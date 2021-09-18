#!/usr/bin/env bash
set -ueo pipefail

location=fsn1
server_type=cpx31

if ! hcloud volume describe dev-env >/dev/null 2>&1; then
  echo creating volume
  hcloud volume create --name dev-env --size 10 --location $location
  hcloud volume enable-protection dev-env delete
fi

if ! hcloud server describe dev-env >/dev/null 2>&1; then
  echo creating server
  hcloud server create --name dev-env --image ubuntu-20.04 --ssh-key key --location $location --type $server_type --volume dev-env --user-data-from-file <(cat cloud-init.sh | envsubst)
fi

ip=$(hcloud server ip dev-env)
echo waiting for server to initialize
until ssh -o "StrictHostKeyChecking=no" root@$ip cloud-init status -w >/dev/null 2>&1; do sleep 1; done

echo server initialized
