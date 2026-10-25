#!/usr/bin/env node
/**
 * 安全区校验：Android 自适应图标只保证中心 66%（1024 画布上的 174..850）可见，
 * 主体越界会被启动器遮罩裁掉。
 *
 * 做法：渲染透明底的 <slug>-mark.svg（与 icon 几何完全相同）到白底页面，
 * 安全区之外出现任何非白像素即判定越界。用 mark 而不是 icon，是为了绕开
 * 圆角方底四角透明、以及页面白底与渐变底色对不上的干扰。
 *
 * 运行：node design/logo/verify-safe-zone.mjs
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SVG_DIR = join(HERE, 'svg');
const TMP = join(HERE, '.render');
mkdirSync(TMP, { recursive: true });

const EDGE = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
].find(existsSync);
if (!EDGE) throw new Error('找不到 msedge.exe');

const SIZE = 1024;

const marks = readdirSync(SVG_DIR).filter((f) => f.endsWith('-mark.svg'));
const pngs = [];
for (const f of marks) {
  const out = join(TMP, f.replace(/\.svg$/, '.png'));
  execFileSync(
    EDGE,
    [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      `--window-size=${SIZE},${SIZE}`,
      `--screenshot=${out}`,
      `file:///${join(SVG_DIR, f).replace(/\\/g, '/')}`,
    ],
    { stdio: 'ignore' },
  );
  pngs.push([f, out]);
}

const script = `
import sys, json
from PIL import Image
SIZE=1024; MIN=174; MAX=850; TOL=8
out={}
for name,path in json.loads(sys.argv[1]):
    im=Image.open(path).convert('RGB')
    if im.size!=(SIZE,SIZE):
        out[name]={'error':'size %s'%(im.size,)}; continue
    px=im.load(); bad=0; worst=0; wxy=None
    for y in range(SIZE):
        for x in range(SIZE):
            if MIN<=x<MAX and MIN<=y<MAX: continue
            r,g,b=px[x,y]
            d=255-min(r,g,b)
            if d>TOL:
                bad+=1
                if d>worst: worst=d; wxy=(x,y)
    out[name]={'outside_px':bad,'max_ink':worst,'at':wxy}
print(json.dumps(out))
`;
const res = JSON.parse(
  execFileSync('C:/ProgramData/miniconda3/python.exe', ['-c', script, JSON.stringify(pngs)], {
    encoding: 'utf8',
  }),
);

let fail = 0;
for (const [name, r] of Object.entries(res)) {
  const label = name.replace(/-mark\.svg$/, '');
  if (r.error) {
    console.log(`✗ ${label}  ${r.error}`);
    fail++;
  } else if (r.outside_px > 0) {
    console.log(`✗ ${label}  越界 ${r.outside_px}px（最深 ${r.max_ink}，位置 ${r.at}）`);
    fail++;
  } else {
    console.log(`✓ ${label}  图形全在安全区内`);
  }
}
console.log(fail ? `\n${fail} 个方案越界，需要收紧几何` : '\n全部落在 174..850 安全区内');
process.exit(fail ? 1 : 0);
