#!/usr/bin/env bash

################################################################################
# Script Name    : azure-vm-batch-shutdown.sh
# Description    : Used to shutdown and deallocate all VMs in a subscription
# Args           : n/a
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
################################################################################

set -e

VIRTUAL_MACHINES=$(az vm list --query "[].id" --output tsv)
for VIRTUAL_MACHINE in ${VIRTUAL_MACHINES}; do
    az vm stop --ids "${VIRTUAL_MACHINE}"
    az vm deallocate --ids "${VIRTUAL_MACHINE}"
done
