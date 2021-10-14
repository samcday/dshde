set -ueo pipefail

pacman --noconfirm -Syu
pacman --noconfirm -S \
  base-devel man git docker openssh wget \
  python-pip libxext libxi libxrender libxtst freetype2

systemctl enable --now {sshd.service,docker.socket}

pip3 install projector-installer

# Create dev user
if ! id -u dev >/dev/null 2>&1; then
  useradd -G docker -s /bin/bash -d /home dev
fi

[[ ! -d /home ]] && mkdir -p /home
chown dev:dev /home

echo 'dev ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dev
