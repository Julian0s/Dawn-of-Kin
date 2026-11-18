# T3.6.1 — Relatório da candidata

**Estado:** candidata para auditoria independente; cancelamento operacional não implementado.

Base `fb31887e9ee6671d81a6797ea0d921c6d8b7a979`. Referência arquitetural [T3.6-R2](https://github.com/Julian0s/Dawn-of-Kin/blob/69c13275a34a30564ac839ec920f83ef36590812/docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md), commit `69c13275a34a30564ac839ec920f83ef36590812`. A R2 permanece preservada na branch documental.

## Escopo e contratos

Arquivos novos: `src/buildings/construction_cancellation_math.gd` e seu UID; `tests/unit/test_t3_6_1_refund_math.gd` e seu UID; este relatório. Nenhum código existente de economia, construção ou ordens foi modificado.

`ConstructionCancellationMath.evaluate_refund(incorporated, progress, total_work)` retorna `{ok, value}` ou erro `{ok, reason}`. Todos os argumentos devem ser inteiros; `0 <= progress <= total_work`, `total_work > 0`, `incorporated >= 0`. Calcula exatamente `floor(floor(C*(W-P)/W)/2)`, equivalente a `floor(C*(W-P)/(2*W))`, sem ponto flutuante. Verifica `C <= INT64_MAX/(W-P)` antes do produto; se este não couber, retorna `overflow`, inclusive para alguns resultados matematicamente representáveis. Em progresso máximo retorna zero sem multiplicação. Nenhum cálculo de `2*W` é necessário.

`evaluate_snapshot(snapshot)` aceita `{progress, total_work, resources}`; por ID de recurso String/StringName não vazio exige exatamente `{required, reserved, in_transit, buffer, incorporated, missing}` como inteiros não negativos. A soma verificada das cinco categorias deve ser igual ao custo; campos extras, valores inválidos, chaves inválidas e overflow são recusados. O resultado novo, por recurso, distingue `reservation_release`, `in_transit`, `buffer`, `incorporated_recovered`, `demolition_loss`, `missing`, `future_physical_return` e `total_predicted`. As somas posteriores são limitadas pela soma contábil previamente verificada. `physical_verified` é sempre falso: a validade matemática não verifica pilhas, mochilas ou claims. Entradas não são alteradas.

`plan_transition(from, to)` valida estados puros ACTIVE, REQUESTED, PREVALIDATING, FREEZING, RECOVERY_PENDING (commit), RETURNING, RETURN_BLOCKED e SETTLED. Mesma transição consultada produz o mesmo resultado; pedir o estado atual é um no-op. Após commit não existe transição para ACTIVE. Nenhum nó ou estado do jogo é alterado; o contrato não comprova as condições físicas ou transacionais de cada transição.

## Exemplos e validação

| Progresso e snapshot | Madeira prevista | Pedra prevista | Observação |
|---|---:|---:|---|
| 0%, buffer 12/6 | 12 | 6 | Sem incorporado |
| 50%, buffer 6/3, incorporado 6/3 | 7 | 3 | Recuperado incorporado 1/0, perda 5/3 |
| 90% histórico, buffer 1/0, incorporado 11/6 | 1 | 0 | Hipotético, não produzido pelo consumo atual a 90% |
| 90% alcançável, buffer 2/1, incorporado 10/5 | 2 | 1 | P=27.000.000; W=30.000.000 |

Valores de referência dos testes foram obtidos por aritmética inteira direta da fórmula, incluindo o limiar de 50% e o produto `3.000.000.000 * 1.000.000.000`; testes não dependem de Python. A suíte também cobre reservas, trânsito, déficit, chaves e tipos inválidos, imutabilidade, limites e estouro. Resultados obtidos em Godot 4.7.2:

- `./tools/run_tests.ps1 -Filter t3_6_1_refund_math`: 5/5 testes, 113 asserções, sem falhas.
- `./tools/validate.ps1`: 124 scripts, zero erros e avisos; importação e inicialização headless aprovadas.
- `./tools/run_tests.ps1 -Segmented`: 42/42 suítes, 289/289 testes, 13.031 asserções, zero falhas ou erros de suíte; 42 suítes únicas e nenhuma ausente.
- `git diff --check`: sem erros.

Não houve teste visual nem alteração de gameplay. Este módulo não disponibiliza liberação real, botão, congelamento, custódia, devolução ou cancelamento.

## Limites e continuidade

A T3.6.2 deverá abordar proveniência, fronteiras transacionais e rollback reais antes de qualquer cancelamento operacional. A correção editorial do exemplo histórico de 90% permanece para tarefa documental própria. Não há persistência, validação de existência física nem prova de atomicidade neste incremento. Homologação e integração dependem de auditoria e decisão posterior.

Commits técnicos: `62cee100d5fa4793b1ad4a19794805dc184cf557` (implementação), `6ed91ec2699daef2b4795a7a66ff9ef42bf1edfd` (testes). O commit que contém este relatório é identificável pelo histórico Git.
