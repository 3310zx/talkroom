import 'dart:math';

import '../../core/constants.dart';

/// 配对码校验结果
enum PairCheckResult { ok, invalid, locked }

/// 配对码防猜守卫（PRD 7.5：6 位配对码、连续错误锁定）。
///
/// 状态存 settings 表（failCount / lockUntil），本类只负责纯逻辑判断与状态推进，
/// 便于单元测试。
class PairGuard {
  PairGuard({
    this.failCount = 0,
    this.lockUntil = 0,
    this.maxFailures = AppConstants.pairMaxFailures,
    this.lockDurationMs = AppConstants.pairLockDurationMs,
    this.now,
  });

  /// 当前累计失败次数
  int failCount;

  /// 锁定截止（毫秒时间戳；0 表示未锁定）
  int lockUntil;

  final int maxFailures;
  final int lockDurationMs;

  /// 可注入时钟（测试用）
  final DateTime Function()? now;

  int get _nowMs => (now?.call() ?? DateTime.now()).millisecondsSinceEpoch;

  /// 是否处于锁定期
  bool get isLocked => _nowMs < lockUntil;

  /// 距解锁剩余毫秒（<=0 表示未锁定）
  int get remainingLockMs => lockUntil - _nowMs;

  /// 校验配对码：先查锁定，再比对码值与位数。
  PairCheckResult check({required String? expectedCode, required String input}) {
    if (isLocked) return PairCheckResult.locked;
    final trimmed = input.trim();
    final valid = expectedCode != null &&
        expectedCode.isNotEmpty &&
        trimmed.length == AppConstants.pairCodeLength &&
        trimmed == expectedCode;
    if (!valid) {
      _registerFailure();
      return PairCheckResult.invalid;
    }
    // 配对成功：清空防猜状态
    reset();
    return PairCheckResult.ok;
  }

  void _registerFailure() {
    failCount += 1;
    if (failCount >= maxFailures) {
      lockUntil = _nowMs + lockDurationMs;
      failCount = 0;
    }
  }

  void reset() {
    failCount = 0;
    lockUntil = 0;
  }

  /// 生成新的 6 位数字配对码（去掉前导 0 歧义：保留 6 位，允许 0 开头）
  static String generateCode({int length = AppConstants.pairCodeLength}) {
    final rng = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(rng.nextInt(10));
    }
    return sb.toString();
  }
}
