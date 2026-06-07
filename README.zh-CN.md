<div align="center">
  <img src="Resources/AppIcon.iconset/icon_128x128.png" width="96" height="96" alt="CN PAC Menubar App Icon">
  <h1>CN PAC Menubar</h1>
  <p><strong>从菜单栏托管 PAC、应用系统自动代理，并把代理配置快速分享给本机应用和局域网设备。</strong></p>
  <p>
    <a href="https://github.com/YTwsy/cn-pac-menubar/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/YTwsy/cn-pac-menubar?style=flat-square"></a>
    <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-000000?style=flat-square&amp;logo=apple">
    <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white">
    <img alt="Menu bar PAC server" src="https://img.shields.io/badge/Menu%20bar-PAC%20server-2ea44f?style=flat-square">
  </p>
  <p>
    <strong>中文</strong> · <a href="README.en.md">English</a>
  </p>
  <p>
    <a href="https://github.com/YTwsy/cn-pac-menubar/releases/latest">下载</a> ·
    <a href="#构建">构建</a> ·
    <a href="docs/RELEASE.zh-CN.md">发布流程</a> ·
    <a href="#局域网设备">局域网设备</a> ·
    <a href="#google-vpn-keepalive">Google VPN Keepalive</a>
  </p>
  <p>
    <img src="Design/Product/cn-pac-menubar-main-window.png" width="38%" alt="CN PAC Menubar 主窗口">
    <img src="Design/Product/cn-pac-menubar-menu.png" width="54%" alt="CN PAC Menubar 菜单栏菜单">
  </p>
</div>

## 功能

- 从菜单栏选择并托管 PAC 文件。
- 将 PAC 内的代理指令改写为当前配置的 SOCKS5/HTTP 代理端点。
- 一键应用 macOS 自动代理配置，不需要手动进系统网络设置。
- 复制局域网 PAC URL，方便同一网络里的手机、平板或其他电脑使用。
- 为单个应用生成代理启动器，覆盖环境变量、Chromium/Electron 参数和 Java 参数等常见路径。
- 通过 PAC 解析出的代理路径执行严格的 Google VPN Keepalive 探测。

## 构建

```sh
swift test
swift build -c release
Scripts/package-app.sh
```

打包后的应用会写入 `.build/CNPacMenubar.app`。

`Scripts/package-app.sh` 会先尝试 SwiftPM 构建。如果本机 Command Line Tools 无法满足 SwiftPM 的 macOS platform lookup，脚本会退回到直接使用已安装 macOS SDK 的 `swiftc` 构建路径。

应用版本默认来自 `VERSION`。发布构建也可以用环境变量覆盖：

```sh
APP_VERSION=1.0 APP_BUILD_NUMBER=1 Scripts/package-app.sh
```

## 本地安装

```sh
Scripts/package-app.sh
cp -R .build/CNPacMenubar.app ~/Applications/
```

## 运行数据

设置会保存到：

```text
~/Library/Application Support/cn-pac-menubar/settings.json
~/Library/Application Support/cn-pac-menubar/launchers.json
```

生成的代理启动器每次启动都会重新读取 `settings.json`，所以在 CN PAC Menubar 里更新 HTTP 代理主机或端口后，后续启动器会自动使用新配置，不需要重新生成。

## PAC 代理兜底

代理规则默认 fail closed：生成的 PAC 代理链不会追加最终的 `DIRECT`，因此应该走代理的主机在所有代理不可用时会失败，而不是静默直连。

如果确实想恢复旧行为，可以在 **Proxy > Allow DIRECT Fallback** 中显式开启。内置的私有 IP 和直连域名规则仍然会返回 `DIRECT`，不受该开关影响。

## Google VPN Keepalive

菜单里包含 **Google VPN Keepalive**，用于在应用运行时按计划发送严格的 PAC 代理探测。它会先用当前 PAC 解析目标 URL，明确使用第一个代理指令，并把 `DIRECT` 视为 keepalive 路径失败。可以从菜单或主窗口启用，再通过 **Keepalive Settings...** 调整：

- 目标 URL，默认为 `https://www.gstatic.com/generate_204`。
- 间隔秒数，范围是 30 秒到 24 小时。
- 超时秒数，范围是 1 到 120 秒。

菜单和主窗口会显示最近一次结果以及下一次计划请求。

## 局域网设备

应用会把本机 macOS 自动代理 URL 保持在 loopback，例如 `http://127.0.0.1:8118/proxy.pac`，同时在菜单里暴露局域网 PAC URL，例如 `http://192.168.1.103:8118/proxy.pac`。手机、平板或其他电脑可以使用 **Copy LAN PAC URL** 复制这个地址。

其他设备要成功使用 PAC，macOS 可能需要允许 CN PAC Menubar 接收入站连接，而且 PAC 里写入的代理端点必须能被该设备访问。如果代理运行在这台 Mac 上，应把 **Proxy Host** 设置为这台 Mac 的局域网 IP，并确认上游代理应用允许局域网连接。

## 启动器兼容性

启动器会为目标应用选择兼容配置：

- Environment：导出常见代理变量，例如 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`、`FTP_PROXY`、`grpc_proxy` 和 `NO_PROXY`。
- Chromium/Electron：除了代理变量，还会加入 `--proxy-server` 和 `--proxy-bypass-list` 等 Chromium 代理参数。
- Java：除了代理变量，还会加入 `JAVA_TOOL_OPTIONS` JVM 代理属性。
- System PAC preferred：标记可能忽略启动器变量的 Apple/系统应用，这类应用更适合通过 macOS 自动代理配置处理。

## 发布

发布通过版本标签驱动：

```sh
VERSION="$(cat VERSION)"
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"
```

`Release` GitHub Actions workflow 会构建应用、生成 `CNPacMenubar-vVERSION-macos.zip`，并为标签创建 GitHub Release。完整流程见 [docs/RELEASE.zh-CN.md](docs/RELEASE.zh-CN.md)。
