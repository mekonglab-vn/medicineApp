import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';

class DrugSearchItem {
  const DrugSearchItem({
    required this.name,
    required this.score,
    this.activeIngredient,
  });

  final String name;
  final double score;
  final String? activeIngredient;

  factory DrugSearchItem.fromJson(Map<String, dynamic> json) {
    String? ingredient;
    final hoatChat = json['hoatChat'];
    if (hoatChat is List && hoatChat.isNotEmpty) {
      final first = hoatChat.first;
      if (first is Map<String, dynamic>) {
        ingredient = first['tenHoatChat']?.toString();
      }
    }

    return DrugSearchItem(
      name: json['name']?.toString() ?? json['tenThuoc']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      activeIngredient: ingredient,
    );
  }
}

class DrugSearchPage {
  const DrugSearchPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<DrugSearchItem> items;
  final int total;
  final int page;
  final int limit;
}

class DrugDetails {
  const DrugDetails({required this.name, this.source, this.raw});

  final String name;
  final String? source;
  final Map<String, dynamic>? raw;

  factory DrugDetails.fromJson(Map<String, dynamic> json) => DrugDetails(
    name: json['tenThuoc']?.toString() ?? json['name']?.toString() ?? '',
    source: json['_source']?.toString(),
    raw: json,
  );
}

class DrugRepository {
  DrugRepository(this._dio);

  final Dio _dio;

  Future<DrugSearchPage> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _dio.get(
      '/drugs/search',
      queryParameters: {'q': query, 'page': page, 'limit': limit},
    );

    final items = (response.data['data'] as List<dynamic>? ?? const [])
        .map((e) => DrugSearchItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination =
        response.data['pagination'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return DrugSearchPage(
      items: items,
      total: pagination['total'] as int? ?? items.length,
      page: pagination['page'] as int? ?? page,
      limit: pagination['limit'] as int? ?? limit,
    );
  }

  Future<DrugDetails> getByName(String name) async {
    final response = await _dio.get('/drugs/$name');
    return DrugDetails.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}

final drugRepositoryProvider = Provider<DrugRepository>((ref) {
  return DrugRepository(ref.watch(dioProvider));
});
