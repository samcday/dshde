#!/usr/bin/env bash
set -ueo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

ws=$1
ide=$2

projector_port=$(./workon.sh $ws <<HERE
set -ueo pipefail

if [[ ! -f /etc/systemd/user/projector@.service ]]; then
  cat | sudo tee /etc/systemd/user/projector@.service > /dev/null <<UNIT
[Service]
Type=simple
ExecStart=bash -c "exec \"~/.projector/configs/%I/run.sh\""
Restart=on-failure
UNIT
  systemctl --user daemon-reload
fi

if ! projector config show "$ide" | grep "Configuration: $ide$" >/dev/null 2>&1; then
  echo installing $ide
  projector ide autoinstall --config-name "$ide" --ide-name "$ide"
fi

systemctl --user start projector@"$(systemd-escape "$ide")"
projector config show "$ide" | grep "Projector port: " | cut -d':' -f2 | tr -d ' '
HERE
)

local_port=1234
WS_SSH_EXTRA="-O forward -L$local_port:localhost:$projector_port" ./workon.sh $ws

echo "http://localhost:$local_port/?notSecureWarning=false"
