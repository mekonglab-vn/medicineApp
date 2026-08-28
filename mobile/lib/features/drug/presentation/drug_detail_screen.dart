import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/drug_repository.dart';

class DrugDetailScreen extends StatelessWidget {
  const DrugDetailScreen({
    super.key,
    required this.details,
    this.activeIngredient,
  });

  final DrugDetails details;
  final String? activeIngredient;

  @override
  Widget build(BuildContext context) {
    final raw = details.raw ?? const <String, dynamic>{};
    final usage = raw['chiDinh']?.toString();
    final sideEffects = raw['tacDungPhu']?.toString();
    final dosageInfo =
        raw['lieuDung']?.toString() ?? raw['dosage_info']?.toString();
    final manufacturer =
        raw['coSoDangKy']?.toString() ?? raw['nhaSanXuat']?.toString();
    final registration = raw['soDangKy']?.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Thông tin thuốc')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      width: 2,
                    ),
                    color: AppColors.surfaceSoft,
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    size: 54,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  details.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (activeIngredient != null &&
                    activeIngredient!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    activeIngredient!,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _InfoCard(
            background: AppColors.infoCard,
            title: 'Thông tin cơ bản',
            children: [
              _InfoLine(label: 'Nguồn', value: details.source ?? 'local'),
              if (registration != null && registration.isNotEmpty)
                _InfoLine(label: 'Số đăng ký', value: registration),
              if (manufacturer != null && manufacturer.isNotEmpty)
                _InfoLine(label: 'Cơ sở đăng ký', value: manufacturer),
              if (activeIngredient != null && activeIngredient!.isNotEmpty)
                _InfoLine(label: 'Hoạt chất', value: activeIngredient!),
            ],
          ),
          const SizedBox(height: 14),
          _InfoCard(
            title: 'Cách dùng',
            children: [
              Text(
                dosageInfo != null && dosageInfo.trim().isNotEmpty
                    ? dosageInfo
                    : 'Chưa có thông tin liều dùng chi tiết.',
                style: const TextStyle(height: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoCard(
            title: 'Chỉ định',
            children: [
              Text(
                usage != null && usage.trim().isNotEmpty
                    ? usage
                    : 'Chưa có thông tin chỉ định chi tiết.',
                style: const TextStyle(height: 1.5),
              ),
            ],
          ),
          if (sideEffects != null && sideEffects.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _InfoCard(
              title: 'Tác dụng phụ',
              children: [
                Text(sideEffects, style: const TextStyle(height: 1.5)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.children,
    this.background,
  });

  final String title;
  final List<Widget> children;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
