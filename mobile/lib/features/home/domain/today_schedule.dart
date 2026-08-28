class DoseExpectedMedication {
  const DoseExpectedMedication({
    required this.planId,
    required this.drugName,
    this.occurrenceId,
    this.dosage,
    this.pillsPerDose,
  });

  final String planId;
  final String drugName;
  final String? occurrenceId;
  final String? dosage;
  final int? pillsPerDose;

  factory DoseExpectedMedication.fromJson(Map<String, dynamic> json) =>
      DoseExpectedMedication(
        planId: json['planId'] as String? ?? '',
        drugName: json['drugName'] as String? ?? '',
        occurrenceId: json['occurrenceId'] as String?,
        dosage: json['dosage'] as String?,
        pillsPerDose: json['pillsPerDose'] as int?,
      );

  Map<String, dynamic> toJson() => {
    'planId': planId,
    'drugName': drugName,
    if (occurrenceId != null) 'occurrenceId': occurrenceId,
    if (dosage != null) 'dosage': dosage,
    if (pillsPerDose != null) 'pillsPerDose': pillsPerDose,
  };
}

class TodayDoseMedication {
  const TodayDoseMedication({
    required this.drugName,
    required this.pills,
    this.dosage,
  });

  final String drugName;
  final int pills;
  final String? dosage;

  factory TodayDoseMedication.fromJson(Map<String, dynamic> json) =>
      TodayDoseMedication(
        drugName:
            json['drugName'] as String? ?? json['drug_name'] as String? ?? '',
        pills: json['pills'] as int? ?? 1,
        dosage: json['dosage'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'drugName': drugName,
    'pills': pills,
    if (dosage != null) 'dosage': dosage,
  };
}

class TodayDose {
  static const Duration reminderLeadTime = Duration(minutes: 30);
  static const Duration missedAfter = Duration(minutes: 45);

  const TodayDose({
    required this.occurrenceId,
    required this.planId,
    this.title,
    required this.drugName,
    required this.time,
    required this.scheduledTime,
    required this.status,
    this.dosage,
    this.pillsPerDose,
    this.notes,
    this.takenAt,
    this.note,
    this.hasReferenceProfile = false,
    this.referenceProfileStatus,
    this.verificationReady = false,
    this.expectedMedications = const [],
    this.missingReferenceDrugNames = const [],
    this.medications = const [],
  });

  final String occurrenceId;
  final String planId;
  final String? title;
  final String drugName;
  final String time;
  final String scheduledTime;
  final String status;
  final String? dosage;
  final int? pillsPerDose;
  final String? notes;
  final String? takenAt;
  final String? note;
  final bool hasReferenceProfile;
  final String? referenceProfileStatus;
  final bool verificationReady;
  final List<DoseExpectedMedication> expectedMedications;
  final List<String> missingReferenceDrugNames;
  final List<TodayDoseMedication> medications;

  bool get isGroupedDose => medications.length > 1;

  String get primaryTitle =>
      (title != null && title!.trim().isNotEmpty) ? title!.trim() : drugName;

  DateTime? get scheduledLocalDateTime {
    final parsed = DateTime.tryParse(scheduledTime);
    return parsed?.toLocal();
  }

  String effectiveStatus(DateTime now) {
    if (status != 'pending') return status;
    if (shouldAutoMiss(now)) return 'missed';
    return 'pending';
  }

  bool isUpcomingSoon(DateTime now) {
    if (effectiveStatus(now) != 'pending') return false;
    final scheduled = scheduledLocalDateTime;
    if (scheduled == null) return false;
    final diff = scheduled.difference(now).inMinutes;
    return diff >= 0 && diff <= reminderLeadTime.inMinutes;
  }

  bool isDueNow(DateTime now) {
    if (effectiveStatus(now) != 'pending') return false;
    final scheduled = scheduledLocalDateTime;
    if (scheduled == null) return false;
    return !now.isBefore(scheduled) &&
        !now.isAfter(scheduled.add(missedAfter));
  }

  bool shouldAutoMiss(DateTime now) {
    if (status != 'pending') return false;
    final scheduled = scheduledLocalDateTime;
    if (scheduled == null) return false;
    return now.isAfter(scheduled.add(missedAfter));
  }

  int comparePriority(TodayDose other, DateTime now) {
    final selfRank = _priorityRank(now);
    final otherRank = other._priorityRank(now);
    if (selfRank != otherRank) return selfRank.compareTo(otherRank);

    final selfScheduled =
        scheduledLocalDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final otherScheduled =
        other.scheduledLocalDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    return selfScheduled.compareTo(otherScheduled);
  }

  int _priorityRank(DateTime now) {
    final currentStatus = effectiveStatus(now);
    if (currentStatus == 'pending' && isDueNow(now)) return 0;
    if (currentStatus == 'pending' && isUpcomingSoon(now)) return 1;
    if (currentStatus == 'pending') return 2;
    if (currentStatus == 'missed') return 3;
    return 4;
  }

  factory TodayDose.fromJson(Map<String, dynamic> json) => TodayDose(
    occurrenceId: json['occurrenceId'] as String? ?? '',
    planId: json['planId'] as String? ?? '',
    title: json['title'] as String?,
    drugName: json['drugName'] as String? ?? '',
    time: json['time'] as String? ?? '',
    scheduledTime: json['scheduledTime'] as String? ?? '',
    status: json['status'] as String? ?? 'pending',
    dosage: json['dosage'] as String?,
    pillsPerDose: json['pillsPerDose'] as int?,
    notes: json['notes'] as String?,
    takenAt: json['takenAt'] as String?,
    note: json['note'] as String?,
    hasReferenceProfile: json['hasReferenceProfile'] as bool? ?? false,
    referenceProfileStatus: json['referenceProfileStatus'] as String?,
    verificationReady: json['verificationReady'] as bool? ?? false,
    expectedMedications:
        (json['expectedMedications'] as List<dynamic>? ?? const [])
            .map(
              (e) => DoseExpectedMedication.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
    missingReferenceDrugNames:
        (json['missingReferenceDrugNames'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
    medications: (json['medications'] as List<dynamic>? ?? const [])
        .map((e) => TodayDoseMedication.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'occurrenceId': occurrenceId,
    'planId': planId,
    if (title != null) 'title': title,
    'drugName': drugName,
    'time': time,
    'scheduledTime': scheduledTime,
    'status': status,
    if (dosage != null) 'dosage': dosage,
    if (pillsPerDose != null) 'pillsPerDose': pillsPerDose,
    if (notes != null) 'notes': notes,
    if (takenAt != null) 'takenAt': takenAt,
    if (note != null) 'note': note,
    'hasReferenceProfile': hasReferenceProfile,
    if (referenceProfileStatus != null) 'referenceProfileStatus': referenceProfileStatus,
    'verificationReady': verificationReady,
    'expectedMedications': expectedMedications.map((e) => e.toJson()).toList(),
    'missingReferenceDrugNames': missingReferenceDrugNames,
    'medications': medications.map((e) => e.toJson()).toList(),
  };

  TodayDose copyWith({
    String? occurrenceId,
    String? planId,
    String? title,
    String? drugName,
    String? time,
    String? scheduledTime,
    String? status,
    String? dosage,
    int? pillsPerDose,
    String? notes,
    String? takenAt,
    String? note,
    bool? hasReferenceProfile,
    String? referenceProfileStatus,
    bool? verificationReady,
    List<DoseExpectedMedication>? expectedMedications,
    List<String>? missingReferenceDrugNames,
    List<TodayDoseMedication>? medications,
  }) {
    return TodayDose(
      occurrenceId: occurrenceId ?? this.occurrenceId,
      planId: planId ?? this.planId,
      title: title ?? this.title,
      drugName: drugName ?? this.drugName,
      time: time ?? this.time,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      status: status ?? this.status,
      dosage: dosage ?? this.dosage,
      pillsPerDose: pillsPerDose ?? this.pillsPerDose,
      notes: notes ?? this.notes,
      takenAt: takenAt ?? this.takenAt,
      note: note ?? this.note,
      hasReferenceProfile: hasReferenceProfile ?? this.hasReferenceProfile,
      referenceProfileStatus: referenceProfileStatus ?? this.referenceProfileStatus,
      verificationReady: verificationReady ?? this.verificationReady,
      expectedMedications: expectedMedications ?? this.expectedMedications,
      missingReferenceDrugNames: missingReferenceDrugNames ?? this.missingReferenceDrugNames,
      medications: medications ?? this.medications,
    );
  }
}

class TodaySummary {
  const TodaySummary({
    required this.total,
    required this.taken,
    required this.pending,
    required this.skipped,
    required this.missed,
  });

  final int total;
  final int taken;
  final int pending;
  final int skipped;
  final int missed;

  factory TodaySummary.fromJson(Map<String, dynamic> json) => TodaySummary(
    total: json['total'] as int? ?? 0,
    taken: json['taken'] as int? ?? 0,
    pending: json['pending'] as int? ?? 0,
    skipped: json['skipped'] as int? ?? 0,
    missed: json['missed'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'total': total,
    'taken': taken,
    'pending': pending,
    'skipped': skipped,
    'missed': missed,
  };
}

class TodaySchedule {
  const TodaySchedule({
    required this.date,
    required this.doses,
    required this.summary,
  });

  final String date;
  final List<TodayDose> doses;
  final TodaySummary summary;

  const TodaySchedule.empty()
    : date = '',
      doses = const [],
      summary = const TodaySummary(
        total: 0,
        taken: 0,
        pending: 0,
        skipped: 0,
        missed: 0,
      );

  factory TodaySchedule.fromJson(Map<String, dynamic> json) => TodaySchedule(
    date: json['date'] as String? ?? '',
    doses: (json['doses'] as List<dynamic>? ?? const [])
        .map((e) => TodayDose.fromJson(e as Map<String, dynamic>))
        .toList(),
    summary: TodaySummary.fromJson(
      (json['summary'] as Map<String, dynamic>? ?? const {}),
    ),
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'doses': doses.map((e) => e.toJson()).toList(),
    'summary': summary.toJson(),
  };

  TodaySchedule copyWith({
    String? date,
    List<TodayDose>? doses,
    TodaySummary? summary,
  }) {
    return TodaySchedule(
      date: date ?? this.date,
      doses: doses ?? this.doses,
      summary: summary ?? this.summary,
    );
  }

  TodaySchedule recount([DateTime? now]) {
    final current = now ?? DateTime.now();
    final counts = <String, int>{
      'taken': 0,
      'pending': 0,
      'skipped': 0,
      'missed': 0,
    };

    for (final dose in doses) {
      final status = dose.effectiveStatus(current);
      counts[status] = (counts[status] ?? 0) + 1;
    }

    return copyWith(
      summary: TodaySummary(
        total: doses.length,
        taken: counts['taken'] ?? 0,
        pending: counts['pending'] ?? 0,
        skipped: counts['skipped'] ?? 0,
        missed: counts['missed'] ?? 0,
      ),
    );
  }
}
