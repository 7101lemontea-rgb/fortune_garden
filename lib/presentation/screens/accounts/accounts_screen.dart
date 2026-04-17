// lib/presentation/screens/accounts/accounts_screen.dart
// SCR-007 /accounts — 계좌 관리
//
// 구성:
//   - AccountListTile  : 프로필별 계좌 목록 + 잔액 표시
//   - BalanceSummary   : 전체 잔액 합계 카드
//   - ImportHistoryList: 계좌별 가져오기 이력 (하단 시트)
//   - 계좌 등록/수정 폼 (BottomSheet)
//   - 계좌 삭제 (확인 다이얼로그)

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/security/account_encryption_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/repositories/i_account_repository.dart';
import '../../../domain/repositories/i_import_history_repository.dart';
import '../../router/app_routes.dart';

// ─────────────────────────────────────────────────────────
// Provider — 전체 프로필의 계좌 목록
// ─────────────────────────────────────────────────────────

final _allAccountsProvider =
    FutureProvider.autoDispose<List<_ProfileAccounts>>((ref) async {
  final profileRepo = ref.read(profileRepositoryProvider);
  final accountRepo = ref.read(accountRepositoryProvider);

  final profiles = await profileRepo.getAll();
  final result = <_ProfileAccounts>[];

  for (final p in profiles) {
    final accounts = await accountRepo.getByProfile(p.id);
    result.add(_ProfileAccounts(profile: p, accounts: accounts));
  }
  return result;
});

class _ProfileAccounts {
  const _ProfileAccounts({required this.profile, required this.accounts});
  final Profile profile;
  final List<Account> accounts;
}

// ─────────────────────────────────────────────────────────
// SCR-007 메인 화면
// ─────────────────────────────────────────────────────────

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  // 헤더 배경색 상수
  static const _headerBgLight = Color(0xFF2d4a22);
  static const _headerBgDark = Color(0xFF051a0f);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAsync = ref.watch(_allAccountsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? _headerBgDark : _headerBgLight;

    return Scaffold(
      body: GrainOverlay(
        child: CustomScrollView(
          slivers: [
            // ── SliverAppBar (다크 그린 헤더) ──────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: headerBg,
              foregroundColor: Colors.white,
              title: Text(
                '계좌 관리',
                style: GoogleFonts.gowunBatang(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  // fontStyle: FontStyle.italic,
                  color: Colors.white,
                ),
              ),
            ),

            // ── 본문 ────────────────────────────────────────
            allAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(child: Text('오류: $e')),
              ),
              data: (groups) {
                final allAccounts = groups.expand((g) => g.accounts).toList();

                if (allAccounts.isEmpty) {
                  return SliverFillRemaining(
                    child: _EmptyGuide(
                      onAdd: () => _showAddSheet(context, ref, groups),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // 잔액 요약 카드
                      _BalanceSummary(accounts: allAccounts),
                      const SizedBox(height: 20),

                      // 프로필별 계좌 목록
                      ...groups.map((g) => _ProfileSection(
                            group: g,
                            onAdded: () => ref.invalidate(_allAccountsProvider),
                            onChanged: () =>
                                ref.invalidate(_allAccountsProvider),
                          )),
                    ]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: allAsync.maybeWhen(
        data: (groups) => FloatingActionButton(
          onPressed: () => _showAddSheet(context, ref, groups),
          child: const Icon(Icons.add),
        ),
        orElse: () => null,
      ),
    );
  }

  void _showAddSheet(
    BuildContext context,
    WidgetRef ref,
    List<_ProfileAccounts> groups,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AccountFormSheet(
        groups: groups,
        onSaved: () => ref.invalidate(_allAccountsProvider),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 잔액 요약 카드
// ─────────────────────────────────────────────────────────

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({required this.accounts});
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final total = accounts.fold<int>(0, (sum, a) => sum + a.balance);
    final fmt = NumberFormat('#,###', 'ko_KR');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: incomeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 24,
                color: incomeColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '전체 잔액',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(total)}원',
                    style: GoogleFonts.gowunBatang(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      // fontStyle: FontStyle.italic,
                      color: incomeColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${accounts.length}개 계좌',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 프로필별 계좌 섹션
// ─────────────────────────────────────────────────────────

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection({
    required this.group,
    required this.onAdded,
    required this.onChanged,
  });

  final _ProfileAccounts group;
  final VoidCallback onAdded;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(int.parse(
        'FF${group.profile.colorHex.replaceAll('#', '')}',
        radix: 16));
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 프로필 섹션 헤더
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color,
                radius: 9,
                child: CircleAvatar(
                  backgroundColor: color.withOpacity(0.3),
                  radius: 4,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                group.profile.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.accounts.length}개',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),

        // 계좌 없음
        if (group.accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 16),
            child: Text(
              '등록된 계좌가 없습니다',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),

        // 계좌 목록
        ...group.accounts.map((a) => _AccountTile(
              account: a,
              profile: group.profile,
              group: group,
              onChanged: onChanged,
            )),

        const SizedBox(height: 12),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// 계좌 타일
// ─────────────────────────────────────────────────────────

class _AccountTile extends ConsumerWidget {
  const _AccountTile({
    required this.account,
    required this.profile,
    required this.group,
    required this.onChanged,
  });

  final Account account;
  final Profile profile;
  final _ProfileAccounts group;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,###', 'ko_KR');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showOptions(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // 기관 아이콘 영역
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.credit_card_outlined,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // 계좌명 + 기관명
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.alias ?? account.institutionCode,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.institutionCode,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              // 잔액 + 최종 동기화
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${fmt.format(account.balance)}원',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: incomeColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (account.lastSyncedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(account.lastSyncedAt!),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),

              // 더보기 아이콘
              const SizedBox(width: 8),
              Icon(
                Icons.more_vert,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('M/d HH:mm', 'ko_KR').format(dt);
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 계좌명 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.credit_card_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    account.alias ?? account.institutionCode,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            Divider(height: 16, color: cs.outlineVariant.withOpacity(0.4)),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('CSV 가져오기'),
              onTap: () {
                Navigator.pop(context);
                context.go(AppRoutes.import);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('가져오기 이력'),
              onTap: () {
                Navigator.pop(context);
                _showHistory(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('계좌 수정'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: cs.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => _AccountFormSheet(
                    groups: [group],
                    existing: account,
                    onSaved: onChanged,
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: expenseColor),
              title: Text('계좌 삭제', style: TextStyle(color: expenseColor)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showHistory(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ImportHistorySheet(accountId: account.id),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('계좌 삭제'),
        content: Text(
          '\'${account.alias ?? account.institutionCode}\' 계좌를 삭제하면\n'
          '관련 거래 내역과 가져오기 이력도 함께 삭제됩니다.\n\n'
          '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: expenseColor),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(accountRepositoryProvider).delete(account.id);
              onChanged();
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 계좌 등록/수정 폼 BottomSheet
// ─────────────────────────────────────────────────────────

class _AccountFormSheet extends ConsumerStatefulWidget {
  const _AccountFormSheet({
    required this.groups,
    required this.onSaved,
    this.existing,
  });

  final List<_ProfileAccounts> groups;
  final Account? existing; // null = 신규 등록
  final VoidCallback onSaved;

  @override
  ConsumerState<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<_AccountFormSheet> {
  final _aliasCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  late int _selectedProfileId;
  String? _selectedInstitutionCode;
  bool _saving = false;
  bool _obscureAccountNumber = true; // 계좌번호 마스킹 토글

  List<Institution> _institutions = [];

  static const _typeLabels = {
    'bank': '은행',
    'card': '카드',
    'stock': '증권',
  };

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _aliasCtrl.text = widget.existing!.alias ?? '';
      _selectedProfileId = widget.existing!.profileId;
      _selectedInstitutionCode = widget.existing!.institutionCode;
      // 기존 계좌번호 복호화해서 필드에 표시
      _loadExistingAccountNumber();
    } else {
      _selectedProfileId =
          widget.groups.isNotEmpty ? widget.groups.first.profile.id : 1;
    }
    _loadInstitutions();
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _accountNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInstitutions() async {
    final list = await ref.read(activeInstitutionsProvider.future);
    if (mounted) setState(() => _institutions = list);
  }

  /// 수정 모드: 기존 암호화된 계좌번호를 복호화해 입력 필드에 채움.
  /// DEV placeholder이거나 복호화 실패 시 필드를 비워둠.
  Future<void> _loadExistingAccountNumber() async {
    final enc = widget.existing?.accountNumberEnc;
    if (enc == null || enc.isEmpty) return;

    if (AccountEncryptionService.isDevPlaceholder(enc)) return;

    final decrypted = await AccountEncryptionService.decrypt(enc);
    if (mounted && decrypted != null) {
      _accountNumberCtrl.text = decrypted;
    }
  }

  Future<void> _save() async {
    if (_selectedInstitutionCode == null) return;

    final rawNumber = _accountNumberCtrl.text.trim();
    if (rawNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계좌번호를 입력해주세요')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // 계좌번호 AES-256 암호화
      final encBytes = await AccountEncryptionService.encrypt(rawNumber);

      await ref.read(accountRepositoryProvider).upsert(
            AccountsCompanion(
              id: widget.existing != null
                  ? Value(widget.existing!.id)
                  : const Value.absent(),
              profileId: Value(_selectedProfileId),
              institutionCode: Value(_selectedInstitutionCode!),
              accountNumberEnc: Value(encBytes),
              alias: Value(
                _aliasCtrl.text.trim().isEmpty ? null : _aliasCtrl.text.trim(),
              ),
              balance: const Value(0),
            ),
          );

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 헤더
            Row(
              children: [
                Text(
                  isEdit ? '계좌 수정' : '계좌 등록',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 프로필 선택 (수정 시 비활성)
            DropdownButtonFormField<int>(
              value: _selectedProfileId,
              decoration: const InputDecoration(labelText: '프로필'),
              items: widget.groups
                  .map((g) => DropdownMenuItem(
                        value: g.profile.id,
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(int.parse(
                                  'FF${g.profile.colorHex.replaceAll('#', '')}',
                                  radix: 16)),
                              radius: 8,
                            ),
                            const SizedBox(width: 8),
                            Text(g.profile.name),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: isEdit
                  ? null
                  : (v) => setState(() => _selectedProfileId = v!),
            ),
            const SizedBox(height: 12),

            // 금융기관 선택 (수정 시 비활성)
            DropdownButtonFormField<String>(
              value: _selectedInstitutionCode,
              decoration: const InputDecoration(labelText: '금융기관 *'),
              hint: const Text('기관을 선택하세요'),
              isExpanded: true,
              items: _buildInstitutionItems(),
              onChanged: isEdit
                  ? null
                  : (v) => setState(() => _selectedInstitutionCode = v),
            ),
            const SizedBox(height: 12),

            // 계좌번호 입력 (암호화 저장)
            TextField(
              controller: _accountNumberCtrl,
              obscureText: _obscureAccountNumber,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '계좌번호 *',
                hintText: '숫자만 입력 (예: 12345678901234)',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureAccountNumber
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(
                      () => _obscureAccountNumber = !_obscureAccountNumber),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 12, color: cs.outline),
                const SizedBox(width: 4),
                Text(
                  'AES-256으로 암호화되어 기기에 안전하게 저장됩니다.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 별명 입력
            TextField(
              controller: _aliasCtrl,
              decoration: const InputDecoration(
                labelText: '계좌 별명 (선택)',
                hintText: '예: KB 급여통장',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '별명을 입력하지 않으면 기관명으로 표시됩니다.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            // 저장 버튼
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_selectedInstitutionCode == null || _saving)
                    ? null
                    : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEdit ? '수정 완료' : '등록'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _buildInstitutionItems() {
    final items = <DropdownMenuItem<String>>[];

    for (final type in ['bank', 'card', 'stock']) {
      final filtered = _institutions.where((i) => i.type == type).toList();
      if (filtered.isEmpty) continue;

      // 유형 구분 헤더 (비활성)
      items.add(DropdownMenuItem(
        enabled: false,
        value: '__header_$type',
        child: Text(
          _typeLabels[type] ?? type,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ));

      // 기관 목록
      items.addAll(filtered.map((i) => DropdownMenuItem(
            value: i.code,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(i.name),
            ),
          )));
    }

    return items;
  }
}

// ─────────────────────────────────────────────────────────
// 가져오기 이력 BottomSheet
// ─────────────────────────────────────────────────────────

class _ImportHistorySheet extends ConsumerWidget {
  const _ImportHistorySheet({required this.accountId});
  final int accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          // 핸들
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Text('가져오기 이력', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
          Expanded(
            child: FutureBuilder<List<ImportHistoryEntry>>(
              future: ref
                  .read(importHistoryRepositoryProvider)
                  .getByAccount(accountId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final history = snap.data!;
                if (history.isEmpty) {
                  return Center(
                    child: Text(
                      '가져오기 이력이 없습니다',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  itemCount: history.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, color: cs.outlineVariant.withOpacity(0.4)),
                  itemBuilder: (ctx, i) => _HistoryTile(entry: history[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});
  final ImportHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(entry.importedAt);
    final fmt = DateFormat('yyyy.MM.dd HH:mm', 'ko_KR');
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark ? AppTheme.incomeDark : AppTheme.incomeLight;
    final expenseColor = isDark ? AppTheme.expenseDark : AppTheme.expenseLight;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.upload_file_outlined,
              size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.fileName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  fmt.format(dt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusChip('신규 ${entry.newRows}건', incomeColor),
              if (entry.duplicateRows > 0) ...[
                const SizedBox(height: 3),
                _StatusChip('중복 ${entry.duplicateRows}건', cs.onSurfaceVariant),
              ],
              if (entry.errorRows > 0) ...[
                const SizedBox(height: 3),
                _StatusChip('오류 ${entry.errorRows}건', expenseColor),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.25), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────
// 계좌 없음 안내
// ─────────────────────────────────────────────────────────

class _EmptyGuide extends StatelessWidget {
  const _EmptyGuide({required this.onAdd});
  final VoidCallback onAdd;

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
                Icons.credit_card_outlined,
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
              'CSV 파일을 가져오려면\n먼저 계좌를 등록해주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('계좌 등록'),
            ),
          ],
        ),
      ),
    );
  }
}
