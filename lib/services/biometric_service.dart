import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// 生物识别服务
/// 封装 local_auth，提供统一的认证入口
class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// 检查设备是否支持生物识别
  static Future<BiometricCheckResult> checkBiometrics() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      final List<BiometricType> available = await _auth.getAvailableBiometrics();

      return BiometricCheckResult(
        canCheck: canCheck,
        isSupported: isSupported,
        availableBiometrics: available,
      );
    } on PlatformException catch (e) {
      return BiometricCheckResult(
        canCheck: false,
        isSupported: false,
        availableBiometrics: [],
        error: e.message,
      );
    }
  }

  /// 执行生物识别验证
  /// [reason] 显示给用户的提示文案
  /// [biometricOnly] 是否仅允许生物识别（不允许 PIN/密码兜底）
  static Future<BiometricAuthResult> authenticate({
    String reason = '验证身份以继续',
    bool biometricOnly = false,
  }) async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: true,          // 切后台再切回，验证不中断
          biometricOnly: biometricOnly,
          sensitiveTransaction: false,
          useErrorDialogs: true,
        ),
      );

      return BiometricAuthResult(
        success: didAuthenticate,
        error: null,
      );
    } on PlatformException catch (e) {
      String message;
      switch (e.code) {
        case 'NotAvailable':
          message = '生物识别不可用，请检查是否已录入指纹或面容';
          break;
        case 'NotEnrolled':
          message = '设备未录入生物特征，请先在系统设置中添加';
          break;
        case 'LockedOut':
          message = '验证失败次数过多，请稍后再试';
          break;
        case 'PermanentlyLockedOut':
          message = '生物识别已锁定，请在系统设置中重新开启';
          break;
        default:
          message = e.message ?? '验证失败';
      }
      return BiometricAuthResult(success: false, error: message);
    }
  }
}

// ════════════════════════════════════════════════════
// 数据结构
// ════════════════════════════════════════════════════

class BiometricCheckResult {
  final bool canCheck;
  final bool isSupported;
  final List<BiometricType> availableBiometrics;
  final String? error;

  BiometricCheckResult({
    required this.canCheck,
    required this.isSupported,
    required this.availableBiometrics,
    this.error,
  });

  /// 是否有可用的生物识别方式
  bool get hasBiometrics => canCheck && isSupported && availableBiometrics.isNotEmpty;

  /// 是否支持指纹
  bool get hasFingerprint =>
      availableBiometrics.contains(BiometricType.fingerprint) ||
      availableBiometrics.contains(BiometricType.strong);

  /// 是否支持面容 / Face ID
  bool get hasFaceId =>
      availableBiometrics.contains(BiometricType.face) ||
      availableBiometrics.contains(BiometricType.strong);

  /// 获取友好的生物识别类型描述
  String get biometricLabel {
    if (hasFaceId && hasFingerprint) return '指纹或面容';
    if (hasFaceId) return '面容识别';
    if (hasFingerprint) return '指纹识别';
    return '生物识别';
  }
}

class BiometricAuthResult {
  final bool success;
  final String? error;

  BiometricAuthResult({required this.success, this.error});
}
