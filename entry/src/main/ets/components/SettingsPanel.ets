import { Constants } from '../common/Constants';
import { ServerProfile } from '../model/Server';
import { ConfigStore } from '../store/ConfigStore';
import { ServerStore } from '../store/ServerStore';
import { OpenCodeClient, ApiResult } from '../api/OpenCodeClient';
import { Parsers } from '../api/Parsers';

const POLL_OPTIONS: number[] = [1000, 2000, 5000, 10000];

/** 通用分区卡片（内容用尾随 UI 块传入） */
@Component
export struct SectionCard {
  @Prop title: string = '';
  @BuilderParam content: () => void;

  build() {
    Column({ space: 10 }) {
      Text(this.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      this.content()
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * 设置内容（连接诊断 / 刷新频率 / 关于 / 清空配置）。
 *
 * 既可作为整页使用，也可放进底部 sheet —— 因此这里**不带顶栏**，
 * 由外层决定标题与返回方式。
 */
@Component
export struct SettingsPanel {
  @State serverName: string = '';
  @State serverHost: string = '';
  @State diagText: string = '';
  @State diagOk: boolean = false;
  @State diagBusy: boolean = false;
  @State pollMs: number = Constants.POLL_INTERVAL_MS;
  @State versionText: string = '';
  /** 清空配置后的回调（整页用时跳回首页；sheet 用时关闭 sheet） */
  onCleared: () => void = () => {};

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    const cur: ServerProfile | null = ServerStore.current();
    this.serverName = cur !== null ? cur.name : '未配置';
    this.serverHost = cur !== null ? (cur.host + ':' + cur.port) : '';
    const stored: number = AppStorage.get<number>('pollIntervalMs') as number;
    this.pollMs = stored > 0 ? stored : Constants.POLL_INTERVAL_MS;
  }

  private onTest(): void {
    this.diagBusy = true;
    this.diagOk = false;
    this.diagText = '测试中…';
    const client: OpenCodeClient = new OpenCodeClient(ConfigStore.load());
    client.checkHealth().then((res: ApiResult) => {
      this.diagBusy = false;
      if (res.ok) {
        const ver: string = Parsers.parseVersion(res.body);
        this.diagOk = true;
        this.diagText = '连接正常' + (ver.length > 0 ? ' · opencode v' + ver : '');
        this.versionText = ver.length > 0 ? 'v' + ver : '';
      } else {
        this.diagText = '连接失败：' + res.error;
      }
    });
  }

  private onPickPoll(ms: number): void {
    this.pollMs = ms;
    AppStorage.setOrCreate<number>('pollIntervalMs', ms);
    this.getUIContext().getPromptAction().showToast({ message: '已设为 ' + (ms / 1000) + ' 秒' });
  }

  private onClearAll(): void {
    this.getUIContext().showAlertDialog({
      title: '清空本地配置？',
      message: '将删除所有服务器记录与连接配置，需要重新扫码或手动添加。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.danger'),
        action: () => {
          ServerStore.clearAll();
          this.onCleared();
        }
      }
    });
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        SectionCard({ title: '当前服务器' }) {
          Row({ space: 14 }) {
            Column({ space: 4 }) {
              Text(this.serverName)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.MARQUEE })
                .marqueeOptions({ start: true, step: 5, loop: -1, fromStart: true, delay: 800, fadeout: true })
              Text(this.serverHost)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.MARQUEE })
                .marqueeOptions({ start: true, step: 4, loop: -1, fromStart: true, delay: 1200, fadeout: true })
            }
            .layoutWeight(1)
            .flexShrink(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ right: 8 })

            Button(this.diagBusy ? '…' : '测试')
              .height(32)
              .fontSize(13)
              .backgroundColor($r('app.color.primary'))
              .borderRadius(12)
              .enabled(!this.diagBusy)
              .onClick(() => {
                this.onTest();
              })
          }
          .width('100%')
        }

        if (this.diagText.length > 0) {
          Text(this.diagText)
            .fontSize(12)
            .fontColor(this.diagOk ? $r('app.color.success') : $r('app.color.danger'))
            .width('100%')
            .padding({ left: 14, right: 14, top: 6 })
        }

        SectionCard({ title: '刷新频率' }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(POLL_OPTIONS, (ms: number) => {
              Text(ms < 1000 ? ms + 'ms' : (ms / 1000) + ' 秒')
                .fontSize(13)
                .fontColor(this.pollMs === ms ? Color.White : $r('app.color.text_primary'))
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .backgroundColor(this.pollMs === ms ? $r('app.color.primary') : $r('app.color.input_bg'))
                .borderRadius(16)
                .margin({ right: 8, bottom: 8 })
                .stateStyles({
                  pressed: {
                    .opacity(0.6)
                  },
                  normal: {
                    .opacity(1)
                  }
                })
                .onClick(() => {
                  this.onPickPoll(ms);
                })
            }, (ms: number) => String(ms))
          }
          .width('100%')
        }

        SectionCard({ title: '关于' }) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('客户端')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              Blank()
              Text('OpenCode Remote')
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')

            if (this.versionText.length > 0) {
              Row({ space: 8 }) {
                Text('服务端版本')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Blank()
                Text(this.versionText)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
              }
              .width('100%')
            }

            Row({ space: 8 }) {
              Text('默认端口')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              Blank()
              Text(String(Constants.DEFAULT_PORT))
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
          }
          .width('100%')
        }

        Button('清空本地配置')
          .width('100%')
          .height(46)
          .fontSize(15)
          .backgroundColor($r('app.color.danger_bg'))
          .fontColor($r('app.color.danger'))
          .borderRadius(14)
          .onClick(() => {
            this.onClearAll();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 24 })
    }
    .width('100%')
    // Scroll 默认会把内容垂直居中，内容少时上方会出现大片空白
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
  }
}
