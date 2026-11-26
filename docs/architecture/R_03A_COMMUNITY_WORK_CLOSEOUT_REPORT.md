# Dawn of Kin — Relatório Consolidado de Encerramento da R-03A (`R-03A CLOSEOUT`)

> **Etapa:** `R-03A` — Seleção Múltipla de Fontes e Trabalho Comunitário Autônomo na `MainScene` (`D0`–`D4`, `D4-R1`, `D4-R2`)  
> **Data da Homologação Definitiva:** `26/11/2026`  
> **Status no momento deste registro documental:** `HOMOLOGADA DEFINITIVAMENTE` (`7c77e49d491f70c1867254f1a76a023050815431`) · `EM CONSOLIDAÇÃO DOCUMENTAL / FECHAMENTO CONTROLADO PARA DEVELOP` *(etapas de `merge --ff-only`, validação pós-integração, publicação final de `develop` e remoção do worktree permanecem marcadas como pendentes até a sua execução efetiva)*

---

## 1. Identificação da Entrega

- **Projeto:** *Dawn of Kin* (Godot `4.7.2.stable.official.ed1daf0bf`, GDScript tipado, `gl_compatibility`, `Jolt Physics`).
- **Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`
- **Branch candidata homologada:** `feat/r-03a-community-work-main-scene`
- **SHA técnico definitivamente homologado (`D4-R2`):** `7c77e49d491f70c1867254f1a76a023050815431`
- **Base anterior de `develop`:** `21c34ee645725a74f1fefac9db0309ec711ab5f2` (`R-02B.5` encerrada)
- **Branch `main` protegida (inalterada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Tags protegidas preservadas:** `t1-complete` (`3dcbba9386cbbee70025b47f4254ef097688a6e1`), `t2-complete` (`049ba9c7714c9b90b5515ae6ac30a28830454773`), `t3-3-complete` (`c7947c9630c102a9d77603cac0bae68678247c95`)
- **Checkout principal permanente:** `C:\Projetos\Dawn of Kin` (`develop`)
- **Worktree candidato utilizado na construção da R-03A:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`
- **Acervo de evidências deste encerramento:** `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\CLOSEOUT\`

---

## 2. Resumo Executivo da Homologação Definitiva

Em `26/11/2026`, após auditorias independentes sucessivas no GitHub e execução dos testes humanos finais **`M1`–`M8` (`8/8 PASS`)** sobre o SHA técnico **`7c77e49d491f70c1867254f1a76a023050815431`**, o proprietário homologou definitivamente a **`R-03A`** completa (`D0`–`D4`, `D4-R1`, `D4-R2`), aceitando explicitamente como limitação conhecida não bloqueante exclusiva da `R-03A` o resultado sintético residual de `19,879 ms` em `1080p` CA no caso `D2-P01: 6_TREES_KEEPING_STONE_FOOD_ACTIVE`, sem alterar o orçamento nominal de `16,7 ms` do projeto, e autorizou exclusivamente a consolidação documental, integração fast-forward à `develop`, validação pós-integração, publicação de `develop` no GitHub, preservação das evidências e encerramento seguro do worktree candidato (`R-03B` permanece estritamente `PLANEJADA — NÃO AUTORIZADA`).

---

## 3. Cadeia Completa de Subetapas e SHAs (`develop` `21c34ee` → `7c77e49`)

| Subetapa | SHA | Síntese do Marco | Documento de Referência |
|---|---|---|---|
| **R1** | `294b0fe` | Primeira implementação da seleção múltipla e trabalho comunitário na `MainScene` | [R_03A_R1_community_work_main_scene_candidate_report.md](../testing/R_03A_R1_community_work_main_scene_candidate_report.md) |
| **R1.1** | `f77e99e` | Coleta de evidências focais pré-revisão de experiência | [R_03A_R1_1_focal_evidence_candidate_report.md](../testing/R_03A_R1_1_focal_evidence_candidate_report.md) |
| **D0** | `a39f3b5` | Plano revisado da experiência (`D0`) homologado documentalmente | [R_03A_D0_community_work_experience_revision_PLAN.md](R_03A_D0_community_work_experience_revision_PLAN.md) |
| **D1 → D1-R3** | `a56af98` → `9f5b307` → `5824c3e` → `9964a06` | Seleção independente (`clique`/`D1-B`/`Shift+clique`/`Shift+arraste`, desmarcação em terreno livre `H-F01`), autorização contextual D2.2 (`D1-C`) e `5/5` retestes `RH-R3-01`–`05` aprovados | [R_03A_D1_R3_shift_consistency_candidate_report.md](../testing/R_03A_D1_R3_shift_consistency_candidate_report.md) |
| **D2 → D2-R1** | `c9f1084` → `7c53187` | Cancelamento seletivo por categoria (selo mineral `×`/`×N`, vão transparente `6 px`), carga residual, auditoria adversarial `D2-A01`, suíte `D2-T01` (`7/7`, `319` asserções), `D2-P01` e `13` testes humanos | [R_03A_D2_R1_adversarial_cancellation_candidate_report.md](../testing/R_03A_D2_R1_adversarial_cancellation_candidate_report.md) |
| **D3.1 → D3.1-R1** | `6aa4c69` → `a88d98d` | Ciclo unificado de derrubada (`STANDING → CHOPPING → FELLING → FALLEN → DEPLETED`) e proteção inicial de reserva | [R_03A_D3_1_R1_reserve_protection_and_harvest_audit_candidate_report.md](../testing/R_03A_D3_1_R1_reserve_protection_and_harvest_audit_candidate_report.md) |
| **D3.2** | `a0bf3ae` | Precedência de ordem pessoal com exclusão por tarefa e liberação limpa; `8/8` testes humanos `HD3-01`–`HD3-08` (observação `HD3-06` preservada para `R-03B`) | [R_03A_D3_2_personal_order_precedence_candidate_report.md](../testing/R_03A_D3_2_personal_order_precedence_candidate_report.md) |
| **D3.3 → D3.3-R1** | `6a11941` → `e7d72e4` | Prova formal de conservação econômica regional (`D0-A04`), reconciliação histórica e auditoria adversarial (`D3.3-A01`) | [R_03A_D3_3_R1_adversarial_conservation_audit_candidate_report.md](../testing/R_03A_D3_3_R1_adversarial_conservation_audit_candidate_report.md) |
| **D3.4** | `5330625` | Consolidação técnica da `D3` (`93/93` suítes, `706/706` testes, `33.845` asserções) | [R_03A_D3_4_d3_consolidation_candidate_report.md](../testing/R_03A_D3_4_d3_consolidation_candidate_report.md) |
| **D4** | `94744ec` | Auditoria visual, desempenho CA/DC e protocolo `M1`–`M8` | [R_03A_D4_final_audit_candidate_report.md](../testing/R_03A_D4_final_audit_candidate_report.md) |
| **D4-R1** | `b088620` | Correção visual `D4-A01` (sobreposição dos banners superiores) e otimizações focais `D4-P01`/`D4-P02` (`GatherSlotPlanner` + sinais em lote) | [R_03A_D4_R1_visual_fix_and_performance_investigation_report.md](../testing/R_03A_D4_R1_visual_fix_and_performance_investigation_report.md) |
| **D4-R2** | `7c77e49` | Auditoria focal e prova de equivalência algorítmica das otimizações `D4-R1` (`D4-R1-A01`–`A03`); **`95/95` suítes, `724/724` testes, `34.026` asserções**; SHA técnico homologado | [R_03A_D4_R2_algorithmic_equivalence_audit_report.md](../testing/R_03A_D4_R2_algorithmic_equivalence_audit_report.md) |

---

## 4. Contratos e Funcionalidades Entregues na `MainScene`

- **Seleção e HUD contextual (`D1` / `D1-R3`):** seleção independente de fontes (`WoodTree`, `StoneRock`, `FoodBush`) sem iniciar trabalho automaticamente; alternância `D1-B`; `Shift+clique` e `Shift+arraste` heterogêneos preservando captura no limiar de arraste (`C-03`/`C-02`); arraste sem `Shift` dedicado a unidades; desmarcação confiável em terreno livre (`H-F01`); `Esc` limpando seleção sem cancelar autorizações; autorização/reautorização explícita (`D1-C`) na HUD contextual com materialidade de pedra D2.2 (`[Machado N]`, `[Picareta N]`, `[Colheita N]`).
- **Cancelamento seletivo e custódia (`D2` / `D2-R1`):** selo mineral `×`/`×N` acima de cada laje com vão transparente de `6 px` e zero deslocamento; cancelamento isolado por categoria mantendo demais categorias e seleção ativas; propriedade por revisão em `GatherResourceOrder` (`D2-A01`); entrega final única preservando carga já coletada (`D2-B`).
- **Derrubada progressiva e conservação (`D3.1`–`D3.4`):** ciclo `STANDING → CHOPPING (2,5 s; 1,5× com 2 cortadores) → FELLING (0,50 s irreversível) → FALLEN → DEPLETED`, extração de madeira exclusivamente pós-`FALLEN`, reautorização explícita para troncos caídos após cancelamento durante `FELLING`, precedência da ordem pessoal (`D3.2`) com liberação de vaga e conservação regional (`D0-A04`).
- **Banners superiores e desempenho em lote (`D4-A01`, `D4-R1`, `D4-R2`):** reposicionamento dinâmico de `AutonomousGatherFeedback` (`8 px` abaixo de `PlacementStatusBanner` quando visível), `GatherSlotPlanner` determinístico e sinais em lote equivalentes (`D4-R1-A01`–`A03`).
- **Flags vigentes preservadas na `MainScene` (`main.tscn`):** `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false` (ativação da HUD global D2.2 reservada à `R-05B`; construção legada `P-REC-1` preservada até `R-04C`).

---

## 5. Consolidação das Auditorias Independentes e Revisões

Todas as questões levantadas pelas auditorias independentes durante a série `R-03A` foram tratadas e encerradas no escopo homologado:

- `D1` (`H-F01`/`H-F02`, `F01`/`C-03`/`C-02` focal): corrigido e encerrado em `D1-R1`–`D1-R3` (`9964a06`).
- `D2-A01` (`A01-R1`/`A01-R2`/`A01-R3A/B/C`) e lacunas `D2-T01`/`D2-P01`: corrigido cirurgicamente e provado em `D2-R1` (`7c53187`).
- `D0-A03` e proteção de reserva `D3.1-R1`: validados em `a88d98d` e encerrados na `D3.4` (`5330625`).
- `D3.3-A01` (`A01-A`, `A01-B`, fronteiras transacionais e identidade regional `D0-A04`): encerrado definitivamente na `D3.3-R1` (`e7d72e4`).
- `D4-A01` (sobreposição entre `AutonomousGatherFeedback` e `PlacementStatusBanner`), `D4-P01` e `D4-P02`: corrigidos em `D4-R1` (`b088620`).
- `D4-R1-A01`–`A03` (equivalência algorítmica de `GatherSlotPlanner`, distribuição/elegibilidade e sinais em lote): auditados e provados em `D4-R2` (`7c77e49`).

---

## 6. Síntese Técnica dos Testes Automatizados

### 6.1 Evidência técnica homologada na candidata (`D4-R2` @ `7c77e49`)
- `.\tools\validate.ps1`: **`0` erros e `0` avisos** em `221` scripts; `0` `.import` sob `docs/design/`.
- `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240`: **`95/95` suítes**, **`724/724` testes**, **`34.026` asserções**, **`68/68` lotes**, `Discovered=724 == ExecutedUnique=724`, `Missing=0`, `Duplicates=0`, `Failed=0`, `SuiteErrors=0`, `AGGREGATE_EXIT_CODE=0`.

### 6.2 Validação pós-integração na `develop`
- **Status no momento deste registro:** **`PENDENTE DE EXECUÇÃO PÓS-FAST-FORWARD`** *(será executada imediatamente após `git merge --ff-only` sobre a árvore limpa e registrada na atualização documental pós-integração).*

---

## 7. Registro Completo dos Testes Humanos

- **Testes humanos finais `M1`–`M8` (`26/11/2026`, SHA `7c77e49`, `720p` e `1080p` CA):** **`8/8 PASS`** (`M7-A` e `M7-B` aprovados de forma consolidada em `M7`), registrados em [R_03A_D4_final_manual_test_protocol.md](../testing/R_03A_D4_final_manual_test_protocol.md).
- **Testes humanos intermediários preservados:**
  - `D1-R3` (`9964a06`): **`5/5` retestes `RH-R3-01`–`RH-R3-05` PASS**.
  - `D2`/`D2-R1` (`7c53187`): **`13` cenários humanos PASS** (`HD2-01`–`HD2-10` + `HD2-R1-01`–`HD2-R1-03`).
  - `D3.2` (`a0bf3ae`): **`8` cenários humanos `HD3-01`–`HD3-08` PASS**.

---

## 8. Observação `HD3-06` Preservada para `R-03B`

Conforme registrado em `D3.2` e ratificado na homologação final: após concluir uma ordem pessoal de deslocamento (`MoveOrder`), o trabalhador pode receber outra tarefa comunitária ainda autorizada porque a exclusão vigente na `R-03A` opera **por tarefa**. O bloqueio e retorno automático comunitário com intervalo configurável após ordem pessoal (**`D-05`**) permanece reservado à **`R-03B`**.

---

## 9. Limitação Conhecida Explícita e Aceita (`D2-P01` em `1080p` CA)

- **Caso:** `D2-P01: 6_TREES_KEEPING_STONE_FOOD_ACTIVE` (medição de estresse sintético em lote máximo de autorização simultânea na `R-03A`).
- **Resultado em `D4-R2` (`7c77e49`, tomada CA):** `1280×720` com `p95 = 16,445 ms`; **`1920×1080` com `p95 = 19,879 ms`** (`P04` na mesma rodada: `12,516 ms` em `720p` e `14,122 ms` em `1080p`).
- **Decisão do proprietário (`26/11/2026`):** aceito explicitamente como **limitação conhecida não bloqueante exclusiva para o encerramento da `R-03A`**, registrada em [docs/KNOWN_ISSUES.md](../KNOWN_ISSUES.md) §6, **sem relaxar ou alterar o orçamento nominal de `16,7 ms`** do projeto para etapas subsequentes.

---

## 10. Estado de `project.godot` e Arquivos Protegidos

- O arquivo local `project.godot` no checkout principal `C:\Projetos\Dawn of Kin` (`SHA-256 = AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`) teve cópia de segurança verificada byte a byte antes da integração em `evidencias/R-03A/CLOSEOUT/02_protected_local_files/project.godot.backup`.
- A comparação `git diff develop feat/r-03a-community-work-main-scene -- project.godot` confirmou diff versionado **vazio**, garantindo integração fast-forward sem conflito ou sobrescrita da cópia local protegida.

---

## 11. Integração Fast-Forward à `develop`

- **Status no momento deste registro:** **`PENDENTE DE EXECUÇÃO`** *(será executada em `C:\Projetos\Dawn of Kin` via `git merge --ff-only feat/r-03a-community-work-main-scene`, seguida de verificação do hash de `project.godot` e prova de diff executável vazio entre `7c77e49` e a ponta integrada).*

---

## 12. Publicação da `develop` no GitHub

- **Status no momento deste registro:** **`PENDENTE DE EXECUÇÃO`** *(a candidata `feat/r-03a-community-work-main-scene` recebe primeiro este commit documental; após validação pós-integração e limpeza de worktree, `develop` é publicada via `git push origin develop`).*

---

## 13. Verificação Pós-Integração

- **Status no momento deste registro:** **`PENDENTE DE EXECUÇÃO`** *(executará `validate.ps1`, `run_tests.ps1 -Segmented`, smoke de flags da `MainScene` na árvore integrada e smoke seguro no checkout principal).*

---

## 14. Inventário de Não Rastreados e Encerramento do Worktree Candidato

- **Status no momento deste registro:** **`PENDENTE DE EXECUÇÃO`** *(inventário completo de não rastreados/ignorados em `C:\Projetos\Dawn_of_Kin_wt_r_03a` e remoção via `git worktree remove` sem `--force` ocorrerão após a validação pós-integração).*

---

## 15. Inventário de Evidências, Backups e Manifesto `SHA-256`

- **Diretório oficial do encerramento:** `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\CLOSEOUT\` (`00_git_baseline` a `09_git_final`).
- **Base `D4-R2` verificada:** manifesto `evidencias\R-03A\D4\D4-R2\MANIFEST_SHA256.txt` validado (`SHA-256 = 8525270f4d04c01ad441ecf9b58cf6e8f15bb4fab2602328aa9a14f4c4457e81`).
- **Manifesto final do `CLOSEOUT`:** será gerado e verificado ao término da etapa com `MANIFEST_VERIFY_FAIL=0`.

---

## 16. Próxima Etapa Planejada (Não Autorizada)

- **`R-03B` — Casa Fundadora e `ControlMode` na `MainScene`:** permanece estritamente **`PLANEJADA — NÃO AUTORIZADA`** até autorização expressa do proprietário após conclusão e auditoria deste encerramento.

---

## 17. Checklist Obrigatório de Encerramento (`AGENTS.md` §6.3)

| # | Item | Estado Atual |
|---:|---|---|
| 1 | Incremento corretamente identificado (`R-03A CLOSEOUT`) | `PASS` |
| 2 | Escopo autorizado respeitado (sem `R-03B`, sem mudanças em código/testes/cenas) | `PASS` |
| 3 | Código e documentos nos locais corretos | `PASS` |
| 4 | Testes aplicáveis concluídos (`validate.ps1`, regressão segmentada, `M1`–`M8` + validação pós-integração) | `EM EXECUÇÃO` *(D4-R2 PASS; pós-integração pendente)* |
| 5 | Auditoria independente concluída via GitHub | `PASS` *(sobre `7c77e49`, aguardando conferência final pós-closeout)* |
| 6 | Homologação registrada pelo proprietário (`26/11/2026`) | `PASS` |
| 7 | Integração à `develop` confirmada | `PENDENTE` |
| 8 | Validação pós-integração concluída | `PENDENTE` |
| 9 | Alterações publicadas conforme autorização | `EM EXECUÇÃO` |
| 10 | Documentação sincronizada | `PASS` |
| 11 | Evidências organizadas fora do checkout principal | `EM EXECUÇÃO` |
| 12 | Arquivos temporários classificados | `EM EXECUÇÃO` |
| 13 | Backups necessários preservados (`project.godot.backup` + `D4-R2`) | `PASS` |
| 14 | Worktrees dispensáveis encerrados (`C:\Projetos\Dawn_of_Kin_wt_r_03a`) | `PENDENTE` |
| 15 | Estado Git conhecido | `PASS` |
| 16 | Ausência de resíduos abandonados | `PENDENTE` |
| 17 | SHA final registrado | `EM EXECUÇÃO` |
| 18 | Próximo incremento identificado sem antecipar sua execução (`R-03B` não autorizada) | `PASS` |
