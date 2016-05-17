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

# Declare actions
setupop=
volcreate=
tblcreate=

# Declare Variables
rolefile=
restartnodes=
clustername=
multimfs=
extraarg=

function usage () {
	echo 
	echo "Usage : "
    echo "./$me -c=<ClusterConfig> <Arguments> [More Options]"

    echo " Arguments : "
    echo -e "\t -c=<file> | --clusterconfig=<file>" 
    echo -e "\t\t - Cluster Configuration Name/Filepath"
    echo -e "\t -i | --install" 
    echo -e "\t\t - Install cluster"
    echo -e "\t -u | --uninstall" 
    echo -e "\t\t - Uninstall cluster"
    echo -e "\t -h --help"
    echo -e "\t\t - Print this"
    echo 
	echo " More Options : "
    #echo -e "\t -r=[all|{IP}] | --restart  (default : all)" 
    #echo -e "\t\t - Restart warden on all or specified nodes"
    echo -e "\t -n=CLUSTER_NAME | --name=CLUSTER_NAME (default : archerx)" 
    echo -e "\t\t - Specify cluster name"
    echo -e "\t -m=<#ofMFS> | --multimfs=<#ofMFS>" 
    echo -e "\t\t - Specify number of MFS instances (enables MULTI MFS) "
    echo -e "\t -y | --ycsbvol" 
    echo -e "\t\t - Create YCSB related volumes "
    echo -e "\t -t | --tablecreate" 
    echo -e "\t\t - Create usertable with lz4 compression "
    echo 
    echo " Example(s) : "
    echo -e "\t ./$me -c=maprdb install -n=Performance -m=3" 
    echo -e "\t ./$me -c=maprdb uninstall" 
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

    	-i | --install)
    		setupop="install"
    	;;
    	-u | --uninstall)
    		setupop="uninstall"
    	;;
    	-c | --clusterconfig)
    		rolefile=$VALUE
    	;;
    	-n | --name)
    		clustername=$VALUE
    	;;
    	-m | --multimfs)
    		multimfs=$VALUE
    	;;
    	-y | --ycsbvol)
    		extraarg=$extraarg"ycsb "
    	;;
    	-t | --tablecreate)
			extraarg=$extraarg"tablecreate "
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
#elif [ -n "$setupop" ]; then
else
	$libdir/main.sh "$rolefile" "-e=$extraarg" "$setupop" "-c=$clustername" "-m=$multimfs"
fi

if [[ "$setupop" =~ ^uninstall.* ]]; then
	exit
fi

