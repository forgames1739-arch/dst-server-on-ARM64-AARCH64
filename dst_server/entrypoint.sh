#!/bin/bash
set -euo pipefail

INSTALL_DIR="/home/ubuntu/dst/game"
SAVE_ROOT="/home/ubuntu/dst/save"
CLUSTER_NAME="${CLUSTER_NAME:-MyDediServer}"
SHARD="${SHARD:-Master}"
CLUSTER_DIR="${SAVE_ROOT}/.klei/DoNotStarveTogether/${CLUSTER_NAME}"
SHARD_DIR="${CLUSTER_DIR}/${SHARD}"

echo ">>> Качаю/обновляю DST Dedicated Server (через box32)..."
/home/ubuntu/steamcmd/steamcmd.sh \
  +@sSteamCmdForcePlatformType linux \
  +force_install_dir "${INSTALL_DIR}" \
  +login anonymous \
  +app_update "${DST_APPID}" validate \
  +quit

echo ">>> Проверяю структуру кластера..."
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

echo ">>> Содержимое кластера перед запуском (${SHARD}):"
ls -la "${SHARD_DIR}"

cd "${INSTALL_DIR}/bin64"

echo ">>> Запускаю шард ${SHARD} через box64..."
exec /usr/local/bin/box64 ./dontstarve_dedicated_server_nullrenderer_x64 \
  -persistent_storage_root "${SAVE_ROOT}/.klei" \
  -cluster "${CLUSTER_NAME}" \
  -shard "${SHARD}"