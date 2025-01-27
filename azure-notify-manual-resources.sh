#!/usr/bin/env bash

# This script helps ensure proper housekeeping by identifying unneeded resources, and therefore
# avoiding unnecessary costs. It identifies resources that have been manually provisioned
# in an Azure subscription, then it filters out resources managed by Terraform and those that were
# intentionally provisioned manually.
# As a final step a notification is sent out to a Microsoft Teams channel with a list of undesired
# manually provisioned resources.

set -e

readonly UNSUPPORTED_TAG_RESOURCE_TYPES=(
    "microsoft.compute/restorepointcollections"
    "microsoft.compute/virtualmachines/extensions"
    "microsoft.domainregistration/domains"
    "microsoft.eventgrid/systemtopics"
    "microsoft.insights/workbooks"
    "microsoft.maintenance/maintenanceconfigurations"
    "microsoft.network/networkwatchers"
    "microsoft.operationsmanagement/solutions"
    "microsoft.portal/dashboards"
    "microsoft.recoveryservices/vaults"
    "microsoft.security/automations"
    "microsoft.visualstudio/account"
    "microsoft.web/connections"
)

get_filtered_untagged_resources() {
    az resource list --output json |
        jq -r '
            [map(
                select(
                    .tags.managed_by != "terraform"
                    and (.name | contains("master") | not)
                    and (.name | contains("stsharedtfwe") | not)
                    and (.name | contains("stdevtfwe") | not)
                    and (.name | contains("stqatfwe") | not)
                    and (.name | contains("ststagetfwe") | not)
                    and (.name | contains("stprodtfwe") | not)
                    and (.resourceGroup | startswith("DefaultResourceGroup-") | not)
                    and (.resourceGroup | ascii_downcase | startswith("mc_") | not)
                    and (.resourceGroup | endswith("tf-we") | not)
                    and (.resourceGroup != "LogAnalyticsDefaultResources")
                    and (.resourceGroup != "rg-shared-jumphost-we")
                    and (.resourceGroup != "rg-shared-mgmt-environment-we")
                    and (.resourceGroup != "rg-shared-jumphost-we")
                )
            )
            | sort_by(.name)[]
            | {name: .name, type: .type, resourceGroup: .resourceGroup}]
        '
}

remove_unsupported_tag_resources() {
    local RESOURCES="${1}"

    for RESOURCE_TYPE in "${UNSUPPORTED_TAG_RESOURCE_TYPES[@]}"; do
        RESOURCES=$(jq -r --arg type "$RESOURCE_TYPE" 'del(.[] | select(.type == $type))' <<<"${RESOURCES,,}")
    done

    echo "${RESOURCES}"
}

# shellcheck disable=SC2016,SC2153
function send_message_to_msteams() {
    local ENVIROMENT="${1}"
    local MSTEAMS_WEBHOOK_URL="${2}"
    local MANUALLY_PROVISIONED_RESOURCES="${3}"
    local PIPELINE_RUN_URI="${4}"

    local MESSAGE='{
        "type": "message",
        "attachments": [
            {
                "contentType": "application/vnd.microsoft.card.adaptive",
                "content": {
                    "type": "AdaptiveCard",
                    "body": [
                        {
                            "type": "TextBlock",
                            "text": "'"[${ENVIRONMENT^^}]"' manually provisioned resources identified",
                            "weight": "bolder",
                            "size": "large",
                            "color": "attention"
                        },
                        {
                            "type": "TextBlock",
                            "text": "Resources:",
                            "weight": "bolder",
                            "size": "medium"
                        },
                        {
                            "type": "TextBlock",
                            "text": "'"${MANUALLY_PROVISIONED_RESOURCES}"'",
                            "wrap": true
                        }
                    ],
                    "actions": [
                        {
                            "type": "Action.OpenUrl",
                            "title": "Go to pipeline run for details",
                            "url": "'"${PIPELINE_RUN_URI}"'"
                        }
                    ],
                    "$schema": "https://adaptivecards.io/schemas/adaptive-card.json",
                    "version": "1.4"
                }
            }
        ]
    }'

    echo "Sending list of manually provisioned resources to Microsoft Teams..."

    local RESPONSE
    RESPONSE=$(curl --request POST \
        --header "Content-Type: application/json" \
        --data "${MESSAGE}" \
        --write-out "%{http_code}" \
        --silent \
        --output /dev/null \
        "${MSTEAMS_WEBHOOK_URL}")

    if [[ ${RESPONSE} -lt 200 || ${RESPONSE} -gt 299 ]]; then
        echo "ERROR: Failed sending failure message with error code ${RESPONSE}"
        exit 1
    fi
}

main() {
    local ENVIROMENT="${1}"
    local MSTEAMS_WEBHOOK_URL="${2}"
    local PIPELINE_RUN_URI="${3}"

    local FILTERED_UNTAGGED_RESOURCES
    FILTERED_UNTAGGED_RESOURCES=$(get_filtered_untagged_resources)

    local MANUALLY_PROVISIONED_RESOURCES
    MANUALLY_PROVISIONED_RESOURCES=$(remove_unsupported_tag_resources "${FILTERED_UNTAGGED_RESOURCES}")

    local MANUALLY_PROVISIONED_RESOURCES_COUNT
    MANUALLY_PROVISIONED_RESOURCES_COUNT=$(jq length <<<"${MANUALLY_PROVISIONED_RESOURCES}")

    if [[ ${MANUALLY_PROVISIONED_RESOURCES_COUNT} -eq 0 ]]; then
        echo "No manually provisioned resources have been identified."
        exit 0
    fi

    echo "The following manually provisioned resources have been identified:"
    jq -r <<<"${MANUALLY_PROVISIONED_RESOURCES}"

    MANUALLY_PROVISIONED_RESOURCES=$(jq -r 'map(.name) | join(", ")' <<<"${MANUALLY_PROVISIONED_RESOURCES}")
    send_message_to_msteams \
        "${ENVIROMENT}" \
        "${MSTEAMS_WEBHOOK_URL}" \
        "${MANUALLY_PROVISIONED_RESOURCES}" \
        "${PIPELINE_RUN_URI}"
}

main "${@}"
