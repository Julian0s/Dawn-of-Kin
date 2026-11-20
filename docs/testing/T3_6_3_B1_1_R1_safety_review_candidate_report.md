# T3.6.3-B1.1-R1 — Revisão de segurança da custódia e do escopo

Base `6003287c6b35afb9bfe54f995a94e4b1eeb19470`, branch `feat/t3-6-3-cancellation-custody`. A referência homologada C4.12 é `ec17f42bbcc8b1b8d7fba51c55c93f8fb89d66b5`.

## Reprodução RED

- A liberação controlada apagou a autoridade regional diante de custódia local em `RECOVERY_PENDING`, carga em trânsito em `RETURNING` e custódia em `RETURN_BLOCKED`. O retorno indicou sucesso e a consulta subsequente perdeu o registro. Os controles com custódia liquidada e sem custódia liberaram a região.
- Nos dois backends, a autorização foi aceita antes da aplicação. Ao encerrar um segundo escopo depois da aplicação silenciosa e antes da publicação, a reserva de quatro madeiras continuou zerada e a revisão não avançou com uma reversão. O teste histórico também admitia um registro operacional sintético apenas com autorização antecipada.
- O RED confirmou 5/7 testes, 223 asserções e 15 falhas de asserção nos dois novos casos. A execução revelou ainda uma conexão de teste que sobrevivia ao backend em memória. A limpeza passou a desconectá-la antes de sair do cenário.

## Correção e fronteira econômica

A liberação regional exige que toda custódia esteja em `SETTLED`, sem saldo em `A` ou `H`, com identidade de mundo e região coerente e contabilidade válida. Obrigações abertas retornam `pending_cancellation_custody`, e registros inválidos retornam `invalid_cancellation_custody`. A recusa conserva a autoridade e os registros.

Preparar valida o plano. Aplicar silenciosamente vincula o checkpoint e as revisões da alteração. A autorização só permite prosseguir após validar a aplicação e permanece reversível. O backend revalida a prova antes de selar o commit econômico, imediatamente antes dos sinais. A partir desse ponto, o rollback é recusado. A publicação síncrona mantém a guarda regional e impede o encerramento reentrante, conforme D-INT-02/A.

Ao encerrar um escopo com aplicação pendente, o coordenador revoga a autorização de publicação, restaura o checkpoint pelo backend e solta as guardas após confirmar a restauração. A restauração avança as revisões e invalida planos anteriores. Um escopo sem mutações encerra normalmente. Os testes verificam a reserva da outra obra, os saldos físicos, a ausência de sinais intermediários, o replay da publicação e a recusa de mutações concorrentes.

O registro operacional de custódia retorna `d3_cancellation_not_implemented`, inclusive após uma liberação de reserva válida. Os testes de consulta e contabilidade montam registros locais de teste sem índices operacionais e os removem ao terminar. [Coordenador](../../src/economy/reserved_withdrawal_coordinator.gd) · [Pilhas físicas](../../src/economy/ground_pile_manager.gd) · [Backend em memória](../../src/economy/in_memory_storage_source.gd) · [Suíte B1.1](../../tests/unit/test_t3_6_3_b1_1_custody_and_release_primitives.gd).

## Validação

| Execução GREEN | Suítes | Aprovados | Asserções | Falhas / erros de suíte |
|---|---:|---:|---:|---:|
| B1.1-R1 | 1 | 7/7 | 254 | 0 / 0 |
| T3.6.1 focada | 1 | 5/5 | 113 | 0 / 0 |
| T3.6.2 focada | 25 | 187/187 | 11.499 | 0 / 0 |
| Segmentada final | 69 | 491/491 | 26.545 | 0 / 0 |

`validate.ps1` aprovou 164 scripts e a inicialização headless. A segmentada final executou as 69 suítes descobertas, sem omissões ou duplicatas. Os logs finais não registraram erros, avisos ou vazamentos do Godot. `git diff --check` passou.

A primeira segmentada atingiu os 120 segundos do lote de integração 06. Ela foi interrompida após o timeout e refeita integralmente com `-Segmented -GroupTimeoutSeconds 240`, sem alterar as suítes.

O commit técnico é `ce6d0ba286e471bb9143bf7782f2de73744b9e59`. O commit documental que contém este relatório fixa a revisão final. [Branch candidata](https://github.com/Julian0s/Dawn-of-Kin/tree/feat/t3-6-3-cancellation-custody).

## Limites

A proteção cobre a liberação controlada do registro regional. A proteção antes do teardown da cena pertence à B1.4. A finalização recusa a soltura se um checkpoint tiver sido invalidado fora dos caminhos cooperativos. A validação foi headless. O commit D3 da B1.2, a recuperação física e a persistência permanecem pendentes.
