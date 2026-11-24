# Combate e unidades

**Status:** implemented · **Updated:** 2026-11-21 · [GDD](../../GDD.md)

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

## Numbers

| Nome | Valor | Unidade | Observação |
|---|---|---|---|
| Multiplicador de defesa: planície / floresta / costa / montanha | 1,0 / 1,15 / 1,0 / 1,35 | × | `Balance.TERRAIN_DEFENSE` |
| Bónus de fortaleza | +0,25 | × | soma ao multiplicador de terreno |
| Poder da milícia | 4 | por tropa | antes do terreno |
| Fator aleatório | 0,9–1,1 | × | `COMBAT_RANDOM_MIN/MAX` |
| Fator de baixas atacante / defensor | 0,7 / 1,0 | × | `ATTACKER_LOSS_FACTOR` / `DEFENDER_LOSS_FACTOR` |
| Espadachins humanos | 5 atk / 5 def | 24 ouro, 5 manpower, 2 manutenção | `human_swordsmen` |
| Besteiros humanos | 7 atk / 3 def | 30 ouro, 6 manpower, 3 manutenção | `human_crossbowmen` |
| Javali mecânico élfico | 6 atk / 7 def | 30 ouro, 6 manpower, 3 manutenção | `elf_boar` |
| Fuzileiros élficos | 8 atk / 4 def | 36 ouro, 8 manpower, 4 manutenção | `elf_riflemen` |
| Divisor / expoente de manutenção | 15 / 1,2 | — | `UPKEEP_COST_DIVISOR` / `UPKEEP_EXPONENT` |

## Edge cases

- Exército atacante vazio não gera batalha.
- Duas facções que chegam à mesma província sem defesa, ou que trocam províncias, lutam numa província temporária de planície.
- As unidades de cerco do lore (catapulta arcana, obus móvel) são `idea`: hoje não existem, e fortalezas apenas somam +0,25 à defesa.

## Open questions

- [ASSUMPTION] Manter os quatro tipos de unidade atuais até o cartão de cerco ser implementado.

## History

- 2026-11-21: documentado a partir de `balance.gd` e `combat_resolver.gd`.
