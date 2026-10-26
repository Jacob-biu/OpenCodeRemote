import { Constants } from '../common/Constants';
import { Utils } from '../common/Utils';
import { SessionInfo } from '../model/Session';
import { ModelInfo } from '../model/Model';
import { ServerProfile } from '../model/Server';
import { ConfigStore } from '../store/ConfigStore';
import { ServerStore } from '../store/ServerStore';
import {
  OpenCodeClient,
  CreatedSession,
  SessionsResult,
  ApiResult,
  ModelsResult
} from '../api/OpenCodeClient';
import { ModelSheet } from '../components/ModelSheet';
import { ConnectPanel } from '../components/ConnectPanel';
import { SettingsPanel } from '../components/SettingsPanel';

@Entry
@Component
struct SessionListPage {
  @State sessions: SessionInfo[] = [];
  @State serverName: string = '';
  @State serverSub: string = '';
  @State errorText: string = '';
  // 抽屉（官方 SideBarContainer：Overlay 模式 + 官方动画 + 左缘右滑展开）
  @State drawerOpen: boolean = false;
  @State servers: ServerProfile[] = [];
  @State currentId: string = '';
  // 服务器编辑
  @State editVisible: boolean = false;
  @State editIsNew: boolean = false;
  @State editTargetId: string = '';
  @State editName: string = '';
  @State editHost: string = '';
  @State editPort: string = '';
  @State editUser: string = '';
  @State editPass: string = '';
  @State editHttps: boolean = false;
  // 新建会话
  @State newVisible: boolean = false;
  @State newPath: string = '';
  @State recentPaths: string[] = [];
  @State creating: boolean = false;
  // 模型
  @State models: ModelInfo[] = [];
  @State modelSheetVisible: boolean = false;
  @State selectedModelId: string = '';
  // 会话重命名
  @State renameId: string = '';
  @State renameTitle: string = '';
  // 连接方式弹窗
  @State connectSheetVisible: boolean = false;
  // 统一弹层（ArkUI 一个组件只支持一个 bindSheet）
  @State sheetVisible: boolean = false;
  @State sheetKind: string = '';
  // 搜索与刷新
  @State searchText: string = '';
  @State refreshing: boolean = false;
  // 会话筛选：all | running
  @State filter: string = 'all';
  // 手势诊断：只打第一条日志
  @State gestureLogged: boolean = false;

  private client: OpenCodeClient = new OpenCodeClient(ConfigStore.load());
  private timer: number = -1;

  aboutToAppear(): void {
    this.reloadServers();
  }

  onPageShow(): void {
    this.reloadServers();
    this.refresh();
    this.startPolling();
  }

  onPageHide(): void {
    this.stopPolling();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  private reloadServers(): void {
    this.servers = ServerStore.all();
    const cur: ServerProfile | null = ServerStore.current();
    this.currentId = cur !== null ? cur.id : '';
    this.serverName = cur !== null ? cur.name : '未配置';
    this.serverSub = cur !== null ? (cur.host + ':' + cur.port) : '';
    this.client = new OpenCodeClient(ConfigStore.load());
  }

  /** 从工程路径取最后一级目录名 */
  private dirName(s: SessionInfo): string {
    if (s.location.length === 0) {
      return '';
    }
    // opencode 返回的工程路径可能是 POSIX 斜杠，也可能是 Windows 反斜杠
    const parts: string[] = s.location.split('/');
    let last: string = parts[parts.length - 1];
    if (last.indexOf('\\') >= 0) {
      const winParts: string[] = last.split('\\');
      last = winParts[winParts.length - 1];
    }
    return last.length > 0 ? last : s.location;
  }

  /**
   * 按筛选 + 关键词过滤。
   * 注意：必须先应用「全部 / 运行中」筛选，再按关键词过滤；
   * 不能在无关键词时提前 return，否则筛选会被整体跳过（表现为筛选无效）。
   */
  private visibleSessions(): SessionInfo[] {
    const kw: string = this.searchText.trim().toLowerCase();
    const out: SessionInfo[] = [];
    for (const s of this.sessions) {
      if (this.filter === 'running' && !s.running) {
        continue;
      }
      if (kw.length > 0 && s.title.toLowerCase().indexOf(kw) < 0 && s.id.toLowerCase().indexOf(kw) < 0
        && s.location.toLowerCase().indexOf(kw) < 0) {
        continue;
      }
      out.push(s);
    }
    return out;
  }

  /** 空状态标题（按当前筛选/搜索给出对应文案） */
  private emptyTitle(): string {
    if (this.filter === 'running') {
      return '没有运行中的会话';
    }
    return this.searchText.length > 0 ? '没有匹配的会话' : '还没有会话';
  }

  /** 空状态副标题 */
  private emptyHint(): string {
    if (this.filter === 'running') {
      return '点上方「全部」查看所有会话';
    }
    return this.searchText.length > 0 ? '换个关键词试试' : '点右上角 + 让 opencode 开始新任务';
  }

  /** 运行中的会话数量（用于筛选计数） */
  private runningCount(): number {
    let n: number = 0;
    for (const s of this.sessions) {
      if (s.running) {
        n++;
      }
    }
    return n;
  }

  /** 是否存在运行中的会话 */
  private hasRunning(): boolean {
    for (const s of this.sessions) {
      if (s.running) {
        return true;
      }
    }
    return false;
  }

  /**
   * 筛选 chip（带计数，常驻显示）。
   * 注意：@Builder 的参数是「按值」传入、不随状态刷新，
   * 所以计数必须在 builder 内部直接读 this.* ，不能靠参数传。
   */
  @Builder
  private FilterChip(label: string, value: string) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.filter === value ? $r('app.color.primary') : $r('app.color.text_secondary'))
      Text(String(value === 'all' ? this.sessions.length : this.runningCount()))
        .fontSize(11)
        .fontColor(this.filter === value ? $r('app.color.primary') : $r('app.color.text_secondary'))
        .opacity(0.75)
    }
    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
    .backgroundColor(this.filter === value ? $r('app.color.primary_bg') : $r('app.color.card_bg'))
    .borderRadius(13)
    .stateStyles({
      pressed: {
        .opacity(0.6)
      },
      normal: {
        .opacity(1)
      }
    })
    .onClick(() => {
      this.filter = value;
    })
  }

  private startPolling(): void {
    this.stopPolling();
    const stored: number = AppStorage.get<number>('pollIntervalMs') as number;
    const period: number = stored > 0 ? stored : Constants.POLL_INTERVAL_MS;
    this.timer = setInterval(() => {
      this.refresh();
    }, period);
  }

  private stopPolling(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async refresh(): Promise<void> {
    const result: SessionsResult = await this.client.fetchSessions();
    this.errorText = result.error;
    const list: SessionInfo[] = result.sessions;
    for (const s of list) {
      s.running = result.activeIDs.indexOf(s.id) >= 0;
    }
    console.info('[active] sessions=' + list.length + ' activeIDs=' + result.activeIDs.length +
      ' running=' + list.filter((s: SessionInfo) => s.running).length);
    list.sort((a: SessionInfo, b: SessionInfo) => b.timeUpdated - a.timeUpdated);
    this.mergeSessions(list);
  }

  /**
   * 把新拉到的会话合入 @State sessions：内容没变就一个字节都不动。
   *
   * 为什么不能直接 this.sessions = list：
   * 轮询每 2 秒会拿到一摞全新 SessionInfo 对象，直接赋值意味着 ForEach
   * 每 2 秒全量重 diff + 重建全部渲染节点。上一轮长跑会话中实测这种
   * 持续抖动会损坏列表：14 个会话只渲染出 9 个（5 个消失、2 个变成
   * 空白卡片）、滚动范围塌缩到无法上滚，且数据层完全正常（重启即恢复），
   * 属于 ForEach + 懒加载在数组高频替换下的渲染态损坏。
   *
   * 合入策略：
   * 1. 按 id 逐项对比，未变化的会话复用原对象引用（ForEach 按 key diff
   *    时引用不变 → 该行渲染节点原样保留，不重建）；
   * 2. 整表顺序与内容都零变化时完全不赋值 —— @State 不触发刷新，
   *    ForEach 一次都不重建，从根上消除持续抖动。
   */
  private mergeSessions(list: SessionInfo[]): void {
    const old: SessionInfo[] = this.sessions;
    const merged: SessionInfo[] = [];
    for (const s of list) {
      let keep: SessionInfo | null = null;
      for (const o of old) {
        if (o.id === s.id) {
          keep = o;
          break;
        }
      }
      if (keep !== null && keep.title === s.title && keep.location === s.location &&
        keep.timeUpdated === s.timeUpdated && keep.agent === s.agent && keep.running === s.running) {
        merged.push(keep);
      } else {
        merged.push(s);
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
    this.sessions = merged;
  }

  /**
   * 会话行的 ForEach key：id + 全部可见字段。
   *
   * 为什么不能只用 s.id：
   * ForEach 带 keyGenerator 时，key 不变的项会复用组件实例、不重跑
   * item 生成器，闭包里捕获的还是旧 SessionInfo 对象。实测后果：
   * 服务端改了标题/时间，this.sessions 已是新数据（日志实证），
   * 但列表卡片文字一直停在首次渲染的旧值，直到重启应用才刷新。
   * 把可见字段拼进 key 后，任何内容变化都会换 key → 重建该行 →
   * 用新数据重新渲染；内容没变时 key 稳定，行状态原样保留。
   */
  private rowKey(s: SessionInfo): string {
    return s.id + '|' + s.title + '|' + s.agent + '|' + s.location + '|' +
      s.timeUpdated + '|' + (s.running ? '1' : '0');
  }

  // ---------------- 抽屉（官方 SideBarContainer，自带展开/收起动画与左缘右滑手势） ----------------

  private openDrawer(): void {
    console.info('[drawer] openDrawer -> true');
    this.drawerOpen = true;
  }

  private closeDrawer(): void {
    console.info('[drawer] closeDrawer -> false');
    this.drawerOpen = false;
  }

  // ---------------- 会话 ----------------

  private openSession(s: SessionInfo): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/SessionDetailPage',
      params: { sessionId: s.id, title: s.title, location: s.location }
    });
  }

  /** 删除会话：二次确认（不可恢复） */
  private onDeleteSession(s: SessionInfo): void {
    this.getUIContext().showAlertDialog({
      title: '删除会话？',
      message: '「' + (s.title.length > 0 ? s.title : '(未命名会话)') + '」的聊天记录将永久删除，不可恢复',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.client.deleteSession(s.id).then((res: ApiResult) => {
            if (res.ok) {
              this.refresh();
            } else {
              this.errorText = '删除失败：' + res.error;
            }
          });
        }
      }
    });
  }

  /** 左滑铅笔：重命名会话 */
  private onShowRename(s: SessionInfo): void {
    this.renameId = s.id;
    this.renameTitle = s.title;
    this.sheetKind = 'rename';
    this.sheetVisible = true;
  }

  private onSaveRename(): void {
    const title: string = this.renameTitle.trim();
    if (title.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '标题不能为空' });
      return;
    }
    this.client.renameSession(this.renameId, title).then((res: ApiResult) => {
      if (res.ok) {
        this.sheetVisible = false;
        this.showToast('已重命名');
        this.refresh();
      } else {
        this.showToast('重命名失败：' + res.error);
      }
    });
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private openSheet(kind: string): void {
    this.sheetKind = kind;
    this.sheetVisible = true;
  }

  /**
   * 各面板的弹层高度：按内容实测收紧，避免「弹窗比内容大太多」。
   * 百分比相对屏幕高度；model 内容(标题+搜索+十余个模型行)超出，保留 78% 内部滚动。
   */
  private sheetHeight(): SheetSize | number | string {
    if (this.sheetKind === 'model') {
      return '78%';
    }
    if (this.sheetKind === 'new') {
      return '70%';
    }
    if (this.sheetKind === 'settings') {
      return '50%';
    }
    if (this.sheetKind === 'edit' || this.sheetKind === 'connect') {
      return '54%';
    }
    // rename（重命名会话）
    return '26%';
  }

  // ---------------- 新建会话 ----------------

  private onNewSession(): void {
    this.sheetKind = 'new';
    this.sheetVisible = true;
    this.creating = false;
    const paths: string[] = [];
    for (const s of this.sessions) {
      if (s.location.length > 0 && paths.indexOf(s.location) < 0) {
        paths.push(s.location);
      }
      // 最多 3 条：再多会把「模型」与「创建会话」挤出弹层可视区
      if (paths.length >= 3) {
        break;
      }
    }
    this.recentPaths = paths;
    if (this.newPath.length === 0 && paths.length > 0) {
      this.newPath = paths[0];
    }
    this.loadModels();
  }

  private loadModels(): void {
    this.client.fetchModels().then((res: ModelsResult) => {
      if (res.error.length === 0) {
        this.models = res.models;
      }
    });
  }

  private currentModelLabel(): string {
    if (this.selectedModelId.length === 0) {
      return '默认模型';
    }
    for (const m of this.models) {
      if (m.id === this.selectedModelId) {
        return m.displayName();
      }
    }
    return '默认模型';
  }

  private onCreateSession(): void {
    let modelId: string = '';
    let providerID: string = '';
    for (const m of this.models) {
      if (m.id === this.selectedModelId) {
        modelId = m.id;
        providerID = m.providerID;
        break;
      }
    }
    this.creating = true;
    this.client.createSessionWithOptionsParsed(this.newPath.trim(), modelId, providerID)
      .then((created: CreatedSession) => {
        this.creating = false;
        if (created.error.length === 0 && created.session.id.length > 0) {
          this.sheetVisible = false;
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/SessionDetailPage',
            params: {
              sessionId: created.session.id,
              title: created.session.title,
              location: created.session.location
            }
          });
        } else {
          this.errorText = '创建失败：' + created.error;
        }
      });
  }

  // ---------------- 服务器管理 ----------------

  private onAddServer(): void {
    this.editIsNew = true;
    this.editTargetId = '';
    this.editName = '';
    this.editHost = '';
    this.editPort = String(Constants.DEFAULT_PORT);
    this.editUser = Constants.DEFAULT_USERNAME;
    this.editPass = '';
    this.editHttps = false;
    this.sheetKind = 'edit';
    this.sheetVisible = true;
  }

  private onEditServer(p: ServerProfile): void {
    this.editIsNew = false;
    this.editTargetId = p.id;
    this.editName = p.name;
    this.editHost = p.host;
    this.editPort = String(p.port);
    this.editUser = p.username;
    this.editPass = p.password;
    this.editHttps = p.useHttps;
    this.sheetKind = 'edit';
    this.sheetVisible = true;
  }

  private onSaveServer(): void {
    if (this.editHost.trim().length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写主机地址' });
      return;
    }
    let port: number = Number(this.editPort);
    if (isNaN(port) || port <= 0 || port > 65535) {
      port = Constants.DEFAULT_PORT;
    }
    const p: ServerProfile = new ServerProfile();
    p.id = this.editIsNew ? '' : this.editTargetId;
    p.name = this.editName.trim().length > 0 ? this.editName.trim() : (this.editHost + ':' + port);
    p.host = this.editHost.trim();
    p.port = port;
    p.username = this.editUser.trim().length > 0 ? this.editUser.trim() : Constants.DEFAULT_USERNAME;
    p.password = this.editPass;
    p.useHttps = this.editHttps;
    ServerStore.save(p);
    this.sheetVisible = false;
    this.reloadServers();
    this.refresh();
  }

  /** 删除服务器前确认（仅本地配置） */
  private onAskDeleteServer(): void {
    this.getUIContext().showAlertDialog({
      title: '删除这个服务器？',
      message: '仅删除本地配置，不影响电脑上的 opencode',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          ServerStore.remove(this.editTargetId);
          this.sheetVisible = false;
          this.reloadServers();
          this.refresh();
        }
      }
    });
  }

  private onSelectServer(p: ServerProfile): void {
    ServerStore.setCurrent(p.id);
    this.closeDrawer();
    this.reloadServers();
    this.refresh();
  }

  build() {
    // 官方侧边栏容器（ArkUI 系统组件，V1 状态管理完全兼容）：
    // Overlay 模式 + 官方展开/收起动画 + 屏幕左缘右滑拉出侧边栏
    SideBarContainer(SideBarContainerType.Overlay) {
      // 第一个子组件：侧边栏

      Column() {
          Row({ space: 10 }) {
            Text('服务器')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Image($r('app.media.icon_close'))
              .width(26)
              .height(26)
              .fillColor($r('app.color.text_secondary'))
              .padding(6)
              .backgroundColor($r('app.color.input_bg'))
              .borderRadius(13)
              .stateStyles({
                pressed: {
                  .opacity(0.6)
                  .scale({ x: 0.9, y: 0.9 })
                },
                normal: {
                  .opacity(1)
                  .scale({ x: 1, y: 1 })
                }
              })
              .onClick(() => {
                this.closeDrawer();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 12, top: 14, bottom: 10 })

          Divider().color($r('app.color.divider'))

          if (this.servers.length === 0) {
            Text('还没有添加服务器')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .padding(20)
          } else {
            List({ space: 8 }) {
              ForEach(this.servers, (p: ServerProfile) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Column({ space: 4 }) {
                      Text(p.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 6 }) {
                        Text(p.host + ':' + p.port + (p.useHttps ? ' · HTTPS' : ''))
                          .fontSize(11)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                        if (p.id === this.currentId) {
                          Text('当前')
                            .fontSize(10)
                            .fontColor($r('app.color.primary'))
                            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                            .backgroundColor($r('app.color.primary_bg'))
                            .borderRadius(4)
                        }
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Image($r('app.media.icon_edit'))
                      .width(30)
                      .height(30)
                      .fillColor($r('app.color.text_secondary'))
                      .padding(6)
                      .backgroundColor($r('app.color.input_bg'))
                      .borderRadius(15)
                      .flexShrink(0)
                      .stateStyles({
                        pressed: {
                          .opacity(0.6)
                          .scale({ x: 0.9, y: 0.9 })
                        },
                        normal: {
                          .opacity(1)
                          .scale({ x: 1, y: 1 })
                        }
                      })
                      .onClick(() => {
                        this.onEditServer(p);
                      })
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor($r('app.color.card_bg'))
                  .borderRadius(12)
                  .stateStyles({
                    pressed: {
                      .opacity(0.65)
                    },
                    normal: {
                      .opacity(1)
                    }
                  })
                  .onClick(() => {
                    this.onSelectServer(p);
                  })
                }
              // 不加 keyGenerator（旧实现用 p.id）：key 稳定的行不会重跑
              // 生成器，「当前」徽标（读 this.currentId）切换服务器后滞停
              // 在旧行上。按索引 diff 时生成器重跑，徽标实时跟上。
              })
            }
            .layoutWeight(1)
            .width('100%')
            .padding({ left: 12, right: 12, top: 8 })
            .divider(null)
            .scrollBar(BarState.Off)
          }

          Row({ space: 10 }) {
            Image($r('app.media.icon_gear'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_primary'))
            Text('设置')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Image($r('app.media.icon_chevron'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_secondary'))
          }
          .width('92%')
          .padding({ top: 12, bottom: 12 })
          .borderRadius(14)
          .stateStyles({
            pressed: {
              .opacity(0.6)
            },
            normal: {
              .opacity(1)
            }
          })
          .onClick(() => {
            // 设置改为底部上弹的 sheet：整页形态内容太少、留白过大
            this.closeDrawer();
            setTimeout(() => {
              this.openSheet('settings');
            }, 180);
          })

          Button('＋ 添加服务器', { type: ButtonType.Capsule })
            .width('92%')
            .height(46)
            .fontSize(14)
            .backgroundColor($r('app.color.primary'))
            .margin({ bottom: 20, top: 8 })
            .onClick(() => {
              this.closeDrawer();
              // 等抽屉收起动画结束再弹 sheet，否则会被抽屉移除打断
              setTimeout(() => {
                this.openSheet('connect');
              }, 180);
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
        // 避让状态栏：标题行与关闭按钮原本被状态栏压住，点不到
        .padding({ top: 36 })
        // 在抽屉自身上向左滑也能收起（用 parallelGesture：
        // 同节点用 .gesture() 会吃掉子节点的 onClick，parallelGesture 不会）
        .parallelGesture(
          PanGesture({ direction: PanDirection.Left, distance: 8 })
            .onActionEnd(() => {
              this.closeDrawer();
            })
        )
  

      // 第二个子组件：主内容区

            Stack({ alignContent: Alignment.TopStart }) {
  Column({ space: 0 }) {
            Row({ space: 10 }) {
              Image($r('app.media.icon_menu'))
                .width(34)
                .height(34)
                .fillColor($r('app.color.text_primary'))
                .padding(5)
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
                  this.openDrawer();
                })
              Column({ space: 1 }) {
                Text(this.serverName)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  // 服务器名（隧道域名）常常超长：滚动展示而不是省略号
                  .textOverflow({ overflow: TextOverflow.MARQUEE })
                  .marqueeOptions({ start: true, step: 5, loop: -1, fromStart: true, delay: 800, fadeout: true })
                Text(this.serverSub)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Image($r('app.media.icon_plus'))
                .width(34)
                .height(34)
                .fillColor($r('app.color.text_primary'))
                .padding(5)
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
                  this.onNewSession();
                })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 8 })

            // 搜索框
            Row({ space: 8 }) {
              TextInput({ placeholder: '搜索会话（标题 / ID / 路径）', text: this.searchText })
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(19)
                .padding({ left: 14, right: 14 })
                .onChange((v: string) => {
                  this.searchText = v;
                })
              if (this.searchText.length > 0) {
                Text('清空')
                  .fontSize(12)
                  .fontColor($r('app.color.primary'))
                  .padding({ left: 8, right: 4, top: 4, bottom: 4 })
                  .borderRadius(10)
                  .stateStyles({
                    pressed: {
                      .opacity(0.6)
                    },
                    normal: {
                      .opacity(1)
                    }
                  })
                  .onClick(() => {
                    this.searchText = '';
                  })
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, bottom: 6 })

            // 筛选：常驻显示（带计数），点击即切换
            Row({ space: 8 }) {
              this.FilterChip('全部', 'all')
              this.FilterChip('运行中', 'running')
            }
            .width('100%')
            .padding({ left: 14, right: 14, bottom: 6 })

            if (this.errorText.length > 0) {
              Row({ space: 8 }) {
                Text(this.errorText)
                  .fontSize(12)
                  .fontColor($r('app.color.danger'))
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('重试')
                  .fontSize(12)
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

            if (this.visibleSessions().length === 0) {
              Column({ space: 8 }) {
                Text(this.emptyTitle())
                  .fontSize(15)
                  .fontColor($r('app.color.text_secondary'))
                Text(this.emptyHint())
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .width('100%')
            } else {
              Refresh({ refreshing: $$this.refreshing }) {
                List({ space: 8 }) {
                  ForEach(this.visibleSessions(), (s: SessionInfo) => {
                    ListItem() {
                      this.SessionRow(s)
                    }
                    .swipeAction({
                      end: this.SessionSwipeActions(s),
                      edgeEffect: SwipeEdgeEffect.Spring
                    })
                  }, (s: SessionInfo) => this.rowKey(s))
                }
                .width('100%')
                .height('100%')
                .padding({ left: 14, right: 14 })
                .divider(null)
                .scrollBar(BarState.Off)
              }
              .layoutWeight(1)
              .width('100%')
              .onRefreshing(() => {
                this.refresh().then(() => {
                  this.refreshing = false;
                });
              })
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.page_bg'))
          .bindSheet($$this.sheetVisible, this.SheetContent(), {
            // 高度按内容实测收紧（2848px 屏），避免弹层远大于内容、底部一大片空白：
            //   model     78%  内容(标题+搜索+十余个模型行)超出，内部滚动
            //   new       70%  内容约 1844px，多留 2% 让「创建会话」按钮不贴屏幕底缘
            //   settings  50%  内容约 1335px（三个分区卡 + 清空按钮）
            //   edit      54%  内容约 1456px（地址/主机/端口/HTTPS/用户名/口令 + 3 按钮）
            //   connect   54%  内容约 1440px（两个页签 + 4 输入 + 2 按钮 + 连接帮助）
            //   rename    26%  内容约 644px（标题 + 输入 + 2 按钮）
            height: this.sheetHeight(),
            dragBar: true,
            showClose: true,
            backgroundColor: $r('app.color.card_bg')
          })

          // 左缘右滑展开抽屉。
          // 官方 showSideBarWithGesture（滑动显示/隐藏侧边栏）需 API 26+，
          // 本工程 targetSdk 6.1.1(24) 不可用，故用官方 PanGesture 作边缘触发器；
          // 用 parallelGesture 与 ListItem 的 swipeAction 并行：
          // 右滑(offsetX>0) 开抽屉、左滑(offsetX<0) 出操作按钮，两者互不干扰。
          .parallelGesture(
            PanGesture({ direction: PanDirection.Right, distance: 8 })
              .onActionEnd((event: GestureEvent) => {
                // 抽屉已打开时不响应，避免「收起已滑开的条目」误触发开抽屉
                if (this.drawerOpen) {
                  return;
                }
                if (px2vp(event.offsetX) > 15) {
                  this.drawerOpen = true;
                }
              })
          )

            // 抽屉打开时的内容区遮罩：
            // - 覆盖内容区 → 列表不可点击（只响应遮罩自身事件）
            // - 点空白处（遮罩）收起抽屉
            // - 在遮罩上向左滑也能收起抽屉
            // 注意：手势放在外层、点击放在内层，
            // 同一个节点上 .gesture() 会吃掉 onClick。
            if (this.drawerOpen) {
              Column() {
                Column()
                  .width('100%')
                  .height('100%')
                  .onClick(() => {
                    this.closeDrawer();
                  })
              }
              .width('100%')
              .height('100%')
              .backgroundColor('#33000000')
              .gesture(
                PanGesture({ direction: PanDirection.Left, distance: 8 })
                  .onActionEnd(() => {
                    this.closeDrawer();
                  })
              )
            }
  
      }
      .width('100%')
      .height('100%')
    }
    // 官方推荐写法：$$ 双向绑定（API 10+）。
    // 注意：不能再叠加 onChange 回写，否则会把外部置的 false 覆盖回 true，
    // 表现为抽屉只能开不能关（已在模拟器上复现并验证）。
    .showSideBar($$this.drawerOpen)
    .autoHide(true)
    .showControlButton(false)
    .sideBarWidth(240)
    .minSideBarWidth(200)
    .maxSideBarWidth(320)
    .minContentWidth(0)
    .width('100%')
    .height('100%')
  }

  

  

  /** 会话条目：左滑露出【编辑 + 删除】圆形按钮 */
  @Builder
  private SessionRow(s: SessionInfo) {
    Stack({ alignContent: Alignment.End }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          // 第一行：标题（超长可横向滚动，不省略号）+ agent + 运行中
          Row({ space: 6 }) {
            // 标题超长时跑马灯滚动（用 Text 的 MARQUEE 溢出模式：
            // 纯文本渲染不参与触摸，不会抢掉 swipeAction 的手势）
            Text(s.title.length > 0 ? s.title : '(未命名会话)')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.MARQUEE })
              // 跑马灯：无限循环、两端淡出，超长标题/路径滚动展示而非省略号
              .marqueeOptions({ start: true, step: 6, loop: -1, fromStart: true, delay: 600, fadeout: true })
              .layoutWeight(1)

            if (s.agent.length > 0 && s.agent !== 'build') {
              Text(s.agent)
                .fontSize(10)
                .fontColor($r('app.color.primary'))
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .backgroundColor($r('app.color.primary_bg'))
                .borderRadius(4)
            }

            if (s.running) {
              Text('运行中')
                .fontSize(10)
                .fontColor($r('app.color.warning'))
                .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                .backgroundColor($r('app.color.warning_bg'))
                .borderRadius(6)
            }
          }
          .width('100%')

          // 第二行：完整工作路径（超长可横向滚动）+ 时间
          Row({ space: 6 }) {
            // 工作路径：超长时跑马灯滚动展示
            Text(s.location.length > 0 ? s.location : this.dirName(s))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.MARQUEE })
              .marqueeOptions({ start: true, step: 5, loop: -1, fromStart: true, delay: 900, fadeout: true })
              .layoutWeight(1)

            Text(Utils.formatDateTime(s.timeUpdated))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(14)
      .stateStyles({
        pressed: {
          .opacity(0.65)
        },
        normal: {
          .opacity(1)
        }
      })
      .onClick(() => {
        this.openSession(s);
      })
    }
    .width('100%')
    .height(76)
  }

  /**
   * 官方滑动操作区：左滑时由 ArkUI 从右侧滑出（带 spring 动画），
   * 两个圆形按钮随手指拖动实时跟随，不是「本来就在那儿」。
   */
  @Builder
  private SessionSwipeActions(s: SessionInfo) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Image($r('app.media.icon_edit'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.text_primary'))
        Text('编辑')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      // 圆形按钮：宽=高=52vp，borderRadius 取一半即成正圆
      .width(52)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.input_bg'))
      .borderRadius(26)
      .stateStyles({
        pressed: {
          .opacity(0.65)
        },
        normal: {
          .opacity(1)
        }
      })
      .onClick(() => {
        this.onShowRename(s);
      })

      Column({ space: 2 }) {
        Image($r('app.media.icon_trash'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.danger'))
        Text('删除')
          .fontSize(10)
          .fontColor($r('app.color.danger'))
      }
      .width(52)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.danger_bg'))
      .borderRadius(26)
      .stateStyles({
        pressed: {
          .opacity(0.65)
        },
        normal: {
          .opacity(1)
        }
      })
      .onClick(() => {
        this.onDeleteSession(s);
      })
    }
    .height('100%')
    .margin({ right: 12 })
  }

  @Builder
  private NewSessionBuilder() {
    Scroll() {
      Column({ space: 12 }) {
      Text('新建会话')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      // 说明卡片
      Row({ space: 10 }) {
        Image($r('app.media.icon_server'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
        Column({ space: 3 }) {
          Text('在电脑上开一个新任务')
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
          Text('opencode 会在指定的工作目录里创建会话，手机端可随时查看与接管。')
            .fontSize(11)
            .lineHeight(16)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.primary_bg'))
      .borderRadius(14)

      Text('工程路径（电脑上的工作目录）')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: '例如 E:\\Code\\HuaWei\\opencode', text: this.newPath })
        .height(46)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.newPath = v;
        })

      if (this.recentPaths.length > 0) {
        Text('最近使用')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.recentPaths, (p: string) => {
              Row({ space: 8 }) {
                Text(p)
                  .fontSize(12)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.MARQUEE })
                  .layoutWeight(1)

                Text('使用')
                  .fontSize(12)
                  .fontColor($r('app.color.primary'))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.input_bg'))
              .borderRadius(10)
              .stateStyles({
                pressed: {
                  .opacity(0.6)
                },
                normal: {
                  .opacity(1)
                }
              })
              .onClick(() => {
                this.newPath = p;
              })
            }, (p: string) => p)
          }
          .width('100%')
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        // 注意：父容器是自适应高度，这里不能用 layoutWeight(1)，
        // 否则 Scroll 会被压成 0 高、列表项全部不可见。只限制最大高度即可。
        .constraintSize({ maxHeight: 110 })
      }

      Text('模型')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 10 }) {
        Text(this.currentModelLabel())
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 4 }) {
          Text('选择模型')
            .fontSize(13)
            .fontColor($r('app.color.primary'))
          Image($r('app.media.icon_chevron_down'))
            .width(14)
            .height(14)
            .fillColor($r('app.color.primary'))
        }
        .height(36)
        .padding({ left: 12, right: 10 })
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(18)
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
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.input_bg'))
      .borderRadius(12)

      Button(this.creating ? '创建中…' : '创建会话')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.primary'))
        .enabled(!this.creating)
        .onClick(() => {
          this.onCreateSession();
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 48, bottom: 18 })
    .borderRadius(20)
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  private SheetContent() {
    if (this.sheetKind === 'rename') {
      this.RenameBuilder()
    } else if (this.sheetKind === 'new') {
      this.NewSessionBuilder()
    } else if (this.sheetKind === 'model') {
      this.ModelSheetContent()
    } else if (this.sheetKind === 'edit') {
      this.EditServerBuilder()
    } else if (this.sheetKind === 'connect') {
      this.ConnectSheetContent()
    } else if (this.sheetKind === 'settings') {
      this.SettingsSheetContent()
    }
  }

  /** 设置（底部 sheet 形态，不整页跳转） */
  @Builder
  private SettingsSheetContent() {
    SettingsPanel({
      onCleared: () => {
        this.sheetVisible = false;
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
      }
    })
    .width('100%')
  }

  /** 重命名会话：标题输入 + 保存 */
  @Builder
  private RenameBuilder() {
    Column({ space: 12 }) {
      Text('重命名会话')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextInput({ placeholder: '输入新的标题', text: this.renameTitle })
        .height(46)
        .fontSize(15)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.renameTitle = v;
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
        Button('保存')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            this.onSaveRename();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 48, bottom: 18 })
    .borderRadius(20)
  }

  @Builder
  private ModelSheetContent() {
    ModelSheet({
      models: this.models,
      selectedId: this.selectedModelId,
      onPick: (m: ModelInfo) => {
        this.selectedModelId = m.id;
        this.sheetVisible = false;
      }
    })
  }

  @Builder
  private EditServerBuilder() {
    Column({ space: 12 }) {
      Text(this.editIsNew ? '添加服务器' : '编辑服务器')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextInput({ placeholder: '名称（如 公司台式机）', text: this.editName })
        .height(46)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.editName = v;
        })
      TextInput({ placeholder: '主机地址', text: this.editHost })
        .height(46)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.editHost = v;
        })
      Row({ space: 10 }) {
        TextInput({ placeholder: '端口', text: this.editPort })
          .type(InputType.Number)
          .height(46)
          .layoutWeight(1)
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(12)
          .onChange((v: string) => {
            this.editPort = v;
          })
        Column({ space: 2 }) {
          Text('HTTPS')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Toggle({ type: ToggleType.Switch, isOn: this.editHttps })
            .onChange((on: boolean) => {
              this.editHttps = on;
            })
        }
        .width(64)
      }
      .width('100%')
      TextInput({ placeholder: '用户名', text: this.editUser })
        .height(46)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.editUser = v;
        })
      TextInput({ placeholder: '密码', text: this.editPass })
        .type(InputType.Password)
        .height(46)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .onChange((v: string) => {
          this.editPass = v;
        })

      Row({ space: 10 }) {
        if (!this.editIsNew) {
          Button('删除')
            .layoutWeight(1)
            .height(46)
            .fontSize(15)
            .backgroundColor($r('app.color.danger_bg'))
            .fontColor($r('app.color.danger'))
            .onClick(() => {
              this.onAskDeleteServer();
            })
        }
        Button('取消')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .backgroundColor($r('app.color.input_bg'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.sheetVisible = false;
          })
        Button('保存')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            this.onSaveServer();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 48, bottom: 18 })
    .borderRadius(20)
  }

  @Builder
  private ConnectSheetContent() {
    ConnectPanel({
      onConnected: () => {
        this.sheetVisible = false;
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/SessionListPage' });
      }
    })
  }
}
