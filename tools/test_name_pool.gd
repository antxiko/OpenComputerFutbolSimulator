extends SceneTree

func _init() -> void:
	print("Test NamePool: 30 nombres aleatorios desde el pool internacional")
	print("=" .repeat(70))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var nat_count: Dictionary = {}
	for i in 30:
		var d: Dictionary = NamePool.generate(rng)
		print("  %2d. %-30s [%s]" % [i + 1, String(d["name"]), String(d["nationality"])])
		nat_count[d["nationality"]] = int(nat_count.get(d["nationality"], 0)) + 1
	print("\n  Distribución de nacionalidades en este sample:")
	for nat in nat_count.keys():
		print("    %s: %d" % [String(nat), int(nat_count[nat])])
	# Test variant Spanish
	print("\nGeneraciones forzadas españolas (Athletic basque_only):")
	for i in 5:
		var d: Dictionary = NamePool.generate_spanish(rng)
		print("  %s [%s]" % [String(d["name"]), String(d["nationality"])])
	quit(0)
