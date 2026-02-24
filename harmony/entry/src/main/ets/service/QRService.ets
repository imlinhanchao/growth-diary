import { AppConfig, generateUUID } from '../model/AppConfig';

/** QR 数据版本 */
const QR_VERSION = '1.1';
/** XOR 加密密钥（与 Flutter 版保持一致） */
const ENCRYPTION_KEY = 'growth_diary_qr_key_2024';
/** 预计算的密钥字节（避免每次 XOR 时重复编码） */
const ENCRYPTION_KEY_BYTES: number[] = (() => {
  const bytes: number[] = [];
  for (let i = 0; i < ENCRYPTION_KEY.length; i++) {
    const code = ENCRYPTION_KEY.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push((code >> 6) | 0xC0, (code & 0x3F) | 0x80);
    } else {
      bytes.push((code >> 12) | 0xE0, ((code >> 6) & 0x3F) | 0x80, (code & 0x3F) | 0x80);
    }
  }
  return bytes;
})();

/**
 * QR 码服务
 * 实现与 Flutter 版完全兼容的 XOR 加密/解密逻辑，
 * 使 HarmonyOS 版生成的 QR 码可被 Flutter 版扫描导入，反之亦然。
 */
export class QRService {
  /**
   * 将 AppConfig 序列化并 XOR + Base64 加密，生成 QR 数据字符串
   */
  static generateEncryptedQRData(config: AppConfig): string {
    const payload: Record<string, Object> = {
      id: config.id,
      babyName: config.babyName,
      birthDate: config.babyBirthDate,
      conceptionDate: config.babyConceptionDate,
      webdavUrl: config.webdavUrl,
      username: config.username,
      password: config.password,
      videoCompressionThreshold: config.videoCompressionThreshold,
      webdavMirrors: config.webdavMirrors,
      version: QR_VERSION,
      timestamp: new Date().toISOString(),
    };

    const jsonStr = JSON.stringify(payload);
    const encrypted = QRService.xorBytes(QRService.textToBytes(jsonStr), ENCRYPTION_KEY);
    return QRService.base64Encode(encrypted);
  }

  /**
   * 解码并解密 QR 数据字符串，返回 AppConfig；解码失败返回 null
   */
  static decodeEncryptedQRData(qrData: string): AppConfig | null {
    try {
      const encrypted = QRService.base64Decode(qrData);
      const decrypted = QRService.xorBytes(encrypted, ENCRYPTION_KEY);
      const jsonStr = QRService.bytesToText(decrypted);
      const data = JSON.parse(jsonStr) as Record<string, Object>;

      const version = data['version'] as string;
      if (version !== '1.0' && version !== '1.1') {
        console.warn('QRService: unsupported version', version);
        return null;
      }

      const mirrors = (data['webdavMirrors'] as string[]) ?? [];
      const webdavUrl = (data['webdavUrl'] as string) ?? '';

      return new AppConfig(
        (data['id'] as string) ?? generateUUID(),
        webdavUrl,
        (data['username'] as string) ?? '',
        (data['password'] as string) ?? '',
        (data['babyName'] as string) ?? '',
        (data['birthDate'] as string) ?? '',
        (data['conceptionDate'] as string) ?? '',
        (data['videoCompressionThreshold'] as number) ?? 10,
        mirrors.length === 0 && webdavUrl.length > 0 ? [webdavUrl] : mirrors,
      );
    } catch (e) {
      console.error('QRService decodeEncryptedQRData error:', e);
      return null;
    }
  }

  /** 校验 QR 数据是否合法 */
  static isValidQRData(qrData: string): boolean {
    try {
      const config = QRService.decodeEncryptedQRData(qrData);
      return config !== null && config.babyName.length > 0;
    } catch {
      return false;
    }
  }

  // ─── 工具方法 ──────────────────────────────────────────────────────────────

  /** UTF-8 字符串 → 字节数组 */
  private static textToBytes(str: string): number[] {
    const bytes: number[] = [];
    for (let i = 0; i < str.length; i++) {
      const code = str.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push((code >> 6) | 0xC0, (code & 0x3F) | 0x80);
      } else {
        bytes.push(
          (code >> 12) | 0xE0,
          ((code >> 6) & 0x3F) | 0x80,
          (code & 0x3F) | 0x80,
        );
      }
    }
    return bytes;
  }

  /** 字节数组 → UTF-8 字符串 */
  private static bytesToText(bytes: number[]): string {
    let result = '';
    let i = 0;
    while (i < bytes.length) {
      const b = bytes[i];
      if ((b & 0x80) === 0) {
        result += String.fromCharCode(b);
        i++;
      } else if ((b & 0xE0) === 0xC0) {
        result += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
        i += 2;
      } else {
        result += String.fromCharCode(
          ((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F),
        );
        i += 3;
      }
    }
    return result;
  }

  /** XOR 加密/解密（对称），使用预计算的密钥字节 */
  private static xorBytes(data: number[], _key: string): number[] {
    const keyBytes = ENCRYPTION_KEY_BYTES;
    return data.map((b, i) => b ^ keyBytes[i % keyBytes.length]);
  }

  /** 字节数组 → Base64 字符串 */
  static base64Encode(bytes: number[]): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let i = 0;
    while (i < bytes.length) {
      const b0 = bytes[i++];
      const b1 = i < bytes.length ? bytes[i++] : -1;
      const b2 = i < bytes.length ? bytes[i++] : -1;
      result += chars[b0 >> 2];
      result += chars[((b0 & 3) << 4) | (b1 >= 0 ? (b1 >> 4) : 0)];
      result += b1 >= 0 ? chars[((b1 & 15) << 2) | (b2 >= 0 ? (b2 >> 6) : 0)] : '=';
      result += b2 >= 0 ? chars[b2 & 63] : '=';
    }
    return result;
  }

  /** Base64 字符串 → 字节数组 */
  static base64Decode(b64: string): number[] {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const lookup: Record<string, number> = {};
    for (let i = 0; i < chars.length; i++) lookup[chars[i]] = i;
    const clean = b64.replace(/=/g, '');
    const result: number[] = [];
    for (let i = 0; i < clean.length; i += 4) {
      const c0 = lookup[clean[i]] ?? 0;
      const c1 = lookup[clean[i + 1]] ?? 0;
      const c2 = lookup[clean[i + 2]] ?? 0;
      const c3 = lookup[clean[i + 3]] ?? 0;
      result.push((c0 << 2) | (c1 >> 4));
      if (i + 2 < clean.length) result.push(((c1 & 15) << 4) | (c2 >> 2));
      if (i + 3 < clean.length) result.push(((c2 & 3) << 6) | c3);
    }
    return result;
  }
}
