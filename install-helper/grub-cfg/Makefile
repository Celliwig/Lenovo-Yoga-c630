grub-cfg.tab.c grub-cfg.tab.h: grub-cfg.y
	bison -d grub-cfg.y

lex.yy.c: grub-cfg.l grub-cfg.tab.h
	flex grub-cfg.l

grub-cfg: lex.yy.c grub-cfg.tab.c grub-cfg.tab.h
	g++ grub-cfg.tab.c lex.yy.c -l:libfl.a -o grub-cfg
