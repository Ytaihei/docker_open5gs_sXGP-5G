#!/bin/bash

# Deployment files path update script
# Updates all deployment files to use new directory structure

DEPLOYMENT_DIR="/home/taihei/docker_open5gs_sXGP-5G/deployments"

echo "Updating deployment files paths..."

# Update all .yaml files in deployments directory
for file in "$DEPLOYMENT_DIR"/*.yaml; do
    if [ -f "$file" ]; then
        echo "Processing $(basename "$file")..."

        # Update .env file path
        sed -i 's|- \.env|- \.\./\.env|g' "$file"

        # Update volume paths for 4G components
        sed -i 's|- \./hss:|- \.\./4g/hss:|g' "$file"
        sed -i 's|- \./mme:|- \.\./4g/mme:|g' "$file"
        sed -i 's|- \./pcrf:|- \.\./4g/pcrf:|g' "$file"
        sed -i 's|- \./sgwc:|- \.\./4g/sgwc:|g' "$file"
        sed -i 's|- \./sgwu:|- \.\./4g/sgwu:|g' "$file"

        # Update volume paths for 5G components
        sed -i 's|- \./amf:|- \.\./5g/amf:|g' "$file"
        sed -i 's|- \./ausf:|- \.\./5g/ausf:|g' "$file"
        sed -i 's|- \./bsf:|- \.\./5g/bsf:|g' "$file"
        sed -i 's|- \./nrf:|- \.\./5g/nrf:|g' "$file"
        sed -i 's|- \./nssf:|- \.\./5g/nssf:|g' "$file"
        sed -i 's|- \./pcf:|- \.\./5g/pcf:|g' "$file"
        sed -i 's|- \./scp:|- \.\./5g/scp:|g' "$file"
        sed -i 's|- \./smf:|- \.\./5g/smf:|g' "$file"
        sed -i 's|- \./udm:|- \.\./5g/udm:|g' "$file"
        sed -i 's|- \./udr:|- \.\./5g/udr:|g' "$file"
        sed -i 's|- \./upf:|- \.\./5g/upf:|g' "$file"

        # Update volume paths for core components
        sed -i 's|- \./webui:|- \.\./core/webui:|g' "$file"
        sed -i 's|- \./base:|- \.\./core/base:|g' "$file"

        # Update volume paths for RAN components
        sed -i 's|- \./srslte:|- \.\./ran/srslte:|g' "$file"
        sed -i 's|- \./srsran:|- \.\./ran/srsran:|g' "$file"

        # Update log directory path
        sed -i 's|- \./log:|- \.\./log:|g' "$file"

        echo "Updated $(basename "$file")"
    fi
done

echo "All deployment files updated successfully!"
