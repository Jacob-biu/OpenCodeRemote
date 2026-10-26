import { Utils } from '../common/Utils';
import { PermissionRequest } from '../model/Message';

/**
 * 权限审批卡片：opencode 请求执行敏感操作（bash / write / edit 等）时
 * 出现在会话详情页，用户可选择 允许一次 / 总是允许 / 拒绝。
 */
@ComponentV2
export struct PermissionCard {
  @Param request: PermissionRequest = new PermissionRequest();
  @Event onReply: (requestID: string, reply: string) => void = () => {};

  private emit(reply: string): void {
    this.onReply(this.request.id, reply);
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        Text('权限请求')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.warning'))
        Blank()
        Text('待确认')
          .fontSize(11)
          .fontColor($r('app.color.warning'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.warning_bg'))
          .borderRadius(6)
      }
      .width('100%')

      Text(this.request.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (this.request.message.length > 0) {
        Text(this.request.message)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }

      if (this.request.resources.length > 0) {
        Column({ space: 3 }) {
          ForEach(this.request.resources, (r: string) => {
            Text(Utils.truncate(r, 120))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Row({ space: 8 }) {
        Button('允许一次')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            this.emit('once');
          })
        Button('总是允许')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor($r('app.color.success'))
          .onClick(() => {
            this.emit('always');
          })
        Button('拒绝')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor($r('app.color.danger'))
          .onClick(() => {
            this.emit('reject');
          })
      }
      .width('100%')
    }
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .width('100%')
    .border({ width: 1, color: $r('app.color.warning') })
    .alignItems(HorizontalAlign.Start)
  }
}
