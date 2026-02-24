import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppConfig, generateUUID } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';

/**
 * 设置页面
 * 查看和修改宝宝信息及 WebDAV 配置
 */
@Entry
@Component
struct Settings {
  @State config: AppConfig | null = null;
  @State isLoading: boolean = true;
  @State isEditing: boolean = false;
  @State isSaving: boolean = false;
  @State showDatePicker: boolean = false;

  // 编辑中的字段
  @State editBabyName: string = '';
  @State editBirthDateStr: string = '';
  @State editWebdavUrl: string = '';
  @State editUsername: string = '';
  @State editPassword: string = '';
  @State selectedDate: Date = new Date();

  private prefsService = PreferencesService.getInstance();
  private webdavService = new WebDAVService();

  aboutToAppear(): void {
    this.loadData();
  }

  build() {
    Stack() {
      Column() {
        // 顶部应用栏
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('←')
              .fontSize(20)
              .fontColor('#E91E8C')
          }
          .width(40)
          .height(40)
          .backgroundColor('#FFF0F5')
          .onClick(() => { router.back(); })

          Text('设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          if (this.isEditing) {
            Button(this.isSaving ? '...' : '保存')
              .height(36)
              .borderRadius(18)
              .backgroundColor('#E91E8C')
              .fontColor('#FFFFFF')
              .fontSize(15)
              .enabled(!this.isSaving)
              .onClick(() => { this.onSave(); })
          } else {
            Button('编辑')
              .height(36)
              .borderRadius(18)
              .backgroundColor('#FFF0F5')
              .fontColor('#E91E8C')
              .fontSize(15)
              .onClick(() => { this.startEditing(); })
          }
        }
        .width('100%')
        .height(60)
        .padding({ left: 12, right: 16 })
        .backgroundColor('#FFFFFF')
        .shadow({ radius: 4, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color('#E91E8C')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.config) {
          Scroll() {
            Column({ space: 20 }) {
              // 宝宝信息卡片
              Column({ space: 16 }) {
                Row() {
                  Text('宝宝信息')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#333333')
                  Blank()
                  Text('👶')
                    .fontSize(20)
                }
                .width('100%')

                // 宝宝昵称
                this.buildInfoRow('昵称', this.isEditing ? undefined : this.config!.babyName, '宝宝的昵称', this.editBabyName, (val) => { this.editBabyName = val; })

                // 生日
                if (this.isEditing) {
                  Column({ space: 6 }) {
                    Text('生日')
                      .fontSize(14)
                      .fontColor('#666666')
                      .width('100%')
                    Row() {
                      Text(this.editBirthDateStr.length > 0 ? this.editBirthDateStr : '未设置')
                        .fontSize(16)
                        .fontColor(this.editBirthDateStr.length > 0 ? '#333333' : '#AAAAAA')
                        .layoutWeight(1)
                      Text('📅')
                        .fontSize(18)
                    }
                    .width('100%')
                    .height(48)
                    .borderRadius(12)
                    .backgroundColor('#FFF5F7')
                    .borderWidth(1)
                    .borderColor('#F0C0D0')
                    .padding({ left: 12, right: 12 })
                    .onClick(() => { this.showDatePicker = true; })
                  }
                } else {
                  Row() {
                    Text('生日')
                      .fontSize(14)
                      .fontColor('#888888')
                      .width(80)
                    Text(this.config!.babyBirthDate ? this.formatDate(this.config!.babyBirthDate) : '未设置')
                      .fontSize(15)
                      .fontColor('#333333')
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .height(48)
                  .padding({ left: 0, right: 0 })
                }
              }
              .width('100%')
              .padding(20)
              .borderRadius(16)
              .backgroundColor('#FFFFFF')
              .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

              // WebDAV 配置卡片
              Column({ space: 16 }) {
                Row() {
                  Text('WebDAV 配置')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#333333')
                  Blank()
                  Text('☁️')
                    .fontSize(20)
                }
                .width('100%')

                this.buildInfoRow('服务器', this.isEditing ? undefined : this.config!.webdavUrl, '服务器地址', this.editWebdavUrl, (val) => { this.editWebdavUrl = val; })
                this.buildInfoRow('用户名', this.isEditing ? undefined : this.config!.username, '用户名', this.editUsername, (val) => { this.editUsername = val; })
                if (this.isEditing) {
                  Column({ space: 6 }) {
                    Text('密码')
                      .fontSize(14)
                      .fontColor('#666666')
                      .width('100%')
                    TextInput({ placeholder: '输入新密码（留空保持不变）', text: this.editPassword })
                      .onChange((val) => { this.editPassword = val; })
                      .type(InputType.Password)
                      .width('100%')
                      .height(48)
                      .borderRadius(12)
                      .backgroundColor('#FFF5F7')
                      .borderWidth(1)
                      .borderColor('#F0C0D0')
                      .padding({ left: 12, right: 12 })
                  }
                } else {
                  Row() {
                    Text('密码')
                      .fontSize(14)
                      .fontColor('#888888')
                      .width(80)
                    Text('••••••••')
                      .fontSize(15)
                      .fontColor('#333333')
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .height(48)
                }
              }
              .width('100%')
              .padding(20)
              .borderRadius(16)
              .backgroundColor('#FFFFFF')
              .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

              // 应用信息
              Column({ space: 8 }) {
                Text('关于应用')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')
                  .width('100%')
                Row() {
                  Text('版本')
                    .fontSize(14)
                    .fontColor('#888888')
                    .width(80)
                  Text('1.0.3')
                    .fontSize(15)
                    .fontColor('#333333')
                    .layoutWeight(1)
                }
                .width('100%')
                .height(40)
                Row() {
                  Text('平台')
                    .fontSize(14)
                    .fontColor('#888888')
                    .width(80)
                  Text('HarmonyOS')
                    .fontSize(15)
                    .fontColor('#333333')
                    .layoutWeight(1)
                }
                .width('100%')
                .height(40)
              }
              .width('100%')
              .padding(20)
              .borderRadius(16)
              .backgroundColor('#FFFFFF')
              .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

              Blank().height(40)
            }
            .padding(20)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#FFF5F7')
        }
      }
      .width('100%')
      .height('100%')

      // 日期选择器弹窗
      if (this.showDatePicker) {
        Column() {
          Column({ space: 0 }) {
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
                  this.editBirthDateStr = this.formatDateSimple(this.selectedDate);
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

  @Builder
  buildInfoRow(
    label: string,
    displayValue: string | undefined,
    placeholder: string,
    editValue: string,
    onChange: (val: string) => void
  ) {
    if (displayValue !== undefined) {
      Row() {
        Text(label)
          .fontSize(14)
          .fontColor('#888888')
          .width(80)
        Text(displayValue.length > 0 ? displayValue : '未设置')
          .fontSize(15)
          .fontColor(displayValue.length > 0 ? '#333333' : '#AAAAAA')
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .minHeight(48)
      .padding({ top: 8, bottom: 8 })
    } else {
      Column({ space: 6 }) {
        Text(label)
          .fontSize(14)
          .fontColor('#666666')
          .width('100%')
        TextInput({ placeholder, text: editValue })
          .onChange(onChange)
          .width('100%')
          .height(48)
          .borderRadius(12)
          .backgroundColor('#FFF5F7')
          .borderWidth(1)
          .borderColor('#F0C0D0')
          .padding({ left: 12, right: 12 })
      }
    }
  }

  private formatDate(isoDate: string): string {
    const d = new Date(isoDate);
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
  }

  private formatDateSimple(date: Date): string {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    try {
      this.config = await this.prefsService.loadConfig();
    } catch (e) {
      promptAction.showToast({ message: `加载失败: ${e}` });
    } finally {
      this.isLoading = false;
    }
  }

  private startEditing(): void {
    if (!this.config) return;
    this.editBabyName = this.config.babyName;
    this.editBirthDateStr = this.config.babyBirthDate
      ? this.formatDateSimple(new Date(this.config.babyBirthDate))
      : '';
    this.editWebdavUrl = this.config.webdavUrl;
    this.editUsername = this.config.username;
    this.editPassword = '';
    if (this.config.babyBirthDate) {
      this.selectedDate = new Date(this.config.babyBirthDate);
    }
    this.isEditing = true;
  }

  private async onSave(): Promise<void> {
    if (this.editBabyName.trim().length === 0) {
      promptAction.showToast({ message: '请输入宝宝昵称' });
      return;
    }
    if (this.editWebdavUrl.trim().length === 0) {
      promptAction.showToast({ message: '请输入 WebDAV 服务器地址' });
      return;
    }
    if (this.editUsername.trim().length === 0) {
      promptAction.showToast({ message: '请输入用户名' });
      return;
    }

    this.isSaving = true;
    try {
      const updatedConfig = new AppConfig(
        this.config!.id,
        this.editWebdavUrl.trim(),
        this.editUsername.trim(),
        this.editPassword.trim().length > 0 ? this.editPassword.trim() : this.config!.password,
        this.editBabyName.trim(),
        this.editBirthDateStr.length > 0 ? new Date(this.editBirthDateStr).toISOString() : '',
        this.config!.babyConceptionDate,
        this.config!.videoCompressionThreshold,
        [this.editWebdavUrl.trim()],
      );

      await this.prefsService.saveConfig(updatedConfig);

      // 同步到 WebDAV
      try {
        await this.webdavService.initialize(updatedConfig);
        await this.webdavService.saveConfig(updatedConfig);
      } catch (_e) {
        // 网络错误不阻断本地保存
      }

      this.config = updatedConfig;
      this.isEditing = false;
      promptAction.showToast({ message: '设置已保存' });
    } catch (e) {
      promptAction.showToast({ message: `保存失败: ${e}` });
    } finally {
      this.isSaving = false;
    }
  }
}
