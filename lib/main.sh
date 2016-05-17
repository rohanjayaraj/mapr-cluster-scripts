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
			echo "Role file specified doesn't exist. Scooting!"
			exit 1
		fi
	fi
fi

# Fetch the nodes to be configured
echo "Using cluster coniguration file : $rolefile "
nodes=$(maprutil_getNodesFromRole $rolefile)

if [ -z "$nodes" ]; then
	echo "Unable to get the list of nodes. Scooting!"
	exit 1
fi

# Check if current user is root
if [ "$(util_isUserRoot)" = "false" ]; then
	echo "Please run the script as root user. Scooting!"
	exit 1
#else
#	echo "Executing as user 'root'"
fi

# Check if ssh key generated on the executor machine
keyexists=$(util_fileExists "/root/.ssh/id_rsa")
if [ -z "$keyexists" ]; then
	echo "SSH key is missing. Creating..."
	ssh_createkey "/root/.ssh"
#else
#	echo "SSH key exists"
fi

# Install sshpass if not already there
ssh_installsshpass

# Check if SSH is configured
#echo "Checking Key-based authentication to all nodes listed... "
for node in ${nodes[@]}
do
	isEnabled=$(ssh_check "root" "$node")
	if [ "$isEnabled" != "enabled" ]; then
		echo "Configuring key-based authentication for the node $node (enter password once)"
		ssh_copyPrivateKey "root" "$node"
	fi
done

# Global Variables
GLB_CLUSTER_NAME="archerx"
GLB_MULTI_MFS=

############################### ALL functions to be defined below this ###############################

function main_install(){
	#set -x
	# Warn user 
	echo
	echo "Installing MapR on the following N-O-D-E-S : "
	local i=1
	for node in ${nodes[@]}
	do
		echo "Node$i : $node"
		let i=i+1
	done

	echo
    read -p "Press 'y' to confirm... " -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    	echo
    	echo "Abandoning install! "
        return 1
    else
    	echo
    fi

    echo
	# Check if MapR is already installed on any of the nodes
	local islist=
	for node in ${nodes[@]}
	do
		local isInstalled=$(maprutil_isMapRInstalledOnNode "$node")
		if [ "$isInstalled" = "true" ]; then
			islist=$islist"$node"" "
		fi
	done

	if [ -n "$islist" ]; then
		echo "MapR is already installed on the node(s) [ $islist] or some stale binaries are still present. Scooting!"
		exit 1
	fi

	# Read properties
	local clustername=$GLB_CLUSTER_NAME

	# Install required binaries on other nodes
	local maprrepo=$repodir"/mapr.repo"
	for node in ${nodes[@]}
	do
		# Copy mapr.repo if it doen't exist
		maprutil_copyRepoFile "$node" "$maprrepo"

		local nodebins=$(maprutil_getNodeBinaries "$rolefile" "$node")
		maprutil_installBinariesOnNode "$node" "$nodebins" "bg"
		sleep 2
		
	done
	wait

	# Configure all nodes
	for node in ${nodes[@]}
	do
		maprutil_configureNode "$node" "$rolefile" "$clustername" "bg"
		sleep 2
	done
	wait

	# Configure all nodes
	for node in ${nodes[@]}
	do
		maprutil_restartWardenOnNode "$node" &
	done
	wait

	# Perform custom executions

	#set +x

}

function main_uninstall(){

	# Warn user 
	echo
	echo "Uninstalling MapR on the following N-O-D-E-S : "
	local i=1
	for node in ${nodes[@]}
	do
		echo "Node$i : $node"
		let i=i+1
	done

	echo
    read -p "Press 'y' to confirm... " -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    	echo
    	echo "Uninstall C-A-N-C-E-L-L-E-D! "
        return 1
    else
    	echo
    fi
    
    echo
	# Check if MapR is installed on all nodes
	local notlist=
	for node in ${nodes[@]}
	do
		local isInstalled=$(maprutil_isMapRInstalledOnNode "$node")
		if [ "$isInstalled" != "true" ]; then
			notlist=$notlist"$node"" "
		else
			echo "MapR is installed on node [$node]"
		fi
	done

	if [ -n "$notlist" ]; then
		echo "MapR not installed on the node(s) [ $notlist]. Scooting!"
		exit 1
	fi

	local cldbnode=
	local nocldblist=
	# Check if each node points to the same CLDB master and the master is part of the cluster
	for node in ${nodes[@]}
	do
		local cldbhost=$(maprutil_getCLDBMasterNode "$node")
		if [ -z "$cldbhost" ]; then
			echo " Unable to identifiy CLDB master on node [$node]"
			nocldblist=$nocldblist$node" "
		else
			local cldbip=$(util_getIPfromHostName "$cldbhost")
			local isone="false"
			for nd in ${nodes[@]}
			do
				if [ "$nd" = "$cldbip" ]; then
					isone="true"
					break
				fi
			done
			if [ "$isone" = "false" ]; then
				echo " Node [$node] is not part of the same cluster. Scooting"
				exit 1
			else
				cldbnode="$cldbip"
			fi
		fi
	done

	if [ -n "$nocldblist" ]; then
		echo "{WARNING} CLDB not found on nodes [$nocldblist]. May be uninstalling another cluster's nodes."
		read -p "Press 'y' to confirm... " -n 1 -r
	    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	    	echo "Over & Out!"
	    	return
	    fi
	else
		echo "CLDB Master : $cldbnode"
	fi

	# Start MapR Unistall for each node
	local hostip=$(util_getHostIP)
	local dohost="false"
	for node in ${nodes[@]}
	do	
    	if [ "$hostip" != "$node" ]; then
			maprutil_uninstallNode "$node"
		else
			dohost="true"
		fi
	done
	
	# Run uninstall on the host node at the end
	if [ "$dohost" = "true" ]; then
		maprutil_uninstallNode "$hostip"
	fi

	wait

	echo "Uninstall is complete!"
}

function main_createYCSBVolume () {
	maprcli volume create -name tables -path /tables -replication 3 -topology /data
	hadoop mfs -setcompression off /tables
}

function main_createTableWithCompression(){
	main_createYCSBVolume
	maprcli table create -path /tables/usertable
	maprcli table cf create -path /tables/usertable -cfname family -compression lz4 -maxversions 1
}

function main_usage () {
	local me=$(basename $BASH_SOURCE)
	echo 
	echo "Usage : "
    echo "./$me CONFIG_NAME [Options]"
    echo " Options : "
    echo -e "\t -h --help"
    echo -e "\t\t - Print this"
    echo 
    echo -e "\t install" 
    echo -e "\t\t - Install cluster"
    echo -e "\t uninstall " 
    echo -e "\t\t - Uninstall cluster"
    echo 
    
}

doInstall=0
doUninstall=0
doYCSBVolCreate=0
doTableCreate=0

while [ "$2" != "" ]; do
	OPTION=`echo $2 | awk -F= '{print $1}'`
    VALUE=`echo $2 | awk -F= '{print $2}'`
    #echo "OPTION : $OPTION; VALUE : $VALUE"
    case $OPTION in
        h | help)
            main_usage
            exit
        ;;
    	install)
    		doInstall=1
    	;;
    	uninstall)
    		doUninstall=1
    	;;
    	-e)
			for i in ${VALUE}; do
				#echo " extra option : $i"
				if [ "$i" = "ycsb" ]; then
    				doYCSBVolCreate=1
    			elif [[ "$i" = "tablecreate" ]]; then
    				doTableCreate=1
    			fi
    		done
    	;;
    	-c)
			if [ -n "$VALUE" ]; then
    			GLB_CLUSTER_NAME=$VALUE
    		fi
    	;;
    	-m)
			if [ -n "$VALUE" ]; then
    			GLB_MULTI_MFS=$VALUE
    		fi
    	;;
        *)
            echo "ERROR: unknown option \"$OPTION\""
            main_usage
            exit 1
            ;;
    esac
    shift
done

if [ "$doInstall" -eq 1 ]; then
	echo " *************** Starting Cluster Installation **************** "
	main_install
elif [ "$doUninstall" -eq 1 ]; then
	echo " *************** Starting Cluster Uninstallation **************** "
	main_uninstall
fi

exitcode=`echo $?`
if [ "$exitcode" -ne 0 ]; then
	#echo "exiting with exit code $exitcode"
	exit
fi

if [ "$doYCSBVolCreate" -eq 1 ]; then
	echo " *************** Creating YCSB Volume **************** "
	main_createYCSBVolume
fi
if [ "$doTableCreate" -eq 1 ]; then
	echo " *************** Creating UserTable (/tables/usertable) **************** "
	main_createTableWithCompression
fi
#echo "Completed!"