import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaItem, MediaType } from '../model/MediaItem';

const DOMAIN: number = 0x1001;
const TAG: string = 'TopShowcase';
const STORE_NAME: string = 'top_showcase_store';
const ITEMS_KEY: string = 'items';
const SETTINGS_KEY: string = 'settings';
const DIR_NAME: string = 'showcase';

/** 一次导入的结果。 */
export interface ImportOutcome {
  items: MediaItem[];
  added: number;
  failed: number;
  message: string;
}

/** 图片像素尺寸。 */
export interface ImageSize {
  width: number;
  height: number;
}

/** 视频元数据：宽高 + 拍摄时间。 */
export interface VideoMeta {
  width: number;
  height: number;
  dateTaken: number;
}

/** 需要记住的界面设置。 */
export interface ShowcaseSettings {
  layoutMode: number;
  sortMode: number;
  filterMode: number;
  group: string;
  autoPlay: boolean;
  columns: number;
  slideInterval: number;
  /** 主题：0 跟随系统，1 浅色，2 深色 */
  theme: number;
}

/**
 * 藏品本地存储：
 * - 元数据通过 Preferences 持久化（JSON 字符串）。
 * - 媒体文件从系统相册选择后复制到应用沙箱 filesDir/showcase 下，
 *   并读取图片真实宽高、生成视频首帧封面。
 */
export class ShowcaseStore {
  // ---------- 资源释放辅助 ----------
  // ArkTS 要求"可能抛异常"的调用必须有 try/catch 处理，finally 里未捕获的异常会继续上抛，
  // 因此所有清理动作统一走这里，自身吞掉异常只记日志。

  static closeQuietly(file: fs.File | null): void {
    if (file === null) {
      return;
    }
    try {
      fs.closeSync(file);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'close file failed: %{public}s', JSON.stringify(err));
    }
  }

  static async releaseExtractorQuietly(extractor: media.AVMetadataExtractor | null): Promise<void> {
    if (extractor === null) {
      return;
    }
    try {
      await extractor.release();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'release extractor failed: %{public}s', JSON.stringify(err));
    }
  }

  static async releaseGeneratorQuietly(generator: media.AVImageGenerator | null): Promise<void> {
    if (generator === null) {
      return;
    }
    try {
      await generator.release();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'release generator failed: %{public}s', JSON.stringify(err));
    }
  }

  static async releaseSourceQuietly(source: image.ImageSource | null): Promise<void> {
    if (source === null) {
      return;
    }
    try {
      await source.release();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'release image source failed: %{public}s', JSON.stringify(err));
    }
  }

  static async releasePixelMapQuietly(pixelMap: image.PixelMap | null): Promise<void> {
    if (pixelMap === null) {
      return;
    }
    try {
      await pixelMap.release();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'release pixel map failed: %{public}s', JSON.stringify(err));
    }
  }

  static async releasePackerQuietly(packer: image.ImagePacker | null): Promise<void> {
    if (packer === null) {
      return;
    }
    try {
      await packer.release();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'release packer failed: %{public}s', JSON.stringify(err));
    }
  }

  static async load(context: common.UIAbilityContext): Promise<MediaItem[]> {
    try {
      const prefs = await preferences.getPreferences(context, STORE_NAME);
      const value = await prefs.get(ITEMS_KEY, '[]');
      let json: string = '[]';
      if (typeof value === 'string') {
        json = value;
      }
      const parsed: MediaItem[] = JSON.parse(json) as MediaItem[];
      const list: MediaItem[] = [];
      for (let i = 0; i < parsed.length; i++) {
        list.push(ShowcaseStore.normalize(parsed[i]));
      }
      return list;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  /** 兼容旧数据：补齐新增字段的默认值。 */
  static normalize(raw: MediaItem): MediaItem {
    const id: string = raw.id ? raw.id : '';
    const type: MediaType = raw.type === MediaType.VIDEO ? MediaType.VIDEO : MediaType.IMAGE;
    const uri: string = raw.uri ? raw.uri : '';
    const fileName: string = raw.fileName ? raw.fileName : '';
    const displayName: string = raw.displayName ? raw.displayName : fileName;
    const size: number = raw.size ? raw.size : 0;
    const addedAt: number = raw.addedAt ? raw.addedAt : 0;
    const dateTaken: number = raw.dateTaken ? raw.dateTaken : 0;
    const width: number = raw.width ? raw.width : 0;
    const height: number = raw.height ? raw.height : 0;
    const thumbUri: string = raw.thumbUri ? raw.thumbUri : '';
    const favorite: boolean = raw.favorite === true;
    const remark: string = raw.remark ? raw.remark : '';
    const group: string = raw.group ? raw.group : '';
    return new MediaItem(id, type, uri, fileName, displayName, size, addedAt, dateTaken, width, height, thumbUri,
      favorite, remark, group);
  }

  static async persist(context: common.UIAbilityContext, items: MediaItem[]): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, STORE_NAME);
      const json: string = JSON.stringify(items);
      await prefs.put(ITEMS_KEY, json);
      await prefs.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'persist failed: %{public}s', JSON.stringify(err));
    }
  }

  static async saveItems(context: common.UIAbilityContext, items: MediaItem[]): Promise<void> {
    await ShowcaseStore.persist(context, items);
  }

  static async loadSettings(context: common.UIAbilityContext): Promise<ShowcaseSettings> {
    try {
      const prefs = await preferences.getPreferences(context, STORE_NAME);
      const value = await prefs.get(SETTINGS_KEY, '');
      let json: string = '';
      if (typeof value === 'string') {
        json = value;
      }
      if (json.length > 0) {
        return JSON.parse(json) as ShowcaseSettings;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadSettings failed: %{public}s', JSON.stringify(err));
    }
    const def: ShowcaseSettings = { layoutMode: 0, sortMode: 0, filterMode: 0, group: '', autoPlay: false, columns: 3, slideInterval: 3, theme: 0 };
    return def;
  }

  static async saveSettings(context: common.UIAbilityContext, settings: ShowcaseSettings): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, STORE_NAME);
      const json: string = JSON.stringify(settings);
      await prefs.put(SETTINGS_KEY, json);
      await prefs.flush();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'saveSettings failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 导出元数据 JSON 到用户选择的位置。 */
  static async exportBackup(context: common.UIAbilityContext, items: MediaItem[]): Promise<string> {
    let uris: string[] = [];
    try {
      const docPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = ['ZhanWu_backup.json'];
      uris = await docPicker.save(options);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'exportBackup picker failed: %{public}s', JSON.stringify(err));
      return '已取消导出';
    }
    if (uris.length === 0) {
      return '已取消导出';
    }
    try {
      const json: string = JSON.stringify(items);
      const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, json);
      } finally {
        ShowcaseStore.closeQuietly(file);
      }
      return '已导出 ' + items.length.toString() + ' 条元数据';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'exportBackup write failed: %{public}s', JSON.stringify(err));
      return '导出失败';
    }
  }

  /** 从用户选择的 JSON 文件导入元数据，按 id 合并（已存在的跳过）。 */
  static async importBackup(context: common.UIAbilityContext, currentItems: MediaItem[]): Promise<ImportOutcome> {
    let uris: string[] = [];
    try {
      const docPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.json'];
      uris = await docPicker.select(options);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'importBackup picker failed: %{public}s', JSON.stringify(err));
      return { items: currentItems, added: 0, failed: 0, message: '已取消导入' };
    }
    if (uris.length === 0) {
      return { items: currentItems, added: 0, failed: 0, message: '未选择文件' };
    }
    try {
      const text: string = ShowcaseStore.readText(uris[0]);
      const parsed: MediaItem[] = JSON.parse(text) as MediaItem[];
      const next: MediaItem[] = currentItems.slice();
      let added: number = 0;
      for (let i = 0; i < parsed.length; i++) {
        const item: MediaItem = ShowcaseStore.normalize(parsed[i]);
        if (item.id.length === 0) {
          continue;
        }
        let exists: boolean = false;
        for (let j = 0; j < next.length; j++) {
          if (next[j].id === item.id) {
            exists = true;
            break;
          }
        }
        if (!exists) {
          next.push(item);
          added++;
        }
      }
      await ShowcaseStore.persist(context, next);
      const msg: string = added > 0 ? ('已导入 ' + added.toString() + ' 条元数据') : '没有新增数据（id 均已存在）';
      return { items: next, added: added, failed: 0, message: msg };
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'importBackup parse failed: %{public}s', JSON.stringify(err));
      return { items: currentItems, added: 0, failed: 0, message: '文件解析失败' };
    }
  }

  static readText(uri: string): string {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(uri).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      const readLen: number = fs.readSync(file.fd, buffer);
      const decoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(new Uint8Array(buffer, 0, readLen));
      return text;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'readText failed: %{public}s', JSON.stringify(err));
      return '';
    } finally {
      ShowcaseStore.closeQuietly(file);
    }
  }

  /** 调起系统分享面板分享若干藏品。成功返回空串，失败返回提示文案。 */
  static async shareItems(context: common.UIAbilityContext, items: MediaItem[]): Promise<string> {
    if (items.length === 0) {
      return '没有可分享的内容';
    }
    try {
      const records: systemShare.SharedRecord[] = [];
      for (let i = 0; i < items.length; i++) {
        const it: MediaItem = items[i];
        // 跨应用分享需用带包名的可授权 file uri，直连沙箱路径其它应用读不到
        const shareUri: string = fileUri.getUriFromPath(ShowcaseStore.rawPath(it.uri));
        const record: systemShare.SharedRecord = {
          utd: it.type === MediaType.VIDEO ? 'general.video' : 'general.image',
          uri: shareUri,
          title: it.displayName
        };
        records.push(record);
      }
      const data: systemShare.SharedData = new systemShare.SharedData(records[0]);
      for (let i = 1; i < records.length; i++) {
        data.addRecord(records[i]);
      }
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const options: systemShare.ShareControllerOptions = {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      };
      await controller.show(context, options);
      return '';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'shareItems failed: %{public}s', JSON.stringify(err));
      return '分享失败';
    }
  }

  /**
   * 打开系统相册选择器（图片 + 视频），复制到沙箱并写入元数据。
   * 图片读取真实宽高；视频生成首帧封面。失败原因写入 hilog 并回显到 message。
   */
  static async importFromPicker(context: common.UIAbilityContext, currentItems: MediaItem[]): Promise<ImportOutcome> {
    let uris: string[] = [];
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
      options.maxSelectNumber = 50;
      const result = await picker.select(options);
      uris = result.photoUris;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'picker.select failed: %{public}s', JSON.stringify(err));
      return { items: currentItems, added: 0, failed: 0, message: '选择已取消或失败' };
    }

    hilog.info(DOMAIN, TAG, 'picked uri count = %{public}d', uris.length);
    if (uris.length === 0) {
      return { items: currentItems, added: 0, failed: 0, message: '未选择任何内容' };
    }

    const dir: string = context.filesDir + '/' + DIR_NAME;
    try {
      fs.mkdirSync(dir, true);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'mkdir failed: %{public}s', JSON.stringify(err));
    }
    let dirReady: boolean = false;
    try {
      dirReady = fs.statSync(dir).isDirectory();
    } catch (err) {
      dirReady = false;
    }
    if (!dirReady) {
      return { items: currentItems, added: 0, failed: 0, message: '创建目录失败' };
    }

    const next: MediaItem[] = currentItems.slice();
    const stamp: number = Date.now();
    let added: number = 0;
    let failed: number = 0;
    let firstError: string = '';

    for (let i = 0; i < uris.length; i++) {
      const uri: string = uris[i];
      let type: MediaType = ShowcaseStore.detectType(uri);
      const fileName: string = ShowcaseStore.buildFileName(uri, type, i, stamp);
      const destPath: string = dir + '/' + fileName;
      try {
        ShowcaseStore.copyFile(uri, destPath);
        const stat = fs.statSync(destPath);
        if (stat.size === 0) {
          failed++;
          if (firstError.length === 0) {
            firstError = '读取到空文件';
          }
          hilog.error(DOMAIN, TAG, 'empty file for uri = %{public}s', uri);
          try {
            fs.unlinkSync(destPath);
          } catch (err) {
          }
        } else {
          let width: number = 0;
          let height: number = 0;
          let thumbUri: string = '';
          let dateTaken: number = 0;
          if (type === MediaType.IMAGE) {
            const size: ImageSize = await ShowcaseStore.readImageSize(destPath);
            width = size.width;
            height = size.height;
            dateTaken = await ShowcaseStore.readImageDate(destPath);
            if (width > 0 && height > 0) {
              const thumbPath: string = dir + '/thumb_' + stamp.toString() + '_' + i.toString() + '.jpg';
              const tOk: boolean = await ShowcaseStore.makeImageThumb(destPath, thumbPath, 640);
              if (tOk) {
                thumbUri = 'file://' + thumbPath;
              }
            }
            if (width <= 0 || height <= 0) {
              // 解不出图片尺寸，可能是被误判的视频：尝试按视频取帧
              const vmeta: VideoMeta = await ShowcaseStore.readVideoMeta(destPath);
              const thumbPath: string = dir + '/thumb_' + stamp.toString() + '_' + i.toString() + '.jpg';
              const ok: boolean = await ShowcaseStore.extractVideoThumb(destPath, thumbPath, vmeta.width, vmeta.height);
              if (ok) {
                type = MediaType.VIDEO;
                thumbUri = 'file://' + thumbPath;
                width = vmeta.width;
                height = vmeta.height;
                dateTaken = vmeta.dateTaken;
              }
            }
          } else {
            const vmeta: VideoMeta = await ShowcaseStore.readVideoMeta(destPath);
            width = vmeta.width;
            height = vmeta.height;
            dateTaken = vmeta.dateTaken;
            const thumbPath: string = dir + '/thumb_' + stamp.toString() + '_' + i.toString() + '.jpg';
            const ok: boolean = await ShowcaseStore.extractVideoThumb(destPath, thumbPath, width, height);
            if (ok) {
              thumbUri = 'file://' + thumbPath;
            }
          }
          const id: string = ShowcaseStore.buildId(uri, stamp, i);
          const displayName: string = ShowcaseStore.originalName(uri);
          const item = new MediaItem(id, type, 'file://' + destPath, fileName, displayName, stat.size, stamp,
            dateTaken, width, height, thumbUri, false, '', '');
          next.push(item);
          added++;
        }
      } catch (err) {
        failed++;
        const detail: string = JSON.stringify(err);
        if (firstError.length === 0) {
          firstError = detail;
        }
        hilog.error(DOMAIN, TAG, 'copy failed: uri=%{public}s err=%{public}s', uri, detail);
      }
    }

    await ShowcaseStore.persist(context, next);

    let message: string = '';
    if (added > 0) {
      message = '已导入 ' + added.toString() + ' 件藏品';
      if (failed > 0) {
        message = message + '，' + failed.toString() + ' 件失败';
      }
    } else {
      message = '导入失败：' + firstError;
    }
    hilog.info(DOMAIN, TAG, 'import done added=%{public}d failed=%{public}d', added, failed);
    return { items: next, added: added, failed: failed, message: message };
  }

  /** 读取图片真实像素尺寸：先按路径、再按 fd 尝试；失败返回 0,0。 */
  static async readImageSize(path: string): Promise<ImageSize> {
    try {
      const source: image.ImageSource = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      const size: ImageSize = { width: info.size.width, height: info.size.height };
      await source.release();
      return size;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'readImageSize(path) failed: %{public}s', JSON.stringify(err));
    }
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const source: image.ImageSource = image.createImageSource(file.fd);
        const info: image.ImageInfo = await source.getImageInfo();
        const size: ImageSize = { width: info.size.width, height: info.size.height };
        await source.release();
        return size;
      } finally {
        ShowcaseStore.closeQuietly(file);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'readImageSize(fd) failed: %{public}s', JSON.stringify(err));
    }
    const fallback: ImageSize = { width: 0, height: 0 };
    return fallback;
  }

  /** 读取视频真实宽高与拍摄时间；失败返回 0。 */
  static async readVideoMeta(path: string): Promise<VideoMeta> {
    let file: fs.File | null = null;
    let extractor: media.AVMetadataExtractor | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const srcFd: number = file.fd;
      extractor = await media.createAVMetadataExtractor();
      const fd: media.AVFileDescriptor = { fd: srcFd };
      extractor.fdSrc = fd;
      const meta: media.AVMetadata = await extractor.fetchMetadata();
      // 注意：本 SDK 的 AVMetadata 字段为字符串类型，需要显式转换
      let w: number = meta.videoWidth ? Number.parseFloat(meta.videoWidth) : 0;
      let h: number = meta.videoHeight ? Number.parseFloat(meta.videoHeight) : 0;
      if (!(w > 0)) {
        w = 0;
      }
      if (!(h > 0)) {
        h = 0;
      }
      const dateTaken: number = ShowcaseStore.parseIsoDate(meta.dateTime ? meta.dateTime : '');
      const info: VideoMeta = { width: w, height: h, dateTaken: dateTaken };
      return info;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'readVideoMeta failed: %{public}s', JSON.stringify(err));
      const info: VideoMeta = { width: 0, height: 0, dateTaken: 0 };
      return info;
    } finally {
      await ShowcaseStore.releaseExtractorQuietly(extractor);
      ShowcaseStore.closeQuietly(file);
    }
  }

  /** 读取图片拍摄时间（EXIF DateTimeOriginal / DateTime）；取不到返回 0。 */
  static async readImageDate(path: string): Promise<number> {
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(path);
      let text: string = '';
      try {
        text = await source.getImageProperty(image.PropertyKey.DATE_TIME_ORIGINAL);
      } catch (e1) {
        text = '';
      }
      if (text.length === 0) {
        try {
          text = await source.getImageProperty(image.PropertyKey.DATE_TIME);
        } catch (e2) {
          text = '';
        }
      }
      return ShowcaseStore.parseExifDate(text);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'readImageDate failed: %{public}s', JSON.stringify(err));
      return 0;
    } finally {
      await ShowcaseStore.releaseSourceQuietly(source);
    }
  }

  /** 解析 EXIF 时间 "YYYY:MM:DD HH:MM:SS" → 毫秒；失败返回 0。 */
  static parseExifDate(text: string): number {
    if (text.length < 19) {
      return 0;
    }
    const y: number = Number.parseInt(text.substring(0, 4), 10);
    const mo: number = Number.parseInt(text.substring(5, 7), 10);
    const d: number = Number.parseInt(text.substring(8, 10), 10);
    const h: number = Number.parseInt(text.substring(11, 13), 10);
    const mi: number = Number.parseInt(text.substring(14, 16), 10);
    const se: number = Number.parseInt(text.substring(17, 19), 10);
    if (!(y > 1970)) {
      return 0;
    }
    return Date.UTC(y, mo - 1, d, h, mi, se);
  }

  /** 解析 ISO 时间字符串 → 毫秒；失败返回 0。 */
  static parseIsoDate(text: string): number {
    if (text.length < 10) {
      return 0;
    }
    const v: number = Date.parse(text);
    if (!(v > 0)) {
      return 0;
    }
    return v;
  }

  /**
   * 生成限尺寸缩略图（JPEG）写入 destPath。
   * 列表/网格/瀑布只看缩略图，避免按原图解码导致大图库内存过高。
   */
  static async makeImageThumb(srcPath: string, destPath: string, maxSide: number): Promise<boolean> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      file = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
      const srcFd: number = file.fd;
      source = image.createImageSource(srcFd);
      const info: image.ImageInfo = await source.getImageInfo();
      const w: number = info.size.width;
      const h: number = info.size.height;
      if (!(w > 0) || !(h > 0)) {
        return false;
      }
      let tw: number = w;
      let th: number = h;
      if (w >= h && w > maxSide) {
        tw = maxSide;
        th = Math.round(maxSide * h / w);
      } else if (h > w && h > maxSide) {
        th = maxSide;
        tw = Math.round(maxSide * w / h);
      }
      if (tw < 1) {
        tw = 1;
      }
      if (th < 1) {
        th = 1;
      }
      const decodeOpts: image.DecodingOptions = { desiredSize: { width: tw, height: th } };
      pixelMap = await source.createPixelMap(decodeOpts);
      packer = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 85 };
      const buf: ArrayBuffer = await packer.packToData(pixelMap, packOpts);
      const out = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(out.fd, buf);
      } finally {
        ShowcaseStore.closeQuietly(out);
      }
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'makeImageThumb failed: %{public}s', JSON.stringify(err));
      return false;
    } finally {
      await ShowcaseStore.releasePackerQuietly(packer);
      await ShowcaseStore.releasePixelMapQuietly(pixelMap);
      await ShowcaseStore.releaseSourceQuietly(source);
      ShowcaseStore.closeQuietly(file);
    }
  }

  /**
   * 回填历史数据：老版本导入的藏品没有宽高/视频封面，这里按需补上。
   * 只在有变化时落盘。
   */
  static async backfill(context: common.UIAbilityContext, items: MediaItem[]): Promise<MediaItem[]> {
    const dir: string = context.filesDir + '/' + DIR_NAME;
    let changed: boolean = false;
    for (let i = 0; i < items.length; i++) {
      const item: MediaItem = items[i];
      const raw: string = ShowcaseStore.rawPath(item.uri);
      if (item.type === MediaType.IMAGE) {
        if (item.width <= 0 || item.height <= 0) {
          const size: ImageSize = await ShowcaseStore.readImageSize(raw);
          if (size.width > 0 && size.height > 0) {
            item.width = size.width;
            item.height = size.height;
            changed = true;
          } else {
            // 之前可能把视频误判成图片，这里纠正
            const vmeta: VideoMeta = await ShowcaseStore.readVideoMeta(raw);
            const thumbPath: string = dir + '/thumb_' + item.id + '.jpg';
            const ok: boolean = await ShowcaseStore.extractVideoThumb(raw, thumbPath, vmeta.width, vmeta.height);
            if (ok) {
              item.type = MediaType.VIDEO;
              item.thumbUri = 'file://' + thumbPath;
              item.width = vmeta.width;
              item.height = vmeta.height;
              if (vmeta.dateTaken > 0) {
                item.dateTaken = vmeta.dateTaken;
              }
              changed = true;
            }
          }
        }
        if (!(item.dateTaken > 0)) {
          const d: number = await ShowcaseStore.readImageDate(raw);
          if (d > 0) {
            item.dateTaken = d;
            changed = true;
          }
        }
        if (item.thumbUri.length === 0 && item.width > 0 && item.height > 0) {
          const thumbPath: string = dir + '/thumb_' + item.id + '.jpg';
          const ok: boolean = await ShowcaseStore.makeImageThumb(raw, thumbPath, 640);
          if (ok) {
            item.thumbUri = 'file://' + thumbPath;
            changed = true;
          }
        }
      } else {
        if (item.width <= 0 || item.height <= 0 || !(item.dateTaken > 0)) {
          const vmeta: VideoMeta = await ShowcaseStore.readVideoMeta(raw);
          if (vmeta.width > 0 && vmeta.height > 0) {
            item.width = vmeta.width;
            item.height = vmeta.height;
            changed = true;
          }
          if (!(item.dateTaken > 0) && vmeta.dateTaken > 0) {
            item.dateTaken = vmeta.dateTaken;
            changed = true;
          }
        }
        // 封面缺失、或旧版方形封面与视频比例不符 → 重新生成
        let needThumb: boolean = item.thumbUri.length === 0;
        if (!needThumb && item.width > 0 && item.height > 0) {
          const tsize: ImageSize = await ShowcaseStore.readImageSize(ShowcaseStore.rawPath(item.thumbUri));
          if (tsize.width > 0 && tsize.height > 0) {
            const ta: number = tsize.width / tsize.height;
            const va: number = item.width / item.height;
            if (ta < va * 0.97 || ta > va * 1.03) {
              needThumb = true;
            }
          }
        }
        if (needThumb) {
          const thumbPath: string = dir + '/thumb_' + item.id + '.jpg';
          const ok: boolean = await ShowcaseStore.extractVideoThumb(raw, thumbPath, item.width, item.height);
          if (ok) {
            item.thumbUri = 'file://' + thumbPath;
            changed = true;
          }
        }
      }
    }
    if (changed) {
      await ShowcaseStore.persist(context, items);
      hilog.info(DOMAIN, TAG, 'backfill updated metadata');
    }
    return items;
  }

  /** 提取视频首帧并写入 thumbPath（按视频真实比例，避免封面被压成方形）；成功返回 true。 */
  static async extractVideoThumb(videoPath: string, thumbPath: string, videoW: number, videoH: number): Promise<boolean> {
    let file: fs.File | null = null;
    let generator: media.AVImageGenerator | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      file = fs.openSync(videoPath, fs.OpenMode.READ_ONLY);
      const srcFd: number = file.fd;
      generator = await media.createAVImageGenerator();
      const fd: media.AVFileDescriptor = { fd: srcFd };
      generator.fdSrc = fd;
      let reqW: number = 640;
      let reqH: number = 640;
      if (videoW > 0 && videoH > 0) {
        if (videoW >= videoH) {
          reqW = 640;
          reqH = Math.round(640 * videoH / videoW);
        } else {
          reqH = 640;
          reqW = Math.round(640 * videoW / videoH);
        }
        if (reqW < 1) {
          reqW = 1;
        }
        if (reqH < 1) {
          reqH = 1;
        }
      }
      pixelMap = await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC,
        { width: reqW, height: reqH });
      packer = image.createImagePacker();
      const opts: image.PackingOption = { format: 'image/jpeg', quality: 80 };
      const buf: ArrayBuffer = await packer.packToData(pixelMap, opts);
      const out = fs.openSync(thumbPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(out.fd, buf);
      } finally {
        ShowcaseStore.closeQuietly(out);
      }
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'extractVideoThumb failed: %{public}s', JSON.stringify(err));
      return false;
    } finally {
      await ShowcaseStore.releasePackerQuietly(packer);
      await ShowcaseStore.releasePixelMapQuietly(pixelMap);
      await ShowcaseStore.releaseGeneratorQuietly(generator);
      ShowcaseStore.closeQuietly(file);
    }
  }

  /** 批量删除（同时清理媒体文件与封面文件）。 */
  static async deleteMany(context: common.UIAbilityContext, ids: string[], currentItems: MediaItem[]): Promise<MediaItem[]> {
    const next: MediaItem[] = [];
    for (let i = 0; i < currentItems.length; i++) {
      const item: MediaItem = currentItems[i];
      if (ids.indexOf(item.id) >= 0) {
        ShowcaseStore.removeFiles(item);
      } else {
        next.push(item);
      }
    }
    await ShowcaseStore.persist(context, next);
    return next;
  }

  static removeFiles(item: MediaItem): void {
    try {
      fs.unlinkSync(ShowcaseStore.rawPath(item.uri));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'unlink media failed: %{public}s', JSON.stringify(err));
    }
    if (item.thumbUri.length > 0) {
      try {
        fs.unlinkSync(ShowcaseStore.rawPath(item.thumbUri));
      } catch (err) {
      }
    }
  }

  static detectType(uri: string): MediaType {
    const lower: string = uri.toLowerCase();
    if (lower.indexOf('/video/') >= 0) {
      return MediaType.VIDEO;
    }
    if (ShowcaseStore.isVideoExt(ShowcaseStore.extractExt(uri))) {
      return MediaType.VIDEO;
    }
    return MediaType.IMAGE;
  }

  static isVideoExt(ext: string): boolean {
    return ext === 'mp4' || ext === 'mov' || ext === 'm4v' || ext === 'mkv' ||
      ext === 'avi' || ext === 'webm' || ext === '3gp' || ext === 'mpg' || ext === 'mpeg' || ext === 'ts';
  }

  static buildFileName(uri: string, type: MediaType, index: number, stamp: number): string {
    let ext: string = ShowcaseStore.extractExt(uri);
    if (ext.length === 0) {
      ext = type === MediaType.VIDEO ? 'mp4' : 'jpg';
    }
    return 'showcase_' + stamp.toString() + '_' + index.toString() + '.' + ext;
  }

  /** 从 uri 取原始文件名（用于默认显示名）。 */
  static originalName(uri: string): string {
    let cleaned: string = uri;
    const q: number = cleaned.indexOf('?');
    if (q >= 0) {
      cleaned = cleaned.substring(0, q);
    }
    const slash: number = cleaned.lastIndexOf('/');
    const name: string = slash >= 0 ? cleaned.substring(slash + 1) : cleaned;
    return name.length > 0 ? name : '未命名';
  }

  /** 提取安全扩展名：去 query/hash，只保留 [a-z0-9]，长度 1~5。 */
  static extractExt(uri: string): string {
    let cleaned: string = uri;
    const q: number = cleaned.indexOf('?');
    if (q >= 0) {
      cleaned = cleaned.substring(0, q);
    }
    const h: number = cleaned.indexOf('#');
    if (h >= 0) {
      cleaned = cleaned.substring(0, h);
    }
    const lastSlash: number = cleaned.lastIndexOf('/');
    if (lastSlash < 0) {
      return '';
    }
    const namePart: string = cleaned.substring(lastSlash + 1);
    const lastDot: number = namePart.lastIndexOf('.');
    if (lastDot < 0 || lastDot >= namePart.length - 1) {
      return '';
    }
    const raw: string = namePart.substring(lastDot + 1).toLowerCase();
    let safe: string = '';
    for (let i = 0; i < raw.length; i++) {
      const c: string = raw.charAt(i);
      if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
        safe = safe + c;
      }
    }
    if (safe.length === 0 || safe.length > 5) {
      return '';
    }
    return safe;
  }

  static buildId(uri: string, stamp: number, index: number): string {
    return stamp.toString() + '_' + index.toString() + '_' + uri.length.toString();
  }

  static rawPath(uri: string): string {
    if (uri.indexOf('file://') === 0) {
      return uri.substring(7);
    }
    return uri;
  }

  /**
   * 把相册临时授权的 uri 复制到沙箱。
   * 首选官方可用写法「源 fd + 目标路径」；若失败则退化为流式复制。
   */
  static copyFile(src: string, dest: string): void {
    let srcFile: fs.File | null = null;
    try {
      srcFile = fs.openSync(src, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(srcFile.fd, dest);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'copyFileSync(fd, path) failed, fallback to stream: %{public}s', JSON.stringify(err));
      if (srcFile !== null) {
        ShowcaseStore.copyByStream(srcFile.fd, dest);
      }
    } finally {
      ShowcaseStore.closeQuietly(srcFile);
    }
  }

  static copyByStream(srcFd: number, dest: string): void {
    let destFile: fs.File | null = null;
    try {
      destFile = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const buffer: ArrayBuffer = new ArrayBuffer(8192);
      while (true) {
        const readLen: number = fs.readSync(srcFd, buffer);
        if (readLen <= 0) {
          break;
        }
        fs.writeSync(destFile.fd, buffer, { length: readLen });
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'copyByStream failed: %{public}s', JSON.stringify(err));
    } finally {
      ShowcaseStore.closeQuietly(destFile);
    }
  }
}
