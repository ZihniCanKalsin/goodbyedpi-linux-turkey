CC       ?= cc
PKGCONF  ?= pkg-config
CFLAGS   ?= -O2 -Wall -Wextra -Wno-unused-parameter -std=gnu11
LDFLAGS  ?=
PKGLIBS  := libnetfilter_queue libmnl

CFLAGS  += $(shell $(PKGCONF) --cflags $(PKGLIBS))
LDLIBS  += $(shell $(PKGCONF) --libs   $(PKGLIBS))

SRC := src/main.c src/nfq_loop.c src/tcp_mangle.c src/raw_inject.c \
       src/dns_redir.c src/checksum.c src/util.c src/fake_payloads.c
OBJ := $(SRC:.c=.o)
BIN := goodbyedpi-linux

all: $(BIN)

$(BIN): $(OBJ)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJ) $(BIN)

.PHONY: all clean
