# DPDK Packet Forwarding and Function Tracing using net\_tap and LTTng

This report documents the successful execution and function-level tracing of a DPDK-based packet forwarding scenario using the `net_tap` PMD, with comprehensive instrumentation and user-space tracing enabled via LTTng.

---

## 🧠 Scenario Overview

We simulate a real-world packet forwarding pipeline with two TAP interfaces and full function-level tracing using LTTng. The steps include:

1. A `.pcap` file (`test_capture.pcap`) containing real network traffic (both UDP and TCP) is replayed to `tap0`.
2. DPDK `testpmd` application is used to receive and forward traffic from `tap0` to `tap1`, using the `net_tap` virtual device.
3. Each port is configured with **2 queues**:

   * Queue 0: for **UDP traffic**
   * Queue 1: for **non-UDP (e.g., TCP)** traffic (attempted, but kernel rejected TCP rules)
4. Flow rules are created to classify traffic based on protocol and redirect them to the correct queue.
5. LTTng UST with `cyg_profile` is used to trace **all function entries/exits**, along with `vpid`, `vtid`, and `procname` context.
6. Trace is collected for \~5 seconds and stored under a named session for analysis in **Trace Compass**.

---

## 📁 PCAP File Content Summary

The `test_capture.pcap` file was created using a real traffic capture and contains a mixture of protocols, primarily:

### 📊 Protocol Breakdown (from `tshark -z io,phs`)

```
eth                                      frames:20394 bytes:11837933
  arp                                    frames:695 bytes:41704
  ip                                     frames:17960 bytes:11538596
    tcp                                  frames:14274 bytes:9785086
      tls                                frames:5831 bytes:5530869
        tcp.segments                     frames:815 bytes:797405
          tls                            frames:431 bytes:560620
          data                           frames:1 bytes:1314
      _ws.malformed                      frames:40 bytes:38394
      tcp.segments                       frames:34 bytes:44651
      data                               frames:49 bytes:64386
      http                               frames:2 bytes:404
    udp                                  frames:3669 bytes:1752656
      mdns                               frames:1194 bytes:206681
      dhcp                               frames:30 bytes:10395
      ssdp                               frames:127 bytes:29589
      nbns                               frames:264 bytes:24792
      llmnr                              frames:316 bytes:20522
      data                               frames:1498 bytes:1417302
      dns                                frames:143 bytes:17723
      dcp-etsi                           frames:1 bytes:1292
      adwin_config                       frames:3 bytes:334
      db-lsp-disc                        frames:69 bytes:19302
      nbdgm                              frames:11 bytes:2631
        smb                              frames:11 bytes:2631
          mailslot                       frames:11 bytes:2631
            browser                      frames:7 bytes:1639
            data                         frames:4 bytes:992
      mndp                               frames:6 bytes:1138
      steam_ihs_discovery                frames:6 bytes:873
      teredo                             frames:1 bytes:82
        ipv6                             frames:1 bytes:82
    igmp                                 frames:17 bytes:854
  llc                                    frames:82 bytes:5172
    basicxid                             frames:19 bytes:1140
    stp                                  frames:63 bytes:4032
  ipv6                                   frames:1657 bytes:252461
    icmpv6                               frames:264 bytes:23256
    udp                                  frames:1393 bytes:229205
      mdns                               frames:982 bytes:177477
      dhcpv6                             frames:64 bytes:8584
      llmnr                              frames:317 bytes:26911
      ssdp                               frames:11 bytes:1887
      data                               frames:19 bytes:14346
```

### 🔍 Traffic Summary Table

| Protocol       | Frame Count |
| -------------- | ----------- |
| **TCP** (IPv4) | 14,274      |
| **UDP** (IPv4) | 3,669       |
| **UDP** (IPv6) | 1,393       |
| **Total UDP**  | **5,062**   |
| **ARP**        | 695         |
| **IPv6**       | 1,657       |
| **ICMPv6**     | 264         |

**Note**: Only **UDP packets** are processed and forwarded in the final setup. TCP and other protocols are **dropped** due to the lack of applicable flow rules.

---

## 📘 Flow Rule Explanation

The flow rules below direct traffic based on IP protocol type:

```text
flow create 0 ingress pattern eth / ipv4 / udp / end actions queue index 0 / end
```

* Port `0` (tap0)
* Match incoming packets
* Protocol stack: Ethernet → IPv4 → UDP
* Action: send matched packets to **queue 0**

```text
flow create 1 ingress pattern eth / ipv4 / udp / end actions queue index 0 / end
```

* Port `1` (tap1)
* Same logic for reverse direction

🛑 **Important**: Additional rules were attempted for TCP and generic IPv4 traffic but rejected by the kernel:

```text
flow create 0 ingress pattern eth / ipv4 / tcp / end actions queue index 1 / end
flow create 0 ingress pattern eth / ipv4 / end actions queue index 1 / end
```

These were denied with error `File exists`, indicating overlapping rules or limitations in `net_tap` + kernel flower classifier.

🔎 **As a result:**

* Only UDP packets matched and were forwarded via `queue 0`
* All TCP or unmatched traffic was silently **dropped**

---

## ✅ Setup Summary

* **DPDK Version**: 23.11
* **OS**: Ubuntu Linux
* **Tracing Tool**: LTTng (user-space tracing via `liblttng-ust-cyg-profile`)
* **Interfaces**: `tap0` (input), `tap1` (output)
* **Goal**: Forward UDP and other traffic via DPDK and trace function execution using LTTng UST with `cyg_profile` instrumentation.

---

## 📦 Step-by-Step Execution

### 1. **Run `testpmd` with net\_tap driver and 2 queues per port**

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

### 2. **Inside `testpmd`, define flow rules**

```text
testpmd> flow create 0 ingress pattern eth / ipv4 / udp / end actions queue index 0 / end
testpmd> flow create 1 ingress pattern eth / ipv4 / udp / end actions queue index 0 / end
```

### 3. **Start forwarding**

```text
testpmd> start
```

---

### 4. **Create and start LTTng session (with context)**

```bash
sudo lttng destroy tap-trace 2>/dev/null
sudo lttng create tap-trace
sudo lttng enable-channel ust --userspace
sudo lttng enable-event -u "lttng_ust_cyg_profile:*" --channel=ust
sudo lttng add-context -u -t vpid -t vtid -t procname
sudo lttng start
```

### 5. **Replay traffic using tcpreplay**

```bash
sudo tcpreplay --intf1=dtap0 --loop=1000 /home/eagle/captures/test_capture.pcap
```

Let it run for \~5 seconds, then stop it manually.

---

### 6. **Stop and destroy LTTng session**

```bash
sudo lttng stop
sudo lttng destroy
```

### 7. **Trace Output Folder**

```
/root/lttng-traces/tap-trace-20250526-205706/
```

Contains:

* `ust_0`, `ust_1`, `ust_2`, `ust_3` (\~900 MB total)
* `metadata`
* `index/`

These files can be loaded into **Trace Compass** for analysis.

---

## 🔍 Trace Compass Analysis

Open the folder in Trace Compass:

```text
/root/lttng-traces/tap-trace-20250526-205706/
```

Enable and inspect:

* **Flame Graph View** → Identify high-latency functions
* **Control Flow View** → See core/thread mapping of execution
* **Statistics View** → Function execution frequency
* **Call Stack Table** → Nested function calls

---

## 📌 Notes

* `dpdk-testpmd` was compiled with `-finstrument-functions` and linked to `liblttng-ust-cyg-profile`
* The `meson.build` in `app/` was modified to include:

```meson
default_ldflags = ['-llttng-ust-cyg-profile']
```

---

## ✅ Outcome

* Successful packet forwarding via DPDK net\_tap
* Function-level instrumentation captured via LTTng
* Only UDP traffic forwarded (as per flow rule); other traffic dropped
* Optimized trace (5 seconds, \~900 MB) ready for performance analysis

---

This trace can now be archived, shared, or referenced in further analysis or performance tuning sessions.


