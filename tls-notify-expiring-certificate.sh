#!/usr/bin/env bash

######################################################################
# Script Name    : tls-notify-expiring-certificate.sh
# Description    : Used to send notification via e-mail about TLS
#                  certificates that will expire in XX days or less using Mailjet
# Args           : URL SENDER RECIPIENT API_PUBLIC_KEY API_PRIVATE_KEY THRESHOLD (OPTIONAL)
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail
set -o nounset

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ${0} URL SENDER RECIPIENT API_KEY THRESHOLD (OPTIONAL)"
    exit 1
}

# Check if the right number of arguments were passed
if [[ "${#}" -lt 4 ]]; then
    usage
fi

URL=$1
SENDER=$2
RECIPIENT=$3
API_KEY=$4

# Define default value of 60 (days) for the THRESHOLD variable if an argument in the 5th position is not passed
THRESHOLD=${5:-60}

function check_url() {
    if ! host "${URL}" >/dev/null; then
        echo "ERROR: URL could not be resolved. Please ensure the correct address is passed."
        exit 1
    fi
}

function fetch_certificate() {
    # Check whether the URL can be resolved
    check_url

    # Define temp file used to store the certificate
    local CERT_FILE
    CERT_FILE=$(mktemp)

    echo -n | timeout 5 openssl s_client -servername "${URL}" -connect "${URL}":443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >"${CERT_FILE}"

    local CERTIFICATE_SIZE
    CERTIFICATE_SIZE=$(stat -c "%s" "${CERT_FILE}")

    if [[ "${CERTIFICATE_SIZE}" -lt 1 ]]; then
        echo "ERROR: Could not read the expiration date of the certificate. Please check the TLS settings of the web server."
        exit 1
    fi

    echo "${CERT_FILE}"
}

function send_email() {
    local EMAIL_API="https://api.sendgrid.com/v3/mail/send"

    local SUBJECT="TLS certificate for ${URL} about to expire"

    local MESSAGE="<p> Dear Site Reliability Engineer, </p> \
        <p> This is to notify you that the TLS certificate for <b>${URL}</b> will expire on <b>${CERT_EXPIRY_DATE_SHORT}</b>. </p> \
        <p> Please ensure a new certificate is ordered and installed in a timely fashion. There are ${DATE_DIFF} days remaining. </p> \
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
    local CERT_FILE
    CERT_FILE=$(fetch_certificate) || exit $?

    # Delete temp file on exit
    trap "unlink ${CERT_FILE}" EXIT

    # Get certificate expiration date
    local CERT_EXPIRY_DATE
    CERT_EXPIRY_DATE=$(openssl x509 -in "${CERT_FILE}" -enddate -noout | sed "s/.*=\(.*\)/\1/")

    local CERT_EXPIRY_DATE_SHORT
    CERT_EXPIRY_DATE_SHORT=$(date -d "${CERT_EXPIRY_DATE}" +%d-%b-%Y)

    # Convert certificate expiration date into seconds
    local CERT_EXPIRY_DATE_SECS
    CERT_EXPIRY_DATE_SECS=$(date -d "${CERT_EXPIRY_DATE}" +%s)

    # Convert current date into seconds
    local CURRENT_DATE_SECS
    CURRENT_DATE_SECS=$(date -d now +%s)

    # Calculate how many days are left for the certificate to expire
    local DATE_DIFF
    DATE_DIFF=$(((CERT_EXPIRY_DATE_SECS - CURRENT_DATE_SECS) / 86400))

    # Check if certificate will expire before the threshold
    if [[ "${DATE_DIFF}" -le "${THRESHOLD}" ]]; then
        echo "WARNING: Oops! Certificate will expire in ${DATE_DIFF} days."
        send_email
    else
        echo "INFO: Nothing to worry about. TLS certificate will expire only in ${DATE_DIFF} days from now. To be more precise on ${CERT_EXPIRY_DATE_SHORT}"
    fi
}

main "$@"
