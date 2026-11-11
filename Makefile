# Prime Linux — test and check targets
#
#   make check      run the read-only E2E layers (structural.sh + contracts.sh)
#   make check-vm   run all three E2E layers (structural + contracts + journeys) inside the test VM

.PHONY: check check-vm

check:
	@bash tests/e2e/run-all.sh --fast

check-vm:
	@bash tests/vm/run-suite.sh
