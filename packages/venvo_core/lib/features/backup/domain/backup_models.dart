import 'dart:io';

/// What a backup archive is, and what it says about itself.
///
/// Every archive carries a manifest, and the manifest is what makes restoring
/// safe rather than hopeful: it records the schema version the database was
/// written at, so an archive from a newer release is refused instead of being
/// opened with the wrong column expectations.
class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.databaseBytes,
    required this.attachmentCount,
    required this.attachmentBytes,
    required this.automatic,
    this.note,
    this.createdByUsername,
  });

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    return BackupManifest(
      appVersion: json['appVersion'] as String? ?? 'unknown',
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.utc(1970),
      databaseBytes: (json['databaseBytes'] as num?)?.toInt() ?? 0,
      attachmentCount: (json['attachmentCount'] as num?)?.toInt() ?? 0,
      attachmentBytes: (json['attachmentBytes'] as num?)?.toInt() ?? 0,
      automatic: json['automatic'] as bool? ?? false,
      note: json['note'] as String?,
      createdByUsername: json['createdByUsername'] as String?,
    );
  }

  static const String fileName = 'manifest.json';

  final String appVersion;

  /// The database schema version the archive was written at.
  final int schemaVersion;

  final DateTime createdAt;
  final int databaseBytes;
  final int attachmentCount;
  final int attachmentBytes;

  /// True when the daily automatic backup produced it rather than a person.
  final bool automatic;

  final String? note;
  final String? createdByUsername;

  Map<String, Object?> toJson() => {
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'databaseBytes': databaseBytes,
    'attachmentCount': attachmentCount,
    'attachmentBytes': attachmentBytes,
    'automatic': automatic,
    if (note != null) 'note': note,
    if (createdByUsername != null) 'createdByUsername': createdByUsername,
  };
}

/// An archive on disk.
class BackupArchive {
  const BackupArchive({
    required this.file,
    required this.sizeBytes,
    required this.manifest,
  });

  final File file;
  final int sizeBytes;
  final BackupManifest manifest;

  String get fileName => file.uri.pathSegments.last;

  bool get isAutomatic => manifest.automatic;
}

/// Why an archive cannot be trusted, or that it can.
///
/// Validation opens the archived database **read-only** and runs SQLite's own
/// integrity check over it, rather than assuming a file that unzipped is a
/// file worth restoring. A backup nobody has checked is a guess.
class BackupValidation {
  const BackupValidation({
    required this.isUsable,
    required this.problems,
    this.manifest,
    this.userCount,
    this.invoiceCount,
    this.stockEntryCount,
  });

  const BackupValidation.broken(this.problems)
    : isUsable = false,
      manifest = null,
      userCount = null,
      invoiceCount = null,
      stockEntryCount = null;

  final bool isUsable;

  /// Empty when the archive is sound. Each entry is a sentence worth showing.
  final List<String> problems;

  final BackupManifest? manifest;

  /// Read out of the archived database itself, so the figures shown before a
  /// restore are what is actually in the file rather than what the manifest
  /// claims.
  final int? userCount;
  final int? invoiceCount;
  final int? stockEntryCount;

  bool get hasProblems => problems.isNotEmpty;
}

/// The outcome of asking for a restore.
///
/// A restore does not happen in place. The archive's contents are staged
/// beside the live data and applied on the next start, because the database
/// this process has open cannot be swapped underneath it: every repository,
/// provider and open query stream is holding the old connection. Staging is
/// also what makes the current data recoverable - the live database is
/// archived first, so a restore is never a one-way door.
class RestoreOutcome {
  const RestoreOutcome({
    required this.stagedFrom,
    required this.safetyArchive,
    required this.manifest,
  });

  final File stagedFrom;

  /// The archive taken of the live data before staging, so the restore can
  /// itself be undone.
  final File safetyArchive;

  final BackupManifest manifest;
}

/// What a pending restore did on the next start.
class RestoreApplied {
  const RestoreApplied({
    required this.restoredFrom,
    required this.appliedAt,
    required this.attachmentsReplaced,
  });

  final String restoredFrom;
  final DateTime appliedAt;
  final bool attachmentsReplaced;
}

/// Human-readable file size.
///
/// Lives here rather than beside `BackupService` so that a client — which can
/// import these models but not the service, since the service opens the
/// database — formats sizes exactly as the server's audit entries do.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
