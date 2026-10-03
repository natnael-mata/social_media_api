<#
.SYNOPSIS
    Dell Desktop - Full Health Check: Specs, Disk Health, Corrupt Files,
    Virus Scan and Performance. Report saved as a TEXT file on the Desktop.
.DESCRIPTION
    1.  Dell identity (model, Service Tag, BIOS)
    2.  Full desktop specification (CPU, RAM modules, GPU, motherboard,
        drives, network) - to judge what software the PC can run and what
        should be upgraded
    3.  Installed software list
    4.  Physical disk health (SMART, temperature, SSD wear, media errors)
    5.  SMART firmware failure prediction
    6.  Volumes - free space & dirty flag
    7.  CHKDSK online scan (read-only)
    8.  Corrupted Windows system files (SFC verify + DISM health check)
    9.  Disk-related errors in the event log
    10. Disk speed test (WinSAT)
    11. Virus / security check (Windows Defender status, threat history,
        quick scan)
    12. Printer status (offline/error printers, stuck jobs, spooler,
        network printer reachability)
    13. Network connection status (adapters, IP/gateway, internet, DNS)
    14. Performance snapshot (CPU, RAM, disk queue, top processes)

    When finished the full report is saved as a .txt file ON THE DESKTOP
    (plus a backup copy in C:\DiskHealthLogs).
.NOTES
    - Windows 10/11, built-in PowerShell 5.1, no modules needed.
    - Must run as Administrator (self-elevates if launched normally).
    - Diagnostic only: nothing is repaired or deleted.
.PARAMETER SkipSpeedTest
    Skip the WinSAT disk speed test (saves ~1-2 min).
.PARAMETER SkipVirusScan
    Skip the Defender quick scan (saves ~5-15 min); status and threat
    history are still reported.
.PARAMETER SkipSystemFileCheck
    Skip SFC/DISM system file verification (saves ~5-10 min).
#>

[CmdletBinding()]
param(
    [switch]$SkipSpeedTest,
    [switch]$SkipVirusScan,
    [switch]$SkipSystemFileCheck
)

# ------------------------------------------------------------------ elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator - relaunching elevated..." -ForegroundColor Yellow
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($SkipSpeedTest)       { $argLine += ' -SkipSpeedTest' }
    if ($SkipVirusScan)       { $argLine += ' -SkipVirusScan' }
    if ($SkipSystemFileCheck) { $argLine += ' -SkipSystemFileCheck' }
    Start-Process powershell.exe -ArgumentList $argLine -Verb RunAs
    exit
}

# ------------------------------------------------------------------- logging
# Report goes to the Desktop as a .txt file; backup copy in C:\DiskHealthLogs.
$Stamp      = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$ReportName = "PC-Health-Report_$($env:COMPUTERNAME)_$Stamp.txt"
$DesktopDir = [Environment]::GetFolderPath('Desktop')
if (-not $DesktopDir -or -not (Test-Path $DesktopDir)) { $DesktopDir = "$env:PUBLIC\Desktop" }
$LogFile    = Join-Path $DesktopDir $ReportName
$BackupDir  = 'C:\DiskHealthLogs'
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

$script:Issues   = New-Object System.Collections.Generic.List[string]
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:Upgrades = New-Object System.Collections.Generic.List[string]   # improvement recommendations

function Write-Log {
    param([string]$Message = '', [string]$Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $Message
}
function Write-Section {
    param([string]$Title)
    $bar = '=' * 70
    Write-Log ''
    Write-Log $bar 'Cyan'
    Write-Log ("  " + $Title) 'Cyan'
    Write-Log $bar 'Cyan'
}
function Add-Issue   { param([string]$Text) $script:Issues.Add($Text);   Write-Log ("  [FAIL] " + $Text) 'Red' }
function Add-Warning { param([string]$Text) $script:Warnings.Add($Text); Write-Log ("  [WARN] " + $Text) 'Yellow' }
function Add-Upgrade { param([string]$Text) $script:Upgrades.Add($Text); Write-Log ("  [UPGRADE] " + $Text) 'Magenta' }
function Write-Pass  { param([string]$Text) Write-Log ("  [PASS] " + $Text) 'Green' }

Write-Log ('#' * 70)
Write-Log "#  DELL DESKTOP - FULL HEALTH, SPEC, VIRUS & PERFORMANCE REPORT"
Write-Log "#  Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "#  Computer: $env:COMPUTERNAME   User: $env:USERNAME"
Write-Log "#  Report  : $LogFile"
Write-Log ('#' * 70)

# ------------------------------------------------- 1. System / Dell identity
Write-Section '1. SYSTEM INFORMATION (Dell)'
try {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os   = Get-CimInstance Win32_OperatingSystem
    Write-Log ("  Manufacturer : {0}" -f $cs.Manufacturer)
    Write-Log ("  Model        : {0}" -f $cs.Model)
    Write-Log ("  Service Tag  : {0}   (use at support.dell.com)" -f $bios.SerialNumber)
    Write-Log ("  BIOS Version : {0}" -f $bios.SMBIOSBIOSVersion)
    Write-Log ("  OS           : {0}  (Build {1}, {2})" -f $os.Caption, $os.BuildNumber, $os.OSArchitecture)
    Write-Log ("  Last Boot    : {0}" -f $os.LastBootUpTime)
    $uptime = (Get-Date) - $os.LastBootUpTime
    Write-Log ("  Uptime       : {0} days {1} hours" -f $uptime.Days, $uptime.Hours)
    if ($uptime.Days -ge 14) { Add-Warning "PC has not rebooted in $($uptime.Days) days - reboot before judging performance." }
    if ($os.Caption -match 'Windows 10') {
        Add-Issue 'Windows 10 reached end of support (Oct 2025) - no more security updates. Upgrade to Windows 11 or replace the PC.'
    }
} catch { Write-Log "  ERROR collecting system info: $_" 'Red' }

# --------------------------------------------- 2. Full desktop specification
Write-Section '2. DESKTOP SPECIFICATION (for software compatibility review)'
try {
    # --- CPU ---
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Write-Log '  CPU:'
    Write-Log ("    Name            : {0}" -f $cpu.Name.Trim())
    Write-Log ("    Cores / Threads : {0} / {1}" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    Write-Log ("    Max Clock       : {0:N2} GHz" -f ($cpu.MaxClockSpeed / 1000))
    if ($cpu.NumberOfCores -lt 4) { Add-Upgrade "CPU has only $($cpu.NumberOfCores) cores - weak for modern software; consider newer PC." }

    # --- RAM ---
    $cs = Get-CimInstance Win32_ComputerSystem
    $totalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    Write-Log ''
    Write-Log ("  RAM: {0:N1} GB total" -f $totalRamGB)
    $memTypes = @{ 20='DDR'; 21='DDR2'; 24='DDR3'; 26='DDR4'; 34='DDR5'; 0='Unknown' }
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $t = $_.SMBIOSMemoryType; if (-not $memTypes.ContainsKey([int]$t)) { $t = 0 }
        Write-Log ("    Slot {0,-12}: {1,5:N1} GB  {2}  {3} MHz  ({4})" -f $_.DeviceLocator,
                   ($_.Capacity/1GB), $memTypes[[int]$t], $_.Speed, $_.Manufacturer)
    }
    $slotsTotal = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum
    $slotsUsed  = (Get-CimInstance Win32_PhysicalMemory | Measure-Object).Count
    Write-Log ("    Slots used      : {0} of {1}" -f $slotsUsed, $slotsTotal)
    if     ($totalRamGB -lt 8)  { Add-Upgrade "Only $totalRamGB GB RAM - below the practical minimum (8 GB); upgrade to 8-16 GB." }
    elseif ($totalRamGB -lt 16) { Add-Upgrade "$totalRamGB GB RAM - fine for office work; upgrade to 16 GB for heavier software." }

    # --- GPU ---
    Write-Log ''
    Write-Log '  Graphics:'
    Get-CimInstance Win32_VideoController | ForEach-Object {
        $vram = if ($_.AdapterRAM -gt 0) { "{0:N1} GB" -f ($_.AdapterRAM/1GB) } else { 'n/a' }
        Write-Log ("    {0}  (VRAM: {1}, Driver: {2}, {3}x{4})" -f $_.Name, $vram,
                   $_.DriverVersion, $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution)
    }

    # --- Motherboard ---
    $mb = Get-CimInstance Win32_BaseBoard
    Write-Log ''
    Write-Log ("  Motherboard: {0} {1}" -f $mb.Manufacturer, $mb.Product)

    # --- Storage devices (type matters for speed) ---
    Write-Log ''
    Write-Log '  Storage drives:'
    $sysDiskIsHDD = $false
    Get-PhysicalDisk | ForEach-Object {
        Write-Log ("    Disk #{0}: {1}  {2:N0} GB  Type: {3}  Bus: {4}" -f $_.DeviceId,
                   $_.FriendlyName, ($_.Size/1GB), $_.MediaType, $_.BusType)
        if ($_.MediaType -eq 'HDD' -and $_.DeviceId -eq 0) { $sysDiskIsHDD = $true }
    }
    if ($sysDiskIsHDD) { Add-Upgrade 'Windows runs from a mechanical HDD - replacing it with an SSD is the single biggest speed improvement.' }

    # --- Network ---
    Write-Log ''
    Write-Log '  Network adapters (connected):'
    Get-CimInstance Win32_NetworkAdapter -Filter "NetConnectionStatus=2" | ForEach-Object {
        $speed = if ($_.Speed) { "{0:N0} Mbps" -f ($_.Speed/1MB) } else { 'n/a' }
        Write-Log ("    {0}  ({1})" -f $_.Name, $speed)
    }
} catch { Write-Log "  ERROR collecting specification: $_" 'Red' }

# ------------------------------------------------------ 3. Installed software
Write-Section '3. INSTALLED SOFTWARE (to review what runs on this PC)'
try {
    $apps = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        Sort-Object DisplayName -Unique
    Write-Log ("  {0} programs installed:" -f $apps.Count)
    foreach ($a in $apps) {
        Write-Log ("    {0,-55} {1,-18} {2}" -f ([string]$a.DisplayName).Substring(0, [math]::Min(55, $a.DisplayName.Length)),
                   $a.DisplayVersion, $a.Publisher)
    }
} catch { Write-Log "  ERROR listing software: $_" 'Red' }

# --------------------------------------------------------- 4. Physical disks
Write-Section '4. PHYSICAL DISK HEALTH (SMART / reliability)'
try {
    foreach ($d in Get-PhysicalDisk) {
        Write-Log ""
        Write-Log ("  Disk #{0}: {1}" -f $d.DeviceId, $d.FriendlyName)
        Write-Log ("    Media/Bus         : {0} / {1}" -f $d.MediaType, $d.BusType)
        Write-Log ("    Size              : {0:N1} GB" -f ($d.Size / 1GB))
        Write-Log ("    Health Status     : {0}" -f $d.HealthStatus)
        Write-Log ("    Operational Status: {0}" -f ($d.OperationalStatus -join ', '))

        if ($d.HealthStatus -ne 'Healthy') {
            Add-Issue ("Disk #{0} ({1}) HealthStatus = {2} - BACK UP DATA, disk may be failing." -f $d.DeviceId, $d.FriendlyName, $d.HealthStatus)
        } else {
            Write-Pass ("Disk #{0} reports Healthy" -f $d.DeviceId)
        }

        try {
            $r = $d | Get-StorageReliabilityCounter -ErrorAction Stop
            if ($null -ne $r.Temperature -and $r.Temperature -gt 0) {
                Write-Log ("    Temperature       : {0} C (max {1} C)" -f $r.Temperature, $r.TemperatureMax)
                if ($r.Temperature -ge 55) { Add-Warning ("Disk #{0} running hot: {1} C - check airflow/fans." -f $d.DeviceId, $r.Temperature) }
            }
            if ($null -ne $r.Wear -and $r.Wear -gt 0) {
                Write-Log ("    SSD Wear          : {0} %" -f $r.Wear)
                if ($r.Wear -ge 80) { Add-Issue ("Disk #{0} SSD wear at {1}% - plan replacement." -f $d.DeviceId, $r.Wear) }
                elseif ($r.Wear -ge 50) { Add-Warning ("Disk #{0} SSD wear at {1}% - monitor." -f $d.DeviceId, $r.Wear) }
            }
            if ($null -ne $r.PowerOnHours) { Write-Log ("    Power-On Hours    : {0}" -f $r.PowerOnHours) }
            foreach ($prop in 'ReadErrorsUncorrected','WriteErrorsUncorrected') {
                $v = $r.$prop
                if ($null -ne $v) {
                    Write-Log ("    {0,-18}: {1}" -f $prop, $v)
                    if ($v -gt 0) { Add-Issue ("Disk #{0} has {1} = {2} (uncorrected errors = failing media)." -f $d.DeviceId, $prop, $v) }
                }
            }
        } catch { Write-Log "    (Reliability counters not available for this disk)" }
    }
} catch { Write-Log "  ERROR reading physical disks: $_" 'Red' }

# -------------------------------------------- 5. SMART predict-failure flag
Write-Section '5. SMART FAILURE PREDICTION (firmware flag)'
try {
    $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop
    foreach ($s in $smart) {
        $name = ($s.InstanceName -split '#')[1]
        if ($s.PredictFailure) {
            Add-Issue ("SMART PREDICTS FAILURE on '$name' (reason code $($s.Reason)) - replace this drive ASAP.")
        } else {
            Write-Pass ("No SMART failure predicted: $name")
        }
    }
} catch {
    Write-Log "  (SMART WMI data not exposed on this controller - rely on Section 4 results)"
}

# --------------------------------------------------------- 6. Volumes / space
Write-Section '6. VOLUMES - FREE SPACE & DIRTY FLAG'
try {
    foreach ($v in (Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' })) {
        $pctFree = if ($v.Size -gt 0) { [math]::Round(($v.SizeRemaining / $v.Size) * 100, 1) } else { 0 }
        Write-Log ""
        Write-Log ("  Drive {0}:  [{1}]  {2}" -f $v.DriveLetter, $v.FileSystem, $v.FileSystemLabel)
        Write-Log ("    Size / Free : {0:N1} GB / {1:N1} GB ({2}% free)" -f ($v.Size/1GB), ($v.SizeRemaining/1GB), $pctFree)
        Write-Log ("    Health      : {0}" -f $v.HealthStatus)

        if ($pctFree -lt 10) { Add-Issue   ("Drive $($v.DriveLetter): only $pctFree% free - low disk space slows Windows badly. Clean up.") }
        elseif ($pctFree -lt 20) { Add-Warning ("Drive $($v.DriveLetter): $pctFree% free - getting low.") }
        else { Write-Pass ("Drive $($v.DriveLetter): space OK ($pctFree% free)") }

        $dirty = (fsutil dirty query "$($v.DriveLetter):" 2>&1) | Out-String
        Write-Log ("    Dirty flag  : {0}" -f $dirty.Trim())
        if ($dirty -match 'is Dirty|is dirty') {
            Add-Warning ("Drive $($v.DriveLetter): volume is flagged DIRTY - run 'chkdsk $($v.DriveLetter): /F' at next reboot.")
        }
    }
} catch { Write-Log "  ERROR reading volumes: $_" 'Red' }

# ------------------------------------------------- 7. Online CHKDSK scan (C:)
Write-Section '7. CHKDSK ONLINE SCAN (C:) - read-only, no repairs'
try {
    Write-Log "  Running: chkdsk C: /scan  (takes 1-3 minutes, PC stays usable)..."
    $chk = chkdsk C: /scan 2>&1 | Out-String
    Write-Log $chk
    if ($chk -match 'found no problems|No further action is required') {
        Write-Pass 'CHKDSK found no file system problems on C:'
    } elseif ($chk -match 'found problems|errors detected|corrupt') {
        Add-Issue 'CHKDSK found file system problems on C: - schedule "chkdsk C: /F" (fix run) at reboot.'
    } else {
        Add-Warning 'CHKDSK output was inconclusive - review Section 7 of the report manually.'
    }
} catch { Write-Log "  ERROR running chkdsk: $_" 'Red' }

# ----------------------------------- 8. Corrupted / unhealthy Windows files
Write-Section '8. CORRUPTED WINDOWS SYSTEM FILES (SFC verify + DISM check)'
if ($SkipSystemFileCheck) {
    Write-Log '  Skipped (-SkipSystemFileCheck was used).'
} else {
    try {
        Write-Log '  Running: DISM /Online /Cleanup-Image /ScanHealth  (2-5 min)...'
        $dism = DISM /Online /Cleanup-Image /ScanHealth 2>&1 | Out-String
        $dismLine = (($dism -split "`r?`n") | Where-Object { $_ -match 'component store|No component|repairable|corrupt' }) -join '; '
        Write-Log ("  DISM result: {0}" -f $(if ($dismLine) { $dismLine.Trim() } else { 'see below' }))
        if ($dism -match 'No component store corruption detected') {
            Write-Pass 'Windows component store is healthy (DISM).'
        } elseif ($dism -match 'repairable|corrupt') {
            Add-Issue 'DISM found Windows image corruption - run "DISM /Online /Cleanup-Image /RestoreHealth" then "sfc /scannow".'
        } else {
            Write-Log $dism
        }

        Write-Log ''
        Write-Log '  Running: sfc /verifyonly  (verifies system files WITHOUT repairing, 5-10 min)...'
        $sfc = sfc /verifyonly 2>&1 | Out-String
        # sfc output is often UTF-16 with interleaved nulls when captured - strip them
        $sfc = $sfc -replace "`0", ''
        $sfcLine = (($sfc -split "`r?`n") | Where-Object { $_ -match 'did not find|found integrity|unable to perform' } | Select-Object -First 1)
        Write-Log ("  SFC result: {0}" -f $(if ($sfcLine) { $sfcLine.Trim() } else { 'see report' }))
        if ($sfc -match 'did not find any integrity violations') {
            Write-Pass 'No corrupted Windows system files (SFC).'
        } elseif ($sfc -match 'found integrity violations') {
            Add-Issue 'SFC found corrupted system files - run "sfc /scannow" (as admin) to repair them.'
        } else {
            Add-Warning 'SFC verification was inconclusive - review Section 8 manually.'
        }
    } catch { Write-Log "  ERROR during system file check: $_" 'Red' }
}

# -------------------------------------------- 9. Disk errors in the Event Log
Write-Section '9. DISK-RELATED ERRORS IN EVENT LOG (last 14 days)'
try {
    $since  = (Get-Date).AddDays(-14)
    $events = Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2,3; StartTime=$since } -ErrorAction SilentlyContinue |
              Where-Object { $_.ProviderName -match 'disk|Ntfs|volmgr|storahci|stornvme|iaStor|partmgr' } |
              Select-Object -First 40
    if ($events) {
        foreach ($g in ($events | Group-Object ProviderName, Id | Sort-Object Count -Descending)) {
            $sample = $g.Group[0]
            Write-Log ("  {0,3}x  [{1}] Event {2}: {3}" -f $g.Count, $sample.ProviderName, $sample.Id,
                       (($sample.Message -split "`n")[0]).Trim())
        }
        $badCount = ($events | Where-Object { $_.Level -le 2 }).Count
        if ($badCount -gt 0) {
            Add-Warning "$badCount disk-related ERROR events in the last 14 days - bad blocks/cabling/controller possible. See Section 9."
        }
    } else {
        Write-Pass 'No disk-related errors or warnings in the System event log (last 14 days).'
    }
} catch { Write-Log "  ERROR querying event log: $_" 'Red' }

# ---------------------------------------------------- 10. Disk speed (WinSAT)
Write-Section '10. DISK SPEED TEST (WinSAT)'
if ($SkipSpeedTest) {
    Write-Log '  Skipped (-SkipSpeedTest was used).'
} else {
    try {
        Write-Log '  Running WinSAT disk test on the system drive (1-2 min)...'
        $ws = winsat disk -drive ((Get-CimInstance Win32_OperatingSystem).SystemDrive.TrimEnd(':')) 2>&1 | Out-String
        $resultLines = ($ws -split "`r?`n") | Where-Object { $_ -match 'Disk\s+(Sequential|Random)|Avg\.|assessment' }
        if ($resultLines) { $resultLines | ForEach-Object { Write-Log ("  " + $_.Trim()) } } else { Write-Log $ws }

        $seq = [regex]::Match($ws, 'Sequential 64\.0 Read\s+([\d\.]+)\s*MB/s')
        if ($seq.Success) {
            $mbps = [double]$seq.Groups[1].Value
            if     ($mbps -lt 80)  { Add-Issue   ("Sequential read only {0} MB/s - very slow (failing HDD, SATA cable, or wrong mode)." -f $mbps) }
            elseif ($mbps -lt 150) { Add-Upgrade ("Sequential read {0} MB/s - typical of an aging HDD; an SSD upgrade would transform this PC." -f $mbps) }
            else                   { Write-Pass  ("Sequential read {0} MB/s - acceptable." -f $mbps) }
        }
    } catch { Write-Log "  ERROR running WinSAT: $_" 'Red' }
}

# --------------------------------------------- 11. Virus / security check
Write-Section '11. VIRUS / SECURITY CHECK (Windows Defender)'
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Write-Log ("  Antivirus Enabled        : {0}" -f $mp.AntivirusEnabled)
    Write-Log ("  Real-Time Protection     : {0}" -f $mp.RealTimeProtectionEnabled)
    Write-Log ("  Definitions Last Updated : {0}  (age: {1} days)" -f $mp.AntivirusSignatureLastUpdated, $mp.AntivirusSignatureAge)
    Write-Log ("  Last Quick Scan          : {0}" -f $mp.QuickScanEndTime)
    Write-Log ("  Last Full Scan           : {0}" -f $mp.FullScanEndTime)

    if (-not $mp.AntivirusEnabled)          { Add-Issue 'Windows Defender antivirus is DISABLED - machine is unprotected.' }
    if (-not $mp.RealTimeProtectionEnabled) { Add-Issue 'Real-time protection is OFF - turn it on in Windows Security.' }
    if ($mp.AntivirusSignatureAge -gt 7)    { Add-Warning "Virus definitions are $($mp.AntivirusSignatureAge) days old - run Windows Update." }

    # --- Threat history (last 30 days) ---
    Write-Log ''
    Write-Log '  Threat detection history (last 30 days):'
    $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue |
               Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-30) }
    if ($threats) {
        foreach ($t in $threats) {
            $info = Get-MpThreat -ThreatID $t.ThreatID -ErrorAction SilentlyContinue
            Write-Log ("    [{0}] {1}" -f $t.InitialDetectionTime, $info.ThreatName)
            foreach ($res in ($t.Resources | Select-Object -First 5)) { Write-Log ("        File: {0}" -f $res) }
        }
        Add-Warning ("{0} malware detection(s) in the last 30 days - see Section 11 for the infected files." -f @($threats).Count)
    } else {
        Write-Pass 'No malware detections recorded in the last 30 days.'
    }

    # --- Quick scan now ---
    if ($SkipVirusScan) {
        Write-Log ''
        Write-Log '  Quick scan skipped (-SkipVirusScan was used).'
    } else {
        Write-Log ''
        Write-Log '  Running Windows Defender QUICK SCAN now (5-15 min, PC stays usable)...'
        Start-MpScan -ScanType QuickScan -ErrorAction Stop
        Write-Log '  Quick scan finished.'
        $active = Get-MpThreat -ErrorAction SilentlyContinue | Where-Object { $_.IsActive }
        if ($active) {
            foreach ($t in $active) {
                Add-Issue ("ACTIVE THREAT FOUND: {0} (severity {1})" -f $t.ThreatName, $t.SeverityID)
                foreach ($res in ($t.Resources | Select-Object -First 5)) { Write-Log ("        File: {0}" -f $res) 'Red' }
            }
            Add-Issue 'Run a FULL scan from Windows Security and quarantine/remove the threats above.'
        } else {
            Write-Pass 'Quick scan completed - no active threats found.'
        }
    }
} catch {
    Write-Log '  Windows Defender not available - checking for third-party antivirus...'
    try {
        $avList = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
        if ($avList) {
            foreach ($av in $avList) {
                # productState bit 0x1000 = enabled, 0x10 = definitions out of date
                $enabled  = ($av.productState -band 0x1000) -ne 0
                $outdated = ($av.productState -band 0x10) -ne 0
                Write-Log ("  AV Product: {0}  Enabled: {1}  Definitions outdated: {2}" -f $av.displayName, $enabled, $outdated)
                if (-not $enabled) { Add-Issue ("Antivirus '{0}' is installed but DISABLED." -f $av.displayName) }
                if ($outdated)     { Add-Warning ("Antivirus '{0}' definitions are out of date." -f $av.displayName) }
            }
        } else {
            Add-Issue 'NO antivirus product detected on this machine.'
        }
    } catch { Add-Warning 'Could not determine antivirus status on this machine.' }
}

# ------------------------------------------------------- 12. Printer status
Write-Section '12. PRINTER STATUS'
try {
    # Print Spooler service must be running for any printing at all
    $spooler = Get-Service -Name Spooler -ErrorAction Stop
    Write-Log ("  Print Spooler service : {0}" -f $spooler.Status)
    if ($spooler.Status -ne 'Running') {
        Add-Issue 'Print Spooler service is NOT running - no printer will work. Start it (services.msc) or reboot.'
    }

    $printers = Get-Printer -ErrorAction Stop
    $wmiPrinters = Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue
    if (-not $printers) {
        Write-Log '  No printers installed on this machine.'
    } else {
        $defaultName = ($wmiPrinters | Where-Object Default | Select-Object -First 1).Name
        Write-Log ("  Installed printers: {0}   Default: {1}" -f @($printers).Count, $(if ($defaultName) { $defaultName } else { 'none set' }))
        if (-not $defaultName) { Add-Warning 'No default printer is set.' }

        foreach ($p in $printers) {
            Write-Log ''
            $isDefault = if ($p.Name -eq $defaultName) { '  (DEFAULT)' } else { '' }
            Write-Log ("  Printer: {0}{1}" -f $p.Name, $isDefault)
            Write-Log ("    Driver : {0}" -f $p.DriverName)
            Write-Log ("    Port   : {0}" -f $p.PortName)
            Write-Log ("    Status : {0}" -f $p.PrinterStatus)

            $wmi = $wmiPrinters | Where-Object { $_.Name -eq $p.Name }
            $offline = $wmi -and $wmi.WorkOffline
            if ($offline) { Write-Log '    Offline: Yes (Windows has it in "Use Printer Offline" mode)' }

            # Skip virtual printers (PDF/XPS/OneNote/Fax) when raising flags
            $isVirtual = $p.Name -match 'PDF|XPS|OneNote|Fax|Print to'
            if (-not $isVirtual) {
                if ($offline -or $p.PrinterStatus -eq 'Offline') {
                    Add-Issue ("Printer '{0}' is OFFLINE - check power/cable/network, then untick 'Use Printer Offline'." -f $p.Name)
                } elseif ($p.PrinterStatus -match 'Error|PaperJam|PaperOut|TonerLow|DoorOpen|NotAvailable') {
                    Add-Issue ("Printer '{0}' reports status '{1}' - check the device." -f $p.Name, $p.PrinterStatus)
                } elseif ($p.PrinterStatus -eq 'Normal') {
                    Write-Pass ("Printer '{0}' status Normal" -f $p.Name)
                }
            }

            # Stuck / failed jobs in the queue
            try {
                $jobs = Get-PrintJob -PrinterName $p.Name -ErrorAction Stop
                if ($jobs) {
                    Write-Log ("    Jobs in queue: {0}" -f @($jobs).Count)
                    foreach ($j in $jobs) {
                        Write-Log ("      [{0}] '{1}' by {2}  status: {3}" -f $j.SubmittedTime, $j.DocumentName, $j.UserName, $j.JobStatus)
                    }
                    $stuck = $jobs | Where-Object { $_.JobStatus -match 'Error|Blocked' -or $_.SubmittedTime -lt (Get-Date).AddHours(-24) }
                    if ($stuck) {
                        Add-Warning ("Printer '{0}' has {1} stuck/failed job(s) in the queue - clear the queue (or restart the Print Spooler)." -f $p.Name, @($stuck).Count)
                    }
                }
            } catch { }

            # Network printer reachability: ping the port's host address
            try {
                $port = Get-PrinterPort -Name $p.PortName -ErrorAction Stop
                $hostAddr = $port.PrinterHostAddress
                if ($hostAddr) {
                    $reachable = Test-Connection -ComputerName $hostAddr -Count 2 -Quiet -ErrorAction SilentlyContinue
                    Write-Log ("    Network address: {0}  Ping: {1}" -f $hostAddr, $(if ($reachable) { 'OK' } else { 'FAILED' }))
                    if (-not $reachable) {
                        Add-Issue ("Network printer '{0}' at {1} does NOT respond to ping - printer off, disconnected, or IP changed." -f $p.Name, $hostAddr)
                    }
                }
            } catch { }
        }
    }
} catch { Write-Log "  ERROR checking printers: $_" 'Red' }

# -------------------------------------------- 13. Network connection status
Write-Section '13. NETWORK CONNECTION STATUS'
try {
    # --- Adapters ---
    Write-Log '  Network adapters:'
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
    $upAdapters = @($adapters | Where-Object Status -eq 'Up')
    foreach ($a in $adapters) {
        Write-Log ("    {0,-28} Status: {1,-12} Speed: {2}" -f $a.Name, $a.Status, $a.LinkSpeed)
    }
    if (-not $upAdapters) {
        Add-Issue 'NO network adapter is connected - check the network cable / Wi-Fi.'
    }

    # --- IP configuration for connected adapters ---
    Write-Log ''
    Write-Log '  IP configuration:'
    $gateway = $null
    foreach ($cfg in (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.NetAdapter.Status -eq 'Up' })) {
        $ip  = ($cfg.IPv4Address | Select-Object -First 1).IPAddress
        $gw  = ($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop
        $dns = ($cfg.DNSServer | Where-Object AddressFamily -eq 2 | Select-Object -ExpandProperty ServerAddresses) -join ', '
        Write-Log ("    {0}: IP {1}  Gateway {2}  DNS {3}" -f $cfg.InterfaceAlias, $ip, $gw, $dns)
        if (-not $gateway -and $gw) { $gateway = $gw }
        if ($ip -like '169.254.*') {
            Add-Issue ("Adapter '{0}' has a 169.254.x.x address - it is NOT getting an IP from the router/DHCP." -f $cfg.InterfaceAlias)
        }
    }
    if ($upAdapters -and -not $gateway) {
        Add-Issue 'Connected to the network but NO default gateway - check router/DHCP settings.'
    }

    # --- Connectivity tests ---
    Write-Log ''
    Write-Log '  Connectivity tests:'
    if ($gateway) {
        $gwOk = Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue
        Write-Log ("    Ping gateway ({0})      : {1}" -f $gateway, $(if ($gwOk) { 'OK' } else { 'FAILED' }))
        if (-not $gwOk) { Add-Issue "Cannot reach the gateway/router ($gateway) - local network problem (cable, switch, router)." }
    }
    $inetOk = Test-Connection -ComputerName 8.8.8.8 -Count 2 -Quiet -ErrorAction SilentlyContinue
    Write-Log ("    Ping internet (8.8.8.8)   : {0}" -f $(if ($inetOk) { 'OK' } else { 'FAILED' }))
    $dnsOk = $false
    try { $null = [System.Net.Dns]::GetHostAddresses('www.microsoft.com'); $dnsOk = $true } catch { }
    Write-Log ("    DNS lookup (microsoft.com): {0}" -f $(if ($dnsOk) { 'OK' } else { 'FAILED' }))

    if ($upAdapters) {
        if (-not $inetOk) {
            Add-Issue 'No internet connection (ping to 8.8.8.8 failed) - problem is at the router/ISP side if the gateway pings OK.'
        } elseif (-not $dnsOk) {
            Add-Issue 'Internet works but DNS FAILS - websites will not load by name. Fix DNS server settings (try 8.8.8.8).'
        } else {
            Write-Pass 'Network OK: gateway, internet and DNS all respond.'
        }
    }
} catch { Write-Log "  ERROR checking network: $_" 'Red' }

# ---------------------------------------------- 14. CPU / RAM / top processes
Write-Section '14. SYSTEM PERFORMANCE SNAPSHOT'
try {
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $os      = Get-CimInstance Win32_OperatingSystem
    $ramUsedPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)

    Write-Log ("  CPU Load        : {0}%" -f $cpuLoad)
    Write-Log ("  RAM In Use      : {0}%  ({1:N1} GB free of {2:N1} GB)" -f $ramUsedPct,
               ($os.FreePhysicalMemory/1MB), ($os.TotalVisibleMemorySize/1MB))

    if ($cpuLoad -ge 85)    { Add-Warning "CPU at $cpuLoad% during the test - check top processes below." }
    if ($ramUsedPct -ge 90) { Add-Issue   "RAM at $ramUsedPct% - machine is memory-starved (close apps or add RAM)." }
    elseif ($ramUsedPct -ge 80) { Add-Warning "RAM at $ramUsedPct% - on the high side." }

    try {
        $samples = Get-Counter -Counter '\PhysicalDisk(_Total)\% Disk Time','\PhysicalDisk(_Total)\Avg. Disk Queue Length' -SampleInterval 1 -MaxSamples 5 -ErrorAction Stop
        $diskTime  = [math]::Round(($samples.CounterSamples | Where-Object Path -match 'disk time'    | Measure-Object CookedValue -Average).Average, 1)
        $diskQueue = [math]::Round(($samples.CounterSamples | Where-Object Path -match 'queue length' | Measure-Object CookedValue -Average).Average, 2)
        Write-Log ("  Disk Busy (avg) : {0}%   Avg Queue Length: {1}" -f $diskTime, $diskQueue)
        if ($diskQueue -gt 2) { Add-Warning "Disk queue length $diskQueue (sustained >2 = disk is the bottleneck)." }
    } catch { Write-Log '  (Disk performance counters unavailable)' }

    Write-Log ''
    Write-Log '  Top 10 processes by CPU time:'
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 |
        ForEach-Object { Write-Log ("    {0,-30} CPU(s): {1,10:N1}   RAM: {2,8:N0} MB" -f $_.ProcessName, $_.CPU, ($_.WorkingSet64/1MB)) }

    Write-Log ''
    Write-Log '  Top 10 processes by RAM:'
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 |
        ForEach-Object { Write-Log ("    {0,-30} RAM: {1,8:N0} MB" -f $_.ProcessName, ($_.WorkingSet64/1MB)) }
} catch { Write-Log "  ERROR collecting performance data: $_" 'Red' }

# ------------------------------------------------------------------ Summary
Write-Section 'SUMMARY'
Write-Log ("  Completed: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Log ''
if ($script:Issues.Count -eq 0 -and $script:Warnings.Count -eq 0) {
    Write-Log '  OVERALL RESULT: PASS - no disk, virus, printer, network or performance problems detected.' 'Green'
} else {
    if ($script:Issues.Count -gt 0) {
        Write-Log ("  CRITICAL ISSUES ({0}):" -f $script:Issues.Count) 'Red'
        $i = 1; foreach ($x in $script:Issues)   { Write-Log ("    {0}. {1}" -f $i++, $x) 'Red' }
        Write-Log ''
    }
    if ($script:Warnings.Count -gt 0) {
        Write-Log ("  WARNINGS ({0}):" -f $script:Warnings.Count) 'Yellow'
        $i = 1; foreach ($x in $script:Warnings) { Write-Log ("    {0}. {1}" -f $i++, $x) 'Yellow' }
        Write-Log ''
    }
    $overall = if ($script:Issues.Count -gt 0) { 'FAIL - action required (see critical issues above)' } else { 'PASS WITH WARNINGS' }
    Write-Log ("  OVERALL RESULT: {0}" -f $overall) $(if ($script:Issues.Count -gt 0) { 'Red' } else { 'Yellow' })
}
if ($script:Upgrades.Count -gt 0) {
    Write-Log ''
    Write-Log ("  RECOMMENDED IMPROVEMENTS ({0}):" -f $script:Upgrades.Count) 'Magenta'
    $i = 1; foreach ($x in $script:Upgrades) { Write-Log ("    {0}. {1}" -f $i++, $x) 'Magenta' }
}
Write-Log ''
Write-Log "  Report saved on the Desktop: $LogFile"

# Backup copy in C:\DiskHealthLogs
try {
    Copy-Item -Path $LogFile -Destination (Join-Path $BackupDir $ReportName) -Force
    Write-Log "  Backup copy               : $(Join-Path $BackupDir $ReportName)"
} catch { Write-Log "  (Could not write backup copy to $BackupDir)" 'Yellow' }

Write-Host ''
Write-Host "Done. Report saved on the Desktop: $LogFile" -ForegroundColor Cyan
Write-Host 'Press any key to close...'
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
