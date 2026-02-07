import 'package:growth_diary/models/app_config.dart';

class AgeCalculator {
  /// Average days per month used for age calculation
  /// 365.25 days/year ÷ 12 months ≈ 30.44 days/month
  static const double averageDaysPerMonth = 30.44;

  /// Calculates the difference between two dates in years, months, and days
  /// Returns a map with keys 'years', 'months', 'days'
  static calculateDateDifference(DateTime start, DateTime end) {
    // 确保 start 在 end 之前，如果不是则交换
    if (start.isAfter(end)) {
      DateTime temp = start;
      start = end;
      end = temp;
    }

    int years = end.year - start.year;
    int months = end.month - start.month;
    int days = end.day - start.day;

    // 调整月份和天数
    if (days < 0) {
      months--;
      // 获取前一个月的天数
      int previousMonth = end.month - 1;
      int previousYear = end.year;
      if (previousMonth == 0) {
        previousMonth = 12;
        previousYear--;
      }
      days += DateTime(previousYear, previousMonth + 1, 0).day;
    }

    if (months < 0) {
      years--;
      months += 12;
    }

    // 如果需要，可以返回一个 Map
    return {
      'years': years,
      'months': months,
      'days': days,
    };
  }

  /// Calculates the difference in weeks between two dates
  static int calculateWeeksDifference(DateTime start, DateTime end) {
    // 确保 start 在 end 之前，如果不是则交换
    if (start.isAfter(end)) {
      DateTime temp = start;
      start = end;
      end = temp;
    }

    // 计算天数差异
    int daysDifference = end.difference(start).inDays;

    // 计算周数差异（向下取整）
    int weeksDifference = daysDifference ~/ 7;

    return weeksDifference;
  }

  /// Calculates the age in months from birth date to the given date
  static int calculateAgeInMonths(DateTime birthDate, DateTime currentDate) {
    final diff = currentDate.difference(birthDate);
    return (diff.inDays / averageDaysPerMonth).ceil().toInt();
  }

  /// Calculates the detailed age (years, months, days) from birth date to the given date
  static Map<String, int> calculateDetailedAge(
      DateTime birthDate, DateTime currentDate) {
    int years = currentDate.year - birthDate.year;
    int months = currentDate.month - birthDate.month;
    int days = currentDate.day - birthDate.day;

    // Adjust for negative months
    if (months < 0) {
      years--;
      months += 12;
    }

    // Adjust for negative days
    if (days < 0) {
      months--;
      if (months < 0) {
        years--;
        months += 12;
      }

      // Calculate days in previous month
      DateTime previousMonth =
          DateTime(currentDate.year, currentDate.month - 1, 1);
      int daysInPreviousMonth =
          DateTime(previousMonth.year, previousMonth.month + 1, 0).day;
      days += daysInPreviousMonth;
    }

    return {
      'years': years.clamp(0, double.infinity).toInt(),
      'months': months.clamp(0, 11), // 0-11 months
      'days': days.clamp(0, double.infinity).toInt(),
    };
  }

  /// Formats age in months to a human-readable Chinese label with days
  static String formatAgeLabel(int ageInMonths) {
    // For backward compatibility, if we only have months, show approximate
    if (ageInMonths == 0) {
      return '出生';
    } else if (ageInMonths < 12) {
      return '$ageInMonths月龄';
    } else {
      int years = ageInMonths ~/ 12;
      int months = ageInMonths % 12;
      if (months == 0) {
        return '$years岁';
      } else {
        return '$years岁$months月';
      }
    }
  }

  /// Formats detailed age (years, months, days) to a human-readable Chinese label
  static String formatDetailedAgeLabel(DateTime currentDate, AppConfig config) {
    int ageInMonths = calculateAgeInMonths(config.childBirthDate!, currentDate);
    if (ageInMonths < 0 && config.conceptionDate == null) {
      return '出生前 ${-ageInMonths} 月';
    } else if (ageInMonths < 0 && config.conceptionDate != null) {
      return '孕${calculateWeeksSinceConception(config.conceptionDate!, currentDate)}周';
    }

    final age = calculateDateDifference(config.childBirthDate!, currentDate);
    final years = age['years']!;
    final months = age['months']!;
    final days = age['days']!;

    final dayText = days > 0 ? (days > 10 ? '$days天' : '零$days天') : '';

    if (years == 0 && months == 0 && days == 0) {
      return '出生';
    } else if (years == 0 && months == 0) {
      return '$days天';
    } else if (years == 0) {
      return months > 0 ? '$months个月$dayText' : dayText;
    } else {
      return '$years岁${months > 0 ? '$months个月$dayText' : dayText}';
    }
  }

  /// Formats age to a simplified Chinese label (years, months and days)
  static String formatSimplifiedAgeLabel(
      DateTime currentDate, AppConfig config) {
    bool isBeforeBirth = currentDate.isBefore(config.childBirthDate!);
    if (isBeforeBirth && config.conceptionDate == null) {
      int ageInMonths =
          calculateAgeInMonths(config.childBirthDate!, currentDate);
      return '出生前 ${-ageInMonths} 月';
    } else if (isBeforeBirth && config.conceptionDate != null) {
      return '孕${calculateWeeksSinceConception(config.conceptionDate!, currentDate)}周';
    }
    final age = calculateDateDifference(config.childBirthDate!, currentDate);
    final years = age['years']!;
    final months = age['months']!;
    final days = age['days']!;

    if (years == 0 && months == 0 && days == 0) {
      return '出生';
    } else if (years == 0 && months == 0) {
      return '1月龄';
    } else if (years == 0) {
      return '$months月龄';
    } else if (months == 0) {
      return '$years周岁';
    } else {
      return '$years岁$months个月';
    }
  }

  /// Calculates the number of weeks since conception date
  static int calculateWeeksSinceConception(
      DateTime conceptionDate, DateTime date) {
    final difference = date.difference(conceptionDate);
    return (difference.inDays / 7).floor();
  }
}
