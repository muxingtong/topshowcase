import { MediaItem } from './MediaItem';

/**
 * LazyForEach 数据源：只构建可见区域的卡片，规模大时避免一次性渲染全部。
 * 数据变化通过 notifyReload()（整表）/ notifyChange(index)（单项）通知。
 */
export class MediaDataSource implements IDataSource {
  private items: MediaItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): MediaItem {
    const n: number = this.items.length;
    if (n === 0) {
      return this.items[index];
    }
    // Swiper 在 loop 模式下会向两侧多要一格做缓冲，索引可能落到 [-1, n]。
    // 直接取会拿到 undefined，那一格瞬间空白再补上，看起来就是内容瞬移。
    // 折回有效范围即可：对正常索引是个恒等变换，不影响其他排布。
    return this.items[((index % n) + n) % n];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i: number = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  /** 替换底层数组（不触发通知）。 */
  setItems(list: MediaItem[]): void {
    this.items = list;
  }

  /** 整表刷新：排序/筛选/导入/删除后调用。 */
  notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 单项刷新：收藏/选中/重命名等只影响一条的改动。 */
  notifyChange(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }
}
