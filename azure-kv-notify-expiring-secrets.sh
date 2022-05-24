#!/usr/bin/env bash

######################################################################
# Script Name    : kv-notify-expiring-secrets.sh
# Description    : Used to send notification via e-mail about Key Vault
#                  secrets that will expire in XX days or less
# Args           : KEYVAULT_NAME HOOK THRESHOLD
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail
set -o nounset

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ${0} KEYVAULT_NAME SENDER RECIPIENT API_KEY THRESHOLD (OPTIONAL)"
    exit 1
}

# Check if the right number of arguments were passed
if [[ "${#}" -lt 4 ]]; then
    usage
fi

KEYVAULT_NAME=$1
SENDER=$2
RECIPIENT=$3
API_KEY=$4

# Define default value of 60 (days) for the THRESHOLD variable if an argument in the 5th position is not passed
THRESHOLD=${5:-60}

function fetch_secrets() {
    local KEYVAULT_SECRETS

    KEYVAULT_SECRETS=$(az keyvault secret list --vault-name "${KEYVAULT_NAME}" --query "[].name" --output tsv)

    echo "${KEYVAULT_SECRETS}"
}

function send_email() {
    local EMAIL_API="https://api.sendgrid.com/v3/mail/send"

    local SUBJECT="KeyVault secret ${SECRET} about to expire"

    local MESSAGE="<p> Dear Site Reliability Engineer, </p> \
        <p> This is to notify you that the Key Vault secret <b>${SECRET}</b> will expire on <b>${SECRET_EXPIRY_DATE_SHORT}</b>. </p> \
        <p> Please ensure the secret is rotated in a timely fashion. There are ${DATE_DIFF} days remaining. </p> \
        <p> Sincerely yours, <br>DevOps Team </p>"

    local REQUEST_DATA='{
        "personalizations": [
            {
                "to": [{"email": "'${RECIPIENT}'"}],
                "dynamic_template_data": { "first_name": "Operations" }
            }
        ],
        "from": {"email": "'${SENDER}'"},
        "subject":"'${SUBJECT}'",
        "content": [{"type": "text/html", "value": "'${MESSAGE}'"}]
    }'

    echo "INFO: Sending out notification via e-mail"
    CURL_HTTP_CODE=$(
        curl \
            --request POST \
            --url "${EMAIL_API}" \
            --header "Authorization: Bearer ${API_KEY}" \
            --header "Content-Type: application/json" \
            --data "${REQUEST_DATA}" \
            --output /dev/null \
            --write-out "%{http_code}" \
            --silent
    )

    if [[ "${CURL_HTTP_CODE}" -lt 200 || "${CURL_HTTP_CODE}" -gt 299 ]]; then
        echo "ERROR: Failed sending notification with error code ${CURL_HTTP_CODE}!"
        exit 1
    fi
}

function main() {
    KEYVAULT_SECRETS=$(fetch_secrets)

    for SECRET in ${KEYVAULT_SECRETS}; do
        # Get the secret expiration date
        SECRET_EXPIRY_DATE=$(az keyvault secret show --name "${SECRET}" --vault-name "${KEYVAULT_NAME}" --query attributes.expires -o tsv)

        if [[ -n "${SECRET_EXPIRY_DATE}" ]]; then
            # Convert the secret expiration date into seconds
            SECRET_EXPIRY_DATE_SHORT=$(date -d "${SECRET_EXPIRY_DATE}" +%d-%b-%Y)
            SECRET_EXPIRY_DATE_SECS=$(date -d "${SECRET_EXPIRY_DATE}" +%s)

            # Convert the current date into seconds
            CURRENT_DATE_SECS=$(date -d now +%s)

            # Calculate how many days are left for the secret to expire
            DATE_DIFF=$(((SECRET_EXPIRY_DATE_SECS - CURRENT_DATE_SECS) / 86400))

            if [[ "${DATE_DIFF}" -le "${THRESHOLD}" ]]; then
                echo "WARNING: Oops! Key Vault secret ${SECRET} will expire in ${DATE_DIFF} days."
                send_email
            else
                echo "INFO: Nothing to worry about. Secret will expire only in ${DATE_DIFF} days from now. To be more precise on ${SECRET_EXPIRY_DATE_SHORT}"
            fi
        fi
    done
}

main
