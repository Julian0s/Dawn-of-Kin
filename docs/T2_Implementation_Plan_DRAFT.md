# T2 — Plano de Implementação Revisado: Somente Pilhas Individuais no Acampamento

> **STATUS: CONSOLIDADO PARA ACEITE FINAL (CANDIDATO T2-CLOSEOUT)**
>
> Este documento registra o plano de execução incremental da **T2 — Trabalho e Recursos**, cujas etapas `T2.0` a `T2.6` e o polimento `B1` foram integralmente implementadas, testadas e consolidadas na branch `review/t2-closeout-candidate`. Preservado como histórico do planejamento técnico aprovado.

---

## 1. Pré-requisitos, baseline e sistemas retirados

- **Baseline Git e engine:** branch base `main` em `t1-complete` (`2808799`), Godot `4.7.2`, GDScript tipado, `Compatibility / OpenGL 3.3`, **Intel UHD 620 (16 GB RAM)**.
- **Invariante de regressão contínua:** em **todos** os incrementos (`T2.0` a `T2.6`), `tools/validate.ps1` e `tools/run_tests.ps1` devem continuar executando integralmente os **90 testes e 1.607 asserções da T1**, preservando corredores espaciais (`test_commands.gd`), `TestMap/Obstacles` (`test_test_map.gd`) e o clique direito no chão como movimento RTS (`MoveOrder`).
- **Invariante de desempenho (`KNOWN_ISSUES.md`):** pós-T1.10 em `1920×1080`, `p95 = 16,586 ms` (folga de `0,114 ms` sobre `16,7 ms`).
- **Invariante de início:** casal protagonista inicia **sem ferramentas, sem equipamentos e sem construções humanas pré-existentes**.

### Sistemas desnecessários retirados desta revisão
Em alinhamento com a decisão de restringir a T2 a **somente pilhas individuais dentro do acampamento**:
- Retirado `DropLoadOrder`, modo/botão de "Soltar carga no chão" e atalho `Alt + Clique Direito`;
- Retirado `CollectFromPileOrder` e picking/transporte de pilhas abandonadas fora do acampamento;
- Retirada a lógica de conversão de pilhas externas em estoque e o termo `PilhasExternas` da contabilidade da T2.

*(Essas ideias permanecem registradas apenas como histórico caso sejam reconsideradas em fase futura, sem compromisso nem aprovação.)*

---

## 2. Escopo da T2 vs adiamentos (`T3+` / `T4+`)

| Item | Entra na T2? | Justificativa |
|---|---|---|
| Dados econômicos, pesos, capacidade (`0%`–`100%`) e estoque (`SettlementInventory`) | **Sim** | Núcleo da decisão D2-1. |
| Pilhas físicas individuais no acampamento (`GroundResourcePile` + placeholders simples) | **Sim** | Decisão **DECIDIDO** para a T2. |
| Agrupamento determinístico e múltiplas pilhas da mesma categoria (incluindo parciais) | **Sim** | Exigido para descarga, consumo e deterioração sincronizada. |
| Deterioração centralizada via `GroundPileManager` (sem `_process` por pilha) | **Sim** | Decisão **DECIDIDO**; fundamenta os armazéns da T3. |
| Fontes naturais coletáveis, estado do trabalhador e concorrência | **Sim** | Ciclo completo de trabalho da T2. |
| Armazéns construíveis com proteção contra deterioração | **Não (adiado para T3)** | Pertence à `T3 — Construção`; na T2 deixamos `StoragePoint` e `decay_multiplier = 0.0` preparados. |
| Ciclo dia/noite, calendário completo e Save/Load em disco | **Não (adiado para T4)** | Pertence à `T4`; na T2 isolamos apenas `WorldTimeProvider`. |
| Modelos 3D definitivos | **Não (pós-protótipo)** | Placeholders simples autorizados pelo GDD §16. |

---

## 3. Sequência incremental simplificada (`T2.0` a `T2.6`)

### Incremento `T2.0` — Dados Econômicos, Pesos, Capacidade (`0%`–`100%`) e Estoque
- **Objetivo:** implementar os contratos puros e determinísticos de dados econômicos (`ResourceDefinition`, `DecayProfile` parametrizável), mochila física da unidade (`UnitCarryLoad`) e a base do `SettlementInventory` com transações atômicas.
- **Arquivos/módulos previstos:** `ResourceDefinition`, `DecayProfile`, `UnitCarryLoad`, `SettlementInventory` e suíte unitária dedicada (com defaults provisórios claramente marcados como parametrizáveis/não aprovados).
- **Dependências:** aprovação do proprietário sobre a arquitetura/plano e permissão para defaults provisórios parametrizáveis.
- **Riscos:** divergência posterior de pesos/capacidades se valores ficarem hardcoded em código em vez de recursos `.tres`/dados.
- **Testes obrigatórios:**
  - Pesos distintos por material, cálculo exato de porcentagem (`0%`–`100%`), recusa de `+1` unidade que ultrapasse `100%`;
  - Nenhuma criação silenciosa, nenhum estoque negativo e proibição de crédito antes da entrega;
  - Regressão integral dos **90 testes / 1.607 asserções da T1**.
- **Critério de aceite:** suíte unitária da `T2.0` + `T1` 100% verdes em headless, zero avisos.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen Medium**.

### Incremento `T2.1` — Pilhas Físicas no Acampamento (`GroundResourcePile`), Deterioração Centralizada e Sincronia com Estoque
- **Objetivo:** implementar `CampStorageZone` (zona lógica no chão sem construções), `GroundResourcePile` (placeholders de madeira, pedra e alimentos com escala/faixa variável), `GroundPileManager` (posicionamento determinístico em slots no NavMesh, agrupamento compatível, suporte a múltiplas pilhas da mesma categoria incluindo parciais), `WorldTimeProvider` (hook T4) e motor de deterioração centralizado (zero `_process` por pilha), mantendo `SettlementInventory` sincronizado como projeção exata das pilhas válidas do acampamento.
- **Arquivos/módulos previstos:** `CampStorageZone`, `GroundResourcePile`, `GroundPileManager`, `WorldTimeProvider`, extensão de sincronia atômica com `SettlementInventory` e testes unitários/integração.
- **Dependências:** `T2.0` concluída.
- **Riscos:** dessincronização entre soma das pilhas e `SettlementInventory` ao consumir/deteriorar parcialmente múltiplas pilhas; mitigado mantendo uma única autoridade transacional.
- **Testes obrigatórios:**
  - Entrega em `CampStorageZone` cria/agrupa pilhas corretamente e `SettlementInventory` reflete o total exato (ex.: `24` madeiras em pilhas = `24` no estoque);
  - Múltiplas pilhas da mesma categoria com quantidades parciais: retirada/consumo abate em ordem determinística sem nunca gerar saldo ou pilha negativa nem contagem duplicada;
  - Deterioração controlada reduz quantidades (e remove pilha ao zerar) atualizando `SettlementInventory` na mesma transação e contabilizando perda intencional;
  - Simulação de proteção (`decay_multiplier = 0.0`, preparo T3) zera deterioração;
  - Regressão T1 intacta.
- **Critério de aceite:** 100% das invariantes de autoridade única, múltiplas pilhas, deterioração e conservação validadas sem `_process` por pilha.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen High**.

### Incremento `T2.2` — Fontes Naturais Coletáveis e Picking Compatível com T1
- **Objetivo:** criar `ResourceSource` parametrizável (árvore, arbusto, rocha com estoque finito) na camada `MASK_RESOURCES`, estender `WorldPicker`/`PickResult` (`RESOURCE_SOURCE` e opcionalmente `CAMP_STORAGE_ZONE` para entrega manual) e manter **100% intacto** o contrato `PickResult.Kind.GROUND → MoveOrder` do clique direito no chão.
- **Arquivos/módulos previstos:** `ResourceSource`, cenas placeholder de fontes, extensão de `PickResult`, `WorldPicker` e `CommandController`.
- **Dependências:** `T2.1` concluída.
- **Riscos:** fontes posicionadas invadindo corredores de `test_commands.gd` ou poluindo `TestMap/Obstacles` (`test_test_map.gd`).
- **Testes obrigatórios:**
  - Picking distingue terreno (`MoveOrder`), unidade, fonte de recurso e zona do acampamento;
  - Corredores de `test_commands.gd` e `test_test_map.gd` 100% preservados;
  - Regressão T1 completa.
- **Critério de aceite:** clique direito no chão segue idêntico à T1; picking em fontes funciona em perspectiva isométrica sem quebrar testes espaciais.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen Medium**.

### Incremento `T2.3` — Ciclo do Trabalhador: Coleta, Transporte, Retorno Automático, Descarga e Concorrência
- **Objetivo:** implementar na unidade os estados e ordens da T2 (caminhar até fonte, coletar acumulando carga física, interromper automaticamente em `100%` ou impossibilidade de `+1` unidade, retornar à `CampStorageZone` e descarregar nas pilhas do acampamento), incluindo entrega parcial quando a fonte esgota, preservação da carga ao cancelar/redirecionar ordem e concorrência entre múltiplos trabalhadores.
- **Arquivos/módulos previstos:** ordens de trabalho/coleta/entrega (`GatherResourceOrder` / `DeliverToCampOrder`), atualização controlada de estados na `Unit` e testes de integração.
- **Dependências:** `T2.2` concluída.
- **Riscos:** condições de corrida ao dois trabalhadores disputarem a última unidade de uma fonte ou convergirem para o mesmo ponto no acampamento (congestionamento RVO).
- **Testes obrigatórios:**
  - Coleta na fonte **não** aumenta `SettlementInventory` antes da descarga física no acampamento;
  - Nenhuma duplicação na entrega e nenhuma perda silenciosa;
  - Fonte esgota antes de `100%` → entrega carga parcial sem travar;
  - Cancelamento ou troca de ordem durante o transporte preserva 100% dos materiais em `UnitCarryLoad`;
  - Dois trabalhadores simultâneos na mesma fonte/descarga preservam conservação exata (`= 0`) e não entram em deadlock RVO;
  - Regressão T1 integral.
- **Critério de aceite:** ciclo completo e todos os cenários de borda e concorrência aprovados com conservação matemática `= 0`.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen High**.

### Incremento `T2.4` — Composição Jogável em `TestMap` sem Infraestrutura Prévia
- **Objetivo:** posicionar fontes naturais iniciais e `CampStorageZone` lógica no cenário principal jogável garantindo **zero construções humanas pré-existentes** e **zero ferramentas iniciais**, mantendo corredores T1 livres e validando concorrência com múltiplas pilhas no mapa real.
- **Arquivos/módulos previstos:** `levels/test_map/test_map.tscn` (nós de fontes/zona sem alterar `TestMap/Obstacles`), `src/main/main.gd` (injeção explícita de dependências T2) e testes de cena/integração.
- **Dependências:** `T2.3` concluída.
- **Riscos:** regressão em `test_test_map.gd` ou impacto visual de sombras na margem de `0,114 ms` da UHD 620.
- **Testes obrigatórios:**
  - Verificação automatizada de ausência de prédios pré-prontos e integridade de `TestMap/Obstacles`;
  - Simulação multi-trabalhador formando e agrupando pilhas de madeira, pedra e alimentos no acampamento;
  - Regressão T1 completa.
- **Critério de aceite:** fluxo jogável integrado na cena principal sem regressões espaciais nem estruturais.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen Medium**.

### Incremento `T2.5` — Interface (HUD) de Carga Individual e Estoque do Acampamento
- **Objetivo:** exibir de forma limpa e desacoplada: porcentagem individual de carga (`0%`–`100%`) e estado da unidade selecionada, estoque coletivo sincronizado por categoria (madeira, pedra, alimentos) e indicação discreta de exposição à deterioração nas pilhas do acampamento.
- **Arquivos/módulos previstos:** nós/controladores leves de HUD em `src/ui/` ligados por sinais (sem polling por frame e sem botão de soltar carga no chão).
- **Dependências:** `T2.4` concluída.
- **Riscos:** vazamento de sinais ao limpar seleção ou descarregar cenas; custo de redraw de UI em `1920×1080`.
- **Testes obrigatórios:**
  - HUD reflete fielmente `0%`–`100%` durante coleta/entrega e atualiza exatamente no mesmo valor das pilhas do acampamento após entrega, consumo e deterioração;
  - Seleção vazia / troca de unidade / descarte de cena sem erros;
  - Regressão T1 + T2 verdes.
- **Critério de aceite:** HUD funcional, legível em perspectiva isométrica e desacoplada da lógica de simulação.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen Medium**.

### Incremento `T2.6` — Validação Global, Benchmark na Intel UHD 620 e Aceite Manual
- **Objetivo:** executar validação estática, suíte automatizada completa (**90 testes / 1.607 asserções da T1** + toda a suíte T2), benchmark real em `1920×1080` (`Compatibility`) na **Intel UHD 620** com trabalhadores, fontes e pilhas em deterioração ativas, e conduzir o protocolo manual de mouse/visual com o proprietário.
- **Dependências:** `T2.5` concluída.
- **Verificações obrigatórias:**
  - `tools/validate.ps1` e `tools/run_tests.ps1`: `0` erros, `0` avisos, T1 + T2 100% aprovados;
  - `tools/perf.ps1` / benchmark T2 em `1920×1080` (UHD 620): confirmar **`p95 <= 16,7 ms`** e `0` quadros `> 100 ms`;
  - Protocolo manual (`docs/testing/T2_manual_test_protocol.md`): selecionar protagonistas, coletar madeira/pedra/alimentos, ver carga subir até `100%`, retorno automático, formação/agrupamento de pilhas no acampamento, conferência exata do estoque e verificação visual da deterioração em cenário controlado.
- **Critério de aceite:** testes automatizados verdes + `p95 <= 16,7 ms` medido + aprovação manual expressa do proprietário.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen High**.

---

## 4. Resumo dos testes críticos garantidos pelo plano

| Invariante / Cenário | Onde é provado |
|---|---|
| Nenhuma duplicação na entrega e nenhuma perda silenciosa | `T2.0`, `T2.1`, `T2.3` |
| Nenhum estoque negativo e nenhuma contagem duplicada pilha ↔ inventário | `T2.0`, `T2.1` |
| Coleta na fonte não aumenta estoque antes da entrega física no acampamento | `T2.0`, `T2.3` |
| Cancelamento de transporte preserva materiais na unidade (`UnitCarryLoad`) | `T2.3` |
| Múltiplas pilhas da mesma categoria (incluindo quantidades parciais) sincronizadas | `T2.1`, `T2.3` |
| Deterioração controlada reduz estoque e registra perda intencional | `T2.1`, `T2.5` |
| Concorrência entre múltiplos trabalhadores sem deadlock nem duplicação | `T2.3`, `T2.4` |
| Preservação dos **90 testes / 1.607 asserções da T1** e `p95 <= 16,7 ms` na UHD 620 | `T2.0`–`T2.6` |

---

## 5. Decisões restantes que realmente bloqueiam a `T2.0`

Para iniciar a **`T2.0`** com segurança, apenas dois pontos exigem resposta do proprietário:
1. **Aprovação formal** dos rascunhos revisados (`T2_architecture_DRAFT.md` e `T2_Implementation_Plan_DRAFT.md`).
2. **Autorização para uso dos defaults provisórios parametrizáveis** na `T2.0` (pesos e capacidade inicial em arquivo de dados), ficando os detalhes finais de deterioração (duração exata, perda gradual vs integral, política de `merge` de exposição e diferenças por categoria) em **`ABERTO`** para decisão/calibração antes da `T2.1`–`T2.6`.
