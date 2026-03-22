# =============================================================================
# Call of Duty 1 (v1.1) Dedicated Server
# https://github.com/mmBesar/cod-container
# =============================================================================
# Stage 1 — downloader
#   Downloads and extracts all server files. Nothing from this stage
#   reaches the final image except the files we explicitly COPY.
# =============================================================================
FROM debian:bookworm-slim AS downloader

# Install download/extract tools only — gone after this stage
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        bzip2 \
        unzip \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# -----------------------------------------------------------------------------
# Download all server files in parallel then extract/verify.
#
# All five curl calls run in the background (&) simultaneously.
# `wait` blocks until every background job finishes.
# If any curl fails (-fsSL exits non-zero) the overall RUN step fails.
#
# Files fetched:
#   cod-lnxded-1.1d.tar.bz2     — server binary + game.mp.i386.so
#   basefiles.zip               — pak0–pak6 + localized english pk3s
#   CoDaM_V1.31.zip             — CoDaM core mod framework
#   CoDaM_HamGoodies_V1.35.zip  — CoDaM HamGoodies module
#   codextended.so              — CoDExtended preload library (latest release)
# -----------------------------------------------------------------------------
RUN set -e \
    # --- Parallel downloads --------------------------------------------------
    && curl -fsSL "https://de.dvotx.org/dump/cod1/cod-lnxded-1.1d.tar.bz2" \
         -o cod-lnxded-1.1d.tar.bz2 & \
    curl -fsSL "https://de.dvotx.org/dump/cod1/downloads.php?get=basefilesfull" \
         -o basefiles.zip & \
    curl -fsSL "https://de.dvotx.org/dump/cod1/CoDaM/CoDaM_V1.31.zip" \
         -o CoDaM_V1.31.zip & \
    curl -fsSL "https://de.dvotx.org/dump/cod1/CoDaM/CoDaM_HamGoodies_V1.35.zip" \
         -o CoDaM_HamGoodies_V1.35.zip & \
    curl -fsSL "https://github.com/riicchhaarrd/codextended/releases/latest/download/codextended.so" \
         -o codextended.so & \
    # Wait for all background downloads to finish
    wait \
    \
    # --- Extract: server binary + game library -------------------------------
    && tar -xjf cod-lnxded-1.1d.tar.bz2 \
    && rm cod-lnxded-1.1d.tar.bz2 \
    # Flatten: move files to /build root if the tarball nested them
    && find . -name "cod_lnxded"      ! -path "./cod_lnxded"      -exec mv {} . \; 2>/dev/null || true \
    && find . -name "game.mp.i386.so" ! -path "./game.mp.i386.so" -exec mv {} . \; 2>/dev/null || true \
    \
    # --- Extract: base pk3 files ---------------------------------------------
    && unzip -q basefiles.zip -d basefiles \
    && rm basefiles.zip \
    # Flatten all pk3 files to basefiles/ root in case they are in a subdir
    && find basefiles/ -name "*.pk3" ! -path "basefiles/*.pk3" \
         -exec mv {} basefiles/ \; 2>/dev/null || true \
    \
    # --- Extract: CoDaM core -------------------------------------------------
    && unzip -q CoDaM_V1.31.zip -d codam_core \
    && rm CoDaM_V1.31.zip \
    \
    # --- Extract: CoDaM HamGoodies -------------------------------------------
    && unzip -q CoDaM_HamGoodies_V1.35.zip -d codam_ham \
    && rm CoDaM_HamGoodies_V1.35.zip \
    \
    # --- Verify all required files are present before proceeding -------------
    && echo "=== Build artefacts ===" && find . | sort \
    && test -f ./cod_lnxded                           || (echo "ERROR: cod_lnxded not found!"                    && exit 1) \
    && test -f ./game.mp.i386.so                      || (echo "ERROR: game.mp.i386.so not found!"               && exit 1) \
    && test -f ./basefiles/pak0.pk3                   || (echo "ERROR: pak0.pk3 not found!"                      && exit 1) \
    && test -f ./basefiles/localized_english_pak0.pk3 || (echo "ERROR: localized_english_pak0.pk3 not found!"   && exit 1) \
    && test -f ./codextended.so                       || (echo "ERROR: codextended.so not found!"                && exit 1) \
    && echo "=== All downloads verified OK ==="

# =============================================================================
# Stage 2 — final
#   Slim runtime image. Only what the server actually needs at runtime.
# =============================================================================
FROM debian:bookworm-slim AS final

# Labels — OCI standard image metadata
LABEL org.opencontainers.image.title="Call of Duty 1 Dedicated Server" \
      org.opencontainers.image.description="CoD1 v1.1 server with CoDaM and CoDExtended" \
      org.opencontainers.image.source="https://github.com/mmBesar/cod-container" \
      org.opencontainers.image.licenses="GPL-2.0"

# -----------------------------------------------------------------------------
# Runtime dependencies
#
#   libc6-i386        — 32-bit glibc (cod_lnxded is an i386 ELF)
#   lib32z1           — 32-bit zlib
#   libstdc++5:i386   — GCC 3.x C++ runtime that CoD1 requires
#                       (not present in trixie — bookworm required)
#   gosu              — clean UID/GID privilege drop in entrypoint
# -----------------------------------------------------------------------------
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libc6-i386 \
        lib32z1 \
        libstdc++5:i386 \
        gosu \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Server directory layout
#
#   /server/              — server root (fs_basepath + fs_homepath)
#   /server/main/         — base pk3 files + CoDaM files
#   /server/maps/         — MOUNT POINT: user-supplied map pk3 files
#   /server/logs/         — MOUNT POINT: games_mp.log and friends
#   /server/config/       — MOUNT POINT: optional hand-crafted server.cfg
# -----------------------------------------------------------------------------
RUN mkdir -p \
        /server/main \
        /server/maps \
        /server/logs \
        /server/config

# -----------------------------------------------------------------------------
# Copy server binary and CoDExtended library
# -----------------------------------------------------------------------------
COPY --from=downloader /build/cod_lnxded      /server/cod_lnxded
COPY --from=downloader /build/codextended.so  /server/codextended.so

# -----------------------------------------------------------------------------
# Copy game library and base pk3 files into main/
# -----------------------------------------------------------------------------
COPY --from=downloader /build/game.mp.i386.so         /server/main/
COPY --from=downloader /build/basefiles/pak0.pk3       /server/main/
COPY --from=downloader /build/basefiles/pak1.pk3       /server/main/
COPY --from=downloader /build/basefiles/pak2.pk3       /server/main/
COPY --from=downloader /build/basefiles/pak3.pk3       /server/main/
COPY --from=downloader /build/basefiles/pak4.pk3       /server/main/
COPY --from=downloader /build/basefiles/pak5.pk3       /server/main/
COPY --from=downloader /build/basefiles/pak6.pk3       /server/main/
COPY --from=downloader /build/basefiles/localized_english_pak0.pk3  /server/main/
COPY --from=downloader /build/basefiles/localized_english_pak1.pk3  /server/main/

# -----------------------------------------------------------------------------
# Copy CoDaM core files into main/
#   - codam/            mod scripts
#   - CoDaM.cfg         base config (we template-override at runtime)
#   - ___CoDaM__CoD1.1__.pk3
# -----------------------------------------------------------------------------
COPY --from=downloader /build/codam_core/codam/                        /server/main/codam/
COPY --from=downloader /build/codam_core/CoDaM.cfg                     /server/main/CoDaM.cfg
COPY --from=downloader /build/codam_core/___CoDaM__CoD1.1__.pk3        /server/main/

# -----------------------------------------------------------------------------
# Copy CoDaM HamGoodies into main/
#   - codam/            (merges with above codam/ folder)
#   - CoDaM_HamGoodies.cfg
#   - ___CoDaM_HamGoodies__CoD1.1__.pk3
# -----------------------------------------------------------------------------
COPY --from=downloader /build/codam_ham/codam/                              /server/main/codam/
COPY --from=downloader /build/codam_ham/CoDaM_HamGoodies.cfg                /server/main/CoDaM_HamGoodies.cfg
COPY --from=downloader /build/codam_ham/___CoDaM_HamGoodies__CoD1.1__.pk3   /server/main/

# -----------------------------------------------------------------------------
# Copy entrypoint script and fix permissions in one layer
# -----------------------------------------------------------------------------
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /server/cod_lnxded

# -----------------------------------------------------------------------------
# Declare mount points
# Maps, logs, and optional config override are expected here at runtime.
# -----------------------------------------------------------------------------
VOLUME ["/server/maps", "/server/logs", "/server/config"]

# CoD1 default UDP port
EXPOSE 28960/udp

# Run as root initially so gosu can drop to the correct UID:GID at runtime
# The actual privilege drop happens inside docker-entrypoint.sh
WORKDIR /server

ENTRYPOINT ["docker-entrypoint.sh"]
