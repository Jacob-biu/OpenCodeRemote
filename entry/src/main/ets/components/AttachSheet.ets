import { AgentInfo, CommandInfo } from '../model/Agent';

/**
 * 附件面板底部弹层内容（由宿主用官方 bindSheet 承载）。
 * - 拍照 / 图片视频 / 添加文件：手机端真实能力（相机 / 相册 / 文档选择器），
 *   选中后由宿主读成 base64，随 prompt 一起发给电脑端
 * - 专家：opencode 智能体（真实可选）
 * - 技能：opencode 斜杠命令（真实可选）
 * - 连接器 / 定时任务：桌面端能力，给出说明
 */
@Component
export struct AttachSheet {
  agents: AgentInfo[] = [];
  commands: CommandInfo[] = [];
  onPickAgent: () => void = () => {};
  onPickCommand: () => void = () => {};
  onTakePhoto: () => void = () => {};
  onPickPhoto: () => void = () => {};
  onPickFile: () => void = () => {};
  onUnsupported: (kind: string) => void = () => {};

  build() {
    Column() {
      // 顶部留白：避让 bindSheet 自带的关闭按钮（右上角）与拖拽条
      Row({ space: 10 }) {
        this.BigEntry('icon_camera', '拍照', 'photo')
        this.BigEntry('icon_image2', '图片 / 视频', 'media')
        this.BigEntry('icon_file', '添加文件', 'file')
      }      .width('100%')
      .padding({ left: 16, right: 16, top: 56, bottom: 10 })

      Divider().color($r('app.color.divider'))

      this.RowItem('icon_expert', '专家', this.agents.length > 0 ? this.agents.length + ' 个可用' : '', 'agent')
      this.RowItem('icon_skill', '技能', this.commands.length > 0 ? this.commands.length + ' 个可用' : '', 'command')
      this.RowItem('icon_connector', '连接器', '桌面端', 'connector')
      this.RowItem('icon_clock', '定时任务', '桌面端', 'schedule')

      Blank()

      Text('拍照 / 图片 / 文件都会先传到电脑端的 opencode，再随消息一起发送。\n（opencode 2.x 没有独立上传接口，附件以 data URL 内联在消息里）')
        .fontSize(11)
        .lineHeight(17)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
  }

  @Builder
  private BigEntry(icon: string, label: string, kind: string) {
    Column({ space: 8 }) {
      // 图标底衬：让图标在浅色卡片上更清晰、尺寸统一
      Row() {
        Image($r(`app.media.${icon}`))
          .width(24)
          .height(24)
          // 拍照/图片/文件是自带配色的多色 SVG，不能用 fillColor 统一着色，
          // 否则会被压成单色、丢掉层次。
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.card_bg'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .backgroundColor($r('app.color.input_bg'))
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
      if (kind === 'photo') {
        this.onTakePhoto();
      } else if (kind === 'media') {
        this.onPickPhoto();
      } else {
        this.onPickFile();
      }
    })
  }

  @Builder
  private RowItem(icon: string, label: string, hint: string, kind: string) {
    Row({ space: 12 }) {
      Image($r(`app.media.${icon}`))
        .width(20)
        .height(20)
        .fillColor($r('app.color.text_primary'))
        .margin({ left: 2 })
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (hint.length > 0) {
        Text(hint)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      Text('›')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 15, bottom: 15 })
    .stateStyles({
      pressed: {
        .opacity(0.6)
      },
      normal: {
        .opacity(1)
      }
    })
    .onClick(() => {
      if (kind === 'agent') {
        this.onPickAgent();
      } else if (kind === 'command') {
        this.onPickCommand();
      } else {
        this.onUnsupported(kind);
      }
    })
  }
}
