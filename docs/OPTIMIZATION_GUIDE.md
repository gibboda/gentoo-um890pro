# System Optimization Guide for UM890 Pro

This guide covers comprehensive system optimizations for the Minisforum EliteMini UM890 Pro running Gentoo Linux with AI/ML workloads.

## Table of Contents

1. [Kernel Optimization](#kernel-optimization)
2. [Memory Optimization](#memory-optimization)
3. [Storage Optimization](#storage-optimization)
4. [GPU Optimization](#gpu-optimization)
5. [AI/ML Workload Optimization](#aiml-workload-optimization)
6. [Blender Cycles Optimization](#blender-cycles-optimization)
7. [ComfyUI/SDXL Optimization](#comfyuisdxl-optimization)
8. [Power Management](#power-management)
9. [Network Optimization](#network-optimization)

## Kernel Optimization

### Boot Configuration with rEFInd

The system uses rEFInd bootloader which auto-detects kernels in `/boot`:

**Dual-kernel mode** (INSTALL_DUAL_KERNEL="yes"):
- Kernel A (fallback): `/boot/vmlinuz-<VERSION>-gentoo-dist`
- Kernel B (tuned): `/boot/vmlinuz-<VERSION>-um890-tuned`

**Single-kernel mode**:
- Single kernel: `/boot/vmlinuz-<VERSION>-gentoo(-dist)`

### Kernel Command Line Parameters

Add these to `/boot/refind_linux.conf`:

```
amd_pstate=active
amd_iommu=on
iommu=pt
mitigations=auto
transparent_hugepage=madvise
```

Example `/boot/refind_linux.conf`:
```bash
"Gentoo (Btrfs subvol=@)"  "root=UUID=<UUID> rootfstype=btrfs rootflags=subvol=@ rw amd_pstate=active amd_iommu=on transparent_hugepage=madvise"
```

### Kernel Configuration

For custom source kernels or Kernel B in dual-kernel mode, ensure these AI/ML-optimized options:

```
CONFIG_AMDGPU=y
CONFIG_DRM_AMDGPU=y
CONFIG_HSA_AMD=y
CONFIG_HSA_AMD_SVM=y
CONFIG_ZONE_DEVICE=y
CONFIG_HMM_MIRROR=y
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_ZRAM=y
CONFIG_ZSWAP=y
CONFIG_BTRFS_FS=y
CONFIG_ZFS=m
```

### Performance Governor

```bash
# Set CPU governor to performance for consistent speeds
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Or use schedutil for balanced performance
echo schedutil | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

Create systemd service for automatic governor setting:

```bash
# /etc/systemd/system/cpu-governor.service
[Unit]
Description=Set CPU Governor to Performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'

[Install]
WantedBy=multi-user.target
```

## Memory Optimization

### DDR5-5600 Crucial CT48G56C46S5 Configuration

With 2× 48GB DDR5-5600 modules (96GB total), optimize for bandwidth and latency:

```bash
# Verify memory configuration
sudo dmidecode -t memory | grep -E "(Size|Speed|Type|Manufacturer|Part Number)"

# Expected output should show:
# - Size: 48 GB (x2)
# - Speed: 5600 MT/s
# - Type: DDR5
# - Manufacturer: Crucial
# - Part Number: CT48G56C46S5
```

### Memory Timings Optimization

```bash
# Check current memory timings
sudo dmidecode -t memory | grep -i latency

# Monitor memory bandwidth
sudo emerge sys-apps/pciutils
sudo pcm-memory.x

# Or use simpler tools
free -h && cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|Cached|SwapTotal)"
```

### Huge Pages

For 96GB system, configure generous huge page allocation:

```bash
# Enable transparent huge pages with madvise mode
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo defer | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# For large AI models, allocate 8GB of huge pages (4096 pages of 2MB each)
echo 4096 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Or allocate 1GB huge pages (8 pages of 1GB each) for very large models
echo 8 | sudo tee /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages
```

Make persistent in `/etc/sysctl.d/90-hugepages.conf`:

```
# 2MB huge pages (8GB total)
vm.nr_hugepages=4096

# Allow all users to use huge pages
vm.hugetlb_shm_group=0

# Increase max map count for large allocations
vm.max_map_count=262144

# Optimize for large memory systems
vm.min_free_kbytes=524288
```

### Memory Limits for AI Workloads

```bash
# Increase memory limits for user processes
# /etc/security/limits.conf
*               soft    memlock         unlimited
*               hard    memlock         unlimited
*               soft    nofile          1048576
*               hard    nofile          1048576
```

### ZRAM Configuration

Optimized zram settings for 96GB DDR5-5600 system in `/etc/conf.d/zram`:

```bash
# Use 24GB for zram (1/4 of 96GB RAM)
# With DDR5-5600's high bandwidth, zram is very efficient
ZRAM_SIZE="24G"
ZRAM_COMP_ALGO="zstd"
ZRAM_SWAP_PRIORITY="100"
```

Alternative configuration for AI workloads that may need more swap:

```bash
# Use 32GB for zram (1/3 of RAM) for heavier AI workloads
ZRAM_SIZE="32G"
ZRAM_COMP_ALGO="zstd"
ZRAM_SWAP_PRIORITY="100"
```

### Swappiness Tuning

```bash
# With 96GB RAM, be conservative with swapping
echo 5 | sudo tee /proc/sys/vm/swappiness

# Make persistent in /etc/sysctl.d/90-swappiness.conf
vm.swappiness=5
vm.vfs_cache_pressure=50

# For systems with large datasets that benefit from cache
vm.dirty_ratio=10
vm.dirty_background_ratio=5

# Optimize for DDR5 bandwidth
vm.zone_reclaim_mode=0
```

## Storage Optimization

### Btrfs Optimizations

Mount options in `/etc/fstab`:

```
UUID=<uuid>  /  btrfs  noatime,compress=zstd:3,ssd,space_cache=v2,commit=120,discard=async,subvol=@  0 0
```

Enable automatic defragmentation:

```bash
# /etc/systemd/system/btrfs-defrag.service
[Unit]
Description=Btrfs filesystem defragmentation

[Service]
Type=oneshot
ExecStart=/bin/btrfs filesystem defragment -r -v -czstd /

[Install]
WantedBy=multi-user.target
```

```bash
# /etc/systemd/system/btrfs-defrag.timer
[Unit]
Description=Weekly Btrfs defragmentation

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
```

### ZFS Optimizations for AI Models

```bash
# Optimize ZFS for large sequential reads (AI models)
zfs set primarycache=metadata tank/ai-models
zfs set recordsize=1M tank/ai-models
zfs set compression=lz4 tank/ai-models
zfs set atime=off tank/ai-models
zfs set sync=disabled tank/ai-models  # For non-critical data only

# Set ARC size limits (in bytes)
echo 32G > /sys/module/zfs/parameters/zfs_arc_max
echo 16G > /sys/module/zfs/parameters/zfs_arc_min
```

Make ZFS ARC limits persistent in `/etc/modprobe.d/zfs.conf`:

```
options zfs zfs_arc_max=34359738368
options zfs zfs_arc_min=17179869184
```

### NVMe Optimizations

#### Crucial P3 Plus CT4000P3PSSD8 Specific

The Crucial P3 Plus uses HMB (Host Memory Buffer) instead of onboard DRAM cache:

```bash
# /etc/udev/rules.d/60-nvme-crucial-p3.rules
# Optimize scheduler and HMB for Crucial P3 Plus
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTRS{model}=="CT4000P3PSSD8", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTRS{model}=="CT4000P3PSSD8", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTRS{model}=="CT4000P3PSSD8", ATTR{queue/read_ahead_kb}="2048"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTRS{model}=="CT4000P3PSSD8", ATTR{queue/max_sectors_kb}="1024"

# Increase HMB (Host Memory Buffer) size for DRAM-less design
# Default is usually 128MB, increase to 256MB for better performance
ACTION=="add", KERNEL=="nvme[0-9]", ATTRS{model}=="CT4000P3PSSD8", ATTR{device/hmb_size}="262144"
```

#### Generic NVMe Settings

```bash
# /etc/udev/rules.d/60-nvme.rules
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="1024"
```

#### NVMe Power Management for PCIe 4.0

```bash
# /etc/modprobe.d/nvme.conf
# Disable APST (Autonomous Power State Transition) if experiencing latency spikes
# options nvme_core default_ps_max_latency_us=0

# For better power efficiency (may increase latency slightly):
options nvme_core default_ps_max_latency_us=5500
```

## GPU Optimization

### AMDGPU Driver Configuration

Create `/etc/modprobe.d/amdgpu.conf`:

```
options amdgpu ppfeaturemask=0xffffffff
options amdgpu gpu_recovery=1
options amdgpu vm_update_mode=3
options amdgpu aspm=0
```

### Mesa Configuration

Set environment variables in `/etc/profile.d/mesa.sh`:

```bash
export RADV_PERFTEST=gpl,nggc
export RADV_DEBUG=zerovram
export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
```

### GPU Clock Control

```bash
# Enable manual GPU clock control
echo manual | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level

# Set to high performance
echo high | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level
```

## AI/ML Workload Optimization

### PyTorch Configuration

Create `~/.config/pytorch/config.py`:

```python
import torch

# Configure PyTorch for ROCm
torch.backends.cuda.matmul.allow_tf32 = True
torch.backends.cudnn.allow_tf32 = True
torch.backends.cudnn.benchmark = True

# For UMA systems
torch.cuda.set_per_process_memory_fraction(0.8)  # Leave 20% for system
```

### ROCm Environment Variables

Add to `/etc/profile.d/rocm.sh`:

```bash
export ROCM_PATH=/usr
export HIP_PATH=/usr
export HSA_OVERRIDE_GFX_VERSION=11.0.3
export GPU_DEVICE_ORDINAL=0
export HIP_VISIBLE_DEVICES=0

# Memory optimizations for UMA
export PYTORCH_HIP_ALLOC_CONF=max_split_size_mb:512,garbage_collection_threshold:0.9
export TORCH_HOME=/data/ai-models/torch-cache
export HF_HOME=/data/ai-models/huggingface-cache

# Enable ROCm profiling (optional)
# export HSA_TOOLS_LIB=/opt/rocm/lib/libroctracer64.so
```

### Hugging Face Optimizations

Create `~/.cache/huggingface/accelerate/default_config.yaml`:

```yaml
compute_environment: LOCAL_MACHINE
distributed_type: 'NO'
downcast_bf16: 'no'
gpu_ids: all
machine_rank: 0
main_training_function: main
mixed_precision: fp16
num_machines: 1
num_processes: 1
rdzv_backend: static
same_network: true
tpu_env: []
tpu_use_cluster: false
tpu_use_sudo: false
use_cpu: false
```

## Blender Cycles Optimization

### Blender Preferences

Create `~/.config/blender/3.6/config/userpref.blend` with these settings via Python:

```python
import bpy

prefs = bpy.context.preferences

# Set Cycles device
cycles_prefs = prefs.addons['cycles'].preferences
cycles_prefs.compute_device_type = 'HIP'
cycles_prefs.get_devices()

# Enable all HIP devices
for device in cycles_prefs.devices:
    if device.type == 'HIP':
        device.use = True
        print(f"Enabled device: {device.name}")

# Scene render settings
for scene in bpy.data.scenes:
    scene.cycles.device = 'GPU'
    scene.cycles.tile_size = 256
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.01
    scene.cycles.use_denoising = True
    scene.cycles.denoiser = 'OPENIMAGEDENOISE'
    
    # Memory optimizations for UMA
    scene.render.use_persistent_data = True
    scene.cycles.debug_use_spatial_splits = True
    scene.cycles.debug_use_hair_bvh = True

bpy.ops.wm.save_userpref()
```

### Environment Variables for Blender

Add to `~/.bashrc` or `/etc/profile.d/blender.sh`:

```bash
export CYCLES_DEVICE=HIP
export BLENDER_USER_SCRIPTS=/data/ai-models/blender-scripts
export BLENDER_USER_CONFIG=~/.config/blender
```

## ComfyUI/SDXL Optimization

### ComfyUI Launch Configuration

Optimized launch script at `/data/ai-models/ComfyUI/launch-uma-optimized.sh`:

```bash
#!/bin/bash

export PYTORCH_HIP_ALLOC_CONF=max_split_size_mb:512
export TORCH_HOME=/data/ai-models/torch-cache
export HF_HOME=/data/ai-models/huggingface-cache
export HSA_OVERRIDE_GFX_VERSION=11.0.3

cd "$(dirname "$0")"
source venv/bin/activate

python main.py \
    --lowvram \
    --preview-method auto \
    --use-split-cross-attention \
    --disable-xformers \
    --fp16-vae \
    --force-fp16 \
    --listen 0.0.0.0 \
    --port 8188 \
    --extra-model-paths-config extra_model_paths.yaml
```

### SDXL Model Configuration

Create optimized config for SDXL in `models/configs/sdxl-uma.yaml`:

```yaml
model:
  base_learning_rate: 1.0e-04
  target: sgm.models.diffusion.DiffusionEngine
  params:
    scale_factor: 0.13025
    disable_first_stage_autocast: True
    
    denoiser_config:
      target: sgm.modules.diffusionmodules.denoiser.DiscreteDenoiser
      params:
        num_idx: 1000
        
    network_config:
      target: sgm.modules.diffusionmodules.openaimodel.UNetModel
      params:
        use_checkpoint: True
        use_fp16: True
        attention_resolutions: [4, 2]
        channel_mult: [1, 2, 4]
        transformer_depth: 2
        use_linear_in_transformer: True
        
    first_stage_config:
      target: sgm.models.autoencoder.AutoencoderKL
      params:
        embed_dim: 4
        monitor: val/rec_loss
        use_fp16: True
        
    conditioner_config:
      target: sgm.modules.GeneralConditioner
      params:
        emb_models:
          - is_trainable: False
            input_key: txt
            ucg_rate: 0.1
            use_fp16: True
```

### Memory-Efficient Sampling

Create custom sampler configuration:

```python
# models/samplers/uma_efficient.py
import torch

class UMAEfficientSampler:
    """Memory-efficient sampler for UMA systems"""
    
    def __init__(self):
        self.vae_decode_chunk_size = 1
        self.enable_vae_slicing = True
        self.enable_attention_slicing = True
        
    def configure_model(self, model):
        # Enable slicing for memory efficiency
        if hasattr(model, 'enable_vae_slicing'):
            model.enable_vae_slicing()
        if hasattr(model, 'enable_attention_slicing'):
            model.enable_attention_slicing(slice_size=1)
        
        # Use CPU offloading for very large models
        # model.enable_sequential_cpu_offload()
        
        return model
```

## Power Management

### TLP Configuration

Install and configure TLP for laptop-mode power savings:

```bash
emerge sys-power/tlp

# /etc/tlp.conf optimizations
CPU_SCALING_GOVERNOR_ON_AC=schedutil
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0
SCHED_POWERSAVE_ON_AC=0
SCHED_POWERSAVE_ON_BAT=1
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto
PCIE_ASPM_ON_AC=performance
PCIE_ASPM_ON_BAT=powersupersave
```

### Custom Power Profile

Create `/usr/local/bin/power-profile`:

```bash
#!/bin/bash

case "$1" in
    performance)
        echo "Setting performance profile..."
        echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
        echo high > /sys/class/drm/card0/device/power_dpm_force_performance_level
        echo 0 > /sys/class/drm/card0/device/power_dpm_state
        ;;
    balanced)
        echo "Setting balanced profile..."
        echo schedutil > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
        echo auto > /sys/class/drm/card0/device/power_dpm_force_performance_level
        ;;
    powersave)
        echo "Setting powersave profile..."
        echo powersave > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
        echo low > /sys/class/drm/card0/device/power_dpm_force_performance_level
        ;;
    *)
        echo "Usage: $0 {performance|balanced|powersave}"
        exit 1
        ;;
esac
```

## Network Optimization

### NetworkManager Configuration

```ini
# /etc/NetworkManager/conf.d/99-performance.conf
[connection]
connection.stable-id=${CONNECTION}/${BOOT}
ipv6.dhcp-timeout=30

[device]
wifi.scan-rand-mac-address=no
```

### TCP/IP Tuning

Create `/etc/sysctl.d/90-network.conf`:

```
# Increase TCP buffer sizes for high-bandwidth applications
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

# Enable TCP window scaling
net.ipv4.tcp_window_scaling=1

# Increase the number of outstanding syn requests
net.ipv4.tcp_max_syn_backlog=8192

# Enable TCP Fast Open
net.ipv4.tcp_fastopen=3

# Disable slow start after idle
net.ipv4.tcp_slow_start_after_idle=0
```

## Monitoring and Profiling

### System Monitoring Tools

```bash
# Install monitoring tools
emerge sys-process/htop sys-process/atop app-admin/sysstat app-benchmarks/sysbench

# Enable sysstat
rc-update add sysstat default  # OpenRC
systemctl enable sysstat       # systemd
```

### GPU Monitoring

```bash
# Watch GPU usage
watch -n1 'radeontop -d - -l 1'

# Or use rocm-smi
watch -n1 rocm-smi
```

### Create monitoring dashboard script

```bash
#!/bin/bash
# /usr/local/bin/system-monitor

while true; do
    clear
    echo "=== UM890 Pro System Monitor ==="
    echo ""
    echo "CPU:"
    grep MHz /proc/cpuinfo | head -8
    echo ""
    echo "Memory:"
    free -h
    echo ""
    echo "GPU:"
    rocm-smi --showuse 2>/dev/null || echo "ROCm not available"
    echo ""
    echo "Temperatures:"
    sensors | grep -E "(temp|fan)"
    echo ""
    echo "Top processes:"
    ps aux --sort=-%mem | head -6
    sleep 2
done
```

## Quick Performance Checklist

After installation, verify these optimizations:

- [ ] CPU governor set appropriately
- [ ] Huge pages enabled
- [ ] ZRAM swap active and configured
- [ ] NVMe scheduler optimized
- [ ] GPU power management configured
- [ ] ROCm environment variables set
- [ ] ComfyUI launch script uses UMA flags
- [ ] Blender Cycles configured for HIP
- [ ] ZFS ARC limits set
- [ ] Monitoring tools installed

## Performance Testing

```bash
# CPU benchmark
sysbench cpu --threads=16 run

# Memory benchmark
sysbench memory --memory-total-size=10G run

# GPU compute test (after ROCm install)
/opt/rocm/bin/rocminfo

# Blender benchmark
blender --background --python benchmark.py

# Stable Diffusion benchmark
cd /data/ai-models/ComfyUI
python benchmark.py
```
