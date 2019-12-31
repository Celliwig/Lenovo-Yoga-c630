%{
	#include "grub-cfg.tab.h"
	#define STATE_STACK_SIZE 32
	unsigned int line_num = 1;
	unsigned int entry_num = 0;
	unsigned int entry_depth = 0;
	unsigned int oldstate[STATE_STACK_SIZE];
	unsigned int oldstate_ptr = 0;

	void push_state(unsigned int tmp_state) {
		if (oldstate_ptr >= STATE_STACK_SIZE) {
			printf("Too many state transitions.\n");
			exit(-1);
		} else {
			oldstate[oldstate_ptr] = tmp_state;
			oldstate_ptr++;
		}
	}

	unsigned int pop_state() {
		if (oldstate_ptr > 0) {
			oldstate_ptr--;
			return oldstate[oldstate_ptr];
		} else {
			printf("Trying to pop below stack.\n");
			exit(-1);
		}
	}
%}
%x set_cfg insmod_cfg if_cfg
%%
^[ \t]*\n		{
	++line_num;
}
set			{
	push_state(YY_START);
	BEGIN(set_cfg);
}
<set_cfg>[= \t]		;
<set_cfg>[^= \t\n]+	{
	yylval.sval = strdup(yytext);
	return SETVALUE;
}
<set_cfg>[ \t]*\n	{
	++line_num;
	BEGIN(pop_state());
}
insmod			{
	push_state(YY_START);
	BEGIN(insmod_cfg);
}
<insmod_cfg>[= \t]	;
<insmod_cfg>[^= \t\n]+	{
	yylval.sval = strdup(yytext);
	return INSMOD;
}
<insmod_cfg>[ \t]*\n	{
	++line_num;
	BEGIN(pop_state());
}
^[ \t]*if		{
	push_state(YY_START);
	BEGIN(if_cfg);
}
<if_cfg>[^\n]*		;
<if_cfg>\n		{
	++line_num;
}
<if_cfg>[ \t]*fi[ \t]*\n	{
	BEGIN(pop_state());
}

%%
