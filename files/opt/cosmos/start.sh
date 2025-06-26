#!/bin/bash

# should the docker volumes be copy on write? This enables compression but accelerates writes onto disk which is harmful for the disk with f.e. database-files. You then need to disable it manually (for databases) on a subfolder basis with 'chattr +C <path-to-subfolder>'. !! Only applies to new files created !!
# cow=true

# additional storage for cosmos? (mmcblk0=internal eMMC)
storage="mmcblk0"

cd /opt/cosmos
touch init.conf

if [[ $(cat init.conf) != "commissioned successfully" ]]; then
    #mount eMMC (btrfs) filesystem (used for cosmos)
    if [ -n "$storage" ]; then
        if [ ! -e /dev/"$storage"p3 ]; then
            echo "add 3rd partition (btrfs) on empty space..." >> init.log
            # add & format 3rd partition after 1024MB
            echo "n
            p
            3
            2097152

            w" | fdisk -W always /dev/"$storage"
            echo "format 3rd partition (btrfs)..." >> init.log
            sleep 5
            partx -u /dev/"$storage"
            mkfs.btrfs /dev/"$storage"p3
            sleep 5
        fi
        if [[ $(findmnt /opt/docker/ -no SOURCE) != "/dev/${storage}p3" ]]; then
            partx -u /dev/"$storage"
            #stop docker service
            service dockerd stop
            # clear docker dir
            rm -R /opt/docker/*
            # mount btrfs partition to docker dir
            echo "mount 3rd partition (btrfs)..." >> init.log
            sleep 10 && block detect | uci import fstab
            uci set fstab.@mount[-1].target='/opt/docker'
            uci set fstab.@mount[-1].enabled='1'
            uci set fstab.@mount[-1].options='compress=zstd:10'
            uci commit fstab
            #set btrfs dockerd storage driver
            echo "switch docker storage driver to btrfs..." >> init.log
            uci set dockerd.globals.storage_driver="btrfs"
            uci commit dockerd
            service dockerd start
        fi
        if [[ $(findmnt /opt/docker/ -no SOURCE) = "/dev/${storage}p3" ]]; then
            if [ -z ${cow+x} ]; then
                echo "disable copy on write on docker volumes..." >> init.log
                mkdir -p /opt/docker/volumes
                chattr +C /opt/docker/volumes
            elif [ $cow = true ]; then
                echo "enable copy on write on docker volumes... (! Danger)" >> init.log
                mkdir -p /opt/docker/volumes
                chattr -C /opt/docker/volumes
            fi
            echo "partition successfully mounted, store state as commissioned in init.conf. Delete the file to check partition-setup again" >> init.log
            echo "commissioned successfully" > init.conf
        else
            echo "failed to mount, reboot in 10s and try again..." >> init.log && \
            sleep 10 && reboot #reboot, because all other commands like partx -u... weren't reliable
        fi
    fi
fi

#make cosmos binaries executable
chmod +x cosmos
chmod +x cosmos-launcher

./cosmos-launcher && ./cosmos