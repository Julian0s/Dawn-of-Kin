# Relatório Técnico: T2.6-B1 — Unificação da Velocidade de Deslocamento (DRAFT)

**Data:** 14/11/2026<br>
**Branch:** `fix/t2-6-b1-unified-travel-speed`<br>
**Commit-base:** `3ba32552915fb81cec896aa809612f210ad0be94`<br>
**Status:** Implementado, validado e coberto por testes automatizados (aguardando teste visual do proprietário)

---

## 1. Diagnóstico do Problema

Durante a execução do protocolo manual da fase T2, observou-se a seguinte divergência de controle:
> Ao ordenar que um personagem caminhe até um ponto do mapa, ele anda mais rápido do que quando recebe uma ordem de coleta. A redução de velocidade precisa decorrer exclusivamente do peso transportado, e não do tipo de ordem recebida.

### Causa Raiz Técnica
1. Em `src/units/orders/gather_resource_order.gd` (`start()`), a ordem forçava `movement.set_speed_context(UnitMovement.SpeedContext.WORK)`.
2. Em `src/units/orders/deliver_to_camp_order.gd` (`start()`), o transporte de entrega também ativava `SpeedContext.WORK`.
3. Em `src/units/unit_movement.gd` (`_recompute_target_speed()`), o contexto `WORK` selecionava `_work_approach_speed` (2,5 m/s) como velocidade-base, ao invés da velocidade normal `_move_speed` (4,8 m/s).
4. Como consequência:
   - Caminhada livre sem carga (`MoveOrder`): 4,8 m/s.
   - Aproximação para coleta sem carga (`GatherResourceOrder`): 2,5 m/s.
   - Retorno carregado ao acampamento (`DeliverToCampOrder`): 2,5 m/s × 0,60 = 1,5 m/s.

---

## 2. Alterações Implementadas

Para solucionar o problema de forma mínima, localizada e sem quebras arquiteturais:

1. **`src/units/orders/gather_resource_order.gd`**:
   - `start()`: alterado de `SpeedContext.WORK` para `SpeedContext.NORMAL`.
   - `_start_approaching_source()`: reforçado `movement.set_speed_context(SpeedContext.NORMAL)`, garantindo que após descarregar no acampamento e retornar para o 2º, 3º e sucessivos ciclos de extração, a velocidade-base permaneça unificada em 4,8 m/s.
   - `cancel()`: restaura explicitamente `SpeedContext.NORMAL`.
2. **`src/units/orders/deliver_to_camp_order.gd`**:
   - `start()`: alterado de `SpeedContext.WORK` para `SpeedContext.NORMAL`.
   - `cancel()`: restaura explicitamente `SpeedContext.NORMAL`.
3. **Preservação de Fórmulas e Assinaturas Centrais**:
   - Mantida a fórmula de redução proporcional de peso (`UnitMovement.compute_load_speed_multiplier`), o multiplicador de carga máxima (0,60) e a compatibilidade do enum `SpeedContext.WORK` em `UnitMovement` para rotinas isoladas.
   - A extração parada na fonte permanece inalterada (cadências de 1,5s / 2,5s / 3,5s e pausas de preparação de 0,25s / 0,35s / 0,40s preservadas).

---

## 3. Comparativo de Comportamento e Velocidades

| Situação de Deslocamento | Comportamento Anterior | Novo Comportamento Unificado | Base de Cálculo |
| :--- | :---: | :---: | :--- |
| **Caminhada livre sem carga** | 4,80 m/s | **4,80 m/s** | 4,8 m/s × 1,00 |
| **Aproximação de coleta sem carga (1º ciclo)** | 2,50 m/s | **4,80 m/s** | 4,8 m/s × 1,00 |
| **Retorno de entrega (25% carga - 5 alimentos)** | 2,25 m/s | **4,32 m/s** | 4,8 m/s × 0,90 |
| **Retorno de entrega (50% carga - 10 alim. / 5 mad.)** | 2,00 m/s | **3,84 m/s** | 4,8 m/s × 0,80 |
| **Retorno de entrega (75% carga - 15 alimentos)** | 1,75 m/s | **3,36 m/s** | 4,8 m/s × 0,70 |
| **Retorno de entrega (90% carga - 6 pedras / peso 18)** | 1,60 m/s | **3,072 m/s** | 4,8 m/s × 0,64 |
| **Retorno de entrega (100% carga - 20 alim. / 10 mad.)** | 1,50 m/s | **2,88 m/s** | 4,8 m/s × 0,60 |
| **Recuperação imediata após descarregar no acampamento** | 2,50 m/s | **4,80 m/s** | 4,8 m/s × 1,00 |
| **Aproximação de coleta no 2º ciclo (pós-entrega)** | 2,50 m/s | **4,80 m/s** | 4,8 m/s × 1,00 |
| **Ordem manual com carga preservada (interrupção)** | Reduzido s/ 4,8 m/s | **Reduzido proporcional à carga** | 4,8 m/s × load_mult |

---

## 4. Testes Automatizados

### A. Testes Atualizados e Novos (`tests/integration/test_t2_pace_and_load.gd`)
- `test_07_real_pace_full_cycle_approach_work_slow_loaded_return_and_unload_recovery`:
  - Atualizado para verificar aproximação sem carga a ~4,8 m/s, retorno com 100% de madeira a ~2,88 m/s e retorno imediato a 4,8 m/s após a descarga no acampamento.
- `test_12_gather_and_deliver_travel_speeds_at_various_load_tiers` (novo):
  - Valida alvos de velocidade para aproximação vazia (4,80 m/s), entregas escalonadas (25% = 4,32 m/s; 50% = 3,84 m/s; 75% = 3,36 m/s; 100% = 2,88 m/s; 90% pedra = 3,072 m/s) e a execução real de entrega com descarga limpa e conservação estrita.
- `test_13_second_cycle_and_interrupted_manual_move_with_preserved_load` (novo):
  - Valida que o 2º ciclo de aproximação mantém contexto `NORMAL` a 4,80 m/s.
  - Valida que interrupções por clique manual preservam o inventário transportado e respeitam a velocidade reduzida proporcional à carga.
  - Valida que reemitir coleta com carga pendente faz a entrega prévia a 2,88 m/s antes de iniciar nova coleta.

### B. Resultado da Suíte Segmentada (`.\tools\run_tests.ps1 -Segmented`)
- **Total de suítes executadas:** 27
- **Total de testes:** 182
- **Passaram:** 182 (100%)
- **Falharam:** 0
- **Avisos / Erros:** 0
- **Total de asserções:** 6.469
- **Tempo acumulado Godot:** 262,4 s (dividido em 6 lotes disjuntos)

---

## 5. Benchmark de Desempenho T2 (1920×1080)

Executado via `.\tools\perf.ps1 -Mode t2 -ProfileFilter "1920x1080" -Runs 3 -WarmupSec 5 -DurationSec 30`.

- **Condições de alimentação no teste:** Bateria (DC), plano `Equilibrado`, `PowerOnline = False`, carga 50%-79%.
- **Resultados medidos (5.030 quadros monitorados):**
  - **FPS médio mediano:** 55,8 FPS
  - **Frame médio:** ~17,9 ms
  - **p50 mediano:** 14,872 ms
  - **p95 mediano:** 33,038 ms (compatível com a baseline de bateria T2.6 de 33,766 ms)
  - **p99 mediano:** 41,797 ms
  - **Quadros > 100 ms:** **0** (0,00%)
- **Nota metodológica:** Conforme detalhado em `T2_6_D2_performance_DRAFT.md`, a medição em bateria (DC) sofre estrangulamento da GPU integrada Intel UHD 620 para economia energética (p95 ~33 ms). Em alimentação AC sem recarga agressiva, a GPU atinge ~145 FPS com p95 de ~9,5 ms. Em ambas as condições, o critério de **zero travamentos acima de 100 ms** foi mantido com perfeição.

---

## 6. Próximos Passos
1. Realização do teste visual pelo proprietário para atestar a fluidez da aproximação e do retorno carregado.
2. Auditoria externa no GitHub.
3. Não iniciar T3 antes do encerramento formal da T2.
