# Bugs found in MMIXware

This is a list of bugs and documentation typos in Knuth's MMIXware. They
were found while translating MMIXware into a Korean literate program in Go
(this repository). The Go port was checked against the original C programs,
running the same inputs and comparing the outputs byte for byte. That
comparison exposed several odd behaviors on the C side.

I should acknowledge that a substantial part of the work of translating
MMIXware into Korean GWEB was done with the help of Claude Code. This includes
the in-depth, detailed testing.

Each entry below gives the location, the symptom, a minimal way to reproduce
it, and a proposed patch in the change-file format. All patches were applied
to a copy of the sources and checked:

- Each patch removes its symptom.
- The patched `mmix` still gives the same standard output for `silly.run`.
- The patched `mmixal` still assembles all 54 `.mms` example files to the
  same `.mmo` files, apart from the timestamp.

## Scope and method

- **Sources:** the MMIXware release of June 2025, the file `mmix.tar.gz`
  (dated 2025-06-20, 85 files) from Knuth's home page. Its SHA-256 is
  `b28b46b2ff44eafb4029b449262b145e538b2703f1d5b336cd429163408fafd9`.
  Section numbers (§) and line numbers refer to the `.w` files of this
  release.
- **Platform:** macOS (Darwin 27) with Apple clang 21.0.0.
- **Build:** the flags of Knuth's `Makefile`, `CFLAGS = -g -fPIE`. Modern
  clang treats K&R-style implicit `int` as an error, so `-std=gnu89 -w` was
  added. The optimization level matters for some bugs (see 10).
- **Verification:** every reproduction below was run on this build. Bugs
  that corrupt memory behave differently from build to build, so their
  cause was also confirmed with an instrumented build or with UBSan.
- **Report date:** 2026-09-27.

## Summary

| No. | Module | Symptom | Kind |
| --- | --- | --- | --- |
| 1 | mmix-arith | huge decimal constants write to `dat[-1]` | memory |
| 2 | mmix-io, mmix-sim | `Fputws` of an empty string, odd address | memory |
| 3 | mmix-sim | option `-e<x>` does not work as documented | function |
| 4 | mmix-sim | online command `rG=<v>` is silently ignored | function |
| 5 | mmix-sim | "privileged/illegal instruction!" sticks | output |
| 6 | mmix-sim | local variable `O` can be used uninitialized | UB |
| 7 | mmixal | a label-only last line reuses the previous line | function |
| 8 | mmotype | wrong expected value in the `lop_end` message | output |
| 9 | mmotype | `printf("%s",NULL)` on a corrupt file | UB |
| 10 | mmmix | `mmmix -s` never halts when built with `-O2` | UB |
| 11 | mmix-pipe | `specval` returns an uninitialized value | output |
| 12 | mmix-pipe | shift by a negative amount | UB |

Some minor items and the typos in `mmix-doc.w` follow the numbered bugs.

## Bugs

### 1. mmix-arith: huge decimal constants write before the array

- **Where:** `mmix-arith.w` §79 (line 1488, `ff.a=x/9`), §82 (line 1524,
  `*p=carry` in `bignum_double`), §83 (line 1543).
- **Symptom:** when `scan_const` reads a decimal constant of about 1e323 or
  more, the value `x=341+zeros-dec_pt-exp` lies between 0 and 9, so
  `ff.a=x/9` can be 0. Then the loop of line 1543 keeps doubling `tt` until
  `tt.a` reaches 0, and `bignum_double` stores its carry into `dat[-1]`,
  which is the field `b` of the struct. The overflow stays inside the
  struct, so AddressSanitizer does not see it.
- **Reproduce:** the simulator reaches `scan_const` through online commands
  such as `g200=.64352139e333` or `g200=9e332`. A build with a check for
  `p<f->dat` before line 1524 shows 56 writes to `dat[-1]` for
  `scan_const(".64352139e333")`. The `-g` build usually still answers `Inf`,
  but it once died with a bus error (exit status 138) when the command came
  from a file. An `-O` build died with a bus error on `.64352139e333`.
- **Proposed patch:** every such value overflows anyway, so treat it as
  infinite. The results for other values are unchanged; for example,
  `1.7976931348623157e308` still gives `7fefffffffffffff`, and `1.8e308`
  gives infinity.

  ```text
  @x [79] l.1485
  if (x<0) {
  @y
  if (x<10) {
  @z
  ```

### 2. mmix-io, mmix-sim: `Fputws` of an empty string at an odd address

- **Where:** `mmix-io.w` §20 (line 332, `mmix_fputws`); `mmix-sim.w` §115
  (line 2494) and `mmix-pipe.w` §382 (line 6742), the odd-address case of
  `mmgetchars`.
- **Symptom:** `mmix_fputws` passes the string address to
  `mmgetchars(buf,256,string,1)` without making it even. When the address
  is odd and its first byte is 0, `mmgetchars` looks at `*(p-1)`, which is
  `buf[-1]`. If that byte happens to be 0 it returns −1, and then
  `fwrite(buf,1,(size_t)-1,fp)` is called. What happens next depends on the
  build and on the stream:
  - The `-g` build with tracing writes 4339 bytes of stack garbage to
    standard output.
  - An `-O` build crashed with a segmentation fault on StdOut and on files.
  - On StdErr, which is unbuffered, nothing is written but the error flag of
    `stderr` is set. From then on, macOS's `fprintf` writes nothing to
    `stderr`, so every later trip warning and every warning of the
    simulator itself is silently lost.

  The string is empty, so the correct result is to write nothing and return
  0. The magic I/O of the meta-simulator has the same code.
- **Reproduce:** run this program with `mmix -t9`. Garbage appears among the
  trace lines, and the trace says `Fputws(StdOut,#2000000000000001) = -1`.

  ```text
          LOC   Data_Segment
          GREG  @
  Buf     BYTE  1,0,0,0,0,0,0,0
          LOC   #100
  Main    LDA   $255,Buf+1
          TRAP  0,Fputws,StdOut
          TRAP  0,Halt,0
  ```

- **Proposed patch:** look at the previous byte only if there is one. With
  this change the example writes nothing and returns 0. The same change
  applies to `mmix-pipe.w` §382.

  ```text
  @x [115] l.2494
      if ((a.l&0x1) && *(p-1)=='\0') return m-1;
  @y
      if ((a.l&0x1) && m>0 && *(p-1)=='\0') return m-1;
  @z
  ```

### 3. mmix-sim: option `-e<x>` does not work as documented

- **Where:** `mmix-sim.w` §2 (lines 69–75, the description) and §122
  (line 2588, `exc&tracing_exceptions`).
- **Symptom:** the documentation says that x in `-e<x>` is a pattern of the
  DVWIOUZX bits as they appear in rA, and that `-e` alone means `-eff`. But
  `exc` holds these bits shifted left by 8 (`X_BIT` is `1<<8`), while
  `tracing_exceptions` holds the rA pattern. So `-e`, `-eff` and `-e40`
  trace nothing, and only `-e4000` or `-eff00` work. The value 0xff that
  `-v` puts into `tracing_exceptions` has no effect either.
- **Reproduce:** with the program below, `mmix -e40 ovf` traces nothing,
  and only `mmix -e4000 ovf` traces the overflow of `ADD` (`rA=#00040`).

  ```text
          LOC   #100
  Main    SETH  $1,#7fff
          ADD   $2,$1,$1
          TRAP  0,Halt,0
  ```

- **Proposed patch:** compare in the same way as line 2591
  (`g[rA].l |= exc>>8`) does.

  ```text
  @x [122] l.2588
    if (exc&tracing_exceptions) tracing=true;
  @y
    if ((exc>>8)&tracing_exceptions) tracing=true;
  @z
  ```

### 4. mmix-sim: online command `rG=<v>` is silently ignored

- **Where:** `mmix-sim.w` §158 (lines 3259–3272).
- **Symptom:** "Set `g[k]=val` only if permissible" begins with
  `if (k<=19) break;`, but rG is register 19. So the branch for `k==rG` right
  below it is dead code, and `rG=<v>` is ignored without any message. The
  `PUT` instruction uses the bound 18 (`xx<=18`) for the same purpose.
- **Reproduce:** in `mmix -i hello`, execute one instruction (an empty line),
  then give `rG=100` and look at `rG`. It is still `g[19]=255`. In the same
  way, `rA=10000` is accepted.
- **Proposed patch:** with this change `rG=100` gives `g[19]=100`.

  ```text
  @x [158] l.3261
    if (k<=19) break;
  @y
    if (k<=18) break;
  @z
  ```

### 5. mmix-sim: "privileged/illegal instruction!" sticks

- **Where:** `mmix-sim.w` §131 (line 2712).
- **Symptom:** `lhs` is rewritten only by instructions whose destination is
  X, by PUSH/POP, and by privileged or illegal instructions. After a
  privileged or illegal instruction in online mode, later traced instructions
  such as SWYM, JMP and TRAP print the same "illegal instruction!" again.
- **Reproduce:** run `mmix -t9 -i priv` on the program below and give `c`
  twice. The `SWYM`, `JMP` and `TRAP` lines all end with
  `illegal instruction!`.

  ```text
          LOC   #100
  Main    RESUME 1
          SWYM
          JMP   1F
  1H      TRAP  0,Halt,0
  ```

- **Proposed patch:** forget the message once it has been printed. With
  this change the message appears only on the `RESUME` line.

  <!-- markdownlint-disable MD013 -->
  ```text
  @x [131] l.2712
  if (lhs[0]=='!') printf("%s instruction!\n",lhs+1); /* privileged or illegal */
  @y
  if (lhs[0]=='!') {
    printf("%s instruction!\n",lhs+1); /* privileged or illegal */
    lhs[0]='\0';
  }
  @z
  ```
  <!-- markdownlint-enable MD013 -->

### 6. mmix-sim: local variable `O` can be used uninitialized

- **Where:** `mmix-sim.w` §75 (line 1779, `register int G,L,O;`).
- **Symptom:** `O` gets its first value from the bootstrap UNSAVE. If the
  online command `@<x>` moves the instruction pointer out of segment 0 before
  the first instruction, that UNSAVE becomes privileged, and `O` is used
  without a value.
- **Reproduce:** run `mmix -t9 -i uo` on the program below and give
  `@4000000000000000`, an empty line, `@100` and `c`. The trace says
  `$0=l[1]`, so `O` held the garbage value 1; it should be `l[0]`.

  ```text
          LOC   #100
  Main    SETL  $0,5
          TRAP  0,Halt,0
  ```

- **Proposed patch:** with this change the trace says `$0=l[0]`.

  ```text
  @x [75] l.1779
  register int G,L,O; /* accessible copies of key registers */
  @y
  register int G,L,O=0; /* accessible copies of key registers */
  @z
  ```

### 7. mmixal: a label-only last line reuses the previous line

- **Where:** `mmixal.w` §103 (line 2631), the last statement of "Scan the
  label field", `for (p++;isspace(*p);p++);`.
- **Symptom:** when the file ends with a line that has a label only and no
  newline, `p++` steps over the terminating null byte. The buffer still holds
  bytes of the previous, longer line that `fgets` left behind. So the
  opcode and operands of the previous line are assembled a second time. With
  a newline at the end, `fgets` leaves one more null byte, and the result is
  the proper warning "no opcode".
- **Reproduce:** after `printf 'Main SWYM 1,2,3\nabc' > stale.mms`, the
  command `mmixal -l stale.lst stale.mms` lists `...004: fd010203  abc` and
  defines `abc` as #4.
- **Proposed patch:** skip the character after the label only if there is
  one. With this change the example gives the warning "no opcode; label `abc'
  will be ignored", as it does when the line ends with a newline.

  ```text
  @x [103] l.2631
  for (p++;isspace(*p);p++);
  @y
  if (*p) p++;
  while (isspace(*p)) p++;
  @z
  ```

### 8. mmotype: wrong expected value in the `lop_end` message

- **Where:** `mmotype.w` §30 (line 458).
- **Symptom:** when the length of the symbol table is wrong, the message
  "YZ field at lop_end should have been %d!" prints `count-yz-1`. The test
  on line 457 is `count!=stab_start+yz+1`, so the correct value is
  `count-stab_start-1`.
- **Reproduce:** assemble the `test.mms` of the MMIXAL documentation. The
  last tetrabyte of `test.mmo` is `lop_end` with YZ=10; change it to YZ=5.
  Then `mmotype` says "should have been 53!" instead of 10.
- **Proposed patch:** with this change the message says 10.

  ```text
  @x [30] l.458
    fprintf(stderr,"YZ field at lop_end should have been %d!\n",count-yz-1);
  @y
    fprintf(stderr,"YZ field at lop_end should have been %d!\n",
      count-stab_start-1);
  @z
  ```

### 9. mmotype: `printf("%s",NULL)` on a corrupt file

- **Where:** `mmotype.w` §20 (lines 265–268).
- **Symptom:** when a file number gets a second name, the name tetrabytes
  are read first and `cur_file=y` comes after them. But the macro `y` then
  refers to a byte of the last name tetrabyte, not of the `lop_file`
  tetrabyte. So `cur_file` can become a number without a name, and a later
  `printf("%s",file_name[cur_file])` receives NULL.
- **Reproduce:** a file with the tetrabytes `98090101 00000000` (lop_pre),
  `98060001 "a.mm"`, `98060001 "abXd"`, `98070001` (lop_line 1) and
  `fd000000` gives, after the expected error messages,
  `0000000000000000: fd000000 ("(null)", line 1)`. Here `(null)` is only
  what macOS's libc prints; the behavior is undefined.
- **Proposed patch:** set `cur_file` before reading the name. With this
  change the example prints `("a.mm", line 1)`.

  ```text
  @x [20] l.265
  case lop_file:@+if (file_name[y]) {
     for (j=z;j>0;j--) read_tet();
     cur_file=y;
  @y
  case lop_file:@+if (file_name[y]) {
     cur_file=y;
     for (j=z;j>0;j--) read_tet();
  @z
  ```

### 10. mmmix: `mmmix -s` never halts when built with `-O2`

- **Where:** `mmix-pipe.w` §10 (lines 226–234, `MMIX_silent`) and §304
  (line 5443).
- **Symptom:** built with clang `-O2`, `mmmix -s` never halts, whatever the
  program. The same sources built with Knuth's flags (`-g -fPIE`) work. The
  local variable `octa breakpoint` of `MMIX_silent` is never initialized, but
  line 5443 compares it with `inst_ptr` in every cycle. The optimizer
  apparently exploits this undefined behavior.
- **Reproduce:** after `mmix -Dhello.mmb hello`, the command
  `timeout 10 mmmix-O2 -s plain.mmconfig hello.mmb` prints nothing and times
  out. The online mode of the same build (`10000`) halts at time 405.
- **Proposed patch:** give `breakpoint` a value that can never be fetched.
  With this change the `-O2` build prints "hello, world" and halts.

  ```text
  @x [10] l.228
    octa breakpoint;
  @y
    octa breakpoint;
    breakpoint.h=breakpoint.l=0xffffffff; /* never fetched */
  @z
  ```

### 11. mmix-pipe: `specval` returns an uninitialized value

- **Where:** `mmix-pipe.w` §93 (lines 1917–1923).
- **Symptom:** when the value of a register is not yet known, `specval` sets
  `res.p` but leaves `res.o` uninitialized. For a CSxx instruction whose X
  value is not yet known and whose condition holds, stage 1 clears `b.p` but
  keeps the garbage in `b.o`. The trace then shows a `b=` field.
- **Reproduce:** dump the program below with `mmix -Dcs.mmb cs`, run
  `mmmix plain.mmconfig cs.mmb`, and give `v1` and `1000`. The trace shows
  `Committing 110: 64030404(cset)* y=1 z=1 b=110 x=1!l[3] state=3`. The value
  depends on the build; another build showed `b=128`.

  ```text
          LOC   #100
  Main    SETL  $1,100
          SETL  $2,7
          DIV   $3,$1,$2
          SETL  $4,1
          CSP   $3,$4,$4
          TRAP  0,Halt,0
  ```

- **Proposed patch:** with this change the `b=` field disappears.

  ```text
  @x [93] l.1921
    else res.p=r->up;
  @y
    else res.o=zero_octa,res.p=r->up;
  @z
  ```

### 12. mmix-pipe: shift by a negative amount

- **Where:** `mmix-pipe.w` §153 (line 2933, `bp_npower=1<<(bp_n-1)`).
- **Symptom:** when `branchpredictbits` is 0, the amount of the shift is −1.
  Zero is the default, used for example by `primes.mmconfig`, where that line
  is commented out. The result is never used, so there is no visible harm.
- **Reproduce:** a UBSan build (`-fsanitize=undefined`) with a configuration
  that has `branchpredictbits 0` reports `mmix-pipe.w:2933:13: runtime
  error: shift exponent -1 is negative`.
- **Proposed patch:**

  ```text
  @x [153] l.2933
  bp_npower=1<<(bp_n-1); /* $2^{n-1}$, the sign bit of an $n$-bit number */
  @y
  if (bp_n)
    bp_npower=1<<(bp_n-1); /* $2^{n-1}$, the sign bit of an $n$-bit number */
  @z
  ```

## Minor items

These have little or no visible effect, or may be intended.

- **mmixal, redefining a symbol with IS or GREG:** "Define the label" (§109,
  line 2721) sets `cur_loc` to the operand of IS before it checks the
  symbol. When the check fails with "already defined" (`derr`), the
  statement `cur_loc=acc` (line 2751) is skipped. So the next instruction
  is placed at the IS operand. For example, with `LOC #100`, `z IS 5`,
  `z IS #1000`, `w TETRA 1`, the tetrabyte `w` goes to #1000 instead of
  #100. An error has already been reported, so the damage is small.
- **mmix-sim, branch penalty:** `sclock.l+=2` (§93, line 2116) does not
  carry into `sclock.h`.
- **mmix-sim, the rL "hole" of SAVE:** `l[(O+L)&lring_mask].l=L` (§102,
  line 2274) sets only the low tetrabyte. The high tetrabyte of the saved
  octabyte keeps an old value.
- **mmix-sim, TRAP arguments:** §94 (lines 2140–2141) reads `ll+1`. When `ll`
  is the last tetrabyte of a 2048-byte chunk, this is beyond the chunk
  (macOS happened to give 0).

The last three were found by reading the code. They were not reproduced with
a minimal program.

## Typos in mmix-doc.w

- **§7, line 296 (LDTU):** the range of an unsigned tetrabyte is given as
  "0 and 4,294,967,296, inclusive". It should be
  4,294,967,295 ($2^{32}-1$, as §6, line 194 says).
- **§10, line 564 (NXOR):** the index entry is `@.NAND@>`; it should be
  `@.NXOR@>`.
- **§7, lines 263 and 277 (LDBU, LDWU):** the bullet line ends with `@>`
  instead of `\>`.
- **§8, lines 351 and 364 (STBU, STWU) and §22, line 1241 (FADD):** the
  bullet line has a stray `@>` before `\>`.
- **§28, lines 1588–1589 (rounding table):** ROUND_UP is glossed as "away
  from zero" and ROUND_DOWN as "toward zero". This is right only for
  positive numbers. §21 (line 1173) and §32 (line 2025) say "toward
  $+\infty$" and "toward $-\infty$". ROUND_OFF is the mode that rounds toward
  zero.

## Relation to the bug reports on mmix.cs.hm.edu

The 17 reports on <https://mmix.cs.hm.edu/bugs/index.html> were checked on
2026-09-27.

- **Already reported:** the change of the "tricky but OK" test in
  `mmix-arith.w` §49 from `d>53` to `d>54` is the fix for "Rounding of
  floating point numbers" by Joe Zbiciak (2015-07-17). The page still lists
  it as "open", but the June 2025 release contains the fix (line 863).
- **Related:** "IS may produce misleading error messages" by Martin Ruckert
  (2012-01-25) is about the same section as the first minor item ("Define
  the label"). That report concerns an undefined operand, though, so it is a
  different bug.
- **New:** bugs 1–12, the minor items and the typos in `mmix-doc.w` do not
  appear on the page.

The other reported bugs are fixed in the June 2025 release, among them the
buffer overrun of the `b` command, `printf(command_buf)`, the parentheses in
the rU update, the `calloc` check in mmix-config, `get_reader`, `alloc_slot`
and the `time_t` cast in mmotype.

## Already fixed

These were found while working on the 2013 release, and turned out to be
fixed already in the June 2025 release.

- **mmix-arith §35:** the tininess bound for short floats, `0x100000`, is now
  `0x800000` (line 591).
- **mmix-arith §49:** the "tricky but OK" test `d>53` is now `d>54`
  (line 863). With the old test, $-2^{64}+1853.1765$ gave
  `c3f0000000000000`.
