FROM debian:stable

ARG version=snapshot
ENV version=$version

ARG target=bcm27xx-bcm2711
ENV target=$target

ARG profile=rpi-4
ENV profile=$profile

ARG packages=
ENV packages=$packages

ARG files=files
ENV files=$files

ARG rootfs_partsize=896
ENV rootfs_partsize=$rootfs_partsize

ARG btrfs-partition=0
ENV btrfs-partition=$btrfs-partition

ARG ssh-key=
ENV ssh-key=$ssh-key

SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get -y install build-essential file libncurses-dev zlib1g-dev gawk git \
    gettext libssl-dev xsltproc rsync wget unzip python3 python3-distutils zstd curl

RUN mkdir /openwrt
WORKDIR /openwrt

RUN if [ "${version}" = "snapshot" ]; then \
    curl -L "https://downloads.openwrt.org/snapshots/targets/${target//-//}/openwrt-imagebuilder-${target}.Linux-x86_64.tar.zst" -o "openwrt-imagebuilder-${target}.Linux-x86_64.tar.zst" && \
    curl -L "https://downloads.openwrt.org/snapshots/targets/${target//-//}/sha256sums" -o sha256sums; \
    else \
    curl -L "https://downloads.openwrt.org/releases/${version}/targets/${target//-//}/openwrt-imagebuilder-${version}-${target}.Linux-x86_64.tar.zst" -o "openwrt-imagebuilder-${version}-${target}.Linux-x86_64.tar.zst" && \
    curl -L "https://downloads.openwrt.org/releases/${version}/targets/${target//-//}/sha256sums" -o sha256sums; \
    fi && \
    sha256sum --check --ignore-missing sha256sums && \
    tar --zstd -x -f openwrt-imagebuilder-* && \
    rm openwrt-imagebuilder-*.tar.zst && rm sha256sums && \
    mv openwrt-imagebuilder-* openwrt-imagebuilder

WORKDIR /openwrt/openwrt-imagebuilder

RUN echo "INSTALLING COSMOS CLOUD..." && \
    echo "Creating directories..." && \
    mkdir -p files/opt/cosmos && \
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/azukaar/Cosmos-Server/releases/latest | grep "tag_name" | cut -d '"' -f 4) && \
    echo "Downloading Cosmos release $LATEST_RELEASE..." && \
    ZIP_FILE="cosmos-cloud-${LATEST_RELEASE#v}-arm64.zip" && \
    curl -L "https://github.com/azukaar/Cosmos-Server/releases/download/${LATEST_RELEASE}/${ZIP_FILE}" -o "${ZIP_FILE}" && \
    curl -L "https://github.com/azukaar/Cosmos-Server/releases/download/${LATEST_RELEASE}/${ZIP_FILE}.md5" -o "${ZIP_FILE}.md5" && \
    echo "Verifying MD5 checksum..." && \
    md5sum -c "${ZIP_FILE}.md5" && \
    echo "Extracting files..." && \
    unzip -o "${ZIP_FILE}" && \
    mv cosmos-cloud-${LATEST_RELEASE#v}-arm64/* files/opt/cosmos/

RUN mkdir -p files/etc/dropbear && echo "${ssh-key}" >> files/etc/dropbear/authorized_keys

COPY --chmod=755 files files

RUN echo "check for btrfs-partition = ${btrfs-partition}" && \
    if [ "${btrfs-partition}" = 0 ]; then \
    echo "add btrfs-partition..." && \
    rm files/etc/uci-defaults/09-btrfs-partition; \
    fi

RUN make image PROFILE=${profile} PACKAGES="${packages}" FILES="${files}" ROOTFS_PARTSIZE="${rootfs_partsize}"