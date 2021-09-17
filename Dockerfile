# syntax = docker/dockerfile:1.2

FROM archlinux

# Install package deps.
RUN --mount=type=cache,target=/var/cache/pacman \
    pacman --noconfirm -Syu && \
    pacman --noconfirm -S \
    base-devel \
    openssh \
    python-pip \
    # Jetbrains Projector requirements
    libxext libxi libxrender libxtst freetype2

RUN systemctl enable sshd.service

# Create dev user
RUN rmdir /home && useradd -d /home -m dev
RUN echo 'dev ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dev
ADD authorized_keys ~/.ssh/authorized_keys

USER dev
ENV PATH=$PATH:/home/.local/bin
WORKDIR /work

# Install Projector + JB IDEs
RUN pip3 install projector-installer --user
RUN projector --accept-license self-update
RUN --mount=type=cache,target=/home/.projector/cache,uid=1000 \
    projector install --no-auto-run "GoLand 2020.3.5" && \
    projector install --no-auto-run "CLion 2020.3.4"
