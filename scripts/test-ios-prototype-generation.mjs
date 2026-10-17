import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const generate = () => {
  execFileSync(process.execPath, ['trae-design-system/scripts/generate-ios.mjs'], { cwd: root });
  return read('trae-design-system/dist/jiezi/JieziTheme+Generated.swift');
};

test('IOS-V2-POLISH-011-B iOS body uses native scalable text while retaining serif and numeric fonts', () => {
  const swift = generate();
  assert.ok(/static let body = Font\.system\(\.body\)/.test(swift), '正文应生成系统动态字体');
  assert.ok(!/Font\.custom\(JieziFontFamily\.sans/.test(swift), '不再消费 Noto Sans');
  assert.ok(/Font\.custom\(JieziFontFamily\.serif/.test(swift), '保留动态衬线标题');
  assert.ok(/Font\.custom\(JieziFontFamily\.numeric/.test(swift), '保留数字字族');
});

test('IOS-V2-POLISH-009 scene output preserves the reference local glow colors', () => {
  const swift = generate();
  assert.ok(/let glow: Color/.test(swift), '场景应导出局部光晕');
  assert.ok(/glow: Color\(jieziHex: "#6E78C8"\), glowOpacity: 0\.35/.test(swift), '睡眠使用原型紫色光晕');
  assert.ok(/glow: Color\(jieziHex: "#EA580C"\), glowOpacity: 0\.22/.test(swift), '饮食使用原型橙色光晕');
});

test('IOS-V2-POLISH-001/004 prototype metrics retain 44/40pt numbers and serif brand', () => {
  const swift = generate();
  assert.ok(swift.includes('static let prototypeHero = Font.custom(JieziFontFamily.numeric, size: 44, relativeTo: .largeTitle)'), '主值应为原型 44pt');
  assert.ok(swift.includes('static let prototypeSleepHero = Font.custom(JieziFontFamily.numeric, size: 40, relativeTo: .largeTitle)'), '睡眠主值应为 40pt');
  assert.ok(swift.includes('static let prototypeBrand = Font.custom(JieziFontFamily.serif, size: 20, relativeTo: .title2)'), '品牌应使用衬线');
  assert.ok(swift.includes('static let prototypeBook = Font.custom(JieziFontFamily.serif, size: 32, relativeTo: .title)'), '阅读书名应遵循主原型 32pt 衬线主值');
});

test('IOS-V2-POLISH-009 reading scene keeps alternating 10pt bands and the reference dark wash', () => {
  const swift = generate();
  assert.ok(swift.includes('let stripeWidth: CGFloat'));
  assert.ok(swift.includes('stripeWidth: 10'));
  assert.ok(swift.includes('Color(jieziHex: "#10211F").opacity(0.82), location: 0.6'));
});

test('IOS-V2-POLISH-009 domain data colors remain distinct from the green action color', () => {
  const swift = generate();
  assert.ok(swift.includes('let dataAccent: Color'));
  assert.ok(swift.includes('let pagerAccent: Color'));
  assert.ok(swift.includes('dataAccent: Color(jieziHex: "#9A96F0")'));
  assert.ok(swift.includes('dataAccent: Color(jieziHex: "#B45309")'));
});

test('IOS-V2-POLISH-011-B repeated iOS generation is deterministic', () => {
  assert.equal(generate(), generate());
});

test('IOS-V2-POLISH-010 shared iOS cards use prototype 16pt inset and restrained surface', () => {
  const card = generate().split('struct JieziCardStyle: ViewModifier {')[1].split('extension View {')[0];
  assert.ok(card.includes('.padding(16)'), '原型卡片内边距为 16pt');
  assert.ok(card.includes('.opacity(solid ? 0.92 : 0.66)'), '半透明表面由原型 Token 控制');
  assert.ok(!card.includes('JieziShadows.Semantic.card'), '不得继续消费旧主题卡片阴影');
});

test('IOS-V2-POLISH-011-B changing iOS-only font and scene tokens leaves emitted PWA CSS and Tailwind unchanged', () => {
  const dir = mkdtempSync(join(tmpdir(), 'jiezi-pwa-isolation-'));
  // 只清理本测试创建的专属临时目录。
  assert.equal(dirname(dir), tmpdir());
  try {
    mkdirSync(join(dir, 'scripts'));
    mkdirSync(join(dir, 'tokens'));
    for (const script of ['generate-css.mjs', 'generate-tailwind.mjs']) {
      writeFileSync(join(dir, 'scripts', script), read(`trae-design-system/scripts/${script}`));
    }
    const tokens = JSON.parse(read('trae-design-system/tokens/design-tokens.json'));
    const output = () => {
      writeFileSync(join(dir, 'tokens/design-tokens.json'), JSON.stringify(tokens));
      for (const script of ['generate-css.mjs', 'generate-tailwind.mjs']) {
        execFileSync(process.execPath, [join(dir, 'scripts', script)], { cwd: dir });
      }
      return ['pwa/tokens.css', 'pwa/tokens.js', 'tailwind/jiezi-tailwind.config.cjs'].map(path =>
        readFileSync(join(dir, 'dist', path), 'utf8').replace(/自动生成于 [^\n]+/g, '自动生成于 <timestamp>')
      );
    };
    const before = output();
    tokens.typography.font_families.ios.prototype_sans = 'NotoSansSC-Thin';
    tokens.ios_prototype.domains.sleep.glow = '#000000';
    tokens.ios_prototype.layout.cat_width = 999;
    assert.deepEqual(output(), before);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('IOS-V2-POLISH-011-B font registration retains full serif and numbers and removes the unused Sans bundle', () => {
  for (const path of ['ios/project.yml', 'ios/SnapCount/Info.plist']) {
    const source = read(path);
    assert.ok(!source.includes('Fonts/NotoSansSC-Variable.ttf'));
    assert.ok(source.includes('Fonts/NotoSerifSC-Variable.ttf'));
    assert.ok(source.includes('Fonts/Nunito-Variable.ttf'));
  }
  assert.ok(!existsSync(new URL('../ios/SnapCount/Resources/Fonts/NotoSansSC-Variable.ttf', import.meta.url)));
});
