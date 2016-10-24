#!/bin/bash


################  
#
#   utilities
#
################

### START_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###

function getOSFromNode(){
    if [ -z "$1" ]; then
        return
    fi
    echo "$(ssh root@$1 lsb_release -a 2> /dev/null| grep Distributor | tr -d '\t' | tr '[:upper:]' '[:lower:]' | cut -d':' -f2 )"
}

function getOS(){
    echo "$(lsb_release -a 2> /dev/null| grep Distributor | tr -d '\t' | tr '[:upper:]' '[:lower:]' | cut -d':' -f2)"
}

function getOSWithVersion(){
    echo "$(lsb_release -a  2> /dev/null| grep 'Distributor\|Release' | tr -d ' ' | awk '{print $2}' | tr '\n' ' ')"
}

function util_getHostIP(){
    command -v ifconfig >/dev/null 2>&1 || util_installprereq
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
    if [ "$(getOS)" = "centos" ]; then
         yum repolist 2>&1 | grep epel || yum install epel-release -y >/dev/null 2>&1
    fi
    util_checkAndInstall "ifconfig" "net-tools"
    util_checkAndInstall "bzip2" "bzip2"
    util_checkAndInstall "screen" "screen"
    util_checkAndInstall "sshpass" "sshpass"
    util_checkAndInstall "vim" "vim"
    util_checkAndInstall "dstat" "dstat"
    util_checkAndInstall "iftop" "iftop"
    util_checkAndInstall "lsof" "lsof"
    util_checkAndInstall "bc" "bc"
    util_checkAndInstall "mpstat" "sysstat"
    util_checkAndInstall "lynx" "lynx"
    if [ "$(getOS)" = "centos" ]; then
        util_checkAndInstall "createrepo" "createrepo"
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        util_checkAndInstall "add-apt-repository" "python-software-properties"
        util_checkAndInstall "add-apt-repository" "software-properties-common"
        util_checkAndInstall "dpkg-scanpackages" "dpkg-dev"
        util_checkAndInstall "gzip" "gzip"
    fi

    util_checkAndInstall2 "/usr/share/dict/words" "words"
}

# @param ip_address_string
function util_validip(){
	local retval=$(ipcalc -cs $1 && echo valid || echo invalid)
	echo "$retval"
}

# @param ip_address_string
function util_validip2()
{
    local  ip=$1
    local  stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    if [ "$stat" -eq 1 ]; then
        echo "invalid"
    else
        echo "valid"
    fi
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
    local prefix=$3

    local newbins=
    for bin in $bins
    do
        local binexists=$(util_checkPackageExists $bin $version)
        if [ "$binexists" = "true" ]; then
            if [ -z "$newbins" ]; then
                newbins="$bin$prefix*$version*"
            else
                newbins=$newbins" $bin$prefix*$version*"
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
    local prefix=$3
    echo "[$(util_getHostIP)] Installing packages : $bins"
    if [ "$(getOS)" = "centos" ]; then
        if [ -n "$2" ]; then
            bins=$(util_appendVersionToPackage "$1" "$2" "$3")
        fi
        yum clean all > /dev/null 2>&1
        yum install ${bins} -y --nogpgcheck
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get update > /dev/null 2>&1
        apt-get install ${bins} -y --force-yes
    fi
}

# @param list of binaries
function util_upgradeBinaries(){
    if [ -z "$1" ]; then
        return
    fi
    local bins=$1
    echo "[$(util_getHostIP)] Upgrading packages : $bins"
    if [ "$(getOS)" = "centos" ]; then
        if [ -n "$2" ]; then
            bins=$(util_appendVersionToPackage "$1" "$2")
        fi
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
    [ -z "$rembins" ] && return

    echo "[$(util_getHostIP)] Removing packages : $rembins"
    if [ "$(getOS)" = "centos" ]; then
        rpm -ef $rembins > /dev/null 2>&1
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get autoremove --purge $rembins
        dpkg --purge $rembins > /dev/null 2>&1
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
    local defdisks=$(util_getDefaultDisks)
    sfdisk -l 2> /dev/null| grep Disk | tr -d ':' | cut -d' ' -f2 | grep -v -f /tmp/defdisks | sort > /tmp/disklist
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
            bash -c "ps aux | grep '$esckey' | sed -n 's/ \+/ /gp' | cut -d' ' -f2 | xargs kill -9" > /dev/null 2>&1
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
      local eline=$(awk '/END_OF_FUNCTIONS/{a=NR}END{print a}' $file)
      if [ -z "$eline" ]; then
        tail -n +$sline $file >> $script
      else
        sed -n ${sline},${eline}p ${file} >> $script
      fi
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
    >&2 echo "Error on or near line ${parent_lineno}: ${message}; exiting with status ${code}"
  else
    >&2 echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
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
        i=$(echo $i | tr -d ' ')
        local node=$(echo $i | awk 'BEGIN {FS="],"} {print $1}')
        if [ -n "$(echo $node | grep '\[')" ]; then
            # Get the start and end index from the string in b/w '[' & ']' 
            local bins=$(echo $i | awk 'BEGIN {FS="],"} {print $2}')
            local prefix=$(echo $node | cut -d'[' -f1)
            local suffix=$(echo $node | cut -d'[' -f2 | tr -d ']')
            # Check if suffix has ',' separated list
            local ranges=$(echo $suffix | tr ',' ' ')
            for range in $ranges
            do
                local startidx=$(echo $range | cut -d'-' -f1)
                local endidx=$(echo $range | cut -d'-' -f2)
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
            done
        else
            node=$(echo $i | cut -d',' -f1)
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

# @param total number of sectors
# @param sector start position
function util_getHDTrimList(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local MAXSECT=65535
    local sectors=$1
    local pos=$2
    while test $sectors -gt 0; do
        if test $sectors -gt $MAXSECT; then
                size=$MAXSECT
        else
                size=$sectors
        fi
        echo $pos:$size
        sectors=$(($sectors-$size))
        pos=$(($pos+$size))
    done
}

# @param disk (ex: /dev/sda)
function util_isSSDDrive(){
    if [ -z "$1" ]; then
        return
    fi

    local disk=$1
    disk=$(echo "$disk"| grep -v -e '^$' | cut -d' ' -f1 | cut -d'/' -f3)
    [ "$(cat /sys/block/$disk/queue/rotational)" -eq 0 ] && echo "yes" || echo "no"
}

# @param disk (ex: /dev/sda)
function util_getMaxDiskSectors(){
    if [ -z "$1" ]; then
        return
    fi

    echo "$(hdparm -I $1 | grep LBA48 | awk '{print $5}')"
}

# @param list of disks
function util_trimSSDDrives(){
    if [ -z "$1" ]; then
        return
    fi
    local disks="$1"
    for disk in $disks
    do
        [ "$(util_isSSDDrive $disk)" = "no" ] && echo "Disk [$disk] is NOT a SSD drive" && continue
        local maxsectors=$(util_getMaxDiskSectors $disk)
        local trimlist=$(util_getHDTrimList $maxsectors 1)
        nohup echo "$trimlist" | hdparm --trim-sector-ranges-stdin ${disk} > /dev/null 2>&1 &
    done
    wait
}

function util_getCPUInfo(){
    local ht=$(lscpu | grep 'Thread(s) per core' | cut -d':' -f2 | tr -d ' ')
    if [[ "$ht" -ne 1 ]]; then
        ht="Enabled ($ht)"
    else
        ht="Disabled ($ht)"
    fi
    local numcores=$(nproc)
    local numnuma=$(lscpu | grep 'NUMA' | cut -d':' -f2 | tr -d ' ' | head -1)
    local numacpus=
    while read -r line
    do
        if [ -z "$numacpus" ]; then
            numacpus="$line"
        else
            numacpus=$numacpus", $line"
        fi
    done <<<"$(lscpu | grep 'NUMA' | grep 'CPU(s)' | awk '{print $2": "$4}')"
    
    echo "CPU Info : "
    echo -e "\t # of cores  : $numcores"
    echo -e "\t HyperThread : $ht"
    echo -e "\t # of numa   : "$numnuma
    if [[ "$numnuma" -gt 1 ]]; then
        echo -e "\t numa cpus   : $numacpus"
    fi
}

function util_getMemInfo(){
    local mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local memgb=$(echo "$mem/1024/1024" | bc)
    echo "Memory Info : "
    echo -e "\t Memory : $memgb GB"
    
}

function util_getNetInfo(){
    local nics="$(ip link show | grep BROADCAST | grep UP | tr -d ':' | awk '{print $2}')"
    echo "Network Info : "
    for nic in $nics
    do
        local ip=$(ip -4 addr show $nic | grep -oP "(?<=inet).*(?=/)" | tr -d ' ')
	    [ -z "$ip" ] && continue
        local mtu=$(cat /sys/class/net/$nic/mtu)
        local speed=$(cat /sys/class/net/${nic}/speed)
        speed=$(echo "$speed/1000" | bc)
        local numa=$(cat /sys/class/net/$nic/device/numa_node)
        local cpulist=$(cat /sys/class/net/$nic/device/local_cpulist)
        echo -e "\t NIC: $nic, MTU: $mtu, IP: $ip, Speed: ${speed}GbE, NUMA: $numa (cpus: $cpulist)"
    done
}

function util_getDiskInfo(){
    local fd=$(fdisk -l 2>/dev/null)
    local disks=$(echo "$fd"| grep "Disk \/" | grep -v mapper | sort | grep -v "\/dev\/md" | awk '{print $2}' | sed -e 's/://g')
    local numdisks=$(echo "$disks" | wc -l)
    echo "Disk Info : [ #ofdisks: $numdisks ]"

    for disk in $disks
    do
        local blk=$(echo $disk | cut -d'/' -f3)
        local size=$(echo "$fd" | grep "Disk \/" | grep "$disk" | tr -d ':' | awk '{print $3}')
        local dtype=$(cat /sys/block/$blk/queue/rotational)
        local isos=$(echo "$fd" |  grep -wA6 "$disk" | grep "Disk identifier" | awk '{print $3}')
        if [ "$dtype" -eq 0 ]; then
            dtype="SSD"
        else
            dtype="HDD"
        fi
        if [ -n "$isos" ]; then
            local dival=$(printf "%d\n" $isos)
            if [[ "$dival" -ne 0 ]]; then
                isos="[ OS ]"
            else
                isos=
            fi
        fi
        echo -e "\t $disk : Type: $dtype, Size: ${size} GB $isos"
    done
}

function util_getMachineInfo(){
    echo "Machine Info : "
    echo -e "\t Hostname : $(hostname -f)"
    echo -e "\t OS       : $(getOSWithVersion)"
    command -v mpstat >/dev/null 2>&1 && echo -e "\t Kernel   : $(mpstat | head -n1 | awk '{print $1,$2}')"
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

### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
