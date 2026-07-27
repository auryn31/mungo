#!/usr/bin/env bash
# Tears down the replica set and its volumes.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -f docker-compose.replset.yml down -v
