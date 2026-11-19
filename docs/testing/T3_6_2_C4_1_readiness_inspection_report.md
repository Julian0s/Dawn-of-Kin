# Dawn of Kin — Relatório Técnico de Inspeção T3.6.2-C4.1
## Prontidão para integração gradual da proveniência ao fluxo RTS legado

- **Natureza:** Inspeção técnica preventiva fundamentada no código-fonte real, sem alteração de produção, cenas, assets, GDD, arquitetura, testes ou protocolos existentes.
- **Data da inspeção:** 19/11/2026
- **Conclusão objetiva:** **PRONTO COM PRÉ-REQUISITOS** para iniciar a integração gradual (`C4.2+`); **NÃO PRONTO** para ativação global imediata da proveniência no fluxo RTS normal nem para iniciar `T3.6.3` (custódia e cancelamento D3).

---

## Classificação normativa e separação de evidências

| Origem da evidência | Escopo e limite |
| --- | --- |
| **Observação direta no código (esta inspeção C4.1)** | Inspeção estática linha a linha do baseline `a19c48b6d9c2f8277c8139786d1cb17c1df36463`, dos contratos normativos vigentes e dos caminhos reais de chamada em `src/`, `data/`, `tests/` e `docs/`. Nenhum código de produção foi alterado e nenhuma bateria de testes foi reexecutada indiscriminadamente. |
| **Resultados automatizados históricos reportados por agentes** | Auditoria independente headless do Codex (commits `0a35351` e `a19c48b`): `410/410` testes em `55` suítes (`23.990` asserções consolidadas após complementação de M8 e reexecução do lote `integration-02`; execução segmentada inicial com `409` testes), `149` scripts validados em `validate.ps1`, `8` testes complementares (`test_m1_m10_independent_headless.gd`), `0` erros/avisos reportados. Relatórios históricos C3.4.3 (`4e89898`) e C3.5 (`cff0de2`) usados como referência de escopo e confrontados com o código real. |
| **Validação visual/manual reportada pelo proprietário** | **M1: APROVADO visualmente**; **M7: APROVADO visualmente** (sem observações). **M2** possui aprovação manual principal anterior. **M3** teve entrega correta, com a ocorrência `empty_load` reproduzida pelo Codex como nova ordem emitida após esvaziamento da mochila. **M4–M6 e M8–M10** possuem cobertura automatizada (`AUTO_PASS` na auditoria headless), mas **não são rotulados como homologados visualmente**. |
| **Status normativo** | Prevalecem `docs/Dawn_of_Kin_GDD.md` (v1.2 consolidado: D2, D3, D9, DEC-11A/B, DEC-18/19) e decisões expressas do proprietário. A arquitetura `T3_6_cancellation_architecture_R2_PROPOSAL.md` (`69c13275a34a30564ac839ec920f83ef36590812`) é tratada estritamente como **PROPOSTA** de referência técnica, não como norma aprovada. |

---

## 1. Baseline Git verificado

Verificações não destrutivas executadas antes da leitura de código:

| Item | Resultado observado |
| --- | --- |
| **Repositório** | `Julian0s/Dawn-of-Kin` |
| **Worktree principal (`C:/Projetos/Dawn of Kin`)** | Em `review/t2-closeout-candidate` (`729390832883587180e3df89193522a72f27299d`), com `project.godot` modificado e `docs/historico/` não rastreado — **não modificado nem descartado**. |
| **Worktree da branch de trabalho (`C:/Projetos/Dawn_of_Kin_wt_t3_4_5`)** | Em `feat/t3-6-2-provenance-transactions`, árvore limpa (`nothing to commit, working tree clean`). Antes do `git fetch`, o ponteiro local estava em `cff0de2ef6913179dc59dc80ca6fe6e258f1f434` (`[behind 2]` de `origin`, sem divergência). |
| **Sincronização não destrutiva (`git fetch origin` + `git merge --ff-only`)** | Fast-forward limpo incorporando exatamente os dois commits da auditoria independente do Codex (`0a35351` e `a19c48b`). |
| **HEAD verificado após fast-forward** | `a19c48b6d9c2f8277c8139786d1cb17c1df36463` — **coincide integralmente com o SHA esperado** e com `origin/feat/t3-6-2-provenance-transactions`. |
| **`main` de referência** | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` — coincide com `origin/main` e permanece inalterada (`feat/t3-6-2-provenance-transactions` está `53` commits à frente e `0` atrás de `main`). |
| **Commit da proposta R2** | `69c13275a34a30564ac839ec920f83ef36590812` verificado via `git show` (`docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md`, 138 linhas). |

### Nota sobre referências cronológicas desatualizadas (sem interpretar como reversão)
- `AGENTS.md` (em `C:/Projetos/Dawn_of_Kin_wt_t3_4_5`) e o cabeçalho/§4.3/§10.2/§11 de `docs/Dawn_of_Kin_GDD.md` v1.2 registram o retrato histórico da `main` em `3c6fc0b` (`t3-3-complete`, 16/11/2026), listando `T3.4–T3.6` como planejadas/bloqueadas. Na `main` real atual (`25e0a20`), `T3.4.1–T3.4.5`, `T3.5.1`, `T3.5.2` e `T3.6.1` já estão integradas e aceitas; esses marcadores são estritamente históricos e não representam reversão de etapas já concluídas.

---

## 2. Fontes e arquivos realmente examinados

### Documentação, protocolos e evidências
- `AGENTS.md` (worktree `C:/Projetos/Dawn_of_Kin_wt_t3_4_5`)
- `docs/Dawn_of_Kin_GDD.md` (v1.2 integral: §1–§12, especialmente D2, D3, D9, DEC-11A/B, DEC-18/19, §4 e §9)
- `69c13275a34a30564ac839ec920f83ef36590812:docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` (integral)
- `docs/testing/T3_6_2_C3_4_3_candidate_report.md` e `docs/testing/T3_6_2_C3_4_3_manual_test_protocol.md` (M1–M6)
- `docs/testing/T3_6_2_C3_5_candidate_report.md` e `docs/testing/T3_6_2_C3_5_manual_test_protocol.md` (M7–M10)
- `docs/testing/T3_6_2_M1_M10_independent_headless_validation_report.md`

### Código-fonte real inspecionado
- **Composição, entrada RTS e unidades:** `src/main/main.gd`, `src/main/main.tscn`, `src/rts/command_controller.gd`, `src/rts/rts_input_controller.gd`, `src/units/unit.gd`, `src/units/unit_movement.gd`, `src/units/character_definition.gd`, `src/units/temporary_test_workers_controller.gd`, `data/characters/leader_a.tres`, `data/characters/leader_b.tres`
- **Ordens e sessões transacionais:** `src/units/orders/unit_order.gd`, `src/units/orders/move_order.gd`, `src/units/orders/gather_resource_order.gd`, `src/units/orders/gather_transfer_session.gd`, `src/units/orders/deliver_to_camp_order.gd`, `src/units/orders/camp_delivery_transfer_session.gd`, `src/units/orders/construct_order.gd`, `src/units/orders/construction_transfer_session.gd`
- **Economia, proveniência, pilhas e coordenadores:** `src/economy/unit_carry_load.gd`, `src/economy/carry_provenance_ledger.gd`, `src/economy/resource_source.gd`, `src/economy/settlement_inventory.gd`, `src/economy/settlement_storage_source.gd`, `src/economy/ground_pile_manager.gd`, `src/economy/ground_resource_pile.gd`, `src/economy/pile_reservation_ledger.gd`, `src/economy/camp_storage_zone.gd`, `src/economy/economy_clock_controller.gd`, `src/economy/reserved_withdrawal_coordinator.gd`, `src/economy/selective_site_delivery_coordinator.gd`, `src/economy/selective_site_delivery_planner.gd`, `src/economy/selective_camp_delivery_coordinator.gd`, `src/economy/selective_camp_delivery_planner.gd`, `src/economy/selective_camp_delivery_tx_helpers.gd`
- **Construção, slots, navegação e UI:** `src/buildings/construction_site.gd`, `src/buildings/construction_manager.gd`, `src/buildings/construction_cancellation_math.gd`, `src/buildings/build_slot_planner.gd`, `src/buildings/placement_test_overlay.gd`, `src/navigation/world_navigation.gd`, `src/ui/building_inspector_panel.gd`, `src/ui/selected_unit_panel.gd`, `src/ui/resource_hud.gd`, `src/ui/hud_formatter.gd`
- **Varredura de chamadas e testes:** varredura sistemática em todo `src/` por todos os mutadores de mochila, fonte, inventário, pilhas, reservas, ordens e `region_id`; inventário das suítes `tests/unit/test_t3_6_2_*`, `tests/integration/test_t3_6_2_*`, `tests/integration/test_m1_m10_independent_headless.gd`, `tests/visual/t3_6_2_c3_4_3_manual_harness.gd`, e inspeção de montagem de `MainScene` em `tests/integration/`.

---

## 3. Mapa dos fluxos legado e opt-in (Questão A — Compatibilidade)

### 3.1 Onde o RTS normal ainda usa caminhos legados

| Ponto de entrada RTS | Caminho atual no código | Estado da proveniência |
| --- | --- | --- |
| **Instanciação de protagonistas** (`src/main/main.tscn`, `src/units/unit.gd:40`, `src/main/main.gd:34-43`) | `Unit._carry_load = UnitCarryLoad.new()` sem chamada a `enable_provenance(...)`. | **Legado** (`is_provenance_enabled() == false`) |
| **Trabalhadores temporários C4** (`src/units/temporary_test_workers_controller.gd:209-218`) | `UNIT_SCENE.instantiate()` cria `Worker3`/`Worker4` com `UnitCarryLoad.new()`. | **Legado** |
| **Clique direito em fonte natural** (`src/rts/command_controller.gd:172-218`, `L201`) | `GatherResourceOrder.new(source, _camp_storage_zone, _settlement_inventory)` (`p_use_provenance_transactions = false`, `p_region_id = &""`). | **Legado** |
| **Clique direito / botão em canteiro** (`src/rts/command_controller.gd:220-282`, `L264`) | `ConstructOrder.new(site, _camp_storage_zone)` (`p_use_provenance_transactions = false`, `p_return_other_site_reserved = false`). | **Legado** |
| **Clique direito em terreno / obstáculo / unidade** (`src/rts/command_controller.gd:156-160`) | `MoveOrder.new(...)` — neutro quanto à mochila; cancela ordem ativa preservando carga e lotes. | **Compatível com ambos os modos** |
| **Entrega direta manual ao acampamento** (`src/rts/command_controller.gd`, `src/rts/rts_input_controller.gd`) | Não existe comando manual RTS para clicar na `CampStorageZone`; entregas ao acampamento ocorrem como subordem de `GatherResourceOrder` ou `ConstructOrder`. | **N/A** (proposta futura opcional no GDD v1.2 §9.1) |
| **Criação, trabalho, complemento e conclusão de obra** (`ConstructionManager`, `ConstructionSite`, `BuildingInspectorPanel`) | `try_create_site_from_placement`, `contribute_work`, `authorize_manual_complement`, `complete_site_transaction` operam sem `RegionalAuthority` (mas respeitam guardas locais). | **Compartilhado (não coordenado por `RegionalAuthority`)** |
| **HUD permanente** (`ResourceHud`, `SelectedUnitPanel`, `SettlementStockpilePanel`, `BuildingInspectorPanel`) | Somente leitura de `SettlementInventory`, `UnitCarryLoad` e `ConstructionSite` (exceto complemento manual em `BuildingInspectorPanel`). | **Compatível com ambos os modos** |

### 3.2 Coexistência dos fluxos legado vs. opt-in nas ordens e mutadores

| Operação econômica | Fluxo legado (padrão) | Fluxo opt-in (T3.6.2 até C3.5) | Barreira cruzada (fail-closed) |
| --- | --- | --- | --- |
| **Extração natural** (`GatherResourceOrder`) | `ResourceSource.transfer_to_carry_load()` → `carry_load.add_units()` | `GatherTransferSession` → `ResourceSource.transfer_to_carry_load_with_provenance()` (`FREE_GATHERED`) | Legado em mochila com proveniência falha com `provenance_opt_in_required` (`L224`); opt-in em mochila legada falha com `provenance_required` (`L229`). `add_units()` retorna `false` se `_provenance != null`. |
| **Descarga no acampamento** (`DeliverToCampOrder`) | `SettlementInventory.deliver_from_carry_load()` → `carry_load.take_all()` + `storage.deposit_batch()` | `CampDeliveryTransferSession` → `SelectiveCampDeliveryCoordinator` (lotes selecionados; padrão conservador só `FREE_GATHERED`) | Legado recusa proveniência (`provenance_opt_in_required`, `L132`); opt-in recusa legado (`provenance_required`, `L141`). `deliver_from_carry_load()` e `take_all()` recusam `_provenance != null`. |
| **Saque reservado para obra** (`ConstructOrder`) | `SettlementInventory.withdraw_reserved_from_pile_to_carry_load()` seguido de `site.record_withdrawn_for_site()` (não atômico) | `ConstructionTransferSession` → `ReservedWithdrawalCoordinator` (pilha + reserva + lote `SITE_RESERVED` + claim no mesmo commit) | `ConstructOrder._carry_admission_failure()` (`L247-255`) bloqueia cruzamento (`provenance_opt_in_required` / `provenance_required`); ambos os métodos legados recusam `is_provenance_enabled()`. |
| **Entrega à obra** (`ConstructOrder`) | `ConstructionSite.accept_delivery_from_carry_load()` → `carry_load.remove_units()` | `ConstructionTransferSession` → `SelectiveSiteDeliveryCoordinator` (débito apenas de lotes `SITE_RESERVED` do próprio `site_id`) | `accept_delivery_from_carry_load()` recusa `is_provenance_enabled()` (`construction_site.gd:965`); `remove_units()` recusa `_provenance != null`. |
| **Retorno de carga excedente em `ConstructOrder`** | `site.get_unneeded_cargo_for_unit()` → `DeliverToCampOrder` legado (`take_all()`) | `CampDeliveryTransferSession.inspect_cargo_for_construction_site()` → `DeliverToCampOrder` seletivo (`FREE_GATHERED` automático; `SITE_RESERVED` de outra obra só se `return_other_site_reserved = true`; D3 bloqueado) | `_start_returning_unneeded_cargo()` recusa modo opt-in com `selective_camp_delivery_required` (`construct_order.gd:521-523`). |

### 3.3 Viabilidade de integração gradual sem regressão T2/T3
A coexistência técnica **no nível das ordens** está limpa e fail-closed: nenhuma mochila é convertida silenciosamente e nenhum caminho legado da T2/T3.3–T3.5 foi alterado. Contudo, **ativar proveniência de forma mista no mesmo assentamento** (algumas unidades legadas e outras com proveniência) apresenta um limite estrutural demonstrável:
1. O `CommandController` hoje não distingue o modo da unidade — qualquer unidade com proveniência selecionada falha ao receber RMB.
2. Mesmo com despacho por unidade no `CommandController`, unidades legadas continuam podendo usar `DeliverToCampOrder` legado (`take_all()`) e `withdraw_reserved_from_pile_to_carry_load` + `record_withdrawn_for_site` (com janela não atômica e sem isolamento de reservas entre obras). Portanto, a coexistência mista serve apenas como transição controlada ou isolamento de testes; para garantir conservação estrita no RTS normal (e como base para T3.6.3), **todas as unidades comandáveis do domínio regional devem operar em proveniência**, com modo legado preservado apenas via flag desligável até homologação final.

---

## 4. Matriz de contratos implementados, testados e pendentes

| Contrato / Camada | Implementado no código | Cobertura automatizada (histórico Codex / T3.6.2) | Validação manual/visual | Pendente antes da integração RTS / T3.6.3 |
| --- | --- | --- | --- | --- |
| **Ledger de proveniência (`CarryProvenanceLedger`)** | Sim (`register_lot`, `split_lot`, `withdraw`, `validate_aggregate`, `snapshot/restore`) | Sim (`test_t3_6_2_a_provenance_ledger`) | Indireta via M7 | Origens D3 (`CANCEL_TRANSIT`, `CANCEL_BUFFER`, `CANCEL_INCORPORATED`) pertencem à T3.6.3 |
| **Binding na mochila (`UnitCarryLoad`)** | Sim (opt-in `enable_provenance`, bloqueio de `add_units`/`remove_units`/`take_all`/`restore_load_snapshot`) | Sim (`test_t3_6_2_b2_carry_binding`) | M2 principal (histórico) | Fechar/restringir `add_with_provenance` público (`P6`); checar `_batch_depth`/`_coordinator_transaction_locked`; migração de mochilas não vazias (`P4`) |
| **Transferência de fonte natural (`ResourceSource` B3.2 + C3.5)** | Sim (`transfer_to_carry_load_with_provenance`, recibos, trava pós-commit `_coordinator_transaction_locked`, `get_provenance_receipt`) | Sim (`b3_2`, `c3_5`, `m1_m10`) | **M7 APROVADO visualmente** | Serialização com `RegionalAuthority` em retries e supressão de eco em `Site._on_unit_carry_load_changed` (`R1`) |
| **Saque reservado → claim (`ReservedWithdrawalCoordinator` C1/C2-R1)** | Sim (ordem fixa de guardas, rollback completo pré-commit, idempotência, recibo em `RegionalAuthority`) | Sim (`c1`, `c2`, `c3_3`) | Coberto em fluxo M6 headless (pendente visual) | Desvinculação controlada da `RegionalAuthority` em `MainScene._exit_tree` (`P1`); fechamento de bypass legado (`P6`) |
| **Entrega seletiva à obra (`SelectiveSiteDeliveryPlanner/Coordinator` C3.1/C3.2)** | Sim (débito estrito por `site_id`, rollback pré-commit, autorização física, recibo regional) | Sim (`c3_1`, `c3_2`, `c3_3`) | M6 headless (pendente visual) | Paridade `get_receipt_in_domain` (`R4`) |
| **Entrega seletiva ao acampamento (`SelectiveCampDeliveryPlanner/Coordinator` C3.4.1–C3.4.2)** | Sim (lotes livres vs. restauração a obra ativa, criação destacada + pós-commit `node_added` seguro, trava em `CampStorageZone`) | Sim (`c3_4_1`, `c3_4_2`) | M3 (com ressalva explicada), M5 headless | Destinos D3 bloqueados propositalmente (`d3_cancellation_not_implemented` → T3.6.3) |
| **Integração opt-in de ordens (`ConstructOrder`, `DeliverToCampOrder`, `GatherResourceOrder`)** | Sim (C3.3, C3.4.3, C3.5 com sessões congeladas, retries `busy`, anti-loop) | Sim (`c3_3`, `c3_4_3`, `c3_5`, `m1_m10`) | **M1 e M7 APROVADOS visualmente**; M4–M6 e M8–M10 pendentes visual | Paridade `cancel_intent` em `ConstructionTransferSession` (`R4`) |
| **Entrada RTS (`CommandController`) e ciclo de cena (`MainScene`)** | **Não integrado** (mantido em legado por escopo) | Regressão legada + M1 | **M1 APROVADO visualmente** | `P1`, `P2`, `P3`, `R3` e decisão `D-INT-01` / `D-INT-03` |
| **Remoção controlada de unidades (`TemporaryTestWorkersController`)** | Parcial (bloqueia mochila não vazia e claims sob `_construction_sites_root`) | Parcial (`c3_5` Cenário 43) | Não testado visualmente em C3.5 | Travas transacionais e varredura por grupo de domínio (`P5`) |
| **Fronteira unificada de obra (`contribute_work`, `authorize_manual_complement`, `try_create_site_from_placement`, `complete_site_transaction`)** | Guardas locais independentes (sem `RegionalAuthority`) | Regressões T3.4/T3.5 | T3.4/T3.5 aceitas na `main` | Integração à `RegionalAuthority` obrigatória antes de `T3.6.3` (`P6`) |

---

## 5. Lacunas concretas com referências aos arquivos e métodos

### 5.1 Bloqueadores atuais (C3.5)
**Nenhum bloqueador atual comprovado.** Nenhuma regressão ou defeito econômico foi encontrado dentro do escopo opt-in aprovado da C3.5.

### 5.2 Pré-requisitos de integração (obrigatórios antes de ativar proveniência no RTS normal)

#### `P1` — `RegionalAuthority` órfã em `World3D` compartilhado após encerramento de `MainScene` *(Vulnerabilidade demonstrável no código)*
- **Arquivos e métodos:**
  - `src/economy/reserved_withdrawal_coordinator.gd`: `_resolve_camp_authority` (`L169-192`), `_resolve_authority` (`L195-211`), `_inspect_camp_economic_domain` (`L464-465`), `_matches_economic_domain` (`L503-504`).
  - `src/main/main.gd`: `_exit_tree` (`L152-166`).
- **Condição de ocorrência:** `RegionalAuthority` é armazenada em `world.set_meta(DOMAIN_META, domains)` com `authority.storage = weakref(storage)`. Todos os testes T3.6.2 isolam cada cena em um `SubViewport` com `own_world_3d = true`, destruindo o `World3D` ao final de cada teste. Porém, no jogo real (e nas suítes `test_t2_playable_economy.gd:60`, `test_t2_worker_cycle.gd:56`, `test_t3_3_ux_flow.gd:26`, `test_commands.gd:27`), `MainScene` roda diretamente sob o `World3D` do `Viewport` raiz. Quando `MainScene._exit_tree()` executa (ex.: `reload_current_scene()`, retorno ao menu e nova partida, ou execução de um segundo teste no mesmo processo), `_ground_pile_manager.cleanup()` libera o `GroundPileManager` antigo, mas **`domains[&"default"]` permanece preso no `World3D` raiz** com `authority.storage.get_ref() == null`. Na segunda `MainScene`, a primeira transação compara `authority.storage.get_ref() != storage_2` (`null != storage_2`) e falha.
- **Consequência econômica/funcional:** Falha permanente (`"ambiguous_domain"`) em **100% das coletas, saques e entregas com proveniência** após recarga de cena ou segunda instância no mesmo `World3D`. Sem perda/duplicação (falha fechada), mas quebra total da jogabilidade após reload e quebra imediata das suítes de integração legadas caso proveniência seja ligada em `MainScene`.

#### `P2` — `CommandController` sem contexto de região, modo opt-in nem formatação de erros de proveniência *(Lacuna estrutural de integração)*
- **Arquivos e métodos:**
  - `src/rts/command_controller.gd`: `_command_gather_resource` (`L172-218`, `L201`), `_command_supply_construction_site` (`L246-282`, `L264`), `configure_economy` (`L43-48`).
  - `src/main/main.gd`: `_ready` (`L47-51`), `_setup_construction` (`L133-140`).
  - `src/buildings/placement_test_overlay.gd`: `_format_command_rejection_reason` (`L690-699`).
- **Condição de ocorrência:** Ao habilitar proveniência em qualquer unidade jogável, `CommandController` continua instanciando `GatherResourceOrder` e `ConstructOrder` com `use_provenance_transactions = false` e sem `region_id`.
- **Consequência:** Cliques direitos em árvores, pedras, arbustos ou canteiros falham imediatamente com `provenance_opt_in_required`; erros de proveniência exibem códigos técnicos crus ao jogador.

#### `P3` — Ausência de contrato de inicialização e unicidade de `provenance_unit_id` em `Unit`, `MainScene` e `TemporaryTestWorkersController` *(Lacuna estrutural + risco de divergência de capacidade)*
- **Arquivos e métodos:**
  - `src/units/unit.gd`: `definition` setter (`L19-25`), `_carry_load` (`L40`), `_sync_definition` (`L110-126`).
  - `src/main/main.gd`: `_ready` (`L39-43`).
  - `src/units/temporary_test_workers_controller.gd`: `_instantiate_worker` (`L209-218`).
  - `src/buildings/construction_site.gd`: `_has_conflicting_unit_identity_pure` (`L1921-1959`).
  - `src/economy/selective_camp_delivery_planner.gd`: `_scan_sites_pure` (`L577-593`).
- **Condição de ocorrência:** `Unit` não habilita proveniência a partir de `character_id`, não valida unicidade de `provenance_unit_id` no mundo/região, e o setter `definition` invoca `_carry_load.set_base_capacity(definition.base_carry_capacity)` sem checar o retorno booleano (se ocorrer sob trava transacional, `definition` muda enquanto `_base_capacity` permanece antiga). Além disso, `_has_conflicting_unit_identity_pure` verifica conflito de `provenance_unit_id` apenas em unidades registradas em canteiros, não em todo o grupo `selectable_units`.
- **Consequência:** Unidades novas (`LeaderA`, `LeaderB`, `Worker3`, `Worker4`) nascem legadas; se duas unidades compartilharem o mesmo `character_id`, todas as transações de construção/entrega falham com `"ambiguous_unit_identity"`.

#### `P4` — Ausência de contrato de admissão/migração atômica para mochilas legadas carregadas e claims ativos *(Pré-requisito de migração / R2-C)*
- **Arquivos e métodos:** `src/economy/unit_carry_load.gd:enable_provenance` (`L290-296`), `src/buildings/construction_site.gd:_clamp_unit_transit_claim` (`L1491-1530`).
- **Condição de ocorrência:** `enable_provenance()` exige mochila estritamente vazia (`_amounts.is_empty() and _unit_weights.is_empty()`). No modo legado, `ConstructionSite._clamp_unit_transit_claim` limita o claim de cada obra isoladamente contra `carry_load.get_amount(res_id)`, permitindo que a soma dos claims entre obras distintas exceda o total carregado ($\sum_s \text{claim}_s(u, r) > \text{carry}_u(r)$) sem rejeição prévia.
- **Consequência:** Não é possível ativar proveniência no meio de uma sessão legada com unidades carregadas ou claims em trânsito sem um serviço dedicado atômico, verificável e fail-closed (detalhado na Seção 6).

#### `P5` — Remoção controlada de trabalhadores temporários sem trava transacional e com escopo restrito de sites *(Vulnerabilidade demonstrável no código)*
- **Arquivos e métodos:** `src/units/temporary_test_workers_controller.gd`: `can_remove_temporary_workers` (`L134-180`), `remove_temporary_workers_safely` (`L183-206`); `src/units/unit.gd`: `_exit_tree` (`L94-101`), `cancel_current_order` (`L261-276`).
- **Condição de ocorrência:** `can_remove_temporary_workers()` verifica apenas `carry.is_empty()` e `site.get_transit_claim_for_unit(worker)` para filhos diretos de `_construction_sites_root`. Não verifica `worker._is_reserved_withdrawal_locked()`, `carry.is_transaction_busy()`, `carry._coordinator_transaction_locked`, `RegionalAuthority.is_executing`, nem `ConstructionSite`s fora de `_construction_sites_root` (ou futuro registro regional de custódia). Se `remove_temporary_workers_safely()` for chamado durante um sinal pós-commit em que a mochila acabou de ficar vazia (`load_changed` em `SelectiveSiteDeliveryCoordinator._publish` ou `SelectiveCampDeliveryCoordinator._publish`), `can_remove_temporary_workers()` aprova a remoção, `worker.cancel_current_order()` é ignorado pela trava (`unit.gd:262`), e o método ainda executa `_units_root.remove_child(worker)` + `worker.queue_free()`. `Unit._exit_tree()` chama `exiting_order.cancel()`, que também retorna cedo sob trava ativa (`deliver_to_camp_order.gd:415`, `construct_order.gd:231`, `gather_resource_order.gd:355`).
- **Consequência econômica/funcional:** No cenário pós-commit com mochila vazia não há perda de recurso imediata, mas viola a pré-condição de remoção sob trava central (R2 §6), deixa a ordem ativa destacada da unidade sem desconectar sinais e abre corrida direta assim que obrigações de custódia D3 existirem na T3.6.3.

#### `P6` — Superfície pública de bypass fora dos coordenadores e operações de obra fora da `RegionalAuthority` *(Pré-requisito de fechamento antes de T3.6.3; avaliar escopo na integração)*
- **Arquivos e métodos:**
  - `src/economy/unit_carry_load.gd:add_with_provenance` (`L358-374`): mutador público que permite criar lotes `FREE_GATHERED` ou `SITE_RESERVED` sem fonte física nem claim, e checa apenas `_provenance_busy` (não `_batch_depth > 0` nem `_coordinator_transaction_locked`).
  - `src/economy/resource_source.gd:extract` (`L189-214`): drena fonte sem destino físico; `transfer_to_carry_load` (`L217-259`) permanece pública para legado.
  - `src/economy/settlement_inventory.gd` (`L169-233`) e `src/economy/ground_pile_manager.gd` (`L312-513`): `deposit`, `deposit_batch`, `withdraw`, `withdraw_batch`, `reserve_batch`, `complement_reservation`, `release_batch`, `withdraw_reserved`, `withdraw_reserved_batch`, `withdraw_reserved_from_pile`, `try_create_pile_at` são públicos e fora de `RegionalAuthority` (embora bloqueados durante transações ativas via `is_locked()` / `is_transaction_busy()`).
  - `src/buildings/construction_manager.gd:try_create_site_from_placement` (`L253-348`) e `complete_site_transaction` (`L163-211`): não adquirem `RegionalAuthority.is_executing` nem `site._is_preparing_or_transacting`. Em `try_create_site_from_placement`, `reserve_batch` (`L301`) publica sinais antes de `site.configure()` (`L318`); em `complete_site_transaction`, `_buildings_root.add_child(building)` (`L185`) e `site.commit_completed_building(building)` (`L204`) executam sem trava regional.
  - `src/buildings/construction_site.gd:contribute_work` (`L374-443`) e `authorize_manual_complement` (`L665-727`): usam guardas locais (`_work_transaction_in_progress`, `_is_complementing`), sem participar da `RegionalAuthority`; em `authorize_manual_complement`, `_plan_manual_complement` executa antes de `_is_complementing = true` e `intent.consumed = true` (`L678`) ocorre antes de checar `inventory.is_transaction_busy()`.
- **Consequência:** Dentro do fluxo normal sem código malicioso, C2/C3.2/C3.4.2 já recusam conflito com `contribute_work`/`authorize_manual_complement` via `site.is_transaction_busy()` e `storage.is_locked()`. Porém, para ativação plena sob os critérios R2 §4/§8 (antes de `T3.6.3`), **`complete_site_transaction`, `try_create_site_from_placement`, `contribute_work`, `authorize_manual_complement` e os bypasses de mochila/armazenamento precisam ser serializados sob a mesma autoridade ou bloqueados contra burla**.

### 5.3 Riscos residuais

#### `R1` — Coleta `ResourceSource` fora de `RegionalAuthority` em retries e eco de sinal em `ConstructionSite` *(Demonstrável no código)*
- **Arquivos e métodos:** `src/economy/resource_source.gd:transfer_to_carry_load_with_provenance` (`L629-692`), `src/units/orders/gather_transfer_session.gd:_execute_locked` (`L233-247`), `src/buildings/construction_site.gd:_on_unit_carry_load_changed` (`L1483-1488`).
- **Condição de ocorrência:** (1) Em retentativa após `busy` (com `_operation_id` já alocado), `GatherTransferSession` chama `source.transfer_to_carry_load_with_provenance` sem reconsultar `RegionalAuthority.is_executing`; (2) `transfer_to_carry_load_with_provenance` emite `carry_load._emit_load_changed()` (`L685`) sem suprimir `_suppress_coordinator_signal_echo` em canteiros onde o trabalhador carrega lotes `SITE_RESERVED`.
- **Consequência econômica/funcional:** Não viola conservação nem altera claims (pois a coleta só aumenta `carry_load`, mantendo `mini(claimed, held_now) == claimed`), mas incrementa espuriamente `Site._transaction_revision` e emite `Site.state_changed` em cada golpe de coleta de um trabalhador com carga mista — podendo causar `"stale_revision"` em planos preparados concorrentes naquela obra e executar observadores da obra sem `RegionalAuthority` travada.

#### `R2` — `DEC-T3.6-SIGNALS-01` pendente (guardas mantidas durante publicação pós-commit)
- **Arquivos:** `reserved_withdrawal_coordinator.gd:929-953`, `selective_site_delivery_coordinator.gd:85-86, 154`, `selective_camp_delivery_coordinator.gd:172-173, 263`, `resource_source.gd:684-691`.
- **Condição e consequência:** Todos os coordenadores e a coleta mantêm guardas cooperativas durante a emissão dos sinais pós-commit. Qualquer observador que tente iniciar imediatamente uma nova transação no mesmo stack recebe `"busy"` (atualmente seguro porque as ordens adiam via `_replan_requested = true`, mas diverge da redação literal de R2 §4). Exige decisão formal (`D-INT-02`).

#### `R3` — `CommandController` contabilizando ordem ignorada por `_is_reserved_withdrawal_locked()` *(Demonstrável no código)*
- **Arquivos e métodos:** `src/units/unit.gd:issue_order` (`L227-229`), `src/units/orders/unit_order.gd:is_active` (`L42-43`), `src/rts/command_controller.gd` (`L160`, `L202-204`, `L265-267`).
- **Condição de ocorrência:** Se `CommandController.command_at()` ou `command_units_to_site()` for chamado sincronamente enquanto `unit._is_reserved_withdrawal_locked()` for `true`, `unit.issue_order(order)` retorna sem iniciar `order`; como `order.status` permanece `PENDING`, `order.is_active()` retorna `true`.
- **Consequência:** Falso positivo em `started_count`, `DestinationMarker` e `command_issued` (sem corrupção econômica). Não ocorre via loop normal de entrada entre frames, apenas em chamadas síncronas a partir de sinais/scripts.

#### `R4` — Assimetrias de sessão em `ConstructionTransferSession` vs. C3.4.3 / C3.5 *(Demonstrável no código)*
- **Arquivos e métodos:** `src/units/orders/construction_transfer_session.gd` (`L25-111`), `src/economy/selective_site_delivery_coordinator.gd:get_receipt` (`L27-33`).
- **Condição e consequência:** Diferente de `CampDeliveryTransferSession` e `GatherTransferSession`, `ConstructionTransferSession` não possui trava definitiva `cancel_intent(...)` (usa `clear()`, descartando `_operation_id`), `SelectiveSiteDeliveryCoordinator` não expõe `get_receipt_in_domain(world, region_id, op)` (depende de `_last_authority()`), e `withdraw()` não congela `_pile_id`/`_resource_id`/`_amount` dentro de `_identity`. Em `ConstructOrder` real o impacto é mitigado porque cancelamentos e erros encerram a ordem, mas convém alinhar antes de T3.6.3.

#### `R5` — Remoção bruta de nós (`free`/`remove_child`) e teardown não controlado *(Limitação técnica conhecida de R2-D)*
- **Arquivos e métodos:** `src/units/unit.gd:_exit_tree` (`L94-101`), `src/economy/resource_source.gd:_prune_invalid_workers` (`L398-405`), `src/economy/ground_pile_manager.gd:cleanup` (`L131-145`), `src/buildings/construction_site.gd:_exit_tree` (`L105-119`).
- **Detalhes observados:** (a) `ResourceSource._prune_invalid_workers()` testa `is_instance_valid(obj)` sem testar `is_inside_tree()`, logo uma unidade removida via `remove_child` durante trava transacional reteria o slot na fonte até ser liberada (`free`); (b) `GroundPileManager.cleanup()` checa `_is_preparing_withdrawal` mas não `_is_mutating`/`_is_notifying`; (c) `Unit._exit_tree` não impede perda de carga em `free()` externo arbitrário ou encerramento abrupto do processo (persistência é escopo de `T3.8`).

#### `R6` — Cobertura visual/manual pendente para M4–M6 e M8–M10
- Conforme evidências recebidas, M1 e M7 foram aprovados visualmente pelo proprietário; M4–M6 e M8–M10 seguem com `AUTO_PASS` headless sem homologação visual interativa. Não há defeito concreto exigindo novos testes manuais nesta etapa C4.1.

### 5.4 Melhorias opcionais
- **`M1-OPT` — Isolar hooks de injeção de falha de produção:** `fault_injection_hook` (`reserved_withdrawal_coordinator.gd:8`), `_fault_at` (`selective_site_delivery_coordinator.gd:11`, `selective_camp_delivery_coordinator.gd:18`) e `pile_creator_override`/`site_creator_override`/`building_creator_override` podem migrar no futuro para indireção virtual via subclasse de teste (padrão já adotado em `GatherTransferSession._invoke_source_transfer` e `CampDeliveryTransferSession._invoke_coordinator`).
- **`M2-OPT` — Checar `_batch_depth > 0` e `_coordinator_transaction_locked` em `UnitCarryLoad.enable_provenance` (`L290`) e `add_with_provenance` (`L359`).**

---

## 6. Avaliação de migração de mochilas e claims (Questão B)

### 6.1 Estado atual observado no código
- `UnitCarryLoad.enable_provenance(unit_id)` (`src/economy/unit_carry_load.gd:290-296`) rejeita qualquer mochila com `_amounts` ou `_unit_weights` não vazios.
- Não existe nenhuma API de migração de mochilas carregadas, tampouco inventário consolidado de claims entre todos os `ConstructionSite`s de uma região.
- No modo legado, `ConstructionSite._clamp_unit_transit_claim` (`construction_site.gd:1491-1530`) valida apenas $\text{claim}_s(u, r) \le \text{carry}_u(r)$ obra a obra, sem validar $\sum_{s} \text{claim}_s(u, r) \le \text{carry}_u(r)$.

### 6.2 Contratos que faltam para uma migração atômica, verificável e fail-closed (se exigida para sessões legadas carregadas)

| Dimensão | Cenário a suportar / recusar | Contrato necessário (ainda ausente) |
| --- | --- | --- |
| **Escopo e atomicidade** | Sessão regional com $N$ unidades e $M$ canteiros. | Adquirir guardas cooperativas de toda a região (`RegionalAuthority`, todos os sites do domínio, `inventory`, `storage`, `camp_zone`, todas as `UnitCarryLoad` alvo em ordem determinística); preparar plano completo puro antes de mutar qualquer mochila; aplicar silenciosamente ou fazer rollback integral em falha (nunca deixar migração parcial). |
| **Identidade de unidades** | Unidades sem `character_id`, duplicadas ou compartilhando `UnitCarryLoad`. | Exigir `unit_id` válido e único entre todas as `Unit` vivas no mundo/região (não apenas em canteiros) e relação 1:1 `Unit ↔ UnitCarryLoad`; falhar fechado com `ambiguous_unit_identity`. |
| **Reconciliação de claims multi-obra** | Unidade carregando materiais de Obra A, Obra B e coleta livre do mesmo recurso. | Somar claims por `(unit, resource_id)` em **todos** os `ConstructionSite` do domínio: exigir cada site `ACTIVE` com `generation > 0`, `site_id`/`reservation_id` únicos, `listener` conectado e invariante contábil válida; criar lotes `SITE_RESERVED` exatos por `(site_id, generation)` e **somente o excedente** $\text{carry}_u(r) - \sum_s \text{claim}_s(u, r) > 0$ como `FREE_GATHERED`. |
| **Estados ambíguos (recusa obrigatória)** | $\sum_s \text{claim}_s(u, r) > \text{carry}_u(r)$; claim em site não `ACTIVE` ou fora do domínio; peso divergente da `ResourceDefinition`; `_amounts.size() != _unit_weights.size()`; unidade em ordem legada em execução crítica ou com `_pending_pickups` inconsistente; backend `InMemoryStorageSource`. | Recusar integralmente antes da primeira mutação, sem alterar mochilas, pilhas ou claims e sem emitir sinais, retornando diagnóstico estruturado. |
| **Capacidade variável e sobrecarga** | Unidade legada com modificadores (`_capacity_modifiers`) ou sobrecarregada (`get_current_weight() > get_effective_capacity()`). | **Não** construir a migração chamando `add_with_provenance` (que rejeita `amount > get_max_additional_for`). Construir o `CarryProvenanceLedger` validando `validate_aggregate(unit_id, _amounts)` e preservando `_base_capacity`, `_capacity_modifiers`, `_amounts` e `_unit_weights` intactos (já confirmado no código que `SelectiveSiteDeliveryPlanner` e `SelectiveCampDeliveryPlanner` suportam descarregar mochilas sobrecarregadas). |
| **Idempotência** | Reinvocação da migração na mesma sessão. | Registrar recibo/estado de migração na `RegionalAuthority` (ou tratar unidade já com proveniência validada como no-op verificado apenas se reconciliada). |

**Nota prática:** Se a ativação no RTS normal ocorrer exclusivamente em **partidas/cenas novas com mochilas inicialmente vazias** (`D-INT-03` Opção A), `enable_provenance` em mochilas vazias já cobre o boot limpo sem converter carga alguma — porém a migração de sessões legadas carregadas permanece obrigatória para cumprir integralmente o requisito de admissão/migração de R2 §5 caso sessões legadas em memória precisem ser promovidas.

---

## 7. Avaliação de reentrância, sinais e atomicidade (Questões C e D)

### 7.1 Mapa completo de mutadores e proteções observadas

| Alvo | Mutadores reais em `src/` | Passa por coordenador? | Proteção contra reentrância em sinais | Risco demonstrável vs. hipotético |
| --- | --- | --- | --- | --- |
| **Mochila (`UnitCarryLoad`)** | Legado: `add_units`, `add_resource`, `remove_units`, `take_all`, `restore_load_snapshot`. Opt-in: `add_with_provenance` (público!), `_apply_prepared_provenance_add`, mutação direta sob guarda pelos coordenadores C3.2/C3.4.2. Capacidade: `set_base_capacity`, `set_capacity_modifier`, `remove_capacity_modifier`. | Apenas C2/C3.2/C3.4.2 e `ResourceSource` usam protocolo transacional; `add_with_provenance` é bypass público. | `_provenance_busy` bloqueia `add_with_provenance` e `transfer_to_carry_load_with_provenance`; `_coordinator_transaction_locked` bloqueia `set_base_capacity`, modificadores, `begin_batch/end_batch` e `Unit.issue_order/cancel_current_order`. | **Demonstrável (`P6`):** chamada direta a `add_with_provenance` fora de transação cria material sem lastro físico. **Demonstrável (`P3`):** `Unit.definition` setter ignora retorno `false` de `set_base_capacity`. |
| **Fonte natural (`ResourceSource`)** | `extract`, `transfer_to_carry_load`, `transfer_to_carry_load_with_provenance`, `configure`, setters `@export`. | `transfer_to_carry_load_with_provenance` usa trava própria + `carry_load` (`_is_transferring`, `_provenance_busy`, `_coordinator_transaction_locked`), mas **não** `RegionalAuthority`. | Bloqueia reentrância na própria fonte e na mochila durante `load_changed`/`amount_changed`/`depleted`. | **Demonstrável (`R1`):** não suprime `_on_unit_carry_load_changed` em `ConstructionSite`s onde a unidade tem claim, gerando bumps de revisão/sinais na obra; retries não verificam `authority.is_executing`. **Demonstrável (`P6`):** `extract()` drena fonte sem destino. |
| **Estoque e pilhas (`SettlementInventory`, `GroundPileManager`, `GroundResourcePile`)** | Coordenadores: `_apply_prepared_pile_withdrawal_silent`, `_apply_camp_delivery_*_silent`. Legado/público: `deposit*`, `withdraw*`, `reserve_batch`, `complement_reservation`, `release_batch`, `try_create_pile_at`, `step_decay`, `cleanup`, `deliver_from_carry_load`, `withdraw_reserved_from_pile_to_carry_load`. | Somente C2 e C3.4.2 usam `RegionalAuthority`; demais são diretos. | `GroundPileManager.is_locked()` (`_is_mutating or _is_notifying or _is_preparing_withdrawal`) e `SettlementInventory.is_transaction_busy()` bloqueiam todos os mutadores públicos durante C2/C3.2/C3.4.2. `GroundResourcePile` bloqueia setters via `_is_coordinator_locked()`. `CampStorageZone` bloqueia setters via `_coordinator_transaction_locked` durante C3.4.2. | **Demonstrável (C3.4.2 corrigido em `cabcb6c`):** remoção bruta via `SceneTree.node_added` não dá crash e falha fechado na operação seguinte (`invalid_physical_pile_collection`). **Demonstrável (`P1`):** `cleanup()` não libera `RegionalAuthority` do `World3D`. **Demonstrável (legado):** `withdraw_reserved_from_pile_to_carry_load` emite sinais antes de `record_withdrawn_for_site`. |
| **Canteiro (`ConstructionSite`) e `ConstructionManager`** | Coordenadores: `_apply_prepared_claim_silent` (C2), mutação direta de `_delivered_buffer`/`_transit_claims` (C3.2/C3.4.2). Diretos: `record_withdrawn_for_site`, `accept_delivery_from_carry_load`, `contribute_work`, `authorize_manual_complement`, `claim_pickup`, `register_worker`, `unregister_worker`, `commit_completed_building`, `try_create_site_from_placement`, `complete_site_transaction`. | Somente C2, C3.2 e C3.4.2 passam por `RegionalAuthority`. | `site.is_transaction_busy()` cobre `_work_transaction_in_progress or _is_complementing or _is_preparing_or_transacting`; todos os coordenadores checam o site alvo e `peer_sites`. | **Demonstrável (`P6`):** `complete_site_transaction` e `try_create_site_from_placement` não adquirem `RegionalAuthority` nem `site._is_preparing_or_transacting`. **Hipotético hoje / real em T3.6.3:** corrida conclusão × cancelamento D3 se `complete_site_transaction` não for serializada na mesma autoridade. |

### 7.2 Verificação da conservação física (Questão D)
Confirmado diretamente no código dos fluxos opt-in implementados até C3.5:
1. **Zero crédito antes da chegada:**
   - `GatherResourceOrder` nunca deposita no inventário; delega a `DeliverToCampOrder` seletivo, que exige caminhada real na NavMesh, chegada física e `TxHelpers.check_physical_authorization_participants` (distância `<= 0,35 m`, `|Δy| <= 0,85 m`, linha física livre sem parede) antes do commit.
   - `ConstructOrder` exige `BuildSlotPlanner.is_unit_in_pile_reach` (saque) e `BuildSlotPlanner.is_unit_in_site_dropoff_range` (entrega) dentro dos coordenadores sob guardas ativas.
2. **Zero duplicação e resultado incerto:**
   - C2, C3.2, C3.4.2 e `ResourceSource` registram recibos antes dos sinais e retornam `replayed = true` com delta `0` em repetições idênticas, rejeitando divergências com `operation_conflict` ou `duplicate_lot`.
   - `CampDeliveryTransferSession` e `GatherTransferSession` congelam `operation_id`, nunca alocam segundo serial em `busy` nem em resultado incerto, consultam recibo e só incrementam contadores de viagem/extração quando `not replayed and delta > 0`.
3. **Zero perda silenciosa e isolamento entre obras:**
   - Cancelamento ou substituição por `MoveOrder` em qualquer fase preserva integralmente lotes `FREE_GATHERED` e `SITE_RESERVED`, pesos e claims, e libera slots de `ResourceSource` e `pending_pickups` de `ConstructionSite`.
   - `SelectiveSiteDeliveryPlanner` debita estritamente lotes do `site_id` alvo; `SelectiveCampDeliveryPlanner` restaura `SITE_RESERVED` estritamente à reserva da própria obra ativa (nunca em estoque livre) e bloqueia obras não ativas (`d3_cancellation_not_implemented`).
4. **Limites de ciclo de vida:**
   - Remoção controlada (`TemporaryTestWorkersController`) precisa do endurecimento `P5`.
   - Teardown de cena em `World3D` compartilhado precisa de `P1`.
   - Destruição externa arbitrária (`free()`/`remove_child()` fora de rotas controladas) e encerramento de processo permanecem fora de garantia até governança de teardown/persistência `T3.8` (sem antecipar `T3.8`).

---

## 8. Comparação com a arquitetura T3.6-R2 (Questão E)

Confronto entre os requisitos propostos em `docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` (§4, §5, §6, §8) para **T3.6.2** e o estado real da branch `feat/t3-6-2-provenance-transactions` (`a19c48b`):

| Requisito proposto na R2 para T3.6.2 | Estado real no código (`a19c48b`) | Lacuna exata antes de `T3.6.3` |
| --- | --- | --- |
| **Proveniência em todos os caminhos T2–T3.5.2** (coleta, saque reservado, entrega à obra, descarga seletiva, `ConstructOrder`) | **Implementado e testado em modo opt-in** (B2, B3.2, C1–C3.5). | Ainda **não ativado** no caminho RTS normal (`CommandController` + `MainScene` + `TemporaryTestWorkersController` → `P1`, `P2`, `P3`). |
| **Invariante de soma de lotes igual à mochila e isolamento entre obras** | **Implementado e testado** em todos os planejadores, coordenadores e suítes C2–C3.5. | Nenhuma lacuna nos fluxos opt-in; manter fechamento contra bypasses (`P6`). |
| **Coordenador/autoridade regional com ordem fixa de guardas, snapshot, rollback completo e idempotência** | **Implementado e testado** para saque reservado (C2-R1), entrega à obra (C3.2) e descarga seletiva ao acampamento (C3.4.2). | Falta ciclo de vida de `RegionalAuthority` em `World3D` compartilhado (`P1`), serialização regional de `ResourceSource` em retries (`R1`) e paridade em `ConstructionTransferSession` (`R4`). |
| **Fronteira transacional em complemento, trabalho, criação e conclusão (`contribute_work`, `authorize_manual_complement`, `complete_site_transaction`)** | **Parcial:** guardas locais independentes; não participam da `RegionalAuthority`. | **Obrigatório antes de T3.6.3 (`P6`):** serializar `complete_site_transaction` (concorrência conclusão × D3), `authorize_manual_complement`, `contribute_work` e `try_create_site_from_placement` sob a mesma autoridade regional/revisões. |
| **Política de sinais após commit sem callbacks sob estado parcial** | Commit atômico sempre ocorre antes dos sinais; guardas permanecem mantidas durante publicação (política provisória). | Resolver formalmente `DEC-T3.6-SIGNALS-01` (`D-INT-02`). |
| **Sem API antiga capaz de burlar participantes** | APIs legadas recusam mochilas com proveniência, mas `UnitCarryLoad.add_with_provenance`, `ResourceSource.extract`, `SettlementInventory`/`GroundPileManager` mutadores diretos seguem públicos. | Definir/fechar fronteira de acesso público (`P6`) antes de declarar blindagem total para T3.6.3. |
| **Migração conciliável e bloqueio de estado ambíguo** | Bloqueio fail-closed existe (`enable_provenance` exige mochila vazia), mas não há migrador de mochilas carregadas/claims. | Decidir escopo (`D-INT-03`) e, se necessário para sessões legadas em memória, implementar migrador atômico fail-closed (`P4`). |
| **Remoção controlada de unidades bloqueada sob guarda central** | `TemporaryTestWorkersController` bloqueia mochila não vazia e claims em `_construction_sites_root`, sem checar travas transacionais nem sites fora da raiz padrão. | Endurecer `TemporaryTestWorkersController` (`P5`). |
| **Sem commit D3, custódia ou UI de cancelamento acessíveis** | **Atendido estritamente:** `d3_cancellation_not_implemented` bloqueia devolução de lotes de obras não ativas; nenhum commit D3 ou botão D3 existe. | Preservar bloqueio até autorização formal de `T3.6.3`. |

### Condições precisas que faltam antes de iniciar `T3.6.3`
1. Fechar **`P1`** (ciclo de vida controlado de `RegionalAuthority` em `World3D` compartilhado) e **`P5`** (remoção controlada sob trava transacional e varredura de domínio).
2. Decidir **`D-INT-01`**, **`D-INT-02`** (`DEC-T3.6-SIGNALS-01`) e **`D-INT-03`**.
3. Integrar e validar proveniência no fluxo RTS normal (`P2`, `P3`, e `P4` caso escolhida Opção B de `D-INT-03`), garantindo regressão completa T1–T3.5.2.
4. Estender a autoridade regional (`RegionalAuthority`) para serializar `complete_site_transaction`, `authorize_manual_complement`, `contribute_work` e `try_create_site_from_placement` (`P6`), alinhar `R1`/`R4` e restringir bypasses públicos (`add_with_provenance` / mutadores diretos em modo proveniência).

---

## 9. Decisões pendentes (Questão F — somente as indispensáveis)

Todas as decisões vigentes do GDD v1.2 permanecem integralmente preservadas (transporte físico obrigatório D2; recursos reservados jamais consumidos por outra obra; complementação manual obrigatória DEC-11B; zero realocação automática silenciosa; pedra sem deterioração temporal DEC-11A). Apenas **três** decisões de design/governança afetam diretamente os incrementos de integração (`C4.2+`) e exigem escolha expressa do proprietário:

### `D-INT-01` — Política do RTS normal para trabalhador com lote `SITE_RESERVED` da Obra B redirecionado à Obra A
Hoje não existe comando manual de "entregar no acampamento" na UI RTS (GDD v1.2 §9.1 marca como `PROPOSTA` opcional). Quando a proveniência for ativada no `CommandController`:
- **Opção A (Conservadora — `return_other_site_reserved = false`):** o trabalhador mantém o lote de B na mochila; se puder carregar/entregar para A na capacidade restante, prossegue; se virar `BUILDER` ou não tiver espaço, a ordem em A falha com diagnóstico legível e o jogador precisa primeiro mandá-lo entregar na Obra B. *Prós:* máxima conservação de intenção do jogador. *Contras:* sem comando manual de descarga ao acampamento, não há forma de devolver o lote de B às pilhas reservadas de B sem entregá-lo em B.
- **Opção B (Retorno físico automático à reserva de origem — `return_other_site_reserved = true`):** ao ser designado à Obra A, o trabalhador caminha fisicamente até a `CampStorageZone`, restaura o lote de B **estritamente na reserva física de B** (nunca convertendo em estoque livre nem transferindo para A) e então atende a Obra A. *Prós:* fluxo RTS fluido sem travar o jogador e sem violar D2 ou isolamento de reservas. *Contras:* um clique em A gera uma viagem prévia de devolução ao acampamento.
- **Opção C (Adicionar comando manual explícito de retorno ao acampamento + manter `false`):** mantém comportamento conservador e adiciona interação RTS/UI para descarregar ao acampamento. *Prós:* controle manual explícito. *Contras:* promove a `PROPOSTA` de comando manual do GDD v1.2 §9.1, ampliando escopo de UX/HUD.

### `D-INT-02` — Ratificação de `DEC-T3.6-SIGNALS-01` (guardas durante sinais pós-commit)
- **Opção A (Ratificar política atual):** manter guardas cooperativas durante publicação pós-commit (C2-R1/C3.2/C3.4.2/C3.5), onde observadores reentrantes recebem `"busy"` e ordens replanejam no próximo tick físico. *Prós:* já provada em 410 testes sem corrida ou estado parcial. *Contras:* exige documentar a divergência frente ao texto original da proposta R2 §4.
- **Opção B (Liberar guardas antes dos sinais):** alterar todos os coordenadores e `ResourceSource` para soltar guardas antes de emitir sinais. *Prós:* aderência literal ao rascunho R2 §4. *Contras:* alto risco de reentrância recursiva em observadores e necessidade de reauditar C2–C3.5.

### `D-INT-03` — Estratégia de ativação gradual vs. migração de mochilas legadas carregadas
- **Opção A (Ativação limpa em sessões novas primeiro, com flag opt-in na cena/controlador):** habilitar proveniência apenas na criação de unidades vazias em `MainScene`/`TemporaryTestWorkersController` (mantendo recusa fail-closed em mochilas legadas carregadas), deixando eventual migrador de sessões legadas carregadas apenas se houver caso real que exija promover uma sessão em andamento.
- **Opção B (Implementar migrador atômico de mochilas carregadas antes de integrar `CommandController`/`MainScene`):** construir o serviço transacional de migração da Seção 6 (`P4`) antes de conectar o fluxo RTS normal.

---

## 10. Proposta de um único próximo incremento pequeno (`T3.6.2-C4.2`)

**Nome proposto:** `T3.6.2-C4.2` — *Ciclo de vida controlado de domínio regional e guarda transacional na remoção segura de trabalhadores*

*(Independente das decisões `D-INT-01`–`D-INT-03`; não ativa proveniência globalmente; não altera comportamento legado padrão.)*

### Objetivo e escopo estrito
Resolver os dois pré-requisitos estruturais de ciclo de vida (`P1` e `P5`) — além da verificação defensiva em `CommandController` (`R3`) — que bloqueiam qualquer ativação segura em `MainScene` real, mantendo proveniência **desligada por padrão** no RTS normal.

1. **Ciclo de vida da `RegionalAuthority` (`P1`):** adicionar em `ReservedWithdrawalCoordinator` um método interno controlado de desvinculação de domínio regional (ex.: `_release_domain_for_storage(world, region_id, storage)`), que **somente** remove a entrada do `World3D` se `authority.storage.get_ref() == storage`, `not authority.is_executing` e o `GroundPileManager` estiver em encerramento controlado (`MainScene._exit_tree()`). Preservar 100% a rejeição fail-closed `"ambiguous_domain"` caso alguém tente trocar `storage` no meio de uma sessão ativa sem encerramento do domínio anterior.
2. **Guarda transacional na remoção de trabalhadores temporários (`P5`):** endurecer `TemporaryTestWorkersController.can_remove_temporary_workers()` e `remove_temporary_workers_safely()` para:
   - recusar remoção se qualquer trabalhador alvo estiver sob `_is_reserved_withdrawal_locked()`, `carry.is_transaction_busy()`, `carry._coordinator_transaction_locked`, ou se a `RegionalAuthority` do domínio estiver `is_executing`;
   - consultar `ConstructionSite`s via grupo `ConstructionSite.GROUP_CONSTRUCTION_SITES` no mesmo `World3D` (além de `_construction_sites_root`), garantindo que claims fora da raiz padrão também bloqueiem remoção;
   - revalidar imediatamente antes de `remove_child`/`queue_free` e abortar se `cancel_current_order()` não encerrar a ordem ativa.
3. **Verificação defensiva em `CommandController` (`R3`):** ao chamar `unit.issue_order(order)`, só contabilizar `started_count` se `unit.get_current_order() == order` (ou `order.is_succeeded()` para ordens concluídas instantaneamente), evitando falso positivo caso `issue_order` seja rejeitado por trava transacional.

### Arquivos prováveis
- `src/economy/reserved_withdrawal_coordinator.gd`
- `src/main/main.gd`
- `src/units/temporary_test_workers_controller.gd`
- `src/rts/command_controller.gd`
- `tests/integration/test_t3_6_2_c4_2_lifecycle_readiness.gd` *(nova suíte focada)*

### Riscos e mitigações
- **Risco:** liberar indevidamente `RegionalAuthority` durante uma sessão ativa, enfraquecendo a proteção de replay/unicidade testada em `test_r1_regions_worlds_and_domain_lifetime`.
  - **Mitigação:** exigir correspondência exata de `storage`, `not authority.is_executing`, ausência de `ConstructionSite`s ativos no domínio apontando para aquele `storage`, e executar somente em `MainScene._exit_tree()` após `_ground_pile_manager.cleanup()`. Manter intacto o teste `test_r1_regions_worlds_and_domain_lifetime`.
- **Risco:** alterar comportamento legado da remoção de `Worker3`/`Worker4` em `test_t3_3_ux_flow` ou `test_t3_3_ux_display_and_workers`.
  - **Mitigação:** quando trabalhadores estão vazios e fora de transação ativa, o comportamento permanece idêntico; validar com regressão direcionada e segmentada.

### Critérios objetivos de aceite
1. Duas instâncias sequenciais de `MainScene` montadas diretamente sob o mesmo `World3D` (sem `SubViewport` separado) executam coleta, saque, entrega à obra e entrega ao acampamento com proveniência opt-in com `100%` de sucesso, sem `"ambiguous_domain"`.
2. Tentativa de substituir `GroundPileManager` no meio de uma sessão ativa (sem teardown controlado) continua falhando fechado com `"ambiguous_domain"`.
3. `TemporaryTestWorkersController.remove_temporary_workers_safely()` recusa remoção durante trava transacional/sinal pós-commit (mesmo com mochila vazia) e quando existir claim em `ConstructionSite` fora de `_construction_sites_root`, e continua removendo normalmente trabalhadores vazios ociosos.
4. `CommandController` não contabiliza nem emite `command_issued` se `unit.issue_order()` recusar uma ordem sob `_is_reserved_withdrawal_locked()`.
5. Modo legado permanece padrão (`use_provenance_transactions = false`); `validate.ps1` e `run_tests.ps1 -Segmented` passam com `0` erros e `0` avisos.

---

## 11. Conclusão

**Veredito:** **PRONTO COM PRÉ-REQUISITOS**

### Significado preciso do status
- **O que está pronto:** A infraestrutura de proveniência implementada até **T3.6.2-C3.5** (`CarryProvenanceLedger`, `UnitCarryLoad`, `ResourceSource` B3.2/C3.5, `ReservedWithdrawalCoordinator`, `SelectiveSiteDeliveryCoordinator`, `SelectiveCampDeliveryCoordinator`, e integrações opt-in de `ConstructOrder`, `DeliverToCampOrder` e `GatherResourceOrder`) não apresentou nenhum **BLOQUEADOR ATUAL** dentro do seu escopo aprovado. A conservação física, a separação entre modos legado e opt-in, a idempotência/replay, o rollback pré-commit e a proteção anti-loop estão sólidos no código auditado.
- **O que impede ativação global imediata (pré-requisitos obrigatórios):**
  1. Ciclo de vida da `RegionalAuthority` em `World3D` compartilhado (`P1`), que causaria `"ambiguous_domain"` em qualquer recarga de cena ou segundo teste em `MainScene`;
  2. Integração de despacho, `region_id` e feedback de rejeição em `CommandController` (`P2`) e inicialização/unicidade de `provenance_unit_id` em `Unit`/`MainScene`/`TemporaryTestWorkersController` (`P3`);
  3. Endurecimento da remoção controlada de trabalhadores sob travas transacionais (`P5`);
  4. Decisões expressas do proprietário em `D-INT-01`, `D-INT-02` e `D-INT-03` (incluindo necessidade ou não de migrador de mochilas legadas carregadas `P4`);
  5. Antes de iniciar **T3.6.3** (fora do escopo imediato da integração RTS), serialização de `complete_site_transaction`, `authorize_manual_complement`, `contribute_work`, `try_create_site_from_placement` sob a `RegionalAuthority` e fechamento dos bypasses públicos (`P6`).

**Próximo passo:** Aguardar revisão do proprietário e do ChatGPT sobre este relatório, as decisões `D-INT-01`–`D-INT-03` e a autorização expressa antes de implementar o incremento `T3.6.2-C4.2` ou qualquer código adicional.
