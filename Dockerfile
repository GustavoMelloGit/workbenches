FROM debian:bookworm-slim

# --- Base system ------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    git openssh-server sudo supervisor \
    build-essential pkg-config \
    zsh fzf ripgrep fd-find jq \
    locales tzdata \
    procps less vim nano \
    redis-server \
  && rm -rf /var/lib/apt/lists/*

# Locale
RUN sed -i 's/# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# --- GitHub CLI -------------------------------------------------------------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# --- PostgreSQL 16 (from official PGDG repo) --------------------------------
RUN install -d /usr/share/postgresql-common/pgdg \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
 && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      postgresql-16 postgresql-client-16 \
 && rm -rf /var/lib/apt/lists/*

# --- User -------------------------------------------------------------------
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid ${USER_GID} ${USERNAME} \
 && useradd  --uid ${USER_UID} --gid ${USER_GID} -m -s /usr/bin/zsh ${USERNAME} \
 && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
 && chmod 0440 /etc/sudoers.d/${USERNAME}

# --- SSH server -------------------------------------------------------------
RUN mkdir -p /var/run/sshd \
 && sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/'                /etc/ssh/sshd_config \
 && sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/'    /etc/ssh/sshd_config

ARG AUTHORIZED_KEY
RUN mkdir -p /home/${USERNAME}/.ssh \
 && echo "${AUTHORIZED_KEY}" > /home/${USERNAME}/.ssh/authorized_keys \
 && chmod 700 /home/${USERNAME}/.ssh \
 && chmod 600 /home/${USERNAME}/.ssh/authorized_keys \
 && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh

# --- Node toolchain (as the dev user) ---------------------------------------
USER ${USERNAME}
ENV NVM_DIR=/home/${USERNAME}/.nvm
RUN mkdir -p ${NVM_DIR} \
 && curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
 && . ${NVM_DIR}/nvm.sh \
 && nvm install --lts \
 && nvm alias default 'lts/*' \
 && npm install -g pnpm yarn

# Oh My Zsh — installer overwrites ~/.zshrc, so plugins and zshrc come after.
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# zsh plugins (must be cloned into oh-my-zsh custom plugins dir)
RUN git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
      ${ZSH_CUSTOM:-/home/${USERNAME}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
 && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
      ${ZSH_CUSTOM:-/home/${USERNAME}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

USER root

# Store zshrc template outside the volume so entrypoint can apply it at runtime.
# /home/dev is a mounted volume — files copied there in the image are hidden by it.
COPY config/zshrc /etc/workbench/zshrc

# --- Postgres data dir owned by dev (lives inside the dev-home volume) -----
# We DO NOT initdb here — the entrypoint does it on first run so the cluster
# lands in the persistent volume, not in the image.
RUN mkdir -p /home/${USERNAME}/.pgdata \
 && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.pgdata

# --- Supervisor config + entrypoint -----------------------------------------
COPY config/supervisord.conf /etc/supervisor/conf.d/devenv.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
CMD ["/usr/local/bin/entrypoint.sh"]
