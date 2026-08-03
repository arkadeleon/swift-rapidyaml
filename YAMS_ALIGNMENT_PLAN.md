# Yams Alignment Plan

Goal: bring `swift-rapidyaml` to full API and behavioral parity with
[Yams](https://github.com/jpsim/Yams), backed by rapidyaml instead of libyaml.

Reference checkout used for this plan: `../Yams` — 21 source files / 5078 lines,
22 test files / 5968 lines.

Drafted 2026-08-03.

## Current state

This section describes the state the plan was drafted against. Phases 0.1
through 5 have since landed; see each phase for what changed.

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

`YAMLError` moved out of `YAMLDecoder.swift` into its own file in Phase 1, the
decoder was retargeted from `YAMLNode` onto `Node` in Phase 2, gained Yams'
scalar parsing semantics in Phase 4, and merge keys and anchor injection in
Phase 5. It is now complete.

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

## Phase 1 — Error type — **done**

| Target | Yams source |
|---|---|
| `YAMLError.swift` | `YamlError.swift` (200) |
| `Mark.swift` | `Mark.swift` (39) — pulled forward from Phase 2, `YAMLError` needs it |
| `String+RapidYAML.swift` | `String+Yams.swift` (81) — line/column helpers behind `description` |

`YAMLError` carries the full Yams case list, and `description` is a verbatim
port — its output was diffed against real Yams output for every case
(`errorDescriptionsMatchYams`).

The mapping from 0.1's `NSError` is deliberately narrow, because rapidyaml
classifies errors more coarsely than libyaml:

- parse error with a location → `.parser`, mark from `ErrorDataParse::ymlloc`
- parse error without one → `.reader`, offset only
- basic / visit error → `.reader`, no location at all

So `.scanner` is never produced — rapidyaml has no equivalent of libyaml's
separate scanner stage. `.composer` comes from our own composer rather than
from rapidyaml (Phase 2). `context` is always `nil`: there is no counterpart to
libyaml's "while parsing a block mapping" half of the message.

One conversion is needed at the boundary: rapidyaml counts columns in bytes,
`Mark` counts them in `UnicodeScalar` as libyaml does, so
`String.mark(atLine:byteColumn:)` re-indexes the column against the offending
line.

The remaining cases (`writer`, `emitter`, `representer`,
`duplicatedKeysInMapping`) exist for API parity and are unused until Phases 4
and 7.

---

## Phase 2 — Node model — **done**

| Target | Yams source |
|---|---|
| `Node.swift` | (357) |
| `Node.Mapping.swift` | (247) |
| `Node.Sequence.swift` | (188) |
| `Node.Scalar.swift` | (124) |
| `Node.Alias.swift` | (56) |
| `Tag.swift` | (172) |
| `Anchor.swift` | (40) |
| `Composer.swift` | the composition half of `Parser.swift` |
| ~~`Mark.swift`~~ | done in Phase 1 |

The ordering bug is gone: the bridge no longer builds an `NSMutableDictionary`
at all, so a mapping's pairs arrive in source order and `Node.Mapping` keeps
them there. `YAMLNode` lost `mapping`, `sequence`, `scalar`, `parent`,
`typeBits`, `typeString` and the boolean flags, and gained styles, per-scalar
locations and normalized tags — the eager copy is now only what the Swift
`Node` actually needs.

`Composer` mirrors Yams' composition: aliases are dereferenced to the node
their anchor names rather than surfacing as `Node.alias`, and duplicate keys
throw `duplicatedKeysInMapping`. `Node.alias` therefore exists for the encoding
side (Phase 7) and is never produced by parsing — same as in Yams.

`YAMLDecoder` now decodes `Node` rather than `YAMLNode`, and `decode(from:)` /
`processNode` match Yams' shapes.

### Deliberate deviations

- **Anchors are held strongly.** Yams declares `Node.Scalar.anchor` and friends
  `weak`, which leaves them `nil` on every node a caller gets back from
  `compose` — nothing keeps the `Anchor` alive once the parser is gone
  (verified against Yams). Holding them strongly costs nothing: `Anchor` is a
  leaf object, so there is no cycle to create.
- **Container styles are real.** Yams reports `.any` for every mapping and
  sequence, because it reads the style off libyaml's *end* event, which does not
  carry one. rapidyaml reports the actual style, and we pass it through.
- **`Anchor.is_cyamlAlpha` is `Anchor.isPermitted`.** The Yams name refers to
  libyaml, which is not what backs this.

### Known gaps against Yams

- **Complex keys are unsupported**: rapidyaml refuses `? [a, b]` outright
  ("ryml trees cannot handle containers as keys"), where Yams composes it into a
  mapping keyed by a sequence. This is a rapidyaml limitation, not a porting
  choice.
- **Container marks point at the first child**, not at the opening token, since
  a container has no scalar of its own to locate. `{a: 1}` marks at `a`, where
  Yams marks at `{`.
- **Scalar marks point at the content**, not at the indicators before it. Yams
  marks `&x 1` at the `&` and `'sq'` at the opening quote; we mark the `1` and
  the `s`. Plain scalars — the common case — match Yams exactly, and this is
  covered by a test.
- **An empty value has no mark**, because there is no scalar in the source to
  point at. Yams marks the position where the value would have been.

Location tracking is enabled unconditionally in `ParserOptions`, which costs an
extra pass over the source to build rapidyaml's line accelerator. `Node.mark` is
part of the public model, so this is not opt-in.

### Stubs since filled in

`Tag` gained its `Resolver` in Phase 3 and its `Constructor` in Phase 4, which
also restored the `ScalarConstructible` accessors and `flatten()`. Phase 4 fixed
one bug this phase introduced: quoted scalars were being resolved by value, so
`'true'` came out a `Bool`.

---

## Phase 3 — Resolver — **done**

| Target | Yams source |
|---|---|
| `Resolver.swift` | `Resolver.swift` (175) |

Portable as-is, as expected. All seven rules — `bool`, `int`, `float`, `merge`,
`null`, `timestamp`, `value` — plus `basic` / `default`, and the
`appending` / `replacing` / `removing` lenses. Resolution was diffed against
Yams over 70 scalars, including the near-misses (`TrUe`, `0o8`, `1e3.5`,
`2026-13`), and agrees on every one.

This retires the tag stubs Phase 2 left behind. `Tag` carries a `Resolver`
again, `Tag.init` and `copy(with:)` take one, and `Node.Scalar.resolveTag`
resolves from contents, so `"1"` is `.int` and `"yes"` is `.bool`. `Composer`
threads a resolver through, defaulting to `.default`; Phase 6 will expose it as
a `Parser` option.

`decodeNil` also moved onto the resolver — `~`, `null`, `Null` and `NULL` now
decode as nil, and only for plain scalars, so `key: 'null'` stays a string. That
is Yams' rule; Phase 4 replaces the hand-written test with the constructor call.

The one thing left out is Yams' free `pattern(_:)` helper, which lives in this
file but is only used by `Constructor`. It comes with Phase 4.

---

## Phase 4 — Constructor / ScalarConstructible — **done**

| Target | Yams source |
|---|---|
| `Constructor.swift` | `Constructor.swift` (710) |

Portable as-is. Phase 3 made the *tags* right; this phase made the *values*
right — `"0x1F"` resolved to `.int` already, but decoding it went through
`Int("0x1F")` and failed. All of it landed: `Bool` (`yes`/`no`/`on`/`off` and
case variants), `Int`/`UInt` in every radix with `_` separators and sexagesimal,
`Double` with `.inf`/`-.inf`/`.nan`, `Data` from base64, `Date` from the YAML
timestamp formats, `UUID`/`Decimal`/`URL`, the `construct_*` family, the
`nsMutable*` maps, `Node.any` and `Node.array(of:)`. `Tag` carries its
`Constructor` again, and the decoder's hand-rolled `Int($0)` closures are gone
in favour of `ScalarConstructible`.

`node.any` was diffed against Yams over 66 documents — every radix, sexagesimal,
the infinities, timestamps with fractions and offsets, base64, sets, omaps,
pairs, merge keys, the `=` value key and empty containers — and agrees on all of
them.

### The one real bug this surfaced

Quoted scalars were being resolved by value, so `'true'` came out as a `Bool`
and `'null'` as null. YAML gives a quoted, literal or folded scalar the
non-specific `!` tag, which means "do not resolve me by value"; libyaml reports
that to Yams as `quoted_implicit` and Yams tags it `.str`. rapidyaml only
reports the style, so `Composer.scalarTag` draws the same conclusion from that.
This is Phase 2's bug, found by the Phase 4 comparison.

### Pulled forward

`Node.Mapping.flatten()`, listed under Phase 5, because `construct_mapping`
calls it. Merge keys therefore work through `node.any` now; wiring them into
*decoding* is still Phase 5.

---

## Phase 5 — Decoder completion — **done**

| Target | Yams source |
|---|---|
| `AliasDereferencingStrategy.swift` | (47) |
| `YAMLAnchorProviding.swift` | `YamlAnchorProviding.swift` (26) |
| `YAMLTagProviding.swift` | `YamlTagProviding.swift` (26) |
| `YAMLDecoder.swift` | the rest of `Decoder.swift` |

Everything the phase called for landed, and all of it was diffed against Yams:

- **Merge keys** — `container(keyedBy:)` calls `node.mapping?.flatten()`, so
  `<<: *base`, `<<: [*x, *y]` and nested merges all decode, with own keys
  winning over merged ones and `<<` absent from `allKeys`.
- **Anchor and tag injection** — a mapping's anchor and explicit tag are
  injected as the `yamlAnchor` / `yamlTag` keys, so a `YAMLAnchorCoding` type
  reads them; a key written in the source wins over the injected one, and
  neither appears in `allKeys`.
- **`AliasDereferencingStrategy`** — `YAMLDecoder.Options` carries one, and with
  `BasicAliasDereferencingStrategy` two aliases of the same anchor decode to the
  same class instance instead of two.
- **`Decoder.mark`**.

One thing this surfaced that is easy to miss: Yams decodes with
`Resolver([.merge])`, not `.default`. Its constructors key off a scalar's
*style* rather than its tag, so the only rule decoding needs is the one that
finds `<<` — and resolving seven regexes per scalar would be waste. The decoder
now passes that resolver to `Composer`; `compose` still defaults to `.default`
for everyone else.

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

Full alignment: **~~0.1~~ → ~~1~~ → ~~2~~ → ~~3~~ → ~~4~~ → ~~5~~ → 6 → 7 → 8**.

0.1 through 5 are done: decoding is complete and matches Yams. What is left is
the public loading API (Phase 6), the whole encoding side (Phase 7), and the
ported test suite (Phase 8).

The "correct and usable" subset — 0.1, 3, 4 and merge keys — is already covered
by what has landed, so everything from here on is API surface rather than
correctness.
