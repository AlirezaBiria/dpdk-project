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
