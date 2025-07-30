#!/usr/bin/env bash

################################################################################
# Script Name    : azure-acr-mirror-image-from-external-registry.sh
# Description    : Used to mirror images from external registries to an ACR (Azure Container Registry)
# Args           : EXTERNAL_CONTAINER_REGISTRY REPOSITORY IMAGE_TAG AZURE_CONTAINER_REGISTRY [IMAGE_ARCHITECTURE]
# Author         : Wellington Ozorio <wozorio@duck.com>
################################################################################

set -e

function log() {
    local MESSAGE="${1}"
    echo "${MESSAGE}" 1>&2
}

function usage() {
    log "ERROR: Missing or invalid arguments"
    log "Usage example: ${0} EXTERNAL_CONTAINER_REGISTRY REPOSITORY IMAGE_TAG AZURE_CONTAINER_REGISTRY [IMAGE_ARCHITECTURE]"
    exit 1
}

function check_image_exists() {
    local IMAGE_EXISTS
    IMAGE_EXISTS=$(
        az acr repository show \
            --name "${AZURE_CONTAINER_REGISTRY}" \
            --image "${REPOSITORY}:${IMAGE_TAG}" \
            --query name \
            2>/dev/null || true
    )
    echo "${IMAGE_EXISTS}"
}

function tag_image() {
    buildah tag "${ECR_TAG}" "${ACR_TAG}"
}

function pull_image() {
    buildah pull --arch "${IMAGE_ARCHITECTURE}" "${ECR_TAG}"
    tag_image
}

function logon_to_acr() {
    # The `addSpnToEnvironment` property must be set to `true` in the AzureCLI@2 pipeline task
    # for the servicePrincipalId and servicePrincipalKey environment variables to be available
    # shellcheck disable=SC2154
    buildah login \
        --username "${servicePrincipalId}" \
        --password "${servicePrincipalKey}" \
        "${AZURE_CONTAINER_REGISTRY}"
}

function push_image_to_acr() {
    local IMAGE_EXISTS
    IMAGE_EXISTS=$(check_image_exists)

    if [[ -n "${IMAGE_EXISTS}" ]]; then
        log "INFO: Image already exists in the ACR! It can be used with the following annotation:"
        log "${ACR_TAG}"
        exit 0
    fi

    pull_image
    logon_to_acr
    buildah push "${ACR_TAG}"

    log "INFO: Image successfully mirrored! It can be used with the following annotation:"
    log "${ACR_TAG}"
}

function main() {
    if [[ "${#}" -lt 4 || "${#}" -gt 5 ]]; then
        usage
    fi

    EXTERNAL_CONTAINER_REGISTRY="${1}"
    REPOSITORY="${2}"
    IMAGE_TAG="${3}"
    AZURE_CONTAINER_REGISTRY="${4}"
    IMAGE_ARCHITECTURE="${5:-amd64}"

    ECR_TAG="${EXTERNAL_CONTAINER_REGISTRY}/${REPOSITORY}:${IMAGE_TAG}"
    ACR_TAG="${AZURE_CONTAINER_REGISTRY}/${REPOSITORY}:${IMAGE_TAG}"

    push_image_to_acr
}

main "$@"
