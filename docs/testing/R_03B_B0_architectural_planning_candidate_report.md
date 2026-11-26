# Dawn of Kin — Relatório de Entrega da Candidata Documental `R-03B B0` (Revisada por `B0-R1`)
## Planejamento Arquitetural da Casa Fundadora e `ControlMode`

> **Status Obrigatório:** **`CANDIDATA DOCUMENTAL ORIGINAL (e502490) REVISADA POR B0-R1 — AGUARDANDO AUDITORIA INDEPENDENTE`** · **`B0-R1 NÃO HOMOLOGADO`** · **`R-03B NÃO IMPLEMENTADA`** · **`B1–B4 BLOQUEADAS`**
>
> **Data:** `26/11/2026`
>
> **Rastreabilidade de Revisão:** Este relatório preserva a rastreabilidade da candidata original `B0` publicada no SHA `e5024909fbb17cd5266d30e0452e92cc095d5923` e foi atualizado em `B0-R1` para incorporar as sete decisões definitivas do proprietário (`B0-Q01`–`B0-Q07`) e corrigir integralmente os cinco achados da auditoria independente (`B0-A01`–`B0-A05`). O detalhamento focal da revisão encontra-se em [R_03B_B0_R1_architectural_reconciliation_candidate_report.md](R_03B_B0_R1_architectural_reconciliation_candidate_report.md).
>
> **Nota de Transparência:** Este relatório registra exclusivamente a etapa de planejamento e reconciliação arquitetural (`B0` / `B0-R1`). **Não representa resultados de testes executáveis de uma implementação inexistente.**

---

## 1. Escopo Executado

Foi realizada a auditoria documental, arquitetural e de código real da base homologada pós-`R-03A` (`develop @ 94c718024359dc7ff8360949313969b3ceaf9776`), produzindo originalmente a candidata `B0` (`e5024909fbb17cd5266d30e0452e92cc095d5923`) e, subsequentemente, a revisão documental **`B0-R1`** em [R_03B_B0_founding_house_control_mode_PLAN.md](../architecture/R_03B_B0_founding_house_control_mode_PLAN.md) (33 seções reconciliadas), neste relatório atualizado e no relatório focal [R_03B_B0_R1_architectural_reconciliation_candidate_report.md](R_03B_B0_R1_architectural_reconciliation_candidate_report.md), sob isolamento documental no worktree `C:\Projetos\Dawn_of_Kin_wt_r_03b` (branch `feat/r-03b-founding-house-control-mode`).

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
- `tests/framework/regional_conservation_audit.gd`
- `tests/unit/test_selection_manager.gd`
- `tests/integration/test_commands.gd`, `test_r_03a_community_work_main_scene.gd`, `test_r_03a_d1_selection_and_authorization.gd`, `test_r_03a_d2_selective_work_cancellation.gd`, `test_r_03a_d2_r1_adversarial_cancellation.gd`, `test_r_03a_d3_2_tree_gather_orders.gd`, `test_r_03a_d4_r2_algorithmic_equivalence.gd`, `test_rux_2a_auto_resources.gd`, `test_rux_2b_multi_source_selection.gd`, `test_t2_worker_cycle.gd`, `test_t3_3_ux_flow.gd`, `test_t3_3_construction_logistics.gd`, `test_t3_6_2_c3_5_gather_order_integration.gd`, `test_t3_6_2_c4_12_rts_provenance.gd`, `test_ui_1_1b_hitboxes_and_pause.gd`, `test_ui_1_2_selection_and_lineage.gd`
- `tests/visual/t3_3_ux_repro.gd`
- Varredura integral de `src/` (exatamente 4 chamadas de `issue_order` e 2 de `cancel_current_order`) e de `tests/` (`43` arquivos com chamadas `unit.issue_order()`, `36` operando sobre `LeaderA`/`LeaderB`, `3` usando `CharacterDefinition.new()`, `4` envolvendo `Worker3`/`Worker4` e `0` chamando `issue_order(RecoveryOrder)` ou `issue_order(null)` diretamente).

---

## 4. Descobertas Relevantes (Incluindo Achados Reconciliados em `B0-R1`)

1. **Barreira de autoridade e entradas de ordens (`B0-A02`):** em `src/`, há exatamente 4 chamadas de `issue_order()` (`command_controller.gd:174,273,359` e `cancellation_recovery_dispatcher.gd:111`). Para impedir qualquer contorno via chamada direta a `Unit` ou falsificação de origem, a validação `UnitControlPermissions` passa a ser obrigatória **no ponto final de instalação em `Unit`**, com entradas explícitas separadas (`issue_personal_order`/`issue_order`, `issue_community_order`, `issue_recovery_order`) e **zero bypass genérico**.
2. **Recuperação econômica durante construção legada (`B0-A03`):** `CancellationRecoveryDispatcher._assign()` (`src/units/cancellation_recovery_dispatcher.gd:85–122`) admite legitimamente substituir uma `ConstructOrder` ativa associada ao mesmo `record.site_id` quando `site.get_site_state() == SiteState.CANCELLED`. A máquina de estados agora representa explicitamente essa transição **`T1b`** (e `T1c` para recuperação explícita em espera), mantendo `entry.manual` e protegendo todas as ordens pessoais ativas.
3. **Reentrância e atomicidade das transições (`B0-A04`):** `Unit.issue_order()` (`src/units/unit.gd:247–288`) possui fronteiras síncronas em `previous_order.cancel()`, `order_finished.emit()`, `order.start()` e `_set_state()`. O plano reconciliado especifica protocolo atômico de 4 estágios (reserva interna silenciosa + guarda de `cancel()` bloqueado por lock + publicação única de `control_mode_changed` após estabilização + revalidação `_order_revision == issued_revision` em toda fronteira), cobrindo 11 casos de borda sem prometer rollback irreal de ordem já encerrada.
4. **Permissões etárias das crianças (`B0-A01`):** corrigida a contradição presente no resumo da candidata original `B0`: `BABY` não é selecionável nem comandável; **`CHILD` pode realizar atividades leves e seguras (ex.: coleta de frutos) e, quando membro da Casa Fundadora, pode receber ordens pessoais compatíveis com essas restrições** (`MOVE`, `GATHER_FOOD`, `DELIVER_TO_CAMP`), mantendo proibidos corte de árvores, mineração, construção pesada e combate (`GDD v1.3` §§3.3–3.4, `DEC-04`).
5. **Interface discreta sem cronômetro regressivo (`B0-A05` / `B0-Q07 A`):** removida qualquer menção a contagem regressiva ou atualização contínua na HUD. O `Timer` controla apenas a lógica interna; a HUD exibe somente rótulos discretos orientados a eventos (`Trabalho comunitário`, `Ordem pessoal`, `Aguardando retorno`, `Morador — somente leitura`) e feedback breve de rejeição.
6. **Impacto real das decisões `B0-Q03 B` e `B0-Q05 B` sobre testes históricos:** inventariado com distinção entre suítes automatizadas e ferramenta visual (`tests/visual/t3_3_ux_repro.gd`), confirmando que `test_t3_6_2_c4_12_rts_provenance.gd` e `test_r_03a_d3_2_tree_gather_orders.gd` (`test_i07`) permanecem 100% preservados sem alteração, enquanto os testes afetados por `Q03 B` (em `B1`) e `Q05 B` (em `B3`) têm estratégia rastreável sem enfraquecimento de asserções.
7. **Ressalvas `CLOSEOUT-DOC-01`/`02`/`03` preservadas:** explicação forense da diferença de `+3` asserções (`34.026 → 34.029` em laços `while` de `tests/integration/test_t2_worker_cycle.gd`) mantida intacta na Seção 31 do plano.

---

## 5. Arquitetura Reconciliada

- **Metadados mínimos em `CharacterDefinition`:** `HouseAffiliation { COMMUNITY, FOUNDING_HOUSE }` (default `COMMUNITY`), `FoundingHouseOrigin { NONE, ORIGINAL_FOUNDER, DIRECT_DESCENDANT, EXTERNAL_SPOUSE }` (default `NONE`) e `AgeStage { BABY, CHILD, YOUTH, ADULT }` (default `ADULT`), com validação cruzada em `is_valid()` e `Worker3`/`Worker4` classificados como `COMMUNITY`/`NONE`/`ADULT` (`B0-Q03 B`).
- **Barreira dupla de permissões (`UnitControlPermissions` em `SelectionManager`, `CommandController`, `CommunityTaskDispatcher` e `Unit`):** separa seleção visual (`B0-Q01 A`), inspeção somente leitura, filtragem pré-planejamento em seleção mista (`B0-Q02 A`), controle pessoal por modalidade e idade (`B0-A01`), trabalho comunitário por `WorkTask.Kind` e gancho futuro `R-03C`, com entradas explícitas `issue_personal_order`/`issue_order`, `issue_community_order` e `issue_recovery_order` (`B0-A02`).
- **`ControlMode` + `OrderOrigin` na `Unit` (`UnitControlState`, `RefCounted`):** 4 estados (`COMMUNITY_FREE`, `COMMUNITY_WORKING`, `PERSONAL_ACTIVE`, `PERSONAL_POST_MOVE_WAIT`) combinados a `active_origin` (`NONE`, `COMMUNITY`, `PERSONAL`, `SYSTEM_RECOVERY`), incluindo transição legítima `T1b` (`B0-A03`) e protocolo atômico de 4 estágios contra reentrância (`B0-A04`).
- **Temporização pausável `D-05` e retorno à mesma tarefa (`B0-Q04 A`, `B0-Q05 B`, `B0-Q06 A`):** `Timer` one-shot lazy com **conexão única** na `Unit` (`PROCESS_MODE_PAUSABLE`, `ignore_time_scale = false`), disparado exclusivamente após `MoveOrder` pessoal `SUCCEEDED`, permitindo retorno inclusive à mesma tarefa ainda em `PENDING_WORKERS` (sem jamais reativar `CANCELLED` ou desbloquear `BLOCKED_REAUTHORIZATION`), com calibração experimental `3 s / 8 s / 15 s` em `B4`.
- **Interface transitória mínima (`B0-Q07 A` / `B0-A05`):** rótulos discretos orientados a eventos no `SelectedUnitPanel`/`HudFormatter` e feedback breve em `AutonomousGatherFeedback`, sem cronômetro regressivo, sem polling e mantendo `use_d2_2_hud = false`.

---

## 6. Alternativas Rejeitadas e Justificativas

- **Rejeitada:** `PERSONAL_HOLD` permanente da `RUX-0` com botão manual — substituída por `D-05`.
- **Rejeitada:** Concentrar permissões apenas em `CommandController` deixando `Unit.issue_order()` desprotegido ou com flag de bypass genérico — rejeitada por `B0-A02`.
- **Rejeitada:** Publicar `control_mode_changed` antes de concluir `previous_order.cancel()`/`order.start()` ou prometer rollback de ordem comunitária já encerrada — rejeitada por `B0-A04`.
- **Rejeitada:** Criar um 5º estado artificial em `ControlMode` para `SYSTEM_RECOVERY` — 4 estados + `OrderOrigin` cobrem `T1a`/`T1b`/`T1c` sem inflar a máquina (`B0-A03`).
- **Rejeitada:** Cronômetro regressivo ou atualização contínua na HUD — explicitamente rejeitada por `B0-Q07 A` e `B0-A05`.
- **Rejeitada:** Polling por frame em `_physics_process`, `Timer` eagerly instanciado em todo morador ou autoload global.

---

## 7. Decisões do Proprietário (Encerradas em `26/11/2026`) e Pendência Remanescente

As sete decisões **`B0-Q01`–`B0-Q07`** foram formalmente aprovadas pelo proprietário em `26/11/2026` (sem observações adicionais) e incorporadas transversalmente ao plano:
- `B0-Q01 = Alt. A` · `B0-Q02 = Alt. A` · **`B0-Q03 = Alt. B`** · `B0-Q04 = Alt. A` · **`B0-Q05 = Alt. B`** · `B0-Q06 = Alt. A` · `B0-Q07 = Alt. A`.

**Única definição de produto legitimamente em aberto (por força da própria `B0-Q06 A`):**
- Escolha da duração padrão definitiva de `D-05` após a calibração experimental de `3 s`, `8 s` e `15 s` no aceite humano futuro (`B4`).

---

## 8. Divisão Recomendada da Implementação (`B0`–`B4` Reconciliada)

Mantidos 5 incrementos sequenciais com ajuste de sequenciamento em `B1` para evitar qualquer estado intermediário inválido:
- **`B0` / `B0-R1`** (atual): Planejamento e reconciliação arquitetural.
- **`B1`**: Metadados mínimos, `UnitControlPermissions` (`B0-A01`), `OrderOrigin` + entradas explícitas separadas (`issue_personal_order`/`issue_order`, `issue_community_order`, `issue_recovery_order` — `B0-A02`), separação de `dispatch_community_gather()`, filtro de seleção mista (`B0-Q02 A`), `SelectionManager` (`B0-Q01 A`), `Worker3`/`Worker4` = `COMMUNITY` (`B0-Q03 B`) + reconciliação dos testes `Q03 B` no mesmo incremento.
- **`B2`**: `UnitControlState` (`COMMUNITY_FREE`, `COMMUNITY_WORKING`, `PERSONAL_ACTIVE`), protocolo atômico de 4 estágios (`B0-A04`), transição legítima `T1b` de recuperação (`B0-A03`) e conservação `D0-A04`.
- **`B3`**: `PERSONAL_POST_MOVE_WAIT`, `Timer` lazy pausável com conexão única (`B0-Q06 A`), gatilho `MoveOrder` `SUCCEEDED` (`B0-Q04 A`), retorno à mesma tarefa + classificação de 4 categorias em `_evaluate_unassigned_task()` + reconciliação dos testes `Q05 B`, e rótulos discretos sem cronômetro regressivo (`B0-Q07 A` / `B0-A05`).
- **`B4`**: Integração final na `MainScene`, regressão integral (`95+` suítes), benchmarks CA UHD 620 (`<= 16,7 ms`), calibração `3 s`/`8 s`/`15 s` e protocolo humano `HB-01`–`HB-08`.

---

## 9. Riscos Principais

- Reentrância síncrona em `Unit.issue_order()` e `control_mode_changed` (`R-B0-01`, mitigado por `B0-A04`).
- Contorno de permissões ou falsificação de origem (`R-B0-02`, mitigado por `B0-A02`).
- Quebra de recuperação automática de `ConstructOrder` cancelada (`R-B0-03`, mitigado por `B0-A03`).
- Regressão em testes legados `Q03 B` e `Q05 B` (`R-B0-04`, mitigado por reconciliação rastreável em `B1` e `B3`).
- Callbacks obsoletos ou conexões acumuladas no `Timer` `D-05` (`R-B0-05`, mitigado por conexão única + `(token, rev)`).
- Falso `BLOCKED_REAUTHORIZATION` ou desbloqueio indevido (`R-B0-06`, mitigado por classificação de 4 categorias em `_evaluate_unassigned_task()`).

---

## 10. Confirmação de Ausência de Alterações Executáveis e Integridade Git

- **Arquivos criados/modificados na cadeia documental (`develop @ 94c7180` → `B0-R1`):** exclusivamente os 3 documentos Markdown autorizados:
  1. `docs/architecture/R_03B_B0_founding_house_control_mode_PLAN.md`
  2. `docs/testing/R_03B_B0_architectural_planning_candidate_report.md`
  3. `docs/testing/R_03B_B0_R1_architectural_reconciliation_candidate_report.md`
- **Zero alterações** em `src/`, `tests/`, `data/`, `levels/`, `assets/`, `tools/`, `project.godot`, `AGENTS.md`, `docs/Dawn_of_Kin_GDD.md`, `docs/ROADMAP_MESTRE.md`, `README.md`, `docs/KNOWN_ISSUES.md` ou relatórios históricos da `R-03A`.
- **Integridade Git:** branch `feat/r-03b-founding-house-control-mode` derivada de `develop @ 94c718024359dc7ff8360949313969b3ceaf9776` (passando por `B0 @ e5024909fbb17cd5266d30e0452e92cc095d5923`); `develop`, `main`, tags e `C:\Projetos\Dawn of Kin\project.godot` (`SHA-256 = AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`) integralmente preservados.
- **Verificações documentais da entrega:** existência de todos os arquivos e símbolos citados, conformidade transversal das 33 seções e dos 12 itens (`B0-Q01`–`B0-Q07` + `B0-A01`–`B0-A05`), ausência de diff executável (`NON_DOC_DIFF_COUNT=0`), `git diff --cached --check` antes do commit e geração/verificação do manifesto externo em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B0-R1\` (preservando intacto o manifesto original `B0`).

---

## 11. Limitações da Análise

- Conforme autorizado para `B0` e `B0-R1`, nenhum teste automatizado da Godot, benchmark ou teste humano foi executado (os números `95/95`, `724/724`, `34.026`/`34.029` citados referem-se estritamente aos registros históricos homologados da `R-03A`).
- A duração definitiva de `D-05` (entre `3 s`, `8 s`, `15 s` ou ajuste fino) permanece aberta para calibração empírica em `B4` conforme `B0-Q06 A`.

---

## 12. Estado da Próxima Etapa

- **`R-03B B0-R1`:** candidata documental reconciliada pronta para **auditoria independente do ChatGPT** (`NÃO HOMOLOGADA`).
- **`R-03B B1`, `B2`, `B3`, `B4` e posteriores:** **`NÃO AUTORIZADAS / BLOQUEADAS`** até conclusão da auditoria independente sobre `B0-R1`, homologação expressa do plano arquitetural e autorização específica de `B1` em etapa posterior.
