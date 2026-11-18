class_name PersonVoice
extends RefCounted
## Words for people: personality descriptions, backgrounds, career goals and interview answers.
## All original text. Pure (no database); [CareerPeople] chooses when someone speaks.

const BACKGROUNDS: Array[String] = [
	"Grew up playing at a local internet café after school.",
	"Started on community servers and climbed the ladders alone.",
	"Learned on an older sibling's hand-me-down PC.",
	"Held movement-map records before ever playing a team game.",
	"Was a promising footballer until an injury turned them to esports.",
	"Spent years coaching friends' teams before deciding to play.",
	"Comes from a family of chess players and treats rounds like puzzles.",
	"Got noticed after a highlight clip went around the scene.",
	"Worked night shifts to pay for their first tournament trip.",
	"Moved cities as a teenager to join an academy squad.",
	"Studied engineering and still reads patch notes like manuals.",
	"Started as a streamer and turned competitive later than most.",
]

## Goal id → (text, drives that favour it).
const GOALS: Dictionary[String, Array] = {
	"win_title": ["Lift a trophy", ["winning", "game"]],
	"reach_tier_1": ["Play in the top tier", ["winning", "money", "fame"]],
	"one_club": ["Spend five years at one club", ["team"]],
	"become_star": ["Become a household name", ["fame", "money"]],
	"play_abroad": ["Play for a team in another region", ["game", "fame"]],
}

const DRIVES: Dictionary[String, String] = {
	"winning": "Winning",
	"money": "Money and security",
	"fame": "Fame and recognition",
	"team": "Team and belonging",
	"game": "Love of the game",
}

## Interview answers by topic and tone. %1 = own team, %2 = opponent (or new team).
const ANSWERS: Dictionary[String, Dictionary] = {
	"star": {
		"brash": ["Days like this are why they pay me. Give me the ball every round.", "I said before the match I'd carry. I carried."],
		"humble": ["The calls were great; I just had to click on heads.", "Honestly it's the team. I got the easy spots today."],
		"fiery": ["People doubted me last month. Keep talking, I'll keep fragging.", "That one was personal."],
		"measured": ["We prepared well and I found my rhythm early.", "A good day, but the next series matters more."],
	},
	"upset_win": {
		"brash": ["Upset? Only for people who weren't watching us practise.", "Write our name down. We're not going anywhere."],
		"humble": ["Nobody expected it, us included. We'll enjoy it tonight.", "We just played our game and it worked."],
		"fiery": ["Everyone wrote us off. That's fuel.", "Remember this one when you do your rankings."],
		"measured": ["We had a plan for their setups and stuck to it.", "One result. We need to back it up."],
	},
	"unsettled": {
		"brash": ["I've outgrown this level. Everyone can see it.", "I want to play for something bigger, simple as that."],
		"humble": ["I'm grateful for everything here, but I need a new challenge.", "It's not about anyone in particular. I just need a change."],
		"fiery": ["Things aren't right here and I'm done pretending.", "Some promises weren't kept. That's all I'll say."],
		"measured": ["I'll keep giving everything, but I'm open to what comes next.", "My priority is my career. We'll see in the window."],
	},
	"goal_done": {
		"brash": ["Told you all I'd get here.", "Ticked that box. Next one's bigger."],
		"humble": ["I used to dream about this. Thanks to everyone who helped.", "Still sinking in, to be honest."],
		"fiery": ["All the people who said I couldn't: here we are.", "Years of grinding for this."],
		"measured": ["It's something I've worked towards for a long time.", "Proud of it. Now I set a new target."],
	},
	"new_club": {
		"brash": ["%2 wanted the best. They got it.", "I'm here to win, not to make friends."],
		"humble": ["Big thanks to %1 for everything. Excited to learn at %2.", "I'll work hard to earn my place at %2."],
		"fiery": ["%1 didn't believe in me. %2 does.", "Point to prove now, and I'll prove it."],
		"measured": ["%2 has a clear plan and I fit into it.", "The right move at the right time."],
	},
}


## How someone talks: brash, humble, fiery or measured.
static func tone(person: Dictionary) -> String:
	var ego := int(person.get("ego", 10))
	var temperament := int(person.get("temperament", 10))
	if temperament <= 6:
		return "fiery"
	if ego >= 15:
		return "brash"
	if ego <= 7:
		return "humble"
	return "measured"


## An answer for [param topic] in this person's voice.
static func answer(person: Dictionary, topic: String, own_team: String, other: String, rng: RandomNumberGenerator) -> String:
	var lines: Array = (ANSWERS.get(topic, {}) as Dictionary).get(tone(person), [])
	if lines.is_empty():
		return ""
	var text := str(lines[rng.randi_range(0, lines.size() - 1)])
	return text.replace("%1", own_team).replace("%2", other)


## Short personality words in the style of a scouting report ("Driven · Loyal · Volatile").
static func descriptors(person: Dictionary) -> PackedStringArray:
	var words: PackedStringArray = []
	var checks: Array[Array] = [["ambition", "Driven", "Content with little"], ["loyalty", "Loyal", "Restless"],
		["professionalism", "Model professional", "Undisciplined"], ["temperament", "Unflappable", "Volatile"],
		["ego", "Big personality", "Modest"], ["sociability", "Social glue", "Keeps to themselves"]]
	for check: Array in checks:
		var value := int(person.get(str(check[0]), 10))
		if value >= 16:
			words.append(str(check[1]))
		elif value <= 5:
			words.append(str(check[2]))
	if words.is_empty():
		words.append("Balanced")
	return words


static func goal_text(goal: String) -> String:
	return str(GOALS[goal][0]) if GOALS.has(goal) else goal


static func drive_text(drive: String) -> String:
	return DRIVES.get(drive, drive)


## "Delighted" … "Wants out" for a happiness value (-50..50).
static func mood_word(happiness: int, wants_move: bool) -> String:
	if wants_move:
		return "Wants a move"
	if happiness >= 25:
		return "Delighted"
	if happiness >= 10:
		return "Happy"
	if happiness > -10:
		return "Settled"
	if happiness > -25:
		return "Frustrated"
	return "Miserable"


## "Close friends" … "Bitter rivals" for a relationship strength (-100..100).
static func bond_word(strength: int) -> String:
	if strength >= 70:
		return "Best friends"
	if strength >= CareerPeople.FRIEND_LEVEL:
		return "Friends"
	if strength >= 15:
		return "Get on well"
	if strength > -15:
		return "Neutral"
	if strength > CareerPeople.RIVAL_LEVEL:
		return "Some friction"
	if strength > -70:
		return "Rivals"
	return "Bitter rivals"
