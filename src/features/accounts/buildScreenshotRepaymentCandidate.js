const OPEN_STATUSES = new Set(['pending', 'due_today', 'overdue_unconfirmed', 'partial_paid', 'minimum_paid', 'carried_over'])
const LIABILITY_TYPES = new Set(['credit_card', 'credit_line', 'huabei', 'jd_baitiao', 'douyin_monthly'])

function normalize(value) {
  return String(value || '').trim().toLowerCase().replace(/\s+/g, '')
}

function daysBetween(left, right) {
  const parse = value => {
    const match = String(value || '').slice(0, 10).match(/^(\d{4})-(\d{2})-(\d{2})$/)
    return match ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : null
  }
  const a = parse(left)
  const b = parse(right)
  return a == null || b == null ? 999 : Math.round((a - b) / 86400000)
}

function compareCandidates(left, right) {
  if (right.score !== left.score) return right.score - left.score
  const due = String(left.cycle.dueDate || '9999-99-99').localeCompare(String(right.cycle.dueDate || '9999-99-99'))
  if (due) return due
  const month = String(left.cycle.cycleMonth || '').localeCompare(String(right.cycle.cycleMonth || ''))
  return month || String(left.cycle.id || '').localeCompare(String(right.cycle.id || ''))
}

export function buildScreenshotRepaymentCandidate(record, accounts = [], cycles = []) {
  const extracted = record?.extracted && typeof record.extracted === 'object' ? record.extracted : {}
  const payload = extracted.payload_jsonb && typeof extracted.payload_jsonb === 'object' ? extracted.payload_jsonb : extracted
  const domainKey = record?.domainKey || extracted.domain_key
  const isLiability = payload.record_kind === 'liability_snapshot' || payload.account_snapshot_kind === 'liability'
  if (domainKey !== 'wallet' || !isLiability || payload.status !== 'paid') return null

  const extractedAmount = Number(extracted.amount ?? payload.amount ?? payload.snapshot_balance)
  const hasAmount = Number.isFinite(extractedAmount) && extractedAmount > 0
  const accountText = normalize([
    payload.account_name,
    payload.institution,
    extracted.title,
    extracted.summary,
    record?.summary,
  ].filter(Boolean).join(' '))

  return cycles
    .filter(cycle => OPEN_STATUSES.has(cycle.status))
    .map(cycle => {
      const account = accounts.find(item => item.id === cycle.accountId && !item.isArchived && LIABILITY_TYPES.has(item.type))
      if (!account) return null
      const accountName = normalize(`${account.name || ''} ${account.institution || ''}`)
      const remaining = Number(cycle.remainingAmount) > 0 ? Number(cycle.remainingAmount) : Number(cycle.statementAmount || 0)
      const amount = hasAmount ? extractedAmount : remaining
      if (!(amount > 0)) return null

      let score = 0.35
      const reasons = []
      if (accountText && accountName && (accountText.includes(accountName) || accountName.includes(accountText))) {
        score += 0.28
        reasons.push(`账户匹配「${account.name}」`)
      } else if (accountText && accountName && [...accountText].some(char => accountName.includes(char))) {
        score += 0.1
        reasons.push('账户名称部分匹配')
      }
      if (hasAmount) {
        const difference = Math.abs(extractedAmount - remaining)
        if (difference < 0.01) {
          score += 0.32
          reasons.push('金额与剩余待还一致')
        } else if (difference <= 5) {
          score += 0.18
          reasons.push(`金额相差 ¥${difference.toFixed(2)}`)
        }
      }
      if (cycle.dueDate && record?.occurredAt && Math.abs(daysBetween(record.occurredAt, cycle.dueDate)) <= 3) {
        score += 0.15
        reasons.push('还款时间接近还款日')
      }
      return {
        cycle,
        account,
        amount,
        score: Math.min(score, 0.99),
        reason: reasons.length ? reasons.join('；') : '识别为已还款截图，需人工确认',
      }
    })
    .filter(candidate => candidate && candidate.score >= 0.55)
    .sort(compareCandidates)[0] || null
}
