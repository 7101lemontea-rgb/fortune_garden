// lib/presentation/screens/categories/categories_screen.dart
// SCR-009 /categories — 카테고리 설정 + 자동 분류 규칙 관리

import 'package:drift/drift.dart' show Value;
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../providers/category_rule_providers.dart';

// ── 헤더 배경색 (로컬 상수) ───────────────────────────────
const _headerBgLight = Color(0xFF2d4a22);
const _headerBgDark = Color(0xFF051a0f);

// ── 색상 헬퍼 ─────────────────────────────────────────────
Color _hexToColor(String hex) =>
    Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

String _colorToHex(Color color) =>
    '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

// ── 아이콘 이름 → IconData 변환 ───────────────────────────
// Material Icons 이름 문자열을 IconData로 매핑.
// DB에 저장된 문자열 기준.
const Map<String, IconData> _kIconMap = {
  'restaurant': Icons.restaurant,
  'directions_car': Icons.directions_car,
  'shopping_bag': Icons.shopping_bag,
  'local_hospital': Icons.local_hospital,
  'movie': Icons.movie,
  'school': Icons.school,
  'receipt': Icons.receipt,
  'smartphone': Icons.smartphone,
  'account_balance': Icons.account_balance,
  'swap_horiz': Icons.swap_horiz,
  'more_horiz': Icons.more_horiz,
  'dining': Icons.dining,
  'local_cafe': Icons.local_cafe,
  'home': Icons.home,
  'shopping_cart': Icons.shopping_cart,
  // 추가 선택 가능 아이콘
  'sports': Icons.sports,
  'pets': Icons.pets,
  'flight': Icons.flight,
  'hotel': Icons.hotel,
  'directions_bus': Icons.directions_bus,
  'local_gas_station': Icons.local_gas_station,
  'fitness_center': Icons.fitness_center,
  'spa': Icons.spa,
  'child_care': Icons.child_care,
  'work': Icons.work,
  'cake': Icons.cake,
  'wine_bar': Icons.wine_bar,
  'music_note': Icons.music_note,
  'videogame_asset': Icons.videogame_asset,
  'book': Icons.book,
  'computer': Icons.computer,
  'camera_alt': Icons.camera_alt,
  'volunteer_activism': Icons.volunteer_activism,
  'card_giftcard': Icons.card_giftcard,
  'savings': Icons.savings,
  'local_pharmacy': Icons.local_pharmacy,
  'park': Icons.park,
  'beach_access': Icons.beach_access,
  'electric_bolt': Icons.electric_bolt,
  'water_drop': Icons.water_drop,
  'wifi': Icons.wifi,
  'tv': Icons.tv,
  'kitchen': Icons.kitchen,
  'build': Icons.build,
  'attach_money': Icons.attach_money,
};

IconData _iconFromName(String? name) =>
    _kIconMap[name] ?? Icons.circle_outlined;

// 선택 가능한 아이콘 목록 (이름 순서 유지)
final _kSelectableIcons = _kIconMap.keys.toList();

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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final headerBg = isLight ? _headerBgLight : _headerBgDark;

    return Scaffold(
      body: GrainOverlay(
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 100,
              backgroundColor: headerBg,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 52),
                title: Text(
                  '카테고리 설정',
                  style: GoogleFonts.gowunBatang(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              bottom: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: '카테고리'),
                  Tab(text: '자동 분류 규칙'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: const [
              _CategoryListTab(),
              _RuleListTab(),
            ],
          ),
        ),
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
    final theme = Theme.of(context);

    return catsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (cats) {
        if (cats.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.category_outlined,
                    size: 64, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 16),
                Text('카테고리가 없습니다', style: theme.textTheme.titleMedium),
              ],
            ),
          );
        }

        final defaults = cats.where((c) => c.isCustom == 0).toList();
        final customs = cats.where((c) => c.isCustom == 1).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _SectionHeader(label: '기본 카테고리 (${defaults.length})'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: defaults.asMap().entries.map((entry) {
                  final i = entry.key;
                  final c = entry.value;
                  return Column(
                    children: [
                      _CategoryTile(
                        category: c,
                        onTap: () =>
                            _showCategoryForm(context, ref, category: c),
                      ),
                      if (i < defaults.length - 1)
                        Divider(
                          height: 1,
                          indent: 56,
                          color:
                              theme.colorScheme.outlineVariant.withOpacity(0.3),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
            if (customs.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionHeader(label: '커스텀 카테고리 (${customs.length})'),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: customs.asMap().entries.map((entry) {
                    final i = entry.key;
                    final c = entry.value;
                    return Column(
                      children: [
                        _CategoryTile(
                          category: c,
                          onTap: () =>
                              _showCategoryForm(context, ref, category: c),
                        ),
                        if (i < customs.length - 1)
                          Divider(
                            height: 1,
                            indent: 56,
                            color: theme.colorScheme.outlineVariant
                                .withOpacity(0.3),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});
  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category.colorHex != null
        ? _hexToColor(category.colorHex!)
        : theme.colorScheme.primary;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        radius: 20,
        // 저장된 아이콘 이름으로 실제 아이콘 표시
        child: Icon(_iconFromName(category.icon), color: color, size: 18),
      ),
      title: Text(
        category.name,
        style: theme.textTheme.bodyLarge,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (category.isCustom == 1)
            _Badge(
              label: '커스텀',
              color: theme.colorScheme.secondaryContainer,
              textColor: theme.colorScheme.onSecondaryContainer,
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right,
              size: 18, color: theme.colorScheme.outlineVariant),
        ],
      ),
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

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: rules.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
  late String _pickedIcon;
  bool _saving = false;
  bool _showIconPicker = false;

  bool get _isEdit => widget.category != null;
  bool get _isDeletable => _isEdit && widget.category!.isCustom == 1;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _pickedColor =
        c?.colorHex != null ? _hexToColor(c!.colorHex!) : Colors.blue;
    // 기존 아이콘이 있으면 유지, 없으면 기본값
    _pickedIcon = (c?.icon != null && _kIconMap.containsKey(c!.icon))
        ? c.icon!
        : 'more_horiz';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final companion = CategoriesCompanion(
        id: _isEdit ? Value(widget.category!.id) : const Value.absent(),
        name: Value(_nameCtrl.text.trim()),
        colorHex: Value(_colorToHex(_pickedColor)),
        icon: Value(_pickedIcon),
        isCustom: _isEdit ? Value(widget.category!.isCustom) : const Value(1),
      );
      await ref.read(categoryRepositoryProvider).upsert(companion);
      ref.invalidate(allCategoriesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 핸들 ──────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── 헤더 ──────────────────────────────────────────
            Row(
              children: [
                Text(
                  _isEdit ? '카테고리 수정' : '카테고리 추가',
                  style: theme.textTheme.titleLarge,
                ),
                const Spacer(),
                if (_isDeletable)
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: theme.colorScheme.error),
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
                prefixIcon: Icon(Icons.label_outline),
              ),
              textInputAction: TextInputAction.done,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '이름을 입력해주세요' : null,
            ),
            const SizedBox(height: 20),

            // ── 아이콘 선택 ────────────────────────────────────
            Row(
              children: [
                Text('아이콘', style: theme.textTheme.labelLarge),
                const SizedBox(width: 12),
                // 현재 선택된 아이콘 미리보기
                CircleAvatar(
                  backgroundColor: _pickedColor.withOpacity(0.18),
                  radius: 20,
                  child: Icon(
                    _iconFromName(_pickedIcon),
                    color: _pickedColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showIconPicker = !_showIconPicker),
                  icon: Icon(
                    _showIconPicker
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                  ),
                  label: Text(_showIconPicker ? '닫기' : '변경'),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),

            // ── 아이콘 선택 그리드 (토글) ──────────────────────
            if (_showIconPicker) ...[
              const SizedBox(height: 8),
              _IconPickerGrid(
                selected: _pickedIcon,
                accentColor: _pickedColor,
                onSelected: (name) => setState(() => _pickedIcon = name),
              ),
            ],
            const SizedBox(height: 20),

            // ── 색상 미리보기 ──────────────────────────────────
            Row(
              children: [
                Text('색상', style: theme.textTheme.labelLarge),
                const SizedBox(width: 12),
                CircleAvatar(backgroundColor: _pickedColor, radius: 14),
                const SizedBox(width: 8),
                Text(
                  _colorToHex(_pickedColor),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
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
              subheading: Text('색조 선택', style: theme.textTheme.bodySmall),
              wheelSubheading:
                  Text('색상 및 밝기', style: theme.textTheme.bodySmall),
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

            // ── 기본 카테고리 안내 ─────────────────────────────
            if (_isEdit && !_isDeletable) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    '기본 카테고리는 삭제할 수 없습니다',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
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
// 아이콘 선택 그리드
// ════════════════════════════════════════════════════════════

class _IconPickerGrid extends StatelessWidget {
  const _IconPickerGrid({
    required this.selected,
    required this.accentColor,
    required this.onSelected,
  });

  final String selected;
  final Color accentColor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _kSelectableIcons.length,
        itemBuilder: (_, i) {
          final name = _kSelectableIcons[i];
          final isSelected = name == selected;
          return GestureDetector(
            onTap: () => onSelected(name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withOpacity(0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? accentColor
                      : cs.outlineVariant.withOpacity(0.3),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Icon(
                _iconFromName(name),
                size: 20,
                color: isSelected ? accentColor : cs.onSurfaceVariant,
              ),
            ),
          );
        },
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
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rule_outlined,
              size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('자동 분류 규칙이 없습니다', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '+ 버튼을 눌러 규칙을 추가하세요.\n거래처명 키워드가 일치하면 자동으로 카테고리가 분류됩니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
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
    final theme = Theme.of(context);
    final color = categoryColor != null
        ? _hexToColor(categoryColor!)
        : theme.colorScheme.primary;

    return Dismissible(
      key: ValueKey(rule.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
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
      child: Card(
        child: ListTile(
          onTap: onEdit,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.18),
            radius: 20,
            child: Icon(Icons.rule, color: color, size: 18),
          ),
          title: Text(
            rule.keyword,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Row(
            children: [
              _ColorDot(color: color),
              const SizedBox(width: 4),
              Text(categoryName, style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              if (rule.profileId == null)
                _Badge(
                  label: '공용',
                  color: theme.colorScheme.secondaryContainer,
                  textColor: theme.colorScheme.onSecondaryContainer,
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rule.priority > 0)
                _Badge(
                  label: 'P${rule.priority}',
                  color: theme.colorScheme.tertiaryContainer,
                  textColor: theme.colorScheme.onTertiaryContainer,
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.outlineVariant),
            ],
          ),
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            // ── 핸들 ──────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── 헤더 ──────────────────────────────────────────
            Row(
              children: [
                Text(_isEdit ? '규칙 수정' : '규칙 추가',
                    style: theme.textTheme.titleLarge),
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
                prefixIcon: Icon(Icons.search),
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
                              _ColorDot(color: _hexToColor(c.colorHex!)),
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _priorityCtrl,
              decoration: const InputDecoration(
                labelText: '우선순위',
                helperText: '숫자가 높을수록 먼저 적용됩니다 (기본값 0)',
                prefixIcon: Icon(Icons.low_priority),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

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
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: textColor, fontWeight: FontWeight.w500)),
      );
}
