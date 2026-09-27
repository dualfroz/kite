# kite

kite is a Scheme interpreter written in Swift with no dependencies beyond Foundation. It is split into `KiteCore`, a library with the reader, evaluator, macro expander, numeric tower, data structures and printer, and `kite`, a command line tool that runs a REPL or a source file. The evaluator is an explicit-continuation machine (CEK style): every pending computation is a heap-allocated continuation frame instead of a Swift stack frame. That gives proper tail calls in constant space, first-class re-entrant `call/cc`, and `dynamic-wind` and exception handlers that cooperate with continuations. The higher-order library procedures are written in Scheme, so continuations captured inside `map` or `for-each` behave like any other.

## Features

**Reader**

- Integers of any size (`123456789012345678901234567890` reads as an exact integer), exact rationals (`3/4`, reduced on read, so `6/2` reads as `3`) and reals (`3.5`, `1e10`).
- Radix prefixes `#x`, `#b`, `#o` and `#d`.
- Strings with `\n`, `\t`, `\r`, `\\`, `\"` and `\0` escapes.
- Characters: `#\a`, `#\space`, `#\newline`, `#\tab`, `#\return`, `#\null` (`#\nul`), `#\delete` (`#\rubout`).
- Booleans `#t` and `#f`, proper and dotted lists, vector literals `#(1 2 3)`.
- Square brackets as an alternative list delimiter: `(let ([x 1]) x)`.
- Reader sugar for `'`, `` ` ``, `,` and `,@`.
- Line comments (`;`), nested block comments (`#| ... |#`) and datum comments (`#;`).

**Special forms**

- `quote`, `quasiquote` with `unquote` and `unquote-splicing`, including nested levels and vector templates.
- `if`, `define` (variables and the `(define (name . formals) body ...)` shorthand), `set!`, `begin`.
- `lambda` with fixed, rest (`(a . rest)`) and fully variadic (`args`) parameter lists.
- `let`, named `let`, `let*`, `letrec`, `letrec*`, `do`.
- `let-values`, `let*-values` and `define-values`, with list, dotted and single-symbol formals. `define-values` also works as an internal definition.
- `cond` with `else`, `=>` and test-only clauses, `case` with `else`, `and`, `or`.
- `delay` and `delay-force`.
- `define-record-type` with a constructor that takes any subset of the fields, a predicate, accessors and modifiers. The type name is bound to a record type descriptor. Records print as `#<point x=1 y=2>`.
- `define-syntax`, `let-syntax`, `letrec-syntax`.
- Defined in the Scheme prelude: `when`, `unless`, `receive`, `guard`, `case-lambda` and `parameterize`.

**Macros**

- `syntax-rules` with literals, the `_` wildcard, ellipsis patterns (including patterns after the ellipsis and nested ellipsis templates) and dotted tails.
- Hygiene by renaming. Each expansion marks the identifiers introduced by its template:
  - a binding introduced by a template (such as `tmp` in a `swap!` macro) never captures a user variable;
  - a free identifier in a template (such as `list` or `if`) refers to its binding where the macro was defined, even if the macro is used inside a `let` that shadows that name;
  - quoted and quasiquoted symbols in a template stay plain symbols.
- The derived forms (`let`, `cond`, `case`, `do`, quasiquote) refer to the global primitives they expand into, so shadowing `cons`, `append` or `memv` locally does not break them.

**Evaluation and control**

- Tail calls in constant space, including mutual recursion and calls in tail position of `cond`, `case`, `and`, `or`, `when` and `do`.
- Deep non-tail recursion is limited by memory, not by the Swift stack.
- `call/cc` and `call-with-current-continuation` with escaping, re-entrant and multi-shot continuations. This works across `map`, `for-each`, `filter`, the folds, `vector-map` and the other higher-order procedures.
- `dynamic-wind`: escaping through a continuation runs the `after` thunks innermost first, and re-entering one runs the `before` thunks again.
- Multiple values: `values`, `call-with-values`, `receive`, `let-values`. A continuation called with several arguments delivers them as multiple values.
- `case-lambda` picks the first clause whose parameter list accepts the argument count, and calls it in tail position.
- Parameters: `make-parameter` with an optional converter, and `parameterize`, which installs new values through `dynamic-wind`. Escaping out of a `parameterize` body restores the old values, and re-entering it reinstalls the new ones.
- `apply` with leading arguments before the final list.

**Exceptions**

- `raise`, `raise-continuable` and `with-exception-handler` with R7RS semantics. A handler runs with the outer handlers installed. Returning from a handler for `raise` is an error, and the value returned for `raise-continuable` becomes the value of the `raise-continuable` call.
- `guard` with `else`, `=>` and test-only clauses. If no clause matches, the condition is re-raised to the outer handler.
- `error` raises an error object. `error-object?`, `error-object-message`, `error-object-irritants`, `read-error?` and `file-error?` inspect it.
- Errors detected by primitives (wrong argument types, arity mismatches, unbound variables, index out of range) become error objects too, so `guard` catches them.
- Errors no handler catches propagate to Swift as `SchemeError`. The `condition` property holds the raised object. Before the error leaves the interpreter, the pending `dynamic-wind` after thunks run, innermost first.

**Numbers**

- Fixnums are Swift `Int`. `+`, `-` and `*` detect overflow and promote to an arbitrary-precision integer, and results that fit again are demoted back to fixnums.
- `quotient`, `remainder`, `modulo`, the `truncate` and `floor` division procedures (including `floor/` and `truncate/`, which return two values), `gcd`, `lcm`, `even?`, `odd?` and `abs` accept integers of any size.
- Exact rationals with arbitrary-precision numerator and denominator, always kept in lowest terms. `expt` stays exact for exact bases and integer exponents, including negative ones (`(expt 2 -3)` is `1/8`).
- `floor`, `ceiling`, `truncate` and `round` (ties to even) are exact on rationals. `sqrt` is exact for perfect squares of integers and rationals. `exact-integer-sqrt` returns the root and the remainder as two values.
- `exact` and `inexact` convert in both directions; `(exact 2.5)` is `5/2`.
- Reals are `Double`; any real operand makes the result real. Reals print as `4.0`, `+inf.0`, `-inf.0` and `+nan.0`.
- `number->string` and `string->number` accept radix 2, 8, 10 and 16.
- `BigInt` is implemented from scratch on 32-bit limbs: addition, subtraction, multiplication, long division (`divMod`, `quotient`, `remainder`, floor `modulo`), `gcd`, `power`, integer square root (`isqrt`) and conversion to and from strings in radix 2 to 36.

**Data structures**

- Vectors: literals, construction, indexing, slicing, copying, filling, appending, conversion to and from lists, `vector-map` and `vector-for-each` over one or more vectors, `equal?` comparison.
- Hash tables with SRFI-69 names. `make-hash-table` takes an optional `eq?`, `eqv?`, `equal?` (the default) or `string=?`. Keys of `eq?`/`eqv?` tables are hashed by identity, and keys of `equal?` tables by structure. Iteration follows insertion order.
- Promises: `delay` evaluates once and memoizes the value. `delay-force` chains run in constant space, as R7RS requires for iterative lazy algorithms. `make-promise` wraps a value; `force` of a non-promise returns it unchanged.
- String ports: `open-input-string`, `open-output-string`, `get-output-string`, `call-with-output-string`. `read-char`, `peek-char`, `read-line`, `read-string` and `read` (parse one datum) read from an input port. `write`, `display`, `newline`, `write-char` and `write-string` take an optional output port. `current-output-port` returns a port connected to the interpreter output.

**Builtins**

| Group | Procedures |
|---|---|
| Arithmetic | `+ - * / = < > <= >= abs min max square expt quotient remainder modulo truncate/ truncate-quotient truncate-remainder floor/ floor-quotient floor-remainder gcd lcm 1+ 1- floor ceiling truncate round sqrt exact-integer-sqrt numerator denominator exact inexact exact->inexact inexact->exact number->string string->number` |
| Numeric predicates | `number? complex? real? rational? integer? exact-integer? exact? inexact? zero? positive? negative? even? odd?` |
| Pairs and lists | `cons car cdr` and every `c[ad]r` combination up to four levels deep (`caddr`, `cdddr`, ...), `set-car! set-cdr! list make-list length reverse append list-ref list-tail list-copy last-pair` |
| Higher order | `map for-each fold-left` (one or more lists), `fold-right filter remove reduce apply` |
| Search | `member memq memv assoc assq assv` |
| Predicates | `null? pair? list? symbol? string? char? boolean? procedure? vector? hash-table? promise? port? eof-object? not eq? eqv? equal?` |
| Strings | `string-length string-ref string-append substring string-copy make-string string string->list list->string string-upcase string-downcase string=? string<? string>? string<=? string>=? string-ci=? string-map string-for-each string->symbol symbol->string` |
| Characters | `char->integer integer->char char=? char<? char>? char<=? char>=? char-alphabetic? char-numeric? char-whitespace? char-upper-case? char-lower-case? char-upcase char-downcase digit-value` |
| Vectors | `vector make-vector vector-length vector-ref vector-set! vector->list list->vector vector-copy vector-fill! vector-append vector-map vector-for-each` |
| Hash tables | `make-hash-table alist->hash-table hash-table-set! hash-table-ref hash-table-ref/default hash-table-delete! hash-table-contains? hash-table-exists? hash-table-count hash-table-size hash-table-keys hash-table-values hash-table->alist hash-table-update! hash-table-update!/default hash-table-walk hash-table-copy hash-table-clear!` |
| Control | `call/cc call-with-current-continuation values call-with-values dynamic-wind force make-promise make-parameter` |
| Exceptions | `raise raise-continuable with-exception-handler error error-object? error-object-message error-object-irritants read-error? file-error?` |
| Ports and output | `display write newline write-char write-string current-output-port open-input-string open-output-string get-output-string call-with-output-string call-with-port read read-char peek-char read-line read-string char-ready? eof-object input-port? output-port? textual-port? input-port-open? output-port-open? close-port close-input-port close-output-port` |

Every builtin checks its argument count, and a mismatch is reported as `car: expected 1 argument, got 0`. `list?` detects circular lists.

The prelude is evaluated in a private environment, and only its public names are copied into the global environment. Its internal helpers are not reachable from user code, and redefining a library procedure such as `reverse` or `apply` does not break `map` or the other prelude procedures.

**Command line tool**

- `kite` with no arguments starts a REPL. Input that does not form a complete expression yet continues on the next line under a `...` prompt. Results are printed in `write` form, and multiple values are printed on one line. Definitions and other unspecified values print nothing. Errors are reported and the session continues.
- `kite file.scm` evaluates a file. On error it prints `error: <message>` to standard error and exits with status 1.

## Build and run

Requires a Swift 6.0 or newer toolchain (the package compiles in the Swift 5 language mode).

```sh
swift build
swift run kite                         # REPL, Ctrl-D to exit
swift run kite examples/streams.scm    # run a file
```

For an optimized binary use `swift build -c release`; it is written to `.build/release/kite`.

A REPL session:

```
kite> (define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))
kite> (fact 25)
15511210043330985984000000
kite> (/ (fact 10) (fact 12))
1/132
kite> (guard (e ((error-object? e) (error-object-message e))) (vector-ref #(1 2) 5))
"vector-ref: index out of range"
kite> (exact-integer-sqrt 17)
4 1
```

## Embedding

`KiteCore` is a library product, so another package can depend on it:

```swift
.package(url: "https://github.com/dualfroz/kite.git", branch: "main")
// target dependency:
.product(name: "KiteCore", package: "kite")
```

```swift
import KiteCore

let interpreter = Interpreter()
interpreter.output = { text in print(text, terminator: "") }
let value = try interpreter.evalString("(map (lambda (x) (* x x)) '(1 2 3))")
print(writeString(value))
```

`evalString` evaluates every form in the source and returns the last value. `evalTop` evaluates a single datum produced by `Reader(source).readProgram()`. `output` receives everything written to the current output port. Uncaught Scheme errors are thrown as `SchemeError`. `displayString` and `writeString` render a `Value` the way `display` and `write` do.

## Examples

The `examples/` directory contains Scheme programs that also run as integration tests:

| File | Shows |
|---|---|
| `factorial.scm` | Factorial with a named-let accumulator |
| `fib.scm` | Naive tree-recursive Fibonacci |
| `maps.scm` | `map` over one and several lists, `filter`, `fold-left`, `for-each`, `append`, `reverse` |
| `tailloop.scm` | A 100000-step loop and a 100000-step mutual recursion in constant space |
| `callcc.scm` | Early exit from a loop with `call/cc`, and a loop built by re-entering a saved continuation |
| `macros.scm` | `swap!` including the hygiene case, an ellipsis macro, a recursive macro, `when` and `unless` |
| `exceptions.scm` | `guard` with error objects and raised values, `dynamic-wind` cleanup on a raise, `raise-continuable` |
| `streams.scm` | Lazy streams built from `delay`: a prime sieve, Fibonacci numbers past 64 bits, memoization, a long `delay-force` chain |
| `wordcount.scm` | A word frequency count using a string input port, a hash table, a string output port and a vector histogram |

## Tests

```sh
swift test
```

The XCTest suite in `Tests/KiteCoreTests` covers:

- `ReaderTests`: atoms, strings, characters, dotted lists, vector literals, square brackets, integers beyond 64 bits, radix prefixes, numeric-looking symbols, quote sugar and all three comment forms.
- `EvalTests`: arithmetic, special forms, closures, quasiquote, `apply`, strings and characters, list utilities, arity errors, prelude procedures surviving user redefinitions, and output redirection.
- `NumericTests`: fixnum overflow, integer division, parity and `gcd` on big integers, exact `expt`, rounding, exactness conversions, square roots, radix conversion and division by zero.
- `TailCallTests`: proves constant space directly. A continuation captured at the bottom of a tail loop has the same number of frames after 10 and after 50000 iterations, through `if`, `cond`, `case`, `and`/`or`, `when`, `let`, `apply` and `do`. Non-tail recursion, by contrast, grows it. Also runs named-let and mutual recursion loops.
- `StandardFormsTests`: `case-lambda`, `let-values`, `let*-values`, `define-values`, `parameterize` with converters, escapes, raises and re-entry, `define-record-type`, the private prelude environment, and after thunks running when an error escapes.
- `CallCCTests`: escaping, unused, re-entrant and multi-shot continuations, escapes out of every higher-order procedure, re-entry into `map`, and a generator built from `for-each`.
- `ExceptionTests`: `guard` clauses, primitive errors, re-raising, uncaught conditions, `raise-continuable`, handler context, and `dynamic-wind` on escape, re-entry, raise and nesting.
- `ValuesAndPromisesTests`: `call-with-values`, `receive`, multi-value continuations, memoized and re-entrant promises, `delay-force` in constant space and lazy streams.
- `DataStructureTests`: vector operations and errors, hash table lookup, update, deletion, walking, equivalence kinds, copying and growth.
- `PortTests`: string output and input ports, `read`, `read-string`, `call-with-output-string`, the current output port and closed ports.
- `MacroTests`: prelude macros, hygiene for introduced bindings and free identifiers, `let-syntax` scoping, keywords and primitives shadowed at the use site, quoted template symbols, literals, ellipsis, recursive macros and `do`.
- `BigIntTests`: round trips, arithmetic checked against `Int`, 100!, division, modulo, gcd, powers, radix conversion, `isqrt` and ordering.
- `ExampleTests`: runs every file in `examples/` and compares its output.

## Project layout

```
Package.swift
Sources/
  KiteCore/
    Reader.swift            source text to Value, number parsing
    Value.swift             Value and the heap types it refers to, eqv?/equal?, hashing
    Interpreter.swift       machine loop, special forms, application, handlers, winders
    Kont.swift              continuation frames and machine states
    Desugar.swift           let, let*, letrec, cond, case, and, or, do, quasiquote
    Macros.swift            syntax-rules matching, expansion and renaming
    Environment.swift       lexical environments and macro definition scopes
    Records.swift           define-record-type
    Numeric.swift           numeric tower operations
    BigInt.swift            arbitrary-precision integers
    HashTable.swift         insertion-ordered hash table
    Port.swift              string and console ports
    Builtins.swift          lists, strings, characters, control and exceptions
    BuiltinsNumeric.swift   numeric procedures
    BuiltinsData.swift      vectors, hash tables, promises
    BuiltinsPorts.swift     port procedures and output
    BuiltinsSupport.swift   registration and argument helpers
    Prelude.swift           procedures and macros written in Scheme
    Printer.swift           display and write rendering
    Errors.swift            SchemeError
  kite/
    main.swift              REPL and file runner
Tests/
  KiteCoreTests/
examples/
```

## Limitations

kite implements a large practical subset of R7RS small, not the full standard.

- Not implemented: bytevectors, complex numbers, file ports and the file system, a console input port (`read-char` and friends need an explicit port), `string-set!` and other string mutation, `eval`, `load`, and the library system (`define-library`, `import`).
- A continuation captured during one top-level form and invoked from a later one finishes the earlier form and then ends the current one, which is how most REPLs treat top-level continuations.
- `current-output-port` is not a parameter, so it cannot be rebound with `parameterize`.

## License

MIT, see [LICENSE](LICENSE).
