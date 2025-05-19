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

# 🧪 DPDK Packet Forwarding using `net_tap` PMD and Traffic Capture with `tshark`

## ✅ Overview

This report documents the successful setup, execution, and observation of a DPDK-based packet forwarding pipeline using the `net_tap` PMD. The test includes injecting a packet via `tap0`, forwarding it through `testpmd`, and capturing the result on `tap1` using `tshark`.

---

## ⚙️ System Configuration

- **DPDK Version:** 23.11  
- **Operating System:** Ubuntu Linux  
- **Tools Used:**  
  - `Scapy` (packet generation)  
  - `tcpreplay` (packet replay)  
  - `testpmd` (DPDK application)  
  - `tshark` (traffic capture)  
- **Interfaces:**  
  - `tap0` – input  
  - `tap1` – output  

---

## 🔧 Step-by-Step Execution

### 1. Create an ICMP Packet with Scapy

```python
# File: create_pcap.py
from scapy.all import Ether, IP, ICMP, wrpcap
pkt = Ether(dst="ff:ff:ff:ff:ff:ff") / IP(src="10.0.0.2", dst="10.0.0.1") / ICMP()
wrpcap("input.pcap", [pkt])
```

Then run:

```bash
python3 create_pcap.py
```

---

### 2. Launch DPDK `testpmd` with TAP Interfaces

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

🔎 **Expected Output:**

```
Logical Core 1 (socket 0) forwards packets on 2 streams:
  RX P=0 → TX P=1
  RX P=1 → TX P=0

Forward statistics:
Port 0: RX=28, TX=26
Port 1: RX=26, TX=28
Total RX=54, TX=54
```

> Press `Ctrl+C` when ready to exit testpmd and stop packet forwarding.

---

### 3. Start Capturing Packets with `tshark` on `tap1`

```bash
sudo tshark -i tap1 -w /tmp/tap1_capture.pcapng
```

> Leave this running and proceed to the next step in a new terminal window.

---

### 4. Replay the ICMP Packet via `tap0`

```bash
sudo tcpreplay -i tap0 input.pcap
```

🔎 **Output:**

```
Warning: flow_decode: packet 1 needs at least 62 bytes for ICMP header but only 42 available
Actual: 1 packets (42 bytes) sent in 0.000018 seconds
Rated: 2333333.3 Bps, 18.66 Mbps, 55555.55 pps
```

Now stop `tshark` by pressing `Ctrl+C`.

---

### 5. Inspect the Capture with `tshark`

```bash
sudo tshark -r /tmp/tap1_capture.pcapng
```

🔍 **Output:**

```
Running as user "root" and group "root". This could be dangerous.
    1 0.000000000     10.0.0.2 → 10.0.0.1     ICMP 42 Echo (ping) request  id=0x0000, seq=0/0, ttl=64
    2 44.111859034 fe80::2c29:1dff:fe89:14cc → ff02::2      ICMPv6 70 Router Solicitation ...
    3 52.720576332 fe80::1818:8cff:fe18:e8eb → ff02::fb     MDNS 203 Standard query ...
    4 53.104617958 fe80::2c29:1dff:fe89:14cc → ff02::fb     MDNS 203 Standard query ...
    5 54.359876773 fe80::1818:8cff:fe18:e8eb → ff02::2      ICMPv6 70 Router Solicitation ...
```

---

## 📁 Output Files

| File Path                     | Description                            |
|------------------------------|----------------------------------------|
| `input.pcap`                 | Generated ICMP packet for replay       |
| `/tmp/tap1_capture.pcapng`   | Captured packets on TAP interface      |

---

## ✅ Summary

This experiment confirms that:

- DPDK successfully forwarded packets via the `net_tap` driver.
- `tshark` correctly captured traffic from the `tap1` interface.
- The injected ICMP packet and system-generated ICMPv6/MDNS traffic were observable in the resulting `.pcapng` file.

This setup is ideal for tracing and debugging DPDK pipelines in virtualized environments, using kernel interfaces and software-based NIC emulation.


