// ════════════════════════════════════════════════════════════════════
// 成熟度档位（Maturity Stages）
// ────────────────────────────────────────────────────────────────────
// 一个数据集（单个域 / 整体）根据"有数据的天数"被划分为 5 档：
//   seed    < 3 天   —— 记录陪伴者：只描述、鼓励
//   sprout  3-6 天   —— 初步形态：能看到极值，不下结论
//   growing 7-13 天  —— 显现趋势：能描述模式，不做关联推断
//   mature  14-29 天 —— 可见关联：可做跨域关联的"观察"
//   rich    30+ 天   —— 个人基准线：可给出具体行动建议
// ────────────────────────────────────────────────────────────────────
// 前端用：进度条、图表分档渲染、洞察口吻
// 后端用：注入 prompt，让 AI 按成熟度档位调整输出
// ════════════════════════════════════════════════════════════════════

export const MATURITY_STAGES = [
  { key: 'seed',    label: '萌芽',    minDays: 0,  nextTarget: 3,  tone: '陪伴', desc: '刚开始记录，还在描绘你的轮廓' },
  { key: 'sprout',  label: '抽芽',    minDays: 3,  nextTarget: 7,  tone: '观察', desc: '已能看到极值和异常' },
  { key: 'growing', label: '成长',    minDays: 7,  nextTarget: 14, tone: '描述', desc: '趋势正在显现' },
  { key: 'mature',  label: '成熟',    minDays: 14, nextTarget: 30, tone: '关联', desc: '可以看到跨域关联' },
  { key: 'rich',    label: '丰盈',    minDays: 30, nextTarget: null, tone: '基准', desc: '已有个人化基准线' },
]

/** 根据"有数据天数"返回对应档位定义 */
export function getMaturity(daysWithData) {
  const n = Math.max(0, Math.floor(Number(daysWithData) || 0))
  let stage = MATURITY_STAGES[0]
  for (const s of MATURITY_STAGES) {
    if (n >= s.minDays) stage = s
    else break
  }
  const remainingToNext = stage.nextTarget ? Math.max(0, stage.nextTarget - n) : 0
  return {
    ...stage,
    days: n,
    remainingToNext,
    isMax: !stage.nextTarget,
  }
}

/** 给单个域生成「解锁文案」 */
export function getMaturityHint(domainLabel, daysWithData) {
  const m = getMaturity(daysWithData)
  if (m.isMax) return `${domainLabel}已积累 ${m.days} 天数据，达到丰盈档`
  if (m.days === 0) return `${domainLabel}尚未开始记录`
  if (m.days < m.nextTarget) return `已记录 ${m.days} 天 · 再记 ${m.remainingToNext} 天解锁「${nextStageLabel(m)}」`
  return `已记录 ${m.days} 天`
}

function nextStageLabel(m) {
  const idx = MATURITY_STAGES.findIndex(s => s.key === m.key)
  return MATURITY_STAGES[idx + 1]?.label || m.label
}

/** 图表渲染档位：用于 UI 决定是否画图、浅色还是实色 */
export function getRenderTier(daysWithData) {
  const n = Math.max(0, Math.floor(Number(daysWithData) || 0))
  if (n < 3) return 'placeholder' // 占位插画
  if (n < 7) return 'light'       // 浅色淡化
  return 'solid'                  // 实色完整
}
