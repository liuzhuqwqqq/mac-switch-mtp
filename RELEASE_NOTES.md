# v0.1.1 · 修复 DBI 开始传输失败

修复点击开始后 DBI 返回 `PTP Invalid Object Handle (2009)` 的问题：发送文件时明确指定 SD 安装入口的根目录。此前 v0.1.0 可能可以连接，但在实际传输前被 DBI 拒绝。

- 已完成一个 2.96 GB XCZ 文件的真实 USB 传输，用户确认 DBI 安装成功、没有错误。
- 更新模拟设备校验，防止根目录参数回归；10 组模拟 MTP 测试通过，不调用真实 USB。
- 保持 Apple Silicon、macOS 13.0+ 部署目标；macOS 13–26 尚未实机验证，暂无 Intel 预编译包。
- 传输完成与安装成功分别判断，安装结果请以 Switch 上的 DBI 提示为准。

应用内置 libmtp / libusb，运行无需另装 Homebrew。本地临时签名，未经过 Apple 公证。仅用于你有权使用的安装文件。

下载文件：

- `mac-switch-mtp-v0.1.1-AppleSilicon.zip`：可运行应用。
- `mac-switch-mtp-v0.1.1-ThirdParty-Sources.zip`：内置第三方库的对应源码、许可与构建配方。
- `SHA256SUMS.txt`：上述文件的校验值。
