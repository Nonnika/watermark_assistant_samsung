# Watermark Assistant · Design System & UI/UX Specifications

> **版本**：1.0.0  
> **设计语言**：Samsung One UI (One UI 6.x / One UI 7.x 现代旗舰视觉规范)  
> **核心受众**：摄影爱好者、摄影师、Galaxy 旗舰及 Android 创作者  
> **核心体验**：纯粹克制、单手从容、指尖触感、非凡画质

---

## 目录

1. [设计哲学与核心理念 (Design Philosophy)](#1-设计哲学与核心理念-design-philosophy)
2. [视觉规范与设计系统 (Visual System & Tokens)](#2-视觉规范与设计系统-visual-system--tokens)
   - [色彩体系 (Color Palette)](#色彩体系-color-palette)
   - [超椭圆鹅卵石几何 (Pebble Squircle Geometry)](#超椭圆鹅卵石几何-pebble-squircle-geometry)
   - [字阶与排版体系 (Typography)](#字阶与排版体系-typography)
   - [高斯模糊与多层材质 (Materials & Blur)](#高斯模糊与多层材质-materials--blur)
   - [空间布局与阴影阶梯 (Spacing & Elevation)](#空间布局与阴影阶梯-spacing--elevation)
3. [UI 架构与页面交互流程 (UI & Interaction Flow)](#3-ui-架构与页面交互流程-ui--interaction-flow)
   - [闪屏与品牌心智 (Splash Screen)](#闪屏与品牌心智-splash-screen)
   - [首页探索与英雄海报 (Hero Poster Banner)](#首页探索与英雄海报-hero-poster-banner)
   - [全功能相册选择器 (Photo Selector & Album Grid)](#全功能相册选择器-photo-selector--album-grid)
   - [核心工作台：扑克牌堆叠与双模式画布 (Card Stack Workspace)](#核心工作台扑克牌堆叠与双模式画布-card-stack-workspace)
4. [核心交互引擎：Snapseed 极简盲操系统 (Snapseed Gesture Engine)](#4-核心交互引擎snapseed-极简盲操系统-snapseed-gesture-engine)
   - [手势分流与阻尼映射](#手势分流与阻尼映射)
   - [中央固定焦点 HUD 滚轮 (Center-Fixed Wheel HUD)](#中央固定焦点-hud-滚轮-center-fixed-wheel-hud)
   - [十点磁吸九宫格 (Ten-Point Smart Snapping)](#十点磁吸九宫格-ten-point-smart-snapping)
   - [物理触觉反馈矩阵 (Haptic Feedback)](#物理触觉反馈矩阵-haptic-feedback)
5. [水印排版与图像渲染设计 (Canvas Rendering Engine)](#5-水印排版与图像渲染设计-canvas-rendering-engine)
   - [EXIF 摄影边框水印排版算法 (Frame EXIF Renderer)](#exif-摄影边框水印排版算法-frame-exif-renderer)
   - [复古棉质手作纸浆纹理生成算法 (Procedural Paper Texture)](#复古棉质手作纸浆纹理生成算法-procedural-paper-texture)
   - [智能取色器引擎 (Adaptive Photo Color Extractor)](#智能取色器引擎-adaptive-photo-color-extractor)
   - [浮动与交错矩阵平铺 PNG 水印引擎 (Floating & Tiled PNG Renderer)](#浮动与交错矩阵平铺-png-水印引擎-floating--tiled-png-renderer)
6. [组件库规范与设计模式 (One UI Component Library)](#6-组件库规范与设计模式-one-ui-component-library)
7. [国际化与无障碍设计 (i18n & Accessibility)](#7-国际化与无障碍设计-i18n--accessibility)

---

## 1. 设计哲学与核心理念 (Design Philosophy)

本应用专为 Android 及 Samsung Galaxy 生态深度定制，旨在提供媲美系统级原生的水准与优雅感。整体设计严格贯彻 **Samsung One UI** 的四大支柱理念：

```
                    ┌─────────────────────────────────────────┐
                    │      One UI 核心设计哲学 (Philosophy)    │
                    └─────────────────────────────────────────┘
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         ▼                               ▼                               ▼
  【Viewing Area 观看区】        【Interaction Area 操作区】      【Tactile Haptics 触觉响应】
   上部 1/3 呈现视觉焦点           下部 2/3 集中手势与交互控制         操作反馈与毫秒级震动协同
   大字阶、沉浸式卡片堆叠          拇指黄金弧度范围单手操作           让调节参数如机械齿轮般清脆
```

1. **Viewing vs Interaction（视觉与操作分离）**：
   - 屏幕上部为专注浏览区（大图预览、卡片倾角动效、EXIF 铭牌）；
   - 屏幕下部为高效操作区（横滑工具条、Snapseed 盲操手势区、底部胶囊操作条）。
2. **Pebble Aesthetics（自然温润的鹅卵石形态）**：
   - 彻底摒弃生硬的圆形或标准圆角矩形，全链路采用数学级超椭圆曲线（Lamé Curve, $n=2.85$）；
   - 配合 0 边缘突兀感的微弥散阴影与通透的毛玻璃材质。
3. **One-Handed Usability（单手从容掌控）**：
   - 在双手不便或大屏设备单手握持场景下，所有核心调节无需将拇指伸向屏幕顶部，通过直觉手势即可完成全流程调节。
4. **Authenticity & Photography Respect（尊重摄影本质）**：
   - 严谨提取照片原始拍摄元数据（机型、光圈、等效焦距、曝光时间、ISO）；
   - 还原原版相机品牌视觉标识，提供冷暖自适应色调与纸浆肌理，赋予数字照片胶片冲印般的仪式感。

---

## 2. 视觉规范与设计系统 (Visual System & Tokens)

### 色彩体系 (Color Palette)

应用提供深色（AMOLED True Black）与浅色（Clean Slate）两种全局自适应主题，主色调汲取 Galaxy 经典电光蓝。

```
[ Galaxy Primary Blue ]  #0381FE   主品牌色 / 激活状态 / 关键按钮
[ Galaxy Blue Dark    ]  #0066D6   按压高亮 / 深色主题重点
[ Galaxy Blue Light   ]  #E8F3FF   浅色指示条底色 / 浅色高光
[ Snapseed Accent     ]  #FFD600   手势调节高亮 / HUD 焦点指示
```

#### 浅色主题 (Light Mode)
| Token | 十六进制值 | 用途说明 |
| :--- | :--- | :--- |
| `lightBackground` | `#F4F5F9` | 页面全局底色，温润高级灰 |
| `lightCardBg` | `#FFFFFF` | 卡片主体背景、弹窗底色 |
| `lightCardSubtle` | `#F7F8FA` | 次级容器底色、胶囊未选中背景 |
| `lightTextPrimary` | `#1E1E24` | 一级主要标题、高对比度正文 |
| `lightTextSecondary` | `#8E8E93` | 二级说明文案、辅助参数标签 |
| `lightDivider` | `#ECEEF2` | 分割线与细边框 |

#### 深色主题 (Dark Mode - Pure Black)
| Token | 十六进制值 | 用途说明 |
| :--- | :--- | :--- |
| `darkBackground` | `#000000` | 原汁原味纯黑背景（极致省电与通透对比） |
| `darkCardBg` | `#1C1C1E` | 卡片容器底色 |
| `darkCardSubtle` | `#2C2C2E` | 次级胶囊底色、轨道底色 |
| `darkTextPrimary` | `#FFFFFF` | 纯白主标题 |
| `darkTextSecondary` | `#98989F` | 暗色副标题与灰度参数 |
| `darkDivider` | `#2C2C2E` | 暗色分割线 |

---

### 超椭圆鹅卵石几何 (Pebble Squircle Geometry)

为了实现 Samsung One UI 标志性的圆润触感，应用通过 `SamsungSquircleClipper` 和 `createSamsungSquirclePath` 基于超椭圆极坐标方程动态生成矢量路径：

$$\left| \frac{x - c_x}{a} \right|^n + \left| \frac{y - c_y}{b} \right|^n = 1 \quad (n = 2.85)$$

- **标准卡片圆角**：`cardRadius = 24.0dp` (抗锯齿连续超椭圆)
- **胶囊按钮圆角**：`buttonRadius = 28.0dp`
- **小徽标/辅助控件**：`smallRadius = 14.0dp`
- **图标遮罩**：144 步高精度细分，曲率连续（$G^2$ 连续），杜绝普通圆角在切线处的突兀折角。

```
      普通圆角矩形 (Tangent Discontinuity)         三星超椭圆鹅卵石 (Continuous Curvature n=2.85)
            ╭───────────────╮                                 ╭───────────────╮
            │               │                                ╱                 ╲
            │   折角过渡不自然 │                               │     平滑曲率过渡   │
            │               │                                ╲                 ╱
            ╰───────────────╯                                 ╰───────────────╯
```

---

### 字阶与排版体系 (Typography)

全应用采用系统默认无衬线字体（One UI One Sans / Roboto），保持字距紧凑（Tight Tracking）以强化现代工业质感：

```
Display 1 (启动页大标题)   : 34pt / SemiBold(700) / Tracking +0.2 / LineHeight 1.1
Poster Title (海报大字)   : 28pt / ExtraBold(800)/ Tracking -0.5 / LineHeight 1.2
Section Header (分栏大字) : 20pt / Bold(700)     / Tracking -0.5 / LineHeight 1.2
Card Title (卡片标题)     : 16pt / SemiBold(600) / Tracking -0.2 / LineHeight 1.3
Body Regular (常规正文)   : 14pt / Regular(400)  / Tracking 0.0  / LineHeight 1.45
Caption / EXIF (参数标签) : 11~13pt / Bold(700)  / Tracking +0.5 / Monospace/Proportional
```

---

### 高斯模糊与多层材质 (Materials & Blur)

应用在弹窗底板、HUD 指示器、相框模糊底色上大量运用实时高斯模糊（`ui.ImageFilter.blur`）：
1. **Snapseed HUD 浮层**：`sigmaX: 20, sigmaY: 20`，配合 `#000000` (65% Alpha) + 1dp 22% 纯白边框与 24dp 圆角；
2. **底栏弹窗 (Blurred Bottom Sheet)**：`sigmaX: 25, sigmaY: 25`，配合 `#2C2C36` (40% Alpha)；
3. **模糊相框背景 (Blurred Photo Frame)**：`sigmaX: 45, sigmaY: 45`，搭配 52% 黑色压暗遮罩，确保前景照片及参数字体的极致清晰度。

---

### 空间布局与阴影阶梯 (Spacing & Elevation)

- **8pt 栅格系统**：外边距 `16dp`，卡片内边距 `14dp`，元素间距 `4dp / 8dp / 12dp / 16dp / 24dp`。
- **弥散软阴影 (Soft Ambient Shadows)**：
  - 卡片阴影：`Offset(0, 4)`, `blurRadius: 16`, `Color(0x0A000000)` (4% Alpha)；
  - 浮动图标外发光：双层叠加发光（极光紫 36% + 电光蓝 28%）；
  - 相框照片立体投影：随着 `shadowOpacity` 比例动态计算模糊核半宽与垂直落差。

---

## 3. UI 架构与页面交互流程 (UI & Interaction Flow)

应用采用平铺无路由单状态树架构，界面由「未导入时的探索态」与「导入后的沉浸工作台」无缝演进。

```
                               ┌───────────────────────────┐
                               │   SplashScreen 启动品牌页  │
                               └─────────────┬─────────────┘
                                             │ (350ms 平滑淡入)
                                             ▼
                     ┌───────────────────────────────────────────────┐
                     │            HomeScreen (未导入图片状态)         │
                     │  ┌─────────────────────────────────────────┐  │
                     │  │ Top: HeroPosterBanner 轮播海报展示      │  │
                     │  │ Bottom: CustomPhotoSelector 批量相册选择│  │
                     │  └─────────────────────────────────────────┘  │
                     └───────────────────────┬───────────────────────┘
                                             │ (一键勾选 / 批量导入)
                                             ▼
                     ┌───────────────────────────────────────────────┐
                     │            HomeScreen (进入编辑工作台)         │
                     │  ┌─────────────────────────────────────────┐  │
                     │  │ Top Area: CardStackPreview (扑克牌堆叠) │  │
                     │  │ Middle: 模式选择 Pill (边框水印 / PNG浮动)│  │
                     │  │ Bottom: AnimatedSubTabs & 动态参数操作面板│  │
                     │  │ Fixed Bottom: 批量导出与更多菜单胶囊     │  │
                     │  └─────────────────────────────────────────┘  │
                     └───────────────────────┬───────────────────────┘
```

---

### 闪屏与品牌心智 (Splash Screen)
- **视觉重心**：居中放置大尺寸 `AppPebbleIcon`，呈现高鲜艳度电光蓝至极光蓝紫渐变，中央堆叠微倾斜的双层纯白拟物相卡；
- **排版节奏**：`水印助手` (34pt) + `感受更强大的水印体验` (15pt 雅灰)；
- **过渡体验**：350ms 优雅淡出至主工作台。

---

### 首页探索与英雄海报 (Hero Poster Banner)
占据屏幕上部约 42% 空间，采用全幅实景摄影大图 + 电影级渐变遮罩：
- **四联精选主题轮播**：
  1. *边框水印* · 「随手皆风景」
  2. *叠加水印* · 「经典依旧经典」
  3. *手势操作* · 「单手亦从容」
  4. *动态图片* · 「不论如何一举拿下」
- **视觉分割**：大标题与说明文案严格锚定在黄金分割点（Top 12% + Safe Area），配以三点呼吸式轮播指示点（`8dp` 纯白微发光）。

---

### 全功能相册选择器 (Photo Selector & Album Grid)
- **多 Tab 分类**：支持 `全部照片`、`Ultra HDR 高动态`、`Motion 动态照片`、`相机拍摄` 快速筛选；
- **网格卡片设计**：3 列紧密排布，圆角平滑，右上方配备 One UI 原生样式圆形复选框（选中有蓝色缩放反弹动效）；
- **特殊徽标**：右上角自动探测并标注 `HDR` 金色徽标与 `Live Photo` 动态照片标识；
- **吸底操作条**：浮动胶囊展示当前已选中张数，一键触发高性能后台并行导入。

---

### 核心工作台：扑克牌堆叠与双模式画布 (Card Stack Workspace)

#### 1. 扑克牌多图堆叠 (Card Stack Physics)
当批量导入多张图片时，画布以逼真的 3D 物理层叠呈现：
- **底二层卡片**：缩放 `0.91`，向左位移 `-10dp`，倾角 `-2.5°`，55% 不透明度；
- **底一层卡片**：缩放 `0.96`，向右位移 `+8dp`，倾角 `+2.2°`，55% 不透明度；
- **顶层激活卡片**：支持左右轻扫切牌（带 `Curves.easeOutBack` 回弹与倾斜跟随物理惯性）。

#### 2. 双模式无缝切换 (Segmented Pill)
- **边框水印模式 (Frame Mode)**：为照片生成精美摄影外框，自动排版相机品牌矢量 Logo 与完整 EXIF 参数；
- **浮动 PNG 模式 (Floating PNG Mode)**：支持用户自定义 PNG 水印、文字印章或全图满铺防盗水印。

---

## 4. 核心交互引擎：Snapseed 极简盲操系统 (Snapseed Gesture Engine)

为解决复杂水印参数在手机屏幕上频繁点选滑块导致遮挡视线的痛点，本应用设计了 **Snapseed-Style 全画幅盲操手势引擎**。

```
                        ┌─────────────────────────────────────┐
                        │      手势滑动方向与参数映射模型       │
                        └─────────────────────────────────────┘
                                           │
             ┌─────────────────────────────┴─────────────────────────────┐
             ▼                                                           ▼
     【垂直纵向拖拽 Δy】                                          【水平横向拖拽 Δx】
   累计位移超过 24dp 步进阈值                                    平滑连续修改当前参数数值
   上下切换当前调节的参数维度                                     配合 10 级等分触觉咔哒反馈
```

### 手势分流与阻尼映射

1. **垂直滑动 (Parameter Switching)**：
   - 累加垂直位移 `_verticalAccumulator`；
   - 当位移超出 `±24dp` 阈值时触发参数步进，并重置累加器；
   - 步进时发出 `HapticFeedback.selectionClick()`；
   - 达到首尾项时提供柔和回弹阻尼（`±6dp` Visual Offset），杜绝突兀跳变。

2. **水平滑动 (Value Fine-Tuning)**：
   - 灵敏度按参数物理量程定制适配：
     - 四周边距 / 留白：`dx * 0.0006`
     - 底部参数栏高度：`dx * 0.0012`
     - 尺寸缩放 / 位置偏移：`dx * 0.005`
     - 旋转角度：`dx * 0.8°`
   - 数值跨越每 $10\%$ 区间里程碑时，触发精准震动提示。

---

### 中央固定焦点 HUD 滚轮 (Center-Fixed Wheel HUD)

传统滚轮菜单移动焦点框会让用户视线上下跟随造成疲劳。本设计采用 **“中央焦点恒定不动，参数列表反向位移穿过焦点”** 的视准仪模型：

```
                      ┌───────────────────────────┐
                      │    Snapseed HUD (120dp)   │
                      │                           │
                      │       上一项参数 (38%灰)   │
                      │ ┌───────────────────────┐ │
                      │ │ ▶ 当前选定参数 (100%黄) │ │ <--- 焦点框固定在绝对中心 (Top 42dp)
                      │ └───────────────────────┘ │
                      │       下一项参数 (38%灰)   │
                      │                           │
                      └───────────────────────────┘
```

- **视觉规范**：
  - 宽 `200dp`，高 `120dp`，单项高 `36dp`；
  - 材质为 20dp 高斯模糊 + 65% 黑色透亮层 + 24dp 超椭圆圆角；
  - 居中焦点框：`1.2dp` 粗细 `#FFD600` 亮黄边框 + 16% 黄色填充；
  - 动态淡入淡出（纵向滑动时立即显现，静止 650ms 后自然隐退）。

---

### 十点磁吸九宫格 (Ten-Point Smart Snapping)

在浮动水印模式下，画布提供基于欧氏距离快速吸附的 10 个经典构图锚点：

```
       [0.12, 0.12] 左上 ──── [0.50, 0.12] 中上 ──── [0.88, 0.12] 右上
             │                      │                      │
       [0.12, 0.50] 左中 ──── [0.50, 0.50] 正中 ──── [0.88, 0.50] 右中
             │                      │                      │
       [0.12, 0.88] 左下 ──── [0.50, 0.88] 中下 ──── [0.88, 0.88] 右下
                                    │
                              [0.50, 0.80] 底标
```
- 点击画布任意位置，自动计算与 10 个锚点的平方距离 $d^2 = (\Delta x)^2 + (\Delta y)^2$；
- 瞬间吸附到最近点，并在点击位置生成涟漪反馈与参数提示。

---

### 物理触觉反馈矩阵 (Haptic Feedback)

| 触发场景 | 震动类型 | 触觉感知 |
| :--- | :--- | :--- |
| 垂直滑动手势切换参数项 | `HapticFeedback.selectionClick()` | 清脆微震（机械齿轮进位感） |
| 水平滑动数值达到 10% 整数倍 | `HapticFeedback.selectionClick()` | 轻微段落感（阻尼刻度感） |
| 点击九宫格磁吸或关键按钮 | `HapticFeedback.lightImpact()` | 扎实击打感 |
| 打开全屏关于页 / 弹窗弹出 | `HapticFeedback.mediumImpact()` | 沉稳确认感 |

---

## 5. 水印排版与图像渲染设计 (Canvas Rendering Engine)

所有水印渲染均运行于高保真矢量/位图混合渲染管线（`FrameCanvasRenderer` 与 `FloatingPngRenderer`），100% 还原至全分辨率导出。

### EXIF 摄影边框水印排版算法 (Frame EXIF Renderer)

```
┌───────────────────────────────────────────────────────────────────┐
│  PAD                                                              │
│ ┌────┬─────────────────────────────────────────────────────┬────┐ │
│ │    │                                                     │    │ │
│ │PAD │                 Photo Viewport 主照片                │PAD │ │
│ │    │        (支持 effectiveCornerRadius 与柔和外投影)       │    │ │
│ │    │                                                     │    │ │
│ └────┴─────────────────────────────────────────────────────┴────┘ │
│  PAD                                                              │
│ ├─────────────────────────────────────────────────────────────────┤
│ │ [Brand Logo / 机型大标]              [EXIF 参数 23mm f/1.7 1/2000s] │
│ │                                     [拍摄时间 2024.08.20 16:30]  │
│ └─────────────────────────────────────────────────────────────────┘
│                           Bottom Bar Height                       │
└───────────────────────────────────────────────────────────────────┘
```

1. **外边框与底部参数栏自适应比例**：
   - 边框外圈留白：`pad = totalWidth * (paddingRatio / (1 + 2 * paddingRatio))`
   - 底部参数栏高度：`bottomBarH = totalHeight * (bottomBarRatio / (1 + paddingRatio + bottomBarRatio))`
2. **左侧品牌区**：
   - 优先渲染品牌 Vector Logo（等比缩放且高度受限于 `bottomBarH * 0.42 * logoScale`）；
   - 若无 Logo 则渲染纯文字大写机型（800 粗体，大字距）。
3. **右侧参数区**：
   - 第一行（强对比色）：`焦距 光圈 快门 ISO`（如 `23mm  f/1.7  1/2000s  ISO 50`）；
   - 第二行（弱对比灰）：`拍摄日期时间`（如 `2024.08.20 16:30`）。

---

### 复古棉质手作纸浆纹理生成算法 (Procedural Paper Texture)

为了重现高端艺术微喷棉纸的温润质感，应用采用基于确定性伪随机 Hash 函数的过程化纹理算法，无需加载任何外置大图即可在任意分辨率生成无接缝纸张纹理：

```
                ┌─────────────────────────────────────────┐
                │ 确定性 Hash 函数:                        │
                │ n = |sin(x·12.9898 + y·78.233)·43758.5| │
                └────────────────────┬────────────────────┘
                                     │
           ┌─────────────────────────┼─────────────────────────┐
           ▼                         ▼                         ▼
   【浅色漫反射微光】         【纸浆微小暗斑点】          【有机短纤维丝】
    n3 > 0.65 绘制微小白斑     n3 > 0.35 绘制微暗颗粒      n1 > 0.82 绘制自然弯折纤维
```

- **基底色泽**：双层混合暖米黄纸浆底色（`#FAF6EE` 至 `#F2EBDC` 的柔光线性渐变）；
- **全幅覆盖**：步长随图片尺寸自适应调节，无论是 1080P 预览还是 5000 万像素原图，颗粒细节纤毫毕现。

---

### 智能取色器引擎 (Adaptive Photo Color Extractor)

`PhotoColorExtractor` 在后台快速采样照片约 300 个核心像素点，并运用三维 RGB 空间欧氏距离过滤算法：

$$\text{Dist}^2 = (R_1 - R_2)^2 + (G_1 - G_2)^2 + (B_1 - B_2)^2 < 1600$$

自动筛除过于相近的邻近色，提取出代表该照片色调精髓的 **8 种独立代表色**，作为一键相框底色供用户选择。

---

### 浮动与交错矩阵平铺 PNG 水印引擎 (Floating & Tiled PNG Renderer)

1. **反色滤镜矩阵 (Invert Color Filter)**：
   应用设计了专用的 $4 \times 5$ 颜色矩阵，一键反转黑白线稿水印，使黑色 Logo 瞬间变为清透纯白以适应暗光照片：
   $$\begin{bmatrix} -1 & 0 & 0 & 0 & 255 \\ 0 & -1 & 0 & 0 & 255 \\ 0 & 0 & -1 & 0 & 255 \\ 0 & 0 & 0 & 1 & 0 \end{bmatrix}$$
2. **交错矩阵平铺 (Staggered Grid Tiling)**：
   在平铺防盗模式下，奇数行自动进行半个周期的横向偏移（`stepX / 2`），形成优雅的对角线交错排列，全面覆盖画面。

---

## 6. 组件库规范与设计模式 (One UI Component Library)

应用沉淀了一套轻量级、高复用、完全符合 One UI 规范的 Flutter 专属组件库：

```
lib/widgets/
├── one_ui_card.dart             # 20dp/24dp 超椭圆质感卡片容器 (支持标题栏与右上角操作)
├── one_ui_segmented_pill.dart   # 经典双联/多联滑动胶囊切换器 (带 200ms easeInOut 动效)
├── one_ui_slider.dart           # 8dp 轨道、10dp 拇指的一体化粗滑块
├── one_ui_nine_grid.dart        # 经典 3x3 九宫格微调吸附选择器
├── pebble_icon.dart             # 超椭圆鹅卵石图标矢量画笔
├── card_stack_preview.dart      # 扑克牌物理堆叠预览与手势分发器
├── custom_photo_selector.dart   # 原生体验多选相册网格
├── export_bottom_sheet.dart     # 导出进度、格式选择与 ADPF 状态底栏
└── sheets/
    ├── preset_picker_sheet.dart # 预设管理与套用抽屉
    └── quick_options_sheet.dart # 快捷配置与功能菜单
```

---

## 7. 国际化与无障碍设计 (i18n & Accessibility)

- **动态双语系统 (`AppStrings`)**：
  - 默认根据系统 Locale 自动识别中文（`zh`）或英文（`en`）；
  - 全局采用 `ValueNotifier<AppLanguage>`，切换语言时全应用所有文本组件与 Canvas 绘制文案零延迟实时重绘，无需重启应用。
- **高对比度保证**：
  - 浅色模式下文本对比度达 $12.5:1$，深色模式下达 $18:1$，完全超越 WCAG AAA 级无障碍阅读标准；
  - 针对纸张纹理模式专门定制了深栗褐色（`#2C241D`）主文本与雅灰褐色（`#7A6B5D`）副文本，确保阅读舒适且极具复古韵味。

---

> **结语**：Watermark Assistant 将专业摄影参数的严谨之美，与 Samsung One UI 的温润流畅融为一体。每一处圆角曲率、每一次指尖滑动、每一帧高动态渲染，皆为呈现旗舰级移动影像的纯粹魅力。
