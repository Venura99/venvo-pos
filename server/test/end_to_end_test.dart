import 'package:test/test.dart';
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/api/revision_bus.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/authentication/api/auth_api.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';
import 'package:venvo_core/features/categories/api/category_api.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/products/api/product_api.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';

import 'support/api_harness.dart';

/// The real client against the real server, in one process.
///
/// Everything else tests one half: the server tests speak raw HTTP, and the
/// client has no server of its own. This is the only place that proves the two
/// agree — that the paths match, that the JSON the server emits is the JSON
/// the client's models expect, and that a rule broken on the server arrives at
/// the client as the same kind of failure it would have been locally.
void main() {
  late ApiHarness harness;
  late ApiClient client;
  late AuthApi auth;
  late CategoryApi categories;
  late ProductApi products;
  late AuthenticatedUser admin;

  setUp(() async {
    harness = await ApiHarness.start();
    client = ApiClient(baseUrl: harness.base, tokens: InMemoryTokenStore());
    auth = AuthApi(client);
    categories = CategoryApi(client);
    products = ProductApi(client);
  });

  tearDown(() async {
    await client.close();
    await harness.stop();
  });

  /// Waits for [condition], failing the test rather than hanging if it never
  /// becomes true.
  Future<void> until(
    bool Function() condition, {
    String reason = 'condition was never met',
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail(reason);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> signUp() async {
    admin = await auth.createFirstAdministrator(
      fullName: 'Venura Admin',
      username: 'admin',
      password: 'Str0ngPass2026',
      deviceLabel: 'Counter 1',
      deviceKind: 'windows',
    );
  }

  group('session', () {
    test('status, first run and identity all agree', () async {
      final before = await auth.status();
      expect(before.needsFirstRunSetup, isTrue);
      expect(before.schemaVersion, 4);
      expect(before.apiVersion, 1);

      expect(client.hasToken, isFalse);
      await signUp();
      // The client now holds a session without anything else being told.
      expect(client.hasToken, isTrue);
      expect(admin.username, 'admin');
      expect(admin.isAdministrator, isTrue);
      expect(admin.permissions, Permissions.all.toSet());

      // And the same user comes back from the server.
      final refreshed = await auth.refresh(admin.id);
      expect(refreshed.username, 'admin');
      expect(refreshed.permissions, admin.permissions);

      expect((await auth.status()).needsFirstRunSetup, isFalse);
    });

    test('signing out clears the token and the session', () async {
      await signUp();
      await auth.signOut(admin);
      expect(client.hasToken, isFalse);

      // And the token really is gone server-side, not just locally.
      await expectLater(auth.refresh(admin.id), throwsA(isA<AuthFailure>()));
    });
  });

  group('a write refreshes the lists watching it', () {
    test('creating a product re-emits on the product stream', () async {
      // This is the behaviour the offline build got free from Drift: a form
      // saved and the table behind it refreshed, because the query stream was
      // watching the tables. Over HTTP nothing watches anything, so the write
      // announces what it touched and this stream re-fetches. If this test
      // fails, every list in the application silently goes stale after a save.
      await signUp();
      final categoryId = await categories.create(
        admin,
        const CategoryDraft(name: 'Chargers'),
      );

      final emissions = <List<ProductListItem>>[];
      final subscription = products
          .watchProducts(const ProductFilter())
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await until(
        () => emissions.length == 1,
        reason: 'the stream never produced its first value',
      );
      expect(emissions.first, isEmpty);

      await products.create(
        admin,
        ProductDraft(
          sku: 'CHG-25W',
          name: 'Fast charger 25W',
          categoryId: categoryId,
          costPrice: const Money(123457),
          wholesalePrice: const Money(149999),
          retailPrice: const Money(199900),
        ),
      );

      await until(
        () => emissions.length >= 2,
        reason: 'the stream did not re-fetch after the product was created',
      );
      expect(emissions.last.single.sku, 'CHG-25W');
    });

    test('money arrives back exactly as it was sent', () async {
      await signUp();
      final categoryId = await categories.create(
        admin,
        const CategoryDraft(name: 'Cables'),
      );
      await products.create(
        admin,
        ProductDraft(
          sku: 'ODD-1',
          name: 'Awkward price',
          categoryId: categoryId,
          // A third of a rupee and seven cents: the kind of value a decimal
          // wire format would quietly ruin.
          costPrice: const Money(33407),
          retailPrice: const Money(99999),
        ),
      );

      final listed = await products.watchProducts(const ProductFilter()).first;
      final product = listed.single;
      expect(product.costPrice, const Money(33407));
      expect(product.retailPrice, const Money(99999));
      expect(product.costPrice.cents, 33407);
    });

    test('a manual refresh re-fetches without a write', () async {
      await signUp();
      final emissions = <List<ProductListItem>>[];
      final subscription = products
          .watchProducts(const ProductFilter())
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await until(() => emissions.length == 1);

      client.refresh({ApiTopic.products});
      await until(
        () => emissions.length >= 2,
        reason: 'refresh() did not make the stream ask again',
      );
    });
  });

  group('failures keep their type across the wire', () {
    test(
      'a business rule arrives as BusinessRuleFailure with its rule',
      () async {
        await signUp();
        await expectLater(
          auth.createFirstAdministrator(
            fullName: 'Second Admin',
            username: 'second',
            password: 'Str0ngPass2026',
          ),
          throwsA(
            isA<BusinessRuleFailure>().having(
              (f) => f.rule,
              'rule',
              'auth.first_run_once',
            ),
          ),
        );
      },
    );

    test(
      'a validation problem arrives as ValidationFailure with its field',
      () async {
        await signUp();
        await expectLater(
          categories.create(admin, const CategoryDraft(name: '')),
          throwsA(
            isA<ValidationFailure>().having((f) => f.field, 'field', isNotNull),
          ),
        );
      },
    );

    test('a missing permission arrives as PermissionFailure', () async {
      await signUp();
      // A cashier signed in on a second client.
      await auth.createUser(
        actor: admin,
        fullName: 'Cashier',
        username: 'cashier',
        password: 'Initial1Pass',
        roleCodes: [RoleCodes.cashier],
      );

      final cashierClient = ApiClient(
        baseUrl: harness.base,
        tokens: InMemoryTokenStore(),
      );
      addTearDown(cashierClient.close);
      final cashierAuth = AuthApi(cashierClient);
      final cashier = await cashierAuth.signIn(
        username: 'cashier',
        password: 'Initial1Pass',
      );
      await cashierAuth.changeOwnPassword(
        user: cashier,
        currentPassword: 'Initial1Pass',
        newPassword: 'Chosen2Pass9',
      );

      await expectLater(
        CategoryApi(
          cashierClient,
        ).create(cashier, const CategoryDraft(name: 'Not allowed')),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            Permissions.productsManage,
          ),
        ),
      );
    });

    test('an unreachable server is a StorageFailure, not a crash', () async {
      // The cost of the online-only decision, as the user will meet it: the
      // message has to say the server cannot be reached, because that is a
      // thing someone can act on. It must not look like a business rule.
      final offline = ApiClient(
        baseUrl: Uri.parse('http://127.0.0.1:1/'),
        tokens: InMemoryTokenStore(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(offline.close);

      // Which of the two messages appears depends on the platform, not on the
      // code: Linux refuses a connection to a closed port immediately, while
      // Windows lets the attempt hang until the timeout. Both are a
      // StorageFailure, which is what matters — the screens must offer a
      // retry, and must not blame the user for a business rule.
      await expectLater(
        AuthApi(offline).status(),
        throwsA(
          isA<StorageFailure>().having(
            (f) => f.message,
            'message',
            anyOf(
              contains('Cannot reach the server'),
              contains('did not answer in time'),
            ),
          ),
        ),
      );
    });

    test('a failed fetch does not kill the stream', () async {
      // A dropped connection must leave the screen recoverable. If the error
      // closed the subscription the user would be stuck on a failure until
      // the provider was rebuilt.
      await signUp();
      final events = <Object>[];
      final subscription = products
          .watchProducts(const ProductFilter())
          .listen(events.add, onError: events.add);
      addTearDown(subscription.cancel);
      await until(() => events.isNotEmpty);

      // Make the next fetch fail by throwing the token away.
      await client.clearToken();
      client.refresh({ApiTopic.products});
      await until(
        () => events.any((e) => e is AuthFailure),
        reason: 'the failure was not delivered to the stream',
      );

      // Still alive: restore the session and it recovers on its own.
      final signedIn = await auth.signIn(
        username: 'admin',
        password: 'Str0ngPass2026',
      );
      expect(signedIn.username, 'admin');
      final before = events.length;
      client.refresh({ApiTopic.products});
      await until(
        () => events.length > before,
        reason: 'the stream did not recover after the error',
      );
      expect(events.last, isA<List<ProductListItem>>());
    });
  });
}
