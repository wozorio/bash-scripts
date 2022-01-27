#!/usr/bin/env bash

######################################################################
# Script Name    : azure-storage-account-disable-firewall.sh
# Description    : Used to disable Azure storage account firewall
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

set -o errexit
set -o pipefail

function usage() {
    echo "Usage:"
    echo -e "\t-r Storage account resource group"
    echo -e "\t-s Storage account name"
    exit 1
}

while getopts "r:s:" OPTION; do
    case "$OPTION" in
    r)
        RESOURCE_GROUP=$OPTARG
        ;;

    s)
        STORAGE_ACCOUNT_NAME=$OPTARG
        ;;

    *)
        usage
        ;;
    esac
done

az storage account update \
--default-action Allow \
--resource-group "${RESOURCE_GROUP}" \
--name "${STORAGE_ACCOUNT_NAME}"
