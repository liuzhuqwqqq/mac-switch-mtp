# 验证记录

日期：2026-11-14。

## 已验证

- Apple Silicon / arm64，macOS 27.3，Apple Swift 6.4.2。
- C 核心启用 `-Wall -Wextra -Werror`，Swift 使用 Swift 5 语言模式。
- 内置 libmtp 1.1.23 / libusb 1.0.30；从应用内部加载动态库。
- 本地临时签名与 `codesign --verify --deep --strict` 检查。
- 10 组模拟 MTP 测试通过，不调用真实 USB。
- 使用 5 GB 稀疏文件与模拟回调验证大小和进度的 64 位处理。
- GUI 启动、中文布局、文件选择器与设备未连接提示。
- 真实 Switch 连接成功，界面显示 **Switch 已连接 · DBI MTP**，识别到 **5: SD Card install**。
- 上述连接使用 C to C 数据线。

## 尚未验证

- 真实游戏文件上传和安装成功。
- 真实超过 4 GB 的完整 USB 传输。
- 持续传输速度、物理拔线后的恢复行为。
- Intel Mac、旧版 macOS、其他 DBI 或主机版本。

Mac 的完成状态代表 MTP 传输结果；安装结果请查看 Switch 上的 DBI 提示。

## 发布构建

原先使用的 Homebrew 动态库要求 macOS 27.0，不能用于旧系统分发。发布构建改为从固定版本上游源码重编译 libmtp / libusb，同时将 C 核心与 Swift 应用的部署目标设为 macOS 13.0。

发布前检查应用、helper 和两个 dylib 的 Mach-O 最低系统版本、外部依赖路径和签名。该检查不能代替旧系统实机验证；macOS 13–26 的实际启动和 USB 行为仍待用户测试。
