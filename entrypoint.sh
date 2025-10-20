#!/usr/bin/env bash
set -euo pipefail

RRSYNC="/usr/bin/rrsync"
# check that rrsync exists
if [ ! -x "${RRSYNC}" ]; then
  echo "Error: rrsync not found at ${RRSYNC}" >&2
  exit 1
fi

FS_UID="${FS_UID:-1000}"
FS_GID="${FS_GID:-1000}"
FS_GROUP="${FS_GROUP:-datausers}"

# Refuse to run as root
if [ "$FS_UID" -eq 0 ] || [ "$FS_GID" -eq 0 ]; then
  echo "Refusing to run with FS_UID/FS_GID = 0" >&2
  exit 1
fi

# Ensure group with FS_GID
if getent group "$FS_GID" >/dev/null; then
  FS_GROUP="$(getent group "$FS_GID" | cut -d: -f1)"
else
  groupadd -g "$FS_GID" "$FS_GROUP"
fi

HOST_KEY_DIR="/var/rsync/host"
CLIENT_KEYS_DIR="/var/rsync/clients"

# Generate SSH host keys if they don’t exist
mkdir -p "$HOST_KEY_DIR"
[[ -f "$HOST_KEY_DIR/ssh_host_ecdsa_key" ]]   || ssh-keygen -q -t ecdsa -b 256 -f "$HOST_KEY_DIR/ssh_host_ecdsa_key" -N ""
[[ -f "$HOST_KEY_DIR/ssh_host_ed25519_key" ]] || ssh-keygen -q -t ed25519 -f "$HOST_KEY_DIR/ssh_host_ed25519_key" -N ""
ln -sf "$HOST_KEY_DIR/ssh_host_ecdsa_key"   /etc/ssh/ssh_host_ecdsa_key
ln -sf "$HOST_KEY_DIR/ssh_host_ecdsa_key.pub"   /etc/ssh/ssh_host_ecdsa_key.pub
ln -sf "$HOST_KEY_DIR/ssh_host_ed25519_key" /etc/ssh/ssh_host_ed25519_key
ln -sf "$HOST_KEY_DIR/ssh_host_ed25519_key.pub" /etc/ssh/ssh_host_ed25519_key.pub

install -d -m 755 -o root -g root /etc/ssh/authorized_keys

# Process client public keys
shopt -s nullglob
FOUND=0
for keyfile in $CLIENT_KEYS_DIR/*.pub; do
  user="$(basename "${keyfile%.pub}")"
  if ! [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "Skipping '$user': invalid username" >&2
    continue
  fi
  FOUND=1

  # Create or update user
  # Use -o to allow non-unique UIDs so multiple users can share FS_UID
  if id "$user" >/dev/null 2>&1; then
    usermod -o -u "$FS_UID" -g "$FS_GID" -s /bin/sh -d /emptyhome "$user" || true
  else
    useradd -M -o -u "$FS_UID" -g "$FS_GID" -s /bin/sh -d /emptyhome "$user"
  fi

  # Ensure the account is *unlocked* by setting a real, random hash
  RANDOM_PW="$(openssl rand -base64 32)"
  HASH="$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "$RANDOM_PW")"
  usermod -p "$HASH" "$user"         # set valid hash (not starting with '!' or '*')
  usermod -U "$user" || true         # ensure unlocked (no '!' lock flag)

  install -m 644 -o root -g root /dev/null "/etc/ssh/authorized_keys/$user"
  PUBKEY="$(tr -d '\r\n' < "$keyfile")"
  cat > "/etc/ssh/authorized_keys/$user" <<EOF
command="${RRSYNC} /data",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding ${PUBKEY}
EOF
done
shopt -u nullglob

if [ "$FOUND" -eq 0 ]; then
  echo "ERROR: no $CLIENT_KEYS_DIR/*.pub found — no users would be able to log in." >&2
  exit 1
fi

echo "Configured users (UID:GID=${FS_UID}:${FS_GID}):"
awk -F: -v gid="$FS_GID" -v uid="$FS_UID" '{ if ($3==uid && $4==gid) print "  - "$1 }' /etc/passwd || true

exec "$@"
