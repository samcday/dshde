#!/usr/bin/env bash
set -ueo pipefail

export HCLOUD_TOKEN=${HCLOUD_TOKEN}
export DEBIAN_FRONTEND=noninteractive

# Do some freaky global state shit.
touch /.devenv # So some scripts know when they're running in the dev server already.
echo "HCLOUD_TOKEN=\"${HCLOUD_TOKEN}\"" >> /etc/environment # So the server can talk to hcloud API for useful stuff later.

# package deps
wget https://downloads.nestybox.com/sysbox/releases/v0.4.0/sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb
apt-get update
apt-get install -y hcloud-cli docker.io ./sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb linux-headers-$(uname -r)

# Docker buildx
mkdir -p ~/.docker/cli-plugins
wget https://github.com/docker/buildx/releases/download/v0.6.3/buildx-v0.6.3.linux-amd64 -O ~/.docker/cli-plugins/docker-buildx
chmod a+x ~/.docker/cli-plugins/docker-buildx

# persistent volume setup
dev=$(hcloud volume describe dev-env -o format="{{ .LinuxDevice }}")
if ! blkid $dev | grep btrfs >/dev/null 2>&1; then
  mkfs.btrfs $dev
fi
mount $dev /mnt
mkdir -p /mnt/docker
mkdir -p /mnt/home
mkdir -p /mnt/work

# Ensure Docker daemon uses persistent volume for containers + images storage.
systemctl stop docker.service
rm -rf /var/lib/docker
mkdir -p /var/lib/docker
mount --bind /mnt/docker /var/lib/docker

# clone project into root homedir and build the env image
git clone https://github.com/samcday/dshde.git
cd dshde
docker buildx build . -t dev-env-image
