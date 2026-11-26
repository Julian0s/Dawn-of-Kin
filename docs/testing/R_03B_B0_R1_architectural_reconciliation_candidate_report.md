# Dawn of Kin — Relatório Focal de Reconciliação Arquitetural `R-03B B0-R1`
## Incorporação das Decisões `B0-Q01`–`B0-Q07` e Correção dos Achados `B0-A01`–`B0-A05`

> **Status Obrigatório:** **`CANDIDATA DOCUMENTAL B0-R1 AGUARDANDO AUDITORIA INDEPENDENTE`** · **`B0-R1 NÃO HOMOLOGADO`** · **`R-03B NÃO IMPLEMENTADA`** · **`B1–B4 BLOQUEADAS`**
>
> **Data:** `26/11/2026`
>
> **SHA Base Auditado (`B0`):** `e5024909fbb17cd5266d30e0452e92cc095d5923`
>
> **Nota de Transparência:** Esta revisão é **exclusivamente documental**. Nenhum código de produção, cena, recurso `.tres`, teste executável, configuração ou documento normativo vigente foi alterado, e nenhum teste Godot ou benchmark foi executado.

---

## 1. Autorização e Objetivo de `B0-R1`

Em `26/11/2026`, o proprietário deliberou sobre todas as sete questões abertas da candidata `B0` (`B0-Q01`–`B0-Q07`, sem observações individuais ou gerais adicionais) e autorizou exclusivamente a revisão documental **`R-03B B0-R1`** para:
1. Incorporar integralmente as sete decisões homologadas pelo proprietário.
2. Corrigir os cinco achados da auditoria independente (`B0-A01`–`B0-A05`).
3. Reconciliar transversalmente plano arquitetural, relatório de entrega, diagramas, contratos, tabela de transições, matriz de testes, subdivisão `B1`–`B4` e roteiro humano `HB-01`–`HB-08`.
4. Publicar a nova candidata documental na branch existente `feat/r-03b-founding-house-control-mode` para nova auditoria independente do ChatGPT.

---

## 2. Registro das Sete Decisões Homologadas pelo Proprietário (`26/11/2026`)

| ID | Recomendação Original (`B0`) | Escolha do Proprietário | Decisão Definitiva Incorporada em `B0-R1` |
|---|---|---|---|
| **`B0-Q01`** | Alt. A | **Alt. A** | Moradores comuns selecionáveis para inspeção somente leitura (nome, mochila, estado, tarefa comunitária), sem controle pessoal; `BABY` permanece não selecionável nem comandável. |
| **`B0-Q02`** | Alt. A | **Alt. A** | Seleções mistas executam ordens pessoais exclusivamente nos membros aptos da Casa Fundadora, com filtragem pré-planejamento (`GroupMovePlanner`, vagas, admissão econômica e `DestinationMarker`) e preservação das ordens das unidades excluídas. |
| **`B0-Q03`** | Alt. A | **Alt. B** *(alterada)* | `Worker3` e `Worker4` (`TemporaryTestWorkersController`) classificados como moradores comuns temporários (`COMMUNITY`, `NONE`, `ADULT`), mantendo caráter transitório de ferramenta de desenvolvimento e reconciliando os testes legados afetados em `B1` sem enfraquecer contratos. |
| **`B0-Q04`** | Alt. A | **Alt. A** | Intervalo `D-05` aplicado somente após `MoveOrder` pessoal concluída com `SUCCEEDED` (nunca em `FAILED`, `CANCELLED`, movimento parcial sem sucesso ou recusa na admissão). |
| **`B0-Q05`** | Alt. A | **Alt. B** *(alterada)* | Retorno automático permitido inclusive à mesma tarefa comunitária ainda autorizada (`PENDING_WORKERS`), desde que não `CANCELLED` nem `BLOCKED_REAUTHORIZATION`, preservando o invariante de que `D-05` regula apenas a disponibilidade da unidade e reconciliando os testes afetados em `B3`. |
| **`B0-Q06`** | Alt. A | **Alt. A** | Calibração experimental de `3 s`, `8 s` e `15 s` em tempo de simulação pausável (`PROCESS_MODE_PAUSABLE`), com `0 s` apenas técnico para testes determinísticos e padrão definitivo aberto até `B4`. |
| **`B0-Q07`** | Alt. A | **Alt. A** | Rótulo textual discreto de controle e feedback breve de rejeição na HUD transitória (`use_d2_2_hud = false`), sem cronômetro regressivo, sem polling e sem redesenho. |

---

## 3. Correções dos Cinco Achados da Auditoria Independente (`B0-A01`–`B0-A05`)

### 3.1 `B0-A01` — Permissões das Crianças (`DEC-04` / `GDD v1.3` §§3.3–3.4)
- **Achado:** O resumo da candidata `B0` afirmava indevidamente que `BABY` e `CHILD` não executavam trabalho produtivo nem ordens pessoais diretas, contradizendo o GDD `v1.3` e a própria tabela do plano.
- **Correção:** Reconciliados integralmente o plano (`§§5.1, 9.2, 10.1–10.2, 26.3 B02, 27, 28, 30`) e ambos os relatórios. `BABY` permanece não selecionável nem comandável; **`CHILD`** executa tarefas leves e seguras (`GATHER_FOOD`) em trabalho comunitário (Fundadora e Comum) e, quando membro da Casa Fundadora, recebe ordens pessoais compatíveis (`MOVE`, `GATHER_FOOD`, `DELIVER_TO_CAMP`), mantendo proibidos corte de árvores, mineração de pedra, construção pesada e combate.

### 3.2 `B0-A02` — Barreira de Autoridade e Origem das Ordens
- **Achado:** A proposta anterior concentrava a barreira de permissão em `CommandController` com `Unit.issue_order(order, origin = PERSONAL)`, deixando potencial brecha de contorno via chamada direta a `Unit` ou falsificação de origem.
- **Auditoria do código real:** Mapeadas todas as chamadas em `src/` (apenas 4 `issue_order`: `command_controller.gd:174,273,359` e `cancellation_recovery_dispatcher.gd:111`; 2 `cancel_current_order`: `community_task_dispatcher.gd:234` e `temporary_test_workers_controller.gd:183`) e os 43 arquivos em `tests/` (`36` usam apenas `LeaderA`/`LeaderB`, `3` usam `CharacterDefinition.new()`, `4` envolvem `Worker3`/`Worker4`, `0` emitem `RecoveryOrder` ou `null` diretamente).
- **Correção (`§§7, 8.1–8.3, 10.1, 12.2, 13, 26.1, 26.3 A05, 29`):** Validação `UnitControlPermissions` obrigatória **no próprio ponto de instalação em `Unit`**, com entradas explícitas separadas (`issue_personal_order`/`issue_order`, `issue_community_order`, `issue_recovery_order`), validação estrita `(tipo da ordem × OrderOrigin × estado atual)` e **proibição expressa de qualquer parâmetro de bypass genérico**. Separação das entradas comunitária e de recuperação antecipada para **`B1`** para impedir estados intermediários quebrados.

### 3.3 `B0-A03` — Recuperação Econômica Durante Construção Legada (`P-REC-1`)
- **Achado:** A transição `T1` do plano `B0` exigia unidade ociosa (`IDLE`, sem ordem), omitindo o caminho real em `src/units/cancellation_recovery_dispatcher.gd:85–122`, que substitui legitimamente uma `ConstructOrder` ativa associada ao mesmo `record.site_id` em `SiteState.CANCELLED`.
- **Correção (`§§5.1, 7, 8.3, 11.1, 12.3, 13, 20, 26.3 E01, 28 HB-07`):** Mantidos os 4 estados canônicos de `ControlMode` combinados a `active_origin: OrderOrigin` (`SYSTEM_RECOVERY`) e formalizadas as transições **`T1a`** (unidade ociosa com custódia), **`T1b`** (substituição estrita de `ConstructOrder` do mesmo `site_id` em `SiteState.CANCELLED`, mesmo a partir de `PERSONAL_ACTIVE`) e **`T1c`** (recuperação explicitamente solicitada `explicit == true` em espera `D-05`). Recuperação automática (`explicit == false`) nunca sequestra ordem pessoal ativa nem ignora `entry.manual = true`, e expiração de `D-05` nunca reativa recuperação interrompida manualmente. Adicionados 11 casos de teste futuros (`E01`).

### 3.4 `B0-A04` — Reentrância Síncrona e Atomicidade das Transições
- **Achado:** A introdução do novo sinal `control_mode_changed` sobre caminhos já sensíveis a callbacks síncronos (`Unit.issue_order()`, `cancel_current_order()`, `_set_state()`, `_exit_tree()`) poderia reintroduzir corrupção por reentrância ou prometer rollback irreal de ordens já canceladas.
- **Correção (`§§13, 14.1–14.5, 23, 25, 26.3 C02`):** Especificado protocolo atômico de 4 estágios: (0) admissão pura sem mutação; (1) reserva interna silenciosa na `issued_revision` (sem emitir `control_mode_changed` ainda); (2) cancelamento seguro de `previous_order` com guarda para recusa por lock transacional e revalidação de `_order_revision`; (3) instalação e `order.start()` com revalidação; (4) estabilização final e publicação única de `control_mode_changed`. Formalizada a semântica explícita de `issue_order(null)` e `cancel_current_order()`, removida qualquer promessa de rollback de ordem encerrada, e documentados os 11 casos de borda obrigatórios (`C02`).

### 3.5 `B0-A05` — Interface Discreta sem Cronômetro Regressivo
- **Achado:** O relatório original `B0` mencionava contagem de espera na interface, conflitando com `B0-Q07 A` e com a atualização orientada a eventos.
- **Correção (`§§3, 5.2, 7, 22, 24, 26.3 G01, 28 HB-03/HB-08` + ambos os relatórios):** Removido integralmente qualquer requisito de cronômetro regressivo, contagem numérica de segundos, barra temporal ou polling na HUD. O `Timer` rege exclusivamente a lógica interna; `SelectedUnitPanel` / `HudFormatter` exibem rótulos textuais discretos orientados a eventos (`Trabalho comunitário`, `Ordem pessoal`, `Aguardando retorno`, `Morador — somente leitura`) e `AutonomousGatherFeedback` exibe feedback breve de rejeição.

---

## 4. Matriz Final de Reconciliação (`B0-Q01`–`B0-Q07` e `B0-A01`–`B0-A05`)

| ID | Problema Original | Decisão ou Correção | Seções Afetadas (`PLAN`) | Verificação Transversal | Estado |
|---|---|---|---|---|---|
| **`B0-Q01`** | Selecionabilidade de moradores comuns | Alt. A: seleção somente leitura (`BABY` bloqueado), sem controle pessoal | §§5.2, 7, 10, 12.2, 21, 22, 26.3, 28, 29, 30 | Coerente em permissões, HUD, testes e `HB-01` | **INCORPORADO (`DECIDIDO`)** |
| **`B0-Q02`** | Seleção mista | Alt. A: filtrar aptos antes de `GroupMovePlanner`, vagas e `DestinationMarker`; preservar excluídas | §§5.2, 7, 10.3, 12.2, 20, 21, 26.3, 27, 28, 29, 30 | Coerente em `CommandController`, `A04` e `HB-02` | **INCORPORADO (`DECIDIDO`)** |
| **`B0-Q03`** | Classificação `Worker3`/`Worker4` | Alt. B: `COMMUNITY`/`NONE`/`ADULT` transitórios + plano de reconciliação dos testes `C4` em `B1` | §§5.2, 7, 9.4, 20, 21, 25, 26.1–26.3, 28, 29, 30 | Zero classificação fundadora de `Worker3`/`Worker4` | **INCORPORADO (`DECIDIDO`)** |
| **`B0-Q04`** | Falha/cancelamento de `MoveOrder` | Alt. A: `D-05` somente após `MoveOrder` `SUCCEEDED` | §§5.2, 12.3, 13, 14.3, 16, 26.3, 27, 28, 29, 30 | Coerente em diagrama, `T0`/`T6a`/`T6b` e `D01` | **INCORPORADO (`DECIDIDO`)** |
| **`B0-Q05`** | Retorno à mesma tarefa | Alt. B: `MoveOrder` não grava `excluded_unit_ids`; retorno à mesma tarefa se `PENDING_WORKERS`; nunca reativa `CANCELLED`/`BLOCKED_REAUTHORIZATION`; reconciliação em `B3` | §§5.2, 13, 15, 16, 19, 21, 23, 25, 26.2–26.3, 27, 28, 29, 30 | Eliminada Alt. A como padrão; invariante `D-05` preservado | **INCORPORADO (`DECIDIDO`)** |
| **`B0-Q06`** | Calibração `D-05` e pausa | Alt. A: `3 s`, `8 s`, `15 s` em tempo simulado pausável (`0 s` apenas técnico); padrão final em `B4` | §§5.2, 6, 16, 17, 21, 23, 26.3, 28, 29, 30 | Conexão única no `Timer` lazy + `PROCESS_MODE_PAUSABLE` | **INCORPORADO (`DECIDIDO`, calibração final em `B4`)** |
| **`B0-Q07`** | Indicação visual transitória | Alt. A: rótulos discretos + feedback breve, sem cronômetro regressivo (`use_d2_2_hud = false`) | §§5.2, 7, 12.2, 22, 24, 26.3, 28, 29, 30 | Coerente com D2.2, `D4-A01` e `B0-A05` | **INCORPORADO (`DECIDIDO`)** |
| **`B0-A01`** | Contradição etária de `CHILD` | `CHILD`: leves/seguras (`GATHER_FOOD`) + pessoais compatíveis na Casa Fundadora; proibidas pesadas/combate | §§5.1, 9.2, 10, 26.3 (`B02`), 27, 28, 30 + relatórios | Zero contradições nos 3 documentos | **CORRIGIDO (AGUARDA AUDITORIA)** |
| **`B0-A02`** | Brecha de contorno em `Unit.issue_order` | Barreira obrigatória na própria `Unit` com entradas explícitas separadas e zero bypass; separado já em `B1` | §§7, 8, 10.1, 12.2, 13, 25, 26.1, 26.3 (`A05`), 27, 29, 30 | Todas as 4 entradas em `src/` e 43 arquivos em `tests/` auditados | **CORRIGIDO (AGUARDA AUDITORIA)** |
| **`B0-A03`** | Omissão de `ConstructOrder` cancelada em `T1` | Transições `T1a`/`T1b`/`T1c` + `OrderOrigin.SYSTEM_RECOVERY` + proteção `entry.manual` + 11 testes `E01` | §§5.1, 7, 8.3, 11.1, 12.3, 13, 20, 25, 26.3 (`E01`), 27, 28, 29, 30 | Verificado contra `cancellation_recovery_dispatcher.gd:85–122` | **CORRIGIDO (AGUARDA AUDITORIA)** |
| **`B0-A04`** | Reentrância em `issue_order` e `control_mode_changed` | Protocolo atômico de 4 estágios, publicação após estabilização, guarda de `cancel()` bloqueado, 11 casos `C02` | §§7, 13, 14, 23, 25, 26.3 (`C02`), 27, 29, 30 | Sem promessa irreal de rollback; `issue_order(null)`/`cancel_current_order()` definidos | **CORRIGIDO (AGUARDA AUDITORIA)** |
| **`B0-A05`** | Menção a contagem regressiva na HUD | Removida totalmente de todos os documentos; apenas rótulo discreto orientado a eventos (`G01`) | §§3, 5.2, 7, 22, 24, 25, 26.3 (`G01`), 27, 28, 29, 30 + relatórios | Verificação automatizada de ausência de cronômetro na HUD | **CORRIGIDO (AGUARDA AUDITORIA)** |

---

## 5. Contratos Preservados Integralmente

- `GDD v1.3`, `AGENTS.md`, `ROADMAP_MESTRE.md`, Design System D2.2 (Cláusula Pétrea), `P-REC-1` a `P-REC-4`, `D-ERR-1 B`, `D-ERR-2 C`.
- `R-03A` encerrada (`D0`–`D4`, `D4-R1`, `D4-R2`, `D0-A03`, `D0-A04` com equação canônica fiel sobre 8 compartimentos físicos e 2 perdas legítimas independentes, `D2-A01`, `D3.1-R1`, `D3.2`, `D3.3-R1`, `D4-A01`).
- Flags vigentes na `MainScene`: `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`.
- `HD3-06` preservada como registro histórico legítimo (não reclassificada retroativamente como bug).
- Explicação forense de `CLOSEOUT-DOC-01`/`02`/`03` preservada sem reabrir a `R-03A` nem alterar relatórios históricos.

---

## 6. Testes Futuros Adicionados ao Planejamento (Não Executados)

Expandida a matriz `RED → GREEN` (Plano §26.2–§26.3) com:
- **Permissões e `Worker3`/`Worker4` (`A03`–`A06`, `B01`–`B03`):** inspeção somente leitura, filtragem pré-planejamento em seleção mista, barreira direta em `Unit` contra contorno e falsificação de origem, `Worker3`/`Worker4` como `COMMUNITY` + tabela específica de preservação/reconciliação dos testes legados `Q03 B`, e matriz etária corrigida (`CHILD` `B0-A01`).
- **Reentrância e atomicidade (`C02`):** todos os 11 casos de borda de `B0-A04`.
- **`D-05` e retorno à mesma tarefa (`D01`–`D03`):** 5 casos `B0-Q04 A`, pausa/reutilização do `Timer` (`B0-Q06 A`) e 10 subcenários de retorno à mesma tarefa + reconciliação dos testes `Q05 B`.
- **Recuperação econômica (`E01`):** todos os 11 subcenários de `B0-A03` (`ConstructOrder` cancelada, `site_id`, revisão, `entry.manual`, preservação de carga, `Worker3` comunitário e `RegionalConservationAudit`).
- **Interface discreta (`G01`) e Roteiro Humano (`HB-01`–`HB-08`):** rótulos discretos, ausência de cronômetro regressivo/polling, `720p`/`1080p`, `Worker3`/`Worker4` na `MainScene`, retorno à mesma árvore e calibração `3 s`/`8 s`/`15 s`.

---

## 7. Questões Efetivamente Remanescentes e Limitações

- **Única pendência de produto em aberto (prevista na própria `B0-Q06 A`):** escolha da duração padrão definitiva de `D-05` após a calibração experimental (`3 s`, `8 s`, `15 s`) no aceite humano futuro (`B4`).
- **Nenhuma outra questão material aberta** foi encontrada na reconciliação transversal.
- **Limitações:** etapa estritamente documental (zero execução de testes Godot, benchmarks ou testes humanos; a arquitetura ainda não foi validada por testes executáveis).

---

## 8. Integridade Git e Escopo Documental

- **Branch candidata:** `feat/r-03b-founding-house-control-mode` (worktree `C:\Projetos\Dawn_of_Kin_wt_r_03b`, preservado ativo para revisão).
- **Ancestralidade:** `develop (94c718024359dc7ff8360949313969b3ceaf9776)` → `B0 (e5024909fbb17cd5266d30e0452e92cc095d5923)` → `B0-R1` (exclusivamente os 3 documentos Markdown autorizados em toda a cadeia desde `develop`; `NON_DOC_DIFF_COUNT=0`).
- **Proteções confirmadas:** `develop`, `main` (`25e0a20f1d6a2f10a9e059afe69759fbe263db4a`), tags históricas (`t1-complete`, `t2-complete`, `t3-3-complete`), manifesto original `evidencias\R-03B\B0\MANIFEST_SHA256.txt` e arquivo local `C:\Projetos\Dawn of Kin\project.godot` (`SHA-256 = AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`) permanecem intactos.
- **Evidências próprias de `B0-R1`:** arquivadas e seladas em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B0-R1\MANIFEST_SHA256.txt`.
