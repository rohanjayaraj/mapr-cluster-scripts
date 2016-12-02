#!/bin/bash


################  
#
#   logging utilities
#
################

### START_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###

# @param logmessage
function log_msg(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	echo -e "\033[1;34m $msg \033[0m"
}

# @param logmessage
function log_msghead(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$(echo "$1" | tr '\n' ' ')
	echo -e "\033[1;96m $msg \033[0m"
}

# @param logmessage
function log_info(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	echo -e "\033[36m [INFO] $msg \033[0m"
}

# @param logmessage
function log_warn(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	echo -e "\033[33m [WARN] $msg \033[0m"
}

# @param logmessage
function log_error(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	>&2 echo -e "\033[31m [ERROR] $msg \033[0m"
}

# @param logmessage
function log_critical(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	>&2 echo -e "\033[1;41m [ERROR] $msg \033[0m"
}

# @param logmessage
function log_success(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	echo -e "\033[1;32m [INFO] $msg \033[0m"
}


### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
