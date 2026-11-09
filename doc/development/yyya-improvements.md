# yyya 阅读体验改进

记录日期：2026-11-10。工作分支：`feature/iphone-reader-improvements`。

## 本地完成的改动

基于 fork 的 `77c2b9e` 合并上游稳定版 v1.18.3（`e8a380e`，1.18.3+249），保留图片遮罩功能，没有扩展遮罩编辑器。修正合并后遮罩图片的有限尺寸约束，未使用遮罩的单图继续采用上游 PhotoView 加载与重试流程。

- 启动阶段记录、失败详情复制与分享、下次启动停用已安装源的恢复开关；iOS 通道注册移除强制转换根视图控制器的写法。
- 更新检查和安装包链接指向自己的 fork；关于页保留原作者更新链接。fork 尚无 Release 时正常返回无更新。
- 单图刷新按图片分别失效缓存，实际解码成功后才提示完成，退出阅读会撤销等待并释放监听。
- 按阅读方向预加载、快速跳页降载、手机缓存上限、后台与内存压力时暂停预读。
- 按漫画保存自动或手动白边裁剪，默认关闭、可随时恢复，不改原文件；有遮罩的图片保持原画面。
- 临时缓存按漫画分组、清理前预估、可保留近期使用缓存；确认后新写入或访问过的缓存不删除。下载与本地漫画占用只读扫描。
- iPhone 接入系统实况文本，提供选字、复制和系统翻译入口；不支持的设备不显示按钮。使用 [Apple VisionKit 接口](https://developer.apple.com/documentation/visionkit/enabling-live-text-interactions-with-images)。
- 增加手动工作流“yyya Windows 与 iPhone 构建”，只调用这两个平台的构建，不自动发布。

原 ZIP 目录未改动。依赖锁文件与上游 v1.18.3 一致。没有推送 GitHub、发布 Release 或启动付费服务。

## Windows 验证

环境：Flutter 3.41.4 / Dart 3.11.1，Visual Studio Build Tools 2026，Rust 1.92.0；工具缓存安装在工作区 `.tools`。

| 检查 | 结果 | 本地日志 |
| --- | --- | --- |
| 阅读器、启动、缓存、更新等相关回归 | 1038 通过，2 跳过 | `logs/tests-pinned-final.log` |
| 最后逻辑调整后的新增功能用例 | 17 通过 | `logs/tests-feature-last.log` |
| Windows 原生启动、心跳、快捷键 | 3/3 通过 | `logs/windows-native-tests-verified.log` |
| Windows Debug 完整构建 | 成功 | `logs/windows-build-nuget.log` |
| Windows 实际启动 | 启动阶段 ready、首帧渲染、MainPage 已挂载、未进入失败页面；测试实例已关闭 | `logs/windows-app-smoke.json`、`logs/windows-app.stderr.log` |
| 全项目严格静态分析 | 通过，无错误、警告或 lint 提示 | `logs/flutter-analyze-complete.log` |
| 结构导入与架构边界 | 通过 | `.github/scripts/check_structure_imports.py`、`check_architecture_dependencies.py` |
| Apple Rustup 工作流静态守卫 | 2 通过，2 因 Windows 不支持 POSIX 跳过 | `.github/scripts/tests/test_apple_rustup_wrapper.py` |

回归统计包含重叠用例，不能相加。测试日志和构建输出不加入版本控制。Windows 启动使用独立数据目录 `build/windows-smoke-profile`，没有升级日常使用的数据。

Windows 程序位于 `build/windows/x64/runner/Debug/VeneraNext.exe`，运行需要旁边的 DLL 与 data 目录；这是调试验证产物，未制作正式发行包。

## iPhone 与验收限制

按用户要求只针对 Windows 与 iPhone 验证，不再运行鸿蒙平台测试。上游已有的其他平台代码随合并保留。

当前机器是 Windows，没有 macOS/Xcode，因此尚未编译 Swift、构建 IPA 或连接 iPhone 真机。iOS 文字识别、缩放、系统翻译菜单、内存告警及后台恢复仍需用 macOS 构建后，在 iPhone 上验收。工作流尚未上传或运行。

不能将启动诊断与防御性修改视为原白屏闪退已修复。仍需出问题的 iPhone 系统 `.ips` 崩溃记录，以区分签名、原生库和 Dart 初始化阶段的问题；当前没有该记录。

裁剪和资源策略的具体上限、格式限制与使用入口见 [阅读工具说明](../user/yyya-reader-tools.zh.md)。没有测量真实漫画站点网络、设备帧率、耗电或温度收益。
