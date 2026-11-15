import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/api/settings_api.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/features/authentication/api/auth_api.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

import 'support/api_harness.dart';

/// The smallest valid PNG signature plus some body; the server checks the
/// signature, not the pixels.
final Uint8List png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ...List.filled(32, 0x00),
]);

final Uint8List jpeg = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(32, 0x20), 0xFF, 0xD9, //
]);

void main() {
  late ApiHarness api;
  late ApiClient adminClient;
  late AuthenticatedUser admin;
  late SettingsApi adminSettings;

  setUp(() async {
    api = await ApiHarness.start();
    adminClient = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    admin = await AuthApi(adminClient).createFirstAdministrator(
      fullName: 'Admin',
      username: 'admin',
      password: ApiHarness.adminPassword,
    );
    adminSettings = SettingsApi(adminClient);
  });

  tearDown(() async {
    await adminClient.close();
    await api.stop();
  });

  test('there is no logo on a new installation', () async {
    await adminSettings.load();
    expect(adminSettings.logoVersion, isNull);
    expect(await adminSettings.logo(), isNull);
    final anonymous = ApiClient(
      baseUrl: api.base,
      tokens: InMemoryTokenStore(),
    );
    expect((await anonymous.getBytes('/api/v1/branding/logo')).bytes, isEmpty);
    await anonymous.close();
  });

  test(
    'an uploaded logo is served publicly and printed on documents',
    () async {
      await adminSettings.uploadLogo(png, contentType: 'image/png');
      expect(adminSettings.logoVersion, isNotNull);

      // Without signing in, as the sign-in screen fetches it.
      final anonymous = ApiClient(
        baseUrl: api.base,
        tokens: InMemoryTokenStore(),
      );
      final file = await anonymous.getBytes('/api/v1/branding/logo');
      expect(file.bytes, png);
      expect(file.contentType, 'image/png');
      await anonymous.close();

      final identity = await adminSettings.businessIdentity();
      expect(identity.logo, png);
    },
  );

  test('replacing the logo changes its version and its contents', () async {
    await adminSettings.uploadLogo(png, contentType: 'image/png');
    final first = adminSettings.logoVersion;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await adminSettings.uploadLogo(jpeg, contentType: 'image/jpeg');
    expect(adminSettings.logoVersion, isNot(first));
    expect(await adminSettings.logo(), jpeg);
  });

  test('only PNG and JPEG are accepted, judged by the contents', () async {
    final pdf = Uint8List.fromList('%PDF-1.4 not a logo'.codeUnits);
    await expectLater(
      adminSettings.uploadLogo(pdf, contentType: 'image/png'),
      throwsA(isA<ValidationFailure>()),
    );
    final text = Uint8List.fromList('hello'.codeUnits);
    await expectLater(
      adminSettings.uploadLogo(text, contentType: 'image/png'),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('a logo over 2 MB is refused', () async {
    final big = Uint8List(2 * 1024 * 1024 + 1)..setAll(0, png);
    await expectLater(
      adminSettings.uploadLogo(big, contentType: 'image/png'),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('removing the logo', () async {
    await adminSettings.uploadLogo(png, contentType: 'image/png');
    await adminSettings.removeLogo();
    expect(adminSettings.logoVersion, isNull);
    expect(await adminSettings.logo(), isNull);
    expect((await adminSettings.businessIdentity()).logo, isNull);
  });

  test('someone without settings permission cannot change the logo', () async {
    await AuthApi(adminClient).createUser(
      actor: admin,
      fullName: 'Kamal (agent)',
      username: 'kamal',
      password: 'Initial1Pass',
      roleCodes: [RoleCodes.agent],
    );
    final agentClient = ApiClient(
      baseUrl: api.base,
      tokens: InMemoryTokenStore(),
    );
    final agentAuth = AuthApi(agentClient);
    final agent = await agentAuth.signIn(
      username: 'kamal',
      password: 'Initial1Pass',
    );
    await agentAuth.changeOwnPassword(
      user: agent,
      currentPassword: 'Initial1Pass',
      newPassword: 'Chosen2Pass9',
    );
    final agentSettings = SettingsApi(agentClient);
    await expectLater(
      agentSettings.uploadLogo(png, contentType: 'image/png'),
      throwsA(isA<PermissionFailure>()),
    );
    await expectLater(
      agentSettings.removeLogo(),
      throwsA(isA<PermissionFailure>()),
    );
    await agentClient.close();
  });
}
