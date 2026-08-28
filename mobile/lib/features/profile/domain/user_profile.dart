class UserProfile {
  final String id;
  final String name;
  final String relation; // 'Bản thân', 'Bố', 'Mẹ', 'Con', 'Khác'
  final String? avatarUrl;
  final bool isDefault;

  const UserProfile({
    required this.id,
    required this.name,
    this.relation = 'Bản thân',
    this.avatarUrl,
    this.isDefault = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Người dùng',
    relation: json['relation'] as String? ?? 'Bản thân',
    avatarUrl: json['avatarUrl'] as String?,
    isDefault: json['isDefault'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'relation': relation,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    'isDefault': isDefault,
  };

  UserProfile copyWith({
    String? id,
    String? name,
    String? relation,
    String? avatarUrl,
    bool? isDefault,
  }) => UserProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    relation: relation ?? this.relation,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    isDefault: isDefault ?? this.isDefault,
  );
}
