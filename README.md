# Dawn of Kin

Jogo single-player em 3D isométrico de sobrevivência familiar, construção de assentamento e estratégia em tempo real (RTS), desenvolvido em **Godot 4.7.2** com **GDScript**.

## Estado atual

- **Marco ativo:** T1 — Fundação RTS
- **Subetapa concluída:** T1.0 — Repositório e esqueleto do projeto
- **Renderizador configurado:** `gl_compatibility` (D1 — sujeito a comparação em cena ambiental representativa antes de T7)
- **Motor de física 3D:** `Jolt Physics`

## Requisitos de ambiente

- **Godot Engine:** `4.7.2.stable.official` (Windows 64-bit).
- Se o executável não estiver no `PATH`, defina a variável de ambiente `GODOT_BIN` apontando para o executável da Godot, ou utilize os scripts em `tools/` (que usam o caminho local conhecido como fallback).
- **Git:** 2.55+ (configuração `user.name` e `user.email` recomendada localmente via `git config --local`).

## Estrutura de pastas

```text
Dawn of Kin/
├─ project.godot              # Configuração da engine, camadas 3D, InputMap e avisos GDScript
├─ AGENTS.md                  # Regras permanentes de engenharia
├─ README.md                  # Este arquivo
├─ docs/                      # GDD e planos técnicos
├─ src/
│  ├─ core/                   # Constantes centrais (camadas de colisão e ações de entrada)
│  └─ main/                   # Cena raiz de composição
└─ tools/                     # Scripts PowerShell de execução e validação
```

## Como executar e validar

No PowerShell, a partir da raiz do projeto (`C:\Projetos\Dawn of Kin`):

```powershell
# Validar importação, checagem estática de scripts e inicialização da cena principal
.\tools\validate.ps1

# Executar o jogo em janela (1280x720 por padrão)
.\tools\run_game.ps1

# Executar em janela por tempo limitado (ex.: 300 quadros a 60 FPS = 5 s)
.\tools\run_game.ps1 -FixedFps 60 -QuitAfter 300
```

## Convenções do projeto

- Código-fonte, identificadores, nós, cenas e comentários técnicos em **inglês**.
- Documentação, protocolos de teste e relatórios de progresso em **português**.
- Qualquer aviso (`WARNING`) ou erro (`ERROR` / `SCRIPT ERROR`) emitido pela Godot durante validação é tratado como falha bloqueante.
