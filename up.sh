#!/usr/bin/env bash
set -ueo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

location=fsn1
server_type=cpx51
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
      hcloud server create --name dev-env --image debian-11 --ssh-key key --location $location --type $server_type --volume dev-env --user-data-from-file - <<-INIT
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
$ssh_command root@$server_ip server_ip=$server_ip bash -ueo pipefail <<'HERE'
if ! cloud-init status -w >/dev/null 2>&1; then
  echo cloud-init failed
  exit 1
fi

cat > ~/dshde-wind-down.sh <<'WINDDOWN'
#!/usr/bin/env bash
set -ueo pipefail
if [[ "$(loginctl list-sessions)" == "No sessions." ]]; then
  for c in $(lxc-ls -1 --running); do lxc-stop $c; done
fi
WINDDOWN

cat > ~/dshde-shutdown.sh <<'SHUTDOWN'
#!/usr/bin/env bash
set -ueo pipefail
if [[ "$(loginctl list-sessions)" == "No sessions." ]]; then
  for c in $(lxc-ls -1 --running); do lxc-stop $c; done
  if mountpoint /var/lib/lxc >/dev/null 2>&1; then
    umount /var/lib/lxc
  fi
  if mountpoint /mnt >/dev/null 2>&1; then
    umount /mnt
  fi
  . /etc/environment
  export HCLOUD_TOKEN
  hcloud volume detach dev-env || true
  hcloud server delete dev-env
fi
SHUTDOWN

if ! systemctl status dshde-wind-down.timer >/dev/null 2>&1; then
  systemd-run -u dshde-wind-down --on-boot=55m --on-unit-active=1h --timer-property=AccuracySec=1 bash ~/dshde-wind-down.sh
fi

if ! systemctl status dshde-shutdown.timer >/dev/null 2>&1; then
  systemd-run -u dshde-shutdown --on-boot=59m --on-unit-active=1h --timer-property=AccuracySec=1 bash ~/dshde-shutdown.sh
fi

# sshd tweaks
# make sure inactive clients are booted. This ensures the self-expiry behaviour is reliable.
sed -i -e "s/#ClientAliveInterval.*/ClientAliveInterval 15/" -e "s/#ClientAliveCountMax.*/ClientAliveCountMax 3/" /etc/ssh/sshd_config

# SSH server tough. Sacred knowledge make SSH server strong.
# https://www.sshaudit.com/hardening_guides.html#debian_11
if [[ ! -f /etc/ssh/sshd_config.d/ssh-audit_hardening.conf ]]; then
  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
  sed -i 's/^\#HostKey \/etc\/ssh\/ssh_host_\(rsa\|ed25519\)_key$/HostKey \/etc\/ssh\/ssh_host_\1_key/g' /etc/ssh/sshd_config
  awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.safe
  mv -f /etc/ssh/moduli.safe /etc/ssh/moduli
  echo -e "\n# Restrict key exchange, cipher, and MAC algorithms, as per sshaudit.com\n# hardening guide.\nKexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256\nCiphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr\nMACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com\nHostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-512,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com" > /etc/ssh/sshd_config.d/ssh-audit_hardening.conf
  systemctl restart sshd
fi

. /etc/environment
export HCLOUD_TOKEN
export DEBIAN_FRONTEND=noninteractive

if ! id -u dev >/dev/null 2>&1; then useradd -d /mnt/home dev -s /bin/bash; fi
if [[ ! -f /etc/sudoers.d/dev ]]; then echo 'dev ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dev; fi

# package deps
if ! dpkg -s lxc >/dev/null 2>&1; then apt-get install -y hcloud-cli lxc gpg dirmngr; fi

# persistent volume is setup as an LVM volume group.
if ! lvdisplay lxc/lxc >/dev/null 2>&1; then
  device_path=$(hcloud volume describe dev-env -o format="{{ .LinuxDevice }}")
  pvcreate -f $device_path
  vgcreate lxc $device_path
  lvcreate --type thin-pool -n lxc -l 95%FREE lxc
fi

vgchange -a y lxc
sed -i -e "s/.*auto_set_activation_skip =.*/auto_set_activation_skip = 0/" /etc/lvm/lvm.conf

if ! lvdisplay lxc/.data >/dev/null 2>&1; then lvcreate -n .data -V 10G --thinpool lxc lxc; fi
if ! blkid /dev/lxc/.data | grep ext4 >/dev/null 2>&1; then mkfs.ext4 /dev/lxc/.data; fi
if ! mountpoint /mnt >/dev/null 2>&1; then mount /dev/lxc/.data /mnt; fi
if ! mountpoint /var/lib/lxc >/dev/null 2>&1; then mkdir -p /mnt/lxc; mount --bind /mnt/lxc /var/lib/lxc; fi

# dev user basic setup
mkdir -p /mnt/{home,work}
chown dev:dev /mnt/{home,work}
sudo -iu dev bash -c "mkdir -p ~dev/.projector/{cache,configs,apps} ~dev/.ssh"
if [[ ! -f ~dev/.ssh/authorized_keys ]]; then
  cat ~/.ssh/authorized_keys | sudo -iu dev bash -c 'cat > ~/.ssh/authorized_keys'
fi
chmod 0600 ~dev/.ssh/authorized_keys

# lxc setup
if [[ ! -f /var/lib/lxc/dev-config ]]; then
  cat > /var/lib/lxc/dev-config <<LXC
lxc.cap.drop =
lxc.mount.auto = sys:rw proc:rw cgroup-full:rw
lxc.apparmor.profile = unconfined
lxc.include = /usr/share/lxc/config/nesting.conf
lxc.net.0.type = veth
lxc.net.0.link = lxcbr0
lxc.net.0.flags = up
lxc.mount.entry = /mnt/home home none bind 0 0
LXC
fi

# initialize root container
if ! lxc-info .root >/dev/null 2>&1; then
  lxc-create -n .root -t download -f /var/lib/lxc/dev-config -B lvm --fssize 10G -- -d archlinux -r current -a amd64 --keyserver hkps://keys.openpgp.org/
  lxc-start .root
  until lxc-attach .root bash <<< "ping -c1 -w1 $server_ip" >/dev/null 2>&1; do sleep 1; done
  lxc-attach .root bash <<INITROOT
set -ueo pipefail

pacman --noconfirm -Syu
pacman --noconfirm -S \
  base-devel man git docker openssh \
  python-pip libxext libxi libxrender libxtst freetype2

systemctl enable --now {sshd.service,docker.socket}

pip3 install projector-installer
# Create dev user
useradd -G docker -d /home dev
echo 'dev ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dev
INITROOT
fi
HERE

touch .state/provisioned
fi
}>&2

server_ip=$(cat .state/ip)
if [ ! -t 0 ]; then
  exec $ssh_command ${SSH_EXTRA:-} -T dev@$server_ip bash <&0
else
  exec $ssh_command ${SSH_EXTRA:-} dev@$server_ip
fi
