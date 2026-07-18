#!/usr/bin/env bash
#
# mc-up.sh — поднять Minecraft-сервер на Hetzner из снэпшота,
#            подцепить volume с миром, IP и firewall, запустить сервер.
#
# Использование: ./mc-up.sh
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  НАСТРОЙКИ — подставь свои значения (см. команды в комментариях)
# ─────────────────────────────────────────────────────────────
START_TS=$(date +%s)

# Имя создаваемого сервера (как он будет называться в Hetzner)
SERVER_NAME="minecraft"

# Тип сервера. Основной выбор + fallback, если основного нет в наличии.
# hcloud server-type list
SERVER_TYPE="cx33"
SERVER_TYPE_FALLBACK="cpx22"

# Локация. ВАЖНО: должна совпадать с локацией volume и primary-ip!
# hcloud location list
LOCATION="fsn1"

# ID снэпшота (образа с установленной Java + systemd-сервисом)
# hcloud image list --type snapshot -o columns=id,description
IMAGE_ID="399642399"

# Имя volume с миром Minecraft
# hcloud volume list -o columns=id,name,location
VOLUME_NAME="minecraft-world"

# Имя SSH-ключа, загруженного в Hetzner
# hcloud ssh-key list
SSH_KEY_NAME="minecraft-key"

# Имя firewall с открытым портом 25565 (+ ssh 22)
# hcloud firewall list -o columns=id,name
FIREWALL_NAME="minecraft-fw"

# Primary IP. Оставь пустым ("") если используешь динамический IP.
# hcloud primary-ip list -o columns=id,name,ip
PRIMARY_IP_NAME="minecraft-ip"

# Локальный SSH-ключ и alias из ~/.ssh/config (для обновления HostName)
SSH_ALIAS="minecraft"
SSH_KEY_FILE="$HOME/.ssh/minecraft"   # подставь свой нестандартный путь


SSH_OPTS=(-i "$SSH_KEY_FILE" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR)

# ─────────────────────────────────────────────────────────────
#  ЛОГИКА — ниже менять обычно не нужно
# ─────────────────────────────────────────────────────────────

echo "==> Проверяю, не запущен ли уже сервер..."
if hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
  echo "Сервер '$SERVER_NAME' уже существует. Если он завис — удали через ~/.local/bin/mc-down.sh"
  exit 1
fi

# Собираем флаги создания
CREATE_ARGS=(
  --name "$SERVER_NAME"
  --image "$IMAGE_ID"
  --location "$LOCATION"
  --ssh-key "$SSH_KEY_NAME"
  --volume "$VOLUME_NAME"
)

# Primary IP подключаем только если задан
if [[ -n "$PRIMARY_IP_NAME" ]]; then
  CREATE_ARGS+=( --primary-ipv4 "$PRIMARY_IP_NAME" )
fi

echo "==> Создаю сервер ($SERVER_TYPE)..."
if ! hcloud server create --type "$SERVER_TYPE" "${CREATE_ARGS[@]}"; then
  echo "!! '$SERVER_TYPE' недоступен, пробую fallback '$SERVER_TYPE_FALLBACK'..."
  hcloud server create --type "$SERVER_TYPE_FALLBACK" "${CREATE_ARGS[@]}"
fi

echo "==> Применяю firewall..."
hcloud firewall apply-to-resource "$FIREWALL_NAME" \
  --type server --server "$SERVER_NAME"

# Получаем IP сервера
SERVER_IP="$(hcloud server ip "$SERVER_NAME")"
echo "==> IP сервера: $SERVER_IP"

# Обновляем HostName в ~/.ssh/config для alias (если динамический IP)
if [[ -n "$SERVER_IP" ]]; then
  echo "==> Обновляю ~/.ssh/config (Host $SSH_ALIAS -> $SERVER_IP)..."
  # Заменяем строку HostName под нужным Host-блоком.
  # Требует, чтобы блок 'Host minecraft' уже существовал в ~/.ssh/config.
  if grep -q "Host $SSH_ALIAS" "$HOME/.ssh/config" 2>/dev/null; then
    sed -i "/Host $SSH_ALIAS\$/,/^Host /{s/HostName .*/HostName $SERVER_IP/}" "$HOME/.ssh/config"
  else
    echo "   (блок 'Host $SSH_ALIAS' не найден в ~/.ssh/config — подключайся по IP напрямую)"
  fi
fi

# Удаляем устаревший host key от предыдущего сервера на этом IP
ssh-keygen -R "$SERVER_IP" 2>/dev/null || true

echo "==> Жду, пока сервер загрузится и поднимет SSH..."
for i in {1..30}; do
  if ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 "root@$SERVER_IP" "true" 2>/dev/null; then
    echo "   SSH доступен."
    break
  fi
  sleep 5
done

echo "==> Запускаю Minecraft (systemd)..."
ssh "${SSH_OPTS[@]}" "root@$SERVER_IP" "systemctl start minecraft"

echo ""
echo "════════════════════════════════════════════"
echo "  Готово! Подключайтесь:  $SERVER_IP"
echo "  Версия клиента: 26.2"
echo "════════════════════════════════════════════"
END_TS=$(date +%s)
echo "==> Полное время от создания до готовности: $((END_TS - START_TS)) сек"
