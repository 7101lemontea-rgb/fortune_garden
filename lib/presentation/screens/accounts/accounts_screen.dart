// lib/presentation/screens/accounts/accounts_screen.dart
// SCR-007 /accounts — 계좌 관리
//
// 구성:
//   - AccountListTile  : 프로필별 계좌 목록 + 잔액 표시
//   - BalanceSummary   : 전체 잔액 합계 카드
//   - ImportHistoryList: 계좌별 가져오기 이력 (하단 시트)
//   - 계좌 등록/수정 폼 (BottomSheet)
//   - 계좌 삭제 (확인 다이얼로그)

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/database/database_provider.dart';
import '../../../domain/repositories/i_account_repository.dart';
import '../../../domain/repositories/i_import_history_repository.dart';

// ─────────────────────────────────────────────────────────
// Provider — 전체 프로필의 계좌 목록
// ─────────────────────────────────────────────────────────

final _allAccountsProvider =
    FutureProvider.autoDispose<List<_ProfileAccounts>>((ref) async {
  final profileRepo = ref.read(profileRepositoryProvider);
  final accountRepo = ref.read(accountRepositoryProvider);

  final profiles = await profileRepo.getAll();
  final result   = <_ProfileAccounts>[];

  for (final p in profiles) {
    final accounts = await accountRepo.getByProfile(p.id);
    result.add(_ProfileAccounts(profile: p, accounts: accounts));
  }
  return result;
});

class _ProfileAccounts {
  const _ProfileAccounts({required this.profile, required this.accounts});
  final Profile        profile;
  final List<Account>  accounts;
}

// ─────────────────────────────────────────────────────────
// SCR-007 메인 화면
// ─────────────────────────────────────────────────────────

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAsync = ref.watch(_allAccountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('계좌 관리')),
      body: allAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('오류: $e')),
        data: (groups) {
          // 전체 계좌 목록 (잔액 합산용)
          final allAccounts = groups
              .expand((g) => g.accounts)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── 잔액 요약 카드 ──
              if (allAccounts.isNotEmpty)
                _BalanceSummary(accounts: allAccounts),
              const SizedBox(height: 16),

              // ── 프로필별 계좌 목록 ──
              ...groups.map((g) => _ProfileSection(
                group: g,
                onAdded: () => ref.invalidate(_allAccountsProvider),
                onChanged: () => ref.invalidate(_allAccountsProvider),
              )),

              // ── 계좌 없음 안내 ──
              if (allAccounts.isEmpty)
                _EmptyGuide(
                  onAdd: () => _showAddSheet(context, ref, groups),
                ),
            ],
          );
        },
      ),
      floatingActionButton: allAsync.when(
        data: (groups) => FloatingActionButton.extended(
          onPressed: () => _showAddSheet(context, ref, groups),
          icon: const Icon(Icons.add),
          label: const Text('계좌 등록'),
        ),
        loading: () => null,
        error:   (_, __) => null,
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
      builder: (_) => _AccountFormSheet(
        groups:    groups,
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
    final fmt   = NumberFormat('#,###', 'ko_KR');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 32, color: Colors.green),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('전체 잔액',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  '${fmt.format(total)}원',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Spacer(),
            Text('${accounts.length}개 계좌',
                style: Theme.of(context).textTheme.bodySmall),
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
  final VoidCallback     onAdded;
  final VoidCallback     onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(int.parse(
        'FF${group.profile.colorHex.replaceAll('#', '')}', radix: 16));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 프로필 헤더
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: color, radius: 8),
              const SizedBox(width: 8),
              Text(
                group.profile.name,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),

        // 계좌 없음
        if (group.accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 12),
            child: Text('등록된 계좌가 없습니다',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ),

        // 계좌 목록
        ...group.accounts.map((a) => _AccountTile(
          account: a,
          profile: group.profile,
          group:   group,
          onChanged: onChanged,
        )),

        const SizedBox(height: 8),
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

  final Account          account;
  final Profile          profile;
  final _ProfileAccounts group;
  final VoidCallback     onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,###', 'ko_KR');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.credit_card_outlined),
        title: Text(account.alias ?? account.institutionCode),
        subtitle: Text(account.institutionCode),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${fmt.format(account.balance)}원',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if (account.lastSyncedAt != null)
              Text(
                _formatDate(account.lastSyncedAt!),
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500),
              ),
          ],
        ),
        onTap: () => _showOptions(context, ref),
      ),
    );
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('M/d HH:mm', 'ko_KR').format(dt);
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('CSV 가져오기'),
              onTap: () {
                Navigator.pop(context);
                context.go('/import');
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
              title: const Text('수정'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _AccountFormSheet(
                    groups:   [group],
                    existing: account,
                    onSaved: onChanged,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref);
              },
            ),
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
      builder: (_) => _ImportHistorySheet(accountId: account.id),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
  final Account?               existing;  // null = 신규 등록
  final VoidCallback           onSaved;

  @override
  ConsumerState<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<_AccountFormSheet> {
  final _aliasCtrl = TextEditingController();
  late int    _selectedProfileId;
  String?     _selectedInstitutionCode;
  bool        _saving = false;

  // 기관 목록 (institutions 테이블에서 로드)
  List<Institution> _institutions = [];

  // 기관 유형별 그룹
  static const _typeLabels = {
    'bank': '은행',
    'card': '카드',
    'stock': '증권',
  };

  @override
  void initState() {
    super.initState();
    // 수정 모드 초기값
    if (widget.existing != null) {
      _aliasCtrl.text          = widget.existing!.alias ?? '';
      _selectedProfileId       = widget.existing!.profileId;
      _selectedInstitutionCode = widget.existing!.institutionCode;
    } else {
      _selectedProfileId = widget.groups.isNotEmpty
          ? widget.groups.first.profile.id
          : 1;
    }
    _loadInstitutions();
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInstitutions() async {
    final list = await ref
        .read(activeInstitutionsProvider.future);
    if (mounted) setState(() => _institutions = list);
  }

  Future<void> _save() async {
    if (_selectedInstitutionCode == null) return;
    setState(() => _saving = true);

    // 계좌번호 암호화 placeholder
    // 실제 운영 시: flutter_secure_storage + encrypt로 AES-256-GCM 처리
    final encBytes = Uint8List.fromList(
      utf8.encode('DEV:${_selectedInstitutionCode}_${DateTime.now().millisecondsSinceEpoch}'),
    );

    await ref.read(accountRepositoryProvider).upsert(
      AccountsCompanion(
        id: widget.existing != null
            ? Value(widget.existing!.id)
            : const Value.absent(),
        profileId:        Value(_selectedProfileId),
        institutionCode:  Value(_selectedInstitutionCode!),
        accountNumberEnc: Value(encBytes),
        alias: Value(
          _aliasCtrl.text.trim().isEmpty ? null : _aliasCtrl.text.trim(),
        ),
        balance:          const Value(0),
      ),
    );

    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
              decoration: const InputDecoration(
                labelText: '프로필',
                border: OutlineInputBorder(),
              ),
              items: widget.groups.map((g) => DropdownMenuItem(
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
              )).toList(),
              onChanged: isEdit
                  ? null
                  : (v) => setState(() => _selectedProfileId = v!),
            ),
            const SizedBox(height: 12),

            // 금융기관 선택
            DropdownButtonFormField<String>(
              value: _selectedInstitutionCode,
              decoration: const InputDecoration(
                labelText: '금융기관 *',
                border: OutlineInputBorder(),
              ),
              hint: const Text('기관을 선택하세요'),
              isExpanded: true,
              items: _buildInstitutionItems(),
              onChanged: isEdit
                  ? null
                  : (v) => setState(() => _selectedInstitutionCode = v),
            ),
            const SizedBox(height: 12),

            // 별명 입력
            TextField(
              controller: _aliasCtrl,
              decoration: const InputDecoration(
                labelText: '계좌 별명 (선택)',
                hintText: '예: KB 급여통장',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '별명을 입력하지 않으면 기관명으로 표시됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
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
      final filtered = _institutions
          .where((i) => i.type == type)
          .toList();
      if (filtered.isEmpty) continue;

      // 유형 구분 헤더
      items.add(DropdownMenuItem(
        enabled: false,
        value:   '__header_$type',
        child: Text(
          _typeLabels[type] ?? type,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('가져오기 이력',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
                  return const Center(
                    child: Text('가져오기 이력이 없습니다',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) =>
                      _HistoryTile(entry: history[i]),
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
    final dt  = DateTime.fromMillisecondsSinceEpoch(entry.importedAt);
    final fmt = DateFormat('yyyy.MM.dd HH:mm', 'ko_KR');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.upload_file_outlined,
              size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(fmt.format(dt),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Chip('신규 ${entry.newRows}건', Colors.green),
              if (entry.duplicateRows > 0) ...[
                const SizedBox(height: 2),
                _Chip('중복 ${entry.duplicateRows}건', Colors.grey),
              ],
              if (entry.errorRows > 0) ...[
                const SizedBox(height: 2),
                _Chip('오류 ${entry.errorRows}건', Colors.red),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w500)),
  );
}

// ─────────────────────────────────────────────────────────
// 계좌 없음 안내
// ─────────────────────────────────────────────────────────

class _EmptyGuide extends StatelessWidget {
  const _EmptyGuide({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.credit_card_outlined,
              size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('등록된 계좌가 없습니다',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text(
            'CSV 파일을 가져오려면 먼저 계좌를 등록해주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
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
