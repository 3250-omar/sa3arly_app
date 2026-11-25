import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/features/auth/login_screen.dart';
import 'package:sanitary_pricing_app/features/reports/reports_screen.dart';
import 'package:sanitary_pricing_app/features/review/review_screen.dart';
import 'package:sanitary_pricing_app/features/shell/main_shell.dart';
import 'package:sanitary_pricing_app/providers/auth_provider.dart';
import 'package:sanitary_pricing_app/services/payment_reminder_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PaymentReminderService.initialize();

  if (!AppConfig.isDemoMode) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  runApp(
    const ProviderScope(
      child: SanitaryPricingApp(),
    ),
  );
}

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final _routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen<AuthState>(authProvider, (_, _) => notifier.refresh());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      if (AppConfig.isDemoMode) return null;
      final auth = ref.read(authProvider);
      final onLogin = state.matchedLocation == '/login';
      if (!auth.isAuthenticated) {
        return onLogin ? null : '/login';
      }
      if (onLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const MainShell(),
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) => const ReviewScreen(),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReportsScreen(),
      ),
    ],
  );
});

class SanitaryPricingApp extends ConsumerWidget {
  const SanitaryPricingApp({
    super.key,
    this.enableRemoteFonts = true,
  });

  final bool enableRemoteFonts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    return MaterialApp.router(
      title: AppConfig.appTitle,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [
        Locale('ar', 'EG'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme(enableRemoteFonts: enableRemoteFonts),
      routerConfig: router,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
