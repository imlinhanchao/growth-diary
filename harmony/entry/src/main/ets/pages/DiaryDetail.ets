import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { DiaryEntry, AgeCalculator } from '../model/DiaryEntry';
import { AppConfig } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';
import { MediaService } from '../service/MediaService';

/**
 * 日记详情页面
 * 展示单条日记的完整内容，支持编辑、删除，以及在线浏览已上传的照片
 */
@Entry
@Component
struct DiaryDetail {
  @State entry: DiaryEntry | null = null;
  @State config: AppConfig | null = null;
  @State isLoading: boolean = true;
  @State showDeleteConfirm: boolean = false;
  /** 当前全屏预览的图片本地路径，空字符串表示不显示 */
  @State previewImagePath: string = '';
  /** 各缩略图的本地缓存路径，key = WebDAV 相对路径 */
  @State thumbCache: Record<string, string> = {};
  @State loadingThumbs: boolean = false;

  private entryId: string = '';
  private configId: string = '';
  private webdavService = new WebDAVService();
  private prefsService = PreferencesService.getInstance();
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = getContext(this) as common.UIAbilityContext;
    const params = router.getParams() as Record<string, string>;
    this.entryId = params?.['entryId'] ?? '';
    this.configId = params?.['configId'] ?? '';
    this.loadData();
  }

  onPageShow(): void {
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

          Text('记录详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row({ space: 8 }) {
            Button({ type: ButtonType.Circle }) {
              Text('✏️')
                .fontSize(16)
            }
            .width(36)
            .height(36)
            .backgroundColor('#FFF0F5')
            .onClick(() => { this.onEdit(); })

            Button({ type: ButtonType.Circle }) {
              Text('🗑️')
                .fontSize(16)
            }
            .width(36)
            .height(36)
            .backgroundColor('#FFF0F5')
            .onClick(() => { this.showDeleteConfirm = true; })
          }
        }
        .width('100%')
        .height(60)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FFFFFF')
        .shadow({ radius: 4, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

        // 内容区
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
        } else if (this.entry) {
          Scroll() {
            Column({ space: 0 }) {
              // 年龄标签和日期
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Text(this.entry!.getAgeLabel(this.config?.babyBirthDate))
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#E91E8C')
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  Text(this.formatDate(this.entry!.date))
                    .fontSize(14)
                    .fontColor('#888888')
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 20, bottom: 12 })
              .backgroundColor('#FFFFFF')

              // 标题
              if (this.entry!.title.length > 0) {
                Text(this.entry!.title)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')
                  .width('100%')
                  .padding({ left: 20, right: 20, bottom: 12 })
                  .backgroundColor('#FFFFFF')
              }

              Divider().color('#F0C0D0').width('100%')

              // 描述
              if (this.entry!.description.length > 0) {
                Text(this.entry!.description)
                  .fontSize(16)
                  .fontColor('#444444')
                  .lineHeight(26)
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 16, bottom: 16 })
                  .backgroundColor('#FFFFFF')
              } else {
                Column() {
                  Text('暂无描述内容')
                    .fontSize(14)
                    .fontColor('#CCCCCC')
                    .fontStyle(FontStyle.Italic)
                }
                .width('100%')
                .padding({ left: 20, right: 20, top: 16, bottom: 16 })
                .backgroundColor('#FFFFFF')
              }

              // ─── 照片展示 ─────────────────────────────────────────────
              if (this.entry!.imagePaths.length > 0) {
                Column({ space: 12 }) {
                  Divider().color('#F0C0D0')

                  Row() {
                    Text('📷 照片')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#E91E8C')
                    Blank()
                    if (this.loadingThumbs) {
                      LoadingProgress()
                        .width(16)
                        .height(16)
                        .color('#E91E8C')
                    }
                  }
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 12 })

                  // 3 列图片网格
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.entry!.imageThumbnails.length > 0
                      ? this.entry!.imageThumbnails
                      : this.entry!.imagePaths,
                    (thumbPath: string, idx: number) => {
                      Stack() {
                        if (this.thumbCache[thumbPath]) {
                          Image(this.thumbCache[thumbPath])
                            .width('31%')
                            .aspectRatio(1)
                            .borderRadius(8)
                            .objectFit(ImageFit.Cover)
                            .margin(2)
                        } else {
                          Column() {
                            LoadingProgress()
                              .width(24)
                              .height(24)
                              .color('#E91E8C')
                          }
                          .width('31%')
                          .aspectRatio(1)
                          .borderRadius(8)
                          .backgroundColor('#F5F5F5')
                          .justifyContent(FlexAlign.Center)
                          .margin(2)
                        }
                      }
                      .onClick(() => {
                        const fullPath = this.entry!.imagePaths[idx] ?? thumbPath;
                        this.previewFullImage(fullPath);
                      })
                    }, (p: string) => p)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 12 })
                }
                .backgroundColor('#FFFFFF')
              }

              // ─── 视频展示 ─────────────────────────────────────────────
              if (this.entry!.videoPaths.length > 0) {
                Column({ space: 8 }) {
                  Divider().color('#F0C0D0')

                  Text(`🎬 视频 (${this.entry!.videoPaths.length} 个)`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#E91E8C')
                    .width('100%')
                    .padding({ left: 20, right: 20, top: 12 })

                  ForEach(this.entry!.videoPaths, (videoPath: string, idx: number) => {
                    Row({ space: 12 }) {
                      // 视频缩略图
                      Stack() {
                        if (this.entry!.videoThumbnails[idx] &&
                            this.thumbCache[this.entry!.videoThumbnails[idx]]) {
                          Image(this.thumbCache[this.entry!.videoThumbnails[idx]])
                            .width(80)
                            .height(60)
                            .borderRadius(8)
                            .objectFit(ImageFit.Cover)
                        } else {
                          Column() {
                            Text('🎬')
                              .fontSize(24)
                          }
                          .width(80)
                          .height(60)
                          .borderRadius(8)
                          .backgroundColor('#F0F0F0')
                          .justifyContent(FlexAlign.Center)
                        }
                        // 播放图标覆盖
                        Text('▶')
                          .fontSize(20)
                          .fontColor('#FFFFFF')
                          .backgroundColor('#80000000')
                          .borderRadius(20)
                          .padding(4)
                      }
                      Column({ space: 4 }) {
                        Text(`视频 ${idx + 1}`)
                          .fontSize(14)
                          .fontColor('#333333')
                        Text('存储于 WebDAV 服务器')
                          .fontSize(12)
                          .fontColor('#888888')
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                    }
                    .width('100%')
                    .padding({ left: 20, right: 20, bottom: 8 })
                    .backgroundColor('#FFFFFF')
                  }, (p: string) => p)
                }
                .backgroundColor('#FFFFFF')
              }

              Blank().height(40)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#FFF5F7')
        } else {
          Column() {
            Text('😢 记录未找到')
              .fontSize(16)
              .fontColor('#888888')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')

      // 全屏图片预览
      if (this.previewImagePath.length > 0) {
        Column() {
          Stack() {
            Image(this.previewImagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
            Button('✕')
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor('#80000000')
              .fontColor('#FFFFFF')
              .fontSize(20)
              .position({ right: 16, top: 48 })
              .onClick(() => { this.previewImagePath = ''; })
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .onClick(() => { this.previewImagePath = ''; })
      }

      // 删除确认弹窗
      if (this.showDeleteConfirm) {
        Column() {
          Column({ space: 20 }) {
            Text('确认删除')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
            Text('确定要删除这条记录吗？此操作不可撤销，相关媒体文件也将从服务器删除。')
              .fontSize(14)
              .fontColor('#666666')
              .textAlign(TextAlign.Center)
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor('#F0F0F0')
                .fontColor('#333333')
                .onClick(() => { this.showDeleteConfirm = false; })
              Button('删除')
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor('#FF4444')
                .fontColor('#FFFFFF')
                .onClick(() => { this.onDelete(); })
            }
          }
          .width('80%')
          .padding(24)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#80000000')
      }
    }
    .width('100%')
    .height('100%')
  }

  private formatDate(isoDate: string): string {
    const d = new Date(isoDate);
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    try {
      const cfg = await this.prefsService.loadConfig(this.configId);
      if (!cfg) return;
      this.config = cfg;
      await this.webdavService.initialize(cfg);

      const entries = await this.webdavService.loadAllEntries();
      this.entry = entries.find(e => e.id === this.entryId) ?? null;

      // 加载缩略图
      if (this.entry && this.context) {
        this.loadThumbnails();
      }
    } catch (e) {
      promptAction.showToast({ message: `加载失败: ${e}` });
    } finally {
      this.isLoading = false;
    }
  }

  /** 异步加载所有缩略图到本地缓存 */
  private async loadThumbnails(): Promise<void> {
    if (!this.entry || !this.context) return;
    const mediaService = new MediaService(this.context);
    this.loadingThumbs = true;

    const allThumbs = [
      ...this.entry.imageThumbnails,
      ...this.entry.videoThumbnails.filter(t => t.length > 0),
    ];

    for (const thumbPath of allThumbs) {
      if (thumbPath.length === 0 || this.thumbCache[thumbPath]) continue;
      try {
        const localPath = await mediaService.getCachedMediaPath(thumbPath, this.webdavService);
        if (localPath.length > 0) {
          const updated = { ...this.thumbCache };
          updated[thumbPath] = localPath;
          this.thumbCache = updated;
        }
      } catch (e) {
        console.warn('DiaryDetail loadThumbnail error:', thumbPath, e);
      }
    }
    this.loadingThumbs = false;
  }

  /** 全屏预览完整图片（先从缓存，再从 WebDAV 下载） */
  private async previewFullImage(imagePath: string): Promise<void> {
    if (!this.context) return;
    const mediaService = new MediaService(this.context);
    try {
      let localPath = this.thumbCache[imagePath] ?? '';
      if (!localPath) {
        promptAction.showToast({ message: '加载图片中...' });
        localPath = await mediaService.getCachedMediaPath(imagePath, this.webdavService);
      }
      if (localPath.length > 0) {
        this.previewImagePath = localPath;
      } else {
        promptAction.showToast({ message: '图片加载失败' });
      }
    } catch (e) {
      promptAction.showToast({ message: `图片加载失败: ${e}` });
    }
  }

  private onEdit(): void {
    if (!this.entry || !this.config) return;
    router.pushUrl({
      url: 'pages/DiaryEditor',
      params: {
        configId: this.config.id,
        entryJson: JSON.stringify(this.entry.toJson()),
      }
    });
  }

  private async onDelete(): Promise<void> {
    this.showDeleteConfirm = false;
    if (!this.entry) return;
    try {
      await this.webdavService.deleteEntry(this.entry);
      promptAction.showToast({ message: '记录已删除' });
      router.back();
    } catch (e) {
      promptAction.showToast({ message: `删除失败: ${e}` });
    }
  }
}
