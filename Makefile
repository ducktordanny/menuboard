.PHONY: build run install clean

build:
	scripts/build-app.sh

run:
	scripts/run.sh

install: build
	rm -rf /Applications/MenuBoard.app
	cp -R build/MenuBoard.app /Applications/MenuBoard.app

clean:
	rm -rf .build build
