#!/usr/bin/env bash

################################################################################
# Script Name    : azuredevops-delete-queued-builds.sh
# Description    : Used to batch delete queued builds ("pipeline runs")
# Args           : PERSONAL_ACCESS_TOKEN ORGANIZATION_NAME PROJECT_NAME [API_VERSION]
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
################################################################################

set -o errexit
set -o pipefail
set -o nounset

PERSONAL_ACCESS_TOKEN="${1}"
ORGANIZATION_NAME="${2}"
PROJECT_NAME="${3}"
API_VERSION="${4:-"7.1-preview.7"}"

NOT_STARTED_BUILDS_URI="https://dev.azure.com/${ORGANIZATION_NAME}/${PROJECT_NAME}/_apis/build/builds?statusFilter=notStarted&${API_VERSION}"
BASE64_PAT=$(printf "%s" ":${PERSONAL_ACCESS_TOKEN}" | base64)
HEADER="Authorization: Basic ${BASE64_PAT}"

function log() {
    local MESSAGE="${1}"
    echo "${MESSAGE}" 1>&2
}

AZURE_DEVOPS_RESPONSE_CODE=$(
    curl -s -H "${HEADER}" "${NOT_STARTED_BUILDS_URI}" -o /dev/null --w "%{http_code}"
)

if [[ ${AZURE_DEVOPS_RESPONSE_CODE} -lt 200 || ${AZURE_DEVOPS_RESPONSE_CODE} -gt 299 ]]; then
    log "ERROR: Failed accessing Azure DevOps API with error code ${AZURE_DEVOPS_RESPONSE_CODE}"
    exit 1
fi

QUEUED_BUILDS=$(curl -s -H "${HEADER}" "${NOT_STARTED_BUILDS_URI}" | jq '.value[].id')
if [[ -z "${QUEUED_BUILDS}" ]]; then
    log "INFO: No queued builds found to be deleted"
    exit 0
fi

jq -r <<<"${QUEUED_BUILDS}" | while IFS= read -r BUILD; do
    log "WARN: Deleting ${BUILD} queued build"
    curl \
        --request DELETE \
        --url "https://dev.azure.com/${ORGANIZATION_NAME}/${PROJECT_NAME}/_apis/build/builds/${BUILD}?api-version=${API_VERSION}" \
        --header "${HEADER}" \
        --silent \
        --fail >/dev/null || {
        log "ERROR: Failed deleting ${BUILD} queued build"
        exit 1
    }
done
