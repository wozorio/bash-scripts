#!/usr/bin/env bash

######################################################################
# Script Name    : kv-notify-expiring-secrets.sh
# Description    : Used to send notification via MS Teams about Key Vault
#                  secrets that will expire in XX days or less
# Args           : KEYVAULT_NAME RESOURCE_GROUP HOOK THRESHOLD
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail
set -o nounset

function usage() {
    echo "Usage: $0 [OPTIONS]"
    echo -e "\t-k Key Vault name"
    echo -e "\t-g Resource group"
    echo -e "\t-h Hook secret"
    echo -e "\t-t Threshold"
    exit 1
}

THRESHOLD=60

while getopts "k:g:h:t:" OPTION; do
    case "$OPTION" in
    k)
        KEYVAULT_NAME=$OPTARG
        ;;

    g)
        RESOURCE_GROUP=$OPTARG
        ;;

    h)
        HOOK=$OPTARG
        ;;

    t)
        THRESHOLD=$OPTARG
        ;;

    *)
        usage
        ;;
    esac
done

function fetch_secrets() {
    local KEYVAULT_SECRETS=$(az keyvault secret list --vault-name ${KEYVAULT_NAME} --query "[].name" --output tsv)

    echo "${KEYVAULT_SECRETS}"
}

function send_notification() {
    local MESSAGE="<strong><blockquote><h1>[SKID] - The secret ${SECRET_NAME} about to expire</h1></blockquote></strong> \n<br/>\n</p> 
    <p><strong>Secret Name:</strong> ${SECRET_NAME}</p> \
    <p><strong>Key Vault Name:</strong> ${KEYVAULT_NAME}</p> \
    <p><strong>Expiration date:</strong> ${SECRET_EXPIRY_DATE_SHORT}</p> \
    <p><strong>Remaining Days:</strong> ${DATE_DIFF}</p>"

    echo "Sending out notification via MS-Teams"
    curl \
        -H 'Content-Type: application/json' \
        -d "{\"text\": \"${MESSAGE}\"}" ${HOOK}

    if [[ "${?}" -ne 0 ]]; then
        echo "ERROR: Failed sending notification!"
        exit 1
    fi
}

function notify_engineers() {
    KEYVAULT_SECRETS=$(fetch_secrets)

    echo "${KEYVAULT_SECRETS[@]}" | while read -r SECRET_NAME; do
        # Get the secret expiration date
        SECRET_EXPIRY_DATE=$(az keyvault secret show --name ${SECRET_NAME} --vault-name ${KEYVAULT_NAME} --query attributes.expires -o tsv)

        if [[ -n "${SECRET_EXPIRY_DATE}" ]]; then
            # Convert the secret expiration date into seconds
            SECRET_EXPIRY_DATE_SHORT=$(date -d ${SECRET_EXPIRY_DATE} +%d-%b-%Y)
            SECRET_EXPIRY_DATE_SECS=$(date -d ${SECRET_EXPIRY_DATE} +%s)

            # Convert the current date into seconds
            CURRENT_DATE_SECS=$(date -d now +%s)

            # Calculate how many days are left for the secret to expire
            DATE_DIFF=$(((${SECRET_EXPIRY_DATE_SECS} - ${CURRENT_DATE_SECS}) / 86400))

            if [[ "${DATE_DIFF}" -le "${THRESHOLD}" ]]; then
                echo "WARNING: Key Vault secret ${SECRET_NAME} will expire on ${SECRET_EXPIRY_DATE_SHORT}"
                send_notification
            else
                echo "INFO: Nothing to worry about. Secret will expire only in ${DATE_DIFF} days from now. To be more precise on ${SECRET_EXPIRY_DATE_SHORT}"
            fi
        fi
    done
}

notify_engineers
