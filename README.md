## 📄 DPDK Packet Forwarding and Function Tracing using net\_tap and LTTng

This report documents the successful execution and function-level tracing of a DPDK-based packet forwarding scenario using the `net_tap` PMD, with comprehensive instrumentation and user-space tracing enabled via LTTng.

---

### 🧠 Scenario Overview

We simulate a realistic packet forwarding pipeline using two TAP interfaces and enable full function-level tracing using LTTng. The execution flow consists of:

1. A `.pcap` file (`test_capture.pcap`) containing real mixed traffic (UDP and TCP) is replayed to `tap0`.
2. `dpdk-testpmd` is configured to receive packets from `tap0` and forward them to `tap1` using the `net_tap` PMD.
3. Each port uses **2 queues**:

   * Queue 0: For UDP traffic.
   * Queue 1: For non-UDP traffic (TCP, etc.) — attempted, but rejected by kernel.
4. Flow rules classify traffic by protocol and redirect them to the appropriate queue.
5. **LTTng UST** with **`cyg_profile` instrumentation** traces all user-space function entries/exits.
6. Traces are collected for \~5 seconds and analyzed using **Trace Compass**.

---

### 📦 PCAP File Content Summary

The `test_capture.pcap` file was generated from a real network capture and contains a broad mixture of protocols:

#### 📊 Protocol Breakdown (via `tshark -z io,phs`)

| Protocol   | Frame Count |
| ---------- | ----------- |
| TCP (IPv4) | 14,274      |
| UDP (IPv4) | 3,669       |
| UDP (IPv6) | 1,393       |
| Total UDP  | 5,062       |
| ARP        | 695         |
| IPv6       | 1,657       |
| ICMPv6     | 264         |

> **Note:** Only UDP packets are forwarded. TCP and unmatched traffic are dropped due to kernel flow rule restrictions.

---
## 📘 Part I – UDP-Only Rule Configuration and Execution
### 📘 Flow Rule Summary

UDP traffic is matched and routed to queue 0 on both ports:

```bash
flow create 0 ingress pattern eth / ipv4 / udp / end actions queue index 0 / end
flow create 1 ingress pattern eth / ipv4 / udp / end actions queue index 0 / end
```

⚠️ TCP rules were attempted but rejected by the kernel with `File exists` errors.

---

### ⚙️ Setup Summary

* **DPDK Version**: 23.11
* **OS**: Ubuntu Linux
* **Tracing Tool**: LTTng (user-space tracing with `liblttng-ust-cyg-profile`)
* **Interfaces**: `tap0` (input), `tap1` (output)

---

### ▶️ Step-by-Step Execution

#### 1. Run `testpmd` with net\_tap driver

```bash
sudo -E LD_PRELOAD=liblttng-ust-cyg-profile.so ./build/app/dpdk-testpmd -c 0xf -n 4 \
  --vdev=net_tap0,iface=tap0,queues=2 \
  --vdev=net_tap1,iface=tap1,queues=2 \
  -- \
  --port-topology=chained \
  --nb-cores=3 \
  --rxq=2 --txq=2 \
  --forward-mode=io \
  --interactive
```

#### 2. Create and apply flow rules in `testpmd`

```bash
testpmd> flow create 0 ingress pattern eth / ipv4 / udp / end actions queue index 0 / end
testpmd> flow create 1 ingress pattern eth / ipv4 / udp / end actions queue index 0 / end
testpmd> start
```

#### 3. Start `tcpreplay` to feed traffic

```bash
sudo tcpreplay --intf1=dtap0 --loop=1000 ~/captures/test_capture.pcap
```

---

### 📡 Function Tracing with LTTng (Updated Method)

To trace DPDK function calls accurately, we run LTTng **during** the actual packet forwarding using the following Bash script:

#### 🔧 `trace_udp_only.sh`

```bash
#!/bin/bash

sudo lttng destroy net_tap_rule_udp_iβ 2>/dev/null
sudo lttng create net_tap_rule_udp_iβ

sudo lttng enable-channel --userspace --num-subbuf=4 --subbuf-size=40M channel0
sudo lttng enable-event --channel channel0 --userspace --all

sudo lttng add-context --channel channel0 --userspace \
  --type=vpid --type=vtid --type=procname \
  --type=perf:thread:cpu-cycles \
  --type=perf:thread:instructions

sudo lttng start
sleep 5
sudo lttng stop
sudo lttng destroy
```

* This captures all user-space function calls and essential performance metrics.
* Run the script while traffic is being replayed.
##  📊 Analysis with Trace Compass  
### 🔥 Flame Graph – Function-Level Execution Time Distribution

This section presents the analysis of the first trace visualization using **Flame Graph** in Trace Compass. The Flame Graph highlights the relative execution time of user-space functions during the runtime of `dpdk-testpmd` with `net_tap`.

#### 🔍 Key Observations:
- The function `common_fwd_stream_transmit` accounts for a large portion of total execution time, indicating its central role in packet forwarding.
- Significant overhead is also observed in `rte_eth_tx_burst` and memory-related functions such as `rte_pktmbuf_free_seg` and `rte_mempool_put_bulk`.
- Functions prefixed with `rte_mempool_trace_` suggest noticeable time spent managing the local mempool cache.
- In contrast, the receive path (`common_fwd_stream_receive`, `rte_eth_rx_burst`) appears to contribute less overhead than the transmit path.

#### 💡 Conclusion:
The transmit path, especially memory handling and mbuf recycling, constitutes the main performance bottleneck in this trace. Further analysis with the Statistics View will help confirm these findings by measuring function call frequencies and average durations.

## 
### 🔁 Flame Chart – Multi-Core Packet Reception View

This visualization shows a **Flame Chart** focused on the `pkt_burst_io_forward` function across multiple DPDK worker threads (`dpdk-worker1`, `dpdk-worker2`, and `dpdk-worker3`).

#### 🔍 Key Observations:
- All three worker threads are actively executing `common_fwd_stream_receive` followed by `rte_eth_rx_burst`.
- The consistent pattern across threads indicates a **balanced distribution of RX load**, with no significant idle gaps.
- Each invocation of `rte_eth_rx_burst` is immediately followed by interactions with `rte_ethdev_trace_rx`, suggesting successful and tight RX path instrumentation.
- The hexadecimal label `0x55743cf241f5` represents the actual function address and is repeated, denoting multiple calls to the same function instance (instrumented with `cyg_profile`).
- The close alignment of function blocks suggests low variance in RX handling latency between threads.

#### 💡 Conclusion:
This chart confirms that the `dpdk-testpmd` application evenly distributes the packet reception workload across available threads. The RX path, specifically `rte_eth_rx_burst`, is functioning efficiently and in parallel across cores, which is ideal for performance scalability.

Further insights can be obtained by zooming in on the time axis to calculate microsecond-level latency between function entries.

##  
### 📈 Function Duration Statistics – Execution Time Breakdown

This table presents statistical data on the duration of user-space functions during DPDK execution, as captured by LTTng with `cyg_profile`.

#### 🔍 Key Observations:
- `rte_constant_bswap16` appears at the top with 756 calls and a total execution time of ~524 μs.
- Several functions such as `rte_pktmbuf_headroom`, `rte_mempool_trace_put_bulk`, and `__rte_mbuf_raw_sanity_check` exhibit relatively high average execution times.
- `__rte_trace_point_fp_is_enabled` was called over 324,000 times, indicating a trace-related overhead that may influence performance measurements.
- The `pmd_rx_burst` function was executed over 322,000 times, highlighting its role as a central and frequently executed component in the RX path.

#### 💡 Conclusion:
This statistical view complements the Flame Graph by providing precise metrics for optimization. Functions with high average durations or excessive call counts are ideal candidates for profiling and performance tuning.

##  
### 📉 Function Durations Distribution – Histogram of Execution Time

This chart shows a histogram of function execution durations across all traced events. It helps identify whether most functions execute quickly or if there are outliers with high latency.

#### 🔍 Key Observations:
- The majority of functions executed within the **1–3 µs** range, indicating highly efficient execution in most cases.
- A few functions (e.g., `rte_eth_rx_burst`, `pmd_rx_burst`, `common_fwd_stream_receive`) show higher durations (up to 10 µs), which may be caused by transient delays.
- The `__rte_trace_point_fp_is_enabled` function appears across various durations, revealing some overhead due to tracing itself.

#### 💡 Conclusion:
This view helps detect outliers and variability in function execution time. Although the general performance is tight and fast, a few longer-duration calls may warrant further inspection if they align with critical path functions.

## 
### 🌲 Weighted Tree View – Function Call Tree with Timing Metrics

This view shows a full call tree for a DPDK worker thread (`dpdk-worker3-5026`), with each function's total and self execution time.

#### 🔍 Key Observations:
- The function `common_fwd_stream_receive` dominates with **950 ms total time**, followed by `rte_eth_rx_burst` and `rte_ethdev_trace_rx_burst`.
- The `__rte_trace_point_fp_is_enabled` function appears frequently, reflecting the internal overhead added by LTTng's UST instrumentation.
- Memory allocation routines such as `rte_mempool_get_bulk`, `rte_pktmbuf_alloc`, and related trace functions show up with lower call counts (52 calls) but non-negligible duration.
- All functions are executed within the scope of the top-level function at address `0x55743cf241f5`.

#### 💡 Conclusion:
This tree highlights the RX path (`rte_eth_rx_burst` and its children) as the main execution hotspot. Tracing and memory pool access contribute significantly to the cumulative time. These areas are prime candidates for deeper profiling and possible optimization.

## 
### 🧪 Hardware Counter Analysis – TID 5024 (Single Thread View)

This chart shows performance counters for DPDK thread `TID 5024`, specifically:

- `thread_cpu_cycles` (green)
- `thread_instructions` (purple)
- `thread_cache_misses` (magenta)

#### 🔍 Key Observations:
- Instructions are executed steadily over time, with minimal fluctuation, indicating stable workload execution.
- CPU cycles closely follow instructions, showing a balanced execution pipeline.
- Cache misses are low and stable, implying efficient memory usage and good cache locality.

#### 💡 Conclusion:
TID 5024 exhibits efficient, predictable, and cache-friendly behavior. No signs of performance stalls or memory bottlenecks are detected in this thread.

## 🚦 Overhead Analysis – Top Functions with Highest Impact

This section summarizes the top functions contributing to execution overhead in the DPDK + net_tap + LTTng tracing scenario. The list is sorted by **descending overhead impact**, based on duration, frequency, and trace tree analysis.

| Rank | Function Name                        | Role                                | Overhead Indicators                            | Notes |
|------|--------------------------------------|-------------------------------------|-------------------------------------------------|-------|
| 1    | `common_fwd_stream_receive`          | Main forwarding logic (RX path)     | 🟢 Very high total duration (~950 ms)<br>🟢 Includes all RX/mempool subcalls | Dominant node in flame/tree views |
| 2    | `rte_eth_rx_burst`                   | Burst receive from NIC              | 🟢 High frequency<br>🟢 Significant duration     | Core of packet processing loop |
| 3    | `rte_ethdev_trace_rx_burst`          | Tracing wrapper for RX              | 🟢 Long cumulative duration<br>🟢 Appears under every RX | Tracing-induced overhead |
| 4    | `__rte_trace_point_fp_is_enabled`    | LTTng instrumentation logic         | 🔴 Over 324,000 calls<br>🟢 Appears in many stack layers | Significant UST overhead |
| 5    | `rte_mempool_get_bulk`               | Bulk buffer allocation              | 🟢 Long self time<br>🟢 Appears frequently       | Memory pool performance-sensitive |
| 6    | `rte_pktmbuf_alloc` / `rte_mbuf_raw_alloc` | Buffer allocation from mempool | 🟡 Moderate duration<br>🟢 Frequent in RX path   | Allocation latency bottleneck |
| 7    | `pmd_rx_burst`                       | PMD-level RX handler                | 🟢 High frequency<br>🟡 Moderate duration        | Appears repeatedly in RX path |

---

### 🧠 Conclusion:

- **RX path dominates performance cost**, especially due to buffer handling and tracing overhead.
- **LTTng’s instrumentation functions** (especially `__rte_trace_point_fp_is_enabled`) add measurable tracing cost and may be optimized in production builds.
- **Memory allocation** and `mempool` access are critical performance points.

## 🔍 Function Analysis – `common_fwd_stream_receive`

### 📁 Location

This function is defined in the following file:

```
dpdk-23.11/app/test-pmd/testpmd.h
```

To locate it quickly, run:

```bash
cd ~/dpdk-23.11
grep -rn "common_fwd_stream_receive" app/test-pmd/
nano app/test-pmd/testpmd.h
```

---

### 📄 Function Definition (with inline comments)

```c
// Inline function to receive a burst of packets from a specific RX port/queue.
static inline uint16_t
common_fwd_stream_receive(struct fwd_stream *fs, struct rte_mbuf **burst,
                          unsigned int nb_pkts)
{
    uint16_t nb_rx;

    // 🔁 Try to receive up to nb_pkts from the RX queue of the given stream
    nb_rx = rte_eth_rx_burst(fs->rx_port, fs->rx_queue, burst, nb_pkts);

    // 📊 Optionally update per-burst statistics if enabled
    if (record_burst_stats)
        fs->rx_burst_stats.pkt_burst_spread[nb_rx]++;

    // ➕ Update total RX packet count
    fs->rx_packets += nb_rx;

    // 📤 Return the number of received packets
    return nb_rx;
}
```

---

### 🔬 Performance & Overhead Analysis

| Factor | Explanation |
|--------|-------------|
| 🔁 **High Call Frequency** | This function is called once per RX burst inside the main loop. With high packet rates, it is executed millions of times. |
| 📦 **Relies on `rte_eth_rx_burst`** | The heavy lifting is done by the DPDK API `rte_eth_rx_burst`, which interacts with the actual driver (e.g., `tap_recv_pkts`). |
| 🧠 **Tracing Overhead** | When LTTng tracing is active with `cyg_profile`, each function call logs entry/exit, introducing measurable runtime cost. |
| 📊 **Optional Statistics Update** | If `record_burst_stats` is enabled, this introduces memory access and cache pressure. |
| 🔥 **Hotspot in Tracing** | Because of its central role and frequency, it appears as one of the top contributors in flame graphs and function duration views in Trace Compass. |

---

### 🧠 Summary

Although `common_fwd_stream_receive` is a simple and inline wrapper, it becomes a top overhead source due to:

- Very frequent execution inside the packet processing loop
- Indirect delegation to lower-level RX functions
- Tracing activity (function instrumentation via LTTng)

This function consistently ranks high in Trace Compass overhead analysis and should be considered a critical point in performance studies.

## 🔍 Function Analysis – `rte_eth_rx_burst`

### 📁 How to Locate the Function

To find the implementation of `rte_eth_rx_burst`, follow these steps:

1. Go to the ethdev library directory:
   ```bash
   cd ~/dpdk-23.11/lib/ethdev
   ```

2. Search for the function definition using `grep`:
   ```bash
   grep -rn "rte_eth_rx_burst" rte_ethdev.h
   ```

3. You will find the function defined at or near line 6045 in `rte_ethdev.h`:
   ```
   rte_ethdev.h:6045:rte_eth_rx_burst(uint16_t port_id, uint16_t queue_id, ...
   ```

4. Open the file at that line to view the full function:
   ```bash
   nano +6045 rte_ethdev.h
   ```

---

### 📄 Full Function Code

```c
static inline uint16_t
rte_eth_rx_burst(uint16_t port_id, uint16_t queue_id,
                 struct rte_mbuf **rx_pkts, const uint16_t nb_pkts)
{
    uint16_t nb_rx;
    struct rte_eth_fp_ops *p;
    void *qd;

    p = &rte_eth_fp_ops[port_id];
    qd = p->rxq.data[queue_id];

    nb_rx = p->rx_pkt_burst(qd, rx_pkts, nb_pkts);

#ifdef RTE_ETHDEV_RXTX_CALLBACKS
    void *cb = rte_atomic_load_explicit(&p->rxq.clbk[queue_id],
                                        rte_memory_order_relaxed);
    if (unlikely(cb != NULL))
        nb_rx = rte_eth_call_rx_callbacks(port_id, queue_id,
                                          rx_pkts, nb_rx, nb_pkts, cb);
#endif

    rte_ethdev_trace_rx_burst(port_id, queue_id, (void **)rx_pkts, nb_rx);
    return nb_rx;
}
```

---

### ⚠️ Why It Has Overhead

| Component | Source of Overhead | Description |
|-----------|---------------------|-------------|
| `p->rx_pkt_burst(...)` | 🔺 **High** | This is a driver function pointer, which calls into the actual PMD (e.g., `tap_recv_pkts`). Most of the processing time is consumed here. |
| Callback logic | 🔸 **Conditional** | If any RX callbacks are registered, additional processing occurs. |
| Trace hook | 🔹 **Low** | Involves user-space trace instrumentation; small but visible in function trace views. |
| Function pointer usage | 🔹 **Moderate** | Indirection adds minor latency due to reduced compiler optimization/inlining. |

---

### 🧠 Summary & Analysis

The `rte_eth_rx_burst` function is a **thin wrapper** that delegates actual packet reception to the underlying driver (PMD). On its own, it doesn’t introduce significant overhead, but since it is executed **frequently** in every RX path, it appears prominently in function-level traces.

Its call to `p->rx_pkt_burst(...)` is where the **real work and cost** occur. In most cases, this delegates to `tap_recv_pkts` for the `net_tap` device, which performs memory allocation and a system call (`read()`), both of which are expensive.

🔎 Therefore, while `rte_eth_rx_burst` itself is lightweight, its high call frequency and delegation to costly driver functions make it **an important transition point** in tracing and overhead analysis.

## 🧩 Final Insight: Root Cause of Overhead – `rx_pkt_burst`

During our analysis, we observed that the **core source of execution overhead** in the RX path is the function pointer:

```c
nb_rx = p->rx_pkt_burst(qd, rx_pkts, nb_pkts);
```

This function pointer is resolved at runtime to the actual driver implementation (e.g., `tap_recv_pkts` for the `net_tap` PMD). Here’s why this call introduces significant performance cost:

### ⚙️ What Happens Under the Hood

1. **Driver-specific packet reception**  
   The function eventually calls into the PMD driver, which performs:
   - `read()` syscall on `/dev/net/tun` or `tap` interface
   - buffer allocation (`rte_pktmbuf_alloc`)
   - packet parsing and copying into mbufs

2. **User-kernel transitions**  
   The read operation causes a context switch between user-space and kernel-space, which is inherently expensive.

3. **High call frequency**  
   Even a lightweight function, when called tens of thousands of times per second, results in visible impact on Flame Graphs and system traces.

---

### 🔎 Conclusion

While `rte_eth_rx_burst()` appears as a lightweight API wrapper, it is a **gateway to a much heavier operation**. The actual cost lies in the function behind `rx_pkt_burst`, typically in PMDs like `tap_recv_pkts`. Thus, most of the observed overhead in function tracing originates from this indirect call.

📌 **Optimization Recommendation:**  
Any attempt to reduce RX path latency should focus on the internals of the `rx_pkt_burst()` implementation — especially syscalls, memory allocation, and batching behavior.

### 🔧 Analysis and Optimization Suggestions for `rx_pkt_burst` Overhead

#### 🧩 Functional Role
The function `rx_pkt_burst` is not a standalone implementation but a function pointer located within the `rte_eth_fp_ops` structure. At runtime, for the `net_tap` driver, this pointer is bound to the function `tap_recv_pkts`, which is the actual implementation responsible for receiving packets via the kernel TAP interface.

```c
.rx_pkt_burst = tap_recv_pkts,
```

This means every call to `rte_eth_rx_burst(...)` eventually triggers:

```text
rte_eth_rx_burst → rx_pkt_burst → tap_recv_pkts → read()
```

The `tap_recv_pkts` function internally relies on the `read()` syscall to retrieve packets from the TAP interface, introducing substantial **overhead due to context switching and kernel-user copy** operations.

#### 📉 Identified Overhead
Based on our function-level tracing using LTTng and Trace Compass, `rx_pkt_burst` emerged as one of the top contributors to overall execution latency. This overhead is directly inherited from `tap_recv_pkts`, making it a primary performance bottleneck in the receive path of the testpmd pipeline.

#### ✅ Optimization Recommendations

To reduce the performance cost of `rx_pkt_burst` (and implicitly `tap_recv_pkts`), we propose the following strategies:

| Optimization | Description | Impact |
|--------------|-------------|--------|
| Replace `net_tap` with `memif` or `af_xdp` | Use high-performance user-space drivers that bypass the kernel and eliminate syscalls like `read()` | Drastically lowers latency and CPU usage |
| Increase `nb_pkt_per_burst` | Set higher burst sizes (e.g., 32 or 64 packets per call) to amortize syscall overhead | Reduces function call frequency |
| Disable `record_burst_stats` | Avoid unnecessary memory writes per RX burst | Minimizes additional overhead in `common_fwd_stream_receive` |
| Use `ring` PMD for local communication | Switch to ring-based PMDs for test environments where TAP is not essential | Avoids kernel interaction entirely |

#### 🚀 Conclusion

The `rx_pkt_burst` function is effectively a gateway to the kernel's TAP subsystem via `tap_recv_pkts`. This tight coupling to the `read()` syscall explains the high overhead observed during function tracing. Replacing `net_tap` with a user-space, zero-copy alternative or tuning burst parameters can significantly improve performance in DPDK-based pipelines.

### 🔍 Analysis of TAP Receive Path Overhead in DPDK

#### 📌 Function: `pmd_rx_burst`

This function is the low-level receive routine of the `net_tap` PMD driver, which is invoked indirectly through the DPDK forwarding pipeline. Here's the implementation:

```c
pmd_rx_burst(void *queue, struct rte_mbuf **bufs, uint16_t nb_pkts)
{
    struct rx_queue *rxq = queue;
    struct pmd_process_private *process_private;
    uint16_t num_rx;
    unsigned long num_rx_bytes = 0;
    uint32_t trigger = tap_trigger;

    if (trigger == rxq->trigger_seen)
        return 0;

    process_private = rte_eth_devices[rxq->in_port].process_private;
    for (num_rx = 0; num_rx < nb_pkts; ) {
        ...
        len = readv(process_private->rxq_fds[rxq->queue_id],
                    *rxq->iovecs,
                    1 + (rxq->rxmode->offloads & RTE_ETH_RX_OFFLOAD_SCATTER ?
                         rxq->nb_rx_desc : 1));
        ...
        bufs[num_rx++] = mbuf;
        num_rx_bytes += mbuf->pkt_len;
    }

    rxq->stats.ipackets += num_rx;
    rxq->stats.ibytes += num_rx_bytes;

    if (trigger && num_rx < nb_pkts)
        rxq->trigger_seen = trigger;

    return num_rx;
}
```

#### ⚙️ Overhead Analysis

The majority of the overhead in `pmd_rx_burst` comes from:

- **System Call `readv()`**: Reading from the TAP interface is a blocking or semi-blocking syscall, which introduces context switch overhead and latency.
- **Memory Allocation (`rte_pktmbuf_alloc`)**: Frequent dynamic allocation of mbufs inside the inner loop can degrade performance, especially when burst size is high.
- **Pointer Chaining and Segment Management**: When dealing with scatter-gather or fragmented packets, the linked-list structure of segments increases processing time.

---

#### 📈 Overhead Path



   ###### A[common_fwd_stream_receive] --> B[rte_eth_rx_burst]
   ###### B --> C[rx_pkt_burst (function pointer)]
   ###### C --> D[pmd_rx_burst]
   ###### D --> E[readv() syscall]


## 📘 Part II – TCP-Only Rule Configuration and Execution

In this second part of the report, we retain the **same test environment and execution pipeline** as in Part I (which focused on forwarding UDP packets), but we modify the **flow classification rules** to focus **exclusively on TCP traffic**.

> The objective is to analyze the performance and overhead characteristics when the DPDK testpmd application processes only TCP packets — using the same net_tap interface, multi-queue setup, and LTTng tracing infrastructure.

---

### 🔄 What’s Changed?

- The `.pcap` replay file remains the same and still contains mixed traffic (TCP, UDP, ARP, ICMPv6, etc.)
- The forwarding logic is unchanged: packets arrive at `tap0` and are forwarded to `tap1` via `dpdk-testpmd` using the `net_tap` PMD.
- **Only the Flow Rules are updated to match TCP traffic.**
- All other aspects — queue configuration, core binding, tracing setup — remain the same as in Part I.

---

### 📜 Updated Flow Rules: TCP-Only Forwarding

We define flow rules on both ports (port 0 = `tap0`, port 1 = `tap1`) to **match only IPv4 + TCP** packets and forward them to **queue 0**:

```bash
flow create 0 ingress pattern eth / ipv4 / tcp / end actions queue index 0 / end
flow create 1 ingress pattern eth / ipv4 / tcp / end actions queue index 0 / end
```

#### 🧠 Rule Explanation:

Each `flow create` command consists of two parts:

1. **Pattern**:
   - `eth / ipv4 / tcp / end`  
     → This matches packets with:
     - Ethernet header
     - Followed by an IPv4 header
     - Containing the TCP protocol

2. **Actions**:
   - `queue index 0 / end`  
     → This tells DPDK to enqueue the matched packets to queue 0 on the specified port.

✅ As a result, **only TCP packets** will be processed and forwarded by `testpmd`.

❌ All other packets (UDP, ARP, ICMP, etc.) are not matched and will be dropped silently.

---

### ⚙️ Scenario Execution (Recap)

Although the rule has changed, the following remains the same:

- `testpmd` is launched with `net_tap` devices for `tap0` and `tap1`
- Two queues are used per port (but only queue 0 will be active here)
- Traffic is fed using `tcpreplay`
- All function calls are traced with `LTTng` using `cyg_profile`

---

### ▶️ Step-by-Step Commands

1. **Run testpmd with tracing and TAP interfaces:**

```bash
sudo -E LD_PRELOAD=liblttng-ust-cyg-profile.so ./build/app/dpdk-testpmd -c 0xf -n 4 \
  --vdev=net_tap0,iface=tap0,queues=2 \
  --vdev=net_tap1,iface=tap1,queues=2 \
  -- \
  --port-topology=chained \
  --nb-cores=3 \
  --rxq=2 --txq=2 \
  --forward-mode=io \
  --interactive
```

2. **Inside the testpmd CLI: apply TCP-only rules:**

```bash
testpmd> flow create 0 ingress pattern eth / ipv4 / tcp / end actions queue index 0 / end
testpmd> flow create 1 ingress pattern eth / ipv4 / tcp / end actions queue index 0 / end
testpmd> start
```

3. **Replay the PCAP traffic into tap0:**

```bash
sudo tcpreplay --intf1=dtap0 --loop=1000 ~/captures/test_capture.pcap
```

---

🔁 This completes the TCP-only version of the forwarding scenario. The packet processing path is now restricted to **TCP over IPv4**, and tracing data will reflect the behavior of `testpmd` under these specific conditions.

➡️ In the next section, we will analyze the LTTng trace results, Flame Graphs, and function-level statistics for this TCP-focused scenario, and compare them with the previous UDP-based setup.

##  📊 Analysis with Trace Compass 
## 🔥 Flame Graph – Function-Level Execution Time Distribution (TCP-Only)

This Flame Graph shows the relative execution time of functions during TCP-only packet forwarding with `dpdk-testpmd` using `net_tap` and traced via LTTng `cyg_profile`. Each horizontal bar represents the self-time of a function, while its vertical stack reveals the call hierarchy.

### 🔍 Key Observations:

- **`pkt_burst_io_forward`** sits at the top of the graph, orchestrating the overall packet forwarding logic.
- **`common_fwd_stream_receive`** and **`common_fwd_stream_transmit`** are both prominently visible, showing that the receive and transmit paths are balanced in processing.
- The **receive path**, specifically:
  - `rte_eth_rx_burst`
  - `pmd_rx_burst`
  - `rte_pktmbuf_alloc`
  - `rte_mbuf_raw_alloc`
  - `rte_mempool_get_bulk`  
  is deeply stacked, indicating that memory allocation and PMD receive functions dominate the RX-side workload.

- The **transmit path**, including:
  - `rte_eth_tx_burst`
  - `pmd_tx_burst`
  - `rte_pktmbuf_free`, `rte_pktmbuf_free_seg`
  - `rte_mempool_put_bulk`  
  appears immediately after `common_fwd_stream_transmit` and contributes substantial overhead as well.

- **TCP-specific behavior**:  
  No explicit TCP stack-level processing is visible (since DPDK operates at L2–L4 forwarding), but the heavier weight in both memory allocation and deallocation functions may reflect larger packet sizes or more stateful packet flows typical of TCP sessions.

- **No idle gaps**:  
  The stack depth and continuity suggest a tight processing loop, with minimal idle time between receive and transmit stages.

---

### 💡 Conclusion:

Compared to the previous UDP-only Flame Graph, the TCP-only trace exhibits:

- **Longer execution time** in allocation and deallocation routines (e.g., `rte_pktmbuf_alloc`, `rte_mempool_get_bulk`)
- **More balanced overhead** between RX and TX paths
- Similar control structure (e.g., `pkt_burst_io_forward`, `common_fwd_stream_*`)
- Potential increase in per-packet processing cost due to larger TCP headers and more complex mbuf handling.

This Flame Graph confirms that under TCP-only forwarding, memory operations and PMD driver interactions are the main contributors to runtime overhead. Further insights will be derived in the next sections using function duration statistics, counters, and weighted tree views.

## 🔁 Flame Chart – Multi-Core Packet Reception View (TCP-Only)

This Flame Chart presents a timeline-based view of function execution across multiple DPDK worker threads during TCP-only forwarding. Each row corresponds to a thread (`dpdk-worker1`, `dpdk-worker2`, `dpdk-worker3`), and function calls are shown with their durations across the time axis.

### 🔍 Key Observations:

- All three worker threads (`dpdk-worker1`, `dpdk-worker2`, and `dpdk-worker3`) actively execute:
  - `pkt_burst_io_forward`
  - `common_fwd_stream_receive`
  - `rte_eth_rx_burst`
  - `pmd_rx_burst` or related PMD RX symbols (`0x562ae08ee1f4`)

- The **execution pattern is consistent** across cores, with each thread repeatedly processing the RX path in a loop — suggesting a well-balanced load.

- The presence of **uniform function blocks** with little variation in length indicates **low latency variance** and predictable execution cycles for each burst of TCP packets.

- The symbol `0x562ae08ee1f4` appears frequently just after `rte_eth_rx_burst`. This corresponds to the actual PMD driver function for `net_tap`, i.e., `tap_recv_pkts`, and confirms successful tracing of PMD-level processing even for TCP packets.

- Each call to `rte_eth_rx_burst` is immediately followed by its deeper stack components (memory allocation, mempool interaction), even though they’re not expanded in this chart.

---

### 💡 Conclusion:

The Flame Chart confirms that **TCP traffic is evenly distributed and processed across all worker threads**, with no observable load imbalance or idle periods. The RX loop (`common_fwd_stream_receive → rte_eth_rx_burst → tap_recv_pkts`) is consistently repeated across all threads, ensuring maximum CPU utilization.

This pattern is similar to the UDP-only scenario, but block durations suggest that **per-burst processing time for TCP is slightly higher**, likely due to packet size and mempool allocation cost.

In the next section, we will examine **statistical duration metrics** for functions to quantify these performance characteristics.

## 📊 Function Duration Statistics – Execution Time Breakdown (TCP-Only)

This table summarizes the function-level execution durations as measured by LTTng with `cyg_profile` during the TCP-only scenario. It includes the minimum, maximum, and average execution times, standard deviation, number of invocations (Count), and total accumulated time (Total) for each function.

### 🔍 Key Observations:

- **Top function by call count**:  
  - The function at address `0x562ae173d9b3` was invoked **5.48 million times** and consumed a total of **23.4 seconds**, averaging **4.3 μs** per call.  
  - This is likely a core RX path function (possibly inlined `rte_eth_rx_burst` or similar).

- **High total duration functions**:
  - `__rte_trace_point_fp_is_enabled` → 443,503 calls → **316 ms total**  
    → This is a tracepoint instrumentation overhead introduced by LTTng.
  - `0x562ae08ef2d3` → 469,990 calls → **360 ms total**  
    → Likely `tap_recv_pkts` or its wrapper, showing it’s a dominant runtime cost.

- **pmd_rx_burst** → 44,695 calls, avg. **724 ns**, total **319 ms**  
  → Consistently contributes significant RX cost.

- **Memory allocation overhead**:
  - Functions like `rte_pktmbuf_headroom`, `rte_pktmbuf_reset_headroom`, `rte_mbuf_raw_alloc`, and `rte_mempool_get_bulk` appear prominently with average durations in the range of **0.6–0.8 μs**.
  - These functions account for the bulk of per-packet processing cost during TCP handling.

- **Trace overhead functions**:
  - `__rte_trace_point_fp_is_enabled`, `rte_mempool_trace_default_cache`, and similar instrumentation helpers are clearly visible and contribute measurable runtime impact.

---

### 💡 Conclusion:

This statistical view confirms the findings from the Flame Graph and Flame Chart:

- **The receive path remains the main performance hotspot**, with `tap_recv_pkts` and `pmd_rx_burst` contributing significantly to overall latency.
- **Memory operations** (allocation, reset, headroom calculation) account for hundreds of microseconds of cumulative time, especially due to high invocation counts.
- **Tracing itself adds overhead** — visible via the high call frequency of `__rte_trace_point_fp_is_enabled`.

Compared to the UDP-only scenario, the TCP case shows **longer average function durations** and **larger total time per function**, highlighting that TCP packet processing, even without kernel stack involvement, leads to greater user-space processing overhead in DPDK.

➡️ Next, we’ll examine the Weighted Tree View to understand the hierarchical structure of function calls and determine the dominant paths in the TCP-only execution trace.

## 🌲 Weighted Tree View – Function Call Tree with Timing Metrics (TCP-Only)

This view shows the full hierarchical structure of function calls during the TCP-only scenario on `dpdk-worker1`. Each branch in the tree represents a nested call, with metrics for total duration, self time (exclusive), and number of calls.

### 🔍 Key Observations:

- **Top-Level Function**:  
  - `pkt_burst_io_forward` is the root of the forwarding loop, consuming **2.6 s** total time with **325.8k calls**.
  - Its child, `common_fwd_stream_receive`, accounts for **2.18 s**, revealing RX as the main execution path.

- **Receive Path Breakdown**:
  - `rte_eth_rx_burst`: 1.72 s total, 325.8k calls
  - `0x562ae08ee1f4`: 697 ms total (likely `tap_recv_pkts`)
  - `__rte_trace_point_fp_is_enabled`: 238 ms overhead (tracing cost)
  - `pmd_rx_burst`: 274 ms (self time 265 ms → very low nesting)

- **Memory Allocation Chain**:
  - `rte_pktmbuf_alloc` → `rte_mbuf_raw_alloc` → `rte_mempool_get_bulk`  
    These functions combined account for several hundred microseconds per burst.
  - `rte_mempool_trace_generic_get`, `rte_trace_point_fp_is_enabled`, and other trace helpers appear deeply nested under memory pools, showing cumulative instrumentation cost.

- **Transmit Path**:
  - `common_fwd_stream_transmit` is lightweight: only 10 ms total time across all calls.

- **Function Call Pie Chart** (right side of second image):  
  Confirms that the **bulk of processing is concentrated in `pmd_rx_burst` and `tap_recv_pkts`**, matching findings from Flame Graph and Stats.

---

### 💡 Conclusion:

The weighted tree confirms that the **receive path dominates total execution time** in the TCP-only scenario. Memory management (`mbuf` and `mempool`) and PMD-level functions (`tap_recv_pkts`, `pmd_rx_burst`) are the primary performance hotspots.

The self time of `pmd_rx_burst` (265 ms) is particularly high and deserves deeper optimization or batching.

Instrumentation (via LTTng trace points) introduces measurable cost — e.g., `__rte_trace_point_fp_is_enabled` appears at multiple levels, adding up to hundreds of milliseconds.

➡️ Overall, this hierarchical view helps identify **which sub-paths (e.g., mempool, PMD, tracing)** contribute most to latency and highlights **optimization targets** for reducing RX overhead in TCP forwarding with DPDK.

## 📉 Function Durations Distribution – Histogram of Execution Time (TCP-Only)

This view presents a histogram showing how long each function took to execute during the TCP-only scenario. The x-axis shows duration (in microseconds), and the y-axis shows the number of function calls falling into each duration bin.

### 🔍 Key Observations:

- **Most function calls** fall within the **0.5 to 2 μs range**, with a clear cluster around **600–800 ns**.
  - This includes trace functions like `__rte_trace_point_fp_is_enabled` and PMD receive wrappers like `pmd_rx_burst`.

- There are **occasional spikes in longer durations**, especially:
  - `0x562ae08ee1f4` (likely `tap_recv_pkts`) → ranges between **1.8–2.5 μs**
  - `rte_eth_rx_burst` → hits **4.4–4.5 μs** in some cases

- **No extreme outliers** (e.g., >10 μs), indicating **tight control over per-function latency** even under TCP packet load.

- The histogram confirms that while **most function executions are short and efficient**, **a few core functions (RX, PMD, tap)** contribute longer runtimes due to memory operations and system interactions.

---

### 💡 Conclusion:

The distribution confirms that **most user-space functions in the DPDK TCP-only pipeline execute quickly**, but **receive path components show variability**, especially in `rte_eth_rx_burst` and its PMD backend (`tap_recv_pkts`).

This histogram complements the flame/tree analyses by showing:
- Execution latency remains consistent for most helpers and instrumentation
- **Heavier operations like memory allocation and syscall-involved reception stand out clearly**

➡️ Together, this view completes the performance profile of TCP-only forwarding in DPDK.

## 🧪 Hardware Counter Analysis – TID 4609 (Single Thread View, TCP-Only)

This chart shows low-level hardware performance counters for DPDK thread **TID 4609** during the TCP-only testpmd execution. The data includes:

- 🔴 `thread_cpu_cycles` (red) – Total CPU cycles used
- 🟢 `thread_instructions` (green) – Number of instructions executed
- 🔵 `thread_cache_misses` (blue) – L3 cache misses

### 🔍 Key Observations:

- Both **CPU cycles** and **instructions** stay relatively stable over time with only minor variance, indicating a **regular and predictable workload**.
  
- **Periodic vertical drops** in both red (CPU cycles) and green (instructions) lines suggest **short periods of inactivity or stalls** — possibly due to memory access delays or syscall wait times (e.g., `read()` on TAP).

- The **cache misses** (blue) remain nearly constant and **close to zero** throughout the execution. This is a **very good indicator of efficient cache usage** and locality.

- The tight correlation between CPU cycles and instructions indicates **a balanced pipeline** — no sign of major bottlenecks like stalls, mispredictions, or excessive branching.

---

### 💡 Conclusion:

TID 4609 performs **very efficiently**, with:

- Stable execution behavior
- Low and consistent cache misses
- Tight alignment between instructions and CPU cycles

The small periodic dips may represent points where the thread waits for data (e.g., waiting on packet input from TAP). Still, overall, this thread shows **excellent low-level performance** for DPDK TCP forwarding under user-space tracing.

This analysis confirms the system is **not CPU-bound** and tracing overheads are **not causing performance collapse**. The thread-level view provides strong evidence that the bottleneck lies in syscall-bound sections (e.g., `tap_recv_pkts`) and not CPU instruction throughput.

## 🚦 Overhead Analysis – Top Functions with Highest Impact (TCP-Only)

This section summarizes the top functions contributing to execution overhead in the TCP-only DPDK + net_tap + LTTng tracing scenario. The ranking is based on a combination of duration, call frequency, and depth in the call stack.

| Rank | Function Name                    | Role                              | Overhead Indicators                                           | Notes                                           |
|------|----------------------------------|-----------------------------------|---------------------------------------------------------------|-------------------------------------------------|
| 1    | `rte_eth_rx_burst`               | Receive burst API                 | 🟢 High duration<br>🟢 Core of RX path                         | Delegates to PMD, appears in all RX stacks     |
| 2    | `0x562ae08ee1f4`                 | PMD backend (tap_recv_pkts)       | 🟢 Heavy processing<br>🟢 Syscall-based (read)<br>🔺 Inlined   | Actual RX cost from TAP interface              |
| 3    | `pmd_rx_burst`                   | PMD-level RX wrapper              | 🟢 High self time<br>🟡 Moderate total time                    | Repeats in all RX bursts                       |
| 4    | `__rte_trace_point_fp_is_enabled`| LTTng tracepoint instrumentation | 🔴 Extremely frequent (443k calls)<br>🟡 Non-trivial time      | Adds measurable tracing overhead               |
| 5    | `rte_pktmbuf_alloc`              | Allocate packet buffer            | 🟡 Moderate time<br>🟢 Memory-sensitive                        | Used in every packet path                      |
| 6    | `rte_mempool_get_bulk`           | Bulk buffer fetch from pool       | 🟡 High total time<br>🟡 Appears in mempool trees              | Performance sensitive in burst RX              |
| 7    | `rte_mbuf_raw_alloc`             | Raw buffer allocator              | 🟡 Deep in path<br>🟡 Per-packet allocator                     | Alloc latency bottleneck                       |
| 8    | `rte_pktmbuf_reset_headroom`     | Reset mbuf headroom               | 🟡 Frequent<br>🟡 Memory operation                             | Memory overhead (low but cumulative)           |
| 9    | `rte_mempool_trace_generic_get`  | Mempool tracing helper            | 🔴 Appears repeatedly<br>🔴 Trace-only cost                    | No functional impact, pure instrumentation      |
| 10   | `common_fwd_stream_receive`      | RX wrapper in testpmd            | 🟡 Lightweight wrapper<br>🟡 Very high frequency               | Amplifies indirect overheads from sub-calls    |

---

### 💡 Summary:

- The **top 3 contributors** are firmly in the **receive path**: `rte_eth_rx_burst`, `tap_recv_pkts`, and `pmd_rx_burst`
- **LTTng instrumentation**, especially `__rte_trace_point_fp_is_enabled`, appears in many layers and introduces non-negligible overhead
- **Memory allocation functions** (pktmbuf, mempool) add latency due to frequent usage in the packet loop
- Even simple wrappers like `common_fwd_stream_receive` become relevant due to **high call frequency**

🧠 Recommendation:  
To reduce overhead in TCP forwarding:
- Investigate alternatives to `net_tap` (e.g., `memif` or `af_xdp`)  
- Batch packet reception (`nb_pkt_per_burst`) to amortize syscall cost  
- Minimize tracing in production runs or sample selectively

## 🔁 Comparative Overhead Analysis – UDP vs TCP

This section compares the top performance overhead sources observed in the two execution scenarios: **UDP-only** and **TCP-only** forwarding using DPDK + net_tap + LTTng.

| Aspect                        | UDP-Only Scenario                             | TCP-Only Scenario                              |
|------------------------------|-----------------------------------------------|------------------------------------------------|
| 🥇 Top Function              | `common_fwd_stream_receive` (lightweight loop)| `rte_eth_rx_burst` (driver interaction point)  |
| 🥈 Second Function           | `rte_eth_rx_burst`                             | `0x562ae08ee1f4` → PMD backend (`tap_recv_pkts`)|
| 🥉 Third Function            | `rte_ethdev_trace_rx_burst` (trace wrapper)   | `pmd_rx_burst` (driver wrapper)                |
| 🔍 Tracing Overhead          | High – seen in upper levels                   | Moderate – still significant, but deeper       |
| 📦 Memory Allocation Impact  | Moderate – mostly visible in `rte_pktmbuf_free`| High – heavy usage of `rte_pktmbuf_alloc`, `mempool`|
| 🧠 syscall overhead          | None (UDP rules matched → packets forwarded)  | Present – `read()` in `tap_recv_pkts` dominates|
| 📊 Execution Pattern         | Uniform and fast                              | Slightly variable with syscall delays          |
| 📉 Cache Behavior            | Minimal misses (flat curves)                  | Still minimal, though with periodic stalls     |
| ⚠️ Bottleneck Depth          | Shallow – mostly wrappers                     | Deep – delegated to PMD and memory subsystems  |
| 🎯 Optimization Target       | Loop efficiency and tracing config            | TAP interaction and syscall amortization       |

---

### 💡 Insights:

- In **UDP-only**, overhead is concentrated in **top-level testpmd logic and instrumentation** because the path is short and efficient.
- In **TCP-only**, overhead shifts deeper into the stack, due to:
  - Memory allocations (`rte_mbuf_raw_alloc`, `mempool`)
  - Kernel interaction via `read()` in `tap_recv_pkts`

This confirms that **TCP handling in user-space DPDK with TAP introduces significantly more processing cost**, both due to system-level interaction and per-packet memory overhead.

---

### ✅ Final Recommendation:

| Area                | Optimization Suggestion                               |
|---------------------|--------------------------------------------------------|
| Syscall overhead     | Replace `net_tap` with `memif` or `af_xdp` for user-space RX |
| Memory allocation    | Tune `mbuf` pool sizes, batch allocations, reduce resets      |
| Tracing impact       | Use selective LTTng UST probes or disable tracing in prod     |
| Flow rule strategy   | Avoid rules that lead to unforwarded traffic (e.g., kernel rejection of TCP flows) |

Together, these improvements can significantly reduce execution time and improve forwarding throughput for both UDP and TCP in DPDK.
