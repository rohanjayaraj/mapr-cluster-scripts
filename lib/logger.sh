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
	printf "\033[1;34m %s \033[0m" $msg && echo
}

# @param logmessage
function log_msghead(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	printf "\033[1;96m %s \033[0m" $msg && echo
}

# @param logmessage
function log_info(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	printf "\033[36m [INFO] %s \033[0m" $msg && echo
}

# @param logmessage
function log_warn(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	printf "\033[33m [WARN] %s \033[0m" $msg && echo
}

# @param logmessage
function log_error(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	>&2 printf "\033[31m [ERROR] %s \033[0m" $msg && echo
}

# @param logmessage
function log_critical(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	>&2 printf "\033[1;41m [ERROR] %s \033[0m" $msg && echo
}

# @param logmessage
function log_success(){
	if [ -z "$1" ]; then
		return
	fi
	local msg=$1
	printf "\033[1;32m [INFO] %s \033[0m" $msg && echo
}


### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
