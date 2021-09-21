#!/usr/bin/env bash
set -ueo pipefail

port=$(hcloud server ssh dev-env ws=$1 bash <<'HERE'
set -ueo pipefail
{
mkdir -p /mnt/src/$ws
if ! docker inspect $ws >/dev/null 2>&1; then
  echo creating pod $ws
  docker create --runtime=sysbox-runc --name $ws -h $ws -p 22 -v/mnt/home:/home -v /mnt/src/$ws:/work dev-env-image /sbin/init
fi
if ! docker ps | grep $ws >/dev/null 2>&1; then
  echo starting pod $ws
  docker start $ws
fi
} >&2
docker container port $ws 22/tcp | head -n1 | cut -d':' -f2
HERE
)

ssh_command="ssh -A -o ControlMaster=auto -o ControlPath=.ssh/$1.socket -o ControlPersist=600 -o ConnectionAttempts=10 -o StrictHostKeyChecking=no -J root@$(hcloud server ip dev-env) -p $port dev@localhost"

( until echo | $ssh_command echo hi mom >/dev/null 2>&1; do sleep 1; done )

if [ -t 0 ]; then
  exec $ssh_command -o 'RemoteCommand=cd /work && $SHELL --login' -t
fi

$ssh_command -T -o 'RemoteCommand=cd /work && $SHELL --login' <& 0
