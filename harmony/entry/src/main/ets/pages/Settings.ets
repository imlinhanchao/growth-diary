import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppConfig, generateUUID } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';

/**
 * 设置页面
 * 风格与 Flutter SettingsScreen 保持一致：
 * - 白色背景
 * - 粉色分组标题（section header）
 * - ListTile 风格条目（SymbolGlyph 图标 + 标签 + 值/箭头）
 * - 多宝宝列表
 * - QR 分享入口
 */
@Entry
@Component
struct Settings {
  @State config: AppConfig | null = null;
  @State allConfigs: AppConfig[] = [];
  @State isLoading: boolean = true;
  @State showAddBabyPanel: boolean = false;

  // 新增宝宝字段
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
    Column() {
      // ─── AppBar ────────────────────────────────────────────────────
      Row() {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(20)
            .fontColor(['#212121'])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => { router.back(); })

        Text('设置')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#212121')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(40)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      Divider().strokeWidth(0.5).color('#F0F0F0')

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#E91E63')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: 0 }) {

            // ─── 宝宝信息（section）────────────────────────────────
            this.buildSectionHeader('宝宝信息')

            if (this.config) {
              this.buildListTile(
                '宝宝昵称',
                this.config!.babyName,
                () => {}
              )
              this.buildListTile(
                '生日',
                this.config!.babyBirthDate
                  ? this.formatDate(this.config!.babyBirthDate)
                  : '未设置',
                () => {}
              )
              this.buildListTile(
                '修改配置',
                '',
                () => { router.pushUrl({ url: 'pages/QRShare', params: { configId: this.config?.id ?? '', mode: 'edit' } }); }
              )
            }

            Divider().strokeWidth(8).color('#F5F5F5')

            // ─── WebDAV 配置（section）────────────────────────────
            this.buildSectionHeader('云存储')

            if (this.config) {
              this.buildListTile(
                '服务器',
                this.config!.webdavUrl.length > 0 ? this.config!.webdavUrl : '未配置',
                () => {}
              )
              this.buildListTile(
                '用户名',
                this.config!.username,
                () => {}
              )
              this.buildListTile(
                '密码',
                '••••••••',
                () => {}
              )
            }

            Divider().strokeWidth(8).color('#F5F5F5')

            // ─── 宝宝列表（多宝宝管理）────────────────────────────
            Row() {
              Text('宝宝列表')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor('#C2185B')
                .padding({ left: 16, top: 12, bottom: 4 })
                .layoutWeight(1)
              Button('添加')
                .height(28)
                .borderRadius(14)
                .backgroundColor('#FCE4EC')
                .fontColor('#E91E63')
                .fontSize(13)
                .padding({ left: 12, right: 12 })
                .margin({ right: 16, top: 8 })
                .onClick(() => { this.showAddBabyPanel = !this.showAddBabyPanel; })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            ForEach(this.allConfigs, (cfg: AppConfig) => {
              Row({ space: 14 }) {
                // 头像
                Column() {
                  Text(cfg.babyName.length > 0 ? cfg.babyName.charAt(0) : '宝')
                    .fontSize(16)
                    .fontColor('#FFFFFF')
                }
                .width(40)
                .height(40)
                .borderRadius(20)
                .backgroundColor(cfg.id === this.config?.id ? '#E91E63' : '#BDBDBD')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Column({ space: 2 }) {
                  Text(cfg.babyName.length > 0 ? cfg.babyName : '(未命名)')
                    .fontSize(16)
                    .fontColor('#212121')
                  Text(cfg.getAgeLabel())
                    .fontSize(12)
                    .fontColor('#9E9E9E')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (cfg.id === this.config?.id) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor(['#E91E63'])
                } else {
                  Row({ space: 8 }) {
                    Text('切换')
                      .fontSize(13)
                      .fontColor('#E91E63')
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor('#FCE4EC')
                      .borderRadius(12)
                      .onClick(() => { this.switchBaby(cfg); })
                    Text('删除')
                      .fontSize(13)
                      .fontColor('#F44336')
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor('#FFEBEE')
                      .borderRadius(12)
                      .onClick(() => { this.deleteBaby(cfg); })
                  }
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor('#FFFFFF')
              Divider().strokeWidth(0.5).color('#F5F5F5').margin({ left: 70 })
            }, (cfg: AppConfig) => cfg.id)

            // 新增宝宝表单
            if (this.showAddBabyPanel) {
              Column({ space: 10 }) {
                Text('添加新宝宝')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#E91E63')
                  .width('100%')

                TextInput({ placeholder: '宝宝昵称 *', text: this.newBabyName })
                  .onChange((v) => { this.newBabyName = v; })
                  .width('100%').height(44).borderRadius(10)
                  .backgroundColor('#FAFAFA')
                  .borderWidth(1).borderColor('#EEEEEE')
                  .padding({ left: 12, right: 12 })

                Row() {
                  SymbolGlyph($r('sys.symbol.calendar'))
                    .fontSize(16)
                    .fontColor(['#E91E63'])
                    .margin({ right: 8 })
                  Text(this.newBirthDateStr.length > 0
                    ? this.newBirthDateStr
                    : '选择生日（可选）')
                    .fontSize(15)
                    .fontColor(this.newBirthDateStr.length > 0 ? '#212121' : '#BDBDBD')
                    .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(13)
                    .fontColor(['#BDBDBD'])
                }
                .width('100%').height(44).borderRadius(10)
                .backgroundColor('#FAFAFA').borderWidth(1).borderColor('#EEEEEE')
                .padding({ left: 12, right: 12 })
                .onClick(() => { this.showNewDatePicker = true; })

                TextInput({ placeholder: 'WebDAV 服务器地址 *', text: this.newWebdavUrl })
                  .onChange((v) => { this.newWebdavUrl = v; })
                  .width('100%').height(44).borderRadius(10)
                  .backgroundColor('#FAFAFA').borderWidth(1).borderColor('#EEEEEE')
                  .padding({ left: 12, right: 12 })

                TextInput({ placeholder: '用户名 *', text: this.newUsername })
                  .onChange((v) => { this.newUsername = v; })
                  .width('100%').height(44).borderRadius(10)
                  .backgroundColor('#FAFAFA').borderWidth(1).borderColor('#EEEEEE')
                  .padding({ left: 12, right: 12 })

                TextInput({ placeholder: '密码 *', text: this.newPassword })
                  .onChange((v) => { this.newPassword = v; })
                  .type(InputType.Password)
                  .width('100%').height(44).borderRadius(10)
                  .backgroundColor('#FAFAFA').borderWidth(1).borderColor('#EEEEEE')
                  .padding({ left: 12, right: 12 })

                Row({ space: 10 }) {
                  Button('取消')
                    .layoutWeight(1).height(40).borderRadius(20)
                    .backgroundColor('#EEEEEE').fontColor('#616161')
                    .onClick(() => { this.showAddBabyPanel = false; })
                  Button(this.isAddingBaby ? '...' : '确认添加')
                    .layoutWeight(1).height(40).borderRadius(20)
                    .backgroundColor('#E91E63').fontColor('#FFFFFF')
                    .enabled(!this.isAddingBaby)
                    .onClick(() => { this.addBaby(); })
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFF8F9')
              .borderWidth(1)
              .borderColor('#F8BBD0')
            }

            Divider().strokeWidth(8).color('#F5F5F5')

            // ─── 配置分享（QR 码）────────────────────────────────
            this.buildSectionHeader('配置分享')

            Row({ space: 14 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.qrcode'))
                  .fontSize(22)
                  .fontColor(['#E91E63'])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor('#FCE4EC')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Column({ space: 2 }) {
                Text('分享 / 导入配置')
                  .fontSize(16)
                  .fontColor('#212121')
                Text('通过加密数据在设备间传输宝宝配置')
                  .fontSize(12)
                  .fontColor('#9E9E9E')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor(['#BDBDBD'])
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .backgroundColor('#FFFFFF')
            .onClick(() => {
              router.pushUrl({
                url: 'pages/QRShare',
                params: { configId: this.config?.id ?? '' }
              });
            })

            Divider().strokeWidth(0.5).color('#F5F5F5').margin({ left: 70 })
            Divider().strokeWidth(8).color('#F5F5F5')

            // ─── 关于（section）──────────────────────────────────
            this.buildSectionHeader('关于')

            Row({ space: 14 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.info_circle'))
                  .fontSize(22)
                  .fontColor(['#9E9E9E'])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor('#F5F5F5')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Column({ space: 2 }) {
                Text('版本')
                  .fontSize(16)
                  .fontColor('#212121')
                Text('1.0.3 · HarmonyOS')
                  .fontSize(12)
                  .fontColor('#9E9E9E')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .backgroundColor('#FFFFFF')

            Blank().height(40)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#F5F5F5')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')

    // ─── 新增宝宝的生日选择器 ─────────────────────────────────────
    if (this.showNewDatePicker) {
      Stack() {
        Blank()
          .width('100%')
          .height('100%')
          .backgroundColor('#80000000')
          .onClick(() => { this.showNewDatePicker = false; })

        Column({ space: 0 }) {
          Row() {
            Button('取消')
              .backgroundColor(Color.Transparent).fontColor('#9E9E9E')
              .onClick(() => { this.showNewDatePicker = false; })
            Blank().layoutWeight(1)
            Text('选择生日').fontSize(16).fontWeight(FontWeight.Bold)
            Blank().layoutWeight(1)
            Button('确定')
              .backgroundColor(Color.Transparent).fontColor('#E91E63')
              .onClick(() => {
                this.newBirthDateStr = this.formatDateSimple(this.newSelectedDate);
                this.showNewDatePicker = false;
              })
          }
          .width('100%').padding({ left: 8, right: 8 })

          DatePicker({
            start: new Date('2000-01-01'),
            end: new Date(),
            selected: this.newSelectedDate,
          })
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
        .borderRadius({ topLeft: 20, topRight: 20 })
        .padding({ top: 8, bottom: 20 })
        .position({ left: 0, bottom: 0 })
      }
      .width('100%')
      .height('100%')
      .position({ left: 0, top: 0 })
    }
  }

  @Builder
  buildSectionHeader(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor('#C2185B')
      .width('100%')
      .padding({ left: 16, top: 16, bottom: 8 })
      .backgroundColor('#F5F5F5')
  }

  @Builder
  buildListTile(label: string, value: string, onClick: () => void) {
    Row({ space: 14 }) {
      // Icon determined by label since $r() cannot be dynamic
      if (label === '宝宝昵称') {
        SymbolGlyph($r('sys.symbol.person_crop_circle'))
          .fontSize(20).fontColor(['#9E9E9E']).width(24).height(24)
      } else if (label === '生日') {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(20).fontColor(['#9E9E9E']).width(24).height(24)
      } else if (label === '修改配置') {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20).fontColor(['#9E9E9E']).width(24).height(24)
      } else if (label === '服务器') {
        SymbolGlyph($r('sys.symbol.cloud'))
          .fontSize(20).fontColor(['#9E9E9E']).width(24).height(24)
      } else if (label === '用户名') {
        SymbolGlyph($r('sys.symbol.person_text_rectangle'))
          .fontSize(20).fontColor(['#9E9E9E']).width(24).height(24)
      } else if (label === '密码') {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(20).fontColor(['#9E9E9E']).width(24).height(24)
      } else {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20).fontColor(['#9E9E9E']).width(24).height(24)
      }
      Text(label)
        .fontSize(16)
        .fontColor('#212121')
        .layoutWeight(1)
      if (value.length > 0) {
        Text(value)
          .fontSize(15)
          .fontColor('#9E9E9E')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 160 })
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor(['#BDBDBD'])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor('#FFFFFF')
    .onClick(onClick)

    Divider().strokeWidth(0.5).color('#F5F5F5').margin({ left: 54 })
  }

  private formatDate(isoDate: string): string {
    const d = new Date(isoDate);
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
  }

  private formatDateSimple(date: Date): string {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  private parseDateSafe(dateStr: string): string {
    if (!dateStr || dateStr.length === 0) return '';
    try {
      const d = new Date(dateStr);
      return isNaN(d.getTime()) ? '' : d.toISOString();
    } catch { return ''; }
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
      message: `确定要删除宝宝「${cfg.babyName}」的配置吗？此操作不可撤销。`,
      buttons: [
        { text: '取消', color: '#9E9E9E' },
        { text: '删除', color: '#F44336' },
      ],
    }, async (err, data) => {
      if (!err && data.index === 1) {
        await this.prefsService.deleteConfig(cfg.id);
        this.allConfigs = this.allConfigs.filter(c => c.id !== cfg.id);
        if (this.config?.id === cfg.id) {
          this.config = this.allConfigs[0] ?? null;
        }
        promptAction.showToast({ message: `已删除「${cfg.babyName}」` });
      }
    });
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
        generateUUID(), this.newWebdavUrl.trim(), this.newUsername.trim(),
        this.newPassword.trim(), this.newBabyName.trim(),
        this.parseDateSafe(this.newBirthDateStr), '', 10, [this.newWebdavUrl.trim()],
      );
      await this.prefsService.saveConfig(newCfg);
      this.allConfigs = [...this.allConfigs, newCfg];
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
