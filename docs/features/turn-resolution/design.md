# Resolução de turnos e ordens

**Status:** implemented · **Updated:** 2026-11-21 · [GDD](../../GDD.md)

O jogador e o bot escrevem ordens sem ver as do adversário; só depois é que o tabuleiro muda. Isto serve o pilar "Simultaneidade sem vantagem": a frente é decidida por planeamento e terreno, não por quem carrega primeiro.

## Rules

1. As fases são `PLAYER_PLANNING` → `BOT_PLANNING` → `RESOLUTION` → `NEXT_TURN` → `PLAYER_PLANNING`. `TurnManager` detém a máquina de estados e emite sinais; nunca chama o bot ou o HUD diretamente.
2. Marchar e recrutar apenas validam e guardam dicionários de ordens. `GameState.resolve_turn()` é o único mutador de donos e guarnições.
3. Na resolução, um snapshot anterior a qualquer ordem congela o tabuleiro. Recrutamentos juntam-se primeiro à guarnição e defendem, mas não podem marchar no mesmo turno.
4. Todos os exércitos partem ao mesmo tempo; o contingente não destacado fica como defesa da origem.
5. Os destinos são resolvidos por ordem baralhada com seed, nunca por ordem de facção.
6. A defesa é a guarnição do snapshot mais milícia e reforços amigáveis chegados nesse turno. Províncias sem defesa caem sem luta; dois exércitos no mesmo destino ou uma troca de províncias geram batalha de campo numa província de planície descartável.
7. Os sobreviventes regressam à origem apenas se a sua facção ainda a possuir depois de todas as capturas.
8. Vitória: possuir todas as províncias, ou manter 70% das províncias transitáveis por três resoluções consecutivas. Derrota: não possuir nenhuma. Ver [vitória dinâmica](dynamic-victory/design.md).
9. Bot e jogador usam a mesma API pública (`queue_move`, `queue_recruit`, `cancel_order`); o bot nunca lê a fila do jogador.

## Numbers

| Nome | Valor | Unidade | Observação |
|---|---|---|---|
| Províncias por seed | 21 | províncias | âncoras garantidas (capitais e fortalezas), grafo ligado |
| Turnos de agitação pós-conquista | 2 | passos de resolução | sem rendimento e sem recrutamento |
| Duração da penalidade de capital | 3 | turnos | +30% custo de recrutamento, −25% rendimento |
| Milícia por província | 1–2 | tropas | até 4 na capital; regenera 1/turno |
| Tropas deixadas pelo bot | 1 / 2 / 3 | tropas | interior / fronteira / capital |

## Edge cases

- Várias marchas amigáveis a partir da mesma origem são permitidas; no máximo um ataque.
- Recursos de recrutamento são reservados ao colocar a ordem e reembolsados pelos valores guardados, pelo que uma mudança de preço não cria lucro ao cancelar.
- Perder a capital não é derrota imediata; a recrutamento continua possível a partir de qualquer cidade possuída.
- Uma província recém-conquistada com milícia neutral mantém essa milícia durante a regeneração.

## History

- 2026-11-21: documentado a partir do código e do lore.
