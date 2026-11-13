class_name DecayProfile
extends Resource
## Minimal configurable deterioration parameters for resource definitions.
## Active timers, physical piles, and decay simulation belong to T2.1+.

enum DecayMode {
	GRADUAL_UNITS,
	EXPIRE_ALL,
}

@export var can_decay: bool = true
@export var exposure_duration_sec: float = 0.0
@export var decay_mode: DecayMode = DecayMode.GRADUAL_UNITS


func is_valid() -> bool:
	return is_finite(exposure_duration_sec) and exposure_duration_sec >= 0.0
