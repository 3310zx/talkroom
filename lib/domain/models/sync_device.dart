/// 已配对设备实体（对应 PRD 6.1.2 `devices` 表，第 7 章 7.4.2）。
class SyncDevice {
  final int? id;
  final String deviceId;
  final String deviceName;
  final String deviceType; // 'server' | 'client'
  final String? token;
  final String? pairCode;
  final bool isTrusted;
  final int failCount;
  final int lockUntil; // 0 表示未锁定
  final int lastSeenAt;
  final int createdAt;

  const SyncDevice({
    this.id,
    required this.deviceId,
    required this.deviceName,
    this.deviceType = 'client',
    this.token,
    this.pairCode,
    this.isTrusted = false,
    this.failCount = 0,
    this.lockUntil = 0,
    this.lastSeenAt = 0,
    required this.createdAt,
  });

  SyncDevice copyWith({
    int? id,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? token,
    String? pairCode,
    bool? isTrusted,
    int? failCount,
    int? lockUntil,
    int? lastSeenAt,
    int? createdAt,
  }) {
    return SyncDevice(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceType: deviceType ?? this.deviceType,
      token: token ?? this.token,
      pairCode: pairCode ?? this.pairCode,
      isTrusted: isTrusted ?? this.isTrusted,
      failCount: failCount ?? this.failCount,
      lockUntil: lockUntil ?? this.lockUntil,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'device_name': deviceName,
      'device_type': deviceType,
      'token': token,
      'pair_code': pairCode,
      'is_trusted': isTrusted ? 1 : 0,
      'fail_count': failCount,
      'lock_until': lockUntil,
      'last_seen_at': lastSeenAt,
      'created_at': createdAt,
    };
  }

  factory SyncDevice.fromMap(Map<String, Object?> map) {
    return SyncDevice(
      id: map['id'] as int?,
      deviceId: map['device_id'] as String? ?? '',
      deviceName: map['device_name'] as String? ?? '未知设备',
      deviceType: map['device_type'] as String? ?? 'client',
      token: map['token'] as String?,
      pairCode: map['pair_code'] as String?,
      isTrusted: (map['is_trusted'] as int? ?? 0) == 1,
      failCount: map['fail_count'] as int? ?? 0,
      lockUntil: map['lock_until'] as int? ?? 0,
      lastSeenAt: map['last_seen_at'] as int? ?? 0,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }
}
