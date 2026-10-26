import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';

/** 手机端选中的一个文件（已读入内存并编码为 base64） */
export class PickedFile {
  /** 文件名（发给电脑端时用） */
  name: string = '';
  /** MIME 类型，如 image/png */
  mime: string = 'application/octet-stream';
  /** 文件内容的 base64（不含 data: 前缀） */
  data: string = '';
  /** 字节数 */
  size: number = 0;
  /** 原始 uri（用于本地缩略图展示） */
  uri: string = '';
  /** 是否图片（决定附件条里显示缩略图还是图标） */
  isImage: boolean = false;
}

/**
 * 手机端文件获取：拍照 / 相册选图 / 文档选文件。
 *
 * 文件不会落在手机本地再由电脑去取——opencode 2.x 没有独立的文件上传
 * 接口，服务端只在 user message 的 files[] 里接收内联附件
 * （结构 { data: base64, mime, source: { type: 'inline' }, name }，
 * 与电脑端客户端行为一致）。因此这里直接把内容读成 base64，
 * 随 prompt 一起发给电脑端。
 */
export class FileUtil {
  /** 单文件上限（base64 后体积再涨 1/3，这里按原始大小限制 8MB） */
  static readonly MAX_SIZE: number = 8 * 1024 * 1024;
  /** 一次最多选几个 */
  static readonly MAX_COUNT: number = 5;

  /** 调起系统相机拍一张照片 */
  static async takePhoto(context: Context): Promise<PickedFile[]> {
    // 官方示例写法：PickerProfile 直接用对象字面量构造。
    // 不能写成 `new cameraPicker.PickerProfile()` 再赋值（属性运行时只读），
    // 也不能加 `as` 强转（ArkTS 会把强转后的对象冻结，报
    // "Cannot assign to read only property"）。
    const profile: cameraPicker.PickerProfile = {
      cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
    };
    const result: cameraPicker.PickerResult =
      await cameraPicker.pick(context, [cameraPicker.PickerMediaType.PHOTO], profile);
    if (!result) {
      // 无摄像头设备（模拟器/部分平板）会返回空
      throw new Error('相机不可用');
    }
    return FileUtil.loadUris([result.resultUri], 'photo.jpg', 'image/jpeg');
  }

  /**
   * 给系统选择器加超时：部分设备/模拟器上没有对应的选择器提供者，
   * select() 的 Promise 会既不 resolve 也不 reject，用户会一直卡在
   * 「正在读取文件…」。超时后明确提示，避免无响应。
   */
  private static async withTimeout<T>(task: Promise<T>, ms: number): Promise<T> {
    return await Promise.race([
      task,
      new Promise<T>((_resolve: (v: T) => void, reject: (e: Error) => void) => {
        setTimeout(() => {
          reject(new Error('选择器无响应'));
        }, ms);
      })
    ]);
  }

  /** 选择器超时（毫秒） */
  static readonly PICK_TIMEOUT: number = 60000;

  /** 从相册选图片（最多 MAX_COUNT 张） */
  static async pickPhoto(): Promise<PickedFile[]> {
    const pv: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = FileUtil.MAX_COUNT;
    try {
      const res: photoAccessHelper.PhotoSelectResult =
        await FileUtil.withTimeout(pv.select(options), FileUtil.PICK_TIMEOUT);
      return FileUtil.loadUris(res.photoUris);
    } catch {
      throw new Error('无法打开相册');
    }
  }

  /** 选文件（文档/任意文件，最多 MAX_COUNT 个） */
  static async pickFile(): Promise<PickedFile[]> {
    const dp: picker.DocumentViewPicker = new picker.DocumentViewPicker();
    const options: picker.DocumentSelectOptions = { maxSelectNumber: FileUtil.MAX_COUNT };
    try {
      const uris: string[] = await FileUtil.withTimeout(dp.select(options), FileUtil.PICK_TIMEOUT);
      return FileUtil.loadUris(uris);
    } catch {
      throw new Error('无法打开文件选择器');
    }
  }

  /** 逐个读入并编码 */
  private static async loadUris(uris: string[], fallbackName: string = '',
    fallbackMime: string = ''): Promise<PickedFile[]> {
    const out: PickedFile[] = [];
    for (const uri of uris) {
      const f: PickedFile | null = await FileUtil.readOne(uri, fallbackName, fallbackMime);
      if (f !== null) {
        out.push(f);
      }
    }
    return out;
  }

  /** 读单个文件 → PickedFile；失败返回 null */
  static async readOne(uri: string, fallbackName: string = '',
    fallbackMime: string = ''): Promise<PickedFile | null> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      if (stat.size > FileUtil.MAX_SIZE) {
        throw new Error('文件超过 ' + Math.floor(FileUtil.MAX_SIZE / 1024 / 1024) + 'MB');
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      const name: string = FileUtil.nameOf(uri, fallbackName);
      const mime: string = FileUtil.mimeOf(name, fallbackMime);
      const helper: util.Base64Helper = new util.Base64Helper();
      const pf: PickedFile = new PickedFile();
      pf.name = name;
      pf.mime = mime;
      pf.size = stat.size;
      pf.uri = uri;
      pf.isImage = mime.indexOf('image/') === 0;
      pf.data = helper.encodeToStringSync(new Uint8Array(buffer));
      return pf;
    } catch {
      return null;
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch {
          // 忽略关闭异常
        }
      }
    }
  }

  /** 从 uri 推断文件名（file://media/Photo/IMG_001.jpg → IMG_001.jpg） */
  static nameOf(uri: string, fallback: string = ''): string {
    const cut: number = uri.lastIndexOf('/');
    let name: string = cut >= 0 ? uri.substring(cut + 1) : uri;
    // 带查询串时去掉
    const q: number = name.indexOf('?');
    if (q > 0) {
      name = name.substring(0, q);
    }
    return name.length > 0 ? name : fallback;
  }

  /** 按扩展名推断 MIME */
  static mimeOf(name: string, fallback: string = ''): string {
    const dot: number = name.lastIndexOf('.');
    if (dot < 0) {
      return fallback.length > 0 ? fallback : 'application/octet-stream';
    }
    const ext: string = name.substring(dot + 1).toLowerCase();
    const map: Record<string, string> = {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'svg': 'image/svg+xml',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'md': 'text/markdown',
      'json': 'application/json',
      'csv': 'text/csv',
      'log': 'text/plain',
      'xml': 'application/xml',
      'yaml': 'application/yaml',
      'yml': 'application/yaml',
      'zip': 'application/zip',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav'
    };
    const mime: string | undefined = map[ext];
    return mime !== undefined ? mime : (fallback.length > 0 ? fallback : 'application/octet-stream');
  }

  /** 人类可读的体积 */
  static sizeText(bytes: number): string {
    if (bytes < 1024) {
      return bytes + ' B';
    }
    if (bytes < 1024 * 1024) {
      return Math.round(bytes / 1024) + ' KB';
    }
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }
}
