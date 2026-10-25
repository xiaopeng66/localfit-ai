# LocalFit AI · Logo 方案

6 个 logo 概念，全部由 `generate.mjs` 从几何定义生成，配色与形状取自 App 现有设计规范。

## 先看什么

| 文件 | 内容 |
|---|---|
| [`preview.png`](preview.png) | 总览：6 个方案 + 128/64/48/32/24px 尺寸阶梯 + mark 变体 |
| [`detail.png`](detail.png) | 细节：每个方案 340px 主图 + mark 在浅底/深底 + iOS 直角变体 |
| [`svg/`](svg/) | 18 个 SVG（每方案 3 个变体），可直接用于打包 |

## 6 个方案

| # | 名称 | 表达什么 | 为什么适合 LocalFit AI |
|---|---|---|---|
| 01 | **分格餐盘** | 食堂餐盘三格 = 营养三色 | 校园食堂是产品核心场景，三格直接复用蛋白/碳水/脂肪的编码色，把「吃什么、吃多少」画成一个形 |
| 02 | **能量环** | App 签名控件 CalorieRing | 今日页最大胆的一处就是环形数字；外环留缺口=进度，内三弧=三宏量构成，与 App 内视觉完全同源 |
| 03 | **三色哑铃** | 哑铃=训练，杆身三段=三宏量 | 一个形同时说清「练」与「吃」，是六个里小尺寸轮廓最稳的 |
| 04 | **本地盾叶** | 盾=数据不出设备，叶=健康 | 直击「无账号、无云端、数据留在本机」这条最硬的差异化；叶片挖空，深浅底都能用 |
| 05 | **窗口定位** | 定位钉=食堂窗口，对勾=已确认 | 对应今日页「下一餐去哪吃」决策卡；对勾同时呼应「可确认才可写入」这条产品铁律 |
| 06 | **AI 营养碗** | 碗=一餐，星芒=AI 创作 | 唯一把 AI 放进主形的方案；星芒从碗体反白，表达「AI 只产草案、装在一餐里」 |

### 我的推荐

- **首选 01 分格餐盘**：最贴产品定位（校园就餐），色彩直接就是营养三色，一眼能看出「饮食 + 营养管理」，且 24px 下三格仍然分得开。
- **次选 02 能量环**：如果更想强调「数据追踪」而非「校园食堂」，它和 App 内视觉的同源度最高。
- **04 本地盾叶** 适合作为品牌辅助图形——它讲的隐私故事没有别的方案在讲，可以在「我的 → 数据与隐私」页复用。

## 每个方案的三个变体

| 后缀 | 用途 | 说明 |
|---|---|---|
| `-icon.svg` | Android 启动图标 / 商店 512 | 1024×1024，圆角 232 方底，薄荷渐变 |
| `-ios.svg` | iOS AppIcon | 满幅直角方底（iOS 自行套圆角遮罩，不能自带圆角或透明边） |
| `-mark.svg` | App 内标题 / 浅底场景 | 透明底、薄荷渐变主体，无背景 |

主体全部落在 Android 自适应图标安全区（1024 画布上的 174..850）内，已由 `verify-safe-zone.mjs` 逐像素验证。

## 选定 02 能量环之后的衍生方案

在保持骨架不变（薄荷环 · 营养三色 · 圆形构图 · 缺口开口朝上）的前提下，对「三宏量」的表达做了 6 个变体，
见 [`ring-variants.png`](ring-variants.png)（原方案放在最前作对照），SVG 在 [`svg/`](svg/) 下，slug 以 `02` 开头。

| # | 名称 | 变化 | 取舍 |
|---|---|---|---|
| A | `02a-arc` 内弧加粗 | 内弧 68→82、断口 28°→32° | 最接近你选的原案，只是更耐小尺寸 |
| B | `02b-dots` 环内三点 | 内三弧 → 三颗圆点 | 24px 下最抗模糊；丢了「构成比例」的含义 |
| C | `02c-invert` 内外互换 | 三色放到外环当主角，内圈留细薄荷进度弧 | 三色面积最大、最有食欲感；层级与原案相反 |
| D | `02d-spark` 环内星芒 | 内三弧 → 一颗反白星芒 | 唯一讲「AI」的变体，最简洁耐看；不讲营养构成 |
| E | `02e-segments` 单环四段 | 内外两层压成一个环，长段薄荷 + 三段彩色 | 结构最干净、层次最少；平头对拼，缝比其它方案硬 |
| F | `02f-gauge` 游标轨道 | 外环改细轨道 + 游标圆点表进度 | 最轻、最像仪表盘；小尺寸下轨道偏细 |

**推荐**：想在原案上稳妥升级选 **A**；想要最强识别度选 **D**（星芒 + 环，24px 下依然成立）；想要三色更饱满、更有食欲感选 **C**。

衍生方案同样全部通过安全区校验。改动某个变体只需编辑 `ring-variants.mjs` 里对应的 `glyph()`。

## 发散探索（10 个方向互不相同的方案）

不锁骨架的一轮发散：色彩（暗底霓虹 / 彩虹渐变 / 粉彩 / 深绿徽章）、线条（细线 / 点阵 / 平涂 / 线稿）、
构图（环 / 盘 / 盾 / 碗筷 / 字标 / 脉搏）各不相同。见 [`explorations-a.png`](explorations-a.png) /
[`explorations-b.png`](explorations-b.png)，SVG 在 [`svg/`](svg/) 下，slug 以 `d` 开头。

这一轮**只出了 icon 变体**——底色本身就是方案的一部分，选定方向后再补 mark / ios 两件套。

| # | 名称 | 一句话 |
|---|---|---|
| d1 | `d1-dark-neon` 深色霓虹 | 近黑底 + 发光薄荷细环，训练页深色沉浸搬到图标上 |
| d2 | `d2-minimal-line` 极简单线 | 奶油底一根细线 + 圆心，全组最克制 |
| d3 | `d3-stitch` 缝线点阵 | 白色圆点串成的环 + 三颗宏量色珠，最俏皮 |
| d4 | `d4-iris` 彩虹光圈 | 闭合粗环沿圆周做薄荷→珊瑚→蜜黄→雾紫→海盐渐变，无缺口 |
| d5 | `d5-wedges` 扇形餐盘 | 圆盘切三块平涂扇形，全组唯一没有线条的 |
| d6 | `d6-emblem` 深绿盾徽 | 深绿底 + 白描边盾 + 浅薄荷叶，讲「数据留在本机」 |
| d7 | `d7-lineart` 线稿碗筷 | 单色线勾碗和筷子，唯一具象画食物的 |
| d8 | `d8-pulse` 脉搏环 | 环在正上方破开接心电 spike，薄荷环 + 珊瑚脉搏 |
| d9 | `d9-monogram` LF 字标 | LocalFit 的 L/F 圆头粗笔画，唯一带字母的 |
| d10 | `d10-candy` 粉彩软糖 | 三段 300 档粉彩弧 + 白色高光，饱和度最低 |

注意：d1（暗底）与 d6（深绿）走的是「深色沉浸」路线，和当前「薄荷奶油」的浅色 UI 是两套气质；
如果选它们，App 内可能需要一组配套的深色品牌物料。d4 的海盐蓝、d10 的粉彩档位都仍取自 `app_colors.dart` 的色板。

## 脉搏环细化（发散方案 d8 的 6 个变体）

用户在发散轮里看中 d8 脉搏环后做的细化，见 [`pulse-variants.png`](pulse-variants.png)，SVG 在 [`svg/`](svg/) 下，slug 以 `p` 开头。
骨架不变（环在正上方破开接一段脉搏线），变的是**波形画法**与**色彩**：

| # | 名称 | 波形 | 色彩 | 一句话 |
|---|---|---|---|---|
| P1 | `p1-pulse-refined` 精修单峰 | 尖峰收窄抬高、回落压深 | 薄荷环 + 珊瑚脉搏 | d8 的直接比例修正，「跳一下」最强 |
| P2 | `p2-ecg` 真实心电 | P 波 + QRS 波群 | 同上 | 懂的人一眼认出心电；小尺寸细节会并在一起 |
| P3 | `p3-mono` 一笔单色 | 单峰 | 全部墨绿（mint700），奶油底 | 环与脉搏同色合并成一条线，最安静 |
| P4 | `p4-dark` 深色霓虹 | 单峰 | 暗底 + 双色外晕 | 对比最强，走深色沉浸方向 |
| P5 | `p5-soft` 柔化波峰 | 三次曲线收口、无尖角 | 薄荷环 + 珊瑚脉搏 | 「脉搏」变「呼吸」，与 App 圆角语言最贴 |
| P6 | `p6-ink` 墨绿纸面 | 单峰 | 墨绿黑环 + 珊瑚脉搏，奶油底 | 纸面印刷感，最不像健康类 App 的惯用配色 |

与能量环那轮不同，这一组只出 icon 变体（同发散轮逻辑），几何上已人工核对主体都在
自适应图标安全区内（环外缘 302、峰顶含描边最低 178，均在 174..850 之内）。

**推荐**：P1 是「d8 但更精神」的稳妥版；想保留心电语义选 P2；想要最耐看、最贴 App 圆角语言选 P5；
想要品牌感最独特选 P4（需接受暗底方向）。

## 深色霓虹线条优化（细化方案 P4 的 5 个变体）

用户选定 P4 深色霓虹后专攻线条画法的一轮，见 [`neon-refine.png`](neon-refine.png)，SVG 在 [`svg/`](svg/) 下，slug 以 `n` 开头。
骨架不变（近黑底 · 薄荷环正上方破开接珊瑚色脉搏 · 整体发光），变的是**描边本身**：

| # | 名称 | 线条处理 | 一句话 |
|---|---|---|---|
| N1 | `n1-core` 管芯发光 | 四层描边：大晕(26 高斯)→紧晕(7 高斯)→亮芯→白热管芯 | 真·霓虹灯管的标准画法，质感的天花板 |
| N2 | `n2-contrast` 细环重脉 | 环 26 细线、脉搏 58 加粗 | 心跳是画面里最大声的东西，层次靠线宽对比 |
| N3 | `n3-hollow` 空心管 | 底色挖掉管芯只留 12px 管壁，脉搏与环之间留 12px 气口 | 像「硬件」，全组最独特 |
| N4 | `n4-gradient` 渐变光管 | 脉搏沿行程蜜黄→珊瑚→深珊瑚渐变 | 多一层暖意，画出「能量消耗」的方向感 |
| N5 | `n5-soft` 柔波霓虹 | 柔化曲线波形（P5 的波形）+ 霓虹分层 | 无尖角的「冷静霓虹」，与 N1 的锐利正好两端 |

实现细节：每个方案把内容裁进圆角方（clipPath），发光分层用两层高斯滤镜（26/7）+ 亮芯 + 白热管芯；
N3 的挖芯用底色描边沿同一路径覆盖实现，气口 12px 是环端圆头（半径 23）与脉搏圆头之间能留出的最小清晰缝。

**推荐**：N1 是「霓虹质感」的标准答案；想要独特性选 N3（空心管）；想要波形更柔和耐看选 N5。

## 空心管管径细化（线条方案 N3 的 5 个变体）

用户选定 N3 空心管后专攻管子物理量的一轮，见 [`hollow-refine.png`](hollow-refine.png)，SVG 在 [`svg/`](svg/) 下，slug 以 `h` 开头。
骨架不变，变量四个：**管径**（外径）· **管壁**（挖芯后剩下的壁厚）· **气口**（脉搏与环两端的间距）· **管端切口**（圆头/平头）：

| # | 名称 | 管径 | 管壁 | 气口 | 一句话 |
|---|---|---|---|---|---|
| — | `n3-hollow`（对照） | 46 | 12 | 12 | 你选中的版本 |
| H1 | `h1-slim` 细管大缝 | 34 | 7 | 20 | 整体最轻最透气；24px 下管壁不足 1px |
| H2 | `h2-chunky` 粗管紧缝 | 60 | 17 | 8 | 实体感最强，24px 下依然粗壮清晰——最耐小尺寸 |
| H3 | `h3-thinwall` 薄壁宽缝 | 46 | 7 | 24 | 外径保持饱满只掏薄管壁，像 LED 灯带 |
| H4 | `h4-flatcut` 平头切口 | 46 | 12 | 12 | 圆头改平头，管端是开口的圆环截面，工业感最重 |
| H5 | `h5-innerlight` 管内微光 | 46 | 12 | 12 | 挖芯换成掺 16% 薄荷的 #19342a，管内像有未熄灭的气体 |

H5 的掺色比例经过像素采样校准：10%（#152821）与底色的绿通道差仅 8/255，实测几乎不可感；
16%（#19342a）实测管内 (25,52,42) vs 管外 (16,22,20)，可感知但仍克制。

**推荐**：要小尺寸下的存在感选 **H2**（粗管）；要轻盈精致选 **H3**；要材质细节选 **H5**——它和对照版远看几乎一样，区别只在管内那一圈微光。

## 空心管材质打磨（H2 的 6+1 个变体）

管径/壁/气口锁定 H2（60/17/8）之后的一轮材质打磨，见 [`tube-polish.png`](tube-polish.png)，SVG 在 [`svg/`](svg/) 下，slug 以 `k` 开头。
思路：真霓虹灯的照片之所以可信，是因为有**环境辉光**（照亮墙）、**玻璃高光**（受光面）、**光衰减**（亮度沿管衰减）、
**管内残光**（气体未全灭）、**电极**（两端接头）——每轮加一层，最后一个全叠加：

| # | 名称 | 加了什么 | 一句话 |
|---|---|---|---|
| — | `h2-chunky`（对照） | — | 平涂管色 + 纯底挖芯 |
| K1 | `k1-ambient` 环境辉光 | 环半径处 13% 薄荷洗光 + 四角暗角 | 管子一根线没动，空间感立刻出来 |
| K2 | `k2-specular` 玻璃高光 | 管壁外侧白 specular：环左上一长条 + 尖峰一小段 | 从「平涂圆环」变成「有受光面的管子」 |
| K3 | `k3-falloff` 光衰减 | 管色沿受光面渐变（左上亮档 → 右下深档），脉搏同理 | 动的是「色」不是「形」，光有了方向 |
| K4 | `k4-residual` 管内残光 | 挖芯掺色：环管 #19342a、脉搏管 #35271f（各掺 16% 管色） | 粗管孔宽 26，残光比细管明显得多 |
| K5 | `k5-electrode` 电极节点 | 脉搏两端白热电极（带紧晕） | 回答「脉搏为什么悬浮」——那是两根管子的接头 |
| K6 | `k6-full` 全部叠加 | 以上全部 | **定稿候选** |
| K7 | `k7-alive` 会呼吸 | K6 + SMIL 心跳动画（1.6s 轻-重-歇，电极同步闪） | 彩蛋：启动图标用不了动画，启动页/官网/关于页可以 |

实现：内容裁进圆角方；发光分两层高斯（soft σ26 / tight σ7）；H5 的掺色比例经像素采样校准
（10% 不可感 → 16% 实测管内 (25,52,42) vs 管外 (16,22,20)）。K7 用 SMIL，浏览器打开或内嵌 HTML 才会动。

**推荐 K6** 作为最终方向：单独看 K1–K5 每层都偏微妙，叠起来才是「实拍霓虹灯」的完成度。

## 定稿：K8（K7 − 环境辉光）· 三件套已产出

最终选定 **K7 去掉环境辉光和暗角**（纯黑底 + 光衰减 + 管内残光 + 玻璃高光 + 电极 + 心跳动画）。
预览见 [`finalize.png`](finalize.png) / [`finalize.html`](finalize.html)，由 [`finalize.mjs`](finalize.mjs) 生成：

| 文件 | 用途 | 说明 |
|---|---|---|
| [`svg/k8-final-icon.svg`](svg/k8-final-icon.svg) | Android 启动图标 / 商店 512 | 圆角方底 1024，**带 SMIL 心跳动画**（浏览器打开可见） |
| [`svg/k8-final-ios.svg`](svg/k8-final-ios.svg) | iOS AppIcon | 满幅直角方底，静态（取动画第 0 帧） |
| [`svg/k8-final-mark.svg`](svg/k8-final-mark.svg) | App 内标题 | 透明底、**mask 真镂空**（管内随背景走）、无发光层；渐变从 NEON 直压深档保证浅底对比度；电极用深珊瑚 |

浅底注意：mark 上的白色 specular 和白热电极在浅色场景不可见，已分别省略/改深珊瑚；
深色场景（启动页、关于页暗色卡）直接用 icon 版。K7 的动画同样只在浏览器/内嵌 HTML 生效，
Flutter 侧要用这条动线需转 Lottie 或自绘。

## 已落到 App 打包资源（apply-icons.mjs）

`apply-icons.mjs` 把定稿栅格化并写入打包资源（2026-09-19 执行，`flutter build apk --debug` 通过，31.4s）：

| 平台 | 写入 | 来源 |
|---|---|---|
| Android legacy | `mipmap-{mdpi…xxxhdpi}/ic_launcher.png`（48–192） | k8-final-icon.svg |
| Android 自适应 | `mipmap-anydpi-v26/ic_launcher.xml` + `mipmap-*/ic_launcher_foreground.png`（108–432）+ `values/colors.xml`（背景 `#0F1412`） | k8-final-foreground.svg（前景整体缩到 93%，脉冲尖峰恰好收进 108dp 画布 66% 安全区圆） |
| iOS | `AppIcon.appiconset/` 全套 19 个 PNG（20–1024，按 Contents.json 推尺寸） | k8-final-ios.svg，已转 RGB 去 alpha（App Store 要求） |

- 母版用 Edge 无头截图出 2048px（2x），PIL Lanczos 缩档，小尺寸质量有保证。
- 替换前的默认 Flutter 图标备份在 [`backup-default-icons/`](backup-default-icons/)。
- `k8-final-icon.svg` 的心跳动画是 SMIL，启动图标取的是第 0 帧（静态）；App 内要用动线需转 Lottie 或自绘。
- 重新生成全部图标资源：`node design/logo/finalize.mjs && node design/logo/apply-icons.mjs`。

## 体积优化版 APK

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --obfuscate --split-debug-info=build/symbols/arm64
```

产物 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`（2026-09-19 实测 **31.5MB**，全 ABI 的 release 包是 75M）：

- `--target-platform android-arm64` 只管 Dart 侧（libflutter/libapp）；**插件的原生库（sqlcipher、dartjni）由 Gradle 打包**，
  必须配合 `--split-per-abi` 才会过滤——只有前者时包里会混进 x86_64/armeabi-v7a 的 sqlcipher（实测 40.6M 的教训）。
- `--obfuscate` 剥掉 Dart 符号名（libapp.so 无膨胀），崩溃符号表在 `build/symbols/arm64`，符号化崩溃日志时要用。
- 仅含 arm64-v8a：适用于全部近十年的真机；x86_64 模拟器和 32 位老设备装不了。
- 签名沿用 debug key（`android/app/build.gradle.kts` 的 release 块），可直接安装；上架商店需换成正式签名。
- 已验证：包内仅 arm64 一组 .so、10 个图标 PNG（R8 改名为 res/*.png）、`resources.arsc` 含自适应图标引用、
  目录只随包 core-000 分片（5.8M 压缩，其余按需分发）。

## 色彩

全部取自 `lib/app/design/app_colors.dart`，没有新增颜色：

| 用途 | 值 |
|---|---|
| 品牌主色 mint500 | `#2FBE8F` |
| 渐变起点 / 终点 | `#3ECC9B` → `#2FBE8F` → `#17875F`（135°） |
| 蛋白 peach | `#FF8A65` |
| 碳水 honey | `#FFC94D` |
| 脂肪 taro | `#B39DDB` |

营养素三色的语义**不可调换**——`docs/21` §2.1 把 `--lf-protein` / `--lf-carbs` / `--lf-fat` 各自绑定到固定色值（珊瑚 / 蜜黄 / 雾紫），§2.8 的迁移口径表逐条锁住这三个值：颜色在这里编码信息，不是装饰。

## 重新生成

```bash
node design/logo/generate.mjs          # 生成方案 01–06（18 个 SVG）+ preview.html
node design/logo/ring-variants.mjs     # 生成能量环 6 个衍生方案（18 个 SVG）+ ring-variants.html
node design/logo/explorations.mjs      # 生成 10 个发散探索方案（10 个 icon SVG）+ 3 个预览页
node design/logo/pulse-variants.mjs    # 生成脉搏环 6 个细化方案（6 个 icon SVG）+ pulse-variants.html
node design/logo/neon-refine.mjs       # 生成深色霓虹 5 个线条方案（5 个 icon SVG）+ neon-refine.html
node design/logo/hollow-refine.mjs     # 生成空心管 5 个管径方案（5 个 icon SVG）+ hollow-refine.html
node design/logo/tube-polish.mjs       # 生成空心管材质打磨 7 个方案（含 1 个动画版）+ tube-polish.html
node design/logo/finalize.mjs          # 定稿 K8 的 ios / mark 两件套 + finalize.html
node design/logo/detail.mjs            # 生成 detail.html
node design/logo/verify-safe-zone.mjs  # 校验主体是否越出自适应图标安全区（覆盖 svg/ 下全部 mark）
```

探索方案的几何在 `explorations.mjs`，每个方案一个 `glyph(uid)`，底色/滤镜各自定义；
因为只出 icon、且各自带私有底色，`verify-safe-zone.mjs` 不覆盖这一组，选定后补 mark 时会一并校验。

渲染预览页（需要 Edge；`--force-device-scale-factor=2` 出 2 倍图）：

```bash
"/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1440,2400 \
  --screenshot="design/logo/preview.png" \
  "file:///E:/AI/Zcode/localfit-ai/design/logo/preview.html"
```

改动几何只需要编辑 `generate.mjs` 里对应概念的 `glyph()`，三个变体会一起更新。

## 选定之后

替换 `android/app/src/main/res/mipmap-*/ic_launcher.png` 与 iOS `AppIcon.appiconset`，需要把 SVG 栅格化成各档 PNG（Flutter 侧可用 `flutter_launcher_icons` 配 `-icon.svg`，或手工导出）。这一步尚未执行——当前只交付设计稿，未改动任何打包资源。
