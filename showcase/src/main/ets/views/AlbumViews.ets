import { MediaItem } from '../model/MediaItem';
import { emptyState } from '../common/Widgets';
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

/** 分组浏览卡片的数据 */
class GroupInfo {
  name: string = '';
  count: number = 0;
  coverUri: string = '';
  /** 封面所属藏品的真实宽高，供瀑布/展柜按真实比例排布 */
  width: number = 0;
  height: number = 0;

  constructor(name: string, count: number, coverUri: string, width: number, height: number) {
    this.name = name;
    this.count = count;
    this.coverUri = coverUri;
    this.width = width;
    this.height = height;
  }
}

/**
 * 组合视图：按分组浏览，形态跟随当前排布（网格 / 瀑布 / 展柜 / 列表）。
 * 只负责渲染，数据与回调由父组件注入。
 */
@Component
export struct AlbumViews {
  /** 现有分组名 */
  @Link groups: string[];
  /** 全量藏品：统计每组件数与封面 */
  @Link allItems: MediaItem[];

  @Prop layoutMode: number;
  @Prop contentPhase: number;
  @Prop headerHeight: number;
  @Prop contentPad: number;
  @Prop columns: number;
  /** 底部导航总高：浮层控件用它避让 */
  @Prop navBlock: number;

  /** 进入某个分组 */
  onOpenGroup: (name: string) => void = () => {};
  onScroll: (first: number) => void = () => {};

  /** 展柜形态下的当前分组 */
  @State albumIndex: number = 0;
  private albumSwiperController: SwiperController = new SwiperController();

  build() {
    if (this.groups.length === 0) {
      emptyState('还没有分组', '在详情页或长按多选，把藏品移入分组');
    } else if (this.layoutMode === LAYOUT_GRID) {
      this.albumsGrid();
    } else if (this.layoutMode === LAYOUT_WATERFALL) {
      this.albumsWaterfall();
    } else if (this.layoutMode === LAYOUT_SHOWCASE) {
      this.albumsShowcase();
    } else {
      this.albumsList();
    }
  }


  // ---------- 组合（按分组浏览） ----------

  groupInfos(): GroupInfo[] {
    const res: GroupInfo[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      const g: string = this.groups[i];
      let count: number = 0;
      let cover: string = '';
      let coverW: number = 0;
      let coverH: number = 0;
      for (let j = 0; j < this.allItems.length; j++) {
        const it: MediaItem = this.allItems[j];
        if (it.group === g) {
          count++;
          if (cover.length === 0) {
            cover = it.thumbUri.length > 0 ? it.thumbUri : it.uri;
            coverW = it.width;
            coverH = it.height;
          }
        }
      }
      res.push(new GroupInfo(g, count, cover, coverW, coverH));
    }
    return res;
  }

  // 组合视图：跟随当前排布样式（网格 / 瀑布 / 展柜 / 列表）
  @Builder
  albumsLayout() {
    if (this.groups.length === 0) {
      emptyState('还没有分组', '在详情页或长按多选，把藏品移入分组');
    } else if (this.layoutMode === LAYOUT_GRID) {
      this.albumsGrid();
    } else if (this.layoutMode === LAYOUT_WATERFALL) {
      this.albumsWaterfall();
    } else if (this.layoutMode === LAYOUT_SHOWCASE) {
      this.albumsShowcase();
    } else {
      this.albumsList();
    }
  }

  // 分组封面比例（无真实宽高时按 3:4 兜底）
  albumRatio(g: GroupInfo): number {
    if (g.width > 0 && g.height > 0) {
      let r: number = g.width / g.height;
      if (r < 0.6) {
        r = 0.6;
      }
      if (r > 1.4) {
        r = 1.4;
      }
      return r;
    }
    return 0.75;
  }

  @Builder
  albumsGrid() {
    Grid() {
      ForEach(this.groupInfos(), (g: GroupInfo, index: number) => {
        GridItem() {
          this.groupCard(g);
        }
        .aspectRatio(1)
        .translate({ x: exitShiftX(this.contentPhase, index), y: enterShiftY(this.contentPhase, index) })
        .opacity(phaseOpacity(this.contentPhase))
        .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
      }, (g: GroupInfo) => g.name)
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
  }

  @Builder
  albumsWaterfall() {
    WaterFlow() {
      ForEach(this.groupInfos(), (g: GroupInfo, index: number) => {
        FlowItem() {
          this.groupCard(g);
        }
        .width('100%')
        .aspectRatio(this.albumRatio(g))
        .translate({ x: exitShiftX(this.contentPhase, index), y: enterShiftY(this.contentPhase, index) })
        .opacity(phaseOpacity(this.contentPhase))
        .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
      }, (g: GroupInfo) => g.name)
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
  }

  @Builder
  albumsShowcase() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 主图铺满整屏，底部延伸到导航下方，透过玻璃能看到分组封面
      Swiper(this.albumSwiperController) {
        ForEach(this.groupInfos(), (g: GroupInfo, index: number) => {
          this.albumShowcaseCard(g);
        }, (g: GroupInfo) => g.name)
      }
      .loop(true)
      .indicator(false)
      .autoPlay(false)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.albumIndex = index;
      })

      // 缩略图条浮在导航上方
      List({ space: 10 }) {
        ForEach(this.groupInfos(), (g: GroupInfo, index: number) => {
          ListItem() {
            this.groupThumb(g, index);
          }
        }, (g: GroupInfo) => g.name)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(72)
      .padding({ left: 16, right: 16 })
      .margin({ bottom: this.navBlock })
    }
    .width('100%')
    .height('100%')
    .translate({ x: exitShiftX(this.contentPhase, this.albumIndex), y: enterShiftY(this.contentPhase, 0) })
    .opacity(phaseOpacity(this.contentPhase))
    .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
  }

  @Builder
  albumShowcaseCard(g: GroupInfo) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        if (g.coverUri.length > 0) {
          Image(g.coverUri)
            .objectFit(ImageFit.Cover)
            .width('100%')
            .height('100%')
        } else {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.c_chip'))
        }

        Column({ space: 4 }) {
          Text(g.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(g.count.toString() + ' 件')
            .fontSize(13)
            .fontColor('#E6E8EC')
        }
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .backgroundColor('#99000000')
        .borderRadius(16)
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius(20)
      .clip(true)
      .shadow({ radius: 16, color: $r('app.color.c_shadow'), offsetX: 0, offsetY: 8 })
      .onClick(() => {
        this.onOpenGroup(g.name);
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 10 })
  }

  // 展柜模式下的分组缩略图条
  @Builder
  groupThumb(g: GroupInfo, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (g.coverUri.length > 0) {
        Image(g.coverUri)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.c_chip'))
      }
      if (this.albumIndex === index) {
        Column()
          .width('100%')
          .height('100%')
          .border({ width: 2, color: $r('app.color.c_chip_active') })
          .borderRadius(12)
      }
    }
    .width(72)
    .height(72)
    .borderRadius(12)
    .clip(true)
    .backgroundColor($r('app.color.c_chip'))
    .onClick(() => {
      this.albumSwiperController.changeIndex(index);
      this.albumIndex = index;
    })
  }

  @Builder
  albumsList() {
    List({ space: 10 }) {
      ForEach(this.groupInfos(), (g: GroupInfo, index: number) => {
        ListItem() {
          Row({ space: 12 }) {
            Stack({ alignContent: Alignment.Center }) {
              if (g.coverUri.length > 0) {
                Image(g.coverUri)
                  .objectFit(ImageFit.Cover)
                  .width('100%')
                  .height('100%')
              } else {
                Column()
                  .width('100%')
                  .height('100%')
                  .backgroundColor($r('app.color.c_chip'))
              }
            }
            .width(68)
            .height(68)
            .borderRadius(12)
            .clip(true)

            Column({ space: 5 }) {
              Text(g.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.c_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(g.count.toString() + ' 件藏品')
                .fontSize(13)
                .fontColor($r('app.color.c_text3'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('›')
              .fontSize(20)
              .fontColor($r('app.color.c_arrow'))
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
          this.onOpenGroup(g.name);
        })
        .translate({ x: exitShiftX(this.contentPhase, index), y: enterShiftY(this.contentPhase, index) })
        .opacity(phaseOpacity(this.contentPhase))
        .animation({ duration: phaseAnimDuration(this.contentPhase), curve: Curve.Friction })
      }, (g: GroupInfo) => g.name)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: this.contentPad })
    .scrollBar(BarState.Off)
    .onScrollIndex((first: number) => {
      this.onScroll(first);
    })
    .contentStartOffset(this.headerHeight)
  }

  @Builder
  groupCard(g: GroupInfo) {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (g.coverUri.length > 0) {
        Image(g.coverUri)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.c_chip'))
      }
      Column({ space: 2 }) {
        Text(g.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(g.count.toString() + ' 件')
          .fontSize(11)
          .fontColor('#E6E8EC')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor('#99000000')
    }
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .clip(true)
    .shadow({ radius: 16, color: $r('app.color.c_shadow'), offsetX: 0, offsetY: 8 })
    .onClick(() => {
      this.onOpenGroup(g.name);
    })
  }
}
