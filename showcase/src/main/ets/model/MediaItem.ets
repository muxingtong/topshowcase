/**
 * 藏品媒体类型。使用字符串枚举，便于 JSON 序列化后直接比较。
 */
export enum MediaType {
  IMAGE = 'image',
  VIDEO = 'video'
}

/**
 * 一件"藏品"：照片（jpg/heic/gif/动图静态帧）或视频。
 * 数据仅用于展示与持久化，不包含业务方法。
 */
export class MediaItem {
  id: string;
  type: MediaType;
  /** 沙箱内的 file:// 路径，用于展示。 */
  uri: string;
  /** 沙箱内的物理文件名。 */
  fileName: string;
  /** 面向用户的名称，可重命名。 */
  displayName: string;
  /** 字节大小。 */
  size: number;
  /** 导入时间戳（ms）。 */
  addedAt: number;
  /** 拍摄时间戳（ms）：图片取 EXIF、视频取媒体元数据；取不到时回退为导入时间。 */
  dateTaken: number;
  /** 图片/视频真实宽（像素），0 表示未知。 */
  width: number;
  /** 图片/视频真实高（像素），0 表示未知。 */
  height: number;
  /** 视频首帧封面（file:// 路径），空表示未生成。 */
  thumbUri: string;
  /** 是否收藏。仅作标记与筛选，不参与排序（不置顶）。 */
  favorite: boolean;
  /** 备注。 */
  remark: string;
  /** 所属分组，空串表示未分组。 */
  group: string;

  constructor(id: string, type: MediaType, uri: string, fileName: string, displayName: string, size: number,
    addedAt: number, dateTaken: number, width: number, height: number, thumbUri: string, favorite: boolean,
    remark: string, group: string) {
    this.id = id;
    this.type = type;
    this.uri = uri;
    this.fileName = fileName;
    this.displayName = displayName;
    this.size = size;
    this.addedAt = addedAt;
    this.dateTaken = dateTaken;
    this.width = width;
    this.height = height;
    this.thumbUri = thumbUri;
    this.favorite = favorite;
    this.remark = remark;
    this.group = group;
  }
}
