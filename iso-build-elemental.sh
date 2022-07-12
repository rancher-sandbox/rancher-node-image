#!/bin/bash

# Export  this here so users dont need to
export DOCKER_BUILDKIT=1

set -e

build()
{
    docker images
    dockerfile | docker build -f - --build-arg IMAGE="${IMAGE}" . "${@}"
}

dockerfile()
{
    cat << "EOF"
FROM registry.opensuse.org/isv/rancher/elemental/teal52/15.3/rancher/elemental-builder-image AS build

RUN mkdir -p /iso/iso-overlay/boot/grub2
RUN echo -e \
'search --file --set=root /boot/kernel.xz\n'\
'set default=0\n'\
'set timeout=10\n'\
'set timeout_style=menu\n'\
'set linux=linux\n'\
'set initrd=initrd\n'\
'if [ "${grub_cpu}" = "x86_64" -o "${grub_cpu}" = "i386" -o "${grub_cpu}" = "arm64" ];then\n'\
'    if [ "${grub_platform}" = "efi" ]; then\n'\
'        if [ "${grub_cpu}" != "arm64" ]; then\n'\
'            set linux=linuxefi\n'\
'            set initrd=initrdefi\n'\
'        fi\n'\
'    fi\n'\
'fi\n'\
'if [ "${grub_platform}" = "efi" ]; then\n'\
'    echo "Please press 't' to show the boot menu on this console"\n'\
'fi\n'\
'set font=($root)/boot/${grub_cpu}/loader/grub2/fonts/unicode.pf2\n'\
'if [ -f ${font} ];then\n'\
'    loadfont ${font}\n'\
'fi\n'\
'menuentry "Install Elemental Teal to disk" --class os --unrestricted {\n'\
'    echo Loading kernel...\n'\
'    $linux ($root)/boot/kernel.xz cdroot root=live:CDLABEL=COS_LIVE rd.live.dir=/ rd.live.squashimg=rootfs.squashfs ata-generic.all-generic-ide=1 rd.driver.post=ata_generic console=tty0 console=ttyS0 rd.cos.disable elemental.install.automatic=false elemental.install.config_url=/run/initramfs/live/config\n'\
'    echo Loading initrd...\n'\
'    $initrd ($root)/boot/rootfs.xz\n'\
'}\n'\
'\n'\
'if [ "${grub_platform}" = "efi" ]; then\n'\
'    hiddenentry "Text mode" --hotkey "t" {\n'\
'        set textmode=true\n'\
'        terminal_output console\n'\
'    }\n'\
'fi\n' > /iso/iso-overlay/boot/grub2/grub.cfg
RUN mkdir -p /iso/iso-overlay/etc/modprobe.d
RUN echo -e \
'options ata_generic all_generic_ide=1\n'\
'install ata_generic /sbin/modprobe ata_piix ; /sbin/modprobe --ignore-install ata_generic\n' \
> /iso/iso-overlay/etc/modprobe.d/98-ata-generic.conf

ARG CONFIG
RUN if [ -n "$CONFIG" ]; then echo "$CONFIG" > /iso/iso-overlay/config; cp /iso/iso-overlay/config /iso/iso-overlay/config.yaml; fi

ARG IMAGE
RUN cd /iso; elemental --debug build-iso -n output --overlay-iso /iso/iso-overlay $IMAGE

FROM scratch AS default
COPY --from=build /iso/output.iso /

EOF
}

usage()
{
    echo "Usage:"
    echo "    $0 ISO_CLOUD_CONFIG"
    echo
    echo "    ISO_CLOUD_CONFIG: An option file that will be used as the default cloud-init in an ISO"
}

CONFIG=$1
IMAGE=registry.opensuse.org/isv/rancher/elemental/teal52/15.3/rancher/elemental-node-image/5.2:latest

if  [ -z "${CONFIG}" ] || echo "$@" | grep -q -- -h; then
    usage
    exit 1
fi  

if [ -n "$CONFIG" ]; then
    CONFIG_DATA="$(<$CONFIG)"
fi
build -o build/ --build-arg CONFIG="${CONFIG_DATA}"
