<#
.SYNOPSIS
    Dell Desktop - Hard Disk Health & System Performance Diagnostic
.DESCRIPTION
    Checks disk health (SMART, reliability counters, dirty volumes, disk errors
    in the event log), runs an online CHKDSK scan, measures disk speed, and
    captures system performance (CPU, RAM, top processes). Everything is written
    to a timestamped log file in C:\DiskHealthLogs so results can be collected
    from each machine and reviewed later.
.NOTES
    - Works on Windows 10/11 with built-in PowerShell 5.1 (no modules needed).
    - Must run as Administrator (it self-elevates if launched normally).
    - Read-only: it does NOT repair anything, so it is safe to run on any PC.
.PARAMETER SkipSpeedTest
    Skip the WinSAT disk speed test (saves ~1-2 minutes per machine).
#>

[CmdletBinding()]
param(
    [switch]$SkipSpeedTest
)

# ------------------------------------------------------------------ elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator - relaunching elevated..." -ForegroundColor Yellow
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($SkipSpeedTest) { $argLine += " -SkipSpeedTest" }
    Start-Process powershell.exe -ArgumentList $argLine -Verb RunAs
    exit
}

# ------------------------------------------------------------------- logging
$LogDir  = 'C:\DiskHealthLogs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$Stamp   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$LogFile = Join-Path $LogDir "DiskHealth_$($env:COMPUTERNAME)_$Stamp.log"

# Issues collected along the way; summarized at the end of the log.
$script:Issues   = New-Object System.Collections.Generic.List[string]
$script:Warnings = New-Object System.Collections.Generic.List[string]

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
function Write-Pass  { param([string]$Text) Write-Log ("  [PASS] " + $Text) 'Green' }

Write-Log ('#' * 70)
Write-Log "#  DELL DESKTOP - DISK HEALTH & PERFORMANCE DIAGNOSTIC"
Write-Log "#  Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "#  Computer: $env:COMPUTERNAME   User: $env:USERNAME"
Write-Log "#  Log file: $LogFile"
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
    Write-Log ("  OS           : {0}  (Build {1})" -f $os.Caption, $os.BuildNumber)
    Write-Log ("  Total RAM    : {0:N1} GB" -f ($cs.TotalPhysicalMemory / 1GB))
    Write-Log ("  Last Boot    : {0}" -f $os.LastBootUpTime)
    $uptime = (Get-Date) - $os.LastBootUpTime
    Write-Log ("  Uptime       : {0} days {1} hours" -f $uptime.Days, $uptime.Hours)
    if ($uptime.Days -ge 14) { Add-Warning "PC has not rebooted in $($uptime.Days) days - reboot before judging performance." }
} catch { Write-Log "  ERROR collecting system info: $_" 'Red' }

# ------------------------------------------------------- 2. Physical disks
Write-Section '2. PHYSICAL DISK HEALTH (SMART / Storage Spaces view)'
try {
    $disks = Get-PhysicalDisk
    foreach ($d in $disks) {
        Write-Log ""
        Write-Log ("  Disk #{0}: {1}" -f $d.DeviceId, $d.FriendlyName)
        Write-Log ("    Media Type        : {0}" -f $d.MediaType)
        Write-Log ("    Bus Type          : {0}" -f $d.BusType)
        Write-Log ("    Size              : {0:N1} GB" -f ($d.Size / 1GB))
        Write-Log ("    Health Status     : {0}" -f $d.HealthStatus)
        Write-Log ("    Operational Status: {0}" -f ($d.OperationalStatus -join ', '))

        if ($d.HealthStatus -ne 'Healthy') {
            Add-Issue ("Disk #{0} ({1}) HealthStatus = {2} - BACK UP DATA, disk may be failing." -f $d.DeviceId, $d.FriendlyName, $d.HealthStatus)
        } else {
            Write-Pass ("Disk #{0} reports Healthy" -f $d.DeviceId)
        }

        # Reliability counters (temperature, wear, read/write errors)
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
        } catch {
            Write-Log "    (Reliability counters not available for this disk)"
        }
    }
} catch { Write-Log "  ERROR reading physical disks: $_" 'Red' }

# -------------------------------------------- 3. SMART predict-failure flag
Write-Section '3. SMART FAILURE PREDICTION (firmware flag)'
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
    Write-Log "  (SMART WMI data not exposed on this controller - rely on Section 2 results)"
}

# --------------------------------------------------------- 4. Volumes / space
Write-Section '4. VOLUMES - FREE SPACE & DIRTY FLAG'
try {
    $vols = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
    foreach ($v in $vols) {
        $pctFree = if ($v.Size -gt 0) { [math]::Round(($v.SizeRemaining / $v.Size) * 100, 1) } else { 0 }
        Write-Log ""
        Write-Log ("  Drive {0}:  [{1}]  {2}" -f $v.DriveLetter, $v.FileSystem, $v.FileSystemLabel)
        Write-Log ("    Size / Free : {0:N1} GB / {1:N1} GB ({2}% free)" -f ($v.Size/1GB), ($v.SizeRemaining/1GB), $pctFree)
        Write-Log ("    Health      : {0}" -f $v.HealthStatus)

        if ($pctFree -lt 10) { Add-Issue   ("Drive $($v.DriveLetter): only $pctFree% free - low disk space slows Windows badly. Clean up.") }
        elseif ($pctFree -lt 20) { Add-Warning ("Drive $($v.DriveLetter): $pctFree% free - getting low.") }
        else { Write-Pass ("Drive $($v.DriveLetter): space OK ($pctFree% free)") }

        # Dirty bit = filesystem flagged for repair
        $dirty = (fsutil dirty query "$($v.DriveLetter):" 2>&1) | Out-String
        Write-Log ("    Dirty flag  : {0}" -f $dirty.Trim())
        if ($dirty -match 'is Dirty|is dirty') {
            Add-Warning ("Drive $($v.DriveLetter): volume is flagged DIRTY - run 'chkdsk $($v.DriveLetter): /F' at next reboot.")
        }
    }
} catch { Write-Log "  ERROR reading volumes: $_" 'Red' }

# ------------------------------------------------- 5. Online CHKDSK scan (C:)
Write-Section '5. CHKDSK ONLINE SCAN (C:) - read-only, no repairs'
try {
    Write-Log "  Running: chkdsk C: /scan  (takes 1-3 minutes, PC stays usable)..."
    $chk = chkdsk C: /scan 2>&1 | Out-String
    Write-Log $chk
    if ($chk -match 'found no problems|No further action is required') {
        Write-Pass 'CHKDSK found no file system problems on C:'
    } elseif ($chk -match 'found problems|errors detected|corrupt') {
        Add-Issue 'CHKDSK found file system problems on C: - schedule "chkdsk C: /F" (fix run) at reboot.'
    } else {
        Add-Warning 'CHKDSK output was inconclusive - review Section 5 of the log manually.'
    }
} catch { Write-Log "  ERROR running chkdsk: $_" 'Red' }

# -------------------------------------------- 6. Disk errors in the Event Log
Write-Section '6. DISK-RELATED ERRORS IN EVENT LOG (last 14 days)'
try {
    $since  = (Get-Date).AddDays(-14)
    $events = Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2,3; StartTime=$since } -ErrorAction SilentlyContinue |
              Where-Object { $_.ProviderName -match 'disk|Ntfs|volmgr|storahci|stornvme|iaStor|partmgr' } |
              Select-Object -First 40
    if ($events) {
        $grouped = $events | Group-Object ProviderName, Id | Sort-Object Count -Descending
        foreach ($g in $grouped) {
            $sample = $g.Group[0]
            Write-Log ("  {0,3}x  [{1}] Event {2}: {3}" -f $g.Count, $sample.ProviderName, $sample.Id,
                       (($sample.Message -split "`n")[0]).Trim())
        }
        $badCount = ($events | Where-Object { $_.Level -le 2 }).Count
        if ($badCount -gt 0) {
            Add-Warning "$badCount disk-related ERROR events in the last 14 days - bad blocks/cabling/controller possible. See Section 6."
        }
    } else {
        Write-Pass 'No disk-related errors or warnings in the System event log (last 14 days).'
    }
} catch { Write-Log "  ERROR querying event log: $_" 'Red' }

# ---------------------------------------------------- 7. Disk speed (WinSAT)
Write-Section '7. DISK SPEED TEST (WinSAT)'
if ($SkipSpeedTest) {
    Write-Log '  Skipped (-SkipSpeedTest was used).'
} else {
    try {
        Write-Log '  Running WinSAT sequential + random read on the system drive (1-2 min)...'
        $ws = winsat disk -drive ((Get-CimInstance Win32_OperatingSystem).SystemDrive.TrimEnd(':')) 2>&1 | Out-String
        # Keep only the useful result lines in the log
        $resultLines = ($ws -split "`r?`n") | Where-Object { $_ -match 'Disk\s+(Sequential|Random)|Avg\.|assessment' }
        if ($resultLines) { $resultLines | ForEach-Object { Write-Log ("  " + $_.Trim()) } } else { Write-Log $ws }

        $seq = [regex]::Match($ws, 'Sequential 64\.0 Read\s+([\d\.]+)\s*MB/s')
        if ($seq.Success) {
            $mbps = [double]$seq.Groups[1].Value
            if     ($mbps -lt 80)  { Add-Issue   ("Sequential read only {0} MB/s - very slow (failing HDD, SATA cable, or wrong mode)." -f $mbps) }
            elseif ($mbps -lt 150) { Add-Warning ("Sequential read {0} MB/s - typical of an aging HDD; an SSD upgrade would transform this PC." -f $mbps) }
            else                   { Write-Pass  ("Sequential read {0} MB/s - acceptable." -f $mbps) }
        }
    } catch { Write-Log "  ERROR running WinSAT: $_" 'Red' }
}

# ------------------------------------------------ 8. CPU / RAM / top processes
Write-Section '8. SYSTEM PERFORMANCE SNAPSHOT'
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

    # Disk busy / queue - sample performance counters for 5 seconds
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
    Write-Log '  OVERALL RESULT: PASS - no disk health or performance problems detected.' 'Green'
} else {
    if ($script:Issues.Count -gt 0) {
        Write-Log ("  CRITICAL ISSUES ({0}):" -f $script:Issues.Count) 'Red'
        $i = 1; foreach ($x in $script:Issues)   { Write-Log ("    {0}. {1}" -f $i++, $x) 'Red' }
        Write-Log ''
    }
    if ($script:Warnings.Count -gt 0) {
        Write-Log ("  WARNINGS ({0}):" -f $script:Warnings.Count) 'Yellow'
        $i = 1; foreach ($x in $script:Warnings) { Write-Log ("    {0}. {1}" -f $i++, $x) 'Yellow' }
    }
    Write-Log ''
    $overall = if ($script:Issues.Count -gt 0) { 'FAIL - action required (see critical issues above)' } else { 'PASS WITH WARNINGS' }
    Write-Log ("  OVERALL RESULT: {0}" -f $overall) $(if ($script:Issues.Count -gt 0) { 'Red' } else { 'Yellow' })
}
Write-Log ''
Write-Log "  Full log saved to: $LogFile"
Write-Log '  Collect this file from each desktop for review.'

Write-Host ''
Write-Host "Done. Log saved to: $LogFile" -ForegroundColor Cyan
Write-Host 'Press any key to close...'
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
