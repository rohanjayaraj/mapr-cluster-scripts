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
				nls=$(echo "$1" | sed 's/],*/]\n/g' | sed 's/[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*,/&\n/g' | sed 's/,*$//g' | sed '/^\s*$/d')
				:> $dummyrole
        for nl in $nls; do
          if [ -z "$(echo "$nl" | grep "]")" ]; then
                for i in $(echo "$nl" | tr ',' ' '); do
                    echo "$i,dummy" >> $dummyrole
                done
          else
                echo "$nl,dummy" >> $dummyrole
          fi
        done
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
GLB_FORCE_DOWNLOAD=
GLB_MAPR_PATCH=
GLB_MAPR_REPOURL=
GLB_MEP_REPOURL=
GLB_PATCH_VERSION=
GLB_PATCH_REPOFILE=
GLB_PUT_BUFFER=
GLB_TABLET_DIST=
GLB_INDEX_NAME=
GLB_TRACE_PNAME=
GLB_SECURE_CLUSTER=
GLB_ENABLE_RDMA=
GLB_ENABLE_DARE=
GLB_ENABLE_QS=
GLB_ATS_USERTICKETS=
GLB_ATS_CLIENTSETUP=
GLB_ATS_CLUSTER=
GLB_FS_THREADS=
GLB_GW_THREADS=
GLB_PERF_URL=
GLB_NODE_STATS=
GLB_SYSINFO_OPTION=
GLB_GREP_MAPRLOGS=
GLB_GREP_EXCERPT=
GLB_GREP_OCCURENCE=
GLB_LOG_VERBOSE=
GLB_COPY_DIR=
GLB_COPY_CORES=
GLB_MAIL_LIST=
GLB_MAIL_SUB=
GLB_SLACK_TRACE=
GLB_CUSTOM_SLACK=
GLB_PERF_OPTION=
GLB_PERF_INTERVAL=
GLB_ASAN_OPTIONS=
GLB_SSLKEY_COPY=1
GLB_USE_JDK17=
GLB_USE_PYTHON39=
GLB_ENABLE_HSM=1
GLB_MINIO_PORT=9000
GLB_MVN_HOST=maven.foo.org
GLB_ART_HOST=artifactory.devops.lab
GLB_CRY_HOST=ntp.foo.org
GLB_DKR_HOST=docker.foo.org
GLB_EXT_ARGS=
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
	
	# resolve hosts
	for node in ${nodes[@]}; do
		main_buildServiceHostNames "${node}"
	done

	# Install required binaries on other nodes
	local buildexists=
	for node in ${nodes[@]}
	do
		local maprrepo=$(main_getRepoFile $node)
		# Copy mapr.repo if it doen't exist
		maprutil_copyRepoFile "$node" "$maprrepo" && [ -z "$GLB_MAPR_VERSION" ] && GLB_MAPR_VERSION=$(maprutil_getMapRVersionFromRepo $node)
		[ -n "$GLB_MAPR_PATCH" ] && maprutil_buildPatchRepoURL "$node" "$maprrepo"
		if [ -n "$GLB_BUILD_VERSION" ] && [ -z "$buildexists" ]; then
			main_isValidBuildVersion
			buildexists=$(maprutil_checkBuildExists "$node" "$GLB_BUILD_VERSION")
			if [ -z "$buildexists" ]; then
				log_error "Specified build version [$GLB_BUILD_VERSION] doesn't exist in the configured repositories. Please check the repo file"
				exit 1
			elif [[ "$GLB_BUILD_VERSION" = "latest" ]]; then
				GLB_BUILD_VERSION="${buildexists}"
			fi
		fi
		local nodebins=$(maprutil_getCoreNodeBinaries "$node")
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
		maprutil_configureNode "$node" "$clustername" "bg"
	done
	maprutil_wait

	# Check and install any binaries(ex: drill) post core binary installation
	local postinstnodes=$(maprutil_getPostInstallNodes)
	if [ -n "$postinstnodes" ]; then
		for node in ${postinstnodes[@]}
		do
			local nodebins=$(maprutil_getNodeBinaries "$node")
			maprutil_installBinariesOnNode "$node" "$nodebins" "bg" "rerun"
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

	if [ -n "$doASAN" ]; then
		local santypes=(${doASAN})
		local numsantypes=${#santypes[@]}
		declare -A santypemap
		local k=0
		for node in ${nodes[@]}; do
			local santype=${santypes[${k}]}
			local santypenodes=${santypemap[${santype}]}
			if [ -n "${santypenodes}" ]; then 
				santypenodes="${santypenodes} ${node}"
			else
				santypenodes="${node}"
			fi
			santypemap[${santype}]="${santypenodes}"
			let k=k+1
			[[ "${k}" -eq "${numsantypes}" ]] && k=0
		done
		for k in "${!santypemap[@]}"; do
			if [[ -z "$(echo ${k} | grep client)" ]]; then 
				log_info "Installing ${k^^}-ed MFS & Gateway binaries on the nodes [${santypemap[$k]}]"
			else
				log_info "Installing $(echo ${k^^} | sed 's/CLIENT//')-ed MFS, Gateway & Client binaries on the nodes [${santypemap[$k]}]"
			fi
			for l in ${santypemap[$k]}; do
				maprutil_runCommandsOnNode "$l" "$k" &
				maprutil_addToPIDList "$!" 
			done
			#maprutil_runCommandsOnNodesInParallel "${santypemap[$k]}" "${k}" &
		done
		maprutil_wait
	else
		# Configure all nodes
		for node in ${nodes[@]}
		do
			maprutil_restartWardenOnNode "$node"
		done
		maprutil_wait
	fi

	# Perform custom executions

	# Print URLs
	main_printURLs

	# Post to SLACK
	local cs="$(maprutil_getClusterSpec "$nodes")"
	util_postToSlack "$(maprutil_getRolesList)" "INSTALLED" "$cs"

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
		maprutil_cleanPrevClusterConfigOnNode "$node"
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
		maprutil_configureNode "$node" "$clustername" "bg"
	done
	maprutil_wait

	# Check and install any binaries(ex: drill) post core binary installation
	local postinstnodes=$(maprutil_getPostInstallNodes)
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
		maprutil_restartWardenOnNode "$node"
	done
	maprutil_wait

	# Print URLs
	main_printURLs

	# Post to SLACK
	local cs="$(maprutil_getClusterSpec "$nodes")"
	util_postToSlack "$(maprutil_getRolesList)" "RECONFIGURED" "$cs"

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

	local cldbnodes=$(maprutil_getCLDBNodes)
	local cldbmaster=
    local zknodes=$(maprutil_getZKNodes)
    local buildexists=
    local sleeptime=60

    # First copy repo on all nodes
    local idx=

  # resolve hosts
	for node in ${nodes[@]}; do
		main_buildServiceHostNames "${node}"
	done

	for node in ${nodes[@]}
	do
		local maprrepo=$(main_getRepoFile $node)
		if [ -z "$idx" ]; then
			# Copy mapr.repo if it doen't exist
			maprutil_copyRepoFile "$node" "$maprrepo" && [ -z "$GLB_MAPR_VERSION" ] && GLB_MAPR_VERSION=$(maprutil_getMapRVersionFromRepo $node)
			[ -n "$GLB_MAPR_PATCH" ] && maprutil_buildPatchRepoURL "$node"
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
					[[ "$GLB_BUILD_VERSION" = "latest" ]] && GLB_BUILD_VERSION="${buildexists}"
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
			maprutil_restartWardenOnNode "$node" "stop" 
		done
		maprutil_wait

		log_info "Stopping zookeeper..."
		# Stop ZK on ZK nodes
		for node in ${zknodes[@]}
		do
			maprutil_restartZKOnNode "$node" "stop"
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
			maprutil_restartWardenOnNode "$node"
		done
		maprutil_wait
	else
		for node in ${zknodes[@]}
		do
			[ -n "$(echo $cldbnodes | grep $node)" ] && continue
			maprutil_rollingUpgradeOnNode "$node"
			sleep $sleeptime
		done
		for node in ${nodes[@]}
		do
			[ -n "$(echo $zknodes | grep $node)" ] && continue
			[ -n "$(echo $cldbnodes | grep $node)" ] && continue
			[ -z "$cldbmaster" ] && cldbmaster=$(maprutil_getCLDBMasterNode "$node" "maprcli")
			maprutil_rollingUpgradeOnNode "$node"
			sleep $sleeptime
		done
		for node in ${cldbnodes[@]}
		do
			[ -n "$(echo $cldbmaster | grep $node)" ] && continue 
			maprutil_rollingUpgradeOnNode "$node"
			sleep $sleeptime
		done
		maprutil_rollingUpgradeOnNode "$cldbmaster"
	fi

	# update upgraded mapr version
	sleep $sleeptime && maprutil_postUpgrade "$cldbnode"
	
	# Print URLs
	main_printURLs

	# Post to SLACK
	local cs="$(maprutil_getClusterSpec "$nodes")"
	util_postToSlack "$(maprutil_getRolesList)" "UPGRADED" "$cs"

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
	util_postToSlack "$(maprutil_getRolesList)" "UNINSTALLED"

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
			[ "$(echo $nodes | wc -w)" -eq "$(echo $notlist | wc -w)" ] && [ "$doForce" -lt 2 ] && log_msg "No MapR installed on the cluster. Scooting!" && exit 1
		fi
	fi
}

function main_minioinstall(){
	#set -x
	# Warn user 
	log_msghead "[$(util_getCurDate)] Installing MinIO on the following N-O-D-E-S : "
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
    log_info "Checking if MinIO is already installed on the nodes..."
    local islist=
    for node in ${nodes[@]}
    do
    	local isInstalled=$(minioutil_isInstalledOnNode "${node}")
    	if [ -n "${isInstalled}" ]; then
    		[ -n "${islist}" ] && islist="${islist} "
    		islist="${islist}${node}"
    	fi
    done
	if [ -n "$islist" ]; then
		log_error "MinIO is already installed on the node(s) [ $islist]. Scooting!"
		exit 255
	else
		log_info "No MinIO installed on any node. Continuing installation..."
	fi

	# resolve hosts
	for node in ${nodes[@]}; do
		main_buildServiceHostNames "${node}"
	done
	
	# Install required binaries on other nodes
	for node in ${nodes[@]}
	do
		[ -n "${noMinioOnCLDB}" ] && [ -n "$(echo $(maprutil_getNodesForService "mapr-cldb") | grep "$node")" ] && continue
		log_info "****** Installing MinIO on node -> $node ****** "
		local maprrepo=$(main_getRepoFile $node)
		# Copy mapr.repo if it doen't exist
		maprutil_copyRepoFile "$node" "$maprrepo"
		minioutil_setupOnNode "$node"
	done
	maprutil_wait

	# Get all disks configured per host
	local minioopts=
	for node in ${nodes[@]}
	do
		[ -n "${noMinioOnCLDB}" ] && [ -n "$(echo $(maprutil_getNodesForService "mapr-cldb") | grep "$node")" ] && continue
		local hostopts=$(minioutil_getHostDiskOpt "${node}")
		[ -n "${minioopts}" ] && minioopts="${minioopts} "
		minioopts="${minioopts}${hostopts}"
	done

	# Configure MinIO & start services
	log_info "Configuring MinIO with server list : ${minioopts}"
	for node in ${nodes[@]}
	do
		[ -n "${noMinioOnCLDB}" ] && [ -n "$(echo $(maprutil_getNodesForService "mapr-cldb") | grep "$node")" ] && continue
		log_info "****** Configuring MinIO on node -> $node ****** "
		minioutil_configureOnNode "$node" "${minioopts}"
	done
	maprutil_wait

	# Post to SLACK
	local cs="$(maprutil_getClusterSpec "$nodes")"
	util_postToSlack "$(maprutil_getRolesList)" "MINIO_INSTALLED" "$cs"

	#set +x
	log_msghead "[$(util_getCurDate)] MinIO install is complete! [ RunTime - $(main_timetaken) ]"
}

function main_miniouninstall(){

	# Warn user 
	log_msghead "[$(util_getCurDate)] Uninstalling MinIO on the following N-O-D-E-S : "
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
    
    echo
    log_info "Checking if MinIO is installed on the nodes..."
    local islist=
    for node in ${nodes[@]}
    do
    	local isInstalled=$(minioutil_isInstalledOnNode "${node}")
    	if [ -n "${isInstalled}" ]; then
    		[ -n "${islist}" ] && islist="${islist} "
    		islist="${islist}${node}"
    	fi
    done
	if [ -z "$islist" ]; then
		log_error "MinIO not found on the node(s). Scooting!"
		exit 255
	else
		log_info "MinIO installed on the node(s) [${islist}]. Continuing uninstallation..."
	fi

	# Uninstall minIO on other nodes
	for node in ${nodes[@]}
	do
		log_info "****** Uninstalling MinIO on node -> $node ****** "
		minioutil_removeOnNode "$node"
	done
	maprutil_wait

	# Post to SLACK
	util_postToSlack "$(maprutil_getRolesList)" "MINIO_UNINSTALLED"

	log_msghead "[$(util_getCurDate)] MinIO uninstall is complete! [ RunTime - $(main_timetaken) ]"
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
    	maprutil_copyZippedLogsFromNode "$node" "$timestamp" "$doBackup" &
	done
	wait

	local scriptfile="$doBackup/extract.sh"
	echo -e '#!/bin/bash \n' > $scriptfile
	echo "echo \"extracting bzip2\"" >> $scriptfile
	echo "for i in \$(ls *.bz2);do bzip2 -dk \$i & done " >> $scriptfile
	echo "wait" >> $scriptfile
	echo "echo \"extracting tar\"" >> $scriptfile
	echo "for i in \$(ls *.tar);do DIR=\$(echo \$i| sed 's/.tar//g' | tr '.' '_' | cut -d'_' -f2); echo \$DIR;mkdir -p \$DIR;tar -xf \$i -C \$(pwd)/\$DIR & done" >> $scriptfile
	echo "wait" >> $scriptfile
	echo "for i in \$(ls *.tar);do rm -f \${i} & done" >> $scriptfile
	echo "wait" >> $scriptfile
	chmod +x $scriptfile
	local delscriptfile="$doBackup/delextract.sh"
    echo -e '#!/bin/bash \n' > $delscriptfile
    echo "for i in \$(ls | grep -v \"bz2\$\" | grep -v \"extract.sh\$\");do rm -rf \${i}; done" >> $delscriptfile
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
    	maprutil_copyprocesstrace "$node" "$timestamp" "$copydir" &
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
		maprutil_copymfscpuuse "$node" "$timestamp" "$copydir" &
	done
	wait
	local mfsnodes=$(maprutil_getMFSDataNodes)
	[ -z "$mfsnodes" ] && mfsnodes="$nodes"
	log_info "Aggregating stats from all nodes [ $nodes ]"
	maprutil_mfsCPUUseOnCluster "$nodes" "$mfsnodes" "$copydir" "$timestamp" "$doPublish"
}

function main_getgutsstats(){
	[ -f "${copydir}" ] && [ -s "${copydir}" ] && main_publishlocalgutsstats && return

	log_msghead "[$(util_getCurDate)] Building & collecting 'guts' trends to $copydir"
	
	[ -z "$startstr" ] || [ -z "$endstr" ] && log_warn "Start/End time not specified. Using entire time range available"
	[ -z "$startstr" ] && [ -n "$endstr" ] && log_warn "Setting start time to end time" && startstr="$endstr" && endstr=
	local mfsnodes=$(maprutil_getMFSDataNodes)
	[ "$doGutsType" = "gw" ] && mfsnodes=$(maprutil_getGatewayNodes)
	local node=$(util_getFirstElement "$mfsnodes")

	local collist=$(marutil_getGutsSample "$node" "$doGutsType" )
	if [ -z "$collist" ]; then
		mfsnodes="$nodes"
		for node in ${nodes[@]}
		do
			collist=$(marutil_getGutsSample "$node" "$doGutsType" )
			[ -n "$collist" ] && break
		done
	fi
	[ -z "$collist" ] && log_error "Guts column list is empty!" && return
	local defaultcols="$(maprutil_getGutsDefCols "$collist" "$doGutsCol")"
	local usedefcols=

	if [ "$doGutsType" = "gw" ] || [ "$doGutsType" = "moss" ] || [ "$doGutsType" = "mast" ]; then
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
		ncollist=$(echo "$ncollist" | sed '1~2 s/\(=[A-Za-z0-9_]*\)/\\033\[36m\1/g' | sed '1~2 s/\(=[A-Za-z0-9_]*\)/\1\\033\[0m/g')
		ncollist=$(echo "$ncollist" | sed '2~2 s/\(=[A-Za-z0-9_]*\)/\\033\[32m\1/g' | sed '2~2 s/\(=[A-Za-z0-9_]*\)/\1\\033\[0m/g')
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
		[ -z "$(echo $collist | grep -o -w "$colid=[A-Za-z0-9_]*")" ] && log_error "Column id '$colid' doesn't exist" && return
		colnames="$colnames $(echo $collist | grep -o -w "$colid=[A-Za-z0-9_]*" | cut -d'=' -f2)"
	done

	[ -z "$doGutsType" ] && doGutsType="mfs"
	
	local timestamp=$(date +%s)
	for node in ${nodes[@]}
	do	
		[ -n "$(maprutil_isClientNode $node)" ] && continue
		log_info "Building guts stats on node $node"
		maprutil_gutsStatsOnNode "$node" "$timestamp" "$doGutsType" "$colids" "$startstr" "$endstr"
	done
	maprutil_wait
	for node in ${nodes[@]}
	do	
		[ -n "$(maprutil_isClientNode $node)" ] && continue
		maprutil_copygutsstats "$node" "$timestamp" "$copydir" &
	done
	wait
	log_info "Aggregating guts stats from Nodes [$mfsnodes]"
	maprutil_gutstatsOnCluster "$mfsnodes" "$copydir" "$timestamp" "$colids" "$colnames" "$doPublish"
}

function main_publishlocalgutsstats(){
	log_msghead "[$(util_getCurDate)] Publishing local guts stats"
	
	[ -z "$startstr" ] || [ -z "$endstr" ] && log_warn "Start/End time not specified. Using entire time range available"
	[ -z "$startstr" ] && [ -n "$endstr" ] && log_warn "Setting start time to end time" && startstr="$endstr" && endstr=
	local localgutsfile=${copydir}

	[ ! -f "${localgutsfile}" ] || [ ! -s "${localgutsfile}" ] && log_error "${localgutsfile} is empty or doesn't exist!" && return

	local collist=$(marutil_getGutsSample "${localgutsfile}")
	[ -z "$collist" ] && log_error "Guts column list is empty!" && return
	local defaultcols="$(maprutil_getGutsDefCols "$collist" "$doGutsCol")"
	local usedefcols=

	if [ -n "$doGutsCol" ] && [ -n "$(echo $doGutsCol | sed 's/,/ /g' | tr ' ' '\n' | grep 'stream\|cache\|fs\|db\|all')" ]; then
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
		ncollist=$(echo "$ncollist" | sed '1~2 s/\(=[A-Za-z0-9_]*\)/\\033\[36m\1/g' | sed '1~2 s/\(=[A-Za-z0-9_]*\)/\1\\033\[0m/g')
		ncollist=$(echo "$ncollist" | sed '2~2 s/\(=[A-Za-z0-9_]*\)/\\033\[32m\1/g' | sed '2~2 s/\(=[A-Za-z0-9_]*\)/\1\\033\[0m/g')
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
		[ -z "$(echo $collist | grep -o -w "$colid=[A-Za-z0-9_]*")" ] && log_error "Column id '$colid' doesn't exist" && return
		colnames="$colnames $(echo $collist | grep -o -w "$colid=[A-Za-z0-9_]*" | cut -d'=' -f2)"
	done

	[ -z "$doGutsType" ] && doGutsType="mfs"
	
	local timestamp=$(date +%s)
	local tmpdir=$(maprutil_buildGutsStats "${timestamp}" "${doGutsType}" "${colids}" "${startstr}" "${endstr}" "${localgutsfile}")

	maprutil_publishGutsStats "${tmpdir}" "${timestamp}" "UNKNOWN" "UNKNOWN" "$colnames" "${doPublish}"
	rm -rf ${tmpdir} > /dev/null 2>&1	
}

function main_perftool(){
	[ -z "$copydir" ] && log_error "Copy directory not specified. Specify '-cc=</path/to/dir>' option" && exit 1

	log_msghead "[$(util_getCurDate)] Running 'perf' CPU profiler on nodes and copying output to '$copydir'"
	
	local timestamp=$(date +%s)
	for node in ${nodes[@]}
	do	
		maprutil_perfToolOnNode "$node" "$timestamp"
	done
	maprutil_wait
	for node in ${nodes[@]}
	do	
		maprutil_copyperfoutput "$node" "$timestamp" "$copydir" &
	done
	wait
	for node in ${nodes[@]}
	do	
		maprutil_printperfoutput "$node" "$copydir"
	done
}

function main_runCommandExec(){
	if [ -z "$1" ]; then
        return
    fi
    local cmds="$1"

    local cldbnodes=$(maprutil_getCLDBNodes)
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
	local mailfile=$logdrfile
	[ -z "$mailfile" ] && mailfile=$(mktemp)

	for node in ${nodes[@]}
	do	
		if [ -n "$(maprutil_isClientNode $node)" ]; then
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
        	disktest | disktest2)
				log_msghead "[$(util_getCurDate)] Running disk tests on all nodes"
				maprutil_runCommandsOnNodesInParallel "$nodes" "$i" "$mailfile"
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
				maprutil_runCommandsOnNodesInParallel "$nodes" "grepmapr"
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
				maprutil_checkClusterSetupOnNodes "$nodelist"
        	;;
        	analyzecores)
				log_msghead "[$(util_getCurDate)] Analyzing core files (if present)"
				local tmailfile=$(mktemp)
				maprutil_runCommandsOnNodesInParallel "$nodes" "analyzecores" "$tmailfile"
				if [ -n "$GLB_SLACK_TRACE" ] && [ -s "$tmailfile" ]; then
					local nodupfile=$(mktemp)
					cp ${tmailfile} ${nodupfile} > /dev/null 2>&1
					if [ -z "${GLB_LOG_VERBOSE}" ]; then
						maprutil_dedupCores "${nodupfile}"
						cat ${nodupfile} >> ${mailfile}
						sed -i "1s/^/\nNodelist : ${nodes}\n\n/" ${nodupfile}  > /dev/null 2>&1
					else
						cat ${tmailfile} >> ${mailfile}
					fi
					[ -n "${GLB_MAIL_SUB}" ] && sed -i "3s/^/\ Subject: ${GLB_MAIL_SUB}\n/" ${nodupfile}  > /dev/null 2>&1
					util_postToSlack2 "${nodupfile}" "https://bit.ly/2vPLzrO"
					rm -rf ${nodupfile} > /dev/null 2>&1
				else
					cat ${tmailfile} >> ${mailfile}
				fi
				rm -rf ${tmailfile}  > /dev/null 2>&1
        	;;
        	analyzeasan)
				local tmailfile=$(mktemp)
				log_msghead "[$(util_getCurDate)] Analyzing ASAN errors reported in logs, if any"
				maprutil_runCommandsOnNodesInParallel "$nodes" "analyzeasan" "$tmailfile"
				cat ${tmailfile} >> ${mailfile}
				if [ -n "$GLB_SLACK_TRACE" ] && [ -s "$tmailfile" ]; then
					local nodupfile=$(mktemp)
					cp ${tmailfile} ${nodupfile} > /dev/null 2>&1
					if [ -z "${GLB_LOG_VERBOSE}" ]; then
						maprutil_dedupASANErrors "${nodupfile}"
						sed -i "1s/^/\nNodelist : ${nodes}\n\n/" ${nodupfile}  > /dev/null 2>&1
					fi
					[ -n "${GLB_MAIL_SUB}" ] && sed -i "3s/^/\ Subject: ${GLB_MAIL_SUB}\n/" ${nodupfile}  > /dev/null 2>&1

				 	util_postToSlack2 "${nodupfile}" "https://bit.ly/3bYkfY2"
					util_postToMSTeams "${nodupfile}" "https://bit.ly/2TBRKJ9"
					rm -rf ${nodupfile} > /dev/null 2>&1
				fi
				rm -rf ${tmailfile}  > /dev/null 2>&1
        	;;
        	mrinfo)
				log_msghead "[$(util_getCurDate)] Running mrconfig info "
				maprutil_runCommandsOnNodesInParallel "$nodelist" "mrinfo"
        	;;
        	mrdbinfo)
				log_msghead "[$(util_getCurDate)] Running mrconfig dbinfo "
				maprutil_runCommandsOnNodesInParallel "$nodelist" "mrdbinfo"
        	;;
        	perftool)
				main_perftool
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
				maprutil_runCommandsOnNodesInParallel "$nodes" "traceoff"
        	;;
        	mfsthreads)
				log_msghead "[$(util_getCurDate)] Listing MFS Process thread details"
				maprutil_runCommandsOnNodesInParallel "$nodes" "mfsthreads"
        	;;
        esac
        local ec=$GLB_EXIT_ERRCODE
        [ -n "$ec" ] && [ "$rc" -eq "0" ] && rc=$ec
	done
	if [ -s "$mailfile" ] && [ -n "$GLB_MAIL_LIST" ]; then
        sed -i "1s/^/\nNodelist : ${nodes}\n\n/" $mailfile
        echo >> $mailfile
        local mailsub="$GLB_MAIL_SUB"
        [ -z "$mailsub" ] && mailsub="[ MapR LogDr Output ]"
        local tmpfile=$(mktemp)
        cat  $mailfile | a2h_convert "--bg=dark" "--palette=solarized" > $tmpfile
        util_sendMail "$GLB_MAIL_LIST" "$mailsub" "$tmpfile"
        rm -f $tmpfile > /dev/null 2>&1
    fi
    if [ -s "${mailfile}" ] && [ -n "${GLB_CUSTOM_SLACK}" ]; then
    	local haslogs=$(cat ${mailfile} | grep -v -e "^Command " -e " \[" -e "^$")
    	if [ -n "${haslogs}" ]; then
    		sed -i '/^Command/,+1d' ${mailfile}  > /dev/null 2>&1
	    	sed -i "1s/^/\nNodelist : ${nodes}\n\n/" ${mailfile}  > /dev/null 2>&1
	    	util_postToSlack2 "${mailfile}" "${GLB_CUSTOM_SLACK}"
	    fi
    fi
    [ -z "$logdrfile" ] && rm -f $mailfile > /dev/null 2>&1
	return $rc
}

function main_isValidBuildVersion(){
    if [[ -z "$GLB_BUILD_VERSION" ]] || [[ "$GLB_BUILD_VERSION" = "latest" ]]; then
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
    	[ -z "${i}" ] && continue
        if kill -0 ${i} 2>/dev/null; then 
        	log_info "[$me] kill -9 $i"
        	kill -9 ${i} 2>/dev/null
        fi
    done
}

function main_buildServiceHostNames(){
	[ -n "${decryptdone}" ] && return
	[ -z "$1" ] && return

	local node=$1
  local hostname=$(maprutil_getMavenHost "${node}")
  [ -n "${hostname}" ] && GLB_MVN_HOST=${hostname} || return
  
  hostname=$(maprutil_getArtHost "${node}")
  [ -n "${hostname}" ] && GLB_ART_HOST=${hostname} || return

  hostname=$(maprutil_getCronyHost "${node}" ) 
  [ -n "${hostname}" ] && GLB_CRY_HOST=${hostname} || return

  hostname=$(maprutil_getDockerHost "${node}" )
  [ -n "${hostname}" ] && GLB_DKR_HOST=${hostname} || return
  
  [ -n "${useRepoURL}" ] && useRepoURL=$(echo "${useRepoURL}" | sed "s/artifactory.devops.lab/${GLB_ART_HOST}/g")
  [ -n "${useRepoURL}" ] && GLB_MAPR_REPOURL=${useRepoURL}
	[ -n "${GLB_PATCH_REPOFILE}" ] && GLB_PATCH_REPOFILE=$(echo "${GLB_PATCH_REPOFILE}" | sed "s/artifactory.devops.lab/${GLB_ART_HOST}/g")
	[ -n "${GLB_MEP_REPOURL}" ] && GLB_MEP_REPOURL=$(echo "${GLB_MEP_REPOURL}" | sed "s/artifactory.devops.lab/${GLB_ART_HOST}/g")

	decryptdone=1
}

function main_getRepoFile(){
	#local cldbnodes=$(maprutil_getCLDBNodes)
	#local cldbnode=$(util_getFirstElement)
	local node="$1"
	local maprrepo=
	local repofile=

	local nodeos=$(getOSFromNode $node)
	if [ "$nodeos" = "centos" ] || [ "$nodeos" = "suse" ] || [ "$nodeos" = "oracle" ]; then
       maprrepo=$repodir"/mapr.repo"
	   repofile="$repodir/mapr2.repo"
    elif [ "$nodeos" = "ubuntu" ]; then
       maprrepo=$repodir"/mapr.list"
	   repofile="$repodir/mapr2.list"
    fi

	if [ -z "$useRepoURL" ]; then
		sed -i "s/artifactory.devops.lab/${GLB_ART_HOST}/g" ${maprrepo}
		echo "$maprrepo"
		return
	fi
	#local cldbnodes=$(maprutil_getCLDBNodes)
	#local cldbnode=$(util_getFirstElement)

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
	local cldbnodes=$(maprutil_getCLDBNodes)
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	local newrolefile=$(mktemp -p $RUNTEMPDIR)
	cat $rolefile > $newrolefile
	for node in ${nodes[@]}
	do	
    	if [ -n "$(maprutil_isClientNode $node)" ]; then
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
	local roles="$(maprutil_getRolesList)"
	local cldbnodes=$(maprutil_getCLDBNodes)
	local cldbnode=$(util_getFirstElement "$cldbnodes")
	local mcsnode=$(echo "$roles" | grep mapr-webserver | head -1 | cut -d',' -f1)
	local rmnode=$(echo "$roles" | grep mapr-resourcemanager | head -1 | cut -d',' -f1)
	local jtnode=$(echo "$roles" | grep mapr-jobtracker | head -1 | cut -d',' -f1)
	local gfnode=$(echo "$roles" | grep mapr-grafana | head -1 | cut -d',' -f1)
	local kbnode=$(echo "$roles" | grep mapr-kibana | head -1 | cut -d',' -f1)
	local adds=
	[ -n "$GLB_SECURE_CLUSTER" ] && adds="s"
	
	log_msghead "Cluster URLs : "
	log_msg "\t MCS - http${adds}://$mcsnode:8443"
	log_msg "\t CLDB - http://$cldbnode:7221"
	[ -n "$rmnode" ] && log_msg "\t RM - http${adds}://$rmnode:8088"
	[ -n "$jtnode" ] && log_msg "\t JT - http${adds}://$jtnode:50030"
	[ -n "$gfnode" ] && log_msg "\t Grafana - http${adds}://$gfnode:3000"
	[ -n "$kbnode" ] && log_msg "\t Kibana - http${adds}://$kbnode:5601"
}

function main_preSetup(){
	# build roles list
	[ -z "$GLB_ROLE_LIST" ] && GLB_ROLE_LIST="$(maprutil_buildRolesList $rolefile)"
	if [[ "$addSpy" = "1" ]]; then 
		main_addSpyglass
	elif [[ "$addSpy" = "2" ]]; then
		main_addSpyglass "addkibana"
	fi
	# update roles list if spyglass was added
	[ -n "$addSpy" ] && GLB_ROLE_LIST="$(maprutil_buildRolesList $rolefile)"
	local roles="$(maprutil_getRolesList)"
	[ -z "$GLB_HAS_FUSE" ] && [ -n "$(echo "$roles" | grep mapr-posix)" ] && GLB_HAS_FUSE=1
	[ -n "$copydir" ] && GLB_COPY_DIR="$copydir" && mkdir -p $GLB_COPY_DIR > /dev/null 2>&1
	[ -z "$GLB_MAPR_PATCH" ] && [ -n "$(echo "$roles" | grep mapr-patch)" ] && GLB_MAPR_PATCH=1
	GLB_CLUSTER_SIZE=$(echo "$roles" |  grep "^[^#;]" | grep 'mapr-fileserver' | wc -l)

	[ -n "${GLB_PATCH_REPOFILE}" ] && [ -z "$(wget $GLB_PATCH_REPOFILE -t 1 -T 5 -O- 2>/dev/null)" ] && GLB_PATCH_REPOFILE=
}

function main_extractMapRVersion(){
	[ -z "$1" ] && return
	local url=$1
	url=$(echo $url | sed 's/\/$//g')
	local ver=$(echo $url | tr '/' '\n' | grep -wo "^v[0-9]*.[0-9]*.[0-9]*")
	[ -z "$(echo $ver | grep -wo 'v[0-9]*.[0-9]*.[0-9]*')" ] && return
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
doMinIOInstall=0
doMinIOUninstall=0
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
noMinioOnCLDB=
addSpy=
doASAN=
startstr=
endstr=
copydir=
logdrfile=
bkpRegex=
decryptdone=
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
		    	installminio)
					doMinIOInstall=1
		    	;;
		    	uninstallminio)
					doMinIOUninstall=1
		    	;;
		    esac
		    ;;
    	-e)
			for i in ${VALUE}; do
				#echo " extra option : $i"
				if [[ "$i" = "createvol" ]] || [[ "$i" = "enableaudit" ]] || [[ "$i" = "auditstream" ]] || [[ "$i" = "tablecreate" ]] || [[ "$i" = "tablelz4" ]] || [[ "$i" = "jsontable" ]] || [[ "$i" = "nocldbtopo" ]] || [[ "$i" = "cldbtopo" ]] || [[ "$i" = "jsontablecf" ]] || [[ "$i" = "tsdbtopo" ]] || [[ "$i" = "traceon" ]] || [[ "$i" = "traceoff" ]] || [[ "$i" = "insttrace" ]]; then
					if [[ "$i" = "cldbtopo" ]]; then
    					GLB_CLDB_TOPO=1
    				elif [[ "$i" = "nocldbtopo" ]]; then
    					GLB_CLDB_TOPO=0
    				elif [[ "$i" = "traceoff" ]]; then
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
    				let doForce+=1
    			elif [[ "$i" = "rolling" ]]; then
    				doRolling=1
    			elif [[ "$i" = "pontis" ]]; then
    				GLB_PONTIS=1
    			elif [[ "$i" = "confirm" ]]; then
    				doSilent=1
    			elif [[ "$i" = "secure" ]]; then
    				GLB_SECURE_CLUSTER=1
    			elif [[ "$i" = "dare" ]]; then
    				GLB_ENABLE_DARE=1
    			elif [[ "$i" = "rdma" ]]; then
    				GLB_ENABLE_RDMA=1
    			elif [[ "$i" = "trim" ]]; then
    				GLB_TRIM_SSD=1
    			elif [[ "$i" = "patch" ]]; then
    				GLB_MAPR_PATCH=1
    			elif [[ "$i" = "spy" ]]; then
    				addSpy=1
    			elif [[ "$i" = "spy2" ]]; then
    				addSpy=2
    			elif [[ "$i" = "queryservice" ]]; then
    				GLB_ENABLE_QS=1
    			elif [[ "$i" = "atstickets" ]]; then
    				GLB_ATS_USERTICKETS=1
    			elif [[ "$i" = "atssetup" ]]; then
    				GLB_ATS_CLIENTSETUP=1
    			elif [[ "$i" = "atsconfig" ]]; then
    				GLB_ATS_CLUSTER=1
    			elif [[ "$i" = "ssdonly" ]]; then
    				GLB_DISK_TYPE="ssd"
    			elif [[ "$i" = "hddonly" ]]; then
    				GLB_DISK_TYPE="hdd"
    			elif [[ "$i" = "nvmeonly" ]]; then
    				GLB_DISK_TYPE="nvme"
    			elif [[ "$i" = "jdk17" ]]; then
    				GLB_USE_JDK17=1
    			elif [[ "$i" = "python39" ]]; then
    				GLB_USE_PYTHON39=1
    			elif [[ "$i" = "asan" ]]; then
    				doASAN="asan"
    			elif [[ "$i" = "asanall" ]]; then
    				doASAN="asanclient"
    			elif [[ "$i" = "ubsan" ]]; then
    				doASAN="ubsan"
    			elif [[ "$i" = "ubsanall" ]]; then
    				doASAN="ubsanclient"
    			elif [[ "$i" = "msan" ]]; then
    				doASAN="msan"
    			elif [[ "$i" = "msanall" ]]; then
    				doASAN="msanclient"
    			elif [[ "$i" = "asanmix" ]]; then
    				doASAN="asan ubsan msan"
    			elif [[ "$i" = "asanmixall" ]]; then
    				doASAN="asanclient ubsanclient msanclient"
    			elif [[ "$i" = "downloadbins" ]]; then
    				GLB_FORCE_DOWNLOAD=1
    			elif [[ "$i" = "nominiooncldb" ]]; then
    				noMinioOnCLDB=1
    			fi
    		done
    	;;
    	-l)
			for i in ${VALUE}; do
				if [[ "$i" = "diskerror" ]]; then
	    			doLogAnalyze="$doLogAnalyze diskerror"
	    		elif [[ "$i" = "disktest" ]]; then
	    			doLogAnalyze="$doLogAnalyze disktest"
	    		elif [[ "$i" = "disktest2" ]]; then
	    			doLogAnalyze="$doLogAnalyze disktest2"
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
	    		elif [[ "$i" = "analyzeasan" ]]; then
	    			doLogAnalyze="$doLogAnalyze analyzeasan"
	    		elif [[ "$i" = "mfstrace" ]]; then
	    			doLogAnalyze="$doLogAnalyze mfstrace"
	    		elif [[ "$i" = "mfscpuuse" ]]; then
	    			doLogAnalyze="$doLogAnalyze mfscpuuse"
	    		elif [[ "$i" = "mfsthreads" ]]; then
	    			doLogAnalyze="$doLogAnalyze $i"
	    		elif [[ "$i" = "publish" ]]; then
	    			GLB_PERF_URL="http://10.163.161.216/puffd/"
	    		elif [[ "$i" = "publishnode" ]]; then
	    			GLB_NODE_STATS=1
	    		elif [[ "$i" = "gutsstats" ]]; then
	    			doLogAnalyze="$doLogAnalyze gutsstats"
	    		elif [[ "$i" = "mrinfo" ]]; then
	    			doLogAnalyze="$doLogAnalyze mrinfo"
	    		elif [[ "$i" = "mrdbinfo" ]]; then
	    			doLogAnalyze="$doLogAnalyze mrdbinfo"
	    		elif [[ "$i" = "gwguts" ]]; then
	    			doGutsType="gw"
	    		elif [[ "$i" = "mossguts" ]]; then
	    			doGutsType="moss"
	    		elif [[ "$i" = "mastguts" ]]; then
	    			doGutsType="mast"
	    		elif [[ "$i" = "defaultguts" ]]; then
	    			doGutsDef=1
	    		elif [[ "$i" = "copycores" ]]; then
    				GLB_COPY_CORES=5
	    		elif [[ "$i" = "slack" ]]; then
    				GLB_SLACK_TRACE=1
    			fi
	    	done
		;;
		-dir)
			[ -n "$VALUE" ] && copydir="$VALUE"
		;;
		-ldrlog)
			[ -n "$VALUE" ] && logdrfile="$VALUE"
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
		-ge)
			[ -n "$VALUE" ] && GLB_GREP_EXCERPT="$VALUE"
		;;
		-geo)
			[ -n "$VALUE" ] && GLB_GREP_OCCURENCE="$VALUE"
		;;
		-td)
			if [ -n "$VALUE" ]; then
				doLogAnalyze="$doLogAnalyze tabletdist"
				GLB_TABLET_DIST=$VALUE
			fi
		;;
		-pt)
			if [ -n "$VALUE" ]; then
				doLogAnalyze="$doLogAnalyze perftool"
				GLB_PERF_OPTION=$VALUE
			fi
		;;
		-pi)
			if [ -n "$VALUE" ]; then
				GLB_PERF_INTERVAL=$VALUE
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
				[ -z "$GLB_PATCH_REPOFILE" ] && [ -n "$(echo ${useRepoURL} | grep "releases")" ] && GLB_PATCH_REPOFILE="$(echo ${useRepoURL} | sed 's/\(\/v[0-9].[0-9].[0-9]\)/\/patches\1/g')"
				[ -n "$GLB_PATCH_REPOFILE" ] && [ -z "$(echo ${GLB_PATCH_REPOFILE} | grep "releases-dev")" ] && GLB_PATCH_REPOFILE=$(echo $GLB_PATCH_REPOFILE | sed 's/\/releases\//\/releases-dev\//')
				#[ -z "$GLB_PATCH_REPOFILE" ] && GLB_PATCH_REPOFILE="${useRepoURL%?}-patch-EBF"
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
 		-aop)
			if [ -n "$VALUE" ]; then
 				GLB_ASAN_OPTIONS="$VALUE"
 			fi
		;;
		-mp)
			[ -n "$VALUE" ] && GLB_MINIO_PORT="$VALUE"
		;;
		-slhk)
			[ -n "$VALUE" ] && GLB_CUSTOM_SLACK="$VALUE"
 		;;
 		-extarg)
			if [ -n "$VALUE" ]; then
				GLB_EXT_ARGS=$VALUE
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

	if [ "${doMinIOInstall}" -eq 1 ]; then
		main_minioinstall
		doSkip=1
	elif [ "${doMinIOUninstall}" -eq 1 ]; then
		main_miniouninstall
		doSkip=1
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

