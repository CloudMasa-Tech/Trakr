import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'firebase/firebase_context.dart';
import 'firebase/firebase_context_provider.dart';
import 'firebase/firebase_manager.dart';
import 'firebase_options.dart';
import 'providers/auth_session_provider.dart';
import 'providers/company_provider.dart';
import 'providers/white_label_provider.dart';
import 'router/app_router.dart';
import 'services/notification_service.dart';
import 'theme/app_theme_colors.dart';
import 'services/bootstrap_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseContext? firebaseContext;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Ensure Master Super Admin exists before proceeding.
    await BootstrapService.instance.bootstrapMasterAdmin();
    if (kIsWeb) {
      // Clean, path-based URLs (no `#`) so workspace routes like
      // `/workspace/cloudmasa-innovation-lab/dashboard` are real URL paths.
      usePathUrlStrategy();
      await FirebaseManager.instance.getAuth().setPersistence(
            Persistence.LOCAL,
          );
      FirebaseManager.instance.getFirestore().settings = const Settings(
        webExperimentalForceLongPolling: true,
      );
    }

    // Bind the singleton NotificationService to the active Firebase context.
    firebaseContext = FirebaseContext();
    NotificationService().configure(firebaseContext);

    // Re-bind singletons whenever FirebaseManager swaps the active project.
    FirebaseManager.instance.setContextApplier(NotificationService().configure);

    // Initialize Push Notifications (Non-blocking to prevent UI hang)
    unawaited(NotificationService().initialize());
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
  runApp(TrakrApp(firebaseContext: firebaseContext));
}

/// Root of the app.
///
/// Mounts the provider tree bound to the Master control-plane project. Login is
/// a single Email/Password screen (no workspace code): [AuthSessionProvider]
/// resolves the entered email against the Master identity index, then swaps the
/// app-wide Firebase context to the tenant's own project before authenticating.
/// [WhiteLabelProvider] and [CompanyProvider] follow those context swaps so
/// branding and company state always come from the active workspace.
class TrakrApp extends StatelessWidget {
  const TrakrApp({super.key, this.firebaseContext});

  /// The initial Firebase context, bound to the default (Master control plane)
  /// project.
  final FirebaseContext? firebaseContext;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FirebaseContextProvider>(
          create: (_) => FirebaseContextProvider(context: firebaseContext),
        ),
        // Hoist AuthSessionProvider to be available for all routes.
        // It uses the Master context initially and swaps to the resolved tenant
        // project during sign-in.
        ChangeNotifierProvider(
          create: (ctx) => AuthSessionProvider(
              context: ctx.read<FirebaseContextProvider>().context),
        ),
        // WhiteLabelProvider follows the active context so branding is
        // data-driven from the session's own project.
        ChangeNotifierProvider(create: (_) => WhiteLabelProvider()),
        // CompanyProvider follows the active context and resolves the signed-in
        // user's company.
        ChangeNotifierProvider(
            create: (ctx) => CompanyProvider(
                context: ctx.read<FirebaseContextProvider>().context)),
      ],
      child: const AppRoot(),
    );
  }
}

/// The app. A [GoRouter] owns all navigation: `/` is the auth gate (loading,
/// landing/login, or the Super Admin portal), and signed-in tenant users are
/// redirected to `/workspace/:workspaceSlug/dashboard` so the address bar
/// always shows the active workspace. The router re-evaluates its redirects
/// whenever [AuthSessionProvider] notifies (login, logout, session restore).
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildAppRouter(context.read<AuthSessionProvider>());
  }

  @override
  Widget build(BuildContext context) {
    final whiteLabel = context.watch<WhiteLabelProvider>();

    return MaterialApp.router(
      title: 'TЯAKR.',
      debugShowCheckedModeBanner: false,
      theme: whiteLabel.lightTheme,
      darkTheme: whiteLabel.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: _router,
      builder: (context, child) {
        // The footer should only show in the main app, not on the unauthenticated
        // web landing page.
        final auth = context.watch<AuthSessionProvider>();
        final hideFooter = kIsWeb && !auth.isAuthenticated;
        return Column(
          children: [
            Expanded(child: child ?? const SizedBox.shrink()),
            if (!hideFooter) const AppFooter(),
          ],
        );
      },
    );
  }
}

class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).size.width < 800) {
      return const SizedBox.shrink();
    }

    final year = DateTime.now().year.toString();
    final colors = AppColors.of(context);
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: const BoxDecoration(
        gradient: AppThemeColors.actionGradient,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: '@',
              style: TextStyle(decoration: TextDecoration.none),
            ),
            TextSpan(
              text: 'Cloud',
              style: TextStyle(
                color: onPrimary.withValues(alpha: 0.92),
                decoration: TextDecoration.none,
              ),
            ),
            TextSpan(
              text: 'MaSa',
              style: TextStyle(
                color: colors.secondary,
                decoration: TextDecoration.none,
              ),
            ),
            TextSpan(
              text: ' $year',
              style: const TextStyle(decoration: TextDecoration.none),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: onPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
      ),
    );
  }
}
