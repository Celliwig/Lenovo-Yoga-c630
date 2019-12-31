%{
	#include "grub-cfg.tab.h"
	#define STATE_STACK_SIZE 32
	unsigned int line_num = 1;
	unsigned int entry_num = 0;
	unsigned int entry_depth = 0;
%}
%x set_cfg insmod_cfg if_cfg menuentry_cfg
%%
^[ \t]*\n			{
	++line_num;
}
set				{
	yy_push_state(set_cfg);
}
<set_cfg>[= \t]			;
<set_cfg>[^= \t\n]+		{
	yylval.sval = strdup(yytext);
	return SETVALUE;
}
<set_cfg>[ \t]*\n		{
	++line_num;
	yy_pop_state();
}
insmod				{
	yy_push_state(insmod_cfg);
}
<insmod_cfg>[= \t]		;
<insmod_cfg>[^= \t\n]+		{
	yylval.sval = strdup(yytext);
	return INSMOD;
}
<insmod_cfg>[ \t]*\n		{
	++line_num;
	yy_pop_state();
}
^[ \t]*if			{
	yy_push_state(if_cfg);
}
<if_cfg>[^\n]*			;
<if_cfg>\n			{
	++line_num;
}
<if_cfg>[ \t]*fi[ \t]*\n	{
	++line_num;
	yy_pop_state();
}
^[ \t]*menuentry		{
	yy_push_state(menuentry_cfg);
}
<menuentry_cfg>[ \t]*\}[ \t]*\n	{
	++line_num;
	yy_pop_state();
}
%%
