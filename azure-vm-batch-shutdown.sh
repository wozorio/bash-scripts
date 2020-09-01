#!/bin/bash

######################################################################
# Script Name    : azure-vm-batch-shutdown.sh
# Description    : Used to shutdown and deallocate all VMs in a subscription
# Args           : n/a
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
######################################################################

# Stop execution on any error
set -e

# Stop all VMs
az vm stop --ids $(
  az vm list --query "[].id" --output tsv
)

# Deallocate all VMs
az vm deallocate --ids $(
  az vm list --query "[].id" --output tsv
)
