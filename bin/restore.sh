#!/usr/bin/env bash
# git-multi-identity: restore.sh
#
# Decrypts a backup produced by backup.sh and lays the files back down on a
# fresh machine: ~/.ssh/{config,id_ed25519*}, ~/.gitconfig*, identities.conf.
# Fixes permissions and loads keys into ssh-agent.
#
# Usage: restore.sh <path-to-backup.tar.age>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

install_pkg age age age age FiloSottile.age

BUNDLE="${1:?Usage: restore.sh <path-to-backup.tar.age>}"
[ -f "$BUNDLE" ] || { echo "File not found: $BUNDLE" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "Decrypting (enter the passphrase you set during backup)..."
age -d -o "$STAGE/backup.tar" "$BUNDLE"
tar -C "$STAGE" -xf "$STAGE/backup.tar"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR" 2>/dev/null || true

if [ -d "$STAGE/ssh" ]; then
  for f in "$STAGE"/ssh/*; do
    [ -e "$f" ] && cp -p "$f" "$SSH_DIR/"
  done
fi

if [ -d "$STAGE/home" ]; then
  for f in "$STAGE"/home/.gitconfig*; do
    [ -e "$f" ] && cp -p "$f" "$HOME/"
  done
fi

if [ -f "$STAGE/identities.conf" ]; then
  cp -p "$STAGE/identities.conf" "$SCRIPT_DIR/../identities.conf"
fi

for f in "$SSH_DIR"/id_ed25519*; do
  case "$f" in
    *.pub) chmod 644 "$f" 2>/dev/null || true ;;
    *) [ -e "$f" ] && chmod 600 "$f" 2>/dev/null || true ;;
  esac
done
[ -f "$SSH_DIR/config" ] && chmod 600 "$SSH_DIR/config" 2>/dev/null || true

if have ssh-agent; then
  eval "$(ssh-agent -s)" >/dev/null
  for key in "$SSH_DIR"/id_ed25519_*; do
    case "$key" in *.pub) continue ;; esac
    [ -f "$key" ] && ssh-add "$key" 2>/dev/null || true
  done
fi

echo
echo "Restore complete."
echo "Test each identity with: ssh -T git@<host_alias>   (aliases are in ~/.ssh/config)"
echo "If this is a brand-new key (not the one already registered on the platform),"
echo "you'll need to add the matching .pub key on GitHub/GitLab before it will work."
