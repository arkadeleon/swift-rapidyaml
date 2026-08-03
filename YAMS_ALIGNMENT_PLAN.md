# Yams Alignment Plan

Goal: bring `swift-rapidyaml` to full API and behavioral parity with
[Yams](https://github.com/jpsim/Yams), backed by rapidyaml instead of libyaml.

Reference checkout used for this plan: `../Yams` — 21 source files / 5078 lines,
22 test files / 5968 lines.

Drafted 2026-08-03.

## Current state

This section describes the state the plan was drafted against. Phases 0.1
through 7 have since landed; see each phase for what changed.

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

`emitter` and `representer` came into use in Phase 7, and
`duplicatedKeysInMapping` in Phase 2. `writer` is still unused: rapidyaml
returns a string rather than writing through a sink, so there is nothing to
fail.

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
- **Types Yams spells `Yaml*` are spelled `YAML*`** — `YAMLSequence`,
  `YAMLAnchorProviding`, `YAMLTagProviding` — matching `YAMLDecoder` and
  `YAMLError`, which this project already had.

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

## Phase 6 — Parser / top-level loading API — **done**

| Target | Yams source |
|---|---|
| `Parser.swift` | `Parser.swift` (486) |

`load`, `load_all`, `compose`, `compose_all`, `YAMLSequence`, the `Parser`
class, and multi-document streams. As predicted, rapidyaml's STREAM root made
this a child walk rather than an event loop: `Parser` holds the document list
and an index, and `nextRoot()` composes one document at a time. `Composer` is
now owned by the `Parser` for the length of the stream, so anchors carry from
one document to the next — not what the spec says, but what Yams does, since
its anchor map is never cleared between documents.

`YAMLDecoder` now goes through `Parser.singleRoot() ?? ""`, exactly as Yams
does, which fixes two things: a source with no document decodes as an empty
scalar rather than throwing, and a source with *several* documents is now
rejected instead of silently decoding the first.

56 outcomes across 14 sources — `compose` / `compose_all` / `load` / `load_all`
over single documents, streams, empty sources, empty documents, and anchors
spanning documents — were diffed against Yams. 40 match exactly; the 16 that
differ are the two limitations below.

### Where this differs from Yams

- **The stream is parsed up front.** rapidyaml builds the whole tree in one
  pass, where libyaml is an event stream, so a malformed *later* document fails
  the whole call: `Parser.init` throws, rather than `compose_all` yielding the
  earlier documents and then reporting the error through
  `YAMLSequence.error`. This is inherent to the parser, not a porting choice.
- **"but found another document" points at the next document's first scalar**,
  where Yams points at its `---` marker. rapidyaml does not record the marker's
  position — the same limitation as the container marks in Phase 2. It only
  affects the text of that one error message.

### On `Parser.Encoding`

Kept for API parity, but it is close to vestigial: rapidyaml only reads UTF-8,
and a `String` is handed to it as UTF-8 whatever the value says, so it has an
effect only on the `Data` initializer, where it picks how bytes become a
`String`. `.default` is plainly `.utf8` — Yams' `.default` reads a
`YAMS_DEFAULT_ENCODING` environment variable and *prints* to stdout when it
fires, which is a debugging affordance for libyaml's two input encodings and
not something worth reproducing.

`YAMLDecoder.Options.encoding` stays `String.Encoding`, this project's existing
public API, rather than switching to `Parser.Encoding`; it is strictly more
capable and used for the same job.

---

## Phase 7 — Encoding / emitting — **done**

| Target | Yams source | Notes |
|---|---|---|
| `YAMLEncoder.swift` | `Encoder.swift` (371) | ported |
| `Emitter.swift` | `Emitter.swift` (572) | public shape ported, driven by rapidyaml's emitter |
| `Representer.swift` | `Representer.swift` (350) | ported |
| `RedundancyAliasingStrategy.swift` | (148) | ported |

`Representer`, `RedundancyAliasingStrategy` and `YAMLEncoder` are pure Swift and
went across as-is, along with `dump` / `serialize` and `Emitter.Options`.
`Node.subscript(NodeRepresentable)` — left out of Phase 2 because
`NodeRepresentable` did not exist yet — is back, which is what `_Encoder` uses
to write into a sequence by index.

The bridge gained `YAMLEmitterNode` and `YAMLEmitter`: a mutable mirror of
`YAMLNode` that Swift fills in and hands over in one call, since rapidyaml
emits a whole tree rather than an event stream. That also means nothing is
written until `Emitter.close()`, where libyaml streams as it goes.

### The emitter is where parity ends

libyaml is an event-based emitter with knobs for layout; rapidyaml emits a
tree and has almost none. The output is valid, equivalent YAML that round-trips
— an `Everything` struct covering every scalar kind encodes and decodes back
equal, and so does a composed `Node` — but it is **not byte-identical to Yams**.
Of 22 documents compared, 14 match exactly. The differences:

| | Yams | here |
|---|---|---|
| sequence under a mapping key | not indented | indented |
| flow separator | `[1, 2]` | `[1,2]` |
| non-ASCII, `allowUnicode: false` | escaped `\uXXXX` | written as-is |
| first document of a stream | no leading `---` | leading `---` |
| scalar tags | **dropped** | kept |

The last one is a deliberate improvement rather than a gap. Yams passes
libyaml `plain_implicit` and `quoted_implicit` unconditionally, so *every*
scalar tag is discarded on the way out: `dump(object: Data(...))` reads back as
a `String`, and `!custom` is lost. We keep a scalar tag whenever re-reading
would not produce it anyway, which costs a few characters and makes the round
trip lossless. Container tags survive in both.

### Options that cannot be honoured

`canonical`, `indent`, `width`, `explicitEnd`, `version` and any `lineBreak`
other than `.ln` have no rapidyaml equivalent. Rather than accept and silently
ignore them, `Emitter.open()` throws `YAMLError.emitter` naming the option, so a
caller finds out at once. Every default value is supported, so ordinary use
never trips it. `allowUnicode` is accepted in both positions but only `true`
describes what actually happens.

`sortKeys`, `explicitStart`, `sequenceStyle`, `mappingStyle`,
`newLineScalarStyle` and `redundancyAliasingStrategy` all work.

### Anchors, checked

Yams' `weak var anchor` bites again here: `serialize(node:)` on a tree whose
anchors were built inline drops them entirely, because the `Anchor` is gone
before the emitter runs. Given a *retained* anchor Yams emits `a: &x 1\nb: *x`,
which is exactly what we produce. Composed aliases re-emit as duplicate
anchors in both libraries.

---

## Phase 8 — Tests

Port Yams' suite (5968 lines), including `SpecTests.swift` (951) which runs the
YAML spec fixtures.

Suggested order: `ConstructorTests` → `NodeTests` → `SpecTests` → `EncoderTests`.
This suite is the only reliable way to verify the earlier phases.

---

## Order of work

Full alignment: **~~0.1~~ → ~~1~~ → ~~2~~ → ~~3~~ → ~~4~~ → ~~5~~ → ~~6~~ → ~~7~~ → 8**.

0.1 through 7 are done. Reading matches Yams; writing produces equivalent YAML
that round-trips, but not byte-identical output — see Phase 7 for why. What is
left is Phase 8, porting Yams' own test suite, which is also the thing that
would tell us how much the emitter differences actually matter.

The "correct and usable" subset — 0.1, 3, 4 and merge keys — is already covered
by what has landed, so everything from here on is API surface rather than
correctness.
