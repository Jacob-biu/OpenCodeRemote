/**
 * 单选圈：选中 = 实心主色圆点，未选中 = 空心灰圈。
 * 供模型选择、专家选择等列表复用。
 */
@Component
export struct RadioDot {
  @Prop selected: boolean = false;

  build() {
    Row() {
      if (this.selected) {
        Row()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor($r('app.color.primary'))
      }
    }
    .width(18)
    .height(18)
    .borderRadius(9)
    .border({ width: this.selected ? 0 : 1.5, color: $r('app.color.text_secondary') })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }
}
