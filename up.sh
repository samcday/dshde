#!/usr/bin/env bash
set -ueo pipefail

location=fsn1
server_type=cpx31

(
  if ! hcloud server describe dev-env >/dev/null 2>&1; then
    # A persistent volume is kept alive at all times. It stores "hot" environment data: Docker images, home directory, git working directories, etc.
    # Block store isn't necessarily cheap. 100GB is already going to cost you 5EUR a month.
    # How much space you'll need depends on what projects you're working on - how greedy they are with disk, caches, etc.
    # In future it could be possible to automate a simple "mothballing" process that writes the entire volume disk image to an object store.
    if ! hcloud volume describe dev-env >/dev/null 2>&1; then
      echo creating volume
      hcloud volume create --name dev-env --size 10 --location $location
      hcloud volume enable-protection dev-env delete
    fi

    echo creating server
    hcloud server create --name dev-env --image ubuntu-20.04 --ssh-key key --location $location --type $server_type --volume dev-env
  fi
) &

# Server's up. Do some quick'n'dirty provisioning on it.
until server_ip=$(hcloud server ip dev-env); ssh -o "StrictHostKeyChecking=no" root@$server_ip echo hi mom >/dev/null 2>&1; do sleep 1; done

ssh -o "StrictHostKeyChecking=no" root@$server_ip bash <<'HERE'
echo 'AcceptEnv HCLOUD_TOKEN' > /etc/ssh/sshd_config.d/hcloud.conf
systemctl restart sshd.service
HERE

ssh -O exit root@$server_ip >/dev/null 2>&1 || true

ssh -o "StrictHostKeyChecking=no" -o "SendEnv=HCLOUD_TOKEN" root@$server_ip bash <<'HERE'
set -ueo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! id -u dev >/dev/null 2>&1; then
  useradd -d /mnt/home dev -s /bin/bash
fi

touch /.devenv # So some scripts know when they're running in the dev server already.

# package deps
if [[ ! -f sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb ]]; then
  wget https://downloads.nestybox.com/sysbox/releases/v0.4.0/sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb -O sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb
fi
apt-get update
apt-get install -y hcloud-cli docker.io ./sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb linux-headers-$(uname -r)

# Docker buildx
mkdir -p ~/.docker/cli-plugins
if [[ ! -f ~/.docker/cli-plugins/docker-buildx ]]; then
  wget https://github.com/docker/buildx/releases/download/v0.6.3/buildx-v0.6.3.linux-amd64 -O ~/.docker/cli-plugins/docker-buildx
fi
chmod a+x ~/.docker/cli-plugins/docker-buildx

# persistent volume setup
device_path=$(hcloud volume describe dev-env -o format="{{ .LinuxDevice }}")

if ! blkid $device_path | grep btrfs >/dev/null 2>&1; then
  echo initializing filesystem
  mkfs.btrfs $device_path
fi

if ! mountpoint /mnt >/dev/null 2>&1; then
  echo mounting $device_path on /mnt
  mount $device_path /mnt
fi
mkdir -p /mnt/docker
mkdir -p /mnt/home/.ssh
mkdir -p /mnt/work

chown -R dev:dev /mnt/home

if [[ ! -f /mnt/home/.ssh/authorized_keys ]]; then
  cat /root/.ssh/authorized_keys | sudo -iu dev 'cat > ~/.ssh/authorized_keys'
fi

# Ensure Docker daemon uses persistent volume for containers + images storage.
systemctl stop docker.service
if ! mountpoint /var/lib/docker >/dev/null 2>&1; then
  rm -rf /var/lib/docker
  mkdir -p /var/lib/docker
  mount --bind /mnt/docker /var/lib/docker
fi

# clone project into root homedir and build the env image
if [[ ! -d dshde ]]; then
  git clone https://github.com/samcday/dshde.git
fi
cd dshde
docker buildx build . -t dev-env-image
HERE

exec ./workon.sh dshde
