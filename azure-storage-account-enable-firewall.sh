#!/usr/bin/env bash

######################################################################
# Script Name    : azure-storage-account-enable-firewall.sh
# Description    : Used to enable Azure storage account firewall
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail

function usage() {
    echo "Usage:"
    echo -e "\t-r Storage account resource group"
    echo -e "\t-s Storage account name"
    exit 1
}

while getopts "r:s:" OPTION; do
    case "$OPTION" in
    r)
        RESOURCE_GROUP=$OPTARG
        ;;

    s)
        STORAGE_ACCOUNT_NAME=$OPTARG
        ;;

    *)
        usage
        ;;
    esac
done

## The initial idea was to only allow the public IP of the Azure DevOps agent as an exception in the firewall.
## However, Microsoft's API is very unstable, so every now and then while running Terraform pipelines
## the connection was dropped with 403 response codes, even having waited 60 seconds after the IP was added to the exception list
## Due to such an instability, the firewall has to be temporarly open to ensure Terraform pipelines run smoothly
az storage account update \
    --public-network-access "Enabled" \
    --default-action "Allow" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${STORAGE_ACCOUNT_NAME}"
