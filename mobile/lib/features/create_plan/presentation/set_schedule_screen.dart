import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/step_wizard_progress.dart';
import '../../home/data/plan_notifier.dart';
import '../../settings/data/settings_repository.dart';
import '../data/plan_repository.dart';
import '../domain/plan.dart';
import '../domain/scan_result.dart';

// ---------------------------------------------------------------------------
// Data model: a time slot with drugs assigned to it
// ---------------------------------------------------------------------------

class _TimeSlot {
  String time; // "HH:mm"

  _TimeSlot({required this.time});
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SetScheduleScreen extends ConsumerStatefulWidget {
  const SetScheduleScreen({
    super.key,
    required this.drugs,
    this.source = 'scan',
    this.existingPlan,
  });

  final List<PlanDrugItem> drugs;

  /// Nguồn gọi màn này: 'manual' (từ edit_drugs) hoặc 'scan' (từ scan_review).
  /// Dùng để điều hướng back đúng context.
  final String source;
  final Plan? existingPlan;

  @override
  ConsumerState<SetScheduleScreen> createState() => _SetScheduleScreenState();
}

class _SetScheduleScreenState extends ConsumerState<SetScheduleScreen> {
  static const List<String> _defaultSlotTimes = ['08:00', '12:00', '20:00'];

  late DateTime _startDate;
  late DateTime _endDate;
  late int _totalDays;
  bool _isSaving = false;

  // Time slots — default 3 common slots
  final List<_TimeSlot> _slots = [];

  // Per-drug per-slot pills (drug index -> {slot index: pills})
  late List<Map<int, int>> _dosePillsByDrugSlot;

  // Per-drug slot assignments (drug index -> slot indices)
  late List<Set<int>> _drugSlotIndices;

  @override
  void initState() {
    super.initState();
    _initializeDraft();
  }

  void _initializeDraft() {
    final existingPlan = widget.existingPlan;
    if (existingPlan == null) {
      _startDate = DateTime.now();
      final firstDays = widget.drugs.isEmpty ? 7 : widget.drugs.first.totalDays;
      _totalDays = firstDays;
      _endDate = _startDate.add(Duration(days: _totalDays - 1));

      // Build initial slots from default slot times + any parsed drug times
      final allTimesSet = <String>{..._defaultSlotTimes};
      for (final drug in widget.drugs) {
        if (drug.doseSchedule.isNotEmpty) {
          for (final ds in drug.doseSchedule) {
            allTimesSet.add(ds.time);
          }
        } else if (drug.times.isNotEmpty) {
          allTimesSet.addAll(drug.times);
        }
      }

      final sortedTimes = allTimesSet.toList()..sort();
      _slots
        ..clear()
        ..addAll(sortedTimes.map((time) => _TimeSlot(time: time)));

      _drugSlotIndices = List<Set<int>>.generate(widget.drugs.length, (_) => <int>{});
      _dosePillsByDrugSlot = List<Map<int, int>>.generate(widget.drugs.length, (_) => <int, int>{});

      for (int i = 0; i < widget.drugs.length; i++) {
        final drug = widget.drugs[i];
        if (drug.doseSchedule.isNotEmpty) {
          for (final ds in drug.doseSchedule) {
            final slotIdx = _slots.indexWhere((s) => s.time == ds.time);
            if (slotIdx != -1) {
              _drugSlotIndices[i].add(slotIdx);
              _dosePillsByDrugSlot[i][slotIdx] = ds.pills;
            }
          }
        } else if (drug.times.isNotEmpty) {
          for (final t in drug.times) {
            final slotIdx = _slots.indexWhere((s) => s.time == t);
            if (slotIdx != -1) {
              _drugSlotIndices[i].add(slotIdx);
              _dosePillsByDrugSlot[i][slotIdx] = drug.pillsPerDose;
            }
          }
        }

        // Fallback if no slots matched for this drug
        if (_drugSlotIndices[i].isEmpty && _slots.isNotEmpty) {
          _drugSlotIndices[i].add(0);
          _dosePillsByDrugSlot[i][0] = drug.pillsPerDose;
        }
      }
      return;
    }

    final parsedStart = existingPlan.parsedStartDate ?? DateTime.now();
    final parsedEnd =
        existingPlan.parsedEndDate ??
        parsedStart.add(Duration(days: (existingPlan.totalDays ?? 7) - 1));
    _startDate = DateTime(parsedStart.year, parsedStart.month, parsedStart.day);
    _endDate = DateTime(parsedEnd.year, parsedEnd.month, parsedEnd.day);
    _totalDays =
        existingPlan.totalDays ?? _endDate.difference(_startDate).inDays + 1;

    final existingTimes = existingPlan.slots.isEmpty
        ? _defaultSlotTimes
        : existingPlan.slots.map((slot) => slot.time).toList();
    _slots
      ..clear()
      ..addAll(existingTimes.map((time) => _TimeSlot(time: time)));

    _drugSlotIndices = List<Set<int>>.generate(
      widget.drugs.length,
      (_) => <int>{},
    );
    _dosePillsByDrugSlot = List<Map<int, int>>.generate(
      widget.drugs.length,
      (_) => <int, int>{},
    );

    for (var drugIndex = 0; drugIndex < widget.drugs.length; drugIndex++) {
      final currentDrug = widget.drugs[drugIndex];
      for (
        var slotIndex = 0;
        slotIndex < existingPlan.slots.length;
        slotIndex++
      ) {
        final slot = existingPlan.slots[slotIndex];
        for (final item in slot.items) {
          if (item.drugName.trim().toLowerCase() ==
              currentDrug.name.trim().toLowerCase()) {
            _drugSlotIndices[drugIndex].add(slotIndex);
            _dosePillsByDrugSlot[drugIndex][slotIndex] = item.pills;
            break;
          }
        }
      }

      if (_drugSlotIndices[drugIndex].isEmpty && _slots.isNotEmpty) {
        _drugSlotIndices[drugIndex].add(0);
        _dosePillsByDrugSlot[drugIndex][0] = currentDrug.pillsPerDose;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Date picking
  // -------------------------------------------------------------------------

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
      _totalDays = _endDate.difference(_startDate).inDays + 1;
      if (_totalDays < 1) _totalDays = 1;
    });
  }

  // -------------------------------------------------------------------------
  // Slot management
  // -------------------------------------------------------------------------

  Future<void> _editSlotTime(int slotIndex) async {
    final parts = _slots[slotIndex].time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: int.tryParse(parts.last) ?? 0,
      ),
    );
    if (picked == null) return;
    setState(() {
      _slots[slotIndex].time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  void _addSlot() {
    setState(() {
      _slots.add(_TimeSlot(time: '18:00'));
    });
  }

  void _removeSlot(int index) {
    if (_slots.length <= 1) return;
    setState(() {
      _slots.removeAt(index);
      for (var i = 0; i < _drugSlotIndices.length; i++) {
        final updated = <int>{};
        final currentPills = _dosePillsByDrugSlot[i];
        final updatedPills = <int, int>{};
        for (final slotIdx in _drugSlotIndices[i]) {
          if (slotIdx == index) continue;
          final normalized = slotIdx > index ? slotIdx - 1 : slotIdx;
          updated.add(normalized);
          updatedPills[normalized] = currentPills[slotIdx] ?? 1;
        }
        if (updated.isEmpty && _slots.isNotEmpty) {
          updated.add(0);
          updatedPills[0] = currentPills.values.isNotEmpty
              ? currentPills.values.first
              : 1;
        }
        _drugSlotIndices[i] = updated;
        _dosePillsByDrugSlot[i] = updatedPills;
      }
    });
  }

  void _toggleDrugInSlot(int drugIndex, int slotIndex) {
    setState(() {
      final assignedSlots = _drugSlotIndices[drugIndex];
      final pillMap = _dosePillsByDrugSlot[drugIndex];
      if (assignedSlots.contains(slotIndex)) {
        if (assignedSlots.length == 1) return;
        assignedSlots.remove(slotIndex);
        pillMap.remove(slotIndex);
      } else {
        assignedSlots.add(slotIndex);
        pillMap[slotIndex] = pillMap.values.isNotEmpty
            ? pillMap.values.first
            : 1;
      }
    });
  }

  Set<int> _assignedDrugsForSlot(int slotIndex) {
    final result = <int>{};
    for (var i = 0; i < _drugSlotIndices.length; i++) {
      if (_drugSlotIndices[i].contains(slotIndex)) {
        result.add(i);
      }
    }
    return result;
  }

  void _applyDailyPreset(int timesPerDay) {
    final presetTimes = switch (timesPerDay) {
      1 => <String>['08:00'],
      2 => <String>['08:00', '20:00'],
      _ => <String>['08:00', '12:00', '20:00'],
    };

    setState(() {
      _slots
        ..clear()
        ..addAll(presetTimes.map((time) => _TimeSlot(time: time)));

      final assignedAll = Set<int>.from(
        List<int>.generate(_slots.length, (index) => index),
      );
      for (var i = 0; i < _drugSlotIndices.length; i++) {
        _drugSlotIndices[i] = Set<int>.from(assignedAll);
        final firstPills = _dosePillsByDrugSlot[i].values.isNotEmpty
            ? _dosePillsByDrugSlot[i].values.first
            : 1;
        _dosePillsByDrugSlot[i] = {
          for (var slotIndex = 0; slotIndex < _slots.length; slotIndex++)
            slotIndex: firstPills,
        };
      }
    });
  }

  String _slotPreviewText(Set<int> assignedDrugIndices) {
    final l10n = AppLocalizations.of(context);
    if (assignedDrugIndices.isEmpty) {
      return l10n.scheduleSlotNoSelection;
    }

    final names = assignedDrugIndices
        .where((index) => index >= 0 && index < widget.drugs.length)
        .map((index) => widget.drugs[index].name)
        .toList();
    names.sort();

    if (names.length <= 3) {
      return l10n.scheduleSlotDrugPreview(names.join(', '));
    }

    final firstThree = names.take(3).join(', ');
    return l10n.scheduleSlotDrugPreviewMore(firstThree, names.length - 3);
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  List<DoseScheduleItem> _buildDoseScheduleForDrug(int drugIndex) {
    final sortedSlots = _drugSlotIndices[drugIndex].toList()..sort();
    return sortedSlots
        .where((slotIndex) => slotIndex >= 0 && slotIndex < _slots.length)
        .map(
          (slotIndex) => DoseScheduleItem(
            time: _slots[slotIndex].time,
            pills: _dosePillsByDrugSlot[drugIndex][slotIndex] ?? 1,
          ),
        )
        .toList();
  }

  void _changeDosePills(int drugIndex, int slotIndex, int delta) {
    setState(() {
      final current = _dosePillsByDrugSlot[drugIndex][slotIndex] ?? 1;
      final next = (current + delta).clamp(1, 10);
      _dosePillsByDrugSlot[drugIndex][slotIndex] = next;
    });
  }

  void _goBack() {
    if (widget.source == 'plan_edit' && widget.existingPlan != null) {
      context.go('/plans/${widget.existingPlan!.id}');
    } else if (widget.source == 'manual') {
      // Manual path: trở về màn danh sách thuốc với drugs hiện tại.
      context.go('/create/edit', extra: widget.drugs);
    } else {
      // Scan path: trở về scan review screen (giữ nguyên behavior cũ).
      final drugs = widget.drugs
          .map(
            (drug) => DetectedDrug(
              name: drug.name,
              dosage: drug.dosage,
              mappingStatus: 'confirmed',
              confidence: 1.0,
              mappedDrugName: drug.name,
            ),
          )
          .toList();
      context.go(
        '/create/review',
        extra: ScanResult(scanId: 'schedule-back', drugs: drugs),
      );
    }
  }

  PrescriptionPlanDraft _buildPlanDraft(String startDateStr) {
    final l10n = AppLocalizations.of(context);
    final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate);
    final drugs = widget.drugs.asMap().entries.map((entry) {
      final index = entry.key;
      final drug = entry.value;
      return PlanMedication(
        id: 'draft-drug-$index',
        drugName: drug.name,
        dosage: drug.dosage.isEmpty ? null : drug.dosage,
        notes: drug.notes.isEmpty ? null : drug.notes,
        sortOrder: index,
      );
    }).toList();

    final slots = _slots
        .asMap()
        .entries
        .map((entry) {
          final slotIndex = entry.key;
          final slot = entry.value;
          final assignedDrugIndices = _assignedDrugsForSlot(slotIndex).toList()
            ..sort();
          final items = assignedDrugIndices.map((drugIndex) {
            final drug = widget.drugs[drugIndex];
            return PlanSlotMedication(
              drugId: 'draft-drug-$drugIndex',
              drugName: drug.name,
              dosage: drug.dosage.isEmpty ? null : drug.dosage,
              pills: _dosePillsByDrugSlot[drugIndex][slotIndex] ?? 1,
            );
          }).toList();
          return PlanSlot(
            id: 'draft-slot-$slotIndex',
            time: slot.time,
            sortOrder: slotIndex,
            items: items,
          );
        })
        .where((slot) => slot.items.isNotEmpty)
        .toList();

    final title = widget.drugs.isEmpty
        ? l10n.schedulePlanTitleDefault
        : widget.drugs.length == 1
        ? widget.drugs.first.name
        : l10n.schedulePlanTitleMultiple(
            widget.drugs.first.name,
            widget.drugs.length - 1,
          );

    return PrescriptionPlanDraft(
      title: title,
      drugs: drugs,
      slots: slots,
      totalDays: _totalDays,
      startDate: startDateStr,
      endDate: endDateStr,
    );
  }

  Future<void> _savePlans() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isSaving = true);
    final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate);
    try {
      final repo = ref.read(planRepositoryProvider);
      final notificationService = ref.read(notificationServiceProvider);
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final remindersEnabled = await settingsRepo.getRemindersEnabled();

      final draft = _buildPlanDraft(startDateStr);
      final savedPlan = widget.existingPlan == null
          ? await repo.createPlan(draft)
          : await repo.updatePlan(
              widget.existingPlan!.id,
              widget.existingPlan!.copyWith(
                title: draft.title ?? widget.existingPlan!.title,
                drugs: draft.drugs,
                slots: draft.slots,
                totalDays: draft.totalDays,
                startDate: draft.startDate,
                endDate: draft.endDate,
                notes: draft.notes,
              ),
            );
      notificationService.markNotificationsDirty(
        widget.existingPlan == null ? 'plan_created' : 'plan_updated',
      );
      if (remindersEnabled) {
        try {
          await notificationService.schedulePlanNotifications(savedPlan);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[SetScheduleScreen] Notification error: $e');
          }
        }
      } else if (widget.existingPlan != null) {
        await notificationService.cancelPlanNotifications(
          widget.existingPlan!.id,
        );
      }

      if (!mounted) return;
      ref.invalidate(planNotifierProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existingPlan == null
                ? l10n.scheduleSaveSuccess
                : 'Đã cập nhật kế hoạch uống thuốc',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      if (widget.existingPlan != null) {
        context.go('/plans/${widget.existingPlan!.id}');
      } else {
        context.go('/plans');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final l10nInner = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.type == DioExceptionType.connectionError
                ? l10nInner.scheduleSaveErrorConnection
                : e.response?.statusCode == 401
                ? l10nInner.scheduleSaveErrorSession
                : l10nInner.scheduleSaveErrorGeneric,
          ),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _isSaving = false);
    } catch (e) {
      if (!mounted) return;
      final l10nInner = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10nInner.scheduleSaveErrorUnknown(e.toString())),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _isSaving = false);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final df = DateFormat('dd/MM');
    final startStr = df.format(_startDate);
    final endStr = df.format(_endDate);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scheduleTitle),
        leading: IconButton(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          const StepWizardProgress(currentStep: 3),
          const SizedBox(height: 12),
          // ── Header summary ──
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.scheduleHeaderTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            l10n.scheduleHeaderSubtitle,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Date range ──
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(l10n.scheduleDateRangeLabel),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DateCard(
                        label: l10n.scheduleDateStart,
                        value: startStr,
                        onTap: () => _pickDate(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateCard(
                        label: l10n.scheduleDateEnd,
                        value: endStr,
                        onTap: () => _pickDate(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    l10n.scheduleDateSummary(_totalDays, startStr, endStr),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick preset ──
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(l10n.schedulePresetLabel),
                const SizedBox(height: 8),
                Text(
                  l10n.schedulePresetHint,
                  style: const TextStyle(color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _applyDailyPreset(1),
                      icon: const Icon(Icons.wb_sunny_outlined),
                      label: Text(l10n.schedulePreset1),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _applyDailyPreset(2),
                      icon: const Icon(Icons.wb_twilight_outlined),
                      label: Text(l10n.schedulePreset2),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _applyDailyPreset(3),
                      icon: const Icon(Icons.auto_awesome_motion_outlined),
                      label: Text(l10n.schedulePreset3),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Fine tune ──
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              l10n.scheduleSlotsLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),

          // ── Slots ──
          ..._slots.asMap().entries.map((entry) {
            final slotIndex = entry.key;
            final slot = entry.value;
            final assignedDrugIndices = _assignedDrugsForSlot(slotIndex);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _TimeSlotCard(
                slot: slot,
                slotIndex: slotIndex,
                drugs: widget.drugs,
                assignedDrugIndices: assignedDrugIndices,
                slotPreviewText: _slotPreviewText(assignedDrugIndices),
                onEditTime: () => _editSlotTime(slotIndex),
                onRemove: _slots.length > 1
                    ? () => _removeSlot(slotIndex)
                    : null,
                onToggleDrug: (di) => _toggleDrugInSlot(di, slotIndex),
              ),
            );
          }),

          // Add slot button
          OutlinedButton.icon(
            onPressed: _addSlot,
            icon: const Icon(Icons.add_alarm),
            label: Text(l10n.scheduleAddSlot),
          ),
          const SizedBox(height: 16),

          // ── Pills per dose per drug ──
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(l10n.schedulePillsLabel),
                const SizedBox(height: 6),
                Text(
                  l10n.schedulePillsHint,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ..._slots.asMap().entries.map((slotEntry) {
                  final slotIndex = slotEntry.key;
                  final slot = slotEntry.value;
                  final assignedDrugIndices = _assignedDrugsForSlot(
                    slotIndex,
                  ).toList()..sort();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slot.time,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        if (assignedDrugIndices.isEmpty)
                          Text(
                            l10n.scheduleSlotNoDrug,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          ...assignedDrugIndices.map((drugIndex) {
                            final drug = widget.drugs[drugIndex];
                            final pills =
                                _dosePillsByDrugSlot[drugIndex][slotIndex] ?? 1;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      drug.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  _PillStepper(
                                    value: pills,
                                    onMinus: pills > 1
                                        ? () => _changeDosePills(
                                            drugIndex,
                                            slotIndex,
                                            -1,
                                          )
                                        : null,
                                    onPlus: pills < 10
                                        ? () => _changeDosePills(
                                            drugIndex,
                                            slotIndex,
                                            1,
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Summary ──
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(l10n.scheduleReviewLabel),
                const SizedBox(height: 10),
                ..._buildSummaryLines(l10n),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _savePlans,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    l10n.scheduleSave,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSummaryLines(AppLocalizations l10n) {
    return widget.drugs.asMap().entries.map((entry) {
      final idx = entry.key;
      final drug = entry.value;
      final doseSchedule = _buildDoseScheduleForDrug(idx);
      final summary = doseSchedule
          .map((item) => l10n.scheduleSummaryDose(item.time, item.pills))
          .join(', ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.medication_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.scheduleSummaryLine(drug.name, summary),
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ---------------------------------------------------------------------------
// Time slot card
// ---------------------------------------------------------------------------

class _TimeSlotCard extends StatelessWidget {
  const _TimeSlotCard({
    required this.slot,
    required this.slotIndex,
    required this.drugs,
    required this.assignedDrugIndices,
    required this.slotPreviewText,
    required this.onEditTime,
    required this.onToggleDrug,
    this.onRemove,
  });

  final _TimeSlot slot;
  final int slotIndex;
  final List<PlanDrugItem> drugs;
  final Set<int> assignedDrugIndices;
  final String slotPreviewText;
  final VoidCallback onEditTime;
  final void Function(int drugIndex) onToggleDrug;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: AppColors.primaryDark,
                size: 20,
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEditTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    slot.time,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.scheduleSlotDrugCount(assignedDrugIndices.length),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: AppColors.error,
                  ),
                  iconSize: 20,
                  tooltip: l10n.scheduleSlotRemoveTooltip,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            slotPreviewText,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.scheduleSlotChooseDrug,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: drugs.asMap().entries.map((e) {
              final selected = assignedDrugIndices.contains(e.key);
              return FilterChip(
                selected: selected,
                label: Text(
                  e.value.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selectedColor: AppColors.primary.withValues(alpha: 0.18),
                checkmarkColor: AppColors.primaryDark,
                labelStyle: TextStyle(
                  color: selected
                      ? AppColors.primaryDark
                      : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
                onSelected: (_) => onToggleDrug(e.key),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared UI components
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
        fontSize: 13,
      ),
    );
  }
}

class _DateCard extends StatelessWidget {
  const _DateCard({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.primaryDark,
              size: 18,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PillStepper extends StatelessWidget {
  const _PillStepper({
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });
  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(icon: Icons.remove_rounded, onTap: onMinus),
        Container(
          width: 44,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        _StepBtn(icon: Icons.add_rounded, onTap: onPlus),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.surfaceHigh : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? AppColors.textMuted : AppColors.primaryDark,
        ),
      ),
    );
  }
}
