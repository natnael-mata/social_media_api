@echo off
REM ==========================================================
REM  Exports the latest CHKDSK repair result (from the Windows
REM  Event Log) to a text file on the Desktop:
REM     chkdsk-result.txt
REM  Just double-click this file. No admin rights needed.
REM ==========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ev = Get-WinEvent -LogName Application -MaxEvents 3000 | Where-Object { $_.ProviderName -match 'Wininit|Chkdsk' } | Select-Object -First 5; if ($ev) { $ev | Format-List TimeCreated, ProviderName, Message | Out-File \"$env:USERPROFILE\Desktop\chkdsk-result.txt\" -Encoding utf8; Write-Host 'Done. chkdsk-result.txt saved on the Desktop.' -ForegroundColor Green } else { Write-Host 'No chkdsk events found in the Application log.' -ForegroundColor Yellow }"
pause
