class MedicationLogEntry {
  const MedicationLogEntry({
    required this.id,
    required this.planId,
    required this.scheduledTime,
    required this.status,
    this.takenAt,
    this.note,
    this.occurrenceId,
    this.drugName,
    this.dosage,
    this.pillsPerDose,
  });

  final String id;
  final String planId;
  final DateTime scheduledTime;
  final String status;
  final DateTime? takenAt;
  final String? note;
  final String? occurrenceId;
  final String? drugName;
  final String? dosage;
  final int? pillsPerDose;

  factory MedicationLogEntry.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
    }

    DateTime? parseNullableDate(dynamic value) {
      final parsed = DateTime.tryParse(value?.toString() ?? '');
      return parsed;
    }

    return MedicationLogEntry(
      id: json['id']?.toString() ?? '',
      planId: json['plan_id']?.toString() ?? json['planId']?.toString() ?? '',
      scheduledTime: parseDate(json['scheduled_time'] ?? json['scheduledTime']),
      status: json['status']?.toString() ?? 'pending',
      takenAt: parseNullableDate(json['taken_at'] ?? json['takenAt']),
      note: json['note']?.toString(),
      occurrenceId:
          json['occurrence_id']?.toString() ?? json['occurrenceId']?.toString(),
      drugName: json['drug_name']?.toString() ?? json['drugName']?.toString(),
      dosage: json['dosage']?.toString(),
      pillsPerDose:
          json['pills_per_dose'] as int? ?? json['pillsPerDose'] as int?,
    );
  }
}

class MedicationLogsPage {
  const MedicationLogsPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<MedicationLogEntry> items;
  final int total;
  final int page;
  final int limit;
}
