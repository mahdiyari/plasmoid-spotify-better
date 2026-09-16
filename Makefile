VERSION := $(shell git describe --tags --always --dirty)
ARCHIVE := plasmoid-spotify-better-$(VERSION).tar.gz
SRC := src

all: $(SRC)/metadata.json $(shell find $(SRC)/contents -type f)
	tar -C $(SRC) -czf $(ARCHIVE) metadata.json contents

clean:
	rm -f $(ARCHIVE)
