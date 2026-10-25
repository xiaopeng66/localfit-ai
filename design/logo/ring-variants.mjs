#!/usr/bin/env node
/**
 * LocalFit AI · 能量环（方案 02）衍生变体。
 *
 * 用户选定 02 能量环后，在保持「薄荷环 + 营养三色 + 圆形构图 + 缺口开口朝上」
 * 这四条骨架不变的前提下，穷举「三宏量」的图形表达：
 *
 *   A 02a-arc       内三弧加粗、断口拉大（在选中的 02 上直接微调）
 *   B 02b-dots      环内三颗圆点
 *   C 02c-bars      环内三段径向圆角条，指向上左/下/左上
 *   D 02d-spark     环内一颗薄荷星芒（表达 AI 辅助，不表达三宏量）
 *   E 02e-segments  单环切四段：长段=热量进度，三段彩色=三宏量
 *   F 02f-gauge     细轨道环 + 进度游标圆点 + 内三弧
 *
 * 运行：node design/logo/ring-variants.mjs
 * 输出样式、安全区校验、预览页写法与 generate.mjs 一致（公共件见 kit.mjs）。
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { C, arc, bg, defs, MINT, renderSvg, roundedArc, spark } from './kit.mjs';
import { bySlug } from './concepts.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SVG_DIR = join(HERE, 'svg');
mkdirSync(SVG_DIR, { recursive: true });

const CX = 512;
const CY = 512;

/** 三宏量按「蛋白 → 碳水 → 脂肪」固定顺序，色值永不调换（docs/06 §2.3）。 */
const MACROS = [
  { color: C.peach, label: '蛋白' },
  { color: C.honey, label: '碳水' },
  { color: C.taro, label: '脂肪' },
];

const VARIANTS = [
  {
    slug: '02a-arc',
    name: 'A · 内弧加粗',
    tag: '在选中方案上的直接微调',
    note: '保持外环 + 内三弧结构，把内弧加粗到 82、断口拉到 32°，四段粗细接近、缺口更清楚，小尺寸下不至于糊成一圈。',
    glyph: (p) => {
      const segs = [
        [14, 106, C.peach],
        [134, 226, C.honey],
        [254, 346, C.taro],
      ];
      return `
    <path d="${arc(CX, CY, 296, 24, 336)}" fill="none" stroke="${p.body}" stroke-width="82" stroke-linecap="round"/>
    ${segs
      .map(
        ([a, b, col]) =>
          `<path d="${arc(CX, CY, 184, a, b)}" fill="none" stroke="${col}" stroke-width="82" stroke-linecap="round"/>`,
      )
      .join('\n    ')}`;
    },
  },
  {
    slug: '02b-dots',
    name: 'B · 环内三点',
    tag: '三宏量最简表达',
    note: '外环保留，三宏量缩成三颗圆点。圆点在小尺寸下比细弧更抗模糊，三色仍然一眼分得开；代价是丢了「构成比例」的含义。',
    glyph: (p) => {
      const R_DOT = 172;
      const dots = [90, 210, 330]
        .map((deg, i) => {
          const a = ((deg - 90) * Math.PI) / 180;
          const x = CX + R_DOT * Math.cos(a);
          const y = CY + R_DOT * Math.sin(a);
          return `<circle cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="68" fill="${MACROS[i].color}"/>`;
        })
        .join('\n    ');
      return `
    <path d="${arc(CX, CY, 296, 24, 336)}" fill="none" stroke="${p.body}" stroke-width="82" stroke-linecap="round"/>
    ${dots}`;
    },
  },
  {
    slug: '02c-invert',
    name: 'C · 内外互换',
    tag: '三色当主角，进度收进内圈',
    note: '把层级反过来：外环由三段彩色弧拼成（营养构成是主视觉），内圈留一条细的薄荷进度弧。三层粗细递减，比双层同粗更透气，小尺寸下三色占的面积也更大。',
    glyph: (p) => {
      const segs = [
        [16, 104, C.peach],
        [136, 224, C.honey],
        [256, 344, C.taro],
      ];
      return `
    ${segs
      .map(
        ([a, b, col]) =>
          `<path d="${arc(CX, CY, 296, a, b)}" fill="none" stroke="${col}" stroke-width="82" stroke-linecap="round"/>`,
      )
      .join('\n    ')}
    <path d="${arc(CX, CY, 178, 24, 336)}" fill="none" stroke="${p.body}" stroke-width="56" stroke-linecap="round"/>`;
    },
  },
  {
    slug: '02d-spark',
    name: 'D · 环内星芒',
    tag: '进度环 + AI',
    note: '环内换成一颗薄荷星芒，讲「AI 辅助」而不是三宏量——营养构成由环下 App 内承担，图标只需要被记住。星芒用反白，深浅底都成立。',
    glyph: (p) => `
    <path d="${arc(CX, CY, 296, 24, 336)}" fill="none" stroke="${p.body}" stroke-width="82" stroke-linecap="round"/>
    ${spark(CX, CY, 210, p.body, 0.15)}`,
  },
  {
    slug: '02e-segments',
    name: 'E · 单环四段',
    tag: '一个环讲两件事',
    note: '把内外两层压成一个环：长段薄荷=热量进度，三段彩色=三宏量，用平头对拼换成清晰的 22° 缝。四段同半径、粗细一致，比双层结构更干净、投影更小。',
    glyph: (p) => {
      const R = 292; // 加 round cap 后外缘 292+38=330，仍在 512-174=338 的安全边界内
      const W = 76;
      // 平头对拼：多段同半径拼环时圆头会把缝吃掉，这里只在视觉上留干净的直边缝。
      const runs = [
        [0, 30, null], // 顶部开口（与其它方案同轴）
        [30, 84, C.peach],
        [106, 160, C.honey],
        [182, 236, C.taro],
        [258, 360, p.body],
      ];
      return runs
        .filter(([, , col]) => col)
        .map(
          ([from, to, col]) =>
            `<path d="${arc(CX, CY, R, from, to)}" fill="none" stroke="${col}" stroke-width="${W}"/>`,
        )
        .join('\n    ');
    },
  },
  {
    slug: '02f-gauge',
    name: 'F · 游标轨道',
    tag: '细轨道 + 进度游标',
    note: '轨道细到不抢戏，进度由一颗游标圆点表示（缺口位置=已完成比例），内三弧回到主角。结构最轻，也最像仪表盘。',
    glyph: (p) => {
      const segs = [
        [14, 106, C.peach],
        [134, 226, C.honey],
        [254, 346, C.taro],
      ];
      // 缺口落在环内三弧的断口处（正上方），游标停在「已完成」的末端。
      const deg = 340;
      const a = ((deg - 90) * Math.PI) / 180;
      const hx = CX + 300 * Math.cos(a);
      const hy = CY + 300 * Math.sin(a);
      return `
    <path d="${arc(CX, CY, 300, 4, 336)}" fill="none" stroke="${p.cut}" stroke-width="26" stroke-linecap="round" opacity="0.7"/>
    <path d="${arc(CX, CY, 300, 0, deg)}" fill="none" stroke="${p.body}" stroke-width="26" stroke-linecap="round"/>
    <circle cx="${hx.toFixed(2)}" cy="${hy.toFixed(2)}" r="54" fill="${p.body}"/>
    ${segs
      .map(
        ([a2, b, col]) =>
          `<path d="${arc(CX, CY, 178, a2, b)}" fill="none" stroke="${col}" stroke-width="76" stroke-linecap="round"/>`,
      )
      .join('\n    ')}`;
    },
  },
];

for (const c of VARIANTS) {
  for (const v of ['icon', 'ios', 'mark']) {
    writeFileSync(join(SVG_DIR, `${c.slug}-${v}.svg`), renderSvg(c, v));
  }
}

// ── 对照页：把原方案 02 放在最前，便于直接比较 ──────────────────────────────
const baseline = {
  ...bySlug('02-ring'),
  name: '原方案 02',
  tag: '你当前选中的版本',
  note: '外环 82 粗、内三弧 68 粗、断口 28°。下面是五个衍生方向，骨架（薄荷环 / 营养三色 / 圆形 / 缺口朝上）都保持不变。',
};
const ALL = [baseline, ...VARIANTS];

const iconSvg = (c) => renderSvg(c, 'icon');
const markSvg = (c) => renderSvg(c, 'mark');

const cards = ALL.map(
  (c) => `
  <section class="row">
    <div class="hero"><div class="hero-icon">${iconSvg(c)}</div></div>
    <div class="body">
      <h2>${c.name}</h2>
      <div class="tag">${c.tag}</div>
      <div class="ladder">
        <div class="ladder-cell"><div class="s s128">${iconSvg(c)}</div><span>128</span></div>
        <div class="ladder-cell"><div class="s s64">${iconSvg(c)}</div><span>64</span></div>
        <div class="ladder-cell"><div class="s s48">${iconSvg(c)}</div><span>48</span></div>
        <div class="ladder-cell"><div class="s s32">${iconSvg(c)}</div><span>32</span></div>
        <div class="ladder-cell"><div class="s s24">${iconSvg(c)}</div><span>24</span></div>
        <div class="ladder-cell mark-cell"><div class="s s64 mark">${markSvg(c)}</div><span>mark</span></div>
      </div>
      <p class="note">${c.note}</p>
    </div>
  </section>`,
).join('\n');

writeFileSync(
  join(HERE, 'ring-variants.html'),
  `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>LocalFit AI · 能量环衍生方案</title>
<style>
  :root { --ink:#17251E; --ink2:#5A6B62; --ink3:#93A29A; --line:#E7ECE8; }
  * { box-sizing:border-box; }
  body { margin:0; padding:48px 56px 64px; background:#FAFBF9; color:var(--ink);
         font-family:"Segoe UI","Microsoft YaHei",system-ui,sans-serif; }
  h1 { font-size:30px; margin:0 0 6px; letter-spacing:-.4px; }
  .sub { color:var(--ink2); font-size:15px; }
  .row { display:grid; grid-template-columns:320px 1fr; gap:0 44px; align-items:center;
         padding:34px 0; border-top:1px solid var(--line); }
  .row:first-of-type { border-top:none; margin-top:22px; }
  .hero-icon { width:300px; }
  .hero-icon svg { width:100%; height:auto; border-radius:24%; box-shadow:0 10px 26px rgba(23,37,30,.13); }
  h2 { font-size:24px; margin:0 0 6px; letter-spacing:-.2px; }
  .tag { font-size:13px; color:#1FA377; margin-bottom:20px; }
  .ladder { display:flex; align-items:flex-end; gap:24px; }
  .ladder-cell { display:flex; flex-direction:column; align-items:center; gap:7px; }
  .ladder-cell span { font-size:11px; color:var(--ink3); }
  .s svg { display:block; border-radius:22%; }
  .s128 svg { width:128px; height:128px; box-shadow:0 5px 14px rgba(23,37,30,.10); }
  .s64 svg  { width:64px;  height:64px;  box-shadow:0 3px 9px rgba(23,37,30,.09); }
  .s48 svg  { width:48px;  height:48px;  box-shadow:0 2px 7px rgba(23,37,30,.08); }
  .s32 svg  { width:32px;  height:32px; }
  .s24 svg  { width:24px;  height:24px; }
  .mark-cell { padding-left:24px; border-left:1px solid var(--line); }
  .mark svg { background:#fff; border-radius:22%; box-shadow:inset 0 0 0 1px var(--line); }
  .note { margin:22px 0 0; font-size:14px; line-height:1.7; color:var(--ink2); max-width:900px; }
</style></head>
<body>
  <h1>能量环 · 衍生方案</h1>
  <div class="sub">骨架不变：薄荷环 · 营养三色 · 圆形构图 · 缺口开口朝上　｜　变的是「三宏量」的表达方式</div>
  ${cards}
</body></html>`,
);

console.log(`✓ ${VARIANTS.length * 3} 个 SVG + ring-variants.html 已写入 ${SVG_DIR}`);
