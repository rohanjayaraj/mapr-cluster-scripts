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
        master=$(ssh_executeCommandWithTimeout "root" "$1" "maprcli node cldbmaster | grep HostName | cut -d' ' -f4" "10")
    else
        master=$(timeout 10 maprcli node cldbmaster | grep HostName | cut -d' ' -f4)
    fi
    if [ ! -z "$master" ]; then
            if [[ "$master" =~ ^Killed.* ]] || [[ "$master" =~ ^Terminate.* ]]; then
                echo
            else
                echo $master
            fi
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
function maprutil_getESNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local esnodes=$(grep elastic $1 | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$esnodes" ]; then
            echo $esnodes
    fi
}

## @param path to config
function maprutil_getOTSDBNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local otnodes=$(grep opentsdb $1 | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
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

function maprutil_coresdirs(){
    local dirlist=()
    dirlist+=("/opt/cores/guts*")
    dirlist+=("/opt/cores/mfs*")
    dirlist+=("/opt/cores/java.core.*")
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
    dirlist+=("/tmp/disklist*")
    dirlist+=("/tmp/configurenode_*")
    dirlist+=("/tmp/postconfigurenode_*")
    dirlist+=("/tmp/cmdonnode_*")
    dirlist+=("/tmp/defdisks*")

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
    local scriptpath="/tmp/isinstalled_${hostnode: -3}.sh"
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

function maprutil_unmountNFS(){
    local nfslist=$(mount | grep nfs | grep mapr | cut -d' ' -f3)
    for i in $nfslist
    do
        umount -l $i
    done
}

function maprutil_uninstallNode2(){
    
    # Unmount NFS
    maprutil_unmountNFS

    # Stop warden
    service mapr-warden stop

    # Stop zookeeper
    service mapr-zookeeper stop  2>/dev/null

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
    util_kill "dstat"
    util_kill "iostat"
    util_kill "initaudit.sh"
    util_kill "java" "jenkins" "elasticsearch"
}

# @param host ip
function maprutil_uninstallNode(){
    if [ -z "$1" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="/tmp/uninstallnode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "maprutil_uninstallNode2" >> $scriptpath

    local bins=
    local hostip=$(util_getHostIP)
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
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
    local scriptpath="/tmp/installbinnode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "util_installprereq" >> $scriptpath
    echo "util_installBinaries \""$2"\"" >> $scriptpath

    local hostip=$(util_getHostIP)
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
    local failcnt=2;
    local iter=0;
    while [ "$failcnt" -gt 0 ] && [ "$iter" -lt 5 ]; do
        failcnt=0;
        maprcli  config save -values {multimfs.numinstances.pernode:${nummfs}}
        let failcnt=$failcnt+`echo $?`
        maprcli  config save -values {multimfs.numsps.perinstance:1}
        let failcnt=$failcnt+`echo $?`
        sleep 30;
        let iter=$iter+1;
    done
}

function maprutil_configurePontis(){
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
}

function maprutil_configureCLDBTopology(){
    
    local datatopo=$(maprcli node list -json | grep racktopo | grep "/data/" | wc -l)
    local numdnodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | wc -l) 
    let numdnodes=numdnodes-1

    if [ "$datatopo" -eq "$numdnodes" ]; then
        return
    fi
    local clustersize=$(maprcli node list -json | grep 'id'| wc -l)
    if [ "$clustersize" -gt 4 ]; then
        ## Move all nodes under /data topology
        local datanodes=`maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | tr "\n" ","`
        maprcli node move -serverids "$datanodes" -topology /data 2>/dev/null
        sleep 5;
        ### Moving CLDB Node to CLDB topology
        local cldbnode=`maprcli node cldbmaster | grep ServerID | awk {'print $2'}`
        maprcli node move -serverids "$cldbnode" -topology /cldb 2>/dev/null
        sleep 5;
        ### Moving CLDB Volume as well
        maprcli volume move -name mapr.cldb.internal -topology /cldb 2>/dev/null
        sleep 5;
    fi
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
    /opt/mapr/bin/guts time:all flush:line cache:all db:all rpc:all log:all dbrepl:all > /opt/mapr/logs/guts.log 2>&1 &
    dstat -tcpldrngims --ipc > /opt/mapr/logs/dstat.log 2>&1 &
    iostat -dmxt 1 > /opt/mapr/logs/iostat.log 2>&1 &
}

function maprutil_configureNode2(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    local diskfile="/tmp/disklist"
    local hostip=$(util_getHostIP)
    local cldbnodes=$(util_getCommaSeparated "$1")
    local zknodes=$(util_getCommaSeparated "$2")
    maprutil_buildDiskList "$diskfile"

    if [ "$ISCLIENT" -eq 1 ]; then
        echo "/opt/mapr/server/configure.sh -c -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3"
        /opt/mapr/server/configure.sh -c -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3
        return 
    else
        echo "/opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3"
        /opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3
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
        local numdiskspermfs=`echo $numdisks/$multimfs|bc`

        /opt/mapr/server/disksetup -FW $numdiskspermfs $diskfile
    elif [[ -n "$numsps" ]]; then
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

    # Perform series of custom configuration based on selected options
    maprutil_customConfigure

    # Start zookeeper
    service mapr-zookeeper start 2>/dev/null
    
    service mapr-warden restart

    local cldbnode=$(util_getFirstElement "$1")
    if [ "$hostip" = "$cldbnode" ]; then
        maprutil_applyLicense
        if [ -n "$multimfs" ] && [ "$multimfs" -gt 1 ]; then
            maprutil_configureMultiMFS "$multimfs"
        fi
        local cldbtopo=$GLB_CLDB_TOPO
        if [ -n "$cldbtopo" ]; then
            sleep 30
            maprutil_configureCLDBTopology
        fi
    fi

    maprutil_startTraces
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
    local scriptpath="/tmp/configurenode_${hostnode: -3}.sh"
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
    
    echo "maprutil_configureNode2 \""$cldbnodes"\" \""$zknodes"\" \""$3"\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$4" ]; then
        wait
    fi
}

function maprutil_postConfigureNode2(){
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
    local ret=$($cmd)

    service mapr-warden restart
}

# @param host ip
# @param config file path
# @param cluster name
# @param don't wait
function maprutil_postConfigureNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
     # build full script for node
    local hostnode=$1
    local scriptpath="/tmp/postconfigurenode_${hostnode: -3}.sh"
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
    
    echo "maprutil_postConfigureNode2 \""$esnodes"\" \""$otnodes"\"" >> $scriptpath
   
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
        ssh_copyCommandasRoot "$node" "$2" "/etc/apt/sources.list.d/"
    fi
}

# @param host node
# @param ycsb/tablecreate
function maprutil_runCommandsOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    local node=$1
    
     # build full script for node
    local scriptpath="/tmp/cmdonnode_${node: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local hostip=$(util_getHostIP)
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    
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
                maprutil_configureCLDBTopology
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

function maprutil_applyLicense(){
    wget http://stage.mapr.com/license/LatestDemoLicense-M7.txt --user=maprqa --password=maprqa -O /tmp/LatestDemoLicense-M7.txt > /dev/null 2>&1
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
    
    local scriptpath="/tmp/zipdironnode_${node: -3}.sh"
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

### 
