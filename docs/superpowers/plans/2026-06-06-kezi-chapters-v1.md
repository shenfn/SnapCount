# Kezi Chapters V1 Planning Note

> Status: planned for later. Do not implement before the current wallet/liability polish track is stabilized.

## Goal

Introduce a product-level "Chapter" concept for Kezi so users can restart cleanly after a period of missing or inconsistent records, while keeping older data available as history.

The core product promise is:

> A new chapter starts from the current truth. Past records remain, but the home page, asset view, and AI analysis prioritize the active chapter.

## Why This Matters

Long-running personal finance data naturally becomes inconsistent when users stop recording for a while, miss automatic repayments, forget screenshots, or encounter platform-specific bill rules such as minimum repayment, installment interest, refunds, and carried-over balances.

If users return and immediately see account balances far away from reality, trust drops quickly. Chapters give users a low-anxiety restart path without requiring them to backfill every missing transaction.

## Naming

Prefer "Chapter" / "篇章" over "Ledger" / "账本".

Rationale:

- "账本" sounds like a traditional accounting-only container.
- Kezi covers finance plus broader life domains, so "篇章" better fits life stages and restart moments.
- Product copy can be gentler: "开启新篇章", "当前篇章", "历史篇章".

## V1 Scope

In scope:

- Create a chapter model per user.
- Maintain one active chapter per user.
- Assign new finance records to the active chapter.
- Migrate existing records into an initial chapter.
- Let the home page and AI finance analysis default to the active chapter.
- When starting a new chapter, allow users to set account opening truth via current balances or balance screenshots.

Out of scope for V1:

- Full cross-domain chapter filtering for every life domain if it slows down finance stabilization.
- Perfect reconstruction of missed historical transactions.
- Bank-level statement reconciliation.
- Automatic migration of old insights into new chapter summaries.

## Suggested Data Model

Potential table:

- `chapters`
  - `id`
  - `user_id`
  - `name`
  - `started_at`
  - `ended_at`
  - `is_active`
  - `opening_note`
  - `created_at`
  - `updated_at`

Potential linked fields:

- `transactions.chapter_id`
- `income_records.chapter_id`
- `accounts.chapter_id` or account-level chapter-opening snapshots
- `account_entries.chapter_id`
- `data_records.chapter_id`
- `staging_records.chapter_id`
- AI insight records may later include `chapter_id`

## Product Flow

### Start New Chapter

User chooses "开启新篇章".

Options:

- Continue with current account balances.
- Reconcile accounts from fresh screenshots.
- Start with selected accounts only.

The system should explain:

> 历史记录会保留。从新篇章开始，首页、资产和 AI 分析将优先基于新的记录周期。

### Active Chapter Defaults

New records should automatically belong to the active chapter.

Home page and asset domain should default to active chapter data.

History can remain browsable through a chapter switcher.

### AI Analysis

AI analysis should prioritize the active chapter and use older chapters only as background context, for example:

> 当前篇章从 2026-06-06 开始。以下分析主要基于本篇章，历史数据仅作参考。

## Implementation Strategy

Do not do this as a single large refactor.

Recommended phases:

1. Add chapter table and default active chapter.
2. Attach chapter IDs to finance records and account entries.
3. Make finance/home queries active-chapter aware.
4. Add "start new chapter" flow with account opening snapshots.
5. Add chapter switcher and historical chapter viewing.
6. Extend AI insights and non-finance domains if needed.

## Relationship To Current Wallet Work

This should come after the wallet/liability polish track:

- Liability bill settings.
- Due repayment detail.
- Repayment screenshot recognition and matching.
- Balance snapshot reconciliation.
- Batch binding.

The current wallet work reduces daily trust loss. Chapters solve long-term restart and retention.
