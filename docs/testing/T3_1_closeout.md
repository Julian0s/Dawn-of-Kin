# Dawn of Kin — Registro de Encerramento da Etapa T3.1

**Etapa:** T3.1 — Contabilidade, Reservas e Saque em Lote  
**Data de Aprovação Formal:** 15 de novembro de 2026  
**Decisão do Proprietário:** APROVADA  
**Auditoria Técnica Independente:** ChatGPT (concluída e aprovada em 15/11/2026)  
**Branch de Implementação:** `feature/t3-1-reservations`  
**Commit Técnico Final:** `b05e8e682b686f1a1afb4cc0a1c2accbb20adc82`  
**Base Oficial:** `main`, tag `t2-complete` (`f7c24592e3a6d936dbcb63f648c474280695ab9b`)  

---

## 1. Escopo Aprovado

A etapa T3.1 cobriu exclusivamente a infraestrutura econômica transacional necessária para suporte às futuras obras da T3, sem alterar a autoridade única de estoque do assentamento nem duplicar saldos:
- Distinção clara e mensurável entre estoque físico total, estoque reservado e estoque disponível utilizável ($Q_{\text{disponível}} = Q_{\text{físico}} - Q_{\text{reservado}}$).
- Sistema de reservas atômicas por canteiro (`reservation_id`) ancorado nas pilhas físicas reais do acampamento.
- Saques reservados e saques compostos com atomicidade estrita e rollback sem efeitos colaterais.
- Aplicação da política de deterioração **Alternativa B — Perda Direta** sobre materiais reservados expostos.
- Proteção defensiva e fail-safe para backends sem suporte a snapshot de reversão.
- Preservação integral de compatibilidade com todos os fluxos e invariantes da T2.

---

## 2. Principais Funcionalidades Implementadas

1. **Livro-Razão de Reservas (`PileReservationLedger`):**
   - Rastreamento determinístico por pilha (`_by_pile`) e ordem de criação de reservas (`_reservation_order`).
   - Invariante estrita: $\sum_r \text{reserva}(p, r) \le p.\text{amount}$ verificada em toda mutação.
   - Suporte a alocação, dedução, cancelamento e reconciliação pós-decaimento com snapshots isolados para rollback.

2. **Extensibilidade e Contratos em `SettlementStorageSource`:**
   - Consultas `get_physical_amount()`, `get_reserved_amount()`, `get_available_amount()` e contrato unificado de `get_amount()` refletindo o saldo livre utilizável.
   - Transações em lote: `can_reserve_batch()`, `reserve_batch()`, `release_batch()`, `can_withdraw_batch()`, `withdraw_batch()`, `withdraw_reserved()` e `withdraw_reserved_batch()`.
   - Sinais econômicos: `reservations_changed` e `reservation_lost_to_decay(reservation_id, resource_id, lost_amount)`.
   - Fail-safe defensivo em `withdraw_reserved_batch()`: se o backend não fornecer snapshot válido (`snapshot == null`), a operação é recusada preventivamente antes de qualquer saque físico.

3. **Backend Físico com Pilhas (`GroundPileManager`):**
   - Transações de reserva e saque baseadas em planos de execução pré-validados (`_build_reserve_plan`, `_build_withdraw_plan`, `_build_withdraw_reserved_plan`).
   - Rollback atômico integrado com snapshot de pilhas e do ledger caso ocorra falha no meio do lote.
   - Saque comum impedido de consumir quantidades reservadas por outras obras.
   - Implementação da **Alternativa B — Perda Direta** em `step_decay()`: quando o desgaste físico reduz o saldo de uma pilha abaixo do total reservado, as reservas vinculadas àquela pilha são reduzidas diretamente sem reancoragem automática para outras pilhas, emitindo `reservation_lost_to_decay`.

4. **Fachada Única de Estoque (`SettlementInventory`):**
   - Delegação transparente de consultas e mutações para o backend ativo, sem manter saldos locais concorrentes.
   - Repasse coordenado de eventos e garantia de conservação global de recursos.

5. **Backend em Memória para Testes (`InMemoryStorageSource`):**
   - Suporte completo a reservas, liberação, saque reservado e `_create_rollback_snapshot()` / `_restore_rollback_snapshot()`.

---

## 3. Commits Relevantes

1. `0b8908d` — `docs(t3): record approved storage, worker and decay rules before T3.1` (atualização documental prévia).
2. `81266a9` — `feat(t3.1): add physical reservation accounting, atomic batch withdraw, and direct decay loss` (implementação técnica principal e 15 testes).
3. `736be79` — `fix(t3.1): make withdraw_reserved_batch atomic via snapshot rollback and sync GDD headers` (T3.1-R1: correção de atomicidade em `withdraw_reserved_batch` e teste 15).
4. `b05e8e6` — `fix(t3.1): enforce fail-safe on withdraw_reserved_batch without snapshot and update GDD v1.1 header` (T3.1-R2: proteção defensiva fail-safe, teste 16 e aviso GDD v1.1).

---

## 4. Resumo das Verificações Automatizadas Reportadas

*Nota de governança: os dados abaixo representam execuções automatizadas reportadas pelo Antigravity durante a etapa T3.1-R2 e confrontadas com o repositório, não constituindo execução direta pelo ChatGPT.*

- **Validação de Arquivos e Cena Principal (`tools/validate.ps1`):**
  - Status: `PASSED` (0 erros, 0 avisos, 88 scripts GDScript analisados).
- **Suíte Específica da T3.1 (`tests/unit/test_t3_1_reservations.gd`):**
  - 17/17 testes aprovados, 432 asserções, 0 falhas.
  - Cobertura: reservas simples, compostas, múltiplas obras concorrentes, rejeição atômica por saldo insuficiente, cancelamento parcial/total, saques reservados de pilhas reais, bloqueio de saque comum sobre saldo reservado, falha intermediária com rollback em `withdraw_batch` e `withdraw_reserved_batch`, decaimento Alternativa B sem reancoragem, descarte de pilhas esgotadas, proteção contra IDs duplicados/inválidos, conservação ponta a ponta com ciclo T2, bloqueio de reentrância em sinais e fail-safe sem snapshot.
- **Suíte Segmentada Completa (`tools/run_tests.ps1 -Segmented`):**
  - 28/28 suítes aprovadas em 6 lotes (`unit`, `integration-01` a `integration-05`).
  - 199/199 testes aprovados (182 herdados da T1/T2 + 17 novos da T3.1).
  - 6.899 asserções verificadas.
  - 0 erros, 0 avisos, 0 testes ignorados.
- **Integridade de Formatação Git:**
  - `git diff --check`: 0 erros de formatação ou caracteres inválidos.

---

## 5. Auditoria Técnica e Aprovação Formal

- **Auditoria Técnica Independente:** Realizada pelo **ChatGPT** em 15/11/2026 sobre o branch `feature/t3-1-reservations` (HEAD `b05e8e6`), atestando a correção dos contratos, a robustez do rollback atômico, a consistência contábil e a suficiência da cobertura de testes.
- **Aprovação Formal:** Concedida expressamente pelo **proprietário do projeto** em 15/11/2026, autorizando o encerramento da T3.1.

---

## 6. Limitações Conhecidas

1. **Desempenho em Bateria DC (Intel UHD 620):**
   - Conforme aceito formalmente no encerramento da T2, o hardware sob bateria apresenta mediana de $p95 = 33,038\text{ ms}$ (`55,80 FPS`), enquanto em tomada CA atende à meta formal com $p95 = 9,757\text{ ms}$ (`147,33 FPS`). As medições realizadas na Intel UHD 620 apresentaram resultados diferentes entre alimentação por tomada CA e bateria DC. A causa específica dessa diferença não foi isolada. A limitação em bateria foi aceita pelo proprietário no encerramento da T2. A T3.1 não realizou novo benchmark de desempenho que permita atribuir causalidade.
2. **Saques Reservados em Backends sem Snapshot:**
   - Backends personalizados que não implementem `_create_rollback_snapshot()` nem forneçam sobrescrita própria de `withdraw_reserved_batch()` terão saques compostos rejeitados preventivamente (`fail-safe`), exigindo saques unitários ou implementação do gancho de reversão.

---

## 7. Funcionalidades Deliberadamente Não Implementadas

Em cumprimento estrito ao princípio de desenvolvimento incremental e controle de escopo:
- Não foram criados canteiros de obra (`ConstructionSite`) nem instâncias construídas (`BuildingInstance`).
- Não foi implementada validação de posicionamento espacial no terreno nem prévia visual (escopo da T3.2).
- Não foi implementado transporte físico de materiais por trabalhadores até obras (escopo da T3.3).
- Não foi criada interface gráfica de construção ou catálogo de edifícios (escopo da T3.5).
- Não foram criados depósitos protetores contra deterioração (escopo da T3.7).
- Não foi implementada serialização em disco nem salvamento/carregamento (escopo da T3.8).

---

## 8. Próxima Etapa Planejada

- **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid:**
  - *Status:* **NÃO AUTORIZADA PARA IMPLEMENTAÇÃO.**
  - *Escopo futuro:* Implementação de `PlacementValidator` (checagem de terreno, exclusão da `CampStorageZone` e corredor de navegação), prévia visual sem grid e controle de posicionamento.
  - *Diretriz:* Aguardar autorização específica expressa do proprietário antes de criar ou modificar qualquer código referente à T3.2.
