FROM node:22

# Layer 1: System deps (changes ~never)
RUN apt-get update && apt-get install -y --no-install-recommends \
    unzip openssh-client sudo \
  && rm -rf /var/lib/apt/lists/*

# Layer 2: GitHub SSH known host (changes ~never)
RUN mkdir -p /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

# Layer 3: Rust toolchain (kept for building project tools)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Layer 4: Install litebrite (lb) from source
RUN cargo install --git https://github.com/coobeeyon/litebrite.git && \
    cp /root/.cargo/bin/lb /usr/local/bin/lb

# Layer 5: Claude Code (changes occasionally)
RUN npm install -g @anthropic-ai/claude-code

# Layer 6: Non-root user matching host UID (for SSH agent socket access)
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN userdel -r node 2>/dev/null || true && \
    groupadd -g ${HOST_GID} runner 2>/dev/null || true && \
    useradd -m -s /bin/bash -u ${HOST_UID} -g ${HOST_GID} runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner && \
    cp -r /root/.ssh /home/runner/.ssh && \
    chown -R runner:runner /home/runner/.ssh
USER runner
ENV HOME=/home/runner
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/runner/.cargo/bin:${PATH}"
RUN git config --global user.name "agent-runner" && \
    git config --global user.email "agent-runner@local"

# Entrypoint scripts are mounted at runtime — no COPY needed
ENTRYPOINT ["bash"]
