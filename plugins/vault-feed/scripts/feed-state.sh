#!/usr/bin/env bash
# feed-state.sh - per-source run-state for vault-feed (last-seen watermark + outcome).
#
#   read    <state_dir> <slug>                        -> prints last_seen (0 if unknown)
#   write   <state_dir> <slug> <epoch|keep> <outcome> -> upserts one entry
#   summary <state_dir>                               -> "ok=N failed=N failed_slugs=a,b"
#
# <slug> must be URL-safe: letters, digits, '.', '_' and '-' only. A slug is
# interpolated into JSON verbatim, so anything else (quote, brace, space, control
# character) is REJECTED rather than escaped - a quote would otherwise inject
# sibling entries into the state file.
#
# epoch is a non-negative integer, or the literal `keep` to leave the existing
# last_seen untouched (0 when the slug is new) while still recording the outcome.
# A quiet-but-healthy source MUST be written with `keep`: writing 0 would erase
# the watermark and re-surface every past item on the next pull.
#
# All three subcommands share ONE JSON parser (json_state below), so read, summary
# and write can never disagree about what the file says: a brace inside a string
# value, a nested object, or an extra field is understood identically by all of
# them. last_seen is read TOLERANTLY - an unquoted integer, or a quoted one left
# by a foreign writer - and is always written back unquoted, exactly once.
#
# The state file must be a well-formed JSON object of shape
#   { "<slug>": { ... }, ... }
# Anything else is REFUSED (exit 65, file left untouched) rather than salvaged;
# a file that merely contains a brace pair is not a state file. Within an entry
# the parser stays permissive: unknown/extra fields survive verbatim, and an entry
# whose last_seen/outcome cannot be read passes through byte-for-byte rather than
# being dropped or rewritten.
#
# Concurrency: single-run-safe only. One run is atomic (write builds a temp file
# and mv's it into place, so a reader never sees a half-written file), but two
# OVERLAPPING pull runs read-modify-write the same file and the later mv wins,
# silently discarding the earlier run's watermarks. There is no lock by design -
# do not run two pulls against one state directory at the same time.
#
# Exit codes: 0 ok | 2 bad usage | 64 bad argument value | 65 unparseable state file.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: feed-state.sh read    <state_dir> <slug>
       feed-state.sh write   <state_dir> <slug> <epoch|keep> <outcome>
       feed-state.sh summary <state_dir>
USAGE
}

# ---------------------------------------------------------------------------
# The one parser. json_state <mode> <state_file> [args...]
#
#   read    <file> <slug>
#   write   <file> <slug> <epoch|keep> <outcome>   -> canonical JSON on stdout
#   summary <file>
#
# A real (small) JSON parser rather than a regex: the regex form was blind to
# braces inside string values and to nested objects, so read/summary lost a
# watermark that write had preserved - the state could never self-heal.
# ---------------------------------------------------------------------------
json_state() {
  perl - "$@" <<'PERL'
use strict;
use warnings;
no warnings 'recursion';   # a deeply nested value is data, not a bug to warn about

my $MODE = shift(@ARGV); $MODE = '' unless defined $MODE;
my $FILE = shift(@ARGV); $FILE = '' unless defined $FILE;

sub bail {
  my ($why) = @_;
  my $tail = ($MODE eq 'write') ? 'refusing to rewrite' : 'refusing to guess';
  print STDERR "feed-state.sh: state file is not a well-formed JSON object ($why); $tail\n";
  exit 65;
}

my $S = '';
{
  open(my $fh, '<', $FILE) or bail('cannot be opened');
  local $/;
  my $data = <$fh>;
  close($fh);
  $S = defined($data) ? $data : '';
}

my %ESC = ('"' => '"', '\\' => '\\', '/' => '/',
           'b' => "\b", 'f' => "\f", 'n' => "\n", 'r' => "\r", 't' => "\t");

sub jdecode {
  my ($raw) = @_;
  $raw =~ s{\\(u[0-9a-fA-F]{4}|.)}{
    my $e = $1;
    ($e =~ /^u/) ? chr(hex(substr($e, 1))) : (exists $ESC{$e} ? $ESC{$e} : $e)
  }gse;
  return $raw;
}

# Every parse step is anchored with \G ... /gc, so a failed alternative leaves
# pos() where it was and the next alternative can try from the same spot.
sub sws { $S =~ /\G[ \t\r\n]*/gc; return }

sub pstr {   # the opening quote is already consumed; returns the RAW inner text
  $S =~ /\G((?:[^"\\\x00-\x1F]|\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4}))*)"/gc
    or bail('malformed string');
  return $1;
}

sub pval {
  sws();
  my $start = pos($S) // 0;
  my $node;
  if    ($S =~ /\G\{/gc) { $node = pobj() }
  elsif ($S =~ /\G\[/gc) { $node = parr() }
  elsif ($S =~ /\G"/gc)  { $node = { t => 'str', v => jdecode(pstr()) } }
  elsif ($S =~ /\G(-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?)/gc)
                         { $node = { t => 'num', v => $1 } }
  elsif ($S =~ /\G(true|false|null)/gc)
                         { $node = { t => 'lit', v => $1 } }
  else                   { bail('unexpected token') }
  $node->{raw} = substr($S, $start, (pos($S) // 0) - $start);
  return $node;
}

sub pobj {   # the opening brace is already consumed
  my @mem;
  sws();
  return { t => 'obj', mem => \@mem } if $S =~ /\G\}/gc;
  while (1) {
    sws();
    $S =~ /\G"/gc or bail('expected a quoted key');
    my $kraw = pstr();
    sws();
    $S =~ /\G:/gc or bail('expected ":" after a key');
    my $v = pval();
    push @mem, { kraw => $kraw, key => jdecode($kraw), val => $v };
    sws();
    next if $S =~ /\G,/gc;
    last if $S =~ /\G\}/gc;
    bail('expected "," or "}"');
  }
  return { t => 'obj', mem => \@mem };
}

sub parr {   # the opening bracket is already consumed; contents kept only as raw
  sws();
  return { t => 'arr' } if $S =~ /\G\]/gc;
  while (1) {
    pval();
    sws();
    next if $S =~ /\G,/gc;
    last if $S =~ /\G\]/gc;
    bail('expected "," or "]"');
  }
  return { t => 'arr' };
}

pos($S) = 0;
sws();
$S =~ /\G\{/gc or bail('top level is not an object');
my $ROOT = pobj();
sws();
bail('trailing content after the top-level object') unless (pos($S) // 0) == length($S);

my %seen;
for my $m (@{ $ROOT->{mem} }) {
  # kraw (source text), never the decoded key, in anything printed: a decoded
  # \uXXXX escape would be a wide character on a byte-oriented handle.
  bail("entry \"$m->{kraw}\" is not an object") unless $m->{val}{t} eq 'obj';
  bail("duplicate top-level key \"$m->{kraw}\"") if $seen{ $m->{key} }++;
}

# Per entry: last_seen (tolerant, last member wins), outcome, and every OTHER
# member kept as verbatim source text so a rewrite cannot lose or mangle it.
sub fields {
  my ($obj) = @_;
  my ($ls, $oc, $oc_seen, @extra) = (undef, undef, 0);
  for my $m (@{ $obj->{mem} }) {
    my $v = $m->{val};
    if ($m->{key} eq 'last_seen') {
      if    ($v->{t} eq 'num' && $v->{v} =~ /^[0-9]+$/) { $ls = $v->{v} }
      elsif ($v->{t} eq 'str' && $v->{v} =~ /^[0-9]+$/) { $ls = $v->{v} }
      else                                              { $ls = undef }
      $ls =~ s/^0+(?=[0-9])// if defined $ls;
    } elsif ($m->{key} eq 'outcome') {
      $oc_seen = 1;
      $oc = ($v->{t} eq 'str') ? $v->{v} : undef;
    } else {
      push @extra, '"' . $m->{kraw} . '":' . $v->{raw};
    }
  }
  return ($ls, $oc, $oc_seen, \@extra);
}

if ($MODE eq 'read') {
  my $slug = shift(@ARGV); $slug = '' unless defined $slug;
  my $out = 0;
  for my $m (@{ $ROOT->{mem} }) {
    next unless $m->{key} eq $slug;
    my ($ls) = fields($m->{val});
    $out = defined($ls) ? $ls : 0;
  }
  print "$out\n";
  exit 0;
}

if ($MODE eq 'summary') {
  my ($ok, $failed, @fs) = (0, 0);
  for my $m (@{ $ROOT->{mem} }) {
    # An entry with no outcome has no run to report; an outcome we cannot read
    # counts as FAILED - never silently absent from the report.
    my ($ls, $oc, $oc_seen) = fields($m->{val});
    next unless $oc_seen;
    if (defined($oc) && $oc eq 'ok') { $ok++ }
    else { $failed++; push @fs, $m->{kraw} }
  }
  print "ok=$ok failed=$failed failed_slugs=" . join(",", @fs) . "\n";
  exit 0;
}

if ($MODE eq 'write') {
  my ($SLUG, $EPOCH, $OUTCOME) = splice(@ARGV, 0, 3);
  my (@rows, $hit);
  for my $m (@{ $ROOT->{mem} }) {
    my ($ls, $oc, $oc_seen, $extra) = fields($m->{val});
    if ($m->{key} eq $SLUG) {
      $hit = 1;
      my $ne = ($EPOCH eq 'keep') ? (defined($ls) ? $ls : 0) : $EPOCH;
      $ne =~ s/^0+(?=[0-9])//;
      push @rows, [ $SLUG, '"' . $SLUG . '":{"last_seen":' . $ne
                           . ',"outcome":"' . $OUTCOME . '"'
                           . join('', map { ',' . $_ } @$extra) . '}' ];
    } elsif (defined($ls) && defined($oc) && $oc =~ /^\w+$/) {
      push @rows, [ $m->{key}, '"' . $m->{kraw} . '":{"last_seen":' . $ls
                               . ',"outcome":"' . $oc . '"'
                               . join('', map { ',' . $_ } @$extra) . '}' ];
    } else {
      # Unreadable last_seen/outcome: pass the entry through byte-for-byte.
      push @rows, [ $m->{key}, '"' . $m->{kraw} . '":' . $m->{val}{raw} ];
    }
  }
  unless ($hit) {
    my $ne = ($EPOCH eq 'keep') ? 0 : $EPOCH;
    $ne =~ s/^0+(?=[0-9])//;
    push @rows, [ $SLUG, '"' . $SLUG . '":{"last_seen":' . $ne
                         . ',"outcome":"' . $OUTCOME . '"}' ];
  }
  print '{' . join(',', map { $_->[1] } sort { $a->[0] cmp $b->[0] } @rows) . "}\n";
  exit 0;
}

print STDERR "feed-state.sh: internal error: unknown mode '$MODE'\n";
exit 2;
PERL
}

cmd="${1:-}"

case "$cmd" in
  read)
    [ "$#" -eq 3 ] || { usage; exit 2; }
    dir="$2"; slug="$3"; state="$dir/state.json"
    [ -s "$state" ] || { echo 0; exit 0; }
    json_state read "$state" "$slug"
    ;;

  write)
    [ "$#" -eq 5 ] || { usage; exit 2; }
    dir="$2"; slug="$3"; epoch="$4"; outcome="$5"; state="$dir/state.json"

    # The slug is interpolated into JSON verbatim (never escaped), so it is
    # charset-checked here: a quote in a slug would inject sibling entries and
    # leave the file unparseable for every later run.
    case "$slug" in
      ''|*[!A-Za-z0-9._-]*)
        echo "feed-state.sh: slug must be URL-safe (letters, digits, '.', '_', '-'), got '$slug'" >&2
        exit 64 ;;
      *) ;;
    esac
    case "$epoch" in
      keep) ;;
      ''|*[!0-9]*)
        echo "feed-state.sh: epoch must be a non-negative integer or 'keep', got '$epoch'" >&2
        exit 64 ;;
      *) ;;
    esac
    # outcome is interpolated into JSON verbatim too, and must stay a single word
    # so the canonical rewrite never has to escape it and summary can re-read it.
    case "$outcome" in
      ''|*[!A-Za-z0-9_]*)
        echo "feed-state.sh: outcome must be a word (letters, digits, underscore), got '$outcome'" >&2
        exit 64 ;;
      *) ;;
    esac

    mkdir -p "$dir"
    [ -s "$state" ] || echo '{}' > "$state"

    tmp="$state.tmp.$$"
    json_state write "$state" "$slug" "$epoch" "$outcome" > "$tmp" \
      || { rc=$?; rm -f "$tmp"; exit "$rc"; }
    mv -f "$tmp" "$state"
    ;;

  summary)
    [ "$#" -eq 2 ] || { usage; exit 2; }
    dir="$2"; state="$dir/state.json"
    [ -s "$state" ] || { echo "ok=0 failed=0 failed_slugs="; exit 0; }
    json_state summary "$state"
    ;;

  *) usage; exit 2;;
esac
