// lib/presentation/screens/setup/setup_screen.dart
// SCR-001 /setup — 초기 설정/프로필 생성

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/profile/profile_use_case.dart';
import '../../providers/app_providers.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _p1NameCtrl   = TextEditingController(text: '나');
  final _p2NameCtrl   = TextEditingController(text: '파트너');
  Color _p1Color = const Color(0xFF2E6DA4);
  Color _p2Color = const Color(0xFFE65100);
  bool  _saving  = false;

  @override
  void dispose() {
    _p1NameCtrl.dispose();
    _p2NameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_p1NameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final useCase = ref.read(profileUseCaseProvider);

    await useCase.upsert(
      id:       1,
      name:     _p1NameCtrl.text.trim(),
      colorHex: '#${_p1Color.value.toRadixString(16).substring(2).toUpperCase()}',
    );
    await useCase.upsert(
      id:       2,
      name:     _p2NameCtrl.text.trim().isEmpty ? '파트너' : _p2NameCtrl.text.trim(),
      colorHex: '#${_p2Color.value.toRadixString(16).substring(2).toUpperCase()}',
    );

    // activeProfileProvider 갱신 후 라우터가 /dashboard로 리디렉트
    ref.invalidate(activeProfileProvider);
    if (mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fortune Garden 시작하기')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('프로필 설정',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('두 사람의 이름과 구분 색상을 입력해주세요.'),
            const SizedBox(height: 24),

            // 프로필 1
            _ProfileForm(
              label:      '프로필 1 (나)',
              controller: _p1NameCtrl,
              color:      _p1Color,
              onColorChanged: (c) => setState(() => _p1Color = c),
            ),
            const SizedBox(height: 16),

            // 프로필 2
            _ProfileForm(
              label:      '프로필 2 (파트너)',
              controller: _p2NameCtrl,
              color:      _p2Color,
              onColorChanged: (c) => setState(() => _p2Color = c),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('시작하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.label,
    required this.controller,
    required this.color,
    required this.onColorChanged,
  });

  final String              label;
  final TextEditingController controller;
  final Color               color;
  final ValueChanged<Color> onColorChanged;

  static const _palette = [
    Color(0xFF2E6DA4), Color(0xFFE65100), Color(0xFF2E7D32),
    Color(0xFF6A1B9A), Color(0xFF00838F), Color(0xFF4E342E),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('색상'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _palette.map((c) => GestureDetector(
                onTap: () => onColorChanged(c),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: color == c
                        ? Border.all(color: Colors.black, width: 2)
                        : null,
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
