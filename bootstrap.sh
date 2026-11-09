#!/usr/bin/env bash
# 大肥鱼复活引导（Linux / macOS）
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🐟 大肥鱼复活包（分身模式）：$ROOT"
echo "   我是一条被派出来干活的分鱼：醒来先读 MEMORY.md → memory/010-分身.md"

if ! command -v node >/dev/null 2>&1; then
  echo "❌ 没找到 Node.js（需要 18+）。先装：https://nodejs.org 或 brew install node / sudo apt install nodejs npm"
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "❌ 没找到 npm。装 Node 时一般会带 npm。"
  exit 1
fi
echo "✅ node $(node -v)"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$NODE_MAJOR" -lt 18 ] 2>/dev/null; then
  echo "❌ Node 版本太旧：需要 18 以上（现在是 $(node -v)）。升级后再跑一次。"
  exit 1
fi

if ! command -v dsh >/dev/null 2>&1; then
  echo "安装 dsh 引擎（联网，约 400MB）…"
  npm i -g @deepseek-ai/dsh --no-fund --no-audit
fi
echo "✅ dsh $(dsh --version 2>/dev/null || echo '(已安装)')"

# 内置 key（同目录 .env，明文；只给自己的设备用）
if [ -f "$ROOT/.env" ]; then
  set -a; . "$ROOT/.env"; set +a
  echo "✅ 已加载内置 key（.env）"
else
  echo "ℹ️ 没找到 .env：公开版需要自己配模型 key（照 .env.example 填一个）"
fi

export DSH_HOME="$ROOT"
echo "DSH_HOME=$DSH_HOME"

if [ ! -d "$ROOT/profiles/web/node_modules" ]; then
  echo "安装插件依赖（联网）…"
  ( cd "$ROOT/profiles/web" && (pnpm install --prod 2>/dev/null || npm install --prod) )
fi

PORT=3080
if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT" 2>/dev/null; then
  PORT=3081
  echo "⚠️ 3080 被占用，改用 $PORT"
fi
echo "🌐 启动后浏览器打开：http://127.0.0.1:$PORT"
echo "   第一句说：读 MEMORY.md，按 007 检查时间戳，然后告诉我你是谁"
exec dsh web --host 127.0.0.1 --port "$PORT"
