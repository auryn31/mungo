#!/usr/bin/env bash
# Brings up the 3-node replica set for the replset_* integration tests:
# generates the keyfile, starts the nodes, initiates the set and creates the
# root user. Idempotent-ish: safe to re-run after `replset-down.sh`.
set -euo pipefail

cd "$(dirname "$0")/.."

KEYFILE=docker/mongo/keyfile

# 1. Keyfile for internal replica-set auth. mongod requires it to be owned by
#    the in-container mongodb user (uid 999) with 0400 perms.
if [ ! -f "$KEYFILE" ]; then
  mkdir -p docker/mongo
  openssl rand -base64 756 > "$KEYFILE"
fi
chmod 400 "$KEYFILE"
# chown may need sudo on CI runners; ignore failure when already correct.
sudo chown 999:999 "$KEYFILE" 2>/dev/null || chown 999:999 "$KEYFILE" 2>/dev/null || true

# 2. Start the nodes.
docker compose -f docker-compose.replset.yml up -d

# 3. Wait for mongo1 to answer.
echo "waiting for mongo1..."
for _ in $(seq 1 30); do
  if docker exec mungo-rs1 mongosh --quiet --port 27017 --eval 'db.adminCommand("ping")' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# 4. Initiate the replica set (localhost exception applies before any user
#    exists, and only from inside the node over localhost).
#    db.hello() needs no auth, so it works whether or not a user exists yet;
#    setName is only present once the set is initiated.
docker exec mungo-rs1 mongosh --quiet --port 27017 --eval '
  if (!db.hello().setName) {
    rs.initiate({
      _id: "mungo-rs",
      members: [
        { _id: 0, host: "localhost:27017" },
        { _id: 1, host: "localhost:27018" },
        { _id: 2, host: "localhost:27019" }
      ]
    })
  }
'

# 5. Wait for a primary to be elected.
echo "waiting for primary..."
for _ in $(seq 1 30); do
  if docker exec mungo-rs1 mongosh --quiet --port 27017 --eval 'db.hello().isWritablePrimary' 2>/dev/null | grep -q true; then
    break
  fi
  sleep 2
done

# 6. Create the root user. The localhost exception permits creating the first
#    user but NOT reading users (usersInfo), so we can't pre-check — just
#    create and swallow the "already exists" error on local re-runs.
docker exec mungo-rs1 mongosh --quiet --port 27017 --eval '
  try {
    db.getSiblingDB("admin").createUser({
      user: "root", pwd: "root", roles: [{ role: "root", db: "admin" }]
    });
  } catch (e) {
    if (e.codeName !== "DuplicateKey" && !/already exists/i.test(e.message)) throw e;
  }
'

echo "replica set mungo-rs is up on localhost:27017-27019 (root/root)"
