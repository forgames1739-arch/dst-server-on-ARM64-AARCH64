# Complete Guide: DST Server on ARM via Dockge

## Why this complex scheme is needed

Klei doesn't release an ARM version of the dedicated server — the binary is x86_64 only. So the only working approach on ARM is to run the x86_64 binary through **box64** (an x86→ARM emulator), and SteamCMD itself (which is 32-bit) through the built-in **box32**. The base image `sonroyaalmerol/steamcmd-arm64` already contains both box64 and box32, and is actively maintained (updated weekly following box64/box86 upstream).

---

## Step 0. Preparation on the Klei side

1. Go to https://accounts.klei.com/account/game/servers?game=DontStarveTogether under the account that owns the game.
2. Enter any cluster name and click **"Add New Server"** — you'll get a token like `pds-...`.
3. Click **"Configure Server"** next to the created server — Klei will offer to download a ready-made `.zip` archive with basic cluster configs (`cluster.ini`, `cluster_token.txt`, `Master` and `Caves` folders). Download it — this saves you from writing configs by hand (At the end, if you wish, you can set up a world on your device and upload it to the server folder with the world).
4. Don't forget to assign permissions to yourself and the container one by one! When editing files, type "sudo chown -R $USER:$USER *your path, for example /mnt/data/stacks/dst_server", and when starting the server, grant permissions to the container with the command "sudo chown -R 1000:1000 *your path, for example /mnt/data/stacks/dst_server". Secure each action with the command "sudo chmod -R 775 *your path, for example /mnt/data/stacks/dst_server".

Save the token somewhere separately — you'll need it in `compose.yaml`.

---

## Step 1. Stack structure in Dockge

Decide where the stack will live, e.g. `/mnt/data/stacks/dst_server/`. In Dockge, create a Compose stack with this name — it'll create the folder itself. The final structure should look like this:

```
/mnt/data/stacks/dst_server/
├── compose.yaml
├── Dockerfile
├── entrypoint.sh
└── save/
    └── DoNotStarveTogether/
            └── MyDediServer/          ← name = CLUSTER_NAME from compose.yaml
                ├── cluster.ini
                ├── cluster_token.txt
                ├── Master/
                │   └── server.ini
                └── Caves/
                    └── server.ini
```

**Critical**: the folder inside `/DoNotStarveTogether/` must be named **exactly** the same as the `CLUSTER_NAME` value in `compose.yaml`. Even a one-character mismatch means the server won't find the token.
**Additional Note**: After the FIRST launch, the container will create the .klei/DoNotStarveTogether folder and copy the contents of DoNotStarveTogether/... . You will need to delete everything from the DoNotStarveTogether/ folder except the token file. If you don't delete the contents, you will end up with two identical servers running (this step should only be done after configuring and running the server for the first time).

---

## Step 2. Dockerfile

```dockerfile
FROM sonroyaalmerol/steamcmd-arm64:root-bookworm

RUN usermod -l ubuntu -d /home/ubuntu -m steam \
    && groupmod -n ubuntu steam

USER ubuntu
WORKDIR /home/ubuntu

ENV DST_APPID=343050 \
    HOME=/home/ubuntu

RUN mkdir -p /home/ubuntu/dst/save

COPY --chown=ubuntu:ubuntu entrypoint.sh /home/ubuntu/entrypoint.sh
RUN chmod +x /home/ubuntu/entrypoint.sh

ENTRYPOINT ["/home/ubuntu/entrypoint.sh"]
```

Why user `ubuntu` instead of `steam` from the base image — purely for admin convenience (fewer different users on the server). UID/GID stay the same on rename, so the already-installed SteamCMD inside the image doesn't break.

---

## Step 3. entrypoint.sh

```bash
#!/bin/bash
set -euo pipefail

INSTALL_DIR="/home/ubuntu/dst/game"
SAVE_ROOT="/home/ubuntu/dst/save"
CLUSTER_NAME="${CLUSTER_NAME:-MyDediServer}"
SHARD="${SHARD:-Master}"
CLUSTER_DIR="${SAVE_ROOT}/.klei/DoNotStarveTogether/${CLUSTER_NAME}"
SHARD_DIR="${CLUSTER_DIR}/${SHARD}"

echo ">>> Downloading/updating DST Dedicated Server (via box32)..."
/home/ubuntu/steamcmd/steamcmd.sh \
  +@sSteamCmdForcePlatformType linux \
  +force_install_dir "${INSTALL_DIR}" \
  +login anonymous \
  +app_update "${DST_APPID}" validate \
  +quit

echo ">>> Checking cluster structure..."
mkdir -p "${SHARD_DIR}/mods"

if [ ! -f "${CLUSTER_DIR}/cluster_token.txt" ] && [ -n "${CLUSTER_TOKEN:-}" ]; then
  echo "${CLUSTER_TOKEN}" > "${CLUSTER_DIR}/cluster_token.txt"
fi

if [ ! -f "${CLUSTER_DIR}/cluster.ini" ]; then
cat > "${CLUSTER_DIR}/cluster.ini" <<EOF
[GAMEPLAY]
game_mode = ${GAME_MODE:-survival}
max_players = ${MAX_PLAYERS:-6}
pvp = ${PVP:-false}
pause_when_empty = true

[NETWORK]
cluster_name = ${CLUSTER_DISPLAY_NAME:-$CLUSTER_NAME}
cluster_description = ${CLUSTER_DESCRIPTION:-DST server}
cluster_password = ${CLUSTER_PASSWORD:-}
cluster_intention = ${CLUSTER_INTENTION:-cooperative}
lan_only_cluster = false

[MISC]
console_enabled = true

[SHARD]
shard_enabled = false
EOF
fi

if [ ! -f "${SHARD_DIR}/server.ini" ]; then
if [ "${SHARD}" = "Caves" ]; then
cat > "${SHARD_DIR}/server.ini" <<EOF
[NETWORK]
server_port = 11000

[SHARD]
is_master = false
name = Caves

[STEAM]
master_server_port = 12348
authentication_port = 12346

[ACCOUNT]
encode_user_path = true
EOF
else
cat > "${SHARD_DIR}/server.ini" <<EOF
[NETWORK]
server_port = 10999

[SHARD]
is_master = true
name = Master

[STEAM]
master_server_port = 12347
authentication_port = 12346

[ACCOUNT]
encode_user_path = true
EOF
fi
fi

echo ">>> Cluster contents before startup (${SHARD}):"
ls -la "${SHARD_DIR}"

cd "${INSTALL_DIR}/bin64"

echo ">>> Starting shard ${SHARD} via box64..."
exec /usr/local/bin/box64 ./dontstarve_dedicated_server_nullrenderer_x64 \
  -persistent_storage_root "${SAVE_ROOT}/.klei" \
  -cluster "${CLUSTER_NAME}" \
  -shard "${SHARD}"
```

### The most important nuance in this whole file

The DST server builds its path using this formula:
```
<persistent_storage_root>/<conf_dir>/<cluster>/<shard>
```
`-conf_dir` defaults to `DoNotStarveTogether` (without `.klei`!). The `.klei` folder is part of the *default* `persistent_storage_root` on Linux, not part of `conf_dir`. So we pass:
```bash
-persistent_storage_root "${SAVE_ROOT}/.klei"
```
instead of just `${SAVE_ROOT}` — otherwise the server would look for files in `.../save/DoNotStarveTogether/...` (no `.klei`) and never find the token, no matter how many file permissions you set. This was the cause of the long struggle with "No auth token could be found" — it wasn't about permissions, it was exactly this path.

---

## Step 4. compose.yaml (with caves right away)

```yaml
services:
  dst-server:
    build: .
    container_name: dst-server
    restart: unless-stopped
    environment:
      SHARD: Master
      CLUSTER_TOKEN: pds-insert_your_token_here
      CLUSTER_NAME: MyDediServer
      CLUSTER_DISPLAY_NAME: Name shown in server browser
      CLUSTER_DESCRIPTION: Server description
      CLUSTER_PASSWORD: "1234"
      MAX_PLAYERS: "6"
      GAME_MODE: survival
      PVP: "false"
      ARM64_DEVICE: generic
      BOX64_DYNAREC_BIGBLOCK: "0"
      BOX64_DYNAREC_SAFEFLAGS: "2"
      BOX64_DYNAREC_STRONGMEM: "3"
      BOX64_DYNAREC_FASTROUND: "0"
      BOX64_DYNAREC_FASTNAN: "0"
      BOX64_DYNAREC_X87DOUBLE: "1"
    ports:
      - 10999:10999/udp
      - 12346:12346/udp
      - 12347:12347/udp
    volumes:
      - /mnt/data/stacks/dst_server/save:/home/ubuntu/dst/save
    networks:
      - dst-net

  dst-server-caves:
    build: .
    container_name: dst-server-caves
    restart: unless-stopped
    depends_on:
      - dst-server
    environment:
      SHARD: Caves
      CLUSTER_TOKEN: pds-insert_your_token_here
      CLUSTER_NAME: MyDediServer
      ARM64_DEVICE: generic
      BOX64_DYNAREC_BIGBLOCK: "0"
      BOX64_DYNAREC_SAFEFLAGS: "2"
      BOX64_DYNAREC_STRONGMEM: "3"
      BOX64_DYNAREC_FASTROUND: "0"
      BOX64_DYNAREC_FASTNAN: "0"
      BOX64_DYNAREC_X87DOUBLE: "1"
    ports:
      - 11000:11000/udp
    volumes:
      - /mnt/data/stacks/dst_server/save:/home/ubuntu/dst/save
    networks:
      - dst-net

networks:
  dst-net:
```

About the `BOX64_DYNAREC_*` variables — these are the officially recommended values for game server stability under box64, `X87DOUBLE=1` in particular matters for correct physics/determinism relative to the original x86 client.

About paths in `volumes:` — use an **absolute path** (`/mnt/data/stacks/dst_server/save`), not `./save`. During experiments, the relative path sometimes led to confusion about where things were actually mounted.

---

## Step 5. Cluster files — manually or from the Klei archive

### Option A — from the archive downloaded in Step 0 (recommended)
Extract `MyDediServer.zip` so you get:
```
save/.klei/DoNotStarveTogether/MyDediServer/
                              ├── cluster.ini
                              ├── cluster_token.txt
                              ├── Master/...
                              └── Caves/...

save/DoNotStarveTogether/MyDediServer/
                              └── cluster_token.txt
```
Be sure to check permissions: the container runs as a user with a UID matching `ubuntu` inside the image. If files were dropped via SFTP as root, you may need:
```bash
sudo chmod -R 777 /mnt/data/stacks/dst_server/save
```
(crude, but reliable for a home server — rules out all permission issues at once).

### Option B — let entrypoint.sh create everything itself
If you just leave the `save` folder empty — the script will create `cluster.ini`, `server.ini`, and (if `CLUSTER_TOKEN` is set in compose) `cluster_token.txt` on first startup. The one thing the script doesn't create itself is the world (save data) — that appears after the first successful server start.

### About cluster.ini for cave support
Open `cluster.ini`, check the `[SHARD]` block:
```ini
[SHARD]
shard_enabled = true
bind_ip = 0.0.0.0
master_ip = dst-server
master_port = 10888
```
`master_ip = dst-server` — this is the name of the Master service from compose.yaml; Docker resolves it as a hostname within the shared `dst-net` network.

---

## Step 6. Build and run

Via the host terminal (SSH, not inside the container) in the stack folder:

```bash
cd /mnt/data/stacks/dst_server
docker compose build --no-cache
docker compose up -d
docker compose logs -f
```

`--no-cache` on the first build is important — it guarantees Docker runs through the whole Dockerfile from scratch instead of taking old layers.

---

## Step 7. How to tell from the log that it worked

Look for these in order:
1. `Success! App '343050' fully installed.` — SteamCMD downloaded the game.
2. `>>> Cluster contents before startup` with a file listing next to it — confirms the volume is mounted correctly.
3. No `No auth token could be found` line anywhere — if it appears, the token wasn't found (see common errors below).
4. `[Connect] PendingConnection::Reset(true)` — server started connecting to Steam.
5. `[200] Account Communication Success` — successful authorization.
6. `Server registered via geo DNS in ...` — server registered and is visible externally.
7. `Sim paused` — world loaded and waiting for players.

The line `[BOX64] Error initializing native libSDL3.so.0 ...` is a harmless warning — box64 just can't find native SDL3 and falls back to the emulated one bundled with the game; doesn't affect server operation.

The line `[S_API FAIL] Tried to access Steam interface STEAMUGC...` is also normal if you're not using Steam Workshop mods.

---

## Common errors and their causes (cheat sheet)

| Log symptom | Cause | Solution |
|---|---|---|
| `No auth token could be found` | `cluster_token.txt` file not found at the path the server actually looks at | Check: 1) whether `-persistent_storage_root` is built correctly (`.klei` must be in it, not in conf_dir separately); 2) whether `CLUSTER_NAME` matches the folder name; 3) file permissions |
| `mkdir: cannot create directory ... Permission denied` | Volume created with root as owner, but container runs as a different UID | `chmod -R 777` on the `save` folder on the host, or `chown` to the right UID |
| Container exits with code 0 in a loop (restart loop) | Usually the same thing — failing on mkdir/permissions, and `restart: unless-stopped` restarts it endlessly | Look at exactly which line the log fails on before exit |
| `Skipping portal[...] (no available shard [Caves] connected)` | Caves shard isn't running or can't reach Master | Check that both containers are in the same network (`networks:`) and `master_ip` in cluster.ini points to the Master service name |
| Changes in compose.yaml don't apply after restart | The "Restart" button in Dockge just does `docker restart`, not a container recreation with new volumes | Use `docker compose down && docker compose up -d` or `--force-recreate` |

---

## After the first successful launch

The server will be visible in-game by name (the `CLUSTER_DISPLAY_NAME` value) in the server list, or friends can connect directly through the game console (`~`):
```
c_connect("your_server_IP", 10999)
```

Don't forget to open the following UDP ports on the host: `10999`, `11000` (if using caves), `12346`, `12347`, `12348` (if using caves).

Make sure you delete the contents of the /save/DoNotStarveTogether folder except the token. At the end, the container structure looks like this:

/mnt/data/stacks/dst_server/
├── compose.yaml
├── Dockerfile
├── entrypoint.sh
└── save/
    └── .klei/
        └── DoNotStarveTogether/
            └── MyDediServer/
                ├── cluster.ini
                ├── cluster_token.txt
                ├── Master/
                │   └── server.ini
                └── Caves/
                    └── server.ini

    └── DoNotStarveTogether/
        └── cluster_token.txt
