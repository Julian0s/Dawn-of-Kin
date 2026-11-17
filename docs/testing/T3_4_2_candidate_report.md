# Dawn of Kin — T3.4.2 — Relatório técnico candidato

**Status:** IMPLEMENTADA COMO CANDIDATA; aguardando auditoria independente e homologação do proprietário. Sem merge ou tag.

**Data:** 17/11/2026. **Branch:** `feat/t3-4-2-deterministic-assembly`.

**Worktree:** `C:/Projetos/Dawn_of_Kin_wt_t3_4_2`.

**Commit de implementação e testes:** `8302e6accce4317b02e49cb864add725fa4ea3e1`. O commit documental posterior contém somente este relatório.

## Base e autorização

- Base integrada verificada em `origin/main`: `60cfbe67382ccc321ee879c90c21fe449f16bf13`.
- Arquitetura T3.4-R2.3: `da20244f4320f0ae5e03236553f5c0e3f57f3a6f`; aprovação registrada em `39cdaac674d78111efd300b70b8f2f3909e347f9`.
- GDD normativo: `docs/Dawn_of_Kin_GDD.md`, v1.2.
- A autorização específica do pedido T3.4.2 permite este incremento, novo worktree, testes, relatório, commits e publicação da branch. Os bloqueios históricos dos documentos anteriores não representam revogação dessa autorização posterior.
- Engine executada: `4.7.2.stable.official.ed1daf0bf`. Projeto em `gl_compatibility`, Jolt; hardware disponível UHD 620 e GTX 1060, aproximadamente 16 GB RAM. Esta etapa não mede desempenho.

## Arquivos e contratos implementados

- [`construction_site.gd`](../../src/buildings/construction_site.gd): progresso e duração em microssegundos; getters `get_work_progress_sec()` e `get_progress_ratio()`; avaliador puro `evaluate_work_transaction_usec(progress_usec, total_usec, delta_usec, costs, incorporated, buffer)`; API `contribute_work(unit, delta_sec)` com nove guardas ordenadas; registro de âncoras por trabalhador/slot; invalidação por remoção, pruning ou mudança de papel/índice; pausa por material e reavaliação após entrega física; e política enxuta de sinais em `contribute_work()` (preserva `buffer_changed` + `state_changed` quando `advanced_usec > 0`; quando `advanced_usec == 0`, emite `state_changed` uma única vez apenas se houver mudança operacional real e não emite `buffer_changed` sem mutação de buffer, suprimindo emissões redundantes quando já está em `PAUSED_STARVED`).
- [`build_slot_planner.gd`](../../src/buildings/build_slot_planner.gd): `is_unit_at_assigned_builder_slot()`, raio horizontal de 0,75 m e tolerância vertical de 0,85 m. A ocupação da âncora e o alcance físico desobstruído são verificações separadas e obrigatórias.
- [`test_t3_4_2_deterministic_assembly.gd`](../../tests/unit/test_t3_4_2_deterministic_assembly.gd): 11 testes específicos de backend, incluindo `T34-AUT-08`, `T34-AUT-08B`, `T34-AUT-09` Parte A e `test_11_no_redundant_signals_in_paused_starved_and_legitimate_resume`; arquivo UID gerado pela importação Godot.
- Este relatório. Nenhum outro arquivo de produção foi alterado.

O avaliador não modifica os dicionários recebidos. Calcula o teto de cada recurso por `((capacity + 1) * total_usec - 1) / cost`, usando divisão inteira, e toma o mínimo global. Depois calcula e valida todos os débitos antes do commit. Há proteção contra overflow dos produtos inteiros e contra quantidades inválidas. A conversão de segundos usa `max(1, roundi(delta_sec * 1_000_000))`, conforme a alternativa expressamente permitida na arquitetura.

A Guarda 9 usa `Engine.get_physics_frames()` por unidade também em chamadas externas ao callback de física. Os testes avançam frames reais entre ciclos; não existe mecanismo de teste que desative a guarda. Uma trava de transação protege callbacks reentrantes durante emissão de sinais, e `_work_cycle_serial` registra os ciclos confirmados. Trabalhadores distintos podem contribuir no mesmo frame após cada commit.

O caso obrigatório `{wood: 2, stone: 0}`, candidato de `6_000_000 µs`, resulta em `4_999_999 µs`, débito de uma madeira e zero pedra. O backend pausa em `ACTIVE / PAUSED_STARVED`, conserva buffer/consumo e só desbloqueia quando a entrega física permite o próximo microssegundo. Reservar ou complementar estoque não equivale a entregar material.

Sem construtor após progresso iniciado, o backend usa `PAUSED_NO_WORKERS`, preservando prioridade de `PAUSED_STARVED` enquanto faltar material. Em 100% de trabalho e consumo, prepara apenas `SiteState.COMPLETING`; mantém o canteiro existente e não cria edifício.

## Testes e evidências

Comandos executados neste worktree, na Godot 4.7.2:

| Verificação | Resultado |
|---|---|
| `./tools/run_tests.ps1 -Filter test_t3_4_2` | 11/11 testes, 829 asserções, zero falhas/erros de suíte |
| `./tools/run_tests.ps1 -Segmented` | 36/36 suítes, 253/253 testes, 8.710 asserções, zero falhas/erros de suíte |
| Cobertura segmentada | 7 lotes aprovados; `Discovered=36`, `ExecutedUnique=36`, `Duplicates=0`, `Missing=0` |
| Regressão T3.4.1 | 8/8 testes, 299 asserções, contabilidade/complementação preservadas |
| Regressões T3.1–T3.3 | Reservas 17/17 (432); posicionamento unitário 7/7 (134), integração 5/5 (111); canteiro 7/7 (164); UX unitário 2/2 (9); logística 11/11 (205); UX integrado 3/3 (55) |
| `git diff --check` | Aprovado, sem erros de whitespace |
| `./tools/validate.ps1` | Importação, `--check-only` em 112 scripts e startup headless da cena principal aprovados; zero erros e zero avisos; exit code 0 |

Os números entre parênteses nas regressões são asserções. Nenhuma suíte anterior foi modificada. O total da suíte `test_t3_4_2` cresceu de `10` para `11` testes (`682 -> 829` asserções, `+147` em `test_11`). Reconciliação sobre a execução anterior de `T3.4.2` (`8.565` asserções): `8.565 + 147 + 1 - 3 = 8.710`, com `tests/integration/test_t2_natural_source_states.gd` em `103` (`+1` vs. `102`) e `tests/integration/test_t2_worker_cycle.gd` em `2.656` (`-3` vs. `2.659`), variação residual esperada por quadro de física. O log segmentado não contém linhas `ERROR`, `SCRIPT ERROR` ou `WARNING`.

Contagem exata de sinais em `test_11_no_redundant_signals_in_paused_starved_and_legitimate_resume`:
- Ciclos `1..20` até `4_999_999 µs` (`{wood: 2, stone: 0}`, consumo `{wood: 1, stone: 0}`, transição para `PAUSED_STARVED`): `20` `buffer_changed` e `20` `state_changed`.
- `4` chamadas válidas subsequentes em frames distintos já em `PAUSED_STARVED`: antes da correção emitiriam `+4` `buffer_changed` e `+4` `state_changed`; após a correção emitem **`0` `buffer_changed` e `0` `state_changed`** (`20 -> 20`).
- Transição direta com `advanced_usec == 0` para `PAUSED_STARVED` (`2_499_999 µs`, buffer `0`): **`0` `buffer_changed` e `1` `state_changed`**; chamada repetida subsequente: **`0` `buffer_changed` e `0` `state_changed`**.
- Entrega física de `1` pedra (`_deliver`): `+1` `buffer_changed` (`21`) e `+2` `state_changed` (`22`, de `record_withdrawn_for_site` + `accept_delivery_from_carry_load`), desbloqueando para `ASSEMBLING`; retomada `0,000001 s` até `5,0 s`: `22` `buffer_changed` e `23` `state_changed`, mantendo proteção de reentrância, duplicação por frame e contribuição de dois trabalhadores distintos.

Também foi iniciada a cena principal em execução gráfica com `--rendering-driver opengl3 --resolution 1280x720 --max-fps 60 --quit-after 1800`. O log identifica GTX 1060 e não registra erros/avisos. A tentativa de inspeção visual por Computer Use falhou com `foreground window did not report a process id`; por isso, não se registra aprovação visual/manual nem benchmark. A checagem gráfica não executou o fluxo futuro de montagem por ordens.

Os fixtures usam `BackendOrder`, subclasse de `ConstructOrder` exclusiva de teste: instala uma ordem ativa real via `Unit.issue_order()` e registra o trabalhador, mas não executa navegação ou montagem automática. O material entra pelo fluxo real de mochila, reivindicação de trânsito e entrega ao canteiro, em lotes respeitando a capacidade. Os fixtures semeiam os recursos físicos de teste, sem alterar custos oficiais.

Cobertura específica: sete fronteiras exigidas; teto sem pedra; ausência de débito repetido; avaliação pura sem mutação; aborto integral; nove guardas; delta `6.0`, zero, negativo, NaN, infinitos e maior que 0,25; slot oposto; altura inválida; parede entre trabalhador e obra; duplicação e reentrância; dois construtores distintos; limpeza das âncoras; retomada após entrega; conservação em 120 passos até 100%; custos não divisíveis e partição do trabalho.

## Falhas encontradas e corrigidas

- Na expansão do teste de Guarda 6, uma definição com `max_builders = 0` era inválida e corretamente rejeitada antes pela Guarda 1. O fixture passou a usar definição válida com um slot e trabalhador no índice 1. Nenhuma guarda de produção foi enfraquecida.
- A revisão do diff detectou recodificação involuntária de duas etiquetas portuguesas durante leitura por encoding padrão do Windows. O texto original foi restaurado e os arquivos escritos explicitamente em UTF-8/LF.
- A revisão do ciclo de vida incluiu a remoção de âncoras também quando ordens inativas são eliminadas pelo pruning.

## Limites e pendências

- **Âncoras dos construtores (`§4`):** `assign_builder_slot_position()`, `is_unit_at_assigned_builder_slot()` e as guardas de `contribute_work()` atendem integralmente às verificações de backend pertinentes à `T3.4.2`. A chamada de integração pela ordem jogável (`ConstructOrder`) com a posição resolvida pelo `BuildSlotPlanner` está reservada à `T3.4.3` (dependência incremental prevista, não defeito).
- Não implementados: T34-AUT-09 Parte B, promoções/fases novas de `ConstructOrder`, `WAITING_FOR_MATERIALS`, integração reativa de ordens, `BuildingInstance`, transação de conclusão, rebake/barreiras, UI, cancelamento/reembolso ou depósitos funcionais.
- Testes de backend não constituem homologação visual ou manual da montagem. Essa interação só poderá ser avaliada após a integração autorizada da T3.4.3; a cena atual mantém as ordens T3.3.
- O próximo incremento depende de auditoria independente desta candidata e revisão do proprietário. Nenhuma autorização para T3.4.3–T3.4.5 é inferida.

**T3.4.2 IMPLEMENTADA COMO CANDIDATA. AINDA NÃO AUDITADA NEM HOMOLOGADA. SEM MERGE. T3.4.3–T3.4.5 BLOQUEADAS.**
