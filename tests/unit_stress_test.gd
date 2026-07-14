extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for target_count in [25, 50, 100]:
		var container := Node2D.new()
		root.add_child(container)
		var started := Time.get_ticks_usec()
		for i in target_count:
			var type_id := "knight" if i % 2 == 0 else "archer"
			var scene := UnitDatabase.get_scene(type_id)
			var unit: Unit = scene.instantiate()
			unit.set_meta("squad_id", "stress-%d" % (i / BalanceConfig.SQUAD_SIZE))
			container.add_child(unit)
			unit.global_position = Vector2(i % 10, i / 10) * 32.0
		await process_frame
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		assert(container.get_child_count() == target_count)
		print("STRESS_%d_OK %.2fms" % [target_count, elapsed_ms])
		container.free()
		await process_frame
	print("UNIT_STRESS_TESTS_OK")
	quit(0)
