#!/usr/bin/env node
/**
 * LocalFit AI · 把定稿 logo 落到 App 打包资源。
 *
 * 输入（finalize.mjs 生成）：
 *   svg/k8-final-icon.svg        圆角方底  → Android legacy ic_launcher.png
 *   svg/k8-final-foreground.svg  透明前景  → Android 自适应 ic_launcher_foreground.png
 *   svg/k8-final-ios.svg         满幅直角  → iOS AppIcon.appiconset 全套
 *
 * 同时写入：
 *   android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml   （API 26+ 自适应图标）
 *   android/app/src/main/res/values/colors.xml                    （自适应背景色 #0F1412）
 *
 * 渲染：Edge 无头截图出 2048px 母版（2x），PIL Lanczos 缩到各档；
 *       iOS 全套转 RGB 去掉 alpha 通道（App Store 要求图标不带 alpha）。
 *
 * 运行：node design/logo/apply-icons.mjs
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const PROJECT = join(HERE, '..', '..');
const SVG_DIR = join(HERE, 'svg');
const RES = join(PROJECT, 'android', 'app', 'src', 'main', 'res');
const APPICON = join(PROJECT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset');
const MASTER_DIR = join(HERE, '.masters');
mkdirSync(MASTER_DIR, { recursive: true });

const EDGE = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
].find(existsSync);
if (!EDGE) throw new Error('找不到 msedge.exe');
const PY = 'C:/ProgramData/miniconda3/python.exe';

const MASTERS = [
  ['icon', 'k8-final-icon.svg'],
  ['ios', 'k8-final-ios.svg'],
  ['fg', 'k8-final-foreground.svg'],
];

// 1) 2x 母版（透明背景，图标自身的圆角/满幅由 SVG 决定）
for (const [name, svg] of MASTERS) {
  const out = join(MASTER_DIR, `${name}-2048.png`);
  execFileSync(
    EDGE,
    [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--default-background-color=00000000',
      '--force-device-scale-factor=2',
      '--window-size=1024,1024',
      `--screenshot=${out}`,
      `file:///${join(SVG_DIR, svg).replace(/\\/g, '/')}`,
    ],
    { stdio: 'ignore' },
  );
}

// 2) 缩放并写入各平台
const script = `
import sys, json, os
from PIL import Image
from xml.etree import ElementTree

masters, res, appicon = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3]
img = {k: Image.open(v).convert('RGBA') for k, v in masters.items()}
assert all(im.size == (2048, 2048) for im in img.values()), {k: im.size for k, im in img.items()}

def write(path, im, flatten=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)
    if flatten:
        rgb = Image.new('RGB', im.size, (255, 255, 255))
        rgb.paste(im, mask=im.split()[3])
        rgb.save(path)

report = {'android': [], 'ios': []}

# Android legacy：圆角方底图标
for dpi, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    p = os.path.join(res, f'mipmap-{dpi}', 'ic_launcher.png')
    write(p, img['icon'].resize((px, px), Image.LANCZOS))
    report['android'].append(f'{p} {px}')

# Android 自适应前景（108dp：mdpi 108 → xxxhdpi 432）
for dpi, px in [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)]:
    p = os.path.join(res, f'mipmap-{dpi}', 'ic_launcher_foreground.png')
    write(p, img['fg'].resize((px, px), Image.LANCZOS))
    report['android'].append(f'{p} {px}')

# iOS：按 Contents.json 的文件名推尺寸，RGB 去 alpha
import json as _json
tree = _json.load(open(os.path.join(appicon, 'Contents.json'), encoding='utf-8'))
for e in tree['images']:
    name = e.get('filename'); size = e.get('size'); scale = e.get('scale')
    base = float(size.split('x')[0])
    px = round(base * float(scale.rstrip('x')))
    p = os.path.join(appicon, name)
    write(p, img['ios'].resize((px, px), Image.LANCZOS), flatten=True)
    report['ios'].append(f'{name} {px}')

print(json.dumps(report))
`;
const report = JSON.parse(
  execFileSync(PY, ['-c', script, JSON.stringify(Object.fromEntries(MASTERS.map(([n]) => [n, join(MASTER_DIR, `${n}-2048.png`)]))), RES, APPICON], {
    encoding: 'utf8',
  }),
);

// 3) 自适应图标声明 + 背景色
const anydpi = join(RES, 'mipmap-anydpi-v26');
mkdirSync(anydpi, { recursive: true });
writeFileSync(
  join(anydpi, 'ic_launcher.xml'),
  `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
`,
);
const valuesDir = join(RES, 'values');
mkdirSync(valuesDir, { recursive: true });
const colorsPath = join(valuesDir, 'colors.xml');
const colors = existsSync(colorsPath) ? readFileSync(colorsPath, 'utf8') : null;
if (!colors || !colors.includes('ic_launcher_background')) {
  if (colors) throw new Error('values/colors.xml 已存在但缺少 ic_launcher_background，请手工合并');
  writeFileSync(
    colorsPath,
    `<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0F1412</color>
</resources>
`,
  );
}

console.log(`✓ Android ${report.android.length} 个 + iOS ${report.ios.length} 个图标已写入`);
for (const line of [...report.android, ...report.ios]) console.log('  ' + line.replace(PROJECT + '\\', ''));
