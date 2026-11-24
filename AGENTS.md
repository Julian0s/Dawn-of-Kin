# Dawn of Kin — Regras Permanentes de Engenharia e Governança

## 1. Fonte de verdade, escopo e estado real do repositório

- **Documentos canônicos obrigatórios (ler antes de propor qualquer alteração):**
  1. [docs/Dawn_of_Kin_GDD.md](docs/Dawn_of_Kin_GDD.md) — **GDD consolidado único (`v1.3` homologada em `R-02A R1`)**, incorporando as decisões canônicas `D-01`–`D-13`, `P-REC-1`–`P-REC-4`, `D-ERR-1 B` e `D-ERR-2 C`.
  2. [docs/ROADMAP_MESTRE.md](docs/ROADMAP_MESTRE.md) — **Roadmap Mestre único e Matriz de Decisões e Rastreabilidade** (`R-01` a `T3.9` + horizonte `T4`–`T8`).
  3. [docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md](docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md) — **Design System Mestre D2.2 ("Marcos de Pedra e Eclipse")** (Cláusula Pétrea visual na Seção 10).
  4. [docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md](docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md) — **Plano técnico da série `UI-1`** (com Adendo de Reconciliação `R-02A R1`).
  5. [docs/architecture/R_02B_WORKSPACE_CONSOLIDATION_REPORT.md](docs/architecture/R_02B_WORKSPACE_CONSOLIDATION_REPORT.md) — **Registro versionado da reorganização `R-02B`**.
- **Projeto:** jogo single-player em **Godot 4.7.2 / GDScript tipado**, RTS isométrico 3D (`gl_compatibility`, `Jolt Physics`, referência de desempenho Intel UHD Graphics 620 em `1920×1080`, meta $p95 \le 16,7\text{ ms}$ em tomada CA).
- **Estado real verificado do projeto (em 24/11/2026):**
  - **`T1 — Fundação RTS`:** `HOMOLOGADO` e `INTEGRADO` na `main` (tag `t1-complete`, commit `2808799`).
  - **`T2 — Trabalho e Recursos`:** `HOMOLOGADO` em 14/11/2026 e `INTEGRADO` na `main` (tag `t2-complete`, commit `f7c2459`, 182/182 testes em 27 suítes, 21/21 manuais; benchmark CA `p95 = 9,757 ms` atendido; bateria DC `p95 = 33,038 ms` aceita como limitação conhecida não bloqueante).
  - **`T3.1`–`T3.6.1` na `main` (`25e0a20f1d6a2f10a9e059afe69759fbe263db4a`):** `HOMOLOGADO` e `INTEGRADO` na `main` — inclui `T3.1`–`T3.3` (`t3-3-complete` @ `3c6fc0b`), `T3.4` (`2a6cce6`), `T3.5.1` (`56d8e97`), `T3.5.2` (`fb31887`) e `T3.6.1` (`25e0a20`, módulo matemático puro `D3`). O fluxo antigo de construção (`D2`/`D3`/`DEC-11B`) permanece ativo em transição segura (`P-REC-1`) até `R-04C`. A `main` permanece preservada em `25e0a20` até autorização específica de promoção.
  - **Cadeia linear homologada na base canônica `develop` (ainda NÃO promovida à `main`):** `T3.6.2 Bloco A` (`ec17f42`, `use_provenance_economy = true` ativo em `main.tscn`), Design System `D2.2` (`cdd9f2f`, homologado documentalmente), plano `UI-1.0 R1` (`7dbfeb1`), série **`UI-1` (`UI-1.1A R2` @ `a02aa97`, `UI-1.1B R1` @ `a6542ca`, `UI-1.2` @ `9f84d33` e `UI-1.3 R1` / `R-01` @ `c4a6361`)** e reconciliação documental **`R-02A R1`** (`docs/r-02a-canonical-reconciliation` @ `3032f40`, `GDD v1.3` homologada). Em `main.tscn`, `use_d2_2_hud = false` permanece preservado até **`R-05B`** (`D-ERR-1 B`).
  - **Reorganização do workspace (`R-02B`):**
    - `R-02B.0`–`R-02B.1-D`: inventário forense e preservação local concluídos e homologados (backup forense `Dawn_of_Kin_R02B_20261123_213528_3032f40`, com dispensa de nuvem `R02B-D2` / `R02B-D11`).
    - `R-02B.2`: branch canônica `develop` criada e publicada em `3032f40` (`origin/develop`), arquivo histórico local organizado em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local`.
    - `R-02B.3`: checkout principal `C:\Projetos\Dawn of Kin` migrado para `develop` e homologado (`208/208` scripts `0/0`, `85/85` suítes, `592/592` testes, `28.983` asserções e testes humanos `M1`–`M3` aprovados).
    - `R-02B.4`: remoção controlada dos `22` worktrees auxiliares, consolidação de duplicatas, remoção do ZIP redundante na raiz e remoção do clone temporário (`R02B-D9`), restando apenas `1` checkout principal permanente e `59` branches locais / `60` remotas efetivas preservadas.
    - **`R-02B.5` (`HOMOLOGADO` / `INTEGRADO À DEVELOP` / `ENCERRADO` @ `21c34ee645725a74f1fefac9db0309ec711ab5f2`):** normalização dos artefatos do editor, prevenção localizada `docs/design/.gdignore` (resolvendo `FIN-18`/`FIN-19`), atualização normativa e publicação na `develop` — **definitivamente homologada pelo proprietário em 24/11/2026 após auditoria independente do ChatGPT; reorganização `R-02B` integralmente encerrada**.
  - **Itens explicitamente `NÃO HOMOLOGADO` (nunca declarar como homologados):**
    - `T3.6.4-R1` (`8deeef1`, retestes manuais `D3-04`/`D3-07` pendentes; mantida em transição `P-REC-1` até `R-04C`).
    - Protótipos/sandboxes `UX-1` (`0e78f9a`) e `RUX-1`/`RUX-2A`/`RUX-2B` (`cddd582`) — validados apenas em sandbox/testes headless; pendentes de integração jogável e aceite humano na `MainScene` em `R-03A`–`R-03D`.
  - **Candidata atual em auditoria (`IMPLEMENTADO` / `VALIDADO TECNICAMENTE` / `PUBLICADO` em branch candidata — `NÃO AUDITADO`, `NÃO HOMOLOGADO`, `NÃO INTEGRADO À DEVELOP`):** **`R-03A` — Seleção múltipla de fontes e trabalho comunitário automático na `MainScene`** (branch candidata isolada `feat/r-03a-community-work-main-scene` a partir de `develop` @ `21c34ee`; relatório técnico em [docs/testing/R_03A_community_work_main_scene_candidate_report.md](docs/testing/R_03A_community_work_main_scene_candidate_report.md); testes humanos `M1`–`M8` **`PENDENTES`**; `R-03B`–`T3.9` e `T4`–`T8` permanecem **`BLOQUEADO`**).

## 2. Taxonomia obrigatória de status (nunca simular conclusão)

Diferenciar rigorosamente em todo documento, relatório e resposta os marcadores normativos vigentes em [docs/ROADMAP_MESTRE.md](docs/ROADMAP_MESTRE.md) §1 e [docs/Dawn_of_Kin_GDD.md](docs/Dawn_of_Kin_GDD.md):

- **Taxonomia base de produto/documentação:** **`DECIDIDO`** · **`PLANEJADO`** · **`IMPLEMENTADO`** · **`VALIDADO`** · **`HOMOLOGADO`** · **`INTEGRADO`** · **`ATIVO NA MAINSCENE`** · **`PROPOSTA`** · **`ABERTO`** · **`SUBSTITUÍDO`** · **`DESCARTADO`**.
- **Taxonomia obrigatória do ciclo de integração de incrementos (determinação permanente do proprietário):**
  - **`PLANEJADO`** (escopo definido, não implementado)
  - **`IMPLEMENTADO`** (código existente)
  - **`VALIDADO TECNICAMENTE`** (testes técnicos executados e aprovados)
  - **`AUDITADO`** (revisão independente concluída)
  - **`HOMOLOGADO`** (aceite expresso do proprietário)
  - **`INTEGRADO À DEVELOP`** (commits incorporados à base canônica `develop`)
  - **`VALIDADO PÓS-INTEGRAÇÃO`** (funcionamento confirmado na base consolidada)
  - **`PUBLICADO`** (alterações autorizadas disponíveis no GitHub)
  - **`ENCERRADO`** (integração, documentação e organização integralmente concluídas)

Nunca confundir: código existente com funcionalidade homologada; homologação com integração; integração Git com disponibilidade jogável na `MainScene`; publicação no GitHub com encerramento completo; ou aprovação em sandbox com homologação da experiência na `MainScene`. Em relatórios técnicos e auditorias, distinguir sempre **testado automaticamente** vs **testado manualmente**, sinalizar itens **`NÃO VERIFICADO`**, **`NÃO HOMOLOGADO`**, **`PENDENTE`** ou **`BLOQUEADO`**, e nunca misturar resultados históricos (com SHA de origem) com resultados da execução atual.

## 3. Regra permanente de acessibilidade pela `MainScene` e sequência incremental

- **Acessibilidade obrigatória na `MainScene`:** toda funcionalidade homologada para o jogador deve possuir **caminho de acesso verificável a partir da `MainScene`** (`res://src/main/main.tscn`, executável por `F5` / `.\tools\run_game.ps1`), e não existir apenas em cenas de sandbox isoladas. Exceções temporárias (como `use_d2_2_hud = false` na `UI-1.1A`–`UI-1.4` até `R-05B`) devem ser explicitamente autorizadas e documentadas.
- **Um incremento por vez:** executar rigorosamente **um único prompt/incremento autorizado por vez** (análise + plano revisável antes de alterar código; parada obrigatória ao concluir cada incremento para auditoria independente e decisão do proprietário).
- **Respeito à ordem canônica (`D-ERR-1 B` e `D-ERR-2 C`):** não antecipar ativação de `use_d2_2_hud = true` antes de `R-05B`, não implementar `UI-1.5` antes de `T3.8`, não remover o mecanismo antigo de construção antes da homologação completa de `R-04A`–`R-04C` (`P-REC-1`), e não implementar `T4`–`T8` antes da conclusão formal da `T3`.

## 4. Qualidade antes da velocidade

- Priorizar corretude, robustez, legibilidade, extensibilidade responsável e boa experiência de jogo. Entrega rápida, por si só, não é critério de sucesso.
- Avaliar o workspace real: conferir arquivos, versão instalada da Godot (`4.7.2`), renderer, hardware disponível e estado exato do Git antes de propor arquitetura.
- Obrigação de confrontar relatórios com documentação e código real: nunca afirmar que testes foram executados ou que arquivos estão sincronizados sem validação e evidência concreta.
- Dividir planos aprovados em incrementos pequenos com objetivo, arquivos afetados, riscos, teste e critério de aceite.
- Se um teste falhar, diagnosticar causa raiz e corrigir sem ocultar avisos, desabilitar funcionalidades ou remover testes para aparentar sucesso.
- Não criar código monolítico ou *god scripts*; separar responsabilidades (câmera, seleção, ordens, navegação, economia, construção, interface) com GDScript tipado, nomes consistentes e tratamento explícito de estados inválidos. Não inventar dependências nem adicionar plugins sem aprovação.
- Não mascarar funcionalidades ausentes com placeholders anunciados como prontos. Assets e parâmetros temporários (`D4`, `DT-03`) são aceitáveis apenas se declarados explicitamente.
- Nunca substituir silenciosamente um comportamento aprovado ou a identidade visual D2.2 (Cláusula Pétrea). Se houver trade-off de qualidade, expor opções e solicitar decisão.

## 5. Política Git permanente e alterações seguras

- **Estratégia de branches:**
  - **`main`:** linha estável formalmente homologada para promoção. Permanece no SHA autorizado (`25e0a20`) até que a cadeia de desenvolvimento atinja estabilidade apropriada e receba autorização específica de promoção; integração em `develop` **nunca** promove automaticamente para `main`.
  - **`develop`:** linha canônica contínua de desenvolvimento (criada em `3032f40` e avançada linearmente). O checkout principal `C:\Projetos\Dawn of Kin` acompanha `develop`, e todo novo incremento deve partir da ponta homologada atual de `develop` (`P-REC-4`), nunca de branches históricas antigas.
  - **Branches temporárias (quando necessário):** `feat/*`, `fix/*`, `docs/*`, `audit/*`, `planning/*`. Não criar branches ou worktrees sem finalidade concreta. Branches históricas existentes permanecem preservadas; exclusões futuras exigem análise e autorização compatível.
- **Regras de integração:**
  - Uma funcionalidade homologada **não** deve permanecer isolada indefinidamente: implementação e integração à `develop` fazem parte do mesmo ciclo obrigatório.
  - Preferir **fast-forward** quando a ancestralidade permitir. Antes da integração: confirmar ancestralidade, ausência de divergências, homologação, conjunto exato de commits, dependências e estados transitórios. Após a integração: confirmar SHA final, validar pós-integração, publicar conforme autorização, atualizar documentação e encerrar worktree temporário.
  - **Proibido:** merges redundantes, cherry-picks indiscriminados, rebase/reescrita de histórico homologado, force push, integração automática de candidatas não homologadas ou comandos destrutivos (`git reset --hard`, `git clean -fd`, `git restore .`) sem identificação, preservação e autorização explícita.
- **Coerência documental:** decisões canônicas vivem no GDD e no Roadmap Mestre; documentos históricos recebem adendos de reconciliação sem apagamento do histórico.

## 6. Ciclo obrigatório de desenvolvimento e checklist de encerramento

### 6.1 Ciclo obrigatório de desenvolvimento (20 etapas)
1. Consultar GDD, arquitetura, Roadmap Mestre e regras vigentes.
2. Identificar a base canônica e confirmar o SHA em `develop`.
3. Definir o escopo exato do incremento.
4. Definir critérios de aceite e criticidade.
5. Obter autorização.
6. Implementar.
7. Executar validação técnica.
8. Publicar a candidata em referência de revisão quando autorizado (sem confundir com promoção à `develop`/`main`).
9. Realizar auditoria independente.
10. Executar testes humanos exigidos pela criticidade.
11. Obter homologação expressa.
12. Integrar à `develop` mediante autorização.
13. Executar validação pós-integração.
14. Publicar a base integrada (`develop`).
15. Atualizar a documentação correspondente.
16. Arquivar evidências fora do checkout principal.
17. Encerrar worktrees temporários dispensáveis.
18. Verificar a organização final (prevenindo resíduos recorrentes).
19. Registrar o incremento como `ENCERRADO`.
20. Preparar somente a próxima etapa autorizável (um incremento por vez).

### 6.2 Política permanente de organização do workspace e prevenção de resíduos
- **Checkout principal único:** manter permanentemente `C:\Projetos\Dawn of Kin` na branch `develop`.
- **Limite de worktrees:** manter no máximo **1 checkout principal permanente** e **1 worktree temporário ativo** por incremento quando tecnicamente necessário (exceções exigem justificativa técnica e autorização). Todo worktree temporário deve registrar nome, branch, SHA de base, incremento, finalidade, responsável, condição de encerramento e destino das evidências; nunca acumular worktrees de incrementos encerrados.
- **Organização de arquivos e prevenção de resíduos:**
  - Backups e arquivos históricos residem fora do checkout principal (`C:\Projetos\Backups\`); manifestos históricos são imutáveis.
  - Evidências em diretórios padronizados; scripts auxiliares, capturas e artefatos temporários classificados com finalidade e condição de encerramento (nunca soltos na raiz).
  - Caches operacionais ignorados (`.godot/`) não são desorganização, mas dados locais insubstituíveis jamais devem ser descartados como lixo; exclusões potencialmente destrutivas exigem identificação, classificação, verificação de integridade, recuperação prevista e autorização compatível (a dispensa de segunda mídia `R02B-D11` foi exceção restrita à `R-02B.4`, não precedente para futuras exclusões).
  - Sempre investigar e prevenir na raiz a geração recorrente de resíduos (ex.: `docs/design/.gdignore` para impedir importação de pranchas documentais, sem usar `*.import`/`*.uid` globais). Nunca limpar o ambiente para ocultar alterações ou falhas.

### 6.3 Checklist obrigatório de encerramento de cada incremento
Antes de encerrar qualquer etapa (aplicando `N/A` com justificativa quando não aplicável, sem atribuir `PASS` sem verificação):
1. Incremento corretamente identificado.
2. Escopo autorizado respeitado.
3. Código e documentos nos locais corretos.
4. Testes aplicáveis concluídos (`validate.ps1`, regressão quando exigida, testes visuais/manuais na Godot `4.7.2` em `1280×720` e `1920×1080`, medições CA/DC quando aplicável).
5. Auditoria independente concluída via GitHub (SHA local == remoto e escopo exato).
6. Homologação registrada pelo proprietário.
7. Integração à `develop` confirmada.
8. Validação pós-integração concluída.
9. Alterações publicadas conforme autorização.
10. Documentação sincronizada.
11. Evidências organizadas.
12. Arquivos temporários classificados.
13. Backups necessários preservados.
14. Worktrees dispensáveis encerrados.
15. Estado Git conhecido (`git status`, branches, tags).
16. Ausência de resíduos abandonados.
17. SHA final registrado.
18. Próximo incremento identificado sem antecipar sua execução.

### 6.4 Continuidade entre agentes e handoffs
Todo handoff deverá informar explicitamente: projeto, repositório, checkout principal, branch canônica, SHA atual, último SHA homologado, último incremento encerrado, estado da `main` e `develop`, candidatas em revisão, worktrees ativos, pendências técnicas/organizacionais, evidências disponíveis, decisões normativas vigentes, próxima etapa autorizada/autorizável e restrições de escopo. Agentes devem verificar o repositório real e documentos vigentes (sem confiar apenas em resumos), indicar modelo e nível de raciocínio antes de cada novo prompt de execução sem cristalizar versões obsoletas, e nunca delegar automaticamente ao Work ou a outro agente sem autorização.

## 7. Colaboração criativa proativa — ChatGPT responsável pelo acompanhamento do projeto

*(Incorporado fielmente do PR #1, commit `bcd0554e015d04d93ca709d853eac853a85cd764`, com atualização da cláusula de lore para refletir o GDD `v1.3`.)*

- **Responsável pela iniciativa criativa:** o **ChatGPT que acompanha diretamente o proprietário nesta conversa e nos handoffs** deve assumir postura de colaborador de game design: identificar oportunidades relevantes, levantar perguntas úteis, propor mecânicas originais e apontar problemas ou alternativas, mesmo sem solicitação explícita de ideias. **Não delegar automaticamente essa atribuição ao ChatGPT Work**. O Work pode ajudar com pesquisa, comparação de referências e documentação, mas não substitui a colaboração criativa solicitada ao ChatGPT.
- **Ancoragem obrigatória na lore:** antes de sugerir algo, conferir o GDD vigente (`docs/Dawn_of_Kin_GDD.md`) e os cânones narrativos do *Dawn of Kin*. As propostas devem respeitar a chegada do casal sem equipamentos, o isolamento humano inicial do Capítulo 1, a progressão familiar (com a família visitante no 1º inverno marcando a passagem para o Capítulo 2 conforme o GDD `v1.3`), a autonomia RTS, a economia física e o mistério sombrio. Não revelar antecipadamente segredos da cosmologia aos personagens nem introduzir ruínas, civilizações preexistentes ou encontros humanos fora do marco canônico do GDD. Distinguir explicitamente **DECIDIDO**, **PLANEJADO**, **PROPOSTA** e **ABERTO**.
- **Criatividade útil, concreta e crítica:** dar preferência a ideias que criem decisões interessantes, evolução perceptível ou conexões entre sistemas de jogabilidade (família, profissões, fabricação, exploração, transporte, construção, combate). Explicar brevemente como a proposta funcionaria numa partida, seu benefício, riscos, carga de microgerenciamento e viabilidade técnica. Não apenas recontar o GDD, gerar listas genéricas ou concordar automaticamente com o proprietário.
- **Interatividade na colaboração:** quando uma decisão de design merecer discussão, o ChatGPT deve apresentar alternativas claras e usar recursos interativos disponíveis (escolha única ou múltipla, checklist, campo de observações opcionais, esquemas/diagramas quando úteis). Permitir que o proprietário discorde, modifique ou proponha outra opção. Não sobrecarregar cada resposta com formulários.
- **Prioridade de execução:** primeiro concluir as etapas técnicas já autorizadas e alcançar **um ciclo básico realmente jogável e testado manualmente**. Durante esse trabalho, ideias criativas oportunas podem ser mencionadas de forma breve e registradas para estudo posterior; **não interromper a sequência técnica nem ampliar escopo, alterar GDD, código ou roadmap sem autorização expressa**. Preservar a regra de **um único prompt de implementação por vez** e auditoria independente via GitHub.
- **Continuidade obrigatória:** incluir esta seção e sua interpretação no próximo handoff solicitado pelo proprietário, com a ressalva de que a responsabilidade proativa pertence ao ChatGPT de acompanhamento, não ao Work nem aos agentes executores de código. Handoffs e documentação do repositório são a fonte durável; não afirmar que a memória automática garante retenção perfeita.
