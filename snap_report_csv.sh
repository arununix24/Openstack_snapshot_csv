
#author: Arun Kumar     
#date: 2023-10-30
#version: 1.0                   
#description: This script filters OpenStack servers based on an Order ID, extracts Subscription IDs, and manages volume snapshots.   


#!/bin/bash
# Step 1: Get Order ID from the user
read -p "Enter the Order ID: " SEARCH_TERM

# Output files
OUTPUT_FILE="filtered_openstack_servers.csv"
VOLUMES_OUTPUT="dynamic_volumes.csv"
FINAL_OUTPUT="final1.csv"
SNAPSHOT_REPORT="snapshot_report.csv"

# Step 2: Get the list of servers based on Order ID
openstack server list --long -f csv | grep "$SEARCH_TERM" > "$OUTPUT_FILE"

if [[ ! -s "$OUTPUT_FILE" ]]; then
    echo "No matching servers found for '$SEARCH_TERM'. Exiting."
    exit 1
fi
echo "Filtered OpenStack server list saved to $OUTPUT_FILE"

# Step 3: Extract Subscription ID
SUBSCRIPTION_ID=$(awk -F ',' '{print $2}' "$OUTPUT_FILE" | sort -u | tr -d '"')
echo "Subscription ID: $SUBSCRIPTION_ID"

# Step 4: Filter servers by Subscription ID
read -p "Enter the Subscription ID from above to filter further: " COLUMN4_INPUT
openstack server list --long -f csv | grep "$COLUMN4_INPUT" > "$VOLUMES_OUTPUT"

if [[ ! -s "$VOLUMES_OUTPUT" ]]; then
    echo "No matching servers found for '$COLUMN4_INPUT'. Output file is empty."
    exit 1
fi
echo "Server ID and Volumes list saved to $VOLUMES_OUTPUT"

# Step 5: Extract server IDs and get volume details
echo "Server ID,Volumes Attached" > "$FINAL_OUTPUT"
echo "Order ID,Subscription ID,Host UUID,Volume Name,Volume ID,Size,Snapshot ID,Status of Snapshot" > "$SNAPSHOT_REPORT"

echo "Processing server IDs to fetch server details..."
while IFS=',' read -r SERVER_ID _; do
    SERVER_ID=$(echo "$SERVER_ID" | tr -d '"')

    if [[ -n "$SERVER_ID" ]]; then
        echo "Fetching server details for Server ID: $SERVER_ID"
        SERVER_INFO=$(openstack server show "$SERVER_ID" -f json 2>/dev/null)

        if [[ -n "$SERVER_INFO" ]]; then
            SERVER_ID_PARSED=$(echo "$SERVER_INFO" | jq -r '.id')
            VOLUMES=$(echo "$SERVER_INFO" | jq -r '[.volumes_attached[].id] | join(", ")')
            [[ -z "$VOLUMES" ]] && VOLUMES="None"
            echo "$SERVER_ID_PARSED,$VOLUMES" >> "$FINAL_OUTPUT"
        else
            echo "No Server found for $SERVER_ID" | tee -a missing_servers.log
        fi
    fi
done < "$VOLUMES_OUTPUT"

# Step 6: Ask user if they want to take snapshots
read -p "Would you like to take snapshots of all volumes? (yes/no): " RESPONSE
if [[ "$RESPONSE" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
    echo "Taking snapshots of all volumes..."

    while IFS=',' read -r SERVER_ID VOLUMES; do
        if [[ "$VOLUMES" != "Volumes Attached" && "$VOLUMES" != "None" ]]; then
            for VOLUME_ID in $(echo "$VOLUMES" | tr ',' '\n'); do
                VOLUME_ID=$(echo "$VOLUME_ID" | xargs)

                # Get volume details
                VOLUME_INFO=$(openstack volume show "$VOLUME_ID" -f json 2>/dev/null)
                VOLUME_NAME=$(echo "$VOLUME_INFO" | jq -r '.name')
                VOLUME_SIZE=$(echo "$VOLUME_INFO" | jq -r '.size')
                VOLUME_STATUS=$(echo "$VOLUME_INFO" | jq -r '.status')
                IMAGE_META=$(echo "$VOLUME_INFO" | jq -r '.volume_image_metadata' | grep -i 'ChainLoader')
                DATE_SUFFIX=$(date +%Y%m%d-%H%M%S)

                # Skip logic
                if [[ -n "$IMAGE_META" ]]; then
                    echo "Skipping $VOLUME_ID due to ChainLoader metadata"
                    continue
                fi
                if (( VOLUME_SIZE <= 50 )); then
                    echo "Skipping $VOLUME_ID due to size <= 50 GB"
                    continue
                fi

                # Replace client01 with Host01 in volume name
                VOLUME_NAME_CLEANED=$(echo "$VOLUME_NAME" | sed 's/client01/Host01/g')

                SNAPSHOT_NAME="snapshot-${VOLUME_NAME_CLEANED}-$DATE_SUFFIX"
                SNAP_ID="N/A"
                SNAP_STATUS="skipped"

                # Create snapshot
                if [[ "$VOLUME_STATUS" == "available" ]]; then
                    echo "Creating snapshot: $SNAPSHOT_NAME"
                    SNAP_ID=$(openstack volume snapshot create --volume "$VOLUME_ID" "$SNAPSHOT_NAME" -f value -c id)
                    SNAP_STATUS="created"
                elif [[ "$VOLUME_STATUS" == "in-use" ]]; then
                    echo "Forcing snapshot: $SNAPSHOT_NAME"
                    SNAP_ID=$(openstack volume snapshot create --force --volume "$VOLUME_ID" "$SNAPSHOT_NAME" -f value -c id)
                    SNAP_STATUS="created (forced)"
                else
                    echo "Skipping $VOLUME_ID due to unknown status"
                fi

                echo "$SEARCH_TERM,$SUBSCRIPTION_ID,$SERVER_ID,$VOLUME_NAME_CLEANED,$VOLUME_ID,$VOLUME_SIZE,$SNAP_ID,$SNAP_STATUS" >> "$SNAPSHOT_REPORT"
            done
        fi
    done < "$FINAL_OUTPUT"

    echo "Snapshot creation and reporting completed."
else
    echo "Snapshot creation skipped."
fi
