#!/usr/bin/env node
/**
 * LocalFit AI logo 概念生成器（方案 01–06）。
 *
 * 每个概念输出三个变体：
 *   - <slug>-icon.svg  圆角方底（Android 启动图标 / 商店 512）
 *   - <slug>-ios.svg   满幅直角方底（iOS AppIcon）
 *   - <slug>-mark.svg  透明底、薄荷渐变主体（App 内标题 / 浅底场景）
 *
 * 运行：node design/logo/generate.mjs
 * 公共件（色值、几何、渲染）见 kit.mjs；概念定义见 concepts.mjs；
 * 能量环衍生方案见 ring-variants.mjs。
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderSvg } from './kit.mjs';
import { CONCEPTS } from './concepts.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SVG_DIR = join(HERE, 'svg');
mkdirSync(SVG_DIR, { recursive: true });

for (const c of CONCEPTS) {
  for (const v of ['icon', 'ios', 'mark']) {
    writeFileSync(join(SVG_DIR, `${c.slug}-${v}.svg`), renderSvg(c, v));
  }
}

// ── 预览页 ─────────────────────────────────────────────────────────────────
const iconSvg = (c) => renderSvg(c, 'icon');
const markSvg = (c) => renderSvg(c, 'mark');

const strip = CONCEPTS.map(
  (c) => `<figure class="strip-item">${iconSvg(c)}<figcaption>${c.name}</figcaption></figure>`,
).join('\n');

const rows = CONCEPTS.map(
  (c, i) => `
  <section class="row">
    <div class="hero">
      <div class="hero-icon">${iconSvg(c)}</div>
      <div class="hero-meta">
        <div class="idx">${String(i + 1).padStart(2, '0')}</div>
        <h2>${c.name}</h2>
        <div class="tag">${c.tag}</div>
      </div>
    </div>
    <div class="ladder">
      <div class="ladder-cell"><div class="s s128">${iconSvg(c)}</div><span>128</span></div>
      <div class="ladder-cell"><div class="s s64">${iconSvg(c)}</div><span>64</span></div>
      <div class="ladder-cell"><div class="s s48">${iconSvg(c)}</div><span>48</span></div>
      <div class="ladder-cell"><div class="s s32">${iconSvg(c)}</div><span>32</span></div>
      <div class="ladder-cell"><div class="s s24">${iconSvg(c)}</div><span>24</span></div>
      <div class="ladder-cell mark-cell"><div class="s s64 mark">${markSvg(c)}</div><span>mark</span></div>
    </div>
    <p class="note">${c.note}</p>
  </section>`,
).join('\n');

const html = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><title>LocalFit AI · Logo 方案对比</title>
<style>
  :root { --ink:#17251E; --ink2:#5A6B62; --ink3:#93A29A; --line:#E7ECE8; --cream:#FAFBF9; }
  * { box-sizing: border-box; }
  body { margin:0; padding:48px 56px 64px; background:var(--cream); color:var(--ink);
         font-family:"Segoe UI","Microsoft YaHei",system-ui,sans-serif; }
  h1 { font-size:30px; margin:0 0 6px; letter-spacing:-.4px; }
  .sub { color:var(--ink2); font-size:15px; margin-bottom:8px; }
  .rule { height:1px; background:var(--line); margin:28px 0 34px; }
  .strip { display:flex; gap:30px; align-items:flex-start; margin-bottom:8px; }
  .strip-item { margin:0; width:150px; text-align:center; }
  .strip-item svg { width:100%; height:auto; border-radius:26px; box-shadow:0 6px 18px rgba(23,37,30,.10); }
  .strip-item figcaption { font-size:13px; color:var(--ink2); margin-top:9px; }
  .row { display:grid; grid-template-columns:300px 1fr; gap:8px 40px; align-items:center;
         padding:30px 0; border-top:1px solid var(--line); }
  .hero { display:flex; gap:20px; align-items:center; }
  .hero-icon { width:190px; flex:0 0 190px; }
  .hero-icon svg { width:100%; height:auto; border-radius:42px; box-shadow:0 8px 22px rgba(23,37,30,.12); }
  .idx { font-size:12px; color:var(--ink3); letter-spacing:1.5px; font-weight:700; }
  h2 { font-size:22px; margin:2px 0 5px; letter-spacing:-.2px; }
  .tag { font-size:13px; color:#1FA377; }
  .ladder { display:flex; align-items:flex-end; gap:26px; }
  .ladder-cell { display:flex; flex-direction:column; align-items:center; gap:7px; }
  .ladder-cell span { font-size:11px; color:var(--ink3); }
  .s svg { display:block; border-radius:22%; }
  .s128 svg { width:128px; height:128px; box-shadow:0 5px 14px rgba(23,37,30,.10); }
  .s64 svg  { width:64px;  height:64px;  box-shadow:0 3px 9px rgba(23,37,30,.09); }
  .s48 svg  { width:48px;  height:48px;  box-shadow:0 2px 7px rgba(23,37,30,.08); }
  .s32 svg  { width:32px;  height:32px; }
  .s24 svg  { width:24px;  height:24px; }
  .mark-cell { padding-left:26px; border-left:1px solid var(--line); }
  .mark svg { background:#fff; border-radius:22%; box-shadow:inset 0 0 0 1px var(--line); }
  .note { grid-column:2; margin:16px 0 0; font-size:14px; line-height:1.65; color:var(--ink2); }
</style></head>
<body>
  <h1>LocalFit AI · Logo 方案</h1>
  <div class="sub">本地优先 · AI 辅助 · 校园饮食与健身管理　｜　色彩取自 app_colors.dart，形状取自 docs/10 形状系统</div>
  <div class="strip">${strip}</div>
  <div class="rule"></div>
  ${rows}
</body></html>
`;
writeFileSync(join(HERE, 'preview.html'), html);

console.log(`✓ ${CONCEPTS.length * 3} 个 SVG + preview.html 已写入 ${SVG_DIR}`);
