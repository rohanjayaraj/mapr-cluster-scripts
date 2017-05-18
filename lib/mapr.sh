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
    if [ -n "$1" ] && [ "$hostip" != "$1" ]; then
        #master=$(ssh_executeCommandWithTimeout "root" "$1" "maprcli node cldbmaster | grep HostName | cut -d' ' -f4" "10")
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
    local cldbnodes=$(grep cldb $1 | grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$cldbnodes" ]; then
            echo $cldbnodes
    fi
}

## @param path to config
function maprutil_getGatewayNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local gwnodes=$(grep mapr-gateway $1 | grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$gwnodes" ]; then
        echo $gwnodes
    fi
}

## @param path to config
function maprutil_getESNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local esnodes=$(grep elastic $1 | grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$esnodes" ]; then
            echo $esnodes
    fi
}

## @param path to config
function maprutil_getOTSDBNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local otnodes=$(grep opentsdb $1 | grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$otnodes" ]; then
            echo $otnodes
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
## @param host ip
function maprutil_getCoreNodeBinaries() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    
    local binlist=$(grep $2 $1 | cut -d, -f 2- | sed 's/,/ /g')
    if [ -n "$binlist" ]; then
        # Remove collectd,fluentd,opentsdb,kibana,grafana
        local newbinlist=
        for bin in ${binlist[@]}
        do
            if [[ ! "${bin}" =~ collectd|fluentd|opentsdb|kibana|grafana|elasticsearch|asynchbase ]]; then
                newbinlist=$newbinlist"$bin "
            fi
        done
        if [ -z "$(maprutil_isClientNode $1 $2)" ]; then
            [ -n "$GLB_MAPR_PATCH" ] && [ -z "$(echo $newbinlist | grep mapr-patch)" ] && newbinlist=$newbinlist"mapr-patch"
        fi
        echo $newbinlist
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
    local isclient=$(grep $2 $1 | grep 'mapr-client\|mapr-loopbacknfs' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    [ -z "$isclient" ] && isclient=$(grep $2 $1 | cut -d',' -f2 | grep mapr-core)
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
    for i in $(cat $1 | grep '^[^#;]'); do
        local node=$(echo $i | cut -f1 -d",")
        local isvalid=$(util_validip2 $node)
        if [ "$isvalid" = "valid" ]; then
            nodes=$nodes$node" "
        else
            echo "Invalid IP [$node]. Scooting"
            exit 1
        fi
    done
    echo $nodes | tr ' ' '\n' | sort -t . -k 3,3n -k 4,4n | tr '\n' ' '
}

function maprutil_ycsbdirs(){
    local dirlist=()
    for i in $(find /var/ycsb -maxdepth 1 -type d -ctime +10 2>/dev/null)
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
    dirlist+=("/opt/cores/*mrconfig*")
    echo ${dirlist[*]}
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
    local scriptpath="$RUNTEMPDIR/isinstalled_${hostnode: -3}.sh"

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
    if [ "$nodeos" = "centos" ]; then
        patch=$(ssh_executeCommandasRoot "$node" "rpm -qa | grep mapr-patch | cut -d'-' -f4 | cut -d'.' -f1")
    elif [ "$nodeos" = "ubuntu" ]; then
        patch=$(ssh_executeCommandasRoot "$node" "dpkg -l | grep mapr-patch | awk '{print $3}' | cut -d'-' -f4 | cut -d'.' -f1")
    fi
    [ -n "$patch" ] && patch=" (patch ${patch})"
    if [ -n "$version" ]; then
        echo $version$patch
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
    local scriptpath="$RUNTEMPDIR/cleanupnode_${hostnode: -3}.sh"
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
    
     # Remove all directories
    maprutil_removedirs "cores" > /dev/null 2>&1
    maprutil_removedirs "temp" > /dev/null 2>&1

    if [ -e "/opt/mapr/roles/zookeeper" ]; then
        for i in datacenter services services_config servers ; do 
            /opt/mapr/zookeeper/zookeeper-*/bin/zkCli.sh -server localhost:5181 rmr /$i > /dev/null 2>&1
        done
         # Stop zookeeper
        service mapr-zookeeper stop  2>/dev/null
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
    local scriptpath="$RUNTEMPDIR/uninstallnode_${hostnode: -3}.sh"
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
    local upbins="mapr-cldb mapr-core mapr-core-internal mapr-fileserver mapr-hadoop-core mapr-historyserver mapr-jobtracker mapr-mapreduce1 mapr-mapreduce2 mapr-metrics mapr-nfs mapr-nodemanager mapr-resourcemanager mapr-tasktracker mapr-webserver mapr-zookeeper mapr-zk-internal"
    local buildversion=$1
    
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

    /opt/mapr/server/configure.sh -R

    # Start zookeeper if if exists
    service mapr-zookeeper start 2>/dev/null
    
    # Restart services on the node
    maprutil_restartWarden "start" > /dev/null 2>&1
}

# @param host ip
function maprutil_upgradeNode(){
    if [ -z "$1" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/upgradenode_${hostnode: -3}.sh"
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
        ssh_executeCommandasRoot "$node" "timeout 50 maprcli config save -values {mapr.targetversion:\"\$(cat /opt/mapr/MapRBuildVersion)\"}" > /dev/null 2>&1
        ssh_executeCommandasRoot "$node" "timeout 10 maprcli node list -columns hostname,csvc" 
    else
        log_warn "Timed out waiting for CLDB to come up. Please update 'mapr.targetversion' manually"
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
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/installbinnode_${hostnode: -3}.sh"
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
    echo "util_installprereq" >> $scriptpath
    local bins="$2"
    local maprpatch=$(echo "$bins" | tr ' ' '\n' | grep mapr-patch)
    [ -n "$maprpatch" ] && bins=$(echo "$bins" | tr ' ' '\n' | grep -v mapr-patch | tr '\n' ' ')
    
    ## Append MapR release version as there might be conflicts with mapr-patch-client with regex as 'mapr-patch*$VERSION*'
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        echo "util_installBinaries \""$bins"\" \""$GLB_BUILD_VERSION"\" \""-$GLB_MAPR_VERSION"\"" >> $scriptpath
        [ -n "$maprpatch" ] && echo "util_installBinaries \""$maprpatch"\" \""$GLB_PATCH_VERSION"\" \""-$GLB_MAPR_VERSION"\" || exit 1" >> $scriptpath
    else
        echo "util_installBinaries \""$bins"\" \""$GLB_BUILD_VERSION"\" \""$GLB_MAPR_VERSION"\"" >> $scriptpath
        [ -n "$maprpatch" ] && echo "util_installBinaries \""$maprpatch"\" \""$GLB_PATCH_VERSION"\" \""$GLB_MAPR_VERSION"\" || exit 1" >> $scriptpath
    fi
    
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$3" ]; then
        maprutil_wait
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
        maprcli config load -json > /dev/null 2>&1
        let failcnt=$failcnt+`echo $?`
        [ "$failcnt" -gt "0" ] && sleep 30;
        let iter=$iter+1;
    done
    if [ "$iter" -lt "$iterlimit" ]; then
        local setnumsps=$(maprcli config load -json 2>/dev/null| grep multimfs.numsps.perinstance | tr -d '"' | tr -d ',' | cut -d':' -f2)
        if [ "$setnumsps" -lt "$numspspermfs" ]; then
            maprcli  config save -values {multimfs.numinstances.pernode:${nummfs}}
            maprcli  config save -values {multimfs.numsps.perinstance:${numspspermfs}}
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

function maprutil_addRootUserToCntrExec(){

    local execfile="container-executor.cfg"
    local execfilelist=$(find /opt/mapr/hadoop -name $execfile -type f ! -path "*/templates/*")
    for i in $execfilelist; do
        local present=$(cat $i | grep "allowed.system.users" | grep -v root)
        if [ -n "$present" ]; then
            sed -i '/^allowed.system.users/ s/$/,root/' $i
        fi
    done
}

function maprutil_customConfigure(){

    local tablens=$GLB_TABLE_NS
    if [ -n "$tablens" ]; then
        maprutil_addTableNS "core-site.xml" "$tablens"
        maprutil_addTableNS "hbase-site.xml" "$tablens"
    fi

    local pontis=$GLB_PONTIS
    if [ -n "$pontis" ]; then
        maprutil_configurePontis
    fi 

    maprutil_addFSThreads "core-site.xml"
    maprutil_addTabletLRU "core-site.xml"
    maprutil_updateGWThreads
    
    local putbuffer=$GLB_PUT_BUFFER
    if [ -n "$putbuffer" ]; then
        maprutil_addPutBufferThreshold "core-site.xml" "$putbuffer"
    fi

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
    
    local datatopo=$(maprcli node list -json | grep racktopo | grep "/data/" | wc -l)
    local numdnodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | wc -l) 
    local j=0
    while [ "$numdnodes" -ne "$GLB_CLUSTER_SIZE" ]; do
        sleep 15
        numdnodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | wc -l) 
        let j=j+1
        if [ "$j" -gt 20 ]; then
            break
        fi
    done
    let numdnodes=numdnodes-1

    if [ "$datatopo" -eq "$numdnodes" ]; then
        return
    fi
    ## Move all nodes under /data topology
    local datanodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | tr "\n" ",")
    maprcli node move -serverids "$datanodes" -topology /data 2>/dev/null
    
    ## Move CLDB if only forced or # of nodes > 5
    if [ "$GLB_CLUSTER_SIZE" -gt 5 ] || [ -n "$1" ]; then
        ### Moving CLDB Nodes to CLDB topology
        #local cldbnode=`maprcli node cldbmaster | grep ServerID | awk {'print $2'}`
        local cldbnodes=$(maprcli node list -json | grep -e configuredservice -e id | grep -B1 cldb | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | tr "\n" "," | sed 's/\,$//')
        maprcli node move -serverids "$cldbnodes" -topology /cldb 2>/dev/null
        ### Moving CLDB Volume as well
        maprcli volume move -name mapr.cldb.internal -topology /cldb 2>/dev/null
    fi
}

function maprutil_moveTSDBVolumeToCLDBTopology(){
    [ -n "$(maprcli volume info -name mapr.monitoring -json 2>/dev/null | grep rackpath | grep cldb)" ] && return
    local tsdbexists=$(maprcli volume info -name mapr.monitoring -json 2>/dev/null| grep ERROR)
    local cldbtopo=$(maprcli node topo -path /cldb 2>/dev/null)
    if [ -n "$tsdbexists" ] || [ -z "$cldbtopo" ]; then
        log_warn "OpenTSDB not installed or CLDB not moved to /cldb topology"
        return
    fi

    maprcli volume modify -name mapr.monitoring -minreplication 1 2>/dev/null
    maprcli volume modify -name mapr.monitoring -replication 1 2>/dev/null
    maprcli volume move -name mapr.monitoring -topology /cldb 2>/dev/null
}

# @param diskfile
# @param disk limit
function maprutil_buildDiskList() {
    if [ -z "$1" ]; then
        return
    fi
    local diskfile=$1
    echo "$(util_getRawDisks)" > $diskfile

    local limit=$GLB_MAX_DISKS
    local numdisks=$(wc -l $diskfile | cut -f1 -d' ')
    if [ -n "$limit" ] && [ "$numdisks" -gt "$limit" ]; then
         local newlist=$(head -n $limit $diskfile)
         echo "$newlist" > $diskfile
    fi
}

function maprutil_startTraces() {
    if [[ "$ISCLIENT" -eq "0" ]] && [[ -e "/opt/mapr/roles" ]]; then
        nohup sh -c 'log="/opt/mapr/logs/guts.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=`pidof mfs`; if [ -n "$mfspid" ]; then timeout 14 /opt/mapr/bin/guts time:all flush:line cache:all db:all rpc:all log:all dbrepl:all >> $log; rc=$?; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done'  > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/dstat.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do timeout 14 dstat -tcdnim >> $log; rc=$?; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/iostat.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do timeout 14 iostat -dmxt 1 >> $log 2> /dev/null; rc=$?; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/mfstop.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=`pidof mfs`; if [ -n "$mfspid" ]; then timeout 10 top -bH -p $mfspid -d 1 >> $log; rc=$?; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/gatewayguts.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/gateway" ]]; do gwpid=$(cat /opt/mapr/pid/gateway.pid 2>/dev/null); if kill -0 ${gwpid}; then timeout 14 stdbuf -o0 /opt/mapr/bin/guts clientpid:$gwpid time:all gateway:all >> $log; rc=$?; [ "$rc" -eq "1" ] && [ -z "$(grep Printing $log)" ] && truncate -s 0 $log && sleep 5; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done'  > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/gatewaytop.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/gateway" ]]; do gwpid=$(cat /opt/mapr/pid/gateway.pid 2>/dev/null); if kill -0 ${gwpid}; then timeout 10 top -bH -p $gwpid -d 1 >> $log; rc=$?; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
    fi
    maprutil_startResourceTraces
}

function maprutil_startResourceTraces() {
    if [[ "$ISCLIENT" -eq "0" ]] && [[ -e "/opt/mapr/roles" ]]; then
        nohup sh -c 'log="/opt/mapr/logs/mfsresusage.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=`pidof mfs`; if [ -n "$mfspid" ]; then st=$(date +%s%N | cut -b1-13); curtime=$(date "+%Y-%m-%d %H:%M:%S"); topline=$(top -bn 1 -p $mfspid | grep -v "^$" | tail -1 | awk '"'"'{ printf("%s\t%s\t%s\n",$6,$9,$10); }'"'"'); rc=$?; echo -e "$curtime\t$topline" >> $log; et=$(date +%s%N | cut -b1-13); td=$(echo "scale=2;1-(($et-$st)/1000)"| bc); sleep $td; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/gwresusage.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/gateway" ]]; do gwpid=$(cat /opt/mapr/pid/gateway.pid 2>/dev/null); if kill -0 ${gwpid}; then st=$(date +%s%N | cut -b1-13); curtime=$(date "+%Y-%m-%d %H:%M:%S"); topline=$(top -bn 1 -p $gwpid | grep -v "^$" | tail -1 | awk '"'"'{ printf("%s\t%s\t%s\n",$6,$9,$10); }'"'"'); rc=$?; echo -e "$curtime\t$topline" >> $log; et=$(date +%s%N | cut -b1-13); td=$(echo "scale=2;1-(($et-$st)/1000)"| bc); sleep $td; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
    fi
}

function maprutil_killTraces() {
    util_kill "timeout"
    util_kill "guts"
    util_kill "dstat"
    util_kill "iostat"
    util_kill "top -b"
    util_kill "runTraces"
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
    maprutil_buildDiskList "$diskfile"

    if [ "$hostip" != "$cldbnode" ] && [ "$(ssh_check root $cldbnode)" != "enabled" ]; then
        ssh_copyPublicKey "root" "$cldbnode"
    fi

    local extops=
    if [ -n "$GLB_SECURE_CLUSTER" ]; then
        extops="-secure"
        pushd /opt/mapr/conf/ > /dev/null 2>&1
        rm -rf cldb.key ssl_truststore ssl_keystore cldb.key maprserverticket /tmp/maprticket_* > /dev/null 2>&1
        popd > /dev/null 2>&1
        if [ "$hostip" = "$cldbnode" ]; then
            extops=$extops" -genkeys"
        else
            maprutil_copySecureFilesFromCLDB "$cldbnode" "$cldbnodes" "$zknodes"
        fi
    fi

    if [ "$ISCLIENT" -eq 1 ]; then
        log_info "[$hostip] /opt/mapr/server/configure.sh -c -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3 $extops"
        # SSH session exits after running for few seconds with error "Write failed: Broken pipe"; Running in background and waiting
        /opt/mapr/server/configure.sh -c -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3 $extops &
    else
        log_info "[$hostip] /opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3 $extops"
        /opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3 $extops &
    fi
    wait

    # Perform series of custom configuration based on selected options
    maprutil_customConfigure

    # Return if configuring client node after this
    if [ "$ISCLIENT" -eq 1 ]; then
        log_info "[$hostip] Done configuring client node"
        return 
    fi

    [ -n "$GLB_TRIM_SSD" ] && log_info "[$hostip] Trimming the SSD disks if present..." && util_trimSSDDrives "$(cat $diskfile)"
    
    #echo "/opt/mapr/server/disksetup -FM /tmp/disklist"
    local multimfs=$GLB_MULTI_MFS
    local numsps=$GLB_NUM_SP
    local numdisks=`wc -l $diskfile | cut -f1 -d' '`
    if [ -n "$multimfs" ] && [ "$multimfs" -gt 0 ]; then
        if [ "$multimfs" -gt "$numdisks" ]; then
            log_info "Node ["`hostname -s`"] has fewer disks than mfs instances. Defaulting # of mfs to # of disks"
            multimfs=$numdisks
        fi
        local numstripe=$(echo $numdisks/$multimfs|bc)
        if [ -n "$numsps" ] && [ "$numsps" -le "$numdisks" ]; then
            numstripe=$(echo "$numdisks/$numsps"|bc)
        else
            numsps=
        fi
        # SSH session exits after running for few seconds with error "Write failed: Broken pipe"; Running in background and waiting
        /opt/mapr/server/disksetup -FW $numstripe $diskfile &
    elif [[ -n "$numsps" ]] &&  [[ "$numsps" -le "$numdisks" ]]; then
        if [ $((numdisks%2)) -eq 1 ] && [ $((numsps%2)) -eq 0 ]; then
            numdisks=$(echo "$numdisks+1" | bc)
        fi
        local numstripe=$(echo "$numdisks/$numsps"|bc)
        /opt/mapr/server/disksetup -FW $numstripe $diskfile &
    else
        /opt/mapr/server/disksetup -FM $diskfile &
    fi
    for i in {1..20}; do echo -ne "."; sleep 1; done
    wait

    # Add root user to container-executor.cfg
    maprutil_addRootUserToCntrExec

    # Start zookeeper
    service mapr-zookeeper start 2>/dev/null
    
    # Restart services on the node
    maprutil_restartWarden > /dev/null 2>&1

   if [ "$hostip" = "$cldbnode" ]; then
        maprutil_mountSelfHosting
        maprutil_applyLicense
        if [ -n "$multimfs" ] && [ "$multimfs" -gt 0 ]; then
            maprutil_configureMultiMFS "$multimfs" "$numsps"
        fi
        if [ -n "$GLB_CLDB_TOPO" ]; then
            maprutil_configureCLDBTopology || exit 1
        fi
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
    local scriptpath="$RUNTEMPDIR/configurenode_${hostnode: -3}.sh"
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
    if [ -z "$1" ] && [ -z "$2" ]; then
        return
    fi
    local esnodes=$(util_getCommaSeparated "$1")
    local otnodes=$(util_getCommaSeparated "$2")
    
    local cmd="/opt/mapr/server/configure.sh "
    if [ -n "$esnodes" ]; then
        cmd=$cmd" -ES "$esnodes
    fi
    if [ -n "$otnodes" ]; then
        cmd=$cmd" -OT "$otnodes
    fi
    cmd=$cmd" -R"

    log_info "$cmd"
    bash -c "$cmd"

    #maprutil_restartWarden
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
    
    if [ "$cldbisup" = "true" ] && [ "$ISCLIENT" -eq 0 ]; then
        ssh_copyFromCommandinBG "root" "$cldbhost" "/tmp/maprticket_*" "/tmp" 2>/dev/null
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
        ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/conf/cldb.key" "/opt/mapr/conf/"; maprutil_addToPIDList "$!" 
    fi
    if [ "$ISCLIENT" -eq 0 ]; then
        ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/conf/ssl_keystore" "/opt/mapr/conf/"; maprutil_addToPIDList "$!" 
        ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/conf/maprserverticket" "/opt/mapr/conf/"; maprutil_addToPIDList "$!" 
    fi
    ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/conf/ssl_truststore" "/opt/mapr/conf/"; maprutil_addToPIDList "$!" 
    
    maprutil_wait

    if [ "$ISCLIENT" -eq 0 ]; then
        chown mapr:mapr /opt/mapr/conf/maprserverticket > /dev/null 2>&1
        chmod +600 /opt/mapr/conf/maprserverticket /opt/mapr/conf/ssl_keystore > /dev/null 2>&1
    fi
    chmod +444 /opt/mapr/conf/ssl_truststore > /dev/null 2>&1
}
# @param host ip
# @param config file path
# @param cluster name
# @param don't wait
function maprutil_postConfigureOnNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
     # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/postconfigurenode_${hostnode: -3}.sh"
    maprutil_buildSingleScript "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local esnodes=$(maprutil_getESNodes "$2")
    local otnodes=$(maprutil_getOTSDBNodes "$2")
    
    echo "maprutil_postConfigure \""$esnodes"\" \""$otnodes"\" || exit 1" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$3" ]; then
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
        newchangeset=$(ssh_executeCommandasRoot "$node" "yum clean all > /dev/null 2>&1; yum --showduplicates list mapr-core | grep -v '$curchangeset' | awk '{if(match(\$2,/[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.GA/)) print \$0}' | tail -n1 | awk '{print \$2}' | cut -d'.' -f4")
    elif [ "$nodeos" = "ubuntu" ]; then
        newchangeset=$(ssh_executeCommandasRoot "$node" "apt-get update > /dev/null 2>&1; apt-cache policy mapr-core | grep Candidate | grep -v '$curchangeset' | awk '{print \$2}' | cut -d'.' -f4")
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
        maprversion=$(ssh_executeCommandasRoot "$node" "yum --showduplicates list mapr-core 2> /dev/null | grep mapr-core | awk '{if(match(\$2,/[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.GA/)) print \$0}' | tail -n1 | awk '{print \$2}' | cut -d'.' -f1-3")
    elif [ "$nodeos" = "ubuntu" ]; then
        maprversion=$(ssh_executeCommandasRoot "$node" "apt-cache policy mapr-core 2> /dev/null | grep Candidate | awk '{print \$2}' | cut -d'.' -f1-3")
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
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        ssh_executeCommandasRoot "$1" "sed -i 's/^enabled.*/enabled=0/g' /etc/yum.repos.d/*mapr*.repo > /dev/null 2>&1" > /dev/null 2>&1
        ssh_copyCommandasRoot "$node" "$2" "/etc/yum.repos.d/" > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        ssh_executeCommandasRoot "$1" "rm -rf /etc/apt/sources.list.d/*mapr*.list > /dev/null 2>&1" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "sed -i '/apt.qa.lab/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "sed -i '/artifactory.devops.lab/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1" > /dev/null 2>&1
        ssh_executeCommandasRoot "$1" "sed -i '/package.mapr.com/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1" > /dev/null 2>&1

        ssh_copyCommandasRoot "$node" "$2" "/etc/apt/sources.list.d/" > /dev/null 2>&1
    fi
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
    if [ "$nodeos" = "centos" ]; then
        meprepo="http://yum.qa.lab/opensource"
        [ -n "$GLB_MEP_REPOURL" ] && meprepo=$GLB_MEP_REPOURL
        [ -z "$GLB_PATCH_REPOFILE" ] && GLB_PATCH_REPOFILE="http://artifactory.devops.lab/artifactory/list/ebf-rpm/"

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
            echo "[QA-CustomPatchRepo]" >> $repofile
            echo "name=MapR Custom Repository" >> $repofile
            echo "baseurl=${GLB_PATCH_REPOFILE}" >> $repofile
            echo "enabled=1" >> $repofile
            echo "gpgcheck=0" >> $repofile
            echo "protect=1" >> $repofile
        fi
        echo >> $repofile
    elif [ "$nodeos" = "ubuntu" ]; then
        meprepo="http://apt.qa.lab/opensource"
        [ -n "$GLB_MEP_REPOURL" ] && meprepo=$GLB_MEP_REPOURL
        [ -z "$GLB_PATCH_REPOFILE" ] && GLB_PATCH_REPOFILE="http://artifactory.devops.lab/artifactory/list/ebf-deb/"

        echo "deb $meprepo binary/" > $repofile
        echo "deb ${repourl} mapr optional" >> $repofile
        [ -n "$GLB_PATCH_REPOURL" ] && echo "deb ${GLB_PATCH_REPOURL} mapr binary" >> $repofile
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
    if [ "$nodeos" = "centos" ]; then
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

    local tempdir="$RUNTEMPDIR/cmdrun"
    mkdir -p $tempdir > /dev/null 2>&1
    for node in ${nodes[@]}
    do
        local nodefile="$tempdir/$node.log"
        maprutil_runCommandsOnNode "$node" "$cmd" > $nodefile &
        maprutil_addToPIDList "$!" 
    done
    maprutil_wait > /dev/null 2>&1

    for node in ${nodes[@]}
    do
        local nodefile="$tempdir/$node.log"
        [ "$(cat $nodefile | wc -w)" -gt "0" ] && cat "$nodefile" 2>/dev/null
    done
    rm -rf $tempdir > /dev/null 2>&1
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
    local scriptpath="$RUNTEMPDIR/cmdonnode_${node: -3}.sh"
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
    local cmd=`$1 > /dev/null;echo $?`;
    local i=0
    while [ "${cmd}" -ne "0" ]; do
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
            ycsb)
                maprutil_createYCSBVolume
            ;;
            tablecreate)
                maprutil_createTableWithCompressionOff
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
            analyzecores)
                maprutil_analyzeCores
            ;;
            *)
            echo "Nothing to do!!"
            ;;
        esac
    done
}

function maprutil_createYCSBVolume () {
    log_msghead " *************** Creating YCSB Volume **************** "
    maprutil_runMapRCmd "maprcli volume create -name tables -path /tables -replication 3 -topology /data"
    maprutil_runMapRCmd "hadoop mfs -setcompression off /tables"
}

function maprutil_createTableWithCompression(){
    log_msghead " *************** Creating UserTable (/tables/usertable) with lz4 compression **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable" 
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname family -compression lz4 -maxversions 1"
}

function maprutil_createTableWithCompressionOff(){
    log_msghead " *************** Creating UserTable (/tables/usertable) with compression off **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable"
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname family -compression off -maxversions 1"
}

function maprutil_createJSONTable(){
    log_msghead " *************** Creating JSON UserTable (/tables/usertable) with compression off **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable -tabletype json "
}

function maprutil_addCFtoJSONTable(){
    log_msghead " *************** Creating JSON UserTable (/tables/usertable) with compression off **************** "
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname cfother -jsonpath field0 -compression off -inmemory true"
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
    
    local filepath=$GLB_TABLET_DIST
    local hostnode=$(hostname -f)

    local cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null |  grep cid: | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $4,$2}')
    local tabletContainers=$(maprcli table region list -path $filepath -json 2>/dev/null | grep -v 'secondary' | grep -A10 $hostnode | grep fid | cut -d":" -f2 | cut -d"." -f1 | tr -d '"')
    if [ -z "$tabletContainers" ]; then
        return
    fi
    local storagePools=$(/opt/mapr/server/mrconfig sp list 2>/dev/null | grep name | cut -d":" -f2 | awk '{print $2}' | tr -d ',' | sort -n -k1.3)
    local numTablets=$(echo "$tabletContainers" | wc -l)
    local numContainers=$(echo "$tabletContainers" | sort | uniq | wc -l)
    log_msg "$(util_getHostIP) : [# of tablets: $numTablets], [# of containers: $numContainers]"

    for sp in $storagePools; do
        local spcntrs=$(echo "$cntrlist" | grep -w $sp | awk '{print $2}')
        local cnt=$(echo "$tabletContainers" |  grep -Fw "${spcntrs}" | wc -l)
        local numcnts=$(echo "$tabletContainers" |  grep -Fw "${spcntrs}" | sort -n | uniq | wc -l)
        log_msg "\t$sp : $cnt Tablets (on $numcnts containers)"
    done
}

function maprutil_checkContainerDistribution(){
    if [[ ! -e "/opt/mapr/roles/fileserver" ]]; then
        return
    fi

    local hostip=$(util_getHostIP)
    local cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null |  grep cid: | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $2,$4}' | sort -n -k2.4)
    local numcnts=$(echo "$cntrlist" | wc -l)
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
    local hostip=$(util_getHostIP)
    local tablepath=$GLB_TABLET_DIST

    local indexlist=
    if [ -z "$GLB_INDEX_NAME" ] || [ "$GLB_INDEX_NAME" = "all" ]; then
        indexlist=$(maprcli table index list -path $tablepath -json 2>/dev/null | grep "indexFid\|indexName" | tr -d '"' | tr -d ',' | tr -d "'")
    else
        indexlist=$(maprcli table index list -path $tablepath -json 2>/dev/null | grep "indexFid\|indexName" | grep -iB1 "$GLB_INDEX_NAME" | tr -d '"' | tr -d ',' | tr -d "'")
    fi
    
    [ -z "$indexlist" ] && return

    local ciddump=$(/opt/mapr/server/mrconfig info dumpcontainers 2>/dev/null)
    local cids=$(echo "$ciddump" |  grep cid: | awk '{print $1}' | cut -d':' -f2 | sort -n | uniq | sed ':a;N;$!ba;s/\n/,/g')
    local localcids=$(maprcli dump containerinfo -ids $cids -json 2>/dev/null | grep 'ContainerId\|Master' | grep -B1 $hostip | grep ContainerId | tr -d '"' | tr -d ',' | tr -d "'" | cut -d':' -f2 | sed 's/^/\^/')

    local indexfids=$(echo "$indexlist" | grep indexFid | cut -d':' -f2)
    local tempdir=$(mktemp -d)

    for idxfid in $indexfids
    do
        local idxcntr=$(echo $idxfid | cut -d'.' -f1)
        local tabletsubfid=$(maprcli debugdb dump -fid $idxfid -json 2>/dev/null | grep -A2 tabletmap | grep fid | cut -d'.' -f2- | tr -d '"')
        local tabletmapfid="${idxcntr}.${tabletsubfid}"
        local idxtabletfids=$(maprcli debugdb dump -fid $tabletmapfid -json 2>/dev/null | grep fid | cut -d':' -f2 | tr -d '"' | grep "$localcids")

        local totaltablets=$(echo "$idxtabletfids" | wc -w)
        [ "$totaltablets" -lt "1" ] && continue
        local indexname=$(echo "$indexlist" | grep -A1 $idxfid | grep indexName | cut -d':' -f2)
        
        local sleeptime=5
        local maxnumcli=$(echo $(nproc)/2|bc)
        local i=1
        local indexlog="$tempdir/$indexname.log"
        for tabletfid in $idxtabletfids
        do
            maprutil_printTabletStats "$i" "$tabletfid" >> $indexlog &
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
            log_msg "\n\t$(util_getHostIP) : Index '$indexname' [ #ofTablets: ${totaltablets}, Size: ${indexSize} GB, #ofRows: ${numrows} ]"
            cat "$indexlog" | sort -nk2.3 2>/dev/null
        fi
    done
    
    rm -rf $tempdir > /dev/null 2>&1
}

function maprutil_printTabletStats(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local tabletindex=$1
    local tabletfid=$2

    local tabletinfo=$(maprcli debugdb dump -fid $tabletfid -json | grep 'numLogicalBlocks\|numRows\|numRowsWithDelete\|numSpills\|numSegments' | tr -d '"' | tr -d ',')
    local tabletsize=$(echo "$tabletinfo" |  grep numLogicalBlocks | cut -d':' -f2 | awk '{sum+=$1}END{print sum*8192/1073741824}')
    tabletsize=$(printf "%.2f\n" $tabletsize)
    local numrows=$(echo "$tabletinfo" | grep numRows | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
    local numdelrows=$(echo "$tabletinfo" | grep numRowsWithDelete | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
    local numspills=$(echo "$tabletinfo" | grep numSpills | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
    local numsegs=$(echo "$tabletinfo" | grep numSegments | cut -d':' -f2 | awk '{sum+=$1}END{print sum}')
    log_msg "\t\t Tablet #${tabletindex} [$tabletfid] Size: $tabletsize GB, #ofRows: $numrows, #ofDelRows: $numdelrows, #ofSegments: $numsegs, #ofSpills: $numspills"
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
            all)
                maprutil_getMapRInfo
                util_getMachineInfo
                util_getCPUInfo
                util_getMemInfo
                util_getNetInfo
                util_getDiskInfo
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
    if [ "$nodeos" = "centos" ]; then
        local rpms=$(rpm -qa | grep mapr)
        patch=$(echo "$rpms" | grep mapr-patch | cut -d'-' -f4 | cut -d'.' -f1)
        client=$(echo "$rpms" | grep mapr-client | cut -d'-' -f3)
        bins=$(echo "$rpms" | grep mapr- | sort | cut -d'-' -f1-2 | tr '\n' ' ')
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
    if [ -e "/opt/mapr/conf/mapr-clusters.conf" ]; then
        nummfs=$(timeout 10 /opt/mapr/server/mrconfig info instances 2>/dev/null| head -1)
        numsps=$(timeout 10 /opt/mapr/server/mrconfig sp list 2>/dev/null| grep SP[0-9] | wc -l)
        #command -v maprcli >/dev/null 2>&1 && sppermfs=$(maprcli config load -json 2>/dev/null| grep multimfs.numsps.perinstance | tr -d '"' | tr -d ',' | cut -d':' -f2)
        sppermfs=$(timeout 10 /opt/mapr/server/mrconfig sp list -v 2>/dev/null| grep SP[0-9] | awk '{print $18}' | tr -d ',' | uniq -c | awk '{print $1}' | sort -nr | head -1)
        #[[ "$nummfs" -gt "1" ]] && [[ "$sppermfs" -eq "0" ]] && sppermfs=$(/opt/mapr/server/mrconfig sp list -v 2>/dev/null| grep SP[0-9] | awk '{print $18}' | tr -d ',' | uniq -c | awk '{print $1}' | sort -nr | head -1)
        [[ "$sppermfs" -eq 0 ]] && sppermfs=$numsps
        command -v maprcli >/dev/null 2>&1 && nodetopo=$(timeout 10 maprcli node list -json | grep "$(hostname -f)" | grep racktopo | sed "s/$(hostname -f)//g" | cut -d ':' -f2 | tr -d '"' | tr -d ',')
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
    [ -n "$cpucores" ] && cpucores=$(echo "$cpucores" | uniq)
    if [ -n "$cpucores" ] && [ "$(echo $cpucores | wc -w)" -gt "1" ]; then
        log_warn "CPU cores do not match. Not a homogeneous cluster"
        cpucores=$(echo "$cpucores" | sort -nr | head -1)
    elif [ -n "$cpucores" ]; then
        cpucores="2 x $cpucores"
    fi
    
    if [ -z "$cpucores" ]; then
        cpucores=$(echo "$sysinfo" | grep -A1 cores | grep -B1 Disabled | grep cores | cut -d ':' -f2 | sed 's/ *//g' | uniq)
        [ -n "$cpucores" ] && [ "$(echo $cpucores | wc -w)" -gt "1" ] && log_warn "CPU cores do not match. Not a homogeneous cluster" && cpucores=$(echo "$cpucores" | sort -nr | head -1)
    fi

    hwspec="$cpucores cores"
    ## Disk
    local numdisks=$(echo "$sysinfo" | grep "Disk Info" | cut -d':' -f3 | tr -d ']' | sed 's/ *//g')
    if [ -n "$numdisks" ]; then 
        [ "$(echo $numdisks| wc -w)" -ne "$numnodes" ] && log_warn "Few nodes do not have disks"
        numdisks=$(echo "$numdisks" | uniq)
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
    
    local disktype=$(echo "$diskstr" | awk '{print $4}' | tr -d ',' | uniq)
    if [ "$(echo $disktype | wc -w)" -gt "1" ]; then
        log_warn "Mix of HDD & SSD disks. Not a homogeneous cluster"
        disktype=$(echo "$diskstr" | awk '{print $4}' | tr -d ',' | uniq -c | sort -nr | awk '{print $2}' | tr '\n' ' ')
    fi

    local disksize=$(echo "$diskstr" | awk '{print $6}' | uniq)
    if [ "$(echo $disksize | wc -w)" -gt "1" ]; then
        local dz=
        for d in $disksize
        do
            local sz=$(util_getNearestPower2 $d)
            [ -z "$dz" ] && dz=$sz
            [ "$sz" -ne "$dz" ] && log_warn "Disks are of different capacities"
        done
        disksize=$(echo "$diskstr" | awk '{print $6}' | uniq | sort -nr | head -1)
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
    local memorystr=$(echo "$sysinfo" | grep Memory | grep -v Info | cut -d':' -f2)
    local memcnt=$(echo "$memorystr" | wc -l)
    if [ -n "$memorystr" ]; then 
        [ "$memcnt" -ne "$numnodes" ] && log_warn "No memory listed for few nodes"
        memory=$(echo "$memorystr" | awk '{print $1}' | uniq)
        local gb=$(echo "$memorystr" | awk '{print $2}' | uniq | sort -nr | head -1)
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
        local mtus=$(echo "$nwstr" | awk '{print $4}' | tr -d ',' | uniq)
        if [ "$(echo $mtus | wc -w)" -gt "1" ]; then
            log_warn "MTUs on the NIC(s) are not same"
            mtus=$(echo "$mtus" | sort -nr | head -1)
        fi
        local nwsp=$(echo "$nwstr" | awk '{print $8}' | tr -d ',' | uniq)
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
        os=$(echo "$osstr" | awk '{print $1}' | uniq)
        local ver=$(echo "$osstr" | awk '{print $2}' | uniq | sort -nr | head -1)
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
        local maprver=$(echo "$maprverstr" | awk '{print $1}' | uniq)
        local maprpver=$(echo "$maprverstr" | grep patch | awk '{print $2,$3}' | uniq | head -1)
        if [ "$(echo $maprver | wc -w)" -gt "1" ]; then
            log_warn "Different versions of MapR installed."
            maprver=$(echo "$maprver" | sort -nr | head -1)
        fi
        [ -n "$maprpver" ] && maprver="$maprver $maprpver"

        local nummfs=$(echo "$maprstr" | grep "# of MFS" | cut -d':' -f2 | sed 's/^ //g' | uniq )
        if [ "$(echo $nummfs | wc -w)" -gt "1" ]; then
             log_warn "Different # of MFS configured on nodes"
             nummfs=$(echo "$nummfs" | sort -nr | head -1)
        fi

        local numsps=$(echo "$maprstr" | grep "# of SPs" | awk '{print $5}' | uniq )
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
        log_info "[$(util_getHostIP)] Waiting for CLDB to come up before applying license.... sleeping 30s"
        if [ "$jobs" -ne 0 ]; then
            local licenseExists=`/opt/mapr/bin/maprcli license list | grep M7 | wc -l`
            if [ "$licenseExists" -ne 0 ]; then
                jobs=0
            else
                sleep 30
            fi
        fi
        ### Attempt using Downloaded License
        if [ "${jobs}" -ne "0" ]; then
            jobs=$(/opt/mapr/bin/maprcli license add -license /tmp/LatestDemoLicense-M7.txt -is_file true > /dev/null;echo $?);
        fi
        let i=i+1
        if [ "$i" -gt 10 ]; then
            log_error "Failed to apply license. Node may not be configured correctly"
            exit 1
        fi
        if [[ -n "$GLB_SECURE_CLUSTER" ]] && [[ ! -e "/tmp/maprticket_0" ]]; then
            echo 'mapr' | maprlogin password  2>/dev/null
            echo 'mapr' | su mapr -c 'maprlogin password' 2>/dev/null
        fi
    done

    if [[ "${jobs}" -eq "0" ]] && [[ -n "$GLB_HAS_FUSE" ]]; then
        local clusterid=$(maprcli dashboard info -json | grep -A5 cluster | grep id | tr -d '"' | tr -d ',' | cut -d':' -f2)
        local expdate=$(date -d "+30 days" +%Y-%m-%d)
        local licfile="/tmp/LatestFuseLicensePlatinum.txt"
        curl -F 'username=maprmanager' -F 'password=maprmapr' -X POST --cookie-jar /tmp/tmpckfile https://apitest.mapr.com/license/authenticate/ 2>/dev/null
        curl --cookie /tmp/tmpckfile -X POST -F "license_type=additionalfeatures_posixclientplatinum" -F "cluster=${clusterid}" -F "customer_name=maprqa" -F "expiration_date=${expdate}" -F "number_of_nodes=${GLB_CLUSTER_SIZE}" -F "enforcement_type=HARD" https://apitest.mapr.com/license/licenses/createlicense/ -o ${licfile} 2>/dev/null
        [ -e "$licfile" ] && /opt/mapr/bin/maprcli license add -license ${licfile} -is_file true > /dev/null
    fi
}

function maprutil_waitForCLDBonNode(){
    local node=$1
    
    local scriptpath="$RUNTEMPDIR/waitforcldb_${node: -3}.sh"
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
        [[ "${binary}" =~ mapr-hbase|mapr-client|mapr-patch|mapr-asynchbase|mapr-posix|mapr-loopbacknfs ]] && continue
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
    if [ -n "$(echo $roles | grep 'hbinternal\|asynchbase\|loopbacknfs')" ]; then
        roles=$(echo $roles | sed 's/hbinternal//g;s/asynchbase//g;s/loopbacknfs//g')
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

    local scriptpath="$RUNTEMPDIR/checksetuponnode_${node: -3}.sh"
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
    local scriptpath="$RUNTEMPDIR/restartonnode_${node: -3}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    if [ -n "$(maprutil_isClientNode $rolefile $node)" ]; then
        return
    fi
    
    echo "maprutil_restartWarden \"$stopstart\"" >> $scriptpath
   
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
        wait $pid
        local errcode=$?
        #if [ "$errcode" -eq "0" ]; then
        #    log_info "$pid completed successfully"
        #else 
        if [ "$errcode" -ne "0" ]; then
            log_warn "Child process [$pid] exited with errorcode : $errcode"
            [ -z "$GLB_EXIT_ERRCODE" ] && GLB_EXIT_ERRCODE=$errcode
        fi
    done
    GLB_BG_PIDS=()
}

# @param timestamp
function maprutil_zipDirectory(){
    local timestamp=$1
    local fileregex=$2

    local tmpdir="/tmp/maprlogs/$(hostname -f)/"
    local logdir="/opt/mapr/logs"
    local buildid=$(cat /opt/mapr/MapRBuildVersion)
    local tarfile="maprlogs_$(hostname -f)_$buildid_$timestamp.tar.bz2"

    mkdir -p $tmpdir > /dev/null 2>&1
    # Copy configurations files 
    maprutil_copyConfsToDir "$tmpdir"
    # Copy the logs
    cd $tmpdir
    if [ -z "$fileregex" ]; then
        cp -r $logdir logs  > /dev/null 2>&1
    else
        [ -z "$(ls $logdir/$fileregex 2> /dev/null)" ] && return
        mkdir -p logs  > /dev/null 2>&1
        cp -r $logdir/$fileregex logs > /dev/null 2>&1
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
    
    local scriptpath="$RUNTEMPDIR/zipdironnode_${node: -3}.sh"
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
    
    ssh_copyFromCommandinBG "root" "$node" "$filetocopy" "$copyto" > /dev/null 2>&1
}

function maprutil_copymfstrace(){
    local node=$1
    local timestamp=$2
    local copyto=$3
    mkdir -p $copyto > /dev/null 2>&1
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local dirtocopy="/tmp/mfstrace/$timestamp/$host"

    ssh_copyFromCommandinBG "root" "$node" "$dirtocopy" "$copyto" > /dev/null 2>&1
}

function maprutil_mfstraceonNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi

    local node=$1
    local timestamp=$2
    local iter=$3
    
    local scriptpath="$RUNTEMPDIR/mfsrtace_${node: -3}.sh"
    maprutil_buildSingleScript "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo "maprutil_mfstrace \"$timestamp\" \"$iter\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_mfstrace(){
    [ ! -e "/opt/mapr/roles/fileserver" ] && return
    local mfspid=$(pidof mfs)
    [ -z "$mfspid" ] && return
    
    local timestamp=$1
    local iter=$2
    [ -z "$iter" ] && iter=10
    local tmpdir="/tmp/mfstrace/$timestamp/$(hostname -f)"
    mkdir -p $tmpdir > /dev/null 2>&1

    for i in $(seq $iter)
    do
        local tracefile="$tmpdir/mfstrace_$(date '+%Y-%m-%d-%H-%M-%S')"
        gstack $mfspid > $tracefile
        sleep 1
    done
}

function maprutil_analyzeCores(){
    local cores=$(ls -ltr /opt/cores | grep 'mfs.core\|java.core' | awk '{print $9}')
    [ -z "$cores" ] && return

    echo
    log_msghead "[$(util_getHostIP)] Analyzing $(echo $cores | wc -w) core file(s)"
    for core in $cores
    do
        local tracefile="/opt/mapr/logs/$core.gdbtrace"
        maprutil_debugCore "/opt/cores/$core" $tracefile > /dev/null 2>&1 &
        while [ "$(ps -ef | grep "[g]db -ex" | wc -l)" -gt "5" ]; do
            sleep 1
        done 
    done
    wait

    local i=1
    for core in $cores
    do
        local tracefile="/opt/mapr/logs/$core.gdbtrace"
        local ftime=$(date -r /opt/cores/$core +'%Y-%m-%d %H:%M:%S')
        log_msg "\n\t Core #${i} : [$ftime] $core ( $tracefile )"
        local backtrace=$(maprutil_debugCore "/opt/cores/$core" $tracefile)

        if [ -n "$(cat $tracefile | grep "is truncated: expected")" ]; then
            log_msg "\t\t Core file is truncated"
        elif [ -n "$backtrace" ]; then
            if [ -z "$GLB_LOG_VERBOSE" ]; then
                echo -e "$backtrace" | sed 's/^/\t\t/'
            else
                cat $tracefile | sed -e '1,/Thread debugging using/d' | sed 's/^/\t\t/'
            fi
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
    local newcore=
    local isjava=$(echo $corefile | grep "java.core")

    if [ -z "$(find $tracefile -type f -size +15k 2> /dev/null)" ]; then
        if [ -z "$isjava" ]; then
            gdb -ex "thread apply all bt" --batch -c ${corefile} /opt/mapr/server/mfs > $tracefile 2>&1    
        else
            gdb -ex "thread apply all bt" --batch -c ${corefile} $(which java) > $tracefile 2>&1
        fi
        newcore=1
    fi
    local btline=$(cat $tracefile | grep -B10 -n "mapr::fs::FileServer::CoreHandler" | grep "Thread [0-9]*" | tail -1 | cut -d '-' -f1)
    [ -z "$btline" ] && btline=$(cat $tracefile | grep -B10 -n  "abort ()" | grep "Thread [0-9]*" | tail -1 | cut -d '-' -f1)
    [ -z "$btline" ] && btline=$(cat $tracefile | grep -n "Thread 1 " | cut -f1 -d:)
    local backtrace=$(cat $tracefile | sed -n "${btline},/^\s*$/p")
    [ -n "$backtrace" ] && btthread=$(echo "$backtrace" | head -1 | awk '{print $2}')
    if [ -z "$isjava" ] && [ -n "$newcore" ] && [ -n "$btthread" ]; then
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
    [ -n "$backtrace" ] && echo "$backtrace" | sed  -n '/Switching to thread/q;p'
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
  local cldbnodes=
  local mfsnodes=
  log_msg "Enter Cluster Node IPs ( ex: 10.10.103.[39-40,43-49] ) : "
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
