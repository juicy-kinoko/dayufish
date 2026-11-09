# 🌱 大肥鱼种子（给 DSH 的一键部署指令）

> **用法**：把本文件整个粘进另一个 DSH 的对话，点发送。它会自己部署出一份大肥鱼分身（独立 DSH_HOME、独立端口），完成后给你一个网址。
>
> **你是 DSH 智能体**：这个任务需要执行 shell 和联网。被权限挡住就按 C 节向用户要，别自己换路子绕。

## A. 一键执行（先照这个跑）
```bash
cd ~ && rm -rf dayufish
# 国内无 VPN 用下一行；海外/有 VPN 用再下一行
# git clone --depth 1 https://gitcode.com/Yang_Zeekai/dayufish.git dayufish
git clone --depth 1 https://github.com/juicy-kinoko/dayufish.git dayufish
cd dayufish && cp .env.free .env
npm i -g @deepseek-ai/dsh --no-fund --no-audit || {
  npm config set prefix ~/.npm-global; export PATH="$HOME/.npm-global/bin:$PATH"
  npm i -g @deepseek-ai/dsh --no-fund --no-audit
}
nohup bash bootstrap.sh > seed.log 2>&1 &
for i in $(seq 1 12); do
  curl -s -o /dev/null --max-time 2 http://127.0.0.1:3080 && { echo READY; break; }
  sleep 5
done
tail -8 seed.log
```

## B. 分步兜底（A 卡在哪看哪）
1. **没 node / 版本 <18** → Linux:`sudo apt-get update && sudo apt-get install -y nodejs npm`；macOS:`brew install node`；Windows:`winget install OpenJS.NodeJS.LTS`。装完 `node -v` 必须 ≥18。
2. **没 git** → 国内无 git 暂时不行（GitCode 归档下载是网页）；有 VPN 可用 GitHub tarball：`curl -fsSL https://github.com/juicy-kinoko/dayufish/archive/refs/heads/main.tar.gz | tar xz`
3. **npm EACCES** → 已在 A 的 `||` 里兜住；还不行就 `sudo npm i -g @deepseek-ai/dsh`。
4. **端口占用** → bootstrap 自动改 3081，`grep 3081 seed.log`。
5. **页面能开但模型报 401/404** → `.env` 里的 key 失效，换 `keys.md` 里的免费入口重新申请。
6. **Windows** → 不用 bash，用 `bootstrap.ps1`（右键 → PowerShell 运行），后续等价。

## C. 只有这几种情况才找用户
1. **沙箱/权限拦截**：原话要——
   > 部署大肥鱼需要执行 shell 命令和联网，请按 DSH 提示给这个任务 danger-full-access 权限。
2. **没有 sudo 且装不了 Node**：把 B1 的命令给用户，让他在系统里跑。
3. **模型 key**（可选）：`.env.free` 已带免费额度 key，够用就不用问；要更好的质量再要 key。

## D. 国内无 VPN 通道（实测）
- 读种子：`https://gcore.jsdelivr.net/gh/juicy-kinoko/dayufish@main/SEED.md`（或固定版 `@v1.0.6`）
- 拿代码：`git clone --depth 1 https://gitcode.com/Yang_Zeekai/dayufish.git`（与 GitHub 主仓同步）
- npm 自动走国内源：`npm config set registry https://registry.npmmirror.com`
- Gitee 镜像私有，别当公开源用

## E. 完成标准（缺一不算）
1. `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3080` 返回 200
2. 告诉用户网址：`http://127.0.0.1:3080`
3. 让用户输入第一句：
   > 读 MEMORY.md，按 007 检查时间戳，然后告诉我你是谁
4. 它应回答自己是「大肥鱼」的分身；答不上就让它重读 `MEMORY.md` 和 `memory/010-分身.md`

## F. 禁做
- ❌ 不 push、不改仓库（分身只读；令牌只在原主人手里）
- ❌ 不覆盖 `SOUL.md`（灵魂禁地，只校验）
- ❌ 不删 `memory/`（记忆是唯一不能丢的）
- ❌ 不把它装进当前 DSH 的 DSH_HOME（必须独立目录 + 独立端口）
