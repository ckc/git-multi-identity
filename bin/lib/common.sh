#!/usr/bin/env bash
# Shared helpers for git-multi-identity scripts.
# Compatible with bash 3.2 (macOS system bash) — no associative arrays, no `declare -g`.

SSH_DIR="$HOME/.ssh"
GITCONFIG_MAIN="$HOME/.gitconfig"

detect_os() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo "macos" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then echo "wsl"; else echo "linux"; fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# install_pkg <command-to-check> <mac-pkg> <apt-pkg> <choco-pkg> <winget-id>
# Silently does nothing if the command already exists. Returns non-zero (but
# does not abort) if no known package manager can install it.
install_pkg() {
  local cmd="$1" mac_pkg="${2:-$1}" apt_pkg="${3:-$1}" choco_pkg="${4:-$1}" winget_id="${5:-}"
  local os
  os="$(detect_os)"

  if have "$cmd"; then
    return 0
  fi

  echo "==> $cmd not found, attempting to install..."
  case "$os" in
    macos)
      if have brew; then
        brew install "$mac_pkg"
      else
        echo "    Homebrew not found. Install it from https://brew.sh, then re-run." >&2
        return 1
      fi
      ;;
    linux|wsl)
      if have apt-get; then
        sudo apt-get update -y && sudo apt-get install -y "$apt_pkg"
      elif have dnf; then
        sudo dnf install -y "$apt_pkg"
      elif have pacman; then
        sudo pacman -Sy --noconfirm "$apt_pkg"
      else
        echo "    No supported package manager found (apt/dnf/pacman). Install $cmd manually." >&2
        return 1
      fi
      ;;
    windows)
      if have choco; then
        choco install -y "$choco_pkg"
      elif have winget; then
        winget install -e --id "${winget_id:-$choco_pkg}"
      else
        echo "    Install Chocolatey (https://chocolatey.org/install) or use winget, then re-run." >&2
        echo "    Alternatively, run this toolkit inside WSL for a smoother experience." >&2
        return 1
      fi
      ;;
    *)
      echo "    Unrecognized OS ($os). Install $cmd manually." >&2
      return 1
      ;;
  esac
}

# backup_file <path> — copies an existing file to <path>.bak.<timestamp> before it's overwritten.
backup_file() {
  local f="$1"
  [ -e "$f" ] || return 0
  cp -p "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
}

# strip_managed_block <file> <start-marker> <end-marker>
# Removes a previously-inserted managed block so setup.sh can be re-run safely (idempotent).
strip_managed_block() {
  local file="$1" start="$2" end="$3"
  [ -f "$file" ] || return 0
  awk -v s="$start" -v e="$end" '
    $0==s {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$file" > "$file.tmp.$$"
  mv "$file.tmp.$$" "$file"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}
