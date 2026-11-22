class_name GameDate
extends RefCounted
## In-game calendar maths. A date is an integer day number: day 0 = 1 Jan of Year 1. Years have
## 365 days (no leap years) so date arithmetic stays exact and deterministic.

const DAYS_PER_YEAR: int = 365
const MONTH_LENGTHS: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const MONTH_NAMES: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
	"Oct", "Nov", "Dec"]
## Day 0 (1 Jan Y1) is a Monday.
const WEEKDAY_NAMES: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const MINUTES_PER_DAY: int = 1440


## Year number (1-based; days before day 0 belong to Year 0, −1, …).
static func year_of(day: int) -> int:
	return floori(float(day) / DAYS_PER_YEAR) + 1


static func day_of_year(day: int) -> int:
	return posmod(day, DAYS_PER_YEAR)


## [month index 0–11, day of month 1–31]
static func month_and_day(day: int) -> Vector2i:
	var remaining := day_of_year(day)
	for month: int in MONTH_LENGTHS.size():
		if remaining < MONTH_LENGTHS[month]:
			return Vector2i(month, remaining + 1)
		remaining -= MONTH_LENGTHS[month]
	return Vector2i(11, 31)


static func make(year: int, month: int, day_of_month: int) -> int:
	var day := (year - 1) * DAYS_PER_YEAR + day_of_month - 1
	for m: int in month - 1:
		day += MONTH_LENGTHS[m]
	return day


## "05 Jan Y1"
static func format(day: int) -> String:
	var md := month_and_day(day)
	return "%02d %s Y%d" % [md.y, MONTH_NAMES[md.x], year_of(day)]


## 0 = Monday … 6 = Sunday.
static func weekday(day: int) -> int:
	return posmod(day, 7)


## "Tue 05 Jan Y1"
static func format_long(day: int) -> String:
	return "%s %s" % [WEEKDAY_NAMES[weekday(day)], format(day)]


## "18:30" for [param minute] minutes after midnight.
static func clock(minute: int) -> String:
	var wrapped := posmod(minute, MINUTES_PER_DAY)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [wrapped / 60, wrapped % 60]


## "05 Jan Y1 · 18:30"
static func format_at(day: int, minute: int) -> String:
	return "%s · %s" % [format(day), clock(minute)]


## "Year 3", or "2 years before Year 1" for dates before the career started.
static func format_year(day: int) -> String:
	var year := year_of(day)
	if year >= 1:
		return "Year %d" % year
	var before := 1 - year
	return "%d year%s before Year 1" % [before, "" if before == 1 else "s"]


## Whole years between [param birth_day] and [param today].
static func age(birth_day: int, today: int) -> int:
	return floori(float(today - birth_day) / DAYS_PER_YEAR)
