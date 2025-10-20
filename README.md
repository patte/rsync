# rsync

<a href="https://github.com/patte/rsync/actions"><img src="https://github.com/patte/rsync/actions/workflows/test.yml/badge.svg" alt="Tests" height="18"></a>

Small and secure container to provide rsync access to a shared `/data` volume using SSH keys for authentication.

Features:
- [x] small docker image based on `debian:13-slim`
- [x] openssh-server with hardened sshd config
- [x] rsync (and python3-minimal) installed
- [x] forced command to restrict users to `/usr/bin/rrsync /data`
- [x] `FS_UID` and `FS_GID` to control the ownership of files created by clients
- [x] on startup:
  - host keys are generated if none are found in `/var/rsync/host`
  - local users and authorized_keys are generated based on keys in `/var/rsync/clients/*.pub`
- [x] GitHub Action to build (daily) and push the image to ghcr.io
- [x] Test harness using docker-compose in `test/` 

Image:
```
ghcr.io/patte/rsync
```

## Controlling file ownership (FS_UID/FS_GID)

FS_UID and FS_GID let you control which numeric user and group ID own files written to /data by any authenticated client.

- Defaults: FS_UID=1000 and FS_GID=1000 if not set.
- Shared across users: All SSH users created from /var/rsync/clients/*.pub share the same FS_UID/FS_GID. At the filesystem level, their writes are indistinguishable by user; use SSH logs if you need per-user auditing.
- Non-root only: The container will refuse to start if either FS_UID or FS_GID is 0.

Choosing values
- If you bind-mount a host directory to /data on a Linux host, set FS_UID/FS_GID to the numeric uid:gid you want to see on the host for created files (for example, your host user and group IDs).
- Existing files in the mounted directory are not modified; changing FS_UID/FS_GID later won’t rewrite ownership. Use chown on the host if you need to migrate existing data.

Recommended rsync options:
Because the process that actually handles the rsync/rrsync session inside the container runs as FS_UID:FS_GID it's not allowed to set arbitrary permissions or ownership on created files.
Therefore, when sending data it's recommended to disable preserving permissions, owner and group. For example:
```bash
rsync -a --no-perms --no-owner --no-group -e "ssh -p 2222 -i keys/clients/test" ./test-data/ test@localhost:/
```

## Development

Generate client keys for testing:
```bash
mkdir -p keys/clients
ssh-keygen -t ed25519 -f keys/clients/test -N ""
```

Generate some test data:
```bash
mkdir ./test-data
echo "This is a test file." > test-data/test-file.txt
dd if=/dev/urandom of=test-data/large-file.bin bs=1m count=10
```

Build and run the container:
```bash
docker compose build && docker compose down && docker compose up
```

```bash
rsync -av -e 'ssh -p 2222 -i keys/clients/test' ./test-data/ test@localhost:/
```

## Usage

### Docker
Example docker run:
```bash
docker run -d \
  --name rsync \
  --cap-drop=ALL \
  --cap-add=CHOWN --cap-add=FOWNER --cap-add=SETUID --cap-add=SETGID --cap-add=SYS_CHROOT \
  -p 2222:22 \
  -v /path/to/data:/data \
  -v /path/to/host-keys:/var/rsync/host \
  -v /path/to/client-keys:/var/rsync/clients:ro \
  ghcr.io/patte/rsync
```

### quadlet
Example podman quadlet: rsync.container
```ini
[Unit]
After=network.target

[Container]
Image=ghcr.io/patte/rsync:main
AutoUpdate=registry
Volume=/path/to/keys/rsync/keys:/var/rsync
Volume=/path/to/data/:/data/
PublishPort=2222:22
PublishPort=[::]:2222:22
Environment=FS_UID=1001
Environment=FS_GID=1001

[Service]
Restart=on-failure

[Install]
WantedBy=multi-user.target
```