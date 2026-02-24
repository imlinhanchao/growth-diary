import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { DiaryEntry, AgeCalculator } from '../model/DiaryEntry';
import { AppConfig } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { WebDAVService } from '../service/WebDAVService';

/** 时间轴分组 */
interface EntryGroup {
  groupKey: number;
  label: string;
  entries: DiaryEntry[];
}

/**
 * 主页（时间轴）
 * 按月龄分组展示所有日记条目，支持下拉刷新
 */
@Entry
@Component
struct Index {
  @State config: AppConfig | null = null;
  @State entries: DiaryEntry[] = [];
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State isRefreshing: boolean = false;

  private prefsService = PreferencesService.getInstance();
  private webdavService = new WebDAVService();

  aboutToAppear(): void {
    this.loadData();
  }

  onPageShow(): void {
    // 每次页面显示时刷新（从编辑页返回时）
    this.loadData();
  }

  build() {
    Column() {
      // 顶部应用栏
      Row() {
        if (this.config) {
          Column({ space: 2 }) {
            Text('成长日记')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#E91E8C')
            Text(this.config.getAgeLabel())
              .fontSize(12)
              .fontColor('#888888')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        } else {
          Text('成长日记')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#E91E8C')
            .layoutWeight(1)
        }

        // 设置按钮
        Button({ type: ButtonType.Circle }) {
          Text('⚙')
            .fontSize(20)
            .fontColor('#E91E8C')
        }
        .width(40)
        .height(40)
        .backgroundColor('#FFF0F5')
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' });
        })
      }
      .width('100%')
      .height(60)
      .padding({ left: 20, right: 16 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 4, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

      // 内容区
      if (this.isLoading) {
        // 加载中
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#E91E8C')
          Text('加载中...')
            .fontSize(14)
            .fontColor('#888888')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.errorMessage.length > 0) {
        // 错误状态
        Column({ space: 16 }) {
          Text('😢')
            .fontSize(48)
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#888888')
            .textAlign(TextAlign.Center)
          Button('重试')
            .onClick(() => { this.loadData(); })
            .backgroundColor('#E91E8C')
            .fontColor('#FFFFFF')
            .borderRadius(20)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.entries.length === 0) {
        // 空状态
        Column({ space: 16 }) {
          Text('🌱')
            .fontSize(64)
          Text('还没有日记记录')
            .fontSize(18)
            .fontColor('#888888')
          Text('点击右下角的 + 按钮添加第一篇日记吧！')
            .fontSize(13)
            .fontColor('#AAAAAA')
            .textAlign(TextAlign.Center)
            .padding({ left: 40, right: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // 时间轴列表
        Refresh({ refreshing: $$this.isRefreshing }) {
          List({ space: 0 }) {
            ForEach(this.getGroupedEntries(), (group: EntryGroup) => {
              // 分组标题
              ListItem() {
                Row() {
                  // 时间轴圆点
                  Column() {
                    Circle({ width: 12, height: 12 })
                      .fill('#E91E8C')
                    Column()
                      .width(2)
                      .height(32)
                      .backgroundColor('#F0C0D0')
                  }
                  .alignItems(HorizontalAlign.Center)
                  .margin({ right: 12 })

                  Text(group.label)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#E91E8C')
                    .backgroundColor('#FFF0F5')
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 4 })
              }

              // 分组内的条目
              ForEach(group.entries, (entry: DiaryEntry) => {
                ListItem() {
                  this.buildEntryCard(entry)
                }
              }, (entry: DiaryEntry) => entry.id)
            }, (group: EntryGroup) => group.groupKey.toString())
          }
          .width('100%')
          .divider({ strokeWidth: 0 })
          .padding({ bottom: 100 })
        }
        .onRefreshing(() => {
          this.refreshData();
        })
        .layoutWeight(1)
      }

      // 浮动添加按钮
      Stack() {
        Blank()
        Button('+')
          .width(56)
          .height(56)
          .borderRadius(28)
          .backgroundColor('#E91E8C')
          .fontColor('#FFFFFF')
          .fontSize(28)
          .shadow({ radius: 8, color: '#40E91E8C', offsetX: 0, offsetY: 4 })
          .position({ right: 20, bottom: 20 })
          .onClick(() => {
            if (!this.config) {
              promptAction.showToast({ message: '请先完成初始设置' });
              return;
            }
            router.pushUrl({
              url: 'pages/DiaryEditor',
              params: { configId: this.config.id }
            });
          })
      }
      .width('100%')
      .height(0)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF5F7')
  }

  @Builder
  buildEntryCard(entry: DiaryEntry) {
    Row() {
      // 时间轴线
      Column() {
        Column()
          .width(2)
          .height(16)
          .backgroundColor('#F0C0D0')
        Circle({ width: 8, height: 8 })
          .fill('#F0C0D0')
        Column()
          .width(2)
          .layoutWeight(1)
          .backgroundColor('#F0C0D0')
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 21, right: 12 })

      // 卡片内容
      Column({ space: 8 }) {
        // 日期
        Text(this.formatDate(entry.date))
          .fontSize(12)
          .fontColor('#AAAAAA')

        // 标题
        if (entry.title.length > 0) {
          Text(entry.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        // 描述
        if (entry.description.length > 0) {
          Text(entry.description)
            .fontSize(14)
            .fontColor('#666666')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        // 媒体数量提示
        if (entry.imagePaths.length > 0 || entry.videoPaths.length > 0) {
          Row({ space: 8 }) {
            if (entry.imagePaths.length > 0) {
              Row({ space: 4 }) {
                Text('📷')
                  .fontSize(12)
                Text(`${entry.imagePaths.length} 张`)
                  .fontSize(12)
                  .fontColor('#888888')
              }
            }
            if (entry.videoPaths.length > 0) {
              Row({ space: 4 }) {
                Text('🎬')
                  .fontSize(12)
                Text(`${entry.videoPaths.length} 个`)
                  .fontSize(12)
                  .fontColor('#888888')
              }
            }
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ top: 12, bottom: 12, right: 16 })
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 2 })
      .margin({ bottom: 8 })
      .onClick(() => {
        router.pushUrl({
          url: 'pages/DiaryDetail',
          params: { entryId: entry.id, configId: this.config?.id ?? '' }
        });
      })
    }
    .width('100%')
    .padding({ left: 0, right: 16 })
  }

  /** 按月龄分组条目 */
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

    // 按分组键倒序排列（最新的在前）
    return Array.from(groups.values()).sort((a, b) => b.groupKey - a.groupKey);
  }

  private formatDate(isoDate: string): string {
    const d = new Date(isoDate);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      // 加载配置
      const cfg = await this.prefsService.loadConfig();
      if (!cfg || !cfg.isConfigured) {
        // 跳转到初始设置页
        router.replaceUrl({ url: 'pages/Setup' });
        return;
      }
      this.config = cfg;

      // 初始化 WebDAV
      await this.webdavService.initialize(cfg);

      // 加载条目
      this.entries = await this.webdavService.loadAllEntries();
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
      }
    } catch (e) {
      promptAction.showToast({ message: `刷新失败: ${e}` });
    } finally {
      this.isRefreshing = false;
    }
  }
}
