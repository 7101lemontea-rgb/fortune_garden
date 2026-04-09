// lib/presentation/providers/pin_notifier.dart
//
// PIN 잠금 기능 상태 관리.
//
// 상태 흐름:
//   앱 시작 → pinLockProvider 초기화 → pin_enabled=true 이면 locked=true
//   백그라운드 전환 → _backgroundTime 기록
//   포그라운드 복귀 → auto_lock_seconds 경과 여부 확인 → 초과 시 locked=true
//   PIN 입력 성공 → locked=false

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';

// ── State ────────────────────────────────────────────────────

class PinLockState {
  const PinLockState({
    this.isLocked = false,
    this.isPinEnabled = false,
    this.isLoading = true,
  });

  /// 현재 잠금 여부 — true이면 PinLockOverlay 표시
  final bool isLocked;

  /// PIN 기능 활성화 여부 (app_settings.pin_enabled)
  final bool isPinEnabled;

  /// 초기 설정값 로딩 중 여부
  final bool isLoading;

  PinLockState copyWith({
    bool? isLocked,
    bool? isPinEnabled,
    bool? isLoading,
  }) =>
      PinLockState(
        isLocked: isLocked ?? this.isLocked,
        isPinEnabled: isPinEnabled ?? this.isPinEnabled,
        isLoading: isLoading ?? this.isLoading,
      );
}

// ── Notifier ─────────────────────────────────────────────────

class PinLockNotifier extends StateNotifier<PinLockState> {
  PinLockNotifier(this._ref) : super(const PinLockState()) {
    _init();
  }

  final Ref _ref;

  /// 백그라운드 진입 시각 (포그라운드 복귀 시 경과 시간 계산용)
  DateTime? _backgroundTime;

  // ── 초기화 ───────────────────────────────────────────────

  Future<void> _init() async {
    final repo = _ref.read(settingsRepositoryProvider);
    final pinEnabled =
        await repo.get('pin_enabled', defaultValue: 'false') == 'true';
    final hasPin = (await repo.get('pin_hash', defaultValue: null)) != null;

    // PIN이 활성화되어 있고 해시가 저장된 경우에만 잠금
    final shouldLock = pinEnabled && hasPin;

    state = PinLockState(
      isLocked: shouldLock,
      isPinEnabled: pinEnabled,
      isLoading: false,
    );
  }

  // ── 백그라운드 / 포그라운드 처리 ────────────────────────────

  /// 앱이 백그라운드로 전환될 때 호출
  void onBackground() {
    if (state.isPinEnabled) {
      _backgroundTime = DateTime.now();
    }
  }

  /// 앱이 포그라운드로 복귀할 때 호출
  Future<void> onForeground() async {
    if (!state.isPinEnabled) return;
    if (_backgroundTime == null) return;

    final repo = _ref.read(settingsRepositoryProvider);
    final secondsStr = await repo.get('auto_lock_seconds', defaultValue: '30');
    final autoLockSeconds = int.tryParse(secondsStr ?? '30') ?? 30;

    final elapsed = DateTime.now().difference(_backgroundTime!).inSeconds;

    if (elapsed >= autoLockSeconds) {
      state = state.copyWith(isLocked: true);
    }
    _backgroundTime = null;
  }

  // ── PIN 검증 ─────────────────────────────────────────────

  /// 입력된 PIN이 저장된 해시와 일치하면 잠금 해제. 결과 반환.
  Future<bool> unlock(String pin) async {
    final repo = _ref.read(settingsRepositoryProvider);
    final savedHash = await repo.get('pin_hash', defaultValue: null);

    if (savedHash == null) return false;

    final inputHash = _hashPin(pin);
    if (inputHash == savedHash) {
      state = state.copyWith(isLocked: false);
      return true;
    }
    return false;
  }

  // ── PIN 설정 ─────────────────────────────────────────────

  /// PIN 활성화 + 해시 저장
  Future<void> enablePin(String pin) async {
    final repo = _ref.read(settingsRepositoryProvider);
    await repo.set('pin_hash', _hashPin(pin));
    await repo.set('pin_enabled', 'true');
    state = state.copyWith(isPinEnabled: true);
  }

  /// PIN 비활성화 + 해시 삭제
  Future<void> disablePin() async {
    final repo = _ref.read(settingsRepositoryProvider);
    await repo.set('pin_enabled', 'false');
    await repo.delete('pin_hash');
    state = state.copyWith(isPinEnabled: false, isLocked: false);
  }

  // ── 헬퍼 ────────────────────────────────────────────────

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }
}

// ── Provider ─────────────────────────────────────────────────

final pinLockProvider =
    StateNotifierProvider<PinLockNotifier, PinLockState>((ref) {
  return PinLockNotifier(ref);
});
