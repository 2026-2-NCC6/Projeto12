/// CPF no cadastro. É dado pessoal (LGPD): fica mascarado na tela, não vai
/// para log e não aparece no ranking nem no perfil público.
library;

import 'package:flutter/services.dart';

/// Só os dígitos: "123.456.789-09" → "12345678909".
String cpfDigitos(String v) => v.replaceAll(RegExp(r'\D'), '');

/// Aplica a máscara 000.000.000-00 (parcial enquanto se digita).
String cpfMascara(String v) {
  final d = cpfDigitos(v);
  final buf = StringBuffer();
  for (var i = 0; i < d.length && i < 11; i++) {
    if (i == 3 || i == 6) buf.write('.');
    if (i == 9) buf.write('-');
    buf.write(d[i]);
  }
  return buf.toString();
}

/// Confere os dois dígitos verificadores. Sequências repetidas
/// (000.000.000-00, 111…) são inválidas.
bool cpfValido(String v) {
  final d = cpfDigitos(v).split('').map(int.parse).toList();
  if (d.length != 11 || d.every((x) => x == d[0])) return false;
  int dv(int n) {
    var soma = 0;
    for (var i = 0; i < n; i++) {
      soma += d[i] * (n + 1 - i);
    }
    final r = soma * 10 % 11;
    return r == 10 ? 0 : r;
  }

  return dv(9) == d[9] && dv(10) == d[10];
}

/// Formatador do campo: aceita só dígitos e aplica a máscara.
class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final texto = cpfMascara(newValue.text);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
