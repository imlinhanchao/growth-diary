import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { DiaryEntry, AgeCalculator } from '../model/DiaryEntry';
import { AppConfig } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';

/**
 * 日记详情页面
 * 展示单条日记的完整内容，支持编辑和删除
 */
@Entry
@Component
struct DiaryDetail {
  @State entry: DiaryEntry | null = null;
  @State config: AppConfig | null = null;
  @State isLoading: boolean = true;
  @State showDeleteConfirm: boolean = false;

  private entryId: string = '';
  private configId: string = '';
  private webdavService = new WebDAVService();
  private prefsService = PreferencesService.getInstance();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.entryId = params?.['entryId'] ?? '';
    this.configId = params?.['configId'] ?? '';
    this.loadData();
  }

  onPageShow(): void {
    // 从编辑页返回时刷新
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

          // 操作菜单
          Row({ space: 8 }) {
            // 编辑
            Button({ type: ButtonType.Circle }) {
              Text('✏️')
                .fontSize(16)
            }
            .width(36)
            .height(36)
            .backgroundColor('#FFF0F5')
            .onClick(() => { this.onEdit(); })

            // 删除
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

              // 分隔线
              Divider()
                .color('#F0C0D0')
                .width('100%')

              // 描述内容
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

              // 媒体信息
              if (this.entry!.imagePaths.length > 0 || this.entry!.videoPaths.length > 0) {
                Column({ space: 8 }) {
                  Divider()
                    .color('#F0C0D0')

                  Text('媒体文件')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#E91E8C')
                    .width('100%')
                    .padding({ left: 20, right: 20, top: 12 })

                  if (this.entry!.imagePaths.length > 0) {
                    Row({ space: 6 }) {
                      Text('📷')
                        .fontSize(16)
                      Text(`照片 ${this.entry!.imagePaths.length} 张`)
                        .fontSize(14)
                        .fontColor('#666666')
                    }
                    .width('100%')
                    .padding({ left: 20, right: 20 })
                  }

                  if (this.entry!.videoPaths.length > 0) {
                    Row({ space: 6 }) {
                      Text('🎬')
                        .fontSize(16)
                      Text(`视频 ${this.entry!.videoPaths.length} 个`)
                        .fontSize(14)
                        .fontColor('#666666')
                    }
                    .width('100%')
                    .padding({ left: 20, right: 20 })
                  }

                  Text('媒体文件存储在 WebDAV 服务器上，请通过文件管理器访问')
                    .fontSize(12)
                    .fontColor('#AAAAAA')
                    .width('100%')
                    .padding({ left: 20, right: 20, bottom: 12 })
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

      // 删除确认弹窗
      if (this.showDeleteConfirm) {
        Column() {
          Column({ space: 20 }) {
            Text('确认删除')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
            Text('确定要删除这条记录吗？此操作不可撤销。')
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

      // 从 WebDAV 加载指定条目
      const entries = await this.webdavService.loadAllEntries();
      this.entry = entries.find(e => e.id === this.entryId) ?? null;
    } catch (e) {
      promptAction.showToast({ message: `加载失败: ${e}` });
    } finally {
      this.isLoading = false;
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
