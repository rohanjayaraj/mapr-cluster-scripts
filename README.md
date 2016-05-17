#MapR Cluster Management Scripts

Single 


## Steps:
* Create a role file similar to the sample file [roles](roles/mapr_roles.maprdb).
* Update the required repo in [mapr-repo](repo/mapr.repo)
* Run mapr_setup.sh to install/uninstall

## To install :
`./mapr_setup.sh -c=<rolefile> -i`

## To uninstall:
`./mapr_setup.sh -c=<rolefile> -u`

## Help
`./mapr_setup.sh -h`

