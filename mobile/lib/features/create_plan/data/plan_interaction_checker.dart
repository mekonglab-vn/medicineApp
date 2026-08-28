import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lookup/data/drug_interaction_repository.dart';
import '../domain/plan.dart';
import '../domain/scan_result.dart';

const _severityPriority = <String, int>{
  'contraindicated': 0,
  'major': 1,
  'moderate': 2,
  'minor': 3,
  'caution': 4,
  'unknown': 5,
};

class PlanInteractionDrugCandidate {
  const PlanInteractionDrugCandidate({
    required this.displayName,
    this.aliases = const [],
  });

  final String displayName;
  final List<String> aliases;
}

class PlanInteractionSummary {
  const PlanInteractionSummary({
    required this.requestedDrugNames,
    required this.result,
    required this.drugSeverityByKey,
  });

  final List<String> requestedDrugNames;
  final InteractionCheckResult? result;
  final Map<String, String> drugSeverityByKey;

  bool get hasInteractions => result?.hasInteractions ?? false;

  String get highestSeverity => result?.highestSeverity ?? 'unknown';

  int get totalInteractions => result?.totalInteractions ?? 0;

  String? severityForDrugName(String drugName) {
    return drugSeverityByKey[_normalizeKey(drugName)];
  }

  factory PlanInteractionSummary.empty({
    List<String> requestedDrugNames = const [],
  }) {
    return PlanInteractionSummary(
      requestedDrugNames: requestedDrugNames,
      result: null,
      drugSeverityByKey: const {},
    );
  }
}

class PlanInteractionChecker {
  PlanInteractionChecker(this._repository);

  final DrugInteractionRepository _repository;

  Future<PlanInteractionSummary> checkDetectedDrugs(
    List<DetectedDrug> drugs,
  ) async {
    final candidates = drugs
        .map(
          (drug) => PlanInteractionDrugCandidate(
            displayName: drug.name,
            aliases: [drug.name, drug.mappedDrugName ?? '', drug.ocrText],
          ),
        )
        .toList();

    return checkCandidates(candidates);
  }

  Future<PlanInteractionSummary> checkPlanDrugs(
    List<PlanDrugItem> drugs,
  ) async {
    final candidates = drugs
        .map(
          (drug) => PlanInteractionDrugCandidate(
            displayName: drug.name,
            aliases: [drug.name],
          ),
        )
        .toList();

    return checkCandidates(candidates);
  }

  Future<PlanInteractionSummary> checkCandidates(
    List<PlanInteractionDrugCandidate> candidates,
  ) async {
    final displayNameByKey = <String, String>{};
    final aliasesByKey = <String, Set<String>>{};

    for (final candidate in candidates) {
      final display = candidate.displayName.trim();
      final displayKey = _normalizeKey(display);
      if (displayKey.isEmpty) {
        continue;
      }

      displayNameByKey.putIfAbsent(displayKey, () => display);
      final aliases = aliasesByKey.putIfAbsent(displayKey, () => <String>{});
      aliases.add(displayKey);

      for (final alias in candidate.aliases) {
        final aliasKey = _normalizeKey(alias);
        if (aliasKey.isNotEmpty) {
          aliases.add(aliasKey);
        }
      }
    }

    final requestedDrugNames = displayNameByKey.values.toList();
    if (requestedDrugNames.length < 2) {
      return PlanInteractionSummary.empty(
        requestedDrugNames: requestedDrugNames,
      );
    }

    final result = await _repository.checkByDrugs(requestedDrugNames);
    final indexedCandidates = aliasesByKey.entries
        .map(
          (entry) =>
              _IndexedCandidate(displayKey: entry.key, aliasKeys: entry.value),
        )
        .toList();

    final severityByDrugKey = <String, String>{};
    for (final item in result.interactions) {
      final left = _resolveDisplayKeys(
        rawValues: [item.drugA, item.ingredientA],
        candidates: indexedCandidates,
      );
      final right = _resolveDisplayKeys(
        rawValues: [item.drugB, item.ingredientB],
        candidates: indexedCandidates,
      );

      final severity = _normalizeSeverity(item.severity);
      for (final displayKey in <String>{...left, ...right}) {
        final current = severityByDrugKey[displayKey];
        if (current == null || _isHigherSeverity(severity, current)) {
          severityByDrugKey[displayKey] = severity;
        }
      }
    }

    return PlanInteractionSummary(
      requestedDrugNames: requestedDrugNames,
      result: result,
      drugSeverityByKey: severityByDrugKey,
    );
  }
}

class _IndexedCandidate {
  const _IndexedCandidate({required this.displayKey, required this.aliasKeys});

  final String displayKey;
  final Set<String> aliasKeys;
}

Set<String> _resolveDisplayKeys({
  required List<String> rawValues,
  required List<_IndexedCandidate> candidates,
}) {
  final normalizedValues = rawValues
      .map(_normalizeKey)
      .where((value) => value.isNotEmpty)
      .toSet();

  if (normalizedValues.isEmpty) {
    return const <String>{};
  }

  final matched = <String>{};
  for (final candidate in candidates) {
    if (_matchesAnyAlias(candidate.aliasKeys, normalizedValues)) {
      matched.add(candidate.displayKey);
    }
  }
  return matched;
}

bool _matchesAnyAlias(Set<String> aliases, Set<String> targets) {
  for (final alias in aliases) {
    for (final target in targets) {
      if (alias == target) {
        return true;
      }
      if (alias.length >= 5 && target.contains(alias)) {
        return true;
      }
      if (target.length >= 5 && alias.contains(target)) {
        return true;
      }
    }
  }
  return false;
}

String _normalizeKey(String value) {
  return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _normalizeSeverity(String value) {
  final normalized = value.trim().toLowerCase();
  if (_severityPriority.containsKey(normalized)) {
    return normalized;
  }
  return 'unknown';
}

bool _isHigherSeverity(String next, String current) {
  final nextRank = _severityPriority[next] ?? _severityPriority['unknown']!;
  final currentRank =
      _severityPriority[current] ?? _severityPriority['unknown']!;
  return nextRank < currentRank;
}

final planInteractionCheckerProvider = Provider<PlanInteractionChecker>((ref) {
  return PlanInteractionChecker(ref.watch(drugInteractionRepositoryProvider));
});
