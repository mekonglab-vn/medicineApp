import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/today_schedule.dart';

class DoseTimelineCard extends StatelessWidget {
  const DoseTimelineCard({
    super.key,
    required this.dose,
    required this.canMark,
    required this.onTap,
    required this.onTaken,
    this.onTakenWithPhoto,
    this.onSkipped,
  });

  final TodayDose dose;
  final bool canMark;
  final VoidCallback onTap;
  final VoidCallback onTaken;
  final Function(String photoPath)? onTakenWithPhoto;
  final VoidCallback? onSkipped;

  Future<void> _handlePhotoProof() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 80,
      );
      if (file != null && onTakenWithPhoto != null) {
        onTakenWithPhoto!(file.path);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = dose.effectiveStatus(now);
    final scheduled = dose.scheduledLocalDateTime;
    final timeStr = scheduled != null
        ? '${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}'
        : dose.time;

    Color badgeBg;
    Color badgeFg;
    IconData badgeIcon;
    String statusText;

    switch (status) {
      case 'taken':
        badgeBg = AppColors.success.withValues(alpha: 0.12);
        badgeFg = AppColors.success;
        badgeIcon = Icons.check_circle_rounded;
        statusText = 'Đã uống';
        break;
      case 'skipped':
        badgeBg = AppColors.warning.withValues(alpha: 0.12);
        badgeFg = AppColors.warning;
        badgeIcon = Icons.remove_circle_outline_rounded;
        statusText = 'Đã bỏ qua';
        break;
      case 'missed':
        badgeBg = AppColors.error.withValues(alpha: 0.12);
        badgeFg = AppColors.error;
        badgeIcon = Icons.error_outline_rounded;
        statusText = 'Trễ liều';
        break;
      default:
        badgeBg = AppColors.primary.withValues(alpha: 0.14);
        badgeFg = AppColors.primaryDark;
        badgeIcon = Icons.schedule_rounded;
        statusText = 'Chờ uống';
        break;
    }

    final medications = dose.medications
        .where((m) => m.drugName.trim().isNotEmpty)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: status == 'pending' && dose.isDueNow(now)
              ? AppColors.primary
              : AppColors.border,
          width: status == 'pending' && dose.isDueNow(now) ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 16,
                            color: AppColors.primaryDark,
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        dose.primaryTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + 2,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 14, color: badgeFg),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: badgeFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (medications.isNotEmpty) ...[
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: medications.map((med) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm + 2,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          '${med.drugName} × ${med.pills} viên',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ] else ...[
                  Text(
                    dose.dosage != null && dose.dosage!.isNotEmpty
                        ? dose.dosage!
                        : '${dose.pillsPerDose ?? 1} viên/liều',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (status == 'pending' || status == 'missed') ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: canMark ? onTaken : null,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Đã uống'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 42),
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                          ),
                        ),
                      ),
                      if (onTakenWithPhoto != null) ...[
                        const SizedBox(width: AppSpacing.xs + 2),
                        IconButton.outlined(
                          onPressed: canMark ? _handlePhotoProof : null,
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          tooltip: 'Uống & Chụp ảnh',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(42, 42),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                          ),
                        ),
                      ],
                      if (onSkipped != null) ...[
                        const SizedBox(width: AppSpacing.xs + 2),
                        OutlinedButton(
                          onPressed: canMark ? onSkipped : null,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(42, 42),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                          ),
                          child: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
