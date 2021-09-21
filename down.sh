#!/usr/bin/env bash
set -ueo pipefail

until ! hcloud server describe dev-env >/dev/null 2>&1; do
  hcloud volume detach dev-env >/dev/null 2>&1 || true
  hcloud server delete dev-env >/dev/null 2>&1 || true
done

rm .state/*
