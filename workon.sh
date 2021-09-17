#!/usr/bin/env bash
set -ueo pipefail

if [[ ! -f /.devenv ]]; then
  exec hcloud server ssh dev-env -A ~/dshde/workon.sh "$*"
fi

mkdir -p /mnt/src/$1

if ! docker inspect $1 >/dev/null 2>&1; then
  docker run --runtime=sysbox-runc -d --name $1 -v /mnt/src/$1:/work dev-env-image /sbin/init
fi

exec docker exec -it -u dev -w /work $1 /bin/bash
