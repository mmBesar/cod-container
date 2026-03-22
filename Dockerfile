# =============================================================================
# Call of Duty 1 (v1.1) Dedicated Server
# https://github.com/mmBesar/cod-container
#
# What is baked into this image:
#   - cod_lnxded          official Linux server binary (v1.1)
#   - codextended.so      CoDExtended preload library (cracked, fast DL, fixes)
#   - /server/codam/      CoDaM v1.31 + HamGoodies v1.35 mod files
#
# What is NOT in this image (user must mount):
#   - /server/main/       your CoD1 main/ folder (pak0.pk3-pak6.pk3,
#                         game.mp.i386.so, localized_english_pak*.pk3)
#
# This keeps the image small (~350MB) and legally clean - no copyrighted
# Activision game assets are distributed.
# =============================================================================

# =============================================================================
# Stage 1 - downloader
#   Downloads and extracts server files. Nothing from this stage reaches
#   the final image except the files we explicitly COPY.
# =============================================================================
FROM debian:bookworm-slim AS downloader

# Install download/extract tools only - gone after this stage
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        bzip2 \
        unzip \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# -----------------------------------------------------------------------------
# Download all files in parallel then extract/verify.
#
# All four curl calls run in the background (&) simultaneously.
# `wait` blocks until every background job finishes.
#
# Files fetched:
#   cod-lnxded-1.1d.tar.bz2     - server binary (cod_lnxded) AND
#                                  game.mp.i386.so (Linux game logic library)
#   CoDaM_V1.31.zip             - CoDaM core mod framework
#   CoDaM_HamGoodies_V1.35.zip  - CoDaM HamGoodies module
#   codextended.so              - CoDExtended preload library (latest release)
#
# NOTE: pak*.pk3 files are intentionally NOT downloaded here - they are
#       copyrighted Activision assets and must be supplied by the user from
#       their own legitimate CoD1 installation.
#       game.mp.i386.so is Linux-only and comes from the official Linux server
#       tarball - the user does not need to supply it.
# -----------------------------------------------------------------------------
RUN set -e \
    && curl -fsSL "https://de.dvotx.org/dump/cod1/cod-lnxded-1.1d.tar.bz2" \
         -o cod-lnxded-1.1d.tar.bz2 & \
    curl -fsSL "https://de.dvotx.org/dump/cod1/CoDaM/CoDaM_V1.31.zip" \
         -o CoDaM_V1.31.zip & \
    curl -fsSL "https://de.dvotx.org/dump/cod1/CoDaM/CoDaM_HamGoodies_V1.35.zip" \
         -o CoDaM_HamGoodies_V1.35.zip & \
    curl -fsSL "https://github.com/riicchhaarrd/codextended/releases/latest/download/codextended.so" \
         -o codextended.so & \
    wait \
    \
    && tar -xjf cod-lnxded-1.1d.tar.bz2 \
    && rm cod-lnxded-1.1d.tar.bz2 \
    && find . -name "cod_lnxded"      ! -path "./cod_lnxded"      \
         -exec mv {} . \; 2>/dev/null || true \
    && find . -name "game.mp.i386.so" ! -path "./game.mp.i386.so" \
         -exec mv {} . \; 2>/dev/null || true \
    \
    && unzip -q CoDaM_V1.31.zip -d codam_core \
    && rm CoDaM_V1.31.zip \
    \
    && unzip -q CoDaM_HamGoodies_V1.35.zip -d codam_ham \
    && rm CoDaM_HamGoodies_V1.35.zip \
    \
    && echo "=== Build artefacts ===" && find . | sort \
    && test -f ./cod_lnxded      || (echo "ERROR: cod_lnxded not found!"      && exit 1) \
    && test -f ./game.mp.i386.so || (echo "ERROR: game.mp.i386.so not found!" && exit 1) \
    && test -f ./codextended.so  || (echo "ERROR: codextended.so not found!"  && exit 1) \
    && echo "=== All downloads verified OK ==="

# =============================================================================
# Stage 2 - final
#   Slim runtime image. Only what the server actually needs at runtime.
# =============================================================================
FROM debian:bookworm-slim AS final

LABEL org.opencontainers.image.title="Call of Duty 1 Dedicated Server" \
      org.opencontainers.image.description="CoD1 v1.1 server with CoDaM and CoDExtended" \
      org.opencontainers.image.source="https://github.com/mmBesar/cod-container" \
      org.opencontainers.image.licenses="GPL-2.0"

# -----------------------------------------------------------------------------
# Runtime dependencies
#
#   libc6-i386        - 32-bit glibc (cod_lnxded is an i386 ELF)
#   lib32z1           - 32-bit zlib
#   libstdc++5:i386   - GCC 3.x C++ runtime that CoD1 requires
#                       (not present in trixie - bookworm required)
# -----------------------------------------------------------------------------
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libc6-i386 \
        lib32z1 \
        libstdc++5:i386 \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Server directory layout
#
#   /server/          - server root (fs_basepath + fs_homepath)
#   /server/main/     - MOUNT POINT: user's CoD1 main/ folder (pak*.pk3 only)
#                       game.mp.i386.so is already baked in here
#   /server/codam/    - CoDaM mod files (baked in, never touched by user)
#   /server/logs/     - MOUNT POINT: games_mp.log output
#   /server/config/   - MOUNT POINT: optional hand-crafted server.cfg
# -----------------------------------------------------------------------------
RUN mkdir -p \
        /server/main \
        /server/codam \
        /server/logs \
        /server/config \
    && mkdir -p /server/.callofduty     && chmod -R 777 \
        /server \
        /server/main \
        /server/codam \
        /server/logs \
        /server/config \
        /server/.callofduty

# -----------------------------------------------------------------------------
# Copy server binary, game logic library, and CoDExtended
#
# game.mp.i386.so comes from the official Linux server tarball - it is the
# Linux multiplayer game logic library. The user does not need to supply it.
# It lives in /server/main/ because that is where the engine expects it
# relative to fs_basepath.
# -----------------------------------------------------------------------------
COPY --from=downloader /build/cod_lnxded      /server/cod_lnxded
COPY --from=downloader /build/game.mp.i386.so /server/codam/game.mp.i386.so
COPY --from=downloader /build/codextended.so  /server/codextended.so

# -----------------------------------------------------------------------------
# Copy CoDaM core into /server/codam/
# -----------------------------------------------------------------------------
COPY --from=downloader /build/codam_core/codam/                 /server/codam/codam/
COPY --from=downloader /build/codam_core/CoDaM.cfg              /server/codam/CoDaM.cfg
COPY --from=downloader /build/codam_core/___CoDaM__CoD1.1__.pk3 /server/codam/

# -----------------------------------------------------------------------------
# Copy CoDaM HamGoodies into /server/codam/
# -----------------------------------------------------------------------------
COPY --from=downloader /build/codam_ham/codam/                             /server/codam/codam/
COPY --from=downloader /build/codam_ham/CoDaM_HamGoodies.cfg               /server/codam/CoDaM_HamGoodies.cfg
COPY --from=downloader /build/codam_ham/___CoDaM_HamGoodies__CoD1.1__.pk3  /server/codam/

# -----------------------------------------------------------------------------
# Copy entrypoint and fix permissions in a single layer
# -----------------------------------------------------------------------------
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /server/cod_lnxded

# Declare mount points
VOLUME ["/server/main", "/server/logs", "/server/config"]

EXPOSE 28960/udp

WORKDIR /server

ENTRYPOINT ["docker-entrypoint.sh"]
