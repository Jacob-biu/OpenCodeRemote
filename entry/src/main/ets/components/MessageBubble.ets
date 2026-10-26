import { Utils } from '../common/Utils';
import { ContentItem, SessionMessageItem } from '../model/Message';
import { MarkdownText } from './MarkdownText';

/**
 * 单条消息（参考图2 的信息层级）：
 * - 助手正文：直接排在页面上，无气泡框
 * - 工具调用 / 思考过程：折叠成一行可点击条目，展开后是圆角浅灰卡片
 * - 用户消息：右侧浅灰圆角气泡
 */
@Component
export struct MessageBubble {
  @Prop message: SessionMessageItem = new SessionMessageItem();
  @State reasoningExpanded: boolean = false;
  @State toolExpanded: boolean = false;

  /** 工具输入输出按代码块展示 */
  private wrapCode(text: string): string {
    if (text.trim().length === 0) {
      return '';
    }
    return '```\n' + text + '\n```';
  }

  private statusLabel(status: string): string {
    if (status === 'pending') {
      return '等待确认';
    }
    if (status === 'streaming') {
      return '输出中';
    }
    if (status === 'running') {
      return '执行中';
    }
    if (status === 'completed') {
      return '已完成';
    }
    if (status === 'error') {
      return '出错';
    }
    return status;
  }

  private statusColor(status: string): ResourceColor {
    if (status === 'completed') {
      return $r('app.color.success');
    }
    if (status === 'error') {
      return $r('app.color.danger');
    }
    if (status === 'pending') {
      return $r('app.color.warning');
    }
    return $r('app.color.text_secondary');
  }

  build() {
    if (this.message.kind === 'user') {
      Row() {
        Blank()
        Column({ space: 6 }) {
          Text(this.message.text)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(23)
            .textAlign(TextAlign.End)
          if (this.message.timeCreated > 0) {
            Text(Utils.formatTime(this.message.timeCreated))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.bubble_user_bg'))
        .borderRadius(16)
        .constraintSize({ maxWidth: '80%' })
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
    } else {
      Column({ space: 14 }) {
        Row({ space: 6 }) {
          // 助手侧主色竖条，与右侧用户气泡形成区分
          Row()
            .width(3)
            .height(12)
            .borderRadius(2)
            .backgroundColor($r('app.color.primary'))
          Text(this.message.agent.length > 0 ? this.message.agent : 'assistant')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          if (this.message.modelName.length > 0) {
            Text(Utils.truncate(this.message.modelName, 22))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')

        // 不加 keyGenerator（旧实现用 c.id / type_index）：
        // key 稳定的内容块不会重跑生成器，流式消息里文字变长、工具状态
        // running→completed 都刷不出来（实测停在首次渲染的旧值）。
        // 按索引 diff 时生成器重跑，新 ContentItem 的内容直接生效。
        ForEach(this.message.contents, (c: ContentItem) => {
          this.ContentBlock(c)
        })

        if (this.message.error.length > 0) {
          Text('错误：' + this.message.error)
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private ContentBlock(c: ContentItem) {
    if (c.type === 'text') {
      // 助手文本：白底圆角卡片，与「思考过程(蓝底)」「工具(白底描边)」形成层次
      Text(c.text)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(24)
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.card_bg'))
        .border({ width: 1, color: $r('app.color.divider') })
        .borderRadius(14)
    } else if (c.type === 'reasoning') {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('◈')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('思考过程')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.reasoningExpanded ? '收起' : '展开')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
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
          this.reasoningExpanded = !this.reasoningExpanded;
        })
        if (this.reasoningExpanded && c.text.length > 0) {
          MarkdownText({ content: c.text, fontSize: 13 })
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.reasoning_bg'))
      .border({ width: 1, color: $r('app.color.divider') })
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)
    } else if (c.type === 'tool') {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('</>')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text(c.name)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.statusLabel(c.status))
            .fontSize(12)
            .fontColor(this.statusColor(c.status))
          Blank()
          Text(this.toolExpanded ? '⌃' : '›')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
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
          this.toolExpanded = !this.toolExpanded;
        })
        if (this.toolExpanded) {
          Column({ space: 8 }) {
            if (c.input.length > 0) {
              MarkdownText({ content: this.wrapCode(c.input), fontSize: 13 })
            }
            if (c.output.length > 0) {
              MarkdownText({ content: this.wrapCode(c.output), fontSize: 13 })
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(14)
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.tool_bg'))
      .border({ width: 1, color: $r('app.color.divider') })
      .borderRadius(14)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
