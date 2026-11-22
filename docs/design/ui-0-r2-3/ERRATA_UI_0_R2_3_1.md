# RELATÓRIO DE ERRATA — UI-0 R2.3.1
## Auditoria de Consistência Factual do Design System Mestre D2.2

> **Status:** `CANDIDATO DOCUMENTAL` (aguardando revisão e homologação expressa do proprietário).  
> **Base auditada:** `design/ui-0-r2-3-design-system` @ commit `8ba3f75a41be5239540ee258e5c933f4a50e1902`.  
> **Branch de correção:** `design/ui-0-r2-3-1-audit-fix` (worktree isolado `C:\Projetos\Dawn_of_Kin_wt_ui_0_r2_3_1`).  
> **Preservação visual:** Nenhuma ilustração, composição, silhueta, proporção ou asset da identidade visual aprovada **D2.2 — Marcos de Pedra e Eclipse** (`1ab8ffb`) foi alterado.

---

## Tabela Consolidada de Errata (6 Eixos Auditados)

| # | Eixo | Informação Anterior Incorreta (`R2.3 @ 8ba3f75`) | Correção Aplicada (`R2.3.1`) | Evidência Verificada nos Arquivos Reais | Arquivos Afetados |
|---|---|---|---|---|---|
| **1** | **Custos e Nomes de Construção** | Prancha exibia `Abrigo de Sobrevivência (10 Mad · 4 Ped)` e `Depósito de Recursos (15 Mad · 8 Ped)`. Manual repetia nomes não canônicos. | Corrigido para **`Abrigo Básico` (`12 Mad · 6 Ped`)** e **`Depósito Rústico` (`18 Mad · 10 Ped`)**, explicitando tratar-se de parâmetros provisórios `D4`. | `docs/Dawn_of_Kin_GDD.md` (linhas 203–205); `data/buildings/shelter_basic.tres`; `data/buildings/storage_depot.tres`. | `DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` (§1.2, §3 C06/C08, §6); `D2_2_master_design_system_1920x1080.html` & `.png` (§05). |
| **2** | **Desempenho e Escopo de Testes** | Prancha e §7.2 citavam `147 FPS`, `> 140 FPS`, `"menos de +40 draw calls"` e `6.469 asserções` no contexto do Atlas UI. | Removidos `147 FPS`, `> 140 FPS` e `6.469 asserções` (que pertence à suíte T2 em `AGENTS.md`). Registradas medições reais isoladas sem V-Sync (`HUD 1080p: média 8,136 ms, p95 10,828 ms, p99 12,034 ms, +40 DC`; `Construção: +66 DC`; `Linhagem: +37 DC`; `720p: p95 11,563 ms`), com limitação explícita de benchmark isolado. | `docs/design/ui-0-r2-2/godot_showcase/benchmark_results_r2_2.json`; `docs/architecture/UI_0_R2_2_D2_visual_fidelity_PROPOSAL.md` (§4.2); `AGENTS.md`. | `DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` (§7.2); `D2_2_master_design_system_1920x1080.html` & `.png` (Badge, §03). |
| **3** | **Contraste e Acessibilidade (WCAG 2.1)** | `#385B2A` sobre `#141618` constava como `5.6:1`; demais rácios da tabela §2.1 estavam aproximados/imprecisos e sem distinção texto × indicador × decorativo. | Recalculados todos os rácios pela fórmula WCAG 2.1: `#385B2A` vs `#141618` = **`2,33:1`** (abaixo de 3:1); `#6A5832` vs `#141618` = **`2,64:1`**; `#DFBC72` = `10,00:1`; `#F5D996` = `13,17:1`; `#F4EFE4` = `15,82:1`; `#B8B2A5` = `8,59:1`; `#1D1813` vs `#F5F0E6` = `15,51:1`; `#5B4B3A` = `7,36:1`; `#A5C98B` = `9,78:1`; `#F2B8AC` = `10,56:1`; `#C66A58` = `4,84:1`; `#EAB464` = `9,68:1`. Adicionada §2.1.1 com regra de uso (`#385B2A` apenas como fundo com `#F4EFE4` [`6,79:1`] ou pareado com `#A5C98B`). | Cálculo linearizado sRGB oficial WCAG 2.1 executado sobre os hex exatos de `ui0_r2_2_d2_faithful_showcase.gd` e CSS D2. | `DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` (§2.1, §2.1.1); `D2_2_master_design_system_1920x1080.html` & `.png` (§07 swatch). |
| **4** | **Recursos Futuros** | §5 listava sistemas futuros sem marcar claramente que são propostas artísticas ilustrativas, usando tom de obrigação ("deverão estritamente"). | Classificados explicitamente como `PROPOSTA DE EXTENSIBILIDADE` com marcadores do GDD (`PLANEJADO T3.5/T5`, `IMPLEMENTADO/T3.7`, `PLANEJADO T4`, `PLANEJADO Cap. 3`), esclarecendo que não criam obrigações de gameplay. | `docs/Dawn_of_Kin_GDD.md` (tabela de estágios e decisões `DECIDIDO`/`PLANEJADO`/`PROPOSTA`). | `DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` (§5); `D2_2_master_design_system_1920x1080.html` & `.png` (§09). |
| **5** | **Autoridade Documental** | Documento intitulava-se `OFICIAL (PROPOSTA MASTER R2.3)` e `ESPECIFICAÇÃO CANÔNICA DE UI/UX`. | Mantida a **D2.2** como *identidade visual aprovada* e reclassificado o Design System **R2.3.1** como **`CANDIDATO DOCUMENTAL`** até homologação expressa do proprietário. | Diretriz do proprietário na solicitação `UI-0 R2.3.1` e `AGENTS.md`. | `DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` (cabeçalho); `D2_2_master_design_system_1920x1080.html` & `.png` (título, badge, rodapé). |
| **6** | **Regras de Preservação & Acessibilidade** | §10 podia dar margem a interpretar que limitações de acessibilidade não poderiam ser reportadas sem risco de conflito com a proteção da D2.2. | Mantida a vedação absoluta a alterações visuais unilaterais/silenciosas da D2.2, explicitando que problemas de legibilidade, acessibilidade e usabilidade devem ser diagnosticados e submetidos ao proprietário com propostas compatíveis. | Diretriz do proprietário na solicitação `UI-0 R2.3.1`. | `DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` (§10); `D2_2_master_design_system_1920x1080.html` & `.png` (rodapé). |

---

## Verificação de Integridade
- `git diff 8ba3f75..HEAD` restringe-se exclusivamente a `docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` e `docs/design/ui-0-r2-3/`.
- Nenhuma modificação em `src/`, `scenes/`, `data/`, `tests/`, `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md`, `docs/design/ui-0-r2-2/assets/` ou `C:\Projetos\Dawn of Kin`.
- `UI-1` permanece estritamente **BLOQUEADA**.
