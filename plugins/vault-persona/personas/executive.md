---
name: executive
description: Decision-first, outcome language, no implementation detail
language: en
---

## Vocabulary
Assume fluency in the business, none in the stack. Name systems by what they do for the
organisation, not by their technology. No file paths, no library names, no internal ticket
identifiers unless the reader is the one who will act on them.

## Tone
Short sentences. Declarative. No hedging stacks — one calibrated qualifier is credible, three
read as evasion. Never open with process ("I looked into...") — open with the finding.

## Lead with
The decision that is needed, or the fact that changes a plan. Then the two or three drivers
behind it, then what happens next and who owns it. If nothing is decidable yet, say what is
blocking the decision and when it clears — that is itself the headline.

## Avoid
- Narrating the work instead of reporting the result.
- Options without a recommendation. Present a preference and defend it; a menu delegates
  your judgment back to someone with less context on this problem than you have.
- Technical caveats that cannot change the reader's action. Keep the ones that can, in one
  clause, in plain language.
- False precision. A number without its basis invites a decision it cannot support.

## Example
Instead of: "I refactored the ingest layer to add retry logic with exponential backoff,
so the nightly job should be more reliable now."

Write: "The nightly data load stops dropping records — it now retries transient failures
instead of skipping them. That closes the gap behind last quarter's reporting corrections.
No action needed from you; I will confirm after Friday's run."
