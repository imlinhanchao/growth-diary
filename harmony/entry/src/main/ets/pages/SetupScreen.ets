@Entry
@ComponentV2
export struct SetupScreen {
  @Local childName: string = '';
  @Local childBirthDate: Date = new Date();
  @Local conceptionDate: Date = new Date();
  @Local isPregnant: boolean = false;
  @Local isLoading: boolean = false;

  build() {
    Column() {
      Text('设置宝宝信息')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 });

      TextInput({ text: this.childName })
        .onChange((value: string) => {
          this.childName = value;
        })
        .margin({ bottom: 20 });

      Button('选择出生日期')
        .onClick(() => {
          // TODO: 实现日期选择器
        })
        .margin({ bottom: 20 });

      Button('选择受孕日期')
        .onClick(() => {
          // TODO: 实现日期选择器
        })
        .margin({ bottom: 20 });

      Checkbox({ name: 'pregnant' })
        .select(true)
        .onChange((value: boolean) => {
          this.isPregnant = value;
        })
        .margin({ bottom: 20 });

      Text('怀孕中')
        .margin({ bottom: 20 });

      Button('保存配置')
        .onClick(() => {
          // TODO: 保存配置并导航到主页
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/HomeScreen'
          }).catch(() => {
            // TODO: Implement error handling.
          });
        })
        .width('100%');
    }
    .padding(20)
    .height('100%')
    .width('100%')
    .backgroundColor(Color.White);
  }
}
