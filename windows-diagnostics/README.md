# Dell Desktop — Full Health Check (Specs + Disk + Virus + Performance)

A self-contained diagnostic for Windows 10/11 Dell desktops. It records the
full desktop specification, checks hard disk health, corrupted system files,
viruses (Windows Defender), and system performance, then **saves the full
report as a .txt file on the Desktop** (with a backup copy in
`C:\DiskHealthLogs\`). Collect the report from each machine to decide what
software it can run and what should be improved.

## Files

| File | Purpose |
|---|---|
| `RUN-DISK-CHECK.bat` | Double-click this to run everything |
| `DiskHealthCheck.ps1` | The actual diagnostic script |

## How to run (per desktop)

1. Copy **both files** into the same folder on the PC (USB stick is fine).
2. **Double-click `RUN-DISK-CHECK.bat`.**
3. Click **Yes** on the admin (UAC) prompt.
4. Wait **15–30 minutes** (the virus quick scan and system file check take the
   longest; the PC stays usable).
5. When finished, the report appears **on the Desktop** as
   `PC-Health-Report_<PCNAME>_<date>.txt` — collect that file.

Faster run (skip the slow parts — virus scan, system file check, speed test):

```powershell
powershell -ExecutionPolicy Bypass -File .\DiskHealthCheck.ps1 -SkipVirusScan -SkipSystemFileCheck -SkipSpeedTest
```

## What the report contains

| Section | Check | Used for |
|---|---|---|
| 1 | Dell model, Service Tag, BIOS, OS, uptime | Warranty lookup, Windows 10 end-of-life flag |
| 2 | **Full spec**: CPU cores/speed, RAM size + modules + free slots, GPU, motherboard, drive types (SSD/HDD), network | Deciding what software the PC can run and what to upgrade |
| 3 | Installed software list | Reviewing what currently runs on the PC |
| 4 | Physical disk health, temperature, SSD wear, uncorrected errors | Failing drives |
| 5 | SMART firmware failure-prediction flag | Drives predicting their own death |
| 6 | Volume free space + NTFS dirty flag | Low space, pending repairs |
| 7 | `chkdsk C: /scan` (online, read-only) | File system corruption |
| 8 | **Unhealthy Windows files**: `sfc /verifyonly` + `DISM /ScanHealth` | Corrupted system files |
| 9 | Disk/NTFS/controller errors in the event log (14 days) | Hardware trouble signs |
| 10 | WinSAT disk speed test | Slow/failing drives, SSD upgrade case |
| 11 | **Virus check**: Defender status, definition age, 30-day threat history, **quick scan** (lists infected files) | Malware on the machine |
| 12 | **Printers**: spooler service, every printer's status (offline/error), stuck print jobs, ping test for network printers | Printers that won't print |
| 13 | **Network**: adapter status/speed, IP/gateway/DNS config, ping gateway, ping internet, DNS lookup | No-internet and local network problems |
| 14 | **Windows Update**: last installed update, pending updates, pending reboot, update service state | Unpatched machines |
| 15 | **Drivers**: devices with driver problems (Device Manager yellow marks), age/version of graphics, network, storage and audio drivers | Broken or outdated drivers |
| 16 | Firewall profiles, Windows activation, startup program list | Security gaps, slow boot |
| 17 | CPU load, RAM usage, disk queue, top 10 processes by CPU and RAM | Performance bottlenecks |

## Reading the results

Every report ends with a **SUMMARY**:

- **PASS / PASS WITH WARNINGS / FAIL** — numbered critical issues and warnings.
- **RECOMMENDED IMPROVEMENTS** — upgrade suggestions generated from the spec
  (e.g. add RAM below 8 GB, replace HDD with SSD, too few CPU cores,
  Windows 10 end-of-life).

Typical actions for critical issues:

- *Disk not Healthy / SMART predicts failure / uncorrected errors* → back up
  now and replace the drive (check warranty with the Service Tag at
  support.dell.com).
- *CHKDSK found problems or dirty volume* → schedule `chkdsk <drive>: /F` at reboot.
- *SFC/DISM found corruption* → run `DISM /Online /Cleanup-Image /RestoreHealth`
  then `sfc /scannow` as admin.
- *Active threat found* → run a FULL scan in Windows Security and quarantine.
- *Printer offline / no ping* → check printer power and cable/Wi-Fi, confirm
  its IP hasn't changed, untick "Use Printer Offline"; stuck jobs → clear the
  queue or restart the Print Spooler service.
- *No gateway / 169.254.x.x address* → cable, switch or DHCP/router problem;
  *internet OK but DNS fails* → set DNS to 8.8.8.8.
- *Low free space* → disk cleanup / move data.

The script is diagnostic-only: it repairs and deletes nothing, so it is safe
to run on every machine. Send the collected Desktop reports back and we can
decide, machine by machine, what software each PC can handle and what to fix
or upgrade.
