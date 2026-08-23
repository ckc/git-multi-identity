#!/usr/bin/env bash
# git-multi-identity: setup.sh
#
# Reads identities.conf and, for each identity:
#   - generates an ed25519 SSH key (if missing)
#   - adds a Host block to ~/.ssh/config
#   - writes ~/.gitconfig-<name> with the right user.name/user.email
#   - wires it into ~/.gitconfig via includeIf (by directory) + insteadOf (by host)
#
# Safe to re-run: it removes its own previous managed blocks before rewriting them,
# and backs up ~/.ssh/config and ~/.gitconfig before first touching them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

IDENTITIES_FILE="${1:-$SCRIPT_DIR/../identities.conf}"

if [ ! -f "$IDENTITIES_FILE" ]; then
  echo "identities.conf not found at: $IDENTITIES_FILE" >&2
  echo "Copy identities.conf.example to identities.conf next to it and edit the emails first." >&2
  exit 1
fi

MARK_START="# >>> git-multi-identity managed block >>>"
MARK_END="# <<< git-multi-identity managed block <<<"

echo "== git-multi-identity setup =="
echo "OS detected: $(detect_os)"
echo "Identities file: $IDENTITIES_FILE"
echo

install_pkg git git git git Git.Git || true
install_pkg ssh-keygen openssh openssh-client openssh Microsoft.OpenSSH.Beta || true
install_pkg age age age age FiloSottile.age || true
echo

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR" 2>/dev/null || true

# Back up existing files the *first* time only (won't clobber a prior backup).
if [ -f "$SSH_DIR/config" ] && ! grep -q "$MARK_START" "$SSH_DIR/config" 2>/dev/null; then
  backup_file "$SSH_DIR/config"
fi
if [ -f "$GITCONFIG_MAIN" ] && ! grep -q "$MARK_START" "$GITCONFIG_MAIN" 2>/dev/null; then
  backup_file "$GITCONFIG_MAIN"
fi

touch "$SSH_DIR/config" "$GITCONFIG_MAIN"
strip_managed_block "$SSH_DIR/config" "$MARK_START" "$MARK_END"
strip_managed_block "$GITCONFIG_MAIN" "$MARK_START" "$MARK_END"

{
  echo ""
  echo "$MARK_START"
} >> "$SSH_DIR/config"

{
  echo ""
  echo "$MARK_START"
} >> "$GITCONFIG_MAIN"

while IFS='|' read -r name host_alias real_host key_file git_name git_email path_glob; do
  case "$name" in \#*|'') continue ;; esac
  name="$(trim "$name")"; host_alias="$(trim "$host_alias")"
  real_host="$(trim "$real_host")"; key_file="$(trim "$key_file")"
  git_name="$(trim "$git_name")"; git_email="$(trim "$git_email")"
  path_glob="$(trim "$path_glob")"

  key_path="$SSH_DIR/$key_file"

  echo "-- Identity: $name  ($git_email @ $real_host)"

  if [ ! -f "$key_path" ]; then
    echo "   Generating ed25519 key: $key_path"
    ssh-keygen -t ed25519 -C "$git_email" -f "$key_path" -N ""
  else
    echo "   Key already exists at $key_path — leaving it as-is."
  fi
  chmod 600 "$key_path" 2>/dev/null || true
  chmod 644 "$key_path.pub" 2>/dev/null || true

  {
    echo ""
    echo "Host $host_alias"
    echo "    HostName $real_host"
    echo "    User git"
    echo "    IdentityFile $key_path"
    echo "    IdentitiesOnly yes"
  } >> "$SSH_DIR/config"

  gitconfig_id_file="$HOME/.gitconfig-$name"
  cat > "$gitconfig_id_file" <<EOF
[user]
	name = $git_name
	email = $git_email
EOF

  {
    echo ""
    echo "[includeIf \"gitdir:$path_glob\"]"
    echo "	path = $gitconfig_id_file"
    echo ""
    echo "[url \"git@$host_alias:\"]"
    echo "	insteadOf = git@$real_host:"
    echo "	insteadOf = https://$real_host/"
  } >> "$GITCONFIG_MAIN"

  echo "   Public key (add to $real_host):"
  echo "   ----------------------------------------"
  cat "$key_path.pub"
  echo "   ----------------------------------------"
  echo
done < "$IDENTITIES_FILE"

echo "$MARK_END" >> "$SSH_DIR/config"
echo "$MARK_END" >> "$GITCONFIG_MAIN"
chmod 600 "$SSH_DIR/config" 2>/dev/null || true

cat <<'EOF'
Setup complete.

Next steps:
  1. Add each public key printed above to its platform:
       GitHub Enterprise : https://github.internal.digitalocean.com/settings/keys
       GitHub.com        : https://github.com/settings/keys
       GitLab.com        : https://gitlab.com/-/profile/keys
  2. Create the folders your identities.conf path_globs point at, e.g.:
       mkdir -p ~/work ~/personal
     Clone repos into the matching folder so the right git name/email is picked
     automatically (check with: git config user.email, from inside the repo).
  3. Test each SSH connection:
       ssh -T git@<host_alias>          # e.g. ssh -T git@github-do
  4. Clone using the *real* hostname — git rewrites it to the right key for you:
       git clone git@github.internal.digitalocean.com:org/repo.git ~/work/repo
EOF
