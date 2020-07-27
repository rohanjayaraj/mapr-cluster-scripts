#!/bin/bash


################  
#
#   ssh utilities
#
################

### START_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###

# @param user
# @param ip
function ssh_check(){
	if [ -z "$1" ] || [ -z "$2" ]; then
		return 1
	fi
	
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no -l $1 $2 exit >/dev/null 2>&1
	local retval=$?
	if [ "$retval" = 0 ]; then
		echo "enabled"
	else
		echo "disabled"
	fi
}

function ssh_checkSSHonNodes(){
	if [ -z "$1" ]; then
		return 1
	fi
	# Check if SSH is configured
	local tempdir=$(mktemp -d)
	local sshnodes="$1"
	for node in ${sshnodes[@]}
	do
		local nodefile="$tempdir/$node.log"
		ssh_check "root" "$node" > $nodefile &
	done
	wait
	local allgood=$(find $tempdir -type f | xargs grep disabled)
	if [ -n "$allgood" ]; then
		echo "false"
	fi
	rm -rf $tempdir > /dev/null 2>&1
}

# Install sshpass
function ssh_installsshpass(){
	command -v sshpass >/dev/null 2>&1 || yum install sshpass -y -q --enablerepo=epel 2>/dev/null || apt-get install sshpass -y 2>/dev/null
}

# @param user
# @param host ip
# @param command to execute
function ssh_executeCommand(){
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		return 1
	fi
	
	local retval=$(ssh $1@$2 "$3")
	echo "$retval"
}

# @param user
# @param host ip
# @param local file/dir to copy
# @param remote file/dir to copy
function ssh_copyCommand(){
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
		return 1
	fi
	local isdir=
	if [ -e "$3" ] && [ -d "$3" ]; then
		isdir="-r"
	fi
	
	local retval=$(scp $isdir $3 $1@$2:$4)
	echo "$retval"
}

# @param user
# @param host ip
# @param remote file/dir to copy
# @param local file/dir to copy
function ssh_copyFromCommandinBG(){
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
		return 1
	fi
	
	scp -r $1@$2:$3 $4 &
}

# @param user
# @param host ip
# @param remote file/dir to copy
# @param local file/dir to copy
function ssh_copyFromCommand(){
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
		return 1
	fi
	
	rsync -a $1@$2:$3 $4
}

# @param host ip
# @param local file/dir to copy
# @param remote file/dir to copy
function ssh_copyCommandasRoot(){
	ssh_copyCommand "root" "$1" "$2" "$3"
}

function ssh_executeCommandWithTimeout(){
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
		return 1
	fi
	
	local retval=$(timeout $4 ssh $1@$2 $3)
	echo "$retval"
}

# @param host ip
# @param command to execute
function ssh_executeCommandasRoot(){
	ssh_executeCommand "root" "$1" "$2"
}

# @param user
# @param host ip
# @param path to script
function ssh_executeScript(){
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		return 1
	fi
	
	local retval=$(ssh $1@$2 'bash -s' < $3)
	echo "$retval"
}

# @param host ip
# @param path to script
function ssh_executeScriptasRoot(){
	ssh_executeScript "root" "$1" "$2"
}

# @param user
# @param host ip
# @param path to script
function ssh_executeScriptInBG(){
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		return 1
	fi
	local logfile="$3.log"
	ssh $1@$2 'bash -s' < $3 | tee -a $logfile &
}

# @param host ip
# @param path to script
function ssh_executeScriptasRootInBG(){
	if [ -z "$1" ] || [ -z "$2" ]; then
		return 1
	fi
	local node=$1
	local script=$2
	local logfile="$script.log"

	ssh root@$node 'bash -s' < $script | tee -a $logfile &
}

# @param .ssh dir path
function ssh_createkey(){
	if [ -z "$1" ]; then
		echo "NULL path specified. "
		return 1
	fi

	local keydir="$1"
	local key="$keydir/id_rsa"
	if [ ! -e  "$key" ]; then
		if [ ! -d "$keydir" ]; then
			mkdir $keydir
		fi
		ssh-keygen -t rsa -N "" -f $key -m PEM -b 2048 > /dev/null 2>&1
	fi
}

# @param host user
# @param host ip
function ssh_copyPublicKey(){
	if [ -z "$1" ] || [ -z "$2" ]; then
		return 1
	fi
	ssh-keygen -R $2 >/dev/null 2>&1
	local rootpwd=${ROOTPWD}
	[ -n "$rootpwd" ] && rootpwd=$(echo "$rootpwd" | tr -d ' ' | tr ',' ' ') || rootpwd="mapr ssmssm"
	local isdone=
	for pwd in $rootpwd
	do
		sshpass -p${pwd} ssh -o StrictHostKeyChecking=no -l $1 $2 exit >/dev/null 2>&1
		local sshpassret=$?
		local idfile=
		[ "$(ls /root/.ssh/id_rsa*.pub | wc -l)" -gt "1" ] && [ -e "/root/.ssh/id_rsa.pub" ] && idfile="-i"
		if [ "$sshpassret" -eq 0 ]; then
			local sshpval=$(sshpass -p${pwd} ssh-copy-id $idfile $1@$2)
			local retval=$?
			if [ "$retval" != 0 ]; then
				cat /root/.ssh/id_rsa.pub | sshpass -p${pwd} ssh -l $1 $2 'umask 0077; mkdir -p .ssh; cat >> .ssh/authorized_keys && echo "Key copied"'
			fi
			isdone=1
			break
		fi
	done
	if [ -z "${isdone}" ]; then
		local sshpval=$(ssh-copy-id $idfile $1@$2)
		local retval=$?
		if [ "$retval" != 0 ]; then
			cat /root/.ssh/id_rsa.pub | ssh -l $1 $2 'umask 0077; mkdir -p .ssh; cat >> .ssh/authorized_keys && echo "Key copied"'
		fi
	fi
}

### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
