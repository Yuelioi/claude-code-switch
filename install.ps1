# Claude Code Switch - Windows Installer (PowerShell + CMD)
# Supports local and remote (irm | iex) execution

$Repo       = "https://raw.githubusercontent.com/Yuelioi/claude-code-switch/main"
$InstallDir = "$env:USERPROFILE\.claude-switch"
$ProfileFile = $PROFILE.CurrentUserAllHosts

# ── Download or copy files ────────────────────────────────────
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

$isRemote = [string]::IsNullOrEmpty($MyInvocation.MyCommand.Definition) -or
            ($MyInvocation.MyCommand.Definition -notmatch "\.ps1$")

function Get-File($filename) {
    $dest = "$InstallDir\$filename"
    if ($isRemote) {
        Write-Host "Downloading $filename..." -ForegroundColor Cyan
        try { Invoke-RestMethod "$Repo/$filename" -OutFile $dest }
        catch { Write-Host "Failed to download $filename`: $_" -ForegroundColor Red; exit 1 }
    } else {
        $src = Join-Path $PSScriptRoot $filename
        if (-not (Test-Path $src)) { Write-Host "$filename not found." -ForegroundColor Red; exit 1 }
        Copy-Item $src $dest -Force
    }
    Write-Host "  -> $dest" -ForegroundColor DarkGray
}

Get-File "ccs.ps1"
Get-File "ccs.bat"

# ── PowerShell: dot-source in profile ────────────────────────
if (-not (Test-Path $ProfileFile)) {
    New-Item -ItemType File -Path $ProfileFile -Force | Out-Null
}

$dotSourceLine  = ". `"$InstallDir\ccs.ps1`""
$profileContent = Get-Content $ProfileFile -Raw -ErrorAction SilentlyContinue

if ($profileContent -and $profileContent.Contains($dotSourceLine)) {
    Write-Host "PowerShell profile already configured." -ForegroundColor Yellow
} else {
    Add-Content -Path $ProfileFile -Value "`n# Claude Code Switch`n$dotSourceLine"
    Write-Host "PowerShell: added to $ProfileFile" -ForegroundColor DarkGray
}

# ── CMD: add InstallDir to user PATH ─────────────────────────
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
    Write-Host "CMD: added $InstallDir to user PATH" -ForegroundColor DarkGray
} else {
    Write-Host "CMD: PATH already configured." -ForegroundColor Yellow
}

# ── Done ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "Installed!" -ForegroundColor Green
Write-Host ""
Write-Host "PowerShell — reload:" -ForegroundColor DarkGray
Write-Host "  . `$PROFILE" -ForegroundColor Cyan
Write-Host ""
Write-Host "CMD — open a new window, then use ccs directly." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Usage:" -ForegroundColor DarkGray
Write-Host "  ccs save <name>     Save current account" -ForegroundColor Yellow
Write-Host "  ccs <name>          Switch account" -ForegroundColor Yellow
Write-Host "  ccs list            List accounts" -ForegroundColor Yellow
Write-Host "  ccs status          Show current account" -ForegroundColor Yellow
Write-Host "  ccs refresh         Refresh OAuth tokens for all accounts" -ForegroundColor Yellow
Write-Host "  ccs schedule        Register hourly auto-refresh task" -ForegroundColor Yellow
Write-Host "  ccs unschedule      Remove the auto-refresh task" -ForegroundColor Yellow
Write-Host "  ccs delete <name>   Delete a saved account" -ForegroundColor Yellow
Write-Host "  ccs uninstall       Uninstall ccs" -ForegroundColor Yellow
Write-Host ""
Write-Host "  clauded             claude --dangerously-skip-permissions" -ForegroundColor Yellow
