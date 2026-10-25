/**
 * LocalFit AI logo 公共件：品牌 token、几何工具、SVG 渲染。
 *
 * 配色取自 lib/app/design/app_colors.dart 与 docs/06 §2、docs/10 §2，
 * 两个生成器（generate.mjs / ring-variants.mjs）共用本文件，避免出现两份色值。
 */

export const SIZE = 1024;

// ── 品牌 token（app_colors.dart） ──────────────────────────────────────────
export const C = {
  mint200: '#C9EEDF',
  mint300: '#A5E2CB',
  mint400: '#63D2A8',
  mint500: '#2FBE8F',
  mint600: '#1FA377',
  mint700: '#17875F',
  mint100: '#E3F6EE',
  mint50: '#F0FBF7',
  peach: '#FF8A65',
  honey: '#FFC94D',
  taro: '#B39DDB',
  cream: '#FAFBF9',
  white: '#FFFFFF',
};

/** 自适应图标安全区（1024 画布上的 174..850）：主体越界会被启动器遮罩裁掉。 */
export const SAFE = { min: 174, max: 850 };

export const MINT = (uid) => `url(#mint-${uid})`;

/**
 * 135° 薄荷渐变；userSpaceOnUse 让「挖空」描边与底色严丝合缝。
 * id 带变体后缀：多个 SVG 内联进同一页时不会互相抢定义。
 */
export const defs = (uid) => `<defs>
    <linearGradient id="mint-${uid}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1024" y2="1024">
      <stop offset="0" stop-color="#3ECC9B"/>
      <stop offset="0.52" stop-color="${C.mint500}"/>
      <stop offset="1" stop-color="${C.mint700}"/>
    </linearGradient>
  </defs>`;

export const bg = (uid, rx) =>
  `<rect width="${SIZE}" height="${SIZE}" rx="${rx}" fill="${MINT(uid)}"/>`;

// ── 几何工具 ───────────────────────────────────────────────────────────────
/** 极坐标：角度从 12 点方向顺时针计。 */
export function polar(cx, cy, r, deg) {
  const rad = ((deg - 90) * Math.PI) / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

/** 圆弧路径（round cap 会向两端各延伸 stroke/2，调用方自行留缝）。 */
export function arc(cx, cy, r, from, to) {
  const [x1, y1] = polar(cx, cy, r, from);
  const [x2, y2] = polar(cx, cy, r, to);
  const large = Math.abs(to - from) > 180 ? 1 : 0;
  const sweep = to > from ? 1 : 0;
  return `M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 ${large} ${sweep} ${x2.toFixed(2)} ${y2.toFixed(2)}`;
}

/**
 * 平头圆弧 + 两端圆点 = 「圆头圆弧」的替代画法。
 * 用于多段同半径拼环：相邻段用平头对拼边界干净，只有整条环的首尾才需要圆头。
 */
export function roundedArc(cx, cy, r, from, to, stroke, width) {
  const head = polar(cx, cy, r, from);
  const tail = polar(cx, cy, r, to);
  const dot = (pt) =>
    `<circle cx="${pt[0].toFixed(2)}" cy="${pt[1].toFixed(2)}" r="${width / 2}" fill="${stroke}"/>`;
  return `
    <path d="${arc(cx, cy, r, from, to)}" fill="none" stroke="${stroke}" stroke-width="${width}"/>
    ${dot(head)}
    ${dot(tail)}`;
}

/** 四角星芒（凹边），半对角线 r，中心 (cx, cy)。 */
export function spark(cx, cy, r, fill, ratio = 0.14) {
  const k = r * ratio;
  return `<path fill="${fill}" d="M${cx} ${cy - r} Q${cx + k} ${cy - k} ${cx + r} ${cy} Q${cx + k} ${cy + k} ${cx} ${cy + r} Q${cx - k} ${cy + k} ${cx - r} ${cy} Q${cx - k} ${cy - k} ${cx} ${cy - r} Z"/>`;
}

// ── 渲染 ───────────────────────────────────────────────────────────────────
/**
 * variant:
 *   icon  圆角方底（Android 启动图标 / 商店 512）
 *   ios   满幅直角方底（iOS 自行套圆角遮罩，必须不带圆角、不留透明边）
 *   mark  透明底、薄荷渐变主体（App 内标题 / 浅底场景）
 */
export function renderSvg(concept, variant) {
  const uid = `${concept.slug}-${variant}`;
  const solid = variant !== 'mark';
  const p = solid
    ? { body: C.white, cut: MINT(uid), uid }
    : { body: MINT(uid), cut: C.white, uid };
  const body = concept.glyph(p).trimEnd();
  const head = variant === 'ios' ? bg(uid, 0) : variant === 'icon' ? bg(uid, 232) : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">
  ${defs(uid)}
  ${head}
  <g>
    ${body}
  </g>
</svg>
`;
}
