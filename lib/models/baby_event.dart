import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class BabyEvent {
  String id;
  String name;
  int iconCodePoint;
  bool isVisible;

  BabyEvent({
    this.id = '',
    required this.name,
    required this.iconCodePoint,
    this.isVisible = true,
  }) {
    if (id.isEmpty) {
      id = const Uuid().v4();
    }
  }

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'iconCodePoint': iconCodePoint,
      'isVisible': isVisible,
    };
  }

  factory BabyEvent.fromJson(Map<String, dynamic> json) {
    return BabyEvent(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? '',
      iconCodePoint: json['iconCodePoint'] ?? Icons.event.codePoint,
      isVisible: json['isVisible'] ?? true,
    );
  }

  BabyEvent copyWith({
    String? id,
    String? name,
    int? iconCodePoint,
    bool? isVisible,
  }) {
    return BabyEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  static List<BabyEvent> defaultEvents() {
    return [
      BabyEvent(
        id: 'default_drink_milk',
        name: '喝奶',
        iconCodePoint: Icons.local_drink.codePoint,
      ),
      BabyEvent(
        id: 'default_diaper',
        name: '换尿布',
        iconCodePoint: Icons.baby_changing_station.codePoint,
      ),
      BabyEvent(
        id: 'default_poop',
        name: '拉屎',
        iconCodePoint: Icons.wc.codePoint,
      ),
      BabyEvent(
        id: 'default_complementary_food',
        name: '吃辅食',
        iconCodePoint: Icons.restaurant.codePoint,
      ),
    ];
  }

  /// Predefined icons available for event selection
  static List<Map<String, dynamic>> availableIcons() {
    return [
      {'icon': Icons.local_drink, 'label': '饮品'},
      {'icon': Icons.baby_changing_station, 'label': '换尿布'},
      {'icon': Icons.wc, 'label': '如厕'},
      {'icon': Icons.restaurant, 'label': '饮食'},
      {'icon': Icons.bedtime, 'label': '睡觉'},
      {'icon': Icons.directions_walk, 'label': '走路'},
      {'icon': Icons.medical_services, 'label': '医疗'},
      {'icon': Icons.vaccines, 'label': '疫苗'},
      {'icon': Icons.monitor_weight, 'label': '体重'},
      {'icon': Icons.height, 'label': '身高'},
      {'icon': Icons.thermostat, 'label': '体温'},
      {'icon': Icons.bathtub, 'label': '洗澡'},
      {'icon': Icons.mood, 'label': '心情'},
      {'icon': Icons.sports, 'label': '运动'},
      {'icon': Icons.toys, 'label': '玩耍'},
      {'icon': Icons.music_note, 'label': '音乐'},
      {'icon': Icons.book, 'label': '阅读'},
      {'icon': Icons.emoji_nature, 'label': '户外'},
      {'icon': Icons.favorite, 'label': '爱心'},
      {'icon': Icons.star, 'label': '星星'},
    ];
  }
}
