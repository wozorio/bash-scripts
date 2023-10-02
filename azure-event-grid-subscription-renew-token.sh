#!/usr/bin/env bash

######################################################################
# Script Name    : azure-event-grid-subscription-renew-token.sh
# Description    : Used to update the webhook Url of domain Event Grid
#                  subscriptions with a new access token
# Args           : SUBSCRIPTION_ID OAUTH2_TOKEN_ENDPOINT EVENT_GRID_DOMAIN CLIENT_ID CLIENT_SECRET RESOURCE_GROUP
#                  FUNCTION_APP_NAME FUNCTION_APP_FUNCTION_NAME
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

# Continue execution even if errors occur
set +e

function log() {
    local MESSAGE="${1}"
    local CURRENT_TIME_UTC
    CURRENT_TIME_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${CURRENT_TIME_UTC} ${MESSAGE}" 1>&2
}

function usage() {
    log "ERROR: Missing or invalid arguments"
    log "Usage example: ${0} \
                            SUBSCRIPTION_ID \
                            OAUTH2_TOKEN_ENDPOINT \
                            EVENT_GRID_DOMAIN \
                            CLIENT_ID \
                            CLIENT_SECRET \
                            RESOURCE_GROUP \
                            FUNCTION_APP_NAME \
                            FUNCTION_APP_FUNCTION_NAME"
    exit 1
}

# Check if the right number of arguments was passed
if [[ "$#" -ne 6 ]] && [[ "$#" -ne 8 ]]; then
    log "Passed arguments are: $*"
    log "Number arguments $#"
    usage
fi

log "INFO: Passed arguments are: $*"

SUBSCRIPTION_ID=$1
OAUTH2_TOKEN_ENDPOINT=$2
EVENT_GRID_DOMAIN=$3
CLIENT_ID=$4
CLIENT_SECRET=$5
RESOURCE_GROUP=$6
FUNCTION_APP_NAME=$7
FUNCTION_APP_FUNCTION_NAME=$8

EVENT_GRID_TOPICS=$(
    az eventgrid domain topic list \
        --resource-group "${RESOURCE_GROUP}" \
        --domain-name "${EVENT_GRID_DOMAIN}" \
        --query [].name \
        --output tsv
)

if [[ -z "${EVENT_GRID_TOPICS}" ]]; then
    log "INFO: No EventGrid topics found"
    exit 0
fi

echo "${EVENT_GRID_TOPICS[@]}" | while read -r topic; do
    EVENT_GRID_SUBSCRIPTIONS=$(
        az eventgrid event-subscription list \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/domains/${EVENT_GRID_DOMAIN}/topics/${topic}" \
            --query [].name \
            --output tsv
    )

    if [[ -z "${EVENT_GRID_SUBSCRIPTIONS}" ]]; then
        log "INFO: No EventGrid subscriptions found"
        exit 0
    fi

    echo "${EVENT_GRID_SUBSCRIPTIONS[@]}" | while read -r subscription; do
        # Retrieve oAuth scope from Azure Portal subscription
        SCOPE=$(
            az eventgrid event-subscription show \
                --name "${subscription}" \
                --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/domains/${EVENT_GRID_DOMAIN}/topics/${topic}" \
                --query labels \
                --output tsv |
                grep scope: |
                cut -d: -f2-
        )

        log "INFO: The following scope was found for EventGrid subscription ${topic}/${subscription}: ${SCOPE}"
        if [[ -n "${SCOPE}" && "${SCOPE}" != "internal" ]]; then
            # Encode the client credentials with base64
            ENCODED_CLIENT_CREDENTIALS=$(echo -n "${CLIENT_ID}":"${CLIENT_SECRET}" | base64 -w 0)

            log "-> Getting an access token for ${topic}/${subscription} and scope ${SCOPE}"
            ACCESS_TOKEN=$(
                curl \
                    --silent \
                    --request POST \
                    --url "${OAUTH2_TOKEN_ENDPOINT}" \
                    --header "Accept:application/json" \
                    --header "Authorization:Basic ${ENCODED_CLIENT_CREDENTIALS}" \
                    --data grant_type=client_credentials \
                    --data client_id="${CLIENT_ID}" \
                    --data client_secret="${CLIENT_SECRET}" \
                    --data scope="${SCOPE}" |
                    jq '.access_token' |
                    tr -d '"'
            )

            if [[ -z "${ACCESS_TOKEN}" || "${ACCESS_TOKEN}" == "null" ]]; then
                echo "##vso[task.complete result=Failed;]"
                echo "##vso[task.logissue type=error]ERROR: The access token could not be retrieved or the access token is null. The access token value is ${ACCESS_TOKEN}"
                exit 1
            fi

            SUBSCRIPTION_ENDPOINT_URL=$(
                az eventgrid event-subscription show \
                    --name "${subscription}" \
                    --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/domains/${EVENT_GRID_DOMAIN}/topics/${topic}" \
                    --include-full-endpoint-url true \
                    --query "destination.endpointUrl" |
                    tr -d '"'
            )

            # Remove the token from the endpoint Url
            SUBSCRIPTION_ENDPOINT_URL=$(echo "${SUBSCRIPTION_ENDPOINT_URL}" | sed 's/&token=.*//')
            SUBSCRIPTION_ENDPOINT_URL=$(echo "${SUBSCRIPTION_ENDPOINT_URL}" | sed 's/?token=.*//')

            if [[ "${SUBSCRIPTION_ENDPOINT_URL}" == *"code="* ]]; then
                SUBSCRIPTION_ENDPOINT_URL_WITHOUT_FUNCTION_CODE=$(echo "${SUBSCRIPTION_ENDPOINT_URL}" | sed 's/?code=.*//')

                FUNCTION_APP_FUNCTION_KEY=$(
                    az functionapp function keys list \
                        --function-name "${FUNCTION_APP_FUNCTION_NAME}" \
                        --name "${FUNCTION_APP_NAME}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --output tsv \
                        --query default
                )

                SUBSCRIPTION_ENDPOINT_URL="${SUBSCRIPTION_ENDPOINT_URL_WITHOUT_FUNCTION_CODE}?code=${FUNCTION_APP_FUNCTION_KEY}&"
            else
                SUBSCRIPTION_ENDPOINT_URL="${SUBSCRIPTION_ENDPOINT_URL}?"
            fi

            SUBSCRIPTION_ENDPOINT_URL_WITHOUT_TOKEN="${SUBSCRIPTION_ENDPOINT_URL}token="

            log "-> Attaching new access token for ${topic}/${subscription} to endpoint URL ${SUBSCRIPTION_ENDPOINT_URL_WITHOUT_TOKEN}"
            log "-> Full subscription webhook URL: ${SUBSCRIPTION_ENDPOINT_URL_WITHOUT_TOKEN}${ACCESS_TOKEN}"

            # Update the endpoint of the subscription with the new access token
            UPDATE_ENDPOINT=$(
                az eventgrid event-subscription update \
                    --name "${subscription}" \
                    --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/domains/${EVENT_GRID_DOMAIN}/topics/${topic}" \
                    --endpoint "${SUBSCRIPTION_ENDPOINT_URL_WITHOUT_TOKEN}${ACCESS_TOKEN}" \
                    --output tsv \
                    --query provisioningState
            )

            if [[ "${UPDATE_ENDPOINT}" == "Succeeded" ]]; then
                log "-> Endpoint ${SUBSCRIPTION_ENDPOINT_URL} updated successfully ${UPDATE_ENDPOINT}"
            else
                log "-> Endpoint ${SUBSCRIPTION_ENDPOINT_URL} update failed"
                echo "##vso[task.complete result=SucceededWithIssues;]"
                echo "##vso[task.logissue type=warning]ERROR: (Url validation) Webhook validation handshake failed for ${subscription}"
            fi
        elif [[ "${SCOPE}" == "internal" ]]; then
            log "INFO: Internal subscription ${subscription}. The access token will not be renewed here"
        else
            echo "##vso[task.complete result=SucceededWithIssues;]"
            echo "##vso[task.logissue type=warning]ERROR: No scope found for subscription ${subscription}"
        fi
    done
done
