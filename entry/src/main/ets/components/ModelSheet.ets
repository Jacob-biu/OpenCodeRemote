import { ModelInfo } from '../model/Model';
import { RadioDot } from './RadioDot';

/**
 * 「选择模型」底部弹层内容（由宿主用官方 bindSheet 承载，带上滑动画与拖拽条）。
 * - 支持按名称 / ID / 提供商搜索
 * - 单选圈为真圆点（非字符），选中行高亮
 * - 顶部「默认模型」项 = 不指定模型，让服务端使用默认
 */
@Component
export struct ModelSheet {
  models: ModelInfo[] = [];
  selectedId: string = '';
  onPick: (m: ModelInfo) => void = () => {};

  @State searchText: string = '';

  private baseCost(): number {
    let min: number = -1;
    for (const m of this.models) {
      if (m.costInput > 0 && (min < 0 || m.costInput < min)) {
        min = m.costInput;
      }
    }
    return min < 0 ? 0 : min;
  }

  private visibleModels(): ModelInfo[] {
    const kw: string = this.searchText.trim().toLowerCase();
    if (kw.length === 0) {
      return this.models;
    }
    const out: ModelInfo[] = [];
    for (const m of this.models) {
      if (m.displayName().toLowerCase().indexOf(kw) >= 0
        || m.id.toLowerCase().indexOf(kw) >= 0
        || m.providerID.toLowerCase().indexOf(kw) >= 0) {
        out.push(m);
      }
    }
    return out;
  }

  build() {
    Column({ space: 0 }) {
      // 顶部留白：避让 bindSheet 自带的关闭按钮（右上角）与拖拽条
      Text('选择模型')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 20, right: 56, top: 48, bottom: 10 })

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索模型（名称 / 提供商）', text: this.searchText })
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .backgroundColor($r('app.color.input_bg'))
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
      .padding({ left: 20, right: 20, bottom: 8 })

      if (this.models.length === 0) {
        Text('正在加载模型…')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .padding(20)
      } else {
        List({ space: 2 }) {
          // 默认模型项：清除选择
          ListItem() {
            Row({ space: 10 }) {
              RadioDot({ selected: false })
              Column({ space: 2 }) {
                Text('默认模型')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(this.selectedId.length === 0 ? FontWeight.Medium : FontWeight.Normal)
                Text('不指定模型，由服务端决定')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .backgroundColor(this.selectedId.length === 0 ? $r('app.color.primary_bg') : Color.Transparent)
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
              const none: ModelInfo = new ModelInfo();
              none.id = '';
              this.onPick(none);
            })
          }

          ForEach(this.visibleModels(), (m: ModelInfo) => {
            ListItem() {
              Row({ space: 10 }) {
                RadioDot({ selected: m.id === this.selectedId })
                Column({ space: 2 }) {
                  Text(m.displayName())
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .fontWeight(m.id === this.selectedId ? FontWeight.Medium : FontWeight.Normal)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (m.providerID.length > 0) {
                    Text(m.providerID)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .maxLines(1)
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (m.contextLabel().length > 0) {
                  Text(m.contextLabel())
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                if (m.ratioLabel(this.baseCost()).length > 0) {
                  Text(m.ratioLabel(this.baseCost()))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 8 })
                }
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 12, bottom: 12 })
              .backgroundColor(m.id === this.selectedId ? $r('app.color.primary_bg') : Color.Transparent)
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
                this.onPick(m);
              })
            }
          }, (m: ModelInfo) => m.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ bottom: 12 })
        .divider(null)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }
}
