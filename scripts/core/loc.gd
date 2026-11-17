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

		# --- HUD: selection ---------------------------------------------
		"select_province": "Selecione uma província no mapa",
		"role_capital": "Capital",
		"role_castle": "Castelo",
		"role_corridor": "Corredor",
		"troops": "%d tropas",
		"troops_none": "Sem tropas",
		"stat_attack": "Atq",
		"stat_defense": "Def",
		"income": "+%d %s",
		"recruit": "+ %s (%d🪙 %d👥)",
		"recruit_city_only": "Só em cidades e castelos",
		"recruit_tooltip": "%s\nAtaque %d · Defesa %d · Manutenção %d",
		"recruit_reason_gold": "Falta ouro ou mão-de-obra",

		# --- HUD: buttons -----------------------------------------------
		"march": "➔ Marchar",
		"end_turn": "⏳ Turno",
		"save": "Gravar",
		"menu": "Menu",
		"options": "Opções",
		"tip_end_turn": "Terminar o turno (Espaço)",
		"tip_march": "Marchar para uma província vizinha (M)",
		"tip_save": "Gravar o jogo (S)",
		"tip_menu": "Voltar ao menu principal",
		"tip_options": "Definições: idioma e ecrã inteiro",

		# --- HUD: hints -------------------------------------------------
		"hint_march": "Modo marcha: escolha uma província vizinha — Esc cancela.",
		"hint_not_neighbor": "Não é uma província vizinha; modo marcha cancelado.",
		"hint_bot_turn": "Aguarde: os Elfos estão a jogar.",
		"hint_no_troops": "Essa província não tem tropas para marchar.",
		"saved": "Jogo gravado.",
		"save_failed": "Não foi possível gravar.",

		# --- Battle report ----------------------------------------------
		"battle_siege": "Cerco ao castelo de %s",
		"battle_field": "Batalha em campo aberto em %s",
		"battle_line": "%s atacou %s — poder %.0f vs %.0f",
		"battle_losses": "Baixas: %d atacante · %d defensor",
		"battle_captured": "território capturado",
		"battle_held": "território mantido",

		# --- Main menu --------------------------------------------------
		"new_game": "Novo jogo",
		"continue": "Continuar",
		"quit": "Sair",
		"settings": "Definições",
		"saved_available": "Há uma campanha gravada disponível.",
		"load_failed": "Não foi possível carregar: %s",

		# --- Game over --------------------------------------------------
		"victory": "Vitória",
		"defeat": "Derrota",
		"victory_body": "%s controla Stellarium.",

		# --- Settings panel --------------------------------------------
		"settings_title": "Definições",
		"language": "Idioma",
		"language_pt": "Português",
		"language_en": "English",
		"fullscreen": "Ecrã inteiro",
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

		# --- HUD: selection ---------------------------------------------
		"select_province": "Select a province on the map",
		"role_capital": "Capital",
		"role_castle": "Castle",
		"role_corridor": "Corridor",
		"troops": "%d troops",
		"troops_none": "No troops",
		"stat_attack": "Atk",
		"stat_defense": "Def",
		"income": "+%d %s",
		"recruit": "+ %s (%d🪙 %d👥)",
		"recruit_city_only": "Cities and castles only",
		"recruit_tooltip": "%s\nAttack %d · Defense %d · Upkeep %d",
		"recruit_reason_gold": "Not enough gold or manpower",

		# --- HUD: buttons -----------------------------------------------
		"march": "➔ March",
		"end_turn": "⏳ Turn",
		"save": "Save",
		"menu": "Menu",
		"options": "Options",
		"tip_end_turn": "End the turn (Space)",
		"tip_march": "March into a neighbouring province (M)",
		"tip_save": "Save the game (S)",
		"tip_menu": "Back to the main menu",
		"tip_options": "Settings: language and fullscreen",

		# --- HUD: hints -------------------------------------------------
		"hint_march": "March mode: pick a neighbouring province — Esc cancels.",
		"hint_not_neighbor": "That province is not a neighbour; march cancelled.",
		"hint_bot_turn": "Please wait: the Elves are playing.",
		"hint_no_troops": "That province has no troops to march.",
		"saved": "Game saved.",
		"save_failed": "Saving failed.",

		# --- Battle report ----------------------------------------------
		"battle_siege": "Castle siege of %s",
		"battle_field": "Open field battle at %s",
		"battle_line": "%s attacked %s — power %.0f vs %.0f",
		"battle_losses": "Losses: %d attacker · %d defender",
		"battle_captured": "territory captured",
		"battle_held": "territory held",

		# --- Main menu --------------------------------------------------
		"new_game": "New Game",
		"continue": "Continue",
		"quit": "Quit",
		"settings": "Settings",
		"saved_available": "A saved campaign is available.",
		"load_failed": "Could not load save: %s",

		# --- Game over --------------------------------------------------
		"victory": "Victory",
		"defeat": "Defeat",
		"victory_body": "%s control Stellarium.",

		# --- Settings panel --------------------------------------------
		"settings_title": "Settings",
		"language": "Language",
		"language_pt": "Português",
		"language_en": "English",
		"fullscreen": "Fullscreen",
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


static func terrain_name(terrain: int) -> String:
	return t("terrain_plains") if terrain == Balance.Terrain.PLAINS else t("terrain_mountains")


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
	text = text.replace(" has already attacked this round", " já atacou esta ronda")
	text = text.replace(
		" is an open corridor — recruitment is only allowed in cities and castles",
		" é um corredor aberto — só se recruta em cidades e castelos"
	)
	text = text.replace("no game in progress", "nenhum jogo em curso")
	text = text.replace("unknown province", "província desconhecida")
	text = text.replace("unknown unit", "unidade desconhecida")
	text = text.replace("no troops selected", "nenhuma tropa selecionada")
	text = text.replace("need ", "faltam ")
	text = text.replace(" gold and ", " de ouro e ")
	text = text.replace(" manpower", " de mão-de-obra")
	return text
