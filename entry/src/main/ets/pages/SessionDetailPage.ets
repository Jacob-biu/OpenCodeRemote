import { Constants } from '../common/Constants';
import { pasteboard } from '@kit.BasicServicesKit';
import { Utils } from '../common/Utils';
import { SessionMessageItem, PermissionRequest } from '../model/Message';
import { ModelInfo } from '../model/Model';
import { AgentInfo, CommandInfo } from '../model/Agent';
import { ServerProfile } from '../model/Server';
import { ConfigStore } from '../store/ConfigStore';
import { ServerStore } from '../store/ServerStore';
import {
  OpenCodeClient,
  MessagesResult,
  ApiResult,
  ModelsResult,
  AgentsResult,
  CommandsResult,
  FilePart
} from '../api/OpenCodeClient';
import { FileUtil, PickedFile } from '../common/FileUtil';
import { MessageBubble } from '../components/MessageBubble';
import { PermissionCard } from '../components/PermissionCard';
import { ModelSheet } from '../components/ModelSheet';
import { RadioDot } from '../components/RadioDot';
import { AttachSheet } from '../components/AttachSheet';

@Entry
@Component
struct SessionDetailPage {
  @State sessionId: string = '';
  @State sessionTitle: string = '';
  @State sessionSub: string = '';
  @State serverName: string = '';
  @State messages: SessionMessageItem[] = [];
  @State permissions: PermissionRequest[] = [];
  @State running: boolean = false;
  @State inputText: string = '';
  @State sending: boolean = false;
  @State errorText: string = '';
  // 模型
  @State models: ModelInfo[] = [];
  @State modelSheetVisible: boolean = false;
  @State attachSheetVisible: boolean = false;
  @State sheetKind: string = '';
  @State sheetVisible: boolean = false;
  @State currentModelId: string = '';
  // 附件
  @State agents: AgentInfo[] = [];
  @State commands: CommandInfo[] = [];
  @State currentAgent: string = '';
  @State showScrollDown: boolean = false;
  @State firstLoading: boolean = true;
  // 附加电脑文件
  @State attachPath: string = '';
  // 桌面端能力说明（connector / schedule）
  @State unsupportedKind: string = '';
  // 自动滚到底部：仅在用户本就位于底部时刷新才滚动（上翻看历史不被拽回）
  @State autoScroll: boolean = true;
  // 消息区内容高度 / 视口高度（用于判定是否停在底部）
  @State contentH: number = 0;
  @State viewH: number = 0;
  // 待发送的附件（手机端拍照/选图/选文件，已读成 base64）
  @State pendingFiles: PickedFile[] = [];
  // 正在选择/读取附件（读大文件要时间，界面给反馈）
  @State pickingFile: boolean = false;
  private timer: number = -1;
  private client: OpenCodeClient = new OpenCodeClient(ConfigStore.load());
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const params: Record<string, Object> =
      this.getUIContext().getRouter().getParams() as Record<string, Object>;
    const sid: Object = params['sessionId'];
    const title: Object = params['title'];
    const loc: Object = params['location'];
    this.sessionId = typeof sid === 'string' ? sid as string : '';
    this.sessionTitle = typeof title === 'string' ? title as string : '会话';
    const locText: string = typeof loc === 'string' ? loc as string : '';
    this.sessionSub = locText.length > 0 ? locText.split('/').pop() as string : 'opencode';
    const cur: ServerProfile | null = ServerStore.current();
    this.serverName = cur !== null ? cur.name : 'opencode';
    this.client = new OpenCodeClient(ConfigStore.load());
    this.loadModels();
  }

  onPageShow(): void {
    this.refresh();
    this.startPolling();
  }

  onPageHide(): void {
    this.stopPolling();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  private startPolling(): void {
    this.stopPolling();
    this.timer = setInterval(() => {
      this.refresh();
    // 详情页拉的是「全量消息」，大会话（带图片附件/长工具输出）单次可达数百 KB，
    // 每 2 秒全量拉一次会把设备存储写满并触发 ArkUI 2300023
    // （Failed to write the received data），表现为消息一直转圈加载不出来。
    // 这里放慢到 4 秒，列表页仍保持 2 秒（响应只有几 KB）。
    }, Constants.DETAIL_POLL_INTERVAL_MS);
  }

  private stopPolling(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async refresh(): Promise<void> {
    if (this.sessionId.length === 0) {
      return;
    }
    // 正在发送时跳过刷新：服务端此时还没把刚发的用户消息落库，
    // 刷新会把本地回显的那条抹掉，造成「消息闪一下又没了」。
    if (this.sending) {
      return;
    }
    if (this.messages.length === 0) {
      this.firstLoading = true;
    }
    const msgResult: MessagesResult = await this.client.fetchMessages(this.sessionId);
    this.firstLoading = false;
    if (msgResult.error.length === 0) {
      this.errorText = '';
      // 合入式更新：内容没变的消息复用原对象引用（气泡零重渲染），
      // 变化/新增/消失的消息才换对象，避免每 2s 整体替换把用户正在
      // 上翻的滚动位置冲掉（实测：列表像被锁死一样无法翻历史）。
      this.mergeMessages(msgResult.messages);
      // 贴底不再在这里主动做：由内容高度变化（onAreaChange）驱动，
      // 只有用户原本就在底部时才跟随，避免轮询把上翻中的用户拽回底部。
    } else {
      this.errorText = msgResult.error;
    }

    const activeIDs: string[] = await this.client.fetchActiveIDs();
    this.running = activeIDs.indexOf(this.sessionId) >= 0;

    const permResult = await this.client.fetchPermissions();
    if (permResult.error.length === 0) {
      const list: PermissionRequest[] = [];
      for (const p of permResult.requests) {
        if (p.sessionID === this.sessionId) {
          list.push(p);
        }
      }
      this.permissions = list;
    }
  }

  // ---------------- 模型 ----------------

  /**
   * 把新拉到的消息合入 @State messages。
   *
   * 为什么不能直接 this.messages = next（旧实现的 sameMessages 还有一个
   * 致命盲区：只比 id/类型/时间/内容块「数量」，流式消息文字变长、工具
   * 状态 running→completed 都不触发更新，界面永远停在旧内容）：
   * 1. 未变化的消息按 id 复用原对象引用 —— ForEach 按索引重跑生成器时，
   *    MessageBubble 的 @Prop 收到同一引用不会重渲染，省掉整列气泡的
   *    无谓刷新（长会话流式时只动变化的那几条）；
   * 2. 任何字段变化（文字、状态、输入输出）都算不同，换新对象 → @Prop
   *    同步 → 气泡重渲染；
   * 3. 整表顺序与引用都零变化时完全不赋值，滚动位置不受轮询干扰。
   */
  private mergeMessages(next: SessionMessageItem[]): void {
    const old: SessionMessageItem[] = this.messages;
    const merged: SessionMessageItem[] = [];
    for (const n of next) {
      let keep: SessionMessageItem | null = null;
      for (const o of old) {
        if (o.id === n.id) {
          keep = o;
          break;
        }
      }
      if (keep !== null && JSON.stringify(keep) === JSON.stringify(n)) {
        merged.push(keep);
      } else {
        merged.push(n);
      }
    }
    if (merged.length === old.length) {
      let identical: boolean = true;
      for (let i = 0; i < merged.length; i++) {
        if (merged[i] !== old[i]) {
          identical = false;
          break;
        }
      }
      if (identical) {
        return;
      }
    }
    this.messages = merged;
  }

  private loadModels(): void {
    this.client.fetchModels().then((res: ModelsResult) => {
      if (res.error.length === 0) {
        this.models = res.models;
      }
    });
  }

  private currentModelLabel(): string {
    if (this.currentModelId.length === 0) {
      return '默认模型';
    }
    for (const m of this.models) {
      if (m.id === this.currentModelId) {
        return m.displayName();
      }
    }
    return '默认模型';
  }

  private onPickModel(m: ModelInfo): void {
    this.sheetVisible = false;
    if (m.id.length === 0) {
      // 「默认模型」：仅清除本地指定（服务端无重置接口，不下发请求）
      this.currentModelId = '';
      this.showToast('已取消本地模型指定（服务端仍按已设模型执行）');
      return;
    }
    this.currentModelId = m.id;
    // 立即切换当前会话的模型
    this.client.setSessionModel(this.sessionId, m.id, m.providerID).then((res: ApiResult) => {
      if (!res.ok) {
        this.errorText = '切换模型失败：' + res.error;
      } else {
        this.showToast('已切换模型：' + m.displayName());
      }
    });
  }

  // ---------------- 附件面板 ----------------

  private onOpenAttach(): void {
    this.sheetKind = 'attach';
    this.sheetVisible = true;
    this.client.fetchAgents().then((res: AgentsResult) => {
      if (res.error.length === 0) {
        this.agents = res.agents;
      }
    });
    this.client.fetchCommands().then((res: CommandsResult) => {
      if (res.error.length === 0) {
        this.commands = res.commands;
      }
    });
  }

  /** 专家列表：真实可选，支持取消 */
  private onOpenAgentPicker(): void {
    if (this.agents.length === 0) {
      this.showToast('没有可用的专家');
      return;
    }
    this.sheetKind = 'agent';
  }

  private onPickAgent(a: AgentInfo): void {
    this.currentAgent = a.name;
    this.sheetVisible = false;
    this.showToast('已选择专家：' + a.name);
  }

  private onClearAgent(): void {
    this.currentAgent = '';
    this.sheetVisible = false;
    this.showToast('已取消专家');
  }

  /** 技能列表：真实可选，点击后把 /name 插入输入框 */
  private onOpenCommandPicker(): void {
    if (this.commands.length === 0) {
      this.showToast('没有可用的技能');
      return;
    }
    this.sheetKind = 'command';
  }

  private onPickCommand(c: CommandInfo): void {
    this.sheetVisible = false;
    const prefix: string = '/' + c.name + ' ';
    this.inputText = this.inputText.length > 0 ? prefix + this.inputText : prefix;
  }

  /** 附加电脑文件（手动输入电脑上的路径，仍保留作为兜底） */
  private onOpenAttachFile(): void {
    this.attachPath = '';
    this.sheetKind = 'file';
  }

  // ---------------- 手机端取附件（拍照 / 选图 / 选文件） ----------------

  /** 调起相机拍一张照片 */
  private async onTakePhoto(): Promise<void> {
    this.sheetVisible = false;
    await this.pickFiles('photo');
  }

  /** 从相册选图片 */
  private async onPickPhoto(): Promise<void> {
    this.sheetVisible = false;
    await this.pickFiles('media');
  }

  /** 选文件（文档） */
  private async onPickFile(): Promise<void> {
    this.sheetVisible = false;
    await this.pickFiles('file');
  }

  /**
   * 按类型取附件并加入待发送列表。
   * 文件在手机端读成 base64（opencode 2.x 没有独立上传接口，
   * 附件随 prompt 的 files[] 一起送到电脑端）。
   */
  private async pickFiles(kind: string): Promise<void> {
    if (this.pickingFile) {
      return;
    }
    this.pickingFile = true;
    try {
      const context: Context = getContext(this) as Context;
      let files: PickedFile[] = [];
      if (kind === 'photo') {
        files = await FileUtil.takePhoto(context);
      } else if (kind === 'media') {
        files = await FileUtil.pickPhoto();
      } else {
        files = await FileUtil.pickFile();
      }
      if (files.length === 0) {
        this.showToast('未选择文件');
        return;
      }
      const merged: PickedFile[] = this.pendingFiles.concat(files);
      this.pendingFiles = merged.length > FileUtil.MAX_COUNT ? merged.slice(0, FileUtil.MAX_COUNT) : merged;
      this.showToast('已添加 ' + files.length + ' 个附件，发送时传到电脑端');
    } catch (e) {
      const msg: string = (e as Error).message;
      this.showToast(msg.length > 0 ? msg : '无法获取文件');
    } finally {
      this.pickingFile = false;
    }
  }

  /** 移除一个待发送附件 */
  private onRemoveFile(index: number): void {
    const next: PickedFile[] = [];
    for (let i = 0; i < this.pendingFiles.length; i++) {
      if (i !== index) {
        next.push(this.pendingFiles[i]);
      }
    }
    this.pendingFiles = next;
  }

  /** 待发送附件 → opencode 的附件结构（uri 用 data URL，内容内联传给电脑端） */
  private buildFileParts(): FilePart[] {
    const parts: FilePart[] = [];
    for (const f of this.pendingFiles) {
      const part: FilePart = {
        uri: 'data:' + f.mime + ';base64,' + f.data,
        mime: f.mime,
        name: f.name
      };
      parts.push(part);
    }
    return parts;
  }

  private onInsertAttach(): void {
    const path: string = this.attachPath.trim();
    if (path.length === 0) {
      this.showToast('请先输入文件路径');
      return;
    }
    this.sheetVisible = false;
    this.inputText = this.inputText.length > 0
      ? this.inputText + ' ' + path
      : path;
    this.showToast('已插入路径，opencode 可读取该文件');
  }

  /** 连接器 / 定时任务：桌面端能力，给出说明 */
  private onOpenUnsupported(kind: string): void {
    this.unsupportedKind = kind;
    this.sheetKind = 'unsupported';
  }

  // ---------------- 发送 ----------------

  /** 是否可发送：有文字或有附件，且不在发送中 */
  private canSend(): boolean {
    return !this.sending && (this.inputText.trim().length > 0 || this.pendingFiles.length > 0);
  }

  private async send(): Promise<void> {
    const text: string = this.inputText.trim();
    const files: FilePart[] = this.buildFileParts();
    if ((text.length === 0 && files.length === 0) || this.sending) {
      return;
    }
    this.sending = true;
    // 立即本地回显（像 PC 端：消息先出现，再等服务端回包）
    const echo: string = text.length > 0 ? text
      : ('[附件] ' + files.length + ' 个文件');
    this.appendLocalUserMessage(echo);
    const res: ApiResult = await this.client.sendPromptWithAgent(this.sessionId, text, this.currentAgent, files);
    this.sending = false;
    if (res.ok) {
      this.inputText = '';
      this.pendingFiles = [];
      this.autoScroll = true;
      await this.refresh();
    } else {
      this.showToast('发送失败：' + res.error);
      // 失败则撤掉回显的这条，避免出现「假消息」
      this.removeLocalUserMessage(echo);
    }
  }

  /** 追加一条本地用户消息（回显） */
  private appendLocalUserMessage(text: string): void {
    const m: SessionMessageItem = new SessionMessageItem();
    m.id = 'local_' + Date.now();
    m.kind = 'user';
    m.text = text;
    m.timeCreated = Date.now();
    const list: SessionMessageItem[] = this.messages.slice(0);
    list.push(m);
    this.messages = list;
    // 自己刚发的消息：无条件贴底（内容高度变化也会触发一次，双保险）
    this.autoScroll = true;
    this.scroller.scrollEdge(Edge.Bottom);
  }

  /** 移除刚回显的本地消息（发送失败时） */
  private removeLocalUserMessage(text: string): void {
    const list: SessionMessageItem[] = [];
    for (const m of this.messages) {
      if (m.id.startsWith('local_') && m.text === text) {
        continue;
      }
      list.push(m);
    }
    this.messages = list;
  }

  private async interrupt(): Promise<void> {
    const res: ApiResult = await this.client.interrupt(this.sessionId);
    if (res.ok) {
      this.showToast('已发送中断请求');
      await this.refresh();
    } else {
      this.showToast('中断失败：' + res.error);
    }
  }

  private async onPermissionReply(requestID: string, reply: string): Promise<void> {
    const res: ApiResult = await this.client.replyPermission(this.sessionId, requestID, reply);
    if (res.ok) {
      const remain: PermissionRequest[] = [];
      for (const p of this.permissions) {
        if (p.id !== requestID) {
          remain.push(p);
        }
      }
      this.permissions = remain;
    } else {
      this.showToast('响应失败：' + res.error);
    }
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 0 }) {
        // ===== 顶栏 =====
        Row({ space: 10 }) {
          Image($r('app.media.icon_back'))
            .width(34)
            .height(34)
            .fillColor($r('app.color.text_primary'))
            .padding(6)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(17)
            .stateStyles({
              pressed: {
                .opacity(0.6)
                .scale({ x: 0.92, y: 0.92 })
              },
              normal: {
                .opacity(1)
                .scale({ x: 1, y: 1 })
              }
            })
            .onClick(() => {
              this.getUIContext().getRouter().back();
            })
          Column({ space: 2 }) {
            Text(this.sessionTitle)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              // 会话标题常很长：滚动展示而不是省略号
              .textOverflow({ overflow: TextOverflow.MARQUEE })
              .marqueeOptions({ start: true, step: 5, loop: -1, fromStart: true, delay: 800, fadeout: true })
            Row({ space: 6 }) {
              Text(this.serverName + '  ·  ' + this.sessionSub)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.MARQUEE })
                .marqueeOptions({ start: true, step: 4, loop: -1, fromStart: true, delay: 1000, fadeout: true })
                .layoutWeight(1)
                .flexShrink(1)
              if (this.running) {
                Text('运行中')
                  .fontSize(10)
                  .fontColor($r('app.color.warning'))
                  .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                  .backgroundColor($r('app.color.warning_bg'))
                  .borderRadius(4)
              }
            }
            .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 右侧胶囊按钮组
          Row({ space: 2 }) {
            if (this.running) {
              // 中断：浅底 + 红色停止方块，与旁边「更多」按钮同一视觉体系
              Row() {
                Row()
                  .width(11)
                  .height(11)
                  .borderRadius(2.5)
                  .backgroundColor($r('app.color.danger'))
              }
              .width(32)
              .height(32)
              .borderRadius(16)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .backgroundColor($r('app.color.input_bg'))
              .stateStyles({
                pressed: {
                  .opacity(0.6)
                  .scale({ x: 0.92, y: 0.92 })
                },
                normal: {
                  .opacity(1)
                  .scale({ x: 1, y: 1 })
                }
              })
              .onClick(() => {
                this.interrupt();
              })
            }
            Image($r('app.media.icon_more'))
              .width(32)
              .height(32)
              .fillColor($r('app.color.text_primary'))
              .padding(8)
              .stateStyles({
                pressed: {
                  .opacity(0.6)
                  .scale({ x: 0.92, y: 0.92 })
                },
                normal: {
                  .opacity(1)
                  .scale({ x: 1, y: 1 })
                }
              })
              .onClick(() => {
                this.sheetKind = 'actions';
                this.sheetVisible = true;
              })
          }
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(18)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 8 })
        .backgroundColor($r('app.color.page_bg'))

        if (this.errorText.length > 0) {
          Row({ space: 8 }) {
            Text(this.errorText)
              .fontSize(11)
              .fontColor($r('app.color.danger'))
              .layoutWeight(1)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('重试')
              .fontSize(11)
              .fontColor($r('app.color.primary'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.primary_bg'))
              .borderRadius(12)
              .stateStyles({
                pressed: {
                  .opacity(0.6)
                },
                normal: {
                  .opacity(1)
                }
              })
              .onClick(() => {
                this.refresh();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 6 })
        }

        if (this.firstLoading) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('app.color.primary'))
            Text('加载会话…')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
        }

        // ===== 消息区（含右下角回到底部）=====
        // 用 Scroll + Column 承载消息而不是 List：
        // List 懒加载在「单条消息极高」（几屏长的报告）时会把滚动范围算错，
        // 实测 26 条消息的会话只渲染出 1 条且无法上翻；Scroll 全量布局无此问题。
        Stack({ alignContent: Alignment.BottomEnd }) {
          Scroll(this.scroller) {
            Column({ space: 12 }) {
              if (!this.firstLoading && this.messages.length === 0 && this.errorText.length === 0) {
                Column({ space: 6 }) {
                  Text('还没有消息')
                    .fontSize(15)
                    .fontColor($r('app.color.text_secondary'))
                  Text('在下方输入框发送内容，开始与 opencode 对话')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .height(220)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }

              // 不要给这条 ForEach 加 keyGenerator（原来用 m.id）：
              // key 稳定的项不会重跑 item 生成器，MessageBubble 的 @Prop
              // 永远收不到新对象——实测流式消息文字/工具状态一直停在首次
              // 渲染的旧值。按索引 diff 时生成器重跑、@Prop 同步刷新，
              // 气泡内的展开状态（@State）随组件实例保留，不受影响。
              ForEach(this.messages, (m: SessionMessageItem) => {
                MessageBubble({ message: m })
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            // 内容高度变化时：用户原本就在底部（或首次加载）就自动贴底；
            // 正在上翻历史时（autoScroll=false）不拽回。
            .onAreaChange((_old: Area, area: Area) => {
              this.contentH = area.height as number;
              if (this.autoScroll) {
                this.scroller.scrollEdge(Edge.Bottom);
              }
            })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .onAreaChange((_old: Area, area: Area) => {
            this.viewH = area.height as number;
          })
          .onScroll((_xOffset: number, yOffset: number) => {
            // 距底部 12px 以内视为「在底部」：刷新时保持自动滚动，否则显示「回到底部」
            const atBottom: boolean = (this.contentH - this.viewH - yOffset) <= 12;
            this.autoScroll = atBottom;
            this.showScrollDown = !atBottom;
          })

          if (this.showScrollDown) {
            Image($r('app.media.icon_chevron_down'))
              .width(34)
              .height(34)
              .fillColor($r('app.color.text_secondary'))
              .padding(9)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(17)
              .shadow({ radius: 12, color: '#0F172A1A', offsetY: 2 })
              .margin({ right: 16, bottom: 12 })
              .stateStyles({
                pressed: {
                  .opacity(0.6)
                  .scale({ x: 0.92, y: 0.92 })
                },
                normal: {
                  .opacity(1)
                  .scale({ x: 1, y: 1 })
                }
              })
              .onClick(() => {
                this.scroller.scrollEdge(Edge.Bottom);
                this.autoScroll = true;
                this.showScrollDown = false;
              })
          }
        }
        .layoutWeight(1)
        .width('100%')

        // ===== 权限审批 =====
        if (this.permissions.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.permissions, (p: PermissionRequest) => {
              PermissionCard({
                request: p,
                onReply: (requestID: string, reply: string) => {
                  this.onPermissionReply(requestID, reply);
                }
              })
            })
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 6 })
        }

        // 快捷指令：横向滚动。
        // 不加右侧渐隐遮罩——遮罩会压住最后一个胶囊，看起来像被截断的脏边。
        Scroll() {
          Row({ space: 8 }) {
            this.QuickChip('解释这段代码', '请解释这段代码的作用与关键逻辑：')
            this.QuickChip('修复报错', '帮我定位并修复这个错误：')
            this.QuickChip('补充测试', '为这段代码补充单元测试：')
            this.QuickChip('代码评审', '对这次改动做一次代码评审，指出风险与改进点：')
            this.QuickChip('性能优化', '分析这段代码的性能瓶颈并给出优化方案：')
            this.QuickChip('写测试', '请为上述改动补充测试用例：')
          }
          .padding({ left: 14, right: 14 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(36)

        // ===== 输入区（悬浮态）=====
        Column({ space: 10 }) {
          // 上下文行：模型 / 专家
          Row({ space: 8 }) {
            Row({ space: 4 }) {
              Text(this.currentModelLabel())
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Image($r('app.media.icon_chevron_down'))
                .width(13)
                .height(13)
                .fillColor($r('app.color.text_secondary'))
            }
            .padding({ left: 12, right: 10, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(14)
            .stateStyles({
              pressed: {
                .opacity(0.6)
                .scale({ x: 0.97, y: 0.97 })
              },
              normal: {
                .opacity(1)
                .scale({ x: 1, y: 1 })
              }
            })
            .onClick(() => {
              this.sheetKind = 'model';
              this.sheetVisible = true;
            })
            .bindSheet($$this.sheetVisible, this.SheetContent(), {
              // 各面板高度按内容实测收紧（2848px 屏），避免「弹窗比内容大太多」：
              //   model     LARGE  内容(标题+搜索+10 余个模型行)基本填满
              //   agent     70%    内容约 1882px(8 个专家行)，留少量余量
              //   command   32%    内容约 764px(2 个技能行)
              //   attach    50%    内容约 1420px(3 入口 + 4 行 + 说明)
              //   info      52%    内容约 1301px(标题/ID/路径/关闭)，留底部余量
              //   actions   40%    内容约 1015px(标题 + 4 按钮)
              //   unsupported 30%  内容约 693px(标题 + 说明 + 按钮)
              //   file      32%    内容约 784px(标题 + 说明 + 输入 + 2 按钮)
              // 列表类(agent/command)内容增多时内部 List 自行滚动，不会裁掉入口。
              height: this.sheetHeight(),
              dragBar: true,
              showClose: true,
              backgroundColor: $r('app.color.card_bg')
            })
            if (this.currentAgent.length > 0) {
              Text('专家 · ' + this.currentAgent)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 待发送附件条：缩略图/文件名 + 体积，可单条移除
          if (this.pendingFiles.length > 0 || this.pickingFile) {
            Scroll() {
              Row({ space: 8 }) {
                if (this.pickingFile) {
                  Row({ space: 6 }) {
                    LoadingProgress()
                      .width(16)
                      .height(16)
                      .color($r('app.color.primary'))
                    Text('正在读取文件…')
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .height(36)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor($r('app.color.input_bg'))
                  .borderRadius(18)
                }
                ForEach(this.pendingFiles, (f: PickedFile, index: number) => {
                  Row({ space: 6 }) {
                    if (f.isImage) {
                      Image(f.uri)
                        .width(24)
                        .height(24)
                        .borderRadius(6)
                        .objectFit(ImageFit.Cover)
                    } else {
                      Image($r('app.media.icon_file'))
                        .width(20)
                        .height(20)
                        .fillColor($r('app.color.text_secondary'))
                    }
                    Column({ space: 1 }) {
                      Text(f.name)
                        .fontSize(11)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(FileUtil.sizeText(f.size))
                        .fontSize(10)
                        .fontColor($r('app.color.text_secondary'))
                    }
                    .alignItems(HorizontalAlign.Start)
                    .constraintSize({ maxWidth: 110 })
                    Image($r('app.media.icon_close'))
                      .width(14)
                      .height(14)
                      .fillColor($r('app.color.text_secondary'))
                      .onClick(() => {
                        this.onRemoveFile(index);
                      })
                  }
                  .height(36)
                  .padding({ left: 8, right: 8 })
                  .backgroundColor($r('app.color.input_bg'))
                  .borderRadius(18)
                }, (f: PickedFile, index: number) => f.name + '_' + index)
              }
              .padding({ left: 14, right: 14 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          // 悬浮输入框（不放未实现的语音入口，避免点了只弹「开发中」）
          Row({ space: 8 }) {
            TextArea({ placeholder: '发消息给 opencode…', text: this.inputText })
              .layoutWeight(1)
              .height(40)
              .fontSize(15)
              .backgroundColor(Color.Transparent)
              .padding({ left: 4, right: 4, top: 8, bottom: 8 })
              .onChange((value: string) => {
                this.inputText = value;
              })
            Image($r('app.media.icon_plus'))
              .width(24)
              .height(24)
              .fillColor($r('app.color.text_primary'))
              .borderRadius(12)
              .stateStyles({
                pressed: {
                  .opacity(0.6)
                  .scale({ x: 0.88, y: 0.88 })
                },
                normal: {
                  .opacity(1)
                  .scale({ x: 1, y: 1 })
                }
              })
              .onClick(() => {
                this.onOpenAttach();
              })

            Row() {
              Image($r('app.media.icon_arrow_up'))
                .width(20)
                .height(20)
                .fillColor(Color.White)
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.primary'))
            .opacity(this.canSend() ? 1.0 : 0.35)
            .enabled(this.canSend())
            .stateStyles({
              pressed: {
                .scale({ x: 0.9, y: 0.9 })
              },
              normal: {
                .scale({ x: 1, y: 1 })
              }
            })
            .onClick(() => {
              if (this.running) {
                this.interrupt();
              } else {
                this.send();
              }
            })
          }
          .width('100%')
          .height(52)
          .margin({ left: 14, right: 14 })
          .padding({ left: 16, right: 8 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(26)
          .shadow({ radius: 16, color: '#0F172A14', offsetY: 4 })
        }
        .width('100%')
        .padding({ top: 4, bottom: 14 })
        .backgroundColor($r('app.color.page_bg'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_bg'))
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 各面板的弹层高度：按内容实测收紧，避免「弹窗比内容大太多」。
   * 百分比相对屏幕高度；model 内容(标题+搜索+十余个模型行)基本填满 LARGE，保留 LARGE。
   */
  private sheetHeight(): SheetSize | number | string {
    if (this.sheetKind === 'model') {
      return SheetSize.LARGE;
    }
    if (this.sheetKind === 'agent') {
      return '70%';
    }
    if (this.sheetKind === 'command') {
      return '32%';
    }
    if (this.sheetKind === 'attach') {
      return '50%';
    }
    if (this.sheetKind === 'info') {
      return '52%';
    }
    if (this.sheetKind === 'actions') {
      return '40%';
    }
    if (this.sheetKind === 'unsupported') {
      return '30%';
    }
    // file（附加电脑文件）
    return '32%';
  }

  @Builder
  private SheetContent() {
    if (this.sheetKind === 'model') {
      this.ModelSheetContent()
    } else if (this.sheetKind === 'attach') {
      this.AttachSheetContent()
    } else if (this.sheetKind === 'agent') {
      this.AgentSheetContent()
    } else if (this.sheetKind === 'command') {
      this.CommandSheetContent()
    } else if (this.sheetKind === 'file') {
      this.FileSheetContent()
    } else if (this.sheetKind === 'unsupported') {
      this.UnsupportedSheetContent()
    } else if (this.sheetKind === 'info') {
      this.InfoSheetContent()
    } else if (this.sheetKind === 'actions') {
      this.ActionsSheetContent()
    }
  }

  @Builder
  private InfoSheetContent() {
    Column({ space: 12 }) {
      Text('会话信息')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Column({ space: 6 }) {
        Text('标题')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text(this.sessionTitle)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.input_bg'))
      .borderRadius(14)

      Column({ space: 6 }) {
        Text('会话 ID')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text(this.sessionId)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.input_bg'))
      .borderRadius(14)

      if (this.sessionSub.length > 0) {
        Column({ space: 6 }) {
          Text('工程路径')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text(this.sessionSub)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(14)
      }

      Button('关闭')
        .width('100%')
        .height(46)
        .fontSize(15)
        .backgroundColor($r('app.color.primary'))
        .onClick(() => {
          this.sheetVisible = false;
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 48, bottom: 18 })
    .borderRadius(20)
  }

  private copySessionId(): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.sessionId);
    pasteboard.getSystemPasteboard().setPasteData(data).then(() => {
      this.showToast('已复制会话 ID');
    }).catch(() => {
      this.showToast('复制失败');
    });
  }

  @Builder
  private ModelSheetContent() {
    ModelSheet({
      models: this.models,
      selectedId: this.currentModelId,
      onPick: (m: ModelInfo) => {
        this.onPickModel(m);
      }
    })
  }

  @Builder
  private AttachSheetContent() {
    AttachSheet({
      agents: this.agents,
      commands: this.commands,
      onPickAgent: () => {
        this.onOpenAgentPicker();
      },
      onPickCommand: () => {
        this.onOpenCommandPicker();
      },
      onTakePhoto: () => {
        this.onTakePhoto();
      },
      onPickPhoto: () => {
        this.onPickPhoto();
      },
      onPickFile: () => {
        this.onPickFile();
      },
      onUnsupported: (kind: string) => {
        this.onOpenUnsupported(kind);
      }
    })
  }

  /** 专家选择列表 */
  @Builder
  private AgentSheetContent() {
    Column({ space: 10 }) {
      Text('选择专家')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      List({ space: 2 }) {
        // 取消专家
        ListItem() {
          Row({ space: 10 }) {
            RadioDot({ selected: this.currentAgent.length === 0 })
            Text('不使用专家')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          .backgroundColor(this.currentAgent.length === 0 ? $r('app.color.primary_bg') : Color.Transparent)
          .borderRadius(12)
          .stateStyles({
            pressed: {
              .opacity(0.6)
            },
            normal: {
              .opacity(1)
            }
          })
          .onClick(() => {
            this.onClearAgent();
          })
        }
        ForEach(this.agents, (a: AgentInfo) => {
          ListItem() {
            Row({ space: 10 }) {
              RadioDot({ selected: this.currentAgent === a.name })
              Column({ space: 2 }) {
                Text(a.name)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(this.currentAgent === a.name ? FontWeight.Medium : FontWeight.Normal)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (a.description.length > 0) {
                  Text(a.description)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(2)
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              if (a.mode.length > 0) {
                Text(a.mode)
                  .fontSize(11)
                  .fontColor($r('app.color.primary'))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .backgroundColor($r('app.color.primary_bg'))
                  .borderRadius(4)
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .backgroundColor(this.currentAgent === a.name ? $r('app.color.primary_bg') : Color.Transparent)
            .borderRadius(12)
            .stateStyles({
              pressed: {
                .opacity(0.6)
              },
              normal: {
                .opacity(1)
              }
            })
            .onClick(() => {
              this.onPickAgent(a);
            })
          }
        }, (a: AgentInfo) => a.id)
      }
      .layoutWeight(1)
      .width('100%')
      .divider(null)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 48 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }

  /** 技能（斜杠命令）选择列表 */
  @Builder
  private CommandSheetContent() {
    Column({ space: 10 }) {
      Text('选择技能')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text('点击后插入输入框，可继续补充内容')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      List({ space: 2 }) {
        ForEach(this.commands, (c: CommandInfo) => {
          ListItem() {
            Column({ space: 3 }) {
              Text('/' + c.name)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (c.description.length > 0) {
                Text(c.description)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(2)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .borderRadius(12)
            .stateStyles({
              pressed: {
                .opacity(0.6)
              },
              normal: {
                .opacity(1)
              }
            })
            .onClick(() => {
              this.onPickCommand(c);
            })
          }
        }, (c: CommandInfo) => c.name)
      }
      .layoutWeight(1)
      .width('100%')
      .divider(null)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 48 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }

  /** 附加电脑文件：输入路径 → 插入输入框 */
  @Builder
  private FileSheetContent() {
    Column({ space: 12 }) {
      Text('附加电脑文件')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text('远程模式下 opencode 只能读取电脑上的文件。输入文件路径后插入输入框，opencode 即可读取内容。')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ placeholder: '例如 E:\\Code\\HuaWei\\opencode\\README.md', text: this.attachPath })
        .height(46)
        .fontSize(14)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.attachPath = v;
        })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .backgroundColor($r('app.color.input_bg'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.sheetVisible = false;
          })
        Button('插入输入框')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            this.onInsertAttach();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 48, bottom: 18 })
    .borderRadius(20)
  }

  /** 桌面端能力说明（连接器 / 定时任务） */
  @Builder
  private UnsupportedSheetContent() {
    Column({ space: 12 }) {
      Text(this.unsupportedKind === 'connector' ? '连接器' : '定时任务')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(this.unsupportedKind === 'connector'
        ? '连接器（MCP）是桌面端能力：需要在电脑端的 opencode.json 中配置 MCP 服务器，然后重启 opencode serve，手机端刷新后即可使用。'
        : '定时任务是桌面端能力：请在电脑端用系统计划任务（Windows 任务计划程序 / cron）定时调用 opencode，或使用 opencode 自带的自动化配置。')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .lineHeight(20)

      Button('知道了')
        .width('100%')
        .height(46)
        .fontSize(15)
        .backgroundColor($r('app.color.primary'))
        .onClick(() => {
          this.sheetVisible = false;
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 48, bottom: 18 })
    .borderRadius(20)
  }

  @Builder
  private QuickChip(label: string, prefix: string) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(14)
      .stateStyles({
        pressed: {
          .opacity(0.6)
          .scale({ x: 0.96, y: 0.96 })
        },
        normal: {
          .opacity(1)
          .scale({ x: 1, y: 1 })
        }
      })
      .onClick(() => {
        if (this.inputText.trim().length === 0) {
          this.inputText = prefix;
        } else {
          this.inputText = prefix + this.inputText;
        }
      })
  }

  @Builder
  private ActionsSheetContent() {
    Column({ space: 10 }) {
      Text('会话操作')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Button('会话信息')
        .width('100%')
        .height(46)
        .fontSize(15)
        .backgroundColor($r('app.color.input_bg'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.sheetVisible = false;
          setTimeout(() => {
            this.sheetKind = 'info';
            this.sheetVisible = true;
          }, 180);
        })

      Button('复制会话 ID')
        .width('100%')
        .height(46)
        .fontSize(15)
        .backgroundColor($r('app.color.input_bg'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.sheetVisible = false;
          this.copySessionId();
        })

      Button('附加电脑文件路径')
        .width('100%')
        .height(46)
        .fontSize(15)
        .backgroundColor($r('app.color.input_bg'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.sheetVisible = false;
          setTimeout(() => {
            this.onOpenAttachFile();
          }, 180);
        })

      Button('重新加载')
        .width('100%')
        .height(46)
        .fontSize(15)
        .backgroundColor($r('app.color.input_bg'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.sheetVisible = false;
          this.refresh();
        })

      if (this.running) {
        Button('中断执行')
          .width('100%')
          .height(46)
          .fontSize(15)
          .backgroundColor($r('app.color.danger'))
          .onClick(() => {
            this.sheetVisible = false;
            this.interrupt();
          })
      }

      Button('取消')
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => {
          this.sheetVisible = false;
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 48, bottom: 18 })
    .borderRadius(20)
  }
}
