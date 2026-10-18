import { print } from "@kit.BasicServicesKit";

@Entry
@ComponentV2
export struct Index {
  @Local isLoading: boolean = true;

  aboutToAppear() {
    // 模拟初始化
    setTimeout(() => {
      this.isLoading = false;
      // 检查是否有配置，如果没有则导航到设置页面
      // 这里简化，假设没有配置，直接导航到设置
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/SetupScreen'
      }).catch((err:Error) => {
        err.message;
        // TODO: Implement error handling.
      });
    }, 2000);
  }

  build() {
    Stack() {
      Column() {
        Image($r('app.media.foreground'))
          .width(100)
          .height(100)
          .objectFit(ImageFit.Contain);

        Text('成长日记')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20 });

        if (this.isLoading) {
          Text('Loading...')
            .fontSize(16);
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center);
    }
    .height('100%')
    .width('100%')
    .backgroundColor(Color.White);
  }
}