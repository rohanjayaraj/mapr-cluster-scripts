#MapR Cluster Management Scripts

MapR cluster setup & management with a single bash script

## MapR Cluster Setup:
- Create a role file similar to the sample file [roles](roles/mapr_roles.maprdb).
- Enable the required repo in [mapr-repo](repo/mapr.repo) by setting enabled=1
- Run mapr_setup.sh to install/uninstall

* To install :
`./mapr_setup.sh -c=<rolefile> -i`

* To uninstall :
`./mapr_setup.sh -c=<rolefile> -u`

* To reconfigure already existing cluster :
`./mapr_setup.sh -c=<rolefile> -r`

* Backup all MFS logs to a local directory :
`./mapr_setup.sh -c=<rolefile> -b=/path/to/dir`

* Help
`./mapr_setup.sh -h`

## MapR Cluster Info & Analysis

* Check for disk errors in mfs logs :
`./mapr_logdr.sh -c=<rolefile> -d`

* Check tablet distribution for table '/tables/usertable' :
`./mapr_logdr.sh -c=<rolefile> -td=/tables/usertable`

* Print system information :
`./mapr_logdr.sh -c=10.10.103.[21,111-117,119-120] -si`

#### TODO:
1. Read certain configs from a conf/env file
