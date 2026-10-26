import { pasteboard } from '@kit.BasicServicesKit';

/** 解析后的 Markdown 块 */
export interface MdBlock {
  kind: string;   // code / heading / quote / list / divider / text
  text: string;   // 内容（list 用换行分隔每一项）
  lang: string;   // 代码语言
}

/**
 * 轻量 Markdown 解析（无第三方依赖，覆盖 opencode 输出里最常见的语法）：
 * 三反引号代码块、单反引号行内代码、井号标题、大于号引用、横杠星号或数字列表、三横杠分隔线。
 */
export class MarkdownParser {
  static parse(src: string): MdBlock[] {
    const out: MdBlock[] = [];
    if (src.length === 0) {
      return out;
    }
    const lines: string[] = src.split('\n');
    let i: number = 0;
    while (i < lines.length) {
      const line: string = lines[i];
      const trim: string = line.trim();

      // 代码块
      if (trim.startsWith('```')) {
        const lang: string = trim.substring(3).trim();
        let buf: string = '';
        i += 1;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buf += lines[i] + '\n';
          i += 1;
        }
        i += 1;
        const b: MdBlock = { kind: 'code', text: buf, lang: lang };
        out.push(b);
        continue;
      }

      // 分隔线
      if (trim.length >= 3 && (MarkdownParser.allChars(trim, '-') || MarkdownParser.allChars(trim, '*'))) {
        const d: MdBlock = { kind: 'divider', text: '', lang: '' };
        out.push(d);
        i += 1;
        continue;
      }

      // 标题
      if (MarkdownParser.isHeading(trim)) {
        const level: number = MarkdownParser.headingLevel(trim);
        const h: MdBlock = { kind: 'heading', text: trim.substring(level + 1).trim(), lang: String(level) };
        out.push(h);
        i += 1;
        continue;
      }

      // 引用（合并连续）
      if (trim.startsWith('>')) {
        let buf: string = '';
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          buf += lines[i].trim().substring(1).trim() + '\n';
          i += 1;
        }
        const q: MdBlock = { kind: 'quote', text: buf, lang: '' };
        out.push(q);
        continue;
      }

      // 列表（合并连续）
      if (MarkdownParser.isListItem(line)) {
        let buf: string = '';
        while (i < lines.length && (MarkdownParser.isListItem(lines[i]) || lines[i].trim().length === 0)) {
          if (lines[i].trim().length > 0) {
            buf += lines[i].trim() + '\n';
          }
          i += 1;
        }
        const l: MdBlock = { kind: 'list', text: buf, lang: '' };
        out.push(l);
        continue;
      }

      // 普通段落（合并到空行为止）
      if (trim.length > 0) {
        let buf: string = '';
        while (i < lines.length && lines[i].trim().length > 0 && !lines[i].trim().startsWith('```')
        && !MarkdownParser.isHeading(lines[i].trim()) && !lines[i].trim().startsWith('>')
        && !MarkdownParser.isListItem(lines[i])) {
          buf += lines[i].trim() + '\n';
          i += 1;
        }
        const p: MdBlock = { kind: 'text', text: buf, lang: '' };
        out.push(p);
        continue;
      }

      i += 1;
    }
    return out;
  }

  private static allChars(s: string, ch: string): boolean {
    for (let k: number = 0; k < s.length; k++) {
      if (s[k] !== ch) {
        return false;
      }
    }
    return true;
  }

  private static isHeading(trim: string): boolean {
    if (trim.length < 2 || trim[0] !== '#') {
      return false;
    }
    return trim[1] === ' ';
  }

  private static headingLevel(trim: string): number {
    let n: number = 0;
    while (n < trim.length && trim[n] === '#') {
      n += 1;
    }
    return n;
  }

  /** 去掉列表项前缀（- / * / 1. / 2) ） */
  static stripMarker(item: string): string {
    const t: string = item.trim();
    if (t.startsWith('- ') || t.startsWith('* ')) {
      return t.substring(2).trim();
    }
    const dot: number = t.indexOf('. ');
    if (dot > 0 && dot <= 3) {
      return t.substring(dot + 2).trim();
    }
    return t;
  }

  static isListItem(line: string): boolean {
    const t: string = line.trim();
    if (t.startsWith('- ') || t.startsWith('* ')) {
      return true;
    }
    // 数字列表：1. 2)
    const dot: number = t.indexOf('. ');
    if (dot > 0 && dot <= 3) {
      let ok: boolean = true;
      for (let k: number = 0; k < dot; k++) {
        if (t[k] < '0' || t[k] > '9') {
          ok = false;
        }
      }
      return ok;
    }
    return false;
  }
}

/**
 * Markdown 渲染：代码块（等宽 + 复制）、标题、列表、引用、分隔线、行内代码。
 */
@Component
export struct MarkdownText {
  @Prop content: string = '';
  @Prop fontSize: number = 15;

  private copyText(text: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setPasteData(data).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: '已复制', duration: 1500 });
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败', duration: 1500 });
    });
  }

  /**
   * 现场解析 markdown（旧实现在 aboutToAppear 里解析一次存字段，
   * @Prop content 变化后永不更新——流式消息文字增长时 markdown 停在旧内容）。
   * 消息按引用复用后，只有真正变化的气泡会重 build，重新解析成本可忽略。
   */
  private parsedBlocks(): MdBlock[] {
    return MarkdownParser.parse(this.content);
  }

  build() {
    Column({ space: 10 }) {
      // 不加 keyGenerator（旧实现用 kind_index）：
      // key 稳定的块不会重跑生成器，块内文字变化刷不出来。
      ForEach(this.parsedBlocks(), (b: MdBlock) => {
        this.BlockView(b)
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private BlockView(b: MdBlock) {
    if (b.kind === 'code') {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          if (b.lang.length > 0) {
            Text(b.lang)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          Blank()
          Text('复制')
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
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
              this.copyText(b.text);
            })
        }
        .width('100%')

        Scroll() {
          Text(b.text.length > 0 ? b.text : ' ')
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor($r('app.color.text_primary'))
            .lineHeight(18)
            .width('100%')
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.input_bg'))
      .borderRadius(12)
    } else if (b.kind === 'heading') {
      Text(b.text)
        .fontSize(this.fontSize + (Number(b.lang) <= 2 ? 3 : 1))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    } else if (b.kind === 'quote') {
      Row({ space: 8 }) {
        Column()
          .width(3)
          .height('100%')
          .backgroundColor($r('app.color.divider'))
          .borderRadius(2)
        Text(b.text)
          .fontSize(this.fontSize - 1)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(21)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .constraintSize({ minHeight: 20 })
    } else if (b.kind === 'list') {
      Column({ space: 4 }) {
        ForEach(b.text.split('\n'), (item: string) => {
          Row({ space: 6 }) {
            Text('•')
              .fontSize(this.fontSize - 1)
              .fontColor($r('app.color.text_secondary'))
            Text(MarkdownParser.isListItem(item) ? MarkdownParser.stripMarker(item) : item)
              .fontSize(this.fontSize)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(22)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (item: string, index: number) => {
          return index + '_' + item;
        })
      }
      .width('100%')
    } else if (b.kind === 'divider') {
      Divider().color($r('app.color.divider')).width('100%')
    } else {
      this.InlineText(b.text)
    }
  }

  /** 段落：处理行内代码（`code`） */
  @Builder
  private InlineText(text: string) {
    if (text.indexOf('`') < 0) {
      Text(text)
        .fontSize(this.fontSize)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(23)
        .width('100%')
    } else {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(text.split('`'), (seg: string, index: number) => {
          if (index % 2 === 1) {
            Text(seg)
              .fontSize(this.fontSize - 1)
              .fontFamily('monospace')
              .fontColor($r('app.color.text_primary'))
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.input_bg'))
              .borderRadius(4)
          } else {
            Text(seg)
              .fontSize(this.fontSize)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(23)
          }
        }, (seg: string, index: number) => {
          return index + '_' + seg;
        })
      }
      .width('100%')
    }
  }
}
