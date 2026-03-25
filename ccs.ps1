# ── Claude Code Account Switcher ──────────────────────────────
# Works both as a dot-sourced function and as a direct script.

function ccs {
    param([string]$Command = "", [string]$Name = "")

    $ClaudeConfig = "$env:USERPROFILE\.claude.json"
    $ClaudeDir    = "$env:USERPROFILE\.claude"
    $BackupDir    = "$env:USERPROFILE\.claude-accounts"
    $CurrentFile  = "$BackupDir\.current"   # tracks active account name

    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

    function _GetCurrent { if (Test-Path $CurrentFile) { ([System.IO.File]::ReadAllText($CurrentFile)).Trim() } else { $null } }
    function _SetCurrent($n) { [System.IO.File]::WriteAllText($CurrentFile, $n) }

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
        "refresh" {
            $TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
            $CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
            $SCOPE     = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
            $cur       = _GetCurrent

            # Collect credential files: all backups + live
            $targets = @()
            Get-ChildItem "$BackupDir\*-dir" -Directory -EA SilentlyContinue | ForEach-Object {
                $acc = $_.Name -replace '-dir$', ''
                $targets += @{ Name = $acc; CredFile = "$($_.FullName)\.credentials.json"; IsLive = ($acc -eq $cur) }
            }
            # Also refresh the live credentials directly (covers unsaved or current account)
            $liveCred = "$ClaudeDir\.credentials.json"
            if ((Test-Path $liveCred) -and -not ($targets | Where-Object { $_.IsLive })) {
                $targets += @{ Name = "(live)"; CredFile = $liveCred; IsLive = $true }
            }

            if (!$targets) { Write-Host "No saved accounts found." -f Red; return }

            foreach ($t in $targets) {
                $credFile = $t.CredFile
                if (!(Test-Path $credFile)) {
                    Write-Host "  [$($t.Name)] no credentials file, skipping." -f DarkGray
                    continue
                }
                $cred = Get-Content $credFile -Raw | ConvertFrom-Json
                $rt   = $cred.claudeAiOauth.refreshToken
                if (!$rt) { Write-Host "  [$($t.Name)] no refresh token, skipping." -f DarkGray; continue }

                Write-Host "  Refreshing '$($t.Name)'..." -f Cyan
                try {
                    $body = @{ grant_type = "refresh_token"; refresh_token = $rt; client_id = $CLIENT_ID; scope = $SCOPE } | ConvertTo-Json
                    $resp = Invoke-RestMethod -Uri $TOKEN_URL -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop

                    $cred.claudeAiOauth.accessToken  = $resp.access_token
                    if ($resp.refresh_token) { $cred.claudeAiOauth.refreshToken = $resp.refresh_token }
                    if ($resp.expires_in) {
                        $cred.claudeAiOauth.expiresAt = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) + ($resp.expires_in * 1000)
                    }
                    $cred | ConvertTo-Json -Depth 5 | Set-Content $credFile -Encoding UTF8
                    if ($t.IsLive -and $credFile -ne $liveCred) {
                        $cred | ConvertTo-Json -Depth 5 | Set-Content $liveCred -Encoding UTF8
                    }
                    Write-Host "    OK" -f Green
                } catch {
                    $errMsg = $null
                    try { $errMsg = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message } catch {}
                    if (!$errMsg) { $errMsg = $_.Exception.Message }
                    Write-Host "    FAILED: $errMsg" -f Red
                }
                Start-Sleep -Seconds 2  # avoid rate limiting between accounts
            }
        }
        "schedule" {
            $TaskName  = "ClaudeCodeTokenRefresh"
            $ScriptPath = "$env:USERPROFILE\.claude-switch\ccs.ps1"
            if (Get-ScheduledTask -TaskName $TaskName -EA SilentlyContinue) {
                Write-Host "Already scheduled (task: $TaskName)." -f Yellow; return
            }
            $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-NoProfile -WindowStyle Hidden -Command `". '$ScriptPath'; ccs refresh`""
            $trigger  = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -Once -At (Get-Date)
            $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
            Write-Host "Scheduled: 'ccs refresh' will run every hour." -f Green
            Write-Host "  Task name: $TaskName" -f DarkGray
        }
        "unschedule" {
            $TaskName = "ClaudeCodeTokenRefresh"
            if (Get-ScheduledTask -TaskName $TaskName -EA SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
                Write-Host "Schedule removed." -f Green
            } else {
                Write-Host "No schedule found (task: $TaskName)." -f Yellow
            }
        }
        "uninstall" {
            # 1. Remove scheduled task
            $TaskName = "ClaudeCodeTokenRefresh"
            if (Get-ScheduledTask -TaskName $TaskName -EA SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
                Write-Host "  Removed scheduled task." -f DarkGray
            }

            # 2. Remove install directory
            $InstallDir = "$env:USERPROFILE\.claude-switch"
            if (Test-Path $InstallDir) {
                Remove-Item $InstallDir -Recurse -Force
                Write-Host "  Removed $InstallDir" -f DarkGray
            }

            # 3. Remove dot-source line from PowerShell profile
            $ProfileFile = $PROFILE.CurrentUserAllHosts
            if (Test-Path $ProfileFile) {
                $content = Get-Content $ProfileFile -Raw
                $cleaned = $content -replace "`r?`n# Claude Code Switch`r?`n[^\n]*claude-switch[^\n]*", ""
                if ($cleaned -ne $content) {
                    Set-Content $ProfileFile $cleaned.TrimEnd() -Encoding UTF8
                    Write-Host "  Removed entry from $ProfileFile" -f DarkGray
                }
            }

            # 4. Remove install dir from user PATH (CMD support)
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($userPath -like "*\.claude-switch*") {
                $newPath = ($userPath -split ";" | Where-Object { $_ -notlike "*\.claude-switch*" }) -join ";"
                [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
                Write-Host "  Removed from user PATH." -f DarkGray
            }

            Write-Host "Uninstalled." -f Green
            Write-Host "  Note: account backups in '$env:USERPROFILE\.claude-accounts\' were kept." -f DarkGray
            Write-Host "  Delete that folder manually if you no longer need them." -f DarkGray
        }
        "switch" {
            if (!$Name) { Write-Host "Usage: ccs switch <n>" -f Red; return }
            $target = $Name
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
        "" {
            Write-Host ""
            Write-Host "  ccs save <n>       Save current account"              -f Yellow
            Write-Host "  ccs switch <n>     Switch to account"                 -f Yellow
            Write-Host "  ccs list           List accounts"                     -f Yellow
            Write-Host "  ccs status         Show current account"              -f Yellow
            Write-Host "  ccs refresh        Refresh OAuth tokens for all accounts" -f Yellow
            Write-Host "  ccs schedule       Register hourly auto-refresh task" -f Yellow
            Write-Host "  ccs unschedule     Remove the auto-refresh task"      -f Yellow
            Write-Host "  ccs delete <n>     Delete a saved account"            -f Yellow
            Write-Host "  ccs uninstall      Uninstall ccs"                     -f Yellow
            Write-Host ""
        }
        default {
            Write-Host "Unknown command: '$Command'. Run 'ccs' for usage." -f Red
        }
    }
}

function clauded { claude --dangerously-skip-permissions @args }

# If executed directly as a script (not dot-sourced), forward args to the function
if ($MyInvocation.InvocationName -ne '.') {
    ccs $args[0] $args[1]
}
# ──────────────────────────────────────────────────────────────
