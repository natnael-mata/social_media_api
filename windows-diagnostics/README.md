# Dell Desktop — Disk Health & Performance Diagnostic

A self-contained, read-only diagnostic for Windows 10/11 Dell desktops. It
checks hard disk health and system performance, then writes a full report to
`C:\DiskHealthLogs\` so logs can be collected from each machine and fixes
planned from the findings.

## How to run (per desktop)

1. Copy the whole `windows-diagnostics` folder to the PC (USB stick, network
   share, or download).
2. **Double-click `RUN-DISK-CHECK.bat`.**
3. Click **Yes** on the admin (UAC) prompt.
4. Wait 3–6 minutes. The window shows live results; when it finishes it prints
   the log path and waits for a key press.
5. Collect the log file from `C:\DiskHealthLogs\DiskHealth_<PCNAME>_<date>.log`.

No installation, no internet, no changes to the machine — the script only
reads and reports (the CHKDSK step runs in `/scan` mode, which does not repair).

To skip the 1–2 minute disk speed test, run instead:

```powershell
powershell -ExecutionPolicy Bypass -File .\DiskHealthCheck.ps1 -SkipSpeedTest
```

## What it checks

| Section | Check | Flags raised |
|---|---|---|
| 1 | Dell model, Service Tag, BIOS, OS, uptime | Uptime over 14 days |
| 2 | Physical disk health, temperature, SSD wear, uncorrected errors | Unhealthy disk, hot disk, worn SSD, media errors |
| 3 | SMART firmware failure-prediction flag | Drive predicting its own failure |
| 4 | Volume free space and the NTFS dirty flag | <10% free (critical), <20% (warning), dirty volume |
| 5 | `chkdsk C: /scan` (online, read-only) | File system corruption |
| 6 | Disk/NTFS/controller errors in the System event log (14 days) | Repeated disk error events |
| 7 | WinSAT disk speed test | Sequential read <80 MB/s (failing/slow drive) |
| 8 | CPU load, RAM usage, disk queue length, top processes | CPU ≥85%, RAM ≥90%, disk queue >2 |

## Reading the results

Every log ends with a **SUMMARY** section:

- **PASS** — nothing found.
- **PASS WITH WARNINGS** — numbered warnings worth monitoring or cleaning up.
- **FAIL** — numbered critical issues; typical actions:
  - *HealthStatus not Healthy / SMART predicts failure / uncorrected errors* →
    back up immediately and replace the drive (check warranty with the Service
    Tag in section 1 at support.dell.com).
  - *CHKDSK found problems or dirty volume* → schedule `chkdsk <drive>: /F` at
    reboot.
  - *Low free space* → disk cleanup / move data.
  - *Slow HDD speeds* → SSD upgrade is usually the biggest single improvement.

Send the collected logs back and we can decide the fixes machine by machine.
