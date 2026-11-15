import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/services/password_hasher.dart';

void main() {
  // A low cost keeps the suite fast; the production cost is exercised by the
  // iteration-count assertions rather than by hashing repeatedly.
  const hasher = PasswordHasher(iterations: 1000);

  group('PasswordHasher', () {
    test('verifies the correct password', () {
      final hash = hasher.hash('Warehouse42');
      expect(
        hasher.verify(
          password: 'Warehouse42',
          hashBase64: hash.hashBase64,
          saltBase64: hash.saltBase64,
          iterations: hash.iterations,
        ),
        isTrue,
      );
    });

    test('rejects a wrong password, including near misses', () {
      final hash = hasher.hash('Warehouse42');
      for (final wrong in ['warehouse42', 'Warehouse4', 'Warehouse42 ', '']) {
        expect(
          hasher.verify(
            password: wrong,
            hashBase64: hash.hashBase64,
            saltBase64: hash.saltBase64,
            iterations: hash.iterations,
          ),
          isFalse,
          reason: 'should reject "$wrong"',
        );
      }
    });

    test('salts every hash, so the same password hashes differently', () {
      final first = hasher.hash('Warehouse42');
      final second = hasher.hash('Warehouse42');
      expect(first.saltBase64, isNot(second.saltBase64));
      expect(first.hashBase64, isNot(second.hashBase64));
    });

    test('never stores the password itself', () {
      final hash = hasher.hash('Warehouse42');
      expect(hash.hashBase64.contains('Warehouse42'), isFalse);
      expect(
        utf8.decode(base64Decode(hash.hashBase64), allowMalformed: true),
        isNot(contains('Warehouse42')),
      );
    });

    test('derives a 256-bit key', () {
      final hash = hasher.hash('Warehouse42');
      expect(base64Decode(hash.hashBase64).length, 32);
      expect(base64Decode(hash.saltBase64).length, 16);
    });

    test('records the cost it used and detects an outdated one', () {
      final weak = const PasswordHasher(iterations: 1000).hash('Warehouse42');
      expect(weak.iterations, 1000);
      const stronger = PasswordHasher(iterations: 120000);
      expect(stronger.needsRehash(weak.iterations), isTrue);
      expect(stronger.needsRehash(120000), isFalse);
      expect(stronger.needsRehash(200000), isFalse);
    });

    test('a hash is still verifiable with its own recorded cost', () {
      // This is what lets the cost be raised without locking anyone out.
      final old = const PasswordHasher(iterations: 500).hash('Warehouse42');
      const current = PasswordHasher(iterations: 120000);
      expect(
        current.verify(
          password: 'Warehouse42',
          hashBase64: old.hashBase64,
          saltBase64: old.saltBase64,
          iterations: old.iterations,
        ),
        isTrue,
      );
    });

    test('malformed stored values are rejected, not thrown', () {
      expect(
        hasher.verify(
          password: 'Warehouse42',
          hashBase64: 'not base64 !!',
          saltBase64: 'also not !!',
          iterations: 1000,
        ),
        isFalse,
      );
    });

    test('matches the published PBKDF2-HMAC-SHA256 test vector', () {
      // password "password", salt "salt", 1 iteration, 32-byte key.
      // Expected: 120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b
      const reference = PasswordHasher(iterations: 1);
      // The salt is random in hash(), so the vector is checked through verify
      // against a known-good hash built from the documented bytes.
      final expectedBytes = _hexToBytes(
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
      expect(
        reference.verify(
          password: 'password',
          hashBase64: base64Encode(expectedBytes),
          saltBase64: base64Encode(utf8.encode('salt')),
          iterations: 1,
        ),
        isTrue,
      );
    });
  });

  group('validatePasswordStrength', () {
    test('accepts a password meeting the policy', () {
      expect(validatePasswordStrength('Warehouse42'), isNull);
      expect(validatePasswordStrength('abcd1234'), isNull);
    });

    test('rejects a short password', () {
      expect(validatePasswordStrength('abc1'), contains('8 characters'));
    });

    test('rejects letters-only and digits-only passwords', () {
      expect(
        validatePasswordStrength('warehouse'),
        contains('letters and numbers'),
      );
      expect(
        validatePasswordStrength('12345678'),
        contains('letters and numbers'),
      );
    });
  });
}

List<int> _hexToBytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
