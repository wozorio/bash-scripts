#!/usr/bin/env bash

################################################################################
# Script Name    : azure-storage-account-copy-files.sh
# Description    : Used to copy files with proper MIME types to an Azure blob 
#                  storage using GNU parallel
# Args           : N/A
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
################################################################################

set -e

function log() {
    local MESSAGE="${1}"
    echo "${MESSAGE}" 1>&2
}

function usage() {
    log "Usage:"
    log "-n Storage account name"
    log "-r Storage account resource group"
    log "-c The container name"
    exit 1
}

function get_args() {
    local OPTIND
    while getopts "n:r:c:" OPTION; do
        case "$OPTION" in
        n)
            export STORAGE_ACCOUNT_NAME=$OPTARG
            ;;
        r)
            export RESOURCE_GROUP=$OPTARG
            ;;
        c)
            export CONTAINER_NAME=$OPTARG
            ;;
        *)
            usage
            ;;
        esac
    done
}

function define_mime_types() {
    declare -gA MIME_TYPES=(
        ["avif"]="image/avif"
        ["css"]="text/css"
        ["gif"]="image/gif"
        ["jpg"]="image/jpeg"
        ["js"]="text/javascript"
        ["mjs"]="text/javascript"
        ["png"]="image/png"
        ["svg"]="image/svg+xml"
        ["txt"]="text/plain"
        ["webp"]="image/webp"
        ["woff"]="font/woff"
        ["woff2"]="font/woff2"
    )
}

function get_files_to_upload() {
    local FILES
    FILES=$(find . -name "*.*")
    echo "${FILES}"
}

function get_connection_string() {
    local CONNECTION_STRING
    CONNECTION_STRING=$(
        az storage account show-connection-string \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --output tsv
    )

    if [[ -z "${CONNECTION_STRING}" ]]; then
        log "ERROR: Storage account connection string could not be fetched"
        exit 1
    fi

    echo "${CONNECTION_STRING}"
}

function upload_file_to_storage_account() {
    local FILEPATH="${1}"
    define_mime_types

    if ! [[ "${!MIME_TYPES[*]}" =~ ${FILEPATH##*.} ]]; then
        log "ERROR: No MIME type has been defined for '${FILEPATH##*.}' file extension"
        exit 1
    fi

    local CONNECTION_STRING
    CONNECTION_STRING=$(get_connection_string)

    for FILE_EXTENSION in "${!MIME_TYPES[@]}"; do
        if [[ "${FILE_EXTENSION}" == "${FILEPATH##*.}" ]]; then
            log "INFO: Uploading ${FILEPATH} with MIME type set to ${MIME_TYPES[$FILE_EXTENSION]}"
            az storage blob upload \
                --account-name "${STORAGE_ACCOUNT_NAME}" \
                --connection-string "${CONNECTION_STRING}" \
                --container-name "${CONTAINER_NAME}" \
                --file "${FILEPATH}" \
                --name "${FILEPATH#"./"}" \
                --content-type "${MIME_TYPES[$FILE_EXTENSION]}" \
                --no-progress \
                --overwrite
        fi
    done
}

function main() {
    get_args "$@"

    export -f log
    export -f define_mime_types
    export -f get_connection_string
    export -f upload_file_to_storage_account

    local FILES_TO_UPLOAD
    FILES_TO_UPLOAD=$(get_files_to_upload)

    parallel --halt-on-error 2 --jobs 50 upload_file_to_storage_account ::: "${FILES_TO_UPLOAD}"
}

main "$@"
