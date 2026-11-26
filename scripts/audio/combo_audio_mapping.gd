class_name ComboAudioMapping
extends RefCounted
## How the combo-gain sound changes with the multiplier: bassier and heavier as it climbs.
##
## [method weight] runs 0 at [constant BASE_MULTIPLIER] (1x) to 1 at
## [constant FULL_MULTIPLIER] (10x, Godly x2) and stays clamped outside that span. The weight
## lowers the hit's pitch from [constant NEUTRAL_PITCH] to [constant DEEPEST_PITCH] and fades a
## sub-bass layer up from silence to [constant SUB_PEAK_DB]. Every curve is monotonic.
## NaN reads as 1x. Static only.

const BASE_MULTIPLIER := 1.0
## The multiplier where the sound is as heavy as it gets.
const FULL_MULTIPLIER := 10.0
const NEUTRAL_PITCH := 1.0
const DEEPEST_PITCH := 0.6
## Level of a fully faded-in sub layer, in dB.
const SUB_PEAK_DB := 0.0
## Level used for a silent sub layer, in dB.
const SILENT_DB := -80.0


## 0 to 1: how far [param multiplier] is from 1x towards [constant FULL_MULTIPLIER].
static func weight(multiplier: float) -> float:
	if is_nan(multiplier):
		return 0.0
	return clampf(
		(multiplier - BASE_MULTIPLIER) / (FULL_MULTIPLIER - BASE_MULTIPLIER), 0.0, 1.0)


## Pitch scale for the combo-gain hit: 1 at 1x, falling to [constant DEEPEST_PITCH].
static func pitch_scale(multiplier: float) -> float:
	return lerpf(NEUTRAL_PITCH, DEEPEST_PITCH, weight(multiplier))


## Volume of the sub-bass layer in dB: [constant SILENT_DB] at 1x, rising (linear in
## amplitude) to [constant SUB_PEAK_DB] at full weight.
static func sub_layer_db(multiplier: float) -> float:
	var amount := weight(multiplier)
	if amount <= 0.0:
		return SILENT_DB
	return maxf(SUB_PEAK_DB + linear_to_db(amount), SILENT_DB)
