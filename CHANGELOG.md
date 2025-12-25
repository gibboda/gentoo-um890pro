# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
- Switch qtbase-6.9.3+ to use Vulkan backend instead of OpenGL
  - Update dev-qt/qtbase USE flags to `-opengl vulkan` (was `opengl -vulkan`)
  - Update dev-qt/qtdeclarative and dev-qt/qttools to use vulkan (was opengl)
  - Add package.accept_keywords for dev-util/vulkan-headers ~amd64 to satisfy dependency
  - This resolves "USE changes are necessary: >=dev-qt/qtbase-6.9.3 -opengl vulkan" requirement
  - Vulkan support is now the primary graphics backend for Qt 6 and KDE Plasma 6
- Separate KDE Plasma 6 package.use configuration into modular components for better maintainability
  - Split into separate files: qt-base, qt-modules, kde-frameworks, kde-plasma, graphics, blender
  - Allows independent management of different dependency groups
- Add version constraint `>=dev-qt/qtbase-6.9.3` to explicitly target newer qtbase versions
- Add Blender 3D creation suite installation support via `INSTALL_BLENDER` configuration variable
- Configure Blender with comprehensive USE flags: opengl, vulkan, cycles, openvdb, embree, and more
- Add media-libs/mesa with vulkan USE flag to ensure Vulkan support for graphics applications
- Document modular package.use approach in inline comments for future maintainability
- Update README.md to document the new `INSTALL_BLENDER` configuration variable

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
