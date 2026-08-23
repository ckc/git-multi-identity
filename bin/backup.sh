#!/usr/bin/env bash
# git-multi-identity: backup.sh
#
# Bundles ~/.ssh keys+config, ~/.gitconfig*, and identities.conf into a tar
# archive, then encrypts it with age (passphrase-based, scrypt). The output
# is a single .tar.age file safe to push to a private repo, cloud drive, or
# password manager — it is useless without the passphrase.
#
# Usage: backup.sh [output-dir]   (default: ~/git-identity-backups)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

install_pkg age age age age FiloSottile.age

OUT_DIR="${1:-$HOME/git-identity-backups}"
mkdir -p "$OUT_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/ssh" "$STAGE/home"

if [ -d "$SSH_DIR" ]; then
  [ -f "$SSH_DIR/config" ] && cp -p "$SSH_DIR/config" "$STAGE/ssh/"
  # shellcheck disable=SC2231
  for f in "$SSH_DIR"/id_ed25519*; do
    [ -e "$f" ] && cp -p "$f" "$STAGE/ssh/"
  done
fi

[ -f "$GITCONFIG_MAIN" ] && cp -p "$GITCONFIG_MAIN" "$STAGE/home/"
for f in "$HOME"/.gitconfig-*; do
  [ -e "$f" ] && cp -p "$f" "$STAGE/home/"
done

[ -f "$SCRIPT_DIR/../identities.conf" ] && cp -p "$SCRIPT_DIR/../identities.conf" "$STAGE/"

ARCHIVE="$STAGE.tar"
tar -C "$STAGE" -cf "$ARCHIVE" .

OUT_FILE="$OUT_DIR/git-identity-backup-$TS.tar.age"
echo "Encrypting with a passphrase — you will be prompted twice (enter, then confirm)."
echo "Remember this passphrase; it is the ONLY way to restore this backup."
age -p -o "$OUT_FILE" "$ARCHIVE"
rm -f "$ARCHIVE"

chmod 600 "$OUT_FILE"

echo
echo "Backup written to: $OUT_FILE"
echo "Store it somewhere durable — a private git repo, cloud drive, or password manager attachment."
echo "The file is encrypted at rest, but treat the passphrase itself like a master password."
