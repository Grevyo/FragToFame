class_name RoundPlan
extends RefCounted
## One team's plan for one round, as its in-game leader calls it ([RoundPlanner]): what kind of
## round it is, which site it is about, where each player goes and what their job is there.
## Pure data on the career layer; the match engine plays it out on the map's [SimMap].

## Attack kinds.
const DEFAULT: StringName = &"default"   ## spread out, take map control, decide on information
const EXECUTE: StringName = &"execute"   ## all five onto one site together, with utility
const SPLIT: StringName = &"split"       ## one site from two entrances at once
const RUSH: StringName = &"rush"         ## straight onto one site as fast as possible
const FAKE: StringName = &"fake"         ## show at one site, then hit the other
## Defence kinds.
const STANDARD: StringName = &"standard" ## players spread over both sites, a rotator between
const STACK: StringName = &"stack"       ## most of the team on one site
const AGGRESSIVE: StringName = &"aggressive"  ## early fights forward for information
const SAVE_SETUP: StringName = &"save"   ## on an eco: few, careful positions, guns kept for later

## Jobs.
const ENTRY: StringName = &"entry"       ## first through the door
const TRADE: StringName = &"trade"       ## right behind the entry, to trade them
const SUPPORT: StringName = &"support"   ## utility and late arrival
const LURK: StringName = &"lurk"         ## alone on the far side, cutting off rotations
const FAKER: StringName = &"faker"       ## makes the noise of a hit somewhere else
const ANCHOR: StringName = &"anchor"     ## holds a site to the end
const ROTATOR: StringName = &"rotator"   ## between sites, goes where the attack is
const AGGRESSOR: StringName = &"aggressor"  ## takes an early fight forward

var side: StringName = &"attack"
var kind: StringName = DEFAULT
## The site this round is about (attack: the target; defence: the stacked site, "" when spread).
var site: String = ""
## Attack, fake: where the noise is made.
var fake_site: String = ""
## Seconds into the round when the attack goes onto the site (default rounds call it on information).
var hit_at: float = 0.0
## player id -> the place they go to (attack) or hold (defence).
var spots: Dictionary[String, String] = {}
## player id -> places walked through from spawn to their spot, in order.
var routes: Dictionary[String, Array] = {}
## player id -> job.
var jobs: Dictionary[String, StringName] = {}
## Why the leader chose this ("they stacked A last round", "eco: rush the nearest site").
var reasons: PackedStringArray = []


## Player IDs with [param job].
func with_job(job: StringName) -> Array[String]:
	var list: Array[String] = []
	for id: String in jobs:
		if jobs[id] == job:
			list.append(id)
	list.sort()
	return list


## How many of this plan's players start on or around [param site_id] (by [param map]'s clusters).
func players_at(map: SimMap, site_id: String) -> int:
	var cluster := map.site_cluster(site_id)
	var count := 0
	for id: String in spots:
		if cluster.has(spots[id]) or (map.entrances(site_id).has(spots[id]) and _belongs_to(map, spots[id], site_id)):
			count += 1
	return count


## A short record for the round log (and later the match view).
func to_dict() -> Dictionary:
	var spot_copy: Dictionary = {}
	for id: String in spots:
		spot_copy[id] = spots[id]
	var job_copy: Dictionary = {}
	for id: String in jobs:
		job_copy[id] = str(jobs[id])
	return {"side": str(side), "kind": str(kind), "site": site, "fake_site": fake_site, "hit_at": snappedf(hit_at, 0.1),
		"spots": spot_copy, "jobs": job_copy, "reasons": Array(reasons)}


## An entrance belongs to the site it is closer to (entrances can be shared between sites).
static func _belongs_to(map: SimMap, place: String, site_id: String) -> bool:
	var own := map.distance(place, site_id)
	for other: String in map.sites():
		if other != site_id and map.distance(place, other) >= 0.0 and map.distance(place, other) < own:
			return false
	return true
