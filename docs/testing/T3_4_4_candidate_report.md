# Dawn of Kin — T3.4.4 — Relatório técnico e registro de homologação

**Status:** **T3.4.4 FORMALMENTE HOMOLOGADA PELO PROPRIETÁRIO EM 17/11/2026** no commit `7e3f961359558839c2cb5ef107a62ab691eb8557`. Autorizado exclusivamente o registro documental na mesma branch candidata. **SEM MERGE NA MAIN, SEM TAG, SEM INÍCIO DA T3.4.5.**

**Data:** 17/11/2026. **Branch:** `feat/t3-4-4-building-completion`.

**Worktree:** `C:/Projetos/Dawn_of_Kin_wt_t3_4_4`.

**Commits da branch candidata:**
- Implementação inicial T3.4.4: `5d0207201dfc530b698bc736ad017542613623c9` (`feat(t3.4.4)`).
- Testes e regressões iniciais: `35c45e5334d7264aff5a059764750a67d0f0526c` (`test(t3.4.4)`).
- Relatório inicial da candidata e evidência gráfica: `3d3c258960dce56ea6962131dbb17bd9ac83f096` (`docs(t3.4.4)`).
- Teste complementar R2-03 (contexto antigo de hover): `a6120266b4e10ea12af3b11ea65b294866856f78` (`test(t3.4.4)`).
- **Commit técnico homologado pelo proprietário:** `7e3f961359558839c2cb5ef107a62ab691eb8557` (`docs(t3.4.4)`). *(O commit subsequente nesta branch é estritamente documental e não altera nem substitui o objeto técnico homologado).*

## Registro formal de homologação — 17/11/2026

**Decisão expressa do proprietário (sem observações):**

> Homologo formalmente a T3.4.4 do Dawn of Kin no commit 7e3f961359558839c2cb5ef107a62ab691eb8557. Autorizo exclusivamente o registro documental da homologação pelo Antigravity ou Codex na mesma branch candidata. Não autorizo merge na main, criação de tag ou início da T3.4.5. Observações: Nenhuma.

- **Objeto técnico homologado:** implementação técnica e testes da T3.4.4 no SHA exato `7e3f961359558839c2cb5ef107a62ab691eb8557`, compreendendo a conclusão transacional de edifícios (`BuildingInstance`, `ConstructionManager.complete_site_transaction`), substituição atômica canteiro/edifício, rollback defensivo com cooldown de retentativa (`MAX_COMPLETION_RETRIES = 3`, `RETRY_COOLDOWN_SEC = 1.0`), proteção contra sobreposição em `PlacementValidator` via `ValidationContext.completed_buildings`, e invalidação de revisão em `WorldNavigation.notify_building_geometry_changed`.
- **Fundamento técnico e auditoria independente:** homologação formal concedida pelo proprietário após conclusão favorável da auditoria estática independente do ChatGPT, que verificou o diff, código de produção, testes automatizados e relatório técnico em confronto com a arquitetura normativa `T3.4-R2.3`, sem apontar defeitos bloqueantes no escopo da T3.4.4.
- **Comprovação do contrato R2-03 (contexto antigo no hover):** plenamente comprovada pelo novo teste `test_09_t34_aut_07_stale_hover_context_after_site_removal_before_physics_sync` (incorporado no commit `a612026`), que demonstra que mesmo com um `ValidationContext` capturado antes da conclusão da obra (contendo o canteiro e nenhum edifício) e antes da sincronização física, a chamada a `validate_hover()` rejeita a sobreposição com `REASON_OBSTACLE_OVERLAP` por força da verificação unificada do footprint lógico dos edifícios concluídos da região.
- **Resultados finais de execução (Codex):**
  - Suíte específica T3.4.4 (`test_t3_4_4_building_completion.gd`): **9/9 testes aprovados** (1.355 asserções).
  - Suíte completa segmentada (`.\tools\run_tests.ps1 -Segmented`): **38/38 suítes, 269/269 testes aprovados, 10.506 asserções**, zero falhas, zero erros de suíte e zero avisos/erros no log em 8 lotes disjuntos.
  - Validação de integridade (`.\tools\validate.ps1`): importação headless, `--check-only` em **116 scripts** e boot headless da cena principal aprovados com **zero erros e zero avisos** (exit code 0).
- **Distinção metodológica estrita:** os testes foram **executados pelo Codex no ambiente Godot local** e a conformidade do diff/código foi **auditada estaticamente pelo ChatGPT** (sem execução independente de Godot pelo ChatGPT). Testes manuais/visuais de interação com o mouse pelo jogador não foram realizados nesta etapa.
- **Limitação deliberada e fronteira T3.4.5:** a malha de navegação ativa (NavMesh) ainda não incorpora o edifício concluído; embora o colisor físico permanente impeça a passagem de unidades, o roteamento global pode continuar calculando caminhos sobre a malha anterior. A incorporação do edifício à navegação via rebake assíncrono N1, barreiras de colisão transitórias (`_pending_building_blockers`) e benchmark de desempenho (`T34-PERF-01`) pertencem estritamente à etapa subsequente `T3.4.5`.
- **Preservação estrita do SHA técnico homologado:** o registro documental adicionado não altera, substitui nem invalida o commit técnico homologado `7e3f961359558839c2cb5ef107a62ab691eb8557`. Nenhum merge para a `main`, criação de tag ou avanço para a `T3.4.5` está autorizado.

## Base e governança

- Base obrigatória conferida após `git fetch origin`: `9e5a782f047b9756776d8ccd281145b2dd4d879f`.
- Commit técnico T3.4.3 integrado: `532a5419f3604edfd6b4b2b74987b7e859b70a3c`, confirmado como ancestral da base.
- Arquitetura normativa R2.3: `da20244f4320f0ae5e03236553f5c0e3f57f3a6f`; aprovação documental `39cdaac674d78111efd300b70b8f2f3909e347f9`.
- Leitura de `AGENTS.md`, GDD v1.2, contratos R2-02/R2-03, plano incremental §7, T34-AUT-05/07 e relatórios T3.4.1–T3.4.3. A autorização específica posterior do proprietário libera exclusivamente esta candidata T3.4.4.
- Base, worktrees T3.4.3/arquitetura e novo ambiente estavam limpos. O workspace antigo `C:/Projetos/Dawn of Kin` foi expressamente excluído somente da condição de limpeza pelo proprietário; nenhum arquivo, configuração ou trabalho preexistente desse workspace foi alterado.
- Godot executada: `4.7.2.stable.official.ed1daf0bf`; configuração `gl_compatibility` e Jolt. Hardware disponível: UHD 620, GTX 1060 e aproximadamente 16 GB RAM.

## Arquivos funcionais e decisões aplicadas

1. [`building_instance.gd`](../../src/buildings/building_instance.gd), novo: `Node3D` com identidade estável do canteiro (`building_id = site_id`), definição, região, footprint, cópia dos materiais incorporados e grupo `completed_buildings`. Implementa `configure`, `is_valid`, `get_footprint_rect`, `get_footprint_aabb` e `resolve_from_collider`.
2. [`construction_site.gd`](../../src/buildings/construction_site.gd): validação de prontidão para conclusão integral; contador, cooldown e diagnóstico; sinais `site_completed`/`site_completion_failed`; registro de falha e encerramento seguro das ordens. A notificação de saída de um canteiro concluído invalida o objeto para observadores existentes, permitindo fechar o inspetor temporário sem alterar UI.
3. [`construction_manager.gd`](../../src/buildings/construction_manager.gd): raiz regional `CompletedBuildings`, registro de edifícios, verificação unificada de footprint, agendamento deduplicado, `building_creator_override`, transação de conclusão e recuperação explícita. A raiz é criada como irmã da raiz dos canteiros, com `region_id` e `World3D` correspondentes; não foi necessário alterar `main.gd`.
4. [`placement_validator.gd`](../../src/buildings/placement_validator.gd): `ValidationContext.completed_buildings`, filtro por mundo/região e atualização dinâmica; rejeição por footprint lógico além da física; caixas de edifícios nas sessões candidatas isoladas já existentes; atualização do contexto antes de preparar confirmações.
5. [`world_navigation.gd`](../../src/navigation/world_navigation.gd): somente `notify_building_geometry_changed`, que invalida o cache e garante incremento de revisão mesmo sem cache anterior. Não modifica a malha ativa, não inicia rebake e não registra fontes N1.

O colisor permanente é `StaticBody3D` com `MASK_BUILDINGS | MASK_OBSTACLES`, `BoxShape3D` de largura/profundidade completas e altura `definition.visual_height`. A validação também confere hierarquia, posição da forma, transformações locais e dimensões. Paredes e cobertura são geometria exterior provisória, distinguível do alicerce; não representam arte final aprovada.

## Transação, reentrância e preservação econômica

1. O sinal `state_changed` ao entrar em `COMPLETING` agenda uma chamada diferida deduplicada por ID. Não há remoção do canteiro dentro de `contribute_work`.
2. `complete_site_transaction(site, building_instance = null)` exige pertencimento ao gerenciador/região, prontidão integral, ausência de contribuição em andamento e ausência de outra conclusão reentrante. Aceita a instância previamente configurada prevista em R2-03; o caminho automático usa o creator do gerenciador quando o segundo argumento está ausente.
3. A instância é criada, configurada, inserida na raiz regional e validada, preservando a transformação global e os materiais incorporados. Em falha, qualquer nó parcial retornado é removido/liberado; canteiro, progresso, consumo e footprint permanecem.
4. `_completed_buildings` recebe a instância antes de `site_completed`. Nesse sinal, ambos os registros de ocupação ainda existem. As ordens ativas são encerradas com segurança e os vínculos de inventário/trânsito são removidos.
5. Somente depois o canteiro sai de `_sites`, é removido da árvore e recebe `queue_free`. A revisão de navegação é invalidada na mesma transação, sem bake.

Não se repete `contribute_work`, não se debita estoque na conclusão e não se cria estoque para representar material já incorporado. O edifício conserva uma cópia `{wood: 12, stone: 6}` do abrigo. O registro de custos por identidade evita reutilização de IDs concluídos no mesmo gerenciador.

Estados: `COMPLETING → COMPLETED` no sucesso; em falha, `COMPLETING → COMPLETION_FAILED_RETRYABLE`; ao esgotar três tentativas, `COMPLETION_BLOCKED_ERROR`.

- `MAX_COMPLETION_RETRIES = 3` inclui a tentativa inicial.
- `RETRY_COOLDOWN_SEC = 1.0`: `Timer` one-shot pertencente ao gerenciador, sem loop de tentativa por quadro. Diagnóstico expõe contador, motivo e tempo restante do timer.
- Durante cooldown, `contribute_work` retorna `completion_pending_retry` sem mutação econômica.
- Após três falhas, não existe timer automático novo. `retry_failed_site_completion` aceita somente um canteiro bloqueado, válido e pertencente ao gerenciador; zera o contador e agenda nova conclusão. Chamadas repetidas/reentrantes são recusadas.
- Ordens que já encerraram em `COMPLETING`, conforme T3.4.3, não são necessárias à retentativa; o gerenciador conclui autonomamente.

## Testes executados

### Correção de auditoria R2-03 — contexto antigo no hover

A auditoria observou que `validate_hover()` não chama `refresh_dynamic_state()` diretamente. A inspeção do fluxo mostrou que ele chama `_validate_spatial_base()`, que atualiza o contexto antes das consultas espaciais e da verificação de `completed_buildings`. `PlacementController` também cria um contexto para cada avaliação de hover e limita atualizações periódicas. Logo, para o caso de ocupação recém-criada, já existe proteção no caminho de produção: não foi necessário acrescentar outra atualização nem uma consulta global adicional a cada movimento do mouse.

O novo `test_09_t34_aut_07_stale_hover_context_after_site_removal_before_physics_sync` guarda um contexto que contém o canteiro e nenhum edifício, conclui a obra pela transação real e, sem aguardar outro frame de física, confirma que o site saiu da árvore e do registro do gerenciador. A atualização do contexto exclui o site e inclui o edifício da mesma região e mundo. O teste desativa temporariamente as camadas dos dois corpos no fixture e exige que `validate_hover()` com o **contexto antigo** retorne `REASON_OBSTACLE_OVERLAP` com o texto específico do footprint lógico do edifício. A camada do edifício é restaurada; após a sincronização física, o mesmo contexto continua rejeitando a posição. O teste confirma que outra região no mesmo mundo não inclui o edifício nem recebe `REASON_OBSTACLE_OVERLAP` por esse footprint; o teste 06 existente cobre mundos independentes.

Na investigação do isolamento, uma expectativa inicial exigia hover válido na outra região, mas o fixture compartilha a NavMesh da primeira região e retornou `invalid_terrain`. A expectativa foi corrigida para verificar a propriedade pertinente — não herdar a ocupação — sem declarar que a NavMesh compartilhada representa uma região navegável independente. O motivo observado e a limitação do fixture foram preservados aqui; nenhuma guarda foi removida.

Resultados desta correção:

- Suíte específica T3.4.4: **9/9 testes, 1.355 asserções**, sem falhas ou erros de suíte. O novo teste passou com 155 asserções, incluindo os 120 passos de montagem.
- Suíte completa `./tools/run_tests.ps1 -Segmented`: **38/38 suítes, 269/269 testes, 10.506 asserções**, zero falhas e erros de suíte; `Discovered=38`, `ExecutedUnique=38`, `Duplicates=0`, `Missing=0`. O log não contém linhas `ERROR`, `SCRIPT ERROR` ou `WARNING`.
- Regressões T3.2: posicionamento unitário **7/7** (134 asserções) e integrado **5/5** (111). Regressões T3.3: canteiro **7/7** (164), UX unitário **2/2** (9), logística **11/11** (214) e UX integrado **3/3** (57).
- `./tools/validate.ps1`: importação, checagem de **116 scripts** e inicialização headless da cena principal aprovadas, com **zero erros e zero avisos**.
- `git diff --check`: sem erros de whitespace.

Não houve mudança em scripts de produção, GDD ou arquitetura. As demais tabelas desta seção preservam os resultados históricos da candidata anterior.

| Comando/verificação | Resultado |
|---|---|
| `./tools/run_tests.ps1 -Filter test_t3_4_4` | 8/8 testes, 1.200 asserções, zero falhas/erros de suíte |
| `./tools/run_tests.ps1 -Segmented` — execução final | 38/38 suítes, 268/268 testes, 10.350 asserções, zero falhas/erros de suíte/diagnósticos Godot; 8 lotes aprovados |
| Cobertura segmentada final | `Discovered=38`, `ExecutedUnique=38`, `Duplicates=0`, `Missing=0`; aproximadamente 401,2 s de tempo total |
| Regressão isolada T3.4.3 | 7/7 testes, 426 asserções, zero falhas/erros de suíte |
| Regressão isolada T3.4.2 | 11/11 testes, 829 asserções, zero falhas/erros de suíte |
| `./tools/validate.ps1` | Importação, 116 scripts em `--check-only` e startup headless da cena principal aprovados; zero erros/avisos |
| Checagem estática após últimos ajustes | `--check-only` repetido para gerenciador, validador e suíte T3.4.4 |
| `git diff --check` | Sem erros de whitespace |

Comparação com a base informada: 113 → 116 scripts, 37 → 38 suítes e 260 → 268 testes. As asserções finais foram 10.350, contra 9.111 na última integração informada; a nova suíte acrescenta 1.200, e o restante inclui as verificações adaptadas de conclusão e contagens variáveis por quadros de física. Na execução final, `test_t2_natural_source_states` integrado registrou 102 asserções, e `test_t2_worker_cycle`, 2.660. Nenhum teste foi desabilitado ou removido.

Regressões na execução completa: T3.4.1 8/8 (299 asserções); T3.4.2 11/11 (829); T3.4.3 7/7 (426); reservas T3.1 17/17 (432); posicionamento T3.2 unitário 7/7 (134) e integrado 5/5 (111); canteiro T3.3 7/7 (164), UX unitário 2/2 (9), logística 11/11 (214), UX integrado 3/3 (57).

[`test_t3_4_4_building_completion.gd`](../../tests/integration/test_t3_4_4_building_completion.gd) usa cenas e física reais isoladas em `SubViewport`, estoque em memória e entregas por mochila/reivindicação/buffer. A montagem atravessa 120 frames de contribuição válida de 0,25 s. A subclasse de ordem do fixture apenas isola locomoção; os fluxos completos de ordens continuam cobertos pelas regressões T3.4.3.

| Caso | Evidência exigida e conferida |
|---|---|
| T34-AUT-05 A | Instância aceita enquanto desconectada, invalidada após inserção na árvore; nó parcial liberado, canteiro e contabilidade intactos, nenhuma tentativa antes de 0,5 s; retry automático posterior cria exatamente um edifício. |
| T34-AUT-05 B | Três retornos nulos, exatamente três tentativas, um sinal de bloqueio; nenhuma tentativa por mais 1,1 s; recuperação explícita cria um edifício sem novo consumo. |
| T34-AUT-05 C | Reentrada pelo creator e pelo sinal de conclusão recusada; solicitações duplicadas deduplicadas; um sinal, um registro e nenhuma janela sem footprint. |
| T34-AUT-07 | No próprio sinal de conclusão: edifício e canteiro registrados, `building_overlap` antes de reserva e rejeição de hover/confirm/confirm_async. Depois da sincronização, raycast encontra o colisor permanente. |
| T34-AUT-07 concorrente | Bake candidato real com entrega de callback controladamente retardada no teste; outro canteiro nasce e conclui na área antes do callback. Resultado anterior aborta com `navigation_stale`, sem confirmação válida. |
| Isolamento | Registros filtrados entre dois mundos 3D independentes e entre regiões distintas no mesmo mundo. |
| Raiz inválida | Região da raiz alterada no fixture: conclusão recusada com diagnóstico, preservando canteiro e materiais; após correção da raiz, retry conclui normalmente. |
| Factory inválida | Creator devolve o próprio canteiro existente: rejeição sem removê-lo/liberá-lo; somente nós temporários cuja propriedade foi transferida ao gerenciador podem ser descartados no rollback. |

As regressões T3.4.3 e o caso terminal T3.3 foram adaptados para observar `site_completed`, guardar o snapshot econômico antes da liberação e verificar o edifício por ID. As verificações intermediárias de ordens, starvation, zero polling, carga excedente, D9 e conservação foram preservadas. A suíte unitária T3.4.2 altera somente o motivo de rejeição durante cooldown, conforme R2-02. Canteiros unitários sem gerenciador continuam terminando em `COMPLETING`.

## Verificação gráfica

[`t3_4_4_completion_preview.gd`](../../tests/visual/t3_4_4_completion_preview.gd) executa a cena principal com janela real, abastece o estoque e envia dois trabalhadores por `CommandController` até a conclusão. Aceleração controlada 3× e 180 ticks/s, sem benchmark. Exporta o viewport para PNG após renderização.

A execução gráfica passou na **Intel UHD Graphics 620**, OpenGL 3.3 / Compatibility, em **1280×720**, sem erros ou avisos no log. Resultado exportado: `building_id = site_default_0001`, `materials = {wood: 12, stone: 6}`, `remaining_sites = 0`, `save_error = 0`.

Captura real inspecionada: [abrigo concluído](evidence/t3_4_4/completed_shelter_1280x720.png). A imagem mostra paredes/cobertura, dois trabalhadores e o acampamento; o painel do canteiro removido está fechado. Essa execução automatizada gráfica não constitui teste manual de mouse, aceite artístico do proprietário ou comprovação de desempenho.

## Problemas diagnosticados durante o trabalho

- A primeira chamada de testes ocorreu antes da importação do novo worktree e não encontrou a classe global `TestCase`; a importação foi executada antes das verificações subsequentes.
- O primeiro fixture chamou uma API de transferência inexistente no backend em memória. Foi corrigido para saque reservado real, crédito limitado à capacidade da mochila, registro de trânsito e entrega. Não foi adicionada API de produção para acomodar o teste.
- As regressões antigas acessavam o canteiro após sua nova liberação legítima. Foram migradas para evidências capturadas no sinal e consulta do edifício definitivo, preservando a contabilidade.
- A inspeção gráfica detectou retenção do último snapshot no painel provisório. A notificação de invalidação na saída do canteiro resolve o ciclo de vida sem introduzir interface T3.5.
- A primeira execução segmentada, realizada durante os últimos ajustes, terminou em 266/267 testes: o caso adicional de raiz regional inválida ainda observou o caminho anterior, concluindo em vez de rejeitar. Essa rodada não é usada como evidência de aprovação. Após consolidar a guarda regional, o teste específico passou, e a suíte segmentada foi executada novamente.
- A revisão defensiva identificou que uma factory poderia devolver um nó já existente. O descarte de rollback foi limitado a nós novos/desconectados cuja propriedade pertence à transação; teste específico confirma a preservação do canteiro retornado indevidamente.

## Limitações deliberadas e fronteira T3.4.5

- Sem `register_additional_source_root`, rebake N1, coalescência, blockers transitórios, fallback degradado ou benchmark. A malha ativa ainda não incorpora o edifício concluído: o colisor impede passagem física, mas o roteamento pode continuar visando a malha antiga. Essa integração pertence à T3.4.5 e não é anunciada como pronta.
- Sem UI definitiva, reembolso, armazenamento protegido, persistência ou alterações de regras D2/D9/DEC-11A/11B/18/19.
- GDD, arquitetura e `AGENTS.md` preservados. Sem alteração intencional das branches existentes ou tags oficiais. Somente a nova branch candidata é publicada.

Conferência remota anterior à publicação: `origin/main` permanece em `9e5a782f047b9756776d8ccd281145b2dd4d879f`; tags anotadas preservadas: `t1-complete` (`3dcbba9…` → `2808799…`), `t2-complete` (`049ba9c…` → `f7c2459…`) e `t3-3-complete` (`c7947c9…` → `3c6fc0b…`). Os worktrees de `main` e T3.4.3 seguem limpos. Nenhum merge ou tag foi criado.

**T3.4.4 FORMALMENTE HOMOLOGADA NO COMMIT `7e3f9613`. SEM MERGE NA MAIN, SEM TAG. T3.4.5 NÃO AUTORIZADA.**
