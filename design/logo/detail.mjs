#!/usr/bin/env node
/** 放大细节校对页：每个概念 icon 340px + mark 120px（白底/深底各一）。 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(HERE, 'svg', f), 'utf8');

const items = [
  ['01-tray', '分格餐盘'],
  ['02-ring', '能量环'],
  ['03-dumbbell', '三色哑铃'],
  ['04-shield', '本地盾叶'],
  ['05-pin', '窗口定位'],
  ['06-bowl-spark', 'AI 营养碗'],
];

const cells = items
  .map(
    ([slug, name]) => `
  <div class="cell">
    <div class="big">${read(`${slug}-icon.svg`)}</div>
    <div class="small">
      <div class="pad light">${read(`${slug}-mark.svg`)}</div>
      <div class="pad dark">${read(`${slug}-mark.svg`)}</div>
      <div class="pad ios">${read(`${slug}-ios.svg`)}</div>
    </div>
    <div class="cap">${name}</div>
  </div>`,
  )
  .join('\n');

writeFileSync(
  join(HERE, 'detail.html'),
  `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>detail</title><style>
  body{margin:0;padding:40px;background:#FAFBF9;font-family:"Segoe UI","Microsoft YaHei",sans-serif;color:#17251E}
  .grid{display:grid;grid-template-columns:repeat(3,1fr);gap:34px 40px}
  .cell{display:flex;flex-direction:column;align-items:center;gap:14px}
  .big svg{width:340px;height:340px;border-radius:24%;box-shadow:0 10px 26px rgba(23,37,30,.13)}
  .small{display:flex;gap:14px;align-items:center}
  .pad{width:110px;height:110px;display:flex;align-items:center;justify-content:center}
  .pad svg{width:96px;height:96px}
  .light{background:#fff;border-radius:22px;box-shadow:inset 0 0 0 1px #E7ECE8}
  .dark{background:#17251E;border-radius:22px}
  .ios svg{border-radius:24%;box-shadow:0 6px 16px rgba(23,37,30,.14)}
  .cap{font-size:15px;color:#5A6B62}
  </style></head><body><div class="grid">${cells}</div></body></html>`,
);
console.log('✓ detail.html');
