// ruby.rl written by Mitchell Foral. mitchell<att>caladbolg<dott>net

/************************* Required for every parser *************************/
#include "ragel_parser_macros.h"

// the name of the language
const char *RUBY_LANG = "ruby";

// the languages entities
const char *ruby_entities[] = {
  "space", "comment", "string", "any"
};

// constants associated with the entities
enum {
  RUBY_SPACE = 0, RUBY_COMMENT, RUBY_STRING, RUBY_ANY
};

// do not change the following variables

// used for newlines
#define NEWLINE -1

// used for newlines inside patterns like strings and comments that can have
// newlines in them
#define INTERNAL_NL -2

// required by Ragel
int cs, act;
char *p, *pe, *eof, *ts, *te;

// used for calculating offsets from buffer start for start and end positions
char *buffer_start;
#define cint(c) ((int) (c - buffer_start))

// state flags for line and comment counting
int whole_line_comment;
int line_contains_code;

// the beginning of a line in the buffer for line and comment counting
char *line_start;

// state variable for the current entity being matched
int entity;

/*****************************************************************************/

%%{
  machine ruby;
  write data;
  include common "common.rl";

  # Line counting machine

  action ruby_ccallback {
    switch(entity) {
    case RUBY_SPACE:
      ls
      break;
    case RUBY_ANY:
      code
      break;
    case INTERNAL_NL:
      std_internal_newline(RUBY_LANG)
      break;
    case NEWLINE:
      std_newline(RUBY_LANG)
    }
  }

  ruby_line_comment = '#' @comment nonnewline*;
  # TODO: detect =begin and =end at start of their lines
  # Can't do that now because using 'when starts_line' fails a Ragel assertion.
  ruby_block_comment =
    '=begin' @comment (
      newline %{ entity = INTERNAL_NL; } %ruby_ccallback
      |
      ws
      |
      (nonnewline - ws) @comment
    )* :>> '=end';
  ruby_comment = ruby_line_comment | ruby_block_comment;

  ruby_sq_str =
    '\'' @code (
      newline %{ entity = INTERNAL_NL; } %ruby_ccallback
      |
      ws
      |
      [^\t '\\] @code
      |
      '\\' nonnewline @code
    )* '\'' @code;
  ruby_dq_str =
    '"' @code (
      newline %{ entity = INTERNAL_NL; } %ruby_ccallback
      |
      ws
      |
      [^\t "\\] @code
      |
      '\\' nonnewline @code
    )* '"' @code;
  # TODO: true literal string detection
  # Turns out any non-alphanum char can be after the initial '%' for a literal
  # string. I only have '(', '[', '{' for now because they are common(?). Their
  # respective closing characters need to be escaped though, which is not
  # accurate; only the single closing character needs to be escaped in a literal
  # string.
  # We need to detect which non-alphanum char opens a literal string, somehow
  # let Ragel know what it is (currently unsupported), and put its respective
  # closing char in the literal string below.
  ruby_lit_str =
    '%' @code [qQ]? [(\[{] (
      newline %{ entity = INTERNAL_NL; } %ruby_ccallback
      |
      ws
      |
      [^\t )\]}\\] @code
      |
      '\\' nonnewline @code
    )* [)\]}] @code;
  ruby_cmd_str =
    '`' @code (
      newline %{ entity = INTERNAL_NL; } %ruby_ccallback
      |
      ws
      |
      [^\t `\\] @code
      |
      '\\' nonnewline @code
    )* '`' @code;
  ruby_regex =
    '/' @code (
      newline %{ entity = INTERNAL_NL; } %ruby_ccallback
      |
      ws
      |
      [^\t /\\] @code
      |
      '\\' nonnewline @code
    )* '/' @code;
  # TODO: true literal array and command detection
  # See TODO above about literal string detection
  ruby_lit_other =
    '%' @code [wrx] [(\[{] (
      newline %{ entity = INTERNAL_NL; } %ruby_ccallback
      |
      ws
      |
      [^\t )\]}\\] @code
      |
      '\\' nonnewline @code
    )* [)\]}] @code;
  # TODO: heredoc detection
  # This is impossible with current Ragel. We need to extract what the end
  # delimiter should be from the heredoc and search up to it on a new line.
  # ruby_heredoc =
  ruby_string =
    ruby_sq_str | ruby_dq_str | ruby_lit_str | ruby_cmd_str | ruby_regex |
    ruby_lit_other;

  ruby_line := |*
    spaces        ${ entity = RUBY_SPACE; } => ruby_ccallback;
    ruby_comment;
    ruby_string;
    newline       ${ entity = NEWLINE;    } => ruby_ccallback;
    ^space        ${ entity = RUBY_ANY;   } => ruby_ccallback;
  *|;

  # Entity machine

  action ruby_ecallback {
    callback(RUBY_LANG, entity, cint(ts), cint(te));
  }

  ruby_entity := 'TODO:';
}%%

/* Parses a string buffer with Ruby code.
 *
 * @param *buffer The string to parse.
 * @param length The length of the string to parse.
 * @param count Integer flag specifying whether or not to count lines. If yes,
 *   uses the Ragel machine optimized for counting. Otherwise uses the Ragel
 *   machine optimized for returning entity positions.
 * @param *callback Callback function. If count is set, callback is called for
 *   every line of code, comment, or blank with 'lcode', 'lcomment', and
 *   'lblank' respectively. Otherwise callback is called for each entity found.
 */
void parse_ruby(char *buffer, int length, int count,
  void (*callback) (const char *lang, const char *entity, int start, int end)
  ) {
  p = buffer;
  pe = buffer + length;
  eof = pe;

  buffer_start = buffer;
  whole_line_comment = 0;
  line_contains_code = 0;
  line_start = 0;
  entity = 0;

  %% write init;
  cs = (count) ? ruby_en_ruby_line : ruby_en_ruby_entity;
  %% write exec;

  // if no newline at EOF; callback contents of last line
  if (count) { process_last_line(RUBY_LANG) }
}
