TAPPER_OBJECTS=tapper.o

all: tapper

tapper: \$(TAPPER_OBJECTS)
	\$(CC) \$(TAPPER_OBJECTS) -o tapper

clean:
	-rm \$(TAPPER_OBJECTS) tapper
sniffer:
	gcc sniffer.c -o sniffer
