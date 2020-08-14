#!/bin/bash

######################################################################
# Script Name    : terragrunt-copy-custom-terraform-provider.sh
# Description    : Used to copy custom Terraform providers to the
#                  plugins directory of each Terragrunt module
# Args           : n/a
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

STAGE="dev"
SUBSCRIPTION_NAME="SUBSCRIPTION_NAME"

# Copy custom Terraform providers (i.e.: MSSQL) to the plugins directory of each instance
cd ~/terraform.deployment/environments/${SUBSCRIPTION_NAME}/${STAGE}-stage01/sys01

for INSTANCE in inst*; do
  cd ${INSTANCE}/main

  INSTANCE_PLUGIN_DIR=$(find -name linux_amd64)
  
  echo "Copying Terraform mssql provider to instance ${INSTANCE}"
  cp ~/terraform-provider-mssql_v1.1.1_x4 ${INSTANCE_PLUGIN_DIR}

  cd ../../
done
