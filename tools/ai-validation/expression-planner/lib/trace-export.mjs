function countBy(items, keyOf) {
  const counts = {}
  for (const item of items) {
    const key = keyOf(item) ?? 'unknown'
    counts[key] = (counts[key] ?? 0) + 1
  }
  return counts
}

function ledgerNotes(events) {
  const notes = ['仅 count_in_facts=true 的事件进入事实候选']
  if (events.some(event => event.event_time_source === 'known_at_proxy')) {
    notes.push('缺少业务发生时间的事件回退到 known_at，时间类候选需要降低置信度')
  }
  if (events.some(event => event.ledger_status === 'user_confirmed_distinct')) {
    notes.push('用户点评覆盖机器重复判断，但保留原始 duplicate 证据')
  }
  return notes
}

export function buildExpressionTrace(snapshot, { runId, caseFile, localDate } = {}) {
  const events = snapshot.recognition_ledger?.events ?? []
  const ledgerSummary = snapshot.recognition_ledger?.summary ?? {}
  const candidates = snapshot.fact_candidates ?? []
  const comparisonCandidates = snapshot.comparison_candidates ?? []
  const eligibleCandidates = candidates.filter(item => item.eligibility?.eligible !== false)
  const blockedCandidates = candidates.filter(item => item.eligibility?.eligible === false)
  const entityId = snapshot.entity_filter?.entity_id ?? 'all-merchants'
  const resolvedLocalDate = localDate ?? snapshot.input?.asOf?.slice(0, 10) ?? null
  const resolvedRunId = runId ?? `expression-planner-${resolvedLocalDate?.replaceAll('-', '') ?? 'unknown'}-${entityId.replaceAll('_', '-')}`
  const resolvedCaseFile = caseFile ?? `${entityId}-${resolvedLocalDate ?? 'unknown'}`

  return {
    trace_id: `expression-replay:${snapshot.data_boundary?.user_id ?? 'unknown'}:${entityId}:${resolvedLocalDate ?? 'unknown'}`,
    run_id: resolvedRunId,
    status: 'done',
    created_at: snapshot.generated_at,
    case: {
      test_case_file: resolvedCaseFile,
      test_case_domain: 'expression_planner',
      test_case_date: resolvedLocalDate,
      source_kind: 'historical_replay',
    },
    user_context: {
      user_id: snapshot.data_boundary?.user_id ?? null,
      as_of: snapshot.data_boundary?.as_of ?? null,
      future_profile_used: snapshot.data_boundary?.future_profile_used ?? null,
    },
    request_context: {
      entity_filter: snapshot.entity_filter ?? null,
      read_only: snapshot.read_only === true,
    },
    steps: [
      {
        step_id: 'event_ledger_build',
        name: '事件账本构建',
        status: 'success',
        duration_ms: null,
        visibility_level: 'L1',
        user_visible: false,
        input_snapshot: {
          entity_id: entityId,
          local_date: resolvedLocalDate,
          override_event_count: events.filter(event => event.override).length,
        },
        output_snapshot: {
          ...ledgerSummary,
          status_counts: ledgerSummary.status_counts ?? countBy(events, event => event.ledger_status),
        },
        artifact_refs: ['event_ledger', 'event_ledger_summary'],
        loss_or_transform_notes: ledgerNotes(events),
      },
      {
        step_id: 'fact_candidate_generate',
        name: '事实候选生成',
        status: 'success',
        duration_ms: null,
        visibility_level: 'L1',
        user_visible: false,
        input_snapshot: {
          ledger_event_count: events.length,
          fact_eligible_event_count: ledgerSummary.fact_eligible_events ?? events.filter(event => event.count_in_facts).length,
          entity_id: entityId,
          local_date: resolvedLocalDate,
        },
        output_snapshot: {
          candidate_count: candidates.length,
          eligible_count: eligibleCandidates.length,
          blocked_count: blockedCandidates.length,
          claim_types: countBy(candidates, item => item.claim_type),
          dimensions: [...new Set(candidates.map(item => item.dimension).filter(Boolean))],
        },
        artifact_refs: ['fact_candidates'],
        loss_or_transform_notes: ['候选只表达可审计事实，不执行评分、个性化或大模型措辞'],
      },
      {
        step_id: 'comparison_candidate_generate',
        name: '比较候选生成',
        status: 'success',
        duration_ms: null,
        visibility_level: 'L1',
        user_visible: false,
        input_snapshot: {
          historical_record_count: snapshot.records?.length ?? 0,
          current_day_fact_event_count: ledgerSummary.fact_eligible_events ?? events.filter(event => event.count_in_facts).length,
          entity_id: entityId,
          local_date: resolvedLocalDate,
        },
        output_snapshot: {
          candidate_count: comparisonCandidates.length,
          claim_types: countBy(comparisonCandidates, item => item.claim_type),
          dimensions: [...new Set(comparisonCandidates.map(item => item.dimension).filter(Boolean))],
        },
        artifact_refs: ['comparison_candidates'],
        loss_or_transform_notes: [
          '当天使用事件账本，历史周期使用正式交易，避免当前日已落库事件重复计算',
          '周比较使用相同已流逝天数，不将未完成周期与完整周期直接比较',
        ],
      },
      {
        step_id: 'candidate_eligibility_evaluate',
        name: '候选资格评估',
        status: 'success',
        duration_ms: null,
        visibility_level: 'L1',
        user_visible: false,
        input_snapshot: {
          fact_candidate_count: candidates.length,
          comparison_candidate_count: comparisonCandidates.length,
        },
        output_snapshot: snapshot.eligibility_summary ?? {},
        artifact_refs: ['eligibility_summary', 'fact_candidates', 'comparison_candidates'],
        loss_or_transform_notes: [
          'claim eligibility 只判断主张是否成立，不按变化幅度制造沉默',
          'surface eligibility 根据置信度和数据完整度限制展示位置',
        ],
      },
      {
        step_id: 'candidate_deterministic_score',
        name: '确定性候选评分',
        status: 'success',
        duration_ms: null,
        visibility_level: 'L1',
        user_visible: false,
        input_snapshot: {
          candidate_count: candidates.length + comparisonCandidates.length,
          preference_profile_source: snapshot.scoring_context?.preference_profile_source ?? 'neutral_default',
          exposure_history_source: snapshot.scoring_context?.exposure_history_source ?? 'empty_baseline',
        },
        output_snapshot: Object.fromEntries(Object.entries(snapshot.scoring_summary ?? {}).map(([surface, value]) => [surface, {
          threshold: value.threshold,
          eligible_count: value.eligible_count,
          passing_count: value.passing_count,
          top_candidate: value.ranking?.[0] ?? null,
        }])),
        artifact_refs: ['scoring_summary', 'fact_candidates', 'comparison_candidates'],
        loss_or_transform_notes: [
          '当前使用透明确定性权重，不使用机器学习',
          '无偏好记忆和曝光历史时使用中性默认值，不宣称个性化',
        ],
      },
      {
        step_id: 'expression_plan_build',
        name: '表达计划决策',
        status: 'success',
        duration_ms: null,
        visibility_level: 'L1',
        user_visible: false,
        input_snapshot: {
          surfaces: Object.keys(snapshot.expression_plans ?? {}),
          candidate_count: candidates.length + comparisonCandidates.length,
        },
        output_snapshot: snapshot.expression_plan_summary ?? {},
        artifact_refs: ['expression_plans', 'scoring_summary', 'fact_candidates', 'comparison_candidates'],
        loss_or_transform_notes: [
          '固定业务槽位优先保留，已覆盖的语义不会再次选择',
          '快捷通知和 AI 弹窗限制为一个主要表达方向',
          '没有过线洞察时可使用精确事实兜底，避免无意义沉默',
        ],
      },
      {
        step_id: 'surface_render_contract_apply',
        name: '展示契约与曝光预览',
        status: 'success',
        duration_ms: null,
        visibility_level: 'L1',
        user_visible: false,
        input_snapshot: {
          planned_surfaces: Object.keys(snapshot.expression_plans ?? {}),
        },
        output_snapshot: {
          render_plans: Object.fromEntries(Object.entries(snapshot.render_plans ?? {}).map(([surface, plan]) => [surface, {
            selected_count: plan.selected?.length ?? 0,
            render_state: plan.render_state,
            simulation_only: plan.simulation_only,
          }])),
          exposure_event_count: snapshot.exposure_events?.length ?? 0,
          counts_for_novelty: (snapshot.exposure_events ?? []).filter(event => event.counts_for_novelty).length,
        },
        artifact_refs: ['render_plans', 'exposure_events', 'expression_plans'],
        loss_or_transform_notes: [
          '字段级区分可见、可展开和仅持久化内容',
          '历史回放只生成 rendered_preview，不计入真实曝光和 novelty',
        ],
      },
    ],
    user_visible_outputs: [],
    artifacts: {
      event_ledger: events,
      event_ledger_summary: ledgerSummary,
      fact_candidates: candidates,
      comparison_candidates: comparisonCandidates,
      eligibility_summary: snapshot.eligibility_summary ?? {},
      scoring_summary: snapshot.scoring_summary ?? {},
      expression_plans: snapshot.expression_plans ?? {},
      render_plans: snapshot.render_plans ?? {},
      exposure_events: snapshot.exposure_events ?? [],
      replay_audit: snapshot.audit ?? {},
      confirmed_record_summaries: snapshot.confirmed_record_summaries ?? {},
    },
    db_targets: [],
    errors: [],
  }
}

export function buildExpressionSummary(trace) {
  return {
    run_id: trace.run_id,
    generated_at: trace.created_at,
    response_mode: 'json',
    capture_kind: 'historical-replay',
    source_app: 'expression-planner',
    total_cases: 1,
    success_cases: trace.status === 'done' ? 1 : 0,
    failed_cases: trace.status === 'done' ? 0 : 1,
    ai_feedback_cases: 0,
    dry_run: true,
  }
}
