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
1. Read certain configs from a conf/env file
