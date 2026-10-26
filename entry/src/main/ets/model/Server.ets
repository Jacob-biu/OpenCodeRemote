/** 一个 opencode 服务器（可命名、可编辑、可删除） */
export class ServerProfile {
  /** 唯一 id */
  id: string = '';
  /** 展示名称，如「公司台式机」 */
  name: string = '';
  host: string = '';
  port: number = 4096;
  username: string = 'opencode';
  password: string = '';
  useHttps: boolean = false;

  static create(host: string, port: number, username: string, password: string,
    useHttps: boolean, name: string): ServerProfile {
    const p: ServerProfile = new ServerProfile();
    p.id = ServerProfile.genId();
    p.name = name.length > 0 ? name : (host + ':' + port);
    p.host = host;
    p.port = port;
    p.username = username;
    p.password = password;
    p.useHttps = useHttps;
    return p;
  }

  static genId(): string {
    return 'srv_' + Date.now().toString(36) + Math.floor(Math.random() * 100000).toString(36);
  }
}
