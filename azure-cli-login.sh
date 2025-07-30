#!/usr/bin/env bash

################################################################################
# Script Name    : az-cli-login.sh
# Description    : Used to sign in to an Azure subscription with a service principal
# Args           : SUBSCRIPTION_ID SERVICE_PRINCIPAL_ID SERVICE_PRINCIPAL_SECRET TENANT_ID
# Author         : Wellington Ozorio <wozorio@duck.com>
################################################################################

# Stop execution on any error
set -e

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ./az-cli-login.sh SUBSCRIPTION_ID SERVICE_PRINCIPAL_ID SERVICE_PRINCIPAL_SECRET TENANT_ID"
    exit 1
}

# Check if the right number of arguments were passed
if [[ "$#" -ne 4 ]]; then
    usage
fi

SUBSCRIPTION_ID=$1
SERVICE_PRINCIPAL_ID=$2
SERVICE_PRINCIPAL_SECRET=$3
TENANT_ID=$4

az login \
    --service-principal \
    --username "${SERVICE_PRINCIPAL_ID}" \
    --password "${SERVICE_PRINCIPAL_SECRET}" \
    --tenant "${TENANT_ID}"

az account set -s "${SUBSCRIPTION_ID}"
