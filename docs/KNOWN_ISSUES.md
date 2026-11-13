# Dawn of Kin — Problemas Conhecidos e Pendências Reais (T1)

Registro objetivo de limitações medidas, defeitos abertos e pendências reais do marco **T1 — Fundação RTS**.

---

## 1. Margem reduzida de desempenho em `1920x1080` na Intel UHD 620 (AC-13)

- **Critério relacionado:** `AC-13` / Seção 10.6 (`p95 <= 16,7 ms` em `1920x1080` na Intel UHD Graphics 620 e nenhum quadro `> 100 ms` pós-aquecimento).
- **Status:** **Resolvido na T1 com margem estreita (`0,114 ms` abaixo do teto sob bateria).**
- **Correção aplicada:**
  - `Terrain/Ground/MeshInstance3D.cast_shadow = 0` (`OFF` no piso plano inferior em [test_map.tscn](file:///c:/Projetos/Dawn%20of%20Kin/levels/test_map/test_map.tscn), mantendo sombras em `Plateau`, `Ramp`, paredes, rochas, árvores e unidades).
  - `DirectionalLight3D` configurado com `directional_shadow_mode = SHADOW_ORTHOGONAL` (`0`) e `directional_shadow_max_distance = 75.0` em [test_map.tscn](file:///c:/Projetos/Dawn%20of%20Kin/levels/test_map/test_map.tscn).
  - `lights_and_shadows/directional_shadow/size = 2048` em [project.godot](file:///c:/Projetos/Dawn%20of%20Kin/project.godot), preservando filtro `SOFT_LOW` e textura triplanar do terreno.
- **Medições pós-correção (`gl_compatibility`, `VSYNC_DISABLED`, bateria / plano `Equilibrado`, i7-8650U + Intel UHD Graphics 620):**
  - `1280x720` (mediana de 3×30s): FPS médio `185,86`, `p50 = 5,173 ms`, `p95 = 8,223 ms`, `p99 = 9,757 ms`, `max = 22,878 ms` (pior `26,830 ms`), `0` quadros `> 100 ms`.
  - `1920x1080` (mediana de 3×30s): FPS médio `94,24`, `p50 = 10,236 ms`, `p95 = 16,586 ms`, `p99 = 19,562 ms`, `max = 33,465 ms` (pior `47,300 ms`), `0` quadros `> 100 ms` (Run 1: `14,055 ms`; Run 2: `16,586 ms`; Run 3: `17,016 ms`).
  - Nativa `3240x2160` fullscreen (mediana de 3×30s): FPS médio `30,39`, `p50 = 32,171 ms`, `p95 = 40,409 ms`, `p99 = 44,880 ms`, `max = 52,274 ms` (pior `69,613 ms`), `0` quadros `> 100 ms`.
- **Risco remanescente para T2–T7:**
  - A margem de `p95` em `1920x1080` na Intel UHD 620 em bateria (`16,586 ms` vs `16,700 ms`, com Run 3 em `17,016 ms` por aquecimento/energia) é estreita. A adição futura de vegetação densa, construções e mais personagens na T2+ exigirá opções gráficas configuráveis para o jogador (ex.: qualidade/resolução de sombras, escala de renderização 3D) e/ou LODs, além da avaliação de renderizador prevista no plano.

---

## 2. Custo e escalabilidade do RVO e física por unidade

- **Observação:** Na medição controlada com 2 protagonistas ativos (`tests/perf/rvo_cost_breakdown.gd`), habilitar RVO elevou:
  - `TIME_NAVIGATION_PROCESS`: de `0,139 ms` (`138,6 µs`) para `0,516 ms` (`515,6 µs`), delta de `+377,0 µs` (solver nativo de evasão).
  - `TIME_PHYSICS_PROCESS`: de `1,991 ms` (`1.990,7 µs`) para `2,362 ms` (`2.361,6 µs`), delta de `+370,9 µs` — dos quais `~45,3 µs` vêm das chamadas `map_get_closest_point` (`_clamp_avoidance_to_navmesh`) e `~325,6 µs` da sincronização C++ do `NavigationAgent3D`, disparo do sinal `velocity_computed` e lógica GDScript associada.
  - Em `IDLE` com RVO ligado, há também custo passivo base (`+662,5 µs` em navegação e `+723,2 µs` em física) apenas por manter os agentes registrados no servidor RVO.
- **Estresse informativo (`tests/perf/rvo_stress_test.gd`):**
  - `2` → `10` → `25` → `50` unidades simultâneas em convergência cruzada escalaram `phys_avg_ms` de `2,14 ms` → `6,17 ms` → `9,24 ms` → `14,56 ms`, mantendo `0` sobreposições (`< 0,80 m`).
  - Com `50` unidades convergindo simultaneamente para o centro, `2` ordens falharam por congestionamento (`stuck`), comportamento esperado para convergência densa sem formação hierárquica.

---

## 3. Verificações manuais pendentes (AC-16)

As verificações abaixo ainda não foram executadas manualmente pelo usuário no jogo real:
1. Comandos RTS por clique direito (T1.8).
2. Desvios RVO e resolução de destinos ocupados/clique sobre aliado (T1.9).
3. Margem física de ~6 px do Edge Scrolling (ajuste pós-T1.7).
4. Execução completa do protocolo em [T1_manual_test_protocol.md](file:///c:/Projetos/Dawn%20of%20Kin/docs/testing/T1_manual_test_protocol.md).
