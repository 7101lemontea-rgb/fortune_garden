// lib/presentation/screens/pin/pin_screen.dart
//
// PIN 입력 화면.
// PinScreenMode에 따라 3가지 모드로 동작:
//   - unlock   : 잠금 해제 (현재 PIN 입력)
//   - setup    : 신규 PIN 설정 (입력 → 확인 2단계)
//   - change   : PIN 변경 (현재 PIN 확인 → 신규 입력 → 확인 3단계)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/pin_notifier.dart';

enum PinScreenMode { unlock, setup, change }

class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({
    super.key,
    required this.mode,
    this.onSuccess,
  });

  final PinScreenMode mode;

  /// 성공 콜백. 잠금 해제/설정 완료 후 호출됨.
  /// null이면 Navigator.pop() 실행.
  final VoidCallback? onSuccess;

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  static const _pinLength = 4;

  String _input = '';
  String _firstPin = ''; // setup/change에서 첫 번째 입력 저장
  bool _isConfirmStep = false; // 확인 입력 단계 여부
  bool _isVerifyStep = false; // change 모드: 기존 PIN 검증 단계
  String? _errorMessage;
  bool _isProcessing = false;

  String get _title {
    if (widget.mode == PinScreenMode.unlock) return 'PIN 입력';
    if (widget.mode == PinScreenMode.setup) {
      return _isConfirmStep ? 'PIN 확인' : 'PIN 설정';
    }
    // change
    if (_isVerifyStep) return '현재 PIN 입력';
    return _isConfirmStep ? '새 PIN 확인' : '새 PIN 입력';
  }

  String get _subtitle {
    if (widget.mode == PinScreenMode.unlock) return '앱 잠금을 해제하려면 PIN을 입력하세요';
    if (widget.mode == PinScreenMode.setup) {
      return _isConfirmStep ? '동일한 PIN을 다시 입력하세요' : '사용할 4자리 PIN을 입력하세요';
    }
    if (_isVerifyStep) return '현재 PIN을 입력하세요';
    return _isConfirmStep ? '새 PIN을 다시 입력하세요' : '새 4자리 PIN을 입력하세요';
  }

  void _onKeyTap(String key) {
    if (_isProcessing) return;
    if (key == 'del') {
      if (_input.isNotEmpty) {
        setState(() {
          _input = _input.substring(0, _input.length - 1);
          _errorMessage = null;
        });
      }
      return;
    }

    if (_input.length >= _pinLength) return;

    setState(() {
      _input += key;
      _errorMessage = null;
    });

    if (_input.length == _pinLength) {
      _onPinComplete(_input);
    }
  }

  Future<void> _onPinComplete(String pin) async {
    setState(() => _isProcessing = true);

    try {
      switch (widget.mode) {
        case PinScreenMode.unlock:
          await _handleUnlock(pin);
        case PinScreenMode.setup:
          await _handleSetup(pin);
        case PinScreenMode.change:
          await _handleChange(pin);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── unlock ──────────────────────────────────────────────

  Future<void> _handleUnlock(String pin) async {
    final success = await ref.read(pinLockProvider.notifier).unlock(pin);
    if (!mounted) return;

    if (success) {
      widget.onSuccess?.call();
    } else {
      setState(() {
        _input = '';
        _errorMessage = '잘못된 PIN입니다. 다시 입력하세요.';
      });
    }
  }

  // ── setup ───────────────────────────────────────────────

  Future<void> _handleSetup(String pin) async {
    if (!_isConfirmStep) {
      // 1단계: 첫 입력 저장 후 확인 단계로
      setState(() {
        _firstPin = pin;
        _input = '';
        _isConfirmStep = true;
      });
      return;
    }

    // 2단계: 일치 여부 확인
    if (pin != _firstPin) {
      setState(() {
        _input = '';
        _firstPin = '';
        _isConfirmStep = false;
        _errorMessage = 'PIN이 일치하지 않습니다. 처음부터 다시 입력하세요.';
      });
      return;
    }

    await ref.read(pinLockProvider.notifier).enablePin(pin);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN이 설정되었습니다')),
    );
    widget.onSuccess != null
        ? widget.onSuccess!()
        : Navigator.of(context).pop(true);
  }

  // ── change ──────────────────────────────────────────────

  Future<void> _handleChange(String pin) async {
    // 1단계: 기존 PIN 검증
    if (_isVerifyStep) {
      final success = await ref.read(pinLockProvider.notifier).unlock(pin);
      if (!mounted) return;
      if (!success) {
        setState(() {
          _input = '';
          _errorMessage = '현재 PIN이 올바르지 않습니다.';
        });
        return;
      }
      // 잠금은 해제하지 않고 변경 단계로만 진행
      await ref.read(pinLockProvider.notifier).disablePin();
      setState(() {
        _input = '';
        _isVerifyStep = false;
        _isConfirmStep = false;
      });
      return;
    }

    // 2단계: 새 PIN 첫 입력
    if (!_isConfirmStep) {
      setState(() {
        _firstPin = pin;
        _input = '';
        _isConfirmStep = true;
      });
      return;
    }

    // 3단계: 새 PIN 확인
    if (pin != _firstPin) {
      setState(() {
        _input = '';
        _firstPin = '';
        _isConfirmStep = false;
        _errorMessage = 'PIN이 일치하지 않습니다. 다시 입력하세요.';
      });
      return;
    }

    await ref.read(pinLockProvider.notifier).enablePin(pin);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN이 변경되었습니다')),
    );
    widget.onSuccess != null
        ? widget.onSuccess!()
        : Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: widget.mode == PinScreenMode.unlock
          ? null // 잠금 화면은 AppBar 없음
          : AppBar(
              title: Text(_title),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // ── 타이틀 / 서브타이틀 ──────────────────────────
            if (widget.mode == PinScreenMode.unlock) ...[
              Icon(Icons.lock_outline, size: 48, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(_title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
            ],
            Text(
              _subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),

            // ── PIN 도트 표시 ────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength, (i) {
                final filled = i < _input.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? colorScheme.primary : Colors.transparent,
                    border: Border.all(
                      color: filled ? colorScheme.primary : colorScheme.outline,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // ── 에러 메시지 ──────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _errorMessage != null
                  ? Text(
                      _errorMessage!,
                      key: ValueKey(_errorMessage),
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    )
                  : const SizedBox(height: 18),
            ),

            const Spacer(),

            // ── 숫자 키패드 ──────────────────────────────────
            _PinKeypad(onKeyTap: _onKeyTap),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── 키패드 위젯 ──────────────────────────────────────────────

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({required this.onKeyTap});
  final ValueChanged<String> onKeyTap;

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', 'del'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: _keys.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) return const SizedBox(width: 72, height: 72);
              return _KeyButton(label: key, onTap: () => onKeyTap(key));
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDel = label == 'del';
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(36),
          child: Center(
            child: isDel
                ? Icon(Icons.backspace_outlined,
                    color: colorScheme.onSurface, size: 24)
                : Text(
                    label,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w400,
                        ),
                  ),
          ),
        ),
      ),
    );
  }
}
