<div align="center">
<pre> ██████╗  █████╗ ███████╗███████╗ ██████╗████████╗██╗
██╔════╝ ██╔══██╗╚══███╔╝██╔════╝██╔════╝╚══██╔══╝██║
██║  ███╗███████║  ███╔╝ █████╗  ██║        ██║   ██║
██║   ██║██╔══██║ ███╔╝  ██╔══╝  ██║        ██║   ██║
     ╚██████╔╝██║  ██║███████╗███████╗╚██████╗   ██║   ███████╗
      ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝   ╚═╝   ╚══════╝
</pre>

**Head tracking display switcher for macOS, Linux, and Windows**

<br />

<img src="assets/demo.png" width="500" />

</div>

---

`gazectl` uses your webcam to detect which monitor you're looking at and automatically switches focus to it. On macOS, it uses Apple's Vision framework for real-time face tracking and native macOS APIs to switch monitor focus — no third-party window manager required. On Linux and Windows, it seamlessly uses Python along with `mediapipe` for tracking and `pyautogui` for screen management.

> macOS 14+, Linux, and Windows supported.

## Dependencies

### macOS
gazectl needs two macOS permissions to work:
- **Camera** — for head tracking via the webcam
- **Accessibility** — for moving the cursor and clicking to switch monitor focus

Grant both in **System Settings → Privacy & Security**. macOS will prompt you on first run.

### Linux and Windows
You must have Python 3 installed. You will need to install the dependencies required for tracking and screen management:
```bash
pip install opencv-python mediapipe pyautogui screeninfo
```

## Install

```bash
npx gazectl@latest
```

Or install globally:

```bash
npm i -g gazectl
```

## Usage

```bash
# First run — calibrates automatically
gazectl

# Force recalibration
gazectl --calibrate

# With verbose logging
gazectl --verbose
```

On first run, gazectl asks you to look at each monitor and press Enter. It samples your head angle for 2 seconds per monitor, then saves calibration to `~/.local/share/gazectl/calibration.json`.

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--calibrate` | off | Force recalibration |
| `--calibration-file` | `~/.local/share/gazectl/calibration.json` | Custom calibration path |
| `--camera` | 0 | Camera index |
| `--verbose` | off | Print yaw angle continuously |

## How it works

1. **Calibrate** — look at each monitor, gazectl records the yaw angle
2. **Track** — Apple Vision detects head yaw in real-time (~30fps)
3. **Switch** — when yaw crosses the midpoint between calibrated angles, moves the cursor to the target monitor and clicks to focus

## Build from source

```bash
swift build -c release
cp .build/release/gazectl /usr/local/bin/gazectl
```

# Star History

<p align="center">
  <a target="_blank" href="https://star-history.com/#jnsahaj/gazectl&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jnsahaj/gazectl&type=Date&theme=dark">
      <img alt="GitHub Star History for jnsahaj/gazectl" src="https://api.star-history.com/svg?repos=jnsahaj/gazectl&type=Date">
    </picture>
  </a>
</p>
