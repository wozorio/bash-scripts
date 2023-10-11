#!/usr/bin/env bash

################################################################################
# Script Name    : azuredevops-trigger-pipeline-run.sh
# Description    : Used to trigger YAML pipeline runs in Azure DevOps with Azure CLI
# Args           : BRANCH DEFINITION_NAME ORGANIZATION PROJECT
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
################################################################################

set -o errexit
set -o pipefail
set -o nounset

function usage() {
    echo "ERROR: Missing or invalid arguments!"
    echo "Usage example: ${0} BRANCH DEFINITION_NAME ORGANIZATION PROJECT"
    exit 1
}

# Check if the right number of arguments was passed
if [[ "${#}" -ne 4 ]]; then
    usage
fi

BRANCH=$1
DEFINITION_NAME=$2
ORGANIZATION=$3
PROJECT=$4

az devops configure --defaults organization="${ORGANIZATION}" project="${PROJECT}"

PIPELINE_RUN=$(
    az pipelines build queue \
        --branch "${BRANCH}" \
        --definition-name "${DEFINITION_NAME}" \
        --verbose
)

BUILD_ID=$(echo "${PIPELINE_RUN}" | jq .id)

function check_if_pipeline_run_completed() {
    PIPELINE_RUN_STATUS=$(az pipelines runs show --id "${BUILD_ID}" | jq .status)

    if [[ "${PIPELINE_RUN_STATUS}" == '"completed"' ]]; then
        echo 1
    else
        echo 0
    fi
}

PIPELINE_RUN_STATUS=$(check_if_pipeline_run_completed)

NUMBER_OF_RETRIES=60
SLEEP_DURATION_IN_SECONDS=10

echo -e "\nINFO: Waiting ${DEFINITION_NAME} pipeline run to finish"
echo "INFO: The progress can be tracked through the following URL: ${ORGANIZATION}${PROJECT}/_build/results?buildId=${BUILD_ID}&view=results"
echo "INFO: Pipeline run status will be updated every ${SLEEP_DURATION_IN_SECONDS} seconds"

while [[ "${PIPELINE_RUN_STATUS}" -ne 1 ]]; do
    sleep "${SLEEP_DURATION_IN_SECONDS}"
    PIPELINE_RUN_STATUS=$(check_if_pipeline_run_completed)

    if [[ "${PIPELINE_RUN_STATUS}" -eq 1 ]]; then
        echo "INFO: ${DEFINITION_NAME} pipeline run has completed!"
        break
    else
        echo "INFO: ${DEFINITION_NAME} pipeline is running..."

        NUMBER_OF_RETRIES=$((NUMBER_OF_RETRIES - 1))

        if [[ "${NUMBER_OF_RETRIES}" -eq 0 ]]; then
            echo "ERROR: Exceeded maximum number of retries! Please check the ${DEFINITION_NAME} pipeline!"
            exit 1
        fi
    fi
done
