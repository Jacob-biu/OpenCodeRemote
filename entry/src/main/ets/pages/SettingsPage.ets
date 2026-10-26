import { SettingsPanel } from '../components/SettingsPanel';

/**
 * 设置页（整页形态）。
 *
 * 主入口已改为列表页抽屉里的底部 sheet（见 SessionListPage 的 'settings' sheet），
 * 这里保留整页形态作为兜底/深链入口，内容统一由 SettingsPanel 提供。
 */
@Entry
@Component
struct SettingsPage {
  build() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Image($r('app.media.icon_back'))
          .width(34)
          .height(34)
          .fillColor($r('app.color.text_primary'))
          .padding(5)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(17)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 10 })

      SettingsPanel({
        onCleared: () => {
          this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
        }
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
