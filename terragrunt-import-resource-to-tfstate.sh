#!/usr/bin/env bash

################################################################################
# Script Name    : terragrunt-import-resource-to-tfstate.sh
# Description    : Used to import existing resources into Terraform
#                  state file and modify an attribute in its contents
#                  before pushing it back to the remote storage in Azure
# Args           : n/a
# Author         : Wellington Ozorio <wozorio@duck.com>
################################################################################

# Declare variables
## Make sure you assign proper values to the variables below before executing the script!!!
STAGE="dev"
SUBSCRIPTION_NAME="SUBSCRIPTION_NAME"
SUBSCRIPTION_ID="SUBSCRIPTION_ID"

TIMESTAMP=$(date "+%Y-%m-%d-%H-%M-%S")
RESOURCE_GROUP_NAME="${STAGE}-sys01-rg01"
SQL_SERVER_NAME="${STAGE}-sys01-sqlsrv01"
export STORAGE_NAME_TERRAFORM_STATE="${STAGE}stage01terraform"

# Retrieve the access key from the Teraform backend storage account
export ACCESS_KEY
ACCESS_KEY=$(
    az storage account keys list \
        --account-name ${STORAGE_NAME_TERRAFORM_STATE} \
        --query "[0].value" | tr -d '"'
)

# Change to sys01 directory structure
# Adjust the path according to your environment
cd ~/terraform.deployment/environments/${SUBSCRIPTION_NAME}/${STAGE}-stage01/sys01 || exit 1

# Iterate over each instance in the directory structure
for INSTANCE in inst*; do
    cd "${INSTANCE}"/main || exit 1

    # Terraform Init
    terragrunt init

    # Import the new module into Terraform state file
    terragrunt import \
        module.sql_database_01.azurerm_mssql_database.database \
        /subscriptions/"${SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP_NAME}"/providers/Microsoft.Sql/servers/"${SQL_SERVER_NAME}"/databases/"${STAGE}"-sys01-"${INSTANCE}"-sqldb01

    # Remove the old module from Terraform state file
    terragrunt state rm module.sql_database_01.azurerm_sql_database.database

    # Pull the Terraform state file from the Storage Account
    terragrunt state pull >main.tfstate

    # Make a backup copy of the downloaded Terraform state file
    cp main.tfstate ~/backup/bkp-"${STAGE}"-"${TIMESTAMP}"-"${INSTANCE}"-main.tfstate

    # Change the value of create_mode from null to "Default"
    sed -i 's/"create_mode": null/"create_mode": "Default"/' main.tfstate

    # Push the modified Terraform state file back to the Storage Account
    terragrunt state push -force main.tfstate

    # Change to one level up in the directory structure
    cd ../../
done
