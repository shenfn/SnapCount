# Wallet V1-A Accounts + Snapshots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first safe wallet-account foundation: account tables, minimal ledger support, Data API grants, existing wallet snapshot compatibility, and a UI path to create/link accounts from wallet snapshots without changing expense/income balances.

**Architecture:** Keep the existing `wallet` universal domain as the screenshot-recognition entry point and evidence layer. Add `accounts` and `account_entries` as the authoritative account layer, then let the frontend display accounts above existing wallet snapshots and allow snapshot-to-account initialization/linking. Do not wire expense/income auto balance changes in this phase.

**Tech Stack:** Vue 3, Vite, Supabase JS v2, Supabase Postgres migrations, existing `data_records` universal domain, existing `ingest-receipt` Edge Function.

---

## Scope Boundaries

**In scope:**
- Create `public.accounts` and `public.account_entries`.
- Add Data API `GRANT`, RLS, and policies for new tables.
- Add optional wallet snapshot linkage fields to `data_records`.
- Load accounts in `useStore.js`.
- Create account from a wallet snapshot.
- Link an existing account to a wallet snapshot.
- Render wallet domain as account asset/liability sections plus historical snapshots.
- Enhance wallet AI payload normalization with `snapshot_balance`, `account_snapshot_kind`, `institution`, and normalized account type.

**Out of scope:**
- Expense screenshot auto-deducting from accounts.
- Income screenshot auto-adding to accounts.
- Full staging account confirmation for expenses/income.
- Transfer, repayment, and balance adjustment workflows.
- Full rule-management UI.

---

## File Structure

### Create
- `supabase/migrations/022_wallet_accounts_v1a.sql`
  - Creates `accounts`, `account_entries`.
  - Adds wallet snapshot linkage columns to `data_records`.
  - Adds constraints, indexes, RLS, policies, explicit Data API grants.

- `src/adapters/domain/accountAdapter.js`
  - Pure mapping/format helpers for account display.
  - Keeps account aggregation out of Vue components.

### Modify
- `src/composables/useStore.js`
  - Add `accounts` state.
  - Load accounts in `loadData`.
  - Add `createAccountFromWalletSnapshot(record)`.
  - Add `linkWalletSnapshotToAccount(record, accountId)`.
  - Add account row mapper.

- `src/adapters/domain/walletAdapter.js`
  - Prefer `store.accounts` for asset/liability metrics and sections.
  - Keep existing snapshot fallback when no accounts exist.
  - Add recent snapshot actions metadata.

- `src/components/pages/PageDomainDetail.vue`
  - For wallet domain, show account sections before existing charts/lists.
  - Add buttons for unlinked wallet snapshots: create account, link existing account.

- `src/domains/registry.js`
  - Add wallet schema fallback fields: `snapshot_balance`, `account_snapshot_kind`, `institution`, `last4`, `linked_account_id`.

- `src/domains/universalFormAdapter.js`
  - Ensure wallet manual records store `snapshot_balance` and `account_snapshot_kind` consistently.

- `supabase/functions/ingest-receipt/index.ts`
  - Normalize wallet payload fields for account snapshots.

- `src/styles/main.css`
  - Add wallet account section/card styles.

### Verification
- `npm run build`
- Static review of migration SQL for `GRANT`, RLS, policies, and constraints.
- Manual smoke scenarios listed in Task 8.

---

## Task 1: Database Migration for Accounts and Minimal Entries

**Files:**
- Create: `supabase/migrations/022_wallet_accounts_v1a.sql`

- [ ] **Step 1: Create the migration file with accounts, entries, snapshot linkage, RLS, policies, and grants**

Write this file exactly, then adjust only if existing migration history proves a column already exists:

```sql
-- ════════════════════════════════════════════════════════════════════
-- 022_wallet_accounts_v1a.sql
-- Wallet V1-A: accounts foundation + minimal account entries + wallet snapshot linkage
-- ════════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp";

do $$
begin
  if not exists (select 1 from pg_type where typname = 'account_type') then
    create type public.account_type as enum (
      'cash',
      'wallet_balance',
      'debit_card',
      'credit_card',
      'credit_line',
      'other'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'account_entry_direction') then
    create type public.account_entry_direction as enum ('in', 'out');
  end if;

  if not exists (select 1 from pg_type where typname = 'account_entry_type') then
    create type public.account_entry_type as enum (
      'opening_balance',
      'snapshot_initialization',
      'expense',
      'income',
      'transfer',
      'adjustment'
    );
  end if;
end $$;

create table if not exists public.accounts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  type public.account_type not null default 'other',
  institution text,
  last4 text,
  currency text not null default 'CNY',
  initial_balance numeric(14,2) not null default 0 check (initial_balance >= 0),
  current_balance numeric(14,2) not null default 0 check (current_balance >= 0),
  snapshot_balance numeric(14,2) check (snapshot_balance is null or snapshot_balance >= 0),
  snapshot_at timestamptz,
  source_record_table text,
  source_record_id uuid,
  is_default_expense boolean not null default false,
  is_default_income boolean not null default false,
  is_archived boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_last4_format check (last4 is null or last4 ~ '^[0-9]{4}$')
);

create table if not exists public.account_entries (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  direction public.account_entry_direction not null,
  amount numeric(14,2) not null check (amount > 0),
  entry_type public.account_entry_type not null,
  source_table text,
  source_id uuid,
  occurred_at timestamptz not null default now(),
  note text,
  is_voided boolean not null default false,
  voided_reason text,
  created_at timestamptz not null default now()
);

create index if not exists idx_accounts_user_archived_sort
  on public.accounts (user_id, is_archived, sort_order, created_at desc);

create index if not exists idx_accounts_user_type
  on public.accounts (user_id, type);

create index if not exists idx_account_entries_account_time
  on public.account_entries (account_id, occurred_at desc);

create index if not exists idx_account_entries_source
  on public.account_entries (source_table, source_id);

create unique index if not exists uq_account_entries_active_source
  on public.account_entries (source_table, source_id, entry_type, account_id)
  where is_voided = false and source_table is not null and source_id is not null;

alter table public.data_records
  add column if not exists linked_account_id uuid references public.accounts(id) on delete set null,
  add column if not exists account_snapshot_kind text check (account_snapshot_kind is null or account_snapshot_kind in ('asset', 'liability')),
  add column if not exists snapshot_balance numeric(14,2) check (snapshot_balance is null or snapshot_balance >= 0),
  add column if not exists snapshot_at timestamptz;

create index if not exists idx_data_records_linked_account
  on public.data_records (linked_account_id);

alter table public.accounts enable row level security;
alter table public.account_entries enable row level security;

drop policy if exists "accounts_user_access" on public.accounts;
create policy "accounts_user_access"
  on public.accounts
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "account_entries_user_access" on public.account_entries;
create policy "account_entries_user_access"
  on public.account_entries
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.accounts to authenticated;
grant select, insert, update, delete on table public.account_entries to authenticated;
grant all privileges on table public.accounts, public.account_entries to service_role;
```

- [ ] **Step 2: Static migration review**

Verify the migration contains all of these strings:

```text
create table if not exists public.accounts
create table if not exists public.account_entries
alter table public.accounts enable row level security
alter table public.account_entries enable row level security
grant select, insert, update, delete on table public.accounts to authenticated
grant select, insert, update, delete on table public.account_entries to authenticated
```

Expected: all strings are present.

---

## Task 2: Account Display Adapter

**Files:**
- Create: `src/adapters/domain/accountAdapter.js`

- [ ] **Step 1: Create account adapter helpers**

```js
export function normalizeAccountType(type) {
  const value = String(type || '').trim()
  if (['cash', 'wallet_balance', 'debit_card', 'credit_card', 'credit_line', 'other'].includes(value)) return value
  if (['wechat', 'alipay', 'balance'].includes(value)) return 'wallet_balance'
  if (['bank_card', 'bank', 'debit'].includes(value)) return 'debit_card'
  if (['huabei', 'jd_baitiao', 'douyin_monthly'].includes(value)) return 'credit_line'
  return 'other'
}

export function isLiabilityAccount(account) {
  return ['credit_card', 'credit_line'].includes(account?.type)
}

export function formatAccountCurrency(value) {
  const amount = Number(value || 0)
  return `¥${amount.toFixed(2)}`
}

export function mapAccountRow(row) {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    type: normalizeAccountType(row.type),
    institution: row.institution || '',
    last4: row.last4 || '',
    currency: row.currency || 'CNY',
    initialBalance: Number(row.initial_balance || 0),
    currentBalance: Number(row.current_balance || 0),
    snapshotBalance: row.snapshot_balance == null ? null : Number(row.snapshot_balance),
    snapshotAt: row.snapshot_at || null,
    sourceRecordTable: row.source_record_table || '',
    sourceRecordId: row.source_record_id || '',
    isDefaultExpense: !!row.is_default_expense,
    isDefaultIncome: !!row.is_default_income,
    isArchived: !!row.is_archived,
    sortOrder: Number(row.sort_order || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function accountTitle(account) {
  if (!account) return '未知账户'
  if (account.last4) return `${account.name}（${account.last4}）`
  return account.name || account.institution || '未命名账户'
}

export function splitAccounts(accounts) {
  const active = (accounts || []).filter(account => !account.isArchived)
  return {
    assets: active.filter(account => !isLiabilityAccount(account)),
    liabilities: active.filter(isLiabilityAccount),
  }
}
```

- [ ] **Step 2: Check importability with build later**

No command yet; Task 8 runs the full build.

---

## Task 3: Store Account State and Snapshot Actions

**Files:**
- Modify: `src/composables/useStore.js`

- [ ] **Step 1: Add adapter import**

Add near existing imports:

```js
import { mapAccountRow, normalizeAccountType } from '../adapters/domain/accountAdapter'
```

- [ ] **Step 2: Add accounts state**

Near other top-level refs, add:

```js
const accounts = ref([])
```

- [ ] **Step 3: Load accounts inside `loadData`**

After universal records load and before staging load, insert:

```js
      const { data: accountRows, error: accountErr } = await sb.from('accounts')
        .select('*')
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: true })
      if (accountErr) {
        console.warn('加载账户失败:', accountErr.message)
        accounts.value = []
      } else {
        accounts.value = (accountRows || []).map(mapAccountRow)
      }
```

- [ ] **Step 4: Add wallet snapshot normalization helpers**

Place near other helper functions inside `useStore`:

```js
function walletSnapshotKindOf(record) {
  const payload = record?.payload || {}
  if (payload.account_snapshot_kind === 'asset' || payload.account_snapshot_kind === 'liability') return payload.account_snapshot_kind
  return payload.record_kind === 'liability_snapshot' ? 'liability' : 'asset'
}

function accountTypeFromWalletSnapshot(record) {
  const payload = record?.payload || {}
  const normalized = normalizeAccountType(payload.account_type)
  if (normalized !== 'other') return normalized
  return walletSnapshotKindOf(record) === 'liability' ? 'credit_line' : 'wallet_balance'
}

function amountFromWalletSnapshot(record) {
  const payload = record?.payload || {}
  const value = payload.snapshot_balance ?? payload.amount
  const amount = Number(value)
  return Number.isFinite(amount) && amount >= 0 ? amount : 0
}
```

- [ ] **Step 5: Add create account from snapshot action**

Add inside `useStore`:

```js
async function createAccountFromWalletSnapshot(record) {
  if (!record || record.domainKey !== 'wallet') {
    showFlash('只能从钱包快照创建账户')
    return
  }
  if (!currentUserId.value) {
    showFlash('请先登录后再创建账户')
    return
  }
  const payload = record.payload || {}
  const amount = amountFromWalletSnapshot(record)
  const now = new Date().toISOString()
  const body = {
    user_id: currentUserId.value,
    name: payload.account_name || record.title || '未命名账户',
    type: accountTypeFromWalletSnapshot(record),
    institution: payload.institution || payload.account_name || null,
    last4: payload.last4 && /^\d{4}$/.test(String(payload.last4)) ? String(payload.last4) : null,
    currency: 'CNY',
    initial_balance: amount,
    current_balance: amount,
    snapshot_balance: amount,
    snapshot_at: record.occurredAt || record.createdAt || now,
    source_record_table: 'data_records',
    source_record_id: record.id,
  }

  const { data: accountRow, error: accountErr } = await sb.from('accounts')
    .insert(body)
    .select('*')
    .single()
  if (accountErr) {
    alert('创建账户失败：' + humanizeDbError(accountErr))
    return
  }

  const { error: linkErr } = await sb.from('data_records')
    .update({
      linked_account_id: accountRow.id,
      account_snapshot_kind: walletSnapshotKindOf(record),
      snapshot_balance: amount,
      snapshot_at: record.occurredAt || record.createdAt || now,
      payload_jsonb: {
        ...payload,
        linked_account_id: accountRow.id,
        account_snapshot_kind: walletSnapshotKindOf(record),
        snapshot_balance: amount,
      },
    })
    .eq('id', record.id)
  if (linkErr) {
    alert('账户已创建，但关联快照失败：' + humanizeDbError(linkErr))
    await loadData(0, true)
    return
  }

  accounts.value.unshift(mapAccountRow(accountRow))
  const idx = dataRecords.value.findIndex(item => item.id === record.id)
  if (idx >= 0) {
    dataRecords.value[idx] = {
      ...dataRecords.value[idx],
      payload: {
        ...payload,
        linked_account_id: accountRow.id,
        account_snapshot_kind: walletSnapshotKindOf(record),
        snapshot_balance: amount,
      },
    }
  }
  showFlash('✓ 已从快照创建账户')
}
```

- [ ] **Step 6: Add link existing account action**

```js
async function linkWalletSnapshotToAccount(record, accountId) {
  if (!record || record.domainKey !== 'wallet' || !accountId) return
  const payload = record.payload || {}
  const amount = amountFromWalletSnapshot(record)
  const snapshotAt = record.occurredAt || record.createdAt || new Date().toISOString()

  const { error: accountErr } = await sb.from('accounts')
    .update({
      snapshot_balance: amount,
      snapshot_at: snapshotAt,
      source_record_table: 'data_records',
      source_record_id: record.id,
      updated_at: new Date().toISOString(),
    })
    .eq('id', accountId)
  if (accountErr) {
    alert('更新账户快照失败：' + humanizeDbError(accountErr))
    return
  }

  const { error: recordErr } = await sb.from('data_records')
    .update({
      linked_account_id: accountId,
      account_snapshot_kind: walletSnapshotKindOf(record),
      snapshot_balance: amount,
      snapshot_at: snapshotAt,
      payload_jsonb: {
        ...payload,
        linked_account_id: accountId,
        account_snapshot_kind: walletSnapshotKindOf(record),
        snapshot_balance: amount,
      },
    })
    .eq('id', record.id)
  if (recordErr) {
    alert('账户快照已更新，但记录关联失败：' + humanizeDbError(recordErr))
    await loadData(0, true)
    return
  }

  await loadData(0, true)
  showFlash('✓ 已关联账户')
}
```

- [ ] **Step 7: Export new state/actions**

In the returned store object, include:

```js
accounts,
createAccountFromWalletSnapshot,
linkWalletSnapshotToAccount,
```

---

## Task 4: Wallet Adapter Uses Accounts While Keeping Snapshot Fallback

**Files:**
- Modify: `src/adapters/domain/walletAdapter.js`

- [ ] **Step 1: Import account helpers**

```js
import { accountTitle, formatAccountCurrency, splitAccounts } from './accountAdapter'
```

- [ ] **Step 2: Update metrics to prefer accounts**

Replace `getMetricItems` with:

```js
export function getMetricItems(store) {
  const accounts = store.accounts?.value || []
  if (accounts.length) {
    const { assets, liabilities } = splitAccounts(accounts)
    const assetTotal = assets.reduce((sum, account) => sum + Number(account.currentBalance || 0), 0)
    const liabilityTotal = liabilities.reduce((sum, account) => sum + Number(account.currentBalance || 0), 0)
    return [
      { label: '资产合计', value: formatAccountCurrency(assetTotal), accent: true },
      { label: '负债合计', value: formatAccountCurrency(liabilityTotal) },
      { label: '净资产', value: formatAccountCurrency(assetTotal - liabilityTotal) },
      { label: '账户数', value: String(accounts.filter(account => !account.isArchived).length) },
    ]
  }

  const snapshots = latestSnapshots(getWalletRecords(store))
  const cashTotal = snapshots.filter(isCash).reduce((sum, record) => sum + amountOf(record), 0)
  const liabilityTotal = snapshots.filter(isUnpaidLiability).reduce((sum, record) => sum + amountOf(record), 0)
  return [
    { label: '可用现金', value: formatCurrency(cashTotal), accent: true },
    { label: '待还款', value: formatCurrency(liabilityTotal) },
    { label: '净额估算', value: formatCurrency(cashTotal - liabilityTotal) },
    { label: '最近还款', value: getNextDueLabel(snapshots) },
  ]
}
```

- [ ] **Step 3: Add exported account sections helper**

```js
export function getAccountSections(store) {
  const { assets, liabilities } = splitAccounts(store.accounts?.value || [])
  return [
    {
      key: 'assets',
      title: '资产账户',
      empty: '还没有资产账户，可从余额截图创建',
      items: assets.map(account => ({
        id: account.id,
        title: accountTitle(account),
        subtitle: account.institution || account.type,
        value: formatAccountCurrency(account.currentBalance),
        snapshot: account.snapshotAt ? `最近快照 ${account.snapshotAt.slice(0, 10)}` : '暂无快照',
      })),
    },
    {
      key: 'liabilities',
      title: '待还负债',
      empty: '还没有待还账户，可从花呗/白条截图创建',
      items: liabilities.map(account => ({
        id: account.id,
        title: accountTitle(account),
        subtitle: account.institution || account.type,
        value: formatAccountCurrency(account.currentBalance),
        snapshot: account.snapshotAt ? `最近快照 ${account.snapshotAt.slice(0, 10)}` : '暂无快照',
      })),
    },
  ]
}
```

- [ ] **Step 4: Include `getAccountSections` in default export**

```js
export default {
  getMetricItems,
  getTrend,
  getTrendItems,
  getTrendScope,
  getDistribution,
  getDimensionItems,
  getRecentRecords,
  getAccountSections,
}
```

---

## Task 5: Wallet Domain UI Sections and Snapshot Actions

**Files:**
- Modify: `src/components/pages/PageDomainDetail.vue`
- Modify: `src/styles/main.css`

- [ ] **Step 1: Import wallet section helper**

Add:

```js
import { getAccountSections } from '../../adapters/domain/walletAdapter'
```

- [ ] **Step 2: Add computed sections**

```js
const walletAccountSections = computed(() => domain.value.id === 'wallet' ? getAccountSections(store) : [])
```

- [ ] **Step 3: Add wallet account section template below add button**

Insert after wallet add button:

```vue
    <section v-if="domain.id === 'wallet'" class="wallet-account-panel">
      <div v-for="section in walletAccountSections" :key="section.key" class="wallet-account-section">
        <div class="wallet-account-section-title">{{ section.title }}</div>
        <div v-if="!section.items.length" class="wallet-account-empty">{{ section.empty }}</div>
        <div v-for="item in section.items" :key="item.id" class="wallet-account-card">
          <div>
            <div class="wallet-account-name">{{ item.title }}</div>
            <div class="wallet-account-subtitle">{{ item.subtitle }} · {{ item.snapshot }}</div>
          </div>
          <div class="wallet-account-value">{{ item.value }}</div>
        </div>
      </div>
    </section>
```

- [ ] **Step 4: Add snapshot action buttons to recent wallet records**

In `DomainRecentRecordList` this may require component support. If the component has no action slot, add a simple wallet-only panel below the list instead:

```vue
    <section v-if="domain.id === 'wallet'" class="wallet-snapshot-action-panel">
      <div class="wallet-account-section-title">未关联快照</div>
      <div
        v-for="record in unlinkedWalletSnapshots"
        :key="record.id"
        class="wallet-snapshot-action-card"
      >
        <div>
          <div class="wallet-account-name">{{ record.title || record.payload?.account_name || '钱包快照' }}</div>
          <div class="wallet-account-subtitle">截图金额 ¥{{ Number(record.payload?.snapshot_balance ?? record.payload?.amount ?? 0).toFixed(2) }}</div>
        </div>
        <button class="wallet-snapshot-action-btn" @click="store.createAccountFromWalletSnapshot(record)">创建账户</button>
      </div>
    </section>
```

Add computed:

```js
const unlinkedWalletSnapshots = computed(() => {
  if (domain.value.id !== 'wallet') return []
  return store.dataRecords.value
    .filter(record => record.domainKey === 'wallet')
    .filter(record => !record.payload?.linked_account_id)
    .slice(0, 5)
})
```

- [ ] **Step 5: Add CSS**

Append to `src/styles/main.css`:

```css
.wallet-account-panel,
.wallet-snapshot-action-panel {
  margin: 0 16px 14px;
  display: grid;
  gap: 12px;
}

.wallet-account-section {
  display: grid;
  gap: 10px;
}

.wallet-account-section-title {
  font-size: 15px;
  font-weight: 800;
  color: var(--text-main);
}

.wallet-account-empty {
  padding: 14px;
  border-radius: 16px;
  background: var(--bg-card);
  color: var(--text-muted);
  font-size: 13px;
}

.wallet-account-card,
.wallet-snapshot-action-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 16px;
  border-radius: 18px;
  background: var(--bg-card);
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.06);
}

.wallet-account-name {
  font-size: 15px;
  font-weight: 800;
  color: var(--text-main);
}

.wallet-account-subtitle {
  margin-top: 4px;
  font-size: 12px;
  color: var(--text-muted);
}

.wallet-account-value {
  color: #7c3aed;
  font-size: 16px;
  font-weight: 900;
  white-space: nowrap;
}

.wallet-snapshot-action-btn {
  border: none;
  border-radius: 999px;
  padding: 8px 12px;
  background: #7c3aed;
  color: #fff;
  font-size: 12px;
  font-weight: 800;
  white-space: nowrap;
}
```

---

## Task 6: Wallet Schema and Manual Form Normalization

**Files:**
- Modify: `src/domains/registry.js`
- Modify: `src/domains/universalFormAdapter.js`

- [ ] **Step 1: Add wallet fallback schema fields in `registry.js`**

Inside `BUILTIN_SCHEMAS.wallet.facts`, add:

```js
      { key: 'snapshot_balance', label: '快照余额', type: 'number', unit: '元', optional: true },
```

Inside `BUILTIN_SCHEMAS.wallet.dimensions`, add:

```js
      { key: 'account_snapshot_kind', label: '快照类型', priority: 6, optional: true },
      { key: 'institution', label: '机构', priority: 7, optional: true },
      { key: 'last4', label: '尾号', priority: 8, optional: true },
      { key: 'linked_account_id', label: '关联账户', priority: 9, optional: true },
```

- [ ] **Step 2: Normalize wallet payload in `buildUniversalRecordDraft`**

Before the `return` in `buildUniversalRecordDraft`, add:

```js
  if (modal.domainKey === 'wallet') {
    payload.snapshot_balance = payload.snapshot_balance ?? primary
    payload.account_snapshot_kind = payload.account_snapshot_kind
      || (payload.record_kind === 'liability_snapshot' ? 'liability' : 'asset')
  }
```

---

## Task 7: Edge Function Wallet Payload Enhancement

**Files:**
- Modify: `supabase/functions/ingest-receipt/index.ts`

- [ ] **Step 1: In wallet branch, add snapshot fields**

In `if (domainKey === "wallet")`, after `payload.amount = amount;`, add:

```ts
    payload.snapshot_balance = amount;
    payload.account_snapshot_kind = recordKind === "liability_snapshot" ? "liability" : "asset";
    payload.institution = normalizeString(payload.institution) ?? accountName;
    const last4 = normalizeString(payload.last4);
    payload.last4 = last4 && /^\d{4}$/.test(last4) ? last4 : null;
```

- [ ] **Step 2: Normalize account type values**

Find `normalizeAccountType` in `ingest-receipt/index.ts`. Ensure it maps:

```ts
wechat -> wallet_balance
alipay -> wallet_balance
bank_card -> debit_card
huabei -> credit_line
jd_baitiao -> credit_line
douyin_monthly -> credit_line
credit_card -> credit_card
cash -> cash
```

If it currently emits old values like `wechat`, change it to emit the new enum-compatible values.

---

## Task 8: Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run production build**

Run:

```powershell
npm run build
```

Expected:

```text
vite build completes successfully
```

- [ ] **Step 2: Static migration review**

Open `supabase/migrations/022_wallet_accounts_v1a.sql` and confirm:

```text
public.accounts has user_id not null
public.account_entries has user_id not null
enable row level security exists for both tables
policy uses auth.uid() = user_id
grant select, insert, update, delete to authenticated exists for both tables
no grant write permission to anon exists
```

Expected: all statements are true.

- [ ] **Step 3: Manual browser smoke test**

Start dev server:

```powershell
npm run dev
```

Expected:

```text
Vite dev server starts without compile errors
```

Manual scenarios:

```text
1. Open 钱包与待还 domain page.
2. Confirm account sections render above existing charts/lists.
3. If no accounts exist, empty states render.
4. Create a manual wallet snapshot with record_kind=cash_snapshot and amount=2065.23.
5. Click 创建账户 on the unlinked snapshot.
6. Confirm a new asset account appears with ¥2065.23.
7. Create a manual wallet snapshot with record_kind=liability_snapshot and amount=1001.08.
8. Click 创建账户 on the unlinked snapshot.
9. Confirm a liability account appears with ¥1001.08.
10. Confirm expense and income pages still load and balances are not auto-mutated.
```

Expected: all scenarios pass.

---

## Self-Review

**Spec coverage:**
- Account base tables: Task 1.
- Minimal entries: Task 1.
- Supabase Data API grants: Task 1 and Task 8.
- Wallet screenshot compatibility: Tasks 5, 6, 7.
- Snapshot creates/links accounts: Task 3 and Task 5.
- No expense/income auto balance mutation: Scope boundaries and Task 8 manual scenario.

**Placeholder scan:**
- No `TBD` or `TODO` placeholders are present.
- Steps include exact files, code snippets, commands, and expected outcomes.

**Type consistency:**
- Frontend account types match SQL enum values.
- Snapshot kind uses `asset` / `liability` consistently.
- Wallet payload fields use `snapshot_balance`, `account_snapshot_kind`, `institution`, `last4`, `linked_account_id` consistently.

---

## Execution Notes

Do not commit automatically. The user explicitly requires confirmation before commit/push/destructive operations. If a plan executor reaches a commit step from a generic skill instruction, skip it and report the changed files instead.
