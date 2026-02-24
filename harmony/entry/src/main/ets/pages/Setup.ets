import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppConfig, generateUUID } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';

/**
 * 初始化设置页面
 * 首次使用时引导用户配置宝宝信息和 WebDAV 连接
 */
@Entry
@Component
struct Setup {
  @State babyName: string = '';
  @State birthDateStr: string = '';
  @State webdavUrl: string = '';
  @State username: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State showDatePicker: boolean = false;
  @State selectedDate: Date = new Date();

  private prefsService = PreferencesService.getInstance();

  build() {
    Stack() {
      // 背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#FFF5F7')

      // 内容
      Scroll() {
        Column({ space: 24 }) {
          // 标题区
          Column({ space: 8 }) {
            Text('🌸')
              .fontSize(64)
            Text('成长日记')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#E91E8C')
            Text('记录每一个珍贵瞬间')
              .fontSize(16)
              .fontColor('#888888')
          }
          .width('100%')
          .padding({ top: 60, bottom: 16 })
          .alignItems(HorizontalAlign.Center)

          // 宝宝信息卡片
          Column({ space: 16 }) {
            Text('宝宝信息')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .width('100%')

            // 宝宝昵称
            Column({ space: 6 }) {
              Text('宝宝昵称 *')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              TextInput({ placeholder: '输入宝宝的昵称', text: this.babyName })
                .onChange((val) => { this.babyName = val; })
                .width('100%')
                .height(48)
                .borderRadius(12)
                .backgroundColor('#FFFFFF')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .padding({ left: 12, right: 12 })
            }

            // 宝宝生日
            Column({ space: 6 }) {
              Text('宝宝生日')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              Row() {
                Text(this.birthDateStr.length > 0 ? this.birthDateStr : '点击选择生日')
                  .fontSize(16)
                  .fontColor(this.birthDateStr.length > 0 ? '#333333' : '#AAAAAA')
                  .layoutWeight(1)
                Image($r('sys.symbol.calendar'))
                  .width(20)
                  .height(20)
                  .fillColor('#E91E8C')
              }
              .width('100%')
              .height(48)
              .borderRadius(12)
              .backgroundColor('#FFFFFF')
              .borderWidth(1)
              .borderColor('#F0C0D0')
              .padding({ left: 12, right: 12 })
              .onClick(() => { this.showDatePicker = true; })
            }
          }
          .width('100%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

          // WebDAV 配置卡片
          Column({ space: 16 }) {
            Text('WebDAV 配置')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .width('100%')

            Text('用于在多设备间同步数据，支持 Nextcloud 等 WebDAV 服务')
              .fontSize(13)
              .fontColor('#888888')
              .width('100%')

            // 服务器地址
            Column({ space: 6 }) {
              Text('服务器地址 *')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              TextInput({ placeholder: 'https://your-server/dav', text: this.webdavUrl })
                .onChange((val) => { this.webdavUrl = val; })
                .width('100%')
                .height(48)
                .borderRadius(12)
                .backgroundColor('#FFFFFF')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .padding({ left: 12, right: 12 })
                .inputFilter('[\\s\\S]*')
            }

            // 用户名
            Column({ space: 6 }) {
              Text('用户名 *')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              TextInput({ placeholder: '输入用户名', text: this.username })
                .onChange((val) => { this.username = val; })
                .width('100%')
                .height(48)
                .borderRadius(12)
                .backgroundColor('#FFFFFF')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .padding({ left: 12, right: 12 })
            }

            // 密码
            Column({ space: 6 }) {
              Text('密码 *')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              TextInput({ placeholder: '输入密码', text: this.password })
                .onChange((val) => { this.password = val; })
                .type(InputType.Password)
                .width('100%')
                .height(48)
                .borderRadius(12)
                .backgroundColor('#FFFFFF')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .padding({ left: 12, right: 12 })
            }
          }
          .width('100%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

          // 完成按钮
          Button('完成设置', { type: ButtonType.Normal })
            .width('100%')
            .height(52)
            .borderRadius(26)
            .backgroundColor('#E91E8C')
            .fontColor('#FFFFFF')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .enabled(!this.isLoading)
            .opacity(this.isLoading ? 0.7 : 1.0)
            .onClick(() => { this.onSave(); })

          Blank().height(40)
        }
        .padding({ left: 20, right: 20 })
      }
      .width('100%')
      .height('100%')

      // 日期选择器弹窗
      if (this.showDatePicker) {
        Column() {
          Column({ space: 0 }) {
            // 标题栏
            Row() {
              Button('取消')
                .backgroundColor(Color.Transparent)
                .fontColor('#888888')
                .onClick(() => { this.showDatePicker = false; })
              Blank()
              Text('选择生日')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
              Blank()
              Button('确定')
                .backgroundColor(Color.Transparent)
                .fontColor('#E91E8C')
                .onClick(() => {
                  this.birthDateStr = this.formatDate(this.selectedDate);
                  this.showDatePicker = false;
                })
            }
            .width('100%')
            .padding({ left: 8, right: 8 })

            DatePicker({
              start: new Date('2000-01-01'),
              end: new Date(),
              selected: this.selectedDate,
            })
              .onDateChange((val: DatePickerResult) => {
                this.selectedDate = new Date(
                  val.year ?? this.selectedDate.getFullYear(),
                  (val.month ?? this.selectedDate.getMonth() + 1) - 1,
                  val.day ?? this.selectedDate.getDate()
                );
              })
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 24, topRight: 24 })
          .padding({ top: 8, bottom: 20 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('#80000000')
        .onClick(() => { this.showDatePicker = false; })
      }
    }
    .width('100%')
    .height('100%')
  }

  private formatDate(date: Date): string {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  private async onSave(): Promise<void> {
    if (this.babyName.trim().length === 0) {
      promptAction.showToast({ message: '请输入宝宝昵称' });
      return;
    }
    if (this.webdavUrl.trim().length === 0) {
      promptAction.showToast({ message: '请输入 WebDAV 服务器地址' });
      return;
    }
    if (this.username.trim().length === 0) {
      promptAction.showToast({ message: '请输入用户名' });
      return;
    }
    if (this.password.trim().length === 0) {
      promptAction.showToast({ message: '请输入密码' });
      return;
    }

    this.isLoading = true;
    try {
      const config = new AppConfig(
        generateUUID(),
        this.webdavUrl.trim(),
        this.username.trim(),
        this.password.trim(),
        this.babyName.trim(),
        this.birthDateStr.length > 0 ? new Date(this.birthDateStr).toISOString() : '',
        '',
        10,
        [this.webdavUrl.trim()],
      );

      // 初始化 WebDAV，确保目录存在
      const webdav = new WebDAVService();
      await webdav.initialize(config);

      // 保存配置到本地
      await this.prefsService.saveConfig(config);
      await this.prefsService.setCurrentConfigId(config.id);

      // 同步配置到 WebDAV
      try {
        await webdav.saveConfig(config);
      } catch (_e) {
        // 网络错误不阻断本地设置
      }

      promptAction.showToast({ message: '设置已保存' });
      router.replaceUrl({ url: 'pages/Index' });
    } catch (e) {
      promptAction.showToast({ message: `保存失败: ${e}` });
    } finally {
      this.isLoading = false;
    }
  }
}
