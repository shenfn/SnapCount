export function createExpressionPlanState({
  repository,
  cache = { value: {} },
  isDeliveryValid = () => false,
  deliveryIdentityMatches = () => false,
}) {
  if (!repository?.postAction) throw new Error('表达计划缺少 Repository')

  const recordExpressionPlanCache = cache
  const loadRequests = new Map()
  const ackRequests = new Map()
  const cacheRevisions = new Map()
  let cacheVersion = 0

  function setRecordExpressionPlan(recordId, value) {
    recordExpressionPlanCache.value = {
      ...recordExpressionPlanCache.value,
      [recordId]: value,
    }
    return value
  }

  function updateRecordExpressionPlan(recordId, patch) {
    return setRecordExpressionPlan(recordId, {
      ...(recordExpressionPlanCache.value[recordId] || {}),
      ...patch,
    })
  }

  function getRecordExpressionPlanCacheRevision(recordId) {
    return cacheRevisions.get(recordId) || 0
  }

  function isCacheCurrent(recordId, version, revision) {
    return version === cacheVersion
      && revision === getRecordExpressionPlanCacheRevision(recordId)
  }

  function reset() {
    recordExpressionPlanCache.value = {}
    loadRequests.clear()
    ackRequests.clear()
    cacheRevisions.clear()
    cacheVersion += 1
  }

  function invalidateRecordExpressionPlan(recordId) {
    const normalizedRecordId = String(recordId || '').trim()
    if (!normalizedRecordId) return false

    const hadCachedPlan = Object.prototype.hasOwnProperty.call(
      recordExpressionPlanCache.value,
      normalizedRecordId,
    )
    if (hadCachedPlan) {
      const nextCache = { ...recordExpressionPlanCache.value }
      delete nextCache[normalizedRecordId]
      recordExpressionPlanCache.value = nextCache
    }
    for (const recordKind of ['expense', 'income', 'data']) {
      loadRequests.delete(`${recordKind}:${normalizedRecordId}`)
    }
    ackRequests.delete(normalizedRecordId)
    cacheRevisions.set(
      normalizedRecordId,
      getRecordExpressionPlanCacheRevision(normalizedRecordId) + 1,
    )
    return hadCachedPlan
  }

  function loadRecordExpressionPlan(recordId, { recordKind, force = false, signal } = {}) {
    const normalizedRecordId = String(recordId || '').trim()
    const normalizedRecordKind = recordKind === 'universal' ? 'data' : String(recordKind || '').trim()
    if (!normalizedRecordId) return Promise.reject(new Error('缺少记录编号'))
    if (!['expense', 'income', 'data'].includes(normalizedRecordKind)) {
      return Promise.reject(new Error('缺少有效的记录类型'))
    }

    const requestKey = `${normalizedRecordKind}:${normalizedRecordId}`
    if (force) {
      invalidateRecordExpressionPlan(normalizedRecordId)
    } else if (loadRequests.has(requestKey)) {
      return loadRequests.get(requestKey)
    }

    const cached = recordExpressionPlanCache.value[normalizedRecordId]
    const retryableUnavailable = cached?.status === 'unavailable' && cached.reason === 'plan_not_ready'
    if (!force
      && cached?.recordKind === normalizedRecordKind
      && !['loading', 'error'].includes(cached.status)
      && !retryableUnavailable) return Promise.resolve(cached)

    const version = cacheVersion
    const revision = getRecordExpressionPlanCacheRevision(normalizedRecordId)
    setRecordExpressionPlan(normalizedRecordId, {
      status: 'loading',
      available: false,
      acknowledged: false,
      feedback: null,
      recordId: normalizedRecordId,
      recordKind: normalizedRecordKind,
      error: '',
    })

    const request = (async () => {
      try {
        const data = await repository.postAction('get_record_expression_plan', {
          record_id: normalizedRecordId,
          record_kind: normalizedRecordKind,
        }, { signal })
        if (!isCacheCurrent(normalizedRecordId, version, revision)) return null
        if (!data?.available) {
          return setRecordExpressionPlan(normalizedRecordId, {
            status: 'unavailable',
            available: false,
            acknowledged: false,
            feedback: null,
            recordId: normalizedRecordId,
            recordKind: normalizedRecordKind,
            reason: data?.reason || 'not_available',
            error: '',
          })
        }

        const planToken = String(data.plan_token || '').trim()
        const candidateId = String(data.candidate_id || '').trim()
        if (!planToken || !candidateId || !isDeliveryValid(data)) {
          throw new Error('表达计划响应不完整')
        }
        return setRecordExpressionPlan(normalizedRecordId, {
          status: 'ready',
          available: true,
          acknowledged: false,
          recordId: normalizedRecordId,
          recordKind: normalizedRecordKind,
          planToken,
          candidateId,
          feedback: data.feedback,
          presentationTarget: data.presentation_target || data.presentationTarget || '',
          renderedPayload: data.rendered_payload || data.renderedPayload || null,
          visibleFieldPaths: data.visible_field_paths || data.visibleFieldPaths || [],
          renderedTextFingerprint: data.rendered_text_fingerprint || data.renderedTextFingerprint || '',
          claimFingerprint: data.claim_fingerprint || data.claimFingerprint || data.feedback?.claim_fingerprint || '',
          error: '',
        })
      } catch (error) {
        if (isCacheCurrent(normalizedRecordId, version, revision)) {
          setRecordExpressionPlan(normalizedRecordId, {
            status: 'error',
            available: false,
            acknowledged: false,
            feedback: null,
            recordId: normalizedRecordId,
            recordKind: normalizedRecordKind,
            error: error?.message || String(error),
          })
        }
        throw error
      }
    })()
    loadRequests.set(requestKey, request)
    request.finally(() => {
      if (loadRequests.get(requestKey) === request) loadRequests.delete(requestKey)
    }).catch(() => {})
    return request
  }

  function ackRecordExpressionPlan(recordId, { signal } = {}) {
    const normalizedRecordId = String(recordId || '').trim()
    if (!normalizedRecordId) return Promise.reject(new Error('缺少记录编号'))
    if (ackRequests.has(normalizedRecordId)) return ackRequests.get(normalizedRecordId)

    const cached = recordExpressionPlanCache.value[normalizedRecordId]
    if (!cached?.available) return Promise.resolve(cached || null)
    if (cached.acknowledged && cached.feedback?.exposure_event_id) return Promise.resolve(cached)

    const version = cacheVersion
    const revision = getRecordExpressionPlanCacheRevision(normalizedRecordId)
    const planToken = cached.planToken
    const candidateId = cached.candidateId
    updateRecordExpressionPlan(normalizedRecordId, { status: 'acknowledging', ackError: '' })

    const request = (async () => {
      try {
        const data = await repository.postAction('ack_record_expression_plan', {
          record_id: normalizedRecordId,
          plan_token: planToken,
          candidate_id: candidateId,
        }, { signal })
        if (!isCacheCurrent(normalizedRecordId, version, revision)) return null
        const current = recordExpressionPlanCache.value[normalizedRecordId]
        if (current?.planToken !== planToken || current?.candidateId !== candidateId) return current || null

        const exposureEventId = String(
          data?.feedback?.exposure_event_id || data?.exposure_event_id || '',
        ).trim()
        const acknowledgedDelivery = {
          candidateId: String(data?.candidate_id || '').trim(),
          feedback: data?.feedback,
          presentationTarget: data?.presentation_target || data?.presentationTarget || '',
          renderedPayload: data?.rendered_payload || data?.renderedPayload || null,
          visibleFieldPaths: data?.visible_field_paths || data?.visibleFieldPaths || [],
          renderedTextFingerprint: data?.rendered_text_fingerprint || data?.renderedTextFingerprint || '',
          claimFingerprint: data?.claim_fingerprint || data?.claimFingerprint || data?.feedback?.claim_fingerprint || '',
        }
        if (!exposureEventId || !deliveryIdentityMatches(current, acknowledgedDelivery)) {
          throw new Error('表达曝光确认响应不完整')
        }
        return updateRecordExpressionPlan(normalizedRecordId, {
          status: 'acknowledged',
          acknowledged: true,
          feedback: {
            ...(current.feedback || {}),
            ...(data?.feedback || {}),
            exposure_event_id: exposureEventId,
          },
          ackError: '',
        })
      } catch (error) {
        if (isCacheCurrent(normalizedRecordId, version, revision)) {
          const current = recordExpressionPlanCache.value[normalizedRecordId]
          if (current?.planToken === planToken && current?.candidateId === candidateId) {
            updateRecordExpressionPlan(normalizedRecordId, {
              status: 'ack_error',
              acknowledged: false,
              ackError: error?.message || String(error),
            })
          }
        }
        throw error
      }
    })()
    ackRequests.set(normalizedRecordId, request)
    request.finally(() => {
      if (ackRequests.get(normalizedRecordId) === request) ackRequests.delete(normalizedRecordId)
    }).catch(() => {})
    return request
  }

  function submitExpressionFeedback({ recordId, choice, freeText = '', exposureEventId = '' }) {
    if (!recordId || !choice) return Promise.reject(new Error('缺少点评信息'))
    return repository.postAction('submit_expression_feedback', {
      record_id: recordId,
      primary_choice: choice,
      free_text: freeText,
      ...(exposureEventId ? { exposure_event_id: exposureEventId } : {}),
    }, { keepalive: true })
  }

  return {
    recordExpressionPlanCache,
    reset,
    invalidateRecordExpressionPlan,
    getRecordExpressionPlanCacheRevision,
    loadRecordExpressionPlan,
    ackRecordExpressionPlan,
    submitExpressionFeedback,
  }
}
