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

# Declare actions
setupop=
volcreate=
tblcreate=

# Declare Variables
rolefile="rolefile"
restartnodes=
clustername=
multimfs=
numsps=
tablens=
maxdisks=
extraarg=
backupdir=
buildid=
volname=
putbuffer=
maxmfsmem=
fsthreads=
gwthreads=
repourl=
meprepourl=
patchrepourl=
patchid=

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
    echo "./$me -c=<ClusterConfig> <Arguments> [Options]"

    echo " Arguments : "
    echo -e "\t -h --help"
    echo -e "\t\t - Print this"

    echo -e "\t -c=<file> | --clusterconfig=<file>" 
    echo -e "\t\t - Cluster Configuration Name/Filepath"
    echo -e "\t -i | --install" 
    echo -e "\t\t - Install cluster"
    echo -e "\t -u | --uninstall" 
    echo -e "\t\t - Uninstall cluster"
    echo -e "\t -up | --upgrade" 
    echo -e "\t\t - Upgrade cluster"
    echo -e "\t -rup | --rollingupgrade" 
    echo -e "\t\t - Rolling cluster upgrade"
    echo -e "\t -r | --reconfigure | --reset" 
    echo -e "\t\t - Reconfigure the cluster if binaries are already installed"
    echo -e "\t -b | -b=<COPYTODIR> | --backuplogs=<COPYTODIR>" 
    echo -e "\t\t - Backup /opt/mapr/logs/ directory on each node to COPYTODIR (default COPYTODIR : /tmp/)"
    
    echo 
    echo " Install/Uninstall Options : "
    # Build replated parameters
    echo -e "\t -bld=<BUILDID> | --buildid=<BUILDID>" 
    echo -e "\t\t - Specify a BUILDID if the repository has more than one version of same binaries (default: install the latest binaries)"
    echo -e "\t -repo=<REPOURL> | --repository=<REPOURL>" 
    echo -e "\t\t - Specify a REPOURL to use to download & install binaries"
    echo -e "\t -prepo=<PATCHREPOURL> | --patchrepository=<PATCHREPOURL>" 
    echo -e "\t\t - Specify a PATCHREPOURL to use to download & install binaries. (Optional if using internal repositories)"
    echo -e "\t -meprepo=<MEPREPOURL> | --meprepository=<MEPREPOURL>" 
    echo -e "\t\t - Specify a MEPREPOURL to use to download & install opensource binaries. (Optional if using internal repositories)"
    
    # Patch replated parameters
    echo -e "\t -patch | --applypatch"
    echo -e "\t\t - Apply patch"
    echo -e "\t -pbld=<PATCHID> | --patchid=<PATCHID>"
    echo -e "\t\t - Specify a PATCHID for the mapr-patch (not client)"

    echo -e "\t -spy | --spyglass"
    echo -e "\t\t - Install SpyGlass (only opentsdb,collectd,grafana)"
    echo -e "\t -spy2 | --spyglass2"
    echo -e "\t\t - Install SpyGlass (only opentsdb,collectd,grafana,kibana,elasticsearch,fluentd)"
    echo -e "\t -ns | -ns=TABLENS | --tablens=TABLENS" 
    echo -e "\t\t - Add table namespace to core-site.xml as part of the install process (default : /tables)"
    echo -e "\t -n=CLUSTER_NAME | --name=CLUSTER_NAME (default : archerx)" 
    echo -e "\t\t - Specify cluster name"
    echo -e "\t -d=<#ofDisks> | --maxdisks=<#ofDisks>" 
    echo -e "\t\t - Specify number of disks to use (default : all available disks)"
    echo -e "\t -sp=<#ofSPs> | --storagepool=<#ofSPs>" 
    echo -e "\t\t - Specify number of storage pools per node"
    echo -e "\t -m=<#ofMFS> | --multimfs=<#ofMFS>" 
    echo -e "\t\t - Specify number of MFS instances (enables MULTI MFS) "
    echo -e "\t -ssd | --ssdonly" 
    echo -e "\t\t - Use only SSD disks if the node(s) have mix of HDD & SSD"
    echo -e "\t -hdd | --hddonly" 
    echo -e "\t\t - Use only HDD disks if the node(s) have mix of HDD & SSD"
    echo -e "\t -s | --secure" 
    echo -e "\t\t - Enable wire-level security on the cluster nodes"
     echo -e "\t -dare" 
    echo -e "\t\t - Generate dare master key if security is enabled"
    echo -e "\t -f | --force" 
    echo -e "\t\t - Force uninstall a node/cluster"
    echo -e "\t -pb=<#ofMBs> | --putbuffer=<#ofMBs>" 
    echo -e "\t\t - Increase client put buffer threshold to <#ofMBs> (default : 1000)"
    echo -e "\t -ft=<#ofThreads> | --flusherthreads=<#ofThreads>" 
    echo -e "\t\t - Update flusher threads config 'fs.mapr.threads' in core-site.xml (default: 64)"
    echo -e "\t -gt=<#ofThreads> | --gatewaythreads=<#ofThreads>" 
    echo -e "\t\t - Update gateway receive threads config 'gateway.receive.numthreads' in gateway.conf"
    echo -e "\t -mm=<%NUM> | --maxmfsmemory=<%NUM>" 
    echo -e "\t\t - Update the maximum MFS heap memory percentage"
    echo -e "\t -tr | --trim" 
    echo -e "\t\t - Trim SSD drives before configuring the node (WARNING: DO NOT TRIM OFTEN)"
    echo -e "\t -p | --pontis" 
    echo -e "\t\t - Configure MFS lrus sizes for Pontis usecase, limit disks to 6 and SPs to 2"
    echo -e "\t -qs | --queryservice" 
    echo -e "\t\t - Enabled query service if Drill is installed"
    echo -e "\t -et | --enabletrace" 
    echo -e "\t\t - Enable guts,dstat & iostat on each node after INSTALL. (Can be run post install as well)"
    echo -e "\t -dt | --disabletrace" 
    echo -e "\t\t - Disable trace processes on all nodes (Can be run post install as well)"
    echo -e "\t -ig | --instanceguts"
    echo -e "\t\t - Enable instance level guts trace on all nodes"
    echo -e "\t -aut | --atsusertickets" 
    echo -e "\t\t - Create ATS user(m7user[1-4],mapruser[1-2]) tickets"
    echo -e "\t -acs | --atsnodesetup" 
    echo -e "\t\t - Setup ATS client nodes w/ maven/git/docker etc"
    
    echo 
	echo " Post install Options : "
    echo -e "\t -ct | --cldbtopo" 
    echo -e "\t\t - Move CLDB node & volume to /cldb topology (enabled by default if cluster size > 5)"
    echo -e "\t -nct | --nocldbtopo" 
    echo -e "\t\t - Disable moving of CLDB node and volume to /cldb topology by default"
    echo -e "\t -vol=<NAME,VOLUMEPATH> | -y=<NAME,VOLUMEPATH>  | --volume=<NAME,VOLUMEPATH>" 
    echo -e "\t\t - Create volume NAME with VOLUMEPATH"
    echo -e "\t -tc | --tsdbtocldb" 
    echo -e "\t\t - Move OpenTSDB volume to /cldb topology"
    echo -e "\t -ea | --enableaudit" 
    echo -e "\t\t - Enable cluster wide audit"

    echo -e "\t -t | --tablecreate" 
    echo -e "\t\t - Create /tables/usertable [cf->family] with compression off"
    echo -e "\t -tlz | --tablelz4" 
    echo -e "\t\t - Create /tables/usertable [cf->family] with lz4 compression"
    echo -e "\t -j | --jsontablecreate" 
    echo -e "\t\t - Create YCSB JSON Table with default family"
    echo -e "\t -jcf | --jsontablecf" 
    echo -e "\t\t - Create YCSB JSON Table with second CF family cfother"
    
    echo 
    echo " Examples : "
    echo -e "\t ./$me -c=maprdb -i -n=Performance -m=3" 
    echo -e "\t ./$me -c=maprdb -u"
    echo -e "\t ./$me -c=roles/pontis.roles -i -p -n=Pontis" 
    echo -e "\t ./$me -c=/root/configs/cluster.role -i -d=4 -sp=2" 
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

    	-i | --install)
    		setupop="install"
            [[ "$rolefile" = "rolefile" ]] && rolefile="install"
    	;;
    	-u | --uninstall)
    		setupop="uninstall"
    	;;
        -up | --upgrade)
            setupop="upgrade"
        ;;
        -rup | --rollingupgrade)
            setupop="upgrade"
            extraarg=$extraarg"rolling "
        ;;
        -r | --reconfigure | --reset)
            setupop="reconfigure"
            [[ "$rolefile" = "rolefile" ]] && rolefile="reconfigure"
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
        -ssd | --ssdonly)
            extraarg=$extraarg"ssdonly "
        ;;
        -hdd | --hddonly)
            extraarg=$extraarg"hddonly "
        ;;
        -d | --maxdisks)
            maxdisks=$VALUE
        ;;
        -ct | --cldbtopo)
            extraarg=$extraarg"cldbtopo "
        ;;
        -nct | --nocldbtopo)
            extraarg=$extraarg"nocldbtopo "
        ;;
        -tc | --tsdbtocldb)
            extraarg=$extraarg"tsdbtopo "
        ;;
    	-vol | -y | --volume)
            if [ -z "$VALUE" ]; then
                VALUE="tables,/tables"
            fi
            extraarg=$extraarg"createvol "
            volname=$VALUE
    	;;
        -ea | --enableaudit)
            if [ -z "$VALUE" ]; then
                extraarg=$extraarg"enableaudit "
            else
                extraarg=$extraarg"auditstream "
            fi
        ;;
    	-t | --tablecreate)
			extraarg=$extraarg"tablecreate "
    	;;
        -j | --jsontablecreate)
            extraarg=$extraarg"jsontable "
        ;;
        -jcf | --jsontablecf)
            extraarg=$extraarg"jsontablecf "
        ;;
        -tlz | --tablelz4)
            extraarg=$extraarg"tablelz4 "
        ;;
        -et | --enabletrace)
            extraarg=$extraarg"traceon "
        ;;
        -ig | --instanceguts)
            extraarg=$extraarg"insttrace "
        ;;
        -dt | --disabletrace)
            extraarg=$extraarg"traceoff "
        ;;
        -tr | --trim)
            extraarg=$extraarg"trim "
        ;;
        -spy | --spyglass)
            extraarg=$extraarg"spy "
        ;;
        -spy2 | --spyglass2)
            extraarg=$extraarg"spy2 "
        ;;
        -qs | --queryservice)
            extraarg=$extraarg"queryservice "
        ;;
        -aut | --atsusertickets)
            extraarg=$extraarg"atstickets "
        ;;
        -acs | --atsnodesetup)
            extraarg=$extraarg"atssetup "
        ;;
        -sp | --storagepool)
            numsps=$VALUE
        ;;
        -p | --pontis)
            extraarg=$extraarg"pontis "
            numsps=2
            maxdisks=6
        ;;
        -ns | --tablens)
            if [ -z "$VALUE" ]; then
                VALUE="/tables"
            fi
            tablens=$VALUE
        ;;
        -f | --force)
           extraarg=$extraarg"force "
        ;;
        -yes)
           extraarg=$extraarg"confirm "
        ;;
        -s | --secure)
            extraarg=$extraarg"secure "
        ;;
        -dare)
            extraarg=$extraarg"dare "
        ;;
        -b | --backuplogs)
            if [ -z "$VALUE" ]; then
                VALUE="/tmp"
            fi
            backupdir=$VALUE
        ;;
        -bld | --buildid)
            if [ -n "$VALUE" ]; then
                buildid=$VALUE
            fi
        ;;
        -pb | --putbuffer)
            if [ -n "$VALUE" ]; then
                putbuffer=$VALUE
            else
                putbuffer=2000
            fi
        ;;
        -ft | --flusherthreads)
            if [ -n "$VALUE" ]; then
                fsthreads=$VALUE
            fi
        ;;
        -gt | --gatewaythreads)
            if [ -n "$VALUE" ]; then
                gwthreads=$VALUE
            fi
        ;;
        -mm | --maxmfsmemory)
            if [ -n "$VALUE" ]; then
                maxmfsmem=$VALUE
            fi
        ;;
        -repo | --repository)
            if [ -n "$VALUE" ]; then
                repourl=$VALUE
            fi
        ;;
        -prepo | --patchrepository)
            if [ -n "$VALUE" ]; then
                patchrepourl=$VALUE
            fi
        ;;
        -meprepo | --meprepository)
            if [ -n "$VALUE" ]; then
                meprepourl=$VALUE
            fi
        ;;
        -pbld | --patchid)
            if [ -n "$VALUE" ]; then
                patchid=$VALUE
            fi
        ;;
        -patch | --applypatch)
            extraarg=$extraarg"patch "
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
	>&2 echo "[ERROR] : Cluster config not specified. Please use -c or --clusterconfig option. Run \"./$me -h\" for more info"
	exit 1
else
    $libdir/main.sh "$rolefile" "-s=$setupop" "-e=$extraarg" "-c=$clustername" "-m=$multimfs" "-ns=$tablens" "-d=$maxdisks" \
    "-sp=$numsps" "-b=$backupdir" "-bld=$buildid" "-pb=$putbuffer" "-ft=$fsthreads" "-gt=$gwthreads" "-repo=$repourl" \
    "-prepo=$patchrepourl" "-meprepo=$meprepourl" "-pid=$patchid" "-maxm=$maxmfsmem" "-vol=$volname"
    returncode=$?
    [ "$returncode" -ne "0" ] && exit $returncode
fi

if [[ "$setupop" =~ ^uninstall.* ]]; then
	exit
fi

echo "DONE!"
