# Claude Code Switch (`ccs`)

快速切换 Claude Code 登录账号的命令行工具，支持 Windows（PowerShell、CMD）、macOS、Linux、WSL 和 Git Bash。

[English](./README.md)

---

## 安装

### Windows — PowerShell / CMD

```powershell
irm https://raw.githubusercontent.com/Yuelioi/claude-code-switch/main/install.ps1 | iex
```

安装后重载 PowerShell：

```powershell
. $PROFILE
```

CMD 用户重新打开一个新窗口即可直接使用 `ccs`。

### macOS / Linux / WSL / Git Bash

```bash
curl -fsSL https://raw.githubusercontent.com/Yuelioi/claude-code-switch/main/install.sh | bash
```

安装后重载 Shell：

```bash
source ~/.bashrc   # bash
source ~/.zshrc    # zsh（macOS 默认）
```

> 安装脚本会自动检测当前 Shell，并写入对应的 rc 文件。

---

## 手动安装

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
source ~/.bashrc  # 或 source ~/.zshrc
```

---

## 用法

```
ccs save <name>     保存当前登录的账号
ccs <name>          切换到指定账号（自动保存当前状态）
ccs list            列出所有已保存的账号
ccs status          查看当前使用的账号
ccs delete <name>   删除一个已保存的账号
```

另附 `clauded`，等同于 `claude --dangerously-skip-permissions`：

```
clauded [args]
```

---

## 示例

```bash
ccs save work        # 保存当前账号为 work
ccs save personal    # 保存当前账号为 personal

ccs personal         # 切换到 personal（自动保存 work 的状态）
ccs work             # 切换回 work

ccs list             # 列出所有账号
ccs status           # 查看当前账号
ccs delete personal  # 删除 personal
```

---

## 工作原理

账号数据保存在 `~/.claude-accounts/`（Windows：`%USERPROFILE%\.claude-accounts\`）：

| 文件 | 说明 |
|------|------|
| `<name>.json` | `~/.claude.json` 的副本（登录 token） |
| `<name>-dir/` | `~/.claude/` 目录的副本（配置、项目数据） |

切换账号时，先将当前账号状态同步到备份，再还原目标账号的文件。

---

## 卸载

**Windows：**

```powershell
Remove-Item "$env:USERPROFILE\.claude-switch" -Recurse -Force
# 再从 PowerShell Profile 中手动删除以下两行：
#   # Claude Code Switch
#   . "C:\Users\<you>\.claude-switch\ccs.ps1"
# CMD 用户还需在系统环境变量中移除 .claude-switch 路径
```

**macOS / Linux / WSL / Git Bash：**

```bash
rm -rf ~/.claude-switch
# 再从 ~/.bashrc 或 ~/.zshrc 中删除以下两行：
#   # Claude Code Switch
#   . "/home/<you>/.claude-switch/ccs.sh"
```

---

## 文件结构

```
claude-code-switch/
├── ccs.ps1        # PowerShell 核心（支持 dot-source 和直接执行）
├── ccs.bat        # CMD 包装器
├── ccs.sh         # Bash/Zsh 核心（macOS / Linux / WSL / Git Bash）
├── install.ps1    # Windows 安装脚本（支持本地和远程执行）
├── install.sh     # Unix 安装脚本（支持本地和远程执行）
└── README.md
```
