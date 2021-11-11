#!/bin/bash
MAINLOG="/root/.maintenance"

## don't start as root
if [ $(whoami) != root ]; then
    echo "run as root only"
    exit 1
fi

if [ ! -f "$MAINLOG" ]; then
    echo "Maintenance Logfile not found: $MAINLOG"
    exit 1
fi

function getmaintenance {

    COUNT=1
    while read line; do
        NAME=$line;
        echo "$COUNT $NAME"
        COUNT=$((COUNT+1))
    done < $MAINLOG
}

getmaintenance
exit 0
