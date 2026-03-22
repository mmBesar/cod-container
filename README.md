# 🎖️ Call of Duty 1 Dedicated Server

A Docker container for running a **Call of Duty 1 (v1.1)** dedicated server on Linux.

- **CoDExtended** — cracked client support, fast download, bot fixes
- **CoDaM v1.31 + HamGoodies v1.35** — server-side admin, map rotation, mod framework
- **MeatBot RC2** — optional bots (experimental on dedicated servers)
- **All config via environment variables** — no config files to edit
- **Maps mounted at runtime** — slim image, bring your own `.pk3` files
- **Runs as your own UID:GID** — no root, no permission headaches

[![Build & Push to GHCR](https://github.com/mmBesar/cod-container/actions/workflows/build.yml/badge.svg)](https://github.com/mmBesar/cod-container/actions/workflows/build.yml)

---

## 📋 Requirements

- Docker Engine 24+
- Docker Compose v2+
- A copy of your CoD1 map `.pk3` files (from your game installation)
- Linux host (amd64 only — the CoD1 server binary is 32-bit x86)

---

## 🚀 Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/mmBesar/cod-container.git
cd cod-container
```

### 2. Create your environment file

```bash
cp .env.example .env
```

Edit `.env` to set your server name, RCON password, and anything else you want to change. The defaults will work for a first run.

### 3. Create the local directories

```bash
mkdir -p main logs config
```

### 4. Add your CoD1 game files

Copy the minimum required files from your legitimate CoD1 installation into `./main/`:

| File | Notes |
|---|---|
| `pak0.pk3` | Core assets — maps, models, textures, sounds |
| `pak1.pk3` – `pak6.pk3` | Additional base assets |
| `localized_english_pak0.pk3` | English text + `default_mp.cfg` |
| `localized_english_pak1.pk3` | English voice lines |

```bash
# Copy only what is needed - skip DLLs, saves, demos, configs
cp /path/to/CallOfDuty/main/pak{0,1,2,3,4,5,6}.pk3 ./main/
cp /path/to/CallOfDuty/main/localized_english_pak{0,1}.pk3 ./main/
```

> **Do not copy:** `.dll` files, `config.cfg`, `config_mp.cfg`, `save/`, `demos/`, `hunkusage.dat`, or any `z_*.pk3` mod files.
>
> **`game.mp.i386.so`** is the Linux game logic library — it is already baked into the image from the official Linux server tarball. You do not need to supply it.
>
> **CoDaM** mod files are also baked into the image. You do not need to copy them.

### 5. Start the server

```bash
# Run as your current user (recommended)
export UID=$(id -u) GID=$(id -g)
docker compose up -d
```

### 6. Follow the logs

```bash
docker compose logs -f
```

### 7. Stop the server

```bash
docker compose down
```

---

## ⚙️ Configuration

All configuration is done via environment variables in your `.env` file. No config files to edit manually.

| Variable | Default | Description |
|---|---|---|
| `UID` | `1000` | Host user ID to run the server as |
| `GID` | `1000` | Host group ID to run the server as |
| **Server identity** | | |
| `SERVER_HOSTNAME` | `CoD1 Docker Server` | Server name shown in the browser |
| `SERVER_PASSWORD` | *(empty)* | Join password — empty = public server |
| `RCON_PASSWORD` | `changeme` | Remote console password — **change this!** |
| `MOTD` | `Welcome...` | Message of the day shown on join |
| **Network** | | |
| `SERVER_PORT` | `28960` | UDP port to listen on |
| `SERVER_IP` | *(auto)* | Bind IP — auto-detects container IP if empty |
| **Gameplay** | | |
| `GAMETYPE` | `tdm` | `dm` `tdm` `sd` `re` `bel` |
| `MAX_CLIENTS` | `16` | Maximum player slots |
| `SV_PURE` | `0` | Pure server check — `0` = allow custom content |
| `FRIENDLY_FIRE` | `0` | `1` = friendly fire on |
| `SCORE_LIMIT` | `100` | Score limit (applied to all gametypes) |
| `TIME_LIMIT` | `30` | Time limit in minutes |
| `ROUND_LIMIT` | `0` | Round limit — `0` = unlimited |
| `ALLOW_VOTE` | `0` | `1` = allow players to vote |
| **Maps** | | |
| `START_MAP` | `mp_harbor` | First map loaded on server start |
| `MAP_ROTATION` | *(empty)* | Space-separated map list — empty = loop `START_MAP` |
| **CoDExtended** | | |
| `X_AUTHORIZE` | `0` | `0` = cracked clients allowed, `1` = require CD key |
| `X_DEADCHAT` | `0` | `1` = dead players' chat visible to alive players |
| `X_NOPBOTS` | `1` | `1` = fix bot movement glitches |
| `X_SPECTATOR_NOCLIP` | `0` | `1` = spectators can fly through walls |
| `SV_FAST_DOWNLOAD` | `1` | `1` = HTTP fast download redirect |
| **Masterserver** | | |
| `SV_MASTER` | `master.cod.pm` | Community masterserver |
| **Bots** | | |
| `BOTS_ENABLED` | `false` | `true` = enable MeatBot bots |
| `BOTS_COUNT` | `4` | Number of bots to add |
| `BOTS_TEAM` | `autoassign` | `allies` `axis` `autoassign` |
| `BOTS_DIFFICULTY` | `5` | `0` (easiest) to `10` (hardest) |
| **Misc** | | |
| `SV_FPS` | `20` | Server tick rate |
| `EXTRA_ARGS` | *(empty)* | Raw args appended to the server launch command |

### Map Rotation Example

```env
START_MAP=mp_harbor
MAP_ROTATION=mp_harbor mp_dawnville mp_carentan mp_brecourt mp_bocage
```

The entrypoint builds the correct `sv_mapRotation` string automatically, honouring the gametype per map.

### Using a Hand-Crafted Config

If you want full manual control, drop a `server.cfg` into `./config/`:

```bash
cp my_custom_server.cfg ./config/server.cfg
docker compose restart
```

The entrypoint detects it and skips env-var generation entirely. Your file is used as-is.

---

## 🗂️ Directory Layout

```
cod-container/
├── main/          ← your CoD1 main/ folder (pak*.pk3, game.mp.i386.so)
├── logs/          ← games_mp.log appears here
├── config/        ← optional: place server.cfg here to override env vars
├── Dockerfile
├── docker-compose.yml
├── docker-entrypoint.sh
├── .env.example
├── .env           ← your local config (never committed)
└── .gitignore
```

Inside the container the layout is:

```
/server/
├── cod_lnxded          ← baked in: server binary
├── codextended.so      ← baked in: CoDExtended library
├── codam/              ← baked in: CoDaM + HamGoodies mod files
├── main/               ← mounted: your CoD1 main/ folder
├── logs/               ← mounted: server log output
└── config/             ← mounted: optional server.cfg override
```

---

## 🤖 Bots

Bots are provided by **MeatBot RC2**, a port of the CoD2 Meatbot mod.

> ⚠️ **Warning:** MeatBot was originally designed for listen servers. Use on dedicated servers is experimental and may be unstable. TDM only.

### Enabling Bots

In your `.env`:

```env
BOTS_ENABLED=true
BOTS_COUNT=6
BOTS_TEAM=autoassign
BOTS_DIFFICULTY=5
```

Bots are added automatically after the server starts by issuing `addbot` commands via RCON.

### Bot Limitations

- TDM gametype only — bots do not work in SD, RE, or BEL
- `SV_PURE` must be `0` (already the default)
- Bot count is approximate — the server may not accept all bots on first map load
- If bots behave erratically, reduce `BOTS_DIFFICULTY` or restart the server

---

## 🎮 Connecting to Your Server

### Client Version

Your players **must** be on **CoD1 v1.1**. The Steam version ships as v1.5 which is incompatible. Downgrading takes under a minute:

1. Download the [CoD1 v1.1 downgrade patch](https://cod.pm)
2. Extract and run `downgrade.bat` (or follow the Linux equivalent)
3. Done — connect via the server browser or direct IP

### Direct Connect

In the CoD1 console (press `~`):

```
/connect YOUR_SERVER_IP:28960
```

### RCON

```
/rconpassword YOUR_RCON_PASSWORD
/rcon status
/rcon map mp_carentan
```

---

## 🔧 RCON Commands

Useful RCON commands to manage your server at runtime:

| Command | Description |
|---|---|
| `rcon status` | Show connected players |
| `rcon map mp_carentan` | Change map immediately |
| `rcon map_rotate` | Advance to next map in rotation |
| `rcon kick "PlayerName"` | Kick a player |
| `rcon clientkick <id>` | Kick by slot ID |
| `rcon g_gametype tdm` | Change gametype |
| `rcon sv_maxclients 8` | Change max players |
| `rcon quit` | Gracefully shut down the server |

---

## 🏗️ Building Locally

```bash
docker build -t cod1-server .
```

To test without pushing:

```bash
docker run --rm \
  -p 28960:28960/udp \
  -v $(pwd)/main:/server/main:ro \
  -v $(pwd)/logs:/server/logs \
  -e SERVER_HOSTNAME="My Test Server" \
  -e RCON_PASSWORD="test" \
  -u "$(id -u):$(id -g)" \
  cod1-server
```

---

## 📦 Image Details

| | |
|---|---|
| Base image | `debian:bookworm-slim` |
| Architecture | `linux/amd64` |
| CoD version | `1.1` |
| CoDExtended | latest release |
| CoDaM | v1.31 |
| CoDaM HamGoodies | v1.35 |
| Approx. image size | ~350MB |
| Published to | `ghcr.io/mmbesar/cod-container` |

> **Why `bookworm` and not `trixie`?** CoD1 requires `libstdc++5:i386` — the old GCC 3.x C++ runtime. This package was dropped in Debian trixie. Bookworm is the newest Debian release that still carries it.

> **Why `amd64` only?** The `cod_lnxded` binary is a 32-bit x86 ELF. There is no ARM build and no open-source reimplementation mature enough to use. ARM64 via QEMU user-mode emulation is possible but not supported here.

---

## 🔄 CI/CD

Every push to `main` builds and publishes `:latest` to GHCR automatically via GitHub Actions. Tagging a release publishes a versioned image:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This produces:
- `ghcr.io/mmbesar/cod-container:1.0.0`
- `ghcr.io/mmbesar/cod-container:1.0`
- `ghcr.io/mmbesar/cod-container:latest`

---

## 📜 License

This project is licensed under the **GPL-2.0** license — see [LICENSE](LICENSE) for details.

Call of Duty® is a registered trademark of Activision Publishing, Inc. This project is not affiliated with or endorsed by Activision. It does not distribute any copyrighted game assets. You must own a legitimate copy of Call of Duty 1 to use the map files.

---

## 🙏 Credits

- [CoDExtended](https://github.com/riicchhaarrd/codextended) — server extension library
- [CoDaM](https://de.dvotx.org/dump/cod1/CoDaM/) — server mod framework
- [cod.pm](https://cod.pm) — community guide and masterserver
- [MeatBot RC2](https://de.dvotx.org/dump/cod1/) — bot mod
