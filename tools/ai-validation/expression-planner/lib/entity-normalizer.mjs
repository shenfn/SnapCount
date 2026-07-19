export function normalizeEntityText(value) {
  return String(value ?? '')
    .normalize('NFKC')
    .trim()
    .toLowerCase()
    .replace(/[\s·•・_—–-]+/g, '')
    .replace(/[（）()【】\[\]]/g, '')
}

export function compileMerchantAliases(config) {
  const aliases = new Map()
  for (const merchant of config?.merchants ?? []) {
    for (const name of [merchant.canonical_name, ...(merchant.aliases ?? [])]) {
      const key = normalizeEntityText(name)
      if (!key) continue
      aliases.set(key, {
        entity_id: merchant.entity_id,
        entity_type: merchant.entity_type ?? 'unknown',
        canonical_name: merchant.canonical_name,
      })
    }
  }
  return aliases
}

export function resolveMerchant(value, aliasMap) {
  const raw_name = String(value ?? '').trim() || null
  const normalized_key = normalizeEntityText(raw_name)
  const matched = normalized_key ? aliasMap.get(normalized_key) : null
  if (matched) {
    return {
      raw_name,
      normalized_key,
      ...matched,
      resolution: 'configured_alias',
      confidence: 1,
    }
  }
  return {
    raw_name,
    normalized_key,
    entity_id: normalized_key ? `merchant_unmapped_${normalized_key}` : null,
    entity_type: 'unknown',
    canonical_name: raw_name,
    resolution: raw_name ? 'normalized_fallback' : 'missing',
    confidence: raw_name ? 0.6 : 0,
  }
}

export function summarizeMerchantObservation(currentMerchant, priorMerchants = []) {
  const entityId = currentMerchant?.entity_id ?? null
  const normalizedKey = currentMerchant?.normalized_key ?? null
  const matchingPrior = entityId
    ? priorMerchants.filter(merchant => merchant?.entity_id === entityId)
    : []
  const priorAliasKeys = new Set(matchingPrior.map(merchant => merchant?.normalized_key).filter(Boolean))
  const observedAliases = []
  const seenRawNames = new Set()

  for (const merchant of [...matchingPrior, currentMerchant]) {
    const rawName = String(merchant?.raw_name ?? '').normalize('NFKC').trim()
    if (!rawName || seenRawNames.has(rawName)) continue
    seenRawNames.add(rawName)
    observedAliases.push(rawName)
  }

  return {
    entity_id: entityId,
    canonical_name: currentMerchant?.canonical_name ?? null,
    raw_name: currentMerchant?.raw_name ?? null,
    normalized_key: normalizedKey,
    resolution: currentMerchant?.resolution ?? 'missing',
    confidence: currentMerchant?.confidence ?? 0,
    entity_first_seen: entityId ? matchingPrior.length === 0 : null,
    alias_first_seen: normalizedKey ? !priorAliasKeys.has(normalizedKey) : null,
    observed_aliases: observedAliases,
  }
}
