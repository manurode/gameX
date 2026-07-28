class_name OcclusionSampleBudget
extends RefCounted

## Caps how many full pixel-occlusion checks run per rendered frame.
## Extra units keep their last silhouette state until a slot frees up.

const MAX_CHECKS_PER_FRAME := 28

static var _frame := -1
static var _remaining := 0


static func try_acquire() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_remaining = MAX_CHECKS_PER_FRAME
	if _remaining <= 0:
		return false
	_remaining -= 1
	return true
