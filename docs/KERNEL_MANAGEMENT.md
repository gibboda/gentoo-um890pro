# Kernel Management Guide

## Overview

This system uses a **binary-first, optimize-later** approach for kernel management with automatic backup preservation. This provides both fast initial setup and the flexibility to optimize your kernel when you're ready.

## Initial Installation

The installer uses **gentoo-kernel-bin** (binary kernel) by default:
- ✅ Fast installation (5 minutes vs 30-60 minutes for source)
- ✅ Get your system running quickly
- ✅ Proven stable configuration
- ✅ No manual kernel configuration needed

## Kernel Backup Strategy

### How It Works

The system automatically preserves old kernel versions for fallback:

1. **Multiple slots**: Each kernel version uses a separate slot (e.g., 6.12.58, 6.13.0)
2. **Automatic preservation**: Old versions are kept when you upgrade or switch kernels
3. **Boot menu access**: All kernel versions appear in the rEFInd boot menu
4. **No manual cleanup needed**: Old kernels remain until you explicitly remove them

### Important Rules

- ✅ **CAN coexist**: Different kernel versions (e.g., binary 6.12.58 + source 6.13.0)
- ❌ **CANNOT coexist**: Same version in both binary and source (e.g., binary 6.12.58 + source 6.12.58)
- ✅ **Best practice**: Keep 2-3 kernel versions for safety

## Switching to Source Kernel

When you're ready to optimize your kernel for maximum performance:

```bash
sudo switch-to-source-kernel
```

This script will:
1. **Preserve your current binary kernel** in the preservation set
2. **Install the source kernel** (takes 30-60 minutes to build)
3. **Replace the binary kernel** in the same slot (if same version)
4. **Keep old kernel versions** in different slots for fallback
5. **Optionally customize** kernel configuration with `make menuconfig`

### What Happens During Switch

**Example scenario:**
- Currently running: `gentoo-kernel-bin-6.12.58`
- Run: `switch-to-source-kernel`
- Result:
  - Old: `gentoo-kernel-bin-6.12.58` → Added to preservation set (still bootable)
  - New: `gentoo-kernel-6.12.58` → Replaces binary in the same slot
  - Fallback: `gentoo-kernel-bin-6.12.58` still available in boot menu

## Kernel Management Commands

### List All Kernels

```bash
sudo manage-kernels list
```

Shows:
- Installed binary kernels
- Installed source kernels
- Available kernel sources
- Preserved kernels
- Boot entries in `/boot`

### Preserve Current Kernels

```bash
sudo manage-kernels preserve
```

Adds current kernels to `/etc/portage/sets/kernels` to prevent automatic removal.

### Clean Old Kernels

```bash
sudo manage-kernels clean
```

Interactively helps you remove old kernel versions you no longer need. Always keep at least 2 versions!

### Show Kernel Info

```bash
sudo manage-kernels info
```

Shows detailed information:
- Currently running kernel
- Selected kernel source
- All installed versions
- Preservation status

## Kernel Upgrade Workflow

### Typical Upgrade Process

1. **Upgrade to new version**:
   ```bash
   sudo emerge --sync
   sudo emerge -u sys-kernel/gentoo-kernel-bin
   ```

2. **Old version is preserved automatically**

3. **Reboot and test new kernel**

4. **After verification, optionally remove old versions**:
   ```bash
   sudo manage-kernels clean
   ```

### Switching to Source Kernel

1. **Switch from binary to source**:
   ```bash
   sudo switch-to-source-kernel
   ```

2. **Customize kernel config** (optional):
   ```bash
   cd /usr/src/linux
   make menuconfig
   emerge --config sys-kernel/gentoo-kernel
   ```

3. **Reboot and test**

4. **Old binary kernel remains available** for fallback

## Fallback Recovery

### Booting Old Kernel

If the new kernel doesn't work:

1. **At boot**, select old kernel from rEFInd menu
2. **After booting**, check kernel versions:
   ```bash
   sudo manage-kernels list
   ```
3. **Remove problematic kernel** or **investigate issues**

### Emergency Recovery

If you can't boot at all:

1. Boot from Gentoo Live USB
2. Mount your root partition
3. Chroot into the system
4. Remove the problematic kernel
5. Reinstall or fix the kernel

## Configuration Files

### Kernel Preservation Set

File: `/etc/portage/sets/kernels`

Contains kernel packages that should be preserved:
```
# Preserved kernels
sys-kernel/gentoo-kernel-bin-6.12.58
sys-kernel/gentoo-kernel-6.13.0
```

Edit this file to manually control which kernels are preserved.

### Package Configuration

File: `/etc/portage/profile/package.provided`

Controls package management behavior. Created automatically by the installer.

## Best Practices

1. **Always keep 2-3 kernel versions** for fallback
2. **Test new kernels before removing old ones**
3. **Use binary kernels for upgrades** (faster, less risky)
4. **Switch to source kernel only when stable** (for optimization)
5. **Document your kernel customizations** (keep notes of config changes)
6. **Preserve working kernels** before major upgrades

## Troubleshooting

### "Kernel slot conflict" Error

**Problem**: Trying to install both binary and source of the same version

**Solution**: 
- You can only have ONE type (binary OR source) per version
- Install different versions, OR
- Remove one type before installing the other

Example:
```bash
# This FAILS: both are version 6.12.58
emerge sys-kernel/gentoo-kernel-bin:6.12.58
emerge sys-kernel/gentoo-kernel:6.12.58  # ERROR: slot conflict!

# This WORKS: different versions
emerge sys-kernel/gentoo-kernel-bin:6.12.58  # binary 6.12.58
emerge sys-kernel/gentoo-kernel:6.13.0       # source 6.13.0
```

### Old Kernels Taking Space

**Problem**: Multiple old kernels consuming disk space

**Solution**:
```bash
# List kernels
sudo manage-kernels list

# Clean old kernels interactively
sudo manage-kernels clean
```

### Can't Boot After Kernel Update

**Problem**: New kernel doesn't boot

**Solution**:
1. Reboot and select old kernel from rEFInd menu
2. After booting old kernel:
   ```bash
   # Check what went wrong
   dmesg | less
   
   # Remove bad kernel
   emerge --deselect sys-kernel/gentoo-kernel:6.13.0
   emerge --depclean
   
   # Or reinstall/rebuild
   emerge -1 sys-kernel/gentoo-kernel
   ```

## Advanced Topics

### Kernel Customization

After switching to source kernel:

```bash
cd /usr/src/linux
make menuconfig  # Configure kernel options
make -j$(nproc)  # Build manually, OR
emerge --config sys-kernel/gentoo-kernel  # Use Gentoo's build system
```

### Multiple Kernel Types

You can maintain both binary and source kernels **in different versions**:

```bash
# Binary for stable, fast updates
emerge sys-kernel/gentoo-kernel-bin

# Source for optimization, current development version
emerge sys-kernel/gentoo-kernel
```

### Local Kernel Builds

For custom kernels:

```bash
# Build from /usr/src/linux
cd /usr/src/linux
cp /proc/config.gz .
gunzip config.gz
mv config .config
make oldconfig
make -j$(nproc)
make modules_install
make install
```

## See Also

- [Installation Guide](INSTALLATION_GUIDE.md)
- [Optimization Guide](OPTIMIZATION_GUIDE.md)
- [Gentoo Kernel/Upgrade Guide](https://wiki.gentoo.org/wiki/Kernel/Upgrade)
- [Gentoo Kernel Configuration](https://wiki.gentoo.org/wiki/Kernel/Configuration)
