// lib/presentation/screens/profiles/profiles_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/profile/profile_use_case.dart';
import '../../../data/database/app_database.dart';
import '../../providers/app_providers.dart';

// ── Provider (화면 전용) ───────────────────────────────────
final _profilesProvider =
    FutureProvider.autoDispose<List<Profile>>((ref) =>
        ref.read(profileUseCaseProvider).getAll());

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(_profilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('프로필 관리')),
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('오류: $e')),
        data: (profiles) => ListView(
          padding: const EdgeInsets.all(16),
          children: profiles
              .map((p) => _ProfileCard(profile: p))
              .toList(),
        ),
      ),
    );
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final _nameCtrl =
      TextEditingController(text: widget.profile.name);
  late Color _color = _hexToColor(widget.profile.colorHex);
  bool _editing = false;

  static const _palette = [
    Color(0xFF2E6DA4), Color(0xFFE65100), Color(0xFF2E7D32),
    Color(0xFF6A1B9A), Color(0xFF00838F), Color(0xFF4E342E),
  ];

  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  Future<void> _save() async {
    await ref.read(profileUseCaseProvider).upsert(
      id:       widget.profile.id,
      name:     _nameCtrl.text.trim(),
      colorHex:
          '#${_color.value.toRadixString(16).substring(2).toUpperCase()}',
    );
    ref.invalidate(activeProfileProvider);
    ref.invalidate(_profilesProvider);
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: _color, radius: 18),
                const SizedBox(width: 12),
                Text('프로필 ${widget.profile.id}',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: Icon(
                      _editing ? Icons.close : Icons.edit_outlined),
                  onPressed: () =>
                      setState(() => _editing = !_editing),
                ),
              ],
            ),
            if (_editing) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '이름',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: _palette
                    .map((c) => GestureDetector(
                          onTap: () => setState(() => _color = c),
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: _color == c
                                  ? Border.all(
                                      color: Colors.black, width: 2)
                                  : null,
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('저장'),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(widget.profile.name,
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
          ],
        ),
      ),
    );
  }
}
