#!/bin/bash


################  
#
#   ssh utilities
#
################

# @param user
# @param ip
function ssh_check(){
	if [ -z "$1" ] || [ -z "$2" ]; then
		return 1
	fi
	
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no -l $1 $2 exit
	local retval=$?
	if [ "$retval" = 0 ]; then
		echo "enabled"
	else
		echo "disabled"
	fi
}

# Install sshpass
function ssh_installsshpass(){
	command -v sshpass >/dev/null 2>&1 || yum install sshpass -y -q 2>/dev/null
}

# @param user
# @param host ip
# @param command to execute
function ssh_executeCommand(){
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		return 1
	fi
	
	local retval=$(ssh $1@$2 $3)
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
	
	ssh $1@$2 'bash -s' < $3 &
}

# @param host ip
# @param path to script
function ssh_executeScriptasRootInBG(){
	if [ -z "$1" ] || [ -z "$2" ]; then
		return 1
	fi
	
	ssh root@$1 'bash -s' < $2 &
	
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
		ssh-keygen -t rsa -N "" -f $key 2>/dev/null
	fi
}

# @param host user
# @param host ip
function ssh_copyPrivateKey(){
	if [ -z "$1" ] || [ -z "$2" ]; then
		return 1
	fi
	sshpass -pmapr ssh -o StrictHostKeyChecking=no -l $1 $2 exit
	local sshpassret=$?
	if [ "$sshpassret" -eq 0 ]; then
		local sshpval=$(sshpass -pmapr ssh-copy-id $1@$2)
		local retval=$?
		if [ "$retval" != 0 ]; then
			cat /root/.ssh/id_rsa.pub | sshpass -pmapr ssh -l $1 $2 'umask 0077; mkdir -p .ssh; cat >> .ssh/authorized_keys && echo "Key copied"'
		fi
	else
		local sshpval=$(ssh-copy-id $1@$2)
		local retval=$?
		if [ "$retval" != 0 ]; then
			cat /root/.ssh/id_rsa.pub | ssh -l $1 $2 'umask 0077; mkdir -p .ssh; cat >> .ssh/authorized_keys && echo "Key copied"'
		fi
	fi
}
