import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_notifier.dart';
import '../../home/data/plan_notifier.dart';
import '../../home/data/today_schedule_notifier.dart';
import '../data/settings_notifier.dart';
import '../../../core/notifications/notification_service.dart';

Future<void> _logoutCleanup(WidgetRef ref) async {
  await ref.read(notificationServiceProvider).cancelAllNotifications();
  await ref.read(planNotifierProvider.notifier).clearForCurrentUser();
  await ref.read(todayScheduleNotifierProvider.notifier).clearForCurrentUser();
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _showScheduledRemindersReport(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final notificationService = ref.read(notificationServiceProvider);
    await ref
        .read(planNotifierProvider.notifier)
        .ensureNotificationsSynced(
          force: true,
          reason: 'settings_report_force',
        );
    final report = await notificationService.buildScheduledRemindersReport();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Báo cáo lịch nhắc trên thiết bị'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                report,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMiuiChecklist(BuildContext context) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Checklist Tối ưu Pin nền / MIUI'),
          content: const SingleChildScrollView(
            child: SelectableText(
              '1) Cài đặt > Ứng dụng > Uống thuốc > Tự khởi động: BẬT.\n\n'
              '2) Cài đặt > Pin > Tiết kiệm pin ứng dụng > Uống thuốc: Không hạn chế.\n\n'
              '3) Quyền thông báo:\n'
              '   - Hiển thị trên màn hình khóa\n'
              '   - Pop-up banner & Âm thanh\n\n'
              '4) Khóa ứng dụng trong cửa sổ Đa nhiệm (Recent Apps).',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Đã hiểu'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final settingsState = settingsAsync.asData?.value ?? const SettingsState();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Cài đặt'),
      ),
      body: ListView(
        children: [
          _buildSection('Tài khoản', [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Hồ sơ cá nhân'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ]),
          _buildSection('Thông báo & Dữ liệu', [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Nhắc uống thuốc'),
              subtitle: const Text('Báo chuông khi đến giờ uống thuốc'),
              value: settingsState.remindersEnabled,
              thumbColor: WidgetStateProperty.all(AppColors.primary),
              onChanged: settingsAsync.isLoading
                  ? null
                  : (v) async {
                      final success = await ref
                          .read(settingsNotifierProvider.notifier)
                          .setRemindersEnabled(v);
                      if (!context.mounted) return;
                      final message = success
                          ? (v
                              ? 'Đã bật nhắc uống thuốc'
                              : 'Đã tắt nhắc uống thuốc')
                          : 'Chưa có quyền thông báo hệ thống';
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    },
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Cập nhật dữ liệu mới'),
              subtitle: const Text('Tải lại lịch uống & danh sách thuốc mới nhất'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await ref.read(planNotifierProvider.notifier).refresh();
                await ref
                    .read(planNotifierProvider.notifier)
                    .ensureNotificationsSynced(
                      force: true,
                      reason: 'settings_manual_sync',
                    );
                await ref
                    .read(todayScheduleNotifierProvider.notifier)
                    .refresh();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã cập nhật dữ liệu xong')),
                );
              },
            ),
          ]),
          _buildSection('Ứng dụng', [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Phiên bản ứng dụng'),
              trailing: const Text(
                'v1.0.0',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),

          // Collapsible Developer Tools to prevent visual noise for end users
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ExpansionTile(
              leading: const Icon(Icons.bug_report_outlined, color: AppColors.textMuted),
              title: const Text(
                'Mục kiểm tra kỹ thuật (Dành cho Dev)',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              children: [
                ListTile(
                  leading: const Icon(Icons.notification_add_outlined),
                  title: const Text('Gửi chuỗi nhắc test (5 lần)'),
                  subtitle: const Text('Test nhắc trước giờ, đúng giờ & trễ'),
                  onTap: () async {
                    await ref
                        .read(notificationServiceProvider)
                        .sendDebugNotificationsBurst();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã lên lịch 5 thông báo test')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Gửi chuỗi nhắc theo phút'),
                  onTap: () async {
                    await ref
                        .read(notificationServiceProvider)
                        .sendDebugNotificationsMinuteScale();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã lên lịch nhắc 1-5 phút')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.screen_lock_portrait_outlined),
                  title: const Text('Hiện thông báo ngay'),
                  onTap: () async {
                    await ref
                        .read(notificationServiceProvider)
                        .showImmediateLockscreenTest();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Báo cáo lịch nhắc thiết bị'),
                  onTap: () async {
                    await _showScheduledRemindersReport(context, ref);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.battery_saver_outlined),
                  title: const Text('Checklist tối ưu Pin nền'),
                  onTap: () async {
                    await _showMiuiChecklist(context);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: () async {
                await _logoutCleanup(ref);
                await ref.read(authNotifierProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout, color: AppColors.error),
              label: const Text(
                'Đăng xuất',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...children,
        const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}
