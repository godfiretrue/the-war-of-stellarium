# The Final War of Stellarium — Arquitetura

**Atualizado:** 2026-11-21 · [GDD](GDD.md) · [Lore](LORE.md)

## 1. Stack

| | |
|---|---|
| Motor / framework | Godot Engine 4.7.2-stable |
| Linguagem | GDScript, com tipagem estática |
| IA | LimboAI v1.8.1 (GDExtension) |
| Runtime alvo | PC desktop, escala 16:9 fixa 1152×648 |
| Distribuição | PAP; exportação ainda por configurar |

## 2. Estrutura

```text
main_menu.tscn → map.tscn
                   ├── MapView (render e hit-test)
                   ├── ProvinceView × 21
                   ├── Bot (LimboAI + BotController)
                   └── hud.tscn (ordens, recursos, relatório)
```

Autoloads: `Settings`, `Game` (GameState), `TurnManager`. O loop de jogo é orientado por fases e sinais, não por `process` a correr regras a cada frame.

## 3. Mapa de módulos

| Módulo / pasta | Responsabilidade | Usado por |
|---|---|---|
| `scripts/core/game_state.gd` | Fonte de verdade sem referências a nós; filas de ordens, resolução e visibilidade | [turnos](features/turn-resolution/design.md), [combate](features/combat-and-units/design.md), [névoa](features/fog-and-ambush/design.md) |
| `scripts/core/turn_manager.gd` | Máquina de fases e sinais | [turnos](features/turn-resolution/design.md) |
| `scripts/core/combat_resolver.gd`, `save_system.gd`, `loc.gd`, `settings.gd` | Cálculo puro, persistência, localização, preferências | várias |
| `scripts/data/balance.gd` | Tabela central de constantes de tuning | [combate](features/combat-and-units/design.md), [mapa](features/map-and-provinces/design.md) |
| `scripts/data/map_factory.gd`, `world_generator.gd`, `map_state.gd` | Seed → mapa, campos e grafo | [mapa](features/map-and-provinces/design.md) |
| `scripts/data/province_data.gd`, `unit_type.gd`, `unit_catalog.gd` | Recursos de dados; apenas ids e valores | [combate](features/combat-and-units/design.md) |
| `scripts/ai/bot_controller.gd`, `scripts/ai/tasks/` | Decisões do bot; folhas LimboAI apenas orquestram | bot |
| `scripts/map/map_view.gd`, `province_view.gd` | Render, overlays, zoom e focus | mapa |
| `scripts/ui/hud.gd`, `ui_style.gd`, `ui_icon.gd` | HUD e linguagem visual partilhada | HUD |
| `shaders/terrain.gdshader`, `shaders/pixel_water.gdshader` | Biomas, relevo e água só sobre o mar | mapa |

## 4. Convenções transversais

- **Sinais:** `TurnManager` emite mudanças de fase; `Settings` emite `changed` e os ecrãs reconstróem texto em vez de recarregar cena.
- **Configuração:** todos os números jogáveis vivem em `scripts/data/balance.gd`; os nomes das constantes são a ponte para os `Numbers` de cada `design.md`.
- **Dados:** `Resource`/`RefCounted` guardam ids e valores, nunca referências a nós. `MapState` detém o grafo e as consultas de vitória.
- **Persistência:** `SaveSystem` é o único escritor de `user://savegame.json` (JSON atómico, versão 4); `Settings` é o único escritor de `user://settings.cfg`.
- **Aleatoriedade:** o mapa e a resolução usam seeds; os destinos são baralhados por seed para não haver vantagem de facção.
- **Névoa:** nenhum sistema lê `defence_troops()`/`defense_power()` de uma província alheia sem passar por `GameState.visible_troops()`/`visible_defense_power()`; o bot e o HUD partilham o mesmo filtro.
- **Render e UI:** `UiStyle` detém paleta, escala de fonte e estilos; `UiIcon` detém glifos. Não há glifos escritos à mão por ecrã.
- **Input:** ações nomeadas no InputMap e atalhos no HUD; gamepad por implementar.
- **Localização:** todo o texto visível passa por `Loc`, com chave em `pt` e `en`.

## 5. Estrutura de ficheiros

```text
scripts/core/     regras e serviços sem nós
scripts/data/     recursos de config e geração procedural
scripts/ai/       bot e folhas de behaviour tree
scripts/map/      render e hit-test
scripts/ui/       menus, HUD e estilo partilhado
scripts/tools/    verificações headless (worldgen_sweep.gd, balance_sim.gd)
scenes/           árvores de cena autorais
shaders/          shaders canvas
docs/             GDD, lore, notas de funcionalidades (este guia)
```

## 6. Testes e ferramentas

```bash
godot --headless --path . --script res://scripts/tools/worldgen_sweep.gd
godot --headless --path . --script res://scripts/tools/balance_sim.gd
godot --headless --path . --script res://scripts/tools/ambush_check.gd
```

`worldgen_sweep.gd` verifica 24 seeds de geração e terreno (incluindo picos e Terras Altas); `balance_sim.gd` corre 20 partidas AI-vs-AI (`41000..41019`); `ambush_check.gd` verifica visibilidade, bónus de emboscada e consumo da ordem. Falta uma verificação headless de arranque pelo menu principal (Novo Jogo + Continuar) — está como cartão no quadro.

## 7. Riscos técnicos

- A árvore de comportamento ainda não é um recurso `.tres`; está construída em código.
- O planeta do menu principal é pixelado; substituir por um render do campo gerado ou esconder.
- Navegação por gamepad exige vizinhos de foco sem deixar de manter Espaço/M.
