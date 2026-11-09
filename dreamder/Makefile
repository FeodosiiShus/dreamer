XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)

PROJECT := Dreamder.xcodeproj
SCHEME := Dreamder
LOGS := .build/logs
CONFIGURATION ?= Debug
FLAVOR ?= plain
SHARDS ?= 3
TIME_ALLOWANCE ?= 0
SHARDED = python3 Scripts/sharded-tests.py --flavor $(FLAVOR) --shards $(SHARDS) --time-allowance $(TIME_ALLOWANCE)
COVERAGE_BUILD := -enableCodeCoverage YES 'OTHER_SWIFT_FLAGS=$$(inherited) -Xllvm -instrprof-atomic-counter-update-all'
DERIVED = .build/xcode$(if $(filter coverage,$(FLAVOR)),-coverage)
PRODUCTS = $(DERIVED)/Build/Products
APP = $(PRODUCTS)/$(CONFIGURATION)/Dreamder.app
TEST_PRODUCTS ?= .build/test-products.tar.zst
XCODEBUILD_BASE = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
	-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' \
	-skipPackagePluginValidation -skipMacroValidation \
	CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
	ENABLE_HARDENED_RUNTIME=NO RUN_DOCUMENTATION_COMPILER=NO COMPILER_INDEX_STORE_ENABLE=NO
XCODEBUILD = $(XCODEBUILD_BASE) $(if $(filter coverage,$(FLAVOR)),$(COVERAGE_BUILD))
PACKAGES = sh Scripts/resolve-packages.sh $(DERIVED) $(XCODEBUILD_BASE) && sh Scripts/stub-swiftlint.sh $(DERIVED)/SourcePackages/artifacts
TEST_ENVIRONMENT := TEST_RUNNER_DREAMDER_HEADLESS=1 TEST_RUNNER_SWIFT_DETERMINISTIC_HASHING=1
COVERAGE_REPORT = python3 Scripts/coverage-report.py .build/coverage.xcresult --json .build/coverage.json | tee $(LOGS)/coverage.txt | tail -$(if $(TOP),$(TOP),40)
COVERAGE_GATE = $(if $(filter 1,$(COVERAGE_CHECK)),python3 Scripts/coverage-report.py .build/coverage.xcresult --check $(if $(GITHUB_STEP_SUMMARY),--summary),:)

.PHONY: build build-for-testing release run headless test test-sharded test-shard coverage coverage-sharded coverage-merge coverage-baseline pack-test-products unpack-test-products check lint lint-baseline ui-test screenshot action open toolwindow contextmenu annotate menuitem merge smoke clean

coverage coverage-sharded: FLAVOR = coverage

check:
	@python3 Scripts/crash-guard.py

lint:
	@mkdir -p $(LOGS)
	@$(PACKAGES)
	@sh Scripts/swiftlint.sh $(DERIVED)/SourcePackages/artifacts check

lint-baseline:
	@sh Scripts/swiftlint.sh $(DERIVED)/SourcePackages/artifacts baseline

build:
	@mkdir -p $(LOGS)
	@$(PACKAGES)
	@set -o pipefail; $(XCODEBUILD) build 2>&1 | tee $(LOGS)/build.log | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u

build-for-testing:
	@mkdir -p $(LOGS)
	@$(PACKAGES)
	@set -o pipefail; $(XCODEBUILD) build-for-testing 2>&1 | tee $(LOGS)/build-for-testing.log | grep -E "error:|TEST BUILD (SUCCEEDED|FAILED)" | sort -u

release:
	@$(MAKE) build CONFIGURATION=Release FLAVOR=plain
	@rm -f .build/Dreamder.zip
	@ditto -c -k --keepParent .build/xcode/Build/Products/Release/Dreamder.app .build/Dreamder.zip
	@echo .build/Dreamder.zip
	@rm -f .build/Dreamder-dSYM.zip
	@ditto -c -k --keepParent .build/xcode/Build/Products/Release/Dreamder.app.dSYM .build/Dreamder-dSYM.zip
	@echo .build/Dreamder-dSYM.zip

run: build
	@pkill -x Dreamder || true
	@sleep 1
	open -a "$(CURDIR)/$(APP)" "$(if $(PROJECT_DIR),$(PROJECT_DIR),$(CURDIR))"

headless: build
	@pkill -x Dreamder || true
	@sleep 1
	@open -g -a "$(CURDIR)/$(APP)" "$(if $(PROJECT_DIR),$(PROJECT_DIR),$(CURDIR))" --args -DreamderHeadless YES

test:
	@mkdir -p $(LOGS)
	@$(PACKAGES)
	@set -o pipefail; $(TEST_ENVIRONMENT) $(XCODEBUILD) test $(if $(FILTER),$(foreach suite,$(FILTER),-only-testing:DreamderTests/$(suite)),-only-testing:DreamderTests) 2>&1 | tee $(LOGS)/test.log | grep -E "error:|failed|Executed|passed after|TEST (SUCCEEDED|FAILED)" | sort -u

coverage:
	@mkdir -p $(LOGS)
	@$(PACKAGES)
	@rm -rf .build/coverage.xcresult
	@set -o pipefail; $(TEST_ENVIRONMENT) $(XCODEBUILD) test -only-testing:DreamderTests -resultBundlePath .build/coverage.xcresult 2>&1 | tee $(LOGS)/coverage.log | grep -E "error:|Test run with|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | sort -u
	@set -o pipefail; $(COVERAGE_REPORT)
	@$(COVERAGE_GATE)

test-sharded: build-for-testing
	@$(SHARDED)

test-shard:
	@$(SHARDED) --only $(SHARD)

coverage-sharded: build-for-testing
	@$(SHARDED) --result .build/coverage.xcresult; tests=$$?; \
		set -o pipefail; $(COVERAGE_REPORT); report=$$?; \
		$(COVERAGE_GATE); gate=$$?; \
		[ $$tests -eq 0 ] && [ $$report -eq 0 ] && [ $$gate -eq 0 ]

coverage-merge:
	@mkdir -p $(LOGS)
	@python3 Scripts/sharded-tests.py --merge --result .build/coverage.xcresult
	@set -o pipefail; $(COVERAGE_REPORT)

coverage-baseline:
	@python3 Scripts/coverage-report.py .build/coverage.xcresult --write-baseline

pack-test-products:
	@tar --zstd -cf $(TEST_PRODUCTS) -C $(PRODUCTS) $(CONFIGURATION) $$(cd $(PRODUCTS) && ls *.xctestrun)
	@du -h $(TEST_PRODUCTS)

unpack-test-products:
	@mkdir -p $(PRODUCTS)
	@tar --zstd -xf $(TEST_PRODUCTS) -C $(PRODUCTS)

ui-test:
	@mkdir -p $(LOGS)
	@set -o pipefail; $(XCODEBUILD) test -only-testing:$(if $(ONLY),$(ONLY),DreamderUITests) 2>&1 | tee $(LOGS)/ui-test.log | grep -E "error:|failed|Executed|TEST (SUCCEEDED|FAILED)" | sort -u

screenshot:
	@sh Scripts/screenshot.sh $(if $(OUT),$(OUT),.build/screenshots/latest)

action:
	@sh Scripts/action.sh "$(NAME)"

open:
	@sh Scripts/open.sh "$(FILE)"

toolwindow:
	@sh Scripts/toolwindow.sh "$(ID)"

contextmenu:
	@sh Scripts/contextmenu.sh $(if $(OUT),$(OUT),.build/contextmenu)

annotate:
	@sh Scripts/annotate.sh $(if $(OUT),$(OUT),.build/annotate)

menuitem:
	@sh Scripts/menuitem.sh "$(NAME)"

merge:
	@sh Scripts/merge.sh "$(CMD)"

smoke:
	@bash Scripts/smoke.sh

clean:
	rm -rf .build/xcode .build/xcode-coverage
