export class Utils {
  private static readonly BASE64_CHARS: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  /**
   * 标准 Base64 编码（自实现，避免依赖版本差异）。
   * 注意：按 UTF-16 code unit 处理，适用于 ASCII 账号口令；
   * 含非 ASCII 字符时可能与标准实现有差异（Basic Auth 场景通常为 ASCII）。
   */
  static base64Encode(input: string): string {
    let output: string = '';
    let i: number = 0;
    const len: number = input.length;
    while (i < len) {
      const b1: number = input.charCodeAt(i++);
      const b2: number = i < len ? input.charCodeAt(i++) : -1;
      const b3: number = i < len ? input.charCodeAt(i++) : -1;
      output += Utils.BASE64_CHARS.charAt(b1 >> 2);
      output += Utils.BASE64_CHARS.charAt(((b1 & 0x03) << 4) | ((b2 > -1 ? (b2 & 0xF0) : 0) >> 4));
      output += b2 > -1
        ? Utils.BASE64_CHARS.charAt(((b2 & 0x0F) << 2) | ((b3 > -1 ? (b3 & 0xC0) : 0) >> 6))
        : '=';
      output += b3 > -1 ? Utils.BASE64_CHARS.charAt(b3 & 0x3F) : '=';
    }
    return output;
  }

  /** 毫秒时间戳格式化为 HH:mm */
  static formatTime(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d: Date = new Date(ms);
    const hh: string = (d.getHours() < 10 ? '0' : '') + d.getHours();
    const mm: string = (d.getMinutes() < 10 ? '0' : '') + d.getMinutes();
    return hh + ':' + mm;
  }

  /** 毫秒时间戳格式化为 MM-DD HH:mm */
  static formatDateTime(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d: Date = new Date(ms);
    const mo: string = (d.getMonth() + 1 < 10 ? '0' : '') + (d.getMonth() + 1);
    const day: string = (d.getDate() < 10 ? '0' : '') + d.getDate();
    return mo + '-' + day + ' ' + Utils.formatTime(ms);
  }

  /** 截断长文本，超出部分以省略号结尾 */
  static truncate(text: string, max: number): string {
    if (text.length <= max) {
      return text;
    }
    return text.substring(0, max) + '…';
  }
}
