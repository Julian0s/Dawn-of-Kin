# T3.6.2-B3.1 — Preparação silenciosa da mochila

Base `c5a064058ba50265a7b0add90a8772ef5f9cc122`, branch `feat/t3-6-2-provenance-transactions`. Implementação e testes em `f29a7d1bf113ed4d5dd23e7d6d01ee1a3311ccca`.

`_prepare_provenance_add` valida identidade, peso, capacidade, operação e balanço; devolve plano destacado com snapshot de base, quantidades candidatas e histórico completo do ledger, sem mutação ou sinal. `_apply_prepared_provenance_add` exige guardas internos, compara base e capacidade atuais, reconstrói o plano e ledger, recusa alteração ou reutilização, e atualiza os estados sem emitir sinal. `add_with_provenance` mantém sua assinatura e usa os dois métodos internamente, mantendo a guarda de reentrância durante a notificação após aplicação. A simulação de coordenador nos testes manipula guardas internos para verificar a aplicação silenciosa: ela não é uma API pública de coordenação pronta.

Os testes comparam snapshots e sinais antes/depois, incluindo preparação inválida, recusa sem guarda, aplicação e reaplicação, conflito de operação e conservação. Nenhuma transação com ResourceSource foi implementada. A futura coordenação deve definir aquisição, publicação de sinais e tratamento de falhas entre participantes; não se deve interpretar a aplicação silenciosa isolada como transação econômica completa. GDScript não oferece privacidade forte: os nomes e guardas internos são convenções de engenharia e não são barreira contra código que altera deliberadamente campos internos.

## Resultados

- `tools/run_tests.ps1 -Filter t3_6_2_b2_carry_binding`: 4/4 testes, 53 asserções, sem falhas.
- `tools/validate.ps1`: 127 scripts, zero erros e avisos; inicialização headless aprovada.
- `tools/run_tests.ps1 -Segmented`: 44 suítes, 297/297 testes, 13.159 asserções, zero falhas ou erros de suíte; 44 descobertas e executadas uma vez, sem duplicações ou omissões.
- `git diff --check`: aprovado.

Sem mudanças em ResourceSource, ordens, canteiros, cenas ou HUD; proveniência permanece opt-in. Não houve teste gráfico. A publicação e integração com fonte pertencem a incremento posterior, sujeito a auditoria.
