/**
 * 全局常量与纯计算。
 * 抽出来给各个视图组件共享，避免常量散落和硬编码。
 */

// ---------- 详情页：下滑退出 ----------
/** 下拉多远算「退出」（vp）。超过它就松手关闭，否则回弹 */
export const DISMISS_DISTANCE: number = 110;
/** 甩动速度达到这个值也算退出（vp/s）：位移不够但甩得够快同样关掉 */
export const DISMISS_VELOCITY: number = 900;
/** 退出过程中最多缩到多小 —— 退场时轻微缩小，像被「丢回去」 */
export const DISMISS_MIN_SCALE: number = 0.82;
/** 位移多少距离时背景完全透明（vp） */
export const DISMISS_FADE_SPAN: number = 340;
/** 横屏详情页：右侧信息面板的固定宽度（vp） */
export const DETAIL_PANEL_W: number = 320;

// ---------- 排布方式 ----------
export const LAYOUT_GRID: number = 0;
export const LAYOUT_WATERFALL: number = 1;
export const LAYOUT_SHOWCASE: number = 2;
export const LAYOUT_LIST: number = 3;
// 画廊系列：更强调"陈列"的视觉语言
export const LAYOUT_WALL: number = 4;       // 展厅墙：画框大小不一、高低错落
export const LAYOUT_CORRIDOR: number = 5;   // 透视长廊：近大远小，向纵深推进
export const LAYOUT_CAROUSEL: number = 6;   // 旋转展台：中央放大，两侧后仰
export const LAYOUT_TIMELINE: number = 7;   // 时间轴：按日期分段，左右交错
export const LAYOUT_COUNT: number = 8;

// ---------- 排序方式 ----------
export const SORT_TIME_DESC: number = 0;
export const SORT_TIME_ASC: number = 1;
export const SORT_NAME: number = 2;
export const SORT_SIZE_DESC: number = 3;
export const SORT_MANUAL: number = 4;

// ---------- 内容筛选 ----------
export const FILTER_ALL: number = 0;
export const FILTER_IMAGE: number = 1;
export const FILTER_VIDEO: number = 2;
// 底部导航第 4 项：按分组（组合）浏览
export const NAV_COMBO: number = 3;

// ---------- 顶栏几何（vp）----------
export const TOP_BTN_H: number = 36;
export const TOP_LEAD_W: number = 56;
export const TOP_SORT_W: number = 68;
export const TOP_MORE_W: number = 36;
/** 顶栏浮层的毛玻璃模糊半径 */
export const HEADER_BLUR: number = 36;

// ---------- 底部导航几何（vp）----------
export const NAV_H: number = 46;
export const NAV_GAP: number = 10;
export const NAV_SIDE: number = 46;
/** 导航胶囊距屏幕底部的间距（不含安全区） */
export const NAV_MARGIN: number = 22;
/** 旋转展台：主图下方镜像倒影的高度（vp） */
export const CAROUSEL_REFLECT_H: number = 140;
/** 旋转展台：主图与镜像倒影之间的间距（vp） */
export const CAROUSEL_REFLECT_GAP: number = 14;
/** 旋转展台：相邻项露出的宽度（vp），左右各一份；项宽 = Swiper 宽 - 2 × 该值 */
export const CAROUSEL_MARGIN: number = 62;
/** 旋转展台：手指按住拖动时，整体后仰到同一角度（度） */
export const CAROUSEL_DRAG_ROTATE: number = 12;
/** 旋转展台：手指按住拖动时的整体缩放 */
export const CAROUSEL_DRAG_SCALE: number = 0.94;
/** 旋转展台：静止时两侧卡片的倾斜角（度），左右对称 */
export const CAROUSEL_SIDE_ROTATE: number = 20;
/** 旋转展台：静止时两侧卡片的缩放 */
export const CAROUSEL_SIDE_SCALE: number = 0.86;
/** 旋转展台：甩动速度达到这个值才算「快速翻页」（vp/ms），低于它交给 Swiper 自己吸附 */
export const CAROUSEL_FLING_V: number = 1.0;
/** 旋转展台：甩动速度每超出阈值这么多，就多翻一张（vp/ms） */
export const CAROUSEL_FLING_STEP: number = 0.8;
/** 旋转展台：单次手势最多翻几张 */
export const CAROUSEL_FLING_MAX: number = 4;
/** 旋转展台：甩动判定的最短采样窗口（ms），低于它算出的速度不可信 */
export const CAROUSEL_FLING_MIN_MS: number = 24;
/** 旋转展台：甩动判定的最小位移（vp），低于它视为误触或抖动，不翻页 */
export const CAROUSEL_FLING_MIN_DX: number = 28;
/** 透视长廊：卡片固定高度（vp）。宽度由它乘图片比例得出。
 *  124 + 行距 6 = 行高 130，780/130 ≈ 6 行 —— 这就是「一屏 5-6 行」的来源 */
export const CORRIDOR_CARD_H: number = 124;
/** 透视长廊：卡片侧面的厚度（vp），画在背离中线的那一侧 */
export const CORRIDOR_SIDE_W: number = 12;
/** 透视长廊（横屏）：横向推进时每张卡的统一宽度（vp）。
 *  横向焦点按「第几列」算，宽度必须固定，否则焦点会飘 */
export const CORRIDOR_ACROSS_W: number = 148;
/** 透视长廊：行间距（vp）。滚动位置换算焦点行时要用它 */
export const CORRIDOR_GAP: number = 6;
/** 透视长廊：卡片贴墙时留给屏幕边缘的宽度（vp）。
 *  卡片按「外边缘对齐」摆位，这条留白就是两列各自的起跑线。
 *  它和最宽卡片之和必须小于半个屏宽，否则会捅到中线对面去：
 *  14 + 124×1.24 = 168 < 180 ✓ */
export const CORRIDOR_WALL: number = 14;
/** 透视长廊：从最近到最远，整列向中线收拢的总距离（vp） */
export const CORRIDOR_COLLAPSE: number = 38;
/** 透视长廊：圆角半径（vp）。近端（贴墙那一侧）的两个角保持直角，
 *  只有远端的两个角做圆角 —— 直角的那条边才像「压在墙上」 */
export const CORRIDOR_CLIP_R: number = 12;
/** 透视长廊：卡片宽高比的上下限。
 *  上限 1.24 是几何上限：两张最宽的卡并排时中间还要剩约 24vp 的缝。
 *  下限抬到 0.95 是为了不让竖图把中间撑出一大片空白 —— 竖图会裁得比较多，
 *  这是「一行两张」必然的代价 */
export const CORRIDOR_RATIO_MIN: number = 0.95;
export const CORRIDOR_RATIO_MAX: number = 1.24;
/** 透视长廊：最远处卡片的侧转角（度）。两侧向走廊中线内转，形成隧道感。
 *  若实机看起来是「向外翻开」而不是「向内收拢」，把这里的正负号翻一下即可。
 *  实测 30° 时几乎看不出侧转（宽度只压到 0.87，和 scaleX 的效果糊在一起），
 *  38° 起才成立：宽度压到 0.79，配合受光面就能读出「转过去了」 */
export const CORRIDOR_YAW: number = 38;
/** 透视长廊：远端被透视压扁的比例，0 表示不压（仍是矩形）。
 *  这一项是「梯形」的唯一来源 —— RotateOptions.perspective 在实机上不产生
 *  任何梯形（已实测），而 2D 仿射变换数学上也变不出梯形，只能自己裁 */
export const CORRIDOR_TAPER: number = 0.25;
/** 透视长廊：纵向收缩系数。真实透视里「纵向间距」也随距离缩短，
 *  而列表布局是等距的，所以要把远处的项往消失点拉。
 *  位移按 d² 增长（近处几乎不动、远处拉得多），d 封顶 4 层 */
export const CORRIDOR_LIFT: number = 6;
/** 透视长廊：纵向收缩的层数上限，超过就不再拉，避免远处的项叠成一坨 */
export const CORRIDOR_LIFT_MAX_D: number = 4;

// ---------- 内容切换过渡（纯计算，多个视图共用）----------
// 阶段约定：0 稳定，1 旧内容左右退场，2 新内容自下而上补位

/** 网格列模板 */
export function gridTemplate(columns: number): string {
  if (columns === 2) {
    return '1fr 1fr';
  }
  if (columns === 4) {
    return '1fr 1fr 1fr 1fr';
  }
  return '1fr 1fr 1fr';
}

/** 是否属于画廊系列排布（决定用哪个视图组件渲染） */
export function isGalleryLayout(mode: number): boolean {
  return mode === LAYOUT_WALL
    || mode === LAYOUT_CORRIDOR
    || mode === LAYOUT_CAROUSEL
    || mode === LAYOUT_TIMELINE;
}

/** 退场横移：偶数项向左、奇数项向右，越靠后移得越远 */
export function exitShiftX(phase: number, index: number): number {
  if (phase !== 1) {
    return 0;
  }
  const dir: number = index % 2 === 0 ? -1 : 1;
  return dir * (88 + (index % 4) * 12);
}

/** 进场下移：越靠后的项起点越低，补位时形成层次 */
export function enterShiftY(phase: number, index: number): number {
  if (phase !== 2) {
    return 0;
  }
  return 64 + (index % 8) * 10;
}

/** 内容整体不透明度：过渡期间为 0，由 .animation 自动补间 */
export function phaseOpacity(phase: number): number {
  return phase === 0 ? 1 : 0;
}

/** 退场用短时长，补位用长时长（阶段切到 0 时读到的是补位时长） */
export function phaseAnimDuration(phase: number): number {
  return phase === 1 ? 110 : 240;
}
