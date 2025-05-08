#!/bin/bash
# Commands used to set up and run DPDK helloworld

# Install dependencies
sudo apt update
sudo apt install libnuma-dev libpcap-dev python3-pyelftools ninja-build python3-pip

# Upgrade Meson
pip3 install --user meson --upgrade
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Configure HugePages
sudo sysctl -w vm.nr_hugepages=1024

# Mount hugetlbfs
sudo mkdir /dev/hugepages
sudo mount -t hugetlbfs none /dev/hugepages

# Build DPDK and helloworld
cd /home/eagle/vpp/build-root/build-vpp-native/external/src-dpdk
rm -rf build
meson setup build
cd build
meson configure -Dexamples=helloworld
ninja

# Run helloworld
sudo ./build/examples/dpdk-helloworld -l 0-3 -n 4
