class_name Team
extends RefCounted

const PLAYER := 0
const ENEMY := 1


static func are_hostile(team_a: int, team_b: int) -> bool:
	return team_a != team_b
