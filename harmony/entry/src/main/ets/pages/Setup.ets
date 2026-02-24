import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppConfig, generateUUID } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';
import { QRService } from '../service/QRService';

/**
 * 初始化设置页面
 * 风格与 Flutter SetupScreen 保持一致：
 * - Logo + 标题 + 描述
 * - 扫码 / 粘贴导入配置按钮（SymbolGlyph qrcode）
 * - 「或」分隔
 * - 「已出生 / 怀孕中」切换段
 * - 宝宝信息表单
 * - WebDAV 配置表单
 * - 完成按钮
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
  @State isPregnant: boolean = false;

  // QR 导入
  @State showQRImportPanel: boolean = false;
  @State qrPasteText: string = '';
  @State qrImportStatus: string = '';

  private prefsService = PreferencesService.getInstance();

  build() {
    Stack() {
      Scroll() {
        Column({ space: 0 }) {
          Blank().height(60)

          // ─── Logo + 标题 ──────────────────────────────────────────
          Column({ space: 12 }) {
            // Symbol 图标代替 logo
            Column() {
              SymbolGlyph($r('sys.symbol.heart_circle_fill'))
                .fontSize(72)
                .fontColor(['#E91E63'])
            }
            .width(100)
            .height(100)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            Text('欢迎使用成长日记')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#212121')
              .textAlign(TextAlign.Center)
            Text('记录宝宝的每一个珍贵瞬间')
              .fontSize(16)
              .fontColor('#9E9E9E')
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)

          Blank().height(28)

          // ─── 导入配置按钮（Flutter 风格 OutlinedButton）──────────
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.qrcode'))
                .fontSize(20)
                .fontColor(['#E91E63'])
              Text('导入配置')
                .fontSize(16)
                .fontColor('#E91E63')
            }
          }
          .width('100%')
          .height(48)
          .borderRadius(10)
          .backgroundColor('#FFFFFF')
          .borderWidth(1)
          .borderColor('#E91E63')
          .padding({ left: 24, right: 24 })
          .onClick(() => { this.showQRImportPanel = true; })

          // 「或」分隔
          Row({ space: 12 }) {
            Divider().layoutWeight(1).strokeWidth(1).color('#EEEEEE')
            Text('或')
              .fontSize(15)
              .fontColor('#9E9E9E')
              .padding({ left: 8, right: 8 })
            Divider().layoutWeight(1).strokeWidth(1).color('#EEEEEE')
          }
          .width('100%')
          .padding({ top: 20, bottom: 20 })

          // ─── 已出生 / 怀孕中 切换段（Flutter 风格）──────────────
          Row({ space: 8 }) {
            Column() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.birthday_cake_fill'))
                  .fontSize(18)
                  .fontColor(!this.isPregnant ? ['#E91E63'] : ['#9E9E9E'])
                Text('已出生')
                  .fontSize(15)
                  .fontColor(!this.isPregnant ? '#E91E63' : '#9E9E9E')
                  .fontWeight(!this.isPregnant ? FontWeight.W600 : FontWeight.Normal)
              }
            }
            .layoutWeight(1)
            .height(44)
            .borderRadius(8)
            .backgroundColor(!this.isPregnant ? '#FCE4EC' : Color.Transparent)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => { this.isPregnant = false; })

            Column() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.heart_fill'))
                  .fontSize(18)
                  .fontColor(this.isPregnant ? ['#E91E63'] : ['#9E9E9E'])
                Text('怀孕中')
                  .fontSize(15)
                  .fontColor(this.isPregnant ? '#E91E63' : '#9E9E9E')
                  .fontWeight(this.isPregnant ? FontWeight.W600 : FontWeight.Normal)
              }
            }
            .layoutWeight(1)
            .height(44)
            .borderRadius(8)
            .backgroundColor(this.isPregnant ? '#FCE4EC' : Color.Transparent)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => { this.isPregnant = true; })
          }
          .width('100%')
          .padding(4)
          .borderRadius(10)
          .borderWidth(1)
          .borderColor('#EEEEEE')
          .backgroundColor('#FFFFFF')

          Blank().height(20)

          // ─── 宝宝信息 ─────────────────────────────────────────────
          Column({ space: 0 }) {
            Text('宝宝信息')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#212121')
              .width('100%')
              .padding({ left: 16, top: 16, bottom: 12 })

            // 宝宝昵称输入
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.person_crop_circle'))
                .fontSize(20)
                .fontColor(['#9E9E9E'])
              TextInput({ placeholder: '宝宝昵称', text: this.babyName })
                .onChange((val) => { this.babyName = val; })
                .fontSize(16)
                .fontColor('#212121')
                .placeholderColor('#BDBDBD')
                .backgroundColor(Color.Transparent)
                .borderWidth(0)
                .layoutWeight(1)
                .height(44)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            Divider().strokeWidth(0.5).color('#EEEEEE').margin({ left: 52 })

            // 日期输入（生日 或 受孕日期）
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.calendar'))
                .fontSize(20)
                .fontColor(['#9E9E9E'])
              Text(this.birthDateStr.length > 0
                ? this.birthDateStr
                : (this.isPregnant ? '受孕日期（可选）' : '宝宝生日'))
                .fontSize(16)
                .fontColor(this.birthDateStr.length > 0 ? '#212121' : '#BDBDBD')
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(13)
                .fontColor(['#BDBDBD'])
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .onClick(() => { this.showDatePicker = true; })

            Blank().height(8)
          }
          .width('100%')
          .borderRadius(14)
          .backgroundColor('#FFFFFF')

          Blank().height(16)

          // ─── WebDAV 配置 ──────────────────────────────────────────
          Column({ space: 0 }) {
            Text('云存储配置')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#212121')
              .width('100%')
              .padding({ left: 16, top: 16, bottom: 4 })

            Text('用于在多设备间同步数据，支持 Nextcloud 等 WebDAV 服务')
              .fontSize(13)
              .fontColor('#9E9E9E')
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 12 })

            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.cloud'))
                .fontSize(20)
                .fontColor(['#9E9E9E'])
              TextInput({ placeholder: 'https://your-server/dav', text: this.webdavUrl })
                .onChange((val) => { this.webdavUrl = val; })
                .fontSize(16).fontColor('#212121').placeholderColor('#BDBDBD')
                .backgroundColor(Color.Transparent).borderWidth(0)
                .layoutWeight(1).height(44)
            }
            .width('100%').padding({ left: 16, right: 16 })

            Divider().strokeWidth(0.5).color('#EEEEEE').margin({ left: 52 })

            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.person_text_rectangle'))
                .fontSize(20)
                .fontColor(['#9E9E9E'])
              TextInput({ placeholder: '用户名', text: this.username })
                .onChange((val) => { this.username = val; })
                .fontSize(16).fontColor('#212121').placeholderColor('#BDBDBD')
                .backgroundColor(Color.Transparent).borderWidth(0)
                .layoutWeight(1).height(44)
            }
            .width('100%').padding({ left: 16, right: 16 })

            Divider().strokeWidth(0.5).color('#EEEEEE').margin({ left: 52 })

            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.lock'))
                .fontSize(20)
                .fontColor(['#9E9E9E'])
              TextInput({ placeholder: '密码', text: this.password })
                .onChange((val) => { this.password = val; })
                .type(InputType.Password)
                .fontSize(16).fontColor('#212121').placeholderColor('#BDBDBD')
                .backgroundColor(Color.Transparent).borderWidth(0)
                .layoutWeight(1).height(44)
            }
            .width('100%').padding({ left: 16, right: 16 })

            Blank().height(8)
          }
          .width('100%')
          .borderRadius(14)
          .backgroundColor('#FFFFFF')

          Blank().height(28)

          // ─── 完成按钮 ─────────────────────────────────────────────
          Button('完成设置')
            .width('100%')
            .height(52)
            .borderRadius(26)
            .backgroundColor('#E91E63')
            .fontColor('#FFFFFF')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .enabled(!this.isLoading)
            .opacity(this.isLoading ? 0.7 : 1.0)
            .onClick(() => { this.onSave(); })

          Blank().height(60)
        }
        .padding({ left: 20, right: 20 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FAFAFA')

      // ─── 日期选择器弹窗 ────────────────────────────────────────────
      if (this.showDatePicker) {
        Column() {
          Column({ space: 0 }) {
            Row() {
              Button('取消').backgroundColor(Color.Transparent).fontColor('#9E9E9E')
                .onClick(() => { this.showDatePicker = false; })
              Blank().layoutWeight(1)
              Text('选择日期').fontSize(16).fontWeight(FontWeight.Bold)
              Blank().layoutWeight(1)
              Button('确定').backgroundColor(Color.Transparent).fontColor('#E91E63')
                .onClick(() => {
                  this.birthDateStr = this.formatDate(this.selectedDate);
                  this.showDatePicker = false;
                })
            }
            .width('100%').padding({ left: 8, right: 8 })

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
          .borderRadius({ topLeft: 20, topRight: 20 })
          .padding({ top: 8, bottom: 20 })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('#80000000')
        .onClick(() => { this.showDatePicker = false; })
      }

      // ─── QR 导入面板 ──────────────────────────────────────────────
      if (this.showQRImportPanel) {
        Column() {
          Column({ space: 16 }) {
            // 标题
            Row() {
              Text('导入配置')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#212121')
                .layoutWeight(1)
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(16)
                  .fontColor(['#757575'])
              }
              .width(32).height(32)
              .backgroundColor('#F5F5F5')
              .onClick(() => { this.showQRImportPanel = false; this.qrPasteText = ''; })
            }
            .width('100%')

            // 说明
            Text('将另一台设备上「设置 → 配置分享」页面生成的数据粘贴到下方输入框，或直接输入加密数据字符串。')
              .fontSize(13)
              .fontColor('#757575')
              .lineHeight(20)
              .width('100%')

            // 粘贴输入框
            TextArea({ placeholder: '粘贴配置数据...', text: this.qrPasteText })
              .onChange((val) => { this.qrPasteText = val; })
              .width('100%')
              .height(100)
              .borderRadius(10)
              .borderWidth(1)
              .borderColor('#EEEEEE')
              .backgroundColor('#FAFAFA')
              .fontSize(14)

            // 状态提示
            if (this.qrImportStatus.length > 0) {
              Text(this.qrImportStatus)
                .fontSize(13)
                .fontColor(this.qrImportStatus.startsWith('✓') ? '#4CAF50' : '#F44336')
                .width('100%')
            }

            // 导入按钮
            Button('确认导入')
              .width('100%')
              .height(44)
              .borderRadius(22)
              .backgroundColor('#E91E63')
              .fontColor('#FFFFFF')
              .onClick(() => { this.doQRImport(); })
          }
          .width('85%')
          .padding(24)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .shadow({ radius: 16, color: '#20000000', offsetX: 0, offsetY: 4 })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#80000000')
        .onClick(() => { this.showQRImportPanel = false; this.qrPasteText = ''; })
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

  private async doQRImport(): Promise<void> {
    const text = this.qrPasteText.trim();
    if (text.length === 0) {
      this.qrImportStatus = '请先粘贴配置数据';
      return;
    }
    const imported = QRService.decodeEncryptedQRData(text);
    if (!imported) {
      this.qrImportStatus = '无效的配置数据，请确认来源正确';
      return;
    }
    this.qrImportStatus = `✓ 识别到宝宝「${imported.babyName}」`;
    try {
      const webdav = new WebDAVService();
      await webdav.initialize(imported);
      await this.prefsService.saveConfig(imported);
      await this.prefsService.setCurrentConfigId(imported.id);
      try { await webdav.saveConfig(imported); } catch { /* WebDAV 同步失败不阻断本地导入 */ }
      promptAction.showToast({ message: `已导入「${imported.babyName}」的配置` });
      router.replaceUrl({ url: 'pages/Index' });
    } catch (e) {
      this.qrImportStatus = `导入失败: ${e}`;
    }
  }

  private async onSave(): Promise<void> {
    if (this.babyName.trim().length === 0) {
      promptAction.showToast({ message: '请输入宝宝昵称' }); return;
    }
    if (this.webdavUrl.trim().length === 0) {
      promptAction.showToast({ message: '请输入 WebDAV 服务器地址' }); return;
    }
    if (this.username.trim().length === 0) {
      promptAction.showToast({ message: '请输入用户名' }); return;
    }
    if (this.password.trim().length === 0) {
      promptAction.showToast({ message: '请输入密码' }); return;
    }
    this.isLoading = true;
    try {
      const config = new AppConfig(
        generateUUID(), this.webdavUrl.trim(), this.username.trim(),
        this.password.trim(), this.babyName.trim(),
        this.birthDateStr.length > 0 ? new Date(this.birthDateStr).toISOString() : '',
        '', 10, [this.webdavUrl.trim()],
      );
      const webdav = new WebDAVService();
      await webdav.initialize(config);
      await this.prefsService.saveConfig(config);
      await this.prefsService.setCurrentConfigId(config.id);
      try { await webdav.saveConfig(config); } catch { /* 网络失败不阻断本地初始化设置 */ }
      promptAction.showToast({ message: '设置已保存' });
      router.replaceUrl({ url: 'pages/Index' });
    } catch (e) {
      promptAction.showToast({ message: `保存失败: ${e}` });
    } finally {
      this.isLoading = false;
    }
  }
}
