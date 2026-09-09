#!/usr/bin/env python3
import sys
import os
import json
import subprocess
import time
import re

import fcntl
import shutil

xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
if xdg_runtime and os.path.isdir(xdg_runtime):
    RUNTIME_DIR = xdg_runtime
else:
    RUNTIME_DIR = f"/tmp/pixelbuds_{os.getuid()}"
    if os.path.islink(RUNTIME_DIR):
        try:
            os.unlink(RUNTIME_DIR)
        except OSError:
            pass
    os.makedirs(RUNTIME_DIR, mode=0o700, exist_ok=True)
    try:
        os.chmod(RUNTIME_DIR, 0o700)
    except OSError:
        pass

CACHE_FILE = os.path.join(RUNTIME_DIR, "pixelbuds_state.json")
LOCK_FILE = os.path.join(RUNTIME_DIR, "pixelbuds_pbpctrl.lock")
CACHE_TTL = 2.5 # seconds

def find_device():
    env_mac = os.environ.get("PIXELBUDS_MAC")
    if env_mac:
        clean_mac = env_mac.strip()
        if re.match(r"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", clean_mac):
            return clean_mac, "Pixel Buds Pro"
    try:
        out = subprocess.check_output(["bluetoothctl", "devices", "Connected"], text=True, stderr=subprocess.DEVNULL)
        for line in out.strip().split("\n"):
            if not line:
                continue
            parts = line.split(" ", 2)
            if len(parts) >= 3:
                mac, name = parts[1], parts[2]
                if "pixel buds" in name.lower() or "pixelbuds" in name.lower():
                    return mac, name
    except Exception:
        pass
    return None, None

def find_pbpctrl():
    path_bin = shutil.which("pbpctrl")
    if path_bin:
        return path_bin
    cargo_bin = os.path.expanduser("~/.cargo/bin/pbpctrl")
    if os.path.isfile(cargo_bin) and os.access(cargo_bin, os.X_OK):
        return cargo_bin
    local_bin = os.path.expanduser("~/.local/bin/pbpctrl")
    if os.path.isfile(local_bin) and os.access(local_bin, os.X_OK):
        return local_bin
    return "pbpctrl"

def run_pbpctrl(args, mac=None):
    pbpctrl_bin = find_pbpctrl()
    cmd = [pbpctrl_bin]
    if mac:
        cmd.extend(["-d", mac])
    cmd.extend(args)
    try:
        lock_f = open(LOCK_FILE, "w")
        fcntl.flock(lock_f, fcntl.LOCK_EX)
    except Exception:
        lock_f = None

    try:
        for attempt in range(3):
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=4.0)
            except subprocess.TimeoutExpired:
                continue
            if res.returncode == 0:
                return 0, res.stdout.strip(), res.stderr.strip()
            err_lower = (res.stderr or "").lower()
            if "already registered" in err_lower or "br-connection" in err_lower or "failedprecondition" in err_lower:
                time.sleep(0.3)
                continue
            break
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    finally:
        if lock_f:
            try:
                fcntl.flock(lock_f, fcntl.LOCK_UN)
                lock_f.close()
            except Exception:
                pass


def get_status(force=False):
    mac, name = find_device()
    if not mac:
        return {"connected": False, "error": "Not connected"}

    if not force and os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                data = json.load(f)
            if time.time() - data.get("_timestamp", 0) < CACHE_TTL and data.get("connected"):
                return data
        except Exception:
            pass

    status = {
        "connected": True,
        "mac": mac,
        "device_name": name,
        "model_name": "Google Pixel Buds Pro",
        "battery_left": -1,
        "charging_left": False,
        "battery_right": -1,
        "charging_right": False,
        "battery_case": -1,
        "charging_case": False,
        "placement_left": "unknown",
        "placement_right": "unknown",
        "noise_mode": "off",
        "eq": [0.0, 0.0, 0.0, 0.0, 0.0],
        "ohd": True,
        "speech_detection": False,
        "_timestamp": time.time()
    }

    code, out, _ = run_pbpctrl(["show", "runtime"], mac)
    if code == 0 and out:
        for line in out.split("\n"):
            line = line.strip()
            # case:      87% (not charging)
            m_case = re.match(r"case:\s+(\d+)%\s+\(([^)]+)\)", line)
            if m_case:
                status["battery_case"] = int(m_case.group(1))
                status["charging_case"] = "charging" in m_case.group(2) and "not" not in m_case.group(2)

            m_left = re.match(r"left bud:\s+(\d+)%\s+\(([^)]+)\)", line)
            if m_left:
                status["battery_left"] = int(m_left.group(1))
                status["charging_left"] = "charging" in m_left.group(2) and "not" not in m_left.group(2)

            m_right = re.match(r"right bud:\s+(\d+)%\s+\(([^)]+)\)", line)
            if m_right:
                status["battery_right"] = int(m_right.group(1))
                status["charging_right"] = "charging" in m_right.group(2) and "not" not in m_right.group(2)

            if line.startswith("left bud:") and "in case" in line:
                status["placement_left"] = "in case" if "out" not in line else "out of case"
            if line.startswith("right bud:") and "in case" in line:
                status["placement_right"] = "in case" if "out" not in line else "out of case"

    code, out, _ = run_pbpctrl(["get", "anc"], mac)
    if code == 0 and out:
        mode = out.lower().strip()
        if mode in ("active", "aware", "off", "adaptive"):
            # Normalize "aware" to "transparency" for consistency with Noctalia convention, or keep "aware"
            status["noise_mode"] = mode

    cached = {}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                cached = json.load(f)
        except Exception:
            pass

    status["eq"] = cached.get("eq", [0.0, 0.0, 0.0, 0.0, 0.0])
    status["ohd"] = cached.get("ohd", True)
    status["speech_detection"] = cached.get("speech_detection", False)
    status["gesture_control"] = cached.get("gesture_control", "assistant")
    status["hold_anc"] = cached.get("hold_anc", False)

    need_full = force or "eq" not in cached or (time.time() - cached.get("_full_timestamp", 0) > 120)
    if need_full:
        status["_full_timestamp"] = time.time()
        code, out, _ = run_pbpctrl(["get", "eq"], mac)
        if code == 0 and out:
            m_eq = re.findall(r"[-+]?\d*\.\d+|\d+", out)
            if len(m_eq) >= 5:
                status["eq"] = [float(x) for x in m_eq[:5]]

        code, out, _ = run_pbpctrl(["get", "ohd"], mac)
        if code == 0 and out:
            status["ohd"] = "true" in out.lower()

        code, out, _ = run_pbpctrl(["get", "speech-detection"], mac)
        if code == 0 and out:
            status["speech_detection"] = "true" in out.lower()

        code, out, _ = run_pbpctrl(["get", "gesture-control"], mac)
        if code == 0 and out:
            status["gesture_control"] = "anc" if "anc" in out.lower() else "assistant"
            status["hold_anc"] = (status["gesture_control"] == "anc")


    try:
        with open(CACHE_FILE, "w") as f:
            json.dump(status, f)
    except Exception:
        pass

    return status

def set_anc(mode):
    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}
    target = mode.lower()
    if target == "transparency":
        target = "aware"
    elif target == "anc":
        target = "active"

    code, _, err = run_pbpctrl(["set", "anc", target], mac)
    if code == 0:
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    data = json.load(f)
                data["noise_mode"] = target
                data["_timestamp"] = time.time()
                with open(CACHE_FILE, "w") as f:
                    json.dump(data, f)
            except Exception:
                pass
        return {"status": "ok", "mode": target}
    else:
        return {"status": "error", "error": err or "Failed to set ANC"}

def cycle_anc():
    curr = get_status().get("noise_mode", "off")
    # Cycle: active (ANC) -> aware (transparency) -> off -> active
    if curr == "active":
        next_mode = "aware"
    elif curr == "aware":
        next_mode = "off"
    else:
        next_mode = "active"
    return set_anc(next_mode)

def set_eq(bands):
    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}
    code, _, err = run_pbpctrl(["set", "eq"] + [str(b) for b in bands], mac)
    if code == 0:
        return {"status": "ok", "eq": bands}
    return {"status": "error", "error": err}

def set_ohd(val):
    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}
    v = "true" if str(val).lower() in ("true", "1", "yes") else "false"
    code, _, err = run_pbpctrl(["set", "ohd", v], mac)
    if code == 0:
        return {"status": "ok", "ohd": v == "true"}
    return {"status": "error", "error": err}

def set_speech_detection(val):
    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}
    v = "true" if str(val).lower() in ("true", "1", "yes") else "false"
    code, _, err = run_pbpctrl(["set", "speech-detection", v], mac)
    if code == 0:
        return {"status": "ok", "speech_detection": v == "true"}
    return {"status": "error", "error": err}

def set_gesture_control(action):
    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}
    act_lower = str(action).lower().strip()
    if act_lower in ("anc", "noise_cancellation", "true", "1", "yes"):
        target = "anc"
    else:
        target = "assistant"

    code, _, err = run_pbpctrl(["set", "gesture-control", target, target], mac)
    if code == 0:
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    data = json.load(f)
                data["gesture_control"] = target
                data["hold_anc"] = (target == "anc")
                data["_timestamp"] = time.time()
                with open(CACHE_FILE, "w") as f:
                    json.dump(data, f)
            except Exception:
                pass
        return {"status": "ok", "gesture_control": target, "hold_anc": target == "anc"}
    return {"status": "error", "error": err}

def toggle_gesture_control():
    curr = get_status().get("gesture_control", "assistant")
    next_action = "anc" if curr != "anc" else "assistant"
    return set_gesture_control(next_action)

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        force = "--force" in sys.argv
        print(json.dumps(get_status(force=force)))
    elif cmd == "set-anc":
        mode = sys.argv[2] if len(sys.argv) > 2 else "active"
        print(json.dumps(set_anc(mode)))
    elif cmd == "cycle-anc":
        print(json.dumps(cycle_anc()))
    elif cmd == "set-eq":
        try:
            bands = [max(-6.0, min(6.0, float(x))) for x in sys.argv[2:7]]
            if len(bands) == 5:
                print(json.dumps(set_eq(bands)))
            else:
                print(json.dumps({"error": "Need 5 bands"}))
        except (ValueError, IndexError):
            print(json.dumps({"error": "Invalid band numbers; must be 5 numeric dB values"}))
    elif cmd == "set-ohd":
        print(json.dumps(set_ohd(sys.argv[2] if len(sys.argv) > 2 else "true")))
    elif cmd == "set-speech-detection":
        print(json.dumps(set_speech_detection(sys.argv[2] if len(sys.argv) > 2 else "true")))
    elif cmd == "set-gesture":
        act = sys.argv[2] if len(sys.argv) > 2 else "anc"
        print(json.dumps(set_gesture_control(act)))
    elif cmd == "toggle-gesture":
        print(json.dumps(toggle_gesture_control()))
    else:
        print(json.dumps({"error": f"Unknown command: {cmd}"}))

if __name__ == "__main__":
    main()
