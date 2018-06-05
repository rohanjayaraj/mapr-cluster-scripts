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
				if [ -z "$(echo "$1" | grep "]")" ]; then
					:> $dummyrole
					for i in $(echo "$1" | tr ',' ' '); do
						echo "$i,dummy" >> $dummyrole	
					done
				else
					echo "$1,dummy" > $dummyrole
				fi
				rolefile=$dummyrole
			else
				rolefile="/tmp/$1"
				maprutil_readClusterRoles "$rolefile" "$1"
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
if [ -n "$(ssh_checkSSHonNodes "$nodes")" ]; then
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
GLB_CLUSTER_SIZE=
GLB_ROLE_LIST=
GLB_TRACE_ON=1
GLB_ENABLE_AUDIT=
GLB_MULTI_MFS=
GLB_NUM_SP=
GLB_TRIM_SSD=
GLB_HAS_FUSE=
GLB_TABLE_NS=
GLB_CLDB_TOPO=
GLB_TSDB_TOPO=
GLB_CREATE_VOL=
GLB_PONTIS=
GLB_BG_PIDS=
GLB_DISK_TYPE=
GLB_MAX_DISKS=
GLB_MFS_MAXMEM=
GLB_MAPR_VERSION=
GLB_BUILD_VERSION=
GLB_MAPR_PATCH=
GLB_MEP_REPOURL=
GLB_PATCH_VERSION=
GLB_PATCH_REPOFILE=
GLB_PUT_BUFFER=
GLB_TABLET_DIST=
GLB_INDEX_NAME=
GLB_TRACE_PNAME=
GLB_SECURE_CLUSTER=
GLB_ENABLE_QS=
GLB_FS_THREADS=
GLB_GW_THREADS=
GLB_PERF_URL=
GLB_SYSINFO_OPTION=
GLB_GREP_MAPRLOGS=
GLB_LOG_VERBOSE=
GLB_COPY_DIR=
GLB_COPY_CORES=
GLB_MAIL_LIST=
GLB_MAIL_SUB=
GLB_SLACK_TRACE=
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
	    	doSkip=1
	        return 1
	    fi
	fi
    echo
    log_info "Checking if MapR is already installed on the nodes..."
    local islist=$(maprutil_isMapRInstalledOnNodes "$nodes")
	if [ -n "$islist" ]; then
		log_error "MapR is already installed on the node(s) [ $islist] or some stale binaries are still present. Scooting!"
		exit 255
	else
		log_info "No MapR installed on any node. Continuing installation..."
	fi

	# Read properties
	local clustername=$GLB_CLUSTER_NAME
	
	# Install required binaries on other nodes
	local buildexists=
	for node in ${nodes[@]}
	do
		local maprrepo=$(main_getRepoFile $node)
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
		log_info "****** Installing binaries on node -> $node ****** "
		maprutil_installBinariesOnNode "$node" "$nodebins" "bg"
	done
	maprutil_wait

	# SSH session exits after running for few seconds with error "Write failed: Broken pipe";
	#util_restartSSHD

	# Configure all nodes
	for node in ${nodes[@]}
	do
		log_info "****** Running configure on node -> $node ****** "
		maprutil_configureNode "$node" "$rolefile" "$clustername" "bg"
	done
	maprutil_wait

	# Check and install any binaries(ex: drill) post core binary installation
	local postinstnodes=$(maprutil_getPostInstallNodes $rolefile)
	if [ -n "$postinstnodes" ]; then
		for node in ${postinstnodes[@]}
		do
			local nodebins=$(maprutil_getNodeBinaries "$rolefile" "$node")
			maprutil_installBinariesOnNode "$node" "$nodebins" "bg"
		done
		maprutil_wait
		for node in ${postinstnodes[@]}
		do
			maprutil_postConfigureOnNode "$node" "bg"
		done
		maprutil_wait
		[ -n "$GLB_ENABLE_QS" ] && main_runCommandExec "queryservice"
		[ -n "$GLB_TSDB_TOPO" ] && main_runCommandExec "tsdbtopo"
	fi

	# Configure all nodes
	for node in ${nodes[@]}
	do
		maprutil_restartWardenOnNode "$node" "$rolefile"
	done
	maprutil_wait

	# Perform custom executions

	# Print URLs
	main_printURLs

	# Post to SLACK
	local cs="$(maprutil_getClusterSpec "$nodes")"
	util_postToSlack "$rolefile" "INSTALLED" "$cs"

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
	    	doSkip=1
	        return 1
	    fi
	fi
    echo
    log_info "Checking if MapR is installed on the nodes..."
	# Check if MapR is installed on all nodes
	local islist=$(maprutil_isMapRInstalledOnNodes "$nodes" "version")
	local notlist=
	for node in ${nodes[@]}
	do
		local isInstalled=$(echo "$islist" | grep $node)
		if [ -z "$isInstalled" ]; then
			notlist=$notlist"$node"" "
		else
			#??? Get install version
			[ -z "$GLB_MAPR_VERSION" ] && GLB_MAPR_VERSION=$(echo $isInstalled | awk '{print $2}')
			log_info "MapR is installed on node '$node' [ $(echo $isInstalled | awk '{print $2}') ]"
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
	
	# SSH session exits after running for few seconds with error "Write failed: Broken pipe";
	#util_restartSSHD

	# Configure all nodes
	for node in ${nodes[@]}
	do
		log_info "****** Running configure on node -> $node ****** "
		maprutil_configureNode "$node" "$rolefile" "$clustername" "bg"
	done
	maprutil_wait

	# Check and install any binaries(ex: drill) post core binary installation
	local postinstnodes=$(maprutil_getPostInstallNodes $rolefile)
	if [ -n "$postinstnodes" ]; then
		for node in ${postinstnodes[@]}
		do
			maprutil_postConfigureOnNode "$node" "bg"
		done
		maprutil_wait
		[ -n "$GLB_ENABLE_QS" ] && main_runCommandExec "queryservice"
		[ -n "$GLB_TSDB_TOPO" ] && main_runCommandExec "tsdbtopo" 
	fi

	# Restart all nodes
	for node in ${nodes[@]}
	do
		maprutil_restartWardenOnNode "$node" "$rolefile"
	done
	maprutil_wait

	# Print URLs
	main_printURLs

	# Post to SLACK
	local cs="$(maprutil_getClusterSpec "$nodes")"
	util_postToSlack "$rolefile" "RECONFIGURED" "$cs"

	log_msghead "[$(util_getCurDate)] Reconfiguration is complete! [ RunTime - $(main_timetaken) ]"
}

function main_upgrade(){
	log_msghead "[$(util_getCurDate)] Upgrading MapR on the following N-O-D-E-S : "
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
	    	log_msg "Upgrade C-A-N-C-E-L-L-E-D! "
	    	doSkip=1
	        return 1
	    fi
	fi
    echo
    log_info "Checking if MapR is installed on the nodes..."
	# Check if MapR is installed on all nodes
	local islist="$(maprutil_isMapRInstalledOnNodes "$nodes" "version")"
	local notlist=
	for node in ${nodes[@]}
	do
		local isInstalled=$(echo "$islist" | grep $node)
		if [ -z "$isInstalled" ]; then
			notlist=$notlist"$node"" "
		else
			log_info "MapR is installed on node '$node' [ $(echo $isInstalled | awk '{print $2}') ]"
		fi
	done

	if [ -n "$notlist" ]; then
		log_error "MapR not installed on the node(s) [ $notlist]. Trying install on the nodes first. Scooting!"
		exit 1
	else
		log_info "MapR installed on all nodes. Continuing upgrade..."
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
				log_warn " Node [$node] may not be part of the same cluster."
			else
				cldbnode="$cldbip"
			fi
		fi
	done

	if [ -n "$nocldblist" ]; then
		log_error "CLDB not found on nodes [$nocldblist]. May be upgrading another cluster's nodes. Check the nodes specified."
    	exit 1
	else
		log_info "CLDB Master : $cldbnode"
	fi

	local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	local cldbmaster=
    local zknodes=$(maprutil_getZKNodes "$rolefile")
    local buildexists=
    local sleeptime=60

    # First copy repo on all nodes
    local idx=
	for node in ${nodes[@]}
	do
		local maprrepo=$(main_getRepoFile $node)
		if [ -z "$idx" ]; then
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
					idx=1
					log_info "Stopping warden on all nodes..."
				fi
			fi
		else
			maprutil_copyRepoFile "$node" "$maprrepo" &
		fi
	done
	wait

	if [ -z "$doRolling" ]; then
		# First stop warden on all nodes
		for node in ${nodes[@]}
		do
			maprutil_restartWardenOnNode "$node" "$rolefile" "stop" 
		done

		log_info "Stopping zookeeper..."
		# Stop ZK on ZK nodes
		for node in ${zknodes[@]}
		do
			maprutil_restartZKOnNode "$node" "$rolefile" "stop"
		done
		maprutil_wait

		# Upgrade rest of the nodes
		log_info "Upgrading MapR on all nodes..."
		for node in ${nodes[@]}
		do	
			maprutil_upgradeNode "$node" "bg"
		done
		maprutil_wait

		# Kill all mapred jos & yarn applications

		for node in ${nodes[@]}
		do
			maprutil_restartWardenOnNode "$node" "$rolefile"
		done
		maprutil_wait
	else
		for node in ${zknodes[@]}
		do
			[ -n "$(echo $cldbnodes | grep $node)" ] && continue
			maprutil_rollingUpgradeOnNode "$node" "$rolefile"
			sleep $sleeptime
		done
		for node in ${nodes[@]}
		do
			[ -n "$(echo $zknodes | grep $node)" ] && continue
			[ -n "$(echo $cldbnodes | grep $node)" ] && continue
			[ -z "$cldbmaster" ] && cldbmaster=$(maprutil_getCLDBMasterNode "$node" "maprcli")
			maprutil_rollingUpgradeOnNode "$node" "$rolefile"
			sleep $sleeptime
		done
		for node in ${cldbnodes[@]}
		do
			[ -n "$(echo $cldbmaster | grep $node)" ] && continue 
			maprutil_rollingUpgradeOnNode "$node" "$rolefile"
			sleep $sleeptime
		done
		maprutil_rollingUpgradeOnNode "$cldbmaster" "$rolefile"
	fi

	# update upgraded mapr version
	sleep $sleeptime && maprutil_postUpgrade "$cldbnode"
	
	# Print URLs
	main_printURLs

	# Post to SLACK
	local cs="$(maprutil_getClusterSpec "$nodes")"
	util_postToSlack "$rolefile" "UPGRADED" "$cs"

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
	    	doSkip=1
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

	# Post to SLACK
	util_postToSlack "$rolefile" "UNINSTALLED"

	log_msghead "[$(util_getCurDate)] Uninstall is complete! [ RunTime - $(main_timetaken) ]"
}

function main_isMapRInstalled(){
	log_msg "Checking if MapR is installed on the nodes..."
	# Check if MapR is installed on all nodes
	local islist=$(maprutil_isMapRInstalledOnNodes "$nodes" "version")
	local notlist=
	for node in ${nodes[@]}
	do
		local isInstalled=$(echo "$islist" | grep $node)
		if [ -z "$isInstalled" ]; then
			notlist=$notlist"$node"" "
		else
			log_info "MapR is installed on node '$node' [ $(echo $isInstalled | awk '{print $2}') ]"
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
    	maprutil_zipLogsDirectoryOnNode "$node" "$timestamp" "$bkpRegex"
	done
	maprutil_wait
	for node in ${nodes[@]}
	do	
    	maprutil_copyZippedLogsFromNode "$node" "$timestamp" "$doBackup"
	done
	wait

	local scriptfile="$doBackup/extract.sh"
	echo -e '#!/bin/bash \n' > $scriptfile
	echo "echo \"extracting bzip2\"" >> $scriptfile
	echo "for i in \$(ls *.bz2);do bzip2 -dk \$i;done " >> $scriptfile
	echo "echo \"extracting tar\"" >> $scriptfile
	echo "for i in \$(ls *.tar);do DIR=\$(echo \$i| sed 's/.tar//g' | tr '.' '_' | cut -d'_' -f2); echo \$DIR;mkdir -p \$DIR;tar -xf \$i -C \$(pwd)/\$DIR && rm -f \${i}; done" >> $scriptfile
	chmod +x $scriptfile
	local delscriptfile="$doBackup/delextract.sh"
    echo -e '#!/bin/bash \n' > $delscriptfile
    echo "for i in \$(ls | grep -v \"bz2\$\" | grep -v \"extract.sh\$\");do rm -f \${i}; done" >> $delscriptfile
    chmod +x $delscriptfile

	log_msghead "[$(util_getCurDate)] Backup complete! [ RunTime - $(main_timetaken) ]"
}

function main_getmfstrace(){
	log_msghead "[$(util_getCurDate)] Getting stacktrace of mapr process on all nodes and copying the trace files to $copydir"
	local timestamp=$(date +%s)
	for node in ${nodes[@]}
	do	
    	maprutil_processtraceonNode "$node" "$timestamp" "$doNumIter"
	done
	maprutil_wait
	for node in ${nodes[@]}
	do	
    	maprutil_copyprocesstrace "$node" "$timestamp" "$copydir"
	done
	wait
}

function main_getmfscpuuse(){
	log_msghead "[$(util_getCurDate)] Building & collecting MFS/GW/Client CPU & Memory and MFS disk & network usage logs to '$copydir'"
	
	[ -z "$startstr" ] || [ -z "$endstr" ] && log_warn "Start/End time not specified. Using entire time range available"
	[ -z "$startstr" ] && [ -n "$endstr" ] && log_warn "Setting start time to end time" && startstr="$endstr" && endstr=
	
	local timestamp=$(date +%s)
	for node in ${nodes[@]}
	do	
		log_info "Building resource usage logs on node $node"
		maprutil_mfsCpuUseOnNode "$node" "$timestamp" "$startstr" "$endstr"
	done
	maprutil_wait
	for node in ${nodes[@]}
	do	
		maprutil_copymfscpuuse "$node" "$timestamp" "$copydir"
	done
	wait
	local mfsnodes=$(maprutil_getMFSDataNodes "$rolefile")
	log_info "Aggregating stats from all nodes [ $nodes ]"
	maprutil_mfsCPUUseOnCluster "$nodes" "$mfsnodes" "$copydir" "$timestamp" "$doPublish"
}

function main_getgutsstats(){
	log_msghead "[$(util_getCurDate)] Building & collecting 'guts' trends to $copydir"
	
	[ -z "$startstr" ] || [ -z "$endstr" ] && log_warn "Start/End time not specified. Using entire time range available"
	[ -z "$startstr" ] && [ -n "$endstr" ] && log_warn "Setting start time to end time" && startstr="$endstr" && endstr=
	local mfsnodes=$(maprutil_getMFSDataNodes "$rolefile")
	[ "$doGutsType" = "gw" ] && mfsnodes=$(maprutil_getGatewayNodes "$rolefile")
	local node=$(util_getFirstElement "$mfsnodes")

	local collist=$(marutil_getGutsSample "$node" "$doGutsType" )
	[ -z "$collist" ] && log_error "Guts column list is empty!" && return
	local defaultcols="$(maprutil_getGutsDefCols "$collist" "$doGutsCol")"
	local usedefcols=

	if [ "$doGutsType" = "gw" ]; then
		doGutsDef=
		[ -n "$(echo $doGutsCol | sed 's/,/ /g' | tr ' ' '\n' | grep 'all')" ] && usedefcols=1 && doGutsCol=
	elif [ -n "$doGutsCol" ] && [ -n "$(echo $doGutsCol | sed 's/,/ /g' | tr ' ' '\n' | grep 'stream\|cache\|fs\|db\|all')" ]; then
		doGutsCol=
		usedefcols=1
	fi
	if [ -n "$doGutsCol" ]; then
		doGutsCol="$(echo "$doGutsCol" | sed 's/,/ /g')"
	elif [ -n "$usedefcols" ] || [ -n "$doGutsDef" ]; then
		doGutsCol="$defaultcols"
	fi

	local colids=

	if [ -n "$doGutsCol" ]; then
		for c in $doGutsCol
		do
			local cid=$(echo $collist | grep -o -w "[0-9]*=$c" | cut -d'=' -f1)
			[ -n "$cid" ] && colids="$colids $cid"
		done
	else
		local tmpfile=$(mktemp)
		local ncollist=$(echo "$collist" | sed 's/\([0-9]*=\)/\\033\[95m\1/g' | sed 's/\(=[a-z]*\)/\\033\[0m\1/g')
		ncollist=$(echo "$ncollist" | sed '1~2 s/\(=[a-Z0-9_]*\)/\\033\[36m\1/g' | sed '1~2 s/\(=[a-Z0-9_]*\)/\1\\033\[0m/g')
		ncollist=$(echo "$ncollist" | sed '2~2 s/\(=[a-Z0-9_]*\)/\\033\[32m\1/g' | sed '2~2 s/\(=[a-Z0-9_]*\)/\1\\033\[0m/g')
		echo "$ncollist" > $tmpfile
		log_msghead "Guts column list : "
		log_msghead "------------------ "
		log_msg "$(column -t < $tmpfile | tr '=' ' ')"
		rm -rf $tmpfile > /dev/null 2>&1
		log_inline "Enter column numbers(space separated) to collect :"
		read colids
		[ -n "$colids" ] && log_info "Column list selected : $colids"
		[ -n "$colids" ] && colids=$(echo "$colids" | sed 's/,/ /g')
	fi

	[ -z "$colids" ] && log_error "No columns specified!" && return
	[ -z "$(echo $colids | grep -o -w "1")" ] && colids="$colids 1"
	[ -z "$(echo $colids | grep -o -w "2")" ] && colids="$colids 2"
	colids=$(echo $colids | sed 's/ /\n/g' | sort -n | sed 's/\n/ /g')

	local colnames=
	for colid in $colids
	do
		[ "$(util_isNumber "$colid")" = "false" ] && log_error "Invalid column id specified" && return
		[ -z "$(echo $collist | grep -o -w "$colid=[a-Z0-9_]*")" ] && log_error "Column id '$colid' doesn't exist" && return
		colnames="$colnames $(echo $collist | grep -o -w "$colid=[a-Z0-9_]*" | cut -d'=' -f2)"
	done

	[ -z "$doGutsType" ] && doGutsType="mfs"
	
	local timestamp=$(date +%s)
	for node in ${nodes[@]}
	do	
		[ -n "$(maprutil_isClientNode $rolefile $node)" ] && continue
		log_info "Building guts stats on node $node"
		maprutil_gutsStatsOnNode "$node" "$timestamp" "$doGutsType" "$colids" "$startstr" "$endstr"
	done
	maprutil_wait
	for node in ${nodes[@]}
	do	
		[ -n "$(maprutil_isClientNode $rolefile $node)" ] && continue
		maprutil_copygutsstats "$node" "$timestamp" "$copydir"
	done
	wait
	log_info "Aggregating guts stats from Nodes [$mfsnodes]"
	maprutil_gutstatsOnCluster "$mfsnodes" "$copydir" "$timestamp" "$colids" "$colnames" "$doPublish"
}

function main_runCommandExec(){
	if [ -z "$1" ]; then
        return
    fi
    local cmds=$1

    local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	local isInstalled=$(maprutil_isMapRInstalledOnNode "$cldbnode")
	if [ "$isInstalled" = "false" ]; then
		log_error "MapR is not installed on the cluster"
		return
	fi
	
	if [[ -n "$(echo $cmds | grep traceoff)" ]]; then
		for node in ${nodes[@]}
		do	
	    	maprutil_runCommandsOnNode "$node" "traceoff" "silent"
		done
		cmds=$(echo $cmds | sed 's/traceoff//')
	elif [[ -n "$(echo $cmds | grep 'traceon\|insttrace')" ]]; then
		local nodecmds=$(echo $cmds | tr ' ' '\n' |  grep -w 'traceon\|insttrace' | sed ':a;N;$!ba;s/\n/ /g')
		for node in ${nodes[@]}
		do	
			for nodecmd in $nodecmds
			do
	    		maprutil_runCommandsOnNode "$node" "$nodecmd" "silent"
	    	done
		done
		cmds=$(echo $cmds | sed 's/traceon//')
	fi
	maprutil_runCommandsOnNode "$cldbnode" "$cmds"
	
}

function main_runLogDoctor(){
	[ -z "$doLogAnalyze" ] && return
	local nodelist=
	local rc=0
	local mailfile=$(mktemp)

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
				maprutil_runCommandsOnNodesInParallel "$nodes" "diskcheck" "$mailfile"
        	;;
        	disktest)
				log_msghead "[$(util_getCurDate)] Running disk tests on all nodes"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "disktest" "$mailfile"
        	;;
        	mfsgrep)
				log_msghead "[$(util_getCurDate)] Grepping MFS logs on all nodes"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "mfsgrep" "$mailfile"
        	;;
        	clsspec)
				log_msghead "[$(util_getCurDate)] Printing cluster specifications"
				maprutil_getClusterSpec "$nodes"
        	;;
        	sysinfo)
				log_msghead "[$(util_getCurDate)] Running system info on all nodes"
				maprutil_runCommandsOnNodesInParallel "$nodes" "sysinfo" "$mailfile"
        	;;
        	greplogs)
				log_msghead "[$(util_getCurDate)] Grepping MapR logs on all nodes for key [ \"$GLB_GREP_MAPRLOGS\" ]"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "grepmapr"
        	;;
        	tabletdist)
				if [ -z "$GLB_INDEX_NAME" ]; then
					log_msghead "[$(util_getCurDate)] Checking tablet distribution for table '$GLB_TABLET_DIST'"
					maprutil_runCommandsOnNodesInParallel "$nodelist" "tabletdist" "$mailfile"
				elif [ -n "$GLB_LOG_VERBOSE" ]; then
					log_msghead "[$(util_getCurDate)] Checking $GLB_INDEX_NAME index table(s) tablet distribution for table '$GLB_TABLET_DIST'"
					maprutil_runCommandsOnNodesInParallel "$nodelist" "indexdist2" "$mailfile"
				else
					log_msghead "[$(util_getCurDate)] Checking $GLB_INDEX_NAME index table(s) tablet distribution for table '$GLB_TABLET_DIST'"
					maprutil_runCommandsOnNodesInParallel "$nodelist" "indexdist" "$mailfile"
				fi
        	;;
        	cntrdist)
				log_msghead "[$(util_getCurDate)] Checking container distribution"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "cntrdist" "$mailfile"
        	;;
        	setupcheck)
				log_msghead "[$(util_getCurDate)] Checking cluster services"
				maprutil_checkClusterSetupOnNodes "$nodelist" "$rolefile"
        	;;
        	analyzecores)
				log_msghead "[$(util_getCurDate)] Analyzing core files (if present)"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "analyzecores" "$mailfile"
				[ -n "$GLB_SLACK_TRACE" ] && [ -s "$mailfile" ] && util_postToSlack2 "$mailfile"
        	;;
        	mrinfo)
				log_msghead "[$(util_getCurDate)] Running mrconfig info "
				maprutil_runCommandsOnNodesInParallel "$nodelist" "mrinfo"
        	;;
        	mrdbinfo)
				log_msghead "[$(util_getCurDate)] Running mrconfig dbinfo "
				maprutil_runCommandsOnNodesInParallel "$nodelist" "mrdbinfo"
        	;;
        	mfstrace)
				main_getmfstrace
			;;
			mfscpuuse)
				main_getmfscpuuse
			;;
			gutsstats)
				main_getgutsstats
			;;
			traceoff)
				log_msghead "[$(util_getCurDate)] Disable traces on all nodes"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "traceoff"
        	;;
        	mfsthreads)
				log_msghead "[$(util_getCurDate)] Listing MFS Process thread details"
				maprutil_runCommandsOnNodesInParallel "$nodelist" "mfsthreads"
        	;;
        esac
        local ec=$GLB_EXIT_ERRCODE
        [ -n "$ec" ] && [ "$rc" -eq "0" ] && rc=$ec
	done
	if [ -s "$mailfile" ] && [ -n "$GLB_MAIL_LIST" ]; then
        sed -i "1s/^/\nNodelist : ${nodelist}\n\n/" $mailfile
        echo >> $mailfile
        local mailsub="$GLB_MAIL_SUB"
        [ -z "$mailsub" ] && mailsub="[ MapR LogDr Output ]"
        local tmpfile=$(mktemp)
        cat  $mailfile | a2h_convert "--bg=dark" "--palette=solarized" > $tmpfile
        util_sendMail "$GLB_MAIL_LIST" "$mailsub" "$tmpfile"
        rm -f $tmpfile > /dev/null 2>&1
    fi
    rm -f $mailfile > /dev/null 2>&1
	return $rc
}

function main_isValidBuildVersion(){
    if [ -z "$GLB_BUILD_VERSION" ]; then
        return
    fi
    local vlen=${#GLB_BUILD_VERSION}
    if [ "$(util_isNumber $GLB_BUILD_VERSION)" = "true" ]; then
    	 if [ "$vlen" -ge 12 ]; then
    	 	local buildts="${GLB_BUILD_VERSION:0:4}-${GLB_BUILD_VERSION:4:2}-${GLB_BUILD_VERSION:6:2} ${GLB_BUILD_VERSION:8:2}:${GLB_BUILD_VERSION:10:2}"
    	 	local validts="$(date -d "$buildts" +%s 2>/dev/null)"
    	 	if [ -z "$validts" ]; then
    	 		log_error "Invalid build timestamp specified. (ex: 201708181434)"
    	 		exit 1
    	 	fi
    	 elif [ "$vlen" -lt 5 ]; then
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
	#local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	#local cldbnode=$(util_getFirstElement "$cldbnodes")
	local node="$1"
	local maprrepo=
	local repofile=

	local nodeos=$(getOSFromNode $node)
	if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ]; then
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
	#local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	#local cldbnode=$(util_getFirstElement "$cldbnodes")

	#[ -z "$(echo $rolefile | grep mapr-patch)" ] && [ -z "$GLB_MAPR_PATCH" ] && GLB_PATCH_REPOFILE=
	maprutil_buildRepoFile "$repofile" "$useRepoURL" "$node"
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
	local addkibana="$1"
	local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	local newrolefile=$(mktemp -p $RUNTEMPDIR)
	cat $rolefile > $newrolefile
	for node in ${nodes[@]}
	do	
    	if [ -n "$(maprutil_isClientNode $rolefile $node)" ]; then
			continue
		elif [ "$node" = "$cldbnode" ]; then
    		sed -i "/$node/ s/$/,mapr-opentsdb,mapr-grafana,mapr-collectd/" $newrolefile
    		[ -n "$addkibana" ] && sed -i "/$node/ s/$/,mapr-elasticsearch,mapr-kibana,mapr-fluentd/" $newrolefile
    	else
    		sed -i "/$node/ s/$/,mapr-collectd/" $newrolefile
    		[ -n "$addkibana" ] && sed -i "/$node/ s/$/,mapr-fluentd/" $newrolefile
    	fi
	done
	rolefile=$newrolefile
}

function main_printURLs(){
	local cldbnodes=$(maprutil_getCLDBNodes "$rolefile")
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	local mcsnode=$(cat "$rolefile" | grep mapr-webserver | head -1 | cut -d',' -f1)
	local rmnode=$(cat "$rolefile" | grep mapr-resourcemanager | head -1 | cut -d',' -f1)
	local jtnode=$(cat "$rolefile" | grep mapr-jobtracker | head -1 | cut -d',' -f1)
	local gfnode=$(cat "$rolefile" | grep mapr-grafana | head -1 | cut -d',' -f1)
	local kbnode=$(cat "$rolefile" | grep mapr-kibana | head -1 | cut -d',' -f1)
	
	log_msghead "Cluster URLs : "
	log_msg "\t MCS - https://$mcsnode:8443"
	log_msg "\t CLDB - http://$cldbnode:7221"
	[ -n "$rmnode" ] && log_msg "\t RM - http://$rmnode:8088"
	[ -n "$jtnode" ] && log_msg "\t JT - http://$jtnode:50030"
	[ -n "$gfnode" ] && log_msg "\t Grafana - http://$gfnode:3000"
	[ -n "$kbnode" ] && log_msg "\t Kibana - http://$kbnode:5601"
}

function main_preSetup(){
	[ -z "$GLB_HAS_FUSE" ] && [ -n "$(cat $rolefile | grep mapr-posix)" ] && GLB_HAS_FUSE=1
	[ -z "$GLB_ROLE_LIST" ] && GLB_ROLE_LIST="$(maprutil_buildRolesList $rolefile)"
	[ -n "$copydir" ] && GLB_COPY_DIR="$copydir" && mkdir -p $GLB_COPY_DIR > /dev/null 2>&1
	GLB_CLUSTER_SIZE=$(cat $rolefile |  grep "^[^#;]" | grep 'mapr-fileserver' | wc -l)
}

function main_extractMapRVersion(){
	[ -z "$1" ] && return
	local url=$1
	url=$(echo $url | sed 's/\/$//g')
	local ver=$(echo $url | tr '/' '\n' | grep "^v[0-9]*.[0-9]*.[0-9]*")
	[ -z "$(echo $ver | grep 'v[0-9]*.[0-9]*.[0-9]*')" ] && return
	GLB_MAPR_VERSION=$(echo $ver | cut -d'_' -f1 | cut -d 'v' -f2)
	#echo $GLB_MAPR_VERSION
}

### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###

STARTTS=$(date +%s);
RUNTEMPDIR="/tmp/maprsetup/maprsetup_$(date +%Y-%m-%d-%H-%M-%S-%6N)"
mkdir -p $RUNTEMPDIR 2>/dev/null

doInstall=0
doUninstall=0
doUpgrade=0
doRolling=
doConfigure=0
doCmdExec=
doLogAnalyze=
doPontis=0
doForce=0
doSilent=0
doBackup=
doNumIter=10
doPublish=
doGutsDef=
doGutsCol=
doGutsType=
doSkip=
startstr=
endstr=
copydir=
bkpRegex=
useBuildID=
useRepoURL=
useMEPURL=

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
				if [[ "$i" = "createvol" ]] || [[ "$i" = "enableaudit" ]] || [[ "$i" = "auditstream" ]] || [[ "$i" = "tablecreate" ]] || [[ "$i" = "tablelz4" ]] || [[ "$i" = "jsontable" ]] || [[ "$i" = "cldbtopo" ]] || [[ "$i" = "jsontablecf" ]] || [[ "$i" = "tsdbtopo" ]] || [[ "$i" = "traceon" ]] || [[ "$i" = "traceoff" ]] || [[ "$i" = "insttrace" ]]; then
					if [[ "$i" = "cldbtopo" ]]; then
    					GLB_CLDB_TOPO=1
    				elif [[ "$i" = "traceon" ]]; then
    					GLB_TRACE_ON=
    				elif [[ "$i" = "tsdbtopo" ]]; then
    					GLB_TSDB_TOPO=1
    				elif [[ "$i" = "enableaudit" ]]; then
    					GLB_ENABLE_AUDIT=1
    				elif [[ "$i" = "auditstream" ]]; then
    					GLB_ENABLE_AUDIT=2
    				fi
    				if [ -z "$doCmdExec" ]; then
    					doCmdExec=$i
    				else
    					doCmdExec=$doCmdExec" "$i
    				fi
    			elif [[ "$i" = "force" ]]; then
    				doForce=1
    			elif [[ "$i" = "rolling" ]]; then
    				doRolling=1
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
    			elif [[ "$i" = "spy2" ]]; then
    				main_addSpyglass "addkibana"
    			elif [[ "$i" = "queryservice" ]]; then
    				GLB_ENABLE_QS=1
    			elif [[ "$i" = "ssdonly" ]]; then
    				GLB_DISK_TYPE="ssd"
    			elif [[ "$i" = "hddonly" ]]; then
    				GLB_DISK_TYPE="hdd"
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
	    		elif [[ "$i" = "cntrdist" ]]; then
	    			doLogAnalyze="$doLogAnalyze cntrdist"
	    		elif [[ "$i" = "setupcheck" ]]; then
	    			doLogAnalyze="$doLogAnalyze setupcheck"
	    		elif [[ "$i" = "analyzecores" ]]; then
	    			doLogAnalyze="$doLogAnalyze analyzecores"
	    		elif [[ "$i" = "mfstrace" ]]; then
	    			doLogAnalyze="$doLogAnalyze mfstrace"
	    		elif [[ "$i" = "mfscpuuse" ]]; then
	    			doLogAnalyze="$doLogAnalyze mfscpuuse"
	    		elif [[ "$i" = "mfsthreads" ]]; then
	    			doLogAnalyze="$doLogAnalyze $i"
	    		elif [[ "$i" = "publish" ]]; then
	    			GLB_PERF_URL="http://dash.perf.lab/puffd/"
	    		elif [[ "$i" = "gutsstats" ]]; then
	    			doLogAnalyze="$doLogAnalyze gutsstats"
	    		elif [[ "$i" = "mrinfo" ]]; then
	    			doLogAnalyze="$doLogAnalyze mrinfo"
	    		elif [[ "$i" = "mrdbinfo" ]]; then
	    			doLogAnalyze="$doLogAnalyze mrdbinfo"
	    		elif [[ "$i" = "gwguts" ]]; then
	    			doGutsType="gw"
	    		elif [[ "$i" = "defaultguts" ]]; then
	    			doGutsDef=1
	    		elif [[ "$i" = "copycores" ]]; then
    				GLB_COPY_CORES=1
	    		elif [[ "$i" = "slack" ]]; then
    				GLB_SLACK_TRACE=1
    			fi
	    	done
		;;
		-dir)
			[ -n "$VALUE" ] && copydir="$VALUE"
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
		-in)
			if [ -n "$VALUE" ]; then
				GLB_INDEX_NAME=$VALUE
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
    	-pn)
			if [ -n "$VALUE" ]; then
				GLB_TRACE_PNAME=$VALUE
			fi
		;;
    	-maxm)
			if [ -n "$VALUE" ]; then
    			GLB_MFS_MAXMEM=$VALUE
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
				copydir=$VALUE
			fi
    	;;
    	-st)
			if [ -n "$VALUE" ]; then
				startstr="$VALUE"
			fi
		;;
		-et)
			if [ -n "$VALUE" ]; then
				endstr="$VALUE"
			fi
		;;
		-pub)
			if [ -n "$VALUE" ]; then
				doPublish="$VALUE"
			fi
		;;
		-gc)
			if [ -n "$VALUE" ]; then
				doGutsCol="$VALUE"
			fi
		;;
		-it)
			if [ -n "$VALUE" ]; then
				doNumIter=$VALUE
			fi
		;;
    	-bf)
			if [ -n "$VALUE" ]; then
				bkpRegex=$VALUE
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
    	-ft)
			if [ -n "$VALUE" ]; then
				GLB_FS_THREADS=$VALUE
			fi
    	;;
    	-gt)
			if [ -n "$VALUE" ]; then
				GLB_GW_THREADS=$VALUE
			fi
    	;;
    	-repo)
			if [ -n "$VALUE" ]; then
				useRepoURL="$VALUE" && main_extractMapRVersion "$useRepoURL"
				[ -z "$GLB_PATCH_REPOFILE" ] && [ -n "$(echo ${useRepoURL} | grep "releases-dev")" ] && GLB_PATCH_REPOFILE="$(echo ${useRepoURL} | sed 's/\(\/v[0-9].[0-9].[0-9]\)/\/patches\1/g')"
				#[ -z "$GLB_PATCH_REPOFILE" ] && GLB_PATCH_REPOFILE="${useRepoURL%?}-patch-EBF"
				[ -z "$(wget $GLB_PATCH_REPOFILE -O- 2>/dev/null)" ] && GLB_PATCH_REPOFILE=
			fi
		;;
		-prepo)
			if [ -n "$VALUE" ]; then
				GLB_PATCH_REPOFILE="$VALUE"
			fi
		;;
		-meprepo)
			if [ -n "$VALUE" ]; then
				GLB_MEP_REPOURL="$VALUE"
			fi
		;;
		-mail)
			if [ -n "$VALUE" ]; then
				GLB_MAIL_LIST="$VALUE"
			fi
		;;
		-sub)
			if [ -n "$VALUE" ]; then
				GLB_MAIL_SUB="$VALUE"
			fi
		;;
		-vol)
			if [ -n "$VALUE" ]; then
				GLB_CREATE_VOL="$VALUE"
			fi
		;;
		-pid)
 			if [ -n "$VALUE" ]; then
 				GLB_PATCH_VERSION=$VALUE
 				GLB_MAPR_PATCH=1
 			fi
 		;;
 		*)
            log_error "unknown option \"$OPTION\""
            main_usage
            exit 1
            ;;
    esac
    shift
done

## Run presetup
main_preSetup

if [ -z "$dummyrole" ]; then 
	if [ "$doInstall" -eq 1 ]; then
		log_msghead " *************** Starting Cluster Installation **************** "
		main_install
	elif [ "$doUninstall" -eq 1 ]; then
		log_msghead " *************** Starting Cluster Uninstallation **************** "
		main_uninstall
		doSkip=1
	elif [ "$doUpgrade" -eq 1 ]; then
		log_msghead " *************** Starting Cluster Upgrade **************** "
		main_upgrade
	elif [ "$doConfigure" -eq 1 ]; then
		log_msghead " *************** Starting Cluster Reset & configuration **************** "
		main_reconfigure
	fi

	[ -n "$GLB_EXIT_ERRCODE" ] && log_critical "One or more nodes returned error '$GLB_EXIT_ERRCODE'" && exit "$GLB_EXIT_ERRCODE"

	if [ -z "$doSkip" ] && [ -n "$doCmdExec" ]; then
		main_runCommandExec "$doCmdExec"
	fi
fi

if [ -z "$doSkip" ] && [ -n "$doBackup" ]; then
	log_msghead " *************** Starting logs backup **************** "
	main_backuplogs	
fi

if [ -z "$doSkip" ] && [ -n "$doLogAnalyze" ]; then
	main_runLogDoctor
fi

exitcode=`echo $?`

rm -rf $RUNTEMPDIR 2>/dev/null
exit $exitcode

