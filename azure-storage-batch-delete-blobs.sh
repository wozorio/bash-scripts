#!/usr/bin/env bash

######################################################################
# Script Name    : azure-storage-batch-delete-blobs.sh
# Description    : Used to delete blobs from a storage account recursively
# Args           : STORAGE_ACCOUNT CONTAINER_NAME
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail
set -o nounset

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ./azure-storage-batch-delete-blobs.sh STORAGE_ACCOUNT CONTAINER_NAME"
    exit 1
}

# Check if the right number of arguments were passed
if [[ "{$#}" -ne 2 ]]; then
    usage
fi

STORAGE_ACCOUNT=$1
CONTAINER_NAME=$2

STORAGE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name ${STORAGE_ACCOUNT} \
    --query "[0].value" | tr -d '"')

az storage blob delete-batch --account-key ${STORAGE_ACCOUNT_KEY} --account-name ${STORAGE_ACCOUNT} --source ${CONTAINER_NAME} --delete-snapshots include
