export class ContentItem {
  /** text | reasoning | tool */
  type: string = '';
  id: string = '';
  /** text / reasoning 类型的正文 */
  text: string = '';
  /** 工具名称 */
  name: string = '';
  /** 工具状态：pending | running | completed | error */
  status: string = '';
  /** 工具入参（截断展示） */
  input: string = '';
  /** 工具输出（截断展示） */
  output: string = '';
}

export class SessionMessageItem {
  id: string = '';
  /** user | assistant */
  kind: string = 'user';
  /** user 消息正文 */
  text: string = '';
  agent: string = '';
  modelName: string = '';
  timeCreated: number = 0;
  timeCompleted: number = 0;
  error: string = '';
  contents: ContentItem[] = [];
}

export class PermissionRequest {
  id: string = '';
  sessionID: string = '';
  /** 请求的动作，如 bash / write / edit */
  action: string = '';
  /** 涉及的文件路径或命令 */
  resources: string[] = [];
  /** 服务端给出的可读说明 */
  message: string = '';
  /** 展示用标题 */
  title: string = '';
}
