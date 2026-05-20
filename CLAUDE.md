# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infrastructure-only repo ("workbench factory"). No application code. Running `./bootstrap.sh` creates a named workbench: a portable Linux container (Debian + Node LTS + Postgres 16 + Redis) that developers connect to via SSH from Zed. Multiple workbenches can run in parallel, each fully isolated. The Mac runs only Docker Desktop and Zed; everything else lives inside the container.

## Key commands

```bash
# Create or start a workbench
chmod +x bootstrap.sh && ./bootstrap.sh   # asks for workbench name

# Day-to-day (replace <nome> with the workbench name)
docker compose --project-name <nome> --env-file workbenches/<nome>/.env up -d
docker compose --project-name <nome> --env-file workbenches/<nome>/.env stop
ssh <nome>                    # shell into the workbench

# Inside the container
sudo supervisorctl status                  # check sshd / postgres / redis
sudo supervisorctl restart postgres        # restart a service
createdb <name>                            # create a project database
pg_isready                                 # check Postgres

# Reset a workbench
./scripts/reset.sh <nome>              # wipe everything
./scripts/reset.sh <nome> --backup     # backup volume first
./scripts/reset.sh <nome> --keep-volume  # keep data, wipe image/container
```

## Architecture

### Workbench state
Each workbench stores everything in `workbenches/<nome>/.env` (gitignored).
The `.env` contains `INSTANCE_NAME`, `SSH_PORT`, and `AUTHORIZED_KEY`.

### Boot sequence
`docker compose up` → `entrypoint.sh` (root) → `initdb` on first run if `/home/dev/.pgdata` is empty → `supervisord` → spawns **sshd**, **postgres**, **redis** as the `dev` user.

### Persistent state
Everything lives in the `<nome>_dev-home` Docker volume mounted at `/home/dev`:
- `/home/dev/projects/` — cloned repos
- `/home/dev/.pgdata/` — Postgres cluster (survives container rebuilds)
- `/home/dev/.redis/` — Redis data
- `/home/dev/.ssh/`, dotfiles, nvm, etc.

### SSH auth flow
`bootstrap.sh` generates `~/.ssh/<nome>` on the Mac, injects the public key as Docker build arg `AUTHORIZED_KEY` (written to `workbenches/<nome>/.env`, never committed), and adds a `Host <nome>` block with `ForwardAgent yes` to `~/.ssh/config`. GitHub auth inside the container uses the Mac's ssh-agent via agent forwarding — no keys stored in the container.

### Files that matter when changing the image
| File | Purpose |
|---|---|
| `Dockerfile` | Installs packages, Node/nvm, oh-my-zsh; bakes in the SSH authorized key |
| `entrypoint.sh` | Runs as root on container start; initializes Postgres cluster then execs supervisord |
| `config/supervisord.conf` | Declares the three long-running processes (sshd, postgres, redis) |
| `docker-compose.yml` | Single service; port and container name driven by `workbenches/<nome>/.env` |
| `bootstrap.sh` | Runs on the Mac; asks for workbench name, creates `workbenches/<nome>/`, builds and starts |
| `scripts/reset.sh` | Tears down a named workbench; `--keep-volume` preserves Postgres data |

### Postgres details
- Superuser: `dev` (no password — trust auth, local only)
- Data dir: `/home/dev/.pgdata` (on the persistent volume, not baked into the image)
- Project `.env` uses `DB_HOST=localhost`, `DB_PORT=5432`, `DB_USERNAME=dev`, `DB_PASSWORD=` — no `host.docker.internal`, no port mapping needed
