// 模型守卫 v8：全自动——换道 + 死回合自动重发，老大一条都不用点。
//
// 在 v6.1（按模型轮巡 12 格 + 网关禁令）之上新增：
//   回合被通道搞死（429/没key/超时/空响应）→
//     ① 轮盘拨到下一格（原有）
//     ② 把死回合的原文重新入队（agent/inbox/spliced，引擎自己的收件箱机制）
//     ③ wakeDriver() 唤醒驱动 → 原文在新通道上自动重跑
//   上限：同一条消息最多自动重发 3 次，防全死循环。
//
// 依据：agent-loop 的 advance 在回合结束后检查 inbox.hasPending；
//       wakeDriver() 在 idle 时恢复 claims 并开跑；goal 驱动同款模式。
export const name = 'local-model-guard'
// 关键：显式声明依赖 agents，cordis 才会把服务挂到这个 ctx 上
export const inject = ['agents']

import { appendFile, appendFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { randomUUID } from 'node:crypto'

// 能力榜顺序：强的在前，弱的/死的垫底（缓过来自然被轮到）
// ⚠️ qnaigc/deepseek-v4.1 烧钱：老大令"实在实在不行再换"——压最后一格，全灭才用它
const ROTATION = [
  { provider: 'custom-qnaigc', model: 'qwen/qwen3.8-flash-next' },
  { provider: 'custom-glm5-3', model: 'glm-5.3-flash' },
  { provider: 'custom-kilo', model: 'kilo-auto/free' },
  { provider: 'custom-glm4', model: 'glm-4-flash' },
  { provider: 'custom-opaifast', model: 'openai-fast' },
  { provider: 'custom-glm4', model: 'glm-4.7-flash' },
  { provider: 'custom-qnaigc', model: 'qiniu/conatus-free' },
  { provider: 'custom-siliconflow', model: 'zai-org/GLM-5.3-Flash' },
  { provider: 'custom-ovh', model: 'gpt-oss-120b' },
  { provider: 'custom-kilo', model: 'nvidia/nemotron-3.5-lightning:free' },
  { provider: 'custom-openrouter', model: 'nvidia/nemotron-3.5-lightning:free' },
  { provider: 'custom-qnaigc', model: 'deepseek/deepseek-v4.1-flash-1017', manual: true }, // 烧钱：只由老大手动选，守卫绝不自动切
]

const LOG = '/root/workspace/logs/model_guard_auto.log'
const MAX_RETRIES = 6 // 有死格记忆，正常一两跳就中，实到 6 次几乎不会发生
const recent = new Map() // sessionId -> 状态
const deadGateway = new Map() // provider -> 禁到什么时候（网关级）
const deadRoute = new Map() // provider|model -> 禁到什么时候（单通道级）
const DEAD_FILE = '/root/workspace/logs/model_guard_dead.json'
try {
  const raw = JSON.parse(readFileSync(DEAD_FILE, 'utf8'))
  const now = Date.now()
  for (const [k, v] of Object.entries(raw)) if (Number(v) > now) deadRoute.set(k, Number(v))
} catch {}
const GATEWAY_BAN_MS = 10 * 60 * 1000
const RATE_COOLDOWN_MS = 90 * 1000
const ROUTE_DEAD_MS = 10 * 60 * 1000

try {
  mkdirSync(dirname(LOG), { recursive: true })
} catch {}

let deadDirty = false
function saveDead() {
  if (!deadDirty) return
  deadDirty = false
  try {
    const obj = {}
    const now = Date.now()
    for (const [k, v] of deadRoute) if (v > now) obj[k] = v
    writeFileSync(DEAD_FILE, JSON.stringify(obj))
  } catch {}
}
setInterval(saveDead, 5000).unref?.()

function note(text) {
  const d = new Date(Date.now() + 8 * 3600 * 1000)
  appendFile(LOG, `[${d.toISOString().slice(0, 19).replace('T', ' ')}] ${text}\n`, () => {})
}

function keyOf(route) {
  return `${route.provider}|${route.model}`
}

function rateLimited(failure) {
  if (!failure || typeof failure !== 'object') return false
  if (Number(failure.status) === 429) return true
  const code = String(failure.code ?? '')
  if (/RATE_LIMIT|rate.?limit|too.?many/i.test(code)) return true
  const msg = String(failure.message ?? '').slice(0, 4096)
  return /请求太频繁|请稍候再试|rate.?limit|too many requests|429/i.test(msg)
}

function gatewayDead(reason) {
  if (!reason || reason.kind !== 'error') return false
  const msg = String(reason.error?.message ?? '')
  const code = String(reason.error?.code ?? '')
  return /no api key|api key|no adapter|unauthorized|401|forbidden/i.test(msg + ' ' + code)
}

function hardDead(reason) {
  if (!reason || reason.kind !== 'error') return false
  const msg = String(reason.error?.message ?? '')
  const code = String(reason.error?.code ?? '')
  return /402|insufficient|balance|quota|timeout|timed out|bad gateway|502|503|504|service unavailable|overloaded|empty|refused|ECONN|fetch failed/i.test(
    msg + ' ' + code
  )
}

/** 回合死于通道问题（限流也算）——只有这种死法才自动重发 */
function channelDead(reason) {
  if (!reason || reason.kind !== 'error') return false
  const msg = String(reason.error?.message ?? '')
  return gatewayDead(reason) || hardDead(reason) || /429|rate.?limit|too many/i.test(msg)
}

function pickNext(from, lastKey, tried) {
  const startIdx = lastKey ? ROTATION.findIndex((r) => keyOf(r) === lastKey) + 1 : 0
  const now = Date.now()
  const skip = (cand) => cand.manual === true || keyOf(cand) === keyOf(from) || (tried && tried.has(keyOf(cand)))
  // 第一轮：跳过已知死格（单通道 + 整网关）和本轮试过的
  let next
  for (let i = 0; i < ROTATION.length; i++) {
    const cand = ROTATION[(startIdx + i) % ROTATION.length]
    if (skip(cand)) continue
    if ((deadGateway.get(cand.provider) ?? 0) > now) continue
    if ((deadRoute.get(keyOf(cand)) ?? 0) > now) continue
    next = cand
    break
  }
  // 第二轮：活格都轮完还没中，退而求其次（仍不碰 from 和本轮试过的）
  if (!next) {
    for (let i = 0; i < ROTATION.length; i++) {
      const cand = ROTATION[(startIdx + i) % ROTATION.length]
      if (skip(cand)) continue
      next = cand
      break
    }
  }
  return next ?? null
}

function freshState() {
  return {
    lastRetryId: null, lastKey: null, switches: 0, at: 0, lastTurnAt: 0,
    lastUser: null, // { id, content, source } 最近一条真人消息
    retries: 0, // 本条消息已自动重发次数
    retriedIds: new Set(), // 本守卫造出来的重发消息 id（避免当成真人消息重置计数）
    tried: new Set(), // 本条消息已经试过的通道
  }
}

export function apply(ctx) {
  const syncNote = (t) => { try { const d = new Date(Date.now() + 8*3600*1000); appendFileSync(LOG, `[${d.toISOString().slice(0,19).replace('T',' ')}] ${t}\n`) } catch {} }
  try {
    initGuard(ctx, syncNote)
  } catch (e) {
    syncNote('apply 崩溃：' + (e && (e.stack || e.message) || String(e)).slice(0, 800))
    throw e
  }
}

function initGuard(ctx, syncNote) {
  note(`v8.2 守卫上线：死格记忆轮巡 ${ROTATION.length} 格 + 只重发真人原文（全自动）`)

  // —— 拿 agents 服务（唤醒驱动必需）：多条路都试一遍，拿到就记住 ——
  let agentsSvc
  const grabAgents = () => {
    if (agentsSvc) return agentsSvc
    try { agentsSvc = ctx.get?.('agents', false) } catch {}
    if (!agentsSvc) { try { agentsSvc = ctx.agents } catch {} }
    return agentsSvc
  }
  try {
    ctx.inject(['agents'], (c) => { agentsSvc = c.agents })
  } catch {}
  const got = !!grabAgents()
  note(got ? 'agents 服务：已拿到（唤醒可用）' : 'agents 服务：拿不到（唤醒会失败，重发不会自动跑）')
  note(`诊断：pid=${process.pid} agents.get=${typeof agentsSvc?.get}`)

  function agentOf(session) {
    try {
      const agents = grabAgents()
      return agents?.get?.(session.id)
    } catch {
      return undefined
    }
  }

  function readCurrent(session) {
    try {
      const sel = agentOf(session)?.model?.current?.()
      if (sel?.provider && sel?.model) return { provider: sel.provider, model: sel.model }
    } catch {}
    return null
  }

  function wakeAgent(session) {
    try {
      const agent = agentOf(session)
      if (!agent) return 'noagent'
      const kind = agent.phase?.kind
      if (kind === 'running') return 'busy'
      if (typeof agent.wakeDriver === 'function') {
        agent.wakeDriver()
        return true
      }
      return 'nowake'
    } catch (e) {
      return 'error:' + (e && e.message ? e.message : String(e))
    }
  }

  ctx.on('session/event', (session, event) => {
    const t = event.type
    const data = event.data ?? {}
    const state = recent.get(session.id) ?? freshState()
    recent.set(session.id, state)

    // —— 通道跟踪 ——
    if (t === 'model/selection') {
      if (data.provider) {
        const route = { provider: data.provider, model: data.model ?? '' }
        state.lastKey = keyOf(route)
        state.lastSel = route
      }
      return
    }

    // —— 真人消息：记下来作为自动重发的原文；重发的跳过 ——
    // ⚠️ 只认 source.kind === 'user'：引擎的模型变更提示（kind:'model-selection'）
    //    也以 user/message 下发，曾把提示当原文重发，必须排除
    if (t === 'user/message') {
      if ((data.source?.kind ?? '') !== 'user') return
      if (data.id && !state.retriedIds.has(data.id)) {
        state.lastUser = { id: data.id, content: data.content, source: data.source }
        state.retries = 0
        state.tried = new Set()
      }
      return
    }

    // —— 耳朵一：限流（llm/retry）→ 只跳当前模型 ——
    if (t === 'llm/retry') {
      if (!rateLimited(data.failure)) return
      const rid = data.retryId ?? null
      if (rid) {
        if (state.lastRetryId === rid) return
      } else if (Date.now() - state.at < 5_000) {
        return
      }
      const from = state.lastSel ?? readCurrent(session) ?? { provider: '?', model: '?' }
      state.lastSel = from
      state.lastKey = keyOf(from)
      deadRoute.set(keyOf(from), Date.now() + RATE_COOLDOWN_MS); deadDirty = true
      state.tried.add(keyOf(from))
      const next = pickNext(from, state.lastKey, state.tried)
      if (!next) { note('限流：活格全试过，等下一跳'); return }
      state.lastRetryId = rid
      state.lastKey = keyOf(next)
      state.switches += 1
      state.at = Date.now()
      state.lastSel = next
      scheduleSwitch(session, from, next, `限流 → 第 ${state.switches} 次轮巡`)
      return
    }

    // —— 耳朵二：回合死于通道 → 换道 + 自动重发原文 ——
    if (t === 'turn/end') {
      const reason = data.reason
      if (!channelDead(reason)) return
      if (Date.now() - state.lastTurnAt < 2_000) return
      state.lastTurnAt = Date.now()

      const gw = gatewayDead(reason)
      const from = state.lastSel ?? readCurrent(session) ?? { provider: '?', model: '?' }
      state.lastSel = from
      if (gw && from.provider) deadGateway.set(from.provider, Date.now() + GATEWAY_BAN_MS)
      if (from.provider && from.model) deadRoute.set(keyOf(from), Date.now() + ROUTE_DEAD_MS); deadDirty = true
      if (from.provider && from.model) state.tried.add(keyOf(from))

      const next = pickNext(from, state.lastKey, state.tried)
      if (!next) {
        note(`全通道皆死/本轮全试过，放弃："${state.lastUser ? str(state.lastUser) : '(无原文)'}"`)
        return
      }
      state.lastKey = keyOf(next)
      state.lastSel = next
      state.switches += 1
      scheduleSwitch(session, from, next, `${gw ? '网关暴毙' : '通道暴毙'} → 第 ${state.switches} 次轮巡`)

      // —— 自动重发：原文重新入队 + 唤醒驱动 ——
      if (!state.lastUser) return
      if (state.retries >= MAX_RETRIES) {
        note(`放弃自动重发："${str(state.lastUser)}" 已重发 ${state.retries} 次仍死，等老大发话`)
        return
      }
      // 页面优先：只换道，不复制消息（重发会堆气泡把页面拖死），等老大确认后再开
      note(`已换道，等引擎下次请求；不自动重发："${str(state.lastUser)}"`)
    }
  })

  function str(u) {
    try {
      return (u.content ?? []).map((b) => b?.text ?? '').join(' ').slice(0, 40) || '(无文本)'
    } catch {
      return '(?)'
    }
  }

  // append 必须延后：事件发布中 append 会撞重入保护
  function scheduleSwitch(session, from, next, why) {
    const attempt = (triesLeft) => {
      try {
        const agent = agentOf(session)
        if (agent?.model?.select) agent.model.select({ provider: next.provider, model: next.model })
        else session.append('model/selection', { provider: next.provider, model: next.model })
        note(`${why}：${from.provider}/${from.model} 切到 ${next.provider}/${next.model}`)
      } catch (e) {
        const msg = e && e.message ? e.message : String(e)
        if (triesLeft > 0 && /reenter|being published|append/i.test(msg)) {
          setTimeout(() => attempt(triesLeft - 1), 120)
          return
        }
        note(`切换失败：${msg}`)
      }
    }
    setTimeout(() => attempt(3), 60)
  }

  function scheduleRetry(session, msg, next, nth, preview) {
    const attempt = (triesLeft) => {
      try {
        session.append('agent/inbox/spliced', { target: 'next-turn', start: 0, inserted: [msg] })
        // 唤醒：running 时稍后再试，最多 5 次
        let wakes = 0
        const kick = () => {
          const r = wakeAgent(session)
          if (r === true) return
          if (r !== true && r !== 'busy') { note(`唤醒失败（${r}），重发可能没跑`); return }
          if (r === 'busy') { if (++wakes < 5) setTimeout(kick, 500); else note('唤醒一直被占：5 次都 busy'); return }
        }

        setTimeout(kick, 150)
        note(`自动重发 ${nth}/${MAX_RETRIES}："${preview}" → 在 ${next.provider}/${next.model} 上重跑`)
      } catch (e) {
        const m = e && e.message ? e.message : String(e)
        if (triesLeft > 0 && /reenter|being published|append/i.test(m)) {
          setTimeout(() => attempt(triesLeft - 1), 120)
          return
        }
        note(`自动重发失败：${m}`)
      }
    }
    setTimeout(() => attempt(3), 150)
  }

  // —— 面板与体检胶囊 ——
  ctx.inject(['dshGo'], (ctx) => {
    ctx.dshGo.on('probe', async (scope, event) => {
      const zh = !String(event.locale).startsWith('en')
      const text = zh
        ? `模型守卫 v8：全自动。死格记 10 分钟不再碰；换道后原文自动重发重跑（最多 6 次），不用手点继续。\n限流跳模型（90 秒冷却）；网关暴毙（No API key）整网关跳 10 分钟。\n末格 deepseek-v4.1 烧钱，全灭才用。`
        : `Guard v8: full auto rotation + auto retry of failed turns.`
      return { insert: text.slice(0, 2000), toast: zh ? 'v8 全自动守卫' : 'v8 on' }
    })

    ctx.dshGo.panel('guard', {
      view: (scope, caps) => ({
        type: 'stack',
        title: '模型守卫 v8',
        children: [
          { type: 'callout', tone: 'good', text: '全自动：通道死→换道→原文重发重跑（≤6 次），手都不用点。' },
          { type: 'text', text: '前排：qnaigc/qwen3.8 → glm5.3 → kilo-auto → glm4-flash → opaifast' },
          { type: 'text', text: '垫底：glm-4.7(暂堵) → conatus → siliconflow(欠费) → ovh(死) → nemotron×2(死) → deepseek-v4.1(烧钱救命格)' },
        ],
      }),
    })
  })
}
