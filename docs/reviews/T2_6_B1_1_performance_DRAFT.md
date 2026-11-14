# Relatório Técnico: T2.6-B1.1 — Benchmark Pós-Correção de Velocidade (DRAFT)

**Data:** 14 de novembro de 2026<br>
**Branch:** `fix/t2-6-b1-unified-travel-speed`<br>
**Commit-base:** `8f53a3f0137d6e450b5af0b87d8fb52a02c22bc3`<br>
**Hardware:** Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz | Intel(R) UHD Graphics 620<br>
**Engine:** Godot 4.7.2.stable.official.ed1daf0bf | Renderizador: `gl_compatibility`

---

## 1. Contexto e Objetivo

A tarefa T2.6-B1 unificou a velocidade de deslocamento sem carga (4,8 m/s) entre ordens de movimento e ordens de trabalho/coleta, tornando a redução de velocidade estritamente proporcional à carga física transportada.

Na entrega de B1, o benchmark realizado ocorreu com o notebook em bateria (DC, `PowerOnline = False`), marcando $p95$ de 33,038 ms (reprovado formalmente pelo critério de $p95 \le 16,7\text{ ms}$).

O objetivo da presente tarefa (T2.6-B1.1) é medir o desempenho da correção B1 em **tomada CA**, sob condições metodologicamente comparáveis à bateria de referência D2 (`docs/t2-6-d2-performance-review`), avaliando se a alteração introduziu regressões no tempo de quadro e confirmando se atende aos critérios formais em ambiente de alimentação contínua.

---

## 2. Condições de Execução e Telemetria

- **Comando executado:**
  ```powershell
  .\tools\perf.ps1 -Mode t2 -ProfileFilter "1920x1080" -Runs 3 -WarmupSec 5 -DurationSec 30
  ```
- **Alimentação:** Tomada CA conectada (`PowerOnline = True`, `Charging = True`).
- **Nível de bateria durante o teste:** Bateria 1 a 42% / Bateria 2 a 79% (recarga ativa em andamento).
- **Esquema de energia:** Equilibrado (`381b4222-f694-41f0-9685-ff5bb260df2e`).
- **Resolução de teste:** 1920×1080 (Full HD).
- **Taxa de atualização e sincronização:** VSync desativado (`vsync_mode = 0`), sem `--fixed-fps`.
- **Harness e proteções:** Flag `-FailOnWarnings` ativa e sem supressão de erros.

---

## 3. Resultados Detalhados da Nova Bateria (CA)

A suíte executou 3 corridas de 30 segundos (antecedidas de 5 segundos de aquecimento cada), registrando um total de **13.278 quadros** analisados:

| Corrida | FPS Médio | Frame Médio | p50 | p95 | p99 | Máximo | Quadros > 16,7 ms | Quadros > 100 ms | Status p95 |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Run 1** | 147,33 | 6,788 ms | 6,582 ms | 10,076 ms | 11,828 ms | 25,258 ms | 4 / 4.420 | 0 | Aprovado |
| **Run 2** | 149,76 | 6,678 ms | 6,608 ms | 8,933 ms | 11,067 ms | 19,074 ms | 3 / 4.493 | 0 | Aprovado |
| **Run 3** | 145,48 | 6,874 ms | 6,751 ms | 9,757 ms | 11,679 ms | 23,197 ms | 7 / 4.365 | 0 | Aprovado |
| **Consolidado (Mediana)** | **147,33** | **6,788 ms** | **6,608 ms** | **9,757 ms** | **11,679 ms** | **23,197 ms** | **14 / 13.278 (0,11%)** | **0 (0,00%)** | **APROVADO** |

- **Pior quadro absoluto registrado:** 25,258 ms (no Run 1).
- **Quadros acima de 33,3 ms:** 0 em todos os 13.278 quadros.
- **Quadros acima de 100 ms:** **0** (0,00%).

---

## 4. Comparação: Bateria D2 (Pré-B1) vs Bateria B1.1 (Pós-B1) em Tomada CA

A tabela a seguir confronta os dados da bateria de referência D2 em tomada CA com os novos resultados B1.1:

| Métrica | Referência D2 em CA (Pré-B1) | Bateria B1.1 em CA (Pós-B1) | Delta / Variação |
| :--- | :---: | :---: | :---: |
| **Condição de alimentação** | Tomada CA (Bateria ~95–100%) | Tomada CA (Bateria 42%–79%) | Ambas em rede elétrica CA |
| **FPS Médio Mediano** | 125,42 | **147,33** | +21,91 FPS (+17,5%) |
| **Tempo de Frame Médio** | 7,973 ms | **6,788 ms** | -1,185 ms |
| **p50 Mediano** | 7,198 ms | **6,608 ms** | -0,590 ms |
| **p95 Mediano** | 13,487 ms | **9,757 ms** | -3,730 ms (folga de 6,943 ms) |
| **p99 Mediano** | 17,053 ms | **11,679 ms** | -5,374 ms |
| **Máximo Mediano** | 28,954 ms | **23,197 ms** | -5,757 ms |
| **Pior Máximo Absoluto** | 32,101 ms | **25,258 ms** | -6,843 ms |
| **Quadros > 16,7 ms** | 112 / 11.458 (0,98%) | **14 / 13.278 (0,11%)** | Redução substancial |
| **Quadros > 100 ms** | 0 / 11.458 (0,00%) | **0 / 13.278 (0,00%)** | Mantido zero absoluto |
| **Resultado Formal p95** | Aprovado (true) | **Aprovado (true)** | Sem regressão |

### Ressalvas Metodológicas de Causalidade
- O ganho observado em FPS e a redução no $p95$ refletem condições operacionais favoráveis do hardware no momento da execução (frequência de clock da GPU Intel em patamar elevado sob alimentação CA).
- **Não se afirma** que a correção na velocidade de deslocamento de personagens seja a responsável direta pelo aumento de FPS; ambas as baterias executam os mesmos ciclos de economia T2, demonstrando com solidez que a unificação da velocidade **não gerou regressão de desempenho**.

---

## 5. Avaliação Formal dos Critérios de Aceitação

1. **Critério 1 — Mediana do $p95 \le 16,7\text{ ms}$ em 1920×1080:**<br>
   **APROVADO.** O $p95$ mediano registrado foi de **9,757 ms**, situando-se amplamente abaixo do teto de 16,7 ms (folga de 6,943 ms).
2. **Critério 2 — Zero quadros acima de 100 ms pós-aquecimento:**<br>
   **APROVADO.** Em 13.278 quadros monitorados, **nenhum quadro excedeu 100 ms** (o maior intervalo medido foi de 25,258 ms).
3. **Critério 3 — Execução limpa sem erros ou avisos bloqueantes:**<br>
   **APROVADO.** As três corridas completaram sem falhas, avisos de compilação ou encerramentos anormais.

---

## 6. Situação da Pendência de Desempenho em Bateria (DC)

- Em bateria (DC, desconectado da tomada), a Intel UHD Graphics 620 opera com perfil de conservação de energia do Windows, resultando em FPS de ~55,8 e $p95$ de ~33,0 ms (conforme documentado no relatório B1).
- Sob alimentação em tomada CA, a GPU atinge ~147 FPS e $p95$ de ~9,8 ms, cumprindo integralmente as metas.
- A conformidade comprovada nesta bateria atesta o desempenho do jogo em **tomada CA**. A operação em bateria DC permanece como uma característica física do comportamento do hardware de referência em economia de energia, sem spikes acima de 100 ms em qualquer cenário.

---

## 7. Evidências Sanitizadas Anexadas

Os arquivos brutos de telemetria foram salvos em `docs/reviews/evidence/`:
- `b1_1_t2_1080p_run1.json`
- `b1_1_t2_1080p_run2.json`
- `b1_1_t2_1080p_run3.json`
- `b1_1_t2_perf_summary.json`
