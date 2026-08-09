export function normalizeEntityText(value) {
  return String(value ?? '')
    .normalize('NFKC')
    .trim()
    .toLowerCase()
    .replace(/[\s·•・_—–-]+/g, '')
    .replace(/[（）()【】\[\]]/g, '')
}

const LEGAL_NAME_SUFFIXES = [
  '股份有限责任公司',
  '有限责任公司',
  '股份有限公司',
  '集团有限公司',
  '个人独资企业',
  '普通合伙企业',
  '有限合伙企业',
  '个体工商户',
  '合伙企业',
  '有限公司',
].sort((left, right) => right.length - left.length)

const ADMINISTRATIVE_PREFIX = /^(?=.{2,16}$)[\p{Script=Han}]+(?:特别行政区|自治区|自治州|地区|省|市|区|县|旗|镇|乡|街道)$/u

function withoutLegalNameSuffix(value) {
  let core = value
  let removed = false
  while (core) {
    const suffix = LEGAL_NAME_SUFFIXES.find(item => core.length > item.length && core.endsWith(item))
    if (!suffix) break
    core = core.slice(0, -suffix.length)
    removed = true
  }
  return { core, removed }
}

function historicalVariantBasis(currentMerchant, priorMerchant) {
  const currentKey = currentMerchant?.normalized_key ?? ''
  const priorKey = priorMerchant?.normalized_key ?? ''
  if (!currentKey || !priorKey || currentKey === priorKey) return null

  const current = withoutLegalNameSuffix(currentKey)
  const prior = withoutLegalNameSuffix(priorKey)
  if (!current.core || !prior.core) return null
  if (current.core === prior.core && (current.removed || prior.removed)) {
    return 'legal_suffix'
  }

  const [longer, shorter] = current.core.length >= prior.core.length
    ? [current.core, prior.core]
    : [prior.core, current.core]
  if (shorter.length < 6 || !longer.endsWith(shorter)) return null
  const prefix = longer.slice(0, -shorter.length)
  if (!ADMINISTRATIVE_PREFIX.test(prefix)) return null
  return current.removed || prior.removed
    ? 'administrative_prefix_and_legal_suffix'
    : 'administrative_prefix'
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
  const originalEntityId = currentMerchant?.entity_id ?? null
  const normalizedKey = currentMerchant?.normalized_key ?? null
  let entityId = originalEntityId
  let canonicalName = currentMerchant?.canonical_name ?? null
  let resolution = currentMerchant?.resolution ?? 'missing'
  let confidence = currentMerchant?.confidence ?? 0
  let matchBasis = resolution
  let ambiguous = false
  let matchingPrior = entityId
    ? priorMerchants.filter(merchant => merchant?.entity_id === entityId)
    : []

  let variantMatches = []
  if (matchingPrior.length === 0 && normalizedKey) {
    variantMatches = priorMerchants.flatMap(merchant => {
      const basis = historicalVariantBasis(currentMerchant, merchant)
      return basis && merchant?.entity_id ? [{ merchant, basis }] : []
    })
    const matchesByEntity = new Map()
    for (const match of variantMatches) {
      if (!matchesByEntity.has(match.merchant.entity_id)) matchesByEntity.set(match.merchant.entity_id, [])
      matchesByEntity.get(match.merchant.entity_id).push(match)
    }

    if (matchesByEntity.size === 1) {
      const [historicalEntityId, matches] = [...matchesByEntity.entries()][0]
      const anchor = matches[0].merchant
      entityId = historicalEntityId
      canonicalName = anchor.canonical_name ?? anchor.raw_name ?? canonicalName
      resolution = 'historical_legal_variant'
      confidence = 0.92
      matchBasis = matches[0].basis
      matchingPrior = priorMerchants.filter(merchant => merchant?.entity_id === historicalEntityId)
    } else if (matchesByEntity.size > 1) {
      ambiguous = true
      resolution = 'historical_variant_ambiguous'
      confidence = Math.min(confidence, 0.4)
      matchBasis = 'multiple_historical_entities'
    }
  }

  const priorAliasKeys = new Set(matchingPrior.map(merchant => merchant?.normalized_key).filter(Boolean))
  const observedAliases = []
  const seenRawNames = new Set()

  const observationSources = ambiguous
    ? [...variantMatches.map(match => match.merchant), currentMerchant]
    : [...matchingPrior, currentMerchant]
  for (const merchant of observationSources) {
    const rawName = String(merchant?.raw_name ?? '').normalize('NFKC').trim()
    if (!rawName || seenRawNames.has(rawName)) continue
    seenRawNames.add(rawName)
    observedAliases.push(rawName)
  }

  return {
    entity_id: entityId,
    canonical_name: canonicalName,
    raw_name: currentMerchant?.raw_name ?? null,
    normalized_key: normalizedKey,
    resolution,
    confidence,
    match_basis: matchBasis,
    entity_first_seen: ambiguous ? null : entityId ? matchingPrior.length === 0 : null,
    alias_first_seen: ambiguous ? null : normalizedKey ? !priorAliasKeys.has(normalizedKey) : null,
    historical_record_count: matchingPrior.length,
    total_record_count: matchingPrior.length + 1,
    observed_aliases: observedAliases,
  }
}
