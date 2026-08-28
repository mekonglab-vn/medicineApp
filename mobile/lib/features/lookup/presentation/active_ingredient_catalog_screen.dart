import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../data/drug_interaction_repository.dart';

class ActiveIngredientCatalogScreen extends ConsumerStatefulWidget {
  const ActiveIngredientCatalogScreen({super.key});

  @override
  ConsumerState<ActiveIngredientCatalogScreen> createState() =>
      _ActiveIngredientCatalogScreenState();
}

class _ActiveIngredientCatalogScreenState
    extends ConsumerState<ActiveIngredientCatalogScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  List<ActiveIngredientCatalogItem> _items = const [];
  int _page = 1;
  int _limit = 20;
  int _total = 0;
  bool _isLoading = true;
  String? _error;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPage();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  int get _totalPages {
    if (_total <= 0) {
      return 1;
    }
    return (_total / _limit).ceil();
  }

  Future<void> _loadPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final page = await ref
          .read(drugInteractionRepositoryProvider)
          .listActiveIngredients(_keyword, page: _page, limit: _limit);
      if (!mounted) {
        return;
      }

      setState(() {
        _items = page.items;
        _total = page.total;
        _page = page.page;
        _limit = page.limit;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = toFriendlyNetworkMessage(
          e,
          genericMessage:
              'Không tải được danh mục hoạt chất. Vui lòng thử lại.',
        );
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _keyword = value.trim();
        _page = 1;
      });
      _loadPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Danh mục hoạt chất')),
      body: RefreshIndicator(
        onRefresh: _loadPage,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tra cứu theo danh mục',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tìm nhanh hoạt chất và mở hồ sơ tương tác chi tiết từ dữ liệu cục bộ của ứng dụng.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Ví dụ: Paracetamol',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: () {
                          _controller.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _CatalogMessageCard(
                icon: Icons.error_outline,
                color: AppColors.error,
                message: _error!,
              )
            else if (_items.isEmpty)
              const _CatalogMessageCard(
                icon: Icons.inbox_outlined,
                color: AppColors.textSecondary,
                message: 'Không tìm thấy hoạt chất phù hợp.',
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Hiển thị ${_items.length} / $_total hoạt chất',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final item in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => context.push(
                      '/lookup/ingredients/${Uri.encodeComponent(item.name)}',
                    ),
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.science_outlined,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${item.interactionCount} tương tác đã ghi nhận',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _page <= 1 || _isLoading
                          ? null
                          : () {
                              setState(() {
                                _page -= 1;
                              });
                              _loadPage();
                            },
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Trang trước'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Trang $_page / $_totalPages',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _page >= _totalPages || _isLoading
                          ? null
                          : () {
                              setState(() {
                                _page += 1;
                              });
                              _loadPage();
                            },
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: const Text('Trang sau'),
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

class _CatalogMessageCard extends StatelessWidget {
  const _CatalogMessageCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
