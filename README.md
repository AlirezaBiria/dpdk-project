# DPDK Project: Setting Up and Running the helloworld Example

This repository contains the setup and execution of the **helloworld** example using the Data Plane Development Kit (DPDK) within a VPP (Vector Packet Processing) environment. This report outlines the steps, challenges faced, solutions applied, results achieved, and system specifications.

## Prerequisites

To replicate this project, the following tools and dependencies were installed:
- **Ubuntu 20.04 LTS** (or compatible Linux distribution)
- **DPDK** (integrated within VPP source code)
- **Meson** (version 1.8.0 or higher)
- **Ninja** (version 1.10.0 or higher)
- **Dependencies**: `libnuma-dev`, `libpcap-dev`, `python3-pyelftools`, `ninja-build`, `python3-pip`

These were installed using:
```bash
sudo apt update
sudo apt install libnuma-dev libpcap-dev python3-pyelftools ninja-build python3-pip

System Specifications

The project was executed on the following system:
text
Architecture: x86_64
CPU op-mode(s): 32-bit, 64-bit
Byte Order: Little Endian
Address sizes: 39 bits physical, 48 bits virtual
CPU(s): 4
On-line CPU(s) list: 0-3
Thread(s) per core: 2
Core(s) per socket: 2
Socket(s): 1
NUMA node(s): 1
Vendor ID: GenuineIntel
CPU family: 6
Model: 69
Model name: Intel(R) Core(TM) i7-4500U CPU @ 1.80GHz
Stepping: 1
CPU MHz: 1000.000
CPU max MHz: 3000.0000
CPU min MHz: 800.0000
BogoMIPS: 4789.31
Virtualization: VT-x
L1d cache: 64 KiB
L1i cache: 64 KiB
L2 cache: 512 KiB
L3 cache: 4 MiB
NUMA node0 CPU(s): 0-3
Vulnerability Gather data sampling: Not affected
Vulnerability Itlb multihit: KVM: Mitigation: VMX disabled
Vulnerability L1tf: Mitigation; PTE Inversion; VMX conditional cache flushes, SMT vulnerable
Vulnerability Mds: Mitigation; Clear CPU buffers; SMT vulnerable
Vulnerability Meltdown: Mitigation; PTI
Vulnerability Mmio stale data: Unknown: No mitigations
Vulnerability Reg file data sampling: Not affected
Vulnerability Retbleed: Not affected
Vulnerability Spec rstack overflow: Not affected
Vulnerability Spec store bypass: Mitigation; Speculative Store Bypass disabled via prctl and seccomp
Vulnerability Spectre v1: Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerability Spectre v2: Mitigation; Retpolines; IBPB conditional; IBRS_FW; STIBP conditional; RSB filling; PBRSB-eIBRS Not affected; BHI Not affected
Vulnerability Srbds: Mitigation; Microcode
Vulnerability Tsx async abort: Not affected
Flags: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm cpuid_fault epb invpcid_single pti ssbd ibrs ibpb stibp tpr_shadow vnmi flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid xsaveopt dtherm ida arat pln pts md_clear flush_l1d
Steps to Set Up and Run helloworld
1. Configuring HugePages

HugePages were allocated to provide large, contiguous memory pages for DPDK. A total of 1024 HugePages (2 GB) were configured.

Command:
bash
sudo sysctl -w vm.nr_hugepages=1024

Result: The system successfully allocated 1024 HugePages, verified using cat /proc/meminfo | grep HugePages.

2. Setting Up the DPDK Build Environment

The DPDK source code was located at /home/eagle/vpp/build-root/build-vpp-native/external/src-dpdk. The helloworld example was built using Meson and Ninja.

Commands:
bash
cd /home/eagle/vpp/build-root/build-vpp-native/external/src-dpdk
rm -rf build
meson setup build
cd build
meson configure -Dexamples=helloworld
ninja

Result: The build process created the dpdk-helloworld executable in build/examples/.
3. Running the helloworld Example

The helloworld example was executed on CPU cores 0-3 to verify the DPDK installation.

Command:
bash
sudo ./build/examples/dpdk-helloworld -l 0-3 -n 4

Result: The example ran successfully, printing "hello" from each core (0 to 3), confirming that DPDK was correctly configured and operational.

Challenges and Solutions

Several challenges were encountered during the setup and execution process:

    Outdated Meson Version:
        Issue: The initial Meson version (0.53.2) was incompatible with DPDK, which required version 0.57 or higher.
        Solution: Upgraded Meson to version 1.8.0 using:
        bash

    pip3 install --user meson --upgrade
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    Outcome: The upgraded Meson resolved compatibility issues, allowing the build to proceed.

Missing helloworld Executable:

    Issue: After running ninja, the dpdk-helloworld executable was not found in build/examples/.
    Solution: Rebuilt the project from scratch by removing the build directory and re-running the build commands:
    bash

        cd /home/eagle/vpp/build-root/build-vpp-native/external/src-dpdk
        rm -rf build
        meson setup build
        cd build
        meson configure -Dexamples=helloworld
        ninja
        Outcome: The rebuild ensured that the dpdk-helloworld executable was correctly generated.
    PATH Configuration for Meson:
        Issue: The upgraded Meson was installed in /home/eagle/.local/bin, which was not in the system’s PATH.
        Solution: Added the directory to PATH using the commands above.
        Outcome: The system used the correct Meson version (1.8.0) for the build.

Conclusion

This project successfully configured HugePages and ran the DPDK helloworld example on CPU cores 0-3. The challenges related to Meson versioning and build issues were resolved through careful debugging and rebuilding. The results confirm that the DPDK environment is correctly set up.
References

    DPDK Documentation: https://doc.dpdk.org
    Memif Guide: https://doc.dpdk.org/guides/nics/memif.html
    VPP Source Code: /home/eagle/vpp
