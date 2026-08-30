// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 本地存储静态加密（local_encryption.dart）
//
// 对前端落盘的个人数据（本地 SQLite 记忆 content）做 AES-256-CBC
// 对称加密，满足 PIPL「个人信息存储加密」要求（at-rest encryption）。
//
// 密钥管理：
//   - 移动端：密钥存于 flutter_secure_storage（Android 加密 SharedPreferences /
//     iOS Keychain），不可被轻易提取；
//   - Web 端：flutter_secure_storage 回退为 localStorage 加密存储，安全性较弱，
//     仅提供基础防护（Web 平台本身无安全飞地）。
//
// 实现：基于 pointycastle（AESFastEngine + CBC + PKCS7），避免引入与
// livekit_client 冲突的 encrypt 包（两者对 pointycastle 版本要求不兼容）。
//
// 兼容：解密失败（旧明文数据 / 损坏行）一律原样返回，保证老库不崩。
//
// 上游：ChatLocalDataSource（对话历史 content）、MemoryService（记忆 content）。
// 下游：flutter_secure_storage（密钥存放）、pointycastle（AES 实现）。
//
// 关键点：
//   1. 每次加密都用 Random.secure() 生成新 IV，IV 以明文拼在密文前 16 字节，
//      解密时按 `iv(16) + ciphertext` 切片。
//   2. 密钥按安装生成并缓存在内存，卸载重装后旧密文不可解——
//      因此 decrypt 必须容错，不能抛异常。
//   3. 本项目已移除 Web 平台支持，上述 Web 端说明仅为历史记录。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';

/// 本地静态加密工具类（无状态，全部静态方法）
///
/// 用于 SQLite 落盘的敏感字段（对话正文、记忆正文）加解密，
/// 满足个人信息「存储加密」的合规要求。
class LocalEncryption {
  /// 安全存储中保存密钥的键名。
  static const String _keyTag = 'zhuyu_local_enc_key';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Uint8List? _cachedKey;
  static final Random _random = Random.secure();

  /// 获取或生成 32 字节 AES 密钥（base64 持久化到安全存储）
  static Future<Uint8List> _getKey() async {
    if (_cachedKey != null) return _cachedKey!;
    final existing = await _storage.read(key: _keyTag);
    if (existing != null && existing.isNotEmpty) {
      try {
        final bytes = base64Decode(existing);
        if (bytes.length == 32) {
          _cachedKey = bytes;
          return _cachedKey!;
        }
      } catch (_) {
        // 损坏则重新生成
      }
    }
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    _cachedKey = bytes;
    await _storage.write(key: _keyTag, value: base64Encode(bytes));
    return _cachedKey!;
  }

  /// 单次 AES-256-CBC（PKCS7）加/解密
  static Uint8List _aes(
    Uint8List key,
    Uint8List iv,
    Uint8List data,
    bool forEncrypt,
  ) {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            forEncrypt,
            PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(key), iv),
              null,
            ),
          );
    return cipher.process(data);
  }

  /// 加密 UTF-8 明文，返回 base64(iv16 + ciphertext)。空串直接返回空。
  static Future<String> encrypt(String plaintext) async {
    if (plaintext.isEmpty) return '';
    final key = await _getKey();
    final iv = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final ct = _aes(key, iv, Uint8List.fromList(utf8.encode(plaintext)), true);
    final combined = Uint8List(16 + ct.length);
    combined.setRange(0, 16, iv);
    combined.setRange(16, combined.length, ct);
    return base64Encode(combined);
  }

  /// 解密 token。空串返回空；非 token / 损坏一律原样返回（兼容旧明文）。
  static Future<String> decrypt(String token) async {
    if (token.isEmpty) return '';
    try {
      final raw = base64Decode(token);
      if (raw.length < 16) return token; // 明文兼容
      final key = await _getKey();
      final iv = raw.sublist(0, 16);
      final pt = _aes(key, iv, raw.sublist(16), false);
      return utf8.decode(pt);
    } catch (_) {
      return token;
    }
  }
}
