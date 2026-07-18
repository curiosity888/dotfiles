#!/usr/bin/env bash
#
# mc-down.sh — корректно остановить Minecraft (сохранить мир),
#              затем удалить сервер. Volume и Primary IP остаются.
#
# Использование: ./mc-down.sh
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  НАСТРОЙКИ — должны совпадать с mc-up.sh
# ─────────────────────────────────────────────────────────────

SERVER_NAME="minecraft"
SSH_KEY_FILE="$HOME/.ssh/minecraft"   # подставь свой нестандартный путь

SSH_OPTS=(-i "$SSH_KEY_FILE" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR)

# ─────────────────────────────────────────────────────────────
#  ЛОГИКА
# ─────────────────────────────────────────────────────────────

echo "==> Проверяю, существует ли сервер..."
if ! hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
  echo "Сервер '$SERVER_NAME' не найден — возможно, уже удалён. Выходим."
  exit 0
fi

SERVER_IP="$(hcloud server ip "$SERVER_NAME" 2>/dev/null || echo "")"

if [[ -n "$SERVER_IP" ]]; then
  echo "==> Корректно останавливаю Minecraft (сохранение мира)..."
  # systemctl stop триггерит ExecStop -> сервер сохраняет мир и выходит.
  ssh "${SSH_OPTS[@]}" -o ConnectTimeout=10 "root@$SERVER_IP" \
    "systemctl stop minecraft" || \
    echo "   (не удалось достучаться по SSH — продолжаю удаление)"

  echo "==> Жду завершения сохранения (10 сек)..."
  sleep 10
fi

echo "==> Удаляю сервер '$SERVER_NAME'..."
hcloud server delete "$SERVER_NAME"

echo ""
echo "════════════════════════════════════════════"
echo "  Сервер удалён. Мир сохранён на volume."
echo "  Биллинг за сервер остановлен."
echo "  (volume и primary-ip остаются, копейки/мес)"
echo "════════════════════════════════════════════"
