#!/usr/bin/env bash

######################################################################
# Script Name    : azure-acr-mirror-image-from-external-registry.sh
# Description    : Used to mirror images from external registries to an ACR (Azure Container Registry)
# Args           : EXTERNAL_CONTAINER_REGISTRY REPOSITORY IMAGE_TAG AZURE_CONTAINER_REGISTRY
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail
set -o nounset

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ${0} EXTERNAL_CONTAINER_REGISTRY REPOSITORY IMAGE_TAG AZURE_CONTAINER_REGISTRY"
    exit 1
}

# Check if the right number of arguments were passed
if [[ "$#" -ne 4 ]]; then
    usage
fi

EXTERNAL_CONTAINER_REGISTRY=$1
REPOSITORY=$2
IMAGE_TAG=$3
AZURE_CONTAINER_REGISTRY=$4

function logon_to_acr() {
    echo "Logging on to the ACR ${AZURE_CONTAINER_REGISTRY}"
    az acr login --name "${AZURE_CONTAINER_REGISTRY}"
}

function check_image_exists() {
    local IMAGE_EXISTS=$(
        az acr repository show \
            --name "${AZURE_CONTAINER_REGISTRY}" \
            --image "${REPOSITORY}:${IMAGE_TAG}" \
            --query name \
            2>/dev/null || true
    )
    echo "${IMAGE_EXISTS}"
}

function mirror_image_to_acr() {
    logon_to_acr
    local IMAGE_EXISTS=$(check_image_exists)

    if [[ -n "${IMAGE_EXISTS}" ]]; then
        echo "Image already exists in the ACR! It can be used with the following annotation:"
        echo "${AZURE_CONTAINER_REGISTRY}.azurecr.io/${REPOSITORY}:${IMAGE_TAG}"
        exit 0
    else
        echo "Mirroring image ${REPOSITORY}:${IMAGE_TAG} to ${AZURE_CONTAINER_REGISTRY}"
        az acr import \
            --name "${AZURE_CONTAINER_REGISTRY}" \
            --source "${EXTERNAL_CONTAINER_REGISTRY}/${REPOSITORY}:${IMAGE_TAG}" \
            --image "${REPOSITORY}:${IMAGE_TAG}"

        echo "Image successfully mirrored! It can be used with the following annotation:"
        echo "${AZURE_CONTAINER_REGISTRY}.azurecr.io/${REPOSITORY}:${IMAGE_TAG}"
    fi
}

mirror_image_to_acr
