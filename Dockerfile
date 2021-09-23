# syntax = docker/dockerfile:1.2

FROM archlinux

# Install package deps.
RUN --mount=type=cache,target=/var/cache/pacman \
    pacman --noconfirm -Syu && \
    pacman --noconfirm -S \
    base-devel \
    man \
    git \
    docker \
    openssh \
    python-pip \
    # Jetbrains Projector requirements
    libxext libxi libxrender libxtst freetype2

# Install Projector.
RUN pip3 install projector-installer

RUN systemctl enable sshd.service
RUN systemctl mask systemd-firstboot.service systemd-udevd.service systemd-modules-load.service systemd-journald-audit.socket systemd-udev-trigger.service

# Create dev user
RUN rmdir /home && useradd -d /home -m dev
RUN echo 'dev ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dev
