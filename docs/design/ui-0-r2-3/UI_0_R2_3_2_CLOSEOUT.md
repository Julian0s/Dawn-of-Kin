# RELATÓRIO DE FECHAMENTO DOCUMENTAL — UI-0 R2.3.2
## Homologação Documental Condicionada do Design System Mestre D2.2

> **Decisão Expressa do Proprietário (22/11/2026):** **HOMOLOGAR O DESIGN SYSTEM MESTRE D2.2**, condicionado a duas correções documentais pontuais (classificação do armazenamento e procedência/licenças dos assets), mantendo integralmente a identidade visual **D2.2 — Marcos de Pedra e Eclipse** e **mantendo `UI-1` BLOQUEADA**.  
> **Estado Final:** **`HOMOLOGADO DOCUMENTALMENTE`** (ambas as condições verificadas e atendidas nesta branch).  
> **Branch de Fechamento:** `design/ui-0-r2-3-2-closeout` (derivada de `design/ui-0-r2-3-1-audit-fix` @ `a48dde9c6d7e80de2f69f05a4e56b41deee9d395`).  
> **Referência Artística Imutável:** `design/ui-0-r2-2-d2-visual-fidelity` @ `1ab8ffb78c269f3a659712491de91ab1f317e919`.

---

## 1. Registro da Decisão do Proprietário e Distinção de Autoridade

| Camada | Estado Oficial | Escopo e Limites |
|---|---|---|
| **Identidade Artística D2.2** (`1ab8ffb`) | **`APROVADA VISUALMENTE`** | Composição, paleta, silhuetas chanfradas, basalto/alabastro/ouro kintsugi, estelas, pedras escalonadas, lajes, maquetes, menu e capturas Godot preservados integralmente. |
| **Design System Mestre (`R2.3.2`)** | **`HOMOLOGADO DOCUMENTALMENTE`** | Manual normativo de tokens, biblioteca de componentes, VCG (10 passos), regras de proteção e ressalvas formais de acessibilidade/procedência. |
| **Implementação em Produção (`UI-1`)** | **`BLOQUEADA`** | A homologação documental **não autoriza** implementação de HUD/menus em produção, alterações de gameplay, merges ou criação de tags. |

---

## 2. Verificação das Duas Correções Condicionantes

### Correção 1 — Classificação do Armazenamento
- **Fontes de Verificação:** `docs/Dawn_of_Kin_GDD.md` (seção 4.1, linhas 185–186; seção D4/D5, linha 205; tabela de estágios, linha 262; seção 6.1, linha 313).
- **Texto Anterior (`R2.3.1 @ a48dde9`):**
  - Manual (§5): `02. Estoque / Depósito (IMPLEMENTADO/T3.7) • Lajes horizontais divididas em compartimentos chanfrados • Fundo grafite vulcânico com divisores kintsugi sutis`
  - Prancha (§09): `Estoque / Depósito (T3.7) — Lajes de basalto compartimentadas com divisores kintsugi finos.`
- **Texto Corrigido (`R2.3.2`):**
  - Manual (§5): `02. Armazenamento Inicial (IMPLEMENTADO T2) vs Depósito Rústico (DECIDIDO / PLANEJADO T3.7 / T4+)` — distinguindo explicitamente:
    - **Armazenamento Inicial (`IMPLEMENTADO` T2):** pilhas físicas na `CampStorageZone`, controle dos recursos coletivos disponíveis e transporte físico (`GatherResourceOrder` / `ConstructOrder`).
    - **Depósito Rústico e Armazenamento Protegido (`DECIDIDO` / `PLANEJADO` `T3.7` / `T4+`):** construção e capacidade prevista em `D4` (`18 Madeiras + 10 Pedras`), proteção de recursos com decaimento `0,0` (`D5`), múltiplos depósitos e armazenamento regional (`D8`).
  - Prancha (§09): `Armazenamento (T2) / Depósito (T3.7) — Pilhas iniciais (IMPLEMENTADO); proteção/depósitos (PLANEJADO T3.7).`

### Correção 2 — Procedência e Licenças dos Assets
- **Fontes de Verificação:** `docs/design/ui-0-r2-2/assets/`, `docs/design/ui-0-r2-2/assets/atlas_manifest.json` e histórico das etapas `UI-0 R1`–`R2.2`.
- **Texto Anterior (`R2.3.1 @ a48dde9`):**
  - Manual (§6): afirmava `"Obra original do projeto. Livre de royalties e sem restrições."`, `"Obra original de estúdio. Sem royalties."` e `"Declaração de Conformidade Legal: Nenhum dos arquivos acima infringe direitos autorais, contém marcas registradas de terceiros ou impõe restrições para distribuição em código aberto comercial."`
- **Texto Corrigido (`R2.3.2`):**
  - Manual (§6 e §6.1): substituídas todas as declarações jurídicas absolutas por categorização factual por origem:
    1. **Produzido para o projeto (metadado):** `atlas_manifest.json`.
    2. **Derivados compostos no projeto (script Python sobre textura base):** `d2_2_faithful_atlas.png`, `d2_2_menu_monolith.png`.
    3. **Gerados por ferramenta de IA (`image-generator`) no fluxo `UI-0`:** `d2_kintsugi_basalt.png`, `emblem_dawn_of_kin.png`, `portrait_alden.jpg`, `portrait_brena.jpg`, `d1_shelter_mini.png`, `d1_depot_mini.png` — descritos como *"Recurso incluído no projeto com procedência técnica registrada; condições de uso e redistribuição sujeitas aos termos aplicáveis e verificação jurídica"*.
    4. **Catálogos de terceiros:** nenhum asset gráfico de banco terceiro importado em `docs/design/ui-0-r2-2/assets/`.
- **Ressalvas Formais Registradas (§6.1):**
  - **Ressalva A (Assets gerados por IA e derivados):** não há certidão jurídica externa de licença anexada ao repositório; eventual redistribuição comercial/pública permanece sujeita aos termos da ferramenta geradora e verificação jurídica pelo proprietário.
  - **Ressalva B (Fontes de Sistema §2.2):** `Palatino Linotype`, `Georgia` e `Segoe UI` pertencem aos sistemas operacionais e não estão embutidas no repositório; antes da futura `UI-1`, deverá ser selecionada fonte com licença aberta verificada (ex.: SIL OFL) caso seja empacotada no build.

---

## 3. Integridade do Projeto e Arquivos Modificados

- **Arquivos modificados/adicionados nesta branch (`design/ui-0-r2-3-2-closeout`):**
  1. `docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md`
  2. `docs/design/ui-0-r2-3/D2_2_master_design_system_1920x1080.png`
  3. `docs/design/ui-0-r2-3/sources/D2_2_master_design_system_1920x1080.html`
  4. `docs/design/ui-0-r2-3/UI_0_R2_3_2_CLOSEOUT.md` (este relatório)
- **Intactos:** `main`, `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md`, `src/`, `scenes/`, `data/`, `tests/`, `docs/design/ui-0-r2-2/assets/*` e o diretório principal `C:\Projetos\Dawn of Kin`.
- **Visual Consistency Gate (VCG):** permanece vigente como gate obrigatório de 10 passos para qualquer futura tela ou proposta na `UI-1`.
