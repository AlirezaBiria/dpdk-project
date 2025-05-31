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
