%{
	#include <unistd.h>
	#include <cstdio>
	#include <iostream>
	#include <string.h>
	using namespace std;

	// stuff from flex that bison needs to know about:
	extern int yylex();
	extern int yyparse();
	extern FILE *yyin;
	extern unsigned int line_num;
	extern unsigned int check_menu_entry_num();
	extern unsigned int *menu_selection_list, menu_selection_list_size;
	extern unsigned char is_submenu;

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
	| linux
	| initrd
	| menutitle
	;
menutitle:
	MENUTITLE {
		if (action == 1) {
			if (check_menu_entry_num()) {
				unsigned int tmp_slen = strlen($1);
				char *tmp_ptr, tmp_qchar;
				if (tmp_slen > 0) {
					tmp_qchar = $1[tmp_slen - 1];			// Get last character
					$1[tmp_slen - 1] = '\0';			// Then remove last character
					tmp_ptr = strchr($1, tmp_qchar);		// Get the first occurence of the ast character

					if (tmp_ptr != NULL) {
						cout << (tmp_ptr + 1) << endl;
					}
				}
			}
		}
		free($1);
	}
linux:
	LINUX {
		if (action == 2) {
			if (check_menu_entry_num() > 1) {
				cout << $1 << endl;
			}
		}
		free($1);
	}
initrd:
	INITRD {
		if (action == 3) {
			if (check_menu_entry_num() > 1) {
				cout << $1 << endl;
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
	menu_selection_list = new unsigned int[menu_selection_list_size];
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

	if (is_submenu) exit(-1);
	exit(0);
}

void yyerror(const char *s) {
	cout << "EEK, parse error on line " << line_num << "!  Message: " << s << endl;
	// might as well halt now:
	exit(-1);
}
