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
        ipadd=$(ip addr | grep 'state UP' -A2 | head -n 3 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
    fi
    if [ -z "$ipadd" ] && [ -n "$HOSTIP" ]; then
        ipadd=$HOSTIP
    fi
    echo "$ipadd"
}

function util_getCurDate(){
    echo "$(date +'%Y-%m-%d %H:%M:%S')"
}

# @param command
# @param package
function util_checkAndInstall(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    if [ "$(getOS)" = "centos" ]; then
        command -v $1 >/dev/null 2>&1 || yum install $2 -y -q 2>/dev/null
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        command -v $1 >/dev/null 2>&1 || apt-get install $2 -y 2>/dev/null
    fi
}


# @param command
# @param package
function util_checkAndInstall2(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    if [ "$(getOS)" = "centos" ]; then
        if [ ! -e "$1" ]; then
            yum install $2 -y -q 2>/dev/null
        fi
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        if [ ! -e "$1" ]; then
            apt-get install $2 -y 2>/dev/null
        fi
    fi
}

function util_installprereq(){
   
    util_checkAndInstall "ifconfig" "net-tools"
    util_checkAndInstall "bzip2" "bzip2"
    util_checkAndInstall "screen" "screen"
    util_checkAndInstall "sshpass" "sshpass"
    util_checkAndInstall "vim" "vim"
    util_checkAndInstall "dstat" "dstat"
    util_checkAndInstall "iftop" "iftop"
    util_checkAndInstall "lsof" "lsof"
    if [ "$(getOS)" = "centos" ]; then
        util_checkAndInstall "createrepo" "createrepo"
    fi

    util_checkAndInstall2 "/usr/share/dict/words" "words"
}

# @param ip_address_string
function util_validip(){
	local retval=$(ipcalc -cs $1 && echo valid || echo invalid)
	echo "$retval"
}

# @param packagename
# @param verion number
function util_checkPackageExists(){
     if [ -z "$1" ] || [ -z "$2" ] ; then
        return
    fi
     if [ "$(getOS)" = "centos" ]; then
        yum --showduplicates list $1 | grep $2 1> /dev/null && echo "true" || echo "false"
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-cache policy $1 | grep $2 1> /dev/null && echo "true" || echo "false"
    fi
   
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

function util_appendVersionToPackage(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local bins=$1
    local version=$2

    local newbins=
    for bin in $bins
    do
        local binexists=$(util_checkPackageExists $bin $version)
        if [ "$binexists" = "true" ]; then
            if [ -z "$newbins" ]; then
                newbins="$bin*$version*"
            else
                newbins=$newbins" $bin*$version*"
            fi
        else
            if [ -z "$newbins" ]; then
                newbins="$bin"
            else
                newbins=$newbins" $bin"
            fi
        fi
    done
    echo "$newbins"
}

# @param list of binaries
function util_installBinaries(){
    if [ -z "$1" ]; then
        return
    fi
    local bins=$1
    if [ -n "$2" ]; then
        bins=$(util_appendVersionToPackage "$1" "$2")
    fi
    echo "[$(util_getHostIP)] Installing packages : $bins"
    if [ "$(getOS)" = "centos" ]; then
        yum clean all
        yum install ${bins} -y --nogpgcheck
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get update
        apt-get install ${bins} -y --force-yes
    fi
}

# @param list of binaries
function util_upgradeBinaries(){
    if [ -z "$1" ]; then
        return
    fi
    local bins=$1
    if [ -n "$2" ]; then
        bins=$(util_appendVersionToPackage "$1" "$2")
    fi
    echo "[$(util_getHostIP)] Upgrading packages : $bins"
    if [ "$(getOS)" = "centos" ]; then
        yum clean all
        yum update ${bins} -y --nogpgcheck
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get update
        apt-get upgrade ${bins} -y --force-yes
    fi
}

# @param searchkey
function util_removeBinaries(){
    if [ -z "$1" ]; then
        return
    fi
    rembins=$(util_getInstalledBinaries $1)
    echo "[$(util_getHostIP)] Removing packages : $rembins"
    if [ "$(getOS)" = "centos" ]; then
        rpm -ef $rembins
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        dpkg -r $rembins
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
    local key=$1
    local i=0
    local ignore=
    while [ "$1" != "" ]; do
        if [ "$i" -eq 0 ]; then 
            let i=i+1
            shift  
            continue 
        else
            let i=i+1 
        fi
        local ig=$1
        if [ -z "$ignore" ]; then
            ignore="grep -vi \""$ig"\""
        else
            ignore=$ignore"| grep -vi \""$ig"\""
        fi
        shift
    done
    local esckey="[${key:0:1}]${key:1}"
    if [ -n "$(ps aux | grep $esckey)" ]; then
        if [ -n "$ignore" ]; then
            bash -c "ps aux | grep '$esckey' | $ignore | sed -n 's/ \+/ /gp' | cut -d' ' -f2 | xargs kill -9" > /dev/null 2>&1
        else
            ps aux | grep '$esckey' | sed -n 's/ \+/ /gp' | cut -d' ' -f2 | xargs kill -9 > /dev/null 2>&1
        fi
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

# @param string 
function util_isNumber(){
    if [ -z "$1" ]; then
        return
    fi
    local reg='^[0-9]+$'
    if ! [[ $1 =~ $reg ]] ; then    
        echo "false" 
    else
        echo "true"
    fi
}

# @param rolefile path
function util_expandNodeList(){
    if [ -z "$1" ]; then
        return
    fi
    local rolefile=$1
    local newrolefile="$rolefile.tmp"
    [ -e "$newrolefile" ] && rm -f $newrolefile > /dev/null 2>&1
    local nodes=
    for i in $(cat $rolefile | grep '^[^#;]'); do
        local node=$(echo $i | cut -f1 -d",")
        if [ -n "$(echo $node | grep '\[')" ]; then
            # Get the start and end index from the string in b/w '[' & ']' 
            local bins=$(echo $i | cut -f2- -d",")
            local prefix=$(echo $node | cut -d'[' -f1)
            local suffix=$(echo $node | cut -d'[' -f2 | tr -d ']')
            local startidx=$(echo $suffix | cut -d'-' -f1)
            local endidx=$(echo $suffix | cut -d'-' -f2)
            for j in $(seq $startidx $endidx)
            do
                local nodeip="$prefix$j"
                local isvalid=$(util_validip $nodeip)
                if [ "$isvalid" = "valid" ]; then
                    echo "$nodeip,$bins" >> $newrolefile
                else
                    echo "Invalid IP [$node]. Scooting"
                    exit 1
                fi
            done
        else
            local isvalid=$(util_validip $node)
            if [ "$isvalid" = "valid" ]; then
                echo "$i" >> $newrolefile
            else
                echo "Invalid IP [$node]. Scooting"
                exit 1
            fi
        fi
    done
    echo $newrolefile
}

#  @param keyword
function util_grepFiles(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    local dirpath=$1
    local filereg=$2
    local runcmd="for i in \$(find $dirpath -type f -name '$filereg'); do "
    local i=0
    for key in "$@"
    do
        if [ "$i" -lt 2 ]; then
            let i=i+1
            continue
        fi
        if [ "$i" -gt 2 ]; then
            runcmd=$runcmd" | grep '$key'"
        else
            runcmd=$runcmd" grep '$key' \$i"
        fi
        let i=i+1
    done
    runcmd=$runcmd"; done"

    local retstat=$(bash -c "$runcmd")
    local cnt=$(echo "$retstat" | wc -l)
    if [ -n "$retstat" ] && [ -n "$cnt" ]; then
        echo -e "\tSearchkey(s) found $cnt times in directory $node"
        echo -e "\t\t$retstat" | head -n 2
    fi
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

