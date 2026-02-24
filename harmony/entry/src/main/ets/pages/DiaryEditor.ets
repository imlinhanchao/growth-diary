import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { DiaryEntry, AgeCalculator } from '../model/DiaryEntry';
import { AppConfig, generateUUID } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';
import { MediaService } from '../service/MediaService';
import { UploadQueueService, UploadTask } from '../service/UploadQueueService';

/** 待显示的本地媒体项 */
interface LocalMediaItem {
  uri: string;
  type: 'photo' | 'video';
}

/**
 * 日记编辑页面
 * 风格与 Flutter DiaryEditorScreen 保持一致：
 * - 白色 AppBar，左侧 xmark 关闭图标，居中标题，右侧保存按钮
 * - 日期选择行（日历图标 + 日期文字 + 星期 + 右箭头）
 * - Apple Notes 风格：大标题输入框 + 内容输入区（无标签）
 * - 媒体区：横向滚动缩略图 + 照片/视频添加按钮（SymbolGlyph）
 */
@Entry
@Component
struct DiaryEditor {
  @State title: string = '';
  @State content: string = '';
  @State selectedDateStr: string = '';
  @State isSavingEntry: boolean = false;
  @State showDatePicker: boolean = false;
  @State selectedDate: Date = new Date();
  @State localMediaItems: LocalMediaItem[] = [];
  @State uploadProgress: string = '';

  private config: AppConfig | null = null;
  private entryToEdit: DiaryEntry | null = null;
  private webdavService = new WebDAVService();
  private prefsService = PreferencesService.getInstance();
  private uploadQueueService = UploadQueueService.getInstance();
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = getContext(this) as common.UIAbilityContext;
    const params = router.getParams() as Record<string, string>;
    const configId = params?.['configId'] ?? '';
    const entryJson = params?.['entryJson'] ?? '';
    const autoPickPhoto = params?.['autoPickPhoto'] === 'true';
    const autoPickVideo = params?.['autoPickVideo'] === 'true';
    this.initData(configId, entryJson, autoPickPhoto, autoPickVideo);
  }

  private async initData(
    configId: string, entryJson: string,
    autoPickPhoto: boolean, autoPickVideo: boolean
  ): Promise<void> {
    try {
      const cfg = await this.prefsService.loadConfig(configId);
      if (!cfg) return;
      this.config = cfg;
      await this.webdavService.initialize(cfg);
      if (entryJson.length > 0) {
        this.entryToEdit = DiaryEntry.fromJson(JSON.parse(entryJson) as Record<string, Object>);
        this.title = this.entryToEdit.title;
        this.content = this.entryToEdit.description;
        this.selectedDate = new Date(this.entryToEdit.date);
        this.selectedDateStr = this.formatDate(this.selectedDate);
      } else {
        this.selectedDate = new Date();
        this.selectedDateStr = this.formatDate(this.selectedDate);
      }
      // 自动弹出媒体选取器
      if (autoPickPhoto) this.pickPhotos();
      else if (autoPickVideo) this.pickVideos();
    } catch (e) {
      promptAction.showToast({ message: `初始化失败: ${e}` });
    }
  }

  build() {
    Stack() {
      Column() {
        // ─── 白色 AppBar（Flutter 风格）──────────────────────────────
        Row() {
          // 左侧关闭按钮
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor(['#212121'])
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back(); })

          // 居中标题
          Text(this.entryToEdit ? '编辑日记' : '写日记')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#212121')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          // 右侧保存按钮（粉色胶囊）
          Button(this.isSavingEntry ? '...' : '保存')
            .height(36)
            .borderRadius(20)
            .backgroundColor('#FCE4EC')
            .fontColor('#E91E63')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .padding({ left: 16, right: 16 })
            .enabled(!this.isSavingEntry)
            .onClick(() => { this.onSave(); })
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 16 })
        .backgroundColor('#FFFFFF')

        Divider()
          .strokeWidth(0.5)
          .color('#F0F0F0')

        // ─── 日期选择行（Flutter 风格）──────────────────────────────
        Row() {
          // 日历图标容器（粉色圆角）
          Column() {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(18)
              .fontColor(['#E91E63'])
          }
          .width(36)
          .height(36)
          .borderRadius(8)
          .backgroundColor('#FCE4EC')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ right: 12 })

          Text(this.selectedDateStr.length > 0
            ? this.formatDisplayDate(this.selectedDate)
            : '选择日期')
            .fontSize(16)
            .fontWeight(FontWeight.W600)
            .fontColor('#424242')

          Blank().width(8)
          Text(this.selectedDateStr.length > 0
            ? this.getWeekday(this.selectedDate)
            : '')
            .fontSize(14)
            .fontColor('#9E9E9E')

          Blank().layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(13)
            .fontColor(['#BDBDBD'])
        }
        .width('100%')
        .padding({ left: 24, right: 16, top: 12, bottom: 12 })
        .backgroundColor('#FFFFFF')
        .onClick(() => { this.showDatePicker = true; })

        Divider()
          .strokeWidth(0.5)
          .color('#EEEEEE')
          .margin({ left: 24, right: 24 })

        // ─── 内容编辑区域 ─────────────────────────────────────────
        Scroll() {
          Column({ space: 0 }) {
            // 标题大输入（24px bold，无边框）
            TextInput({
              placeholder: '输入标题...',
              text: this.title
            })
              .onChange((val) => { this.title = val; })
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#212121')
              .placeholderColor('#BDBDBD')
              .placeholderFont({ size: 24, weight: FontWeight.Bold })
              .backgroundColor(Color.Transparent)
              .borderWidth(0)
              .width('100%')
              .padding({ left: 24, right: 24, top: 20, bottom: 8 })

            Blank().height(16)

            // 正文输入区（17px，无边框，自适应高度）
            TextArea({
              placeholder: '记录今天发生的趣事...',
              text: this.content
            })
              .onChange((val) => { this.content = val; })
              .fontSize(17)
              .lineHeight(27)
              .fontColor('#212121')
              .placeholderColor('#BDBDBD')
              .placeholderFont({ size: 17 })
              .backgroundColor(Color.Transparent)
              .borderWidth(0)
              .width('100%')
              .padding({ left: 24, right: 24 })
              .maxLines(999)

            Blank().height(24)

            // ─── 媒体区 ──────────────────────────────────────────
            if (this.localMediaItems.length > 0) {
              // 已选媒体横向滚动列表
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.localMediaItems, (item: LocalMediaItem, idx: number) => {
                    Stack() {
                      if (item.type === 'photo') {
                        Image(item.uri)
                          .width(90)
                          .height(90)
                          .borderRadius(8)
                          .objectFit(ImageFit.Cover)
                      } else {
                        Column() {
                          SymbolGlyph($r('sys.symbol.video_fill'))
                            .fontSize(30)
                            .fontColor(['#F48FB1'])
                          Text('视频')
                            .fontSize(11)
                            .fontColor('#9E9E9E')
                        }
                        .width(90)
                        .height(90)
                        .borderRadius(8)
                        .backgroundColor('#F5F5F5')
                        .justifyContent(FlexAlign.Center)
                        .alignItems(HorizontalAlign.Center)
                      }
                      // 删除按钮
                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.xmark'))
                          .fontSize(10)
                          .fontColor(['#FFFFFF'])
                      }
                      .width(20)
                      .height(20)
                      .backgroundColor('#80000000')
                      .position({ right: 2, top: 2 })
                      .onClick(() => { this.removeMedia(idx); })
                    }
                  }, (item: LocalMediaItem) => item.uri)
                }
                .padding({ left: 24, right: 24 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .width('100%')
              Blank().height(16)
            }

            // 添加媒体按钮行
            Row({ space: 16 }) {
              // 添加照片
              Button({ type: ButtonType.Normal }) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.photo'))
                    .fontSize(18)
                    .fontColor(['#E91E63'])
                  Text('照片')
                    .fontSize(14)
                    .fontColor('#E91E63')
                }
              }
              .backgroundColor('#FCE4EC')
              .borderRadius(20)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => { this.pickPhotos(); })

              // 添加视频
              Button({ type: ButtonType.Normal }) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.video_fill'))
                    .fontSize(18)
                    .fontColor(['#E91E63'])
                  Text('视频')
                    .fontSize(14)
                    .fontColor('#E91E63')
                }
              }
              .backgroundColor('#FCE4EC')
              .borderRadius(20)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => { this.pickVideos(); })
            }
            .width('100%')
            .padding({ left: 24, right: 24 })

            // 上传进度提示
            if (this.uploadProgress.length > 0) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color('#E91E63')
                Text(this.uploadProgress)
                  .fontSize(13)
                  .fontColor('#E91E63')
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 8 })
            }

            Blank().height(100)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FFFFFF')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')

      // ─── 日期选择器弹窗 ──────────────────────────────────────────
      if (this.showDatePicker) {
        Column() {
          Column({ space: 0 }) {
            Row() {
              Button('取消')
                .backgroundColor(Color.Transparent)
                .fontColor('#9E9E9E')
                .onClick(() => { this.showDatePicker = false; })
              Blank().layoutWeight(1)
              Text('选择日期')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
              Blank().layoutWeight(1)
              Button('确定')
                .backgroundColor(Color.Transparent)
                .fontColor('#E91E63')
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
          .borderRadius({ topLeft: 20, topRight: 20 })
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

  private async pickPhotos(): Promise<void> {
    if (!this.context) return;
    const mediaService = new MediaService(this.context);
    const uris = await mediaService.pickPhotos(9 - this.localMediaItems.length);
    for (const uri of uris) {
      this.localMediaItems = [...this.localMediaItems, { uri, type: 'photo' }];
    }
  }

  private async pickVideos(): Promise<void> {
    if (!this.context) return;
    const mediaService = new MediaService(this.context);
    const uris = await mediaService.pickVideos(1);
    for (const uri of uris) {
      this.localMediaItems = [...this.localMediaItems, { uri, type: 'video' }];
    }
  }

  private removeMedia(index: number): void {
    const updated = [...this.localMediaItems];
    updated.splice(index, 1);
    this.localMediaItems = updated;
  }

  private formatDate(date: Date): string {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  private formatDisplayDate(date: Date): string {
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  }

  private getWeekday(date: Date): string {
    const days = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return days[date.getDay()];
  }

  /** 从 URI 中提取文件扩展名 */
  private extractExtension(uri: string): string {
    const dotIdx = uri.lastIndexOf('.');
    if (dotIdx < 0) return '';
    const ext = uri.slice(dotIdx + 1).toLowerCase().split('?')[0].split('#')[0];
    return ext.length > 0 && ext.length <= 5 ? ext : '';
  }

  private async onSave(): Promise<void> {
    if (this.title.trim().length === 0 && this.content.trim().length === 0
        && this.localMediaItems.length === 0) {
      promptAction.showToast({ message: '请至少输入标题、描述或选择媒体' });
      return;
    }
    if (!this.config || !this.context) {
      promptAction.showToast({ message: '配置未加载，请返回重试' });
      return;
    }
    this.isSavingEntry = true;
    try {
      const dateIso = this.selectedDateStr.length > 0
        ? new Date(this.selectedDateStr).toISOString()
        : new Date().toISOString();
      const ageInMonths = this.config.babyBirthDate
        ? AgeCalculator.calculateAgeInMonths(this.config.babyBirthDate, dateIso)
        : 0;
      const entryId = this.entryToEdit?.id ?? generateUUID();
      const imagePaths: string[] = [...(this.entryToEdit?.imagePaths ?? [])];
      const videoPaths: string[] = [...(this.entryToEdit?.videoPaths ?? [])];
      const imageThumbs: string[] = [...(this.entryToEdit?.imageThumbnails ?? [])];
      const videoThumbs: string[] = [...(this.entryToEdit?.videoThumbnails ?? [])];

      const mediaService = new MediaService(this.context);
      const newItems = this.localMediaItems;

      if (newItems.length > 0) {
        this.uploadProgress = `上传媒体 0 / ${newItems.length}`;
        for (let i = 0; i < newItems.length; i++) {
          const item = newItems[i];
          this.uploadProgress = `上传媒体 ${i + 1} / ${newItems.length}`;
          try {
            if (item.type === 'photo') {
              const res = await mediaService.uploadPhoto(item.uri, this.webdavService);
              imagePaths.push(res.mediaPath);
              imageThumbs.push(res.smallThumbPath || res.mediaPath);
            } else {
              const res = await mediaService.uploadVideo(item.uri, this.webdavService);
              videoPaths.push(res.mediaPath);
              videoThumbs.push('');
            }
          } catch (uploadErr) {
            const ext = item.type === 'photo'
              ? 'jpg'
              : (this.extractExtension(item.uri) || 'mp4');
            const task: UploadTask = {
              id: generateUUID(),
              configId: this.config!.id,
              entryId,
              localUri: item.uri,
              type: item.type,
              targetPath: `media/${Date.now()}_${item.type}.${ext}`,
              status: 'pending',
              errorMessage: String(uploadErr),
              createdAt: new Date().toISOString(),
            };
            await this.uploadQueueService.enqueue(task);
          }
        }
        this.uploadProgress = '';
      }

      const entry = new DiaryEntry(
        entryId, dateIso, this.title.trim(), this.content.trim(),
        imagePaths, videoPaths, imageThumbs, videoThumbs, ageInMonths,
      );
      await this.webdavService.saveDiaryEntry(entry);
      promptAction.showToast({ message: this.entryToEdit ? '记录已更新' : '记录已保存' });
      router.back();
    } catch (e) {
      promptAction.showToast({ message: `保存失败: ${e}` });
    } finally {
      this.isSavingEntry = false;
      this.uploadProgress = '';
    }
  }
}
