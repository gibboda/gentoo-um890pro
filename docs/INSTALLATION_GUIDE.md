# Quick Installation Guide

## Pre-Installation Checklist

Before running the installer, verify:

- [ ] System is Minisforum EliteMini UM890 Pro
- [ ] 2× Crucial 48GB DDR5-5600 RAM (CT48G56C46S5) installed = 96GB total
- [ ] 2× Crucial P3 Plus 4TB NVMe SSD (CT4000P3PSSD8) installed
- [ ] BIOS updated to latest version
- [ ] UEFI mode enabled (not Legacy/CSM)
- [ ] Both NVMe drives detected in BIOS
- [ ] Memory running at DDR5-5600 speed
- [ ] Gentoo Live USB created and booted
- [ ] Network connectivity working
- [ ] Backed up any existing data

## Boot Gentoo Live Environment

1. **Create Gentoo Live USB**:
   ```bash
   # Download latest Gentoo LiveGUI ISO
   wget https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-iso.txt
   # Check the ISO filename and download it
   wget https://distfiles.gentoo.org/releases/amd64/autobuilds/<path-from-txt>
   
   # Write to USB (replace sdX with your USB device)
   sudo dd if=gentoo-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

2. **Boot from USB**:
   - Enter BIOS/UEFI (usually F2 or DEL during boot)
   - Set USB as first boot device
   - Boot into Gentoo Live environment

3. **Verify UEFI mode**:
   ```bash
   ls /sys/firmware/efi
   # Should exist if in UEFI mode
   ```

## Network Setup

1. **Check network interface**:
   ```bash
   ip addr
   ```

2. **Configure network** (if needed):
   ```bash
   # For DHCP (wired)
   dhcpcd enp4s0  # or your interface name
   
   # For WiFi
   net-setup wlp5s0  # follow the wizard
   ```

3. **Verify connectivity**:
   ```bash
   ping -c 3 gentoo.org
   ```

## Download and Prepare Installer

1. **Become root**:
   ```bash
   sudo su -
   ```

2. **Download installer**:
   ```bash
   cd /tmp
   wget https://raw.githubusercontent.com/gibboda/gentoo-um890pro/main/gentoo-um890pro-install.sh
   chmod +x gentoo-um890pro-install.sh
   ```

3. **Identify your NVMe drives**:
   ```bash
   lsblk -o NAME,SIZE,MODEL,SERIAL
   ```
   
   Example output:
   ```
   NAME        SIZE MODEL                 SERIAL
   nvme0n1     3.7T CT4000P3PSSD8        2341E6D8XXXX
   nvme1n1     3.7T CT4000P3PSSD8        2341E6D8YYYY
   ```

4. **Get stable device paths**:
   ```bash
   ls -l /dev/disk/by-id/ | grep CT4000P3PSSD8
   ```
   
   Note the paths like:
   - `/dev/disk/by-id/nvme-CT4000P3PSSD8_2341E6D8XXXX`
   - `/dev/disk/by-id/nvme-CT4000P3PSSD8_2341E6D8YYYY`

## Configure the Installer

1. **Edit the installer script**:
   ```bash
   nano gentoo-um890pro-install.sh
   ```

2. **Modify these variables** (top of script):
   ```bash
   # Set your hostname
   HOSTNAME="um890-gentoo"
   
   # Use stable disk paths (IMPORTANT!)
   OS_DISK="/dev/disk/by-id/nvme-CT4000P3PSSD8_YOUR_SERIAL1"
   DATA_DISK="/dev/disk/by-id/nvme-CT4000P3PSSD8_YOUR_SERIAL2"
   
   # Choose init system
   INIT_SYSTEM="openrc"  # or "systemd"
   
   # Kernel choice
   USE_BINARY_KERNEL="no"  # Uses source kernel
   INSTALL_DUAL_KERNEL="yes"  # Installs both for safety
   
   # Desktop and features
   INSTALL_KDE_PLASMA="yes"
   INSTALL_BLENDER="yes"
   INSTALL_COMFYUI="yes"
   INSTALL_ROCM="yes"
   INSTALL_SDXL="yes"
   
   # Snapshot management
   ENABLE_SNAPSHOTS="yes"
   
   # Timezone and locale
   TIMEZONE="America/Chicago"  # Adjust to your location
   LOCALE="en_US.UTF-8 UTF-8"
   ```

3. **Save and exit** (Ctrl+X, Y, Enter in nano)

## Run the Installer

1. **Start installation**:
   ```bash
   ./gentoo-um890pro-install.sh
   ```

2. **Confirm disk wipe**:
   - Review the displayed disk information carefully
   - Type exactly: `WIPE-AND-INSTALL`
   - Press Enter

3. **Wait for installation** (2-4 hours depending on network and CPU):
   - Stage3 download and extraction: ~10 min
   - Base system packages: ~20-40 min
   - Kernel compilation: ~30-60 min (source) or ~5 min (binary)
   - ZFS installation: ~10-20 min
   - KDE Plasma: ~40-90 min
   - Blender (if enabled): ~60-120 min
   - ROCm and AI packages: ~30-60 min

4. **Interactive steps**:
   - Set root password when prompted
   - Optionally create a user account
   - Choose username and set password

5. **Installation complete**:
   ```bash
   umount -R /mnt/gentoo
   reboot
   ```

## First Boot

1. **rEFInd Boot Menu**:
   - Select "Gentoo Linux (Current)"
   - Or "Gentoo Linux (Binary Kernel Fallback)" if issues

2. **Login**:
   - Use root or the user account you created

3. **Verify installation**:
   ```bash
   # Check memory
   free -h
   # Should show ~92-93 GiB available
   
   # Check storage
   df -h
   btrfs filesystem show
   zpool status
   
   # Check GPU
   lspci | grep VGA
   rocminfo  # Should show Radeon 780M (gfx1103)
   ```

## Post-Installation Setup

### 1. Set up ComfyUI

```bash
sudo setup-comfyui
```

Follow the prompts to:
- Clone ComfyUI repository
- Install Python dependencies with ROCm support
- Configure for UMA optimization

### 2. Download SDXL Models

```bash
cd /data/ai-models/ComfyUI/models/checkpoints
wget https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
```

### 3. Create System Snapshot

```bash
sudo manage-snapshots create
```

### 4. Configure Desktop

Start KDE Plasma:
```bash
# OpenRC
sudo rc-service xdm start

# Or enable for auto-start
sudo rc-update add xdm default

# Systemd
sudo systemctl start sddm
sudo systemctl enable sddm
```

### 5. Optimize System

Review optimization guides:
- [OPTIMIZATION_GUIDE.md](OPTIMIZATION_GUIDE.md) - Performance tuning
- [HARDWARE_SETUP.md](HARDWARE_SETUP.md) - Hardware configuration

Apply recommended optimizations:
```bash
# Set CPU governor
sudo power-profile performance

# Enable TRIM for NVMe
sudo systemctl enable fstrim.timer  # systemd
sudo rc-update add fstrim default   # OpenRC
```

## Testing Your Installation

### Test GPU Compute (ROCm)

```bash
rocm-smi
rocminfo | grep "Name:"
# Should show gfx1103
```

### Test Blender

```bash
blender --background --python ~/.config/blender/cycles-igpu-config.py
```

### Test ComfyUI

```bash
cd /data/ai-models/ComfyUI/ComfyUI
./launch-comfyui-uma.sh
```

Open browser to: http://localhost:8188

### Benchmark Performance

```bash
# CPU benchmark
sysbench cpu --threads=16 run

# Memory benchmark
sysbench memory --memory-total-size=10G run

# GPU benchmark (after loading Blender)
blender --background --python benchmark.py
```

## Troubleshooting

### Boot Issues

If system doesn't boot:
1. At rEFInd menu, select "Gentoo Linux (Snapshot Recovery)"
2. Or select "Gentoo Linux (Binary Kernel Fallback)"
3. Or boot from Live USB and use `chroot` to fix issues

### GPU Not Detected

```bash
# Load amdgpu module
sudo modprobe amdgpu

# Check dmesg
dmesg | grep amdgpu

# Verify firmware
ls /lib/firmware/amdgpu/ | grep gc_11_0_3
```

### Memory Issues

```bash
# Check memory configuration
sudo dmidecode -t memory | grep -E "(Size|Speed|Type)"

# Verify 96GB detected
free -h
```

### Network Issues

```bash
# Check interface status
ip link

# Restart NetworkManager
sudo rc-service NetworkManager restart  # OpenRC
sudo systemctl restart NetworkManager    # systemd
```

## Maintenance

### Create Regular Snapshots

```bash
# Manual snapshot
sudo manage-snapshots create

# List snapshots
sudo manage-snapshots list

# Rollback if needed
sudo manage-snapshots rollback
```

### Update System

```bash
# Sync repository
sudo emerge --sync

# Update packages
sudo emerge -avuDN @world

# Create snapshot before major updates
sudo manage-snapshots create
```

### Monitor System Health

```bash
# Run ML boot selector check
sudo ml-boot-selector

# Check logs
sudo journalctl -xe  # systemd
sudo less /var/log/messages  # OpenRC
```

## Getting Help

- [GitHub Repository](https://github.com/gibboda/gentoo-um890pro)
- [Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
- [Gentoo Forums](https://forums.gentoo.org/)
- [Gentoo IRC](irc://irc.libera.chat/#gentoo)

## Summary

You now have a fully optimized Gentoo Linux system on your UM890 Pro with:
- ✅ Dual-kernel setup for safety
- ✅ Btrfs snapshots for rollback
- ✅ ZFS for AI/data storage
- ✅ ROCm for GPU compute
- ✅ KDE Plasma 6 desktop
- ✅ Blender with GPU rendering
- ✅ ComfyUI for AI image generation
- ✅ Optimized for 96GB UMA architecture

Enjoy your high-performance AI/ML workstation!
