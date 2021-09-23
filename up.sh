#!/usr/bin/env bash
set -ueo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

location=fsn1
server_type=cpx31
ssh_command="ssh -F ssh_config"

(
  if [[ -f .state/ip ]]; then
    if ! hcloud server describe dev-env >/dev/null 2>&1; then
      rm .state/*
    fi
  fi
) >/dev/null 2>&1 &

{
until server_ip="$(cat .state/ip 2>/dev/null || true)"; $ssh_command -n -o"ConnectTimeout=5" root@$server_ip echo hi mom >/dev/null 2>&1; do
  sleep 1

  if ! find .state/ip -mmin -10 >/dev/null 2>&1; then
    # Bring up a server if there isn't one already.
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
      hcloud server create --name dev-env --image ubuntu-20.04 --ssh-key key --location $location --type $server_type --volume dev-env --user-data-from-file - <<-INIT
#!/usr/bin/env bash
set -ueo pipefail
apt-get update
echo HCLOUD_TOKEN=$HCLOUD_TOKEN >> /etc/environment
INIT
    fi

    hcloud server ip dev-env > .state/ip
  fi
done

# Server's up. Wait for it to be responsive on SSH.
server_ip=$(cat .state/ip)
until $ssh_command -n root@$server_ip echo hi mom >/dev/null 2>&1; do sleep 1; done

# quick, very bad bashops provisioning over the SSH pipe.
if [ .state/provisioned -ot .state/ip ] || [ .state/provisioned -ot up.sh ] || [ .state/provisioned -ot Dockerfile ]; then
$ssh_command root@$server_ip bash -ueo pipefail <<'HERE'
if ! cloud-init status -w >/dev/null 2>&1; then
  echo cloud-init failed
  exit 1
fi

# SSH server tough. Sacred knowledge make SSH server strong.
# https://www.sshaudit.com/hardening_guides.html#ubuntu_20_04_lts
if [[ ! -f /etc/ssh/sshd_config.d/ssh-audit_hardening.conf ]]; then
  rm /etc/ssh/ssh_host_*
  ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
  awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.safe
  mv /etc/ssh/moduli.safe /etc/ssh/moduli
  sed -i 's/^\#HostKey \/etc\/ssh\/ssh_host_\(rsa\|ed25519\)_key$/HostKey \/etc\/ssh\/ssh_host_\1_key/g' /etc/ssh/sshd_config
  echo -e "\n# Restrict key exchange, cipher, and MAC algorithms, as per sshaudit.com\n# hardening guide.\nKexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256\nCiphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr\nMACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com\nHostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-512,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com" > /etc/ssh/sshd_config.d/ssh-audit_hardening.conf
  systemctl restart sshd
fi

. /etc/environment
export HCLOUD_TOKEN
export DEBIAN_FRONTEND=noninteractive

if ! id -u dev >/dev/null 2>&1; then
  useradd -d /mnt/home dev -s /bin/bash
fi

if [[ ! -f /etc/sudoers.d/dev ]]; then
  echo 'dev ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dev
fi

touch /.devenv # So some scripts know when they're running in the dev server already.

# package deps
if [[ ! -f sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb ]]; then
  wget -q https://downloads.nestybox.com/sysbox/releases/v0.4.0/sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb -O sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb
fi

if ! dpkg -s docker.io >/dev/null 2>&1; then
  apt-get install -y hcloud-cli docker.io ./sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb linux-headers-$(uname -r)
fi

usermod -a -G docker dev

# Docker buildx
mkdir -p ~/.docker/cli-plugins
if [[ ! -f ~/.docker/cli-plugins/docker-buildx ]]; then
  wget -q https://github.com/docker/buildx/releases/download/v0.6.3/buildx-v0.6.3.linux-amd64 -O ~/.docker/cli-plugins/docker-buildx
fi
chmod a+x ~/.docker/cli-plugins/docker-buildx

# persistent volume setup
if ! mountpoint /mnt >/dev/null 2>&1; then
  device_path=$(hcloud volume describe dev-env -o format="{{ .LinuxDevice }}")
  echo mounting $device_path on /mnt

  if ! blkid $device_path | grep btrfs >/dev/null 2>&1; then
    echo initializing filesystem
    mkfs.btrfs $device_path
  fi

  mount $device_path /mnt
fi
mkdir -p /mnt/docker
mkdir -p /mnt/home
mkdir -p /mnt/work

chown dev:dev /mnt/home
chown dev:dev /mnt/work

sudo -iu dev bash -c "mkdir -p ~dev/.projector/{cache,configs,apps}"

if [[ ! -f ~dev/.ssh/authorized_keys ]]; then
  cat ~/.ssh/authorized_keys | sudo -iu dev bash -c 'mkdir -m 0700 ~/.ssh; cat > ~/.ssh/authorized_keys'
fi
chmod 0600 ~dev/.ssh/authorized_keys

# Ensure Docker daemon uses persistent volume for containers + images storage.
if ! mountpoint /var/lib/docker >/dev/null 2>&1; then
  systemctl stop docker.service >/dev/null 2>&1
  rm -rf /var/lib/docker
  mkdir -p /var/lib/docker
  mount --bind /mnt/docker /var/lib/docker
fi
HERE

dockerfile_hash=$(shasum -a 512 Dockerfile | cut -d' ' -f1)
if ! $ssh_command -n root@$server_ip docker inspect dev-env-image:$dockerfile_hash >/dev/null 2>&1; then
  time cat Dockerfile | $ssh_command root@$server_ip docker buildx build - -t dev-env-image:$dockerfile_hash -t dev-env-image
fi

touch .state/provisioned
fi
}>&2

server_ip=$(cat .state/ip)
if [ ! -t 0 ]; then
  exec $ssh_command ${SSH_EXTRA:-} -T dev@$server_ip bash <&0
else
  exec $ssh_command ${SSH_EXTRA:-} dev@$server_ip
fi
