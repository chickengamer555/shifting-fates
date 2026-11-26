class_name PhysicsLayers
extends RefCounted
## The project's 3D physics layers (named in project.godot), in one place.
##
## [code]*_LAYER[/code] constants are layer numbers (1-based, for
## [method CollisionObject3D.set_collision_mask_value]); [code]*_MASK[/code] constants are
## the matching bits for [member CollisionObject3D.collision_layer] / [code]collision_mask[/code]
## and physics queries. Static only, never instantiate.

## Solid level geometry.
const WORLD_LAYER := 1
## The skater's body.
const PLAYER_LAYER := 2
## Solid normally, passable while the skater is shifted (see [ShiftPhase]).
const PHASEABLE_LAYER := 3
## Grind rail detection areas (see [GrindRail]).
const GRIND_RAIL_LAYER := 4
## Trigger areas (portals, barriers, pickups).
const TRIGGER_LAYER := 5

const WORLD_MASK := 1 << (WORLD_LAYER - 1)
const PLAYER_MASK := 1 << (PLAYER_LAYER - 1)
const PHASEABLE_MASK := 1 << (PHASEABLE_LAYER - 1)
const GRIND_RAIL_MASK := 1 << (GRIND_RAIL_LAYER - 1)
const TRIGGER_MASK := 1 << (TRIGGER_LAYER - 1)
