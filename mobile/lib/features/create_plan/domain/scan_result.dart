class ScanResult {
  final String scanId;
  final List<DetectedDrug> drugs;
  final String qualityState;
  final String? rejectReason;
  final String? guidance;
  final bool rejected;
  // Legacy / internal session info (for backwards compatibility)
  final LegacyScanData legacyData;

  // Backward compatibility getters for legacy multi-image session flow
  @Deprecated('Use legacyData.sessionId')
  String? get sessionId => legacyData.sessionId;

  @Deprecated('Use legacyData.converged')
  bool get converged => legacyData.converged;

  @Deprecated('Use legacyData.rawText')
  String? get rawText => legacyData.rawText;

  @Deprecated('Use legacyData.unresolvedCount')
  int get unresolvedCount => legacyData.unresolvedCount;

  @Deprecated('Use legacyData.candidates')
  List<DetectedDrug> get candidates => legacyData.candidates;

  const ScanResult({
    required this.scanId,
    required this.drugs,
    this.qualityState = 'GOOD',
    this.rejectReason,
    this.guidance,
    this.rejected = false,
    this.legacyData = const LegacyScanData(),
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    final src =
        (json['mergedDrugs'] as List?) ?? (json['drugs'] as List?) ?? [];
    final drugs = src
        .map((d) => DetectedDrug.fromJson(d as Map<String, dynamic>))
        .toList();

    return ScanResult(
      scanId: json['scanId'] as String? ?? '',
      drugs: drugs,
      qualityState: json['qualityState'] as String? ?? 'GOOD',
      rejectReason: json['rejectReason'] as String?,
      guidance: json['guidance'] as String?,
      rejected: json['rejected'] as bool? ?? false,
      legacyData: LegacyScanData.fromJson(json, src),
    );
  }
}

/// Legacy fields used by the older multi-image session flow.
/// Kept here for compatibility when querying old endpoints.
class LegacyScanData {
  final String? sessionId;
  final bool converged;
  final String? rawText;
  final int unresolvedCount;
  final List<DetectedDrug> candidates;

  const LegacyScanData({
    this.sessionId,
    this.converged = false,
    this.rawText,
    this.unresolvedCount = 0,
    this.candidates = const [],
  });

  factory LegacyScanData.fromJson(
    Map<String, dynamic> json,
    List<dynamic> src,
  ) {
    final candidateSrc = (json['candidates'] as List?) ?? src;
    final candidates = candidateSrc
        .map((d) => DetectedDrug.fromJson(d as Map<String, dynamic>))
        .toList();
    return LegacyScanData(
      sessionId: json['sessionId'] as String?,
      converged: json['converged'] as bool? ?? false,
      rawText: json['rawText'] as String?,
      unresolvedCount: json['unresolvedCount'] as int? ?? 0,
      candidates: candidates,
    );
  }
}

/// A single drug detected by OCR.
class DetectedDrug {
  final String name;
  final String? dosage;
  final double confidence;
  final double matchScore;
  final String mappingStatus;
  final String ocrText;
  final String? mappedDrugName;
  final int frequency;
  final List<String> sources;

  const DetectedDrug({
    required this.name,
    this.dosage,
    this.confidence = 0.0,
    this.matchScore = 0.0,
    this.mappingStatus = 'confirmed',
    this.ocrText = '',
    this.mappedDrugName,
    this.frequency = 1,
    this.sources = const [],
  });

  factory DetectedDrug.fromJson(Map<String, dynamic> json) => DetectedDrug(
    name: json['name'] as String? ?? json['drugName'] as String? ?? '',
    dosage: json['dosage'] as String?,
    confidence:
        (json['confidence'] as num?)?.toDouble() ??
        (json['matchScore'] as num?)?.toDouble() ??
        0.0,
    matchScore: (json['matchScore'] as num?)?.toDouble() ?? 0.0,
    mappingStatus: json['mappingStatus'] as String? ?? 'confirmed',
    ocrText: json['ocrText'] as String? ?? '',
    mappedDrugName: json['mappedDrugName'] as String?,
    frequency: json['frequency'] as int? ?? 1,
    sources: (json['sources'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'dosage': dosage,
    'confidence': confidence,
    'matchScore': matchScore,
    'mappingStatus': mappingStatus,
    'ocrText': ocrText,
    'mappedDrugName': mappedDrugName,
    'frequency': frequency,
    'sources': sources,
  };

  bool get needsReview => mappingStatus != 'confirmed' || confidence < 0.85;
}
