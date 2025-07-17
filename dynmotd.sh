#!/bin/bash

# dynamic message of the day
# Robert Tulke, rt@debian.sh
# Improved version with performance and portability optimizations

## version
VERSION="dynmotd v1.11.0"

## configuration and logfile
MAINLOG="/root/.dynmotd/maintenance.log"
ENVFILE="/root/.dynmotd/environment.cfg"

## install path
DYNMOTD_INSTALL_PATH="/usr/local/bin"     # path where "dynmotd -i" is to be installed /without trailing slash
DYNMOTD_PROFILE="/etc/profile.d/motd.sh"  # file where dynmotd should be loaded
DYNMOTD_FILENAME="dynmotd"                # file name to be used for the installation

## enable system related information about your system
SYSTEM_INFO="1"             # show system information
STORAGE_INFO="1"            # show storage information
USER_INFO="1"               # show some user information
ENVIRONMENT_INFO="1"        # show environment information
MAINTENANCE_INFO="1"        # show maintenance information
UPDATE_INFO="1"             # show update information
VERSION_INFO="1"            # show the version banner

## how many log lines will be display in MAINTENANCE_INFO
LIST_LOG_ENTRY="2"          


## some colors
C_BLACK="\033[0;30m"        # Black
C_DGRAY="\033[1;30m"        # Dark Grey
C_GREY="\033[0;37m"         # Grey
C_WHITE="\033[1;37m"        # White
C_RED="\033[0;31m"          # Red
C_LRED="\033[1;31m"         # Light Red
C_BLUE="\033[0;34m"         # Blue
C_LBLUE="\033[1;34m"        # Light Blue
C_CYAN="\033[0;36m"         # Cyan
C_LCYAN="\033[1;36m"        # Light Cyan
C_PINK="\033[0;35m"         # Purple
C_LPINK="\033[1;35m"        # Light Purple
C_GREEN="\033[0;32m"        # Green
C_LGREEN="\033[1;32m"       # Light Green
C_BROWN="\033[0;33m"        # Brown/Orange
C_YELLOW="\033[1;33m"       # Yellow


#### color schemes

## DOT, day of the tentacle scheme
F1=${C_GREY}
F2=${C_PINK}
F3=${C_LGREEN}
F4=${C_RED}

## retro hacker
#F1=${C_GREEN}
#F2=${C_GREEN}
#F3=${C_GREEN}
#F4=${C_RED}

## retro alert
#F1=${C_RED}
#F2=${C_RED}
#F3=${C_RED}
#F4=${C_RED}


## Function to check dependencies
function check_dependencies() {
    local missing_deps=()
    for cmd in bc grep hostname sed awk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Missing dependencies found: ${missing_deps[*]}"
        echo "Please install the missing packages:"
        echo "Debian/Ubuntu: apt install coreutils bc procps hostname sed mawk grep bind9-host lsb-release"
        echo "CentOS/RHEL: yum install bc bind-utils redhat-lsb-core"
        return 1
    fi
    return 0
}

## don't start as non-root
if [[ "$USER" != "root" ]]; then
    cat /etc/motd 2>/dev/null || echo "No message of the day available"
    exit 0
fi



#### Configuration Part

## create .maintenance file if not exist
function createmaintenance {
    if [ ! -f "$MAINLOG" ]; then
        DYNMOTDDIR=$(dirname "$MAINLOG")
        mkdir -p "$DYNMOTDDIR"
        touch "$MAINLOG"
        chmod 600 "$MAINLOG"
        echo "New log file created: $MAINLOG"
        echo
    fi
}


## create .environment file if not exist
function createenv {
    echo -e "
${F2}============[ ${F1}Maintenance Setup${F2} ]==============================================
${F1}"
    echo "We want to assign a function name for $(hostname --fqdn 2>/dev/null || hostname)"
    echo
    echo -n "System Function, like Webserver, Mailserver e.g. [${1:-Unset}]: "
    read -r SYSFUNCTION
    echo -n "System Environment, like DEV|TST|INT|PRD [${2:-DEV}]: "
    read -r SYSENV
    echo -n "Service Level Agreement, like SLA1|SLA2|SLA3|None: [${3:-None}] "
    read -r SYSSLA
    
    # Set default values if empty
    SYSFUNCTION="${SYSFUNCTION:-Unset}"
    SYSENV="${SYSENV:-DEV}"
    SYSSLA="${SYSSLA:-None}"
    
    rm -rf "$ENVFILE"
    mkdir -p "$(dirname "$ENVFILE")"
    touch "$ENVFILE"
    chmod 600 "$ENVFILE"
    echo "SYSENV=\"$SYSENV\"" >> "$ENVFILE"
    echo "SYSFUNCTION=\"$SYSFUNCTION\"" >> "$ENVFILE"
    echo "SYSSLA=\"$SYSSLA\"" >> "$ENVFILE"
}


#### Parameter Part

## addlog
function addlog () {
    if [ ! -f "$MAINLOG" ]; then
        echo "Maintenance logfile not found: $MAINLOG trying to create a new one..."
        createmaintenance
    fi

    if [ -z "$1" ]; then
        echo "Usage:"
        echo
        echo "  ./$(basename "$0") -a \"new guest account added\" "
        echo
        exit 1
    fi

    mydate=$(date +"%b %d %H:%M:%S")
    #echo "$mydate" "$1" >> "$MAINLOG"
    printf '%s %s\n' "$mydate" "${1//[$'\n\r']/}" >> "$MAINLOG"

    echo "Log entry added..."
}


## rmlog
function rmlog () {
    if [ -z "$1" ]; then
        echo "Usage: "
        echo
        echo "  ./$(basename "$0") -d [line-number] "
        echo
        exit 1
    fi

    re='^[0-9]+$'
    if ! [[ $1 =~ $re ]] ; then
        echo "$1 : not a number"
        exit 1
    fi

    ## remove specific line
    sed -i "$1"'d' "$MAINLOG"
    RC=$?
    if [ $RC = "0" ]; then
        echo "Line $1 successfully deleted..."
    else
        echo "Something went wrong"
        exit 1
    fi
}


## listlog
function listlog () {
    if [ ! -f "$MAINLOG" ]; then
        echo "Maintenance logfile not found: $MAINLOG"
        createmaintenance
        return
    fi

    COUNT=1
    while read -r line; do
        NAME=$line;
        echo -e "${F2}$COUNT ${F1}$NAME${F2}"
        COUNT=$((COUNT+1))
    done < "$MAINLOG"
}

#### install itself
function install () {
    # Check dependencies before installation
    check_dependencies || {
        echo "Please install the missing dependencies and try again."
        return 1
    }

    # if dynmotd does not exist then install it
    if [ ! -f "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}" ]; then
        echo -n "Installing dynmotd... "
        cat "$0" > "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"
        chmod ugo+rx "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"
        echo "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}" > "$DYNMOTD_PROFILE"
        echo "done."
    else
        echo -n "It seems like dynmotd is already installed, should I overwrite it? [Y|n]: "
        read -r OPT

        if [[ "$OPT" == "Y" || "$OPT" == "y" || "$OPT" == "" ]]; then
            echo -n "Installing dynmotd... "
            cat "$0" > "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"
            chmod ugo+rx "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"
            echo "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}" > "$DYNMOTD_PROFILE"
            echo "done."
        else
            echo "Nothing to do..."
        fi
    fi
}

#### uninstall itself
function uninstall () {
    echo "Should the following files be deleted?"
    echo
    for rmfile in "$DYNMOTD_PROFILE" "${MAINLOG}" "${ENVFILE}" "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"; do
        if [ -f "$rmfile" ]; then
            echo "$rmfile"
        fi
    done

    echo
    echo -n "Please confirm with [Y|n]: "
    read -r OPT 
    echo

    if [[ "$OPT" == "Y" || "$OPT" == "y" || "$OPT" == "" ]]; then
        for rmfile in "$DYNMOTD_PROFILE" "${MAINLOG}" "${ENVFILE}" "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}"; do
            if [ -f "$rmfile" ]; then
                rm -f "$rmfile"
                rc=$?
                if [ "$rc" -eq 0 ]; then
                    echo "$rmfile successfully removed"
                else
                    echo "Error: $rmfile cannot be removed!"
                    echo "exit $rc"
                fi
            fi
        done
    else
        echo "Nothing to do..."
    fi
}



#### Output Part

## System Info
function show_system_info () {
    if [ "$SYSTEM_INFO" = "1" ]; then
        ## get my fqdn hostname.domain.name.tld
        HOSTNAME=$(hostname --fqdn 2>/dev/null || hostname)

        ## get my main ip - improved with fallback
        IP=$(host "$HOSTNAME" 2>/dev/null | grep "has address" | head -n1 | awk '{print $4}')
        if [ -z "$IP" ]; then
            IP=$(hostname -I 2>/dev/null | awk '{print $1}')
            [ -z "$IP" ] && IP="Unknown"
        fi

        ## get current kernel version
        UNAME=$(uname -r)

        ## get running distribution name with fallback options
        if command -v lsb_release >/dev/null 2>&1; then
            DISTRIBUTION=$(lsb_release -s -d)
        else
            if [ -f /etc/os-release ]; then
                DISTRIBUTION=$(grep -m1 PRETTY_NAME /etc/os-release | cut -d '=' -f 2 | tr -d '"')
            elif [ -f /etc/redhat-release ]; then
                DISTRIBUTION=$(cat /etc/redhat-release)
            else
                DISTRIBUTION="Unknown Distribution"
            fi
        fi

        ## get hardware platform
        PLATFORM=$(uname -m)

        ## get system uptime
        UPTIME=$(uptime | cut -c2- | cut -d, -f1)

        ## get amount of cpu processors
        CPUS=$(grep -c processor /proc/cpuinfo)

        ## get system cpu model
        CPUMODEL=$(grep -m1 -E 'model name' /proc/cpuinfo | awk -F ': ' '{print $2}')

        ## get memory info - read once for all memory information
        MEM_INFO=$(awk '
            /^MemFree:/ {MEMFREE=$2/1024}
            /^MemTotal:/ {MEMMAX=$2/1024}
            /^SwapFree:/ {SWAPFREE=$2/1024}
            /^SwapTotal:/ {SWAPMAX=$2/1024}
            END {printf "%.0f %.0f %.0f %.0f", MEMFREE, MEMMAX, SWAPFREE, SWAPMAX}
        ' /proc/meminfo)

        # split values into own variables
        read -r MEMFREE MEMMAX SWAPFREE SWAPMAX <<< "$MEM_INFO"

        
        #MEM_INFO=$(cat /proc/meminfo)
        #MEMFREE=$(echo "$(echo "$MEM_INFO" | grep -E '^MemFree:' | awk '{print $2}')/1024" | bc)
        #MEMMAX=$(echo "$(echo "$MEM_INFO" | grep -E '^MemTotal:' | awk '{print $2}')/1024" | bc)
        #SWAPFREE=$(echo "$(echo "$MEM_INFO" | grep -E '^SwapFree:' | awk '{print $2}')/1024" | bc)
        #SWAPMAX=$(echo "$(echo "$MEM_INFO" | grep -E '^SwapTotal:' | awk '{print $2}')/1024" | bc)

        ## get current procs
        #PROCCOUNT=$(ps -Afl | grep -E -v 'ps|wc' | wc -l)
        PROCCOUNT=$(ps --no-headers -eo pid | wc -l)

        ## get maximum usable procs
        PROCMAX=$(ulimit -u)

        ## display system information
        echo -e "
${F2}============[ ${F1}System Info${F2} ]====================================================
${F1}        Hostname ${F2}= ${F3}$HOSTNAME
${F1}         Address ${F2}= ${F3}$IP
${F1}          Kernel ${F2}= ${F3}$UNAME
${F1}    Distribution ${F2}= ${F3}$DISTRIBUTION ${PLATFORM}
${F1}          Uptime ${F2}= ${F3}$UPTIME
${F1}             CPU ${F2}= ${F3}$CPUS x $CPUMODEL
${F1}          Memory ${F2}= ${F3}$MEMFREE MB Free of $MEMMAX MB Total
${F1}     Swap Memory ${F2}= ${F3}$SWAPFREE MB Free of $SWAPMAX MB Total
${F1}       Processes ${F2}= ${F3}$PROCCOUNT of $PROCMAX MAX${F1}"
    fi
}


## Update Information with support for different package managers
function show_update_info () {
    if [ "$UPDATE_INFO" = "1" ]; then
        UPDATES="Unknown"
        REBOOT_REQUIRED="Unknown"
        REBOOT_PACKAGES="Unknown"

        # Check for different package managers
        if command -v apt-get >/dev/null 2>&1; then
            UPDATES=$(apt-get -s dist-upgrade 2>/dev/null | grep -E "upgraded" | grep -E "newly installed" | awk '{print $1}')
            if [ -f /var/run/reboot-required ]; then
                REBOOT_REQUIRED="Yes"
                # Format REBOOT_PACKAGES with line breaks at >80 characters and 20 characters indentation
                if [ -f /var/run/reboot-required.pkgs ]; then
                    raw_packages=$(cat /var/run/reboot-required.pkgs 2>/dev/null || echo "0")
                    # Format the output: max. 80 characters per line, then break with 20 spaces indentation
                    formatted_packages=""
                    line_length=0
                    
                    for pkg in $raw_packages; do
                        pkg_length=${#pkg}
                        
                        if [ $line_length -eq 0 ]; then
                            # First line or after line break
                            formatted_packages+="$pkg"
                            line_length=$pkg_length
                        elif [ $((line_length + pkg_length + 1)) -le 80 ]; then
                            # Enough space in current line
                            formatted_packages+=" $pkg"
                            line_length=$((line_length + pkg_length + 1))
                        else
                            # Line break at >80 characters
                            formatted_packages+="\n                    $pkg"
                            line_length=$((pkg_length + 20))
                        fi
                    done
                    
                    REBOOT_PACKAGES="$formatted_packages"
                else
                    REBOOT_PACKAGES="0"
                fi
            else
                REBOOT_REQUIRED="No"
                REBOOT_PACKAGES="0"
            fi
        elif command -v dnf >/dev/null 2>&1; then
            UPDATES=$(dnf check-update --quiet 2>/dev/null | grep -v "^$" | wc -l)
            REBOOT_REQUIRED="Unknown"
            REBOOT_PACKAGES="N/A"
        elif command -v yum >/dev/null 2>&1; then
            UPDATES=$(yum check-update --quiet 2>/dev/null | grep -v "^$" | wc -l)
            REBOOT_REQUIRED="Unknown"
            REBOOT_PACKAGES="N/A"
        elif command -v zypper >/dev/null 2>&1; then
            UPDATES=$(zypper list-updates 2>/dev/null | grep -v "^$" | wc -l)
            REBOOT_REQUIRED="Unknown"
            REBOOT_PACKAGES="N/A"
        fi

        # Display update information
        echo -e "
${F2}============[ ${F1}Update Info${F2} ]====================================================
${F1}Available Updates ${F2}= ${F3}${UPDATES}${F1}
${F1}  Reboot Required ${F2}= ${F3}${REBOOT_REQUIRED}${F1}
${F1}  Reboot Packages ${F2}= ${F3}${REBOOT_PACKAGES}${F1}"
    fi
}

## Storage Informations
function show_storage_info () {
    if [ "$STORAGE_INFO" = "1" ]; then
        ## get current storage information, how much space is left
        STORAGE=$(df -hT | awk '!/docker/ {if ($0 ~ /^File|^Datei/) print "\033[0;37m" $0 "\033[1;32m"; else if (NR > 1) {print}}' | awk '{line[NR]=$0; size[NR]=$6} END {for (i=NR; i>=1; i--) for (j=1; j<i; j++) if (size[j] < size[j+1]) {t=line[j]; line[j]=line[j+1]; line[j+1]=t; t=size[j]; size[j]=size[j+1]; size[j+1]=t} for (i=1; i<=NR; i++) print line[i]}')


        ## display storage information
        echo -e "
${F2}============[ ${F1}Storage Info${F2} ]===================================================
${F3}${STORAGE}${F1}"
    fi
}


## User Informations - with optimized SSH-Key-Handling
function show_user_info () {
    if [ "$USER_INFO" = "1" ]; then
        ## get my username
        WHOIAM=$USER

        ## get my user id
        ID=$(id)

        ## how many users are logged in
        SESSIONS=$(who | wc -l)

        ## get a list of all logged in users - optimized
        LOGGEDIN=$(who | awk '{print $1, $5}' | awk -F '[()]' '{print $1, $2}' | uniq -c | awk '{printf "(%s) %s %s,", $1, $2, $3}' | sed 's/,$//' | sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

        ## System Users with arrays
        mapfile -t sys_users < <(grep -E ':x:1[0-9]{3}:' /etc/passwd | grep -E ':(bin/bash|bin/sh)$' | awk -F ':' '{print $1}')

        SYSTEMUSERCOUNT=${#sys_users[@]}
        SYSTEMUSER=$(IFS=", "; echo "${sys_users[*]}" | sed '1,$s/\([^,]*,[^,]*,[^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

        ## Optimized SSH-Key display - Only show comments behind SSH Keys
        if [ -f "/root/.ssh/authorized_keys" ]; then
            # Array for SSH key users
            mapfile -t ssh_root_users < <(while read -r line; do
                if [[ "$line" =~ ^ssh- ]]; then
                    # Check if the key has more than two fields (ssh-rsa AAAA... [comment])
                    # Count fields in string
                    field_count=$(echo "$line" | wc -w)
                    
                    if [ "$field_count" -gt 2 ]; then
                        # If there are more than 2 fields, take the last one as comment
                        comment=$(echo "$line" | awk '{print $NF}')
                        
                        # Check if the last part is actually a comment and not part of the key
                        if [[ "$comment" == ssh-* || "$comment" == AAAA* ]]; then
                            echo "- Unknown -"
                        else
                            echo "$comment"
                        fi
                    else
                        # If only 2 fields (ssh-rsa and the key), then no comment present
                        echo "- Unknown -"
                    fi
                fi
            done < /root/.ssh/authorized_keys)
            
            SUPERUSERCOUNT=${#ssh_root_users[@]}
            SUPERUSER=$(IFS=", "; echo "${ssh_root_users[*]}" | sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')
        else
            SUPERUSERCOUNT=0
            SUPERUSER="None"
        fi

        ## SSH-Keys of regular users - improved comment detection
        KEYUSERCOUNT=0
        keyusers=()
        while IFS=: read -r _ _ _ _ _ homedir _; do
            if [ -d "$homedir/.ssh" ] && [ -f "$homedir/.ssh/authorized_keys" ]; then
                while read -r line; do
                    if [[ "$line" =~ ^ssh- ]]; then
                        # Check if the key has more than two fields
                        field_count=$(echo "$line" | wc -w)
                        
                        if [ "$field_count" -gt 2 ]; then
                            # If there are more than 2 fields, take the last one as comment
                            comment=$(echo "$line" | awk '{print $NF}')
                            
                            # Check if the last part is actually a comment and not part of the key
                            if [[ "$comment" == ssh-* || "$comment" == AAAA* ]]; then
                                keyusers+=("- Unknown -")
                            else
                                keyusers+=("$comment")
                            fi
                        else
                            # If only 2 fields (ssh-rsa and the key), then no comment present
                            keyusers+=("- Unknown -")
                        fi
                        ((KEYUSERCOUNT++))
                    fi
                done < "$homedir/.ssh/authorized_keys"
            fi
        done < <(grep -E ':x:1[0-9]{3}:' /etc/passwd)
        
        KEYUSER=$(IFS=", "; echo "${keyusers[*]}" | sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

        ## show user information
        echo -e "
${F2}============[ ${F1}User Data${F2} ]======================================================
${F1}    Your Username ${F2}= ${F3}$WHOIAM
${F1}  Your Privileges ${F2}= ${F3}$ID
${F1} Current Sessions ${F2}= ${F3}[$SESSIONS] $LOGGEDIN
${F1}      SystemUsers ${F2}= ${F3}[$SYSTEMUSERCOUNT] $SYSTEMUSER
${F1}  SshKeyRootUsers ${F2}= ${F3}[$SUPERUSERCOUNT] $SUPERUSER
${F1}      SshKeyUsers ${F2}= ${F3}[$KEYUSERCOUNT] $KEYUSER${F1}"
    fi
}


## Environment Informations
function show_environment_info () {
    if [ "$ENVIRONMENT_INFO" = "1" ]; then
        ## environment file check
        if [ ! -f "$ENVFILE" ]; then
            createenv
            return
        fi

        ## include sys environment variables safer
        if [ -f "$ENVFILE" ]; then
            source "$ENVFILE"
        else
            echo "Environment file missing: $ENVFILE"
            return
        fi

        ## test environment.cfg variables, if any of them are empty or damaged
        if [ -z "${SYSFUNCTION}" ] || [ -z "${SYSENV}" ] || [ -z "${SYSSLA}" ]; then
            rm -f "$ENVFILE"
            createenv  # variables exist but are empty, create new
            return
        fi

        ## display environment information
        echo -e "
${F2}============[ ${F1}Environment Data${F2} ]===============================================
${F1}         Function ${F2}= ${F3}$SYSFUNCTION
${F1}      Environment ${F2}= ${F3}$SYSENV
${F1}    Service Level ${F2}= ${F3}$SYSSLA${F1}"
    fi
}


## Maintenance Information
function show_maintenance_info () {
    if [ "$MAINTENANCE_INFO" = "1" ]; then
        if [ ! -f "$MAINLOG" ]; then
            echo -e "
${F2}============[ ${F1}Maintenance Information${F2} ]========================================
${F4}No maintenance log found at $MAINLOG${F1}"
            return
        fi

        ## get latest maintenance information
        MAINTENANCE=$(listlog | head -n"${LIST_LOG_ENTRY}")

        ## display maintenance information
        echo -e "
${F2}============[ ${F1}Maintenance Information${F2} ]========================================
${F4}$MAINTENANCE${F1}"
    fi
}


## Version Information
function show_version_info () {
    if [ "$VERSION_INFO" = "1" ]; then
        ## display version information
        echo -e "
${F2}==========================================================[ ${F1}$VERSION${F2} ]==
${F1}"
    fi
}


## Display Output
function show_info () {
    # Check dependencies before display
    check_dependencies || {
        echo "Please install the missing dependencies for full functionality."
    }

    show_system_info
    show_storage_info
    show_user_info
    show_update_info
    show_environment_info
    show_maintenance_info
    show_version_info
}


#### Main Part

## if no parameter is passed then start show_info
if [ -z "$1" ]; then
    show_info
    exit 0
fi


## Parameter processing
case "$1" in
    addlog|-a|--addlog)
        addlog "$2"
    ;;

    rmlog|-d|--rmlog)
        rmlog "$2"
    ;;

    log|--log|-l|--listlog|listlog)
        listlog
    ;;

    config|-c|--config|setup|-s|--set)
        createenv
    ;;

    install|-i|--install)
        install
    ;;

    uninstall|-u|--uninstall)
        uninstall
    ;;

    help|-h|--help|?)
    echo -e "
        Usage: $0 [-c|-a|-d|--install|--help] <params>

        e.g. $0 -a \"start web migration\"

        Parameter:

           -a | addlog    | --addlog \"...\"               add new log entry
           -d | rmlog     | --rmlog [loglinenumber]      delete specific log entry
           -l | log       | --log                        list log entries
           -c | config    | --config                     restart setup
           -i | install   | --install                    install dynmotd
           -u | uninstall | --uninstall                  uninstall dynmotd
     "
    ;;

    *)
        echo "Unknown parameter: $1"
        echo "Use $0 --help for usage information"
        exit 1
    ;;
esac

exit 0
