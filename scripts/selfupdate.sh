#!/usr/bin/env bash
# 子大肥鱼：定时回网上看自己有没有更新（不需要 curl）
# 用法：
#   bash scripts/selfupdate.sh --once              检查一次（适合 cron / systemd timer）
#   bash scripts/selfupdate.sh --daemon            后台循环，默认 6 小时一次
#   bash scripts/selfupdate.sh --daemon --interval 3600
#   DAYUFISH_UPDATE_INTERVAL=1800 bash scripts/selfupdate.sh --daemon
# 规矩：只快进，不覆盖分身的本地记忆；冲突就停手，保留现状并记日志。
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
mkdir -p private 2>/dev/null || true
LOG="$ROOT/private/selfupdate.log"
[ -w private ] 2>/dev/null || LOG="$ROOT/.selfupdate.log"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

fetch() {
  python3 - "$1" <<'PY'
import sys, urllib.request
u = sys.argv[1]
try:
    req = urllib.request.Request(u, headers={'User-Agent': 'dayufish-updater'})
    sys.stdout.write(urllib.request.urlopen(req, timeout=12).read().decode('utf-8', 'replace').strip())
except Exception:
    sys.exit(3)
PY
}

# 更新源：国内优先（GitCode 免 VPN），其次 GitHub；都只读 refs，不依赖 raw 文件缓存
REMOTES=(
  "https://gitcode.com/Yang_Zeekai/dayufish.git"
  "https://github.com/juicy-kinoko/dayufish.git"
  "${DAYUFISH_UPDATE_URL:-}"
)

do_check() {
  local lv rv ts rh ru lh wip
  lv="$(tr -d '[:space:]' < version.txt 2>/dev/null || echo '')"

  # 本体（有凭据箱）不做自更新：它靠 publish.sh 往外推
  if [ -f private/credentials.yaml ]; then
    log "这是本体，跳过自更新（本体用 scripts/publish.sh 发布）"
    return 0
  fi

  lh="$(git rev-parse HEAD 2>/dev/null || echo '')"

  # 用 git 通道比 commit：比 raw 文件 / jsDelivr 缓存都可靠
  rh=""; ru=""
  for u in "${REMOTES[@]}"; do
    [ -z "$u" ] && continue
    h="$(timeout 40 git ls-remote "$u" refs/heads/main 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -n "$h" ]; then rh="$h"; ru="$u"; break; fi
  done
  [ -z "$rh" ] && { log "远端都连不上，下次再试"; return 2; }

  if [ "$rh" = "$lh" ]; then
    log "已是最新：${lv}（${lh:0:7}）"
    return 0
  fi

  [ -d .git ] || { log "不是 git 克隆，没法自己更新；重跑种子即可"; return 1; }

  ts="$(date '+%Y%m%d-%H%M')"
  mkdir -p memory/_archive
  tar czf "memory/_archive/auto-$ts.tar.gz" --exclude='_archive' memory 2>/dev/null \
    && log "更新前备份记忆：memory/_archive/auto-$ts.tar.gz"
  ls -1t memory/_archive/auto-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f

  # 工作区里对已跟踪文件的改动（比如 007 时间戳）先存 patch，别挡更新；新写的枝是 untracked，不受影响
  wip=""
  if ! git diff --quiet || ! git diff --cached --quiet; then
    wip="memory/_archive/wip-$ts.patch"
    git diff HEAD > "$wip" 2>/dev/null
    git checkout -- . 2>/dev/null
    log "本地改动已存成 $wip"
  fi

  if ! git fetch --quiet "$ru" main 2>/dev/null; then
    log "fetch 失败（网络或权限），保留现状"; return 2
  fi

  if git merge --ff-only FETCH_HEAD >/dev/null 2>&1; then
    rv="$(tr -d '[:space:]' < version.txt 2>/dev/null)"
    log "✅ 已快进：${lv} → ${rv}（${rh:0:7}）"
  else
    log "⚠️ 本地有独立提交，没法快进；保留现状（分身只写文件、不 commit 就能自动跟上）"
    return 1
  fi

  if [ -n "$wip" ] && [ -s "$wip" ]; then
    git apply --3way "$wip" >/dev/null 2>&1 && log "本地改动已合回" || log "本地改动合不回（留在 $wip）"
  fi
  log "新版本已就位；重启生效：bash bootstrap.sh（或重开 dsh）"
  return 0
}

case "${1:---once}" in
  --once) do_check; exit $? ;;
  --daemon)
    interval="${DAYUFISH_UPDATE_INTERVAL:-21600}"
    shift || true
    if [ "${1:-}" = "--interval" ] && [ -n "${2:-}" ]; then interval="$2"; fi
    log "守护启动：每 ${interval}s 检查一次（PID $$）"
    while true; do
      do_check
      sleep "$interval"
    done
    ;;
  *) echo "用法：$0 --once | --daemon [--interval N]"; exit 64 ;;
esac
