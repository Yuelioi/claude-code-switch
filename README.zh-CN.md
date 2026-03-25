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
ccs save <name>      保存当前登录的账号
ccs <name>           切换到指定账号（自动保存当前状态）
ccs list             列出所有已保存的账号
ccs status           查看当前使用的账号
ccs refresh          刷新所有已保存账号的 OAuth token
ccs schedule         注册每小时自动刷新任务（Windows 任务计划 / cron）
ccs unschedule       取消自动刷新任务
ccs delete <name>    删除一个已保存的账号
ccs uninstall        卸载 ccs
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

ccs list             # 列出所有账号（* 标记当前账号）
ccs status           # 查看当前账号
ccs delete personal  # 删除 personal
```

---

## Token 自动刷新

Claude Code 的 OAuth token 会随时间过期。如果切换回长时间未使用的账号，备份里的 token 可能已失效，导致 `401` 认证错误。

### 手动刷新

```bash
ccs refresh
```

直接向 `platform.claude.com/v1/oauth/token` 发起请求，用各账号的 refresh token 换取新 token，无需切换账号，就地更新所有备份中的凭据文件。

### 自动刷新（推荐）

注册后台定时任务，每小时自动执行一次 `ccs refresh`：

```bash
ccs schedule
```

取消定时任务：

```bash
ccs unschedule
```

| 平台                | 机制                                                               |
| ------------------- | ------------------------------------------------------------------ |
| Windows             | Windows 任务计划程序（任务名：`ClaudeCodeTokenRefresh`）         |
| macOS / Linux / WSL | cron（`0 * * * *`），日志位于 `~/.claude-accounts/refresh.log` |

---

## 工作原理

账号数据保存在 `~/.claude-accounts/`（Windows：`%USERPROFILE%\.claude-accounts\`）：

| 文件 / 目录     | 说明                                              |
| --------------- | ------------------------------------------------- |
| `<name>.json` | `~/.claude.json` 的副本（账号元数据）           |
| `<name>-dir/` | `~/.claude/` 目录的副本（配置、项目数据、凭据） |
| `.current`    | 当前活跃账号的名称                                |

切换账号时，`ccs` 先读取 `.current` 确定要更新哪个备份，再恢复目标账号的文件。`~/.claude-accounts/<name>-dir/.credentials.json` 存储各账号的 OAuth token。

---

## 从旧版本升级

如果你使用的是旧版本（通过文件哈希匹配来识别当前账号），升级后需要执行一次重新保存：

```bash
ccs save <你的账号名>
```

---

## 卸载

```bash
ccs uninstall
```

自动完成以下操作：取消定时任务（如已注册）、删除安装目录、从 Shell 配置文件中移除加载行。

`~/.claude-accounts/` 中的账号备份**不会**被自动删除，如不再需要可手动删除(防止误操作)：

```bash
rm -rf ~/.claude-accounts        # macOS / Linux / WSL
Remove-Item "$env:USERPROFILE\.claude-accounts" -Recurse -Force  # Windows
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
