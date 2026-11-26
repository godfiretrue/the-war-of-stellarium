class_name Loc
extends RefCounted
## Player-facing text in Portuguese and English.
##
## The game keeps its data in English (territory keys, unit ids, save fields);
## this class is the only place where those values become display text. The
## language comes from the Settings autoload, so swapping it re-renders the HUD
## and the menu without restarting.
##
## Keys are snake_case. `t()` returns the key itself when a translation is
## missing, which keeps the game running while making the gap obvious.

static var language := "pt"

const STRINGS := {
	"pt": {
		# --- Common -----------------------------------------------------
		"gold": "Ouro",
		"manpower": "Mão-de-obra",
		"aether": "Éter",
		"iron": "Ferro",
		"turn_badge": "Turno %d · %s",
		"phase_player": "Jogador",
		"phase_elves": "Elfos",
		"phase_resolution": "Resolução",
		"phase_next": "Seguinte",
		"phase_over": "Fim",
		"faction_humans": "Humanos",
		"faction_elves": "Elfos",
		"faction_neutral": "Neutro",
		"terrain_plains": "Planícies",
		"terrain_mountains": "Montanhas",
		"terrain_forest": "Floresta",
		"terrain_coast": "Costa",
		"terrain_highlands": "Terras Altas",
		"territory_highland_stronghold": "Fortaleza das Terras Altas",
		"peak_impassable": "Pico intransponível",
		"ambush": "Emboscada",
		"ambush_active": "Em emboscada",
		"fog_hidden": "Sem informação sobre a guarnição inimiga",
		"fog_unexplored": "Território por explorar",
		"territory_capital_port": "Porto Capital",
		"territory_fortress": "Fortaleza",
		"territory_fortress_pass": "Passo Fortificado",
		"territory_river_town": "Vila Ribeirinha",
		"territory_elven_spire": "Torre Élfica",
		"territory_capital_citadel": "Cidadela Capital",
		"territory_market_town": "Vila de Mercado",
		"territory_port_town": "Vila Portuária",
		"territory_highlands": "Terras Altas",
		"territory_forest_coast": "Costa Florestal",
		"territory_deep_forest": "Floresta Densa",
		"territory_coastline": "Litoral",
		"territory_river_valley": "Vale do Rio",
		"territory_farmlands": "Terras Agrícolas",
		"territory_wilderness": "Ermos",

		# --- Units ------------------------------------------------------
		"unit_human_swordsmen": "Espadachins",
		"unit_human_crossbowmen": "Besteiros",
		"unit_elf_boar": "Javali Mecânico",
		"unit_elf_riflemen": "Mosqueteiros",
		"unit_human_knights": "Cavaleiros",
		"unit_human_pikemen": "Piqueiros",
		"unit_human_ironclad": "Couraçado",
		"unit_human_catapult": "Catapulta Arcana",
		"unit_elf_grove_wardens": "Guardas do Bosque",
		"unit_elf_thorn_lancers": "Lanceiros Espinhosos",
		"unit_elf_iron_guard": "Guarda de Ferro",
		"unit_elf_howitzer": "Obus Móvel",

		# --- HUD: selection ---------------------------------------------
		"select_province": "Selecione uma província no mapa",
		"role_capital": "Capital",
		"role_castle": "Castelo",
		"role_corridor": "Corredor",
		"role_wildland": "Ermos",
		"tip_wildland": "Ermos não têm defesa nem recrutamento; só servem de passagem.",
		"troops": "%d tropas",
		"troops_none": "Sem tropas",
		"militia": "%d milícia",
		"stat_attack": "Atq",
		"stat_defense": "Def",
		"income": "+%d %s",
		"recruit": "+ %s (%d🪙 %d👥)",
		"recruit_short": "+ %s",
		"recruit_page": "%d/%d",
		"tip_recruit_page": "Clica para ver outro par de unidades.",
		"recruit_cost": "Custo: %d ouro · %d mão-de-obra",
		"recruit_city_only": "Só em cidades e castelos",
		"recruit_unrest": "Província em revolta (%d turnos)",
		"unrest": "Revolta %d",
		"recruit_tooltip": "%s\nAtaque %d · Defesa %d · Manutenção %d",
		"recruit_reason_gold": "Falta ouro ou mão-de-obra",
		"capital_penalty": "Capital perdida: +30%% recrutamento, -25%% rendimento (%d turnos)",

		# --- HUD: buttons -----------------------------------------------
		"march": "Marchar",
		"march_troops": "Tropas a marchar",
		"end_turn": "Terminar turno",
		"save": "Gravar",
		"menu": "Menu",
		"options": "Opções",
		"cancel": "Cancelar",
		"orders_title": "Ordens em fila",
		"order_move": "Marchar %s → %s (%d tropas)",
		"order_recruit": "Recrutar %d %s em %s",
		"tip_end_turn": "Terminar o planeamento (Espaço)",
		"tip_march": "Enfileirar uma marcha para uma província vizinha (M)",
		"tip_save": "Gravar o jogo (S) — só no início do turno, sem ordens",
		"tip_menu": "Voltar ao menu principal",
		"tip_options": "Definições: idioma, gráficos e ecrã inteiro",
		"tip_menu_button": "Menu da campanha: gravar, opções e sair",
		"tip_gold": "Ouro: %d\nRendimento: +%d · Manutenção: -%d",
		"tip_manpower": "Mão-de-obra: %d\nRendimento: +%d",
		"tip_resource": "%s: %d\nRendimento: +%d",
		"tip_terrain": "Rendimento base: +%d ouro, +%d mão-de-obra\nDefesa: ×%.2f",
		"tip_ambush": "Esconder a guarnição até o inimigo entrar (A)",
		"ambush_reason_ground": "Só em cidades, fortalezas ou ermos",
		"ambush_reason_troops": "Não há tropas para emboscar",
		"ambush_reason_busy": "Esta província já tem uma ordem",
		"ambush_reason_active": "A guarnição já está em emboscada",
		"order_ambush": "Emboscar tropas em %s",
		"order_short_ambush": "Emboscada",
		"fortress_upkeep": "Fortaleza: -%d ouro/turno",
		"tip_orders_toggle": "Mostrar ou esconder a fila de ordens",
		"tip_orders_collapse": "Recolher a fila de ordens",
		"orders_tab": "Ordens (%d)",
		"orders_tab_empty": "Ordens",
		"orders_empty": "Sem ordens em fila.",
		"order_short_move": "%s → %s",
		"order_short_recruit": "+%d %s",
		"order_count": "%d tropas",
		"order_count_one": "%d tropa",
		"order_hover_tip": "Passa o rato para realçar a ordem no mapa; clica para selecionar a origem.",
		"garrison_title": "Guarnição",
		"garrison_empty": "Sem guarnição",
		"garrison_unit_line": "%s × %d",
		"garrison_militia": "Milícia local × %d",
		"battle_focus_tip": "Clica para centrar o mapa nesta batalha.",
		"reason_no_selection": "Seleciona uma província tua.",
		"reason_not_owned": "A província não é tua.",
		"reason_not_planning": "Aguarda o teu turno de planeamento.",

		# --- HUD: hints -------------------------------------------------
		"hint_march": "Modo marcha: escolha uma província vizinha — Esc cancela.",
		"hint_not_neighbor": "Não é uma província vizinha; modo marcha cancelado.",
		"hint_bot_turn": "Aguarde: os Elfos estão a planear.",
		"hint_no_troops": "Essa província não tem tropas para marchar.",
		"hint_order_queued": "Ordem registada; resolve no fim do turno.",
		"saved": "Jogo gravado.",
		"save_failed": "Não foi possível gravar.",
		"save_turn_start_only": "Só é possível gravar no início do turno, sem ordens em fila.",

		# --- Battle report ----------------------------------------------
		"battle_siege": "Cerco ao castelo de %s",
		"battle_field": "Batalha em campo aberto em %s",
		"battle_ambush": "Emboscada em %s!",
		"battle_line": "%s atacou %s — poder %.0f vs %.0f",
		"battle_losses": "Baixas: %d atacante · %d defensor",
		"battle_captured": "território capturado",
		"battle_held": "território mantido",
		"battle_swap_line": "Troca de posições: %s ↔ %s",
		"battles_title": "Batalhas do turno (%d)",

		# --- Battle preview ---------------------------------------------
		"preview_title": "Previsão — %s",
		"preview_free": "Sem defesa: captura garantida.",
		"preview_low_intel": "Sem informação sobre a guarnição inimiga.",
		"preview_power": "Poder: %.0f contra %.0f (ataque %.0f%%)",
		"preview_losses": "Baixas previstas: %d tuas · %d inimigas",
		"preview_band": "Intervalo: %d–%d tuas baixas · %s",
		"preview_capture": "captura provável",
		"preview_hold": "defesa mantém-se",
		"preview_note": "O resultado final varia com a sorte.",

		# --- Main menu --------------------------------------------------
		"new_game": "Novo jogo",
		"continue": "Continuar",
		"quit": "Sair",
		"settings": "Definições",
		"saved_available": "Há uma campanha gravada disponível.",
		"load_failed": "Não foi possível carregar: %s",
		"world_failed": "Não foi possível gerar o mundo.",
		"loading_world": "A gerar o continente",

		# --- New game setup ---------------------------------------------
		"new_game_title": "Novo jogo",
		"world_seed": "Seed (vazia = aleatória)",
		"world_seed_invalid": "A seed tem de ser um número inteiro.",
		"world_size": "Tamanho do mundo",
		"world_size_1": "1x",
		"world_size_15": "1,5x",
		"world_size_2": "2x",
		"difficulty": "Dificuldade",
		"difficulty_easy": "Fácil",
		"difficulty_normal": "Normal",
		"difficulty_hard": "Difícil",
		"difficulty_hud": "Dificuldade: %s",
		"new_game_note": "Deixa a seed vazia para gerar um mundo aleatório.",
		"start_game": "Começar",
		"back": "Voltar",

		# --- Domination -------------------------------------------------
		"domination_progress": "Cidades %d%% · %d/%d",
		"tip_domination": "Cidades possuídas e turnos seguidos acima de 70%.",

		# --- Game over --------------------------------------------------
		"victory": "Vitória",
		"defeat": "Derrota",
		"victory_body": "%s venceu a guerra por Stellarium.",

		# --- Settings panel --------------------------------------------
		"settings_title": "Definições",
		"language": "Idioma",
		"language_pt": "Português",
		"language_en": "English",
		"fullscreen": "Ecrã inteiro",
		"graphics_quality": "Qualidade gráfica",
		"quality_low": "Baixa",
		"quality_medium": "Média",
		"quality_high": "Alta",
		"menu_animations": "Animações do menu",
		"animations_on": "Animações",
		"animations_off": "Sem animações",
		"settings_note": "As alterações são aplicadas de imediato.",
		"close": "Fechar",
	},
	"en": {
		# --- Common -----------------------------------------------------
		"gold": "Gold",
		"manpower": "Manpower",
		"aether": "Aether",
		"iron": "Iron",
		"turn_badge": "Turn %d · %s",
		"phase_player": "Player",
		"phase_elves": "Elves",
		"phase_resolution": "Resolution",
		"phase_next": "Next",
		"phase_over": "Over",
		"faction_humans": "Humans",
		"faction_elves": "Elves",
		"faction_neutral": "Neutral",
		"terrain_plains": "Plains",
		"terrain_mountains": "Mountains",
		"terrain_forest": "Forest",
		"terrain_coast": "Coast",
		"terrain_highlands": "Highlands",
		"territory_highland_stronghold": "Highland Stronghold",
		"peak_impassable": "Impassable peak",
		"ambush": "Ambush",
		"ambush_active": "Ambushing",
		"fog_hidden": "No intelligence on the enemy garrison",
		"fog_unexplored": "Unexplored territory",
		"territory_capital_port": "Capital Port",
		"territory_fortress": "Fortress",
		"territory_fortress_pass": "Fortress Pass",
		"territory_river_town": "River Town",
		"territory_elven_spire": "Elven Spire",
		"territory_capital_citadel": "Capital Citadel",
		"territory_market_town": "Market Town",
		"territory_port_town": "Port Town",
		"territory_highlands": "Highlands",
		"territory_forest_coast": "Forest Coast",
		"territory_deep_forest": "Deep Forest",
		"territory_coastline": "Coastline",
		"territory_river_valley": "River Valley",
		"territory_farmlands": "Farmlands",
		"territory_wilderness": "Wilderness",

		# --- Units ------------------------------------------------------
		"unit_human_swordsmen": "Swordsmen",
		"unit_human_crossbowmen": "Crossbowmen",
		"unit_elf_boar": "Mechanical Boar",
		"unit_elf_riflemen": "Riflemen",
		"unit_human_knights": "Knights",
		"unit_human_pikemen": "Pikemen",
		"unit_human_ironclad": "Ironclad",
		"unit_human_catapult": "Arcane Catapult",
		"unit_elf_grove_wardens": "Grove Wardens",
		"unit_elf_thorn_lancers": "Thorn Lancers",
		"unit_elf_iron_guard": "Iron Guard",
		"unit_elf_howitzer": "Mobile Howitzer",

		# --- HUD: selection ---------------------------------------------
		"select_province": "Select a province on the map",
		"role_capital": "Capital",
		"role_castle": "Castle",
		"role_corridor": "Corridor",
		"role_wildland": "Wildland",
		"tip_wildland": "Wildlands have no defence and no recruitment; armies only pass through.",
		"troops": "%d troops",
		"troops_none": "No troops",
		"militia": "%d militia",
		"stat_attack": "Atk",
		"stat_defense": "Def",
		"income": "+%d %s",
		"recruit": "+ %s (%d🪙 %d👥)",
		"recruit_short": "+ %s",
		"recruit_cost": "Cost: %d gold · %d manpower",
		"recruit_city_only": "Cities and castles only",
		"recruit_unrest": "Province in revolt (%d turns)",
		"unrest": "Revolt %d",
		"capital_penalty": "Capital lost: +30%% recruitment, -25%% income (%d turns)",
		"recruit_tooltip": "%s\nAttack %d · Defense %d · Upkeep %d",
		"recruit_reason_gold": "Not enough gold or manpower",

		# --- HUD: buttons -----------------------------------------------
		"march": "March",
		"march_troops": "Troops to march",
		"end_turn": "End turn",
		"save": "Save",
		"menu": "Menu",
		"options": "Options",
		"cancel": "Cancel",
		"orders_title": "Queued orders",
		"order_move": "March %s → %s (%d troops)",
		"order_recruit": "Recruit %d %s in %s",
		"tip_end_turn": "Finish planning (Space)",
		"tip_march": "Queue a march into a neighbouring province (M)",
		"tip_save": "Save the game (S) — start of turn only, with no orders",
		"tip_menu": "Back to the main menu",
		"tip_options": "Settings: language, graphics and fullscreen",
		"tip_menu_button": "Campaign menu: save, options and quit",
		"tip_gold": "Gold: %d\nIncome: +%d · Upkeep: -%d",
		"tip_manpower": "Manpower: %d\nIncome: +%d",
		"tip_resource": "%s: %d\nIncome: +%d",
		"tip_terrain": "Base income: +%d gold, +%d manpower\nDefence: ×%.2f",
		"tip_ambush": "Hide the garrison until the enemy enters (A)",
		"ambush_reason_ground": "Cities, fortresses or wildlands only",
		"ambush_reason_troops": "No troops to hide",
		"ambush_reason_busy": "This province already has an order",
		"ambush_reason_active": "The garrison is already ambushing",
		"order_ambush": "Ambush troops in %s",
		"order_short_ambush": "Ambush",
		"fortress_upkeep": "Fortress: -%d gold/turn",
		"tip_orders_toggle": "Show or hide the order queue",
		"tip_orders_collapse": "Collapse the order queue",
		"orders_tab": "Orders (%d)",
		"orders_tab_empty": "Orders",
		"orders_empty": "No queued orders.",
		"order_short_move": "%s → %s",
		"order_short_recruit": "+%d %s",
		"order_count": "%d troops",
		"order_count_one": "%d troop",
		"order_hover_tip": "Hover to highlight this order on the map; click to select its origin.",
		"garrison_title": "Garrison",
		"garrison_empty": "No garrison",
		"garrison_unit_line": "%s × %d",
		"garrison_militia": "Local militia × %d",
		"battle_focus_tip": "Click to centre the map on this battle.",
		"reason_no_selection": "Select one of your provinces.",
		"reason_not_owned": "That province is not yours.",
		"reason_not_planning": "Wait for your planning turn.",

		# --- HUD: hints -------------------------------------------------
		"hint_march": "March mode: pick a neighbouring province — Esc cancels.",
		"hint_not_neighbor": "That province is not a neighbour; march cancelled.",
		"hint_bot_turn": "Please wait: the Elves are planning.",
		"hint_no_troops": "That province has no troops to march.",
		"hint_order_queued": "Order queued; it resolves at the end of the turn.",
		"saved": "Game saved.",
		"save_failed": "Saving failed.",
		"save_turn_start_only": "You can only save at the start of a turn, with no queued orders.",

		# --- Battle report ----------------------------------------------
		"battle_siege": "Castle siege of %s",
		"battle_field": "Open field battle at %s",
		"battle_ambush": "Ambush at %s!",
		"battle_line": "%s attacked %s — power %.0f vs %.0f",
		"battle_losses": "Losses: %d attacker · %d defender",
		"battle_captured": "territory captured",
		"battle_held": "territory held",
		"battle_swap_line": "Swap of positions: %s ↔ %s",
		"battles_title": "Battles this turn (%d)",

		# --- Battle preview ---------------------------------------------
		"preview_title": "Forecast — %s",
		"preview_free": "Undefended: capture guaranteed.",
		"preview_low_intel": "No intelligence on the enemy garrison.",
		"preview_power": "Power: %.0f vs %.0f (attack %.0f%%)",
		"preview_losses": "Expected losses: %d yours · %d enemy",
		"preview_band": "Range: %d–%d your losses · %s",
		"preview_capture": "likely capture",
		"preview_hold": "defence holds",
		"preview_note": "The final result varies with the roll.",

		# --- Main menu --------------------------------------------------
		"new_game": "New Game",
		"continue": "Continue",
		"quit": "Quit",
		"settings": "Settings",
		"saved_available": "A saved campaign is available.",
		"load_failed": "Could not load save: %s",
		"world_failed": "Could not generate the world.",
		"loading_world": "Generating the continent",

		# --- New game setup ---------------------------------------------
		"new_game_title": "New Game",
		"world_seed": "Seed (blank = random)",
		"world_seed_invalid": "The seed must be a whole number.",
		"world_size": "World size",
		"world_size_1": "1x",
		"world_size_15": "1.5x",
		"world_size_2": "2x",
		"difficulty": "Difficulty",
		"difficulty_easy": "Easy",
		"difficulty_normal": "Normal",
		"difficulty_hard": "Hard",
		"difficulty_hud": "Difficulty: %s",
		"new_game_note": "Leave the seed blank for a random world.",
		"start_game": "Start",
		"back": "Back",

		# --- Domination -------------------------------------------------
		"domination_progress": "Cities %d%% · %d/%d",
		"tip_domination": "Cities held and consecutive turns above 70%.",

		# --- Game over --------------------------------------------------
		"victory": "Victory",
		"defeat": "Defeat",
		"victory_body": "%s won the war for Stellarium.",

		# --- Settings panel --------------------------------------------
		"settings_title": "Settings",
		"language": "Language",
		"language_pt": "Português",
		"language_en": "English",
		"fullscreen": "Fullscreen",
		"graphics_quality": "Graphics quality",
		"quality_low": "Low",
		"quality_medium": "Medium",
		"quality_high": "High",
		"menu_animations": "Menu animations",
		"animations_on": "Animations",
		"animations_off": "No animations",
		"settings_note": "Changes are applied immediately.",
		"close": "Close",
	},
}


## Translated string for `key`, with optional printf-style arguments.
static func t(key: String, args: Array = []) -> String:
	var table: Dictionary = STRINGS.get(language, STRINGS["pt"])
	if not table.has(key):
		push_warning("Loc: missing key '%s' for language '%s'" % [key, language])
		return key
	var text := String(table[key])
	if args.is_empty():
		return text
	return text % args


static func faction_name(faction: int) -> String:
	match faction:
		Balance.Faction.HUMANS:
			return t("faction_humans")
		Balance.Faction.ELVES:
			return t("faction_elves")
	return t("faction_neutral")


static func difficulty_name(difficulty: int) -> String:
	match difficulty:
		Balance.Difficulty.EASY:
			return t("difficulty_easy")
		Balance.Difficulty.NORMAL:
			return t("difficulty_normal")
		Balance.Difficulty.HARD:
			return t("difficulty_hard")
	return t("difficulty_normal")


static func terrain_name(terrain: int) -> String:
	match terrain:
		Balance.Terrain.MOUNTAINS:
			return t("terrain_mountains")
		Balance.Terrain.FOREST:
			return t("terrain_forest")
		Balance.Terrain.COAST:
			return t("terrain_coast")
		Balance.Terrain.HIGHLANDS:
			return t("terrain_highlands")
	return t("terrain_plains")


static func resource_name(resource_key: String) -> String:
	match resource_key:
		"aether":
			return t("aether")
		"iron":
			return t("iron")
		"gold":
			return t("gold")
		"manpower":
			return t("manpower")
	return resource_key


## Territory types are data values in English ("River Town", ...); they get a
## stable key lookup instead of being translated in the generator.
static func territory_type(raw: String) -> String:
	var key := "territory_" + raw.to_lower().replace(" ", "_")
	var table: Dictionary = STRINGS.get(language, STRINGS["pt"])
	if table.has(key):
		return String(table[key])
	return raw


static func unit_name(unit_id: String) -> String:
	var key := "unit_" + unit_id
	var table: Dictionary = STRINGS.get(language, STRINGS["pt"])
	if table.has(key):
		return String(table[key])
	var defs: Dictionary = Balance.UNIT_DEFS.get(unit_id, {})
	return String(defs.get("display_name", unit_id))


## Localised phase label for the turn badge.
static func phase_short(phase: int) -> String:
	match phase:
		0:
			return t("phase_player")
		1:
			return t("phase_elves")
		2:
			return t("phase_resolution")
		3:
			return t("phase_next")
	return t("phase_over")


## Game rules return English reasons; the common ones are translated here and
## anything unknown falls through unchanged so no error is ever hidden.
static func reason(raw: String) -> String:
	if language == "en" or raw.is_empty():
		return raw
	var text := raw
	text = text.replace(" is not yours", " não é tua")
	text = text.replace(" does not border ", " não faz fronteira com ")
	text = text.replace(" has already issued an attack order this turn", " já emitiu uma ordem de ataque neste turno")
	text = text.replace("unknown order", "ordem desconhecida")
	text = text.replace("origin and target are the same province", "a origem e o destino são a mesma província")
	text = text.replace("recruit count must be positive", "o número de recrutas tem de ser positivo")
	text = text.replace(
		" is an open corridor — recruitment is only allowed in cities and castles",
		" é um corredor aberto — só se recruta em cidades e castelos"
	)
	text = text.replace("no game in progress", "nenhum jogo em curso")
	text = text.replace("unknown province", "província desconhecida")
	text = text.replace("unknown unit", "unidade desconhecida")
	text = text.replace("no troops selected", "nenhuma tropa selecionada")
	text = text.replace(" cannot hide an army here", " não pode esconder um exército aqui")
	text = text.replace(" is lying in ambush and cannot march", " está em emboscada e não pode marchar")
	text = text.replace(" is lying in ambush and cannot recruit", " está em emboscada e não pode recrutar")
	text = text.replace(" already has an order this turn", " já tem uma ordem neste turno")
	text = text.replace("need ", "faltam ")
	text = text.replace(" gold and ", " de ouro e ")
	text = text.replace(" manpower", " de mão-de-obra")
	return text
