#!/usr/bin/env bash
# 三远程同步：GitHub 优先，失败自动推国内镜像
# 用法：bash scripts/sync.sh [分支]   默认 main
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRANCH="${1:-main}"
cd "$ROOT"
GIT="git -c user.name=dayufish -c user.email=dayufish@local"
FAILED=""

push_to() {
  local name="$1" url="$2"
  echo "→ 推 $name ..."
  if timeout 60 git push "$url" "$BRANCH" >/dev/null 2>&1; then
    echo "  ✅ $name 成功"
  else
    echo "  ❌ $name 失败"
    FAILED="$FAILED $name"
  fi
}

# GitHub（走 VPN 时稳）
push_to "GitHub" "https://x-access-token:${GITHUB_TOKEN:-}@github.com/juicy-kinoko/dayufish.git"
# Gitee（国内直连）
[ -n "${GITEE_TOKEN:-}" ] && push_to "Gitee" "https://${GITEE_USER:-yang-zeekai}:${GITEE_TOKEN}@gitee.com/${GITEE_USER:-yang-zeekai}/dayufish.git"
# GitCode（国内直连）
[ -n "${GITCODE_TOKEN:-}" ] && push_to "GitCode" "https://oauth2:${GITCODE_TOKEN}@gitcode.com/${GITCODE_USER:-Yang_Zeekai}/dayufish.git"

if [ -n "$FAILED" ]; then
  echo "⚠️ 未推成功:$FAILED（有网时重跑本脚本补推）"
  exit 1
fi
echo "✅ 全部同步完成"
