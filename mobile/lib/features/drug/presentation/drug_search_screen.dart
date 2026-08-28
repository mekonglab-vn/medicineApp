import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../data/drug_repository.dart';
import '../data/drug_search_notifier.dart';

class DrugSearchScreen extends ConsumerStatefulWidget {
  const DrugSearchScreen({super.key});

  @override
  ConsumerState<DrugSearchScreen> createState() => _DrugSearchScreenState();
}

class _DrugSearchScreenState extends ConsumerState<DrugSearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openDetails(DrugSearchItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(drugRepositoryProvider);
      final details = await repo.getByName(item.name);
      if (!mounted) return;
      context.push(
        '/drugs/detail',
        extra: {'details': details, 'activeIngredient': item.activeIngredient},
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            toFriendlyNetworkMessage(
              e,
              genericMessage:
                  'Không tải được thông tin thuốc. Vui lòng thử lại.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(drugSearchNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Thông tin thuốc')),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  onChanged: (value) => ref
                      .read(drugSearchNotifierProvider.notifier)
                      .search(value),
                  decoration: InputDecoration(
                    hintText: 'Paracetamol',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        ref.read(drugSearchNotifierProvider.notifier).clear();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tìm theo tên thuốc hoặc hoạt chất để xem thông tin nhanh.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Builder(
              builder: (context) {
                if (state.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.error != null) {
                  final friendlyError = toFriendlyNetworkMessage(
                    state.error!,
                    genericMessage:
                        'Không thể tìm thuốc lúc này. Vui lòng thử lại.',
                  );
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        friendlyError,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  );
                }
                if (state.query.length < 2) {
                  return const _SearchHint();
                }
                if (state.items.isEmpty) {
                  return const _EmptyResult();
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  itemCount: state.items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return InkWell(
                      onTap: () => _openDetails(item),
                      borderRadius: BorderRadius.circular(22),
                      child: Ink(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSoft,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.medication_outlined,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.activeIngredient?.isNotEmpty == true
                                        ? item.activeIngredient!
                                        : 'Không rõ hoạt chất',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                item.score.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 42,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nhập ít nhất 2 ký tự để tìm thuốc',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bạn có thể tìm theo tên thuốc, tên thương mại hoặc hoạt chất.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Không tìm thấy kết quả phù hợp',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
