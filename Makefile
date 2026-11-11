.PHONY: setup project open test clean

# Симулятор для тестов: make test SIM="iPhone 16 Pro"
SIM ?= iPhone 17

# Нужен XcodeGen 2.45+ (синхронизируемые папки Xcode 16).
XCODEGEN_MIN = 2.45.0

# Первый запуск: ставит XcodeGen, создаёт локальный конфиг и проект, открывает Xcode.
setup:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@test -f Config/Local.xcconfig || (cp Config/Local.xcconfig.example Config/Local.xcconfig && \
		echo "→ Создан Config/Local.xcconfig — впишите свой DEVELOPMENT_TEAM и BUNDLE_ID_PREFIX")
	@$(MAKE) project open

project:
	@v=$$(xcodegen --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'); \
	if [ "$$(printf '%s\n' $(XCODEGEN_MIN) $$v | sort -V | head -1)" != "$(XCODEGEN_MIN)" ]; then \
		echo "→ XcodeGen $$v устарел, обновляю…"; brew upgrade xcodegen; fi
	xcodegen generate

open:
	open TripAtlas.xcodeproj

test: project
	xcodebuild test -project TripAtlas.xcodeproj -scheme TripAtlas \
		-destination 'platform=iOS Simulator,name=$(SIM)'

clean:
	rm -rf TripAtlas.xcodeproj DerivedData build
