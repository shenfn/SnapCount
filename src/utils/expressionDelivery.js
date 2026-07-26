export function createAbortError() {
  const error = new Error('操作已取消')
  error.name = 'AbortError'
  return error
}

export function isAbortError(error) {
  return error?.name === 'AbortError'
}

function throwIfAborted(signal) {
  if (signal?.aborted) throw createAbortError()
}

export function waitForDelay(delayMs, signal) {
  throwIfAborted(signal)
  return new Promise((resolve, reject) => {
    const timer = setTimeout(finish, Math.max(0, Number(delayMs) || 0))

    function cleanup() {
      clearTimeout(timer)
      signal?.removeEventListener('abort', handleAbort)
    }

    function finish() {
      cleanup()
      resolve()
    }

    function handleAbort() {
      cleanup()
      reject(createAbortError())
    }

    signal?.addEventListener('abort', handleAbort, { once: true })
    if (signal?.aborted) handleAbort()
  })
}

export async function retryWithBackoff(operation, {
  delays = [],
  shouldRetryResult = () => false,
  shouldRetryError = () => false,
  signal,
  onRetry,
} = {}) {
  for (let attempt = 0; ; attempt += 1) {
    throwIfAborted(signal)
    try {
      const result = await operation({ attempt, signal })
      throwIfAborted(signal)
      if (!shouldRetryResult(result, attempt) || attempt >= delays.length) return result
      onRetry?.({ attempt, result })
    } catch (error) {
      if (isAbortError(error) || signal?.aborted) throw createAbortError()
      if (!shouldRetryError(error, attempt) || attempt >= delays.length) throw error
      onRetry?.({ attempt, error })
    }
    await waitForDelay(delays[attempt], signal)
  }
}

export function waitForVisibleElement(element, {
  signal,
  documentRef = globalThis.document,
  IntersectionObserverCtor = globalThis.IntersectionObserver,
  minimumRatio = 0.01,
} = {}) {
  throwIfAborted(signal)
  if (!element) return Promise.reject(new Error('找不到待确认的反馈卡片'))
  if (!documentRef || typeof IntersectionObserverCtor !== 'function') {
    return Promise.reject(new Error('当前环境无法确认反馈卡片是否可见'))
  }

  return new Promise((resolve, reject) => {
    let intersecting = false
    let settled = false
    const observer = new IntersectionObserverCtor((entries) => {
      const entry = entries.find(item => item.target === element) || entries[0]
      intersecting = Boolean(entry?.isIntersecting && Number(entry.intersectionRatio || 0) >= minimumRatio)
      resolveWhenVisible()
    }, { threshold: [0, minimumRatio] })

    function cleanup() {
      observer.disconnect()
      documentRef.removeEventListener('visibilitychange', resolveWhenVisible)
      signal?.removeEventListener('abort', handleAbort)
    }

    function settle(callback, value) {
      if (settled) return
      settled = true
      cleanup()
      callback(value)
    }

    function resolveWhenVisible() {
      if (intersecting && documentRef.visibilityState === 'visible') settle(resolve)
    }

    function handleAbort() {
      settle(reject, createAbortError())
    }

    documentRef.addEventListener('visibilitychange', resolveWhenVisible)
    signal?.addEventListener('abort', handleAbort, { once: true })
    observer.observe(element)
    if (signal?.aborted) handleAbort()
  })
}
