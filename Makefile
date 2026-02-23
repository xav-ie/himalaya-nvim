.PHONY: check test perf coverage coverage-check lint fmt fmt-check

MIN_COVERAGE ?= 90

check:
	nix develop --command parallel --tagstring '[{#}:{=s/ .*//=}]' --line-buffer ::: \
		'nix fmt -- --fail-on-change' \
		'luacheck lua/ tests/'
	$(MAKE) coverage-check

test:
	nix develop --command busted

perf:
	@rm -f perf-results.json
	nix develop --command busted --run perf
	@echo ""
	@echo "── results written to perf-results.json ──"
	@python3 -m json.tool perf-results.json 2>/dev/null || cat perf-results.json

coverage:
	@rm -f luacov.stats.out luacov.report.out
	LUACOV=1 nix develop --command busted
	nix develop --command luacov
	@echo ""
	@echo "Coverage report: luacov.report.out"

coverage-check: coverage
	@awk '/^lua\/himalaya\/.*\.lua\s/ { \
		split($$0, a); pct = a[length(a)]; gsub(/%/, "", pct); \
		if (pct + 0 < $(MIN_COVERAGE)) { printf "FAIL: %s at %s%% (min $(MIN_COVERAGE)%%)\n", a[1], pct; fail=1 } \
	} END { if (fail) exit 1; print "Each file >= $(MIN_COVERAGE)% coverage" }' luacov.report.out

lint:
	nix develop --command luacheck lua/ tests/

fmt:
	nix fmt

fmt-check:
	nix fmt -- --fail-on-change
