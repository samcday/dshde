# syntax = docker/dockerfile:1.2

FROM archlinux

# Install package deps.
RUN --mount=type=cache,target=/var/cache/pacman \
    pacman --noconfirm -Syu && \
    pacman --noconfirm -S \
    base-devel \
    git \
    docker \
    openssh \
    python-pip \
    # Jetbrains Projector requirements
    libxext libxi libxrender libxtst freetype2

RUN systemctl enable sshd.service

# Create dev user
RUN rmdir /home && useradd -d /home -m dev
RUN echo 'dev ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dev

# Install Projector.
RUN pip3 install projector-installer
