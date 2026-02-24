/**
 * 日记条目数据模型
 * 对应 Flutter 版本的 DiaryEntry
 */
export class DiaryEntry {
  id: string;
  date: string; // ISO 8601 格式
  title: string;
  description: string;
  imagePaths: string[];
  videoPaths: string[];
  imageThumbnails: string[];
  videoThumbnails: string[];
  ageInMonths: number;

  constructor(
    id: string,
    date: string,
    title: string,
    description: string,
    imagePaths: string[],
    videoPaths: string[],
    imageThumbnails: string[],
    videoThumbnails: string[],
    ageInMonths: number
  ) {
    this.id = id;
    this.date = date;
    this.title = title;
    this.description = description;
    this.imagePaths = imagePaths;
    this.videoPaths = videoPaths;
    this.imageThumbnails = imageThumbnails;
    this.videoThumbnails = videoThumbnails;
    this.ageInMonths = ageInMonths;
  }

  toJson(): Record<string, Object> {
    return {
      id: this.id,
      date: this.date,
      title: this.title,
      description: this.description,
      imagePaths: this.imagePaths,
      videoPaths: this.videoPaths,
      imageThumbnails: this.imageThumbnails,
      videoThumbnails: this.videoThumbnails,
      ageInMonths: this.ageInMonths,
    };
  }

  static fromJson(json: Record<string, Object>): DiaryEntry {
    return new DiaryEntry(
      json['id'] as string,
      json['date'] as string,
      json['title'] as string,
      (json['description'] as string) ?? '',
      (json['imagePaths'] as string[]) ?? [],
      (json['videoPaths'] as string[]) ?? [],
      (json['imageThumbnails'] as string[]) ?? [],
      (json['videoThumbnails'] as string[]) ?? [],
      (json['ageInMonths'] as number) ?? 0,
    );
  }

  /**
   * 根据宝宝生日格式化年龄标签
   */
  getAgeLabel(birthDate?: string): string {
    if (!birthDate) {
      return AgeCalculator.formatAgeLabel(this.ageInMonths);
    }
    return AgeCalculator.formatDetailedAgeLabel(this.date, birthDate);
  }
}

/**
 * 年龄计算工具类
 * 对应 Flutter 版本的 AgeCalculator
 */
export class AgeCalculator {
  /**
   * 计算两个日期之间的差值（年、月、天）
   */
  static calculateDateDifference(
    startIso: string,
    endIso: string
  ): { years: number; months: number; days: number } {
    const start = new Date(startIso);
    const end = new Date(endIso);

    let years = end.getFullYear() - start.getFullYear();
    let months = end.getMonth() - start.getMonth();
    let days = end.getDate() - start.getDate();

    if (days < 0) {
      months--;
      const prevMonth = new Date(end.getFullYear(), end.getMonth(), 0);
      days += prevMonth.getDate();
    }
    if (months < 0) {
      years--;
      months += 12;
    }

    return { years, months, days };
  }

  /**
   * 计算从出生日期到指定日期的月龄
   */
  static calculateAgeInMonths(birthDateIso: string, currentDateIso: string): number {
    const birth = new Date(birthDateIso);
    const current = new Date(currentDateIso);
    const diffMs = current.getTime() - birth.getTime();
    const diffDays = diffMs / (1000 * 60 * 60 * 24);
    return Math.ceil(diffDays / 30.44);
  }

  /**
   * 计算两个日期之间的周数差
   */
  static calculateWeeksDifference(startIso: string, endIso: string): number {
    const start = new Date(startIso);
    const end = new Date(endIso);
    const diffMs = Math.abs(end.getTime() - start.getTime());
    return Math.floor(diffMs / (1000 * 60 * 60 * 24 * 7));
  }

  /**
   * 将月龄格式化为可读的中文标签
   */
  static formatAgeLabel(ageInMonths: number): string {
    if (ageInMonths <= 0) {
      return '出生';
    } else if (ageInMonths < 12) {
      return `${ageInMonths}月龄`;
    } else {
      const years = Math.floor(ageInMonths / 12);
      const months = ageInMonths % 12;
      if (months === 0) {
        return `${years}岁`;
      } else {
        return `${years}岁${months}月`;
      }
    }
  }

  /**
   * 根据出生日期格式化详细年龄标签
   */
  static formatDetailedAgeLabel(currentDateIso: string, birthDateIso: string): string {
    const ageInMonths = AgeCalculator.calculateAgeInMonths(birthDateIso, currentDateIso);

    if (ageInMonths < 0) {
      return `出生前 ${-ageInMonths} 月`;
    }

    const diff = AgeCalculator.calculateDateDifference(birthDateIso, currentDateIso);
    const years = diff.years;
    const months = diff.months;
    const days = diff.days;

    const dayText = days > 0 ? (days > 10 ? `${days}天` : `零${days}天`) : '';

    if (years === 0 && months === 0 && days === 0) {
      return '出生';
    } else if (years === 0 && months === 0) {
      return `${days}天`;
    } else if (years === 0) {
      return months > 0 ? `${months}个月${dayText}` : dayText;
    } else {
      return `${years}岁${months > 0 ? `${months}个月${dayText}` : dayText}`;
    }
  }

  /**
   * 格式化简化年龄标签（用于分组标题）
   */
  static formatSimplifiedAgeLabel(currentDateIso: string, birthDateIso: string): string {
    const currentDate = new Date(currentDateIso);
    const birthDate = new Date(birthDateIso);

    if (currentDate < birthDate) {
      const ageInMonths = AgeCalculator.calculateAgeInMonths(birthDateIso, currentDateIso);
      return `出生前 ${-ageInMonths} 月`;
    }

    const diff = AgeCalculator.calculateDateDifference(birthDateIso, currentDateIso);
    const years = diff.years;
    const months = diff.months;

    if (years === 0 && months === 0) {
      return '出生';
    } else if (years === 0) {
      return `${months}月龄`;
    } else if (months === 0) {
      return `${years}周岁`;
    } else {
      return `${years}岁${months}个月`;
    }
  }

  /**
   * 计算当前日期的分组键
   */
  static getGroupKey(currentDateIso: string, birthDateIso: string): number {
    return AgeCalculator.calculateAgeInMonths(birthDateIso, currentDateIso);
  }
}
