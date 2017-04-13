#!/bin/bash

################  
#
#   MapR Cluster Log/Disk/System Analyzer
#
#################
#set -x

# Library directory
basedir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
libdir=$basedir"/lib"
me=$(basename $BASH_SOURCE)
meid=$$

# Declare Variables
returncode=0
rolefile=
args=
tbltdist=
indexname=
sysinfo=
grepkey=
backupdir=
backupregex=
verbose=
doNoFormat=

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
    echo
    echo -e "\t -c=<file> | --clusterconfig=<file>" 
    echo -e "\t\t - Cluster Configuration Name/Filepath"

    echo " Options : "
    echo -e "\t -h --help"
    echo -e "\t\t - Print this"

    echo -e "\t -fl | --noformat" 
    echo -e "\t\t - Remove output formatting (ANSI color)"

    echo -e "\t -d | --diskerror" 
    echo -e "\t\t - Find any disk errors on nodes"

    echo -e "\t -ac | --analyzecores" 
    echo -e "\t\t - Analyze cores present"

    echo -e "\t -v | --verbose" 
    echo -e "\t\t - Print verbose of messages"

    echo -e "\t -dt | --disktest" 
    echo -e "\t\t - Run 'hdparm' disk tests on all nodes for MapR disks"

    echo -e "\t -cd | --containerdist" 
    echo -e "\t\t - Check Container distribution across SPs on each node"

    echo -e "\t -td=<FILEPATH> | --tabletdist=<FILEPATH>" 
    echo -e "\t\t - Check Tablet distribution across SPs on each node for FILEPATH"

    echo -e "\t -in | --indexname= | -in=<INDEXNAME> | --indexname=<INDEXNAME>" 
    echo -e "\t\t - When passed with -td option, check INDEXNAME table's Tablet distribution across nodes"

    echo -e "\t -si=<OPTIONS> | --systeminfo=<OPTIONS>" 
    echo -e "\t\t - Print system info of each node. OPTIONS : mapr,machine,cpu,disk,nw,mem or all (comma separated)"

    echo -e "\t -cs | --clusterspec" 
    echo -e "\t\t - Print overall cluster specifications"

    echo -e "\t -sc | --setupcheck" 
    echo -e "\t\t - Validate a cluster setup & the services"

    echo -e "\t -l | --mfsloggrep" 
    echo -e "\t\t - Grep mfs logs for FATAL & Disk errors"

    echo -e "\t -g=<SEARCHKEY> | --greplogs=<SEARCHKEY>" 
    echo -e "\t\t - Grep MapR logs for SEARCHKEY on all nodes"

    echo -e "\t -b | -b=<COPYTODIR> | --backuplogs=<COPYTODIR>" 
    echo -e "\t\t - Backup /opt/mapr/logs/ directory on each node to COPYTODIR (default COPYTODIR : /tmp/)"

    echo -e "\t -bf=<FILEREGEX> | --backupregex=<FILEREGEX>" 
    echo -e "\t\t - When passed with -b option, backup only log files with name matching the FILEREGEX"
    
    echo 
    echo " Examples : "
    echo -e "\t ./$me -c=maprdb -d -l" 
    echo -e "\t ./$me -c=maprdb -td=/tables/usertable -cd"
    echo -e "\t ./$me -c=maprdb -b=~/logsbkp/ -bf=\"*mfs*\""
    echo -e "\t ./$me -c=maprdb -si -cs"
    echo -e "\t ./$me -c=maprdb -si -fl > /tmp/sysinfo.log"
    echo -e "\t ./$me -c=maprdb -sc"
    echo -e "\t ./$me -c=maprdb -g=\"error 5\""
    echo
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
        -ac | --analyzecores)
            args=$args"analyzecores "
        ;;
        -dt | --disktest)
            args=$args"disktest "
        ;;
        -cs | --clusterspec)
            args=$args"clsspec "
        ;;
        -sc | --setupcheck)
            args=$args"setupcheck "
        ;;
        -cd | --containerdist)
            args=$args"cntrdist "
        ;;
        -td | --tabletdist)
            if [ -n "$VALUE" ]; then
                args=$args"tabletdist "
                tbltdist="$VALUE"
            fi
        ;;
        -in | --indexname)
            if [ -n "$VALUE" ]; then
                indexname="$VALUE"
            else
                indexname="all"
            fi
        ;;
        -b | --backuplogs)
            if [ -z "$VALUE" ]; then
                VALUE="/tmp"
            fi
            backupdir=$VALUE
        ;;
        -bf | --backupregex)
            [ -n "$VALUE" ] && backupregex=$VALUE
        ;;
        -si | --systeminfo)
            sysinfo="$VALUE"
            if [ -z "$sysinfo" ]; then
                sysinfo="all"
            fi
        ;;
        -g | --greplogs)
            if [ -n "$VALUE" ]; then
                grepkey="$VALUE"
            fi
        ;;
        -l | --mfsloggrep)
            args=$args"mfsgrep "
        ;;
        -v | --verbose)
            verbose=1
        ;;
        -fl)
            doNoFormat=1
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
	returncode=1
else
    params="$libdir/main.sh $rolefile -td=$tbltdist -in=${indexname} -si=$sysinfo -v=$verbose \"-e=force\" \"-g=$grepkey\" \"-b=$backupdir\" \"-bf=$backupregex\" \"-l=$args\""
    if [ -z "$doNoFormat" ]; then
        bash -c "$params"
    else
        bash -c "$params" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g'
    fi
    returncode=$?
fi

exit $returncode
