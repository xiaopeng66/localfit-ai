/**
 * LocalFit AI logo 概念定义（方案 01–06）。
 *
 * glyph(p) 返回图形标记；p = { body, cut, uid }
 *   body   主形体色（icon/ios=白，mark=薄荷渐变）
 *   cut    挖空 / 反白描边色（icon/ios=薄荷渐变，mark=白）
 *   uid    变体唯一后缀，用于需要 id 的定义（渐变、clipPath）
 *
 * 本文件只放定义，不写文件；生成入口见 generate.mjs，能量环衍生方案见 ring-variants.mjs。
 */
import { C, arc } from './kit.mjs';

export const CONCEPTS = [
  {
    slug: '01-tray',
    name: '分格餐盘',
    tag: '校园食堂 × 营养三色',
    note: '食堂分格餐盘：左侧大格=主食（碳水蜜黄），右侧两格=蛋白珊瑚、脂肪雾紫，三格即营养素编码色。',
    glyph: (p) => `
    <rect x="200" y="200" width="624" height="624" rx="132" fill="${p.body}"/>
    <rect x="244" y="244" width="316" height="536" rx="86" fill="${C.honey}"/>
    <rect x="594" y="244" width="186" height="251" rx="70" fill="${C.peach}"/>
    <rect x="594" y="529" width="186" height="251" rx="70" fill="${C.taro}"/>`,
  },
  {
    slug: '02-ring',
    name: '能量环',
    tag: 'App 签名控件 × 三宏量',
    note: '把今日页签名件 CalorieRing 图形化：外环保留缺口=热量进度，内三弧=三宏量构成。',
    glyph: (p) => {
      const segs = [
        [14, 106, C.peach],
        [134, 226, C.honey],
        [254, 346, C.taro],
      ];
      return `
    <path d="${arc(512, 512, 296, 24, 336)}" fill="none" stroke="${p.body}" stroke-width="82" stroke-linecap="round"/>
    ${segs
      .map(
        ([a, b, col]) =>
          `<path d="${arc(512, 512, 180, a, b)}" fill="none" stroke="${col}" stroke-width="68" stroke-linecap="round"/>`,
      )
      .join('\n    ')}`;
    },
  },
  {
    slug: '03-dumbbell',
    name: '三色哑铃',
    tag: '饮食 × 训练双核',
    note: '哑铃=训练，杆身三段=蛋白/碳水/脂肪。一个形同时说清「练」与「吃」，小尺寸下轮廓最稳。',
    glyph: (p) => `
    <clipPath id="bar-${p.uid}"><rect x="344" y="456" width="336" height="112" rx="56"/></clipPath>
    <rect x="176" y="352" width="168" height="320" rx="68" fill="${p.body}"/>
    <rect x="680" y="352" width="168" height="320" rx="68" fill="${p.body}"/>
    <g clip-path="url(#bar-${p.uid})">
      <rect x="344" y="456" width="112" height="112" fill="${C.peach}"/>
      <rect x="456" y="456" width="112" height="112" fill="${C.honey}"/>
      <rect x="568" y="456" width="112" height="112" fill="${C.taro}"/>
    </g>`,
  },
  {
    slug: '04-shield',
    name: '本地盾叶',
    tag: '本地优先 × 数据不出设备',
    note: '盾=数据只留在本机（无账号/无云端），叶=饮食与健康。叶片 evenodd 挖空、整体倾斜 38°，底色透出。',
    glyph: (p) => `
    <path fill-rule="evenodd" fill="${p.body}" d="M512 212 L802 316 L802 512 C802 668 692 764 512 814 C332 764 222 668 222 512 L222 316 Z"/>
    <path fill="${p.cut}" transform="rotate(38 512 512)" d="M512 330 C648 386 676 538 512 694 C348 538 376 386 512 330 Z"/>`,
  },
  {
    slug: '05-pin',
    name: '窗口定位',
    tag: '下一餐去哪吃 × 决策确认',
    note: '定位钉=食堂/窗口位置，对勾=「已确认」这条产品铁律。对应今日页「下一餐去哪」决策卡。',
    glyph: (p) => `
    <path d="M282 404 A230 230 0 0 1 742 404 C742 590 650 720 512 850 C374 720 282 590 282 404 Z" fill="${p.body}"/>
    <path d="M426 404 L486 464 L604 346" fill="none" stroke="${p.cut}" stroke-width="64" stroke-linecap="round" stroke-linejoin="round"/>`,
  },
  {
    slug: '06-bowl-spark',
    name: 'AI 营养碗',
    tag: 'AI 辅助 × 结构化成餐',
    note: '碗=一餐（宽口平底的饭碗轮廓），四角星芒=AI 创作（但只产草案）。星芒从碗体反白，整体是「AI 装进一餐里」。',
    glyph: (p) => `
    <path fill="${p.body}" d="M236 356 C252 576 336 684 440 684 L584 684 C688 684 772 576 788 356 Z"/>
    <path fill="${p.cut}" d="M512 396 Q531 495 630 514 Q531 533 512 632 Q493 533 394 514 Q493 495 512 396 Z"/>`,
  },
];

export const bySlug = (slug) => CONCEPTS.find((c) => c.slug === slug);
