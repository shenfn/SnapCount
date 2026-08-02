import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'

function parseArgs(argv) {
  const runArg = argv.find(arg => arg.startsWith('--run='))
  if (!runArg) throw new Error('--run=<replay run directory> is required')
  return { runDir: path.resolve(runArg.slice(6)) }
}

function safeJson(value) {
  return JSON.stringify(value).replaceAll('<', '\\u003c').replaceAll('>', '\\u003e').replaceAll('&', '\\u0026')
}

function documentHtml(data) {
  const embedded = safeJson({ generated_at: data.generated_at, rows: data.rows })
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>表达规划器逐条回放</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f6f4;
      --surface: #ffffff;
      --surface-soft: #eef1ed;
      --text: #17201b;
      --muted: #667169;
      --line: #d9dfda;
      --accent: #176447;
      --accent-soft: #e1f0e8;
      --warning: #9a5b11;
      --warning-soft: #f6ead8;
      --danger: #a23c35;
      --danger-soft: #f7e5e3;
      --focus: #2f8d68;
    }
    * { box-sizing: border-box; }
    html, body { height: 100%; margin: 0; overflow: hidden; background: var(--bg); color: var(--text); font-family: Inter, "Segoe UI", "Microsoft YaHei", sans-serif; font-size: 14px; letter-spacing: 0; }
    button, input, select { font: inherit; }
    button, a, select, input { outline-color: var(--focus); }
    .app { height: 100vh; display: grid; grid-template-rows: auto minmax(0, 1fr); }
    .topbar { min-height: 58px; display: flex; align-items: center; gap: 16px; padding: 10px 18px; background: var(--surface); border-bottom: 1px solid var(--line); }
    .brand { min-width: 210px; }
    .brand h1 { margin: 0; font-size: 17px; font-weight: 600; }
    .brand p { margin: 2px 0 0; color: var(--muted); font-size: 12px; }
    .controls { flex: 1; display: grid; grid-template-columns: minmax(180px, 1fr) 130px 150px; gap: 8px; }
    .control { width: 100%; min-height: 36px; padding: 7px 10px; color: var(--text); background: var(--surface); border: 1px solid var(--line); border-radius: 6px; }
    .raw-link { color: var(--accent); text-decoration: none; white-space: nowrap; }
    .raw-link:hover { text-decoration: underline; }
    .workspace { min-height: 0; display: grid; grid-template-columns: 330px minmax(0, 1fr); }
    .sidebar { min-height: 0; display: grid; grid-template-rows: auto minmax(0, 1fr); background: var(--surface); border-right: 1px solid var(--line); }
    .list-meta { padding: 10px 12px; color: var(--muted); border-bottom: 1px solid var(--line); }
    .record-list { min-height: 0; overflow-y: auto; }
    .record-button { width: 100%; display: block; padding: 11px 12px; color: var(--text); text-align: left; background: transparent; border: 0; border-bottom: 1px solid var(--line); cursor: pointer; transition: background 120ms ease, padding-left 120ms ease; }
    .record-button:hover { background: var(--surface-soft); }
    .record-button.is-selected { padding-left: 16px; background: var(--accent-soft); box-shadow: inset 3px 0 0 var(--accent); }
    .record-line { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
    .record-title { min-width: 0; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .record-count { color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
    .record-sub { margin-top: 4px; color: var(--muted); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .record-flags { display: flex; flex-wrap: wrap; gap: 5px; margin-top: 7px; }
    .tag { display: inline-flex; align-items: center; min-height: 22px; padding: 2px 7px; border-radius: 999px; background: var(--surface-soft); color: var(--muted); font-size: 11px; }
    .tag.accent { background: var(--accent-soft); color: var(--accent); }
    .tag.warning { background: var(--warning-soft); color: var(--warning); }
    .tag.danger { background: var(--danger-soft); color: var(--danger); }
    .detail { min-width: 0; min-height: 0; overflow-y: auto; }
    .detail-inner { max-width: 1180px; margin: 0 auto; padding: 22px 26px 56px; }
    .detail-head { display: flex; justify-content: space-between; gap: 18px; padding-bottom: 16px; border-bottom: 1px solid var(--line); }
    .detail-head h2 { margin: 0; font-size: 22px; font-weight: 600; overflow-wrap: anywhere; }
    .detail-meta { margin-top: 6px; color: var(--muted); }
    .headline-status { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 6px; align-content: start; }
    .section { padding: 20px 0; border-bottom: 1px solid var(--line); }
    .section:last-child { border-bottom: 0; }
    .section-title { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
    .section-title h3 { margin: 0; font-size: 15px; font-weight: 600; }
    .section-note { color: var(--muted); font-size: 12px; }
    .fact-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1px; background: var(--line); border: 1px solid var(--line); border-radius: 6px; overflow: hidden; }
    .fact { min-width: 0; padding: 10px 12px; background: var(--surface); }
    .fact dt { color: var(--muted); font-size: 11px; }
    .fact dd { margin: 3px 0 0; overflow-wrap: anywhere; }
    .summary-copy { margin: 0 0 12px; font-size: 16px; }
    .compare { display: grid; grid-template-columns: minmax(0, 0.9fr) minmax(0, 1.1fr); gap: 24px; }
    .lane { min-width: 0; }
    .lane-head { display: flex; justify-content: space-between; gap: 8px; padding-bottom: 8px; border-bottom: 2px solid var(--line); }
    .lane-head h3 { margin: 0; font-size: 15px; font-weight: 600; }
    .notification { margin: 12px 0 0; padding: 12px; white-space: pre-wrap; overflow-wrap: anywhere; background: var(--surface-soft); border-left: 3px solid var(--accent); }
    .candidate { padding: 13px 0; border-bottom: 1px solid var(--line); }
    .candidate:last-child { border-bottom: 0; }
    .candidate-keyline { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; }
    .candidate-key { color: var(--accent); font-weight: 600; overflow-wrap: anywhere; }
    .candidate-text { margin-top: 6px; font-size: 15px; overflow-wrap: anywhere; }
    .candidate-meta { display: flex; flex-wrap: wrap; gap: 6px 12px; margin-top: 7px; color: var(--muted); font-size: 12px; }
    .score-row { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 6px; margin-top: 9px; }
    .score { padding: 7px 8px; background: var(--surface-soft); border-radius: 4px; }
    .score span { display: block; color: var(--muted); font-size: 10px; }
    .score strong { display: block; margin-top: 2px; font-weight: 600; font-variant-numeric: tabular-nums; }
    .empty { padding: 18px 0; color: var(--muted); }
    .zero { padding: 14px; color: var(--danger); background: var(--danger-soft); border-left: 3px solid var(--danger); }
    .selection-table, .dish-table { width: 100%; border-collapse: collapse; }
    .selection-table th, .selection-table td, .dish-table th, .dish-table td { padding: 9px 8px; text-align: left; border-bottom: 1px solid var(--line); vertical-align: top; }
    .selection-table th, .dish-table th { color: var(--muted); font-size: 11px; font-weight: 500; }
    .selection-table code { overflow-wrap: anywhere; }
    .dish-table td:not(:first-child), .dish-table th:not(:first-child) { text-align: right; font-variant-numeric: tabular-nums; }
    details { margin-top: 12px; }
    summary { color: var(--accent); cursor: pointer; }
    pre { margin: 10px 0 0; padding: 12px; overflow: auto; color: var(--text); background: var(--surface-soft); border-radius: 6px; font: 12px/1.55 "Cascadia Code", Consolas, monospace; white-space: pre-wrap; overflow-wrap: anywhere; }
    .no-results { padding: 24px 14px; color: var(--muted); }
    @media (max-width: 850px) {
      html, body { height: auto; min-height: 100%; overflow: auto; }
      .app { height: auto; min-height: 100vh; }
      .topbar { align-items: flex-start; flex-wrap: wrap; }
      .brand { min-width: 100%; }
      .controls { grid-template-columns: 1fr 1fr; width: 100%; }
      .controls input { grid-column: 1 / -1; }
      .workspace { grid-template-columns: 1fr; }
      .sidebar { min-height: 300px; max-height: 44vh; border-right: 0; border-bottom: 1px solid var(--line); }
      .detail { overflow: visible; }
      .detail-inner { padding: 18px 14px 40px; }
      .compare { grid-template-columns: 1fr; }
      .score-row { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    }
    @media (prefers-reduced-motion: reduce) { * { scroll-behavior: auto !important; transition: none !important; } }
  </style>
</head>
<body>
  <main class="app">
    <header class="topbar">
      <div class="brand"><h1>表达规划器逐条回放</h1><p id="generated-at"></p></div>
      <div class="controls" aria-label="记录筛选">
        <input id="search" class="control" type="search" placeholder="搜索商户、菜品、候选内容">
        <select id="domain" class="control" aria-label="数据域"></select>
        <select id="state" class="control" aria-label="结果状态">
          <option value="all">全部状态</option>
          <option value="zero">仅零候选</option>
          <option value="changed">仅候选变化</option>
          <option value="shadow">有旧 Shadow</option>
          <option value="rich">至少 3 个候选</option>
        </select>
      </div>
      <a class="raw-link" href="replay-results.json">打开原始 JSON</a>
    </header>
    <div class="workspace">
      <aside class="sidebar">
        <div id="list-meta" class="list-meta"></div>
        <div id="record-list" class="record-list" aria-label="回放记录"></div>
      </aside>
      <section id="detail" class="detail" aria-live="polite"></section>
    </div>
  </main>
  <script id="replay-data" type="application/json">${embedded}</script>
  <script>
    (() => {
      const data = JSON.parse(document.getElementById('replay-data').textContent);
      const rows = data.rows.filter(row => row.comparison);
      const state = { query: '', domain: 'all', result: 'all', selectedId: null };
      const list = document.getElementById('record-list');
      const detail = document.getElementById('detail');
      const listMeta = document.getElementById('list-meta');
      const search = document.getElementById('search');
      const domain = document.getElementById('domain');
      const resultState = document.getElementById('state');

      document.getElementById('generated-at').textContent = '固定快照 · ' + new Date(data.generated_at).toLocaleString('zh-CN');
      const domains = [...new Set(rows.map(row => row.domain_key))].sort();
      domain.innerHTML = '<option value="all">全部数据域</option>' + domains.map(value => '<option value="' + esc(value) + '">' + esc(domainLabel(value)) + '</option>').join('');

      function esc(value) {
        return String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
      }

      function domainLabel(value) {
        return ({ expense: '支出', food: '饮食', sleep: '睡眠', sport: '运动', reading: '阅读', wallet: '钱包', income: '收入' })[value] || value;
      }

      function recordTitle(row) {
        return row.current_record?.title || row.current_record?.merchant_name || row.current_record?.summary || domainLabel(row.domain_key) + '记录';
      }

      function recordSubtitle(row) {
        if (row.current_record?.summary) return row.current_record.summary;
        if (row.domain_key === 'expense') return [row.current_record?.amount == null ? null : '¥' + row.current_record.amount, row.current_record?.category, row.current_record?.platform].filter(Boolean).join(' · ');
        return row.record_id;
      }

      function candidateCount(row) {
        return row.comparison?.local?.candidate_count ?? 0;
      }

      function hasChange(row) {
        return Boolean(row.old_shadow && (row.comparison.added_candidate_keys.length || row.comparison.removed_candidate_keys.length));
      }

      function searchable(row) {
        return JSON.stringify({ current: row.current_record, candidates: row.local_candidates, old: row.old_shadow?.baseline_payload }).toLowerCase();
      }

      function filteredRows() {
        const query = state.query.trim().toLowerCase();
        return rows.filter(row => {
          if (state.domain !== 'all' && row.domain_key !== state.domain) return false;
          if (state.result === 'zero' && candidateCount(row) !== 0) return false;
          if (state.result === 'changed' && !hasChange(row)) return false;
          if (state.result === 'shadow' && !row.old_shadow) return false;
          if (state.result === 'rich' && candidateCount(row) < 3) return false;
          return !query || searchable(row).includes(query);
        }).sort((a, b) => String(b.occurred_at).localeCompare(String(a.occurred_at)));
      }

      function tag(text, kind = '') {
        return '<span class="tag ' + kind + '">' + esc(text) + '</span>';
      }

      function renderList() {
        const visible = filteredRows();
        listMeta.textContent = '显示 ' + visible.length + ' / ' + rows.length + ' 条';
        if (!visible.length) {
          list.innerHTML = '<div class="no-results">没有符合条件的记录</div>';
          detail.innerHTML = '';
          return;
        }
        if (!visible.some(row => row.record_id === state.selectedId)) state.selectedId = visible[0].record_id;
        list.innerHTML = visible.map(row => {
          const count = candidateCount(row);
          const flags = [tag(domainLabel(row.domain_key)), row.old_shadow ? tag('旧 Shadow', 'accent') : '', count === 0 ? tag('零候选', 'danger') : '', hasChange(row) ? tag('候选变化', 'warning') : ''].join('');
          return '<button type="button" class="record-button ' + (row.record_id === state.selectedId ? 'is-selected' : '') + '" data-id="' + esc(row.record_id) + '">' +
            '<span class="record-line"><span class="record-title">' + esc(recordTitle(row)) + '</span><span class="record-count">' + count + ' 候选</span></span>' +
            '<span class="record-sub">' + esc(new Date(row.occurred_at).toLocaleString('zh-CN')) + ' · ' + esc(recordSubtitle(row)) + '</span>' +
            '<span class="record-flags">' + flags + '</span></button>';
        }).join('');
        list.querySelectorAll('[data-id]').forEach(button => button.addEventListener('click', () => {
          state.selectedId = button.dataset.id;
          renderList();
          renderDetail();
        }));
        renderDetail();
      }

      function simpleFacts(row) {
        const record = row.current_record || {};
        const payload = record.payload || {};
        const source = row.domain_key === 'expense' ? record : { title: record.title, summary: record.summary, ...payload };
        const skip = new Set(['dishes', 'ai_feedback', 'time_context', 'confidence_note', 'companion_message', 'title', 'summary']);
        const labels = { amount: '金额', merchant_name: '商户', category: '分类', platform: '平台', payment_method: '支付方式', meal_type: '餐次', total_calorie_kcal: '热量（千卡）', sleep_hours: '睡眠小时', sleep_minutes: '睡眠分钟', sleep_start_at: '入睡时间', wake_at: '醒来时间', quality_score: '睡眠评分', deep_sleep_minutes: '深睡分钟', light_sleep_minutes: '浅睡分钟', rem_minutes: 'REM 分钟', awake_minutes: '清醒分钟', sport_type: '运动类型', duration_minutes: '时长（分钟）', calories: '消耗（千卡）', distance_km: '距离（公里）', avg_heart_rate: '平均心率', record_kind: '记录类型', account_name: '账户', snapshot_balance: '账户金额' };
        const facts = Object.entries(source).filter(([key, value]) => !skip.has(key) && value !== null && value !== undefined && value !== '' && typeof value !== 'object');
        return '<dl class="fact-grid">' + facts.map(([key, value]) => '<div class="fact"><dt>' + esc(labels[key] || key) + '</dt><dd>' + esc(value) + '</dd></div>').join('') + '</dl>';
      }

      function dishes(record) {
        const items = record?.payload?.dishes;
        if (!Array.isArray(items) || !items.length) return '';
        return '<div class="section"><div class="section-title"><h3>识别到的菜品</h3><span class="section-note">真实 payload</span></div><table class="dish-table"><thead><tr><th>菜品</th><th>克</th><th>千卡</th><th>蛋白质</th><th>碳水</th><th>脂肪</th></tr></thead><tbody>' + items.map(item => '<tr><td>' + esc(item.name) + '</td><td>' + esc(item.estimated_grams ?? '—') + '</td><td>' + esc(item.calorie_kcal ?? '—') + '</td><td>' + esc(item.protein_g ?? '—') + '</td><td>' + esc(item.carb_g ?? '—') + '</td><td>' + esc(item.fat_g ?? '—') + '</td></tr>').join('') + '</tbody></table></div>';
      }

      function scores(candidate) {
        const labels = { shortcut_notification: '快捷通知', pwa_pending_ai_card: 'AI 卡片', record_detail: '记录详情', weekly_report: '周报' };
        return '<div class="score-row">' + Object.entries(labels).map(([key, label]) => '<div class="score"><span>' + label + '</span><strong>' + esc(candidate.scores?.[key] ?? '—') + '</strong></div>').join('') + '</div>';
      }

      function selectedSurfaces(row, semanticKey, source) {
        const selected = source === 'old' ? row.old_shadow?.plan?.selected : row.comparison.local.selected;
        if (!selected) return [];
        return Object.entries(selected).filter(([, keys]) => keys.includes(semanticKey)).map(([surface]) => surface);
      }

      function candidates(row, items, source) {
        if (!items?.length) return '<div class="empty">没有候选</div>';
        return items.map(candidate => {
          const selected = selectedSurfaces(row, candidate.semantic_key, source);
          const added = source === 'local' && row.old_shadow && row.comparison.added_candidate_keys.includes(candidate.semantic_key);
          return '<article class="candidate"><div class="candidate-keyline"><span class="candidate-key">' + esc(candidate.semantic_key) + '</span><span>' + (added ? tag('新增', 'warning') : '') + (selected.length ? tag('已入选', 'accent') : '') + '</span></div>' +
            '<div class="candidate-text">' + esc(candidate.canonical_text || '无 canonical_text') + '</div>' +
            '<div class="candidate-meta"><span>维度 ' + esc(candidate.dimension) + '</span><span>' + esc(candidate.claim_type) + '</span>' + (selected.length ? '<span>入选 ' + esc(selected.join(' / ')) + '</span>' : '') + '</div>' +
            scores(candidate) + '<details><summary>结构化值</summary><pre>' + esc(JSON.stringify(candidate.structured_value, null, 2)) + '</pre></details></article>';
        }).join('');
      }

      function oldContent(row) {
        if (!row.old_shadow) return '<div class="empty">这条记录没有旧 Shadow，不能做逐条前后对照。</div>';
        const baseline = row.old_shadow.baseline_payload || {};
        const feedback = baseline.ai_feedback || {};
        const copy = baseline.notification || [feedback.badge, feedback.emotion_line, feedback.utility_line].filter(Boolean).join('\\n');
        return (copy ? '<div class="notification">' + esc(copy) + '</div>' : '') + candidates(row, row.old_shadow.candidates, 'old');
      }

      function selectionTable(row) {
        const labels = { shortcut_notification: '快捷通知', pwa_pending_ai_card: 'AI 卡片', record_detail: '记录详情', weekly_report: '周报' };
        return '<table class="selection-table"><thead><tr><th>Surface</th><th>当前本地入选候选</th></tr></thead><tbody>' + Object.entries(labels).map(([key, label]) => '<tr><td>' + label + '</td><td>' + ((row.comparison.local.selected[key] || []).map(value => '<code>' + esc(value) + '</code>').join('<br>') || '静默') + '</td></tr>').join('') + '</tbody></table>';
      }

      function renderDetail() {
        const row = rows.find(item => item.record_id === state.selectedId);
        if (!row) return;
        const count = candidateCount(row);
        const summary = row.current_record?.summary;
        const statusTags = [tag(domainLabel(row.domain_key), 'accent'), tag(count + ' 个本地候选', count ? '' : 'danger'), row.old_shadow ? tag('有旧 Shadow') : tag('无旧 Shadow'), hasChange(row) ? tag('候选已变化', 'warning') : ''].join('');
        detail.innerHTML = '<div class="detail-inner"><header class="detail-head"><div><h2>' + esc(recordTitle(row)) + '</h2><div class="detail-meta">' + esc(new Date(row.occurred_at).toLocaleString('zh-CN')) + ' · 历史上下文 ' + esc(row.causal_history_count) + ' 条</div></div><div class="headline-status">' + statusTags + '</div></header>' +
          '<section class="section"><div class="section-title"><h3>真实记录</h3><span class="section-note">线上只读快照</span></div>' + (summary ? '<p class="summary-copy">' + esc(summary) + '</p>' : '') + simpleFacts(row) + '<details><summary>查看完整记录 JSON</summary><pre>' + esc(JSON.stringify(row.current_record, null, 2)) + '</pre></details></section>' +
          dishes(row.current_record) +
          (count === 0 ? '<section class="section"><div class="zero"><strong>当前 Planner 返回 0 候选。</strong><br>记录字段仍完整保留；显式 zero-candidate reason code 尚未实现，因此这里不会伪造原因。</div></section>' : '') +
          '<section class="section"><div class="compare"><div class="lane"><div class="lane-head"><h3>生产 Shadow（旧）</h3><span>' + esc(row.old_shadow?.plan?.candidate_count ?? '未运行') + '</span></div>' + oldContent(row) + '</div><div class="lane"><div class="lane-head"><h3>当前修改（本地）</h3><span>' + count + ' 条</span></div>' + candidates(row, row.local_candidates, 'local') + '</div></div></section>' +
          '<section class="section"><div class="section-title"><h3>当前 Surface 选择</h3><span class="section-note">仍未部署</span></div>' + selectionTable(row) + '</section>' +
          '<section class="section"><details><summary>查看完整逐条回放 JSON</summary><pre>' + esc(JSON.stringify(row, null, 2)) + '</pre></details></section></div>';
      }

      search.addEventListener('input', event => { state.query = event.target.value; renderList(); });
      domain.addEventListener('change', event => { state.domain = event.target.value; renderList(); });
      resultState.addEventListener('change', event => { state.result = event.target.value; renderList(); });
      renderList();
    })();
  </script>
</body>
</html>`
}

async function main() {
  const { runDir } = parseArgs(process.argv.slice(2))
  const resultPath = path.join(runDir, 'replay-results.json')
  const data = JSON.parse(await readFile(resultPath, 'utf8'))
  const outputPath = path.join(runDir, '逐条查看.html')
  await writeFile(outputPath, documentHtml(data), 'utf8')
  console.log(JSON.stringify({ viewer: outputPath, rows: data.rows.length }, null, 2))
}

main().catch(error => {
  console.error(error.stack || error.message)
  process.exitCode = 1
})
