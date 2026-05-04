import { ref, onMounted, onBeforeUnmount } from 'vue'

/**
 * 下拉刷新 composable
 *
 * @param {Object} opts
 * @param {Function} opts.onRefresh - 触发刷新时调用（可以返回 Promise）
 * @param {Ref<HTMLElement>} [opts.target] - 监听的容器 ref（默认为 window）
 * @param {number} [opts.threshold=60] - 触发刷新的下拉距离（px）
 * @param {number} [opts.maxPull=120] - 最大下拉距离（px）
 */
export function usePullToRefresh({ onRefresh, target = null, threshold = 60, maxPull = 120 } = {}) {
  const pullDistance = ref(0)
  const refreshing = ref(false)
  const ptrActive = ref(false)

  let startY = 0
  let startScrollTop = 0
  let dragging = false

  function getScrollTop() {
    if (target?.value) return target.value.scrollTop
    return window.scrollY || document.documentElement.scrollTop || 0
  }

  function onTouchStart(e) {
    if (refreshing.value) return
    if (getScrollTop() > 0) {
      dragging = false
      return
    }
    startY = e.touches[0].clientY
    startScrollTop = getScrollTop()
    dragging = true
    ptrActive.value = false
  }

  function onTouchMove(e) {
    if (!dragging || refreshing.value) return
    const dy = e.touches[0].clientY - startY
    // 仅处理向下拉（dy > 0）
    if (dy <= 0) {
      pullDistance.value = 0
      ptrActive.value = false
      return
    }
    // 如果用户在滚动过程中滚到了顶再往下拉，也接住
    if (getScrollTop() > 0) {
      dragging = false
      pullDistance.value = 0
      return
    }
    // 阻尼效果：越拉越慢
    const resistance = 0.5
    const pulled = Math.min(dy * resistance, maxPull)
    pullDistance.value = pulled
    ptrActive.value = pulled > 0
    // 阻止浏览器自带的下拉刷新（iOS Safari）
    if (pulled > 5 && e.cancelable) {
      e.preventDefault()
    }
  }

  async function onTouchEnd() {
    if (!dragging) return
    dragging = false
    const reached = pullDistance.value >= threshold
    if (reached && !refreshing.value) {
      refreshing.value = true
      pullDistance.value = threshold
      try {
        await onRefresh?.()
      } catch (e) {
        console.warn('[PullToRefresh] onRefresh failed:', e)
      } finally {
        refreshing.value = false
        pullDistance.value = 0
        ptrActive.value = false
      }
    } else {
      pullDistance.value = 0
      ptrActive.value = false
    }
  }

  onMounted(() => {
    const el = target?.value || window
    el.addEventListener('touchstart', onTouchStart, { passive: true })
    el.addEventListener('touchmove', onTouchMove, { passive: false })
    el.addEventListener('touchend', onTouchEnd, { passive: true })
    el.addEventListener('touchcancel', onTouchEnd, { passive: true })
  })

  onBeforeUnmount(() => {
    const el = target?.value || window
    el.removeEventListener('touchstart', onTouchStart)
    el.removeEventListener('touchmove', onTouchMove)
    el.removeEventListener('touchend', onTouchEnd)
    el.removeEventListener('touchcancel', onTouchEnd)
  })

  return { pullDistance, refreshing, ptrActive }
}
