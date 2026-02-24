import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { DiaryEntry, AgeCalculator } from '../model/DiaryEntry';
import { AppConfig } from '../model/AppConfig';
import { generateUUID } from '../model/AppConfig';
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
 * 支持：新建/编辑日记条目（文字 + 日期）、选取并上传照片/视频
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
    this.initData(configId, entryJson);
  }

  private async initData(configId: string, entryJson: string): Promise<void> {
    try {
      const cfg = await this.prefsService.loadConfig(configId);
      if (!cfg) return;
      this.config = cfg;
      await this.webdavService.initialize(cfg);

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

          Button(this.isSavingEntry ? '...' : '保存')
            .height(36)
            .borderRadius(18)
            .backgroundColor('#E91E8C')
            .fontColor('#FFFFFF')
            .fontSize(15)
            .enabled(!this.isSavingEntry)
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
                .height(160)
                .borderRadius(12)
                .backgroundColor('#FFFFFF')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .padding(12)
            }
            .width('100%')

            // 媒体区
            Column({ space: 10 }) {
              Row() {
                Text('照片 / 视频')
                  .fontSize(14)
                  .fontColor('#666666')
                  .layoutWeight(1)
                if (this.localMediaItems.length > 0) {
                  Text(`已选 ${this.localMediaItems.length} 项`)
                    .fontSize(12)
                    .fontColor('#E91E8C')
                }
              }
              .width('100%')

              // 已选媒体缩略图列表
              if (this.localMediaItems.length > 0) {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(this.localMediaItems, (item: LocalMediaItem, idx: number) => {
                      Stack() {
                        if (item.type === 'photo') {
                          Image(item.uri)
                            .width(80)
                            .height(80)
                            .borderRadius(8)
                            .objectFit(ImageFit.Cover)
                        } else {
                          Column() {
                            Text('🎬')
                              .fontSize(28)
                            Text('视频')
                              .fontSize(11)
                              .fontColor('#888888')
                          }
                          .width(80)
                          .height(80)
                          .borderRadius(8)
                          .backgroundColor('#F0F0F0')
                          .justifyContent(FlexAlign.Center)
                          .alignItems(HorizontalAlign.Center)
                        }
                        Button('✕')
                          .width(20)
                          .height(20)
                          .borderRadius(10)
                          .backgroundColor('#80000000')
                          .fontColor('#FFFFFF')
                          .fontSize(11)
                          .position({ right: 2, top: 2 })
                          .onClick(() => { this.removeMedia(idx); })
                      }
                    }, (item: LocalMediaItem) => item.uri)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .width('100%')
              }

              Row({ space: 10 }) {
                Button() {
                  Row({ space: 6 }) {
                    Text('📷')
                      .fontSize(16)
                    Text('添加照片')
                      .fontSize(14)
                      .fontColor('#E91E8C')
                  }
                }
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor('#FFF0F5')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .onClick(() => { this.pickPhotos(); })

                Button() {
                  Row({ space: 6 }) {
                    Text('🎬')
                      .fontSize(16)
                    Text('添加视频')
                      .fontSize(14)
                      .fontColor('#E91E8C')
                  }
                }
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor('#FFF0F5')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .onClick(() => { this.pickVideos(); })
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(12)
            .backgroundColor('#FFFFFF')
            .borderWidth(1)
            .borderColor('#F0C0D0')

            // 上传进度提示
            if (this.uploadProgress.length > 0) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color('#E91E8C')
                Text(this.uploadProgress)
                  .fontSize(13)
                  .fontColor('#E91E8C')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor('#FFF0F5')
            }

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

  /** 从 URI 中提取文件扩展名（小写），无法识别时返回空字符串 */
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
            console.error(`DiaryEditor upload item ${i} failed:`, uploadErr);
            // 从 URI 提取扩展名，确保与原始文件格式一致
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
        entryId,
        dateIso,
        this.title.trim(),
        this.content.trim(),
        imagePaths,
        videoPaths,
        imageThumbs,
        videoThumbs,
        ageInMonths,
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
