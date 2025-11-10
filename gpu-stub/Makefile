# Makefile for ASTRAL JNA GPU Stub Library

CC = gcc
CFLAGS = -O3 -fPIC -shared -Wall
TARGET = libastral_gpu.so
SOURCE = astral_gpu.c

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) ../lib-enhanced/
	cp $(TARGET) ../cuda/ 2>/dev/null || mkdir -p ../cuda && cp $(TARGET) ../cuda/

.PHONY: all clean install
