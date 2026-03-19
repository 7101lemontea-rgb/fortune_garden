// lib/presentation/screens/categories/categories_screen.dart
// SCR-009 /categories — 카테고리 설정

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/category/category_classify_use_case.dart';
import '../../../data/database/app_database.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('카테고리 설정')),
      body: FutureBuilder<List<Category>>(
        future: ref
            .read(categoryClassifyUseCaseProvider)
            .getAllCategories(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cats = snap.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: cats.length,
            itemBuilder: (ctx, i) {
              final c = cats[i];
              return ListTile(
                leading: c.colorHex != null
                    ? CircleAvatar(
                        backgroundColor: Color(int.parse(
                            'FF${c.colorHex!.replaceAll('#', '')}',
                            radix: 16)),
                        radius: 14,
                      )
                    : const CircleAvatar(radius: 14),
                title: Text(c.name),
                trailing: c.isCustom == 1
                    ? const Chip(label: Text('커스텀'))
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
