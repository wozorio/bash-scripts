#!/usr/bin/env bash

######################################################################
# Script Name    : azure-acr-delete-images-by-manifest.sh
# Description    : Used to delete container images by the manifest digest
# Args           : ACR_NAME REPO
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

# Stop execution on any error
set -e

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ./azure-acr-delete-images-by-manifest.sh ACR_NAME REPO"
    exit 1
}

# Check if the right number of arguments were passed
if [[ "$#" -ne 2 ]]; then
    usage
fi

ACR_NAME=$1
REPO=$2

## !!! ATTENTION !!!
## Update the MANIFESTS variable below with the desired list of manifests to be deleted
MANIFESTS="sha256:a94b1e9390ad107b9a9de21e7e9caca7a6ae3cc3bc74d1db0a75359bc89a1940
sha256:8b06d545318addf0b8438b9565b346dd6f310819cf227c6d44648e0c91248aca
sha256:4ad46dbb122437ec3bfb02f1af541cfb5b5a90be12aead314bab731c4b97fefd
sha256:e20a7551a4e2f56af0afa9147df939e65102e0aed66c27701a72bdef97468e2f"

# Iterate over the MANIFESTS variable and delete each image by the manifest digest
echo "${MANIFESTS[@]}" | while read -r manifest; do
    echo "deleting $manifest"
    az acr repository delete --name "${ACR_NAME}" --image "${REPO}@${manifest}" --yes
done
