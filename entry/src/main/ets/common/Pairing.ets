/**
 * opencode 官方「扫码配对」链接解析。
 *
 * 桌面端 Pairing → Copy link 给出的格式：
 *   https://<隧道域名>/auth/connect/<配对码>
 * 例如：https://9fd6ae97b76cc945.uthotjpn2mff.opentunnel.xyz/auth/connect/oOy8PbzkhIjXDVGqCuoehQ
 *
 * 配对码是一次性的，5 分钟有效；兑换成功后得到 token，
 * 之后把 token 当作 Basic Auth 的密码（用户名固定 opencode）使用。
 */
export class PairingLink {
  host: string = '';
  port: number = 443;
  useHttps: boolean = true;
  code: string = '';
  ok: boolean = false;
}

export class PairingParser {
  private static readonly PATH_MARK: string = '/auth/connect/';

  /**
   * 解析扫码/粘贴得到的内容。
   *
   * 支持三种输入：
   * ① 桌面端二维码内容（JSON）：{"code":"...","urls":["https://<隧道域名>"]}
   * ② 完整链接：https://host[:port]/auth/connect/<配对码>
   * ③ 仅配对码（配合已填写的服务器地址）
   *
   * @param text 扫码或粘贴的原始文本
   * @param fallbackHost 文本只有配对码时使用的服务器地址
   */
  static parse(text: string, fallbackHost: string): PairingLink {
    const link: PairingLink = new PairingLink();
    const raw: string = text.trim();
    if (raw.length === 0) {
      return link;
    }

    // 情况 1：桌面端二维码的 JSON 载荷
    if (raw.charAt(0) === '{') {
      return PairingParser.parseJsonPayload(raw);
    }

    // 情况 2：完整链接 https://host[:port]/auth/connect/CODE
    const schemeIdx: number = raw.indexOf('://');
    if (schemeIdx > 0) {
      const scheme: string = raw.substring(0, schemeIdx).toLowerCase();
      const rest: string = raw.substring(schemeIdx + 3);
      const slashIdx: number = rest.indexOf('/');
      const authority: string = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
      const path: string = slashIdx >= 0 ? rest.substring(slashIdx) : '';
      const code: string = PairingParser.extractCode(path);
      if (code.length === 0) {
        return link;
      }
      link.code = code;
      link.useHttps = scheme !== 'http';
      const colonIdx: number = authority.lastIndexOf(':');
      if (colonIdx > 0 && authority.indexOf(']') < colonIdx) {
        link.host = authority.substring(0, colonIdx);
        const portText: string = authority.substring(colonIdx + 1);
        const port: number = Number(portText);
        link.port = isNaN(port) ? (link.useHttps ? 443 : 80) : port;
      } else {
        link.host = authority;
        link.port = link.useHttps ? 443 : 80;
      }
      link.ok = link.host.length > 0;
      return link;
    }

    // 情况 3：只有路径 https 被省掉，形如 host/auth/connect/CODE
    const pathIdx: number = raw.indexOf(PairingParser.PATH_MARK);
    if (pathIdx > 0) {
      const host: string = raw.substring(0, pathIdx);
      const code: string = PairingParser.extractCode(raw.substring(pathIdx));
      if (host.length === 0 || code.length === 0) {
        return link;
      }
      link.host = host;
      link.code = code;
      link.useHttps = true;
      link.port = 443;
      link.ok = true;
      return link;
    }

    // 情况 4：只有配对码，配合已填写的服务器地址使用
    if (raw.indexOf('/') < 0 && raw.indexOf(' ') < 0) {
      link.code = raw;
      link.host = fallbackHost.trim();
      link.port = 443;
      link.useHttps = true;
      link.ok = link.host.length > 0;
    }
    return link;
  }

  /** 解析 {"code":"...","urls":["https://..."]} 形式的二维码载荷 */
  private static parseJsonPayload(raw: string): PairingLink {
    const link: PairingLink = new PairingLink();
    let obj: Object | null = null;
    try {
      obj = JSON.parse(raw);
    } catch {
      return link;
    }
    if (obj === null) {
      return link;
    }
    const rec: Record<string, Object> = obj as Record<string, Object>;
    const codeVal: Object = rec['code'];
    const code: string = typeof codeVal === 'string' ? codeVal as string : '';
    if (code.length === 0) {
      return link;
    }
    link.code = code;

    const urlsVal: Object = rec['urls'];
    let host: string = '';
    let port: number = 443;
    let useHttps: boolean = true;
    if (urlsVal !== undefined && urlsVal !== null && Array.isArray(urlsVal)) {
      const arr: Object[] = urlsVal as Object[];
      if (arr.length > 0 && typeof arr[0] === 'string') {
        const first: string = arr[0] as string;
        const schemeIdx: number = first.indexOf('://');
        if (schemeIdx > 0) {
          useHttps = first.substring(0, schemeIdx).toLowerCase() !== 'http';
          const rest: string = first.substring(schemeIdx + 3);
          const slashIdx: number = rest.indexOf('/');
          const authority: string = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
          const colonIdx: number = authority.lastIndexOf(':');
          if (colonIdx > 0) {
            host = authority.substring(0, colonIdx);
            const p: number = Number(authority.substring(colonIdx + 1));
            port = isNaN(p) ? (useHttps ? 443 : 80) : p;
          } else {
            host = authority;
            port = useHttps ? 443 : 80;
          }
        } else {
          host = first;
        }
      }
    }
    if (host.length === 0) {
      return link;
    }
    link.host = host;
    link.port = port;
    link.useHttps = useHttps;
    link.ok = true;
    return link;
  }

  private static extractCode(path: string): string {
    const idx: number = path.indexOf(PairingParser.PATH_MARK);
    if (idx < 0) {
      return '';
    }
    const tail: string = path.substring(idx + PairingParser.PATH_MARK.length);
    const parts: string[] = tail.split('/');
    const code: string = parts.length > 0 ? parts[0] : '';
    return code.trim();
  }
}
