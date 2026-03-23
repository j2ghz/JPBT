SCHEME = JPBT
DESTINATION = platform=macOS
EXTRA =

build:
	xcodebuild -project JPBT.xcodeproj -scheme $(SCHEME) -destination '$(DESTINATION)' -skipMacroValidation build $(EXTRA)

test:
	xcodebuild -project JPBT.xcodeproj -scheme $(SCHEME) -destination '$(DESTINATION)' -skipMacroValidation test $(EXTRA)

.PHONY: build test
