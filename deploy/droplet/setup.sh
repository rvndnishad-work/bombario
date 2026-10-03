#!/usr/bin/env bash
# Sets up (or updates) the Bombario room server on an Ubuntu droplet.
# Run as root:
#   curl -fsSL https://raw.githubusercontent.com/rvndnishad-work/bombario/main/deploy/droplet/setup.sh | bash
#
# - Fresh droplet: runs the server plus its own Caddy for HTTPS.
# - A Caddy container already serving ports 80/443 (another site): runs only
#   the server, joins that Caddy's Docker network, adds one site block to its
#   Caddyfile (backed up first, validated, reloaded) and leaves the rest alone.
#
# Optional: DOMAIN=play.example.com (point its DNS A record here first).
# Without it the droplet's IP gets a free name, e.g. 203-0-113-7.sslip.io.
# Running it again pulls the latest code and redeploys.
set -euo pipefail

REPO=https://github.com/rvndnishad-work/bombario.git
DIR=/opt/bombario

if ! command -v docker >/dev/null; then
  echo "==> Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi

# Compiling the server needs more memory than the smallest droplets have.
if [ "$(swapon --noheadings | wc -l)" -eq 0 ]; then
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

# Someone else's proxy on port 443?
PROXY=$(docker ps --filter publish=443 --format '{{.Names}}' | grep -v '^bombario-' | head -n1 || true)

if [ -n "$PROXY" ]; then
  NET=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$PROXY" | awk '{print $1}')
  echo "==> $PROXY already serves ports 80/443; running only the game server on its network ($NET)"
  cat > .env <<ENV
DOMAIN=$DOMAIN
PROXY_NETWORK=$NET
COMPOSE_FILE=docker-compose.yml:docker-compose.shared.yml
ENV
else
  echo "==> Ports 80/443 are free; running the game server with its own Caddy"
  printf 'DOMAIN=%s\nCOMPOSE_PROFILES=caddy\n' "$DOMAIN" > .env
fi

if command -v ufw >/dev/null && ufw status | grep -q active; then
  ufw allow 80/tcp
  ufw allow 443/tcp
fi

echo "==> Building and starting (the first build takes a few minutes)"
docker compose up -d --build --remove-orphans

if [ -n "$PROXY" ]; then
  # Find the existing Caddyfile on the host through the container's mounts.
  CADDYFILE=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy/Caddyfile"}}{{.Source}}{{end}}{{end}}' "$PROXY")
  if [ -z "$CADDYFILE" ]; then
    D=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy"}}{{.Source}}{{end}}{{end}}' "$PROXY")
    [ -n "$D" ] && CADDYFILE="$D/Caddyfile"
  fi
  BLOCK="
# Bombario game server (added by bombario/deploy/droplet/setup.sh)
$DOMAIN {
	reverse_proxy bombario-server:8080
}"
  if [ -n "$CADDYFILE" ] && [ -f "$CADDYFILE" ]; then
    if grep -q "^$DOMAIN {" "$CADDYFILE"; then
      echo "==> $CADDYFILE already has $DOMAIN"
    else
      BACKUP="$CADDYFILE.bak.$(date +%s)"
      cp "$CADDYFILE" "$BACKUP"
      echo "==> Adding $DOMAIN to $CADDYFILE (backup: $BACKUP)"
      # Append in place so a file bind mount keeps pointing at it.
      printf '%s\n' "$BLOCK" >> "$CADDYFILE"
      if ! docker exec "$PROXY" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
        cat "$BACKUP" > "$CADDYFILE"
        echo "Caddy rejected the new config, so I put the old one back." >&2
        echo "Add this to your Caddyfile by hand, then reload $PROXY:" >&2
        echo "$BLOCK" >&2
        exit 1
      fi
    fi
    docker exec "$PROXY" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
  else
    echo "Could not find $PROXY's Caddyfile. Add this to it, then reload Caddy:"
    echo "$BLOCK"
    echo "  docker exec $PROXY caddy reload --config /etc/caddy/Caddyfile"
  fi
fi

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
