#!/usr/bin/env bash
# One-time setup of the Bombario room server on a fresh Ubuntu droplet.
# Run as root:
#   curl -fsSL https://raw.githubusercontent.com/rvndnishad-work/bombario/main/deploy/droplet/setup.sh | bash
# Optional: DOMAIN=play.example.com to use your own domain (point its DNS A
# record at the droplet first). Without it the droplet's IP gets a free
# name from sslip.io, e.g. 203-0-113-7.sslip.io.
# Running it again pulls the latest code and redeploys.
set -euo pipefail

REPO=https://github.com/rvndnishad-work/bombario.git
DIR=/opt/bombario

if ! command -v docker >/dev/null; then
  echo "==> Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi

# Compiling the server needs more memory than the smallest droplets have.
if ! swapon --show | grep -q /swapfile; then
  echo "==> Adding 2 GB of swap"
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

if [ -d "$DIR/.git" ]; then
  echo "==> Updating the code"
  git -C "$DIR" pull --ff-only
else
  echo "==> Downloading the code"
  git clone --depth 1 "$REPO" "$DIR"
fi

cd "$DIR/deploy/droplet"
if [ -z "${DOMAIN:-}" ] && [ -f .env ]; then
  DOMAIN=$(sed -n 's/^DOMAIN=//p' .env)
fi
if [ -z "${DOMAIN:-}" ]; then
  IP=$(curl -fsS http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address \
    || curl -fsS https://api.ipify.org)
  DOMAIN="${IP//./-}.sslip.io"
fi
echo "DOMAIN=$DOMAIN" > .env

if command -v ufw >/dev/null && ufw status | grep -q active; then
  ufw allow 80/tcp
  ufw allow 443/tcp
fi

echo "==> Building and starting (the first build takes a few minutes)"
docker compose up -d --build

echo "==> Waiting for https://$DOMAIN/health"
for _ in $(seq 1 60); do
  if curl -fsS "https://$DOMAIN/health" >/dev/null 2>&1; then
    echo
    echo "Bombario server is live at https://$DOMAIN"
    exit 0
  fi
  sleep 5
done
echo "Not answering yet. Check: cd $DIR/deploy/droplet && docker compose logs" >&2
exit 1
