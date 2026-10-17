#!/usr/bin/env node
/**
 * iOS Swift Token 生成脚本
 *
 * 输入：tokens/design-tokens.json (SSOT)
 * 输出：dist/jiezi/JieziTheme+Generated.swift
 *
 * 使用：
 *   node scripts/generate-ios.mjs
 *
 * v0.2 产物特性：
 *   - 自包含：自带 Color(hex:) / blended(with:amount:)，不再依赖手写 JieziTheme.swift
 *   - 全部 9 个主题的 Palette + 运行时切换（JieziThemeManager.shared）
 *   - 派生色 line（brand 13%）作为 Palette 计算属性
 *   - 时间相位 + 相邻相位线性插值（transition_minutes）
 *   - 主题感知阴影（按 palette 解析 color_ref，不再硬编码首个主题）
 *   - 语义字体角色 JieziType（serif 标题 / rounded 金额数字）
 *   - 描边 JieziStroke（金线 0.5mm）/ 图标尺寸 JieziIcon
 *   - 数据域色 JieziDomainColor / 艺术色 JieziArtColor / 触觉 JieziHaptics
 *   - spring 参数与视觉实验室决定一致（response 0.42 / damping 0.82）
 *   - 卡片表面修饰符 jieziCard（玻璃卡 / 实卡）
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ROOT = resolve(__dirname, '..');
const REPO_ROOT = resolve(ROOT, '..');

const args = new Set(process.argv.slice(2));
const knownArgs = new Set(['--check', '--sync-app']);
for (const arg of args) {
  if (!knownArgs.has(arg)) throw new Error(`未知参数：${arg}`);
}
if (args.has('--check') && args.has('--sync-app')) {
  throw new Error('--check 与 --sync-app 不能同时使用');
}
const checkOnly = args.has('--check');
const syncApp = args.has('--sync-app');

const tokens = JSON.parse(readFileSync(join(ROOT, 'tokens/design-tokens.json'), 'utf8'));
const outDir = join(ROOT, 'dist/jiezi');

const swiftWeight = (w) => {
  const map = { regular: '.regular', medium: '.medium', semibold: '.semibold', bold: '.bold' };
  return map[w] || '.regular';
};
const swiftTextStyle = (id) => id === 'title1' ? 'title' : id;

const fontById = Object.fromEntries(tokens.typography.scale.map((f) => [f.id, f]));

function catPathCommands(source, pose) {
  const parts = source.match(/[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)/g) ?? [];
  if (parts[0] !== 'M') throw new Error(`cat_paths.${pose} 必须以 M 开始`);
  let index = 1;
  const number = () => {
    const value = Number(parts[index++]);
    if (!Number.isFinite(value)) throw new Error(`cat_paths.${pose} 坐标无效`);
    return value;
  };
  const commands = [`path.move(to: CGPoint(x: ${number()}, y: ${number()}))`];
  while (index < parts.length) {
    if (parts[index++] !== 'C' || index + 6 > parts.length) {
      throw new Error(`cat_paths.${pose} 只支持单个 M 和完整 C 曲线序列`);
    }
    const x1 = number(), y1 = number(), x2 = number(), y2 = number(), x = number(), y = number();
    commands.push(`path.addCurve(to: CGPoint(x: ${x}, y: ${y}), control1: CGPoint(x: ${x1}, y: ${y1}), control2: CGPoint(x: ${x2}, y: ${y2}))`);
  }
  return commands;
}

const lines = [];
lines.push('//');
lines.push('//  JieziTheme+Generated.swift');
lines.push('//  SnapCount');
lines.push('//');
lines.push(`//  数据源：trae-design-system/tokens/design-tokens.json v${tokens.$meta.version}`);
lines.push('//  禁止手工修改本文件。任何调整请改 SSOT 后运行 scripts/generate-ios.mjs');
lines.push('//');
lines.push('');
lines.push('import SwiftUI');
lines.push('import UIKit');
lines.push('');

// MARK: 自包含颜色工具
lines.push('// MARK: - 颜色工具（自包含，勿与手写版重复定义）');
lines.push('');
lines.push('extension Color {');
lines.push('    init(jieziHex: String) {');
lines.push('        let cleaned = jieziHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)');
lines.push('        var value: UInt64 = 0');
lines.push('        Scanner(string: cleaned).scanHexInt64(&value)');
lines.push('        let red = Double((value >> 16) & 0xFF) / 255');
lines.push('        let green = Double((value >> 8) & 0xFF) / 255');
lines.push('        let blue = Double(value & 0xFF) / 255');
lines.push('        self.init(red: red, green: green, blue: blue)');
lines.push('    }');
lines.push('');
lines.push('    func jieziBlended(with other: Color, amount: Double) -> Color {');
lines.push('        let ratio = CGFloat(min(max(amount, 0), 1))');
lines.push('        let lhs = UIColor(self)');
lines.push('        let rhs = UIColor(other)');
lines.push('        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0');
lines.push('        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0');
lines.push('        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)');
lines.push('        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)');
lines.push('        return Color(');
lines.push('            red: Double(lr + (rr - lr) * ratio),');
lines.push('            green: Double(lg + (rg - lg) * ratio),');
lines.push('            blue: Double(lb + (rb - lb) * ratio),');
lines.push('            opacity: Double(la + (ra - la) * ratio)');
lines.push('        )');
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 主题 Palette
lines.push('// MARK: - 主题 Palette（运行时可切换）');
lines.push('');
lines.push('struct JieziGeneratedPalette {');
lines.push('    let id: String');
lines.push('    let name: String');
lines.push('    let description: String');
lines.push('    let paper: Color');
lines.push('    let brand: Color');
lines.push('    let light: Color');
lines.push('    let space: Color');
lines.push('    let ink: Color');
lines.push('    let muted: Color');
lines.push('    let coral: Color');
lines.push('');
lines.push('    /// 派生分隔线色：brand 13%（SSOT 派生规则，不是独立槽位）');
lines.push('    var line: Color { brand.opacity(0.13) }');
lines.push('');
tokens.color.themes.forEach((t) => {
  lines.push(`    static let ${t.id} = JieziGeneratedPalette(`);
  lines.push(`        id: "${t.id}", name: "${t.name}", description: "${t.description}",`);
  lines.push(`        paper: Color(jieziHex: "${t.colors.paper}"),`);
  lines.push(`        brand: Color(jieziHex: "${t.colors.brand}"),`);
  lines.push(`        light: Color(jieziHex: "${t.colors.light}"),`);
  lines.push(`        space: Color(jieziHex: "${t.colors.space}"),`);
  lines.push(`        ink: Color(jieziHex: "${t.colors.ink}"),`);
  lines.push(`        muted: Color(jieziHex: "${t.colors.muted}"),`);
  lines.push(`        coral: Color(jieziHex: "${t.colors.coral}")`);
  lines.push(`    )`);
  lines.push('');
});
lines.push('    /// 全部主题清单，供设置页展示与切换');
lines.push('    static let all: [JieziGeneratedPalette] = [');
tokens.color.themes.forEach((t) => lines.push(`        .${t.id},`));
lines.push('    ]');
lines.push('');
const iosDefault = tokens.color.themes.find((t) => t.is_default_ios) || tokens.color.themes[0];
lines.push('    /// iOS 默认主题');
lines.push(`    static let defaultPalette: JieziGeneratedPalette = .${iosDefault.id}`);
lines.push('}');
lines.push('');

// MARK: 主题管理器
lines.push('// MARK: - 主题运行时管理器（ObservableObject）');
lines.push('');
lines.push('final class JieziThemeManager: ObservableObject {');
lines.push('    /// 全局共享实例。App 根部应使用 @StateObject 持有同一实例并 environmentObject 注入，');
lines.push('    /// 各处读取请用注入的实例，不要自行新建。');
lines.push('    static let shared = JieziThemeManager()');
lines.push('');
lines.push('    @Published var palette: JieziGeneratedPalette');
lines.push('    @Published var hourOffset: Int = 0');
lines.push('');
lines.push('    init() {');
lines.push('        self.palette = .defaultPalette');
lines.push('    }');
lines.push('');
lines.push('    /// 历史 jiezi.theme.id 保留，但不再控制应用外观。');
lines.push('    func switchTo(_ id: String) {}');
lines.push('}');
lines.push('');

// MARK: 原型五域场景
lines.push('// MARK: - iOS 原型五域场景 Token');
lines.push('');
lines.push('struct JieziSceneTokens {');
lines.push('    let background: [Color]');
lines.push('    let accent: Color');
lines.push('    let foreground: Color');
lines.push('    let muted: Color');
lines.push('    let surface: Color');
lines.push('    let usesDiagonalTexture: Bool');
lines.push('}');
lines.push('');
lines.push('enum JieziScene {');
Object.entries(tokens.ios_prototype.domains).forEach(([id, scene]) => {
  lines.push(`    static let ${id} = JieziSceneTokens(background: [${scene.background.map((color) => `Color(jieziHex: "${color}")`).join(', ')}], accent: Color(jieziHex: "${scene.accent}"), foreground: Color(jieziHex: "${scene.foreground}"), muted: Color(jieziHex: "${scene.muted}"), surface: Color(jieziHex: "${scene.surface}"), usesDiagonalTexture: ${scene.texture === 'diagonal'})`);
});
lines.push('');
lines.push('    static func tokens(for domain: String) -> JieziSceneTokens {');
lines.push('        switch domain {');
Object.keys(tokens.ios_prototype.domains).forEach((id) => lines.push(`        case "${id}": return .${id}`));
lines.push('        default: return .expense');
lines.push('        }');
lines.push('    }');
lines.push('}');
lines.push('');
lines.push('enum JieziPrototypeLayout {');
Object.entries(tokens.ios_prototype.layout).forEach(([id, value]) => lines.push(`    static let ${id}: CGFloat = ${value}`));
lines.push('}');
lines.push('');
lines.push('enum JieziPrototypeMotion {');
Object.entries(tokens.ios_prototype.motion).forEach(([id, value]) => lines.push(`    static let ${id}: TimeInterval = ${value / 1000}`));
lines.push('}');
lines.push('');

lines.push('enum JieziCatPose: String {');
Object.keys(tokens.ios_prototype.cat_paths).forEach((id) => lines.push(`    case ${id}`));
lines.push('');
lines.push('    static func forDomain(_ domain: String) -> JieziCatPose {');
lines.push('        JieziCatPose(rawValue: domain) ?? .expense');
lines.push('    }');
lines.push('}');
lines.push('');
lines.push('struct JieziCatShape: Shape {');
lines.push('    let pose: JieziCatPose');
lines.push('');
lines.push('    func path(in rect: CGRect) -> Path {');
lines.push('        var path = Path()');
lines.push('        switch pose {');
Object.entries(tokens.ios_prototype.cat_paths).forEach(([id, source]) => {
  lines.push(`        case .${id}:`);
  catPathCommands(source, id).forEach((command) => lines.push(`            ${command}`));
});
lines.push('        }');
lines.push('        let scale = min(rect.width / 210, rect.height / 200)');
lines.push('        let x = rect.midX - 105 * scale');
lines.push('        let y = rect.midY - 100 * scale');
lines.push('        return path.applying(CGAffineTransform(scaleX: scale, y: scale))');
lines.push('            .applying(CGAffineTransform(translationX: x, y: y))');
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 时间相位（含插值）
lines.push('// MARK: - 时间相位（与 PWA 一致，相邻相位线性插值）');
lines.push('');
lines.push('struct JieziPhase {');
lines.push('    let id: String');
lines.push('    let name: String');
lines.push('    let start: Int');
lines.push('    let end: Int');
lines.push('    let warmth: Double');
lines.push('    let brightness: Double');
lines.push('    let saturation: Double');
lines.push('    let spaceShift: Double');
lines.push('');
lines.push(`    /// 相邻相位在边界前后各 transitionMinutes/2 分钟内线性插值`);
lines.push(`    static let transitionMinutes: Double = ${tokens.time_phases.transition_minutes}`);
lines.push('');
tokens.time_phases.phases.forEach((p) => {
  lines.push(`    static let ${p.id} = JieziPhase(id: "${p.id}", name: "${p.name}", start: ${p.start}, end: ${p.end}, warmth: ${p.warmth}, brightness: ${p.brightness}, saturation: ${p.saturation}, spaceShift: ${p.spaceShift})`);
});
lines.push('');
lines.push('    static let all: [JieziPhase] = [');
tokens.time_phases.phases.forEach((p) => lines.push(`        .${p.id},`));
lines.push('    ]');
lines.push('');
lines.push('    static func at(hour: Int) -> JieziPhase {');
lines.push('        let h = ((hour % 24) + 24) % 24');
lines.push('        return all.first(where: { h >= $0.start && h < $0.end }) ?? .deepNight');
lines.push('    }');
lines.push('}');
lines.push('');
lines.push('/// 插值后的相位数值（用于实时调色）');
lines.push('struct JieziPhaseValues {');
lines.push('    let warmth: Double');
lines.push('    let brightness: Double');
lines.push('    let saturation: Double');
lines.push('    let spaceShift: Double');
lines.push('}');
lines.push('');
lines.push('extension JieziPhase {');
lines.push('    /// 计算某时刻的插值相位数值。边界前后 transitionMinutes/2 内与相邻相位线性混合，避免整点跳变。');
lines.push('    static func values(atHour hour: Int, minute: Int = 0) -> JieziPhaseValues {');
lines.push('        let t = (Double(hour) * 60 + Double(minute)).truncatingRemainder(dividingBy: 1440)');
lines.push('        let tr = transitionMinutes / 2');
lines.push('        guard let idx = all.firstIndex(where: { t >= Double($0.start) * 60 && t < Double($0.end) * 60 }) else {');
lines.push('            return JieziPhaseValues(warmth: deepNight.warmth, brightness: deepNight.brightness, saturation: deepNight.saturation, spaceShift: deepNight.spaceShift)');
lines.push('        }');
lines.push('        let p = all[idx]');
lines.push('        let startM = Double(p.start) * 60');
lines.push('        let endM = Double(p.end) * 60');
lines.push('        if t - startM < tr {');
lines.push('            let prev = all[(idx - 1 + all.count) % all.count]');
lines.push('            let progress = ((t - startM) + tr) / (2 * tr)');
lines.push('            return lerp(prev, p, progress)');
lines.push('        } else if endM - t < tr {');
lines.push('            let next = all[(idx + 1) % all.count]');
lines.push('            let progress = (t - (endM - tr)) / (2 * tr)');
lines.push('            return lerp(p, next, progress)');
lines.push('        }');
lines.push('        return JieziPhaseValues(warmth: p.warmth, brightness: p.brightness, saturation: p.saturation, spaceShift: p.spaceShift)');
lines.push('    }');
lines.push('');
lines.push('    private static func lerp(_ a: JieziPhase, _ b: JieziPhase, _ k: Double) -> JieziPhaseValues {');
lines.push('        JieziPhaseValues(');
lines.push('            warmth: a.warmth + (b.warmth - a.warmth) * k,');
lines.push('            brightness: a.brightness + (b.brightness - a.brightness) * k,');
lines.push('            saturation: a.saturation + (b.saturation - a.saturation) * k,');
lines.push('            spaceShift: a.spaceShift + (b.spaceShift - a.spaceShift) * k');
lines.push('        )');
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 间距
lines.push('// MARK: - 间距 Token');
lines.push('');
lines.push('enum JieziSpacing {');
tokens.spacing.scale.forEach((s) => {
  lines.push(`    static let ${s.id}: CGFloat = ${s.value}`);
});
lines.push('');
lines.push('    enum Semantic {');
Object.entries(tokens.spacing.semantic).forEach(([k, v]) => {
  lines.push(`        static let ${k}: CGFloat = ${v.value}`);
});
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 圆角
lines.push('// MARK: - 圆角 Token');
lines.push('');
lines.push('enum JieziRadius {');
tokens.radius.scale.forEach((s) => {
  lines.push(`    static let ${s.id}: CGFloat = ${s.value}`);
});
lines.push('');
lines.push('    enum Semantic {');
Object.entries(tokens.radius.semantic).forEach(([k, v]) => {
  lines.push(`        static let ${k}: CGFloat = ${v.value}`);
});
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 阴影（主题感知）
lines.push('// MARK: - 阴影 Token（按 palette 解析颜色，主题感知）');
lines.push('');
lines.push('struct JieziShadow {');
lines.push('    let color: Color');
lines.push('    let alpha: Double');
lines.push('    let radius: CGFloat');
lines.push('    let x: CGFloat');
lines.push('    let y: CGFloat');
lines.push('}');
lines.push('');
lines.push('enum JieziShadows {');
tokens.shadow.scale.forEach((s) => {
  if (s.alpha === 0) {
    lines.push(`    static let ${s.id} = JieziShadow(color: .clear, alpha: 0, radius: 0, x: 0, y: 0)`);
  } else {
    lines.push(`    static func ${s.id}(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow {`);
    lines.push(`        JieziShadow(color: p.${s.color_ref}, alpha: ${s.alpha}, radius: ${s.radius}, x: ${s.x}, y: ${s.y})`);
    lines.push('    }');
  }
});
lines.push('');
lines.push('    enum Semantic {');
Object.entries(tokens.shadow.semantic).forEach(([k, v]) => {
  lines.push(`        /// 语义阴影：${k} → ${v.ref}`);
  lines.push(`        static func ${k}(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow { JieziShadows.${v.ref}(p) }`);
});
lines.push('    }');
lines.push('}');
lines.push('');
lines.push('extension View {');
lines.push('    func jieziShadow(_ shadow: JieziShadow) -> some View {');
lines.push('        self.shadow(color: shadow.color.opacity(shadow.alpha), radius: shadow.radius, x: shadow.x, y: shadow.y)');
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 字体层级
lines.push('// MARK: - 字体 Token（HIG 层级）');
lines.push('');
lines.push('enum JieziFont {');
tokens.typography.scale.forEach((f) => {
  lines.push(`    static let ${f.id} = Font.custom(JieziFontFamily.sans, size: ${f.ios_size}, relativeTo: .${swiftTextStyle(f.id)}).weight(${swiftWeight(f.ios_weight)})`);
});
lines.push('}');
lines.push('');

lines.push('enum JieziFontFamily {');
lines.push(`    static let sans = "${tokens.typography.font_families.ios.prototype_sans}"`);
lines.push(`    static let serif = "${tokens.typography.font_families.ios.prototype_serif}"`);
lines.push(`    static let numeric = "${tokens.typography.font_families.ios.prototype_numeric}"`);
lines.push('}');
lines.push('');

// MARK: 语义字体角色
lines.push('// MARK: - 语义字体角色（「芥子味」：serif 标题 + rounded 金额）');
lines.push('/// 注意：money 系列角色在使用处追加 .monospacedDigit()（SSOT numeric 规则）。');
lines.push('enum JieziType {');
Object.entries(tokens.typography.roles).forEach(([roleId, role]) => {
  if (roleId === '$description') return;
  const base = fontById[role.ref];
  const weight = role.weight_override || base.ios_weight;
  const family = role.numeric ? 'numeric' : role.design === 'serif' ? 'serif' : 'sans';
  lines.push(`    /// ${role.usage}`);
  lines.push(`    static let ${roleId} = Font.custom(JieziFontFamily.${family}, size: ${base.ios_size}, relativeTo: .${swiftTextStyle(role.ref)}).weight(${swiftWeight(weight)})`);
});
lines.push('}');
lines.push('');

// MARK: 描边
lines.push('// MARK: - 描边 Token（金线 0.5mm 为骨）');
lines.push('');
lines.push('struct JieziStrokeStyle {');
lines.push('    let color: Color');
lines.push('    let width: CGFloat');
lines.push('}');
lines.push('');
lines.push('enum JieziStroke {');
Object.entries(tokens.stroke).forEach(([k, v]) => {
  if (k === '$description') return;
  lines.push(`    /// ${v.usage}`);
  lines.push(`    static func ${k}(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziStrokeStyle {`);
  lines.push(`        JieziStrokeStyle(color: p.${v.color_ref}.opacity(${v.alpha}), width: ${v.width})`);
  lines.push('    }');
});
lines.push('}');
lines.push('');

// MARK: 图标尺寸
lines.push('// MARK: - 图标尺寸 Token');
lines.push('');
lines.push('enum JieziIcon {');
tokens.icon.scale.forEach((s) => {
  lines.push(`    /// ${s.usage}`);
  lines.push(`    static let ${s.id}: CGFloat = ${s.value}`);
});
lines.push('');
lines.push('    enum Semantic {');
Object.entries(tokens.icon.semantic).forEach(([k, v]) => {
  lines.push(`        static let ${k}: CGFloat = ${v.value}`);
});
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 数据域色
lines.push('// MARK: - 数据域色（全局固定，不随主题切换）');
lines.push('');
lines.push('enum JieziDomainColor {');
Object.entries(tokens.color.domains).forEach(([k, v]) => {
  if (k === '$description') return;
  lines.push(`    /// ${v.name}`);
  lines.push(`    static let ${k} = Color(jieziHex: "${v.hex}")`);
});
lines.push('');
lines.push('    static func color(for domain: String) -> Color {');
lines.push('        switch domain {');
Object.entries(tokens.color.domains).forEach(([k, v]) => {
  if (k === '$description') return;
  lines.push(`        case "${k}": return JieziDomainColor.${k}`);
});
lines.push('        default: return JieziThemeManager.shared.palette.brand');
lines.push('        }');
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 艺术色
lines.push('// MARK: - 艺术版专用色（功能页面禁用）');
lines.push('');
lines.push('enum JieziArtColor {');
Object.entries(tokens.color.art).forEach(([k, v]) => {
  if (k === '$description') return;
  const camel = k.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
  lines.push(`    /// ${v.usage}`);
  lines.push(`    static let ${camel} = Color(jieziHex: "${v.hex}")`);
});
lines.push('}');
lines.push('');

// MARK: 动效
lines.push('// MARK: - 动效 Token');
lines.push('');
lines.push('enum JieziDuration {');
tokens.motion.durations.forEach((d) => {
  lines.push(`    static let ${d.id}: TimeInterval = ${d.ms / 1000}`);
});
lines.push('}');
lines.push('');
lines.push('enum JieziEasing {');
tokens.motion.easings.forEach((e) => {
  const springMatch = e.ios.match(/^spring\(response:([\d.]+),dampingFraction:([\d.]+)\)$/);
  if (springMatch) {
    lines.push(`    static let ${e.id} = Animation.spring(response: ${springMatch[1]}, dampingFraction: ${springMatch[2]})`);
  } else {
    lines.push(`    static let ${e.id} = Animation.${e.ios}(duration: JieziDuration.normal)`);
  }
});
lines.push('}');
lines.push('');

// MARK: 触觉
lines.push('// MARK: - 触觉反馈 Token');
lines.push('');
lines.push('enum JieziHaptics {');
Object.entries(tokens.haptics).forEach(([k, v]) => {
  if (k === '$description') return;
  lines.push(`    /// ${v.usage}`);
  if (v.ios.startsWith('UIImpactFeedbackGenerator.')) {
    const style = v.ios.split('.')[1];
    lines.push(`    static func ${k}() { UIImpactFeedbackGenerator(style: .${style}).impactOccurred() }`);
  } else {
    const kind = v.ios.split('.')[1];
    lines.push(`    static func ${k}() { UINotificationFeedbackGenerator().notificationOccurred(.${kind}) }`);
  }
});
lines.push('}');
lines.push('');

// MARK: 渐变构建器
lines.push('// MARK: - 渐变构建器');
lines.push('');
lines.push('enum JieziGradient {');
lines.push('    static func pageBackground(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> LinearGradient {');
lines.push('        LinearGradient(');
lines.push('            colors: JieziScene.expense.background,');
lines.push('            startPoint: .top,');
lines.push('            endPoint: .bottomTrailing');
lines.push('        )');
lines.push('    }');
lines.push('');
lines.push('    static func sumeruBackground(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> RadialGradient {');
lines.push('        RadialGradient(');
lines.push('            colors: [');
lines.push('                palette.brand.jieziBlended(with: palette.light, amount: 0.16),');
lines.push('                palette.space,');
lines.push('                palette.space.jieziBlended(with: .black, amount: 0.58)');
lines.push('            ],');
lines.push('            center: .center,');
lines.push('            startRadius: 18,');
lines.push('            endRadius: 520');
lines.push('        )');
lines.push('    }');
lines.push('');
lines.push('    static func brandWash(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> LinearGradient {');
lines.push('        LinearGradient(');
lines.push('            colors: [');
lines.push('                palette.brand.opacity(0.92),');
lines.push('                palette.brand.jieziBlended(with: palette.space, amount: 0.22)');
lines.push('            ],');
lines.push('            startPoint: .topLeading,');
lines.push('            endPoint: .bottomTrailing');
lines.push('        )');
lines.push('    }');
lines.push('}');
lines.push('');

// MARK: 卡片表面
const glass = tokens.glass.card;
const solid = tokens.glass.solid_card;
lines.push('// MARK: - 卡片表面修饰符（玻璃卡 / 实卡）');
lines.push('');
lines.push('struct JieziCardStyle: ViewModifier {');
lines.push('    let palette: JieziGeneratedPalette');
lines.push('    var solid: Bool = false');
lines.push('');
lines.push('    func body(content: Content) -> some View {');
lines.push('        content');
lines.push(`            .padding(${glass.padding.value})`);
lines.push('            .background {');
lines.push('                if solid {');
lines.push(`                    RoundedRectangle(cornerRadius: ${solid.radius.value}, style: .continuous)`);
lines.push('                        .fill(JieziScene.expense.surface)');
lines.push('                } else {');
lines.push(`                    RoundedRectangle(cornerRadius: ${glass.radius.value}, style: .continuous)`);
lines.push('                        .fill(JieziScene.expense.surface)');
lines.push('                }');
lines.push('            }');
lines.push('            .overlay {');
lines.push(`                RoundedRectangle(cornerRadius: ${glass.radius.value}, style: .continuous)`);
lines.push(`                    .stroke(palette.brand.opacity(solid ? ${solid.stroke_alpha} : ${glass.stroke_alpha}), lineWidth: 1)`);
lines.push('            }');
lines.push('            .jieziShadow(solid ? JieziShadows.sm(palette) : JieziShadows.Semantic.card(palette))');
lines.push('    }');
lines.push('}');
lines.push('');
lines.push('extension View {');
lines.push('    /// 芥子卡片：默认玻璃卡（材质+宣纸底色），solid: true 为实卡（列表行/小卡场景）。');
lines.push('    func jieziCard(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette, solid: Bool = false) -> some View {');
lines.push('        modifier(JieziCardStyle(palette: palette, solid: solid))');
lines.push('    }');
lines.push('}');
lines.push('');

const generatedSwift = `${lines.join('\n').trimEnd()}\n`;
const outPath = join(outDir, 'JieziTheme+Generated.swift');
const appPath = join(REPO_ROOT, 'ios/SnapCount/DesignSystem/JieziTheme+Generated.swift');

if (checkOnly) {
  const appSwift = readFileSync(appPath, 'utf8').replace(/\r\n/g, '\n');
  if (appSwift !== generatedSwift) {
    console.error(`✗ App Token 副本与 SSOT 不一致：${appPath}`);
    process.exitCode = 1;
  } else {
    console.log(`✓ App Token 副本与 SSOT 一致：${appPath}`);
  }
} else {
  mkdirSync(outDir, { recursive: true });
  writeFileSync(outPath, generatedSwift, 'utf8');
  console.log(`✓ iOS Swift Token 已生成：${outPath}`);
  if (syncApp) {
    writeFileSync(appPath, generatedSwift, 'utf8');
    console.log(`✓ iOS App 编译副本已同步：${appPath}`);
  }
}
console.log(`  - ${tokens.color.themes.length} 个主题（含派生 line 计算属性）`);
console.log(`  - ${tokens.time_phases.phases.length} 个时间相位 + 线性插值（transition ${tokens.time_phases.transition_minutes}min）`);
console.log(`  - ${tokens.typography.scale.length} 个字体层级 + ${Object.keys(tokens.typography.roles).filter((k) => k !== '$description').length} 个语义角色`);
console.log(`  - ${tokens.spacing.scale.length} 个间距 / ${tokens.radius.scale.length} 个圆角 / ${tokens.shadow.scale.length} 个阴影（主题感知）`);
console.log(`  - ${Object.keys(tokens.stroke).filter((k) => k !== '$description').length} 个描边 / ${tokens.icon.scale.length} 个图标尺寸`);
console.log(`  - ${Object.keys(tokens.color.domains).filter((k) => k !== '$description').length} 个域色 / ${Object.keys(tokens.color.art).filter((k) => k !== '$description').length} 个艺术色 / ${Object.keys(tokens.haptics).filter((k) => k !== '$description').length} 个触觉`);
console.log(`  - spring 参数化（response/dampingFraction 来自 SSOT）`);
console.log(`  - jieziCard 卡片表面修饰符（玻璃卡/实卡）`);
