#!/usr/bin/env bash
# =============================================================================
#
#   L I N U X   D O C T O R   —   linux-doctor_v1.sh
#
#   Crafted with love by MUHAMMAD ALI SIDDIQUI
#
#   One-shot Linux troubleshooting & health report. Reads the logs, checks the
#   hardware and the OS, hunts down the cause of freezes / hangs and explains
#   every problem in plain English with the command that fixes it.
#
#   Works on:
#     Debian family : Debian, Ubuntu, Mint, Kali, Pop!_OS, Raspberry Pi OS ...
#     RedHat family : RHEL, CentOS, Rocky, AlmaLinux, Fedora, Oracle, Amazon
#     SUSE / others : best effort (every check skips itself if a tool is missing)
#
#   What it checks (read-only by default):
#      1. System overview          6. Services & boot
#      2. CPU                      7. Log scan (errors explained)
#      3. Memory                   8. Network & DNS
#      4. Disk & filesystems       9. System freezes & hangs (root cause)
#      5. Hardware & storage      10. Security & updates
#   Then: health score, "fix these first" list, TXT + HTML report + evidence.
#
#   Usage:  sudo bash linux-doctor_v1.sh [options]
#      --fix        after the report, offer safe fixes one by one (asks y/N)
#      --quick      skip slow checks (SMART, update queries, iostat)
#      --hours N    how far back to read logs (default 24)
#      --out DIR    where to save reports (default /var/log/linux-doctor)
#      --no-color   plain output (also: NO_COLOR env var, or output to a pipe)
#      --ascii      no Unicode symbols / emoji (for old consoles)
#      -h, --help   show help
#
#   Safety: this script never deletes anything. In --fix mode every action is
#   shown first and only runs after you answer "y".
# =============================================================================

set -uo pipefail                                   # unset variable = error; a failing pipe part is noticed (no -e: one failed check must not stop the run)
unset LC_ALL                                       # let the per-category settings below take effect
export LC_NUMERIC=C LC_MESSAGES=C                  # dot as decimal separator + English tool output, so parsing works everywhere

# ----------------------------------------------------------------------------
#  Defaults & command-line options
# ----------------------------------------------------------------------------
VERSION="1.0"                                      # script version shown in banner & reports
AUTHOR="MUHAMMAD ALI SIDDIQUI"                     # author credit
FIX_MODE=0                                         # 1 = offer fixes after the report
QUICK=0                                            # 1 = skip slow checks
HOURS=24                                           # log look-back window in hours
USE_COLOR=1                                        # 1 = colored output
FORCE_ASCII=0                                      # 1 = no Unicode
OUT_DIR="/var/log/linux-doctor"                    # default report folder
TOTAL_STEPS=10                                     # number of check sections

usage() {                                          # print the help text
  cat <<EOF
Linux Doctor v${VERSION} — crafted with love by ${AUTHOR}

Usage: sudo bash $0 [options]
  --fix        after the report, offer safe fixes one by one (asks y/N each)
  --quick      skip slow checks (SMART, update queries, iostat)
  --hours N    how far back to read logs (default 24)
  --out DIR    where to save reports (default /var/log/linux-doctor)
  --no-color   plain output
  --ascii      no Unicode symbols / emoji
  -h, --help   this help
EOF
}

while [[ $# -gt 0 ]]; do                           # walk through every argument
  case "$1" in
    --fix)      FIX_MODE=1 ;;                      # enable fix mode
    --quick)    QUICK=1 ;;                         # enable quick mode
    --hours)    shift; HOURS="${1:-}"              # read the next argument as the hour count
                [[ "$HOURS" =~ ^[0-9]+$ && "$HOURS" -gt 0 ]] || { echo "--hours needs a positive number"; exit 2; } ;;
    --out)      shift; OUT_DIR="${1:-}"            # custom report folder
                [[ -n "$OUT_DIR" ]] || { echo "--out needs a folder"; exit 2; } ;;
    --no-color) USE_COLOR=0 ;;                     # disable colors
    --ascii)    FORCE_ASCII=1 ;;                   # disable Unicode
    -h|--help)  usage; exit 0 ;;                   # show help and quit
    *)          echo "Unknown option: $1"; usage; exit 2 ;;   # anything else is a mistake
  esac
  shift                                            # move to the next argument
done

# ----------------------------------------------------------------------------
#  Look & feel: colors, symbols, terminal width
# ----------------------------------------------------------------------------
[[ -t 1 && -z "${NO_COLOR:-}" ]] || USE_COLOR=0    # no colors when output is not a terminal or NO_COLOR is set

UTF=0                                              # assume plain ASCII until proven otherwise
case "${LC_CTYPE:-}${LANG:-}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF=1 ;; esac   # terminal locale speaks UTF-8?
(( FORCE_ASCII )) && UTF=0                         # user asked for ASCII

COLS=$( { stty size </dev/tty; } 2>/dev/null | awk '{print $2}')   # real terminal width (silent if no terminal)
[[ "$COLS" =~ ^[0-9]+$ ]] || COLS=${COLUMNS:-100}  # fall back to $COLUMNS or 100

if (( USE_COLOR )); then                           # define ANSI color codes
  R=$'\e[0m'; B=$'\e[1m'; DIM=$'\e[2m'             # reset, bold, dim
  RED=$'\e[38;5;196m'; GRN=$'\e[38;5;46m'; YEL=$'\e[38;5;220m'   # status colors
  BLU=$'\e[38;5;39m';  CYN=$'\e[38;5;51m'; MAG=$'\e[38;5;201m'   # accent colors
  GRY=$'\e[38;5;245m'; ORG=$'\e[38;5;208m'; PNK=$'\e[38;5;213m'  # extra shades
else
  R=""; B=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; CYN=""; MAG=""; GRY=""; ORG=""; PNK=""   # all empty = no color
fi
GRAD=(51 45 39 33 63 99 135 171 207)               # 256-color gradient: cyan -> blue -> magenta
c256() { (( USE_COLOR )) && printf '\e[38;5;%sm' "$1"; }   # print one 256-color code

if (( UTF )); then                                 # pretty Unicode symbols
  S_OK="✔"; S_WARN="⚠"; S_FAIL="✖"; S_INFO="➜"; S_FIX="💡"; S_DOT="•"
  BAR_F="█"; BAR_E="░"; HL="━"; PG_F="▰"; PG_E="▱"
  BX_TL="╭"; BX_TR="╮"; BX_BL="╰"; BX_BR="╯"; BX_H="─"; BX_V="│"           # rounded box
  DB_TL="╔"; DB_TR="╗"; DB_BL="╚"; DB_BR="╝"; DB_H="═"; DB_V="║"           # double box
  SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)                     # braille spinner frames
  STEP_ICON=("" "💻" "⚡" "🧠" "💾" "🔩" "🚀" "📜" "🌐" "🧊" "🔒")   # one icon per step
  I_HOST="💻"; I_OS="🐧"; I_KER="🧬"; I_UP="⏰"; I_NET="🌐"; I_VM="📦"; I_CPU="⚡"; I_MEM="🧠"
else                                               # ASCII fall-backs
  S_OK="[OK]"; S_WARN="[!]"; S_FAIL="[X]"; S_INFO="->"; S_FIX="*"; S_DOT="-"
  BAR_F="#"; BAR_E="."; HL="="; PG_F="#"; PG_E="-"
  BX_TL="+"; BX_TR="+"; BX_BL="+"; BX_BR="+"; BX_H="-"; BX_V="|"
  DB_TL="+"; DB_TR="+"; DB_BL="+"; DB_BR="+"; DB_H="="; DB_V="|"
  SPIN=('|' '/' '-' '\')
  STEP_ICON=("" "" "" "" "" "" "" "" "" "" "")
  I_HOST="  "; I_OS="  "; I_KER="  "; I_UP="  "; I_NET="  "; I_VM="  "; I_CPU="  "; I_MEM="  "
fi

# ----------------------------------------------------------------------------
#  Small helpers
# ----------------------------------------------------------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; }     # is a tool installed?
to() { if has_cmd timeout; then timeout "$@"; else shift; "$@"; fi; }   # run with a time limit if 'timeout' exists
rep() { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }  # repeat a string N times
num() { [[ "${1:-}" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }            # sanitize to an integer
cnt() { local n; n=$(grep -Eic -- "$1" "$2" 2>/dev/null); echo "${n:-0}"; }   # count matching lines in a file (case-insensitive)
human_kb() { awk -v k="${1:-0}" 'BEGIN{u="KMGTP";i=1;while(k>=1024&&i<5){k/=1024;i++};printf "%.1f%s",k,substr(u,i,1)}'; }  # KB -> human size

N_CRIT=0; N_WARN=0; N_OK=0                         # counters for the summary
F_SEV=(); F_AREA=(); F_MSG=(); F_HINT=(); F_CMD=() # findings: severity, area, message, hint, auto-fix command
M_LABEL=(); M_VAL=()                               # meters (for the HTML report)
STEP_TITLES=()                                     # step titles (for the HTML report)
CUR_AREA="General"                                 # area name of the current step
STEP_NO=0                                          # current step number
declare -A FZ=([io]=0 [mem]=0 [cpu]=0 [kernel]=0 [nfs]=0 [hw]=0 [limits]=0)   # freeze-cause evidence points

# ---- output primitives -------------------------------------------------------
ok()   { printf '  %s%s%s %s\n' "$GRN" "$S_OK" "$R" "$*"; }            # green tick line
good() { ok "$@"; N_OK=$((N_OK+1)); }                                   # tick line that counts as a passed check
info() { printf '  %s%s%s %s\n' "$BLU" "$S_INFO" "$R" "$*"; }          # blue info line
note() { printf '    %s%s%s\n' "$GRY" "$*" "$R"; }                      # grey detail line
kv()   { printf '  %s%-20s%s %s\n' "$GRY" "$1" "$R" "$2"; }             # "label   value" line
skip() { printf '  %s%s skipped:%s %s%s%s\n' "$GRY" "$S_DOT" "$R" "$DIM" "$*" "$R"; }   # skipped check line
sub()  { printf '\n  %s%s%s\n' "$CYN$B" "$*" "$R"; }                    # small sub-heading

add_finding() {                                    # record + print a problem: SEV MESSAGE HINT [FIX_CMD]
  local sev=$1 msg=$2 hint=${3:-} cmd=${4:-}
  F_SEV+=("$sev"); F_AREA+=("$CUR_AREA"); F_MSG+=("$msg"); F_HINT+=("$hint"); F_CMD+=("$cmd")   # store for summary/reports/fixes
  if [[ $sev == CRIT ]]; then
    printf '  %s%s CRITICAL%s %s\n' "$RED$B" "$S_FAIL" "$R" "$msg"; N_CRIT=$((N_CRIT+1))        # red line
  else
    printf '  %s%s WARNING%s  %s\n' "$YEL$B" "$S_WARN" "$R" "$msg"; N_WARN=$((N_WARN+1))        # yellow line
  fi
  [[ -n $hint ]] && printf '      %s%s Fix:%s %s%s%s\n' "$YEL" "$S_FIX" "$R" "$DIM" "$hint" "$R"   # how to fix it
  return 0
}

meter() {                                          # colored usage bar: LABEL PERCENT [EXTRA TEXT]
  local label=$1 pct extra=${3:-} width=30 fill col
  pct=$(num "${2%.*}")                             # integer percent
  local shown=$pct; (( pct > 100 )) && pct=100     # bar is capped at 100 but real value is shown
  fill=$(( pct * width / 100 ))                    # how many blocks to fill
  if   (( shown >= 90 )); then col=$RED            # red at 90%+
  elif (( shown >= 70 )); then col=$YEL            # yellow at 70%+
  else col=$GRN; fi                                # green below
  printf '  %-16.16s %s%s%s%s%s %s%4d%%%s  %s%s%s\n' "$label" "$col" "$(rep "$BAR_F" "$fill")" "$GRY" \
    "$(rep "$BAR_E" $((width - fill)))" "$R" "$col$B" "$shown" "$R" "$DIM" "$extra" "$R"
  M_LABEL+=("$CUR_AREA: $label"); M_VAL+=("$shown")   # remember for HTML
}

table_head() { printf '  %s%s%s\n' "$MAG$B" "$*" "$R"; }              # colored table header row
table_rows() { sed 's/^/  /' | cut -c1-"$(( COLS > 40 ? COLS - 2 : 118 ))"; }   # indent + trim table rows to terminal width

step() {                                           # big colored section header with progress bar
  STEP_NO=$((STEP_NO + 1)); CUR_AREA=$1; STEP_TITLES+=("$1")
  local icon=${STEP_ICON[$STEP_NO]:-} title=${1^^}
  local done=$(( STEP_NO * 10 / TOTAL_STEPS )) pad=$(( 44 - ${#title} ))
  (( pad < 3 )) && pad=3
  echo
  printf '%s%s [%d/%d] %s %s %s%s  %s%s%s%s %3d%%%s\n' "$(c256 "${GRAD[$(( (STEP_NO-1) % ${#GRAD[@]} ))]}")$B" "$(rep "$HL" 3)" \
    "$STEP_NO" "$TOTAL_STEPS" "$icon" "$title" "$(rep "$HL" "$pad")" "$R" \
    "$CYN" "$(rep "$PG_F" "$done")" "$GRY$(rep "$PG_E" $((10 - done)))" "$R" $(( STEP_NO * 100 / TOTAL_STEPS )) ""
}

SPIN_N=0; SPIN_OUT=""; SPIN_RC=0                   # spinner state
run_spin() {                                       # run a slow command with a spinner: MESSAGE CMD [ARGS...]
  local msg=$1; shift
  SPIN_N=$((SPIN_N + 1))
  local f="$EVID/cmd_${SPIN_N}.out" i=0 pid      # command output is kept as evidence
  "$@" >"$f" 2>&1 &                                # start the command in the background
  pid=$!
  if [[ -t 2 ]] && (( USE_COLOR )); then           # animate only on a real terminal
    while kill -0 "$pid" 2>/dev/null; do           # while the command is still running
      printf '\r  %s%s%s %s%s%s ' "$CYN" "${SPIN[i++ % ${#SPIN[@]}]}" "$R" "$DIM" "$msg" "$R" >&2   # draw next frame
      sleep 0.1                                    # 10 frames per second
    done
    printf '\r\e[K' >&2                            # clear the spinner line
  fi
  wait "$pid"; SPIN_RC=$?                          # collect exit code
  SPIN_OUT=$(<"$f")                                # collect output
}

ask() {                                            # yes/no question read from the keyboard
  local a=""
  printf '  %s%s [y/N]%s ' "$CYN$B" "$1" "$R" >&2  # question goes to the screen only
  read -r a </dev/tty 2>/dev/null || a=""          # read the answer from the terminal
  [[ $a =~ ^[Yy] ]]                                # true only for y / yes
}

# ----------------------------------------------------------------------------
#  Pre-flight: who am I, which distro, where do logs live, where to save
# ----------------------------------------------------------------------------
IS_ROOT=0; [[ $EUID -eq 0 ]] && IS_ROOT=1          # running as root?

OS_ID="unknown"; OS_LIKE=""; OS_NAME="$(uname -s)"; OS_VER=""
if [[ -r /etc/os-release ]]; then                  # standard distro identification file
  # shellcheck disable=SC1091
  . /etc/os-release                                # load NAME, ID, ID_LIKE, PRETTY_NAME, VERSION_ID
  OS_ID=${ID:-unknown}; OS_LIKE=${ID_LIKE:-}; OS_NAME=${PRETTY_NAME:-${NAME:-Linux}}; OS_VER=${VERSION_ID:-}
elif [[ -r /etc/redhat-release ]]; then            # very old RedHat without os-release
  OS_ID="rhel"; OS_NAME=$(</etc/redhat-release)
fi

case " $OS_ID $OS_LIKE " in                        # map the distro to a family
  *" debian "*|*" ubuntu "*|*" raspbian "*|*" linuxmint "*|*" pop "*|*" kali "*) FAMILY="debian" ;;
  *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*|*" amzn "*) FAMILY="rhel" ;;
  *" suse "*|*" sles "*|*" opensuse"*) FAMILY="suse" ;;
  *) FAMILY="other" ;;
esac

PKG="none"                                         # package manager
for p in apt-get dnf yum zypper; do has_cmd "$p" && { PKG=$p; break; }; done   # first one found wins

SYSLOG=""; AUTHLOG=""                              # classic text log files
for f in /var/log/syslog /var/log/messages; do [[ -r $f ]] && { SYSLOG=$f; break; }; done      # Debian / RedHat main log
for f in /var/log/auth.log /var/log/secure; do [[ -r $f ]] && { AUTHLOG=$f; break; }; done     # Debian / RedHat login log

HAS_JOURNAL=0                                      # can we read the systemd journal?
has_cmd journalctl && journalctl -n 1 -q --no-pager >/dev/null 2>&1 && HAS_JOURNAL=1
HAS_SYSTEMD=0; [[ -d /run/systemd/system ]] && HAS_SYSTEMD=1   # is systemd the init system?
SINCE="${HOURS} hours ago"                         # journal time window

HOST=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname)  # machine name
TS=$(date +%Y%m%d-%H%M%S)                          # timestamp for file names

if ! mkdir -p "$OUT_DIR" 2>/dev/null || [[ ! -w $OUT_DIR ]]; then   # can we write the report folder?
  OUT_DIR="${HOME:-/tmp}/linux-doctor-reports"    # fall back to the user's home folder
  mkdir -p "$OUT_DIR" 2>/dev/null || OUT_DIR="/tmp"   # last resort: /tmp
fi
BASE="$OUT_DIR/linux-doctor_${HOST}_${TS}"         # common file name prefix
TXT="$BASE.txt"; HTML="$BASE.html"                 # report files
EVID="${BASE}_evidence"                            # folder with raw evidence (log extracts, command output)
mkdir -p "$EVID"                                   # create evidence folder
RAW="$EVID/terminal-output.ansi"                   # colored copy of the screen (view with: less -R)
KLOG="$EVID/kernel.log"; ERRLOG="$EVID/errors.log"; AUTHL="$EVID/auth.log"   # log extracts we analyse

exec 3>&1                                          # keep the real screen on file descriptor 3
exec > >(tee -a "$RAW")                            # everything printed from now on is also saved
TEE_PID=${!:-}                                     # remember tee so we can wait for it at the end
START_SEC=$SECONDS                                 # start time for the duration counter

# ============================================================================
#  BANNER
# ============================================================================
banner() {
  echo
  if (( UTF )) && (( COLS >= 96 )); then           # wide terminal: big block letters
    local L=(
"██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗  ██████╗  ██████╗  ██████╗████████╗ ██████╗ ██████╗ "
"██║     ██║████╗  ██║██║   ██║╚██╗██╔╝  ██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗"
"██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝   ██║  ██║██║   ██║██║        ██║   ██║   ██║██████╔╝"
"██║     ██║██║╚██╗██║██║   ██║ ██╔██╗   ██║  ██║██║   ██║██║        ██║   ██║   ██║██╔══██╗"
"███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗  ██████╔╝╚██████╔╝╚██████╗   ██║   ╚██████╔╝██║  ██║"
"╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝  ╚═════╝  ╚═════╝  ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝"
    )
    local i; for i in "${!L[@]}"; do printf '  %s%s%s\n' "$(c256 "${GRAD[$((i+1))]}")$B" "${L[$i]}" "$R"; done   # each line one shade further in the gradient
  elif (( UTF )); then                             # narrow terminal: compact letters
    local L=("╦  ╦╔╗╔╦ ╦═╗ ╦  ╔╦╗╔═╗╔═╗╔╦╗╔═╗╦═╗" "║  ║║║║║ ║╔╩╦╝   ║║║ ║║   ║ ║ ║╠╦╝" "╩═╝╩╝╚╝╚═╝╩ ╚═  ═╩╝╚═╝╚═╝ ╩ ╚═╝╩╚═")
    local i; for i in "${!L[@]}"; do printf '  %s%s%s\n' "$(c256 "${GRAD[$((i*3))]}")$B" "${L[$i]}" "$R"; done
  else                                             # ASCII terminal
    printf '  %s==============  L I N U X   D O C T O R  ==============%s\n' "$CYN$B" "$R"
  fi
  if (( UTF )); then                               # heartbeat line under the logo
    printf '  %s──────────────────────╮%s╭╮%s╭─────────╯╰──╮╭─────────────────%s\n' "$GRY" "$RED$B" "$GRY" "$R"
    printf '  %s                      ╰╯ ╰╯              ╰╯%s\n' "$RED" "$R"
  fi
  local w=62                                       # credit box width
  printf '  %s%s%s%s%s\n' "$PNK" "$BX_TL" "$(rep "$BX_H" "$w")" "$BX_TR" "$R"
  printf '  %s%s%s  %s%-58s%s  %s%s%s\n' "$PNK" "$BX_V" "$R" "$B" "Crafted with love by $AUTHOR" "$R" "$PNK" "$BX_V" "$R"
  printf '  %s%s%s  %s%-58s%s  %s%s%s\n' "$PNK" "$BX_V" "$R" "$GRY" "Linux Doctor v$VERSION  -  find it, explain it, fix it" "$R" "$PNK" "$BX_V" "$R"
  printf '  %s%s%s%s%s\n' "$PNK" "$BX_BL" "$(rep "$BX_H" "$w")" "$BX_BR" "$R"
  echo
  kv "Started"       "$(date '+%Y-%m-%d %H:%M:%S %Z')"                     # when
  kv "Log window"    "last $HOURS hours"                                    # how far back
  kv "Mode"          "$( ((FIX_MODE)) && echo 'diagnose + offer fixes' || echo 'diagnose only (read-only)')$( ((QUICK)) && echo ', quick')"
  kv "Distro family" "$FAMILY  (package manager: $PKG)"
  kv "Reports to"    "$OUT_DIR"
  if (( ! IS_ROOT )); then                         # warn when not root
    echo
    printf '  %s%s Not running as root%s - some checks (logs, SMART, firewall) will be limited.\n' "$YEL$B" "$S_WARN" "$R"
    note "For the full picture run:  sudo bash $0"
  fi
}

# ============================================================================
#  LOG COLLECTION (runs once, all steps reuse the extracts)
# ============================================================================
collect_logs() {
  # --- kernel messages ---
  if (( HAS_JOURNAL )); then
    journalctl -k --since "$SINCE" --no-pager -q -o short-iso >"$KLOG" 2>/dev/null    # kernel log for the window
  fi
  if [[ ! -s $KLOG ]]; then
    dmesg -T >"$KLOG" 2>/dev/null || dmesg >"$KLOG" 2>/dev/null                       # kernel ring buffer since boot
  fi
  if [[ ! -s $KLOG ]]; then
    for f in /var/log/kern.log /var/log/messages; do                                  # text log fall-back
      [[ -r $f ]] && { tail -n 50000 "$f" | grep -i 'kernel' >"$KLOG"; break; }
    done
  fi
  # --- errors from every program ---
  if (( HAS_JOURNAL )); then
    journalctl -p err --since "$SINCE" --no-pager -q -o short-iso >"$ERRLOG" 2>/dev/null   # priority err and worse
  fi
  if [[ ! -s $ERRLOG && -n $SYSLOG ]]; then
    tail -n 100000 "$SYSLOG" | grep -Ei 'error|fail|crit|emerg|alert|panic|denied' >"$ERRLOG"   # grep the text log
  fi
  # --- logins / sudo ---
  if (( HAS_JOURNAL )); then
    journalctl --since "$SINCE" --no-pager -q -o short-iso _COMM=sshd _COMM=sudo _COMM=su _COMM=login >"$AUTHL" 2>/dev/null   # auth related programs
  fi
  if [[ ! -s $AUTHL && -n $AUTHLOG ]]; then
    tail -n 100000 "$AUTHLOG" >"$AUTHL"                                                 # text auth log fall-back
  fi
  touch "$KLOG" "$ERRLOG" "$AUTHL"                                                       # make sure the files exist
}

# ============================================================================
#  1. SYSTEM OVERVIEW
# ============================================================================
check_overview() {
  step "System overview"
  local up_s up virt ip kern cpu_model mem_kb boot_t users
  up_s=$(awk '{print int($1)}' /proc/uptime)                                   # uptime in seconds
  up=$(uptime -p 2>/dev/null || echo "$((up_s/86400)) days")                    # human uptime
  boot_t=$(uptime -s 2>/dev/null || echo "?")                                   # boot time
  virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")                     # VM / container / physical
  [[ $virt == none ]] && virt="physical (bare metal)"
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')                              # main IP address
  [[ -z $ip ]] && ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4; exit}')
  kern=$(uname -r)                                                              # kernel version
  cpu_model=$(awk -F: '/model name/{gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo)   # CPU model
  mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)                            # total RAM
  users=$(who 2>/dev/null | wc -l)                                              # logged in sessions

  local w=66 line                                                               # host card
  printf '  %s%s%s%s%s\n' "$BLU" "$BX_TL" "$(rep "$BX_H" "$w")" "$BX_TR" "$R"
  for line in "$I_HOST|Host|$HOST" "$I_OS|OS|$OS_NAME" "$I_KER|Kernel|$kern ($(uname -m))" \
              "$I_CPU|CPU|$(nproc 2>/dev/null) cores  ${cpu_model:0:40}" "$I_MEM|RAM|$(human_kb "$mem_kb")" \
              "$I_UP|Uptime|$up (since $boot_t)" "$I_VM|Platform|$virt" "$I_NET|IP|${ip:-none}  ($users user sessions)"; do
    IFS='|' read -r ic lb vl <<<"$line"                                         # split icon|label|value
    printf '  %s%s%s %s %s%-9s%s %-50.50s %s%s%s\n' "$BLU" "$BX_V" "$R" "$ic" "$CYN$B" "$lb" "$R" "$vl" "$BLU" "$BX_V" "$R"
  done
  printf '  %s%s%s%s%s\n' "$BLU" "$BX_BL" "$(rep "$BX_H" "$w")" "$BX_BR" "$R"

  if (( up_s > 180*86400 )); then                                               # very long uptime
    add_finding WARN "Not rebooted for $((up_s/86400)) days - kernel security fixes installed since then are NOT active" \
      "Plan a maintenance reboot"
  else
    good "Uptime looks normal ($up)"
  fi
  if has_cmd last; then                                                         # recent reboots / shutdowns
    local lr; lr=$(last -x -n 6 reboot shutdown 2>/dev/null | grep -Ev '^$|wtmp begins' | head -6)
    [[ -n $lr ]] && { sub "Recent reboots & shutdowns"; printf '%s\n' "$lr" | table_rows; }
  fi
}

# ============================================================================
#  2. CPU
# ============================================================================
VM_R=0; VM_B=0; VM_SI=0; VM_SO=0; VM_US=0; VM_SY=0; VM_ID=100; VM_WA=0; VM_ST=0   # vmstat results, reused later
check_cpu() {
  step "CPU"
  local cores l1 l5 l15 lp
  cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)               # number of CPU threads
  read -r l1 l5 l15 _ </proc/loadavg                                            # load averages
  lp=$(awk -v l="$l1" -v c="$cores" 'BEGIN{printf "%d", l*100/c}')              # load as % of capacity

  if has_cmd vmstat; then
    run_spin "Sampling CPU, memory & disk activity for 5 seconds..." vmstat 1 5    # 5 one-second samples
    read -r VM_R VM_B VM_SI VM_SO VM_US VM_SY VM_ID VM_WA VM_ST < <(awk '
      NR==2 { for (i=1;i<=NF;i++) h[$i]=i }                                     # header line: remember column positions
      END   { print $h["r"], $h["b"], $h["si"], $h["so"], $h["us"], $h["sy"], $h["id"], $h["wa"], (("st" in h) ? $h["st"] : 0) }' <<<"$SPIN_OUT")
  fi
  VM_R=$(num "$VM_R"); VM_B=$(num "$VM_B"); VM_SI=$(num "$VM_SI"); VM_SO=$(num "$VM_SO")   # sanitize numbers
  VM_ID=$(num "$VM_ID"); VM_WA=$(num "$VM_WA"); VM_ST=$(num "$VM_ST")

  meter "CPU busy"  $((100 - VM_ID)) "user ${VM_US}%  system ${VM_SY}%"        # overall CPU use
  meter "Load (1m)" "$lp"            "load $l1 / $l5 / $l15 on $cores cores"    # load vs cores
  meter "IO wait"   "$VM_WA"         "time CPUs sit idle waiting for disk"
  (( VM_ST > 0 )) && meter "Steal" "$VM_ST" "CPU taken by the hypervisor"

  if awk -v l="$l5" -v c="$cores" 'BEGIN{exit !(l > c*2)}'; then              # load > 2x cores
    add_finding CRIT "System is overloaded: 5-min load $l5 is more than double the $cores cores" \
      "See the top processes below; kill/limit the runaway one or add CPU"; FZ[cpu]=$((FZ[cpu]+2))
  elif awk -v l="$l5" -v c="$cores" 'BEGIN{exit !(l > c)}'; then             # load > cores
    add_finding WARN "CPU is busier than it can handle (load $l5 on $cores cores) - things will feel slow" \
      "Check the top processes below"; FZ[cpu]=$((FZ[cpu]+1))
  else
    good "CPU load is healthy ($l1 on $cores cores)"
  fi
  if (( VM_WA >= 20 )); then                                                    # heavy IO wait
    add_finding WARN "CPUs spend ${VM_WA}% of time waiting for the disk - storage is the bottleneck" \
      "Check step 9 (freezes) and: iotop -o   /  iostat -x 2"; FZ[io]=$((FZ[io]+2))
  fi
  if (( VM_ST >= 10 )); then                                                    # noisy neighbour on VM host
    add_finding WARN "Hypervisor steals ${VM_ST}% CPU - the VM host is overcommitted" \
      "Ask the virtualization admin to move/resize this VM"; FZ[cpu]=$((FZ[cpu]+1))
  fi

  sub "Top 5 CPU users"
  table_head "$(printf '%-8s %-12s %6s %6s  %s' PID USER CPU% MEM% COMMAND)"
  ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu --no-headers 2>/dev/null | head -5 | \
    awk '{printf "%-8s %-12.12s %6s %6s  %s\n",$1,$2,$3,$4,$5}' | table_rows       # top CPU processes

  local temp=0 t z                                                              # temperature
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [[ -r $z ]] || continue
    t=$(num "$(<"$z")"); t=$((t/1000))                                          # millidegrees -> degrees
    (( t > temp && t < 150 )) && temp=$t                                        # keep the hottest sane reading
  done
  if (( temp == 0 )) && has_cmd sensors; then
    temp=$(sensors 2>/dev/null | grep -oE '\+[0-9]+(\.[0-9])?°?C' | tr -dc '0-9.\n' | sort -n | tail -1 | cut -d. -f1)
    temp=$(num "$temp")
  fi
  if (( temp > 0 )); then
    meter "Temperature" "$temp" "${temp} C (bar = % of 100 C)"
    if   (( temp >= 90 )); then add_finding CRIT "CPU is overheating at ${temp} C - it will throttle or shut down" "Check fans, airflow, dust, heatsink paste"; FZ[hw]=$((FZ[hw]+2))
    elif (( temp >= 80 )); then add_finding WARN "CPU runs hot at ${temp} C" "Check cooling / fan speed"
    fi
  fi
  local thr; thr=$(cnt 'cpu clock throttled|temperature above threshold|thermal.*critical' "$KLOG")
  (( thr > 0 )) && { add_finding WARN "CPU was throttled for heat $thr time(s) - it slowed down to cool off" "Improve cooling"; FZ[hw]=$((FZ[hw]+1)); }
  return 0
}

# ============================================================================
#  3. MEMORY
# ============================================================================
OOM_N=0
check_memory() {
  step "Memory"
  local mt ma sf st mu su
  mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)                              # total RAM (KB)
  ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)                          # RAM still available (KB)
  [[ -z $ma ]] && ma=$(awk '/^(MemFree|Buffers|Cached):/{s+=$2} END{print s}' /proc/meminfo)   # old kernels
  st=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)                             # total swap
  sf=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)                              # free swap
  mt=$(num "$mt"); ma=$(num "$ma"); st=$(num "$st"); sf=$(num "$sf")           # sanitize
  (( mt > 0 )) || mt=1                                                          # never divide by zero
  mu=$(( (mt - ma) * 100 / mt ))                                                # RAM used %
  meter "RAM used" "$mu" "$(human_kb $((mt-ma))) of $(human_kb "$mt")"
  if (( st > 0 )); then
    su=$(( (st - sf) * 100 / st ))                                              # swap used %
    meter "Swap used" "$su" "$(human_kb $((st-sf))) of $(human_kb "$st")"
  else
    su=0; info "No swap configured"
  fi

  if   (( mu >= 95 )); then add_finding CRIT "RAM is almost full (${mu}%) - the system will crawl or start killing programs" "Find the hog below; restart it or add RAM/swap"; FZ[mem]=$((FZ[mem]+2))
  elif (( mu >= 85 )); then add_finding WARN "RAM usage is high (${mu}%)" "Check the top memory users below"; FZ[mem]=$((FZ[mem]+1))
  else good "RAM usage is fine (${mu}%)"; fi
  if   (( su >= 80 )); then add_finding CRIT "Swap is ${su}% full - RAM ran out and the disk is used as memory (very slow)" "Free memory or add RAM"; FZ[mem]=$((FZ[mem]+2))
  elif (( su >= 50 )); then add_finding WARN "Swap is ${su}% used - memory has been under pressure" "Check the top memory users below"; FZ[mem]=$((FZ[mem]+1))
  fi
  if (( st == 0 && mu >= 85 )); then
    add_finding WARN "No swap and high RAM use - one spike will trigger the OOM killer" "Add a swap file (e.g. 2-4 GB)"
  fi

  sub "Top 5 memory users"
  table_head "$(printf '%-8s %-12s %6s %10s  %s' PID USER MEM% RSS COMMAND)"
  ps -eo pid,user,%mem,rss,comm --sort=-rss --no-headers 2>/dev/null | head -5 | \
    while read -r p u m r c; do printf '%-8s %-12.12s %6s %10s  %s\n' "$p" "$u" "$m" "$(human_kb "$r")" "$c"; done | table_rows

  OOM_N=$(cnt 'out of memory|oom-kill|killed process' "$KLOG")                  # OOM killer activity
  if (( OOM_N > 0 )); then
    add_finding CRIT "The kernel's OOM killer fired $OOM_N time(s): RAM ran out and programs were killed" \
      "See victims below; give the app a memory limit or add RAM"; FZ[mem]=$((FZ[mem]+3))
    sub "OOM victims"
    grep -Eio 'killed process [0-9]+ \([^)]+\)' "$KLOG" | sed -E 's/.*\((.*)\)/\1/' | sort | uniq -c | sort -rn | head -5 | table_rows
  else
    good "No out-of-memory kills in the last $HOURS h"
  fi
}

# ============================================================================
#  4. DISK & FILESYSTEMS
# ============================================================================
check_disk() {
  step "Disk & filesystems"
  local fs type size used avail pct mnt p bad=0
  local XF=(-x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x iso9660 -x fuse.snapfuse)   # ignore pseudo filesystems
  sub "Space usage"
  while read -r fs type size used avail pct mnt; do                            # each real filesystem
    p=$(num "${pct%\%}")
    meter "${mnt}" "$p" "$(human_kb "$used") used of $(human_kb "$size"), $(human_kb "$avail") free ($type)"
    if   (( p >= 95 )); then add_finding CRIT "Filesystem $mnt is ${p}% full - programs will fail to write" "du -xh --max-depth=1 $mnt 2>/dev/null | sort -h | tail -15" ; bad=1
    elif (( p >= 85 )); then add_finding WARN "Filesystem $mnt is ${p}% full" "du -xh --max-depth=1 $mnt 2>/dev/null | sort -h | tail -15"; bad=1
    fi
  done < <(to 15 df -PT "${XF[@]}" 2>/dev/null | tail -n +2 | \
           awk '{for(i=NF;i>0;i--) if ($i ~ /^[0-9]+%$/) break; if (i<5) next
                 m=$(i+1); for(j=i+2;j<=NF;j++) m=m" "$j
                 print $1, (i>=6 ? $2 : "?"), $(i-3), $(i-2), $(i-1), $i, m}')  # -P one line per fs, -T type; columns located by the "NN%" field so any df layout works
  (( bad )) || good "All filesystems have enough free space"

  bad=0                                                                         # inode check
  while read -r fs ino iu ifr ipct mnt; do
    [[ $ipct == "-" ]] && continue                                              # filesystems without inode limits
    p=$(num "${ipct%\%}")
    if (( p >= 90 )); then
      add_finding CRIT "Filesystem $mnt has used ${p}% of its inodes (file slots) - no new files can be created even with free space" \
        "Find folders with millions of small files: for d in $mnt/*; do echo \$(find \$d -xdev | wc -l) \$d; done | sort -n | tail"; bad=1
    fi
  done < <(to 15 df -Pi "${XF[@]}" 2>/dev/null | tail -n +2)
  (( bad )) || good "Inode (file count) usage is fine"

  local ro                                                                      # filesystems forced read-only
  ro=$(awk '$4 ~ /(^|,)ro(,|$)/ && $3 ~ /^(ext[234]|xfs|btrfs|jfs|reiserfs)$/ {print $2}' /proc/mounts)
  if [[ -n $ro ]]; then
    add_finding CRIT "Filesystem(s) mounted READ-ONLY: $(echo $ro) - usually the kernel did this after disk errors" \
      "Check step 5 disk errors; then fsck at next boot: touch /forcefsck (or boot rescue mode)"; FZ[io]=$((FZ[io]+2))
  else
    good "No filesystem is stuck in read-only mode"
  fi

  if (( IS_ROOT )); then
    sub "Biggest items in /var/log"
    to 20 du -sh /var/log/* 2>/dev/null | sort -rh | head -5 | table_rows       # biggest log files/folders
  fi
  if (( HAS_JOURNAL )); then
    local ju jb
    ju=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]')        # journal size
    [[ -n $ju ]] && info "Systemd journal uses $ju on disk"
    jb=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+G' | cut -d. -f1)
    if (( $(num "$jb") >= 2 )); then
      add_finding WARN "The systemd journal uses $ju of disk" "journalctl --vacuum-size=200M" "journalctl --vacuum-size=200M"
    fi
  fi
}

# ============================================================================
#  5. HARDWARE & STORAGE HEALTH
# ============================================================================
check_hardware() {
  step "Hardware & storage health"
  local d out
  if (( QUICK )); then skip "SMART disk health (quick mode)"
  elif ! has_cmd smartctl; then skip "SMART disk health - install 'smartmontools' to enable"
  elif (( ! IS_ROOT )); then skip "SMART disk health needs root"
  else
    for d in $(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}'); do   # every physical disk
      run_spin "Asking /dev/$d for its SMART health..." to 30 smartctl -H "/dev/$d"
      out=$SPIN_OUT
      if grep -Eq 'PASSED|: OK' <<<"$out"; then good "Disk /dev/$d reports SMART health: PASSED"
      elif grep -q 'FAILED' <<<"$out"; then
        add_finding CRIT "Disk /dev/$d says it is FAILING (SMART) - back up NOW and replace it" "smartctl -a /dev/$d"; FZ[io]=$((FZ[io]+3)); FZ[hw]=$((FZ[hw]+2))
      else note "/dev/$d: SMART not available (virtual disk or unsupported controller)"
      fi
    done
  fi

  if [[ -r /proc/mdstat ]] && grep -q '^md' /proc/mdstat; then                  # software RAID
    if grep -Eq '\[[U_]*_[U_]*\]' /proc/mdstat; then
      add_finding CRIT "Software RAID is DEGRADED - a disk dropped out of the array" "cat /proc/mdstat ; mdadm --detail /dev/mdX"; FZ[hw]=$((FZ[hw]+1))
    elif grep -Eq 'recovery|resync' /proc/mdstat; then info "Software RAID is rebuilding (slow disks expected until done)"
    else good "Software RAID arrays are healthy"; fi
  fi

  local derr                                                                    # disk / filesystem errors in kernel log
  derr=$(cnt 'I/O error|Buffer I/O|blk_update_request|EXT4-fs error|XFS .*(error|corrupt)|BTRFS error|ata[0-9.]+: .*(failed|error)|critical (medium|target) error|reset controller|nvme.*timeout' "$KLOG")
  if (( derr > 0 )); then
    add_finding CRIT "Kernel logged $derr disk / filesystem error(s) - storage hardware or filesystem is in trouble" \
      "See lines below; check cables/controller, run SMART, fsck the filesystem"; FZ[io]=$((FZ[io]+3))
    sub "Disk error samples"
    grep -Ei 'I/O error|Buffer I/O|blk_update_request|EXT4-fs error|XFS .*(error|corrupt)|BTRFS error|ata[0-9.]+: .*(failed|error)|critical (medium|target) error|reset controller|nvme.*timeout' "$KLOG" | tail -5 | cut -c1-160 | table_rows
  else
    good "No disk or filesystem errors in the kernel log"
  fi

  local mce; mce=$(cnt 'Machine check|mce:|Hardware Error|EDAC .*(CE|UE)|PCIe Bus Error' "$KLOG")   # CPU/RAM/PCIe hardware errors
  if (( mce > 0 )); then
    add_finding CRIT "$mce hardware error(s) reported by CPU/RAM/PCIe (MCE/EDAC) - faulty RAM or board likely" \
      "Run a memory test (memtest86+), check vendor hardware logs (iLO/iDRAC)"; FZ[hw]=$((FZ[hw]+3))
  else
    good "No CPU / RAM / PCIe hardware errors reported"
  fi

  local z; z=$(ps -eo stat --no-headers 2>/dev/null | grep -c '^Z')             # zombie processes
  if (( z > 5 )); then
    add_finding WARN "$z zombie processes - a parent program is not cleaning up its children" "ps -eo ppid,pid,stat,comm | awk '\$3 ~ /^Z/' (restart the parent)"
  else
    good "Zombie processes: $z"
  fi
}

# ============================================================================
#  6. SERVICES & BOOT
# ============================================================================
check_services() {
  step "Services & boot"
  if (( ! HAS_SYSTEMD )); then skip "systemd not in use - service checks skipped"; return; fi
  local failed u
  failed=$(systemctl --failed --no-legend --plain --no-pager 2>/dev/null | \
    awk '{for(i=1;i<=NF;i++) if ($i ~ /\.(service|socket|mount|timer|target|path|swap|automount)$/) {print $i; break}}')   # names of failed units
  if [[ -n $failed ]]; then
    for u in $failed; do
      add_finding CRIT "Service '$u' has FAILED" "journalctl -u $u -n 50 --no-pager   then: systemctl restart $u" "systemctl restart $u"
      journalctl -u "$u" -n 3 --no-pager -q 2>/dev/null | cut -c1-150 | sed 's/^/    /' | table_rows   # last lines of that service
    done
  else
    good "No failed services"
  fi

  local bt; bt=$(to 10 systemd-analyze 2>/dev/null | head -1)                   # boot duration
  if [[ -n $bt ]]; then
    info "Boot: ${bt#Startup finished in }"
    if grep -Eq '= *([2-9]|[1-9][0-9])min' <<<"$bt"; then
      add_finding WARN "Boot is slow (over 2 minutes)" "systemd-analyze blame | head   (disable or fix the slowest units)"
    fi
    sub "Slowest services at boot"
    to 10 systemd-analyze blame --no-pager 2>/dev/null | head -5 | table_rows
  fi

  local pan seg
  pan=$(cnt 'Kernel panic|kernel BUG|Oops:|general protection fault' "$KLOG")   # kernel crashes
  (( pan > 0 )) && { add_finding CRIT "Kernel crash / bug messages found ($pan) - a driver or kernel problem" "Update the kernel & drivers; see $KLOG"; FZ[kernel]=$((FZ[kernel]+3)); }
  seg=$(cnt 'segfault at|traps:.*(general protection|trap)' "$KLOG")           # crashing programs
  if (( seg > 0 )); then
    add_finding WARN "Programs crashed (segfault) $seg time(s)" "Update/reinstall the program shown below"
    grep -Eo '[A-Za-z0-9_.+-]+\[[0-9]+\]: segfault' "$KLOG" | sed -E 's/\[[0-9]+\].*//' | sort | uniq -c | sort -rn | head -5 | table_rows
  fi
  (( pan == 0 && seg == 0 )) && good "No kernel crashes or program segfaults"
  return 0
}

# ============================================================================
#  7. LOG SCAN
# ============================================================================
#  regex @@ plain-English meaning
PATTERNS=(
  "out of memory|oom-kill|killed process@@RAM ran out - kernel killed programs"
  "no space left on device@@A disk filled up - writes failed"
  "read-only file system@@A filesystem went read-only (usually disk errors)"
  "i/o error|buffer i/o|blk_update_request|medium error@@Disk / storage hardware errors"
  "segfault|core dumped@@A program crashed"
  "failed to start|failed with result|dependency failed@@A service could not start"
  "connection refused@@Something tried to reach a service that is down / not listening"
  "connection timed out|timed out|timeout@@Network or service too slow / unreachable"
  "permission denied|operation not permitted@@Permission, SELinux or AppArmor block"
  "authentication failure|failed password|invalid user@@Failed logins"
  "temporary failure in name resolution|name or service not known|servfail|could not resolve@@DNS (name lookup) is broken"
  "too many open files@@A program hit its open-files limit"
  "network is unreachable|link is down|nic link is down@@Network link went down"
  "certificate (verify failed|has expired)|ssl routines@@Certificate / TLS problem"
  "call trace|kernel bug|soft lockup|hung_task|blocked for more than@@Kernel stalls or bugs"
)
check_logs() {
  step "Log scan"
  local total all="$EVID/all-problems.log"
  cat "$ERRLOG" "$KLOG" >"$all" 2>/dev/null                                     # one file to search
  total=$(wc -l <"$ERRLOG")
  info "$total error-level log lines in the last $HOURS h  (source: $( ((HAS_JOURNAL)) && echo journal || echo "${SYSLOG:-none}"))"
  if (( total > 1000 )); then add_finding WARN "Very noisy error log ($total errors in $HOURS h)" "See the top offenders below"
  elif (( total > 0 )); then good "Error volume is moderate ($total lines)"
  else good "No error-level log lines"; fi

  sub "What the logs are saying (plain English)"
  table_head "$(printf '%7s  %s' COUNT MEANING)"
  local p rx mean n hits=0
  for p in "${PATTERNS[@]}"; do
    rx=${p%%@@*}; mean=${p##*@@}                                                # split regex / meaning
    n=$(cnt "$rx" "$all")
    if (( n > 0 )); then
      hits=1
      if (( n >= 50 )); then printf '  %s%7d%s  %s\n' "$RED$B" "$n" "$R" "$mean"
      else printf '  %s%7d%s  %s\n' "$YEL" "$n" "$R" "$mean"; fi
    fi
  done
  (( hits )) || ok "None of the well-known problem patterns were found"

  local dns perm fd
  dns=$(cnt 'temporary failure in name resolution|name or service not known|could not resolve' "$all")
  (( dns >= 5 )) && add_finding WARN "DNS lookups failed $dns times in the logs" "Check step 8 (Network & DNS)"
  fd=$(cnt 'too many open files' "$all")
  (( fd > 0 )) && { add_finding WARN "A program hit 'too many open files' ($fd times)" "Raise LimitNOFILE in the service unit or ulimit -n"; FZ[limits]=$((FZ[limits]+1)); }
  perm=$(cnt 'permission denied' "$all")
  (( perm >= 50 )) && add_finding WARN "Many 'permission denied' errors ($perm)" "Check file ownership and SELinux/AppArmor (step 10)"

  if (( total > 0 )); then
    sub "Programs producing the most errors"
    table_head "$(printf '%7s  %s' COUNT PROGRAM)"
    awk '{for(i=2;i<=6&&i<=NF;i++) if ($i ~ /:$/ && $i !~ /^[0-9:.T+-]+:$/) {p=$i; sub(/\[[0-9]+\]:$/,"",p); sub(/:$/,"",p); print p; break}}' "$ERRLOG" | \
      sort | uniq -c | sort -rn | head -8 | awk '{printf "%7d  %s\n",$1,$2}' | table_rows

    sub "Most repeated error messages"
    table_head "$(printf '%7s  %s' COUNT MESSAGE)"
    awk '{p=4; for(i=2;i<=6&&i<=NF;i++) if ($i ~ /:$/ && $i !~ /^[0-9:.T+-]+:$/) {p=i+1; break}
          m=""; for(j=p;j<=NF;j++) m=m" "$j; gsub(/\[[0-9]+\]/,"",m); gsub(/0x[0-9a-fA-F]+/,"0x#",m); gsub(/[0-9]+/,"#",m); print substr(m,2,110)}' "$ERRLOG" | \
      sort | uniq -c | sort -rn | head -10 | awk '{c=$1; $1=""; printf "%7d %s\n",c,$0}' | table_rows
  fi
  note "Full extracts saved in: $EVID"
}

# ============================================================================
#  8. NETWORK & DNS
# ============================================================================
check_network() {
  step "Network & DNS"
  if has_cmd ip; then
    sub "Interfaces"
    ip -br addr 2>/dev/null | grep -v '^lo ' | table_rows                       # one line per interface
    local gw; gw=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')   # default gateway
    if [[ -z $gw ]]; then
      add_finding CRIT "No default gateway - this machine cannot reach other networks" "ip route add default via <gateway-ip>  (and fix the network config)"
    else
      kv "Default gateway" "$gw"
      if has_cmd ping; then
        if to 6 ping -c 2 -W 2 "$gw" >/dev/null 2>&1; then good "Gateway $gw answers ping"
        else add_finding WARN "Gateway $gw does not answer ping (could be blocked, or the link is broken)" "Check cable/VLAN/switch; ip -s link"; fi
      fi
    fi
    if ! ip -4 -o addr show scope global 2>/dev/null | grep -q inet; then
      add_finding CRIT "No interface has an IPv4 address" "Check DHCP / static IP config (netplan, NetworkManager: nmcli)"
    fi
  fi

  local inet=0
  if has_cmd ping; then
    if to 6 ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1 || to 6 ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
      good "Internet is reachable (ping 1.1.1.1 / 8.8.8.8)"; inet=1
    else
      add_finding WARN "Cannot ping the internet (1.1.1.1 / 8.8.8.8) - no route out or ICMP is blocked" "Check gateway, firewall, proxy"
    fi
  fi

  local ns; ns=$(awk '/^nameserver/{printf "%s ",$2}' /etc/resolv.conf 2>/dev/null)   # configured DNS servers
  kv "DNS servers" "${ns:-none configured}"
  if to 6 getent hosts debian.org >/dev/null 2>&1 || to 6 getent hosts redhat.com >/dev/null 2>&1; then
    good "DNS works (names resolve)"
  else
    if (( inet )); then add_finding CRIT "DNS is BROKEN - internet works by IP but names don't resolve" "Fix nameservers in /etc/resolv.conf (or resolvectl / nmcli)"
    else add_finding WARN "DNS lookups fail (may be caused by no internet access)" "Check /etc/resolv.conf"; fi
  fi

  if has_cmd ss; then
    sub "Listening ports"
    table_head "$(printf '%-6s %-28s %s' PROTO LOCAL-ADDRESS PROCESS)"
    ss -tulpn 2>/dev/null | tail -n +2 | awk '{p=$NF; if (p !~ /users/) p="-"; gsub(/users:\(\("|",.*$/,"",p); printf "%-6s %-28s %s\n",$1,$5,p}' | sort -u | head -15 | table_rows
  fi

  local fw="none"                                                               # firewall status
  if has_cmd firewall-cmd && [[ $(firewall-cmd --state 2>/dev/null) == running ]]; then fw="firewalld (running)"
  elif has_cmd ufw && ufw status 2>/dev/null | grep -q 'Status: active'; then fw="ufw (active)"
  elif has_cmd nft && (( $(nft list ruleset 2>/dev/null | grep -c 'chain') > 0 )); then fw="nftables rules loaded"
  elif has_cmd iptables && (( $(iptables -S 2>/dev/null | grep -c '^-A') > 0 )); then fw="iptables rules loaded"
  fi
  if [[ $fw == none ]]; then
    if (( ! IS_ROOT )); then skip "firewall status needs root"
    elif has_cmd firewall-cmd; then add_finding WARN "No firewall is active" "systemctl enable --now firewalld" "!systemctl enable --now firewalld"
    elif has_cmd ufw; then add_finding WARN "No firewall is active" "ufw allow 22/tcp && ufw enable" "!ufw allow 22/tcp && ufw --force enable"
    else add_finding WARN "No firewall is active" "Install and enable firewalld or ufw"; fi
  else
    good "Firewall: $fw"
  fi

  if has_cmd timedatectl; then                                                  # clock sync
    local sync; sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    [[ -z $sync ]] && sync=$(timedatectl 2>/dev/null | awk -F: '/synchronized/{gsub(/ /,"",$2); print $2}')
    if [[ $sync == yes ]]; then good "Clock is synchronized (NTP)"
    else
      local svc=""; for s in chronyd chrony systemd-timesyncd ntpd ntp; do systemctl list-unit-files "$s.service" 2>/dev/null | grep -q "^$s" && { svc=$s; break; }; done
      add_finding WARN "Clock is NOT synchronized - wrong time breaks logins (Kerberos/FreeIPA), TLS and logs" \
        "systemctl restart ${svc:-chronyd}; chronyc tracking" "${svc:+systemctl restart $svc}"
    fi
  fi
  local ct; ct=$(cnt 'nf_conntrack: table full|dropping packet' "$KLOG")
  (( ct > 0 )) && { add_finding CRIT "Connection tracking table is full - network packets are being DROPPED ($ct)" "sysctl -w net.netfilter.nf_conntrack_max=262144"; FZ[limits]=$((FZ[limits]+2)); }
  return 0
}

# ============================================================================
#  9. SYSTEM FREEZES & HANGS
# ============================================================================
psi() {                                            # read Pressure Stall Info: FILE -> "some_avg60 full_avg60"
  awk '{for(i=2;i<=NF;i++){split($i,a,"="); if(a[1]=="avg60") v[$1]=a[2]}} END{printf "%d %d\n", v["some"]+0, v["full"]+0}' "$1" 2>/dev/null
}
check_freeze() {
  step "System freezes & hangs"
  local n

  # -- hung tasks: processes stuck > 120 s --
  n=$(cnt 'blocked for more than [0-9]+ seconds' "$KLOG")
  if (( n > 0 )); then
    add_finding CRIT "$n 'hung task' event(s): processes were frozen for 2+ minutes waiting on the kernel (almost always disk or NFS)" \
      "Check disk health (step 5), iostat -x, and NFS mounts"; FZ[io]=$((FZ[io]+3))
    sub "Hung tasks"
    grep -Eo 'task [^ ]+ blocked for more than [0-9]+ seconds' "$KLOG" | sed -E 's/:[0-9]+ blocked/ blocked/' | sort | uniq -c | sort -rn | head -5 | table_rows
  else good "No hung-task (frozen process) events"; fi

  # -- lockups / RCU stalls --
  n=$(cnt 'soft lockup|hard lockup|watchdog: BUG|rcu_(sched|preempt).*stall|rcu: INFO' "$KLOG")
  if (( n > 0 )); then
    add_finding CRIT "$n CPU lockup / RCU stall event(s): a CPU got stuck in the kernel - the classic 'whole system freezes'" \
      "Usually a driver/firmware/kernel bug or overloaded VM host: update kernel, firmware, VM tools"; FZ[kernel]=$((FZ[kernel]+4))
    grep -Ei 'soft lockup|hard lockup|watchdog: BUG|rcu.*stall' "$KLOG" | tail -3 | cut -c1-160 | table_rows
  else good "No CPU lockups or RCU stalls"; fi

  # -- processes stuck in D state right now --
  local dproc; dproc=$(ps -eo state,pid,wchan:28,comm --no-headers 2>/dev/null | awk '$1=="D"')
  if [[ -n $dproc ]]; then
    n=$(wc -l <<<"$dproc")
    add_finding WARN "$n process(es) stuck right now in uninterruptible wait (D state) - waiting for disk/NFS" "See wait channel below"; FZ[io]=$((FZ[io]+1))
    table_head "$(printf '%-5s %-8s %-28s %s' STATE PID WAITING-IN COMMAND)"
    printf '%s\n' "$dproc" | head -8 | awk '{printf "%-5s %-8s %-28s %s\n",$1,$2,$3,$4}' | table_rows
    grep -qiE 'nfs|rpc' <<<"$dproc" && FZ[nfs]=$((FZ[nfs]+2))
  else good "No processes stuck in D state right now"; fi

  # -- pressure stall information (kernel 4.20+) --
  if [[ -r /proc/pressure/cpu ]]; then
    sub "Pressure stall (% of time tasks waited in the last 60 s)"
    local r s f
    for r in cpu memory io; do
      read -r s f < <(psi "/proc/pressure/$r")
      meter "$r pressure" "$s" "full stall: ${f}%"
      if (( s >= 40 || f >= 10 )); then
        add_finding CRIT "Severe $r pressure: tasks were stalled ${s}% of the time (full stall ${f}%)" "This resource is starving the system"
        case $r in cpu) FZ[cpu]=$((FZ[cpu]+2));; memory) FZ[mem]=$((FZ[mem]+3));; io) FZ[io]=$((FZ[io]+3));; esac
      elif (( s >= 15 )); then
        add_finding WARN "Noticeable $r pressure (${s}% stall)" ""
        case $r in cpu) FZ[cpu]=$((FZ[cpu]+1));; memory) FZ[mem]=$((FZ[mem]+1));; io) FZ[io]=$((FZ[io]+1));; esac
      fi
    done
  else
    skip "Pressure stall info (needs kernel 4.20+)"
  fi

  # -- memory thrashing --
  if (( VM_SI + VM_SO >= 1000 )); then
    add_finding CRIT "Memory THRASHING: swapping ${VM_SI} KB/s in, ${VM_SO} KB/s out - the system freezes while it shuffles memory to disk" \
      "Stop the memory hog (step 3) or add RAM"; FZ[mem]=$((FZ[mem]+3))
  elif (( VM_SI + VM_SO >= 100 )); then
    add_finding WARN "Active swapping (${VM_SI}/${VM_SO} KB/s in/out)" "Memory is tight"; FZ[mem]=$((FZ[mem]+1))
  else good "No memory thrashing"; fi
  (( OOM_N > 0 )) && FZ[mem]=$((FZ[mem]+1))
  if ! systemctl is-active -q systemd-oomd 2>/dev/null && ! pgrep -x earlyoom >/dev/null 2>&1; then
    note "No userspace OOM daemon (systemd-oomd / earlyoom): low-memory freezes can last minutes before the kernel reacts"
  fi

  # -- per-disk latency --
  if (( QUICK )); then skip "iostat disk latency (quick mode)"
  elif has_cmd iostat; then
    run_spin "Measuring disk latency for 3 seconds..." iostat -dx 3 2
    local slow
    slow=$(awk '/^Device/{split("",rows); n=0; for(i=1;i<=NF;i++) h[$i]=i; next}
                NF>3 {rows[++n]=$0}
                END{for(k=1;k<=n;k++){split(rows[k],c," "); u=("%util" in h)?c[h["%util"]]:0;
                    aw=0; if("await" in h) aw=c[h["await"]]; if("r_await" in h && c[h["r_await"]]>aw) aw=c[h["r_await"]]; if("w_await" in h && c[h["w_await"]]>aw) aw=c[h["w_await"]];
                    if (u+0>=90 || aw+0>=100) printf "%s util=%s%% latency=%sms\n", c[1], u, aw}}' <<<"$SPIN_OUT")
    if [[ -n $slow ]]; then
      add_finding WARN "Disk(s) saturated or slow: $(echo $slow)" "Find the IO heavy process: iotop -o (or pidstat -d 2)"; FZ[io]=$((FZ[io]+2))
    else good "Disk latency and utilization look normal"; fi
  else
    skip "iostat disk latency - install 'sysstat' to enable"
  fi
  n=$(cnt 'scsi.*timeout|task abort|blk_update_request|nvme.*(timeout|reset)|ata[0-9.]+: (hard resetting|SRST failed)' "$KLOG")
  (( n > 0 )) && { add_finding CRIT "$n storage timeout/reset event(s): the disk stopped answering for a while = system freeze" "Check disk/controller/SAN path, multipath, VM datastore latency"; FZ[io]=$((FZ[io]+3)); }

  # -- previous boot: clean or crash? --
  if (( HAS_JOURNAL )); then
    local nb prev
    nb=$(journalctl --list-boots --no-pager 2>/dev/null | wc -l)              # how many boots the journal remembers
    if (( nb > 1 )); then
      prev=$(journalctl -b -1 -n 40 --no-pager -q -o short-iso 2>/dev/null)  # last lines of the previous boot
      if grep -Eq 'systemd-shutdown|Reached target.*(Shutdown|Power-Off|Reboot|Final Step|System Reboot)|Journal stopped|Stopping .*Journal|reboot: (Restarting|Power down)|Shutting down' <<<"$prev"; then
        good "Previous boot ended with a clean shutdown/reboot"
      else
        printf '%s\n' "$prev" >"$EVID/previous-boot-last-lines.log"
        add_finding CRIT "The previous boot ended WITHOUT a clean shutdown - crash, hard freeze, power loss or forced reset" \
          "Read what happened just before it died: $EVID/previous-boot-last-lines.log"; FZ[kernel]=$((FZ[kernel]+2))
        sub "Last log lines before the previous boot died"
        tail -6 <<<"$prev" | cut -c1-150 | table_rows
      fi
    else
      add_finding WARN "The journal only keeps the current boot, so crashes from before the last reboot are invisible" \
        "Make the journal persistent" "mkdir -p /var/log/journal && systemd-tmpfiles --create --prefix /var/log/journal && systemctl restart systemd-journald"
    fi
  fi
  n=$(cnt 'watchdog did not stop|watchdog timeout|Watchdog timer expired|hardware watchdog' "$KLOG")
  (( n > 0 )) && { add_finding WARN "Watchdog events ($n): the system was reset by a watchdog after it stopped responding" ""; FZ[kernel]=$((FZ[kernel]+2)); }
  if [[ -d /var/crash ]] && [[ -n $(ls -A /var/crash 2>/dev/null) ]]; then
    add_finding WARN "Crash dumps exist in /var/crash - the system (or an app) crashed before" "ls -la /var/crash  (kernel dumps: analyse with 'crash')"; FZ[kernel]=$((FZ[kernel]+1))
    ls -lt /var/crash 2>/dev/null | head -5 | table_rows
  fi

  # -- stuck network mounts --
  local m stuck=""
  while read -r m; do
    to 5 stat -t "$m" >/dev/null 2>&1 || stuck="$stuck $m"                     # a mount that does not answer within 5 s
  done < <(awk '$3 ~ /^(nfs|nfs4|cifs|smb3|smbfs|fuse\.sshfs|glusterfs|ceph)$/ {print $2}' /proc/mounts)
  if [[ -n $stuck ]]; then
    add_finding CRIT "Network mount(s) not responding:$stuck - anything touching them (even 'ls' or 'df') hangs" \
      "Fix the file server/network, or: umount -f -l <mount>"; FZ[nfs]=$((FZ[nfs]+4))
  else good "No hanging network mounts (NFS/CIFS)"; fi

  # -- kernel limits --
  local thr tmax pmax fdu fdm ctc ctm
  thr=$(awk '{split($4,a,"/"); print a[2]}' /proc/loadavg)                    # total threads now
  thr=$(num "$thr")
  tmax=$(num "$(cat /proc/sys/kernel/threads-max 2>/dev/null)"); pmax=$(num "$(cat /proc/sys/kernel/pid_max 2>/dev/null)")   # kernel limits
  (( pmax > 0 && tmax > pmax )) && tmax=$pmax
  if (( tmax > 0 )); then                                                       # only if the kernel exposes the limit
    meter "Threads" $(( thr * 100 / tmax )) "$thr of $tmax"
    (( thr * 100 / tmax >= 80 )) && { add_finding CRIT "Process/thread table almost full ($thr of $tmax) - new programs can't start (fork fails)" "Find the process spawning threads: ps -eLf | awk '{print \$2}' | uniq -c | sort -rn | head"; FZ[limits]=$((FZ[limits]+3)); }
  fi
  read -r fdu _ fdm < <(cat /proc/sys/fs/file-nr 2>/dev/null)                    # open file handles
  fdu=$(num "${fdu:-}"); fdm=$(num "${fdm:-}")
  if (( fdm > 0 && fdm < 9000000000000000000 )); then                          # skip "unlimited" style huge values
    meter "Open files" $(( fdu * 100 / fdm )) "$fdu of $fdm"
    (( fdu * 100 / fdm >= 80 )) && { add_finding CRIT "System-wide open files almost exhausted ($fdu of $fdm)" "sysctl -w fs.file-max=<bigger>"; FZ[limits]=$((FZ[limits]+2)); }
  fi
  if [[ -r /proc/sys/net/netfilter/nf_conntrack_count ]]; then
    ctc=$(num "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)"); ctm=$(num "$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)")
    (( ctm > 0 )) && meter "Conntrack" $(( ctc * 100 / ctm )) "$ctc of $ctm tracked connections"
  fi

  # -- clock problems --
  n=$(cnt 'clocksource.*unstable|Marking clocksource|time jumped|clock skew' "$KLOG")
  (( n > 0 )) && { add_finding WARN "Unstable clock source ($n): timers misbehave, can look like short freezes" "On VMs install guest tools; check kernel clocksource"; FZ[cpu]=$((FZ[cpu]+1)); }

  # -- verdict --
  sub "Freeze / hang verdict"
  declare -A FZ_TXT=(
    [io]="STORAGE: disks are slow, failing or timing out - everything freezes while waiting for the disk"
    [mem]="MEMORY: RAM runs out, the system swaps/thrashes and the OOM killer steps in"
    [cpu]="CPU: overloaded CPUs or an overcommitted VM host starve everything else"
    [kernel]="KERNEL/DRIVER: lockups, crashes or unclean resets point to a kernel, driver or firmware bug"
    [nfs]="NETWORK STORAGE: an NFS/CIFS server stops answering and every process touching it hangs"
    [hw]="HARDWARE: overheating or CPU/RAM errors (MCE/EDAC) are destabilizing the machine"
    [limits]="LIMITS: process, file or connection tables are full, so new work cannot start"
  )
  local k rank=0 maxs
  maxs=$(for k in "${!FZ[@]}"; do echo "${FZ[$k]}"; done | sort -rn | head -1)  # strongest evidence score
  if (( $(num "$maxs") == 0 )); then
    printf '  %s%s No signs of freezes or hangs in the last %s h.%s\n' "$GRN$B" "$S_OK" "$HOURS" "$R"
  else
    while read -r s k; do
      (( s == 0 )) && continue
      rank=$((rank+1))
      local col=$YEL; (( rank == 1 )) && col=$RED
      printf '  %s#%d%s %s%s%s\n' "$col$B" "$rank" "$R" "$col" "${FZ_TXT[$k]}" "$R"
      printf '     evidence %s%s%s%s%s\n' "$col" "$(rep "$BAR_F" $(( s > 10 ? 10 : s )))" "$GRY" "$(rep "$BAR_E" $(( s > 10 ? 0 : 10 - s )))" "$R"
    done < <(for k in "${!FZ[@]}"; do echo "${FZ[$k]} $k"; done | sort -rn)
  fi
  return 0
}

# ============================================================================
# 10. SECURITY & UPDATES
# ============================================================================
check_security() {
  step "Security & updates"
  local fails top rootok sudof
  fails=$(cnt 'failed password|invalid user|authentication failure' "$AUTHL") # failed logins
  if (( fails >= 500 )); then
    add_finding CRIT "Brute-force attack: $fails failed logins in $HOURS h" "Install fail2ban, disable password SSH login (keys only)"
  elif (( fails >= 30 )); then
    add_finding WARN "$fails failed login attempts in $HOURS h" "Consider fail2ban and key-only SSH"
  else good "Failed logins: $fails (normal)"; fi
  if (( fails > 0 )); then
    sub "Top source IPs of failed logins"
    grep -Ei 'failed password|invalid user' "$AUTHL" | grep -Eo 'from [0-9a-fA-F:.]+' | awk '{print $2}' | sort | uniq -c | sort -rn | head -5 | table_rows
  fi
  rootok=$(cnt 'accepted .* for root from' "$AUTHL")
  (( rootok > 0 )) && add_finding WARN "Direct root SSH logins happened ($rootok)" "Set 'PermitRootLogin no' in /etc/ssh/sshd_config, use sudo"
  sudof=$(cnt 'sudo:.*(incorrect password|not in sudoers|authentication failure)' "$AUTHL")
  (( sudof > 0 )) && add_finding WARN "$sudof failed sudo attempt(s)" "grep sudo $AUTHL"

  if has_cmd getenforce; then                                                   # SELinux (RedHat family)
    local se den; se=$(getenforce 2>/dev/null)
    kv "SELinux" "$se"
    if [[ $se != Disabled ]] && (( IS_ROOT )); then
      if has_cmd ausearch; then den=$(ausearch -m AVC,USER_AVC -ts today 2>/dev/null | grep -c 'type=AVC')
      else den=$(grep -c 'avc:  denied' /var/log/audit/audit.log 2>/dev/null); fi
      den=$(num "$den")
      if (( den > 0 )); then
        add_finding WARN "SELinux blocked something $den time(s) today - a service may be failing because of it" "ausearch -m AVC -ts today | audit2why"
        grep 'avc:  denied' /var/log/audit/audit.log 2>/dev/null | grep -Eo 'comm="[^"]+"' | sort | uniq -c | sort -rn | head -5 | table_rows
      else good "No SELinux denials today"; fi
    fi
  fi
  local aa; aa=$(cnt 'apparmor="DENIED"' "$KLOG")                               # AppArmor (Debian family)
  if (( aa > 0 )); then
    add_finding WARN "AppArmor blocked something $aa time(s)" "Check the profile shown below (aa-status, /etc/apparmor.d)"
    grep -Eo 'profile="[^"]+"' "$KLOG" | sort | uniq -c | sort -rn | head -5 | table_rows
  fi

  if (( QUICK )); then skip "pending updates (quick mode)"
  else
    local up=0 sec=0 secfix=""
    case $PKG in
      apt-get)
        run_spin "Checking pending updates (apt)..." bash -c 'apt list --upgradable 2>/dev/null'
        up=$(grep -c 'upgradable' <<<"$SPIN_OUT"); sec=$(grep -c -- '-security' <<<"$SPIN_OUT")
        local stamp=/var/lib/apt/periodic/update-success-stamp; [[ -f $stamp ]] || stamp=/var/cache/apt/pkgcache.bin
        [[ -f $stamp ]] && note "Package lists last refreshed: $(date -r "$stamp" '+%Y-%m-%d %H:%M')  (run 'apt update' for fresh numbers)"
        if has_cmd unattended-upgrade; then secfix="unattended-upgrade -v"
        else secfix="apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade"; fi ;;
      dnf|yum)
        run_spin "Checking pending updates ($PKG)..." to 120 "$PKG" -q check-update
        up=$(grep -cE '^[[:alnum:]_.+-]+\.(x86_64|noarch|aarch64|i686|ppc64le|s390x)[[:space:]]' <<<"$SPIN_OUT")
        run_spin "Checking security advisories ($PKG)..." to 120 "$PKG" -q updateinfo list --security
        sec=$(grep -cE 'Sec|RHSA|ALSA|RLSA|ELSA|FEDORA' <<<"$SPIN_OUT")
        secfix="$PKG -y upgrade --security" ;;
      zypper)
        run_spin "Checking pending updates (zypper)..." to 120 zypper -q lu
        up=$(grep -c '^v ' <<<"$SPIN_OUT"); secfix="zypper -n patch --category security" ;;
    esac
    up=$(num "$up"); sec=$(num "$sec")
    if (( sec > 0 )); then add_finding WARN "$sec security update(s) pending ($up updates total)" "$secfix   (services may restart)" "$secfix"
    elif (( up > 0 )); then info "$up normal update(s) pending, no security updates"
    else good "System is up to date"; fi
  fi

  if [[ -f /var/run/reboot-required ]]; then                                    # Debian reboot flag
    add_finding WARN "A reboot is required to finish updates ($(tr '\n' ' ' </var/run/reboot-required.pkgs 2>/dev/null | cut -c1-60))" "Plan a reboot"
  elif has_cmd needs-restarting && (( IS_ROOT )); then                          # RedHat reboot check
    needs-restarting -r >/dev/null 2>&1 || add_finding WARN "A reboot is required to load updated core packages (kernel/glibc/systemd)" "Plan a reboot"
  fi

  if has_cmd openssl; then                                                      # expiring certificates
    local c exp_n=0 soon_n=0 nf=0
    while IFS= read -r c; do
      openssl x509 -in "$c" -noout 2>/dev/null || continue                      # not a certificate (e.g. a key)
      nf=$((nf+1))
      if ! openssl x509 -in "$c" -noout -checkend 0 >/dev/null 2>&1; then
        add_finding CRIT "Certificate EXPIRED: $c" "Renew it (certbot renew / ipa-getcert / your CA)"; exp_n=$((exp_n+1))
      elif ! openssl x509 -in "$c" -noout -checkend $((30*86400)) >/dev/null 2>&1; then
        add_finding WARN "Certificate expires within 30 days: $c ($(openssl x509 -in "$c" -noout -enddate | cut -d= -f2))" "Renew it soon"; soon_n=$((soon_n+1))
      fi
    done < <(find /etc/ssl /etc/pki /etc/letsencrypt/live /etc/nginx /etc/httpd /etc/apache2 /etc/ipa -maxdepth 4 \
               \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' \) \
               -not -path '*/ca-certificates/*' -not -path '/etc/ssl/certs/*' -not -path '*/ca-trust/*' \
               -not -path '*/pki/tls/certs/ca-bundle*' -not -name '*key*' 2>/dev/null | head -300)
    (( exp_n == 0 && soon_n == 0 )) && good "Certificates checked: $nf, none expiring within 30 days"
  fi
}

# ============================================================================
#  SUMMARY DASHBOARD
# ============================================================================
SCORE=100
summary() {
  SCORE=$(( 100 - N_CRIT * 15 - N_WARN * 5 )); (( SCORE < 0 )) && SCORE=0    # health score
  local col label w=70
  if   (( SCORE >= 85 )); then col=$GRN; label="HEALTHY";         (( UTF )) && label="HEALTHY ✅"
  elif (( SCORE >= 60 )); then col=$YEL; label="NEEDS ATTENTION"; (( UTF )) && label="NEEDS ATTENTION 🔶"
  else                         col=$RED; label="CRITICAL";        (( UTF )) && label="CRITICAL 🔥"; fi

  echo; echo
  printf '%s%s [SUMMARY] HEALTH REPORT %s%s\n' "$(c256 201)$B" "$(rep "$HL" 3)" "$(rep "$HL" 40)" "$R"
  echo
  printf '  %s%s%s%s\n' "$col" "$DB_TL" "$(rep "$DB_H" "$w")" "$R"           # open-sided box (emoji widths vary by terminal)
  printf '  %s%s%s   %sHEALTH SCORE  %3d / 100%s   %s%s%s\n' "$col" "$DB_V" "$R" "$col$B" "$SCORE" "$R" "$col$B" "$label" "$R"
  printf '  %s%s%s   %s%s%s%s%s\n' "$col" "$DB_V" "$R" "$col" "$(rep "$BAR_F" $((SCORE*50/100)))" "$GRY" "$(rep "$BAR_E" $((50 - SCORE*50/100)))" "$R"
  printf '  %s%s%s   %s%s %d critical%s   %s%s %d warnings%s   %s%s %d passed%s\n' "$col" "$DB_V" "$R" \
    "$RED$B" "$S_FAIL" "$N_CRIT" "$R" "$YEL$B" "$S_WARN" "$N_WARN" "$R" "$GRN$B" "$S_OK" "$N_OK" "$R"
  printf '  %s%s%s%s\n' "$col" "$DB_BL" "$(rep "$DB_H" "$w")" "$R"

  if (( N_CRIT + N_WARN > 0 )); then
    echo; printf '  %s%s FIX THESE FIRST%s\n' "$ORG$B" "$S_INFO" "$R"
    local i shown=0 sev
    for sev in CRIT WARN; do                                                    # criticals first, then warnings
      for ((i=0; i<${#F_SEV[@]}; i++)); do
        [[ ${F_SEV[i]} == "$sev" ]] || continue
        shown=$((shown+1)); (( shown > 15 )) && break 2
        if [[ $sev == CRIT ]]; then printf '  %s%2d. %s %-8s%s %s\n' "$RED$B" "$shown" "$S_FAIL" "[${F_AREA[i]%% *}]" "$R" "${F_MSG[i]}"
        else printf '  %s%2d. %s %-8s%s %s\n' "$YEL$B" "$shown" "$S_WARN" "[${F_AREA[i]%% *}]" "$R" "${F_MSG[i]}"; fi
        [[ -n ${F_HINT[i]} ]] && printf '        %s%s %s%s\n' "$DIM" "$S_INFO" "${F_HINT[i]}" "$R"
      done
    done
    (( N_CRIT + N_WARN > 15 )) && note "...and $(( N_CRIT + N_WARN - 15 )) more - see the full report"
  else
    echo; printf '  %s%s Everything looks good. Nothing to fix.%s\n' "$GRN$B" "$S_OK" "$R"
  fi
  local fixable=0 i; for ((i=0; i<${#F_CMD[@]}; i++)); do [[ -n ${F_CMD[i]} ]] && fixable=$((fixable+1)); done
  (( fixable > 0 && ! FIX_MODE )) && { echo; info "$fixable problem(s) can be fixed automatically - re-run with ${B}--fix${R}"; }
}

# ============================================================================
#  FIX MODE
# ============================================================================
run_fixes() {
  echo
  printf '%s%s [AUTO-FIX] SAFE FIXES %s%s\n' "$(c256 46)$B" "$(rep "$HL" 3)" "$(rep "$HL" 41)" "$R"
  if (( ! IS_ROOT )); then printf '  %s%s Fixes need root - re-run with sudo.%s\n' "$YEL" "$S_WARN" "$R"; return; fi
  if [[ ! -r /dev/tty ]]; then printf '  %s%s No keyboard (tty) available to confirm fixes - skipped.%s\n' "$YEL" "$S_WARN" "$R"; return; fi
  local i cmd danger rc any=0
  declare -A seen=()
  for ((i=0; i<${#F_CMD[@]}; i++)); do
    cmd=${F_CMD[i]}; [[ -z $cmd ]] && continue                                  # nothing automatic for this finding
    [[ -n ${seen[$cmd]:-} ]] && continue; seen[$cmd]=1                          # each command only once
    any=1; danger=0
    [[ $cmd == '!'* ]] && { danger=1; cmd=${cmd#!}; }                           # '!' prefix = needs double confirmation
    echo
    printf '  %sProblem:%s %s\n' "$B" "$R" "${F_MSG[i]}"
    printf '  %sCommand:%s %s%s%s\n' "$B" "$R" "$CYN" "$cmd" "$R"
    if ! ask "Run this fix?"; then printf '  %s%s skipped by user%s\n' "$GRY" "$S_DOT" "$R"; continue; fi
    if (( danger )) && ! ask "This changes firewall/network access. Are you SURE?"; then
      printf '  %s%s skipped by user%s\n' "$GRY" "$S_DOT" "$R"; continue
    fi
    bash -c "$cmd" 2>&1 | sed 's/^/      /'                                     # run it, indent its output
    rc=${PIPESTATUS[0]}
    if (( rc == 0 )); then ok "Done: $cmd"
    else printf '  %s%s Failed (exit %d): %s%s\n' "$RED" "$S_FAIL" "$rc" "$cmd" "$R"; fi
  done
  (( any )) || info "No automatic fixes available - follow the hints above."
}

# ============================================================================
#  REPORTS (TXT + HTML)
# ============================================================================
esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }   # make text safe for HTML

build_html() {
  local scol="#3fb950" i sev cls titles
  (( SCORE < 85 )) && scol="#d29922"; (( SCORE < 60 )) && scol="#f85149"
  titles=$(IFS='|'; echo "${STEP_TITLES[*]}")
  cat <<EOF
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Linux Doctor - $(esc "$HOST")</title>
<style>
:root{--bg:#0d1117;--card:#161b22;--line:#30363d;--fg:#e6edf3;--mut:#8b949e;--red:#f85149;--yel:#d29922;--grn:#3fb950;--acc:#a371f7}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
.wrap{max-width:1100px;margin:auto;padding:24px 16px}
.hero{background:linear-gradient(120deg,#0b3d5c,#3b1f6b 60%,#6b1f5c);border-radius:16px;padding:28px;display:flex;gap:28px;align-items:center;flex-wrap:wrap}
.hero h1{margin:0;font-size:30px;letter-spacing:4px}.hero p{margin:4px 0;color:#d0d7de}
.ring{--p:$SCORE;width:130px;height:130px;border-radius:50%;background:conic-gradient($scol calc(var(--p)*1%),#ffffff22 0);display:grid;place-items:center;flex:none}
.ring div{width:104px;height:104px;border-radius:50%;background:#1b1f2a;display:grid;place-items:center;font-size:30px;font-weight:700}
.ring small{display:block;font-size:12px;color:var(--mut);font-weight:400;text-align:center}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:18px 0}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px}.card b{font-size:26px;display:block}
h2{margin:28px 0 10px;font-size:19px;color:var(--acc)}
table{width:100%;border-collapse:collapse;background:var(--card);border-radius:12px;overflow:hidden}
th,td{padding:9px 12px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}th{color:var(--mut);font-weight:600;font-size:13px}
.b{display:inline-block;padding:2px 8px;border-radius:99px;font-size:12px;font-weight:700}.CRIT{background:#f8514933;color:var(--red)}.WARN{background:#d2992233;color:var(--yel)}
code{background:#0d1117;border:1px solid var(--line);border-radius:6px;padding:1px 6px;font-size:12.5px;word-break:break-all}
.m{display:grid;grid-template-columns:minmax(120px,260px) 1fr 52px;gap:10px;align-items:center;margin:6px 0;font-size:13px}
.bar{height:10px;background:#21262d;border-radius:99px;overflow:hidden}.bar i{display:block;height:100%;border-radius:99px}
details{background:var(--card);border:1px solid var(--line);border-radius:12px;margin:8px 0}summary{cursor:pointer;padding:12px 14px;font-weight:600}
pre{margin:0;padding:12px 14px;overflow-x:auto;font:12.5px/1.45 ui-monospace,Consolas,monospace;color:#c9d1d9;border-top:1px solid var(--line)}
footer{color:var(--mut);text-align:center;margin:30px 0 10px;font-size:13px}
</style></head><body><div class="wrap">
<div class="hero"><div class="ring"><div>$SCORE<small>/ 100</small></div></div>
<div><h1>LINUX DOCTOR</h1><p><b>$(esc "$HOST")</b> &middot; $(esc "$OS_NAME") &middot; kernel $(esc "$(uname -r)")</p>
<p>Report of $(date '+%Y-%m-%d %H:%M %Z') &middot; logs of the last $HOURS h &middot; ran in $((SECONDS-START_SEC)) s</p>
<p>Crafted with love by $(esc "$AUTHOR")</p></div></div>
<div class="cards"><div class="card"><b style="color:var(--red)">$N_CRIT</b>critical</div><div class="card"><b style="color:var(--yel)">$N_WARN</b>warnings</div>
<div class="card"><b style="color:var(--grn)">$N_OK</b>checks passed</div><div class="card"><b>$(esc "$FAMILY")</b>distro family</div></div>
<h2>Fix these first</h2>
EOF
  if (( ${#F_SEV[@]} == 0 )); then echo "<p>Everything looks good. Nothing to fix.</p>"
  else
    echo "<table><tr><th>Severity</th><th>Area</th><th>Problem</th><th>How to fix</th></tr>"
    for sev in CRIT WARN; do
      for ((i=0; i<${#F_SEV[@]}; i++)); do
        [[ ${F_SEV[i]} == "$sev" ]] || continue
        printf '<tr><td><span class="b %s">%s</span></td><td>%s</td><td>%s</td><td>%s</td></tr>\n' "$sev" \
          "$([[ $sev == CRIT ]] && echo CRITICAL || echo WARNING)" "$(esc "${F_AREA[i]}")" "$(esc "${F_MSG[i]}")" \
          "$([[ -n ${F_HINT[i]} ]] && echo "<code>$(esc "${F_HINT[i]}")</code>")"
      done
    done
    echo "</table>"
  fi
  echo "<h2>Gauges</h2>"
  for ((i=0; i<${#M_LABEL[@]}; i++)); do
    local v=${M_VAL[i]} c="var(--grn)"; (( v >= 70 )) && c="var(--yel)"; (( v >= 90 )) && c="var(--red)"
    printf '<div class="m"><span>%s</span><div class="bar"><i style="width:%d%%;background:%s"></i></div><b>%d%%</b></div>\n' \
      "$(esc "${M_LABEL[i]}")" "$(( v > 100 ? 100 : v ))" "$c" "$v"
  done
  echo "<h2>Full details per check</h2>"
  awk -v titles="$titles" '                                                     # split the text report into collapsible sections
    BEGIN { n = split(titles, T, "|"); open = 0 }
    {
      line = $0; gsub(/&/, "\\&amp;", line); gsub(/</, "\\&lt;", line); gsub(/>/, "\\&gt;", line)
      if (line ~ /^(━━━|===) \[[0-9]+\/[0-9]+\]/ && match(line, /\[[0-9]+\/[0-9]+\]/)) {   # a step header line
        num = substr(line, RSTART + 1, index(substr(line, RSTART), "/") - 2) + 0
        if (open) print "</pre></details>"
        printf "<details%s><summary>%d. %s</summary><pre>\n", (num == 1 ? " open" : ""), num, T[num]; open = 1; next
      }
      if (line ~ /\[SUMMARY\]/)  { if (open) print "</pre></details>"; print "<details><summary>Summary (text)</summary><pre>"; open = 1; next }
      if (line ~ /\[AUTO-FIX\]/) { if (open) print "</pre></details>"; print "<details open><summary>Fixes applied</summary><pre>"; open = 1; next }
      if (open) print line
    }
    END { if (open) print "</pre></details>" }' "$TXT"
  cat <<EOF
<footer>Linux Doctor v$VERSION &middot; Crafted with love by $(esc "$AUTHOR")<br>Evidence folder: $(esc "$EVID")</footer>
</div></body></html>
EOF
}

finish() {
  echo
  printf '  %sFinished in %d s.%s\n' "$GRY" $((SECONDS - START_SEC)) "$R"
  exec 1>&3                                        # stop copying to the raw file (closes tee's input)
  if [[ -n $TEE_PID ]]; then wait "$TEE_PID" 2>/dev/null || sleep 1; else sleep 1; fi   # let tee write its last bytes
  sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g; s/\r//g' "$RAW" >"$TXT"   # plain-text report = screen output without colors
  build_html >"$HTML"                              # styled HTML report
  local w=74
  echo
  printf '  %s%s%s%s%s\n' "$PNK" "$BX_TL" "$(rep "$BX_H" "$w")" "$BX_TR" "$R"
  printf '  %s%s%s %sReports saved%s\n' "$PNK" "$BX_V" "$R" "$B" "$R"
  printf '  %s%s%s   TXT : %s\n' "$PNK" "$BX_V" "$R" "$TXT"
  printf '  %s%s%s   HTML: %s\n' "$PNK" "$BX_V" "$R" "$HTML"
  printf '  %s%s%s   Evidence: %s\n' "$PNK" "$BX_V" "$R" "$EVID"
  printf '  %s%s%s %sCrafted with love by %s%s\n' "$PNK" "$BX_V" "$R" "$GRY" "$AUTHOR" "$R"
  printf '  %s%s%s%s%s\n' "$PNK" "$BX_BL" "$(rep "$BX_H" "$w")" "$BX_BR" "$R"
  echo
}

# ============================================================================
#  MAIN
# ============================================================================
banner                                             # logo, credit, run info
echo
run_spin "Reading system logs (last $HOURS h)..." collect_logs   # gather log extracts once
info "Logs collected: $(wc -l <"$KLOG") kernel lines, $(wc -l <"$ERRLOG") error lines, $(wc -l <"$AUTHL") auth lines"
check_overview                                     # 1
check_cpu                                          # 2
check_memory                                       # 3
check_disk                                         # 4
check_hardware                                     # 5
check_services                                     # 6
check_logs                                         # 7
check_network                                      # 8
check_freeze                                       # 9
check_security                                     # 10
summary                                            # score + fix-first list
(( FIX_MODE )) && run_fixes                        # optional fixes
finish                                             # write TXT + HTML, show where
# exit code: 2 = critical problems, 1 = warnings only, 0 = healthy (handy for monitoring/cron)
if (( N_CRIT > 0 )); then exit 2; elif (( N_WARN > 0 )); then exit 1; else exit 0; fi
