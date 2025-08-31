#!/bin/bash

# Convert deployment files to use local source-based builds
DEPLOY_DIR="/home/taihei/docker_open5gs_sXGP-5G/deployments"

echo "Converting deployment files to use local source builds..."

for file in "$DEPLOY_DIR"/*.yaml; do
    if [ -f "$file" ] && [[ "$file" != *"srs"* ]]; then
        echo "Processing $(basename "$file")..."

        # Create backup
        cp "$file" "$file.bak"

        # Add build context for Open5GS services
        # Replace 'image: docker_open5gs' with build directive
        sed -i 's|image: docker_open5gs|build:\
      context: ..\
      dockerfile: open5gs/base/Dockerfile|g' "$file"

        echo "Updated $(basename "$file")"
    fi
done

echo "All deployment files converted to use local source builds!"
echo "Backups created with .bak extension"
