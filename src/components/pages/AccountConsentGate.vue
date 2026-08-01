<template>
  <div class="page active">
    <div class="auth-hero auth-consent-hero">
      <div class="auth-logo">芥</div>
      <div class="auth-title">继续使用芥子</div>
      <div class="auth-subtitle">请确认当前的数据处理与 AI 服务说明</div>
    </div>

    <div class="auth-consent-gate">
      <div v-if="loading" class="auth-callback-panel" role="status">
        <strong>正在核对账号状态</strong>
        <span>完成前不会加载你的记录或调用 AI 服务。</span>
      </div>

      <template v-else>
        <div class="auth-consent-summary">
          <strong>{{ blocked ? '账户已停用或正在删除' : '你的记录包含财务、图片、睡眠等私密信息' }}</strong>
          <p v-if="blocked">当前不会加载记录或调用 AI。你可以重新提交同一删号请求以取得受理编号，或退出登录。</p>
          <p v-else>主要数据存储在 Supabase 新加坡区域；使用图片识别和 AI 联动分析时，必要内容会发送至阿里云百炼 Qwen 当前的中国内地接口。</p>
        </div>

        <div v-if="!blocked" class="auth-consent-list">
          <label class="auth-consent-row">
            <input v-model="acceptedLegal" type="checkbox">
            <span>我已阅读并同意 <a href="/terms.html" target="_blank" rel="noopener">服务协议</a> 和 <a href="/privacy.html" target="_blank" rel="noopener">隐私政策</a></span>
          </label>
          <label class="auth-consent-row">
            <input v-model="acceptedSensitive" type="checkbox">
            <span>我同意处理我主动提交的敏感或高度私密数据，并了解上述跨区域存储与 AI 处理路径</span>
          </label>
        </div>

        <div v-if="error" class="auth-message is-error" role="alert">{{ error }}</div>

        <button
          v-if="!blocked"
          type="button"
          class="auth-btn"
          :disabled="submitting || deleting || !acceptedLegal || !acceptedSensitive"
          @click="$emit('accept')"
        >
          {{ submitting ? '正在确认' : '同意并继续' }}
        </button>

        <div class="auth-consent-actions">
          <button v-if="error" type="button" class="auth-switch-btn" :disabled="submitting || deleting" @click="$emit('retry')">重新核对</button>
          <button type="button" class="auth-switch-btn is-danger" :disabled="submitting || deleting" @click="requestDeletion">
            {{ deleting ? '正在提交删除' : '删除账户' }}
          </button>
          <button type="button" class="auth-switch-btn" :disabled="submitting || deleting" @click="$emit('sign-out')">退出登录</button>
        </div>
      </template>
    </div>

    <div class="auth-footer">同意记录使用服务端时间保存。账户删除请求受理后会先在本机保存支持编号。</div>
  </div>
</template>

<script setup>
import { ref } from 'vue'

defineProps({
  loading: { type: Boolean, default: false },
  submitting: { type: Boolean, default: false },
  deleting: { type: Boolean, default: false },
  blocked: { type: Boolean, default: false },
  error: { type: String, default: '' },
})

const emit = defineEmits(['accept', 'retry', 'sign-out', 'delete-account'])

const acceptedLegal = ref(false)
const acceptedSensitive = ref(false)

function requestDeletion() {
  if (typeof window !== 'undefined' && !window.confirm('永久删除账户及全部数据？请求受理后会立即退出，且无法恢复。')) return
  emit('delete-account')
}
</script>
