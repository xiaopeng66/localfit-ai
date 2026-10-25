#!/usr/bin/env node
/**
 * LocalFit AI · 定稿 logo（K8 = K7 − 环境辉光）的交付变体。
 *
 * 选定设计：空心霓虹管——近黑底、薄荷环正上方破开、悬浮珊瑚脉搏、
 * 光衰减 + 管内残光 + 玻璃高光 + 电极节点；icon 版带 SMIL 心跳动画
 * （几何与 tube-polish.mjs 的 K8 一致，icon 由那边生成）。
 *
 * 本脚本补齐另外两件套：
 *   - k8-final-ios.svg   满幅直角方底（iOS AppIcon；静态，取动画第 0 帧）
 *   - k8-final-mark.svg  透明底、浅色场景用（App 内标题）：mask 真镂空、
 *                        无发光层、电极改深珊瑚——薄荷奶油浅色 UI 里直接可放
 *
 * 运行：node design/logo/finalize.mjs
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SIZE, arc } from './kit.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SVG_DIR = join(HERE, 'svg');
mkdirSync(SVG_DIR, { recursive: true });

// ── 与 tube-polish.mjs 的 K8 一致的几何与色彩 ──────────────────────────────
const CX = 512;
const CY = 512;
const R = 280;
const BREAK = 40;
const CHORD_Y = +(CY - R * Math.cos((BREAK * Math.PI) / 180)).toFixed(1);
const X1 = +(CX - R * Math.sin((BREAK * Math.PI) / 180)).toFixed(1);
const X2 = +(CX + R * Math.sin((BREAK * Math.PI) / 180)).toFixed(1);

const BG = '#0F1412';
const W = 60; // 管外径
const PUNCH = 26; // 挖芯宽 → 壁 17

const NEON_LIT = '#6BEFBA';
const NEON = '#4ED9A6';
const NEON_DIM = '#1FA377';
const CORAL_LIT = '#FF9A75';
const CORAL = '#FF8A65';
const CORAL_DIM = '#F0704A';
const HOLE_MINT = '#19342a';
const HOLE_CORAL = '#35271f';
const HOT = '#FFE9DC';

const RING = arc(CX, CY, R, BREAK, 360 - BREAK);
const PULSE = `M400 ${CHORD_Y} L458 ${CHORD_Y} L508 206 L536 378 L578 ${CHORD_Y} L624 ${CHORD_Y}`;

const FALLOFF_DEFS = (uid) => `
    <linearGradient id="rg-${uid}" gradientUnits="userSpaceOnUse" x1="240" y1="220" x2="790" y2="810">
      <stop offset="0" stop-color="${NEON_LIT}"/>
      <stop offset="0.45" stop-color="${NEON}"/>
      <stop offset="1" stop-color="${NEON_DIM}"/>
    </linearGradient>
    <linearGradient id="pg-${uid}" gradientUnits="userSpaceOnUse" x1="${X1}" y1="${CHORD_Y}" x2="${X2}" y2="${CHORD_Y}">
      <stop offset="0" stop-color="${CORAL_LIT}"/>
      <stop offset="1" stop-color="${CORAL_DIM}"/>
    </linearGradient>`;

/** mark 专用：浅底上 NEON_LIT 对比不足，渐变从 NEON 直接压到深档。 */
const MARK_FALLOFF_DEFS = (uid) => `
    <linearGradient id="rg-${uid}" gradientUnits="userSpaceOnUse" x1="240" y1="220" x2="790" y2="810">
      <stop offset="0" stop-color="${NEON}"/>
      <stop offset="1" stop-color="${NEON_DIM}"/>
    </linearGradient>
    <linearGradient id="pg-${uid}" gradientUnits="userSpaceOnUse" x1="${X1}" y1="${CHORD_Y}" x2="${X2}" y2="${CHORD_Y}">
      <stop offset="0" stop-color="${CORAL}"/>
      <stop offset="1" stop-color="${CORAL_DIM}"/>
    </linearGradient>`;

const SPEC = `
    <path d="${arc(CX, CY, 304, 255, 318)}" fill="none" stroke="#FFFFFF" stroke-width="8" stroke-linecap="round" opacity="0.32"/>
    <path d="${arc(508, 206, 22, 300, 340)}" fill="none" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round" opacity="0.35"/>`;

const ELECTRODES = (color) => `
    <circle cx="400" cy="${CHORD_Y}" r="13" fill="${color}"/>
    <circle cx="624" cy="${CHORD_Y}" r="13" fill="${color}"/>`;

/** 实色管 + 底色挖芯（深底场景用）。 */
function tubeSolid(d, stroke, punchColor) {
  return `
    <path d="${d}" fill="none" stroke="${stroke}" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${d}" fill="none" stroke="${punchColor}" stroke-width="${PUNCH}" stroke-linecap="round" stroke-linejoin="round"/>`;
}

/** mask 真镂空定义：mark 场景管内透明，随背景走。 */
function holeMask(uid) {
  return `
    <mask id="holes-${uid}" maskUnits="userSpaceOnUse" x="0" y="0" width="${SIZE}" height="${SIZE}">
      <rect width="${SIZE}" height="${SIZE}" fill="#fff"/>
      <path d="${RING}" fill="none" stroke="#000" stroke-width="${PUNCH}" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="${PULSE}" fill="none" stroke="#000" stroke-width="${PUNCH}" stroke-linecap="round" stroke-linejoin="round"/>
    </mask>`;
}

function tubesTrueHoles(uid) {
  return `
    <g mask="url(#holes-${uid})">
      <path d="${RING}" fill="none" stroke="url(#rg-${uid})" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="${PULSE}" fill="none" stroke="url(#pg-${uid})" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
    </g>`;
}

// ── iOS：满幅直角方底（iOS 自行套圆角遮罩），静态取动画第 0 帧 ─────────────
const IOS_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">
  <defs>
    ${FALLOFF_DEFS('ios')}
    <filter id="soft-ios" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="26"/></filter>
  </defs>
  <rect width="${SIZE}" height="${SIZE}" fill="${BG}"/>
  <g filter="url(#soft-ios)" opacity="0.5">
    <path d="${PULSE}" fill="none" stroke="url(#pg-ios)" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  ${tubeSolid(RING, 'url(#rg-ios)', HOLE_MINT)}
  ${tubeSolid(PULSE, 'url(#pg-ios)', HOLE_CORAL)}
  ${SPEC}
  ${ELECTRODES(HOT)}
</svg>
`;

// ── mark：透明底、真实镂空、浅色场景（无发光层、无白色高光、深珊瑚电极） ──
const MARK_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">
  <defs>
    ${MARK_FALLOFF_DEFS('mark')}
    ${holeMask('mark')}
  </defs>
  ${tubesTrueHoles('mark')}
  ${ELECTRODES(CORAL_DIM)}
</svg>
`;

writeFileSync(join(SVG_DIR, 'k8-final-ios.svg'), IOS_SVG);
writeFileSync(join(SVG_DIR, 'k8-final-mark.svg'), MARK_SVG);

// ── Android 自适应图标前景：透明底、只留管子，整体缩到 93% 塞进 66% 安全区 ──
// 安全区 = 108dp 画布里半径 33dp 的圆（1024 单位下 r≈312.9）；
// 管子外缘最远到脉冲尖峰 (508,206)，距圆心 336 → 0.93 倍后 312.5 ✓。
const FOREGROUND_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">
  <defs>
    ${FALLOFF_DEFS('fg')}
    <filter id="soft-fg" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="26"/></filter>
  </defs>
  <g transform="translate(${CX} ${CY}) scale(0.93) translate(-${CX} -${CY})">
    <g filter="url(#soft-fg)" opacity="0.5">
      <path d="${PULSE}" fill="none" stroke="url(#pg-fg)" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
    </g>
    <path d="${RING}" fill="none" stroke="url(#rg-fg)" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${PULSE}" fill="none" stroke="url(#pg-fg)" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${RING}" fill="none" stroke="${HOLE_MINT}" stroke-width="${PUNCH}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${PULSE}" fill="none" stroke="${HOLE_CORAL}" stroke-width="${PUNCH}" stroke-linecap="round" stroke-linejoin="round"/>
    ${SPEC}
    ${ELECTRODES(HOT)}
  </g>
</svg>
`;
writeFileSync(join(SVG_DIR, 'k8-final-foreground.svg'), FOREGROUND_SVG);

// ── 预览页：用 <img> 引用文件，避开多份 SVG 内联时的 id 冲突 ────────────────
// （SMIL 动画在 <img> 里同样会跑。）
const img = (f, cls) => `<img src="svg/${f}" class="${cls}" alt="">`;

const preview = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>LocalFit AI · 定稿交付</title>
<style>
  body { margin:0; padding:44px 52px 60px; background:#FAFBF9; color:#17251E;
         font-family:"Segoe UI","Microsoft YaHei",system-ui,sans-serif; }
  h1 { font-size:28px; margin:0 0 6px; }
  .sub { color:#5A6B62; font-size:14px; margin-bottom:28px; }
  .grid { display:grid; grid-template-columns:repeat(4,1fr); gap:36px; }
  .cell { text-align:center; }
  .box { display:flex; align-items:center; justify-content:center;
         height:280px; border-radius:20px; margin-bottom:14px; }
  .bgDark { background:#0F1412; }
  .bgLight { background:#fff; box-shadow:inset 0 0 0 1px #E7ECE8; }
  .bgMint { background:#F0FBF7; box-shadow:inset 0 0 0 1px #E7ECE8; }
  img.w260 { width:260px; height:260px; }
  img.w200 { width:200px; height:200px; }
  img.w120 { width:120px; height:120px; }
  .cap { font-size:14px; color:#5A6B62; line-height:1.5; }
  .cap b { color:#17251E; }
</style></head>
<body>
<h1>LocalFit AI · 定稿</h1>
<div class="sub">空心霓虹管 K8（K7 − 环境辉光）　｜　左：启动图标（带心跳动画）　中：iOS 满幅　右：App 内 mark（浅色场景）</div>
<div class="grid">
  <div class="cell"><div class="box bgDark">${img('k8-final-icon.svg', 'w260')}</div>
    <div class="cap"><b>icon</b>（圆角方底 1024，动画）<br>Android 启动图标 / 商店 512</div></div>
  <div class="cell"><div class="box bgDark">${img('k8-final-ios.svg', 'w200')}</div>
    <div class="cap"><b>ios</b>（满幅直角 1024，静态）<br>iOS AppIcon，系统自行套圆角</div></div>
  <div class="cell"><div class="box bgLight">${img('k8-final-mark.svg', 'w120')}</div>
    <div class="cap"><b>mark</b>（透明底）on 白卡<br>App 内标题</div></div>
  <div class="cell"><div class="box bgMint">${img('k8-final-mark.svg', 'w120')}</div>
    <div class="cap"><b>mark</b>（透明底）on 薄荷 50<br>App 内标题 · 浅薄荷面</div></div>
</div>
</body></html>
`;
writeFileSync(join(HERE, 'finalize.html'), preview);

console.log('✓ k8-final-ios.svg / k8-final-mark.svg / finalize.html 已写入');
