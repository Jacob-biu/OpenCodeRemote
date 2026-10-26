import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ServerConfig } from '../model/Config';
import { SessionInfo } from '../model/Session';
import { SessionMessageItem, PermissionRequest } from '../model/Message';
import { ModelInfo } from '../model/Model';
import { AgentInfo, CommandInfo } from '../model/Agent';
import { Utils } from '../common/Utils';
import { Constants } from '../common/Constants';
import { Parsers } from './Parsers';

/** POST /api/session/{id}/prompt 请求体（v2.1.2：text 在顶层） */
interface PromptRequestBody {
  text: string;
}

/**
 * 随消息发送的文件附件。
 *
 * opencode 2.1.3 的 prompt 接口要求 files[] 里带 **uri**（实测报
 * Missing key at ["files"][0]["uri"]），支持两种：
 *  - data URL：data:<mime>;base64,<base64>（内容内联，手机端用这个）
 *  - file:// 路径：服务端直接读电脑上的文件
 * 服务端收到后会解码成内联附件 { data, mime, source:{type:'inline'}, name }。
 */
export interface FilePart {
  /** data URL，如 data:image/png;base64,xxxx */
  uri: string;
  /** MIME，如 image/png */
  mime: string;
  /** 文件名 */
  name: string;
}

/** POST /api/session/{id}/permission/{requestID}/reply 请求体（v2.1.2 用 decision） */
interface PermissionReplyBody {
  decision: string;
}

/** 单次 HTTP 调用结果 */
export class ApiResult {
  ok: boolean = false;
  httpCode: number = 0;
  body: string = '';
  error: string = '';
}

/** 带类型的调用结果 */
export class SessionsResult {
  sessions: SessionInfo[] = [];
  activeIDs: string[] = [];
  error: string = '';
}

export class MessagesResult {
  messages: SessionMessageItem[] = [];
  error: string = '';
}

export class PermissionsResult {
  requests: PermissionRequest[] = [];
  error: string = '';
}

export class CreatedSession {
  session: SessionInfo = new SessionInfo();
  error: string = '';
}

/** 扫码配对结果 */
export class PairResult {
  token: string = '';
  error: string = '';
}

/** 模型列表结果 */
export class ModelsResult {
  models: ModelInfo[] = [];
  error: string = '';
}

/** 智能体 / 命令列表结果 */
export class AgentsResult {
  agents: AgentInfo[] = [];
  error: string = '';
}

export class CommandsResult {
  commands: CommandInfo[] = [];
  error: string = '';
}

/**
 * opencode v2 HTTP API 客户端。
 * 目标服务端：opencode-ai 1.19.3（opencode serve，默认端口 4096）。
 * 鉴权：HTTP Basic Auth（OPENCODE_SERVER_PASSWORD 开启时）。
 */
export class OpenCodeClient {
  private cfg: ServerConfig;

  constructor(cfg: ServerConfig) {
    this.cfg = cfg;
  }

  private baseUrl(): string {
    const scheme: string = this.cfg.useHttps ? 'https' : 'http';
    return scheme + '://' + this.cfg.host + ':' + this.cfg.port;
  }

  private authHeader(): string {
    return 'Basic ' + Utils.base64Encode(this.cfg.username + ':' + this.cfg.password);
  }

  private send(method: http.RequestMethod, path: string, body: string): Promise<ApiResult> {
    return this.sendInternal(method, path, body, true);
  }

  /** 免鉴权请求（配对兑换接口不需要 Authorization 头） */
  private sendInternal(method: http.RequestMethod, path: string, body: string,
    useAuth: boolean): Promise<ApiResult> {
    return new Promise<ApiResult>((resolve) => {
      let req: http.HttpRequest = http.createHttp();
      const header: Record<string, string> = {
        'Content-Type': 'application/json'
      };
      if (useAuth) {
        header['Authorization'] = this.authHeader();
      }
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: Constants.HTTP_READ_TIMEOUT,
        connectTimeout: Constants.HTTP_CONNECT_TIMEOUT,
        // 固定 HTTP/1.1：ArkUI 默认走 HTTP/2，实测带 body 的写操作
        // （PATCH 改标题、POST 新建会话）会被服务端判成 401 Parameter error，
        // 而同样报文用 HTTP/1.1 的客户端返回 204。
        usingProtocol: http.HttpProtocol.HTTP1_1,
        // 不用磁盘缓存：这是远程控制客户端，每次都要拿电脑端的最新状态；
        // 开启缓存还会在写缓存失败时报 2300023（Failed to write the received
        // data to the disk），表现为会话/消息一直转圈加载不出来。
        usingCache: false,
        extraData: body
      };
      req.request(this.baseUrl() + path, options, (err: BusinessError, resp: http.HttpResponse) => {
        const result: ApiResult = new ApiResult();
        if (err) {
          // 2300023：接收响应时写盘失败（设备存储空间不足 / 缓存目录异常）。
          // 原始英文提示对用户没有可操作性，这里换成中文指引。
          if (err.code === 2300023) {
            result.error = '设备存储空间不足，无法接收电脑端数据，请清理存储后重试';
          } else {
            result.error = '网络错误 ' + err.code + '：' + err.message;
          }
        } else {
          result.httpCode = resp.responseCode;
          result.body = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
          result.ok = resp.responseCode >= 200 && resp.responseCode < 300;
          if (!result.ok) {
            result.error = 'HTTP ' + resp.responseCode + '：' + Utils.truncate(result.body, 200);
          }
        }
        req.destroy();
        resolve(result);
      });
    });
  }

  // ---------- 裸端点 ----------

  checkHealth(): Promise<ApiResult> {
    // v2.1.2 无 /api/health，用 /api/info 兼做连通性与版本探测
    return this.send(http.RequestMethod.GET, '/api/info', '');
  }

  getVersion(): Promise<ApiResult> {
    return this.send(http.RequestMethod.GET, '/api/info', '');
  }

  listSessions(): Promise<ApiResult> {
    return this.send(http.RequestMethod.GET, '/api/session', '');
  }

  listActive(): Promise<ApiResult> {
    return this.send(http.RequestMethod.GET, '/api/session/active', '');
  }

  createSession(): Promise<ApiResult> {
    return this.send(http.RequestMethod.POST, '/api/session', '{}');
  }

  /**
   * 新建会话（可指定工程路径与模型）。
   * location: { directory }；model: { id, providerID }
   */
  createSessionWithOptions(directory: string, modelId: string, providerID: string): Promise<ApiResult> {
    interface LocationBody {
      directory: string;
    }
    interface ModelBody {
      id: string;
      providerID: string;
    }
    interface CreateBody {
      location?: LocationBody;
      model?: ModelBody;
    }
    const body: CreateBody = {};
    if (directory.length > 0) {
      const loc: LocationBody = { directory: directory };
      body.location = loc;
    }
    if (modelId.length > 0) {
      const m: ModelBody = { id: modelId, providerID: providerID };
      body.model = m;
    }
    return this.send(http.RequestMethod.POST, '/api/session', JSON.stringify(body));
  }

  /** GET /api/model → 可用模型列表 */
  listModels(): Promise<ApiResult> {
    return this.send(http.RequestMethod.GET, '/api/model', '');
  }

  /** GET /api/agent → 智能体（专家）列表 */
  listAgents(): Promise<ApiResult> {
    return this.send(http.RequestMethod.GET, '/api/agent', '');
  }

  /** GET /api/command → 斜杠命令（技能）列表 */
  listCommands(): Promise<ApiResult> {
    return this.send(http.RequestMethod.GET, '/api/command', '');
  }

  /** POST /api/session/{id}/model → 切换会话模型 */
  setSessionModel(sessionID: string, modelId: string, providerID: string): Promise<ApiResult> {
    interface ModelBody {
      id: string;
      providerID: string;
    }
    interface ModelSetBody {
      model: ModelBody;
    }
    const m: ModelBody = { id: modelId, providerID: providerID };
    const body: ModelSetBody = { model: m };
    return this.send(http.RequestMethod.POST, '/api/session/' + sessionID + '/model', JSON.stringify(body));
  }

  /**
   * 发送消息并指定智能体（专家），可携带文件附件。
   *
   * 附件结构与电脑端一致（opencode 2.x user message 的 files 字段）：
   * { data: base64, mime, source: { type: 'inline' }, name }。
   * opencode 2.1.3 没有独立的文件上传接口，文件随 prompt 一起送到电脑端。
   */
  sendPromptWithAgent(sessionID: string, text: string, agentName: string,
    files: FilePart[] = []): Promise<ApiResult> {
    interface AgentBody {
      name: string;
    }
    interface PromptBody {
      text: string;
      agents?: AgentBody[];
      files?: FilePart[];
    }
    const body: PromptBody = { text: text };
    if (agentName.length > 0) {
      const a: AgentBody = { name: agentName };
      body.agents = [a];
    }
    if (files.length > 0) {
      body.files = files;
    }
    return this.send(http.RequestMethod.POST, '/api/session/' + sessionID + '/prompt', JSON.stringify(body));
  }

  listMessages(sessionID: string): Promise<ApiResult> {
    return this.send(http.RequestMethod.GET, '/api/session/' + sessionID + '/message', '');
  }

  sendPrompt(sessionID: string, text: string): Promise<ApiResult> {
    const req: PromptRequestBody = { text: text };
    const body: string = JSON.stringify(req);
    return this.send(http.RequestMethod.POST, '/api/session/' + sessionID + '/prompt', body);
  }

  interrupt(sessionID: string): Promise<ApiResult> {
    return this.send(http.RequestMethod.POST, '/api/session/' + sessionID + '/interrupt', '{}');
  }

  listPermissions(): Promise<ApiResult> {
    return this.send(http.RequestMethod.GET, '/api/permission/request', '');
  }

  /** 删除会话（DELETE /api/session/{id}） */
  deleteSession(sessionID: string): Promise<ApiResult> {
    return this.send(http.RequestMethod.DELETE, '/api/session/' + sessionID, '');
  }

  /**
   * 重命名会话（PATCH /api/session/{id}，body { title }）。
   * 注意：ArkTS http.RequestMethod 枚举没有 PATCH（SDK typings 实测只有
   * OPTIONS/GET/HEAD/POST/PUT/DELETE），且 ArkTS 禁止 any/unknown，
   * 因此用 Object 中转做向下转型；服务端实测 PATCH 有效（204），
   * PUT/POST 均 404，故只能走 PATCH。
   */
  renameSession(sessionID: string, title: string): Promise<ApiResult> {
    interface RenameBody {
      title: string;
    }
    const body: string = JSON.stringify({ title: title } as RenameBody);
    const method: http.RequestMethod = ('PATCH' as Object) as http.RequestMethod;
    return this.send(method, '/api/session/' + sessionID, body);
  }

  replyPermission(sessionID: string, requestID: string, reply: string): Promise<ApiResult> {
    const replyBody: PermissionReplyBody = { decision: reply };
    const body: string = JSON.stringify(replyBody);
    return this.send(http.RequestMethod.POST, '/api/session/' + sessionID + '/permission/' + requestID + '/reply', body);
  }

  // ---------- 带类型的封装 ----------

  async fetchSessions(): Promise<SessionsResult> {
    const result: SessionsResult = new SessionsResult();
    const res: ApiResult = await this.listSessions();
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      result.sessions = Parsers.parseSessions(res.body);
    } catch {
      result.error = '解析会话列表失败';
      return result;
    }
    const activeRes: ApiResult = await this.listActive();
    if (activeRes.ok) {
      try {
        result.activeIDs = Parsers.parseActiveSet(activeRes.body);
      } catch {
        // active 解析失败不阻塞会话列表
      }
    }
    return result;
  }

  async fetchMessages(sessionID: string): Promise<MessagesResult> {
    const result: MessagesResult = new MessagesResult();
    const res: ApiResult = await this.listMessages(sessionID);
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      result.messages = Parsers.parseMessages(res.body);
    } catch {
      result.error = '解析消息失败';
    }
    return result;
  }

  async fetchPermissions(): Promise<PermissionsResult> {
    const result: PermissionsResult = new PermissionsResult();
    const res: ApiResult = await this.listPermissions();
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      result.requests = Parsers.parsePermissions(res.body);
    } catch {
      result.error = '解析权限请求失败';
    }
    return result;
  }

  async fetchActiveIDs(): Promise<string[]> {
    const res: ApiResult = await this.listActive();
    if (!res.ok) {
      return [];
    }
    try {
      return Parsers.parseActiveSet(res.body);
    } catch {
      return [];
    }
  }

  async createSessionParsed(): Promise<CreatedSession> {
    const result: CreatedSession = new CreatedSession();
    const res: ApiResult = await this.createSession();
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      const list: SessionInfo[] = Parsers.parseSessions(res.body);
      if (list.length > 0) {
        result.session = list[0];
      } else {
        result.error = '响应中未包含会话信息';
      }
    } catch {
      result.error = '解析新建会话响应失败';
    }
    return result;
  }

  /** 新建会话（指定路径/模型）并解析结果 */
  async createSessionWithOptionsParsed(directory: string, modelId: string,
    providerID: string): Promise<CreatedSession> {
    const result: CreatedSession = new CreatedSession();
    const res: ApiResult = await this.createSessionWithOptions(directory, modelId, providerID);
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      const list: SessionInfo[] = Parsers.parseSessions(res.body);
      if (list.length > 0) {
        result.session = list[0];
      } else {
        result.error = '响应中未包含会话信息';
      }
    } catch {
      result.error = '解析新建会话响应失败';
    }
    return result;
  }

  /** 拉取可用模型 */
  async fetchModels(): Promise<ModelsResult> {
    const result: ModelsResult = new ModelsResult();
    const res: ApiResult = await this.listModels();
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      result.models = Parsers.parseModels(res.body);
    } catch {
      result.error = '解析模型列表失败';
    }
    return result;
  }

  /** 拉取智能体（专家） */
  async fetchAgents(): Promise<AgentsResult> {
    const result: AgentsResult = new AgentsResult();
    const res: ApiResult = await this.listAgents();
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      result.agents = Parsers.parseAgents(res.body);
    } catch {
      result.error = '解析智能体列表失败';
    }
    return result;
  }

  /** 拉取斜杠命令（技能） */
  async fetchCommands(): Promise<CommandsResult> {
    const result: CommandsResult = new CommandsResult();
    const res: ApiResult = await this.listCommands();
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      result.commands = Parsers.parseCommands(res.body);
    } catch {
      result.error = '解析命令列表失败';
    }
    return result;
  }

  /**
   * 官方扫码配对：GET /auth/connect/{code}（免鉴权）→ 兑换 token。
   * 之后把 token 作为 Basic Auth 的密码（用户名 opencode）即可访问。
   */
  static async pair(host: string, port: number, useHttps: boolean, code: string): Promise<PairResult> {
    const result: PairResult = new PairResult();
    const cfg: ServerConfig = new ServerConfig();
    cfg.host = host;
    cfg.port = port;
    cfg.username = Constants.DEFAULT_USERNAME;
    cfg.password = '';
    cfg.useHttps = useHttps;
    const client: OpenCodeClient = new OpenCodeClient(cfg);
    const res: ApiResult = await client.sendInternal(http.RequestMethod.GET,
      '/auth/connect/' + code, '', false);
    if (!res.ok) {
      result.error = res.error.length > 0 ? res.error : 'HTTP ' + res.httpCode;
      return result;
    }
    try {
      result.token = Parsers.parsePairingToken(res.body);
      if (result.token.length === 0) {
        result.error = '配对响应中未包含 token';
      }
    } catch {
      result.error = '解析配对响应失败';
    }
    return result;
  }
}
