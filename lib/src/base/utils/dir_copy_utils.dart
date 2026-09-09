import 'dart:io';

import 'package:path/path.dart' as p;

/// Recursively copies every file and subdirectory under [src] into [dest]
/// (created, along with any missing subdirectories, if needed) — `dart:io`
/// has no built-in recursive directory copy, so this is a small hand-rolled
/// one used for archiving report output (see docs/RUN_EXPERIENCE_REDESIGN.md
/// §8). A **copy**, never a move — the source (the repo's own report
/// folder) is left untouched.
///
/// ponytail: follows symlinks (via [Directory.listSync]'s default) rather
/// than special-casing them — a build tool's report output isn't expected to
/// contain any; revisit if that assumption breaks.
void copyDirectoryContents(Directory src, Directory dest) {
  if (!dest.existsSync()) dest.createSync(recursive: true);
  for (final entity in src.listSync()) {
    final name = p.basename(entity.path);
    if (entity is Directory) {
      copyDirectoryContents(entity, Directory(p.join(dest.path, name)));
    } else if (entity is File) {
      entity.copySync(p.join(dest.path, name));
    }
  }
}

/// Total size in bytes of every file under [dir], recursively. Returns 0 for
/// a missing directory. Used by the report-retention size limit.
int directorySizeBytes(Directory dir) {
  if (!dir.existsSync()) return 0;
  var total = 0;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      try {
        total += entity.lengthSync();
      } catch (_) {
        // Deleted/unreadable between listing and stat — ignore, best-effort.
      }
    }
  }
  return total;
}

/// Best-effort recursive delete — a report folder that's already gone (or
/// unreadable) is not an error worth surfacing to the user.
void deleteDirectoryQuietly(String path) {
  try {
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {
    // Best-effort.
  }
}
