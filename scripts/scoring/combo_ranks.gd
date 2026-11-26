class_name ComboRanks
extends RefCounted
## Names the combo rank for a multiplier, per the GDD rank table.
##
## Ranks sit on 0.5x thresholds starting at 1.0x; a multiplier gets the name of the highest
## threshold at or below it. Past [constant NAMED_RANKS] the rank is "Godly xN", where N
## counts up by one every further 0.5x without end (9.5x is Godly x1, 10x Godly x2, ...).
## Static only: call [method rank_name] directly, never instantiate.

## Multiplier of the first rank (Baby). Anything lower is still Baby.
const BASE_MULTIPLIER := 1.0
## Multiplier gap between consecutive ranks.
const RANK_STEP := 0.5
## Absorbs float noise so 2.4999999 counts as the 2.5x rank.
const THRESHOLD_EPSILON := 1e-6
## Ranks from 1.0x upward, one per [constant RANK_STEP].
const NAMED_RANKS: Array[String] = [
	"Baby",
	"Chump",
	"Mediocre",
	"Potential",
	"Amateur",
	"Great",
	"Awesome",
	"Spectacular",
	"Professional",
	"Totally Tubular",
	"Radical to the Bone",
	"Extreme!!!",
	"Champion",
	"Perfection",
	"Surpassing",
	"Ascending",
	"The Pearly Gates",
]
## Name pattern for every rank past the named ones; %d is the Godly tier, starting at 1.
const GODLY_FORMAT := "Godly x%d"


## Zero-based rank for [param multiplier]: 0 is Baby, each [constant RANK_STEP] adds one.
static func rank_index(multiplier: float) -> int:
	var steps := floori((multiplier - BASE_MULTIPLIER) / RANK_STEP + THRESHOLD_EPSILON)
	return maxi(steps, 0)


## Display name of the rank [param multiplier] has reached, e.g. 10.5 gives "Godly x3".
static func rank_name(multiplier: float) -> String:
	var index := rank_index(multiplier)
	if index < NAMED_RANKS.size():
		return NAMED_RANKS[index]
	return GODLY_FORMAT % (index - NAMED_RANKS.size() + 1)
