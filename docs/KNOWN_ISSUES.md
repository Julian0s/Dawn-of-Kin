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

---

## 3. Execução da suíte automatizada combinada acima de 240 s (T2.6)

- **Observação medida:** A suíte total (`27` suítes, `180` testes, `6.423` asserções) divide-se em `12` suítes unitárias (`85` testes, `~7,2 s` internos) e `15` suítes de integração (`95` testes, `~239 s` internos em processo único), de modo que a execução integral em um único processo Godot ultrapassa o limite de `240 s` porque testes de integração simulam tempos reais de coleta (`1,5 s` / `2,5 s` / `3,5 s`), movimento e rebakes de NavMesh em tempo real de 60 Hz (`~15–46 s` por suíte pesada).
- **Mitigação implementada em `T2.6`:** `tools/run_tests.ps1 -Segmented` executa descoberta automática (`--discovery-only`), particiona os lotes em grupos menores (`unit` + `integration-01`..`05` com até `3` suítes por lote e limite individual de `120 s`), verifica bijeção exata (`Discovered == ExecutedUnique`, `0` duplicatas, `0` omissões), preserva avisos/erros e agrega os totais. Execução segmentada **não** é apresentada como execução integral em processo único.
- **Correções associadas de estabilidade descobertas durante `T2.6`:**
  - `src/navigation/world_navigation.gd`: `request_rebake()` passa a registrar as revisões mínimas de mapa e região para `_check_navigation_server_ready()`, evitando falso pronto ao reaproveitar a `World3D` entre múltiplas cenas no mesmo processo.
  - `tests/integration/test_t2_pace_and_load.gd`: `test_02` agora descarrega frames residuais de limpeza antes de acionar a extração e amostra todos os frames desde o frame 1, evitando que pausas de teardown pulem o pulso de `0,22 s` do `Tween` sob espera fixa de 2 frames.

---

## 4. Benchmark representativo T2 vs referência T1 na Intel UHD 620 (T2.6)

- **Condições medidas em `2026-11-14` (`tests/perf/t2_perf_benchmark.gd` e `tests/perf/perf_benchmark.gd`, `gl_compatibility`, `VSYNC_DISABLED`, sem `--fixed-fps`, esquema `Equilibrado`, bateria em carga `37–38%`, Intel Core i7-8650U + Intel UHD Graphics 620):**
  - **Referência T1 na cena atual (`1920x1080`, mediana de 3×30s após 5s aquecimento):**
    - FPS médio: `54,78` | `p50 = 13,113 ms` | `p95 = 35,435 ms` | `p99 = 46,020 ms` | `max = 70,691 ms` (pior `79,916 ms`) | `0` quadros `> 100 ms`.
    - Run 1: `p95 = 35,705 ms` (`53,96 FPS`) | Run 2: `p95 = 35,435 ms` (`54,78 FPS`) | Run 3: `p95 = 33,699 ms` (`55,25 FPS`).
  - **Cenário representativo T2 (`1280x720`, mediana de 3×30s, coleta simultânea + pilhas físicas + HUD + clock econômico acelerado em `35x` para exercer deterioração real):**
    - FPS médio: `78,32` | `p50 = 9,514 ms` | `p95 = 24,503 ms` | `p99 = 42,348 ms` | `max = 53,764 ms` (pior `56,850 ms`) | `0` quadros `> 100 ms`.
    - Run 1: `p95 = 24,503 ms` (`78,32 FPS`) | Run 2: `p95 = 24,618 ms` (`78,28 FPS`) | Run 3: `p95 = 24,408 ms` (`79,92 FPS`).
  - **Cenário representativo T2 (`1920x1080`, mediana de 3×30s):**
    - FPS médio: `53,96` | `p50 = 14,910 ms` | **`p95 = 33,766 ms`** | `p99 = 40,180 ms` | `max = 59,068 ms` (pior `60,826 ms`) | `0` quadros `> 100 ms`.
    - Run 1: `p95 = 33,681 ms` (`54,23 FPS`) | Run 2: `p95 = 33,766 ms` (`53,92 FPS`) | Run 3: `p95 = 33,793 ms` (`53,96 FPS`).
    - Eventos reais por execução (`30 s`): `2` entregas em acampamento, `11` passos de deterioração (`12` unidades decaídas), `2` pilhas físicas ativas ao final, `13` atualizações do painel de estoque e `16` do painel de unidade (`< 1%` dos quadros).
- **Diagnóstico honesto e pendência:**
  - A lógica da economia T2, pilhas físicas, deterioração centralizada e HUD por sinais **não** introduziu degradação perceptível (`53,96 FPS` T2 vs `54,78 FPS` referência T1 em `1920x1080`; `0` quadros `> 100 ms`).
  - Contudo, sob energia `Equilibrado` em bateria em carga (`37–38%`), **tanto a referência T1 quanto o cenário T2 ultrapassaram a meta formal `p95 <= 16,7 ms` em `1920x1080`** (`35,435 ms` e `33,766 ms`, contrastando com `16,586 ms` medidos na T1.10 antes da composição de T2 e em estado térmico/energia diferente). Requer medição adicional com energia CA plena / perfil gráfico futuro de sombras e escala 3D.

---

## 5. Limites visuais provisórios aceitos até T2.6

- Assets geométricos provisórios para pilhas no chão (`GroundResourcePile`) e fontes (`wood_tree`, `stone_rock`, `food_bush`), feedback corporal simples durante coleta e ausência de efeitos sonoros permanecem intencionalmente fora do escopo T2 conforme [Dawn_of_Kin_GDD_v1.0.md](file:///c:/Projetos/Dawn%20of%20Kin/docs/Dawn_of_Kin_GDD_v1.0.md) e aceite da etapa T2.4.3.
