// 生成 WebDAV 测试数据：多组 configId，每组 N 条日记 + 缩略图 + 媒体占位。
//
// 用法：
//   dart tool/dav_seed.dart --root build/dav_root \
//       --ids baby-500:500,baby-2000:2000 \
//       --webdav-url http://10.0.2.2:8088/
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  final opts = _parseArgs(args);
  final root = Directory(opts['root'] ?? 'build/dav_root');
  final url = opts['webdav-url'] ?? 'http://127.0.0.1:8088/';
  final ids = (opts['ids'] ?? 'baby-500:500').split(',');
  final imagesPerEntry = int.parse(opts['images'] ?? '2');
  final birth = DateTime.parse(opts['birth'] ?? '2022-03-08');

  final palette = List.generate(24, (i) {
    final r = 60 + (i * 37) % 180;
    final g = 90 + (i * 53) % 150;
    final b = 120 + (i * 71) % 130;
    return (r, g, b);
  });
  // 预编码一轮，避免上万次 zlib 压缩拖慢生成
  final smallPngs = [
    for (final c in palette) pngSolid(400, 300, c.$1, c.$2, c.$3)
  ];
  final mediumPngs = [
    for (final c in palette) pngSolid(768, 576, c.$1, c.$2, c.$3)
  ];

  for (final spec in ids) {
    final parts = spec.split(':');
    final id = parts[0];
    final count = int.parse(parts[1]);
    _seedOne(root, url, id, count, imagesPerEntry, birth, palette,
        smallPngs, mediumPngs);
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      final key = args[i].substring(2);
      final next = i + 1 < args.length && !args[i + 1].startsWith('--')
          ? args[++i]
          : 'true';
      map[key] = next;
    }
  }
  return map;
}

void _seedOne(Directory root, String url, String id, int count,
    int imagesPerEntry, DateTime birth, List<(int, int, int)> palette,
    List<Uint8List> smallPngs, List<Uint8List> mediumPngs) {
  final base = Directory('${root.path}/growth_diary/$id');
  final entriesDir = Directory('${base.path}/entries')
    ..createSync(recursive: true);
  final mediaDir = Directory('${base.path}/media')..createSync(recursive: true);
  final thumbDir = Directory('${base.path}/thumbnails')
    ..createSync(recursive: true);

  // 清理旧数据，保证可重复执行
  for (final dir in [entriesDir, mediaDir, thumbDir]) {
    for (final f in dir.listSync()) {
      f.deleteSync(recursive: true);
    }
  }

  final config = {
    'id': id,
    'webdavUrl': url,
    'username': 'tester',
    'password': 'secret',
    'babyName': id == 'baby-2000' ? '压力测试宝宝' : '小星星',
    'babyBirthDate': birth.toIso8601String(),
    'babyConceptionDate':
        birth.subtract(const Duration(days: 280)).toIso8601String(),
    'babyCoverImagePath': null,
    'videoCompressionThreshold': 10,
    'webdavMirrors': [
      {'url': url, 'wifiSsid': null}
    ],
  };
  File('${base.path}/config.json')
      .writeAsStringSync(jsonEncode(config), flush: true);

  final stopwatch = Stopwatch()..start();
  var totalImages = 0;
  var totalVideos = 0;

  for (var i = 0; i < count; i++) {
    // 从出生开始，平均每天一条，覆盖约 count 天
    final date = birth.add(Duration(days: 30 + i));
    final months = (date.year - birth.year) * 12 + date.month - birth.month;
    final variant = i % palette.length;

    final imagePaths = <String>[];
    final imageThumbs = <String>[];
    for (var k = 0; k < imagesPerEntry; k++) {
      final name = 'img_${id}_${i}_$k';
      final small = smallPngs[(variant + k) % smallPngs.length];
      File('${mediaDir.path}/$name.jpg').writeAsBytesSync(small, flush: true);
      File('${thumbDir.path}/${name}_small.jpg')
          .writeAsBytesSync(small, flush: true);
      File('${thumbDir.path}/${name}_medium.jpg')
          .writeAsBytesSync(mediumPngs[(variant + k) % mediumPngs.length],
              flush: true);
      imagePaths.add('media/$name.jpg');
      imageThumbs.add('thumbnails/${name}_small.jpg');
      totalImages++;
    }

    final videoPaths = <String>[];
    final videoThumbs = <String>[];
    if (i % 10 == 0) {
      final name = 'vid_${id}_$i';
      final thumb = pngSolid(400, 300, 30, 30, 40);
      File('${mediaDir.path}/$name.mp4')
          .writeAsBytesSync(Uint8List(256), flush: true);
      File('${thumbDir.path}/${name}_small.jpg').writeAsBytesSync(thumb);
      File('${thumbDir.path}/${name}_medium.jpg').writeAsBytesSync(thumb);
      videoPaths.add('media/$name.mp4');
      videoThumbs.add('thumbnails/${name}_small.jpg');
      totalVideos++;
    }

    final body = '第 $i 条记录的正文。' * (i % 5 == 0 ? 12 : 2);
    final entry = {
      'id': 'entry-${id}-$i',
      'date': date.toIso8601String(),
      'title': '记录 $i：${_titlePool[i % _titlePool.length]}',
      'description': body,
      'imagePaths': imagePaths,
      'videoPaths': videoPaths,
      'imageThumbnails': imageThumbs,
      'videoThumbnails': videoThumbs,
      'ageInMonths': months,
    };
    File('${entriesDir.path}/entry-${id}-$i.json')
        .writeAsStringSync(jsonEncode(entry), flush: true);
  }

  stopwatch.stop();
  stdout.writeln('[$id] $count 条（图片 $totalImages，视频 $totalVideos），'
      '目录 ${entriesDir.path}，用时 ${stopwatch.elapsedMilliseconds}ms');
}

const _titlePool = [
  '第一次翻身',
  '会叫妈妈了',
  '今天去公园',
  '第一次吃辅食',
  '学会了挥手',
  '出牙了',
  '第一次走路',
  '周末全家出游',
  '在沙滩上玩了一下午',
  '第一次自己拿勺子',
  '睡前故事时间',
  '下雨天在家画画',
];

// ── 最小 PNG 编码器（纯色图） ──────────────────────────────

Uint8List pngSolid(int width, int height, int r, int g, int b) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < width; x++) {
      raw.addByte(r);
      raw.addByte(g);
      raw.addByte(b);
    }
  }
  final idat = Uint8List.fromList(ZLibCodec(level: 6).encode(raw.toBytes()));

  final out = BytesBuilder();
  out.add([137, 80, 78, 71, 13, 10, 26, 10]);
  out.add(_chunk('IHDR', _ihdr(width, height)));
  out.add(_chunk('IDAT', idat));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.toBytes();
}

Uint8List _ihdr(int width, int height) {
  final data = Uint8List(13);
  final bd = ByteData.view(data.buffer);
  bd.setUint32(0, width);
  bd.setUint32(4, height);
  data[8] = 8; // bit depth
  data[9] = 2; // color type: truecolor
  data[10] = 0; // compression
  data[11] = 0; // filter
  data[12] = 0; // interlace
  return data;
}

Uint8List _chunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  final body = BytesBuilder()
    ..add(typeBytes)
    ..add(data);
  final bytes = body.toBytes();
  final out = BytesBuilder();
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  out.add(bytes);
  final crc = ByteData(4)..setUint32(0, _crc32(bytes));
  out.add(crc.buffer.asUint8List());
  return out.toBytes();
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
