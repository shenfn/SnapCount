#!/usr/bin/env node
/**
 * PWA CSS Token 生成脚本
 *
 * 输入：tokens/design-tokens.json (SSOT)
 * 输出：dist/pwa/tokens.css          （CSS Variables，所有主题为 :root + [data-theme="xxx"]）
 *       dist/pwa/tokens.json         （JS 可消费的 token 对象）
 *
 * 使用：
 *   node scripts/generate-css.mjs
 *
 * 产物特性：
 *   - 通过 [data-theme="cyan"] 切换主题，:root 默认指向 iOS 默认主题
 *   - 时间相位通过 prefers-color-scheme 之外的方式，需运行时 JS 切换
 *   - 包含 font-family / spacing / radius / shadow / motion 全部 CSS variables
 *   - 不破坏现有 PWA src/styles/main.css，作为独立文件供项目按需引入
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ROOT = resolve(__dirname, '..');

const tokens = JSON.parse(readFileSync(join(ROOT, 'tokens/design-tokens.json'), 'utf8'));
const outDir = join(ROOT, 'dist/pwa');
mkdirSync(outDir, { recursive: true });

const lines = [];
lines.push('/*');
lines.push(' * 芥子设计系统 PWA CSS Variables');
lines.push(` * 自动生成于 ${new Date().toISOString()}`);
lines.push(` * 数据源：trae-design-system/tokens/design-tokens.json v${tokens.$meta.version}`);
lines.push(' * 禁止手工修改本文件。任何调整请改 SSOT 后运行 scripts/generate-css.mjs');
lines.push(' */');
lines.push('');

// 默认主题写到 :root，所有主题都以 [data-theme="xxx"] 暴露
tokens.color.themes.forEach((theme, idx) => {
  const selector = theme.is_default_ios ? ':root' : `[data-theme="${theme.id}"]`;
  lines.push(`/* ${theme.name} (${theme.id}) - ${theme.description} */`);
  lines.push(`${selector} {`);
  Object.entries(theme.colors).forEach(([key, value]) => {
    lines.push(`  --jiezi-color-${key}: ${value};`);
  });
  // 衍生透明度变体
  Object.entries(tokens.color.alpha_variants).forEach(([key, alpha]) => {
    if (key.startsWith('$')) return;
    const [colorName, , alphaStr] = key.split('_');
    if (theme.colors[colorName]) {
      const hex = theme.colors[colorName];
      const r = parseInt(hex.slice(1, 3), 16);
      const g = parseInt(hex.slice(3, 5), 16);
      const b = parseInt(hex.slice(5, 7), 16);
      lines.push(`  --jiezi-color-${colorName}-alpha-${Math.round(alpha * 100)}: rgba(${r}, ${g}, ${b}, ${alpha});`);
    }
  });
  // line 槽位（brand 13% alpha）
  const brandHex = theme.colors.brand;
  const br = parseInt(brandHex.slice(1, 3), 16);
  const bg = parseInt(brandHex.slice(3, 5), 16);
  const bb = parseInt(brandHex.slice(5, 7), 16);
  lines.push(`  --jiezi-color-line: rgba(${br}, ${bg}, ${bb}, 0.13);`);
  lines.push('}');
  lines.push('');
});

// 字体
lines.push('/* 字体层级 */');
lines.push(':root {');
tokens.typography.scale.forEach((f) => {
  lines.push(`  --jiezi-font-${f.id}-size: ${f.pwa_size}px;`);
  lines.push(`  --jiezi-font-${f.id}-weight: ${f.pwa_weight};`);
  lines.push(`  --jiezi-font-${f.id}-line-height: ${f.line_height};`);
});
lines.push('');
Object.entries(tokens.typography.font_families.pwa).forEach(([k, v]) => {
  lines.push(`  --jiezi-font-family-${k}: ${v};`);
});
lines.push('}');
lines.push('');

// 间距
lines.push('/* 间距 */');
lines.push(':root {');
tokens.spacing.scale.forEach((s) => {
  lines.push(`  --jiezi-spacing-${s.id}: ${s.value}px;`);
});
lines.push('');
Object.entries(tokens.spacing.semantic).forEach(([k, v]) => {
  lines.push(`  --jiezi-spacing-${k}: ${v.value}px;`);
});
lines.push('}');
lines.push('');

// 圆角
lines.push('/* 圆角 */');
lines.push(':root {');
tokens.radius.scale.forEach((s) => {
  const v = s.value === 999 ? '9999px' : `${s.value}px`;
  lines.push(`  --jiezi-radius-${s.id}: ${v};`);
});
lines.push('');
Object.entries(tokens.radius.semantic).forEach(([k, v]) => {
  const val = v.value === 999 ? '9999px' : `${v.value}px`;
  lines.push(`  --jiezi-radius-${k}: ${val};`);
});
lines.push('}');
lines.push('');

// 阴影
lines.push('/* 阴影 */');
lines.push(':root {');
tokens.shadow.scale.forEach((s) => {
  // 阴影颜色用当前主题的 space/brand，通过 var() 引用
  const colorVar = s.color_ref === 'space' ? 'var(--jiezi-color-space)' : 'var(--jiezi-color-brand)';
  lines.push(`  --jiezi-shadow-${s.id}: 0 ${s.y}px ${s.radius}px ${colorVar};`);
  lines.push(`  --jiezi-shadow-${s.id}-alpha: ${s.alpha};`);
});
lines.push('');
Object.entries(tokens.shadow.semantic).forEach(([k, v]) => {
  lines.push(`  --jiezi-shadow-semantic-${k}: var(--jiezi-shadow-${v.ref});`);
});
lines.push('}');
lines.push('');

// 动效
lines.push('/* 动效 */');
lines.push(':root {');
tokens.motion.durations.forEach((d) => {
  lines.push(`  --jiezi-duration-${d.id}: ${d.ms}ms;`);
});
lines.push('');
tokens.motion.easings.forEach((e) => {
  lines.push(`  --jiezi-easing-${e.id}: cubic-bezier(${e.bezier.join(', ')});`);
});
lines.push('');
Object.entries(tokens.motion.semantic).forEach(([k, v]) => {
  lines.push(`  --jiezi-motion-${k}-duration: var(--jiezi-duration-${v.duration});`);
  lines.push(`  --jiezi-motion-${k}-easing: var(--jiezi-easing-${v.easing});`);
});
lines.push('}');
lines.push('');

// 域色（全局固定，不随主题切换）
lines.push('/* 数据域色（全局固定） */');
lines.push(':root {');
Object.entries(tokens.color.domains).forEach(([k, v]) => {
  if (k === '$description') return;
  lines.push(`  --jiezi-domain-${k}: ${v.hex}; /* ${v.name} */`);
});
lines.push('}');
lines.push('');

// 艺术色（功能页面禁用）
lines.push('/* 艺术版专用色（功能页面禁用） */');
lines.push(':root {');
Object.entries(tokens.color.art).forEach(([k, v]) => {
  if (k === '$description') return;
  lines.push(`  --jiezi-art-${k.replace(/_/g, '-')}: ${v.hex}; /* ${v.usage} */`);
});
lines.push('}');
lines.push('');

// 描边（金线 0.5mm 为骨）
lines.push('/* 描边（金线 0.5mm 为骨） */');
lines.push(':root {');
Object.entries(tokens.stroke).forEach(([k, v]) => {
  if (k === '$description') return;
  lines.push(`  --jiezi-stroke-${k.replace(/_/g, '-')}-width: ${v.width}px; /* ${v.usage} */`);
  lines.push(`  --jiezi-stroke-${k.replace(/_/g, '-')}-color: var(--jiezi-color-${v.color_ref});`);
  lines.push(`  --jiezi-stroke-${k.replace(/_/g, '-')}-alpha: ${v.alpha};`);
});
lines.push('}');
lines.push('');

// 图标尺寸
lines.push('/* 图标尺寸 */');
lines.push(':root {');
tokens.icon.scale.forEach((s) => {
  lines.push(`  --jiezi-icon-${s.id}: ${s.value}px; /* ${s.usage} */`);
});
Object.entries(tokens.icon.semantic).forEach(([k, v]) => {
  lines.push(`  --jiezi-icon-semantic-${k.replace(/_/g, '-')}: ${v.value}px;`);
});
lines.push('}');
lines.push('');

// 语义字体角色
lines.push('/* 语义字体角色（serif 标题 + rounded 金额） */');
lines.push(':root {');
const fontById = Object.fromEntries(tokens.typography.scale.map((f) => [f.id, f]));
Object.entries(tokens.typography.roles).forEach(([roleId, role]) => {
  if (roleId === '$description') return;
  const base = fontById[role.ref];
  const weightMap = { regular: 400, medium: 500, semibold: 600, bold: 700 };
  const weight = role.weight_override ? weightMap[role.weight_override] : base.pwa_weight;
  const family = role.design === 'serif' ? 'var(--jiezi-font-family-serif)' : role.design === 'rounded' ? 'var(--jiezi-font-family-rounded)' : 'var(--jiezi-font-family-sans)';
  const kebab = roleId.replace(/([A-Z])/g, '-$1').toLowerCase();
  lines.push(`  --jiezi-type-${kebab}-size: ${base.pwa_size}px; /* ${role.usage} */`);
  lines.push(`  --jiezi-type-${kebab}-weight: ${weight};`);
  lines.push(`  --jiezi-type-${kebab}-line-height: ${base.line_height};`);
  lines.push(`  --jiezi-type-${kebab}-family: ${family};`);
  if (role.numeric) {
    lines.push(`  --jiezi-type-${kebab}-numeric: tabular-nums;`);
  }
});
lines.push('}');
lines.push('');

// 布局
lines.push('/* 布局 */');
lines.push(':root {');
Object.entries(tokens.layout).forEach(([k, v]) => {
  if (typeof v === 'number') {
    lines.push(`  --jiezi-layout-${k.replace(/_/g, '-')}: ${v}px;`);
  } else {
    lines.push(`  --jiezi-layout-${k.replace(/_/g, '-')}: ${v};`);
  }
});
lines.push('}');
lines.push('');

// z-index
lines.push('/* z-index */');
lines.push(':root {');
tokens.z_index.scale.forEach((z) => {
  lines.push(`  --jiezi-z-${z.id}: ${z.value};`);
});
lines.push('}');
lines.push('');

// 时间相位 JS 切换工具
lines.push('/*');
lines.push(' * 时间相位切换工具（运行时 JS）');
lines.push(' * 使用：import { applyTimePhase } from "./tokens-phase.mjs";');
lines.push(' *       applyTimePhase(new Date().getHours());');
lines.push(' */');

const cssOutPath = join(outDir, 'tokens.css');
writeFileSync(cssOutPath, lines.join('\n'));

// 同时输出一份 JS 版本便于按需 import
const jsLines = [];
jsLines.push('/**');
jsLines.push(' * 芥子设计系统 PWA JS Token');
jsLines.push(` * 自动生成于 ${new Date().toISOString()}`);
jsLines.push(' */');
jsLines.push('');
jsLines.push('export const THEMES = [');
tokens.color.themes.forEach((t) => {
  jsLines.push(`  { id: "${t.id}", name: "${t.name}", description: "${t.description}", colors: ${JSON.stringify(t.colors)} },`);
});
jsLines.push('];');
jsLines.push('');
jsLines.push('export const DEFAULT_THEME_IOS = "' + (tokens.color.themes.find(t => t.is_default_ios) || tokens.color.themes[0]).id + '";');
jsLines.push('export const DEFAULT_THEME_PWA = "' + (tokens.color.themes.find(t => t.is_default_pwa) || tokens.color.themes[0]).id + '";');
jsLines.push('');
jsLines.push('export const SPACING = {');
tokens.spacing.scale.forEach((s) => { jsLines.push(`  ${s.id}: ${s.value},`); });
jsLines.push('};');
jsLines.push('');
jsLines.push('export const RADIUS = {');
tokens.radius.scale.forEach((s) => { jsLines.push(`  ${s.id}: ${s.value === 999 ? '999' : s.value},`); });
jsLines.push('};');
jsLines.push('');
jsLines.push('export const FONT_SCALE = [');
tokens.typography.scale.forEach((f) => {
  jsLines.push(`  { id: "${f.id}", name: "${f.name}", size: ${f.pwa_size}, weight: ${f.pwa_weight}, lineHeight: ${f.line_height} },`);
});
jsLines.push('];');
jsLines.push('');
jsLines.push('export const DURATIONS = {');
tokens.motion.durations.forEach((d) => { jsLines.push(`  ${d.id}: ${d.ms},`); });
jsLines.push('};');
jsLines.push('');
jsLines.push('export const EASINGS = {');
tokens.motion.easings.forEach((e) => { jsLines.push(`  ${e.id}: 'cubic-bezier(${e.bezier.join(', ')})',`); });
jsLines.push('};');
jsLines.push('');
jsLines.push('export const DOMAIN_COLORS = {');
Object.entries(tokens.color.domains).forEach(([k, v]) => {
  if (k === '$description') return;
  jsLines.push(`  ${k}: '${v.hex}', // ${v.name}`);
});
jsLines.push('};');
jsLines.push('');
jsLines.push('export const ART_COLORS = {');
Object.entries(tokens.color.art).forEach(([k, v]) => {
  if (k === '$description') return;
  jsLines.push(`  ${k}: '${v.hex}', // ${v.usage}`);
});
jsLines.push('};');
jsLines.push('');
jsLines.push('export const STROKES = {');
Object.entries(tokens.stroke).forEach(([k, v]) => {
  if (k === '$description') return;
  jsLines.push(`  ${k}: { width: ${v.width}, colorRef: '${v.color_ref}', alpha: ${v.alpha} },`);
});
jsLines.push('};');
jsLines.push('');
jsLines.push('export const ICON_SIZES = {');
tokens.icon.scale.forEach((s) => { jsLines.push(`  ${s.id}: ${s.value},`); });
jsLines.push('};');
jsLines.push('');
jsLines.push('export const TYPE_ROLES = {');
Object.entries(tokens.typography.roles).forEach(([roleId, role]) => {
  if (roleId === '$description') return;
  jsLines.push(`  ${roleId}: { ref: '${role.ref}', design: ${role.design ? `'${role.design}'` : 'null'}, numeric: ${role.numeric ? 'true' : 'false'} }, // ${role.usage}`);
});
jsLines.push('};');

const jsOutPath = join(outDir, 'tokens.js');
writeFileSync(jsOutPath, jsLines.join('\n'));

console.log(`✓ PWA CSS Token 已生成：${cssOutPath}`);
console.log(`✓ PWA JS  Token 已生成：${jsOutPath}`);
console.log(`  - ${tokens.color.themes.length} 个主题（含 [data-theme] 切换）`);
console.log(`  - ${tokens.typography.scale.length} 个字体层级`);
console.log(`  - ${tokens.spacing.scale.length} 个间距层级`);
console.log(`  - ${tokens.radius.scale.length} 个圆角层级`);
console.log(`  - ${tokens.shadow.scale.length} 个阴影层级`);
console.log(`  - ${tokens.motion.durations.length} 个动效时长 + ${tokens.motion.easings.length} 个曲线`);
console.log(`  - ${Object.keys(tokens.color.domains).filter((k) => k !== '$description').length} 个域色 + ${Object.keys(tokens.color.art).filter((k) => k !== '$description').length} 个艺术色 + ${Object.keys(tokens.stroke).filter((k) => k !== '$description').length} 个描边 + ${tokens.icon.scale.length} 个图标尺寸 + ${Object.keys(tokens.typography.roles).filter((k) => k !== '$description').length} 个字体角色`);
