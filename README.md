#MapR Cluster Management Scripts

MapR cluster setup & management with a single bash script

## MapR Cluster Setup:
* Create a role file similar to the sample file [roles](roles/mapr_roles.maprdb).
* Enable the required repo in [mapr-repo](repo/mapr.repo) by setting enabled=1
* Run mapr_setup.sh to install/uninstall

#### To install :
`./mapr_setup.sh -c=<rolefile> -i`

#### To uninstall :
`./mapr_setup.sh -c=<rolefile> -u`

#### To reconfigure already existing cluster :
`./mapr_setup.sh -c=<rolefile> -r`

#### Backup all MFS logs to a local directory :
`./mapr_setup.sh -c=<rolefile> -b=/path/to/dir`

#### Help
`./mapr_setup.sh -h`

## MapR Cluster Info & Analysis

#### Check for disk errors in mfs logs :
`./mapr_logdr.sh -c=<rolefile> -d`

#### Check tablet distribution for table '/tables/usertable' :
`./mapr_logdr.sh -c=<rolefile> -td=/tables/usertable`

#### Print system information :
`./mapr_logdr.sh -c=10.10.103.[21,111-117,119-120] -si`

### TODO:
1. Read certain configs from a conf/env file

Usage :
./mapr_setup.sh -c=<ClusterConfig> <Arguments> [Options]
 Arguments :
	 -h --help
		 - Print this
	 -c=<file> | --clusterconfig=<file>
		 - Cluster Configuration Name/Filepath
	 -i | --install
		 - Install cluster
	 -u | --uninstall
		 - Uninstall cluster
	 -up | --upgrade
		 - Upgrade cluster
	 -r | --reconfigure | --reset
		 - Reconfigure the cluster if binaries are already installed
	 -b | -b=<COPYTODIR> | --backuplogs=<COPYTODIR>
		 - Backup /opt/mapr/logs/ directory on each node to COPYTODIR (default COPYTODIR : /tmp/)

 Install/Uninstall Options :
	 -bld=<BUILDID> | --buildid=<BUILDID>
		 - Specify a BUILDID if the repository has more than one version of same binaries (default: install the latest binaries)
	 -repo=<REPOURL> | --repository=<REPOURL>
		 - Specify a REPOURL to use to download & install binaries
	 -ns | -ns=TABLENS | --tablens=TABLENS
		 - Add table namespace to core-site.xml as part of the install process (default : /tables)
	 -n=CLUSTER_NAME | --name=CLUSTER_NAME (default : archerx)
		 - Specify cluster name
	 -d=<#ofDisks> | --maxdisks=<#ofDisks>
		 - Specify number of disks to use (default : all available disks)
	 -sp=<#ofSPs> | --storagepool=<#ofSPs>
		 - Specify number of storage pools per node
	 -m=<#ofMFS> | --multimfs=<#ofMFS>
		 - Specify number of MFS instances (enables MULTI MFS)
	 -p | --pontis
		 - Configure MFS lrus sizes for Pontis usecase, limit disks to 6 and SPs to 2
	 -f | --force
		 - Force uninstall a node/cluster
	 -et | --enabletrace
		 - Enable guts,dstat & iostat on each node after INSTALL. (WARN: may fill the root partition)
	 -pb=<#ofMBs> | --putbuffer=<#ofMBs>
		 - Increase client put buffer threshold to <#ofMBs> (default : 1000)
	 -s | --secure
		 - Enable wire-level security on the cluster nodes
	 -tr | --trim
		 - Trim SSD drives before configuring the node (WARNING: DO NOT TRIM OFTEN)

 Post install Options :
	 -ct | --cldbtopo
		 - Move CLDB node & volume to /cldb topology
	 -y | --ycsbvol
		 - Create YCSB related volumes
	 -tc | --tsdbtocldb
		 - Move OpenTSDB volume to /cldb topology
	 -t | --tablecreate
		 - Create /tables/usertable [cf->family] with compression off
	 -tlz | --tablelz4
		 - Create /tables/usertable [cf->family] with lz4 compression
	 -j | --jsontablecreate
		 - Create YCSB JSON Table with default family
	 -jcf | --jsontablecf
		 - Create YCSB JSON Table with second CF family cfother

 Examples :
	 ./mapr_setup.sh -c=maprdb -i -n=Performance -m=3
	 ./mapr_setup.sh -c=maprdb -u
	 ./mapr_setup.sh -c=roles/pontis.roles -i -p -n=Pontis
	 ./mapr_setup.sh -c=/root/configs/cluster.role -i -d=4 -sp=2
