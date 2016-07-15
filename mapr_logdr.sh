#!/bin/bash

################  
#
#   MapR Cluster Install, Uninstall Script
#
#################
#set -x

# Library directory
basedir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
libdir=$basedir"/lib"
me=$(basename $BASH_SOURCE)
meid=$$

# Declare Variables
rolefile=
args=
tbltdist=

trap handleInterrupt SIGHUP SIGINT SIGTERM

function kill_tree {
    local LIST=()
    IFS=$'\n' read -ra LIST -d '' < <(exec pgrep -P "$1")

    for i in "${LIST[@]}"; do
        kill_tree "$i"
    done

    echo "kill -9 $1"
    kill -9 "$1" 2>/dev/null
}

function handleInterrupt() {
    echo
    echo " Script interrupted!!! Stopping... "
    local mainid=$(ps -o pid --no-headers --ppid $meid)
    echo "CHILD PROCESS ID : $mainid; Sending SIGTERM..."
    kill -15 $mainid 
    kill -9 $mainid 2>/dev/null
    kill_tree $meid
    echo "Bye!!!"
}

function usage () {
	echo 
	echo "Usage : "
    echo "./$me -c=<ClusterConfig> [Options]"

    echo " Options : "
    echo -e "\t -h --help"
    echo -e "\t\t - Print this"

    echo -e "\t -c=<file> | --clusterconfig=<file>" 
    echo -e "\t\t - Cluster Configuration Name/Filepath"

    echo -e "\t -d | --diskerror" 
    echo -e "\t\t - Find any disk errors on nodes"

    echo -e "\t -td=<FILEPATH> | --tabletdist=<FILEPATH>" 
    echo -e "\t\t - Check Tablet distribution across SPs on each node for FILEPATH"
    
    echo 
    echo " Examples : "
    echo -e "\t ./$me -c=maprdb -d" 
    echo -e "\t ./$me -c=maprdb -cd=/tables/usertable" 
}

while [ "$1" != "" ]; do
    OPTION=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    #echo "OPTION -> $OPTION ; VALUE -> $VALUE"
    case $OPTION in
        -h | h | help)
            usage
            exit
            ;;
        -c | --clusterconfig)
            rolefile=$VALUE
        ;;
    	-d | --diskerror)
    		args=$args"diskerror "
    	;;
        -td | --tabletdist)
            if [ -n "$VALUE" ]; then
                args=$args"tabletdist "
                tbltdist="$VALUE"
            fi
        ;;
        *)
            #echo "ERROR: unknown option \"$OPTION\""
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$rolefile" ]; then
	echo "[ERROR] : Cluster config not specified. Please use -c or --clusterconfig option. Run \"./$me -h\" for more info"
	exit 1
elif [ -z "$args" ]; then
    echo "No option specified"
    exit
else
    $libdir/main.sh "$rolefile" "-l=$args" "-cd=$tbltdist"
fi

echo "DONE!"
