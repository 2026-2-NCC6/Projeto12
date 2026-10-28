/// Formatação pt-BR simples (sem dependência de `intl`).
library;

/// Inteiro com separador de milhar: 2146 → "2.146".
String fmtInt(int v) {
  final neg = v < 0;
  final digits = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${neg ? '−' : ''}$buf';
}

/// Decimal com vírgula: 1.5 → "1,5".
String fmtDec(double v, [int casas = 1]) =>
    v.toStringAsFixed(casas).replaceAll('.', ',');

/// Pontos com sinal: 96 → "+96", -20 → "−20".
String fmtPontos(int v) => v < 0 ? '−${-v}' : '+$v';

/// Número com dois dígitos: 9 → "09".
String twoDigits(int v) => v.toString().padLeft(2, '0');

/// Duração em segundos: 40 → "40 s", 60 → "1 min", 80 → "1 min 20 s".
String fmtDuracao(int segundos) {
  if (segundos < 60) return '$segundos s';
  final min = segundos ~/ 60, s = segundos % 60;
  return s == 0 ? '$min min' : '$min min $s s';
}

/// Data no formato dd/MM/aaaa: 12/05/1998.
String fmtData(DateTime d) =>
    '${twoDigits(d.day)}/${twoDigits(d.month)}/${d.year}';
