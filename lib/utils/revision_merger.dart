import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';

/// 一次保存的裁决结果。
///
/// [entry] 需要写入原 id 的条目（null 表示远端版本更优，不覆盖）；
/// [conflictCopy] 需要另存为新 id 的副本（冲突时保留另一方内容）。
class SaveDecision {
  const SaveDecision({
    this.entry,
    this.conflictCopy,
    required this.reason,
  });

  final DiaryEntry? entry;
  final DiaryEntry? conflictCopy;
  final String reason;

  bool get hasConflict => conflictCopy != null;

  @override
  String toString() =>
      'SaveDecision(entry:${entry?.id}/${entry?.rev}, '
      'copy:${conflictCopy?.id}/${conflictCopy?.rev}, reason:$reason)';
}

/// 冲突裁决：以 rev 为主、updatedAt 为辅，绝不静默丢内容。
///
/// 规则：
/// 1. 远端不存在 → 直接写入，rev + 1；
/// 2. 内容完全相同（忽略版本字段）→ 只递增 rev，不产生副本；
/// 3. rev 不同 → rev 大的一方留在原 id，另一方另存为"冲突副本"；
/// 4. rev 相同 → updatedAt 较新的一方留在原 id，另一方另存副本。
///
/// 时钟只用在同一 rev 的排序上，且双方时间差超过 [clockSkewTolerance] 时
/// 走"都保留"策略，避免两台手机时钟不一致导致静默覆盖。
const int clockSkewToleranceMs = 5 * 60 * 1000;

SaveDecision decideEntrySave({
  required DiaryEntry incoming,
  required DiaryEntry? remote,
  required String deviceId,
  required DateTime now,
  String conflictSuffix = '（冲突副本）',
}) {
  final stamp = now.millisecondsSinceEpoch;

  DiaryEntry withVersion(DiaryEntry base, int rev, {String? id, String? title}) {
    return base.copyWith(
      id: id,
      title: title,
      rev: rev,
      updatedAt: stamp,
      deviceId: deviceId,
    );
  }

  DiaryEntry copyOf(DiaryEntry source) => withVersion(
        source,
        1,
        id: const Uuid().v4(),
        title: source.title.isEmpty
            ? conflictSuffix
            : '${source.title}$conflictSuffix',
      );

  if (remote == null) {
    return SaveDecision(
      entry: withVersion(incoming, incoming.rev + 1),
      reason: 'create',
    );
  }

  // 旧版本写的条目没有版本信息（rev/updatedAt 都是 0），
  // 第一次编辑它时不能判成冲突，否则每次改老日记都会多出一份副本。
  if (remote.rev == 0 && remote.updatedAt == 0) {
    return SaveDecision(
      entry: withVersion(incoming, _max(incoming.rev, remote.rev) + 1),
      reason: 'legacy-remote',
    );
  }

  if (_sameContent(incoming, remote)) {
    return SaveDecision(
      entry: withVersion(incoming, _max(incoming.rev, remote.rev) + 1),
      reason: 'unchanged',
    );
  }

  final mainRev = _max(incoming.rev, remote.rev) + 1;

  if (incoming.rev != remote.rev) {
    if (incoming.rev > remote.rev) {
      return SaveDecision(
        entry: withVersion(incoming, mainRev),
        conflictCopy: copyOf(remote),
        reason: 'local-rev-higher',
      );
    }
    return SaveDecision(
      entry: null,
      conflictCopy: copyOf(incoming),
      reason: 'remote-rev-higher',
    );
  }

  // rev 相同：看修改时间。差距过大则视为时钟不可信，两边都留。
  final diff = incoming.updatedAt - remote.updatedAt;
  if (diff.abs() > clockSkewToleranceMs) {
    if (diff > 0) {
      return SaveDecision(
        entry: withVersion(incoming, mainRev),
        conflictCopy: copyOf(remote),
        reason: 'local-time-newer',
      );
    }
    return SaveDecision(
      entry: null,
      conflictCopy: copyOf(incoming),
      reason: 'remote-time-newer',
    );
  }

  // 无法判断谁更新：保留两份，原 id 归本次编辑
  return SaveDecision(
    entry: withVersion(incoming, mainRev),
    conflictCopy: copyOf(remote),
    reason: 'ambiguous-keep-both',
  );
}

int _max(int a, int b) => a > b ? a : b;

/// 比较正文内容，忽略 id、版本号、时间戳与设备字段。
bool _sameContent(DiaryEntry a, DiaryEntry b) {
  return a.date == b.date &&
      a.title == b.title &&
      a.description == b.description &&
      a.ageInMonths == b.ageInMonths &&
      _sameList(a.imagePaths, b.imagePaths) &&
      _sameList(a.videoPaths, b.videoPaths) &&
      _sameList(a.imageThumbnails, b.imageThumbnails) &&
      _sameList(a.videoThumbnails, b.videoThumbnails);
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
