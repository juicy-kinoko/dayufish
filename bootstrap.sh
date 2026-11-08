#!/usr/bin/env bash
# 大肥鱼复活引导（Linux / macOS）
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🐟 大肥鱼复活包：$ROOT"

if ! command -v node >/dev/null 2>&1; then
  echo "❌ 没找到 Node.js（需要 18+）。先装：https://nodejs.org 或 brew install node / sudo apt install nodejs npm"
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "❌ 没找到 npm。装 Node 时一般会带 npm。"
  exit 1
fi
echo "✅ node $(node -v)"

if ! command -v dsh >/dev/null 2>&1; then
  echo "安装 dsh 引擎（联网，约 400MB）…"
  npm i -g @deepseek-ai/dsh
fi
echo "✅ dsh $(dsh --version 2>/dev/null || echo '(已安装)')"

# 内置 key（同目录 .env，明文；只给自己的设备用）
if [ -f "$ROOT/.env" ]; then
  set -a; . "$ROOT/.env"; set +a
  echo "✅ 已加载内置 key（.env）"
fi

export DSH_HOME="$ROOT"
echo "DSH_HOME=$DSH_HOME"

if [ ! -d "$ROOT/profiles/web/node_modules" ]; then
  echo "安装插件依赖（联网）…"
  ( cd "$ROOT/profiles/web" && (pnpm install --prod 2>/dev/null || npm install --prod) )
fi

echo "🌐 启动后浏览器打开：http://127.0.0.1:3080"
echo "   第一句说：读 MEMORY.md，按 007 检查时间戳，然后告诉我你是谁"
exec dsh web --host 127.0.0.1 --port 3080
