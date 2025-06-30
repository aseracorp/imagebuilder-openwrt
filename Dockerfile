FROM debian:stable

ARG version=
ENV version=$version

ARG target=
ENV target=$target

ARG profile=
ENV profile=$profile

ARG packages=
ENV packages=$packages

ARG files=
ENV files=$files

ARG rootfs_partsize=
ENV rootfs_partsize=$rootfs_partsize

ARG storage=
ENV storage=$storage

ARG prod=
ENV prod=$prod


SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get -y install build-essential file libncurses-dev zlib1g-dev gawk git \
    gettext libssl-dev xsltproc rsync wget unzip python3 python3-distutils zstd curl

RUN mkdir /openwrt
WORKDIR /openwrt

RUN if [ "${version}" = "snapshots" ]; then \
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
    mkdir -p files/etc/dropbear && \
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/azukaar/Cosmos-Server/releases/latest | grep "tag_name" | cut -d '"' -f 4) && \
    echo "Downloading Cosmos release $LATEST_RELEASE..." && \
    ZIP_FILE="cosmos-cloud-${LATEST_RELEASE#v}-arm64.zip" && \
    curl -L "https://github.com/azukaar/Cosmos-Server/releases/download/${LATEST_RELEASE}/${ZIP_FILE}" -o "${ZIP_FILE}" && \
    curl -L "https://github.com/azukaar/Cosmos-Server/releases/download/${LATEST_RELEASE}/${ZIP_FILE}.md5" -o "${ZIP_FILE}.md5" && \
    echo "Verifying MD5 checksum..." && \
    md5sum -c "${ZIP_FILE}.md5" && \
    echo "Extracting files..." && \
    unzip -o "${ZIP_FILE}" && \
    mv cosmos-cloud-${LATEST_RELEASE#v}-arm64/* files/opt/cosmos/ && \
    echo "" > files/opt/cosmos/init.conf && \
    echo "STORAGE=${storage}" >> files/opt/cosmos/.env && \
    echo "ROOTFS_PARTSIZE=${rootfs_partsize}" >> files/opt/cosmos/.env && \
    echo "PROD=${prod}" >> files/opt/cosmos/.env

RUN --mount=type=secret,id=TAILSCALE_SERVER,env=tailscale_server \
    echo "TAILSCALE_SERVER=${tailscale_server}" >> files/opt/cosmos/.env

RUN --mount=type=secret,id=TAILSCALE_KEY,env=tailscale_key \
    echo "TAILSCALE_KEY=${tailscale_key}" >> files/opt/cosmos/.env

RUN --mount=type=secret,id=SSH_KEY,env=ssh_key \
    echo "${ssh_key}" >> files/etc/dropbear/authorized_keys
    

COPY --chmod=755 files files

RUN make image PROFILE=${profile} PACKAGES="${packages}" FILES="${files}" ROOTFS_PARTSIZE="${rootfs_partsize}"