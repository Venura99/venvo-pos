import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/bootstrap/app_bootstrap.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/services/app_paths.dart';
import 'package:venvo_core/core/services/clock.dart';
import 'package:venvo_core/core/services/settings_service.dart';
import 'package:venvo_core/features/agents/data/agent_repository.dart';
import 'package:venvo_core/features/authentication/data/auth_repository.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/services/audit_service.dart';
import 'package:venvo_core/features/authentication/data/user_admin_repository.dart';
import 'package:venvo_core/features/attachments/data/attachment_service.dart';
import 'package:venvo_core/features/backup/data/backup_service.dart';
import 'package:venvo_core/features/categories/data/category_repository.dart';
import 'package:venvo_core/features/dashboard/data/dashboard_repository.dart';
import 'package:venvo_core/features/employees/data/employee_repository.dart';
import 'package:venvo_core/features/expenses/data/expense_query_repository.dart';
import 'package:venvo_core/features/expenses/data/expense_service.dart';
import 'package:venvo_core/features/finance/data/financial_ledger_service.dart';
import 'package:venvo_core/features/inventory/data/location_repository.dart';
import 'package:venvo_core/features/inventory/data/stock_count_repository.dart';
import 'package:venvo_core/features/inventory/data/stock_ledger_service.dart';
import 'package:venvo_core/features/inventory/data/stock_query_repository.dart';
import 'package:venvo_core/features/invoices/data/invoice_query_repository.dart';
import 'package:venvo_core/features/invoices/data/invoice_service.dart';
import 'package:venvo_core/features/payments/data/payment_query_repository.dart';
import 'package:venvo_core/features/payments/data/cheque_reminders.dart';
import 'package:venvo_core/features/payments/data/payment_service.dart';
import 'package:venvo_core/features/petty_cash/data/petty_cash_service.dart';
import 'package:venvo_core/features/reports/data/report_repository.dart';
import 'package:venvo_core/features/returns/data/return_query_repository.dart';
import 'package:venvo_core/features/returns/data/return_service.dart';
import 'package:venvo_core/features/salaries/data/salary_query_repository.dart';
import 'package:venvo_core/features/salaries/data/salary_service.dart';
import 'package:venvo_core/features/products/data/product_repository.dart';
import 'package:venvo_core/features/shops/data/shop_repository.dart';

import 'auth/auth_middleware.dart';
import 'auth/session_store.dart';
import 'config.dart';
import 'http/error_middleware.dart';
import 'http/web_app.dart';
import 'notifications/whatsapp_sender.dart';
import 'http/responses.dart';
import 'routes/admin_routes.dart';
import 'routes/auth_routes.dart';
import 'routes/backup_routes.dart';
import 'routes/cheque_extra_routes.dart';
import 'routes/expense_routes.dart';
import 'routes/finance_routes.dart';
import 'routes/invoice_routes.dart';
import 'routes/master_data_routes.dart';
import 'routes/payment_routes.dart';
import 'routes/petty_cash_routes.dart';
import 'routes/report_routes.dart';
import 'routes/return_routes.dart';
import 'routes/branding_routes.dart';
import 'routes/salary_routes.dart';
import 'routes/stock_routes.dart';
import 'routes/system_routes.dart';
import 'sqlite_runtime.dart';

/// The running API.
///
/// Composes the same object graph as the desktop client — through
/// [AppBootstrap], not a parallel copy of it — so a rule enforced on the
/// desktop is the same rule enforced here. The only differences are where the
/// data directory comes from and that requests arrive over HTTP.
class VenvoApiServer {
  VenvoApiServer._({
    required this.config,
    required AppBootstrap bootstrap,
    required HttpServer httpServer,
    required Timer maintenance,
    required Timer reminderTimer,
  }) : _bootstrap = bootstrap,
       _httpServer = httpServer,
       _maintenance = maintenance,
       _reminderTimer = reminderTimer;

  final ServerConfig config;
  final AppBootstrap _bootstrap;
  final HttpServer _httpServer;
  final Timer _maintenance;
  final Timer _reminderTimer;

  /// How often expired sessions are swept. The table would otherwise grow
  /// without bound on a server that is never restarted.
  static const Duration _maintenanceInterval = Duration(hours: 6);

  Uri get url => Uri(
    scheme: 'http',
    host: _httpServer.address.host,
    port: _httpServer.port,
  );

  /// True when the database holds no user, so a client must run first-run
  /// setup before anything else will work.
  bool get needsFirstRunSetup => _bootstrap.needsFirstRunSetup;

  static Future<VenvoApiServer> start(
    ServerConfig config, {
    Clock clock = const SystemClock(),
    void Function(String message)? log,
    ReminderSender? reminderSender,
  }) async {
    final write = log ?? _stdoutLog;
    configureSqliteRuntime();

    final bootstrap = await AppBootstrap.open(
      paths: await AppPaths.at(config.dataRoot),
      clock: clock,
      logStatements: config.logStatements,
    );

    final composed = compose(
      bootstrap: bootstrap,
      config: config,
      clock: clock,
      log: write,
      reminderSender: reminderSender,
    );
    final sessions = composed.sessions;

    final swept = await sessions.purgeExpired();
    if (swept > 0) write('swept $swept expired session(s) at start-up');

    final webRoot = config.webRoot;
    final httpServer = await shelf_io.serve(
      webRoot == null
          ? composed.handler
          : withWebApp(api: composed.handler, webRoot: webRoot),
      config.address,
      config.port,
    );
    if (webRoot != null) write('serving the web app from ${webRoot.path}');

    // Cheque reminders: once at start-up, then every hour. Hourly rather than
    // once a day so a reminder is not lost to a server that happened to be
    // restarting at the one moment it would have run; the log of attempts
    // makes running often harmless.
    Future<void> remind() async {
      try {
        final result = await composed.reminders.run(composed.reminderSender);
        if (result.due > 0 || result.notConfiguredReason != null) {
          write('$result');
        }
      } catch (error) {
        write('cheque reminder run FAILED: $error');
      }
    }

    unawaited(remind());
    final reminderTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => remind(),
    );

    write('Venvo POS API ${config.describe()}');
    if (bootstrap.needsFirstRunSetup) {
      write(
        'no users exist yet: a client must call POST /api/v1/auth/first-run '
        'to create the administrator. No default account has been created.',
      );
    }

    return VenvoApiServer._(
      config: config,
      bootstrap: bootstrap,
      httpServer: httpServer,
      reminderTimer: reminderTimer,
      maintenance: Timer.periodic(_maintenanceInterval, (_) async {
        try {
          final removed = await sessions.purgeExpired();
          if (removed > 0) write('swept $removed expired session(s)');
        } catch (error) {
          // Housekeeping must not take the server down — and must not fail
          // silently either.
          write('session sweep failed: $error');
        }
      }),
    );
  }

  /// Builds every service and the request handler over [bootstrap], without
  /// binding a socket.
  ///
  /// Separate from [start] for one reason: the client application's own tests
  /// drive the real handler in-process, so the screens are exercised against
  /// the real server logic with no network in between. [start] is this plus a
  /// listening socket and the housekeeping timer.
  static ({
    Handler handler,
    SessionStore sessions,
    ChequeReminderService reminders,
    ReminderSender reminderSender,
  })
  compose({
    required AppBootstrap bootstrap,
    required ServerConfig config,
    required void Function(String message) log,
    Clock clock = const SystemClock(),
    ReminderSender? reminderSender,
  }) {
    final auth = AuthRepository(
      database: bootstrap.database,
      clock: clock,
      audit: bootstrap.audit,
    );

    // The same repositories the desktop client builds, over the same
    // database. Locations is constructed first because agents and shops need
    // it: creating an agent creates the inventory location that makes the
    // stock ledger balance for it.
    final locations = LocationRepository(
      database: bootstrap.database,
      clock: clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
    );
    // The stock ledger needs the financial ledger: a movement posts its
    // inventory value into the journal in the same transaction, which is what
    // keeps the stock figures and the accounts from disagreeing.
    final finance = FinancialLedgerService(
      database: bootstrap.database,
      clock: clock,
      sequences: bootstrap.sequences,
    );
    final stockLedger = StockLedgerService(
      database: bootstrap.database,
      clock: clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
      settings: bootstrap.settings,
      finance: finance,
    );

    // Payments before invoices: an invoice may take an immediate payment, so
    // the invoice service is given the payment service rather than repeating
    // any of it.
    final paymentService = PaymentService(
      database: bootstrap.database,
      clock: clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
      finance: finance,
    );
    final invoiceService = InvoiceService(
      database: bootstrap.database,
      clock: clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
      settings: bootstrap.settings,
      ledger: stockLedger,
      payments: paymentService,
      finance: finance,
    );

    // Petty cash before expenses: an expense marked as paid from the float
    // writes its petty cash entry in the same transaction, so the expense
    // service is given the petty cash service rather than duplicating it.
    final pettyCashService = PettyCashService(
      database: bootstrap.database,
      clock: clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
      finance: finance,
    );

    final modules = _Modules(
      products: ProductRepository(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
      ),
      categories: CategoryRepository(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
      ),
      agents: AgentRepository(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        locations: locations,
      ),
      shops: ShopRepository(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        locations: locations,
      ),
      employees: EmployeeRepository(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
      ),
      locations: locations,
      stockQueries: StockQueryRepository(bootstrap.database),
      stockLedger: stockLedger,
      stockCounts: StockCountRepository(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        ledger: stockLedger,
      ),
      invoices: invoiceService,
      invoiceQueries: InvoiceQueryRepository(bootstrap.database),
      payments: paymentService,
      paymentQueries: PaymentQueryRepository(bootstrap.database),
      finance: finance,
      returns: ReturnService(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        ledger: stockLedger,
        locations: locations,
        finance: finance,
      ),
      returnQueries: ReturnQueryRepository(bootstrap.database),
      expenses: ExpenseService(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        finance: finance,
        pettyCash: pettyCashService,
      ),
      expenseQueries: ExpenseQueryRepository(bootstrap.database),
      pettyCash: pettyCashService,
      salaries: SalaryService(
        database: bootstrap.database,
        clock: clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        finance: finance,
      ),
      salaryQueries: SalaryQueryRepository(bootstrap.database),
      reports: ReportRepository(
        database: bootstrap.database,
        clock: clock,
        finance: finance,
      ),
      dashboard: DashboardRepository(bootstrap.database, clock),
      settings: bootstrap.settings,
      database: bootstrap.database,
      audit: bootstrap.audit,
      // Backups need somewhere to be written. A graph built for a test with
      // no data directory has nowhere, so it simply has no backup endpoints.
      backups: bootstrap.paths == null
          ? null
          : BackupService(
              database: bootstrap.database,
              paths: bootstrap.requirePaths,
              clock: clock,
              audit: bootstrap.audit,
              settings: bootstrap.settings,
            ),
      attachments: bootstrap.paths == null
          ? null
          : AttachmentService(
              database: bootstrap.database,
              paths: bootstrap.requirePaths,
              clock: clock,
              audit: bootstrap.audit,
            ),
      logos: bootstrap.paths == null ? null : LogoStore(bootstrap.requirePaths),
      reminders: ChequeReminderService(
        database: bootstrap.database,
        settings: bootstrap.settings,
        clock: clock,
      ),
      reminderSender:
          reminderSender ??
          WhatsAppCloudSender.fromEnvironment(Platform.environment),
    );
    final userAdmin = UserAdminRepository(
      database: bootstrap.database,
      clock: clock,
      audit: bootstrap.audit,
    );
    final sessions = SessionStore(
      database: bootstrap.database,
      auth: auth,
      clock: clock,
      config: config,
    );

    return (
      handler: _buildHandler(
        auth: auth,
        userAdmin: userAdmin,
        modules: modules,
        sessions: sessions,
        schemaVersion: bootstrap.database.schemaVersion,
        log: log,
      ),
      sessions: sessions,
      reminders: modules.reminders,
      reminderSender: modules.reminderSender,
    );
  }

  /// Three pipelines, cascaded in order of how much they trust the caller.
  ///
  /// The ordering is what makes this correct. A request carrying a valid token
  /// for a business path falls through the identity router's 404 and reaches
  /// the business router. The same path with **no** token stops at the
  /// identity pipeline with a 401 — the right answer, and one that tells an
  /// unauthenticated caller nothing about which paths exist.
  ///
  /// Anything mounted on the business pipeline is authenticated and
  /// password-change-gated by default. Making an endpoint public means moving
  /// it into [publicRoutes] deliberately, so an endpoint cannot end up open
  /// because something was forgotten.
  static Handler _buildHandler({
    required AuthRepository auth,
    required UserAdminRepository userAdmin,
    required _Modules modules,
    required SessionStore sessions,
    required int schemaVersion,
    required void Function(String) log,
  }) {
    Handler pipeline(
      Handler inner, {
      required bool authenticated,
      bool gated = false,
    }) {
      var built = const Pipeline().addMiddleware(handleFailures(log: log));
      if (authenticated) built = built.addMiddleware(requireSession(sessions));
      if (gated) built = built.addMiddleware(refuseUntilPasswordChanged());
      return built.addHandler(inner);
    }

    final public = Router()
      ..mount(
        '/api/v1/',
        publicRoutes(
          auth: auth,
          sessions: sessions,
          schemaVersion: schemaVersion,
          // The automatic daily backup, on the first sign-in of the day by
          // somebody allowed to take one — the same trigger the desktop
          // build used, now running where the database is. Not awaited: a
          // backup must never slow somebody getting to work. A failure is
          // logged, not swallowed.
          onSignedIn: (user) {
            final backups = modules.backups;
            if (backups == null || !user.can(Permissions.backupRun)) return;
            unawaited(
              backups
                  .runAutomaticBackupIfDue(user)
                  .then<void>(
                    (archive) {
                      if (archive != null) log('automatic daily backup taken');
                    },
                    onError: (Object error) {
                      log('automatic daily backup FAILED: $error');
                    },
                  ),
            );
          },
        ).call,
      )
      // Liveness, for the reverse proxy and for monitoring. Reveals nothing
      // about the business and needs no credentials.
      ..mount('/api/v1/', brandingPublicRoutes(logos: modules.logos).call)
      ..get('/health', (Request request) => Api.ok({'status': 'ok'}));

    final identity = Router()
      ..mount('/api/v1/', identityRoutes(auth: auth, sessions: sessions).call);

    // One module router per area, cascaded so that each falls through to the
    // next on a 404. `mount` strips the `/api/v1/` prefix before the cascade
    // sees the request, so the module routers declare plain paths like
    // `/products` and the prefix lives in exactly one place.
    //
    // A failure thrown inside a module is an exception, not a response, so it
    // passes straight out of the cascade to `handleFailures` — a 403 from one
    // module is never mistaken for "not found here, try the next one".
    final business = Router()
      ..mount(
        '/api/v1/',
        Cascade()
            .add(
              adminRoutes(
                users: userAdmin,
                auth: auth,
                sessions: sessions,
              ).call,
            )
            .add(
              masterDataRoutes(
                products: modules.products,
                categories: modules.categories,
                agents: modules.agents,
                shops: modules.shops,
                employees: modules.employees,
                locations: modules.locations,
              ).call,
            )
            .add(
              stockRoutes(
                queries: modules.stockQueries,
                ledger: modules.stockLedger,
                counts: modules.stockCounts,
              ).call,
            )
            .add(
              invoiceRoutes(
                invoices: modules.invoices,
                queries: modules.invoiceQueries,
              ).call,
            )
            .add(
              paymentRoutes(
                payments: modules.payments,
                queries: modules.paymentQueries,
              ).call,
            )
            .add(
              returnRoutes(
                returns: modules.returns,
                queries: modules.returnQueries,
              ).call,
            )
            .add(
              expenseRoutes(
                expenses: modules.expenses,
                queries: modules.expenseQueries,
              ).call,
            )
            .add(pettyCashRoutes(pettyCash: modules.pettyCash).call)
            .add(
              salaryRoutes(
                salaries: modules.salaries,
                queries: modules.salaryQueries,
              ).call,
            )
            .add(reportRoutes(reports: modules.reports).call)
            .add(
              systemRoutes(
                dashboard: modules.dashboard,
                finance: modules.finance,
                settings: modules.settings,
                database: modules.database,
                audit: modules.audit,
              ).call,
            )
            .add(financeRoutes(finance: modules.finance).call)
            .add(
              modules.backups == null
                  ? Router().call
                  : backupRoutes(backups: modules.backups!).call,
            )
            .add(
              modules.attachments == null
                  ? Router().call
                  : chequeExtraRoutes(
                      attachments: modules.attachments!,
                      reminders: modules.reminders,
                      sender: modules.reminderSender,
                      log: log,
                    ).call,
            )
            .add(
              modules.logos == null
                  ? Router().call
                  : brandingAdminRoutes(
                      logos: modules.logos!,
                      settings: modules.settings,
                      audit: modules.audit,
                    ).call,
            )
            .handler,
      );

    return Cascade()
        .add(pipeline(public.call, authenticated: false))
        .add(pipeline(identity.call, authenticated: true))
        .add(pipeline(business.call, authenticated: true, gated: true))
        .handler;
  }

  Future<void> stop() async {
    _maintenance.cancel();
    _reminderTimer.cancel();
    await _httpServer.close(force: true);
    await _bootstrap.database.close();
  }

  static void _stdoutLog(String message) {
    // This is a server: stdout is where a container's logs come from.
    // ignore: avoid_print
    print('${DateTime.now().toUtc().toIso8601String()} $message');
  }
}

/// The business repositories, built once at start-up and shared by every
/// request.
///
/// They hold no per-request state — the actor is passed into each call — so a
/// single instance each is correct, and it keeps the repositories off the hot
/// path of building a response.
class _Modules {
  const _Modules({
    required this.products,
    required this.categories,
    required this.agents,
    required this.shops,
    required this.employees,
    required this.locations,
    required this.stockQueries,
    required this.stockLedger,
    required this.stockCounts,
    required this.invoices,
    required this.invoiceQueries,
    required this.payments,
    required this.paymentQueries,
    required this.finance,
    required this.returns,
    required this.returnQueries,
    required this.expenses,
    required this.expenseQueries,
    required this.pettyCash,
    required this.salaries,
    required this.salaryQueries,
    required this.reports,
    required this.dashboard,
    required this.settings,
    required this.database,
    required this.audit,
    required this.backups,
    required this.attachments,
    required this.logos,
    required this.reminders,
    required this.reminderSender,
  });

  final ProductRepository products;
  final CategoryRepository categories;
  final AgentRepository agents;
  final ShopRepository shops;
  final EmployeeRepository employees;
  final LocationRepository locations;
  final StockQueryRepository stockQueries;
  final StockLedgerService stockLedger;
  final StockCountRepository stockCounts;
  final InvoiceService invoices;
  final InvoiceQueryRepository invoiceQueries;
  final PaymentService payments;
  final PaymentQueryRepository paymentQueries;
  final FinancialLedgerService finance;
  final ReturnService returns;
  final ReturnQueryRepository returnQueries;
  final ExpenseService expenses;
  final ExpenseQueryRepository expenseQueries;
  final PettyCashService pettyCash;
  final SalaryService salaries;
  final SalaryQueryRepository salaryQueries;
  final ReportRepository reports;
  final DashboardRepository dashboard;
  final SettingsService settings;

  /// The audit trail is read with a direct query rather than through a
  /// repository, because the offline build never needed one — its screen
  /// queried the database itself.
  final AppDatabase database;
  final AuditService audit;

  /// Null when the graph has no data directory to write archives into.
  final BackupService? backups;
  final AttachmentService? attachments;
  final LogoStore? logos;
  final ChequeReminderService reminders;
  final ReminderSender reminderSender;
}
