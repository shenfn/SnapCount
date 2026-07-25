#!/usr/bin/env node
/**
 * Tailwind Config Token 生成脚本
 *
 * 输入：tokens/design-tokens.json (SSOT)
 * 输出：dist/tailwind/jiezi-tailwind.config.cjs  （Tailwind 颜色/间距/圆角/阴影/字体/动效预设）
 *
 * 使用：
 *   1. 运行：node scripts/generate-tailwind.mjs
 *   2. 在项目 tailwind.config.js 中：
 *        const jiezi = require('./path/to/jiezi-tailwind.config.cjs');
 *        module.exports = { presets: [jiezi], ... };
 *
 * 产物特性：
 *   - 通过 CSS Variables 引用主题色，支持运行时切换主题
 *   - 间距/圆角/阴影/字体/动效全部映射到 Tailwind 默认 token
 *   - 不修改任何现有 tailwind.config.js
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ROOT = resolve(__dirname, '..');

const tokens = JSON.parse(readFileSync(join(ROOT, 'tokens/design-tokens.json'), 'utf8'));
const outDir = join(ROOT, 'dist/tailwind');
mkdirSync(outDir, { recursive: true });

const colorKeys = ['paper', 'brand', 'light', 'space', 'ink', 'muted', 'coral', 'line'];

const domainColorObj = {};
Object.entries(tokens.color.domains).forEach(([k, v]) => {
  if (k === '$description') return;
  domainColorObj[`domain-${k}`] = v.hex;
});
const artColorObj = {};
Object.entries(tokens.color.art).forEach(([k, v]) => {
  if (k === '$description') return;
  artColorObj[`art-${k.replace(/_/g, '-')}`] = v.hex;
});

const spacingObj = {};
tokens.spacing.scale.forEach((s) => { spacingObj[s.id] = `${s.value}px`; });
Object.entries(tokens.spacing.semantic).forEach(([k, v]) => { spacingObj[k.replace(/_/g, '-')] = `${v.value}px`; });

const radiusObj = {};
tokens.radius.scale.forEach((s) => {
  radiusObj[s.id] = s.value === 999 ? '9999px' : `${s.value}px`;
});
Object.entries(tokens.radius.semantic).forEach(([k, v]) => {
  radiusObj[k.replace(/_/g, '-')] = v.value === 999 ? '9999px' : `${v.value}px`;
});

const shadowObj = {};
tokens.shadow.scale.forEach((s) => {
  const colorVar = s.color_ref === 'space' ? 'rgb(var(--jiezi-color-space-rgb) / ' + s.alpha + ')' : 'rgb(var(--jiezi-color-brand-rgb) / ' + s.alpha + ')';
  shadowObj[s.id] = `0 ${s.y}px ${s.radius}px ${colorVar}`;
});

const fontSizeObj = {};
tokens.typography.scale.forEach((f) => {
  fontSizeObj[f.id] = [`${f.pwa_size}px`, { lineHeight: `${f.line_height}`, fontWeight: `${f.pwa_weight}` }];
});

const durationObj = {};
tokens.motion.durations.forEach((d) => { durationObj[d.id] = `${d.ms}ms`; });

const easingObj = {};
tokens.motion.easings.forEach((e) => { easingObj[e.id] = `cubic-bezier(${e.bezier.join(', ')})`; });

const zIndexObj = {};
tokens.z_index.scale.forEach((z) => { zIndexObj[z.id] = `${z.value}`; });

const fontFamilyObj = {};
Object.entries(tokens.typography.font_families.pwa).forEach(([k, v]) => {
  fontFamilyObj[k] = v.split(',').map((s) => s.trim());
});

const config = {
  theme: {
    extend: {
      colors: {
        jiezi: Object.fromEntries(colorKeys.map((k) => [k, `var(--jiezi-color-${k})`])),
        ...domainColorObj,
        ...artColorObj,
      },
      spacing: spacingObj,
      borderRadius: radiusObj,
      boxShadow: shadowObj,
      fontSize: fontSizeObj,
      transitionDuration: durationObj,
      transitionTimingFunction: easingObj,
      zIndex: zIndexObj,
      fontFamily: fontFamilyObj,
      maxWidth: {
        page: `${tokens.layout.page_max_width}px`,
        'page-tablet': `${tokens.layout.page_max_width_tablet}px`,
      },
    },
  },
};

const lines = [];
lines.push('/**');
lines.push(' * 芥子设计系统 Tailwind Preset');
lines.push(` * 自动生成于 ${new Date().toISOString()}`);
lines.push(` * 数据源：trae-design-system/tokens/design-tokens.json v${tokens.$meta.version}`);
lines.push(' * 禁止手工修改本文件。任何调整请改 SSOT 后运行 scripts/generate-tailwind.mjs');
lines.push(' */');
lines.push('');
lines.push('// 使用方法：在项目 tailwind.config.js 中');
lines.push('//   const jiezi = require("./jiezi-tailwind.config.cjs");');
lines.push('//   module.exports = { presets: [jiezi] };');
lines.push('');
lines.push('module.exports = ' + JSON.stringify(config, null, 2) + ';');
lines.push('');

const outPath = join(outDir, 'jiezi-tailwind.config.cjs');
writeFileSync(outPath, lines.join('\n'));

console.log(`✓ Tailwind Preset 已生成：${outPath}`);
console.log(`  - colors.jiezi.*  → 8 个语义槽位（CSS vars）+ ${Object.keys(domainColorObj).length} 个域色 + ${Object.keys(artColorObj).length} 个艺术色`);
console.log(`  - spacing.*       → ${Object.keys(spacingObj).length} 个间距值`);
console.log(`  - borderRadius.*  → ${Object.keys(radiusObj).length} 个圆角值`);
console.log(`  - boxShadow.*     → ${Object.keys(shadowObj).length} 个阴影值`);
console.log(`  - fontSize.*      → ${Object.keys(fontSizeObj).length} 个字体层级`);
console.log(`  - transitionDuration.* → ${Object.keys(durationObj).length} 个时长`);
console.log(`  - transitionTimingFunction.* → ${Object.keys(easingObj).length} 个曲线`);
console.log(`  - fontFamily.*    → ${Object.keys(fontFamilyObj).length} 个字体族`);
