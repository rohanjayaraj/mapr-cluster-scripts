#!/bin/bash


################  
#
#   Main Script
#
################

basedir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
#echo "BASEDIR : $basedir"
isLibDir=${basedir:(-4)}
#echo "isLibDir : $isLibDir"
if [ "$isLibDir" = "/lib" ]; then
	basedirlen=${#basedir}
	len=`expr $basedirlen - 4`
	basedir=${basedir:0:$len}
fi
echo "BASEDIR : $basedir"

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
# first check $1 file exists
rolefile=$rolesdir"/"$1
if [ -z "$(util_fileExists $rolefile)" ]; then
	rolefile=$rolesdir"/mapr_roles."$1
	if [ -z "$(util_fileExists $rolefile)" ]; then
		echo "Role file specified doesn't exist. Scooting!"
		exit 1
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


############################### ALL functions to be defined below this ###############################

function main_install(){
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
        return
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

	# Copy mapr.repo if it doen't exist


	# Read properties
	local clustername="archerx"

	# Identify CLDB Master
	#local cldbnode=$(util_getFirstElement "$(maprutil_getCLDBNodes "$rolefile")")

	#echo "CLDB Node : $cldbnode"

	# Install MapR on CLDB Node
	#local cldbbins=$(maprutil_getNodeBinaries "$rolefile" "$cldbnode")
	#maprutil_installBinariesOnNode "$cldbnode" "$cldbbins"
	#maprutil_configureNode "$cldbnode" "$rolefile" "$clustername"

	# Install required binaries on other nodes
	for node in ${nodes[@]}
	do
		#if [ "$node" != "$cldbnode" ]; then
			local nodebins=$(maprutil_getNodeBinaries "$rolefile" "$node")
			maprutil_installBinariesOnNode "$node" "$nodebins" "bg"
			sleep 2
		#fi
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


	# Execute post install script 

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
        return
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
	# Check if each node points to the same CLDB master and the master is part of the cluster
	for node in ${nodes[@]}
	do
		local cldbhost=$(maprutil_getCLDBMasterNode "$node")
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
			#exit 1
		else
			cldbnode="$cldbip"
		fi
	done

	echo "CLDB Master : $cldbnode"

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

while [ "$2" != "" ]; do
    OPTION=`echo $2`
    case $OPTION in
        h | help)
            main_usage
            exit
            ;;
    	install)
    		main_install
    	;;
    	uninstall)
    		main_uninstall
    	;;
        *)
            echo "ERROR: unknown option \"$OPTION\""
            main_usage
            exit 1
            ;;
    esac
    shift
done

#echo "Completed!"