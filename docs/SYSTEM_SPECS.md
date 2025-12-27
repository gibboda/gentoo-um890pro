# Complete System Specifications

## Minisforum EliteMini UM890 Pro - Full Build Specification

### System Base
- **Model**: Minisforum EliteMini UM890 Pro
- **Form Factor**: Mini PC (approx. 130mm × 126mm × 46.9mm)
- **Chipset**: AMD Promontory21 (embedded in CPU)

### Processor
- **CPU**: AMD Ryzen 9 8945HS
  - Architecture: Zen 4
  - Cores/Threads: 8C/16T
  - Base Clock: 4.0 GHz
  - Boost Clock: Up to 5.2 GHz
  - L2 Cache: 8MB
  - L3 Cache: 16MB
  - TDP: 35W - 54W (configurable)
  - Process: TSMC 4nm

### Graphics
- **iGPU**: AMD Radeon 780M
  - Architecture: RDNA 3
  - Compute Units: 12 CUs
  - Stream Processors: 768
  - Graphics Clock: Up to 2,800 MHz
  - Architecture ID: gfx1103
  - ROCm Support: Yes (gfx11)
  - Vulkan: 1.3
  - OpenGL: 4.6
  - DirectX: 12 Ultimate

### Memory (2× SO-DIMM Slots)
- **Module 1**: Crucial 48GB DDR5-5600 (CT48G56C46S5)
  - Capacity: 48GB
  - Type: DDR5 SO-DIMM (260-pin)
  - Speed: 5600 MT/s (PC5-44800)
  - CAS Latency: CL46-45-45
  - Voltage: 1.1V
  - Unbuffered, Non-ECC
  
- **Module 2**: Crucial 48GB DDR5-5600 (CT48G56C46S5)
  - Capacity: 48GB
  - Type: DDR5 SO-DIMM (260-pin)
  - Speed: 5600 MT/s (PC5-44800)
  - CAS Latency: CL46-45-45
  - Voltage: 1.1V
  - Unbuffered, Non-ECC

- **Total Memory**: 96GB
- **Memory Bandwidth**: ~89.6 GB/s (dual-channel)
- **Architecture**: UMA (Unified Memory Architecture)

### Storage (2× M.2 2280 Slots)
- **Drive 1 (OS)**: Crucial P3 Plus 4TB (CT4000P3PSSD8)
  - Capacity: 4TB (3.7 TiB usable)
  - Interface: PCIe 4.0 x4
  - Protocol: NVMe 1.4
  - Controller: Phison PS5021-E21T
  - NAND: Micron 176-layer TLC
  - DRAM: None (HMB - Host Memory Buffer)
  - Sequential Read: Up to 4,800 MB/s
  - Sequential Write: Up to 4,100 MB/s
  - Random Read: Up to 600K IOPS
  - Random Write: Up to 750K IOPS
  - Endurance: 800 TBW
  - Warranty: 5 years
  
- **Drive 2 (Data/AI)**: Crucial P3 Plus 4TB (CT4000P3PSSD8)
  - Same specifications as Drive 1
  - Dedicated to ZFS pool for AI/ML datasets

- **Total Storage**: 8TB (7.4 TiB usable)

### Connectivity
- **Ethernet**: 2.5GbE (Realtek RTL8125B)
- **WiFi**: WiFi 6E (802.11ax, tri-band)
- **Bluetooth**: 5.3

### Ports & I/O
- **USB Type-A**: 4× USB 3.2 Gen 2 (10 Gbps)
- **USB Type-C**: 2× USB 4 (40 Gbps, DP Alt Mode, Power Delivery)
- **Display**: 2× HDMI 2.1, 2× USB-C with DP 1.4
- **Audio**: 3.5mm combo jack
- **SD Card**: SD 4.0 (UHS-II)

### Power
- **Power Supply**: 19V DC (external adapter, typically 120W)
- **Power Consumption**: 
  - Idle: ~15-20W
  - Typical: 35-54W
  - Peak: ~90-100W

### Operating System
- **OS**: Gentoo Linux (custom installation)
- **Kernel**: 
  - Dual-kernel mode (when INSTALL_DUAL_KERNEL="yes"):
    - Kernel A: gentoo-kernel-bin (stable fallback)
      - Naming: `<VERSION>-gentoo-dist` (e.g., `6.12.58-gentoo-dist`)
      - Boot: `/boot/vmlinuz-<VERSION>-gentoo-dist`
      - initramfs: `/boot/initramfs-<VERSION>-gentoo-dist.img`
    - Kernel B: gentoo-sources (custom tuned)
      - Naming: `<VERSION>-um890-tuned` (e.g., `6.12.58-um890-tuned`)
      - Boot: `/boot/vmlinuz-<VERSION>-um890-tuned`
      - initramfs: `/boot/initramfs-<VERSION>-um890-tuned.img`
  - Single-kernel mode (default):
    - gentoo-kernel-bin OR gentoo-kernel with standard naming
- **Init System**: OpenRC (default) or systemd
- **Desktop**: KDE Plasma 6 with Wayland
- **Bootloader**: rEFInd

### Filesystem Configuration
- **OS Drive (NVMe0)**:
  - Filesystem: Btrfs
  - Layout: Subvolumes for /, /home, /var, snapshots
  - Compression: zstd:3
  - Mount options: noatime, ssd, space_cache=v2
  
- **Data Drive (NVMe1)**:
  - Filesystem: ZFS
  - Pool name: tank
  - Datasets: data, backup, ai-models
  - Compression: lz4
  - Special: ai-models uses 1M recordsize

### AI/ML Stack
- **GPU Compute**: ROCm 5.7+
- **Frameworks**: PyTorch with HIP support
- **Applications**: 
  - ComfyUI (Stable Diffusion workflow)
  - SDXL (Stable Diffusion XL)
  - Transformers (Hugging Face)
- **Optimization**: UMA-specific memory management

### 3D Rendering
- **Software**: Blender 3.6+
- **Renderer**: Cycles with HIP support
- **GPU Backend**: HIP (ROCm)
- **Optimizations**: 
  - 256x256 tiles for UMA
  - Adaptive sampling enabled
  - Persistent data mode

### Performance Characteristics

#### Memory Bandwidth
- **System**: ~89.6 GB/s (DDR5-5600 dual-channel)
- **Available to iGPU**: Shared with CPU
- **Effective for AI**: 70-80 GB/s under mixed workload

#### Storage Performance
- **Sequential Read**: ~9,600 MB/s (both drives)
- **Sequential Write**: ~8,200 MB/s (both drives)
- **Random 4K**: >1M IOPS combined

#### Compute Performance
- **CPU**: ~25,000 PassMark score (est.)
- **GPU (OpenCL)**: ~50,000 OpenCL score (est.)
- **GPU (Vulkan)**: Similar to GTX 1650 GDDR6

### Thermal Management
- **Cooling**: Active cooling with intelligent fan curve
- **CPU TDP**: 35-54W configurable
- **Thermal Throttle**: ~95°C (CPU), ~100°C (GPU)
- **Typical Temps**: 
  - Idle: 35-45°C
  - Load: 70-85°C

### Use Case Optimization

#### AI/ML Workloads
- Large model inference (up to 70B parameters)
- Stable Diffusion image generation
- Fine-tuning smaller models (<13B)
- Multi-modal AI pipelines

#### Content Creation
- 4K video editing
- 3D modeling and rendering
- Photo editing and RAW processing
- Game development

#### Development
- Software compilation
- Container/VM hosting
- Code IDE and debugging
- Multiple development environments

### Benchmarks (Expected)

#### CPU
- Cinebench R23 Multi: ~19,000 pts
- Geekbench 6 Single: ~2,600 pts
- Geekbench 6 Multi: ~13,500 pts

#### GPU
- 3DMark Time Spy: ~3,500 pts
- Blender Cycles (BMW27): ~4-5 min
- Stable Diffusion XL: ~15-20 sec/image (512×512)

#### Memory
- AIDA64 Read: ~85,000 MB/s
- AIDA64 Write: ~80,000 MB/s
- AIDA64 Copy: ~80,000 MB/s
- Latency: ~85-95 ns

#### Storage (per drive)
- CrystalDiskMark Seq Q32T1 Read: ~4,800 MB/s
- CrystalDiskMark Seq Q32T1 Write: ~4,100 MB/s
- 4K Random Read: ~60 MB/s
- 4K Random Write: ~150 MB/s

### Power Efficiency
- Performance per Watt: Excellent
- Idle power: Very low (~15W)
- Load efficiency: ~85-90%
- Thermal efficiency: Good airflow design

### Total System Cost (Components Only)
- **Base System**: ~$700-800 (UM890 Pro barebone)
- **RAM** (2× 48GB): ~$250-300
- **Storage** (2× 4TB): ~$400-450
- **Total**: ~$1,350-1,550

### Recommended Operating Conditions
- **Temperature**: 10-35°C ambient
- **Humidity**: 20-80% non-condensing
- **Clearance**: 50mm on all ventilated sides
- **Mounting**: Horizontal (preferred) or vertical with stand

## Summary

This is a high-performance, compact workstation optimized for AI/ML development, 3D content creation, and software development. The combination of Zen 4 CPU, RDNA 3 iGPU, 96GB of fast DDR5 memory, and 8TB of NVMe storage provides excellent performance for a wide range of professional workloads in a small form factor.

The UMA architecture is particularly well-suited for AI workloads requiring large model storage, as the 96GB of system RAM can be efficiently shared between CPU and GPU operations without the overhead of PCIe transfers.
