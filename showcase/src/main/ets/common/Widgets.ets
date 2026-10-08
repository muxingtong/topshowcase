import { MediaItem, MediaType } from '../model/MediaItem';

/**
 * 藏品缩略图填充：优先用缩略图（省内存），视频叠加播放角标。
 * 全局 @Builder，多个视图组件共用。
 */
@Builder
export function mediaFill(item: MediaItem) {
  Stack({ alignContent: Alignment.Center }) {
    if (item.thumbUri.length > 0) {
      Image(item.thumbUri)
        .objectFit(ImageFit.Cover)
        .width('100%')
        .height('100%')
    } else if (item.type === MediaType.VIDEO) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#141820')
    } else {
      Image(item.uri)
        .objectFit(ImageFit.Cover)
        .width('100%')
        .height('100%')
    }

    if (item.type === MediaType.VIDEO) {
      Column() {
        Text('▶')
          .fontSize(16)
          .fontColor('#FFFFFF')
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor('#66000000')
      .justifyContent(FlexAlign.Center)
    }
  }
  .width('100%')
  .height('100%')
}

/** 空状态：居中一个大图标 + 标题 + 说明 */
@Builder
export function emptyState(title: string, subtitle: string) {
  Column({ space: 14 }) {
    Column() {
      Text('＋')
        .fontSize(34)
        .fontColor($r('app.color.c_text3'))
    }
    .width(88)
    .height(88)
    .borderRadius(28)
    .backgroundColor($r('app.color.c_chip'))
    .border({ width: 1, color: $r('app.color.c_chip_border') })
    .justifyContent(FlexAlign.Center)

    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.c_text'))
    Text(subtitle)
      .fontSize(13)
      .fontColor($r('app.color.c_text3'))
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
}


// 详情面板：次要按钮
@Builder
export function ghostPill(label: string, action: () => void) {
  Text(label)
    .fontSize(13)
    .fontColor($r('app.color.c_text2b'))
    .padding({ left: 15, right: 15, top: 9, bottom: 9 })
    .backgroundColor($r('app.color.d_pill'))
    .borderRadius(19)
    .onClick(action)
}


// 详情面板：主按钮
@Builder
export function accentPill(label: string, action: () => void) {
  Text(label)
    .fontSize(13)
    .fontWeight(FontWeight.Medium)
    .fontColor('#FFFFFF')
    .padding({ left: 17, right: 17, top: 9, bottom: 9 })
    .backgroundColor($r('app.color.c_chip_active'))
    .borderRadius(19)
    .onClick(action)
}
