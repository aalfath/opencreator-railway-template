# OpenCreator (KrillinAI Server) for Railway
# Upstream: https://github.com/krillinai/OpenCreator (Apache-2.0), release v3.3.4
# Upstream publishes no Docker image, so we install the official release asset
# (checked against its published SHA-256) on a pinned Debian base.

FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy
FROM denoland/deno:bin-2.9.8@sha256:b507583d3c68ba69f3ed2ce5969ae5b8b70f43421c781279c7aea06435263543 AS deno

FROM debian:trixie-20261104-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

ARG KRILLIN_VERSION=3.3.4
ARG KRILLIN_SHA256=d95f1711b662aabe553ca40dc1d443fc13b2b488071f9ae471dd14f87d18a026
ARG YTDLP_VERSION=2026.10.26
ARG YTDLP_SHA256=767ba9dce7052aa196f8b12652f433d76de128ba168966fa84b6394d5e6c6795

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl ffmpeg tini fonts-dejavu-core fonts-noto-cjk \
 && rm -r /var/lib/apt/lists/*

RUN set -eux; \
    cd /tmp; \
    curl -fsSL -o krillin.tgz "https://github.com/krillinai/OpenCreator/releases/download/v${KRILLIN_VERSION}/KrillinAI-Server-${KRILLIN_VERSION}-linux-x64.tar.gz"; \
    echo "${KRILLIN_SHA256}  krillin.tgz" | sha256sum -c -; \
    mkdir -p /opt/krillinai; \
    tar -xzf krillin.tgz -C /opt/krillinai --strip-components=1; \
    rm krillin.tgz; \
    chmod 0755 /opt/krillinai/krillinai-server; \
    echo "v${KRILLIN_VERSION}" > /opt/krillinai/VERSION; \
    curl -fsSL -o /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp_linux"; \
    echo "${YTDLP_SHA256}  /usr/local/bin/yt-dlp" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/yt-dlp

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY --from=deno /deno /usr/local/bin/deno
COPY rootfs/ /

RUN chmod 0755 /usr/local/bin/start.sh /usr/local/bin/ffmpeg \
 && /usr/local/bin/caddy version \
 && /usr/local/bin/deno --version \
 && /usr/local/bin/ffmpeg -version | head -1

ENV PORT=8080 \
    DATA_DIR=/data \
    GOMAXPROCS=2 \
    FFMPEG_THREADS=2 \
    XDG_CONFIG_HOME=/data/.config \
    XDG_DATA_HOME=/data/.local/share

WORKDIR /data
EXPOSE 8080

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/usr/local/bin/start.sh"]
