#!/bin/bash
BASE_DIR=$(dirname $0)
cd ${BASE_DIR}

rm -rf add-mtls-dr cert edit-probe 

# Install Business Application
echo
echo "# Install Business Application"
bash 03_install_app.sh

# OpenShift Service Mesh operator and multi-tenant ServiceMeshControlPlane
echo $'\n\n\n'
echo "# OpenShift Service Mesh operator and multi-tenant ServiceMeshControlPlane"
bash 04_setup_sm_cp.sh

# ServiceMeshMemberRoll and auto-injected bookinfo deployments
echo $'\n\n\n'
echo "# ServiceMeshMemberRoll and auto-injected bookinfo deployments"
bash 05_setup_sm_memberroll.sh

# Strict mTLS network traffic between bookinfo services
echo $'\n\n\n'
echo "# Strict mTLS network traffic between bookinfo services"
bash 06_setup_mtls.sh

# Cleaning environment
# bash 99_cleaning.sh
