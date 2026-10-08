/**
 * 时间轴条目：日期分组头，或挂在轴上的一张照片。
 * 时间轴排布把扁平列表按日期切成"头 + 照片"的序列，渲染时逐行取用。
 */
export class TimelineEntry {
  /** 0 = 日期头，1 = 照片 */
  kind: number = 1;
  /** 日期头的文案（kind 为 0 时有效） */
  title: string = '';
  /** 在 items 中的下标（kind 为 1 时有效） */
  index: number = -1;
  /** 挂在轴的哪一侧：0 左，1 右 */
  side: number = 0;

  constructor(kind: number, title: string, index: number, side: number) {
    this.kind = kind;
    this.title = title;
    this.index = index;
    this.side = side;
  }
}
