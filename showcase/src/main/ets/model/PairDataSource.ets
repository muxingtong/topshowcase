import { MediaItem } from './MediaItem';

/**
 * 成对数据源：把 [a, b, c, d, ...] 暴露成 [[a,b], [c,d], ...] 这样的「行」。
 *
 * 透视长廊要把两侧的画框摆成并排的一行两张，而 LazyForEach 是按「条」索引的，
 * 没法在渲染层把两条合成一行 —— 所以得在数据源这一层先切好行。
 * 奇数张时最后一行只有左边一张，右侧留空。
 */
export class PairDataSource implements IDataSource {
  private rows: MediaItem[][] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): MediaItem[] {
    const n: number = this.rows.length;
    if (n === 0) {
      return this.rows[index];
    }
    return this.rows[((index % n) + n) % n];
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

  /** 按两两一组重切行。奇数张的那一行只有左边一张。 */
  setItems(list: MediaItem[]): void {
    const rows: MediaItem[][] = [];
    for (let i = 0; i < list.length; i += 2) {
      const row: MediaItem[] = [list[i]];
      if (i + 1 < list.length) {
        row.push(list[i + 1]);
      }
      rows.push(row);
    }
    this.rows = rows;
  }

  notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
