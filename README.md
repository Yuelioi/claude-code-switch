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
ccs save <name>     Save the current account
ccs <name>          Switch to an account (auto-saves current)
ccs list            List all saved accounts
ccs status          Show the current account
ccs delete <name>   Delete a saved account
```

`clauded` is a shortcut for `claude --dangerously-skip-permissions`:

```
clauded [args]
```

---

## Example

```bash
ccs save work        # save current session as "work"
ccs save personal    # save current session as "personal"

ccs personal         # switch to personal (auto-saves work first)
ccs work             # switch back to work

ccs list             # list all accounts
ccs status           # show current account
ccs delete personal  # delete personal
```

---

## How It Works

Account data is stored in `~/.claude-accounts/` (Windows: `%USERPROFILE%\.claude-accounts\`):

| File | Description |
|------|-------------|
| `<name>.json` | Copy of `~/.claude.json` (login token) |
| `<name>-dir/` | Copy of `~/.claude/` directory (config & project data) |

On switch, the current account is synced to its backup before the target is restored.

---

## Uninstall

**Windows:**

```powershell
Remove-Item "$env:USERPROFILE\.claude-switch" -Recurse -Force
# Then remove these two lines from your PowerShell profile:
#   # Claude Code Switch
#   . "C:\Users\<you>\.claude-switch\ccs.ps1"
# CMD users: also remove .claude-switch from the user PATH environment variable
```

**macOS / Linux / WSL / Git Bash:**

```bash
rm -rf ~/.claude-switch
# Then remove these two lines from ~/.bashrc or ~/.zshrc:
#   # Claude Code Switch
#   . "/home/<you>/.claude-switch/ccs.sh"
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
