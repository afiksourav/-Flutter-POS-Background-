import 'package:flutter/material.dart';

import 'services/pos_api.dart';
import 'ui/app_shell.dart';
import 'ui/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PosTransferApp());
}

class PosTransferApp extends StatefulWidget {
  const PosTransferApp({super.key});

  @override
  State<PosTransferApp> createState() => _PosTransferAppState();
}

class _PosTransferAppState extends State<PosTransferApp> {
  final PosApi _api = PosApi();
  String? _token;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await _api.savedToken();
    if (!mounted) return;
    setState(() {
      _token = token;
      _checkingSession = false;
    });
  }

  Future<void> _onLogin(String token) async {
    if (!mounted) return;
    setState(() => _token = token);
  }

  Future<void> _onLogout() async {
    await _api.logout();
    if (!mounted) return;
    setState(() => _token = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS Transfers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF167D75),
          brightness: Brightness.light,
          surface: const Color(0xFFF7F9FC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F9FC), surfaceTintColor: Colors.transparent),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE9EDF2)),
          ),
        ),
      ),
      home: _checkingSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _token == null
          ? LoginScreen(api: _api, onLogin: _onLogin)
          : AppShell(key: ValueKey(_token), token: _token!, api: _api, onLogout: _onLogout),
    );
  }
}
