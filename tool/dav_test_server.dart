// 本地 WebDAV 测试夹具：为 Phase 1 的加载/同步验收提供可控服务端。
//
// 用法：
//   dart tool/dav_test_server.dart --root build/dav_root --port 8088 --latency 20
//
// 控制接口（不属于 DAV，不计入请求统计）：
//   GET  /__stats            请求计数与明细（?reset=1 顺带清零）
//   POST /__reset            清零计数
//   GET  /__chaos?latency=50&fail=1.0&failStatus=503
//   POST /__shutdown         退出进程（模拟服务端消失）
//
// 支持的 DAV 方法：OPTIONS / PROPFIND(depth 0,1) / GET / HEAD / PUT / DELETE / MKCOL
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

late Directory rootDir;
late Stats stats;
int latencyMs = 0;
double failRate = 0;
int failStatus = 503;
File? logFile;
final _rand = math.Random(42);

void main(List<String> args) async {
  final opts = _parseArgs(args);
  final port = int.parse(opts['port'] ?? '8088');
  latencyMs = int.parse(opts['latency'] ?? '0');
  failRate = double.parse(opts['fail'] ?? '0');
  final rootPath = opts['root'] ?? 'build/dav_root';
  final logPath = opts['log'];

  rootDir = Directory(rootPath);
  if (!rootDir.existsSync()) {
    stderr.writeln('root 不存在: $rootPath');
    exit(2);
  }
  stats = Stats();

  if (logPath != null) {
    logFile = File(logPath)..writeAsStringSync('');
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  // 与真实服务端一致：按客户端 Accept-Encoding 压缩响应
  server.autoCompress = true;
  stdout.writeln('DAV fixture listening on http://0.0.0.0:$port (root=$rootPath)');

  server.listen((req) {
    unawaited(_handle(req));
  });
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

class Stats {
  int total = 0;
  int _inflight = 0;
  int peakInflight = 0;

  void enter() {
    _inflight++;
    if (_inflight > peakInflight) peakInflight = _inflight;
  }

  void leave() => _inflight--;
  final Map<String, int> byMethod = {};
  final Map<String, int> byPath = {};
  final List<Map<String, dynamic>> entries = [];
  DateTime windowStart = DateTime.now();

  void hit(String method, String path) {
    total++;
    byMethod[method] = (byMethod[method] ?? 0) + 1;
    byPath[path] = (byPath[path] ?? 0) + 1;
    final entry = {
      't': DateTime.now().millisecondsSinceEpoch,
      'm': method,
      'p': path,
    };
    entries.add(entry);
    logFile?.writeAsStringSync('${jsonEncode(entry)}\n',
        mode: FileMode.append, flush: true);
  }

  void reset() {
    total = 0;
    peakInflight = 0;
    byMethod.clear();
    byPath.clear();
    entries.clear();
    windowStart = DateTime.now();
  }

  Map<String, dynamic> toJson({bool detail = false}) {
    final sorted = byPath.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'total': total,
      'byMethod': byMethod,
      'peakInflight': peakInflight,
      if (detail) 'paths': byPath else 'topPaths': {
        for (final e in sorted.take(8)) e.key: e.value
      },
        'windowStart': windowStart.toIso8601String(),
        'elapsedMs': DateTime.now().difference(windowStart).inMilliseconds,
      'latencyMs': latencyMs,
      'failRate': failRate,
    };
  }
}

String _decodedPath(HttpRequest req) {
  final segments = req.uri.pathSegments.map(Uri.decodeComponent);
  return '/${segments.join('/')}';
}

File _fileFor(String path) =>
    File('${rootDir.path}${path == '/' ? '' : path}');

Directory _dirFor(String path) =>
    Directory('${rootDir.path}${path == '/' ? '' : path}');

bool _isSafe(String path) => !path.contains('..');

Future<void> _handle(HttpRequest req) async {
  final method = req.method.toUpperCase();
  final path = _decodedPath(req);

  if (path.startsWith('/__')) {
    await _handleControl(req, path);
    return;
  }

  stats.hit(method, path);
  stats.enter();
  try {
    await _handleInner(req, method, path);
  } finally {
    stats.leave();
  }
}

Future<void> _handleInner(HttpRequest req, String method, String path) async {
  if (latencyMs > 0) {
    await Future<void>.delayed(Duration(milliseconds: latencyMs));
  }
  if (failRate > 0 && _rand.nextDouble() < failRate) {
    req.response.statusCode = failStatus;
    req.response.write('injected failure');
    await req.response.close();
    return;
  }
  if (!_isSafe(path)) {
    req.response.statusCode = 400;
    await req.response.close();
    return;
  }

  try {
    switch (method) {
      case 'OPTIONS':
        await _options(req);
      case 'PROPFIND':
        await _propfind(req, path);
      case 'GET':
      case 'HEAD':
        await _get(req, path, headOnly: method == 'HEAD');
      case 'PUT':
        await _put(req, path);
      case 'DELETE':
        await _delete(req, path);
      case 'MKCOL':
        await _mkcol(req, path);
      default:
        req.response.statusCode = 405;
        req.response.headers.set('allow', 'OPTIONS, GET, PUT, PROPFIND, DELETE, MKCOL');
        await req.response.close();
    }
  } catch (e, st) {
    stderr.writeln('handle error $method $path: $e\n$st');
    try {
      req.response.statusCode = 500;
      await req.response.close();
    } catch (_) {}
  }
}

Future<void> _handleControl(HttpRequest req, String path) async {
  final res = req.response;
  switch (path) {
    case '/__stats':
      if (req.uri.queryParameters['reset'] == '1') stats.reset();
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(
          stats.toJson(detail: req.uri.queryParameters['detail'] == '1')));
    case '/__reset':
      stats.reset();
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'ok': true}));
    case '/__chaos':
      final q = req.uri.queryParameters;
      if (q['latency'] != null) latencyMs = int.parse(q['latency']!);
      if (q['fail'] != null) failRate = double.parse(q['fail']!);
      if (q['failStatus'] != null) failStatus = int.parse(q['failStatus']!);
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'latencyMs': latencyMs, 'failRate': failRate}));
    case '/__shutdown':
      res.write('bye');
      await res.close();
      exit(0);
    default:
      res.statusCode = 404;
  }
  await res.close();
}

Future<void> _options(HttpRequest req) async {
  final res = req.response;
  res.statusCode = 200;
  res.headers.set('DAV', '1, 2');
  res.headers.set('MS-Author-Via', 'DAV');
  res.headers.set('Allow',
      'OPTIONS, GET, HEAD, PUT, PROPFIND, DELETE, MKCOL, COPY, MOVE');
  res.headers.contentLength = 0;
  await res.close();
}

String _href(String path, {required bool isDir}) {
  final encoded = path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  final withSlash = isDir && !encoded.endsWith('/') ? '$encoded/' : encoded;
  return '/$withSlash';
}

String _responseXml({
  required String href,
  required bool isDir,
  required int size,
  required DateTime mtime,
  required String etag,
}) {
  final type = isDir
      ? '<d:resourcetype><d:collection/></d:resourcetype>'
      : '<d:resourcetype/>';
  final length = isDir ? 0 : size;
  final contentType =
      isDir ? 'httpd/unix-directory' : _mimeFor(href);
  return '''
<d:response>
  <d:href>$href</d:href>
  <d:propstat>
    <d:prop>
      <d:displayname>${_displayName(href)}</d:displayname>
      $type
      <d:getcontentlength>$length</d:getcontentlength>
      <d:getcontenttype>$contentType</d:getcontenttype>
      <d:getetag>$etag</d:getetag>
      <d:getlastmodified>${HttpDate.format(mtime.toUtc())}</d:getlastmodified>
    </d:prop>
    <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat>
</d:response>''';
}

String _displayName(String href) {
  final trimmed = href.replaceAll(RegExp(r'/$'), '');
  final idx = trimmed.lastIndexOf('/');
  return idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
}

String _mimeFor(String href) {
  final lower = href.toLowerCase();
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  return 'application/octet-stream';
}

String _etagFor(FileStat stat) =>
    '"${stat.size.toRadixString(16)}-${stat.modified.millisecondsSinceEpoch.toRadixString(16)}"';

Future<void> _propfind(HttpRequest req, String path) async {
  final res = req.response;
  final depth = req.headers.value('depth') ?? '1';
  final dir = _dirFor(path);
  final file = _fileFor(path);

  final parts = <String>[];
  if (dir.existsSync()) {
    final stat = dir.statSync();
    parts.add(_responseXml(
      href: _href(path, isDir: true),
      isDir: true,
      size: 0,
      mtime: stat.modified,
      etag: _etagFor(stat),
    ));
    if (depth != '0') {
      final children = dir.listSync(followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final child in children) {
        final name = child.path.split(Platform.pathSeparator).last;
        final childPath = '${path.replaceAll(RegExp(r'/$'), '')}/$name';
        final childStat = child.statSync();
        parts.add(_responseXml(
          href: _href(childPath, isDir: child is Directory),
          isDir: child is Directory,
          size: childStat.size,
          mtime: childStat.modified,
          etag: _etagFor(childStat),
        ));
      }
    }
  } else if (file.existsSync()) {
    final stat = file.statSync();
    parts.add(_responseXml(
      href: _href(path, isDir: false),
      isDir: false,
      size: stat.size,
      mtime: stat.modified,
      etag: _etagFor(stat),
    ));
  } else {
    res.statusCode = 404;
    await res.close();
    return;
  }

  final body = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<d:multistatus xmlns:d="DAV:">\n${parts.join('\n')}\n</d:multistatus>';
  res.statusCode = 207;
  res.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
  res.write(body);
  await res.close();
}

Future<void> _get(HttpRequest req, String path, {required bool headOnly}) async {
  final res = req.response;
  final file = _fileFor(path);
  if (!file.existsSync()) {
    res.statusCode = 404;
    await res.close();
    return;
  }
  final stat = file.statSync();
  res.statusCode = 200;
  res.headers.set('ETag', _etagFor(stat));
  res.headers.set('Last-Modified', HttpDate.format(stat.modified.toUtc()));
  res.headers.contentType = ContentType.parse(_mimeFor(path));
  res.headers.contentLength = stat.size;
  if (!headOnly) {
    await res.addStream(file.openRead());
  }
  await res.close();
}

Future<void> _put(HttpRequest req, String path) async {
  final res = req.response;
  final file = _fileFor(path);
  final existed = file.existsSync();
  file.parent.createSync(recursive: true);
  final bytes = await req.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
  final tmp = File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
  tmp.writeAsBytesSync(bytes, flush: true);
  if (file.existsSync()) file.deleteSync();
  tmp.renameSync(file.path);
  res.statusCode = existed ? 204 : 201;
  await res.close();
}

Future<void> _delete(HttpRequest req, String path) async {
  final res = req.response;
  final file = _fileFor(path);
  final dir = _dirFor(path);
  if (file.existsSync()) {
    file.deleteSync();
    res.statusCode = 204;
  } else if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
    res.statusCode = 204;
  } else {
    res.statusCode = 404;
  }
  await res.close();
}

Future<void> _mkcol(HttpRequest req, String path) async {
  final res = req.response;
  final dir = _dirFor(path);
  if (dir.existsSync()) {
    res.statusCode = 405;
  } else {
    final parent = dir.parent;
    if (!parent.existsSync()) {
      res.statusCode = 409;
    } else {
      dir.createSync();
      res.statusCode = 201;
    }
  }
  await res.close();
}
