#!/usr/bin/env bash

################################################################################
# Script Name    : bump-semantic-version.sh
# Description    : Used to bump semantic version based on PR titles following
#                  slightly adapted conventional commits specification (break, feat, fix)
#                  Conventional Commits spec: https://www.conventionalcommits.org/
# Args           : CURRENT_VERSION INCREMENT_VERSION_TYPE
# Author         : Wellington Ozorio <wozorio@duck.com>
################################################################################

set -o pipefail
set -o nounset

function log() {
    local MESSAGE="${1}"
    echo "${MESSAGE}" 1>&2
}

function usage() {
    log "ERROR: Missing or invalid arguments"
    log "Usage example: ${0} CURRENT_VERSION INCREMENT_VERSION_TYPE"
    exit 1
}

if [[ "${#}" -ne 2 ]]; then
    usage
fi

CURRENT_VERSION="$1"
INCREMENT_VERSION_TYPE="$2"

if [[ -z "${CURRENT_VERSION}" ]]; then
    log "ERROR: Could not read previous version! Please ensure the version to be incremented is passed"
    exit 1
fi

SUPPORTED_VERSION_TYPES="break feat fix"

if [[ ! "${SUPPORTED_VERSION_TYPES[*]}" =~ ${INCREMENT_VERSION_TYPE} ]]; then
    log "ERROR: Invalid version type. Supported types are [ ${SUPPORTED_VERSION_TYPES} ]"
    exit 1
fi

SEMANTIC_VERSION_REGEX="^([0-9]+)[/./]([0-9]+)[/./]([0-9]+?$)"

if [[ "${CURRENT_VERSION}" =~ ${SEMANTIC_VERSION_REGEX} ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
else
    log "ERROR: Current version ${CURRENT_VERSION} is not a semantic version!"
    exit 1
fi

case "${INCREMENT_VERSION_TYPE}" in
"break")
    ((++MAJOR))
    MINOR=0
    PATCH=0
    ;;

"feat")
    ((++MINOR))
    PATCH=0
    ;;

"fix")
    ((++PATCH))
    ;;
esac

NEXT_VERSION="${MAJOR}.${MINOR}.${PATCH}"
log "INFO: Version will be bumped from ${CURRENT_VERSION} to ${NEXT_VERSION}"
echo "##vso[task.setvariable variable=next_version]${NEXT_VERSION}"
