import 'package:flutter/material.dart';
import 'package:huideng_connection/connection_router.dart';
import 'package:huideng_connection/routed_transport.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/admin_api.dart';
import 'features/admin_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('ADMIN_SUPABASE_URL');
  const key = String.fromEnvironment('ADMIN_SUPABASE_PUBLIC_KEY');
  // No disk session persistence: closing this independent admin app signs out locally.
  final configured = Uri.tryParse(url)?.scheme == 'https' && key.isNotEmpty;
  final connection = configured
      ? ConnectionRouter(
          canonical: Uri.parse(url),
          project: url,
          publicKey: const String.fromEnvironment(
            'CONNECTION_CONFIG_PUBLIC_KEY',
          ),
          sources: const String.fromEnvironment('CONNECTION_CONFIG_URLS')
              .split(',')
              .where((s) => s.trim().isNotEmpty)
              .take(4)
              .map((s) => Uri.parse(s.trim()))
              .toList(),
        )
      : null;
  await connection?.initialize();
  final api = configured
      ? SupabaseAdminApi(
          SupabaseClient(
            url,
            key,
            httpClient: RoutedHttpClient(connection!),
            authOptions: const AuthClientOptions(autoRefreshToken: true),
          ),
        )
      : null;
  runApp(AdminApp(api: api));
}

class AdminApp extends StatelessWidget {
  final AdminApi? api;
  const AdminApp({super.key, this.api});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '文殊计数器后台管理',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff72533d)),
      scaffoldBackgroundColor: const Color(0xfffaf7f2),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 17),
        bodyLarge: TextStyle(fontSize: 18),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
    ),
    home: AdminShell(api: api),
  );
}
