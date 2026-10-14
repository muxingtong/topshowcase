import { curves } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import {
  LAYOUT_GRID,
  LAYOUT_WATERFALL,
  LAYOUT_SHOWCASE,
  LAYOUT_LIST,
  LAYOUT_WALL,
  LAYOUT_CORRIDOR,
  LAYOUT_CAROUSEL,
  LAYOUT_TIMELINE,
  LAYOUT_COUNT,
  FILTER_ALL,
  FILTER_IMAGE,
  FILTER_VIDEO,
  NAV_COMBO,
  NAV_H,
  NAV_GAP,
  NAV_SIDE,
  NAV_MARGIN
} from '../common/Constants';

/**
 * 底部沉浸式胶囊导航。
 * 三块 HDS 沉浸光感材质背板只负责渲染，内容全部自绘叠在上层：
 * 左胶囊点击循环排布 / 长按弹菜单，中胶囊是液态指示器（可拖动），右胶囊导入。
 */
@Component
export struct BottomNav {
  @Prop layoutMode: number;
  @Prop filterMode: number;
  @Prop safeBottom: number;
  @Prop importing: boolean;
  /** 横屏：三块胶囊不再两端对齐，改为居中等距排开 */
  @Prop isLandscape: boolean = false;
  /** 横屏：刘海在侧边，导航整体要避开 */
  @Prop safeSide: number = 0;

  onSwitchLayout: (mode: number) => void = () => {};
  onFilterChange: (mode: number) => void = () => {};
  onImport: () => void = () => {};

  /** 中胶囊轨道宽度（用于计算滑动指示块位置，由 onAreaChange 测得） */
  @State filterTrackW: number = 0;
  /** 排布菜单是否展开 */
  @State layoutMenuShown: boolean = false;
  /** 液态指示器：拖动偏移量 / 是否跟手 / 速度形变量 */
  @State pillOffsetX: number = 0;
  @State pillStretching: boolean = false;
  @State pillDeform: number = 0;
  private lastPanX: number = 0;
  private smoothedVel: number = 0;
  // HDS 页签控制器：只用来承载沉浸光感材质背板
  private midTabController: HdsTabsController = new HdsTabsController();
  private leftTabController: HdsTabsController = new HdsTabsController();
  private rightTabController: HdsTabsController = new HdsTabsController();

  /** 导航胶囊底边距（避开手势条） */
  navBottomMargin(): number {
    return NAV_MARGIN + this.safeBottom;
  }

  build() {
    this.bottomNavLayer();
  }


  // 底部导航：三块沉浸光感材质背板（左右单页签 + 中间四页签），内容自绘叠在上层
  @Builder
  bottomNavLayer() {
    Stack({ alignContent: Alignment.Bottom }) {
      // ① 左右胶囊材质
      this.sideTabBacking(true)
      this.sideTabBacking(false)

      // ② 中胶囊材质：悬浮页签栏，宽度与自绘中胶囊一致
      HdsTabs({ controller: this.midTabController }) {
        TabContent() {
        }.tabBar(this.emptyTabSlot())
        TabContent() {
        }.tabBar(this.emptyTabSlot())
        TabContent() {
        }.tabBar(this.emptyTabSlot())
        TabContent() {
        }.tabBar(this.emptyTabSlot())
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barHeight(NAV_H)
      .barFloatingStyle({
        barWidth: { smallWidth: this.navBarWidth(), mediumWidth: this.navBarWidth(), largeWidth: this.navBarWidth() },
        barBottomMargin: this.navBottomMargin(),
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onChange((index: number) => {
        this.onFilterChange(index);
      })
      .width('100%')
      .height('100%')
      // 材质背板纯装饰：完全不参与命中测试，避免挡住内容区的点击
      .hitTestBehavior(HitTestMode.None)

      // ③ 自绘内容层：左右胶囊文字 + 中胶囊液态指示块与选项
      this.navRow()
    }
    .width('100%')
    .height(NAV_H + this.navBottomMargin())
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  navRow() {
    Row({ space: this.isLandscape ? NAV_GAP + 12 : NAV_GAP }) {
      // 背板材质由对应的 HdsTabs 提供，此处只放内容
      // 点击循环切换；长按弹出全部排布菜单（上滑会与中胶囊拖动、列表滚动抢手势，故只用长按）
      Text(this.layoutName())
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.c_text'))
        .width(NAV_SIDE)
        .height(NAV_H)
        .textAlign(TextAlign.Center)
        // 长按期间轻微内缩，给出"按住了"的反馈
        .scale({ x: this.layoutMenuShown ? 0.9 : 1, y: this.layoutMenuShown ? 0.9 : 1 })
        .animation({ duration: 160, curve: Curve.EaseOut })
        .onClick(() => {
          this.cycleLayout();
        })
        .bindContextMenu(this.layoutMenuShown, this.layoutMenuContent(), {
          placement: Placement.Top,
          enableArrow: false,
          offset: { x: 0, y: -6 },
          onDisappear: () => {
            this.layoutMenuShown = false;
          },
          // 菜单从胶囊位置轻微放大淡入
          transition: TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
            .combine(TransitionEffect.scale({ x: 0.86, y: 0.86 }).animation({ duration: 180, curve: Curve.EaseOut }))
        })
        .gesture(LongPressGesture({ repeat: false, duration: 420 })
          .onAction(() => {
            this.layoutMenuShown = true;
          }))

      this.midCapsule()

      Column() {
        Text('＋')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.c_chip_active'))
      }
      .width(NAV_SIDE)
      .height(NAV_H)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .opacity(this.importing ? 0.5 : 1)
      .onClick(() => {
        this.onImport();
      })
    }
    .width('100%')
    .padding({ left: 16 + this.safeSide, right: 16 + this.safeSide, bottom: this.navBottomMargin() })
    // 居中：竖屏下三块本来就撑满屏宽，居中无副作用；横屏下屏宽翻倍，
    // 若仍两端对齐，左右胶囊会被甩到屏幕两头，中间空出一大片
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 中胶囊：展品 / 图片 / 视频 / 组合（液态指示器，背板材质来自 HdsTabs 悬浮页签栏）
  @Builder
  midCapsule() {
    Stack() {
      // 液态指示块：拖动跟手（duration 0），松手弹簧吸附
      Column()
        .width(this.pillW())
        .height(this.pillH())
        .borderRadius(this.pillH() / 2)
        .backgroundColor($r('app.color.c_chip_active'))
        .border({ width: 1, color: '#33FFFFFF' })
        .shadow({ radius: 18, color: $r('app.color.c_glow'), offsetX: 0, offsetY: 4 })
        .position({ x: this.segPillX(this.filterMode, 4, this.filterTrackW) + this.pillOffsetX, y: this.pillY() })
        .animation({ duration: this.pillStretching ? 0 : 260, curve: curves.springMotion() })
      Row() {
        this.midSegItem('展品', FILTER_ALL)
        this.midSegItem('图片', FILTER_IMAGE)
        this.midSegItem('视频', FILTER_VIDEO)
        this.midSegItem('组合', NAV_COMBO)
      }
      .width('100%')
      .height('100%')
    }
    .layoutWeight(1)
    .height(NAV_H)
    // 背板材质由 HdsTabs 的悬浮页签栏提供，此处只保留液态指示器与可拖动热区
    .clip(false)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w = newArea.width;
      if (typeof w === 'number') {
        this.filterTrackW = w;
      }
    })
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal })
        .onActionStart(() => {
          this.pillStretching = true;
          this.lastPanX = 0;
          this.smoothedVel = 0;
          this.pillDeform = 0;
        })
        .onActionUpdate((event: GestureEvent) => {
          this.onPillPanUpdate(event.offsetX);
        })
        .onActionEnd(() => {
          this.onPillPanEnd();
        })
        .onActionCancel(() => {
          this.onPillPanEnd();
        })
    )
  }

  // 选中态必须在这里读 this.filterMode
  @Builder
  midSegItem(label: string, mode: number) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(this.filterMode === mode ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.filterMode === mode ? $r('app.color.c_chip_active_text') : $r('app.color.c_text2b'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onFilterChange(mode);
    })
  }

  // 页签槽位留空：材质背板由 HdsTabs 渲染，内容全部由上层自绘
  @Builder
  emptyTabSlot() {
    Column()
      .width('100%')
      .height('100%')
  }

  // 左右胶囊的沉浸光感材质背板：单页签 HdsTabs，平移到自绘胶囊正下方
  @Builder
  sideTabBacking(left: boolean) {
    HdsTabs({ controller: left ? this.leftTabController : this.rightTabController }) {
      TabContent() {
      }.tabBar(this.emptyTabSlot())
    }
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barHeight(NAV_H)
    .barFloatingStyle({
      barWidth: { smallWidth: NAV_SIDE, mediumWidth: NAV_SIDE, largeWidth: NAV_SIDE },
      barBottomMargin: this.navBottomMargin(),
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .width('100%')
    .height('100%')
    .position({ x: this.sideBackingOffset(left), y: 0 })
    // 材质背板纯装饰：完全不参与命中测试，避免挡住内容区的点击
    .hitTestBehavior(HitTestMode.None)
  }

  // 左右胶囊材质背板的水平偏移
  // 自绘层：左右各 padding 16、胶囊宽 NAV_SIDE、间隙 NAV_GAP
  // HdsTabs 铺满屏幕且页签栏水平居中，需平移后与自绘胶囊同心
  sideBackingOffset(left: boolean): number {
    const w: number = this.filterTrackW;
    if (!(w > 0)) {
      return 0;
    }
    const screenW: number = w + NAV_SIDE * 2 + NAV_GAP * 2 + 32;
    const centerFromEdge: number = 16 + NAV_SIDE / 2;
    return left ? (centerFromEdge - screenW / 2) : (screenW / 2 - centerFromEdge);
  }

  // 中胶囊宽度（页签栏材质背板宽度，需与自绘内容层严格一致）
  navBarWidth(): number {
    const w: number = this.filterTrackW;
    return w > 0 ? w : 200;
  }

  // 液态指示块：静止时贴合插槽，拖动时随速度拉宽压扁
  pillW(): number {
    return this.segPillW(4, this.filterTrackW) + this.pillDeform;
  }

  pillH(): number {
    const h: number = 38 - this.pillDeform * 0.35;
    return h > 26 ? h : 26;
  }

  // 形变时保持竖直居中
  pillY(): number {
    return 4 + (38 - this.pillH()) / 2;
  }

  // 拖动中：跟手 + 速度形变（拉宽同时压扁，模拟液态）
  onPillPanUpdate(offsetX: number): void {
    const v: number = offsetX - this.lastPanX;
    this.lastPanX = offsetX;
    this.smoothedVel = this.smoothedVel * 0.7 + v * 0.3;
    const abs: number = Math.abs(this.smoothedVel);
    if (abs < 0.12) {
      this.pillDeform = 0;
    } else {
      const norm: number = abs / 18 > 1 ? 1 : abs / 18;
      this.pillDeform = Math.sqrt(norm) * 16;
    }
    // 首尾锚点之外只跟手 1/4，形成阻尼
    const slot: number = this.filterTrackW / 4;
    const minX: number = -slot * this.filterMode;
    const maxX: number = slot * (3 - this.filterMode);
    let x: number = offsetX;
    if (x < minX) {
      x = minX + (x - minX) * 0.25;
    }
    if (x > maxX) {
      x = maxX + (x - maxX) * 0.25;
    }
    this.pillOffsetX = x;
  }

  // 松手：按滑动格数吸附到最近锚点（不足半格回弹）
  onPillPanEnd(): void {
    const slot: number = this.filterTrackW / 4;
    let moved: number = 0;
    if (slot > 0) {
      moved = Math.round(this.pillOffsetX / slot);
    }
    let next: number = this.filterMode + moved;
    if (next < 0) {
      next = 0;
    }
    if (next > 3) {
      next = 3;
    }
    this.pillStretching = false;
    this.pillOffsetX = 0;
    this.pillDeform = 0;
    if (next !== this.filterMode) {
      this.onFilterChange(next);
    }
  }

  // 指示块位置/宽度：按整段宽度对齐，左右各内缩 4vp
  segPillX(active: number, count: number, trackW: number): number {
    if (!(trackW > 0)) {
      return 0;
    }
    return trackW / count * active + 4;
  }

  segPillW(count: number, trackW: number): number {
    if (!(trackW > 0)) {
      return 0;
    }
    const w: number = trackW / count - 8;
    return w > 0 ? w : 0;
  }

  // ---------- 底部沉浸式胶囊导航 ----------

  layoutName(): string {
    if (this.layoutMode === LAYOUT_WATERFALL) {
      return '瀑布';
    }
    if (this.layoutMode === LAYOUT_SHOWCASE) {
      return '展柜';
    }
    if (this.layoutMode === LAYOUT_LIST) {
      return '列表';
    }
    if (this.layoutMode === LAYOUT_WALL) {
      return '展厅墙';
    }
    if (this.layoutMode === LAYOUT_CORRIDOR) {
      return '长廊';
    }
    if (this.layoutMode === LAYOUT_CAROUSEL) {
      return '展台';
    }
    if (this.layoutMode === LAYOUT_TIMELINE) {
      return '时间轴';
    }
    return '网格';
  }

  // 排布菜单内容：长按左胶囊弹出，当前排布高亮
  @Builder
  layoutMenuContent() {
    Column() {
      Text('排布方式')
        .fontSize(13)
        .fontColor($r('app.color.c_text3'))
        .width('100%')
        .padding({ left: 10, bottom: 6 })

      this.layoutMenuRow('网格', LAYOUT_GRID)
      this.layoutMenuRow('瀑布', LAYOUT_WATERFALL)
      this.layoutMenuRow('展柜', LAYOUT_SHOWCASE)
      this.layoutMenuRow('列表', LAYOUT_LIST)

      Divider()
        .color($r('app.color.c_chip_border'))
        .strokeWidth(1)
        .margin({ top: 5, bottom: 5 })

      Text('画廊')
        .fontSize(13)
        .fontColor($r('app.color.c_text3'))
        .width('100%')
        .padding({ left: 10, bottom: 6 })

      this.layoutMenuRow('展厅墙', LAYOUT_WALL)
      this.layoutMenuRow('透视长廊', LAYOUT_CORRIDOR)
      this.layoutMenuRow('旋转展台', LAYOUT_CAROUSEL)
      this.layoutMenuRow('时间轴', LAYOUT_TIMELINE)
    }
    .width(176)
    .padding(8)
    .backgroundColor($r('app.color.c_card'))
    .borderRadius(16)
  }

  // 选中态必须在这里读 this.layoutMode
  @Builder
  layoutMenuRow(name: string, mode: number) {
    Row() {
      Text(name)
        .fontSize(13)
        .fontWeight(this.layoutMode === mode ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.layoutMode === mode ? $r('app.color.c_chip_active') : $r('app.color.c_text'))
        .layoutWeight(1)

      if (this.layoutMode === mode) {
        Text('✓')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.c_chip_active'))
      }
    }
    .width('100%')
    .height(38)
    .padding({ left: 10, right: 10 })
    .borderRadius(8)
    .backgroundColor(this.layoutMode === mode ? $r('app.color.c_chip') : Color.Transparent)
    .onClick(() => {
      // 先收起菜单再切换，避免菜单浮在过渡动画之上
      this.layoutMenuShown = false;
      this.onSwitchLayout(mode);
    })
  }

  // 点击左胶囊：循环切换全部排布
  cycleLayout(): void {
    this.onSwitchLayout((this.layoutMode + 1) % LAYOUT_COUNT);
  }
}
