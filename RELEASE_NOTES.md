# v0.1.0 · 首个试用版

macOS 上的 Switch DBI MTP 安装助手，支持 USB 传输、批量队列和实时进度。

- 中文原生界面，支持拖入 NSP / NSZ / XCI / XCZ 文件。
- 识别 DBI 的 SD Card install 入口，按队列依次发送。
- 显示传输进度、速度、取消与诊断日志。
- 应用内置 libmtp / libusb，无需用户另装 Homebrew。

**下载版本：Apple Silicon（M 系列）Mac，部署目标 macOS 13.0+，包括 macOS 26。**

应用、libmtp 和 libusb 均从源码按 macOS 13.0 重新编译。已在 macOS 27.3 验证；macOS 13–26 仍需实机测试，不提供 Intel 预编译包。

Switch 端需已经可以运行 DBI，并进入 **Run MTP responder**。USB-C to USB-C 数据线已完成连接验证。

已通过本机编译、签名检查、10 组模拟协议测试和真实 DBI 连接检查。完整文件传输、实际游戏安装、持续速度及真实超过 4 GB 的传输尚未验证。安装结果请以 Switch 上的 DBI 为准。

应用为本地临时签名，未经过 Apple 公证。仅用于你有权使用的安装文件。

下载文件：

- `mac-switch-mtp-v0.1.0-AppleSilicon.zip`：可运行应用。
- `mac-switch-mtp-v0.1.0-ThirdParty-Sources.zip`：内置第三方库的对应源码、许可与构建配方。
- `SHA256SUMS.txt`：上述文件的校验值。
