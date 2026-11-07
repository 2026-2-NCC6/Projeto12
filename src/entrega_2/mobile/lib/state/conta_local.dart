import '../data/auth_store.dart';
import '../data/fila_sessoes.dart';
import '../data/mock_data.dart';
import 'app_settings.dart';
import 'device_state.dart';
import 'profile_state.dart';

/// Depois de excluir a conta no servidor, apaga do aparelho tudo o que era
/// dela: o token e o usuário guardados, a calibração, a fila de sessões e as
/// preferências.
///
/// A fila é o que mais importa: sem apagá-la, o próximo cadastro neste
/// aparelho herdaria as sessões pendentes da conta excluída e tentaria
/// enviá-las com o token novo, como se fossem dele.
///
/// O endereço do servidor (`api_base_url`) fica: é configuração do aparelho,
/// não dado da pessoa, e apagá-lo mandaria o próximo login para outro lugar.
///
/// O envio em segundo plano não precisa ser parado: uma nova tentativa
/// agendada encontra a fila vazia, e uma rodada já em curso usa o token da
/// conta excluída, recebe 401 e para.
Future<void> esquecerContaNoAparelho({FilaSessoes? fila}) async {
  await (fila ?? FilaSessoes.doApp).apagarTudo();
  await AuthStore.limparToken(); // token, papel, calibração e usuário

  // Estado em memória.
  DeviceState.calibracao.value = 0.0;
  DeviceState.refAngulo.value = Mock.deviceRefAngulo;
  ProfileState.foto.value = null;
  AppSettings.textoGrande.value = false;
}
