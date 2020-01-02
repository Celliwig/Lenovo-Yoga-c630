%{
	#include <unistd.h>
	#include <cstdio>
	#include <iostream>
	using namespace std;

	// stuff from flex that bison needs to know about:
	extern int yylex();
	extern int yyparse();
	extern FILE *yyin;
	extern int line_num;
	extern int check_menu_entry_num();
	extern int *menu_selection_list, menu_selection_list_size;

	void yyerror(const char *s);

	#define ACTION_PRINT_TITLE 1;
	#define ACTION_PRINT_KERNEL 2;
	#define ACTION_PRINT_INITRD 3;
	unsigned char action = 0;
%}

%union {
	int ival;
	float fval;
	char *sval;
}

// define the constant-string tokens:
//%token END ENDL

// define the "terminal symbol" token types I'm going to use (in CAPS
// by convention), and associate each with a field of the union:
%token <sval> SETVALUE
%token <sval> INSMOD
%token <sval> MENUTITLE
%token <sval> LINUX
%token <sval> INITRD

%%
grub-cfg:
	cfglines
//{
//      cout << "Processed GRUB config!" << endl;
//    }
  ;
cfglines:
	cfglines cfgline
	| cfgline
	;
cfgline:
	| set
	| insmod
	| linux
	| initrd
	| menutitle
	;
//sets:
//	sets set
//	| set
//	;
set:
	SETVALUE SETVALUE {
		//cout << "define: " << $1 << "->" << $2 << endl;
		free($1);
		free($2);
	}
	;
//insmods:
//	insmods insmod
//	| insmod
//	;
insmod:
	INSMOD {
		//cout << "load: " << $1 << endl;
		free($1);
	}
	;
menutitle:
	MENUTITLE {
		if (action == 1) {
			if (check_menu_entry_num()) {
				cout << "menu title: " << $1 << endl;
			}
		}
		free($1);
	}
linux:
	LINUX {
		if (action == 2) {
			if (check_menu_entry_num() > 1) {
				cout << "linux: " << $1 << endl;
			}
		}
		free($1);
	}
initrd:
	INITRD {
		if (action == 3) {
			if (check_menu_entry_num() > 1) {
				cout << "initrd: " << $1 << endl;
			}
		}
		free($1);
	}
%%
int main(int argc, char** argv) {
	char* grub_config = NULL;
	int opt, index;

	// Parse normal arguments
	while ((opt = getopt(argc, argv, "f:ikt")) != -1) {
		switch (opt) {
			case 'f':
				grub_config = optarg;
				break;
			case 'i':
				action = ACTION_PRINT_INITRD;
				break;
			case 'k':
				action = ACTION_PRINT_KERNEL;
				break;
			case 't':
				action = ACTION_PRINT_TITLE;
				break;
		}
	}
	// Parse additional arguments (menu entry selections)
	menu_selection_list_size = argc - optind;
	menu_selection_list = new int[menu_selection_list_size];
	index = 0;
	for(; optind < argc; optind++){
		menu_selection_list[index] = atoi(argv[optind]);
		index++;
	}

	if ((action == 0) || (grub_config == NULL)) {
		printf("Usage:\n");
		printf("%s\n", argv[0]);
		printf("	-f <grub_config>\n");
		printf("	-i - Print initrd info from menu entry\n");
		printf("	-k - Print kernel info from menu entry\n");
		printf("	-t - Print menu entry title\n");
		exit(-1);
	}

	// open a file handle to a particular file:
	FILE *myfile = fopen(grub_config, "r");
	// make sure it's valid:
	if (!myfile) {
		cout << "Can't open GRUB config." << endl;
		return -1;
	}
	// Set lex to read from it instead of defaulting to STDIN:
	yyin = myfile;

	// Parse through the input:
	yyparse();

	// Clean up
	delete menu_selection_list;
}

void yyerror(const char *s) {
	cout << "EEK, parse error on line " << line_num << "!  Message: " << s << endl;
	// might as well halt now:
	exit(-1);
}
