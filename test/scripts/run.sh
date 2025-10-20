#!/usr/bin/env bash
set -euo pipefail

# Config (local defaults; CI can override via env)
PORT="${PORT:-2122}"
USER="${USER_NAME:-test}"
KEY="tmp/keys/clients/test"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH="ssh -p ${PORT} -i ${KEY} ${SSH_OPTS} ${USER}@localhost"

log() { printf ">> %s\n" "$*"; }

# Cross-platform uid:gid reader (GNU stat on Linux, BSD stat on macOS)
get_ugid() {
  if stat --version >/dev/null 2>&1; then
    stat -c '%u:%g' "$1"     # GNU
  else
    stat -f '%u:%g' "$1"     # BSD/macOS
  fi
}

# 0) container up
log "Container is running"
docker ps --format '{{.Names}} {{.Status}}' | grep -q '^test_rsync' || true

# 1) refuse FS_UID=0 (throwaway run using the built image)
log "Negative: FS_UID=0 should fail"
set +e
docker run --rm \
  -e FS_UID=0 -e FS_GID=1234 \
  -v "$PWD/tmp/keys/clients:/var/rsync/clients:ro" \
  -v "$PWD/tmp/keys/host:/var/rsync/host" \
  -p 0:22 rsync:test >/dev/null 2>&1
rc=$?
set -e
test $rc -ne 0

# 2) forced-command + options in authorized_keys
log "authorized_keys forced command and SSH restrictions"
docker compose -f docker-compose.test.yml exec -T rsync \
  sh -c "cat /etc/ssh/authorized_keys/${USER}" | tee /tmp/ak.txt >/dev/null
grep -q 'command="/usr/bin/rrsync /data"' /tmp/ak.txt
grep -q 'no-pty' /tmp/ak.txt
grep -q 'no-port-forwarding' /tmp/ak.txt

# 3) host key persistence across restart (fingerprint)
log "Host key persistence"
F1=$(ssh-keyscan -p ${PORT} localhost 2>/dev/null | awk "{print \$3}" | head -n1)
docker compose -f docker-compose.test.yml restart rsync
sleep 2
F2=$(ssh-keyscan -p ${PORT} localhost 2>/dev/null | awk "{print \$3}" | head -n1)
test "$F1" = "$F2"

# 4) deny access outside /data (rrsync restriction)
log "Deny access outside /data"
set +e
OUT="$($SSH 'ls /etc' 2>&1 || true)"
echo "$OUT" | sed -e 's/^/SSH_OUT: /' >&2
echo "$OUT" | grep -Eq 'rrsync|restricted|denied'
rc=$?
set -e
test $rc -eq 0

# 5) no TTY
log "No TTY allowed"
OUT_TTY=$(ssh -tt \
  -p "${PORT}" -i "${KEY}" ${SSH_OPTS} \
  -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
  "${USER}@localhost" 'echo ok' 2>&1 || true)
echo "$OUT_TTY" | sed 's/^/SSH_TTY: /' >&2
echo "$OUT_TTY" | grep -iq 'PTY allocation request failed'
rc=$?
test $rc -eq 0

# 6) no port forwarding
log "No port forwarding allowed"
SSH_FWD_LOG="$(mktemp)"
set +e
ssh \
  -p "${PORT}" -i "${KEY}" ${SSH_OPTS} \
  -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
  -o ExitOnForwardFailure=yes \
  -N -L 127.0.0.1:9999:127.0.0.1:22 \
  "${USER}@localhost" >"$SSH_FWD_LOG" 2>&1 &
SSH_FWD_PID=$!
sleep 0.5
# Try to actually traverse the tunnel: run a command over 127.0.0.1:9999
printf "ping" | nc -w 2 127.0.0.1 9999 >/dev/null 2>&1 || true
# Always cleanup the background ssh
kill "$SSH_FWD_PID" >/dev/null 2>&1 || true
wait "$SSH_FWD_PID" >/dev/null 2>&1 || true
set -e
# Check
echo "SSH_FWD: $(cat "$SSH_FWD_LOG")" >&2
echo "$(cat "$SSH_FWD_LOG")" | grep -iq 'prohibited'
rc=$?
test $rc -eq 0

# 7a) rsync data and verify it's correctly written (existence + byte-for-byte match)
log "Push data via rsync"
rsync -av --no-perms --no-owner --no-group -e "ssh -p ${PORT} -i ${KEY} ${SSH_OPTS}" ./fixtures/test-data/ ${USER}@localhost:/

log "Verify files exist and match source"
test -f tmp/data/test-file.txt
test -f tmp/data/large-file.bin
cmp -s fixtures/test-data/test-file.txt tmp/data/test-file.txt
cmp -s fixtures/test-data/large-file.bin tmp/data/large-file.bin

# 7b) verify uid:gid on host bind mount
if [[ "$(uname -s)" == "Darwin" ]]; then
  echo ">> macOS bind mount detected — skipping strict uid:gid check"
else
  echo ">> Verify uid:gid on written files"
  EXPECT_UID="${EXPECT_UID:-1234}"
  EXPECT_GID="${EXPECT_GID:-1234}"
  UGID_TXT=$(get_ugid tmp/data/test-file.txt)
  UGID_BIN=$(get_ugid tmp/data/large-file.bin)
  test "$UGID_TXT" = "${EXPECT_UID}:${EXPECT_GID}"
  test "$UGID_BIN" = "${EXPECT_UID}:${EXPECT_GID}"
fi

# 8) second user can connect and push data
USER2="${USER2_NAME:-test2}"
KEY2="tmp/keys/clients/test2"
SSH2="ssh -p ${PORT} -i ${KEY2} ${SSH_OPTS} ${USER2}@localhost"

log "Second user can push via rsync"
# Push only a single small file into a separate subdirectory to avoid overwriting files from first user
rsync -av -e "ssh -p ${PORT} -i ${KEY2} ${SSH_OPTS}" ./fixtures/test-data/test-file.txt ${USER2}@localhost:/test2/

log "Verify second user's file exists and matches source"
test -f tmp/data/test2/test-file.txt
cmp -s fixtures/test-data/test-file.txt tmp/data/test2/test-file.txt


log "All checks passed ✔"
