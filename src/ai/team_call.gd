class_name TeamCall
extends RefCounted
## One mid-round call to a team (Milestone 7 D), made by its in-game leader: the AI leader
## ([BotTactics]) or a human player. The squad turns a call into orders, the same way whoever
## made it, so the AI teammates of a human IGL respond exactly as to their own leader.
##
## Attack: [constant EXECUTE] a site (from where the team is now), [constant HOLD] where you are,
## [constant REGROUP] (fall back to the gathering spot and go again together), [constant SAVE]
## (give up the round and keep the guns).
## Defence: [constant ROTATE] everyone to a site (after a plant: retake it), [constant HOLD] the
## set-up (no more rotations), [constant REGROUP] (gather outside the attacked site to retake
## together), [constant SAVE].

enum Kind { EXECUTE, HOLD, ROTATE, SAVE, REGROUP }

const NAMES: Dictionary[Kind, String] = {
	Kind.EXECUTE: "Execute", Kind.HOLD: "Hold", Kind.ROTATE: "Rotate", Kind.SAVE: "Save", Kind.REGROUP: "Regroup",
}

var kind: Kind = Kind.HOLD
## The bombsite letter for an execute, a rotation or where to regroup ("" otherwise; a regroup
## without one picks the site under attack).
var site: String = ""
## Who called it: a player ID, or "" for the AI leader.
var caller: String = ""
## Why (the AI leader's reason, shown to teammates).
var reason: String = ""


static func make(call_kind: Kind, letter: String = "", by: String = "", why: String = "") -> TeamCall:
	var call := TeamCall.new()
	call.kind = call_kind
	call.site = letter if call_kind != Kind.HOLD and call_kind != Kind.SAVE else ""
	call.caller = by
	call.reason = why
	return call


## "Execute B", "Hold", "Rotate A", ...
func label() -> String:
	if site.is_empty():
		return NAMES[kind]
	return NAMES[kind] + (" for " if kind == Kind.REGROUP else " ") + site


## The calls a leader on [param side] can make, in menu order, for a map with [param letters].
static func menu(side: StringName, letters: Array[String]) -> Array[TeamCall]:
	var list: Array[TeamCall] = []
	var site_kind := Kind.EXECUTE if side == MatchRules.SIDE_ATTACK else Kind.ROTATE
	for letter: String in letters:
		list.append(make(site_kind, letter))
	for other: Kind in [Kind.HOLD, Kind.REGROUP, Kind.SAVE]:
		list.append(make(other))
	return list
