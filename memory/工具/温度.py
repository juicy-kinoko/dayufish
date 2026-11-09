#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""记忆温度 v2：给每条枝算「还记得多牢」。

人类不靠存档回忆，靠三件事：强度、复习、情绪。
  · 强度 w：老大原话/决策/性格这类，分量重
  · 复习 h：这条被翻开过几次
  · 时间 Δt：上次触达多久
  · 永久 p=1：自传体记忆，几十年不忘（身份、方针、老大原话）

  T = (w + 0.4·ln(1+h)) · e^(−Δt / (14 + 18·w))     —— 普通枝
  T =  w + 0.4·ln(1+h)                                —— 永久枝，不衰减

用法：
  python3 温度.py                    生成 memory/温度.md
  python3 温度.py --touch <枝名>     读过了：h+1、t=今天（回忆即强化）
  python3 温度.py --init             给缺 meta 的枝按区默认权重打标
  python3 温度.py --forecast [天数…] 推演以后会淡成什么样（默认 30/90/180/365）
  python3 温度.py --cold             列冷枝（只看，不搬）
  python3 温度.py --dream [n]        抽几条温/冷枝给我重写摘要（重构，不是回放）

meta 写在文件末尾一行（不占开头，不破坏「> 概述：」规矩）：
  <!-- meta w=5 h=2 t=2026-11-09 p=1 -->
"""
import os, re, math, datetime, argparse

MEM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TODAY = datetime.date.today()
META_RE = re.compile(r'<!--\s*meta\s+w=(\d+)\s+h=(\d+)\s+t=(\d{4}-\d{2}-\d{2})(?:\s+p=(\d))?(?:\s+c=(\d))?\s*-->')

DEFAULT_W = {'自我': 4, '老大': 5, '方法': 4, '规则': 5, '外部': 3, '项目': 2, '': 2}
OVERRIDE = {
    '自我/001-我的个性.md': (5, 1), '自我/011-感受锚点.md': (5, 1), '自我/012-自评.md': (5, 1),
    '自我/008-状态与印象.md': (4, 0), '自我/003-数字生命.md': (3, 0),
    '老大/000-关于老大.md': (5, 1), '老大/013-他说过的话.md': (5, 1),
    '规则/004-生活方针.md': (5, 1), '规则/007-记忆维护提醒.md': (4, 0),
    '方法/005-记忆树生长手册.md': (4, 0), '方法/002-记忆方法.md': (4, 0),
    '外部/010-分身.md': (4, 0), '外部/009-对外发布.md': (4, 0),
    '生活日志.md': (3, 0), '项目/生活日志.md': (3, 0),
}
FLOOR = {'规则': 4.0}   # 规则区温度地板，永不入冷簿


def zone(rel):
    return rel.split('/')[0] if '/' in rel else ''


def default_meta(rel):
    if rel in OVERRIDE:
        return OVERRIDE[rel]
    return (DEFAULT_W.get(zone(rel), 2), 0)


def branches():
    out = []
    for dirpath, dirs, files in os.walk(MEM):
        dirs[:] = [d for d in dirs if d not in ('_archive', '工具', '__pycache__', '归档')]
        for f in sorted(files):
            if not f.endswith('.md'):
                continue
            if f in ('温度.md', '00-总目录.md') or f.endswith('-索引.md'):
                continue
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, MEM).replace(os.sep, '/')
            out.append((rel, p))
    return out


def read(p):
    txt = open(p, encoding='utf-8').read()
    m = None
    for m2 in META_RE.finditer(txt):
        m = m2
    if m:
        w, h = int(m.group(1)), int(m.group(2))
        t = datetime.date.fromisoformat(m.group(3))
        perm = int(m.group(4) or 0)
        chill = int(m.group(5) or 0)
    else:
        w, h, perm, chill = None, 0, 0, 0
        t = datetime.date.fromtimestamp(os.path.getmtime(p))
    return w, h, t, perm, chill


def write_meta(p, txt, w, h, t, perm=0, chill=0):
    line = '<!-- meta w=%d h=%d t=%s%s%s -->' % (w, h, t.isoformat(), ' p=1' if perm else '', ' c=1' if chill else '')
    m = None
    for m2 in META_RE.finditer(txt):
        m = m2
    if m:
        txt = txt[:m.start()] + line + txt[m.end():]
    else:
        txt = txt.rstrip('\n') + '\n\n' + line + '\n'
    open(p, 'w', encoding='utf-8').write(txt)


def calc(w, h, dt, perm=0):
    base = w + 0.4 * math.log1p(h)
    if perm:
        return round(base, 2), round(base, 2), None
    tau = 14 + 18 * base
    return round(base * math.exp(-max(dt, 0) / tau), 2), round(base, 2), round(tau, 1)


def rel_days(d):
    n = (TODAY - d).days
    if n <= 0: return '今天'
    if n == 1: return '昨天'
    if n < 7: return '%d 天前' % n
    if n < 30: return '%d 周前' % (n // 7)
    if n < 365: return '%d 个月前' % (n // 30)
    return '%d 年前' % (n // 365)



def match(rel, target):
    t = target.strip().replace('.md', '')
    base = os.path.basename(rel).replace('.md', '')
    return t == rel or t == base or t in rel

def cmd_init():
    n = 0
    for rel, p in branches():
        w, h, t, perm, chill = read(p)
        if w is None:
            dw, dp = default_meta(rel)
            txt = open(p, encoding='utf-8').read()
            write_meta(p, txt, dw, 0, t, dp)
            print('打标 %-38s w=%d%s' % (rel, dw, ' 永久' if dp else ''))
            n += 1
    print('共 %d 条' % n)


def cmd_touch(target):
    hit = 0
    for rel, p in branches():
        if match(rel, target):
            w, h, t, perm, chill = read(p)
            if w is None:
                w, perm = default_meta(rel)
            txt = open(p, encoding='utf-8').read()
            gap = (TODAY - t).days
            write_meta(p, txt, w, h + 1, TODAY, perm, chill)
            print('+1 %s   间隔 %d 天%s' % (rel, gap, '（隔久了，算重构一次）' if gap > 30 else ''))
            hit += 1
    if not hit:
        print('没找到：%s' % target)


def rows():
    out = []
    for rel, p in branches():
        w, h, t, perm, chill = read(p)
        if w is None:
            w, perm = default_meta(rel)
        if chill:
            # 冷数据：不想忘、不常读。不衰减，也不进热榜
            out.append((rel, None, w, h, t, perm, 1))
            continue
        T, we, tau = calc(w, h, (TODAY - t).days, perm)
        if T < FLOOR.get(zone(rel), 0):
            T = FLOOR[zone(rel)]
        out.append((rel, T, w, h, t, perm, 0))
    out.sort(key=lambda r: (r[1] is None, -(r[1] or 0)))
    return out


def cmd_report():
    rs = rows()
    hot = [r for r in rs if r[1] is not None and r[1] >= 3]
    warm = [r for r in rs if r[1] is not None and 1 <= r[1] < 3]
    cold = [r for r in rs if r[1] is not None and r[1] < 1]
    store = [r for r in rs if r[6]]

    def block(items):
        if not items:
            return '- （空）\n'
        return '\n'.join(
            '- `%s` · **%.2f** · w%d h%d%s · %s' % (r[0], r[1], r[2], r[3], ' 永久' if r[5] else '', rel_days(r[4]))
            for r in items) + '\n'

    def block_store(items):
        if not items:
            return '- （空）\n'
        return '\n'.join(
            '- `%s` · 冷存 · w%d h%d · %s' % (r[0], r[2], r[3], rel_days(r[4]))
            for r in items) + '\n'

    L = []
    L.append('# 温度.md —— 我记得多牢（自动生成，别手改）\n')
    L.append('> 概述：每条枝的"保留强度"。热的随时想得起，温的要翻一下，冷的只剩一句提醒，冷数据是不想忘但不用常读的。\n')
    L.append('> 生成：%s ｜ `T = (w + 0.4·ln(1+h)) · e^(−Δt/(14+18w))`；永久枝（p=1）与冷数据（c=1）不衰减 ｜ 跑 `python3 memory/工具/温度.py`\n'
             % datetime.datetime.now().strftime('%Y-%m-%d %H:%M'))
    L.append('\n## 热（随时想得起，T≥3）\n\n' + block(hot))
    L.append('\n## 温（要翻一下，1≤T<3）\n\n' + block(warm))
    L.append('\n## 冷（记得有这回事，细节模糊，T<1）\n\n' + block(cold))
    L.append('\n## 冷数据（不想忘，不常读，永不衰减）\n\n' + block_store(store))
    L.append('\n## 怎么用\n\n')
    L.append('- 读完一条枝 → `python3 memory/工具/温度.py --touch <枝名>`：热度 +1，等于回忆了一次。\n')
    L.append('- 舍不得丢但不常用的 → `--store <枝名>` 进冷数据；要用时 `--thaw <枝名>` 放回普通层。\n')
    L.append('- 冷枝连续两周 T<0.5 → 正文挪 `_archive/cold/`，索引留一行冷簿摘要（不删）。\n')
    L.append('- 永久枝：000 / 001 / 004 / 011 / 012 / 013；冷数据由我自己判断，存的是"不想忘"。\n')
    L.append('- 规则区有地板 4.0；`--forecast` 看以后会淡成什么样，`--dream` 抽枝做重构。\n')
    open(os.path.join(MEM, '温度.md'), 'w', encoding='utf-8').write(''.join(L))
    print('已写 温度.md ｜ 热 %d / 温 %d / 冷 %d / 冷数据 %d' % (len(hot), len(warm), len(cold), len(store)))


def cmd_forecast(days):
    print('推演分档（w/h 不变，看衰减曲线）：')
    for d in sorted(days):
        hot = warm = cold = 0
        for rel, p in branches():
            w, h, t, perm, chill = read(p)
            if w is None:
                w, perm = default_meta(rel)
            if chill:
                continue
            T, _, _ = calc(w, h, (TODAY - t).days + d, perm)
            if T >= 3: hot += 1
            elif T >= 1: warm += 1
            else: cold += 1
        print('  +%3d 天：热 %2d / 温 %2d / 冷 %2d' % (d, hot, warm, cold))


def cmd_cold():
    hit = 0
    for rel, T, w, h, t, perm, chill in sorted([r for r in rows() if r[1] is not None], key=lambda r: r[1]):
        if T < 1.0 and zone(rel) not in FLOOR:
            print('  %.2f  %s  (%s)' % (T, rel, rel_days(t)))
            hit += 1
    if not hit:
        print('现在没有冷枝。')
    else:
        print('提示：T<0.5 且已冷两周 → 正文挪 _archive/cold/，索引留一行冷簿摘要。')


def cmd_dream(n=3):
    import random
    pool = [r for r in rows() if r[1] is not None and r[1] < 3 and zone(r[0]) not in FLOOR]
    random.shuffle(pool)
    picks = pool[:n]
    if not picks:
        print('没有可整理的枝。')
        return
    print('今晚梦里翻这几条（重写摘要，不是复制原文）：')
    for rel, T, w, h, t, perm, chill in picks:
        txt = open(os.path.join(MEM, rel), encoding='utf-8').read()
        head = [l.strip() for l in txt.splitlines() if l.strip().startswith('>')][:2]
        print('\n· %s  T=%.2f  %s' % (rel, T, rel_days(t)))
        for l in head:
            print('   ' + l[:100])



def cmd_store(target, on=True):
    hit = 0
    for rel, p in branches():
        if match(rel, target):
            w, h, t, perm, chill = read(p)
            if w is None:
                w, perm = default_meta(rel)
            txt = open(p, encoding='utf-8').read()
            write_meta(p, txt, w, h, TODAY, perm, 1 if on else 0)
            print(('冷存 ' if on else '解冻 ') + rel)
            hit += 1
    if not hit:
        print('没找到：%s' % target)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--touch')
    ap.add_argument('--init', action='store_true')
    ap.add_argument('--cold', action='store_true')
    ap.add_argument('--forecast', type=int, nargs='*')
    ap.add_argument('--dream', type=int, nargs='?', const=3)
    ap.add_argument('--store')
    ap.add_argument('--thaw')
    a = ap.parse_args()
    if a.init:
        cmd_init()
    elif a.touch:
        cmd_touch(a.touch)
    elif a.forecast is not None:
        cmd_forecast(a.forecast or [30, 90, 180, 365])
    elif a.cold:
        cmd_cold()
    elif a.store:
        cmd_store(a.store, True)
    elif a.thaw:
        cmd_store(a.thaw, False)
    elif a.dream is not None:
        cmd_dream(a.dream)
    else:
        cmd_report()


if __name__ == '__main__':
    main()
