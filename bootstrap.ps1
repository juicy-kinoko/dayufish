# 大肥鱼复活引导（Windows PowerShell）
$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "🐟 大肥鱼复活包：$ROOT"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "❌ 没找到 Node.js（需要 18+）。先装：https://nodejs.org"
  exit 1
}
Write-Host "✅ node $(node -v)"

if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
  Write-Host "安装 dsh 引擎（联网，约 400MB）…"
  npm i -g "@deepseek-ai/dsh"
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
}

$env:DSH_HOME = $ROOT
Write-Host "DSH_HOME=$env:DSH_HOME"

$web = Join-Path $ROOT "profiles\web"
if (-not (Test-Path (Join-Path $web "node_modules"))) {
  Write-Host "安装插件依赖（联网）…"
  Push-Location $web
  try { npm install --prod } finally { Pop-Location }
}

Write-Host "🌐 启动后浏览器打开：http://127.0.0.1:3080"
Write-Host "   第一句说：读 MEMORY.md，按 007 检查时间戳，然后告诉我你是谁"
dsh web --host 127.0.0.1 --port 3080
