#!/bin/bash

# cow=true

# additional storage for cosmos? (mmcblk0=internal eMMC)
storage="mmcblk0"

# log potential errors
exec >/tmp/start-cosmos.log 2>&1

#mount eMMC (btrfs) filesystem (used for cosmos)
if [ -n "$storage" ]; then
    if [ ! -e /dev/"$storage"p3 ]; then
        echo "add 3rd partition (btrfs) on empty space..."
        # add 3rd partition after 1024MB
        #stop docker service
        service dockerd stop
        parted -sf /dev/"$storage" -- mkpart primary btrfs 1024 100%
        sleep 10 && partx -u /dev/$storage
        #format partition
        echo "format 3rd partition (btrfs)..."
        mkfs.btrfs /dev/"$storage"p3 -qf
        # clear docker dir
        rm -R /opt/docker/*
        # mount btrfs partition to docker dir
        echo "mount 3rd partition (btrfs)..."
        sleep 10 && block detect | uci import fstab
        uci set fstab.@mount[-1].target='/opt/docker'
        uci set fstab.@mount[-1].enabled='1'
        uci set fstab.@mount[-1].options='compress=zstd:10'
        uci commit fstab
        #set btrfs dockerddocker storage driver
        echo "switch docker storage driver to btrfs..."
        uci set dockerd.globals.storage_driver="btrfs"
        uci commit dockerd
        service dockerd start
        mkdir -p /opt/docker/volumes
        sleep 10 && chattr +C /opt/docker/volumes
    fi
    if [ -z ${cow+x} ]; then
        mkdir -p /opt/docker/volumes
        chattr +C /opt/docker/volumes
    elif [ $cow = true ]; then
        mkdir -p /opt/docker/volumes
        chattr -C /opt/docker/volumes
    fi
fi

cd /opt/cosmos

chmod +x cosmos
chmod +x cosmos-launcher

./cosmos-launcher && ./cosmos