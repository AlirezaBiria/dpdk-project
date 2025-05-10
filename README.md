# DPDK memif Traffic Transfer and LTTng Tracing Report

This report provides a detailed account of the process undertaken to establish a client-server traffic transfer utilizing the DPDK `memif` interface, configure DPDK with tracing support via the `-finstrument-functions` flag, and attempt to record the traffic using LTTng tools. The objective was to facilitate traffic transfer between a client and server using `dpdk-testpmd` and capture function call traces with LTTng for potential visualization in Trace Compass. However, the tracing process did not record any events, and this document outlines the procedures, configurations, and outcomes.

## Objective
- Establish a DPDK-based client-server configuration using the `memif` interface for traffic transfer.
- Compile DPDK with the `-finstrument-functions` flag to enable tracing capabilities.
- Employ LTTng to capture traffic and function call data.
- Prepare the trace for potential visualization in Trace Compass (not completed due to absence of trace data).

## System Setup
- **Operating System:** Ubuntu 20.04
- **DPDK Version:** 23.11.0
- **Tools Installed:** `lttng-tools`, `liblttng-ust-dev`, `meson`, `ninja`, `gcc`, `ccache`
- **User:** `eagle` on host `eagle-X450LD`

## Procedures and Commands

### 1. Environment Preparation
Ensure all necessary dependencies are installed and Hugepages are configured to support DPDK operations.

```bash
# Install required packages
sudo apt install lttng-tools liblttng-ust-dev meson ninja-build gcc ccache

# Configure Hugepages (1024 pages of 2MB each)
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Verify Hugepages configuration
cat /proc/meminfo | grep Huge
```

**Hugepages Verification Output:**
```
AnonHugePages:         0 kB
ShmemHugePages:        0 kB
FileHugePages:         0 kB
HugePages_Total:    1024
HugePages_Free:     1003
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:         2097152 kB
```

### 2. DPDK Build with Tracing Support
The DPDK build was modified to incorporate the `-finstrument-functions` flag for tracing.

```bash
# Navigate to the DPDK directory
cd /home/eagle/dpdk-23.11

# Modify meson.build files to include -finstrument-functions
nano app/meson.build
# Modify the line:
# default_cflags = machine_args + ['-DALLOW_EXPERIMENTAL_API']
# to:
# default_cflags = machine_args + ['-DALLOW_EXPERIMENTAL_API', '-finstrument-functions']

nano lib/meson.build
# After the line:
# default_cflags = machine_args
# Add:
# default_cflags += ['-finstrument-functions']

nano drivers/meson.build
# After the line:
# default_cflags = machine_args
# Add:
# default_cflags += ['-finstrument-functions']

# Clean and recreate the build directory
rm -rf build/
mkdir build
cd build

# Configure and build DPDK
meson setup ..
ninja

# Verify the build
ls -l app/dpdk-testpmd
./app/dpdk-testpmd -v
```

**Build Output (Excerpt):**
```
[2538/2538] Linking target app/dpdk-test
-rwxrwxr-x 1 eagle eagle 49456024 May  9 22:00 app/dpdk-testpmd
EAL: Detected CPU lcores: 4
EAL: Detected NUMA nodes: 1
EAL: RTE Version: 'DPDK 23.11.0'
```

### 3. LTTng Session Configuration
An LTTng session was created to trace user-space events using the `cyg-profile` provider.

```bash
# Clear previous trace files
rm -rf /home/eagle/lttng-traces/*

# Create LTTng session
lttng create memif_trace_1
lttng enable-event -u 'lttng_ust_cyg_profile:*'
lttng add-context --userspace --type=vpid --type=vtid --type=procname
lttng start
```

### 4. Server Execution (memif Server)
The `dpdk-testpmd` application was executed in server mode using the `net_memif` virtual device.

```bash
cd /home/eagle/dpdk-23.11/build
sudo env LD_PRELOAD=/usr/lib/x86_64-linux-gnu/liblttng-ust-cyg-profile.so ./app/dpdk-testpmd -l 0-1 --proc-type=primary --file-prefix=pmd1 --vdev=net_memif,role=server -- -i
```

Within the `testpmd` interactive prompt:
```
start
show port stats 0
```

**Server Output (memif Server):**

![memif Server Output](server_output.png)

**Analysis of Server Output:**
- Port 0 was configured with the MAC address `FA:EC:EB:32:87:CE`.
- Traffic statistics indicated successful data exchange:
  - `RX-packets: 39,021,952` (approximately 39 million packets received).
  - `TX-packets: 39,021,952` (approximately 39 million packets transmitted).
  - `RX-bytes: 2,497,404,928` and `TX-bytes: 2,497,404,928` (approximately 2.5 GB of data transferred).
- The throughput metrics (`Rx-pps` and `Tx-pps`) were reported as 0, reflecting the timing of the measurement after traffic ceased.

### 5. Client Execution (memif Client)
The `dpdk-testpmd` application was run as a client to transmit traffic to the server.

```bash
cd /home/eagle/dpdk-23.11/build
sudo env LD_PRELOAD=/usr/lib/x86_64-linux-gnu/liblttng-ust-cyg-profile.so ./app/dpdk-testpmd -l 2-3 --proc-type=primary --file-prefix=pmd2 --vdev=net_memif -- -i
```

Within the `testpmd` interactive prompt:
```
start tx_first
show port stats 0
```

**Client Output (memif Client):**

![memif Client Output](client_output.png)

**Analysis of Client Output:**
- Port 0 was configured with the MAC address `D2:05:5D:0B:B3:0F`.
- Traffic statistics confirmed successful transmission:
  - `RX-packets: 50,802,848` (approximately 50 million packets received).
  - `TX-packets: 50,802,848` (approximately 50 million packets transmitted).
  - `RX-bytes: 3,251,382,272` and `TX-bytes: 3,251,383,488` (approximately 3.25 GB of data transferred).
- The higher packet count compared to the server suggests the client initiated and sustained the traffic flow.
- The throughput metrics (`Rx-pps` and `Tx-pps`) were 0, consistent with the timing of the measurement.

### 6. Trace Termination and Review
Following the execution of the server and client, the LTTng session was terminated to evaluate the trace data.

```bash
lttng stop
ls -l /home/eagle/lttng-traces/memif_trace_1-*
lttng view
lttng destroy
```

**Trace Output:**
```
ls -l /home/eagle/lttng-traces/memif_trace_1-*
total 0
```

### 7. Results
- **Traffic Transfer:** The transfer of traffic between the memif server and client was successfully accomplished, with a significant volume of packets exchanged (39 million on the server and 50 million on the client).
- **Tracing:** Despite the implementation of `-finstrument-functions` and the configuration of `lttng_ust_cyg_profile:*` events, the trace output remained empty, with no events recorded by `lttng view`.

### 8. Future Updates
This report will be revised and updated upon resolution of the tracing issue.
