import { candidate, median, num, payloadValue, timestamp } from './generic-domain-shared.mjs'

function sleepClock(value) {
  const parsed = timestamp(value)
  if (parsed === null) return null
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(parsed))
}

function clockMinutes(value) {
  const match = String(value ?? '').match(/(?:T|\s|^)(\d{1,2}):(\d{2})/)
  if (!match) return null
  const minutes = Number(match[1]) * 60 + Number(match[2])
  return Number.isFinite(minutes) ? minutes : null
}

function signedClockDelta(current, baseline) {
  if (current === null || baseline === null) return null
  let delta = current - baseline
  if (delta > 720) delta -= 1440
  if (delta < -720) delta += 1440
  return delta
}

export function generateSleepCandidates(current, prior, domainProfile = {}) {
  const output = []
  const start = payloadValue(current, 'sleep_start_at')
  const wake = payloadValue(current, 'wake_at')
  const score = num(payloadValue(current, 'quality_score'))
  const deep = num(payloadValue(current, 'deep_sleep_minutes'))
  const light = num(payloadValue(current, 'light_sleep_minutes'))
  const rem = num(payloadValue(current, 'rem_minutes'))

  if (start || wake) {
    const timingNumbers = [
      { value: clockMinutes(start), meaning: 'sleep_start_clock_minutes', derivation: 'source_record.sleep_start_at' },
      { value: clockMinutes(wake), meaning: 'wake_clock_minutes', derivation: 'source_record.wake_at' },
    ].filter(item => item.value !== null)
    output.push(candidate({
      id: `fact:sleep:timing:${current.id}`,
      domainKey: 'sleep',
      semanticKey: 'sleep_timing',
      subtype: 'observed',
      dimension: 'temporal_rhythm',
      value: { occurred_at: current.occurred_at, sleep_start_at: start, wake_at: wake },
      text: `入睡 ${sleepClock(start) ?? '未知'}，醒来 ${sleepClock(wake) ?? '未知'}`,
      records: [current],
      numbers: timingNumbers,
      confidence: timingNumbers.length === 2 ? 0.9 : 0.8,
      dataCoverage: timingNumbers.length / 2,
      evidenceFields: ['occurred_at', 'sleep_start_at', 'wake_at', 'time_context'],
      selectionHints: { allowed_surfaces: ['pwa_pending_ai_card', 'record_detail'] },
    }))
    const typicalStart = clockMinutes(domainProfile?.chronotype?.typical_sleep_start)
    const typicalWake = clockMinutes(domainProfile?.chronotype?.typical_wake)
    const startDelta = signedClockDelta(clockMinutes(start), typicalStart)
    const wakeDelta = signedClockDelta(clockMinutes(wake), typicalWake)
    if (startDelta !== null || wakeDelta !== null) {
      const describeDelta = value => value === null
        ? null
        : `${Math.abs(value)} 分钟${value >= 0 ? '晚' : '早'}`
      output.push(candidate({
        id: `comparison:sleep:timing-baseline:${current.id}`,
        domainKey: 'sleep',
        semanticKey: 'sleep_timing_vs_typical',
        claimType: 'comparison',
        dimension: 'timing_baseline',
        value: {
          sleep_start_delta_minutes: startDelta,
          wake_delta_minutes: wakeDelta,
          baseline: domainProfile.chronotype,
        },
        text: `入睡${describeDelta(startDelta) ?? '时间未知'}，醒来${describeDelta(wakeDelta) ?? '时间未知'}（相对你的典型作息）`,
        records: [current],
        numbers: [
          startDelta === null ? null : { value: startDelta, meaning: 'sleep_start_delta_minutes', derivation: 'current_start - typical_start' },
          wakeDelta === null ? null : { value: wakeDelta, meaning: 'wake_delta_minutes', derivation: 'current_wake - typical_wake' },
        ].filter(Boolean),
        confidence: 0.86,
        evidenceFields: ['occurred_at', 'sleep_start_at', 'wake_at'],
      }))
    }
  }

  if (score !== null) {
    const priorScores = prior
      .map(record => num(payloadValue(record, 'quality_score')))
      .filter(value => value !== null)
    const baseline = priorScores.length >= 3 ? median(priorScores) : null
    output.push(candidate({
      id: `fact:sleep:quality:${current.id}`,
      domainKey: 'sleep',
      semanticKey: 'sleep_quality_current',
      subtype: baseline === null ? 'observed' : 'comparison',
      dimension: 'quality',
      value: { current: score, median: baseline, sample_count: priorScores.length },
      text: baseline === null ? `设备睡眠评分 ${score}` : `设备睡眠评分 ${score}，历史中位数 ${baseline}`,
      records: [current, ...prior.filter(record => num(payloadValue(record, 'quality_score')) !== null)],
      numbers: [
        { value: score, meaning: 'current_sleep_quality_score', derivation: 'source_record.quality_score' },
        ...(baseline === null ? [] : [
          { value: baseline, meaning: 'historical_median_sleep_quality_score', derivation: 'median(prior.quality_score)' },
          { value: priorScores.length, meaning: 'sleep_quality_baseline_sample_count', role: 'count', derivation: 'count(prior.quality_score)' },
        ]),
      ],
      confidence: baseline === null ? 0.82 : 0.86,
      evidenceFields: ['occurred_at', 'quality_score', 'quality_level'],
    }))
  }

  if (deep !== null || light !== null || rem !== null) {
    const known = [deep, light, rem].filter(value => value !== null)
    const total = known.reduce((sum, value) => sum + value, 0)
    output.push(candidate({
      id: `fact:sleep:stages:${current.id}`,
      domainKey: 'sleep',
      semanticKey: 'sleep_stage_composition',
      subtype: 'derived',
      dimension: 'sleep_structure',
      value: { deep_minutes: deep, light_minutes: light, rem_minutes: rem, observed_total_minutes: total },
      text: `睡眠阶段：深睡 ${deep ?? '未知'} 分钟、浅睡 ${light ?? '未知'} 分钟、REM ${rem ?? '未知'} 分钟（设备估算）`,
      records: [current],
      numbers: [
        deep === null ? null : { value: deep, meaning: 'deep_sleep_minutes', derivation: 'source_record.deep_sleep_minutes' },
        light === null ? null : { value: light, meaning: 'light_sleep_minutes', derivation: 'source_record.light_sleep_minutes' },
        rem === null ? null : { value: rem, meaning: 'rem_sleep_minutes', derivation: 'source_record.rem_minutes' },
      ].filter(Boolean),
      confidence: 0.74,
      dataCoverage: known.length / 3,
      evidenceFields: ['occurred_at', 'deep_sleep_minutes', 'light_sleep_minutes', 'rem_minutes', 'awake_minutes'],
      selectionHints: { allowed_surfaces: ['pwa_pending_ai_card', 'record_detail'] },
    }))
  }
  return output
}
