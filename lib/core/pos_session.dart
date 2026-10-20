/// Identity carried between screens. This is presentation state, not an
/// authorization boundary; server policies are introduced in the data phase.
class PosSession {
  const PosSession({
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.preview = false,
  });
  final String fullName, role, userId, location;
  final bool preview;
  PosSession atBranch(String value) => PosSession(
    fullName: fullName,
    role: role,
    userId: userId,
    location: value,
    preview: preview,
  );
}
