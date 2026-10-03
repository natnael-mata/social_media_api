@echo off
setlocal
title PC Fix Toolkit - %COMPUTERNAME%

rem ---- Ask for administrator rights if we do not have them ----
net session >nul 2>&1
if errorlevel 1 (
  echo Asking for administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "SELF=%~f0"

:menu
cls
echo ==============================================================
echo   PC FIX TOOLKIT  -  %COMPUTERNAME%
echo   Results of 1, 7 and 8 are also saved on the Desktop as
echo   PC-Fix-Log_%COMPUTERNAME%.txt
echo ==============================================================
echo.
echo    1  Malware check - dlIhost / setup / cmd     DO THIS FIRST
echo    2  Update Defender + FULL virus scan         1-2 hours
echo    3  Defender OFFLINE scan                     restarts PC
echo.
echo    -- BACK UP the user's files before 4, 5 and 6 --
echo    4  Schedule CHKDSK C: /F                     restarts PC
echo    5  SFC /scannow - repair system files
echo    6  DISM RestoreHealth - only if SFC could not fix all
echo.
echo    7  Power-cut check - unexpected shutdowns
echo    8  Licence check - Windows, Office, Adobe
echo    9  Remove drive letter D: from System Reserved
echo   10  Open Programs and Features - uninstall list
echo   11  Open Task Manager - Startup tab
echo   12  Add Amharic keyboard - opens Language settings
echo.
echo    0  Exit
echo.
set "c="
set /p "c=Type a number and press Enter: "
if "%c%"=="1"  goto malware
if "%c%"=="2"  goto fullscan
if "%c%"=="3"  goto offlinescan
if "%c%"=="4"  goto chkdsk
if "%c%"=="5"  goto sfc
if "%c%"=="6"  goto dism
if "%c%"=="7"  goto powercuts
if "%c%"=="8"  goto licences
if "%c%"=="9"  goto driveletter
if "%c%"=="10" goto uninstall
if "%c%"=="11" goto startup
if "%c%"=="12" goto amharic
if "%c%"=="0"  exit /b
goto menu

:malware
call :runps Check-Malware
pause
goto menu

:fullscan
set "MP=%ProgramFiles%\Windows Defender\MpCmdRun.exe"
echo Updating Defender virus definitions...
"%MP%" -SignatureUpdate
echo.
echo Starting FULL scan. This takes 1-2 hours. The PC stays usable.
"%MP%" -Scan -ScanType 2
echo.
echo Full scan finished. Threats found, if any, are listed above
echo and in Windows Security - Protection history.
pause
goto menu

:offlinescan
echo The PC will RESTART and scan for about 15 minutes before Windows loads.
echo Save and close all open work first.
choice /C YN /M "Start the offline scan now"
if errorlevel 2 goto menu
powershell -NoProfile -Command "Start-MpWDOScan"
exit /b

:chkdsk
echo CHKDSK /F repairs the file system on C: during the next restart.
echo Make sure the user's files are backed up first.
choice /C YN /M "Schedule CHKDSK on C: now"
if errorlevel 2 goto menu
echo Y| chkdsk C: /F
echo.
choice /C YN /M "Restart now so CHKDSK can run"
if errorlevel 2 goto menu
shutdown /r /t 10 /c "Restarting to run CHKDSK on C:"
exit /b

:sfc
echo Running SFC /scannow - takes 10-20 minutes...
sfc /scannow
echo.
echo If it says "found corrupt files but was unable to fix some of them",
echo run option 6 (DISM), then run option 5 (SFC) again.
pause
goto menu

:dism
echo Running DISM RestoreHealth - takes 10-30 minutes, needs internet...
DISM /Online /Cleanup-Image /RestoreHealth
echo.
echo Now run option 5 (SFC) again.
pause
goto menu

:powercuts
call :runps Check-PowerCuts
pause
goto menu

:licences
call :runps Check-Licences
pause
goto menu

:driveletter
vol D: 2>nul | find /i "System Reserved" >nul
if errorlevel 1 goto notreserved
mountvol D: /D
echo Drive letter D: removed from System Reserved. Nothing was deleted.
pause
goto menu
:notreserved
echo D: is NOT labelled "System Reserved" on this PC - left untouched.
pause
goto menu

:uninstall
echo Uninstall these if present:
echo   Power Ge'ez 2010, Web Companion, Searchims, ZipandRar,
echo   AVG Secure Browser, Freemake Video Converter, PDF Suite 20,
echo   Rainmeter, SMADAV, WinRAR 4.00, Mozilla Firefox 72,
echo   Mozilla Maintenance Service, Microsoft Office Enterprise 2007,
echo   Python 3.7 - only if nobody uses it.
echo Then update WinRAR 6.02 to the latest version from rarlab.com,
echo and run Malwarebytes AdwCleaner from malwarebytes.com.
start "" appwiz.cpl
pause
goto menu

:startup
echo Disable: Rainmeter, Opera Stable, MicrosoftEdgeAutoLaunch,
echo          IDMan, Simple Sticky Notes, Web Companion, Ge'ez 2010.
echo AnyDesk: disable it unless someone really uses it.
start "" taskmgr /0 /startup
pause
goto menu

:amharic
echo Click "Add a language", choose Amharic, and install it.
start "" ms-settings:regionlanguage
pause
goto menu

rem ---- Runs one function from the PowerShell part at the end of this file ----
:runps
powershell -NoProfile -ExecutionPolicy Bypass -Command "$code = ((Get-Content -LiteralPath $env:SELF -Raw) -split ('#PS' + 'START'))[1]; . ([scriptblock]::Create($code)); %~1"
goto :eof

rem Everything below the marker is PowerShell, never run by cmd.
exit /b
#PSSTART
$Log = Join-Path ([Environment]::GetFolderPath('Desktop')) ("PC-Fix-Log_{0}.txt" -f $env:COMPUTERNAME)

function Write-Section {
    param([string]$Title, [scriptblock]$Body)
    $head = "`r`n==== $Title  [$(Get-Date -Format 'yyyy-MM-dd HH:mm')] ===="
    $text = $head + "`r`n" + ((& $Body) | Out-String -Width 250)
    $text | Tee-Object -FilePath $Log -Append
}

function Check-Malware {
    Write-Section 'Running processes named dlIhost / setup / cmd' {
        $procs = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(dlihost|setup|cmd)\.exe$' })
        if ($procs.Count -eq 0) { 'None running right now.' }
        foreach ($p in $procs) {
            $path = $p.ExecutablePath
            $sig = $null
            $hash = $null
            if ($path -and (Test-Path -LiteralPath $path)) {
                $sig  = Get-AuthenticodeSignature -LiteralPath $path
                $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            }
            $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue).Name
            $signer = ''
            if ($sig -and $sig.SignerCertificate) { $signer = $sig.SignerCertificate.Subject }
            if ($p.Name -match '^dlihost') {
                $verdict = 'SUSPICIOUS - fake name with a capital I. The real Windows file is dllhost.exe'
            } elseif (-not $sig) {
                $verdict = 'UNKNOWN - could not read the file'
            } elseif ($sig.Status -ne 'Valid') {
                $verdict = 'SUSPICIOUS - file is not validly signed'
            } elseif ($signer -match 'O=Microsoft' -and $path -like "$env:windir\System32\*") {
                $verdict = 'OK - genuine Microsoft file in System32'
            } else {
                $verdict = "CHECK - signed by: $signer"
            }
            [pscustomobject]@{
                Verdict     = $verdict
                Name        = $p.Name
                PID         = $p.ProcessId
                Parent      = "$parent (PID $($p.ParentProcessId))"
                Path        = $path
                CommandLine = $p.CommandLine
                Signature   = "$(if ($sig) { $sig.Status }) $signer"
                SHA256      = $hash
            } | Format-List
        }
        'Note: the cmd.exe whose CommandLine contains PC-Fix-Toolkit is this toolkit itself.'
    }

    Write-Section 'Startup entries, services and scheduled tasks that mention dlIhost' {
        $hits = @()
        $hits += Get-CimInstance Win32_StartupCommand | Where-Object { $_.Command -match 'dlihost' } |
            ForEach-Object { "Startup: $($_.Name) - $($_.Command) [$($_.Location)]" }
        $hits += Get-CimInstance Win32_Service | Where-Object { $_.PathName -match 'dlihost' } |
            ForEach-Object { "Service: $($_.Name) - $($_.PathName)" }
        $hits += Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -match 'dlihost' } |
            ForEach-Object { "Task: $($_.TaskPath)$($_.TaskName)" }
        if ($hits.Count -eq 0) { 'None found.' } else { $hits }
    }

    Write-Host ''
    Write-Host 'Searching C: and E: for dlIhost.exe - this takes a few minutes, please wait...' -ForegroundColor Yellow
    Write-Section 'Files named dlIhost.exe on C: and E:' {
        $files = @()
        foreach ($d in 'C:\', 'E:\') {
            if (Test-Path $d) {
                $files += Get-ChildItem -Path $d -Filter 'dlihost.exe' -Recurse -Force -File -ErrorAction SilentlyContinue
            }
        }
        if ($files.Count -eq 0) { 'No file named dlIhost.exe found.' }
        foreach ($f in $files) {
            [pscustomobject]@{
                Path      = $f.FullName
                Size      = $f.Length
                Modified  = $f.LastWriteTime
                Signature = (Get-AuthenticodeSignature -LiteralPath $f.FullName).Status
                SHA256    = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
            } | Format-List
        }
    }

    Write-Host ''
    Write-Host 'NEXT: paste every SHA256 shown above into the search box at virustotal.com.' -ForegroundColor Cyan
    Write-Host 'If anything says SUSPICIOUS: unplug the network cable, back up data files only,' -ForegroundColor Cyan
    Write-Host 'and reinstall Windows. Do not bother with CHKDSK/SFC on an infected PC.' -ForegroundColor Cyan
    Write-Host "Log saved to: $Log"
}

function Check-PowerCuts {
    Write-Section 'Unexpected shutdowns / power loss (newest 30)' {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 6008 } -MaxEvents 30 -ErrorAction SilentlyContinue)
        if ($ev.Count -eq 0) {
            'None found.'
        } else {
            "Found: $($ev.Count) (showing up to 30)"
            $ev | Select-Object TimeCreated, Id, @{ n = 'Meaning'; e = {
                if ($_.Id -eq 41) { 'Kernel-Power 41: PC lost power or was hard-reset' }
                else { '6008: the previous shutdown was unexpected' } } } | Format-Table -AutoSize
        }
    }
    Write-Host "Log saved to: $Log"
}

function Check-Licences {
    Write-Section 'Windows activation' {
        cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    }
    Write-Section 'Office activation' {
        $found = $false
        foreach ($o in "$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS", "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS") {
            if (Test-Path $o) { $found = $true; cscript //nologo $o /dstatus }
        }
        if (-not $found) { 'OSPP.VBS not found.' }
        'Look at "KMS machine name". An unknown name, or 127.0.0.x, means a crack (KMSpico / KMSAuto).'
    }
    Write-Section 'Activation crack traces (tasks / services)' {
        $t = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'KMS|Pico|AAct' })
        $s = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'KMS|Pico' -or $_.PathName -match 'KMS|Pico|AAct' })
        if (($t.Count + $s.Count) -eq 0) { 'None found.' }
        $t | ForEach-Object { "Task: $($_.TaskPath)$($_.TaskName)" }
        $s | ForEach-Object { "Service: $($_.Name) - $($_.PathName)" }
    }
    Write-Section 'Adobe' {
        $cc = (Test-Path "$env:ProgramFiles\Adobe\Adobe Creative Cloud") -or (Test-Path "${env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud")
        "Creative Cloud app installed: $cc   (a licensed Adobe install always has it)"
        $h = @(Select-String -Path "$env:windir\System32\drivers\etc\hosts" -Pattern 'adobe' -ErrorAction SilentlyContinue)
        "Lines in the hosts file blocking Adobe: $($h.Count)   (more than 0 = typical cracked Adobe)"
        $h | ForEach-Object { '  ' + $_.Line }
    }
    Write-Host "Log saved to: $Log"
}
