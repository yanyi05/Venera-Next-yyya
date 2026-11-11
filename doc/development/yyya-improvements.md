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

原 ZIP 目录未改动。依赖锁文件与上游 v1.18.3 一致。分支代码已上传 GitHub，没有发布 Release 或启动付费服务。

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

Windows 调试程序位于 `build/windows/x64/runner/Debug/VeneraNext.exe`。之后另外完成了 Windows Release 本地构建（596.5 秒），位于 `build/windows/x64/runner/Release/VeneraNext.exe`；完整压缩包包含 66 个文件，已校验 CRC 和文件清单，不能单独复制 EXE。

## 网站验证入口补回

之前的 `reader-mask-tools` 分支含有浏览器验证入口，而首次同步使用的是 fork 的 `main`，没有包含该入口。本轮移植相关入口与发现页漫画源替换后的回调更新，不合并该分支其他无关功能。保留 v1.18.3 对漫画列表请求生命周期的上游修改。

发现页工具栏和失败页、分类页工具栏提供“网站验证”；验证完成并保存后返回原页面重试。恢复动作不解析错误文本来猜测站点，只使用漫画源声明的网页登录地址。补回的源替换/移除处理防止旧源回调在验证返回后继续被调用。

另外修正 WebView Cookie 转换时丢失路径、有效期、Secure 与 HttpOnly 的问题，并在页面加载完成后再次检查源的验证成功条件。没有改动用户实际的 Cookie 值、安装源脚本或网络设置。

73 项相关回归测试通过，覆盖入口显示、验证完成后保存并返回、旧源替换和移除、Cookie 属性、窗口代理与浏览器回调释放。日志：`logs/browser-verification-tests.log`。改动文件的严格静态分析、结构导入与架构边界检查也通过。这些测试不等于真实站点会话可复用；网站过期策略、源配置中的域名/UA、浏览器与原生请求环境仍可能导致重新验证。

## 阅读误触与历史验证入口（2026-11-11）

阅读点击增加独立的 8 逻辑像素移动限制：超过后取消本次点击和等待中的单击，即使手指移回起点也不再打开菜单。滚动开始或继续滚动时，同样取消等待中的点击；保留原有双击间距、长按和拖动手势判定。

历史记录使用的 `ReaderWithLoading` 失败页、阅读器章节失败页补上当前源的“网站验证”，返回后重试对应请求；在线阅读工具栏也保留入口。复用已有的内置浏览器、会话保存及源提供的验证地址，未声明网页登录入口的源继续隐藏按钮。

214 项相关回归通过，覆盖短滑动及回到起点、轻微点击抖动、等待中的点击取消、iOS 弹性滚动物理下的列表滚动、历史加载失败重试，以及章节失败页和阅读工具栏入口。日志：`logs/reader-touch-verification-tests.log`；严格静态分析、结构导入与架构边界检查均通过，分析日志：`logs/reader-touch-verification-analyze.log`。iPhone 尚未构建或真机验收。

## iPhone 与验收限制

按用户要求只针对 Windows 与 iPhone 验证，不再运行鸿蒙平台测试。上游已有的其他平台代码随合并保留。

当前机器是 Windows，没有 macOS/Xcode，因此尚未在本机编译 Swift、构建 IPA 或连接 iPhone 真机。iOS 文字识别、缩放、系统翻译菜单、内存告警及后台恢复仍需用 macOS 构建后，在 iPhone 上验收。分支已包含可手动运行的 Windows/iPhone 构建工作流；本机检查没有验证远端 iOS 构建结果。

不能将启动诊断与防御性修改视为原白屏闪退已修复。仍需出问题的 iPhone 系统 `.ips` 崩溃记录，以区分签名、原生库和 Dart 初始化阶段的问题；当前没有该记录。

裁剪和资源策略的具体上限、格式限制与使用入口见 [阅读工具说明](../user/yyya-reader-tools.zh.md)。没有测量真实漫画站点网络、设备帧率、耗电或温度收益。
