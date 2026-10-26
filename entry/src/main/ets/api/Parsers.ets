import { SessionInfo } from '../model/Session';
import { SessionMessageItem, ContentItem, PermissionRequest } from '../model/Message';
import { ModelInfo } from '../model/Model';
import { AgentInfo, CommandInfo } from '../model/Agent';
import { Utils } from '../common/Utils';

/**
 * opencode v2 API（/api/*）响应解析。
 * 目标服务端：opencode-ai 1.19.3，实证自 /doc OpenAPI 3.1 规范。
 */
export class Parsers {
  private static readonly EMPTY: Record<string, Object> = {};

  /** GET /api/session → SessionsResponse */
  static parseSessions(body: string): SessionInfo[] {
    const out: SessionInfo[] = [];
    const root: Object = JSON.parse(body);
    const data: Object[] = Parsers.getArr(root, 'data');
    for (const item of data) {
      const s: SessionInfo = new SessionInfo();
      s.id = Parsers.getStr(item, 'id');
      s.title = Parsers.getStr(item, 'title');
      s.projectID = Parsers.getStr(item, 'projectID');
      s.agent = Parsers.getStr(item, 'agent');
      const loc: Object = Parsers.getObj(item, 'location');
      s.location = Parsers.getStr(loc, 'directory');
      const time: Object = Parsers.getObj(item, 'time');
      s.timeCreated = Parsers.getNum(time, 'created');
      s.timeUpdated = Parsers.getNum(time, 'updated');
      out.push(s);
    }
    return out;
  }

  /** GET /api/session/active → { data: { [sessionID]: { type: 'running' } } } */
  static parseActiveSet(body: string): string[] {
    const root: Object = JSON.parse(body);
    const data: Object = Parsers.getObj(root, 'data');
    const rec: Record<string, Object> = data as Record<string, Object>;
    const keys: string[] = Object.keys(rec);
    const out: string[] = [];
    for (const k of keys) {
      const v: Object = rec[k];
      // 值形如 { type: 'running' }。只有明确为 running 才算运行中；
      // 若该版本不带 type 字段，则退化为「出现即运行中」。
      const t: string = Parsers.getStr(v, 'type');
      if (t.length === 0 || t === 'running' || t === 'busy') {
        out.push(k);
      }
    }
    return out;
  }

  /** GET /api/session/{id}/message → SessionMessagesResponse */
  static parseMessages(body: string): SessionMessageItem[] {
    const out: SessionMessageItem[] = [];
    const root: Object = JSON.parse(body);
    const data: Object[] = Parsers.getArr(root, 'data');
    for (const item of data) {
      const kind: string = Parsers.getStr(item, 'type');
      if (kind === 'user') {
        const m: SessionMessageItem = new SessionMessageItem();
        m.id = Parsers.getStr(item, 'id');
        m.kind = 'user';
        m.text = Parsers.getStr(item, 'text');
        const time: Object = Parsers.getObj(item, 'time');
        m.timeCreated = Parsers.getNum(time, 'created');
        out.push(m);
      } else if (kind === 'assistant') {
        const m: SessionMessageItem = new SessionMessageItem();
        m.id = Parsers.getStr(item, 'id');
        m.kind = 'assistant';
        m.agent = Parsers.getStr(item, 'agent');
        const model: Object = Parsers.getObj(item, 'model');
        m.modelName = Parsers.getStr(model, 'id');
        const time: Object = Parsers.getObj(item, 'time');
        m.timeCreated = Parsers.getNum(time, 'created');
        m.timeCompleted = Parsers.getNum(time, 'completed');
        const errObj: Object = Parsers.getObj(item, 'error');
        m.error = Parsers.getStr(errObj, 'message');
        m.contents = Parsers.parseContents(Parsers.getArr(item, 'content'));
        out.push(m);
      }
      // system / shell / synthetic / compaction 等类型 MVP 跳过
    }
    // 按创建时间稳定排序：服务端返回顺序不保证与时间一致，
    // 不排序会导致用户消息与模型消息前后错位。
    return Parsers.sortByTime(out);
  }

  /** 稳定排序：按 timeCreated 升序，同一时间保持原顺序 */
  private static sortByTime(items: SessionMessageItem[]): SessionMessageItem[] {
    const out: SessionMessageItem[] = items.slice(0);
    // 插入排序：稳定且不依赖 Array.prototype.sort 的比较器实现
    for (let i = 1; i < out.length; i++) {
      const cur: SessionMessageItem = out[i];
      let j = i - 1;
      while (j >= 0 && out[j].timeCreated > cur.timeCreated) {
        out[j + 1] = out[j];
        j--;
      }
      out[j + 1] = cur;
    }
    return out;
  }

  private static parseContents(arr: Object[]): ContentItem[] {
    const out: ContentItem[] = [];
    for (const raw of arr) {
      const type: string = Parsers.getStr(raw, 'type');
      if (type !== 'text' && type !== 'reasoning' && type !== 'tool') {
        continue;
      }
      const c: ContentItem = new ContentItem();
      c.type = type;
      c.id = Parsers.getStr(raw, 'id');
      c.text = Parsers.getStr(raw, 'text');
      c.name = Parsers.getStr(raw, 'name');
      const state: Object = Parsers.getObj(raw, 'state');
      c.status = Parsers.getStr(state, 'status');
      c.input = Parsers.parseToolInput(state);
      c.output = Parsers.parseToolOutput(state);
      out.push(c);
    }
    return out;
  }

  private static parseToolInput(state: Object): string {
    const input: Object = Parsers.getObj(state, 'input');
    if (input !== Parsers.EMPTY) {
      return Utils.truncate(JSON.stringify(input), 300);
    }
    // pending 状态下 input 直接是字符串
    return Utils.truncate(Parsers.getStr(state, 'input'), 300);
  }

  private static parseToolOutput(state: Object): string {
    const parts: string[] = [];
    const content: Object[] = Parsers.getArr(state, 'content');
    for (const c of content) {
      const text: string = Parsers.getStr(c, 'text');
      if (text.length > 0) {
        parts.push(text);
      }
      const jsonObj: Object = Parsers.getObj(c, 'json');
      if (jsonObj !== Parsers.EMPTY) {
        parts.push(JSON.stringify(jsonObj));
      }
    }
    const paths: string[] = Parsers.getStrArr(state, 'outputPaths');
    for (const p of paths) {
      parts.push(p);
    }
    return Utils.truncate(parts.join('\n'), 600);
  }

  /** GET /api/permission/request → PermissionV2Request[] */
  static parsePermissions(body: string): PermissionRequest[] {
    const out: PermissionRequest[] = [];
    const root: Object = JSON.parse(body);
    const data: Object[] = Parsers.getArr(root, 'data');
    for (const item of data) {
      const p: PermissionRequest = new PermissionRequest();
      p.id = Parsers.getStr(item, 'id');
      p.sessionID = Parsers.getStr(item, 'sessionID');
      p.action = Parsers.getStr(item, 'action');
      p.resources = Parsers.getStrArr(item, 'resources');
      p.message = Parsers.getStr(item, 'message');
      p.title = Parsers.buildPermissionTitle(p.action, p.resources);
      out.push(p);
    }
    return out;
  }

  static buildPermissionTitle(action: string, resources: string[]): string {
    let title: string = action.length > 0 ? action : '未知操作';
    if (resources.length > 0) {
      title += ' · ' + Utils.truncate(resources[0], 60);
      if (resources.length > 1) {
        title += ' 等 ' + resources.length + ' 项';
      }
    }
    return title;
  }

  /** GET /global/health（兼容端点）→ { healthy, version } */
  static parseVersion(body: string): string {
    try {
      const root: Object = JSON.parse(body);
      return Parsers.getStr(root, 'version');
    } catch {
      return '';
    }
  }

  /** GET /api/agent → { location, data: Agent.Info[] } */
  static parseAgents(body: string): AgentInfo[] {
    const out: AgentInfo[] = [];
    const root: Object = JSON.parse(body);
    const data: Object[] = Parsers.getArr(root, 'data');
    for (const item of data) {
      const a: AgentInfo = new AgentInfo();
      a.id = Parsers.getStr(item, 'id');
      a.name = Parsers.getStr(item, 'name');
      a.description = Parsers.getStr(item, 'description');
      a.mode = Parsers.getStr(item, 'mode');
      if (a.id.length > 0) {
        out.push(a);
      }
    }
    return out;
  }

  /** GET /api/command → { location, data: Command.Info[] } */
  static parseCommands(body: string): CommandInfo[] {
    const out: CommandInfo[] = [];
    const root: Object = JSON.parse(body);
    const data: Object[] = Parsers.getArr(root, 'data');
    for (const item of data) {
      const c: CommandInfo = new CommandInfo();
      c.name = Parsers.getStr(item, 'name');
      c.description = Parsers.getStr(item, 'description');
      if (c.name.length > 0) {
        out.push(c);
      }
    }
    return out;
  }

  /** GET /auth/connect/{code} → { token: "..." } */
  static parsePairingToken(body: string): string {
    const root: Object = JSON.parse(body);
    return Parsers.getStr(root, 'token');
  }

  /** GET /api/model → { location, data: Model.Info[] } */
  static parseModels(body: string): ModelInfo[] {
    const out: ModelInfo[] = [];
    const root: Object = JSON.parse(body);
    const data: Object[] = Parsers.getArr(root, 'data');
    for (const item of data) {
      const m: ModelInfo = new ModelInfo();
      m.id = Parsers.getStr(item, 'id');
      m.providerID = Parsers.getStr(item, 'providerID');
      m.variant = Parsers.getStr(item, 'variant');
      m.name = Parsers.getStr(item, 'name');
      m.description = Parsers.getStr(item, 'description');
      // cost: [{ input, output, cache }]
      const costs: Object[] = Parsers.getArr(item, 'cost');
      if (costs.length > 0) {
        m.costInput = Parsers.getNum(costs[0], 'input');
        m.costOutput = Parsers.getNum(costs[0], 'output');
      }
      // limit: { context, input, output }
      const limit: Object = Parsers.getObj(item, 'limit');
      m.context = Parsers.getNum(limit, 'context');
      if (m.id.length > 0) {
        out.push(m);
      }
    }
    return out;
  }

  // ---------- 基础取值辅助 ----------

  /** 取子对象；键不存在时返回 EMPTY（调用方无需判空） */
  private static getObj(v: Object, key: string): Object {
    const rec: Record<string, Object> = v as Record<string, Object>;
    const val: Object = rec[key];
    if (val === null || val === undefined) {
      return Parsers.EMPTY;
    }
    return val;
  }

  private static getArr(v: Object, key: string): Object[] {
    const rec: Record<string, Object> = v as Record<string, Object>;
    const val: Object = rec[key];
    if (val === undefined || val === null || !Array.isArray(val)) {
      return [];
    }
    return val as Object[];
  }

  private static getStr(v: Object, key: string): string {
    const rec: Record<string, Object> = v as Record<string, Object>;
    const val: Object = rec[key];
    if (typeof val === 'string') {
      return val as string;
    }
    return '';
  }

  private static getNum(v: Object, key: string): number {
    const rec: Record<string, Object> = v as Record<string, Object>;
    const val: Object = rec[key];
    if (typeof val === 'number') {
      return val as number;
    }
    return 0;
  }

  private static getStrArr(v: Object, key: string): string[] {
    const arr: Object[] = Parsers.getArr(v, key);
    const out: string[] = [];
    for (const e of arr) {
      if (typeof e === 'string') {
        out.push(e as string);
      }
    }
    return out;
  }
}
