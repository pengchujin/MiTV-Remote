# MiTV-Remote

macOS menu bar remote for Xiaomi/Redmi displays exposed through MiTV Assistant Server on port 6095.

## Features

- Menu bar app
- Volume percentage control
- HDMI 1 / HDMI 2 source switching
- Compact remote control buttons
- Keyboard arrow keys mapped to remote direction keys while the menu is open
- LAN device discovery and device switching
- Device, online, and last selected HDMI input status display

## Run

```bash
./script/build_and_run.sh
```

## Build App Bundle

```bash
./script/build_and_run.sh --verify
```

The generated app is written to:

```text
dist/MiTV-Remote.app
```

## Device Address

The app defaults to `192.168.1.50`. Override it with:

```bash
TV_VOLUME_MITV_HOST=your-tv-ip ./script/build_and_run.sh
```

## Notes

This app uses Xiaomi/Redmi network remote endpoints such as:

```text
/controller?action=keyevent&keycode=...
/controller?action=changesource&source=hdmi1
/controller?action=changesource&source=hdmi2
```

Some older MiTV models expose a signed `/general?action=setVolum` endpoint. The app tries it first for volume percentage changes and falls back to key events when the endpoint is unavailable.
