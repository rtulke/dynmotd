#!/bin/bash

# dynamic message of the day
# Robert Tulke, rt@debian.sh
# Multi-distribution MOTD script with automatic dependency management

## version
VERSION="dynmotd v1.18.0"

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
FAIL2BAN_INFO="1"          # fail2ban banned IPs (only shown if fail2ban-client is installed)
SHOWFAIL2BAN_IPS="1"       # show individual banned IPs per jail (no DNS)
RESOLVEFAIL2BAN_IPS="1"    # resolve banned IPs via DNS (requires SHOWFAIL2BAN_IPS="1")
FAILED_SERVICES_INFO="1"    # failed systemd services (auto-hidden if none failed)
NETWORK_INFO="1"            # network interface state and speed
VERSION_INFO="1"            # version banner

## number of maintenance log lines shown in MAINTENANCE_INFO
LIST_LOG_ENTRY="2"

## hours before the apt update count cache is refreshed (0 = always live)
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
        opensuse*|sles|sled|opensuse-leap|opensuse-tumbleweed)
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


function createenv() {
    ## Show current values as defaults when reconfiguring
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

    mkdir -p "$DYNMOTDDIR"
    rm -f "$ENVFILE"
    touch "$ENVFILE"
    chmod 600 "$ENVFILE"
    printf 'SYSFUNCTION="%s"\n' "$SYSFUNCTION" >> "$ENVFILE"
    printf 'SYSENV="%s"\n'      "$SYSENV"      >> "$ENVFILE"
    printf 'SYSSLA="%s"\n'      "$SYSSLA"      >> "$ENVFILE"

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
    printf '%s %s\n' "$mydate" "${1//[$'\n\r']/}" >> "$MAINLOG"
    echo "Log entry added."
}


function rmlog() {
    if [ -z "$1" ]; then
        echo "Usage: $(basename "$0") -d [line-number]"
        exit 1
    fi

    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "Error: '$1' is not a valid line number."
        exit 1
    fi

    sed -i "${1}d" "$MAINLOG"
    local rc=$?
    [ $rc -eq 0 ] && echo "Line $1 deleted." || { echo "Error deleting line $1."; exit $rc; }
}


function listlog() {
    if [ ! -f "$MAINLOG" ]; then
        echo "Maintenance log not found: $MAINLOG"
        _createmaintenance
        return
    fi

    local count=1
    while read -r line; do
        echo -e "${F2}${count} ${F1}${line}${F2}"
        (( count++ ))
    done < "$MAINLOG"
}


#### Install / Uninstall

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

    if [ -f "$target" ]; then
        echo -n "dynmotd is already installed at ${target}. Overwrite? [Y/n]: "
        read -r OPT
        [[ "$OPT" =~ ^[Nn]$ ]] && { echo "Nothing to do."; return 0; }
    fi

    echo -n "Installing to ${target}... "
    cat "$0" > "$target"
    chmod 755 "$target"
    echo "$target" > "$DYNMOTD_PROFILE"
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
    cat "$0" > "$target"
    chmod 755 "$target"
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
        [ -f "$MAINLOG" ] && echo "  maintenance.log  ($(wc -l < "$MAINLOG") entries)"
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
        rm -f "$f" \
            && echo "Removed: $f" \
            || echo "Error: could not remove $f"
    done

    ## Remove data directory only if explicitly confirmed
    if $remove_data; then
        rm -rf "$DYNMOTDDIR" \
            && echo "Removed: ${DYNMOTDDIR}/" \
            || echo "Error: could not remove ${DYNMOTDDIR}/"
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

## Generates a section header with consistent 79-char visible width.
## Fixed parts: "============[ " (14) + " ]" (2) = 16 chars
## Trailing padding = 63 - ${#label}
## Usage inside echo -e: "$(_section_header "Label")"
function _section_header() {
    local label="$1"
    local trail=$(( 63 - ${#label} ))
    local padding
    padding=$(printf '%*s' "$trail" '' | tr ' ' '=')
    printf '%s' "${F2}============[ ${F1}${label}${F2} ]${padding}"
}


## Renders a progress bar using the active color scheme.
## F3 = filled blocks (█)   F1 = empty blocks (░)   F2 = brackets [ ]
## Output contains real ESC codes so it works in both echo -e and printf %s.
## Usage: bar=$(_progress_bar <value> <max> [width=20])
function _progress_bar() {
    local val=$1 max=$2 width=${3:-20}
    local pct filled empty bar_filled bar_empty

    if (( max == 0 )); then
        local empty_bar
        empty_bar=$(printf '%*s' "$width" '' | tr ' ' '-')
        printf "${F2}[${F1}%s${F2}]${F3}  0%%" "$empty_bar"
        return
    fi

    pct=$(( val * 100 / max ))
    (( pct   > 100   )) && pct=100
    filled=$(( val * width / max ))
    (( filled > width )) && filled=$width
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

    HOSTNAME=$(hostname --fqdn 2>/dev/null || hostname)

    ## IPv4 + IPv6: all non-loopback addresses via iproute2, fallback to hostname -I
    if command -v ip >/dev/null 2>&1; then
        IPV4=$(ip -4 -brief addr show 2>/dev/null \
            | awk '$1 != "lo" && $2 != "DOWN" {
                for(i=3;i<=NF;i++) { split($i,a,"/"); if(a[1]) printf "%s ", a[1] }
              }' | xargs)
        IPV6=$(ip -6 -brief addr show 2>/dev/null \
            | awk '$1 != "lo" && $2 != "DOWN" {
                for(i=3;i<=NF;i++) { split($i,a,"/"); if(a[1] !~ /^fe80/) printf "%s ", a[1] }
              }' | xargs)
    else
        IPV4=$(hostname -I 2>/dev/null | awk '{print $1}')
        IPV6=""
    fi
    [ -z "$IPV4" ] && IPV4="Unknown"
    ## Only add IPv6 line if addresses are present
    IPV6_LINE=""
    [ -n "$IPV6" ] && IPV6_LINE="\n${F1}      Address v6 ${F2}= ${F3}${IPV6}"

    UNAME=$(uname -r)

    ## Distribution: lsb_release → /etc/os-release → /etc/redhat-release
    if command -v lsb_release >/dev/null 2>&1; then
        DISTRIBUTION=$(lsb_release -s -d)
    elif [ -f /etc/os-release ]; then
        DISTRIBUTION=$(grep -m1 'PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [ -f /etc/redhat-release ]; then
        DISTRIBUTION=$(< /etc/redhat-release)
    else
        DISTRIBUTION="Unknown Distribution"
    fi

    PLATFORM=$(uname -m)

    ## uptime -p (procps >= 3.3.0) gives clean "up X days, Y hours" output
    UPTIME=$(uptime -p 2>/dev/null) \
        || UPTIME=$(uptime | awk -F'up ' '{print $2}' | cut -d, -f1,2 | xargs)

    CPUS=$(grep -c processor /proc/cpuinfo)
    CPUMODEL=$(grep -m1 'model name' /proc/cpuinfo | awk -F': ' '{print $2}')

    ## Load average from /proc/loadavg (1m / 5m / 15m)
    LOADAVG=$(awk '{print $1, $2, $3}' /proc/loadavg)

    ## Read /proc/meminfo once via awk — MemAvailable instead of MemFree:
    ## MemFree is misleadingly low on Linux (kernel cache not counted as free).
    ## MemAvailable shows realistic usable memory (available since kernel 3.14).
    read -r MEMAVAIL MEMMAX SWAPFREE SWAPMAX <<< "$(awk '
        /^MemAvailable:/ { a=$2/1024 }
        /^MemTotal:/     { t=$2/1024 }
        /^SwapFree:/     { sf=$2/1024 }
        /^SwapTotal:/    { st=$2/1024 }
        END { printf "%.0f %.0f %.0f %.0f", a, t, sf, st }
    ' /proc/meminfo)"
    MEMUSED=$(( MEMMAX - MEMAVAIL ))
    SWAPUSED=$(( SWAPMAX - SWAPFREE ))

    ## ps --no-headers is GNU/procps; fall back for minimal systems
    PROCCOUNT=$(ps --no-headers -eo pid 2>/dev/null | wc -l \
                || ps -e | tail -n +2 | wc -l)
    PROCMAX=$(ulimit -u)
    [ "$PROCMAX" = "unlimited" ] && PROCMAX="∞"

    local bar_width=$(( ${COLUMNS:-80} / 4 ))
    (( bar_width < 10 )) && bar_width=10
    (( bar_width > 30 )) && bar_width=30

    echo -e "
$(_section_header "System Info")
${F1}        Hostname ${F2}= ${F3}${HOSTNAME}
${F1}      Address v4 ${F2}= ${F3}${IPV4}${IPV6_LINE}
${F1}          Kernel ${F2}= ${F3}${UNAME}
${F1}    Distribution ${F2}= ${F3}${DISTRIBUTION} ${PLATFORM}
${F1}          Uptime ${F2}= ${F3}${UPTIME}
${F1}    Load Average ${F2}= ${F3}${LOADAVG} ${F1}(1m 5m 15m)
${F1}             CPU ${F2}= ${F3}${CPUS} x ${CPUMODEL}
${F1}          Memory ${F2}= $(_progress_bar "${MEMUSED}" "${MEMMAX}" "${bar_width}")  ${F3}${MEMAVAIL} MB free of ${MEMMAX} MB
${F1}     Swap Memory ${F2}= $(_progress_bar "${SWAPUSED}" "${SWAPMAX}" "${bar_width}")  ${F3}${SWAPFREE} MB free of ${SWAPMAX} MB
${F1}       Processes ${F2}= ${F3}${PROCCOUNT} of ${PROCMAX} MAX${F1}"
}


function show_update_info() {
    [ "$UPDATE_INFO" = "1" ] || return

    local UPDATES="Unknown"
    local REBOOT_REQUIRED="Unknown"
    local REBOOT_PACKAGES="N/A"

    if command -v apt-get >/dev/null 2>&1; then
        ## Cache apt update count to avoid running apt-get -s on every login (1–3 sec).
        ## Cache file is refreshed when older than UPDATE_CACHE_HOURS hours.
        local cache_file="${DYNMOTDDIR}/update_cache"
        local needs_refresh=true
        if [ -f "$cache_file" ]; then
            local cache_mtime cache_age
            cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
            cache_age=$(( $(date +%s) - cache_mtime ))
            (( cache_age < UPDATE_CACHE_HOURS * 3600 )) && needs_refresh=false
        fi
        if $needs_refresh; then
            UPDATES=$(apt-get -s -qq dist-upgrade 2>/dev/null | grep -c '^Inst')
            UPDATES=${UPDATES:-0}
            mkdir -p "$DYNMOTDDIR"
            echo "$UPDATES" > "$cache_file"
        else
            UPDATES=$(< "$cache_file")
        fi

        if [ -f /var/run/reboot-required ]; then
            REBOOT_REQUIRED="Yes"
            if [ -f /var/run/reboot-required.pkgs ]; then
                local raw_packages formatted_packages="" line_length=0
                raw_packages=$(< /var/run/reboot-required.pkgs)
                for pkg in $raw_packages; do
                    local pkg_length=${#pkg}
                    if [ $line_length -eq 0 ]; then
                        formatted_packages+="$pkg"
                        line_length=$pkg_length
                    elif [ $((line_length + pkg_length + 1)) -le 80 ]; then
                        formatted_packages+=" $pkg"
                        line_length=$((line_length + pkg_length + 1))
                    else
                        formatted_packages+="\n                    $pkg"
                        line_length=$((pkg_length + 20))
                    fi
                done
                REBOOT_PACKAGES="$formatted_packages"
            else
                REBOOT_PACKAGES="(unknown)"
            fi
        else
            REBOOT_REQUIRED="No"
            REBOOT_PACKAGES="-"
        fi

    elif command -v dnf >/dev/null 2>&1; then
        ## Filter out dnf header/metadata lines; count only actual package lines
        UPDATES=$(dnf check-update -q 2>/dev/null \
            | awk '/^[A-Za-z0-9]/ && !/^Last|^Loaded|^Loading|^Updated/ {c++} END {print c+0}')
        ## needs-restarting -r exits 1 if reboot needed
        if command -v needs-restarting >/dev/null 2>&1; then
            needs-restarting -r >/dev/null 2>&1 \
                && REBOOT_REQUIRED="No" || REBOOT_REQUIRED="Yes"
        else
            REBOOT_REQUIRED=$([ -f /var/run/reboot-required ] && echo "Yes" || echo "No")
        fi

    elif command -v yum >/dev/null 2>&1; then
        UPDATES=$(yum check-update -q 2>/dev/null \
            | awk '/^[A-Za-z0-9]/ && !/^Last|^Loaded|^Loading|^Updated/ {c++} END {print c+0}')
        ## needs-restarting -r exits 1 if reboot needed (same tool as dnf)
        if command -v needs-restarting >/dev/null 2>&1; then
            needs-restarting -r >/dev/null 2>&1 \
                && REBOOT_REQUIRED="No" || REBOOT_REQUIRED="Yes"
        else
            REBOOT_REQUIRED="Unknown"
        fi

    elif command -v zypper >/dev/null 2>&1; then
        ## zypper list-updates: count lines starting with "|" (table rows)
        UPDATES=$(zypper list-updates 2>/dev/null | grep -c '^|')
        UPDATES=${UPDATES:-0}
        zypper needs-rebooting >/dev/null 2>&1 \
            && REBOOT_REQUIRED="No" || REBOOT_REQUIRED="Yes"

    elif command -v pacman >/dev/null 2>&1; then
        UPDATES=$(pacman -Qu 2>/dev/null | wc -l)
        ## If the running kernel's module directory is no longer owned by any
        ## installed package, the kernel was upgraded and a reboot is needed.
        if pacman -Qo "/lib/modules/$(uname -r)" >/dev/null 2>&1; then
            REBOOT_REQUIRED="No"
        else
            REBOOT_REQUIRED="Yes"
        fi

    elif command -v apk >/dev/null 2>&1; then
        UPDATES=$(apk list --upgradeable 2>/dev/null | wc -l)
        REBOOT_REQUIRED=$([ -f /var/run/reboot-required ] && echo "Yes" || echo "No")
    fi

    echo -e "
$(_section_header "Update Info")
${F1}Available Updates ${F2}= ${F3}${UPDATES}
${F1}  Reboot Required ${F2}= ${F3}${REBOOT_REQUIRED}
${F1}  Reboot Packages ${F2}= ${F3}${REBOOT_PACKAGES}${F1}"
}


function show_storage_info() {
    [ "$STORAGE_INFO" = "1" ] || return

    echo -e "\n$(_section_header "Storage Info")"

    ## Bar width scales with terminal width: COLUMNS/4, clamped to [10,30].
    ## bar_visible = bar_width + 7  ([ + width + ] + space + 3-digit pct + %)
    local bar_width=$(( ${COLUMNS:-80} / 4 ))
    (( bar_width < 10 )) && bar_width=10
    (( bar_width > 30 )) && bar_width=30
    local bar_visible=$(( bar_width + 7 ))

    ## Header line — aligned with data rows
    printf "${F1}%-${bar_visible}s  %-7s  %6s         %6s   %s\n" \
        "Utilization" "Type" "Used" "Size" "Mount"

    ## Exclude virtual/overlay filesystems; extract pct + fields via awk;
    ## sort descending by usage percentage; draw one bar per filesystem.
    while IFS='|' read -r pct type size used avail mount; do
        local bar
        bar=$(_progress_bar "$pct" "100" "$bar_width")
        printf "%s  ${F1}%-7s${F3}  %6s ${F1}used of${F3} %6s   ${F1}%s\n" \
            "$bar" "$type" "$used" "$size" "$mount"
    done < <(df -hT 2>/dev/null \
        | awk '!/docker|tmpfs|devtmpfs|squashfs|udev|overlay|shm|cgroupfs/ && NR > 1 {
            pct=$6; gsub(/%/,"",pct)
            printf "%03d|%s|%s|%s|%s|%s\n", pct,$2,$3,$4,$5,$7
        }' \
        | sort -t'|' -k1 -rn)

    printf "${F1}"
}


## Use getent passwd if available (includes LDAP/NIS/AD users).
## Falls back to /etc/passwd for systems without getent (e.g. Alpine/musl).
function _get_passwd() {
    if command -v getent >/dev/null 2>&1; then
        getent passwd
    else
        cat /etc/passwd
    fi
}


## Extract the comment field from an authorized_keys line.
## Uses read -ra to avoid a subshell+pipe per key.
## Supports: ssh-rsa, ssh-ed25519, ecdsa-sha2-*, sk-ssh-*, sk-ecdsa-*
function _ssh_key_comment() {
    local -a fields
    read -ra fields <<< "$1"
    local count=${#fields[@]}

    if [ "$count" -gt 2 ]; then
        local comment="${fields[$((count-1))]}"
        ## Last field is still a key type or base64 blob → no comment present
        if [[ "$comment" =~ ^(ssh-|ecdsa-|sk-|AAAA|BBBB) ]]; then
            echo "- Unknown -"
        else
            echo "$comment"
        fi
    else
        echo "- Unknown -"
    fi
}


function show_user_info() {
    [ "$USER_INFO" = "1" ] || return

    local WHOIAM ID SESSIONS LOGGEDIN
    local SYSTEMUSERCOUNT SYSTEMUSER
    local SUPERUSERCOUNT SUPERUSER
    local KEYUSERCOUNT=0

    WHOIAM=$USER
    ID=$(id)
    SESSIONS=$(who | wc -l)

    LOGGEDIN=$(who | awk '{print $1, $5}' | awk -F'[()]' '{print $1, $2}' | uniq -c \
        | awk '{printf "(%s) %s %s,", $1, $2, $3}' | sed 's/,$//' \
        | sed 's/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

    ## System users: UID 1000–65533, interactive shell only
    mapfile -t sys_users < <(
        _get_passwd | awk -F: '$3 >= 1000 && $3 < 65534 && ($7 ~ /bash$|sh$/) {print $1}'
    )
    SYSTEMUSERCOUNT=${#sys_users[@]}
    SYSTEMUSER=$(IFS=", "; echo "${sys_users[*]}" \
        | sed 's/\([^,]*,[^,]*,[^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

    ## SSH keys authorized for root
    if [ -f "/root/.ssh/authorized_keys" ]; then
        mapfile -t ssh_root_users < <(
            while read -r line; do
                [[ "$line" =~ ^(ssh-|ecdsa-sha2-|sk-ssh-|sk-ecdsa-) ]] \
                    && _ssh_key_comment "$line"
            done < /root/.ssh/authorized_keys
        )
        SUPERUSERCOUNT=${#ssh_root_users[@]}
        SUPERUSER=$(IFS=", "; echo "${ssh_root_users[*]}" \
            | sed 's/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')
    else
        SUPERUSERCOUNT=0
        SUPERUSER="None"
    fi

    ## SSH keys for regular users (UID 1000–65533)
    local keyusers=()
    while IFS=: read -r _ _ uid _ _ homedir _; do
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        (( uid < 1000 || uid >= 65534 )) && continue
        [ -f "$homedir/.ssh/authorized_keys" ] || continue
        while read -r line; do
            if [[ "$line" =~ ^(ssh-|ecdsa-sha2-|sk-ssh-|sk-ecdsa-) ]]; then
                keyusers+=("$(_ssh_key_comment "$line")")
                (( KEYUSERCOUNT++ ))
            fi
        done < "$homedir/.ssh/authorized_keys"
    done < <(_get_passwd)

    local KEYUSER
    KEYUSER=$(IFS=", "; echo "${keyusers[*]}" \
        | sed 's/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

    echo -e "
$(_section_header "User Data")
${F1}    Your Username ${F2}= ${F3}${WHOIAM}
${F1}  Your Privileges ${F2}= ${F3}${ID}
${F1} Current Sessions ${F2}= ${F3}[${SESSIONS}] ${LOGGEDIN}
${F1}      SystemUsers ${F2}= ${F3}[${SYSTEMUSERCOUNT}] ${SYSTEMUSER}
${F1}  SshKeyRootUsers ${F2}= ${F3}[${SUPERUSERCOUNT}] ${SUPERUSER}
${F1}      SshKeyUsers ${F2}= ${F3}[${KEYUSERCOUNT}] ${KEYUSER}${F1}"
}


function show_environment_info() {
    [ "$ENVIRONMENT_INFO" = "1" ] || return

    if [ ! -f "$ENVFILE" ]; then
        createenv
        return
    fi

    ## Safety: only source the file if root owns it
    local file_owner
    file_owner=$(stat -c '%U' "$ENVFILE" 2>/dev/null)
    if [ "$file_owner" != "root" ]; then
        echo "Warning: $ENVFILE is not owned by root — skipping."
        return 1
    fi

    # shellcheck source=/dev/null
    source "$ENVFILE"

    if [ -z "${SYSFUNCTION}" ] || [ -z "${SYSENV}" ] || [ -z "${SYSSLA}" ]; then
        rm -f "$ENVFILE"
        createenv
        return
    fi

    echo -e "
$(_section_header "Environment Data")
${F1}         Function ${F2}= ${F3}${SYSFUNCTION}
${F1}      Environment ${F2}= ${F3}${SYSENV}
${F1}    Service Level ${F2}= ${F3}${SYSSLA}${F1}"
}


function show_maintenance_info() {
    [ "$MAINTENANCE_INFO" = "1" ] || return

    if [ ! -f "$MAINLOG" ]; then
        echo -e "
$(_section_header "Maintenance Information")
${F4}No maintenance log found at ${MAINLOG}${F1}"
        return
    fi

    local MAINTENANCE
    MAINTENANCE=$(listlog | head -n "${LIST_LOG_ENTRY}")

    echo -e "
$(_section_header "Maintenance Information")
${F4}${MAINTENANCE}${F1}"
}


function show_fail2ban_info() {
    [ "$FAIL2BAN_INFO" = "1" ] || return
    command -v fail2ban-client >/dev/null 2>&1 || return

    local -a jails
    local banned_total=0
    local summary=""

    ## Retrieve active jail list from fail2ban-client status
    mapfile -t jails < <(
        fail2ban-client status 2>/dev/null \
            | awk -F':\t' '/Jail list/ {print $2}' \
            | tr ',' '\n' | tr -d ' \t' | grep -v '^$'
    )

    if [ ${#jails[@]} -eq 0 ]; then
        echo -e "
$(_section_header "Fail2Ban")
${F4}fail2ban is not running or no active jails${F1}"
        return
    fi

    for jail in "${jails[@]}"; do
        local banned
        banned=$(fail2ban-client status "$jail" 2>/dev/null \
            | awk '/Currently banned:/ {print $NF}')
        banned=${banned:-0}
        banned_total=$(( banned_total + banned ))
        summary+="${jail}:${banned}  "
    done
    summary="${summary%  }"     # strip trailing spaces

    echo -e "
$(_section_header "Fail2Ban")
${F1}    Total Banned ${F2}= ${F3}${banned_total}
${F1}    Active Jails ${F2}= ${F3}${summary}${F1}"

    ## Optional: list banned IPs per jail with reverse DNS
    [ "$SHOWFAIL2BAN_IPS" = "1" ] || return

    for jail in "${jails[@]}"; do
        local -a ips
        mapfile -t ips < <(
            fail2ban-client status "$jail" 2>/dev/null \
                | grep 'Banned IP list:' \
                | sed 's/.*Banned IP list:[[:space:]]*//' \
                | tr ' ' '\n' | grep -v '^$'
        )
        [ ${#ips[@]} -eq 0 ] && continue

        printf "\n${F1} %s ${F2}(${F3}%d ${F1}IPs${F2}):\n" "$jail" "${#ips[@]}"

        ## Field width = longest IP in this jail + 1 (min 1 space before =).
        ## Guarantees = lands at the same column for every IP in the list.
        local max_ip_len=0
        for ip in "${ips[@]}"; do
            (( ${#ip} > max_ip_len )) && max_ip_len=${#ip}
        done
        local ip_field=$(( max_ip_len + 1 ))

        if [ "$RESOLVEFAIL2BAN_IPS" = "1" ]; then
            ## Resolve all IPs in parallel; collect results in temp files to preserve order.
            local -a ip_tmpfiles=()
            for ip in "${ips[@]}"; do
                local tmpf
                tmpf=$(mktemp 2>/dev/null) || tmpf="/tmp/dynmotd_ip_$$_${#ip_tmpfiles[@]}"
                ip_tmpfiles+=("$tmpf")
                (
                    local hostname=""
                    if command -v getent >/dev/null 2>&1; then
                        hostname=$(timeout 1 getent hosts "$ip" 2>/dev/null | awk '{print $2; exit}')
                    elif command -v host >/dev/null 2>&1; then
                        hostname=$(host -W 1 "$ip" 2>/dev/null \
                            | awk '/domain name pointer/ {sub(/\.$/, "", $NF); print $NF; exit}')
                    fi
                    printf "${F3} %-${ip_field}s${F2}= ${F3}%s\n" "$ip" "${hostname:---}" > "$tmpf"
                ) &
            done
            wait
            for tmpf in "${ip_tmpfiles[@]}"; do
                cat "$tmpf" 2>/dev/null
                rm -f "$tmpf"
            done
        else
            for ip in "${ips[@]}"; do
                printf "${F3} %s\n" "$ip"
            done
        fi
    done
    printf "${F1}"
}


function show_network_info() {
    [ "$NETWORK_INFO" = "1" ] || return
    command -v ip >/dev/null 2>&1 || return

    echo -e "\n$(_section_header "Network Interfaces")"

    printf "${F1}  %-14s %-10s %s\n" "Interface" "State" "Speed"

    while read -r iface state; do
        ## skip loopback and docker veth pairs
        [ "$iface" = "lo" ] && continue
        [[ "$iface" == veth* ]] && continue

        local speed="--"
        local speed_raw
        speed_raw=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null)
        if [[ "$speed_raw" =~ ^[0-9]+$ ]] && (( speed_raw > 0 )); then
            speed="${speed_raw} Mbps"
        fi

        local state_color="$F3"
        [ "$state" != "UP" ] && state_color="$F4"

        printf "${F3}  %-14s ${state_color}%-10s ${F3}%s\n" \
            "$iface" "$state" "$speed"

    done < <(ip -brief link show 2>/dev/null \
        | awk '{print $1, toupper($2)}')

    printf "${F1}"
}


function show_version_info() {
    [ "$VERSION_INFO" = "1" ] || return
    echo -e "
${F2}==========================================================[ ${F1}${VERSION}${F2} ]==
${F1}"
}



function show_failed_services_info() {
    [ "$FAILED_SERVICES_INFO" = "1" ] || return
    command -v systemctl >/dev/null 2>&1 || return

    local -a units
    mapfile -t units < <(
        systemctl --failed --no-legend --no-pager 2>/dev/null \
            | awk 'NF >= 4 { print ($1 ~ /^[a-zA-Z0-9_@:.-]/) ? $1 : $2 }'
    )

    ## Auto-hide when no services are in failed state
    [ ${#units[@]} -eq 0 ] && return

    echo -e "\n$(_section_header "Failed Services")"
    printf "${F1}  Failed Services ${F2}= ${F4}%d\n" "${#units[@]}"

    local max_len=0
    for u in "${units[@]}"; do
        (( ${#u} > max_len )) && max_len=${#u}
    done
    local field=$(( max_len + 1 ))

    for u in "${units[@]}"; do
        printf "${F4}    %-${field}s${F2}= ${F4}failed\n" "$u"
    done
    printf "${F1}"
}


function show_info() {
    _check_dependencies \
        || echo "Warning: some dependencies are missing — output may be incomplete."

    ## Run all sections in parallel, each writing to a numbered temp file.
    ## Output is collected and printed in order once all sections complete.
    local tmpdir
    tmpdir=$(mktemp -d 2>/dev/null) || {
        ## mktemp failed — fall back to sequential output
        show_system_info; show_storage_info; show_network_info
        show_user_info; show_update_info; show_environment_info
        show_maintenance_info; show_fail2ban_info; show_failed_services_info; show_version_info
        echo -e "${C_RESET}"
        return
    }
    chmod 700 "$tmpdir"

    show_system_info      > "${tmpdir}/01" &
    show_storage_info     > "${tmpdir}/02" &
    show_network_info     > "${tmpdir}/03" &
    show_user_info        > "${tmpdir}/04" &
    show_update_info      > "${tmpdir}/05" &
    show_environment_info > "${tmpdir}/06" &
    show_maintenance_info > "${tmpdir}/07" &
    show_fail2ban_info          > "${tmpdir}/08" &
    show_failed_services_info   > "${tmpdir}/09" &
    show_version_info           > "${tmpdir}/10" &

    wait  ## wait for all sections to complete

    cat "${tmpdir}"/0* 2>/dev/null
    rm -rf "$tmpdir"
    echo -e "${C_RESET}"
}


#### Main dispatcher

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
