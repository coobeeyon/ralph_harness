# Stage 1: Build litebrite (lb) — static musl binary, no glibc dependency
FROM rust:slim AS lb-builder
RUN apt-get update && apt-get install -y musl-tools && rm -rf /var/lib/apt/lists/*
RUN rustup target add x86_64-unknown-linux-musl
RUN cargo install --git https://github.com/coobeeyon/litebrite.git --target x86_64-unknown-linux-musl

# Stage 2: Runtime image — no Rust toolchain
FROM node:22

# Layer 1: System deps (changes ~never)
RUN apt-get update && apt-get install -y --no-install-recommends \
    unzip openssh-client sudo \
  && rm -rf /var/lib/apt/lists/*

# Layer 2: GitHub SSH known host (changes ~never)
RUN mkdir -p /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

# Layer 3: Copy lb binary from builder
COPY --from=lb-builder /usr/local/cargo/bin/lb /usr/local/bin/lb

# Layer 4: Claude Code (changes occasionally)
RUN npm install -g @anthropic-ai/claude-code

# Layer 5: Non-root user matching host UID (for SSH agent socket access)
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
RUN git config --global user.name "agent-runner" && \
    git config --global user.email "agent-runner@local"

ENTRYPOINT ["bash"]
