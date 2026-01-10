# Hardware Setup Guide for Minisforum EliteMini UM890 Pro

## Hardware Specifications

### Target System
- **Model**: Minisforum EliteMini UM890 Pro
- **CPU**: AMD Ryzen 9 8945HS (8-core, 16-thread, Zen 4 architecture)
- **iGPU**: AMD Radeon 780M (RDNA 3, gfx1103)
- **Memory**: 96 GB DDR5-5600 (2× Crucial 48GB CT48G56C46S5, UMA - Unified Memory Architecture)
  - Specifications per module:
    - Capacity: 48GB
    - Speed: DDR5-5600 (PC5-44800)
    - Type: SO-DIMM (260-pin)
    - CAS Latency: CL46
    - Voltage: 1.1V
    - Form Factor: Unbuffered Non-ECC
- **Storage**: 2× Crucial P3 Plus 4TB NVMe SSD (CT4000P3PSSD8)
  - NVMe0: OS drive (Gentoo Linux on Btrfs)
  - NVMe1: AI/Data drive (ZFS with optimizations for large models)
  - Specifications per drive:
    - Capacity: 4TB
    - Interface: PCIe 4.0 x4, NVMe 1.4
    - Sequential Read: Up to 4,800 MB/s
    - Sequential Write: Up to 4,100 MB/s
    - Form Factor: M.2 2280
- **Boot Mode**: UEFI only

## BIOS/UEFI Configuration

### Required Settings

1. **Boot Mode**
   - Set to UEFI mode (disable Legacy/CSM)
   - Verify by checking `/sys/firmware/efi` exists after boot

2. **Secure Boot**
   - Can be disabled for ease of installation
   - Can be re-enabled later with proper key management

3. **Memory Configuration**
   - Verify both 48GB modules detected (96GB total)
   - Enable XMP/EXPO profile for DDR5-5600 (if available)
   - Verify memory running at 5600 MT/s
   - Set iGPU memory allocation to AUTO or 4GB minimum
   - UMA mode should be enabled (default on APU systems)
   
   **Memory verification commands** (after boot):
   ```bash
   # Check total memory
   free -h
   
   # Check memory speed and modules
   sudo dmidecode -t memory | grep -A 20 "Memory Device"
   
   # Verify DDR5-5600
   sudo dmidecode -t memory | grep -i speed
   ```

4. **AMD Platform Security**
   - AMD-V (virtualization) can be enabled for future VM support
   - IOMMU can be enabled for device passthrough

5. **Power Management**
   - AMD PSP (Platform Security Processor): Enabled
   - AMD Cool'n'Quiet: Enabled
   - C-States: Enabled for power efficiency

### Recommended BIOS Updates

Check Minisforum's website for latest BIOS updates that may include:
- Improved AGESA microcode
- Enhanced memory compatibility
- Better iGPU performance

## Storage Configuration

### NVMe Drive Identification

Before installation, identify your drives:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL
```

Example output for CT4000P3PSSD8:
```
NAME        SIZE MODEL                 SERIAL
nvme0n1     3.7T CT4000P3PSSD8        2341E6D8XXXX
nvme1n1     3.7T CT4000P3PSSD8        2341E6D8YYYY
```

Use `/dev/disk/by-id/*` paths for stability:
```bash
ls -l /dev/disk/by-id/ | grep CT4000P3PSSD8
```

Example output:
```
nvme-CT4000P3PSSD8_2341E6D8XXXX -> ../../nvme0n1
nvme-CT4000P3PSSD8_2341E6D8YYYY -> ../../nvme1n1
```

### Recommended Drive Layout

**NVMe0 (OS Drive - Crucial P3 Plus 4TB)**
- Partition 1: 1 GiB - EFI System Partition (FAT32)
- Partition 2: Remaining (~3.99 TB) - Btrfs root with subvolumes
  - `@` - Root filesystem
  - `@home` - User home directories
  - `@var` - Variable data
  - `@snapshots` - System snapshots for rollback

**NVMe1 (AI/Data Drive - Crucial P3 Plus 4TB)**
- Partition 1: Entire disk (~4 TB) - ZFS pool
  - `tank/data` - General data storage
  - `tank/backup` - Backup storage
  - `tank/ai-models` - AI models (recordsize=1M for large files)

### Crucial P3 Plus Specific Notes

- **PCIe 4.0 x4**: Ensure your M.2 slots support PCIe 4.0 for full performance
- **TBW (Total Bytes Written)**: 800 TBW for 4TB model - excellent for AI/ML workloads
- **DRAM-less design**: Uses HMB (Host Memory Buffer) - ensure proper BIOS settings
- **Thermal management**: Consider adding heatsinks if sustained writes cause throttling
- **Power loss protection**: Basic capacitor-based protection included

## Memory Considerations (UMA Architecture)

### Understanding UMA with Crucial CT48G56C46S5 (96GB DDR5-5600)

The UM890 Pro uses Unified Memory Architecture (UMA) with 2× 48GB DDR5-5600 modules:
- System RAM is shared between CPU and iGPU
- No dedicated VRAM; iGPU uses system RAM
- Total bandwidth: ~89.6 GB/s (DDR5-5600, dual-channel)
- Large capacity (96GB) ideal for AI workloads with huge models
- Low latency (CL46) benefits both CPU and GPU operations

### DDR5-5600 Performance Benefits

1. **High Bandwidth**: 
   - DDR5-5600 provides ~44.8 GB/s per channel
   - Dual-channel: ~89.6 GB/s total bandwidth
   - Critical for iGPU performance (Radeon 780M bandwidth-limited)

2. **Large Capacity (96GB)**:
   - Can load 70B+ parameter LLMs entirely in RAM
   - Supports multiple AI models simultaneously
   - Excellent for Stable Diffusion XL with large batch sizes
   - Sufficient for 8K video editing and complex 3D scenes

3. **Memory Optimization Strategies**

1. **For AI/ML Workloads**
   - 96 GB allows loading 70B+ parameter models
   - UMA eliminates PCIe transfer overhead
   - Shared memory benefits multi-modal workflows

2. **For Graphics (Blender/Cycles)**
   - Smaller tile sizes recommended (256x256)
   - Enable adaptive sampling
   - Use persistent data mode

3. **For ComfyUI/SDXL**
   - Use `--lowvram` flag
   - Enable VAE slicing
   - Enable attention slicing
   - Limit VRAM allocation to leave headroom

4. **System Memory Management**
   - Configure zram swap (RAM/4 = 24GB compressed swap)
   - Avoid excessive disk swap on NVMe
   - Monitor with `free -h` and `watch -n1 'cat /proc/meminfo | grep -i available'`

## Network Configuration

### Ethernet
- Onboard Gigabit Ethernet supported by kernel drivers
- NetworkManager recommended for desktop use
- Static IP or DHCP

### WiFi
- Check specific WiFi card model in your unit
- Most modern cards supported by `linux-firmware`
- May require enabling specific firmware files

### Bluetooth
- Usually integrated with WiFi module
- Requires `bluez` package
- Enable with `rc-service bluetooth start` (OpenRC) or `systemctl start bluetooth` (systemd)

## Cooling and Thermal Management

### Thermal Characteristics
- Compact mini-PC form factor
- Active cooling with fan(s)
- May throttle under sustained heavy load

### Monitoring
```bash
# Install monitoring tools
emerge sys-apps/lm-sensors

# Detect sensors
sensors-detect

# Monitor temperatures
watch -n1 sensors
```

### Performance Tuning
```bash
# CPU governor (set in kernel command line)
amd_pstate=active

# Check current governor
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Monitor CPU frequency
watch -n1 "grep MHz /proc/cpuinfo"
```

## GPU Configuration (Radeon 780M)

### Kernel Modules
- `amdgpu` - Main AMD GPU driver
- Loaded automatically with proper kernel config

### Verify GPU Detection
```bash
# List PCI devices
lspci -k | grep -A 3 VGA

# Check DRM devices
ls -l /dev/dri/

# AMD GPU info
rocminfo  # After ROCm installation
```

### Mesa and Vulkan
- Mesa provides OpenGL and Vulkan support
- Vulkan ICD: `/usr/share/vulkan/icd.d/radeon_icd.x86_64.json`
- Verify with: `vulkaninfo | grep deviceName`

## UEFI Boot Verification

### Check UEFI Mode
```bash
# This should exist if booted in UEFI mode
ls /sys/firmware/efi
```

### EFI Variables
```bash
# View EFI boot entries
efibootmgr -v

# After installation, you should see a rEFInd entry
efibootmgr | grep -i refind
```

### Boot Menu Entries (Post-Installation)

After installation, rEFInd will auto-detect kernels in `/boot`:

**Dual-kernel mode** (INSTALL_DUAL_KERNEL="yes"):
```bash
# List detected kernels
ls -1 /boot/vmlinuz-*

# Expected output:
# /boot/vmlinuz-6.12.58-gentoo-dist      # Kernel A (fallback)
# /boot/vmlinuz-6.12.58-um890-tuned      # Kernel B (tuned)
```

**Single-kernel mode**:
```bash
# Single kernel entry
ls -1 /boot/vmlinuz-*

# Expected output (binary kernel):
# /boot/vmlinuz-6.12.58-gentoo-dist
```

rEFInd automatically creates boot menu entries for all detected kernels.

## Pre-Installation Checklist

- [ ] BIOS updated to latest version
- [ ] UEFI mode enabled
- [ ] Both NVMe drives detected in BIOS
- [ ] Memory running at full speed (check BIOS)
- [ ] Network connectivity verified
- [ ] Gentoo live USB created and booted
- [ ] Verified `/sys/firmware/efi` exists
- [ ] Identified NVMe device paths
- [ ] Backed up any existing data

## Post-Installation Verification

### System Info
```bash
# CPU info
lscpu

# Memory info - verify 96GB
free -h

# Detailed memory info
sudo dmidecode -t memory

# Verify DDR5-5600 modules
sudo dmidecode -t memory | grep -A 20 "Memory Device" | grep -E "(Size|Speed|Type|Manufacturer|Part Number|Locator)"

# Expected output:
# Size: 48 GB (first module)
# Size: 48 GB (second module)  
# Type: DDR5
# Speed: 5600 MT/s
# Manufacturer: Crucial
# Part Number: CT48G56C46S5

# Memory bandwidth test
emerge app-benchmarks/sysbench
sysbench memory --memory-total-size=10G --memory-oper=read run
sysbench memory --memory-total-size=10G --memory-oper=write run

# GPU info
lspci | grep VGA
glxinfo | grep "OpenGL renderer"
vulkaninfo | grep deviceName

# Kernel info - verify installation mode
uname -r
# Dual-kernel mode: Shows <VERSION>-gentoo-dist OR <VERSION>-um890-tuned
# Single-kernel mode: Shows <VERSION>-gentoo-dist OR <VERSION>-gentoo

# List all installed kernels
ls -1 /boot/vmlinuz-* | sed 's/.*vmlinuz-//'

# Verify initramfs for each kernel
ls -1 /boot/initramfs-*.img

# Check module directories match boot kernels
ls -1d /lib/modules/*/

# Storage info
lsblk
btrfs filesystem show
zpool status
```

### Performance Baseline
```bash
# CPU benchmark
emerge app-benchmarks/sysbench
sysbench cpu run

# Memory bandwidth
sysbench memory run

# Disk I/O
dd if=/dev/zero of=/tmp/test bs=1M count=1024 conv=fdatasync
dd if=/data/test of=/dev/null bs=1M count=1024
```

## Troubleshooting

### Boot Issues
- Verify UEFI boot order in BIOS
- Check rEFInd configuration in `/boot/EFI/refind/refind.conf`
- Use snapshot boot option if system won't start
- Access UEFI shell to manually boot kernel

### iGPU Not Detected
- Verify `amdgpu` module loaded: `lsmod | grep amdgpu`
- Check kernel logs: `dmesg | grep -i amdgpu`
- Ensure firmware installed: `emerge sys-kernel/linux-firmware`

### Memory Issues
- Monitor with `htop` or `atop`
- Check for memory leaks in running processes
- Verify zram: `zramctl`
- Review OOM killer logs: `dmesg | grep -i oom`

### Storage Performance

For Crucial P3 Plus CT4000P3PSSD8:

```bash
# Check NVMe link speed (should show PCIe 4.0 x4)
lspci -vv | grep -i nvme -A 20 | grep LnkSta

# Monitor I/O performance
iostat -x 1

# Verify TRIM support (should show non-zero values)
lsblk --discard

# Enable TRIM (systemd)
systemctl enable fstrim.timer

# Enable TRIM (OpenRC)
rc-update add fstrim default

# Test sequential read performance
dd if=/dev/nvme0n1 of=/dev/null bs=1M count=4096 iflag=direct

# Test sequential write performance (WARNING: destroys data!)
dd if=/dev/zero of=/dev/nvme0n1 bs=1M count=4096 oflag=direct

# Better benchmarking with fio
fio --name=seqread --rw=read --direct=1 --ioengine=libaio --bs=1M --numjobs=1 --size=4G --runtime=60 --group_reporting --filename=/dev/nvme0n1
```

### Crucial P3 Plus Optimization

The CT4000P3PSSD8 uses HMB (Host Memory Buffer) instead of onboard DRAM. Optimize by:

```bash
# Check HMB status
nvme id-ctrl /dev/nvme0n1 | grep -i hmb

# Increase HMB size if needed (in KB, typically 128-256 MB)
echo 262144 > /sys/block/nvme0n1/device/hmb_size

# Make persistent via udev rule
# /etc/udev/rules.d/60-nvme-hmb.rules
ACTION=="add", KERNEL=="nvme[0-9]", ATTR{device/hmb_size}="262144"
```

## Additional Resources

- [Gentoo AMD64 Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
- [Gentoo AMDGPU Wiki](https://wiki.gentoo.org/wiki/AMDGPU)
- [Btrfs Wiki](https://btrfs.wiki.kernel.org/)
- [ZFS on Linux](https://openzfs.github.io/openzfs-docs/)
- [ROCm Documentation](https://rocm.docs.amd.com/)
- [Minisforum Support](https://www.minisforum.com/support)
