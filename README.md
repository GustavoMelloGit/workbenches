# Devenv — ambiente de desenvolvimento isolado e portátil

Um único container que tem **tudo** que você precisa pra desenvolver:
Node, Postgres 16, Redis, git, gh, zsh. Você se conecta via Zed por SSH,
trabalha como num computador Linux dedicado — e nada toca o seu Mac.

---

## Arquitetura

```
┌─────────────────────────────────────────┐
│ Seu Mac                                 │
│                                         │
│  Zed ──SSH──┐                           │
│             ▼                           │
│  ┌───────────────────────────────────┐  │
│  │ devenv (container)                │  │
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
git clone git@github.com:voce/devenv.git ~/devenv
cd ~/devenv
chmod +x bootstrap.sh
./bootstrap.sh
```

O `bootstrap.sh`:

1. Gera chave SSH dedicada (`~/.ssh/devenv`).
2. Cria `.env` com a chave pública.
3. Adiciona bloco `Host devenv` ao `~/.ssh/config`.
4. Builda a imagem (~5–7 min na 1ª vez).
5. Sobe o container, aguarda SSH e Postgres ficarem prontos.

No fim, conecta o Zed: **File → Open Remote Project → Add Server → `devenv`**.

---

## Trabalhando num projeto

```bash
ssh devenv
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

## O que tem no container

| Ferramenta | Versão | Como acessar |
|---|---|---|
| Node | LTS via nvm (troca com `nvm use X`) | `node`, `npm`, `pnpm`, `yarn` |
| Postgres | 16 | `psql`, `createdb`, `dropdb` |
| Redis | 7 (debian) | `redis-cli` |
| git, gh | latest | — |
| Shell | zsh + oh-my-zsh | — |

### Postgres — atalhos úteis

O usuário superuser é `dev` (mesmo nome do usuário do container), sem senha,
porque é dev local em ambiente isolado.

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
   | Port | `2222` |
   | User Name | `dev` |
   | Authentication | Public Key |
   | Private Key | `~/.ssh/devenv` |

4. **Test Connection** → deve conectar.

A mesma configuração funciona pra qualquer banco criado no devenv —
só muda o campo **Database** na aba Main.

---

## Credenciais e git

O bootstrap configura `ForwardAgent yes` no seu `~/.ssh/config`. Isso
encaminha o `ssh-agent` do Mac pro container — o git do devenv usa as
chaves do Mac (via 1Password, ssh-agent) **sem que elas nunca toquem o
disco do container**.

Pré-requisito: suas chaves no Mac estão carregadas no agent (`ssh-add -l`
deve listar algo; com 1Password é automático se você ativar o SSH agent
nas preferências dele).

Configurar identidade do git (uma vez):
```bash
ssh devenv
git config --global user.name  "Seu Nome"
git config --global user.email "voce@empresa.com"
gh auth login   # opcional, login OAuth no GitHub
```

---

## Reset (testar do zero)

O `reset.sh` apaga tudo — container, imagem, volume, chave SSH, `.env` — pra
simular um Mac novo. Útil pra testar se o `bootstrap.sh` ainda funciona do zero.

```bash
# Apaga tudo, mas faz backup do volume antes
./scripts/reset.sh --backup

# Apaga tudo MENOS o volume (mantém projetos e bancos)
# Útil pra testar mudanças no Dockerfile sem perder trabalho
./scripts/reset.sh --keep-volume

# Pula a confirmação (pra uso em outros scripts)
./scripts/reset.sh --yes

# Combina: backup + sem confirmação
./scripts/reset.sh --backup --yes

# Ajuda
./scripts/reset.sh --help
```

> Por padrão o script pede que você digite `reset` pra confirmar antes de
> apagar qualquer coisa.

---

## Operação do dia a dia

Substitua `<nome>` pelo nome da workbench (o valor de `INSTANCE_NAME` no `.env`).

| Ação | Comando (no Mac, na pasta do devenv) |
|---|---|
| Setup inicial / nova workbench | `./bootstrap.sh` |
| Subir | `docker compose --project-name <nome> up -d` |
| Parar | `docker compose --project-name <nome> stop` |
| Shell | `ssh <nome>` |
| Logs | `docker compose --project-name <nome> logs -f` |
| Status dos serviços internos | `ssh <nome> 'sudo supervisorctl status'` |
| Reiniciar Postgres | `ssh <nome> 'sudo supervisorctl restart postgres'` |
| Reiniciar Redis | `ssh <nome> 'sudo supervisorctl restart redis'` |
| Rebuildar imagem | `docker compose --project-name <nome> build --no-cache` |
| Reset total | `./scripts/reset.sh` |
| Reset total c/ backup | `./scripts/reset.sh --backup` |

---

## Backup e portabilidade

Tudo importante mora no volume `devenv_dev-home` (projetos, dotfiles,
configs, **dados do Postgres e Redis**). Pra fazer backup:

```bash
docker run --rm \
  -v devenv_dev-home:/data \
  -v "$PWD":/backup \
  alpine tar czf /backup/devenv-home-$(date +%Y%m%d).tar.gz -C /data .
```

Pra restaurar num Mac novo, depois do `bootstrap.sh`:

```bash
# Para o container pra não corromper o cluster Postgres durante restore
docker compose stop

# Restaura
docker run --rm \
  -v devenv_dev-home:/data \
  -v "$PWD":/backup \
  alpine sh -c "cd /data && tar xzf /backup/devenv-home-XXXXXXXX.tar.gz"

# Sobe de novo
docker compose start
```

Pra projetos individuais, costuma ser mais limpo só:
- `git push` antes de migrar (código vai pro repositório);
- `pg_dump` dos bancos que importam (vai pra um SQL versionável);

E recriar do zero no Mac novo, em vez de transportar o volume inteiro.

---

## Segurança — o que cada coisa protege

| O que | Como |
|---|---|
| Credenciais do trabalho não vazam pro Mac | Tudo vive no volume isolado |
| Chaves SSH privadas nunca tocam o container | `ForwardAgent yes` no SSH |
| Banco/cache de um Mac não vão pra outro | Volume é local, você decide o que migrar |
| SSH do container não vaza na rede local | Porta 2222 bindada em `127.0.0.1` |
| Sem login por senha no SSH | Só chave pública, sem root |
| Sem acesso ao Docker do Mac | Socket NÃO está montado |
| Postgres/Redis não expostos | Bindados em `127.0.0.1` dentro do container |

---

## Limitações conhecidas

- **Versões de banco fixas.** O container tem Postgres 16. Se um projeto
  exige Postgres 14 especificamente (por causa de extensão, sintaxe, etc.),
  você teria que adaptar. Pra maioria absoluta dos projetos, 16 funciona.
- **Bancos compartilham a mesma instância.** Cada projeto cria seu próprio
  *database* (`taya_credit_card`, `taya_billing`, etc.), o que é normal.
  Eles não enxergam dados uns dos outros, mas compartilham configuração
  (memória, conexões máximas, etc.).
- **Não é fronteira de segurança equivalente a uma VM.** Containers no
  Docker Desktop compartilham o kernel da VM do Docker Desktop. É
  isolamento muito forte pra deps e credenciais, mas pra rodar código
  hostil de terceiros, use uma VM dedicada.
