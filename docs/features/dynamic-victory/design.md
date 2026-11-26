# Vitória dinâmica

**Status:** implemented · **Updated:** 2026-11-25 · [GDD](../../GDD.md)

A conquista total ainda vence, mas deixou de ser o único fim: um exército que domina o mapa de forma sustentada também vence. Isto dá um objetivo legível durante o meio de jogo, sem introduzir heróis, moral, eventos de Apocalipse ou diplomacia.

## Rules

1. Após cada resolução, `GameState.advance_turn_state()` compara a parte das províncias transitáveis possuídas por cada facção com o limiar. Quem atinge ou ultrapassa o limiar soma 1 ao seu `domination_streak`; quem fica abaixo reinicia a 0.
2. Picos intransponíveis não contam nem como território possuído nem no total, para que o limiar não dependa da sorte da geração.
3. `TurnManager._check_game_over()` continua a ser o único decisor do fim: eliminação primeiro, conquista total depois, e só então a sequência de domínio. A sequência não altera owners nem guarnições.
4. O HUD lê `GameState.domination_progress()` e mostra percentagem e sequência; a névoa não é afetada porque o cálculo usa apenas o estado real do mapa.
5. O contador é guardado no save. Um save v7 migrado começa com sequência 0 para ambas as facções.

## Numbers

| Nome | Valor | Unidade | Observação |
|---|---|---|---|
| Limiar de domínio | 70% | províncias transitáveis | arredondado para cima ao contar províncias |
| Sequência necessária | 3 | resoluções consecutivas | perder o limiar zera a sequência |
| Versão do save | 8 | — | v7 recebe `domination_streak = 0`; v6 continua recusado |

## Edge cases

- Duas facções não podem atingir o limiar ao mesmo tempo, porque 70% é superior a metade do mapa.
- Uma facção pode ser eliminada no mesmo turno em que a outra atinge a sequência; a eliminação tem precedência.
- Continuar um save v7 não herda uma sequência antiga: o contador recomeça, mas o mapa e os estoques são preservados.

## History

- 2026-11-25: documentado a partir de `balance.gd`, `game_state.gd`, `turn_manager.gd` e `save_system.gd`.
