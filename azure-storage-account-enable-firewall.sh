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

# Remove allowed IP addresses (if any) from the exception list
ALLOWED_IP_ADRESSES=$(
    az storage account network-rule list \
    --resource-group "${RESOURCE_GROUP}" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --output tsv \
    --query ipRules[].ipAddressOrRange
)

if [[ -n "${ALLOWED_IP_ADRESSES}" ]]; then
    for ALLOWED_IP_ADDRESS in ${ALLOWED_IP_ADRESSES}; do
        az storage account network-rule remove \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --ip-address "${ALLOWED_IP_ADDRESS}"
    done
fi

# Close the firewall
az storage account update \
--default-action Deny \
--resource-group "${RESOURCE_GROUP}" \
--name "${STORAGE_ACCOUNT_NAME}"
