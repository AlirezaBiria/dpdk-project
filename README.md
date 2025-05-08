Installation Challenges for LTTng and Trace Compass on Ubuntu 20.04
System Specifications

Operating System: Ubuntu 20.04 LTS (Focal Fossa)
CPU: Intel Core i7-4500U (2.0 GHz, 4 cores)
RAM: 8 GB
GPU: NVIDIA GeForce 820M (using Nouveau open-source driver)
Disk Space: 176 GB free
Kernel Version: 5.4.0-174-generic
Architecture: x86_64

LTTng Installation
Steps
The following commands were used to install LTTng components:
sudo apt update
sudo apt install -y lttng-tools lttng-modules-dkms
sudo apt install -y liblttng-ust0 liblttng-ust-dev

Challenges

Missing lttng-ust Package:

Initial attempts to install lttng-ust failed with the error: Unable to locate package lttng-ust.
Solution: The correct package name for Ubuntu 20.04 is liblttng-ust0. Installed using:sudo apt install -y liblttng-ust0 liblttng-ust-dev




Babeltrace2 Unavailable:

Attempting to install babeltrace2 failed as it was not available in Ubuntu 20.04's default repositories.
Solution: Proceeded with the pre-installed babeltrace (version 1.5.8), which was sufficient for LTTng trace analysis:babeltrace --version





Verification

LTTng version: 2.11.2
Kernel modules loaded:lsmod | grep lttng

Output confirmed modules like lttng_tracer, lttng_statedump, etc.
User-space libraries:ldconfig -p | grep lttng

Confirmed presence of liblttng-ust.so, liblttng-ust-ctl.so, etc.

Trace Compass Installation
Steps
Trace Compass (version 10.3.0) was downloaded manually and installed:
mv ~/Downloads/trace-compass-10.3.0-20250313-1426-linux.gtk.x86_64.tar.gz ~
tar -xvzf trace-compass-10.3.0-20250313-1426-linux.gtk.x86_64.tar.gz
sudo mv trace-compass /opt/trace-compass
sudo apt install -y openjdk-21-jre
cd /opt/trace-compass
./tracecompass

Challenges

Download Issues:

Initial attempts to download Trace Compass 9.0.0 using wget resulted in HTTP 403 Forbidden errors:wget https://download.eclipse.org/tracecompass/releases/9.0.0/linux/tracecompass-9.0.0-20230614-0836-linux64.tar.gz


Directory listings (rcp, rcp-repository, repository) did not include the expected tar.gz file.
Solution: Manually downloaded version 10.3.0 from:https://download.eclipse.org/tracecompass/releases/10.3.0/linux/




Java Version Requirement:

Trace Compass 10.3.0 requires Java 21, which was not available in Ubuntu 20.04’s default repositories.
Solution: Added the OpenJDK PPA and installed Java 21:sudo add-apt-repository ppa:openjdk-r/ppa
sudo apt update
sudo apt install -y openjdk-21-jre




Pixman and GTK Errors:

Running ./tracecompass produced errors:*** BUG ***
In pixman_region32_init_rect: Invalid rectangle passed
Set a breakpoint on '_pixman_log_error' to debug

(Trace Compass:91358): Gtk-WARNING **: Negative content width -7 (allocation 1, extents 4x4) while allocating gadget (node button, owner GtkButton)


Cause: Likely due to the Nouveau driver for NVIDIA GeForce 820M, which may have compatibility issues with GTK/Pixman.
Temporary Solution: Errors were ignored as the GUI functioned correctly. Potential fix includes installing the NVIDIA proprietary driver:sudo apt install -y nvidia-driver-470
sudo reboot




Java Annotation Warnings:

Warnings about javax.inject and javax.annotation packages appeared:WARNING: Annotation classes from the 'javax.inject' or 'javax.annotation' package found.


Solution: Suppressed by adding JVM flags:./tracecompass -Declipse.e4.inject.javax.warning=false





Verification

Trace Compass GUI opened successfully.
A sample LTTng trace was created and loaded:lttng create sample-session
sudo lttng enable-event -a -k
sudo lttng start
sleep 5
sudo lttng stop


Trace loaded in Trace Compass via File > Open Trace (~/lttng-traces/sample-session-*/).

Recommendations

For LTTng: Ensure correct package names (liblttng-ust0 instead of lttng-ust) and verify babeltrace compatibility.
For Trace Compass: Use the archive site (archive.eclipse.org) for older versions or manually download newer versions. Install Java 21 for version 10.3.0.
For Graphics Issues: Consider installing NVIDIA proprietary drivers to resolve Pixman/GTK errors.
For Cleaner Output: Suppress Java warnings with JVM flags.

Conclusion
Despite initial challenges with package availability, download errors, and graphical issues, LTTng and Trace Compass were successfully installed and functional. The system is now ready for kernel and user-space tracing with graphical analysis.
