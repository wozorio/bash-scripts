################################################################################
# DEPRECATION NOTICE
#
# This script has been replaced with a new Python-based solution.
# Please refer to the new approach instead: https://github.com/wozorio/acr-cleaner
################################################################################

#!/bin/bash

################################################################################
# Script Name    : azure-acr-cleanup.sh
# Description    : Used to clean up container registries by deleting untagged (dangling) images and images older than 30 days
# Args           : CONTAINER_REGISTRY_NAME
# Author         : Wellington Ozorio <well.ozorio@gmail.com>
################################################################################

# Stop execution on any error
set -e

# Check if correct parameters were passed
if [ "$#" -ne 1 ]; then
    echo "ERROR: Missing or invalid parameters!"
    echo "Usage example: ./container-registry-cleanup.sh CONTAINER_REGISTRY_NAME"
    exit 1
else
    # Declare variables
    CONTAINER_REGISTRY_NAME=$1
    DATE_THRESHOLD="$(date +%Y-%m-%d -d "30 days ago")"

    # Fetch the list of repositories
    REPOSITORIES=()
    REPOSITORIES="$(az acr repository list -n "$CONTAINER_REGISTRY_NAME" --output tsv)"

    # Search for untagged (dangling) images in each repository
    echo "################################################"
    echo "EXECUTION OF UNTAGGED (DANGLING) IMAGES DELETION"
    echo "################################################"

    UNTAGGED_IMGS=()
    echo "${REPOSITORIES[@]}" | while read -r rep; do
        UNTAGGED_IMGS=$(
            az acr repository show-manifests --name "$CONTAINER_REGISTRY_NAME" --repository "$rep" \
                --query "[?tags[0]==null].digest" \
                --orderby time_asc \
                --output tsv
        )
        if [ -z "${UNTAGGED_IMGS[@]}" ]; then
            echo "INFO: No untagged (dangling) images found in the repository: $rep"
        else
            # Delete untagged (dangling) images
            echo
            echo "${UNTAGGED_IMGS[@]}" | while read -r img; do
                echo "WARN: Deleting untagged (dangling) image: $rep@$img"
                # az acr repository delete --name $CONTAINER_REGISTRY_NAME --image $rep@$img --yes
            done
        fi
    done

    # Search for images older than 30 days in each repository
    echo "################################################"
    echo "       EXECUTION OF OLD IMAGES DELETION"
    echo "################################################"

    OLD_IMGS=()
    echo "${REPOSITORIES[@]}" | while read -r rep; do
        OLD_IMGS=$(
            az acr repository show-manifests --name "$CONTAINER_REGISTRY_NAME" --repository "$rep" \
                --query "[?timestamp < '$DATE_THRESHOLD'].[digest, timestamp]" \
                --orderby time_asc \
                --output tsv
        )
        if [ -z "${OLD_IMGS[@]}" ]; then
            echo "INFO: No images older than 30 days found in the repository: $rep"
        else
            # Get how many images exist in the repository
            MANIFEST_COUNT=$(
                az acr repository show --name "$CONTAINER_REGISTRY_NAME" --repository "$rep" --output yaml |
                    awk '/manifestCount:/{print $NF}'
            )

            # Check if there is more than 1 image in the repository
            if [ "$MANIFEST_COUNT" -ge 2 ]; then
                echo
                echo "The repository $rep contains a total of $MANIFEST_COUNT images"

                # Loop through each image older than 30 days
                echo "${OLD_IMGS[@]}" | while read -r img; do

                    # Get only the manifest digest without the timestamp
                    IMG_MANIFEST_ONLY="$(echo "$img" | cut -d' ' -f1)"

                    # Get the repository last update time
                    LAST_UPDATE_TIME_REPO=$(
                        az acr repository show --name "$CONTAINER_REGISTRY_NAME" --repository "$rep" --output yaml |
                            awk '/lastUpdateTime:/{print $NF}' |
                            # Remove single quote from the string
                            sed "s/['\"]//g"
                    )

                    # Convert the repository last update time into seconds
                    LAST_UPDATE_TIME_REPO="$(date -d "$LAST_UPDATE_TIME_REPO" +%s)"

                    # Get the image last update time
                    LAST_UPDATE_TIME_IMG=$(
                        az acr repository show --name "$CONTAINER_REGISTRY_NAME" --image "$rep@$IMG_MANIFEST_ONLY" --output yaml |
                            awk '/lastUpdateTime:/{print $NF}' |
                            # Remove single quote from the string
                            sed "s/['\"]//g"
                    )

                    # Convert the image last update time into seconds
                    LAST_UPDATE_TIME_IMG="$(date -d "$LAST_UPDATE_TIME_IMG" +%s)"

                    if [ "$LAST_UPDATE_TIME_REPO" -gt "$LAST_UPDATE_TIME_IMG" ]; then
                        IMG_TO_DELETE=$(
                            az acr repository show --name "$CONTAINER_REGISTRY_NAME" --image "$rep"@"$IMG_MANIFEST_ONLY" --output yaml |
                                grep -A1 'tags:' | tail -n1 | awk '{ print $2}'
                        )

                        # Delete images older than 30 days
                        echo "WARN: Deleting image with tag: $IMG_TO_DELETE from repository: $rep"
                        # az acr repository delete --name $CONTAINER_REGISTRY_NAME --image $rep@$IMG_MANIFEST_ONLY --yes
                    fi
                done
            else
                echo "INFO: Nothing to do. There is only 1 image in the repository: $rep"
            fi
        fi
    done
fi
