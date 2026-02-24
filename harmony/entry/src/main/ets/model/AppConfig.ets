/**
 * 应用配置数据模型
 * 对应 Flutter 版本的 AppConfig
 */
export class AppConfig {
  id: string;
  webdavUrl: string;
  username: string;
  password: string;
  babyName: string;
  babyBirthDate: string; // ISO 8601 格式，空字符串表示未设置
  babyConceptionDate: string; // ISO 8601 格式，空字符串表示未设置
  videoCompressionThreshold: number; // 视频压缩阈值，单位 MB，0 表示不压缩
  webdavMirrors: string[]; // WebDAV 镜像地址列表

  constructor(
    id: string,
    webdavUrl: string,
    username: string,
    password: string,
    babyName: string,
    babyBirthDate: string,
    babyConceptionDate: string,
    videoCompressionThreshold: number,
    webdavMirrors: string[]
  ) {
    this.id = id;
    this.webdavUrl = webdavUrl;
    this.username = username;
    this.password = password;
    this.babyName = babyName;
    this.babyBirthDate = babyBirthDate;
    this.babyConceptionDate = babyConceptionDate;
    this.videoCompressionThreshold = videoCompressionThreshold;
    this.webdavMirrors = webdavMirrors;
  }

  /** 检查配置是否完整 */
  get isConfigured(): boolean {
    return this.webdavUrl.length > 0 && this.username.length > 0 && this.babyName.length > 0;
  }

  /** 获取年龄标签 */
  getAgeLabel(): string {
    if (!this.babyBirthDate) {
      return this.babyName;
    }
    const now = new Date();
    const birth = new Date(this.babyBirthDate);
    const diffMs = now.getTime() - birth.getTime();
    const diffDays = diffMs / (1000 * 60 * 60 * 24);
    const ageInMonths = Math.ceil(diffDays / 30.44);
    if (ageInMonths < 0) {
      const weeks = Math.floor(-diffDays / 7);
      return `${this.babyName} (孕${weeks}周)`;
    } else {
      return `${this.babyName} (${ageInMonths}个月)`;
    }
  }

  toJson(): Record<string, Object> {
    return {
      id: this.id,
      webdavUrl: this.webdavUrl,
      username: this.username,
      password: this.password,
      babyName: this.babyName,
      babyBirthDate: this.babyBirthDate,
      babyConceptionDate: this.babyConceptionDate,
      videoCompressionThreshold: this.videoCompressionThreshold,
      webdavMirrors: this.webdavMirrors,
    };
  }

  static fromJson(json: Record<string, Object>): AppConfig {
    const webdavUrl = (json['webdavUrl'] as string) ?? '';
    const mirrors = (json['webdavMirrors'] as string[]) ?? [];
    // 向后兼容：如果没有 mirrors 但有 webdavUrl，则迁移
    const effectiveMirrors = mirrors.length === 0 && webdavUrl.length > 0
      ? [webdavUrl]
      : mirrors;

    return new AppConfig(
      (json['id'] as string) ?? generateUUID(),
      webdavUrl,
      (json['username'] as string) ?? '',
      (json['password'] as string) ?? '',
      (json['babyName'] as string) ?? (json['childName'] as string) ?? '',
      (json['babyBirthDate'] as string) ?? (json['childBirthDate'] as string) ?? '',
      (json['babyConceptionDate'] as string) ?? (json['conceptionDate'] as string) ?? '',
      (json['videoCompressionThreshold'] as number) ?? 10,
      effectiveMirrors,
    );
  }

  static createDefault(): AppConfig {
    return new AppConfig(
      generateUUID(),
      '',
      '',
      '',
      '',
      '',
      '',
      10,
      [],
    );
  }
}

/**
 * 生成 UUID v4
 */
export function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}
