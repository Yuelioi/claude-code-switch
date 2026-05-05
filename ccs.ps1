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

    # Save credentials + identity fields only (~1 KB per account)
    function _SaveAccount($n) {
        $credSrc = "$ClaudeDir\.credentials.json"
        if (-not (Test-Path $credSrc)) { Write-Host "  no credentials file, nothing to save" -f DarkGray; return }
        $creds = Get-Content $credSrc -Raw | ConvertFrom-Json
        $oauthAccount = $null
        $userID = $null
        if (Test-Path $ClaudeConfig) {
            try {
                $config = Get-Content $ClaudeConfig -Raw | ConvertFrom-Json
                $oauthAccount = $config.oauthAccount
                $userID       = $config.userID
            } catch {}
        }
        $out = [ordered]@{
            credentials  = $creds
            oauthAccount = $oauthAccount
            userID       = $userID
        }
        $out | ConvertTo-Json -Depth 20 | Set-Content "$BackupDir\$n.creds.json" -Encoding UTF8
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
            $files = Get-ChildItem "$BackupDir\*.creds.json" -EA SilentlyContinue
            if (!$files) { Write-Host "  (none)" -f DarkGray; return }
            foreach ($f in $files) {
                $n = $f.Name -replace '\.creds\.json$', ''
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
            $f = "$BackupDir\$Name.creds.json"
            if (!(Test-Path $f)) { Write-Host "Account '$Name' not found." -f Red; return }
            Remove-Item $f -Force
            if ((_GetCurrent) -eq $Name) { Remove-Item $CurrentFile -Force -EA SilentlyContinue }
            Write-Host "Deleted '$Name'" -f Green
        }
        "refresh" {
            $TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
            $CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
            $SCOPE     = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
            $cur       = _GetCurrent
            $liveCred  = "$ClaudeDir\.credentials.json"
            $refreshedLive = $false

            $files = Get-ChildItem "$BackupDir\*.creds.json" -EA SilentlyContinue

            foreach ($f in $files) {
                $acc  = $f.Name -replace '\.creds\.json$', ''
                $data = Get-Content $f.FullName -Raw | ConvertFrom-Json
                $rt   = $data.credentials.claudeAiOauth.refreshToken
                if (!$rt) { Write-Host "  [$acc] no refresh token, skipping." -f DarkGray; continue }

                Write-Host "  Refreshing '$acc'..." -f Cyan
                try {
                    $body = @{ grant_type = "refresh_token"; refresh_token = $rt; client_id = $CLIENT_ID; scope = $SCOPE } | ConvertTo-Json
                    $resp = Invoke-RestMethod -Uri $TOKEN_URL -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop

                    $data.credentials.claudeAiOauth.accessToken = $resp.access_token
                    if ($resp.refresh_token) { $data.credentials.claudeAiOauth.refreshToken = $resp.refresh_token }
                    if ($resp.expires_in) {
                        $data.credentials.claudeAiOauth.expiresAt = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) + ($resp.expires_in * 1000)
                    }
                    $data | ConvertTo-Json -Depth 20 | Set-Content $f.FullName -Encoding UTF8
                    if ($acc -eq $cur) {
                        $data.credentials | ConvertTo-Json -Depth 20 | Set-Content $liveCred -Encoding UTF8
                        $refreshedLive = $true
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

            # Refresh live credentials if not covered by any backup
            if (-not $refreshedLive -and (Test-Path $liveCred)) {
                $cred = Get-Content $liveCred -Raw | ConvertFrom-Json
                $rt   = $cred.claudeAiOauth.refreshToken
                if ($rt) {
                    Write-Host "  Refreshing '(live)'..." -f Cyan
                    try {
                        $body = @{ grant_type = "refresh_token"; refresh_token = $rt; client_id = $CLIENT_ID; scope = $SCOPE } | ConvertTo-Json
                        $resp = Invoke-RestMethod -Uri $TOKEN_URL -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
                        $cred.claudeAiOauth.accessToken = $resp.access_token
                        if ($resp.refresh_token) { $cred.claudeAiOauth.refreshToken = $resp.refresh_token }
                        if ($resp.expires_in) {
                            $cred.claudeAiOauth.expiresAt = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) + ($resp.expires_in * 1000)
                        }
                        $cred | ConvertTo-Json -Depth 20 | Set-Content $liveCred -Encoding UTF8
                        Write-Host "    OK" -f Green
                    } catch {
                        $errMsg = $null
                        try { $errMsg = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message } catch {}
                        if (!$errMsg) { $errMsg = $_.Exception.Message }
                        Write-Host "    FAILED: $errMsg" -f Red
                    }
                }
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
        "login" {
            if (!$Name) { Write-Host "Usage: ccs login <n>" -f Red; return }
            if (-not (Get-Command claude -EA SilentlyContinue)) {
                Write-Host "Error: 'claude' CLI not found in PATH." -f Red; return
            }
            _AutoSave   # flush current state before login overwrites .credentials.json
            Write-Host "Starting Claude Code login flow..." -f Cyan
            & claude auth login
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Login failed or cancelled." -f Red; return
            }
            if (-not (Test-Path "$ClaudeDir\.credentials.json")) {
                Write-Host "Login completed but no credentials file was written." -f Red; return
            }
            _SaveAccount $Name
            _SetCurrent $Name
            Write-Host "Logged in as '$Name'" -f Green
        }
        "switch" {
            if (!$Name) { Write-Host "Usage: ccs switch <n>" -f Red; return }
            $target = $Name
            if ((_GetCurrent) -eq $target) {
                Write-Host "Already on '$target'" -f DarkGray
                return
            }
            Write-Host "Switching to '$target'..." -f Cyan
            $f = "$BackupDir\$target.creds.json"
            if (!(Test-Path $f)) { Write-Host "Account '$target' not found. Run: ccs save $target" -f Red; return }

            _AutoSave   # flush live state → current account's backup

            if (-not (Test-Path $ClaudeDir)) { New-Item -ItemType Directory -Path $ClaudeDir | Out-Null }

            $data = Get-Content $f -Raw | ConvertFrom-Json

            # Write live credentials
            $data.credentials | ConvertTo-Json -Depth 20 | Set-Content "$ClaudeDir\.credentials.json" -Encoding UTF8

            # Merge identity fields into live .claude.json, preserving everything else
            $config = $null
            if (Test-Path $ClaudeConfig) {
                try { $config = Get-Content $ClaudeConfig -Raw | ConvertFrom-Json } catch {}
            }
            if (-not $config) { $config = New-Object PSObject }

            function _SetProp($obj, $name, $value) {
                if ($null -eq $value) { return }
                if ($obj.PSObject.Properties.Name -contains $name) {
                    $obj.$name = $value
                } else {
                    $obj | Add-Member -MemberType NoteProperty -Name $name -Value $value
                }
            }
            _SetProp $config 'oauthAccount' $data.oauthAccount
            _SetProp $config 'userID'       $data.userID

            $config | ConvertTo-Json -Depth 100 | Set-Content $ClaudeConfig -Encoding UTF8

            _SetCurrent $target
            Write-Host "Switched to '$target'" -f Green
        }
        "" {
            Write-Host ""
            Write-Host "  ccs login <n>      Log in via 'claude auth login' and save as <n>" -f Yellow
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
