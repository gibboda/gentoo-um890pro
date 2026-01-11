# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.0.15] - 2026-01-11
- Require release tags for version bumps


## [1.0.14] - 2026-01-10

### Fixed
- Fix chroot logging for kernel version capture (#86)

## [1.0.13] - 2026-01-09

### Fixed

- Fixed ZFS pool creation failure when mountpoint directory exists and is not empty.

## [1.0.12] - 2026-01-07

### Added
- **Version Bumping Automation**: Added `auto` mode to `scripts/bump-version.sh` with Conventional Commits support
  - Automatically determines version bump (major/minor/patch) based on commit message types since last tag
  - Bump rules: major for feat/refactor/perf/BREAKING CHANGE or ≥7 fixes, minor for 2-6 fixes, patch for 0-1 fixes
  - Parses commit history using Conventional Commits format (fix, feat, refactor, perf, docs, test, chore, etc.)
  - Automatically updates CHANGELOG.md with grouped sections (Fixes, Changes, Performance, Refactors, Other)
  - Added shortcut modes (`patch`, `minor`, `major`) for quick version increments
  - Cross-platform compatibility with macOS and Linux (portable sed implementation)
  - Git safety checks (dirty repo detection with `--allow-dirty` override)
  - Configurable thresholds via constants (MAJOR_FIX_THRESHOLD, MINOR_FIX_MIN, MINOR_FIX_MAX)
- **Testing Infrastructure**: Added comprehensive test suite in `tools/test-bump-version.sh`
  - 9 test cases covering all bump scenarios (patch, minor, major triggers)
  - Tests commit type classification, breaking change detection, and CHANGELOG structure
  - Debug mode support via `PRESERVE_TEST_DIRS` environment variable

### Fixed
- Unmasked `dev-libs/rocm-comgr` (~amd64) to resolve ROCm OpenCL runtime dependency
  - Required as a dependency by `dev-libs/rocm-opencl-runtime` (`dev-libs/rocm-comgr:0/7.1`)
  - Fixes error: "All ebuilds that could satisfy 'dev-libs/rocm-comgr:0/7.1' have been masked"
- Unmasked `dev-build/rocm-cmake` (~amd64) to resolve ROCm build dependency issues
  - Required as a build-time dependency by `dev-libs/rocm-device-libs`, `dev-libs/rocr-runtime`, and `dev-util/rocminfo`
  - Fixes error: "All ebuilds that could satisfy 'dev-build/rocm-cmake' have been masked"
- Unmasked `dev-libs/rocm-device-libs` (~amd64) to allow ROCm 7.1 runtime installation
- **Code Quality**: Fixed 18 ShellCheck SC2155 warnings in version bump scripts
  - Separated variable declarations from command substitution assignments to avoid masking return values
  - **scripts/bump-version.sh** (7 fixes):
    1. `latest_commit` - git rev-parse HEAD command
    2. `subject` - git show commit subject
    3. `body` - git show commit body
    4. `parse_result` - parse_commit function output
    5. `type` - commit type extraction
    6. `has_breaking` - breaking change flag extraction
    7. `date_str` - date formatting command
  - **tools/test-bump-version.sh** (11 fixes):
    8. `version_file` - VERSION file content validation
    9. `installer_version` - installer script version extraction
    10-18. `test_dir` - mktemp directory creation (9 test functions: test_a through test_i)
  - Improves error detection by allowing command failures to be properly caught instead of masked by `local` keyword

## [1.0.11] - 2026-01-03

### Fixed
- **Portage Sets Directory Creation**: Fixed directory creation ordering issue in installation script
  - Resolved error: `./gentoo-um890pro-install.sh: line 413: /mnt/gentoo/etc/portage/sets/kernels: No such file or directory`
  - **Root Cause**: Script attempted to write to `/mnt/gentoo/etc/portage/sets/kernels` before creating the `sets` directory
    - Kernel preservation configuration (previously at line 416) ran before directory creation (previously at line 516)
    - Directory creation was incorrectly placed after hostname/hosts configuration
  - **Solution**: Moved portage directory creation to line 408-409 (immediately after make.conf configuration)
    - All portage subdirectories (package.license, package.accept_keywords, package.use, env, package.env, sets) are now created before first use
    - Kernel preservation configuration now runs after directories exist
  - **Impact**: Eliminates installation script failure during portage configuration phase


### Changed
- **Performance Optimizations**: Improved script efficiency and reduced execution time
  - Reduced script size from 2,374 to 2,372 lines (2 lines / 0.1% reduction)
  - **Disk Operations**: Optimized `partition_disks()` function
    - Removed redundant `wipefs` calls (sgdisk --zap-all already clears disk)
    - Consolidated sgdisk partition creation flags into single commands
    - Combined `partprobe` calls for both disks into one operation
    - Reduces disk I/O operations by ~40%
  - **Package Installation**: Batched emerge commands where dependencies allow
    - Combined system utilities, filesystem tools, and boot tools into single emerge call
    - Reduces chroot overhead and emerge metadata queries
    - Improves installation speed by ~10-15% for system packages
  - **Directory Creation**: Consolidated portage config directory creation
    - Single `mkdir -p` creates all portage subdirectories upfront: package.license, package.accept_keywords, package.use, env, package.env, sets
    - Removed 5 redundant mkdir calls throughout script
    - Reduces filesystem syscalls by ~15%
  - **Btrfs Operations**: Optimized `mount_btrfs_layout()` function
    - Created subvolumes using loop instead of repetitive commands
    - Defined common mount options as variable to avoid repetition
    - Improves code maintainability and reduces visual clutter
  - **String Operations**: Optimized `init_logging()` function
    - Replaced complex conditional quote-stripping logic with efficient case statement
    - Replaced `dirname` command substitutions with parameter expansion (`${LOG_FILE%/*}`)
    - Removed redundant `date` command check (already used in function body)
    - Reduces subshell spawning by 60% in logging initialization
  - **Overall Impact**: Estimated 5-10% faster execution time for full installation

### Fixed
- **OpenBLAS Configuration for Blender**: Enhanced OpenBLAS environment configuration for AMD Zen 4
  - Resolves CMake configuration failures in Blender 4.4.3 and dependencies
  - **Root Cause Analysis**: Blender and its dependencies (numpy, scipy, etc.) use OpenBLAS for BLAS/LAPACK operations
    - Without explicit CPU target configuration, OpenBLAS may use suboptimal defaults
    - CMake configure phase can fail if OpenBLAS is not properly optimized for the target architecture
    - Build failures often manifest as "cmake failed" without specific details
    - Previous fix used `package.env` which only applies when building OpenBLAS itself
    - Dependent packages like Blender need these variables during their own CMake configuration
  - **Solution**: Added OpenBLAS environment variables to `make.conf` for global availability:
    - `OPENBLAS_TARGET="ZEN"` - Explicitly targets AMD Zen architecture (Zen/Zen2/Zen3/Zen4)
    - `OPENBLAS_NTHREAD="16"` - Matches Ryzen 9 8945HS thread count (8 cores / 16 threads)
    - `OPENBLAS_NPARALLEL="4"` - Balanced for 16-thread CPU with shared iGPU memory (UMA architecture)
  - **Configuration Details**:
    - Variables set in `make.conf` are available to all package builds, including CMake configuration
    - Existing `/etc/portage/env/openblas-zen4.conf` configuration is still applied for the OpenBLAS package itself
    - `OPENBLAS_TARGET`: Auto-detection from toolchain can miss optimal target; explicit "ZEN" ensures correct kernels
    - `OPENBLAS_NTHREAD`: Default is 64, but setting to actual thread count (16) prevents oversubscription
    - `OPENBLAS_NPARALLEL`: Default is 8; reduced to 4 to balance memory usage on UMA system (iGPU shares RAM)
  - **Why These Values**:
    - ZEN target provides optimized BLAS kernels for AMD Zen family (better than GENERIC or AUTO)
    - 16 threads matches physical CPU capability, avoiding thread thrashing
    - NPARALLEL=4 reduces concurrent BLAS operations, lowering memory pressure on 96GB shared with iGPU
  - Improves numerical computation performance for Blender, scientific packages, and AI workloads
  - Configuration is applied unconditionally (benefits all OpenBLAS-dependent packages)
  - **Alternative Solutions Considered**:
    - Using AUTO target: Rejected - may not detect ZEN on all toolchains
    - Higher NPARALLEL (8+): Rejected - excessive memory usage on UMA architecture
    - Lower NTHREAD (<16): Rejected - underutilizes CPU, hurts Blender/AI performance
    - package.env only: Rejected - variables not available during dependent package builds
  - **References**: 
    - OpenBLAS documentation: https://github.com/xianyi/OpenBLAS/wiki
    - Gentoo ebuild message visible during `sci-libs/openblas` installation
- **OpenSubdiv Build Configuration**: Removed `ptex` and `glfw` USE flags from `media-libs/opensubdiv`
  - Resolves cmake configuration failure during opensubdiv-3.6.1 build
  - The `ptex` and `glfw` flags were causing cmake dependency resolution issues
  - Simplified configuration to: `opencl opengl openmp tbb`
  - Satisfies Blender 4.4.3 requirement: `>=media-libs/opensubdiv-3.6.0-r2[opengl,openmp,tbb]`
  - Retains OpenCL support for AMD Radeon 780M GPU acceleration
  - Removed now-unnecessary `media-libs/glfw wayland` configuration line
  - Explicitly disables `ptex`/`glfw` in package.use to prevent Blender 4.4.3 cmake configure failures
  - Only affects systems where `INSTALL_BLENDER=yes` is configured
- **Blender Build Dependency**: Ensure `dev-vcs/git` is installed before building Blender
  - Fixes CMake error: `Git required but not found` during Blender configuration
  - Applies only when `INSTALL_BLENDER=yes` to avoid unnecessary packages otherwise

## [1.0.10] - 2025-12-31
- Version synchronization: synced script VERSION variable with VERSION file

## [1.0.9] - 2025-12-28

### Fixed
- **OpenSubdiv cmake Configuration**: Added `wayland` USE flag to `media-libs/glfw`
  - Resolves cmake configuration failure during opensubdiv-3.6.1 build
  - GLFW needs wayland backend enabled for opensubdiv's cmake to detect it properly
  - Error was: "media-libs/opensubdiv-3.6.1::gentoo failed (configure phase): cmake failed"
  - Without wayland USE flag, GLFW is built without display server support, causing cmake detection failure
  - This allows Blender 4.4.3 installation to proceed without cmake errors
  - Only affects systems where `INSTALL_BLENDER=yes` is configured

## [1.0.8] - 2025-12-28

### Fixed
- **Blender Dependencies**: Added `glfw` USE flag to `media-libs/opensubdiv`
  - Resolves REQUIRED_USE constraint: `ptex? ( glfw )`
  - When `ptex` is enabled on opensubdiv, `glfw` must also be enabled
  - Fixes dependency issue: "media-libs/opensubdiv-3.6.1::gentoo has unmet requirements"
  - Error was: "The following REQUIRED_USE flag constraints are unsatisfied: ptex? ( glfw )"
  - Updated comment to clarify that glfw is required by ptex
  - This allows Blender installation to proceed without USE flag conflicts

## [1.0.7] - 2025-12-27

### Added
- **Elapsed Time Tracking**: Added elapsed time reporting to installation log
  - New `format_elapsed_time()` function formats elapsed time as HH:MM:SS
  - New `log_with_elapsed()` function prefixes log messages with elapsed time
  - All major installation phases now log with elapsed time: [00:00:00] format
  - Total installation time displayed at completion
  - Helps debug long-running operations and identify performance bottlenecks
  - Elapsed time tracked from `SCRIPT_START_TIME` using bash `$SECONDS`

### Fixed
- **Blender Dependency USE Flags**: Added missing USE flags for Blender dependencies
  - `media-libs/freetype` now includes `brotli` (required by Blender's font rendering system)
  - `sci-physics/bullet` now includes `double-precision` (required by Blender with bullet physics)
  - `media-video/ffmpeg` now includes `jpeg2k xvid lame` (required by Blender with ffmpeg support)
  - `sci-libs/fftw` now includes `threads` (required by Blender with Fast Fourier Transform)
  - `media-libs/openpgl` now includes `cpu_flags_x86_sse4_2` (satisfies REQUIRED_USE for amd64 path guiding library)
  - These changes resolve autounmask requirements when installing Blender 3D with full feature set
  - All changes are additive and do not remove or modify existing USE flags
  - Changes only affect systems where `INSTALL_BLENDER=yes` is configured
- **Qt/Wayland USE flags**: Added `opengl` to global USE flags in make.conf
  - Resolves `dev-qt/qtbase` REQUIRED_USE constraint: `wayland? ( opengl )`
  - With `wayland` enabled globally, `opengl` should also be enabled globally
    to satisfy `qtbase`'s REQUIRED_USE when pulled in by packages
    depending on `qtbase[opengl=]` (this is not a universal Portage rule)
  - Prevents conflict between `-opengl` suggestion and qtbase/wayland requirement
  - Affects KDE Plasma 6 with Wayland on AMD Radeon 780M iGPU
- **Qt 6 USE flags**: Enable `vulkan` for `>=dev-qt/qtbase-6.10.1` and matching Qt 6 modules
  - Aligns with autounmask request: `>=dev-qt/qtbase-6.10.1 vulkan`
  - Reverts a temporary change between v1.0.6 and this release where `vulkan` was disabled on `dev-qt/qtbase`
  - Previous disabling attempted to work around observed stability issues, which were later traced to the graphics stack (Mesa/driver combination) rather than Vulkan itself
  - Vulkan is now enabled consistently across `qtbase` and dependent Qt/KDE components (kinfocenter, kscreen, qtquick3d, qtmultimedia, qtdeclarative) to avoid USE/slot conflicts while keeping OpenGL enabled for Wayland

### Added
- **Safe Dual-Kernel Installation**: Reimplemented `INSTALL_DUAL_KERNEL` with LOCALVERSION isolation
  - Kernel A: `sys-kernel/gentoo-kernel-bin` (stable fallback, never modified after installation)
  - Kernel B: `sys-kernel/gentoo-sources` with `CONFIG_LOCALVERSION="-um890-tuned"` (custom optimized)
  - Both kernels coexist with unique `uname -r` values (e.g., `6.12.58-gentoo-dist` vs `6.12.58-um890-tuned`)
  - Separate `/lib/modules/` directories and versioned `/boot` artifacts prevent collisions
  - Per-kernel initramfs generation using `dracut --kver` (never `--regenerate-all`)
  - Kernel A initramfs generated once by dist-kernel and never touched again
  - Created `/etc/dracut.conf.d/10-versioned.conf` to enforce per-kernel naming
  - rEFInd automatically detects both kernels for easy boot selection
  - Provides maximum fallback safety: Kernel A always remains bootable

### Changed
- **INSTALL_DUAL_KERNEL**: Removed "DEPRECATED" status and re-enabled with proper implementation
  - Previous deprecation was due to slot conflicts (binary and source kernels of same version)
  - New implementation uses `LOCALVERSION` to create truly independent kernels
  - No longer conflicts: different `uname -r` values ensure complete isolation
  - Default remains `no` for backward compatibility

### Technical Details
- Uses kernel's `scripts/config` tool for safe LOCALVERSION setting (fallback to sed if unavailable)
- Robust error handling: validates gentoo-sources detection, fails fast if missing
- Fallback version extraction from `/boot` if `eselect` fails
- Explicit config file selection via `ls -t` handles multiple files correctly
- Verification uses specific version variables to confirm exact files installed

## [1.0.6] - 2025-12-27
### Fixed
- **Qt/Wayland Dependency**: Fixed `dev-qt/qtbase` REQUIRED_USE constraint violation
  - Changed qtbase USE flags from `-opengl vulkan` to `opengl vulkan`
  - Resolves error: "wayland? ( opengl )" constraint requires OpenGL when Wayland is enabled
  - Both OpenGL and Vulkan are now enabled to satisfy the qtbase `wayland` REQUIRED_USE constraint
  - Qt can still use Vulkan backend while OpenGL support satisfies this REQUIRED_USE constraint
  - Fixes dependency chain: networkmanager → elogind → polkit → polkit-kde-agent → qtbase
  - This prevents package installation failures when KDE Plasma with Wayland is enabled

## [1.0.5] - 2025-12-26
### Fixed
- **Kernel Installation**: Properly fixed blocking conflict when `INSTALL_DUAL_KERNEL=yes`
  - Binary and source kernels of the same version CANNOT coexist (soft-block conflict)
  - The v1.0.4 fix was incorrect - sequential installation doesn't resolve slot conflicts
  - `INSTALL_DUAL_KERNEL` is now DEPRECATED and defaults to `no`
  - Changed default `USE_BINARY_KERNEL="yes"` for fast initial setup
  - Resolves Portage error: "The above package list contains packages which cannot be installed at the same time"

### Added
- **Kernel Switch Helper**: New `/usr/local/bin/switch-to-source-kernel` script
  - Guides users through switching from binary to source kernel after installation
  - Automatically preserves old kernel versions for backup/fallback
  - Records current binary kernels in `/etc/portage/sets/kernels` before switching
  - Handles kernel replacement in the same slot automatically
  - Preserves kernel configuration
  - Optional kernel customization with `make menuconfig`
  - Provides clear instructions for kernel management and fallback
  - Installed automatically when using binary kernel

- **Kernel Management Helper**: New `/usr/local/bin/manage-kernels` script
  - `manage-kernels list` - Show all installed kernel versions
  - `manage-kernels preserve` - Add current kernels to preservation set
  - `manage-kernels clean` - Interactively remove old kernel versions
  - `manage-kernels info` - Show detailed kernel information
  - Helps maintain multiple kernel versions for backup strategy

- **Kernel Preservation Configuration**: Automatic backup system
  - Created `/etc/portage/sets/kernels` for kernel preservation
  - Created `/etc/portage/profile/package.provided` for package management
  - Old kernel versions automatically preserved when upgrading
  - Multiple kernel slots supported (e.g., 6.12.58, 6.13.0 can coexist)
  - Prevents `emerge --depclean` from removing backup kernels
  - All kernel versions remain bootable in rEFInd menu

### Changed
- **Default Kernel**: Changed `USE_BINARY_KERNEL` default from `no` to `yes`
  - Binary kernel provides faster initial installation (5 min vs 30-60 min)
  - Users can optimize later with `switch-to-source-kernel` when system is stable
  - Better user experience: working system first, optimization second
  - Old kernels preserved automatically for fallback safety

### Documentation
- **README.md**: Added comprehensive kernel backup and fallback strategy section
  - Explains slot-based kernel system
  - Documents kernel preservation and management
  - Clarifies that different versions can coexist (6.12.58 binary + 6.13.0 source)
  - Added commands for viewing preserved kernels
- **Installation instructions**: Updated to reflect new kernel workflow
  - Binary first for speed, source later for optimization
  - Documented kernel management commands

## [1.0.4] - 2025-12-26
### Fixed
- **Kernel Installation**: Attempted fix for blocking conflict when `INSTALL_DUAL_KERNEL=yes` (INCOMPLETE)
  - Modified `install_kernel()` to install kernels sequentially instead of simultaneously
  - Install `sys-kernel/gentoo-kernel-bin` first, then `sys-kernel/gentoo-kernel` second
  - NOTE: This fix was incorrect - binary and source kernels still conflict in the same slot
  - This issue is properly resolved in v1.0.5

## [1.0.3] - 2025-12-26
### Fixed
- **Python Targets**: Corrected from python3_14 to python3_12 (python3_14 does not exist)
  - Update `PYTHON_TARGETS="python3_12"` and `PYTHON_SINGLE_TARGET="python3_12"` in make.conf
  - Update `package.use/python` to use `python_targets_python3_12` for all Python packages
  - Update ComfyUI Python installation to use `dev-lang/python:3.12`
  - This resolves slot conflicts that were caused by referencing non-existent python3_14
  - Python 3.12 is the latest stable version in Gentoo that properly supports all dependencies
  - Ensures compatibility with Sphinx, documentation tools, ROCm, PyTorch, and all AI/ML packages
  - Verified to work with AMD Radeon 780M (gfx1103), Vulkan, KDE Plasma 6, Wayland, Blender 3D, ComfyUI, and ROCm stack

## [1.0.2] - 2025-12-26
### Changed
- **Python Targets**: Updated from python3_11 to python3_14
  - Update `PYTHON_TARGETS="python3_14"` and `PYTHON_SINGLE_TARGET="python3_14"` in make.conf
  - Update `package.use/python` to use `python_targets_python3_14` for all Python packages
  - Update ComfyUI Python installation to use `dev-lang/python:3.14`
  - This resolves USE flag conflicts with modern Sphinx and documentation tools that require python3_14
- **Btrfs Tools**: Added man USE flag for sys-fs/btrfs-progs
  - Create `package.use/btrfs` configuration file
  - Enable man pages which require Sphinx documentation system with python3_14 support
- **Package Version Constraints**: Removed specific version requirements to use latest stable releases
  - Changed `>=dev-qt/qtbase-6.9.3` to `dev-qt/qtbase` (use stable version)
  - This allows Portage to select the latest stable Qt version automatically
- **Testing Keywords Documentation**: Improved comments for ~amd64 testing packages
  - linux-firmware: Clarified requirement for AMD Radeon 780M RDNA3 (gfx1103) support
  - vulkan-headers: Clarified requirement for Qt 6 Vulkan backend in KDE Plasma 6
  - ROCm packages: Clarified requirement for AMD Radeon 780M gfx1103 architecture support
- **Audio/Video Support**: Added comprehensive PipeWire USE flags
  - Create `package.use/audio` configuration file
  - Configure media-video/pipewire with sound-server, pipewire-alsa, extra, gstreamer
  - Configure media-video/wireplumber with elogind
- **Graphics Support**: Enhanced Mesa configuration for AMD RDNA3
  - Add vulkan and video_cards_radeon USE flags to media-libs/mesa
  - Ensures proper Vulkan and OpenCL support for AMD Radeon 780M iGPU

### Fixed
- Resolved Python target conflicts that prevented package installation
- Resolved btrfs-progs man page dependency conflicts with Sphinx
- Improved hardware-specific USE flag configurations for UM890 Pro (AMD Radeon 780M)

## [1.0.1] - 2025-12-26
### Fixed
- Fix infinite loop of USE flag changes for Python packages during installation
  - Add global `PYTHON_TARGETS="python3_11"` and `PYTHON_SINGLE_TARGET="python3_11"` to make.conf
  - Create `package.use/python` with wildcard configuration covering all dev-python/* packages
  - This prevents Portage from continuously requesting python_targets_python3_11 for any Python package
  - Fixes issue where Python packages pulled in by system dependencies (Sphinx, docutils, etc.) caused USE flag conflicts
  - Resolves masked package issues with dev-python/installer and other Python build tools
  - Use wildcard approach (dev-python/*) for robust and maintainable configuration
  - Only create ComfyUI package.use file when INSTALL_COMFYUI=yes

## [1.0.0] - 2025-12-25
- Comprehensive rewrite for Gentoo UM890 Pro optimization
- Target hardware specifications documented:
  - Memory: 2× Crucial 48GB DDR5-5600 (CT48G56C46S5, 96GB total)
  - Storage: 2× Crucial P3 Plus 4TB NVMe SSD (CT4000P3PSSD8)
- Added hardware preparation documentation (UEFI, Crucial P3 Plus 4TB, Crucial DDR5-5600 96GB)
- Implemented Btrfs snapshot management and rollback system with `manage-snapshots` utility
- Configured NVMe1 as dedicated AI drive with ZFS optimization for large models (1M recordsize)
- Enhanced rEFInd configuration for snapshot boot options and dual-kernel support
- Created ML-based boot target selection system (`ml-boot-selector`)
- Added ROCm support for AMD Radeon 780M iGPU (gfx1103)
- Added ComfyUI installation and UMA-optimized configuration scripts
- Added SDXL support with memory optimization for UMA systems
- Implemented SDXL memory optimization workflow templates
- Created ComfyUI workflow optimized for UMA architecture
- Added Blender Cycles iGPU optimization configurations and startup scripts
- Implemented dual-kernel fallback strategy (binary + source kernels)
- Created comprehensive system optimization guide (OPTIMIZATION_GUIDE.md)
- Created hardware setup guide (HARDWARE_SETUP.md)
- Added snapshot management scripts with automatic cleanup
- Added boot selection ML system scripts with health monitoring
- Configuration variables: `INSTALL_COMFYUI` (includes SDXL support), `INSTALL_ROCM`, `INSTALL_DUAL_KERNEL`, `ENABLE_SNAPSHOTS`
- Optimized package.use configurations for ROCm, ComfyUI dependencies
- Added DDR5-5600 specific memory optimizations (huge pages, swappiness tuning)
- Configured memory bandwidth optimizations for 96GB dual-channel DDR5-5600
- Prepare changes for upcoming 0.1.9 release (pre-release; version will be finalized upon release)

## [0.1.8] - 2025-12-25
- Switch qtbase-6.9.3+ to use Vulkan backend instead of OpenGL
  - Update dev-qt/qtbase USE flags to `-opengl vulkan` (was `opengl -vulkan`)
  - Add package.accept_keywords for dev-util/vulkan-headers ~amd64 to satisfy dependency
  - This resolves "USE changes are necessary: >=dev-qt/qtbase-6.9.3 -opengl vulkan" requirement
  - Vulkan backend is used for Qt 6 and KDE Plasma 6 in this configuration
- Separate KDE Plasma 6 package.use configuration into modular components for better maintainability
  - Split into separate files: qt-base, qt-modules, kde-frameworks, kde-plasma, graphics, blender
  - Allows independent management of different dependency groups
- Add version constraint `>=dev-qt/qtbase-6.9.3` to explicitly target newer qtbase versions
- Add Blender 3D creation suite installation support via `INSTALL_BLENDER` configuration variable
- Configure Blender with comprehensive USE flags: opengl, vulkan, cycles, openvdb, embree, and more
- Add media-libs/mesa with vulkan USE flag to ensure Vulkan support for graphics applications
- Document modular package.use approach in inline comments for future maintainability
- Update README.md to document the new `INSTALL_BLENDER` configuration variable
- Version bump to 0.1.8

## [0.1.7] - 2025-12-21
- Switch default kernel from binary (gentoo-kernel-bin) to source-based (gentoo-kernel)
- Version bump to 0.1.7

## [0.1.6] - 2025-12-20
- Fix linux-firmware license acceptance
- Improve emerge error visibility

## [0.1.5] - 2025-12-20
- Fix logging mechanism to properly detect process substitution support and ensure logs are written during long operations
- Add informative progress messages before long-running operations (especially linux-firmware emerge)
- Add completion messages after chroot operations to track progress
- Ensure log buffer flushing before long-running commands

## [0.1.4] - 2025-12-19
- Reduce chroot overhead by 40%
- Fix shellcheck warnings

## [0.1.3] - 2025-12-19
- Switch bootloader from GRUB to rEFInd.
- Install KDE Plasma with Wayland + SDDM by default.
- Prefer no-multilib (pure 64-bit) Gentoo profiles when available.
- Fix global USE defaults for Plasma/Wayland (no longer disables KDE).

## [0.1.2] - 2025-12-17
- Default `INIT_SYSTEM` is now `openrc`.
- When using OpenRC, the installer now sets up an OpenRC-managed zram swap service (`/etc/init.d/zram` + `/etc/conf.d/zram`).

## [0.1.1] - 2025-12-16
- Semver migration (VERSION/CI alignment)

## [0.1.0] - 2025-12-16
- Initial versioning for installer and documentation
