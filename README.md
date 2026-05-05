# Claude Code Switch (`ccs`)

A CLI tool for quickly switching between Claude Code accounts.
Supports Windows (PowerShell, CMD), macOS, Linux, WSL, and Git Bash.

[中文文档](./README.zh-CN.md)

---

## Install

### Windows — PowerShell / CMD

```powershell
irm https://raw.githubusercontent.com/Yuelioi/claude-code-switch/main/install.ps1 | iex
```

Reload PowerShell after install:

```powershell
. $PROFILE
```

CMD users just open a new terminal window — `ccs` will be available immediately.

### macOS / Linux / WSL / Git Bash

```bash
curl -fsSL https://raw.githubusercontent.com/Yuelioi/claude-code-switch/main/install.sh | bash
```

Reload your shell after install:

```bash
source ~/.bashrc   # bash
source ~/.zshrc    # zsh (macOS default)
```

> The installer auto-detects your current shell and writes to the correct rc file.

---

## Manual Install

```powershell
# Windows
git clone https://github.com/Yuelioi/claude-code-switch.git
cd claude-code-switch
.\install.ps1
. $PROFILE
```

```bash
# macOS / Linux / WSL / Git Bash
git clone https://github.com/Yuelioi/claude-code-switch.git
cd claude-code-switch
bash install.sh
source ~/.bashrc  # or: source ~/.zshrc
```

---

## Usage

```
ccs login <name>     Run `claude auth login` and save the new credentials as <name>
ccs save <name>      Save the current account
ccs switch <name>    Switch to an account (auto-saves current first)
ccs list             List all saved accounts
ccs status           Show the current account
ccs refresh          Refresh OAuth tokens for all saved accounts
ccs schedule         Register hourly auto-refresh (Windows Task Scheduler / cron)
ccs unschedule       Remove the auto-refresh schedule
ccs delete <name>    Delete a saved account
ccs uninstall        Uninstall ccs
```

`clauded` is a shortcut for `claude --dangerously-skip-permissions`:

```
clauded [args]
```

---

## Example

```bash
ccs login work       # run `claude auth login` and save the result as "work"
ccs login personal   # log in as another account and save as "personal"

ccs switch personal  # switch to personal (auto-saves work first)
ccs switch work      # switch back to work

ccs list             # list all accounts (* marks the current one)
ccs status           # show current account
ccs delete personal  # delete personal
```

`ccs save <name>` is also available if you've already logged in via `claude auth login` directly and want to capture the active session under a name.

---

## Token Auto-Refresh

Claude Code uses OAuth tokens that expire over time. If you switch back to an account you haven't used in a while, the stored token may be expired, causing a `401` authentication error.

### Manual refresh

```bash
ccs refresh
```

Calls `platform.claude.com/v1/oauth/token` directly with each account's refresh token — no account switching needed. Updates all backup credential files in place.

### Automatic refresh (recommended)

Register a background task that runs `ccs refresh` every hour:

```bash
ccs schedule
```

To stop it:

```bash
ccs unschedule
```

| Platform | Mechanism |
|----------|-----------|
| Windows  | Windows Task Scheduler (`ClaudeCodeTokenRefresh`) |
| macOS / Linux / WSL | cron (`0 * * * *`), log at `~/.claude-accounts/refresh.log` |

---

## How It Works

Account data is stored in `~/.claude-accounts/` (Windows: `%USERPROFILE%\.claude-accounts\`):

| File | Description |
|------|-------------|
| `<name>.creds.json` | OAuth credentials + identity fields (`oauthAccount`, `userID`) — about 1 KB per account |
| `.current` | Name of the currently active account |

`ccs` only persists what's needed to authenticate as a different account: the `.credentials.json` payload plus the two identity fields from `~/.claude.json`. Project data, conversation history, and other local state stay in `~/.claude/` and are shared across accounts. When switching, `ccs` writes the new credentials to `~/.claude/.credentials.json` and merges the identity fields into `~/.claude.json` — everything else is left untouched.

---

## Upgrading from an older version

The storage format changed in this release: only credentials are saved now (~1 KB per account), instead of the entire `~/.claude/` directory (~hundreds of MB). **The new version does not read the old format.** If you're upgrading from a version that used `<name>.json` + `<name>-dir/`:

```bash
rm -rf ~/.claude-accounts        # macOS / Linux / WSL / Git Bash
Remove-Item "$env:USERPROFILE\.claude-accounts" -Recurse -Force  # Windows
```

Then run `ccs save <name>` for each account you want to keep (you'll need to log in to each one in Claude Code first).

---

## Uninstall

```bash
ccs uninstall
```

This removes the scheduled task (if any), the install directory, and the shell profile entry automatically.

Account backups in `~/.claude-accounts/` are **not** removed — delete that directory manually if you no longer need the saved accounts.

```bash
rm -rf ~/.claude-accounts        # macOS / Linux / WSL
Remove-Item "$env:USERPROFILE\.claude-accounts" -Recurse -Force  # Windows
```

---

## File Structure

```
claude-code-switch/
├── ccs.ps1        # PowerShell core (dot-source or direct execution)
├── ccs.bat        # CMD wrapper
├── ccs.sh         # Bash/Zsh core (macOS / Linux / WSL / Git Bash)
├── install.ps1    # Windows installer (local and remote)
├── install.sh     # Unix installer (local and remote)
└── README.md
```
