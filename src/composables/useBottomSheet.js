import { ref, watch, onUnmounted } from 'vue'

export function useBottomSheet(isOpen, close, options = {}) {
  const sheetEl = ref(null)
  const bodyEl = ref(null)
  const showUnsaved = ref(false)
  const isSwiping = ref(false)
  const isClosing = ref(false)
  const swipeDir = ref(null)

  let touchStartY = 0
  let touchStartX = 0
  let touchStartTime = 0
  let bodyScrollY = 0
  let originalBodyOverflow = ''
  let originalBodyPosition = ''
  let originalBodyTop = ''
  let originalBodyWidth = ''

  const hasChanges = options.hasChanges || (() => false)
  const resetChanges = options.resetChanges || (() => {})

  function lockBodyScroll() {
    bodyScrollY = window.scrollY
    originalBodyOverflow = document.body.style.overflow
    originalBodyPosition = document.body.style.position
    originalBodyTop = document.body.style.top
    originalBodyWidth = document.body.style.width
    document.body.style.overflow = 'hidden'
    document.body.style.position = 'fixed'
    document.body.style.top = `-${bodyScrollY}px`
    document.body.style.width = '100%'
  }

  function unlockBodyScroll() {
    document.body.style.overflow = originalBodyOverflow
    document.body.style.position = originalBodyPosition
    document.body.style.top = originalBodyTop
    document.body.style.width = originalBodyWidth
    window.scrollTo(0, bodyScrollY)
  }

  watch(isOpen, open => {
    if (open) { lockBodyScroll(); showUnsaved.value = false }
    else unlockBodyScroll()
  })

  onUnmounted(unlockBodyScroll)

  function isScrollAtTop() {
    if (!bodyEl.value) return true
    return bodyEl.value.scrollTop <= 1
  }

  function isInteractiveTarget(target) {
    return !!target.closest('input, button, img, .sel-chip, .thumb-wrap, .confirm-btn, .delete-bill-btn, .unsaved-bar, .seg-control')
  }

  function tryClose() {
    if (hasChanges()) {
      showUnsaved.value = true
      return
    }
    close()
  }

  function doForceClose() {
    showUnsaved.value = false
    resetChanges()
    close()
  }

  function animateClose(direction) {
    if (!sheetEl.value) return
    isClosing.value = true
    swipeDir.value = direction
    sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
    sheetEl.value.style.transform = 'translateY(110%)'
    setTimeout(() => {
      if (hasChanges()) {
        showUnsaved.value = true
        sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
        sheetEl.value.style.transform = ''
        isClosing.value = false
        swipeDir.value = null
      } else {
        close()
        if (sheetEl.value) {
          sheetEl.value.style.transition = ''
          sheetEl.value.style.transform = ''
        }
        isClosing.value = false
        swipeDir.value = null
      }
    }, 280)
  }

  function onTouchStart(e) {
    if (!isInteractiveTarget(e.target)) showUnsaved.value = false
    isSwiping.value = false
    isClosing.value = false
    swipeDir.value = null
    touchStartY = e.touches[0].clientY
    touchStartX = e.touches[0].clientX
    touchStartTime = Date.now()
    if (sheetEl.value) sheetEl.value.style.transition = 'none'
  }

  function onTouchMove(e) {
    if (isClosing.value) return
    const deltaY = e.touches[0].clientY - touchStartY
    const absY = Math.abs(deltaY)
    if (absY < 8) return

    if (deltaY > 0) {
      if (!isScrollAtTop()) return
      if (isInteractiveTarget(e.target)) return
      e.preventDefault()
      isSwiping.value = true
      swipeDir.value = 'down'
      if (sheetEl.value) sheetEl.value.style.transform = `translateY(${Math.min(deltaY, window.innerHeight * 0.5)}px)`
    }
  }

  function onTouchEnd(e) {
    if (!isSwiping.value || !sheetEl.value) {
      isSwiping.value = false
      swipeDir.value = null
      return
    }

    if (swipeDir.value === 'down') {
      const deltaY = e.changedTouches[0].clientY - touchStartY
      const velocity = deltaY / Math.max(1, Date.now() - touchStartTime)
      const distanceThreshold = Math.max(100, window.innerHeight * 0.22)
      if (deltaY > distanceThreshold || velocity > 0.5) animateClose('down')
      else {
        sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
        sheetEl.value.style.transform = ''
      }
    }

    isSwiping.value = false
    swipeDir.value = null
  }

  return {
    sheetEl, bodyEl, showUnsaved, isSwiping, isClosing,
    tryClose, doForceClose, onTouchStart, onTouchMove, onTouchEnd,
  }
}
