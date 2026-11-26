# Dawn of Kin — Relatório Técnico da Candidata `R-03A D3.3-R1`
## Validação Adversarial da Auditoria de Conservação Regional (`D3.3-A01`)

**Data:** 26/11/2026  
**Etapa:** `R-03A D3.3-R1` *(validação adversarial das hipóteses `A01-A` e `A01-B` sobre a instrumentação de testes `D0-A04`)*  
**Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**SHA base (`D3.3`):** `6a11941e2cc4acba1c34b13a4d817d5d04438b33` *(base `D3.2` homologada: `a0bf3aec15ef1ec405f2ed93008e565a62f27ed2`)*  
**SHA final publicado:** registrado em `06_git_depois.txt` no acervo de evidências *(commit único exclusivo na branch candidata; `HEAD == origin/feat/r-03a-community-work-main-scene`)*  
**Base canônica preservada (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2` *(não alterada)*  
**Linha estável preservada (`main`):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` *(não alterada)*  
**Checkout principal preservado:** `C:\Projetos\Dawn of Kin` *(em `develop`, preservando integralmente `M project.godot`, SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`)*  
**Godot:** `4.7.2.stable.official.ed1daf0bf`  
**Status obrigatório:** **`IMPLEMENTADO`** · **`VALIDADO TECNICAMENTE`** · **`PENDENTE DE AUDITORIA INDEPENDENTE`** · **`NÃO HOMOLOGADO`** · **`NÃO INTEGRADO À DEVELOP`**

> [!IMPORTANT]
> Este incremento **NÃO** declara homologação definitiva de `D0-A04`, **NÃO** encerra `D3` e **NÃO** inicia `D3.4`, `D4` ou `R-03B`. Zero arquivos de produção (`src/`, `data/`, `assets/`), `docs/Dawn_of_Kin_GDD.md` ou `project.godot` foram modificados.

---

## 1. Resultado Individual das Hipóteses `D3.3-A01`

| Hipótese | Classificação | Resumo Objetivo |
|---|---|---|
| **`A01-A` — Fronteira transacional instável** | **`CONFIRMADA E CORRIGIDA`** | `RegionalConservationAudit.capture()` registrava `stable_boundary`, mas `verify_conservation()` não exigia sua presença nem seu valor `true`, aceitando comparações com snapshots instáveis ou sem evidência de estabilidade (`ok = true`). |
| **`A01-B` — Identidade do armazenamento** | **`CONFIRMADA E CORRIGIDA`** | `RegionalConservationAudit.capture()` registrava `domain.storage_instance_id`, mas `verify_conservation()` comparava apenas `(world_instance_id, region_id, resource_id)`, aceitando trocas de instância de armazenamento no mesmo domínio (inclusive mascarando descontinuidade em `decay_losses`). Adicionalmente, `capture()` passou a validar o `region_id` de `_piles_root` no mesmo `World3D`. |

---

## 2. Reprodução RED Obrigatória (sobre `6a11941` intacto)

Execução arquivada em `01_red/d3_3_r1_red_integration__test_r_03a_d3_3_regional_conservation.log`:
- **Resultado:** `Tests=13 Passed=11 Failed=2 SuiteErrors=0 Assertions=1136`, **`GodotExitCode = 1`**, `DurationSec = 20.567`.
- **`test_r1_a_transactional_stability_guards` (FAIL, 10 falhas):** `capture()` identificou corretamente `stable_boundary = false` tanto durante `GroundPileManager.begin_batch()` quanto durante `UnitCarryLoad._provenance_busy = true`, mas `verify_conservation()` retornou `ok = true` (`reason = ""`) para `Unstable->Stable`, `Stable->Unstable`, `Unstable->Unstable` e snapshots sem a chave `stable_boundary`.
- **`test_r1_b_storage_identity_continuity_and_domain` (FAIL, 8 falhas):** confirmou que `verify_conservation()` aceitava snapshots sem `storage_instance_id`, com `storage_instance_id` assimétrico (`0` vs não-zero) e não exigia identidade contínua de armazenamento. *(Nota transparente de fixture: na 1ª execução RED, `gpm_alt` coexistia com pilhas de `gpm1` no mesmo domínio gerando `unmanaged_ground_pile_in_world`, e `tick_decay()` não existia — corrigido no teste para substituição limpa via `gpm_a.cleanup()` + `step_decay()`.)*

---

## 3. Causa Técnica e Correções Realizadas (exclusivamente em `tests/`)

### Arquivos alterados (2)
1. `tests/framework/regional_conservation_audit.gd`
2. `tests/integration/test_r_03a_d3_3_regional_conservation.gd`

### Correções em `RegionalConservationAudit`
1. **Contrato de estabilidade transacional (`verify_conservation()`):**
   - Exige presença explícita do campo booleano `stable_boundary` em ambos os snapshots (`missing_initial_and_final_stability_evidence`, `missing_initial_stability_evidence`, `missing_final_stability_evidence`).
   - Exige `stable_boundary == true` em ambos os snapshots (`unstable_initial_and_final_snapshots`, `unstable_initial_snapshot`, `unstable_final_snapshot`).
   - Preserva integralmente a captura diagnóstica em `capture()` durante transações/locks (`ok = true`, `stable_boundary = false`), recusando apenas seu uso como prova definitiva em `verify_conservation()`.
2. **Contrato de identidade do armazenamento (`capture()` + `verify_conservation()`):**
   - Em `capture()`, além de `bound_world`/`bound_region` e `_piles_root.get_world_3d()`, valida `_resolve_node_region_readonly(gpm._piles_root) == region_id` (`storage_piles_root_region_mismatch`).
   - Em `verify_conservation()`, exige presença e tipo `int` de `domain.storage_instance_id` em ambos os snapshots (`missing_storage_identity`) e igualdade exata `b_stor_id == a_stor_id` (`storage_identity_mismatch`).
   - **Nota técnica de 64 bits (Godot 4):** durante a primeira tentativa GREEN (`02_green/d3_3_r1_green_*`), constatou-se que `Object.get_instance_id()` no Godot 4 (64 bits) pode ter o bit 63 ligado (inteiro com sinal negativo em GDScript), sendo `0` o único sentinela de ausência de armazenamento. A guarda `< 0` indevida foi removida, preservando `0 == 0` para domínios legitimamente sem armazenamento e rejeitando `0` vs não-zero ou IDs distintos.
   - **Continuidade de perdas:** como `decay_losses` é lido de `storage.get_total_decayed(r)`, substituir o armazenamento zera ou altera artificialmente o contador acumulado; a exigência `b_stor_id == a_stor_id` impede comparações que mascarem ou quebrem a continuidade de `decay_losses`.

---

## 4. Impacto sobre `C01`–`C12` e Revalidação Completa

- **Impacto sobre `C01`–`C12`:** **zero testes quebrados ou alterados**. Todos os 11 testes anteriores (`C01`–`C12`, `1.087` asserções), incluindo **`C02`** (capturas nos sinais `CHOPPING`, `FELLING` e `FALLEN`), já operavam em fronteiras estáveis (`stable_boundary == true`) e no mesmo armazenamento, passando integralmente sem necessidade de reposicionamento ou adaptação.
- **Resultado GREEN final (`02_green/d3_3_r1_green_v2_*`):**
  - Suíte: `res://tests/integration/test_r_03a_d3_3_regional_conservation.gd`
  - **Contagem anterior (`D3.3`):** `11/11` testes, `1.087` asserções.
  - **Contagem atual (`D3.3-R1`):** **`13/13` testes PASS, `0` falhas, `0` erros, `0` avisos, `1.147` asserções (`+2` testes, `+60` asserções), `20,47 s`, `GodotExitCode = 0`**.
- **Validação estática (`.\tools\validate.ps1`):** registrada em `03_static/validate_d3_3_r1.log` (`ValidateExitCode = 0`, `0` erros, `0` avisos, `219` scripts verificados, `DOCS_DESIGN_IMPORT_COUNT = 0`).

---

## 5. Limitações Remanescentes e Parecer Técnico sobre `D0-A04`

- **Limitações remanescentes preservadas:** limitação regional histórica `R01` (`TestMap/ResourceSources` sem `meta(&"region_id")` resolvido para `&"default"` até `T4`) e ausência de compartimento físico separado para pilhas avulsas externas na arquitetura `T3` (sinalizadas como `unmanaged_ground_pile_in_world`).
- **Parecer técnico atualizado sobre `D0-A04`:** **`COMPROVADA NO ESCOPO INTEGRAL AUTORIZADO`** (sujeita à auditoria independente do ChatGPT e homologação expressa do proprietário; `D3.4`, `D4` e `R-03B` seguem bloqueadas).
