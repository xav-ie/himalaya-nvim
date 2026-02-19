.PHONY: test perf

test:
	nix develop --command nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', exclude_dirs = {'perf'}}"

perf:
	@rm -f perf-results.json
	nix develop --command nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/perf/ {minimal_init = 'tests/minimal_init.lua'}"
	@echo ""
	@echo "── results written to perf-results.json ──"
	@python3 -m json.tool perf-results.json 2>/dev/null || cat perf-results.json
