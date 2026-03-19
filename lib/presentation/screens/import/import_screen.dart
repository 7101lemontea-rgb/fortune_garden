// lib/presentation/screens/import/import_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../domain/entities/parsed_transaction.dart';  // ← ImportResult
import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../providers/app_providers.dart';

// ── 계좌 + 파서 상태 모델 ──────────────────────────────────
class _AccountWithParser {
  const _AccountWithParser({
    required this.account,
    required this.profileName,
    required this.profileColor,
    required this.hasParser,
  });
  final Account account;
  final String  profileName;
  final String  profileColor;
  final bool    hasParser;
}

// ── Provider ──────────────────────────────────────────────
final _importAccountsProvider =
    FutureProvider.autoDispose<List<_AccountWithParser>>((ref) async {
  final profileRepo = ref.read(profileRepositoryProvider);
  final accountRepo = ref.read(accountRepositoryProvider);
  final parserRepo  = ref.read(csvParserProfileRepositoryProvider);

  final profiles = await profileRepo.getAll();
  final result   = <_AccountWithParser>[];

  for (final p in profiles) {
    final accounts = await accountRepo.getByProfile(p.id);
    for (final a in accounts) {
      final parser = await parserRepo.getByInstitution(a.institutionCode);
      result.add(_AccountWithParser(
        account:      a,
        profileName:  p.name,
        profileColor: p.colorHex,
        hasParser:    parser != null,
      ));
    }
  }
  return result;
});

// ── 화면 ──────────────────────────────────────────────────
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  File?   _pickedFile;
  int?    _selectedAccountId;
  String? _selectedInstitutionCode;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result?.files.single.path != null) {
      setState(() => _pickedFile = File(result!.files.single.path!));
    }
  }

  Future<void> _import(List<_AccountWithParser> accounts) async {
    if (_pickedFile == null || _selectedAccountId == null) return;
    final ap = accounts.firstWhere(
        (a) => a.account.id == _selectedAccountId);
    await ref.read(csvImportStateProvider.notifier).execute(
      file:            _pickedFile!,
      profileId:       ap.account.profileId,
      accountId:       ap.account.id,
      institutionCode: ap.account.institutionCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final importState   = ref.watch(csvImportStateProvider);
    final accountsAsync = ref.watch(_importAccountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('CSV 파일 가져오기')),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('오류: $e')),
        data: (accounts) {
          if (accounts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_outlined,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('등록된 계좌가 없습니다',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    const Text(
                      '계좌 관리 탭에서 계좌를 먼저 등록해주세요.\n'
                      '개발 모드에서는 앱 재시작 시 임시 계좌가 생성됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          final selectedAp = _selectedAccountId != null
              ? accounts
                  .where((a) => a.account.id == _selectedAccountId)
                  .firstOrNull
              : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Step 1: 계좌 선택
              Text('Step 1  계좌 선택',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...accounts.map((ap) {
                final isSelected =
                    ap.account.id == _selectedAccountId;
                final color = Color(int.parse(
                    'FF${ap.profileColor.replaceAll('#', '')}',
                    radix: 16));
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: isSelected
                        ? BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .primary,
                            width: 2)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                        backgroundColor: color, radius: 14),
                    title: Text(ap.account.alias ??
                        ap.account.institutionCode),
                    subtitle: Text(
                        '${ap.profileName}  ·  ${ap.account.institutionCode}'),
                    trailing: ap.hasParser
                        ? const Icon(Icons.check_circle_outline,
                            color: Colors.green, size: 20)
                        : const Tooltip(
                            message: '파서 프로필 미등록',
                            child: Icon(
                                Icons.warning_amber_outlined,
                                color: Colors.orange,
                                size: 20),
                          ),
                    selected: isSelected,
                    onTap: importState.isImporting
                        ? null
                        : () => setState(() {
                              _selectedAccountId = ap.account.id;
                              _selectedInstitutionCode =
                                  ap.account.institutionCode;
                            }),
                  ),
                );
              }),

              // 파서 없음 경고
              if (selectedAp != null && !selectedAp.hasParser)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_outlined,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${selectedAp.account.institutionCode} 기관의 파서 프로필이 없습니다.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Step 2: 파일 선택
              Text('Step 2  파일 선택',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    importState.isImporting ? null : _pickFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  _pickedFile == null
                      ? 'CSV 파일 선택'
                      : _pickedFile!.path
                          .split(Platform.pathSeparator)
                          .last,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  alignment: Alignment.centerLeft,
                ),
              ),
              if (_pickedFile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _pickedFile!.path,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              const SizedBox(height: 24),

              // 가져오기 버튼
              FilledButton.icon(
                onPressed: (_pickedFile != null &&
                        _selectedAccountId != null &&
                        !importState.isImporting)
                    ? () => _import(accounts)
                    : null,
                icon: importState.isImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : const Icon(Icons.download_outlined),
                label: Text(importState.isImporting
                    ? '가져오는 중...'
                    : '가져오기 시작'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),

              const SizedBox(height: 24),

              // 완료 결과
              if (importState.status == ImportStatus.done &&
                  importState.result != null) ...[
                _ResultCard(result: importState.result!),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    ref
                        .read(csvImportStateProvider.notifier)
                        .reset();
                    setState(() => _pickedFile = null);
                  },
                  child: const Text('다른 파일 가져오기'),
                ),
              ],

              // 오류
              if (importState.status == ImportStatus.error) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('가져오기 실패',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red)),
                      const SizedBox(height: 8),
                      Text(importState.errorMessage ?? '',
                          style:
                              const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref
                      .read(csvImportStateProvider.notifier)
                      .reset(),
                  child: const Text('다시 시도'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ── 결과 카드 ──────────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final ImportResult result;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('가져오기 완료',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green)),
              ],
            ),
            const Divider(height: 20),
            _Row('전체 행',     '${result.totalRows}건'),
            _Row('신규 저장',   '${result.newRows}건',      Colors.green),
            _Row('중복 건너뜀', '${result.duplicateRows}건'),
            if (result.errorRows > 0)
              _Row('오류', '${result.errorRows}건', Colors.red),
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, [this.color]);
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 13)),
          ],
        ),
      );
}
