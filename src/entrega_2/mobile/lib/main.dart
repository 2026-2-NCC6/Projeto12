import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/api_client.dart';
import 'data/api_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.carregarConfig();
  // Acorda a API em segundo plano enquanto o usuário digita o login.
  unawaited(ApiClient().acordarApi());
  // Desenha atrás das barras do sistema; cada tela define a cor dos ícones.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SmartTennisArenaApp());
}
