# Dawn of Kin — Problemas Conhecidos e Observações Reais (T1)

Registro objetivo de limitações medidas e observações técnicas do marco **T1 — Fundação RTS**.

---

## 1. Margem de desempenho em `1920x1080` na Intel UHD 620 (AC-13)

- **Critério relacionado:** `AC-13` / Seção 10.6 (`p95 <= 16,7 ms` em `1920x1080` na Intel UHD Graphics 620 e nenhum quadro `> 100 ms` pós-aquecimento).
- **Status:** **Aprovado segundo o critério formal (mediana de três execuções), com margem estreita sob bateria.**
- **Correção aplicada na T1.10:**
  - `Terrain/Ground/MeshInstance3D.cast_shadow = 0` (`OFF` no piso plano inferior em [test_map.tscn](file:///c:/Projetos/Dawn%20of%20Kin/levels/test_map/test_map.tscn), mantendo sombras em `Plateau`, `Ramp`, paredes, rochas, árvores e unidades).
  - `DirectionalLight3D` configurado com `directional_shadow_mode = SHADOW_ORTHOGONAL` (`0`) e `directional_shadow_max_distance = 75.0` em [test_map.tscn](file:///c:/Projetos/Dawn%20of%20Kin/levels/test_map/test_map.tscn).
  - `lights_and_shadows/directional_shadow/size = 2048` em [project.godot](file:///c:/Projetos/Dawn%20of%20Kin/project.godot), preservando filtro `SOFT_LOW` e textura triplanar do terreno.
- **Medições pós-correção (`gl_compatibility`, `VSYNC_DISABLED`, bateria / plano `Equilibrado`, i7-8650U + Intel UHD Graphics 620):**
  - `1280x720` (mediana de 3×30s): FPS médio `185,86`, `p50 = 5,173 ms`, `p95 = 8,223 ms`, `p99 = 9,757 ms`, `max = 22,878 ms` (pior `26,830 ms`), `0` quadros `> 100 ms`.
  - `1920x1080` (mediana de 3×30s): FPS médio `94,24` (anterior: `37,97`), `p50 = 10,236 ms` (anterior: `26,414 ms`), **`p95 = 16,586 ms`** (anterior: `39,568 ms`, meta: `≤ 16,7 ms`), `p99 = 19,562 ms`, `max = 33,465 ms` (pior `47,300 ms`), `0` quadros `> 100 ms` (Run 1: `14,055 ms`; Run 2: `16,586 ms`; Run 3: `17,016 ms`).
  - Nativa `3240x2160` fullscreen (mediana de 3×30s): FPS médio `30,39` (anterior: `20,05`), `p50 = 32,171 ms`, `p95 = 40,409 ms`, `p99 = 44,880 ms`, `max = 52,274 ms` (pior `69,613 ms`), `0` quadros `> 100 ms`.
- **Ressalva e alerta técnico:**
  - A margem da mediana em relação ao limite na bateria é de apenas `0,114 ms` (`16,586 ms` vs `16,700 ms`), tendo o Run 3 marcado `17,016 ms` por throttling térmico/energia contínua na bateria.
  - Novos benchmarks serão obrigatórios conforme a população, construções e vegetação crescerem em fases futuras (T2+), exigindo implementação de opções gráficas para o jogador (resolução de sombra, escala de renderização 3D) e avaliação de LODs.

---

## 2. Custo e escalabilidade do RVO e física por unidade

- **Observação:** Na medição controlada com 2 protagonistas ativos (`tests/perf/rvo_cost_breakdown.gd`), habilitar RVO elevou:
  - `TIME_NAVIGATION_PROCESS`: de `0,139 ms` (`138,6 µs`) para `0,516 ms` (`515,6 µs`), delta de `+377,0 µs` (solver nativo de evasão).
  - `TIME_PHYSICS_PROCESS`: de `1,991 ms` (`1.990,7 µs`) para `2,362 ms` (`2.361,6 µs`), delta de `+370,9 µs` — dos quais `~45,3 µs` vêm das chamadas `map_get_closest_point` (`_clamp_avoidance_to_navmesh`) e `~325,6 µs` da sincronização C++ do `NavigationAgent3D`, disparo do sinal `velocity_computed` e lógica GDScript associada.
  - Em `IDLE` com RVO ligado, há também custo passivo base (`+662,5 µs` em navegação e `+723,2 µs` em física) apenas por manter os agentes registrados no servidor RVO.
- **Estresse informativo (`tests/perf/rvo_stress_test.gd`):**
  - `2` → `10` → `25` → `50` unidades simultâneas em convergência cruzada escalaram `phys_avg_ms` de `2,14 ms` → `6,17 ms` → `9,24 ms` → `14,56 ms`, mantendo `0` sobreposições (`< 0,80 m`).
  - Com `50` unidades convergindo simultaneamente para o centro, `2` ordens falharam por congestionamento (`stuck`), comportamento esperado para convergência densa sem formação hierárquica.
