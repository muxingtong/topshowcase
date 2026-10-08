import { MediaItem, MediaType } from '../model/MediaItem';
import { MediaDataSource } from '../model/MediaDataSource';
import { accentPill, ghostPill } from '../common/Widgets';
import { formatDate, formatSize } from '../common/Format';
import {
  DISMISS_DISTANCE,
  DISMISS_VELOCITY,
  DISMISS_MIN_SCALE,
  DISMISS_FADE_SPAN,
  DETAIL_PANEL_W
} from '../common/Constants';

/**
 * 详情页覆盖层：左右滑切换、双指缩放、双击复位、视频播放、名称/备注编辑、收藏与分组。
 * 草稿与手势状态用 @Link 与父组件共享（关闭时需要复位），动作通过同名回调上报。
 */
@Component
export struct DetailView {
  @Link items: MediaItem[];
  @Link selectedIndex: number;
  /** 信息卡片读取的索引：滑动一开始就更新，不必等切换动画播完 */
  @Link detailIndex: number;
  @Link nameDraft: string;
  @Link remarkDraft: string;
  @Link editingName: boolean;
  @Link remarkEditing: boolean;
  @Link detailFavorite: boolean;
  /** 缩放与位移（父组件关闭详情时要复位） */
  @Link scaleValue: number;
  @Link offsetX: number;
  @Link offsetY: number;

  /** 列表数据源（详情分页用） */
  ds: MediaDataSource = new MediaDataSource();
  /** 视频控制器（父组件在切页/关闭时负责 stop） */
  videoController: VideoController = new VideoController();

  @Prop safeTop: number;
  @Prop safeBottom: number;
  /** 横屏：图片与信息面板左右并排，把横向空间用满 */
  @Prop isLandscape: boolean = false;
  /** 横屏：刘海在侧边，整页要避开 */
  @Prop safeSide: number = 0;

  // 回调成员沿用父组件方法名
  closeDetail: () => void = () => {};
  onDetailPageChange: (index: number) => void = () => {};
  saveName: () => void = () => {};
  saveRemark: () => void = () => {};
  toggleDetailFavorite: () => void = () => {};
  onDeleteSingle: () => void = () => {};
  onShareItem: () => void = () => {};
  openGroupEditor: () => void = () => {};
  resetZoom: () => void = () => {};

  /** 手势基准值：只在详情页内部使用 */
  private baseScale: number = 1;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;
  private detailSwiper: SwiperController = new SwiperController();

  /**
   * Swiper 实际使用的索引，**只在有效时跟随 selectedIndex**。
   *
   * 关闭详情时父组件把 selectedIndex 置成 -1，而 Swiper 的 `.index(-1)`
   * 会被当成默认值 0 —— 它会先跳到第一张，再通过 onChange 把 selectedIndex
   * 改回 0，于是详情页「复活」并停在第一张，要再返回一次才关得掉。
   * 留住最后一个有效索引就没这回事了。
   */
  @State swiperIndex: number = 0;

  // ---------- 下滑退出 ----------
  /** 实时下拉位移（vp）。整页跟着手指走，松手时决定关闭还是回弹 */
  @State dismissOffset: number = 0;
  /** 详情可视区尺寸：缩放态要算图片边界，才知道「拖到顶了没有」 */
  @State viewW: number = 0;
  @State viewH: number = 0;
  /** 本次拖动是否已经进入「退出模式」：缩放态下拖到顶之后才会置真 */
  private dismissArmed: boolean = false;
  /** 松手瞬间的垂直速度（vp/s），用来判断「甩出去」 */
  private lastPanY: number = 0;
  private lastPanTime: number = 0;
  private panVelocity: number = 0;

  build() {
    this.detailOverlay();
  }

  aboutToAppear(): void {
    if (this.selectedIndex >= 0) {
      this.swiperIndex = this.selectedIndex;
    }
  }


  @Builder
  detailOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 沉浸式底色：延伸到状态栏 / 导航栏之下，控件仍保持在安全区内（跟随深浅色）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.c_bg'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
      Row({ space: 12 }) {
        Text(this.nameDraft)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.c_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text('关闭')
          .fontSize(13)
          .fontColor($r('app.color.c_text2b'))
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.d_pill'))
          .borderRadius(15)
          .onClick(() => {
            this.closeDetail();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)

      // 横屏：图片与信息面板左右并排 —— 横屏屏高只有 ~360vp，
      // 上下堆叠会把图片压成一条，横向空间却白白空着
      if (this.isLandscape) {
        Row() {
          this.detailPager()
          this.detailPanel()
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      } else {
        this.detailPager()
        this.detailPanel()
      }
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.safeTop,
        bottom: this.safeBottom,
        left: this.safeSide,
        right: this.safeSide
      })
    }
    .width('100%')
    .height('100%')
    // 下滑退出：整页跟手，越往下越淡、越小 —— 像被「丢回去」。
    // translate 只用实时位移，不加 .animation()，否则拖动会有跟手延迟；
    // 回弹的过渡由 settleDismiss() 里的 animateTo 负责
    .translate({ y: this.dismissOffset })
    .scale({ x: this.dismissScale(), y: this.dismissScale() })
    .opacity(this.dismissOpacity())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w = newArea.width;
      const h = newArea.height;
      if (typeof w === 'number' && w > 0) {
        this.viewW = w;
      }
      if (typeof h === 'number' && h > 0) {
        this.viewH = h;
      }
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseInOut })
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation({ duration: 240, curve: Curve.EaseInOut })))
  }

  /** 退出过程中的缩放：往下拉得越多缩得越小 */
  dismissScale(): number {
    const t: number = this.dismissOffset / DISMISS_FADE_SPAN;
    const s: number = 1 - t * (1 - DISMISS_MIN_SCALE);
    return s > DISMISS_MIN_SCALE ? s : DISMISS_MIN_SCALE;
  }

  /** 退出过程中的整体透明度：拉得越远越透，露出底下的列表 */
  dismissOpacity(): number {
    const o: number = 1 - this.dismissOffset / DISMISS_FADE_SPAN;
    return o > 0.25 ? o : 0.25;
  }

  /**
   * 松手时的判定：够远、或者甩得够快，就关掉；否则回弹。
   *
   * 回弹必须走 animateTo，不能用 .animation() 常驻 —— 常驻动画会让拖动过程
   * 也带上缓动，那是「跟手不跟手」的分界。
   */
  settleDismiss(): void {
    const far: boolean = this.dismissOffset > DISMISS_DISTANCE;
    const fast: boolean = this.panVelocity > DISMISS_VELOCITY;
    if (far || fast) {
      this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, () => {
        this.dismissOffset = this.viewH;
      });
      // 等淡出动画走完再真正关闭，避免画面「啪」地消失
      setTimeout(() => {
        this.closeDetail();
      }, 180);
    } else {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => {
        this.dismissOffset = 0;
      });
    }
    this.dismissArmed = false;
    this.panVelocity = 0;
  }

  /**
   * 缩放态下的下拉：先正常拖动看图，等图片上边缘被拖出屏幕（上方露出空白）之后，
   * 多出来的那部分位移才转为「退出」。这样放大看图不会误触退出，
   * 而拖到顶还继续拉时又能顺理成章地关掉 —— 两件事共用一个手势，靠边界分开。
   *
   * 图片按 Contain 摆放，显示高度是 min(可视高, 可视宽 / 宽高比)，
   * 乘上缩放倍率就是它的实际高度。
   */
  applyZoomPan(rawY: number): void {
    const item: MediaItem = this.items[this.detailShowIndex()];
    let imgH: number = this.viewH;
    if (item && this.viewW > 0 && item.width > 0 && item.height > 0) {
      const containH: number = this.viewW * item.height / item.width;
      imgH = containH < this.viewH ? containH : this.viewH;
    }
    const half: number = imgH * this.scaleValue / 2;
    // offsetY 超过这个值，图片上边缘就跑出屏幕顶部了，上方开始露白
    const limit: number = half - this.viewH / 2;
    const edge: number = limit > 0 ? limit : 0;

    if (rawY > edge) {
      // 图片钉在边界，超出的部分交给退出位移
      this.offsetY = edge;
      this.dismissOffset = rawY - edge;
      this.dismissArmed = true;
    } else {
      this.offsetY = rawY;
      this.dismissOffset = 0;
      this.dismissArmed = false;
    }
  }

  /** 记录拖动速度（vp/s）：位移不够但甩得够快时也判定退出 */
  trackPanVelocity(y: number): void {
    const now: number = Date.now();
    const dt: number = now - this.lastPanTime;
    if (dt > 0) {
      this.panVelocity = (y - this.lastPanY) / dt * 1000;
    }
    this.lastPanY = y;
    this.lastPanTime = now;
  }

  @Builder
  detailPage(item: MediaItem, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (item.type === MediaType.VIDEO) {
        if (index === this.selectedIndex) {
          Video({ src: item.uri, controller: this.videoController })
            .width('100%')
            .height('100%')
            .controls(true)
            .autoPlay(true)
            .loop(true)
            .objectFit(ImageFit.Contain)
        } else if (item.thumbUri.length > 0) {
          Image(item.thumbUri)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
        } else {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.c_bg'))
        }
      } else if (this.scaleValue > 1.05) {
        Image(item.uri)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.baseScale = this.scaleValue;
                })
                .onActionUpdate((event: GestureEvent) => {
                  let s: number = this.baseScale * event.scale;
                  if (s < 1) {
                    s = 1;
                  }
                  if (s > 5) {
                    s = 5;
                  }
                  this.scaleValue = s;
                }),
              PanGesture({ fingers: 1 })
                .onActionStart(() => {
                  this.baseOffsetX = this.offsetX;
                  this.baseOffsetY = this.offsetY;
                  this.lastPanY = 0;
                  this.lastPanTime = Date.now();
                  this.panVelocity = 0;
                  this.dismissArmed = false;
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.offsetX = this.baseOffsetX + event.offsetX;
                  const rawY: number = this.baseOffsetY + event.offsetY;
                  this.trackPanVelocity(rawY);
                  // 先正常拖动看图；拖到图片上方露白之后，多余位移才转为退出
                  this.applyZoomPan(rawY);
                })
                .onActionEnd(() => {
                  if (this.dismissArmed) {
                    this.settleDismiss();
                  }
                }),
              TapGesture({ count: 2 })
                .onAction(() => {
                  this.resetZoom();
                })
            )
          )
      } else {
        Image(item.uri)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.baseScale = this.scaleValue;
                })
                .onActionUpdate((event: GestureEvent) => {
                  let s: number = this.baseScale * event.scale;
                  if (s < 1) {
                    s = 1;
                  }
                  if (s > 5) {
                    s = 5;
                  }
                  this.scaleValue = s;
                }),
              // 单指下拉退出。方向限定 Vertical，横向的滑动仍然交给外层的 Swiper 翻页，
              // 两者不抢手势
              PanGesture({ direction: PanDirection.Vertical })
                .onActionStart(() => {
                  this.lastPanY = 0;
                  this.lastPanTime = Date.now();
                  this.panVelocity = 0;
                })
                .onActionUpdate((event: GestureEvent) => {
                  let dy: number = event.offsetY;
                  if (dy < 0) {
                    dy = 0;
                  }
                  this.trackPanVelocity(dy);
                  this.dismissOffset = dy;
                })
                .onActionEnd(() => {
                  this.settleDismiss();
                }),
              TapGesture({ count: 2 })
                .onAction(() => {
                  this.scaleValue = 2.5;
                })
            )
          )
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.c_bg'))
  }

  /** 图片翻页区。横竖屏共用，只是外层排布不同 */
  @Builder
  detailPager() {
    Swiper(this.detailSwiper) {
      LazyForEach(this.ds, (item: MediaItem, index: number) => {
        this.detailPage(item, index);
      }, (item: MediaItem) => item.id)
    }
    .index(this.swiperIndex)
    .loop(false)
    .indicator(false)
    .autoPlay(false)
    .disableSwipe(this.scaleValue > 1.05)
    .width('100%')
    .layoutWeight(1)
    .onAnimationStart((index: number, targetIndex: number) => {
      // 动画一开始就把信息卡片切到目标页，避免等切换动画播完才有反应
      this.detailIndex = targetIndex;
      this.swiperIndex = targetIndex;
    })
    .onChange((index: number) => {
      this.swiperIndex = index;
      // 父组件已经把 selectedIndex 置成 -1 说明正在关闭：这时候的 onChange
      // 是 `.index()` 被强行拉回 0 产生的，回传过去会让详情页复活
      if (this.selectedIndex < 0) {
        return;
      }
      this.onDetailPageChange(index);
    })
  }

  /**
   * 信息面板。竖屏时是贴底的抽屉（通栏、上圆角），
   * 横屏时变成右侧的固定宽度侧栏（全高、左圆角）—— 圆角和描边要跟着换边。
   */
  @Builder
  detailPanel() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        if (this.editingName) {
          TextInput({ text: this.nameDraft })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor($r('app.color.c_text'))
            .backgroundColor($r('app.color.c_inputbg'))
            .borderRadius(10)
            .onChange((v: string) => {
              this.nameDraft = v;
            })
          accentPill('保存', () => {
            this.saveName();
          })
        } else {
          Text(this.nameDraft)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.c_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          ghostPill('重命名', () => {
            this.nameDraft = this.currentDisplayName();
            this.editingName = true;
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.remarkEditing) {
        TextArea({ text: this.remarkDraft })
          .width('100%')
          .height(72)
          .fontSize(14)
          .fontColor($r('app.color.c_text'))
          .backgroundColor($r('app.color.c_inputbg'))
          .borderRadius(10)
          .onChange((v: string) => {
            this.remarkDraft = v;
          })
        Row({ space: 10 }) {
          Blank()
          ghostPill('取消', () => {
            this.remarkDraft = this.currentRemark();
            this.remarkEditing = false;
          })
          accentPill('保存', () => {
            this.saveRemark();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Row({ space: 10 }) {
          Text(this.remarkDraft.length > 0 ? this.remarkDraft : '暂无备注')
            .fontSize(13)
            .fontColor(this.remarkDraft.length > 0 ? $r('app.color.c_text2') : $r('app.color.c_text3'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          ghostPill('写备注', () => {
            this.remarkDraft = this.currentRemark();
            this.remarkEditing = true;
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      Row({ space: 8 }) {
        if (this.detailFavorite) {
          this.goldPill('取消收藏', () => {
            this.toggleDetailFavorite();
          })
        } else {
          ghostPill('收藏', () => {
            this.toggleDetailFavorite();
          })
        }
        ghostPill('分组', () => {
          this.openGroupEditor();
        })
        ghostPill('分享', () => {
          this.onShareItem();
        })
        Blank()
        this.dangerPill('删除', () => {
          this.onDeleteSingle();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    // 横屏：右侧固定宽度侧栏，全高；圆角和描边换到左边
    .width(this.isLandscape ? DETAIL_PANEL_W : '100%')
    .height(this.isLandscape ? '100%' : undefined)
    .padding({ left: 16, right: 16, top: 16, bottom: 24 })
    .backgroundColor($r('app.color.c_card'))
    .border(this.isLandscape
      ? { width: { left: 1 }, color: $r('app.color.c_chip_border') }
      : { width: { top: 1 }, color: $r('app.color.c_chip_border') })
    .borderRadius(this.isLandscape
      ? { topLeft: 20, bottomLeft: 20 }
      : { topLeft: 20, topRight: 20 })
  }

  // 信息卡片使用的索引：滑动开始即更新；越界或未设置时退回 selectedIndex
  detailShowIndex(): number {
    const i: number = this.detailIndex;
    if (i >= 0 && i < this.items.length) {
      return i;
    }
    return this.selectedIndex;
  }

  currentDisplayName(): string {
    const i: number = this.detailShowIndex();
    if (i >= 0 && i < this.items.length) {
      return this.items[i].displayName;
    }
    return '';
  }

  currentRemark(): string {
    const i: number = this.detailShowIndex();
    if (i >= 0 && i < this.items.length) {
      return this.items[i].remark;
    }
    return '';
  }

  // 详情面板：金色（已收藏）按钮
  @Builder
  goldPill(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.c_favtext'))
      .padding({ left: 15, right: 15, top: 9, bottom: 9 })
      .backgroundColor($r('app.color.d_gold_bg'))
      .borderRadius(19)
      .onClick(action)
  }

  // 详情面板：危险按钮
  @Builder
  dangerPill(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.d_danger'))
      .padding({ left: 15, right: 15, top: 9, bottom: 9 })
      .backgroundColor($r('app.color.d_danger_bg'))
      .borderRadius(19)
      .onClick(action)
  }
}
