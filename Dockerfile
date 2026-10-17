FROM mcr.microsoft.com/devcontainers/base:ubuntu

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

#
# Remove sudo so the agent can't escalate (must run as root, so it comes before USER)
RUN rm -f /etc/sudoers.d/* \
    && SUDO_FORCE_REMOVE=yes apt-get purge -y sudo \
    && ! command -v sudo

# Project toolchain (as root): Lua 5.5, headers, compiler, sqlite3
RUN apt-get update && apt-get install -y --no-install-recommends \
      lua5.5 liblua5.5-dev build-essential unzip sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# luarocks 3.13.0 (same as the Mac), built against Lua 5.5
RUN curl -fsSL https://luarocks.org/releases/luarocks-3.13.0.tar.gz | tar xz -C /tmp \
    && cd /tmp/luarocks-3.13.0 \
    && ./configure --with-lua-include=/usr/include/lua5.5 \
    && make \
    && make install \
    && rm -rf /tmp/luarocks-3.13.0

# busted, pinned to the Mac's version
RUN luarocks --lua-version 5.5 install busted 2.3.0-1

# Switch from root to the non-root user the base image provides (UID 1000)
USER 1000
WORKDIR /workspace
RUN mkdir -p /home/vscode/.claude

# Per-user tools (no root needed)
RUN curl -fsSL https://claude.ai/install.sh | bash
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v1.3.6"
RUN curl -fsSL https://just.systems/install.sh | bash -s -- --to /home/vscode/.local/bin
ENV PATH="/home/vscode/.bun/bin:/home/vscode/.local/bin:${PATH}"
