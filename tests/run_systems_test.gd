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
	assert(BalanceConfig.meta_fragments_for_nights(0) == 0)
	assert(BalanceConfig.meta_fragments_for_nights(1) == 0)
	assert(BalanceConfig.meta_fragments_for_nights(2) == 0)
	assert(BalanceConfig.meta_fragments_for_nights(3) >= 1)
	assert(
		BalanceConfig.meta_fragments_for_nights(10)
		> BalanceConfig.meta_fragments_for_nights(5)
	)
	assert(
		BalanceConfig.meta_fragments_for_nights(BalanceConfig.WIN_NIGHTS)
		== BalanceConfig.META_FRAGMENT_TARGET_VICTORY
	)
	assert(BalanceConfig.get_wave_base_count(1) < BalanceConfig.get_wave_base_count(10))
	assert(BalanceConfig.get_wave_base_count(BalanceConfig.WIN_NIGHTS) > 100)

	var meta := root.get_node_or_null("MetaProgression")
	assert(meta != null)
	# Shop spans cheap early buys through multi-victory epic armies.
	assert(meta.UNLOCKS.has("start_food"))
	assert(int(meta.UNLOCKS["start_food"].get("cost", 0)) <= 10)
	assert(meta.UNLOCKS.has("knight_legion"))
	assert(int(meta.UNLOCKS["knight_legion"].get("cost", 0)) >= 300)
	assert(meta.UNLOCKS.has("mage_academy"))
	assert(int(meta.UNLOCKS["mage_academy"].get("cost", 0)) >= 300)

	var before: int = meta.fragments
	var earned: int = meta.award_run_rewards(3, false)
	assert(earned == BalanceConfig.meta_fragments_for_nights(3))
	assert(meta.fragments == before + earned)
	var victory_earn: int = meta.award_run_rewards(BalanceConfig.WIN_NIGHTS, true)
	assert(victory_earn == BalanceConfig.META_FRAGMENT_TARGET_VICTORY)
	# Restore to avoid polluting the user's save during tests.
	meta.fragments = before
	meta.save()
