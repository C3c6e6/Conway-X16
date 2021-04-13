CONWAY.PRG conway.list &: conway.asm
	cl65 -t cx16 -o CONWAY.PRG -l conway.list conway.asm

clean:
	rm -v *.PRG *.list
