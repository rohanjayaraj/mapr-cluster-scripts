#!/bin/bash


################  
#
#   utilities
#
################

lib_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$lib_dir/logger.sh"

### START_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###

function getOSFromNode(){
    if [ -z "$1" ]; then
        return
    fi
    local osstr="$(ssh root@$1 lsb_release -a 2> /dev/null| grep Distributor | tr -d '\t' | tr '[:upper:]' '[:lower:]' | cut -d':' -f2 )"
    if [ -n "$(echo $osstr | grep -i redhat)" ]; then
        echo "centos"
    else 
        echo "$osstr"
    fi
}

function getOS(){
    local osstr="$(lsb_release -a 2> /dev/null| grep Distributor | tr -d '\t' | tr '[:upper:]' '[:lower:]' | cut -d':' -f2)"
    if [ -n "$(echo $osstr | grep -i redhat)" ]; then
        echo "centos"
    else 
        echo "$osstr"
    fi
}

function getOSWithVersion(){
    echo "$(lsb_release -a  2> /dev/null| grep 'Distributor\|Release' | tr -d ' ' | awk '{print $2}' | tr '\n' ' ')"
}

function util_getHostIP(){
    command -v ifconfig >/dev/null 2>&1 || util_installprereq > /dev/null 2>&1
    local ipadd=$(ifconfig | grep -e "inet:" -e "addr:" | grep -v "inet6" | grep -v "127.0.0.1\|0.0.0.0" | head -n 1 | awk '{print $2}' | cut -c6-)
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
        command -v $1 >/dev/null 2>&1 || yum --enablerepo=C6*,C7*,base,epel,epel-release install $2 -y -q 2>/dev/null
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        command -v $1 >/dev/null 2>&1 || apt-get -y install $2 2>/dev/null
    elif [[ "$(getOS)" = "suse" ]]; then
        command -v $1 >/dev/null 2>&1 || zypper --no-gpg-checks --non-interactive -q install -n $2 2>/dev/null
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
            yum install $2 -y -q --enablerepo=C6*,C7*,base,epel,epel-release 2>/dev/null
        fi
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        if [ ! -e "$1" ]; then
            apt-get install -y $2  2>/dev/null
        fi
    elif [[ "$(getOS)" = "suse" ]]; then
        if [ ! -e "$1" ]; then
            zypper --no-gpg-checks --non-interactive -q install $2  2>/dev/null
        fi
    fi
}

function util_maprprereq(){
    local DEPENDENCY_BASE_DEB="apt-utils curl dnsutils file iputils-ping libssl1.0.0 \
    net-tools nfs-common openssl sudo syslinux sysv-rc-conf tzdata wget clustershell"
    local DEPENDENCY_BASE_RPM="curl file net-tools openssl sudo syslinux wget which clustershell"
    local DEPENDENCY_BASE_SUSE="aaa_base curl net-tools sudo timezone wget which"
    local DEPENDENCY_DEB="$DEPENDENCY_BASE_DEB debianutils libnss3 libsysfs2 netcat ntp \
    ntpdate openssh-client openssh-server python-dev python-pycurl sdparm sshpass \
    syslinux sysstat"
    local DEPENDENCY_RPM="$DEPENDENCY_BASE_RPM device-mapper initscripts iputils \
    libsysfs lvm2 nc nfs-utils nss ntp openssh-clients openssh-server \
    python-devel python-pycurl rpcbind sdparm sshpass sysstat"
    local DEPENDENCY_SUSE="$DEPENDENCY_BASE_SUSE libopenssl1_0_0 \
    netcat-openbsd nfs-client openssl syslinux tar util-linux vim openssh \
    device-mapper iputils lvm2 mozilla-nss ntp sdparm sysfsutils sysstat util-linux python-pycurl"

    if [ "$(getOS)" = "centos" ]; then
        yum --disablerepo=epel -q -y update ca-certificates 
        yum -q -y install $DEPENDENCY_RPM --enablerepo=C6*,C7*,epel,epel-release 
        yum -q -y install java-1.8.0-openjdk-devel --enablerepo=C6*,C7*,epel,epel-release 
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get update -qq 
        apt-get -qq -y install  ca-certificates
        apt-get -qq -y install $DEPENDENCY_DEB
        apt-get -qq -y install --force-yes openjdk-8-jdk
    elif [[ "$(getOS)" = "suse" ]]; then
        zypper --non-interactive -q refresh
        zypper --non-interactive -q --no-gpg-checks -p http://download.opensuse.org/distribution/leap/42.3/repo/oss/ install sshpass
        zypper --non-interactive -q install ca-certificates
        zypper --non-interactive -q install -n $DEPENDENCY_SUSE
        zypper --non-interactive -q install -n java-1_8_0-openjdk-devel
    fi

    local MAPR_UID=${MAPR_UID:-5000}
    local MAPR_GID=${MAPR_GID:-5000}
    local MAPR_USER=${MAPR_USER-mapr}
    local MAPR_GROUP=${MAPR_GROUP:-mapr}

    groupadd -g $MAPR_GID $MAPR_GROUP
    useradd -m -u $MAPR_UID -g $MAPR_GID -G $(stat -c '%G' /etc/shadow) $MAPR_USER
    passwd $MAPR_USER > /dev/null 2>&1 << EOM
$MAPR_USER
$MAPR_USER
EOM

}

function util_installprereq(){
    if [ "$(getOS)" = "centos" ]; then
         yum repolist all 2>&1 | grep "epel/" || yum install epel-release -y --enablerepo=C6*,C7* > /dev/null 2>&1
         yum repolist enabled 2>&1 | grep epel || yum-config-manager --enable epel > /dev/null 2>&1
    fi

    [ -z "$(getent passwd mapr)" ] && util_maprprereq

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
    util_checkAndInstall "pbzip2" "pbzip2"
    util_checkAndInstall "fio" "fio"
    util_checkAndInstall "pip" "python-pip"
    util_checkAndInstall "lstopo" "hwloc"
    util_checkAndInstall "iperf3" "iperf3"
    util_checkAndInstall "gawk" "gawk"
    util_checkAndInstall "gdb" "gdb"
    if [ "$(getOS)" = "centos" ]; then
        util_checkAndInstall "lstopo" "hwloc-gui"
        util_checkAndInstall "createrepo" "createrepo"
        util_checkAndInstall "host" "bind-utils"
        util_checkAndInstall "yum-config-manager" "yum-utils"
        util_checkAndInstall "perf" "perf"
        util_checkAndInstall "sendmail" "sendmail sendmail-cf m4"
        util_checkAndInstall "ethtool" "ethtool.x86_64"
        util_checkAndInstall2 "/usr/lib64/libtcmalloc.so" "gperftools"
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        util_checkAndInstall "add-apt-repository" "python-software-properties"
        util_checkAndInstall "add-apt-repository" "software-properties-common"
        util_checkAndInstall "dpkg-scanpackages" "dpkg-dev"
        util_checkAndInstall "gzip" "gzip"
        util_checkAndInstall "host" "dnsutils"
        util_checkAndInstall "sendmail" "sendmail"
        util_checkAndInstall "ethtool" "ethtool"
        util_checkAndInstall2 "/usr/lib64/libtcmalloc.so" "google-perftools"
    elif [ "$(getOS)" = "suse" ]; then
        util_checkAndInstall "createrepo" "createrepo"
        util_checkAndInstall "host" "bind-utils"
        util_checkAndInstall "perf" "perf"
        util_checkAndInstall2 "/usr/lib64/libtcmalloc.so" "gperftools"
        zypper -n --no-gpg-checks -q -p http://download.opensuse.org/distribution/leap/42.3/repo/oss/ install sshpass > /dev/null 2>&1
    fi

    util_checkAndInstall2 "/usr/share/dict/words" "words"
    util_checkAndInstall2 "/usr/lib64/libprotobuf.so.8" "protobuf-c"
    util_checkAndInstall2 "/usr/lib64/libprotobuf.so.8" "protobuf"

    if [ "$(getOS)" = "centos" ]; then
         yum repolist enabled 2>&1 | grep epel && yum-config-manager --disable epel >/dev/null 2>&1 && yum clean metadata > /dev/null 2>&1
    fi
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
    elif [[ "$(getOS)" = "suse" ]]; then
        zypper search -s $1 | grep $2 1> /dev/null && echo "true" || echo "false"
    fi
   
}

# @param searchkey
function util_getInstalledBinaries(){
    if [ -z "$1" ]; then
        return
    fi

    if [ "$(getOS)" = "centos" ] || [ "$(getOS)" = "suse" ]; then
        echo $(rpm -qa | grep $1 | awk '{split ($0, a, "-0"); print a[1]}' | sed ':a;N;$!ba;s/\n/ /g')
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        echo $(dpkg -l | grep $1 | awk '{print $2}' | sed ':a;N;$!ba;s/\n/ /g')
    fi
}

function util_appendVersionToPackage(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local bins="$1"
    local version="$2"
    local prefix="$3"
    
    local newbins=
    for bin in $bins
    do
        local binexists=$(util_checkPackageExists $bin $version)
        if [ "$binexists" = "true" ]; then
            if [ -z "$newbins" ]; then
                if [ "$(getOS)" = "centos" ] || [ "$(getOS)" = "suse" ]; then
                    newbins="$bin$prefix*$version*"
                elif [[ "$(getOS)" = "ubuntu" ]]; then
                    newbins="$bin=$prefix*$version*"
                fi
            else
                if [ "$(getOS)" = "centos" ] || [ "$(getOS)" = "suse" ]; then
                    newbins=$newbins" $bin$prefix*$version*"
                elif [[ "$(getOS)" = "ubuntu" ]]; then
                    newbins=$newbins" $bin=$prefix*$version*"
                fi
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
    local bins="$1"
    local prefix=$3
    if [ -n "$2" ]; then
        bins=$(util_appendVersionToPackage "$1" "$2" "$3")
    fi
    log_info "[$(util_getHostIP)] Installing packages : $bins"
    if [ "$(getOS)" = "centos" ]; then
        yum clean all > /dev/null 2>&1
        yum install ${bins} -y --nogpgcheck
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get update > /dev/null 2>&1
        apt-get -y install ${bins} --force-yes
    elif [[ "$(getOS)" = "suse" ]]; then
        zypper refresh > /dev/null 2>&1
        zypper --no-gpg-checks -n install ${bins}
    fi
}

# @param list of binaries
function util_upgradeBinaries(){
    if [ -z "$1" ]; then
        return
    fi
    local bins="$1"
    log_info "[$(util_getHostIP)] Upgrading packages : $bins"
    if [ "$(getOS)" = "centos" ]; then
        if [ -n "$2" ]; then
            bins=$(util_appendVersionToPackage "$1" "$2")
        fi
        yum clean all
        yum update ${bins} -y --nogpgcheck
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get update
        apt-get -y upgrade ${bins} --force-yes
    elif [[ "$(getOS)" = "suse" ]]; then
        zypper refresh
        zypper --no-gpg-checks -n update ${bins}
    fi
}

# @param searchkey
function util_removeBinaries(){
    if [ -z "$1" ]; then
        return
    fi
    local rembins=
    while [ "$1" != "" ]; do
        for i in $(echo $1 | tr "," "\n")
        do 
            if [ -n "$rembins" ]; then
                rembins="${rembins} $(util_getInstalledBinaries $i)"
            else
                rembins="$(util_getInstalledBinaries $i)"
            fi
        done
        shift
    done 
    [ -z "$rembins" ] && return

    log_info "[$(util_getHostIP)] Removing packages : $rembins"
    if [ "$(getOS)" = "centos" ] || [ "$(getOS)" = "suse" ]; then
        rpm -ef $rembins > /dev/null 2>&1
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        apt-get -y --purge $rembins
        dpkg --purge $rembins > /dev/null 2>&1
    fi
}

function util_getDefaultDisks(){
    local disks=
    disks=$(blkid -o list | grep -v 'not mounted' | grep '/' | cut -d' ' -f1 | tr -d '[0-9]' | uniq | sort)
    disks="${disks}\n$(df -x tmpfs | grep -v : | cut -d' ' -f1 | sed -e /Filesystem/d |  sed '/^$/d' |  tr -d '[0-9]')"
    disks="${disks}\n$(lsblk -nl 2>/dev/null| grep -v disk | cut -d' ' -f1)"
    disks=$(echo -e "$disks" | sort | uniq)
    echo -e "$disks"
}

# returns space separated list of raw disks
function util_getRawDisks(){
    local disktype="$1"
    local defdisks=$(util_getDefaultDisks)
    local cmd="sfdisk -l 2> /dev/null| grep Disk | tr -d ':' | cut -d' ' -f2"
    for disk in $defdisks
    do
        cmd="$cmd | grep -v \"$disk\""
    done
    local fdisks=$(fdisk -l 2>/dev/null)
    for disk in $(bash -c  "$cmd")
    do
        local sizestr=$(echo "$fdisks" | grep "Disk \/" | grep "$disk" | awk '{print $3, $4}' | tr -d ',')
        # If no disk found in fdisk, ignore that disk
        [ -z "$sizestr" ] && cmd="$cmd | grep -v \"$disk\"" && continue
        local size=$(printf "%.0f" $(echo "$sizestr" | awk '{print $1}'))
        local rep=$(echo "$sizestr" | awk '{print $2}')
        [ "$rep" = "MB" ] && [ "$size" -lt "100000" ] && cmd="$cmd | grep -v \"$disk\""
        [ "$rep" = "GB" ] && [ "$size" -lt "100" ] &&  cmd="$cmd | grep -v \"$disk\""
    done
    local disks=$(bash -c  "$cmd | sort")
    if [ -n "$disktype" ]; then
        local ssddisks=
        for disk in $disks
        do
            local blk=$(echo $disk | cut -d'/' -f3)
            [ "$(cat /sys/block/$blk/queue/rotational)" -eq 0 ] && [ "$disktype" = "ssd" ] && ssddisks="${ssddisks}${disk} "
            [ "$(cat /sys/block/$blk/queue/rotational)" -eq 1 ] && [ "$disktype" = "hdd" ] && ssddisks="${ssddisks}${disk} "
        done
        [ -n "$ssddisks" ] && ssddisks=$(echo $ssddisks| sed 's/ $//') && disks=$(echo $ssddisks | tr ' ' '\n')
    fi
    echo "$disks"
}

## @param $1 process to kill
## @params $n process to ignore
function util_kill(){
    if [ -z "$1" ]; then
        return
    fi
    local key="$1"
    local ignore=
    if [ -n "$2" ]; then
        shift
        while [ "$1" != "" ]; do
            local ig=$1
            if [ -z "$ignore" ]; then
                ignore="grep -vi \""$ig"\""
            else
                ignore=$ignore"| grep -vi \""$ig"\""
            fi
            shift
        done
    fi
    local esckey="[${key:0:1}]${key:1}"
    if [ -n "$(ps aux | grep "$esckey")" ]; then
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
    log_error "Error on or near line ${parent_lineno}: ${message}; exiting with status ${code}"
  else
    log_error "Error on or near line ${parent_lineno}; exiting with status ${code}"
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
    str="$1"
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
    local vals="$1"
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
    local vals="$1"
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
    while read -r i; do
        i=$(echo $i | sed 's/,[[:space:]]*/,/g' | tr ' ' ',')
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
                    local isvalid=$(util_validip2 $nodeip)
                    if [ "$isvalid" = "valid" ]; then
                        echo "$nodeip,$bins" >> $newrolefile
                    else
                        log_error "Invalid IP [$node]. Scooting"
                        exit 1
                    fi
                done
            done
        else
            node=$(echo $i | cut -d',' -f1)
            local isvalid=$(util_validip2 $node)
            if [ "$isvalid" = "valid" ]; then
                echo "$i" >> $newrolefile
            else
                log_error "Invalid IP [$node]. Scooting"
                exit 1
            fi
        fi
    done <<< "$(cat $rolefile | grep '^[^#;]')"
    echo $newrolefile
}

#  @param numprint - number of log files to print if found
#  @param dirpath - directory path to find the grep files
#  @param filereg - File prefix/regex to grep on 
#  @param keywords - List of search keys
function util_grepFiles(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        return
    fi

    local numprint=$1
    local dirpath=$2
    local filereg=$3
    local keywords=${@:4}

    local runcmd="for i in \$(find $dirpath -type f -name '$filereg'); do "
    local i=0
    for key in "$keywords"
    do
        if [ "$i" -gt 0 ]; then
            runcmd=$runcmd" | grep \"$key\""
        else
            runcmd=$runcmd" grep -Hn \"$key\" \$i"
        fi
        let i=i+1
    done
    runcmd=$runcmd"; done"

    local retstat=$(bash -c "$runcmd" | sed "s~${dirpath}~~" | sed "s~^/~~")
    retstat="$(echo "$retstat" | awk '{gsub(/:/," ",$1); print}' | sort -k3 -k4 | sed 's/ /:/')"
    local cnt=$(echo "$retstat" | wc -l)
    if [ -n "$retstat" ] && [ -n "$cnt" ]; then
        echo -e "  Searchkey(s) found $cnt times in directory [ $dirpath ] in file(s) [ $filereg ]"
        if [ "$numprint" = "all" ]; then
            echo -e "$retstat" | sed 's/^/\t/'
        elif [ "$(util_isNumber $numprint)" = "true" ]; then
            echo -e "$retstat" | sed 's/^/\t/' | head -n $numprint
        else
            echo -e "$retstat" | sed 's/^/\t/' | head -n 2
        fi
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

    local disk="$1"
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
    
    log_msghead "CPU Info : "
    log_msg "\t # of cores  : $numcores"
    log_msg "\t HyperThread : $ht"
    log_msg "\t # of numa   : "$numnuma
    if [[ "$numnuma" -gt 1 ]]; then
        log_msg "\t numa cpus   : $numacpus"
    fi
}

function util_getMemInfo(){
    local mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local memgb=$(echo "$mem/1024/1024" | bc)
    log_msghead "Memory Info : "
    log_msg "\t Memory : $memgb GB"
    
}

function util_getNetInfo(){
    local nics="$(ip link show | grep BROADCAST | grep "state UP" | grep -v docker | grep -wv master | tr -d ':' | awk '{print $2}' | cut -d'@' -f1)"
    log_msghead "Network Info : "
    for nic in $nics
    do
        local ip=$(ip -4 addr show $nic | grep -oP "(?<=inet).*(?=/)" | tr -d ' ')
	    [ -z "$ip" ] && continue
        local mtu=$(cat /sys/class/net/$nic/mtu)
        local speed=$(cat /sys/class/net/${nic}/speed)
        local numad=
        speed=$(echo "$speed/1000" | bc)
        if [ -e "/sys/class/net/$nic/device" ]; then
            local numa=$(cat /sys/class/net/$nic/device/numa_node)
            local cpulist=$(cat /sys/class/net/$nic/device/local_cpulist)
            numad="NUMA: $numa (cpus: $cpulist)"
        fi
        log_msg "\t NIC: $nic, MTU: $mtu, IP: $ip, Speed: ${speed}GigE, ${numad}"
    done
}

function util_getDiskInfo(){
    local fd=$(fdisk -l 2>/dev/null)
    local disks=$(echo "$fd"| grep "Disk \/" | grep -v 'mapper\|docker' | sort | grep -v "\/dev\/md" | awk '{print $2}' | sed -e 's/://g')
    local numdisks=$(echo "$disks" | wc -l)
    local defdisks=$(util_getDefaultDisks)
    log_msghead "Disk Info : [ #ofdisks: $numdisks ]"

    for disk in $disks
    do
        local blk=$(echo $disk | cut -d'/' -f3)
        local size=$(echo "$fd" | grep "Disk \/" | grep "$disk" | tr -d ':' | awk '{if($4 ~ /^G/) {print $3} else if($4 ~ /^T/) {print $3*1024} else if($4 ~ /^M/) {print $3/1024}}')
        local dtype=$(cat /sys/block/$blk/queue/rotational)
        local isos=$(echo "$fd" |  grep -wA6 "$disk" | grep "Disk identifier" | awk '{print $3}')
        local used=$(echo "$defdisks" | grep -w "$disk")
        if [ "$dtype" -eq 0 ]; then
            dtype="SSD"
        else
            dtype="HDD"
        fi
        if [ -n "$isos" ]; then
            local dival=0
            if [ -n "$(echo $isos | grep "^0x" )" ]; then
                dival=$(printf "%d\n" $isos)
            elif [ -n "$(echo $isos | grep "-")" ]; then
                dival=1
            fi
            if [[ "$dival" -ne 0 ]]; then
                isos="[ OS ]"
                used=
            else
                isos=
            fi
        fi
        if [ -n "$used" ]; then
            used="[ USED ]"
        fi
        log_msg "\t $disk : Type: $dtype, Size: ${size} GB ${isos}${used}"
    done
}

function util_getNumaInfo(){
    command -v lstopo >/dev/null 2>&1 || util_installprereq > /dev/null 2>&1
    local lstopo=$(lstopo --no-caches)
    local numnuma=$(echo "$lstopo" |  grep NUMANode | wc -l)
    #local fd=$(fdisk -l 2>/dev/null)
    #local disks=$(echo "$fd"| grep "Disk \/" | grep -v 'mapper\|docker' | sort | grep -v "\/dev\/md" | awk '{print $2}' | sed -e 's/://g')

    log_msghead "Numa Info : [ #ofnuma: $numnuma ]"
    for ((i=0; i<$numnuma; i++))
    do
        log_msg "\t NUMANode #${i} :"
        log_msg "\t   CPUs   : $(lscpu | grep "NUMA node$i" | awk '{print $4}')" 
        log_msg "\t   Memory : $(echo "$lstopo"  | grep NUMA | grep "#${i}" | awk '{print $4}' | tr -d ')')" 
        local numadisk=
        local nextnuma=$(echo "$i+1" | bc)
        local k=0
        local prevline=
        local pcidisk=
        local numdisks=0
        while read -r line
        do
            local ispci=$(echo "$line" | grep PCI)
            [ -n "$ispci" ] && [ -z "$prevline" ] && prevline="pci" && continue
            local isdisk=$(echo "$line" | grep Block)
            [ "$prevline" = "pci" ] && [ -z "$isdisk" ] && continue
            [ -z "$prevline" ] && [ -z "$isdisk" ] && continue

            if [ -z "$isdisk" ]; then
                numdisks=$(echo "$numdisks + $(echo $pcidisk | wc -w)" | bc) && numadisk="${numadisk}{ PCI #$k: $pcidisk} "
                pcidisk=
                prevline=
                let k=k+1
                continue
            else
                prevline="disk"
            fi
            local diskname=$(echo "$isdisk" | awk '{print $3}' | tr -d '"')
            #diskname=$(echo "$disks" | grep $diskname)
            pcidisk="$pcidisk${diskname} "
        done <<<"$(echo "$lstopo" | grep 'NUMANode\|PCI\|Block' | grep -v PCIBridge | sed -n -e "/NUMANode L#${i}/,/NUMANode L#${nextnuma}/ p")"
        [ -n "$pcidisk" ] && numdisks=$(echo "$numdisks + $(echo $pcidisk | wc -w)" | bc) && numadisk="${numadisk}{ PCI #$k: $pcidisk}"

        numadisk=$(echo "$numadisk" | sed 's/[[:space:]]*$//g')
        [ -n "$numadisk" ] && log_msg "\t   Disks  : ${numdisks} [$numadisk]" 
    done
}

function util_getMachineInfo(){
    log_msghead "Machine Info : "
    log_msg "\t Hostname : $(hostname -f)"
    log_msg "\t OS       : $(getOSWithVersion)"
    command -v mpstat >/dev/null 2>&1 && log_msg "\t Kernel   : $(mpstat | head -n1 | awk '{print $1,$2}')"
}

# @param round to power of 2
function util_getNearestPower2() { 
    if [ -z "$1" ]; then
        return
    fi
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; 
}

function util_restartSSHD(){
    if [ "$(getOS)" = "centos" ] || [ "$(getOS)" = "suse" ]; then
        service sshd restart > /dev/null 2>&1
    elif [[ "$(getOS)" = "ubuntu" ]]; then
        service ssh restart > /dev/null 2>&1
    fi
}

function util_createExtractFile(){
    local scriptfile="extract.sh"
    echo -e '#!/bin/bash \n' > $scriptfile
    echo "for i in \$(ls *.bz2);do bzip2 -dk \$i;done " >> $scriptfile
    echo "for i in \$(ls *.tar);do tar -xf \$i && rm -f \${i}; done" >> $scriptfile
    chmod +x $scriptfile

    local delscriptfile="delextract.sh"
    echo -e '#!/bin/bash \n' > $delscriptfile
    echo "for i in \$(ls | grep -v \"bz2\$\" | grep -v "extract.sh$");do rm -f \${i}; done" >> $delscriptfile
    chmod +x $delscriptfile
}

function util_getResourceUseHeader(){
    echo -e "TIME\tMEMORY\t%CPU\t%MEM"
}

function util_getResourceUse(){
    [ -z "$1" ] && return
    local ppid="$1"
    if kill -0 ${ppid}; then
        local curtime=$(date '+%Y-%m-%d-%H-%M-%S')
        local topline=$(top -bn 1 -p $ppid | tail -1 | awk '{ printf("%s\t%s\t%s\n", $6, $9, $10); }')
        echo -e "$curtime\t$topline"
    fi
}

function util_isValidEmail(){
    [ -z "$1" ] && return
    local maillist="$1"
    maillist=$(echo "$maillist" | tr ',' ' ')
    local valid=
    for i in $maillist
    do
        [ -z "$(echo "${i}" | grep '^[a-zA-Z0-9]*@[a-zA-Z0-9]*\.[a-zA-Z0-9]*$')" ] && return
    done
    echo "true"
}

function util_sendMail(){
    [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] && echo "Missing arguments" && return

    local tolist="$1"
    local subject="$2"
    local content="$3"

    [ -z "$(util_isValidEmail "$tolist")" ] && echo "Incorrect mail id(s)" && return
    [ -z "$(util_fileExists $content)" ] && echo "Content file doesn't exist" && return

    (
      echo To: ${tolist}
      echo From: no-reply@mapr.com
      echo "Content-Type: text/html; "
      echo Subject: ${subject}
      echo
      cat $content
    ) | sendmail -t
}

function util_sendJSONMail(){
    [ -z "$1" ] || [ -z "$2" ] && echo "Missing arguments" && return

    local json="$1"
    local useurl="$2"

    curl -L -X POST --data @- ${useurl} < $json > /dev/null 2>&1
}

function util_removeXterm(){
    [ -z "$1" ] && return
    echo "$1" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g'
}

function util_postToSlack(){
     [ -z "$1" ] || [ -z "$2" ] && echo "Missing arguments" && return

    local SLACK_URL="https://hooks.slack.com/services/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"
    local rolefile="$1"
    local optype="$2"
    local extrainfo="$3"
    
    local roles="$(cat $rolefile)"
    local mainnode=$(echo "$roles" | grep '^[^#;]' | grep cldb | head -1 | cut -d',' -f1)
    local text="$(echo -e "Cluster \`$mainnode\` *$(echo $optype | awk '{print toupper($0)}')* \n \`\`\`$roles\`\`\`")"
    if [ -n "$extrainfo" ]; then
        extrainfo="$(echo "$extrainfo" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g')"
        text="$(echo -e "$text \n\n \`\`\`$extrainfo\`\`\`")"
    fi
    text="$(echo "$text" | python -c 'import json,sys; print json.dumps(sys.stdin.read())')"
    
    local json="{\"text\":$text}"
    local tmpfile=$(mktemp)
    echo "$json" > $tmpfile
    curl -L -X POST -H 'Content-type: application/json' --data @-  $SLACK_URL  < $tmpfile > /dev/null 2>&1
    rm -f $tmpfile > /dev/null 2>&1
}

function util_postToSlack2(){
     [ -z "$1" ] && echo "Missing arguments" && return

    local SLACK_URL="https://hooks.slack.com/services/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"
    local filetopost="$1"
    
    local posttext="$(cat $filetopost)"
    posttext="$(echo "$posttext" | python -c 'import json,sys; print json.dumps(sys.stdin.read())' | sed 's/^.\(.*\).$/\1/')"

    # Slack per message size limit
    local charlimit=3800
    local textlen=${#posttext}
    while [[ "$textlen" -gt "2" ]]; do
        local nlpos=$(echo "$posttext" | grep -aob '\\n' | cut -d ':' -f1 | awk -v sl=$charlimit '{if($1<=sl)l=$1}END{print l+2}')
        local ptext="${posttext:0:$nlpos}"
        local json="{\"text\":\"\`\`\`$ptext\`\`\`\"}"
        local tmpfile=$(mktemp)
        echo "$json" > $tmpfile
        curl -L -X POST -H 'Content-type: application/json' --data @-  $SLACK_URL  < $tmpfile > /dev/null 2>&1
        rm -f $tmpfile > /dev/null 2>&1
        let nlpos=nlpos+1
        textlen=${#posttext}
        posttext="${posttext:$nlpos:$textlen}"
    done
}

# @param host name with domin
function util_getIPfromHostName(){
    if [ -z "$1" ]; then
        return
    fi
    local ip=$(ping -c 1 $1 2>/dev/null | awk -F '[()]' '/PING/{print $2}')
    if [ "$(util_validip2 "$ip")" = "valid" ]; then
        echo $ip
    fi
}

### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
