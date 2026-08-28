import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/user_profile.dart';

class ProfileState {
  final List<UserProfile> profiles;
  final String activeProfileId;

  const ProfileState({
    required this.profiles,
    required this.activeProfileId,
  });

  UserProfile get activeProfile => profiles.firstWhere(
        (p) => p.id == activeProfileId,
        orElse: () => profiles.first,
      );

  ProfileState copyWith({
    List<UserProfile>? profiles,
    String? activeProfileId,
  }) => ProfileState(
    profiles: profiles ?? this.profiles,
    activeProfileId: activeProfileId ?? this.activeProfileId,
  );
}

class ProfileNotifier extends Notifier<ProfileState> {
  static const _defaultProfiles = [
    UserProfile(id: 'self', name: 'Bản thân', relation: 'Bản thân', isDefault: true),
    UserProfile(id: 'father', name: 'Bố', relation: 'Bố'),
    UserProfile(id: 'mother', name: 'Mẹ', relation: 'Mẹ'),
    UserProfile(id: 'child', name: 'Bé An', relation: 'Con'),
  ];

  @override
  ProfileState build() {
    return const ProfileState(
      profiles: _defaultProfiles,
      activeProfileId: 'self',
    );
  }

  void selectProfile(String profileId) {
    state = state.copyWith(activeProfileId: profileId);
  }

  void addProfile(String name, String relation) {
    final newProfile = UserProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      relation: relation,
    );
    state = state.copyWith(
      profiles: [...state.profiles, newProfile],
    );
  }
}

final profileNotifierProvider = NotifierProvider<ProfileNotifier, ProfileState>(
  ProfileNotifier.new,
);
