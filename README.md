# Workbenches — ambientes de desenvolvimento isolados e portáteis

Cada workbench é um container Linux completo com Node, Postgres 16, Redis,
git, gh e zsh. Você se conecta via Zed por SSH e trabalha como num
computador dedicado — nada toca o seu Mac.

Um único repositório cria quantas workbenches quiser, cada uma com seu
próprio container, banco e volume isolados.

---

## Arquitetura

```
┌─────────────────────────────────────────┐
│ Seu Mac                                 │
│                                         │
│  Zed ──SSH──┐                           │
│             ▼                           │
│  ┌───────────────────────────────────┐  │
│  │ <nome> (workbench)                │  │
│  │   • código dos projetos           │  │
│  │   • Node, git, gh                 │  │
│  │   • Postgres @ localhost:5432     │  │
│  │   • Redis    @ localhost:6379     │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

Tudo dentro de um container só. Sem socket do Docker exposto, sem rede
compartilhada, sem composes paralelos. Isolamento real.

---

## Setup num Mac novo

Pré-requisitos: Docker Desktop instalado e rodando.

```bash
git clone git@github.com:GustavoMelloGit/workbenches.git ~/workbenches
cd ~/workbenches
chmod +x bootstrap.sh
./bootstrap.sh
# → Nome da workbench: work
```

O `bootstrap.sh`:

1. Pergunta o nome da workbench.
2. Gera chave SSH dedicada (`~/.ssh/<nome>`).
3. Cria `workbenches/<nome>/.env` com a chave pública e a porta alocada.
4. Adiciona bloco `Host <nome>` ao `~/.ssh/config`.
5. Builda a imagem (~5–7 min na 1ª vez).
6. Sobe o container, aguarda SSH e Postgres ficarem prontos.

No fim, conecta o Zed: **File → Open Remote Project → Add Server → `<nome>`**.

---

## Criando mais workbenches

```bash
./bootstrap.sh
# → Nome da workbench: personal
```

Cada workbench recebe porta SSH única (2222, 2223, ...) detectada
automaticamente. Todas rodam em paralelo sem conflito.

---

## Trabalhando num projeto

```bash
ssh <nome>
mkdir -p ~/projects && cd ~/projects
git clone git@github.com:Taya/credit-card.git
cd credit-card
npm install

# cria o banco do projeto (uma vez)
createdb taya_credit_card

# .env do projeto:
cat > .env <<EOF
NODE_ENV=local
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=dev
DB_PASSWORD=
DB_NAME=taya_credit_card
DB_SSL=false
EOF

npm run dev
```

Pronto. Sem `host.docker.internal`, sem mapeamento de porta esquisito,
sem mexer no docker-compose do projeto.

---

## O que tem em cada workbench

| Ferramenta | Versão | Como acessar |
|---|---|---|
| Node | LTS via nvm (troca com `nvm use X`) | `node`, `npm`, `pnpm`, `yarn` |
| Postgres | 16 | `psql`, `createdb`, `dropdb` |
| Redis | 7 (debian) | `redis-cli` |
| git, gh | latest | — |
| Shell | zsh + oh-my-zsh | — |

### Postgres — atalhos úteis

O usuário superuser é `dev`, sem senha (dev local em ambiente isolado).

```bash
createdb meu_projeto                       # criar banco
dropdb   meu_projeto                       # apagar banco
psql     meu_projeto                       # abrir cliente
psql -l                                    # listar todos os bancos

# dump/restore pra mover entre máquinas
pg_dump meu_projeto > meu_projeto.sql
psql meu_projeto < meu_projeto.sql
```

### Redis

```bash
redis-cli                                  # cliente interativo
redis-cli ping                             # pong
```

### Trocar versão do Node por projeto

```bash
nvm install 20      # instala
nvm use 20          # usa na sessão atual

# se o projeto tem .nvmrc, é só:
nvm use
```

---

## Conectando o DBeaver ao Postgres

O Postgres não está exposto no Mac — ele escuta só dentro do container.
O DBeaver chega lá via túnel SSH, sem precisar abrir nenhuma porta extra.

1. **New Connection → PostgreSQL**

2. Aba **Main**:
   | Campo | Valor |
   |---|---|
   | Host | `localhost` |
   | Port | `5432` |
   | Database | nome do banco (ex: `taya_credit_card`) |
   | Username | `dev` |
   | Password | *(vazio)* |

3. Aba **SSH**:
   | Campo | Valor |
   |---|---|
   | Use SSH Tunnel | ✅ |
   | Host/IP | `127.0.0.1` |
   | Port | porta da workbench (ver `workbenches/<nome>/.env`) |
   | User Name | `dev` |
   | Authentication | Public Key |
   | Private Key | `~/.ssh/<nome>` (caminho absoluto, sem `~`) |

4. **Test Connection** → deve conectar.

---

## Credenciais e git

O bootstrap configura `ForwardAgent yes` no `~/.ssh/config`. Isso
encaminha o `ssh-agent` do Mac pro container — o git da workbench usa as
chaves do Mac (via 1Password, ssh-agent) **sem que elas nunca toquem o
disco do container**.

Pré-requisito: suas chaves no Mac estão carregadas no agent (`ssh-add -l`
deve listar algo; com 1Password é automático se você ativar o SSH agent
nas preferências dele).

Configurar identidade do git (uma vez por workbench):
```bash
ssh <nome>
git config --global user.name  "Seu Nome"
git config --global user.email "voce@empresa.com"
gh auth login   # opcional, login OAuth no GitHub
```

---

## Reset de uma workbench

```bash
# Remove tudo da workbench (container, volume, chave SSH)
./scripts/reset.sh <nome>

# Faz backup do volume antes de apagar
./scripts/reset.sh <nome> --backup

# Mantém o volume (projetos e bancos) — útil pra testar o Dockerfile
./scripts/reset.sh <nome> --keep-volume

# Sem confirmação interativa
./scripts/reset.sh <nome> --yes
```

> Por padrão pede que você digite `reset` para confirmar.

---

## Operação do dia a dia

Substitua `<nome>` pelo nome da workbench.

| Ação | Comando (no Mac, na pasta do projeto) |
|---|---|
| Nova workbench / subir existente | `./bootstrap.sh` |
| Subir | `docker compose --project-name <nome> --env-file workbenches/<nome>/.env up -d` |
| Parar | `docker compose --project-name <nome> --env-file workbenches/<nome>/.env stop` |
| Shell | `ssh <nome>` |
| Logs | `docker compose --project-name <nome> --env-file workbenches/<nome>/.env logs -f` |
| Status dos serviços internos | `ssh <nome> 'sudo supervisorctl status'` |
| Reiniciar Postgres | `ssh <nome> 'sudo supervisorctl restart postgres'` |
| Reiniciar Redis | `ssh <nome> 'sudo supervisorctl restart redis'` |
| Rebuildar imagem | `docker compose --project-name <nome> --env-file workbenches/<nome>/.env build --no-cache` |
| Reset | `./scripts/reset.sh <nome>` |
| Reset c/ backup | `./scripts/reset.sh <nome> --backup` |

---

## Backup e portabilidade

Cada workbench tem seu volume `<nome>_dev-home` (projetos, dotfiles,
configs, **dados do Postgres e Redis**). Pra fazer backup:

```bash
docker run --rm \
  -v <nome>_dev-home:/data \
  -v "$PWD":/backup \
  alpine tar czf /backup/<nome>-backup-$(date +%Y%m%d).tar.gz -C /data .
```

Pra restaurar numa workbench recém-criada:

```bash
# Para o container
docker compose --project-name <nome> --env-file workbenches/<nome>/.env stop

# Restaura
docker run --rm \
  -v <nome>_dev-home:/data \
  -v "$PWD":/backup \
  alpine sh -c "cd /data && tar xzf /backup/<nome>-backup-XXXXXXXX.tar.gz"

# Sobe de novo
docker compose --project-name <nome> --env-file workbenches/<nome>/.env start
```

Pra projetos individuais, costuma ser mais limpo:
- `git push` antes de migrar (código vai pro repositório);
- `pg_dump` dos bancos que importam (vai pra um SQL versionável);

E recriar do zero no Mac novo, em vez de transportar o volume inteiro.

---

## Segurança — o que cada coisa protege

| O que | Como |
|---|---|
| Credenciais do trabalho não vazam pro Mac | Tudo vive no volume isolado |
| Chaves SSH privadas nunca tocam o container | `ForwardAgent yes` no SSH |
| Banco/cache de uma workbench não vão pra outra | Volume é por workbench |
| SSH do container não vaza na rede local | Porta bindada em `127.0.0.1` |
| Sem login por senha no SSH | Só chave pública, sem root |
| Sem acesso ao Docker do Mac | Socket NÃO está montado |
| Postgres/Redis não expostos | Bindados em `127.0.0.1` dentro do container |

---

## Limitações conhecidas

- **Versões de banco fixas.** O container tem Postgres 16. Se um projeto
  exige Postgres 14 especificamente, você teria que adaptar o Dockerfile.
- **Bancos compartilham a mesma instância dentro da workbench.** Cada
  projeto cria seu próprio *database*, o que é normal. Eles não enxergam
  dados uns dos outros, mas compartilham configuração (memória, conexões).
- **Não é fronteira de segurança equivalente a uma VM.** Containers no
  Docker Desktop compartilham o kernel da VM do Docker Desktop. Pra rodar
  código hostil de terceiros, use uma VM dedicada.
