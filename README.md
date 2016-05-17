#MapR Cluster Management Scripts

...MapR cluster setup with a single bash script

## Steps:
* Create a role file similar to the sample file [roles](roles/mapr_roles.maprdb).
* Enable the required repo in [mapr-repo](repo/mapr.repo) by setting enabled=1
* Run mapr_setup.sh to install/uninstall

## To install :
`./mapr_setup.sh -c=<rolefile> -i`

## To uninstall:
`./mapr_setup.sh -c=<rolefile> -u`

## Help
`./mapr_setup.sh -h`


#### TODO:
1. Full support for Ubuntu
..* Repo file for ubuntu
..* Binary add/remove
..* Ttesting
2. Automatically enable/disable required repo based on the command line input
3. Support custom configurations on the cluster nodes
4. Reduce errors logged on stdout
5. Read certain configs from a conf/env file
6. Support install of binaries from a local dir
