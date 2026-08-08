extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_modifiers()
	_test_meta_rewards()
	_test_meta_upgrade_application()
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
	var before_best: int = meta.best_nights
	var before_wins: int = meta.wins
	var before_hero_wins: Dictionary = meta.hero_wins.duplicate()
	var before_power_unlocks: Dictionary = meta.hero_power_unlocks.duplicate(true)
	var hero_id: String = str(meta.selected_hero_id)
	var before_hero_count: int = meta.get_hero_wins(hero_id)
	var frag_mult: float = GameSettings.get_fragment_reward_mult()
	var earned: int = meta.award_run_rewards(3, false)
	var expected_partial: int = maxi(
		1, int(round(float(BalanceConfig.meta_fragments_for_nights(3)) * frag_mult))
	)
	assert(earned == expected_partial)
	assert(meta.fragments == before + earned)
	assert(meta.best_nights == maxi(before_best, 3))
	var victory_earn: int = meta.award_run_rewards(BalanceConfig.WIN_NIGHTS, true)
	var expected_victory: int = maxi(
		1, int(round(float(BalanceConfig.META_FRAGMENT_TARGET_VICTORY) * frag_mult))
	)
	assert(victory_earn == expected_victory)
	assert(meta.wins == before_wins + 1)
	assert(meta.get_hero_wins(hero_id) == before_hero_count + 1)
	assert(meta.best_nights == maxi(before_best, BalanceConfig.WIN_NIGHTS))
	# Restore to avoid polluting the user's save during tests.
	meta.fragments = before
	meta.best_nights = before_best
	meta.wins = before_wins
	meta.hero_wins = before_hero_wins
	meta.hero_power_unlocks = before_power_unlocks
	meta.save()


func _test_meta_upgrade_application() -> void:
	var meta := root.get_node_or_null("MetaProgression")
	assert(meta != null)
	var saved_unlocked: Dictionary = meta.unlocked.duplicate()
	var saved_enabled: Dictionary = meta.enabled.duplicate()
	meta.unlocked = {
		"gather_boost": true,
		"gather_mastery": true,
		"archer_dmg": true,
		"knight_hp": true,
		"mage_chain": true,
		"extra_gather_worker": true,
		"pop_surge": true,
	}
	meta.enabled = {
		"gather_boost": true,
		"gather_mastery": true,
		"archer_dmg": true,
		"knight_hp": true,
		"mage_chain": true,
		"extra_gather_worker": true,
		"pop_surge": true,
	}
	assert(is_equal_approx(meta.get_gather_multiplier(), 1.155))
	assert(meta.get_archer_damage_bonus() == 3)
	assert(meta.get_knight_hp_bonus() == 15)
	assert(meta.get_mage_chain_damage_bonus() == 2)
	assert(meta.get_mage_chain_target_bonus() == 1)
	assert(meta.get_gather_max_workers_bonus() == 1)
	assert(meta.get_population_cap_bonus() == 8)

	var archer := Unit.new()
	UnitDatabase.apply_definition_to_unit(archer, "archer")
	assert(archer.attack_damage == 17)
	var knight := Unit.new()
	UnitDatabase.apply_definition_to_unit(knight, "knight")
	assert(knight.max_hp == 115)
	var mage := Unit.new()
	UnitDatabase.apply_definition_to_unit(mage, "mage")
	assert(mage.chain_damage == 6)
	assert(mage.chain_max_targets == 4)

	var lumber_workers := BuildingDatabase.get_max_workers("lumber_camp")
	assert(lumber_workers == 4)

	var descriptions := meta.get_unlocked_upgrade_descriptions()
	assert(descriptions.has("Recolección permanente +5%."))
	assert(descriptions.has("Recolección permanente +10% adicional."))

	meta.enabled["gather_boost"] = false
	assert(not meta.is_enabled("gather_boost"))
	assert(is_equal_approx(meta.get_gather_multiplier(), 1.10))
	var active_only := meta.get_unlocked_upgrade_descriptions()
	assert(not active_only.has("Recolección permanente +5%."))
	assert(active_only.has("Recolección permanente +10% adicional."))
	meta.enabled["gather_boost"] = true

	meta.unlocked = saved_unlocked
	meta.enabled = saved_enabled
