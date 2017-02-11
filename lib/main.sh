#!/bin/bash


################  
#
#   Main Executor Script
#
################

#set -x

basedir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
#echo "BASEDIR : $basedir"
isLibDir=${basedir:(-4)}
#echo "isLibDir : $isLibDir"
if [ "$isLibDir" = "/lib" ]; then
	basedirlen=${#basedir}
	len=`expr $basedirlen - 4`
	basedir=${basedir:0:$len}
fi
#echo "BASEDIR : $basedir"

libdir=$basedir"/lib"
repodir=$basedir"/repo"
rolesdir=$basedir"/roles"

# source all binaries
for srcfile in "$libdir"/*.sh
do
  if [[ $srcfile == *"main.sh" ]]; then
  	continue
  fi
  #echo "Souring : $srcfile"
  source $srcfile
done


# Get the roles files
rolefile=$1
if [ -z "$(util_fileExists $rolefile)" ]; then
	rolefile=$rolesdir"/"$1
	if [ -z "$(util_fileExists $rolefile)" ]; then
		rolefile=$rolesdir"/mapr_roles."$1
		if [ -z "$(util_fileExists $rolefile)" ]; then
			if  [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]]; then
				dummyrole=$rolesdir"/mapr_roles.temp"
				echo "$1,dummy" > $dummyrole
				rolefile=$dummyrole
			else
				rolefile="/tmp/$1"
				maprutil_readClusterRoles "$rolefile"
			fi
		fi
	fi
fi

# Handle rolefile regex here
if [ -n "$(cat $rolefile | grep '^[^#;]' | grep '\[')" ]; then
	rolefile=$(util_expandNodeList "$rolefile")
fi

# Fetch the nodes to be configured
log_msghead "Using cluster configuration file : $rolefile "
nodes=$(maprutil_getNodesFromRole $rolefile)

if [ -z "$nodes" ]; then
	log_error "Unable to get the list of nodes. Scooting!"
	exit 1
fi

# Check if current user is root
if [ "$(util_isUserRoot)" = "false" ]; then
	log_critical "Please run the script as root user. Scooting!"
	exit 1
#else
#	echo "Executing as user 'root'"
fi

# Check if ssh key generated on the executor machine
keyexists=$(util_fileExists "/root/.ssh/id_rsa")
if [ -z "$keyexists" ]; then
	log_info "SSH key is missing. Creating..."
	ssh_createkey "/root/.ssh"
#else
#	echo "SSH key exists"
fi

# Install sshpass if not already there
ssh_installsshpass

# Check if SSH is configured
#echo "Checking Key-based authentication to all nodes listed... "
if [ -n $(ssh_checkSSHonNodes "$nodes") ]; then
	for node in ${nodes[@]}
	do
		isEnabled=$(ssh_check "root" "$node")
		if [ "$isEnabled" != "enabled" ]; then
			log_info "Configuring key-based authentication for the node $node (enter password once if required)"
			ssh_copyPublicKey "root" "$node"
		fi
	done
fi

trap main_stopall SIGHUP SIGINT SIGTERM SIGKILL

# Global Variables : All need to start with 'GLB_' as they are replayed back to other cluster nodes during setup
GLB_CLUSTER_NAME="archerx"
GLB_CLUSTER_SIZE=$(cat $rolefile |  grep "^[^#;]" | grep -v 'mapr-client\|mapr-loopbacknfs' | wc -l)
GLB_TRACE_ON=
GLB_MULTI_MFS=
GLB_NUM_SP=
GLB_TRIM_SSD=
GLB_TABLE_NS=
GLB_CLDB_TOPO=
GLB_PONTIS=
GLB_BG_PIDS=
GLB_MAX_DISKS=
GLB_MAPR_VERSION=
GLB_BUILD_VERSION=
GLB_MAPR_PATCH=
GLB_PATCH_VERSION=
GLB_PATCH_REPOFILE=
GLB_PUT_BUFFER=
GLB_TABLET_DIST=
GLB_SECURE_CLUSTER=
GLB_SYSINFO_OPTION=
GLB_GREP_MAPRLOGS=
GLB_LOG_VERBOSE=
GLB_EXIT_ERRCODE=

### START_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
############################### ALL functions to be defined below this ###############################

function main_install(){
	#set -x
	# Warn user 
	log_msghead "[$(util_getCurDate)] Installing MapR on the following N-O-D-E-S : "
	echo
	local i=1
	for node in ${nodes[@]}
	do
		log_msg "Node$i : $node"
		let i=i+1
	done

	if [[ "$doSilent" -eq 0 ]]; then
		read -p "Press 'y' to confirm... " -n 1 -r
	    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	    	echo
	    	log_msg "Abandoning install! "
	        return 1
	    fi
	fi
    echo
    log_info "Checking if MapR is already installed on the nodes..."
    local islist=$(maprutil_isMapRInstalledOnNodes "$nodes")
	if [ -n "$islist" ]; then
		log_error "MapR is already installed on the node(s) [ $islist] or some stale binaries are still present. Scooting!"
		exit 255
	fi

	# Read properties
	local clustername=$GLB_CLUSTER_NAME
	local maprrepo=$(main_getRepoFile)

	# Install required binaries on other nodes
	local buildexists=
	for node in ${nodes[@]}
	do
		# Copy mapr.repo if it doen't exist
		maprutil_copyRepoFile "$node" "$maprrepo" && [ -z "$GLB_MAPR_VERSION" ] && GLB_MAPR_VERSION=$(maprutil_getMapRVersionFromRepo $node)
		if [ -n "$GLB_BUILD_VERSION" ] && [ -z "$buildexists" ]; then
			main_isValidBuildVersion
			buildexists=$(maprutil_checkBuildExists "$node" "$GLB_BUILD_VERSION")
			if [ -z "$buildexists" ]; then
				log_error "Specified build version [$GLB_BUILD_VERSION] doesn't exist in the configured repositories. Please check the repo file"
				exit 1
			fi
		fi
		local nodebins=$(maprutil_getCoreNodeBinaries "$rolefile" "$node")
		maprutil_installBinariesOnNode "$node" "$nodebins" "bg"
	done
	maprutil_wait

	# Configure all nodes
	for node in ${nodes[@]}
	do
		log_info "****** Running configure on node -> $node ****** "
		maprutil_configureNode "$node" "$rolefile" "$clustername" "bg"
	done
	maprutil_wait

	# Configure ES & OpenTSDB nodes
	if [ -n "$(maprutil_getESNodes $rolefile)" ] || [ -n "$(maprutil_getOTSDBNodes $rolefile)" ]; then 
		log_info "****** Installing and configuring Spyglass ****** " 
		for node in ${nodes[@]}
		do
			local nodebins=$(maprutil_getNodeBinaries "$rolefile" "$node")
			local nodecorebins=$(maprutil_getCoreNodeBinaries "$rolefile" "$node")
			if [ "$(echo $nodebins | wc -w)" -gt "$(echo $nodecorebins | wc -w)" ]; then
				maprutil_installBinariesOnNode "$node" "$nodebins" "bg"
			fi
		done
		maprutil_wait

		for node in ${nodes[@]}
		do
			maprutil_postConfigureOnNode "$node" "$rolefile" "bg"
		done
		maprutil_wait
	fi

	# Configure all nodes
	for node in ${nodes[@]}
	do
		maprutil_restartWardenOnNode "$node" "$rolefile"
	done
	maprutil_wait

	# Perform custom executions

	#set +x
	log_msghead "[$(util_getCurDate)] Install is complete! [ RunTime - $(main_timetaken) ]"
}

function main_reconfigure(){
	log_msghead "[$(util_getCurDate)] Reconfiguring MapR on the following N-O-D-E-S : "
	echo
	local i=1
	for node in ${nodes[@]}
	do
		log_msg "Node$i : $node"
		let i=i+1
	done

	if [[ "$doSilent" -eq 0 ]]; then
		read -p "Press 'y' to confirm... " -n 1 -r
	    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	    	log_msg "Reconfigure C-A-N-C-E-L-L-E-D! "
	        return 1
	    fi
	fi
    echo
    log_info "Checking if MapR is installed on the nodes..."
	# Check if MapR is installed on all nodes
	local islist=$(maprutil_isMapRInstalledOnNodes "$nodes")
	local notlist=
	for node in ${nodes[@]}
	do
		local isInstalled=$(echo "$islist" | grep $node)
		if [ -z "$isInstalled" ]; then
			notlist=$notlist"$node"" "
		else
			#??? Get install version
			[ -z "$GLB_MAPR_VERSION" ] && GLB_MAPR_VERSION=$(maprutil_getMapRVersionFromRepo $node)
			log_info "MapR is installed on node '$node' [ $(maprutil_getMapRVersionOnNode $node) ]"
		fi
	done

	if [ -n "$notlist" ]; then
		log_error "MapR not installed on the node(s) [ $notlist]. Trying install on the nodes first. Scooting!"
		exit 1
	fi

	log_info "Erasing files/directories from previous configurations"
	for node in ${nodes[@]}
	do
		maprutil_cleanPrevClusterConfigOnNode "$node" "$rolefile"
	done
	maprutil_wait

	# Read properties
	local clustername=$GLB_CLUSTER_NAME
	
	# Configure all nodes
	for node in ${nodes[@]}
	do
		log_info "****** Running configure on node -> $node ****** "
		maprutil_configureNode "$node" "$rolefile" "$clustername" "bg"
	done
	maprutil_wait

	# Restart all nodes
	for node in ${nodes[@]}
	do
		maprutil_restartWardenOnNode "$node" "$rolefile"
	done
	maprutil_wait

	log_msghead "[$(util_getCurDate)] Reconfiguration is complete! [ RunTime - $(main_timetaken) ]"
}

function main_upgrade(){
	log_msghead "[$(util_getCurDate)] Upgrading MapR on the following N-O-D-E-S : "
	echo
	local i=1
	for node in ${nodes[@]}
	do
		log_info "Node$i : $node"
		let i=i+1
	done

	if [[ "$doSilent" -eq 0 ]]; then
		read -p "Press 'y' to confirm... " -n 1 -r
	    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	    	log_msg "Upgrade C-A-N-C-E-L-L-E-D! "
	        return 1
	    fi
	fi
    echo
    log_info "Checking if MapR is installed on the nodes..."
	# Check if MapR is installed on all nodes
	local islist=$(maprutil_isMapRInstalledOnNodes "$nodes")
	local notlist=
	for node in ${nodes[@]}
	do
		local isInstalled=$(echo "$islist" | grep $node)
		if [ -z "$isInstalled" ]; then
			notlist=$notlist"$node"" "
		else
			log_info "MapR is installed on node '$node' [ $(maprutil_getMapRVersionOnNode $node) ]"
		fi
	done

	if [ -n "$notlist" ]; then
		log_error "MapR not installed on the node(s) [ $notlist]. Trying install on the nodes first. Scooting!"
		exit 1
	fi

	local cldbnode=
	local nocldblist=
	# Check if each node points to the same CLDB master and the master is part of the cluster
	for node in ${nodes[@]}
	do
		local cldbhost=$(maprutil_getCLDBMasterNode "$node")
		if [ -z "$cldbhost" ]; then
			log_warn " Unable to identifiy CLDB master on node [$node]"
			nocldblist=$nocldblist$node" "
		else
			local cldbip=$cldbhost
			if [ "$(util_validip2 $cldbhost)" = "invalid" ]; then
				cldbip=$(util_getIPfromHostName "$cldbhost")
			fi
			local isone="false"
			for nd in ${nodes[@]}
			do
				if [ "$nd" = "$cldbip" ]; then
					isone="true"
					break
				fi
			done
			if [ "$isone" = "false" ]; then
				log_error " Node [$node] is not part of the same cluster. Scooting"
			else
				cldbnode="$cldbip"
			fi
		fi
	done

	if [ -n "$nocldblist" ]; then
		log_error "CLDB not found on nodes [$nocldblist]. May be uninstalling another cluster's nodes. Check the nodes specified."
    	exit 1
	else
		log_info "CLDB Master : $cldbnode"
	fi

	local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
    local zknodes=$(maprutil_getZKNodes "$rolefile")
    local buildexists=
    local maprrepo=$(main_getRepoFile)

    # First stop warden on all nodes
	for node in ${nodes[@]}
	do
		# Copy mapr.repo if it doen't exist
		maprutil_copyRepoFile "$node" "$maprrepo" && [ -z "$GLB_MAPR_VERSION" ] && GLB_MAPR_VERSION=$(maprutil_getMapRVersionFromRepo $node)
		if [ -z "$buildexists" ] && [ -z "$(maprutil_checkNewBuildExists $node)" ]; then
			log_error "No newer build exists. Please check the repo file [$maprrepo] for configured repositories"
			exit 1
		fi
		if [ -n "$GLB_BUILD_VERSION" ] && [ -z "$buildexists" ]; then
			main_isValidBuildVersion
			buildexists=$(maprutil_checkBuildExists "$node" "$GLB_BUILD_VERSION")
			if [ -z "$buildexists" ]; then
				log_error "Specified build version [$GLB_BUILD_VERSION] doesn't exist in the configured repositories. Please check the repo file"
				exit 1
			else
				log_info "Stopping warden on all nodes..."
			fi
		fi
		# Stop warden on all nodes
		maprutil_restartWardenOnNode "$node" "$rolefile" "stop" 
	done

	log_info "Stopping zookeeper..."
	# Stop ZK on ZK nodes
	for node in ${zknodes[@]}
	do
		maprutil_restartZKOnNode "$node" "$rolefile" "stop"
	done
	maprutil_wait
	
	# Kill all mapred jos & yarn applications

	
	# Upgrade rest of the nodes
	log_info "Upgrading MaPR on all nodes..."
	for node in ${nodes[@]}
	do	
		maprutil_upgradeNode "$node" "bg"
	done
	maprutil_wait

	sleep 60 && maprutil_postUpgrade "$cldbnode"
	
	for node in ${nodes[@]}
	do
		maprutil_restartWardenOnNode "$node" "$rolefile"
	done
	maprutil_wait

	log_msghead "[$(util_getCurDate)] Upgrade is complete! [ RunTime - $(main_timetaken) ]"
}

function main_uninstall(){

	# Warn user 
	log_msghead "[$(util_getCurDate)] Uninstalling MapR on the following N-O-D-E-S : "
	echo
	local i=1
	for node in ${nodes[@]}
	do
		log_msg "Node$i : $node"
		let i=i+1
	done

	if [[ "$doSilent" -eq 0 ]]; then
		read -p "Press 'y' to confirm... " -n 1 -r
	    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	    	log_msg "Uninstall C-A-N-C-E-L-L-E-D! "
	        return 1
	    fi
	fi
    echo && main_isMapRInstalled

	local cldbnode=
	local nocldblist=
	# Check if each node points to the same CLDB master and the master is part of the cluster
	for node in ${nodes[@]}
	do
		local cldbhost=$(maprutil_getCLDBMasterNode "$node")
		if [ -z "$cldbhost" ]; then
			log_warn " Unable to identifiy CLDB master on node [$node]"
			nocldblist=$nocldblist$node" "
		else
			local cldbip=$cldbhost
			if [ "$(util_validip2 $cldbhost)" = "invalid" ]; then
				cldbip=$(util_getIPfromHostName "$cldbhost")
			fi
			local isone="false"
			for nd in ${nodes[@]}
			do
				if [ "$nd" = "$cldbip" ]; then
					isone="true"
					break
				fi
			done
			if [ "$isone" = "false" ]; then
				if [ "$doForce" -eq 0 ]; then
					log_error " Node [$node] is not part of the same cluster. Scooting"
					exit 1
				else
					log_warn " Node [$node] is not part of the same cluster"
				fi
			else
				cldbnode="$cldbip"
			fi
		fi
	done

	if [ -n "$nocldblist" ]; then
		log_warn "CLDB not found on nodes [$nocldblist]. May be uninstalling another cluster's nodes."
		if [[ "$doForce" -eq 0 ]]; then
			read -p "Press 'y' to confirm... " -n 1 -r
		    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		    	log_msg "Over & Out!"
		    	exit 1
		    fi
		else
			log_msg "Continuing uninstallation..."
		fi
	else
		log_info "CLDB Master : $cldbnode"
	fi


	if [ -n "$doBackup" ]; then
		main_backuplogs
	fi

	# Start MapR Unistall for each node
	local hostip=$(util_getHostIP)
	local dohost="false"
	for node in ${nodes[@]}
	do	
    	#if [ "$hostip" != "$node" ]; then
			maprutil_uninstallNode "$node"
		#else
		#	dohost="true"
		#fi
	done
	
	# Run uninstall on the host node at the end
	#if [ "$dohost" = "true" ]; then
	#	maprutil_uninstallNode "$hostip"
	#fi

	maprutil_wait

	log_msghead "[$(util_getCurDate)] Uninstall is complete! [ RunTime - $(main_timetaken) ]"
}

function main_isMapRInstalled(){
	log_msg "Checking if MapR is installed on the nodes..."
	# Check if MapR is installed on all nodes
	local islist=$(maprutil_isMapRInstalledOnNodes "$nodes")
	local notlist=
	for node in ${nodes[@]}
	do
		local isInstalled=$(echo "$islist" | grep $node)
		if [ -z "$isInstalled" ]; then
			notlist=$notlist"$node"" "
		else
			log_info "MapR is installed on node '$node' [ $(maprutil_getMapRVersionOnNode $node) ]"
		fi
	done

	if [ -n "$notlist" ]; then
		if [ "$doForce" -eq 0 ]; then
			log_error "MapR not installed on the node(s) [ $notlist]. Scooting!"
			exit 1
		else
			log_warn "MapR not installed on the node(s) [ $notlist]."
			[ "$(echo $nodes | wc -w)" -eq "$(echo $notlist | wc -w)" ] && log_msg "No MapR installed on the cluster. Scooting!" && exit 1
		fi
	fi
}

function main_backuplogs(){
	log_msghead "[$(util_getCurDate)] Backing up MapR log directory on all nodes to $doBackup"
	
	main_isMapRInstalled

	local timestamp=$(date +%Y-%m-%d-%H-%M)
	for node in ${nodes[@]}
	do	
    	maprutil_zipLogsDirectoryOnNode "$node" "$timestamp"
	done
	maprutil_wait
	for node in ${nodes[@]}
	do	
    	maprutil_copyZippedLogsFromNode "$node" "$timestamp" "$doBackup"
	done
	wait

	local scriptfile="$doBackup/extract.sh"
	echo "echo \"extracting bzip2\"" > $scriptfile
	echo "for i in \$(ls *.bz2);do bzip2 -dk \$i;done " >> $scriptfile
	echo "echo \"extracting tar\"" >> $scriptfile
	echo "for i in \$(ls *.tar);do DIR=\$(echo \$i| sed 's/.tar//g' | tr '.' '_' | cut -d'_' -f2); echo \$DIR;mkdir -p \$DIR;tar -xf \$i -C \$(pwd)/\$DIR && rm -f \${i}; done" >> $scriptfile
	chmod +x $scriptfile

	log_msghead "[$(util_getCurDate)] Backup complete! [ RunTime - $(main_timetaken) ]"
}

function main_runCommandExec(){
	if [ -z "$1" ]; then
        return
    fi
    local allnodes=
    local cmds=$1

    if [[ "$GLB_TRACE_ON" -eq "1" ]]; then
    	allnodes=1
    fi

    local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	local isInstalled=$(maprutil_isMapRInstalledOnNode "$cldbnode")
	if [ "$isInstalled" = "false" ]; then
		log_error "MapR is not installed on the cluster"
		return
	fi
	
	if [ -z "$allnodes" ]; then
		maprutil_runCommandsOnNode "$cldbnode" "$cmds"
	else
		for node in ${nodes[@]}
		do	
	    	maprutil_runCommandsOnNode "$node" "$cmds"
		done
	fi
}

function main_runLogDoctor(){
	[ -z "$doLogAnalyze" ] && return
	local nodelist=
	for node in ${nodes[@]}
	do	
		if [ -n "$(maprutil_isClientNode $rolefile $node)" ]; then
			continue
		fi
		nodelist=$nodelist"$node "
	done

	for i in $doLogAnalyze 
	do
		echo
	    case $i in
	    	diskerror)
				maprutil_runCommandsOnNodesInParallel "$nodes" "diskcheck"
        	;;
        	disktest)
				log_msghead "[$(util_getCurDate)] Running disk tests on all nodes"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "disktest"
        	;;
        	mfsgrep)
				log_msghead "[$(util_getCurDate)] Grepping MFS logs on all nodes"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "mfsgrep"
        	;;
        	clsspec)
				log_msghead "[$(util_getCurDate)] Printing cluster specifications"
				maprutil_getClusterSpec "$nodes"
        	;;
        	sysinfo)
				log_msghead "[$(util_getCurDate)] Running system info on all nodes"
				maprutil_runCommandsOnNodesInParallel "$nodes" "sysinfo"
        	;;
        	greplogs)
				log_msghead "[$(util_getCurDate)] Grepping MapR logs on all nodes for key [ $GLB_GREP_MAPRLOGS ]"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "grepmapr"
        	;;
        	tabletdist)
				log_msghead "[$(util_getCurDate)] Checking tablet distribution for table '$GLB_TABLET_DIST'"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "tabletdist"
        	;;
        esac
	done
}

function main_isValidBuildVersion(){
    if [ -z "$GLB_BUILD_VERSION" ]; then
        return
    fi
    local vlen=${#GLB_BUILD_VERSION}
    if [ "$(util_isNumber $GLB_BUILD_VERSION)" = "true" ]; then
    	 if [ "$vlen" -lt 5 ]; then
    	 	log_error "Specify a longer build/changelist id (ex: 38395)"
            exit 1
    	 fi
    elif [ "$vlen" -lt 11 ]; then
        log_error "Specify a longer version string (ex: 5.2.0.38395)"
        exit 1
    fi
}

function main_stopall() {
	local me=$(basename $BASH_SOURCE)
    log_warn "$me script interrupted!!! Stopping... "
    for i in "${GLB_BG_PIDS[@]}"
    do
        log_info "[$me] kill -9 $i"
        kill -9 ${i} 2>/dev/null
    done
}

function main_getRepoFile(){
	local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	local maprrepo=
	local repofile=

	local nodeos=$(getOSFromNode $cldbnode)
	if [ "$nodeos" = "centos" ]; then
       maprrepo=$repodir"/mapr.repo"
	   repofile="$repodir/mapr2.repo"
    elif [ "$nodeos" = "ubuntu" ]; then
       maprrepo=$repodir"/mapr.list"
	   repofile="$repodir/mapr2.list"
    fi

	if [ -z "$useRepoURL" ]; then
		echo "$maprrepo"
		return
	fi
	local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	maprutil_buildRepoFile "$repofile" "$useRepoURL" "$cldbnode"
	echo "$repofile"
}

function main_usage () {
	local me=$(basename $BASH_SOURCE)
	echo 
	log_msghead "Usage : "
    log_msg "./$me CONFIG_NAME [Options]"
    log_msg " Options : "
    log_msg "\t -h --help"
    log_msg "\t\t - Print this"
    echo 
    log_msg "\t install" 
    log_msg "\t\t - Install cluster"
    log_msg "\t uninstall " 
    log_msg "\t\t - Uninstall cluster"
    echo 
    
}

function main_timetaken(){
	local ENDTS=$(date +%s);
	echo $((ENDTS-STARTTS)) | awk '{print int($1/60)"min "int($1%60)"sec"}'
}

function main_addSpyglass(){
	local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	local newrolefile=$(mktemp -p $RUNTEMPDIR)
	for node in ${nodes[@]}
	do	
    	if [ "$node" = "$cldbnode" ]; then
    		sed -i 's/$/,mapr-opentsdb,mapr-grafana,mapr-elasticsearch,mapr-kibana,mapr-collectd,mapr-fluentd/' $newrolefile
    	else
    		sed -i 's/$/,mapr-collectd,mapr-fluentd"/' $newrolefile
    	fi
	done
	rolefile=$newrolefile
}

### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###

STARTTS=$(date +%s);
RUNTEMPDIR="/tmp/maprsetup/maprsetup_$(date +%Y-%m-%d-%H-%M-%S-%6N)"
mkdir -p $RUNTEMPDIR 2>/dev/null

doInstall=0
doUninstall=0
doUpgrade=0
doConfigure=0
doCmdExec=
doLogAnalyze=
doPontis=0
doForce=0
doSilent=0
doBackup=
useBuildID=
useRepoURL=

while [ "$2" != "" ]; do
	OPTION=`echo $2 | awk -F= '{print $1}'`
    VALUE=`echo $2 | awk -F= '{print $2}'`
    #echo "OPTION : $OPTION; VALUE : $VALUE"
    case $OPTION in
        h | help)
            main_usage
            exit
        ;;
        -s)
			case $VALUE in
		    	install)
		    		doInstall=1
		    		GLB_CLDB_TOPO=1
		    	;;
		    	uninstall)
		    		doUninstall=1
		    	;;
		    	upgrade)
		    		doUpgrade=1
		    	;;
		    	reconfigure)
		    		doConfigure=1
		    		GLB_CLDB_TOPO=1
		    	;;
		    esac
		    ;;
    	-e)
			for i in ${VALUE}; do
				#echo " extra option : $i"
				if [[ "$i" = "ycsb" ]] || [[ "$i" = "tablecreate" ]] || [[ "$i" = "tablelz4" ]] || [[ "$i" = "jsontable" ]] || [[ "$i" = "cldbtopo" ]] || [[ "$i" = "jsontablecf" ]] || [[ "$i" = "tsdbtopo" ]] || [[ "$i" = "traceon" ]]; then
					if [[ "$i" = "cldbtopo" ]]; then
    					GLB_CLDB_TOPO=1
    				elif [[ "$i" = "traceon" ]]; then
    					GLB_TRACE_ON=1
    				fi
    				if [ -z "$doCmdExec" ]; then
    					doCmdExec=$i
    				else
    					doCmdExec=$doCmdExec" "$i
    				fi
    			elif [[ "$i" = "force" ]]; then
    				doForce=1
    			elif [[ "$i" = "pontis" ]]; then
    				GLB_PONTIS=1
    			elif [[ "$i" = "confirm" ]]; then
    				doSilent=1
    			elif [[ "$i" = "secure" ]]; then
    				GLB_SECURE_CLUSTER=1
    			elif [[ "$i" = "trim" ]]; then
    				GLB_TRIM_SSD=1
    			elif [[ "$i" = "patch" ]]; then
    				GLB_MAPR_PATCH=1
    			elif [[ "$i" = "spy" ]]; then
    				main_addSpyglass
    			fi
    		done
    	;;
    	-l)
			for i in ${VALUE}; do
				if [[ "$i" = "diskerror" ]]; then
	    			doLogAnalyze="$doLogAnalyze diskerror"
	    		elif [[ "$i" = "disktest" ]]; then
	    			doLogAnalyze="$doLogAnalyze disktest"
	    		elif [[ "$i" = "mfsgrep" ]]; then
	    			doLogAnalyze="$doLogAnalyze mfsgrep"
	    		elif [[ "$i" = "clsspec" ]]; then
	    			doLogAnalyze="$doLogAnalyze clsspec"
	    		fi
	    	done
		;;
		-si)
			if [ -n "$VALUE" ]; then
				doLogAnalyze="$doLogAnalyze sysinfo"
				GLB_SYSINFO_OPTION="$VALUE"
			fi
		;;
		-g)
			if [ -n "$VALUE" ]; then
				doLogAnalyze="$doLogAnalyze greplogs"
				GLB_GREP_MAPRLOGS="$VALUE"
			fi
		;;
		-td)
			if [ -n "$VALUE" ]; then
				doLogAnalyze="$doLogAnalyze tabletdist"
				GLB_TABLET_DIST=$VALUE
			fi
		;;
		-c)
			if [ -n "$VALUE" ]; then
    			GLB_CLUSTER_NAME=$VALUE
    		fi
    	;;
    	-v)
			if [ -n "$VALUE" ]; then
    			GLB_LOG_VERBOSE=1
    		fi
    	;;
    	-m)
			if [ -n "$VALUE" ]; then
    			GLB_MULTI_MFS=$VALUE
    		fi
    	;;
    	-sp)
			if [ -n "$VALUE" ]; then
    			GLB_NUM_SP=$VALUE
    		fi
    	;;
    	-ns)
			if [ -n "$VALUE" ]; then
    			GLB_TABLE_NS=$VALUE
    		fi
    	;;
    	-d)
			if [ -n "$VALUE" ]; then
    			GLB_MAX_DISKS=$VALUE
    		fi
    	;;
    	-b)
			if [ -n "$VALUE" ]; then
				doBackup=$VALUE
			fi
    	;;
    	-bld)
			if [ -n "$VALUE" ]; then
				GLB_BUILD_VERSION=$VALUE
			fi
    	;;
    	-pb)
			if [ -n "$VALUE" ]; then
				GLB_PUT_BUFFER=$VALUE
			fi
    	;;
    	-repo)
			if [ -n "$VALUE" ]; then
				useRepoURL="$VALUE"
				[ -z "$GLB_PATCH_REPOFILE" ] && GLB_PATCH_REPOFILE="${useRepoURL%?}-patch-EBF"
				[ -z "$(wget $GLB_PATCH_REPOFILE -O- 2>/dev/null)" ] && GLB_PATCH_REPOFILE=
			fi
		;;
		-prepo)
			if [ -n "$VALUE" ]; then
				GLB_PATCH_REPOFILE="$VALUE"
			fi
		;;
		-pid)
 			if [ -n "$VALUE" ]; then
 				GLB_PATCH_VERSION=$VALUE
 				GLB_MAPR_PATCH=1
 			fi
 		;;
 		*)
            log_error "ERROR: unknown option \"$OPTION\""
            main_usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$dummyrole" ]; then 
	if [ "$doInstall" -eq 1 ]; then
		log_msghead " *************** Starting Cluster Installation **************** "
		main_install
	elif [ "$doUninstall" -eq 1 ]; then
		log_msghead " *************** Starting Cluster Uninstallation **************** "
		main_uninstall
	elif [ "$doUpgrade" -eq 1 ]; then
		log_msghead " *************** Starting Cluster Upgrade **************** "
		main_upgrade
	elif [ "$doConfigure" -eq 1 ]; then
		log_msghead " *************** Starting Cluster Reset & configuration **************** "
		main_reconfigure
	fi

	[ -n "$GLB_EXIT_ERRCODE" ] && log_critical "One or more nodes returned error '$GLB_EXIT_ERRCODE'" && exit "$GLB_EXIT_ERRCODE"

	if [ -n "$doCmdExec" ]; then
		main_runCommandExec "$doCmdExec"
	fi
fi

if [ -n "$doBackup" ]; then
	log_msghead " *************** Starting logs backup **************** "
	main_backuplogs	
fi

exitcode=`echo $?`
if [ "$exitcode" -ne 0 ]; then
	#echo "exiting with exit code $exitcode"
	exit
fi

if [ -n "$doLogAnalyze" ]; then
	main_runLogDoctor
fi

rm -rf $RUNTEMPDIR 2>/dev/null
