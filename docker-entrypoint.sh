#!/bin/sh
# =============================================================================
# Call of Duty 1 (v1.1) Dedicated Server — Entrypoint
# https://github.com/mmBesar/cod-container
#
# Responsibilities:
#   1. Symlink /server/maps/*.pk3 into /server/main/ so the engine finds them
#   2. Generate /server/main/server.cfg from env vars (if no override exists)
#   3. Drop privileges to the UID:GID the container was started with (gosu)
#   4. Launch cod_lnxded with CoDExtended via LD_PRELOAD
# =============================================================================
set -e

# =============================================================================
# Helpers
# =============================================================================
log() { printf '[entrypoint] %s\n' "$*"; }

die() {
    printf '[entrypoint] FATAL: %s\n' "$*" >&2
    exit 1
}

# =============================================================================
# Defaults — all overridable via environment variables
# =============================================================================

# --- Server identity ---------------------------------------------------------
SERVER_HOSTNAME="${SERVER_HOSTNAME:-CoD1 Docker Server}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
MOTD="${MOTD:-}"

# --- Network -----------------------------------------------------------------
SERVER_PORT="${SERVER_PORT:-28960}"
# Auto-detect container IP if SERVER_IP is not set
if [ -z "${SERVER_IP:-}" ]; then
    SERVER_IP="$(hostname -i | awk '{print $1}')"
    log "SERVER_IP not set, auto-detected: ${SERVER_IP}"
fi

# --- Gameplay ----------------------------------------------------------------
GAMETYPE="${GAMETYPE:-tdm}"
MAX_CLIENTS="${MAX_CLIENTS:-16}"
SV_PURE="${SV_PURE:-0}"
FRIENDLY_FIRE="${FRIENDLY_FIRE:-0}"
SCORE_LIMIT="${SCORE_LIMIT:-100}"
TIME_LIMIT="${TIME_LIMIT:-30}"
ROUND_LIMIT="${ROUND_LIMIT:-0}"
ALLOW_VOTE="${ALLOW_VOTE:-0}"

# --- Maps --------------------------------------------------------------------
START_MAP="${START_MAP:-mp_harbor}"
# MAP_ROTATION: space-separated list of maps e.g. "mp_harbor mp_dawnville"
# If empty, server loops START_MAP only.
MAP_ROTATION="${MAP_ROTATION:-}"

# --- CoDExtended -------------------------------------------------------------
X_AUTHORIZE="${X_AUTHORIZE:-0}"          # 0 = cracked (no CD key check)
X_DEADCHAT="${X_DEADCHAT:-0}"
X_NOPBOTS="${X_NOPBOTS:-1}"
X_SPECTATOR_NOCLIP="${X_SPECTATOR_NOCLIP:-0}"
SV_FAST_DOWNLOAD="${SV_FAST_DOWNLOAD:-1}"

# --- Masterserver ------------------------------------------------------------
SV_MASTER="${SV_MASTER:-master.cod.pm}"

# --- Bots --------------------------------------------------------------------
BOTS_ENABLED="${BOTS_ENABLED:-false}"
BOTS_COUNT="${BOTS_COUNT:-4}"
BOTS_TEAM="${BOTS_TEAM:-autoassign}"
BOTS_DIFFICULTY="${BOTS_DIFFICULTY:-5}"  # 0–10, MeatBot skill range

# --- Misc --------------------------------------------------------------------
SV_FPS="${SV_FPS:-20}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

# =============================================================================
# Step 1 — Symlink maps
#
# Maps are mounted at /server/maps/ as pk3 files.
# The engine reads from /server/main/ so we symlink each pk3 in.
# We use symlinks (not copies) to keep the image slim and avoid duplicating
# potentially large files on every container start.
# =============================================================================
log "Linking map files from /server/maps/ into /server/main/ ..."
for pk3 in /server/maps/*.pk3; do
    # Guard against empty glob (no maps mounted)
    [ -e "$pk3" ] || continue
    name="$(basename "$pk3")"
    target="/server/main/${name}"
    if [ ! -e "$target" ]; then
        ln -s "$pk3" "$target"
        log "  Linked: ${name}"
    fi
done

# =============================================================================
# Step 2 — Config: use override or generate from env vars
# =============================================================================
OVERRIDE_CFG="/server/config/server.cfg"
GENERATED_CFG="/server/main/server.cfg"

if [ -f "$OVERRIDE_CFG" ]; then
    # -------------------------------------------------------------------------
    # User mounted a hand-crafted server.cfg — use it, don't touch it.
    # -------------------------------------------------------------------------
    log "Found ${OVERRIDE_CFG} — using hand-crafted config, skipping generation."
    ln -sf "$OVERRIDE_CFG" "$GENERATED_CFG"
else
    # -------------------------------------------------------------------------
    # No override — generate server.cfg from environment variables.
    # -------------------------------------------------------------------------
    log "No override config found — generating ${GENERATED_CFG} from env vars ..."

    # Build sv_mapRotation string
    # Format: "gametype <gt> map <map> gametype <gt> map <map> ..."
    if [ -n "$MAP_ROTATION" ]; then
        ROTATION_STRING=""
        for m in $MAP_ROTATION; do
            ROTATION_STRING="${ROTATION_STRING}gametype ${GAMETYPE} map ${m} "
        done
        ROTATION_STRING="$(echo "$ROTATION_STRING" | sed 's/ $//')"
    else
        # No rotation — loop the start map
        ROTATION_STRING="gametype ${GAMETYPE} map ${START_MAP}"
    fi

    cat > "$GENERATED_CFG" << EOF
// =============================================================================
// server.cfg — auto-generated by docker-entrypoint.sh
// To use your own config, mount it at /server/config/server.cfg
// =============================================================================

// --- Server identity ---------------------------------------------------------
set sv_hostname         "${SERVER_HOSTNAME}"
set scr_motd            "${MOTD}"
set g_password          "${SERVER_PASSWORD}"
set rconpassword        "${RCON_PASSWORD}"

// --- Server options ----------------------------------------------------------
set sv_maxclients       "${MAX_CLIENTS}"
set sv_pure             "${SV_PURE}"
set sv_fps              "${SV_FPS}"
set sv_floodprotect     "1"
set sv_allowanonymous   "0"
set sv_cheats           "0"
set sv_allowdownload    "0"
set sv_privateclients   "0"
set sv_privatepassword  ""

// --- Masterserver ------------------------------------------------------------
set sv_master1          "master.cod.pm"
set sv_master2          "${SV_MASTER}"

// --- Gametype ----------------------------------------------------------------
set g_gametype          "${GAMETYPE}"
set g_allowvote         "${ALLOW_VOTE}"
set scr_allow_vote      "${ALLOW_VOTE}"
set scr_friendlyfire    "${FRIENDLY_FIRE}"
set scr_forcerespawn    "0"
set scr_drawfriend      "0"

// --- Per-gametype limits (applied to all gametypes) -------------------------
set scr_dm_scorelimit   "${SCORE_LIMIT}"
set scr_dm_timelimit    "${TIME_LIMIT}"
set scr_tdm_scorelimit  "${SCORE_LIMIT}"
set scr_tdm_timelimit   "${TIME_LIMIT}"
set scr_bel_scorelimit  "${SCORE_LIMIT}"
set scr_bel_timelimit   "${TIME_LIMIT}"
set scr_sd_scorelimit   "${SCORE_LIMIT}"
set scr_sd_timelimit    "${TIME_LIMIT}"
set scr_sd_roundlimit   "${ROUND_LIMIT}"
set scr_re_scorelimit   "${SCORE_LIMIT}"
set scr_re_timelimit    "${TIME_LIMIT}"
set scr_re_roundlimit   "${ROUND_LIMIT}"

// --- Weapons (all enabled by default) ----------------------------------------
set scr_allow_m1carbine     "1"
set scr_allow_m1garand      "1"
set scr_allow_enfield       "1"
set scr_allow_bar           "1"
set scr_allow_bren          "1"
set scr_allow_mp40          "1"
set scr_allow_mp44          "1"
set scr_allow_sten          "1"
set scr_allow_ppsh          "1"
set scr_allow_fg42          "1"
set scr_allow_thompson      "1"
set scr_allow_panzerfaust   "1"
set scr_allow_springfield   "1"
set scr_allow_kar98ksniper  "1"
set scr_allow_nagantsniper  "1"
set scr_allow_kar98k        "1"
set scr_allow_nagant        "1"
set scr_allow_mg42          "1"

// --- CoDExtended CVARs -------------------------------------------------------
set x_authorize             "${X_AUTHORIZE}"
set x_deadchat              "${X_DEADCHAT}"
set x_nopbots               "${X_NOPBOTS}"
set x_spectator_noclip      "${X_SPECTATOR_NOCLIP}"
set sv_fastDownload         "${SV_FAST_DOWNLOAD}"

// --- Logging -----------------------------------------------------------------
set g_log                   "games_mp.log"
set g_logsync               "0"
set logfile                 "1"

// --- Map rotation ------------------------------------------------------------
set sv_mapRotation          "${ROTATION_STRING}"

// --- Execute CoDaM configs ---------------------------------------------------
exec CoDaM.cfg
exec CoDaM_HamGoodies.cfg

EOF
    log "Config generated at ${GENERATED_CFG}"
fi

# =============================================================================
# Step 3 — Bots warning
#
# MeatBot requires addbot commands issued after the server starts.
# This is handled post-launch via rcon if BOTS_ENABLED=true.
# We warn here if bots are requested — a companion script handles the rest.
# =============================================================================
if [ "$BOTS_ENABLED" = "true" ]; then
    log "Bots enabled: ${BOTS_COUNT} bots, team=${BOTS_TEAM}, difficulty=${BOTS_DIFFICULTY}"
    log "NOTE: MeatBot requires 'addbot' commands after server start."
    log "      Use the companion add-bots script or issue rcon commands manually."
fi

# =============================================================================
# Step 4 — Build the server launch command
# =============================================================================
CMD_ARGS="\
    +set fs_homepath /server \
    +set fs_basepath /server \
    +set net_ip ${SERVER_IP} \
    +set net_port ${SERVER_PORT} \
    +set dedicated 1 \
    +exec server.cfg \
    +map ${START_MAP}"

# Append any extra args the user passed
if [ -n "$EXTRA_ARGS" ]; then
    CMD_ARGS="${CMD_ARGS} ${EXTRA_ARGS}"
fi

log "Starting CoD1 server on ${SERVER_IP}:${SERVER_PORT} ..."
log "  Gametype : ${GAMETYPE}"
log "  Max players : ${MAX_CLIENTS}"
log "  Start map : ${START_MAP}"

# =============================================================================
# Step 5 — Drop privileges and launch
#
# gosu re-executes the process as the UID:GID the container was started with
# (set via `user: "UID:GID"` in docker-compose.yml).
# LD_PRELOAD injects CoDExtended into the server process.
# The trailing `< /dev/null` prevents the engine from blocking on stdin.
# =============================================================================
exec gosu "$(id -u):$(id -g)" \
    env LD_PRELOAD=/server/codextended.so \
    /server/cod_lnxded \
    $CMD_ARGS \
    < /dev/null
