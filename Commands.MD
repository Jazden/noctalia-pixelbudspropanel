# Google Pixel Buds Pro — Linux Control & Protocol Analysis

This repository contains reverse-engineered tools, documentation, and protocols for interacting with the **Google Pixel Buds Pro** over Bluetooth on Linux.

---

## 1. Bluetooth Architecture & Discovered Profiles

Running a probe against a connected device (`AA:BB:CC:DD:EE:FF`) reveals both standard Bluetooth audio profiles and two proprietary RFCOMM communication channels:

```
Device AA:BB:CC:DD:EE:FF (public)
  Name: Pixel Buds Pro
  Class: 0x00240404 (Audio Headset)
  Modalias: bluetooth:v00E0p3004d0001
```

### Supported UUIDs:
| Profile / Service | UUID | Description |
| :--- | :--- | :--- |
| **Advanced Audio Distribution (A2DP)** | `0000110d-0000-1000-8000-00805f9b34fb` | High quality audio streaming (SBC / AAC) |
| **A/V Remote Control (AVRCP)** | `0000110e-0000-1000-8000-00805f9b34fb` | Media playback controls & basic combined battery |
| **Handsfree Profile (HFP)** | `0000111e-0000-1000-8000-00805f9b34fb` | Voice calls & microphone audio |
| **Google Fast Pair Service (GFPS)** | `df21fe2c-2515-4fdb-8886-f12c4d67927c` | **RFCOMM Message Stream**: Battery telemetry (left/right/case), SASS multi-point switching, ringing |
| **Fast Pair GATT Service** | `f8d1fbe4-7966-4334-8024-ff96c9330e15` | BLE Fast Pair advertising & key exchange |
| **Google Maestro Protocol** | `25e97ff7-24ce-4c4c-8951-f764a708f7b5` | **RFCOMM Pigweed RPC**: Full settings control (ANC, EQ, gestures, OHD, telemetry) |
| **Vendor Specific (Pro 2 / Aux)** | `25e97ff7-24ce-4c4c-8951-f764a708f7b4` | Secondary vendor endpoint |
| **Vendor Specific** | `74c34f02-a774-4f6d-ae2e-dab5030b5842` | Firmware / diagnostic bridge |
| **Vendor Specific** | `81c2e72a-0591-443e-a1ff-05f988593351` | Companion app communication channel |

---

## 2. Fast Pair Service (GFPS) Protocol

* **Transport**: Direct RFCOMM socket on UUID `df21fe2c-2515-4fdb-8886-f12c4d67927c`.
* **Framing**: `[Group (1 byte)] [Code (1 byte)] [Length (2 bytes BE)] [Payload]`
* **Battery Telemetry** (`Group 0x03, Code 0x03`):
  * Byte 0: Left Bud battery byte
  * Byte 1: Right Bud battery byte
  * Byte 2: Case battery byte
  * *Bit format*: Bit 7 (`0x80`) is `is_charging` (1 = charging, 0 = discharging). Bits 0–6 (`0x7F`) represent the percentage (`0..100%`). `0xFF` or `0x7F` indicates Unknown.
* **Remaining Time** (`Group 0x03, Code 0x04`): Remaining battery duration in minutes.
* **Device Ringing** (`Group 0x04, Code 0x01`): Trigger Find My Device acoustic ring.

---

## 3. Maestro Control Protocol (Pigweed RPC)

* **Transport**: RFCOMM socket on UUID `25e97ff7-24ce-4c4c-8951-f764a708f7b5`.
* **Framing**: High-Level Data Link Control (HDLC) U-frames (`control = 0x03`) wrapping Google Pigweed RPC (`pw_rpc`) packets with Protocol Buffers (`protobuf`).
* **Addressing**:
  * Internal peers: `Host` (1), `Case` (2), `LeftBtCore` (3), `RightBtCore` (4), `LeftSensorHub` (5), `RightSensorHub` (6), `MaestroA` (10), `MaestroB` (13).
  * Method names are hashed using Pigweed's `hash_65599` algorithm:
    * `maestro_pw.Maestro` = `0x7ede71ea`
    * `GetSoftwareInfo` = `0x7199fa44`
    * `GetHardwareInfo` = `0xb95192ec`
    * `WriteSetting` = `0x9e8c9a1d`
    * `ReadSetting` = `0xc39116a4`

---

## 4. Setting Active Noise Cancellation (ANC)

### Available ANC Modes:
* **`active`**: Active Noise Cancellation (ANC enabled)
* **`aware`**: Transparency mode (environmental sound pass-through)
* **`off`**: Standard passive isolation (ANC & Transparency disabled)
* **`adaptive`**: Dynamic environmental adjustment

### Commands:
```bash
# Check current ANC status
./pixelbuds anc

# Set ANC mode
./pixelbuds anc active
./pixelbuds anc aware
./pixelbuds anc off
./pixelbuds anc adaptive

# Configure touch-and-hold gesture loop (which modes to cycle through)
pbpctrl set anc-gesture-loop true true true false
# Syntax: <off> <active> <aware> <adaptive> (boolean flags)
```

> [!IMPORTANT]
> **Precondition Requirement (`FailedPrecondition` / Status 9)**:
> If you execute `./pixelbuds anc active` while one of the earbuds is docked inside the charging case or not detected in your ear, the earbuds' firmware will reject the RPC with:
> `Error: status: FailedPrecondition, message: "The system is not in a state required for the operation's execution"`
> Both earbuds must be removed from the charging case and placed in your ears to toggle ANC modes (unless single-bud ANC accessibility mode is supported by the firmware).

---

## 5. Other Configurable Features

### 5-Band Equalizer (EQ)
Values range from `-6.0` to `+6.0` dB across: Low Bass, Bass, Mid, Treble, Upper Treble.
```bash
# Read current EQ
./pixelbuds eq

# Set custom EQ (e.g., bass boost)
./pixelbuds eq 5.0 3.0 0.0 0.0 0.0
```

### Volume Balance
```bash
# Set balance (-100 = full left, 0 = centered, +100 = full right)
pbpctrl set balance 0
```

### In-Ear / On-Head Detection (OHD)
```bash
# Enable or disable automatic pause when removing an earbud
pbpctrl set ohd true
pbpctrl set ohd false
```

### Touch Gestures
```bash
# Enable/disable touch gestures
pbpctrl set gestures true

# Configure hold gesture action ('anc' or 'assistant')
pbpctrl set gesture-control anc assistant
```

### Multipoint Audio
```bash
# Toggle seamless switching between two connected Bluetooth devices
pbpctrl set multipoint true
```

### Conversation Awareness (Speech Detection)
```bash
# Automatically switch to transparency when you speak
pbpctrl set speech-detection true
```

### Telemetry & Hardware Info
```bash
# Show serial numbers, firmware version, battery, and bud placement
./pixelbuds status
```

---

## 6. Battery Cycles & State of Health (SoH) Analysis

### What the Buds Expose:
1. **Real-time State of Charge (SoC)**: Granular percentages for Left Bud, Right Bud, and Charging Case (e.g. `Left: 95%`, `Right: 100%`, `Case: 87%`).
2. **Charging State**: Real-time status (`charging` vs `not charging`) per component.
3. **Placement State**: Real-time reporting of whether each earbud is docked `in case` or `out of case`.
4. **Estimated Remaining Time**: Remaining run time in minutes via GFPS.

### Battery Health / Cycle Count Verdict:
* **No Battery Cycles Exposed**: Battery cycle counts are **not accessible** over the Bluetooth protocols.
* **No State of Health (SoH) Percentage**: Neither standard Bluetooth GATT Battery Service (`0x180F`), Google Fast Pair Service (GFPS), nor the Maestro Pigweed RPC API provide a method or protobuf field for battery wear, health percentage, or cycle counts.
* **Hardware Reason**: The Fuel Gauge / PMIC inside each bud tracks charging cycles internally for thermal and charging curve safety, but Google’s firmware does not expose these registers to the companion app or external RPC callers. Battery diagnostics on Pixel Buds are restricted to real-time voltage/capacity thresholds and acoustic seal checks.

---

## 7. Noctalia Desktop Shell Plugin (`jazden/pixelbuds`)

A native desktop shell integration for [Noctalia](https://noctalia.dev/) is included in the [`plugin/`](./plugin) directory (and installed at `~/.local/share/noctalia/plugins/pixelbuds`).

### Features:
* **Bar Widget**: Live listening mode glyph (`shield-check` for ANC, `ear` for Transparency, `headphones` for Off) and earbud battery %.
  * **Left-click**: Toggles the control panel.
  * **Right-click**: Cycles listening modes (`ANC` → `Transparency` → `Off`).
* **Floating Control Panel**:
  * 3-way battery meters for Left Bud, Case, and Right Bud.
  * Mode buttons: Active Noise Cancellation, Transparency, Off.
  * **Collapsible 5-Band Equalizer**: Hidden by default behind a clean dropdown toggle; expands to 5 sliders (-6.0 dB to +6.0 dB) with fixed table alignment and identical bar lengths.
  * In-Ear Detection and Conversation Awareness toggles.
### Prerequisites:
This plugin and the `./pixelbuds` CLI wrapper communicate with the Pixel Buds via [`pbpctrl`](https://github.com/qzed/pbpctrl). Ensure `pbpctrl` is installed on your `PATH`:

```bash
# Install via Cargo
cargo install --git https://github.com/qzed/pbpctrl.git

# Or ensure ~/.cargo/bin or ~/.local/bin is in your PATH
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
```

### Installation & Usage:
```bash
# Link or copy to Noctalia plugins directory
ln -s "$(pwd)/plugin" ~/.local/share/noctalia/plugins/pixelbuds

# Enable in Noctalia
noctalia msg plugins enable jazden/pixelbuds

# Toggle panel via IPC
noctalia msg panel-toggle jazden/pixelbuds:panel

# Cycle noise modes via IPC / keybind
noctalia msg plugin jazden/pixelbuds:service all cycle-noise
```
