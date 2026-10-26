import { Constants } from '../common/Constants';
import { ServerConfig } from '../model/Config';
import { ConfigStore } from '../store/ConfigStore';
import { OpenCodeClient, ApiResult, PairResult } from '../api/OpenCodeClient';
import { Parsers } from '../api/Parsers';
import { PairingParser, PairingLink } from '../common/Pairing';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * 连接方式面板：服务器连接 / 链接配对（可滑动切换），右上角可放扫码入口。
 * 首页与「添加服务器」弹窗共用。
 */
@Component
export struct ConnectPanel {
  @State host: string = Constants.DEFAULT_HOST;
  @State port: string = String(Constants.DEFAULT_PORT);
  @State username: string = Constants.DEFAULT_USERNAME;
  @State password: string = '';
  @State useHttps: boolean = false;
  @State statusText: string = '';
  @State statusOk: boolean = false;
  @State busy: boolean = false;
  @State pairText: string = '';
  @State currentTab: number = 0;
  @State showScan: boolean = false;
  @State helpOpen: boolean = false;
  // 首页已有品牌标题行时置 false，避免出现两行标题 / 两个扫码入口
  @Prop showHeader: boolean = true;
  onScanned: (text: string) => void = () => {};
  onConnected: () => void = () => {};
  private pairAttempts: number = 0;

  aboutToAppear(): void {
    const cfg: ServerConfig = ConfigStore.load();
    this.host = cfg.host;
    this.port = String(cfg.port);
    this.username = cfg.username;
    this.password = cfg.password;
    this.useHttps = cfg.useHttps;
  }

  private buildConfig(): ServerConfig {
    let port: number = Number(this.port);
    if (isNaN(port) || port <= 0 || port > 65535) {
      port = Constants.DEFAULT_PORT;
    }
    const cfg: ServerConfig = new ServerConfig();
    cfg.host = this.host.trim();
    cfg.port = port;
    cfg.username = this.username.trim();
    cfg.password = this.password;
    cfg.useHttps = this.useHttps;
    return cfg;
  }

  /** 根据错误给出针对性排障建议 */
  private failText(err: string): string {
    let base: string = '连接失败：' + err;
    if (err.indexOf('超时') >= 0 || err.indexOf('timeout') >= 0) {
      return base + '\n· 电脑端需要 opencode serve --hostname 0.0.0.0 --port ' + Constants.DEFAULT_PORT;
    }
    if (err.indexOf('401') >= 0 || err.indexOf('403') >= 0) {
      return base + '\n· 账号或密码不对，确认 service.json 里的 password';
    }
    if (err.indexOf('证书') >= 0 || err.indexOf('SSL') >= 0 || err.indexOf('TLS') >= 0) {
      return base + '\n· 隧道用 HTTPS 时请打开右上角 HTTPS 开关';
    }
    if (err.indexOf('解析') >= 0 || err.indexOf('host') >= 0) {
      return base + '\n· 检查主机地址与端口是否正确';
    }
    return base + '\n· 确认电脑端 opencode 已启动且端口可访问';
  }

  private onTest(): void {
    if (this.host.trim().length === 0) {
      this.showToast('请填写主机地址');
      return;
    }
    this.busy = true;
    this.statusOk = false;
    this.statusText = '正在连接…';
    const client: OpenCodeClient = new OpenCodeClient(this.buildConfig());
    client.checkHealth().then((res: ApiResult) => {
      this.busy = false;
      if (res.ok) {
        this.statusOk = true;
        this.statusText = this.successText(res);
      } else {
        this.statusText = this.failText(res.error);
      }
    });
  }

  private onSaveAndEnter(): void {
    if (this.host.trim().length === 0) {
      this.showToast('请填写主机地址');
      return;
    }
    const cfg: ServerConfig = this.buildConfig();
    ConfigStore.save(cfg);
    this.busy = true;
    this.statusOk = false;
    this.statusText = '正在连接…';
    const client: OpenCodeClient = new OpenCodeClient(cfg);
    client.checkHealth().then((res: ApiResult) => {
      this.busy = false;
      if (res.ok) {
        this.statusOk = true;
        this.statusText = this.successText(res) + '，正在进入…';
        this.onConnected();
      } else {
        this.statusText = this.failText(res.error);
        this.showToast('连接失败');
      }
    });
  }

  private onPastePairing(): void {
    pasteboard.getSystemPasteboard().getPasteData().then((data: pasteboard.PasteData) => {
      const text: string = data.getPrimaryText();
      if (text.length === 0) {
        this.showToast('剪贴板为空，请先复制配对链接');
        return;
      }
      this.pairText = text.trim();
      this.onPairConnect();
    }).catch(() => {
      this.showToast('读取剪贴板失败，请手动粘贴');
    });
  }

  private onPairConnect(): void {
    const link: PairingLink = PairingParser.parse(this.pairText, this.host);
    if (!link.ok) {
      this.statusText = '无法识别配对内容，请粘贴 desktop 的 Copy link 结果';
      this.showToast(this.statusText);
      return;
    }
    this.host = link.host;
    this.port = String(link.port);
    this.useHttps = link.useHttps;
    this.username = Constants.DEFAULT_USERNAME;
    this.pairAttempts = 0;
    this.doPairRequest(link);
  }

  private doPairRequest(link: PairingLink): void {
    this.busy = true;
    this.statusOk = false;
    this.statusText = '配对中… ' + link.host;
    OpenCodeClient.pair(link.host, link.port, link.useHttps, link.code).then((res: PairResult) => {
      if (res.error.length > 0) {
        this.busy = false;
        this.pairAttempts += 1;
        if (this.pairAttempts < 3) {
          this.statusText = '配对重试中…（' + this.pairAttempts + '/3）';
          setTimeout(() => {
            this.doPairRequest(link);
          }, 2000);
          return;
        }
        this.statusText = '配对失败：' + res.error;
        this.showToast('配对失败，可点「配对并连接」重试');
        return;
      }
      this.password = res.token;
      this.pairText = '';
      const cfg: ServerConfig = this.buildConfig();
      ConfigStore.save(cfg);
      const client: OpenCodeClient = new OpenCodeClient(cfg);
      client.checkHealth().then((info: ApiResult) => {
        this.busy = false;
        if (info.ok) {
          this.statusOk = true;
          this.statusText = this.successText(info) + '，正在进入…';
          this.showToast('配对成功');
          this.onConnected();
        } else {
          this.statusText = '配对成功但连接失败：' + info.error;
          this.showToast(this.statusText);
        }
      });
    });
  }

  private successText(res: ApiResult): string {
    const ver: string = Parsers.parseVersion(res.body);
    if (ver.length > 0) {
      return '连接成功 · opencode v' + ver;
    }
    return '连接成功（HTTP ' + res.httpCode + '）';
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  build() {
    Column({ space: 8 }) {
      if (this.showHeader) {
        // 标题行只放标题：右上角是 bindSheet 的官方关闭按钮，
        // 标题行右侧再放图标会和 X 抢位置，扫码入口改放在「链接配对」里
        Row() {
          Text('连接到电脑端')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()
        }
        .width('100%')
      }

      // 分段控件（不用 Tabs：Tabs 默认高度为 '100%'，会把卡片撑到整屏，
      // 导致标签与表单之间出现大片空白；自绘胶囊分段高度完全跟随内容）
      Row({ space: 6 }) {
        this.SegChip('服务器连接', 0)
        this.SegChip('链接配对', 1)
      }
      .width('100%')
      .padding(4)
      .backgroundColor($r('app.color.input_bg'))
      .borderRadius(18)

      if (this.currentTab === 0) {
        this.ServerPane()
      } else {
        this.PairPane()
      }

      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor(this.statusOk ? $r('app.color.success') : $r('app.color.danger'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      Row({ space: 6 }) {
        Text(this.helpOpen ? '▾' : '▸')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text('连接帮助')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ top: 4, bottom: 2 })
      .borderRadius(8)
      .stateStyles({
        pressed: {
          .opacity(0.6)
        },
        normal: {
          .opacity(1)
        }
      })
      .onClick(() => {
        this.helpOpen = !this.helpOpen;
      })

      if (this.helpOpen) {
        Column({ space: 6 }) {
          Text('1. 电脑端启动：opencode serve --hostname 0.0.0.0 --port ' + Constants.DEFAULT_PORT)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text('2. 同一局域网填电脑内网 IP；外网用 Tailscale / frp 隧道地址')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text('3. 隧道是 https 时打开 HTTPS 开关')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text('4. 用户名默认 opencode，密码取电脑端 service.json 中的 password（或用配对二维码）')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 分段控件的一项：选中为主色胶囊，未选中为透明 */
  @Builder
  private SegChip(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.currentTab === index ? $r('app.color.primary') : $r('app.color.text_secondary'))
      .layoutWeight(1)
      .height(32)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.currentTab === index ? $r('app.color.card_bg') : Color.Transparent)
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
        this.currentTab = index;
      })
  }

  @Builder
  private ServerPane() {
    Column({ space: 12 }) {
      TextInput({ placeholder: '主机地址（IP / 域名）', text: this.host })
        .type(InputType.Normal)
        .height(46)
        .width('100%')
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .onChange((v: string) => {
          this.host = v;
        })

      Row({ space: 10 }) {
        TextInput({ placeholder: '端口', text: this.port })
          .type(InputType.Number)
          .height(46)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .onChange((v: string) => {
            this.port = v;
          })
        Column({ space: 2 }) {
          Text('HTTPS')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          Toggle({ type: ToggleType.Switch, isOn: this.useHttps })
            .onChange((on: boolean) => {
              this.useHttps = on;
            })
        }
        .width(64)
      }
      .width('100%')

      TextInput({ placeholder: '用户名（默认 opencode）', text: this.username })
        .type(InputType.Normal)
        .height(46)
        .width('100%')
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .onChange((v: string) => {
          this.username = v;
        })

      TextInput({ placeholder: '密码（service.json 里的 password）', text: this.password })
        .type(InputType.Password)
        .height(46)
        .width('100%')
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .onChange((v: string) => {
          this.password = v;
        })

      Row({ space: 10 }) {
        Button('测试连接')
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .backgroundColor($r('app.color.input_bg'))
          .fontColor($r('app.color.primary'))
          .enabled(!this.busy)
          .onClick(() => {
            this.onTest();
          })
        Button('保存并进入')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.primary'))
          .enabled(!this.busy)
          .onClick(() => {
            this.onSaveAndEnter();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PairPane() {
    Column({ space: 12 }) {
      Text('粘贴桌面端 Pairing → Copy link 的链接')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ placeholder: 'https://<隧道域名>/auth/connect/<配对码>', text: this.pairText })
        .type(InputType.Normal)
        .height(46)
        .width('100%')
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .onChange((v: string) => {
          this.pairText = v;
        })

      // 次要动作一行、主动作独占一行，避免三个按钮挤在一行导致文字被截断
      Row({ space: 10 }) {
        Button('扫码配对')
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .backgroundColor($r('app.color.input_bg'))
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/QrScanPage' });
          })
        Button('从剪贴板读取')
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .backgroundColor($r('app.color.input_bg'))
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.onPastePairing();
          })
      }
      .width('100%')

      Button('配对并连接')
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(14)
        .enabled(!this.busy)
        .onClick(() => {
          this.onPairConnect();
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
