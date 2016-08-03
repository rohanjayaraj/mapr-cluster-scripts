#!/bin/bash


################  
#
#   utilities
#
################

lib_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$lib_dir/utils.sh"
source "$lib_dir/ssh.sh"

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
        echo $newbinlist
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
    
    local isclient=$(grep $2 $1 | grep 'mapr-client\|mapr-loopbacknfs' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
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
    dirlist+=("/tmp/mapr*")
    dirlist+=("/tmp/hsperfdata*")
    dirlist+=("/tmp/hadoop*")
    dirlist+=("/tmp/mapr*")
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
        *)
            echo "ERROR: unknown parameter passed to removedirs \"$PARAM\""
            ;;
    esac
       
}

# @param host ip
function maprutil_isMapRInstalledOnNode(){
    if [ -z "$1" ] ; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/isinstalled_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
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

function maprutil_isMapRInstalledOnNodes(){
    if [ -z "$1" ] ; then
        return
    fi
    local maprnodes=$1
    local tmpdir="$RUNTEMPDIR/installed"
    mkdir -p $tmpdir 2>/dev/null
    local yeslist=
    for node in ${maprnodes[@]}
    do
        local nodelog="$tmpdir/$node.log"
        maprutil_isMapRInstalledOnNode "$node" > $nodelog &
    done
    wait
    for node in ${maprnodes[@]}
    do
        local nodelog=$(cat $tmpdir/$node.log)
        if [ "$nodelog" = "true" ]; then
            yeslist=$yeslist"$node"" "
        fi
    done
    echo "$yeslist"
}

# @param host ip
function maprutil_getMapRVersionOnNode(){
    if [ -z "$1" ] ; then
        return
    fi
    local node=$1
    local version=$(ssh_executeCommandasRoot "$node" "[ -e '/opt/mapr/MapRBuildVersion' ] && cat /opt/mapr/MapRBuildVersion")
    if [ -n "$version" ]; then
        echo $version
    fi
}

function maprutil_unmountNFS(){
    local nfslist=$(mount | grep nfs | grep mapr | grep -v '10.10.10.20' | cut -d' ' -f3)
    for i in $nfslist
    do
        umount -l $i
    done
}

function maprutil_uninstall(){
    
    # Kill running traces 
    util_kill "timeout"
    util_kill "guts"
    util_kill "dstat"
    util_kill "iostat"
    util_kill "top -b"
    util_kill "runTraces"
    
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
        yum clean all
    elif [ "$nodeos" = "ubuntu" ]; then
        apt-get install -f -y
        apt-get autoremove -y
        apt-get update
    fi

    # Remove mapr shared memory segments
    util_removeSHMSegments "mapr"

    # kill all processes
    util_kill "initaudit.sh"
    util_kill "java" "jenkins" "elasticsearch"
    util_kill "timeout"
    util_kill "guts"
    util_kill "dstat"
    util_kill "iostat"
    util_kill "top -b"

    # Remove all directories
    maprutil_removedirs "all"
}

# @param host ip
function maprutil_uninstallNode(){
    if [ -z "$1" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/uninstallnode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
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

    util_upgradeBinaries "$upbins" "$buildversion"
    
    #mv /opt/mapr/conf/warden.conf  /opt/mapr/conf/warden.conf.old
    #cp /opt/mapr/conf.new/warden.conf /opt/mapr/conf/warden.conf
    if [ -e "/opt/mapr/roles/cldb" ]; then
        echo "Transplant any new changes in warden configs to /opt/mapr/conf/warden.conf. Do so manually!"
        diff /opt/mapr/conf/warden.conf /opt/mapr/conf.new/warden.conf
        if [ -d "/opt/mapr/conf/conf.d.new" ]; then
            echo "New configurations from /opt/mapr/conf/conf.d.new aren't merged with existing files. Do so manually!"
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
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    if [ -n "$GLB_BUILD_VERSION" ]; then
        echo "maprutil_setupLocalRepo" >> $scriptpath
    fi
    echo "maprutil_upgrade \""$GLB_BUILD_VERSION"\"" >> $scriptpath

    ssh_executeScriptasRootInBG "$hostnode" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$2" ]; then
        wait
    fi
}

# @param cldbnode
function maprutil_postUpgrade(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    ssh_executeCommandasRoot "$node" "timeout 50 maprcli config save -values {mapr.targetversion:\"\$(cat /opt/mapr/MapRBuildVersion)\"}" > /dev/null 2>&1
    ssh_executeCommandasRoot "$node" "timeout 10 maprcli node list -columns hostname,csvc" 
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
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    maprutil_addGlobalVars "$scriptpath"
    if [ -n "$GLB_BUILD_VERSION" ]; then
        echo "maprutil_setupLocalRepo" >> $scriptpath
    fi
    echo "util_installprereq" >> $scriptpath
    echo "util_installBinaries \""$2"\" \""$GLB_BUILD_VERSION"\"" >> $scriptpath

    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$3" ]; then
        wait
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
    while [ "$failcnt" -gt 0 ] && [ "$iter" -lt 5 ]; do
        failcnt=0;
        maprcli  config save -values {multimfs.numinstances.pernode:${nummfs}}
        let failcnt=$failcnt+`echo $?`
        maprcli  config save -values {multimfs.numsps.perinstance:${numspspermfs}}
        let failcnt=$failcnt+`echo $?`
        sleep 30;
        let iter=$iter+1;
    done
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
        <value>64</value>
    </property>
</configuration>
EOL
    done
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
     local putbuffer=$GLB_PUT_BUFFER
    if [ -n "$putbuffer" ]; then
        maprutil_addPutBufferThreshold "core-site.xml" "$putbuffer"
    fi
}

# @param force move CLDB topology
function maprutil_configureCLDBTopology(){
    
    local datatopo=$(maprcli node list -json | grep racktopo | grep "/data/" | wc -l)
    local numdnodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | wc -l) 
    local j=0
    while [ "$numdnodes" -ne "$GLB_CLUSTER_SIZE" ] && [ -z "$1" ]; do
        sleep 5
        numdnodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | wc -l) 
        let j=j+1
        if [ "$j" -gt 12 ]; then
            break
        fi
    done
    let numdnodes=numdnodes-1

    if [ "$datatopo" -eq "$numdnodes" ]; then
        return
    fi
    #local clustersize=$(maprcli node list -json | grep 'id'| wc -l)
    local clustersize=$GLB_CLUSTER_SIZE
    if [ "$clustersize" -gt 4 ] || [ -n "$1" ]; then
        ## Move all nodes under /data topology
        local datanodes=`maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | tr "\n" ","`
        maprcli node move -serverids "$datanodes" -topology /data 2>/dev/null
        ### Moving CLDB Node to CLDB topology
        local cldbnode=`maprcli node cldbmaster | grep ServerID | awk {'print $2'}`
        maprcli node move -serverids "$cldbnode" -topology /cldb 2>/dev/null
        ### Moving CLDB Volume as well
        maprcli volume move -name mapr.cldb.internal -topology /cldb 2>/dev/null
    fi
}

function maprutil_moveTSDBVolumeToCLDBTopology(){
    local tsdbexists=$(maprcli volume info -path /mapr.monitoring -json | grep ERROR)
    local cldbtopo=$(maprcli node topo -path /cldb)
    if [ -n "$tsdbexists" ] || [ -z "$cldbtopo" ]; then
        echo "OpenTSDB not installed or CLDB not moved to /cldb topology"
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
    local disklist=$(util_getRawDisks)

    local limit=$GLB_MAX_DISKS
    local numdisks=$(wc -l $diskfile | cut -f1 -d' ')
    if [ -n "$limit" ] && [ "$numdisks" -gt "$limit" ]; then
         local newlist=$(head -n $limit $diskfile)
         echo "$newlist" > $diskfile
    fi
}

function maprutil_startTraces() {
    if [ "$ISCLIENT" -eq 0 ] && [ -e "/opt/mapr/roles" ]; then
        nohup sh -c 'ec=124; while [ "$ec" -eq 124 ]; do timeout 14 /opt/mapr/bin/guts time:all flush:line cache:all db:all rpc:all log:all dbrepl:all >> /opt/mapr/logs/guts.log; ec=$?; done'  > /dev/null &
        nohup sh -c 'ec=124; while [ "$ec" -eq 124 ]; do timeout 14 dstat -tcdnim >> /opt/mapr/logs/dstat.log; ec=$?; done' > /dev/null &
        nohup iostat -dmxt 1 > /opt/mapr/logs/iostat.log &
        nohup sh -c 'rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=`pidof mfs`; if [ -n "$mfspid" ]; then timeout 10 top -bH -p $mfspid -d 1 >> /opt/mapr/logs/mfstop.log; rc=$?; else sleep 10; fi; done' > /dev/null &
    fi
}

function maprutil_configure(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    local diskfile="/tmp/disklist"
    local hostip=$(util_getHostIP)
    local cldbnodes=$(util_getCommaSeparated "$1")
    local zknodes=$(util_getCommaSeparated "$2")
    maprutil_buildDiskList "$diskfile"

    if [ "$ISCLIENT" -eq 1 ]; then
        echo "[$hostip] /opt/mapr/server/configure.sh -c -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3"
        /opt/mapr/server/configure.sh -c -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3
    else
        echo "[$hostip] /opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3"
        /opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3
    fi
    
    # Perform series of custom configuration based on selected options
    maprutil_customConfigure

    # Return if configuring client node after this
    if [ "$ISCLIENT" -eq 1 ]; then
        echo "[$hostip] Done configuring client node"
        return 
    fi

    #echo "/opt/mapr/server/disksetup -FM /tmp/disklist"
    local multimfs=$GLB_MULTI_MFS
    local numsps=$GLB_NUM_SP
    local numdisks=`wc -l $diskfile | cut -f1 -d' '`
    if [ -n "$multimfs" ] && [ "$multimfs" -gt 1 ]; then
        if [ "$multimfs" -gt "$numdisks" ]; then
            echo "[ERROR] Node ["`hostname -s`"] has fewer disks than mfs instances. Defaulting # of mfs to # of disks"
            multimfs=$numdisks
        fi
        local numstripe=$(echo $numdisks/$multimfs|bc)
        if [ -n "$numsps" ] && [ "$numsps" -le "$numdisks" ]; then
            numstripe=$(echo "$numdisks/$numsps"|bc)
        else
            numsps=
        fi
        /opt/mapr/server/disksetup -FW $numstripe $diskfile
    elif [[ -n "$numsps" ]] &&  [[ "$numsps" -le "$numdisks" ]]; then
        if [ $((numdisks%2)) -eq 1 ] && [ $((numsps%2)) -eq 0 ]; then
            numdisks=$(echo "$numdisks+1" | bc)
        fi
        local numstripe=$(echo "$numdisks/$numsps"|bc)
        /opt/mapr/server/disksetup -FW $numstripe $diskfile
    else
        /opt/mapr/server/disksetup -FM $diskfile
    fi

    # Add root user to container-executor.cfg
    maprutil_addRootUserToCntrExec

    # Start zookeeper
    service mapr-zookeeper start 2>/dev/null
    
    # Restart services on the node
    maprutil_restartWarden > /dev/null 2>&1

    local cldbnode=$(util_getFirstElement "$1")
    if [ "$hostip" = "$cldbnode" ]; then
        maprutil_applyLicense
        if [ -n "$multimfs" ] && [ "$multimfs" -gt 1 ]; then
            maprutil_configureMultiMFS "$multimfs" "$numsps"
        fi
        local cldbtopo=$GLB_CLDB_TOPO
        if [ -n "$cldbtopo" ]; then
            sleep 30
            maprutil_configureCLDBTopology
        fi
    fi

    if [ -n "$GLB_TRACE_ON" ]; then
        maprutil_startTraces
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
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/configurenode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local hostip=$(util_getHostIP)
    local cldbnodes=$(maprutil_getCLDBNodes "$2")
    local zknodes=$(maprutil_getZKNodes "$2")
    local client=$(maprutil_isClientNode "$2" "$hostnode")
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath

    maprutil_addGlobalVars "$scriptpath"
    if [ -n "$client" ]; then
         echo "ISCLIENT=1" >> $scriptpath
    else
        echo "ISCLIENT=0" >> $scriptpath
    fi
    
    echo "maprutil_configure \""$cldbnodes"\" \""$zknodes"\" \""$3"\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$4" ]; then
        wait
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

    echo "$cmd"
    bash -c "$cmd"

    #maprutil_restartWarden
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
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local esnodes=$(maprutil_getESNodes "$2")
    local otnodes=$(maprutil_getOTSDBNodes "$2")
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath

    maprutil_addGlobalVars "$scriptpath"
    
    echo "maprutil_postConfigure \""$esnodes"\" \""$otnodes"\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$3" ]; then
        wait
    fi
}

# @param script path
function maprutil_addGlobalVars(){
    if [ -z "$1" ]; then
        return
    fi
    local scriptpath=$1
    local glbvars=$( set -o posix ; set  | grep GLB_)
    for i in $glbvars
    do
        #echo "%%%%%%%%%% -> $i <- %%%%%%%%%%%%%"
        if [[ "$i" =~ ^GLB_BG_PIDS.* ]]; then
            continue
        elif [[ ! "$i" =~ ^GLB_.* ]]; then
            continue
        fi
        echo $i >> $scriptpath
    done
}

function maprutil_getBuildID(){
    local buildid=`yum info mapr-core installed  | grep Version | tr "." " " | awk '{print $6}'`
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
        retval=$(ssh_executeCommandasRoot "$node" "apt-cache policy mapr-core | grep $buildid")
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
        newchangeset=$(ssh_executeCommandasRoot "$node" "yum --showduplicates list mapr-core | grep -v '$curchangeset' | tail -n1 | awk '{print \$2}' | cut -d'.' -f4")
    elif [ "$nodeos" = "ubuntu" ]; then
        newchangeset=$(ssh_executeCommandasRoot "$node" "apt-cache policy mapr-core | grep Candidate | grep -v '$curchangeset' | awk '{print \$2}' | cut -d'.' -f4")
    fi

    if [[ -n "$newchangeset" ]] && [[ "$(util_isNumber $newchangeset)" = "true" ]] && [[ "$newchangeset" -gt "$curchangeset" ]]; then
        echo "$newchangeset"
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
        ssh_executeCommandasRoot "$1" "sed -i 's/^enabled.*/enabled = 0/g' /etc/yum.repos.d/*mapr*.repo > /dev/null 2>&1"
        ssh_copyCommandasRoot "$node" "$2" "/etc/yum.repos.d/"
    elif [ "$nodeos" = "ubuntu" ]; then
        ssh_executeCommandasRoot "$1" "sed -i '/apt.qa.lab/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1"
        ssh_executeCommandasRoot "$1" "sed -i '/artifactory.devops.lab/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1"
        ssh_executeCommandasRoot "$1" "sed -i '/package.mapr.com/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1"
        ssh_copyCommandasRoot "$node" "$2" "/etc/apt/sources.list.d/"
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
    if [ "$nodeos" = "centos" ]; then
        echo "[QA-Opensource]" > $repofile
        echo "name=MapR Latest Build QA Repository" >> $repofile
        echo "baseurl=http://yum.qa.lab/opensource" >> $repofile
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
        echo >> $repofile
    elif [ "$nodeos" = "ubuntu" ]; then
        echo "deb http://apt.qa.lab/opensource binary/" > $repofile
        echo "deb ${repourl} binary ubuntu" >> $repofile
    fi
}

function maprutil_getRepoURL(){
    local nodeos=$(getOS)
    if [ "$nodeos" = "centos" ]; then
        local repolist=$(yum repolist enabled -v | grep -e Repo-id -e Repo-baseurl -e MapR | grep -A1 -B1 MapR | grep -v Repo-name | grep -iv opensource | grep Repo-baseurl | cut -d':' -f2- | tr -d " " | head -1)
        echo "$repolist"
    elif [ "$nodeos" = "ubuntu" ]; then
        local repolist=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $2}' | grep -iv opensource | head -1)
        echo "$repolist"
    fi
}

function maprutil_disableAllRepo(){
    local nodeos=$(getOS)
    if [ "$nodeos" = "centos" ]; then
        local repolist=$(yum repolist enabled -v | grep -e Repo-id -e Repo-baseurl -e MapR | grep -A1 -B1 MapR | grep -v Repo-name | grep -iv opensource | grep Repo-id | cut -d':' -f2 | tr -d " ")
        for repo in $repolist
        do
            echo "[$(util_getHostIP)] Disabling repository $repo"
            yum-config-manager --disable $repo > /dev/null 2>&1
        done
    elif [ "$nodeos" = "ubuntu" ]; then
        local repolist=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $2}' | grep -iv opensource | cut -d '/' -f3)
        for repo in $repolist
        do
           local repof=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep $repo | cut -d":" -f1)
           sed -i '/${repo}/s/^/#/' ${repof}
        done
    fi
}

# @param local repo path
function maprutil_addLocalRepo(){
    if [ -z "$1" ]; then
        return
    fi
    local nodeos=$(getOS)
    local repofile="$RUNTEMPDIR/maprbuilds/mapr-$GLB_BUILD_VERSION.repo"
    if [ "$nodeos" = "ubuntu" ]; then
        repofile="$RUNTEMPDIR/maprbuilds/mapr-$GLB_BUILD_VERSION.list"
    fi

    local repourl=$1
    echo "[$(util_getHostIP)] Adding local repo $repourl for installing the binaries"
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
        echo "deb file://$repourl ./" > $repofile
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
    echo "[$(util_getHostIP)] Downloading binaries for version [$searchkey]"
    if [ "$nodeos" = "centos" ]; then
        pushd $dlddir > /dev/null 2>&1
        wget -r -np -nH -nd --cut-dirs=1 --accept "*${searchkey}*.rpm" ${repourl} > /dev/null 2>&1
        popd > /dev/null 2>&1
        createrepo $dlddir > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        pushd $dlddir > /dev/null 2>&1
        wget -r -np -nH -nd --cut-dirs=1 --accept "*${searchkey}*.deb" ${repourl} > /dev/null 2>&1
        dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz > /dev/null 2>&1
        popd > /dev/null 2>&1
    fi
}

function maprutil_setupLocalRepo(){
    local repourl=$(maprutil_getRepoURL)
    maprutil_disableAllRepo
    maprutil_downloadBinaries "$RUNTEMPDIR/maprbuilds/$GLB_BUILD_VERSION" "$repourl" "$GLB_BUILD_VERSION"
    maprutil_addLocalRepo "$RUNTEMPDIR/maprbuilds/$GLB_BUILD_VERSION"
}

# @param host node
# @param ycsb/tablecreate
function maprutil_runCommandsOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    local node=$1
    
     # build full script for node
    local scriptpath="$RUNTEMPDIR/cmdonnode_${node: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local client=$(maprutil_isClientNode "$2" "$hostnode")
    local hostip=$(util_getHostIP)
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    maprutil_addGlobalVars "$scriptpath"
    
    echo "maprutil_runCommands \"$2\"" >> $scriptpath
   
    if [ "$hostip" != "$node" ]; then
        ssh_executeScriptasRoot "$node" "$scriptpath"
    else
        maprutil_runCommands "$2"
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
            echo "Failed to run command [ $1 ]"
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
            disktest)
                maprutil_runDiskTest
            ;;
            *)
            echo "Nothing to do!!"
            ;;
        esac
    done
}

function maprutil_createYCSBVolume () {
    echo " *************** Creating YCSB Volume **************** "
    maprutil_runMapRCmd "maprcli volume create -name tables -path /tables -replication 3 -topology /data"
    maprutil_runMapRCmd "hadoop mfs -setcompression off /tables"
}

function maprutil_createTableWithCompression(){
    echo " *************** Creating UserTable (/tables/usertable) with lz4 compression **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable" 
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname family -compression lz4 -maxversions 1"
}

function maprutil_createTableWithCompressionOff(){
    echo " *************** Creating UserTable (/tables/usertable) with compression off **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable"
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname family -compression off -maxversions 1"
}

function maprutil_createJSONTable(){
    echo " *************** Creating JSON UserTable (/tables/usertable) with compression off **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable -tabletype json "
}

function maprutil_addCFtoJSONTable(){
    echo " *************** Creating JSON UserTable (/tables/usertable) with compression off **************** "
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname cfother -jsonpath field0 -compression off -inmemory true"
}

function maprutil_checkDiskErrors(){
    echo " [$(util_getHostIP)] Checking for disk errors "
    util_grepFiles "/opt/mapr/logs/" "mfs.log*" "DHL" "lun.cc"
}

function maprutil_runDiskTest(){
    local maprdisks=$(util_getRawDisks)
    if [ -z "$maprdisks" ]; then
        return
    fi
    echo
    echo "[$(util_getHostIP)] Running disk tests [$maprdisks]"
    local disktestdir="$RUNTEMPDIR/disktest"
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

    local cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $4,$2}')
    local tabletContainers=$(maprcli table region list -path $filepath -json | grep -v 'secondary' | grep -A10 $hostnode | grep fid | cut -d":" -f2 | cut -d"." -f1 | tr -d '"')
    if [ -z "$tabletContainers" ]; then
        return
    fi
    local storagePools=$(/opt/mapr/server/mrconfig sp list | grep name | cut -d":" -f2 | awk '{print $2}' | tr -d ',' | sort)
    local numTablets=$(echo "$tabletContainers" | wc -l)
    local numContainers=$(echo "$tabletContainers" | sort | uniq | wc -l)
    echo "$(util_getHostIP) : [# of tablets: $numTablets], [# of containers: $numContainers]"

    for sp in $storagePools; do
        local spcntrs=$(echo "$cntrlist" | grep $sp | awk '{print $2}')
        local cnt=$(echo "$tabletContainers" |  grep -Fw "${spcntrs}" | wc -l)
        echo -e "\t$sp : $cnt Tablets"
    done
}

function maprutil_applyLicense(){
    wget http://stage.mapr.com/license/LatestDemoLicense-M7.txt --user=maprqa --password=maprqa -O /tmp/LatestDemoLicense-M7.txt > /dev/null 2>&1
    local buildid=$(maprutil_getBuildID)
    local i=0
    local jobs=1
    while [ "${jobs}" -ne "0" ]; do
        echo "[$(util_getHostIP)] Waiting for CLDB to come up before applying license.... sleeping 30s"
        sleep 30
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
    util_buildSingleScript "$lib_dir" "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    if [ -n "$(maprutil_isClientNode $rolefile $node)" ]; then
        return
    fi
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    
    echo "maprutil_restartWarden \"$stopstart\"" >> $scriptpath
   
    ssh_executeScriptasRoot "$node" "$scriptpath"
    
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
        echo "{WARNING} warden init scripts not configured on nodes"
        execcmd="/opt/mapr/initscripts/mapr-warden"
    else
        echo "{ERROR} No mapr-warden on node"
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
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper restart"
    elif [[ "$stopstart" = "stop" ]]; then
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper stop"
    elif [[ "$stopstart" = "start" ]]; then
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper start"
    fi
}

function maprutil_removemMapRPackages(){
   
    util_removeBinaries "mapr-"
}

# @param PID 
function maprutil_addToPIDList(){
    if [ -z "$1" ]; then
        return
    fi
    if [ -z "$GLB_BG_PIDS" ]; then
        GLB_BG_PIDS=$1
    else
        GLB_BG_PIDS=$GLB_BG_PIDS" "$1
    fi
}

# @param timestamp
function maprutil_zipDirectory(){
    local timestamp=$1
    local tmpdir="/tmp/maprlogs/$(hostname -f)/"
    local logdir="/opt/mapr/logs"
    local buildid=$(cat /opt/mapr/MapRBuildVersion)
    local tarfile="maprlogs_$(hostname -f)_$buildid_$timestamp.tar.bz2"

    mkdir -p $tmpdir > /dev/null 2>&1
    
    cd $tmpdir && tar -cjf $tarfile -C $logdir . > /dev/null 2>&1
}

# @param host ip
# @param timestamp
function maprutil_zipLogsDirectoryOnNode(){
    if [ -z "$1" ]; then
        echo "Node not specified."
        return
    fi

    local node=$1
    local timestamp=$2
    
    local scriptpath="$RUNTEMPDIR/zipdironnode_${node: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath

    echo "maprutil_zipDirectory \"$timestamp\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"
}


# @param host ip
# @param local directory to copy the zip file
function maprutil_copyZippedLogsFromNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo "Incorrect or null arguments. Ignoring copy of the files"
        return
    fi

    local node=$1
    local timestamp=$2
    local copyto=$3
    mkdir -p $copyto > /dev/null 2>&1
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local filetocopy="/tmp/maprlogs/$host/*$timestamp.tar.bz2"
    
    ssh_copyFromCommandinBG "root" "$node" "$filetocopy" "$copyto"
}

### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
