#!/usr/bin/make

# MAKEFLAGS := $(MAKEFLAGS) s
HC := ghc
CC := gcc-8
CFLAGS := -fPIC $(shell python3-config --cflags)
CLIBS := $(shell python3-config --libs)
CYTHON := cython3
CYTHONFLAGS := --embed -X language_level=3
EXECUTABLE_INSTALL_LOCATION := /usr/bin/arggen

.DEFAULT_GOAL := all
.PHONY: all

args: test.hs args.hs
	$(HC) $^ -o $@

all: arggen test test_c;

test: ./test.hs ./args.hs
	$(HC) $^ -o $@

./args.hs: arggen ./spec.json ../argspec/arguments.schema.json
	./arggen -H ./spec.json > ./args.hs

%.hs:;

arggen: arggen.py.c
	$(CC) $(CFLAGS) $^ -o $@ $(CLIBS)

arggen.py.c: arggen.pyx; 
	$(CYTHON) $(CYTHONFLAGS) $< -o $@

arggen.pyx:;

test_c: test.c t.c tester_arg_parser.h
	gcc-8 -Wall -Werror -Wpedantic -pedantic-errors -g $^ -o $@

t.c: ./spec.json arggen
	./arggen -C ./spec.json > $@

%.json:;

install: arggen
	sudo install arggen $(EXECUTABLE_INSTALL_LOCATION)

clean:
	-@$(RM) argparser			2>/dev/null || true
	-@$(RM) arggen 				2>/dev/null || true
	-@$(RM) arggen.py.c			2>/dev/null || true
	-@$(RM) test				2>/dev/null || true
	-@$(RM) *.hi				2>/dev/null || true
	-@$(RM) *.o					2>/dev/null || true
	-@$(RM) args.hs				2>/dev/null || true
	-@$(RM) args				2>/dev/null || true
	-@$(RM) test_c				2>/dev/null || true
	-@$(RM) t					2>/dev/null || true
	-@$(RM) t.c					2>/dev/null || true
	-@$(RM) tester_arg_parser.h	2>/dev/null || true