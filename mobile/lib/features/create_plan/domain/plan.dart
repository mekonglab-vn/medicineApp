class DoseScheduleItem {
  final String time;
  final int pills;

  const DoseScheduleItem({required this.time, required this.pills});

  factory DoseScheduleItem.fromJson(Map<String, dynamic> json) =>
      DoseScheduleItem(
        time: json['time'] as String? ?? '',
        pills: json['pills'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {'time': time, 'pills': pills};

  DoseScheduleItem copyWith({String? time, int? pills}) =>
      DoseScheduleItem(time: time ?? this.time, pills: pills ?? this.pills);
}

class PlanDrugItem {
  String name;
  String dosage;
  int pillsPerDose;
  String frequency;
  List<String> times;
  List<DoseScheduleItem> doseSchedule;
  int totalDays;
  String notes;

  PlanDrugItem({
    required this.name,
    this.dosage = '',
    this.pillsPerDose = 1,
    this.frequency = 'daily',
    List<String>? times,
    List<DoseScheduleItem>? doseSchedule,
    this.totalDays = 7,
    this.notes = '',
  }) : times = (times == null || times.isEmpty)
           ? ['07:00']
           : List<String>.from(times),
       doseSchedule = _normalizeDoseSchedule(
         times: times,
         doseSchedule: doseSchedule,
         fallbackPills: pillsPerDose,
       ) {
    this.times = this.doseSchedule.map((item) => item.time).toList()..sort();
    if (this.doseSchedule.isNotEmpty) {
      pillsPerDose = this.doseSchedule.first.pills;
      frequency = _frequencyFromLength(this.doseSchedule.length, frequency);
    }
  }

  bool get hasVariableDoseSchedule =>
      doseSchedule.map((item) => item.pills).toSet().length > 1;

  String get scheduleSummary => doseSchedule
      .map((item) => '${item.time}: ${item.pills} viên')
      .join(' · ');

  PlanDrugItem copyWith({
    String? name,
    String? dosage,
    int? pillsPerDose,
    String? frequency,
    List<String>? times,
    List<DoseScheduleItem>? doseSchedule,
    int? totalDays,
    String? notes,
  }) {
    return PlanDrugItem(
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      pillsPerDose: pillsPerDose ?? this.pillsPerDose,
      frequency: frequency ?? this.frequency,
      times: times ?? List<String>.from(this.times),
      doseSchedule:
          doseSchedule ??
          this.doseSchedule.map((item) => item.copyWith()).toList(),
      totalDays: totalDays ?? this.totalDays,
      notes: notes ?? this.notes,
    );
  }
}

class PlanEditFlowArgs {
  const PlanEditFlowArgs({
    required this.drugs,
    this.existingPlan,
    this.source = 'manual',
  });

  final List<PlanDrugItem> drugs;
  final Plan? existingPlan;
  final String source;

  factory PlanEditFlowArgs.fromPlan(Plan plan, {String source = 'plan_edit'}) {
    return PlanEditFlowArgs(
      source: source,
      existingPlan: plan,
      drugs: plan.drugs
          .map(
            (drug) => PlanDrugItem(
              name: drug.drugName,
              dosage: drug.dosage ?? '',
              totalDays: plan.totalDays ?? 7,
              notes: drug.notes ?? '',
            ),
          )
          .toList(),
    );
  }
}

class PlanMedication {
  final String id;
  final String drugName;
  final String? dosage;
  final String? notes;
  final int sortOrder;

  const PlanMedication({
    required this.id,
    required this.drugName,
    this.dosage,
    this.notes,
    this.sortOrder = 0,
  });

  factory PlanMedication.fromJson(Map<String, dynamic> json) => PlanMedication(
    id: json['id'] as String? ?? '',
    drugName: json['drugName'] as String? ?? json['drug_name'] as String? ?? '',
    dosage: json['dosage'] as String?,
    notes: json['notes'] as String?,
    sortOrder: json['sortOrder'] as int? ?? json['sort_order'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'drugName': drugName,
    if (dosage != null) 'dosage': dosage,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
    'sortOrder': sortOrder,
  };
}

class PlanSlotMedication {
  final String? drugId;
  final String drugName;
  final String? dosage;
  final int pills;

  const PlanSlotMedication({
    this.drugId,
    required this.drugName,
    this.dosage,
    required this.pills,
  });

  factory PlanSlotMedication.fromJson(Map<String, dynamic> json) =>
      PlanSlotMedication(
        drugId: json['drugId'] as String? ?? json['drug_id'] as String?,
        drugName:
            json['drugName'] as String? ?? json['drug_name'] as String? ?? '',
        dosage: json['dosage'] as String?,
        pills: json['pills'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {
    if (drugId != null && drugId!.isNotEmpty) 'drugId': drugId,
    'drugName': drugName,
    if (dosage != null) 'dosage': dosage,
    'pills': pills,
  };
}

class PlanSlot {
  final String id;
  final String time;
  final int sortOrder;
  final List<PlanSlotMedication> items;

  const PlanSlot({
    required this.id,
    required this.time,
    required this.items,
    this.sortOrder = 0,
  });

  factory PlanSlot.fromJson(Map<String, dynamic> json) => PlanSlot(
    id: json['id'] as String? ?? '',
    time: json['time'] as String? ?? '',
    sortOrder: json['sortOrder'] as int? ?? json['sort_order'] as int? ?? 0,
    items: (json['items'] as List<dynamic>? ?? const [])
        .map((e) => PlanSlotMedication.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'time': time,
    'sortOrder': sortOrder,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

class PrescriptionPlanDraft {
  final String? title;
  final List<PlanMedication> drugs;
  final List<PlanSlot> slots;
  final int? totalDays;
  final String startDate;
  final String? endDate;
  final String? notes;

  const PrescriptionPlanDraft({
    this.title,
    required this.drugs,
    required this.slots,
    this.totalDays,
    required this.startDate,
    this.endDate,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
    'drugs': drugs.map((drug) => drug.toJson()).toList(),
    'slots': slots.map((slot) => slot.toJson()).toList(),
    if (totalDays != null) 'totalDays': totalDays,
    'startDate': startDate,
    if (endDate != null) 'endDate': endDate,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };
}

class Plan {
  final String id;
  final String title;
  final List<PlanMedication> drugs;
  final List<PlanSlot> slots;
  final int? totalDays;
  final String startDate;
  final String? endDate;
  final bool isActive;
  final String? notes;

  const Plan({
    required this.id,
    required this.title,
    this.drugs = const [],
    this.slots = const [],
    this.totalDays,
    required this.startDate,
    this.endDate,
    this.isActive = true,
    this.notes,
  });

  DateTime? get parsedStartDate => DateTime.tryParse(startDate);

  DateTime? get parsedEndDate => endDate == null || endDate!.trim().isEmpty
      ? null
      : DateTime.tryParse(endDate!);

  bool get hasEnded {
    final end = parsedEndDate;
    if (end == null) return !isActive;

    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final endKey = DateTime(end.year, end.month, end.day);
    return !isActive || endKey.isBefore(todayKey);
  }

  bool get isCurrentPlan => isActive && !hasEnded;

  String get drugName {
    if (title.trim().isNotEmpty) return title;
    if (drugs.isEmpty) return 'Kế hoạch thuốc';
    if (drugs.length == 1) return drugs.first.drugName;
    final preview = drugs.take(2).map((d) => d.drugName).join(', ');
    return '$preview${drugs.length > 2 ? ' và ${drugs.length - 2} thuốc khác' : ''}';
  }

  String? get dosage => null;

  String get frequency => _frequencyFromLength(slots.length, 'daily');

  List<String> get times => slots.map((slot) => slot.time).toList()..sort();

  int get pillsPerDose {
    if (slots.isEmpty || slots.first.items.isEmpty) return 1;
    return slots.first.items.first.pills;
  }

  List<DoseScheduleItem> get doseSchedule {
    return slots
        .map(
          (slot) => DoseScheduleItem(
            time: slot.time,
            pills: slot.items.fold(0, (sum, item) => sum + item.pills),
          ),
        )
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  bool get hasVariableDoseSchedule =>
      doseSchedule.map((item) => item.pills).toSet().length > 1;

  String get scheduleSummary => doseSchedule
      .map((item) => '${item.time}: ${item.pills} viên')
      .join(' · ');

  int pillsForTime(String time) {
    for (final slot in slots) {
      if (slot.time == time) {
        return slot.items.fold(0, (sum, item) => sum + item.pills);
      }
    }
    return pillsPerDose;
  }

  List<PlanSlotMedication> medicationsForTime(String time) {
    for (final slot in slots) {
      if (slot.time == time) return slot.items;
    }
    return const [];
  }

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    drugs: (json['drugs'] as List<dynamic>? ?? const [])
        .map((e) => PlanMedication.fromJson(e as Map<String, dynamic>))
        .toList(),
    slots:
        (json['slots'] as List<dynamic>? ?? const [])
            .map((e) => PlanSlot.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time)),
    totalDays: json['total_days'] as int? ?? json['totalDays'] as int?,
    startDate:
        json['start_date'] as String? ?? json['startDate'] as String? ?? '',
    endDate: json['end_date'] as String? ?? json['endDate'] as String?,
    isActive: json['is_active'] as bool? ?? json['isActive'] as bool? ?? true,
    notes: json['notes'] as String?,
  );

  Map<String, dynamic> toUpdateJson() => {
    'title': title,
    'drugs': drugs.map((drug) => drug.toJson()).toList(),
    'slots': slots.map((slot) => slot.toJson()).toList(),
    if (totalDays != null) 'totalDays': totalDays,
    'startDate': startDate,
    if (endDate != null) 'endDate': endDate,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };

  Plan copyWith({
    String? id,
    String? title,
    List<PlanMedication>? drugs,
    List<PlanSlot>? slots,
    int? totalDays,
    String? startDate,
    String? endDate,
    bool? isActive,
    String? notes,
  }) {
    return Plan(
      id: id ?? this.id,
      title: title ?? this.title,
      drugs: drugs ?? this.drugs,
      slots: slots ?? this.slots,
      totalDays: totalDays ?? this.totalDays,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
    );
  }
}

List<DoseScheduleItem> _normalizeDoseSchedule({
  List<String>? times,
  List<DoseScheduleItem>? doseSchedule,
  required int fallbackPills,
}) {
  if (doseSchedule != null && doseSchedule.isNotEmpty) {
    final items = doseSchedule
        .where((item) => item.time.isNotEmpty)
        .map((item) => item.copyWith(pills: item.pills < 1 ? 1 : item.pills))
        .toList();
    items.sort((a, b) => a.time.compareTo(b.time));
    return items;
  }
  final resolvedTimes = (times == null || times.isEmpty) ? ['07:00'] : times;
  final items = resolvedTimes
      .map((time) => DoseScheduleItem(time: time, pills: fallbackPills))
      .toList();
  items.sort((a, b) => a.time.compareTo(b.time));
  return items;
}

String _frequencyFromLength(int count, String fallback) {
  return switch (count) {
    1 => 'daily',
    2 => 'twice_daily',
    3 => 'three_daily',
    _ => fallback,
  };
}
