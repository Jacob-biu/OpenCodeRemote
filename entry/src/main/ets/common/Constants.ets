export class Constants {
  static readonly TAG: string = 'OpenCodeRemote';

  // preferences 存储
  static readonly PREF_NAME: string = 'opencode_remote_config';
  static readonly KEY_HOST: string = 'host';
  static readonly KEY_PORT: string = 'port';
  static readonly KEY_USERNAME: string = 'username';
  static readonly KEY_PASSWORD: string = 'password';
  static readonly KEY_HTTPS: string = 'useHttps';

  /** 扫码页回传结果用的 AppStorage key */
  static readonly KEY_SCAN_RESULT: string = 'pair_scan_result';

  /** 多服务器列表与当前选中项 */
  static readonly KEY_SERVERS: string = 'servers';
  static readonly KEY_CURRENT_SERVER: string = 'current_server';

  // 连接默认值
  static readonly DEFAULT_HOST: string = '192.168.1.100';
  static readonly DEFAULT_PORT: number = 4096;
  static readonly DEFAULT_USERNAME: string = 'opencode';

  // 网络参数（TLS 首次握手需拉取证书链，超时给足余量）
  static readonly POLL_INTERVAL_MS: number = 2000;
  // 详情页轮询：拉的是全量消息，响应比会话列表大得多，放慢避免写满设备存储
  static readonly DETAIL_POLL_INTERVAL_MS: number = 4000;
  static readonly HTTP_READ_TIMEOUT: number = 30000;
  static readonly HTTP_CONNECT_TIMEOUT: number = 20000;
}
