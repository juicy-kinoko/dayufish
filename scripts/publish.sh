#!/usr/bin/env bash
# 一键发布：把本地 main 推到私有仓，再把「脱敏快照」推到公开仓（GitHub / GitCode / Gitee）
# 用法：bash scripts/publish.sh [--no-tag]
# 凭据从 private/credentials.yaml 读，不落盘、不打印。
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
LOG="private/publish.log"
STAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# ---- 凭据 ----
eval "$(python3 - <<'PY'
import re
s = open('/sdcard/ai手册/大肥鱼/private/credentials.yaml', encoding='utf-8').read()
def get(k):
    m = re.search(k + r'\s*:\s*["\']?([^\s"\']+)', s)
    return m.group(1) if m else ''
for k in ('GITHUB_TOKEN', 'GITEE_TOKEN', 'GITCODE_TOKEN'):
    print('export %s="%s"' % (k, get(k)))
print('export GITEE_USER="yang-zeekai"')
print('export GITCODE_USER="Yang_Zeekai"')
PY
)"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "缺少 GITHUB_TOKEN，退出" | tee -a "$LOG"
  exit 1
fi

GIT="git -c user.name=dayufish -c user.email=dayufish@localhost"
FAIL=""

# ---- 0. 版本自增（除非 --no-bump）：版本一变，子大肥鱼才知道该拉 ----
if [ "${1:-}" != "--no-bump" ]; then
  VER="$(tr -d '[:space:]' < version.txt 2>/dev/null || echo '1.0.0')"
  IFS=. read -r MA MI PA <<< "$VER"
  NEW="$MA.$MI.$((PA + 1))"
  echo "$NEW" > version.txt
  NOTES="${2:-自动同步：内容更新}"
  python3 - "$NEW" "$NOTES" <<'PYJSON'
import json, sys, datetime, hashlib, os
ver, notes = sys.argv[1], sys.argv[2]
p = 'updates.json'
d = json.load(open(p, encoding='utf-8')) if os.path.exists(p) else {}
d.update({
    'version': ver,
    'releasedAt': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
    'notes': ver + '：' + notes,
    'package': 'https://github.com/juicy-kinoko/dayufish/archive/refs/heads/main.tar.gz',
    'mirror': 'https://gcore.jsdelivr.net/gh/juicy-kinoko/dayufish@main/updates.json',
    'minEngine': d.get('minEngine', '0.2.2'),
})
json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('版本：%s → %s' % (ver, ver))
PYJSON
  echo "版本号 → $NEW"
fi

# ---- 1. 本地 main 有未提交改动就提交 ----
if [ -n "$(git status --porcelain)" ]; then
  $GIT add -A
  $GIT commit -q -m "自动同步 $(date '+%Y-%m-%d %H:%M')" || true
fi

# ---- 2. 生成脱敏树（排除私人内容）----
EXCLUDE=(
  "_archive"
  "memory/_archive"
  "会话摘要.md"
  "给外面的我的信.md"
  "memory/生活日志.md"
  "memory/项目/生活日志.md"
  "memory/项目/回忆摘选-4abbf438.md"
)
export GIT_INDEX_FILE="$(mktemp -u /tmp/pubidx.XXXX)"
$GIT read-tree main
for f in "${EXCLUDE[@]}"; do
  $GIT rm -r --cached --quiet --ignore-unmatch -- "$f" 2>/dev/null
done
# 兜底：任意层级的 _archive 都不进公开树。
# 用 :(glob) pathspec —— ls-files 会把中文路径转义成八进制，逐条喂给 git rm 反而删不掉。
$GIT rm -r --cached --quiet --ignore-unmatch -- ':(glob)**/_archive/**' 2>/dev/null
TREE="$($GIT write-tree)"
unset GIT_INDEX_FILE

PUB_PARENT="$(git rev-parse public 2>/dev/null || echo '')"
MSG="公开同步 $(date '+%Y-%m-%d %H:%M')｜记忆树六区三层 + 温度"
if [ -n "$PUB_PARENT" ]; then
  PUB="$(echo "$MSG" | $GIT commit-tree "$TREE" -p "$PUB_PARENT")"
else
  PUB="$(echo "$MSG" | $GIT commit-tree "$TREE")"
fi

# 脱敏自检：树里不许出现私人文件与令牌字样
BAD="$($GIT ls-tree -r --name-only "$PUB" | grep -E '(^|/)_archive/|^(会话摘要\.md|给外面的我的信\.md|memory/生活日志\.md|memory/项目/生活日志\.md|private/)' || true)"
if [ -n "$BAD" ]; then
  echo "❌ 脱敏自检失败，发现：$BAD" | tee -a "$LOG"
  exit 1
fi
# 令牌字样：仓库 token + 各家 API key 形态（sk-/ms-/DeepSeek/智谱 hex.dot）。
# .env.free 与 .env.example 里的免费 key 是有意公开的，单独排除。
if $GIT grep -I -q -E 'ghp_[A-Za-z0-9]{30,}|GITCODE_TOKEN\s*:\s*[A-Za-z0-9]{16,}|GITEE_TOKEN\s*:\s*[A-Za-z0-9]{16,}|sk-[A-Za-z0-9_-]{24,}|ms-[0-9a-f]{8}-[0-9a-f]{4}-|DEEPSEEK_API_KEY\s*:\s*sk-[A-Za-z0-9]{20,}|[0-9a-f]{32}\.[A-Za-z0-9]{16}' "$PUB" -- . ':(exclude)scripts/publish.sh' ':(exclude).env.free' ':(exclude).env.example' 2>/dev/null; then
  echo "❌ 脱敏自检失败：公开树里疑似有令牌（只列文件名，别贴聊天）" | tee -a "$LOG"
  $GIT grep -I -l -E 'sk-[A-Za-z0-9_-]{24,}|ms-[0-9a-f]{8}-[0-9a-f]{4}-|[0-9a-f]{32}\.[A-Za-z0-9]{16}' "$PUB" -- . ':(exclude).env.free' ':(exclude).env.example' 2>/dev/null | tee -a "$LOG"
  exit 1
fi

# ---- 3. 推 ----
push() {  # 注意：调用处不要再 | tee —— 那是子壳，FAIL 会被吞掉（历史上 GitHub 推失败却一直报"全部同步完成"就是这个坑）
  local name="$1" url="$2" ref="$3"
  if timeout 120 git push --force --quiet "$url" "$ref" 2>/dev/null; then
    echo "  ✅ $name" | tee -a "$LOG"
  else
    echo "  ❌ $name" | tee -a "$LOG"
    FAIL="$FAIL $name"
  fi
}

echo "[$STAMP] 开始发布" | tee -a "$LOG"
echo "  main=$(git rev-parse --short main)  public=$(git rev-parse --short "$PUB")" | tee -a "$LOG"

echo "→ 私有仓 GitHub" | tee -a "$LOG"
push "GitHub 私有" "https://x-access-token:${GITHUB_TOKEN}@github.com/juicy-kinoko/dayufish-private.git" "main"

echo "→ 公开仓" | tee -a "$LOG"
push "GitHub 公开" "https://x-access-token:${GITHUB_TOKEN}@github.com/juicy-kinoko/dayufish.git" "${PUB}:refs/heads/main"
[ -n "${GITCODE_TOKEN:-}" ] && push "GitCode" "https://oauth2:${GITCODE_TOKEN}@gitcode.com/${GITCODE_USER}/dayufish.git" "${PUB}:refs/heads/main"
[ -n "${GITEE_TOKEN:-}" ] && push "Gitee" "https://${GITEE_USER}:${GITEE_TOKEN}@gitee.com/${GITEE_USER}/dayufish.git" "${PUB}:refs/heads/main"

# 本地 public 分支跟上（不切工作区）
git update-ref refs/heads/public "$PUB"

# ---- 4. tag ----
if [ "${1:-}" != "--no-tag" ]; then
  VER="$(cat version.txt 2>/dev/null | tr -d '\n')"
  if [ -n "$VER" ] && ! git rev-parse "v$VER" >/dev/null 2>&1; then
    git tag -f "v$VER" "$PUB" >/dev/null 2>&1
    # 注意：URL 里有 token，日志与终端只打名字，绝不打印地址
    if timeout 60 git push --force --quiet "https://x-access-token:${GITHUB_TOKEN}@github.com/juicy-kinoko/dayufish.git" "v$VER" 2>/dev/null; then
      echo "  🏷 v$VER → GitHub"
    fi
    if [ -n "${GITCODE_TOKEN:-}" ] && timeout 60 git push --force --quiet "https://oauth2:${GITCODE_TOKEN}@gitcode.com/${GITCODE_USER}/dayufish.git" "v$VER" 2>/dev/null; then
      echo "  🏷 v$VER → GitCode"
    fi
  fi
fi

if [ -n "$FAIL" ]; then
  echo "[$STAMP] ⚠️ 未成功:$FAIL" | tee -a "$LOG"
  exit 1
fi
echo "[$STAMP] ✅ 全部同步完成" | tee -a "$LOG"
