#!/bin/sh

# Backup paths
SLURM_CONF="/etc/slurm/slurm.conf"
AZURE_CONF="/etc/slurm/azure.conf"
GRES_CONF="/etc/slurm/gres.conf"
TEMP_FILE="/tmp/gres.conf.tmp"

# Backup slurm.conf and update only if "mps" is missing in GresTypes
if ! grep -q "GresTypes=gpu,mps" "$SLURM_CONF"; then
    cp "$SLURM_CONF" "${SLURM_CONF}.bak"
    sed -i 's/GresTypes=gpu/GresTypes=gpu,mps/' "$SLURM_CONF"
    echo "Updated GresTypes in slurm.conf to include mps."
else
    echo "slurm.conf already has GresTypes=gpu,mps."
fi

# Backup azure.conf and update only if "mps" format is incorrect or missing
if grep -q "Gres=gpu" "$AZURE_CONF"; then
    cp "$AZURE_CONF" "${AZURE_CONF}.bak"
    
    # Use sed to dynamically set mps based on the GPU count
    sed -i -E 's/(Gres=gpu:([0-9]+))(,mps:[0-9]+)?/\1,mps:\2*100/' "$AZURE_CONF"
    
    # Now correct the output by calculating the mps value based on the GPU count
    sed -i -E 's/mps:([0-9]+)\*100/mps:$(echo "\1 * 100" | bc)/' "$AZURE_CONF"
    
    echo "Updated Gres line in azure.conf to set mps based on GPU count."
else
    echo "No Gres=gpu line found in azure.conf; skipping update."
fi

# Clear temporary file
> "$TEMP_FILE"

# Process each line in gres.conf
while IFS= read -r line; do
    # Write the current line to the temporary file
    echo "$line" >> "$TEMP_FILE"
    
    # Check if the line contains a GPU entry
    if echo "$line" | grep -q "Name=gpu"; then
        # Extract node name and file path
        NODE_NAME=$(echo "$line" | sed -n 's/.*Nodename=\([^ ]*\) .*/\1/p')
        FILE_PATH=$(echo "$line" | sed -n 's/.*File=\([^ ]*\) .*/\1/p')
        GPU_COUNT=$(echo "$line" | sed -n 's/.*Count=\([0-9]*\) .*/\1/p')
        MPS_COUNT=$((GPU_COUNT * 100))

        # Check if an MPS line for this node already exists in the original gres.conf
        if ! grep -q "Nodename=$NODE_NAME Name=mps" "$GRES_CONF"; then
            # Add the MPS line to the temporary file
            echo "Nodename=$NODE_NAME Name=mps Count=$MPS_COUNT File=$FILE_PATH" >> "$TEMP_FILE"
        fi
    fi
done < "$GRES_CONF"

# Replace the original gres.conf with the updated content
mv "$TEMP_FILE" "$GRES_CONF"
echo "Updated gres.conf with MPS configuration where needed."

# Restart slurmctld to apply changes
systemctl restart slurmctld
