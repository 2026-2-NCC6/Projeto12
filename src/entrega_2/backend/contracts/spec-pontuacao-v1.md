# Especificação da pontuação — TOBIAS

**Versão da regra:** 1
**Status:** proposta para implementação na US-705
**Atende:** RF10 (pontuação gamificada), US-705 (recálculo autoritativo)

Este documento é a fonte única da fórmula de pontuação. A implementação em
Python (servidor) e em Dart (app) devem produzir resultados idênticos, provado
pelos *golden fixtures* descritos na seção 8.

---

## 1. Origem e divergência declarada

A fórmula original está na seção 6.2 do `smart-tennis-arena-joao-bobo-v2.md`.
Ela não pode ser implementada como escrita, porque depende de quatro grandezas
que o firmware entregue não produz:

| Grandeza | O que seria | Situação no firmware entregue |
|---|---|---|
| `a_pk` | pico de aceleração, em g | Não existe. O firmware converte a leitura em **ângulo de inclinação, em graus** (`calcularAnguloInclinacao`) |
| `a_ref` | mediana dos picos da calibração | Não existe. A calibração devolve média e máximo **em graus** |
| `Ω` | integral do giroscópio em 2 s | Não existe. O giroscópio **nunca é lido**: `lerAcelerometroRaw` requisita 6 bytes a partir do registrador `0x3B`, que cobre apenas o acelerômetro |
| `t_r` | tempo entre o *cue* e o impacto | Não existe. O firmware **não emite *cue***; ele apenas abre uma janela de tempo e aguarda |

A fórmula da seção 6.2 foi escrita para o firmware planejado. O firmware
construído mede inclinação, não aceleração.

**Decisão:** preservar o raciocínio de design da seção 6.2 — curva côncava
favorecendo o iniciante, multiplicador de sequência com teto, bônus de
derrubada, penalidade por erro — e reexpressá-lo nas grandezas que existem.

---

## 2. Dados de entrada

### Princípio: só o que o sensor mediu

A pontuação usa exclusivamente **medidas brutas**. Qualquer valor que o
firmware ou o app tenham *interpretado* é ignorado e recalculado pelo servidor.
É isso que torna o recálculo autoritativo de fato.

Por lance, vindos do firmware via app (contrato da US-704):

| Campo | Tipo | Uso na pontuação |
|---|---|---|
| `resultado` | `acerto` \| `erro` | decide o ramo da fórmula |
| `angulo` | graus, 1 casa decimal | **única** medida de perícia usada |
| `bola` | int | ordem, para a sequência |
| `knockout` | bool | **não usado** — recalculado pelo servidor (seção 4) |
| `classe` | `fraco` \| `medio` \| `forte` \| `sem_impacto` | **não usado** |
| `ts_ms` | int | **não usado** na versão 1 |

Por sessão:

| Campo | Faixa | Uso |
|---|---|---|
| `dificuldade` | 0,0 a 45,0 graus, 1 casa decimal | graus adicionais da calibração; define o teto da normalização |

A faixa de `dificuldade` acompanha a do `CalibracaoEntrada` já existente.

### Por que `classe` e `knockout` não entram

Ambos são decisões do firmware, tomadas na mesma linha de código: ao classificar
o pico, ele define `classe = "forte"` e `knockout = true` juntos, comparando o
ângulo com `ANGULO_KO + calibDificuldade`. São interpretações de uma medida, não
a medida.

Se o servidor confiasse no `knockout` recebido, um app adulterado somaria o
bônus de 75 pontos em qualquer lance, inclusive num de 25°.

Usar o ângulo bruto também torna irrelevante a divergência de limiares entre o
firmware (22/38/58°) e o manual BLE (15/30/50/65°), que permanece em aberto mas
não afeta o placar.

---

## 3. Precisão da entrada

`angulo` e `dificuldade` aceitam **no máximo uma casa decimal**. Mais do que
isso é recusado com `422`.

Isso não restringe nada que exista hoje: o firmware emite `String(valor, 1)` e o
app envia a calibração com `toStringAsFixed(1)`.

A razão é a equivalência entre as duas linguagens. Com uma casa decimal, a
conversão para décimos de grau é exata nos dois lados — no Python pela leitura
como `Decimal`, sem ponto flutuante em momento algum; no Dart por
`(valor * 10).round()`, verificado para os 1801 valores de 0,0 a 180,0 em IEEE
754. Aceitar precisão arbitrária exigiria definir uma regra de arredondamento, e
é exatamente aí que Python e Dart divergem.

Pelo mesmo motivo, a coluna `lance.angulo` é `Numeric(4,1)` e não `Float`: o
valor precisa voltar do banco como decimal exato para alimentar o recálculo.

---

## 4. A fórmula

Toda a aritmética é **inteira**. Ângulos em décimos de grau.

### Passo 1 — Normalização

```
piso = 220                          (22,0° — limiar de impacto válido no firmware)
teto = 580 + dificuldade_decimos    (58,0° — limiar de KO, deslocado pela calibração)

bruto = max( 0 , angulo_decimos − piso )        ← limita ANTES de dividir
I     = min( 1000 , bruto · 1000 // (teto − piso) )
```

`I` é a perícia normalizada, de 0 a 1000 milésimos.

O `max(0, …)` vem antes da divisão de propósito: sem ele, um ângulo abaixo do
piso produziria um numerador negativo e a divisão inteira passaria a divergir
entre Python e Dart (seção 7).

O piso é fixo porque o firmware não desloca `ANGULO_GATILHO` com a calibração;
apenas `ANGULO_MEDIO` e `ANGULO_KO` são deslocados.

### Passo 2 — Pontos de força, com curva côncava

```
se I ≤ 400:   f = (50 · I) // 400
se I ≤ 700:   f = 50 + (22 · (I − 400)) // 300
senão:        f = 72 + (18 · (I − 700)) // 300

P_forca = 10 + f          →  10 a 100
```

Três segmentos de inclinação decrescente (0,125 · 0,073 · 0,060 pontos por
milésimo) substituem o expoente 0,7 da fórmula original. A concavidade é a
mesma; a aritmética é exata.

O `+10` de base garante que uma batida fraca porém válida valha alguma coisa.
A fórmula original daria zero no limiar, o que contraria o próprio argumento
de engajamento do iniciante.

Valores de referência (dificuldade 0):

| Ângulo | 22° | 30° | 38° | 46° | 54° | 58°+ |
|---|---|---|---|---|---|---|
| `P_forca` | 10 | 37 | 63 | 79 | 93 | 100 |

Subir de 22° para 30° rende 27 pontos; de 50° para 58°, 14. Dobrar o esforço de
quem bate fraco vale mais do que dobrar o de quem já bate forte.

### Passo 3 — Multiplicador de sequência

```
streak = número de acertos consecutivos IMEDIATAMENTE ANTERIORES a este lance
m      = 100 + 10 · min(streak, 10)        →  100 a 200 (porcentagem)
```

O primeiro acerto de uma sequência tem `streak = 0`, logo `m = 100`. Um erro
zera a sequência.

**O teto de 10 é imutável.** Ele não é apenas equilíbrio de jogo: a seção 5.4
do documento da equipe o usa para sustentar que um Autômato Finito
Determinístico é suficiente, porque o contador cabe num conjunto finito de
estados. Um multiplicador sem limite mudaria a classe do modelo computacional
da entrega de Teoria da Computação.

### Passo 4 — Derrubada e penalidade

O KO é **determinado pelo servidor**, com a mesma regra do firmware:

```
ko = ( angulo_decimos ≥ teto )

B_ko = 75     quando ko
ERRO = −20
```

Invariante útil para teste: `ko` é verdadeiro exatamente quando `I = 1000`, já
que `I` satura no mesmo ponto.

O contador `kos` da sessão é recalculado pela mesma regra, não pela contagem
enviada.

### Fórmula final

```
acerto:  pontos_lance = (P_forca · m) // 100 + B_ko
erro:    pontos_lance = −20

pontuacao_total = max( 0 , Σ pontos_lance )
```

O multiplicador incide apenas sobre a perícia; o bônus de KO é somado depois,
como na fórmula original. O erro subtrai de fato, mas a sessão nunca fica
negativa.

---

## 5. Exemplos conferidos

Dificuldade 0 em todos.

| Situação | Conta | Pontos |
|---|---|---|
| 25,0°, sem sequência anterior | I=83 · f=10 · P=20 · m=100 · sem KO | **20** |
| 45,0°, 3 acertos anteriores | I=638 · f=67 · P=77 · m=130 · sem KO | **100** |
| 60,0°, 7 acertos anteriores | I=1000 · P=100 · m=170 · KO (60,0 ≥ 58,0) | **245** |
| Erro | — | **−20** |

---

## 6. Casos de borda

| Caso | Comportamento |
|---|---|
| Sessão sem lances | `pontuacao_total = 0`, `melhor_sequencia = 0` |
| Sessão só com erros | soma negativa, truncada em `0` |
| Ângulo abaixo de 22° num acerto | `bruto = 0`, `I = 0`, `P_forca = 10`, sem KO. Não deveria ocorrer; a fórmula não quebra |
| Ângulo acima do teto | `I = 1000` e KO. Bater mais forte que o KO não rende mais pontos de força |
| 11 ou mais acertos seguidos | `m` estabiliza em 200 |
| `dificuldade` ausente | tratada como 0 |
| `dificuldade` acima de 45,0 | `422` |
| Mais de uma casa decimal em `angulo` ou `dificuldade` | `422` |
| Erro com ângulo diferente de 0 | rejeitado na entrada pela validação da US-704 |

---

## 7. Aritmética inteira entre Python e Dart

A divisão inteira do Python (`//`) arredonda para baixo; a do Dart (`~/`) trunca
em direção ao zero. **São idênticas quando ambos os operandos são não
negativos.**

Regras obrigatórias nas duas implementações:

1. Nenhuma divisão opera sobre valor negativo. Por isso o `max(0, …)` do passo 1
   vem antes da divisão, e não depois. O único outro número negativo da fórmula
   é a penalidade de −20, que não passa por divisão.
2. Nenhum ponto flutuante em etapa alguma do cálculo. A conversão para décimos
   de grau acontece na fronteira de entrada (seção 3).
3. Nenhuma chamada a `round()` dentro da fórmula.

É por isso que o expoente 0,7 foi substituído por segmentos lineares: qualquer
potência fracionária reintroduziria divergência de arredondamento entre as duas
linguagens.

---

## 8. Golden fixtures

Arquivo: `contracts/pontuacao/golden.json`. Carregado pelos testes dos dois
lados — `pytest` no servidor, `flutter test` no app. Se alguém alterar a fórmula
de um lado só, o teste do outro quebra.

```json
{
  "versao_regra": 1,
  "casos": [
    {
      "id": "acerto-fraco-sem-sequencia",
      "dificuldade": 0.0,
      "lances": [
        { "bola": 1, "resultado": "acerto", "angulo": 25.0 }
      ],
      "esperado": {
        "pontos_por_lance": [20],
        "pontuacao_total": 20,
        "melhor_sequencia": 1,
        "kos": 0
      }
    }
  ]
}
```

Os casos **não** incluem `knockout` nem `classe` na entrada, justamente porque a
fórmula não os usa. Incluí-los convidaria uma implementação futura a lê-los.

Cobertura mínima: sessão vazia · só erros com total truncado em 0 · sequência
acima de 10 provando o teto · erro no meio zerando a sequência · ângulo
exatamente no limiar de KO · ângulo acima do teto · dificuldade diferente de
zero deslocando o teto · ângulo abaixo do piso · um caso longo com mistura de
tudo.

---

## 9. Versionamento da regra

A coluna `sessao.versao_pontuacao` grava qual versão produziu cada placar.
Sem ela não há como saber quais sessões precisam ser recalculadas quando a
fórmula mudar.

---

## 10. Detecção de divergência

O app pode enviar `pontuacao_cliente` por sessão. Esse valor é **apenas
comparado, nunca gravado** como oficial.

A comparação acontece somente quando as duas condições valem:

1. a requisição alterou a sessão — ela foi criada, recebeu lances novos, ou teve
   `encerrada_em` preenchida;
2. os lances do payload cobrem todos os lances gravados da sessão.

A primeira condição impede que um reenvio por timeout registre o mesmo alerta
várias vezes, inflando os números que a US-707 vai contar. A segunda impede
comparar um placar parcial com um total.

Havendo diferença: um `logger.warning` estruturado (id interno da sessão, id do
usuário, placar do servidor, placar do cliente, versão da regra — sem dados
pessoais) e um registro `pontuacao_divergente` em `log_auditoria`, atendendo ao
RF23.

---

## 11. O que ficou de fora, e por quê

**Pontos de reação.** A fórmula original tem `P_reacao = 50 · R`, medindo o
intervalo entre o *cue* e o impacto. O firmware entregue não emite *cue*. Seria
possível estimar o intervalo subtraindo `ts_ms` de lances consecutivos, menos os
1800 ms de áudio, menos o tempo variável de estabilização — um número apoiado em
três aproximações e sem significado físico.

A dimensão de consistência que o `P_reacao` carregava permanece representada
pelo multiplicador de sequência.

Se o firmware passar a emitir *cue*, o termo volta e a `versao_pontuacao` sobe
para 2.

**Consistência e ranking.** A seção 6.2 define
`Consistencia = 1 − σ(a_pk)/μ(a_pk)` e uma fórmula de ranking. Ambas dependem de
estatísticas sobre a população de sessões e não de um lance isolado; ficam para
quando existir a funcionalidade de ranking.
