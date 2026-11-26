# Dawn of Kin — Relatório de Entrega da Candidata Documental `R-03B B0`
## Planejamento Arquitetural da Casa Fundadora e `ControlMode`

> **Status Obrigatório:** **`CANDIDATA DOCUMENTAL AGUARDANDO AUDITORIA INDEPENDENTE`** · **`B0 NÃO HOMOLOGADO`** · **`R-03B NÃO IMPLEMENTADA`** · **`B1 NÃO AUTORIZADA`**
>
> **Data:** `26/11/2026`
>
> **Nota de Transparência:** Este relatório registra exclusivamente a execução da etapa de planejamento arquitetural (`B0`). **Não representa resultados de testes executáveis de uma implementação inexistente.**

---

## 1. Escopo Executado

Foi realizada a auditoria documental, arquitetural e de código real da base homologada pós-`R-03A` (`develop @ 94c718024359dc7ff8360949313969b3ceaf9776`), produzindo o plano arquitetural completo em [R_03B_B0_founding_house_control_mode_PLAN.md](../architecture/R_03B_B0_founding_house_control_mode_PLAN.md) (33 seções) e este relatório de entrega, sob isolamento documental em worktree dedicado (`C:\Projetos\Dawn_of_Kin_wt_r_03b`, branch `feat/r-03b-founding-house-control-mode`).

---

## 2. Documentos Consultados

### Normativos
- `AGENTS.md`
- `docs/Dawn_of_Kin_GDD.md` (`v1.3` integral, §§1–12)
- `docs/ROADMAP_MESTRE.md` (integral, §§1–6)
- `docs/KNOWN_ISSUES.md` (§§1–6)
- `README.md`
- `docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` (`D2.2`, Cláusula Pétrea)

### Arquiteturais e Auditorias
- `docs/architecture/RUX_0_autonomous_work_family_PROPOSAL.md` (com Adendo de Reconciliação `R-02A R1`)
- `docs/architecture/R_03A_D0_community_work_experience_revision_PLAN.md`
- `docs/architecture/R_03A_COMMUNITY_WORK_CLOSEOUT_REPORT.md`
- `docs/audits/DAWN_OF_KIN_GLOBAL_VISION_AUDIT_PROPOSAL.md`

### Relatórios Técnicos e Evidências Históricas
- `docs/testing/R_03A_D1_R3_shift_consistency_candidate_report.md`
- `docs/testing/R_03A_D2_R1_adversarial_cancellation_candidate_report.md`
- `docs/testing/R_03A_D3_1_R1_tree_cut_authorization_lifecycle_candidate_report.md`
- `docs/testing/R_03A_D3_2_tree_gather_orders_candidate_report.md`
- `docs/testing/R_03A_D3_3_R1_adversarial_conservation_audit_candidate_report.md`
- `docs/testing/R_03A_D3_4_integral_validation_candidate_report.md`
- `docs/testing/R_03A_D4_R1_visual_and_performance_candidate_report.md`
- `docs/testing/R_03A_D4_R2_algorithmic_equivalence_candidate_report.md`
- `docs/testing/R_03A_D4_final_manual_test_protocol.md`
- Logs históricos comparados (somente leitura) para `CLOSEOUT-DOC-02`: `evidencias/R-03A/D4/D4-R2/07_full_validation/full_regression.log` × `evidencias/R-03A/CLOSEOUT/05_post_integration_validation/segmented_post_integration.log`

---

## 3. Arquivos de Código, Cenas, Dados e Testes Inspecionados

### Produção e Dados
- `data/characters/leader_a.tres`, `data/characters/leader_b.tres`
- `src/units/character_definition.gd`, `src/units/unit.gd`, `src/units/unit_movement.gd`, `src/units/temporary_test_workers_controller.gd`, `src/units/cancellation_recovery_dispatcher.gd`
- `src/units/orders/unit_order.gd`, `move_order.gd`, `gather_resource_order.gd`, `deliver_to_camp_order.gd`, `construct_order.gd`, `recovery_order.gd`
- `src/rts/command_controller.gd`, `community_task_dispatcher.gd`, `community_work_board.gd`, `work_task.gd`, `selection_manager.gd`, `rts_input_controller.gd`, `autonomous_gather_input.gd`
- `src/economy/unit_carry_load.gd`, `resource_source.gd`, `economy_clock_controller.gd`, `reserved_withdrawal_coordinator.gd`
- `src/main/main.gd`, `src/main/main.tscn`
- `src/ui/selected_unit_panel.gd`, `src/ui/hud_formatter.gd`, `src/ui/d2/d2_simulation_pause_controller.gd`, `src/ui/d2/components/d2_founder_steles_view.gd`, `src/ui/d2/components/d2_lineage_blade_view.gd`

### Testes Inspecionados (Somente Leitura)
- `tests/unit/test_selection_manager.gd`
- `tests/integration/test_commands.gd`
- `tests/integration/test_r_03a_community_work_main_scene.gd`
- `tests/integration/test_r_03a_d2_r1_adversarial_cancellation.gd`
- `tests/integration/test_r_03a_d3_2_tree_gather_orders.gd`
- `tests/integration/test_r_03a_d4_r2_algorithmic_equivalence.gd`
- `tests/integration/test_t2_worker_cycle.gd`
- `tests/integration/test_t3_3_ux_flow.gd`
- `tests/integration/test_ui_1_1b_hitboxes_and_pause.gd`
- `tests/integration/test_ui_1_2_selection_and_lineage.gd`
- Varredura de referências em `tests/` (identificando 5 arquivos com `CharacterDefinition.new()`, 5 arquivos usando `Worker3`/`Worker4` com `CommandController` e 43 arquivos chamando `Unit.issue_order()` diretamente).

---

## 4. Descobertas Relevantes

1. **Ausência de origem de ordem em `Unit` e `UnitOrder`:** atualmente nem `Unit` nem `UnitOrder` registram `PERSONAL` vs `COMMUNITY` vs `SYSTEM_RECOVERY`; `CommunityTaskDispatcher` infere propriedade externamente em `WorkTask` e reutiliza `CommandController.command_units_to_gather()`, que precisará separar o caminho comunitário do pessoal para impedir que moradores comuns recebam ordens pessoais e impedir bloqueio indevido no despacho comunitário.
2. **Janela síncrona crítica em `Unit.issue_order()` (`src/units/unit.gd:250–275`):** ao substituir uma ordem comunitária, `previous_order.cancel()` e `order_finished.emit()` executam antes de `order.start()`. O plano exige comprometer `ControlMode = PERSONAL_ACTIVE` na `issued_revision` **antes** do cancelamento da ordem anterior (com rollback limpo se `start()` falhar), eliminando qualquer janela de sequestro comunitário.
3. **Impacto real de `TemporaryTestWorkersController` (`Worker3`/`Worker4`):** 5 suítes legadas (`test_t3_3_ux_flow.gd`, `test_t3_3_construction_logistics.gd`, `test_t3_6_2_c3_5_gather_order_integration.gd`, `test_t3_6_2_c4_12_rts_provenance.gd`, `tests/visual/t3_3_ux_repro.gd`) comandam `Worker3`/`Worker4` diretamente via `CommandController`, originando a deliberação explícita **`B0-Q03`**.
4. **Acoplamento nominal isolado em `D2FounderStelesView`:** apenas `src/ui/d2/components/d2_founder_steles_view.gd:22–23,651–669` referencia `leader_a`/`leader_b` no diretório `src/`.
5. **Explicação forense de `CLOSEOUT-DOC-02` (`34.026 → 34.029`):** comprovado nos logs históricos que toda a diferença de `+3` asserções ocorreu em laços `while` por quadro de física em `tests/integration/test_t2_worker_cycle.gd` (`test_01` `+1`, `test_08` `+2`), sem alteração executável.
6. **Erratas `CLOSEOUT-DOC-01` e `CLOSEOUT-DOC-03`:** registradas transparentemente na Seção 31 do plano (`Discovered=95 == ExecutedUnique=95` para 95 suítes / 724 testes; `D2-P01` é cancelamento em lote de 6 árvores mantendo pedra/alimento ativos).

---

## 5. Arquitetura Recomendada

- **Metadados mínimos em `CharacterDefinition`:** `HouseAffiliation { COMMUNITY, FOUNDING_HOUSE }` (default `COMMUNITY`), `FoundingHouseOrigin { NONE, ORIGINAL_FOUNDER, DIRECT_DESCENDANT, EXTERNAL_SPOUSE }` (default `NONE`) e `AgeStage { BABY, CHILD, YOUTH, ADULT }` (default `ADULT`), com validação cruzada em `is_valid()` e separação estrita entre pertencimento (`D-04`) e proteção contra morte (`DEC-07`, exclusiva de `ORIGINAL_FOUNDER`).
- **Autoridade de permissões centralizada (`UnitControlPermissions`, `RefCounted` puro):** separa seleção visual, inspeção, comando pessoal por modalidade, trabalho comunitário por `WorkTask.Kind` e gancho futuro de equipe manual (`R-03C`).
- **Fonte única do `ControlMode` (`Unit` + `UnitControlState`, `RefCounted`):** 4 estados (`COMMUNITY_FREE`, `COMMUNITY_WORKING`, `PERSONAL_ACTIVE`, `PERSONAL_POST_MOVE_WAIT`), sem `PERSONAL_HOLD` permanente, protegidos por `_order_revision` e `_wait_token_id` monotônicos e 3 origens explícitas (`COMMUNITY`, `PERSONAL`, `SYSTEM_RECOVERY`).
- **Temporização pausável `D-05`:** `Timer` one-shot criado de forma lazy na própria `Unit` (`PROCESS_MODE_PAUSABLE`, `ignore_time_scale = false`), zero polling, custo zero em moradores comuns, compatível com `D2SimulationPauseController` e coalescido no `CommunityTaskDispatcher` via `_flush_queued`.

---

## 6. Alternativas Rejeitadas e Justificativas

- **Rejeitada:** `PERSONAL_HOLD` permanente da `RUX-0` com botão manual `"Liberar para comunidade"` — contradiz diretamente `D-05` (retorno automático configurável).
- **Rejeitada:** Dicionário central de `ControlMode` no `CommunityTaskDispatcher` — cria estado duplicado, quebra isolamento de testes unitários de `Unit` e falha quando não há dispatcher.
- **Rejeitada:** Polling por frame em `_physics_process` para contagem regressiva `D-05` — viola `§19` e desperdiça CPU por unidade ociosa na Intel UHD 620.
- **Rejeitada:** `Timer` eagerly instanciado em `unit.tscn` para todo habitante — adiciona nós desnecessários para centenas de moradores comuns que nunca entram em `PERSONAL_POST_MOVE_WAIT`.
- **Rejeitada:** Autoload global de controle/tempo — proibido pelas diretrizes do projeto (`MainScene` sem autoloads).
- **Rejeitada:** Consolidar `B2+B3` em um único incremento — mistura risco crítico de reentrância de autoridade de ordens (`B2`) com temporização/pausa/calibração `D-05` (`B3`).

---

## 7. Decisões Abertas Encaminhadas ao Proprietário

Documentadas em detalhe (10 campos cada) na Seção 30 do plano:
- **`B0-Q01`:** Seleção visual e inspeção somente leitura de moradores comuns (`COMMUNITY`).
- **`B0-Q02`:** Comportamento em seleção mista (Fundador + Morador comum).
- **`B0-Q03`:** Classificação de `Worker3`/`Worker4` (`TemporaryTestWorkersController`) na `MainScene` durante `P-REC-1`.
- **`B0-Q04`:** Comportamento de `D-05` em `MoveOrder` que termina por falha de navegação ou cancelamento.
- **`B0-Q05`:** Elegibilidade da mesma tarefa comunitária interrompida (`excluded_unit_ids`) após expirar `D-05`.
- **`B0-Q06`:** Faixa experimental de calibração de `D-05` e confirmação de congelamento sob pausa.
- **`B0-Q07`:** Indicação visual mínima de `ControlMode` na HUD transitória (`use_d2_2_hud = false`).

---

## 8. Divisão Recomendada da Implementação

Mantida a divisão em 5 incrementos sequenciais com parada obrigatória para auditoria em cada um:
- **`B0`** (atual): Planejamento arquitetural.
- **`B1`**: Metadados mínimos da Casa Fundadora, `AgeStage` (`DEC-04`) e `UnitControlPermissions`.
- **`B2`**: `UnitControlState` (`ControlMode`), `OrderOrigin`, commit atômico em `Unit`/`CommandController`/`Dispatcher` e preservação `D2`/`D3`/`D0-A04`/`P-REC-1`.
- **`B3`**: `PERSONAL_POST_MOVE_WAIT`, temporizador lazy pausável `D-05`, reconciliação `HD3-06` e indicação transitória mínima.
- **`B4`**: Integração final na `MainScene`, regressão integral (`95+` suítes), benchmarks CA UHD 620 (`<= 16,7 ms`) e protocolo humano `HB-01`–`HB-08`.

---

## 9. Riscos Principais

- Reentrância síncrona em `Unit.issue_order()` entre cancelamento da ordem comunitária e início da ordem pessoal (`R-B0-01`).
- Compatibilidade com as 5 suítes históricas que comandam `Worker3`/`Worker4` (`R-B0-02`) e 43 suítes que chamam `Unit.issue_order()` diretamente (`R-B0-03`).
- Timers ou callbacks obsoletos corrompendo ordens pessoais subsequentes (`R-B0-04`).
- Falso `BLOCKED_REAUTHORIZATION` em tarefas aguardando término de `PERSONAL_POST_MOVE_WAIT` (`R-B0-05`).
- Interferência sobre locks transacionais econômicos (`R-B0-06`).

---

## 10. Confirmação de Ausência de Alterações Executáveis e Integridade Git

- **Arquivos criados/modificados na candidata:** exclusivamente os 2 documentos Markdown autorizados:
  1. `docs/architecture/R_03B_B0_founding_house_control_mode_PLAN.md`
  2. `docs/testing/R_03B_B0_architectural_planning_candidate_report.md`
- **Zero alterações** em `src/`, `tests/`, `data/`, `levels/`, `assets/`, `tools/`, `project.godot`, `AGENTS.md`, `docs/Dawn_of_Kin_GDD.md`, `docs/ROADMAP_MESTRE.md`, `README.md`, `docs/KNOWN_ISSUES.md` ou relatórios históricos.
- **Integridade Git:** branch `feat/r-03b-founding-house-control-mode` derivada de `develop @ 94c718024359dc7ff8360949313969b3ceaf9776`; `develop` intacta em `94c718024359dc7ff8360949313969b3ceaf9776`; `main` intacta em `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`; tags `t1-complete`, `t2-complete`, `t3-3-complete` preservadas; `C:\Projetos\Dawn of Kin\project.godot` preservado byte a byte (`SHA-256 = AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`).
- **Verificações documentais da entrega:** existência de todos os arquivos e símbolos citados, conformidade estrutural das 33 seções do plano, ausência de diff executável (`NON_DOC_DIFF_COUNT=0`), validação de whitespace/higiene (`git diff --cached --check`) antes do commit e geração/verificação do manifesto externo `MANIFEST_SHA256.txt` em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B0\` na publicação final da candidata.

---

## 11. Limitações da Análise

- Conforme autorizado para `B0`, nenhum teste automatizado da Godot, benchmark ou teste humano foi executado (os números `95/95`, `724/724`, `34.026`/`34.029` citados referem-se estritamente aos registros históricos homologados da `R-03A`).
- A definição exata da duração do intervalo `D-05` e os 7 pontos `B0-Q01`–`B0-Q07` aguardam deliberação expressa do proprietário.

---

## 12. Estado da Próxima Etapa

- **`R-03B B0`:** candidata documental pronta para **auditoria independente do ChatGPT** (`NÃO HOMOLOGADA`).
- **`R-03B B1` e posteriores:** **`NÃO AUTORIZADAS / BLOQUEADAS`** até auditoria independente, deliberação do proprietário sobre `B0-Q01`–`B0-Q07` e autorização expressa de `B1` em etapa posterior.
