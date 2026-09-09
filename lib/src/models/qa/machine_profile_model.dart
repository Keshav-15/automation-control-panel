/// Paths to the Centurion sibling repos on this machine.
///
/// Persisted in SharedPreferences so we never hard-code a username.
/// The user sets this once via the Setup screen; it is derived from a single
/// "Projects root" folder they select (e.g. ~/Documents/Projects).
class MachineProfile {
  /// Absolute path to the parent directory that contains all sibling repos.
  /// e.g. "/Users/alice/Documents/Projects"
  final String projectsRoot;

  /// Extra directories to prepend to PATH (e.g. /opt/homebrew/bin).
  /// Usually empty — login-shell PATH already includes these.
  final List<String> extraPathDirs;

  const MachineProfile({
    required this.projectsRoot,
    this.extraPathDirs = const [],
  });

  bool get isValid => projectsRoot.isNotEmpty;

  /// Resolve the absolute path to a repo given its [relPath] from the manifest.
  String repoPath(String relPath) => '$projectsRoot/$relPath';

  MachineProfile copyWith({
    String? projectsRoot,
    List<String>? extraPathDirs,
  }) {
    return MachineProfile(
      projectsRoot: projectsRoot ?? this.projectsRoot,
      extraPathDirs: extraPathDirs ?? this.extraPathDirs,
    );
  }
}
