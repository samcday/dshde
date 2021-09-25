#!/usr/bin/env bash
set -ueo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

ip=$(./up.sh <<HERE
set -ueo pipefail
{
mkdir -p /mnt/work/$1
if ! sudo lxc-info $1 >/dev/null 2>&1; then
  sudo lxc-copy -o /dev/stdout -n .root -N $1 -B lvm -s -a
  echo "lxc.mount.entry = /mnt/work/$1 work none bind,create=dir 0 0" | sudo tee -a /var/lib/lxc/$1/config > /dev/null
fi
sudo lxc-start $1 2> >(grep -v "Container is already running" >&2)
} >&2
sudo lxc-info -i -H $1 | head -n1
HERE
)

ssh_command="ssh -F ssh_config -J root@$(cat .state/ip) dev@$ip"
echo $ssh_command
exit

until $ssh_command -n echo hi mom >/dev/null 2>&1; do sleep 1; done

if [ -t 0 ]; then
  exec $ssh_command ${WS_SSH_EXTRA:-} -t -o 'RemoteCommand=cd /work && $SHELL --login'
fi

exec $ssh_command ${WS_SSH_EXTRA:-} -T -o 'RemoteCommand=cd /work && $SHELL --login' <& 0
