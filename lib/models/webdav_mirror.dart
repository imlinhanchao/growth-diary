class WebDavMirror {
  final String url;
  final String? wifiSsid; // 绑定的 WiFi SSID，为空表示不限制WiFi（作为通用/默认镜像）

  WebDavMirror({
    required this.url,
    this.wifiSsid,
  });

  /// 是否配置了 WiFi 绑定
  bool get hasWifiBinding =>
      wifiSsid != null && wifiSsid!.trim().isNotEmpty;

  /// 检查是否匹配指定的 WiFi SSID
  bool matchesWifi(String? ssid) {
    if (!hasWifiBinding || ssid == null || ssid.trim().isEmpty) {
      return false;
    }
    final target = ssid.trim().toLowerCase();
    final configuredSsids = wifiSsid!
        .split(RegExp(r'[,;，；]'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty);
    return configuredSsids.contains(target);
  }

  WebDavMirror copyWith({
    String? url,
    String? wifiSsid,
    bool clearWifi = false,
  }) {
    return WebDavMirror(
      url: url ?? this.url,
      wifiSsid: clearWifi ? null : (wifiSsid ?? this.wifiSsid),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      if (wifiSsid != null && wifiSsid!.trim().isNotEmpty)
        'wifiSsid': wifiSsid!.trim(),
    };
  }

  factory WebDavMirror.fromJson(dynamic json) {
    if (json is WebDavMirror) return json;
    if (json is String) {
      return WebDavMirror(url: json);
    } else if (json is Map<String, dynamic>) {
      return WebDavMirror(
        url: json['url'] as String? ?? '',
        wifiSsid: json['wifiSsid'] as String?,
      );
    }
    return WebDavMirror(url: json?.toString() ?? '');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebDavMirror &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          wifiSsid == other.wifiSsid;

  @override
  int get hashCode => url.hashCode ^ (wifiSsid?.hashCode ?? 0);

  @override
  String toString() => 'WebDavMirror(url: $url, wifiSsid: $wifiSsid)';
}
