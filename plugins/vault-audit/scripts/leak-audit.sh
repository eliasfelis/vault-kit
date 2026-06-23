#!/usr/bin/env bash
# leak-audit.sh - publish gate: fail if any scanned file matches a forbidden pattern.
# Usage: leak-audit.sh --path P [--pattern-file F] [--extra-patterns X] [--exclude REGEX]
# exit 0 clean / 1 leak(s) or unreadable file(s) / 2 a named pattern file is missing or holds an invalid regex / 64 bad usage.
# Scanner is perl (PCRE) so the existing .NET-style patterns (\b, \d, (?:...)) work unchanged.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
path=""
pattern_file="$script_dir/leak-patterns.txt"
extra_patterns=""
exclude='\.git/'

while [ $# -gt 0 ]; do
  case "$1" in
    --path)           [ $# -ge 2 ] || { echo "ERROR: --path needs a value" >&2; exit 64; }; path="$2"; shift 2 ;;
    --pattern-file)   [ $# -ge 2 ] || { echo "ERROR: --pattern-file needs a value" >&2; exit 64; }; pattern_file="$2"; shift 2 ;;
    --extra-patterns) [ $# -ge 2 ] || { echo "ERROR: --extra-patterns needs a value" >&2; exit 64; }; extra_patterns="$2"; shift 2 ;;
    --exclude)        [ $# -ge 2 ] || { echo "ERROR: --exclude needs a value" >&2; exit 64; }; exclude="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$path" ]; then echo "ERROR: --path is required" >&2; exit 64; fi
# A non-existent path must NOT report clean — that would give a security gate false assurance.
if [ ! -e "$path" ]; then echo "ERROR: path not found: $path" >&2; exit 64; fi
if [ ! -f "$pattern_file" ]; then echo "Pattern file not found: $pattern_file" >&2; exit 2; fi

combined="$(mktemp)"
filelist="$(mktemp)"
trap 'rm -f "$combined" "$filelist"' EXIT

# Load patterns (strip comment + blank lines). Fail-loud (exit 2) on a named-but-missing extra file.
grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$pattern_file" >> "$combined" || true
if [ -n "$extra_patterns" ]; then
  if [ ! -f "$extra_patterns" ]; then echo "ExtraPatterns file not found: $extra_patterns" >&2; exit 2; fi
  grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$extra_patterns" >> "$combined" || true
fi

# A publish gate that loaded zero patterns must NOT certify clean (it checked nothing).
if [ ! -s "$combined" ]; then echo "ERROR: no patterns loaded - refusing to certify (empty pattern set)" >&2; exit 2; fi

# Validate every pattern compiles as a perl regex. A broken pattern fails the gate LOUD and
# deterministically (exit 2) — never a silent skip or an undefined exit 255. Patterns are
# trimmed of surrounding whitespace so a stray trailing space can't silently disable one.
if ! perl -e '
  my $pf = shift;
  open(my $ph, "<", $pf) or die "patterns: $!";
  my $bad = 0;
  while (my $p = <$ph>) {
    $p =~ s/\r?\n$//; $p =~ s/^\s+//; $p =~ s/\s+$//; next unless length $p;
    eval { qr/$p/ };
    if ($@) { (my $m = $@) =~ s/\n.*//s; print STDERR "Invalid pattern: $p  ($m)\n"; $bad = 1; }
  }
  exit($bad ? 1 : 0);
' "$combined"; then
  echo "ERROR: invalid regex in pattern set (see above)" >&2
  exit 2
fi

# Build file list: single file as-is, else enumerate by extension and apply --exclude.
# -iname (case-insensitive) so an uppercase extension (README.MD, Config.JSON) is NOT skipped.
# An EMPTY --exclude must NOT drop every file (grep -vE '' matches all -> false-clean); only
# filter when a non-empty exclude regex is supplied.
enumerate() {
  find "$1" -type f \( \
      -iname '*.md' -o -iname '*.json' -o -iname '*.yaml' -o -iname '*.yml' \
      -o -iname '*.ps1' -o -iname '*.txt' -o -iname '*.js' -o -iname '*.ts' -o -iname '*.sh' \
      -o -iname '*.env' -o -iname '*.pem' -o -iname '*.key' -o -iname '*.cfg' \
      -o -iname '*.conf' -o -iname '*.ini' -o -iname '*.toml' -o -iname '*.xml' \
      -o -iname '*.html' -o -iname '*.py' -o -iname '*.rb' -o -iname '*.go' \
      -o -iname '*.java' -o -iname '*.csv' -o -iname '*.properties' -o -iname '*.tfvars' \
      -o -iname 'Dockerfile*' -o -iname 'Makefile' -o -iname 'LICENSE*' \
      -o -iname '.npmrc' -o -iname '.netrc' -o -iname '.dockercfg' -o -iname '.git-credentials' \
      -o -iname '.gitignore' -o -iname '.gitattributes' \
    \) 2>/dev/null
}

if [ -f "$path" ]; then
  printf '%s\n' "$path" > "$filelist"
else
  allfiles="$(mktemp)"
  enumerate "$path" > "$allfiles" || true
  total=$(wc -l < "$allfiles" | tr -d '[:space:]')
  if [ -n "$exclude" ]; then
    grep -vE "$exclude" "$allfiles" > "$filelist" || true
  else
    cp "$allfiles" "$filelist"
  fi
  kept=$(wc -l < "$filelist" | tr -d '[:space:]')
  rm -f "$allfiles"
  # An over-broad --exclude that drops every enumerated file would scan nothing and
  # falsely certify clean. A publish gate must never report clean having scanned 0 of N.
  if [ "${total:-0}" -gt 0 ] && [ "${kept:-0}" -eq 0 ]; then
    echo "ERROR: --exclude matched all $total enumerated files - nothing scanned, refusing to certify" >&2
    exit 2
  fi
fi

# Scan with perl (PCRE). An enumerated-but-unreadable file is surfaced as FAILED and fails the
# gate (fail-soft != silent) — it must never be silently skipped into a false 'clean'.
perl -e '
  my ($pf, $lf) = @ARGV;
  open(my $ph, "<", $pf) or die "patterns: $!";
  my @pats = grep { length } map { my $x = $_; $x =~ s/\r?\n$//; $x =~ s/^\s+//; $x =~ s/\s+$//; $x } <$ph>;
  close($ph);
  open(my $lh, "<", $lf) or die "filelist: $!";
  my $hits = 0;
  my $unreadable = 0;
  while (my $file = <$lh>) {
    $file =~ s/\r?\n$//;
    next unless length $file;
    my $fh;
    if (!open($fh, "<", $file)) {
      print "FAILED: cannot read $file: $!\n";
      $unreadable++;
      next;
    }
    while (my $line = <$fh>) {
      for my $p (@pats) {
        if ($line =~ /$p/) {
          my $t = $line; $t =~ s/\r?\n$//;
          print "LEAK $file:$.: $t\n";
          $hits++;
          last;
        }
      }
    }
    close($fh);
  }
  close($lh);
  if ($hits > 0)       { print "FAIL: $hits leak(s)\n"; exit 1; }
  if ($unreadable > 0) { print "FAIL: $unreadable unreadable file(s) - cannot certify clean\n"; exit 1; }
  print "OK: no leaks\n"; exit 0;
' "$combined" "$filelist"
