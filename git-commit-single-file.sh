#!/usr/bin/env bash

################################################################################
# Script Name    : git-commit-single-file.sh
# Description    : Used to git commit changes to single files
# Args           : FILE COMMIT_MESSAGE
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
################################################################################

set -o errexit
set -o pipefail
set -o nounset

function log() {
    local MESSAGE="${1}"
    echo "${MESSAGE}" 1>&2
}

function usage() {
    log "ERROR: Missing or invalid arguments"
    log "Usage example: ${0} FILE COMMIT_MESSAGE"
    exit 1
}

if [[ "${#}" -ne 2 ]]; then
    usage
fi

FILE="${1}"
COMMIT_MESSAGE="${2}"

DIFF=$(git diff "${FILE}")

if [[ -z "${DIFF}" ]]; then
    log "ERROR: No changes to commit"
    exit 1
else
    log "INFO: The following changes have been made to the ${FILE} file:"
    log "${DIFF}"

    AUTHOR_NAME=$(git log -1 --pretty=format:'%an')
    AUTHOR_EMAIL=$(git log -1 --pretty=format:'%ae')

    log "INFO: Using as author: ${AUTHOR_NAME} <${AUTHOR_EMAIL}>"
    git config user.name "${AUTHOR_NAME}"
    git config user.email "${AUTHOR_EMAIL}"

    git add "${FILE}"
    git commit -m "${COMMIT_MESSAGE}"
fi
