# Linux Server Runbook

This runbook documents the process to build a minimal Debian server, configured with LVM, static networking, and a custom systemd service.

## Installation

1. Create a new Virtual Machine in VirtualBox / UTM.
2. Boot from the Debian Netinst ISO.
3. Select "Install" (no graphical installer required).
4. Set Hostname, Locale, and Timezone during the installation prompts.
5. When prompted for software selection, **uncheck** "Debian desktop environment" and "GNOME". Only check "SSH server" and "standard system utilities" to ensure a minimal installation.

## Storage and LVM

During installation, select "Manual" partitioning.
Create a `/boot` partition (e.g., 512MB, ext4, standard partition).
Use the rest of the disk as an LVM Physical Volume.
Create a Volume Group (e.g., `vg0`).
Create the following Logical Volumes:

### Logical Volume Sizing Justifications

- **`/` (root)**: 4GB. Contains the base OS and root filesystem. If this fills up, the system may become unbootable or unstable, and essential system services might crash due to lack of temporary file space.
- **`/home`**: 2GB. Contains user data. If this fills up, users won't be able to write files or save their configurations, but it generally won't crash the core operating system.
- **`/var`**: 4GB. Contains logs, package caches, and databases. This needs real headroom. If `/var` fills up, the system can't write logs, apt cannot install updates, and databases will fail to operate, which is one of the most common ways a server falls over.
- **`swap`**: 2GB. Used when RAM is full. If swap fills up and RAM is exhausted, the kernel OOM (Out Of Memory) killer will start forcefully terminating processes to keep the system alive.

*Note: Leave free space in the volume group instead of allocating all extents at install time. You cannot grow a volume out of space that is already spoken for.*

### Growing a Logical Volume

It is better to over-provision the volume group and leave free space because growing a logical volume is an online operation that can be done safely while the system is running. Shrinking a filesystem (like ext4) requires unmounting it first, which causes downtime, and some filesystems (like XFS) cannot be shrunk at all. It's safer to grow later than guess large up front.

To grow the `/var` volume by 1GB while the system is running, run:

```bash
sudo lvextend -L +1G /dev/vg0/var
sudo resize2fs /dev/mapper/vg0-var
```

## Networking

Configure a static IP address from the command line by editing `/etc/network/interfaces` (assuming standard Debian ifupdown). Do not use a graphical tool.

```bash
sudo nano /etc/network/interfaces
```

Modify the primary network interface configuration (e.g., `enp0s3`):

```text
auto enp0s3
iface enp0s3 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 1.1.1.1 8.8.8.8
```

Restart networking or reboot, then confirm connectivity and DNS resolution:
```bash
ping -c 3 google.com
```

## Custom Service: monitor_disk

This repository contains a custom service that monitors disk usage every 60 seconds and logs it to the journal. The loop ensures the process keeps running rather than exiting immediately.

### Deployment

1. Copy the script to an appropriate location and make it executable:
   ```bash
   sudo cp scripts/monitor_disk.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/monitor_disk.sh
   ```

2. Copy the unit file to systemd's directory:
   ```bash
   sudo cp systemd/monitor_disk.service /etc/systemd/system/
   ```

3. Reload systemd daemon to read the new unit file, enable, and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable monitor_disk.service
   sudo systemctl start monitor_disk.service
   ```

4. Verify it's writing to the journal:
   ```bash
   sudo journalctl -u monitor_disk.service -f
   ```

## Boot Report

### Slowest Units at Boot

You can measure boot performance and identify the slowest units by running:
```bash
systemd-analyze blame
```

Example output:
```text
3.125s networking.service
1.002s systemd-udev-settle.service
 450ms ssh.service
```

**Explanation of `networking.service`**: This unit configures the network interfaces at boot time based on the settings in `/etc/network/interfaces`. It takes longer than many other units because it physically brings up the network interfaces, waits for links to become ready, and potentially applies static IP settings or negotiates DHCP, which inherently takes time.

### Enabled vs. Active

- **Enabled**: A service that is *enabled* is configured to start automatically at boot (usually because a symlink was created in a target's `.wants` directory, like `multi-user.target.wants/`). This is a persistent state regarding boot behavior.
- **Active**: A service that is *active* is currently running in memory right now. This is its current operational state.

A service can be enabled but inactive (e.g., if it crashed after booting or hasn't started yet), or active but disabled (started manually by a user, but it will not survive a reboot).