import { common } from '@kit.AbilityKit';
import { ServerConfig } from '../model/Config';
import { ServerProfile } from '../model/Server';
import { ServerStore } from './ServerStore';
import { Constants } from '../common/Constants';

/**
 * 连接配置入口：实际数据落在 ServerStore（多服务器），
 * 这里保留单例读写接口，供各页面按「当前服务器」使用。
 */
export class ConfigStore {
  static init(context: common.Context): void {
    ServerStore.init(context);
  }

  static load(): ServerConfig {
    const cfg: ServerConfig = new ServerConfig();
    cfg.host = Constants.DEFAULT_HOST;
    cfg.port = Constants.DEFAULT_PORT;
    cfg.username = Constants.DEFAULT_USERNAME;
    cfg.password = '';
    cfg.useHttps = false;
    const s: ServerProfile | null = ServerStore.current();
    if (s !== null) {
      cfg.host = s.host;
      cfg.port = s.port;
      cfg.username = s.username;
      cfg.password = s.password;
      cfg.useHttps = s.useHttps;
    }
    return cfg;
  }

  /** 保存到当前服务器；没有当前服务器时新建一个 */
  static save(cfg: ServerConfig): void {
    const cur: ServerProfile | null = ServerStore.current();
    const p: ServerProfile = new ServerProfile();
    p.id = cur !== null ? cur.id : '';
    p.name = cur !== null ? cur.name : (cfg.host + ':' + cfg.port);
    p.host = cfg.host;
    p.port = cfg.port;
    p.username = cfg.username;
    p.password = cfg.password;
    p.useHttps = cfg.useHttps;
    ServerStore.save(p);
  }
}
