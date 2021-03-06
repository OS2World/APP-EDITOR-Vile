%pointer
%x META sTEXT NORMAL ONELINE HEREDOC SSTRING DSTRING QUOTED2 SUBST

%o 10000
%a 10000

%{
/*
 * $Header: /usr/build/vile/vile/filters/RCS/rpm-filt.l,v 1.31 2010/07/13 13:45:53 tom Exp $
 *
 * Filter to add vile "attribution" sequences to selected bits of rpm spec-file.
 */

#include <filters.h>

DefineFilter("rpm");

#define isQuote(ch) (ch != 0 && strchr("\\'\"", ch) != 0)

static char *Action_attr;
static char *Comment_attr;
static char *Error_attr;
static char *Ident_attr;
static char *Number_attr;
static char *String_attr;

static int strip_tabs;
static char *here_tag;
static size_t here_len;
static int here_exp;

#include <fltstack.h>

static const char * meta_variable(char *name, int len);
static const char * my_keyword_attr(char *name, int len);
static int embed_or_append(char *text, int length);
static int got_here(char *text, int length);
static void begin_section(char *name, int length);
static void color_delimiter(char *text, int size, char *attr);
static void save_here(char *text, int length);

%}

SPACE		[ \t]

SSTRING		\'([^']|\n)*\'
DSTRING		\"([^"]|\n)*\"

NAME		[[:alnum:]_]

WILDCARD	(\?|\*)
WILDNAME	({NAME}|{WILDCARD})
FILENAME	(([./]{WILDNAME}+)|({WILDNAME}+[./]{WILDNAME}*)|({NAME}*{WILDCARD})|\.+\/+)+

ACTION		[\.`{}]
IDENT		[[:alpha:]_]{NAME}*
QIDENT		({SSTRING}|{DSTRING}|[^ \"'$\t\r\n])+
IDENT0		[-]+[[:digit:]]*[[:alpha:]_-]+[[:alnum:]_-]*

SH_IDENT1	[$]{NAME}+
SH_IDENT2	[$]\{{IDENT}\}
SH_IDENT2L	[$]\{{IDENT}

MY_IDENT1	[%]{NAME}+
MY_IDENT2	[%]\{{IDENT}\}
MY_IDENT2L	[%]\{{IDENT}

IDENT1		({SH_IDENT1}|{MY_IDENT1})
IDENT2		({SH_IDENT2}|{MY_IDENT2})
IDENT2L		({SH_IDENT2L}|{MY_IDENT2L})

IDENT2R		\}

IDENTEQLS	[[:alpha:]_]{NAME}*=
IDENTX		\$[\*@#\?\$!-]

INTEGER		[-+]?([[:digit:]]+)

SECTION		%{IDENT}

%%

<NORMAL>{SECTION}	{ begin_section(yytext, yyleng); }

<sTEXT,NORMAL>"%%"	{ WriteToken(String_attr); }

<sTEXT,NORMAL>^{IDENT}:	{
			  const char *attr;
			  int len = yyleng - 1;
			  int save = yytext[len];
			  yytext[len] = 0;
			  attr = my_keyword_attr(yytext, len);
			  yytext[len] = (char) save;
			  if (cur_state == sTEXT && (attr == 0 || *attr == 0)) {
			      WriteToken(String_attr);
			  } else {
			      WriteToken3(attr, len);
			      WriteToken2("", len);
			  }
			  push_state(ONELINE);
			  flt_bfr_begin(String_attr);
			}

<sTEXT>^"%"[^\r\n \t]*	{ begin_section(yytext, yyleng); }
<sTEXT>{IDENT1}		|
<sTEXT>{IDENT2}		{ WriteToken(my_keyword_attr(yytext, yyleng)); }
<sTEXT>[^%\r\n]*	{ WriteToken(String_attr); }
<sTEXT>\n		{ ECHO; }

<NORMAL>{IDENT0}	|
<NORMAL>{FILENAME}	{ ECHO; /* exclude from other classes */ }

<ONELINE>[\r\n]		{
			  flt_bfr_finish();
			  pop_state();
			  ECHO;
			}
<ONELINE>{IDENT1}	|
<ONELINE>{IDENT2}	{ flt_bfr_embed(yytext, yyleng, meta_variable(yytext, yyleng)); }
<ONELINE>{IDENT2L}	{
			  flt_bfr_embed(yytext, yyleng, meta_variable(yytext, yyleng));
			  push_state(SUBST);
			}
<ONELINE>{IDENTX}	{ flt_bfr_embed(yytext, yyleng, meta_variable(yytext, yyleng)); }

<ONELINE>{IDENTEQLS}	{
			  flt_bfr_embed(yytext, yyleng-1, meta_variable(yytext, yyleng));
			  flt_bfr_embed("=", 1, "");
			}
<ONELINE>.		{ flt_bfr_embed(yytext, yyleng, String_attr); }

<NORMAL>{IDENT}		{
			  WriteToken(my_keyword_attr(yytext, yyleng));
			}

<NORMAL>"#"[^\r\n]*	{ WriteToken(Comment_attr); }

<NORMAL>^{SPACE}*:	{ color_delimiter(yytext, yyleng, Action_attr); }

<NORMAL>{ACTION}	{ WriteToken(Action_attr); }

<NORMAL>{INTEGER}	{ WriteToken(Number_attr); }

<NORMAL>{IDENT1}	|
<NORMAL>{IDENT2}	{ WriteToken(meta_variable(yytext, yyleng)); }
<NORMAL>{IDENT2L}	{
			  WriteToken(meta_variable(yytext, yyleng));
			  push_state(SUBST);
			}
<NORMAL>{IDENTX}	{ WriteToken(meta_variable(yytext, yyleng)); }

<NORMAL>{IDENTEQLS}	{
			  flt_puts(yytext, yyleng-1, meta_variable(yytext, yyleng));
			  flt_putc('=');
			}

<NORMAL>\\.		{ WriteToken(String_attr); }
<NORMAL>\'		{
			  push_state(SSTRING);
			  BeginQuote(SSTRING, String_attr);
			}
<NORMAL>\"		{
			  push_state(DSTRING);
			  BeginQuote(DSTRING, String_attr);
			}

<NORMAL>\<\<[-]?{SPACE}*{QIDENT} {
			    int n;
			    strip_tabs = 0;
			    for (n = 0; n < yyleng; n++) {
				if (yytext[n] != '<'
				 && !isspace(CharOf(yytext[n]))) {
				    strip_tabs = (yytext[n] == '-');
				    break;
				}
			    }
			    save_here(yytext, yyleng);
			    push_state(HEREDOC);
			    if (strchr(yytext, '\n') != 0) {
				flt_error("unexpected end of line");
				BeginQuote(HEREDOC, Error_attr);
			    } else {
				BeginQuote(HEREDOC, String_attr);
			    }
			    flt_bfr_begin(String_attr);
			}
<HEREDOC>\\\$		{ flt_bfr_append(yytext, yyleng); }
<HEREDOC>{IDENT1}	|
<HEREDOC>{IDENT2}	{ embed_or_append(yytext, yyleng); }
<HEREDOC>{IDENT2L}	{ if (embed_or_append(yytext, yyleng)) push_state(SUBST); }
<HEREDOC>^[\t]*{QIDENT}$ {
			    int used = 0;
			    if (strip_tabs) {
				used = (int) (skip_blanks(yytext) - (char *) yytext);
				if (used != 0)
				    flt_bfr_append(yytext, used);
			    }
			    if (got_here(yytext + used, yyleng - used)) {
				flt_bfr_finish();
				pop_state();
				strip_tabs = 0;
			    } else {
				flt_bfr_append(yytext, yyleng);
			    }
			}
<HEREDOC>[^\r\n\$]+	{ flt_bfr_append(yytext, yyleng); }
<HEREDOC>\n		{ flt_bfr_append(yytext, yyleng); }
<HEREDOC>.		{ flt_bfr_append(yytext, yyleng); }

<DSTRING>\\		{ flt_bfr_embed(yytext, yyleng, Action_attr); push_state(QUOTED2); }
<DSTRING>{IDENT1}	|
<DSTRING>{IDENT2}	{ flt_bfr_embed(yytext, yyleng, meta_variable(yytext, yyleng)); }
<DSTRING>{IDENT2L}	{ if (embed_or_append(yytext, yyleng)) push_state(SUBST); }
<DSTRING>[^\r\n\\\"$]+	{ flt_bfr_append(yytext, yyleng); }
<DSTRING>[\n$]		{ flt_bfr_append(yytext, yyleng); }
<DSTRING>\"		{ FinishQuote(NORMAL); pop_state(); }

<SSTRING>{MY_IDENT1}	|
<SSTRING>{MY_IDENT2}	{ flt_bfr_embed(yytext, yyleng, meta_variable(yytext, yyleng)); }
<SSTRING>{MY_IDENT2L}	{ if (embed_or_append(yytext, yyleng)) push_state(SUBST); }
<SSTRING>[^\r\n\'%]+	{ flt_bfr_append(yytext, yyleng); }
<SSTRING>[\r\n%]	{ flt_bfr_append(yytext, yyleng); }
<SSTRING>\'		{ FinishQuote(NORMAL); pop_state(); }

<QUOTED2>(.|\n)		{ flt_bfr_embed(yytext, yyleng, Action_attr); pop_state(); }

<SUBST>{IDENT2R}	{ flt_bfr_embed(yytext, yyleng, meta_variable(yytext, yyleng)); pop_state(); }
<SUBST>\"		{ push_state(DSTRING); BeginQuote(DSTRING, String_attr); }
<SUBST>[^"}]+		{ flt_bfr_embed(yytext, yyleng, ""); }

%%

#include <fltstack.h>

static void
begin_section(char *name, int len)
{
    const char *flags = ci_keyword_flag(name);

    if (flags == 0)
	flags = "";

    WriteToken(my_keyword_attr(name, len));
    if (strchr(flags, 'o') != 0) {
	push_state(ONELINE);
	flt_bfr_begin(String_attr);
    } else if (strchr(flags, 'q') != 0) {
	new_state(sTEXT);
    } else {
	new_state(NORMAL);
    }
}

static const char *
meta_variable(char *name, int len)
{
    const char *attr = my_keyword_attr(name, len);
    return (attr != 0) ? attr : Ident_attr;
}

static const char *
my_keyword_attr(char *name, int len)
{
    const char *attr = ci_keyword_attr(name);
    if (attr == 0) {
	int try = len;
	char save;
	const char *flags;

	while (try > 0 && isdigit(CharOf(name[try-1]))) {
	    --try;
	}
	if (try < len) {
	    save = name[try];
	    name[try] = 0;
	    attr = ci_keyword_attr(name);
	    flags = ci_keyword_flag(name);
	    name[try] = save;
	    if (attr != 0) {
		if (flags != 0) {
		    if (strchr(flags, 'n') == 0) {
			attr = 0;
		    }
		} else {
		    attr = 0;
		}
	    }
	}
    }
    return attr;
}

static void
save_here(char *text, int length)
{
    char *s;

    here_exp = 1;
    if ((here_tag = do_alloc(here_tag, (size_t) length, &here_len)) != 0) {
	s = here_tag;
	while (length--) {
	    if (isQuote(*text)) {
		here_exp = 0;
	    } else if (strchr(" \t", *text) != 0) {
		if (s != here_tag)
		    break;
	    } else if (strchr("<->", *text) == 0) {
		*s++ = *text;
	    }
	    text++;
	}
	*s = 0;
    }
}

static int
embed_or_append(char *text, int length)
{
    if (here_exp) {
	flt_bfr_embed(text, length, meta_variable(text, length));
    } else {
	flt_bfr_append(text, length);
    }
    return here_exp;
}

static int
got_here(char *text, int length)
{
    int pass, j, k;

    for (pass = 0; pass < 2; pass++) {
	for (j = k = 0; j < length; j++) {
	    if (isQuote(text[j])) {
		if (pass) {
		    flt_error("unexpected quote");
		    flt_bfr_embed(text + j, 1, Error_attr);
		}
	    } else {
		if (here_tag != 0 && (text[j] != here_tag[k++]))
		    return 0;
		if (pass)
		    flt_bfr_append(text + j, 1);
	    }
	}
    }
    return 1;
}

/*
 * string passed to this routine is in the format:
 *
 *    [<white>]:
 */
static void
color_delimiter(char *text, int size, char *attr)
{
    char delim[2];

    delim[0] = text[--size];       /* save the trailing delimiter */
    delim[1] = text[size] = '\0';  /* chop the trailing delimiter */
    if (size)
	flt_puts(text, size , "");
    flt_puts(delim, 1, attr);
}

static void
init_filter(int before GCC_UNUSED)
{
    (void) before;
}

static void
do_filter(FILE *inputs)
{
    InitLEX(inputs);

    Action_attr  = class_attr(NAME_ACTION);
    Comment_attr = class_attr(NAME_COMMENT);
    Error_attr   = class_attr(NAME_ERROR);
    Ident_attr   = class_attr(NAME_IDENT2);
    Number_attr  = class_attr(NAME_NUMBER);
    String_attr  = class_attr(NAME_LITERAL);

    here_exp = 0;
    begin_state(NORMAL);
    RunLEX();
    flt_bfr_error();
    end_state();
}

#if NO_LEAKS
static void
free_filter(void)
{
    USE_LEXFREE;
    flt_free(&here_tag, &here_len);
}
#endif
