# Build the skeleton object only. This Makefile does not call bpftool load
# or tc attach.

CLANG ?= clang
OUT ?= /tmp/open5g-app-classifier.bpf.o

.PHONY: check clean

check:
	python3 scripts/check_build.py

clean:
	rm -f $(OUT)
