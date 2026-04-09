// lib/presentation/screens/categories/categories_screen.dart
// SCR-009 /categories — 카테고리 설정 + 자동 분류 규칙 관리

import 'package:drift/drift.dart' show Value;
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../providers/category_rule_providers.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('카테고리 설정'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '카테고리'),
            Tab(text: '자동 분류 규칙'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CategoryListTab(),
          _RuleListTab(),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          return FloatingActionButton(
            onPressed: () => _tabController.index == 0
                ? _showCategoryForm(context, ref)
                : _showRuleForm(context, ref),
            tooltip: _tabController.index == 0 ? '카테고리 추가' : '규칙 추가',
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 탭 1 — 카테고리 목록
// ════════════════════════════════════════════════════════════

class _CategoryListTab extends ConsumerWidget {
  const _CategoryListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(allCategoriesProvider);

    return catsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (cats) {
        if (cats.isEmpty) return const Center(child: Text('카테고리가 없습니다'));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: cats.length,
          itemBuilder: (ctx, i) {
            final c = cats[i];
            final color = c.colorHex != null
                ? Color(int.parse('FF${c.colorHex!.replaceAll('#', '')}',
                    radix: 16))
                : Theme.of(context).colorScheme.primary;

            return ListTile(
              onTap: () => _showCategoryForm(context, ref, category: c),
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(0.2),
                radius: 20,
                child: Icon(Icons.circle, color: color, size: 14),
              ),
              title: Text(c.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.isCustom == 1)
                    _Badge(
                      label: '커스텀',
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      textColor:
                          Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
// 탭 2 — 자동 분류 규칙 목록
// ════════════════════════════════════════════════════════════

class _RuleListTab extends ConsumerWidget {
  const _RuleListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(categoryRulesProvider);
    final catsAsync = ref.watch(allCategoriesProvider);

    return rulesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (rules) {
        if (rules.isEmpty) return const _EmptyRulesPlaceholder();

        final catMap = catsAsync.valueOrNull != null
            ? {for (final c in catsAsync.value!) c.id: c}
            : <int, Category>{};

        return ListView.builder(
          itemCount: rules.length,
          itemBuilder: (ctx, i) {
            final rule = rules[i];
            final cat = catMap[rule.categoryId];
            return _RuleTile(
              rule: rule,
              categoryName: cat?.name ?? '(알 수 없음)',
              categoryColor: cat?.colorHex,
              onEdit: () => _showRuleForm(context, ref, rule: rule),
              onDelete: () => _deleteRule(context, ref, rule),
            );
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
// 카테고리 추가 / 수정 폼
// ════════════════════════════════════════════════════════════

void _showCategoryForm(BuildContext context, WidgetRef ref,
    {Category? category}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _CategoryFormSheet(category: category, ref: ref),
  );
}

class _CategoryFormSheet extends ConsumerStatefulWidget {
  const _CategoryFormSheet({this.category, required this.ref});
  final Category? category;
  final WidgetRef ref;

  @override
  ConsumerState<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late Color _pickedColor;
  bool _saving = false;

  bool get _isEdit => widget.category != null;

  // 커스텀 카테고리(isCustom == 1)만 삭제 가능
  bool get _isDeletable => _isEdit && widget.category!.isCustom == 1;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _pickedColor = c?.colorHex != null
        ? Color(int.parse('FF${c!.colorHex!.replaceAll('#', '')}', radix: 16))
        : Colors.blue;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) =>
      '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final companion = CategoriesCompanion(
        id: _isEdit ? Value(widget.category!.id) : const Value.absent(),
        name: Value(_nameCtrl.text.trim()),
        colorHex: Value(_colorToHex(_pickedColor)),
        icon: _isEdit ? Value(widget.category!.icon) : const Value.absent(),
        isCustom: _isEdit
            ? Value(widget.category!.isCustom)
            : const Value(1), // 신규는 항상 커스텀
      );

      await ref.read(categoryRepositoryProvider).upsert(companion);
      ref.invalidate(allCategoriesProvider);

      if (mounted) Navigator.of(context).pop();
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

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('카테고리 삭제'),
        content: Text('"${widget.category!.name}" 카테고리를 삭제할까요?\n'
            '해당 카테고리의 거래는 미분류로 변경됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(categoryRepositoryProvider).delete(widget.category!.id);
      ref.invalidate(allCategoriesProvider);
      ref.invalidate(categoryRulesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 헤더 ──────────────────────────────────────────
            Row(
              children: [
                Text(
                  _isEdit ? '카테고리 수정' : '카테고리 추가',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (_isDeletable)
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: '삭제',
                    onPressed: _delete,
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── 이름 입력 ──────────────────────────────────────
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '카테고리 이름 *',
                hintText: '예: 식비, 교통비',
              ),
              textInputAction: TextInputAction.done,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '이름을 입력해주세요';
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ── 색상 미리보기 ──────────────────────────────────
            Row(
              children: [
                Text('색상', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: _pickedColor,
                  radius: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  _colorToHex(_pickedColor),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── 컬러피커 ───────────────────────────────────────
            ColorPicker(
              color: _pickedColor,
              onColorChanged: (c) => setState(() => _pickedColor = c),
              width: 36,
              height: 36,
              borderRadius: 18,
              spacing: 5,
              runSpacing: 5,
              wheelDiameter: 220,
              showMaterialName: false,
              showColorName: false,
              showColorCode: true,
              colorCodeHasColor: true,
              subheading:
                  Text('색조 선택', style: Theme.of(context).textTheme.bodySmall),
              wheelSubheading:
                  Text('색상 및 밝기', style: Theme.of(context).textTheme.bodySmall),
              pickersEnabled: const {
                ColorPickerType.primary: true,
                ColorPickerType.accent: false,
                ColorPickerType.wheel: true,
                ColorPickerType.custom: false,
                ColorPickerType.bw: false,
              },
            ),
            const SizedBox(height: 24),

            // ── 저장 버튼 ──────────────────────────────────────
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? '수정 완료' : '카테고리 추가'),
            ),

            // ── 기본 카테고리 삭제 불가 안내 ──────────────────
            if (_isEdit && !_isDeletable) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    '기본 카테고리는 삭제할 수 없습니다',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 규칙 관련 위젯
// ════════════════════════════════════════════════════════════

class _EmptyRulesPlaceholder extends StatelessWidget {
  const _EmptyRulesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rule_outlined,
              size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('자동 분류 규칙이 없습니다',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '+ 버튼을 눌러 규칙을 추가하세요.\n거래처명 키워드가 일치하면 자동으로 카테고리가 분류됩니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.categoryName,
    this.categoryColor,
    required this.onEdit,
    required this.onDelete,
  });

  final CategoryRule rule;
  final String categoryName;
  final String? categoryColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor != null
        ? Color(int.parse('FF${categoryColor!.replaceAll('#', '')}', radix: 16))
        : Theme.of(context).colorScheme.primary;

    return Dismissible(
      key: ValueKey(rule.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(Icons.delete_outline,
            color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('규칙 삭제'),
            content: Text('"${rule.keyword}" 규칙을 삭제할까요?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('삭제')),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onEdit,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          radius: 20,
          child: Icon(Icons.rule, color: color, size: 18),
        ),
        title: Text(rule.keyword,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Row(
          children: [
            _ColorDot(color: color),
            const SizedBox(width: 4),
            Text(categoryName),
            const SizedBox(width: 8),
            if (rule.profileId == null)
              _Badge(
                label: '공용',
                color: Theme.of(context).colorScheme.secondaryContainer,
                textColor: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rule.priority > 0)
              _Badge(
                label: 'P${rule.priority}',
                color: Theme.of(context).colorScheme.tertiaryContainer,
                textColor: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

void _showRuleForm(BuildContext context, WidgetRef ref, {CategoryRule? rule}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _RuleFormSheet(rule: rule, ref: ref),
  );
}

class _RuleFormSheet extends ConsumerStatefulWidget {
  const _RuleFormSheet({this.rule, required this.ref});
  final CategoryRule? rule;
  final WidgetRef ref;

  @override
  ConsumerState<_RuleFormSheet> createState() => _RuleFormSheetState();
}

class _RuleFormSheetState extends ConsumerState<_RuleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _keywordCtrl;
  late final TextEditingController _priorityCtrl;
  int? _selectedCategoryId;
  int? _selectedProfileId;
  bool _saving = false;

  bool get _isEdit => widget.rule != null;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _keywordCtrl = TextEditingController(text: r?.keyword ?? '');
    _priorityCtrl = TextEditingController(text: r?.priority.toString() ?? '0');
    _selectedCategoryId = r?.categoryId;
    _selectedProfileId = r?.profileId;
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    _priorityCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카테고리를 선택해주세요')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final companion = CategoryRulesCompanion(
        id: _isEdit ? Value(widget.rule!.id) : const Value.absent(),
        keyword: Value(_keywordCtrl.text.trim()),
        categoryId: Value(_selectedCategoryId!),
        profileId: Value(_selectedProfileId),
        priority: Value(int.tryParse(_priorityCtrl.text) ?? 0),
      );
      await ref.read(categoryRepositoryProvider).upsertRule(companion);
      ref.invalidate(categoryRulesProvider);
      if (mounted) Navigator.of(context).pop();
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
    final catsAsync = ref.watch(allCategoriesProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(_isEdit ? '규칙 수정' : '규칙 추가',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _keywordCtrl,
              decoration: const InputDecoration(
                labelText: '거래처명 키워드 *',
                hintText: '예: 스타벅스, 편의점, GS25',
                helperText: '거래처명에 이 키워드가 포함되면 자동 분류됩니다',
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '키워드를 입력해주세요' : null,
            ),
            const SizedBox(height: 16),
            catsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('카테고리 로드 실패: $e'),
              data: (cats) => DropdownButtonFormField<int>(
                value: _selectedCategoryId,
                decoration: const InputDecoration(labelText: '카테고리 *'),
                items: cats
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Row(children: [
                            if (c.colorHex != null)
                              _ColorDot(
                                color: Color(int.parse(
                                    'FF${c.colorHex!.replaceAll('#', '')}',
                                    radix: 16)),
                              ),
                            const SizedBox(width: 8),
                            Text(c.name),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategoryId = v),
                validator: (v) => v == null ? '카테고리를 선택해주세요' : null,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<int?>(
              segments: const [
                ButtonSegment(value: null, label: Text('공용')),
                ButtonSegment(value: 1, label: Text('프로필 1')),
                ButtonSegment(value: 2, label: Text('프로필 2')),
              ],
              selected: {_selectedProfileId},
              onSelectionChanged: (s) =>
                  setState(() => _selectedProfileId = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              '공용: 두 프로필 모두 적용  /  개인: 해당 프로필만 적용',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priorityCtrl,
              decoration: const InputDecoration(
                labelText: '우선순위',
                helperText: '숫자가 높을수록 먼저 적용됩니다 (기본값 0)',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                if (int.tryParse(v) == null) return '숫자를 입력해주세요';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? '수정 완료' : '규칙 추가'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _deleteRule(
    BuildContext context, WidgetRef ref, CategoryRule rule) async {
  try {
    await ref.read(categoryRepositoryProvider).deleteRule(rule.id);
    ref.invalidate(categoryRulesProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }
}

// ════════════════════════════════════════════════════════════
// 공용 소형 위젯
// ════════════════════════════════════════════════════════════

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.label, required this.color, required this.textColor});
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(fontSize: 11, color: textColor)),
      );
}
