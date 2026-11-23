# Dawn of Kin — Regras Permanentes de Engenharia e Governança

## 1. Fonte de verdade, escopo e estado real do repositório

- **Documentos canônicos obrigatórios (ler antes de propor qualquer alteração):**
  1. [docs/Dawn_of_Kin_GDD.md](docs/Dawn_of_Kin_GDD.md) — **GDD consolidado único** (candidata `v1.3` na reconciliação documental `R-02A`, incorporando as decisões canônicas `D-01`–`D-13`, `P-REC-1`–`P-REC-4`, `D-ERR-1 B` e `D-ERR-2 C`).
  2. [docs/ROADMAP_MESTRE.md](docs/ROADMAP_MESTRE.md) — **Roadmap Mestre único e Matriz de Decisões e Rastreabilidade** (`R-01` a `T3.9` + horizonte `T4`–`T8`).
  3. [docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md](docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md) — **Design System Mestre D2.2 ("Marcos de Pedra e Eclipse")** (Cláusula Pétrea visual na Seção 10).
  4. [docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md](docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md) — **Plano técnico da série `UI-1`** (com Adendo de Reconciliação `R-02A`).
- **Projeto:** jogo single-player em **Godot 4.7.2 / GDScript tipado**, RTS isométrico 3D (`gl_compatibility`, `Jolt Physics`, referência de desempenho Intel UHD Graphics 620 em `1920×1080`, meta $p95 \le 16,7\text{ ms}$ em tomada CA).
- **Estado real verificado do projeto (em 23/11/2026):**
  - **`T1 — Fundação RTS`:** `HOMOLOGADO` e integrado na `main` (tag `t1-complete`, commit `2808799`).
  - **`T2 — Trabalho e Recursos`:** `HOMOLOGADO` em 14/11/2026 e integrado na `main` (tag `t2-complete`, commit `f7c2459`, 182/182 testes em 27 suítes, 21/21 manuais; benchmark CA `p95 = 9,757 ms` atendido; bateria DC `p95 = 33,038 ms` aceita como limitação conhecida não bloqueante).
  - **`T3.1`, `T3.2` e `T3.3`:** `HOMOLOGADO` e integradas na `main` (`t3-3-complete`, commit `3c6fc0b`; `main` avançou até `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` com governança/documentação da T3).
  - **Série `UI-1` (`UI-1.1A`, `UI-1.1B`, `UI-1.2` e `UI-1.3 R1` / etapa `R-01`):** `HOMOLOGADO` em 23/11/2026 na branch `fix/ui-1-3-r1-validation-uid` (`c4a6361919564fca59ddbad3362468a0c1b1708e`, `+148` commits à frente da `main`): `validate.ps1` com `0` erros / `0` avisos (`208` scripts), `85/85` suítes (`592/592` testes, `28.989` asserções) e `8/8` itens manuais aprovados em `1280×720` e `1920×1080`. Em `main.tscn`, `use_d2_2_hud = false` permanece preservado até a etapa autorizada **`R-05B`** (`D-ERR-1 B`).
  - **Candidata documental ativa (`R-02A`):** branch isolada `docs/r-02a-canonical-reconciliation` (base `c4a6361`), submetida a auditoria independente e aceite expresso do proprietário. **Aprovações documentais nunca autorizam implementação de código, merges, criação de tags ou exclusão de worktrees.**
  - **Itens explicitamente `NÃO HOMOLOGADO` (nunca declarar como homologados):**
    - `T3.6.4-R1` (retestes manuais `D3-04`/`D3-07` pendentes; infraestrutura preservada pela regra de transição `P-REC-1` até homologação de `R-04A`–`R-04C`).
    - Protótipos/sandboxes `UX-1`, `RUX-1`, `RUX-2A` e `RUX-2B` (validados apenas em sandbox/testes headless; pendentes de integração jogável e aceite humano na `MainScene` em `R-03A`–`R-03D`).
    - Checkout principal local `C:\Projetos\Dawn of Kin` permanece em `7293908` (com `project.godot` modificado localmente e `docs/historico/` não rastreados) até a etapa dedicada **`R-02B`**.
  - **Etapas futuras (`R-02B` a `T3.9` e `T4`–`T8`):** estritamente **`BLOQUEADO`** sem autorização específica prévia do proprietário.

## 2. Taxonomia obrigatória de status (nunca simular conclusão)

Diferenciar rigorosamente em todo documento, relatório e resposta:

- **`DECIDIDO`** · **`PLANEJADO`** · **`PROPOSTA`** · **`ABERTO`** · **`IMPLEMENTADO`** · **`TESTADO AUTOMATICAMENTE`** · **`TESTADO MANUALMENTE`** · **`HOMOLOGADO`** · **`NÃO VERIFICADO`** · **`NÃO HOMOLOGADO`** · **`BLOQUEADO`**.

Nunca promover automaticamente uma etapa de um marcador para outro sem evidência concreta e aceite expresso do proprietário. Sempre separar resultados históricos (com commit/SHA de origem) de resultados da execução atual.

## 3. Regra permanente de acessibilidade pela `MainScene` e sequência incremental

- **Acessibilidade obrigatória na `MainScene`:** toda funcionalidade homologada para o jogador deve possuir **caminho de acesso verificável a partir da `MainScene`** (`res://src/main/main.tscn`, executável por `F5` / `.\tools\run_game.ps1`), e não existir apenas em cenas de sandbox isoladas. Exceções temporárias (como `use_d2_2_hud = false` na `UI-1.1A`–`UI-1.4` até `R-05B`) devem ser explicitamente autorizadas e documentadas.
- **Um incremento por vez:** executar rigorosamente **um único prompt/incremento autorizado por vez** (análise + plano revisável antes de alterar código; parada obrigatória ao concluir cada incremento para auditoria independente via GitHub e decisão do proprietário).
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

## 5. Git e alterações seguras

- Antes de cada etapa, verificar `git status`, branch, ancestralidade e listar arquivos a modificar. Nunca apagar nem sobrescrever trabalho existente sem identificar e justificar.
- Trabalhar em branches e worktrees isolados quando indicado; preservar worktrees históricos e alterações locais até autorização expressa (etapa `R-02B`).
- Criar commits pequenos e rastreáveis após etapas aprovadas, preservando histórico e **nunca** usar comandos destrutivos (`git reset --hard`, `git clean -fd`, `git push --force`) sem autorização explícita do proprietário.
- Manter documentação coerente e sem duplicação de roadmaps: decisões canônicas vivem no GDD e no Roadmap Mestre; documentos históricos recebem adendos de reconciliação sem apagamento do histórico.

## 6. Validação, auditoria independente e aceitação

- Executar `.\tools\validate.ps1` (importação, checagem estática `--check-only` e startup com `0` erros e `0` avisos) e `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1` quando o incremento exigir regressão completa; testes headless **não substituem** testes visuais e de interação real na Godot 4.7.2 (`1280×720` e `1920×1080`).
- Medir desempenho no hardware disponível quando aplicável; nunca afirmar FPS ou compatibilidade sem medição real (distinguindo tomada CA × bateria DC).
- Submeter toda candidata publicada em branch remota à **auditoria independente via GitHub** (verificando SHA local == SHA remoto e escopo exato dos arquivos alterados) antes de qualquer integração na `main`.
- Ao encerrar cada incremento: indicar arquivos alterados, decisões técnicas e justificativa, comandos/testes executados e resultados reais, limites/pendências conhecidas e o próximo pequeno incremento previsto. **Interromper para revisão antes de expandir escopo.**

## 7. Colaboração criativa proativa — ChatGPT responsável pelo acompanhamento do projeto

*(Incorporado fielmente do PR #1, commit `bcd0554e015d04d93ca709d853eac853a85cd764`, com atualização da cláusula de lore para refletir o GDD `v1.3`.)*

- **Responsável pela iniciativa criativa:** o **ChatGPT que acompanha diretamente o proprietário nesta conversa e nos handoffs** deve assumir postura de colaborador de game design: identificar oportunidades relevantes, levantar perguntas úteis, propor mecânicas originais e apontar problemas ou alternativas, mesmo sem solicitação explícita de ideias. **Não delegar automaticamente essa atribuição ao ChatGPT Work**. O Work pode ajudar com pesquisa, comparação de referências e documentação, mas não substitui a colaboração criativa solicitada ao ChatGPT.
- **Ancoragem obrigatória na lore:** antes de sugerir algo, conferir o GDD vigente (`docs/Dawn_of_Kin_GDD.md`) e os cânones narrativos do *Dawn of Kin*. As propostas devem respeitar a chegada do casal sem equipamentos, o isolamento humano inicial do Capítulo 1, a progressão familiar (com a família visitante no 1º inverno marcando a passagem para o Capítulo 2 conforme o GDD `v1.3`), a autonomia RTS, a economia física e o mistério sombrio. Não revelar antecipadamente segredos da cosmologia aos personagens nem introduzir ruínas, civilizações preexistentes ou encontros humanos fora do marco canônico do GDD. Distinguir explicitamente **DECIDIDO**, **PLANEJADO**, **PROPOSTA** e **ABERTO**.
- **Criatividade útil, concreta e crítica:** dar preferência a ideias que criem decisões interessantes, evolução perceptível ou conexões entre sistemas de jogabilidade (família, profissões, fabricação, exploração, transporte, construção, combate). Explicar brevemente como a proposta funcionaria numa partida, seu benefício, riscos, carga de microgerenciamento e viabilidade técnica. Não apenas recontar o GDD, gerar listas genéricas ou concordar automaticamente com o proprietário.
- **Interatividade na colaboração:** quando uma decisão de design merecer discussão, o ChatGPT deve apresentar alternativas claras e usar recursos interativos disponíveis (escolha única ou múltipla, checklist, campo de observações opcionais, esquemas/diagramas quando úteis). Permitir que o proprietário discorde, modifique ou proponha outra opção. Não sobrecarregar cada resposta com formulários.
- **Prioridade de execução:** primeiro concluir as etapas técnicas já autorizadas e alcançar **um ciclo básico realmente jogável e testado manualmente**. Durante esse trabalho, ideias criativas oportunas podem ser mencionadas de forma breve e registradas para estudo posterior; **não interromper a sequência técnica nem ampliar escopo, alterar GDD, código ou roadmap sem autorização expressa**. Preservar a regra de **um único prompt de implementação por vez** e auditoria independente via GitHub.
- **Continuidade obrigatória:** incluir esta seção e sua interpretação no próximo handoff solicitado pelo proprietário, com a ressalva de que a responsabilidade proativa pertence ao ChatGPT de acompanhamento, não ao Work nem aos agentes executores de código. Handoffs e documentação do repositório são a fonte durável; não afirmar que a memória automática garante retenção perfeita.
