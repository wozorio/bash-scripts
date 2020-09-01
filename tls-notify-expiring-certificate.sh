#!/bin/bash

######################################################################
# Script Name    : tls-notify-expiring-certificate.sh
# Description    : Used to send notification via e-mail about TLS
#                  certificates that will expire in 60 days or less using Mailjet
# Args           : WEBSITE SENDER RECIPIENT MJ_APIKEY_PUBLIC MJ_APIKEY_PRIVATE
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

# Stop execution on any error
set -e

function usage() {
  echo "ERROR: Missing or invalid arguments!"
  echo "Usage example: ./notify-expiring-tls-certificate.sh WEBSITE SENDER RECIPIENT MJ_APIKEY_PUBLIC MJ_APIKEY_PRIVATE"
  exit 1
}

# Check if the right number of arguments were passed
if [[ $# -lt 5 ]] || [[ $# -gt 5 ]]; then
  usage
fi

# Declare variables
WEBSITE=$1
SENDER=$2
RECIPIENT=$3
MJ_APIKEY_PUBLIC=$4
MJ_APIKEY_PRIVATE=$5

# Temporary file used to store the certificate
CERT_FILE=$(mktemp)

# Delete temporary file on exit
trap "unlink ${CERT_FILE}" EXIT

# Check whether the address of the website can be resolved
host ${WEBSITE} >&-
if [ ${?} -eq "0" ]; then
  echo -n | timeout 5 openssl s_client -servername ${WEBSITE} -connect ${WEBSITE}:443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >${CERT_FILE}
else
  echo "ERROR: Website could not be resolved. Please ensure the correct address is passed."
  exit 1
fi

CERTIFICATE_SIZE=$(stat -c "%s" ${CERT_FILE})

if [ "${CERTIFICATE_SIZE}" -gt "1" ]; then
  # Get the certificate expiration date
  CERT_EXPIRY_DATE=$(openssl x509 -in ${CERT_FILE} -enddate -noout | sed "s/.*=\(.*\)/\1/")
  CERT_EXPIRY_DATE_SHORT=$(date -d "${CERT_EXPIRY_DATE}" +%d-%b-%Y)

  # Convert the certificate expiration date into seconds
  CERT_EXPIRY_DATE_SECS=$(date -d "${CERT_EXPIRY_DATE}" +%s)

  # Convert the current date into seconds
  CURRENT_DATE_SECS=$(date -d now +%s)

  # Calculate how many days are left for the certificate to expire
  DATE_DIFF=$(((${CERT_EXPIRY_DATE_SECS} - ${CURRENT_DATE_SECS}) / 86400))

  # Check if the certificate will expire in 20 days or earlier
  if [[ 60 -gt ${DATE_DIFF} ]]; then
    echo "WARNING: Oops! Certificate will expire in ${DATE_DIFF} days."
    SUBJECT="TLS certificate for ${WEBSITE} about to expire"
    MESSAGE="<p> Dear SysAdmin, </p> \
    <p> This is to notify you that the TLS certificate for the address <b>${WEBSITE}</b> will expire on <b>${CERT_EXPIRY_DATE_SHORT}</b>. </p> \
    <p> Please ensure a new certificate is ordered and installed in a timely fashion. There are ${DATE_DIFF} days remaining. </p> \
    <p> Sincerely yours, </p> \
    <p> DevOps Team </p>"

    REQUEST_DATA='{
      "FromEmail":"'${SENDER}'",
      "FromName":"Operations",
      "Subject": "'${SUBJECT}'",
      "Html-part":"'${MESSAGE}'",
      "To":"'${RECIPIENT}'",
    }'

    echo "Sending out notification via e-mail"
    curl \
    -s \
    -X POST \
    --user ${MJ_APIKEY_PUBLIC}:${MJ_APIKEY_PRIVATE} \
    https://api.mailjet.com/v3/send \
    -H 'Content-Type: application/json' \
    -d "${REQUEST_DATA}"
  else
    echo "INFO: Nothing to worry about. TLS certificate will expire only in ${DATE_DIFF} days from now. To be more precise on ${CERT_EXPIRY_DATE_SHORT}"
  fi

else
  echo "ERROR: Could not read the expiration date of the certificate. Please check the TLS settings of the website."
  exit 1
fi
