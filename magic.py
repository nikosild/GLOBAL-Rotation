"""
magic.py — ALiTiS GLOBAL Rotation
=================================================
Single helper process managing two independent modules:

  EVADE   — watches evade_trigger.txt, sends Space to Diablo IV
  BUTCHER — watches butcher_trigger.txt, content = key number (1/2/3/4)
             sends the corresponding keyboard key to Diablo IV

Both modules share the same game window handle and poll loop.
Auto-exits when Diablo IV closes. Prevents duplicate instances.

SET WATCH_DIR below to your GLOBAL Rotation folder, e.g.:
  WATCH_DIR = r"B:\GLYKO\scripts\GLOBAL Rotation"
"""

import ctypes
import ctypes.wintypes
import os
import sys
import time
import subprocess

# ── Config ────────────────────────────────────────────────────────────────────
WATCH_DIR     = None        # None = same folder as this file
POLL_INTERVAL = 0.005       # 5ms
GAME_TITLE    = "Diablo IV"

# ── Trigger file names ────────────────────────────────────────────────────────
EVADE_TRIGGER   = "evade_trigger.txt"
BUTCHER_TRIGGER = "butcher_trigger.txt"

# ── Virtual key codes ─────────────────────────────────────────────────────────
VK_SPACE = 0x20
VK_KEYS  = {
    '1': 0x31,
    '2': 0x32,
    '3': 0x33,
    '4': 0x34,
}
# Mouse buttons
BUTCHER_RIGHTCLICK = 'rc'
BUTCHER_LEFTCLICK  = 'lc'

# ── Windows API ───────────────────────────────────────────────────────────────
user32     = ctypes.windll.user32
WM_KEYDOWN = 0x0100
WM_KEYUP   = 0x0101

INPUT_KEYBOARD  = 1
KEYEVENTF_KEYUP = 0x0002

class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk",         ctypes.wintypes.WORD),
        ("wScan",       ctypes.wintypes.WORD),
        ("dwFlags",     ctypes.wintypes.DWORD),
        ("time",        ctypes.wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]

class INPUT_UNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT)]

class INPUT(ctypes.Structure):
    _fields_ = [
        ("type",   ctypes.wintypes.DWORD),
        ("_input", INPUT_UNION),
    ]

# ── Core key sending ──────────────────────────────────────────────────────────
def _send_key_postmessage(hwnd, vk):
    """Send a key directly to game window via PostMessage."""
    scancode    = user32.MapVirtualKeyW(vk, 0)
    lparam_down = 1 | (scancode << 16)
    lparam_up   = 1 | (scancode << 16) | (1 << 30) | (1 << 31)
    user32.PostMessageW(hwnd, WM_KEYDOWN, vk, lparam_down)
    time.sleep(0.03)
    user32.PostMessageW(hwnd, WM_KEYUP,   vk, lparam_up)

def _send_key_sendinput(vk):
    """Send key via keybd_event — older API, bypasses some security blocks."""
    scancode = user32.MapVirtualKeyW(vk, 0)
    ctypes.windll.user32.keybd_event(vk, scancode, 0, 0)
    time.sleep(0.05)
    KEYEVENTF_KEYUP_FLAG = 0x0002
    ctypes.windll.user32.keybd_event(vk, scancode, KEYEVENTF_KEYUP_FLAG, 0)

def send_key(hwnd, vk):
    """Send key via keybd_event — works with raw input games."""
    _send_key_sendinput(vk)

# ── Utility ───────────────────────────────────────────────────────────────────
def get_game_hwnd():
    hwnd = user32.FindWindowW(None, GAME_TITLE)
    return hwnd if hwnd else None

def is_game_focused(hwnd):
    """Returns True if Diablo IV is the current foreground window."""
    if not hwnd:
        return False
    return user32.GetForegroundWindow() == hwnd

def is_game_running():
    return user32.FindWindowW(None, GAME_TITLE) != 0

def kill_existing_instance(lock_file):
    """Kill all other pythonw.exe instances before starting."""
    my_pid = os.getpid()
    try:
        result = subprocess.check_output(
            ['tasklist', '/FI', 'IMAGENAME eq pythonw.exe', '/FO', 'CSV', '/NH'],
            stderr=subprocess.DEVNULL
        ).decode()
        for line in result.strip().splitlines():
            parts = line.strip('"').split('","')
            if len(parts) >= 2:
                try:
                    pid = int(parts[1])
                    if pid != my_pid:
                        subprocess.call(['taskkill', '/PID', str(pid), '/F'],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception:
                    pass
    except Exception:
        pass
    # Write our own PID lock
    try:
        with open(lock_file, 'w') as f:
            f.write(str(my_pid))
    except Exception:
        pass

def clean_file(path):
    try:
        if os.path.exists(path):
            os.remove(path)
    except Exception:
        pass

# ── EVADE module ──────────────────────────────────────────────────────────────
def handle_evade(evade_trigger, hwnd, counts):
    if not os.path.exists(evade_trigger):
        return hwnd
    try:
        with open(evade_trigger, 'r') as f:
            content = f.read().strip()
        os.remove(evade_trigger)

        # Validate trigger content — must be '1' (written by Lua)
        # Stale or corrupt files are silently discarded
        if content != '1':
            return hwnd

        if not hwnd:
            hwnd = get_game_hwnd()
        if not is_game_focused(hwnd):
            return hwnd
        send_key(hwnd, VK_SPACE)
        counts['evade'] += 1
        print(f"[{time.strftime('%H:%M:%S')}] [EVADE] Space sent #{counts['evade']} via SendInput")
    except Exception as e:
        print(f"[EVADE ERROR] {e}")
    return hwnd

def send_right_click(hwnd):
    """Send right click via keybd_event style mouse_event."""
    MOUSEEVENTF_RIGHTDOWN = 0x0008
    MOUSEEVENTF_RIGHTUP   = 0x0010
    ctypes.windll.user32.mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0)
    time.sleep(0.05)
    ctypes.windll.user32.mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0)

def send_left_click(hwnd):
    """Send left click via mouse_event."""
    MOUSEEVENTF_LEFTDOWN = 0x0002
    MOUSEEVENTF_LEFTUP   = 0x0004
    ctypes.windll.user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    time.sleep(0.05)
    ctypes.windll.user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)

# ── BUTCHER module ────────────────────────────────────────────────────────────
def handle_butcher(butcher_trigger, hwnd, counts):
    if not os.path.exists(butcher_trigger):
        return hwnd
    try:
        with open(butcher_trigger, 'r') as f:
            key_char = f.read().strip()
        os.remove(butcher_trigger)

        if not hwnd:
            hwnd = get_game_hwnd()
        if not is_game_focused(hwnd):
            return hwnd

        if key_char == BUTCHER_RIGHTCLICK:
            send_right_click(hwnd)
            counts['butcher'] += 1
            print(f"[{time.strftime('%H:%M:%S')}] [BUTCHER] Right Click sent #{counts['butcher']} via SendInput")
        elif key_char == BUTCHER_LEFTCLICK:
            send_left_click(hwnd)
            counts['butcher'] += 1
            print(f"[{time.strftime('%H:%M:%S')}] [BUTCHER] Left Click sent #{counts['butcher']} via SendInput")
        else:
            vk = VK_KEYS.get(key_char)
            if vk is None:
                print(f"[BUTCHER ERROR] Unknown key: '{key_char}' (expected 1/2/3/4/rc)")
                return hwnd
            send_key(hwnd, vk)
            counts['butcher'] += 1
            print(f"[{time.strftime('%H:%M:%S')}] [BUTCHER] Key '{key_char}' sent #{counts['butcher']} via SendInput")
    except Exception as e:
        print(f"[BUTCHER ERROR] {e}")
    return hwnd

# ── Main loop ─────────────────────────────────────────────────────────────────
def main():
    if sys.platform != "win32":
        print("[ERROR] Windows only.")
        sys.exit(1)

    watch_dir      = WATCH_DIR or os.path.dirname(os.path.abspath(__file__))
    evade_trigger  = os.path.join(watch_dir, EVADE_TRIGGER)
    butcher_trigger = os.path.join(watch_dir, BUTCHER_TRIGGER)
    lock_file      = os.path.join(watch_dir, "magic.lock")
    os.makedirs(watch_dir, exist_ok=True)

    kill_existing_instance(lock_file)

    # Clean stale triggers
    clean_file(evade_trigger)
    clean_file(butcher_trigger)

    print("=" * 55)
    print("  ALiTiS GLOBAL Rotation — Magic")
    print("=" * 55)
    print(f"  Game     : {GAME_TITLE}")
    print(f"  Poll     : {POLL_INTERVAL*1000:.0f}ms")
    print(f"  EVADE    : {EVADE_TRIGGER}")
    print(f"  BUTCHER  : {BUTCHER_TRIGGER} (content: 1/2/3/4)")
    print("  Auto-exits when Diablo IV closes.")
    print("  Ctrl+C to stop manually.")
    print("=" * 55)

    hwnd = get_game_hwnd()
    if hwnd:
        print(f"  Game window found: HWND={hwnd}")
    else:
        print(f"  WARNING: '{GAME_TITLE}' not found — will retry on each trigger.")
    print()

    counts     = {'evade': 0, 'butcher': 0}
    last_hb    = time.time()
    game_check = time.time()

    try:
        while True:
            now = time.time()

            # Auto-exit when game closes
            if now - game_check >= 5.0:
                game_check = now
                if not is_game_running():
                    print(f"\n[{time.strftime('%H:%M:%S')}] Diablo IV closed — exiting.")
                    break

            # EVADE module
            hwnd = handle_evade(evade_trigger, hwnd, counts)

            # BUTCHER module
            hwnd = handle_butcher(butcher_trigger, hwnd, counts)

            # Heartbeat
            if now - last_hb >= 30:
                last_hb = now
                hwnd = get_game_hwnd()
                print(f"[{time.strftime('%H:%M:%S')}] Alive — evade={counts['evade']} butcher={counts['butcher']} hwnd={hwnd}")

            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        print(f"\nStopped. evade={counts['evade']} butcher={counts['butcher']}")
    finally:
        clean_file(lock_file)
        clean_file(evade_trigger)
        clean_file(butcher_trigger)

if __name__ == "__main__":
    main()
