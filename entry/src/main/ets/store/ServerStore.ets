import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ServerProfile } from '../model/Server';
import { Constants } from '../common/Constants';

/**
 * 多服务器管理：列表持久化到 preferences，current 记录当前选中项。
 */
export class ServerStore {
  private static pref: preferences.Preferences | null = null;
  private static servers: ServerProfile[] = [];
  private static currentId: string = '';

  static init(context: common.Context): void {
    if (ServerStore.pref !== null) {
      return;
    }
    try {
      ServerStore.pref = preferences.getPreferencesSync(context, { name: Constants.PREF_NAME });
    } catch {
      ServerStore.pref = null;
      return;
    }
    ServerStore.load();
  }

  private static load(): void {
    const p: preferences.Preferences | null = ServerStore.pref;
    if (p === null) {
      return;
    }
    try {
      const raw: string = p.getSync(Constants.KEY_SERVERS, '') as string;
      const cur: string = p.getSync(Constants.KEY_CURRENT_SERVER, '') as string;
      ServerStore.currentId = cur;
      if (raw.length === 0) {
        ServerStore.servers = [];
        return;
      }
      const arr: Object[] = JSON.parse(raw) as Object[];
      const list: ServerProfile[] = [];
      for (const item of arr) {
        const rec: Record<string, Object> = item as Record<string, Object>;
        const s: ServerProfile = new ServerProfile();
        s.id = String(rec['id'] ?? '');
        s.name = String(rec['name'] ?? '');
        s.host = String(rec['host'] ?? '');
        const portVal: Object = rec['port'];
        s.port = typeof portVal === 'number' ? portVal as number : Constants.DEFAULT_PORT;
        s.username = String(rec['username'] ?? Constants.DEFAULT_USERNAME);
        s.password = String(rec['password'] ?? '');
        const httpsVal: Object = rec['useHttps'];
        s.useHttps = httpsVal === true;
        if (s.id.length > 0 && s.host.length > 0) {
          list.push(s);
        }
      }
      ServerStore.servers = list;
      if (ServerStore.currentId.length === 0 && list.length > 0) {
        ServerStore.currentId = list[0].id;
      }
    } catch {
      ServerStore.servers = [];
    }
  }

  private static persist(): void {
    const p: preferences.Preferences | null = ServerStore.pref;
    if (p === null) {
      return;
    }
    try {
      p.putSync(Constants.KEY_SERVERS, JSON.stringify(ServerStore.servers));
      p.putSync(Constants.KEY_CURRENT_SERVER, ServerStore.currentId);
      p.flush();
    } catch {
      // 持久化失败不阻塞流程
    }
  }

  static all(): ServerProfile[] {
    return ServerStore.servers;
  }

  static current(): ServerProfile | null {
    if (ServerStore.servers.length === 0) {
      return null;
    }
    for (const s of ServerStore.servers) {
      if (s.id === ServerStore.currentId) {
        return s;
      }
    }
    return ServerStore.servers[0];
  }

  static setCurrent(id: string): void {
    ServerStore.currentId = id;
    ServerStore.persist();
  }

  static find(id: string): ServerProfile | null {
    for (const s of ServerStore.servers) {
      if (s.id === id) {
        return s;
      }
    }
    return null;
  }

  /** 新增或更新一个 server（id 为空则新建） */
  static save(profile: ServerProfile): ServerProfile {
    if (profile.id.length === 0) {
      profile.id = ServerProfile.genId();
      ServerStore.servers.push(profile);
    } else {
      for (let i = 0; i < ServerStore.servers.length; i++) {
        if (ServerStore.servers[i].id === profile.id) {
          ServerStore.servers[i] = profile;
          break;
        }
      }
    }
    if (ServerStore.currentId.length === 0) {
      ServerStore.currentId = profile.id;
    }
    ServerStore.persist();
    return profile;
  }

  static remove(id: string): void {
    const list: ServerProfile[] = [];
    for (const s of ServerStore.servers) {
      if (s.id !== id) {
        list.push(s);
      }
    }
    ServerStore.servers = list;
    if (ServerStore.currentId === id) {
      ServerStore.currentId = list.length > 0 ? list[0].id : '';
    }
    ServerStore.persist();
  }

  static rename(id: string, name: string): void {
    const s: ServerProfile | null = ServerStore.find(id);
    if (s !== null) {
      s.name = name;
      ServerStore.persist();
    }
  }

  /** 清空所有服务器与当前选择 */
  static clearAll(): void {
    ServerStore.servers = [];
    ServerStore.currentId = '';
    ServerStore.persist();
  }
}
