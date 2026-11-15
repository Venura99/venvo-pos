import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_pos/core/providers/core_providers.dart';
import 'package:venvo_pos/core/router/nav_destinations.dart';
import 'package:venvo_pos/core/widgets/app_sidebar.dart';
import 'package:venvo_pos/main.dart';

import 'helpers/in_process_server.dart';

/// Tears the app down and lets Drift finish closing its query streams.
///
/// Riverpod disposes the stream providers when the scope unmounts, and Drift
/// schedules a zero-duration timer as it closes each one. Those timers have to
/// be given frames to run inside the test body, or the test fails on them
/// being still pending. Tests that open many screens need this; it is harmless
/// for the ones that do not.
Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps a fixed number of frames instead of settling.
///
///  waits for all animation to stop, which never happens on a
/// screen showing an indeterminate progress indicator. A bounded pump still
/// lets the database streams and futures deliver.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 15; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// Boots the real application widget tree against the real server.
///
/// The server runs in-process over an in-memory database, and the client talks
/// to it through the same HTTP layer it uses in production — so these drive
/// the actual screens, providers and API client end to end, with every read
/// and write going through the server.
void main() {
  late InProcessServer server;

  setUp(() async {
    server = await InProcessServer.start();
  });

  tearDown(() async {
    await server.stop();
  });

  /// Pumps the app at a desktop window size, since the shell is laid out for
  /// one.
  Future<void> pumpApp(WidgetTester tester) async {
    // A real desktop window. Width matters because the sidebar collapses to
    // icons below 1280, and height matters because its ListView is lazy: an
    // off-screen item is never built, and an unbuilt widget cannot be tapped.
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [clientBootstrapProvider.overrideWithValue(server.client)],
        child: const VenvoApp(),
      ),
    );
    await settle(tester);
  }

  /// Completes the first-run screen, which is the only way into the app.
  Future<void> createAdministrator(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Nimal Perera',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'nimal',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Warehouse42',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'Warehouse42',
    );

    await tester.tap(find.text('Create account and continue'));
    await settle(tester);
  }

  /// Clicks a sidebar item and waits for its screen.
  Future<void> openFromSidebar(WidgetTester tester, String label) async {
    // Scoped to the sidebar: several of these words also appear as column
    // headings on the pages themselves.
    await tester.tap(
      find.descendant(of: find.byType(AppSidebar), matching: find.text(label)),
    );
    await settle(tester);
  }

  group('first run', () {
    testWidgets('a fresh database opens on the first-run screen', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.text('Create the administrator account'), findsOneWidget);
      // No default credentials exist anywhere, and the screen says so.
      expect(
        find.textContaining('There is no default password'),
        findsOneWidget,
      );
      // The shell is not reachable yet.
      expect(find.text('Dashboard'), findsNothing);
    });

    testWidgets('creating the administrator lands on the dashboard', (
      tester,
    ) async {
      await pumpApp(tester);
      await createAdministrator(tester);

      expect(find.text('Set up your business'), findsOneWidget);
      // The sidebar is there, with the sections a new user needs.
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Products'), findsWidgets);
      expect(find.text('Agents'), findsWidgets);
    });

    testWidgets('the dashboard reads true zeros on an empty database', (
      tester,
    ) async {
      await pumpApp(tester);
      await createAdministrator(tester);

      // Figures are read live; on an empty database they are genuinely zero
      // rather than placeholders.
      expect(find.text('Sales today'), findsOneWidget);
      expect(find.text('Rs. 0.00'), findsWidgets);
      expect(find.text('Total receivable'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('every implemented screen renders', (tester) async {
      await pumpApp(tester);
      await createAdministrator(tester);

      // One pass through the whole application, which is what would catch a
      // screen that throws the moment it is opened.
      const screens = <String, String>{
        'Categories': 'Categories',
        'Products': 'Products',
        'Agents': 'Agents',
        'Shops': 'Shops',
        'Employees': 'Employees',
        'Warehouses': 'Warehouses & Locations',
        'Stock Transfers': 'Stock Transfers',
        'Shop Supply': 'Shop Supply',
        'Stock Overview': 'Stock Overview',
        'Opening Stock': 'Opening Stock',
        'Adjustments': 'Stock Adjustments',
        'Reconciliation': 'Stock Reconciliation',
        'Stock Movements': 'Stock Movements',
        'Invoices': 'Invoices',
        'Retail Sales': 'Retail Sales',
        'Payments': 'Payments',
        'Cheques': 'Cheques',
        'Returns': 'Returns',
        'Credit Notes': 'Credit Notes',
        'Expenses': 'Expenses',
        'Petty Cash': 'Petty Cash',
        'Salaries': 'Salaries',
        'Financial Ledger': 'Financial Ledger',
        'Reports': 'Reports',
        'Backups': 'Backups',
        'Users & Roles': 'Users & Roles',
        'Audit Log': 'Audit Log',
        'Settings': 'Settings',
      };

      for (final entry in screens.entries) {
        await openFromSidebar(tester, entry.key);
        expect(
          find.text(entry.value),
          findsWidgets,
          reason: 'opening "${entry.key}" should show "${entry.value}"',
        );
        // A screen that threw would leave an error widget behind.
        expect(
          tester.takeException(),
          isNull,
          reason: '"${entry.key}" threw while rendering',
        );
      }

      await closeApp(tester);
    });

    test('no module is left pointing at the "not built yet" page', () {
      // Through seven phases this test opened whichever module was next and
      // asserted that it said so honestly rather than presenting dead
      // controls. There is nothing left to point it at: every destination in
      // the sidebar is implemented, which is what finishing phase 8 means.
      expect(
        kAllDestinations
            .where(
              (destination) =>
                  destination.availableFromPhase > kImplementedThroughPhase,
            )
            .map((destination) => destination.label),
        isEmpty,
      );
      expect(kImplementedThroughPhase, 8);
    });
  });

  group('settings', () {
    testWidgets('business details can be saved and are read back', (
      tester,
    ) async {
      await pumpApp(tester);
      await createAdministrator(tester);
      await openFromSidebar(tester, 'Settings');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Venvo Global (Pvt) Ltd',
      );
      await settle(tester);

      await tester.tap(find.text('Save changes'));
      await settle(tester);

      expect(
        server.client.settings.getStringSync('business.name'),
        'Venvo Global (Pvt) Ltd',
      );
    });

    testWidgets('the negative-stock policy defaults to off', (tester) async {
      await pumpApp(tester);
      await createAdministrator(tester);
      await openFromSidebar(tester, 'Settings');

      expect(find.text('Allow stock to go negative'), findsOneWidget);
      expect(
        server.client.settings.getBoolSync('inventory.allow_negative_stock'),
        isFalse,
      );
    });
  });

  group('master data through the interface', () {
    testWidgets('a category can be added and appears in the list', (
      tester,
    ) async {
      await pumpApp(tester);
      await createAdministrator(tester);
      await openFromSidebar(tester, 'Categories');

      await tester.tap(find.text('Add category').first);
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name *'),
        'Chargers',
      );
      await tester.tap(find.text('Add category').last);
      await settle(tester);

      expect(find.text('Chargers'), findsWidgets);
      expect(find.text('1 category'), findsOneWidget);

      await closeApp(tester);
    });

    testWidgets('an agent gets a stock location, visible on the locations '
        'screen', (tester) async {
      await pumpApp(tester);
      await createAdministrator(tester);
      await openFromSidebar(tester, 'Agents');

      await tester.tap(find.text('Add agent').first);
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Agent name *'),
        'Sunil Distributors',
      );
      await tester.tap(find.text('Add agent').last);
      await settle(tester);

      expect(find.text('Sunil Distributors'), findsWidgets);

      // The location created alongside the agent shows up where stock lives.
      await openFromSidebar(tester, 'Warehouses');
      expect(find.textContaining('Sunil Distributors'), findsWidgets);

      await closeApp(tester);
    });
  });

  group('sign out and back in', () {
    testWidgets('signing out returns to the sign-in screen', (tester) async {
      await pumpApp(tester);
      await createAdministrator(tester);

      await tester.tap(find.byTooltip('Account'));
      await settle(tester);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      await tester.tap(find.text('Sign out').last);
      await settle(tester);

      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('Dashboard'), findsNothing);
    });

    testWidgets('a wrong password is refused with one message', (tester) async {
      await pumpApp(tester);
      await createAdministrator(tester);

      await tester.tap(find.byTooltip('Account'));
      await settle(tester);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      await tester.tap(find.text('Sign out').last);
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'nimal',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'WrongPass1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);

      expect(find.text('Incorrect username or password.'), findsOneWidget);
    });
  });
}
