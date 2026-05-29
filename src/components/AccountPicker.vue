<template>
  <div class="account-picker">
    <div class="account-picker-header">
      <span class="account-picker-label">{{ label }}</span>
      <button class="account-picker-create" @click="onCreate">+ 新建账户</button>
    </div>
    <div class="account-picker-list">
      <button
        v-for="account in visibleAccounts"
        :key="account.id"
        class="account-picker-chip"
        :class="{ selected: !unbound && selectedId === account.id }"
        @click="onPick(account.id)"
      >
        <div class="account-picker-chip-title">{{ account.name }}</div>
        <div class="account-picker-chip-sub">{{ formatBalance(account) }}</div>
      </button>
      <button
        class="account-picker-chip unbind"
        :class="{ selected: unbound }"
        @click="onUnbind"
      >
        <div class="account-picker-chip-title">暂不绑定</div>
        <div class="account-picker-chip-sub">仅记录，不入账</div>
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'

const props = defineProps({
  selectedId: { type: String, default: null },
  unbound: { type: Boolean, default: false },
  kind: { type: String, default: 'expense' },
  label: { type: String, default: '出资账户' },
})

const emit = defineEmits(['update:selectedId', 'update:unbound'])
const store = inject('store')

const visibleAccounts = computed(() => {
  const list = (store.accounts?.value || []).filter(a => !a.isArchived)
  return list
})

function onPick(id) {
  emit('update:unbound', false)
  emit('update:selectedId', id)
}

function onUnbind() {
  emit('update:unbound', true)
  emit('update:selectedId', null)
}

function onCreate() {
  store.openAccountModalForCreate()
}

function formatBalance(account) {
  const bal = Number(account.currentBalance ?? account.current_balance ?? 0)
  const suffix = account.last4 ? ` · ${account.last4}` : ''
  return `余额 ¥${bal.toFixed(2)}${suffix}`
}
</script>

<style scoped>
.account-picker { margin-top: 16px; }
.account-picker-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; }
.account-picker-label { font-size: 13px; color: var(--text2, #555); font-weight: 500; }
.account-picker-create { font-size: 12px; color: #1565C0; background: transparent; border: none; padding: 4px 8px; cursor: pointer; }
.account-picker-list { display: flex; gap: 8px; overflow-x: auto; padding-bottom: 4px; }
.account-picker-chip {
  flex: 0 0 auto;
  min-width: 110px;
  background: #f5f4ef;
  border: 1.5px solid transparent;
  border-radius: 12px;
  padding: 10px 12px;
  text-align: left;
  cursor: pointer;
  transition: all 0.15s;
}
.account-picker-chip.selected { background: #1565C0; color: #fff; border-color: #1565C0; }
.account-picker-chip.unbind { background: #fff8e1; }
.account-picker-chip.unbind.selected { background: #f57c00; border-color: #f57c00; color: #fff; }
.account-picker-chip-title { font-size: 13px; font-weight: 600; }
.account-picker-chip-sub { font-size: 11px; opacity: 0.8; margin-top: 2px; }
</style>
