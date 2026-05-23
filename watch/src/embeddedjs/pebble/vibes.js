export function shortPulse() {
	native("xs_vibes_short_pulse")();
}

export function longPulse() {
	native("xs_vibes_long_pulse")();
}

export function doublePulse() {
	native("xs_vibes_double_pulse")();
}

export function pattern(pat) {
	native("xs_vibes_pattern")(pat);
}

export function cancel() {
	native("xs_vibes_cancel")();
}
