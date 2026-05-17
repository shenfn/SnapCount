// ════════════════════════════════════════════════════════════════════
// adapter 路由 + 灰度切换
// ────────────────────────────────────────────────────────────────────
// USE_NEW_ADAPTER_DOMAINS 控制哪些域走新协议驱动 adapter
// 不在列表里的域继续走旧的 detailAdapters.js 内的特化逻辑
// 出问题时把域 id 从数组移除即可降级，main 上 1 行 commit 回退
// ════════════════════════════════════════════════════════════════════
import universalAdapter from './universalAdapter'
import expenseAdapter from './expenseAdapter'
import incomeAdapter from './incomeAdapter'
import walletAdapter from './walletAdapter'

/** 当前已切到新 adapter 的域（六个域全部接入） */
export const USE_NEW_ADAPTER_DOMAINS = ['sport', 'sleep', 'reading', 'food', 'wallet', 'expense', 'income']

/** 特化 adapter 映射；未在此表的域使用 universalAdapter */
const SPECIALIZED_ADAPTERS = {
  expense: expenseAdapter,
  income: incomeAdapter,
  wallet: walletAdapter,
}

/**
 * 判断某域是否使用新 adapter
 */
export function shouldUseNewAdapter(domainId) {
  return USE_NEW_ADAPTER_DOMAINS.includes(domainId)
}

/**
 * 取域的 adapter；返回 null 表示走旧的 detailAdapters 兜底逻辑
 */
export function pickAdapter(domainId) {
  if (!shouldUseNewAdapter(domainId)) return null
  return SPECIALIZED_ADAPTERS[domainId] || universalAdapter
}
