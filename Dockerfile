# only for local build

FROM registry.opensuse.org/home/kwk/elemental/images/sle_15_sp3/rancher/rancher-node-image/5.2
ARG CACHEBUST
ENV LUET_NOLOCK=true

RUN luet install -y \
    meta/cos-light \
    cloud-config/live \
    cloud-config/recovery \
    cloud-config/network

# Starting from here are the lines needed for Elemental to work

# Make this build unique for elemental-updater
RUN echo "TIMESTAMP="`date +"\"%Y%m%d%H%M%S\""` >> /etc/os-release

# Make sure we have a basic rootfs layout
RUN mkdir -p /etc/rancher \
          /etc/cni \
          /var/lib/rancher \
          /var/lib/kubelet \
          /var/lib/longhorn \
          /var/lib/cni

# Rebuild initrd to setup dracut with the boot configurations
RUN mkinitrd && \
    # aarch64 has an uncompressed kernel so we need to link it to vmlinuz
    kernel=$(ls /boot/Image-* | head -n1) && \
    if [ -e "$kernel" ]; then ln -sf "${kernel#/boot/}" /boot/vmlinuz; fi
