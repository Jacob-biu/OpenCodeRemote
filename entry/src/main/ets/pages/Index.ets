import { Constants } from '../common/Constants';
import { ServerConfig } from '../model/Config';
import { ConfigStore } from '../store/ConfigStore';
import { ServerStore } from '../store/ServerStore';
import { OpenCodeClient, ApiResult } from '../api/OpenCodeClient';
import { ConnectPanel } from '../components/ConnectPanel';

@Entry
@Component
struct Index {
  private autoTried: boolean = false;

  aboutToAppear(): void {
    this.tryAutoConnect();
  }

  /** 记忆：自动连上上次使用的服务器并直接进入会话列表 */
  private tryAutoConnect(): void {
    if (this.autoTried) {
      return;
    }
    this.autoTried = true;
    const cur = ServerStore.current();
    if (cur === null || cur.host.length === 0 || cur.password.length === 0) {
      return;
    }
    const cfg: ServerConfig = ConfigStore.load();
    const client: OpenCodeClient = new OpenCodeClient(cfg);
    client.checkHealth().then((res: ApiResult) => {
      if (res.ok) {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/SessionListPage' });
      }
    });
  }

  private openScanner(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/QrScanPage' });
  }

  build() {
    // 外层用 Column 居中而不是 Scroll：
    // Scroll 的子节点会被测量成"可撑满视口"，导致卡片被拉到整屏高，
    // 标签与表单之间出现大片空白。
    Column() {
      Column({ space: 14 }) {
        Row({ space: 12 }) {
          Column({ space: 3 }) {
            Text('OpenCode Remote')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('远程操控电脑端 opencode 智能体')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Image($r('app.media.scan_icon'))
            .width(44)
            .height(44)
            .borderRadius(14)
            .backgroundColor($r('app.color.card_bg'))
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
              this.openScanner();
            })
        }
        .width('100%')

        // 连接面板（自身为圆角卡片：标签页 + 表单整体居中）
        ConnectPanel({
          // 这里首页已有品牌标题行，面板内不再重复标题与扫码入口
          showHeader: false,
          onConnected: () => {
            this.getUIContext().getRouter().replaceUrl({ url: 'pages/SessionListPage' });
          }
        })
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Center)
      .constraintSize({ maxWidth: 460 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
  }
}
