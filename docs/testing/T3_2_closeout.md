# Dawn of Kin — Registro de Encerramento da Etapa T3.2

**Etapa:** T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid  
**Data de Aprovação Formal:** 15 de novembro de 2026  
**Decisão do Proprietário:** APROVADA  
**Auditoria Técnica Independente:** ChatGPT (concluída e aprovada em 15/11/2026)  
**Branch de Implementação:** `feature/t3-2-placement`  
**Commit Técnico Final:** `f2110b619640a149b2c3190b05d7f08d3359891d`  
**Base Oficial:** `main`, commit `ceb3f7194a750e66dbf73ebb0b0a7460d51eb87f` (T3.1 integrada)  

---

## 1. Identificação e Objetivo da Etapa

A etapa **T3.2** teve como objetivo implementar o sistema de prévia interativa 3D e validação espacial contínua sem grid para o posicionamento de edifícios, garantindo:
- Projeção e arrasto contínuo da prévia sobre o terreno sem restrições artificiais de grade ("gridless").
- Respeito estrito à zona de armazenamento reservada do acampamento (**D6** — `CampStorageZone`) calculada de forma dinâmica.
- Detecção conservadora de colisões contra recursos naturais (`ResourceSource`), obstáculos físicos, unidades (`Unit`) e pilhas no chão (`GroundResourcePile`).
- Amostragem 3×3 de terreno para controle de inclinação máxima (`10,0°`) e desnível de cota sob a pegada (`0,35 m`).
- Validação topológica por malha navegável candidata isolada (`CandidateSession`), preservando corredores, pontos de acesso ao perímetro da construção e âncoras da região antes da confirmação.
- Ausência total de efeitos colaterais persistentes na economia, reservas de estoque, malha de navegação ativa ou instanciação de edifícios reais (funcionalidades delimitadas para a T3.3+).

---

## 2. Histórico da Implementação e Revisões Técnicas (R1 e R2)

1. **Implementação Inicial T3.2 (`ec4a61f`):**
   - Criação dos recursos `BuildingDefinition` (`shelter_basic` 4×4 m e `storage_depot` 5×4 m).
   - Implementação de `PlacementPreview` (silhueta translúcida discreta, sem sombras projetadas), `PlacementValidator` e `PlacementController`.
   - Roteamento de comandos em `RtsInputController` preservando movimentação de câmera (`WASD`, setas, `MMB`, `Scroll`, `Edge Scroll`) e cancelamento por `Esc` ou `RMB`.
   - Camada `MASK_NAV_STATIC` em `CollisionLayers` isolando recursos naturais do bake da região.

2. **Revisão T3.2-R1 (`cbbddc5`, `643af2e`, `6340099`):**
   - **Desempenho da Confirmação:** identificada pausa na thread principal de ~92–135 ms devido ao re-parse de colisores e bake síncrono. Introduzido cache de geometria estática reaproveitado via `append_arrays()` (evitando bugs internos do Godot 4.7.2 com `set_indices()`/`.duplicate()`) e bake assíncrono em worker thread via `NavigationServer3D.bake_from_source_geometry_data_async()`.
   - **Atualização Dinâmica da Prévia com Mouse Parado:** adicionada reavaliação periódica (`0,12 s`) e conexões reativas a `storage_changed` e `navigation_ready`, atualizando o feedback verde/vermelho mesmo com o cursor imóvel quando unidades ou pilhas entram na pegada.
   - **Isolamento Regional:** reescrita de `ValidationContext.from_region()` para eliminar varreduras globais no `SceneTree`, restringindo a busca à subárvore e ao mundo `World3D` da região ativa.

3. **Revisão T3.2-R2 (`f2110b6`):**
   - **Prevenção de Condição de Corrida (TOCTOU) na Confirmação Assíncrona:** durante o bake em segundo plano, o estado da cena ou da navegação podia mudar. O contrato de `PlacementValidator` foi estendido com `refresh_dynamic_state()` e `_revalidate_confirm_preconditions()`, checando novamente o snapshot atual de unidades, pilhas, obstáculos e a versão de navegação (`_navigation_revision`) antes de autorizar `placement_confirmed`.
   - **Ciclo de Vida Defensivo:** uso de callbacks estáticos com `WeakRef` e cancelamento de tokens pendentes em `WorldNavigation._exit_tree()` para garantir descarte seguro de RIDs caso o controlador seja destruído ou cancelado durante a operação.

---

## 3. Resultado dos Testes Automatizados Reportados

Executados pelo Antigravity no Godot 4.7.2 (`gl_compatibility`) sobre o commit técnico final `f2110b6`:

| Verificação Automatizada | Escopo | Resultado Reportado |
|---|---|---|
| `.\tools\validate.ps1` | Importação headless, verificação de 96 scripts GDScript (`--check-only`) e startup da cena principal | **0 erros, 0 avisos** |
| `.\tools\run_tests.ps1 -Filter "t3_2_placement"` | Suítes específicas da T3.2 (`test_t3_2_placement_validation.gd` e `test_t3_2_placement_flow.gd`) | **12/12 aprovados** (245 asserções) |
| `.\tools\run_tests.ps1 -Segmented` | Suíte de regressão global completa (7 batches: unit + integration-01 a 06) | **211/211 aprovados em 30/30 suítes** (7.147 asserções, 0 falhas, 0 erros) |
| Cenários de Corrida R2 | Cenários determinísticos A (unidade entra), B (pilha aparece), C (estável), D (cancelamentos) e E (rebake da nav) | **100% aprovados** |

---

## 4. Resultado dos Testes Manuais Aprovados pelo Proprietário

Em 15/11/2026, o proprietário realizou a execução manual completa do protocolo [T3_2_manual_test_protocol.md](T3_2_manual_test_protocol.md) nas resoluções `1280×720` e `1920×1080`, deliberando pela **aprovação integral de todos os 11 itens sem ressalvas**:

| ID | Verificação Manual | Resoluções | Resultado |
|---|---|---|---|
| **A1** | Ativação por botão e atalho (`F6` / `F7`), alternância de escala (4×4 m vs 5×4 m), foco limpo | 1280×720 e 1920×1080 | **APROVADO** |
| **A2** | Movimento contínuo sem grid, silhueta sem saltos, sem sombras duplicadas, sem grade excessiva | 1280×720 e 1920×1080 | **APROVADO** |
| **B1** | Área protegida do acampamento (D6) com rejeição imediata no perímetro e texto legível | 1280×720 e 1920×1080 | **APROVADO** |
| **B2** | Rejeição sobre obstáculos, árvores, rochas, arbustos e personagens com diagnóstico correto | 1280×720 e 1920×1080 | **APROVADO** |
| **B3** | Rejeição em rampas inclinadas, desníveis de platô e corredor estreito bloqueado | 1280×720 e 1920×1080 | **APROVADO** |
| **C1** | Clique esquerdo em local inválido mantém prévia ativa e reforça motivo de recusa | 1280×720 e 1920×1080 | **APROVADO** |
| **C2** | Confirmação simulada válida: pulso visual, encerramento do modo sem criar nós nem alterar estoque | 1280×720 e 1920×1080 | **APROVADO** |
| **C3** | Cancelamento por `Esc` e `RMB` fecha prévia mantendo seleção da unidade e sem ordens RTS | 1280×720 e 1920×1080 | **APROVADO** |
| **D1** | Câmera isométrica (`WASD`, setas, `MMB`, `Scroll`, `Edge Scroll`) funcional durante prévia ativa | 1280×720 e 1920×1080 | **APROVADO** |
| **D2** | Controles RTS (seleção simples, caixa de seleção, ordens de movimento e coleta) íntegros pós-prévia | 1280×720 e 1920×1080 | **APROVADO** |
| **D3** | Layout do HUD e console sem sobreposição e com 0 erros/avisos nas duas resoluções | 1280×720 e 1920×1080 | **APROVADO** |

**Veredito Geral:** APROVADO PELO PROPRIETÁRIO (11/11 aprovados, 0 reprovações, 0 ressalvas).

---

## 5. Auditoria Técnica Independente

A revisão dos arquivos implementados foi realizada de forma independente pelo ChatGPT, distinguindo a análise estática e arquitetural de código da execução dos testes locais no hardware real do usuário:
- Confirmou a eficácia do bake assíncrono e da eliminação de pausas na thread principal.
- Identificou as revisões R1 (desempenho, prévia dinâmica e isolamento regional) e R2 (condição de corrida assíncrona TOCTOU).
- Aprovou as correções técnicas aplicadas e atestou a prontidão para encerramento após validação do proprietário.

---

## 6. Resultados de Desempenho e Limitações Aceitas

Medições reportadas no benchmark `1920×1080` (Intel UHD Graphics 620, `gl_compatibility`, warmup + 32 confirmações):
- **Hover contínuo:** avaliação $p50 = 0,77\text{ ms}$, média $0,95\text{ ms}$, $p95 = 2,12\text{ ms}$; frametime durante hover $p50 = 8,35\text{ ms}$, $p95 = 13,77\text{ ms}$.
- **Confirmação na thread principal:** tempo gasto na thread principal reduzido para $p50 = 13,55\text{ ms}$ (média $13,05\text{ ms}$) e $p95 = 21,92\text{ ms}$ (máximo $21,95\text{ ms}$; em medição prévia sob clock mais elevado registrou $p50 = 6,57\text{ ms}$, $p95 = 15,32\text{ ms}$), reduzindo drasticamente o bloqueio da thread principal frente ao baseline síncrono inicial de $p50 = 92,09\text{ ms}$ e $p95 = 134,71\text{ ms}$.
- **Impacto no frametime durante confirmações assíncronas:** $p50 = 6,87\text{ ms}$, média $7,67\text{ ms}$, $p95 = 15,89\text{ ms}$, máximo $24,60\text{ ms}$ (**0 quadros $> 30\text{ ms}$ e 0 quadros $> 100\text{ ms}$**).
- **Tempo de execução do worker thread (`worker_bake`):** $p50 = 89,99\text{ ms}$, média $92,76\text{ ms}$, $p95 = 163,01\text{ ms}$, máximo $180,84\text{ ms}$ (em medição prévia registrou $p50 = 46,87\text{ ms}$, $p95 = 99,52\text{ ms}$).
- **Tempo total de parede até o callback (`async_confirm_wall_ms`):** $p50 = 106,40\text{ ms}$, média $108,32\text{ ms}$, $p95 = 185,98\text{ ms}$, máximo $192,43\text{ ms}$ (em medição prévia registrou $p50 = 55,52\text{ ms}$, $p95 = 119,55\text{ ms}$).

### Limitações Conhecidas Aceitas no Encerramento
1. **Latência de Parede da Confirmação Assíncrona:** a confirmação assíncrona requer entre ~106 ms e 186 ms de tempo total de parede ($p50\text{–}p95$; variando entre ~56 ms e 120 ms sob clock mais alto) até que o worker thread finalize o bake Recast e o callback seja processado na thread principal. Durante esse intervalo em voo, a prévia mantém-se responsiva, `is_confirm_pending()` bloqueia cliques duplicados, cancelamentos por `Esc`/`RMB` ou troca de edifício são processados imediatamente, e o estado é revalidado no retorno prevenindo aceitação de dados obsoletos.
2. **Custo do Fallback Síncrono:** caso o modo assíncrono seja deliberadamente desativado (`use_async_confirm = false`), o bake síncrono completo na thread principal consome de $p50 = 37,31\text{ ms}$ a $79,44\text{ ms}$ ($p95 = 48,52\text{ ms}$ a $116,31\text{ ms}$) no `TestMap` ($64 \times 64\text{ m}$).
3. **Escalaridade em Mapas Maiores:** se regiões futuras crescerem substancialmente além de $64 \times 64\text{ m}$ (T4/T5), será recomendável implementar particionamento regional ou recorte via `filter_baking_aabb`.
4. **Acoplamento à API de Navegação:** a detecção de obsolescência assume que modificações na geometria de navegação ocorram pelos métodos públicos de `WorldNavigation`.

---

## 7. Garantias de Compatibilidade com T1, T2 e T3.1

- **T1:** movimentação, câmera isométrica, rotas com obstáculos, desvios RVO e seleções RTS continuam operando normalmente sem alterações de comportamento.
- **T2:** ciclos de coleta, cálculo de carga e peso, entrega no acampamento e decaimento temporal em pilhas físicas continuam 100% aprovados na suíte segmentada.
- **T3.1:** a contabilidade de estoque (`SettlementInventory`), livro-razão de reservas (`PileReservationLedger`) e saques em lote transacionais permanecem preservados; a confirmação simulada da T3.2 não reserva nem consome recursos.

---

## 8. Funcionalidades Deliberadamente Não Implementadas (Escopo da T3.3+)

Permanecem intencionalmente ausentes da T3.2, sem placeholders ou simulações:
- Criação de canteiro de obras (`ConstructionSite`).
- Alocação e reserva de recursos para montagem.
- Transporte físico de materiais por trabalhadores até o canteiro.
- Incorporação de materiais, trabalho de montagem e conclusão do edifício.
- Gravação do obstáculo definitivo na `WorldNavigation` ativa.
- Interface definitiva com catálogo retrátil e painel de inspeção de canteiro (T3.5).
- Persistência de obras em disco (T3.8).

---

## 9. Estado de Governança e Próxima Etapa

- **Estado Atual:** A etapa **T3.2** está concluída, tecnicamente auditada, testada manualmente e formalmente aprovada pelo proprietário na branch `feature/t3-2-placement`.
- **Integração:** A branch permanece isolada aguardando decisão expressa do proprietário para integração à `main` via procedimento fast-forward.
- **Próxima Etapa Planejada:** **T3.3 — Canteiro de Obra e Suprimento Físico (Transporte)**, que permanece **estritamente bloqueada sem autorização prévia de implementação**.
