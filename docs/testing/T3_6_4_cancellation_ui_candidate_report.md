# T3.6.4 — Candidata da interface D3

Base `08ba6350ad5acfe9e596edcd267c5bea5c464ebd`, na branch `feat/t3-6-3-cancellation-custody`. Main de referência `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`. Godot 4.7.2.

O inspetor contextual da T3.5.2 recebe a ação **Cancelar construção**. A composição exige economia de proveniência admitida, armazenamento físico e despachante regional disponível. A ação é restrita ao canteiro registrado em ACTIVE e é recusada durante transações. A complementação DEC-11B continua no mesmo painel. A fórmula D3 e as transferências continuam nos componentes da T3.6.3.

O clique abre uma prévia somente leitura do coordenador. A interface mostra S, T, B, K, D e M por recurso e avisa que só S fica disponível no commit. Cada intenção tem um ID por instância do painel e uma sequência própria. Selecionar outro alvo, fechar ou voltar descarta a intenção. Confirmar consome a intenção antes de entrar na transação, que compara o plano inteiro com os participantes e revisões atuais. Uma recusa exige nova prévia. Uma troca reentrante de seleção durante o commit preserva a seleção mais recente.

O commit bem-sucedido abre a custódia no mesmo inspetor por ID regional. O botão **Recuperações** reabre a consulta. O seletor mostra as recuperações abertas no domínio e mantém o último cancelamento confirmado acessível. A consulta apresenta A, H, E e D e o diagnóstico disponível. O timer de 0,5 s roda enquanto o acompanhamento está aberto. A referência ao canteiro é descartada ao abrir o acompanhamento. A UI não designa trabalhadores, e a retomada fica a cargo das regras existentes de B1.4.

A suíte usa a MainScene real. Cobre cliques no SubViewport, prévia sem efeitos econômicos, confirmação consumida antes dos callbacks, replay, mudança de seleção/estado, remoção, deterioração, saque após a prévia, montagem parcial, descarga física, interrupção manual e consulta após remover o canteiro. A concorrência da conclusão é verificada pelos estados e pela guarda de transação. O RED inicial teve a falha esperada de ausência da ação, com 3/4 testes e 65 asserções (incluindo os casos herdados de T3.5.2). A suíte final separa os casos T3.6.4 das regressões existentes.

| Execução | Resultado |
| --- | --- |
| Focada T3.6.4 | 6/6 em 1 suíte, 82 asserções |
| Regressão focada T3.5 | 6/6 em 2 suítes, 99 asserções |
| Regressão focada T3.6.3 | 36/36 em 4 suítes, 1.003 asserções |
| Regressão segmentada | 526/526 em 73 suítes, 27.381 asserções, zero falhas, erros de suíte, timeouts, omissões ou duplicatas |
| Validação de scripts | 173 scripts, importação e inicialização headless aprovadas, zero erros ou avisos |
| Whitespace técnico | Aprovado |

No desenvolvimento, uma verificação exigia que o domínio já estivesse vinculado a um armazenamento mesmo antes do primeiro saque. Isso ocultava a ação em canteiros recém-criados. A configuração admitida permite o vínculo inicial pelo coordenador e continua recusando vínculos incompatíveis. O fixture de deterioração passou a exigir que a reserva de madeira realmente diminua antes de tentar a confirmação.

Como o coordenador compara o plano completo, progresso ou suprimento contínuo durante a prévia podem exigir que o jogador espere um intervalo sem alterações para confirmar. Uma custódia sem trabalhador elegível pode permanecer pendente e uma interrupção manual pode permanecer bloqueada. O painel é de acompanhamento, e a designação posterior continua na API interna B1.4.

Arquivos técnicos: quatro scripts de produção (inspetor, MainScene, gerenciador e coordenador), a suíte de integração T3.6.4 e seu UID. Arquivos documentais: este relatório e o protocolo manual.

A validação manual das duas resoluções, câmera e convivência visual dos HUDs aguarda o proprietário. [Protocolo manual](T3_6_4_manual_test_protocol.md).

Commit técnico b32a8ff220a5144a530b7987a210780223bb70e2. As execuções finais não registraram falhas, avisos do Godot, timeouts ou diagnósticos de vazamento. O Git avisou sobre normalização CRLF para LF no teste novo. O diff técnico passou nos checks de whitespace.
