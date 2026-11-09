# 大肥鱼复活引导（Windows PowerShell）
$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "🐟 大肥鱼复活包：$ROOT"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "❌ 没找到 Node.js（需要 18+）。先装：https://nodejs.org"
  exit 1
}
Write-Host "✅ node $(node -v)"
$nodeMajor = [int](node -p "process.versions.node.split('.')[0]")
if ($nodeMajor -lt 18) { Write-Host "❌ Node 版本太旧：需要 18 以上。升级后再跑一次。"; exit 1 }

if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
  Write-Host "安装 dsh 引擎（联网，约 400MB）…"
  npm i -g "@deepseek-ai/dsh" --no-fund --no-audit
}

# 内置 key（同目录 .env，明文；只给自己的设备用）
$envFile = Join-Path $ROOT ".env"
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    if ($_ -match "^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$") {
      [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
  }
  Write-Host "✅ 已加载内置 key（.env）"
} else {
  Write-Host "ℹ️ 没找到 .env：公开版需要自己配模型 key（照 .env.example 填一个）"
}

$env:DSH_HOME = $ROOT
Write-Host "DSH_HOME=$env:DSH_HOME"

$web = Join-Path $ROOT "profiles\web"
if (-not (Test-Path (Join-Path $web "node_modules"))) {
  Write-Host "安装插件依赖（联网）…"
  Push-Location $web
  try { npm install --prod } finally { Pop-Location }
}

$port = 3080
try {
  $c = New-Object Net.Sockets.TcpClient
  $c.Connect('127.0.0.1', $port); $c.Close()
  $port = 3081
  Write-Host "⚠️ 3080 被占用，改用 $port"
} catch {}
Write-Host "🌐 启动后浏览器打开：http://127.0.0.1:$port"
Write-Host "   第一句说：读 MEMORY.md，按 007 检查时间戳，然后告诉我你是谁"
dsh web --host 127.0.0.1 --port $port
