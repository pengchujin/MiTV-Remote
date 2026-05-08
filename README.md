# MiTV Remote

macOS 菜单栏遥控器，支持小米/Redmi 显示器与电视。通过局域网 Wi-Fi 接口（端口 6095）控制设备。

[English](#english)

---

## 功能

- **菜单栏常驻**：点击菜单栏图标即可弹出控制面板，不占 Dock
- **音量控制**：拖动滑块或点击按钮精确调节音量百分比
- **HDMI 切换**：一键切换 HDMI 1 / HDMI 2 输入源
- **完整遥控按键**：方向键、确认、主页、返回、菜单、电源
- **键盘映射**：菜单打开时，键盘方向键自动映射到遥控方向键
- **局域网设备发现**：自动扫描局域网，找到所有小米/Redmi 设备并一键切换
- **设备状态显示**：实时显示当前设备 IP 和设备名

## 使用方法

将 `dist/MiTV-Remote.app` 拖入 Applications 文件夹，双击启动即可。

首次使用时，点击菜单栏图标 → **搜索/切换设备**，选择局域网中的目标设备。

## 构建

```bash
./script/build_and_run.sh
```

生成的 App 位于：

```
dist/MiTV-Remote.app
```

## 指定设备 IP

App 默认连接 `192.168.1.50`。可通过环境变量覆盖：

```bash
TV_VOLUME_MITV_HOST=你的设备IP ./script/build_and_run.sh
```

## 技术说明

本 App 通过小米/Redmi 设备暴露的本地 HTTP 接口（端口 6095）进行控制，主要接口包括：

```
/request?action=isalive          — 获取设备名与在线状态
/controller?action=keyevent      — 发送遥控按键
/controller?action=changesource  — 切换输入源
/controller?action=getvolume     — 获取当前音量
/general?action=setVolum         — 精确设置音量（带签名，部分机型支持）
```

音量百分比设置优先使用签名接口 `setVolum`，不支持时自动回退为按键方式。

---

## English

macOS menu bar remote for Xiaomi/Redmi displays and TVs, controlled over LAN via the MiTV Assistant Server on port 6095.

### Features

- **Menu bar app**: Control panel accessible from the menu bar, no Dock icon
- **Volume control**: Drag slider or click buttons to set exact volume percentage
- **HDMI switching**: One-click switch between HDMI 1 and HDMI 2
- **Full remote buttons**: D-pad, OK, Home, Back, Menu, Power
- **Keyboard mapping**: Arrow keys map to remote direction keys while the menu is open
- **LAN device discovery**: Scan the local network and switch between devices
- **Device status**: Shows current device IP and device name in real time

### Usage

Drag `dist/MiTV-Remote.app` to Applications and launch it.

On first use, click the menu bar icon → **搜索/切换设备** (Search/Switch Device) to select a device on the LAN.

### Build

```bash
./script/build_and_run.sh
```

Output:

```
dist/MiTV-Remote.app
```

### Device Address

Defaults to `192.168.1.50`. Override with:

```bash
TV_VOLUME_MITV_HOST=your-device-ip ./script/build_and_run.sh
```
