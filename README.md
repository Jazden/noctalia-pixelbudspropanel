# Google Pixel Buds Pro for Linux & Noctalia Shell

A complete Linux integration and desktop shell plugin for the **Google Pixel Buds Pro** and **Noctalia**.

Features a native top-bar widget, a floating popup control panel, standalone CLI tooling, and full IPC command support for window manager keybindings.

---

## Features

* **Top-Bar Widget**:
  * Live noise cancellation glyph (`shield-check` for ANC, `ear` for Transparency, `headphones` for Off).
  * Real-time earbud battery percentage.
  * Interactive tooltip showing Left Bud, Right Bud, and Case battery levels with charging indicators.
  * **Fast Pair Presence Detection**: When the earbuds are disconnected (e.g. in case or connected to other devices via Bluetooth Multipoint) but nearby, the top-bar widget automatically appears displaying the headphones logo alongside the broadcast icon (`broadcast`), showing nearby signal strength in dBm.
  * **Left-Click**: Toggles the control panel.
  * **Right-Click**: Quickly cycles noise modes (`ANC` → `Transparency` → `Off`).

* **Floating Control Panel**:
  * Symmetrical 3-way battery meters for Left Bud, Case, and Right Bud.
  * Instant Active Noise Cancellation (ANC), Transparency, and Off mode buttons.
  * **Collapsible 5-Band Equalizer**: Expandable panel with sliders (-6.0 dB to +6.0 dB) for Low Bass, Bass, Mid, Treble, and Upper Treble with fixed table alignment.
  * **Settings Accordion (Available Connected & Disconnected)**:
    * **Fast Pair BLE Scanning**: Toggle background Fast Pair BLE discovery on or off in `pbpctrld`.
    * **BLE Scan Interval**: Adjust scanning frequency (**5s**, **10s**, **15s**, **30s**) persisted to `~/.config/pbpctrl/config.json`.
    * **Touch & Hold Controls**: Compact 2x2 radio table for Left and Right earbuds (Noise Control vs Google Assistant).
    * **Hardware Toggles**: In-Ear Detection (pause on remove) and Conversation Awareness (auto-transparency).
  * **Nearby Presence Card**: Disconnected state displays an advertisement badge with signal strength (RSSI in dBm) and a one-click **"Connect Earbuds"** button.
  * **Auto-Scrolling**: Fully contained vertical scrolling prevents popups from overflowing smaller screen viewports when multiple sections are expanded.

* **IPC & Scripting**:
  * Full IPC event support via `noctalia msg` for custom hotkeys, scripts, and window managers.

* **CLI Utility (`./pixelbuds`)**:
  * Standalone terminal script for inspecting telemetry and adjusting settings without opening the UI.

---

## Prerequisites

1. **Linux Bluetooth**: `bluez` with `bluetoothctl` running.
2. **Python 3**: For the plugin backend bridge.
3. **Backend Client / Daemon**:
   - **Recommended (`pbpctrld`)**: High-performance persistent connection daemon for near-instant (~20ms) controls and background Fast Pair BLE presence scanning:
     ```bash
     git clone https://github.com/Jazden/pbpctrld.git
     cd pbpctrld && cargo build --release -p pbpctrld
     cp target/release/pbpctrld ~/.cargo/bin/
     systemctl --user enable --now pbpctrld
     ```
   - **Alternative (`pbpctrl`)**: Standard one-shot CLI client (the plugin automatically falls back to `pbpctrl` if `pbpctrld` is not installed):
     ```bash
     cargo install --git https://github.com/qzed/pbpctrl.git
     ```

Make sure Cargo's binary directory is in your `$PATH`:
```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

---

## Installation

### 1. Clone the Repository
```bash
git clone https://github.com/Jazden/noctalia-pixelbudspropanel.git
cd noctalia-pixelbudspropanel
```

### 2. Install the Noctalia Plugin
Symlink or copy the `plugin/` folder into your Noctalia plugins directory:
```bash
ln -s "$(pwd)/plugin" ~/.local/share/noctalia/plugins/pixelbuds
```

### 3. Enable the Plugin in Noctalia
```bash
noctalia msg plugins enable jazden/pixelbudspro
```

### 4. Add the Widget to Your Bar
1. Open Noctalia Settings (press **Super** or click the settings icon).
2. Go to **Bar** → **Widgets**.
3. Add **Pixel Buds Pro** to your preferred position (start, center, or end).

---

## IPC Commands & Keybindings

You can bind Noctalia IPC commands to window manager key combinations (e.g. Niri, Hyprland, Sway, i3).

### Available IPC Commands:

| Action | Command |
| :--- | :--- |
| **Toggle Control Panel** | `noctalia msg panel-toggle jazden/pixelbudspro:panel` |
| **Open Control Panel** | `noctalia msg panel-open jazden/pixelbudspro:panel` |
| **Close Control Panel** | `noctalia msg panel-close jazden/pixelbudspro:panel` |
| **Cycle Noise Modes** | `noctalia msg plugin jazden/pixelbudspro:service all cycle-noise` |
| **Set Mode: ANC** | `noctalia msg plugin jazden/pixelbudspro:service all set-noise active` |
| **Set Mode: Transparency** | `noctalia msg plugin jazden/pixelbudspro:service all set-noise aware` |
| **Set Mode: Off** | `noctalia msg plugin jazden/pixelbudspro:service all set-noise off` |
| **Toggle Hold Gesture** | `noctalia msg plugin jazden/pixelbudspro:service all toggle-gesture` |
| **Set Hold Gesture: ANC** | `noctalia msg plugin jazden/pixelbudspro:service all set-gesture anc` |
| **Set Hold Gesture: Assistant** | `noctalia msg plugin jazden/pixelbudspro:service all set-gesture assistant` |
| **Force Refresh** | `noctalia msg plugin jazden/pixelbudspro:service all refresh` |

### Window Manager Configuration Examples:

#### Niri (`~/.config/niri/config.kdl`):
```kdl
binds {
    // Toggle Pixel Buds control panel
    Mod+Shift+P { spawn "noctalia" "msg" "panel-toggle" "jazden/pixelbudspro:panel"; }

    // Cycle through ANC -> Transparency -> Off
    Mod+Shift+N { spawn "noctalia" "msg" "plugin" "jazden/pixelbudspro:service" "all" "cycle-noise"; }
}
```

#### Hyprland (`~/.config/hypr/hyprland.conf`):
```ini
bind = $mainMod SHIFT, P, exec, noctalia msg panel-toggle jazden/pixelbudspro:panel
bind = $mainMod SHIFT, N, exec, noctalia msg plugin jazden/pixelbudspro:service all cycle-noise
```

#### Sway / i3 (`~/.config/sway/config`):
```ini
bindsym $mod+Shift+p exec noctalia msg panel-toggle jazden/pixelbudspro:panel
bindsym $mod+Shift+n exec noctalia msg plugin jazden/pixelbudspro:service all cycle-noise
```

---

## Standalone CLI Usage (`./pixelbuds`)

A lightweight bash CLI wrapper is provided in the repository root for terminal workflows:

```bash
# Check device status, placement, and battery levels
./pixelbuds status

# Check current ANC mode
./pixelbuds anc

# Set ANC mode (active, aware, off)
./pixelbuds anc active
./pixelbuds anc aware
./pixelbuds anc off

# Check 5-band Equalizer values
./pixelbuds eq

# Set custom Equalizer (Low Bass, Bass, Mid, Treble, Upper Treble in dB from -6.0 to +6.0)
./pixelbuds eq 4.0 2.5 0.0 1.0 2.0

# Check Touch & Hold Gesture action (ANC vs Assistant)
./pixelbuds gesture

# Toggle Hold Gesture between ANC and Assistant
./pixelbuds gesture toggle

# Set Hold Gesture explicitly (anc or assistant)
./pixelbuds gesture anc
./pixelbuds gesture assistant

# Fast Pair BLE Scanning Configuration (when using pbpctrld)
./pixelbuds config get
./pixelbuds config set fast-pair-scan true     # Enable or disable background scanning
./pixelbuds config set scan-interval 15       # Set scan interval in seconds (5s, 10s, 15s, etc.)
```

> [!NOTE]
> If your device name is customized and not automatically detected, specify the Bluetooth MAC address explicitly:
> ```bash
> DEVICE=AA:BB:CC:DD:EE:FF ./pixelbuds status
> ```
> Or for the Noctalia plugin, set the `PIXELBUDS_MAC` environment variable.

---

## Protocol & Advanced Documentation

For detailed reverse-engineering findings, Bluetooth UUIDs, Google Fast Pair Service (GFPS) framing, and Google Maestro Pigweed RPC protocol analysis, see [`Commands.MD`](./Commands.MD).

---

## License

This project is licensed under the [MIT License](./plugin/plugin.toml).
