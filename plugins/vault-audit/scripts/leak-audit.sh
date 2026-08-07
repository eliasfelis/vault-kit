#!/usr/bin/env bash
# leak-audit.sh - publish gate: fail if any scanned file matches a forbidden pattern.
# Usage: leak-audit.sh --path P [--pattern-file F] [--extra-patterns X] [--exclude REGEX] [--tracked-only]
# exit 0 clean / 1 leak(s) or unreadable file(s) / 2 the gate could not do its job / 64 bad usage.
# exit 2 covers: a named pattern file missing or holding an invalid regex, an empty pattern set,
# an invalid or over-broad --exclude, zero files enumerated, AND any path that could not be
# line-scanned. Two shapes qualify: (a) a NUL byte ANYWHERE in the file (binary / UTF-16) --
# checked on every line, not only the first, because a file that is ASCII up front (a heading,
# YAML frontmatter) and UTF-16 afterwards is precisely the shape that would otherwise buy a
# clean verdict; (b) a path that is a DIRECTORY -- a submodule gitlink enumerated by
# --tracked-only opens fine, reads zero lines, and would otherwise be counted as a
# scanned-clean file while nothing inside it was ever read. An unscannable path is the same
# epistemic state as an unreadable one - the gate has not seen its content - so it never
# certifies clean. To declare such a path out of scope, --exclude it: an excluded path is
# never enumerated, and that exclusion is a recorded decision rather than a silent skip.
# --exclude ADDS to the built-in `\.git/` exclusion, it never replaces it: a user regex that
# silently re-opened .git/ would drag git internals (loose objects, packed refs) into the
# scan. Consequence, deliberately accepted: .git/ cannot be scanned by this tool at all -
# git internals are not publish surface, and the failure mode of trying is a loud exit 2
# ("--exclude matched all N"), never a quiet clean.
# A leading UTF-8 BOM is stripped from every pattern line (shipped set AND --extra-patterns)
# and from the first line of every scanned file. A BOM'd pattern COMPILES and then never
# matches - a silent hole, and Windows editors write one by default; a BOM'd document would
# likewise defeat any ^-anchored pattern.
# --tracked-only enumerates `git ls-files` instead of a filesystem walk: gitignored scratch is
# never scanned (no fragile --exclude for it) and ALL tracked files are checked, not an extension
# allowlist -> fail-closed by coverage. Requires --path to be (inside) a git repo.
# Scanner is perl (PCRE) so the existing .NET-style patterns (\b, \d, (?:...)) work unchanged.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
path=""
pattern_file="$script_dir/leak-patterns.txt"
extra_patterns=""
user_exclude=""
tracked_only=false

while [ $# -gt 0 ]; do
  case "$1" in
    --path)           [ $# -ge 2 ] || { echo "ERROR: --path needs a value" >&2; exit 64; }; path="$2"; shift 2 ;;
    --pattern-file)   [ $# -ge 2 ] || { echo "ERROR: --pattern-file needs a value" >&2; exit 64; }; pattern_file="$2"; shift 2 ;;
    --extra-patterns) [ $# -ge 2 ] || { echo "ERROR: --extra-patterns needs a value" >&2; exit 64; }; extra_patterns="$2"; shift 2 ;;
    --exclude)        [ $# -ge 2 ] || { echo "ERROR: --exclude needs a value" >&2; exit 64; }; user_exclude="$2"; shift 2 ;;
    --tracked-only)   tracked_only=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$path" ]; then echo "ERROR: --path is required" >&2; exit 64; fi
# A non-existent path must NOT report clean — that would give a security gate false assurance.
if [ ! -e "$path" ]; then echo "ERROR: path not found: $path" >&2; exit 64; fi
# --tracked-only enumerates a repo; it says nothing about a single file. Silently ignoring it
# would let a caller believe the tracked-only contract applied when it did not.
if [ "$tracked_only" = true ] && [ -f "$path" ]; then
  echo "ERROR: --tracked-only needs a directory to enumerate; --path is a single file: $path" >&2
  echo "Drop --tracked-only to scan one file, or point --path at the repository." >&2
  exit 64
fi
if [ ! -f "$pattern_file" ]; then echo "Pattern file not found: $pattern_file" >&2; exit 2; fi

# The built-in `\.git/` exclusion is ALWAYS in force; --exclude is ADDED to it (alternation),
# never substituted for it. Replacing it let any --exclude silently re-enumerate .git/. An
# empty --exclude therefore still leaves .git/ excluded instead of switching the filter off.
if [ -n "$user_exclude" ]; then
  exclude="(\.git/)|($user_exclude)"
else
  exclude='\.git/'
fi

combined="$(mktemp)"
filelist="$(mktemp)"
trap 'rm -f "$combined" "$filelist"' EXIT

# Load patterns: strip a leading UTF-8 BOM from EVERY line, then drop comment + blank lines.
# The BOM strip is the single point for both layers and it comes FIRST, before the comment
# filter, for two reasons: a BOM'd pattern compiles clean and then matches nothing (the qr//
# validator below proves a pattern COMPILES, not that it is the one the author typed), and a
# BOM'd `#` comment would stop looking like a comment and become a live pattern. Windows
# editors add the BOM by default, and the layer that gets hand-edited most is the user's own
# --extra-patterns file - the one holding their instance literals.
load_patterns() {
  perl -ne 's/^\xEF\xBB\xBF//; next if /^\s*#/ || /^\s*$/; print' "$1"
}

# Fail-loud (exit 2) on a named-but-missing extra file.
load_patterns "$pattern_file" >> "$combined" || true
if [ -n "$extra_patterns" ]; then
  if [ ! -f "$extra_patterns" ]; then echo "ExtraPatterns file not found: $extra_patterns" >&2; exit 2; fi
  load_patterns "$extra_patterns" >> "$combined" || true
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
#
# The list is DELIBERATELY BROAD, and it should stay that way: a secret-bearing file that is
# never enumerated is a silent false-clean, and the "0 files" guard below only fires when
# NOTHING matched - one clean .md in the directory is enough to hide fifteen unscanned
# .tf / .env.local / credentials / .sql files behind it. It is still an ALLOWLIST (the gate
# does not go walking into binaries); when in doubt, add the extension here, or use
# --tracked-only, which drops the allowlist entirely and checks every tracked file.
enumerate() {
  find "$1" -type f \( \
      -iname '*.md' -o -iname '*.mdx' -o -iname '*.txt' -o -iname '*.log' -o -iname '*.bak' \
      -o -iname '*.json' -o -iname '*.jsonl' -o -iname '*.yaml' -o -iname '*.yml' \
      -o -iname '*.xml' -o -iname '*.html' -o -iname '*.csv' -o -iname '*.sql' \
      -o -iname '*.toml' -o -iname '*.ini' -o -iname '*.cfg' -o -iname '*.conf' \
      -o -iname '*.properties' -o -iname '*.sh' -o -iname '*.ps1' \
      -o -iname '*.js' -o -iname '*.mjs' -o -iname '*.cjs' -o -iname '*.ts' \
      -o -iname '*.jsx' -o -iname '*.tsx' \
      -o -iname '*.py' -o -iname '*.rb' -o -iname '*.go' -o -iname '*.rs' \
      -o -iname '*.php' -o -iname '*.java' \
      -o -iname '*.tf' -o -iname '*.tfvars' -o -iname '*.tfstate' \
      -o -iname '*.pem' -o -iname '*.key' \
      -o -iname '*.env' -o -iname '.env.*' -o -iname '*.env.*' \
      -o -iname 'credentials' -o -iname 'credentials.*' \
      -o -iname 'Dockerfile*' -o -iname 'Makefile' -o -iname 'Procfile*' -o -iname 'LICENSE*' \
      -o -iname '.npmrc' -o -iname '.netrc' -o -iname '.dockercfg' -o -iname '.git-credentials' \
      -o -iname '.gitignore' -o -iname '.gitattributes' \
    \) 2>/dev/null
}

if [ -f "$path" ]; then
  printf '%s\n' "$path" > "$filelist"
else
  allfiles="$(mktemp)"
  if [ "$tracked_only" = true ]; then
    if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
      echo "ERROR: --tracked-only requires a git repo at: $path" >&2
      rm -f "$allfiles"; exit 2
    fi
    # ls-files paths are repo-relative; prefix the repo path so perl can open them.
    # core.quotePath=false: git C-quotes non-ASCII paths by default, which would make
    # perl try to open the QUOTED string -> false "unreadable" on clean non-ASCII names.
    base="${path%/}"
    git -C "$path" -c core.quotePath=false ls-files 2>/dev/null | while IFS= read -r rel; do
      [ -n "$rel" ] && printf '%s/%s\n' "$base" "$rel"
    done > "$allfiles" || true
  else
    enumerate "$path" > "$allfiles" || true
  fi
  total=$(wc -l < "$allfiles" | tr -d '[:space:]')
  # $exclude is never empty (it always carries at least the built-in `\.git/`), so the filter
  # always runs. grep rc: 0 = lines kept, 1 = none kept, >=2 = grep itself failed (invalid
  # regex). Swallowing rc 2 would empty the file list and surface as "--exclude matched all N
  # files" - a true statement about the wrong cause. Name the real one, and name it with the
  # regex the USER typed, not the combined form they never wrote.
  grep -vE "$exclude" "$allfiles" > "$filelist"
  grep_rc=$?
  if [ "$grep_rc" -ge 2 ]; then
    echo "ERROR: invalid --exclude regex: ${user_exclude:-$exclude}" >&2
    rm -f "$allfiles"; exit 2
  fi
  kept=$(wc -l < "$filelist" | tr -d '[:space:]')
  rm -f "$allfiles"
  # An over-broad --exclude that drops every enumerated file would scan nothing and
  # falsely certify clean. A publish gate must never report clean having scanned 0 of N.
  if [ "${total:-0}" -gt 0 ] && [ "${kept:-0}" -eq 0 ]; then
    echo "ERROR: --exclude matched all $total enumerated files - nothing scanned, refusing to certify" >&2
    exit 2
  fi
  # Zero files AT ALL is equally non-certifiable (empty dir, no matching extensions,
  # --tracked-only with nothing tracked): a gate that scanned nothing knows nothing.
  if [ "${kept:-0}" -eq 0 ]; then
    echo "ERROR: no files to scan under: $path - refusing to certify (0 files)" >&2
    exit 2
  fi
fi

# Scan with perl (PCRE). An enumerated-but-unreadable file is surfaced as FAILED and fails the
# gate (fail-soft != silent) — it must never be silently skipped into a false 'clean'.
# Also checks each FILENAME (path relative to the scan root — an absolute prefix such as
# a Windows user-profile dir must not trip the user-profile pattern on every file): instance
# literals leak via paths too, not just content. NUL-containing files (binary, or
# UTF-16 — the PowerShell `>` default encoding) cannot be line-matched, and neither can a
# DIRECTORY entry (a submodule gitlink from `git ls-files`): both are listed VISIBLY under
# UNSCANNABLE and the run exits 2, because a leak hiding in an unscanned path is exactly what
# a gate exists to catch. The NUL probe runs on EVERY line, not just the first — an ASCII
# heading or a YAML frontmatter block in front of a UTF-16 body must not buy a clean verdict.
# The counts in every verdict line are scanned AND unscannable, never one alone.
if [ -f "$path" ]; then dirbase=""; else dirbase="${path%/}"; fi
perl -e '
  my ($pf, $lf, $base) = @ARGV;
  open(my $ph, "<", $pf) or die "patterns: $!";
  my @pats = grep { length } map { my $x = $_; $x =~ s/\r?\n$//; $x =~ s/^\s+//; $x =~ s/\s+$//; $x } <$ph>;
  close($ph);
  open(my $lh, "<", $lf) or die "filelist: $!";
  my $fname_hits = 0;
  my $line_hits = 0;
  my %leak_files;
  my $unreadable = 0;
  my $scanned = 0;
  my @skipped;
  FILE: while (my $file = <$lh>) {
    $file =~ s/\r?\n$//;
    next unless length $file;
    my $rel = $file;
    if (length $base) { $rel =~ s/^\Q$base\E\/*//; } else { $rel =~ s{^.*/}{}; }
    for my $p (@pats) {
      if ($rel =~ /$p/) {
        print "LEAK (filename) $file\n";
        $fname_hits++;
        $leak_files{$file} = 1;
        last;
      }
    }
    # A DIRECTORY opens without error and reads zero lines, so it would be tallied as one more
    # scanned-clean file while nothing inside it was ever read. `git ls-files` emits exactly
    # such an entry for a submodule gitlink. Never certify a path whose content was not read.
    if (-d $file) {
      print "SKIP (directory / submodule gitlink - contents not scanned) $file\n";
      push @skipped, "$file  [directory/gitlink]";
      next FILE;
    }
    my $fh;
    if (!open($fh, "<", $file)) {
      print "FAILED: cannot read $file: $!\n";
      $unreadable++;
      next;
    }
    $scanned++;
    while (my $line = <$fh>) {
      # A NUL on ANY line, not only line 1. A line-1-only probe certifies a file that is
      # ASCII up front (a heading, YAML frontmatter) and UTF-16 / binary afterwards - the
      # ASCII prefix is free to write, so it is a one-line bypass of the whole gate.
      if ($line =~ /\x00/) {
        print "SKIP (binary/UTF-16, not line-scanned) $file\n";
        push @skipped, "$file  [binary/UTF-16]";
        $scanned--;
        close($fh);
        next FILE;
      }
      # A UTF-8 BOM sits in front of the first character and would defeat any ^-anchored
      # pattern; strip it so a document carrying one is scanned like any other.
      if ($. == 1) { $line =~ s/^\xEF\xBB\xBF//; }
      for my $p (@pats) {
        if ($line =~ /$p/) {
          my $t = $line; $t =~ s/\r?\n$//;
          print "LEAK $file:$.: $t\n";
          $line_hits++;
          $leak_files{$file} = 1;
          last;
        }
      }
    }
    close($fh);
  }
  close($lh);
  my $hits  = $fname_hits + $line_hits;
  my $nskip = scalar @skipped;
  if ($nskip) {
    print "UNSCANNABLE (no line scan possible - binary/UTF-16, or a directory/gitlink entry):\n";
    print "  - $_\n" for @skipped;
  }
  my $cover = "$scanned file(s) scanned, $nskip unscannable";
  if ($hits > 0) {
    my $nfiles = scalar keys %leak_files;
    print "FAIL: $hits leak finding(s) in $nfiles file(s) - $fname_hits filename, $line_hits content line(s); $cover\n";
    exit 1;
  }
  if ($unreadable > 0) { print "FAIL: $unreadable unreadable file(s) - cannot certify clean ($cover)\n"; exit 1; }
  if ($nskip > 0) {
    print "FAIL: $nskip unscannable path(s) - cannot certify clean ($cover). Convert binary/UTF-16 files to UTF-8; --exclude any path (a submodule gitlink, a vendored blob) you mean to put out of scope on the record.\n";
    exit 2;
  }
  print "OK: no leaks ($cover)\n"; exit 0;
' "$combined" "$filelist" "$dirbase"
