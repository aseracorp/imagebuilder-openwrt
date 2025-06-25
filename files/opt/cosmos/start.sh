#!/bin/bash

mkdir -p /opt/docker/volumes
chattr +C /opt/docker/volumes

cd /opt/cosmos

chmod +x cosmos
chmod +x cosmos-launcher

./cosmos-launcher && ./cosmos