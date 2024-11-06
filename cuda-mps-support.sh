#!/bin/bash
CLUSTER_NAME=$(grep ^ClusterName /etc/slurm/slurm.conf | cut -d "=" -f2)
echo "Cluster Name: $CLUSTER_NAME"
CONF_DIR="/sched/$CLUSTER_NAME"
# Define file paths
SLURM_CONF="$CONF_DIR/slurm.conf"
AZURE_CONF="$CONF_DIR/azure.conf"
GRES_CONF="$CONF_DIR/gres.conf"
TEMP_FILE="/tmp/gres.conf.tmp"
AZURE_TEMP_FILE="/tmp/azure.conf.tmp"

# Backup slurm.conf and update GresTypes to include mps if not already there
if ! grep -q "GresTypes=gpu,mps" "$SLURM_CONF"; then
    cp "$SLURM_CONF" "${SLURM_CONF}.bak"
    sed -i 's/GresTypes=gpu/GresTypes=gpu,mps/' "$SLURM_CONF"
    echo "Updated GresTypes in slurm.conf to include mps."
else
    echo "slurm.conf already has GresTypes=gpu,mps."
fi

# Process each line in azure.conf
cp "$AZURE_CONF" "$AZURE_TEMP_FILE"
> "$AZURE_TEMP_FILE"

while IFS= read -r line; do
    # Check if the line contains a GPU entry and lacks mps to avoid duplicates
    if echo "$line" | grep -q "Gres=gpu" && ! echo "$line" | grep -q "mps:"; then
        # Extract GPU count and calculate MPS count based on GPU count
        GPU_COUNT=$(echo "$line" | sed -n 's/.*Gres=gpu:\([0-9]\+\).*/\1/p')
        MPS_COUNT=$((GPU_COUNT * 100))
        
        # Modify the line with the correct mps value
        modified_line=$(echo "$line" | sed -E "s/Gres=gpu:[0-9]+/Gres=gpu:$GPU_COUNT,mps:$MPS_COUNT/")
        echo "$modified_line" >> "$AZURE_TEMP_FILE"
    else
        # Copy the line as-is if it already has mps or no GPU entry
        echo "$line" >> "$AZURE_TEMP_FILE"
    fi
done < "$AZURE_CONF"

# Move the modified azure.conf back to the original file
mv "$AZURE_TEMP_FILE" "$AZURE_CONF"
echo "Updated Gres line in azure.conf to set mps based on GPU count."

# Process each line in gres.conf
> "$TEMP_FILE"

while IFS= read -r line; do
    # Write the current line to the temporary file
    echo "$line" >> "$TEMP_FILE"
    
    # Check if the line contains a GPU entry and lacks an mps entry to prevent duplication
    if echo "$line" | grep -q "Name=gpu" && ! grep -q "Name=mps" <<< "$line"; then
        # Extract node name, file path, and GPU count
        NODE_NAME=$(echo "$line" | sed -n 's/.*Nodename=\([^ ]*\) .*/\1/p')
        FILE_PATH=$(echo "$line" | sed -n 's/.*File=\([^ ]*\) .*/\1/p')
        GPU_COUNT=$(echo "$line" | sed -n 's/.*Count=\([0-9]*\) .*/\1/p')

        # Debugging step: check the values of NODE_NAME, FILE_PATH, GPU_COUNT
        echo "DEBUG: NODE_NAME=$NODE_NAME, FILE_PATH=$FILE_PATH, GPU_COUNT=$GPU_COUNT"

        # Ensure FILE_PATH is not empty
        if [ -z "$FILE_PATH" ]; then
            echo "ERROR: No device file found for GPU, skipping MPS line addition."
        else
            # Calculate the MPS count based on GPU count
            MPS_COUNT=$((GPU_COUNT * 100))

            # Check if an MPS line for this node already exists in the original gres.conf
            if ! grep -q "Nodename=$NODE_NAME Name=mps" "$GRES_CONF"; then
                # Add the MPS line to the temporary file with the correct File path
                echo "Nodename=$NODE_NAME Name=mps Count=$MPS_COUNT File=$FILE_PATH" >> "$TEMP_FILE"
            fi
        fi
    fi
done < "$GRES_CONF"

# Replace the original gres.conf with the updated content
mv "$TEMP_FILE" "$GRES_CONF"
echo "Updated gres.conf with MPS configuration where needed."

# Restart slurmctld to apply changes
systemctl restart slurmctld
echo "Restarted slurmctld to apply configuration changes."