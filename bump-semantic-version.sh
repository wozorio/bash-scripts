#!/usr/bin/env bash

######################################################################
# Script Name    : bump-semantic-version.sh
# Description    : Used to bump semantic version based on PR titles following conventional commits specification (break, feat, fix)
#                  Conventional Commits specification reference: https://www.conventionalcommits.org/en/v1.0.0/
# Args           : CURRENT_VERSION INCREMENT_VERSION_TYPE
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail
set -o nounset

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ${0} CURRENT_VERSION INCREMENT_VERSION_TYPE"
    exit 1
}

if [[ "${#}" -ne 2 ]]; then
    usage
fi

CURRENT_VERSION="$1"
INCREMENT_VERSION_TYPE="$2"

if [[ -z "${CURRENT_VERSION}" ]]; then
    echo "ERROR: Could not read previous version! Please ensure the version to be incremented is passed."
    exit 1
fi

SUPPORTED_VERSION_TYPES="break feat fix"

if [[ ! "${SUPPORTED_VERSION_TYPES[*]}" =~ "${INCREMENT_VERSION_TYPE}" ]]; then
    echo "ERROR: Invalid version type! Supported types are [ ${SUPPORTED_VERSION_TYPES} ]!"
    exit 1
fi

SEMANTIC_VERSION_REGEX="^([0-9]+)[/./]([0-9]+)[/./]([0-9]+?$)"

if [[ "${CURRENT_VERSION}" =~ ${SEMANTIC_VERSION_REGEX} ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
else
    echo "ERROR: Current version ${CURRENT_VERSION} is not a semantic version!"
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
echo "Bump semantic version: ${CURRENT_VERSION} -> ${NEXT_VERSION}"

# Define an output variable in Azure DevOps
echo "##vso[task.setvariable variable=next_version;isOutput=true]${NEXT_VERSION}"
