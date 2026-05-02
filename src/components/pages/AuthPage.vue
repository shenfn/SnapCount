<template>
  <div class="page active">
    <div class="auth-hero">
      <div class="auth-logo">数</div>
      <div class="auth-title">随手账</div>
      <div class="auth-subtitle">AI 自动记账，截图即入账</div>
    </div>

    <div class="auth-tabs">
      <button :class="{ active: mode === 'login' }" @click="mode = 'login'">登录</button>
      <button :class="{ active: mode === 'register' }" @click="mode = 'register'">注册</button>
    </div>

    <form class="auth-form" @submit.prevent="submit">
      <input v-model="email" type="email" class="auth-input" placeholder="邮箱地址" autocomplete="email" required>
      <input v-model="password" type="password" class="auth-input" placeholder="密码（至少6位）" autocomplete="current-password" minlength="6" required>

      <p v-if="errorMsg" class="auth-error">{{ errorMsg }}</p>

      <button class="auth-btn" :disabled="loading">
        {{ loading ? '处理中...' : mode === 'login' ? '登录' : '注册' }}
      </button>

      <p class="auth-hint">
        {{ mode === 'login' ? '还没有账号？' : '已有账号？' }}
        <a href="#" @click.prevent="mode = mode === 'login' ? 'register' : 'login'">
          {{ mode === 'login' ? '注册' : '登录' }}
        </a>
      </p>
    </form>

    <p class="auth-footer">
      当前为内测版本。注册即表示你同意数据仅用于提供记账服务，不会公开或出售给第三方。
    </p>
  </div>
</template>

<script setup>
import { ref, inject, onMounted } from 'vue'
import { sb } from '../../lib/supabase'

const store = inject('store')
const mode = ref('login')
const email = ref('')
const password = ref('')
const loading = ref(false)
const errorMsg = ref('')

onMounted(async () => {
  const { data } = await sb.auth.getSession()
  if (data?.session) store.loadData()
})

async function submit() {
  loading.value = true
  errorMsg.value = ''

  try {
    if (mode.value === 'register') {
      const { data, error } = await sb.auth.signUp({
        email: email.value.trim(),
        password: password.value,
      })
      if (error) throw error

      if (data?.user) {
        // 自动创建用户配置
        await sb.from('user_configs').upsert({
          user_id: data.user.id,
          plan: 'seed',
          created_at: new Date().toISOString(),
        }, { onConflict: 'user_id' })
        store.currentUserId.value = data.user.id
        store.isLoggedIn.value = true
        store.showFlash('✓ 注册成功，已自动登录')
        await store.loadData()
      }
    } else {
      const { data, error } = await sb.auth.signInWithPassword({
        email: email.value.trim(),
        password: password.value,
      })
      if (error) throw error

      if (data?.user) {
        store.currentUserId.value = data.user.id
        store.isLoggedIn.value = true
        store.showFlash('✓ 登录成功')
        await store.loadData()
      }
    }
  } catch (e) {
    errorMsg.value = e.message || '操作失败，请重试'
  } finally {
    loading.value = false
  }
}
</script>
