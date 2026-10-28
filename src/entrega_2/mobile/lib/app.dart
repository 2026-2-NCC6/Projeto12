import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'state/app_settings.dart';
import 'theme/app_theme.dart';

class SmartTennisArenaApp extends StatefulWidget {
  const SmartTennisArenaApp({super.key, this.initialLocation = Routes.login});

  /// Tela inicial (padrão: Login). Útil para abrir uma tela direto em testes.
  final String initialLocation;

  @override
  State<SmartTennisArenaApp> createState() => _SmartTennisArenaAppState();
}

class _SmartTennisArenaAppState extends State<SmartTennisArenaApp> {
  late final GoRouter _router = createRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TOBIAS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // pt-BR nos componentes do Material (ex.: seletor de data do cadastro).
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      builder: (context, child) => ValueListenableBuilder(
        valueListenable: AppSettings.textoGrande,
        builder: (context, grande, _) {
          if (!grande) return child!;
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(
                mq.textScaler.scale(1) * AppSettings.escalaGrande,
              ),
            ),
            child: child!,
          );
        },
      ),
    );
  }
}
