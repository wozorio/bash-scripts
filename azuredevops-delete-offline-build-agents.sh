#!/usr/bin/env bash

################################################################################
# Script Name    : azuredevops-delete-offline-build-agents.sh
# Description    : Used to batch delete offline build agents from a specified agent pool
# Args           : PERSONAL_ACCESS_TOKEN ORGANIZATION_NAME AGENT_POOL_NAME [API_VERSION]
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
################################################################################

set -o errexit
set -o pipefail
set -o nounset

PERSONAL_ACCESS_TOKEN="${1}"
ORGANIZATION_NAME="${2}"
AGENT_POOL_NAME="${3}"
API_VERSION="${4:-"7.2-preview.1"}"

AGENT_POOLS_URI="https://dev.azure.com/${ORGANIZATION_NAME}/_apis/distributedtask/pools?api-version=${API_VERSION}"
BASE64_PAT=$(printf "%s" ":${PERSONAL_ACCESS_TOKEN}" | base64)
HEADER="Authorization: Basic ${BASE64_PAT}"

function log() {
    local MESSAGE="${1}"
    echo "${MESSAGE}" 1>&2
}

AZURE_DEVOPS_RESPONSE_CODE=$(
    curl --silent --header "${HEADER}" "${AGENT_POOLS_URI}" -o /dev/null --write-out "%{http_code}"
)

if [[ ${AZURE_DEVOPS_RESPONSE_CODE} -lt 200 || ${AZURE_DEVOPS_RESPONSE_CODE} -gt 299 ]]; then
    log "ERROR: Failed accessing Azure DevOps API with HTTP code ${AZURE_DEVOPS_RESPONSE_CODE}"
    exit 1
fi

AGENT_POOL=$(curl -s -H "${HEADER}" "${AGENT_POOLS_URI}" | jq --arg AGENT_POOL_NAME "$AGENT_POOL_NAME" '.value[] | select(.name == $AGENT_POOL_NAME)')
if [[ -z "$AGENT_POOL" ]]; then
    log "ERROR: ${AGENT_POOL_NAME} agent pool not found in ${ORGANIZATION_NAME} organization"
    exit 1
fi

AGENT_POOL_ID=$(jq -r '.id' <<<"${AGENT_POOL}")
AGENTS_URI="https://dev.azure.com/${ORGANIZATION_NAME}/_apis/distributedtask/pools/${AGENT_POOL_ID}/agents?api-version=${API_VERSION}"

OFFLINE_AGENTS=$(curl -s -H "${HEADER}" "${AGENTS_URI}" | jq '.value[] | select(.status == "offline")')
if [[ -z "$OFFLINE_AGENTS" ]]; then
    log "INFO: No offline agents found in ${AGENT_POOL_NAME} agent pool"
    exit 0
fi

jq -r '.id' <<<"${OFFLINE_AGENTS}" | while IFS= read -r AGENT; do
    log "WARN: Deleting offline agent ID ${AGENT} from ${AGENT_POOL_NAME} agent pool in ${ORGANIZATION_NAME} organization"
    curl \
        --request DELETE \
        --url "https://dev.azure.com/${ORGANIZATION_NAME}/_apis/distributedtask/pools/${AGENT_POOL_ID}/agents/${AGENT}?api-version=${API_VERSION}" \
        --header "${HEADER}" \
        --silent \
        --fail >/dev/null || {
        log "ERROR: Failed deleting offline agent ID ${AGENT} from ${AGENT_POOL_NAME} agent pool in ${ORGANIZATION_NAME} organization"
        exit 1
    }
done
