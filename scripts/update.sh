#!/usr/bin/env bash
# 大肥鱼自动更新检查（骨架）
# 用法：bash scripts/update.sh          → 只检查
#       bash scripts/update.sh --apply  → 检查并下载（暂不自动替换）
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${DAYUFISH_UPDATE_URL:-https://gcore.jsdelivr.net/gh/juicy-kinoko/dayufish@main/updates.json}"
LOCAL="$(cat "$ROOT/version.txt" 2>/dev/null | tr -d '[:space:]')"
REMOTE="$(curl -s --max-time 15 "$SRC" | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])" 2>/dev/null || true)"

if [ -z "$REMOTE" ]; then
  echo "❌ 更新源不可达：$SRC"
  exit 1
fi

echo "本地版本：$LOCAL"
echo "远端版本：$REMOTE"

if [ "$LOCAL" = "$REMOTE" ]; then
  echo "✅ 已是最新"
  exit 0
fi

echo "⬆️ 发现新版本 $REMOTE"
curl -s --max-time 15 "$SRC" -o "$ROOT/.update-pending.json"
echo "已保存更新信息到 .update-pending.json（替换逻辑待启用）"
