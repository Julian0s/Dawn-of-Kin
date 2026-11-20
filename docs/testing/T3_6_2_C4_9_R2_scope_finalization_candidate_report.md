# DAWN OF KIN — T3.6.2-C4.9-R2
## Relatório Técnico da Candidata: Auditoria Corretiva de Publicação Antecipada e Uso Indevido de Escopos Ativos

**Data:** 2026-11-19  
**Repositório:** `Julian0s/Dawn-of-Kin`  
**Branch:** `feat/t3-6-2-provenance-transactions`  
**Baseline inicial verificada:** `6ad7071f0037115dceb3425fc779bbef8afda8fa`  
**`main` preservada (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Status:** Implementado, validado automaticamente e submetido à auditoria independente (`P6` ainda **NÃO** declarada integralmente concluída).

---

## 1. Análise de Causa e Diferenciação (Defeitos Reproduzidos vs. Já Protegidos)

Durante `ConstructionManager.try_create_site_from_placement()`, os callbacks `site_creator_override` (`L536`) e `child_entered_tree` em `_sites_root` (`L576`) executam **após** a aplicação silenciosa da reserva (`scope._reservation_applied = true`, `scope._published = false`), mas **antes** da validação completa e do ponto irreversível de commit (`L613`).

Como `ReservedWithdrawalCoordinator._active_site_creation_scopes` mantém a referência ao `SiteCreationScope` ativo e `_owns_site_creation_scope(scope)` retornava `true` durante essa janela:

1. **Defeito reproduzido A — Publicação antecipada antes do commit impedindo rollback (`test_01` e `test_02`):**
   - Um callback em `site_creator_override` ou `child_entered_tree` que obtivesse o `SiteCreationScope` verdadeiro ativo conseguia invocar `_publish_site_reservation_committed(scope)` (ou `_publish_silent_reservation_events(scope, false)`) em `GroundPileManager` e `InMemoryStorageSource`.
   - A chamada marcava `scope._published = true` e emitia `reservations_changed` e `storage_changed` prematuramente.
   - Quando a criação falhava em seguida (`site_creator_override` retornando `null` ou falha de sobreposição pós-`add_child`), `_restore_site_reservation_checkpoint_silent()` era recusado porque `scope._published == true`, deixando reserva órfã permanente (`res_site_..._0002`), drenando saldo disponível e derivando revisões.
2. **Defeito reproduzido B — Restauração indevida com checkpoint divergente/fabricado usando escopo verdadeiro ativo (`test_03`):**
   - Na mesma janela pré-commit (`_reservation_applied == true`, `_published == false`), um callback com o `SiteCreationScope` verdadeiro ativo conseguia invocar `_restore_site_reservation_checkpoint_silent(stale_or_fake_ckpt, active_sc)` passando um checkpoint antigo (anterior à criação da primeira obra) ou fabricado.
   - A restauração sobrescrevia o `_ledger` / `_reservations` com o snapshot antigo (apagando a reserva válida da primeira obra!) e limpava `scope._reservation_applied = false`, impedindo até mesmo o rollback legítimo subsequente da segunda obra.
3. **Caminho já protegido na baseline `6ad7071` (`test_04`):**
   - Em `ConstructionSite.authorize_manual_complement()`, não há callbacks externos entre `_apply_*_manual_complement_silent` e `_publish_manual_complement_committed`; quando os callbacks pós-commit (`reservations_changed`, `storage_changed`, `inventory_changed`, `state_changed`, `site_created`) executam, `scope._published` já é `true`, bloqueando repetição de `_publish` e `_restore`. Ainda assim, `ManualComplementScope` foi alinhado à mesma máquina de fases e vínculo de checkpoint para manter simetria estrutural.

---

## 2. Evidência RED na Baseline (`6ad7071`) — Antes de Editar `src/`

Executando [`tests/integration/test_t3_6_2_c4_9_r2_scope_finalization.gd`](../../tests/integration/test_t3_6_2_c4_9_r2_scope_finalization.gd) sobre `6ad7071` sem alterações em `src/`:
- **Resumo RED:** `1` suíte, `4` testes, `1` aprovado (`test_04`), **`3` falhos (`test_01`, `test_02`, `test_03`)**, `99` asserções, `0` `SuiteErrors`:
  - `test_01_premature_publish_in_site_creator_override_then_null_rollback_ground_pile_and_in_memory` (`18` falhas): reservas órfãs `&"res_site_c49_r2_gpm_pub_0002"` e `&"res_site_c49_r2_mem_pub_0002"` retidas após retorno `null`, saldo livre caiu `4 -> 0`, sinais econômicos intermediários emitidos (`1` cada) e revisões derivadas;
  - `test_02_premature_publish_in_child_entered_tree_then_overlap_failure_rolls_back_cleanly` (`6` falhas): reserva órfã `&"res_site_c49_r2_tree_pub_0002"` retida após publicação antecipada em `child_entered_tree` seguida de falha por sobreposição;
  - `test_03_mismatched_or_fabricated_checkpoint_with_real_active_scope_rejected_on_both_backends` (`10` falhas): reserva de `site_1` (`4` madeiras) apagada (`4 -> 0`, `get_all_reservation_ids() == []`) em `GroundPileManager` e `InMemoryStorageSource` ao passar checkpoint antigo com o escopo ativo verdadeiro.

---

## 3. Alterações Implementadas

### 3.1 `src/economy/reserved_withdrawal_coordinator.gd`
- Estendidos `SiteCreationScope` e `ManualComplementScope` com flags explícitas de fase de finalização (`_commit_authorized`, `_rollback_authorized`, `_rolled_back`) e snapshot vinculado (`_bound_checkpoint: Dictionary`).
- Adicionados os autorizadores de transição de fase:
  - `_authorize_site_creation_commit(scope)` e `_authorize_site_creation_rollback(scope)`;
  - `_authorize_manual_complement_commit(scope)` e `_authorize_manual_complement_rollback(scope)`.

### 3.2 `src/economy/ground_pile_manager.gd` e `src/economy/in_memory_storage_source.gd`
- **Preparação e Aplicação (`_prepare_*`, `_apply_*`):** exigem que o escopo não tenha sido aplicado, publicado, revertido (`_rolled_back`) nem esteja em fase de commit/rollback (`not _commit_authorized and not _rollback_authorized`); ao aplicar a reserva silenciosamente, gravam uma cópia profunda do checkpoint em `scope._bound_checkpoint = checkpoint.duplicate(true)`.
- **Publicação (`_publish_site_reservation_committed`, `_publish_manual_complement_committed`, `_publish_silent_reservation_events`):** exige `scope._commit_authorized == true`, `not scope._rollback_authorized`, `not scope._rolled_back` e `not scope._published`; consome a fase (`_published = true`, `_commit_authorized = false`, `_bound_checkpoint = {}`) antes de emitir sinais.
- **Rollback (`_restore_site_reservation_checkpoint_silent`, `_restore_manual_complement_checkpoint_silent`, `_restore_silent_checkpoint_internal`):** exige `scope._rollback_authorized == true`, `not scope._commit_authorized`, `not scope._published`, `not scope._rolled_back`, `not scope._bound_checkpoint.is_empty()` e igualdade exata `checkpoint == scope._bound_checkpoint`; restaura a partir de `scope._bound_checkpoint` e encerra a fase (`_rolled_back = true`, `_rollback_authorized = false`, flag aplicada `false`, `_bound_checkpoint = {}`).

### 3.3 `src/buildings/construction_manager.gd` e `src/buildings/construction_site.gd`
- `ConstructionManager.try_create_site_from_placement`: autoriza rollback (`_authorize_site_creation_rollback(scope)`) exclusivamente no bloco `if not valid:` (`L594`) e autoriza commit (`_authorize_site_creation_commit(scope)`) exclusivamente após o ponto irreversível de commit (`L620`, depois de todas as validações pós-`add_child` e registro em `_sites`).
- `ConstructionSite.authorize_manual_complement`: autoriza rollback (`_authorize_manual_complement_rollback(scope)`) exclusivamente na falha de invariante pós-aplicação (`L781`) e autoriza commit (`_authorize_manual_complement_commit(scope)`) imediatamente antes da publicação (`L797`).

---

## 4. Validação GREEN e Regressão Completa

1. **`.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_9_r2_scope_finalization -TimeoutSeconds 45`:** `1` suíte, `4/4` testes aprovados, `0` falhas, `0` `SuiteErrors`, `99` asserções, código `0` e `0` vazamentos.
2. **`git diff --check`:** código `0`.
3. **`.\tools\validate.ps1`:** `Validation PASSED (0 errors, 0 warnings, 160 scripts checked)`.
4. **`.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240`:** `23` suítes, `170/170` testes aprovados, `0` falhas, `0` `SuiteErrors`, `10.964` asserções.
5. **`.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240`:**
   - `16` lotes (`unit` + `integration-01`..`integration-15`) — **TODOS APROVADOS**;
   - **Cobertura:** `Discovered=66 | ExecutedUnique=66 | Duplicates=0 | Missing=0`;
   - **Totais:** `66` suítes, `467/467` testes aprovados, `0` falhas, `0` `SuiteErrors`, `25.749` asserções, `0` erros/avisos da Godot.

---

## 5. Commits Produzidos

- **Produção (`SHA1`):** `afb78db5215d59ecbec1dd8847079cb2124db88e` — `fix(t3.6.2-c4.9-r2): enforce scope finalization phases and bound checkpoints`
- **Testes (`SHA2`):** `5b0cb72baca10af3ee792416ee0c751e5fdc3072` — `test(t3.6.2-c4.9-r2): verify premature publish and checkpoint tampering guards`

---

## 6. Riscos Residuais e Limites Reais

- **Limitação intrínseca da linguagem (GDScript):** conforme documentado nos requisitos de arquitetura, o GDScript não possui modificadores de visibilidade privada em nível de linguagem; as guardas implementadas impedem qualquer uso fora de ordem ou com checkpoint divergente através dos pontos de entrada transacionais (`_prepare_*`, `_apply_*`, `_restore_*`, `_publish_*`), sem alegar proteção contra código que reescreva diretamente variáveis internas arbitrárias das instâncias.
- **Escopo de `P6` ainda parcial:** permanecem para etapas futuras (não iniciadas) a fronteira regional de `ConstructionSite.contribute_work`, o fechamento de mutadores públicos remanescentes fora dos coordenadores (`UnitCarryLoad.add_with_provenance`, `ResourceSource.extract`, mutadores diretos fora de transações protegidas em modo proveniência), `D3`, `P2`, `P4`, ativação global de proveniência e `C4.10`.
