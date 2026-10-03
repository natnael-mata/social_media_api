@echo off
REM ============================================================
REM  Dell Desktop - Disk Health & Performance Check (launcher)
REM  Just double-click this file. It runs the PowerShell script
REM  with the right policy; the script self-elevates to Admin.
REM  Log output: C:\DiskHealthLogs\
REM ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DiskHealthCheck.ps1"
