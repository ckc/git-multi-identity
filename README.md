# git-multi-identity

Separate SSH keys + git author identity for multiple git hosts (e.g. company
GitHub Enterprise vs. personal GitHub/GitLab), driven by one config file.
Portable across macOS, Linux, and Windows (Git Bash or WSL). Built on
standard, open-source tools only: `git`, `ssh-keygen`, `age`. No proprietary
agent required.

## How it works

- **One SSH key per identity**, referenced through a `Host` alias in
  `~/.ssh/config` (`IdentityFile` + `IdentitiesOnly yes`), so the right key is
  always used for the right host.
- **One git identity (name/email) per directory tree**, via git's
  `includeIf "gitdir:..."`. Put work repos under `~/work/**` and personal
  repos under `~/personal/**` (or whatever globs you choose) and the correct
  `user.name`/`user.email` is applied automatically — no more accidentally
  committing with the wrong email.
- **`insteadOf` URL rewriting** so you can `git clone` using the real
  hostname (`git@github.internal.dev:...`) and git transparently
  rewrites it to the aliased host that carries the right key. You don't have
  to remember alias names when cloning.
- **Encrypted backup/restore** with [age](https://github.com/FiloSottile/age)
  (passphrase-based) so you can move your keys to a new machine without ever
  committing a private key in plaintext.

All of this is config-driven from a single file: `identities.conf`.

## Layout

```
git-multi-identity/
├── identities.conf.example   # template — copy to identities.conf and edit
├── bin/
│   ├── setup.sh               # generates keys, writes ssh config + gitconfig
│   ├── backup.sh               # encrypts ~/.ssh + ~/.gitconfig* to a .tar.age file
│   ├── restore.sh              # decrypts and restores on a new machine
│   └── lib/common.sh           # shared helpers (OS detection, package install)
└── .gitignore                 # keeps real keys/identities.conf out of git
```

## Quick start — new machine

Requires Git Bash (comes with [Git for Windows](https://git-scm.com/download/win))
or WSL on Windows; a normal terminal on macOS/Linux.

```bash
# 1. Put this folder somewhere permanent, e.g. push it to your own private repo
#    (only the scripts + .example file — identities.conf and keys are gitignored)
cd git-multi-identity

# 2. Create your real config
cp identities.conf.example identities.conf
$EDITOR identities.conf     # fill in your personal emails

# 3. Run setup — installs git/ssh/age if missing, generates keys, wires config
./bin/setup.sh
```

The script prints each public key it generates. Add each one to the matching
platform:

- GitHub Enterprise: `https://github.internal.dev/settings/keys`
- GitHub.com: `https://github.com/settings/keys`
- GitLab.com: `https://gitlab.com/-/profile/keys`

Then:

```bash
mkdir -p ~/work ~/personal
ssh -T git@github-wk            # verify each host alias works
git clone git@github.internal.dev:org/repo.git ~/work/repo
```

`setup.sh` is idempotent — re-run it any time after editing `identities.conf`
(e.g. to add a new identity); it won't duplicate config blocks or overwrite
existing keys.

## Backing up

```bash
./bin/backup.sh                       # -> ~/git-identity-backups/git-identity-backup-<ts>.tar.age
```

You'll be prompted for a passphrase (twice). The output file is a single
encrypted archive containing your SSH keys, `~/.ssh/config`, all
`~/.gitconfig*` files, and `identities.conf`. It's safe to:

- push to a **private** git repo,
- store in a password manager as an attachment,
- copy to a cloud drive.

It is **not** safe to make public — treat it like a password vault, and pick
a strong, memorable passphrase (this is the only recovery mechanism).

## Restoring on a new machine

```bash
git clone <your-private-repo-with-this-toolkit> ~/git-multi-identity
cd ~/git-multi-identity
./bin/restore.sh /path/to/git-identity-backup-<ts>.tar.age
```

This decrypts the bundle, restores everything to `~/.ssh` and `$HOME`, fixes
file permissions, and loads keys into `ssh-agent`. Verify with
`ssh -T git@<host_alias>` for each identity.

## Adding another identity later

Add a line to `identities.conf`, then re-run `./bin/setup.sh`. Nothing else
changes.

**Note on shared `path_glob` values:** `path_glob` controls `user.name`/
`user.email` only (via `includeIf`), separately from the SSH key (which is
selected by hostname). If two identities share the same `path_glob` — e.g.
`personal-github` and `personal-gitlab` both under `~/personal/**` in the
example — whichever one's block appears later in `~/.gitconfig` wins for
that field when both would apply to the same repo. That's harmless as long
as they share the same name/email (the common case), but if you want a
different author identity per host, use distinct subfolders instead, e.g.
`~/personal/github/**` and `~/personal/gitlab/**`.

## Design notes / alternatives considered

- **Why not one key for everything?** GitHub/GitLab best practice is a
  distinct key per device *and* per trust boundary — a compromised personal
  laptop shouldn't be able to touch company repos, and vice versa. Per-host
  `IdentitiesOnly yes` also stops SSH from offering the wrong key and getting
  rate-limited or logged against the wrong account.
- **Why `age` instead of GPG?** Same job, far simpler CLI and file format,
  actively maintained, no keyring/agent setup needed for passphrase mode.
  GPG works too if you already have it — swap `age -p` for
  `gpg --symmetric` in `backup.sh`/`restore.sh` if you prefer.
- **1Password / Bitwarden SSH agent**: if you already pay for a password
  manager with an SSH agent (1Password, Bitwarden), that's a strong
  alternative to this backup/restore flow — keys never touch disk at all.
  This toolkit assumes you don't want that dependency; swapping to it later
  just means pointing `IdentityAgent` in `~/.ssh/config` at their agent
  instead of using `IdentityFile`.
- **Chezmoi / yadm**: if you want to manage *all* your dotfiles (not just
  git/ssh), look at [chezmoi](https://www.chezmoi.io/) or
  [yadm](https://yadm.io/) — both are open-source, cross-platform dotfile
  managers with built-in encryption support and could absorb this toolkit's
  job as one part of a bigger setup.

## Windows caveats

- Run these scripts from **Git Bash** or **WSL** — they're bash, not
  PowerShell.
- NTFS doesn't enforce POSIX file permissions the way `chmod` implies; OpenSSH
  on native Windows can be picky about private key file ACLs. If `ssh` warns
  about permissions, either run everything inside WSL2 (recommended, full
  POSIX semantics) or use `icacls` to restrict the key file to your user.
