#!/bin/bash


################  
#
#   utilities
#
################

lib_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$lib_dir/utils.sh"
source "$lib_dir/ssh.sh"

## @param optional hostip
function maprutil_getCLDBMasterNode() {
    local master=
    local hostip=$(util_getHostIP)
    if [ -n "$1" ] && [ "$hostip" != "$1" ]; then
        master=$(ssh_executeCommand "root" "$1" "maprcli node cldbmaster | grep HostName | cut -d' ' -f4")
    else
        master=$(maprcli node cldbmaster | grep HostName | cut -d' ' -f4)
    fi
    if [ ! -z "$master" ]; then
            echo $master
    fi
}

## @param path to config
function maprutil_getCLDBNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local cldbnodes=$(grep cldb $1 | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$cldbnodes" ]; then
            echo $cldbnodes
    fi
}

## @param path to config
## @param host ip
function maprutil_getNodeBinaries() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    
    local binlist=$(grep $2 $1 | cut -d, -f 2- | sed 's/,/ /g')
    if [ ! -z "$binlist" ]; then
        echo $binlist
    fi
}

## @param path to config
function maprutil_getZKNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    
    local zknodes=$(grep zoo $1 | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$zknodes" ]; then
        echo $zknodes
    fi
}

# @param ip_address_string
# @param cldb host ip
function maprutil_isClusterNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    local hostip=$(util_getHostIP)
    local mcldb=$2
    local retval=
    if [ "$hostip" = "$1" ]; then
        retval=$(grep $mcldb /opt/mapr/conf/mapr-clusters.conf)
    else
        retval=$(ssh_executeCommand "root" "$1" "grep $mcldb /opt/mapr/conf/mapr-clusters.conf")
        #echo "ssh return value $?"
    fi
    echo $retval
}

# @param full_path_roles_file
function maprutil_getNodesFromRole() {
    if [ -z "$1" ]; then
        return
    fi
    local nodes=
    for i in $(cat $1 | grep -v '#'); do
        local node=$(echo $i | cut -f1 -d",")
        local isvalid=$(util_validip $node)
        if [ "$isvalid" = "valid" ]; then
            nodes=$nodes$node" "
        else
            echo "Invalid IP [$node]. Scooting"
            exit 1
        fi
    done
    echo $nodes
}

function maprutil_knowndirs(){
    local dirlist=()
    dirlist+=("/maprdev/")
    dirlist+=("/opt/mapr")
    dirlist+=("/var/mapr-zookeeper-data")
    echo ${dirlist[*]}
}

function maprutil_tempdirs() {
    local dirslist=()
    dirlist+=("/tmp/mapr*")
    dirlist+=("/tmp/hsperfdata*")
    dirlist+=("/tmp/hadoop*")
    dirlist+=("/tmp/mapr*")
    dirlist+=("/tmp/*.lck")
    echo  ${dirlist[*]}
}  

function maprutil_removedirs(){
    if [ -z "$1" ]; then
        return
    fi

    while [ "$1" != "" ]; do
        local OPTION=`echo $1 | awk -F= '{print substr($1,2)}'`
        case $OPTION in
            all)
                rm -rfv $(maprutil_knowndirs)
                rm -rfv $(maprutil_tempdirs)
               ;;
             known)
                rm -rfv $(maprutil_knowndirs)
               ;;
             temp)
                rm -rfv $(maprutil_tempdirs)
               ;;
            *)
                echo "ERROR: unknown parameter \"$PARAM\""
                ;;
        esac
        shift
    done
}

# @param host ip
function maprutil_isMapRInstalledOnNode(){
    if [ -z "$1" ] ; then
        return
    fi
    
    # build full script for node
    local scriptpath="/tmp/isinstalled.sh"
    util_builtSingleScript "$lib_dir" "$scriptpath" 
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "util_getInstalledBinaries 'mapr-'" >> $scriptpath

    local bins=
    local hostip=$(util_getHostIP)
    if [ "$hostip" != "$1" ]; then
        bins=$(ssh_executeScriptasRoot "$1" "$scriptpath")
    else
        bins=$(util_getInstalledBinaries "mapr-")
    fi

    if [ -z "$bins" ]; then
        echo "false"
    else
        echo "true"
    fi
}

# @param host ip
function maprutil_isNodePartofCluster(){
    echo
}

function maprutil_uninstallNode2(){
    
    # Stop warden
    /etc/init.d/mapr-warden stop

    # Stop zookeeper
    /etc/init.d/mapr-zookeeper stop

    # Remove MapR Binaries
    maprutil_removemMapRPackages

    # Run Yum clean
    yum clean all

    # Remove mapr shared memory segments
    util_removeSHMSegments "mapr"

    # Remove all directories
    maprutil_removedirs "all"

    # kill all processes
    util_kill "guts"
    util_kill "java" "jenkins" "elasticsearch"

}

# @param host ip
function maprutil_uninstallNode(){
    if [ -z "$1" ] ; then
        return
    fi
    
    # build full script for node
    local scriptpath="/tmp/uninstallnode.sh"
    util_builtSingleScript "$lib_dir" "$scriptpath" 
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "maprutil_uninstallNode2" >> $scriptpath

    local bins=
    local hostip=$(util_getHostIP)
    if [ "$hostip" != "$1" ]; then
        ssh_executeScriptasRootInBG "$1" "$scriptpath"
    else
        maprutil_uninstallNode2
    fi
}

# @param host ip
# @param binary list
# @param don't wait
function maprutil_installBinariesOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    # build full script for node
    local scriptpath="/tmp/installbinnode.sh"
    util_builtSingleScript "$lib_dir" "$scriptpath" 
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "util_installBinaries \""$2"\"" >> $scriptpath

    local hostip=$(util_getHostIP)
    if [ "$hostip" != "$1" ]; then
        ssh_executeScriptasRootInBG "$1" "$scriptpath"
        if [ -z "$3" ]; then
            wait
        fi
    else
        util_installBinaries "$2"
    fi
}

function maprutil_configureNode2(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    local hostip=$(util_getHostIP)
    local cldbnodes=$(util_getCommaSeparated "$1")
    local zknodes=$(util_getCommaSeparated "$2")
    local disklist=$(util_getCommaSeparated "$(util_getRawDisks)")
    echo "$disklist" > /tmp/disklist.txt

    echo "/opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3"
    /opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3

    #echo "/opt/mapr/server/disksetup -FM /tmp/disklist"
    /opt/mapr/server/disksetup -FM /tmp/disklist

    # Start zookeeper
    /etc/init.d/mapr-zookeeper start;
    
    /etc/init.d/mapr-warden restart

    local cldbnode=$(util_getFirstElement "$1")
    if [ "$hostip" = "$cldbnode" ]; then
        maprutil_applyLicense
    fi
}

# @param host ip
# @param config file path
# @param cluster name
# @param don't wait
function maprutil_configureNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
     # build full script for node
    local scriptpath="/tmp/configurenode.sh"
    util_builtSingleScript "$lib_dir" "$scriptpath" 
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local cldbnodes=$(maprutil_getCLDBNodes "$2")
    local zknodes=$(maprutil_getZKNodes "$2")
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "maprutil_configureNode2 \""$cldbnodes"\" \""$zknodes"\" \""$3"\"" >> $scriptpath

    local hostip=$(util_getHostIP)
    if [ "$hostip" != "$1" ]; then
        ssh_executeScriptasRootInBG "$1" "$scriptpath"
        if [ -z "$4" ]; then
            wait
        fi
    else
        maprutil_configureNode2 "$cldbnodes" "$zknodes" "$3"
    fi
}

function maprutil_getBuildID(){
    local buildid=`yum info mapr-core installed  | grep Version | tr "." " " | awk '{print $6}'`
    echo "$buildid"
}

function maprutil_applyLicense(){
    wget http://stage.mapr.com/license/LatestDemoLicense-M7.txt --user=maprqa --password=maprqa -O /tmp/LatestDemoLicense-M7.txt
    local buildid=$(maprutil_getBuildID)
    local i=0
    local jobs=1
    while [ "${jobs}" -ne "0" ]; do
        echo "Waiting for CLDB to come up before applying license.... sleeping 30s"
        sleep 30
        echo "Recovered jobs="$jobs
        if [ "$jobs" -ne 0 ]; then
            local licenseExists=`/opt/mapr/bin/maprcli license list | grep M7 | wc -l`
            if [ "$licenseExists" -ne 0 ]; then
                jobs=0
            fi
        fi
        ### Attempt using Downloaded License
        if [ "${jobs}" -ne "0" ]; then
            jobs=`/opt/mapr/bin/maprcli license add -license /tmp/LatestDemoLicense-M7.txt -is_file true > /dev/null;echo $?`;
        fi
        let i=i+1
        if [ "$i" -gt 10 ]; then
            echo "Failed to apply license. Node may not be configured correctly"
            exit 1
        fi
    done
}

## @param optional hostip
function maprutil_restartWardenOnNode() {
     if [ -z "$1" ]; then
        return
    fi
    local hostip=$(util_getHostIP)
    if [ "$hostip" != "$1" ]; then
        ssh_executeCommandasRoot "$1" "service mapr-warden restart"
    else
        service mapr-warden restart
    fi
}

function maprutil_removemMapRPackages(){
   
    util_removeBinaries "mapr-"
}

### 
