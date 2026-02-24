import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { DiaryEntry, AgeCalculator } from '../model/DiaryEntry';
import { AppConfig } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';
import { generateUUID } from '../model/AppConfig';

/**
 * 日记编辑页面
 * 支持新建和编辑日记条目（文字 + 日期）
 */
@Entry
@Component
struct DiaryEditor {
  @State title: string = '';
  @State content: string = '';
  @State selectedDateStr: string = '';
  @State isLoading: boolean = false;
  @State showDatePicker: boolean = false;
  @State selectedDate: Date = new Date();

  private config: AppConfig | null = null;
  private entryToEdit: DiaryEntry | null = null;
  private webdavService = new WebDAVService();
  private prefsService = PreferencesService.getInstance();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    const configId = params?.['configId'] ?? '';
    const entryJson = params?.['entryJson'] ?? '';

    this.initData(configId, entryJson);
  }

  private async initData(configId: string, entryJson: string): Promise<void> {
    try {
      const cfg = await this.prefsService.loadConfig(configId);
      if (!cfg) return;
      this.config = cfg;
      await this.webdavService.initialize(cfg);

      // 如果是编辑模式，预填充数据
      if (entryJson.length > 0) {
        this.entryToEdit = DiaryEntry.fromJson(JSON.parse(entryJson) as Record<string, Object>);
        this.title = this.entryToEdit.title;
        this.content = this.entryToEdit.description;
        this.selectedDateStr = this.formatDate(new Date(this.entryToEdit.date));
        this.selectedDate = new Date(this.entryToEdit.date);
      } else {
        this.selectedDate = new Date();
        this.selectedDateStr = this.formatDate(this.selectedDate);
      }
    } catch (e) {
      promptAction.showToast({ message: `初始化失败: ${e}` });
    }
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

          Text(this.entryToEdit ? '编辑记录' : '新建记录')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Button(this.isLoading ? '...' : '保存')
            .height(36)
            .borderRadius(18)
            .backgroundColor('#E91E8C')
            .fontColor('#FFFFFF')
            .fontSize(15)
            .enabled(!this.isLoading)
            .onClick(() => { this.onSave(); })
        }
        .width('100%')
        .height(60)
        .padding({ left: 12, right: 16 })
        .backgroundColor('#FFFFFF')
        .shadow({ radius: 4, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

        // 表单内容
        Scroll() {
          Column({ space: 20 }) {
            // 日期选择
            Column({ space: 6 }) {
              Text('记录日期')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              Row() {
                Text('📅')
                  .fontSize(18)
                  .margin({ right: 8 })
                Text(this.selectedDateStr.length > 0 ? this.selectedDateStr : '点击选择日期')
                  .fontSize(16)
                  .fontColor(this.selectedDateStr.length > 0 ? '#333333' : '#AAAAAA')
                  .layoutWeight(1)
                if (this.config?.babyBirthDate && this.selectedDateStr.length > 0) {
                  Text(AgeCalculator.formatDetailedAgeLabel(
                    new Date(this.selectedDateStr).toISOString(),
                    this.config.babyBirthDate
                  ))
                    .fontSize(13)
                    .fontColor('#E91E8C')
                    .backgroundColor('#FFF0F5')
                    .borderRadius(8)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                }
              }
              .width('100%')
              .height(52)
              .borderRadius(12)
              .backgroundColor('#FFFFFF')
              .borderWidth(1)
              .borderColor('#F0C0D0')
              .padding({ left: 12, right: 12 })
              .onClick(() => { this.showDatePicker = true; })
            }
            .width('100%')

            // 标题
            Column({ space: 6 }) {
              Text('标题')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              TextInput({ placeholder: '今天发生了什么...', text: this.title })
                .onChange((val) => { this.title = val; })
                .width('100%')
                .height(52)
                .borderRadius(12)
                .backgroundColor('#FFFFFF')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .padding({ left: 12, right: 12 })
            }
            .width('100%')

            // 内容
            Column({ space: 6 }) {
              Text('描述')
                .fontSize(14)
                .fontColor('#666666')
                .width('100%')
              TextArea({ placeholder: '记录宝宝成长的点点滴滴...', text: this.content })
                .onChange((val) => { this.content = val; })
                .width('100%')
                .height(200)
                .borderRadius(12)
                .backgroundColor('#FFFFFF')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .padding(12)
            }
            .width('100%')

            // 提示信息
            Row({ space: 8 }) {
              Text('ℹ️')
                .fontSize(14)
              Text('照片和视频可以在宝宝的 WebDAV 存储空间中直接管理')
                .fontSize(12)
                .fontColor('#AAAAAA')
                .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor('#FFF8F0')

            Blank().height(40)
          }
          .padding(20)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FFF5F7')
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
              Text('选择日期')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
              Blank()
              Button('确定')
                .backgroundColor(Color.Transparent)
                .fontColor('#E91E8C')
                .onClick(() => {
                  this.selectedDateStr = this.formatDate(this.selectedDate);
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
    if (this.title.trim().length === 0 && this.content.trim().length === 0) {
      promptAction.showToast({ message: '请至少输入标题或描述' });
      return;
    }

    if (!this.config) {
      promptAction.showToast({ message: '配置未加载，请返回重试' });
      return;
    }

    this.isLoading = true;
    try {
      const dateIso = this.selectedDateStr.length > 0
        ? new Date(this.selectedDateStr).toISOString()
        : new Date().toISOString();

      const ageInMonths = this.config.babyBirthDate
        ? AgeCalculator.calculateAgeInMonths(this.config.babyBirthDate, dateIso)
        : 0;

      let entry: DiaryEntry;
      if (this.entryToEdit) {
        // 编辑模式：保留原有媒体文件
        entry = new DiaryEntry(
          this.entryToEdit.id,
          dateIso,
          this.title.trim(),
          this.content.trim(),
          this.entryToEdit.imagePaths,
          this.entryToEdit.videoPaths,
          this.entryToEdit.imageThumbnails,
          this.entryToEdit.videoThumbnails,
          ageInMonths,
        );
      } else {
        // 新建模式
        entry = new DiaryEntry(
          generateUUID(),
          dateIso,
          this.title.trim(),
          this.content.trim(),
          [],
          [],
          [],
          [],
          ageInMonths,
        );
      }

      await this.webdavService.saveDiaryEntry(entry);
      promptAction.showToast({ message: this.entryToEdit ? '记录已更新' : '记录已保存' });
      router.back();
    } catch (e) {
      promptAction.showToast({ message: `保存失败: ${e}` });
    } finally {
      this.isLoading = false;
    }
  }
}
