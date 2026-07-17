extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_modifiers()
	_test_meta_rewards()
	print("RUN_SYSTEMS_OK")
	quit(0)


func _test_modifiers() -> void:
	assert(NightModifier.all_ids().size() >= 4)
	var swarm := NightModifier.get_definition(NightModifier.Id.SWARM)
	assert(swarm.get("continuous_spawn", false) == true)
	var siege := NightModifier.get_definition(NightModifier.Id.SIEGE)
	assert(float(siege.get("count_mult", 1.0)) < 1.0)
	var ambush := NightModifier.get_definition(NightModifier.Id.AMBUSH)
	assert(ambush.get("dual_direction", false) == true)
	var picked := NightModifier.pick_random([NightModifier.Id.SWARM])
	assert(picked != NightModifier.Id.SWARM or NightModifier.all_ids().size() == 1)


func _test_meta_rewards() -> void:
	var before := MetaProgression.fragments
	var earned := MetaProgression.award_run_rewards(3, false)
	assert(earned == 3 * BalanceConfig.META_REWARD_PER_NIGHT)
	assert(MetaProgression.fragments == before + earned)
	var victory_earn := MetaProgression.award_run_rewards(5, true)
	assert(
		victory_earn
		== 5 * BalanceConfig.META_REWARD_PER_NIGHT + BalanceConfig.META_REWARD_VICTORY
	)
	# Restore to avoid polluting the user's save during tests.
	MetaProgression.fragments = before
	MetaProgression.save()
