#!/usr/bin/env bash
set -ueo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

port=$(./up.sh <<HERE
set -ueo pipefail
{
mkdir -p /mnt/work/$1
if ! docker inspect $1 >/dev/null 2>&1; then
  echo creating pod $1
  docker create --runtime=sysbox-runc --name $1 -h $1 -p 22 -v/mnt/home:/home -v /home/.projector/configs -v /mnt/work/$1:/work dev-env-image /sbin/init
fi
if ! docker ps | grep $1 >/dev/null 2>&1; then
  echo starting pod $1
  docker start $1
fi
docker exec $1 chown dev:dev /home/.projector/configs
} >&2
docker container port $1 22/tcp | head -n1 | cut -d':' -f2
HERE
)

ssh_command="ssh -F ssh_config -J root@$(cat .state/ip) -p $port dev@localhost"

until $ssh_command -n echo hi mom >/dev/null 2>&1; do sleep 1; done

if [ -t 0 ]; then
  exec $ssh_command ${WS_SSH_EXTRA:-} -t -o 'RemoteCommand=cd /work && $SHELL --login'
fi

exec $ssh_command ${WS_SSH_EXTRA:-} -T -o 'RemoteCommand=cd /work && $SHELL --login' <& 0
