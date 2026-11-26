# Dawn of Kin — Relatório Técnico da Candidata `R-03A D3.3`
## Conservação Econômica Regional (`D0-A04`) e Reconciliação de Compatibilidade Histórica

**Data:** 26/11/2026  
**Etapa:** `R-03A D3.3` *(incremento intermediário autorizado de prova formal de conservação econômica regional `D0-A04` e reconciliação de testes históricos afetados pelo ciclo de derrubada `D3`)*  
**Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**SHA base homologado (`D3.2`):** `a0bf3aec15ef1ec405f2ed93008e565a62f27ed2`  
**SHA final publicado:** registrado em `06_git_depois.txt` no acervo de evidências *(commit único exclusivo na branch candidata; `HEAD == origin/feat/r-03a-community-work-main-scene`)*  
**Base canônica preservada (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2` *(não alterada)*  
**Linha estável preservada (`main`):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` *(não alterada)*  
**Checkout principal preservado:** `C:\Projetos\Dawn of Kin` *(em `develop`, preservando integralmente `M project.godot`)*  
**Godot:** `4.7.2.stable.official.ed1daf0bf`  
**Status obrigatório:** **`IMPLEMENTADO`** · **`VALIDADO TECNICAMENTE`** · **`PENDENTE DE AUDITORIA INDEPENDENTE`** · **`NÃO HOMOLOGADO`** · **`NÃO INTEGRADO À DEVELOP`**

> [!IMPORTANT]
> Este incremento **NÃO** declara homologação definitiva de `D0-A04`, **NÃO** encerra `D3`, **NÃO** promove alterações para `develop` ou `main` e **NÃO** executa `D3.4`, `D4` ou `R-03B` (que permanecem bloqueadas). Nenhum arquivo de produção (`src/`, `data/`, `assets/`), nem `docs/Dawn_of_Kin_GDD.md`, nem o comportamento registrado em `HD3-06` foram modificados nesta missão. A reconciliação documental definitiva da substituição da fórmula original do §7.4 da `D0` pela decisão homologada `D0-A04` permanece registrada de forma aditiva sem apagar o histórico original.

---

## 1. Escopo Autorizado e Contratos Preservados

A partir da homologação intermediária de `D3.2` (`a0bf3aec15ef1ec405f2ed93008e565a62f27ed2`, com os 8 testes humanos `HD3-01`–`HD3-08` aprovados), foi autorizada exclusivamente a **`D3.3`**:
1. Prova formal verificável de conservação econômica regional **`D0-A04`** por domínio `(World3D, region_id, resource_id)`, complementada por deltas individuais por compartimento e operação.
2. Auditoria de propriedade das quantidades físicas no código real de produção e prova de ausência de dupla contagem.
3. Reconciliação determinística e transparente dos testes históricos afetados pelo novo contrato `D3` de corte e derrubada de árvores.
4. Correções focais apenas se comprovada violação real dentro do escopo — **nenhuma violação de produção foi comprovada; zero arquivos em `src/` foram modificados**.

Todos os contratos anteriores permanecem intactos: `D0-A03`, corte provisório de `2,5 s`, rendimento combinado de dois cortadores de `1,5×`, queda provisória de `0,50 s`, zero extração de madeira antes de `FALLEN`, congelamento sustentado por autorização legítima, reset pré-queda, `D3.1-A01`, uma atribuição por tarefa comunitária, soberania de ordens pessoais, observação `HD3-06` preservada para `R-03B`, cancelamento seletivo `D2`, transporte/entrega físicos, proveniência/atomicidade/idempotência/autoridade regional e construção legada em transição segura `P-REC-1` (`use_d2_2_hud = false`, `use_provenance_economy = true`, `automatic_cancellation_recovery = true`).

---

## 2. Fórmula Formal de Conservação Regional (`D0-A04`)

Em substituição à comparação simplificada do §7.4 da `D0` (que comparava indevidamente uma árvore individual com o estoque comunitário inteiro — preservada historicamente sem apagamento), aplica-se a identidade formal por domínio regional $D = (\text{World3D}, \text{region\_id})$ e recurso $r$:

$$Q_{\text{final}}(D, r) = Q_{\text{inicial}}(D, r) + \text{Entradas}(D, r) - \text{Saídas}(D, r) - \Delta \text{PerdasLegítimas}(D, r)$$

Em cenários fechados ($\text{Entradas} = 0$, $\text{Saídas} = 0$, $\Delta\text{PerdasLegítimas} = 0$):

$$Q_{\text{final}}(D, r) = Q_{\text{inicial}}(D, r)$$

Onde a quantidade física total $Q(D, r)$ é a soma exata de **8 compartimentos físicos mutuamente exclusivos**:

$$Q(D, r) = Q_{\text{sources}} + Q_{\text{carry}} + Q_{\text{camp}} + Q_{\text{site\_buf}} + Q_{\text{site\_cons}} + Q_{\text{buildings}} + Q_{\text{cancel\_buf}} + Q_{\text{cancel\_inc}}$$

E as perdas legítimas acumuladas são obtidas **exclusivamente de fontes independentes** (nunca derivadas por $Q_{\text{inicial}} - Q_{\text{final}}$):

$$\text{PerdasLegítimas}(D, r) = \text{DecayLosses}(D, r) + \text{DemolitionLosses}(D, r)$$

---

## 3. Matriz de Propriedade das Quantidades Físicas (Auditoria do Código Real)

Auditoria direta sobre `src/economy/*`, `src/buildings/*`, `src/rts/*`, `src/units/*` e `src/main/main.gd`:

| # | Compartimento Físico | Objeto Proprietário | API de Leitura | Identidade Regional | Registros Derivados / Espelhados (NÃO somar em $Q$) | Risco de Dupla Contagem | Transições de Entrada / Saída |
|---|---|---|---|---|---|---|---|
| 1 | `natural_sources` | `ResourceSource` (grupo `resource_sources`) | `get_remaining_amount()` | `get_world_3d()` + meta `region_id` (default `&"default"` em `R01`) | `initial_amount`, estágios `STANDING`/`CHOPPING`/`FELLING`/`FALLEN` | Somar `initial_amount` ou contar estágios como saldo separado | Saída: `extract()` / `transfer_to_carry_load()` / `transfer_to_carry_load_with_provenance()` (madeira somente em `FALLEN`) |
| 2 | `unit_carry_loads` | `UnitCarryLoad` de cada `Unit` (grupo `selectable_units`) | `get_amount(r)` | `unit.get_world_3d()` + meta `region_id` (deduplicado por `unit` e `carry_load` ID) | `CarryProvenanceLedger` (`provenance_snapshot()`), peso (`get_current_weight()`), `ConstructionSite._transit_claims`, `CancellationCustodyRecord.in_transit_remaining` (`H`) | Somar `CarryProvenanceLedger`, `in_transit_remaining` ou `_transit_claims` junto com `UnitCarryLoad` | Entrada: extração de fonte, `ReservedWithdrawalCoordinator`, `CancellationRecoveryTransaction`; Saída: `SelectiveCampDeliveryCoordinator`, `SelectiveSiteDeliveryCoordinator`, `deposit_to_inventory()` |
| 3 | `camp_storage` | `SettlementStorageSource` (`GroundPileManager` na `MainScene`) | `storage.get_physical_amount(r)` (soma de `_piles`) | `RegionalAuthority.storage` + `bound_world`/`bound_region` + `_piles_root.get_world_3d()` | `SettlementInventory.get_physical_amount()` (delega ao mesmo `storage`), `PileReservationLedger` (`get_reserved_amount()`), `get_available_amount()`, `GroundResourcePile.amount` individual | Somar `SettlementInventory` + `GroundPileManager`, somar reservas (`reserved`), ou somar pilhas individuais + total do gerenciador | Entrada: entrega física / `deposit()`; Saída: retirada reservada, `withdraw()`, deterioração (`_record_decay()` → `get_total_decayed()`) |
| 4 | `construction_sites_buffer` | `ConstructionSite` (grupo `construction_sites`, estados `ACTIVE`, `COMPLETING`, `COMPLETION_FAILED_RETRYABLE`, `COMPLETION_BLOCKED_ERROR`) | `get_delivered_buffer_amount(r)` | `site.get_world_3d()` + `site.region_id` | `get_total_received_amount(r)` (`= buffer + consumed`), `required_amounts`, `get_reserved_in_piles_amount(r)`, `_transit_claims` | Somar `get_total_received_amounts()` com `buffer`/`consumed`, ou ler sites em estado `COMPLETED`/`CANCELLED` | Entrada: `SelectiveSiteDeliveryCoordinator` / `deliver_materials()`; Saída: `contribute_work()` (→ `consumed`) ou `SiteCancellationTransaction` (→ `local_buffer_remaining`) |
| 5 | `construction_sites_consumed` | `ConstructionSite` (mesmos estados ativos acima; exclui `COMPLETED` e `CANCELLED`) | `get_consumed_amount(r)` | `site.get_world_3d()` + `site.region_id` | `get_total_received_amount(r)` | Contar `site.get_consumed_amount()` após `COMPLETED` simultaneamente com `BuildingInstance`, ou após `CANCELLED` simultaneamente com `CancellationCustodyRecord` | Entrada: `contribute_work()` (`buffer → consumed`); Saída: `ConstructionManager._execute_site_completion()` (→ `BuildingInstance`) ou `SiteCancellationTransaction` (→ `local_incorporated_remaining` + `demolition_loss`) |
| 6 | `completed_buildings` | `BuildingInstance` (grupo `completed_buildings`) | `incorporated_materials.get(r, 0)` | `bldg.get_world_3d()` + `bldg.region_id` | `ConstructionSite` histórico (`SiteState.COMPLETED`, excluído dos compartimentos 4–5) | Contar canteiro `COMPLETED` e `BuildingInstance` ao mesmo tempo | Entrada: transferência atômica em `ConstructionManager._execute_site_completion()` (momento exato em que a propriedade deixa o `ConstructionSite`) |
| 7 | `cancellation_local_buffer` | `CancellationCustodyRecord` em `RegionalAuthority.cancellation_custodies` | `local_buffer_remaining.get(r, 0)` (`A_buf`) | `rec.world_instance_id` + `rec.region_id` | `released_on_piles` (`L`, ainda em `camp_storage`), `in_transit_remaining` (`H`, já em `unit_carry_loads`), `delivered_to_camp` (`E`, contador histórico já em `camp_storage`), `missing_deficit` (`M`) | Somar `L`, `H`, `E` ou `M` no balanço físico | Entrada: `SiteCancellationTransaction.execute()`; Saída: `CancellationRecoveryTransaction.recover()` (`A_buf → unit_carry_loads` + `H`) |
| 8 | `cancellation_local_incorporated` | `CancellationCustodyRecord` em `RegionalAuthority.cancellation_custodies` | `local_incorporated_remaining.get(r, 0)` (`A_inc`) | `rec.world_instance_id` + `rec.region_id` | `demolition_loss` (`D`, perda consumada independente — NÃO é compartimento físico) | Somar `D` como material físico remanescente ou somar `H`/`E` | Entrada: `SiteCancellationTransaction.execute()` (parcela recuperável de `ConstructionCancellationMath`); Saída: `CancellationRecoveryTransaction.recover()` (`A_inc → unit_carry_loads` + `H`) |

### Confirmações Arquiteturais Explícitas (Seção 5 do Escopo)
- **Estoque e pilhas externas:** `GroundPileManager` gerencia exclusivamente `_piles` associadas à `CampStorageZone` (incluindo fallback `overflow_radial` dentro da mesma lista `_piles`). **Não existe na arquitetura atual (`T3`) compartimento físico separado para pilhas avulsas externas fora do gerenciador.** O auditor não inventa compartimento fictício; em vez disso, escaneia `GROUP_GROUND_PILES` no domínio e sinaliza qualquer pilha física não gerenciada como anomalia (`unmanaged_ground_pile_in_world`).
- **Reservas (`PileReservationLedger`):** representam direito econômico sobre material já presente em `camp_storage` (`camp_available == camp_storage - camp_reserved`). Nunca somadas em $Q$.
- **Perdas legítimas independentes:**
  - `decay_losses`: `SettlementStorageSource.get_total_decayed(r)`, incrementado exclusivamente por `GroundPileManager._record_decay()`.
  - `demolition_losses`: soma de `CancellationCustodyRecord.demolition_loss[r]` na `RegionalAuthority` do domínio (persiste em memória mesmo quando `record.state == SETTLED`), calculado de forma pura e independente em `ConstructionCancellationMath.evaluate_snapshot()`.

---

## 4. Instrumentação Somente Leitura e Demonstração de Ausência de Dupla Contagem

Foi criado o helper somente de testes [regional_conservation_audit.gd](file:///C:/Projetos/Dawn_of_Kin_wt_r_03a/tests/framework/regional_conservation_audit.gd) (`class_name RegionalConservationAudit extends RefCounted`), **sem qualquer código de auditoria ou livro-caixa paralelo em produção (`src/`)**:
- **Estritamente somente leitura:** consulta apenas `world.get_meta(DOMAIN_META)` sem criar `RegionalAuthority`, sem alocar seriais/IDs, sem alterar revisões de inventário/armazenamento/mochila e sem chamar getters mutáveis (ex.: lê `site._transit_claims` diretamente sem invocar `_prune_stale_state()`). Comprovado em `C01` pela invariância exata de `inv.get_transaction_revision()`, `gpm.get_transaction_revision()`, `load.get_transaction_revision()` e `authority.construction_transfer_serial`.
- **Fronteiras estáveis:** reporta `stable_boundary` observando locks ativos (`storage.is_batch_active()`, `is_locked()`, `inventory.is_transaction_busy()`, `authority.has_active_operation()`, `load.is_transaction_busy()`, `site.is_transaction_busy()`), sem interpretar estados mid-lock como perdas definitivas.
- **Verificações cruzadas internas de consistência (sem somar espelhos a $Q$):**
  - `inventory.get_physical_amount(r) == storage.get_physical_amount(r)`
  - `sum(pile.amount in gpm.get_piles()) == storage.get_physical_amount(r)`
  - `camp_reserved <= camp_storage` e `camp_available == camp_storage - camp_reserved`
  - `load.validate_provenance()` e `sum(ledger lots of r) == load.get_amount(r)`
  - `site.get_delivered_buffer_amount(r) + site.get_consumed_amount(r) == site.get_total_received_amount(r)`
  - `ReservedWithdrawalCoordinator.validate_custody_accounting_pure(rec)`
  - `cancel_in_transit_mirror == provenance_cancel_total` e `sites_transit_claims_mirror == provenance_site_reserved_total`
  - Deduplicação de instâncias (`seen_source_ids`, `seen_unit_ids`, `seen_load_ids` com detecção de `shared_carry_load_instance`, `seen_site_ids`, `seen_building_ids`) e detecção de `unmanaged_ground_pile_in_world`.

---

## 5. Identificação e Isolamento dos Domínios Regionais

O domínio é identificado pela tupla `(world_instance_id: int, region_id: StringName, resource_id: StringName)`, **nunca** apenas por um `region_id` textual:
- `C11` executa simultaneamente **três domínios vivos**: dois mundos `MainScene` completos em `SubViewport(own_world_3d = true)` distintos compartilhando o mesmo texto `region_id = &"default"`, mais um domínio `region_north` coexistindo no mesmo `World3D` do Mundo 1.
- Operações de extração, entrega seletiva ao acampamento, reserva de construção e deterioração no Mundo 1 / `&"default"` conservam exatamente esse domínio (`ΔQ = -1`, `decay_delta = +1`) enquanto ambos os outros domínios registram delta **exatamente zero** em todos os 8 compartimentos e perdas.
- **Limitação regional histórica preservada (`R01`, pré-`T4`):** na `MainScene` atual, os nós sob `TestMap/ResourceSources` (`wood_tree_01..02`, `stone_rock_01..02`, `food_bush_01..02`) não possuem `meta(&"region_id")` explícito, enquanto `PlayableCommunitySources` (`wood_tree_03..06`, etc.) possui `meta(&"region_id") = &"default"`. O auditor resolve nós sem metadado para `&"default"` (alinhado ao padrão de `ConstructionSite` e `CommunityWorkBoard`), impedindo vazamento de fontes sem metadado para regiões não-padrão (`region_north`) no mesmo `World3D`, sem antecipar a arquitetura territorial da `T4`.

---

## 6. Matriz `C01`–`C12`: Balanços Iniciais, Finais, Deltas e Perdas Independentes

Suíte implementada em [test_r_03a_d3_3_regional_conservation.gd](file:///C:/Projetos/Dawn_of_Kin_wt_r_03a/tests/integration/test_r_03a_d3_3_regional_conservation.gd) (**11 testes, 1.087 asserções, 100% PASS, `GodotExitCode = 0`**; `C07` e `C08` executam encadeados em ciclo contínuo `reserva → retirada → entrega → montagem → edifício concluído`):

| Cenário | Teste Executado | Domínio / Recurso | $Q_{\text{inicial}}$ | $Q_{\text{final}}$ | Entradas / Saídas | Perdas Independentes ($\Delta D_{\text{decay}} / \Delta D_{\text{demo}}$) | Deltas por Compartimento ($\Delta$) e Invariantes Comprovadas |
|---|---|---|---|---|---|---|---|
| **C01** | `test_c01_non_empty_initial_regional_balance_and_readonly_audit` | `MainScene` (`wood`, `stone`, `food`) | `W:159`, `S:79`, `F:129` | `W:159`, `S:79`, `F:129` | `0 / 0` | `0 / 0` | Múltiplas árvores (`144 W`), estoque prévio (`12 W`, `7 S`, `9 F`), mochilas mistas (`3 W`, `1 S`, `2 F`), reservas ativas (`4 W`, `2 S` em espelho, `0` em $Q$). Zero mutação de revisões e seriais. |
| **C02** | `test_c02_cut_and_felling_preserve_zero_extraction_deltas` | `MainScene` (`wood`) | `131` (`126 src + 5 camp`) | `131` | `0 / 0` | `0 / 0` | Em `STANDING`, `CHOPPING`, `FELLING` e entrada em `FALLEN`: `Δsrc=0`, `Δcarry=0`, `Δcamp=0`, `0` novos lotes `FREE_GATHERED`, `0` seriais regionais alocados. |
| **C03** | `test_c03_cancellation_freeze_resume_and_reauthorization_conserve_wood` | `MainScene` (`wood`) | `124` (`124 src`) | `124` (`120 src + 4 camp`) | `0 / 0` | `0 / 0` | Cancelamento pré-queda (`Δ=0`), congelamento por `MoveOrder` + retomada (`Δ=0`), cancelamento durante `FELLING` (`Δ=0`, saldo `4` preservado), reautorização pós-`FALLEN` (`Δsrc=-4`, `Δcamp=+4`, `Δcarry=0`). |
| **C04** | `test_c04_multi_trip_extraction_capacity_mixed_weights_and_depletion` | `MainScene` (`wood`, `stone`) | `W:133`, `S:72` | `W:133`, `S:72` | `0 / 0` | `0 / 0` | Capacidade `14` com `2` pedras prévias (peso `6`): `3` viagens reais (`4 W + 7 W + 2 W`), peso máximo observado `14 <= 14`, esgotamento `DEPLETED`. Final: `W` (`Δsrc=-13`, `Δcamp=+13`, `Δcarry=0`), `S` (`Δcarry=-2`, `Δcamp=+2`). |
| **C05** | `test_c05_two_workers_same_tree_dispute_final_units_with_exact_conservation` | `MainScene` (`wood`) | `125` (`125 src`) | `125` (`120 src + 5 camp`) | `0 / 0` | `0 / 0` | Dois trabalhadores na mesma árvore (`5` unidades ímpares): soma extraída exatamente `5`, `DEPLETED`, `Δsrc=-5`, `Δcamp=+5`, `Δcarry=0`. |
| **C06** | `test_c06_provenance_replay_conflict_rollback_retry_and_uncertain_reconciliation` | Isolado `c06_region` (`wood`) | `11` (`8 src + 3 camp`) | `11` (`2 src + 6 carry + 3 camp`) | `0 / 0` | `0 / 0` | Extração (`-2/+2`), replay idempotente (`Δ=0`), conflito (`Δ=0`), rollback pré-commit (`Δ=0`, recibo vazio), retry protegido em busy (`-2/+2`), resultado incerto reconciliado por recibo (`-2/+2`, sem dupla extração). |
| **C07** | `test_c07_c08_reservation_transport_assembly_and_building_completion` | `MainScene` (`wood`, `stone`) | `W:154`, `S:78` | `W:154`, `S:78` | `0 / 0` | `0 / 0` | Reserva (`4 W`, `2 S`): `Δ=0` em todos os compartimentos; retirada reservada: `W` (`Δcamp=-4`, `Δcarry=+4`), `S` (`Δcamp=-2`, `Δcarry=+2`); entrega ao buffer: `W` (`Δcarry=0`, `Δsite_buf=+4`), `S` (`Δsite_buf=+2`). |
| **C08** | `test_c07_c08_reservation_transport_assembly_and_building_completion` | `MainScene` (`wood`, `stone`) | `W:154`, `S:78` | `W:154`, `S:78` | `0 / 0` | `0 / 0` | Montagem 50%: `W` (`buf=2`, `cons=2`), `S` (`buf=1`, `cons=1`); conclusão atômica em `BuildingInstance`: `site_buf=0`, `site_cons=0`, `completed_buildings=4 W / 2 S` (zero dupla contagem entre canteiro e edifício). |
| **C09** | `test_c09_construction_cancellation_custody_demolition_loss_and_recovery` | `MainScene` (`wood`) | `156` (`144 src + 12 camp`) | `153` (`144 src + 9 camp`) | `0 / 0` | `0 / 3` (`demolition_loss`) | Cancelamento com `2` reservados (`L=2`), `2` em trânsito (`H=2`), `2` buffer (`A_buf=2`), `4` incorporados (40% → `A_inc=1`, `D=3`). Recuperação `A→H` (`Δcancel_buf=-2`, `Δcancel_inc=-1`, `Δcarry=+3`); retorno `H→E` (`Δcamp=+5`, `Δcarry=0`, `E_hist=5`). $153 = 156 - 3$. |
| **C10** | `test_c10_decay_losses_independently_evidenced_and_unregistered_loss_rejected` | `MainScene` (`food`, `wood`) | `F:130`, `W:150` | `F:127`, `W:150` (passo 1); `F:125` (passo 2) | `0 / 0` (passo 1); `0 / 2` (passo 2) | `3 / 0` (`food` decay em `315 s`) | `GroundPileManager.get_total_decayed(&"food") == 3` explica exatamente `Δcamp = -3` (`130 → 127`). Retirada não declarada de `2` falha com `discrepancy = -2` (prova anti-tautologia); com `expected_exits = 2`, fecha com `ok = true`. |
| **C11** | `test_c11_regional_isolation_across_worlds_with_same_region_id_and_distinct_regions` | `W1/default`, `W1/region_north`, `W2/default` (`wood`) | `154` / `13` / `158` | `153` / `13` / `158` | `0 / 0` | `1 / 0` (somente `W1/default`, `540 s`) | Operações em `W1/default` (`Δsrc=-2`, `Δcamp=+1`, `decay_delta=1`) conservam `153 = 154 - 1`; `W1/region_north` (`13→13`) e `W2/default` (`158→158`) mantêm delta zero. |
| **C12** | `test_c12_adversarial_accounting_detection` | Controlado `adv_region` (`wood`) | `16` | `16` (base limpa) | Adversariais controlados | `0 / 0` | Detecta sem injeção em produção: `inventory+piles` (`+8`), `carry+provenance` (`+4`) + `unreconciled_provenance_ledger`, reservas (`+2`), `sites_transit_claims` (`+2`), `cancellation_in_transit` (`+2`), exclusão de fonte de outra região, `storage` cross-world, `domain_identity_mismatch`, falta (`-3`), duplicação (`+5`), `unmanaged_ground_pile_in_world` e `shared_carry_load_instance`. |

---

## 7. Reconciliação dos Testes Históricos (Inventário Determinístico e Classificação A–E)

A varredura determinística de `extract()`, `transfer_to_carry_load()`, `transfer_to_carry_load_with_provenance()` e `can_extract()` sobre toda a árvore `tests/` identificou **26 suítes históricas relevantes**, executadas primeiro em baseline **RED** sobre `a0bf3aec15ef1ec405f2ed93008e565a62f27ed2` (`01_red_historical/`). Todas as `15` suítes com falha/timeout em RED decorreram exclusivamente da substituição do contrato legado de madeira pelo ciclo `D3` (zero ocorrências de classe **E — falha funcional não explicada**):

| Suíte / Arquivo | Resultado RED (`a0bf3ae`) | Resultado GREEN (`D3.3`) | Classificação | Justificativa Técnica e Garantias Preservadas |
|---|---|---|---|---|
| `tests/unit/test_t2_natural_source_states.gd` | FAIL (`1/4`, exit `1`) | **PASS (`4/4`, `104` asserts, exit `0`)** | **C + B** | `test_01`/`test_04` atualizados para exercitar a máquina real de estados `STANDING→CHOPPING→FELLING→FALLEN` via `_start_real_tree_cut`; `test_03` usa fixture `FALLEN` para teste isolado pós-queda; `test_02` (pedra/alimento) preservado integralmente. |
| `tests/unit/test_t2_resource_sources.gd` | FAIL (`2/6`, exit `1`) | **PASS (`6/6`, `98` asserts, exit `0`)** | **C + B** | Verifica recusa explícita de extração pré-queda em `WOOD` e aplica fixture `FALLEN` para validar extração parcial, esgotamento, limites e capacidade em `test_01`/`04`/`05`/`06`. |
| `tests/unit/test_t2_worker_transfer.gd` | FAIL (`4/5`, exit `1`) | **PASS (`5/5`, `53` asserts, exit `0`)** | **B** | `test_02` prepara fonte `WOOD` já derrubada (`FALLEN`) para testar a transferência direta fonte→mochila→inventário isolada. |
| `tests/unit/test_source_selection_model.gd` | TIMEOUT (`90,95 s`, exit `124`) | **PASS (`4/4`, `52` asserts, exit `0`)** | **B** | Loop `while not t1.is_depleted(): t1.extract(...)` girava infinitamente em árvore `STANDING`. Aplicada fixture `FALLEN` em `test_03`/`test_04` + guarda de iteração limitada; todas as asserções do modelo visual preservadas. |
| `tests/unit/test_t3_1_reservations.gd` | FAIL (`16/17`, exit `1`) | **PASS (`17/17`, `432` asserts, exit `0`)** | **B** | `test_13` usa fixture `FALLEN` para obter madeira na preparação de pilhas para teste de reservas. Todas as `17` provas de reserva intactas. |
| `tests/integration/test_t2_pace_and_load.gd` | TIMEOUT (`90,88 s`, exit `124`) | **PASS (`13/13`, `456` asserts, exit `0`)** | **C + B** | `test_01` reconciliado ao contrato `D3` (corte `2,5 s` + queda `0,5 s` + coleta `2,5 s` = `5,5 s`, mantendo verificação de ritmo `food 1,5 s < cut 2,5 s < stone 3,5 s < wood_extract 5,5 s`); `test_02` usa fixture `FALLEN` + guarda de loop para testar `DEPLETED`. |
| `tests/integration/test_t2_resource_picking.gd` | FAIL (`4/5`, exit `1`) | **PASS (`5/5`, `50` asserts, exit `0`)** | **B** | Fixture `FALLEN` em L287 para esgotar `tree` e testar picking/rejeição pós-esgotamento. |
| `tests/integration/test_m1_m10_independent_headless.gd` | FAIL (`7/8`, exit `1`) | **PASS (`8/8`, `1.757` asserts, exit `0`)** | **C** | `test_m8` atualizado para confirmar `tree.is_felling()` com `0` madeira extraída e, após concluir a queda, `tree.is_fallen()` com extração legítima de `4` unidades. |
| `tests/integration/test_t3_6_2_b3_2_source_transfer.gd` | FAIL (`0/4`, exit `1`) | **PASS (`4/4`, `84` asserts, exit `0`)** | **B + D** | Adicionada cobertura complementar (`D`) verificando recusa `tree_not_felled` em árvore `STANDING` sem alocação indevida, e fixture `FALLEN` em `source()` para as 4 provas de transferência com proveniência/replay/rollback. |
| `tests/integration/test_t3_6_2_c1_reserved_withdrawal_prep.gd` | FAIL (`9/10`, exit `1`) | **PASS (`10/10`, `282` asserts, exit `0`)** | **B** | Fixture `FALLEN` em `test_03` para gerar lote `FREE_GATHERED` de madeira antes de testar retirada reservada. |
| `tests/integration/test_t3_6_2_c2_reserved_withdrawal_transaction.gd` | FAIL (`14/16`, exit `1`) | **PASS (`16/16`, `651` asserts, exit `0`)** | **B** | Fixture `FALLEN` em dois pontos (`L359` e `L802`) para semear carga `FREE_GATHERED` mista nas transações de retirada reservada. |
| `tests/integration/test_t3_6_2_c3_1_selective_delivery_prep.gd` | FAIL (`4/6`, exit `1`) | **PASS (`6/6`, `161` asserts, exit `0`)** | **B** | Reconciliado via `tests/framework/selective_site_delivery_fixture.gd` (`_gather()` prepara árvore `FALLEN` antes da transferência de setup). |
| `tests/integration/test_t3_6_2_c3_2_selective_delivery_transaction.gd` | FAIL (`6/8`, exit `1`) | **PASS (`8/8`, `360` asserts, exit `0`)** | **B** | Mesma fixture compartilhada `selective_site_delivery_fixture.gd`; todas as provas transacionais preservadas intactas. |
| `tests/integration/test_t3_6_2_c3_3_order_integration.gd` | FAIL (`9/10`, exit `1`) | **PASS (`10/10`, `328` asserts, exit `0`)** | **B** | Fixture `FALLEN` em `L255` (`free_source`) para preparar lote `FREE_GATHERED` em coexistência com entrega de canteiro. |
| `tests/integration/test_t3_6_2_c4_6_gather_regional_isolation.gd` | FAIL (`4/5`, exit `1`) | **PASS (`5/5`, `198` asserts, exit `0`)** | **B** | Fixture `FALLEN` em `test_03` (`tree_free`) preservando integralmente todas as asserções de isolamento regional cross-world/cross-region. |
| `tests/integration/test_t3_6_3_b1_4_recovery_dispatch.gd` | TIMEOUT (`90,92 s` em cap 90s; 11/16 já em PASS) | **PASS (`16/16`, `178` asserts, `100,47 s`, exit `0`)** | **A** | **Preservação integral** (zero edição): timeout em RED foi exclusivamente o teto de `90 s` do runner; executou integralmente em `100,47 s` com teto `240 s`. |
| **10 suítes históricas intactas em RED** (`test_t2_natural_source_states` int, `test_t2_playable_economy`, `test_t2_worker_cycle`, `c3_4_3`, `c4_4`, `c4_5`, `c4_12`, `b1_2`, `b1_3`, `t3_6_4_cancellation_ui`) | **PASS (`65/65`, `6.151` asserts, exit `0`)** | **Intactas (zero edição)** | **A** | **Preservação integral** — nenhuma dependência de extração direta pré-queda em árvore intacta. |

---

## 8. Execuções Intermediárias, Validação Proporcional e Códigos de Saída Diretos

Todas as execuções (incluindo RED, timeouts, falhas de fixture intermediárias e GREEN final) foram preservadas integralmente em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\D3\D3.3\` com registro de comando, SHA, timestamps, duração, contagens e `GodotExitCode` capturado diretamente via `Invoke-Godot` (sem mascaramento por wrapper):

| Fase / Lote | Diretório de Evidência | Resultado | Testes / Asserções | Saída Direta |
|---|---|---|---|---|
| Baseline Git antes | `00_git_antes.txt` | Registrado | `HEAD = a0bf3ae`, `develop = 21c34ee`, `main = 25e0a20` | `0` |
| **RED histórico (26 suítes)** | `01_red_historical/` | `10` PASS, `13` FAIL (`exit=1`), `3` TIMEOUT (`exit=124` helper; saída original da Godot indisponível nos 3 encerramentos por tempo) | `15` incompatibilidades D3 + `1` timeout de duração (`b1_4`) | `0` / `1` / `124` |
| **Iterações intermediárias `D0-A04`** (`run1`, `run2`, `run3`) | `02_d0_a04_proofs/` | `run1`: `6/11` FAIL (`1`); `run2`: `8/11` FAIL (`1`); `run3`: `10/11` FAIL (`1`) — ajustes apenas em fixtures/helper de teste (`SubViewport` `get_world_3d()`, registro `BUILDER` D9, `MainScene` com navmesh em `C11`, default `&"default"` no auditor para `R01`) | `1.028` / `1.087` / `1.087` | `1` (Godot) |
| **GREEN `D0-A04` (`C01`–`C12`)** | `02_d0_a04_proofs/d0_a04_green_*` | **PASS** (`1/1` suíte, `0` erros, `0` avisos, `51,12 s`) | **`11/11` testes, `1.087` asserções** | **`0` (Godot e runner)** |
| **GREEN histórico (15 reconciliadas + `b1_4`)** | `03_green_historical/` | **PASS** (`16/16` suítes, `0` erros, `0` avisos) | **`137/137` testes, `5.244` asserções** (`121/121` / `5.066` reconciliadas + `16/16` / `178` em `b1_4`) | **`0` em todas as 16 suítes** |
| **Regressões focais consolidadas `D3.2` (13 suítes — execução fresca `D3.3`)** | `04_focal_regressions/focal_d32_consolidated_*` | **PASS** (`13/13` suítes, `0` erros, `0` avisos) | **`174/174` testes, `9.263` asserções** (incluindo **`D3.1-R1`: `17/17`, `300` asserts** e **`D3.2`: `12/12`, `179` asserts**) | **`0` em todas as 13 suítes** |
| **Regressões focais econômicas, construção, reservas e autoridade (15 suítes)** | `04_focal_regressions/focal_econ_construction_*` | **PASS** (`15/15` suítes, `0` erros, `0` avisos) | **`110/110` testes, `4.486` asserções** | **`0` em todas as 15 suítes** |
| **Validação estática (`.\tools\validate.ps1`)** | `05_static_validation/validate_d3_3.log` | **PASS** — importação headless, **`219` scripts** verificados (`+2` novos scripts de teste), boot headless `--quit-after 3`, `DOCS_DESIGN_IMPORT_COUNT = 0`, `0` erros, `0` avisos | `219/219` scripts | **`0` (`ValidateExitCode`)** |

*Nota de escopo (Seção 12):* A campanha segmentada integral definitiva permanece reservada à **`D3.4`**; os `8` testes humanos `HD3-01`–`HD3-08` (`D3.2`) e os `13` testes humanos da `D2` não foram repetidos porque nenhum arquivo de produção ou comportamento jogável foi modificado na `D3.3`.

---

## 9. Inventário de Arquivos Adicionados / Modificados

- **Produção (`src/`, `data/`, `assets/`, `docs/Dawn_of_Kin_GDD.md`):** **0 arquivos modificados.**
- **Novos arquivos de prova e relatório (5):**
  1. `tests/framework/regional_conservation_audit.gd` (+ `.uid`)
  2. `tests/integration/test_r_03a_d3_3_regional_conservation.gd` (+ `.uid`)
  3. `docs/testing/R_03A_D3_3_regional_conservation_and_compatibility_candidate_report.md`
- **Arquivos de teste/fixture reconciliados (14):**
  1. `tests/framework/selective_site_delivery_fixture.gd`
  2. `tests/unit/test_t2_natural_source_states.gd`
  3. `tests/unit/test_t2_resource_sources.gd`
  4. `tests/unit/test_t2_worker_transfer.gd`
  5. `tests/unit/test_source_selection_model.gd`
  6. `tests/unit/test_t3_1_reservations.gd`
  7. `tests/integration/test_t2_pace_and_load.gd`
  8. `tests/integration/test_t2_resource_picking.gd`
  9. `tests/integration/test_m1_m10_independent_headless.gd`
  10. `tests/integration/test_t3_6_2_b3_2_source_transfer.gd`
  11. `tests/integration/test_t3_6_2_c1_reserved_withdrawal_prep.gd`
  12. `tests/integration/test_t3_6_2_c2_reserved_withdrawal_transaction.gd`
  13. `tests/integration/test_t3_6_2_c3_3_order_integration.gd`
  14. `tests/integration/test_t3_6_2_c4_6_gather_regional_isolation.gd`

---

## 10. Pendências Remanescentes para `D3.4` (e Etapas Posteriores)

Permanecem expressamente reservadas às etapas posteriores bloqueadas:
- **`D3.4` (campanha consolidada da `D3`):** execução da campanha segmentada integral (`run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`) sobre todas as suítes do repositório, verificação de `Discovered == ExecutedUnique` (`0` duplicatas, `0` ausentes), smoke/desempenho proporcional quando exigido e consolidação para decisão final da `D3`.
- **`D4`:** homologação humana integral e promoção/encerramento de `R-03A` (quando autorizada).
- **`R-03B`:** `ControlMode` e retorno comunitário configurável (`D-05`, observação `HD3-06`).
- **`T4` / `R-04A`–`R-04C`:** arquitetura territorial multi-região plena (substituindo a limitação `R01`), ecologia/regeneração, depósitos dedicados e substituição do fluxo legado `P-REC-1` por `D-01`/`D-02`.

---

## 11. Parecer Técnico Fundamentado sobre `D0-A04`

**Classificação técnica:** **`COMPROVADA NO ESCOPO INTEGRAL AUTORIZADO`**

**Fundamentação:**
1. A identidade formal regional $Q_{\text{final}}(D, r) = Q_{\text{inicial}}(D, r) + \text{Entradas} - \text{Saídas} - \Delta\text{PerdasLegítimas}$ foi demonstrada de forma não tautológica, estritamente somente leitura e sem introdução de código paralelo em produção, cobrindo todos os **8 compartimentos físicos reais** existentes na arquitetura atual (`T3` / `P-REC-1`) e todos os cenários **`C01`–`C12`** (`11/11` testes, `1.087` asserções, `exit=0`).
2. A separação entre quantidades físicas e espelhos/direitos/históricos (`SettlementInventory`, `CarryProvenanceLedger`, `PileReservationLedger`, `_transit_claims`, `L`/`H`/`E`/`M` de `CancellationCustodyRecord`) e a independência das perdas legítimas (`GroundPileManager.get_total_decayed()` e `CancellationCustodyRecord.demolition_loss`) foram provadas tanto em fluxo positivo (`C01`–`C11`) quanto em cenários adversariais controlados (`C10` e `C12`).
3. O isolamento por domínio real `(World3D, region_id, resource_id)` foi demonstrado inclusive entre mundos distintos com o mesmo `region_id` textual (`C11`), preservando transparentemente as fronteiras arquiteturais atuais pré-`T4` (ausência de compartimento físico separado para pilhas externas fora do `GroundPileManager` e limitação regional histórica `R01` em `TestMap/ResourceSources`).
4. Todas as `15` suítes históricas incompatíveis com o novo contrato `D3` foram reconciliadas sem perda de cobertura econômica/adversarial/regional e validadas em GREEN (`137/137` com `b1_4`), junto às `28` regressões focadas (`284/284`, `13.749` asserções) e ao `validate.ps1` (`219/219` scripts, `0/0`).

> Esta classificação representa parecer técnico da candidata `R-03A D3.3`. A homologação definitiva de `D0-A04`, o avanço para `D3.4` e o encerramento integral da `D3` pertencem exclusivamente ao proprietário após auditoria independente.
