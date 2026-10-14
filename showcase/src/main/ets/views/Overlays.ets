import { MediaItem, MediaType } from '../model/MediaItem';
import { MediaDataSource } from '../model/MediaDataSource';
import { accentPill, ghostPill } from '../common/Widgets';

/**
 * 覆盖层：沉浸式幻灯片 / 分组编辑弹层 / 多选底栏。
 * 数据由父组件注入，动作通过同名回调成员上报，组件自身不碰业务。
 */
@Component
export struct Overlays {
  /** 幻灯片当前页（父组件也用它做恢复） */
  @Link slideIndex: number;
  @Link items: MediaItem[];
  @Link groups: string[];
  @Link groupDraft: string;

  /** 列表数据源（幻灯片的 LazyForEach 用） */
  ds: MediaDataSource = new MediaDataSource();
  /** 幻灯片视频控制器（父组件在进出时负责 stop） */
  slideVideo: VideoController = new VideoController();

  @Prop slideInterval: number;
  @Prop safeTop: number;
  @Prop safeBottom: number;
  /** 横屏：刘海在侧边，覆盖层内容要避开 */
  @Prop safeSide: number = 0;
  @Prop selectedCount: number;

  /** 三块覆盖层各自的显示开关，由父组件决定 */
  @Prop showSlideshow: boolean;
  @Prop showGroupEditor: boolean;
  @Prop showSelectBar: boolean;

  // 回调成员沿用父组件的方法名，搬迁时几乎不用改调用点
  exitSlideshow: () => void = () => {};
  applyGroup: () => void = () => {};
  closeGroupEditor: () => void = () => {};
  onDeleteSelected: () => void = () => {};
  onShareSelected: () => void = () => {};
  openGroupEditor: () => void = () => {};

  build() {
    Stack() {
      if (this.showSelectBar) {
        this.selectBar();
      }
      if (this.showSlideshow) {
        this.slideshowOverlay();
      }
      if (this.showGroupEditor) {
        this.groupEditor();
      }
    }
    .width('100%')
    .height('100%')
    // 不显示的层不能挡住下层内容
    .hitTestBehavior(HitTestMode.Transparent)
  }


  @Builder
  slideshowOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Swiper() {
        LazyForEach(this.ds, (item: MediaItem, index: number) => {
          this.slidePage(item, index);
        }, (item: MediaItem) => item.id)
      }
      .index(this.slideIndex)
      .loop(true)
      .indicator(false)
      .autoPlay(true)
      .interval(this.slideInterval * 1000)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.onSlideChange(index);
      })

      Stack({ alignContent: Alignment.TopEnd }) {
        Text('退出展示')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor('#66000000')
          .borderRadius(16)
          .margin({ right: 16 + this.safeSide, top: 16 + this.safeTop })
          .onClick(() => {
            this.exitSlideshow();
          })
      }
      .width('100%')
      .height('100%')

      if (this.slideIndex >= 0 && this.slideIndex < this.items.length) {
        Stack({ alignContent: Alignment.Bottom }) {
          Text(this.items[this.slideIndex].displayName)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({
              left: 16 + this.safeSide,
              right: 16 + this.safeSide,
              top: 8,
              bottom: 24 + this.safeBottom
            })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseInOut }))
  }

  @Builder
  slidePage(item: MediaItem, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (item.type === MediaType.VIDEO) {
        if (index === this.slideIndex) {
          Video({ src: item.uri, controller: this.slideVideo })
            .width('100%')
            .height('100%')
            .controls(false)
            .autoPlay(true)
            .loop(true)
            .muted(true)
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
            .backgroundColor('#000000')
        }
      } else {
        Image(item.uri)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  onSlideChange(index: number): void {
    try {
      this.slideVideo.stop();
    } catch (err) {
    }
    this.slideIndex = index;
  }

  @Builder
  groupEditor() {
    Column() {
      Column({ space: 14 }) {
        Text('移入分组')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.c_text'))
          .width('100%')

        TextInput({ text: this.groupDraft, placeholder: '输入分组名（留空则移出分组）' })
          .width('100%')
          .height(44)
          .fontSize(13)
          .backgroundColor($r('app.color.c_inputbg'))
          .borderRadius(12)
          .onChange((v: string) => {
            this.groupDraft = v;
          })

        if (this.groups.length > 0) {
          Text('已有分组（点击填入）')
            .fontSize(13)
            .fontColor($r('app.color.c_text2'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.groups, (g: string) => {
              Text(g)
                .fontSize(13)
                .fontColor($r('app.color.c_text2b'))
                .padding({ left: 13, right: 13, top: 7, bottom: 7 })
                .backgroundColor($r('app.color.c_chip'))
                .borderRadius(16)
                .border({ width: 1, color: $r('app.color.c_chip_border') })
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.groupDraft = g;
                })
            }, (g: string) => g)
          }
          .width('100%')
        }

        Row({ space: 10 }) {
          Blank()
          this.chromeGhost('取消', () => {
            this.closeGroupEditor();
          })
          accentPill('确定', () => {
            this.applyGroup();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('84%')
      .padding(20)
      .backgroundColor($r('app.color.c_card'))
      .borderRadius(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
  }

  @Builder
  selectBar() {
    Row({ space: 10 }) {
      ghostPill('移入分组', () => {
        this.openGroupEditor();
      })
      ghostPill('分享', () => {
        this.onShareSelected();
      })
      Blank()
      this.selectDeletePill()
    }
    .width('100%')
    .padding({
      left: 16 + this.safeSide,
      right: 16 + this.safeSide,
      top: 12,
      bottom: 22 + this.safeBottom
    })
    .backgroundColor($r('app.color.c_card'))
    .border({ width: { top: 1 }, color: $r('app.color.c_chip_border') })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .transition(TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ y: 60 }))
      .animation({ duration: 260, curve: Curve.EaseOut }))
  }

  // 多选底栏删除：数量变化需在此读取状态才会刷新
  @Builder
  selectDeletePill() {
    Text(this.selectedCount > 0 ? ('删除 ' + this.selectedCount.toString()) : '删除')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.selectedCount > 0 ? '#FFFFFF' : $r('app.color.c_text3'))
      .padding({ left: 15, right: 15, top: 9, bottom: 9 })
      .backgroundColor(this.selectedCount > 0 ? '#E5484D' : $r('app.color.d_pill'))
      .borderRadius(19)
      .onClick(() => {
        this.onDeleteSelected();
      })
  }

  // 顶栏「浅色底」次要按钮
  @Builder
  chromeGhost(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.c_text2b'))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.c_chip'))
      .borderRadius(16)
      .border({ width: 1, color: $r('app.color.c_chip_border') })
      .onClick(action)
  }
}
