#!/usr/bin/env bash
set -ueo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

increment=${1:-5}

hcloud volume resize --size $(( $(hcloud volume describe dev-env -o "format={{ .Size }}") + $increment )) dev-env
sleep 1
./up.sh <<< "sudo btrfs filesystem resize max /mnt"
