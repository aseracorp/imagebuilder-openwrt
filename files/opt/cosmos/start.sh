#!/bin/bash

# cow=true

if [ -z ${cow+x} ]; then
    mkdir -p /opt/docker/volumes
    chattr +C /opt/docker/volumes
elif [ $cow = true ]; then
    mkdir -p /opt/docker/volumes
    chattr -C /opt/docker/volumes
fi

cd /opt/cosmos

chmod +x cosmos
chmod +x cosmos-launcher

./cosmos-launcher && ./cosmos