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

all: arggen_c arggen_haskell arggen_python ./test/test_python.args.py;
# test;
# test arggen

./test/test: ./test.hs ./args.hs
	$(HC) $^ -o $@

./test/args.hs: ./spec.json arggen_haskell ../argspec/arguments.schema.json
	./arggen_haskell < $< > $@

./test/%.hs:;

./test/test_python.args.py: ./spec.json arggen_python
	./arggen_python < $< > $@

%: %.py.c
	$(CC) $(CFLAGS) $^ -o $@ $(CLIBS)

%.py.c: %.pyx; 
	$(CYTHON) $(CYTHONFLAGS) $^ -o $@

%.pyx:;

./test/test_c: ./test/test.c ./test/t.c tester_arg_parser.h
	gcc-8 -Wall -Werror -Wpedantic -pedantic-errors -g $^ -o $@

./test/t.c: ./spec.json arggen_c.pyx # arggen
	python3 ./arggen_c.pyx < $< > $@

%.h:;

%.json:;

install: arggen
	sudo install arggen $(EXECUTABLE_INSTALL_LOCATION)

clean:
	-@$(RM) argparser			2>/dev/null || true
	-@$(RM) arggen_c 			2>/dev/null || true
	-@$(RM) arggen_haskell		2>/dev/null || true
	-@$(RM) arggen_python		2>/dev/null || true
	-@$(RM) *.py.c				2>/dev/null || true
	-@$(RM) test				2>/dev/null || true
	-@$(RM) *.hi				2>/dev/null || true
	-@$(RM) *.o					2>/dev/null || true
	-@$(RM) args.hs				2>/dev/null || true
	-@$(RM) args				2>/dev/null || true
	-@$(RM) test_c				2>/dev/null || true
	-@$(RM) t					2>/dev/null || true
	-@$(RM) t.c					2>/dev/null || true
	-@$(RM) tester_arg_parser.h	2>/dev/null || true