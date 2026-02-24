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
 * 风格与 Flutter EntryDetailScreen 保持一致：
 * - 白色 AppBar，SymbolGlyph 图标（返回/日历/编辑/删除）
 * - 大号日期（56px 细体）+ 年月/星期 + 年龄胶囊
 * - 标题（22px bold）→ 描述（16px 行高1.8）→ 照片节（图片网格）→ 视频节
 */
@Entry
@Component
struct DiaryDetail {
  @State entry: DiaryEntry | null = null;
  @State config: AppConfig | null = null;
  @State isLoading: boolean = true;
  @State showDeleteConfirm: boolean = false;
  @State previewImagePath: string = '';
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
        // ─── 白色 AppBar ─────────────────────────────────────────────
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

          Blank().layoutWeight(1)

          // 修改日期
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(20)
              .fontColor(['#212121'])
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)

          // 编辑内容
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(20)
              .fontColor(['#212121'])
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.onEdit(); })

          // 删除
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(20)
              .fontColor(['#F44336'])
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.showDeleteConfirm = true; })

          Blank().width(8)
        }
        .width('100%')
        .height(56)
        .padding({ left: 4, right: 4 })
        .backgroundColor('#FFFFFF')
        .borderWidth({ bottom: 0 })

        // ─── 内容区 ───────────────────────────────────────────────────
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color('#E91E63')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.entry) {
          Scroll() {
            Column({ space: 0 }) {
              // ─── 日期 + 年龄标头（Flutter 大数字风格）───────────────
              Row() {
                // 大号日期数字
                Column({ space: 0 }) {
                  Text(`${new Date(this.entry!.date).getDate()}`)
                    .fontSize(56)
                    .fontWeight(FontWeight.W300)
                    .fontColor('#212121')
                    .lineHeight(56)
                    .letterSpacing(-2)
                }
                Blank().width(12)
                // 年月 + 星期
                Column({ space: 2 }) {
                  Text(`${new Date(this.entry!.date).getFullYear()}年${new Date(this.entry!.date).getMonth() + 1}月`)
                    .fontSize(14)
                    .fontWeight(FontWeight.W600)
                    .fontColor('#757575')
                  Text(this.getWeekday(new Date(this.entry!.date)))
                    .fontSize(12)
                    .fontWeight(FontWeight.W500)
                    .fontColor('#BDBDBD')
                }
                .alignItems(HorizontalAlign.Start)
                .justifyContent(FlexAlign.End)
                .margin({ bottom: 8 })

                Blank().layoutWeight(1)

                // 年龄胶囊
                Text(this.entry!.getAgeLabel(this.config?.babyBirthDate))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#EC407A')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor('#FCE4EC')
                  .borderRadius(20)
                  .margin({ bottom: 8 })
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 12, bottom: 0 })
              .alignItems(VerticalAlign.Bottom)

              Blank().height(32)

              // 标题
              if (this.entry!.title.length > 0) {
                Text(this.entry!.title)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#212121')
                  .lineHeight(29)
                  .letterSpacing(0.5)
                  .width('100%')
                  .padding({ left: 24, right: 24 })
                Blank().height(16)
              }

              // 描述
              if (this.entry!.description.length > 0) {
                Text(this.entry!.description)
                  .fontSize(16)
                  .fontColor('#212121')
                  .lineHeight(29)
                  .width('100%')
                  .padding({ left: 24, right: 24 })
                Blank().height(32)
              } else if (this.entry!.title.length === 0) {
                Text('没有文字记录')
                  .fontSize(15)
                  .fontColor('#BDBDBD')
                  .padding({ left: 24, right: 24 })
                Blank().height(32)
              }

              // ─── 照片区 ──────────────────────────────────────────
              if (this.entry!.imagePaths.length > 0) {
                this.buildSectionHeader('照片', this.entry!.imagePaths.length)
                Blank().height(16)
                this.buildImageGrid()
                Blank().height(32)
              }

              // ─── 视频区 ──────────────────────────────────────────
              if (this.entry!.videoPaths.length > 0) {
                this.buildSectionHeader('视频', this.entry!.videoPaths.length)
                Blank().height(16)
                this.buildVideoGrid()
                Blank().height(32)
              }

              Blank().height(40)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#FFFFFF')

        } else {
          Column() {
            Text('记录未找到')
              .fontSize(16)
              .fontColor('#9E9E9E')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')

      // ─── 全屏图片预览 ─────────────────────────────────────────────
      if (this.previewImagePath.length > 0) {
        Column() {
          Stack() {
            Image(this.previewImagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                .fontSize(28)
                .fontColor(['#FFFFFF'])
            }
            .width(44)
            .height(44)
            .backgroundColor('#60000000')
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

      // ─── 删除确认对话框 ──────────────────────────────────────────
      if (this.showDeleteConfirm) {
        Column() {
          Column({ space: 20 }) {
            Text('确认删除')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#212121')
            Text('确定要删除这条记录吗？此操作不可撤销，相关媒体文件也将从服务器删除。')
              .fontSize(14)
              .fontColor('#757575')
              .textAlign(TextAlign.Center)
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor('#EEEEEE')
                .fontColor('#424242')
                .onClick(() => { this.showDeleteConfirm = false; })
              Button('删除')
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor('#F44336')
                .fontColor('#FFFFFF')
                .onClick(() => { this.onDelete(); })
            }
          }
          .width('85%')
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

  // ─── Builder：区域标头 ─────────────────────────────────────────
  @Builder
  buildSectionHeader(title: string, count: number) {
    Row({ space: 8 }) {
      // SymbolGlyph icon determined by title since $r() cannot be dynamic
      if (title === '照片') {
        SymbolGlyph($r('sys.symbol.photo'))
          .fontSize(18)
          .fontColor(['#F48FB1'])
      } else {
        SymbolGlyph($r('sys.symbol.video_fill'))
          .fontSize(18)
          .fontColor(['#F48FB1'])
      }
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#212121')
      Text(`${count}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#757575')
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .backgroundColor('#F5F5F5')
        .borderRadius(10)
    }
    .width('100%')
    .padding({ left: 24 })
  }

  // ─── Builder：照片网格（匹配 Flutter 逻辑）────────────────────
  @Builder
  buildImageGrid() {
    if (!this.entry) return;
    const thumbs = this.entry!.imageThumbnails.length > 0
      ? this.entry!.imageThumbnails
      : this.entry!.imagePaths;
    const count = thumbs.length;

    if (count === 1) {
      // 单张 - 全宽展示
      Stack() {
        if (this.thumbCache[thumbs[0]]) {
          Image(this.thumbCache[thumbs[0]])
            .width('100%')
            .height(240)
            .objectFit(ImageFit.Cover)
            .borderRadius(16)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.photo'))
              .fontSize(40)
              .fontColor(['#BDBDBD'])
          }
          .width('100%')
          .height(240)
          .backgroundColor('#F5F5F5')
          .justifyContent(FlexAlign.Center)
          .borderRadius(16)
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .onClick(() => { this.previewFullImage(this.entry!.imagePaths[0]); })
    } else {
      // 网格展示（2列或3列，与Flutter逻辑一致）
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(thumbs, (thumbPath: string, idx: number) => {
          Stack() {
            if (this.thumbCache[thumbPath]) {
              Image(this.thumbCache[thumbPath])
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .borderRadius(10)
            } else {
              Column() {
                SymbolGlyph($r('sys.symbol.photo'))
                  .fontSize(24)
                  .fontColor(['#BDBDBD'])
              }
              .width('100%')
              .height('100%')
              .backgroundColor('#F5F5F5')
              .justifyContent(FlexAlign.Center)
              .borderRadius(10)
            }
          }
          .width(count === 2 || count === 4 ? '48%' : '31%')
          .aspectRatio(1)
          .margin({ right: 4, bottom: 4 })
          .onClick(() => { this.previewFullImage(this.entry!.imagePaths[idx]); })
        }, (p: string) => p)
      }
      .padding({ left: 24, right: 24 })
    }
  }

  // ─── Builder：视频网格（2列 16:10 比例）──────────────────────
  @Builder
  buildVideoGrid() {
    if (!this.entry) return;
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.entry!.videoPaths, (videoPath: string, idx: number) => {
        Stack() {
          if (this.entry!.videoThumbnails[idx] &&
              this.thumbCache[this.entry!.videoThumbnails[idx]]) {
            Image(this.thumbCache[this.entry!.videoThumbnails[idx]])
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(10)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.video_fill'))
                .fontSize(32)
                .fontColor(['#F48FB1'])
            }
            .width('100%')
            .height('100%')
            .backgroundColor('#F5F5F5')
            .justifyContent(FlexAlign.Center)
            .borderRadius(10)
          }
          // 播放按钮覆盖
          Column() {
            Column() {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(22)
                .fontColor(['#E91E63'])
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor('#CCFFFFFF')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width('48%')
        .aspectRatio(1.6)
        .margin({ right: 4, bottom: 4 })
      }, (p: string) => p)
    }
    .padding({ left: 24, right: 24 })
  }

  private getWeekday(date: Date): string {
    const days = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return days[date.getDay()];
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
      if (this.entry && this.context) {
        this.loadThumbnails();
      }
    } catch (e) {
      promptAction.showToast({ message: `加载失败: ${e}` });
    } finally {
      this.isLoading = false;
    }
  }

  private async loadThumbnails(): Promise<void> {
    if (!this.entry || !this.context) return;
    const mediaService = new MediaService(this.context);
    this.loadingThumbs = true;
    const allThumbs = [
      ...this.entry.imageThumbnails,
      ...this.entry.videoThumbnails.filter(t => t.length > 0),
    ];
    for (const thumbPath of allThumbs) {
      if (!thumbPath || this.thumbCache[thumbPath]) continue;
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

  private async previewFullImage(imagePath: string): Promise<void> {
    if (!this.context) return;
    const mediaService = new MediaService(this.context);
    try {
      let localPath = this.thumbCache[imagePath] ?? '';
      if (!localPath) {
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
      params: { configId: this.config.id, entryJson: JSON.stringify(this.entry.toJson()) }
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
