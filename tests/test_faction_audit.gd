extends "res://tests/test_case.gd"
## CW-0 (#251, design/CANDLEWAKE.md §1.2): the generated two-faction audit (tools/faction_audit.gd) stays complete for the
## engine. Every hit in data/, rules/ and ai/ (a faction, capital or roster id, `size() == 2`, `factions[0]`,
## `FactionData.FACTIONS`, a faction pair key) is counted by its file's mark, which says what was done about it; a new
## hit, or one gone, fails here until the mark is looked at and updated with its reason.

const Audit := preload("res://tools/faction_audit.gd")


func test_every_engine_hit_is_marked() -> void:
	var problems := Audit.check(Audit.scan(Audit.ENGINE_DIRS))
	assert_eq(problems, [], "\n".join(problems))


func test_the_audit_looks_for_every_id_the_data_has() -> void:
	var found := Audit.ids()
	assert_eq(found.faction, FactionData.ids(), "every faction, the Candlewake included")
	assert_eq(found.capital, ["crownkeep", "fangridge"], "the capitals the rows name (the Candlewake take the free one)")
	for row in FactionData.rows():
		for u in row.unit_types:
			assert_true(found.unit.has(String(u.id)), "%s is looked for" % u.id)
		assert_true(found.unit.has(String(row.commander.id)), "%s is looked for" % row.commander.id)
	for sid in MagicData.SUMMONS:
		assert_true(found.unit.has(String(sid)), "the summon %s is looked for" % sid)


func test_each_kind_of_hit_is_found() -> void:
	var hits := Audit.scan(["data", "rules", "ui"])
	var kinds := {}
	for h in hits:
		for k in h.kinds:
			kinds[k] = true
	for k in ["faction", "capital", "unit", "two", "index", "table"]:
		assert_true(kinds.has(k), "the audit finds a %s" % Audit.KIND_NAMES[k])
	assert_true(hits.any(func(h): return h.file == "data/factions.gd" and h.kinds.has("faction")), "the faction rows")
	assert_false(hits.any(func(h): return String(h.text).begins_with("#")), "comment lines are not code")


func test_the_report_gives_every_engine_file_its_disposition() -> void:
	var md := Audit.report(Audit.scan(Audit.ENGINE_DIRS))
	assert_false(md.contains("NOT MARKED"), "every engine file in the report says what was done")
	for s in Audit.SEMANTIC:
		assert_true(FileAccess.file_exists("res://" + String(s[0])), "%s is a file" % s[0])
		assert_false(String(s[2]).is_empty(), "%s has a disposition" % s[0])
