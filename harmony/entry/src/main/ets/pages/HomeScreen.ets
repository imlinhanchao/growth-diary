@Entry
@ComponentV2
export struct HomeScreen {
  @Local entries: string[] = ['日记条目1', '日记条目2', '日记条目3'];

  build() {
    Column() {
      Text('成长日记')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 });

      List() {
        ForEach(this.entries, (entry: string) => {
          ListItem() {
            Text(entry)
              .fontSize(16);
          }
        });
      }
      .height('80%')
      .width('100%');

      Button('添加新日记')
        .onClick(() => {
          // TODO: 导航到编辑页面
        })
        .width('100%')
        .margin({ top: 20 });
    }
    .padding(20)
    .height('100%')
    .width('100%')
    .backgroundColor(Color.White);
  }
}
