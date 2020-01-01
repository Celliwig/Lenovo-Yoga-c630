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

	void yyerror(const char *s);
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
cfglines {
      cout << "Processed GRUB config!" << endl;
    }
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
		cout << "menu title: " << $1 << endl;
		free($1);
	}
linux:
	LINUX {
		cout << "linux: " << $1 << endl;
		free($1);
	}
initrd:
	INITRD {
		cout << "initrd: " << $1 << endl;
		free($1);
	}
%%
int main(int argc, char** argv) {
	if(argc < 2){
		printf("Usage : %s <filename> ...\n", argv[0]);
		exit(0);
	}

	// open a file handle to a particular file:
	FILE *myfile = fopen(argv[1], "r");
	// make sure it's valid:
	if (!myfile) {
		cout << "Can't open GRUB config." << endl;
		return -1;
	}
	// Set lex to read from it instead of defaulting to STDIN:
	yyin = myfile;

	// Parse through the input:
	yyparse();
}

void yyerror(const char *s) {
	cout << "EEK, parse error on line " << line_num << "!  Message: " << s << endl;
	// might as well halt now:
	exit(-1);
}
