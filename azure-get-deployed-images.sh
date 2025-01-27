#!/usr/bin/env bash

# This script retrieves the deployed images from all AKS clusters and function apps
# within a subscription and consolidates them into a single array. The array is then
# set as an Azure DevOps output variable which can be used in subsequent pipeline steps.

# Example use-case: passing the array of deployed images as an exception list to a container
# registry cleanup task.

set -o errexit
set -o pipefail
set -o nounset

log() {
    local MESSAGE="${1}"
    echo "${MESSAGE}" 1>&2
}

get_aks_deployed_images() {
    local REGISTRY_NAME="${1}"

    local DEPLOYED_IMAGES=()
    local CONSOLIDATED_DEPLOYED_IMAGES=()

    local CLUSTERS
    CLUSTERS=$(az aks list --query "[].{name:name, resourceGroup:resourceGroup}" --output json)

    for ROW in $(jq -r '.[] | @base64' <<<"${CLUSTERS}"); do
        _jq() {
            base64 --decode <<<"${ROW}" | jq -r "${1}"
        }

        local CLUSTER
        CLUSTER=$(_jq '.name')

        local RESOURCE_GROUP
        RESOURCE_GROUP=$(_jq '.resourceGroup')

        az aks get-credentials \
            --overwrite \
            --name "${CLUSTER}" \
            --resource-group "${RESOURCE_GROUP}" \
            --admin

        mapfile -t DEPLOYED_IMAGES <<<"$(kubectl get pods \
            --all-namespaces \
            --output jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}' |
            grep "${REGISTRY_NAME}" | sort | uniq)"

        local MIN_EXPECTED_DEPLOYED_IMAGES=3

        if [[ ${#DEPLOYED_IMAGES[@]} -lt ${MIN_EXPECTED_DEPLOYED_IMAGES} && "${CLUSTER}" != *"app-tests"* ]]; then
            log "ERROR: The number of deployed images fetched from the ${CLUSTER} cluster is ${#DEPLOYED_IMAGES[@]}, but a minimum of ${MIN_EXPECTED_DEPLOYED_IMAGES} is expected"
            exit 1
        fi

        log "INFO: A total of ${#DEPLOYED_IMAGES[@]} unique images (listed below) are currently deployed to the ${CLUSTER} cluster:"
        tr ' ' '\n' <<<"${DEPLOYED_IMAGES[@]}" >&2

        CONSOLIDATED_DEPLOYED_IMAGES+=("${DEPLOYED_IMAGES[@]} ")
    done

    echo "${CONSOLIDATED_DEPLOYED_IMAGES[*]}"
}

get_function_app_deployed_images() {
    local REGISTRY_NAME="${1}"

    local CONSOLIDATED_DEPLOYED_IMAGES=()

    local FUNCTION_APPS
    FUNCTION_APPS=$(
        az functionapp list \
            --query "[?contains(kind, 'container')].{name:name, resourceGroup:resourceGroup}" \
            --output json
    )

    for ROW in $(jq -r '.[] | @base64' <<<"${FUNCTION_APPS}"); do
        _jq() {
            base64 --decode <<<"${ROW}" | jq -r "${1}"
        }

        local FUNCTION_APP
        FUNCTION_APP=$(_jq '.name')

        local RESOURCE_GROUP
        RESOURCE_GROUP=$(_jq '.resourceGroup')

        local DEPLOYED_IMAGE_TAG
        DEPLOYED_IMAGE_TAG=$(
            az functionapp config container show \
                --name "${FUNCTION_APP}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[?name=='DOCKER_CUSTOM_IMAGE_NAME' && contains(value, '${REGISTRY_NAME}')].value" \
                --output tsv
        )

        if [[ -z "${DEPLOYED_IMAGE_TAG}" ]]; then
            log "ERROR: Unable to fetch the deployed image tag for the function app ${FUNCTION_APP}"
            exit 1
        fi

        local IMAGE_DIGEST
        IMAGE_DIGEST=$(
            az acr repository show \
                --name "${REGISTRY_NAME}" \
                --image "func:${DEPLOYED_IMAGE_TAG##*:}" \
                --query "digest" \
                --output tsv
        )

        if [[ -z "${IMAGE_DIGEST}" ]]; then
            log "ERROR: Unable to fetch the deployed image digest for the function app ${FUNCTION_APP}"
            exit 1
        fi

        local DEPLOYED_IMAGE="${REGISTRY_NAME}.azurecr.io/func@${IMAGE_DIGEST}"

        log "INFO: The deployed image for the function app ${FUNCTION_APP} is ${DEPLOYED_IMAGE}"

        CONSOLIDATED_DEPLOYED_IMAGES+=("${DEPLOYED_IMAGE} ")
    done

    echo "${CONSOLIDATED_DEPLOYED_IMAGES[*]} "
}

main() {
    local REGISTRY_NAME="${1}"

    local AKS_DEPLOYED_IMAGES
    AKS_DEPLOYED_IMAGES=$(get_aks_deployed_images "${REGISTRY_NAME}")

    local FUNCTION_APP_DEPLOYED_IMAGES
    FUNCTION_APP_DEPLOYED_IMAGES=$(get_function_app_deployed_images "${REGISTRY_NAME}")

    local ALL_DEPLOYED_IMAGES=("${AKS_DEPLOYED_IMAGES[*]}" "${FUNCTION_APP_DEPLOYED_IMAGES[*]}")
    echo "##vso[task.setvariable variable=deployed_images;isOutput=true]${ALL_DEPLOYED_IMAGES[*]}"
}

main "${@}"
