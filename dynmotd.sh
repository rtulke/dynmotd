#!/bin/bash

# dynamic message of the day
# Robert Tulke, rt@debian.sh



## version
VERSION="dynmotd v1.9"

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
USER_INFO="1"               # show some user infomration
ENVIRONMENT_INFO="1"        # show environement information
MAINTENANCE_INFO="1"        # show maintenance infomration
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




## don't start as non-root
if [ $(whoami) != root ]; then
    cat /etc/motd
    exit 0
fi



#### Configuration Part

## create .maintenance file if not exist
function createmaintenance {

    if [ ! -f $MAINLOG ]; then
        DYNMOTDDIR=$(dirname $MAINLOG)
        mkdir -p $DYNMOTDDIR
        touch $MAINLOG
        chmod 600 $MAINLOG
        echo "new log file created $MAINLOG"
        echo
    fi
}


## create .environment file if not exist
function createenv {

echo -e "
${F2}============[ ${F1}Maintenance Setup${F2} ]==============================================
${F1}"
        echo "We want to assign a function name for $(hostname --fqdn)"
        echo
        echo -n "System Function, like Webserver, Mailserver e.g. [${1}]: "
        read SYSFUNCTION
    	echo -n "System Environment, like DEV|TST|INT|PRD [${2}]: "
    	read SYSENV
        echo -n "Service Level Agreement, like SLA1|SLA2|SLA3|None: [${3}] "
        read SYSSLA
        rm -rf $ENVFILE
        mkdir -p $(dirname $ENVFILE)
        touch $ENVFILE
        chmod 600 $ENVFILE
       	echo "SYSENV=\"$SYSENV\"" >> $ENVFILE
       	echo "SYSFUNCTION=\"$SYSFUNCTION\"" >> $ENVFILE
        echo "SYSSLA=\"$SYSSLA\"" >> $ENVFILE
}


#### Parameter Part

## addlog
function addlog () {

    if [ ! -f "$MAINLOG" ]; then
        echo "maintenance logfile not found: $MAINLOG try to create a new one..."
        createmaintenance
    fi

    if [ -z "$1" ]; then
        echo "Usage:"
        echo
        echo "  ./$(basename $0) -a \"new guest account added\" "
        echo
        exit 1
    fi

    mydate=$(date +"%b %d %H:%M:%S")
    echo $mydate $1 >> $MAINLOG
    echo "log entry added..."
}


## rmlog
function rmlog () {

        if [ -z "$1" ]; then
            echo "Usage: "
            echo
            echo "  ./$(basename $0) -d [line-number] "
            echo
            exit 1
        fi

        re='^[0-9]+$'
        if ! [[ $1 =~ $re ]] ; then
            echo "$1 : not a number"
            exit 1
        fi

        ## remove specific line
        sed -i "$1"'d' $MAINLOG
        RC=$?
        if [ $RC = "0" ]; then
            echo "line $1 successfully deleted..."
        else
            echo "something went wrong"
            exit 1

        fi
}


## listlog
function listlog () {

    if [ ! -f "$MAINLOG" ]; then
        echo "Maintenance Logfile not found: $MAINLOG"
        createmaintenance
    fi

    COUNT=1
    while read line; do
        NAME=$line;
        echo -e "${F2}$COUNT ${F1}$NAME${F2}"
        COUNT=$((COUNT+1))
    done < $MAINLOG
}

#### install itself
function install () {


    # if dynmotd does not exist then install it
    if [ ! -f ${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME} ]; then

        echo -n "Install dynmotd... "
        cat $0 > ${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}
        chmod ugo+rwx ${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}
        echo "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}" > $DYNMOTD_PROFILE

        ## install geopiplookup
        #if [ -f /etc/debian_version ]; then
        #
        #    apt upgrade -y -qq
        #    apt install geoip-bin geoip-database geoipupdate -y -qq /dev/null 2>&1
        #    if [[ ! $? -eq 0 ]]; then
        #        echo -e "${F1}Something went wrong${F2}"
        #    fi
        #fi

        echo "done."
    else
        echo -n "It seems like dynmotd is already installed, should I overwrite it? [Y|n]: "
        read OPT

        if [[ "Y" == "$OPT" ]]; then
            echo -n "Install dynmotd... "
            cat $0 > ${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}
            chmod ugo+rwx ${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}
            echo "${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME}" > $DYNMOTD_PROFILE
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
    for rmfile in $DYNMOTD_PROFILE ${MAINLOG} ${ENVFILE} ${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME} ; do
        
        if [ -f "$rmfile" ]; then
            echo $rmfile
        fi
    done

    echo
    echo -n "Please confirm with [Y|n]: "
    read OPT 
    echo

    if [[ "Y" == "$OPT" ]]; then

        for rmfile in $DYNMOTD_PROFILE ${MAINLOG} ${ENVFILE} ${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME} ; do
            rm -rf $rmfile
            rc=$?
            if [ ! -z "$rc" ]; then
                echo "$rmfile successfully removed"
            else
                echo "Error: $rmfile cannot removed!"
                echo "exit $rc"
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
        HOSTNAME=$(hostname --fqdn)

        ## get my main ip
        IP=$(host $HOSTNAME |grep "has address" |head -n1 |awk {'print $4'})

        ## get current kernel version
        UNAME=$(uname -r)

        ## get runnig sles distribution name
        DISTRIBUTION=$(lsb_release -s -d)

        ## get hardware platform
        PLATFORM=$(uname -m)

        ## get system uptime
        UPTIME=$(uptime |cut -c2- |cut -d, -f1)

        ## get amount of cpu processors
        CPUS=$(cat /proc/cpuinfo|grep processor|wc -l)

        ## get system cpu model
        CPUMODEL=$(cat /proc/cpuinfo |grep -E 'model name' |uniq |awk -F ': ' {'print $2'})

        ## get current free memory
        MEMFREE=$(echo $(cat /proc/meminfo |grep -E MemFree |awk {'print $2'})/1024 |bc)

        ## get maxium usable memory
        MEMMAX=$(echo $(cat /proc/meminfo |grep -E MemTotal |awk {'print $2'})/1024 |bc)

        ## get current free swap space
        SWAPFREE=$(echo $(cat /proc/meminfo |grep -E SwapFree |awk {'print $2'})/1024 |bc)

        ## get maxium usable swap space
        SWAPMAX=$(echo $(cat /proc/meminfo |grep -E SwapTotal |awk {'print $2'})/1024 |bc)

        ## get current procs
        PROCCOUNT=$(ps -Afl |grep -E -v 'ps|wc' |wc -l)

        ## get maxium usable procs
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


## Storage Information only for APT based distributionss
function show_update_info () {

    if [ ! -f /usr/bin/apt-get ]; then
        exit 1
    fi

    if [ -f /var/run/reboot-required ]; then
        REBOOT_REQUIRED=$(echo "Yes")
        REBOOT_PACKAGES=$(cat /var/run/reboot-required.pkgs)
    else
        REBOOT_REQUIRED=$(echo "No")
        REBOOT_PACKAGES=$(echo "0")
    fi

    if [ "$UPDATE_INFO" = "1" ]; then

        ## get outdated updates
        UPDATES=$(/usr/bin/apt-get -s dist-upgrade |grep -E  "upgraded" |grep -E "newly installed" |awk {'print $1'})

## display storage information
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

        ## get current storage information, how many space a left :)
        STORAGE=$(df -hT |sort -r -k 6 -i |sed -e 's/^File.*$/\x1b[0;37m&\x1b[1;32m/' |sed -e 's/^Datei.*$/\x1b[0;37m&\x1b[1;32m/' |grep -E -v docker )

## display storage information
echo -e "
${F2}============[ ${F1}Storage Info${F2} ]===================================================
${F3}${STORAGE}${F1}"

    fi
}


## User Informations
function show_user_info () {

    if [ "$USER_INFO" = "1" ]; then

        ## get my username
        WHOIAM=$(whoami)

        ## get my own user groups
        GROUPZ=$(groups)

        ## get my user id
        ID=$(id)

        ## how many users are logged in
        SESSIONS=$(who |wc -l)

        ## get a list of all logged in users
        LOGGEDIN=$(echo $(who |awk {'print $1" " $5'} |awk -F '[()]' '{ print $1 $2 '}  |uniq -c |awk {'print "(" $1 ") "$2" " $3","'} ) |sed 's/,$//' |sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

        ## how many system users are there, only check uid <1000 and has a login shell
        SYSTEMUSERCOUNT=$(cat /etc/passwd |grep -E '\:x\:10[0-9][0-9]' |grep '\:\/bin\/bash' |wc -l)

        ## who is a system user, only check uid <1000 and has a login shell
        SYSTEMUSER=$(cat /etc/passwd |grep -E '\:x\:10[0-9][0-9]' |grep -E '\:\/bin\/bash|\:\/bin/sh' |awk '{if ($0) print}' |awk -F ':' {'print $1'} |awk -vq=" " 'BEGIN{printf""}{printf(NR>1?",":"")q$0q}END{print""}' |cut -c2- |sed 's/ ,/,/g' |sed '1,$s/\([^,]*,[^,]*,[^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

        ## how many ssh super user (root) are there
        SUPERUSERCOUNT=$(cat /root/.ssh/authorized_keys |grep -E '^ssh-' |wc -l)

        ## who is super user (ignore root@)
        #SUPERUSER=$(echo $(for user in $(cat /root/.ssh/authorized_keys |grep -E '^ssh-' |awk '{print $NF}'); do echo -n "${user}, "; done) |sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

        SUPERUSER=$(echo $(readarray -t rows < /root/.ssh/authorized_keys; for row in "${rows[@]}"; do row_array=(${row}); third=${row_array[2]}; if [ -z $third ]; then echo -n "- Unknown -, "; else echo -n "${third}, "; fi; done) |sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g' |sed 's/,$//' )

#        SUPERUSER=$(cat /root/.ssh/authorized_keys |grep -E '^ssh-' |awk '{print $NF}' |awk -vq=" " 'BEGIN{printf""}{printf(NR>1?",":"")q$0q}END{print""}' |cut -c2- |sed 's/ ,/,/g' |sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g' )

        ## count sshkeys
        KEYUSERCOUNT=$(for i in $(cat /etc/passwd |grep -E '\:x\:10[0-9][0-9]' |awk -F ':' {'print $6'}) ; do cat $i/.ssh/authorized_keys  2> /dev/null |grep ^ssh- |awk '{print substr($0, index($0,$3)) }'; done |wc -l)

        ## print any authorized ssh-key-user of a existing system user
        KEYUSER=$(for i in $(cat /etc/passwd |grep -E '\:x\:10[0-9][0-9]' |awk -F ':' {'print $6'}) ; do cat $i/.ssh/authorized_keys  2> /dev/null |grep ^ssh- |awk '{print substr($0, index($0,$3)) }'; done |awk -vq=" " 'BEGIN {printf ""}{printf(NR>1?",":"")q$0q}END{print""}' |cut -c2- |sed 's/ , /, /g' |sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g'  )


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
        if [ ! -f $ENVFILE ]; then
            createenv ;
        fi

        ## include sys environment variables
        source $ENVFILE

        ## test environment.cfg variables, if any of them are empty or damaged
        if [ -z "${SYSFUNCTION}" ] || [ -z "${SYSENV}" ] || [ -z "${SYSSLA}" ]; then
            rm $ENVFILE
            createenv ;	# variables are exist but empty, create new
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

        ## get latest maintenance information
        MAINTENANCE=$(${DYNMOTD_INSTALL_PATH}/${DYNMOTD_FILENAME} --listlog |head -n${LIST_LOG_ENTRY})

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
${F2}=============================================================[ ${F1}$VERSION${F2} ]==
${F1}"

    fi
}


## Display Output
function show_info () {

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
fi


## paremeter
param="$2 $3"

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

esac
