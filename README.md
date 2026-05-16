# CN PAC Menubar

macOS 13+ status-bar utility for serving PAC files, applying macOS automatic proxy configuration, and launching selected apps with `HTTP_PROXY`/`HTTPS_PROXY` environment variables.

## Build

```sh
swift test
swift build -c release
Scripts/package-app.sh
```

The packaged app is written to `.build/CNPacMenubar.app`.

`Scripts/package-app.sh` first tries SwiftPM. If the local Command Line Tools installation cannot satisfy SwiftPM's macOS platform lookup, the script falls back to a direct `swiftc` build with the installed macOS SDK.

## Install Locally

```sh
Scripts/package-app.sh
cp -R .build/CNPacMenubar.app ~/Applications/
```

## Runtime Data

Settings are stored in:

```text
~/Library/Application Support/cn-pac-menubar/settings.json
~/Library/Application Support/cn-pac-menubar/launchers.json
```

Generated proxy launchers read `settings.json` every time they start, so updating the HTTP proxy host or port in CN PAC Menubar changes future launcher sessions without rebuilding the launcher.

## Google VPN Keepalive

The menu includes **Google VPN Keepalive** for sending a strict scheduled PAC proxy probe while the app is running. It evaluates the selected PAC for the target URL, uses the first proxy directive explicitly, and treats `DIRECT` as a failed keepalive path. Enable it from the menu or main window, then use **Keepalive Settings...** to adjust:

- Target URL, defaulting to `https://www.gstatic.com/generate_204`.
- Interval in seconds, from 30 seconds to 24 hours.
- Timeout in seconds, from 1 to 120 seconds.

The menu and main window show the latest result and the next scheduled request.

## LAN Devices

The app keeps the Mac's own automatic proxy URL on loopback, for example `http://127.0.0.1:8118/proxy.pac`, and also exposes a LAN PAC URL in the menu bar such as `http://192.168.1.103:8118/proxy.pac`. Use **Copy LAN PAC URL** for phones, tablets, or other computers on the same network.

For another device to use the PAC successfully, macOS may need to allow incoming connections for CN PAC Menubar, and the proxy endpoint written inside the PAC must be reachable from that device. If the proxy runs on this Mac, set **Proxy Host** to this Mac's LAN IP and make sure the upstream proxy app allows LAN connections.

## Launcher Compatibility

Launchers now choose a profile for the target app:

- Environment: exports common proxy variables such as `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `FTP_PROXY`, `grpc_proxy`, and `NO_PROXY`.
- Chromium/Electron: adds Chromium proxy flags like `--proxy-server` and `--proxy-bypass-list` in addition to proxy variables.
- Java: adds `JAVA_TOOL_OPTIONS` JVM proxy properties in addition to proxy variables.
- System PAC preferred: marks Apple/system apps that may ignore launcher variables and are better handled by macOS automatic proxy configuration.
