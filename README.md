# DPDK Project: Setting Up and Running the helloworld Example

This repository contains the setup and execution of the **helloworld** example using the Data Plane Development Kit (DPDK) within a VPP (Vector Packet Processing) environment. It will also include future work on a memif-based client-server application with LTTng tracing and Trace Compass analysis. This report outlines the steps, challenges faced, solutions applied, results achieved, and system specifications for the helloworld example.

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
'''bash
