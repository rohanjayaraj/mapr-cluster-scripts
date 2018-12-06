#!/bin/bash


################  
#
#   utilities
#
################

lib_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$lib_dir/utils.sh"
source "$lib_dir/ssh.sh"
source "$lib_dir/logger.sh"

### START_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###

## @param optional hostip
function maprutil_getCLDBMasterNode() {
    local master=
    local hostip=$(util_getHostIP)
    local usemaprcli=$2
    if [ -n "$2" ] && [ -n "$1" ]; then
        master=$(ssh_executeCommandWithTimeout "root" "$1" "timeout 30 maprcli node cldbmaster 2>/dev/null | grep HostName | cut -d' ' -f4" "10")
        master=$(util_getIPfromHostName $master)
    elif [ -n "$1" ] && [ "$hostip" != "$1" ]; then
        #master=$(ssh_executeCommandWithTimeout "root" "$1" "timeout 30 maprcli node cldbmaster | grep HostName | cut -d' ' -f4" "10")
        master=$(ssh_executeCommandasRoot "$1" "[ -e '/opt/mapr/conf/mapr-clusters.conf' ] && cat /opt/mapr/conf/mapr-clusters.conf | cut -d' ' -f3 | cut -d':' -f1")
    else
        #master=$(timeout 10 maprcli node cldbmaster | grep HostName | cut -d' ' -f4)
        master=$([ -e '/opt/mapr/conf/mapr-clusters.conf' ] && cat /opt/mapr/conf/mapr-clusters.conf | cut -d' ' -f3 | cut -d':' -f1)
    fi
    if [ ! -z "$master" ]; then
        if [[ ! "$master" =~ ^Killed.* ]] || [[ ! "$master" =~ ^Terminate.* ]]; then
            echo $master
        fi
    fi
}

## @param path to config
function maprutil_getCLDBNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local cldbnodes=$(grep cldb $1 2>/dev/null| grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$cldbnodes" ]; then
            echo $cldbnodes | sed 's/[[:space:]]*$//'
    fi
}

## @param path to config
function maprutil_getGatewayNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local gwnodes=$(grep mapr-gateway $1 2>/dev/null| grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$gwnodes" ]; then
        echo $gwnodes | sed 's/[[:space:]]*$//'
    fi
}

## @param path to config
function maprutil_getESNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local esnodes=$(grep elastic $1 2>/dev/null| grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$esnodes" ]; then
            echo $esnodes | sed 's/[[:space:]]*$//'
    fi
}

## @param path to config
function maprutil_getOTSDBNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local otnodes=$(grep opentsdb $1 2>/dev/null| grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$otnodes" ]; then
            echo $otnodes | sed 's/[[:space:]]*$//'
    fi
}

## @param path to config
function maprutil_getDrillNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local drillnodes=$(grep drill $1 2>/dev/null| grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$drillnodes" ]; then
        echo $drillnodes | sed 's/[[:space:]]*$//'
    fi
}

## @param service name
function maprutil_getNodesForService() {
    if [ -z "$GLB_ROLE_LIST" ] || [ -z "$1" ]; then
        return 1
    fi
    local rolelist="$(maprutil_getRolesList)"
    local servicenodes=$(echo "$rolelist" | grep "$1" | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$servicenodes" ]; then
        echo $servicenodes | sed 's/[[:space:]]*$//'
    fi
}

## @param path to config
function maprutil_buildRolesList(){
     if [ -z "$1" ]; then
        return 1
    fi
    echo "$(cat $1 2>/dev/null| grep '^[^#;]' | tr '\n' '#' | sed 's/#$//')"
}

function maprutil_getRolesList(){
     if [ -z "$GLB_ROLE_LIST" ]; then
        return 1
    fi
    echo "$(echo "$GLB_ROLE_LIST" | tr '#' '\n')"
}

## @param path to config
function maprutil_getMFSDataNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local mfsnodes=
    local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
    
    if [ -n "$cldbnodes" ]; then
        local cldbnode=$(util_getFirstElement "$cldbnodes")
        local isCLDBUp=$(maprutil_waitForCLDBonNode "$cldbnode")
        if [ -n "$isCLDBUp" ]; then
            local mfshosts="$(ssh_executeCommandasRoot "$cldbnode" "timeout 30 maprcli node list -columns id,configuredservice,racktopo -json 2>/dev/null | grep 'hostname\|racktopo' | grep -B1 '/data/' | grep hostname | tr -d '\"' | cut -d':' -f2 | tr -d ','")"
            for mfshost in $mfshosts
            do
                mfsnodes="$mfsnodes $(util_getIPfromHostName $mfshost)"
            done
            [ -z "$(echo $mfsnodes | grep [0-9])" ] && mfsnodes="$(ssh_executeCommandasRoot "$cldbnode" "timeout 30 maprcli node list -columns id,configuredservice,racktopo -json 2>/dev/null | grep 'ip\|racktopo' | grep -B1 '/data/' | grep ip | tr -d '\"' | cut -d':' -f2 | tr -d ','")"
        else
            mfsnodes=$(grep mapr-fileserver $1 | grep '^[^#;]' | grep -v cldb | awk -F, '{print $1}')
        fi
    else
        mfsnodes=$(cat $rolefile | grep '^[^#;]' | awk -F, '{print $1}')
    fi
    
    [ -n "$mfsnodes" ] && echo "$mfsnodes" | sed ':a;N;$!ba;s/\n/ /g' | sed 's/[[:space:]]*$//'
}

## @param path to config
## @param host ip
function maprutil_getNodeBinaries() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    
    local binlist=$(grep $2 $1 | grep '^[^#;]' | cut -d, -f 2- | sed 's/,/ /g')
    if [ ! -z "$binlist" ]; then
        echo $binlist
    fi
}

## @param path to config
## @param host ip
function maprutil_getCoreNodeBinaries() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    
    local binlist=$(grep $2 $1 | grep '^[^#;]' | cut -d, -f 2- | sed 's/,/ /g')
    if [ -n "$binlist" ]; then
        # Remove collectd,fluentd,opentsdb,kibana,grafana
        local newbinlist=
        for bin in ${binlist[@]}
        do
            if [[ ! "${bin}" =~ collectd|fluentd|opentsdb|kibana|grafana|elasticsearch|asynchbase|drill|webserver2 ]]; then
                newbinlist=$newbinlist"$bin "
            fi
        done
        if [ -z "$(maprutil_isClientNode $1 $2)" ]; then
            [ -n "$GLB_MAPR_PATCH" ] && [ -z "$(echo $newbinlist | grep mapr-patch)" ] && newbinlist=$newbinlist"mapr-patch"
        fi
        echo $newbinlist
    fi
}

# @param rolefile
function maprutil_getPostInstallNodes(){
    [ -z "$1" ] && return
    local nodelist=
    while read -r line
    do
        local node=$(echo $line | awk -F, '{print $1}')
        local binlist=$(echo $line | cut -d',' -f2- | sed 's/,/ /g')
        for bin in ${binlist[@]}
        do
            if [[ "${bin}" =~ collectd|fluentd|opentsdb|kibana|grafana|elasticsearch|asynchbase|drill|webserver2 ]]; then
                nodelist="$nodelist $node"
                break
            fi
        done
    done <<<"$(cat $1 2>/dev/null | grep '^[^#;]')"
    if [ -n "$nodelist" ]; then
        echo $nodelist
    fi
}

## @param path to config
## @param host ip
function maprutil_hasSpyglass() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    local binlist=$(grep $2 $1 | cut -d, -f 2- | sed 's/,/ /g')
    if [ -n "$binlist" ]; then
        for bin in ${binlist[@]}
        do
            if [[ "${bin}" =~ collectd|fluentd|opentsdb|kibana|grafana|elasticsearch ]]; then
                echo "yes"
                break
            fi
        done
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

## @param path to config
## @param host ip
function maprutil_isClientNode() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    [ -n "$(grep $2 $1 | grep mapr-fileserver)" ] && return
    local isclient=$(grep $2 $1 | grep -v 'mapr-fileserver' | grep 'mapr-client\|mapr-loopbacknfs\|mapr-posix' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    [ -z "$isclient" ] && isclient=$(grep $2 $1 | cut -d',' -f2 | grep -v 'mapr-fileserver' | grep mapr-core)
    if [ -n "$isclient" ]; then
        echo $isclient
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
    while read -r i; do
        local node=$(echo $i | sed 's/,[[:space:]]*/,/g' | tr ' ' ',' | cut -f1 -d",")
        local isvalid=$(util_validip2 $node)
        if [ "$isvalid" = "valid" ]; then
            nodes=$nodes$node" "
        else
            echo "Invalid IP [$node]. Scooting"
            exit 1
        fi
    done <<< "$(cat $1 | grep '^[^#;]')"
    echo $nodes | tr ' ' '\n' | sort -t . -k 3,3n -k 4,4n | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

function maprutil_ycsbdirs(){
    local dirlist=()
    for i in $(find /var/ycsb -maxdepth 1 -type d -ctime +10 2>/dev/null)
    do
      dirlist+=("$i")
    done
    echo ${dirlist[*]}
}

function maprutil_rubixdirs(){
    local dirlist=()
    for i in $(find /var/rubix -maxdepth 1 -type d -ctime +10 2>/dev/null)
    do
      dirlist+=("$i")
    done
    echo ${dirlist[*]}
}

function maprutil_coresdirs(){
    local dirlist=()
    dirlist+=("/opt/cores/guts*")
    dirlist+=("/opt/cores/mfs*")
    dirlist+=("/opt/cores/java.core.*")
    dirlist+=("/opt/cores/collectd.core.*")
    dirlist+=("/opt/cores/reader*core*")
    dirlist+=("/opt/cores/writer*core*")
    dirlist+=("/opt/cores/*mrconfig*")
    dirlist+=("/opt/cores/g*.log")
    dirlist+=("/opt/cores/h*.log")
    dirlist+=("/opt/cores/java*.hprof")
    dirlist+=("/opt/cores/mrdisk*core*")
    dirlist+=("/opt/cores/hoststat*core*")
    dirlist+=("/opt/cores/posix*core*")
    echo ${dirlist[*]}
}

function maprutil_knowndirs(){
    local dirlist=()
    dirlist+=("/maprdev/")
    dirlist+=("/opt/mapr")
    dirlist+=("/var/mapr-zookeeper-data")
    dirlist+=("/etc/drill")
    dirlist+=("/var/log/drill")
    dirlist+=("/mapr/perf")
    dirlist+=("/mapr/archerx")
    dirlist+=("/mapr/[A-Za-z0-9]*")
    echo ${dirlist[*]}
}

function maprutil_tempdirs() {
    local dirslist=()
    dirlist+=("/tmp/*mapr*.*")
    dirlist+=("/tmp/hsperfdata*")
    dirlist+=("/tmp/hadoop*")
    dirlist+=("/tmp/*mapr-disk.rules*")
    dirlist+=("/tmp/*.lck")
    dirlist+=("/tmp/mfs*")
    dirlist+=("/tmp/isinstalled_*")
    dirlist+=("/tmp/uninstallnode_*")
    dirlist+=("/tmp/installbinnode_*")
    dirlist+=("/tmp/upgradenode_*")
    dirlist+=("/tmp/disklist*")
    dirlist+=("/tmp/configurenode_*")
    dirlist+=("/tmp/postconfigurenode_*")
    dirlist+=("/tmp/cmdonnode_*")
    dirlist+=("/tmp/defdisks*")
    dirlist+=("/tmp/zipdironnode_*")
    dirlist+=("/tmp/maprbuilds*")
    dirlist+=("/tmp/restartonnode_*")
    dirlist+=("/tmp/maprsetup_*")
    dirlist+=("/tmp/ycsb*.sh")
    dirlist+=("/tmp/dstat.*.out")
    dirlist+=("/tmp/iostat.*.out")
    dirlist+=("/tmp/guts.*.out")
    dirlist+=("/tmp/mpstat.*.out")
    dirlist+=("/tmp/top.*.out")
    dirlist+=("/tmp/clienttrace*.sh")
    dirlist+=("/tmp/perftool/")
    dirlist+=("/tmp/maprtrace/")
    dirlist+=("/tmp/maprlogs/")

    echo  ${dirlist[*]}
}  

function maprutil_removedirs(){
    if [ -z "$1" ]; then
        return
    fi

   case $1 in
        all)
            rm -rfv $(maprutil_knowndirs) > /dev/null 2>&1
            rm -rfv $(maprutil_tempdirs)  > /dev/null 2>&1
            rm -rfv $(maprutil_coresdirs) > /dev/null 2>&1
            rm -rfv $(maprutil_ycsbdirs) > /dev/null 2>&1
            rm -rfv $(maprutil_rubixdirs) > /dev/null 2>&1
           ;;
         known)
            rm -rfv $(maprutil_knowndirs) 
           ;;
         temp)
            rm -rfv $(maprutil_tempdirs)
           ;;
         cores)
            rm -rfv $(maprutil_coresdirs)
           ;;
         ycsb)
            rm -rfv $(maprutil_ycsbdirs)
           ;;
         rubix)
            rm -rfv $(maprutil_rubixdirs)
           ;;
        *)
            log_warn "unknown parameter passed to removedirs \"$PARAM\""
            ;;
    esac
       
}

# @param host ip
function maprutil_isMapRInstalledOnNode(){
    if [ -z "$1" ] ; then
        return
    fi
    
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/isinstalled_${hostnode}.sh"

    # build full script for node
    maprutil_buildSingleScript "$scriptpath" "$hostnode"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi
    echo "util_getInstalledBinaries 'mapr-'" >> $scriptpath

    local bins=
    local hostip=$(util_getHostIP)
    if [ "$hostip" != "$hostnode" ]; then
        bins=$(ssh_executeScriptasRoot "$hostnode" "$scriptpath")
    else
        bins=$(util_getInstalledBinaries "mapr-")
    fi

    if [ -z "$bins" ]; then
        echo "false"
    else
        echo "true"
    fi
}

function maprutil_isMapRInstalledOnNodes(){
    if [ -z "$1" ] ; then
        return
    fi
    local maprnodes=$1
    local maprversion=$2
    local tmpdir="$RUNTEMPDIR/installed"
    mkdir -p $tmpdir 2>/dev/null
    local yeslist=
    for node in ${maprnodes[@]}
    do
        local nodelog="$tmpdir/$node.log"
        maprutil_isMapRInstalledOnNode "$node" > $nodelog &
        maprutil_addToPIDList "$!"
        if [ -n "$maprversion" ]; then
            local nodevlog="$tmpdir/$node_ver.log"
            maprutil_getMapRVersionOnNode "$node" > $nodevlog &
            maprutil_addToPIDList "$!"
        fi
    done
    maprutil_wait > /dev/null 2>&1
    for node in ${maprnodes[@]}
    do
        local nodelog=$(cat $tmpdir/$node.log)
        if [ "$nodelog" = "true" ]; then
            if [ -n "$maprversion" ]; then
                local nodevlog=$(cat $tmpdir/$node_ver.log)
                yeslist=$yeslist"$node $nodevlog""\n"
            else
                yeslist=$yeslist"$node"" "
            fi
        fi
    done
    echo -e "$yeslist"
}

# @param host ip
function maprutil_getMapRVersionOnNode(){
    if [ -z "$1" ] ; then
        return
    fi
    local node=$1
    local version=$(ssh_executeCommandasRoot "$node" "[ -e '/opt/mapr/MapRBuildVersion' ] && cat /opt/mapr/MapRBuildVersion")
    local patch=
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ]; then
        patch=$(ssh_executeCommandasRoot "$node" "rpm -qa | grep mapr-patch | cut -d'-' -f4 | cut -d'.' -f1")
    elif [ "$nodeos" = "ubuntu" ]; then
        patch=$(ssh_executeCommandasRoot "$node" "dpkg -l | grep mapr-patch | awk '{print $3}' | cut -d'-' -f4 | cut -d'.' -f1")
    fi
    [ -n "$patch" ] && patch=" (patch ${patch})"
    if [ -n "$version" ]; then
        echo $version$patch
    fi
}

# @param version to check "x.y.z"
function maprutil_isMapRVersionSameOrNewer(){
    if [ -z "$1" ] ; then
        return
    fi

    local curver=$(cat /opt/mapr/MapRBuildVersion)
    local ismaprv=($(echo $1 | tr '.' ' ' | awk '{print $1,$2,$3}'))

    if [ -n "$curver" ]; then
        local maprv=($(echo $curver | tr '.' ' ' | awk '{print $1,$2,$3}'))
        local oldver=
        if [ "${maprv[0]}" -lt "${ismaprv[0]}" ]; then
            oldver=1
        elif [ "${maprv[0]}" -eq "${ismaprv[0]}" ] && [ "${maprv[1]}" -lt "${ismaprv[1]}" ]; then
            oldver=1
        elif [ "${maprv[0]}" -eq "${ismaprv[0]}" ] && [ "${maprv[1]}" -eq "${ismaprv[1]}" ] && [ "${maprv[2]}" -lt "${ismaprv[2]}" ]; then
            oldver=1
        fi
        
        if [ -z "$oldver" ]; then
            echo "newer"
        fi
    fi
    
}

function maprutil_unmountNFS(){
    local nfslist=$(mount | grep nfs | grep mapr | grep -v '10.10.10.20' | cut -d' ' -f3)
    for i in $nfslist
    do
        timeout 20 umount -l $i
    done

    if [ -n "$(util_getInstalledBinaries mapr-posix)" ]; then
        local fusemnt=$(mount -l | grep posix-client | awk '{print $3}')
        service mapr-posix-client* stop > /dev/null 2>&1
        /etc/init.d/mapr-fuse stop > /dev/null 2>&1
        /etc/init.d/mapr-posix-* stop > /dev/null 2>&1
        [ -n "$fusemnt" ] && timeout 10 fusermount -uq $fusemnt > /dev/null 2>&1
    fi
}

# @param host ip
function maprutil_cleanPrevClusterConfigOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local client=$(maprutil_isClientNode "$2" "$hostnode")
    local scriptpath="$RUNTEMPDIR/cleanupnode_${hostnode}.sh"
    maprutil_buildSingleScript "$scriptpath" "$hostnode"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi
    
    if [ -n "$client" ]; then
         echo "ISCLIENT=1" >> $scriptpath
    else
        echo "ISCLIENT=0" >> $scriptpath
    fi
    #echo "maprutil_checkIsBareMetal" >> $scriptpath
    echo "maprutil_cleanPrevClusterConfig" >> $scriptpath

    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_cleanPrevClusterConfig(){
    # Kill running traces 
    maprutil_killTraces

    # Kill YCSB processes
    maprutil_killYCSB

    #util_kill "mfs"
    #util_kill "java" "jenkins" "QuorumPeerMain"

    # Unmount NFS
    maprutil_unmountNFS

    # Stop warden
    if [[ "$ISCLIENT" -eq 0 ]]; then
        maprutil_restartWarden "stop" 2>/dev/null
        sleep 60
    fi

    # Remove mapr shared memory segments
    util_removeSHMSegments "mapr"

    # kill all processes
    util_kill "initaudit.sh"
    util_kill "pullcentralconfig"
    util_kill "mfs"
    util_kill "java" "jenkins" "QuorumPeerMain"
    util_kill "FsShell"
    util_kill "CentralConfigCopyHelper"
    
    maprutil_killTraces

    rm -rf /opt/mapr/conf/disktab /opt/mapr/conf/mapr-clusters.conf /opt/mapr/logs/* 2>/dev/null

    pushd /opt/mapr/conf/ > /dev/null 2>&1
    rm -rf cldb.key ssl_truststore* ssl_keystore* mapruserticket maprserverticket /tmp/maprticket_* dare.master.key > /dev/null 2>&1
    popd > /dev/null 2>&1
    
     # Remove all directories
    maprutil_removedirs "cores" > /dev/null 2>&1
    maprutil_removedirs "temp" > /dev/null 2>&1

    if [ -e "/opt/mapr/roles/zookeeper" ]; then
        for i in datacenter services services_config servers queryservice drill ; do 
            /opt/mapr/zookeeper/zookeeper-*/bin/zkCli.sh -server localhost:5181 rmr /$i > /dev/null 2>&1
            #su mapr -c '/opt/mapr/zookeeper/zookeeper-*/bin/zkCli.sh -server localhost:5181 rmr /$i' > /dev/null 2>&1
        done
         # Stop zookeeper
        service mapr-zookeeper stop  2>/dev/null
        rm -rf /opt/mapr/zkdata/* > /dev/null 2>&1
        util_kill "java" "jenkins" 
    fi
}

function maprutil_killSpyglass(){
    # Grafana uninstall has a bug (loops in sleep until timeout if warden is not running)
    util_removeBinaries "mapr-opentsdb,mapr-grafana,mapr-elasticsearch,mapr-kibana,mapr-collectd,mapr-fluentd" 2>/dev/null
    
    util_kill "collectd"
    util_kill "fluentd"
    util_kill "grafana"
    util_kill "kibana"
}

function maprutil_uninstall(){
    
    # Kill Spyglass
    maprutil_killSpyglass

    # Kill running traces 
    maprutil_killTraces

    # Kill YCSB processes
    maprutil_killYCSB

    util_kill "mfs"
    util_kill "java" "jenkins"

    # Unmount NFS
    maprutil_unmountNFS

    # Stop warden
    maprutil_restartWarden "stop"

    # Stop zookeeper
    service mapr-zookeeper stop  2>/dev/null

    # Remove MapR Binaries
    maprutil_removemMapRPackages

    # Run Yum clean
    local nodeos=$(getOS $node)
    if [ "$nodeos" = "centos" ]; then
        yum clean all > /dev/null 2>&1
        yum-complete-transaction --cleanup-only > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        apt-get install -f -y > /dev/null 2>&1
        apt-get autoremove -y > /dev/null 2>&1
        apt-get update > /dev/null 2>&1
    elif [ "$nodeos" = "suse" ]; then
        zypper refresh > /dev/null 2>&1
        zypper clean > /dev/null 2>&1
    fi

    # Remove mapr shared memory segments
    util_removeSHMSegments "mapr"

    # Kill running traces 
    maprutil_killTraces

    # kill all processes
    util_kill "initaudit.sh"
    util_kill "mfs"
    util_kill "java" "jenkins"
    util_kill "/opt/mapr"     

    # Remove all directories
    maprutil_removedirs "all"

    echo 1 > /proc/sys/vm/drop_caches

    log_info "[$(util_getHostIP)] Uninstall complete"
}

# @param host ip
function maprutil_uninstallNode(){
    if [ -z "$1" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/uninstallnode_${hostnode}.sh"
    maprutil_buildSingleScript "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_uninstall" >> $scriptpath

    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_upgrade(){
    #local upbins="mapr-cldb mapr-core mapr-core-internal mapr-fileserver mapr-hadoop-core mapr-historyserver mapr-jobtracker mapr-mapreduce1 mapr-mapreduce2 mapr-metrics mapr-nfs mapr-nodemanager mapr-resourcemanager mapr-tasktracker mapr-webserver mapr-zookeeper mapr-zk-internal mapr-drill"
    local hostip=$(util_getHostIP)
    local upbins=$(util_getInstalledBinaries "mapr-")
    upbins=$(echo "$upbins"| sed 's/ /\n/g' | grep -v "patch")
    upbins=$(echo "$upbins" | tr '-' ' ' | tr '_' ' ' | awk '{for(i=1;i<=NF;i++) {if($i ~ /^[[:digit:]]/) break; printf("%s ",$i)} printf("\n")}' | sed 's/ /-/g' | sed 's/-$//g')
    upbins=$(echo $upbins | sed 's/\n/ /g')

    local buildversion=$1
    local starttrace=
    [ -n "$(maprutil_areTracesRunning)" ] && maprutil_killTraces && starttrace=1
    
    local removebins="mapr-patch"
    if [ -n "$(util_getInstalledBinaries $removebins)" ]; then
        util_removeBinaries $removebins
    fi

    util_upgradeBinaries "$upbins" "$buildversion" || exit 1
    
    #mv /opt/mapr/conf/warden.conf  /opt/mapr/conf/warden.conf.old
    #cp /opt/mapr/conf.new/warden.conf /opt/mapr/conf/warden.conf
    if [ -e "/opt/mapr/roles/cldb" ]; then
        log_msghead "Transplant any new changes in warden configs to /opt/mapr/conf/warden.conf. Do so manually!"
        diff /opt/mapr/conf/warden.conf /opt/mapr/conf.new/warden.conf
        if [ -d "/opt/mapr/conf/conf.d.new" ]; then
            log_msghead "New configurations from /opt/mapr/conf/conf.d.new aren't merged with existing files. Do so manually!"
        fi
    fi

    local queryservice=$(echo $(maprutil_getNodesForService "drill") | grep "$hostip")

    local cmd="/opt/mapr/server/configure.sh -R"
    if [ -n "$queryservice" ] && [ -n "$GLB_ENABLE_QS" ] && [ -n "$(maprutil_isMapRVersionSameOrNewer "6.0.0")" ]; then
        cmd=$cmd" -QS"
    fi
    log_info "$cmd"
    bash -c "$cmd"

    # Start zookeeper if if exists
    service mapr-zookeeper start 2>/dev/null
    
    # Restart services on the node
    maprutil_restartWarden "start" > /dev/null 2>&1

    [ -n "$starttrace" ] && maprutil_startTraces
}

# @param host ip
function maprutil_upgradeNode(){
    if [ -z "$1" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/upgradenode_${hostnode}.sh"
    maprutil_buildSingleScript "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    if [ -n "$GLB_BUILD_VERSION" ]; then
        echo "maprutil_setupLocalRepo" >> $scriptpath
    fi
    echo "maprutil_upgrade \""$GLB_BUILD_VERSION"\" || exit 1" >> $scriptpath

    ssh_executeScriptasRootInBG "$hostnode" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$2" ]; then
        maprutil_wait
    fi
}

# @param cldbnode
function maprutil_postUpgrade(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    local isCLDBUp=$(maprutil_waitForCLDBonNode "$node")

    if [ -n "$isCLDBUp" ]; then
        ssh_executeCommandasRoot "$node" "timeout 30 maprcli config save -values {mapr.targetversion:\"\$(cat /opt/mapr/MapRBuildVersion)\"}" > /dev/null 2>&1
        ssh_executeCommandasRoot "$node" "timeout 10 maprcli node list -columns hostname,csvc" 
    else
        log_warn "Timed out waiting for CLDB to come up. Please update 'mapr.targetversion' manually"
    fi
}

# @param host ip
# @param rolefile
function maprutil_rollingUpgradeOnNode(){
    local node="$1"
    local rolefile="$2"
    ## http://doc.mapr.com/display/MapR/Rolling+MapR+Core+Upgrade+Using+Manual+Steps
    
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    ssh_executeCommandasRoot "$node"  "timeout 30 maprcli node maintenance -nodes $host -timeoutminutes 30"
    ssh_executeCommandasRoot "$node"  "timeout 30 maprcli notifyupgrade start -node $host"

    maprutil_restartWardenOnNode "$node" "$rolefile" "stop" 
    maprutil_restartZKOnNode "$node" "$rolefile" "stop"

    maprutil_upgradeNode "$node"

    ssh_executeCommandasRoot "$node"  "timeout 30 maprcli node maintenance -nodes $host -timeoutminutes 0"
    ssh_executeCommandasRoot "$node"  "timeout 30 maprcli notifyupgrade finish –node $host"
}

# @param host ip
# @param binary list
# @param don't wait
function maprutil_installBinariesOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/installbinnode_${hostnode}.sh"
    maprutil_buildSingleScript "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    if [ -n "$GLB_BUILD_VERSION" ]; then
        echo "maprutil_setupLocalRepo" >> $scriptpath
    fi
    echo "keyexists=\$(util_fileExists \"/root/.ssh/id_rsa\")" >> $scriptpath
    echo "[ -z \"\$keyexists\" ] && ssh_createkey \"/root/.ssh\"" >> $scriptpath
    #echo "maprutil_checkIsBareMetal" >> $scriptpath
    echo "util_installprereq > /dev/null 2>&1" >> $scriptpath
    local bins="$2"
    local maprpatch=$(echo "$bins" | tr ' ' '\n' | grep mapr-patch)
    [ -n "$maprpatch" ] && bins=$(echo "$bins" | tr ' ' '\n' | grep -v mapr-patch | tr '\n' ' ')
    
    ## Append MapR release version as there might be conflicts with mapr-patch-client with regex as 'mapr-patch*$VERSION*'
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ]; then
        [ -n "$(echo "$GLB_PATCH_REPOFILE" | grep ubuntu)" ] && GLB_PATCH_REPOFILE=$(echo $GLB_PATCH_REPOFILE | sed 's/ubuntu/redhat/g')
        [ -n "$GLB_PATCH_REPOFILE" ] && echo "maprutil_disableRepoByURL \"$GLB_PATCH_REPOFILE\"" >> $scriptpath
        echo "util_installBinaries \""$bins"\" \""$GLB_BUILD_VERSION"\" \""-$GLB_MAPR_VERSION"\"" >> $scriptpath
        if [ -n "$maprpatch" ]; then
            echo "maprutil_enableRepoByURL \"$GLB_PATCH_REPOFILE\"" >> $scriptpath
            echo "util_installBinaries \""$maprpatch"\" \""$GLB_PATCH_VERSION"\" \""-$GLB_MAPR_VERSION"\" || exit 1" >> $scriptpath
        fi
    else
        [ -n "$(echo "$GLB_PATCH_REPOFILE" | grep redhat)" ] && GLB_PATCH_REPOFILE=$(echo $GLB_PATCH_REPOFILE | sed 's/redhat/ubuntu/g')
        [ -n "$GLB_PATCH_REPOFILE" ] && echo "maprutil_disableRepoByURL \"$GLB_PATCH_REPOFILE\"" >> $scriptpath
        echo "util_installBinaries \""$bins"\" \""$GLB_BUILD_VERSION"\" \""$GLB_MAPR_VERSION"\"" >> $scriptpath
        if [ -n "$maprpatch" ]; then
            echo "maprutil_enableRepoByURL \"$GLB_PATCH_REPOFILE\"" >> $scriptpath
            echo "util_installBinaries \""$maprpatch"\" \""$GLB_PATCH_VERSION"\" \""$GLB_MAPR_VERSION"\" || exit 1" >> $scriptpath
        fi
    fi
    
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$3" ]; then
        maprutil_wait
    fi
}

function maprutil_checkIsBareMetal(){
    local isbm=$(util_isBareMetal)
    if [ -z "$isbm" ]; then
        log_error "[$(util_getHostIP)] Trying to operate on a linux container. NOT SUPPORTED!"
        exit 1    
    fi
}

function maprutil_configureMultiMFS(){
     if [ -z "$1" ]; then
        return
    fi
    local nummfs=$1
    local numspspermfs=1
    local numsps=$2
    if [ -n "$numsps" ]; then
        numspspermfs=$(echo "$numsps/$nummfs"|bc)
    fi
    local failcnt=2;
    local iter=0;
    local iterlimit=5
    while [ "$failcnt" -gt 0 ] && [ "$iter" -lt "$iterlimit" ]; do
        failcnt=0;
        timeout 30 maprcli config load -json > /dev/null 2>&1
        let failcnt=$failcnt+`echo $?`
        [ "$failcnt" -gt "0" ] && sleep 30;
        let iter=$iter+1;
    done
    if [ "$iter" -lt "$iterlimit" ]; then
        local setnummfs=$(maprcli config load -json 2>/dev/null| grep multimfs.numinstances.pernode | tr -d '"' | tr -d ',' | cut -d':' -f2)
        if [ "$setnummfs" -lt "$nummfs" ]; then
            timeout 30 maprcli  config save -values {multimfs.numinstances.pernode:${nummfs}}
            timeout 30 maprcli  config save -values {multimfs.numsps.perinstance:${numspspermfs}}
        fi
    fi
}

function maprutil_configurePontis(){
    if [ ! -e "/opt/mapr/conf/mfs.conf" ]; then
        return
    fi
    sed -i 's|mfs.cache.lru.sizes=|#mfs.cache.lru.sizes=|g' /opt/mapr/conf/mfs.conf
    # Adding Specific Cache Settings
    cat >> /opt/mapr/conf/mfs.conf << EOL
#[PONTIS]
mfs.cache.lru.sizes=inode:3:log:3:dir:3:meta:3:small:5:db:5:valc:1
EOL
}

# @param filename
# @param table namespace 
function maprutil_addTableNS(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local filelist=$(find /opt/mapr/ -name $1 -type f ! -path "*/templates/*")
    local tablens=$2
    for i in $filelist; do
        local present=$(cat $i | grep "hbase.table.namespace.mappings")
        if [ -n "$present" ]; then
            continue;
        fi
        sed -i '/<\/configuration>/d' $i
        cat >> $i << EOL
    <!-- MapRDB -->
    <property>
        <name>hbase.table.namespace.mappings</name>
        <value>*:${tablens}</value>
    </property>
</configuration>
EOL
    done
}

# @param filename
function maprutil_addFSThreads(){
    if [ -z "$1" ]; then
        return
    fi
    local fsthreads=64
    [ -n "$GLB_FS_THREADS" ] && fsthreads=$GLB_FS_THREADS
    local filelist=$(find /opt/mapr/ -name $1 -type f ! -path "*/templates/*")
    for i in $filelist; do
        local present=$(cat $i | grep "fs.mapr.threads")
        if [ -n "$present" ]; then
            continue;
        fi
        sed -i '/<\/configuration>/d' $i
        cat >> $i << EOL
    <!-- MapRDB -->
    <property>
        <name>fs.mapr.threads</name>
        <value>${fsthreads}</value>
    </property>
</configuration>
EOL
    done
}

# @param filename
function maprutil_updateGWThreads(){
    [ ! -e "/opt/mapr/conf/gateway.conf" ] && return
    [ -z "$GLB_GW_THREADS" ] && return
    sed -i "/gateway.receive.numthreads/c\gateway.receive.numthreads=${GLB_GW_THREADS}" /opt/mapr/conf/gateway.conf
}

# @param filename
function maprutil_addTabletLRU(){
    if [ -z "$1" ]; then
        return
    fi
    local filelist=$(find /opt/mapr/ -name $1 -type f ! -path "*/templates/*")
    for i in $filelist; do
        local present=$(cat $i | grep "fs.mapr.tabletlru.size.kb")
        if [ -n "$present" ]; then
            continue;
        fi
        sed -i '/<\/configuration>/d' $i
        cat >> $i << EOL
    <!-- MapRDB Client Tablet Cache Size -->
    <property>
        <name>fs.mapr.tabletlru.size.kb</name>
        <value>2000</value>
    </property>
</configuration>
EOL
    done
}

function maprutil_updateMFSMemory(){
    [ ! -e "/opt/mapr/roles/fileserver" ] && return
    [ -z "$GLB_MFS_MAXMEM" ] && return
    [[ "$(util_isNumber $GLB_MFS_MAXMEM)" = "false" ]] && return
    [[ "$GLB_MFS_MAXMEM" -le "0" ]] && return
    [[ "$GLB_MFS_MAXMEM" -gt "100" ]] && return

    sed -i "/service.command.mfs.heapsize.maxpercent/c\service.command.mfs.heapsize.maxpercent=${GLB_MFS_MAXMEM}" /opt/mapr/conf/warden.conf
    
}

# @param filename
function maprutil_addPutBufferThreshold(){
    if [ -z "$1" ] && [ -z "$2" ]; then
        return
    fi
    local filelist=$(find /opt/mapr/ -name $1 -type f ! -path "*/templates/*")
    local value=$2
    for i in $filelist; do
        local present=$(cat $i | grep "db.mapr.putbuffer.threshold.mb")
        if [ -n "$present" ]; then
            continue;
        fi
        sed -i '/<\/configuration>/d' $i
        cat >> $i << EOL
    <!-- MapRDB Client Put Buffer Threshold Size -->
    <property>
        <name>db.mapr.putbuffer.threshold.mb</name>
        <value>${value}</value>
    </property>
</configuration>
EOL
    done
}

function maprutil_updateConfigs(){

    local execfile="container-executor.cfg"
    local execfilelist=$(find /opt/mapr/hadoop -name $execfile -type f ! -path "*/templates/*")
    for i in $execfilelist; do
        local present=$(cat $i | grep "allowed.system.users" | grep -v root)
        if [ -n "$present" ]; then
            sed -i '/^allowed.system.users/ s/$/,root/' $i
        fi
    done

    # Disable 'fuse.ticketfile.location' in fuse.conf 
    if [ -s "/opt/mapr/conf/fuse.conf" ]; then
        sed -i 's/^fuse.ticketfile.location/#fuse.ticketfile.location/g' /opt/mapr/conf/fuse.conf
    fi
}

function maprutil_configureSSD(){
    local mfsconf="/opt/mapr/conf/mfs.conf"
    [ ! -e "$mfsconf" ] && return

    sed -i '/mfs.disk.is.ssd.*/d' $mfsconf
    sed -i '/mfs.ssd.trim.enabled.*/d' $mfsconf
    echo "mfs.disk.is.ssd=true" >> $mfsconf
    echo "mfs.ssd.trim.enabled=true" >> $mfsconf
}

function maprutil_customConfigure(){

    if [ -n "$GLB_TABLE_NS" ]; then
        maprutil_addTableNS "core-site.xml" "$GLB_TABLE_NS"
        maprutil_addTableNS "hbase-site.xml" "$GLB_TABLE_NS"
    fi

    [ -n "$GLB_PONTIS" ] && maprutil_configurePontis
    

    maprutil_addFSThreads "core-site.xml"
    maprutil_addTabletLRU "core-site.xml"
    [ -n "$GLB_GW_THREADS" ] && maprutil_updateGWThreads
    
    [ -n "$GLB_PUT_BUFFER" ] && maprutil_addPutBufferThreshold "core-site.xml" "$GLB_PUT_BUFFER"

    maprutil_updateMFSMemory

    if [ -e "/opt/mapr/roles/webserver" ]; then
        local maprv=($(cat /opt/mapr/MapRBuildVersion | tr '.' ' ' | awk '{print $1,$2,$3}'))
        local applyfix=
        if [ "${maprv[0]}" -lt "4" ]; then
            applyfix=1
        elif [ "${maprv[0]}" -eq "4" ] && [ "${maprv[1]}" -eq "0" ] && [ "${maprv[2]}" -le "1" ]; then
            applyfix=1
        fi
        
        if [ -n "$applyfix" ]; then
            wget http://package.mapr.com/scripts/mcs/fixssl -O /tmp/fixssl > /dev/null 2>&1
            chmod 755 /tmp/fixssl && /tmp/fixssl > /dev/null 2>&1
        fi
    fi
}

# @param force move CLDB topology
function maprutil_configureCLDBTopology(){
    log_info "[$(util_getHostIP)] Moving $GLB_CLUSTER_SIZE nodes to /data topology"
    local datatopo=$(timeout 30 maprcli node list -columns racktopo -json 2>/dev/null | grep racktopo | grep "/data/" | wc -l)
    local numdnodes=$(timeout 30 maprcli node list  -columns id,service | awk '{if ($2 ~ /fileserver/) print $4}' | wc -l) 
    local j=0
    local downnodes=
    while [ "$numdnodes" -ne "$GLB_CLUSTER_SIZE" ]; do
        numdnodes=$(timeout 30 maprcli node list  -columns id,service | awk '{if ($2 ~ /fileserver/) print $4}' | wc -l) 
        let j=j+1
        if [ "$j" -gt 12 ]; then
            log_warn "[$(util_getHostIP)] Timeout reached waiting for nodes to be online"
            break
        elif [[ "$numdnodes" -ne "$GLB_CLUSTER_SIZE" ]]; then
            downnodes=$(echo "$GLB_CLUSTER_SIZE-$numdnodes" | bc) 
            log_info "[$(util_getHostIP)] Waiting for $downnodes nodes to come online. Sleeping for 10s"
            sleep 10
        fi
    done
    let numdnodes=numdnodes-1

    if [ "$datatopo" -eq "$numdnodes" ]; then
        log_info "[$(util_getHostIP)] All nodes are already on /data topology"
        return
    fi
    ## Move all nodes under /data topology
    local datanodes=$(timeout 30 maprcli node list  -columns id,configuredservice,racktopo -json 2>/dev/null | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | tr "\n" ",")
    timeout 30 maprcli node move -serverids "$datanodes" -topology /data 2>/dev/null
    
    ## Move CLDB if only forced or # of nodes > 5
    if [ "$GLB_CLUSTER_SIZE" -gt 5 ] || [ -n "$1" ]; then
        ### Moving CLDB Nodes to CLDB topology
        #local cldbnode=`maprcli node cldbmaster | grep ServerID | awk {'print $2'}`
        local cldbnodes=$(timeout 30 maprcli node list -columns id,configuredservice,racktopo -json 2>/dev/null | grep -e configuredservice -e id | grep -B1 cldb | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | tr "\n" "," | sed 's/\,$//')
        local numcldbs=$(echo "$cldbnodes" | tr ',' '\n' | wc -l)
        [[ -z "$1" ]] && [[ "$numcldbs" -gt "1" ]] && log_info "[$(util_getHostIP)] Multiple CLDBs found; Not moving them to /cldb topology" && return
        log_info "[$(util_getHostIP)] Moving CLDB node(s) & cldb internal volume to /cldb topology"
        timeout 30 maprcli node move -serverids "$cldbnodes" -topology /cldb 2>/dev/null
        ### Moving CLDB Volume as well
        timeout 30 maprcli volume move -name mapr.cldb.internal -topology /cldb 2>/dev/null
    fi
}

function maprutil_moveTSDBVolumeToCLDBTopology(){
    [ -n "$(timeout 30 maprcli volume info -name mapr.monitoring -json 2>/dev/null | grep rackpath | grep cldb)" ] && return
    local tsdbexists=$(timeout 30 maprcli volume info -name mapr.monitoring -json 2>/dev/null| grep ERROR)
    local cldbtopo=$(timeout 30 maprcli node topo -path /cldb 2>/dev/null)
    if [ -n "$tsdbexists" ] || [ -z "$cldbtopo" ]; then
        log_warn "OpenTSDB not installed or CLDB not moved to /cldb topology"
        return
    fi

    #maprcli volume modify -name mapr.monitoring -minreplication 1 2>/dev/null
    #maprcli volume modify -name mapr.monitoring -replication 1 2>/dev/null
    timeout 30 maprcli volume move -name mapr.monitoring -topology /cldb 2>/dev/null
    timeout 30 maprcli volume move -name mapr.monitoring.metricstreams -topology /cldb 2>/dev/null
}

# @param diskfile
# @param disk limit
function maprutil_buildDiskList() {
    if [ -z "$1" ]; then
        return
    fi
    local diskfile=$1
    local ignorefile=$2
    echo "$(util_getRawDisks $GLB_DISK_TYPE)" > $diskfile
    maprutil_getSSDvsHDDRatio "$(cat $diskfile)"
    local diskratio=$?
    [[ -z "$GLB_DISK_TYPE" ]] && [[ "$diskratio" -eq "1" ]] && echo "$(util_getRawDisks "ssd")" > $diskfile
    [[ -z "$GLB_DISK_TYPE" ]] && [[ "$diskratio" -eq "0" ]] && echo "$(util_getRawDisks "hdd")" > $diskfile
    if [ -s "$ignorefile" ]; then
        local baddisks=$(cat $ignorefile | sed 's/,/ /g' | tr -s " " | tr ' ' '\n')
        local gooddisks=$(cat $diskfile | grep -v "$baddisks")
        log_warn "[$(util_getHostIP)] Excluding disks [$(echo $baddisks | sed ':a;N;$!ba;s/\n/,/g')] "
        echo "$gooddisks" > $diskfile
    fi

    local limit=$GLB_MAX_DISKS
    local numdisks=$(wc -l $diskfile | cut -f1 -d' ')
    if [ -n "$limit" ] && [ "$numdisks" -gt "$limit" ]; then
         local newlist=$(head -n $limit $diskfile)
         echo "$newlist" > $diskfile
    fi
}

function maprutil_isSSDOnlyInstall(){
    [ -z "$1" ] && return

    local disks="$1"
    local hasHDD=
    for disk in $disks
    do
        local isSSD=$(util_isSSDDrive "$disk")
        if [ -z "$isSSD" ] || [ "$isSSD" = "no" ]; then
            hasHDD=1
            break
        fi
    done
    [ -z "$hasHDD" ] && echo "yes"
}

function maprutil_getSSDvsHDDRatio(){
    [ -z "$1" ] && return

    local disks="$1"
    local hasHDD=
    local numssd=0
    local numhdd=0
    for disk in $disks
    do
        local isSSD=$(util_isSSDDrive "$disk")
        if [ -z "$isSSD" ] || [ "$isSSD" = "no" ]; then
            let numhdd=numhdd+1
        else
            let numssd=numssd+1
        fi
    done
    [[ "$numhdd" -eq 0 ]] && [[ "$numssd" -eq 0 ]] && return -1
    [[ "$numhdd" -eq 0 ]] && return 1
    [[ "$numssd" -eq 0 ]] && return 0
    [[ "$(echo "$numssd/$numhdd" | bc)" -ge "2" ]] && return 1
    
    return 0
} 


function maprutil_startTraces() {
    maprutil_killTraces
    if [[ "$ISCLIENT" -eq "0" ]] && [[ -e "/opt/mapr/roles" ]]; then
        nohup bash -c 'log="/opt/mapr/logs/guts.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=$(pidof mfs); if kill -0 ${mfspid} 2>/dev/null; then timeout 70 stdbuf -o0 /opt/mapr/bin/guts time:all flush:line cache:all streams:all db:all rpc:all log:all dbrepl:all io:all >> $log; rc=$?; [[ "$rc" -eq "1" ]] || [[ "$rc" -eq "134" ]] && sleep 5; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done'  > /dev/null 2>&1 &
        nohup bash -c 'log="/opt/mapr/logs/dstat.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do timeout 14 dstat -tcdnim >> $log; rc=$?; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup bash -c 'log="/opt/mapr/logs/iostat.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do timeout 14 iostat -dmxt 1 >> $log 2> /dev/null; rc=$?; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        local nodeos=$(getOS)
        if [ -z "$(maprutil_isMapRVersionSameOrNewer "6.0.0")" ]; then
        #if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ]; then
            nohup bash -c 'log="/opt/mapr/logs/mfstop.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=$(pidof mfs); if [ -n "$mfspid" ]; then date "+%Y-%m-%d %H:%M:%S" >> $log; timeout 10 top -bH -p $mfspid -d 1 >> $log; rc=$?; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        #elif [ "$nodeos" = "ubuntu" ]; then
        else
            nohup bash -c 'log="/opt/mapr/logs/tguts.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=$(cat /opt/mapr/pid/mfs.pid 2>/dev/null); if kill -0 ${mfspid} 2>/dev/null; then timeout 70 stdbuf -o0 /opt/mapr/bin/guts time:all cpu:none db:none fs:none rpc:none cache:none threadcpu:all >> $log; rc=$?; [[ "$rc" -eq "1" ]] || [[ "$rc" -eq "134" ]] && sleep 5; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done'  > /dev/null 2>&1 &
        fi
        nohup bash -c 'log="/opt/mapr/logs/gatewayguts.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/gateway" ]]; do gwpid=$(cat /opt/mapr/pid/gateway.pid 2>/dev/null); if kill -0 ${gwpid} 2>/dev/null; then timeout 70 stdbuf -o0 /opt/mapr/bin/guts clientpid:$gwpid time:all gateway:all >> $log; rc=$?; [ "$rc" -eq "1" ] && [ -z "$(grep Printing $log)" ] && truncate -s 0 $log && sleep 5; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done'  > /dev/null 2>&1 &
        nohup bash -c 'log="/opt/mapr/logs/gatewaytop.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/gateway" ]]; do gwpid=$(cat /opt/mapr/pid/gateway.pid 2>/dev/null); if kill -0 ${gwpid} 2>/dev/null; then date "+%Y-%m-%d %H:%M:%S" >> $log; timeout 10 top -bH -p $gwpid -d 1 >> $log; rc=$?; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
    fi
    maprutil_startResourceTraces
    maprutil_startClientResourceTraces
}

function maprutil_startInstanceGuts(){
    local numinst="$1"
    [ -z "$numinst" ] && numinst="$(/opt/mapr/server/mrconfig info instances 2>/dev/null | head -1 )"
    [ -z "$numinst" ] && return
    [[ -n "$numinst" ]] && [[ "$numinst" -le "1" ]] && return
    for (( i=0; i<$numinst; i++ ))
    do
        [ -n "$(ps -ef | grep "[g]uts_inst$i.log")" ] && continue
        var=$i nohup bash -c 'id=$var; log="/opt/mapr/logs/guts_inst$id.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=`pidof mfs`; if [ -n "$mfspid" ]; then timeout 70 stdbuf -o0 /opt/mapr/bin/guts instance:$id time:all flush:line cache:all streams:all db:all rpc:all log:all dbrepl:all io:all >> $log; rc=$?; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done'  > /dev/null 2>&1 &
    done
}

function maprutil_startResourceTraces() {
    if [[ "$ISCLIENT" -eq "0" ]] && [[ -e "/opt/mapr/roles" ]]; then
        nohup bash -c 'log="/opt/mapr/logs/mfsresusage.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=$(pidof mfs); if kill -0 ${mfspid} 2>/dev/null; then st=$(date +%s%N | cut -b1-13); curtime=$(date "+%Y-%m-%d %H:%M:%S"); topline=$(top -bn 1 -p $mfspid | grep -v "^$" | tail -1 | grep -v "USER" | awk '"'"'{ printf("%s\t%s\t%s\n",$6,$9,$10); }'"'"'); rc=$?; [ -n "$topline" ] && echo -e "$curtime\t$topline" >> $log; et=$(date +%s%N | cut -b1-13); td=$(echo "scale=2;1-(($et-$st)/1000)"| bc); sleep $td; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup bash -c 'log="/opt/mapr/logs/gwresusage.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/gateway" ]]; do gwpid=$(cat /opt/mapr/pid/gateway.pid 2>/dev/null); if kill -0 ${gwpid} 2>/dev/null; then st=$(date +%s%N | cut -b1-13); curtime=$(date "+%Y-%m-%d %H:%M:%S"); topline=$(top -bn 1 -p $gwpid | grep -v "^$" | tail -1 | grep -v "USER" | awk '"'"'{ printf("%s\t%s\t%s\n",$6,$9,$10); }'"'"'); rc=$?; [ -n "$topline" ] && echo -e "$curtime\t$topline" >> $log; et=$(date +%s%N | cut -b1-13); td=$(echo "scale=2;1-(($et-$st)/1000)"| bc); sleep $td; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup bash -c 'log="/opt/mapr/logs/drillresusage.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/drill" ]]; do qspid=$(cat /opt/mapr/pid/drillbit.pid 2>/dev/null); if kill -0 ${qspid} 2>/dev/null; then st=$(date +%s%N | cut -b1-13); curtime=$(date "+%Y-%m-%d %H:%M:%S"); topline=$(top -bn 1 -p $qspid | grep -v "^$" | tail -1 | grep -v "USER" | awk '"'"'{ printf("%s\t%s\t%s\n",$6,$9,$10); }'"'"'); rc=$?; [ -n "$topline" ] && echo -e "$curtime\t$topline" >> $log; et=$(date +%s%N | cut -b1-13); td=$(echo "scale=2;1-(($et-$st)/1000)"| bc); sleep $td; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup bash -c 'log="/opt/mapr/logs/dagresusage.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/data-access-gateway" ]]; do dagpid=$(cat /opt/mapr/pid/data-access-gateway.pid 2>/dev/null); if kill -0 ${dagpid} 2>/dev/null; then st=$(date +%s%N | cut -b1-13); curtime=$(date "+%Y-%m-%d %H:%M:%S"); topline=$(top -bn 1 -p $dagpid | grep -v "^$" | tail -1 | grep -v "USER" | awk '"'"'{ printf("%s\t%s\t%s\n",$6,$9,$10); }'"'"'); rc=$?; [ -n "$topline" ] && echo -e "$curtime\t$topline" >> $log; et=$(date +%s%N | cut -b1-13); td=$(echo "scale=2;1-(($et-$st)/1000)"| bc); sleep $td; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup bash -c 'log="/opt/mapr/logs/tsdbresusage.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/opentsdb" ]]; do tsdpid=$(cat /opt/mapr/pid/opentsdb.pid 2>/dev/null); if kill -0 ${tsdpid} 2>/dev/null; then st=$(date +%s%N | cut -b1-13); curtime=$(date "+%Y-%m-%d %H:%M:%S"); topline=$(top -bn 1 -p $tsdpid | grep -v "^$" | tail -1 | grep -v "USER" | awk '"'"'{ printf("%s\t%s\t%s\n",$6,$9,$10); }'"'"'); rc=$?; [ -n "$topline" ] && echo -e "$curtime\t$topline" >> $log; et=$(date +%s%N | cut -b1-13); td=$(echo "scale=2;1-(($et-$st)/1000)"| bc); sleep $td; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "1258291200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
    fi
}

function maprutil_startClientResourceTraces(){
    local tracescript="/tmp/clienttrace.sh"
    rm -rf $tracescript > /dev/null 2>&1
    cat >> $tracescript << EOL
#!/bin/sh
function startClientTrace(){
    local cpids="\$1"
    for cpid in \$cpids
    do
        nohup bash -c 'cpid=\$0; log="/opt/mapr/logs/clientresusage_\$cpid.log"; sleep 2; [ -e "/proc/\$cpid/cmdline" ] && tr -cd "\11\12\15\40-\176" < /proc/\$cpid/cmdline > \$log && echo >> \$log; while kill -0 \${cpid} 2>/dev/null; do st=\$(date +%s%N | cut -b1-13); curtime=\$(date "+%Y-%m-%d %H:%M:%S"); topline=\$(top -bn 1 -p \$cpid | grep -v "^$" | tail -1 | grep -v "USER" | awk '"'"'{ printf("%s\t%s\t%s\n",\$6,\$9,\$10); }'"'"'); [ -n "\$topline" ] && echo -e "\$curtime\t\$topline" >> \$log; et=\$(date +%s%N | cut -b1-13); td=\$(echo "scale=2;1-((\$et-\$st)/1000)"| bc); sleep \$td; sz=\$(stat -c %s \$log); [ "\$sz" -gt "209715200" ] && tail -c 1048576 \$log > \$log.bkp && rm -rf \$log && mv \$log.bkp \$log; done' \$cpid > /dev/null 2>&1 &
    done
}

sleeptime=2
while [[ -d "/opt/mapr/" ]];
do
        shmids="\$(ipcs -m | grep '^0x'  | grep 1234 | awk '{print \$2}')"
        [ -z "\$shmids" ] && sleep \$sleeptime && continue
        clientpids=\$(echo "\$(ipcs -mp)" | grep -Fw "\$shmids" | awk '{print \$3}' | sort | uniq | tr '\n' ' ')
        actualcpids=
        for cpid in \$clientpids
        do
                ppid=\$(ps -ef | grep -w \$cpid | awk -v p="\$cpid" '{if(\$2==p) print \$3}')
                crpid=\$(ps -ef | grep "[c]lientresusage" | grep -w "\$cpid")
                [[ "\$ppid" -eq "1" ]] && [ -n "\$crpid" ] && kill -9 \$crpid > /dev/null 2>&1
                [[ "\$ppid" -eq "1" ]] && continue
                [ -n "\$crpid" ] && continue
                fspid=\$(ps -ef | grep "[j]ava" | grep "[o]rg.apache.hadoop.fs.FsShell" | grep -w "\$cpid")
                [ -n "\$fspid" ] && continue
                actualcpids="\${actualcpids}\${cpid} "
        done
        [ -n "\$actualcpids" ] && startClientTrace "\$actualcpids"
        sleep \$sleeptime
done
EOL
    chmod +x $tracescript > /dev/null 2>&1
    nohup bash -c '/tmp/clienttrace.sh' > /dev/null 2>&1 &
}

function maprutil_areTracesRunning(){
    [[ -n "$(ps -ef | grep "[l]og=\"/opt")" ]] && echo "true"
}

function maprutil_killTraces() {
    util_kill "timeout"
    util_kill "guts"
    util_kill "dstat"
    util_kill "iostat"
    util_kill "top -b"
    util_kill "sh -c log"
    util_kill "bash -c log"
    util_kill "runTraces"
    util_kill "clientresusage_"
    util_kill "clienttrace.sh"
}

function maprutil_killYCSB() {
    util_kill "ycsb-driver"
    util_kill "/var/ycsb/"
    util_kill "/tmp/ycsb"
}

function maprutil_configureSSH(){
    if [ -z "$1" ]; then
        return
    fi
    local nodes="$1"
    local hostip=$(util_getHostIP)

    if [ -n $(ssh_checkSSHonNodes "$nodes") ]; then
        for node in ${nodes[@]}
        do
            local isEnabled=$(ssh_check "root" "$node")
            if [ "$isEnabled" != "enabled" ]; then
                log_info "Configuring key-based authentication from $hostip to $node "
                ssh_copyPublicKey "root" "$node"
            fi
        done
    fi
    local nodehn=
    for node in ${nodes[@]}
    do
        local hostname=$(ssh $node "\$(hostname -f)")
        nodehn="$nodehn $hostname"
    done

    if [ -n $(ssh_checkSSHonNodes "$nodehn") ]; then
        for node in ${nodehn[@]}
        do
            local isEnabled=$(ssh_check "root" "$node")
            if [ "$isEnabled" != "enabled" ]; then
                log_info "Configuring key-based authentication from $hostip to $node "
                ssh_copyPublicKey "root" "$node"
            fi
        done
    fi

}

function maprutil_configure(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi

    # SSH session exits after running for few seconds with error "Write failed: Broken pipe"
    #util_restartSSHD

    if [ ! -d "/opt/mapr/" ]; then
        log_warn "Configuration skipped as no MapR binaries are installed "
        return 1
    fi
    
    local diskfile="/tmp/disklist"
    local hostip=$(util_getHostIP)
    local cldbnodes=$(util_getCommaSeparated "$1")
    local cldbnode=$(util_getFirstElement "$1")
    local zknodes=$(util_getCommaSeparated "$2")
    local hsnodes=$(maprutil_getNodesForService "historyserver")
    local rmnodes=$(maprutil_getNodesForService "resourcemanager")
    local ignoredisks=/root/baddisks
    maprutil_buildDiskList "$diskfile" "$ignoredisks"

    local disklist="$(cat $diskfile)"
    [ -n "$(maprutil_isSSDOnlyInstall "$disklist")" ] && maprutil_configureSSD

    if [ "$hostip" != "$cldbnode" ] && [ "$(ssh_check root $cldbnode)" != "enabled" ]; then
        ssh_copyPublicKey "root" "$cldbnode"
    fi

    local extops=
    if [ -n "$GLB_SECURE_CLUSTER" ]; then
        extops="-secure"
        pushd /opt/mapr/conf/ > /dev/null 2>&1
        rm -rf cldb.key ssl_truststore* ssl_keystore* mapruserticket maprserverticket /tmp/maprticket_* dare.master.key > /dev/null 2>&1
        popd > /dev/null 2>&1
        if [ "$hostip" = "$cldbnode" ]; then
            extops=$extops" -genkeys"
        else
            maprutil_copySecureFilesFromCLDB "$cldbnode" "$cldbnodes" "$zknodes"
        fi
        [ -n "$GLB_ENABLE_DARE" ] && extops="$extops -dare"
    fi

    local configurecmd="/opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3"
    [ -n "$extops" ] && configurecmd="$configurecmd $extops"

    if [ "$ISCLIENT" -eq 1 ]; then
        configurecmd="$configurecmd -c"
    else
    #   [ -n "$rmnodes" ] && configurecmd="$configurecmd -RM $(util_getCommaSeparated "$rmnodes")"
       [ -n "$hsnodes" ] && configurecmd="$configurecmd -HS $(util_getFirstElement "$hsnodes")"
    fi

    # Run configure.sh on the node
    log_info "[$hostip] $configurecmd"
    bash -c "$configurecmd"
    
    # Perform series of custom configuration based on selected options
    maprutil_customConfigure

    # Return if configuring client node after this
    if [ "$ISCLIENT" -eq 1 ]; then
        [ -n "$GLB_SECURE_CLUSTER" ] &&  maprutil_copyMapRTicketsFromCLDB "$cldbnode"
        [ -n "$GLB_TRACE_ON" ] && maprutil_startTraces
        log_info "[$hostip] Done configuring client node"
        return 
    fi

    [ -n "$GLB_TRIM_SSD" ] && log_info "[$hostip] Trimming the SSD disks if present..." && util_trimSSDDrives "$(cat $diskfile)"
    
    #echo "/opt/mapr/server/disksetup -FM /tmp/disklist"
    local multimfs=$GLB_MULTI_MFS
    local numsps=$GLB_NUM_SP
    local numdisks=`wc -l $diskfile | cut -f1 -d' '`
    local dspid=
    if [ -n "$multimfs" ] && [ "$multimfs" -gt 1 ]; then
        if [ "$multimfs" -gt "$numdisks" ]; then
            log_info "Node ["`hostname -s`"] has fewer disks than mfs instances. Defaulting # of mfs to # of disks"
            multimfs=$numdisks
        fi
        
        local numstripe=$(echo $numdisks/$multimfs|bc)
        if [ -n "$numsps" ] && [ "$numsps" -le "$numdisks" ]; then
            [ $((numdisks%2)) -eq 1 ] && [ $((numsps%2)) -eq 0 ] && numdisks=$(echo "$numdisks+1" | bc)
            numstripe=$(echo "$numdisks/$numsps"|bc)
        else
            numsps=
        fi
        # SSH session exits after running for few seconds with error "Write failed: Broken pipe"; Running in background and waiting
        /opt/mapr/server/disksetup -FW $numstripe $diskfile &
        dspid=$!
    elif [[ -n "$numsps" ]] &&  [[ "$numsps" -le "$numdisks" ]]; then
        [ $((numdisks%2)) -eq 1 ] && numdisks=$(echo "$numdisks+1" | bc)
        local numstripe=$(echo "$numdisks/$numsps"|bc)
        if [[ "$(echo "$numstripe*$numsps" | bc)" -lt "$numdisks" ]]; then
            numstripe=$(echo "$numstripe+1" | bc)
        fi
        /opt/mapr/server/disksetup -FW $numstripe $diskfile &
        dspid=$!
    else
        /opt/mapr/server/disksetup -FM $diskfile &
        dspid=$!
    fi
    while kill -0 ${dspid} 2>/dev/null; do echo -ne "."; sleep 1; done
    echo
    wait

    # Add root user to container-executor.cfg
    maprutil_updateConfigs

    # Start zookeeper
    service mapr-zookeeper restart 2>/dev/null
    
    # Restart services on the node
    maprutil_restartWarden > /dev/null 2>&1

    # Restart posix-client
    service mapr-posix-client-basic restart > /dev/null 2>&1
    service mapr-posix-client-platinum restart > /dev/null 2>&1

    # Mount self-hosting on all nodes
    maprutil_mountSelfHosting

   if [ "$hostip" = "$cldbnode" ]; then
        maprutil_applyLicense
        if [ -n "$multimfs" ] && [ "$multimfs" -gt 0 ]; then
            maprutil_configureMultiMFS "$multimfs" "$numsps"
        fi
        if [ -n "$GLB_CLDB_TOPO" ]; then
            maprutil_configureCLDBTopology || exit 1
        fi
        [ -n "$GLB_ENABLE_AUDIT" ] && maprutil_enableClusterAudit
        [ -n "$GWNODES" ] && maprutil_setGatewayNodes "$3" "$GWNODES"
    else
        [ -n "$GLB_SECURE_CLUSTER" ] &&  maprutil_copyMapRTicketsFromCLDB "$cldbnode"
        [ ! -f "/opt/mapr/bin/guts" ] && maprutil_copyGutsFromCLDB
        if [ -n "$multimfs" ] && [ "$multimfs" -gt 0 ]; then
            maprutil_configureMultiMFS "$multimfs" "$numsps"
        fi
    fi

    if [ -n "$GLB_TRACE_ON" ]; then
        maprutil_startTraces
    fi

    log_info "[$(util_getHostIP)] Node configuration complete"
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
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/configurenode_${hostnode}.sh"
    maprutil_buildSingleScript "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local hostip=$(util_getHostIP)
    local allnodes=$(maprutil_getNodesFromRole "$2")
    local cldbnodes=$(maprutil_getCLDBNodes "$2")
    local cldbnode=$(util_getFirstElement "$cldbnodes")
    local zknodes=$(maprutil_getZKNodes "$2")
    local client=$(maprutil_isClientNode "$2" "$hostnode")
    local gwnodes=$(maprutil_getGatewayNodes "$2")
    
    if [ -n "$client" ]; then
         echo "ISCLIENT=1" >> $scriptpath
    else
        echo "ISCLIENT=0" >> $scriptpath
        echo "GWNODES=\"$gwnodes\"" >> $scriptpath
    fi
    
    if [ "$hostip" != "$cldbnode" ] && [ "$hostnode" = "$cldbnode" ]; then
        echo "maprutil_configureSSH \""$allnodes"\" && maprutil_configure \""$cldbnodes"\" \""$zknodes"\" \""$3"\" || exit 1" >> $scriptpath
    else
        echo "maprutil_configure \""$cldbnodes"\" \""$zknodes"\" \""$3"\" || exit 1" >> $scriptpath
    fi
   
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$4" ]; then
        maprutil_wait
    fi
}

function maprutil_postConfigure(){
    local hostip=$(util_getHostIP)

    local esnodes="$(maprutil_getNodesForService "elastic")"
    local otnodes="$(maprutil_getNodesForService "opentsdb")"
    [ -n "$esnodes" ] && esnodes="$(util_getCommaSeparated "$esnodes")"
    [ -n "$otnodes" ] && otnodes="$(util_getCommaSeparated "$otnodes")"
    local queryservice=$(echo $(maprutil_getNodesForService "drill") | grep "$hostip")

    local cmd="/opt/mapr/server/configure.sh -R"
    if [ -n "$esnodes" ]; then
        cmd=$cmd" -ES "$esnodes
    fi
    if [ -n "$otnodes" ]; then
        cmd=$cmd" -OT "$otnodes
    fi
    if [ -n "$queryservice" ] && [ -n "$GLB_ENABLE_QS" ] && [ -n "$(maprutil_isMapRVersionSameOrNewer "6.0.0")" ]; then
        cmd=$cmd" -QS"
    fi
    log_info "$cmd"
    bash -c "$cmd"
    
    [ -n "$otnodes" ] || [ -n "$esnodes" ] && sleep 30
    [ -n "$otnodes" ] && /opt/mapr/collectd/collectd-*/etc/init.d/collectd restart > /dev/null 2>&1 
    [ -n "$esnodes" ] && /opt/mapr/fluentd/fluentd-*/etc/init.d/fluentd restart > /dev/null 2>&1
    [ -n "$otnodes" ] || [ -n "$esnodes" ] && sleep 30

    #if [ -n "$otnodes" ] || [ -n "$esnodes" ]; then
    #    sed -i '/service.command.mfs.heapsize.percent.*/d' /opt/mapr/conf/warden.conf
    #    echo "service.command.mfs.heapsize.percent=85" >> /opt/mapr/conf/warden.conf
    #fi
    #maprutil_restartWarden
}

function maprutil_queryservice(){
    local drillname="${GLB_CLUSTER_NAME}-drillbits"
    timeout 30 maprcli cluster queryservice setconfig -enabled true -clusterid ${drillname} -storageplugin dfs -znode /drill > /dev/null 2>&1
}

# @param cldbnode ip
function maprutil_copyGutsFromCLDB(){
    if [ -z "$1" ] || [ ! -d "/opt/mapr/bin" ]; then
        return
    fi
    local cldbhost=$1
    local gutsexists="false"
    local i=0
    while [ "$gutsexists" = "false" ]; do
        gutsexists=$(ssh_executeCommandasRoot "$cldbhost" "[ -e '/opt/mapr/bin/guts' ] && echo true || echo false")
        if [ "$gutsexists" = "false" ]; then
            sleep 10
        else
            gutsexists="true"
            sleep 1
        fi
        let i=i+1
        if [ "$i" -gt 18 ]; then
            log_warn "[$(util_getHostIP)] Failed to copy guts from CLDB node"
            break
        fi
    done
    if [ "$gutsexists" = "true" ]; then
        ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/bin/guts" "/opt/mapr/bin/" 2>/dev/null
    fi
}

# @param cldbnode ip
function maprutil_copyMapRTicketsFromCLDB(){
    if [ -z "$1" ]; then
        return
    fi
    local cldbhost=$1
    
    # Check if CLDB is configured & files are available for copy
    local cldbisup="false"
    local i=0
    while [ "$cldbisup" = "false" ]; do
        cldbisup=$(ssh_executeCommandasRoot "$cldbhost" "[ -e '/tmp/maprticket_0' ] && echo true || echo false")
        if [ "$cldbisup" = "false" ]; then
            sleep 10
        else
            cldbisup="true"
            sleep 10
            break
        fi
        let i=i+1
        if [ "$i" -gt 18 ]; then
            log_warn "[$(util_getHostIP)] Timed out waiting to find 'maprticket_0' on CLDB node [$cldbhost]. Copy manually!"
            break
        fi
    done
    
    if [ "$cldbisup" = "true" ]; then
        ssh_copyFromCommand "root" "$cldbhost" "/tmp/maprticket_*" "/tmp" 2>/dev/null
    fi
}

# @param cldbnode ip
function maprutil_copySecureFilesFromCLDB(){
    local cldbhost=$1
    local cldbnodes=$2
    local zknodes=$3
    
    # Check if CLDB is configured & files are available for copy
    local cldbisup="false"
    local i=0
    while [ "$cldbisup" = "false" ]; do
        cldbisup=$(ssh_executeCommandasRoot "$cldbhost" "[ -e '/opt/mapr/conf/cldb.key' ] && [ -e '/opt/mapr/conf/maprserverticket' ] && [ -e '/opt/mapr/conf/ssl_keystore' ] && [ -e '/opt/mapr/conf/ssl_truststore' ] && echo true || echo false")
        if [ "$cldbisup" = "false" ]; then
            sleep 10
        else
            break
        fi
        let i=i+1
        if [ "$i" -gt 18 ]; then
            log_warn "[$(util_getHostIP)] Timed out waiting to find cldb.key on CLDB node [$cldbhost]. Exiting!"
            exit 1
        fi
    done
    
    sleep 10

    if [[ -n "$(echo $cldbnodes | grep $hostip)" ]] || [[ -n "$(echo $zknodes | grep $hostip)" ]]; then
        ssh_copyFromCommand "root" "$cldbhost" "/opt/mapr/conf/cldb.key" "/opt/mapr/conf/";
    fi
    [ -n "$GLB_ENABLE_DARE" ] && ssh_copyFromCommand "root" "$cldbhost" "/opt/mapr/conf/dare.master.key" "/opt/mapr/conf/";
     
    #if [ "$ISCLIENT" -eq 0 ]; then
        ssh_copyFromCommand "root" "$cldbhost" "/opt/mapr/conf/ssl_keystore*" "/opt/mapr/conf/"; 
        ssh_copyFromCommand "root" "$cldbhost" "/opt/mapr/conf/maprserverticket" "/opt/mapr/conf/"; 
    #fi
    ssh_copyFromCommand "root" "$cldbhost" "/opt/mapr/conf/ssl_truststore*" "/opt/mapr/conf/"; 
    
    #if [ "$ISCLIENT" -eq 0 ]; then
        chown mapr:mapr /opt/mapr/conf/maprserverticket > /dev/null 2>&1
        chmod +600 /opt/mapr/conf/maprserverticket /opt/mapr/conf/ssl_keystore* > /dev/null 2>&1
    #fi
    chmod +444 /opt/mapr/conf/ssl_truststore* > /dev/null 2>&1
}
# @param host ip
# @param config file path
# @param cluster name
# @param don't wait
function maprutil_postConfigureOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
     # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/postconfigurenode_${hostnode}.sh"
    maprutil_buildSingleScript "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_postConfigure || exit 1" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$hostnode" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$2" ]; then
        maprutil_wait
    fi
}

# @param script path
function maprutil_addGlobalVars(){
    if [ -z "$1" ]; then
        return
    fi
    local scriptpath=$1
    local OIFS=$IFS; IFS=$(echo -en "\n\b");
    for i in $( set -o posix ; set  | grep GLB_)
    do
        #echo "%%%%%%%%%% -> $i <- %%%%%%%%%%%%%"
        if [[ "$i" =~ ^GLB_BG_PIDS.* ]]; then
            continue
        elif [[ ! "$i" =~ ^GLB_.* ]]; then
            continue
        fi
        echo "$i" >> $scriptpath
    done
    IFS=$OIFS
}

function maprutil_getBuildID(){
    local buildid=$(cat /opt/mapr/MapRBuildVersion)
    echo "$buildid"
}

# @param node
# @param build id
function maprutil_checkBuildExists(){
     if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local node=$1
    local buildid=$2
    local retval=
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        retval=$(ssh_executeCommandasRoot "$node" "yum --showduplicates list mapr-core | grep $buildid")
    elif [ "$nodeos" = "ubuntu" ]; then
        retval=$(ssh_executeCommandasRoot "$node" "apt-get update >/dev/null 2>&1 && apt-cache policy mapr-core | grep $buildid")
    elif [ "$nodeos" = "suse" ]; then
        retval=$(ssh_executeCommandasRoot "$node" "zypper search -s mapr-core | grep $buildid")
    fi
    echo "$retval"
}

# @param node
function maprutil_checkNewBuildExists(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    local buildid=$(maprutil_getMapRVersionOnNode $node)
    local curchangeset=$(echo $buildid | cut -d'.' -f4)
    local newchangeset=
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        #ssh_executeCommandasRoot "$node" "yum clean all" > /dev/null 2>&1
        newchangeset=$(ssh_executeCommandasRoot "$node" "yum clean all > /dev/null 2>&1; yum --showduplicates list mapr-core | grep -v '$curchangeset' | awk '{if(match(\$2,/[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.[a-zA-Z]*/)) print \$0}' | tail -n1 | awk '{print \$2}' | cut -d'.' -f4")
    elif [ "$nodeos" = "ubuntu" ]; then
        newchangeset=$(ssh_executeCommandasRoot "$node" "apt-get update > /dev/null 2>&1; apt-cache policy mapr-core | grep Candidate | grep -v '$curchangeset' | awk '{print \$2}' | cut -d'.' -f4")
    elif [ "$nodeos" = "suse" ]; then
        newchangeset=$(ssh_executeCommandasRoot "$node" "zypper refresh > /dev/null 2>&1; zypper search -s mapr-core | grep -v '$curchangeset' | awk '{if(match(\$7,/[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.[a-zA-Z]*/)) print \$0}' | tail -n1 | awk '{print \$7}' | cut -d'.' -f4")
    fi

    if [[ -n "$newchangeset" ]] && [[ "$(util_isNumber $newchangeset)" = "true" ]] && [[ "$newchangeset" -gt "$curchangeset" ]]; then
        echo "$newchangeset"
    fi
}

function maprutil_getMapRVersionFromRepo(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    local nodeos=$(getOSFromNode $node)
    local maprversion=
    if [ "$nodeos" = "centos" ]; then
        #ssh_executeCommandasRoot "$node" "yum clean all" > /dev/null 2>&1
        maprversion=$(ssh_executeCommandasRoot "$node" "yum --showduplicates list mapr-core 2> /dev/null | grep mapr-core | awk '{if(match(\$2,/[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.[a-zA-Z]*/)) print \$0}' | tail -n1 | awk '{print \$2}' | cut -d'.' -f1-3")
    elif [ "$nodeos" = "ubuntu" ]; then
        maprversion=$(ssh_executeCommandasRoot "$node" "apt-cache policy mapr-core 2> /dev/null | grep Candidate | awk '{print \$2}' | cut -d'.' -f1-3")
    elif [ "$nodeos" = "suse" ]; then
        maprversion=$(ssh_executeCommandasRoot "$node" "zypper search -s mapr-core | grep -v '$curchangeset' | awk '{if(match(\$7,/[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.[a-zA-Z]*/)) print \$0}' | tail -n1 | awk '{print \$7}' | cut -d'.' -f1-3")
    fi

    if [[ -n "$maprversion" ]]; then
        echo "$maprversion"
    fi
}

function maprutil_copyRepoFile(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local node=$1
    local repofile=$2
    local repofilename=$(basename $repofile)
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        ssh_executeCommandasRoot "$1" "sed -i 's/^enabled.*/enabled=0/g' /etc/yum.repos.d/*mapr*.repo > /dev/null 2>&1" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "yum-config-manager --disable \\*" > /dev/null 2>&1
        #ssh_executeCommandasRoot "$1" "yum repolist | grep -i mapr | awk '{print \$1}' | tr '\n' ',' | sed 's/,$//g' > /dev/null 2>&1" > /dev/null 2>&1
        ssh_copyCommandasRoot "$node" "$2" "/etc/yum.repos.d/" > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        ssh_executeCommandasRoot "$1" "rm -rf /etc/apt/sources.list.d/*mapr*.list > /dev/null 2>&1" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "sed -i '/apt.qa.lab/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "sed -i '/artifactory.devops.lab/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "sed -i '/package.mapr.com/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1" > /dev/null 2>&1

        ssh_copyCommandasRoot "$node" "$2" "/etc/apt/sources.list.d/" > /dev/null 2>&1
    elif [ "$nodeos" = "suse" ]; then
        ssh_executeCommandasRoot "$1" "sed -i 's/^enabled.*/enabled=0/g' /etc/zypp/repos.d/*mapr*.repo > /dev/null 2>&1" > /dev/null 2>&1
        ssh_copyCommandasRoot "$node" "$2" "/etc/zypp/repos.d/" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "sed -i 's/redhat/suse/g' /etc/zypp/repos.d/$repofilename > /dev/null 2>&1" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "sed -i 's/protect=1/type=rpm-md/g' /etc/zypp/repos.d/$repofilename > /dev/null 2>&1" > /dev/null 2>&1
        #statements
    fi
}

function maprutil_buildPatchRepoURL(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ]; then
        [ -z "$GLB_PATCH_REPOFILE" ] && [ -n "$GLB_MAPR_VERSION" ] && GLB_PATCH_REPOFILE="http://artifactory.devops.lab/artifactory/prestage/releases-dev/patches/v${GLB_MAPR_VERSION}/redhat/"
    elif [ "$nodeos" = "ubuntu" ]; then
        [ -z "$GLB_PATCH_REPOFILE" ] && [ -n "$GLB_MAPR_VERSION" ] && GLB_PATCH_REPOFILE="http://artifactory.devops.lab/artifactory/prestage/releases-dev/patches/v${GLB_MAPR_VERSION}/ubuntu/"
    fi
    #echo "$GLB_PATCH_REPOFILE"
}

function maprutil_buildRepoFile(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    local repofile=$1
    local repourl=$2
    local node=$3
    local nodeos=$(getOSFromNode $node)
    local meprepo=
    if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ]; then
        meprepo="http://artifactory.devops.lab/artifactory/prestage/releases-dev/MEP/MEP-6.0.0/redhat/"
        [ -n "$GLB_MEP_REPOURL" ] && meprepo=$GLB_MEP_REPOURL
        [ -n "$GLB_MAPR_PATCH" ] && maprutil_buildPatchRepoURL "$node"
        [ -n "$GLB_PATCH_REPOFILE" ] && [ -z "$(wget $GLB_PATCH_REPOFILE -O- 2>/dev/null)" ] && GLB_PATCH_REPOFILE="http://artifactory.devops.lab/artifactory/list/ebf-rpm/"
        
        [ -n "$(echo "$GLB_MEP_REPOURL" | grep ubuntu)" ] && meprepo=$(echo $meprepo | sed 's/ubuntu/redhat/g')
        [ -n "$(echo "$repourl" | grep ubuntu)" ] && repourl=$(echo $repourl | sed 's/ubuntu/redhat/g')
        [ -n "$(echo "$GLB_PATCH_REPOFILE" | grep ubuntu)" ] && GLB_PATCH_REPOFILE=$(echo $GLB_PATCH_REPOFILE | sed 's/ubuntu/redhat/g')

        echo "[QA-CustomOpensource]" > $repofile
        echo "name=MapR Latest Build QA Repository" >> $repofile
        echo "baseurl=$meprepo" >> $repofile
        echo "enabled=1" >> $repofile
        echo "gpgcheck=0" >> $repofile
        echo "protect=1" >> $repofile
        echo >> $repofile
        echo "[QA-CustomRepo]" >> $repofile
        echo "name=MapR Custom Repository" >> $repofile
        echo "baseurl=${repourl}" >> $repofile
        echo "enabled=1" >> $repofile
        echo "gpgcheck=0" >> $repofile
        echo "protect=1" >> $repofile

        # Add patch if specified
        if [ -n "$GLB_PATCH_REPOFILE" ]; then
            echo >> $repofile
            echo "[QA-CustomPatchRepo]" >> $repofile
            echo "name=MapR Custom Repository" >> $repofile
            echo "baseurl=${GLB_PATCH_REPOFILE}" >> $repofile
            echo "enabled=1" >> $repofile
            echo "gpgcheck=0" >> $repofile
            echo "protect=1" >> $repofile
        fi
        echo >> $repofile
    elif [ "$nodeos" = "ubuntu" ]; then
        meprepo="http://artifactory.devops.lab/artifactory/prestage/releases-dev/MEP/MEP-6.0.0/ubuntu/"
        [ -n "$GLB_MEP_REPOURL" ] && meprepo=$GLB_MEP_REPOURL
        [ -n "$GLB_MAPR_PATCH" ] && maprutil_buildPatchRepoURL "$node"
        [ -n "$GLB_PATCH_REPOFILE" ] && [ -z "$(wget $GLB_PATCH_REPOFILE -O- 2>/dev/null)" ] && GLB_PATCH_REPOFILE="http://artifactory.devops.lab/artifactory/list/ebf-deb/"

        [ -n "$(echo "$GLB_MEP_REPOURL" | grep redhat)" ] && meprepo=$(echo $meprepo | sed 's/redhat/ubuntu/g')
        [ -n "$(echo "$repourl" | grep redhat)" ] && repourl=$(echo $repourl | sed 's/redhat/ubuntu/g')
        [ -n "$(echo "$GLB_PATCH_REPOFILE" | grep redhat)" ] && GLB_PATCH_REPOFILE=$(echo $GLB_PATCH_REPOFILE | sed 's/redhat/ubuntu/g')

        echo "deb $meprepo binary trusty" > $repofile
        echo "deb ${repourl} binary trusty" >> $repofile
        [ -n "$GLB_PATCH_REPOFILE" ] && echo "deb ${GLB_PATCH_REPOFILE} binary trusty" >> $repofile
    fi
}

function maprutil_getRepoURL(){
    local nodeos=$(getOS)
    if [ "$nodeos" = "centos" ]; then
        local repolist=$(yum repolist enabled -v | grep -e Repo-id -e Repo-baseurl -e MapR | grep -A1 -B1 MapR | grep -v Repo-name | grep -iv 'mep\|opensource\|file://\|ebf' | grep Repo-baseurl | cut -d':' -f2- | tr -d " " | head -1)
        echo "$repolist"
    elif [ "$nodeos" = "ubuntu" ]; then
        local repolist=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $2}' | grep -iv 'mep\|opensource\|file://\|ebf' | head -1)
        echo "$repolist"
    elif [ "$nodeos" = "suse" ]; then
        local repolist=$(zypper lr -u | awk '{if($7~"Yes") print $NF}' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com | grep -iv 'mep\|opensource\|file://\|ebf' | head -1)
        echo "$repolist"
    fi
}

function maprutil_getPatchRepoURL(){
    local nodeos=$(getOS)
    if [ "$nodeos" = "centos" ]; then
        local repolist=$(yum repolist enabled -v | grep -e Repo-id -e Repo-baseurl -e MapR | grep -A1 -B1 MapR | grep -v Repo-name | grep -iv 'mep\|opensource\|file://' | grep Repo-baseurl | grep -i EBF | cut -d':' -f2- | tr -d " " | head -1)
        echo "$repolist"
    elif [ "$nodeos" = "ubuntu" ]; then
        local repolist=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $2}' | grep -iv 'mep\|opensource\|file://' | grep -i EBF| head -1)
        echo "$repolist"
    elif [ "$nodeos" = "suse" ]; then
        local repolist=$(zypper lr -u | awk '{if($7~"Yes") print $NF}' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com | grep -iv 'mep\|opensource\|file://' | grep -i EBF | head -1)
        echo "$repolist"
    fi
}

function maprutil_disableAllRepo(){
    local nodeos=$(getOS)
    if [ "$nodeos" = "centos" ]; then
        local repolist=$(yum repolist enabled -v | grep -e Repo-id -e Repo-baseurl -e MapR | grep -A1 -B1 MapR | grep -v Repo-name | grep -iv opensource | grep Repo-id | cut -d':' -f2 | tr -d " ")
        for repo in $repolist
        do
            log_info "[$(util_getHostIP)] Disabling repository $repo"
            yum-config-manager --disable $repo > /dev/null 2>&1
        done
    elif [ "$nodeos" = "ubuntu" ]; then
        local repolist=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $2}' | grep -iv opensource | cut -d '/' -f3)
        for repo in $repolist
        do
           local repof=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep $repo | cut -d":" -f1)
           sed -i "/${repo}/s/^/#/" ${repof}
        done
    elif [ "$nodeos" = "suse" ]; then
        local repolist=$(zypper lr -u | awk '{if($7~"Yes") print $0}' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $3}' | grep -iv opensource)
        for repo in $repolist
        do
           log_info "[$(util_getHostIP)] Disabling repository $repo"
           zypper modifyrepo -d $repo > /dev/null 2>&1
        done
    fi
}

function maprutil_disableRepoByURL(){
    local nodeos=$(getOS)
    local repourl="$1"
    
    if [ "$nodeos" = "centos" ]; then
        local repofiles=$(grep "enabled=1" /etc/yum.repos.d/* | uniq | cut -d':' -f1)
        local repoline=$(grep -Hn "^baseurl=${repourl}" $repofiles)
        local repofile=$(echo "$repoline" | cut -d':' -f1)
        local repoln=$(grep -A2 -B2 -n "^baseurl=${repourl}" $repofile | grep "enabled" | cut -d'-' -f1)
        sed -i "${repoln}s/enabled.*/enabled=0/" $repofile
    elif [ "$nodeos" = "ubuntu" ]; then
        local repoline=$(grep -n "^${repourl}" /etc/apt/sources.list.d/*)
        local repofile=$(echo "$repoline" | cut -d':' -f1)
        local repoln=$(echo "$repoline" | cut -d':' -f2)
        sed -i "${repoln}s/^/#/" $repofile
    elif [ "$nodeos" = "suse" ]; then
        repourl=$(echo "$repourl" | sed 's/redhat/suse/g')
        local repofiles=$(grep "enabled=1" /etc/zypp/repos.d/* | uniq | cut -d':' -f1)
        local repoline=$(grep -Hn "^baseurl=${repourl}" $repofiles)
        local repofile=$(echo "$repoline" | cut -d':' -f1)
        local repoln=$(grep -A2 -B2 -n "^baseurl=${repourl}" $repofile | grep "enabled" | cut -d'-' -f1)
        sed -i "${repoln}s/enabled.*/enabled=0/" $repofile
    fi
}

function maprutil_enableRepoByURL(){
    local repourl="$1"
    local nodeos=$(getOS)
    
    if [ "$nodeos" = "centos" ]; then
        local repofiles=$(grep "enabled=1" /etc/yum.repos.d/* | uniq | cut -d':' -f1)
        local repoline=$(grep -Hn "^baseurl=${repourl}" $repofiles)
        local repofile=$(echo "$repoline" | cut -d':' -f1)
        local repoln=$(grep -A2 -B2 -n "^baseurl=${repourl}" $repofile | grep "enabled" | cut -d'-' -f1)
        sed -i "${repoln}s/enabled.*/enabled=1/" $repofile
    elif [ "$nodeos" = "ubuntu" ]; then
        local repoline=$(grep -n "^${repourl}" /etc/apt/sources.list.d/*)
        local repofile=$(echo "$repoline" | cut -d':' -f1)
        local repoln=$(echo "$repoline" | cut -d':' -f2)
        sed -i "${repoln}s/^#//" $repofile
    elif [ "$nodeos" = "suse" ]; then
        repourl=$(echo "$repourl" | sed 's/redhat/suse/g')
        local repofiles=$(grep "enabled=1" /etc/zypp/repos.d/* | uniq | cut -d':' -f1)
        local repoline=$(grep -Hn "^baseurl=${repourl}" $repofiles)
        local repofile=$(echo "$repoline" | cut -d':' -f1)
        local repoln=$(grep -A2 -B2 -n "^baseurl=${repourl}" $repofile | grep "enabled" | cut -d'-' -f1)
        sed -i "${repoln}s/enabled.*/enabled=1/" $repofile
    fi
}

# @param local repo path
function maprutil_addLocalRepo(){
    if [ -z "$1" ]; then
        return
    fi
    local nodeos=$(getOS)
    local repofile="/tmp/maprbuilds/mapr-$GLB_BUILD_VERSION.repo"
    if [ "$nodeos" = "ubuntu" ]; then
        repofile="/tmp/maprbuilds/mapr-$GLB_BUILD_VERSION.list"
    fi

    local repourl=$1
    log_info "[$(util_getHostIP)] Adding local repo $repourl for installing the binaries"
    if [ "$nodeos" = "centos" ]; then
        echo "[MapR-LocalRepo-$GLB_BUILD_VERSION]" > $repofile
        echo "name=MapR $GLB_BUILD_VERSION Repository" >> $repofile
        echo "baseurl=file://$repourl" >> $repofile
        echo "enabled=1" >> $repofile
        echo "gpgcheck=0" >> $repofile
        echo "protect=1" >> $repofile
        cp $repofile /etc/yum.repos.d/ > /dev/null 2>&1
        yum-config-manager --enable MapR-LocalRepo-$GLB_BUILD_VERSION > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        echo "deb file:$repourl ./" > $repofile
        cp $repofile /etc/apt/sources.list.d/ > /dev/null 2>&1
        apt-get update > /dev/null 2>&1
    elif [ "$nodeos" = "suse" ]; then
        echo "[MapR-LocalRepo-$GLB_BUILD_VERSION]" > $repofile
        echo "name=MapR $GLB_BUILD_VERSION Repository" >> $repofile
        echo "baseurl=file://$repourl" >> $repofile
        echo "enabled=1" >> $repofile
        echo "gpgcheck=0" >> $repofile
        echo "type=rpm-md" >> $repofile
        cp $repofile /etc/zypp/repos.d/ > /dev/null 2>&1
        zypper clean > /dev/null 2>&1
        zypper refresh > /dev/null 2>&1
    fi
}

# @param directory to download
# @param url to download
# @param filter keywork
function maprutil_downloadBinaries(){
     if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    local nodeos=$(getOS)
    local dlddir=$1
    mkdir -p $dlddir > /dev/null 2>&1
    local repourl=$2
    local searchkey=$3
    log_info "[$(util_getHostIP)] Downloading binaries for version [$searchkey]"
    if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ]; then
        pushd $dlddir > /dev/null 2>&1
        wget -r -np -nH -nd --cut-dirs=1 --accept "*${searchkey}*.rpm" ${repourl} > /dev/null 2>&1
        popd > /dev/null 2>&1
        createrepo $dlddir > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        pushd $dlddir > /dev/null 2>&1
        wget -r -np -nH -nd --cut-dirs=1 --accept "*${searchkey}*.deb" ${repourl} > /dev/null 2>&1
        dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
        popd > /dev/null 2>&1
    fi
}

function maprutil_setupLocalRepo(){
    local repourl=$(maprutil_getRepoURL)
    local patchrepo=$(maprutil_getPatchRepoURL)
    maprutil_disableAllRepo
    maprutil_downloadBinaries "/tmp/maprbuilds/$GLB_BUILD_VERSION" "$repourl" "$GLB_BUILD_VERSION"
    if [ -n "$patchrepo" ]; then
        local patchkey=
        if [ -z "$GLB_PATCH_VERSION" ]; then
            patchkey=$(lynx -dump -listonly ${patchrepo} | grep mapr-patch-[0-9] | tail -n 1 | awk '{print $2}' | rev | cut -d'/' -f1 | cut -d'.' -f2- | rev)
        else
            patchkey="mapr-patch*$GLB_BUILD_VERSION*$GLB_PATCH_VERSION"
        fi
        maprutil_downloadBinaries "/tmp/maprbuilds/$GLB_BUILD_VERSION" "$patchrepo" "$patchkey"
    fi
    maprutil_addLocalRepo "/tmp/maprbuilds/$GLB_BUILD_VERSION"
}

function maprutil_runCommandsOnNodesInParallel(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi

    local nodes=$1
    local cmd=$2
    local mailfile=$3

    local tempdir=$GLB_COPY_DIR
    if [ -z "$tempdir" ]; then
        tempdir="$RUNTEMPDIR/cmdrun"
    else
        tempdir="$tempdir/$cmd"
    fi
    mkdir -p $tempdir > /dev/null 2>&1

    for node in ${nodes[@]}
    do
        local nodefile="$tempdir/${node}_${cmd}.log"
        maprutil_runCommandsOnNode "$node" "$cmd" > $nodefile &
        maprutil_addToPIDList "$!" 
    done
    maprutil_wait > /dev/null 2>&1

    for node in ${nodes[@]}
    do
        local nodefile="$tempdir/${node}_${cmd}.log"
        if [ "$(cat $nodefile | wc -w)" -gt "0" ]; then
            cat "$nodefile" 2>/dev/null
            if [ -n "$mailfile" ]; then
                echo "Command '$cmd' Output : " >> $mailfile
                util_removeXterm "$(cat "$nodefile")" >> $mailfile
                echo >> $mailfile
            fi
        fi
    done
    [ -z "$GLB_COPY_DIR" ] && rm -rf $tempdir > /dev/null 2>&1
}

# @param host node
# @param ycsb/tablecreate
function maprutil_runCommandsOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    local node=$1
    local silent=$3
    
     # build full script for node
    local scriptpath="$RUNTEMPDIR/cmdonnode_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local client=$(maprutil_isClientNode "$2" "$hostnode")
    local hostip=$(util_getHostIP)
    
    echo "maprutil_runCommands \"$2\"" >> $scriptpath
   

    if [ -z "$silent" ]; then
        ssh_executeScriptasRoot "$node" "$scriptpath"
    else
        ssh_executeScriptasRoot "$node" "$scriptpath" > /dev/null 2>&1
    fi
}

# @param command
function maprutil_runMapRCmd(){
    if [ -z "$1" ]; then
        return
    fi
    local cmd=1;
    local i=0
    while [ "${cmd}" -ne "0" ]; do
        bash -c "$1"
        cmd=$?;
        [[ "${cmd}" -eq 0 ]] && break
        sleep 20
        let i=i+1
        if [ "$i" -gt 3 ]; then
            log_warn "Failed to run command [ $1 ]"
           return
        fi
    done
}

function maprutil_runCommands(){
    if [ -z "$1" ]; then
        return
    fi
    for i in $1
    do
        case $i in
            cldbtopo)
                maprutil_configureCLDBTopology "force"
            ;;
            tsdbtopo)
                maprutil_moveTSDBVolumeToCLDBTopology
            ;;
            createvol)
                maprutil_createVolume
            ;;
            tablecreate)
                maprutil_createTableWithCompressionOff
            ;;
            enableaudit)
                maprutil_enableClusterAudit
            ;;
            jsontable)
                maprutil_createJSONTable
            ;;
            jsontablecf)
                maprutil_createJSONTable
                maprutil_addCFtoJSONTable
            ;;
            tablelz4)
                maprutil_createTableWithCompression
            ;;
            diskcheck)
               maprutil_checkDiskErrors
            ;;
            tabletdist)
                maprutil_checkTabletDistribution
            ;;
            indexdist)
                maprutil_checkIndexTabletDistribution
            ;;
            indexdist2)
                maprutil_checkIndexTabletDistribution2
            ;;
            cntrdist)
                maprutil_checkContainerDistribution
            ;;
            disktest)
                maprutil_runDiskTest
            ;;
            sysinfo)
                maprutil_sysinfo
            ;;
            sysinfo2)
                maprutil_sysinfo "all"
            ;;
            mfsgrep)
                maprutil_grepMFSLogs
            ;;
            grepmapr)
                maprutil_grepMapRLogs
            ;;
            traceon)
                maprutil_killTraces
                maprutil_startTraces
            ;;
            mrinfo)
                maprutil_runmrconfig_info
            ;;
            mrdbinfo)
                maprutil_runmrconfig_info "dbinfo"
            ;;
            insttrace)
                maprutil_startInstanceGuts
            ;;
            traceoff)
                maprutil_killTraces
            ;;
            analyzecores)
                maprutil_analyzeCores
            ;;
            mfsthreads)
                maprutil_mfsthreads
            ;;
            queryservice)
                maprutil_queryservice
            ;;
            *)
            echo "Nothing to do!!"
            ;;
        esac
    done
}

function maprutil_enableClusterAudit () {
    log_msghead " *************** Enable cluster wide Audit **************** "
    maprutil_runMapRCmd "timeout 30 maprcli audit cluster -enabled true"
    maprutil_runMapRCmd "timeout 30 maprcli audit data -enabled true"
    if [[ "$GLB_ENABLE_AUDIT" -gt "1" ]]; then
        maprutil_runMapRCmd "timeout 30 maprcli config save -values '{\"mfs.enable.audit.as.stream\":\"1\"}'"
        maprutil_runMapRCmd "timeout 30 maprcli node services -name hoststats -action restart -filter '[csvc==hoststats]'"
    fi
}

function maprutil_createVolume () {
    local volname=$(echo "$GLB_CREATE_VOL" | cut -d',' -f1)
    local volpath=$(echo "$GLB_CREATE_VOL" | cut -d',' -f2)
    [ -z "$volname" ] || [ -z "$volpath" ] && return

    log_msghead " *************** Creating $volname Volume **************** "
    maprutil_runMapRCmd "timeout 30 maprcli volume create -name $volname -path $volpath -replication 3 -topology /data"
    [[ "$volname" = "tables" ]] && maprutil_runMapRCmd "hadoop mfs -setcompression off /tables"
}

function maprutil_createTableWithCompression(){
    log_msghead " *************** Creating UserTable (/tables/usertable) with lz4 compression **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "timeout 30 maprcli table create -path /tables/usertable" 
    maprutil_runMapRCmd "timeout 30 maprcli table cf create -path /tables/usertable -cfname family -compression lz4 -maxversions 1"
}

function maprutil_createTableWithCompressionOff(){
    log_msghead " *************** Creating UserTable (/tables/usertable) with compression off **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "timeout 30 maprcli table create -path /tables/usertable"
    maprutil_runMapRCmd "timeout 30 maprcli table cf create -path /tables/usertable -cfname family -compression off -maxversions 1"
}

function maprutil_createJSONTable(){
    log_msghead " *************** Creating JSON UserTable (/tables/usertable) with compression off **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "timeout 30 maprcli table create -path /tables/usertable -tabletype json "
}

function maprutil_addCFtoJSONTable(){
    log_msghead " *************** Creating JSON UserTable (/tables/usertable) with compression off **************** "
    maprutil_runMapRCmd "timeout 30 maprcli table cf create -path /tables/usertable -cfname cfother -jsonpath field0 -compression off -inmemory true"
}

function maprutil_checkDiskErrors(){
    log_msghead " [$(util_getHostIP)] Checking for disk errors "
    local numlines=2
    [ -n "$GLB_LOG_VERBOSE" ] && numlines=all
    util_grepFiles "$numlines" "/opt/mapr/logs/" "mfs.log*" "DHL" "lun.cc"
}

function maprutil_runDiskTest(){
    local maprdisks=$(util_getRawDisks)
    if [ -z "$maprdisks" ]; then
        return
    fi
    echo
    log_msghead "[$(util_getHostIP)] Running disk tests [$maprdisks]"
    local disktestdir="/tmp/disktest"
    mkdir -p $disktestdir 2>/dev/null
    for disk in ${maprdisks[@]}
    do  
        local disklog="$disktestdir/${disk////_}.log"
        hdparm -tT $disk > $disklog &
    done
    wait
    for file in $(find $disktestdir -type f | sort)
    do
        grep -v '^$' $file
    done
    rm -rf $disktestdir 2>/dev/null
}

function maprutil_checkTabletDistribution(){
    if [[ -z "$GLB_TABLET_DIST" ]] || [[ ! -e "/opt/mapr/roles/fileserver" ]]; then
        return
    fi
    [ -z "$(pidof mfs)" ] && return

    local filepath=$GLB_TABLET_DIST
    local hostnode=$(hostname -f)


    [ -n "$(echo "$filepath" | grep -ow "[0-9]*\.[0-9]*\.[0-9]*")" ] && maprutil_checkTabletDistribution2 && return

    local cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null |  grep cid: | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $4,$2}')
    [ -z "$cntrlist" ] && return

    local nodetablets=$(timeout 30 maprcli table region list -path $filepath -json 2>/dev/null | tr -d '\040\011\012\015' | sed 's/,{"/,\n{"/g' | sed 's/},/\n},/g' | sed 's/,"/,\n"/g' | sed 's/}]/\n}]/g' | sed 's/primarymfs/\nprimarymfs/g' | grep -v 'secondary' | grep -A11 "mfs\":\"$hostnode" | tr -d '"' | tr -d ',')
    local tabletContainers=$(echo "$nodetablets" | grep fid | cut -d":" -f2 | cut -d"." -f1 | tr -d '"')
    [ -z "$tabletContainers" ] && return
    
    local storagePools=$(/opt/mapr/server/mrconfig sp list 2>/dev/null | grep name | cut -d":" -f2 | awk '{print $2}' | tr -d ',' | sort -n -k1.3)
    local numTablets=$(echo "$tabletContainers" | wc -l)
    local numContainers=$(echo "$tabletContainers" | sort | uniq | wc -l)
    log_msg "$(util_getHostIP) : [# of tablets: $numTablets], [# of containers: $numContainers]"

    for sp in $storagePools; do
        local spcntrs=$(echo "$cntrlist" | grep -w $sp | awk '{print $2}')
        local cnt=$(echo "$tabletContainers" |  grep -Fw "${spcntrs}" | wc -l)
        local numcnts=$(echo "$tabletContainers" |  grep -Fw "${spcntrs}" | sort -n | uniq | wc -l)
        [ "$cnt" -eq "0" ] && continue

        local sptabletfids=$(echo "$nodetablets" | grep -Fw "${spcntrs}" | grep -w "[0-9]*\.[0-9].*\.[0-9].*" | cut -d':' -f2 | sort -t. -n -k1,1 -k2,2 -k3)
        [ -z "$sptabletfids" ] && continue
        [ -n "$sptabletfids" ] && log_msg "\t$sp : $cnt Tablets (on $numcnts containers)"

        [ -z "$GLB_LOG_VERBOSE" ] && continue

        for tabletfid in $sptabletfids
        do
            local tabletinfo=$(echo "$nodetablets" | grep -B4 -A7 $tabletfid | grep -w 'physicalsize\|numberofrows\|numberofrowswithdelete\|numberofspills\|numberofsegments')
            
            local tabletsize=$(echo "$tabletinfo" |  grep -w physicalsize | cut -d':' -f2 | tr -d ',' | awk '{ if($1<1024) printf("%d B",$1); else if($1<(1024*1024)) printf("%d KB",($1/1024)); else if($1<(1024*1024*1024)) printf("%d MB",($1/(1024*1024))); else printf("%.2f GB",($1/1073741824));}')
            local numrows=$(echo "$tabletinfo" | grep -w numberofrows | cut -d':' -f2)
            local numdelrows=$(echo "$tabletinfo" | grep -w numberofrowswithdelete | cut -d':' -f2)
            local numspills=$(echo "$tabletinfo" | grep -w numberofspills | cut -d':' -f2)
            local numsegs=$(echo "$tabletinfo" | grep -w numberofsegments | cut -d':' -f2)
            
            log_msg "\t\t Tablet [$tabletfid] Size: ${tabletsize}, #ofRows: $numrows, #ofDelRows: $numdelrows, #ofSegments: $numsegs, #ofSpills: $numspills"
        done

    done
}

function maprutil_checkTabletDistribution2(){
    if [[ -z "$GLB_TABLET_DIST" ]] || [[ ! -e "/opt/mapr/roles/fileserver" ]]; then
        return
    fi
    [ -z "$(pidof mfs)" ] && return

    local hostip=$(util_getHostIP)
    local tablecid=$(echo "$GLB_TABLET_DIST" | cut -d'.' -f1)

    local tablemapfid=$(timeout 30 maprcli debugdb dump -fid $GLB_TABLET_DIST -json 2>/dev/null | grep -A2 "tabletmap" | grep fid | grep -oh "<parentCID>\.[0-9]*\.[0-9]*" | cut -d'.' -f2-)
    [ -z "$tablemapfid" ] && return

    tablemapfid="$tablecid.$tablemapfid"

    local alltabletfids=$(timeout 30 maprcli debugdb dump -fid $tablemapfid -json 2>/dev/null | grep fid | cut -d':' -f2 | tr -d '"' | sort)
    local allcids=$(echo "$alltabletfids" | cut -d'.' -f1 | sort | uniq | sed ':a;N;$!ba;s/\n/,/g')

    local localcids=$(timeout 10 maprcli dump containerinfo -ids $allcids -json 2>/dev/null | grep '\"ContainerId\"\|\"Master\"' | grep -B1 "$hostip" | grep ContainerId | cut -d':' -f2 | tr -d ',' | grep "^[0-9]*")
    [ -z "$localcids" ] && return
    local numlocalcids=$(echo "$localcids" | wc -l)

    local localtabletfids=
    for i in $alltabletfids; do
      for j in $localcids; do
        [ -n "$(echo "$i" | grep "^$j\.")" ] && localtabletfids="$localtabletfids $i"
      done
    done
    localtabletfids=$(echo "$localtabletfids" | tr ' ' '\n' | grep "[0-9]*")

    local cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null |  grep cid: | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $4,$2}')
    [ -z "$cntrlist" ] && return

    local storagePools=$(/opt/mapr/server/mrconfig sp list 2>/dev/null | grep name | cut -d":" -f2 | awk '{print $2}' | tr -d ',' | sort -n -k1.3)
    local numTablets=$(echo "$alltabletfids" | cut -d'.' -f1 | grep -Fw "$localcids" | wc -l)
    log_msg "$(util_getHostIP) : [# of tablets: $numTablets], [# of containers: $numlocalcids]"

    for sp in $storagePools; do
        local spcntrs=$(echo "$cntrlist" | grep -w $sp | awk '{print $2}')
        local numcnts=$(echo "$localcids" |  grep -Fw "${spcntrs}" | sort -n | uniq | wc -l)
        local sptabletfids=$(echo "$localtabletfids" | grep -Fw "${spcntrs}" | grep -w "[0-9]*\.[0-9].*\.[0-9].*" | cut -d':' -f2 | sort -t. -n -k1,1 -k2,2 -k3)
        [ -z "$sptabletfids" ] && continue
        local tcnt=$(echo "$sptabletfids" | wc -l)
        [ -n "$sptabletfids" ] && log_msg "\t$sp : $tcnt Tablets (on $numcnts containers)"

        [ -z "$GLB_LOG_VERBOSE" ] && continue

        for tabletfid in $sptabletfids
        do
            local tabletinfo=$(timeout 30 maprcli debugdb dump -fid $tabletfid -json 2>/dev/null | grep -w 'numPhysicalBlocks\|numRows\|numRowsWithDelete\|numSpills\|numSegments' | tr -d '"' | tr -d ',')
            local tabletsize=$(echo "$tabletinfo" |  grep -w numPhysicalBlocks | cut -d':' -f2 | awk '{sum+=$1}END{print sum*8192/1073741824}')
            tabletsize=$(printf "%.2f\n" $tabletsize)
            
            local numrows=$(echo "$tabletinfo" | grep -w numRows | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
            local numdelrows=$(echo "$tabletinfo" | grep -w numRowsWithDelete | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
            local numspills=$(echo "$tabletinfo" | grep -w numSpills | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
            local numsegs=$(echo "$tabletinfo" | grep -w numSegments | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')

            log_msg "\t\t Tablet [$tabletfid] Size: ${tabletsize}GB, #ofRows: $numrows, #ofDelRows: $numdelrows, #ofSegments: $numsegs, #ofSpills: $numspills"
        done

    done

}

function maprutil_checkContainerDistribution(){
    if [[ ! -e "/opt/mapr/roles/fileserver" ]]; then
        return
    fi
    [ -z "$(pidof mfs)" ] && return

    local hostip=$(util_getHostIP)
    local cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null |  grep cid: | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $2,$4}' | sort -n -k2.4)
    local numcnts=$(echo "$cntrlist" | wc -l)
    cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null |  grep cid: | grep "role:0\|role:1" | grep -v "volid:0" | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $2,$4}' | sort -n -k2.4)
    local cids="$(echo "$cntrlist" | awk '{print $1}' | sed ':a;N;$!ba;s/\n/,/g')"
    local nummcids=$(timeout 10 maprcli dump containerinfo -ids $cids -json 2>/dev/null | grep Master | grep $hostip | wc -l)
    
    log_msg "$(util_getHostIP) : [ # of containers master/total : $nummcids/$numcnts]"

    local splist=$(/opt/mapr/server/mrconfig sp list 2>/dev/null | grep name | cut -d":" -f2 | awk '{print $2}' | tr -d ',' | sort -n -k1.3)
    for sp in $splist
    do
        cids="$(echo "$cntrlist" | grep -w $sp | awk '{print $1}' | sed ':a;N;$!ba;s/\n/,/g')"
        numcids=$(echo "$cntrlist" | grep -w $sp | awk '{print $1}' | wc -l)
        nummcids=$(timeout 10 maprcli dump containerinfo -ids $cids -json 2>/dev/null | grep Master | grep $hostip | wc -l)
        log_msg "\t$sp : $nummcids / $numcids"
    done
}

function maprutil_checkIndexTabletDistribution(){
    if [[ -z "$GLB_TABLET_DIST" ]] || [[ ! -e "/opt/mapr/roles/fileserver" ]]; then
        return
    fi
    [ -z "$(pidof mfs)" ] && return

    local tablepath=$GLB_TABLET_DIST
    local hostnode=$(hostname -f)

    local cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null |  grep cid: | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $4,$2}')
    [ -z "$cntrlist" ] && return

    local indexlist=
    if [ -z "$GLB_INDEX_NAME" ] || [ "$GLB_INDEX_NAME" = "all" ]; then
        indexlist=$(timeout 30 maprcli table index list -path $tablepath -json 2>/dev/null | grep "indexName" | tr -d '"' | tr -d ',' | cut -d':' -f2 | sed 's/\n/ /g')
    else
        indexlist="$GLB_INDEX_NAME"
    fi

    local storagePools=$(/opt/mapr/server/mrconfig sp list 2>/dev/null | grep name | cut -d":" -f2 | awk '{print $2}' | tr -d ',' | sort -n -k1.3)
    local tempdir=$(mktemp -d)

    for index in $indexlist
    do
        local nodeindextablets=$(timeout 30 maprcli table region list -path $tablepath -index $index -json 2>/dev/null | tr -d '\040\011\012\015' | sed 's/,{"/,\n{"/g' | sed 's/,"/,\n"/g' | sed 's/},/\n},/g' | sed 's/}]/\n}]/g' | sed 's/primarymfs/\nprimarymfs/g' | grep -v 'secondary' | grep -A11 "mfs\":\"$hostnode" | tr -d '"' | tr -d ',')
        local tabletContainers=$(echo "$nodeindextablets" | grep fid | cut -d":" -f2 | cut -d"." -f1 | tr -d '"')
        [ -z "$tabletContainers" ] && continue
        local numTablets=$(echo "$tabletContainers" | wc -l)
        local numContainers=$(echo "$tabletContainers" | sort | uniq | wc -l)
        local indexlog="$tempdir/$index.log"
        for sp in $storagePools; do
            local spcntrs=$(echo "$cntrlist" | grep -w $sp | awk '{print $2}')
            local cnt=$(echo "$tabletContainers" |  grep -Fw "${spcntrs}" | wc -l)
            [ "$cnt" -eq "0" ] && continue

            local numcnts=$(echo "$tabletContainers" |  grep -Fw "${spcntrs}" | sort -n | uniq | wc -l)
            local sptabletfids=$(echo "$nodeindextablets" | grep -Fw "${spcntrs}" | grep -w "[0-9]*\.[0-9].*\.[0-9].*" | cut -d':' -f2 | sort -t. -n -k1,1 -k2,2 -k3)
            [ -z "$sptabletfids" ] && continue
            [ -n "$sptabletfids" ] && log_msg "\t$sp : $cnt Tablets (on $numcnts containers)" >> $indexlog
            for tabletfid in $sptabletfids
            do
                local tabletinfo=$(echo "$nodeindextablets" | grep -B4 -A7 $tabletfid | grep -w 'physicalsize\|numberofrows\|numberofrowswithdelete\|numberofspills\|numberofsegments')
                
                local tabletsize=$(echo "$tabletinfo" |  grep -w physicalsize | cut -d':' -f2 | tr -d ',' | awk '{ if($1<1024) printf("%d B",$1); else if($1<(1024*1024)) printf("%d KB",($1/1024)); else if($1<(1024*1024*1024)) printf("%d MB",($1/(1024*1024))); else printf("%.2f GB",($1/1073741824));}')
                local numrows=$(echo "$tabletinfo" | grep -w numberofrows | cut -d':' -f2)
                local numdelrows=$(echo "$tabletinfo" | grep -w numberofrowswithdelete | cut -d':' -f2)
                local numspills=$(echo "$tabletinfo" | grep -w numberofspills | cut -d':' -f2)
                local numsegs=$(echo "$tabletinfo" | grep -w numberofsegments | cut -d':' -f2)
                
                log_msg "\t\t Tablet [$tabletfid] Size: ${tabletsize}, #ofRows: $numrows, #ofDelRows: $numdelrows, #ofSegments: $numsegs, #ofSpills: $numspills" >> $indexlog
            done
        done
        if [ "$(cat $indexlog | wc -w)" -gt "0" ]; then
            local indexSize=$(cat "$indexlog" | grep -o "Size: [0-9]*.[0-9]*.*B" | awk '{if($3 ~ /GB/) sum+=$2; else if($3 ~ /MB/) sum+=$2/1024;}END{print sum}')
            local numrows=$(cat "$indexlog" | grep -o "#ofRows: [0-9]*" | awk '{sum+=$2}END{print sum}')
            local numtablets=$(cat "$indexlog" | grep -o "Size: [0-9]*.[0-9]*" | wc -l)
            numrows=$(printf "%'d" $numrows)
            log_msg "\n $(util_getHostIP) : Index '$index' [ #ofTablets: ${numtablets}, Size: ${indexSize}GB, #ofRows: ${numrows} ]"
            cat "$indexlog" 2>/dev/null
        fi
    done
    rm -rf $tempdir > /dev/null 2>&1
}

function maprutil_checkIndexTabletDistribution2(){
    if [[ -z "$GLB_TABLET_DIST" ]] || [[ ! -e "/opt/mapr/roles/fileserver" ]]; then
        return
    fi
    [ -z "$(pidof mfs)" ] && return

    local hostip=$(util_getHostIP)
    local tablepath=$GLB_TABLET_DIST

    local ciddump=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null)
    local cids=$(echo "$ciddump" |  grep cid: | awk '{print $1}' | cut -d':' -f2 | sort -n | uniq | sed ':a;N;$!ba;s/\n/,/g')
    [ -z "$cids" ] && return

    local indexlist=
    if [ -z "$GLB_INDEX_NAME" ] || [ "$GLB_INDEX_NAME" = "all" ]; then
        indexlist=$(timeout 30 maprcli table index list -path $tablepath -json 2>/dev/null | grep "indexFid\|indexName" | tr -d '"' | tr -d ',' | tr -d "'")
    else
        indexlist=$(timeout 30 maprcli table index list -path $tablepath -json 2>/dev/null | grep "indexFid\|indexName" | grep -iB1 "$GLB_INDEX_NAME" | tr -d '"' | tr -d ',' | tr -d "'")
    fi
    [ -z "$indexlist" ] && return

    local localcids=$(timeout 30 maprcli dump containerinfo -ids $cids -json 2>/dev/null | grep 'ContainerId\|Master' | grep -B1 $hostip | grep ContainerId | tr -d '"' | tr -d ',' | tr -d "'" | cut -d':' -f2 | sed 's/^/\^/')
    local indexfids=$(echo "$indexlist" | grep indexFid | cut -d':' -f2)
    local tempdir=$(mktemp -d)

    for idxfid in $indexfids
    do
        local idxcntr=$(echo $idxfid | cut -d'.' -f1)
        local tabletsubfid=$(timeout 30 maprcli debugdb dump -fid $idxfid -json 2>/dev/null | grep -A2 tabletmap | grep fid | cut -d'.' -f2- | tr -d '"')
        local tabletmapfid="${idxcntr}.${tabletsubfid}"
        local idxtabletfids=$(timeout 30 maprcli debugdb dump -fid $tabletmapfid -json 2>/dev/null | grep fid | cut -d':' -f2 | tr -d '"' | grep "$localcids")

        local totaltablets=$(echo "$idxtabletfids" | wc -w)
        [ "$totaltablets" -lt "1" ] && continue
        local indexname=$(echo "$indexlist" | grep -A1 $idxfid | grep indexName | cut -d':' -f2)
        
        local sleeptime=5
        local maxnumcli=$(echo $(nproc)/2|bc)
        local i=1
        local indexlog="$tempdir/$indexname.log"
        for tabletfid in $idxtabletfids
        do
            maprutil_printTabletStats2 "$i" "$tabletfid" >> $indexlog &
            let i=i+1
            local curnumcli=$(jps | grep CLIMainDriver | wc -l)
            while [ "$curnumcli" -gt "$maxnumcli" ]
            do
                sleep $sleeptime
                curnumcli=$(jps | grep CLIMainDriver | wc -l)
            done
        done
        wait

        # Print the output
        if [ "$(cat $indexlog | wc -w)" -gt "0" ]; then
            local indexSize=$(cat "$indexlog" | grep -o "Size: [0-9]*.[0-9]*" | awk '{sum+=$2}END{print sum}')
            local numrows=$(cat "$indexlog" | grep -o "#ofRows: [0-9]*" | awk '{sum+=$2}END{print sum}')
            local numtablets=$(cat "$indexlog" | grep -o "Size: [0-9]*.[0-9]*" | wc -l)
            numrows=$(printf "%'d" $numrows)
            log_msg "\n$(util_getHostIP) : Index '$indexname' [ #ofTablets: ${numtablets}, Size: ${indexSize}GB, #ofRows: ${numrows} ]"
            cat "$indexlog" | sort -nk2.3 | sort -nk3.3 2>/dev/null
        fi
    done
    
    rm -rf $tempdir > /dev/null 2>&1
}

function maprutil_printTabletStats2(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local tabletindex=$1
    local tabletfid=$2

    local tabletinfo=$(timeout 30 maprcli debugdb dump -fid $tabletfid -json 2>/dev/null | grep -w 'numPhysicalBlocks\|numRows\|numRowsWithDelete\|numSpills\|numSegments' | tr -d '"' | tr -d ',')
    local tabletsize=$(echo "$tabletinfo" |  grep -w numPhysicalBlocks | cut -d':' -f2 | awk '{sum+=$1}END{print sum*8192/1073741824}')
    tabletsize=$(printf "%.2f\n" $tabletsize)
    
    local numrows=$(echo "$tabletinfo" | grep -w numRows | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
    local numdelrows=$(echo "$tabletinfo" | grep -w numRowsWithDelete | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
    local numspills=$(echo "$tabletinfo" | grep -w numSpills | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
    local numsegs=$(echo "$tabletinfo" | grep -w numSegments | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
    log_msg "\t Tablet #${tabletindex} [$tabletfid] Size: ${tabletsize}GB, #ofRows: $numrows, #ofDelRows: $numdelrows, #ofSegments: $numsegs, #ofSpills: $numspills"
}

function maprutil_sysinfo(){
    echo
    log_msghead "[$(util_getHostIP)] System info"
    
    local options=
    [ -z "$GLB_SYSINFO_OPTION" ] && GLB_SYSINFO_OPTION="all"

    if [ "$(echo $GLB_SYSINFO_OPTION | grep all)" ]; then
        options="all"
    else
        options=$(echo $GLB_SYSINFO_OPTION | tr "," "\n")
    fi

    [ -n "$1" ] && options="all"

    for i in $options
    do
        case $i in
            cpu)
                util_getCPUInfo
            ;;
            disk)
                util_getDiskInfo
            ;;
            nw)
                util_getNetInfo
            ;;
            mem)
                util_getMemInfo
            ;;
            machine)
                util_getMachineInfo
            ;;
            mapr)
                maprutil_getMapRInfo
            ;;
            numa)
                util_getNumaInfo
            ;;
            all)
                maprutil_getMapRInfo
                util_getMachineInfo
                util_getCPUInfo
                util_getMemInfo
                util_getNetInfo
                util_getDiskInfo
                util_getNumaInfo
            ;;
        esac
    done
}

function maprutil_grepMFSLogs(){
    echo
    log_msghead "[$(util_getHostIP)] Searching MFS logs for FATAL & DHL messages"
    local dirpath="/opt/mapr/logs"
    local fileprefix="mfs.log*"
    local numlines=2
    [ -n "$GLB_LOG_VERBOSE" ] && numlines=all

    util_grepFiles "$numlines" "$dirpath" "$fileprefix" "FATAL"
    util_grepFiles "$numlines" "$dirpath" "$fileprefix" "DHL" "lun.cc"
}

function maprutil_grepMapRLogs(){
    echo
    log_msghead "[$(util_getHostIP)] Searching MapR logs"
    local dirpath="/opt/mapr/logs"
    local fileprefix="*"
    local numlines=2
    [ -n "$GLB_LOG_VERBOSE" ] && numlines=all

    util_grepFiles "$numlines" "$dirpath" "$fileprefix" "$GLB_GREP_MAPRLOGS"
}

function maprutil_getMapRInfo(){
    local version=$(cat /opt/mapr/MapRBuildVersion 2>/dev/null)
    [ -z "$version" ] && return

    local roles=$(ls /opt/mapr/roles 2>/dev/null| tr '\n' ' ')
    local nodeos=$(getOS)
    local patch=
    local client=
    local bins=
    if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ]; then
        local rpms=$(rpm -qa | grep mapr)
        patch=$(echo "$rpms" | grep mapr-patch | cut -d'-' -f4 | cut -d'.' -f1)
        client=$(echo "$rpms" | grep mapr-client | cut -d'-' -f3)
        bins=$(echo "$rpms" | grep mapr- | sort | sed 's/-[0-9].*//' | tr '\n' ' ')
    elif [ "$nodeos" = "ubuntu" ]; then
        local debs=$(dpkg -l | grep mapr)
        patch=$(echo "$debs" | grep mapr-patch | awk '{print $3}' | cut -d'-' -f4 | cut -d'.' -f1)
        client=$(echo "$debs" | grep mapr-client | awk '{print $3}' | cut -d'-' -f1)
        bins=$(echo "$debs" | grep mapr- | awk '{print $2}' | sort | tr '\n' ' ')
    fi
    [ -n "$patch" ] && version="$version (patch ${patch})"
    local nummfs=
    local numsps=
    local sppermfs=
    local nodetopo=
    if [ -e "/opt/mapr/roles/fileserver" ] && [ -n "$(pidof mfs)" ]; then
        nummfs=$(timeout 10 /opt/mapr/server/mrconfig info instances 2>/dev/null| head -1)
        numsps=$(timeout 10 /opt/mapr/server/mrconfig sp list 2>/dev/null| grep SP[0-9] | wc -l)
        #command -v maprcli >/dev/null 2>&1 && sppermfs=$(maprcli config load -json 2>/dev/null| grep multimfs.numsps.perinstance | tr -d '"' | tr -d ',' | cut -d':' -f2)
        sppermfs=$(timeout 10 /opt/mapr/server/mrconfig sp list -v 2>/dev/null| grep SP[0-9] | awk '{print $18}' | tr -d ',' | uniq -c | awk '{print $1}' | sort -nr | head -1)
        #[[ "$nummfs" -gt "1" ]] && [[ "$sppermfs" -eq "0" ]] && sppermfs=$(/opt/mapr/server/mrconfig sp list -v 2>/dev/null| grep SP[0-9] | awk '{print $18}' | tr -d ',' | uniq -c | awk '{print $1}' | sort -nr | head -1)
        [[ "$sppermfs" -eq 0 ]] && sppermfs=$numsps
        command -v maprcli >/dev/null 2>&1 && nodetopo=$(timeout 10 maprcli node list -columns id,configuredservice,racktopo -json 2>/dev/null | grep "$(hostname -f)" | grep racktopo | sed "s/$(hostname -f)//g" | cut -d ':' -f2 | tr -d '"' | tr -d ',')
    fi
    
    log_msghead "MapR Info : "
    [ -n "$roles" ] && log_msg "\t Roles    : $roles"
    log_msg "\t Version  : ${version}"
    [ -n "$client" ] && log_msg "\t Client   : ${client}"
    log_msg "\t Binaries : $bins"
    [[ -n "$nummfs" ]] && [[ "$nummfs" -gt 0 ]] && log_msg "\t # of MFS : $nummfs"
    [[ -n "$numsps" ]] && [[ "$numsps" -gt 0 ]] && log_msg "\t # of SPs : $numsps (${sppermfs} per mfs)"
    [[ -n "$nodetopo" ]] && log_msg "\t Topology : ${nodetopo%?}"
}

function maprutil_getClusterSpec(){
    if [ -z "$1" ]; then
        return
    fi
    local nodelist=$1
    local sysinfo=$(maprutil_runCommandsOnNodesInParallel "$nodelist" "sysinfo2" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g')
    local hwspec=
    local sysspec=
    local maprspec=

    # Build System Spec

    local numnodes=$(echo "$sysinfo" | grep "System info" | wc -l)
    sysspec="$numnodes nodes"

    ## CPU
    local cpucores=$(echo "$sysinfo" | grep -A1 cores | grep -B1 Enabled | grep cores | cut -d ':' -f2 | sed 's/ *//g')
    [ -n "$cpucores" ] && [ "$(echo $cpucores| wc -w)" -ne "$numnodes" ] && log_warn "CPU hyperthreading mismatch on nodes" && cpucores=0
    [ -n "$cpucores" ] && cpucores=$(echo "$cpucores" | sort | uniq)
    if [ -n "$cpucores" ] && [ "$(echo $cpucores | wc -w)" -gt "1" ]; then
        log_warn "CPU cores do not match. Not a homogeneous cluster"
        cpucores=$(echo "$cpucores" | sort -nr | head -1)
    elif [ -n "$cpucores" ]; then
        cpucores="2 x $cpucores"
    fi
    
    if [ -z "$cpucores" ]; then
        cpucores=$(echo "$sysinfo" | grep -A1 cores | grep -B1 Disabled | grep cores | cut -d ':' -f2 | sed 's/ *//g' | sort | uniq)
        [ -n "$cpucores" ] && [ "$(echo $cpucores | wc -w)" -gt "1" ] && log_warn "CPU cores do not match. Not a homogeneous cluster" && cpucores=$(echo "$cpucores" | sort -nr | head -1)
    fi

    hwspec="$cpucores cores"
    ## Disk
    local numdisks=$(echo "$sysinfo" | grep "Disk Info" | cut -d':' -f3 | tr -d ']' | sed 's/ *//g')
    if [ -n "$numdisks" ]; then 
        [ "$(echo $numdisks| wc -w)" -ne "$numnodes" ] && log_warn "Few nodes do not have disks"
        numdisks=$(echo "$numdisks" | sort | uniq)
        if [ "$(echo $numdisks | wc -w)" -gt "1" ]; then
            log_warn "# of disks do not match. Not a homogeneous cluster"
            numdisks=$(echo "$numdisks" | sort -nr | head -1)
        fi
    else
        log_error "No disks listed on any nodes"
        numdisks=0
    fi
    
    ## More disk info
    local diskstr=$(echo "$sysinfo" | grep -A${numdisks} "Disk Info" | grep -v OS | grep Type: )
    local diskcnt=$(echo "$diskstr" | sort -k1 | awk '{print $1}' | uniq -c | wc -l)
    if [ "$diskcnt" -ge "$numdisks" ]; then
        diskcnt=$(echo "$diskstr" | sort -k1 | awk '{print $1}' | uniq -c | wc -l)
    fi
    [ "$diskcnt" -lt "$numdisks" ] && numdisks=$diskcnt
    
    local disktype=$(echo "$diskstr" | awk '{print $4}' | tr -d ',' | sort | uniq)
    if [ "$(echo $disktype | wc -w)" -gt "1" ]; then
        log_warn "Mix of HDD & SSD disks. Not a homogeneous cluster"
        disktype=$(echo "$diskstr" | awk '{print $4}' | tr -d ',' | sort | uniq -c | sort -nr | awk '{print $2}' | tr '\n' '/' | sed s'/.$//')
    fi

    local disksize=$(echo "$diskstr" | awk '{print $6}' | sort | uniq)
    if [ "$(echo $disksize | wc -w)" -gt "1" ]; then
        local dn=
        local dz=
        for d in $disksize
        do
            local sz=$(util_getNearestPower2 $d)
            [ -z "$dz" ] && dz=$sz
            [ -z "$dn" ] && [ "$sz" -ne "$dz" ] && log_warn "Disks are of different capacities" && dn=1
        done
        disksize=$(echo "$diskstr" | awk '{print $6}' | sort | uniq | sort -nr | head -1)
    fi
    disksize=$(util_getNearestPower2 $disksize)
    if [ "$disksize" -lt "999" ]; then
        disksize="${disksize} GB" 
    else
        disksize="$(echo "$disksize/1000" | bc)TB"
    fi

    hwspec="$hwspec, ${numdisks} x ${disksize} $disktype"

    ## Memory
    local memory=
    local memorystr=$(echo "$sysinfo" | grep -A1 "Memory Info" | grep Memory | grep -v Info | cut -d':' -f2)
    local memcnt=$(echo "$memorystr" | wc -l)
    if [ -n "$memorystr" ]; then 
        [ "$memcnt" -ne "$numnodes" ] && log_warn "No memory listed for few nodes"
        memory=$(echo "$memorystr" | awk '{print $1}' | sort | uniq)
        local gb=$(echo "$memorystr" | awk '{print $2}' | sort | uniq | sort -nr | head -1)
        if [ "$(echo $memory | wc -w)" -gt "1" ]; then
            log_warn "Memory isn't same all node nodes. Not a homogeneous cluster"
            memory=$(echo "$memory" | sort -nr | head -1)
        fi
        memory=$(util_getNearestPower2 $memory)
        memory="${memory} ${gb}"
    else
        log_error "No memory listed on any nodes"
        memory=0
    fi

    hwspec="$hwspec, $memory RAM"

    ## Network
    local nw=
    local nwstr=$(echo "$sysinfo" | grep -A2 "Network Info" | grep -v Disk | grep NIC | sort -k2)
    if [ -n "$nwstr" ]; then
        local niccnt=$(echo "$nwstr" | wc -l)
        local nicpernode=$(echo "$niccnt/$numnodes" | bc)
        [ "$(( $niccnt % $numnodes ))" -ne "0" ] && log_warn "# of NICs do not match. Not a homogeneous cluster"
        local mtus=$(echo "$nwstr" | awk '{print $4}' | tr -d ',' | sort | uniq)
        if [ "$(echo $mtus | wc -w)" -gt "1" ]; then
            log_warn "MTUs on the NIC(s) are not same"
            mtus=$(echo "$mtus" | sort -nr | head -1)
        fi
        local nwsp=$(echo "$nwstr" | awk '{print $8}' | tr -d ',' | sort | uniq)
        if [ "$(echo $nwsp | wc -w)" -gt "1" ]; then
            log_warn "NIC(s) are of different speeds"
            nwsp=$(echo "$nwsp" | sort -nr | head -1)
        fi
        nw="${nicpernode} x ${nwsp}"
        [ "$mtus" -gt "1500" ] && nw="$nw (mtu : $mtus/jumbo frames)" || nw="$nw (mtu : $mtus)"
    fi
    
    hwspec="$hwspec, $nw"

    ## OS
    local os=
    local osstr=$(echo "$sysinfo" | grep -A2 "Machine Info" | grep OS | cut -d ':' -f2 | sed 's/^ //g')
    local oscnt=$(echo "$osstr" | wc -l)
    if [ -n "$osstr" ]; then 
        [ "$oscnt" -ne "$numnodes" ] && log_warn "No OS listed for few nodes"
        os=$(echo "$osstr" | awk '{print $1}' | sort | uniq)
        local ver=$(echo "$osstr" | awk '{print $2}' | sort | uniq | sort -nr | head -1)
        if [ "$(echo $os | wc -w)" -gt "1" ]; then
            log_warn "OS isn't same all node nodes. Not a homogeneous cluster"
            os=$(echo "$os" | sort | head -1)
        fi
        os="${os} ${ver}"
        sysspec="$sysspec, $os"
    else
        log_warn "No OS listed on any nodes"
    fi
    
    # Build MapR Spec

    ## Build & Patch
    local maprstr=$(echo "$sysinfo" | grep -A6 "MapR Info")
    if [ -n "$maprstr" ]; then 
        local maprverstr=$(echo "$maprstr" | grep Version |  cut -d':' -f2- | sed 's/^ //g')
        local maprver=$(echo "$maprverstr" | awk '{print $1}' | sort | uniq)
        local maprpver=$(echo "$maprverstr" | grep patch | awk '{print $2,$3}' | sort | uniq | head -1)
        if [ "$(echo $maprver | wc -w)" -gt "1" ]; then
            log_warn "Different versions of MapR installed."
            maprver=$(echo "$maprver" | sort -nr | head -1)
        fi
        [ -n "$maprpver" ] && maprver="$maprver $maprpver"

        local nummfs=$(echo "$maprstr" | grep "# of MFS" | cut -d':' -f2 | sed 's/^ //g' | sort | uniq )
        if [ "$(echo $nummfs | wc -w)" -gt "1" ]; then
             log_warn "Different # of MFS configured on nodes"
             nummfs=$(echo "$nummfs" | sort -nr | head -1)
        fi

        local numsps=$(echo "$maprstr" | grep "# of SPs" | awk '{print $5}' | sort | uniq )
        if [ "$(echo $numsps | wc -w)" -gt "1" ]; then
             log_warn "Different # of SPs configured on nodes"
             numsps=$(echo "$numsps" | sort -nr | head -1)
        fi
        
        local numdn=$(echo "$maprstr" | grep "mapr-fileserver" | wc -l)
        local numcldb=$(echo "$maprstr" | grep "mapr-cldb" | wc -l)
        local numtopo=$(echo "$maprstr" | grep "Topology" | awk '{print $3}' | sort | uniq)H
        if [ "$(echo $numtopo | wc -w)" -gt "1" ]; then
            numdn=$(echo "$maprstr" | grep "Topology" | awk '{print $3}' | sort | uniq -c | sort -nr | head -1 | awk '{print $1}')
        fi
        maprspec="$numnodes nodes ($numcldb CLDB, $numdn Data), $nummfs MFS, $numsps SP, $maprver"
    fi

    ## Print specifications
    echo
    log_msghead "Cluster Specs : "
    log_msg "\t H/W   : $hwspec"
    log_msg "\t Nodes : $sysspec"
    [ -n "$maprspec" ] && log_msg "\t MapR  : $maprspec" 
    return 0
}

function maprutil_applyLicense(){
    
    wget http://stage.mapr.com/license/LatestDemoLicense-M7.txt --user=maprqa --password=maprqa -O /tmp/LatestDemoLicense-M7.txt > /dev/null 2>&1
    local buildid=$(maprutil_getBuildID)
    local i=0
    local jobs=1
    while [ "${jobs}" -ne "0" ]; do
        log_info "[$(util_getHostIP)] Waiting for CLDB to come up before applying license.... sleeping 10s"
        if [ "$jobs" -ne 0 ]; then
            local licenseExists=`timeout 30 /opt/mapr/bin/maprcli license list 2>/dev/null | grep M7 | wc -l`
            if [ "$licenseExists" -ne 0 ]; then
                jobs=0
            else
                sleep 10
            fi
        fi
        ### Attempt using Downloaded License
        if [ "${jobs}" -ne "0" ]; then
            jobs=$(timeout 30 /opt/mapr/bin/maprcli license add -license /tmp/LatestDemoLicense-M7.txt -is_file true > /dev/null;echo $?);
        fi
        let i=i+1
        if [ "$i" -gt 30 ]; then
            log_error "Failed to apply license. Node may not be configured correctly"
            exit 1
        fi
        if [[ -n "$GLB_SECURE_CLUSTER" ]] && [[ ! -e "/tmp/maprticket_0" ]]; then
            echo 'mapr' | maprlogin password  2>/dev/null
            echo 'mapr' | su mapr -c 'maprlogin password' 2>/dev/null
        fi
    done

    if [[ "${jobs}" -eq "0" ]] && [[ -n "$GLB_HAS_FUSE" ]]; then
        mkdir -p /fusemnt > /dev/null 2>&1
        local clusterid=$(timeout 30 maprcli dashboard info -json 2>/dev/null | grep -A5 cluster | grep id | tr -d '"' | tr -d ',' | cut -d':' -f2)
        local expdate=$(date -d "+30 days" +%Y-%m-%d)
        local licfile="/tmp/LatestFuseLicensePlatinum.txt"
        curl -F 'username=maprmanager' -F 'password=maprmapr' -X POST --cookie-jar /tmp/tmpckfile https://apitest.mapr.com/license/authenticate/ 2>/dev/null
        curl --cookie /tmp/tmpckfile -X POST -F "license_type=additionalfeatures_posixclientplatinum" -F "cluster=${clusterid}" -F "customer_name=maprqa" -F "expiration_date=${expdate}" -F "number_of_nodes=${GLB_CLUSTER_SIZE}" -F "enforcement_type=HARD" https://apitest.mapr.com/license/licenses/createlicense/ -o ${licfile} 2>/dev/null
        [ -e "$licfile" ] && timeout 30 /opt/mapr/bin/maprcli license add -license ${licfile} -is_file true > /dev/null
    fi
    [[ "${jobs}" -eq "0" ]] && log_info "[$(util_getHostIP)] License has been applied."
}

function maprutil_waitForCLDBonNode(){
    local node=$1
    
    local scriptpath="$RUNTEMPDIR/waitforcldb_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_waitForCLDB" >> $scriptpath
   
    local result=$(ssh_executeScriptasRoot "$node" "$scriptpath")
    
    if [ -n "$result" ]; then
        echo "$result"
    fi
}

function maprutil_waitForCLDB() {
    local rc=1;
    local iter=0;
    local iterlimit=9
    while [ "$rc" -gt 0 ] && [ "$iter" -lt "$iterlimit" ]; do
        rc=0;
        timeout 10 maprcli node cldbmaster -json > /dev/null 2>&1
        let rc=$rc+`echo $?`
        [ "$rc" -gt "0" ] && sleep 10;
        let iter=$iter+1;
    done
    if [ "$iter" -lt "$iterlimit" ]; then
        echo "ready"
    fi
}

function maprutil_setGatewayNodes(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local clsname=$1
    local gwnodes=$2

    if [ -n "$(maprutil_waitForCLDB)" ]; then
        timeout 10 maprcli cluster gateway set -dstcluster $clsname -gateways "$gwnodes" > /dev/null 2>&1
    else
        log_warn "[$(util_getHostIP)] Failed to set gateway nodes[$gwnodes] for cluster $clsname"
    fi
}

function maprutil_mountSelfHosting(){
    local ismounted=$(mount | grep -Fw "10.10.10.20:/mapr/selfhosting/")
    [ -n "$ismounted" ] && return
    for i in $(mount | grep "/mapr/selfhosting/" | cut -d' ' -f3)
    do
        timeout 20 umount -l $i > /dev/null 2>&1
    done

    [ ! -d "/home/MAPRTECH" ] && mkdir -p /home/MAPRTECH > /dev/null 2>&1
    log_info "[$(util_getHostIP)] Mounting selfhosting on /home/MAPRTECH"
    timeout 20 mount -t nfs 10.10.10.20:/mapr/selfhosting/ /home/MAPRTECH  > /dev/null 2>&1
}

function maprutil_checkClusterSetup(){
    if [ -z "$1" ]; then
        return
    fi

    local cldbnode="$1"
    local bins="$2"
    local javapids=$(su mapr -c jps)
    local installedbins=$(util_getInstalledBinaries "mapr-")

    [ -n "$(echo $installedbins | grep mapr-fluentd)" ] && [ -z "$(echo $bins | grep mapr-fluentd)" ] && bins="$bins mapr-fluentd"
    [ -n "$(echo $installedbins | grep mapr-collectd)" ] && [ -z "$(echo $bins | grep mapr-collectd)" ] && bins="$bins mapr-collectd"
    [ -n "$(echo $installedbins | grep mapr-kibana)" ] && [ -z "$(echo $bins | grep mapr-kibana)" ] && bins="$bins mapr-kibana"
    [ -n "$(echo $installedbins | grep mapr-grafana)" ] && [ -z "$(echo $bins | grep mapr-grafana)" ] && bins="$bins mapr-grafana"
    [ -n "$(echo $installedbins | grep mapr-elasticsearch)" ] && [ -z "$(echo $bins | grep mapr-elasticsearch)" ] && bins="$bins mapr-elasticsearch"
    [ -n "$(echo $installedbins | grep mapr-opentsdb)" ] && [ -z "$(echo $bins | grep mapr-opentsdb)" ] && bins="$bins mapr-opentsdb"
    
    # Check if configure for different CLDB node
    local cldbconf=$(cat /opt/mapr/conf/mapr-clusters.conf 2>/dev/null | head -1 | grep $cldbnode)
    [ -z "$cldbconf" ] && log_errormsg "Node configured with different CLDB IP"

    # Check if binaries are installed on the cluster
    local roles=$(ls /opt/mapr/roles/ 2>/dev/null)
    for binary in ${bins[@]}
    do
        [ -z "$(util_getInstalledBinaries $binary)" ] && log_errormsg "Package '$binary' NOT installed"
        [[ "${binary}" =~ mapr-hbase|mapr-client|mapr-patch|mapr-asynchbase|mapr-posix|mapr-loopbacknfs|mapr-kafka ]] && continue
        [ -z "$(echo $roles | grep $(echo $binary | cut -d'-' -f2))" ] && log_errormsg "Role '$(echo $binary | cut -d'-' -f2)' not configured"
    done

    # Check if Zk node & is running
    if [ -n "$(echo $bins | grep zookeeper)" ]; then
        local zkpid=$(ps -ef | grep -i [o]rg.apache.zookeeper.server.quorum.QuorumPeerMain | awk '{print $2}')
        [ -z "$zkpid" ] && zkpid=$(echo "$javapids" | grep QuorumPeerMain | awk '{print $1}')
        [ -z "$zkpid" ] && log_errormsg "Zookeeper is not running"
        local zkok="$(echo ruok | nc 127.0.0.1 5181)"
        [ "$zkok" != "imok" ] && log_errormsg "Zookeeper is not OK"
    fi

    # Check if CLDB node & is running
    if [ -n "$(echo $bins | grep cldb)" ]; then
        local cldbpid=$(ps -ef | grep [c]om.mapr.fs.cldb.CLDB | awk '{print $2}')
        [ -z "$cldbpid" ] && cldbpid=$(echo "$javapids" | grep CLDB | awk '{print $1}')
        if [ -n "$cldbpid" ]; then
            local cldbstatus=$(cat /proc/$cldbpid/stat 2>/dev/null | awk '{print $3}')
            [ "$cldbstatus" = "D" ] && log_errormsg "CLDB($cldbpid) is running in uninterruptible state. Possibly dead!"
        else
            log_errormsg "CLDB process is not running"
        fi
    fi

    # Check if node is configure with the same set of cldb nodes
    if [ -n "$(echo $bins | grep fileserver)" ]; then
        local mfspid=$(ps -ef | grep [/]opt/mapr/server/mfs | awk '{print $2}')
        if [ -n "$mfspid" ]; then
            local mfsstatus=$(cat /proc/$mfspid/stat 2>/dev/null | awk '{print $3}')
            [ "$mfsstatus" = "D" ] && log_errormsg "MFS ($mfspid) is running in uninterruptible state. Possibly dead!"
        else
            log_errormsg "MFS is not running on the node"
        fi
    fi

    # Remove client roles from 
    if [ -n "$(echo $roles | grep 'hbinternal\|asynchbase\|loopbacknfs\|kafka')" ]; then
        roles=$(echo $roles | sed 's/hbinternal//g;s/asynchbase//g;s/loopbacknfs//g;s/kafka//g')
    fi
    roles=$(echo $roles | xargs)

    # Check if warden is up and running
    if [ -n "$$roles" ]; then
        local wpid=$( ps -ef | grep [c]om.mapr.warden.WardenMain | awk '{print $2}')
        [ -z "$wpid" ] && wpid=$(echo "$javapids" | grep WardenMain | awk '{print $1}')
        [ -z "$wpid" ] && log_errormsg "Warden is not running on the node"
        local maprpids=$(ps -u mapr -Oppid | grep -v 'TTY\|hoststats\|initaudit.sh\|createsystemvolumes' | awk '{if($2==1) print $1}' | tr '\n' ' ')
        local numpids=$(echo $maprpids | wc -w)
        
        # Subtract one for warden process
        numpids=$(echo $numpids-1|bc)
        [ "$numpids" -gt "$(echo $roles | wc -w)" ] && log_warnmsg "One or more/few process is running under mapr user than configured roles"

        for maprpid in ${maprpids[@]}
        do
            local pidstatus=$(cat /proc/$maprpid/stat 2>/dev/null | awk '{print $3}')
            [ "$pidstatus" = "D" ] && log_errormsg "MapR process($maprpid) is running in uninterruptible state. Possibly dead!"
        done
    fi

    
}

function maprutil_checkClusterSetupOnNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi

    local hostnode=$1
    local cldbnode=$2
    local bins="$3"

    local scriptpath="$RUNTEMPDIR/checksetuponnode_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_checkClusterSetup \"$cldbnode\" \"$bins\"" >> $scriptpath
   
    local result=$(ssh_executeScriptasRoot "$hostnode" "$scriptpath")
    
    if [ -n "$result" ]; then
        echo "$result"
    fi
}

# @param nodelist
# @param rolefile
function maprutil_checkClusterSetupOnNodes(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi

    local maprnodes=$1
    local rfile=$2
    local cldbnodes=$(maprutil_getCLDBNodes "$rfile")
    local cldbnode=$(util_getFirstElement "$cldbnodes")

    local tmpdir="$RUNTEMPDIR/setupcheck"
    mkdir -p $tmpdir 2>/dev/null
    for node in ${maprnodes[@]}
    do
        local nodelog="$tmpdir/$node.log"
        local bins=$(maprutil_getNodeBinaries "$rfile" "$node")
        maprutil_checkClusterSetupOnNode "$node" "$cldbnode" "$bins" > $nodelog 2>&1 &
        maprutil_addToPIDList "$!"
    done
    maprutil_wait > /dev/null 2>&1

    local rc=0
    for node in ${maprnodes[@]}
    do
        local nodelog=$(cat $tmpdir/$node.log)
        if [ -n "$nodelog" ]; then
            log_msg " $node : "
            echo "$nodelog"
            local errors=$(echo "$nodelog" | grep ERROR)
            [ -n "$errors" ] && rc=1
        fi
    done
    [ "$rc" -eq "0" ] && log_msg "\tALL OK (phew!)"
    return $rc
}

## @param optional hostip
## @param rolefile
function maprutil_restartWardenOnNode() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local node=$1
    local rolefile=$2
    local stopstart=$3

     # build full script for node
    local scriptpath="$RUNTEMPDIR/restartonnode_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    if [ -n "$(maprutil_isClientNode $rolefile $node)" ]; then
        return
    fi
    
    echo "maprutil_restartWarden \"$stopstart\"" >> $scriptpath
    echo "service mapr-posix-client-platinum \"$stopstart\" > /dev/null 2>&1" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"   
}

## @param stop/start/restart
function maprutil_restartWarden() {
    local stopstart=$1
    local execcmd=
    if [[ -e "/etc/systemd/system/mapr-warden.service" ]]; then
        execcmd="service mapr-warden"
    elif [[ -e "/etc/init.d/mapr-warden" ]]; then
        execcmd="/etc/init.d/mapr-warden"
    elif [[ -e "/opt/mapr/initscripts/mapr-warden" ]]; then
        log_warn "warden init scripts not configured on nodes"
        execcmd="/opt/mapr/initscripts/mapr-warden"
    else
        log_warn "No mapr-warden on node"
        return
    fi
        #statements
    if [[ "$stopstart" = "stop" ]]; then
        execcmd=$execcmd" stop"
    elif [[ "$stopstart" = "start" ]]; then
        execcmd=$execcmd" start"
    else
        execcmd=$execcmd" restart"
    fi

    bash -c "$execcmd"
}

## @param optional hostip
## @param rolefile
function maprutil_restartZKOnNode() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local rolefile=$2
    local stopstart=$3
    if [ -n "$(maprutil_isClientNode $rolefile $1)" ]; then
        return
    fi
    if [ -z "$stopstart" ]; then
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper restart" &
    elif [[ "$stopstart" = "stop" ]]; then
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper stop" &
    elif [[ "$stopstart" = "start" ]]; then
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper start" &
    fi
    maprutil_addToPIDList "$!" 
}

function maprutil_removemMapRPackages(){
   
    util_removeBinaries "mapr-"
}

# @param PID 
function maprutil_addToPIDList(){
    if [ -z "$1" ]; then
        return
    fi
    [ -z "$GLB_BG_PIDS" ] && GLB_BG_PIDS=()
    GLB_BG_PIDS+=($1)
}

function maprutil_wait(){
    #log_info "Waiting for background processes to complete [${GLB_BG_PIDS[*]}]"
    for((i=0;i<${#GLB_BG_PIDS[@]};i++)); do
        local pid=${GLB_BG_PIDS[i]}
        if ! kill -0 ${pid} 2>/dev/null; then 
        #    unset GLB_BG_PIDS[$i]
            continue
        fi
        wait $pid
        local errcode=$?
        if [ "$errcode" -ne "0" ] && [ "$errcode" -ne "130" ]; then
            log_warn "Child process [$pid] exited with errorcode : $errcode"
            [ -z "$GLB_EXIT_ERRCODE" ] && GLB_EXIT_ERRCODE=$errcode
        fi
        #unset GLB_BG_PIDS[$i]
    done
    GLB_BG_PIDS=()
}

# @param timestamp
function maprutil_zipDirectory(){
    local timestamp=$1
    local fileregex=$2

    local tmpdir="/tmp/maprlogs/$(hostname -f)/"
    local logdir="/opt/mapr/logs"
    local drilllogdir="$(find  /opt/mapr/drill -name logs -type d  2>/dev/null)"
    local daglogdir="$(find  /opt/mapr/data-access-gateway -name logs -type d  2>/dev/null)"
    local buildid=$(cat /opt/mapr/MapRBuildVersion)
    local tarfile="maprlogs_$(hostname -f)_$buildid_$timestamp.tar.bz2"

    mkdir -p $tmpdir > /dev/null 2>&1
    # Copy configurations files 
    maprutil_copyConfsToDir "$tmpdir"
    # Copy the logs
    cd $tmpdir
    if [ -z "$fileregex" ]; then
        cp -r $logdir logs  > /dev/null 2>&1
    elif [ -n "$(ls $logdir/$fileregex 2> /dev/null)" ]; then
        mkdir -p logs  > /dev/null 2>&1
        cp -r $logdir/$fileregex logs > /dev/null 2>&1
    fi
    if [ -n "$drilllogdir" ]; then 
        mkdir -p drilllogs > /dev/null 2>&1
        cp -r $drilllogdir/drillbit.* drilllogs > /dev/null 2>&1
    fi
    if [ -n "$daglogdir" ]; then 
        mkdir -p daglogs > /dev/null 2>&1
        cp -r $daglogdir daglogs > /dev/null 2>&1
    fi
    local dirstotar=$(echo $(ls -d */))
    #tar -cjf $tarfile $dirstotar > /dev/null 2>&1
    tar -cf $tarfile --use-compress-prog=pbzip2 $dirstotar > /dev/null 2>&1
    rm -rf $dirstotar > /dev/null 2>&1
}

function maprutil_copyConfsToDir(){
    if [ -z "$1" ]; then
        return
    fi
    local todir="$1/conf"
    mkdir -p $todir > /dev/null 2>&1

    [ -e "/opt/mapr/conf" ] && cp -r /opt/mapr/conf $todir/mapr-conf/ > /dev/null 2>&1
    for i in $(ls -d /opt/mapr/hadoop/hadoop-*/ 2>/dev/null)
    do
        i=${i%?};
        local hv=$(echo "$i" | rev | cut -d '/' -f1 | rev)
        [ -e "$i/conf" ] && cp -r $i/conf $todir/$hv-conf/ > /dev/null 2>&1
        [ -e "$i/etc/hadoop" ] && cp -r $i/conf $todir/$hv-conf/ > /dev/null 2>&1
    done

    for i in $(ls -d /opt/mapr/hbase/hbase-*/ 2>/dev/null)
    do
        i=${i%?};
        local hbv=$(echo "$i" | rev | cut -d '/' -f1 | rev)
        [ -e "$i/conf" ] && cp -r $i/conf $todir/$hbv-conf/ > /dev/null 2>&1
    done
}

# @param host ip
# @param timestamp
function maprutil_zipLogsDirectoryOnNode(){
    if [ -z "$1" ]; then
        return
    fi

    local node=$1
    local timestamp=$2
    local fileregex=$3
    
    local scriptpath="$RUNTEMPDIR/zipdironnode_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_zipDirectory \"$timestamp\" \"$fileregex\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"
}


# @param host ip
# @param local directory to copy the zip file
function maprutil_copyZippedLogsFromNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        log_warn "Incorrect or null arguments. Ignoring copy of the files"
        return
    fi

    local node=$1
    local timestamp=$2
    local copyto=$3
    mkdir -p $copyto > /dev/null 2>&1
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local filetocopy="/tmp/maprlogs/$host/*$timestamp.tar.bz2"
    
    [ -n "$host" ] && [ -d "$copyto/$host" ] && rm -rf $copyto/$host > /dev/null 2>&1
    ssh_copyFromCommand "root" "$node" "$filetocopy" "$copyto" > /dev/null 2>&1
    ssh_executeCommandasRoot "$node" "rm -rf $filetocopy" > /dev/null 2>&1
}

function maprutil_copyprocesstrace(){
    local node=$1
    local timestamp=$2
    local copyto=$3
    mkdir -p $copyto > /dev/null 2>&1
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local dirtocopy="/tmp/maprtrace/$timestamp/$host"

    [ -n "$host" ] && [ -d "$copyto/$host" ] && rm -rf $copyto/$host > /dev/null 2>&1
    ssh_copyFromCommand "root" "$node" "$dirtocopy" "$copyto" > /dev/null 2>&1
    ssh_executeCommandasRoot "$node" "rm -rf $dirtocopy" > /dev/null 2>&1
}

function maprutil_processtraceonNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi

    local node=$1
    local timestamp=$2
    local iter=$3
    
    local scriptpath="$RUNTEMPDIR/mfsrtace_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_processtrace \"$timestamp\" \"$iter\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_processtrace(){
    local timestamp=$1
    local iter=$2
    local pname="$GLB_TRACE_PNAME"
    local isjava=

    [ -z "$pname" ] && [ ! -e "/opt/mapr/roles/fileserver" ] && return
    [ -n "$pname" ] && [ -n "$(jps 2>/dev/null | grep $pname)" ] && isjava=1
    [ -z "$pname" ] && pname="mfs"
    
    local ppid=$(pidof $pname)
    [ -n "$isjava" ] && ppid=$(jps 2>/dev/null | grep $pname | awk '{print $1}')
    [ -z "$ppid" ] && return
    [ -z "$iter" ] && iter=10
    
    local tmpdir="/tmp/maprtrace/$timestamp/$(hostname -f)"
    mkdir -p $tmpdir > /dev/null 2>&1

    for i in $(seq $iter)
    do
        local tracefile="$tmpdir/${pname}_trace_$(date '+%Y-%m-%d-%H-%M-%S')"
        command -v gstack >/dev/null 2>&1 && gstack $ppid > $tracefile || gdb -ex "t a a bt" --batch -p $ppid  | grep -v "^\[New" > $tracefile
        [ -n "$isjava" ] && jstack $ppid > ${tracefile}_jstack
        sleep 1
    done
}

function maprutil_mfsthreads(){
    [ ! -e "/opt/mapr/roles/fileserver" ] && return
    local mfspid=$(pidof mfs)
    [ -z "$mfspid" ] && log_warn "[$(util_getHostIP)] No MFS running to list it's threads" && return
    [ -n "$(ls /opt/mapr/logs/*mfs*.gdbtrace 2>/dev/null)" ] && log_warn "[$(util_getHostIP)] MFS has previously crashed. Thread IDs may not match"

    local types="CpuQ_IOMgr CpuQ_FS CpuQ_Compress CpuQ_DBMain CpuQ_DBHelper CpuQ_DBFlush CpuQ_SysCalls CpuQ_Rpc CpuQ_ExtInstance"
    local mfsgstack="/opt/mapr/logs/$mfspid.gstack"
    local mfstrace=

    if [ -s "$mfsgstack" ] && [ -n "$(cat $mfsgstack | grep CpuQ_FS)" ]; then
        mfstrace=$(cat $mfsgstack) 
    else
        #mfstrace=$(gstack $mfspid | sed '1!G;h;$!d')
        mfstrace=$(command -v gstack >/dev/null 2>&1 && gstack $mfspid | sed '1!G;h;$!d' || gdb -ex "t a a bt" --batch -p $mfspid  | grep -v "^\[New" | sed '1!G;h;$!d')
        echo "$mfstrace" > $mfsgstack
    fi
    echo
    log_msg "$(util_getHostIP): MFS ($mfspid) thread id(s)"
    for type in $types
    do
        local ids=$(echo "$mfstrace" | grep -e "$type" -e "^Thread" | grep -A1 "$type" | grep -o "LWP [0-9]*" | awk '{print $2}' | sort -n | sed ':a;N;$!ba;s/\n/,/g')
        [ -n "$ids" ] && log_msg "\t${type}: $ids"
    done
}

function maprutil_publishMFSCPUUse(){
    [ -z "$GLB_PERF_URL" ] && return

    local logdir="$1"
    local timestamp="$2"
    local hostlist="$3"
    local buildid="$4"
    local desc="$5"

    [ -z "$desc" ] && desc="${buildid}-${timestamp}"

    pushd $logdir > /dev/null 2>&1

    local json="{"
    json="$json\"timestamp\":$timestamp,\"nodes\":\"$hostlist\",\"driver\":\"$(util_getHostIP)\""
    json="$json,\"build\":\"$buildid\",\"description\":\"$desc\""

    log_info "Publishing resource usage statistics to \"$GLB_PERF_URL\""

    local sjson=
    local stjson=
    local tjson=
    local ttime=0
    local files="fs.log db.log dbh.log dbf.log fs_max.log db_max.log dbh_max.log dbf_max.log"
    for fname in $files
    do
        [ ! -s "$fname" ] && continue
        local tlog=$(cat $fname | awk 'BEGIN{printf("["); i=1} { if(i!=1) printf(","); printf("%s",$1); i++} END{printf("]")}')
        [ -n "$tjson" ] && tjson="$tjson,"
        # tlog=$(echo $tlog | python -c 'import json,sys; print json.dumps(sys.stdin.read())')
        tjson="$tjson\"$(echo $fname| cut -d'.' -f1)\":$tlog"
        [ "$ttime" -lt "$(cat $fname | wc -l)" ] && ttime=$(cat $fname | wc -l)

        [ -n "$(echo $fname | grep "max")" ] && continue
        local avg=$(cat $fname | awk '{sum+=$1}END{print sum/NR}')
        local stddev=$(util_getStdDev "$(cat $fname)")
        [ -n "$stjson" ] && stjson="$stjson,"
        stjson="$stjson\"$(echo $fname| cut -d'.' -f1)\":{\"avg\":$avg,\"stddev\":$stddev}"
    done
    [ -n "$tjson" ] && tjson="{\"maxcount\":$ttime,$tjson}" && tjson=$(echo $tjson | python -c 'import json,sys; print json.dumps(sys.stdin.read())')
    [ -n "$tjson" ] && json="$json,\"threads\":$tjson"
    [ -n "$stjson" ] && sjson="\"threads\":{$stjson}" && stjson=

    ttime=0
    local files="Rpc.log IOMgr.log FS.log DBMain.log DBHelper.log DBFlush.log Compress.log SysCalls.log ExtInstance.log Rpc_max.log IOMgr_max.log FS_max.log DBMain_max.log DBHelper_max.log DBFlush_max.log Compress_max.log SysCalls_max.log ExtInstance_max.log"
    for fname in $files
    do
        [ ! -s "$fname" ] && continue
        local tlog=$(cat $fname | awk 'BEGIN{printf("["); i=1} { if(i!=1) printf(","); printf("%s",$1); i++} END{printf("]")}')
        [ -n "$tjson" ] && tjson="$tjson,"
        tjson="$tjson\"$(echo $fname| cut -d'.' -f1)\":$tlog"
        [ "$ttime" -lt "$(cat $fname | wc -l)" ] && ttime=$(cat $fname | wc -l)

        [ -n "$(echo $fname | grep "max")" ] && continue
        local avg=$(cat $fname | awk '{sum+=$1}END{print sum/NR}')
        local stddev=$(util_getStdDev "$(cat $fname)")
        [ -n "$stjson" ] && stjson="$stjson,"
        stjson="$stjson\"$(echo $fname| cut -d'.' -f1)\":{\"avg\":$avg,\"stddev\":$stddev}"
    done
    [ -n "$tjson" ] && tjson="{\"maxcount\":$ttime,$tjson}" && tjson=$(echo $tjson | python -c 'import json,sys; print json.dumps(sys.stdin.read())')
    [ -n "$tjson" ] && json="$json,\"threads\":$tjson"
    [ -n "$sjson" ] && sjson="$sjson,"
    [ -n "$stjson" ] && sjson="$sjson\"threads\":{$stjson}" && stjson=


    # add MFS & GW cpu
    files="mfs.log gw.log client.log qs.log dag.log tsdb.log"
    tjson=
    for fname in $files
    do
        [ ! -s "$fname" ] && continue
        local mlog=$(cat $fname | awk 'BEGIN{printf("["); i=0} { if(i==0) printf("{\"ts\":\"%s %s\",\"mem\":%s,\"cpu\":%s}",$1,$2,$3,$4); else printf(",{\"mem\":%s,\"cpu\":%s}",$3,$4); i++; } END{printf("]")}')
        [ -n "$tjson" ] && tjson="$tjson,"
        mlog=$(echo $mlog | python -c 'import json,sys; print json.dumps(sys.stdin.read())')
        tjson="$tjson\"$(echo $fname| cut -d'.' -f1)\":$mlog"

        local mavg=$(cat $fname | awk '{sum+=$3;}END{print sum/NR}')
        local cavg=$(cat $fname | awk '{sum+=$4;}END{print sum/NR}')
        local mstddev=$(util_getStdDev "$(cat $fname | awk '{print $3}')")
        local cstddev=$(util_getStdDev "$(cat $fname | awk '{print $4}')")
        [ -n "$stjson" ] && stjson="$stjson,"
        stjson="$stjson\"$(echo $fname| cut -d'.' -f1)\":{\"mem\":{\"avg\":$mavg,\"stddev\":$mstddev},\"cpu\":{\"avg\":$mavg,\"stddev\":$mstddev}}"
    done
    [ -n "$tjson" ] && json="$json,$tjson"
    [ -n "$sjson" ] && sjson="$sjson,"
    [ -n "$stjson" ] && sjson="${sjson}${stjson}" && stjson=

    files="cpu.log"
    tjson=
    for fname in $files
    do
        [ ! -s "$fname" ] && continue
        local mlog=$(cat $fname | awk 'BEGIN{printf("["); i=0} { if(i==0) { cmd="date \"+%Y-%m-%d %H:%M:%S\" -d \""$1" "$2"\""; cmd | getline var; close(cmd); printf("{\"ts\":\"%s\",\"pcpu\":%s}",var,$3) } else printf(",{\"pcpu\":%s}",$3);  i++;} END{printf("]")}')
        [ -n "$tjson" ] && tjson="$tjson,"
        mlog=$(echo $mlog | python -c 'import json,sys; print json.dumps(sys.stdin.read())')
        tjson="$tjson\"$(echo $fname| cut -d'.' -f1)\":$mlog"
    done
    [ -n "$tjson" ] && json="$json,$tjson"

    files="disks.log"
    tjson=
    for fname in $files
    do
        [ ! -s "$fname" ] && continue
        local mlog=$(cat $fname | awk 'BEGIN{printf("["); i=0} { if(i==0) { cmd="date \"+%Y-%m-%d %H:%M:%S\" -d \""$1" "$2"\""; cmd | getline var; close(cmd); printf("{\"ts\":\"%s\",\"pcpu\":%s,\"max\":%s}",var,$3,$4) } else printf(",{\"pcpu\":%s,\"max\":%s}",$3,$4);  i++;} END{printf("]")}')
        [ -n "$tjson" ] && tjson="$tjson,"
        mlog=$(echo $mlog | python -c 'import json,sys; print json.dumps(sys.stdin.read())')
        tjson="$tjson\"$(echo $fname| cut -d'.' -f1)\":$mlog"
    done
    [ -n "$tjson" ] && json="$json,$tjson"

    files="net.log"
    tjson=
    for fname in $files
    do
        [ ! -s "$fname" ] && continue
        local mlog=$(cat $fname | awk 'BEGIN{printf("["); i=0} { if(i==0) printf("{\"ts\":\"%s %s\",\"rx\":%s,\"tx\":%s}",$1,$2,$3,$4); else { printf(",{\"rx\":%s,\"tx\":%s}",$3,$4); }  i++; } END{printf("]")}')
        [ -n "$tjson" ] && tjson="$tjson,"
        mlog=$(echo $mlog | python -c 'import json,sys; print json.dumps(sys.stdin.read())')
        tjson="$tjson\"$(echo $fname| cut -d'.' -f1)\":$mlog"
    done
    [ -n "$tjson" ] && json="$json,$tjson"
    [ -n "$sjson" ] && sjson=$(echo "{$sjson}" | python -c 'import json,sys; print json.dumps(sys.stdin.read())') && sjson="\"stats\":$sjson"
    [ -n "$sjson" ] && json="$json,$sjson"

    json="$json}"
    json="cpuuse=$json"
    #echo $json > cpuuse.json
    local tmpfile=$(mktemp)
    echo "$json" > $tmpfile
    local fsize=$(echo "$(stat -c %s $tmpfile)/(1024*1024)" | bc )
    [[ "$fsize" -ge "20" ]] && log_warn "Publish may fail as aggregated log file size (${fsize}MB) is >20MB. Reduce the size by limiting the time range"
    curl -L -X POST --data @- ${GLB_PERF_URL} < $tmpfile > /dev/null 2>&1
    # TODO : Print URL
    rm -f $tmpfile > /dev/null 2>&1
    popd > /dev/null 2>&1
}

function maprutil_mfsCPUUseOnCluster(){
    local allnodes="$1"
    local nodes="$2"
    local tmpdir="$3"
    local timestamp="$4"
    local publish="$5"

    local hostlist=
    local buildid=
    local patchid=
    local dirlist=
    local alldirlist=
    for node in ${allnodes[@]}
    do
        local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
        [ ! -d "$tmpdir/$host/" ] && log_error "Incomplete logs; '$host' logs are missing. Exiting!" && return
        [ -n "$(echo $nodes | grep -w $node)" ] && dirlist="$dirlist $tmpdir/$host/" && hostlist="$hostlist $node"
        alldirlist="$alldirlist $tmpdir/$host/"
        [ -z "$buildid" ] && buildid=$(ssh_executeCommandasRoot "$node" "cat /opt/mapr/MapRBuildVersion")
        [ -z "$patchid" ] && patchid=$(ssh_executeCommandasRoot "$node" "ls /opt/mapr/.patch/README.* | cut -d '.' -f3 | tr -d 'p'" 2>/dev/null)
    done
    [ -n "$buildid" ] && [ -n "$patchid" ] && buildid="$buildid (patch $patchid)"
    [ -z "$(echo $dirlist | grep "$tmpdir")" ] && return
    [ -z "$(ls $tmpdir/* 2>/dev/null)" ] && return
    local logdir="$tmpdir/cluster"
    rm -rf $logdir > /dev/null 2>&1
    mkdir -p $logdir > /dev/null 2>&1
    log_info "Aggregating MFS stats from nodes [ $nodes ]"

    local files="fs.log db.log dbh.log dbf.log comp.log"
    for fname in $files
    do
        local filelist=$(find $dirlist -name $fname 2>/dev/null)
        [ -n "$filelist" ] && paste $filelist | awk '{for(i=1;i<=NF;i++) sum+=$i; printf("%.0f\n", sum/NF); sum=0}' > $logdir/$fname 2>&1 &
    done

    files="Rpc IOMgr FS DBMain DBHelper DBFlush Compress SysCalls ExtInstance"
    for fname in $files
    do
        local filelist=$(find $dirlist -name "${fname}.log" 2>/dev/null)
        local maxfilelist=$(find $dirlist -name "${fname}_max.log" 2>/dev/null)
        [ -n "$filelist" ] && paste $filelist | awk '{for(i=1;i<=NF;i++) sum+=$i; printf("%.0f\n", sum/NF); sum=0}' > $logdir/${fname}.log 2>&1 &
        [ -n "$maxfilelist" ] && paste $maxfilelist | awk '{for(i=1;i<=NF;i++) { if($i>max) max=$i; } printf("%.0f\n", max); max=0}' > $logdir/${fname}_max.log 2>&1 &
    done

    files="fs_max.log db_max.log dbh_max.log dbf_max.log comp_max.log"
    for fname in $files
    do
        local filelist=$(find $dirlist -name $fname 2>/dev/null)
        [ -n "$filelist" ] && paste $filelist | awk '{for(i=1;i<=NF;i++) { if($i>max) max=$i; } printf("%.0f\n", max); max=0}' > $logdir/$fname 2>&1 &
    done
    wait

    files="mfs.log"
    for fname in $files
    do
        local filelist=$(find $dirlist -name $fname 2>/dev/null)
        [ -n "$filelist" ] && paste $filelist | awk '{for(i=3;i<=NF;i+=4) {msum+=$i; k=i+1; csum=$k; j++} printf("%s %s %.3f %.0f\n",$1,$2,msum/j,csum/j); msum=0; csum=0; j=0}' > $logdir/$fname 2>&1 &
    done
    files="cpu.log"
    for fname in $files
    do
        local filelist=$(find $dirlist -name $fname 2>/dev/null)
        [ -n "$filelist" ] && paste $filelist | awk '{for(i=3;i<=NF;i+=3) {csum+=$i; j++} printf("%s %s %.0f\n",$1,$2,csum/j); csum=0; j=0}' > $logdir/$fname 2>&1 &
    done
    files="disks.log"
    for fname in $files
    do
        local filelist=$(find $dirlist -name $fname 2>/dev/null)
        [ -n "$filelist" ] && paste $filelist | awk '{for(i=3;i<=NF;i+=4) {sum+=$i; k=i+1; if($k>max) max=$k; j++} printf("%s %s %.0f %.0f\n",$1,$2,sum/j,max); sum=0; max=0; j=0}' > $logdir/$fname 2>&1 &
    done
    files="net.log"
    for fname in $files
    do
        local filelist=$(find $dirlist -name $fname 2>/dev/null)
        [ -n "$filelist" ] && paste $filelist | awk '{for(i=3;i<=NF;i+=4) {rsum+=$i; k=i+1; ssum+=$k; j++} printf("%s %s %.0f %.0f\n",$1,$2,rsum/j,ssum/j); rsum=0; ssum=0; j=0}' > $logdir/$fname 2>&1 &
    done
    # logs from all nodes, NOT just MFS/data nodes
    files="gw.log qs.log dag.log tsdb.log"
    for fname in $files
    do
        local filelist=$(find $alldirlist -name $fname 2>/dev/null)
        [ -n "$filelist" ] && paste $filelist | awk '{for(i=3;i<=NF;i+=4) {msum+=$i; k=i+1; csum=$k; j++} printf("%s %s %.3f %.0f\n",$1,$2,msum/j,csum/j); msum=0; csum=0; j=0}' > $logdir/$fname 2>&1 &
    done
    wait

    log_info "Aggregating client stats from nodes [ $allnodes ]"
    local clientst=
    local clientet=
    if [ -s "$logdir/mfs.log" ]; then
        clientst=$(head -1 $logdir/mfs.log | awk '{print $1,$2}')
        clientst=$(date +%s -d "$clientst")
        clientet=$(tail -1 $logdir/mfs.log | awk '{print $1,$2}')
        clientet=$(date +%s -d "$clientet")
    fi
    files="client.log"
    for fname in $files
    do
        local tmpclog=$(mktemp)
        local loglines=$(find $alldirlist -name $fname -exec cat {} \; 2>/dev/null | sort -n)
        [ -n "$loglines" ] && echo "$loglines" | sort -n | awk '{ts=$1" "$2; cnt[ts]+=1; cmem[ts]+=$3; ccpu[ts]+=$4} END {for (i in cnt) printf("%s %.2f %.0f\n",i,cmem[i]/cnt[i],ccpu[i]/cnt[i])}' | sort -n > $tmpclog
        while [[ -n "$clientst" ]] && [[ -s "$tmpclog" ]] && [[ "$clientst" -le "$clientet" ]];
        do
            echo "$(date -d "@$clientst" "+%Y-%m-%d %H:%M:%S") 0 0" >> $tmpclog
            clientst=$(date +%s -d "@$(($clientst+1))")
        done
        [ -s "$tmpclog" ] && cat $tmpclog | sort -n | awk '{ts=$1" "$2; cmem[ts]+=$3; ccpu[ts]+=$4} END {for (i in cmem) printf("%s %.2f %.0f\n",i,cmem[i],ccpu[i])}' | sort -n > $logdir/$fname
        rm -f $tmpclog > /dev/null 2>&1
    done

    [ -n "$GLB_PERF_URL" ] && maprutil_publishMFSCPUUse "$logdir" "$timestamp" "$hostlist" "$buildid" "$publish"

    pushd $tmpdir > /dev/null 2>&1
    local dirstotar=$dirlist
    if [ "$2" != "/tmp" ] || [ "$2" != "/tmp/" ]; then
        dirstotar=$(echo $(ls -d */))
    fi        
    tar -cf maprcpuuse_$timestamp.tar.bz2 --use-compress-prog=pbzip2 $dirstotar > /dev/null 2>&1

    util_createExtractFile

    [ "$dirstotar" != "$dirlist" ] && rm -rf $dirstotar > /dev/null 2>&1 
    popd > /dev/null 2>&1
}

function maprutil_copymfscpuuse(){
    local node=$1
    local timestamp=$2
    local copyto=$3
    mkdir -p $copyto > /dev/null 2>&1
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local dirtocopy="/tmp/mfscpuuse/$timestamp/$host"

    [ -n "$host" ] && [ -d "$copyto/$host" ] && rm -rf $copyto/$host > /dev/null 2>&1
    ssh_copyFromCommand "root" "$node" "$dirtocopy" "$copyto" > /dev/null 2>&1
    ssh_executeCommandasRoot "$node" "rm -rf $dirtocopy" > /dev/null 2>&1
}

function maprutil_mfsCpuUseOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi

    local node=$1
    local timestamp=$2
    local stime="$3"
    local etime="$4"
    
    local scriptpath="$RUNTEMPDIR/mfscpuuse_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_buildMFSCpuUse \"$timestamp\" \"$stime\" \"$etime\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_buildMFSCpuUse(){
    if [ -z "$1" ]; then
        return
    fi
    
    local timestamp="$1"
    local stime="$2"
    local etime="$3"
    local sl=
    local el=
    local stts=
    local etts=
    local cst=
    local cet=
    local invalidts=

    [ -n "$stime" ] && stime=$(date -d "$stime" "+%Y-%m-%d %H:%M") && stts=$(date -d "$stime" +%s)
    [ -n "$etime" ] && etime=$(date -d "$etime" "+%Y-%m-%d %H:%M") && etts=$(date -d "$etime" +%s)

    local tempdir="/tmp/mfscpuuse/$timestamp/$(hostname -f)"
    mkdir -p $tempdir > /dev/null 2>&1

    if ls /opt/mapr/logs/clientresusage_* 1> /dev/null 2>&1; then
        maprutil_buildClientUsage "$tempdir" "$stime" "$etime" &
    fi

    maprutil_buildResUsage "$tempdir" "$2" "$3" &

    local sysuse="/opt/mapr/logs/dstat.log"
    if [ -s "$sysuse" ]; then
        sl=1
        el=$(cat $sysuse | wc -l)
        stime="$2"
        etime="$3"
        local year=

        [ -n "$stime" ] && year=$(date -d "$stime" "+%Y") && stime=$(date -d "$stime" "+%d-%m %H:%M") 
        [ -n "$etime" ] && etime=$(date -d "$etime" "+%d-%m %H:%M")
        [ -n "$stime" ] && sl=$(cat $sysuse | grep -n "$stime" | cut -d':' -f1 | tail -1)
        [ -n "$etime" ] && el=$(cat $sysuse | grep -n "$etime" | cut -d':' -f1 | tail -1)
        if [ -n "$el" ] && [ -n "$sl" ]; then
            [ -z "$year" ] && year=$(date +%Y)
            sed -n ${sl},${el}p $sysuse | sed -e '/time/,+1d' | grep "^[0-9]" | tr '|' ' ' | awk -v y="$year" '{ r=$11; s=$12; if(r ~ /M/) {r=r*1;} else if(r ~ /k/) {r=r*1/1024} else if(r ~ /B/) {r=r*1/(1024*1024)} if(r ~ /M/) {s=s*1;} else if(s ~ /k/) {s=s*1/1024} else if(s ~ /B/) {s=s*1/(1024*1024)} split($1,d,"-"); printf("%s-%s-%s %s %.0f %.0f\n",y,d[2],d[1],$2,r,s)}' > $tempdir/net.log 2>&1 &
            sed -n ${sl},${el}p $sysuse | sed -e '/time/,+1d' | grep "^[0-9]" | tr '|' ' ' | awk -v y="$year" '{c=100-$5; split($1,d,"-"); printf("%s-%s-%s %s %.0f\n",y,d[2],d[1],$2,c)}' > $tempdir/cpu.log 2>&1 &
        fi
    fi
    wait

    local mfstop="/opt/mapr/logs/mfstop.log"
    [ -s "$mfstop" ] && maprutil_getMFSThreadUse "$tempdir" "$2" "$3"

    maprutil_getMFSThreadUseFromGuts "$tempdir" "$2" "$3" &
    
    if [ -s "/opt/mapr/logs/iostat.log" ]; then 
        maprutil_buildDiskUsage "$tempdir" "$2" "$3" &
    else
        log_warn "[$(util_getHostIP)] No disk stats available. Skipping disk usage stats"
    fi
    wait
}

maprutil_buildResUsage(){
    local tempdir="$1"
    local stime="$2"
    local etime="$3"

    [ -n "$stime" ] && stime=$(date -d "$stime" "+%Y-%m-%d %H:%M")
    [ -n "$etime" ] && etime=$(date -d "$etime" "+%Y-%m-%d %H:%M")

    local PROCLIST=( "/opt/mapr/logs/mfsresusage.log:mfs.log"
        "/opt/mapr/logs/gwresusage.log:gw.log"
        "/opt/mapr/logs/drillresusage.log:qs.log"
        "/opt/mapr/logs/dagresusage.log:dag.log"
        "/opt/mapr/logs/tsdbresusage.log:tsdb.log" )

    for proc in "${PROCLIST[@]}"
    do
        local resuse="${proc%%:*}"
        local plog="${proc##*:}"
        
        if [ -s "$resuse" ]; then
            local sl=1
            local el=$(cat $resuse | wc -l)
            local invalidts=

            local cst=$(sed -n 1p $resuse | awk '{print $1,$2}') && cst=$(date -d "$cst" +%s)
            local cet=$(tail -1 $resuse | awk '{print $1,$2}') && cet=$(date -d "$cet" +%s)

            [ -n "$stime" ] && sl=$(cat $resuse | grep -n "$stime" | cut -d':' -f1 | head -1)
            [ -n "$etime" ] && el=$(cat $resuse | grep -n "$etime" | cut -d':' -f1 | tail -1)
            
            if [ -z "$el" ] || [ -z "$sl" ]; then
                [[ -n "$etts" ]] && [[ "$etts" -lt "$cst" ]] && invalidts=1
                [[ -n "$stts" ]] && [[ "$stts" -gt "$cet" ]] && invalidts=1
                [ -z "$sl" ] && sl=1
                [ -z "$el" ] && el=$(cat $resuse | wc -l)
            fi 
            [ "$sl" -gt "$el" ] && el=$(cat $resuse | wc -l)
            if [ -z "$invalidts" ]; then
                sed -n ${sl},${el}p $resuse | awk '{r=$3; if(r ~ /g/) {r=r*1} else if(r ~ /t/) {r=r*1024} else if(r ~ /m/) {r=r/1024} else {r=r/1024/1024} printf("%s %s %.3f %s\n",$1,$2,r,$4)}' > $tempdir/$plog 2>&1 &
            fi
        fi
    done
    wait
}

maprutil_getMFSThreadUseFromGuts(){
    local gutsfile="/opt/mapr/logs/tguts.log"
    [ ! -s "$gutsfile" ] && return

    local tempdir="$1"
    local stime="$2"
    local etime="$3"
    
    local sl=1
    local el=$(cat $gutsfile | wc -l)

    [ -n "$stime" ] && stime=$(date -d "$stime" "+%Y-%m-%d %H:%M")
    [ -n "$etime" ] && etime=$(date -d "$etime" "+%Y-%m-%d %H:%M")
    [ -n "$stime" ] && sl=$(cat $gutsfile | grep -n "$stime" | cut -d':' -f1 | head -1)
    [ -n "$etime" ] && el=$(cat $gutsfile | grep -n "$etime" | cut -d':' -f1 | tail -1)

    [ -z "$el" ] || [ -z "$sl" ] && log_error "[$(util_getHostIP)] Start or End time not found in the tguts.log. Specify newer time range" && return
    [ "$sl" -gt "$el" ] && el=$(cat $gutsfile | wc -l)

    local gheader=$(grep '^[a-z]' $gutsfile | grep time | head -1 | sed 's/ \+/ /g' | tr ' ' '\n' | awk 'BEGIN{i=2}{ print i,$0; i++}' | grep "\[")
    local nummfsinst="$(echo "$gheader" | grep Rpc | awk '{print $2}' | cut -d ']' -f1 | sort | uniq | wc -l)"

    local threadtypes="Rpc IOMgr FS DBMain DBHelper DBFlush Compress SysCalls ExtInstance"

    for ((j=0; j < $nummfsinst ; j++))
    do
        local ji=$j
        [[ "$j" -lt "10" ]] && ji="0$j"
        for type in $threadtypes    
        do
            local logfile="$tempdir/mfs${j}_${type}.log"
            local colids="$(echo "$gheader" | grep $type | grep "\[$ji]" | awk '{print $1}' | sed ':a;N;$!ba;s/\n/ /g')"
            sed -n ${sl},${el}p $gutsfile | grep "^2" | awk -v var="$colids" 'BEGIN{split(var,cids," "); ncols=length(cids)} {for (i=1;i<=length(cids);i++) { sum+=$cids[i]; if($cids[i]>max) max=$cids[i] } printf("%d %d\n",sum/ncols, max); sum=0; max=0}' > $logfile 2>&1 &
        done
    done
    wait

    for type in $threadtypes    
    do
        local logfile="$tempdir/${type}.log"
        paste $tempdir/mfs*_${type}.log | awk '{for(i=1;i<=NF;i+=2) { sum+=$i; j++} printf("%d\n", sum/j); sum=0; j=0}' > $logfile 2>&1 &
        local maxlogfile="$tempdir/${type}_max.log"
        paste $tempdir/mfs*_${type}.log | awk '{for(i=2;i<=NF;i+=2) { if($i>max) max=$i } printf("%d\n", max); max=0}' > $maxlogfile 2>&1 &
    done
    wait
}

maprutil_getMFSThreadUse()
{
    local mfstop="/opt/mapr/logs/mfstop.log"
    [ ! -s "$mfstop" ] && return
    [ -n "$(ls /opt/mapr/logs/*mfs*.gdbtrace 2>/dev/null)" ] && log_warn "[$(util_getHostIP)] MFS has previously crashed. Thread IDs may not match"
    
    local mfsthreads=$(maprutil_mfsthreads | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g')
    [ -z "$(echo "$mfsthreads" | grep CpuQ)" ] && log_warn "[$(util_getHostIP)] MFS threadwise CPU will not be captured"

    local tempdir="$1"
    local stime="$2"
    local etime="$3"
    
    local sl=1
    local el=$(cat $mfstop | wc -l)

    [ -n "$stime" ] && stime=$(date -d "$stime" "+%Y-%m-%d %H:%M")
    [ -n "$etime" ] && etime=$(date -d "$etime" "+%Y-%m-%d %H:%M")
    [ -n "$stime" ] && sl=$(cat $mfstop | grep -n "$stime" | cut -d':' -f1 | head -1)
    [ -n "$etime" ] && el=$(cat $mfstop | grep -n "$etime" | cut -d':' -f1 | head -1)

    [ -z "$el" ] || [ -z "$sl" ] && log_error "[$(util_getHostIP)] Start or End time not found in the mfstop.log. Specify newer time range" && return
    [ "$sl" -gt "$el" ] && el=$(cat $mfstop | wc -l)

    local fsthreads="$(echo "$mfsthreads" | grep CpuQ_FS | awk '{print $2}' | sed 's/,/ /g')"
    for fsthread in $fsthreads
    do
        local fsfile="$tempdir/fs_$fsthread.log"
        sed -n ${sl},${el}p $mfstop | grep mfs | grep -w "$fsthread" | awk '{print $9}' > ${fsfile} 2>&1 &
    done
    
    local dbthreads="$(echo "$mfsthreads" | grep CpuQ_DBMain | awk '{print $2}' | sed 's/,/ /g')"
    for dbthread in $dbthreads
    do
        local dbfile="$tempdir/db_$dbthread.log"
        sed -n ${sl},${el}p $mfstop | grep mfs | grep -w "$dbthread" | awk '{print $9}' > ${dbfile} 2>&1 &
    done
    
    local dbhthreads="$(echo "$mfsthreads" | grep CpuQ_DBHelper | awk '{print $2}' | sed 's/,/ /g')"
    for dbhthread in $dbhthreads
    do
        local dbhfile="$tempdir/dbh_$dbhthread.log"
        sed -n ${sl},${el}p $mfstop | grep mfs | grep -w "$dbhthread" | awk '{print $9}' > ${dbhfile} 2>&1 &
    done
    
    local dbfthreads="$(echo "$mfsthreads" | grep CpuQ_DBFlush | awk '{print $2}' | sed 's/,/ /g')"
    for dbfthread in $dbfthreads
    do
        local dbffile="$tempdir/dbf_$dbfthread.log"
        sed -n ${sl},${el}p $mfstop | grep mfs | grep -w "$dbfthread" | awk '{print $9}' > ${dbffile} 2>&1 &
    done
    
    local compthreads="$(echo "$mfsthreads" | grep CpuQ_Compress | awk '{print $2}' | sed 's/,/ /g')"
    for compthread in $compthreads
    do
        local compfile="$tempdir/comp_$compthread.log"
        sed -n ${sl},${el}p $mfstop | grep mfs | grep -w "$compthread" | awk '{print $9}' > ${compfile} 2>&1 &
    done
    wait

    [ -n "$fsthreads" ] && paste $tempdir/fs_*.log | awk '{for(i=1;i<=NF;i++) sum+=$i; printf("%.0f\n", sum/NF); sum=0}' > $tempdir/fs.log 2>&1 &
    [ -n "$fsthreads" ] && paste $tempdir/fs_*.log | awk '{for(i=1;i<=NF;i++) { if($i>max) max=$i; } printf("%.0f\n", max); max=0}' > $tempdir/fs_max.log 2>&1 &
    
    [ -n "$dbthreads" ] && paste $tempdir/db_*.log | awk '{for(i=1;i<=NF;i++) sum+=$i; printf("%.0f\n", sum/NF); sum=0}' > $tempdir/db.log 2>&1 &
    [ -n "$dbthreads" ] && paste $tempdir/db_*.log | awk '{for(i=1;i<=NF;i++) { if($i>max) max=$i; } printf("%.0f\n", max); max=0}' > $tempdir/db_max.log 2>&1 &
    
    [ -n "$dbhthreads" ] && paste $tempdir/dbh_*.log | awk '{for(i=1;i<=NF;i++) sum+=$i; printf("%.0f\n", sum/NF); sum=0}' > $tempdir/dbh.log 2>&1 &
    [ -n "$dbhthreads" ] && paste $tempdir/dbh_*.log | awk '{for(i=1;i<=NF;i++) { if($i>max) max=$i; } printf("%.0f\n", max); max=0}' > $tempdir/dbh_max.log 2>&1 &
    
    [ -n "$dbfthreads" ] && paste $tempdir/dbf_*.log | awk '{for(i=1;i<=NF;i++) sum+=$i; printf("%.0f\n", sum/NF); sum=0}' > $tempdir/dbf.log 2>&1 &
    [ -n "$dbfthreads" ] && paste $tempdir/dbf_*.log | awk '{for(i=1;i<=NF;i++) { if($i>max) max=$i; } printf("%.0f\n", max); max=0}' > $tempdir/dbf_max.log 2>&1 &

    [ -n "$compthreads" ] && paste $tempdir/comp_*.log | awk '{for(i=1;i<=NF;i++) sum+=$i; printf("%.0f\n", sum/NF); sum=0}' > $tempdir/comp.log 2>&1 &
    [ -n "$compthreads" ] && paste $tempdir/comp_*.log | awk '{for(i=1;i<=NF;i++) { if($i>max) max=$i; } printf("%.0f\n", max); max=0}' > $tempdir/comp_max.log 2>&1 &
    wait
}

function maprutil_getGutsDefCols(){
    local collist="$1"
    local runtype="$2"
    

    local defcols="date,time,rpc,ior_ops,ior_mb,iow_ops,iow_mb"
    local defdbcols="rget,rgetR,tgetR,rmtg,cmtg,vcM,vcL,vcH,bget,sg,spg,riIO,rput,rputR,tputR,bucketWr_ops,fl,ffl,sfl,mcom,rsc,rscR,bsc,ssc,spsc,spscR,rtlk,rim,rip,rop,rob"
    local defstrcols="mpr,mpm,mpMB,mlr,mlm,mlMB"
    local deffscols="write_ops,write_mb,lwrite_ops,lwrite_mb,read_ops,read_mb,lread_ops,lread_mb"
    local defcaccols="inode_lkps,inode_miss,small_lkps,small_miss,large_lkps,large_miss,meta_lkps,meta_miss,dir_lkps,dir_miss"
    
    if [ -z "$runtype" ]; then
        echo "$defcols" | sed 's/,/ /g'
        return
    fi

    runtype="$(echo "$runtype" | tr ',' ' ')"
    local finalcols="$defcols"
    [ -n "$(echo $runtype | grep -w "db")" ] && finalcols="${finalcols}${defdbcols},"
    [ -n "$(echo $runtype | grep -w "stream")" ] && finalcols="${finalcols}${defstrcols},"
    [ -n "$(echo $runtype | grep -w "fs")" ] && finalcols="${finalcols}${deffscols},"
    [ -n "$(echo $runtype | grep -w "cache")" ] && finalcols="${finalcols}${defcaccols},"
    if [ -n "$(echo $runtype | grep -w "all")" ]; then
        finalcols=$(echo $collist | tr ' ' '\n' | grep -v "=cpu_[0-9]*" | grep "^[0-9]" | cut -d '=' -f2 | sed ':a;N;$!ba;s/\n/,/g')
    fi
            
    [ -n "$finalcols" ] && echo "$finalcols" | sed 's/,$//' | sed 's/,/ /g'
}

function marutil_getGutsSample(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    local gutsfile="/opt/mapr/logs/guts.log"
    [ -n "$2" ] && [ "$2" = "gw" ] && gutsfile="/opt/mapr/logs/gatewayguts.log"

    local gutsline="$(ssh_executeCommandasRoot "$node" "tail -n 1000 $gutsfile | grep '^[a-z]' | grep time | head -1 | sed 's/ \+/ /g'")"
    local twocols="time bucketWr write lwrite bwrite read lread inode regular small large meta dir ior iow iorI iowI iorB iowB iorD iowD icache dcache"
    local lkpmiss="icache dcache inode regular small large meta dir"
    local collist=
    local allcollist=
    local i=0
    for gline in $gutsline
    do
        let i=i+1
        if [ "$(util_isNumber $gline)" = "true" ]; then
            collist="$collist $i=cpu_$gline"
        elif [ -n "$(echo "$gline" | grep "^\[[0-9]*]")" ]; then
            collist="$collist $i=$(echo "$gline" | tr ']' ' ' | tr -d '[' | awk '{printf("mfs%d_%s",int($1),tolower($2))}')"
        elif [ -n "$(echo $twocols | grep -w $gline)" ]; then
            if [ "$gline" = "time" ]; then
                collist="$collist $i=date"
                [ "$(($i % 10))" -eq "0" ] && collist="$collist\n"
                let i=i+1
                collist="$collist $i=$gline"
            else
                if [ -z "$(echo $lkpmiss | grep -w $gline)" ]; then
                    collist="$collist $i=${gline}_ops"
                else
                    collist="$collist $i=${gline}_lkps"
                fi
                [ "$(($i % 10))" -eq "0" ] && collist="$collist\n"
                let i=i+1
                if [ -z "$(echo $lkpmiss | grep -w $gline)" ]; then
                    collist="$collist $i=${gline}_mb"
                else
                    collist="$collist $i=${gline}_miss"
                fi
            fi
        else
            collist="$collist $i=$gline"
        fi
        [ "$(($i % 10))" -eq "0" ] && collist="$collist\n"
    done
    [ -n "$collist" ] && echo -e "$collist" 
}

function maprutil_copygutsstats(){
    local node=$1
    local timestamp=$2
    local copyto=$3
    mkdir -p $copyto > /dev/null 2>&1
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local dirtocopy="/tmp/gutsstats/$timestamp/$host"

    [ -n "$host" ] && [ -d "$copyto/$host" ] && rm -rf $copyto/$host > /dev/null 2>&1
    ssh_copyFromCommand "root" "$node" "$dirtocopy" "$copyto" > /dev/null 2>&1
    ssh_executeCommandasRoot "$node" "rm -rf $dirtocopy" > /dev/null 2>&1
}

function maprutil_gutsStatsOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi

    local node=$1
    local timestamp=$2
    local gutstype=$3
    local colids="$4"
    local stime="$5"
    local etime="$6"
    
    local scriptpath="$RUNTEMPDIR/gutsstats_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_buildGutsStats \"$timestamp\" \"$gutstype\" \"$colids\" \"$stime\" \"$etime\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_publishGutsStats(){
    [ -z "$GLB_PERF_URL" ] && return

    local logdir="$1"
    local timestamp="$2"
    local hostlist="$3"
    local buildid="$4"
    local colnames="$5"
    local desc="$6"
    
    [ -z "$desc" ] && desc="${buildid}-${timestamp}"

    pushd $logdir > /dev/null 2>&1
    local fname="guts.log"
    [ ! -s "$fname" ] && return

    log_info "Publishing guts statistics to \"$GLB_PERF_URL\""

    local json="{"
    json="$json\"timestamp\":$timestamp,\"nodes\":\"$hostlist\",\"driver\":\"$(util_getHostIP)\""
    json="$json,\"build\":\"$buildid\",\"description\":\"$desc\""

    local ttime=0
    local fieldarr="["
    for col in $colnames
    do
        fieldarr="$fieldarr\"$col\","
    done
    fieldarr=$(echo $fieldarr | sed 's/,$//')
    fieldarr="$fieldarr]"
    fieldarr=$(echo $fieldarr | python -c 'import json,sys; print json.dumps(sys.stdin.read())')

    json="$json,\"columns\":$fieldarr"

    local glog=$(cat $fname | awk 'BEGIN{printf("["); i=0} { if(i==0) printf("{\"ts\":\"%s %s\",\"val\":[",$1,$2); else  printf(",{\"val\":["); for(j=3;j<=NF;j++) { printf("%s", $j); if(j!=NF) printf(",");} printf("]}"); i++} END{printf("]")}')
    glog=$(echo $glog | python -c 'import json,sys; print json.dumps(sys.stdin.read())')
    json="$json,\"data\":$glog"
    json="$json}"

    json="gutstats=$json"
    echo $json > guts.json
    local tmpfile=$(mktemp)
    echo "$json" > $tmpfile
    local fsize=$(echo "$(stat -c %s $tmpfile)/(1024*1024)" | bc )
    [[ "$fsize" -ge "20" ]] && log_warn "Publish may fail as aggregated log file size (${fsize}MB) is >20MB. Reduce the size by limiting the time range"
    curl -L -X POST --data @- ${GLB_PERF_URL} < $tmpfile > /dev/null 2>&1
    # TODO : Print URL
    rm -f $tmpfile > /dev/null 2>&1
    popd > /dev/null 2>&1
}

function maprutil_gutstatsOnCluster(){
    local nodes="$1"
    local tmpdir="$2"
    local timestamp="$3"
    local colids="$4"
    local colnames="$5"
    local publish="$6"


    local hostlist=
    local buildid=
    local patchid=
    local dirlist=
    for node in ${nodes[@]}
    do
        local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
        [ ! -d "$tmpdir/$host/" ] && log_error "Incomplete logs; '$host' logs are missing. Exiting!" && return
        dirlist="$dirlist $tmpdir/$host/"
        hostlist="$hostlist $node"
        [ -z "$buildid" ] && buildid=$(ssh_executeCommandasRoot "$node" "cat /opt/mapr/MapRBuildVersion")
        [ -z "$patchid" ] && patchid=$(ssh_executeCommandasRoot "$node" "ls /opt/mapr/.patch/README.* | cut -d '.' -f3 | tr -d 'p'" 2>/dev/null)
    done
    [ -n "$buildid" ] && [ -n "$patchid" ] && buildid="$buildid (patch $patchid)"
    [ -z "$(echo $dirlist | grep "$tmpdir")" ] && return
    [ -z "$(ls $tmpdir/* 2>/dev/null)" ] && return
    
    local logdir="$tmpdir/cluster"
    rm -rf $logdir > /dev/null 2>&1
    mkdir -p $logdir > /dev/null 2>&1

    local filelist=$(find $dirlist -name guts.log 2>/dev/null)
    [ -z "$filelist" ] && log_warn "No guts log found" && return

    local colarr=

    local filecnt=$(echo "$filelist" | wc -l)
    local colcnt=$(echo "$colids" | wc -w)
    local i=1
    for col in $colids
    do  
        for ((j = 0; j < $filecnt; j++))
        do
            if [ "$col" -eq "1" ] || [ "$col" -eq "2" ]; then
                colarr="$colarr $i"
                break
            fi
            colarr="$colarr $(echo "$j*$colcnt+$i" | bc)"
        done
        let i=i+1
    done

    paste $filelist | awk -v var="$colarr" -v fcnt="$filecnt" 'BEGIN{split(var,cids," ")} {j=0; for (i=1;i<=length(cids);i++) { if(cids[i] < 3) printf("%s ", $cids[i]); else { sum+=$cids[i]; j++;  if(j==fcnt) { printf("%s ", sum); sum=0; j=0}}}  printf("\n");}' > $logdir/guts.log

    [ -n "$GLB_PERF_URL" ] && maprutil_publishGutsStats "$logdir" "$timestamp" "$hostlist" "$buildid" "$colnames" "$publish"

    colnames="$(echo "$colnames" | sed 's/,/ /g')" && sed -i "1s/^/${colnames}\n/" $logdir/guts.log > /dev/null 2>&1
    
    pushd $tmpdir > /dev/null 2>&1
    local dirstotar=$dirlist
    if [ "$2" != "/tmp" ] || [ "$2" != "/tmp/" ]; then
        dirstotar=$(echo $(ls -d */))
    fi        
    tar -cf maprgutsstats_$timestamp.tar.bz2 --use-compress-prog=pbzip2 $dirstotar > /dev/null 2>&1

    util_createExtractFile

    [ "$dirstotar" != "$dirlist" ] && rm -rf $dirstotar > /dev/null 2>&1 
    popd > /dev/null 2>&1
}

function maprutil_buildGutsStats(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    
    local timestamp="$1"
    local gutstype="$2"
    local colids="$3"
    local stime="$4"
    local etime="$5"

    local gutslog="/opt/mapr/logs/guts.log"
    [ "$gutstype" = "gw" ] && gutslog="/opt/mapr/logs/gatewayguts.log"

    [ ! -s "$gutslog" ] && return

    local sl=1
    local el=$(cat $gutslog | wc -l)
    [ -n "$stime" ] && stime=$(date -d "$stime" "+%Y-%m-%d %H:%M")
    [ -n "$etime" ] && etime=$(date -d "$etime" "+%Y-%m-%d %H:%M")
    [ -n "$stime" ] && sl=$(cat $gutslog | grep -n "$stime" | cut -d':' -f1 | tail -1)
    [ -n "$etime" ] && el=$(cat $gutslog | grep -n "$etime" | cut -d':' -f1 | tail -1)
    [ -z "$el" ] || [ -z "$sl" ] && return
    [ "$sl" -gt "$el" ] && el=$(cat $gutslog | wc -l)

    local tempdir="/tmp/gutsstats/$timestamp/$(hostname -f)"
    mkdir -p $tempdir > /dev/null 2>&1

    local gutsfile="$tempdir/guts.log"
    sed -n ${sl},${el}p $gutslog | grep "^2" |  awk -v var="$colids" 'BEGIN{split(var,cids," ")} {for (i=1;i<=length(cids);i++) printf("%s ", $cids[i]); printf("\n");}' > ${gutsfile} 2>&1
}

function maprutil_buildDiskUsage(){
    [ -z "$1" ] && return
    
    local tmpdir="$1"
    local stime="$2"
    local etime="$3"


    local disklog="/opt/mapr/logs/iostat.log"
    [ ! -s "$disklog" ] && return

    local sl=1
    local el=$(cat $disklog | wc -l)

    [ -n "$stime" ] && stime="$(date -d "$stime" '+%m/%d/%Y %r')"
    [ -n "$etime" ] && etime="$(date -d "$etime" '+%m/%d/%Y %r')"
    [ -n "$stime" ] && sl=$(cat $disklog | grep -n "$stime" | cut -d':' -f1 | tail -1)
    [ -n "$etime" ] && el=$(cat $disklog | grep -n "$etime" | cut -d':' -f1 | tail -1)
    [ -z "$el" ] || [ -z "$sl" ] && log_warn "Start/End date is not available in the disks usage logs. Try another range for disk data" && return
    [ "$sl" -gt "$el" ] && el=$(cat $disklog | wc -l)

    local disksfile="$tmpdir/disks.log"

    local mdisks=$(cat /opt/mapr/conf/disktab | grep '/' | awk '{print $1}' | sed 's/\/dev\///g' | tr '\n' ' ')
    local numdisks=$(echo $mdisks | wc -w)
    mdisks="$mdisks AM PM"
    mdisks=$(echo $mdisks | tr ' ' '\n')
    local colid=$(grep "%util" $disklog | head -1 | awk '{for (i = 1; i <= NF; ++i) {if($i ~ /%util/) print i}}')
    sed -n ${sl},${el}p $disklog | grep -Fw "${mdisks}" | awk -v cid="$colid" -v nd="$numdisks" '{if($0 ~ /AM/ || $0 ~ /PM/) { if(time!="") print time,sum/nd,max; time=sprintf("%s %s%s",$1,$2,$3); sum=0; max=0 } else {sum+=$cid; if($cid>max) max=$cid}} END{print time,sum/nd,max}' > ${disksfile}
}

function maprutil_buildClientUsage(){
    [ -z "$1" ] && return
    
    local tmpdir="$1"
    local stime="$2"
    local etime="$3"

    local clientreslogs=$(ls /opt/mapr/logs/clientresusage_* 2>/dev/null)
    [ -z "$clientreslogs" ] && return

    local stts=
    local etts=
    [ -n "$stime" ] && stime=$(date -d "$stime" "+%Y-%m-%d %H:%M") && stts=$(date -d "$stime" +%s)
    [ -n "$etime" ] && etime=$(date -d "$etime" "+%Y-%m-%d %H:%M") && etts=$(date -d "$etime" +%s)

    # Build CPU & Memory average for each second in the time range
    local clientsfile="$tmpdir/client.log"
    local tmpclog=$(mktemp)
    for clog in $clientreslogs
    do
        local sl=2
        local el=$(cat $clog | wc -l)
        local cst=$(sed -n 2p $clog | awk '{print $1,$2}')
        [ -z "$(echo "$cst" | grep '^[0-9]')" ] && continue

        local cet=$(tail -1 $clog | awk '{print $1,$2}')
        cst=$(date -d "$cst" +%s)
        cet=$(date -d "$cet" +%s)

        [ -n "$stime" ] && sl=$(cat $clog | grep -n "$stime" | cut -d':' -f1 | head -1)
        [ -n "$etime" ] && el=$(cat $clog | grep -n "$etime" | cut -d':' -f1 | tail -1)
        if [ -z "$el" ] || [ -z "$sl" ]; then
            [[ -n "$etts" ]] && [[ "$etts" -lt "$cst" ]] && continue
            [[ -n "$stts" ]] && [[ "$stts" -gt "$cet" ]] && continue
            [ -z "$sl" ] && sl=2
            [ -z "$el" ] && el=$(cat $clog | wc -l)
        fi 
        [ "$sl" -gt "$el" ] && el=$(cat $clog | wc -l)
        sed -n ${sl},${el}p $clog >> $tmpclog
    done
    [ -s "$tmpclog" ] && cat $tmpclog | awk '{ts=$1" "$2; cnt[ts]+=1; r=$3; if(r ~ /g/) {r=r*1} else if(r ~ /t/) {r=r*1024} else if(r ~ /m/) {r=r/1024} else {r=r/1024/1024} cmem[ts]+=r; ccpu[ts]+=$4} END {for (i in cnt) printf("%s %.3f %.0f\n",i,cmem[i]/cnt[i],ccpu[i]/cnt[i])}' | sort -n > ${clientsfile}
    rm -f $tmpclog > /dev/null 2>&1
}

function maprutil_perfToolOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi

    local node=$1
    local timestamp=$2
    
    local scriptpath="$RUNTEMPDIR/perftool_${node}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_perftool \"$timestamp\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_copyperfoutput(){
    local node=$1
    local timestamp=$2
    local copyto=$3
    mkdir -p $copyto > /dev/null 2>&1
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local dirtocopy="/tmp/perftool/$timestamp/$host"

    [ -n "$host" ] && [ -d "$copyto/$host" ] && rm -rf $copyto/$host > /dev/null 2>&1
    ssh_copyFromCommand "root" "$node" "$dirtocopy" "$copyto" > /dev/null 2>&1
    ssh_executeCommandasRoot "$node" "rm -rf $dirtocopy" > /dev/null 2>&1

    ## TBD : PRINT Top 20 frames
}

function maprutil_printperfoutput(){
    local node=$1
    local logdir=$2
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local perflog="$logdir/$host/perf.log"

    log_msghead "[$node]: Perf CPU profile for '$GLB_PERF_OPTION'"
    [ ! -s "$perflog" ] && return

    local lines="$(cat $perflog | sed '/#/d' | sed '/^\[/d' | sed 's/^ *//g' | awk '{if($3 !~ /kernel.kallsyms/ || $5 !~ /0x/ ) print $0}' | sed '/^\s*$/d' | head -n 20)"
    if [ -n "$lines" ]; then
        log_msg "\t Top 20 frames from $perflog "
        echo "$lines" | sed 's/^/\t\t/' && echo
    fi
}

function maprutil_perftool(){
    local timestamp=$1
    
    local ppid=
    local tids=
    local binarypath="/opt/mapr/server/mfs"
    
    case $GLB_PERF_OPTION in 
        mfs) 
            ppid=$(pidof mfs) 
        ;;
        gw) 
            ppid="$(jps | awk '{if($2 == "Gateway") print $1}')"
            binarypath="/opt/mapr/lib/libGatewayNative.so"
        ;;
        *)
            ppid=$(pidof mfs) 
            local mfsthreads=$(maprutil_mfsthreads | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g')
            case $GLB_PERF_OPTION in
                fs)
                    tids="$(echo "$mfsthreads" | grep CpuQ_FS | awk '{print $2}')"
                ;;
                compress)
                    tids="$(echo "$mfsthreads" | grep CpuQ_Compress | awk '{print $2}')"
                ;;
                dbmain)
                    tids="$(echo "$mfsthreads" | grep CpuQ_DBMain | awk '{print $2}')"
                ;;
                dbflusher)
                    tids="$(echo "$mfsthreads" | grep CpuQ_DBFlush | awk '{print $2}')"
                ;;
                dbhelper)
                    tids="$(echo "$mfsthreads" | grep CpuQ_DBHelper | awk '{print $2}')"
                ;;
                rpc)
                    tids="$(echo "$mfsthreads" | grep CpuQ_Rpc | awk '{print $2}')"
                ;;
            esac
        ;;
    esac

    [ -z "$ppid" ] && [ -z "$tids" ] && return

    local tempdir="/tmp/perftool/$timestamp/$(hostname -f)"
    mkdir -p $tempdir > /dev/null 2>&1

    cd $tempdir
    timeout $GLB_PERF_INTERVAL perf record -p $ppid -q -o "perf.data.$ppid" > /dev/null 2>&1
    
    [ -n "$tids" ] && tids="--tid=$tids"

    perf report $tids -k $binarypath --stdio -i perf.data.$ppid -U --header > perf.log 2>&1
    rm -rf perf.data.$ppid > /dev/null 2>&1
}

function maprutil_analyzeCores(){
    local cores=$(ls -ltr /opt/cores | grep 'mfs.core\|java.core\|reader\|writer\|collectd' | awk '{print $9}')
    [ -n "$GLB_EXT_ARGS" ] && cores=$(echo "$cores" | grep "$GLB_EXT_ARGS")
    [ -z "$cores" ] && return

    echo
    if [ -z "$GLB_COPY_CORES" ] || [ -z "$GLB_COPY_DIR" ]; then
        log_msghead "[$(util_getHostIP)] Analyzing $(echo $cores | wc -w) core file(s)"
    else
        log_msghead "[$(util_getHostIP)] Analyzing and copying $(echo $cores | wc -w) core file(s). This may take a while"
    fi

    local i=1
    for core in $cores
    do
        local tracefile="/opt/mapr/logs/$core.gdbtrace"
        maprutil_debugCore "/opt/cores/$core" $tracefile $i > /dev/null 2>&1 &
        while [ "$(ps -ef | grep "[g]db -ex" | wc -l)" -gt "5" ]; do
            sleep 1
        done
        let i=i+1 
    done
    wait

    i=1
    for core in $cores
    do
        local tracefile="/opt/mapr/logs/$core.gdbtrace"
        local cpfile=
        [ -n "$GLB_COPY_DIR" ] && mkdir -p $GLB_COPY_DIR > /dev/null 2>&1 && cpfile="$GLB_COPY_DIR/$core.gdbtrace"
        [ -z "$cpfile" ] && cpfile="$tracefile"
        local ftime=$(date -r /opt/cores/$core +'%Y-%m-%d %H:%M:%S')
        log_msg "\n\t Core #${i} : [$ftime] $core ( $cpfile )"
        local backtrace=$(maprutil_debugCore "/opt/cores/$core" $tracefile $i)

        if [ -n "$(cat $tracefile | grep "is truncated: expected")" ]; then
            log_msg "\t\t Core file is truncated"
        elif [ -n "$backtrace" ]; then
            if [ -z "$GLB_LOG_VERBOSE" ]; then
                local btlen=$(echo -e "$backtrace" | wc -l)
                echo -e "$backtrace" | awk -v l=$btlen 'BEGIN{i=0; j=0;}{i++; if(i<40||i>l-10){print $0;}else if(j<3){j++;printf("...\n")}}' | sed 's/^/\t\t/' 
            else
                cat $tracefile | sed -e '1,/Thread debugging using/d' | sed 's/^/\t\t/'
            fi
            [ -n "$GLB_COPY_DIR" ] && cp $tracefile $cpfile > /dev/null 2>&1
        else
            log_msg "\t\t Unable to fetch the backtrace"
        fi
        let i=i+1
    done
}

# @param corefile
# @param gdb trace file
function maprutil_debugCore(){
    if [ -z "$1" ]; then
        return
    fi
    command -v gdb >/dev/null 2>&1 || return

    local corefile=$1
    local tracefile=$2
    local coreidx=$3
    local newcore=
    local isjava=$(echo $corefile | grep "java.core")
    local iscollectd=$(echo $corefile | grep "reader\|writer\|collectd")
    local ismfs=$(echo $corefile | grep "mfs.core")
    local colbin=

    if [ -z "$(find $tracefile -type f -size +15k 2> /dev/null)" ]; then
        if [ -n "$isjava" ]; then
            gdb -ex "thread apply all bt" --batch -c ${corefile} $(which java) > $tracefile 2>&1
            newcore=1
        elif [ -n "$iscollectd" ]; then
            colbin=$(find /opt/mapr/collectd -type f -name collectd  -exec file -i '{}' \; 2> /dev/null | tr -d ':' | grep 'x-executable' | awk {'print $1'})
            gdb -ex "thread apply all bt" --batch -c ${corefile} $colbin > $tracefile 2>&1    
            newcore=1
        elif [ -n "$ismfs" ]; then
            gdb -ex "thread apply all bt" --batch -c ${corefile} /opt/mapr/server/mfs > $tracefile 2>&1    
            newcore=1
        fi
    fi
    local btline=$(cat $tracefile | grep -B10 -n "mapr::fs::FileServer::CoreHandler" | grep "Thread [0-9]*" | tail -1 | cut -d '-' -f1)
    [ -z "$btline" ] && btline=$(cat $tracefile | grep -B10 -n  "abort ()" | grep "Thread [0-9]*" | tail -1 | cut -d '-' -f1)
    [ -z "$btline" ] && btline=$(cat $tracefile | grep -n "Thread 1 " | cut -f1 -d:)
    local backtrace=$(cat $tracefile | sed -n "${btline},/^\s*$/p")
    [ -n "$backtrace" ] && btthread=$(echo "$backtrace" | head -1 | awk '{print $2}')
    if [ -n "$ismfs" ] && [ -n "$newcore" ] && [ -n "$btthread" ]; then
        local tmpfile=$(mktemp)
        echo "info threads" > $tmpfile
        echo "info registers" >> $tmpfile
        echo "thread apply all bt" >> $tmpfile
        echo "thread $btthread" >> $tmpfile
        for i in {0..10}
        do
            echo "f $i" >> $tmpfile
            echo "info frame" >> $tmpfile
            echo "info args" >> $tmpfile
            echo "info locals" >> $tmpfile
        done
        gdb -x $tmpfile -f -batch -c ${corefile} /opt/mapr/server/mfs > $tracefile 2>&1
        rm -f $tmpfile >/dev/null 2>&1
    fi
    if [[ -n "$GLB_COPY_CORES" ]] && [[ "$coreidx" -le "$GLB_COPY_CORES" ]] && [[ -n "$GLB_COPY_DIR" ]] && [[ ! -f "$GLB_COPY_DIR/$(basename $corefile)" ]]; then
        local sz=$(stat -c %s $corefile);
        log_info "[$(util_getHostIP)] Copying $corefile ($(echo $sz/1024/1024/1024|bc) GB) to $GLB_COPY_DIR directory"
        cp $corefile $GLB_COPY_DIR/ > /dev/null 2>&1
        [ -n "$ismfs" ] && [ ! -f "$GLB_COPY_DIR/mfs" ] && cp /opt/mapr/server/mfs $GLB_COPY_DIR/ > /dev/null 2>&1
        [ ! -f "$GLB_COPY_DIR/libMapRClient.so" ] && cp /opt/mapr/lib/libMapRClient.so $GLB_COPY_DIR/ > /dev/null 2>&1
        [ ! -f "$GLB_COPY_DIR/libGatewayNative.so" ] && cp /opt/mapr/lib/libGatewayNative.so $GLB_COPY_DIR/ > /dev/null 2>&1
        [ -n "$colbin" ] && [ ! -f "$GLB_COPY_DIR/collectd" ] && cp $colbin $GLB_COPY_DIR/ > /dev/null 2>&1
        [ "$sz" -gt "10737418240" ] && log_warn "[$(util_getHostIP)] Disk may get full with large(>10GB) core file(s)"
    fi
    [ -n "$backtrace" ] && echo "$backtrace" | sed  -n '/Switching to thread/q;p'
}

function maprutil_runmrconfig_info(){
    [ ! -e "/opt/mapr/roles/fileserver" ] && return
    local info="$1"
    [ -z "$info" ] && info="dbinfo"
    local commands=$(/opt/mapr/server/mrconfig $info | awk '{if(NF==2) print $2}')
    log_msghead "[$(util_getHostIP)] Running 'mrconfig $info' commands : "
    for i in $commands; do
        log_msg "/opt/mapr/server/mrconfig $info $i"
        local output=$(/opt/mapr/server/mrconfig $info $i)
        echo "$output" | sed 's/^/\t/'
        echo
    done
}

# @param scriptpath
# @param node
function maprutil_buildSingleScript(){
    local _scriptpath=$1
    local _fornode=$2

    util_buildSingleScript "$lib_dir" "$_scriptpath" "$_fornode"
    local rval=$?
    if [ "$rval" -ne "0" ]; then
        return $rval
    fi
    echo >> $_scriptpath
    echo "##########  Global Parameters below ########### " >> $_scriptpath
    maprutil_addGlobalVars "$_scriptpath"
    echo >> $_scriptpath
    echo "##########  Adding execute steps below ########### " >> $_scriptpath
    echo >> $_scriptpath
}

# @param file path
function maprutil_readClusterRoles(){
  local rfile="$1"
  local setupop="$2"
  local cldbnodes=
  local mfsnodes=

  log_msg "Enter Cluster Node IPs ( ex: 10.10.103.[39-40,43-49] ) : "
  echo
  if [ -n "$setupop" ] && [ "$setupop" != "install" ] && [ "$setupop" != "reconfigure" ]; then
      log_inline "Enter Node IP(s)  : "
      read mfsnodes
      echo "$mfsnodes,dummy" > $rfile && util_expandNodeList "$rfile" > /dev/null 2>&1
      return
  fi

  log_inline "Enter CLDB Node IP(s) : "
  read cldbnodes
  echo "$cldbnodes,dummy" > $rfile && util_expandNodeList "$rfile" > /dev/null 2>&1
  cldbnodes=$(cat $(util_expandNodeList "$rfile") | cut -d',' -f1 | tr '\n' ' ')

  log_inline "Enter MFS Node IP(s)  : "
  read mfsnodes
  echo "$mfsnodes,dummy" > $rfile && util_expandNodeList "$rfile" > /dev/null 2>&1
  mfsnodes=$(cat $(util_expandNodeList "$rfile") | cut -d',' -f1 | tr '\n' ' ')

  #log_msg "CLDB Node(s) -> $cldbnodes, MFS Node(s) ->  $mfsnodes"

  log_msg "Select Cluster Role Configuration Type"
  log_msg "\t 1: Hadoop YARN"
  log_msg "\t 2: Hadoop MRv1"
  log_msg "\t 3: YCSB [default]"

  log_inline "Enter selection : "
  read -n 1 -r
  echo
  case $REPLY in
    1) 
        local i=1
        for node in ${cldbnodes[@]}
        do
            if [ "$i" -eq "1" ]; then
                echo "$node,mapr-cldb,mapr-fileserver,mapr-webserver,mapr-zookeeper,mapr-gateway,mapr-nfs,mapr-resourcemanager,mapr-historyserver" > $rfile
            else
                echo "$node,mapr-cldb,mapr-fileserver,mapr-zookeeper,mapr-resourcemanager" >> $rfile
            fi
            let i=i+1
        done
        for node in ${mfsnodes[@]}
        do
            [ -n "$(echo "$cldbnodes" | grep $node)" ] && continue
            echo "$node,mapr-fileserver,mapr-nodemanager" >> $rfile
            let i=i+1
        done
        ;;
    2) 
        local i=1
        for node in ${cldbnodes[@]}
        do
            if [ "$i" -eq "1" ]; then
                echo "$node,mapr-cldb,mapr-fileserver,mapr-webserver,mapr-zookeeper,mapr-gateway,mapr-nfs,mapr-jobtracker" > $rfile
            else
                echo "$node,mapr-cldb,mapr-fileserver,mapr-zookeeper,mapr-jobtracker" >> $rfile
            fi
            let i=i+1
        done
        for node in ${mfsnodes[@]}
        do
            [ -n "$(echo "$cldbnodes" | grep $node)" ] && continue
            echo "$node,mapr-fileserver,mapr-tasktracker" >> $rfile
            let i=i+1
        done
        ;;
    3 | *)
        local i=1
        for node in ${cldbnodes[@]}
        do
            if [ "$i" -eq "1" ]; then
                echo "$node,mapr-cldb,mapr-fileserver,mapr-webserver,mapr-zookeeper,mapr-gateway,mapr-nfs" > $rfile
            else
                echo "$node,mapr-cldb,mapr-fileserver,mapr-zookeeper" >> $rfile
            fi
            let i=i+1
        done
        for node in ${mfsnodes[@]}
        do
            [ -n "$(echo "$cldbnodes" | grep $node)" ] && continue
            echo "$node,mapr-fileserver" >> $rfile
            let i=i+1
        done
        ;;
    
  esac
  #cat $rfile
} 

### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
