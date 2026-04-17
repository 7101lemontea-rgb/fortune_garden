// lib/core/security/account_encryption_service.dart
//
// 계좌번호 AES-256-CBC 암호화/복호화 서비스.
//
// 키 관리:
//   - 앱 최초 실행 시 256비트 랜덤 키를 생성해 flutter_secure_storage에 저장.
//   - 이후 실행에서는 저장된 키를 재사용.
//   - 키 분실(앱 데이터 초기화 등) 시 기존 암호문은 복호화 불가 → DB 재입력 필요.
//
// 저장 형식 (Uint8List):
//   [ IV 16바이트 | 암호문 n바이트 ]

import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AccountEncryptionService {
  AccountEncryptionService._();

  static const _keyAlias = 'fortune_garden_account_enc_key';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── 키 획득 (없으면 생성) ──────────────────────────────────
  static Future<Key> _getOrCreateKey() async {
    String? keyBase64 = await _storage.read(key: _keyAlias);

    if (keyBase64 == null) {
      final random = Random.secure();
      final keyBytes = Uint8List.fromList(
        List.generate(32, (_) => random.nextInt(256)),
      );
      keyBase64 = Key(keyBytes).base64;
      await _storage.write(key: _keyAlias, value: keyBase64);
    }

    return Key.fromBase64(keyBase64);
  }

  // ── 암호화 ─────────────────────────────────────────────────
  /// 계좌번호 문자열을 암호화해 Uint8List로 반환.
  /// 반환값 형식: [ IV(16B) | 암호문(nB) ]
  static Future<Uint8List> encrypt(String accountNumber) async {
    final key = await _getOrCreateKey();
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(accountNumber, iv: iv);

    // IV + 암호문 결합
    final result = Uint8List(16 + encrypted.bytes.length);
    result.setRange(0, 16, iv.bytes);
    result.setRange(16, result.length, encrypted.bytes);
    return result;
  }

  // ── 복호화 ─────────────────────────────────────────────────
  /// encrypt()로 생성된 Uint8List를 복호화해 원문 문자열 반환.
  /// 키 불일치 또는 데이터 손상 시 null 반환.
  static Future<String?> decrypt(Uint8List data) async {
    // DEV placeholder 또는 너무 짧은 데이터는 null 반환
    if (data.length <= 16) return null;

    try {
      final key = await _getOrCreateKey();
      final iv = IV(data.sublist(0, 16));
      final cipherBytes = Encrypted(data.sublist(16));
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      return encrypter.decrypt(cipherBytes, iv: iv);
    } catch (_) {
      return null;
    }
  }

  // ── DEV placeholder 판별 ───────────────────────────────────
  /// 기존 DEV placeholder 값인지 확인 (마이그레이션 용도).
  static bool isDevPlaceholder(Uint8List data) {
    try {
      final str = String.fromCharCodes(data);
      return str.startsWith('DEV:');
    } catch (_) {
      return false;
    }
  }
}
