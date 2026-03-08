FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*

ARG ZIG_VERSION
ARG ZIG_URL

RUN curl -fsSL "${ZIG_URL}" | tar -xJ -C /opt \
  && ln -s /opt/zig-* /opt/zig

ENV PATH="/opt/zig:${PATH}"

RUN zig version
