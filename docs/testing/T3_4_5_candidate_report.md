# T3.4.5 — Relatório da implementação candidata

## Correção de auditoria — resultado de rota parcial após rebake

**Aceite e integração autorizados em 17/11/2026; veja o [registro de encerramento](T3_4_5_closeout_ACCEPTANCE.md).** Base da correção: `6795fdfe12845720629c208a7e52dfe3d3fa46d0`. Commit técnico: `737482750675b7d580e10225571a5abd787843e4`. O commit documental é identificável por `git log -1 --format=%H -- docs/testing/T3_4_5_candidate_report.md`.

O recálculo de uma rota originalmente alcançável podia substituir o alvo de movimento por um ponto parcial, enquanto `MoveOrder` ainda considerava a rota completa; ao chegar ao ponto parcial, a ordem reportava sucesso indevido. `UnitMovement` agora registra que um recálculo retornou `PARTIAL_UNREACHABLE` e seu motivo, zerando essa informação no início de cada movimento. Na chegada, `MoveOrder` consulta o resultado, atualiza o destino resolvido e encerra com `FAILED / unreachable`. O destino solicitado da ordem permanece disponível; uma ordem já parcial desde o início conserva seu comportamento anterior. A informação de parcialidade é preservada em recálculos subsequentes para o alvo parcial, evitando que um novo caminho `OK` até esse alvo apague a falha original. Não há dependência de `UnitMovement` para `MoveOrder`.

O novo teste `test_09_repath_to_partial_target_fails_after_real_rebake` inicia uma ordem com caminho `OK`, conclui o abrigo com materiais reais, verifica espera pelo blocker, libera o callback do bake e aguarda sincronização. A consulta real retorna `PARTIAL_UNREACHABLE` com caminho não vazio; a unidade chega ao ponto parcial sem atravessar a footprint e a ordem encerra com `FAILED / unreachable`. O teste também confere o destino solicitado e os materiais incorporados. Os testes existentes 02 e 03 da T3.4.5 cobrem, respectivamente, retomada bem-sucedida para rota ainda alcançável e falha explícita em modo degradado. `test_04_closed_enclosure_unreachable_resolves_exterior_and_fails` da T1 cobre uma ordem parcialmente inacessível desde o início até a chegada ao ponto parcial.

Resultados desta correção:

- `./tools/run_tests.ps1 -Filter test_t3_4_5`: **9/9 testes, 2.305 asserções**, zero falhas e erros de suíte.
- `./tools/validate.ps1`: importação, **118 scripts** e inicialização headless aprovados, zero erros e avisos.
- `./tools/run_tests.ps1 -Segmented`: **39/39 suítes, 278/278 testes, 12.821 asserções**, zero falhas ou erros de suíte; `Discovered=39`, `ExecutedUnique=39`, `Duplicates=0`, `Missing=0`. Inclui regressões T1 de movimento e ordens, T2 de coleta/transporte e T3 de construção/logística.
- `git diff --check`: aprovado.

O benchmark T34-PERF-01 não foi repetido: a nova atribuição ocorre exclusivamente quando há recálculo, e a consulta do resultado ocorre somente no evento de chegada, sem acrescentar trabalho ao processamento de movimento por quadro. A medição Intel UHD 620 em CA de **13,505 ms p95**, descrita abaixo, é histórica da candidata anterior e não uma nova medição desta correção.

**Status histórico à publicação da correção:** candidata, sem homologação, merge ou tag. Data: 17/11/2026.

## Base, escopo e ambiente

- Base obrigatória conferida após `git fetch origin`: `85bbe3ff2edc74d45f2083956fd0932e4ec35919` em `origin/main`.
- Branch exclusiva: `feat/t3-4-5-navigation-bake`.
- Worktree novo e inicialmente limpo: `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`.
- Arquitetura normativa: [T3.4-ARCHITECTURE-R2.3, commit da aprovação](https://github.com/Julian0s/Dawn-of-Kin/blob/da20244f4320f0ae5e03236553f5c0e3f57f3a6f/docs/architecture/T3_4_implementation_plan_PROPOSAL.md), branch documental `planning/t3-4-architecture-r2`, HEAD `39cdaac674d78111efd300b70b8f2f3909e347f9`. Documento lido diretamente pelo Git, pois não está na árvore desta main.
- GDD v1.2, `AGENTS.md`, código e [relatório T3.4.4](T3_4_4_candidate_report.md) confrontados com os contratos de navegação e construção. Autorizações expressas posteriores liberam somente este incremento; avisos históricos não foram tratados como homologação automática nem como revogação dessa autorização.
- Godot `4.7.2.stable.official.ed1daf0bf`, GDScript, Compatibility / OpenGL3, Jolt. Windows com Intel UHD Graphics 620 e GTX 1060 instaladas; o benchmark efetivamente usou a Intel, conforme log da engine.

## Arquitetura aplicada

### Fontes regionais e cache

`WorldNavigation` registra e remove raízes adicionais por `register_additional_source_root()` / `unregister_additional_source_root()`. As raízes e seus edifícios precisam pertencer à mesma região e `World3D`. O terreno estático e `_append_sloped_terrain_side_curbs()` continuam separados dos colisores dos edifícios.

`ConstructionManager.configure()` registra sua raiz `CompletedBuildings`, irmã de `ConstructionSites`, diretamente no `WorldNavigation` recebido. O gerenciador também desconecta sinais e remove esse registro ao sair da árvore. Essa integração fica no proprietário da raiz em vez de duplicar a chamada em `MainScene`; não foi necessário alterar `main.gd` nem pressupor que edifícios estão dentro do `TestMap`.

A preparação candidata reaproveita os vértices/índices estáticos e acrescenta as caixas dos colisores permanentes regionais. As caixas já fornecidas pelo `PlacementValidator` são reconhecidas por posição e dimensões, evitando duplicação. Não houve alteração no terreno, nas rampas ou nos curbs. `notify_building_geometry_changed()` incrementa a revisão imediatamente e preserva o cache estático.

### Conclusão e rebake ativo

Na transação de conclusão: registrar o edifício definitivo → registrar sincronicamente seu blocker expandido em 0,50 m e incrementar revisão → emitir conclusão e encerrar o canteiro → solicitar rebake ativo. Assim, callbacks externos já encontram a proteção antes de emitir ordens.

`request_async_active_rebake()` usa um `AsyncBakeToken` dedicado, separado dos tokens das sessões candidatas T3.2. O bake é executado por `NavigationServer3D.bake_from_source_geometry_data_async()`, mantendo a última navegação válida e a prontidão global durante o processamento. Novos pedidos cancelam logicamente o token anterior; o callback valida identidade do token, cancelamento e revisão antes de aplicar a malha.

Após aplicar, a liberação aguarda iterações mínimas do mapa e da região e uma consulta navegável válida. Só então são removidos os blockers cobertos pela revisão aplicada e emitido `navigation_ready`. O método síncrono `request_rebake()` continua disponível para inicialização e regressões. A utilização da API segue a [documentação do NavigationServer3D](https://docs.godotengine.org/en/stable/classes/class_navigationserver3d.html); os resultados aqui foram medidos na versão instalada.

### Segurança de ordens e movimentação

- `get_pending_route_reason()`, `is_route_blocked_by_pending_building()` e `does_path_intersect_pending_blockers()` filtram segmentos/polilinhas. Sem blockers, a checagem termina em `is_empty()`.
- `find_path()` devolve `PARTIAL_UNREACHABLE / pending_building_blocker` para destino ocupado; `NOT_READY / pending_building_nav_sync` para passagem temporariamente bloqueada; `PARTIAL_UNREACHABLE / navigation_rebake_degraded` para proteção permanente. Caminhos bloqueados não oferecem um fallback parcial inseguro.
- `CommandController` verifica destino solicitado, origens, destinos da formação e rotas, antes de emitir qualquer ordem do grupo. O fallback geométrico do `GroupMovePlanner` não supera essa guarda. Nenhuma mudança no planner foi necessária.
- `UnitMovement` verifica também a polilinha antiga do `NavigationAgent3D` e o deslocamento previsto. Ao receber o blocker, zera velocidade horizontal e espera com `_awaiting_pending_nav_sync`, sem acumular tempo de estagnação. Após `navigation_ready`, faz `_perform_controlled_repath()` e retoma pelo caminho atualizado.
- `ConstructOrder` pode aguardar sinais de navegação quando a escolha de slots é impedida temporariamente; não repete planejamento a cada frame enquanto espera. `BuildSlotPlanner` foi alterado somente para propagar esse motivo, evitando confundir uma espera com inacessibilidade definitiva. Carga, reservas, buffer e progresso não são reiniciados.

### Falha e modo degradado

O watchdog usa `SYNC_TIMEOUT_SEC = 5.0` tanto para retorno do bake quanto para sincronização. Falhas preservam/restauram a última malha válida, incrementam revisão e emitem `navigation_rebake_failed`. O gerenciador agenda uma retentativa com `Timer` de 1 s, sem loop por frame.

São permitidas três tentativas por atualização estável de geometria. Uma nova conclusão inicia uma nova atualização coalescida. Após três falhas, os blockers permanecem com `permanent_degraded = true`, `_rebake_degraded` é ativado, há diagnóstico explícito por `push_error` e sinais `navigation_rebake_degraded` / `navigation_failed`. Ordens afetadas encerram com falha explícita; áreas não afetadas continuam operacionais. Não há tentativa automática adicional após o limite. Uma falha de navegação nunca desfaz o edifício nem devolve ou consome novamente materiais.

## Arquivos envolvidos

Produção: `src/navigation/world_navigation.gd`, `src/buildings/construction_manager.gd`, `src/buildings/build_slot_planner.gd`, `src/rts/command_controller.gd`, `src/units/unit_movement.gd`, `src/units/orders/move_order.gd` e `src/units/orders/construct_order.gd`.

Testes: nova suíte `tests/integration/test_t3_4_5_navigation_bake.gd` e seu UID; adaptações das regressões `test_t3_3_construction_logistics.gd` e `test_t3_4_4_building_completion.gd`. A expectativa histórica de malha inalterada depois da conclusão foi substituída por espera limitada pela aplicação e verificação de caminho externo à footprint. As verificações anteriores de transporte, estoque e conservação foram preservadas.

Benchmark/documentação: `tests/perf/t3_4_assembly_benchmark.gd` e seu UID, [protocolo manual](T3_4_manual_test_protocol.md), este relatório e [dados do benchmark](evidence/t3_4_5/benchmark_uhd620_ac.json).

Não foram alterados GDD, arquitetura, `AGENTS.md`, regras econômicas, recursos, cenas ou configurações do projeto. Não foram implementados sistemas posteriores.

## Verificação automatizada

Suíte segmentada final: **39/39 suítes, 277/277 testes, 12.597 asserções, zero falhas e zero erros de suíte**. Cobertura: `Discovered=39`, `ExecutedUnique=39`, `Duplicates=0`, `Missing=0`; tempo total de parede **413,445 s**. Executor estrito aprovado, sem erros/avisos Godot inesperados. Base anterior: 38 suítes / 269 testes; foram acrescentados 8 testes, sem remoção de cobertura.

| Validação / regressão | Resultado observado |
|---|---|
| `./tools/validate.ps1` | Importação, 118 scripts em `--check-only` e startup headless da cena principal; zero erros e zero avisos |
| `./tools/run_tests.ps1 -Segmented` | 39 suítes, 277 testes, 12.597 asserções; cobertura integral e zero falhas/erros de suíte |
| Nova suíte T3.4.5, incluída na segmentada | 8/8, 2.083 asserções na versão final com construção real no TestMap |
| T3.4.3, também executada isoladamente | 7/7, 426 asserções |
| T3.4.4, também executada isoladamente | 9/9, 1.355 asserções |
| T1: navegação / comandos / movimento físico | 8/8 (292), 5/5 (72), 8/8 (318) |
| Separação RVO | 7/7, 129 asserções |
| T2: ritmo e carga / ciclo de trabalho / economia jogável | 13/13 (452), 8/8 (2.659), 8/8 (351) |
| T3.1: reservas unitárias | 17/17, 432 asserções |
| T3.2: posicionamento unitário / integrado | 7/7 (134), 5/5 (111) |
| T3.3: canteiro unitário / UX unitário / logística / UX integrado | 7/7 (164), 2/2 (9), 11/11 (224), 3/3 (57) |
| T3.4.1 / T3.4.2 | 8/8 (299), 11/11 (829) |

As contagens entre parênteses são asserções. Testes que verificam quadros individuais podem variar a quantidade de asserções entre execuções; os totais acima são os efetivamente emitidos pela execução segmentada final. A suíte específica também passou em execução isolada antes do fortalecimento do fixture de construção no platô; a versão final foi executada dentro da segmentada, sem erros de script.

| Caso executável na nova suíte | Proteção verificada |
|---|---|
| 01 — T34-AUT-06 | Duas montagens reais, conclusões separadas exatamente por um frame de física, cancelamento do token anterior, replay de callback obsoleto, malha final com ambos os prédios, conservação e liberação do token cancelado. A remoção por revisão preserva entradas posteriores. |
| 02 — T34-AUT-12B A–D | Blocker presente no callback externo da conclusão; rejeição antes de substituir ordens; destino interno recusado; comando distante continua; agente com caminho antigo pausa por mais de sua janela de estagnação e retoma por contorno físico após sincronização. |
| 03 — T34-AUT-12B E | Três falhas reais de callback controladas, cooldown, um diagnóstico terminal capturado, proteção permanente, ordem encerrada, nenhuma quarta tentativa automática, edifício/material preservados e rota distante disponível. |
| 04 — Isolamento / candidatos | Caminho normal sem blockers; rejeição de raízes de outro mundo ou região; navegação independente não herda blockers; entradas de geometria candidata sem duplicação de caixas já fornecidas. |
| 05 — T34-AUT-12 | TestMap real, construção de abrigo no platô pela transação do gerenciador, cache estático idêntico, caminho pela rampa e unidade física chegando além do prédio sem entrar na footprint nem cair do platô. |
| 06 — Construção reativa | Escolha de slot com NavMesh antiga provoca espera passiva; sinal de prontidão retoma a ordem sem alterar consumo/progresso; sinal terminal encerra a ordem afetada. |
| 07 — Watchdogs | Expiração determinística dos relógios percorre os ramos reais de timeout de bake e sync; última malha restaurada, blocker retido, ausência de retry por frame e sucesso na terceira tentativa. |
| 08 — Formação | Reachability do planner controladamente recusada para forçar seu fallback real; destino solicitado livre, slot geométrico ocupado; grupo inteiro recusado antes de criar ordens. |

Os bakes dos fixtures são reais. O double controla a entrega do callback ou injeta sua falha; não substitui o cálculo por resultados fictícios. Somente o diagnóstico terminal esperado é capturado no double para não contaminar o executor estrito; erros inesperados continuam reprovando a execução. Os relógios de timeout são ajustados no fixture para testar o ramo sem esperar cinco segundos reais por falha.

## Benchmark T34-PERF-01

Execução gráfica em Intel UHD 620 / OpenGL 3.3 / Compatibility, janela e viewport 1920×1080. Condição CA confirmada por `root/wmi:BatteryStatus` antes e depois (`PowerOnline = true`, `Discharging = false`, nas duas entradas retornadas). Sem `--headless`, `--fixed-fps` ou aceleração do tempo.

O script cria as obras, atribui dois trabalhadores por obra e acompanha montagem, conclusão e rebake até terminar. Registra frametimes integrais, de montagem e da janela de rebake; identifica os sites efetivamente em `BUILDER_ASSEMBLING` para comprovar montagem paralela. Os materiais dos edifícios permanecem `{wood:12, stone:6}` e `{wood:18, stone:10}`.

O preparo mede a thread principal; o tempo assíncrono de bake é tempo de parede até o callback, incluindo atraso de entrega, e a sincronização mede a espera pelo servidor. As chaves `active_*` são as medidas da atualização dinâmica; os campos legados de bake inicial não devem ser somados como tempo dinâmico de preparo.

**Resultado final: CRITÉRIOS ATENDIDOS**, em uma execução gráfica de **33,895 s**, com **4.169 amostras**, **4 trabalhadores**, **2 edifícios concluídos**, **1.491 frames com dois sites distintos efetivamente em `BUILDER_ASSEMBLING`** e **2 rebakes ativos sincronizados**. Zero erros ou avisos inesperados; `scenario_ok`, `target_environment` e `performance_ok` retornaram `true`.

| Janela | Amostras | p95 | Máximo | Frames >100 ms |
|---|---:|---:|---:|---:|
| Execução integral final | 4.169 | **13,505 ms** | 44,561 ms | **0** |
| Montagem | 3.986 | 13,568 ms | 34,440 ms | 0 |
| Rebake / sincronização | 29 | 11,933 ms | 13,841 ms | 0 |

| Rebake | Preparo | Bake assíncrono até callback | Sync |
|---|---:|---:|---:|
| 1 | 0,548 ms | 50,962 ms | 54,718 ms |
| 2 | 0,518 ms | 45,355 ms | 53,635 ms |

A primeira execução já havia atendido a meta, com p95 12,651 ms e zero frames >100 ms. Após refinar o contador para exigir dois sites em fase ativa, o benchmark foi repetido sem outros processos de validação do projeto em execução; os números finais são os da tabela. A versão final do script também passou em `--check-only`, além da execução gráfica. Dados da primeira instrumentação foram preservados no JSON como observação anterior, sem serem confundidos com o contador final.

O critério permanece p95 ≤16,7 ms, zero frames >100 ms e zero diagnósticos inesperados. Nenhuma meta foi alterada. As medidas são deste cenário e não representam garantia para populações futuras, regiões T4 ou conteúdo artístico definitivo.

## Diagnóstico das rodadas exploratórias

As primeiras rodadas não foram aceitas como validação: houve chamadas a métodos inexistentes no fixture (`get_total_amount` / `is_failed`), posição de teste fechando a saída estreita da rampa, comparação de dicionário vazio contra contadores zerados e replay interceptado novamente pelo próprio double. Foram corrigidos os fixtures e executadas novamente as verificações. O teste de formação passou a forçar explicitamente a recusa de reachability para exercitar o fallback, pois o planner normalmente encontra slots seguros por conta própria. Nenhum teste foi desabilitado ou teve uma guarda de segurança removida.

## Pendências de aceitação

O proprietário declarou em 17/11/2026 os oito itens **aprovados, sem observações**. Ver [protocolo](T3_4_manual_test_protocol.md). Essa declaração é distinta das observações parciais do Codex e dos testes automatizados.

O modo degradado conserva a segurança e encerra ordens; não adiciona interface definitiva de recuperação. Persistência em disco, regiões futuras, cancelamento/reembolso, armazenamento protegido e HUD definitivo continuam fora deste incremento. A solicitação de encerramento informa auditoria estática independente favorável do ChatGPT e autoriza o encerramento e a integração.

## Git e preservação

- Implementação funcional: `7785f83c6783ec9819b3d506fcc33aaf2f2ac517`.
- Testes e regressões: `5d57ea335041faa210d588ec3c7508e64cf6b0ca`.
- Benchmark, protocolo e relatório: commit separado imediatamente posterior; seu SHA é retornado por `git log -1 --format=%H -- docs/testing/T3_4_5_candidate_report.md` e informado na entrega final. O arquivo não tenta registrar o próprio hash.
- Destino exclusivo da publicação: `origin/feat/t3-4-5-navigation-bake`; SHA remoto e limpeza final são conferidos após o push, na entrega.
- `origin/main` foi reconferida em `85bbe3ff2edc74d45f2083956fd0932e4ec35919`. A main local do worktree `Dawn_of_Kin_wt_t2_closeout` permaneceu em `9e5a782f047b9756776d8ccd281145b2dd4d879f`, limpa; não foi atualizada por este trabalho.
- O workspace antigo `C:\Projetos\Dawn of Kin` não foi utilizado para implementação e permanece com `M project.godot` e `?? docs/historico/`. Não houve edição, descarte, movimentação, stash ou commit desses arquivos. Os worktrees T3.4.4 e de planejamento foram preservados.
- `git diff --check` e `git diff --cached --check` aprovados na preparação final. Uma linha vazia excedente no fim do novo teste, detectada ao incluir os arquivos antes não rastreados, foi removida antes da publicação; nenhuma lógica foi alterada nessa limpeza.

Tags oficiais conferidas, sem criação ou movimentação:

| Tag | Objeto da tag anotada | Commit apontado |
|---|---|---|
| `t1-complete` | `3dcbba9386cbbee70025b47f4254ef097688a6e1` | `2808799c43b815cf876144807f41f92902bc2983` |
| `t2-complete` | `049ba9c7714c9b90b5515ae6ac30a28830454773` | `f7c24592e3a6d936dbcb63f648c474280695ab9b` |
| `t3-3-complete` | `c7947c9630c102a9d77603cac0bae68678247c95` | `3c6fc0bd36fc3828af5a89662fb23cfb60d37865` |

**Registro histórico:** a candidata aguardava auditoria e aceite quando publicada; a decisão posterior consta do [encerramento](T3_4_5_closeout_ACCEPTANCE.md).

**Condição histórica na publicação:** merge, tag e início da T3.5 não estavam autorizados. A integração foi posteriormente autorizada; tag e T3.5 permanecem fora do escopo deste encerramento.
