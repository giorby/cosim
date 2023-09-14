# Output directory:
OUT_DIR := /tmp/test

$(OUT_DIR)/read.bin: read-data.o
	gcc -O3 -o $@ $<

%.o : %.c
	gcc -O3 -c -o $@ $<
