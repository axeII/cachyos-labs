#!/usr/bin/env python3
import os
import time
import subprocess
import sys
from pathlib import Path

LOG_FILE = Path.home() / ".local" / "share" / "game-profile-monitor.log"
TRIGGERS = [
    "steam.exe",
    "heroic",
    "GamesExplorer",
    "legendary",
    "Beyond-All-Reason.AppImage",
]

PROFILE_GAMING = "cachyos-gaming"
PROFILE_POWERSAVE = "cachyos-powersave"
POLL_INTERVAL = 5
IDLE_TIMEOUT = 60

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def get_current_profile():
    try:
        result = subprocess.run(
            ["tuned-adm", "active"],
            capture_output=True, text=True, timeout=10
        )
        for line in result.stdout.splitlines():
            if "Current active profile:" in line:
                return line.split("Current active profile:")[1].strip()
    except Exception:
        pass
    return None

def set_profile(profile):
    try:
        subprocess.run(
            ["tuned-adm", "profile", profile],
            capture_output=True, timeout=30
        )
    except Exception as e:
        log(f"ERROR: Failed to set profile {profile}: {e}")

def send_notification(title, body):
    try:
        subprocess.run(
            ["notify-send", "-a", "ProfileManager", title, body],
            capture_output=True, timeout=10
        )
    except Exception as e:
        log(f"ERROR: Failed to send notification: {e}")

def scan_processes():
    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            comm_path = f"/proc/{pid}/comm"
            with open(comm_path, "r") as f:
                comm = f.read().strip()
                # Check simple comm triggers
                for trigger in TRIGGERS:
                    if trigger == comm or trigger in comm:
                        found.append(comm)
                        break
                else:
                    # Special case: Steam's reaper launcher (not oom_reaper)
                    if comm == "reaper":
                        cmdline_path = f"/proc/{pid}/cmdline"
                        with open(cmdline_path, "r") as cf:
                            cmdline = cf.read()
                            if "SteamLaunch" in cmdline:
                                found.append("reaper(SteamLaunch)")
        except (PermissionError, FileNotFoundError, ProcessLookupError):
            continue
    return found

def main():
    current = get_current_profile()
    if current and current != PROFILE_POWERSAVE:
        set_profile(PROFILE_POWERSAVE)
        send_notification("🔋 Power Saver", "System reset to power saver profile")
        log("Startup: forced powersave profile")

    last_game_seen = 0
    gaming_active = False

    while True:
        found = scan_processes()
        now = time.time()

        if found:
            last_game_seen = now
            if not gaming_active:
                set_profile(PROFILE_GAMING)
                send_notification("🎮 Gaming Mode", f"Profile switched to gaming ({', '.join(found[:3])})")
                gaming_active = True
                log(f"GAMING: activated by {found}")
        else:
            if gaming_active and (now - last_game_seen) > IDLE_TIMEOUT:
                set_profile(PROFILE_POWERSAVE)
                send_notification("🔋 Power Saver", "All game processes idle — switching to power saver")
                gaming_active = False
                log("POWERSAVE: all game processes gone for 60s")

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()