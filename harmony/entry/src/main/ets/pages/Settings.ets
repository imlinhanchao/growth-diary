import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppConfig, generateUUID } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';

/**
 * 设置页面
 * 支持：
 * - 查看和修改当前宝宝信息及 WebDAV 配置
 * - 多宝宝管理（添加、删除、切换）
 * - QR 码分享 / 导入
 */
@Entry
@Component
struct Settings {
  @State config: AppConfig | null = null;
  @State allConfigs: AppConfig[] = [];
  @State isLoading: boolean = true;
  @State isEditing: boolean = false;
  @State isSaving: boolean = false;
  @State showDatePicker: boolean = false;
  @State showAddBabyPanel: boolean = false;

  // 编辑当前宝宝的字段
  @State editBabyName: string = '';
  @State editBirthDateStr: string = '';
  @State editWebdavUrl: string = '';
  @State editUsername: string = '';
  @State editPassword: string = '';
  @State selectedDate: Date = new Date();

  // 新增宝宝的字段
  @State newBabyName: string = '';
  @State newBirthDateStr: string = '';
  @State newWebdavUrl: string = '';
  @State newUsername: string = '';
  @State newPassword: string = '';
  @State newSelectedDate: Date = new Date();
  @State showNewDatePicker: boolean = false;
  @State isAddingBaby: boolean = false;

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
        } else {
          Scroll() {
            Column({ space: 20 }) {
              // ─── 当前宝宝信息 ─────────────────────────────────────────
              if (this.config) {
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

                  this.buildInfoRow(
                    '昵称',
                    this.isEditing ? undefined : this.config!.babyName,
                    '宝宝的昵称',
                    this.editBabyName,
                    (val) => { this.editBabyName = val; }
                  )

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
                        Text('📅').fontSize(18)
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
                      Text('生日').fontSize(14).fontColor('#888888').width(80)
                      Text(this.config!.babyBirthDate
                        ? this.formatDate(this.config!.babyBirthDate)
                        : '未设置')
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

                // ─── WebDAV 配置 ──────────────────────────────────────
                Column({ space: 16 }) {
                  Row() {
                    Text('WebDAV 配置')
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#333333')
                    Blank()
                    Text('☁️').fontSize(20)
                  }
                  .width('100%')

                  this.buildInfoRow('服务器', this.isEditing ? undefined : this.config!.webdavUrl, '服务器地址', this.editWebdavUrl, (val) => { this.editWebdavUrl = val; })
                  this.buildInfoRow('用户名', this.isEditing ? undefined : this.config!.username, '用户名', this.editUsername, (val) => { this.editUsername = val; })
                  if (this.isEditing) {
                    Column({ space: 6 }) {
                      Text('密码').fontSize(14).fontColor('#666666').width('100%')
                      TextInput({ placeholder: '留空保持不变', text: this.editPassword })
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
                      Text('密码').fontSize(14).fontColor('#888888').width(80)
                      Text('••••••••').fontSize(15).fontColor('#333333').layoutWeight(1)
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
              }

              // ─── 多宝宝管理 ───────────────────────────────────────────
              Column({ space: 12 }) {
                Row() {
                  Text('宝宝列表')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#333333')
                    .layoutWeight(1)
                  Button('+ 添加')
                    .height(32)
                    .borderRadius(16)
                    .backgroundColor('#FFF0F5')
                    .fontColor('#E91E8C')
                    .fontSize(13)
                    .onClick(() => { this.showAddBabyPanel = !this.showAddBabyPanel; })
                }
                .width('100%')

                ForEach(this.allConfigs, (cfg: AppConfig) => {
                  Row({ space: 12 }) {
                    Text(cfg.babyName.length > 0 ? cfg.babyName.charAt(0) : '🌸')
                      .fontSize(16)
                      .fontColor('#FFFFFF')
                      .width(36)
                      .height(36)
                      .borderRadius(18)
                      .backgroundColor(cfg.id === this.config?.id ? '#E91E8C' : '#DDDDDD')
                      .textAlign(TextAlign.Center)

                    Column({ space: 2 }) {
                      Text(cfg.babyName.length > 0 ? cfg.babyName : '(未命名)')
                        .fontSize(15)
                        .fontColor('#333333')
                      Text(cfg.getAgeLabel())
                        .fontSize(12)
                        .fontColor('#888888')
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (cfg.id === this.config?.id) {
                      Text('当前')
                        .fontSize(12)
                        .fontColor('#E91E8C')
                        .backgroundColor('#FFF0F5')
                        .borderRadius(8)
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    } else {
                      Row({ space: 8 }) {
                        Button('切换')
                          .height(28)
                          .borderRadius(14)
                          .backgroundColor('#FFF0F5')
                          .fontColor('#E91E8C')
                          .fontSize(12)
                          .onClick(() => { this.switchBaby(cfg); })
                        Button('删除')
                          .height(28)
                          .borderRadius(14)
                          .backgroundColor('#FFF0F0')
                          .fontColor('#FF4444')
                          .fontSize(12)
                          .onClick(() => { this.deleteBaby(cfg); })
                      }
                    }
                  }
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
                  .borderRadius(12)
                  .borderWidth(1)
                  .borderColor(cfg.id === this.config?.id ? '#F0C0D0' : '#F0F0F0')
                  .padding(12)
                }, (cfg: AppConfig) => cfg.id)

                // 新增宝宝表单
                if (this.showAddBabyPanel) {
                  Column({ space: 10 }) {
                    Text('添加新宝宝')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#E91E8C')
                      .width('100%')

                    TextInput({ placeholder: '宝宝昵称 *', text: this.newBabyName })
                      .onChange((val) => { this.newBabyName = val; })
                      .width('100%')
                      .height(44)
                      .borderRadius(10)
                      .backgroundColor('#FFF5F7')
                      .borderWidth(1)
                      .borderColor('#F0C0D0')
                      .padding({ left: 12, right: 12 })

                    Row() {
                      Text(this.newBirthDateStr.length > 0 ? this.newBirthDateStr : '选择生日（可选）')
                        .fontSize(14)
                        .fontColor(this.newBirthDateStr.length > 0 ? '#333333' : '#AAAAAA')
                        .layoutWeight(1)
                      Text('📅').fontSize(16)
                    }
                    .width('100%')
                    .height(44)
                    .borderRadius(10)
                    .backgroundColor('#FFF5F7')
                    .borderWidth(1)
                    .borderColor('#F0C0D0')
                    .padding({ left: 12, right: 12 })
                    .onClick(() => { this.showNewDatePicker = true; })

                    TextInput({ placeholder: 'WebDAV 服务器地址 *', text: this.newWebdavUrl })
                      .onChange((val) => { this.newWebdavUrl = val; })
                      .width('100%')
                      .height(44)
                      .borderRadius(10)
                      .backgroundColor('#FFF5F7')
                      .borderWidth(1)
                      .borderColor('#F0C0D0')
                      .padding({ left: 12, right: 12 })

                    TextInput({ placeholder: '用户名 *', text: this.newUsername })
                      .onChange((val) => { this.newUsername = val; })
                      .width('100%')
                      .height(44)
                      .borderRadius(10)
                      .backgroundColor('#FFF5F7')
                      .borderWidth(1)
                      .borderColor('#F0C0D0')
                      .padding({ left: 12, right: 12 })

                    TextInput({ placeholder: '密码 *', text: this.newPassword })
                      .onChange((val) => { this.newPassword = val; })
                      .type(InputType.Password)
                      .width('100%')
                      .height(44)
                      .borderRadius(10)
                      .backgroundColor('#FFF5F7')
                      .borderWidth(1)
                      .borderColor('#F0C0D0')
                      .padding({ left: 12, right: 12 })

                    Row({ space: 10 }) {
                      Button('取消')
                        .layoutWeight(1)
                        .height(40)
                        .borderRadius(20)
                        .backgroundColor('#F0F0F0')
                        .fontColor('#666666')
                        .onClick(() => { this.showAddBabyPanel = false; })
                      Button(this.isAddingBaby ? '...' : '确认添加')
                        .layoutWeight(1)
                        .height(40)
                        .borderRadius(20)
                        .backgroundColor('#E91E8C')
                        .fontColor('#FFFFFF')
                        .enabled(!this.isAddingBaby)
                        .onClick(() => { this.addBaby(); })
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .padding(16)
                  .borderRadius(12)
                  .backgroundColor('#FFF5F7')
                  .borderWidth(1)
                  .borderColor('#F0C0D0')
                }
              }
              .width('100%')
              .padding(20)
              .borderRadius(16)
              .backgroundColor('#FFFFFF')
              .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

              // ─── QR 码分享 ────────────────────────────────────────────
              if (this.config) {
                Column({ space: 12 }) {
                  Row() {
                    Text('配置分享')
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#333333')
                    Blank()
                    Text('📱').fontSize(20)
                  }
                  .width('100%')

                  Text('将当前宝宝的配置（含 WebDAV 信息）分享给其他设备，或从其他设备导入配置。')
                    .fontSize(13)
                    .fontColor('#888888')
                    .width('100%')

                  Button('分享 / 导入配置')
                    .width('100%')
                    .height(44)
                    .borderRadius(22)
                    .backgroundColor('#E91E8C')
                    .fontColor('#FFFFFF')
                    .fontSize(15)
                    .onClick(() => {
                      router.pushUrl({
                        url: 'pages/QRShare',
                        params: { configId: this.config?.id ?? '' }
                      });
                    })
                }
                .width('100%')
                .padding(20)
                .borderRadius(16)
                .backgroundColor('#FFFFFF')
                .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })
              }

              // ─── 应用信息 ─────────────────────────────────────────────
              Column({ space: 8 }) {
                Text('关于应用')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')
                  .width('100%')
                Row() {
                  Text('版本').fontSize(14).fontColor('#888888').width(80)
                  Text('1.0.3').fontSize(15).fontColor('#333333').layoutWeight(1)
                }
                .width('100%').height(40)
                Row() {
                  Text('平台').fontSize(14).fontColor('#888888').width(80)
                  Text('HarmonyOS').fontSize(15).fontColor('#333333').layoutWeight(1)
                }
                .width('100%').height(40)
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

      // 当前宝宝生日选择器
      if (this.showDatePicker) {
        Column() {
          Column({ space: 0 }) {
            Row() {
              Button('取消')
                .backgroundColor(Color.Transparent)
                .fontColor('#888888')
                .onClick(() => { this.showDatePicker = false; })
              Blank()
              Text('选择生日').fontSize(16).fontWeight(FontWeight.Bold)
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
            DatePicker({ start: new Date('2000-01-01'), end: new Date(), selected: this.selectedDate })
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
        .width('100%').height('100%').justifyContent(FlexAlign.End).backgroundColor('#80000000')
        .onClick(() => { this.showDatePicker = false; })
      }

      // 新增宝宝的生日选择器
      if (this.showNewDatePicker) {
        Column() {
          Column({ space: 0 }) {
            Row() {
              Button('取消')
                .backgroundColor(Color.Transparent)
                .fontColor('#888888')
                .onClick(() => { this.showNewDatePicker = false; })
              Blank()
              Text('选择生日').fontSize(16).fontWeight(FontWeight.Bold)
              Blank()
              Button('确定')
                .backgroundColor(Color.Transparent)
                .fontColor('#E91E8C')
                .onClick(() => {
                  this.newBirthDateStr = this.formatDateSimple(this.newSelectedDate);
                  this.showNewDatePicker = false;
                })
            }
            .width('100%')
            .padding({ left: 8, right: 8 })
            DatePicker({ start: new Date('2000-01-01'), end: new Date(), selected: this.newSelectedDate })
              .onDateChange((val: DatePickerResult) => {
                this.newSelectedDate = new Date(
                  val.year ?? this.newSelectedDate.getFullYear(),
                  (val.month ?? this.newSelectedDate.getMonth() + 1) - 1,
                  val.day ?? this.newSelectedDate.getDate()
                );
              })
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 24, topRight: 24 })
          .padding({ top: 8, bottom: 20 })
        }
        .width('100%').height('100%').justifyContent(FlexAlign.End).backgroundColor('#80000000')
        .onClick(() => { this.showNewDatePicker = false; })
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
        Text(label).fontSize(14).fontColor('#888888').width(80)
        Text(displayValue.length > 0 ? displayValue : '未设置')
          .fontSize(15)
          .fontColor(displayValue.length > 0 ? '#333333' : '#AAAAAA')
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%').minHeight(48).padding({ top: 8, bottom: 8 })
    } else {
      Column({ space: 6 }) {
        Text(label).fontSize(14).fontColor('#666666').width('100%')
        TextInput({ placeholder, text: editValue })
          .onChange(onChange)
          .width('100%').height(48)
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

  /** 安全地将日期字符串转为 ISO 字符串，无效时返回空字符串 */
  private parseDateSafe(dateStr: string): string {
    if (!dateStr || dateStr.length === 0) return '';
    try {
      const d = new Date(dateStr);
      if (isNaN(d.getTime())) return '';
      return d.toISOString();
    } catch {
      return '';
    }
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    try {
      const configs = await this.prefsService.loadAllConfigs();
      this.allConfigs = Object.values(configs);
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
      promptAction.showToast({ message: '请输入宝宝昵称' }); return;
    }
    if (this.editWebdavUrl.trim().length === 0) {
      promptAction.showToast({ message: '请输入 WebDAV 服务器地址' }); return;
    }
    if (this.editUsername.trim().length === 0) {
      promptAction.showToast({ message: '请输入用户名' }); return;
    }

    this.isSaving = true;
    try {
      const updatedConfig = new AppConfig(
        this.config!.id,
        this.editWebdavUrl.trim(),
        this.editUsername.trim(),
        this.editPassword.trim().length > 0 ? this.editPassword.trim() : this.config!.password,
        this.editBabyName.trim(),
        this.parseDateSafe(this.editBirthDateStr),
        this.config!.babyConceptionDate,
        this.config!.videoCompressionThreshold,
        [this.editWebdavUrl.trim()],
      );

      await this.prefsService.saveConfig(updatedConfig);

      try {
        await this.webdavService.initialize(updatedConfig);
        await this.webdavService.saveConfig(updatedConfig);
      } catch (_e) { /* 网络失败不影响本地保存 */ }

      this.config = updatedConfig;
      // 更新 allConfigs 中的条目
      const idx = this.allConfigs.findIndex(c => c.id === updatedConfig.id);
      if (idx >= 0) {
        const updated = [...this.allConfigs];
        updated[idx] = updatedConfig;
        this.allConfigs = updated;
      }
      this.isEditing = false;
      promptAction.showToast({ message: '设置已保存' });
    } catch (e) {
      promptAction.showToast({ message: `保存失败: ${e}` });
    } finally {
      this.isSaving = false;
    }
  }

  private async switchBaby(cfg: AppConfig): Promise<void> {
    await this.prefsService.setCurrentConfigId(cfg.id);
    this.config = cfg;
    promptAction.showToast({ message: `已切换到宝宝「${cfg.babyName}」` });
  }

  private async deleteBaby(cfg: AppConfig): Promise<void> {
    if (this.allConfigs.length <= 1) {
      promptAction.showToast({ message: '至少保留一个宝宝配置' });
      return;
    }
    promptAction.showDialog({
      title: '确认删除',
      message: `确定要删除宝宝「${cfg.babyName}」的配置吗？`,
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '删除', color: '#FF4444' },
      ],
    }).then(async (result) => {
      if (result.index === 1) {
        await this.prefsService.deleteConfig(cfg.id);
        this.allConfigs = this.allConfigs.filter(c => c.id !== cfg.id);
        if (this.config?.id === cfg.id) {
          this.config = this.allConfigs[0] ?? null;
        }
        promptAction.showToast({ message: '已删除' });
      }
    }).catch(() => {});
  }

  private async addBaby(): Promise<void> {
    if (this.newBabyName.trim().length === 0) {
      promptAction.showToast({ message: '请输入宝宝昵称' }); return;
    }
    if (this.newWebdavUrl.trim().length === 0) {
      promptAction.showToast({ message: '请输入 WebDAV 服务器地址' }); return;
    }
    if (this.newUsername.trim().length === 0) {
      promptAction.showToast({ message: '请输入用户名' }); return;
    }
    if (this.newPassword.trim().length === 0) {
      promptAction.showToast({ message: '请输入密码' }); return;
    }

    this.isAddingBaby = true;
    try {
      const newCfg = new AppConfig(
        generateUUID(),
        this.newWebdavUrl.trim(),
        this.newUsername.trim(),
        this.newPassword.trim(),
        this.newBabyName.trim(),
        this.parseDateSafe(this.newBirthDateStr),
        '',
        10,
        [this.newWebdavUrl.trim()],
      );

      await this.prefsService.saveConfig(newCfg);
      this.allConfigs = [...this.allConfigs, newCfg];

      try {
        const wds = new WebDAVService();
        await wds.initialize(newCfg);
        await wds.saveConfig(newCfg);
      } catch (_e) { /* 网络失败不阻断 */ }

      // 重置表单
      this.newBabyName = '';
      this.newBirthDateStr = '';
      this.newWebdavUrl = '';
      this.newUsername = '';
      this.newPassword = '';
      this.showAddBabyPanel = false;

      promptAction.showToast({ message: `已添加宝宝「${newCfg.babyName}」` });
    } catch (e) {
      promptAction.showToast({ message: `添加失败: ${e}` });
    } finally {
      this.isAddingBaby = false;
    }
  }
}
