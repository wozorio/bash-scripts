#!/bin/bash

######################################################################
# Script Name    : event-grid-subscription-update-access-token.sh
# Description    : Used to update the webhook Url of domain Event Grid
#                  subscriptions with a new access token
# Args           : SUBSCRIPTION_ID OAUTH2_TOKEN_ENDPOINT EVENT_GRID_DOMAIN CLIENT_ID CLIENT_SECRET
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

# Stop execution on any error
set -e

function usage() {
  echo "ERROR: Missing or invalid arguments!"
  echo "Usage example: ./event-grid-subscription-update-access-token.sh SUBSCRIPTION_ID OAUTH2_TOKEN_ENDPOINT EVENT_GRID_DOMAIN CLIENT_ID CLIENT_SECRET"
  exit 1
}

# Check if the right number of arguments was passed
if [[ $# -ne 5 ]]; then
  usage
fi

# Declare variables
SUBSCRIPTION_ID=$1
OAUTH2_TOKEN_ENDPOINT=$2
EVENT_GRID_DOMAIN=$3
CLIENT_ID=$4
CLIENT_SECRET=$5

RESOURCE_GROUP="RG_${EVENT_GRID_DOMAIN}"

# List Event Grid domain topics
EVENT_GRID_TOPICS=$(az eventgrid domain topic list \
  -g ${RESOURCE_GROUP} \
  --domain-name ${EVENT_GRID_DOMAIN} \
  --query [].name \
  --output tsv)

if [[ -n ${EVENT_GRID_TOPICS} ]]; then
  # Iterate over each topic
  echo "${EVENT_GRID_TOPICS[@]}" | while read -r topic; do
    EVENT_GRID_SUBSCRIPTIONS=$(az eventgrid event-subscription list \
      --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/domains/${EVENT_GRID_DOMAIN}/topics/${topic}" \
      --query [].name \
      --output tsv)

    if [[ -n ${EVENT_GRID_SUBSCRIPTIONS} ]]; then
      # Iterate over each subscription
      echo "${EVENT_GRID_SUBSCRIPTIONS[@]}" | while read -r subscription; do
        # Encode the client credentials with base64
        ENCODED_CLIENT_CREDENTIALS=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64 -w 0)

        echo "Getting an access token for the subscription ${subscription}"
        ACCESS_TOKEN=$(curl --request POST \
          --url ${OAUTH2_TOKEN_ENDPOINT} \
          --header "Accept:application/json" \
          --header "Authorization:Basic ${ENCODED_CLIENT_CREDENTIALS}" \
          --data grant_type=client_credentials \
          --data client_id=${CLIENT_ID} \
          --data client_secret=${CLIENT_SECRET} \
          --data scope=${subscription} |
          jq '.access_token' |
          tr -d '"')

        # Fetch the endpoint Url of the subscription
        SUBSCRIPTION_ENDPOINT_URL=$(az eventgrid event-subscription show --name ${subscription} \
          --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/domains/${EVENT_GRID_DOMAIN}/topics/${topic}" \
          --include-full-endpoint-url true \
          --query "destination.endpointUrl" |
          tr -d '"')

        # Remove the token from the endpoint Url
        SUBSCRIPTION_ENDPOINT_URL=$(echo ${SUBSCRIPTION_ENDPOINT_URL} | sed 's/&token=.*//')
        SUBSCRIPTION_ENDPOINT_URL=$(echo ${SUBSCRIPTION_ENDPOINT_URL} | sed 's/?token=.*//')

        if [[ ${SUBSCRIPTION_ENDPOINT_URL} == *"code="* ]]; then
          SUBSCRIPTION_ENDPOINT_URL="$(echo "${SUBSCRIPTION_ENDPOINT_URL}&")"
        else
          SUBSCRIPTION_ENDPOINT_URL="$(echo "${SUBSCRIPTION_ENDPOINT_URL}?")"
        fi

        # Update the endpoint of the subscription with the new access token
        az eventgrid event-subscription update --name ${subscription} \
          --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/domains/${EVENT_GRID_DOMAIN}/topics/${topic}" \
          --endpoint "${SUBSCRIPTION_ENDPOINT_URL}token=${ACCESS_TOKEN}"
      done
    else
      echo "No Event Grid subscriptions found!"
    fi
  done
else
  echo "No Event Grid topics found!"
fi
