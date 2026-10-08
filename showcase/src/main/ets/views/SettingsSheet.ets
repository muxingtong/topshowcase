import { ghostPill } from '../common/Widgets';

/**
 * 设置页：整页覆盖，四组设置（外观 / 播放 / 数据 / 关于）。
 * 数值全部只读，修改通过回调交给父组件落盘。
 */
@Component
export struct SettingsSheet {
  @Prop safeTop: number;
  @Prop safeBottom: number;
  /** 横屏：刘海在侧边，设置页要避开 */
  @Prop safeSide: number = 0;
  @Prop columns: number;
  @Prop slideInterval: number;
  @Prop autoPlay: boolean;
  @Prop theme: number;
  @Prop itemCount: number;
  @Prop imageCount: number;
  @Prop videoCount: number;
  @Prop groupCount: number;

  onClose: () => void = () => {};
  onSetColumns: (n: number) => void = () => {};
  onSetInterval: (sec: number) => void = () => {};
  onToggleAutoPlay: (on: boolean) => void = () => {};
  onApplyTheme: (t: number) => void = () => {};
  onExportBackup: () => void = () => {};
  onImportBackup: () => void = () => {};

  build() {
    this.settingsPage();
  }


  // 设置页：整页覆盖，分组卡片布局
  @Builder
  settingsPage() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.c_bg'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        Row({ space: 4 }) {
          Text('←')
            .fontSize(20)
            .fontColor($r('app.color.c_text'))
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onClose();
            })
          Text('设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.c_text'))
          Blank()
        }
        .width('100%')
        .padding({ left: 8, right: 16, top: 6, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: 18 }) {
            this.settingAppearance()
            this.settingPlayback()
            this.settingData()
            this.settingAbout()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 32 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
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
    .transition(TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ y: 40 }))
      .animation({ duration: 260, curve: Curve.EaseOut }))
  }

  @Builder
  settingLabel(text: string) {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.c_text3'))
      .width('100%')
      .padding({ left: 4 })
  }

  // 外观：网格列数 + 主题
  @Builder
  settingAppearance() {
    Column({ space: 10 }) {
      this.settingLabel('外观')

      Column({ space: 14 }) {
        Text('网格列数')
          .fontSize(14)
          .fontColor($r('app.color.c_text'))
          .width('100%')
        Row() {
          this.settingSeg(2)
          this.settingSeg(3)
          this.settingSeg(4)
        }
        .width('100%')
        .height(38)
        .padding(3)
        .backgroundColor($r('app.color.c_chip'))
        .borderRadius(19)

        Divider().color($r('app.color.c_chip_border')).strokeWidth(1)

        Text('主题')
          .fontSize(14)
          .fontColor($r('app.color.c_text'))
          .width('100%')
        Row() {
          this.themeSeg('跟随系统', 0)
          this.themeSeg('浅色', 1)
          this.themeSeg('深色', 2)
        }
        .width('100%')
        .height(38)
        .padding(3)
        .backgroundColor($r('app.color.c_chip'))
        .borderRadius(19)
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.c_card'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.c_chip_border') })
    }
    .width('100%')
  }

  // 播放：幻灯片间隔 + 展柜自动轮播
  @Builder
  settingPlayback() {
    Column({ space: 10 }) {
      this.settingLabel('播放')

      Column({ space: 14 }) {
        Text('幻灯片间隔')
          .fontSize(14)
          .fontColor($r('app.color.c_text'))
          .width('100%')
        Row() {
          this.intervalSeg(2)
          this.intervalSeg(3)
          this.intervalSeg(5)
        }
        .width('100%')
        .height(38)
        .padding(3)
        .backgroundColor($r('app.color.c_chip'))
        .borderRadius(19)

        Divider().color($r('app.color.c_chip_border')).strokeWidth(1)

        Row() {
          Column({ space: 2 }) {
            Text('展柜自动轮播')
              .fontSize(14)
              .fontColor($r('app.color.c_text'))
            Text('展柜排布下自动播放下一个')
              .fontSize(12)
              .fontColor($r('app.color.c_text3'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.autoPlay })
            .selectedColor($r('app.color.c_chip_active'))
            .onChange((isOn: boolean) => {
              this.onToggleAutoPlay(isOn);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.c_card'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.c_chip_border') })
    }
    .width('100%')
  }

  // 数据：统计 + 备份 / 恢复
  @Builder
  settingData() {
    Column({ space: 10 }) {
      this.settingLabel('数据')

      Column({ space: 14 }) {
        Row() {
          Text('藏品总数')
            .fontSize(14)
            .fontColor($r('app.color.c_text'))
            .layoutWeight(1)
          Text(this.itemCount.toString() + ' 件')
            .fontSize(14)
            .fontColor($r('app.color.c_text2b'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider().color($r('app.color.c_chip_border')).strokeWidth(1)

        Row() {
          Text('图片 / 视频')
            .fontSize(14)
            .fontColor($r('app.color.c_text'))
            .layoutWeight(1)
          Text(this.imageCount.toString() + ' / ' + this.videoCount.toString())
            .fontSize(14)
            .fontColor($r('app.color.c_text2b'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider().color($r('app.color.c_chip_border')).strokeWidth(1)

        Row() {
          Text('分组')
            .fontSize(14)
            .fontColor($r('app.color.c_text'))
            .layoutWeight(1)
          Text(this.groupCount.toString() + ' 组')
            .fontSize(14)
            .fontColor($r('app.color.c_text2b'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider().color($r('app.color.c_chip_border')).strokeWidth(1)

        Row({ space: 10 }) {
          ghostPill('备份元数据', () => {
            this.onExportBackup();
          })
          ghostPill('恢复元数据', () => {
            this.onImportBackup();
          })
          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.c_card'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.c_chip_border') })
    }
    .width('100%')
  }

  @Builder
  settingAbout() {
    Column({ space: 10 }) {
      this.settingLabel('关于')

      Column({ space: 14 }) {
        Row() {
          Text('应用名称')
            .fontSize(14)
            .fontColor($r('app.color.c_text'))
            .layoutWeight(1)
          Text('展物')
            .fontSize(14)
            .fontColor($r('app.color.c_text2b'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider().color($r('app.color.c_chip_border')).strokeWidth(1)

        Row() {
          Text('版本')
            .fontSize(14)
            .fontColor($r('app.color.c_text'))
            .layoutWeight(1)
          Text('1.0.0')
            .fontSize(14)
            .fontColor($r('app.color.c_text2b'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider().color($r('app.color.c_chip_border')).strokeWidth(1)

        Text('沉浸光感胶囊导航 · 液态指示器 · 网格 / 瀑布 / 展柜 / 列表四种排布 · 数据仅存本地')
          .fontSize(12)
          .fontColor($r('app.color.c_text3'))
          .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.c_card'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.c_chip_border') })
    }
    .width('100%')
  }

  @Builder
  settingSeg(n: number) {
    Column() {
      Text(n.toString())
        .fontSize(13)
        .fontWeight(this.columns === n ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.columns === n ? $r('app.color.c_chip_active_text') : $r('app.color.c_text2b'))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.columns === n ? $r('app.color.c_chip_active') : Color.Transparent)
    .borderRadius(16)
    .onClick(() => {
      this.onSetColumns(n);
    })
  }

  @Builder
  intervalSeg(sec: number) {
    Column() {
      Text(sec.toString() + ' 秒')
        .fontSize(13)
        .fontWeight(this.slideInterval === sec ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.slideInterval === sec ? $r('app.color.c_chip_active_text') : $r('app.color.c_text2b'))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.slideInterval === sec ? $r('app.color.c_chip_active') : Color.Transparent)
    .borderRadius(16)
    .onClick(() => {
      this.onSetInterval(sec);
    })
  }

  // 选中态必须在这里读 this.theme
  @Builder
  themeSeg(label: string, value: number) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(this.theme === value ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.theme === value ? $r('app.color.c_chip_active_text') : $r('app.color.c_text2b'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme === value ? $r('app.color.c_chip_active') : Color.Transparent)
    .borderRadius(16)
    .onClick(() => {
      this.onApplyTheme(value);
    })
  }
}
