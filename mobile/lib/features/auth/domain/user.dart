/// User model — matches Node.js API response.
class User {
  final String id;
  final String email;
  final String? name;

  const User({required this.id, required this.email, this.name});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['name'] as String?,
  );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};
}
