#!/bin/bash


################  
#
#   utilities
#
################
function getOSFromNode(){
    if [ -z "$1" ]; then
        return
    fi
    echo "$(ssh root@$1 lsb_release -a | grep Distributor | tr -d '\t' | tr '[:upper:]' '[:lower:]' | cut -d':' -f2 )"
}

function getOS(){
    echo "$(lsb_release -a | grep Distributor | tr -d '\t' | tr '[:upper:]' '[:lower:]' | cut -d':' -f2)"
}

function util_getHostIP(){
    command -v ifconfig >/dev/null 2>&1 || yum install net-tools -y -q 2>/dev/null
    local ipadd=$(/sbin/ifconfig | grep -e "inet:" -e "addr:" | grep -v "inet6" | grep -v "127.0.0.1" | head -n 1 | awk '{print $2}' | cut -c6-)
    if [ -z "$ipadd" ]; then
        ipadd=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
    fi
    if [ -z "$ipadd" ] && [ -n "$HOSTIP" ]; then
        ipadd=$HOSTIP
    fi
    echo "$ipadd"
}

# @param ip_address_string
function util_validip(){
	local retval=$(ipcalc -cs $1 && echo valid || echo invalid)
	echo "$retval"
}

# @param searchkey
function util_getInstalledBinaries(){
    if [ -z "$1" ]; then
        return
    fi

    if [ "$(getOS)" = "centos" ]; then
        echo $(rpm -qa | grep $1 | awk '{split ($0, a, "-0"); print a[1]}' | sed ':a;N;$!ba;s/\n/ /g')
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        echo $(dpkg -l | grep $1 | awk '{print $2}' | sed ':a;N;$!ba;s/\n/ /g')
    fi
}

# @param list of binaries
function util_installBinaries(){
    if [ -z "$1" ]; then
        return
    fi
    local bins=$1
    echo "[$(util_getHostIP)] Installing packages : $bins"
    if [ "$(getOS)" = "centos" ]; then
        yum clean all
        yum install ${bins} -y --nogpgcheck
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get update
        apt-get install ${bins} -y --force-yes
    fi
}

# @param searchkey
function util_removeBinaries(){
    if [ -z "$1" ]; then
        return
    fi
    bins=$(util_getInstalledBinaries $1)
    echo "[$(util_getHostIP)] Removing packages : $bins"
    if [ "$(getOS)" = "centos" ]; then
        rpm -ef $bins
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        dpkg -r $bins
    fi
}

function util_getDefaultDisks(){
    blkid | tr -d ':' | cut -d' ' -f1 | tr -d '[0-9]' | uniq | sort > /tmp/defdisks
    df -x tmpfs | grep -v : | cut -d' ' -f1 | sed -e /Filesystem/d |  sed '/^$/d' |  tr -d '[0-9]' >> /tmp/defdisks
    lsblk -nl | grep -v disk | cut -d' ' -f1  >> /tmp/defdisks
    echo $(cat /tmp/defdisks)
}

# returns space separated list of raw disks
function util_getRawDisks(){
    util_getDefaultDisks
    sfdisk -l | grep Disk | tr -d ':' | cut -d' ' -f2 | grep -v -f /tmp/defdisks | sort > /tmp/disklist
    echo $(cat /tmp/disklist)
}

## @param $1 process to kill
## @params $n process to ignore
function util_kill(){
    if [ -z "$1" ]; then
        return
    fi
    local i=0
    local ignore=
    while [  $i -lt "$#" ]; do
        if [ "$i" -eq 0 ]; then 
            let i=i+1  
            continue 
        else
            let i=i+1 
        fi
        if [ -z "$ignore" ]; then
            ignore="grep -vi \""$i"\""
        else
            ignore=$ignore"| grep -vi \""$i"\""
        fi
    done
    if [ -z "$ignore" ]; then
        ps aux | grep $1 | $ignore | sed -n 's/ \+/ /gp' | cut -d' ' -f2 | xargs kill -9 2>/dev/null
    else
        ps aux | grep $1 | sed -n 's/ \+/ /gp' | cut -d' ' -f2 | xargs kill -9 2>/dev/null
    fi
}

# @param directory containing shell scripts with functions
# @param path to copy
# @param script to ignore
function util_buildSingleScript(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return 1
    fi
    local script=$2
    truncate -s 0 $script
    echo '#!/bin/bash \n' >> $script
    echo "###########################################" >> $script
    echo "#" >> $script
    echo "#              The RING! " >> $script
    echo "#" >> $script
    echo "########################################### \n" >> $script
    
    local ignore=$3
    for file in "$1"/*.sh
    do
      if [[ -n "$ignore" ]] && [[ $srcfile == *"$ignore" ]]; then
        continue
      fi
      local sline=$(awk '/function/{ print NR; exit }' $file)
      tail -n +$sline $file >> $script
      echo >> $script
    done

    echo >> $script
    echo >> $script
    echo >> $script
    echo "HOSTIP=$3" >> $script
    return 0
}

# @param owner
function util_removeSHMSegments(){
    if [ -z "$1" ]; then
        return
    fi
    local shmlist=($(ipcs -m | grep -i $1 | cut -f 2 -d " " | grep ^[0-9]))
    for x in ${shmlist[@]}
    do
        ipcrm -m ${x}
    done
}

function util_errorHandler() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  if [[ -n "$message" ]] ; then
    echo "Error on or near line ${parent_lineno}: ${message}; exiting with status ${code}"
  else
    echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
  fi
  exit "${code}"
}

function util_setupTrap(){
    set -o pipefail  # trace ERR through pipes
    set -o errtrace  # trace ERR through 'time command' and other functions
    #set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
    set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

    #trap 'util_errorHandler ${LINENO}' ERR
    #trap 'util_errorHandler ${LINENO}' EXIT
}

# @param file path
function util_fileExists(){
    if [ -z "$1" ]; then
        return
    fi
    if [ -e "$1" ] && [ -f "$1" ]; then
        echo "exists"
    fi
}

# @param file path
function util_fileExists2(){
    if [ -z "$1" ]; then
        return
    fi
    local FILE=$1
    if [ -f "$FILE" ]; then
        echo "exists"
    else
        echo "$FILE doesn't"
    fi
}

function util_isUserRoot(){
    if [[ $EUID -eq 0 ]]; then
        echo "true" 
    else
        echo "false"
    fi
}

# @param string containing the sequence
function util_getStartEndSeq(){
    if [ -z "$1" ]; then
        return
    fi
    str=$1
    strlen=${#str}
    if [[ "$str" = *[* ]] && [[ "$str" = *] ]]; then
        local bidx=`expr index "$str" "["`
        local prefix=
        if [ "$bidx" -ne 1 ]; then
            prefix=${str:0:$bidx-1}
        fi
        local hidx=`expr index "$str" "-"`
        local start=$prefix${str:$bidx:$hidx-$bidx-1}
        local end=$prefix${str:$hidx:$strlen-$hidx-1}
        echo "$start,$end"
    fi
}

# @param space separated string values
function util_getFirstElement(){
    if [ -z "$1" ]; then
        return
    fi
    local vals=$1
    for val in ${vals[@]}
    do
        echo "$val"
        return
    done
    echo "$vals"
}

# @param space separated string values
function util_getCommaSeparated(){
    if [ -z "$1" ]; then
        return
    fi
    local retval=
    local vals=$1
    for val in ${vals[@]}
    do
        if [ -z "$retval" ]; then
            retval=$val
        else
            retval=$retval","$val
        fi
    done
    if [ -z "$retval" ]; then
        retval=$vals
    fi
    echo "$retval"
}



# @param host name with domin
function util_getIPfromHostName(){
    if [ -z "$1" ]; then
        return
    fi
    local ip=$(ping -c 1 $1 | awk -F'[()]' '/PING/{print $2}')
    if [ "$(util_validip "$ip")" = "valid" ]; then
        echo $ip
    fi
}

