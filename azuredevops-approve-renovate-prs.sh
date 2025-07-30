#!/usr/bin/env bash

################################################################################
# Script Name    : azuredevops-approve-renovate-prs.sh
# Description    : Used to approve PRs created by Renovate bot
# Args           : ORGANIZATION PROJECT REPOSITORY
# Author         : Wellington Ozorio <wozorio@duck.com>
################################################################################

set -o errexit
set -o pipefail
set -o nounset

function log() {
    local MESSAGE="${1}"
    echo "${MESSAGE}" 1>&2
}

function usage() {
    log "Usage: ${0} ORGANIZATION PROJECT REPOSITORY"
    exit 1
}

function check_required_env_var() {
    local ENV_VAR="${1}"

    if [[ -z "${ENV_VAR}" ]]; then
        log "ERROR: ${ENV_VAR} environment variable is required"
        exit 1
    fi
}

function get_pull_requests() {
    log "INFO: Fetching PRs created by Renovate bot"
    az repos pr list \
        --org "${ORGANIZATION}" \
        --project "${PROJECT}" \
        --repository "${REPOSITORY}" \
        --status active \
        --query "[?contains(sourceRefName, 'renovate/')].pullRequestId" \
        --output tsv
}

function approve_pull_request() {
    local PULL_REQUEST="${1}"

    log "INFO: Approving PR#${PULL_REQUEST}"
    az repos pr set-vote \
        --id "${PULL_REQUEST}" \
        --vote approve \
        --org "${ORGANIZATION}"
}

function main() {
    if [[ "${#}" -ne 3 ]]; then
        usage
    fi

    ORGANIZATION="${1}"
    PROJECT="${2}"
    REPOSITORY="${3}"

    check_required_env_var "AZURE_DEVOPS_EXT_PAT"

    PULL_REQUESTS_TO_APPROVE=$(get_pull_requests "${REPOSITORY}")
    if [[ -z "${PULL_REQUESTS_TO_APPROVE}" ]]; then
        echo "INFO: No Renovate PRs to approve, exiting..."
        exit 0
    fi

    for PULL_REQUEST in ${PULL_REQUESTS_TO_APPROVE}; do
        approve_pull_request "${PULL_REQUEST}"
    done
}

main "${@}"
