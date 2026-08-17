# ---------- Build ----------
FROM alpine:latest AS builder

# Fix commit or tag:
# example: --build-arg TELEGRAM_BOT_API_REF=v9.4
ARG TELEGRAM_BOT_API_REF=master

# Install packages
RUN apk update && \
    apk upgrade && \
    apk add --no-cache alpine-sdk linux-headers git zlib-dev openssl-dev gperf cmake

# Clone sources
WORKDIR /src
RUN git init && \
    git remote add origin https://github.com/tdlib/telegram-bot-api.git && \
    git fetch --depth 1 origin ${TELEGRAM_BOT_API_REF} && \
    git checkout FETCH_HEAD && \
    git submodule update --init --recursive --depth 1

# Add patches to support proxy options
COPY ./add_proxy/*.patch .
RUN patch -p1 ./telegram-bot-api/Client.cpp < Client.cpp.patch
RUN patch -p1 ./telegram-bot-api/ClientParameters.h < ClientParameters.h.patch
RUN patch -p1 ./telegram-bot-api/telegram-bot-api.cpp < telegram-bot-api.cpp.patch

# Build
RUN mkdir -p build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    cmake --build . --target telegram-bot-api -j"$(nproc)"

# Strip binary
RUN strip /src/build/telegram-bot-api || true

# ---------- Runtime ----------
FROM alpine:latest

ARG BUILD_VERSION="unknown"

# Install packages
RUN apk update && \
    apk upgrade && \
    apk add --no-cache libssl3 zlib ca-certificates curl libstdc++

# Create group, user and workdir
RUN addgroup -S telegram-bot-api && \
    adduser -S -G telegram-bot-api -h /var/lib/telegram-bot-api -s /sbin/nologin telegram-bot-api && \
    mkdir -p /var/lib/telegram-bot-api && \
    chown -R telegram-bot-api:telegram-bot-api /var/lib/telegram-bot-api

# Copy binary from builder
COPY --from=builder /src/build/telegram-bot-api /usr/local/bin/telegram-bot-api

# Expose ports
EXPOSE 8081/tcp 8082/tcp

USER telegram-bot-api
WORKDIR /var/lib/telegram-bot-api

# Command line options (api-id, api-hash, ports, dirs) configured via docker-compose:
#   command: ["--api-id=...", "--api-hash=...", "--http-port=8081", "--dir=/var/lib/telegram-bot-api"]
ENTRYPOINT ["/usr/local/bin/telegram-bot-api"]

LABEL \
  maintainer="andreyzin (https://github.com/andreyzin), fork of avbor/docker-telegram-bot-api" \
  org.opencontainers.image.title="Telegram Bot API" \
  org.opencontainers.image.description="Telegram Bot API server with proxy server support" \
  org.opencontainers.image.authors="andreyzin (https://github.com/andreyzin)" \
  org.opencontainers.image.licenses="MIT" \
  org.opencontainers.image.url="https://github.com/andreyzin/proxied-telegram-bot-api" \
  org.opencontainers.image.source="https://github.com/andreyzin/proxied-telegram-bot-api" \
  org.opencontainers.image.documentation="https://github.com/andreyzin/proxied-telegram-bot-api/blob/main/README.md" \
  org.opencontainers.image.version=${BUILD_VERSION}
