import http from '@ohos.net.http';
import { AppConfig } from '../model/AppConfig';
import { DiaryEntry } from '../model/DiaryEntry';

/**
 * WebDAV 客户端服务
 * 对应 Flutter 版本的 WebDAVService
 *
 * 数据目录结构（与 Flutter 版保持一致）：
 *   growth_diary/<config-id>/
 *   ├── config.json
 *   ├── entries/<entry-id>.json
 *   ├── media/<filename>
 *   └── thumbnails/<filename>
 */
export class WebDAVService {
  private config: AppConfig | null = null;
  private baseUrl: string = '';
  private authHeader: string = '';

  /** 是否已初始化 */
  get isInitialized(): boolean {
    return this.config !== null && this.baseUrl.length > 0;
  }

  /** 初始化 WebDAV 连接 */
  async initialize(config: AppConfig): Promise<void> {
    this.config = config;

    // 优先使用第一个镜像地址
    const url = config.webdavMirrors.length > 0 ? config.webdavMirrors[0] : config.webdavUrl;
    this.baseUrl = url.endsWith('/') ? url.slice(0, -1) : url;

    // 构造 Basic Auth 头
    const credentials = `${config.username}:${config.password}`;
    const encoded = this.base64Encode(credentials);
    this.authHeader = `Basic ${encoded}`;

    if (this.baseUrl.length > 0 && config.username.length > 0) {
      // 确保基础目录存在
      await this.mkdirSafe(this.getBasePath());
      await this.mkdirSafe(this.getEntriesPath());
      await this.mkdirSafe(`${this.getBasePath()}/media`);
      await this.mkdirSafe(`${this.getBasePath()}/thumbnails`);
    }
  }

  // ─── 路径辅助 ─────────────────────────────────────────────────────────────

  private getBasePath(): string {
    return `growth_diary/${this.config!.id}`;
  }

  private getConfigPath(): string {
    return `${this.getBasePath()}/config.json`;
  }

  private getEntriesPath(): string {
    return `${this.getBasePath()}/entries`;
  }

  private getMediaPath(fileName: string): string {
    return `${this.getBasePath()}/media/${fileName}`;
  }

  private getThumbnailsPath(fileName: string): string {
    return `${this.getBasePath()}/thumbnails/${fileName}`;
  }

  private fullUrl(path: string): string {
    return `${this.baseUrl}/${path}`;
  }

  // ─── 配置 CRUD ────────────────────────────────────────────────────────────

  /** 保存应用配置到 WebDAV */
  async saveConfig(config: AppConfig): Promise<void> {
    if (!this.isInitialized) return;
    const body = JSON.stringify(config.toJson());
    await this.put(this.getConfigPath(), body, 'application/json');
  }

  /** 从 WebDAV 加载应用配置 */
  async loadConfig(): Promise<AppConfig | null> {
    if (!this.isInitialized) return null;
    try {
      const body = await this.get(this.getConfigPath());
      if (body) {
        return AppConfig.fromJson(JSON.parse(body) as Record<string, Object>);
      }
    } catch (e) {
      console.error('WebDAVService loadConfig error:', e);
    }
    return null;
  }

  // ─── 日记条目 CRUD ─────────────────────────────────────────────────────────

  /** 保存单条日记条目 */
  async saveDiaryEntry(entry: DiaryEntry): Promise<void> {
    if (!this.isInitialized) return;
    const body = JSON.stringify(entry.toJson());
    await this.put(`${this.getEntriesPath()}/${entry.id}.json`, body, 'application/json');
  }

  /** 加载所有日记条目 */
  async loadAllEntries(): Promise<DiaryEntry[]> {
    if (!this.isInitialized) return [];
    try {
      const fileNames = await this.listDirectory(this.getEntriesPath());
      const jsonFiles = fileNames.filter(f => f.endsWith('.json'));

      const entries: DiaryEntry[] = [];
      for (const fileName of jsonFiles) {
        try {
          const body = await this.get(`${this.getEntriesPath()}/${fileName}`);
          if (body) {
            entries.push(DiaryEntry.fromJson(JSON.parse(body) as Record<string, Object>));
          }
        } catch (e) {
          console.error(`WebDAVService loadEntry ${fileName} error:`, e);
        }
      }

      // 按日期倒序排列
      entries.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
      return entries;
    } catch (e) {
      console.error('WebDAVService loadAllEntries error:', e);
      return [];
    }
  }

  /** 分页加载日记条目 */
  async loadEntriesPage(offset: number, limit: number): Promise<DiaryEntry[]> {
    const all = await this.loadAllEntries();
    return all.slice(offset, offset + limit);
  }

  /** 删除日记条目及其媒体文件 */
  async deleteEntry(entry: DiaryEntry): Promise<void> {
    if (!this.isInitialized) return;

    // 删除关联媒体文件
    const mediaPaths = [
      ...entry.imagePaths,
      ...entry.videoPaths,
      ...entry.imageThumbnails,
      ...entry.videoThumbnails,
    ];
    for (const path of mediaPaths) {
      try {
        const fullPath = path.startsWith('growth_diary/') ? path : `${this.getBasePath()}/${path}`;
        await this.delete(fullPath);
      } catch (e) {
        // 忽略单个文件删除失败，继续处理
      }
    }

    // 删除条目 JSON
    await this.delete(`${this.getEntriesPath()}/${entry.id}.json`);
  }

  // ─── 媒体文件 ─────────────────────────────────────────────────────────────

  /** 从 WebDAV 下载文件 */
  async downloadFile(path: string): Promise<ArrayBuffer | null> {
    if (!this.isInitialized) return null;
    try {
      const fullPath = path.startsWith('growth_diary/') ? path : `${this.getBasePath()}/${path}`;
      return await this.getBinary(fullPath);
    } catch (e) {
      console.error('WebDAVService downloadFile error:', e);
      return null;
    }
  }

  // ─── HTTP 底层方法 ─────────────────────────────────────────────────────────

  /** HTTP GET，返回文本 */
  private async get(path: string): Promise<string> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(this.fullUrl(path), {
        method: http.RequestMethod.GET,
        header: { 'Authorization': this.authHeader },
        connectTimeout: 10000,
        readTimeout: 10000,
      });
      if (response.responseCode >= 200 && response.responseCode < 300) {
        return response.result as string;
      }
      throw new Error(`HTTP ${response.responseCode}`);
    } finally {
      httpRequest.destroy();
    }
  }

  /** HTTP GET，返回二进制 */
  private async getBinary(path: string): Promise<ArrayBuffer | null> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(this.fullUrl(path), {
        method: http.RequestMethod.GET,
        header: { 'Authorization': this.authHeader },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 30000,
      });
      if (response.responseCode >= 200 && response.responseCode < 300) {
        return response.result as ArrayBuffer;
      }
      return null;
    } finally {
      httpRequest.destroy();
    }
  }

  /** HTTP PUT，上传文本 */
  private async put(path: string, body: string, contentType: string): Promise<void> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(this.fullUrl(path), {
        method: http.RequestMethod.PUT,
        header: {
          'Authorization': this.authHeader,
          'Content-Type': contentType,
        },
        extraData: body,
        connectTimeout: 30000,
        readTimeout: 30000,
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP PUT ${response.responseCode}`);
      }
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * WebDAV MKCOL，创建目录
   *
   * HarmonyOS `@ohos.net.http` 的 `RequestMethod` 枚举不包含 MKCOL，
   * 因此使用 POST + `X-HTTP-Method-Override: MKCOL` 作为替代方案。
   * 兼容性说明：
   *   - Nextcloud 4.x+ 及 ownCloud 支持此 header 隧道
   *   - 不支持此 header 的服务端将返回 4xx，此处会被静默忽略
   *   - 对于不兼容的服务端，请升级服务端或通过其他方式预先创建目录结构
   */
  private async mkdirSafe(path: string): Promise<void> {
    const httpRequest = http.createHttp();
    try {
      await httpRequest.request(this.fullUrl(path), {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': this.authHeader,
          'X-HTTP-Method-Override': 'MKCOL',
          'Content-Type': 'application/xml',
        },
        connectTimeout: 10000,
        readTimeout: 10000,
      });
    } catch (_e) {
      // 忽略错误，目录可能已存在
    } finally {
      httpRequest.destroy();
    }
  }

  /** HTTP DELETE */
  private async delete(path: string): Promise<void> {
    const httpRequest = http.createHttp();
    try {
      await httpRequest.request(this.fullUrl(path), {
        method: http.RequestMethod.DELETE,
        header: { 'Authorization': this.authHeader },
        connectTimeout: 10000,
        readTimeout: 10000,
      });
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * WebDAV PROPFIND，列出目录内容
   *
   * HarmonyOS `@ohos.net.http` 的 `RequestMethod` 枚举不包含 PROPFIND，
   * 因此使用 POST + `X-HTTP-Method-Override: PROPFIND` 作为替代方案。
   * 兼容性说明：
   *   - Nextcloud 4.x+ 及 ownCloud 支持此 header 隧道
   *   - 不支持此 header 的服务端将返回空结果
   *   - Apache mod_dav、IIS WebDAV 等可能不支持，需在服务端额外配置
   * 解析 XML multistatus 响应，提取文件名。
   */
  private async listDirectory(path: string): Promise<string[]> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(this.fullUrl(path), {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': this.authHeader,
          'X-HTTP-Method-Override': 'PROPFIND',
          'Depth': '1',
          'Content-Type': 'application/xml',
        },
        extraData: '<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop><getlastmodified/><getcontentlength/><resourcetype/></prop></propfind>',
        connectTimeout: 30000,
        readTimeout: 30000,
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        return [];
      }

      // 从 XML 响应中解析文件名
      return this.parseFileNames(response.result as string, path);
    } catch (e) {
      console.error('WebDAVService listDirectory error:', e);
      return [];
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 从 WebDAV PROPFIND 响应中解析文件名
   *
   * 使用简单的正则表达式解析 XML，提取 <href> 标签中路径的最后一段文件名。
   * 注意：此实现为轻量解析方案，适用于标准 Nextcloud / ownCloud 格式的响应。
   * 如果服务端返回非标准命名空间（如 <D:href> 代替 <d:href>），正则已做大小写不敏感处理。
   * 已知局限：不支持 XML CDATA 节点；XML 响应中若包含特殊编码字符可能解析不完整。
   */
  private parseFileNames(xml: string, basePath: string): string[] {
    const names: string[] = [];
    const hrefRegex = /<[Dd]:[Hh][Rr][Ee][Ff]>([^<]+)<\/[Dd]:[Hh][Rr][Ee][Ff]>/g;
    let match: RegExpExecArray | null;

    // 提取目录本身的最后一段路径，用于过滤目录自身条目
    const basePathOriginal = basePath.split('/').pop() ?? '';
    const basePathEncoded = encodeURIComponent(basePathOriginal);

    while ((match = hrefRegex.exec(xml)) !== null) {
      const href = decodeURIComponent(match[1]).replace(/\/$/, '');
      const fileName = href.split('/').pop() ?? '';
      // 排除目录本身（同时检查 URI 编码形式）
      if (fileName && fileName !== basePathOriginal && !fileName.endsWith(basePathEncoded)) {
        names.push(fileName);
      }
    }
    return names;
  }

  // ─── 工具 ─────────────────────────────────────────────────────────────────

  /** Base64 编码（用于 Basic Auth） */
  private base64Encode(str: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let i = 0;
    const bytes: number[] = [];
    for (let j = 0; j < str.length; j++) {
      const code = str.charCodeAt(j);
      if (code < 128) {
        bytes.push(code);
      } else if (code < 2048) {
        bytes.push((code >> 6) | 192, (code & 63) | 128);
      } else {
        bytes.push((code >> 12) | 224, ((code >> 6) & 63) | 128, (code & 63) | 128);
      }
    }
    while (i < bytes.length) {
      const b0 = bytes[i++] ?? 0;
      const b1 = i < bytes.length ? bytes[i++] : -1;
      const b2 = i < bytes.length ? bytes[i++] : -1;
      result += chars[b0 >> 2];
      result += chars[((b0 & 3) << 4) | (b1 >= 0 ? (b1 >> 4) : 0)];
      result += b1 >= 0 ? chars[((b1 & 15) << 2) | (b2 >= 0 ? (b2 >> 6) : 0)] : '=';
      result += b2 >= 0 ? chars[b2 & 63] : '=';
    }
    return result;
  }
}
