#!/usr/bin/env python3
"""
OptiScaler Manager - CLI tool to manage OptiScaler installations across multiple games.
Usage:
  optiscaler list                    # List all managed games
  optiscaler status                  # Check version status of all games
  optiscaler update [game]           # Update game(s) to latest version
  optiscaler add <name>              # Search and add a game
  optiscaler remove <name>           # Remove a game from management
  optiscaler check                   # Check for new versions on GitHub
  optiscaler --tui                   # Launch interactive TUI mode
"""

import os
import sys
import json
import subprocess
import shutil
import zipfile
import tempfile
import argparse
import re
from difflib import SequenceMatcher
from pathlib import Path
from datetime import datetime
from typing import Optional, List

try:
    from rich.console import Console
    from rich.table import Table
    from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn
    from rich.prompt import Prompt, Confirm
    from rich.panel import Panel
    from rich.align import Align
except ImportError:
    print("Installing rich library...", file=sys.stderr)
    subprocess.run([sys.executable, "-m", "pip", "install", "rich"], check=True)
    from rich.console import Console
    from rich.table import Table
    from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn
    from rich.prompt import Prompt, Confirm
    from rich.panel import Panel
    from rich.align import Align

GITHUB_API_URL = "https://api.github.com/repos/optiscaler/OptiScaler/releases/latest"
CONFIG_DIR = Path.home() / ".config" / "optiscaler"
GAMES_FILE = CONFIG_DIR / "games.json"
CONFIG_FILE = CONFIG_DIR / "config.json"
RELEASES_DIR = CONFIG_DIR / "releases"

STEAM_COMMON_PATH = Path.home() / ".local" / "share" / "Steam" / "steamapps" / "common"
STEAM_MNT_PATH = Path("/mnt/games/SteamLibrary/steamapps/common")
HEROIC_PREFIXES = [Path.home() / "Games" / "Heroic", Path("/mnt/games/Heoric")]

SCAN_FILE = CONFIG_DIR / "installed_scan.json"
COMPAT_FILE = CONFIG_DIR / "compatibility_cache.json"

STEAM_NON_GAMES = {
    "steamlinuxruntime", "steamlinuxruntime 3.0", "steamlinuxruntime - soldier",
    "proton", "proton - experimental", "proton 9.0", "proton 8.0", "proton 7.0",
    "proton ge", "proton-ge-custom", "steam native runtime",
    "steamworks shared", "steam redistributable", "steam libraries",
    "controller blueprint", "steam game association", "steam input mappings",
    "valve游戏的default", "vrbin", "vrconfig", "vrdrivers",
}

console = Console()


def ensure_config_dirs():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    RELEASES_DIR.mkdir(parents=True, exist_ok=True)


def load_config() -> dict:
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    return {"current_version": None, "latest_version": None, "last_check": None, "skipped_versions": [], "user_gpu_type": "amd"}


def save_config(config: dict):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)


def load_games() -> list:
    if GAMES_FILE.exists():
        with open(GAMES_FILE, 'r') as f:
            data = json.load(f)
            return data.get("games", [])
    return []


def save_games(games: list):
    with open(GAMES_FILE, 'w') as f:
        json.dump({"games": games}, f, indent=2)


def detect_gpu_type() -> str:
    try:
        result = subprocess.run(['nvidia-smi'], capture_output=True, text=True)
        if result.returncode == 0:
            return "nvidia"
    except FileNotFoundError:
        pass
    return "amd"


def find_steam_games() -> dict:
    games = {}
    for steam_path in [STEAM_COMMON_PATH, STEAM_MNT_PATH]:
        if not steam_path.exists():
            continue
        for game_path in steam_path.iterdir():
            if not game_path.is_dir():
                continue
            possible_paths = [
                game_path / "OptiScaler.ini",
                game_path / "DeadIsland" / "Binaries" / "Win64" / "OptiScaler.ini",
                game_path / "SwGame" / "Binaries" / "Win64" / "OptiScaler.ini",
                game_path / "PenDriverPro" / "Binaries" / "Win64" / "OptiScaler.ini",
                game_path / "binaries" / "OptiScaler.ini",
                game_path / "Retail" / "OptiScaler.ini",
            ]
            ini_path = None
            for p in possible_paths:
                if p.exists():
                    ini_path = p
                    break
            if ini_path:
                games[game_path.name.lower()] = {
                    "name": game_path.name, "platform": "steam",
                    "path": str(ini_path.parent), "exe_path": None
                }
    return games


def find_heroic_games() -> dict:
    games = {}
    for heroic_prefix in HEROIC_PREFIXES:
        if not heroic_prefix.exists():
            continue
        for game_dir in heroic_prefix.iterdir():
            if not game_dir.is_dir():
                continue
            ini_path = game_dir / "bin" / "x64" / "OptiScaler.ini"
            if not ini_path.exists():
                for subdir in ["bin/x64", "Binaries/Win64"]:
                    test_path = game_dir / subdir / "OptiScaler.ini"
                    if test_path.exists():
                        ini_path = test_path
                        break
            if ini_path.exists():
                games[game_dir.name.lower()] = {
                    "name": game_dir.name, "platform": "gog",
                    "path": str(ini_path.parent), "exe_path": None
                }
    return games


def search_games_by_name(query: str) -> list:
    def match_score(q: str, candidate: str) -> float:
        q_norm = normalize_name(q)
        c_norm = normalize_name(candidate)
        q_compact = q_norm.replace(" ", "")
        c_compact = c_norm.replace(" ", "")

        if q_norm == c_norm or q_compact == c_compact:
            return 1.0
        if q_norm in c_norm or q_compact in c_compact:
            return 0.95

        return SequenceMatcher(None, q_compact, c_compact).ratio()

    scored = []
    seen = set()
    query_norm = normalize_name(query)
    query_compact = query_norm.replace(" ", "")

    for steam_path in [STEAM_COMMON_PATH, STEAM_MNT_PATH]:
        if not steam_path.exists():
            continue
        for game_path in steam_path.iterdir():
            if not game_path.is_dir():
                continue
            score = match_score(query, game_path.name)
            if score < 0.62:
                continue
            key = (game_path.name.lower(), "steam")
            if key in seen:
                continue
            seen.add(key)
            scored.append((score, {"name": game_path.name, "platform": "steam", "path": str(game_path)}))

    for heroic_prefix in HEROIC_PREFIXES:
        if not heroic_prefix.exists():
            continue
        for game_path in heroic_prefix.iterdir():
            if not game_path.is_dir():
                continue
            score = match_score(query, game_path.name)
            if score < 0.62:
                continue
            key = (game_path.name.lower(), "gog")
            if key in seen:
                continue
            seen.add(key)
            scored.append((score, {"name": game_path.name, "platform": "gog", "path": str(game_path)}))

    scored.sort(key=lambda item: (-item[0], item[1]["name"].lower()))
    return [item[1] for item in scored]


def detect_game_target_dir(game_root: Path) -> Path:
    preferred_rel = [
        ".",
        "Binaries/Win64",
        "bin/x64",
        "bin",
        "binaries",
        "Retail",
        "DeadIsland/Binaries/Win64",
        "SwGame/Binaries/Win64",
        "PenDriverPro/Binaries/Win64",
    ]

    for rel in preferred_rel:
        candidate = game_root / rel
        if (candidate / "OptiScaler.ini").exists():
            return candidate

    exe_candidates = []
    skip_tokens = ("uninstall", "setup", "crash", "report", "benchmark", "launcher")
    game_name_norm = normalize_name(game_root.name)

    for exe in game_root.rglob("*.exe"):
        exe_name_norm = normalize_name(exe.stem)
        if any(token in exe_name_norm for token in skip_tokens):
            continue

        score = 0
        if exe.parent == game_root:
            score += 5
        if exe.parent.name.lower() in {"win64", "x64"}:
            score += 3
        if game_name_norm and game_name_norm.replace(" ", "") in exe_name_norm.replace(" ", ""):
            score += 4
        score -= len(exe.parts)
        exe_candidates.append((score, exe.parent))

    if exe_candidates:
        exe_candidates.sort(key=lambda item: item[0], reverse=True)
        return exe_candidates[0][1]

    return game_root


def match_name_score(query: str, candidate: str) -> float:
    q_norm = normalize_name(query)
    c_norm = normalize_name(candidate)
    q_compact = q_norm.replace(" ", "")
    c_compact = c_norm.replace(" ", "")

    if q_norm == c_norm or q_compact == c_compact:
        return 1.0
    if q_norm in c_norm or q_compact in c_compact:
        return 0.95
    return SequenceMatcher(None, q_compact, c_compact).ratio()


def find_managed_games(games: list, query: str, min_score: float = 0.62) -> list:
    scored = []
    for game in games:
        score = match_name_score(query, game["name"])
        if score >= min_score:
            scored.append((score, game))
    scored.sort(key=lambda item: (-item[0], item[1]["name"].lower()))
    return [item[1] for item in scored]


def has_optiscaler_installed(game: dict) -> bool:
    game_path = Path(game.get("path", ""))
    if not game_path.exists():
        return False

    dll_name = game.get("dll_name", "dxgi.dll")
    markers = [
        game_path / dll_name,
        game_path / "OptiScaler.ini",
        game_path / "fakenvapi.dll",
        game_path / "D3D12_Optiscaler",
    ]
    return any(marker.exists() for marker in markers)


def refresh_managed_paths(games: list) -> list:
    scanned = scan_installed_games()
    updated = False

    for game in games:
        current = Path(game.get("path", ""))
        if current.exists():
            continue

        candidates = [
            s for s in scanned
            if s.get("platform") == game.get("platform")
        ]
        if not candidates:
            continue

        best = None
        best_score = 0.0
        for cand in candidates:
            score = match_name_score(game["name"], cand["name"])
            if score > best_score:
                best_score = score
                best = cand

        if best and best_score >= 0.85:
            new_path = detect_game_target_dir(Path(best["path"]))
            game["path"] = str(new_path)
            updated = True

    if updated:
        save_games(games)

    return games


def check_github_version() -> tuple[Optional[str], Optional[str]]:
    try:
        import urllib.request
        req = urllib.request.Request(GITHUB_API_URL, headers={"User-Agent": "Python/3"})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
        tag_name = data.get("tag_name", "").lstrip('v')
        return tag_name, data.get("html_url", "")
    except Exception as e:
        return None, None


def is_real_game(name: str) -> bool:
    n = name.lower().strip()
    if n in STEAM_NON_GAMES:
        return False
    for blocked in STEAM_NON_GAMES:
        if blocked in n:
            return False
    return True


def scan_installed_games() -> list:
    found = []
    seen_names = set()

    for steam_path in [STEAM_COMMON_PATH, STEAM_MNT_PATH]:
        if not steam_path.exists():
            continue
        for game_path in steam_path.iterdir():
            if not game_path.is_dir():
                continue
            name = game_path.name
            if name.lower() in seen_names:
                continue
            if not is_real_game(name):
                continue
            seen_names.add(name.lower())

            ini_path = None
            for pattern in [
                game_path / "OptiScaler.ini",
                game_path / "DeadIsland" / "Binaries" / "Win64" / "OptiScaler.ini",
                game_path / "SwGame" / "Binaries" / "Win64" / "OptiScaler.ini",
                game_path / "PenDriverPro" / "Binaries" / "Win64" / "OptiScaler.ini",
                game_path / "binaries" / "OptiScaler.ini",
                game_path / "Retail" / "OptiScaler.ini",
            ]:
                if pattern.exists():
                    ini_path = pattern
                    break

            found.append({
                "name": name,
                "platform": "steam",
                "path": str(game_path),
                "optiscaler_installed": ini_path is not None,
                "optiscaler_path": str(ini_path.parent) if ini_path else None,
            })

    for heroic_prefix in HEROIC_PREFIXES:
        if not heroic_prefix.exists():
            continue
        for game_dir in heroic_prefix.iterdir():
            if not game_dir.is_dir():
                continue
            name = game_dir.name
            if name.lower() in seen_names:
                continue
            if not is_real_game(name):
                continue
            seen_names.add(name.lower())

            ini_path = None
            for subdir in ["bin/x64", "Binaries/Win64", "bin"]:
                test_path = game_dir / subdir / "OptiScaler.ini"
                if test_path.exists():
                    ini_path = test_path
                    break

            found.append({
                "name": name,
                "platform": "gog",
                "path": str(game_dir),
                "optiscaler_installed": ini_path is not None,
                "optiscaler_path": str(ini_path.parent) if ini_path else None,
            })

    with open(SCAN_FILE, 'w') as f:
        json.dump({"games": found, "scanned_at": datetime.now().isoformat()}, f, indent=2)

    return found


def load_scan() -> list:
    if SCAN_FILE.exists():
        with open(SCAN_FILE, 'r') as f:
            data = json.load(f)
            return data.get("games", [])
    return []


def fetch_compatibility_list() -> dict:
    compat_url = "https://raw.githubusercontent.com/wiki/optiscaler/OptiScaler/Compatibility-List.md"
    cache = {}
    try:
        import urllib.request
        req = urllib.request.Request(compat_url, headers={"User-Agent": "Python/3"})
        with urllib.request.urlopen(req, timeout=15) as response:
            content = response.read().decode('utf-8', errors='ignore')

        for line in content.split('\n'):
            line = line.strip()
            if not line.startswith('|') or line.startswith('|-'):
                continue
            parts = [p.strip() for p in line.split('|')]
            if len(parts) < 3 or not parts[1]:
                continue

            raw_name = parts[1]
            compat_raw = parts[2] if len(parts) > 2 else ''

            name_key = raw_name.lower()

            compat = 'unknown'
            if '✅' in compat_raw:
                compat = 'yes'
            elif '❌' in compat_raw:
                compat = 'no'
            elif '➖' in compat_raw:
                compat = 'partial'

            cache[name_key] = compat

        with open(COMPAT_FILE, 'w') as f:
            json.dump({"cache": cache, "fetched_at": datetime.now().isoformat()}, f, indent=2)
        print(f"Compatibility list updated: {len(cache)} entries")
    except Exception as e:
        print(f"Failed to fetch compatibility list: {e}")
        if COMPAT_FILE.exists():
            with open(COMPAT_FILE, 'r') as f:
                old = json.load(f)
                cache = old.get("cache", {})
    return cache


def load_compat_cache() -> dict:
    if COMPAT_FILE.exists():
        with open(COMPAT_FILE, 'r') as f:
            data = json.load(f)
            return data.get("cache", {})
    return {}


def normalize_name(name: str) -> str:
    n = name
    n = re.sub(r'([a-z])([A-Z])', r'\1 \2', n)
    n = re.sub(r'([A-Za-z])([0-9])', r'\1 \2', n)
    n = re.sub(r'([0-9])([A-Za-z])', r'\1 \2', n)
    n = n.lower()
    n = n.replace('‐', '-').replace('\u2010', '-').replace('\u2011', '-')
    n = re.sub(r"['\u0027\u2018\u2019]", '', n)
    n = re.sub(r'[^a-z0-9]', ' ', n)
    n = re.sub(r'\s+', ' ', n).strip()
    return n


def compact_name(name: str) -> str:
    return normalize_name(name).replace(' ', '')


def build_compat_index(cache: dict) -> tuple[dict, list]:
    index = {}
    names = []

    def add_variant(variant: str, status: str):
        if not variant:
            return
        index[variant] = status
        if variant not in names:
            names.append(variant)

    for k, v in cache.items():
        display_name = k
        slug = k
        m = re.match(r'\[([^\]]+)\]\(([^)]+)\)', k)
        if m:
            display_name = m.group(1)
            slug = m.group(2)

        norm_display = normalize_name(display_name)
        norm_slug = normalize_name(slug)
        compact_display = compact_name(display_name)
        compact_slug = compact_name(slug)

        for variant in [
            norm_display,
            norm_slug,
            compact_display,
            compact_slug,
            slug.lower().replace('-', ' '),
            slug.lower().replace('-', ''),
            display_name.lower(),
        ]:
            add_variant(variant, v)
    return index, names


def lookup_compat(cache: dict, game_name: str) -> str:
    index, index_names = build_compat_index(cache)
    gn_norm = normalize_name(game_name)
    gn_compact = compact_name(game_name)
    gn_words = set(gn_norm.split())

    STOPWORDS = {'the', 'a', 'an', 'of', 'edition', 'ultimate', 'remastered', 'complete', 'definitive', 'pro', 'goty'}

    if gn_norm in index:
        return index[gn_norm]
    if gn_compact in index:
        return index[gn_compact]

    for idx_name, val in index.items():
        if gn_norm in idx_name or idx_name in gn_norm or gn_compact == idx_name.replace(' ', ''):
            return val

    for idx_name, val in index.items():
        idx_words = set(idx_name.split())
        overlap = gn_words & idx_words - STOPWORDS
        if len(overlap) >= 2 and overlap == gn_words - STOPWORDS:
            return val

    best_ratio = 0.0
    best_status = "unknown"
    for idx_name in index_names:
        ratio = SequenceMatcher(None, gn_norm, idx_name).ratio()
        if ratio > best_ratio:
            best_ratio = ratio
            best_status = index.get(idx_name, "unknown")

    if best_ratio >= 0.82:
        return best_status

    return "unknown"


def download_release(version: str) -> Optional[Path]:
    release_dir = RELEASES_DIR / f"v{version}"
    if release_dir.exists():
        return release_dir

    print(f"Downloading OptiScaler v{version}...")
    try:
        import urllib.request
        api_url = f"https://api.github.com/repos/optiscaler/OptiScaler/releases/tags/v{version.split('-')[0] if '-' in version else version}"
        req = urllib.request.Request(api_url, headers={"User-Agent": "Python/3"})
        with urllib.request.urlopen(req, timeout=10) as response:
            release_data = json.loads(response.read().decode())

        download_url = None
        for asset in release_data.get("assets", []):
            if asset["name"].endswith(".7z"):
                download_url = asset["browser_download_url"]
                break

        if not download_url:
            print("Could not find .7z asset in release")
            return None

        temp_dir = tempfile.mkdtemp()
        temp_file = Path(temp_dir) / "optiscaler.7z"

        req = urllib.request.Request(download_url, headers={"User-Agent": "Python/3"})
        with urllib.request.urlopen(req, timeout=120) as response:
            with open(temp_file, 'wb') as f:
                shutil.copyfileobj(response, f)

        print("Downloaded!")
        extract_dir = RELEASES_DIR / f"v{version}"
        extract_dir.mkdir(parents=True, exist_ok=True)

        result = subprocess.run(['7z', 'x', '-y', f'-o{extract_dir}', str(temp_file)], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Extraction failed: {result.stderr}")
            shutil.rmtree(temp_dir)
            return None

        shutil.rmtree(temp_dir)
        print(f"Extracted to {extract_dir}")
        return extract_dir

    except Exception as e:
        print(f"Error downloading release: {e}")
        return None


def backup_game(game: dict, version: str):
    backup_dir = RELEASES_DIR / f"v{version}" / "backup" / game["name"]
    backup_dir.mkdir(parents=True, exist_ok=True)
    game_path = Path(game["path"])
    dll_name = game.get("dll_name", "dxgi.dll")

    for ext in ["dll", "ini", "log"]:
        for f in game_path.glob(f"*.{ext}"):
            if "OptiScaler" in f.name or f.name == dll_name or "fakenvapi" in f.name:
                shutil.copy2(f, backup_dir / f.name)

    for dir_name in ["D3D12_Optiscaler", "Licenses"]:
        dir_path = game_path / dir_name
        if dir_path.exists():
            shutil.copytree(dir_path, backup_dir / dir_name, dirs_exist_ok=True)

    return backup_dir


def restore_backup(game: dict, backup_dir: Path):
    game_path = Path(game["path"])
    for f in backup_dir.glob("*"):
        if f.is_file():
            shutil.copy2(f, game_path / f.name)
        elif f.is_dir():
            target = game_path / f.name
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(f, target)


def update_game(game: dict, version: str, verbose=True) -> bool:
    game_path = Path(game["path"])
    release_dir = RELEASES_DIR / f"v{version}"

    if not release_dir.exists():
        print(f"Release v{version} not found. Downloading...")
        release_dir = download_release(version)
        if not release_dir:
            return False

    if verbose:
        print(f"Updating {game['name']} to v{version}...")

    try:
        backup_game(game, version)

        dll_name = game.get("dll_name", "dxgi.dll")
        old_files = [
            game_path / dll_name, game_path / "OptiScaler.dll", game_path / "OptiScaler.ini",
            game_path / "OptiScaler.log", game_path / "fakenvapi.dll", game_path / "fakenvapi.ini",
            game_path / "fakenvapi.log",
        ]
        for f in old_files:
            if f.exists():
                f.unlink()

        for dir_name in ["D3D12_Optiscaler", "Licenses", "DlssOverrides"]:
            d = game_path / dir_name
            if d.exists():
                shutil.rmtree(d)

        for f in release_dir.iterdir():
            if f.is_file() and f.suffix in ['.dll', '.ini', '.log']:
                if "setup" not in f.name.lower():
                    shutil.copy2(f, game_path / f.name)
            elif f.is_dir() and f.name not in ["setup_linux.sh", "setup_windows.bat", "__MACOSX"]:
                target_dir = game_path / f.name
                if target_dir.exists():
                    shutil.rmtree(target_dir)
                shutil.copytree(f, target_dir)

        opti_in_game = game_path / "OptiScaler.dll"
        if opti_in_game.exists():
            target_dll = game_path / dll_name
            if target_dll.exists():
                target_dll.unlink()
            opti_in_game.rename(target_dll)

        create_uninstaller(game_path, dll_name)

        games = load_games()
        for g in games:
            if g["path"] == game["path"]:
                g["installed_version"] = version
                break
        save_games(games)

        if verbose:
            print(f"  ✓ {game['name']} updated to v{version}")
        return True

    except Exception as e:
        print(f"  ✗ Error updating {game['name']}: {e}")
        backup_path = RELEASES_DIR / f"v{version}" / "backup" / game["name"]
        if backup_path.exists():
            restore_backup(game, backup_path)
        return False


def create_uninstaller(game_path: Path, dll_name: str):
    uninstaller_content = """#!/usr/bin/env bash
clear
echo "OptiScaler Uninstaller"
echo "======================"
remove_choice=""
for arg in "$@"; do
    case "$arg" in
        --remove=*) remove_choice="${arg#*=}" ;;
    esac
done
if [ -z "$remove_choice" ]; then
    read -p "Remove OptiScaler? [y/n]: " remove_choice
fi
if [ "$remove_choice" = "y" ] || [ "$remove_choice" = "Y" ]; then
    rm -f OptiScaler.log OptiScaler.ini %s fakenvapi.dll fakenvapi.ini fakenvapi.log
    rm -f dlssg_to_fsr3_amd_is_better.dll dlssg_to_fsr3.log
    rm -rf D3D12_Optiscaler DlssOverrides Licenses
    echo "OptiScaler removed!"
    rm -f "$0"
else
    echo "Cancelled."
fi
""" % dll_name

    uninstaller_path = game_path / "remove_optiscaler.sh"
    with open(uninstaller_path, 'w') as f:
        f.write(uninstaller_content)
    os.chmod(uninstaller_path, 0o755)


def cmd_list(args):
    """List all managed games with pretty table."""
    games = load_games()
    compat_cache = load_compat_cache()

    console.print("[bold cyan]OptiScaler Games[/bold cyan]")
    table = Table(box=None, show_header=True, header_style="dim")
    table.add_column("#", justify="right", width=3)
    table.add_column("Game", style="cyan")
    table.add_column("Platform", style="magenta")
    table.add_column("Version", style="white")
    table.add_column("DLSS", justify="center")
    table.add_column("Wiki", justify="center")
    table.add_column("OptiScaler", justify="center")

    sorted_games = sorted(games, key=lambda g: (
        g.get("installed_version") == "unknown",
        not g.get("installed_version"),
        g["name"].lower()
    ))

    for i, game in enumerate(sorted_games, 1):
        platform_icon = "🎮" if game["platform"] == "steam" else "🐔"
        ver = game.get("installed_version", "-")
        dlss_icon = "[green]✓[/green]" if game.get("using_dlss") else "[dim]✗[/dim]"

        compat_status = lookup_compat(compat_cache, game["name"])
        if compat_status == "yes":
            support_icon = "[green]✓[/green]"
        elif compat_status == "no":
            support_icon = "[red]✗[/red]"
        elif compat_status == "partial":
            support_icon = "[yellow]➖[/yellow]"
        else:
            support_icon = "[dim]—[/dim]"

        installed_icon = "[green]✓[/green]" if has_optiscaler_installed(game) else "[dim]✗[/dim]"

        table.add_row(
            str(i),
            game["name"],
            f"{platform_icon} {game['platform']}",
            ver,
            dlss_icon,
            support_icon,
            installed_icon,
        )

    console.print(table)
    console.print(f"[dim]{len(games)} game(s) tracked. DLSS=DLSS spoofing on. Wiki=OptiScaler wiki compat. OptiScaler=files present.[/dim]")
    return 0


def cmd_scan(args):
    """Scan for installed Steam/Heroic games (real games only)."""
    console.print("[cyan]Scanning for installed games...[/cyan]")
    found = scan_installed_games()
    if not found:
        console.print("[yellow]No games found.[/yellow]")
        return 0

    games = load_games()
    managed_names = {g["name"].lower(): g for g in games}
    compat_cache = load_compat_cache()

    console.print(f"[bold cyan]Installed Games ({len(found)})[/bold cyan]")
    table = Table(box=None, show_header=True, header_style="dim")
    table.add_column("#", justify="right", width=3)
    table.add_column("Game", style="cyan")
    table.add_column("Platform", style="magenta")
    table.add_column("Wiki", justify="center")
    table.add_column("Installed", justify="center")
    table.add_column("Tracked", justify="center")

    sorted_found = sorted(found, key=lambda g: (
        not g["optiscaler_installed"],
        g["name"].lower() not in managed_names,
        g["name"].lower()
    ))

    for i, game in enumerate(sorted_found, 1):
        platform_icon = "🎮" if game["platform"] == "steam" else "🐔"

        compat_key = game["name"].lower()
        compat_status = lookup_compat(compat_cache, game["name"])
        if compat_status == "yes":
            support_icon = "[green]✓[/green]"
        elif compat_status == "no":
            support_icon = "[red]✗[/red]"
        elif compat_status == "partial":
            support_icon = "[yellow]➖[/yellow]"
        else:
            support_icon = "[dim]—[/dim]"

        opti_icon = "[green]✓[/green]" if game.get("optiscaler_installed") else "[dim]✗[/dim]"
        managed_icon = "[yellow]★[/yellow]" if game["name"].lower() in managed_names else "[dim]-[/dim]"

        table.add_row(
            str(i),
            game["name"],
            f"{platform_icon} {game['platform']}",
            support_icon,
            opti_icon,
            managed_icon,
        )

    console.print(table)
    tracked = len([g for g in found if g["name"].lower() in managed_names])
    console.print(f"[dim]Scanned: {len(found)} | Wiki=compat list. Installed=OptiScaler files in folder. Tracked=managed by optiscaler.[/dim]")
    return 0

    games = load_games()
    managed_names = {g["name"].lower() for g in games}
    compat_cache = load_compat_cache()

    table = Table(title=f"[bold cyan]Installed Games ({len(found)})[/bold cyan]", box=None, padding=1)
    table.add_column("#", justify="right", style="dim", width=3)
    table.add_column("Game", style="cyan")
    table.add_column("Platform", style="magenta")
    table.add_column("Supports", justify="center")
    table.add_column("OptiScaler", justify="center")
    table.add_column("Managed", justify="center")

    sorted_found = sorted(found, key=lambda g: (g["optiscaler_installed"], not g["name"].lower() in managed_names, g["name"].lower()))

    for i, game in enumerate(sorted_found, 1):
        platform_icon = "🎮" if game["platform"] == "steam" else "🐔"

        compat_key = game["name"].lower()
        compat_status = lookup_compat(compat_cache, game["name"])
        if compat_status == "yes":
            support_icon = "[green]✓[/green]"
        elif compat_status == "no":
            support_icon = "[red]✗[/red]"
        else:
            support_icon = "[dim]?[/dim]"

        opti_icon = "[green]✓[/green]" if game.get("optiscaler_installed") else "[dim]✗[/dim]"
        managed_icon = "[yellow]★[/yellow]" if game["name"].lower() in managed_names else "[dim]-[/dim]"

        table.add_row(
            str(i),
            game["name"],
            f"{platform_icon} {game['platform']}",
            support_icon,
            opti_icon,
            managed_icon,
        )

    console.print(table)
    console.print(f"\n[dim]Scanned: {len(found)} game(s) | Managed: {len([g for g in found if g['name'].lower() in managed_names])}[/dim]")
    return 0


def cmd_compat_update(args):
    """Fetch and cache compatibility list from GitHub wiki."""
    console.print("[cyan]Fetching compatibility list...[/cyan]")
    cache = fetch_compatibility_list()
    if cache:
        console.print(f"[green]Cached {len(cache)} compatibility entries.[/green]")
    return 0


def cmd_status(args):
    """Check status of all managed games."""
    games = load_games()
    config = load_config()
    latest_ver = config.get("latest_version")

    if latest_ver:
        latest_ver = f"v{latest_ver}"
    else:
        latest_ver = "unknown"

    print(f"\n{'='*60}")
    print(f"OptiScaler Status")
    print(f"{'='*60}")
    print(f"Latest available: {latest_ver}")
    print()

    if not games:
        print("No games managed.")
        return 0

    for game in games:
        inst_ver = game.get("installed_version", "unknown")
        if inst_ver == latest_ver.lstrip('v'):
            status = "✓ up to date"
        elif inst_ver == "unknown":
            status = "? unknown"
        else:
            status = f"⬆ needs update"

        platform = "steam" if game["platform"] == "steam" else "gog"
        print(f"  [{status}] {game['name']} ({platform}) - v{inst_ver}")

    print()
    return 0


def cmd_update(args):
    """Update game(s) to latest version."""
    games = load_games()
    config = load_config()

    if not games:
        print("No games managed. Add games first.")
        return 1

    games = refresh_managed_paths(games)
    latest_ver = config.get("latest_version") or config.get("current_version")

    if not latest_ver:
        print("Checking for latest version...")
        latest_ver, _ = check_github_version()
        if latest_ver:
            config["latest_version"] = latest_ver
            save_config(config)
            print(f"Latest version: v{latest_ver}")
        else:
            print("Could not determine latest version.")
            return 1

    # Check if we have the release downloaded
    release_dir = RELEASES_DIR / f"v{latest_ver}"
    if not release_dir.exists():
        print(f"Downloading v{latest_ver}...")
        release_dir = download_release(latest_ver)
        if not release_dir:
            print("Failed to download release.")
            return 1

    # Determine which games to update
    if args.name:
        target_games = find_managed_games(games, args.name)
        if not target_games:
            print(f"Game '{args.name}' not found in managed games.")
            print("Run 'optiscaler list' to see tracked game names.")
            return 1
    else:
        # Update all
        target_games = games

    print(f"\nUpdating {len(target_games)} game(s) to v{latest_ver}...\n")

    success = 0
    failed = 0
    for game in target_games:
        if update_game(game, latest_ver, verbose=True):
            success += 1
        else:
            failed += 1

    print(f"\n{success} updated, {failed} failed.")
    return 0 if failed == 0 else 1


def cmd_add(args):
    """Add a new game to management."""
    if not args.name:
        print("Error: Game name required.")
        print("Usage: optiscaler add <game_name>")
        return 1

    config = load_config()
    print(f"\nSearching for '{args.name}'...")

    results = search_games_by_name(args.name)
    if not results:
        print("No games found matching that name.")
        return 1

    if len(results) == 1:
        selected = results[0]
    else:
        top_score = SequenceMatcher(
            None,
            normalize_name(args.name).replace(" ", ""),
            normalize_name(results[0]["name"]).replace(" ", ""),
        ).ratio()
        second_score = SequenceMatcher(
            None,
            normalize_name(args.name).replace(" ", ""),
            normalize_name(results[1]["name"]).replace(" ", ""),
        ).ratio()
        if top_score >= 0.90 and (top_score - second_score) >= 0.10:
            selected = results[0]
        else:
            print(f"\nFound {len(results)} games:")
            for i, r in enumerate(results[:10], 1):
                print(f"  {i}. {r['name']} ({r['platform']})")
            print("\nUse a more specific name or add path manually in games.json.")
            return 0

    # Find OptiScaler.ini
    game_path = Path(selected["path"])
    ini_path = None
    actual_path = detect_game_target_dir(game_path)

    for root, dirs, files in os.walk(game_path):
        if "OptiScaler.ini" in files:
            ini_path = Path(root) / "OptiScaler.ini"
            actual_path = Path(root)
            break

    games = load_games()
    for existing in games:
        if existing["name"].lower() == selected["name"].lower() and Path(existing["path"]) == actual_path:
            print(f"{selected['name']} is already tracked.")
            return 0

    # Get settings
    dll_name = args.dll or "dxgi.dll"
    using_dlss = args.dlss if args.dlss is not None else True

    installed_version = config.get("current_version") if ini_path else "unknown"

    new_game = {
        "name": selected["name"],
        "platform": selected["platform"],
        "path": str(actual_path),
        "dll_name": dll_name,
        "using_nvidia": detect_gpu_type() == "nvidia",
        "using_dlss": using_dlss,
        "installed_version": installed_version
    }

    games.append(new_game)
    save_games(games)

    print(f"\n✓ Added {new_game['name']} to management")
    print(f"  Path: {new_game['path']}")
    print(f"  DLL: {new_game['dll_name']}")
    print(f"  DLSS: {'enabled' if using_dlss else 'disabled'}")
    if not ini_path:
        print("  Note: OptiScaler files were not found yet (game added for first install).")
    return 0


def cmd_remove(args):
    """Remove a game from management."""
    games = load_games()

    if not args.name:
        print("Error: Game name required.")
        return 1

    # Find game
    idx = None
    for i, g in enumerate(games):
        if args.name.lower() in g["name"].lower():
            idx = i
            break

    if idx is None:
        print(f"Game '{args.name}' not found in managed games.")
        return 1

    removed = games.pop(idx)
    save_games(games)

    print(f"\n✓ Removed {removed['name']} from management")
    print("  (OptiScaler files in game folder were not removed)")
    return 0


def cmd_check(args):
    """Check GitHub for latest version."""
    print("Checking GitHub for latest version...")

    latest_ver, url = check_github_version()
    config = load_config()
    current_ver = config.get("current_version")

    if latest_ver:
        print(f"\nLatest version: v{latest_ver}")
        if url:
            print(f"URL: {url}")

        if current_ver and latest_ver != current_ver:
            print(f"\nUpdate available: v{current_ver} → v{latest_ver}")
            print("Run 'optiscaler update' to update all games.")
        elif current_ver == latest_ver:
            print("\nAll games are up to date.")
        else:
            print("\nNo current version tracked.")

        config["latest_version"] = latest_ver
        config["last_check"] = datetime.now().isoformat()
        save_config(config)
    else:
        print("Could not fetch latest version.")
        return 1

    return 0


def run_tui():
    """Launch interactive TUI mode."""
    display_header()

    config = load_config()
    games = load_games()

    console.print("[dim]Checking for updates...[/dim]")
    latest_version, _ = check_github_version()

    if latest_version:
        config["latest_version"] = latest_version
        config["last_check"] = datetime.now().isoformat()

        current_version = config.get("current_version")

        if latest_version != current_version and latest_version not in config.get("skipped_versions", []):
            console.print(f"\n[bold yellow]⚠ New version available![/bold yellow]")
            console.print(f"   Current: [cyan]{current_version or 'none'}[/cyan] → Latest: [green]{latest_version}[/green]")

            choice = Prompt.ask("\n[yellow]What would you like to do?[/yellow]", choices=["y", "l", "s"], default="l", show_choices=False)

            if choice.lower() == "y":
                release_dir = download_release(latest_version)
                if release_dir:
                    config["current_version"] = latest_version
                    save_config(config)
                    if games:
                        console.print("\n[bold cyan]Updating all games...[/bold cyan]")
                        with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"), BarColumn(), TaskProgressColumn(), console=console) as progress:
                            task = progress.add_task(f"[cyan]Updating...[/cyan]", total=len(games))
                            for game in games:
                                progress.update(task, description=f"[cyan]Updating {game['name']}...")
                                update_game(game, latest_version, verbose=False)
                                progress.advance(task)
                return

            elif choice.lower() == "s":
                skipped = config.get("skipped_versions", [])
                skipped.append(latest_version)
                config["skipped_versions"] = skipped
                save_config(config)
            else:
                pass

    save_config(config)

    while True:
        console.print("\n[bold cyan]Main Menu[/bold cyan]")
        console.print("─" * 40)
        console.print("[cyan]1.[/cyan] List installed games")
        console.print("[cyan]2.[/cyan] Add new game")
        console.print("[cyan]3.[/cyan] Remove game")
        console.print("[cyan]4.[/cyan] Update all games")
        console.print("[cyan]5.[/cyan] Update single game")
        console.print("[cyan]6.[/cyan] Check for updates")
        console.print("[cyan]7.[/cyan] Settings")
        console.print("[cyan]Q.[/cyan] Quit")

        choice = Prompt.ask("\n[yellow]Select option[/yellow]", default="1")

        if choice == "1":
            games = load_games()
            if not games:
                console.print("[yellow]No games installed yet.[/yellow]")
            else:
                table = Table(title="[bold]Installed Games[/bold]", box=None)
                table.add_column("Game", style="cyan")
                table.add_column("Platform", style="magenta")
                table.add_column("Version", style="cyan")
                table.add_column("DLSS", style="green")

                for game in games:
                    platform_emoji = "🎮" if game["platform"] == "steam" else "🐔"
                    inst_ver = game.get("installed_version", "unknown")
                    dlss = "[green]✓[/green]" if game.get("using_dlss") else "[dim]✗[/dim]"
                    table.add_row(game["name"], f"{platform_emoji} {game['platform']}", inst_ver, dlss)
                console.print(table)

        elif choice == "2":
            query = Prompt.ask("[yellow]Enter game name to search[/yellow]")
            results = search_games_by_name(query)
            if not results:
                console.print("[red]No games found.[/red]")
                continue

            if len(results) == 1:
                selected = results[0]
            else:
                console.print("\n[bold]Found games:[/bold]")
                for i, r in enumerate(results, 1):
                    console.print(f"  [cyan]{i}[/cyan]. {r['name']} ({r['platform']})")
                choice = Prompt.ask("\n[yellow]Select number[/yellow]", default="1")
                try:
                    selected = results[int(choice) - 1]
                except:
                    continue

            game_path = Path(selected["path"])
            ini_path = None
            actual_path = detect_game_target_dir(game_path)
            for root, dirs, files in os.walk(game_path):
                if "OptiScaler.ini" in files:
                    ini_path = Path(root) / "OptiScaler.ini"
                    actual_path = Path(root)
                    break

            dll_name = Prompt.ask("[yellow]DLL filename[/yellow]", default="dxgi.dll")
            using_dlss = Confirm.ask("Enable DLSS inputs/spoofing?", default=True)
            config = load_config()
            installed_version = config.get("current_version") if ini_path else "unknown"

            games = load_games()
            already_exists = any(
                g["name"].lower() == selected["name"].lower() and Path(g["path"]) == actual_path
                for g in games
            )
            if already_exists:
                console.print(f"[yellow]{selected['name']} is already tracked.[/yellow]")
                continue

            games.append({
                "name": selected["name"], "platform": selected["platform"], "path": str(actual_path),
                "dll_name": dll_name, "using_nvidia": detect_gpu_type() == "nvidia",
                "using_dlss": using_dlss, "installed_version": installed_version
            })
            save_games(games)
            if ini_path:
                console.print(f"[green]Added {selected['name']}![/green]")
            else:
                console.print(f"[green]Added {selected['name']} (OptiScaler not installed yet).[/green]")

        elif choice == "3":
            games = load_games()
            if not games:
                console.print("[yellow]No games to remove.[/yellow]")
                continue
            console.print("\n[bold]Select game to remove:[/bold]")
            for i, g in enumerate(games, 1):
                console.print(f"  [cyan]{i}[/cyan]. {g['name']}")
            choice = Prompt.ask("\n[yellow]Game number[/yellow]", default="")
            try:
                idx = int(choice) - 1
                removed = games.pop(idx)
                save_games(games)
                console.print(f"[green]Removed {removed['name']}[/green]")
            except:
                pass

        elif choice == "4":
            if not games:
                console.print("[yellow]No games installed.[/yellow]")
                continue
            version = config.get("current_version") or config.get("latest_version")
            if version:
                console.print(f"\n[cyan]Updating all games to v{version}...[/cyan]")
                for game in games:
                    update_game(game, version, verbose=False)
            else:
                console.print("[yellow]No version available.[/yellow]")

        elif choice == "5":
            games = load_games()
            if not games:
                console.print("[yellow]No games installed.[/yellow]")
                continue
            console.print("\n[bold]Select game:[/bold]")
            for i, g in enumerate(games, 1):
                console.print(f"  [cyan]{i}[/cyan]. {g['name']}")
            choice = Prompt.ask("\n[yellow]Game number[/yellow]", default="")
            try:
                idx = int(choice) - 1
                game = games[idx]
                version = config.get("current_version") or config.get("latest_version")
                if version:
                    update_game(game, version, verbose=False)
                else:
                    console.print("[yellow]No version available.[/yellow]")
            except:
                pass

        elif choice == "6":
            latest, url = check_github_version()
            if latest:
                console.print(f"[green]Latest version: v{latest}[/green]")
            else:
                console.print("[yellow]Could not fetch latest version.[/yellow]")

        elif choice == "7":
            console.print("\n[bold cyan]Settings[/bold cyan]")
            console.print("─" * 40)
            console.print(f"[yellow]GPU Type:[/yellow] {detect_gpu_type()}")
            console.print(f"[yellow]Current Version:[/yellow] {config.get('current_version', 'none')}")
            console.print(f"[yellow]Latest Version:[/yellow] {config.get('latest_version', 'none')}")
            console.print(f"[yellow]Last Check:[/yellow] {config.get('last_check', 'never')}")

            console.print("\n[bold cyan]Per-Game Versions:[/bold cyan]")
            games = load_games()
            for g in games:
                game_path = Path(g["path"])
                dll_name = g.get("dll_name", "dxgi.dll")
                dll_path = game_path / dll_name
                status = "[green]✓[/green]" if dll_path.exists() else "[red]✗ missing[/red]"
                console.print(f"  {g['name']}: v{g.get('installed_version', 'unknown')} {status}")

            if Confirm.ask("\n[yellow]Reset skipped versions?[/yellow]", default=False):
                config["skipped_versions"] = []
                save_config(config)

        elif choice.lower() == "q":
            console.print("\n[cyan]Goodbye![/cyan]")
            break


def display_header():
    header = """
[bold cyan]  ___________     ___________
[cyan] /___  /___  |   /___  /___  |
[cyan]    / /   / /|   |  / /   / /|
[cyan]   / /   / / |   | / /   / / |
[cyan]  / /___/ /  |   |/ /___/ /  |
[cyan] /_______/   |___/|_______/   |
[cyan]    OptiScaler Manager v0.1
[/bold cyan]
"""
    console.print(Align.center(header))


def main():
    parser = argparse.ArgumentParser(
        description="OptiScaler Manager - CLI tool to manage OptiScaler installations",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Commands:
  list              List all managed games (pretty table)
  status            Check version status of all games
  update [game]     Update game(s) to latest version (omit game name to update all)
  add <name>        Search and add a game to management
  remove <name>     Remove a game from management
  check             Check GitHub for latest version
  scan              Scan for all installed Steam/Heroic games
  compat-update     Fetch and cache compatibility list from GitHub wiki

Options:
  --tui             Launch interactive TUI mode
  --dlss            Enable DLSS inputs when adding game (default)
  --no-dlss         Disable DLSS inputs when adding game
  --dll <name>      Specify DLL name when adding game (default: dxgi.dll)

Examples:
  optiscaler list
  optiscaler status
  optiscaler update
  optiscaler update "Cyberpunk 2077"
  optiscaler add "Elden Ring"
  optiscaler --tui
"""
    )

    parser.add_argument("--tui", action="store_true", help="Launch interactive TUI mode")
    parser.add_argument("--dlss", dest="dlss", action="store_true", default=None, help="Enable DLSS inputs")
    parser.add_argument("--no-dlss", dest="dlss", action="store_false", help="Disable DLSS inputs")
    parser.add_argument("--dll", dest="dll", help="DLL filename for game")

    parser.add_argument("command", nargs="?", help="Command to run")
    parser.add_argument("name", nargs="?", help="Game name for add/remove commands")

    args = parser.parse_args()

    ensure_config_dirs()

    if args.tui:
        run_tui()
        return 0

    if args.command is None:
        parser.print_help()
        return 0

    if args.command == "list":
        return cmd_list(args)
    elif args.command == "status":
        return cmd_status(args)
    elif args.command == "update":
        return cmd_update(args)
    elif args.command == "add":
        return cmd_add(args)
    elif args.command == "remove":
        return cmd_remove(args)
    elif args.command == "check":
        return cmd_check(args)
    elif args.command == "scan":
        return cmd_scan(args)
    elif args.command == "compat-update":
        return cmd_compat_update(args)
    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(130)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
