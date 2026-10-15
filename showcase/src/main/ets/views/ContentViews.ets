import { MediaItem, MediaType } from '../model/MediaItem';
import { MediaDataSource } from '../model/MediaDataSource';
import { mediaFill } from '../common/Widgets';
import { effDate, formatDate, formatSize } from '../common/Format';
import {
  LAYOUT_GRID,
  LAYOUT_WATERFALL,
  LAYOUT_SHOWCASE,
  gridTemplate,
  exitShiftX,
  enterShiftY,
  phaseOpacity,
  phaseAnimDuration
} from '../common/Constants';

/**
 * 常规四种排布：网格 / 瀑布 / 展柜 / 列表。
 * 只负责渲染，数据源与交互回调由父组件注入。
 */
@Component
export struct ContentViews {
  /** 列表数据源（LazyForEach 用）：父组件 setItems 后 notifyReload 即可驱动刷新 */
  ds: MediaDataSource = new MediaDataSource();
  /** 大数组用 @Link 传引用，避免 @Prop 的值拷贝 */
  @Link items: MediaItem[];
  /** 展柜的自动轮播开关，子组件可切换 */
  @Link autoPlay: boolean;

  @Prop layoutMode: number;
  @Prop contentPhase: number;
  @Prop headerHeight: number;
  /** 内容底部留白（父组件按导航高度算好）：0 表示铺到屏幕底 */
  @Prop contentPad: number;
  /** 底部导航总高：浮层控件用它避让 */
  @Prop navBlock: number;
  /** 网格列数 */
  @Prop columns: number;
  @Prop selectMode: boolean;
  /** 展柜轮播间隔（秒） */
  @Prop slideInterval: number;

  onCardTap: (index: number) => void = () => {};
  onLongPress: (id: string) => void = () => {};
  onScroll: (first: number) => void = () => {};
  isSelected: (id: string) => boolean = () => false;
  onMoveItem: (from: number, to: number) => void = () => {};
  onToggleAutoPlay: () => void = () => {};

  /** 展柜当前页 */
  @State showcaseIndex: number = 0;
  private swiperController: SwiperController = new SwiperController();

  build() {
    if (this.layoutMode === LAYOUT_GRID) {
      this.gridLayout();
    } else if (this.layoutMode === LAYOUT_WATERFALL) {
      this.waterfallLayout();
    } else if (this.layoutMode === LAYOUT_SHOWCASE) {
      this.showcaseLayout();
    } else {
      this.listLayout();
    }
  }

  @Builder
  gridLayout() {
    Grid() {
      LazyForEach(this.ds, (item: MediaItem, index: number) => {
        GridItem() {
          this.mediaCard(item, index);
        }
        .aspectRatio(1)
        .translate({ x: exitShiftX(this.contentPhase, index), y: enterShiftY(this.contentPhase, index) })
        .opacity(phaseOpacity(this.contentPhase))
        .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
      }, (item: MediaItem) => item.id)
    }
    .columnsTemplate(gridTemplate(this.columns))
    .columnsGap(12)
    .rowsGap(12)
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

  @Builder
  mediaCard(item: MediaItem, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      mediaFill(item);

      if (item.type === MediaType.VIDEO) {
        Stack({ alignContent: Alignment.TopStart }) {
          Text('视频')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor('#E5484D')
            .borderRadius(8)
            .margin({ left: 8, top: 8 })
        }
        .width('100%')
        .height('100%')
      }

      if (this.selectMode) {
        Stack({ alignContent: Alignment.TopEnd }) {
          this.checkCircle(item);
        }
        .width('100%')
        .height('100%')
        .padding({ right: 8, top: 8 })
      } else if (item.favorite) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Text('★')
            .fontSize(17)
            .fontColor($r('app.color.c_gold'))
            .textShadow({ radius: 4, color: '#66000000', offsetX: 0, offsetY: 1 })
            .margin({ right: 8, top: 6 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .clip(true)
    .backgroundColor($r('app.color.c_chip'))
    .shadow({ radius: 16, color: $r('app.color.c_shadow'), offsetX: 0, offsetY: 8 })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      this.onCardTap(index);
    })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.onLongPress(item.id);
    }))
  }

  @Builder
  checkCircle(item: MediaItem) {
    Column() {
      Text(this.isSelected(item.id) ? '✓' : '')
        .fontSize(13)
        .fontColor('#FFFFFF')
    }
    .width(22)
    .height(22)
    .borderRadius(11)
    .backgroundColor(this.isSelected(item.id) ? $r('app.color.c_chip_active') : '#66000000')
    .border({ width: 1.5, color: '#FFFFFF' })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  waterfallLayout() {
    WaterFlow() {
      LazyForEach(this.ds, (item: MediaItem, index: number) => {
        FlowItem() {
          this.mediaCard(item, index);
        }
        .width('100%')
        .aspectRatio(this.waterfallRatio(item))
        .translate({ x: exitShiftX(this.contentPhase, index), y: enterShiftY(this.contentPhase, index) })
        .opacity(phaseOpacity(this.contentPhase))
        .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
      }, (item: MediaItem) => item.id)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
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

  // 瀑布流：用图片真实宽高比例（宽/高），无数据时用 3:4 兜底
  waterfallRatio(item: MediaItem): number {
    if (item.width > 0 && item.height > 0) {
      let r: number = item.width / item.height;
      if (r < 0.5) {
        r = 0.5;
      }
      if (r > 2) {
        r = 2;
      }
      return r;
    }
    return 0.75;
  }

  @Builder
  listLayout() {
    List({ space: 10 }) {
      LazyForEach(this.ds, (item: MediaItem, index: number) => {
        ListItem() {
          Row({ space: 12 }) {
            Stack({ alignContent: Alignment.Center }) {
              mediaFill(item);
            }
            .width(68)
            .height(68)
            .borderRadius(12)
            .clip(true)
            .backgroundColor($r('app.color.c_chip'))

            Column({ space: 5 }) {
              Text(item.displayName)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.c_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 8 }) {
                Text(item.type === MediaType.VIDEO ? '视频' : '图片')
                  .fontSize(11)
                  .fontColor('#FFFFFF')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .backgroundColor(item.type === MediaType.VIDEO ? '#E5484D' : '#3B82F6')
                  .borderRadius(5)
                if (item.favorite) {
                  Text('收藏')
                    .fontSize(11)
                    .fontColor($r('app.color.c_favtext'))
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor($r('app.color.c_favbg'))
                    .borderRadius(5)
                }
                Text(formatDate(effDate(item)) + ' · ' + formatSize(item.size))
                  .fontSize(13)
                  .fontColor($r('app.color.c_text2'))
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.selectMode) {
              this.checkCircle(item);
            } else {
              Text('›')
                .fontSize(20)
                .fontColor($r('app.color.c_arrow'))
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.c_card'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.c_chip_border') })
          .alignItems(VerticalAlign.Center)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
        }
        .onClick(() => {
          this.onCardTap(index);
        })
        .translate({ x: exitShiftX(this.contentPhase, index), y: enterShiftY(this.contentPhase, index) })
        .opacity(phaseOpacity(this.contentPhase))
        .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
      }, (item: MediaItem) => item.id)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: this.contentPad })
    .scrollBar(BarState.Off)
    .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
      return this.dragFloatPreview();
    })
    .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
      if (isSuccess && itemIndex !== insertIndex) {
        this.onMoveItem(itemIndex, insertIndex);
      }
    })
    .onScrollIndex((first: number) => {
      this.onScroll(first);
    })
    .contentStartOffset(this.headerHeight)
    .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseInOut }))
  }

  @Builder
  dragFloatPreview() {
    Text('拖动排序')
      .fontSize(13)
      .fontColor('#FFFFFF')
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.c_chip_active'))
      .borderRadius(16)
  }

  @Builder
  showcaseLayout() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 主图铺满整屏，底部延伸到导航下方，透过玻璃能看到展品
      Swiper(this.swiperController) {
        LazyForEach(this.ds, (item: MediaItem, index: number) => {
          this.showcaseCard(item, index);
        }, (item: MediaItem) => item.id)
      }
      .loop(true)
      .indicator(false)
      .autoPlay(this.autoPlay)
      .interval(this.slideInterval * 1000)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.showcaseIndex = index;
      })

      // 信息行 + 缩略图条浮在导航上方
      Column() {
        Row({ space: 10 }) {
        if (this.showcaseIndex >= 0 && this.showcaseIndex < this.items.length) {
          Text(this.items[this.showcaseIndex].displayName)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.c_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        Text(this.autoPlay ? '暂停轮播' : '自动轮播')
          .fontSize(13)
          .fontColor(this.autoPlay ? $r('app.color.c_text2b') : $r('app.color.c_chip_active_text'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.autoPlay ? $r('app.color.c_chip') : $r('app.color.c_chip_active'))
          .borderRadius(16)
          .onClick(() => {
            this.autoPlay = !this.autoPlay;
            this.onToggleAutoPlay();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      List({ space: 10 }) {
        LazyForEach(this.ds, (item: MediaItem, index: number) => {
          ListItem() {
            this.thumbnail(item, index);
          }
        }, (item: MediaItem) => item.id)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(72)
      .padding({ left: 16, right: 16 })
      .margin({ bottom: this.navBlock })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.headerHeight })
    .translate({ x: exitShiftX(this.contentPhase, this.showcaseIndex), y: enterShiftY(this.contentPhase, 0) })
    .opacity(phaseOpacity(this.contentPhase))
    .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
    .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseInOut }))
  }

  @Builder
  showcaseCard(item: MediaItem, index: number) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        this.mediaFillContain(item);
        if (item.type === MediaType.VIDEO) {
          Column() {
            Text('▶')
              .fontSize(30)
              .fontColor('#FFFFFF')
          }
          .width(62)
          .height(62)
          .borderRadius(31)
          .backgroundColor('#66000000')
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius(20)
      .clip(true)
      .backgroundColor($r('app.color.c_card'))
      .shadow({ radius: 48, color: $r('app.color.c_glow'), offsetX: 0, offsetY: 0 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16 })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      this.onCardTap(index);
    })
  }

  @Builder
  thumbnail(item: MediaItem, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      mediaFill(item);
    }
    .width(60)
    .height(60)
    .borderRadius(12)
    .clip(true)
    .backgroundColor($r('app.color.c_chip'))
    .border({ width: this.showcaseIndex === index ? 2 : 0, color: $r('app.color.c_chip_active') })
    .opacity(this.showcaseIndex === index ? 1 : 0.5)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      this.swiperController.changeIndex(index, true);
    })
  }

  @Builder
  /**
   * 展柜主图：按原比例完整显示（Contain），但**顶部对齐**。
   *
   * 卡片是整屏高的框，照片是宽幅时居中会同时在上、下留出卡片底色 —— 深色主题下
   * 那两块就是黑带，上面那块尤其像"顶了个黑边框"。改成顶对齐后留白只落在下方，
   * 而下方正好是信息行与缩略图条所在的位置，读起来就是展柜下方的标签区。
   */
  mediaFillContain(item: MediaItem) {
    if (item.type === MediaType.VIDEO) {
      if (item.thumbUri.length > 0) {
        Image(item.thumbUri)
          .objectFit(ImageFit.TOP)
          .width('100%')
          .height('100%')
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#141820')
      }
    } else {
      Image(item.uri)
        .objectFit(ImageFit.TOP)
        .width('100%')
        .height('100%')
    }
  }
}
