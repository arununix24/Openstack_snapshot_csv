#!/bin/bash

#author: Arun Kumar
#date: 2023-10-30
#version: 2.0
#description: Filters OpenStack servers based on an Order ID, extracts Subscription IDs,
#             collects attached volumes, optionally includes ChainLoader volumes,
#             creates snapshots, and generates a detailed CSV report.

#####################################################
# User Input
#####################################################

read -p "Enter the Order ID: " SEARCH_TERM
read -p "Do you want to snapshot ChainLoader volumes? (Y/N): " SNAP_CHAINLOADER

#####################################################
# Output Files
#####################################################

OUTPUT_FILE="filtered_openstack_servers.csv"
VOLUMES_OUTPUT="dynamic_volumes.csv"
FINAL_OUTPUT="final.csv"
SNAPSHOT_REPORT="snapshot_${SEARCH_TERM}.csv"

#####################################################
# Step 1 - Get Servers for Order ID
#####################################################

openstack server list --long -f csv | grep "$SEARCH_TERM" > "$OUTPUT_FILE"

if [[ ! -s "$OUTPUT_FILE" ]]; then
    echo "No matching servers found for '$SEARCH_TERM'. Exiting."
    exit 1
fi

echo "Filtered OpenStack server list saved to $OUTPUT_FILE"

#####################################################
# Step 2 - Extract Subscription ID
#####################################################

SUBSCRIPTION_ID=$(awk -F ',' '{print $2}' "$OUTPUT_FILE" | sort -u | tr -d '"')

echo
echo "Subscription ID(s) Found:"
echo "$SUBSCRIPTION_ID"
echo

#####################################################
# Step 3 - Filter by Subscription ID
#####################################################

read -p "Enter the Subscription ID from above to filter further: " COLUMN4_INPUT

openstack server list --long -f csv | grep "$COLUMN4_INPUT" > "$VOLUMES_OUTPUT"

if [[ ! -s "$VOLUMES_OUTPUT" ]]; then
    echo "No matching servers found for '$COLUMN4_INPUT'."
    exit 1
fi

echo "Server list saved to $VOLUMES_OUTPUT"

#####################################################
# Step 4 - Build Server / Volume Mapping
#####################################################

echo "Server ID,Volumes Attached" > "$FINAL_OUTPUT"

echo "Order ID,Subscription ID,Host UUID,Volume Name,Volume ID,Mount Point,Size,Snapshot ID,Status of Snapshot" > "$SNAPSHOT_REPORT"

echo
echo "Processing server IDs..."
echo

while IFS=',' read -r SERVER_ID _; do

    SERVER_ID=$(echo "$SERVER_ID" | tr -d '"')

    [[ -z "$SERVER_ID" ]] && continue

    echo "Fetching server details for Server ID: $SERVER_ID"

    SERVER_INFO=$(openstack server show "$SERVER_ID" -f json 2>/dev/null)

    if [[ -n "$SERVER_INFO" ]]; then

        SERVER_ID_PARSED=$(echo "$SERVER_INFO" | jq -r '.id')

        VOLUMES=$(echo "$SERVER_INFO" | jq -r '[.volumes_attached[].id] | join(", ")')

        [[ -z "$VOLUMES" ]] && VOLUMES="None"

        echo "$SERVER_ID_PARSED,$VOLUMES" >> "$FINAL_OUTPUT"

    else

        echo "No server found for $SERVER_ID" | tee -a missing_servers.log

    fi

done < "$VOLUMES_OUTPUT"

#####################################################
# Step 5 - Snapshot Creation
#####################################################

read -p "Would you like to take snapshots of all volumes? (yes/no): " RESPONSE

if [[ "$RESPONSE" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then

    echo
    echo "Taking snapshots of all volumes..."
    echo

    while IFS=',' read -r SERVER_ID VOLUMES; do

        if [[ "$VOLUMES" != "Volumes Attached" && "$VOLUMES" != "None" ]]; then

            for VOLUME_ID in $(echo "$VOLUMES" | tr ',' '\n'); do

                VOLUME_ID=$(echo "$VOLUME_ID" | xargs)

                #####################################################
                # Volume Details
                #####################################################

                VOLUME_INFO=$(openstack volume show "$VOLUME_ID" -f json 2>/dev/null)

                [[ -z "$VOLUME_INFO" ]] && continue

                VOLUME_NAME=$(echo "$VOLUME_INFO" | jq -r '.name')
                VOLUME_SIZE=$(echo "$VOLUME_INFO" | jq -r '.size')
                VOLUME_STATUS=$(echo "$VOLUME_INFO" | jq -r '.status')

                IMAGE_META=$(echo "$VOLUME_INFO" | jq -r '.volume_image_metadata')

                MOUNT_POINT=$(echo "$VOLUME_INFO" | jq -r '.attachments[0].device // "N/A"')
                MOUNT_POINT=$(basename "$MOUNT_POINT")

                DATE_SUFFIX=$(date +%Y%m%d-%H%M%S)

                #####################################################
                # ChainLoader Logic
                #####################################################

                if echo "$IMAGE_META" | grep -qi "ChainLoader"; then

                    VOLUME_NAME="ChainLoader"

                    if [[ ! "$SNAP_CHAINLOADER" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
                        echo "Skipping ChainLoader volume: $VOLUME_ID"
                        continue
                    else
                        echo "Including ChainLoader volume: $VOLUME_ID"
                    fi

                fi

                #####################################################
                # Clean Volume Name
                #####################################################

                if [[ "$VOLUME_NAME" == "ChainLoader" ]]; then
                    VOLUME_NAME_CLEANED="ChainLoader"
                else
                    VOLUME_NAME_CLEANED=$(echo "$VOLUME_NAME" | sed 's/client01/Host01/g')
                fi

                #####################################################
                # Snapshot Name
                #####################################################

                SNAPSHOT_NAME="snapshot-${VOLUME_NAME_CLEANED}-${DATE_SUFFIX}"

                SNAP_ID="N/A"
                SNAP_STATUS="skipped"

                #####################################################
                # Create Snapshot
                #####################################################

                if [[ "$VOLUME_STATUS" == "available" ]]; then

                    echo "Creating snapshot: $SNAPSHOT_NAME"

                    SNAP_ID=$(openstack volume snapshot create \
                        --volume "$VOLUME_ID" \
                        "$SNAPSHOT_NAME" \
                        -f value -c id)

                    SNAP_STATUS="created"

                elif [[ "$VOLUME_STATUS" == "in-use" ]]; then

                    echo "Forcing snapshot: $SNAPSHOT_NAME"

                    SNAP_ID=$(openstack volume snapshot create \
                        --force \
                        --volume "$VOLUME_ID" \
                        "$SNAPSHOT_NAME" \
                        -f value -c id)

                    SNAP_STATUS="created (forced)"

                else

                    echo "Skipping $VOLUME_ID due to volume status: $VOLUME_STATUS"

                fi

                #####################################################
                # CSV Report Entry
                #####################################################

                echo "$SEARCH_TERM,$SUBSCRIPTION_ID,$SERVER_ID,$VOLUME_NAME_CLEANED,$VOLUME_ID,$MOUNT_POINT,$VOLUME_SIZE,$SNAP_ID,$SNAP_STATUS" >> "$SNAPSHOT_REPORT"

            done

        fi

    done < "$FINAL_OUTPUT"

    echo
    echo "Snapshot creation and reporting completed."
    echo "Report file: $SNAPSHOT_REPORT"
    echo

else

    echo "Snapshot creation skipped."

fi
