# Dawn of Kin — R-03B B1 — Relatório de Candidata Técnica (Casa Fundadora, Permissões e Autoridade de Admissão de Ordens)

**Status obrigatório:** **CANDIDATA TÉCNICA B1 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA.**

> **Taxonomia normativa (`AGENTS.md` §2):**
> - **R-03A:** `HOMOLOGADA DEFINITIVAMENTE` · `INTEGRADA À DEVELOP` · `VALIDADA PÓS-INTEGRAÇÃO` · `PUBLICADA` · `ENCERRADA`.
> - **R-03B B0 (`B0` / `B0-R1` / `B0-R2`):** `HOMOLOGADO DEFINITIVAMENTE` · `ENCERRADO` (SHA documental homologado: `30b791571a7594f3e1de5a2403a69a1f11713eee`).
> - **R-03B B1 (esta candidata):** `IMPLEMENTADA` · `VALIDADA TECNICAMENTE` · `PUBLICADA EM BRANCH CANDIDATA` · **`NÃO AUDITADA`** · **`NÃO HOMOLOGADA`** · **`NÃO INTEGRADA À DEVELOP`**.
> - **R-03B B2, B3, B4:** `PLANEJADAS` · `BLOQUEADAS` · `NÃO AUTORIZADAS`.

---

## 1. Autorização

O proprietário homologou definitivamente o planejamento arquitetural **`R-03B B0-R2`** (commit `30b791571a7594f3e1de5a2403a69a1f11713eee`, encerrando integralmente `B0`) e autorizou exclusivamente a implementação da etapa **`R-03B B1 — Casa Fundadora, Permissões e Autoridade de Admissão de Ordens`**, seguindo estritamente o plano arquitetural homologado (`docs/architecture/R_03B_FOUNDING_HOUSE_CONTROL_MODE_PLAN.md`), a Estratégia A de fronteira `B1/B2` (`F04`), e os critérios complementares da última auditoria independente.

**Diferenciação obrigatória de referências e estados:**
- **SHA documental homologado (`B0-R2`):** `30b791571a7594f3e1de5a2403a69a1f11713eee`.
- **SHA técnico B1 / SHA final publicado:** registrado na Seção 24 e no registro final de `10_git_final` após o commit único e `git push` normal na branch candidata `feat/r-03b-founding-house-control-mode`.
- **Estado da homologação técnica de B1:** **`NÃO HOMOLOGADA`** — aguardando auditoria independente do ChatGPT e decisão expressa do proprietário.
- **Restrições preservadas:** nenhum componente de `B2`, `B3` ou `B4` foi antecipado; nenhum documento histórico (`B0`, `B0-R1`, `B0-R2`) ou normativo (`AGENTS.md`, `GDD v1.3`, `ROADMAP_MESTRE.md`, `KNOWN_ISSUES.md`) foi modificado.

---

## 2. Escopo implementado

Em conformidade integral com o escopo autorizado para `R-03B B1`:

1. **Metadados mínimos da Casa Fundadora e estágios etários** em `CharacterDefinition`, com validação cruzada em `is_valid()`, defaults seguros (`COMMUNITY`, `NONE`, `ADULT`) e configuração explícita dos dois protagonistas originais (`data/characters/leader_a.tres`, `data/characters/leader_b.tres`).
2. **Fonte única de verdade de permissões** em `UnitControlPermissions` (`src/units/unit_control_permissions.gd`), cobrindo seleção visual, inspeção, ordens pessoais, trabalho comunitário, recuperação econômica e API preparada `can_join_manual_team_future` (sem uso de jogabilidade nesta etapa).
3. **Reclassificação explícita de `Worker3` e `Worker4` (`B0-Q03 B`)** como moradores comuns temporários (`COMMUNITY`, `NONE`, `ADULT`) em `TemporaryTestWorkersController`, mantendo remoção controlada e participação legítima em trabalho comunitário e recuperação econômica.
4. **Origem formal das ordens (`UnitOrder.OrderOrigin`)** em `src/units/orders/unit_order.gd` (`NONE`, `PERSONAL`, `COMMUNITY`, `SYSTEM_RECOVERY`), atribuída exclusivamente pela barreira de admissão da `Unit`.
5. **Barreira final e entradas separadas na `Unit`** (`issue_personal_order`, `issue_order` como entrada de compatibilidade estrita, `issue_community_order`, `issue_recovery_order`), sem flags de bypass e preservando `issue_order(null)` para encerramento limpo de ciclo de vida.
6. **Autoridade comunitária via `CommunityWorkBoard.DispatchLease` (`F01`)** abrangendo madeira, pedra e alimento, com ciclo de vida completo (`ACTIVE -> INSTALLING -> COMMITTED / ABORTED / REVOKED`), proteção anti-falsificação, revogação automática e tratamento de conclusão síncrona e callbacks reentrantes.
7. **Autoridade de recuperação econômica (`F02`)** em `CancellationRecoveryDispatcher` e `Unit.issue_recovery_order()` com verificação ativa de instância exata (`is_admitting_recovery`), registro regional real com custódia pendente, isolamento de domínio/revisão, transições `T1a`/`T1b`, guarda transacional somente leitura (`ConstructOrder.is_transfer_executing_readonly()`) e preservação de `entry.manual`.
8. **Filtro pré-planejamento de seleção mista (`B0-Q02 A`)** em `CommandController` e proteção de seleção/hover contra `BABY` em `SelectionManager` e `RtsInputController`.
9. **Intervenção visual transitória mínima e event-driven (`B0-Q01 A`)** em `SelectedUnitPanel`, `HudFormatter`, `ResourceHud` e `MainScene` (`AutonomousGatherFeedback`), preservando `use_d2_2_hud = false`, zero polling por frame e compatibilidade integral com `D4-A01`.
10. **Suítes de testes RED → GREEN de B1 (`A01`–`A07`, `B01`–`B03`, `E01-B1`)** e reconciliação documentada das 3 suítes históricas diretamente impactadas por `B0-Q03 B`, sem enfraquecimento de asserções e preservando integralmente os contratos `B0-Q05`/`BLOCKED_REAUTHORIZATION`/`HD3-06` para `B3`.

**Fronteira `B1/B2` (`F04` — Estratégia A) estritamente respeitada:** nenhuma ocorrência de `UnitControlState`, `ControlMode`, `control_mode_changed`, `InterruptionCause`, temporizador `D-05`, `PERSONAL_POST_MOVE_WAIT`, `T1c`, retorno automático à mesma tarefa (`B0-Q05 B`) ou ativação da HUD `D2.2`.

---

## 3. Base Git

- **Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`
- **Branch candidata:** `feat/r-03b-founding-house-control-mode`
- **Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03b`
- **Checkout principal protegido:** `C:\Projetos\Dawn of Kin` (em `develop`, SHA `94c718024359dc7ff8360949313969b3ceaf9776`, arquivo local `project.godot` intacto com SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`)
- **Base autorizada (`B0-R2`):** `30b791571a7594f3e1de5a2403a69a1f11713eee` (3 commits à frente de `develop`, 0 atrás)
- **`main` protegida:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Tags protegidas:** `t1-complete`, `t2-complete`, `t3-3-complete`
- **Flags vigentes em `src/main/main.tscn` (preservadas):** `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`

---

## 4. Metadados

Em `src/units/character_definition.gd`:
- `enum HouseAffiliation { COMMUNITY, FOUNDING_HOUSE }` (default seguro: `COMMUNITY`)
- `enum FoundingHouseOrigin { NONE, ORIGINAL_FOUNDER, DIRECT_DESCENDANT, EXTERNAL_SPOUSE }` (default seguro: `NONE`)
- `enum AgeStage { BABY, CHILD, YOUTH, ADULT }` (default seguro: `ADULT`)
- **Validação cruzada em `is_valid()`:**
  - `COMMUNITY` exige `founding_house_origin == NONE`.
  - `FOUNDING_HOUSE` exige `founding_house_origin != NONE`.
  - `ORIGINAL_FOUNDER` e `EXTERNAL_SPOUSE` exigem `age_stage == ADULT`.
  - Valores fora dos enums ou campos numéricos/IDs inválidos tornam `is_valid() == false`, negando todos os privilégios em `UnitControlPermissions`.
- **Helpers sem dependência de nome de nó ou `display_name`:** `is_founding_house_member()` e `is_original_founder()` (`DEC-07`).
- **Protagonistas originais:** `data/characters/leader_a.tres` e `data/characters/leader_b.tres` configurados com `house_affiliation = 1` (`FOUNDING_HOUSE`), `founding_house_origin = 1` (`ORIGINAL_FOUNDER`) e `age_stage = 3` (`ADULT`).

---

## 5. Permissões

Implementadas em `src/units/unit_control_permissions.gd` (`UnitControlPermissions`) como fonte única de verdade:

| Perfil (`HouseAffiliation` / `AgeStage`) | Seleção visual & Inspeção | Ordens pessoais leves (`MOVE`, `GATHER_FOOD`, `DELIVER_TO_CAMP`) | Ordens pessoais pesadas (`GATHER_WOOD`, `GATHER_STONE`, `CONSTRUCT_SITE`) | Coleta comunitária leve (`GATHER_FOOD`) | Coleta comunitária pesada (`GATHER_WOOD`, `GATHER_STONE`) | Recuperação econômica (`RecoveryOrder`) | `can_join_manual_team_future` |
|---|---|---|---|---|---|---|---|
| Metadados ausentes ou inválidos | Não | Não (`invalid_character_definition`) | Não (`invalid_character_definition`) | Não | Não | Não | Não |
| `FOUNDING_HOUSE` / `BABY` | Não | Não (`age_restricted_task`) | Não (`age_restricted_task`) | Não | Não | Não | Não |
| `COMMUNITY` / `BABY` | Não | Não (`age_restricted_task`) | Não (`age_restricted_task`) | Não | Não | Não | Não |
| `FOUNDING_HOUSE` / `CHILD` | Sim | Sim | Não (`age_restricted_task`) | Sim | Não | Não | Apenas `GATHER_FOOD` |
| `COMMUNITY` / `CHILD` | Sim (somente leitura) | Não (`personal_control_denied`) | Não (`personal_control_denied`) | Sim | Não | Não | Não |
| `FOUNDING_HOUSE` / `YOUTH` | Sim | Sim | Sim | Sim | Sim | Sim | Sim |
| `COMMUNITY` / `YOUTH` | Sim (somente leitura) | Não (`personal_control_denied`) | Não (`personal_control_denied`) | Sim | Sim | Sim | Não |
| `FOUNDING_HOUSE` / `ADULT` | Sim | Sim | Sim | Sim | Sim | Sim | Sim |
| `COMMUNITY` / `ADULT` | Sim (somente leitura) | Não (`personal_control_denied`) | Não (`personal_control_denied`) | Sim | Sim | Sim | Não |

- `SelectionManager._is_selectable_unit()` e `RtsInputController._set_hovered_unit()` consultam `UnitControlPermissions.can_be_selected_visually(unit)`, bloqueando seleção e hover de `BABY` e preservando inspeção de moradores comuns.

---

## 6. Seleção mista

Em `src/rts/command_controller.gd` (`B0-Q02 A`):
- `_filter_personal_command_units(units, command_kind)` filtra a seleção **antes** de `GroupMovePlanner`, `_collect_occupied_positions`, verificação de bloqueadores pendentes, `_admit_economic_command`, verificação de slots de fonte/canteiro, criação de ordens e `DestinationMarker`.
- **Movimento (`GROUND`, `OBSTACLE`, `UNIT`):** apenas unidades elegíveis recebem posições planejadas; unidades excluídas permanecem como ocupantes físicos em `_collect_occupied_positions(eligible)` e conservam suas ordens comunitárias e revisões intocadas.
- **Coleta pessoal (`RESOURCE_SOURCE`) e Construção (`CONSTRUCTION_SITE`):** unidades excluídas não consomem vagas em `ResourceSource` nem em `ConstructionSite` e não entram em `_admit_economic_command`.
- **Seleção 100% inelegível:** falha sem efeitos colaterais, registra `_last_command_reason` (`personal_control_denied` ou `age_restricted_task`), emite `command_rejected` e nunca movimenta `DestinationMarker`.

---

## 7. Inspeção de moradores comuns

Intervenção visual transitória mínima (`B0-Q01 A`), estritamente event-driven (zero `set_process` / `set_physics_process`):
- `src/ui/hud_formatter.gd`: `format_unit_inspection_meta(unit, community_board)` e `format_resource_label(resource_id)`.
- `src/ui/selected_unit_panel.tscn` e `src/ui/selected_unit_panel.gd`: adição do rótulo discreto `InspectionMetaLabel` dentro de `SingleUnitContent` (`visible = false` para membros da Casa Fundadora, preservando `get_state_text()` 100% compatível com os testes de `T2`). Para moradores comuns exibe `"Morador — somente leitura"`, enriquecido reativamente por sinais do `CommunityWorkBoard` com `" · Coleta comunitária: Madeira/Pedra/Alimentos"` ou `" · Recuperação de materiais"`.
- `src/ui/resource_hud.gd` e `src/main/main.gd`: vinculação opcional de `CommunityWorkBoard` em `ResourceHud.configure()` e conexão de `CommandController.command_rejected` ao `AutonomousGatherFeedback` (mensagens curtas e não repetitivas para `personal_control_denied` e `age_restricted_task`, respeitando `D4-A01`).

---

## 8. Worker3 e Worker4

Em `src/units/temporary_test_workers_controller.gd` (`B0-Q03 B`):
- `_create_worker_definition()` define explicitamente:
  - `house_affiliation = CharacterDefinition.HouseAffiliation.COMMUNITY`
  - `founding_house_origin = CharacterDefinition.FoundingHouseOrigin.NONE`
  - `age_stage = CharacterDefinition.AgeStage.ADULT`
- `Worker3` (`&"test_worker_3"`) e `Worker4` (`&"test_worker_4"`) permanecem selecionáveis para inspeção somente leitura, recusam ordens pessoais (movimento, coleta pessoal e construção pessoal), executam coleta comunitária legítima via `CommunityWorkBoard` + `DispatchLease` + `CommunityTaskDispatcher`, podem executar recuperação econômica legítima sem adquirir controle pessoal, e continuam sob todas as travas seguras de `remove_temporary_workers_safely()`.

---

## 9. OrderOrigin

Em `src/units/orders/unit_order.gd`:
- `enum OrderOrigin { NONE, PERSONAL, COMMUNITY, SYSTEM_RECOVERY }`
- Propriedade interna `_order_origin: OrderOrigin = OrderOrigin.NONE` com getter público somente leitura `get_order_origin()` e setter interno `_set_order_origin()` invocado exclusivamente por `Unit._install_admitted_order()` após admissão validada.
- Ordens não admitidas mantêm `OrderOrigin.NONE`.

---

## 10. Entradas pessoais

Em `src/units/unit.gd`:
- `issue_personal_order(order: UnitOrder) -> bool`: valida trava transacional, ordem não-nula em estado `PENDING` e `UnitControlPermissions.get_personal_order_rejection_reason_for_order(self, order)` (rejeitando `RecoveryOrder`, moradores comuns, `BABY`, tarefas pesadas para `CHILD` e metadados inválidos). Em recusa, retorna `false`, preenche `_last_order_rejection_reason`, e **não** altera `_current_order` nem `_order_revision`.
- `issue_order(order: UnitOrder) -> bool`: entrada de compatibilidade estrita — delega ordens não-nulas a `issue_personal_order(order)` (sem bypass!) e preserva `issue_order(null)` para encerramento limpo de ordem ativa (`_clear_current_order_for_null_issue()`).
- `CommandController` utiliza exclusivamente `issue_personal_order()` nos caminhos pessoais (movimento, coleta pessoal, construção) e `dispatch_community_gather()` no caminho comunitário.

---

## 11. DispatchLease

Em `src/rts/community_work_board.gd`, `src/rts/command_controller.gd`, `src/rts/community_task_dispatcher.gd` e `src/units/unit.gd` (`F01`):
- **`CommunityWorkBoard.DispatchLease`:** possui estados `ACTIVE`, `INSTALLING`, `COMMITTED`, `ABORTED`, `REVOKED` (default `REVOKED`, impedindo falsificação por `DispatchLease.new()`).
- **Registro interno autoritativo:** o `CommunityWorkBoard` mantém `_pending_leases_by_task_id` e `_active_leases_by_id`, impedindo leases simultâneos na mesma tarefa ou na mesma unidade.
- **Emissão (`begin_task_dispatch`):** valida árvore, tarefa ativa em `PENDING_WORKERS` sem unidade/ordem atribuída, fonte utilizável no domínio regional, token `CutAuthorization` válido em `GATHER_WOOD`, permissão `UnitControlPermissions.can_participate_in_community_work`, unidade ociosa no mesmo `World3D`, ausência de exclusão em `excluded_unit_ids` e ausência de lease pendente.
- **Pré-instalação (`validate_dispatch_lease_for_installation` + `mark_dispatch_lease_installing`):** valida as 13 condições contratuais (incluindo igualdade estrita `order.get_tree_cut_authorization() == task.tree_cut_authorization` em `WOOD` e `unit.get_order_revision() == lease.expected_unit_revision`) e transita `ACTIVE -> INSTALLING` antes de `order.start()`, bloqueando reentrada/reuso do mesmo lease durante callbacks.
- **Pós-instalação (`is_dispatch_lease_valid_for_commit` + `commit_task_dispatch`):** exige `INSTALLING`, tarefa ainda `PENDING_WORKERS` sem atribuição e mesmo `tree_cut_authorization`, **sem** rejeitar pelo avanço legítimo da revisão da unidade durante a instalação.
- **Revogação e limpeza (`abort_task_dispatch` / `_revoke_pending_lease_for_task`):** revogação automática em `close_task()`, `block_for_reauthorization()`, `reauthorize_gather_task()` e `teardown()`, garantindo zero leases órfãos.

---

## 12. Recuperação T1a e T1b

Em `src/units/cancellation_recovery_dispatcher.gd`, `src/units/orders/recovery_order.gd`, `src/units/orders/construct_order.gd` e `src/units/unit.gd` (`F02`):
- **Rastreamento de admissão exata no dispatcher:** `CancellationRecoveryDispatcher` grava `_admitting_unit`, `_admitting_order`, `_admitting_explicit` exclusivamente durante a janela de `_assign()` e expõe `is_admitting_recovery(unit, order, explicit) -> bool`.
- **`Unit.issue_recovery_order(order: RecoveryOrder, expected_revision: int, explicit: bool = false) -> bool`:** valida trava transacional, `order` `PENDING`, unidade válida na árvore, `UnitControlPermissions.can_perform_recovery_order(self)` (`YOUTH`/`ADULT`), revisão exata, `dispatcher.is_admitting_recovery(self, order, explicit)`, ausência de transação regional ativa, registro real em `CancellationRecoveryTransaction._record(world, region_id, cancel_id)` com `has_unsettled_custody()`, e `validate_unit_identity_in_domain_readonly`.
- **Regra estrita `T1a` / `T1b`:**
  - `T1a`: `_current_order == null and _state == State.IDLE`.
  - `T1b`: `_current_order is ConstructOrder` com `site.site_id == record.site_id`, `site.get_site_state() == SiteState.CANCELLED`, e `not c_order.is_transfer_executing_readonly()`.
  - Rejeita `MoveOrder`, `GatherResourceOrder`, `ConstructOrder` de canteiro ativo ou divergente, `cancel_id` inexistente, registro liquidado (`SETTLED`) e revisões obsoletas.
- **Preservação de `entry.manual`:** se `issue_recovery_order` recusar antes de avançar `_order_revision` (ex.: trava transacional), `CancellationRecoveryDispatcher._assign()` restaura `prior` sem marcar `manual = true`; quando uma ordem pessoal interrompe `RecoveryOrder`, `entry.manual = true` continua persistindo e bloqueando reatribuição automática.

---

## 13. Critérios complementares da auditoria

Todos verificados em código e cobertos por testes automatizados (`test_a07`, `test_e01_b1`):
- **Lease fabricado (`DispatchLease.new()`):** nasce `REVOKED` e ausente de `_active_leases_by_id` → rejeitado.
- **Reutilização de lease consumido (`COMMITTED`) ou abortado (`ABORTED`):** rejeitado; `commit_task_dispatch()` retorna `false` em segunda tentativa.
- **Atribuição duplicada concorrente:** `begin_task_dispatch()` retorna `null` enquanto houver lease ativo na tarefa ou unidade.
- **Token válido de outra tarefa de madeira:** rejeitado por comparação estrita `order.get_tree_cut_authorization() == task.tree_cut_authorization`.
- **Término síncrono (`order.is_succeeded()` dentro de `start()`):** `Unit._install_admitted_order()` retorna `true` (não trata conclusão síncrona como recusa); `CommunityTaskDispatcher` consolida o lease e fecha a tarefa como `COMPLETED` se a fonte exauriu.
- **Invalidacão durante callback com instalação de ordem pessoal sucessora:** `CommunityTaskDispatcher` verifica `unit.get_current_order() == order and unit.get_order_revision() == installed_revision` antes de qualquer cancelamento, preservando intacta a ordem pessoal sucessora e abortando o lease sem órfãos.
- **Ordem `RecoveryOrder` divergente durante admissão ativa:** rejeitada por `is_admitting_recovery(unit, order, explicit)` verificar identidade exata da instância `order`.

---

## 14. Preservação econômica

- Nenhuma alteração em regras de proveniência (`CarryProvenanceLedger`, `ReservedWithdrawalCoordinator`, `CancellationRecoveryTransaction`, `GroundPileManager`, `SettlementInventory`).
- Conservação regional exata verificada em `test_e01_b1_t1b_legitimate_replacement_and_conservation` via `RegionalConservationAudit` (madeira e pedra antes/depois do cancelamento e liquidação `SETTLED`).
- Todas as suítes econômicas (`T2`, `T3.1`–`T3.6.4`, `R-03A D3.3`) passaram integralmente na regressão completa (`98/98`).

---

## 15. Reconciliação dos testes históricos

Das 95 suítes históricas pré-existentes, **92 passaram sem nenhuma modificação** e apenas **3 suítes** precisaram de adaptação estritamente decorrente da decisão homologada **`B0-Q03 B`** (`Worker3`/`Worker4` classificados como `COMMUNITY`). Nenhuma suíte de `B0-Q05` (`BLOCKED_REAUTHORIZATION` / `excluded_unit_ids` / `HD3-06`) foi modificada (reservadas à `B3`).

| Arquivo/teste | Contrato anterior | Motivo da adaptação | Alteração realizada | Contrato preservado | Novas verificações |
|---|---|---|---|---|---|
| `tests/integration/test_t3_3_ux_flow.gd` (`test_03_c4_three_workers_fourth_rejected_and_promotion_on_interrupt`) | Usava `Worker3`/`Worker4` (do botão C4) como 3º e 4º trabalhadores recebendo `command_units_to_site` pessoal | `B0-Q03 B`: `Worker3`/`Worker4` são `COMMUNITY` e não aceitam comandos pessoais de construção | Mantido o spawn C4 de `Worker3`/`Worker4` verificando recusa `personal_control_denied`; criadas 2 fixtures locais `FOUNDING_HOUSE` (`FounderC`, `FounderD`) para os passos C4-C/C4-D/C4-E | Cap D9 de 3 trabalhadores (1 transportador + 2 construtores), recusa do 4º com `no_worker_slot`, banner do overlay, promoção por interrupção e entrega exata 12 madeira / 6 pedra | Verificação explícita de que `Worker3`/`Worker4` são `COMMUNITY` e rejeitam `command_units_to_site` com `personal_control_denied` |
| `tests/integration/test_t3_6_2_c4_2_lifecycle_readiness.gd` (`test_p5_02`, `test_p5_04`) | Emitia `w3.issue_order(ConstructOrder)` / `w4.issue_order(ConstructOrder)` / `w3.issue_order(GatherResourceOrder)` / `w4.issue_order(NonCancellableOrder)` diretamente em `Worker3`/`Worker4` | `B0-Q03 B` + `F01`: `Worker3`/`Worker4` são `COMMUNITY` e só aceitam `GatherResourceOrder` mediante `DispatchLease` legítimo | Em `p5_02`, registro de fixture de `ConstructOrder` diretamente no `ConstructionSite` (padrão já usado em `c3_5`) para testar `transit_claim_active`; em `p5_04`, `w3` recebe coleta comunitária real via `CommunityWorkBoard` + `DispatchLease` e `w4` instala `NonCancellableOrder` apenas como injeção sintética de falha no fixture | Todas as travas de remoção controlada (`transit_claim_active` dentro e fora de `ConstructionSites`, `order_cancel_failed`, zero remoção parcial, revalidação pós-cancelamento `cargo_in_backpack`, isolamento multi-região) | Execução de coleta legítima de `Worker3` via `CommunityWorkBoard` + `DispatchLease` com remoção limpa de slot |
| `tests/integration/test_t3_6_2_c3_5_gather_order_integration.gd` (`test_group_e`, bloco `#43`) | Emitia `w3.issue_order(GatherResourceOrder)` e `w4.issue_order(GatherResourceOrder)` diretamente em `Worker3`/`Worker4` | `B0-Q03 B` + `F01`: `Worker3`/`Worker4` são `COMMUNITY` e exigem autoridade comunitária (`DispatchLease`) | Criado `CommunityWorkBoard` local com duas tarefas reais (`slot_bush` e `slot_bush_w4`) e despachos legítimos via `begin_task_dispatch` + `issue_community_order` + `commit_task_dispatch` | Bloqueio `cargo_in_backpack` durante carga de `w4`, conclusão com sucesso e mochila vazia de `w4`, e liberação limpa de slot de `w3` na remoção controlada | Fluxo real de `DispatchLease` + proveniência + remoção controlada de trabalhadores comunitários |

**Ferramenta visual inspecionada separadamente (não contabilizada como suíte automatizada):**
- `tests/visual/t3_3_ux_repro.gd`: script manual histórico de `T3.3-UX` (verificado sintaticamente pelo `validate.ps1` com `0` erros/avisos). Mantido inalterado nesta candidata por ser ferramenta histórica manual pré-`B0-Q03 B` que invocava `command_units_to_site` em `Worker3`/`Worker4`; documentado como referência histórica de reprodução visual.

---

## 16. RED

Antes de qualquer alteração em código de produção, foram criadas as 3 suítes de B1 (`test_r_03b_b1_founding_house_permissions.gd`, `test_r_03b_b1_authority_and_dispatch_lease.gd`, `test_r_03b_b1_recovery_authority.gd`) e executadas contra a base `30b791571a7594f3e1de5a2403a69a1f11713eee`:
- **Comando:** `.\tools\run_tests.ps1 -Filter test_r_03b_b1`
- **Evidência preservada:** `evidencias\R-03B\B1\02_red\red_run.log`
- **Resultado RED autêntico:** `RED_EXIT_CODE=1`, `SuiteErrors: 3` (ausência das novas APIs `HouseAffiliation`, `UnitControlPermissions`, `OrderOrigin`, `DispatchLease`, retorno `bool` de `Unit.issue_order()`).

---

## 17. GREEN

Após a implementação B1 e ajustes de isolamento `SubViewport` (`own_world_3d = true`) em `test_r_03b_b1_recovery_authority.gd`:
- **Comando:** `.\tools\run_tests.ps1 -Filter test_r_03b_b1`
- **Evidência:** `evidencias\R-03B\B1\04_green\b1_tests_green.log` e `evidencias\R-03B\B1\06_recovery_and_conservation\e01_b1_recovery_and_conservation.log`
- **Resultado:**
  - `test_r_03b_b1_founding_house_permissions.gd`: **5/5 PASS** (`105` asserções) — `A01`, `A02`, `B01`–`B03`, invariantes de `CharacterDefinition`, `OrderOrigin`.
  - `test_r_03b_b1_authority_and_dispatch_lease.gd`: **5/5 PASS** (`127` asserções) — `A03`, `A04`, `A05`, `A06`, `A07` (11 subcenários + todos os casos complementares de auditoria), `B01`–`B02` em entradas de produção.
  - `test_r_03b_b1_recovery_authority.gd`: **3/3 PASS** (`71` asserções) — `E01-B1` completo (`T1a`, `T1b`, rejeições, instância divergente, trava transacional, `entry.manual`, `Worker3`, `RegionalConservationAudit`).
  - **Total B1:** **3/3 suítes · 13/13 testes · 303 asserções · 0 falhas · `B1_GREEN_EXIT=0`**.

---

## 18. Validação estática

- **Comando:** `.\tools\validate.ps1`
- **Evidência:** `evidencias\R-03B\B1\07_static_validation\validate.log`
- **Resultado:** `Validation PASSED (0 errors, 0 warnings, 225 scripts checked).` · **`VALIDATE_EXIT=0`**.
- Headless import (`--import`), checagem de todos os 225 scripts (`--check-only`) e boot headless da `MainScene` (`--quit-after 3`) concluídos com 0 erros e 0 avisos; 0 arquivos `.import` gerados sob `docs/design/`.

---

## 19. Regressão

**Justificativa da extensão integral (`§41`):** devido à natureza transversal da alteração na barreira de admissão `Unit.issue_order()` e da reclassificação de `Worker3`/`Worker4`, foi executada a **campanha segmentada completa** cobrindo todas as 98 suítes descobertas do repositório (95 históricas + 3 novas de B1).

- **Comando:** `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 180`
- **Evidência:** `evidencias\R-03B\B1\08_regression\segmented_regression.log` (além dos logs individuais das 3 suítes reconciliadas em `05_historical_test_reconciliation\`).
- **Resultado agregado (execução atual B1, sem mistura com baselines históricas de R-03A):**
  - **Lotes:** `70/70 PASS` (`unit` + `integration-01`..`integration-69`)
  - **Suítes:** `98/98` (`Discovered=98 | ExecutedUnique=98 | Duplicates=0 | Missing=0`)
  - **Testes:** `737/737 PASS` (`Failed=0 | SuiteErrors=0`)
  - **Asserções:** `34.352`
  - **Código de saída real:** **`SEGMENTED_REGRESSION_EXIT=0`**

---

## 20. Smoke

Executado smoke renderizado real na `MainScene` (`res://src/main/main.tscn`) com `opengl3` em hardware de referência (`Intel(R) UHD Graphics 620`), `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`:
- **Evidência:** `evidencias\R-03B\B1\09_smoke_and_visual\smoke_visual.log` e `smoke_summary.json`
- **Resultado:** `SMOKE_SUCCESS=True`, `EXIT=0`, `ERR=False`, `WARN=False`, `"passed": true`.
- Comprovados na `MainScene`: navegação pronta, `LeaderA`/`LeaderB` como fundadores originais válidos, comando pessoal de `LeaderA`, spawn e classificação `COMMUNITY` de `Worker3`/`Worker4`, trabalho comunitário legítimo de `Worker3` com `OrderOrigin.COMMUNITY`, inspeção somente leitura em `SelectedUnitPanel` (zero polling), recusa pessoal com aviso em `AutonomousGatherFeedback`, criação e atribuição em canteiro legado para fundador, e remoção controlada de `Worker3`/`Worker4`.

---

## 21. Evidências visuais

Capturas renderizadas produzidas e inspecionadas em ambas as resoluções canônicas (`evidencias\R-03B\B1\09_smoke_and_visual\`):
- `b1_mainscene_1280x720_readonly_inspection.png` (`1280×720`)
- `b1_mainscene_1920x1080_readonly_inspection.png` (`1920×1080`)

**Verificação visual:** em ambas as resoluções, `SelectedUnitPanel` (canto inferior esquerdo) exibe `Worker3`, `Trabalhando` e o rótulo discreto `Morador — somente leitura · Coleta comunitária: Madeira`, sem cortes ou sobreposições; `AutonomousGatherFeedback` (topo central) exibe `Moradores da comunidade não recebem comandos diretos.` sem colisão com `DebugOverlay` nem `SettlementStockpilePanel`; `use_d2_2_hud = false` permanece preservado.

---

## 22. Limitações

- **Ainda não implementados (escopo reservado a etapas futuras bloqueadas):**
  - `B2`: `UnitControlState`, `ControlMode`, `control_mode_changed`, `InterruptionCause`, temporizador `D-05`, `PERSONAL_POST_MOVE_WAIT`, `T1c` e reescrita completa de revisões/notificações `F03`.
  - `B3`: retorno automático à mesma tarefa comunitária (`B0-Q05 B`) e reconciliação de `BLOCKED_REAUTHORIZATION`/`HD3-06`.
  - `B4`: campanha final de desempenho/benchmarks CA/DC completos e aceite humano final da `R-03B`.
- **Testes humanos finais:** `NÃO EXECUTADOS` nesta candidata (a homologação da experiência jogável depende da auditoria independente do ChatGPT e da execução manual pelo proprietário conforme governança).
- **Ferramenta histórica manual `tests/visual/t3_3_ux_repro.gd`:** mantida inalterada como artefato histórico de `T3.3-UX`.

---

## 23. Riscos remanescentes

- **Dependência `B2` (`F03`/`F04`):** `Unit` na `B1` preserva a máquina de estados existente com barreira de admissão limpa; na `B2`, `UnitControlState` se integrará sobre as mesmas entradas separadas (`issue_personal_order`, `issue_community_order`, `issue_recovery_order`) sem necessidade de refatorar `UnitControlPermissions` ou `DispatchLease`.
- **Custos futuros de `SelectedUnitPanel`:** a escuta dos sinais de `CommunityWorkBoard` é estritamente orientada a eventos com deduplicação por `_render_keys_match`; quando a HUD `D2.2` for ativada em `R-05B`, os rótulos de inspeção de moradores comuns deverão ser espelhados na HUD `D2.2`.
- **Auditoria independente pendente:** esta candidata ainda não passou pela auditoria independente do ChatGPT nem pela homologação expressa do proprietário.

---

## 24. Estado Git

- **Branch candidata:** `feat/r-03b-founding-house-control-mode`
- **SHA base (`B0-R2` homologado):** `30b791571a7594f3e1de5a2403a69a1f11713eee`
- **SHA técnico B1 / SHA final publicado:** registrado em `evidencias\R-03B\B1\10_git_final\git_final_state.txt` e no relatório final ao supervisor imediatamente após `git commit` + `git push`.
- **`develop` preservada:** `94c718024359dc7ff8360949313969b3ceaf9776`
- **`main` preservada:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Tags preservadas:** `t1-complete`, `t2-complete`, `t3-3-complete`
- **Checkout principal `C:\Projetos\Dawn of Kin`:** intocado, `project.godot` preservado (`AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`).
- **Worktree candidato `C:\Projetos\Dawn_of_Kin_wt_r_03b`:** mantido ativo e limpo (não encerrado).
- **Evidências externas e manifesto:** `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B1\` + `MANIFEST_SHA256.txt` verificado com `MANIFEST_VERIFY_FAIL=0` (preservando os manifestos `B0`, `B0-R1` e `B0-R2`).

---

## 25. Critério de parada

A execução de `R-03B B1` encerra-se imediatamente após a publicação desta candidata técnica em `origin/feat/r-03b-founding-house-control-mode` e verificação integral do manifesto de evidências:
- `R-03A`: homologada, integrada e encerrada.
- `R-03B B0`: definitivamente homologado e encerrado (`30b791571a7594f3e1de5a2403a69a1f11713eee`).
- **`R-03B B1`:** **CANDIDATA TÉCNICA B1 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA.**
- `R-03B B2`, `B3`, `B4`: bloqueadas.
- Nenhum merge, tag, promoção, declaração de homologação ou preparação executável de `B2` foi realizado.
