@echo off
:: Claude Code Switch - CMD wrapper
:: Calls the PowerShell script so CMD users can use `ccs` directly.
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude-switch\ccs.ps1" %*
