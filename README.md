# DPDK Packet Forwarding and LTTng Tracing Using net\_tap PMD

## Overview

This report documents the successful execution and tracing of a DPDK-based packet forwarding pipeline using the `net_tap` Poll Mode Driver (PMD). The setup involves sending packets from a pcap file into a DPDK testpmd application via a TAP interface, forwarding them internally within DPDK, and finally capturing the forwarded packets on another TAP interface. System call tracing was performed using LTTng to monitor kernel-level activity during this process.

---

## System Configuration

* **DPDK version:** 23.11
* **Operating System:** Ubuntu Linux
* **Tracing Tool:** LTTng (kernel syscall tracing)
* **Interfaces Used:** `tap0` (input) and `tap1` (output)

---

## Step-by-Step Execution

### 1. Packet Preparation

A valid ICMP packet was constructed and saved into a `pcap` file using Scapy:

```python
from scapy.all import Ether, IP, ICMP, wrpcap
pkt = Ether(dst="ff:ff:ff:ff:ff:ff") / IP(src="10.0.0.2", dst="10.0.0.1") / ICMP()
wrpcap("input.pcap", [pkt])
```

### 2. Starting DPDK testpmd with TAP Interfaces

```bash
cd ~/dpdk-23.11

sudo ./build/app/dpdk-testpmd -c 0xf -n 4 \
  --vdev=net_tap0,iface=tap0 \
  --vdev=net_tap1,iface=tap1 \
  -- \
  --port-topology=chained \
  --forward-mode=io \
  --auto-start
```

#### Output Summary:

```
Logical Core 1 (socket 0) forwards packets on 2 streams:
  RX P=0/Q=0 (socket 0) -> TX P=1/Q=0 (socket 0)
  RX P=1/Q=0 (socket 0) -> TX P=0/Q=0 (socket 0)

Forward statistics:
Port 0: RX=22, TX=30
Port 1: RX=30, TX=22
Total RX=52, TX=52
```

---

### 3. LTTng Trace Activation

```bash
sudo lttng destroy dpdk-final 2>/dev/null
sudo lttng create dpdk-final
sudo lttng enable-event --kernel --syscall --all
sudo lttng start
```

---

### 4. Traffic Injection and Capture

#### Run tcpdump to capture output on tap1:

```bash
sudo tcpdump -i tap1 -w pcapout.pcap
```

*(run in background and stop with Ctrl+C after replay)*

#### Replay pcap packet on tap0:

```bash
sudo tcpreplay -i tap0 input.pcap
```

Result:

```
1 packet sent successfully on tap0
3 packets captured on tap1
```

---

### 5. Finalize LTTng Trace

```bash
sudo lttng stop
sudo lttng destroy
```

### 6. Trace Analysis

```bash
sudo babeltrace /root/lttng-traces/dpdk-final-* | wc -l
```

Result:

```
16923505 system call events captured
```

---

## Conclusion

The experiment successfully demonstrated packet forwarding using DPDK's `net_tap` PMD between two TAP interfaces and traced the corresponding system call activity using LTTng. The packet flow was verified using `tcpdump`, and over 16 million syscall events were recorded, confirming the system's runtime behavior.

This setup provides a strong foundation for further kernel-level analysis, visualization in Trace Compass, or latency profiling.
