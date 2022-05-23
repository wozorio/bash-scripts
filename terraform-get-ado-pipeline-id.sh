#!/usr/bin/env bash

######################################################################
# Script Name    : terraform-get-ado-pipeline-id.sh
# Description    : Used by Terraform external data source resource to
#                : fetch pipeline ID from the Azure DevOps Pipelines REST API
# Args           : PIPELINE_NAME
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail
set -o nounset

# Extract "pipeline_name" argument from the input into the PIPELINE_NAME shell variable
# jq will ensure that the values are properly quoted and escaped for consumption by the shell
eval "$(jq -r '@sh "PIPELINE_NAME=\(.pipeline_name)"')"

# Azure DevOps Pipelines REST API reference:
# https://docs.microsoft.com/en-us/rest/api/azure/devops/pipelines/pipelines/list?view=azure-devops-rest-6.0
ADO_PIPELINES_API="https://dev.azure.com/bosch-ciam/skid/_apis/pipelines?api-version=6.0-preview.1"

PIPELINE_ID=$(
    curl \
    --request GET "${ADO_PIPELINES_API}" \
    --user "PAT:${AZDO_PERSONAL_ACCESS_TOKEN}" \
    --header "Content-Type: application/json" \
    --fail | \
    jq \
    --arg pipeline_name "$PIPELINE_NAME" \
    '.value[] | select(.name==$pipeline_name) | .id'
)

if [[ "${?}" -ne 0 || -z "${PIPELINE_ID}" ]]; then
    echo "ERROR: failed to fetch ID of ${PIPELINE_NAME} pipeline" 1>&2
    exit 1
fi

jq \
--null-input \
--arg pipeline_id "$PIPELINE_ID" \
'{"pipeline_id":$pipeline_id}'
