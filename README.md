===============================================================================

                    L I N U X   D O C T O R   -   v2.1

                Crafted with love by MUHAMMAD ALI SIDDIQUI

        One-shot Linux troubleshooting, health report and repair tool

===============================================================================


WHAT IT IS
----------
Linux Doctor is a single bash script (linux-doctor_v2.sh). It checks a Linux
machine from top to bottom, explains every problem in plain English, shows
the evidence, and offers fixes you can choose from a menu. When it finishes
it saves a text report and a visual HTML report.

It is meant to get a slow, freezing or broken Linux system back up and
running quickly, without having to know every log file and command.


SUPPORTED SYSTEMS
-----------------
  Debian family : Debian, Ubuntu, Linux Mint, Kali, Pop!_OS, Raspberry Pi OS
  RedHat family : RHEL, Rocky Linux, AlmaLinux, CentOS, Fedora, Oracle, Amazon
  SUSE / others : best effort

  Every check skips itself quietly if a tool is missing, so the script never
  crashes because something is not installed.


QUICK START
-----------
  1. Copy linux-doctor_v2.sh to the Linux machine.
  2. Run it as root:

        sudo bash linux-doctor_v2.sh

  3. Read the summary at the end and, if fixes are offered, pick them from
     the fix menu.
  4. Open the HTML report in a browser (its path is printed at the end).


OPTIONS
-------
  (no option)        Diagnose, then ask whether to open the fix menu
  --fix              Open the fix menu straight after the report
  --no-fix           Never show the fix menu (for cron / automation)
  --quick            Skip slow checks (SMART, updates, iostat, firmware, du)
  --hours N          How far back to read the logs (default: 24 hours)
  --out DIR          Where to save reports (default: /var/log/linux-doctor)
  --net-wait N       In cron runs, wait at most N seconds for internet
                     (default 120). On a terminal it waits until you connect.
  --no-zombie-kill   Report zombie processes but do not clean them up
  --no-color         Plain output without colors
  --no-anim          No intro animation
  --ascii            No Unicode symbols or emoji (for old consoles)
  -h, --help         Show help

  Examples:
     sudo bash linux-doctor_v2.sh                 full check, then fix menu
     sudo bash linux-doctor_v2.sh --quick         fast check
     sudo bash linux-doctor_v2.sh --hours 72      read 3 days of logs
     sudo bash linux-doctor_v2.sh --no-fix --no-color > /dev/null   (cron)


WHAT IT CHECKS (14 SECTIONS)
----------------------------
   1. System overview
      Host, OS, kernel, CPU, RAM, uptime, laptop/desktop/VM, IP address,
      recent reboots and shutdowns.

   2. CPU
      CPU busy %, load compared with the number of cores, time spent waiting
      for the disk, CPU taken by the VM host, CPU speed, top CPU users,
      heat throttling.

   3. Memory
      RAM and swap usage, top memory users, programs killed because memory
      ran out (OOM killer).

   4. Disk & filesystems
      Free space per disk, file-count (inode) limits, disks stuck in
      read-only mode, journal size, biggest items in /var/log.

   5. Storage hardware
      SMART disk health, SSD wear, failing sectors, software RAID, disk and
      filesystem errors, CPU/RAM hardware errors (MCE/EDAC), firmware
      updates (fwupd).

   6. Cooling, fans & battery
      All temperature sensors, fan speeds (RPM, incl. ThinkPad), stopped
      fans, battery charge, battery health and charge cycles.

   7. Processes & zombies
      Process counts and zombie processes, grouped by the application that
      causes them (name, command, service, package, age).

   8. Services & boot
      Failed services, boot time, slowest services, kernel crashes,
      programs that crashed (segfaults).

   9. Log scan
      All errors in the log window, translated into plain English, the
      programs producing the most errors, the most repeated messages.

  10. Network & DNS
      Interfaces, gateway, internet, DNS, listening ports, firewall,
      clock synchronisation (NTP), full connection-tracking table.

  11. System freezes & hangs
      Frozen programs (hung tasks), CPU lockups, processes stuck on disk,
      memory/CPU/disk pressure, swapping, slow disks, storage timeouts,
      crashes or unclean shutdowns of the previous boot, crash capture
      (kdump), hanging network mounts, kernel limits. Ends with a ranked
      "likely freeze cause" verdict.

  12. Security & updates
      Failed logins and attacking IPs, root logins, failed sudo, SELinux /
      AppArmor blocks, pending security updates, reboot required, expiring
      certificates, domain join health (FreeIPA / Active Directory keytab,
      SSSD).

  13. Recent changes
      Packages installed or updated in the last 7 days, config files changed
      in /etc, newer kernel installed but not running. Helps answer "what
      changed before it broke?".

  14. Performance & lag
      Why the desktop, sudo or apps feel slow even when the machine is not
      busy: graphics driver (hardware vs software drawing), GNOME health,
      power profile, Turbo Boost, CPU speed cap, own hostname lookup,
      user/sudo lookup time (SSSD), DNS speed, broken IPv6, busy background
      updaters. Ends with a ranked "lag verdict".


THE SUMMARY
-----------
At the end you get:
  - a scoreboard: every section with its passed / warning / critical count
  - a HEALTH SCORE from 0 to 100 (HEALTHY / NEEDS ATTENTION / CRITICAL)
  - a "FIX THESE FIRST" list with the exact command for each problem
  - the score before and after fixes, if any fixes were applied


THE FIX MENU
------------
The fix menu lets you choose which fixes to run. Each fix shows a risk level:

  SAFE   harmless
  CARE   changes the system
  RISKY  may interrupt services or network access - asks a second time

Choices:
  1,3,5-7   run the fixes with these numbers
  a         run all SAFE fixes
  g         open the GNOME desktop repair menu
  r         save this report and re-scan the whole system
  q         finish

Every fix is checked afterwards and marked FIXED, APPLIED, FAILED or
SKIPPED. Fixes that need to download something are marked "needs internet".

Examples of fixes it can offer:
  - restart a failed service
  - free disk space (shrink the journal, clean the package cache)
  - create a swap file
  - lower the priority of a CPU hog
  - fix time sync, restart the DNS resolver
  - enable the firewall (your SSH ports stay open)
  - install security updates
  - make logs survive reboots (persistent journal)
  - unmount a hanging network share
  - enable kdump (crash capture), install firmware updates
  - switch from Power Saver to Balanced, turn Turbo Boost back on
  - add the machine's own name to /etc/hosts (fixes slow sudo)
  - clear the SSSD cache, enable a GPU driver


GNOME DESKTOP REPAIR MENU (press g)
-----------------------------------
For machines with the GNOME desktop (Rocky, RHEL, Fedora, Ubuntu, Debian):

  - Turn off all GNOME extensions
  - Turn off only YOUR installed extensions (keeps Ubuntu Dock, tray icons
    and desktop icons on Ubuntu)
  - Reset GNOME settings (settings backed up first, old folders kept)
  - Reinstall the core GNOME packages (on Ubuntu also Ubuntu's own desktop
    parts: session, dock, tray, desktop icons, Yaru theme)
  - FULL repair (the three above in a row)
  - Restart the login screen (gdm) - ends all desktop sessions

After a repair: log out and back in, then run the script again and press r.

To undo a settings reset (as your normal user):
     dconf load / < ~/gnome-settings-backup_<date>.ini


ZOMBIE PROCESSES
----------------
Zombies are cleaned up AUTOMATICALLY when the script runs as root:
  1. the parent application is asked to clean up (harmless)
  2. its service is restarted (60 second limit)
  3. the parent is stopped - only after you confirm

Never touched: this script's own terminal, sudo and SSH session, login
sessions, the desktop session, containers and core services. In cron runs
(no keyboard) only step 1 is done.

Use --no-zombie-kill for a strictly read-only run.


INTERNET
--------
Most checks and fixes work fully offline. Only these need the internet:
security updates, firmware updates, and installing a missing package.

If the internet is needed and missing, the script shows what to do
(cable, Wi-Fi, VPN, proxy) and WAITS - it never exits. As soon as you are
connected it carries on. Press S to skip that one step. In cron runs it
waits at most --net-wait seconds and then skips the step.

The script also accepts your package mirror (Satellite / local repo) and
your proxy (https_proxy) as "connected".


REPORTS
-------
Saved in /var/log/linux-doctor (or your --out folder), readable by root only:

  linux-doctor_<host>_<date>.txt        plain text report
  linux-doctor_<host>_<date>.html       visual report: health score rings,
                                        problem cards (what was found / how
                                        to fix / how it was solved),
                                        resolution timeline, gauges, fans,
                                        battery, zombie table, filters,
                                        copy buttons, light/dark mode, print
  linux-doctor_<host>_<date>_evidence/  raw log extracts and command output

A re-scan writes a new report; the earlier one is kept.


SAFETY
------
  - Apart from zombie cleanup, the checks only read - nothing is changed.
  - Nothing is ever deleted. Old folders are renamed to *.old_<date>.
  - Config files a fix edits directly (fstab, /etc/hosts, firewall rules,
    boot config) are backed up first as <file>.backupN_<date>.
  - Fixes only run when you choose them; RISKY fixes ask twice.
  - Values taken from the system (names, paths) are quoted, so they can
    never inject commands into a fix.


EXIT CODES (for cron / monitoring)
----------------------------------
  0   healthy
  1   warnings only
  2   critical problems still open


FILES IN THIS FOLDER
--------------------
  linux-doctor_v2.sh                          the current script (use this)
  linux-doctor_v1.sh                          first version, kept for history
  linux-doctor_v2.sh.backup1_20261126-124803  backup of v2 before the
                                              internet-wait change
  README.txt                                  this file


===============================================================================
                Crafted with love by MUHAMMAD ALI SIDDIQUI
===============================================================================
