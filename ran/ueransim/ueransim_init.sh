#!/bin/bash
set -e

if [[ -n "$STARTUP_DELAY" ]]; then
    echo "Waiting for ${STARTUP_DELAY} seconds before starting $COMPONENT_NAME..."
    sleep "$STARTUP_DELAY"
fi

mkdir -p /etc/ueransim

if [[ -z "$COMPONENT_NAME" ]]; then
    echo "Error: COMPONENT_NAME environment variable not set"
    exit 1
elif [[ "$COMPONENT_NAME" == "nr_gnb" ]]; then
    cp /mnt/ueransim/gnb.yaml /etc/ueransim/gnb.yaml
    sed -i "s|MCC|$MCC|g" /etc/ueransim/gnb.yaml
    sed -i "s|MNC|$MNC|g" /etc/ueransim/gnb.yaml
    sed -i "s|TAC|$TAC|g" /etc/ueransim/gnb.yaml
    sed -i "s|NR_GNB_IP|$NR_GNB_IP|g" /etc/ueransim/gnb.yaml
    sed -i "s|AMF_IP|$AMF_IP|g" /etc/ueransim/gnb.yaml
    exec /UERANSIM/build/nr-gnb -c /etc/ueransim/gnb.yaml
elif [[ "$COMPONENT_NAME" == "nr_ue" ]]; then
    cp /mnt/ueransim/ue.yaml /etc/ueransim/ue.yaml
    sed -i "s|MCC|$MCC|g" /etc/ueransim/ue.yaml
    sed -i "s|MNC|$MNC|g" /etc/ueransim/ue.yaml
    sed -i "s|NR_GNB_IP|$NR_GNB_IP|g" /etc/ueransim/ue.yaml
    sed -i "s|UE1_IMSI|$UE1_IMSI|g" /etc/ueransim/ue.yaml
    sed -i "s|UE1_KI|$UE1_KI|g" /etc/ueransim/ue.yaml
    sed -i "s|UE1_OP|$UE1_OP|g" /etc/ueransim/ue.yaml
    sed -i "s|UE1_AMF|$UE1_AMF|g" /etc/ueransim/ue.yaml
    sed -i "s|UE1_IMEI|$UE1_IMEI|g" /etc/ueransim/ue.yaml
    exec /UERANSIM/build/nr-ue -c /etc/ueransim/ue.yaml
else
    echo "Error: Invalid COMPONENT_NAME '$COMPONENT_NAME'"
    exit 1
fi
