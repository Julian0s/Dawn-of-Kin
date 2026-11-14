# Dawn of Kin — Problemas Conhecidos e Observações Reais (T1 e T2)

Registro objetivo de limitações medidas e observações técnicas dos marcos **T1 — Fundação RTS** e **T2 — Trabalho e Recursos**.

---

## 1. Margem de desempenho em `1920x1080` na Intel UHD 620 (AC-13)

- **Critério relacionado:** `AC-13` / Seção 10.6 (`p95 <= 16,7 ms` em `1920x1080` na Intel UHD Graphics 620 e nenhum quadro `> 100 ms` pós-aquecimento).
- **Status:** **Aprovado segundo o critério formal (mediana de três execuções), com margem estreita sob bateria.**
- **Correção aplicada na T1.10:**
  - `Terrain/Ground/MeshInstance3D.cast_shadow = 0` (`OFF` no piso plano inferior em [test_map.tscn](../levels/test_map/test_map.tscn), mantendo sombras em `Plateau`, `Ramp`, paredes, rochas, árvores e unidades).
  - `DirectionalLight3D` configurado com `directional_shadow_mode = SHADOW_ORTHOGONAL` (`0`) e `directional_shadow_max_distance = 75.0` em [test_map.tscn](../levels/test_map/test_map.tscn).
  - `lights_and_shadows/directional_shadow/size = 2048` em [project.godot](../project.godot), preservando filtro `SOFT_LOW` e textura triplanar do terreno.
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

## 3. Execução da suíte automatizada combinada acima de 240 s (T2.6 / B1)

- **Observação medida:** A suíte total consolidada (**27 suítes, 182 testes, 6.469 asserções**) divide-se em 12 suítes unitárias (85 testes) e 15 suítes de integração (97 testes), de modo que a execução integral em um único processo Godot ultrapassa o limite de `240 s` porque testes de integração simulam tempos reais de coleta (`1,5 s` / `2,5 s` / `3,5 s`), movimento físico e rebakes de NavMesh em tempo real de 60 Hz (`~15–46 s` por suíte pesada).
- **Mitigação implementada em `T2.6`:** `tools/run_tests.ps1 -Segmented` executa descoberta automática (`--discovery-only`), particiona os lotes em grupos menores (`unit` + `integration-01`..`05` com até `3` suítes por lote e limite individual de `120 s`), verifica bijeção exata (`Discovered == ExecutedUnique`, `0` duplicatas, `0` omissões), preserva avisos/erros e agrega os totais. Execução segmentada **não** é apresentada como execução integral em processo único.
- **Correções associadas de estabilidade descobertas durante `T2.6` e `B1`:**
  - `src/navigation/world_navigation.gd`: `request_rebake()` passa a registrar as revisões mínimas de mapa e região para `_check_navigation_server_ready()`, evitando falso pronto ao reaproveitar a `World3D` entre múltiplas cenas no mesmo processo.
  - `tests/integration/test_t2_pace_and_load.gd`: `test_02` agora descarrega frames residuais de limpeza antes de acionar a extração e amostra todos os frames desde o frame 1. Os testes `test_12` e `test_13` foram adicionados em B1 para verificar que viagens subsequentes e interrupções manuais com carga preservam a velocidade unificada e o inventário.

---

## 4. Benchmarks de Desempenho T2 vs Referência T1 na Intel UHD 620 (T2.6, D2, B1 e B1.1)

- **Resolução de teste:** 1920×1080 (Full HD, janela de 1920×1080)
- **Engine e Hardware:** Godot 4.7.2, `gl_compatibility`, `VSYNC_DISABLED`, Intel Core i7-8650U + Intel UHD Graphics 620.
- **Histórico comparativo de medições:**
  1. **Medição T2.6 Inicial em Bateria DC (`37–38%` de carga):**
     - Referência T1: FPS médio `54,78` | $p95 = 35,435\text{ ms}$ | $0$ quadros $> 100\text{ ms}$.
     - Cenário T2: FPS médio `53,96` | $p95 = 33,766\text{ ms}$ | $0$ quadros $> 100\text{ ms}$.
     - Observação: Ambos os cenários operaram muito próximos, indicando que a lógica da economia T2 não adicionou custo perceptível, porém sob bateria DC o $p95$ manteve-se acima de $16,7\text{ ms}$.
  2. **Auditoria D2 em Tomada CA (Bateria ~95–100%):**
     - Referência T1: FPS médio `125,19` | $p95 = 12,141\text{ ms}$ | $0$ quadros $> 100\text{ ms}$ (**APROVADO**).
     - Cenário T2: FPS médio `125,42` | $p95 = 13,487\text{ ms}$ | $0$ quadros $> 100\text{ ms}$ (**APROVADO**).
  3. **Pós-Correção B1 em Bateria DC (Bateria ~50–79%):**
     - Cenário T2: FPS médio `55,80` | $p95 = 33,038\text{ ms}$ | $0$ quadros $> 100\text{ ms}$ (**critério de `p95 <= 16,7 ms` não atendido na bateria B1**).
  4. **Pós-Correção B1.1 em Tomada CA (Bateria 42%–79% em recarga):**
     - Cenário T2: FPS médio `147,33` | **$p95 = 9,757\text{ ms}$** | $p99 = 11,679\text{ ms}$ | Máximo absoluto `25,258 ms` | **$0$ quadros $> 100\text{ ms}$** (**critério atendido com folga de 6,943 ms**).
- **Ressalvas metodológicas de integridade:**
  - Os resultados sustentam uma associação entre condições de alimentação (tomada CA vs. bateria DC) e o desempenho medido, porém não há telemetria síncrona direta (clock, temperatura ou potência por quadro) suficiente para comprovar de forma definitiva o mecanismo físico específico.
  - **Estado por critério:**
    - **CA:** `p95 = 9,757 ms` — critério atendido na bateria B1.1.
    - **DC:** `p95 = 33,038 ms` — critério de `p95 <= 16,7 ms` não atendido na bateria B1.
    - **Critério de spikes:** zero quadros acima de 100 ms nas duas baterias (CA e DC).
  - A aprovação em CA aplica-se estritamente às condições de tomada CA; a classificação do desempenho em DC como limitação aceitável para encerrar a T2 **ainda depende de decisão expressa do proprietário**.

---

## 5. Limites visuais provisórios aceitos até T2.6

- Assets geométricos provisórios para pilhas no chão (`GroundResourcePile`) e fontes (`wood_tree`, `stone_rock`, `food_bush`), feedback corporal simples durante coleta e ausência de efeitos sonoros permanecem intencionalmente fora do escopo T2 conforme [Dawn_of_Kin_GDD_v1.0.md](Dawn_of_Kin_GDD_v1.0.md) e aceite da etapa T2.4.3.
