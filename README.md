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
##  
### 🔥 Flame Graph – Function-Level Execution Time Distribution

This section presents the analysis of the first trace visualization using **Flame Graph** in Trace Compass. The Flame Graph highlights the relative execution time of user-space functions during the runtime of `dpdk-testpmd` with `net_tap`.

#### 🔍 Key Observations:
- The function `common_fwd_stream_transmit` accounts for a large portion of total execution time, indicating its central role in packet forwarding.
- Significant overhead is also observed in `rte_eth_tx_burst` and memory-related functions such as `rte_pktmbuf_free_seg` and `rte_mempool_put_bulk`.
- Functions prefixed with `rte_mempool_trace_` suggest noticeable time spent managing the local mempool cache.
- In contrast, the receive path (`common_fwd_stream_receive`, `rte_eth_rx_burst`) appears to contribute less overhead than the transmit path.

#### 💡 Conclusion:
The transmit path, especially memory handling and mbuf recycling, constitutes the main performance bottleneck in this trace. Further analysis with the Statistics View will help confirm these findings by measuring function call frequencies and average durations.

## 📊 Analysis with Trace Compass  
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
