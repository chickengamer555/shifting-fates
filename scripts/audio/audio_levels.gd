class_name AudioLevels
extends RefCounted
## Shared loudness constants for every audio script, so "silent" means the same everywhere.

## Level treated as silence, in dB. Players faded to it are muted or stopped.
const SILENT_DB := -80.0
