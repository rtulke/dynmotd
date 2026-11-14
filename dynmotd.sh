#!/bin/bash

# dynamic message of the day
# Robert Tulke, rt@debian.sh
# Multi-distribution MOTD script with automatic dependency management

## version
VERSION="dynmotd v1.20.0"

## data directory: configuration, maintenance log and caches
DYNMOTDDIR="/root/.dynmotd"
CONFFILE="${DYNMOTDDIR}/dynmotd.conf"
MAINLOG="${DYNMOTDDIR}/maintenance.log"
ENVFILE="${DYNMOTDDIR}/environment.cfg"   # pre-1.20 file, imported into dynmotd.conf

## install path
DYNMOTD_INSTALL_PATH="/usr/local/bin"     # install destination (no trailing slash)
DYNMOTD_PROFILE="/etc/profile.d/motd.sh"  # profile.d hook that loads dynmotd
DYNMOTD_FILENAME="dynmotd"                # binary name


#### Built-in defaults
##
## DO NOT EDIT THE VALUES BELOW to configure a host: --install and --update
## replace this file. Settings belong in the configuration file (CONFFILE),
## which is generated from _config_template() further down and survives every
## update:
##
##     dynmotd --genconfig     create or refresh the configuration file
##
## A setting that is missing from the configuration file uses the default
## defined here. Every variable in this block must also appear in
## _config_template(), which holds its documentation, and in
## _sanitize_config(), which validates it.

## general
MOTD_MODE="full"
COLOR_SCHEME="dot"
COLOR_LABEL="grey"
COLOR_BORDER="pink"
COLOR_VALUE="lgreen"
COLOR_WARN="red"

## host description
SYSFUNCTION=""
SYSENV=""
SYSSLA=""

## sections
SYSTEM_INFO="1"
TIMESYNC_INFO="auto"
WEATHER_INFO="1"
WEATHER_ALWAYS="0"
WEATHER_CITY=""
WEATHER_UNITS=""
WEATHER_CACHE_HOURS="1"
STORAGE_INFO="1"
RAID_INFO="auto"
ZFS_INFO="auto"
LVM_INFO="auto"
NETWORK_INFO="1"
USER_INFO="1"
SECURITY_INFO="1"
SSH_PASSWORD_WARN="1"
LAST_LOGINS="3"
UPDATE_INFO="1"
UPDATE_ALWAYS="0"
UPDATE_CACHE_HOURS="6"
ENVIRONMENT_INFO="1"
FAILED_SERVICES_INFO="1"
FAILED_SERVICES_ALWAYS="0"
DOCKER_INFO="auto"
DOCKER_MAX_LIST="10"
CERT_INFO="auto"
CERT_FILES=""
CERT_WARN_DAYS="20"
CERT_MAX_LIST="10"
BACKUP_INFO="auto"
BACKUP_PATHS=""
BACKUP_MAX_AGE_HOURS="26"
FAIL2BAN_INFO="1"
FAIL2BAN_ALWAYS="0"
SHOWFAIL2BAN_IPS="1"
RESOLVEFAIL2BAN_IPS="1"
FAIL2BAN_MAX_IPS="10"
MAINTENANCE_INFO="1"
MAINTENANCE_ALWAYS="0"
LIST_LOG_ENTRY="2"
VERSION_INFO="1"

## warning thresholds (0 = never warn)
DISK_WARN_PERCENT="85"
INODE_WARN_PERCENT="85"
MEMORY_WARN_PERCENT="90"
SWAP_WARN_PERCENT="80"
LOAD_WARN_PERCENT="100"
UPDATE_WARN_COUNT="25"


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

## Active colors, set by _apply_colors() from COLOR_SCHEME:
## F1 = labels/text   F2 = borders/separators   F3 = values   F4 = warnings
F1=${C_GREY}
F2=${C_PINK}
F3=${C_LGREEN}
F4=${C_RED}


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


#### Configuration file

## The complete configuration file, with the current value of every setting.
## This is the single source for the file's content, its documentation and the
## list of known settings (_config_keys reads the names from here).
## Rules for editing: one KEY="${KEY}" line per setting, no other line may
## start with a capital letter, and no $ or backtick in the comment text.
function _config_template() {
    cat <<EOF
# dynmotd configuration
#
# Generated by ${VERSION}. This file is yours: edit it freely, it survives
# every --install and --update of dynmotd.
#
#   dynmotd --genconfig   rewrite this file: keeps your values, adds settings
#                         that are new in the installed version and restores
#                         the comments
#   dynmotd --check       show which sections are active and which tools
#                         they need
#
# Format: one KEY="value" per line. Lines starting with # are comments.
# The file is read as plain text, never executed. A setting that is missing
# or has an invalid value falls back to the built-in default, and the MOTD
# says so in a "Configuration" section.
#
# Section switches take these values:
#   "1"     on. If the tool the section needs is not installed, the section
#           shows a one-line notice instead of silently disappearing.
#   "0"     off.
#   "auto"  on if the tool the section needs is installed, otherwise hidden
#           without a notice. Only available where stated.


##############################################################################
# General
##############################################################################

# What a login shows.
#   "full"     every active section
#   "compact"  a three-line summary plus only the lines that need attention
#              (the ones the full view prints in the warning color)
# Override for a single run: dynmotd --full / dynmotd --compact
MOTD_MODE="${MOTD_MODE}"

# Color scheme.
#   "dot"        grey labels, pink borders, green values (default)
#   "hacker"     all green
#   "alert"      all red
#   "ocean"      cyan and blue
#   "solarized"  grey with yellow borders
#   "nord"       ice blue
#   "amber"      brown and yellow, like an old CRT terminal
#   "none"       no colors at all
#   "custom"     use the four COLOR_* settings below
COLOR_SCHEME="${COLOR_SCHEME}"

# Only used with COLOR_SCHEME="custom". Available color names:
#   black dgray grey white red lred blue lblue cyan lcyan pink lpink
#   green lgreen brown yellow
COLOR_LABEL="${COLOR_LABEL}"
COLOR_BORDER="${COLOR_BORDER}"
COLOR_VALUE="${COLOR_VALUE}"
COLOR_WARN="${COLOR_WARN}"


##############################################################################
# Host description (section "Environment Data")
##############################################################################

# Free text describing this host. Set interactively with: dynmotd --config
SYSFUNCTION="${SYSFUNCTION}"
# Suggested values: DEV, TST, INT, PRD
SYSENV="${SYSENV}"
# Suggested values: SLA1, SLA2, SLA3, None
SYSSLA="${SYSSLA}"

# Show the section. "1" or "0".
ENVIRONMENT_INFO="${ENVIRONMENT_INFO}"


##############################################################################
# System Info
##############################################################################

# Host name, addresses, kernel, distribution, uptime, load, CPU, memory,
# swap and process count. "1" or "0".
SYSTEM_INFO="${SYSTEM_INFO}"

# "Time Sync" line: is the system clock synchronized (timedatectl, chronyc
# or ntpstat)? "1", "0" or "auto".
TIMESYNC_INFO="${TIMESYNC_INFO}"

# Warning thresholds. A value at or above the threshold is printed in the
# warning color and shows up in compact mode. 0 disables a warning.
#
# Memory and swap in use, in percent.
MEMORY_WARN_PERCENT="${MEMORY_WARN_PERCENT}"
SWAP_WARN_PERCENT="${SWAP_WARN_PERCENT}"
# 1-minute load average in percent of the number of CPUs:
# 100 on a 4-CPU machine means "warn at a load of 4.0 or more".
LOAD_WARN_PERCENT="${LOAD_WARN_PERCENT}"


##############################################################################
# Weather
##############################################################################

# Current weather from wttr.in. This is the only section that contacts an
# external service: one HTTP request per WEATHER_CACHE_HOURS.
# Needs curl. "1", "0" or "auto".
WEATHER_INFO="${WEATHER_INFO}"

# "1" also shows the section (as "unavailable") when the request fails.
WEATHER_ALWAYS="${WEATHER_ALWAYS}"

# City to look up, for example "Berlin". Empty: wttr.in guesses the location
# from the public IP address of this host.
WEATHER_CITY="${WEATHER_CITY}"

# Units: "m" metric, "u" US customary, "M" metric with wind in m/s.
# Empty: wttr.in decides by location.
WEATHER_UNITS="${WEATHER_UNITS}"

# Hours before the weather is fetched again. 0 fetches on every login.
WEATHER_CACHE_HOURS="${WEATHER_CACHE_HOURS}"


##############################################################################
# Storage
##############################################################################

# One line per mounted filesystem with a usage bar. "1" or "0".
STORAGE_INFO="${STORAGE_INFO}"

# Disk space in use, in percent, from which a filesystem is a warning.
DISK_WARN_PERCENT="${DISK_WARN_PERCENT}"

# Inodes in use, in percent. Inode usage is only printed when it reaches
# this threshold (a filesystem can be "full" with free space left).
INODE_WARN_PERCENT="${INODE_WARN_PERCENT}"

# Linux software RAID arrays from /proc/mdstat; degraded arrays are a
# warning. "1", "0" or "auto" (shown when at least one array exists).
RAID_INFO="${RAID_INFO}"

# ZFS pools with usage and health. Needs zpool. "1", "0" or "auto".
ZFS_INFO="${ZFS_INFO}"

# LVM volume groups with size and free space. Needs vgs. "1", "0" or "auto".
LVM_INFO="${LVM_INFO}"


##############################################################################
# Network Interfaces
##############################################################################

# State and link speed of every interface (read from /sys/class/net).
# "1" or "0".
NETWORK_INFO="${NETWORK_INFO}"


##############################################################################
# Users and logins
##############################################################################

# Current sessions, local users and the SSH keys that grant access.
# "1" or "0".
USER_INFO="${USER_INFO}"

# Section "Login Security": effective sshd settings (root login, password
# logins, port), failed login attempts and the most recent logins.
# Lines whose tool is missing are left out. "1", "0" or "auto".
SECURITY_INFO="${SECURITY_INFO}"

# "1" prints "SSH Passwords = yes" as a warning, "0" as a plain value.
# Set to "0" if password logins are intended on this host.
SSH_PASSWORD_WARN="${SSH_PASSWORD_WARN}"

# Number of most recent logins listed. 0 hides the list.
LAST_LOGINS="${LAST_LOGINS}"


##############################################################################
# Updates
##############################################################################

# Pending package updates and whether a reboot is required. "1" or "0".
UPDATE_INFO="${UPDATE_INFO}"

# "1" shows the section even when UPDATE_INFO="0".
UPDATE_ALWAYS="${UPDATE_ALWAYS}"

# Hours before the package manager is asked again. Asking takes one to
# several seconds, so the count is cached. 0 asks on every login.
UPDATE_CACHE_HOURS="${UPDATE_CACHE_HOURS}"

# Number of pending updates from which the count is a warning. 0 = never.
UPDATE_WARN_COUNT="${UPDATE_WARN_COUNT}"


##############################################################################
# Services
##############################################################################

# Failed systemd units. Hidden while nothing has failed.
# Needs systemctl. "1", "0" or "auto".
FAILED_SERVICES_INFO="${FAILED_SERVICES_INFO}"

# "1" shows the section (as "none") even when nothing has failed.
FAILED_SERVICES_ALWAYS="${FAILED_SERVICES_ALWAYS}"

# Docker containers: how many are running and stopped; unhealthy,
# restarting and crashed containers are listed by name as warnings.
# Needs docker. "1", "0" or "auto".
DOCKER_INFO="${DOCKER_INFO}"

# Maximum number of problem containers listed by name. 0 = no limit.
DOCKER_MAX_LIST="${DOCKER_MAX_LIST}"


##############################################################################
# TLS certificates
##############################################################################

# Days until certificates expire. Certificates of Let's Encrypt / certbot
# under /etc/letsencrypt/live are found automatically.
# Needs openssl. "1", "0" or "auto".
CERT_INFO="${CERT_INFO}"

# Additional certificate files (PEM), separated by spaces. Wildcards are
# allowed; paths must not contain spaces. Example:
#   CERT_FILES="/etc/ssl/private/mail.pem /opt/app/certs/*.crt"
CERT_FILES="${CERT_FILES}"

# A certificate that expires within this many days is a warning.
# certbot renews 30 days before expiry, so a value below 30 only warns when
# a renewal has actually failed.
CERT_WARN_DAYS="${CERT_WARN_DAYS}"

# Maximum number of certificates listed, the ones expiring first on top.
# The rest is summarized in one line. 0 = no limit.
CERT_MAX_LIST="${CERT_MAX_LIST}"


##############################################################################
# Backups
##############################################################################

# Age of the newest file below each backup path. "1", "0" or "auto"
# (shown when BACKUP_PATHS is not empty).
BACKUP_INFO="${BACKUP_INFO}"

# Directories or files to check, separated by spaces. Directories are
# searched three levels deep. Wildcards are allowed; paths must not contain
# spaces. Example:
#   BACKUP_PATHS="/mnt/backup/daily /var/backups/db.sql.gz"
BACKUP_PATHS="${BACKUP_PATHS}"

# A path whose newest file is older than this many hours is a warning.
# 0 = never warn.
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS}"


##############################################################################
# Fail2Ban
##############################################################################

# Banned addresses per jail. Needs fail2ban-client. "1", "0" or "auto".
FAIL2BAN_INFO="${FAIL2BAN_INFO}"

# "1" shows the section even when FAIL2BAN_INFO="0".
FAIL2BAN_ALWAYS="${FAIL2BAN_ALWAYS}"

# "1" lists the banned addresses of each jail, "0" shows the totals only.
SHOWFAIL2BAN_IPS="${SHOWFAIL2BAN_IPS}"

# "1" looks up the host name of every listed address (reverse DNS, in
# parallel, one second time limit each). Needs SHOWFAIL2BAN_IPS="1".
RESOLVEFAIL2BAN_IPS="${RESOLVEFAIL2BAN_IPS}"

# Maximum number of addresses listed per jail. 0 = no limit.
FAIL2BAN_MAX_IPS="${FAIL2BAN_MAX_IPS}"


##############################################################################
# Maintenance log
##############################################################################

# The most recent entries of the maintenance log
# (dynmotd -a "note" adds one, dynmotd -l lists all). "1" or "0".
MAINTENANCE_INFO="${MAINTENANCE_INFO}"

# "1" shows the section even when MAINTENANCE_INFO="0".
MAINTENANCE_ALWAYS="${MAINTENANCE_ALWAYS}"

# Number of entries shown.
LIST_LOG_ENTRY="${LIST_LOG_ENTRY}"


##############################################################################
# Footer
##############################################################################

# Version banner at the bottom. "1" or "0".
VERSION_INFO="${VERSION_INFO}"
EOF
}


## Prints the name of every setting, one per line, in file order.
## The list is derived from the template once per run and then reused.
_CONFIG_KEYS=""
function _config_keys() {
    [ -n "$_CONFIG_KEYS" ] \
        || _CONFIG_KEYS=$(_config_template | sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p')
    printf '%s\n' "$_CONFIG_KEYS"
}


## Problems found while reading the configuration; shown by show_config_info.
CONFIG_WARNINGS=()

## Remembers the built-in default of every setting as _DEF_<KEY>, so invalid
## values can fall back to it. Must run before _load_config.
function _capture_defaults() {
    local key
    _config_keys >/dev/null     # fill the key list in this shell, not a subshell
    for key in $_CONFIG_KEYS; do
        printf -v "_DEF_${key}" '%s' "${!key}"
    done
}


## Reads the configuration file. It is parsed as text and never executed, so
## a typo cannot break the login and the file cannot run code as root.
## Accepted per line: KEY="value", KEY='value' or KEY=value, optionally
## followed by a # comment. Unknown settings and unreadable lines are reported.
## Returns 1 if there is no usable configuration file.
function _load_config() {
    [ -f "$CONFFILE" ] || return 1

    ## Only trust a file that belongs to root and that nobody else can write
    local owner perms
    owner=$(stat -c '%U' "$CONFFILE" 2>/dev/null)
    perms=$(stat -c '%a' "$CONFFILE" 2>/dev/null)
    if [ "$owner" != "root" ]; then
        CONFIG_WARNINGS+=("ignored: not owned by root")
        return 1
    fi
    if [[ "$perms" =~ ^[0-7]+$ ]] && (( 8#$perms & 8#022 )); then
        CONFIG_WARNINGS+=("ignored: writable by group or others (chmod 600)")
        return 1
    fi

    local known line key val n=0
    local re_assign='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$'
    local re_dq='^"([^"]*)"[[:space:]]*(#.*)?$'
    local re_dq_greedy='^"(.*)"[[:space:]]*$'
    local re_sq="^'([^']*)'[[:space:]]*(#.*)?\$"
    _config_keys >/dev/null
    known=" ${_CONFIG_KEYS//$'\n'/ } "

    while IFS= read -r line || [ -n "$line" ]; do
        n=$(( n + 1 ))
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue

        if ! [[ "$line" =~ $re_assign ]]; then
            CONFIG_WARNINGS+=("line ${n}: not understood")
            continue
        fi
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"

        if [[ "$val" =~ $re_dq ]] || [[ "$val" =~ $re_sq ]] || [[ "$val" =~ $re_dq_greedy ]]; then
            val="${BASH_REMATCH[1]}"
        else
            val="${val%%[[:space:]]#*}"
            val="${val%"${val##*[![:space:]]}"}"
        fi

        if [[ "$known" == *" ${key} "* ]]; then
            printf -v "$key" '%s' "$val"
        else
            CONFIG_WARNINGS+=("line ${n}: unknown setting ${key}")
        fi
    done < "$CONFFILE"
    return 0
}


## Imports SYSFUNCTION / SYSENV / SYSSLA from the pre-1.20 environment.cfg
## while no configuration file exists yet. The old file was written by
## dynmotd itself as shell assignments, so it is read in a subshell.
function _import_legacy_env() {
    [ -f "$ENVFILE" ] && [ ! -f "$CONFFILE" ] || return 1
    [ "$(stat -c '%U' "$ENVFILE" 2>/dev/null)" = "root" ] || return 1

    local -a legacy
    mapfile -t legacy < <(
        # shellcheck source=/dev/null
        source "$ENVFILE" 2>/dev/null
        printf '%s\n%s\n%s\n' "${SYSFUNCTION:-}" "${SYSENV:-}" "${SYSSLA:-}"
    )
    [ -n "$SYSFUNCTION" ] || SYSFUNCTION="${legacy[0]:-}"
    [ -n "$SYSENV" ]      || SYSENV="${legacy[1]:-}"
    [ -n "$SYSSLA" ]      || SYSSLA="${legacy[2]:-}"
    return 0
}


## Resets a setting to its built-in default and reports it.
function _config_reset() {
    local def="_DEF_$1"
    CONFIG_WARNINGS+=("$1=\"${!1}\" is invalid, using \"${!def}\"")
    printf -v "$1" '%s' "${!def}"
}


## Validates every setting, so a typo in the configuration can neither break
## arithmetic nor switch a section into an undefined state.
function _sanitize_config() {
    local key

    for key in SYSTEM_INFO STORAGE_INFO NETWORK_INFO USER_INFO ENVIRONMENT_INFO \
               UPDATE_INFO MAINTENANCE_INFO VERSION_INFO WEATHER_ALWAYS \
               UPDATE_ALWAYS FAILED_SERVICES_ALWAYS FAIL2BAN_ALWAYS \
               MAINTENANCE_ALWAYS SHOWFAIL2BAN_IPS RESOLVEFAIL2BAN_IPS \
               SSH_PASSWORD_WARN; do
        case "${!key}" in 0|1) ;; *) _config_reset "$key" ;; esac
    done

    for key in TIMESYNC_INFO WEATHER_INFO RAID_INFO ZFS_INFO LVM_INFO \
               SECURITY_INFO FAILED_SERVICES_INFO DOCKER_INFO CERT_INFO \
               BACKUP_INFO FAIL2BAN_INFO; do
        case "${!key}" in 0|1|auto) ;; *) _config_reset "$key" ;; esac
    done

    for key in WEATHER_CACHE_HOURS LAST_LOGINS UPDATE_CACHE_HOURS DOCKER_MAX_LIST \
               CERT_WARN_DAYS CERT_MAX_LIST BACKUP_MAX_AGE_HOURS FAIL2BAN_MAX_IPS LIST_LOG_ENTRY \
               DISK_WARN_PERCENT INODE_WARN_PERCENT MEMORY_WARN_PERCENT \
               SWAP_WARN_PERCENT LOAD_WARN_PERCENT UPDATE_WARN_COUNT; do
        if [[ "${!key}" =~ ^[0-9]{1,9}$ ]]; then
            printf -v "$key" '%s' "$(( 10#${!key} ))"
        else
            _config_reset "$key"
        fi
    done

    case "$MOTD_MODE" in full|compact) ;; *) _config_reset MOTD_MODE ;; esac
    case "$WEATHER_UNITS" in ""|m|u|M) ;; *) _config_reset WEATHER_UNITS ;; esac
    case "$COLOR_SCHEME" in
        dot|hacker|alert|ocean|solarized|nord|amber|none|custom) ;;
        *) _config_reset COLOR_SCHEME ;;
    esac
    for key in COLOR_LABEL COLOR_BORDER COLOR_VALUE COLOR_WARN; do
        _color_code "${!key}" >/dev/null || _config_reset "$key"
    done

    ## Free text ends up in the terminal: no control characters
    local val
    for key in SYSFUNCTION SYSENV SYSSLA WEATHER_CITY CERT_FILES BACKUP_PATHS; do
        val="${!key}"
        printf -v "$key" '%s' "${val//[[:cntrl:]]/}"
    done
}


## Prints the escape sequence of a color name; returns 1 for unknown names.
function _color_code() {
    case "$1" in
        black)  printf '%s' "$C_BLACK" ;;   dgray)  printf '%s' "$C_DGRAY" ;;
        grey)   printf '%s' "$C_GREY" ;;    white)  printf '%s' "$C_WHITE" ;;
        red)    printf '%s' "$C_RED" ;;     lred)   printf '%s' "$C_LRED" ;;
        blue)   printf '%s' "$C_BLUE" ;;    lblue)  printf '%s' "$C_LBLUE" ;;
        cyan)   printf '%s' "$C_CYAN" ;;    lcyan)  printf '%s' "$C_LCYAN" ;;
        pink)   printf '%s' "$C_PINK" ;;    lpink)  printf '%s' "$C_LPINK" ;;
        green)  printf '%s' "$C_GREEN" ;;   lgreen) printf '%s' "$C_LGREEN" ;;
        brown)  printf '%s' "$C_BROWN" ;;   yellow) printf '%s' "$C_YELLOW" ;;
        *) return 1 ;;
    esac
}


## Sets F1–F4 from COLOR_SCHEME.
## F1 = labels/text   F2 = borders/separators   F3 = values   F4 = warnings
function _apply_colors() {
    case "$COLOR_SCHEME" in
        hacker)    F1=$C_GREEN; F2=$C_GREEN;  F3=$C_GREEN;  F4=$C_RED ;;
        alert)     F1=$C_RED;   F2=$C_RED;    F3=$C_RED;    F4=$C_LRED ;;
        ocean)     F1=$C_CYAN;  F2=$C_LBLUE;  F3=$C_WHITE;  F4=$C_LRED ;;
        solarized) F1=$C_GREY;  F2=$C_YELLOW; F3=$C_LCYAN;  F4=$C_LRED ;;
        nord)      F1=$C_LBLUE; F2=$C_LCYAN;  F3=$C_WHITE;  F4=$C_YELLOW ;;
        amber)     F1=$C_BROWN; F2=$C_YELLOW; F3=$C_WHITE;  F4=$C_LRED ;;
        none)      F1="";       F2="";        F3="";        F4="";  C_RESET="" ;;
        custom)
            F1=$(_color_code "$COLOR_LABEL");  F2=$(_color_code "$COLOR_BORDER")
            F3=$(_color_code "$COLOR_VALUE");  F4=$(_color_code "$COLOR_WARN")
            ;;
        *)         F1=$C_GREY;  F2=$C_PINK;   F3=$C_LGREEN; F4=$C_RED ;;
    esac
}


## Writes the configuration file from the current values (temp file + rename,
## mode 600). Existing values are kept because they were loaded at startup;
## settings new in this version get their defaults and all comments are
## restored. The imported pre-1.20 environment.cfg is removed afterwards.
function _write_config() {
    local tmp
    mkdir -p "$DYNMOTDDIR" 2>/dev/null || return 1
    tmp=$(mktemp "${CONFFILE}.XXXXXX" 2>/dev/null) || return 1
    if _config_template > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$CONFFILE"; then
        rm -f "$ENVFILE"
        return 0
    fi
    rm -f "$tmp"
    return 1
}


## Prints the settings of this version that the configuration file lacks.
function _config_missing_keys() {
    local key
    [ -f "$CONFFILE" ] || return 0
    for key in $(_config_keys); do
        grep -q "^[[:space:]]*${key}[[:space:]]*=" "$CONFFILE" || echo "$key"
    done
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
    echo "Assign a role and environment label for: $(_hostname_fqdn)"
    echo

    local answer
    echo -n "System Function (e.g. Webserver, Mailserver) [${cur_func}]: "
    read -r answer
    SYSFUNCTION="${answer:-$cur_func}"
    echo -n "Environment (DEV|TST|INT|PRD) [${cur_env}]: "
    read -r answer
    SYSENV="${answer:-$cur_env}"
    echo -n "Service Level (SLA1|SLA2|SLA3|None) [${cur_sla}]: "
    read -r answer
    SYSSLA="${answer:-$cur_sla}"

    ## The configuration is parsed as plain text: no quotes or control
    ## characters in the values
    SYSFUNCTION=$(printf '%s' "$SYSFUNCTION" | tr -d '"\000-\037\177')
    SYSENV=$(printf '%s' "$SYSENV" | tr -d '"\000-\037\177')
    SYSSLA=$(printf '%s' "$SYSSLA" | tr -d '"\000-\037\177')

    echo
    if _config_writable && _write_config; then
        echo "Configuration saved to $CONFFILE"
    else
        echo "Error: could not write $CONFFILE"
        return 1
    fi
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

    ## ISO timestamp with year, and who made the entry (the invoking user
    ## when called through sudo)
    local mydate who
    mydate=$(date +"%Y-%m-%d %H:%M:%S")
    who="${SUDO_USER:-$(id -un 2>/dev/null)}"
    printf '%s [%s] %s\n' "$mydate" "${who:-root}" "${1//[$'\n\r']/}" >> "$MAINLOG" \
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

    ## Create the configuration file, or refresh it: existing values are kept,
    ## settings that are new in this version are added
    if ! _config_writable; then
        echo "Warning: ${CONFFILE} was not read (${CONFIG_WARNINGS[0]:-unknown reason}) and is left untouched."
    elif _write_config; then
        echo "Configuration: ${CONFFILE}"
    else
        echo "Warning: could not write ${CONFFILE}"
    fi

    ## Run first-time setup if needed
    [ -z "${SYSFUNCTION}${SYSENV}${SYSSLA}" ] && [ -t 0 ] && { echo; createenv; }
    [ ! -f "$MAINLOG" ]  && _createmaintenance

    echo
    echo "Installation complete."
    echo "Log out and back in (or: sudo -i) to see dynmotd on next login."
}


## --update: replace binary without running setup (safe for Ansible/Puppet/cron)
## Only the binary is replaced — maintenance log and configuration are untouched.
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

    ## The configuration is not touched here; only say if it could be refreshed
    local -a missing
    mapfile -t missing < <(_config_missing_keys)
    if (( ${#missing[@]} > 0 )); then
        echo "${#missing[@]} settings of this version are not in ${CONFFILE} yet and use their defaults."
        echo "Add them, documented, with: ${DYNMOTD_FILENAME} --genconfig"
    fi
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
        [ -f "$CONFFILE" ] && echo "  dynmotd.conf     (configuration)"
        [ -f "$MAINLOG" ]  && echo "  maintenance.log  ($(grep -c '' "$MAINLOG") entries)"
        [ -f "$ENVFILE" ]  && echo "  environment.cfg  (pre-1.20 configuration)"
        echo "  caches"
        echo
        ## Default is YES: uninstall leaves nothing behind unless told otherwise
        echo -n "Also delete configuration, log and caches in ${DYNMOTDDIR}/? [Y/n]: "
        read -r OPT_DATA
        [[ "$OPT_DATA" =~ ^[Nn]$ ]] || remove_data=true
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
    _kv_warn "$1" "$2 not installed (hide: $3=\"0\")"
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


## Records a line that needs attention. Compact mode and --json read these
## records; the full view is not affected. fd 3 is opened per section by
## _run_sections, _DYNMOTD_FLAGS tells whether it is there.
## Usage: _flag <label> <value>
function _flag() {
    [ -n "$_DYNMOTD_FLAGS" ] || return 0
    printf '%s\t%s\n' "$1" "${2//$'\n'/ }" >&3
    return 0
}


## Prints a "label = value" line in the warning color and records it.
## Usage: _kv_warn <label> <value> [label width=LABEL_WIDTH]
function _kv_warn() {
    _kv "$1" "$2" "$F4" "${3:-}"
    _flag "$1" "$2"
}


## True if a section switch is "1" or "auto".
## Usage: _enabled <switch variable>
function _enabled() {
    case "${!1}" in
        1|auto) return 0 ;;
    esac
    return 1
}


## Decides whether a section that depends on a tool runs.
##   switch "1"     run; if the tool is missing, print the section header
##                  with a notice and return 1
##   switch "auto"  run only if the tool is installed, otherwise stay silent
##   switch "0"     return 1
## Usage: _section_ready <switch variable> <label> <tool> <section title> || return
function _section_ready() {
    _enabled "$1" || return 1
    command -v "$3" >/dev/null 2>&1 && return 0
    if [ "${!1}" = "1" ]; then
        echo -e "\n$(_section_header "$4")"
        _missing_tool "$2" "$3" "$1"
        printf "${F1}"
    fi
    return 1
}


## Prints the fully qualified host name.
## hostname --fqdn does a DNS lookup and can hang when the resolver is down.
function _hostname_fqdn() {
    local name
    name=$(_timeout 2 hostname --fqdn 2>/dev/null)
    [ -n "$name" ] || name=$(hostname 2>/dev/null)
    echo "${name:-Unknown}"
}


## Prints the uptime as "up X days, Y hours".
## uptime -p needs procps >= 3.3.0; older systems get the classic format.
function _uptime_text() {
    uptime -p 2>/dev/null \
        || uptime | awk -F'up ' '{print $2}' | cut -d, -f1,2 | xargs
}


## Sets _KFLAVOR to the flavor of a kernel release: the release without its
## version numbers, e.g. "6.12.117+deb13-cloud-amd64" -> "deb-cloud-amd".
## Kernels are only compared within the same flavor.
function _kernel_flavor() {
    local rest="$1"
    [[ "$1" =~ ^[0-9][0-9.]*(-[0-9][0-9.]*)?(.*)$ ]] && rest="${BASH_REMATCH[2]}"
    _KFLAVOR="${rest//[0-9.+_]/}"
}


## Prints the newest installed kernel of the running flavor if it is newer
## than the running one (a reboot would activate it). Prints nothing when the
## running kernel is current or when this cannot be determined.
function _newer_kernel() {
    local running dir ver flavor best newest
    running=$(uname -r)
    [ -d /lib/modules ] || return 0
    ## sort -V: coreutils >= 7.0, recent busybox
    printf '1\n' | sort -V >/dev/null 2>&1 || return 0

    _kernel_flavor "$running"
    flavor="$_KFLAVOR"

    best=$(for dir in /lib/modules/*/; do
               ver="${dir%/}"; ver="${ver##*/}"
               _kernel_flavor "$ver"
               [ "$_KFLAVOR" = "$flavor" ] || continue
               ## Count only kernels that still have a boot image, where the
               ## distribution names images after the release at all
               [ -e "/boot/vmlinuz-${ver}" ] || [ ! -e "/boot/vmlinuz-${running}" ] || continue
               echo "$ver"
           done | sort -V | tail -n 1)

    [ -n "$best" ] && [ "$best" != "$running" ] || return 0
    newest=$(printf '%s\n%s\n' "$running" "$best" | sort -V | tail -n 1)
    [ "$newest" = "$best" ] && echo "$best"
    return 0
}


## Prints "yes" or "no" depending on whether the system clock is synchronized.
## Returns 1 if no tool can tell.
function _time_sync_state() {
    local out
    if command -v timedatectl >/dev/null 2>&1; then
        ## "System clock synchronized: yes" (older systemd: "NTP synchronized: yes")
        out=$(_timeout 3 env LC_ALL=C timedatectl status 2>/dev/null \
            | awk -F': *' '/synchronized:/ {print $2; exit}')
        case "$out" in
            yes|no) echo "$out"; return 0 ;;
        esac
    fi
    if command -v chronyc >/dev/null 2>&1; then
        out=$(_timeout 3 env LC_ALL=C chronyc tracking 2>/dev/null \
            | awk -F': *' '/^Leap status/ {print $2; exit}')
        case "$out" in
            Normal)  echo "yes"; return 0 ;;
            Not*)    echo "no";  return 0 ;;
        esac
    fi
    if command -v ntpstat >/dev/null 2>&1; then
        _timeout 3 ntpstat >/dev/null 2>&1
        case $? in
            0) echo "yes"; return 0 ;;
            1) echo "no";  return 0 ;;
        esac
    fi
    return 1
}


## Prints an age in seconds as "N minutes", "N hours" or "N days".
function _human_age() {
    local s="$1"
    if   (( s < 7200 ));   then echo "$(( s / 60 )) minutes"
    elif (( s < 172800 )); then echo "$(( s / 3600 )) hours"
    else                        echo "$(( s / 86400 )) days"
    fi
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
    local val max width fill="${4:-$F3}"
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

    printf "${F2}[${fill}%s${F1}%s${F2}]${fill} %3d%%" \
        "$bar_filled" "$bar_empty" "$pct"
}


function show_system_info() {
    [ "$SYSTEM_INFO" = "1" ] || return

    local HOSTNAME IPV4 IPV6 UNAME DISTRIBUTION PLATFORM UPTIME
    local CPUS CPUMODEL LOADAVG MEMAVAIL MEMMAX MEMUSED SWAPFREE SWAPMAX SWAPUSED PROCCOUNT PROCMAX

    HOSTNAME=$(_hostname_fqdn)

    ## IPv4 + IPv6: all non-loopback addresses, link-local IPv6 excluded
    IPV4=$(_list_addresses 4 | xargs)
    IPV6=$(_list_addresses 6 | grep -vi '^fe80' | xargs)
    [ -z "$IPV4" ] && IPV4="Unknown"

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
    UPTIME=$(_uptime_text)

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

    echo -e "\n$(_section_header "System Info")"
    _kv "Hostname"   "$HOSTNAME"
    _kv "Address v4" "$IPV4"
    [ -n "$IPV6" ] && _kv "Address v6" "$IPV6"

    ## A newer installed kernel of the same flavor means a reboot is pending
    local newer
    newer=$(_newer_kernel)
    _kv "Kernel" "$UNAME"
    [ -n "$newer" ] && _kv_warn "Newer Kernel" "${newer} installed, reboot to activate"

    _kv "Distribution" "${DISTRIBUTION} ${PLATFORM}"
    _kv "Uptime"       "$UPTIME"

    ## Load warning: 1-minute load in percent of the CPU count
    if (( LOAD_WARN_PERCENT > 0 )) && awk -v l="${LOADAVG%% *}" -v c="$CPUS" -v t="$LOAD_WARN_PERCENT" \
            'BEGIN { exit !(l * 100 >= c * t) }' 2>/dev/null; then
        _kv_warn "Load Average" "${LOADAVG} (1m 5m 15m), high for ${CPUS} CPUs"
    else
        printf "${F1}%${LABEL_WIDTH}s ${F2}= ${F3}%s ${F1}(1m 5m 15m)\n" "Load Average" "$LOADAVG"
    fi

    _kv "CPU" "${CPUS} x ${CPUMODEL}"

    ## Memory and swap bars turn to the warning color at their thresholds
    local color pct
    color="$F3"; pct=0
    (( MEMMAX > 0 )) && pct=$(( MEMUSED * 100 / MEMMAX ))
    if (( MEMORY_WARN_PERCENT > 0 && pct >= MEMORY_WARN_PERCENT )); then
        color="$F4"
        _flag "Memory" "${pct}% used, ${MEMAVAIL} MB free of ${MEMMAX} MB"
    fi
    printf "${F1}%${LABEL_WIDTH}s ${F2}= %s  ${color}%s\n" "Memory" \
        "$(_progress_bar "$MEMUSED" "$MEMMAX" "$bar_width" "$color")" \
        "${MEMAVAIL} MB free of ${MEMMAX} MB"

    color="$F3"; pct=0
    (( SWAPMAX > 0 )) && pct=$(( SWAPUSED * 100 / SWAPMAX ))
    if (( SWAP_WARN_PERCENT > 0 && pct >= SWAP_WARN_PERCENT )); then
        color="$F4"
        _flag "Swap Memory" "${pct}% used, ${SWAPFREE} MB free of ${SWAPMAX} MB"
    fi
    printf "${F1}%${LABEL_WIDTH}s ${F2}= %s  ${color}%s\n" "Swap Memory" \
        "$(_progress_bar "$SWAPUSED" "$SWAPMAX" "$bar_width" "$color")" \
        "${SWAPFREE} MB free of ${SWAPMAX} MB"

    _kv "Processes" "${PROCCOUNT} of ${PROCMAX} MAX"

    ## Clock synchronization. "auto" stays silent when no tool can tell.
    if _enabled TIMESYNC_INFO; then
        local sync
        if sync=$(_time_sync_state); then
            if [ "$sync" = "yes" ]; then
                _kv "Time Sync" "yes"
            else
                _kv_warn "Time Sync" "no, the system clock is not synchronized"
            fi
        elif [ "$TIMESYNC_INFO" = "1" ]; then
            _kv_warn "Time Sync" "unknown, needs timedatectl, chronyc or ntpstat (hide: TIMESYNC_INFO=\"0\")"
        fi
    fi
    printf "${F1}"
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

    echo -e "\n$(_section_header "Update Info")"
    if [[ "$UPDATES" =~ ^[0-9]+$ ]] && (( UPDATE_WARN_COUNT > 0 && UPDATES >= UPDATE_WARN_COUNT )); then
        _kv_warn "Available Updates" "$UPDATES"
    else
        _kv "Available Updates" "$UPDATES"
    fi
    if [ "$REBOOT_REQUIRED" = "Yes" ]; then
        _kv_warn "Reboot Required" "Yes"
    else
        _kv "Reboot Required" "$REBOOT_REQUIRED"
    fi
    _kv "Reboot Packages" "$REBOOT_PACKAGES"
    printf "${F1}"
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
    local filter='docker|tmpfs|devtmpfs|squashfs|udev|overlay|shm|cgroupfs|efivarfs'
    local -a rows
    mapfile -t rows < <(_timeout 5 env LC_ALL=C df -hTP 2>/dev/null \
        | awk -v filter="$filter" 'NR > 1 && $0 !~ filter {
            pct=$6; gsub(/%/,"",pct)
            mount=$7; for (i=8; i<=NF; i++) mount = mount " " $i
            printf "%d|%s|%s|%s|%s|%s\n", pct+0,$2,$3,$4,$5,mount
        }' \
        | sort -t'|' -k1,1 -rn)

    if (( ${#rows[@]} == 0 )); then
        _kv_warn "Filesystems" "no data available (df failed or timed out)"
        printf "${F1}"
        return
    fi

    ## The mount point is the label; a mount point longer than the label
    ## column widens it for the whole section so the = stays in one column.
    local row pct type size used mount bar color field=$LABEL_WIDTH
    for row in "${rows[@]}"; do
        mount="${row##*|}"
        (( ${#mount} > field )) && field=${#mount}
    done

    for row in "${rows[@]}"; do
        IFS='|' read -r pct type size used _ mount <<< "$row"
        color="$F3"
        if (( DISK_WARN_PERCENT > 0 && pct >= DISK_WARN_PERCENT )); then
            color="$F4"
            _flag "$mount" "${pct}% used, ${used} of ${size}"
        fi
        bar=$(_progress_bar "$pct" "100" "$bar_width" "$color")
        printf "${F1}%${field}s ${F2}= %s  ${color}%5s ${F1}used of${color} %5s  ${F1}%s\n" \
            "$mount" "$bar" "$used" "$size" "$type"
    done

    ## Inode usage is only worth a line when it gets tight: a filesystem can
    ## be full with plenty of free space left.
    if (( INODE_WARN_PERCENT > 0 )); then
        local ipct iused itotal
        while IFS='|' read -r ipct iused itotal mount; do
            _kv_warn "$mount" "inodes ${ipct}% used, ${iused} of ${itotal}" "$field"
        done < <(_timeout 5 env LC_ALL=C df -iP 2>/dev/null \
            | awk -v filter="$filter" -v t="$INODE_WARN_PERCENT" 'NR > 1 && $0 !~ filter {
                pct=$5; gsub(/%/,"",pct)
                if (pct+0 >= t) {
                    mount=$6; for (i=7; i<=NF; i++) mount = mount " " $i
                    printf "%d|%s|%s|%s\n", pct+0,$3,$2,mount
                }
            }')
    fi

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
    if [ -z "${SYSFUNCTION}${SYSENV}${SYSSLA}" ]; then
        _kv_warn "Environment" "not configured, run: ${DYNMOTD_FILENAME} --config"
    else
        _kv "Function"      "${SYSFUNCTION:--}"
        _kv "Environment"   "${SYSENV:--}"
        _kv "Service Level" "${SYSSLA:--}"
    fi
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
    _enabled FAIL2BAN_INFO || [ "$FAIL2BAN_ALWAYS" = "1" ] || return

    if ! command -v fail2ban-client >/dev/null 2>&1; then
        [ "$FAIL2BAN_INFO" = "auto" ] && [ "$FAIL2BAN_ALWAYS" != "1" ] && return
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
        _kv_warn "Fail2Ban" "not running or no active jails"
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
        state=$(printf '%s' "$state" | tr '[:lower:]' '[:upper:]')
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
    _section_ready FAILED_SERVICES_INFO "Failed Services" systemctl "Failed Services" || return

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
        _kv_warn "$u" "failed" "$field"
    done
    printf "${F1}"
}


## A wttr.in answer is usable if it is one short line with the six
## pipe-separated fields we asked for (error pages are HTML or plain text).
function _weather_valid() {
    [[ "$1" == *'|'*'|'*'|'*'|'*'|'* ]] && [[ "$1" != *'<'* ]] && (( ${#1} < 200 ))
}


function show_weather_info() {
    _enabled WEATHER_INFO || [ "$WEATHER_ALWAYS" = "1" ] || return

    local weather="" cached=""

    if ! command -v curl >/dev/null 2>&1; then
        [ "$WEATHER_INFO" = "auto" ] && [ "$WEATHER_ALWAYS" != "1" ] && return
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


function show_config_info() {
    (( ${#CONFIG_WARNINGS[@]} > 0 )) || return

    echo -e "\n$(_section_header "Configuration")"
    _kv "Config File" "$CONFFILE"

    ## Problems found while reading the configuration, at most eight
    local i max=${#CONFIG_WARNINGS[@]}
    (( max > 8 )) && max=8
    for (( i = 0; i < max; i++ )); do
        _kv_warn "Problem" "${CONFIG_WARNINGS[$i]}"
    done
    (( ${#CONFIG_WARNINGS[@]} > max )) \
        && printf "${F1}%$(( LABEL_WIDTH + 3 ))s... and %d more\n" "" $(( ${#CONFIG_WARNINGS[@]} - max ))
    printf "${F1}"
}


function show_raid_info() {
    _enabled RAID_INFO || return

    if [ ! -r /proc/mdstat ]; then
        if [ "$RAID_INFO" = "1" ]; then
            echo -e "\n$(_section_header "Software RAID")"
            _kv_warn "Software RAID" "/proc/mdstat not available (hide: RAID_INFO=\"0\")"
            printf "${F1}"
        fi
        return
    fi

    ## /proc/mdstat, one block per array:
    ##   md0 : active raid1 sdb1[1] sda1[0]
    ##         976630464 blocks super 1.2 [2/2] [UU]
    ##         [==>......]  recovery = 12.6% (...) finish=127.5min
    ## Output: name|state|level|devices|map|progress
    local -a rows
    mapfile -t rows < <(awk '
        function emit() {
            if (name != "") printf "%s|%s|%s|%s|%s|%s\n", name, state, level, devs, map, prog
        }
        /^md[^ ]* :/ {
            emit()
            name = $1; state = $3; level = "-"; devs = ""; map = ""; prog = ""
            for (i = 4; i <= NF; i++)
                if ($i ~ /^(raid|linear|multipath|faulty)/) { level = $i; break }
            next
        }
        name != "" {
            if (match($0, /\[[0-9]+\/[0-9]+\] \[[U_]+\]/)) {
                split(substr($0, RSTART, RLENGTH), part, " ")
                devs = part[1]; map = part[2]
                gsub(/\[|\]/, "", devs)
            }
            for (i = 1; i < NF - 1; i++)
                if ($i ~ /^(recovery|resync|reshape|check)$/ && $(i+1) == "=") prog = $i " " $(i+2)
        }
        END { emit() }
    ' /proc/mdstat 2>/dev/null)

    if (( ${#rows[@]} == 0 )); then
        [ "$RAID_INFO" = "1" ] || return
        echo -e "\n$(_section_header "Software RAID")"
        _kv "Software RAID" "no arrays"
        printf "${F1}"
        return
    fi

    echo -e "\n$(_section_header "Software RAID")"
    local row name state level devs map prog text
    for row in "${rows[@]}"; do
        IFS='|' read -r name state level devs map prog <<< "$row"
        text="$level"
        [ "$text" = "-" ] && text=""
        ## devs is "<expected>/<working>"
        [ -n "$map" ]  && text+="  ${map}  ${devs#*/} of ${devs%/*} devices"
        [ -n "$prog" ] && text+=", ${prog}"
        if [ "$state" != "active" ]; then
            _kv_warn "$name" "${state}${text:+  $text}"
        elif [[ "$map" == *_* ]]; then
            _kv_warn "$name" "DEGRADED  ${text}"
        else
            _kv "$name" "$text"
        fi
    done
    printf "${F1}"
}


function show_zfs_info() {
    _section_ready ZFS_INFO "ZFS" zpool "ZFS Pools" || return

    ## -H: tab-separated, no header
    local -a rows
    mapfile -t rows < <(_timeout 5 zpool list -H -o name,size,alloc,cap,health 2>/dev/null)

    if (( ${#rows[@]} == 0 )); then
        [ "$ZFS_INFO" = "1" ] || return
        echo -e "\n$(_section_header "ZFS Pools")"
        _kv "ZFS" "no pools"
        printf "${F1}"
        return
    fi

    echo -e "\n$(_section_header "ZFS Pools")"
    local bar_width
    bar_width=$(_bar_width)

    local row name size alloc cap health color
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r name size alloc cap health <<< "$row"
        cap=$(_to_int "${cap%\%}" 0)
        color="$F3"
        if [ "$health" != "ONLINE" ]; then
            color="$F4"
            _flag "$name" "pool is ${health}"
        elif (( DISK_WARN_PERCENT > 0 && cap >= DISK_WARN_PERCENT )); then
            color="$F4"
            _flag "$name" "${cap}% used, ${alloc} of ${size}"
        fi
        printf "${F1}%${LABEL_WIDTH}s ${F2}= %s  ${color}%5s ${F1}used of${color} %5s  %s\n" \
            "$name" "$(_progress_bar "$cap" 100 "$bar_width" "$color")" "$alloc" "$size" "$health"
    done
    printf "${F1}"
}


function show_lvm_info() {
    _section_ready LVM_INFO "LVM" vgs "LVM Volume Groups" || return

    local -a rows
    mapfile -t rows < <(_timeout 5 vgs --noheadings --separator '|' \
        -o vg_name,vg_size,vg_free,lv_count,pv_count 2>/dev/null | grep '|')

    if (( ${#rows[@]} == 0 )); then
        [ "$LVM_INFO" = "1" ] || return
        echo -e "\n$(_section_header "LVM Volume Groups")"
        _kv "LVM" "no volume groups"
        printf "${F1}"
        return
    fi

    echo -e "\n$(_section_header "LVM Volume Groups")"
    local row name size free lvs pvs
    for row in "${rows[@]}"; do
        IFS='|' read -r name size free lvs pvs <<< "${row//[[:space:]]/}"
        _kv "$name" "${size} total, ${free} free, ${lvs} LV, ${pvs} PV"
    done
    printf "${F1}"
}


## Prints the lines of the Login Security section. Every line is optional:
## it is left out when its tool or data source is not there.
function _security_lines() {
    local out

    ## Effective sshd settings. sshd -T resolves includes and defaults, which
    ## reading sshd_config by hand would get wrong.
    local sshd_bin
    sshd_bin=$(command -v sshd 2>/dev/null) || sshd_bin="/usr/sbin/sshd"
    if [ -x "$sshd_bin" ] && out=$(_timeout 5 "$sshd_bin" -T 2>/dev/null) && [ -n "$out" ]; then
        local root_login passwords ports
        root_login=$(awk '$1 == "permitrootlogin" {print $2; exit}' <<< "$out")
        passwords=$(awk '$1 == "passwordauthentication" {print $2; exit}' <<< "$out")
        ports=$(awk '$1 == "port" {printf "%s%s", (n++ ? ", " : ""), $2}' <<< "$out")

        if [ "$root_login" = "yes" ]; then
            _kv_warn "SSH Root Login" "yes, root can log in with a password"
        elif [ -n "$root_login" ]; then
            _kv "SSH Root Login" "$root_login"
        fi

        if [ "$passwords" = "yes" ] && [ "$SSH_PASSWORD_WARN" = "1" ]; then
            _kv_warn "SSH Passwords" "yes, password logins are allowed"
        elif [ -n "$passwords" ]; then
            _kv "SSH Passwords" "$passwords"
        fi

        [ -n "$ports" ] && _kv "SSH Port" "$ports"
    fi

    ## Failed logins since the last log rotation. /var/log/btmp can be very
    ## large on an exposed host, so the count comes from the file size: every
    ## record has the same size (384 bytes, or 400 on 64-bit architectures
    ## without 32-bit compatibility such as arm64).
    if [ -f /var/log/btmp ]; then
        local size rec=0
        size=$(stat -c %s /var/log/btmp 2>/dev/null)
        size=$(_to_int "$size" 0)
        if   (( size % 384 == 0 && size % 400 != 0 )); then rec=384
        elif (( size % 400 == 0 && size % 384 != 0 )); then rec=400
        elif (( size % 384 == 0 )); then
            case "$(uname -m)" in
                x86_64|i?86|arm*) rec=384 ;;
                *)                rec=400 ;;
            esac
        fi
        if (( rec > 0 )); then
            local since=""
            [ -f /var/log/btmp.1 ] && since=$(stat -c %y /var/log/btmp.1 2>/dev/null | cut -c1-10)
            if [ -n "$since" ]; then
                _kv "Failed Logins" "$(( size / rec )) since ${since}"
            else
                _kv "Failed Logins" "$(( size / rec ))"
            fi
        fi
    fi

    ## Most recent logins. -F prints full timestamps with the year at a fixed
    ## position, -a moves the origin to the end of the line:
    ##   cray pts/2 Sat Nov 14 13:56:52 2026 - Sat Nov 14 14:32:19 2026 (00:35) 192.0.2.7
    if (( LAST_LOGINS > 0 )) && command -v last >/dev/null 2>&1; then
        local -a logins
        mapfile -t logins < <(_timeout 5 env LC_ALL=C last -a -F -n "$(( LAST_LOGINS * 4 ))" 2>/dev/null \
            | awk -v max="$LAST_LOGINS" '
                NF >= 7 && $7 ~ /^[0-9][0-9][0-9][0-9]$/ && $1 != "reboot" && $1 != "shutdown" && $1 != "runlevel" {
                    host = $NF
                    if (host ~ /^\(.*\)$/ || host == "in" || host == "logout" || host == $7) host = "local"
                    printf "%s %2d %s %s  %s from %s\n", $4, $5, substr($6, 1, 5), $7, $1, host
                    if (++n >= max) exit
                }')
        if (( ${#logins[@]} > 0 )); then
            _kv "Last Logins" "${logins[0]}"
            local i
            for (( i = 1; i < ${#logins[@]}; i++ )); do
                printf "${F3}%$(( LABEL_WIDTH + 3 ))s%s\n" "" "${logins[$i]}"
            done
        fi
    fi
}


function show_security_info() {
    _enabled SECURITY_INFO || return

    local body
    body=$(_security_lines)
    [ -n "$body" ] || return

    echo -e "\n$(_section_header "Login Security")"
    printf '%s\n' "$body"
    printf "${F1}"
}


function show_docker_info() {
    _section_ready DOCKER_INFO "Docker" docker "Docker" || return

    echo -e "\n$(_section_header "Docker")"

    local out
    if ! out=$(_timeout 5 docker ps -a --format '{{.Names}}|{{.Status}}' 2>/dev/null); then
        _kv_warn "Docker" "daemon not reachable"
        printf "${F1}"
        return
    fi

    ## Status text: "Up 3 days", "Up 2 hours (unhealthy)", "Up 5 minutes (Paused)",
    ## "Restarting (1) 5 seconds ago", "Exited (137) 3 days ago", "Created", "Dead"
    local name status running=0 stopped=0 paused=0 field=$LABEL_WIDTH
    local -a p_names=() p_states=()
    while IFS='|' read -r name status; do
        [ -n "$name" ] || continue
        case "$status" in
            Up*"(unhealthy)"*)
                running=$(( running + 1 ))
                p_names+=("$name"); p_states+=("unhealthy") ;;
            Up*"(Paused)"*)
                paused=$(( paused + 1 )) ;;
            Up*)
                running=$(( running + 1 )) ;;
            Restarting*)
                p_names+=("$name"); p_states+=("restarting") ;;
            Dead*)
                p_names+=("$name"); p_states+=("dead") ;;
            "Exited (0)"*|Created*)
                stopped=$(( stopped + 1 )) ;;
            Exited*)
                ## non-zero exit code: the container crashed or was killed
                stopped=$(( stopped + 1 ))
                p_names+=("$name"); p_states+=("e${status#E}") ;;
            *)
                stopped=$(( stopped + 1 )) ;;
        esac
    done <<< "$out"

    local summary="${running} running, ${stopped} stopped"
    (( paused > 0 )) && summary+=", ${paused} paused"

    local shown=${#p_names[@]} i
    (( DOCKER_MAX_LIST > 0 && shown > DOCKER_MAX_LIST )) && shown=$DOCKER_MAX_LIST
    for (( i = 0; i < shown; i++ )); do
        (( ${#p_names[$i]} > field )) && field=${#p_names[$i]}
    done

    if (( ${#p_names[@]} > 0 )); then
        _kv_warn "Containers" "${summary}, ${#p_names[@]} need attention" "$field"
    else
        _kv "Containers" "$summary" "" "$field"
    fi
    for (( i = 0; i < shown; i++ )); do
        _kv_warn "${p_names[$i]}" "${p_states[$i]}" "$field"
    done
    (( ${#p_names[@]} > shown )) \
        && printf "${F1}%$(( field + 3 ))s... and %d more\n" "" $(( ${#p_names[@]} - shown ))
    printf "${F1}"
}


function show_certs_info() {
    _enabled CERT_INFO || return

    ## Certificates to check: every certbot lineage plus CERT_FILES.
    ## CERT_FILES is deliberately unquoted so wildcards expand; an entry that
    ## matches nothing stays as it is and is reported as missing.
    local -a files=() missing=()
    local f
    for f in /etc/letsencrypt/live/*/cert.pem; do
        [ -f "$f" ] && files+=("$f")
    done
    for f in $CERT_FILES; do
        if [ -f "$f" ]; then files+=("$f"); else missing+=("$f"); fi
    done

    ## Nothing to check: no section
    (( ${#files[@]} + ${#missing[@]} > 0 )) || return

    _section_ready CERT_INFO "Certificates" openssl "TLS Certificates" || return

    ## Label: the directory name for generic file names (certbot: the lineage
    ## name), otherwise the file name without its extension.
    local -a labels=()
    local label field=$LABEL_WIDTH
    for f in "${files[@]}" "${missing[@]}"; do
        label="${f##*/}"
        case "$label" in
            cert.pem|fullchain.pem|cert.crt|tls.crt)
                label="${f%/*}"; label="${label##*/}" ;;
            *)
                label="${label%.*}" ;;
        esac
        labels+=("$label")
    done

    ## Reading a certificate costs an openssl and a date call. With dozens of
    ## certificates that adds up on every login, so the expiry date is cached
    ## per file in cert_cache ("<mtime>:<path>" TAB <epoch> TAB <day>) and only
    ## read again when the file has changed. One stat call covers all files.
    local cache_file="${DYNMOTDDIR}/cert_cache" dirty=0
    local -a c_keys=() c_epochs=() c_days=() mtimes=() n_lines=()
    local key c_epoch c_day
    if [ -f "$cache_file" ]; then
        while IFS=$'\t' read -r key c_epoch c_day; do
            c_keys+=("$key"); c_epochs+=("$c_epoch"); c_days+=("$c_day")
        done < "$cache_file"
    fi
    (( ${#files[@]} > 0 )) && mapfile -t mtimes < <(stat -L -c '%Y' "${files[@]}" 2>/dev/null)
    (( ${#mtimes[@]} == ${#files[@]} )) || mtimes=()

    ## Collect "<expiry epoch>|<warning 0/1>|<label>|<text>" per certificate.
    ## Entries without a usable date get epoch 0 and sort to the top.
    local -a entries=()
    local i=0 n end epoch day days now
    now=$(date +%s)
    for f in "${files[@]}"; do
        label="${labels[$i]}"
        key="${mtimes[$i]:-0}:${f}"
        i=$(( i + 1 ))

        ## Cache lookup
        epoch=""; day=""
        if [ "${key%%:*}" != "0" ]; then
            for (( n = 0; n < ${#c_keys[@]}; n++ )); do
                if [ "${c_keys[$n]}" = "$key" ]; then
                    epoch="${c_epochs[$n]}"; day="${c_days[$n]}"
                    break
                fi
            done
        fi

        if ! [[ "$epoch" =~ ^[0-9]+$ ]]; then
            end=$(_timeout 5 openssl x509 -noout -enddate -in "$f" 2>/dev/null)
            end="${end#notAfter=}"
            if [ -z "$end" ]; then
                entries+=("0|1|${label}|not a readable certificate")
                continue
            fi

            ## "Mar  1 12:00:00 2027 GMT" -> epoch. GNU date parses it directly,
            ## busybox date needs the format spelled out.
            epoch=$(date -d "$end" +%s 2>/dev/null) \
                || epoch=$(date -D '%b %e %H:%M:%S %Y' -d "${end% GMT}" +%s 2>/dev/null) \
                || epoch=""

            if ! [[ "$epoch" =~ ^[0-9]+$ ]]; then
                ## No usable date arithmetic: let openssl compare against the clock
                if ! openssl x509 -noout -checkend 0 -in "$f" >/dev/null 2>&1; then
                    entries+=("0|1|${label}|EXPIRED (${end})")
                elif ! openssl x509 -noout -checkend $(( CERT_WARN_DAYS * 86400 )) -in "$f" >/dev/null 2>&1; then
                    entries+=("0|1|${label}|expires within ${CERT_WARN_DAYS} days (${end})")
                else
                    entries+=("9999999999|0|${label}|valid until ${end}")
                fi
                continue
            fi
            day=$(date -d "@${epoch}" +%Y-%m-%d 2>/dev/null) || day="$end"
            dirty=1
        fi
        n_lines+=("${key}"$'\t'"${epoch}"$'\t'"${day}")

        days=$(( (epoch - now) / 86400 ))
        if (( epoch <= now )); then
            entries+=("${epoch}|1|${label}|EXPIRED $(( (now - epoch) / 86400 )) days ago (${day})")
        elif (( days <= CERT_WARN_DAYS )); then
            entries+=("${epoch}|1|${label}|expires in ${days} days (${day})")
        else
            entries+=("${epoch}|0|${label}|${days} days left (${day})")
        fi
    done

    ## Rewrite the cache with the current files only, so it prunes itself
    if (( dirty )) || (( ${#n_lines[@]} != ${#c_keys[@]} )); then
        local tmp
        if tmp=$(mktemp "${cache_file}.XXXXXX" 2>/dev/null); then
            if (( ${#n_lines[@]} > 0 )); then printf '%s\n' "${n_lines[@]}" > "$tmp"; fi
            mv -f "$tmp" "$cache_file" 2>/dev/null || rm -f "$tmp"
        fi
    fi

    for f in "${missing[@]}"; do
        entries+=("0|1|${labels[$i]}|file not found: ${f}")
        i=$(( i + 1 ))
    done

    ## Earliest expiry first; list at most CERT_MAX_LIST and widen the label
    ## column only for the certificates that are actually listed
    local -a sorted
    mapfile -t sorted < <(printf '%s\n' "${entries[@]}" | sort -t'|' -k1,1n)

    local shown=${#sorted[@]} is_warn text
    (( CERT_MAX_LIST > 0 && shown > CERT_MAX_LIST )) && shown=$CERT_MAX_LIST
    field=$LABEL_WIDTH
    for (( i = 0; i < shown; i++ )); do
        IFS='|' read -r _ _ label _ <<< "${sorted[$i]}"
        (( ${#label} > field )) && field=${#label}
    done

    echo -e "\n$(_section_header "TLS Certificates")"
    for (( i = 0; i < shown; i++ )); do
        IFS='|' read -r _ is_warn label text <<< "${sorted[$i]}"
        if [ "$is_warn" = "1" ]; then
            _kv_warn "$label" "$text" "$field"
        else
            _kv "$label" "$text" "" "$field"
        fi
    done
    (( ${#sorted[@]} > shown )) \
        && printf "${F1}%$(( field + 3 ))s... and %d more that expire later\n" "" $(( ${#sorted[@]} - shown ))
    printf "${F1}"
}


function show_backup_info() {
    _enabled BACKUP_INFO || return

    if [ -z "$BACKUP_PATHS" ]; then
        [ "$BACKUP_INFO" = "1" ] || return
        echo -e "\n$(_section_header "Backups")"
        _kv_warn "Backups" "BACKUP_PATHS is empty (hide: BACKUP_INFO=\"0\")"
        printf "${F1}"
        return
    fi

    ## Deliberately unquoted so wildcards expand
    local -a paths=()
    local p field=$LABEL_WIDTH
    for p in $BACKUP_PATHS; do
        paths+=("$p")
        (( ${#p} > field )) && field=${#p}
    done

    echo -e "\n$(_section_header "Backups")"

    local newest age now text
    now=$(date +%s)
    for p in "${paths[@]}"; do
        if [ ! -e "$p" ]; then
            _kv_warn "$p" "not found" "$field"
            continue
        fi

        ## Modification time of the newest file, at most three levels deep.
        ## stat -c works with GNU and busybox; find -printf would not.
        newest=$(_timeout 10 find "$p" -maxdepth 3 -type f -exec stat -c %Y {} + 2>/dev/null \
            | sort -n | tail -n 1)
        if ! [[ "$newest" =~ ^[0-9]+$ ]]; then
            _kv_warn "$p" "no files found" "$field"
            continue
        fi

        age=$(( now - newest ))
        (( age < 0 )) && age=0
        text="newest file is $(_human_age "$age") old"
        if (( BACKUP_MAX_AGE_HOURS > 0 && age > BACKUP_MAX_AGE_HOURS * 3600 )); then
            _kv_warn "$p" "${text}, limit is ${BACKUP_MAX_AGE_HOURS} hours" "$field"
        else
            _kv "$p" "$text" "" "$field"
        fi
    done
    printf "${F1}"
}


## True if the configuration file may be rewritten from memory: it does not
## exist yet, or it was read successfully. A file that was ignored (wrong
## owner or permissions) is left alone, otherwise its content would be lost.
function _config_writable() {
    [ ! -f "$CONFFILE" ] || [ "$_CONFIG_STATE" = "loaded" ]
}


## Creates or refreshes the configuration file (--genconfig).
function genconfig() {
    if ! _config_writable; then
        echo "Not touching ${CONFFILE}: ${CONFIG_WARNINGS[0]:-it could not be read}."
        echo "Fix owner and permissions first: chown root ${CONFFILE}; chmod 600 ${CONFFILE}"
        return 1
    fi

    local existed=0
    [ -f "$CONFFILE" ] && existed=1

    local -a added
    mapfile -t added < <(_config_missing_keys)

    if ! _write_config; then
        echo "Error: could not write ${CONFFILE}"
        return 1
    fi

    if (( existed )); then
        echo "Configuration refreshed: ${CONFFILE}"
        echo "Your values were kept."
        (( ${#added[@]} > 0 )) && echo "Added settings: ${added[*]}"
    else
        echo "Configuration created: ${CONFFILE}"
    fi

    local w
    for w in "${CONFIG_WARNINGS[@]}"; do
        echo "Cleaned up: ${w}"
    done
}


## Display order — the single place that defines it. Every name needs a
## function show_<name>_info.
SECTIONS=(config system weather storage raid zfs lvm network user security
          update environment failed_services docker certs backup fail2ban
          maintenance version)

## Temp directory of the current run; removed by the EXIT trap.
_DYNMOTD_TMPDIR=""
## Set while sections may record warnings on fd 3 (see _flag).
_DYNMOTD_FLAGS=""


## Runs the given sections in parallel. Section NN writes its output to
## <tmpdir>/NN and its warning records to <tmpdir>/NN.warn, so the results can
## be collected in order once all sections are done.
## Returns 1 if no temp directory could be created.
function _run_sections() {
    local s i=0 out

    _DYNMOTD_TMPDIR=$(mktemp -d 2>/dev/null) || _DYNMOTD_TMPDIR=""
    [ -n "$_DYNMOTD_TMPDIR" ] || return 1

    _DYNMOTD_FLAGS=1
    for s in "$@"; do
        i=$(( i + 1 ))
        out=$(printf '%s/%02d' "$_DYNMOTD_TMPDIR" "$i")
        "show_${s}_info" > "$out" 3> "${out}.warn" &
    done

    wait  ## wait for all sections to complete
    _DYNMOTD_FLAGS=""
    return 0
}


function _cleanup_sections() {
    [ -n "$_DYNMOTD_TMPDIR" ] && rm -rf "$_DYNMOTD_TMPDIR"
    _DYNMOTD_TMPDIR=""
}


## Things that need a terminal or may write files happen here, in the
## foreground, before any section runs: sections are background jobs whose
## stdin is not the terminal, so they cannot prompt.
function _first_run_setup() {
    ## Create the configuration file on the first run (this also imports a
    ## pre-1.20 environment.cfg, which _write_config then removes)
    [ -f "$CONFFILE" ] || _write_config

    ## Ask for the host description once; skipped without a terminal
    if [ "$ENVIRONMENT_INFO" = "1" ] && [ -z "${SYSFUNCTION}${SYSENV}${SYSSLA}" ] \
        && [ -t 0 ] && [ -t 1 ] && _config_writable; then
        createenv
    fi
}


function show_info() {
    _check_dependencies \
        || echo "Warning: some dependencies are missing — output may be incomplete."

    _first_run_setup

    if [ "$MOTD_MODE" = "compact" ] && show_compact; then
        return
    fi

    local s
    if ! _run_sections "${SECTIONS[@]}"; then
        ## mktemp failed — fall back to sequential output
        for s in "${SECTIONS[@]}"; do
            "show_${s}_info"
        done
        echo -e "${C_RESET}"
        return
    fi

    cat "${_DYNMOTD_TMPDIR}"/[0-9][0-9] 2>/dev/null
    _cleanup_sections
    echo -e "${C_RESET}"
}


## Compact view: a short summary plus every line the full view would print as
## a warning. Returns 1 if the sections could not be run.
function show_compact() {
    _run_sections "${SECTIONS[@]}" || return 1

    local -a warn_labels=() warn_values=()
    local label value field=$LABEL_WIDTH
    while IFS=$'\t' read -r label value; do
        [ -n "$label" ] || continue
        warn_labels+=("$label"); warn_values+=("$value")
        (( ${#label} > field )) && field=${#label}
    done < <(cat "${_DYNMOTD_TMPDIR}"/[0-9][0-9].warn 2>/dev/null)
    _cleanup_sections

    echo -e "\n$(_section_header "Status")"
    _kv "Hostname"     "$(_hostname_fqdn)"                              "" "$field"
    _kv "Uptime"       "$(_uptime_text)"                                "" "$field"
    _kv "Load Average" "$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null)" "" "$field"

    if (( ${#warn_labels[@]} == 0 )); then
        _kv "Status" "OK, nothing needs attention" "" "$field"
    else
        _kv "Status" "${#warn_labels[@]} items need attention" "$F4" "$field"
        echo -e "\n$(_section_header "Attention")"
        local i
        for (( i = 0; i < ${#warn_labels[@]}; i++ )); do
            _kv "${warn_labels[$i]}" "${warn_values[$i]}" "$F4" "$field"
        done
    fi
    printf "${F1}"

    show_version_info
    echo -e "${C_RESET}"
    return 0
}


## --section: prints the named sections only, in the order given.
function show_section() {
    local s known=" ${SECTIONS[*]} "

    if [ $# -eq 0 ]; then
        echo "Usage: $(basename "$0") --section <name> [name...]"
        echo "Sections: ${SECTIONS[*]}"
        return 1
    fi
    for s in "$@"; do
        if [[ "$known" != *" ${s} "* ]]; then
            echo "Unknown section: ${s}"
            echo "Sections: ${SECTIONS[*]}"
            return 1
        fi
    done
    for s in "$@"; do
        "show_${s}_info"
    done
    echo -e "${C_RESET}"
}


## --json: the same information as the MOTD, machine-readable:
##   { "version": "...", "host": "...",
##     "sections": [ { "name": "...", "items": [ { "label": "...", "value": "..." } ] } ],
##     "warnings": [ { "label": "...", "value": "..." } ] }
## It is derived from the uniform "label = value" layout of the sections, so a
## new section shows up here without extra code.
function show_json() {
    ## No colors: the output is parsed
    F1=""; F2=""; F3=""; F4=""; C_RESET=""

    if ! _run_sections "${SECTIONS[@]}"; then
        echo '{"error":"could not create a temporary directory"}'
        return 1
    fi

    ## Shared awk helpers. Label lines start within the label column;
    ## continuation lines of wrapped values are indented beyond it.
    local awk_lib='
        function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }'

    printf '{"version":"%s","host":"%s","sections":[' \
        "${VERSION//\"/}" "$(_hostname_fqdn | tr -d '"\\')"

    cat "${_DYNMOTD_TMPDIR}"/[0-9][0-9] 2>/dev/null \
        | tr '\t' ' ' | tr -d '\000-\011\013-\037\177' \
        | awk -v col="$(( LABEL_WIDTH + 3 ))" "$awk_lib"'
        function flush_item() {
            if (have) printf "%s{\"label\":\"%s\",\"value\":\"%s\"}", (items++ ? "," : ""), esc(label), esc(value)
            have = 0
        }
        function close_section() {
            flush_item()
            if (open) printf "]}"
            open = 0
        }
        substr($0, 1, 14) == "============[ " {
            close_section()
            name = $0; sub(/^=+\[ /, "", name); sub(/ \]=*$/, "", name)
            printf "%s{\"name\":\"%s\",\"items\":[", (sections++ ? "," : ""), esc(name)
            open = 1; items = 0
            next
        }
        /^=+\[ / || !open || /^[ \t]*$/ { next }
        {
            match($0, /^ */)
            p = index($0, " = ")
            if (p > 0 && RLENGTH < col && RLENGTH < p) {
                flush_item()
                label = trim(substr($0, 1, p - 1)); value = trim(substr($0, p + 3)); have = 1
            } else if (have) {
                value = value " " trim($0)
            }
        }
        END { close_section() }'

    printf '],"warnings":['
    cat "${_DYNMOTD_TMPDIR}"/[0-9][0-9].warn 2>/dev/null \
        | tr -d '\000-\010\013-\037\177' \
        | awk -F'\t' "$awk_lib"'
        NF >= 2 { printf "%s{\"label\":\"%s\",\"value\":\"%s\"}", (n++ ? "," : ""), esc(trim($1)), esc(trim($2)) }'
    printf ']}\n'

    _cleanup_sections
}


## --check: which sections are active, which tools they need and whether the
## tools are there. Changes nothing.
function show_check() {
    echo -e "\n$(_section_header "dynmotd check")"
    _kv "Version" "$VERSION"
    _kv "Bash"    "$BASH_VERSION"

    if [ -f "$CONFFILE" ]; then
        _kv "Config File" "$CONFFILE"
    else
        _kv "Config File" "not created yet, built-in defaults apply (create: --genconfig)"
    fi
    local w
    for w in "${CONFIG_WARNINGS[@]}"; do
        _kv "Problem" "$w" "$F4"
    done
    local -a missing
    mapfile -t missing < <(_config_missing_keys)
    (( ${#missing[@]} > 0 )) \
        && _kv "New Settings" "${#missing[@]} not in the config file yet (add: --genconfig)"

    echo -e "\n$(_section_header "Required tools")"
    local cmd
    for cmd in grep sed awk hostname stat df; do
        if command -v "$cmd" >/dev/null 2>&1; then
            _kv "$cmd" "found"
        else
            _kv "$cmd" "MISSING" "$F4"
        fi
    done

    ## label|switch variable|tool
    echo -e "\n$(_section_header "Sections that need a tool")"
    local entry label var tool state
    for entry in "Weather|WEATHER_INFO|curl" \
                 "ZFS Pools|ZFS_INFO|zpool" \
                 "LVM|LVM_INFO|vgs" \
                 "Failed Services|FAILED_SERVICES_INFO|systemctl" \
                 "Docker|DOCKER_INFO|docker" \
                 "TLS Certificates|CERT_INFO|openssl" \
                 "Fail2Ban|FAIL2BAN_INFO|fail2ban-client"; do
        IFS='|' read -r label var tool <<< "$entry"
        state="${var}=\"${!var}\", ${tool}"
        if command -v "$tool" >/dev/null 2>&1; then
            case "${!var}" in
                0) _kv "$label" "${state} found, section is off" ;;
                *) _kv "$label" "${state} found, section is on" ;;
            esac
        else
            case "${!var}" in
                1)    _kv "$label" "${state} MISSING, section shows a notice" "$F4" ;;
                auto) _kv "$label" "${state} not installed, section is hidden" ;;
                *)    _kv "$label" "${state} not installed, section is off" ;;
            esac
        fi
    done

    echo -e "\n$(_section_header "Optional helpers")"
    for entry in "timeout|time limits for slow commands" \
                 "lscpu|CPU model on non-x86 systems" \
                 "ip|network addresses (fallbacks: ifconfig, hostname -I)" \
                 "getent|users from LDAP/NIS and reverse DNS" \
                 "sshd|effective SSH settings" \
                 "last|most recent logins" \
                 "timedatectl|time synchronization (or chronyc, ntpstat)" \
                 "md5sum|weather cache per city"; do
        IFS='|' read -r tool label <<< "$entry"
        if command -v "$tool" >/dev/null 2>&1 || [ -x "/usr/sbin/${tool}" ]; then
            _kv "$tool" "found: ${label}"
        else
            _kv "$tool" "not installed: ${label}"
        fi
    done
    echo -e "${C_RESET}"
}


#### Main dispatcher

## Configuration: built-in defaults, overridden by the configuration file,
## then validated. _CONFIG_STATE: loaded | none (no usable file)
_capture_defaults
if _load_config; then
    _CONFIG_STATE="loaded"
else
    _CONFIG_STATE="none"
    _import_legacy_env
fi
_sanitize_config
_apply_colors

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
        createenv || exit 1
    ;;
    -g|genconfig|--genconfig)
        genconfig || exit 1
    ;;
    -k|check|--check)
        show_check
    ;;
    -S|section|--section)
        shift
        show_section "$@" || exit 1
    ;;
    -j|json|--json)
        show_json || exit 1
    ;;
    compact|--compact)
        MOTD_MODE="compact"
        show_info
    ;;
    full|--full)
        MOTD_MODE="full"
        show_info
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
      -c | --config                 Set function, environment and service level
      -g | --genconfig              Create or refresh the configuration file
      -k | --check                  Show active sections and the tools they need
      -S | --section name [name..]  Show only the named sections
      -j | --json                   Print everything as JSON
           --compact                Show the summary and warnings only
           --full                   Show all sections
      -i | --install                Install dynmotd and its dependencies
      -U | --update                 Update binary only (no setup, safe for Ansible/cron)
      -u | --uninstall              Uninstall dynmotd, configuration and log
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
