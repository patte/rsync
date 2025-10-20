# rsync

Small and secure container to provide rsync access to a shared `/data` volume using SSH keys for authentication.

Features:
- [x] small docker image based on `debian:13-slim`
- [x] openssh-server with hardened sshd config
- [x] rsync (and python3-minimal) installed
- [x] forced command to restrict users to `/usr/bin/rrsync /data`
- [x] on startup:
  - host keys are generated if none are found in `/var/rsync/host`
  - local users and authorized_keys are generated based on keys in `/var/rsync/clients/*.pub`
- [x] GitHub Action to build (daily) and push the image to ghcr.io

Image:
```
ghcr.io/patte/rsync
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
rsync -av -e 'ssh -p 2222 -i keys/clients/test' ./test-data test@localhost:/
```

## Usage

### Docker

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