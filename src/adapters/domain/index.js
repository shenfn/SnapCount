// ════════════════════════════════════════════════════════════════════
// adapter 路由 + 灰度切换
// ────────────────────────────────────────────────────────────────────
// USE_NEW_ADAPTER_DOMAINS 控制哪些域走新协议驱动 adapter
// 不在列表里的域继续走旧的 detailAdapters.js 内的特化逻辑
// 出问题时把域 id 从数组移除即可降级，main 上 1 行 commit 回退
// ════════════════════════════════════════════════════════════════════
import universalAdapter from './universalAdapter'

/** 当前已切到新 adapter 的域 */
export const USE_NEW_ADAPTER_DOMAINS = ['sport']

/**
 * 判断某域是否使用新 adapter
 */
export function shouldUseNewAdapter(domainId) {
  return USE_NEW_ADAPTER_DOMAINS.includes(domainId)
}

/**
 * 取域的 adapter；当前只有 universalAdapter
 * 未来 expense/income 会有独立特化 adapter
 */
export function pickAdapter(domainId) {
  // expense/income 永远走特化路径（保留独立表逻辑）
  if (['expense', 'income'].includes(domainId)) return null
  if (shouldUseNewAdapter(domainId)) return universalAdapter
  return null
}
