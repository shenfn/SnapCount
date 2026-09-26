const THEMES = [
  { id: 'cyan', name: '芥青微光' },
  { id: 'xuan', name: '玄青须弥' },
  { id: 'paper', name: '宣纸生境' },
  { id: 'jade', name: '竹影鎏金' },
  { id: 'lotus', name: '藕荷余晖' },
  { id: 'tea', name: '苔茶暖金' },
  { id: 'moon', name: '月白远青' },
  { id: 'springWood', name: '枯木逢春' },
  { id: 'temple', name: '古刹苔痕' },
];

const pages = [...document.querySelectorAll('[data-page]')];
const routeButtons = [...document.querySelectorAll('.tab-item[data-route], [data-route]')];
const toastRegion = document.querySelector('.toast-region');
const themeNameInput = document.querySelector('[data-bind="theme-name"]');

function showToast(message) {
  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = message;
  Object.assign(toast.style, {
    position: 'fixed',
    right: '20px',
    bottom: '20px',
    zIndex: '100000',
    padding: '10px 14px',
    borderRadius: '18px',
    color: 'var(--jiezi-color-ink)',
    background: 'var(--jiezi-color-paper)',
    boxShadow: '0 12px 22px color-mix(in srgb, var(--jiezi-color-space) 12%, transparent)',
    font: '400 13px/1.4 system-ui, sans-serif',
  });
  toastRegion.append(toast);
  window.setTimeout(() => toast.remove(), 2000);
}

function currentTheme() {
  return document.documentElement.dataset.theme || 'cyan';
}

function themeLabel(id) {
  return THEMES.find((t) => t.id === id)?.name ?? id;
}

function applyTheme(id, announce = false) {
  document.documentElement.dataset.theme = id;
  if (themeNameInput) themeNameInput.value = themeLabel(id);
  try {
    localStorage.setItem('jiezi.prototype.theme', id);
  } catch {
    /* ignore */
  }
  if (announce) showToast(`主题 · ${themeLabel(id)}`);
}

function cycleTheme() {
  const idx = THEMES.findIndex((t) => t.id === currentTheme());
  const next = THEMES[(idx + 1) % THEMES.length];
  applyTheme(next.id, true);
}

function navigate(pageId, announce = true) {
  const target = pages.find((page) => page.dataset.page === pageId) ?? pages[0];
  pages.forEach((page) => {
    const active = page === target;
    page.hidden = !active;
    page.classList.toggle('is-active', active);
  });
  document.querySelectorAll('.tab-item[data-route]').forEach((button) => {
    const active = button.dataset.route === target.dataset.page;
    button.classList.toggle('is-active', active);
    button.setAttribute('aria-current', active ? 'page' : 'false');
  });
  history.replaceState(null, '', `#${target.dataset.page}`);
  target.scrollTop = 0;
  if (announce) {
    const label = target.getAttribute('aria-label') || target.dataset.page;
    showToast(label);
  }
}

function bindDates() {
  const now = new Date();
  const full = new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  }).format(now);
  const month = new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: 'long',
  }).format(now);
  const fullEl = document.querySelector('[data-bind="full-date"]');
  const monthEl = document.querySelector('[data-bind="month-label"]');
  if (fullEl) fullEl.textContent = full;
  if (monthEl) monthEl.textContent = month;
}

routeButtons.forEach((button) => {
  const route = button.dataset.route;
  if (!route || route === 'capture-hint' || route === 'accounts') return;
  button.addEventListener('click', () => navigate(route));
});

document.querySelector('[data-action="cycle-theme"]')?.addEventListener('click', cycleTheme);
document.querySelector('[data-action="toggle-lab"]')?.addEventListener('click', () => {
  navigate('lab');
});

document.querySelectorAll('.jz-chip').forEach((chip) => {
  chip.addEventListener('click', () => {
    const row = chip.parentElement;
    row?.querySelectorAll('.jz-chip').forEach((c) => c.classList.remove('is-selected'));
    chip.classList.add('is-selected');
  });
});

document.querySelector('[data-route="capture-hint"]')?.addEventListener('click', () => {
  showToast('留下此刻 · 手动 / 相册 / 拍照（后续接线）');
});

/* 首页：速览锚点、趋势柱、组件管理、toast 行 */
document.querySelectorAll('[data-scroll-to]').forEach((el) => {
  el.addEventListener('click', () => {
    const id = `home-${el.dataset.scrollTo}`;
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
});

document.querySelectorAll('[data-toast]').forEach((el) => {
  el.addEventListener('click', () => showToast(el.dataset.toast));
});

const trendSummary = document.querySelector('[data-bind="trend-summary"]');
document.querySelectorAll('.finance-bar-col').forEach((col) => {
  col.addEventListener('click', () => {
    const selected = col.classList.contains('is-selected');
    document.querySelectorAll('.finance-bar-col').forEach((c) => {
      c.classList.remove('is-selected');
      c.querySelector('.finance-bar')?.classList.remove('is-selected');
    });
    if (!selected) {
      col.classList.add('is-selected');
      col.querySelector('.finance-bar')?.classList.add('is-selected');
      const amount = Number(col.dataset.amount || 0);
      const share = amount ? Math.max(1, Math.round((amount / 420) * 100)) : 0;
      const label = col.dataset.trend === 'today' ? '今日' : col.dataset.trend;
      if (trendSummary) trendSummary.textContent = `${label}占比 ${share}%`;
      return;
    }
    if (trendSummary) trendSummary.textContent = '今日占比 38%';
    showToast('进入当天支出明细 · 后续接线');
  });
});

const layoutPanel = document.querySelector('[data-layout-panel]');
document.querySelector('[data-action="open-layout"]')?.addEventListener('click', () => {
  if (layoutPanel) layoutPanel.hidden = false;
});
document.querySelector('[data-action="close-layout"]')?.addEventListener('click', () => {
  if (layoutPanel) layoutPanel.hidden = true;
});
document.querySelector('[data-action="reset-layout"]')?.addEventListener('click', () => {
  document.querySelectorAll('[data-widget-toggle]').forEach((input) => {
    input.checked = true;
  });
  document.querySelectorAll('[data-widget]').forEach((el) => el.classList.remove('widget-hidden'));
  showToast('已恢复默认组件');
});
layoutPanel?.addEventListener('click', (event) => {
  if (event.target === layoutPanel) layoutPanel.hidden = true;
});
document.querySelectorAll('[data-widget-toggle]').forEach((input) => {
  input.addEventListener('change', () => {
    const key = input.dataset.widgetToggle;
    document.querySelectorAll(`[data-widget="${key}"]`).forEach((el) => {
      el.classList.toggle('widget-hidden', !input.checked);
    });
    const enabled = [...document.querySelectorAll('[data-widget-toggle]')].filter((i) => i.checked).length;
    const title = document.querySelector('.home-layout-title');
    if (title) title.textContent = `${enabled} 个首页组件已启用`;
  });
});

/* 记录详情 fixture · 字段对齐 recordDetailAdapters / PageRecordDetail */
const RECORD_FIXTURES = {
  'exp-lunch': {
    kind: 'expense',
    domainLabel: '消费',
    domainBadge: 'badge',
    amount: '-¥28.00',
    amountClass: 'is-expense',
    title: '午餐 · 巷口食堂',
    meta: '12:18 · 本地截图识别',
    imageLabel: '点击查看原始图片',
    hasImage: true,
    basic: [
      ['数据域', '消费', 'badge'],
      ['上传时间', '2026年9月12日 12:20'],
      ['发生时间', '2026年9月12日 12:18'],
      ['来源', '截图识别'],
      ['状态', '已完成', 'badge-success'],
    ],
    fields: [
      ['金额', '-¥28.00', true],
      ['商家名称', '巷口食堂'],
      ['消费渠道', '线下'],
      ['消费分类', '餐饮'],
      ['支付方式', '现金'],
      ['消费日期', '2026年9月12日'],
      ['备注', '和同事一起', false, true],
    ],
    account: {
      status: 'bound',
      mark: '已',
      title: '现金账户',
      reason: '已根据支付方式绑定到「现金」',
    },
    companion: '这顿午饭 28 元，比本周工作日午餐均值低 12%。',
    summary: '系统记录了一笔支出，商家为巷口食堂，金额 28.00 元，渠道线下，分类餐饮。',
  },
  'exp-coffee': {
    kind: 'expense',
    domainLabel: '消费',
    amount: '-¥15.40',
    amountClass: 'is-expense',
    title: '便利店咖啡',
    meta: '09:20 · 截图识别',
    imageLabel: '点击查看原始图片',
    hasImage: true,
    basic: [
      ['数据域', '消费', 'badge'],
      ['上传时间', '2026年9月12日 09:22'],
      ['来源', '截图识别'],
      ['状态', '已完成', 'badge-success'],
    ],
    fields: [
      ['金额', '-¥15.40', true],
      ['商家名称', '便利蜂'],
      ['消费渠道', '支付宝'],
      ['消费分类', '饮品'],
      ['支付方式', '支付宝'],
      ['消费日期', '2026年9月12日'],
      ['备注', '无', false, true],
    ],
    account: {
      status: 'recommended',
      mark: '荐',
      title: '支付宝',
      reason: '渠道匹配「支付宝」，可一键绑定',
      bind: true,
    },
    summary: '系统记录了一笔支出，商家为便利蜂，金额 15.40 元，渠道支付宝，分类饮品。',
  },
  'exp-metro': {
    kind: 'expense',
    domainLabel: '消费',
    amount: '-¥6.00',
    amountClass: 'is-expense',
    title: '地铁通勤',
    meta: '08:42 · 手动补录',
    imageLabel: '暂无图片预览',
    hasImage: false,
    basic: [
      ['数据域', '消费', 'badge'],
      ['上传时间', '2026年9月12日 08:45'],
      ['来源', '手动录入'],
      ['状态', '待补充', 'badge-warning'],
    ],
    fields: [
      ['金额', '-¥6.00', true],
      ['商家名称', '地铁'],
      ['消费渠道', '交通卡'],
      ['消费分类', '交通'],
      ['支付方式', '交通卡'],
      ['消费日期', '2026年9月12日'],
      ['备注', '无', false, true],
    ],
    account: null,
    summary: '系统记录了一笔支出，商家为地铁，金额 6.00 元，渠道交通卡，分类交通。',
  },
  'inc-salary': {
    kind: 'income',
    domainLabel: '收入',
    amount: '+¥2,000.00',
    amountClass: 'is-income',
    title: '项目奖金',
    meta: '09-10 · 手动录入',
    imageLabel: '暂无图片预览',
    hasImage: false,
    basic: [
      ['数据域', '收入', 'badge'],
      ['上传时间', '2026年9月10日 18:02'],
      ['来源', '手动录入'],
    ],
    fields: [
      ['金额', '+¥2,000.00', true],
      ['收入类型', '奖金'],
      ['来源名称', '公司项目组'],
      ['到账日期', '2026年9月10日'],
      ['备注', 'Q3 项目结项', false, true],
    ],
    account: {
      status: 'bound',
      mark: '已',
      title: '银行卡',
      reason: '已绑定到默认收款账户',
    },
    companion: '一笔 2000 元奖金到账，本月收入结构更稳了。',
    summary: '系统记录了一笔奖金收入，金额 2000.00 元，来源为公司项目组。',
  },
  'food-breakfast': {
    kind: 'food',
    domainLabel: '饮食',
    amount: '980 千卡',
    amountClass: '',
    title: '早餐 · 豆浆油条',
    meta: '07:55 · 中转站归档',
    imageLabel: '点击查看原始图片',
    hasImage: true,
    basic: [
      ['数据域', '饮食', 'badge'],
      ['上传时间', '2026年9月12日 08:01'],
      ['发生时间', '2026年9月12日 07:55'],
      ['来源', '中转站归档'],
    ],
    fields: [
      ['标题', '早餐 · 豆浆油条'],
      ['餐次', '早餐'],
      ['总热量', '980 千卡（估算）', true],
      ['菜品数', '3 道'],
      ['记录日期', '2026年9月12日'],
      ['来源类型', '中转站归档'],
      ['估算依据', '按常见份量估算，仅供参考', false, true],
      ['备注', '无', false, true],
    ],
    dishes: [
      { name: '豆浆', kcal: '180 千卡', macros: ['约 300ml', '蛋白 9g', '碳水 12g'] },
      { name: '油条', kcal: '520 千卡', macros: ['约 80g', '蛋白 6g', '脂肪 28g'] },
      { name: '茶叶蛋', kcal: '80 千卡', macros: ['约 50g', '蛋白 7g'] },
    ],
    companion: '早餐蛋白质还可以再高一点，下次可以加个鸡蛋或牛奶。',
    summary: '饮食记录：早餐 · 豆浆油条。',
  },
  'sleep-last': {
    kind: 'sleep',
    domainLabel: '睡眠',
    amount: '7.2h',
    amountClass: '',
    title: '良好',
    meta: '昨夜 · 截图识别',
    imageLabel: '点击查看原始图片',
    hasImage: true,
    basic: [
      ['数据域', '睡眠', 'badge'],
      ['上传时间', '2026年9月12日 07:10'],
      ['来源', '截图识别'],
    ],
    fields: [
      ['标题', '良好'],
      ['质量等级', '良好'],
      ['睡眠时长', '7小时12分', true],
      ['睡眠评分', '82', true],
      ['入睡时间', '9月11日 23:40'],
      ['醒来时间', '9月12日 06:52'],
      ['发生日期', '2026年9月11日'],
      ['模板版本', '1.0'],
      ['来源类型', '截图识别'],
      ['备注', '无', false, true],
    ],
    companion: '连续两天睡够 7 小时，状态会稳很多。',
    summary: '睡眠中记录了「良好」，睡眠时长为 7小时12分。评分 82。',
  },
  'sport-run': {
    kind: 'sport',
    domainLabel: '运动',
    amount: '4.2 km',
    amountClass: '',
    title: '晨跑 · 公园',
    meta: '06:40 · 截图识别',
    imageLabel: '点击查看原始图片',
    hasImage: true,
    basic: [
      ['数据域', '运动', 'badge'],
      ['上传时间', '2026年9月12日 07:05'],
      ['发生时间', '2026年9月12日 06:40'],
      ['来源', '截图识别'],
    ],
    fields: [
      ['标题', '晨跑 · 公园'],
      ['运动类型', '跑步'],
      ['时长', '32 分钟', true],
      ['距离', '4.20 km', true],
      ['发生日期', '2026年9月12日'],
      ['模板版本', '1.0'],
      ['来源类型', '截图识别'],
      ['备注', '配速平稳', false, true],
    ],
    companion: '清晨 4.2 公里，节奏很稳，比上周同路线快了约 1 分钟。',
    summary: '运动中记录了「跑步」，距离为 4.20km。',
  },
};

let detailReturnPage = 'records';

function fieldRow(label, value, numeric, multiline) {
  const cls = ['record-detail-field'];
  if (multiline) cls.push('stacked');
  return `<div class="${cls.join(' ')}">
    <span class="field-label">${label}</span>
    <span class="field-value${numeric ? ' numeric' : ''}${multiline ? ' wrap' : ''}">${value}</span>
  </div>`;
}

function renderRecordDetail(id) {
  const rec = RECORD_FIXTURES[id];
  const root = document.querySelector('[data-bind="record-detail-body"]');
  if (!root) return;
  if (!rec) {
    root.innerHTML = '<div class="jz-empty"><h3>未找到记录</h3><p>原型 fixture 未包含该条。</p></div>';
    return;
  }

  const image = rec.hasImage
    ? `<div class="record-detail-image-card">
        <div class="record-detail-image" role="img" aria-label="来源截图占位"></div>
        <div class="record-detail-image-label">${rec.imageLabel}</div>
      </div>`
    : `<div class="record-detail-image-card">
        <div class="record-detail-image-ph">…</div>
        <div class="record-detail-image-label">${rec.imageLabel}</div>
      </div>`;

  const header = `<div class="record-header-block">
    <div class="record-header-amount ${rec.amountClass || ''}">${rec.amount}</div>
    <div class="record-header-title">${rec.title}</div>
    <div class="record-header-meta">${rec.meta}</div>
  </div>`;

  const basic = rec.basic
    .map(([label, value, badge]) => {
      if (badge) {
        return `<div class="record-detail-field">
          <span class="field-label">${label}</span>
          <span class="field-value"><span class="badge ${badge === 'badge' ? '' : badge}">${value}</span></span>
        </div>`;
      }
      return fieldRow(label, value);
    })
    .join('');

  const extracted = rec.fields
    .map(([label, value, numeric, multiline]) => fieldRow(label, value, numeric, multiline))
    .join('');

  let account = '';
  if (rec.account) {
    const a = rec.account;
    account = `<div class="record-account-card ${a.status}">
      <div class="record-account-mark">${a.mark}</div>
      <div class="record-account-body">
        <div class="record-account-kicker">账户绑定</div>
        <div class="record-account-title">${a.title}</div>
        <div class="record-account-reason">${a.reason}</div>
      </div>
      ${a.bind ? '<button class="record-account-bind-btn" type="button" data-toast="一键绑定 · 后续接线">一键绑定</button>' : ''}
    </div>`;
  }

  let dishes = '';
  if (rec.dishes?.length) {
    dishes = `<div class="record-detail-section">
      <div class="record-detail-section-title">菜品明细 <span class="badge badge-warning">估算值</span></div>
      ${rec.dishes
        .map(
          (d) => `<div class="record-detail-field stacked food-dish-field">
            <div class="food-dish-header">
              <span class="field-label food-dish-name">${d.name}</span>
              <span class="field-value numeric">${d.kcal}</span>
            </div>
            <div class="food-dish-macros">${d.macros.map((m) => `<span>${m}</span>`).join('')}</div>
          </div>`
        )
        .join('')}
    </div>`;
  }

  const companion = rec.companion
    ? `<div class="record-detail-companion">
        <div class="record-detail-companion-mark">💬</div>
        <div class="record-detail-companion-body">
          <div class="record-detail-companion-title">AI 陪伴</div>
          <div class="record-detail-companion-text">${rec.companion}</div>
        </div>
      </div>`
    : '';

  const summary = `<div class="record-detail-section">
    <div class="record-detail-section-title">AI 摘要</div>
    <div class="record-detail-ai-summary">${rec.summary}</div>
  </div>`;

  const actions = `<div class="record-detail-actions">
    <button class="record-detail-btn secondary" type="button" data-toast="${rec.kind === 'expense' && rec.basic.some((b) => b[1] === '待补充') ? '补充信息' : '编辑'} · 后续接线">${rec.kind === 'expense' && rec.basic.some((b) => b[1] === '待补充') ? '补充信息' : '编辑'}</button>
    <button class="record-detail-btn danger" type="button" data-toast="删除确认 · 后续接线">删除</button>
  </div>`;

  root.innerHTML = [image, header, `<div class="record-detail-section"><div class="record-detail-section-title">基本信息</div>${basic}</div>`, `<div class="record-detail-section"><div class="record-detail-section-title">抽取字段</div>${extracted}</div>`, account, dishes, companion, summary, actions]
    .filter(Boolean)
    .join('');

  root.querySelectorAll('[data-toast]').forEach((el) => {
    el.addEventListener('click', () => showToast(el.dataset.toast));
  });
}

function openRecordDetail(id) {
  const currentPage = pages.find((p) => !p.hidden);
  if (currentPage && currentPage.dataset.page !== 'record-detail') {
    detailReturnPage = currentPage.dataset.page;
  }
  renderRecordDetail(id);
  navigate('record-detail', false);
}

document.querySelectorAll('[data-open-record]').forEach((el) => {
  el.addEventListener('click', () => openRecordDetail(el.dataset.openRecord));
});

document.querySelector('[data-action="close-detail"]')?.addEventListener('click', () => {
  navigate(detailReturnPage || 'records', false);
});

/* ========== 中转站 fixture 与交互 ========== */
const INBOX_STATUS = {
  routing_failed: { label: '待分类', tone: 'is-routing' },
  pending_review: { label: '待确认', tone: 'is-review' },
  ai_error: { label: '需重试', tone: 'is-error' },
};

const ARCHIVE_DOMAINS = {
  expense: '消费',
  income: '收入',
  food: '饮食',
  sport: '运动',
  sleep: '睡眠',
  wallet: '钱包',
};

let inboxItems = [
  {
    id: 'stg-1',
    status: 'pending_review',
    scope: 'today',
    day: '今天',
    title: '支付成功截图',
    desc: '识别为消费，金额 25.00，待确认分类',
    context: '消费',
    amount: '-¥25.00',
    merchant: '便利蜂',
    facts: ['支付宝', '饮品', '支付宝'],
    occurred: '今天 10:02',
    uploaded: '今天 10:03',
    hasImage: true,
    suggested: 'expense',
    primary: '收下到消费',
    assurance: 3,
  },
  {
    id: 'stg-2',
    status: 'routing_failed',
    scope: 'today',
    day: '今天',
    title: '聊天截图 · 转账',
    desc: '未能判断数据域，请选择归档方向',
    context: '未分类',
    amount: '—',
    merchant: '微信聊天',
    facts: [],
    occurred: '今天 08:40',
    uploaded: '今天 08:41',
    hasImage: true,
    suggested: null,
    primary: '选择数据域',
    assurance: 1,
  },
  {
    id: 'stg-3',
    status: 'ai_error',
    scope: 'today',
    day: '今天',
    title: '外卖订单页',
    desc: '识别超时，可重试或销毁',
    context: '饮食',
    amount: '—',
    merchant: '美团',
    facts: [],
    occurred: '今天 12:05',
    uploaded: '今天 12:06',
    hasImage: false,
    error: 'AI 识别服务超时（timeout after 30s）',
    suggested: 'food',
    primary: '重试识别',
    assurance: 0,
  },
  {
    id: 'stg-4',
    status: 'pending_review',
    scope: 'all',
    day: '昨天',
    title: '地铁 App 行程',
    desc: '识别为支出 6.00，待确认',
    context: '消费',
    amount: '-¥6.00',
    merchant: '地铁',
    facts: ['交通卡', '交通', '交通卡'],
    occurred: '昨天 18:22',
    uploaded: '昨天 18:25',
    hasImage: true,
    suggested: 'expense',
    primary: '收下到消费',
    assurance: 2,
  },
];

let inboxScope = 'today';
let inboxFilter = 'all';
let verdictIndex = 0;

function inboxVisibleItems() {
  return inboxItems.filter((item) => {
    if (inboxScope === 'today' && item.scope !== 'today') return false;
    if (inboxFilter !== 'all' && item.status !== inboxFilter) return false;
    return true;
  });
}

function updateInboxCounts() {
  const scoped = inboxItems.filter((i) => (inboxScope === 'today' ? i.scope === 'today' : true));
  const counts = { all: scoped.length, routing_failed: 0, pending_review: 0, ai_error: 0 };
  scoped.forEach((i) => {
    if (counts[i.status] != null) counts[i.status] += 1;
  });
  Object.entries(counts).forEach(([key, value]) => {
    const el = document.querySelector(`[data-count="${key}"]`);
    if (el) el.textContent = String(value);
  });
  document.querySelectorAll('[data-inbox-filter]').forEach((btn) => {
    const key = btn.dataset.inboxFilter;
    if (key !== 'all' && !counts[key]) btn.hidden = true;
    else btn.hidden = false;
  });
  const sub = document.querySelector('[data-bind="inbox-subtitle"]');
  if (sub) {
    sub.textContent = counts.all
      ? inboxScope === 'today'
        ? `今天还有 ${counts.all} 条需要你决定`
        : `全部 ${counts.all} 条按发生时间排列`
      : inboxScope === 'today'
        ? '今天没有待处理记录'
        : '当前没有待处理记录';
  }
}

function renderInboxList() {
  const root = document.querySelector('[data-inbox-list]');
  const empty = document.querySelector('[data-inbox-empty]');
  if (!root) return;
  const items = inboxVisibleItems();
  if (!items.length) {
    root.innerHTML = '';
    if (empty) empty.hidden = false;
    updateInboxCounts();
    return;
  }
  if (empty) empty.hidden = true;

  const byDay = new Map();
  items.forEach((item) => {
    if (!byDay.has(item.day)) byDay.set(item.day, []);
    byDay.get(item.day).push(item);
  });

  root.innerHTML = [...byDay.entries()]
    .map(
      ([day, list]) => `<section class="pending-film-group">
        <div class="pending-date-label">${day}</div>
        <div class="pending-film-grid">
          ${list
            .map((item) => {
              const st = INBOX_STATUS[item.status] || INBOX_STATUS.pending_review;
              const visual = item.hasImage
                ? `<span class="pending-film-visual has-image" aria-hidden="true"></span>
                   <span class="pending-film-scrim"><strong>${item.title}</strong><small>${item.desc}</small></span>`
                : `<span class="pending-film-visual is-fact">
                     <span class="pending-film-fact">
                       <small>${item.merchant}</small>
                       <strong>${item.title}</strong>
                       ${item.amount !== '—' ? `<b>${item.amount}</b>` : ''}
                       <small>${item.facts.length ? item.facts.join(' · ') : item.desc}</small>
                     </span>
                   </span>`;
              return `<button class="pending-film-card" type="button" data-open-verdict="${item.id}">
                <span class="pending-film-visual-wrap" style="position:relative;display:block">
                  ${visual}
                  <span class="pending-film-state ${st.tone}"><i></i>${st.label}</span>
                </span>
                <span class="pending-film-caption">
                  <strong>${item.title}</strong>
                  <span class="pending-film-caption-domain">${item.context}</span>
                  <span class="pending-time-stack">
                    <span><i>记录</i>${item.occurred}</span>
                    <span><i>上传</i>${item.uploaded}</span>
                  </span>
                </span>
              </button>`;
            })
            .join('')}
        </div>
      </section>`
    )
    .join('');

  root.querySelectorAll('[data-open-verdict]').forEach((btn) => {
    btn.addEventListener('click', () => openVerdict(btn.dataset.openVerdict));
  });
  updateInboxCounts();
}

function openVerdict(id) {
  const list = inboxVisibleItems();
  verdictIndex = Math.max(0, list.findIndex((i) => i.id === id));
  paintVerdict();
  const stage = document.querySelector('[data-verdict-stage]');
  if (stage) stage.hidden = false;
}

function closeVerdict() {
  const stage = document.querySelector('[data-verdict-stage]');
  if (stage) stage.hidden = true;
}

function paintVerdict() {
  const list = inboxVisibleItems();
  if (!list.length) {
    closeVerdict();
    return;
  }
  verdictIndex = Math.max(0, Math.min(verdictIndex, list.length - 1));
  const item = list[verdictIndex];
  const st = INBOX_STATUS[item.status] || INBOX_STATUS.pending_review;
  const set = (key, value) => {
    const el = document.querySelector(`[data-bind="${key}"]`);
    if (el) el.textContent = value;
  };
  set('verdict-state', '');
  const stateEl = document.querySelector('[data-bind="verdict-state"]');
  if (stateEl) stateEl.innerHTML = `<i></i>${st.label} · ${item.context}`;
  set('verdict-counter', `${verdictIndex + 1} / ${list.length}`);
  set('verdict-title', item.title);
  set('verdict-desc', item.desc);
  set('verdict-occurred', item.occurred);
  set('verdict-uploaded', item.uploaded);
  set('verdict-primary', item.primary);

  const photo = document.querySelector('[data-bind="verdict-photo"]');
  if (photo) {
    photo.classList.toggle('has-shot', item.hasImage);
    photo.dataset.label = item.hasImage ? '来源截图\n（原型占位）' : '原图未保留\n依据文字事实';
  }

  const assurance = document.querySelector('[data-bind="verdict-assurance"]');
  if (assurance) {
    const n = item.assurance || 0;
    const label = n >= 3 ? '较高把握' : n === 2 ? '一般把握' : n === 1 ? '把握较低' : '待重试';
    assurance.innerHTML = `${[1, 2, 3].map((d) => `<i class="${d <= n ? 'on' : ''}"></i>`).join('')}${label}`;
  }

  const err = document.querySelector('[data-bind="verdict-error"]');
  if (err) {
    if (item.error) {
      err.hidden = false;
      err.textContent = item.error;
    } else {
      err.hidden = true;
      err.textContent = '';
    }
  }

  document.querySelectorAll('[data-verdict-domain]').forEach((btn) => {
    btn.classList.toggle('is-current', item.suggested && btn.dataset.verdictDomain === item.suggested);
  });
}

function archiveCurrentVerdict(domainKey) {
  const list = inboxVisibleItems();
  const item = list[verdictIndex];
  if (!item) return;
  const domain = ARCHIVE_DOMAINS[domainKey] || item.context;
  showToast(`已收下到「${domain}」`);
  inboxItems = inboxItems.filter((i) => i.id !== item.id);
  if (!inboxVisibleItems().length) closeVerdict();
  else paintVerdict();
  renderInboxList();
}

document.querySelectorAll('[data-inbox-scope]').forEach((btn) => {
  btn.addEventListener('click', () => {
    inboxScope = btn.dataset.inboxScope;
    document.querySelectorAll('[data-inbox-scope]').forEach((b) => b.classList.toggle('is-active', b === btn));
    renderInboxList();
  });
});

document.querySelectorAll('[data-inbox-filter]').forEach((btn) => {
  btn.addEventListener('click', () => {
    inboxFilter = btn.dataset.inboxFilter;
    document.querySelectorAll('[data-inbox-filter]').forEach((b) => b.classList.toggle('is-active', b === btn));
    renderInboxList();
  });
});

document.querySelector('[data-action="close-verdict"]')?.addEventListener('click', closeVerdict);
document.querySelector('[data-action="verdict-prev"]')?.addEventListener('click', () => {
  verdictIndex -= 1;
  paintVerdict();
});
document.querySelector('[data-action="verdict-next"]')?.addEventListener('click', () => {
  verdictIndex += 1;
  paintVerdict();
});
document.querySelector('[data-action="verdict-archive"]')?.addEventListener('click', () => {
  const list = inboxVisibleItems();
  const item = list[verdictIndex];
  if (!item) return;
  if (!item.suggested) {
    showToast('请在下方选择数据域');
    return;
  }
  archiveCurrentVerdict(item.suggested);
});
document.querySelector('[data-action="verdict-adjust"]')?.addEventListener('click', () => {
  showToast('调整 · 选择下方数据域即可改判');
});
document.querySelector('[data-action="verdict-retry"]')?.addEventListener('click', () => {
  showToast('已排队重试识别');
});
document.querySelector('[data-action="verdict-discard"]')?.addEventListener('click', () => {
  const list = inboxVisibleItems();
  const item = list[verdictIndex];
  if (!item) return;
  showToast('已销毁');
  inboxItems = inboxItems.filter((i) => i.id !== item.id);
  if (!inboxVisibleItems().length) closeVerdict();
  else paintVerdict();
  renderInboxList();
});
document.querySelectorAll('[data-verdict-domain]').forEach((btn) => {
  btn.addEventListener('click', () => archiveCurrentVerdict(btn.dataset.verdictDomain));
});
document.querySelector('[data-action="toggle-processed"]')?.addEventListener('click', (e) => {
  const box = document.querySelector('[data-inbox-processed]');
  if (!box) return;
  box.hidden = !box.hidden;
  const label = e.currentTarget.childNodes[0];
  if (label?.nodeType === Node.TEXT_NODE) label.textContent = box.hidden ? '展开' : '收起';
});

renderInboxList();

/* ========== 设置交互 ========== */
document.querySelectorAll('[data-toggle-setting]').forEach((btn) => {
  btn.addEventListener('click', () => {
    const on = btn.getAttribute('aria-checked') === 'true';
    btn.setAttribute('aria-checked', on ? 'false' : 'true');
    const input = btn.querySelector('input');
    if (input) input.checked = !on;
    const title = btn.closest('.jz-row')?.querySelector('.jz-row-title')?.textContent || '设置';
    showToast(`${title} · ${!on ? '已开启' : '已关闭'}`);
  });
});

document.querySelectorAll('[data-chip-group]').forEach((group) => {
  group.querySelectorAll('.jz-chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      group.querySelectorAll('.jz-chip').forEach((c) => c.classList.remove('is-selected'));
      chip.classList.add('is-selected');
      if (group.dataset.chipGroup === 'retention') {
        const label = document.querySelector('[data-bind="retention-label"]');
        if (label) label.textContent = chip.textContent.trim();
        showToast(`原图留存 · ${chip.textContent.trim()}`);
      }
    });
  });
});

const exportPanel = document.querySelector('[data-export-panel]');
document.querySelector('[data-action="open-export"]')?.addEventListener('click', () => {
  if (exportPanel) exportPanel.hidden = false;
});
document.querySelector('[data-action="close-export"]')?.addEventListener('click', () => {
  if (exportPanel) exportPanel.hidden = true;
});
document.querySelector('[data-action="do-export"]')?.addEventListener('click', () => {
  showToast('已开始导出（原型演示）');
  if (exportPanel) exportPanel.hidden = true;
});
exportPanel?.addEventListener('click', (e) => {
  if (e.target === exportPanel) exportPanel.hidden = true;
});

/* ========== 账户 fixture 与详情 ========== */
const ACCOUNT_FIXTURES = {
  'acc-cash': {
    title: '现金',
    subtitle: '现金 · 本地账户',
    kicker: 'ASSET ACCOUNT',
    balance: '¥860.00',
    caption: '当前可用余额',
    liability: false,
    stats: [
      ['初始余额', '¥1,000.00'],
      ['有效流水净额', '-¥140.00', 'negative'],
      ['账户类型', '现金'],
      ['有效流水数', '18'],
    ],
    txs: [
      { title: '午餐 · 巷口食堂', sub: '今天 12:18 · 消费', amount: '-¥28.00', dir: 'is-out' },
      { title: '早餐 · 豆浆油条', sub: '今天 07:55 · 消费', amount: '-¥12.00', dir: 'is-out' },
      { title: '提现转入', sub: '昨天 20:10 · 转账', amount: '+¥200.00', dir: 'is-in' },
    ],
  },
  'acc-alipay': {
    title: '支付宝',
    subtitle: '电子钱包',
    kicker: 'ASSET ACCOUNT',
    balance: '¥1,240.50',
    caption: '当前可用余额',
    liability: false,
    stats: [
      ['初始余额', '¥0.00'],
      ['有效流水净额', '+¥1,240.50', 'positive'],
      ['账户类型', '电子钱包'],
      ['有效流水数', '42'],
    ],
    txs: [
      { title: '便利店咖啡', sub: '今天 09:20 · 消费', amount: '-¥15.40', dir: 'is-out' },
      { title: '转账收入', sub: '9月10日 · 收入', amount: '+¥500.00', dir: 'is-in' },
    ],
  },
  'acc-bank': {
    title: '银行卡',
    subtitle: '储蓄卡 · 招商银行',
    kicker: 'ASSET ACCOUNT',
    balance: '¥1,159.50',
    caption: '默认收入账户',
    liability: false,
    stats: [
      ['初始余额', '¥0.00'],
      ['有效流水净额', '+¥1,159.50', 'positive'],
      ['账户类型', '储蓄卡'],
      ['有效流水数', '6'],
    ],
    txs: [
      { title: '项目奖金', sub: '9月10日 · 收入', amount: '+¥2,000.00', dir: 'is-in' },
      { title: '转入支付宝', sub: '昨天 20:10 · 转账', amount: '-¥200.00', dir: 'is-out' },
    ],
  },
  'acc-cmb': {
    title: '招商信用卡',
    subtitle: '信用卡 · 每月 18 日还款',
    kicker: 'LIABILITY ACCOUNT',
    balance: '-¥860.00',
    caption: '当前欠款估算',
    liability: true,
    cycle: { amount: '¥860', scope: '2026-09 账单' },
    repayment: {
      status: '待还',
      statusDesc: '本期账单未结清，还款日 09-18',
      rows: [
        ['本期状态', '待还'],
        ['本期应还', '¥860.00'],
        ['已还 / 剩余', '¥0.00 / ¥860.00'],
        ['周期结束日', '每月 5 日'],
        ['还款日', '每月 18 日'],
        ['最近待还', '09-18'],
        ['自动扣款', '支付宝'],
        ['自动确认', '需手动确认'],
      ],
    },
    stats: [
      ['初始余额', '¥0.00'],
      ['有效流水净额', '-¥860.00', 'negative'],
      ['账户类型', '信用卡'],
      ['有效流水数', '9'],
    ],
    txs: [
      { title: '数码配件', sub: '9月8日 · 消费', amount: '-¥320.00', dir: 'is-out' },
      { title: '餐饮合计', sub: '9月3日 · 消费', amount: '-¥186.00', dir: 'is-out' },
      { title: '上期还款', sub: '8月18日 · 还款', amount: '+¥1,200.00', dir: 'is-in' },
    ],
  },
  'acc-huabei': {
    title: '花呗',
    subtitle: '信用支付 · 每月 10 日还款',
    kicker: 'LIABILITY ACCOUNT',
    balance: '-¥260.00',
    caption: '当前欠款估算',
    liability: true,
    cycle: { amount: '¥260', scope: '2026-09 账单' },
    repayment: {
      status: '本期已还清',
      statusDesc: '自动扣款已确认',
      rows: [
        ['本期状态', '已还清'],
        ['本期应还', '¥260.00'],
        ['已还 / 剩余', '¥260.00 / ¥0.00'],
        ['周期结束日', '每月 1 日'],
        ['还款日', '每月 10 日'],
        ['最近待还', '10-10'],
        ['自动扣款', '余额宝'],
        ['自动确认', '高置信度截图可自动确认'],
      ],
    },
    stats: [
      ['初始余额', '¥0.00'],
      ['有效流水净额', '-¥260.00', 'negative'],
      ['账户类型', '信用支付'],
      ['有效流水数', '4'],
    ],
    txs: [
      { title: '外卖', sub: '9月1日 · 消费', amount: '-¥48.00', dir: 'is-out' },
      { title: '本期还款', sub: '9月10日 · 还款', amount: '+¥310.00', dir: 'is-in' },
    ],
  },
  'acc-archived': {
    title: '旧校园卡',
    subtitle: '已归档',
    kicker: 'ASSET ACCOUNT',
    balance: '¥12.00',
    caption: '归档账户 · 不参与合计',
    liability: false,
    archived: true,
    stats: [
      ['初始余额', '¥50.00'],
      ['有效流水净额', '-¥38.00', 'negative'],
      ['账户类型', '储值卡'],
      ['有效流水数', '3'],
    ],
    txs: [{ title: '食堂消费', sub: '2025年12月 · 消费', amount: '-¥8.00', dir: 'is-out' }],
  },
};

let accountReturnPage = 'today';
let accountDetailFrom = 'accounts';

function openAccounts(returnPage) {
  const current = pages.find((p) => !p.hidden);
  accountReturnPage = returnPage || (current && current.dataset.page !== 'accounts' ? current.dataset.page : 'today');
  navigate('accounts', false);
}

function openAccountDetail(id) {
  const rec = ACCOUNT_FIXTURES[id];
  const root = document.querySelector('[data-bind="account-detail-body"]');
  const title = document.querySelector('[data-bind="account-title"]');
  const sub = document.querySelector('[data-bind="account-subtitle"]');
  const current = pages.find((p) => !p.hidden);
  accountDetailFrom = current?.dataset.page === 'accounts' ? 'accounts' : current?.dataset.page || 'today';
  if (!rec || !root) {
    navigate('account-detail', false);
    return;
  }
  if (title) title.textContent = rec.title;
  if (sub) sub.textContent = rec.subtitle;

  const hero = `<section class="account-hero-card${rec.liability ? ' liability' : ''}">
    <div>
      <div class="account-hero-kicker">${rec.kicker}</div>
      <div class="account-hero-balance">${rec.balance}</div>
      <div class="account-hero-caption">${rec.caption}</div>
      ${rec.cycle ? `<div class="account-hero-subline"><span>本期 ${rec.cycle.amount}</span><span>${rec.cycle.scope}</span></div>` : ''}
    </div>
    <div class="account-hero-mark">${rec.liability ? '还' : '钱'}</div>
  </section>`;

  const manage = `<section class="account-source-card">
    <div class="wallet-account-section-title">账户使用状态</div>
    <p class="jz-status-line" style="margin:0">${rec.archived ? '恢复不会自动还原默认项或自动扣款关系。' : '归档会保留余额、流水和还款历史，并清除默认项。'}</p>
    <button class="record-detail-btn secondary" type="button" style="margin-top:10px;width:100%" data-toast="${rec.archived ? '恢复账户' : '归档账户'} · 后续接线">${rec.archived ? '恢复账户' : '归档账户'}</button>
  </section>`;

  const stats = `<section class="account-detail-grid">${rec.stats
    .map(
      ([label, value, tone]) =>
        `<div class="account-stat-card"><span>${label}</span><strong class="${tone || ''}">${value}</strong></div>`
    )
    .join('')}</section>`;

  let repayment = '';
  if (rec.repayment) {
    const r = rec.repayment;
    repayment = `<section class="account-repayment-panel">
      <div class="wallet-account-section-title">还款计划</div>
      <div class="account-repayment-status"><strong>${r.status}</strong><span>${r.statusDesc}</span></div>
      ${r.rows.map(([k, v]) => `<div class="account-repayment-row"><span>${k}</span><strong>${v}</strong></div>`).join('')}
      <div class="account-repayment-actions">
        <div class="account-repayment-mode">
          <button class="account-repayment-mode-btn active" type="button">还清本期</button>
          <button class="account-repayment-mode-btn" type="button" data-toast="记录部分还款 · 后续接线">记录部分还款</button>
        </div>
        <button class="jz-btn jz-btn--primary" type="button" data-toast="确认还款 · 后续接线">确认还款</button>
      </div>
    </section>`;
  }

  const txs = `<section class="record-detail-section">
    <div class="record-detail-section-title">最近流水</div>
    ${rec.txs
      .map(
        (t) => `<div class="wallet-tx-row">
          <div class="wallet-tx-main">
            <div class="wallet-tx-title">${t.title}</div>
            <div class="wallet-tx-sub">${t.sub}</div>
          </div>
          <div class="wallet-tx-amount ${t.dir}">${t.amount}</div>
        </div>`
      )
      .join('')}
  </section>`;

  root.innerHTML = [hero, manage, stats, repayment, txs].filter(Boolean).join('');
  root.querySelectorAll('[data-toast]').forEach((el) => {
    el.addEventListener('click', () => showToast(el.dataset.toast));
  });
  navigate('account-detail', false);
}

document.querySelectorAll('[data-route="accounts"]').forEach((el) => {
  el.addEventListener('click', (e) => {
    e.preventDefault();
    openAccounts();
  });
});
document.querySelectorAll('[data-open-account]').forEach((el) => {
  el.addEventListener('click', () => openAccountDetail(el.dataset.openAccount));
});
document.querySelector('[data-action="close-accounts"]')?.addEventListener('click', () => {
  navigate(accountReturnPage || 'today', false);
});
document.querySelector('[data-action="close-account-detail"]')?.addEventListener('click', () => {
  navigate(accountDetailFrom === 'accounts' ? 'accounts' : accountDetailFrom || 'today', false);
});

// 首页数据域「钱包」也可进账户列表
document.querySelectorAll('.domain-quick-card').forEach((card) => {
  if (card.textContent.includes('钱包')) {
    card.addEventListener('click', () => openAccounts('today'));
  }
});

let saved = 'cyan';
try {
  saved = localStorage.getItem('jiezi.prototype.theme') || 'cyan';
} catch {
  /* ignore */
}
if (!THEMES.some((t) => t.id === saved)) saved = 'cyan';
applyTheme(saved, false);
bindDates();
navigate(window.location.hash.slice(1) || 'today', false);
