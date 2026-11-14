#!/bin/bash

# dynamic message of the day
# Robert Tulke, rt@debian.sh
# Multi-distribution MOTD script with automatic dependency management

## version
VERSION="dynmotd v1.19.5"

## configuration and logfile
MAINLOG="/root/.dynmotd/maintenance.log"
ENVFILE="/root/.dynmotd/environment.cfg"
DYNMOTDDIR="/root/.dynmotd"

## install path
DYNMOTD_INSTALL_PATH="/usr/local/bin"     # install destination (no trailing slash)
DYNMOTD_PROFILE="/etc/profile.d/motd.sh"  # profile.d hook that loads dynmotd
DYNMOTD_FILENAME="dynmotd"                # binary name

## enable / disable information sections (1=on, 0=off)
SYSTEM_INFO="1"             # system information
STORAGE_INFO="1"            # storage information
USER_INFO="1"               # user information
ENVIRONMENT_INFO="1"        # environment information
MAINTENANCE_INFO="1"        # maintenance log
UPDATE_INFO="1"             # available package updates
FAIL2BAN_INFO="1"          # fail2ban banned IPs (shows a notice if fail2ban-client is missing)
FAIL2BAN_ALWAYS="0"        # always show Fail2Ban section, even if FAIL2BAN_INFO="0"
UPDATE_ALWAYS="0"          # always show Update section, even if UPDATE_INFO="0"
MAINTENANCE_ALWAYS="0"     # always show Maintenance section, even if MAINTENANCE_INFO="0"
SHOWFAIL2BAN_IPS="1"       # show individual banned IPs per jail (no DNS)
RESOLVEFAIL2BAN_IPS="1"    # resolve banned IPs via DNS (requires SHOWFAIL2BAN_IPS="1")
FAIL2BAN_MAX_IPS="10"      # max banned IPs listed per jail (0 = no limit)
FAILED_SERVICES_INFO="1"    # failed systemd services (auto-hidden if none failed; notice if systemctl is missing)
FAILED_SERVICES_ALWAYS="0"  # always show Failed Services section, even when none failed
NETWORK_INFO="1"            # network interface state and speed
WEATHER_INFO="1"            # weather section via wttr.in (shows a notice if curl is missing)
WEATHER_ALWAYS="0"          # always show Weather section, even if fetch fails
WEATHER_CITY=""             # city name for weather lookup (empty = auto-detect from IP)
WEATHER_CACHE_HOURS="1"     # hours before weather data is refreshed (0 = always live)
WEATHER_UNITS=""            # unit system: m=metric  u=USCS  M=wind in m/s  (empty=wttr.in default)
VERSION_INFO="1"            # version banner

## number of most recent maintenance log entries shown in MAINTENANCE_INFO
LIST_LOG_ENTRY="2"

## hours before the cached update count is refreshed (0 = always live)
UPDATE_CACHE_HOURS="6"


## ANSI color definitions
C_BLACK="\033[0;30m"
C_DGRAY="\033[1;30m"
C_GREY="\033[0;37m"
C_WHITE="\033[1;37m"
C_RED="\033[0;31m"
C_LRED="\033[1;31m"
C_BLUE="\033[0;34m"
C_LBLUE="\033[1;34m"
C_CYAN="\033[0;36m"
C_LCYAN="\033[1;36m"
C_PINK="\033[0;35m"
C_LPINK="\033[1;35m"
C_GREEN="\033[0;32m"
C_LGREEN="\033[1;32m"
C_BROWN="\033[0;33m"
C_YELLOW="\033[1;33m"
C_RESET="\033[0m"

#### color schemes
## F1 = labels/text   F2 = borders/separators   F3 = values   F4 = warnings
## Uncomment exactly ONE scheme block. All others must remain commented out.

## 1. DOT - day of the tentacle (default)
F1=${C_GREY}
F2=${C_PINK}
F3=${C_LGREEN}
F4=${C_RED}

## 2. retro hacker — all green, Matrix style
#F1=${C_GREEN}
#F2=${C_GREEN}
#F3=${C_GREEN}
#F4=${C_RED}

## 3. retro alert — full red, high urgency
#F1=${C_RED}
#F2=${C_RED}
#F3=${C_RED}
#F4=${C_RED}

## 4. ocean — cool blue/cyan, professional
#F1=${C_CYAN}
#F2=${C_LBLUE}
#F3=${C_WHITE}
#F4=${C_LRED}

## 5. solarized dark — warm yellow accent on grey
#F1=${C_GREY}
#F2=${C_YELLOW}
#F3=${C_LCYAN}
#F4=${C_LRED}

## 6. nord — ice blue, clean and modern
#F1=${C_LBLUE}
#F2=${C_LCYAN}
#F3=${C_WHITE}
#F4=${C_YELLOW}

## 7. amber — classic CRT amber terminal
#F1=${C_BROWN}
#F2=${C_YELLOW}
#F3=${C_WHITE}
#F4=${C_LRED}


## root check — use id -u, not $USER (more reliable in su/sudo/cron contexts)
if [[ "$(id -u)" -ne 0 ]]; then
    cat /etc/motd 2>/dev/null || echo "No message of the day available"
    exit 0
fi


#### Distribution Detection

## Sets: DISTRO_ID, DISTRO_ID_LIKE, DISTRO_PRETTY
function _detect_distro() {
    DISTRO_ID=""
    DISTRO_ID_LIKE=""
    DISTRO_PRETTY=""

    if [ -f /etc/os-release ]; then
        DISTRO_ID=$(grep -m1 '^ID=' /etc/os-release \
            | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
        DISTRO_ID_LIKE=$(grep -m1 '^ID_LIKE=' /etc/os-release \
            | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
        DISTRO_PRETTY=$(grep -m1 '^PRETTY_NAME=' /etc/os-release \
            | cut -d= -f2 | tr -d '"')
    elif [ -f /etc/redhat-release ]; then
        DISTRO_ID="rhel"
        DISTRO_PRETTY=$(< /etc/redhat-release)
    elif [ -f /etc/debian_version ]; then
        DISTRO_ID="debian"
        DISTRO_PRETTY="Debian $(< /etc/debian_version)"
    else
        DISTRO_ID="unknown"
        DISTRO_PRETTY="Unknown Distribution"
    fi
}


#### Dependency Management

function _check_dependencies() {
    local missing_deps=()
    for cmd in grep hostname sed awk; do
        command -v "$cmd" >/dev/null 2>&1 || missing_deps+=("$cmd")
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Missing dependencies: ${missing_deps[*]}"
        echo "Run: $(basename "$0") --install  to install them automatically"
        return 1
    fi
    return 0
}


## Detects the distribution and installs any missing dependencies
## using the native package manager. Does NOT remove packages on uninstall.
function _install_dependencies() {
    _detect_distro
    echo "Detected: ${DISTRO_PRETTY:-$DISTRO_ID}"
    echo

    local pkg_mgr="" update_cmd="" packages=""
    local is_debian=false is_rhel=false is_fedora=false
    local is_suse=false is_arch=false is_alpine=false

    ## Classify by DISTRO_ID first
    case "$DISTRO_ID" in
        debian|ubuntu|linuxmint|raspbian|pop|elementary|zorin|\
        kali|parrot|mx|devuan|lmde|neon|trisquel)
            is_debian=true ;;
        rhel|centos|rocky|almalinux|ol|scientific|eurolinux|\
        springdale|cloudlinux|anolis)
            is_rhel=true ;;
        fedora)
            is_fedora=true ;;
        opensuse*|sles|sled)
            is_suse=true ;;
        arch|manjaro|endeavouros|garuda|artix|cachyos|blackarch)
            is_arch=true ;;
        alpine)
            is_alpine=true ;;
    esac

    ## Fallback: use ID_LIKE for derivatives not listed above
    if ! $is_debian && ! $is_rhel && ! $is_fedora && \
       ! $is_suse && ! $is_arch && ! $is_alpine; then
        [[ "$DISTRO_ID_LIKE" == *"debian"* || \
           "$DISTRO_ID_LIKE" == *"ubuntu"* ]]          && is_debian=true
        [[ "$DISTRO_ID_LIKE" == *"rhel"*   || \
           "$DISTRO_ID_LIKE" == *"centos"* ]]          && is_rhel=true
        ## fedora only if not already classified as rhel
        [[ "$DISTRO_ID_LIKE" == *"fedora"* ]] && \
            ! $is_rhel                                 && is_fedora=true
        [[ "$DISTRO_ID_LIKE" == *"suse"* ]]            && is_suse=true
        [[ "$DISTRO_ID_LIKE" == *"arch"* ]]            && is_arch=true
    fi

    ## Map family to package manager and package list
    if $is_debian; then
        pkg_mgr="apt-get"
        update_cmd="apt-get update -qq"
        packages="coreutils procps hostname sed gawk grep dnsutils lsb-release"
    elif $is_rhel; then
        command -v dnf >/dev/null 2>&1 && pkg_mgr="dnf" || pkg_mgr="yum"
        packages="hostname procps-ng gawk bind-utils"
    elif $is_fedora; then
        pkg_mgr="dnf"
        packages="hostname procps-ng gawk bind-utils"
    elif $is_suse; then
        pkg_mgr="zypper"
        packages="hostname procps gawk bind-utils lsb-release"
    elif $is_arch; then
        pkg_mgr="pacman"
        packages="inetutils procps-ng gawk bind"
    elif $is_alpine; then
        pkg_mgr="apk"
        packages="bind-tools busybox-extras procps gawk"
    else
        echo "Unsupported distribution: '${DISTRO_ID}'"
        echo "Install manually: grep, hostname, sed, awk, host (dnsutils / bind-utils)"
        return 1
    fi

    ## Only install what is actually missing
    local missing_cmds=()
    for cmd in grep hostname sed awk host; do
        command -v "$cmd" >/dev/null 2>&1 || missing_cmds+=("$cmd")
    done

    if [ ${#missing_cmds[@]} -eq 0 ]; then
        echo "All dependencies are already installed."
        return 0
    fi

    echo "Missing commands   : ${missing_cmds[*]}"
    echo "Package manager    : ${pkg_mgr}"
    echo "Packages to install: ${packages}"
    echo

    [ -n "$update_cmd" ] && $update_cmd

    case "$pkg_mgr" in
        apt-get) apt-get install -y $packages ;;
        dnf)     dnf install -y $packages ;;
        yum)     yum install -y $packages ;;
        zypper)  zypper install -y $packages ;;
        pacman)  pacman -Sy --noconfirm $packages ;;
        apk)     apk add --no-cache $packages ;;
    esac

    local rc=$?
    echo
    if [ $rc -eq 0 ]; then
        echo "Dependencies installed successfully."
    else
        echo "Warning: package installation returned exit code ${rc}."
        echo "Please check the output above and install missing packages manually."
    fi
    return $rc
}


#### Generic helpers

## Runs an external command with a time limit when `timeout` is available, so a
## hanging tool (stale NFS mount, unresponsive daemon, slow DNS) cannot block
## the login. Does not work for shell functions.
## Usage: _timeout <seconds> <command> [args...]
function _timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    else
        "$@"
    fi
}


## Prints <value> as a base-10 integer, or <default> if it is not a plain
## non-negative number. Leading zeros are stripped ("038" would otherwise be
## parsed as invalid octal in shell arithmetic).
## Usage: VAR=$(_to_int "$VAR" <default>)
function _to_int() {
    local v="${1:-}"
    [[ "$v" =~ ^[0-9]{1,9}$ ]] || v="${2:-0}"
    echo $(( 10#$v ))
}


## Normalizes numeric settings so a typo in the config block cannot break
## arithmetic later on.
function _sanitize_config() {
    LIST_LOG_ENTRY=$(_to_int "$LIST_LOG_ENTRY" 2)
    UPDATE_CACHE_HOURS=$(_to_int "$UPDATE_CACHE_HOURS" 6)
    WEATHER_CACHE_HOURS=$(_to_int "$WEATHER_CACHE_HOURS" 1)
    FAIL2BAN_MAX_IPS=$(_to_int "$FAIL2BAN_MAX_IPS" 10)
}


## Prints the age of a file in seconds (very large if the file is unreadable).
function _file_age() {
    local mtime
    mtime=$(stat -c %Y "$1" 2>/dev/null)
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    echo $(( $(date +%s) - mtime ))
}


## Writes a single line to a cache file atomically (temp file + rename), so
## parallel logins never read a half-written cache.
## Usage: _write_cache <file> <content>
function _write_cache() {
    local file="$1" tmp
    mkdir -p "$DYNMOTDDIR" 2>/dev/null || return 1
    tmp=$(mktemp "${file}.XXXXXX" 2>/dev/null) || return 1
    if printf '%s\n' "$2" > "$tmp" && mv -f "$tmp" "$file"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}


## Joins items and wraps the result so no line exceeds 79 columns.
## The first line is assumed to start at column <indent>; continuation lines
## are indented by <indent> spaces. <separator> is appended to every item
## except the last ("," or "").
## Usage: _wrap_list <indent> <separator> item...
function _wrap_list() {
    local indent="$1" sep="$2"; shift 2
    local width=79 out="" col=0 item pad first=1
    pad=$(printf '%*s' "$indent" '')

    for item in "$@"; do
        if (( first )); then
            out="$item"
            col=$(( indent + ${#item} ))
            first=0
        elif (( col + ${#sep} + 1 + ${#item} > width )); then
            out+="${sep}"$'\n'"${pad}${item}"
            col=$(( indent + ${#item} ))
        else
            out+="${sep} ${item}"
            col=$(( col + ${#sep} + 1 + ${#item} ))
        fi
    done
    printf '%s' "$out"
}


#### Configuration helpers

function _createmaintenance() {
    if [ ! -f "$MAINLOG" ]; then
        mkdir -p "$DYNMOTDDIR"
        touch "$MAINLOG"
        chmod 600 "$MAINLOG"
        echo "New log file created: $MAINLOG"
        echo
    fi
}


## Loads SYSFUNCTION / SYSENV / SYSSLA from environment.cfg.
## Returns: 0 = loaded, 1 = missing or incomplete, 2 = not owned by root (not sourced)
function _load_env() {
    [ -f "$ENVFILE" ] || return 1

    ## Safety: only source the file if root owns it
    local owner
    owner=$(stat -c '%U' "$ENVFILE" 2>/dev/null)
    [ "$owner" = "root" ] || return 2

    # shellcheck source=/dev/null
    source "$ENVFILE" 2>/dev/null
    [ -n "${SYSFUNCTION:-}" ] && [ -n "${SYSENV:-}" ] && [ -n "${SYSSLA:-}" ]
}


function createenv() {
    ## Show current values as defaults when reconfiguring
    _load_env
    local cur_func="${SYSFUNCTION:-Unset}"
    local cur_env="${SYSENV:-DEV}"
    local cur_sla="${SYSSLA:-None}"

    echo -e "
$(_section_header "Environment Setup")
${F1}"
    echo "Assign a role and environment label for: $(hostname --fqdn 2>/dev/null || hostname)"
    echo

    echo -n "System Function (e.g. Webserver, Mailserver) [${cur_func}]: "
    read -r SYSFUNCTION
    echo -n "Environment (DEV|TST|INT|PRD) [${cur_env}]: "
    read -r SYSENV
    echo -n "Service Level (SLA1|SLA2|SLA3|None) [${cur_sla}]: "
    read -r SYSSLA

    SYSFUNCTION="${SYSFUNCTION:-$cur_func}"
    SYSENV="${SYSENV:-$cur_env}"
    SYSSLA="${SYSSLA:-$cur_sla}"

    ## %q quotes the values for the shell: the file is sourced as root, so
    ## input containing quotes, $ or backticks must not be able to run code.
    mkdir -p "$DYNMOTDDIR"
    rm -f "$ENVFILE"
    (
        umask 077
        {
            printf 'SYSFUNCTION=%q\n' "$SYSFUNCTION"
            printf 'SYSENV=%q\n'      "$SYSENV"
            printf 'SYSSLA=%q\n'      "$SYSSLA"
        } > "$ENVFILE"
    ) || { echo "Error: could not write $ENVFILE"; return 1; }

    echo
    echo "Configuration saved to $ENVFILE"
}


#### Log management

function addlog() {
    if [ ! -f "$MAINLOG" ]; then
        echo "Maintenance log not found — creating: $MAINLOG"
        _createmaintenance
    fi

    if [ -z "$1" ]; then
        echo "Usage: $(basename "$0") -a \"maintenance note\""
        exit 1
    fi

    local mydate
    mydate=$(date +"%b %d %H:%M:%S")
    printf '%s %s\n' "$mydate" "${1//[$'\n\r']/}" >> "$MAINLOG" \
        || { echo "Error: could not write to $MAINLOG"; exit 1; }
    echo "Log entry added."
}


function rmlog() {
    if [ -z "$1" ]; then
        echo "Usage: $(basename "$0") -d [line-number]"
        exit 1
    fi

    if ! [[ "$1" =~ ^[0-9]{1,9}$ ]]; then
        echo "Error: '$1' is not a valid line number."
        exit 1
    fi

    if [ ! -f "$MAINLOG" ]; then
        echo "Maintenance log not found: $MAINLOG"
        exit 1
    fi

    local line total
    line=$(( 10#$1 ))
    total=$(grep -c '' "$MAINLOG")
    if (( line < 1 || line > total )); then
        echo "Error: line $line does not exist (log has $total entries)."
        exit 1
    fi

    if sed -i "${line}d" "$MAINLOG"; then
        echo "Line $line deleted."
    else
        echo "Error deleting line $line."
        exit 1
    fi
}


function listlog() {
    if [ ! -f "$MAINLOG" ]; then
        echo "Maintenance log not found: $MAINLOG"
        _createmaintenance
        return
    fi

    ## printf %s keeps backslashes in log entries literal;
    ## "|| [ -n ]" also prints a last line that has no trailing newline.
    local count=1 line
    while IFS= read -r line || [ -n "$line" ]; do
        printf "${F2}%s ${F1}%s\n" "$count" "$line"
        count=$(( count + 1 ))
    done < "$MAINLOG"
}


#### Install / Uninstall

## Copies the running script to <target> via temp file + rename, so a failed
## or interrupted copy never leaves a truncated binary behind.
function _copy_self() {
    local target="$1" tmp

    if [ ! -f "$0" ] || [ ! -r "$0" ]; then
        echo "failed."
        echo "Error: cannot read the script source '$0'."
        echo "Run it from a file (bash dynmotd.sh ...), not through a pipe."
        return 1
    fi

    ## cat "$0" > "$target" on the same file would truncate it to zero bytes
    if [ "$0" -ef "$target" ]; then
        echo "skipped."
        echo "Source and target are the same file: ${target}"
        echo "Run this from the downloaded script instead, e.g.: bash dynmotd.sh --update"
        return 1
    fi

    mkdir -p "$(dirname "$target")" 2>/dev/null
    tmp=$(mktemp "${target}.XXXXXX" 2>/dev/null) || {
        echo "failed."
        echo "Error: cannot write to $(dirname "$target")."
        return 1
    }

    if cat "$0" > "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$target"; then
        return 0
    fi
    rm -f "$tmp"
    echo "failed."
    echo "Error: could not install ${target}."
    return 1
}


function install() {
    echo -e "$(_section_header "Installing dynmotd")${F1}"
    echo

    ## Install missing system packages for this distribution
    _install_dependencies
    echo

    ## Verify core tools are present after installation
    _check_dependencies || {
        echo "Dependency check failed. Please resolve missing packages and retry."
        return 1
    }

    local target="${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"

    if [ -f "$target" ] && [ ! "$0" -ef "$target" ]; then
        echo -n "dynmotd is already installed at ${target}. Overwrite? [Y/n]: "
        read -r OPT
        [[ "$OPT" =~ ^[Nn]$ ]] && { echo "Nothing to do."; return 0; }
    fi

    echo -n "Installing to ${target}... "
    _copy_self "$target" || return 1

    ## Profile hook: run only for interactive shells, so non-interactive login
    ## shells (bash -lc from cron, Ansible, ...) do not get the MOTD mixed
    ## into their output.
    mkdir -p "$(dirname "$DYNMOTD_PROFILE")" 2>/dev/null
    cat > "$DYNMOTD_PROFILE" <<EOF
# dynmotd: show the dynamic MOTD for interactive login shells
case "\$-" in
    *i*) [ -x "${target}" ] && "${target}" ;;
esac
EOF
    echo "done."

    ## Run first-time setup if needed
    [ ! -f "$ENVFILE" ]  && { echo; createenv; }
    [ ! -f "$MAINLOG" ]  && _createmaintenance

    echo
    echo "Installation complete."
    echo "Log out and back in (or: sudo -i) to see dynmotd on next login."
}


## --update: replace binary without running setup (safe for Ansible/Puppet/cron)
## Only the binary is replaced — logs, config, and environment.cfg are untouched.
function update() {
    local target="${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"

    if [ ! -f "$target" ]; then
        echo "dynmotd is not installed at ${target}."
        echo "Run: $(basename "$0") --install  for a full installation."
        return 1
    fi

    echo -n "Updating dynmotd at ${target}... "
    _copy_self "$target" || return 1
    echo "done."
    echo "Version: ${VERSION}"
}


function uninstall() {
    local target="${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"

    echo -e "$(_section_header "Uninstalling dynmotd")${F1}"
    echo

    ## Collect program files that exist
    local remove_files=()
    [ -f "$target" ]          && remove_files+=("$target")
    [ -f "$DYNMOTD_PROFILE" ] && remove_files+=("$DYNMOTD_PROFILE")

    if [ ${#remove_files[@]} -eq 0 ] && [ ! -d "$DYNMOTDDIR" ]; then
        echo "dynmotd does not appear to be installed. Nothing to do."
        return 0
    fi

    if [ ${#remove_files[@]} -gt 0 ]; then
        echo "Program files to remove:"
        for f in "${remove_files[@]}"; do
            echo "  $f"
        done
    fi

    ## Ask separately about data / logs
    local remove_data=false
    if [ -d "$DYNMOTDDIR" ]; then
        echo
        echo "Data directory: ${DYNMOTDDIR}/"
        [ -f "$MAINLOG" ] && echo "  maintenance.log  ($(grep -c '' "$MAINLOG") entries)"
        [ -f "$ENVFILE" ]  && echo "  environment.cfg"
        echo
        echo -n "Also delete logs and configuration in ${DYNMOTDDIR}/? [y/N]: "
        read -r OPT_DATA
        [[ "$OPT_DATA" =~ ^[Yy]$ ]] && remove_data=true
    fi

    echo
    echo -n "Confirm removal [Y/n]: "
    read -r OPT
    echo

    ## Default is YES (empty = confirm)
    if [[ "$OPT" =~ ^[Nn]$ ]]; then
        echo "Aborted. Nothing removed."
        return 0
    fi

    ## Remove binary and profile hook
    for f in "${remove_files[@]}"; do
        if rm -f "$f"; then
            echo "Removed: $f"
        else
            echo "Error: could not remove $f"
        fi
    done

    ## Remove data directory only if explicitly confirmed
    if $remove_data; then
        if rm -rf "$DYNMOTDDIR"; then
            echo "Removed: ${DYNMOTDDIR}/"
        else
            echo "Error: could not remove ${DYNMOTDDIR}/"
        fi
    else
        echo
        [ -d "$DYNMOTDDIR" ] && echo "Data preserved: ${DYNMOTDDIR}/"
        echo "(Remove manually if desired: rm -rf ${DYNMOTDDIR}/)"
    fi

    echo
    echo "Note: System packages installed as dependencies were NOT removed."
    echo "      Use your package manager to remove them if desired."
    echo
    echo "dynmotd uninstalled."
}


#### Output sections

## Layout convention for all sections: every line is "label = value". Labels
## are right-aligned in a LABEL_WIDTH-char column, so every = sits in the same
## column across the whole MOTD and values start at column LABEL_WIDTH + 3.
## A section whose labels are data (mount points, unit names, IP addresses) may
## widen its own column when one of them does not fit.
LABEL_WIDTH=17


## Prints the notice for a section that is switched on but whose tool is not
## installed, so a missing section is never a silent surprise.
## Usage: _missing_tool <label> <tool> <toggle variable>
function _missing_tool() {
    _kv "$1" "$2 not installed (hide: $3=\"0\")" "$F4"
}


## Extracts the addresses of one family from ifconfig output on stdin.
## Handles both net-tools formats:
##   old:  "inet addr:192.0.2.1  Bcast:..."   "inet6 addr: 2001:db8::1/64 Scope:Global"
##   new:  "inet 192.0.2.1  netmask ..."      "inet6 2001:db8::1  prefixlen 64 ..."
## Usage: ifconfig | _parse_ifconfig <4|6>
function _parse_ifconfig() {
    awk -v fam="$1" '
        /^[^ \t]/ { iface = $1; sub(/:$/, "", iface) }
        iface == "lo" { next }
        fam == 4 && $1 == "inet" {
            a = $2; sub(/^addr:/, "", a)
            if (a != "") print a
        }
        fam == 6 && $1 == "inet6" {
            a = $2; if (a == "addr:") a = $3
            sub(/\/.*/, "", a)
            if (a != "") print a
        }
    '
}


## Prints the addresses of all active non-loopback interfaces, one per line.
## Tries the tools from newest to oldest so the script also works on old
## distributions:
##   1. ip -brief          iproute2 4.x and newer
##   2. ip -o addr show    any iproute2
##   3. ifconfig           net-tools
##   4. hostname -I        last resort
## Usage: _list_addresses <4|6>
function _list_addresses() {
    local fam="$1" out iface addr state

    if command -v ip >/dev/null 2>&1; then
        ## Interfaces without carrier (state DOWN) are skipped
        if out=$(ip "-${fam}" -brief addr show 2>/dev/null); then
            awk '$1 != "lo" && $2 != "DOWN" {
                    for (i = 3; i <= NF; i++) { split($i, a, "/"); if (a[1]) print a[1] }
                 }' <<< "$out"
            return 0
        fi

        ## One line per address: "2: eth0    inet 192.0.2.1/24 brd ... scope global eth0"
        ## This form has no carrier state, so it is read from sysfs.
        if out=$(ip -o "-${fam}" addr show up 2>/dev/null); then
            while read -r _ iface _ addr _; do
                iface="${iface%%@*}"
                [ -n "$addr" ] && [ "$iface" != "lo" ] || continue
                state=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null)
                [ "$state" = "down" ] && continue
                echo "${addr%%/*}"
            done <<< "$out"
            return 0
        fi
    fi

    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null | _parse_ifconfig "$fam"
        return 0
    fi

    ## hostname -I lists both families; IPv6 addresses contain a colon
    if [ "$fam" = "6" ]; then
        hostname -I 2>/dev/null | tr -s ' ' '\n' | grep ':'
    else
        hostname -I 2>/dev/null | tr -s ' ' '\n' | grep -v ':' | grep .
    fi
    return 0
}


## Prints one "label = value" line in the common layout.
## Usage: _kv <label> <value> [value color=F3] [label width=LABEL_WIDTH]
function _kv() {
    printf "${F1}%${4:-$LABEL_WIDTH}s ${F2}= ${3:-$F3}%s\n" "$1" "$2"
}


## Generates a section header with consistent 79-char visible width.
## Fixed parts: "============[ " (14) + " ]" (2) = 16 chars
## Trailing padding = 63 - ${#label}
## Usage inside echo -e: "$(_section_header "Label")"
function _section_header() {
    local label="$1"
    local trail=$(( 63 - ${#label} ))
    (( trail < 0 )) && trail=0
    local padding
    padding=$(printf '%*s' "$trail" '' | tr ' ' '=')
    printf '%s' "${F2}============[ ${F1}${label}${F2} ]${padding}"
}


## Bar width scales with terminal width: COLUMNS/4, clamped to [10,30].
function _bar_width() {
    local width=$(( $(_to_int "${COLUMNS:-}" 80) / 4 ))
    (( width < 10 )) && width=10
    (( width > 30 )) && width=30
    echo "$width"
}


## Renders a progress bar using the active color scheme.
## F3 = filled blocks (#)   F1 = empty blocks (-)   F2 = brackets [ ]
## Output contains real ESC codes so it works in both echo -e and printf %s.
## Visible width is always <width> + 7, also for empty or invalid input.
## Usage: bar=$(_progress_bar <value> <max> [width=20])
function _progress_bar() {
    ## _to_int strips leading zeros and maps non-numeric input (e.g. "-") to 0
    local val max width
    val=$(_to_int "${1:-}" 0)
    max=$(_to_int "${2:-}" 0)
    width=$(_to_int "${3:-}" 20)
    local pct=0 filled=0 empty bar_filled bar_empty

    if (( max > 0 )); then
        (( val > max )) && val=$max
        pct=$(( val * 100 / max ))
        filled=$(( val * width / max ))
    fi
    empty=$(( width - filled ))

    bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '#')
    bar_empty=$(printf  '%*s' "$empty"  '' | tr ' ' '-')

    printf "${F2}[${F3}%s${F1}%s${F2}]${F3} %3d%%" \
        "$bar_filled" "$bar_empty" "$pct"
}


function show_system_info() {
    [ "$SYSTEM_INFO" = "1" ] || return

    local HOSTNAME IPV4 IPV6 IPV6_LINE UNAME DISTRIBUTION PLATFORM UPTIME
    local CPUS CPUMODEL LOADAVG MEMAVAIL MEMMAX MEMUSED SWAPFREE SWAPMAX SWAPUSED PROCCOUNT PROCMAX

    ## hostname --fqdn does a DNS lookup and can hang when the resolver is down
    HOSTNAME=$(_timeout 2 hostname --fqdn 2>/dev/null)
    [ -n "$HOSTNAME" ] || HOSTNAME=$(hostname 2>/dev/null)
    [ -n "$HOSTNAME" ] || HOSTNAME="Unknown"

    ## IPv4 + IPv6: all non-loopback addresses, link-local IPv6 excluded
    IPV4=$(_list_addresses 4 | xargs)
    IPV6=$(_list_addresses 6 | grep -vi '^fe80' | xargs)
    [ -z "$IPV4" ] && IPV4="Unknown"
    ## Only add IPv6 line if addresses are present
    IPV6_LINE=""
    [ -n "$IPV6" ] && IPV6_LINE="\n${F1}       Address v6 ${F2}= ${F3}${IPV6}"

    UNAME=$(uname -r)

    ## Distribution: /etc/os-release → lsb_release → /etc/redhat-release
    ## (os-release first: lsb_release starts a Python interpreter on every login)
    DISTRIBUTION=""
    if [ -f /etc/os-release ]; then
        DISTRIBUTION=$(grep -m1 '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
    fi
    if [ -z "$DISTRIBUTION" ] && command -v lsb_release >/dev/null 2>&1; then
        DISTRIBUTION=$(lsb_release -s -d 2>/dev/null | tr -d '"')
    fi
    if [ -z "$DISTRIBUTION" ] && [ -f /etc/redhat-release ]; then
        DISTRIBUTION=$(< /etc/redhat-release)
    fi
    [ -n "$DISTRIBUTION" ] || DISTRIBUTION="Unknown Distribution"

    PLATFORM=$(uname -m)

    ## uptime -p (procps >= 3.3.0) gives clean "up X days, Y hours" output
    UPTIME=$(uptime -p 2>/dev/null) \
        || UPTIME=$(uptime | awk -F'up ' '{print $2}' | cut -d, -f1,2 | xargs)

    CPUS=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
    [[ "$CPUS" =~ ^[1-9][0-9]*$ ]] || CPUS=$(nproc 2>/dev/null)
    [[ "$CPUS" =~ ^[1-9][0-9]*$ ]] || CPUS=1

    ## x86 has "model name" in /proc/cpuinfo; ARM, RISC-V and s390x do not.
    ## Ask lscpu there and fall back to the machine architecture.
    CPUMODEL=$(awk -F': *' '/^model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)
    if [ -z "$CPUMODEL" ] && command -v lscpu >/dev/null 2>&1; then
        CPUMODEL=$(_timeout 2 env LC_ALL=C lscpu 2>/dev/null \
            | awk -F': +' '/^Model name/ {print $2; exit}')
    fi
    if [ -z "$CPUMODEL" ] || [ "$CPUMODEL" = "-" ]; then
        CPUMODEL="$PLATFORM"
    fi

    ## Load average from /proc/loadavg (1m / 5m / 15m)
    LOADAVG=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null)

    ## Read /proc/meminfo once via awk — MemAvailable instead of MemFree:
    ## MemFree is misleadingly low on Linux (kernel cache not counted as free).
    ## MemAvailable shows realistic usable memory (available since kernel 3.14);
    ## older kernels get the classic MemFree + Buffers + Cached estimate.
    read -r MEMAVAIL MEMMAX SWAPFREE SWAPMAX <<< "$(awk '
        /^MemAvailable:/ { a=$2/1024; has_a=1 }
        /^MemFree:/      { f=$2/1024 }
        /^Buffers:/      { b=$2/1024 }
        /^Cached:/       { c=$2/1024 }
        /^MemTotal:/     { t=$2/1024 }
        /^SwapFree:/     { sf=$2/1024 }
        /^SwapTotal:/    { st=$2/1024 }
        END {
            if (!has_a) a = f + b + c
            printf "%.0f %.0f %.0f %.0f", a, t, sf, st
        }
    ' /proc/meminfo 2>/dev/null)"
    MEMAVAIL=$(_to_int "$MEMAVAIL" 0)
    MEMMAX=$(_to_int "$MEMMAX" 0)
    SWAPFREE=$(_to_int "$SWAPFREE" 0)
    SWAPMAX=$(_to_int "$SWAPMAX" 0)
    MEMUSED=$(( MEMMAX - MEMAVAIL ))
    SWAPUSED=$(( SWAPMAX - SWAPFREE ))
    (( MEMUSED  < 0 )) && MEMUSED=0
    (( SWAPUSED < 0 )) && SWAPUSED=0

    ## ps --no-headers is GNU/procps; fall back for minimal systems
    PROCCOUNT=$(ps --no-headers -eo pid 2>/dev/null | wc -l)
    PROCCOUNT=$(_to_int "${PROCCOUNT//[[:space:]]/}" 0)
    if (( PROCCOUNT == 0 )); then
        PROCCOUNT=$(ps -e 2>/dev/null | tail -n +2 | wc -l)
        PROCCOUNT=$(_to_int "${PROCCOUNT//[[:space:]]/}" 0)
    fi
    PROCMAX=$(ulimit -u)
    [ "$PROCMAX" = "unlimited" ] && PROCMAX="∞"

    local bar_width
    bar_width=$(_bar_width)

    echo -e "
$(_section_header "System Info")
${F1}         Hostname ${F2}= ${F3}${HOSTNAME}
${F1}       Address v4 ${F2}= ${F3}${IPV4}${IPV6_LINE}
${F1}           Kernel ${F2}= ${F3}${UNAME}
${F1}     Distribution ${F2}= ${F3}${DISTRIBUTION} ${PLATFORM}
${F1}           Uptime ${F2}= ${F3}${UPTIME}
${F1}     Load Average ${F2}= ${F3}${LOADAVG} ${F1}(1m 5m 15m)
${F1}              CPU ${F2}= ${F3}${CPUS} x ${CPUMODEL}
${F1}           Memory ${F2}= $(_progress_bar "${MEMUSED}" "${MEMMAX}" "${bar_width}")  ${F3}${MEMAVAIL} MB free of ${MEMMAX} MB
${F1}      Swap Memory ${F2}= $(_progress_bar "${SWAPUSED}" "${SWAPMAX}" "${bar_width}")  ${F3}${SWAPFREE} MB free of ${SWAPMAX} MB
${F1}        Processes ${F2}= ${F3}${PROCCOUNT} of ${PROCMAX} MAX${F1}"
}


## Prints the name of the first package manager found, in detection order.
function _pkg_manager() {
    local mgr
    for mgr in apt-get dnf yum zypper pacman apk; do
        if command -v "$mgr" >/dev/null 2>&1; then
            echo "$mgr"
            return 0
        fi
    done
    return 1
}


## Prints the number of pending package updates for <package-manager>.
## Returns 1 without output if the count could not be determined (lock held,
## timeout, repository error), so a failed query is never shown or cached as 0.
## LC_ALL=C keeps the tool output parseable on non-English systems.
function _count_updates() {
    local out rc
    case "$1" in
        apt-get)
            out=$(_timeout 30 env LC_ALL=C apt-get -s -qq dist-upgrade 2>/dev/null) || return 1
            grep -c '^Inst' <<< "$out"
            ;;
        dnf|yum)
            ## check-update exit codes: 0 = no updates, 100 = updates, other = error
            out=$(_timeout 60 env LC_ALL=C "$1" check-update -q 2>/dev/null)
            rc=$?
            (( rc == 0 || rc == 100 )) || return 1
            ## Count package lines only; stop at the "Obsoleting Packages" list
            awk '/^Obsoleting/ { exit }
                 /^[A-Za-z0-9]/ && !/^Last|^Loaded|^Loading|^Updated|^Security/ { c++ }
                 END { print c+0 }' <<< "$out"
            ;;
        zypper)
            ## Table rows of available updates start with the status column "v"
            out=$(_timeout 60 env LC_ALL=C zypper --non-interactive list-updates 2>/dev/null) || return 1
            grep -c '^v[[:space:]]*|' <<< "$out"
            ;;
        pacman)
            ## pacman -Qu exits 1 when there is nothing to update
            out=$(pacman -Qu 2>/dev/null)
            grep -c . <<< "$out"
            ;;
        apk)
            out=$(_timeout 30 apk list --upgradeable 2>/dev/null) || return 1
            grep -c . <<< "$out"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}


function show_update_info() {
    [ "$UPDATE_INFO" = "1" ] || [ "$UPDATE_ALWAYS" = "1" ] || return

    local UPDATES="Unknown"
    local REBOOT_REQUIRED="Unknown"
    local REBOOT_PACKAGES="N/A"
    local mgr
    mgr=$(_pkg_manager)
    [ -n "$mgr" ] || UPDATES="Unknown (no supported package manager found)"

    if [ -n "$mgr" ]; then
        ## Cache the update count: querying the package manager takes 1–3 sec
        ## (apt) up to much longer (dnf/zypper) on every login.
        ## The cache is refreshed when older than UPDATE_CACHE_HOURS hours, or
        ## when dpkg has installed/removed packages since it was written.
        local cache_file="${DYNMOTDDIR}/update_cache"
        local cached="" count=""

        if (( UPDATE_CACHE_HOURS > 0 )) && [ -f "$cache_file" ] \
            && (( $(_file_age "$cache_file") < UPDATE_CACHE_HOURS * 3600 )) \
            && [ ! /var/lib/dpkg/status -nt "$cache_file" ]; then
            read -r cached < "$cache_file"
            [[ "$cached" =~ ^[0-9]+$ ]] && UPDATES="$cached"
        fi

        if [ "$UPDATES" = "Unknown" ]; then
            ## Stays "Unknown" if the query fails (lock held, timeout, repo error)
            if count=$(_count_updates "$mgr") && [[ "$count" =~ ^[0-9]+$ ]]; then
                UPDATES="$count"
                _write_cache "$cache_file" "$count"
            fi
        fi
    fi

    case "$mgr" in
        apt-get)
            if [ -f /var/run/reboot-required ]; then
                REBOOT_REQUIRED="Yes"
                REBOOT_PACKAGES="(unknown)"
                if [ -f /var/run/reboot-required.pkgs ]; then
                    ## The file lists a package once per upgrade → de-duplicate
                    local -a reboot_pkgs
                    mapfile -t reboot_pkgs < <(
                        tr -s '[:space:]' '\n' < /var/run/reboot-required.pkgs \
                            | grep -v '^$' | sort -u
                    )
                    (( ${#reboot_pkgs[@]} > 0 )) \
                        && REBOOT_PACKAGES=$(_wrap_list 20 "" "${reboot_pkgs[@]}")
                fi
            else
                REBOOT_REQUIRED="No"
                REBOOT_PACKAGES="-"
            fi
            ;;
        dnf|yum)
            ## needs-restarting -r: 0 = no reboot needed, 1 = reboot needed
            if command -v needs-restarting >/dev/null 2>&1; then
                _timeout 30 needs-restarting -r >/dev/null 2>&1
                case $? in
                    0) REBOOT_REQUIRED="No" ;;
                    1) REBOOT_REQUIRED="Yes" ;;
                esac
            elif [ -f /var/run/reboot-required ]; then
                REBOOT_REQUIRED="Yes"
            fi
            ;;
        zypper)
            ## zypper needs-rebooting: 0 = no reboot needed, 102 = reboot needed
            _timeout 30 zypper --non-interactive needs-rebooting >/dev/null 2>&1
            case $? in
                0)   REBOOT_REQUIRED="No" ;;
                102) REBOOT_REQUIRED="Yes" ;;
            esac
            ;;
        pacman)
            ## If the running kernel's module directory is no longer owned by any
            ## installed package, the kernel was upgraded and a reboot is needed.
            if pacman -Qo "/lib/modules/$(uname -r)" >/dev/null 2>&1; then
                REBOOT_REQUIRED="No"
            else
                REBOOT_REQUIRED="Yes"
            fi
            ;;
        apk)
            REBOOT_REQUIRED=$([ -f /var/run/reboot-required ] && echo "Yes" || echo "No")
            ;;
    esac

    echo -e "
$(_section_header "Update Info")
${F1}Available Updates ${F2}= ${F3}${UPDATES}
${F1}  Reboot Required ${F2}= ${F3}${REBOOT_REQUIRED}
${F1}  Reboot Packages ${F2}= ${F3}${REBOOT_PACKAGES}${F1}"
}


function show_storage_info() {
    [ "$STORAGE_INFO" = "1" ] || return

    echo -e "\n$(_section_header "Storage Info")"

    local bar_width
    bar_width=$(_bar_width)

    ## Exclude virtual/overlay filesystems; extract pct + fields via awk;
    ## sort descending by usage percentage; draw one bar per filesystem.
    ## -P keeps every filesystem on one line (long device names would wrap),
    ## the timeout protects against hanging network mounts, and the mount
    ## point is rebuilt from all remaining fields so paths with spaces survive.
    local -a rows
    mapfile -t rows < <(_timeout 5 env LC_ALL=C df -hTP 2>/dev/null \
        | awk 'NR > 1 && !/docker|tmpfs|devtmpfs|squashfs|udev|overlay|shm|cgroupfs|efivarfs/ {
            pct=$6; gsub(/%/,"",pct)
            mount=$7; for (i=8; i<=NF; i++) mount = mount " " $i
            printf "%d|%s|%s|%s|%s|%s\n", pct+0,$2,$3,$4,$5,mount
        }' \
        | sort -t'|' -k1,1 -rn)

    if (( ${#rows[@]} == 0 )); then
        _kv "Filesystems" "no data available (df failed or timed out)" "$F4"
        printf "${F1}"
        return
    fi

    ## The mount point is the label; a mount point longer than the label
    ## column widens it for the whole section so the = stays in one column.
    local row pct type size used mount bar field=$LABEL_WIDTH
    for row in "${rows[@]}"; do
        mount="${row##*|}"
        (( ${#mount} > field )) && field=${#mount}
    done

    for row in "${rows[@]}"; do
        IFS='|' read -r pct type size used _ mount <<< "$row"
        bar=$(_progress_bar "$pct" "100" "$bar_width")
        printf "${F1}%${field}s ${F2}= %s  ${F3}%5s ${F1}used of${F3} %5s  ${F1}%s\n" \
            "$mount" "$bar" "$used" "$size" "$type"
    done

    printf "${F1}"
}


## Use getent passwd if available (includes LDAP/NIS/AD users).
## Falls back to /etc/passwd for systems without getent (e.g. Alpine/musl) or
## when the directory service does not answer in time. Consumers de-duplicate,
## because a timed-out getent may already have printed part of the list.
function _get_passwd() {
    if command -v getent >/dev/null 2>&1; then
        _timeout 5 getent passwd 2>/dev/null && return 0
    fi
    cat /etc/passwd 2>/dev/null
}


## Prints the comment of one authorized_keys line; returns 1 if the line holds
## no public key. The key type may be preceded by options
## (from="...",command="..." ssh-ed25519 AAAA... comment).
## Supports: ssh-rsa, ssh-dss, ssh-ed25519, ecdsa-sha2-*, sk-ssh-*, sk-ecdsa-*
function _ssh_key_comment() {
    local re='(^|[[:space:]])(ssh-(rsa|dss|ed25519)|ecdsa-sha2-[a-z0-9-]+|sk-(ssh-ed25519|ecdsa-sha2-[a-z0-9-]+)@openssh\.com)[[:space:]]+AAAA[A-Za-z0-9+/=]+[[:space:]]*(.*)$'

    [[ "$1" =~ ^[[:space:]]*# ]] && return 1
    [[ "$1" =~ $re ]] || return 1

    local comment="${BASH_REMATCH[5]}"
    comment="${comment%"${comment##*[![:space:]]}"}"    # trim trailing whitespace
    (( ${#comment} > 60 )) && comment="${comment:0:57}..."
    echo "${comment:-- Unknown -}"
}


## Prints one comment per public key found in an authorized_keys file.
## These files are user-controlled but shown in root's terminal, so the input
## is limited in size and stripped of control characters (terminal escapes).
function _ssh_key_comments() {
    local line
    [ -f "$1" ] && [ -r "$1" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        _ssh_key_comment "$line"
    done < <(head -n 500 "$1" 2>/dev/null | tr '\t' ' ' | tr -d '\000-\010\013-\037\177')
}


## Prints "<label> = [<count>] item, item, ..." wrapped at 79 columns.
## Usage: _print_count_list <label (max 17 chars)> <count> [item...]
function _print_count_list() {
    local label="$1" prefix="[$2] " list="None"
    shift 2
    (( $# > 0 )) && list=$(_wrap_list $(( 20 + ${#prefix} )) "," "$@")
    printf "${F1}%17s ${F2}= ${F3}%s%s\n" "$label" "$prefix" "$list"
}


function show_user_info() {
    [ "$USER_INFO" = "1" ] || return

    local WHOIAM ID SESSIONS
    local -a sessions sys_users ssh_root_users keyusers

    ## id -un instead of $USER, which is unset or stale under su/sudo/cron
    WHOIAM=$(id -un 2>/dev/null)
    ID=$(id)

    ## One entry per user + origin: "(count) user host".
    ## The origin is the last field if it is in parentheses; its position
    ## depends on the locale's date format, so it cannot be addressed as $5.
    SESSIONS=$(who 2>/dev/null | grep -c .)
    mapfile -t sessions < <(
        who 2>/dev/null | awk '{
            host = ($NF ~ /^\(.*\)$/) ? substr($NF, 2, length($NF) - 2) : "local"
            n[$1 " " host]++
        } END { for (k in n) printf "(%d) %s\n", n[k], k }' | sort -k2
    )

    ## System users: UID 1000–65533, interactive shell only
    mapfile -t sys_users < <(
        _get_passwd | awk -F: '$3 ~ /^[0-9]+$/ && $3 >= 1000 && $3 < 65534 \
            && $7 ~ /sh$/ && !seen[$1]++ { print $1 }'
    )

    ## SSH keys authorized for root
    mapfile -t ssh_root_users < <(_ssh_key_comments /root/.ssh/authorized_keys)

    ## SSH keys for regular users (UID 1000–65533), one pass per home directory
    mapfile -t keyusers < <(
        _get_passwd | awk -F: '$3 ~ /^[0-9]+$/ && $3 >= 1000 && $3 < 65534 \
            && $6 != "" && !seen[$6]++ { print $6 }' \
        | while IFS= read -r homedir; do
            _ssh_key_comments "${homedir}/.ssh/authorized_keys"
        done
    )

    echo -e "\n$(_section_header "User Data")"
    printf "${F1}%17s ${F2}= ${F3}%s\n" "Your Username"   "$WHOIAM"
    printf "${F1}%17s ${F2}= ${F3}%s\n" "Your Privileges" "$ID"
    _print_count_list "Current Sessions" "$SESSIONS"               "${sessions[@]}"
    _print_count_list "SystemUsers"      "${#sys_users[@]}"        "${sys_users[@]}"
    _print_count_list "SshKeyRootUsers"  "${#ssh_root_users[@]}"   "${ssh_root_users[@]}"
    _print_count_list "SshKeyUsers"      "${#keyusers[@]}"         "${keyusers[@]}"
    printf "${F1}"
}


function show_environment_info() {
    [ "$ENVIRONMENT_INFO" = "1" ] || return

    echo -e "\n$(_section_header "Environment Data")"

    ## Sections run as background jobs without a terminal on stdin, so the
    ## interactive setup cannot run here — show_info() does that up front.
    _load_env
    case $? in
        0)
            _kv "Function"      "$SYSFUNCTION"
            _kv "Environment"   "$SYSENV"
            _kv "Service Level" "$SYSSLA"
            ;;
        2)
            _kv "Environment" "${ENVFILE} is not owned by root — skipped" "$F4"
            ;;
        *)
            _kv "Environment" "not configured — run: ${DYNMOTD_FILENAME} --config" "$F4"
            ;;
    esac
    printf "${F1}"
}


function show_maintenance_info() {
    [ "$MAINTENANCE_INFO" = "1" ] || [ "$MAINTENANCE_ALWAYS" = "1" ] || return

    echo -e "\n$(_section_header "Maintenance Information")"

    if [ ! -f "$MAINLOG" ]; then
        _kv "Log Entries" "no log file at ${MAINLOG}" "$F4"
        printf "${F1}"
        return
    fi

    ## Newest entries (the log is append-only, so they are at the end).
    ## The label "#n" is the line number in the log, as used by --rmlog.
    local total first n=0 line
    total=$(grep -c '' "$MAINLOG")
    first=$(( total - LIST_LOG_ENTRY + 1 ))

    if (( total == 0 )); then
        _kv "Log Entries" "none — add one with: ${DYNMOTD_FILENAME} -a \"note\""
    else
        while IFS= read -r line || [ -n "$line" ]; do
            n=$(( n + 1 ))
            (( n >= first )) && _kv "#${n}" "$line"
        done < "$MAINLOG"
    fi
    printf "${F1}"
}


## Prints the reverse DNS name of an IP address, or nothing.
## PTR records are controlled by the remote party, so only hostname characters
## are let through.
function _resolve_ip() {
    local name=""
    if command -v getent >/dev/null 2>&1; then
        name=$(_timeout 1 getent hosts "$1" 2>/dev/null | awk '{print $2; exit}')
    elif command -v host >/dev/null 2>&1; then
        name=$(_timeout 2 host -W 1 "$1" 2>/dev/null \
            | awk '/domain name pointer/ {sub(/\.$/, "", $NF); print $NF; exit}')
    fi
    printf '%s' "${name//[^A-Za-z0-9._:-]/}"
}


function show_fail2ban_info() {
    [ "$FAIL2BAN_INFO" = "1" ] || [ "$FAIL2BAN_ALWAYS" = "1" ] || return

    if ! command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "\n$(_section_header "Fail2Ban")"
        _missing_tool "Fail2Ban" "fail2ban-client" "FAIL2BAN_INFO"
        printf "${F1}"
        return
    fi

    local -a jails jail_ips
    local banned_total=0
    local summary="" jail status banned

    ## Retrieve active jail list from fail2ban-client status
    mapfile -t jails < <(
        _timeout 5 fail2ban-client status 2>/dev/null \
            | awk -F':\t' '/Jail list/ {print $2}' \
            | tr ',' '\n' | tr -d ' \t' | grep -v '^$'
    )

    echo -e "\n$(_section_header "Fail2Ban")"

    if [ ${#jails[@]} -eq 0 ]; then
        _kv "Fail2Ban" "not running or no active jails" "$F4"
        printf "${F1}"
        return
    fi

    ## One status call per jail delivers both the counter and the IP list.
    ## Only syntactically valid addresses are kept.
    for jail in "${jails[@]}"; do
        status=$(_timeout 5 fail2ban-client status "$jail" 2>/dev/null)
        banned=$(awk '/Currently banned:/ {print $NF}' <<< "$status")
        banned=$(_to_int "$banned" 0)
        banned_total=$(( banned_total + banned ))
        summary+="${jail}:${banned}  "
        jail_ips+=("$(sed -n 's/.*Banned IP list:[[:space:]]*//p' <<< "$status" \
            | tr -s '[:space:]' '\n' | grep -E '^[0-9A-Fa-f.:]+$' | tr '\n' ' ')")
    done
    summary="${summary%  }"     # strip trailing spaces

    ## A busy jail can hold hundreds of addresses — list at most
    ## FAIL2BAN_MAX_IPS of them per jail (0 = no limit).
    ## Jail names and addresses are the labels of this section; anything
    ## longer than the label column (IPv6) widens it for the whole section.
    local idx ip field=$LABEL_WIDTH
    local -a ips shown
    if [ "$SHOWFAIL2BAN_IPS" = "1" ]; then
        for idx in "${!jails[@]}"; do
            read -ra ips <<< "${jail_ips[$idx]}"
            (( ${#ips[@]} > 0 )) || continue
            (( FAIL2BAN_MAX_IPS > 0 )) && ips=("${ips[@]:0:FAIL2BAN_MAX_IPS}")
            (( ${#jails[$idx]} > field )) && field=${#jails[$idx]}
            [ "$RESOLVEFAIL2BAN_IPS" = "1" ] || continue
            for ip in "${ips[@]}"; do
                (( ${#ip} > field )) && field=${#ip}
            done
        done
    fi

    _kv "Total Banned" "$banned_total" "" "$field"
    _kv "Active Jails" "$summary"      "" "$field"

    ## Optional: list banned IPs per jail with reverse DNS
    if [ "$SHOWFAIL2BAN_IPS" != "1" ]; then
        printf "${F1}"
        return
    fi

    for idx in "${!jails[@]}"; do
        jail="${jails[$idx]}"
        read -ra ips <<< "${jail_ips[$idx]}"
        (( ${#ips[@]} > 0 )) || continue

        if (( FAIL2BAN_MAX_IPS > 0 && ${#ips[@]} > FAIL2BAN_MAX_IPS )); then
            shown=("${ips[@]:0:FAIL2BAN_MAX_IPS}")
        else
            shown=("${ips[@]}")
        fi
        local more=$(( ${#ips[@]} - ${#shown[@]} ))

        ## Resolve all IPs in parallel; one result file per IP inside a private
        ## temp directory preserves the order. Without a temp directory the
        ## addresses are listed unresolved.
        local rdir=""
        [ "$RESOLVEFAIL2BAN_IPS" = "1" ] && rdir=$(mktemp -d 2>/dev/null)

        echo
        if [ -n "$rdir" ]; then
            local n=0 name
            for ip in "${shown[@]}"; do
                ( _resolve_ip "$ip" > "${rdir}/${n}" ) &
                n=$(( n + 1 ))
            done
            wait

            _kv "$jail" "${#ips[@]} banned" "" "$field"
            n=0
            for ip in "${shown[@]}"; do
                name=""
                [ -f "${rdir}/${n}" ] && IFS= read -r name < "${rdir}/${n}"
                _kv "$ip" "${name:---}" "" "$field"
                n=$(( n + 1 ))
            done
            rm -rf "$rdir"
        else
            _kv "$jail" "$(_wrap_list $(( field + 3 )) "," "${shown[@]}")" "" "$field"
        fi

        (( more > 0 )) && printf "${F1}%$(( field + 3 ))s... and %d more\n" "" "$more"
    done
    printf "${F1}"
}


function show_network_info() {
    [ "$NETWORK_INFO" = "1" ] || return

    echo -e "\n$(_section_header "Network Interfaces")"

    ## Interfaces and their state come straight from sysfs — the same data
    ## `ip -brief link` prints, but without needing any tool or tool version.
    if [ ! -d /sys/class/net ]; then
        _kv "Interfaces" "not available (/sys/class/net is missing)" "$F4"
        printf "${F1}"
        return
    fi

    local dir iface state idx
    while read -r _ iface; do
        ## skip loopback and docker veth pairs
        [ "$iface" = "lo" ] && continue
        [[ "$iface" == veth* ]] && continue

        state=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null)
        state="${state^^}"
        [ -n "$state" ] || state="UNKNOWN"

        local speed=""
        local speed_raw
        speed_raw=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null)
        if [[ "$speed_raw" =~ ^[0-9]+$ ]] && (( speed_raw > 0 )); then
            speed="${speed_raw} Mbps"
        fi

        local state_color="$F3"
        [ "$state" != "UP" ] && state_color="$F4"

        ## The interface name is the label: "<iface> = <state>  <speed>"
        if [ -n "$speed" ]; then
            printf "${F1}%${LABEL_WIDTH}s ${F2}= ${state_color}%-8s ${F3}%s\n" \
                "$iface" "$state" "$speed"
        else
            _kv "$iface" "$state" "$state_color"
        fi

    ## "*/" matches interface directories only; sort by kernel interface index
    done < <(for dir in /sys/class/net/*/; do
                 iface="${dir%/}"; iface="${iface##*/}"
                 idx=$(cat "${dir}ifindex" 2>/dev/null)
                 printf '%s %s\n' "$(_to_int "$idx" 0)" "$iface"
             done | sort -n)

    printf "${F1}"
}


function show_version_info() {
    [ "$VERSION_INFO" = "1" ] || return

    ## Right-aligned banner, 79 chars wide: padding + "[ " + version + " ]=="
    local lead=$(( 73 - ${#VERSION} ))
    (( lead < 0 )) && lead=0
    local padding
    padding=$(printf '%*s' "$lead" '' | tr ' ' '=')
    echo -e "
${F2}${padding}[ ${F1}${VERSION}${F2} ]==
${F1}"
}


function show_failed_services_info() {
    [ "$FAILED_SERVICES_INFO" = "1" ] || return

    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "\n$(_section_header "Failed Services")"
        _missing_tool "Failed Services" "systemctl" "FAILED_SERVICES_INFO"
        printf "${F1}"
        return
    fi

    ## --plain drops the status bullet, so the unit name is always field 1;
    ## the awk expression still tolerates older systemd versions that print it.
    local -a units
    mapfile -t units < <(
        _timeout 5 systemctl --failed --no-legend --no-pager --plain 2>/dev/null \
            | awk 'NF >= 4 { print ($1 ~ /^[a-zA-Z0-9_@:.-]/) ? $1 : $2 }'
    )

    if [ ${#units[@]} -eq 0 ]; then
        [ "$FAILED_SERVICES_ALWAYS" = "1" ] || return
        echo -e "\n$(_section_header "Failed Services")"
        _kv "Failed Services" "none"
        printf "${F1}"
        return
    fi

    ## Unit names are the labels; a name longer than the label column widens
    ## it for the whole section so the = stays in one column.
    local field=$LABEL_WIDTH u
    for u in "${units[@]}"; do
        (( ${#u} > field )) && field=${#u}
    done

    echo -e "\n$(_section_header "Failed Services")"
    _kv "Failed Services" "${#units[@]}" "$F4" "$field"
    for u in "${units[@]}"; do
        _kv "$u" "failed" "$F4" "$field"
    done
    printf "${F1}"
}


## A wttr.in answer is usable if it is one short line with the six
## pipe-separated fields we asked for (error pages are HTML or plain text).
function _weather_valid() {
    [[ "$1" == *'|'*'|'*'|'*'|'*'|'* ]] && [[ "$1" != *'<'* ]] && (( ${#1} < 200 ))
}


function show_weather_info() {
    [ "$WEATHER_INFO" = "1" ] || [ "$WEATHER_ALWAYS" = "1" ] || return

    local weather="" cached=""

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "\n$(_section_header "Weather")"
        _missing_tool "Weather" "curl" "WEATHER_INFO"
        printf "${F1}"
        return
    fi

    local cache_key
    cache_key=$(printf '%s|%s' "${WEATHER_CITY:-}" "${WEATHER_UNITS:-}" \
        | md5sum 2>/dev/null | awk '{print $1}')
    [ -z "$cache_key" ] && cache_key="default"
    local cache_file="${DYNMOTDDIR}/weather_cache_${cache_key}"

    if [ -f "$cache_file" ]; then
        IFS= read -r cached < "$cache_file"
        _weather_valid "$cached" || cached=""
    fi

    ## Use cached data if still within WEATHER_CACHE_HOURS
    if [ -n "$cached" ] && (( WEATHER_CACHE_HOURS > 0 )) \
        && (( $(_file_age "$cache_file") < WEATHER_CACHE_HOURS * 3600 )); then
        weather="$cached"
    fi

    ## Fetch fresh data if cache is empty or expired
    if [ -z "$weather" ]; then
        local location="${WEATHER_CITY:-}"
        location="${location// /+}"
        local url="wttr.in/${location}?format=%l|%C|%t|%f|%h|%w"
        case "${WEATHER_UNITS:-}" in
            m|u|M) url="${url}&${WEATHER_UNITS}" ;;
        esac
        ## First line only, control characters stripped: the answer comes
        ## from the network and is printed into root's terminal.
        weather=$(curl -fsS --connect-timeout 2 --max-time 3 "$url" 2>/dev/null \
            | head -n 1 | tr -d '\000-\037\177')
        if _weather_valid "$weather"; then
            _write_cache "$cache_file" "$weather"
        else
            ## Service unreachable or error page → fall back to the last
            ## good answer instead of caching or showing garbage
            weather="$cached"
        fi
    fi

    if [ -z "$weather" ]; then
        [ "$WEATHER_ALWAYS" = "1" ] || return
        echo -e "\n$(_section_header "Weather")"
        printf "${F1}          Weather ${F2}= ${F4}unavailable\n"
        printf "${F1}"
        return
    fi

    local loc condition temp feels humidity wind
    IFS='|' read -r loc condition temp feels humidity wind <<< "$weather"

    echo -e "\n$(_section_header "Weather")"
    printf "${F1}         Location ${F2}= ${F3}%s\n" "$loc"
    printf "${F1}          Weather ${F2}= ${F3}%s\n" "$condition"
    printf "${F1}      Temperature ${F2}= ${F3}%s ${F1}(feels like ${F3}%s${F1})\n" "$temp" "$feels"
    printf "${F1}         Humidity ${F2}= ${F3}%s\n" "$humidity"
    printf "${F1}             Wind ${F2}= ${F3}%s\n" "$wind"
    printf "${F1}"
}


## Temp directory of the current show_info run; removed by the EXIT trap.
_DYNMOTD_TMPDIR=""

function show_info() {
    _check_dependencies \
        || echo "Warning: some dependencies are missing — output may be incomplete."

    ## First-run setup has to happen here in the foreground: the sections below
    ## run as background jobs whose stdin is not the terminal, so they cannot
    ## prompt. Without a terminal (cron, pipe) the setup is skipped.
    if [ "$ENVIRONMENT_INFO" = "1" ] && [ -t 0 ] && [ -t 1 ]; then
        _load_env
        [ $? -eq 1 ] && createenv
    fi

    ## Display order — the single place that defines it.
    local sections=(system weather storage network user update environment
                    failed_services fail2ban maintenance version)
    local s i=0

    _DYNMOTD_TMPDIR=$(mktemp -d 2>/dev/null) || _DYNMOTD_TMPDIR=""
    if [ -z "$_DYNMOTD_TMPDIR" ]; then
        ## mktemp failed — fall back to sequential output
        for s in "${sections[@]}"; do
            "show_${s}_info"
        done
        echo -e "${C_RESET}"
        return
    fi

    ## Run all sections in parallel, each writing to a numbered temp file.
    ## Output is collected and printed in order once all sections complete.
    for s in "${sections[@]}"; do
        i=$(( i + 1 ))
        "show_${s}_info" > "$(printf '%s/%02d' "$_DYNMOTD_TMPDIR" "$i")" &
    done

    wait  ## wait for all sections to complete

    cat "${_DYNMOTD_TMPDIR}"/[0-9][0-9] 2>/dev/null
    rm -rf "$_DYNMOTD_TMPDIR"
    _DYNMOTD_TMPDIR=""
    echo -e "${C_RESET}"
}


#### Main dispatcher

_sanitize_config

## Remove the temp directory of show_info even when the run is interrupted
trap '[ -n "$_DYNMOTD_TMPDIR" ] && rm -rf "$_DYNMOTD_TMPDIR"' EXIT
trap 'exit 130' INT TERM HUP

if [ -z "$1" ]; then
    show_info
    exit 0
fi

case "$1" in
    -a|addlog|--addlog)
        addlog "$2"
    ;;
    -d|rmlog|--rmlog)
        rmlog "$2"
    ;;
    -l|log|--log|listlog|--listlog)
        listlog
    ;;
    -c|config|--config|setup|-s|--setup)
        createenv
    ;;
    -i|install|--install)
        install
    ;;
    -U|update|--update)
        update
    ;;
    -u|uninstall|--uninstall)
        uninstall
    ;;
    -v|version|--version)
        echo "$VERSION"
    ;;
    -h|help|--help|\?)
        echo -e "
    Usage: $(basename "$0") [OPTION] [value]

    e.g.  $(basename "$0") -a \"deployed new SSL certificate\"

    Options:

      -a | --addlog \"...\"           Add a maintenance log entry
      -d | --rmlog  [line-number]   Delete a log entry by line number
      -l | --log                    List all log entries
      -c | --config                 Reconfigure environment settings
      -i | --install                Install dynmotd and its dependencies
      -U | --update                 Update binary only (no setup, safe for Ansible/cron)
      -u | --uninstall              Uninstall dynmotd (log deletion is optional)
      -v | --version                Show version and exit
      -h | --help                   Show this help
    "
    ;;
    *)
        echo "Unknown parameter: $1"
        echo "Use $(basename "$0") --help for usage."
        exit 1
    ;;
esac

exit 0
