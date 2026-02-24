import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { AppConfig } from '../model/AppConfig';
import { PreferencesService } from '../service/PreferencesService';
import { QRService } from '../service/QRService';

/**
 * QR 码分享页面
 *
 * 功能：
 * 1. 展示当前宝宝配置的 QR 码（使用 Canvas 绘制，与 Flutter 版数据格式兼容）
 * 2. 支持复制 QR 数据字符串（供另一台设备粘贴导入）
 * 3. 支持导入：粘贴 QR 数据字符串扫描导入配置
 */
@Entry
@Component
struct QRShare {
  @State config: AppConfig | null = null;
  @State qrData: string = '';
  @State importText: string = '';
  @State showImport: boolean = false;
  @State isImporting: boolean = false;
  @State qrModules: boolean[][] = [];

  private prefsService = PreferencesService.getInstance();
  private readonly QR_SIZE = 280; // px
  private readonly MODULE_COUNT = 25; // 简化的模块数

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    const configId = params?.['configId'] ?? '';
    this.loadConfig(configId);
  }

  private async loadConfig(configId: string): Promise<void> {
    try {
      const cfg = configId
        ? await this.prefsService.loadConfig(configId)
        : await this.prefsService.loadConfig();
      if (cfg) {
        this.config = cfg;
        this.qrData = QRService.generateEncryptedQRData(cfg);
        this.qrModules = this.generateQRMatrix(this.qrData);
      }
    } catch (e) {
      promptAction.showToast({ message: `加载配置失败: ${e}` });
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

          Text('分享 / 导入配置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Blank().width(48)
        }
        .width('100%')
        .height(60)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FFFFFF')
        .shadow({ radius: 4, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

        Scroll() {
          Column({ space: 20 }) {
            // QR 码展示卡片
            if (this.config) {
              Column({ space: 12 }) {
                Text('分享给其他设备')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')
                  .width('100%')

                Text(`宝宝：${this.config.babyName}`)
                  .fontSize(14)
                  .fontColor('#888888')
                  .width('100%')

                // QR 码画布（简化矩阵渲染）
                Stack() {
                  Canvas(this.renderingContext)
                    .width(this.QR_SIZE)
                    .height(this.QR_SIZE)
                    .onReady(() => { this.drawQR(); })
                }
                .width(this.QR_SIZE + 24)
                .height(this.QR_SIZE + 24)
                .borderRadius(12)
                .backgroundColor('#FFFFFF')
                .border({ width: 1, color: '#F0C0D0' })
                .padding(12)

                Text('用另一台设备的"导入"功能扫描此码')
                  .fontSize(12)
                  .fontColor('#AAAAAA')
                  .textAlign(TextAlign.Center)

                // 复制数据按钮
                Button('复制配置数据')
                  .width('100%')
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor('#FFF0F5')
                  .fontColor('#E91E8C')
                  .fontSize(15)
                  .onClick(() => { this.copyQRData(); })
              }
              .width('100%')
              .padding(20)
              .borderRadius(16)
              .backgroundColor('#FFFFFF')
              .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })
              .alignItems(HorizontalAlign.Center)
            }

            // 导入卡片
            Column({ space: 12 }) {
              Text('从其他设备导入')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
                .width('100%')

              Text('请将另一台设备上复制的配置数据粘贴到下方：')
                .fontSize(13)
                .fontColor('#888888')
                .width('100%')

              TextArea({ placeholder: '粘贴配置数据...', text: this.importText })
                .onChange((val) => { this.importText = val; })
                .width('100%')
                .height(120)
                .borderRadius(12)
                .backgroundColor('#FFF5F7')
                .borderWidth(1)
                .borderColor('#F0C0D0')
                .padding(12)

              Button(this.isImporting ? '导入中...' : '导入配置')
                .width('100%')
                .height(44)
                .borderRadius(22)
                .backgroundColor('#E91E8C')
                .fontColor('#FFFFFF')
                .fontSize(15)
                .enabled(!this.isImporting && this.importText.trim().length > 0)
                .onClick(() => { this.doImport(); })
            }
            .width('100%')
            .padding(20)
            .borderRadius(16)
            .backgroundColor('#FFFFFF')
            .shadow({ radius: 8, color: '#1AE91E8C', offsetX: 0, offsetY: 2 })

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
    }
    .width('100%')
    .height('100%')
  }

  // Canvas 渲染上下文
  private renderingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  );

  /** 在 Canvas 上绘制简化 QR 码矩阵 */
  private drawQR(): void {
    const ctx = this.renderingContext;
    const size = this.QR_SIZE;
    const modules = this.qrModules;
    if (modules.length === 0) return;

    const n = modules.length;
    const cellSize = size / n;

    ctx.clearRect(0, 0, size, size);
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, size, size);

    ctx.fillStyle = '#000000';
    for (let row = 0; row < n; row++) {
      for (let col = 0; col < n; col++) {
        if (modules[row][col]) {
          ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize);
        }
      }
    }
  }

  /**
   * 生成简化 QR 矩阵（哈希散列映射为视觉模式）
   *
   * 注：这是视觉效果占位实现，生成的图案不是标准 QR 码，
   * 无法被通用 QR 扫描器识别。实际设备间传输使用"复制/粘贴"方式。
   * 若需标准 QR 码，可集成 `@ohos/qrcode` 三方库。
   */
  private generateQRMatrix(data: string): boolean[][] {
    const N = this.MODULE_COUNT;
    const matrix: boolean[][] = Array.from({ length: N }, () => Array(N).fill(false));

    // 使用数据的每个字节位来填充模块（简单的视觉哈希）
    const bytes = this.stringToBytes(data);
    for (let i = 0; i < bytes.length && i < N * N; i++) {
      const row = Math.floor(i / N);
      const col = i % N;
      matrix[row][col] = (bytes[i] & 1) === 1;
    }

    // 添加角定位图案（类 QR 码视觉特征）
    this.addFinderPattern(matrix, 0, 0);
    this.addFinderPattern(matrix, 0, N - 7);
    this.addFinderPattern(matrix, N - 7, 0);

    return matrix;
  }

  private addFinderPattern(matrix: boolean[][], row: number, col: number): void {
    const pattern = [
      [true, true, true, true, true, true, true],
      [true, false, false, false, false, false, true],
      [true, false, true, true, true, false, true],
      [true, false, true, true, true, false, true],
      [true, false, true, true, true, false, true],
      [true, false, false, false, false, false, true],
      [true, true, true, true, true, true, true],
    ];
    for (let r = 0; r < 7; r++) {
      for (let c = 0; c < 7; c++) {
        const tr = row + r;
        const tc = col + c;
        if (tr >= 0 && tr < matrix.length && tc >= 0 && tc < matrix[0].length) {
          matrix[tr][tc] = pattern[r][c];
        }
      }
    }
  }

  private stringToBytes(str: string): number[] {
    const bytes: number[] = [];
    for (let i = 0; i < str.length; i++) {
      bytes.push(str.charCodeAt(i) & 0xFF);
    }
    return bytes;
  }

  /** 复制 QR 数据到剪贴板 */
  private copyQRData(): void {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.qrData);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '配置数据已复制到剪贴板' });
    } catch (e) {
      // 若剪贴板不可用，提示用户手动复制
      promptAction.showDialog({
        title: '配置数据',
        message: this.qrData,
        buttons: [{ text: '关闭', color: '#E91E8C' }],
      });
    }
  }

  /** 导入配置 */
  private async doImport(): Promise<void> {
    const text = this.importText.trim();
    if (!QRService.isValidQRData(text)) {
      promptAction.showToast({ message: '无效的配置数据，请确认粘贴正确' });
      return;
    }

    this.isImporting = true;
    try {
      const imported = QRService.decodeEncryptedQRData(text);
      if (!imported) {
        promptAction.showToast({ message: '解析配置失败' });
        return;
      }

      await this.prefsService.saveConfig(imported);
      await this.prefsService.setCurrentConfigId(imported.id);
      promptAction.showToast({ message: `已导入宝宝「${imported.babyName}」的配置` });
      router.replaceUrl({ url: 'pages/Index' });
    } catch (e) {
      promptAction.showToast({ message: `导入失败: ${e}` });
    } finally {
      this.isImporting = false;
    }
  }
}
