#!/bin/bash

# should the docker volumes be copy on write? This enables compression but accelerates writes onto disk which is harmful for the disk with f.e. database-files. You then need to disable it manually (for databases) on a subfolder basis with 'chattr +C <path-to-subfolder>'. !! Only applies to new files created !!
# cow=true

cd /opt/cosmos
source .env
touch init.conf

# workaround for raspberry pi retaining settings after reflash (https://forum.openwrt.org/t/pi-remembers-my-mistakes/164450/14)
if [[ $(cat init.conf) = "commissioned successfully with btrfs-storage" ]]; then
    if [ -n "${STORAGE}" ]; then
        if [ ! -e /dev/"${STORAGE}"p3 ]; then
            # missing partition despite state "commission successfully", force re-init
            firstboot -y && reboot && exit 0
        fi
    fi
fi

if [[ $(cat init.conf | cut -c 0-25) != "commissioned successfully" ]]; then
    echo "$(date +"%F_%H%M%S") start init..." >> init.log
    if [ $(tailscale status --peers=false --json | grep Online | sed -e "s/^.*: //" -e "s/,$//") != "true" ]; then
        echo "$(date +"%F_%H%M%S") configure tailscale and remove keys..." >> init.log
        tailscale up --login-server=${TAILSCALE_SERVER} --auth-key=${TAILSCALE_KEY} --ssh --accept-dns --accept-routes
        if [ ${PROD} -eq 1 ]; then
            #Disable tailscale on production-nodes
            tailscale down
        else
            service tailscale enable
        fi
    fi
    #mount eMMC (btrfs) filesystem (used for cosmos)
    if [ -n "${STORAGE}" ]; then
        if [ ! -e /dev/"${STORAGE}"p3 ]; then
            start_sector=$(((64+8+${ROOTFS_PARTSIZE})*2048))
            echo "$(date +"%F_%H%M%S") add 3rd partition (btrfs) on empty space (start-sector: ${start_sector})..." >> init.log
            # add & format 3rd partition after 1024MB
            echo "n
            p
            3
            $start_sector

            w" | fdisk -W always /dev/"${STORAGE}"
            echo "$(date +"%F_%H%M%S") format 3rd partition (btrfs)..." >> init.log
            sleep 5
            partx -u /dev/"${STORAGE}"
            mkfs.btrfs /dev/"${STORAGE}"p3
            sleep 5
        fi
        if [[ $(findmnt /opt/docker/ -no SOURCE) != "/dev/${STORAGE}p3" ]]; then
            partx -u /dev/"${STORAGE}"
            #stop docker service
            service dockerd stop
            # clear docker dir
            rm -R /opt/docker/*
            # mount btrfs partition to docker dir
            echo "$(date +"%F_%H%M%S") mount 3rd partition (btrfs)..." >> init.log
            sleep 5 && block detect | uci import fstab
            uci set fstab.@mount[-1].target='/opt/docker'
            uci set fstab.@mount[-1].enabled='1'
            uci set fstab.@mount[-1].options='compress=zstd:10'
            uci commit fstab
            #set btrfs dockerd storage driver
            echo "$(date +"%F_%H%M%S") switch docker storage driver to btrfs..." >> init.log
            uci set dockerd.globals.storage_driver="btrfs"
            uci commit dockerd
            service dockerd start
        fi
        if [[ $(findmnt /opt/docker/ -no SOURCE) = "/dev/${STORAGE}p3" ]]; then
            if [ -z ${cow+x} ]; then
                echo "$(date +"%F_%H%M%S") disable copy on write on docker volumes..." >> init.log
                mkdir -p /opt/docker/volumes
                chattr +C /opt/docker/volumes
            elif [ $cow = 1 ]; then
                echo "$(date +"%F_%H%M%S") enable copy on write on docker volumes... (! Danger)" >> init.log
                mkdir -p /opt/docker/volumes
                chattr -C /opt/docker/volumes
            fi
            echo "$(date +"%F_%H%M%S") partition successfully mounted, store state as commissioned in init.conf. Delete the file to check partition-setup again" >> init.log
            echo "commissioned successfully with btrfs-storage" > init.conf
        else
            echo "$(date +"%F_%H%M%S") failed to mount, reboot now and try again..." >> init.log && \
            reboot && exit 0 #reboot, because all other commands like partx -u... weren't reliable
        fi
    else
        echo "$(date +"%F_%H%M%S") init finished without btrfs-storage" >> init.log
        echo "commissioned successfully without btrfs-storage" > init.conf
    fi
fi

#make cosmos binaries executable
chmod +x cosmos
chmod +x cosmos-launcher

./cosmos-launcher && ./cosmos