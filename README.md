# mac-switch-mtp

**macOS 上的 Switch DBI MTP 安装助手，支持 USB 传输、批量队列和实时进度。**

中文原生界面，将本地 NSP / NSZ / XCI / XCZ 文件传入 DBI 的 **SD Card install** 入口，由 Switch 上的 DBI 边接收边安装。

v0.1.1 修复 DBI 在开始传输时报 `Invalid Object Handle` 的问题；旧版用户请重新下载应用。

## 下载与使用

在 [Releases](https://github.com/liuzhuqwqqq/mac-switch-mtp/releases) 下载应用压缩包，解压后将 **Switch MTP.app** 拖入「应用程序」。已内置 libmtp / libusb，运行无需另外安装 Homebrew。

当前预编译版本：**Apple Silicon（M 系列），部署目标 macOS 13.0 及以上，包括 macOS 26**。应用和两个内置动态库均从源码按该目标重新编译。已在 macOS 27.3 检查启动、真实 DBI 连接和一个 2.96 GB XCZ 文件的完整传输；用户确认 DBI 安装成功；**尚未在 macOS 13–26 实机验证，也未提供 Intel 预编译包**。应用为本地临时签名，未经过 Apple 公证。

1. Switch 打开 DBI → **Run MTP responder**，保持该界面。
2. 用支持数据传输的 USB 线直连 Mac，**C to C 数据线可以使用**。
3. 应用点击 **连接 Switch**，确认识别到 **SD Card install**。
4. 拖入文件或点击 **选择文件…**，然后点击 **开始传输安装**。
5. 等待队列传输结束，**安装结果以 Switch 上 DBI 的提示为准**。

要求 Switch 已经能够运行 DBI；原版系统本身不提供这个安装入口。仅用于你有权使用的安装文件，不附带游戏、密钥或系统破解工具。

## 功能

- 中文 AppKit / SwiftUI 界面，拖放文件与多文件队列。
- 实时字节进度、传输速度、取消和可复制日志。
- 使用 64 位文件大小和流式传输，不将整个安装文件读进内存。
- 按名称识别 SD 安装入口，适应不同 DBI 版本的入口编号。
- 错误后停止队列；重新连接后可重试失败或取消的文件。
- 传输期间防止 Mac 自动睡眠；合盖或手动睡眠仍会中断 USB。

当前仅提供 SD 安装传输，未实现卸载游戏、存档管理或按键远程控制。

## 无法连接时

- 确认进入 **Run MTP responder**，而非 **Install title from DBIbackend**。
- 退出 OpenMTP、Android File Transfer 及其代理等可能占用 MTP 的软件，再重新进入 DBI MTP 模式。
- 优先用数据线直连 Mac，尝试更换接口或线材。
- macOS 询问是否允许配件连接时选择允许。
- 未出现安装入口时，在 DBI 的 `[MTP Storages]` 中启用 `SD Card install`。
- 展开 **连接与传输日志** 查看诊断信息；反馈问题时移除个人文件路径等信息。

压缩安装包解压后的占用可能大于文件大小，请以 DBI 的空间检查为准。本工具检查扩展名与可读性，不校验安装包内容。

## 从源码构建

需要支持该源码的 Xcode 命令行工具、Python 3 和 pkg-config。使用 Homebrew 安装构建工具：

```sh
brew install pkgconf
git clone https://github.com/liuzhuqwqqq/mac-switch-mtp.git
cd mac-switch-mtp
bash build.sh
```

默认输出 `dist/Switch MTP.app`，也可指定位置：

```sh
SWITCH_MTP_APP_PATH="$HOME/Applications/Switch MTP.app" bash build.sh
```

修改已有应用前先正常退出。默认部署目标为 macOS 13.0，可用 `SWITCH_MTP_DEPLOYMENT_TARGET` 更改。构建脚本会下载并校验 libmtp / libusb 的固定版本源码，将它们与应用按同一目标重新编译，缓存到 `~/Library/Caches/mac-switch-mtp`；不会直接使用 Homebrew 的高版本系统动态库。若云同步目录自动附加 Finder 属性导致签名失败，请改为输出到本机 `~/Applications`。

## 测试与验证

```sh
python3 -m unittest discover -s tests -v
```

10 组模拟 MTP 测试覆盖中文文件名、64 位大文件元信息与进度、目标存储限制、取消、错误断开和连续传输。测试不调用真实 USB。

已在真实 Switch 上识别到 **DBI MTP** 连接和 **SD Card install** 入口。已通过一个 2.96 GB XCZ 文件的真实 USB 传输，并由用户确认 DBI 安装成功。持续速度和真实超过 4 GB 的完整传输仍未验证；大文件测试使用稀疏文件与模拟回调。详细记录见 [VALIDATION.md](VALIDATION.md)。

## 源码与许可

- `Sources/mtp_helper.c`：libmtp 传输核心与 JSON 事件。
- `Sources/SwitchMTP.swift`：macOS 界面与队列管理。
- `tests/`：不访问 USB 的模拟设备测试。
- `vendor/`：第三方许可证、源码下载、依赖构建和发布包检查脚本。
- `package-release.sh`：生成应用与配套源码压缩包。

本项目源码采用 [MIT License](LICENSE)。libmtp / libusb 分别遵循 LGPL-2.1-or-later，详见 [THIRD_PARTY.md](THIRD_PARTY.md) 和 Releases 中的配套源码包。

感谢 [DBI](https://github.com/rashevskyv/dbi#run-mtp-responder)、[libmtp](https://github.com/libmtp/libmtp) 和 [libusb](https://github.com/libusb/libusb)。本项目与 Nintendo 及上述项目没有隶属关系。
