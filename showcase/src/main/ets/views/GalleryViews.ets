import { PathShape } from '@kit.ArkUI';
import { MediaItem } from '../model/MediaItem';
import { MediaDataSource } from '../model/MediaDataSource';
import { PairDataSource } from '../model/PairDataSource';
import { TimelineEntry } from '../model/TimelineEntry';
import { mediaFill } from '../common/Widgets';
import {
  LAYOUT_WALL,
  LAYOUT_CORRIDOR,
  LAYOUT_CAROUSEL,
  CAROUSEL_REFLECT_H,
  CAROUSEL_MARGIN,
  CAROUSEL_REFLECT_GAP,
  CAROUSEL_DRAG_ROTATE,
  CAROUSEL_DRAG_SCALE,
  CAROUSEL_SIDE_ROTATE,
  CAROUSEL_SIDE_SCALE,
  CAROUSEL_FLING_V,
  CAROUSEL_FLING_STEP,
  CAROUSEL_FLING_MAX,
  CAROUSEL_FLING_MIN_MS,
  CAROUSEL_FLING_MIN_DX,
  CORRIDOR_CARD_H,
  CORRIDOR_SIDE_W,
  CORRIDOR_ACROSS_W,
  CORRIDOR_GAP,
  CORRIDOR_WALL,
  CORRIDOR_COLLAPSE,
  CORRIDOR_CLIP_R,
  CORRIDOR_RATIO_MIN,
  CORRIDOR_RATIO_MAX,
  CORRIDOR_YAW,
  CORRIDOR_TAPER,
  CORRIDOR_LIFT,
  CORRIDOR_LIFT_MAX_D,
  exitShiftX,
  enterShiftY,
  phaseOpacity,
  phaseAnimDuration
} from '../common/Constants';

/**
 * 画廊系列排布：展厅墙 / 透视长廊 / 旋转展台 / 时间轴。
 * 只负责渲染，数据源与交互回调由父组件注入。
 */
@Component
export struct GalleryViews {
  /** 列表数据源（LazyForEach 用）：父组件 setItems 后 notifyReload 即可驱动刷新 */
  ds: MediaDataSource = new MediaDataSource();
  /** 大数组用 @Link 传引用，避免 @Prop 的值拷贝。
   *  items 一变就重切长廊的行 —— 长廊按「行」渲染，不能直接用这个数组 */
  @Link @Watch('syncCorridorRows') items: MediaItem[];
  @Link timeline: TimelineEntry[];

  @Prop layoutMode: number;
  /** 内容切换阶段：0 稳定，1 退场，2 补位 */
  @Prop contentPhase: number;
  @Prop headerHeight: number;
  /** 内容底部留白（父组件按导航高度算好）：滚动容器用它，0 表示铺到屏幕底 */
  @Prop contentPad: number;
  /** 底部导航总高：浮层控件用它避让，避免被导航盖住 */
  @Prop navBlock: number;
  /** 横屏：长廊转成横向推进，展台收一收倒影 */
  @Prop isLandscape: boolean = false;

  onCardTap: (index: number) => void = () => {};
  onLongPress: (id: string) => void = () => {};
  onScroll: (first: number) => void = () => {};

  /** 透视长廊的焦点行。**带小数** —— 只取整行会让一屏卡片一起咯噔跳 */
  @State corridorFocus: number = 0;
  /** 透视长廊的画布尺寸：横屏走横向滚动，焦点要按横向偏移算 */
  @State corridorW: number = 0;
  /** 透视长廊的画布高度：滚动位置换算焦点行时要用它 */
  @State corridorH: number = 0;
  /** 透视长廊的滚动控制器：焦点要跟着滚动位置连续走，
   *  onScrollIndex 只在跨行时触发，取不到中间过程 */
  private corridorScroller: Scroller = new Scroller();
  /** 透视长廊的行数据源：两张一行，左右并排 */
  private corridorRows: PairDataSource = new PairDataSource();
  /** 旋转展台：基准索引，单向 —— 只由 Swiper 的 onChange 写入，绝不回写 Swiper */
  @State carouselIndex: number = 0;
  /** 旋转展台：手指是否正按在展台上拖动。由 onTouch 直接驱动，
   *  只在按下/抬起各变一次，拖动全程不再变化 */
  @State carouselDragging: boolean = false;
  private carouselSwiper: SwiperController = new SwiperController();
  /** 展台甩动判定：本次手势的起点、以及往左右两侧伸出的最远点。
   *  普通成员而非 @State —— 它们每帧都在变，绝不能参与 UI 刷新。 */
  private touchTracking: boolean = false;
  private touchStartX: number = 0;
  private touchStartMs: number = 0;
  private touchMinX: number = 0;
  private touchMaxX: number = 0;
  private touchLastMs: number = 0;
  /** 展台甩动：还欠多少张没走。正数往后翻，负数往前翻，走完归零。
   *  用「待走张数」而不是目标索引 —— 绝对值会被 Swiper 的环形位置绕反。 */
  private flingRemain: number = 0;

  aboutToAppear(): void {
    // @Watch 只在 items 变化时触发，首次挂载得自己同步一次。
    // 长廊是按「行」渲染的，行数据源必须在这里先切好
    this.syncCorridorRows();
  }

  /** items 一变就重切长廊的行。两张一行，左右并排。 */
  syncCorridorRows(): void {
    this.corridorRows.setItems(this.items);
    this.corridorRows.notifyReload();
  }

  build() {
    if (this.layoutMode === LAYOUT_WALL) {
      this.wallLayout();
    } else if (this.layoutMode === LAYOUT_CORRIDOR) {
      this.corridorLayout();
    } else if (this.layoutMode === LAYOUT_CAROUSEL) {
      this.carouselLayout();
    } else {
      this.timelineLayout();
    }
  }

  // ---------- ① 展厅墙：画框大小不一、高低错落 ----------

  @Builder
  wallLayout() {
    WaterFlow() {
      LazyForEach(this.ds, (item: MediaItem, index: number) => {
        FlowItem() {
          this.wallFrame(item, index);
        }
        .width('100%')
        .aspectRatio(this.wallRatio(index))
        .margin({ top: index % 2 === 0 ? 0 : 26, left: index % 2 === 0 ? 0 : 12 })
        .translate({ x: exitShiftX(this.contentPhase, index), y: enterShiftY(this.contentPhase, index) })
        .opacity(phaseOpacity(this.contentPhase))
        .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
      }, (item: MediaItem) => item.id)
    }
    // 横屏屏宽翻倍，两列会让画框宽得离谱；加到三列，尺寸才和竖屏接近
    .columnsTemplate(this.isLandscape ? '1fr 1fr 1fr' : '1fr 1fr')
    .columnsGap(14)
    .rowsGap(14)
    .padding({ left: 16, right: 16, bottom: this.contentPad })
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .onScrollIndex((first: number) => {
      this.onScroll(first);
    })
    .contentStartOffset(this.headerHeight)
    .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseInOut }))
  }

  /** 奇偶交替「竖幅 / 横幅」，形成挂画的高低差 */
  wallRatio(index: number): number {
    return index % 2 === 0 ? 0.78 : 1.16;
  }

  @Builder
  wallFrame(item: MediaItem, index: number) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        mediaFill(item);
      }
      .width('100%')
      .height('100%')
      .borderRadius(1)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .padding(6)
    .backgroundColor($r('app.color.c_frame'))
    .borderRadius(4)
    .shadow({ radius: 16, color: $r('app.color.c_shadow'), offsetX: 0, offsetY: 8 })
    .onClick(() => {
      this.onCardTap(index);
    })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.onLongPress(item.id);
    }))
  }

  // ---------- ② 透视长廊：两侧展板向纵深推进 ----------

  @Builder
  corridorLayout() {
    if (this.isLandscape) {
      this.corridorAcross();
    } else {
      this.corridorDown();
    }
  }

  /**
   * 横屏长廊：改成横向推进。
   *
   * 竖屏那套是「一屏好几行、越往下越小」，靠的是屏高够 —— 横屏只剩 ~360vp，
   * 一屏只放得下两行，纵深链条直接断掉。转 90° 之后屏宽有 780vp，
   * 能同时看到五六层，「近大远小」才有得看。
   *
   * 横屏下卡片改用统一宽度：横向滚动的焦点要按「第几列」算，
   * 宽度不一的话每列占多宽都不确定，焦点就飘了。
   */
  @Builder
  corridorAcross() {
    Stack({ alignContent: Alignment.Center }) {
      // 尽头的光：横屏下挪到右侧，因为纵深方向变成了自左向右
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['88%', '50%'],
          radius: '42%',
          colors: [
            [$r('app.color.c_corridor_glow'), 0],
            [$r('app.color.c_corridor_glow'), 0.35],
            ['#00000000', 1]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      List({ space: CORRIDOR_GAP, scroller: this.corridorScroller }) {
        LazyForEach(this.ds, (item: MediaItem, index: number) => {
          ListItem() {
            this.corridorCardA(item, index);
          }
          .translate({ x: exitShiftX(this.contentPhase, index), y: enterShiftY(this.contentPhase, index) })
          .opacity(phaseOpacity(this.contentPhase))
          .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
        }, (item: MediaItem) => item.id)
      }
      .listDirection(Axis.Horizontal)
      .width('100%')
      .height('100%')
      .padding({ left: CORRIDOR_WALL, right: CORRIDOR_WALL })
      .scrollBar(BarState.Off)
      .onScrollFrameBegin((offset: number, _state: ScrollState): OnScrollFrameBeginHandlerResult => {
        this.syncCorridorFocusAcross();
        return { offsetRemain: offset };
      })
      .onScrollIndex((first: number, last: number) => {
        this.syncCorridorFocusAcross();
        this.onScroll(first);
      })

      // 暗角：横屏下压上下两边，暗示「走廊的墙在上下」
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            ['#59000000', 0],
            ['#00000000', 0.22],
            ['#00000000', 0.78],
            ['#59000000', 1]
          ]
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w = newArea.width;
      const h = newArea.height;
      if (typeof w === 'number' && w > 0) {
        this.corridorW = w;
      }
      if (typeof h === 'number' && h > 0) {
        this.corridorH = h;
      }
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseInOut }))
  }

  /** 横向滚动的焦点：屏幕正中落在第几列 */
  syncCorridorFocusAcross(): void {
    if (this.corridorW <= 0) {
      return;
    }
    const x: number = this.corridorScroller.currentOffset().xOffset;
    const contentX: number = x + this.corridorW / 2 - CORRIDOR_WALL;
    this.corridorFocus = contentX / (CORRIDOR_ACROSS_W + CORRIDOR_GAP);
  }

  /** 横向长廊的一张卡：宽度统一，高度按图片比例浮动（钳制） */
  @Builder
  corridorCardA(item: MediaItem, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      mediaFill(item);
    }
    .width(CORRIDOR_ACROSS_W)
    .height(CORRIDOR_ACROSS_W / this.corridorRatio(item))
    .borderRadius(12)
    .clip(true)
    .shadow({
      radius: this.corridorShadowRadius(index),
      color: this.corridorShadowColor(index),
      offsetX: 0,
      offsetY: 6
    })
    .scale({ x: this.corridorScaleX(index), y: this.corridorScaleX(index) })
    .opacity(this.corridorOpacity(index))
    .zIndex(this.corridorZ(index))
    .onClick(() => {
      this.onCardTap(index);
    })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.onLongPress(item.id);
    }))
  }

  @Builder
  corridorDown() {
    Stack({ alignContent: Alignment.Center }) {
      // 走廊深处：消失点那一团柔光。
      // 地面和墙脚线画出了空间的「骨头」，但没有这团光，走廊尽头是一片死黑，
      // 视线无处可落 —— 它给出「尽头有光」的暗示，纵深才收得住。
      // 刻意用暖金而不是白色：和这个应用的红金基调一致，也不像冷白那样刺眼。
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '50%'],
          radius: '38%',
          colors: [
            [$r('app.color.c_corridor_glow'), 0],
            [$r('app.color.c_corridor_glow'), 0.35],
            ['#00000000', 1]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      List({ space: CORRIDOR_GAP, scroller: this.corridorScroller }) {
        LazyForEach(this.corridorRows, (row: MediaItem[], rowIndex: number) => {
          ListItem() {
            this.corridorRow(row, rowIndex);
          }
          .translate({ x: exitShiftX(this.contentPhase, rowIndex), y: enterShiftY(this.contentPhase, rowIndex) })
          .opacity(phaseOpacity(this.contentPhase))
          .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
        }, (row: MediaItem[], rowIndex: number) => row[0].id + '_' + rowIndex)
      }
      .width('100%')
      .height('100%')
      // 左右不留内边距：卡片的左右位置由 translate 决定
      .padding({ bottom: this.contentPad })
      .scrollBar(BarState.Off)
      .onScrollFrameBegin((offset: number, _state: ScrollState): OnScrollFrameBeginHandlerResult => {
        // 逐帧刷新焦点，卡片才是「跟着手指连续变化」而不是「跨一行跳一次」
        this.syncCorridorFocus();
        return { offsetRemain: offset };
      })
      .onScrollIndex((first: number, last: number) => {
        this.syncCorridorFocus();
        this.onScroll(first);
      })
      .contentStartOffset(this.headerHeight)

      // 消失点暗角：中央留一点微光、四周压暗
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '50%'],
          radius: '74%',
          colors: [
            ['#12FFFFFF', 0],
            ['#00000000', 0.52],
            ['#59000000', 1]
          ]
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      // 只要高度：滚动位置换算焦点行时要用它
      const h = newArea.height;
      if (typeof h === 'number' && h > 0) {
        this.corridorH = h;
      }
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseInOut }))
  }

  /**
   * 把滚动位置换算成「屏幕正中落在第几行」，**带小数**。
   *
   * 原来直接用 onScrollIndex 的 (first + last) / 2：它只在滚动跨过整行时触发，
   * 一屏五张卡片会整排一起咯噔跳一下 —— 所有纵深参数都挂在焦点距离上，
   * 于是大小、位置、透明度、阴影、梯形同时跳，这就是「不够丝滑」的来源。
   * 换成按滚动偏移连续取值，卡片才会跟着手指一路平滑地变。
   */
  syncCorridorFocus(): void {
    if (this.corridorH <= 0) {
      return;
    }
    const y: number = this.corridorScroller.currentOffset().yOffset;
    // 内容坐标：屏幕中心往下数，扣掉内容起始的偏移
    const contentY: number = y + this.corridorH / 2 - this.headerHeight;
    this.corridorFocus = contentY / (CORRIDOR_CARD_H + CORRIDOR_GAP);
  }

  /** 该行离透视焦点的距离，单位是「行」 */
  corridorD(index: number): number {
    return Math.abs(index - this.corridorFocus);
  }

  /** 横向缩放：按 1/(1+kd) 衰减，这是透视投影的真实规律。
   *  效果是「近处几层差别大、远处几层挤在一起」——
   *  线性衰减会让第 3 层和第 4 层看起来一样远，隧道尽头就散了 */
  corridorScaleX(index: number): number {
    const s: number = 1 / (1 + this.corridorD(index) * 0.25);
    return s > 0.44 ? s : 0.44;
  }

  /** 纵向缩放：衰减比横向更快，模拟透视里的「缩短」——
   *  只靠等比缩小的话，远处那张仍是个端正的小卡片，不会被压出纵深 */
  corridorScaleY(index: number): number {
    const s: number = 1 / (1 + this.corridorD(index) * 0.33);
    return s > 0.40 ? s : 0.40;
  }

  /** 纵向收缩：把远处的项往消失点（焦点行）拉。
   *  列表布局天生等距，而真实透视里纵向间距也随距离缩短，
   *  这一下位移就是补上那条线索。位移按 d² 增长，近处几乎不动、远处拉得多。
   *  下方项往上拉（负值），上方项往下拉（正值），所以带上 index - focus 的符号。 */
  corridorLiftY(index: number): number {
    const sd: number = index - this.corridorFocus;
    const d: number = Math.abs(sd);
    const far: number = d > CORRIDOR_LIFT_MAX_D ? CORRIDOR_LIFT_MAX_D : d;
    const shift: number = CORRIDOR_LIFT * far * far;
    return sd > 0 ? -shift : shift;
  }

  /** 纵向收缩会让相邻项叠在一起，绘制顺序就得让近的压住远的。
   *  少了这一步，远处的小卡片会盖在近处的大卡片上，空间关系就反了 */
  corridorZ(index: number): number {
    const d: number = this.corridorD(index);
    const far: number = d > CORRIDOR_LIFT_MAX_D ? CORRIDOR_LIFT_MAX_D : d;
    return 100 - far;
  }

  /**
   * 投影的横向偏移：卡片是立在走廊两侧墙上的，光从走廊中线来，
   * 影子就该落向远离中线的那一侧。左列往左投、右列往右投。
   * 全都朝正下方投的话，卡片会显得是从屏幕表面浮起来的，
   * 而不是立在两面墙上 —— 这是「贴墙」和「悬浮」的分界。
   */
  corridorShadowX(rowIndex: number, col: number): number {
    const d: number = this.corridorD(rowIndex);
    const far: number = d > CORRIDOR_LIFT_MAX_D ? CORRIDOR_LIFT_MAX_D : d;
    const side: number = col === 0 ? -1 : 1;
    return side * far * 3;
  }

  /** 投影的纵向偏移：焦点行那张离观察者最近、最「悬空」，影子拉得最长；
   *  越远越贴近墙面，影子收得越短 */
  corridorShadowY(index: number): number {
    const y: number = 10 - this.corridorD(index) * 1.8;
    return y > 4 ? y : 4;
  }

  /** 两侧向走廊中线内转：焦点行正对观察者，越远越侧。 */
  corridorYaw(rowIndex: number, col: number): number {
    const d: number = this.corridorD(rowIndex);
    // 两行之内就转到最大角度，再远保持，避免远处的卡片刻意扭过头
    const t: number = d > 2 ? 1 : d / 2;
    const side: number = col === 0 ? 1 : -1;
    return side * CORRIDOR_YAW * t;
  }

  /**
   * 侧转的梯形裁切。
   *
   * ArkUI 的 `.rotate()` 只会让卡片「整体变窄」（效果等价于 scaleX），
   * 真正的透视梯形要靠 `RotateOptions.perspective`，而它在实机上不产生
   * 任何梯形 —— 已实测确认。2D 仿射变换在数学上也变不出梯形（矩形只会
   * 变成平行四边形），所以只能自己裁：近端保持原高、远端缩进，
   * 形状对了才读得出「转过去」，而不只是「变窄了」。
   *
   * 近端 = 靠中线的那一侧，它离观察者更近，投影更高。
   */
  corridorClip(item: MediaItem, rowIndex: number, col: number): PathShape {
    const ctx = this.getUIContext();
    const w: number = ctx.vp2px(CORRIDOR_CARD_H * this.corridorRatio(item));
    const h: number = ctx.vp2px(CORRIDOR_CARD_H);
    // 缩进量跟着侧转角的正弦走：转得越多，远端被压得越扁
    const rad: number = Math.abs(this.corridorYaw(rowIndex, col)) * Math.PI / 180;
    const inset: number = w * Math.sin(rad) * CORRIDOR_TAPER;
    // 圆角半径：不能超过短边的一半，否则切点会跑到边外面去
    const maxR: number = Math.min(w, h - 2 * inset) / 2;
    let rFar: number = ctx.vp2px(CORRIDOR_CLIP_R);
    if (rFar > maxR) {
      rFar = maxR;
    }
    // 近端（贴墙、保持原高不缩进的那一侧）的两个角用直角 —— 那条边压在墙上，
    // 直角才「硬」，才像贴住；只有朝走廊中心那一侧的远端做圆角。
    //
    // 注意近端角「恒为 A、D」，不要按 col 再分一次：未镜像的坐标里 A、D 在左边，
    // 而左边正是高的那侧；右列会把整张图水平镜像，这两个角自然跟着跑到右边。
    // 若这里再按 col 交换一次，就会和镜像叠加、把直角翻回错误的一侧。
    const nearIsLeft: boolean = col === 0;

    // 八个切点：每个角取相邻两边上距顶点该角半径的位置，
    // 中间用 Q 命令（控制点就是顶点本身）画弧 —— 半径 0 时它退化成直线，即直角。
    // 斜边 AB 的单位向量，用来算它在斜边上的切点
    const len: number = Math.sqrt(w * w + inset * inset);
    const ux: number = len > 0 ? w / len : 1;
    const uy: number = len > 0 ? inset / len : 0;

    const p: number[][] = [
      [0, 0],                                       // A 出射（近端角，直角）
      [w - ux * rFar, inset - uy * rFar],           // B 入射
      [w, inset + rFar],                            // B 出射
      [w, h - inset - rFar],                        // C 入射
      [w - ux * rFar, h - inset + uy * rFar],       // C 出射
      [0, h],                                       // D 入射（近端角，直角）
      [0, h],                                       // D 出射
      [0, 0]                                        // A 入射
    ];
    const corners: number[][] = [
      [w, inset],            // B
      [w, h - inset],        // C
      [0, h],                // D
      [0, 0]                 // A
    ];
    // 近端在右时整体水平镜像
    const fx = (x: number): string => (nearIsLeft ? x : w - x).toFixed(1);
    let cmd: string = 'M' + fx(p[0][0]) + ',' + p[0][1].toFixed(1);
    for (let i = 0; i < 4; i++) {
      const nxt: number[] = p[(i * 2 + 1) % 8];
      const out: number[] = p[(i * 2 + 2) % 8];
      const c: number[] = corners[i];
      cmd = cmd + ' L' + fx(nxt[0]) + ',' + nxt[1].toFixed(1) +
        ' Q' + fx(c[0]) + ',' + c[1].toFixed(1) + ' ' + fx(out[0]) + ',' + out[1].toFixed(1);
    }
    cmd = cmd + ' Z';
    // PathShape 不吃 width/height（官方文档明确：path 形状不支持设尺寸），
    // 只接 commands，坐标一律 px
    return new PathShape({ commands: cmd });
  }

  /** 走廊里的卡片宽高比：在真实比例基础上只裁掉极端值。
   *  不这样做的话，一张 3:4 竖图会把卡片撑到半屏高，一屏只剩两层，
   *  「近大远小」的链条就断了 —— 而那正是长廊的全部效果来源 */
  corridorRatio(item: MediaItem): number {
    let r: number = this.mediaRatio(item);
    if (r < CORRIDOR_RATIO_MIN) {
      r = CORRIDOR_RATIO_MIN;
    }
    if (r > CORRIDOR_RATIO_MAX) {
      r = CORRIDOR_RATIO_MAX;
    }
    return r;
  }

  /**
   * 向中线收拢的距离。
   *
   * 卡片是「外边缘对齐」摆的（左列的左边缘、右列的右边缘各自贴在一条起跑线上），
   * 所以整列本来就是齐的 —— 不同宽度的图片只让靠中线那一侧参差，看起来是
   * 一排挂在同一条墙线上的画框，而不是一堆随手撒开的方块。
   *
   * 收拢只作用在整列上：越远整列越靠中线，且左列向右、右列向左，
   * 所以同一列里的卡片永远保持对齐，不会各走各的。
   */
  corridorShift(rowIndex: number, col: number): number {
    const d: number = this.corridorD(rowIndex);
    const far: number = d > CORRIDOR_LIFT_MAX_D ? CORRIDOR_LIFT_MAX_D : d;
    const base: number = col === 0 ? 1 : -1;
    return base * CORRIDOR_COLLAPSE * (far / CORRIDOR_LIFT_MAX_D);
  }

  /** 大气透视：越远越淡，避免远处的小卡片和近处一样实 */
  corridorOpacity(index: number): number {
    const o: number = 1 - this.corridorD(index) * 0.08;
    return o > 0.42 ? o : 0.42;
  }

  /** 越远投影越短，否则远处小卡片会顶着一团大盘子影 */
  corridorShadowRadius(index: number): number {
    const r: number = 22 - this.corridorD(index) * 4;
    return r > 6 ? r : 6;
  }

  /**
   * 投影的浓度：越远越淡。
   *
   * radius 和 offset 都已经随距离收了，但 color 一直是固定的 ——
   * 结果是远处那张巴掌大的小卡片，底下压着一团和近处一样重的黑影，
   * 大气透视在这里断了。shadow.color 接受字符串，所以能直接算 alpha。
   */
  corridorShadowColor(index: number): string {
    let a: number = 0.42 - this.corridorD(index) * 0.075;
    if (a < 0.12) {
      a = 0.12;
    }
    return 'rgba(0, 0, 0, ' + a.toFixed(2) + ')';
  }

  /**
   * 一行：左右两张并排，各贴自己那一侧的外边缘。
   *
   * 中间用 Blank 吃掉剩余空间 —— 两张卡宽度不同（各自跟着图片比例走），
   * 中间的空隙就自然不同；但两侧的外边缘始终固定在起跑线上，整面墙是齐的。
   * 奇数张时最后一行只有左边一张，右侧留空。
   */
  @Builder
  corridorRow(row: MediaItem[], rowIndex: number) {
    Row() {
      if (row.length > 0) {
        this.corridorCard(row[0], rowIndex, 0);
      }
      Blank()
      if (row.length > 1) {
        this.corridorCard(row[1], rowIndex, 1);
      }
    }
    .width('100%')
    .padding({ left: CORRIDOR_WALL, right: CORRIDOR_WALL })
  }

  /** 一行里的一张卡。col：0 = 左列，1 = 右列 —— 朝向、投影方向、梯形方向都由它定 */
  @Builder
  corridorCard(item: MediaItem, rowIndex: number, col: number) {
    Stack({ alignContent: Alignment.Center }) {
      mediaFill(item);
      // 受光面：卡片朝向中线的那一侧受光、背侧落暗。
      // 平面卡片绕 Y 轴转出来的轮廓和「横向压缩」长得一样，光靠 rotate 分不出
      // 「转过去了」还是「变窄了」；这层明暗才是「立着」的凭据。
      // 强度必须够 —— 15% 的差值在深色照片上会被完全吃掉，要 30% 才读得出来。
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          // 左列朝右转 → 右侧受光；右列朝左转 → 左侧受光
          angle: col === 0 ? 270 : 90,
          colors: [
            ['#4DFFFFFF', 0],
            ['#00000000', 0.42],
            ['#40000000', 1]
          ]
        })
      // 侧面厚度：背离中线那一侧的暗边。画框是有厚度的，
      // 这条边是「卡片立在墙上」最直白的那个信号 —— 它同时交代了朝向和实体感
      Row() {
        Column()
          .width(col === 0 ? CORRIDOR_SIDE_W : 0)
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [['#73000000', 0], ['#B3000000', 1]]
          })
        Blank()
        Column()
          .width(col === 0 ? 0 : CORRIDOR_SIDE_W)
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [['#B3000000', 0], ['#73000000', 1]]
          })
      }
      .width('100%')
      .height('100%')
    }
    // 固定高度、宽度由比例推出：竖图会窄、横图会宽，错落得像墙上尺寸不一的画框。
    // 关键是高度受控 —— 一屏能看到约五行，「近大远小」才有链条可言
    .height(CORRIDOR_CARD_H)
    .aspectRatio(this.corridorRatio(item))
    // 裁成梯形 + 圆角：近端高、远端矮。这是「侧转」唯一可靠的来源 ——
    // rotate 只给「变窄」，perspective 在实机上不出梯形。
    .clipShape(this.corridorClip(item, rowIndex, col))
    .shadow({
      radius: this.corridorShadowRadius(rowIndex),
      // 浓度也随距离衰减，让大气透视贯穿到底
      color: this.corridorShadowColor(rowIndex),
      // 影子朝远离中线的一侧投、越远越贴墙 —— 「立着」还是「浮着」就看这两项
      offsetX: this.corridorShadowX(rowIndex, col),
      offsetY: this.corridorShadowY(rowIndex)
    })
    // 横向和纵向分开缩放：纵向衰减更快，远处那张会被压扁，出现「缩短」
    .scale({ x: this.corridorScaleX(rowIndex), y: this.corridorScaleY(rowIndex) })
    // 侧转：只保留角度。perspective 在这个环境下不产生梯形（已实测），
    // 留着它只会让人以为透视是靠这里做出来的；梯形改由上面的 clipShape 负责
    .rotate({ x: 0, y: 1, z: 0, angle: this.corridorYaw(rowIndex, col) })
    // x 是向中线收拢，y 是纵向收缩（补上「近疏远密」那条线索）
    .translate({ x: this.corridorShift(rowIndex, col), y: this.corridorLiftY(rowIndex) })
    .opacity(this.corridorOpacity(rowIndex))
    // 纵向收缩会让相邻项叠起来，绘制顺序必须让近的压住远的
    .zIndex(this.corridorZ(rowIndex))
    .onClick(() => {
      // 对外仍然是「第几张」的全局索引
      this.onCardTap(rowIndex * 2 + col);
    })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.onLongPress(item.id);
    }))
  }

  // ---------- ③ 旋转展台：中央放大，两侧后仰 ----------

  @Builder
  carouselLayout() {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper(this.carouselSwiper) {
        LazyForEach(this.ds, (item: MediaItem, index: number) => {
          this.carouselCard(item, index);
        }, (item: MediaItem) => item.id)
      }
      // 刻意不挂 .index()：它是声明式双向绑定，carouselIndex 一变就会要求 Swiper
      // 重新定位。循环回绕的那一刻（索引从最后一张变回首张）Swiper 自己的循环位移
      // 正做到一半，被这次无动画的重定位打断 —— 就是那下「突然跳动画」。
      // 索引改为单向：只由 onChange 从 Swiper 读出来，不再回写。
      // 环形：滑到最后一张继续滑会回到首张，甩多张也能一直转下去
      .loop(true)
      .indicator(false)
      .autoPlay(false)
      .displayCount(1)
      .prevMargin(CAROUSEL_MARGIN)
      .nextMargin(CAROUSEL_MARGIN)
      .itemSpace(14)
      .width('100%')
      .height('100%')
      // 缩短切换时长让跟手感更好（默认 400 偏慢）
      .duration(240)
      // 循环回绕需要多个槽位同时在场：当前项 + 左右相邻项（两侧靠 prevMargin /
      // nextMargin 露出来）。loop(true) 时实际渲染数 = cachedCount + 1，
      // 只给 2 个槽位时，滑到边界要同时往两个方向备货就补不上，内容会瞬移。
      // 展台卡片本身节点偏重（主图 + 镜像倒影 + 渐隐层 + 3D 变换），
      // 现场创建赶不上，所以这里给到能覆盖一次甩动（CAROUSEL_FLING_MAX）的跨度。
      .cachedCount(4)
      // 手指状态是这里唯一的动效开关：开始拖动即后仰，抬起即回正。
      // 用 onTouch 而不是 onGestureSwipe，是因为只有它能拿到「抬起」的那一刻；
      // 而且它整个拖动过程只在首尾各改一次状态，中间不产生任何属性变化，
      // 3D 变换不会被逐帧重算 —— 之前那份每帧重算的开销就是顿挫的来源。
      // 只认 Move 不认 Down：单纯点一下卡片（进详情）不该触发后仰。
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.touchTracking = false;
          // 新手势打断上一次还没走完的甩动，避免两张接不上
          this.flingRemain = 0;
        } else if (event.type === TouchType.Move) {
          // 只记录位置和时间，不触发任何 UI 刷新
          if (event.touches.length > 0) {
            const x: number = event.touches[0].x;
            const now: number = Date.now();
            if (!this.touchTracking) {
              this.touchTracking = true;
              this.touchStartX = x;
              this.touchStartMs = now;
              this.touchMinX = x;
              this.touchMaxX = x;
            }
            if (x < this.touchMinX) {
              this.touchMinX = x;
            }
            if (x > this.touchMaxX) {
              this.touchMaxX = x;
            }
            this.touchLastMs = now;
          }
          if (!this.carouselDragging) {
            this.carouselDragging = true;
          }
        } else if (event.type === TouchType.Up) {
          this.carouselDragging = false;
          // 抬起瞬间按甩动速度决定是否一次翻多张
          this.flingCarousel();
        } else if (event.type === TouchType.Cancel) {
          this.carouselDragging = false;
          this.touchTracking = false;
        }
      })
      .onChange((index: number) => {
        // 停稳：只更新基准索引（决定「中心大、两侧小」的层次），不再维护滚动进度。
        // 取模是为了不依赖 Swiper 在环形模式下回传的是真实索引还是累加的虚拟索引，
        // 两者都能规范到 [0, cnt)，计数显示也不会越界。
        const cnt: number = this.items.length;
        this.carouselIndex = cnt > 0 ? index % cnt : 0;
        this.carouselDragging = false;
        // 甩动的后续张数在这里逐张兑现：每次停稳走一步，直到走完
        this.advanceFling();
      })

      Text((this.carouselIndex + 1).toString() + ' / ' + this.items.length.toString())
        .fontSize(13)
        .fontColor($r('app.color.c_text3'))
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .backgroundColor($r('app.color.c_chip'))
        .borderRadius(12)
        .margin({ bottom: this.navBlock + 10 })
    }
    .width('100%')
    .height('100%')
    .translate({ x: exitShiftX(this.contentPhase, 0), y: enterShiftY(this.contentPhase, 0) })
    .opacity(phaseOpacity(this.contentPhase))
    .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
    .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseInOut }))
  }

  // 展台卡片的变换只依赖两个「离散」输入，它们在拖动过程中都不变：
  //   · carouselIndex     —— 换页停稳后才变一次，负责「中心大、两侧小」的层次
  //   · carouselDragging  —— 手指按下/抬起各变一次，负责「整体后仰、松手回正」
  // 拖动中间没有任何属性参与计算，所以拖动是零变换开销的。

  /** 手指按住时整体收一点；静止时中心项最大，两侧项略小 */
  carouselScale(index: number): number {
    if (this.carouselDragging) {
      return CAROUSEL_DRAG_SCALE;
    }
    return this.carouselDelta(index) === 0 ? 1 : CAROUSEL_SIDE_SCALE;
  }

  /**
   * 某一项相对基准项的带符号距离，折算到环形上的最短路径。
   * loop 模式下首尾是相邻的：carouselIndex 为 0 时，左边那张的原始索引是
   * length-1，直接用 index - carouselIndex 会得到一个大正数，被当成「右边很远
   * 的那张」，倾斜方向就反了。这里把所有索引差折算进 (-cnt/2, cnt/2]。
   */
  carouselDelta(index: number): number {
    const cnt: number = this.items.length;
    if (cnt <= 0) {
      return 0;
    }
    // 索引不再回写 Swiper，两者可能因为删除/筛选导致列表变短而错开，
    // 先把基准折算回有效范围，层次判断才不会整体偏掉
    const base: number = ((this.carouselIndex % cnt) + cnt) % cnt;
    let d: number = (index - base) % cnt;
    if (d < 0) {
      d += cnt;
    }
    // d * 2 > cnt 等价于 d > cnt / 2，避免引入浮点比较
    if (d * 2 > cnt) {
      d -= cnt;
    }
    return d;
  }

  /** 手指按住时整体后仰到同一角度；静止时两侧项向各自外侧倾斜 */
  carouselRotate(index: number): number {
    if (this.carouselDragging) {
      return CAROUSEL_DRAG_ROTATE;
    }
    const d: number = this.carouselDelta(index);
    if (d === 0) {
      return 0;
    }
    return d < 0 ? CAROUSEL_SIDE_ROTATE : -CAROUSEL_SIDE_ROTATE;
  }

  /**
   * 甩动翻页：Swiper 自己的吸附只会停在相邻一张，这里在手指抬起的那一刻
   * 按甩动速度算出「还要再走几张」，剩下的交给 advanceFling 逐张兑现。
   * 速度不够快就什么都不做，完全交给 Swiper 原本的吸附。
   */
  flingCarousel() {
    if (!this.touchTracking || this.items.length < 2) {
      return;
    }
    this.touchTracking = false;
    const dt: number = this.touchLastMs - this.touchStartMs;
    // 采样窗口太短时速度会严重失真：几毫秒配上几 vp 就能算出很高的速度，
    // 而且这种手势里位移方向本身就不可靠。
    if (dt < CAROUSEL_FLING_MIN_MS) {
      return;
    }
    // 方向取「起点分别往左右伸出的最大幅度」里更大的那一边。
    // 不能用「末点 - 起点」：抬手前手指往往会自然回摆一下，
    // 那一下足以把符号带反 —— 于是往左滑却往右翻。
    const toLeft: number = this.touchStartX - this.touchMinX;
    const toRight: number = this.touchMaxX - this.touchStartX;
    const span: number = toLeft > toRight ? toLeft : toRight;
    if (span < CAROUSEL_FLING_MIN_DX) {
      return;
    }
    const v: number = span / dt;
    if (v < CAROUSEL_FLING_V) {
      return;
    }
    let n: number = 1 + Math.floor((v - CAROUSEL_FLING_V) / CAROUSEL_FLING_STEP);
    if (n > CAROUSEL_FLING_MAX) {
      n = CAROUSEL_FLING_MAX;
    }
    // 往左侧伸出得更多，说明手指整体是往左走的；往左滑是往后翻。
    const dir: number = toLeft > toRight ? 1 : -1;
    // Swiper 自己的吸附已经会带走一张，这里只记「还要再走几张」。
    // 不能用 changeIndex 一次跳到位：它按绝对索引定位，而 loop 模式下 Swiper
    // 内部是连续位置，两者对不上时它会朝反方向绕过去 —— 那正是「方向偶尔反」。
    this.flingRemain = dir * (n - 1);
  }

  /**
   * 甩动的后续推进：每停稳一张就走一步，走完为止。
   * 走的是 showNext / showPrevious 这类相对接口，方向由「前进/后退」本身决定，
   * 不依赖任何索引算术，所以环形首尾相接处也不会绕反。
   */
  advanceFling() {
    if (this.flingRemain === 0) {
      return;
    }
    if (this.flingRemain > 0) {
      this.flingRemain--;
      this.carouselSwiper.showNext();
    } else {
      this.flingRemain++;
      this.carouselSwiper.showPrevious();
    }
  }

  /** 主图的真实宽高比（宽/高）；无数据时按 3:4 兜底。走廊和展台共用 */
  mediaRatio(item: MediaItem): number {
    if (item.width > 0 && item.height > 0) {
      let r: number = item.width / item.height;
      if (r < 0.4) {
        r = 0.4;
      }
      if (r > 2.2) {
        r = 2.2;
      }
      return r;
    }
    return 0.75;
  }

  @Builder
  carouselCard(item: MediaItem, index: number) {
    Column() {
      // 上方弹性占位（1 份）：把主图从屏幕底往上抬，留出呼吸空间
      Column()
        .width('100%')
        .layoutWeight(1)

      // 主图：按真实宽高比，不裁切
      Stack({ alignContent: Alignment.Center }) {
        mediaFill(item);
      }
      .width('100%')
      .aspectRatio(this.mediaRatio(item))
      .borderRadius(16)
      .clip(true)
      // 阴影半径收小：三张卡片同时在屏，大半径阴影的重绘开销很可观
      .shadow({ radius: 16, color: $r('app.color.c_shadow'), offsetX: 0, offsetY: 8 })

      // 镜像倒影：与主图等宽的上下镜像，向下渐隐融进页面底色。
      // 始终显示、不做任何显隐切换 —— 显隐（无论 if 还是 opacity）都会在换页时
      // 引入一次额外的状态变更，之前那一下停顿就出在这里。
      Stack({ alignContent: Alignment.Top }) {
        Stack({ alignContent: Alignment.Center }) {
          mediaFill(item);
        }
        .width('100%')
        .height('100%')
        .borderRadius(16)
        .clip(true)
        .scale({ y: -1 })

        // 向下渐隐：越靠近底部越淡，最后融进页面底色
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [
              [$r('app.color.c_bg0'), 0],
              [$r('app.color.c_bg0'), 0.1],
              [$r('app.color.c_bg'), 0.75],
              [$r('app.color.c_bg'), 1]
            ]
          })
      }
      .width('100%')
      // 固定高度，不随卡片剩余空间拉长。横屏屏高只有 ~360vp，
      // 倒影还占 140 会把主图压没，一并收窄
      .height(this.isLandscape ? CAROUSEL_REFLECT_H * 0.5 : CAROUSEL_REFLECT_H)
      .margin({ top: CAROUSEL_REFLECT_GAP })

      // 下方弹性占位（2 份）：与顶部配合把主图放在偏上的位置
      Column()
        .width('100%')
        .layoutWeight(2)
    }
    .width('100%')
    .height('100%')
    .scale({ x: this.carouselScale(index), y: this.carouselScale(index) })
    .rotate({ x: 0, y: 1, z: 0, angle: this.carouselRotate(index) })
    // 过渡只服务于「按下 / 抬起」这一次状态切换；拖动过程不产生属性变化，
    // 所以这里不会像以前那样给跟手引入延迟。
    .animation({ duration: 200, curve: Curve.Friction })
    .onClick(() => {
      this.onCardTap(index);
    })
  }

  // ---------- ④ 时间轴：竖直轴线，照片左右交错 ----------

  @Builder
  timelineLayout() {
    List({ space: 10 }) {
      ForEach(this.timeline, (entry: TimelineEntry, i: number) => {
        ListItem() {
          this.timelineRow(entry);
        }
        .translate({ x: exitShiftX(this.contentPhase, i), y: enterShiftY(this.contentPhase, i) })
        .opacity(phaseOpacity(this.contentPhase))
        .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
      }, (entry: TimelineEntry) => entry.kind === 0
        ? ('h_' + entry.title)
        : ('i_' + entry.index.toString() + '_' + entry.side.toString()))
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, bottom: this.contentPad })
    .scrollBar(BarState.Off)
    .onScrollIndex((first: number) => {
      this.onScroll(first);
    })
    .contentStartOffset(this.headerHeight)
    .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseInOut }))
  }

  @Builder
  timelineRow(entry: TimelineEntry) {
    if (entry.kind === 0) {
      this.timelineHeader(entry.title);
    } else {
      this.timelinePhotoRow(entry.index, entry.side);
    }
  }

  @Builder
  timelineHeader(title: string) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.c_text2b'))
        .padding({ left: 11, right: 11, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.c_chip'))
        .borderRadius(12)
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  timelinePhotoRow(index: number, side: number) {
    Row() {
      Stack() {
        if (side === 0) {
          this.timelineCard(index);
        }
      }
      .layoutWeight(1)
      .height('100%')

      // 轴线
      Column() {
        Column()
          .width(1)
          .height('100%')
          .backgroundColor($r('app.color.c_axis'))
      }
      .width(26)
      .height('100%')
      .alignItems(HorizontalAlign.Center)

      Stack() {
        if (side === 1) {
          this.timelineCard(index);
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height(112)
    .alignItems(VerticalAlign.Center)
  }

  /** 用下标从 items 取数据，避免把对象传进 @Builder */
  @Builder
  timelineCard(index: number) {
    if (index >= 0 && index < this.items.length) {
      Stack({ alignContent: Alignment.Center }) {
        mediaFill(this.items[index]);
      }
      .width('100%')
      .aspectRatio(1.3)
      .borderRadius(12)
      .clip(true)
      .shadow({ radius: 16, color: $r('app.color.c_shadow'), offsetX: 0, offsetY: 8 })
      .onClick(() => {
        this.onCardTap(index);
      })
      .gesture(LongPressGesture({ repeat: false }).onAction(() => {
        this.onLongPress(this.items[index].id);
      }))
    }
  }
}
