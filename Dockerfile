# only for local build

FROM registry.opensuse.org/home/kwk/elemental/images/sle_15_sp3/rancher/rancher-node-image/5.2
ARG CACHEBUST
ENV LUET_NOLOCK=true

RUN mv /usr/bin/elemental /usr/bin/elemental.orig

RUN luet install -y \
    meta/cos-modules \
    cloud-config/live \
    cloud-config/recovery \
    cloud-config/network

RUN mv /usr/bin/elemental.orig /usr/bin/elemental
COPY bootargs.cfg /etc/cos/bootargs.cfg
# Starting from here are the lines needed for RancherOS to work

# Make this build unique for ros-updater
RUN echo "TIMESTAMP="`date +"\"%Y%m%d%H%M%S\""` >> /etc/os-release

# Make sure we have a basic rootfs layout
RUN mkdir -p /etc/systemd \
          /etc/rancher \
          /etc/ssh \
          /etc/iscsi \
          /etc/cni \
          /home \
          /opt \
          /root \
          /usr/libexec \
          /var/log \
          /var/lib/rancher \
          /var/lib/kubelet \
          /var/lib/wicked \
          /var/lib/longhorn \
          /var/lib/cni

# Rebuild initrd to setup dracut with the boot configurations
RUN mkinitrd && \
    # aarch64 has an uncompressed kernel so we need to link it to vmlinuz
    kernel=$(ls /boot/Image-* | head -n1) && \
    if [ -e "$kernel" ]; then ln -sf "${kernel#/boot/}" /boot/vmlinuz; fi
