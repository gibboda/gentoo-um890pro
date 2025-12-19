# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Describe upcoming changes here.

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
