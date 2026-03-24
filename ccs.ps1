# ── Claude Code Account Switcher ──────────────────────────────
# Works both as a dot-sourced function and as a direct script.

function ccs {
    param([string]$Command = "", [string]$Name = "")

    $ClaudeConfig = "$env:USERPROFILE\.claude.json"
    $ClaudeDir    = "$env:USERPROFILE\.claude"
    $BackupDir    = "$env:USERPROFILE\.claude-accounts"
    $CurrentFile  = "$BackupDir\.current"   # tracks active account name

    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

    function _GetCurrent { if (Test-Path $CurrentFile) { (Get-Content $CurrentFile -Raw).Trim() } else { $null } }
    function _SetCurrent($n) { Set-Content $CurrentFile $n -Encoding UTF8 }

    function _SaveAccount($n) {
        if (Test-Path $ClaudeConfig) {
            Copy-Item $ClaudeConfig "$BackupDir\$n.json" -Force
        }
        if (Test-Path $ClaudeDir) {
            $d = "$BackupDir\$n-dir"
            if (Test-Path $d) { Remove-Item $d -Recurse -Force }
            Copy-Item $ClaudeDir $d -Recurse -Force
        }
    }

    function _AutoSave {
        $cur = _GetCurrent
        if ($cur) {
            Write-Host "  Auto-saving '$cur'..." -f DarkGray
            _SaveAccount $cur
        }
    }

    switch ($Command) {
        "save" {
            if (!$Name) { Write-Host "Usage: ccs save <n>" -f Red; return }
            if (!(Test-Path $ClaudeConfig)) { Write-Host "No Claude config found." -f Red; return }
            _SaveAccount $Name
            _SetCurrent $Name
            Write-Host "Saved as '$Name'" -f Green
        }
        "list" {
            $cur = _GetCurrent
            Write-Host "Saved accounts:" -f Cyan
            $files = Get-ChildItem "$BackupDir\*.json" -EA SilentlyContinue
            if (!$files) { Write-Host "  (none)" -f DarkGray; return }
            foreach ($f in $files) {
                $n = [IO.Path]::GetFileNameWithoutExtension($f.Name)
                if ($n -eq $cur) { Write-Host "  * $n (current)" -f Green }
                else              { Write-Host "  - $n" }
            }
        }
        "status" {
            $cur = _GetCurrent
            if ($cur) { Write-Host "Current: $cur" -f Green }
            else       { Write-Host "Current: unknown (run 'ccs save <n>' first)" -f Yellow }
        }
        "delete" {
            if (!$Name) { Write-Host "Usage: ccs delete <n>" -f Red; return }
            $tj = "$BackupDir\$Name.json"
            if (!(Test-Path $tj)) { Write-Host "Account '$Name' not found." -f Red; return }
            Remove-Item $tj -Force
            $td = "$BackupDir\$Name-dir"
            if (Test-Path $td) { Remove-Item $td -Recurse -Force }
            if ((_GetCurrent) -eq $Name) { Remove-Item $CurrentFile -Force -EA SilentlyContinue }
            Write-Host "Deleted '$Name'" -f Green
        }
        "" {
            Write-Host ""
            Write-Host "  ccs save <n>    Save current account" -f Yellow
            Write-Host "  ccs <n>         Switch to account"    -f Yellow
            Write-Host "  ccs list           List accounts"        -f Yellow
            Write-Host "  ccs status         Show current account" -f Yellow
            Write-Host "  ccs delete <n>  Delete a saved account" -f Yellow
            Write-Host ""
        }
        default {
            $target = $Command
            if ((_GetCurrent) -eq $target) {
                Write-Host "Already on '$target'" -f DarkGray
                return
            }
            Write-Host "Switching to '$target'..." -f Cyan
            $tj = "$BackupDir\$target.json"
            if (!(Test-Path $tj)) { Write-Host "Account '$target' not found. Run: ccs save $target" -f Red; return }

            _AutoSave   # flush live state → current account's backup

            Copy-Item $tj $ClaudeConfig -Force
            $td = "$BackupDir\$target-dir"
            if (Test-Path $td) {
                if (Test-Path $ClaudeDir) { Remove-Item $ClaudeDir -Recurse -Force }
                Copy-Item $td $ClaudeDir -Recurse -Force
            }
            _SetCurrent $target
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
