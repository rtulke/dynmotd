#!/bin/bash

# Dynamic Motd
# Robert Tulke, rt@debian.sh

## don't start as root
if [ $(whoami) != root ]; then
    cat /etc/motd
    exit 0
fi

## version
version="dynmotd v1.1"
fqdn=$(hostname --fqdn)

##some colors
C_RED="\033[0;31m"
C_BLUE="\033[0;34m"
C_BLACK="\033[0;30m"
C_CYAN="\033[0;36m"
C_PINK="\033[0;35m"
C_GREY="\033[0;37m"
C_LGREEN="\033[1;32m"


## color schemes
# DOT, day of the tentacle scheme
F1=${C_GREY}
F2=${C_PINK}
F3=${C_LGREEN}
F4=${C_RED}


## create .maintenance file if not exist
if [ ! -f /root/.maintenance ]; then
    touch /root/.maintenance
fi

## investigate linux distribution

## create .environment file if not exist
function createenv {

    if [ ! -f /root/.environment ]; then
    	echo "First login... We want to assign a function name for $fqdn,"
        echo "like: Backup Server|File Server|Gateway|Proxy|..."
    	echo
     	echo -n "System Function: "
    	read SYSFUNCTION
    	echo -n "System Environment, like PRD|TST|ITG: "
    	read SYSENV
      echo -n "Service Level Agreement, like SLA1|SLA2|SLA3: "
      read SYSSLA

      touch /root/.environment
    	echo "SYSENV=\"$SYSENV\"" >> /root/.environment
    	echo "SYSFUNCTION=\"$SYSFUNCTION\"" >> /root/.environment
      echo "SYSSLA=\"$SYSSLA\"" >> /root/.environment
    fi
}

## environment check
if [ ! -f /root/.environment ]; then
    createenv ;	# if not exist then create
fi

## include sys environment variables
source /root/.environment

## test sys .environment variables, if any of them are empty or currupt
if [ -z "${SYSFUNCTION}" ] || [ -z "${SYSENV}" ] || [ -z "${SYSSLA}" ]; then
    rm /root/.environment
    createenv ;	# variables are exist but empty, create new
fi

## get a list of all logged in users
#LOGGEDIN=$( echo $( for i in $( who |awk -F '[()]' '{ print $2 '} |sort -n ) ; do echo $i; done |uniq -c |awk {'print "(" $1 ") "$2","'} ) |sed 's/,$//' |sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g' )
LOGGEDIN=$(echo $(who |awk {'print $1" " $5'} |awk -F '[()]' '{ print $1 $2 '}  |uniq -c |awk {'print "(" $1 ") "$2" " $3","'} ) |sed 's/,$//' |sed '1,$s/\([^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')


## get my terminal
MYTTY=$(tty |sed 's/\/dev\///')

## get my hostname
MYHOST=$(who |egrep $MYTTY |awk -F '[()]' {'print $2'})

## extract my apn from fqdn
APN=$(echo $MYHOST |awk -F '.' '{print $1}')

## get current procs
PROCCOUNT=$(ps -Afl |egrep -v 'ps|wc' |wc -l)

## get maxium usable procs
PROCMAX=$(ulimit -u)

## get my own user groups
GROUPZ=$(groups)

## how many ssh super user (root) are there
SUPERUSERCOUNT=$(cat /root/.ssh/authorized_keys |egrep '^ssh-' |wc -l)

## how many system users are there, only check uid <1000 and has a login shell
SYSTEMUSERCOUNT=$(cat /etc/passwd |egrep '\:x\:10[0-9][0-9]' |grep '\:\/bin\/bash' |wc -l)

## who is a system user, only check uid <1000 and has a login shell
SYSTEMUSER=$(cat /etc/passwd |egrep '\:x\:10[0-9][0-9]' |egrep '\:\/bin\/bash|\:\/bin/sh' |awk '{if ($0) print}' |awk -F ':' {'print $1'} |awk -vq=" " 'BEGIN{printf""}{printf(NR>1?",":"")q$0q}END{print""}' |cut -c2- |sed 's/ ,/,/g' |sed '1,$s/\([^,]*,[^,]*,[^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g')

## print any authorized ssh-key-user of a existing system user
KEYUSER=$(for i in $(cat /etc/passwd |egrep '\:x\:10[0-9][0-9]' |awk -F ':' {'print $6'}) ; do cat $i/.ssh/authorized_keys  2> /dev/null |grep ^ssh- |awk '{print substr($0, index($0,$3)) }'; done |awk -vq=" " 'BEGIN {printf ""}{printf(NR>1?",":"")q$0q}END{print""}' |cut -c2- |sed 's/ , /, /g' |sed '1,$s/\([^,]*,[^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g'  )

## who is super user (ignore root@)
#SUPERUSER=$(cat /root/.ssh/authorized_keys |egrep '^ssh-' |awk '{print $NF}' |awk -vq=" " 'BEGIN{printf""}{printf(NR>1?",":"")q$0q}END{print""}' |cut -c2- |sed 's/ ,/,/g' |sed '1,$s/\([^,]*,[^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g' |sed 's/\b\(.\)/\u\1/g')
#SUPERUSER=$(cat /root/.ssh/authorized_keys |egrep '^ssh-' |awk '{print $NF}' |awk -vq=" " 'BEGIN{printf""}{printf(NR>1?",":"")q$0q}END{print""}' |cut -c2- |sed 's/ ,/,/g' |sed '1,$s/\([^,]*,[^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g' |sed 's/\b\(.\)/\u\1/g')
SUPERUSER=$(cat /root/.ssh/authorized_keys |egrep '^ssh-' |awk '{print $NF}' |awk -vq=" " 'BEGIN{printf""}{printf(NR>1?",":"")q$0q}END{print""}' |cut -c2- |sed 's/ ,/,/g' |sed '1,$s/\([^,]*,[^,]*,[^,]*,[^,]*,\)/\1\n\\033[1;32m\t          /g' )

## count sshkeys
KEYUSERCOUNT=$(for i in $(cat /etc/passwd |egrep '\:x\:10[0-9][0-9]' |awk -F ':' {'print $6'}) ; do cat $i/.ssh/authorized_keys  2> /dev/null |grep ^ssh- |awk '{print substr($0, index($0,$3)) }'; done |wc -l)

## get system uptime
UPTIME=$(uptime |cut -c2- |cut -d, -f1)

## get maxium usable memory
MEMMAX=$(echo $(cat /proc/meminfo |egrep MemTotal |awk {'print $2'})/1024 |bc)

## get current free memory
MEMFREE=$(echo $(cat /proc/meminfo |egrep MemFree |awk {'print $2'})/1024 |bc)

## get maxium usable swap space
SWAPMAX=$(echo $(cat /proc/meminfo |egrep SwapTotal |awk {'print $2'})/1024 |bc)

## get current free swap space
SWAPFREE=$(echo $(cat /proc/meminfo |egrep SwapFree |awk {'print $2'})/1024 |bc)

## get current kernel version
UNAME=$(uname -r)

## get my fqdn hostname.domain.name.tld
HOSTNAME=$fqdn

## get my main ip
IP=$(host $HOSTNAME |awk {'print $4'})

## get system cpu model
CPUMODEL=$(cat /proc/cpuinfo |egrep 'model name' |uniq |awk -F ': ' {'print $2'})

## how many cpu i have
CPUS=$(cat /proc/cpuinfo|grep processor|wc -l)

## how many user logged in at the moment
SESSIONS=$(who |wc -l)

## get my username
WHOIAM=$(whoami)

## get my user id
ID=$(id)

## get runnig distribution name
if [ -f /etc/SuSE-release ]; then
	VERSION=$(cat /etc/SuSE-release |egrep SUSE -m 1)
	## get the curernt installed patch level
	PATCHLEVEL=$(cat /etc/SuSE-release |egrep PATCHLEVEL |awk -F '= ' {'print $2'})
	DISTRIBUTION="$VERSION SP$PATCHLEVEL"
fi

## get runnig distribution name
if [ -f /etc/debian_version ]; then
	PATCHLEVEL=$(cat /etc/debian_version)
	DISTRIBUTION="Debian GNU/Linux $PATCHLEVEL"
fi


## get latest maintenance information
#MAINTENANCE1=$(cat /root/.maintenance)
function getmaintenance {
COUNT=1
while read line; do
    NAME=$line;
    echo "$COUNT $NAME"
    COUNT=$((COUNT+1))
done < /root/.maintenance
}
MAINTENANCE=$(getmaintenance)

## get current storage information, how many space a left :)
STORAGE=$(df -hT |sort -r -k 6 -i |sed -e 's/^File.*$/\x1b[0;37m&\x1b[1;32m/' |sed -e 's/^Datei.*$/\x1b[0;37m&\x1b[1;32m/' |egrep -v docker )

## Main Menu
echo -e "
${F2}============[ ${F1}System Data${F2} ]====================================================
${F1}     Function ${F2}= ${F3}$SYSFUNCTION
${F1}     Hostname ${F2}= ${F3}$HOSTNAME
${F1}      Address ${F2}= ${F3}$IP
${F1}       Kernel ${F2}= ${F3}$UNAME
${F1} Distribution ${F2}= ${F3}$DISTRIBUTION
${F1}       Uptime ${F2}= ${F3}$UPTIME
${F1}          CPU ${F2}= ${F3}$CPUS x $CPUMODEL
${F1}       Memory ${F2}= ${F3}$MEMFREE MB Free of $MEMMAX MB Total
${F1}  Swap Memory ${F2}= ${F3}$SWAPFREE MB Free of $SWAPMAX MB Total
${F1}    Processes ${F2}= ${F3}$PROCCOUNT of $PROCMAX MAX
${F2}============[ ${F1}Storage Data${F2} ]===================================================
${F3}${STORAGE}
${F2}============[ ${F1}User Data${F2} ]======================================================
${F1}     Username ${F2}= ${F3}$WHOIAM, ($APN)
${F1}   Privileges ${F2}= ${F3}$ID
${F1}     Sessions ${F2}= ${F3}[$SESSIONS] $LOGGEDIN
${F1}  SystemUsers ${F2}= ${F3}[$SYSTEMUSERCOUNT] $SYSTEMUSER
${F1}   SuperUsers ${F2}= ${F3}[$SUPERUSERCOUNT] $SUPERUSER
${F1}  SshKeyUsers ${F2}= ${F3}[$KEYUSERCOUNT] $KEYUSER
${F2}============[ ${F1}Environment Data${F2} ]===============================================
${F1}     Function ${F2}= ${F3}$SYSFUNCTION
${F1}  Environment ${F2}= ${F3}$SYSENV
${F1}Service Level ${F2}= ${F3}$SYSSLA
${F2}============[ ${F1}Maintenance Information${F2} ]========================================
${F4}$(getmaintenance)
${F2}=============================================================[ ${F1}$version${F2} ]==
${F1}
"
