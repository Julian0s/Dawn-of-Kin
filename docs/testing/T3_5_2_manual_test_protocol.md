# T3.5.2 — Protocolo manual do inspetor

Status: **7/7 aprovados pelo proprietário em 17/11/2026, sem observações**, conforme declaração nesta conversa. Candidata: `cae9ea7115678189c8abc7397660dc6eca10db53`. Os testes manuais e a avaliação visual foram declarados pelo proprietário; o Codex não realizou essas verificações. Hardware, alimentação e resoluções efetivas não foram informados.

1. **INS-01 — Seleção e layout:** criar um canteiro e clicar sobre ele. Verificar nome, estado, progresso e ausência de painel temporário duplicado. Selecionar uma unidade ou terreno vazio e verificar fechamento. Repetir em 1280×720 e 1920×1080 com catálogo e estoque.
   Resultado: [x] Aprovado  [ ] Reprovado. Observações: Nenhuma.
2. **INS-02 — Materiais e trabalhadores:** atribuir trabalhadores e observar papéis, limite de construtores, reserva, transporte, buffer, materiais incorporados, déficit e progresso enquanto a obra avança.
   Resultado: [x] Aprovado  [ ] Reprovado. Observações: Nenhuma.
3. **INS-03 — Sem déficit:** conferir que não há botão de complemento quando a reserva está íntegra. Abrir e fechar o inspetor sem modificar o estoque.
   Resultado: [x] Aprovado  [ ] Reprovado. Observações: Nenhuma.
4. **INS-04 — Déficit sem estoque:** após perda por deterioração de madeira reservada, abrir Complementar materiais e verificar déficit, estoque livre, proposta e saldo remanescente; conferir que a confirmação integral fica desabilitada se o estoque for insuficiente. Pedra bruta não deve sofrer deterioração temporal.
   Resultado: [x] Aprovado  [ ] Reprovado. Observações: Nenhuma.
5. **INS-05 — Complementação integral:** com estoque livre suficiente, confirmar explicitamente. Verificar que os materiais continuam nas pilhas reservadas, o buffer e progresso não aumentam imediatamente, o transporte físico ocorre e a obra retoma sem segundo consumo. Conferir preservação de reservas de outra obra.
   Resultado: [x] Aprovado  [ ] Reprovado. Observações: Nenhuma.
6. **INS-06 — Segurança da interface:** trocar o canteiro durante a confirmação, testar clique duplo e clicar no painel. Não deve ocorrer reserva não solicitada, seleção ou ordem RTS através da interface; Esc/RMB do posicionamento e F6/F7/F8 continuam funcionando.
   Resultado: [x] Aprovado  [ ] Reprovado. Observações: Nenhuma.
7. **INS-07 — Conclusão:** ao concluir, conferir que o inspetor fecha e não mantém dados do canteiro removido.
   Resultado: [x] Aprovado  [ ] Reprovado. Observações: Nenhuma.


Não há opção de reserva parcial nesta candidata; a única ação oferecida exige cobertura integral.
