# ── Claude Code Account Switcher ──────────────────────────────
# Works both as a dot-sourced function and as a direct script.

function ccs {
    param([string]$Command = "", [string]$Name = "")

    $ClaudeConfig = "$env:USERPROFILE\.claude.json"
    $ClaudeDir    = "$env:USERPROFILE\.claude"
    $BackupDir    = "$env:USERPROFILE\.claude-accounts"

    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

    function _Hash($p) { if (Test-Path $p) { (Get-FileHash $p -Algorithm MD5).Hash } }
    function _Eq($a,$b) { (_Hash $a) -and (_Hash $a) -eq (_Hash $b) }

    function _AutoSave {
        if (-not (Test-Path $ClaudeConfig)) { return }
        foreach ($f in (Get-ChildItem "$BackupDir\*.json" -EA SilentlyContinue)) {
            $n = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (_Eq $ClaudeConfig $f.FullName) {
                Copy-Item $ClaudeConfig $f.FullName -Force
                $d = "$BackupDir\$n-dir"
                if (Test-Path $ClaudeDir) {
                    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
                    Copy-Item $ClaudeDir $d -Recurse -Force
                }
                break
            }
        }
    }

    switch ($Command) {
        "save" {
            if (!$Name) { Write-Host "Usage: ccs save <name>" -f Red; return }
            if (!(Test-Path $ClaudeConfig)) { Write-Host "No Claude config found." -f Red; return }
            Copy-Item $ClaudeConfig "$BackupDir\$Name.json" -Force
            if (Test-Path $ClaudeDir) {
                $d = "$BackupDir\$Name-dir"
                if (Test-Path $d) { Remove-Item $d -Recurse -Force }
                Copy-Item $ClaudeDir $d -Recurse -Force
            }
            Write-Host "Saved as '$Name'" -f Green
        }
        "list" {
            Write-Host "Saved accounts:" -f Cyan
            $files = Get-ChildItem "$BackupDir\*.json" -EA SilentlyContinue
            if (!$files) { Write-Host "  (none)" -f DarkGray; return }
            foreach ($f in $files) { Write-Host "  - $([IO.Path]::GetFileNameWithoutExtension($f.Name))" }
        }
        "status" {
            $cur = "unknown"
            foreach ($f in (Get-ChildItem "$BackupDir\*.json" -EA SilentlyContinue)) {
                if (_Eq $ClaudeConfig $f.FullName) { $cur = [IO.Path]::GetFileNameWithoutExtension($f.Name); break }
            }
            if ($cur -ne "unknown") { Write-Host "Current: $cur" -f Green }
            else { Write-Host "Current: unknown (not saved yet)" -f Yellow }
        }
        "delete" {
            if (!$Name) { Write-Host "Usage: ccs delete <name>" -f Red; return }
            $tj = "$BackupDir\$Name.json"
            if (!(Test-Path $tj)) { Write-Host "Account '$Name' not found." -f Red; return }
            Remove-Item $tj -Force
            $td = "$BackupDir\$Name-dir"
            if (Test-Path $td) { Remove-Item $td -Recurse -Force }
            Write-Host "Deleted '$Name'" -f Green
        }
        "" {
            Write-Host ""
            Write-Host "  ccs save <name>     Save current account" -f Yellow
            Write-Host "  ccs <name>          Switch account" -f Yellow
            Write-Host "  ccs list            List accounts" -f Yellow
            Write-Host "  ccs status          Show current account" -f Yellow
            Write-Host "  ccs delete <name>   Delete a saved account" -f Yellow
            Write-Host ""
        }
        default {
            $target = $Command
            Write-Host "Switching to '$target'..." -f Cyan
            _AutoSave
            $tj = "$BackupDir\$target.json"
            if (!(Test-Path $tj)) { Write-Host "Account '$target' not found. Run: ccs save $target" -f Red; return }
            Copy-Item $tj $ClaudeConfig -Force
            $td = "$BackupDir\$target-dir"
            if (Test-Path $td) {
                if (Test-Path $ClaudeDir) { Remove-Item $ClaudeDir -Recurse -Force }
                Copy-Item $td $ClaudeDir -Recurse -Force
            }
            Write-Host "Switched to '$target'" -f Green
        }
    }
}

function clauded { claude --dangerously-skip-permissions @args }

# If executed directly as a script (not dot-sourced), forward args to the function
if ($MyInvocation.InvocationName -ne '.') {
    ccs $args[0] $args[1]
}
# ──────────────────────────────────────────────────────────────
