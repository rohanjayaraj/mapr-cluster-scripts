MapR Cluster Management Scripts

## Steps:
1) Create a role file similar to the sample file 'roles' dir.
2) Update the required repo in 'repo/mapr.repo'
3) Run mapr_setup.sh to install/uninstall

## To install :
./mapr_setup.sh -c=<rolefile> -i

## To uninstall:
./mapr_setup.sh -c=<rolefile> -u


Run ./mapr_setup.sh -h for info

