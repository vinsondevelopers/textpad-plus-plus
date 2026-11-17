# Textpad++ build (macOS, Command Line Tools only; no Xcode project required)
#
#   make                 debug-ish optimized build for the host arch -> build/Textpad++.app
#   make ARCHS="arm64 x86_64"   universal build
#   make test            unit tests + in-app acceptance self-test
#   make dmg             dist/Textpad++.dmg (universal, ad-hoc signed)
#   make notarize DEVELOPER_ID="Developer ID Application: ..." NOTARY_PROFILE=<profile>
#                        Developer ID + hardened runtime, notarized and stapled DMG for website download
#   make clean

APP_NAME   := Textpad++
BUNDLE_ID  := com.textpadplusplus.app
VERSION    := 1.0.0
UPDATE_URL ?=
# ? > Update Textpad++ reads this GUP XML (make dmg writes dist/update.xml for it); empty = no update address
DOWNLOAD_URL ?= $(if $(UPDATE_URL),$(dir $(UPDATE_URL))Textpad++.dmg,)
PLUGINLIST_URL ?= $(if $(UPDATE_URL),$(dir $(UPDATE_URL))pluginList.json,)
# the update signing key (created once by `make dmg UPDATE_URL=…`, never inside the project) and its public half,
# built into Info.plist (TPUpdatePublicKey: the 65-byte uncompressed P-256 point, base64)
UPDATE_KEY ?= $(HOME)/.textpad-update-key.pem
UPDATE_PUBKEY ?= $(shell [ -f "$(UPDATE_KEY)" ] && [ -n "$(UPDATE_URL)" ] && /usr/bin/openssl ec -in "$(UPDATE_KEY)" -pubout -outform DER 2>/dev/null | tail -c 65 | base64)
BUILD      ?= build
ARCHS      ?= $(shell uname -m)
MIN_MACOS  ?= 12.0

CC   := clang
CXX  := clang++
ARCHFLAGS := $(foreach a,$(ARCHS),-arch $(a))
empty :=
space := $(empty) $(empty)
ARCHTAG   := $(subst $(space),-,$(strip $(ARCHS)))
OBJ  := $(BUILD)/obj-$(ARCHTAG)

OPT        ?= -O2 -g
COMMON     := $(ARCHFLAGS) -mmacosx-version-min=$(MIN_MACOS) $(OPT) -fno-strict-aliasing
SCI_DEFS   := -DSCI_OWNREGEX -DBOOST_REGEX_STANDALONE -DNDEBUG
SCI_INC    := -Ithird_party/scintilla/include -Ithird_party/scintilla/src -Ithird_party/scintilla/cocoa -Ithird_party/boostregex
LEX_INC    := -Ithird_party/lexilla/include -Ithird_party/lexilla/lexlib -Ithird_party/scintilla/include
APP_INC    := -Isrc -Isrc/generated -Ithird_party/scintilla/include -Ithird_party/scintilla/cocoa -Ithird_party/lexilla/include -Ithird_party/uchardet -Isdk

THIRD_WARN := -w
APP_WARN   := -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers -Wno-deprecated-declarations

# ---- sources --------------------------------------------------------------
SCI_SRCS   := $(wildcard third_party/scintilla/src/*.cxx) \
              third_party/boostregex/BoostRegExSearch.cxx third_party/boostregex/UTF8DocumentIterator.cxx
SCI_MM     := $(filter-out %/InfoBar.mm,$(wildcard third_party/scintilla/cocoa/*.mm)) third_party/scintilla/cocoa/InfoBar.mm
LEX_SRCS   := $(wildcard third_party/lexilla/lexers/*.cxx) $(wildcard third_party/lexilla/lexlib/*.cxx) third_party/lexilla/src/Lexilla.cxx
CORE_SRCS  := $(wildcard src/core/*.cpp)
UCD_SRCS   := $(wildcard third_party/uchardet/*.cpp)
CORE_MM    := $(wildcard src/core/*.mm)
APP_MM     := $(wildcard src/*.mm src/app/*.mm src/commands/*.mm src/search/*.mm src/dialogs/*.mm src/panels/*.mm src/plugins/*.mm src/testing/*.mm)

SCI_OBJS   := $(patsubst %,$(OBJ)/%.o,$(SCI_SRCS) $(SCI_MM))
LEX_OBJS   := $(patsubst %,$(OBJ)/%.o,$(LEX_SRCS))
CORE_OBJS  := $(patsubst %,$(OBJ)/%.o,$(CORE_SRCS) $(CORE_MM) $(UCD_SRCS))
APP_OBJS   := $(patsubst %,$(OBJ)/%.o,$(APP_MM))

SCI_LIB    := $(OBJ)/libscintilla.a
LEX_LIB    := $(OBJ)/liblexilla.a
CORE_LIB   := $(OBJ)/libtppcore.a

APP        := $(BUILD)/$(APP_NAME).app
APP_BIN    := $(APP)/Contents/MacOS/$(APP_NAME)
FRAMEWORKS := -framework Cocoa -framework QuartzCore -framework CoreText -framework UniformTypeIdentifiers \
              -framework CoreServices -framework Security -framework WebKit -liconv

.PHONY: all app clean test unit selftest dmg run release notarize sample-plugin
all: app

app: $(APP_BIN) bundle-resources

# ---- compile rules ---------------------------------------------------------
$(OBJ)/third_party/scintilla/%.cxx.o: third_party/scintilla/%.cxx
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(COMMON) -std=c++17 $(THIRD_WARN) $(SCI_DEFS) $(SCI_INC) -c $< -o $@

$(OBJ)/third_party/boostregex/%.cxx.o: third_party/boostregex/%.cxx
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(COMMON) -std=c++17 $(THIRD_WARN) $(SCI_DEFS) $(SCI_INC) -c $< -o $@

$(OBJ)/third_party/scintilla/cocoa/%.mm.o: third_party/scintilla/cocoa/%.mm
	@mkdir -p $(dir $@)
	@echo "  OBJC $<"
	@$(CXX) $(COMMON) -std=c++17 -fobjc-arc $(THIRD_WARN) $(SCI_DEFS) $(SCI_INC) -c $< -o $@

$(OBJ)/third_party/lexilla/%.cxx.o: third_party/lexilla/%.cxx
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(COMMON) -std=c++17 $(THIRD_WARN) $(LEX_INC) -c $< -o $@

# uchardet (Mozilla universal charset detector, as bundled by Notepad++ in PowerEditor/src/uchardet)
$(OBJ)/third_party/uchardet/%.cpp.o: third_party/uchardet/%.cpp
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(COMMON) -std=c++17 $(THIRD_WARN) -Ithird_party/uchardet -c $< -o $@

$(OBJ)/src/%.cpp.o: src/%.cpp
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(COMMON) -std=c++20 $(APP_WARN) $(APP_INC) -MMD -MP -c $< -o $@

$(OBJ)/src/%.mm.o: src/%.mm
	@mkdir -p $(dir $@)
	@echo "  OBJC $<"
	@$(CXX) $(COMMON) -std=c++20 -fobjc-arc $(APP_WARN) $(APP_INC) -MMD -MP -c $< -o $@

$(SCI_LIB): $(SCI_OBJS)
	@rm -f $@; libtool -static -o $@ $^ 2>/dev/null
$(LEX_LIB): $(LEX_OBJS)
	@rm -f $@; libtool -static -o $@ $^ 2>/dev/null
$(CORE_LIB): $(CORE_OBJS)
	@rm -f $@; libtool -static -o $@ $^ 2>/dev/null

$(APP_BIN): $(APP_OBJS) $(CORE_LIB) $(SCI_LIB) $(LEX_LIB)
	@mkdir -p $(dir $@)
	@echo "  LINK $@"
	@$(CXX) $(COMMON) -fobjc-arc $(APP_OBJS) $(CORE_LIB) $(SCI_LIB) $(LEX_LIB) $(FRAMEWORKS) -o $@

# ---- bundle ----------------------------------------------------------------
ICONSET := $(BUILD)/AppIcon.iconset
ICNS    := $(BUILD)/AppIcon.icns

$(BUILD)/make_icon: scripts/make_icon.m
	@mkdir -p $(BUILD)
	@$(CC) -fobjc-arc -framework Cocoa $< -o $@

$(ICNS): $(BUILD)/make_icon
	@rm -rf $(ICONSET); mkdir -p $(ICONSET)
	@$(BUILD)/make_icon $(ICONSET)
	@iconutil -c icns $(ICONSET) -o $@

bundle-resources: $(APP_BIN) $(ICNS) resources/Info.plist
	@mkdir -p $(APP)/Contents/Resources
	@sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' -e 's/@MIN_MACOS@/$(MIN_MACOS)/g' -e 's|@UPDATE_URL@|$(UPDATE_URL)|g' -e 's|@PLUGINLIST_URL@|$(PLUGINLIST_URL)|g' -e 's|@UPDATE_PUBKEY@|$(UPDATE_PUBKEY)|g' resources/Info.plist > $(APP)/Contents/Info.plist
	@printf 'APPL????' > $(APP)/Contents/PkgInfo
	@cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	@rsync -a --delete resources/data/ $(APP)/Contents/Resources/data/
	@rsync -a --delete resources/icons/ $(APP)/Contents/Resources/icons/
	@cp third_party/scintilla/cocoa/res/*.png $(APP)/Contents/Resources/
	@for n in mac_cursor_busy mac_cursor_flipped info_bar_bg; do \
	  tiffutil -cathidpicheck third_party/scintilla/cocoa/res/$$n.png third_party/scintilla/cocoa/res/$$n@2x.png \
	    -out $(APP)/Contents/Resources/$$n.tiff >/dev/null 2>&1; done
	@rm -rf $(APP)/Contents/Resources/licenses; mkdir -p $(APP)/Contents/Resources/licenses
	@cp LICENSE $(APP)/Contents/Resources/licenses/Textpad++-GPL-3.0.txt
	@cp third_party/scintilla/License.txt $(APP)/Contents/Resources/licenses/Scintilla-License.txt
	@cp third_party/lexilla/License.txt $(APP)/Contents/Resources/licenses/Lexilla-License.txt
	@cp third_party/boostregex/LICENSE_1_0.txt $(APP)/Contents/Resources/licenses/Boost-License.txt 2>/dev/null || true
	@cp resources/licenses/*.txt $(APP)/Contents/Resources/licenses/
	@mkdir -p $(APP)/Contents/Resources/sdk/samples/SamplePlugin
	@cp sdk/TextpadPlusPlusPlugin.h third_party/scintilla/include/Scintilla.h third_party/scintilla/include/Sci_Position.h $(APP)/Contents/Resources/sdk/
	@cp sdk/samples/SamplePlugin/SamplePlugin.m sdk/samples/SamplePlugin/Info.plist $(APP)/Contents/Resources/sdk/samples/SamplePlugin/
	@cp docs/PLUGINS.md $(APP)/Contents/Resources/sdk/ 2>/dev/null || true
	@codesign --force --sign - --timestamp=none $(APP) 2>/dev/null && echo "  SIGN $(APP) (ad-hoc)"

run: app
	@open $(APP)

# ---- plugins: the SDK sample, built for the same architectures as the app (the self-test imports it)
SAMPLE_PLUGIN := $(BUILD)/plugins/SamplePlugin.tpplugin
sample-plugin: $(SAMPLE_PLUGIN)/Contents/MacOS/SamplePlugin
$(SAMPLE_PLUGIN)/Contents/MacOS/SamplePlugin: sdk/samples/SamplePlugin/SamplePlugin.m sdk/samples/SamplePlugin/Info.plist sdk/TextpadPlusPlusPlugin.h
	@mkdir -p $(dir $@)
	@echo "  CC   $<"
	@$(CC) $(COMMON) -bundle -fobjc-arc -framework Cocoa -Isdk -Ithird_party/scintilla/include $< -o $@
	@cp sdk/samples/SamplePlugin/Info.plist $(SAMPLE_PLUGIN)/Contents/Info.plist
	@codesign --force --sign - --timestamp=none $(SAMPLE_PLUGIN) 2>/dev/null

# ---- tests -----------------------------------------------------------------
UNIT_SRCS := $(wildcard tests/unit/*.cpp) $(wildcard tests/unit/*.mm)
UNIT_BIN  := $(BUILD)/unit_tests

$(UNIT_BIN): $(UNIT_SRCS) $(CORE_LIB)
	@mkdir -p $(BUILD)
	@echo "  LINK $@"
	@$(CXX) $(COMMON) -std=c++20 -fobjc-arc $(APP_WARN) $(APP_INC) -Itests/unit $(UNIT_SRCS) $(CORE_LIB) -framework Foundation -framework Security -liconv -o $@

unit: $(UNIT_BIN)
	@$(UNIT_BIN) $(BUILD)/unit-results.json

selftest: app sample-plugin
	@rm -f $(BUILD)/selftest-results.json
	@"$(APP_BIN)" --self-test "$(CURDIR)/$(BUILD)/selftest-results.json" >$(BUILD)/selftest.log 2>&1; status=$$?; \
	  python3 -I scripts/print_results.py $(BUILD)/selftest-results.json; exit $$status

test: unit selftest

# ---- packaging -------------------------------------------------------------
release:
	@$(MAKE) ARCHS="arm64 x86_64" app
	@# no debug symbol table in what ships: it records this machine's folder paths
	@strip -S $(APP_BIN) && codesign --force --sign - --timestamp=none $(APP) 2>/dev/null && echo "  STRIP + SIGN $(APP)"

dmg:
	@if [ -n "$(UPDATE_URL)" ]; then scripts/update_key.sh "$(UPDATE_KEY)"; fi
	@$(MAKE) release
	@scripts/make_dmg.sh "$(BUILD)/$(APP_NAME).app" dist "$(VERSION)"
	@if [ -n "$(UPDATE_URL)" ]; then scripts/make_update.sh "$(BUILD)/$(APP_NAME).app" dist "$(VERSION)" "$(UPDATE_KEY)" "$(DOWNLOAD_URL)" "$(UPDATE_URL)"; fi

notarize: release
	@DEVELOPER_ID="$(DEVELOPER_ID)" NOTARY_PROFILE="$(NOTARY_PROFILE)" scripts/notarize.sh "$(BUILD)/$(APP_NAME).app" dist "$(VERSION)"

clean:
	rm -rf $(BUILD)

-include $(shell find $(BUILD) -name '*.d' 2>/dev/null)
