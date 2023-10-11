#!/usr/bin/env bash

################################################################################
# Script Name    : terraform-azure-bootstrap.sh
# Description    : Used to create a blob storage account for Terraform state files
# Args           : RESOURCE_GROUP_NAME LOCATION STORAGE_ACCOUNT_NAME
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
################################################################################

set -o errexit
set -o pipefail
set -o nounset

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ${0} RESOURCE_GROUP_NAME LOCATION STORAGE_ACCOUNT_NAME"
    exit 1
}

function create_resource_group() {
    local RESOURCE_GROUP_EXISTS
    RESOURCE_GROUP_EXISTS=$(az group exists --name "${RESOURCE_GROUP_NAME}")

    if [[ "${RESOURCE_GROUP_EXISTS}" == "true" ]]; then
        echo "INFO: ${RESOURCE_GROUP_NAME} resource group already exists!"
    else
        echo "INFO: Creating resource group: ${RESOURCE_GROUP_NAME}"
        az group create --location "${LOCATION}" --name "${RESOURCE_GROUP_NAME}"
    fi
}

function create_storage_account() {
    local STORAGE_ACCOUNT_EXISTS
    STORAGE_ACCOUNT_EXISTS=$(az storage account check-name --name "${STORAGE_ACCOUNT_NAME}" --query "nameAvailable")

    if [[ "${STORAGE_ACCOUNT_EXISTS}" == "false" ]]; then
        echo "INFO: ${STORAGE_ACCOUNT_NAME} storage account already exists!"
    else
        echo "INFO: Creating storage account: ${STORAGE_ACCOUNT_NAME}"
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP_NAME}" \
            --access-tier "Cool" \
            --kind "BlobStorage" \
            --location "${LOCATION}" \
            --sku "Standard_LRS" \
            --https-only true \
            --allow-blob-public-access false \
            --min-tls-version "TLS1_2"

        # Enable blob versioning
        # https://docs.microsoft.com/en-us/azure/storage/blobs/versioning-overview
        az storage account blob-service-properties update \
            --account-name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP_NAME}" \
            --enable-versioning true \
            --enable-delete-retention true \
            --delete-retention-days 30 \
            --container-retention true \
            --container-days 30

        # Create a policy to delete blob versions older than 30 days
        # https://docs.microsoft.com/en-us/azure/storage/blobs/storage-lifecycle-management-concepts?tabs=azure-portal#manage-versions
        az storage account management-policy create \
            --account-name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP_NAME}" \
            --policy "@files/azure-blob-policy-delete-old-versions.json"
    fi
}

function create_storage_container() {
    local STORAGE_ACCOUNT_KEY
    STORAGE_ACCOUNT_KEY=$(
        az storage account keys list \
            --account-name "${STORAGE_ACCOUNT_NAME}" \
            --query "[0].value"
    )

    local STORAGE_CONTAINER_EXISTS
    STORAGE_CONTAINER_EXISTS=$(
        az storage container exists \
            --name "${STORAGE_CONTAINER_NAME}" \
            --account-name "${STORAGE_ACCOUNT_NAME}" \
            --account-key "${STORAGE_ACCOUNT_KEY}" \
            --query "exists"
    )

    if [[ "${STORAGE_CONTAINER_EXISTS}" == "true" ]]; then
        echo "INFO: ${STORAGE_CONTAINER_NAME} storage container already exists!"
    else
        echo "INFO: Creating storage container: ${STORAGE_CONTAINER_NAME}"
        az storage container create --name "${STORAGE_CONTAINER_NAME}" --account-name "${STORAGE_ACCOUNT_NAME}" --account-key "${STORAGE_ACCOUNT_KEY}"
    fi
}

function main() {
    # Check if the right number of arguments was passed
    if [[ "$#" -ne 3 ]]; then
        usage
    fi

    RESOURCE_GROUP_NAME=$1
    LOCATION=$2
    STORAGE_ACCOUNT_NAME=$3
    STORAGE_CONTAINER_NAME="tfstate"

    create_resource_group
    create_storage_account
    create_storage_container
}

main "$@"
