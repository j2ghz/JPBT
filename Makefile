SCHEME = JPBT
DESTINATION = platform=macOS

build:
	xcodebuild -project JPBT.xcodeproj -scheme $(SCHEME) -destination '$(DESTINATION)' build

test:
	xcodebuild -project JPBT.xcodeproj -scheme $(SCHEME) -destination '$(DESTINATION)' test

.PHONY: build test
