#!/usr/bin/env bash

################################################################################
# Script Name    : azure-eventgrid-renew-subscription-access-tokens.sh
# Description    : Used to renew access tokens for EventGrid subscriptions
# Args           : AZURE_SUBSCRIPTION_ID OAUTH2_TOKEN_ENDPOINT EVENTGRID_DOMAIN CLIENT_ID CLIENT_SECRET RESOURCE_GROUP
#                  FUNCTION_APP_NAME FUNCTION_APP_FUNCTION_NAME
# Author         : Wellington Ozorio <wozorio@duck.com>
################################################################################

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
    log "Usage example: ${0} AZURE_SUBSCRIPTION_ID OAUTH2_TOKEN_ENDPOINT EVENTGRID_DOMAIN CLIENT_ID CLIENT_SECRET RESOURCE_GROUP FUNCTION_APP_NAME FUNCTION_APP_FUNCTION_NAME"
    exit 1
}

function get_eventgrid_topics() {
    local EVENT_GRID_TOPICS
    EVENT_GRID_TOPICS=$(
        az eventgrid domain topic list \
            --resource-group "${RESOURCE_GROUP}" \
            --domain-name "${EVENTGRID_DOMAIN}" \
            --query [].name \
            --output tsv
    )

    if [[ -z "${EVENT_GRID_TOPICS}" ]]; then
        echo "##vso[task.logissue type=error]ERROR: No topics found in EventGrid domain ${EVENTGRID_DOMAIN}"
        exit 1
    fi

    echo "${EVENT_GRID_TOPICS}"
}

function get_eventgrid_subscriptions() {
    local TOPIC="${1}"
    local EVENT_GRID_SUBSCRIPTIONS
    EVENT_GRID_SUBSCRIPTIONS=$(
        az eventgrid event-subscription list \
            --source-resource-id "${TOPIC_RESOURCE_ID_PREFIX}/${TOPIC}" \
            --query [].name \
            --output tsv
    )

    if [[ -z "${EVENT_GRID_SUBSCRIPTIONS}" ]]; then
        echo "##vso[task.logissue type=error]ERROR: No subscriptions found in EventGrid topic ${TOPIC}"
        exit 1
    fi

    echo "${EVENT_GRID_SUBSCRIPTIONS}"
}

function is_internal_subscription() {
    local SUBSCRIPTION="${1}"

    local EVENTGRID_INTERNAL_SUBSCRIPTIONS=("inernal-http-subscription")

    for INTERNAL_SUBSCRIPTION in "${EVENTGRID_INTERNAL_SUBSCRIPTIONS[@]}"; do
        if [[ "${INTERNAL_SUBSCRIPTION}" == "${SUBSCRIPTION}" ]]; then
            echo 1
            return
        fi
    done

    echo 0
}

function get_subscription_scope() {
    local TOPIC="${1}"
    local SUBSCRIPTION="${2}"

    local SCOPE
    SCOPE=$(
        az eventgrid event-subscription show \
            --name "${SUBSCRIPTION}" \
            --source-resource-id "${TOPIC_RESOURCE_ID_PREFIX}/${TOPIC}" \
            --output tsv \
            --query labels | grep scope: | cut -d: -f2-
    )

    if [[ -z "${SCOPE}" ]]; then
        echo "##vso[task.logissue type=warning]WARN: No scope found"
        return
    fi

    log "-> The following scope was retrieved: ${SCOPE}"
    echo "${SCOPE}"
}

function get_subscription_endpoint_url() {
    local TOPIC="${1}"
    local SUBSCRIPTION="${2}"

    local ENDPOINT_URL
    ENDPOINT_URL=$(
        az eventgrid event-subscription show \
            --name "${SUBSCRIPTION}" \
            --source-resource-id "${TOPIC_RESOURCE_ID_PREFIX}/${TOPIC}" \
            --include-full-endpoint-url true \
            --output tsv \
            --query destination.endpointUrl
    )

    if [[ -z "${ENDPOINT_URL}" ]]; then
        echo "##vso[task.logissue type=warning]WARN: Endpoint URL for subscription ${SUBSCRIPTION} could not be retrieved"
        return
    fi

    echo "${ENDPOINT_URL}"
}

function get_access_token() {
    local SUBSCRIPTION_SCOPE="${1}"

    local BASE64_ENCODED_CLIENT_CREDENTIALS
    BASE64_ENCODED_CLIENT_CREDENTIALS=$(printf "%s:%s" "${CLIENT_ID}" "${CLIENT_SECRET}" | base64 -w 0)

    log "-> Getting access token from OAuth2 token endpoint ${OAUTH2_TOKEN_ENDPOINT}"
    local ACCESS_TOKEN
    ACCESS_TOKEN=$(
        curl \
            --request POST \
            --url "${OAUTH2_TOKEN_ENDPOINT}" \
            --silent \
            --header "Accept: application/json" \
            --header "Authorization: Basic ${BASE64_ENCODED_CLIENT_CREDENTIALS}" \
            --data grant_type=client_credentials \
            --data client_id="${CLIENT_ID}" \
            --data client_secret="${CLIENT_SECRET}" \
            --data scope="${SUBSCRIPTION_SCOPE}" | jq '.access_token' | tr -d '"'
    )

    if [[ -z "${ACCESS_TOKEN}" || "${ACCESS_TOKEN}" == "null" ]]; then
        echo "##vso[task.logissue type=warning]WARN: An access token could not be retrieved"
        return
    fi

    echo "${ACCESS_TOKEN}"
}

function get_functionapp_function_key() {
    log "-> Getting access key for function ${FUNCTION_APP_FUNCTION_NAME} in FunctionApp ${FUNCTION_APP_NAME}"
    local FUNCTIONAPP_FUNCTION_KEY
    FUNCTIONAPP_FUNCTION_KEY=$(
        az functionapp function keys list \
            --function-name "${FUNCTION_APP_FUNCTION_NAME}" \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output tsv \
            --query default
    )

    if [[ -z "${FUNCTIONAPP_FUNCTION_KEY}" ]]; then
        echo "##vso[task.logissue type=warning]WARN: Access key for function ${FUNCTION_APP_FUNCTION_NAME} could not be retrieved from FunctionApp ${FUNCTION_APP_NAME}"
        return
    fi

    echo "${FUNCTIONAPP_FUNCTION_KEY}"
}

function normalize_subscription_endpoint_url() {
    local ENDPOINT_URL="${1}"

    # Remove the token from the subscription endpoint URL
    if [[ "${ENDPOINT_URL}" == *"&token="* ]]; then
        ENDPOINT_URL="${ENDPOINT_URL%%&token=*}"
    elif [[ "${ENDPOINT_URL}" == *"?token="* ]]; then
        ENDPOINT_URL="${ENDPOINT_URL%%\?token=*}"
    fi

    # Assign a new authorization code (if applicable) to the subscription endpoint URL
    if [[ "${ENDPOINT_URL}" == *"code="* ]]; then
        ENDPOINT_URL="${ENDPOINT_URL%%\?code=*}"

        local FUNCTIONAPP_FUNCTION_KEY
        FUNCTIONAPP_FUNCTION_KEY=$(get_functionapp_function_key)

        ENDPOINT_URL="${ENDPOINT_URL}?code=${FUNCTIONAPP_FUNCTION_KEY}&"
    else
        ENDPOINT_URL="${ENDPOINT_URL}?"
    fi

    ENDPOINT_URL="${ENDPOINT_URL}token="

    echo "${ENDPOINT_URL}"
}

function renew_eventgrid_subscription_access_token() {
    local TOPIC="${1}"
    local SUBSCRIPTION="${2}"

    log "INFO: Renewing access token for ${TOPIC}/${SUBSCRIPTION}:"

    if [[ $(is_internal_subscription "${SUBSCRIPTION}") -eq 1 ]]; then
        log "-> Subscription ${SUBSCRIPTION} is internal, skipping access token renewal..."
        return
    fi

    local SUBSCRIPTION_SCOPE
    SUBSCRIPTION_SCOPE=$(get_subscription_scope "${TOPIC}" "${SUBSCRIPTION}")

    local SUBSCRIPTION_ENDPOINT_URL
    SUBSCRIPTION_ENDPOINT_URL=$(get_subscription_endpoint_url "${TOPIC}" "${SUBSCRIPTION}")

    local NORMALIZED_SUBSCRIPTION_ENDPOINT_URL
    NORMALIZED_SUBSCRIPTION_ENDPOINT_URL=$(normalize_subscription_endpoint_url "${SUBSCRIPTION_ENDPOINT_URL}")

    local ACCESS_TOKEN
    ACCESS_TOKEN=$(get_access_token "${SUBSCRIPTION_SCOPE}")

    log "-> Attaching access token to EventGrid subscription endpoint URL"
    local SUBSCRIPTION_ENDPOINT_UPDATE_STATUS
    SUBSCRIPTION_ENDPOINT_UPDATE_STATUS=$(
        az eventgrid event-subscription update \
            --name "${SUBSCRIPTION}" \
            --source-resource-id "${TOPIC_RESOURCE_ID_PREFIX}/${TOPIC}" \
            --endpoint "${NORMALIZED_SUBSCRIPTION_ENDPOINT_URL}${ACCESS_TOKEN}" \
            --output tsv \
            --query provisioningState
    )

    if [[ "${SUBSCRIPTION_ENDPOINT_UPDATE_STATUS}" != "Succeeded" ]]; then
        echo "##vso[task.logissue type=warning]WARN: Access token for ${TOPIC}/${SUBSCRIPTION} could not be renewed"
        echo "##vso[task.complete result=SucceededWithIssues]"
        return
    fi

    log "-> Access token for ${TOPIC}/${SUBSCRIPTION} has been successfully renewed"
}

function main() {
    if [[ "${#}" -ne 8 ]]; then
        log "Passed arguments are: ${*}"
        log "Number of arguments: ${#}"
        usage
    fi

    export AZURE_SUBSCRIPTION_ID="${1}"
    export OAUTH2_TOKEN_ENDPOINT="${2}"
    export EVENTGRID_DOMAIN="${3}"
    export CLIENT_ID="${4}"
    export CLIENT_SECRET="${5}"
    export RESOURCE_GROUP="${6}"
    export FUNCTION_APP_NAME="${7}"
    export FUNCTION_APP_FUNCTION_NAME="${8}"

    # Export functions to be used in parallel
    export -f log
    export -f is_internal_subscription
    export -f get_subscription_scope
    export -f get_subscription_endpoint_url
    export -f get_access_token
    export -f get_functionapp_function_key
    export -f normalize_subscription_endpoint_url
    export -f renew_eventgrid_subscription_access_token

    export TOPIC_RESOURCE_ID_PREFIX="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/domains/${EVENTGRID_DOMAIN}/topics"

    local EVENT_GRID_TOPICS
    EVENT_GRID_TOPICS=$(get_eventgrid_topics)

    for TOPIC in ${EVENT_GRID_TOPICS}; do
        local EVENT_GRID_SUBSCRIPTIONS=()
        mapfile -t EVENT_GRID_SUBSCRIPTIONS <<<"$(get_eventgrid_subscriptions "${TOPIC}")"

        log "INFO: Found the following EventGrid subscriptions for topic ${TOPIC}:"
        tr ' ' '\n' <<<"${EVENT_GRID_SUBSCRIPTIONS[@]}"

        parallel --keep-order renew_eventgrid_subscription_access_token "${TOPIC}" {} ::: "${EVENT_GRID_SUBSCRIPTIONS[@]}"
    done
}

main "${@}"
