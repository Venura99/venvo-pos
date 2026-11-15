import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../constants/app_constants.dart';

/// Result of deriving a password hash. All three parts are stored: the cost is
/// kept per user so it can be raised later without locking anyone out.
class PasswordHash {
  const PasswordHash({
    required this.hashBase64,
    required this.saltBase64,
    required this.iterations,
  });

  final String hashBase64;
  final String saltBase64;
  final int iterations;
}

/// PBKDF2-HMAC-SHA256 password hashing.
///
/// Chosen over a bare SHA-256 because it is deliberately slow, and over
/// bcrypt/argon2 because those would pull a native dependency into a
/// fully offline Windows build for no practical gain at this scale. The
/// iteration count lives in [AppConstants.pbkdf2Iterations] and is stored
/// alongside each hash.
///
/// No password or derived key is ever logged, and no credential is hardcoded
/// anywhere in the application: the first administrator account is created by
/// the person installing the software.
class PasswordHasher {
  const PasswordHasher({this.iterations = AppConstants.pbkdf2Iterations});

  final int iterations;

  static const int _saltLength = 16;
  static const int _keyLength = 32;

  /// Hashes [password] with a fresh random salt.
  PasswordHash hash(String password) {
    final salt = _randomSalt();
    final derived = _pbkdf2(
      password: password,
      salt: salt,
      iterations: iterations,
      keyLength: _keyLength,
    );
    return PasswordHash(
      hashBase64: base64Encode(derived),
      saltBase64: base64Encode(salt),
      iterations: iterations,
    );
  }

  /// Re-derives the key from [password] using the stored salt and cost, and
  /// compares it to the stored hash in constant time.
  bool verify({
    required String password,
    required String hashBase64,
    required String saltBase64,
    required int iterations,
  }) {
    final Uint8List expected;
    final Uint8List salt;
    try {
      expected = base64Decode(hashBase64);
      salt = base64Decode(saltBase64);
    } on FormatException {
      return false;
    }
    final actual = _pbkdf2(
      password: password,
      salt: salt,
      iterations: iterations,
      keyLength: expected.length,
    );
    return _constantTimeEquals(expected, actual);
  }

  /// True when a stored hash was derived with a weaker cost than the current
  /// setting, so the caller can transparently re-hash on next sign-in.
  bool needsRehash(int storedIterations) => storedIterations < iterations;

  Uint8List _randomSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => random.nextInt(256)),
    );
  }

  /// PBKDF2 as specified in RFC 8018, with HMAC-SHA256 as the PRF.
  static Uint8List _pbkdf2({
    required String password,
    required Uint8List salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password));
    const hashLength = 32;
    final blockCount = (keyLength + hashLength - 1) ~/ hashLength;
    final output = Uint8List(blockCount * hashLength);

    for (var block = 1; block <= blockCount; block++) {
      final blockIndex = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;

      var u = Uint8List.fromList(hmac.convert([...salt, ...blockIndex]).bytes);
      final accumulator = Uint8List.fromList(u);

      for (var round = 1; round < iterations; round++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var i = 0; i < hashLength; i++) {
          accumulator[i] ^= u[i];
        }
      }
      output.setRange(
        (block - 1) * hashLength,
        block * hashLength,
        accumulator,
      );
    }
    return Uint8List.sublistView(output, 0, keyLength);
  }

  /// Compares without an early return, so a wrong password takes the same time
  /// however much of the prefix matched.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Validates a candidate password against the application's policy. Returns
/// null when acceptable, otherwise the reason to show the user.
String? validatePasswordStrength(String password) {
  if (password.length < AppConstants.passwordMinLength) {
    return 'Password must be at least ${AppConstants.passwordMinLength} characters.';
  }
  final hasLetter = password.contains(RegExp(r'[A-Za-z]'));
  final hasDigit = password.contains(RegExp(r'\d'));
  if (!hasLetter || !hasDigit) {
    return 'Password must contain both letters and numbers.';
  }
  return null;
}
