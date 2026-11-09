# Linux installation and distribution

[简体中文](linux.zh.md) · [README](../../README.en.md#linux)

Choose an asset from the [latest stable release](https://github.com/CyrilPeng/Venera-Next/releases/latest) matching `uname -m`: `x86_64` corresponds to x64 / amd64; `aarch64` corresponds to ARM64 / arm64. The current stable release, [v1.18.1](https://github.com/CyrilPeng/Venera-Next/releases/tag/v1.18.1), includes DEB, RPM and AppImage packages for both architectures, plus an x86_64 Arch package. Development builds are available as artifacts of the **构建** (Build) Actions workflow.

## Installation

DEB builds use `python3 debian/build.py x64` or `python3 debian/build.py arm64` and the system `dpkg-deb`, without installing `flutter_to_debian`. First run `flutter pub get --enforce-lockfile`. Add `--skip-build` to package an existing release bundle. Output is `build/linux/<arch>/release/debian/`. The script owns dependencies, desktop entries, and the existing `/usr/local/lib/venera-next` installation path; it does not modify repository templates. Quality checks build and extract DEBs with ELF fixtures for both architectures; these checks do not replace real platform compilation or runtime tests.

Replace `xxx` with the version in the downloaded filename.

```bash
# Debian / Ubuntu
sudo apt install ./venera-next_xxx_amd64.deb
# Fedora and compatible RPM distributions
sudo dnf install ./venera-next-xxx.x86_64.rpm
# Arch Linux (x86_64 only)
sudo pacman -U ./venera-next-xxx-x86_64.pkg.tar.zst
```

Start the RPM installation from the application menu or `venera-next`. Install a newer RPM using the same command; uninstall with `sudo dnf remove venera-next`. These packages do not configure an update repository.

## AppImage

```bash
chmod +x VeneraNext-xxx-x86_64.AppImage
./VeneraNext-xxx-x86_64.AppImage
# Run without FUSE when mounting is unavailable:
./VeneraNext-xxx-x86_64.AppImage --appimage-extract-and-run
```

Use the `aarch64` asset for ARM64. No administrator permission is needed. Menu integration is not installed automatically. Replace the file to upgrade; application data remains in your system user data directory.

## Compatibility and dependencies

Linux packages share a binary compiled on Ubuntu 22.04 with a glibc 2.35 baseline. DEB/RPM use the package manager to install system dependencies such as libstdc++, GTK 3 and WebKitGTK 4.1. RPM records system ELF symbol requirements automatically, and the package manager rejects installation when dependencies are missing.

The current v1.18.1 stable AppImage includes Flutter, GTK 3, WebKitGTK 4.1, its helper processes, image loaders and runtime resources, so no separate GTK/WebKit installation is needed. It still requires host glibc 2.35 or newer and compatible OpenGL/EGL graphics drivers. Filenames are `VeneraNext-<version>-x86_64.AppImage` or `VeneraNext-<version>-aarch64.AppImage`, without `linux`. These bundled libraries and filename changes were introduced in v1.17.0-rc.2.

The already published **v1.17.0-rc.1 AppImage does not bundle GTK/WebKit** and uses filenames containing linux. That release still needs the following host packages; DEB/RPM continue to use system dependencies:

```bash
sudo apt install libgtk-3-0 libwebkit2gtk-4.1-0  # Ubuntu / Debian
sudo dnf install gtk3 webkit2gtk4.1             # Fedora
```

RPM does not imply compatibility with every Red Hat family distribution. RHEL / Rocky / AlmaLinux 9 use glibc 2.34, below this baseline; AppImage cannot bypass this requirement either. Use a newer distribution with the required libraries, or compile on the target system.

## GitHub Actions and packaging

The Linux x64 / ARM64 switches in **构建** build DEB, RPM and AppImage for the selected architecture; x64 also builds Arch packages. The release workflow collects these assets. The additional workflow artifacts are named `linux_extra_x64` and `linux_extra_arm64`.

After building the Flutter bundle on a Linux runner:

```bash
sudo apt install rpm squashfs-tools desktop-file-utils file
python3 .github/scripts/build_linux_packages.py --arch x64
# Use --arch arm64 on an ARM64 runner.
```

The script checks ELF architecture and Flutter resources, builds and inspects the RPM, recursively collects AppImage ELF dependencies and verifies the dependency closure again after extraction. WebKit helpers and relocatable resource paths are required. Only glibc and graphics drivers remain host interfaces; missing other libraries fail packaging. Dependency versions and copyright notices are included under `usr/share/doc/venera-next-runtime/`.

See the Linux installation steps in `.github/workflows/build.yml` for GTK/WebKit development and runtime build packages. After packaging, run `bash .github/scripts/test_appimage.sh x64` (or `arm64`), using a C compiler, pkg-config and Docker. CI runs this before uploading either architecture: an Ubuntu 22.04 container without GTK/WebKit must display the application window and load HTML in a WebKit helper process. The container-only WebKit sandbox override is never included in the distributed launcher.

A second pass relaxes Docker's outer seccomp/AppArmor policies and masked system paths and explicitly enables WebKit's own sandbox. Ubuntu release builds ignore `WEBKIT_EXEC_PATH`, so the launcher relocates compiled-in helper paths in a private library copy under a mode-0700 `/tmp` directory, cleaned up on exit. It never modifies the system or original AppImage. `/tmp` must be writable and executable, with approximately 100 MB available for this copy; unsupported WebKit path layouts fail explicitly.

Both architectures use SHA-256-verified appimagetool 1.9.1 and type2-runtime 20251108. Packaging does not require FUSE. Outputs are in `build/linux/<architecture>/packages/`. To roll back, restore the previous packaging scripts and workflow and rebuild; those images require host GTK/WebKit again. Application data formats are unchanged.
