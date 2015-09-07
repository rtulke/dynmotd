#!/bin/bash
MAINLOG="/root/.maintenance"

## don't start as root
if [ $(whoami) != root ]; then
    echo "run as root only"
    exit 0
fi

if [ ! -f "$MAINLOG" ]; then
    echo "Maintenance Logfile not found: $MAINLOG"
    exit 0
fi

E_NOARGS=65
if [ -z "$1" ]
then
  echo "Usage: "
  echo "  ./$(basename $0) \"added new guest account\" "
  echo
  exit $E_NOARGS
fi
mydate=$(date +"%b %d %H:%M:%S")
echo $mydate $1 >> $MAINLOG
exit 0
