#!/usr/bin/env bash
set -ueo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if hcloud server describe dev-env >/dev/null 2>&1; then
  ssh -T -F ssh_config root@$(hcloud server ip dev-env) <<'CLEANUP'
for vm in $(lxc-ls --running); do
  echo stopping $vm
  lxc-stop $vm
done

loginctl kill-user dev
umount /var/lib/lxc || true
umount /mnt || true
CLEANUP
fi

if [[ -f .state/ip ]]; then
  ssh -F ssh_config -O exit {root,dev}@$(cat .state/ip) || true
fi

until ! hcloud server describe dev-env >/dev/null 2>&1; do
  hcloud volume detach dev-env >/dev/null 2>&1 || true
  hcloud server delete dev-env >/dev/null 2>&1 || true
done

rm .state/*
