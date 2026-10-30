// Validação local dos campos de Login e Cadastro, feita antes de chamar a API.
// Cada função devolve a mensagem em português para mostrar abaixo do campo,
// ou `null` quando o valor é válido.

/// Algo antes do @, um domínio e uma extensão (ex.: nome@dominio.com).
final _formatoEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validarEmail(String email) {
  if (email.isEmpty) return 'Informe seu e-mail.';
  if (!_formatoEmail.hasMatch(email)) return 'Digite um e-mail válido.';
  return null;
}

/// Login: só exige que a senha tenha sido preenchida.
String? validarSenhaLogin(String senha) {
  if (senha.isEmpty) return 'Informe sua senha.';
  return null;
}

/// Cadastro: mesmos limites da API (8 a 72 caracteres).
String? validarSenhaCadastro(String senha) {
  if (senha.isEmpty) return 'Informe sua senha.';
  if (senha.length < 8) return 'A senha deve ter no mínimo 8 caracteres.';
  if (senha.length > 72) return 'A senha deve ter no máximo 72 caracteres.';
  return null;
}

/// Cadastro: mesmos limites da API (3 a 120 caracteres).
String? validarNome(String nome) {
  if (nome.isEmpty) return 'Informe o nome.';
  if (nome.length < 3) return 'O nome deve ter no mínimo 3 caracteres.';
  if (nome.length > 120) return 'O nome deve ter no máximo 120 caracteres.';
  return null;
}

/// Cadastro: mesmos limites da API (2 a 40 caracteres).
String? validarApelido(String apelido) {
  if (apelido.isEmpty) return 'Informe o apelido.';
  if (apelido.length < 2) return 'O apelido deve ter no mínimo 2 caracteres.';
  if (apelido.length > 40) return 'O apelido deve ter no máximo 40 caracteres.';
  return null;
}

/// Cadastro: data de nascimento obrigatória.
String? validarNascimento(DateTime? data) {
  if (data == null) return 'Informe a data de nascimento.';
  return null;
}
