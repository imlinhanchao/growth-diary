import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { DiaryEntry, AgeCalculator } from '../model/DiaryEntry';
import { AppConfig } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';
import { UploadQueueService } from '../service/UploadQueueService';

/** 时间轴分组 */
interface EntryGroup {
  groupKey: number;
  label: string;
  entries: DiaryEntry[];
}

/**
 * 主页（时间轴）
 * 风格与 Flutter 版保持一致：
 * - 粉色渐变 AppBar，白色文字/图标（HarmonyOS Symbol）
 * - 分组分隔线居中（两侧横线 + 粉色徽章）
 * - 平铺卡片（无竖线），日期在底部，媒体计数徽章
 * - 可展开 FAB（写日记 / 添加照片 / 添加视频）
 */
@Entry
@Component
struct Index {
  @State config: AppConfig | null = null;
  @State allConfigs: AppConfig[] = [];
  @State entries: DiaryEntry[] = [];
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State isRefreshing: boolean = false;
  @State showBabySwitcher: boolean = false;
  @State pendingUploadCount: number = 0;
  @State isFabExpanded: boolean = false;

  private prefsService = PreferencesService.getInstance();
  private webdavService = new WebDAVService();
  private uploadQueueService = UploadQueueService.getInstance();

  aboutToAppear(): void {
    this.loadData();
  }

  onPageShow(): void {
    this.loadData();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // ─── 粉色渐变 AppBar ──────────────────────────────────────────
        Row() {
          // 宝宝名称（点击切换宝宝）
          Row({ space: 6 }) {
            Column({ space: 2 }) {
              if (this.config) {
                Text(this.config.babyName)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                Text(this.config.getAgeLabel())
                  .fontSize(12)
                  .fontColor('#FFD6E4')
              } else {
                Text('成长日记')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
              }
            }
            .alignItems(HorizontalAlign.Start)

            if (this.allConfigs.length > 1) {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(14)
                .fontColor(['#FFFFFF'])
            }
          }
          .layoutWeight(1)
          .onClick(() => {
            if (this.allConfigs.length > 1) {
              this.showBabySwitcher = !this.showBabySwitcher;
            }
          })

          // 后台上传进度徽章
          if (this.pendingUploadCount > 0) {
            Row({ space: 4 }) {
              LoadingProgress()
                .width(12)
                .height(12)
                .color('#FFFFFF')
              Text(`${this.pendingUploadCount}`)
                .fontSize(11)
                .fontColor('#FFFFFF')
            }
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(12)
            .backgroundColor('#30FFFFFF')
            .margin({ right: 8 })
            .onClick(() => { this.retryPendingUploads(); })
          }

          // 设置按钮
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(20)
              .fontColor(['#FFFFFF'])
          }
          .width(40)
          .height(40)
          .backgroundColor('#20FFFFFF')
          .onClick(() => { router.pushUrl({ url: 'pages/Settings' }); })
        }
        .width('100%')
        .height(60)
        .padding({ left: 16, right: 12 })
        .linearGradient({
          angle: 135,
          colors: [['#F06292', 0.0], ['#E91E63', 1.0]]
        })
        .shadow({ radius: 4, color: '#30E91E63', offsetX: 0, offsetY: 2 })

        // 多宝宝切换下拉
        if (this.showBabySwitcher && this.allConfigs.length > 1) {
          Column() {
            ForEach(this.allConfigs, (cfg: AppConfig) => {
              Row({ space: 12 }) {
                Text(cfg.babyName.length > 0 ? cfg.babyName.charAt(0) : '宝')
                  .fontSize(16)
                  .fontColor('#FFFFFF')
                  .width(36)
                  .height(36)
                  .borderRadius(18)
                  .backgroundColor(cfg.id === this.config?.id ? '#E91E63' : '#DDDDDD')
                  .textAlign(TextAlign.Center)
                Column({ space: 2 }) {
                  Text(cfg.babyName)
                    .fontSize(15)
                    .fontColor('#333333')
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
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => { this.switchBaby(cfg); })
            }, (cfg: AppConfig) => cfg.id)
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 12, color: '#1A000000', offsetX: 0, offsetY: 4 })
          .zIndex(10)
        }

        // ─── 内容区 ──────────────────────────────────────────────────
        if (this.isLoading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color('#E91E63')
            Text('加载中...')
              .fontSize(14)
              .fontColor('#9E9E9E')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.errorMessage.length > 0) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(64)
              .fontColor(['#EF9A9A'])
            Text('加载失败')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#EF5350')
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor('#9E9E9E')
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
            Button('重试')
              .onClick(() => { this.loadData(); })
              .backgroundColor('#E91E63')
              .fontColor('#FFFFFF')
              .borderRadius(20)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.entries.length === 0) {
          // 空状态 - 匹配 Flutter 空白样式
          Column({ space: 20 }) {
            Column() {
              SymbolGlyph($r('sys.symbol.book'))
                .fontSize(64)
                .fontColor(['#F48FB1'])
            }
            .width(128)
            .height(128)
            .borderRadius(64)
            .backgroundColor('#FCE4EC')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            Text('开启成长之旅')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#616161')
            Text('记录宝宝的每一个珍贵瞬间\n照片、视频或日记')
              .fontSize(15)
              .fontColor('#9E9E9E')
              .textAlign(TextAlign.Center)
              .lineHeight(24)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 时间轴列表
          Refresh({ refreshing: $$this.isRefreshing }) {
            List({ space: 0 }) {
              // 当前月龄标签（置顶）
              if (this.config?.babyBirthDate) {
                ListItem() {
                  this.buildCurrentAgeSeparator()
                }
              }

              ForEach(this.getGroupedEntries(), (group: EntryGroup) => {
                // Flutter 风格分组分隔符
                ListItem() {
                  this.buildGroupSeparator(group.label)
                }

                ForEach(group.entries, (entry: DiaryEntry) => {
                  ListItem() {
                    this.buildEntryCard(entry)
                  }
                }, (entry: DiaryEntry) => entry.id)
              }, (group: EntryGroup) => group.groupKey.toString())
            }
            .width('100%')
            .padding({ bottom: 100 })
            .divider({ strokeWidth: 0 })
          }
          .onRefreshing(() => { this.refreshData(); })
          .layoutWeight(1)
          .backgroundColor('#FFFFFF')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')
      .onClick(() => {
        if (this.showBabySwitcher) this.showBabySwitcher = false;
      })

      // ─── 展开 FAB（点击时向上弹出子按钮）────────────────────────
      Column({ space: 12 }) {
        // 写日记子按钮
        if (this.isFabExpanded) {
          Row({ space: 10 }) {
            Text('写日记')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#C2185B')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .shadow({ radius: 4, color: '#15000000', offsetX: 0, offsetY: 2 })
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(20)
                .fontColor(['#FFFFFF'])
            }
            .width(44)
            .height(44)
            .backgroundColor('#E91E63')
            .shadow({ radius: 6, color: '#40E91E63', offsetX: 0, offsetY: 3 })
            .onClick(() => {
              this.isFabExpanded = false;
              this.onAddDiary();
            })
          }
          .justifyContent(FlexAlign.End)

          // 添加照片子按钮
          Row({ space: 10 }) {
            Text('添加照片')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#C2185B')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .shadow({ radius: 4, color: '#15000000', offsetX: 0, offsetY: 2 })
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.photo'))
                .fontSize(20)
                .fontColor(['#FFFFFF'])
            }
            .width(44)
            .height(44)
            .backgroundColor('#EC407A')
            .shadow({ radius: 6, color: '#40EC407A', offsetX: 0, offsetY: 3 })
            .onClick(() => {
              this.isFabExpanded = false;
              this.onAddPhotoEntry();
            })
          }
          .justifyContent(FlexAlign.End)

          // 添加视频子按钮
          Row({ space: 10 }) {
            Text('添加视频')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#C2185B')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .shadow({ radius: 4, color: '#15000000', offsetX: 0, offsetY: 2 })
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.video_fill'))
                .fontSize(20)
                .fontColor(['#FFFFFF'])
            }
            .width(44)
            .height(44)
            .backgroundColor('#F06292')
            .shadow({ radius: 6, color: '#40F06292', offsetX: 0, offsetY: 3 })
            .onClick(() => {
              this.isFabExpanded = false;
              this.onAddVideoEntry();
            })
          }
          .justifyContent(FlexAlign.End)
        }

        // 主 FAB（加号 / 关闭）
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.isFabExpanded
            ? $r('sys.symbol.xmark')
            : $r('sys.symbol.plus'))
            .fontSize(26)
            .fontColor(['#FFFFFF'])
        }
        .width(56)
        .height(56)
        .backgroundColor('#E91E63')
        .shadow({ radius: 8, color: '#50E91E63', offsetX: 0, offsetY: 4 })
        .onClick(() => {
          if (!this.config) {
            promptAction.showToast({ message: '请先完成初始设置' });
            return;
          }
          this.isFabExpanded = !this.isFabExpanded;
        })
      }
      .alignItems(HorizontalAlign.End)
      .padding({ right: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
  }

  // ─── Builder：当前月龄顶部标签 ──────────────────────────────────
  @Builder
  buildCurrentAgeSeparator() {
    Row() {
      Divider()
        .strokeWidth(1)
        .color('#F48FB1')
        .layoutWeight(1)
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.birthday_cake_fill'))
          .fontSize(16)
          .fontColor(['#D81B60'])
        if (this.config?.babyBirthDate) {
          Text(`宝宝${AgeCalculator.formatDetailedAgeLabel(
            new Date().toISOString(),
            this.config?.babyBirthDate ?? ''
          )}啦`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#AD1457')
        }
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(14)
          .fontColor(['#D81B60'])
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FCE4EC')
      .borderRadius(20)
      Divider()
        .strokeWidth(1)
        .color('#F48FB1')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  // ─── Builder：分组分隔符（Flutter GroupSeparator 风格）────────────
  @Builder
  buildGroupSeparator(label: string) {
    Row() {
      Column()
        .layoutWeight(1)
        .height(1)
        .backgroundColor('#F48FB1')
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#C2185B')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor('#FCE4EC')
        .borderRadius(16)
        .margin({ left: 8, right: 8 })
      Column()
        .layoutWeight(1)
        .height(1)
        .backgroundColor('#F48FB1')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  // ─── Builder：日记条目卡片（Flutter TimelineItem 风格）────────────
  @Builder
  buildEntryCard(entry: DiaryEntry) {
    Column({ space: 0 }) {
      Column({ space: 8 }) {
        // 标题
        if (entry.title.length > 0) {
          Text(entry.title)
            .fontSize(16)
            .fontWeight(FontWeight.W600)
            .fontColor('#000000')
            .lineHeight(21)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        // 描述
        if (entry.description.length > 0) {
          Text(entry.description)
            .fontSize(15)
            .fontColor('#212121')
            .lineHeight(21)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        // 媒体缩略图格子（简化版，仅显示计数徽章）
        if (entry.imagePaths.length > 0 || entry.videoPaths.length > 0) {
          Row({ space: 6 }) {
            if (entry.imagePaths.length > 0) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.photo'))
                  .fontSize(13)
                  .fontColor(['#757575'])
                Text(`${entry.imagePaths.length}`)
                  .fontSize(12)
                  .fontColor('#757575')
              }
            }
            if (entry.videoPaths.length > 0) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.video_fill'))
                  .fontSize(13)
                  .fontColor(['#757575'])
                Text(`${entry.videoPaths.length}`)
                  .fontSize(12)
                  .fontColor('#757575')
              }
            }
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
        }

        // 日期在底部（Flutter 风格）
        Text(this.formatDate(entry.date))
          .fontSize(12)
          .fontColor('#9E9E9E')
          .width('100%')
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Divider()
        .strokeWidth(0.5)
        .color('#F5F5F5')
        .margin({ left: 16, right: 16 })
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      router.pushUrl({
        url: 'pages/DiaryDetail',
        params: { entryId: entry.id, configId: this.config?.id ?? '' }
      });
    })
  }

  // ─── 按月龄分组 ──────────────────────────────────────────────────
  private getGroupedEntries(): EntryGroup[] {
    const groups: Map<number, EntryGroup> = new Map();
    for (const entry of this.entries) {
      const key = this.config?.babyBirthDate
        ? AgeCalculator.getGroupKey(entry.date, this.config.babyBirthDate)
        : entry.ageInMonths;
      if (!groups.has(key)) {
        const label = this.config?.babyBirthDate
          ? AgeCalculator.formatSimplifiedAgeLabel(entry.date, this.config.babyBirthDate)
          : AgeCalculator.formatAgeLabel(entry.ageInMonths);
        groups.set(key, { groupKey: key, label, entries: [] });
      }
      groups.get(key)!.entries.push(entry);
    }
    return Array.from(groups.values()).sort((a, b) => b.groupKey - a.groupKey);
  }

  private formatDate(isoDate: string): string {
    const d = new Date(isoDate);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.showBabySwitcher = false;
    try {
      const configs = await this.prefsService.loadAllConfigs();
      this.allConfigs = Object.values(configs);
      const cfg = await this.prefsService.loadConfig();
      if (!cfg || !cfg.isConfigured) {
        router.replaceUrl({ url: 'pages/Setup' });
        return;
      }
      this.config = cfg;
      await this.webdavService.initialize(cfg);
      this.entries = await this.webdavService.loadAllEntries();
      this.pendingUploadCount = await this.uploadQueueService.getActiveCount(cfg.id);
    } catch (e) {
      this.errorMessage = `加载失败: ${e}`;
    } finally {
      this.isLoading = false;
    }
  }

  private async refreshData(): Promise<void> {
    try {
      if (this.config) {
        this.entries = await this.webdavService.loadAllEntries();
        this.pendingUploadCount = await this.uploadQueueService.getActiveCount(this.config.id);
      }
    } catch (e) {
      promptAction.showToast({ message: `刷新失败: ${e}` });
    } finally {
      this.isRefreshing = false;
    }
  }

  private async switchBaby(cfg: AppConfig): Promise<void> {
    this.showBabySwitcher = false;
    await this.prefsService.setCurrentConfigId(cfg.id);
    this.config = cfg;
    this.isLoading = true;
    try {
      await this.webdavService.initialize(cfg);
      this.entries = await this.webdavService.loadAllEntries();
      this.pendingUploadCount = await this.uploadQueueService.getActiveCount(cfg.id);
    } catch (e) {
      this.errorMessage = `切换失败: ${e}`;
    } finally {
      this.isLoading = false;
    }
  }

  private onAddDiary(): void {
    if (!this.config) return;
    router.pushUrl({
      url: 'pages/DiaryEditor',
      params: { configId: this.config.id }
    });
  }

  private onAddPhotoEntry(): void {
    if (!this.config) return;
    router.pushUrl({
      url: 'pages/DiaryEditor',
      params: { configId: this.config.id, autoPickPhoto: 'true' }
    });
  }

  private onAddVideoEntry(): void {
    if (!this.config) return;
    router.pushUrl({
      url: 'pages/DiaryEditor',
      params: { configId: this.config.id, autoPickVideo: 'true' }
    });
  }

  private async retryPendingUploads(): Promise<void> {
    if (!this.config) return;
    await this.uploadQueueService.clearDoneTasks(this.config.id);
    this.pendingUploadCount = await this.uploadQueueService.getActiveCount(this.config.id);
    promptAction.showToast({ message: '已清理已完成的上传任务' });
  }
}
