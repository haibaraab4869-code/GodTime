extends RefCounted

## A time-window buffer for one action.
##
## A press is remembered for `window` seconds and can be consumed once. This is
## what makes an input feel responsive: pressing jump slightly before landing,
## or attack during the previous swing, still registers.

var _remaining := 0.0

func press(window: float) -> void:
	if window > 0.0:
		_remaining = maxf(_remaining, window)

func tick(delta: float) -> void:
	if _remaining > 0.0:
		_remaining = maxf(0.0, _remaining - delta)

## Takes the buffered press if one is pending. Returns whether it was taken.
func consume() -> bool:
	if _remaining > 0.0:
		_remaining = 0.0
		return true
	return false

func is_active() -> bool:
	return _remaining > 0.0

func remaining() -> float:
	return _remaining

func clear() -> void:
	_remaining = 0.0
