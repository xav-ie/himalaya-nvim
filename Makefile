.PHONY: test perf coverage

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
