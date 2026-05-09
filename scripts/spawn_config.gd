extends RefCounted
class_name SpawnConfig

# ══════════════════════════════════════════════════════════════
#  스폰 파라미터 통합 관리
#  모든 시스템의 SPACING_Z / SPAWN_CHANCE 기본값, 스테이지 스케일,
#  루트별 모디파이어를 이 파일 하나에서 정의한다.
#
#  사용법:
#    var p := SpawnConfig.get_params(route_type, current_stage)
#    _watchers.SPACING_Z    = p.watcher.spacing
#    _watchers.SPAWN_CHANCE = p.watcher.chance
# ══════════════════════════════════════════════════════════════

# ── 기본값 (stage 1, normal 루트 기준) ────────────────────────
# scavenging은 스테이지 스케일 대상 아님 (파밍 밸런스 고정)
const _DEFAULTS := {
	"scavenging": { "spacing": 80.0, "chance": 0.45, "scale": false },
	"watcher":    { "spacing": 35.0, "chance": 0.42, "scale": true  },
	"jumper":     { "spacing": 65.0, "chance": 0.15, "scale": true  },
	"obstacle":   { "spacing": 18.0, "chance": 0.25, "scale": true  },
}

# ── 루트별 모디파이어 테이블 ──────────────────────────────────
# 모디파이어 키:
#   spacing_abs / chance_abs  → 스테이지 스케일 후 절대값으로 덮어씀
#   spacing_mult / chance_mult → 스케일 후 값에 배수 적용
#   spacing_min / chance_max   → 배수 적용 후 클램프
const _ROUTE_TABLE := {
	"normal": {},

	"wreck": {
		"scavenging": { "spacing_abs": 50.0, "chance_abs": 0.65 },
		"obstacle":   { "spacing_abs": 14.0, "chance_abs": 0.22 },
	},

	"dark": {
		"watcher": { "spacing_abs": 40.0, "chance_abs": 0.25 },
		"jumper":  { "spacing_abs": 55.0, "chance_abs": 0.16 },
	},

	"cult": {
		"watcher":    { "spacing_mult": 0.65, "spacing_min": 14.0,
		                "chance_mult":  1.5,  "chance_max":  0.80 },
		"jumper":     { "spacing_mult": 0.72, "spacing_min": 28.0,
		                "chance_mult":  1.4,  "chance_max":  0.45 },
		"scavenging": { "chance_abs": 0.60 },
	},

	"weather": {},
}

# ── 퍼블릭 API ────────────────────────────────────────────────
## route_type과 stage를 받아 각 시스템의 최종 spacing/chance를 반환
## 반환값: { "watcher": { spacing, chance }, "jumper": ..., ... }
static func get_params(route_type: String, stage: int) -> Dictionary:
	var stage_scale := 1.0 + (stage - 1) * 0.15   # 1.0(stage1) ~ 1.75(stage6)
	var route_mods: Dictionary = _ROUTE_TABLE.get(route_type, {})
	var result := {}

	for system in _DEFAULTS:
		var def: Dictionary = _DEFAULTS[system]
		var spacing: float = def["spacing"]
		var chance: float  = def["chance"]

		# 1) 스테이지 난이도 스케일 (대상 시스템만)
		if def["scale"]:
			spacing /= stage_scale
			chance  *= stage_scale

		# 2) 루트 모디파이어 적용
		if route_mods.has(system):
			var mod: Dictionary = route_mods[system]
			# spacing
			if mod.has("spacing_abs"):
				spacing = mod["spacing_abs"]
			elif mod.has("spacing_mult"):
				spacing = maxf(spacing * mod["spacing_mult"],
				               mod.get("spacing_min", 0.0))
			# chance
			if mod.has("chance_abs"):
				chance = mod["chance_abs"]
			elif mod.has("chance_mult"):
				chance = minf(chance * mod["chance_mult"],
				              mod.get("chance_max", 1.0))

		result[system] = { "spacing": spacing, "chance": chance }

	return result
