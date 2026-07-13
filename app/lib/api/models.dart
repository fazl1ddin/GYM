class AppUser {
  final int id;
  final String name;
  final String login;
  final String role; // 'employee' | 'admin'
  final int? workplaceId;
  final bool active;
  final bool enrolled;
  final bool deviceBound;

  AppUser({
    required this.id,
    required this.name,
    required this.login,
    required this.role,
    required this.workplaceId,
    required this.active,
    required this.enrolled,
    required this.deviceBound,
  });

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'],
        name: j['name'] ?? '',
        login: j['login'] ?? '',
        role: j['role'] ?? 'employee',
        workplaceId: j['workplaceId'],
        active: j['active'] ?? true,
        enrolled: j['enrolled'] ?? false,
        deviceBound: j['deviceBound'] ?? false,
      );
}

class ShiftStatus {
  final bool onShift;
  final int? since; // epoch ms
  ShiftStatus({required this.onShift, this.since});
  factory ShiftStatus.fromJson(Map<String, dynamic> j) =>
      ShiftStatus(onShift: j['onShift'] ?? false, since: j['since']);
}

class AttendanceRecord {
  final int id;
  final String type; // 'in' | 'out'
  final int time;
  final String status; // 'confirmed' | 'pending' | 'rejected'
  final int riskScore;
  final List<String> riskFlags;
  final double? distanceM;
  final String? employeeName;
  final String? photoRef;
  // поля детализации
  final String? workplaceName;
  final double? lat;
  final double? lng;
  final bool? qrOk;
  final bool offline;

  AttendanceRecord({
    required this.id,
    required this.type,
    required this.time,
    required this.status,
    required this.riskScore,
    required this.riskFlags,
    this.distanceM,
    this.employeeName,
    this.photoRef,
    this.workplaceName,
    this.lat,
    this.lng,
    this.qrOk,
    this.offline = false,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: j['id'],
        type: j['type'],
        time: j['time'],
        status: j['status'],
        riskScore: j['riskScore'] ?? 0,
        riskFlags: (j['riskFlags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        distanceM: (j['distanceM'] as num?)?.toDouble(),
        employeeName: j['employeeName'],
        photoRef: j['photoRef'],
        workplaceName: j['workplaceName'],
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        qrOk: j['qrOk'] as bool?,
        offline: j['offline'] == true,
      );
}

class CheckinChallenge {
  final String nonce;
  final String challenge; // 'blink' | 'turn_left' | 'turn_right' | 'smile'
  final String type;
  final int serverTime;
  final int expiresAt;
  final Map<String, dynamic>? workplace;

  CheckinChallenge({
    required this.nonce,
    required this.challenge,
    required this.type,
    required this.serverTime,
    required this.expiresAt,
    this.workplace,
  });

  factory CheckinChallenge.fromJson(Map<String, dynamic> j) => CheckinChallenge(
        nonce: j['nonce'],
        challenge: j['challenge'],
        type: j['type'],
        serverTime: j['serverTime'],
        expiresAt: j['expiresAt'],
        workplace: j['workplace'],
      );
}

class CheckinResult {
  final String status;
  final String message;
  final double? similarity;
  final int riskScore;
  final List<String> riskFlags;
  final int? distanceM;

  CheckinResult({
    required this.status,
    required this.message,
    this.similarity,
    required this.riskScore,
    required this.riskFlags,
    this.distanceM,
  });

  bool get confirmed => status == 'confirmed';

  factory CheckinResult.fromJson(Map<String, dynamic> j) => CheckinResult(
        status: j['status'],
        message: j['message'] ?? '',
        similarity: (j['similarity'] as num?)?.toDouble(),
        riskScore: j['riskScore'] ?? 0,
        riskFlags: (j['riskFlags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        distanceM: j['distanceM'],
      );
}

class Workplace {
  final int id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final int radiusM;
  final bool requireQr;
  Workplace({required this.id, required this.name, this.address, this.lat, this.lng, required this.radiusM, this.requireQr = false});
  factory Workplace.fromJson(Map<String, dynamic> j) => Workplace(
        id: j['id'], name: j['name'], address: j['address'],
        lat: (j['lat'] as num?)?.toDouble(), lng: (j['lng'] as num?)?.toDouble(),
        radiusM: j['radiusM'] ?? 150, requireQr: j['requireQr'] ?? false,
      );
}
