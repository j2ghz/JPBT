SCHEME = JPBT
DESTINATION = platform=macOS
EXTRA =

build:
	xcodebuild -project JPBT.xcodeproj -scheme $(SCHEME) -destination '$(DESTINATION)' build $(EXTRA)

test:
	xcodebuild -project JPBT.xcodeproj -scheme $(SCHEME) -destination '$(DESTINATION)' test $(EXTRA)

.PHONY: build test
