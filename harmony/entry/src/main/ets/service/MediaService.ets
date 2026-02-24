import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import common from '@ohos.app.ability.common';
import { WebDAVService } from './WebDAVService';

/** 上传结果 */
export interface MediaUploadResult {
  /** 原始文件 WebDAV 相对路径，如 media/xxx.jpg */
  mediaPath: string;
  /** 中号缩略图 WebDAV 相对路径（仅图片），如 thumbnails/xxx_medium.jpg */
  mediumThumbPath: string;
  /** 小号缩略图 WebDAV 相对路径（仅图片），如 thumbnails/xxx_small.jpg */
  smallThumbPath: string;
  /** 本地文件 URI（用于 Image 组件直接显示） */
  localUri: string;
}

/** 媒体类型 */
export type MediaType = 'photo' | 'video';

/**
 * 媒体服务
 * 封装相册选择、缩略图生成、WebDAV 上传等操作
 * 对应 Flutter 版本的 MediaService + part of WebDAVService
 */
export class MediaService {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * 打开相册选择器，让用户选取照片
   * @param maxCount 最多可选数量，默认 9
   * @returns 选取的文件 URI 列表
   */
  async pickPhotos(maxCount: number = 9): Promise<string[]> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: maxCount,
      });
      return result.photoUris ?? [];
    } catch (e) {
      console.error('MediaService pickPhotos error:', e);
      return [];
    }
  }

  /**
   * 打开相册选择器，让用户选取视频
   * @param maxCount 最多可选数量，默认 1
   * @returns 选取的文件 URI 列表
   */
  async pickVideos(maxCount: number = 1): Promise<string[]> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.VIDEO_TYPE,
        maxSelectNumber: maxCount,
      });
      return result.photoUris ?? [];
    } catch (e) {
      console.error('MediaService pickVideos error:', e);
      return [];
    }
  }

  /**
   * 上传图片到 WebDAV，同时生成缩略图
   * @param localUri  本地文件 URI（来自 picker）
   * @param webdav    已初始化的 WebDAVService
   * @returns MediaUploadResult
   */
  async uploadPhoto(localUri: string, webdav: WebDAVService): Promise<MediaUploadResult> {
    const timestamp = Date.now();
    const baseName = `${timestamp}_photo`;
    const fileName = `${baseName}.jpg`;

    // 读取原始文件字节
    const rawData = await this.readFileAsArrayBuffer(localUri);

    // 上传原图
    await webdav.uploadData(`media/${fileName}`, rawData);

    // 生成缩略图（中号 768px、小号 400px）
    const mediumFileName = `${baseName}_medium.jpg`;
    const smallFileName = `${baseName}_small.jpg`;
    try {
      const mediumData = await this.resizeImage(rawData, 768, 85);
      const smallData = await this.resizeImage(rawData, 400, 80);
      await webdav.uploadData(`thumbnails/${mediumFileName}`, mediumData);
      await webdav.uploadData(`thumbnails/${smallFileName}`, smallData);
    } catch (thumbErr) {
      console.warn('MediaService thumbnail generation failed:', thumbErr);
      // 缩略图生成失败时使用原图路径
      return {
        mediaPath: `media/${fileName}`,
        mediumThumbPath: `media/${fileName}`,
        smallThumbPath: `media/${fileName}`,
        localUri,
      };
    }

    return {
      mediaPath: `media/${fileName}`,
      mediumThumbPath: `thumbnails/${mediumFileName}`,
      smallThumbPath: `thumbnails/${smallFileName}`,
      localUri,
    };
  }

  /**
   * 上传视频到 WebDAV（不生成缩略图，直接上传原文件）
   * @param localUri  本地文件 URI
   * @param webdav    已初始化的 WebDAVService
   * @returns MediaUploadResult
   */
  async uploadVideo(localUri: string, webdav: WebDAVService): Promise<MediaUploadResult> {
    const timestamp = Date.now();
    // 尝试从 URI 获取扩展名，默认 mp4
    const ext = this.getExtension(localUri) || 'mp4';
    const fileName = `${timestamp}_video.${ext}`;

    const rawData = await this.readFileAsArrayBuffer(localUri);
    await webdav.uploadData(`media/${fileName}`, rawData);

    return {
      mediaPath: `media/${fileName}`,
      mediumThumbPath: '',
      smallThumbPath: '',
      localUri,
    };
  }

  /**
   * 将 WebDAV 路径的媒体文件下载并缓存到本地，返回本地缓存路径
   */
  async getCachedMediaPath(
    webdavPath: string,
    webdav: WebDAVService,
  ): Promise<string> {
    const cacheDir = this.context.cacheDir;
    // 用路径中的文件名作为缓存文件名
    const safeKey = webdavPath.replace(/[^a-zA-Z0-9_.\-]/g, '_');
    const cachePath = `${cacheDir}/${safeKey}`;

    // 如果缓存已存在则直接返回
    if (await this.fileExists(cachePath)) {
      return cachePath;
    }

    // 从 WebDAV 下载
    const data = await webdav.downloadFile(webdavPath);
    if (!data) {
      return '';
    }

    // 写入缓存文件
    try {
      const file = fs.openSync(cachePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, data);
      fs.closeSync(file);
      return cachePath;
    } catch (e) {
      console.error('MediaService write cache error:', e);
      return '';
    }
  }

  // ─── 私有工具方法 ─────────────────────────────────────────────────────────

  private async readFileAsArrayBuffer(uri: string): Promise<ArrayBuffer> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      return buf;
    } finally {
      fs.closeSync(file);
    }
  }

  private async resizeImage(
    rawData: ArrayBuffer,
    targetWidth: number,
    quality: number,
  ): Promise<ArrayBuffer> {
    // 使用 @ohos.multimedia.image 解码 → 缩放 → 编码
    const imageSource = image.createImageSource(rawData);
    const info = await imageSource.getImageInfo();
    const origWidth = info.size?.width ?? 0;
    const origHeight = info.size?.height ?? 0;

    if (origWidth <= 0 || origHeight <= 0) {
      imageSource.release();
      throw new Error('Invalid image dimensions');
    }

    const scale = targetWidth / origWidth;
    const targetHeight = Math.max(1, Math.round(origHeight * scale));

    const pixelMap = await imageSource.createPixelMap({
      desiredSize: { width: targetWidth, height: targetHeight },
    });
    imageSource.release();

    const imagePacker = image.createImagePacker();
    const packed = await imagePacker.packing(pixelMap, {
      format: 'image/jpeg',
      quality,
    });
    pixelMap.release();
    imagePacker.release();

    return packed;
  }

  private getExtension(uri: string): string {
    const dotIdx = uri.lastIndexOf('.');
    if (dotIdx < 0) return '';
    const ext = uri.slice(dotIdx + 1).toLowerCase().split('?')[0];
    return ext.length > 0 && ext.length < 6 ? ext : '';
  }

  private async fileExists(path: string): Promise<boolean> {
    try {
      fs.accessSync(path);
      return true;
    } catch {
      return false;
    }
  }
}
