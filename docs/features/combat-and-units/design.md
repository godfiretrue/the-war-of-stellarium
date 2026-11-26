# Combate e unidades

**Status:** implemented · **Updated:** 2026-11-25 · [GDD](../../GDD.md)

O combate é numérico: o jogador escolhe que tropas destacar e o resultado depende do efetivo, do tipo de unidade, do terreno e da milícia defensora. Isto serve o pilar "O terreno decide" — atacar uma montanha fortificada sem cerco é caro.

## Rules

1. Ataque = soma de `attack × contagem` das unidades destacadas; defesa = soma de `defense × contagem` da guarnição mais `milícia × 4`, multiplicada pelo terreno e por +0,25 se a província for fortaleza.
2. Ambos os lados recebem um fator aleatório entre 0,9 e 1,1, com seed controlada no simulador.
3. `ratio = ataque / (ataque + defesa)`. O atacante perde `ceil(tropas_atacantes × (1 − ratio) × 0,7)`; o defensor perde `ceil(tropas_defensoras × ratio × 1,0)`.
4. A milícia sofre as baixas primeiro; só depois a guarnição profissional. Baixas de milícia não passam para o atacante.
5. Província sem defesa é conquistada sem luta. Um ataque em que restam zero defensores e zero milícia captura a província.
6. Recrutamento só em cidades e castelos (`ProvinceData.is_city`). Humanos pagam 0,7× o custo; Elfos recebem 1,15× de ouro e manpower.
7. Manutenção por exército: `ceil(custo_médio_da_unidade / 15 × tropas ^ 1,2)`.
8. As baixas são distribuídas uma tropa de cada vez, por ordem estável de unidade, para não apagar um tipo inteiro de uma vez.
9. Uma guarnição em **emboscada** (ordem `queue_ambush`) multiplica o seu poder defensivo por 1,5 e as baixas do atacante por 1,25. A emboscada gasta-se no primeiro combate, mesmo que a província resista, e aparece no relatório. Só se pode emboscar em cidades, fortalezas ou terreno defensivo (terras altas, montanhas, floresta). A guarnição não pode receber outra ordem no mesmo turno; se marchar no turno seguinte, a emboscada termina.

## Numbers

| Nome | Valor | Unidade | Observação |
|---|---|---|---|
| Multiplicador de defesa: planície / floresta / costa / montanha / terras altas | 1,0 / 1,15 / 1,0 / 1,35 / 1,5 | × | `Balance.TERRAIN_DEFENSE` |
| Bónus de fortaleza | +0,25 | × | soma ao multiplicador de terreno |
| Poder da milícia | 4 | por tropa | antes do terreno |
| Fator aleatório | 0,9–1,1 | × | `COMBAT_RANDOM_MIN/MAX` |
| Fator de baixas atacante / defensor | 0,7 / 1,0 | × | `ATTACKER_LOSS_FACTOR` / `DEFENDER_LOSS_FACTOR` |
| Bónus defensivo da emboscada | 1,5 | × | `AMBUSH_DEFENSE_MULTIPLIER` |
| Bónus de baixas ao atacante emboscado | 1,25 | × | `AMBUSH_ATTACKER_LOSS_MULTIPLIER` |
| Espadachins humanos (infantaria) | 5 atk / 5 def | 24 ouro, 5 manpower, 2 manutenção | `human_swordsmen` |
| Besteiros humanos (arco) | 7 atk / 3 def | 30 ouro, 6 manpower, 3 manutenção | `human_crossbowmen` |
| Cavaleiros humanos (cavalaria) | 8 atk / 6 def | 34 ouro, 7 manpower, 4 manutenção | `human_knights` |
| Piqueiros humanos (anti-cavalaria) | 5 atk / 8 def | 30 ouro, 6 manpower, 3 manutenção | `human_pikemen` |
| Couraçado humano (armadura) | 8 atk / 9 def | 36 ouro, 9 manpower, 4 manutenção | `human_ironclad` |
| Catapulta arcana humana (cerco) | 9 atk / 3 def | 36 ouro, 8 manpower, 4 manutenção | `human_catapult` |
| Guardas do Bosque élficos (infantaria) | 5 atk / 6 def | 24 ouro, 5 manpower, 2 manutenção | `elf_grove_wardens` |
| Javali mecânico élfico (cavalaria) | 6 atk / 7 def | 30 ouro, 6 manpower, 3 manutenção | `elf_boar` |
| Lanceiros Espinhosos élficos (anti-cavalaria) | 6 atk / 8 def | 36 ouro, 7 manpower, 4 manutenção | `elf_thorn_lancers` |
| Fuzileiros élficos (arco) | 8 atk / 4 def | 36 ouro, 8 manpower, 4 manutenção | `elf_riflemen` |
| Guarda de Ferro élfica (armadura) | 7 atk / 9 def | 36 ouro, 9 manpower, 4 manutenção | `elf_iron_guard` |
| Obus Móvel élfico (cerco) | 9 atk / 3 def | 36 ouro, 8 manpower, 4 manutenção | `elf_howitzer` |
| Bónus de contra-ataque por função | +25% no ciclo infantaria → cerco → armadura → cavalaria → arco → infantaria; +30% anti-cavalaria contra cavalaria | Proporção da guarnição inimiga com a função contra-atacada | `COUNTER_BONUS`, `ANTI_CAVALRY_BONUS`, `COUNTERS` |
| Cerco | Reduz o bónus de fortaleza (+0,25) até 0,15 conforme a proporção de tropas de cerco; +25% de ataque em fortalezas e Highlands | `role: siege` | `SIEGE_FORTRESS_REDUCTION`, `SIEGE_ATTACK_BONUS` |
| Divisor / expoente de manutenção | 15 / 1,2 | — | `UPKEEP_COST_DIVISOR` / `UPKEEP_EXPONENT` |

## Previsão de batalha

Durante o modo marcha, passar o rato sobre uma província vizinha mostra uma previsão antes de confirmar a ordem. `CombatResolver.predict()` é puro: não tira números aleatórios e não altera a província. Calcula três pontos com a mesma fórmula do combate: `expected` (ambos os fatores 1,0), `best` (ataque 1,1 / defesa 0,9) e `worst` (ataque 0,9 / defesa 1,1). O painel mostra poder, baixas esperadas, o intervalo entre os dois extremos e se a captura é provável. Como as baixas usam `ceil`, os extremos podem trocar de ordem; a interface usa sempre o menor e o maior valor.

A previsão respeita a névoa: se a guarnição defensora não estiver visível para o jogador, o painel mostra apenas "sem informação" em vez de revelar o efetivo através do cálculo. O painel não envia ordens nem bloqueia cliques no mapa.

## Edge cases

- Exército atacante vazio não gera batalha.
- Duas facções que chegam à mesma província sem defesa, ou que trocam províncias, lutam numa província temporária de planície.

## History

- 2026-11-21: documentado a partir de `balance.gd` e `combat_resolver.gd`.
- 2026-11-25: rosário alargado para 12 unidades (6 por facção), com funções, ciclo de contra-ataques, cerco e paginação no HUD; previsão de batalha acrescentada.
