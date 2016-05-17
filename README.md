#MapR Cluster Management Scripts

Single 


## Steps:
1) Create a role file similar to the sample file [roles](roles/mapr_roles.maprdb).
2) Update the required repo in [mapr-repo](repo/mapr.repo)
3) Run mapr_setup.sh to install/uninstall

## To install :
`./mapr_setup.sh -c=<rolefile> -i`

## To uninstall:
`./mapr_setup.sh -c=<rolefile> -u`

## Help
`./mapr_setup.sh -h`

