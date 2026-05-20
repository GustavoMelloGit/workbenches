# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infrastructure-only repo. No application code. It provisions a portable Linux development container (Debian + Node LTS + Postgres 16 + Redis) that developers connect to via SSH from Zed. The Mac runs only Docker Desktop and Zed; everything else lives inside the container.

## Key commands

```bash
# First-time setup (or after reset)
chmod +x bootstrap.sh && ./bootstrap.sh

# Day-to-day
docker compose up -d          # start container
docker compose stop           # stop container
docker compose build --no-cache  # rebuild image after Dockerfile changes
ssh devenv                    # shell into the container

# Inside the container
sudo supervisorctl status                  # check sshd / postgres / redis
sudo supervisorctl restart postgres        # restart a service
createdb <name>                            # create a project database
pg_isready                                 # check Postgres

# Reset (simulate fresh Mac)
./scripts/reset.sh --backup        # backup volume then wipe everything
./scripts/reset.sh --keep-volume   # wipe image/container but keep data
```

## Architecture

### Boot sequence
`docker compose up` → `entrypoint.sh` (root) → `initdb` on first run if `/home/dev/.pgdata` is empty → `supervisord` → spawns **sshd**, **postgres**, **redis** as the `dev` user.

### Persistent state
Everything lives in the `devenv_dev-home` Docker volume mounted at `/home/dev`:
- `/home/dev/projects/` — cloned repos
- `/home/dev/.pgdata/` — Postgres cluster (survives container rebuilds)
- `/home/dev/.redis/` — Redis data
- `/home/dev/.ssh/`, dotfiles, nvm, etc.

### SSH auth flow
`bootstrap.sh` generates `~/.ssh/devenv` on the Mac, injects the public key as Docker build arg `AUTHORIZED_KEY` (written to `.env`, never committed), and adds a `Host devenv` block with `ForwardAgent yes` to `~/.ssh/config`. GitHub auth inside the container uses the Mac's ssh-agent via agent forwarding — no keys stored in the container.

### Files that matter when changing the image
| File | Purpose |
|---|---|
| `Dockerfile` | Installs packages, Node/nvm, oh-my-zsh; bakes in the SSH authorized key |
| `entrypoint.sh` | Runs as root on container start; initializes Postgres cluster then execs supervisord |
| `config/supervisord.conf` | Declares the three long-running processes (sshd, postgres, redis) |
| `docker-compose.yml` | Single service; only port 2222 exposed (localhost only) |
| `bootstrap.sh` | Runs on the Mac; idempotent setup end-to-end |
| `scripts/reset.sh` | Tears everything down; `--keep-volume` preserves Postgres data |

### Postgres details
- Superuser: `dev` (no password — trust auth, local only)
- Data dir: `/home/dev/.pgdata` (on the persistent volume, not baked into the image)
- Project `.env` uses `DB_HOST=localhost`, `DB_PORT=5432`, `DB_USERNAME=dev`, `DB_PASSWORD=` — no `host.docker.internal`, no port mapping needed
