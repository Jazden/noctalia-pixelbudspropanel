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
DAEMON_SOCKET = os.path.join(RUNTIME_DIR, "pbpctrl.sock")
CACHE_TTL = 2.5 # seconds

def try_daemon_cmd(cmd_line, timeout=2.0):
    if not os.path.exists(DAEMON_SOCKET):
        return None
    try:
        import socket
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect(DAEMON_SOCKET)
        s.sendall(f"{cmd_line}\n".encode("utf-8"))
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        s.close()
        if data:
            return json.loads(data.decode("utf-8").strip())
    except Exception:
        pass
    return None

def find_device():
    env_mac = os.environ.get("PIXELBUDS_MAC")
    if env_mac:
        clean_mac = env_mac.strip()
        if re.match(r"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", clean_mac):
            dev_name = "Pixel Buds Pro"
            try:
                info_out = subprocess.check_output(["bluetoothctl", "info", clean_mac], text=True, stderr=subprocess.DEVNULL)
                for iline in info_out.split("\n"):
                    iline = iline.strip()
                    if iline.startswith("Alias: "):
                        dev_name = iline.split("Alias: ", 1)[1].strip()
                        break
                    elif iline.startswith("Name: "):
                        dev_name = iline.split("Name: ", 1)[1].strip()
            except Exception:
                pass
            return clean_mac, dev_name
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
    # 1. Fast path: check persistent connection daemon
    d_stat = try_daemon_cmd("status", timeout=1.0)
    if d_stat and d_stat.get("status") == "ok":
        dev = d_stat.get("device") or {}
        presence = d_stat.get("presence") or {}
        cfg = d_stat.get("config") or {}

        if not d_stat.get("connected"):
            return {
                "connected": False,
                "error": "Not connected",
                "mac": dev.get("mac") or "",
                "device_name": dev.get("name") or "Pixel Buds Pro",
                "nearby": presence.get("nearby", False),
                "rssi": presence.get("rssi"),
                "fast_pair_available": presence.get("fast_pair_available", False),
                "fast_pair_scan": cfg.get("fast_pair_scan", True),
                "scan_interval_secs": cfg.get("scan_interval_secs", 10),
            }

        bat = d_stat.get("battery") or {}
        place = d_stat.get("placement") or {}
        anc = d_stat.get("anc") or {}
        sets = d_stat.get("settings") or {}

        b_left = bat.get("left") or {}
        b_right = bat.get("right") or {}
        b_case = bat.get("case") or {}

        g_left = sets.get("gesture_left", "assistant")
        g_right = sets.get("gesture_right", "assistant")

        res = {
            "connected": True,
            "mac": dev.get("mac") or "",
            "device_name": dev.get("name") or "Pixel Buds Pro",
            "model_name": "Google Pixel Buds Pro",
            "battery_left": b_left.get("level") if b_left.get("level") is not None else -1,
            "charging_left": b_left.get("charging", False),
            "battery_right": b_right.get("level") if b_right.get("level") is not None else -1,
            "charging_right": b_right.get("charging", False),
            "battery_case": b_case.get("level") if b_case.get("level") is not None else -1,
            "charging_case": b_case.get("charging", False),
            "placement_left": place.get("left", "unknown"),
            "placement_right": place.get("right", "unknown"),
            "noise_mode": anc.get("state", "off"),
            "eq": sets.get("eq", [0.0, 0.0, 0.0, 0.0, 0.0]),
            "ohd": sets.get("ohd", True),
            "speech_detection": sets.get("speech_detection", False),
            "gesture_left": g_left,
            "gesture_right": g_right,
            "gesture_control": g_left,
            "hold_anc": g_left == "anc",
            "nearby": presence.get("nearby", True),
            "rssi": presence.get("rssi"),
            "fast_pair_available": presence.get("fast_pair_available", True),
            "fast_pair_scan": cfg.get("fast_pair_scan", True),
            "scan_interval_secs": cfg.get("scan_interval_secs", 10),
            "_timestamp": d_stat.get("timestamp", time.time()),
        }
        try:
            with open(CACHE_FILE, "w") as f:
                json.dump(res, f)
        except Exception:
            pass
        return res

    # 2. Fallback to cold binary connection
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
            out_lower = out.lower()
            m_left = re.search(r"left:\s*([a-zA-Z_-]+)", out_lower)
            m_right = re.search(r"right:\s*([a-zA-Z_-]+)", out_lower)
            status["gesture_left"] = "anc" if m_left and "anc" in m_left.group(1) else ("anc" if "anc" in out_lower else "assistant")
            status["gesture_right"] = "anc" if m_right and "anc" in m_right.group(1) else ("anc" if "anc" in out_lower else "assistant")
            status["gesture_control"] = status["gesture_left"]
            status["hold_anc"] = (status["gesture_control"] == "anc")


    try:
        with open(CACHE_FILE, "w") as f:
            json.dump(status, f)
    except Exception:
        pass

    return status

def set_anc(mode):
    target = mode.lower()
    if target == "transparency":
        target = "aware"
    elif target == "anc":
        target = "active"

    d_res = try_daemon_cmd(f"set-anc {target}")
    if d_res and d_res.get("status") == "ok":
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

    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}

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
    d_res = try_daemon_cmd("cycle-anc")
    if d_res and d_res.get("status") == "ok":
        new_mode = d_res.get("anc", "active")
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    data = json.load(f)
                data["noise_mode"] = new_mode
                data["_timestamp"] = time.time()
                with open(CACHE_FILE, "w") as f:
                    json.dump(data, f)
            except Exception:
                pass
        return {"status": "ok", "mode": new_mode}

    curr = None
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                data = json.load(f)
            curr = data.get("noise_mode")
        except Exception:
            pass
    if not curr:
        mac, _ = find_device()
        if not mac:
            return {"error": "Not connected"}
        code, out, _ = run_pbpctrl(["get", "anc"], mac)
        if code == 0 and out:
            curr = out.lower().strip()

    # Cycle: active (ANC) -> aware (transparency) -> off -> active
    if curr == "active":
        next_mode = "aware"
    elif curr == "aware":
        next_mode = "off"
    else:
        next_mode = "active"
    return set_anc(next_mode)

def set_eq(bands):
    d_res = try_daemon_cmd("set-eq " + " ".join(str(b) for b in bands))
    if d_res and d_res.get("status") == "ok":
        return {"status": "ok", "eq": bands}

    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}
    code, _, err = run_pbpctrl(["set", "eq"] + [str(b) for b in bands], mac)
    if code == 0:
        return {"status": "ok", "eq": bands}
    return {"status": "error", "error": err}

def set_ohd(val):
    v = "true" if str(val).lower() in ("true", "1", "yes") else "false"
    d_res = try_daemon_cmd(f"set-ohd {v}")
    if d_res and d_res.get("status") == "ok":
        return {"status": "ok", "ohd": v == "true"}

    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}
    code, _, err = run_pbpctrl(["set", "ohd", v], mac)
    if code == 0:
        return {"status": "ok", "ohd": v == "true"}
    return {"status": "error", "error": err}

def set_speech_detection(val):
    v = "true" if str(val).lower() in ("true", "1", "yes") else "false"
    d_res = try_daemon_cmd(f"set-speech-detection {v}")
    if d_res and d_res.get("status") == "ok":
        return {"status": "ok", "speech_detection": v == "true"}

    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}
    code, _, err = run_pbpctrl(["set", "speech-detection", v], mac)
    if code == 0:
        return {"status": "ok", "speech_detection": v == "true"}
    return {"status": "error", "error": err}

def set_gesture_control(action, side=None):
    act_lower = str(action).lower().strip()
    if act_lower in ("anc", "noise_cancellation", "true", "1", "yes"):
        target = "anc"
    else:
        target = "assistant"

    side_norm = (side or "both").lower().strip()
    if side_norm not in ("left", "right", "both", "all"):
        side_norm = "both"

    if side_norm in ("both", "all"):
        d_res = try_daemon_cmd(f"set-gesture-control {target} {target}")
    else:
        d_res = try_daemon_cmd(f"set-gesture {side_norm} {target}")

    if d_res and d_res.get("status") == "ok":
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    data = json.load(f)
                if side_norm in ("left", "both", "all"):
                    data["gesture_left"] = target
                if side_norm in ("right", "both", "all"):
                    data["gesture_right"] = target
                data["gesture_control"] = data.get("gesture_left", target)
                data["hold_anc"] = (data["gesture_control"] == "anc")
                data["_timestamp"] = time.time()
                with open(CACHE_FILE, "w") as f:
                    json.dump(data, f)
            except Exception:
                pass
        return {
            "status": "ok",
            "side": side_norm,
            "gesture_left": d_res.get("left", target),
            "gesture_right": d_res.get("right", target),
        }

    mac, _ = find_device()
    if not mac:
        return {"error": "Not connected"}

    cached = {}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                cached = json.load(f)
        except Exception:
            pass

    cur_left = cached.get("gesture_left", "assistant")
    cur_right = cached.get("gesture_right", "assistant")

    new_left = target if side_norm in ("left", "both", "all") else cur_left
    new_right = target if side_norm in ("right", "both", "all") else cur_right

    code, _, err = run_pbpctrl(["set", "gesture-control", new_left, new_right], mac)
    if code == 0:
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    data = json.load(f)
                data["gesture_left"] = new_left
                data["gesture_right"] = new_right
                data["gesture_control"] = new_left
                data["hold_anc"] = (new_left == "anc")
                data["_timestamp"] = time.time()
                with open(CACHE_FILE, "w") as f:
                    json.dump(data, f)
            except Exception:
                pass
        return {
            "status": "ok",
            "side": side_norm,
            "gesture_left": new_left,
            "gesture_right": new_right,
        }
    return {"status": "error", "error": err}

def toggle_gesture_control():
    curr = None
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                data = json.load(f)
            curr = data.get("gesture_control")
        except Exception:
            pass
    if not curr:
        mac, _ = find_device()
        if not mac:
            return {"error": "Not connected"}
        code, out, _ = run_pbpctrl(["get", "gesture-control"], mac)
        if code == 0 and out:
            curr = "anc" if "anc" in out.lower() else "assistant"

    next_action = "anc" if curr != "anc" else "assistant"
    return set_gesture_control(next_action)

def get_config():
    d_res = try_daemon_cmd("get-config")
    if d_res and d_res.get("status") == "ok":
        return d_res.get("config", {})
    return {"fast_pair_scan": True, "scan_interval_secs": 10}

def set_config(key, value):
    d_res = try_daemon_cmd(f"set-config {key} {value}")
    if d_res and d_res.get("status") == "ok":
        return d_res
    return {"status": "error", "message": "Daemon not running"}

def connect_device(mac=None):
    if not mac:
        target_mac, _ = find_device()
        mac = target_mac
    if not mac:
        return {"status": "error", "message": "No MAC address found"}
    try:
        proc = subprocess.run(["bluetoothctl", "connect", mac], capture_output=True, text=True, timeout=10)
        return {"status": "ok" if proc.returncode == 0 else "error", "output": proc.stdout}
    except Exception as e:
        return {"status": "error", "message": str(e)}

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
        if len(sys.argv) > 3:
            side = sys.argv[2]
            act = sys.argv[3]
            print(json.dumps(set_gesture_control(act, side=side)))
        else:
            act = sys.argv[2] if len(sys.argv) > 2 else "anc"
            print(json.dumps(set_gesture_control(act, side="both")))
    elif cmd == "toggle-gesture":
        print(json.dumps(toggle_gesture_control()))
    elif cmd == "get-config":
        print(json.dumps(get_config()))
    elif cmd == "set-config":
        key = sys.argv[2] if len(sys.argv) > 2 else "fast-pair-scan"
        val = sys.argv[3] if len(sys.argv) > 3 else "true"
        print(json.dumps(set_config(key, val)))
    elif cmd == "connect":
        mac = sys.argv[2] if len(sys.argv) > 2 else None
        print(json.dumps(connect_device(mac=mac)))
    else:
        print(json.dumps({"error": f"Unknown command: {cmd}"}))

if __name__ == "__main__":
    main()
