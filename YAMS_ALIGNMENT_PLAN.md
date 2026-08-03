# Yams Alignment Plan

Goal: bring `swift-rapidyaml` to full API and behavioral parity with
[Yams](https://github.com/jpsim/Yams), backed by rapidyaml instead of libyaml.

Reference checkout used for this plan: `../Yams` — 21 source files / 5078 lines,
22 test files / 5968 lines.

Drafted 2026-08-03.

## Current state

| | |
|---|---|
| `Sources/YAMLNode/` | Obj-C++ wrapper over rapidyaml. Read-only tree, eagerly deep-copied into `NSString`/`NSArray`/`NSDictionary` at parse time. |
| `Sources/RapidYAML/YAMLDecoder.swift` | Structurally aligned with Yams' `Decoder.swift`. See "Already done" below. |
| Everything else | Not started. |

### Already done

`YAMLDecoder.swift` matches the shape of Yams' `Decoder.swift`:
public entry points, `Options`, `_decoder(from:userInfo:)` /
`processYAMLNode(_:from:with:)` helpers, `DecodableWithConfiguration` support,
`scalar()` / `construct()` helpers, `Decimal` + `URL` scalar decoding, and
mapping/sequence types as `typeMismatch` expectations.

Still missing from that file, pending the phases below: Yams' scalar parsing
semantics (Phase 4), merge keys and anchors (Phase 5), and `Decoder.mark`
(Phase 2).

## Architecture decision

**Node model: option B — a public Swift value-type `Node`, with `YAMLNode`
demoted to a bridging layer.**

Yams' public API is built around `Node`, a value-type enum: pattern matching,
value semantics, literal initialization, subscripts, and the
`Node.Mapping` / `Node.Sequence` / `Node.Scalar` / `Node.Alias` family.
Exposing the existing Obj-C `YAMLNode` class instead (option A) would be less
work but makes most of Yams' `Node` usage impossible to reproduce, so it was
rejected. Phases 2 onwards assume B.

---

## Phase 0 — Prerequisites

### 0.1 Parse errors must throw instead of aborting — **done**

rapidyaml's three default error callbacks all call `abort()`
(`src/c4/yml/common.cpp:45` onwards). Malformed YAML used to kill the process,
and the `catch` in `processYAMLNode` was dead code.

`YAMLNode.mm` now installs throwing callbacks via `ryml::set_callbacks()`
(`pfn_error_basic` / `pfn_error_parse` / `pfn_error_visit`, installed once on
first parse), catches the exception, and converts it to an `NSError` in
`YAMLNodeErrorDomain`. `initWithYAMLString:` became
`initWithYAMLString:error:`, which Swift imports as `init(yamlString:) throws`,
so `processYAMLNode`'s `catch` now runs and yields
`DecodingError.dataCorrupted`.

Parse errors carry `ErrorDataParse::ymlloc` in the `NSError` user info under
`YAMLNodeErrorLineKey` / `YAMLNodeErrorColumnKey` / `YAMLNodeErrorOffsetKey`
(line and column are one-based, offset zero-based) — this is what Phase 1's
`Context` and Phase 2's `Mark` consume. Basic and visit errors carry only the
message; their locations point into the rapidyaml C++ source, not the YAML.

---

## Phase 1 — Error type

| Target | Yams source |
|---|---|
| `YAMLError.swift` | `YamlError.swift` (200) |

Cases for `parser` / `scanner` / `composer` / `emitter` / `reader`, plus
`Context` (line, column, mark, description). Data comes from 0.1.

rapidyaml classifies errors more coarsely than libyaml, so this is a mapping
exercise, not a one-to-one port.

---

## Phase 2 — Node model

| Target | Yams source | rapidyaml support |
|---|---|---|
| `Node.swift` | (357) | tree traversal available |
| `Node.Mapping.swift` | (247) | **must preserve order** — see below |
| `Node.Sequence.swift` | (188) | available |
| `Node.Scalar.swift` | (124) | styles in `scalar_style.hpp` |
| `Node.Alias.swift` | (56) | `is_val_ref()` / `val_ref()` already exposed |
| `Tag.swift` | (172) | tag parsing/normalization in `tag.hpp` |
| `Anchor.swift` | (40) | `keyAnchor` / `valueAnchor` already exposed |
| `Mark.swift` | (39) | needs location tracking enabled in `ParserOptions`, then `Tree::location(Parser const&, id)` |

Ordering bug to fix here: `YAMLNode.mm:101-109` builds mappings into an
`NSMutableDictionary`, which loses key order. `Node.Mapping` is order-preserving
in Yams, and `allKeys` is currently non-deterministic as a result.

Also revisit the eager deep copy of the whole tree — with a Swift-side `Node`
the bridging layer can be much thinner.

---

## Phase 3 — Resolver

| Target | Yams source |
|---|---|
| `Resolver.swift` | `Resolver.swift` (175) |

Pure Swift regex, no libyaml dependency — portable nearly as-is.
Seven rules: `bool`, `int`, `float`, `null`, `timestamp`, `merge`, `value`.

---

## Phase 4 — Constructor / ScalarConstructible

| Target | Yams source |
|---|---|
| `Constructor.swift` | `Constructor.swift` (710) |

Also largely pure Swift and portable. This is where today's behavioral gap is
widest:

- `Bool` — `yes`/`no`/`on`/`off` and case variants (currently only `true`/`false`)
- `Int`/`UInt` — `0x`, `0o`, `0b`, `_` separators, sexagesimal (`SexagesimalConvertible`)
- `Double` — `.inf`, `-.inf`, `.nan`
- `Data` — base64 (`!!binary`)
- `Date` — YAML timestamp formats
- `UUID`, `Decimal`, `URL`
- `construct_mapping` / `construct_set` / `construct_omap` / `construct_pairs`
- `Node.any`, `Node.array(of:)`

Highest correctness-per-effort ratio of any phase.

---

## Phase 5 — Decoder completion

Closes the gaps left open in `YAMLDecoder.swift`, on top of Phases 2–4:

- Merge keys (`<<`) — either `mapping.flatten()` as Yams does, or rapidyaml's
  `Tree::resolve()`, which handles `<<` natively including the
  `<<: [*A, *B]` form (`src/c4/yml/reference_resolver.cpp:36`).
- Anchors and aliases — `AliasDereferencingStrategy.swift` (47) and
  `YamlAnchorProviding.swift` (26), plus injecting anchor/tag keys into keyed
  containers.
- `YamlTagProviding.swift` (26).
- `Decoder.mark`, once Phase 2 lands `Mark`.

---

## Phase 6 — Parser / top-level loading API

| Target | Yams source |
|---|---|
| `Parser.swift` | `Parser.swift` (486) |

`load`, `load_all`, `compose`, `compose_all`, `YamlSequence`, the `Parser` class,
and multi-document streams.

rapidyaml gives a STREAM root node for multi-document input, so this is a child
walk rather than libyaml's event stream — simpler than the Yams implementation.

---

## Phase 7 — Encoding / emitting

Nothing exists here yet.

| Target | Yams source | Notes |
|---|---|---|
| `YAMLEncoder.swift` | `Encoder.swift` (371) | |
| `Emitter.swift` | `Emitter.swift` (572) | rapidyaml has a full emitter (`emit.hpp`, `emit_options.hpp`) |
| `Representer.swift` | `Representer.swift` (350) | `NodeRepresentable` protocol family |
| `RedundancyAliasingStrategy.swift` | (148) | anchor generation while encoding |

The top-level `dump` / `serialize` functions belong to this phase.

---

## Phase 8 — Tests

Port Yams' suite (5968 lines), including `SpecTests.swift` (951) which runs the
YAML spec fixtures.

Suggested order: `ConstructorTests` → `NodeTests` → `SpecTests` → `EncoderTests`.
This suite is the only reliable way to verify the earlier phases.

---

## Order of work

Full alignment: **~~0.1~~ → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8**.

0.1 is done — it was the only process-crashing defect and was independent of
everything else. Next up is Phase 1.

If the scope ever needs to be cut back to "correct and usable" rather than
API-equivalent, **0.1 → 3 → 4 → 5 (merge keys)** delivers most of the practical
value without touching the Node model.
