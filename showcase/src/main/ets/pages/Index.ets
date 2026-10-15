import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaItem, MediaType } from '../model/MediaItem';
import { MediaDataSource } from '../model/MediaDataSource';
import { TimelineEntry } from '../model/TimelineEntry';
import { ShowcaseStore, ImportOutcome, ShowcaseSettings } from '../store/ShowcaseStore';
import { emptyState } from '../common/Widgets';
import { effDate, formatDate } from '../common/Format';
import { GalleryViews } from '../views/GalleryViews';
import { ContentViews } from '../views/ContentViews';
import { AlbumViews } from '../views/AlbumViews';
import { BottomNav } from '../views/BottomNav';
import { TopBar } from '../views/TopBar';
import { SettingsSheet } from '../views/SettingsSheet';
import { Overlays } from '../views/Overlays';
import { DetailView } from '../views/DetailView';
import {
  LAYOUT_GRID,
  SORT_TIME_DESC,
  SORT_TIME_ASC,
  SORT_NAME,
  SORT_SIZE_DESC,
  SORT_MANUAL,
  FILTER_ALL,
  FILTER_IMAGE,
  FILTER_VIDEO,
  NAV_COMBO,
  NAV_H,
  NAV_MARGIN,
  PHASE_EXIT_WAIT_MS,
  PHASE_SWAP_GAP_MS,
  PHASE_ENTER_MS,
  LAYOUT_SWITCH_MS,
  isGalleryLayout,
} from '../common/Constants';

@Entry
@Component
struct Index {
  // 全量数据（真源）
  @State allItems: MediaItem[] = [];
  // 当前展示列表（= 全量经过筛选+排序）
  @State items: MediaItem[] = [];

  @State layoutMode: number = LAYOUT_GRID;
  @State sortMode: number = SORT_TIME_DESC;
  // 导航选中态（点击立即变化，驱动指示块滑动）
  @State filterMode: number = FILTER_ALL;
  // 内容实际使用的筛选（滞后于 filterMode 一拍，用于编排切换过渡）
  @State contentFilter: number = FILTER_ALL;
  // 内容过渡阶段：0 稳定，1 旧内容左右退场，2 新内容自下而上补位
  @State contentPhase: number = 0;
  // 过渡的忙碌截止时刻（Date.now() 毫秒）。contentPhase 在换完数据 16ms 后就归 0，
  // 而补位动画还要再播 240ms —— 只看 contentPhase 会把"动画仍在播"当成"已稳定"，
  // 于是连点时每一拍都重新退场一次，补位永远走不完，看着就是点快了卡住
  private switchBusyUntil: number = 0;
  // 排布切换的忙碌截止时刻：连点排布时不再每次重播淡入
  private layoutBusyUntil: number = 0;
  // 连续快速切换时的令牌，只有最后一次生效
  private switchToken: number = 0;
  // 内容切换编排的定时器句柄：新一次切换先取消上一次，避免定时器堆积
  private switchTimer1: number = -1;
  private switchTimer2: number = -1;
  // 设置落盘防抖的定时器句柄
  private settingsTimer: number = -1;


  @State selectedIndex: number = -1;
  // 信息卡片读取的索引：在滑动动画一开始就更新，不必等切换动画播完
  @State detailIndex: number = -1;
  @State importing: boolean = false;
  @State autoPlay: boolean = false;

  // 时间轴条目缓存（由 refresh() 重建，交给画廊视图组件渲染）
  @State timeline: TimelineEntry[] = [];

  // 多选
  @State selectMode: boolean = false;
  @State selectedIds: string[] = [];

  // 搜索
  @State keyword: string = '';

  // 分组（空串 = 全部分组）
  @State groupFilter: string = '';

  // 沉浸式展示
  @State slideshow: boolean = false;
  @State slideIndex: number = 0;

  // 分组编辑弹层
  @State groupEditing: boolean = false;
  @State groupDraft: string = '';
  // 现有分组名（供 chips 渲染，refresh 时重算，保证能刷新）
  @State groups: string[] = [];

  // 顶栏：内容是否已滚离顶部（毛玻璃渐入）/ 顶栏实测高度（内容区让位）
  @State headerScrolled: boolean = false;
  @State headerHeight: number = 96;

  // 设置
  @State settingsOpen: boolean = false;
  @State columns: number = 3;
  @State slideInterval: number = 3;
  // 主题：0 跟随系统，1 浅色，2 深色
  @State theme: number = 0;

  // 详情编辑态
  @State nameDraft: string = '';
  @State editingName: boolean = false;
  @State remarkDraft: string = '';
  @State remarkEditing: boolean = false;
  @State detailFavorite: boolean = false;

  // 详情缩放手势
  @State scaleValue: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;

  private ds: MediaDataSource = new MediaDataSource();
  private swiperController: SwiperController = new SwiperController();
  private videoController: VideoController = new VideoController();
  private slideVideo: VideoController = new VideoController();

  // 沉浸式：安全区（状态栏 / 导航栏）高度，vp
  @State safeTop: number = 0;
  @State safeBottom: number = 0;
  /** 横屏时刘海在侧边，必须另外避让左右 */
  @State safeLeft: number = 0;
  @State safeRight: number = 0;

  // ---------- 横竖屏 ----------
  /** 是否横屏。判据用宽高比而不是绝对宽高，折叠屏展开、平板分屏也能正确识别 */
  @State isLandscape: boolean = false;
  /** 根容器实测尺寸：横屏时要按实际宽高推算列数、压缩各种留白 */
  @State viewWidth: number = 0;
  @State viewHeight: number = 0;

  aboutToAppear(): void {
    this.initStore();
    this.initInsets();
  }

  aboutToDisappear(): void {
    // 退出前把防抖窗口内待写的设置落盘，避免丢失
    if (this.settingsTimer >= 0) {
      clearTimeout(this.settingsTimer);
      this.settingsTimer = -1;
      this.flushSettings();
    }
  }

  // 全屏布局下系统不自动避让，这里读取安全区用于内边距。
  // 四个方向都要读：竖屏靠 top/bottom 避让状态栏与手势条，
  // 横屏时刘海跑到侧边、top/bottom 会归零，就得靠 left/right。
  // 旋转后必须重算，所以横竖屏切换时也会再调一次。
  async initInsets(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(ctx);
      const avoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const ui = this.getUIContext();
      this.safeTop = ui.px2vp(avoid.topRect.height);
      this.safeBottom = ui.px2vp(avoid.bottomRect.height);
      this.safeLeft = ui.px2vp(avoid.leftRect.width);
      this.safeRight = ui.px2vp(avoid.rightRect.width);
    } catch (err) {
      this.safeTop = 0;
      this.safeBottom = 0;
      this.safeLeft = 0;
      this.safeRight = 0;
    }
  }

  /** 横屏下要避让的侧边留白。取左右较大的一边，两侧对称处理 */
  safeSide(): number {
    if (!this.isLandscape) {
      return 0;
    }
    return this.safeLeft > this.safeRight ? this.safeLeft : this.safeRight;
  }

  onBackPress(): boolean {
    if (this.settingsOpen) {
      this.closeSettings();
      return true;
    }
    if (this.groupEditing) {
      this.closeGroupEditor();
      return true;
    }
    if (this.slideshow) {
      this.exitSlideshow();
      return true;
    }
    if (this.selectedIndex >= 0) {
      this.closeDetail();
      return true;
    }
    if (this.selectMode) {
      this.exitSelectMode();
      return true;
    }
    return false;
  }

  async initStore(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const settings: ShowcaseSettings = await ShowcaseStore.loadSettings(context);
    this.layoutMode = settings.layoutMode ? settings.layoutMode : 0;
    this.sortMode = settings.sortMode ? settings.sortMode : 0;
    this.filterMode = settings.filterMode ? settings.filterMode : 0;
    this.contentFilter = this.filterMode;
    this.groupFilter = settings.group ? settings.group : '';
    this.autoPlay = settings.autoPlay === true;
    this.columns = settings.columns ? settings.columns : 3;
    this.slideInterval = settings.slideInterval ? settings.slideInterval : 3;
    this.theme = settings.theme ? settings.theme : 0;
    this.applyTheme();
    const loaded: MediaItem[] = await ShowcaseStore.load(context);
    this.allItems = loaded;
    // 回填必须赶在首屏之前。它原本是个不 await 的后台任务，跑完再 refresh()，
    // 而那次 refresh 会走 ds.notifyReload() —— LazyForEach 全表重建、Swiper 的
    // 槽位被整体换掉。如果用户这时正在展台里滑，画面内容就会「突然瞬移」。
    // 耗时只跟「缺宽高 / 缺封面」的老数据条数有关：新导入的项在导入时就写好了，
    // 这里会被逐条快速跳过，所以正常情况下几乎不增加启动时间。
    await this.runBackfill(context);
    this.refresh();
    this.startThumbUpgrade();
  }

  // ---------- 老缩略图按批升档（640 → 1280）----------
  // 放在首屏之后：重编一张要几十毫秒，上千张一次跑完会把启动路径堵死。
  // 每批之间让出事件循环，跑完即止；中途退出则由文件名后缀判断，下次启动接着来。

  startThumbUpgrade(): void {
    setTimeout(() => {
      this.runThumbUpgradeBatch();
    }, 1200);
  }

  async runThumbUpgradeBatch(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const batch: number = 4;
      const done: number = await ShowcaseStore.upgradeThumbs(context, this.allItems, batch);
      if (done >= batch) {
        setTimeout(() => {
          this.runThumbUpgradeBatch();
        }, 300);
      }
    } catch (err) {
      // 升档是后台优化，出问题不能影响主流程；剩下的批次下次启动继续
      hilog.warn(0x1001, 'TopShowcase', 'thumb upgrade batch failed: %{public}s', JSON.stringify(err));
    }
  }

  // 主题：跟随系统 / 强制浅色 / 强制深色
  applyTheme(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (this.theme === 1) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else if (this.theme === 2) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      context.getApplicationContext().setColorMode(mode);
    } catch (err) {
      // 主题切换失败时保持系统默认，不打断使用
    }
  }

  // 记住界面设置（布局/排序/筛选/分组/自动轮播/列数/幻灯片间隔/主题）
  // 做 400ms 防抖：连续点击/滑动只落盘一次，避免频繁 preferences IO 造成响应变慢
  async persistSettings(): Promise<void> {
    if (this.settingsTimer >= 0) {
      clearTimeout(this.settingsTimer);
    }
    this.settingsTimer = setTimeout(() => {
      this.settingsTimer = -1;
      this.flushSettings();
    }, 400);
  }

  /** 立即把设置写入 Preferences。 */
  async flushSettings(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const s: ShowcaseSettings = {
      layoutMode: this.layoutMode,
      sortMode: this.sortMode,
      filterMode: this.filterMode,
      group: this.groupFilter,
      autoPlay: this.autoPlay,
      columns: this.columns,
      slideInterval: this.slideInterval,
      theme: this.theme
    };
    await ShowcaseStore.saveSettings(context, s);
  }

  // ---------- 备份与恢复 ----------

  async onExportBackup(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const msg: string = await ShowcaseStore.exportBackup(context, this.allItems);
    this.showToast(msg);
  }

  async onImportBackup(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const outcome: ImportOutcome = await ShowcaseStore.importBackup(context, this.allItems);
    this.allItems = outcome.items;
    this.refresh();
    this.showToast(outcome.message);
  }

  // 回填老数据的宽高与视频封面。调用方必须在首屏渲染之前 await 它：
  // 回填会改 dateTaken，进而影响排序，所以它之后确实需要一次 refresh；
  // 把这次 refresh 留在调用链末尾，就能保证全程只重建一次列表。
  async runBackfill(context: common.UIAbilityContext): Promise<void> {
    this.allItems = await ShowcaseStore.backfill(context, this.allItems);
  }

  // 依据 allItems + 筛选 + 分组 + 搜索 + 排序，重建展示列表
  // 注意：用 contentFilter 而不是 filterMode，切换类型时可以先把旧内容动画送走再换数据
  refresh(): void {
    let list: MediaItem[] = this.allItems.slice();
    if (this.contentFilter === FILTER_IMAGE) {
      list = list.filter((it: MediaItem) => it.type === MediaType.IMAGE);
    } else if (this.contentFilter === FILTER_VIDEO) {
      list = list.filter((it: MediaItem) => it.type === MediaType.VIDEO);
    }
    if (this.groupFilter.length > 0) {
      const g: string = this.groupFilter;
      list = list.filter((it: MediaItem) => it.group === g);
    }
    const kw: string = this.keyword.trim().toLowerCase();
    if (kw.length > 0) {
      list = list.filter((it: MediaItem) => this.matchKeyword(it, kw));
    }
    if (this.sortMode !== SORT_MANUAL) {
      list.sort((a: MediaItem, b: MediaItem) => this.compareItems(a, b));
    }
    this.items = list;
    this.ds.setItems(list);
    this.ds.notifyReload();
    this.groups = this.uniqueGroups();
    // 时间轴排布需要按日期重新分段
    this.rebuildTimeline();
  }

  // 设置页的统计口径：按类型统计全量藏品
  countImages(): number {
    let n: number = 0;
    for (let i = 0; i < this.allItems.length; i++) {
      if (this.allItems[i].type === MediaType.IMAGE) {
        n++;
      }
    }
    return n;
  }

  countVideos(): number {
    let n: number = 0;
    for (let i = 0; i < this.allItems.length; i++) {
      if (this.allItems[i].type === MediaType.VIDEO) {
        n++;
      }
    }
    return n;
  }

  matchKeyword(item: MediaItem, kw: string): boolean {
    if (item.displayName.toLowerCase().indexOf(kw) >= 0) {
      return true;
    }
    if (item.remark.toLowerCase().indexOf(kw) >= 0) {
      return true;
    }
    return false;
  }

  // 只按所选方式排序；收藏不参与排序，任何排布下都不置顶
  compareItems(a: MediaItem, b: MediaItem): number {
    if (this.sortMode === SORT_TIME_ASC) {
      return effDate(a) - effDate(b);
    }
    if (this.sortMode === SORT_NAME) {
      if (a.displayName < b.displayName) {
        return -1;
      }
      if (a.displayName > b.displayName) {
        return 1;
      }
      return 0;
    }
    if (this.sortMode === SORT_SIZE_DESC) {
      return b.size - a.size;
    }
    return effDate(b) - effDate(a);
  }

  // ---------- 导入 / 删除 ----------

  async onImport(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const outcome: ImportOutcome = await ShowcaseStore.importFromPicker(context, this.allItems);
      this.allItems = outcome.items;
      this.refresh();
      this.showToast(outcome.message);
    } catch (err) {
      this.showToast('导入异常');
    } finally {
      this.importing = false;
    }
  }

  async onDeleteSingle(): Promise<void> {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.items.length) {
      return;
    }
    const id: string = this.items[this.selectedIndex].id;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.allItems = await ShowcaseStore.deleteMany(context, [id], this.allItems);
    this.selectedIndex = -1;
    this.refresh();
    this.showToast('已删除');
  }

  async onDeleteSelected(): Promise<void> {
    if (this.selectedIds.length === 0) {
      return;
    }
    const ids: string[] = this.selectedIds.slice();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.allItems = await ShowcaseStore.deleteMany(context, ids, this.allItems);
    this.selectedIds = [];
    this.selectMode = false;
    this.refresh();
    this.showToast('已删除 ' + ids.length.toString() + ' 件');
  }

  // ---------- 多选 ----------

  enterSelectMode(): void {
    this.selectedIds = [];
    this.ds.notifyReload();
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
      this.selectMode = true;
    });
  }

  exitSelectMode(): void {
    this.selectedIds = [];
    this.ds.notifyReload();
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseIn }, () => {
      this.selectMode = false;
    });
  }

  toggleSelect(id: string): void {
    const idx: number = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      const next: string[] = this.selectedIds.slice();
      next.splice(idx, 1);
      this.selectedIds = next;
    } else {
      this.selectedIds = this.selectedIds.concat([id]);
    }
    this.ds.notifyChange(this.indexOfItem(id));
  }

  indexOfItem(id: string): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  onLongPress(id: string): void {
    if (!this.selectMode) {
      this.selectedIds = [id];
      this.ds.notifyReload();
      this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
        this.selectMode = true;
      });
    } else {
      this.toggleSelect(id);
    }
  }

  isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  // ---------- 排序 / 筛选 ----------

  setSort(mode: number): void {
    if (this.sortMode === mode) {
      return;
    }
    this.sortMode = mode;
    this.selectedIndex = -1;
    this.refresh();
    this.persistSettings();
  }

  // 列表拖动排序：把 from 位置的藏品移动到 to 位置，并切换为手动排序
  moveManual(from: number, to: number): void {
    if (from < 0 || from >= this.items.length) {
      return;
    }
    if (to < 0 || to >= this.items.length) {
      return;
    }
    const movedId: string = this.items[from].id;
    const targetId: string = this.items[to].id;
    const all: MediaItem[] = this.allItems.slice();
    let moved: MediaItem | null = null;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === movedId) {
        moved = all[i];
        all.splice(i, 1);
        break;
      }
    }
    if (moved === null) {
      return;
    }
    let targetPos: number = all.length;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === targetId) {
        targetPos = i;
        break;
      }
    }
    if (to > from) {
      targetPos = targetPos + 1;
    }
    all.splice(targetPos, 0, moved);
    this.allItems = all;
    this.sortMode = SORT_MANUAL;
    this.refresh();
    this.persistSettings();
    this.persistItems();
  }

  async persistItems(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ShowcaseStore.persist(context, this.allItems);
  }

  // ---------- 分享 ----------

  async onShareItem(): Promise<void> {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.items.length) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const msg: string = await ShowcaseStore.shareItems(context, [this.items[this.selectedIndex]]);
    if (msg.length > 0) {
      this.showToast(msg);
    }
  }

  async onShareSelected(): Promise<void> {
    if (this.selectedIds.length === 0) {
      return;
    }
    const chosen: MediaItem[] = [];
    for (let i = 0; i < this.allItems.length; i++) {
      if (this.selectedIds.indexOf(this.allItems[i].id) >= 0) {
        chosen.push(this.allItems[i]);
      }
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const msg: string = await ShowcaseStore.shareItems(context, chosen);
    if (msg.length > 0) {
      this.showToast(msg);
    }
  }

  setFilter(mode: number): void {
    if (this.filterMode === mode) {
      return;
    }
    // 导航选中态立即变化：指示块先滑过去
    this.filterMode = mode;
    this.selectedIndex = -1;
    this.persistSettings();
    // 内容随后：旧内容左右分侧退场，新内容自下而上补位
    this.playContentSwitch(mode);
  }

  // 内容切换过渡编排：分三拍，避免数据替换与位移动画互相打架
  playContentSwitch(mode: number): void {
    this.switchToken++;
    const token: number = this.switchToken;
    // 先取消上一次未完成的编排，否则连点会不断堆积定时器
    if (this.switchTimer1 >= 0) {
      clearTimeout(this.switchTimer1);
      this.switchTimer1 = -1;
    }
    if (this.switchTimer2 >= 0) {
      clearTimeout(this.switchTimer2);
      this.switchTimer2 = -1;
    }

    // 上一次过渡还没播完（退场 + 补位整段）：只换数据，不重播退场。
    // 这时内容本来就在往"稳定"走，直接换数据出来就是最快的反馈；
    // 再退场一次只会把补位从头开始，连点就会一直卡在半透明状态
    if (Date.now() < this.switchBusyUntil) {
      this.contentPhase = 0;
      this.contentFilter = mode;
      this.refresh();
      // 连点期间维持忙碌：每一下都走"直接换"，直到用户停下来
      this.switchBusyUntil = Date.now() + PHASE_ENTER_MS;
      return;
    }

    // 第一拍：旧内容按奇偶分左右退场（PHASE_EXIT_WAIT_MS 后就让新内容接手，尽量压缩点击到内容的延迟）
    this.switchBusyUntil = Date.now() + PHASE_EXIT_WAIT_MS + PHASE_SWAP_GAP_MS + PHASE_ENTER_MS;
    this.contentPhase = 1;
    this.switchTimer1 = setTimeout(() => {
      this.switchTimer1 = -1;
      if (token !== this.switchToken) {
        return;
      }
      // 第二拍：换数据，新内容先落在下方并隐藏
      this.contentPhase = 2;
      this.contentFilter = mode;
      this.refresh();
      this.switchTimer2 = setTimeout(() => {
        this.switchTimer2 = -1;
        if (token !== this.switchToken) {
          return;
        }
        // 第三拍：自下而上补位
        this.contentPhase = 0;
      }, PHASE_SWAP_GAP_MS);
    }, PHASE_EXIT_WAIT_MS);
  }

  setGroupFilter(group: string): void {
    this.groupFilter = group;
    this.selectedIndex = -1;
    this.refresh();
    this.persistSettings();
  }

  // 现有分组名（去重 + 排序）
  uniqueGroups(): string[] {
    const result: string[] = [];
    for (let i = 0; i < this.allItems.length; i++) {
      const g: string = this.allItems[i].group;
      if (g.length > 0 && result.indexOf(g) < 0) {
        result.push(g);
      }
    }
    result.sort((a: string, b: string) => {
      if (a < b) {
        return -1;
      }
      if (a > b) {
        return 1;
      }
      return 0;
    });
    return result;
  }

  openGroupEditor(): void {
    if (this.selectMode) {
      this.groupDraft = '';
    } else if (this.selectedIndex >= 0 && this.selectedIndex < this.items.length) {
      this.groupDraft = this.items[this.selectedIndex].group;
    } else {
      return;
    }
    this.groupEditing = true;
  }

  closeGroupEditor(): void {
    this.groupEditing = false;
  }

  async applyGroup(): Promise<void> {
    const name: string = this.groupDraft.trim();
    if (this.selectMode) {
      if (this.selectedIds.length === 0) {
        this.groupEditing = false;
        return;
      }
      for (let i = 0; i < this.allItems.length; i++) {
        if (this.selectedIds.indexOf(this.allItems[i].id) >= 0) {
          this.allItems[i].group = name;
        }
      }
    } else if (this.selectedIndex >= 0 && this.selectedIndex < this.items.length) {
      this.items[this.selectedIndex].group = name;
    } else {
      this.groupEditing = false;
      return;
    }
    this.groupEditing = false;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ShowcaseStore.persist(context, this.allItems);
    if (this.selectMode) {
      this.exitSelectMode();
    }
    this.refresh();
    this.showToast(name.length > 0 ? '已移入「' + name + '」' : '已移出分组');
  }

  // ---------- 沉浸式展示 ----------

  enterSlideshow(): void {
    if (this.items.length === 0) {
      this.showToast('没有可展示的藏品');
      return;
    }
    this.slideIndex = 0;
    this.slideshow = true;
  }

  exitSlideshow(): void {
    try {
      this.slideVideo.stop();
    } catch (err) {
    }
    this.slideshow = false;
  }

  // ---------- 详情 ----------

  onCardTap(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    if (this.selectMode) {
      this.toggleSelect(this.items[index].id);
      return;
    }
    this.openDetail(index);
  }

  openDetail(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    this.syncDetail(index);
    this.detailIndex = index;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.selectedIndex = index;
    });
  }

  // 详情左右滑切换页面时，重算草稿与缩放
  onDetailPageChange(index: number): void {
    // 只有上一页确实是视频时才需要停止播放，避免每次切页都做一次解码器停止
    const prev: number = this.selectedIndex;
    if (prev >= 0 && prev < this.items.length && this.items[prev].type === MediaType.VIDEO) {
      try {
        this.videoController.stop();
      } catch (err) {
      }
    }
    this.selectedIndex = index;
    this.detailIndex = index;
    this.syncDetail(index);
  }

  syncDetail(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    const item: MediaItem = this.items[index];
    this.nameDraft = item.displayName;
    this.remarkDraft = item.remark;
    this.editingName = false;
    this.remarkEditing = false;
    this.detailFavorite = item.favorite;
    this.resetZoom();
  }

  resetZoom(): void {
    this.scaleValue = 1;
    this.offsetX = 0;
    this.offsetY = 0;
  }

  closeDetail(): void {
    // 关闭前先停止视频，避免退出后声音继续
    try {
      this.videoController.stop();
    } catch (err) {
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.selectedIndex = -1;
    });
    this.refresh();
  }

  async saveName(): Promise<void> {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.items.length) {
      return;
    }
    const name: string = this.nameDraft.trim();
    if (name.length === 0) {
      this.showToast('名称不能为空');
      return;
    }
    this.items[this.selectedIndex].displayName = name;
    this.nameDraft = name;
    this.editingName = false;
    this.ds.notifyChange(this.selectedIndex);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ShowcaseStore.persist(context, this.allItems);
    this.showToast('已重命名');
  }

  async saveRemark(): Promise<void> {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.items.length) {
      return;
    }
    const text: string = this.remarkDraft;
    this.items[this.selectedIndex].remark = text;
    this.remarkEditing = false;
    this.ds.notifyChange(this.selectedIndex);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ShowcaseStore.persist(context, this.allItems);
    this.showToast('已保存备注');
  }

  async toggleDetailFavorite(): Promise<void> {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.items.length) {
      return;
    }
    const item: MediaItem = this.items[this.selectedIndex];
    item.favorite = !item.favorite;
    this.detailFavorite = item.favorite;
    this.ds.notifyChange(this.selectedIndex);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ShowcaseStore.persist(context, this.allItems);
  }

  // ---------- 工具 ----------

  showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      // 提示失败不影响主流程
    }
  }

  // ForEach key 里带上会变化的字段，保证重命名/收藏/选中/回填宽高后能刷新
  // 渲染列表由 MediaDataSource 驱动（LazyForEach），无需 key 生成器
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 沉浸式背景：延伸到状态栏 / 导航栏之下（内容仍留在安全区内）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.c_bg'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 内容区：顶部让位由各滚动容器的 contentStartOffset 负责，
      // 这样内容可以滚到顶栏下方，顶栏毛玻璃才有内容可糊
      Column() {
        if (this.allItems.length === 0) {
          emptyState('还没有藏品', '点击右下角「＋」添加照片或视频');
        } else if (this.contentFilter === NAV_COMBO) {
          // 组合视图：按分组浏览，形态跟随排布设置
          AlbumViews({
            groups: $groups,
            allItems: $allItems,
            layoutMode: this.layoutMode,
            contentPhase: this.contentPhase,
            headerHeight: this.headerHeight,
            contentPad: this.navContentPad(),
            columns: this.effectiveColumns(),
            navBlock: this.navBlockH(),
            onOpenGroup: (name: string) => {
              this.groupFilter = name;
              this.setFilter(FILTER_ALL);
            },
            onScroll: (first: number) => {
              this.onContentScrollIndex(first);
            }
          })
        } else if (this.items.length === 0) {
          emptyState('没有符合条件的藏品', '试试换个关键词或筛选条件');
        } else if (isGalleryLayout(this.layoutMode)) {
          // 四种画廊排布整体交给独立组件，只注入数据与交互回调
          GalleryViews({
            ds: this.ds,
            items: $items,
            timeline: $timeline,
            layoutMode: this.layoutMode,
            contentPhase: this.contentPhase,
            headerHeight: this.headerHeight,
            contentPad: this.navContentPad(),
            navBlock: this.navBlockH(),
            isLandscape: this.isLandscape,
            onCardTap: (index: number) => {
              this.onCardTap(index);
            },
            onLongPress: (id: string) => {
              this.onLongPress(id);
            },
            onScroll: (first: number) => {
              this.onContentScrollIndex(first);
            }
          })
        } else {
          // 常规四种排布同样交给独立组件
          ContentViews({
            ds: this.ds,
            items: $items,
            autoPlay: $autoPlay,
            layoutMode: this.layoutMode,
            contentPhase: this.contentPhase,
            headerHeight: this.headerHeight,
            contentPad: this.navContentPad(),
            navBlock: this.navBlockH(),
            columns: this.effectiveColumns(),
            selectMode: this.selectMode,
            slideInterval: this.slideInterval,
            onCardTap: (index: number) => {
              this.onCardTap(index);
            },
            onLongPress: (id: string) => {
              this.onLongPress(id);
            },
            onScroll: (first: number) => {
              this.onContentScrollIndex(first);
            },
            isSelected: (id: string) => this.isSelected(id),
            onMoveItem: (from: number, to: number) => {
              this.moveManual(from, to);
            },
            onToggleAutoPlay: () => {
              this.persistSettings();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      // 横屏时刘海在侧边，内容要避开；竖屏 safeSide() 返回 0，等于不加
      .padding({ left: this.safeSide(), right: this.safeSide() })
      // 内容延伸到屏幕最底部（含手势条安全区），
      // 底部导航和它下方的安全区压着的都是展品，玻璃才真正透得出来
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      // 顶栏浮层：内容滚动时毛玻璃渐入
      TopBar({
        itemCount: this.items.length,
        selectedCount: this.selectedIds.length,
        safeTop: this.safeTop,
        headerScrolled: this.headerScrolled,
        keyword: this.keyword,
        selectMode: this.selectMode,
        sortMode: this.sortMode,
        groupFilter: this.groupFilter,
        safeSide: this.safeSide(),
        onHeightChange: (h: number) => {
          this.headerHeight = h;
        },
        onKeywordChange: (kw: string) => {
          this.keyword = kw;
          this.refresh();
        },
        onSort: (mode: number) => {
          this.setSort(mode);
        },
        onEnterSelect: () => {
          this.enterSelectMode();
        },
        onExitSelect: () => {
          this.exitSelectMode();
        },
        onEnterSlideshow: () => {
          this.enterSlideshow();
        },
        onOpenSettings: () => {
          this.settingsOpen = true;
        },
        onExportBackup: () => {
          this.onExportBackup();
        },
        onImportBackup: () => {
          this.onImportBackup();
        },
        onClearGroup: () => {
          this.setGroupFilter('');
        }
      })

      if (!this.selectMode) {
        BottomNav({
          layoutMode: this.layoutMode,
          filterMode: this.filterMode,
          safeBottom: this.safeBottom,
          isLandscape: this.isLandscape,
          safeSide: this.safeSide(),
          importing: this.importing,
          onSwitchLayout: (mode: number) => {
            this.switchLayout(mode);
          },
          onFilterChange: (mode: number) => {
            this.setFilter(mode);
          },
          onImport: () => {
            this.onImport();
          }
        })
      }

      // 覆盖层：多选底栏 / 沉浸式幻灯片 / 分组编辑
      Overlays({
        slideIndex: $slideIndex,
        items: $items,
        groups: $groups,
        groupDraft: $groupDraft,
        ds: this.ds,
        slideVideo: this.slideVideo,
        slideInterval: this.slideInterval,
        safeTop: this.safeTop,
        safeBottom: this.safeBottom,
        safeSide: this.safeSide(),
        selectedCount: this.selectedIds.length,
        showSelectBar: this.selectMode,
        showSlideshow: this.slideshow && this.items.length > 0,
        showGroupEditor: this.groupEditing,
        exitSlideshow: () => {
          this.exitSlideshow();
        },
        applyGroup: () => {
          this.applyGroup();
        },
        closeGroupEditor: () => {
          this.closeGroupEditor();
        },
        onDeleteSelected: () => {
          this.onDeleteSelected();
        },
        onShareSelected: () => {
          this.onShareSelected();
        },
        openGroupEditor: () => {
          this.openGroupEditor();
        }
      })

      if (this.selectedIndex >= 0 && this.selectedIndex < this.items.length) {
        DetailView({
          items: $items,
          selectedIndex: $selectedIndex,
          detailIndex: $detailIndex,
          nameDraft: $nameDraft,
          remarkDraft: $remarkDraft,
          editingName: $editingName,
          remarkEditing: $remarkEditing,
          detailFavorite: $detailFavorite,
          scaleValue: $scaleValue,
          offsetX: $offsetX,
          offsetY: $offsetY,
          ds: this.ds,
          videoController: this.videoController,
          safeTop: this.safeTop,
          safeBottom: this.safeBottom,
          isLandscape: this.isLandscape,
          safeSide: this.safeSide(),
          closeDetail: () => {
            this.closeDetail();
          },
          onDetailPageChange: (index: number) => {
            this.onDetailPageChange(index);
          },
          saveName: () => {
            this.saveName();
          },
          saveRemark: () => {
            this.saveRemark();
          },
          toggleDetailFavorite: () => {
            this.toggleDetailFavorite();
          },
          onDeleteSingle: () => {
            this.onDeleteSingle();
          },
          onShareItem: () => {
            this.onShareItem();
          },
          openGroupEditor: () => {
            this.openGroupEditor();
          },
          resetZoom: () => {
            this.resetZoom();
          }
        })
      }

      if (this.settingsOpen) {
        SettingsSheet({
          safeTop: this.safeTop,
          safeBottom: this.safeBottom,
          safeSide: this.safeSide(),
          columns: this.columns,
          slideInterval: this.slideInterval,
          autoPlay: this.autoPlay,
          theme: this.theme,
          itemCount: this.allItems.length,
          imageCount: this.countImages(),
          videoCount: this.countVideos(),
          groupCount: this.groups.length,
          onClose: () => {
            this.closeSettings();
          },
          onSetColumns: (n: number) => {
            this.columns = n;
            this.persistSettings();
          },
          onSetInterval: (sec: number) => {
            this.slideInterval = sec;
            this.persistSettings();
          },
          onToggleAutoPlay: (on: boolean) => {
            this.autoPlay = on;
            this.persistSettings();
          },
          onApplyTheme: (t: number) => {
            this.theme = t;
            this.applyTheme();
            this.persistSettings();
          },
          onExportBackup: () => {
            this.onExportBackup();
          },
          onImportBackup: () => {
            this.onImportBackup();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    // 横竖屏判定：旋转、折叠屏展开、平板分屏都会走到这里
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w = newArea.width;
      const h = newArea.height;
      if (typeof w === 'number' && w > 0) {
        this.viewWidth = w;
      }
      if (typeof h === 'number' && h > 0) {
        this.viewHeight = h;
      }
      const land: boolean = this.viewWidth > 0 && this.viewHeight > 0 && this.viewWidth > this.viewHeight;
      if (land !== this.isLandscape) {
        this.isLandscape = land;
        // 旋转后安全区会换方向（刘海从顶部挪到侧边），必须重算一次
        this.initInsets();
      }
    })
  }

  /**
   * 网格列数。竖屏沿用用户设置；横屏按「每格不小于 108vp」自动推算 ——
   * 屏宽翻倍后还用 3 列，每个格子会宽得离谱，图片反而显得小。
   */
  effectiveColumns(): number {
    if (!this.isLandscape || this.viewWidth <= 0) {
      return this.columns;
    }
    let n: number = Math.floor(this.viewWidth / 108);
    if (n < 3) {
      n = 3;
    }
    if (n > 7) {
      n = 7;
    }
    return n;
  }

  // 内容滚离顶部时切换顶栏毛玻璃（first > 0 即已滚动）
  onContentScrollIndex(first: number): void {
    const scrolled: boolean = first > 0;
    if (scrolled !== this.headerScrolled) {
      this.headerScrolled = scrolled;
    }
  }



  // 底部导航底边距（避开手势条）
  navBottomMargin(): number {
    return NAV_MARGIN + this.safeBottom;
  }

  // 内容底部让出的高度 = 底部导航总高
  // 内容正好能滚到导航上沿，滚动过程中会从导航下方穿过（导航是玻璃材质，能透出展品）
  navBlockH(): number {
    return NAV_H + this.navBottomMargin();
  }

  // 滚动排布的内容底边：直接铺到屏幕最底部
  // 这样整条底部导航（含胶囊下方的安全区）压着的都是展品，玻璃透出来的不是页面底色
  // 注意：代价是滚到底时最后一行会被导航盖住
  navContentPad(): number {
    return 0;
  }

  switchLayout(mode: number): void {
    if (this.layoutMode === mode) {
      return;
    }
    // 上一次切换的淡入还没播完就再点：直接换，不再套一层动画。
    // 套着 animateTo 换排布会让新内容重新走一次淡入，连点排布时内容一直在
    // 淡出/淡入之间来回闪，看着就是卡住；不套动画则是立刻换过来，响应更快
    if (Date.now() < this.layoutBusyUntil) {
      this.layoutMode = mode;
    } else {
      this.getUIContext().animateTo({ duration: LAYOUT_SWITCH_MS, curve: Curve.EaseInOut }, () => {
        this.layoutMode = mode;
      });
    }
    this.layoutBusyUntil = Date.now() + LAYOUT_SWITCH_MS;
    this.persistSettings();
  }

  // 按日期分段重建时间轴条目：日期头 + 左右交错的照片
  rebuildTimeline(): void {
    const list: TimelineEntry[] = [];
    let last: string = '';
    let side: number = 0;
    for (let i = 0; i < this.items.length; i++) {
      const it: MediaItem = this.items[i];
      const day: string = formatDate(effDate(it));
      if (day !== last) {
        last = day;
        list.push(new TimelineEntry(0, day, -1, 0));
        side = 0;
      }
      list.push(new TimelineEntry(1, '', i, side));
      side = side === 0 ? 1 : 0;
    }
    this.timeline = list;
  }

  closeSettings(): void {
    this.settingsOpen = false;
  }
}
