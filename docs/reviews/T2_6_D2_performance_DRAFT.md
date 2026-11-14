# Dawn of Kin — T2.6-D2: Validação de Spikes e Integridade dos Benchmarks

**Documento:** Minuta Técnica de Revisão de Desempenho (DRAFT)  
**Data:** 14 de novembro de 2026 (Atualizado: T2.6-D2.1)<br>
**Branch:** `docs/t2-6-d2-performance-review`<br>
**Commit-base:** `3ba32552915fb81cec896aa809612f210ad0be94`<br>
**Modelo de análise:** Gemini 3.8 Flash (Low)<br>
**Hardware de referência:** Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz | Intel(R) UHD Graphics 620 (driver 30.0.101.1339)<br>
**Engine:** Godot 4.7.2.stable.official.ed1daf0bf | Renderizador: `gl_compatibility`

> **Aviso de vigência:** Este documento é uma minuta de investigação complementar da etapa T2.6. Não autoriza encerramento de marco, não modifica gameplay, cenas ou código GDScript, e não inicia a etapa T3.

---

## 1. Correções Obrigatórias da Análise Anterior (D1)

A auditoria técnica da entrega D1 apontou três falhas metodológicas que foram retificadas nesta revisão:

1. **Julgamento de critério incompleto retificado:**  
   O contrato formal de desempenho estabelecido no projeto exige **duas condições simultâneas**:
   - Mediana do $p95 \le 16,7\text{ ms}$ em 1920×1080;
   - **Zero quadros acima de 100 ms** após o período de aquecimento.  
   Na medição D1 de 1080p, embora o $p95$ mediano tenha atingido $9,547\text{ ms}$, foram registrados **4 quadros $> 100\text{ ms}$ no Run 3 de T2** (máximo de $225,198\text{ ms}$) e **1 quadro no Run 1 de T1** ($127,040\text{ ms}$). A D1 concluiu erroneamente pela aprovação integral do benchmark ignorando o segundo critério formal. **Nesta revisão, reafirma-se que qualquer quadro $> 100\text{ ms}$ invalida o critério estrito de aceitação da bateria**.

2. **Causalidade sem comprovação direta retificada:**  
   A D1 atribuiu a variação de desempenho ao estrangulamento térmico por recarga de bateria e os spikes ao sistema operacional Windows como certezas estabelecidas, sem apresentar telemetria de sensores ou correlação temporal direta. Nesta revisão, tais conclusões foram reclassificadas: são hipóteses com forte correlação empírica externa, porém a ausência de amostragem síncrona de temperatura/frequência de clock por quadro impede a declaração de causa física comprovada.

3. **Investigação do aviso/erro no executor T1:**  
   A falha de execução observada em `tools/perf.ps1 -Mode benchmark` com `-FailOnWarnings` foi investigada via Windows Event Viewer e log do sistema, identificando a causa raiz exata sem desabilitar o mecanismo estrito de validação.

---

## 2. Auditoria dos Dados da D1 e Causa Raiz da Falha em T1

### 2.1. Causa comprovada da interrupção em `perf.ps1` no benchmark T1
A investigação nos logs locais de eventos do Windows (`Application Error`, Event ID 1000 e `Windows Error Reporting`, Event ID 1001) revelou a causa exata que interrompeu o benchmark de T1 no Run 3 da D1:

- **Carimbo de data/hora:** `14/11/2026 16:25:32`
- **Aplicativo:** `Godot_v4.7.2-stable_win64.exe` (PID `0x288C`)
- **Módulo com falha:** `ig9icd64.dll` (Driver OpenGL ICD da Intel, versão `30.0.101.1339`)
- **Código de exceção:** `0xc0000005` (Access Violation) no deslocamento `0x000000000064a7a6`
- **Contexto técnico:** O script `tests/perf/perf_benchmark.gd` executou integralmente os 30 segundos de medição, calculou as estatísticas, gravou com sucesso o arquivo `test_output/perf/bench_1920x1080_run3.json`, imprimiu a linha `PERF_RESULT` na saída padrão e chamou `quit(0)`. Durante o encerramento do processo e destruição do contexto gráfico pelo driver OpenGL da Intel (`ig9icd64.dll`), ocorreu uma violação de acesso de memória nativa que encerrou o processo com o código de saída NTSTATUS `0xC0000005` (`3221225477`).
- **Comportamento do harness:** `tools/godot.ps1` verifica `($exitCode -eq 0)`. Como o código de saída foi diferente de zero, `Invoke-Godot` retornou `Success = $false`, levando `tools/perf.ps1` a lançar `throw "Benchmark failed on 1920x1080 run 3"`. Não houve aviso textual (`WARNING:`) na saída do Godot.
- **Ressalva de auditoria:** Esse diagnóstico baseia-se na leitura local do log de eventos do sistema operacional Windows (`Get-WinEvent`) gerado concomitantemente à execução, e não em telemetria embutida nos arquivos JSON da suíte.

### 2.2. Origem dos spikes observados na D1
Na bateria D1 em 1080p:
- **T2 Run 1:** 4.227 quadros, 0 quadros $> 100\text{ ms}$, máximo $23,848\text{ ms}$.
- **T2 Run 2:** 4.296 quadros, 0 quadros $> 100\text{ ms}$, máximo $28,757\text{ ms}$.
- **T2 Run 3:** 3.720 quadros, **4 quadros $> 100\text{ ms}$**, máximo **$225,198\text{ ms}$**.
- **T1 Run 1:** 2.400 quadros, **1 quadro $> 100\text{ ms}$** ($127,040\text{ ms}$).

Como os Runs 1 e 2 de T2 executaram exatamente as mesmas 2 entregas de recursos, 11 passos de deterioração acelerada em 35× e 16 atualizações de HUD sem ultrapassar $28,8\text{ ms}$, os 4 picos concentrados exclusivamente no Run 3 representam comportamento não determinístico. Contudo, na ausência de registro sincronizado de threads e processos do host, a causa dos spikes na D1 permanece tecnicamente **não determinada**.

---

## 3. Repetição Controlada D2 (1920×1080, Tomada CA, Bateria 95–100%)

Para verificar se o comportamento com spikes $> 100\text{ ms}$ era reproduzível ou anômalo, foi executada uma nova bateria controlada em 1920×1080, mantendo todas as condições exigidas:
- Godot 4.7.2 oficial, Intel UHD Graphics 620, `gl_compatibility`, VSync desativado, sem `--fixed-fps`.
- Esquema de energia `Equilibrado`, notebook conectado à tomada CA (`PowerOnline: True`, bateria em 95–100%).
- Parâmetros rigorosos: 3 execuções de 30s (+ 5s de aquecimento), avaliando $p95 \le 16,7\text{ ms}$ e quadros $> 100\text{ ms}$.

### 3.1. Resultados individuais da repetição D2

#### Cenário representativo T2 (`t2_perf_benchmark.gd` — 1920×1080)
*(Coleta ativa de 3 recursos, transporte com peso de carga, pilhas de chão no acampamento, deterioração acelerada 35× com 11 passos e HUD completo ativo).*

| Execução D2 | FPS Médio | Frame Médio (ms) | p50 (ms) | p95 (ms) | p99 (ms) | Máximo (ms) | Quadros > 16,7 ms | Quadros > 100 ms | Status Formal |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Run 1** | 110,80 | 9,025 | 8,452 | 14,624 | 17,751 | 28,954 | 57 / 3.324 | **0** | Aprovado |
| **Run 2** | 145,67 | 6,865 | 6,661 | 9,749 | 12,857 | 27,298 | 8 / 4.370 | **0** | Aprovado |
| **Run 3** | 125,42 | 7,973 | 7,198 | 13,487 | 17,053 | 32,101 | 47 / 3.764 | **0** | Aprovado |
| **Consolidado (Mediana)** | **125,42** | **7,973** | **7,198** | **13,487** | **17,053** | **28,954** | **Pior: 32,101** | **Total: 0** | **APROVADO** |

- Resumo do executor (`d2_t2_perf_summary.json`): `median_passed_p95: true`.
- Total correto de quadros avaliados: **11.458 quadros** ($3.324 + 4.370 + 3.764$).
- Quadros $> 33,3\text{ ms}$: **0**.
- Quadros $> 100\text{ ms}$: **0** (máximo absoluto em 90 segundos: $32,101\text{ ms}$).

#### Cenário de referência T1 (`perf_benchmark.gd` — 1920×1080)
*(Varredura circular ampla cobrindo todo o mapa, 2 protagonistas em trânsito com RVO).*

| Execução D2 | FPS Médio | Frame Médio (ms) | p50 (ms) | p95 (ms) | p99 (ms) | Máximo (ms) | Quadros > 16,7 ms | Quadros > 100 ms | Status Formal |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Run 1** | 126,47 | 7,907 | 7,524 | 12,141 | 14,682 | 29,274 | 9 / 3.794 | **0** | Aprovado |
| **Run 2** | 125,19 | 7,988 | 7,606 | 12,032 | 14,849 | 23,460 | 15 / 3.756 | **0** | Aprovado |
| **Run 3** | 112,72 | 8,872 | 8,692 | 13,536 | 16,548 | 24,015 | 31 / 3.381 | **0** | Aprovado |
| **Consolidado (Mediana)** | **125,19** | **7,988** | **7,606** | **12,141** | **14,849** | **24,015** | **Pior: 29,274** | **Total: 0** | **APROVADO** |

- Resumo do executor (`d2_perf_summary.json`): Conclusão com código de saída 0, sem avisos, sem exceções de encerramento.
- Total de quadros avaliados: **10.931 quadros** ($3.794 + 3.756 + 3.381$).
- Quadros $> 100\text{ ms}$: **0** (máximo absoluto em 90 segundos: $29,274\text{ ms}$).

---

## 4. Confronto Geral de Todas as Baterias em 1920×1080

| Bateria | Condição de Alimentação / Estado | Cenário | FPS Médio | p50 (ms) | p95 (ms) | Quadros > 100 ms | Pior Quadro (ms) | median_passed_p95 |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Histórica T1.10** (13/11) | Bateria estável / Mapa inicial | T1 | 94,24 | 10,236 | 16,586 | 0 | 47,300 | `true` |
| **Preliminar T2.6** (14/11 14h) | Bateria 37–38% (recarga rápida) | T1 Ref | 54,78 | 13,113 | 35,435 | 0 | 79,916 | `false` |
| **Preliminar T2.6** (14/11 14h) | Bateria 37–38% (recarga rápida) | T2 Rep | 53,96 | 14,910 | 33,766 | 0 | 60,826 | `false` |
| **D1 Investigativa** (14/11 16h25) | Tomada CA (Bateria 89–100%) | T1 Ref | 133,06 | 7,291 | 10,586 | 1 | 127,040 | `false` (crash teardown) |
| **D1 Investigativa** (14/11 16h30) | Tomada CA (Bateria 89–100%) | T2 Rep | 140,89 | 7,016 | 9,547 | 4 | 225,198 | `false` (>100ms) |
| **D2 Controlada** (14/11 16h42) | Tomada CA (Bateria 95–100%) | **T2 Rep** | **125,42** | **7,198** | **13,487** | **0** | **32,101** | **`true` (APROVADO)** |
| **D2 Controlada** (14/11 16h47) | Tomada CA (Bateria 95–100%) | **T1 Ref** | **125,19** | **7,606** | **12,141** | **0** | **29,274** | **`true` (APROVADO)** |

---

## 5. Auditoria Metodológica e Inconsistências Investigadas

1. **Discrepância T1 vs T2 em 1280×720 (D1):**
   Na D1, em 720p, T1 marcou 79,91 FPS ($p95 = 23,659\text{ ms}$), enquanto T2 marcou 315,32 FPS ($p95 = 4,640\text{ ms}$).
   - **Causa identificada:** Em `perf_benchmark.gd` (T1), a câmera move-se continuamente em uma trajetória elíptica ampla ($X \in [-14, 14]$, $Z \in [-14, 10]$). Ao cruzar os limites do mapa em 720p, a câmera aproxima-se dos nós com sombras projetadas e geometria mais densa, gerando ~110 draw calls por quadro com maior sobrecarga de culling. Em `t2_perf_benchmark.gd`, a câmera permanece focada no centro do acampamento com zoom sutil, permitindo que o fillrate da GPU integrada em 720p entregue mais de 300 FPS. Portanto, a comparação direta entre T1 e T2 em 720p não é válida como medida de custo de simulação.
2. **Consolidação de T1 na D1:**
   Na D1, o benchmark T1 não gerou um `perf_summary.json` consolidado para 1080p devido à exceção no Run 3; os números reportados haviam sido recuperados manualmente dos JSONs individuais gravados em disco antes do crash de saída do processo. Na repetição D2, o executor completou todas as 3 corridas e gerou a consolidação oficial sem falhas.
3. **Comparação entre os cenários T1 e T2:**
   Observa-se na bateria D2 em 1080p:
   - T1: FPS 125,19 | $p50 = 7,606\text{ ms}$ | $p95 = 12,141\text{ ms}$
   - T2: FPS 125,42 | $p50 = 7,198\text{ ms}$ | $p95 = 13,487\text{ ms}$
   A diferença observada entre as medianas de $p95$ é de **$1,346\text{ ms}$**. Como os dois cenários utilizam rotas de câmera e padrões de visibilidade distintos, **essa variação não deve ser interpretada como uma medição isolada e causal do custo estrito da economia T2**, mas sim como evidência comparativa de que ambos os cenários operam com folga substancial (mais de $3,2\text{ ms}$) em relação ao teto de $16,7\text{ ms}$.

---

## 6. Julgamento Formal dos Critérios de Aceitação

Conforme as regras de engenharia do projeto:

- **Critério 1 — Mediana de $p95 \le 16,7\text{ ms}$ em 1920×1080:**  
  **APROVADO.** T2 registrou $13,487\text{ ms}$ (folga de $3,213\text{ ms}$). T1 registrou $12,141\text{ ms}$ (folga de $4,559\text{ ms}$).
- **Critério 2 — Zero quadros $> 100\text{ ms}$ pós-aquecimento:**  
  **APROVADO na bateria D2.** Em 11.458 quadros avaliados de T2 e 10.931 quadros de T1 sob alimentação estável, registraram-se zero quadros $> 100\text{ ms}$ (pior quadro de T2: $32,101\text{ ms}$; pior quadro de T1: $29,274\text{ ms}$).
- **Critério 3 — Execução limpa do benchmark formal:**  
  **APROVADO.** Ambas as suítes em 1080p completaram com código de saída 0, sem avisos e sem bloqueios pelo parâmetro `-FailOnWarnings`.

---

## 7. Evidências Anexadas (Arquivos JSON Sanitizados)

Os resultados brutos de cada corrida analisada estão salvos no repositório na pasta `docs/reviews/evidence/`:

- `d1_t1_1080p_run1.json` a `run3.json`: Execuções T1 da D1 (incluindo o Run 1 com spike isolado e Run 3 antes do crash de saída).
- `d1_t2_1080p_run1.json` a `run3.json`: Execuções T2 da D1 (incluindo o Run 3 com 4 spikes).
- `d2_t1_1080p_run1.json` a `run3.json` e `d2_perf_summary.json`: Bateria completa e limpa de T1 em 1080p (D2).
- `d2_t2_1080p_run1.json` a `run3.json` e `d2_t2_perf_summary.json`: Bateria completa e limpa de T2 em 1080p (D2), com `median_passed_p95: true`.

Todos os arquivos foram verificados contra caminhos locais e dados pessoais, contendo exclusivamente identificadores técnicos de GPU, métricas de simulação e tempos de quadro.

---

## 8. Recomendações e Encerramento

1. **Condições de alimentação em testes (Proposta de Protocolo):** A correlação empírica indica que em hardware móvel a execução em tomada CA com bateria estabilizada evita flutuações severas de desempenho. Recomenda-se registrar como **PROPOSTA DE PROTOCOLO** que medições formais sejam conduzidas preferencialmente em tomada CA e com carga superior a 80%, aguardando validação formal de regras.
2. **Flag `-FailOnWarnings`:** Manter a flag ativa no executor. A investigação comprovou que a falha observada não foi um aviso textual descartável, mas um encerramento anormal com código de exceção `0xc0000005` do driver de vídeo que exigia auditoria.
3. **Estado técnico da T2:** A bateria de desempenho D2 satisfez os critérios formais quantitativos em 1920×1080 na GPU Intel UHD Graphics 620. Contudo, **o marco T2 permanece aberto** até a execução e aceite manual definitivo de `docs/testing/T2_manual_test_protocol.md` pelo proprietário. Não se afirma ausência absoluta de bugs ou encerramento global do marco nesta etapa.
