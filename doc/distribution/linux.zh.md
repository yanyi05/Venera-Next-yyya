# Linux 安装与分发

[English](linux.en.md) · [返回 README](../../README.md#linux)

从 [最新稳定版](https://github.com/CyrilPeng/Venera-Next/releases/latest) 下载与机器架构对应的包。`uname -m` 输出 `x86_64` 时选择 x64 / amd64，输出 `aarch64` 时选择 ARM64 / arm64。当前稳定版 [v1.18.1](https://github.com/CyrilPeng/Venera-Next/releases/tag/v1.18.1) 提供两种架构的 DEB、RPM 和 AppImage，以及 x86_64 的 Arch 包；开发构建产物可在 GitHub Actions 的“构建”工作流中下载。

## 安装

以下 `xxx` 代表下载文件中的实际版本号。

```bash
# Debian / Ubuntu
sudo apt install ./venera-next_xxx_amd64.deb

# Fedora 及提供对应依赖的红帽系发行版
sudo dnf install ./venera-next-xxx.x86_64.rpm

# Arch Linux（目前仅提供 x86_64）
sudo pacman -U ./venera-next-xxx-x86_64.pkg.tar.zst
```

RPM 安装后可从应用菜单或 `venera-next` 命令启动。升级时再次执行 `dnf install ./新版本.rpm`；卸载使用 `sudo dnf remove venera-next`。这些下载包不配置自动更新仓库。

## AppImage

```bash
chmod +x VeneraNext-xxx-x86_64.AppImage
./VeneraNext-xxx-x86_64.AppImage
```

ARM64 使用文件名含 `aarch64` 的版本。无法挂载 FUSE 时，可使用无需 FUSE 的解包运行方式：

```bash
./VeneraNext-xxx-x86_64.AppImage --appimage-extract-and-run
```

AppImage 不需管理员权限，不会自动安装菜单入口；下载新文件替换旧文件即可更新。应用数据仍使用系统用户数据目录，不保存到 AppImage 文件内。

## 系统依赖与兼容范围

所有 Linux 格式目前复用 Ubuntu 22.04 编译的程序，glibc 基线为 2.35。DEB/RPM 通过包管理器获取 libstdc++、GTK 3 和 WebKitGTK 4.1 等系统依赖；RPM 使用 ELF 依赖检测记录所需符号版本，包管理器会拒绝缺失依赖的安装。

当前 v1.18.1 稳定版 AppImage 携带 Flutter、GTK 3、WebKitGTK 4.1、WebKit 子进程、图片加载器及相关运行资源，无需额外安装 GTK/WebKit。仍需宿主提供 glibc 2.35 或更新版本，以及兼容的 OpenGL/EGL 显卡驱动。文件名为 `VeneraNext-<版本>-x86_64.AppImage` 或 `VeneraNext-<版本>-aarch64.AppImage`，不含 `linux`。这些运行库与文件名调整已从 v1.17.0-rc.2 开始采用。

已经发布的 **v1.17.0-rc.1 AppImage 未包含 GTK/WebKit**，文件名包含 linux；该版本仍需手动安装以下运行依赖。DEB/RPM 继续通过包管理器获取系统依赖：

```bash
# Ubuntu 22.04 / Debian 等
sudo apt install libgtk-3-0 libwebkit2gtk-4.1-0

# Fedora
sudo dnf install gtk3 webkit2gtk4.1
```

“RPM”不代表兼容所有红帽系系统：RHEL / Rocky / AlmaLinux 9 的 glibc 2.34 低于当前基线，不能保证运行；AppImage 同样不能绕过 glibc 版本限制。请使用提供所需运行库的新发行版，或在目标系统自行编译。

## GitHub Actions 与本地打包

DEB 由 `python3 debian/build.py x64` 或 `python3 debian/build.py arm64` 构建，使用系统 `dpkg-deb`，不再安装 `flutter_to_debian`。先运行 `flutter pub get --enforce-lockfile`；已有对应架构的 Release bundle 时可加 `--skip-build`。输出为 `build/linux/<架构>/release/debian/`。运行依赖、菜单入口和安装路径由脚本维护，保留 `/usr/local/lib/venera-next` 以兼容已有安装；不再修改仓库内的模板文件。质量检查会用两种架构的 ELF 测试数据执行 DEB 打包与解包，这不代替实际平台编译和运行验证。

“构建”工作流的 Linux x64 / ARM64 开关同时控制该架构的 DEB、RPM、AppImage；x64 还生成 Arch 包。完整发布工作流收集两种新格式并上传 Release。工作流产物分别为 `linux_extra_x64` 和 `linux_extra_arm64`。

Linux runner 在现有 Flutter bundle 上运行：

```bash
sudo apt install rpm squashfs-tools desktop-file-utils file
python3 .github/scripts/build_linux_packages.py --arch x64
# ARM64 runner 使用 --arch arm64
```

脚本校验 ELF 架构和 Flutter 资源，生成并检查 RPM；AppImage 递归收集 ELF 依赖，检查 WebKit 辅助进程及可重定位资源路径，解包后再次验证依赖闭包。glibc 和显卡驱动保留为宿主接口，其余缺库会使构建失败。依赖版本清单和版权说明位于包内 `usr/share/doc/venera-next-runtime/`。

AppImage 构建所需的 GTK/WebKit 开发包及运行资源包见 `.github/workflows/build.yml` 的 Linux 安装步骤。构建后运行 `bash .github/scripts/test_appimage.sh x64`（ARM64 使用 `arm64`），需要 C 编译器、pkg-config 和 Docker。该检查在不安装 GTK/WebKit 的 Ubuntu 22.04 容器内验证真实应用窗口及 WebKit 子进程加载 HTML；容器测试专用的 WebKit 沙箱关闭设置不会写入分发包。两个架构均在 CI 上传产物前执行。

检查还会放开外层 Docker 的 seccomp/AppArmor 和系统路径遮蔽限制，再显式开启 WebKit 自身沙箱复验。Ubuntu 的 WebKit 发布版不支持通过 `WEBKIT_EXEC_PATH` 重定位，因此启动器在权限为 0700 的 `/tmp` 私有目录中生成库副本，替换子进程与沙箱辅助程序路径，退出时清理；不修改系统或原始 AppImage。运行时需要 `/tmp` 可写、可执行，并留有约 100 MB 空间用于该副本；不支持的 WebKit 路径布局会明确失败。

AppImage 工具固定为 appimagetool 1.9.1、type2-runtime 20251108，并分别校验两个架构的 SHA-256；构建无需 FUSE。产物位于 `build/linux/<架构>/packages/`。如需回滚，恢复旧打包脚本和工作流并重新构建；回滚产物需要用户自行安装 GTK/WebKit，应用数据格式不受影响。
