import { MediaItem } from '../model/MediaItem';

/**
 * 展示用格式化与时间取值。抽成纯函数供各视图组件复用。
 */

/** 有效时间：优先拍摄时间，没有则用导入时间 */
export function effDate(item: MediaItem): number {
  return item.dateTaken > 0 ? item.dateTaken : item.addedAt;
}

/** 文件大小：B / KB / MB */
export function formatSize(bytes: number): string {
  if (bytes < 1024) {
    return bytes.toString() + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  }
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

/** yyyy-MM-dd */
export function formatDate(ms: number): string {
  if (!(ms > 0)) {
    return '—';
  }
  const d = new Date(ms);
  const y: number = d.getFullYear();
  const mo: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const mos: string = mo < 10 ? ('0' + mo.toString()) : mo.toString();
  const days: string = day < 10 ? ('0' + day.toString()) : day.toString();
  return y.toString() + '-' + mos + '-' + days;
}
