import {
  TOP_BTN_H,
  TOP_LEAD_W,
  TOP_SORT_W,
  TOP_MORE_W,
  HEADER_BLUR,
  SORT_TIME_DESC,
  SORT_TIME_ASC,
  SORT_NAME,
  SORT_SIZE_DESC,
  SORT_MANUAL
} from '../common/Constants';

/**
 * 顶栏浮层：标题 + 搜索/排序/更多三个材质按钮 + 可展开的搜索行 + 分组提示条。
 * 毛玻璃背景随内容滚动渐入；实测高度回写父组件（内容区据此做 contentStartOffset）。
 */
@Component
export struct TopBar {
  @Prop itemCount: number;
  @Prop selectedCount: number;
  @Prop safeTop: number;
  @Prop headerScrolled: boolean;
  @Prop keyword: string;
  @Prop selectMode: boolean;
  @Prop sortMode: number;
  @Prop groupFilter: string;
  /** 横屏：刘海在侧边，顶栏内容整体要避开 */
  @Prop safeSide: number = 0;

  onHeightChange: (h: number) => void = () => {};
  onKeywordChange: (kw: string) => void = () => {};
  onSort: (mode: number) => void = () => {};
  onEnterSelect: () => void = () => {};
  onExitSelect: () => void = () => {};
  onEnterSlideshow: () => void = () => {};
  onOpenSettings: () => void = () => {};
  onExportBackup: () => void = () => {};
  onImportBackup: () => void = () => {};
  onClearGroup: () => void = () => {};

  /** 搜索行是否展开 */
  @State searchOpen: boolean = false;

  build() {
    this.topBarLayer();
  }


  // 顶栏浮层：内容滚动时毛玻璃渐入
  @Builder
  topBarLayer() {
    Column() {
      // 顶栏本体：单层结构，模糊/底色直接挂在这一层，随滚动渐入
      Column() {
        this.topBar();
        if (this.searchOpen) {
          this.searchRow();
        }
        if (this.groupFilter.length > 0 && !this.selectMode) {
          this.activeGroupRow();
        }
      }
      .width('100%')
      .padding({ top: this.safeTop })
      .backdropBlur(this.headerBlur())
      .backgroundColor(this.headerTint())
      .animation({ duration: 240, curve: Curve.EaseOut })
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const h = newArea.height;
        if (typeof h === 'number' && h > 0) {
          this.onHeightChange(h);
        }
      })

      // 撑满剩余高度，让外层容器保持满屏、顶栏贴住顶部
      Blank()
    }
    .width('100%')
    .height('100%')
    // 不阻塞下层：顶栏空白处的手势（滑动列表、点被遮住的图片）要能穿透到内容区
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  topBar() {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Text('展物')
          .fontSize(23)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.c_text'))
        Text(this.itemCount.toString() + ' 件藏品')
          .fontSize(12)
          .fontColor($r('app.color.c_text3'))
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      if (this.selectMode) {
        Text(this.selectedCount > 0 ? ('已选 ' + this.selectedCount.toString()) : '多选')
          .fontSize(13)
          .fontColor($r('app.color.c_text2'))
          .padding({ right: 4 })
      }

      // 顶栏按钮：与底部胶囊同一套沉浸光感材质
      this.topLeadButton()
      if (!this.selectMode) {
        this.topSortButton()
        this.topMoreButton()
      }
    }
    .width('100%')
    .padding({ left: 16 + this.safeSide, right: 16 + this.safeSide, top: 14, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  // 顶栏按钮背板
  // HDS 沉浸式系统材质自带阴影且无参数可关，顶栏按钮尺寸小、背后又是纯色，
  // 材质阴影会显成突兀的小方框，因此这里用同色系的玻璃（无阴影）代替。
  @Builder
  topButtonGlass() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.nav_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .border({ width: 1, color: $r('app.color.nav_border') })
      .borderRadius(TOP_BTN_H / 2)
      // 纯装饰，不参与命中测试
      .hitTestBehavior(HitTestMode.None)
  }

  // 首位按钮：常规态「搜索」，多选态「取消」
  @Builder
  topLeadButton() {
    Stack() {
      this.topButtonGlass()
      if (this.selectMode) {
        Text('取消')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.c_text'))
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onExitSelect();
          })
      } else {
        Text(this.searchOpen ? '关闭' : '搜索')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.c_text'))
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.searchOpen = !this.searchOpen;
            if (!this.searchOpen && this.keyword.length > 0) {
              this.onKeywordChange('');
            }
          })
      }
    }
    .width(TOP_LEAD_W)
    .height(TOP_BTN_H)
  }

  @Builder
  topSortButton() {
    Stack() {
      this.topButtonGlass()
      Text(this.sortLabel() + ' ▾')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.c_text'))
        .width('100%')
        .height('100%')
        .textAlign(TextAlign.Center)
        .bindMenu([
          { value: '最新拍摄', action: () => { this.onSort(SORT_TIME_DESC); } },
          { value: '最早拍摄', action: () => { this.onSort(SORT_TIME_ASC); } },
          { value: '按名称', action: () => { this.onSort(SORT_NAME); } },
          { value: '按大小', action: () => { this.onSort(SORT_SIZE_DESC); } },
          { value: '手动排序', action: () => { this.onSort(SORT_MANUAL); } }
        ])
    }
    .width(TOP_SORT_W)
    .height(TOP_BTN_H)
  }

  @Builder
  topMoreButton() {
    Stack() {
      this.topButtonGlass()
      Text('⋯')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.c_text2b'))
        .width('100%')
        .height('100%')
        .textAlign(TextAlign.Center)
        .bindMenu([
          { value: '多选管理', action: () => { this.onEnterSelect(); } },
          { value: '沉浸式展示', action: () => { this.onEnterSlideshow(); } },
          { value: '设置…', action: () => { this.onOpenSettings(); } },
          { value: '备份元数据', action: () => { this.onExportBackup(); } },
          { value: '恢复元数据', action: () => { this.onImportBackup(); } }
        ])
    }
    .width(TOP_MORE_W)
    .height(TOP_BTN_H)
  }

  // 顶栏滚动时的模糊半径与底色（配合 .animation 平滑过渡）
  headerBlur(): number {
    return this.headerScrolled ? HEADER_BLUR : 0;
  }

  headerTint(): ResourceColor {
    return this.headerScrolled ? $r('app.color.c_bar_blur') : Color.Transparent;
  }

  sortLabel(): string {
    if (this.sortMode === SORT_TIME_ASC) {
      return '最早';
    }
    if (this.sortMode === SORT_NAME) {
      return '名称';
    }
    if (this.sortMode === SORT_SIZE_DESC) {
      return '大小';
    }
    if (this.sortMode === SORT_MANUAL) {
      return '手动';
    }
    return '最新';
  }

  @Builder
  searchRow() {
    Row() {
      Search({ value: this.keyword, placeholder: '搜索名称或备注' })
        .layoutWeight(1)
        .height(38)
        .backgroundColor($r('app.color.c_searchbg'))
        .borderRadius(19)
        .placeholderColor($r('app.color.c_text3'))
        .placeholderFont({ size: 14 })
        .fontColor($r('app.color.c_text'))
        .onChange((value: string) => {
          this.onKeywordChange(value);
        })
    }
    .width('100%')
    .padding({ left: 16 + this.safeSide, right: 16 + this.safeSide, bottom: 10 })
  }

  // 已进入某分组时的提示条
  @Builder
  activeGroupRow() {
    Row() {
      Text('分组：' + this.groupFilter + '  ✕')
        .fontSize(12)
        .fontColor($r('app.color.c_chip_active_text'))
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.c_chip_active'))
        .borderRadius(14)
        .onClick(() => {
          this.onClearGroup();
        })
      Blank()
    }
    .width('100%')
    .padding({ left: 16 + this.safeSide, right: 16 + this.safeSide, bottom: 8 })
  }
}
