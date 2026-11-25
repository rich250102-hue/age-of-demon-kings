class_name DetRng
extends RefCounted
## Générateur pseudo-aléatoire déterministe (xorshift32), identique bit à bit à
## server/nakama/modules/src/det_rng.ts. Le client et le serveur tirent ainsi
## exactement les mêmes nombres à partir de la même graine.

const MASK := 0xFFFFFFFF

var state: int


func _init(seed_value: int) -> void:
	state = seed_value & MASK
	if state == 0:
		state = 0x9E3779B9


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	state = x & MASK
	return state


## Entier dans [low, high], bornes comprises.
func range_int(low: int, high: int) -> int:
	return low + next_u32() % (high - low + 1)
