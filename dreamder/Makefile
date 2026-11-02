XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)

PROJECT := Dreamder.xcodeproj
SCHEME := Dreamder
DERIVED := .build/xcode
LOGS := .build/logs
CONFIGURATION ?= Debug
APP := $(DERIVED)/Build/Products/$(CONFIGURATION)/Dreamder.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
	-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' \
	-skipPackagePluginValidation -skipMacroValidation \
	CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
	ENABLE_HARDENED_RUNTIME=NO

.PHONY: build release run headless test coverage ui-test screenshot action open toolwindow contextmenu annotate menuitem merge clean

build:
	@mkdir -p $(LOGS)
	@$(XCODEBUILD) -resolvePackageDependencies > $(LOGS)/resolve.log 2>&1
	@sh Scripts/stub-swiftlint.sh $(DERIVED)/SourcePackages/artifacts
	@set -o pipefail; $(XCODEBUILD) build 2>&1 | tee $(LOGS)/build.log | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u

release:
	@$(MAKE) build CONFIGURATION=Release
	@rm -f .build/Dreamder.zip
	@ditto -c -k --keepParent $(DERIVED)/Build/Products/Release/Dreamder.app .build/Dreamder.zip
	@echo .build/Dreamder.zip

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
	@set -o pipefail; TEST_RUNNER_DREAMDER_HEADLESS=1 $(XCODEBUILD) test $(if $(FILTER),-only-testing:DreamderTests/$(FILTER),-only-testing:DreamderTests) 2>&1 | tee $(LOGS)/test.log | grep -E "error:|failed|Executed|passed after|TEST (SUCCEEDED|FAILED)" | sort -u

coverage:
	@mkdir -p $(LOGS)
	@rm -rf .build/coverage.xcresult
	@set -o pipefail; TEST_RUNNER_DREAMDER_HEADLESS=1 $(XCODEBUILD) test -only-testing:DreamderTests -enableCodeCoverage YES -resultBundlePath .build/coverage.xcresult 2>&1 | tee $(LOGS)/coverage.log | grep -E "error:|Test run with|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | sort -u
	@python3 Scripts/coverage-report.py .build/coverage.xcresult | tee $(LOGS)/coverage.txt | tail -$(if $(TOP),$(TOP),40)

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

clean:
	rm -rf $(DERIVED)
