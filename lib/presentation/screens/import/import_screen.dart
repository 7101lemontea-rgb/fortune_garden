// lib/presentation/screens/import/import_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/parsed_transaction.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────
// 입력 방식
// ─────────────────────────────────────────────────────────

/// 거래내역을 가져오는 방식.
/// 은행 웹 화면의 표를 복사해 붙여넣는 [paste]가 기본값.
/// 엑셀 변환·인코딩 문제가 없어 파일 방식보다 단계가 짧다.
enum _ImportMode {
  paste('붙여넣기', Icons.content_paste_outlined, 'paste'),
  file('CSV 파일', Icons.upload_file_outlined, 'file');

  const _ImportMode(this.label, this.icon, this.sourceType);
  final String label;
  final IconData icon;

  /// csv_parser_profiles.source_type 값
  final String sourceType;
}

// ─────────────────────────────────────────────────────────
// 계좌 + 파서 상태 모델
// ─────────────────────────────────────────────────────────

class _AccountWithParser {
  const _AccountWithParser({
    required this.account,
    required this.profileName,
    required this.profileColor,
    required this.hasFileParser,
    required this.hasPasteParser,
  });
  final Account account;
  final String profileName;
  final String profileColor;
  final bool hasFileParser;
  final bool hasPasteParser;

  /// 선택한 입력 방식에 해당하는 파서 프로필이 등록되어 있는지.
  bool hasParserFor(_ImportMode mode) =>
      mode == _ImportMode.paste ? hasPasteParser : hasFileParser;
}

// ─────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────

final _importAccountsProvider =
    FutureProvider.autoDispose<List<_AccountWithParser>>((ref) async {
  final profileRepo = ref.read(profileRepositoryProvider);
  final accountRepo = ref.read(accountRepositoryProvider);
  final parserRepo = ref.read(csvParserProfileRepositoryProvider);

  final profiles = await profileRepo.getAll();
  final result = <_AccountWithParser>[];

  for (final p in profiles) {
    final accounts = await accountRepo.getByProfile(p.id);
    for (final a in accounts) {
      // 입력 방식별로 프로필이 따로 등록되므로 각각 확인한다.
      final fileParser = await parserRepo.getByInstitution(
        a.institutionCode,
        sourceType: 'file',
      );
      final pasteParser = await parserRepo.getByInstitution(
        a.institutionCode,
        sourceType: 'paste',
      );
      result.add(_AccountWithParser(
        account: a,
        profileName: p.name,
        profileColor: p.colorHex,
        hasFileParser: fileParser != null,
        hasPasteParser: pasteParser != null,
      ));
    }
  }
  return result;
});

// ─────────────────────────────────────────────────────────
// SCR-008 메인 화면
// ─────────────────────────────────────────────────────────

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  // 헤더 배경색 상수
  static const _headerBgLight = Color(0xFF2d4a22);
  static const _headerBgDark = Color(0xFF051a0f);

  _ImportMode _mode = _ImportMode.paste;
  File? _pickedFile;
  int? _selectedAccountId;

  final _pasteController = TextEditingController();

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  /// 선택한 방식에 입력이 채워졌는지 여부.
  bool get _hasInput => _mode == _ImportMode.paste
      ? _pasteController.text.trim().isNotEmpty
      : _pickedFile != null;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result?.files.single.path != null) {
      setState(() => _pickedFile = File(result!.files.single.path!));
    }
  }

  /// 클립보드 내용을 입력창에 붙여넣기.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;

    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('클립보드가 비어 있습니다.')),
      );
      return;
    }
    setState(() => _pasteController.text = text);
  }

  Future<void> _import(List<_AccountWithParser> accounts) async {
    if (!_hasInput || _selectedAccountId == null) return;
    final ap = accounts.firstWhere((a) => a.account.id == _selectedAccountId);
    final notifier = ref.read(csvImportStateProvider.notifier);

    if (_mode == _ImportMode.paste) {
      await notifier.executeFromText(
        content: _pasteController.text,
        profileId: ap.account.profileId,
        accountId: ap.account.id,
        institutionCode: ap.account.institutionCode,
      );
    } else {
      await notifier.execute(
        file: _pickedFile!,
        profileId: ap.account.profileId,
        accountId: ap.account.id,
        institutionCode: ap.account.institutionCode,
      );
    }
  }

  void _reset() {
    ref.read(csvImportStateProvider.notifier).reset();
    setState(() {
      _pickedFile = null;
      _selectedAccountId = null;
      _pasteController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final importState = ref.watch(csvImportStateProvider);
    final accountsAsync = ref.watch(_importAccountsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? _headerBgDark : _headerBgLight;

    return Scaffold(
      body: GrainOverlay(
        child: CustomScrollView(
          slivers: [
            // ── SliverAppBar ───────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: headerBg,
              foregroundColor: Colors.white,
              title: Text(
                '거래내역 가져오기',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      // fontStyle: FontStyle.italic,
                    ),
              ),
            ),

            // ── 본문 ──────────────────────────────────
            accountsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(child: Text('오류: $e')),
              ),
              data: (accounts) {
                if (accounts.isEmpty) {
                  return SliverFillRemaining(
                    child: _EmptyAccountsGuide(),
                  );
                }

                final selectedAp = _selectedAccountId != null
                    ? accounts
                        .where((a) => a.account.id == _selectedAccountId)
                        .firstOrNull
                    : null;

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── Step 1: 입력 방식 ────────────
                      _StepLabel(number: '1', title: '입력 방식'),
                      const SizedBox(height: 10),
                      _ModeSelector(
                        mode: _mode,
                        disabled: importState.isImporting,
                        onChanged: (m) => setState(() => _mode = m),
                      ),

                      const SizedBox(height: 24),

                      // ── Step 2: 계좌 선택 ────────────
                      _StepLabel(number: '2', title: '계좌 선택'),
                      const SizedBox(height: 10),
                      ...accounts.map((ap) => _AccountCard(
                            ap: ap,
                            hasParser: ap.hasParserFor(_mode),
                            isSelected: ap.account.id == _selectedAccountId,
                            disabled: importState.isImporting,
                            onTap: () => setState(() {
                              _selectedAccountId = ap.account.id;
                            }),
                          )),

                      // 파서 없음 경고
                      if (selectedAp != null &&
                          !selectedAp.hasParserFor(_mode)) ...[
                        const SizedBox(height: 4),
                        _WarningBanner(
                          '${selectedAp.account.institutionCode} 기관의 '
                          '${_mode.label} 파서 프로필이 없습니다.',
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ── Step 3: 내용 입력 ────────────
                      _StepLabel(
                        number: '3',
                        title: _mode == _ImportMode.paste
                            ? '거래내역 붙여넣기'
                            : '파일 선택',
                      ),
                      const SizedBox(height: 10),
                      if (_mode == _ImportMode.paste)
                        _PasteInput(
                          controller: _pasteController,
                          disabled: importState.isImporting,
                          onPasteTap: _pasteFromClipboard,
                          onClearTap: () =>
                              setState(() => _pasteController.clear()),
                          onChanged: () => setState(() {}),
                        )
                      else
                        _FilePickerButton(
                          pickedFile: _pickedFile,
                          disabled: importState.isImporting,
                          onTap: _pickFile,
                        ),

                      const SizedBox(height: 28),

                      // ── 가져오기 버튼 ────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: (_hasInput &&
                                  _selectedAccountId != null &&
                                  !importState.isImporting)
                              ? () => _import(accounts)
                              : null,
                          icon: importState.isImporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download_outlined),
                          label: Text(
                            importState.isImporting ? '가져오는 중...' : '가져오기 시작',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── 완료 결과 ────────────────────
                      if (importState.status == ImportStatus.done &&
                          importState.result != null) ...[
                        _ResultCard(result: importState.result!),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _reset,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: const Text('다른 파일 가져오기'),
                        ),
                      ],

                      // ── 오류 ─────────────────────────
                      if (importState.status == ImportStatus.error) ...[
                        _ErrorBanner(message: importState.errorMessage ?? ''),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () =>
                              ref.read(csvImportStateProvider.notifier).reset(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Step 레이블
// ─────────────────────────────────────────────────────────

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.number, required this.title});
  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 계좌 선택 카드
// ─────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.ap,
    required this.hasParser,
    required this.isSelected,
    required this.disabled,
    required this.onTap,
  });

  final _AccountWithParser ap;

  /// 현재 선택된 입력 방식에 맞는 파서 프로필이 있는지.
  final bool hasParser;
  final bool isSelected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final profileColor =
        Color(int.parse('FF${ap.profileColor.replaceAll('#', '')}', radix: 16));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide(color: cs.outlineVariant.withOpacity(0.6), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // 프로필 색상 아바타
              CircleAvatar(
                backgroundColor: profileColor,
                radius: 14,
                child: Text(
                  ap.profileName.isNotEmpty
                      ? ap.profileName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // 계좌명 + 부제
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ap.account.alias ?? ap.account.institutionCode,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ap.profileName}  ·  ${ap.account.institutionCode}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              // 파서 유무 아이콘
              if (hasParser)
                Icon(Icons.check_circle_outline, color: incomeColor, size: 20)
              else
                Tooltip(
                  message: '파서 프로필 미등록',
                  child: Icon(
                    Icons.warning_amber_outlined,
                    color: cs.tertiary,
                    size: 20,
                  ),
                ),

              // 선택 체크
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(Icons.radio_button_checked, color: cs.primary, size: 20),
              ] else ...[
                const SizedBox(width: 8),
                Icon(Icons.radio_button_unchecked,
                    color: cs.outlineVariant, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 입력 방식 선택
// ─────────────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.disabled,
    required this.onChanged,
  });

  final _ImportMode mode;
  final bool disabled;
  final ValueChanged<_ImportMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_ImportMode>(
            segments: _ImportMode.values
                .map((m) => ButtonSegment<_ImportMode>(
                      value: m,
                      label: Text(m.label),
                      icon: Icon(m.icon, size: 18),
                    ))
                .toList(),
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: disabled
                ? null
                : (set) => onChanged(set.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          mode == _ImportMode.paste
              ? '은행 거래내역 화면의 표를 복사해 붙여넣습니다. '
                  '엑셀 변환이 필요 없습니다.'
              : '엑셀에서 CSV로 저장한 파일을 선택합니다.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 거래내역 붙여넣기 입력
// ─────────────────────────────────────────────────────────

class _PasteInput extends StatelessWidget {
  const _PasteInput({
    required this.controller,
    required this.disabled,
    required this.onPasteTap,
    required this.onClearTap,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool disabled;
  final VoidCallback onPasteTap;
  final VoidCallback onClearTap;
  final VoidCallback onChanged;

  /// 입력된 줄 수 (빈 줄 제외). 표 머리글·메타 줄도 포함된 값.
  int get _lineCount => controller.text
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final hasText = controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: hasText
                ? incomeColor.withValues(alpha: 0.06)
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasText
                  ? incomeColor.withValues(alpha: 0.4)
                  : cs.outlineVariant,
              width: hasText ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: controller,
            enabled: !disabled,
            minLines: 6,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            style: Theme.of(context).textTheme.bodySmall,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintMaxLines: 4,
              hintText: '거래일시  거래구분  기재내용  출금금액  입금금액  잔액\n'
                  '2026.09.29 10:31:22  현카구매  주식회사 아성다이소  '
                  '15,200원  0원  1,382,866원',
              hintStyle: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(height: 8),

        // ── 보조 액션 ─────────────────────────────
        Row(
          children: [
            if (hasText)
              Text(
                '$_lineCount줄 입력됨',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: incomeColor),
              )
            else
              Text(
                '표 제목·조회기간 줄이 섞여 있어도 됩니다',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            const Spacer(),
            if (hasText)
              TextButton.icon(
                onPressed: disabled ? null : onClearTap,
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('지우기'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: cs.onSurfaceVariant,
                ),
              ),
            TextButton.icon(
              onPressed: disabled ? null : onPasteTap,
              icon: const Icon(Icons.content_paste_go_outlined, size: 16),
              label: const Text('클립보드에서'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 파일 선택 버튼
// ─────────────────────────────────────────────────────────

class _FilePickerButton extends StatelessWidget {
  const _FilePickerButton({
    required this.pickedFile,
    required this.disabled,
    required this.onTap,
  });

  final File? pickedFile;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final fileName = pickedFile?.path.split(Platform.pathSeparator).last;

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pickedFile != null
              ? incomeColor.withOpacity(0.06)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: pickedFile != null
                ? incomeColor.withOpacity(0.4)
                : cs.outlineVariant,
            width: pickedFile != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              pickedFile != null
                  ? Icons.description_outlined
                  : Icons.upload_file_outlined,
              color: pickedFile != null ? incomeColor : cs.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: pickedFile != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName ?? '',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: incomeColor,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '탭하여 다른 파일 선택',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    )
                  : Text(
                      'CSV 파일 선택',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 경고 배너 (파서 없음)
// ─────────────────────────────────────────────────────────

class _WarningBanner extends StatelessWidget {
  const _WarningBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // tertiary = 앰버 계열 (AppTheme에서 tertiary는 주황/갈색 계열)
    final warnColor = cs.tertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warnColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: warnColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: warnColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: warnColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 오류 배너
// ─────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: expenseColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: expenseColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: expenseColor, size: 18),
              const SizedBox(width: 8),
              Text(
                '가져오기 실패',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: expenseColor,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 완료 결과 카드
// ─────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: incomeColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: incomeColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: incomeColor, size: 20),
              const SizedBox(width: 8),
              Text(
                '가져오기 완료',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: incomeColor),
              ),
            ],
          ),
          Divider(
            height: 20,
            color: incomeColor.withOpacity(0.2),
          ),
          _ResultRow(
            label: '전체 행',
            value: '${result.totalRows}건',
            color: cs.onSurface,
          ),
          _ResultRow(
            label: '신규 저장',
            value: '${result.newRows}건',
            color: incomeColor,
          ),
          _ResultRow(
            label: '중복 건너뜀',
            value: '${result.duplicateRows}건',
            color: cs.onSurfaceVariant,
          ),
          if (result.errorRows > 0)
            _ResultRow(
              label: '오류',
              value: '${result.errorRows}건',
              color: expenseColor,
            ),

          // 잔액 흐름 검증 등 확인이 필요한 사항
          if (result.warnings.isNotEmpty) ...[
            Divider(
              height: 12,
              color: incomeColor.withValues(alpha: 0.2),
            ),
            ...result.warnings.map(
              (w) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: cs.tertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.tertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────
// 계좌 없음 안내
// ─────────────────────────────────────────────────────────

class _EmptyAccountsGuide extends StatelessWidget {
  const _EmptyAccountsGuide();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.account_balance_outlined,
                size: 36,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '등록된 계좌가 없습니다',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '계좌 관리 탭에서 계좌를 먼저 등록해주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.accounts),
              icon: const Icon(Icons.credit_card_outlined),
              label: const Text('계좌 관리로 이동'),
            ),
          ],
        ),
      ),
    );
  }
}
