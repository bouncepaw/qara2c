#!/usr/bin/perl
use 5.010;
use warnings;
use Data::Dumper;
use experimental qw( switch );

 # This section contains parts important for both modes.

# Only subset of Markdown that is important for Qaraidel is checked.
sub line_type {
  given ($_) {
    when(/^\s*\#{1,6} /)  { 'header' }
    when(/^\s*```/)       { 'fence'  }
    when(/^\s*[\*\-\+] /) { 'bullet' }
    when(/^\s*\d+\. /)    { 'index'  }
    when(/^\s*\> /)       { 'quote'  }
    when(/^\s*$/)         { 'blank'  }
    default               { 'text'   } } }

my $should_weave = 0;

foreach (@ARGV) {
  given ($_) {
    when(/^-h|--help/) {
      say <<'EOK';
qara2c 0.1.0
  Convert Qaraidel document with C source code in Markdown.
  Released under terms of MIT license.

  See https://github.com/bouncepaw/qara2c

  Input text is read from stdin and generated text is output 
  to stdout. You can use shell's capabilities to read from
  file or to save into file:
    Read file input.md
      cat input.md | qara2c
      qara2c < input.md
    Write to file output.md
      qara2c > output.md
    You can combine them
      cat input.md | qara2c > output.md

Options
  -h, --help
    Print this message and exit.
  --doc, --weave
    Strip codeblocks and output what's left. This can be used
    as documentation.
EOK
      exit 0; }
    when(/^--doc|--weave/)     { $should_weave = 1; }
    default                    { die "Unknown option: $_" } } }
 # This section is about weave mode

if ($should_weave) {
  my $in_codelet = 0;
  my $would_be_nice_to_clean_blank = 0;
  while (<STDIN>) {
    given (line_type $_) {
      when('fence') {
        # Invert state.
        $in_codelet = $in_codelet ? 1 : 0;
        $would_be_nice_to_clean_blank = 1 unless $in_codelet; }
      when('quote') {
        $would_be_nice_to_clean_blank = 1; }
      when('blank') {
        print unless $would_be_nice_to_clean_blank }
      default {
        print } } }
  exit 0;
}

 # Start parsers for headers

# ∀ word: word ∈ header => header is special.
my %special_header_triggers =
  map { $_ => 1 } ( "fn", "struct", "enum", "union", "defconst", "defmacro" );

sub header_type {
  my ($text) = @_;
  my @words = split / /, $text;
  my $word = $words[0];
  if (exists $special_header_triggers{$word}) {
    return $word;
  }
  else {
    return 'normal';
  }
}

# (nest, text, mode)
sub parse_header {
  $_ =~ /^\s*(\#{1,6}) (.*)/;
  my $nest = length $1;
  my $text = $2;
  my $type = header_type $text;
  ($nest, $text, $type)
}

sub New {
  my ($nest_lvl, $header1, $htype) = @_;
  %obj =
  ( 'prologue' => '',        'epilogue' => '',
    'header1'  => $header1,  'header2'  => '',
    'header3'  => '',        'type'     => $htype,
    'nest_lvl' => $nest_lvl, 'body'     => '',
    'closed?'  => 0,         'postbody' => ' ' );
  %obj
}
 # Parsers for codelets

# (line on which parsing ended,
#  result of parsing)
sub parse_codelet {
  my $res = "";
  while (<STDIN>) {
    return ($_, $res) if 'fence' eq line_type $_;
    $res .= $_;
  }
}

sub ApplyCodelet {
  my ($obj_ref, $line) = @_;
  my ($stopline, $res) = parse_codelet $line;
  if ($obj_ref->{'type'} =~ /fn/) {
    $obj_ref->{'body'} .= $res
  } 
  elsif ($obj_ref->{'type'} =~ /defmacro/) {
    my @lines = split /\n/, $res;
    $obj_ref->{'body'} .= (join "\\\n", @lines) . "\n";
  }
  elsif ($obj_ref->{'type'} =~ m/struct|enum|union/) {
    $obj_ref->{'postbody'} .= $res;
  }
  else {
    $obj_ref->{'body'} .= $res;
  }
  $stopline
}

 # parsers for bulletlists

# Remove bullet and optional backticks from list item.
sub disbullet {
  $_ =~ /^\s*[\*\-\+] \`?([^\`]*)/; $1 }

# (line on which parsing ended,
#  result of parsing)
sub parse_bulleted_list_generic {
  my ($commencer, $joiner, $terminator, $first_line) = @_;
  my $res = $commencer . disbullet($first_line);

  while (<STDIN>) {
    my $type = line_type $_;
    return ($_, $res . $terminator) unless $type eq 'bullet' or $type eq 'text';
    $res .= $joiner . disbullet $_ if $type eq 'bullet';
  }
}

sub parse_bulleted_list_for_fn_or_defmacro {
  parse_bulleted_list_generic('(', ', ', ')', $_[0]) }
sub parse_bulleted_list_for_struct_or_enum {
  parse_bulleted_list_generic("    ", ",\n    ", "\n", $_[0]) }
sub parse_bulleted_list_for_defconst {
  parse_bulleted_list_generic("#define ", "\n#define ", "\n", $_[0]) }

sub ApplyBulletedList {
  my ($obj_ref, $line) = @_;
  if ($obj_ref->{'type'} =~ /^fn|defmacro/) {
    my ($stopline, $res) = parse_bulleted_list_for_fn_or_defmacro $line;
    $obj_ref->{'header2'} .= $res;
    return $stopline;
  }
  elsif ($obj_ref->{'type'} =~ /^struct|enum|union/) {
    my ($stopline, $res) = parse_bulleted_list_for_struct_or_enum $line;
    $obj_ref->{'body'} .= $res;
    return $stopline;
  }
  elsif ($obj_ref->{'type'} =~ /^defconst/) {
    my ($stopline, $res) = parse_bulleted_list_for_defconst $line;
    $obj_ref->{'body'} .= $res;
    return $stopline;
  }
  ''
}

 # Parsers for quotes

sub disquote {
  $_ =~ /^\s*\>\s*\`?([^\`]*)/; $1 }

sub parse_quote {
  my ($line) = @_;
  my $res = disquote($line) . "\n";

  while (<STDIN>) {
    return ($_, $res) if 'quote' ne line_type $_ ;
    $res .= disquote($_) . "\n";
  }
}

sub ApplyQuote {
  my ($obj_ref, $line) = @_;
  if ($obj_ref->{'type'} ne 'normal') {
    my ($stopline, $res) = parse_quote $line;
    $obj_ref->{'prologue'} = $res;
    return $stopline;
  }
  ''
}

 # Start main part
sub AsString {
  my ($hash_ref) = @_;
  return $hash_ref->{'body'} . $hash_ref->{'epilogue'}
  if ($hash_ref->{'type'} eq 'normal');

  if ($hash_ref->{'type'} =~ /fn|defmacro/ and not $hash_ref->{'header2'}) {
    $hash_ref->{'header2'} = '()'
  }
  if ($hash_ref->{'type'} =~ /struct|enum|union/) {
    return $hash_ref->{'prologue'} . $hash_ref->{'header1'} . " {\n"
    . $hash_ref->{'body'} . "}" . $hash_ref->{'postbody'} . ";\n"
    . $hash_ref->{'epilogue'}
  }
  elsif ($hash_ref->{'type'} =~ /defmacro/) {
    $hash_ref->{'header1'} =~ /defmacro (.*)/;
    my $true_header = $1;
    return $hash_ref->{'prologue'} . '#define ' . $true_header
    . $hash_ref->{'header2'} . "\\\n". $hash_ref->{'body'}
    . $hash_ref->{'epilogue'}
  }
  elsif ($hash_ref->{'type'} =~ /defconst/) {
    return $hash_ref->{'body'} . $hash_ref->{'epilogue'}
  }
  $hash_ref->{'prologue'} . $hash_ref->{'header1'} . $hash_ref->{'header2'}
  . $hash_ref->{'header3'} . $hash_ref->{'body'}
  . $hash_ref->{'epilogue'} . "\n"
}

# First, read everything into array of sections:
my @sections = ();
my $line = '';
while (<STDIN>) {
  my $type = line_type $_;
  if ($type eq 'header') { 
    my %new_section = New parse_header $_;
    push @sections, \%new_section;
  } 
  elsif ($type eq 'bullet') { 
    $line = ApplyBulletedList $sections[-1];
  }
  elsif ($type eq 'fence') {
    $line = ApplyCodelet $sections[-1];
  }
  elsif ($type eq 'quote') {
    $line = ApplyQuote $sections[-1];
  }
  elsif ($type eq 'text' or $type eq 'blank' or $type eq 'index') {}
  else { print "$type	$_" }
}

# Second, push fake section object. It is required by the alcorithm:
my %fake_section = New(0, 'normal', '');
push @sections, \%fake_section;

# Third, declare some tricky functons that will be used later:
sub close_sections {
  my ($sections_ref) = @_;
  # I used < for purpose.
  for ($i = 0; $i < $#$sections_ref; $i++) {
    $sections_ref->[$i]->{'closed?'} = 1 if
    $sections_ref->[$i]->{'nest_lvl'} >= $sections_ref->[$i + 1]->{'nest_lvl'}
  }
}

sub merge_sections {
  my ($sections_ref) = @_;
  my $changed_anything = 0;
  for ($i = 0; $i < $#$sections_ref; $i++) {
    if ($sections_ref->[$i]->{'closed?'} == 0
        and $sections_ref->[$i + 1]->{'closed?'}) {
      $sections_ref->[$i]->{'epilogue'} .= AsString $sections_ref->[$i + 1];
      undef $sections_ref->[$i + 1];
      $i++;
      $changed_anything = 1;
    }
  }
  $changed_anything
}

# Fourth, apply the tricky alcorithm until it's ok:
# print Dumper \@sections ;
my $changed_anything = 0;
do {
  close_sections \@sections;
  $changed_anything = merge_sections \@sections;
  @sections = grep defined, @sections;
} while ($changed_anything);

# Fifth, remove the fake sections object as it is not needed anymore:
pop @sections;

# Sixth, join and print everything.
print join '', map({ AsString $_ } @sections)
