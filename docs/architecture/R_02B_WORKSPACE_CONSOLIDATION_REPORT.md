# Relatório de Consolidação do Workspace e Governança (`R-02B`)

> **Projeto:** *Dawn of Kin*  
> **Etapa:** `R-02B` (`R-02B.0` a `R-02B.5`) — Consolidação Física do Workspace e Encerramento da Reorganização  
> **Data:** 24 de novembro de 2026  
> **Branch Canônica de Desenvolvimento:** `develop` @ `21c34ee645725a74f1fefac9db0309ec711ab5f2` (ancestral linear a partir de `3032f4079a8b3a39806b159c0771d980198ec848`, preservando `main` em `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`)  
> **Status:** **`HOMOLOGADO` / `INTEGRADO À DEVELOP` / `ENCERRADO`** *(homologação definitiva da `R-02B.5` em `21c34ee645725a74f1fefac9db0309ec711ab5f2` deliberada pelo proprietário em 24/11/2026; etapa `R-03A` autorizada em implementação isolada).*

---

## 1. Resumo Executivo

A etapa `R-02B` unificou o checkout principal do projeto em `C:\Projetos\Dawn of Kin` sobre a linha canônica `develop`, preservando integralmente o histórico Git, todas as referências remotas e locais e os artefatos históricos fora do repositório versionado:

- **`R-02B.0`:** inventário forense de worktrees, branches, tags, alterações locais e plano reversível.
- **`R-02B.1` / `R-02B.1-C` / `R-02B.1-D`:** backup forense completo (`bundle` Git + arquivo `.zip` + manifestos SHA-256 + prova de restauração) homologado localmente pelo proprietário (`R02B-D1`).
- **`R-02B.2`:** criação e publicação de `origin/develop` em `3032f4079a8b3a39806b159c0771d980198ec848` (`R02B-D3`, `R02B-D4`, `R02B-D8`).
- **`R-02B.3`:** arquivamento reversível dos `159` arquivos locais originais (`docs/historico/`, diff histórico de `project.godot`, inventários e evidências) para fora do checkout Git, migração de `C:\Projetos\Dawn of Kin` para `develop` @ `3032f40` e validação completa (`208/208` scripts, `85/85` suítes, `592/592` testes) + aceite humano `M1`–`M3` (`R02B-D10`).
- **`R-02B.4`:** verificação de integridade dos backups existentes (`R02B-D11`), remoção controlada dos `22` worktrees históricos redundantes e do clone temporário de restauração (`R02B-D9`), mantendo todas as `59` branches locais e `60` referências remotas intactas.
- **`R-02B.5`:** normalização dos artefatos incidentais deixados pelo editor (`project.godot`, `assets/placeholder/mat_ground_placeholder.tres`, cena solta `ui_1_d2_2_sandbox.tscn` na raiz e `200` arquivos `.import` em `docs/design/`), prevenção permanente via [docs/design/.gdignore](../design/.gdignore), atualização dos documentos normativos de governança e validação integral final.

---

## 2. Topologia Git Resultante e Reconciliação de Ancestralidade

| Referência | SHA | Estado |
|---|---|---|
| `main` / `origin/main` | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` | Preservada intacta (`152` commits atrás / `0` à frente de `3032f40`) |
| Base `R-02A R1` / início da `develop` | `3032f4079a8b3a39806b159c0771d980198ec848` | Ancestral direto da série `R-02B.5` em `develop` |
| Worktree ativo único | `C:\Projetos\Dawn of Kin` | Único diretório ativo do repositório (`develop`) |
| Branches e tags históricas | `59` locais / `60` remotas efetivas / `3` tags | Preservadas sem exclusões destrutivas |

Das `22` branches ligadas aos worktrees históricos encerrados em `R-02B.4`, **`17`** são ancestrais estritos de `3032f40` e **`5`** possuem commits exclusivos preservados integralmente nas referências locais e remotas (`audit/global-vision-and-design` `+2`, `planning/t3-4-architecture` `+2`, `planning/t3-4-architecture-r2` `+6`, `planning/ui-1-0-integration-plan` `+1`, `planning/ui-1-0-r1-integration-plan` `+2` — este último com conteúdo incorporado semanticamente ao plano reconciliado sem merge de branch). Os logs brutos de reconciliação permanecem arquivados fora do repositório em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\registros_de_organizacao\R-02B.5\`.

---

## 3. Prevenção de Resíduos de Importação (`FIN-18` e `FIN-19`)

- A abertura de `C:\Projetos\Dawn of Kin` no editor da Godot `4.7.2` gerava `200` arquivos `.import` em `docs/design/` (subpastas de referência/conceitos D2.2).
- Uma varredura em `src/`, `data/`, `levels/`, `tests/`, `tools/` e `project.godot` confirmou que nenhuma cena ou script carrega esses arquivos como `Resource`; apenas [tests/unit/test_ui_1_1a_foundation.gd](../../tests/unit/test_ui_1_1a_foundation.gd) lê diretamente arquivos originais via `FileAccess`.
- Os `200` arquivos `.import` gerados foram removidos (mantendo 100% dos arquivos originais PNG/JPG/HTML/MD) e foi adicionado [docs/design/.gdignore](../design/.gdignore), impedindo que o editor importe ou crie `.import`/`.uid` sob `docs/design/` em execuções futuras.

---

## 4. Políticas Permanentes Consolidadas

1. **Integração de incrementos homologados (`AGENTS.md` §5):** toda entrega homologada em sua etapa deve ser integrada com segurança em `develop` antes do início da etapa seguinte; `main` só recebe integrações mediante autorização expressa do proprietário.
2. **Organização contínua do workspace (`AGENTS.md` §5):** limite permanente de `1` checkout principal (`C:\Projetos\Dawn of Kin`) + no máximo `1` worktree temporário ativo quando uma etapa isolada exigir isolamento, com arquivamento de evidências e logs sempre fora do repositório Git (`C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\`).
3. **Estado preservado na `MainScene` (`main.tscn`):** permanecem inalterados `use_provenance_economy = true`, `automatic_cancellation_recovery = true` e `use_d2_2_hud = false` (ativação da HUD D2.2 prevista apenas em `R-05B`, após conclusão de `R-03A`–`R-03D` e `R-04A`–`R-04C`).
4. **Próxima etapa autorizada:** `R-03A` (seleção múltipla e coleta autônoma na `MainScene`), autorizada pelo proprietário em `24/11/2026` após homologação definitiva da `R-02B.5` em `21c34ee645725a74f1fefac9db0309ec711ab5f2`.

---

## 5. Validação Técnica Registrada na `R-02B.5`

- `.\tools\validate.ps1` (com `docs/design/.gdignore` ativo): **`0` erros, `0` avisos, `208` scripts verificados** (exit code `0`).
- Segunda passagem `godot --headless --import`: **`0` arquivos `.import` e `0` `.gd.uid` regenerados** sob `docs/design/` ou qualquer outro diretório.
- `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`: **`85/85` suítes descobertas, `0` duplicatas, `0` omissões, `592/592` testes PASS, `28.982` asserções** (exit code `0`).
- `.\tools\run_game.ps1 -Resolution 1280x720 -QuitAfter 45 -FailOnWarnings`: exit code `0`, sem erros ou avisos; verificação visual da `MainScene` (`use_d2_2_hud = false` preservado) e do sandbox D2.2 (`tests/visual/ui_1_d2_2_sandbox.tscn`) íntegra.
