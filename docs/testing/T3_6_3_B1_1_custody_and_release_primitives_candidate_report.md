# T3.6.3-B1.1 — Primitivas de custódia, proveniência D3 e liberação transacional de reservas

**Status:** CANDIDATA — implementada e testada automaticamente; **aguardando revisão independente e aceite do proprietário**. Não há teste manual aplicável (nenhum comando de gameplay foi adicionado).

## 1. Baseline

| Item | Valor |
|---|---|
| Repositório | `Julian0s/Dawn-of-Kin` |
| Branch de origem (homologada) | `feat/t3-6-2-provenance-transactions` @ `ec17f42bbcc8b1b8d7fba51c55c93f8fb89d66b5` |
| Branch candidata | `feat/t3-6-3-cancellation-custody` |
| Commit de implementação | `703f15fb7566481ada170dcb4dc9dc5b29dab7bd` |
| `main` (inalterada) | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` |
| Engine | Godot 4.7.2 stable, `gl_compatibility` |

## 2. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `src/economy/carry_provenance_ledger.gd` | Origens `CANCEL_TRANSIT`, `CANCEL_BUFFER`, `CANCEL_INCORPORATED`; `reclassify_lot()` (`SITE_RESERVED → CANCEL_TRANSIT`, exige `site_id`/`generation` correspondentes); operação `"reclassify"` em `restore_transaction_state()`. |
| `src/economy/unit_carry_load.gd` | Adição física direta restrita a `FREE_GATHERED` e `SITE_RESERVED`; lotes `CANCEL_*` não podem ser creditados sem fluxo verificado. |
| `src/economy/reserved_withdrawal_coordinator.gd` | `CancellationScope`, `CancellationCustodyRecord`, `RECEIPT_SITE_CANCELLATION`; registro regional de custódias em `RegionalAuthority`; rastreamento de escopos ativos integrado a `is_region_transaction_active_readonly`, inspeção de remoção de trabalhador e `release_regional_domain`; autorizações de commit/rollback; validação pura `Q = L + A + H + E + D + M`; sequência de estados pura; `execute_site_cancellation()` permanece *fail-closed*. |
| `src/economy/ground_pile_manager.gd` | `_prepare_cancel_release_under_guard`, `_apply_prepared_cancel_release_silent`, `_restore_cancel_release_checkpoint_silent`, `_publish_cancel_release_committed`, todos exigindo escopo de cancelamento possuído. |
| `src/economy/in_memory_storage_source.gd` | Mesmas quatro primitivas para o backend em memória; `is_locked()` considera cancelamento ativo. |
| `tests/unit/test_t3_6_3_b1_1_custody_and_release_primitives.gd` (+ `.uid`) | Suíte nova: 5 testes, 171 asserções. |

`docs/Dawn_of_Kin_GDD.md`: **sem alterações**.

## 3. Contratos implementados

1. **Proveniência D3.** Lotes `CANCEL_BUFFER`/`CANCEL_INCORPORATED` exigem `site_id` válido e `generation > 0`. A reclassificação é atômica, validada contra a obra/geração esperadas e reproduzível por *replay* do log transacional.
2. **Liberação de reserva com escopo.** Preparar não altera estado nem revisões. A aplicação silenciosa não emite sinais. A publicação só ocorre após `_authorize_cancellation_release_commit` e roda com as travas regionais mantidas (D-INT-02/A). O rollback é recusado após a autorização de commit.
3. **Rollback com revisão monotônica (Ajuste 1).** O rollback restaura exatamente as quantidades, a ordem das reservas e o `next_seq`, e mesmo assim avança `storage._transaction_revision` e a revisão do `PileReservationLedger`. Planos anteriores ao rollback falham com `stale_revision`.
4. **S = 0.** Uma liberação vazia é um *no-op* legítimo (`noop == true`) quando a reserva realmente não existe. Declarar S = 0 para uma reserva que ainda tem alocação falha fechado.
5. **Máquina de estados (Ajuste 2).** `FREEZING → SETTLED` direto continua proibido. Cancelamento sem custódia encadeia `FREEZING → RECOVERY_PENDING → SETTLED`.
6. **Registro de custódia (Ajustes 3 e 4).** Consultável por `cancel_id` e por `(site_id, generation)`, isolado por região/mundo, com duplicatas rejeitadas. `requires_local_footprint_occupation()` implementa D-CANC-02/A (A > 0 ou coleta local em curso ocupa o terreno; H > 0 sozinho não ocupa). `get_obligation_status()` distingue `settled`, `pending` e `blocked`.
7. **D3 operacional inacessível.** `execute_site_cancellation()` retorna `d3_cancellation_not_implemented`. Não há `SiteState.CANCELLED`, nem botão/UI, nem redirecionamento de trabalhadores.

## 4. Decisões respeitadas

- **D-CANC-01/A**, **D-CANC-02/A**, **D-CANC-03/A**: registradas. Neste incremento, só D-CANC-02/A tem código (predicado puro no registro). D-CANC-01/A e D-CANC-03/A ficam para B1.2–B1.4.
- **D-INT-01/B**, **D-INT-02/A**, **D-INT-03/A**: preservadas.

## 5. Evidências de teste

| Etapa | Comando | Resultado |
|---|---|---|
| RED (baseline `ec17f42`, sem produção) | `.\tools\run_tests.ps1 -Filter test_t3_6_3_b1_1` | 1 suíte, 5 testes, **0 aprovados / 5 falhas** (mensagens esperadas de “não implementado”) |
| GREEN | `.\tools\run_tests.ps1 -Filter test_t3_6_3_b1_1 -TimeoutSeconds 240` | **5/5**, 171 asserções, exit 0, sem vazamentos ao sair |
| Validação | `.\tools\validate.ps1` | **PASSED — 164 scripts, 0 erros, 0 avisos** |
| Regressão segmentada | `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | **489/489** testes, **69** suítes, **26.457** asserções, 17/17 lotes PASS, cobertura 69/69, 0 duplicados/ausentes |
| Whitespace | `git diff --check` | sem ocorrências |

### Correções feitas durante a validação GREEN
1. `in_memory_storage_source.gd` estava com o bloco das quatro primitivas duplicado por um erro de edição, o que causava *parse error*. A cópia redundante foi removida. O diff final só tem inserções.
2. A suíte nova vazava objetos ao encerrar (`World3D`/Scenario, meshes): o *teardown* tinha nome errado (`tear_down` em vez de `after_each`), os gerenciadores não chamavam `cleanup()`, as conexões de sinais com lambdas não eram desfeitas e o domínio regional não era liberado. O *teardown* agora segue o padrão das suítes C4.x: desconecta sinais, libera nós, chama `cleanup()` e faz `release_regional_domain`. O código de produção não foi alterado por esse motivo.

## 6. Limites e pendências

- **Não verificado:** comportamento visual (não se aplica a este incremento).
- Custódias vivem só em memória na sessão; persistência fica para a T3.8.
- Fora do escopo: transação de commit do cancelamento (B1.2), coleta e entrega física (B1.3), redirecionamento de trabalhadores (B1.4) e UI.

## 7. Próximo incremento proposto

**T3.6.3-B1.2**: transação atômica de commit do cancelamento em `ACTIVE`, usando as primitivas deste incremento. Só começa após revisão independente e aprovação expressa do proprietário.
