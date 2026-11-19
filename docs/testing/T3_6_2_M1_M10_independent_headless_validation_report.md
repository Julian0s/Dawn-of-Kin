# Dawn of Kin — Auditoria independente headless M1–M10

Base auditada: `cff0de2ef6913179dc59dc80ca6fe6e258f1f434`, branch `feat/t3-6-2-provenance-transactions` de `Julian0s/Dawn-of-Kin`. A ponta da branch no GitHub e o clone limpo coincidiam antes dos testes. O trabalho ocorreu em um clone temporário independente, no Windows, em segundo plano, conforme autorização posterior do proprietário que substituiu a exigência de nuvem. Godot `4.7.2.stable.official.ed1daf0bf`, todos os processos de Godot em modo headless. Nenhum cenário foi executado por automação gráfica ou observado em janela pelo auditor.

Referências verificadas: [AGENTS](../../AGENTS.md), [GDD v1.2](../Dawn_of_Kin_GDD.md) (§4 e §9), relatórios [C3.4.3](T3_6_2_C3_4_3_candidate_report.md) e [C3.5](T3_6_2_C3_5_candidate_report.md), protocolos [M1–M6](T3_6_2_C3_4_3_manual_test_protocol.md) e [M7–M10](T3_6_2_C3_5_manual_test_protocol.md), [harness manual](../../tests/visual/t3_6_2_c3_4_3_manual_harness.gd), suítes e caminhos de produção. Os relatórios históricos serviram como referências de escopo. Os resultados abaixo vêm desta execução.

## Resultado por cenário

`AUTO_PASS` se refere aos contratos técnicos exercitados. `VISUAL_PENDING` se refere às partes do protocolo que dependem de percepção ou uso em janela. `MANUAL_PASS_REPORTED` identifica o relato fornecido pelo proprietário, preservadas as ressalvas.

| Teste | Resultado automatizado | Resultado manual | Ressalvas | Necessita verificação humana? |
|---|---|---|---|---|
| M1 — fluxo legado | AUTO_PASS | VISUAL_PENDING | Cena normal, ordens RTS, logística e montagem exercitadas em headless | Sim, jogabilidade, apresentação e feedback do RTS normal |
| M2 — ativação | AUTO_PASS | MANUAL_PASS_REPORTED (principal) | Caso negativo exercitado nesta auditoria com uma madeira legada | Sem repetição técnica do caso negativo |
| M3 — quatro madeiras | AUTO_PASS | MANUAL_PASS_REPORTED (com ressalvas) | `empty_load` reproduzido em nova ordem sobre mochila vazia. Crédito observado na auditoria, sem reconstruir a sessão anterior | Só se for necessário o aceite visual específico da caminhada, da pilha ou do HUD |
| M4 — interrupção da entrega | AUTO_PASS | VISUAL_PENDING | Substituição pela API de ordem real e conservação verificada | Para aceite da resposta visual ao clique e da mudança de destino |
| M5 — retorno da carga mista | AUTO_PASS | VISUAL_PENDING | Dois deslocamentos reais após a preparação da carga pelo harness | Para aceite da apresentação, seleção e feedback no jogo |
| M6 — suprimento da Obra A | AUTO_PASS | VISUAL_PENDING | Uma volta ao acampamento, três pedras em trânsito e depois no buffer de A | Para aceite da apresentação e do feedback de ordens |
| M7 — coleta opt-in | AUTO_PASS | VISUAL_PENDING | Estados de queda/fim de queda e árvore remanescente exercitados logicamente | Sim, aparência da queda, do deslocamento e atualização visual da pilha/HUD |
| M8 — cancelamento da coleta | AUTO_PASS | VISUAL_PENDING | Cancelamento antes da extração, durante espera de retry e após extração | Para aceite visual do cancelamento por clique e da animação |
| M9 — interrupção do retorno | AUTO_PASS | VISUAL_PENDING | `MoveOrder` substituiu coleta real durante transporte, seguida de nova entrega | Para aceite do clique e da transição visual |
| M10 — coleta com carga mista | AUTO_PASS | VISUAL_PENDING | Capacidade de alimento verificada com carga exata. Caso sem espaço coberto com madeira | Para aceite da apresentação da carga e da entrega |

## Comandos e contagens

Na raiz do clone, com a versão do Godot confirmada:

| Comando | Suítes | Testes aprovados/executados | Asserções | Resultado |
|---|---:|---:|---:|---|
| `pwsh -NoProfile -File .\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` | 12 | 113/113 | 9.203 | Exit 0 |
| C3.4.3, dentro do comando anterior | 1 | 8/8 | 1.187 | Sem falhas |
| C3.5, dentro do mesmo comando | 1 | 6/6 | 964 | Sem falhas |
| `pwsh -NoProfile -File .\tools\run_tests.ps1 -Filter test_m1_m10_independent_headless` | 1 | 8/8 | 1.754 | Exit 0 |
| `pwsh -NoProfile -File .\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | 55 | 409/409 | 23.959 | Exit 0, 13/13 lotes, 0 duplicatas e 0 omissões |
| Reexecução do lote `integration-02` com M8 complementar | 3 | 25/25 | 2.116 | Exit 0 |
| Cobertura final consolidada por suíte | 55 | 410/410 | 23.990 | 0 falhas, 0 bloqueios, 0 diagnósticos Godot |
| `pwsh -NoProfile -File .\tools\validate.ps1` | — | — | — | Exit 0, 149 scripts, 0 erros, 0 avisos, inicialização headless OK |
| `git diff --check` e `git diff --cached --check` | — | — | — | Exit 0 |

O segmentado já estava em andamento quando foi acrescentada a comparação exata do M8. Reexecutei o lote correspondente, com o mesmo runner e as mesmas três suítes. O total consolidado substitui os três registros originais pelos três finais em vez de somar execuções sobrepostas. O número de asserções em verificações por quadro pode variar. A primeira tentativa de desenvolvimento da suíte complementar encontrou uma chamada com assinatura incorreta no próprio teste M2. A chamada foi corrigida e o filtro final executou os oito testes.

A execução inicial de `validate.ps1` conferiu os 148 scripts da base. A execução final incluiu o arquivo complementar e a inicialização da cena normal. O arquivo final também passou em `--headless --check-only` após a adição do caso M8.

Reprodução do lote final, com `$godot` apontando para o executável 4.7.2 e a pasta corrente na raiz do clone:

```powershell
& $godot --headless --path . --script res://tests/framework/test_runner.gd -- '--suites=res://tests/integration/test_m1_m10_independent_headless.gd,res://tests/integration/test_navigation.gd,res://tests/integration/test_picking_selection.gd'
```

## Evidência por cenário

As referências **Complementar**, **C343** e **C35** apontam para a [suíte desta auditoria](../../tests/integration/test_m1_m10_independent_headless.gd), a [integração C3.4.3](../../tests/integration/test_t3_6_2_c3_4_3_order_integration.gd) e a [integração C3.5](../../tests/integration/test_t3_6_2_c3_5_gather_order_integration.gd). A primeira foi executada no filtro dedicado e as outras duas no filtro `test_t3_6_2`.

- **M1** — A regressão segmentada cobre [`test_02_playable_right_click_wood_cycle_and_no_premature_credit`](../../tests/integration/test_t2_playable_economy.gd#L264), [`test_01_full_e2e_shelter_placement_reserve_transport_and_no_t34_progress`](../../tests/integration/test_t3_3_construction_logistics.gd#L133), [`test_02_t34_aut_10_parallel_logistics_starvation_wakeup_and_full_completion`](../../tests/integration/test_t3_4_3_reactive_construction_orders.gd#L280) e [`test_01_individual_right_click_orders_for_each_protagonist_and_marker`](../../tests/integration/test_commands.gd#L129). Asserções verificam ordem por clique sintético, carga transportada, crédito após chegada, reservas e conclusão de obra. A C35 `test_group_a_compatibility_opt_in_default_off_and_strict_isolation` verifica fluxo legado e isolamento. O [CommandController](../../src/rts/command_controller.gd#L201) emite coleta sem opt-in, assim como [construção](../../src/rts/command_controller.gd#L264).
- **M2** — Complementar `test_m2_loaded_legacy_opt_in_is_economically_inert`, 13 asserções. A ativação recusada preservou o snapshot, 1 madeira legada e peso 2/20. Com a carga retirada no fixture, a ativação funcionou e o ledger ficou sem lotes. Estoque físico idêntico nas duas tentativas.
- **M3** — Complementar `test_m3_harness_repeat_during_and_after_physical_delivery`, 361 asserções. O worker iniciou distante, 4 madeiras e peso 8/20. O teste amostrou o balanço por quadro, manteve o estoque em 12 e o lote íntegro enquanto a ordem ficou ativa. Na notificação do commit observou `[[16, 0]]` (estoque físico, mochila). Houve um único crédito e uma única viagem concluída. A C343 `test_group_b_physical_walk_free_partial_reserved_mixed_and_replay_trips` também repetiu o ID comprometido, obtendo `replayed=true` e `delivered_now=0`.
- **M4** — Complementar `test_m4_four_wood_preserved_after_manual_replacement`, 15 asserções. Observou deslocamento antes de substituir a entrega por `MoveOrder`, conferiu `CANCELLED/replaced`, conclusão do novo movimento, retorno a `IDLE`, estoque 12 e snapshot completo intacto após 180 quadros físicos adicionais. O grupo D da C343 também tentou executar o intento cancelado e recebeu `order_cancelled`, sem crédito tardio.
- **M5** — Complementar `test_m5_exact_harness_mixed_cargo_and_site_b_return`, 30 asserções. Os 3 alimentos entraram no livre após deslocamento, com madeira física/livre, reserva, claim e lote B preservados. Depois de um novo movimento para fora, outra viagem devolveu 2 madeiras à reserva física de B, deixando o estoque livre inalterado e zerando o claim em trânsito e a mochila.
- **M6** — Complementar `test_m6_exact_harness_stone_supply_preserves_site_b`, 292 asserções. A ordem entrou em retorno de carga livre, descarregou 3 alimentos, carregou 3 pedras com buffer de A ainda zerado, e terminou em sucesso com `{stone: 3}` em A. Estoque físico + mochila + buffer foi constante para pedra a cada quadro. Uma única volta para a carga livre. Lote B e claim idênticos no fim.
- **M7** — C35 `test_group_b_real_cycle_slots_weights_felling_and_depletion`, 417 asserções na execução focada. Observou aproximação e slot, contenção do segundo trabalhador, preparação sem extração, queda lógica `FELLING` → `FALLEN` antes do transporte, três lotes identificados e desaceleração com 20/20. Conferiu fonte + mochila + acampamento = 14 madeiras por quadro, nenhum crédito durante a primeira viagem e duas viagens físicas após retomar a fonte.
- **M8** — Complementar `test_m8_replace_before_and_after_first_extraction`, 31 asserções. A primeira substituição por `MoveOrder` ocorreu em preparação, com slot adquirido, árvore em 12 madeiras e mochila vazia. A segunda ocorreu durante a queda, logo depois de extrair 4 madeiras. O mesmo lote `FREE_GATHERED` e o peso 8/20 permaneceram após o movimento e 60 quadros adicionais, com 8 madeiras na árvore, nenhum slot ocupado e estoque zero. A C35 `test_group_e_cancellations_removals_navigation_callbacks_and_guards` (140 asserções no grupo) também recusou explicitamente um intento de extração cancelado durante retentativa.
- **M9** — Complementar `test_m9_replace_real_gather_during_walk_then_deliver_preserved_lots`, 372 asserções. Duas extrações da árvore produziram 10 madeiras a 20/20. Houve movimento de transporte, com zero slots e estoque. `MoveOrder` cancelou a coleta com `replaced`, preservando os dois lotes, origem, peso, quantidade e as 4 unidades ainda na árvore. Nova entrega física creditou 10 uma vez, sem perda ou duplicação. Conferiu a conservação por quadro na entrega.
- **M10** — Complementar `test_m10_food_gather_respects_residual_capacity_and_site_b_claim`, 640 asserções. Com 2 madeiras reservadas e 3 alimentos (7/20), extraiu 13 adicionais até 20/20, iniciou retorno com estoque zero, depois coletou os 2 restantes. Duas viagens, 18 alimentos no livre, descarregando apenas os lotes livres. Conservação de alimento por quadro e reserva/claim/identidade de B preservados. C35 `test_group_c_mixed_cargo_selective_delivery_and_anti_loop` verifica o caso residual de 19/20 que não comporta madeira de peso 2. Sem carga elegível faz zero viagens, com 1 alimento livre faz exatamente uma e encerra com `insufficient_carry_capacity`.

Em M5, M6 e M10 a posição inicial e a carga mista são condições de teste. O harness prepara a reserva B pelo coordenador com o trabalhador posicionado junto à pilha e depois restaura sua posição inicial. Nas etapas verificadas a partir desse ponto, entrega, transporte e coleta efetuam deslocamentos e transações reais. M4, M8 e M9 verificam a substituição por `MoveOrder` pela mesma API de ordens usada pelo jogo. A aparência da queda em M7 permanece visual.

## M3 — explicação de `empty_load`

O [harness](../../tests/visual/t3_6_2_c3_4_3_manual_harness.gd#L154) instancia um novo `DeliverToCampOrder` a cada comando, guarda-o em `last_order` e imprime o status imediatamente. Uma repetição enquanto há carga cancela a ordem anterior com `replaced` e mantém a nova em `RUNNING`. Quando a ordem ativa chega, ela termina em `SUCCEEDED` e esvazia a mochila após o crédito. O comando seguinte com mochila vazia encontra a guarda [em `DeliverToCampOrder.start()`](../../src/units/orders/deliver_to_camp_order.gd#L143), termina imediatamente em `FAILED/empty_load` e não inicia transferência ou viagem. Como `last_order` já foi trocado, o diagnóstico passa a exibir o status da nova ordem.

Recorte observado: status imediatos `1`, `1`, `3 failure=empty_load`. Estados finais por instância: `4/CANCELLED` (primeira), `2/SUCCEEDED` (segunda), `3/FAILED` (mochila vazia). Evento econômico único `[[16, 0]]`. A reprodução é compatível com o relato, cuja sequência temporal original não foi registrada integralmente. Nenhum defeito econômico foi reproduzido nesse caminho.

## Reentrância e limites

As suítes C343 `test_group_e_busy_retries_uncertain_outcome_replay_two_orders_reentrancy_and_cancel_lock` e `test_group_f_global_conservation_invariants_across_mixed_cycles_and_failures`, e C35 `test_group_d_idempotency_busy_retries_uncertain_outcome_depleted_replay_and_conflicts` e `test_group_f_conservation_invariants_observer_atomicity_and_guard_cleanup`, passaram no filtro T3.6.2. Exercitaram estados `busy`, replay, guardas, tentativas durante sinais e conservação observável. A regressão inclui os testes de rollback pré-commit de C2/C3.2/C3.4.2. `DEC-T3.6-SIGNALS-01` mantém o status pendente.

A cobertura técnica dispensa repetir manualmente a contabilidade dos cenários, salvo se o aceite exigir confirmação visual. Para uma rodada visual curta, M1 cobre controle do jogo normal e M7 cobre a aparência da queda, o percurso e o HUD. Os demais itens ainda mantêm o estado manual individual acima. Não houve verificação de desempenho em janela nem homologação.

Escopo versionado: a suíte complementar em `tests/integration/` (commit `0a353516d192e5883ca12733751d6721b324aae8`) e este relatório. O código de produção, o GDD, a arquitetura e os protocolos preexistentes ficam fora do diff. `main` de referência: `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`.
