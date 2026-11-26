class_name MathLimits
extends RefCounted
## Shared numeric thresholds for vector maths, in one place. Static only, never instantiate.

## Above this |dot| two unit vectors count as parallel (or opposite), e.g. a direction
## that is nearly straight up or down. Use it before a cross product or a look-at basis
## that would degenerate, and pick a different helper axis instead.
const NEAR_PARALLEL_DOT := 0.999
