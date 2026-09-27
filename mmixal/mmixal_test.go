//line mmixal.w:3669
package main

import (
	"bytes"
	"fmt"
	"os"
	"strings"
	"testing"
)

func assembleFile(t *testing.T, name, src string, opts ...string) (mmo []byte, lst, stderr string, code int) {
	t.Helper()
	t.Chdir(t.TempDir())
	if err := os.WriteFile(name, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	args := append(append([]string{"mmixal"}, opts...), "-l", "out.lst", name)
	var e bytes.Buffer
	code = mmixal(args, &e, 0x36f4a363)
	mmo, _ = os.ReadFile(strings.TrimSuffix(name, "s") + "o")
	l, _ := os.ReadFile("out.lst")
	return mmo, string(l), e.String(), code
}

//line mmixal.w:3697
func TestKnuthExample(t *testing.T) {
	mmo, lst, stderr, code := assembleFile(t, "test.mms", testMMS)
	if code != 0 || stderr != "" {
		t.Fatalf("종료 코드 %d, 표준 오류 %q", code, stderr)
	}
	var got []string
	for i := 0; i+4 <= len(mmo); i += 4 {
		got = append(got, fmt.Sprintf("%02x%02x%02x%02x", mmo[i], mmo[i+1], mmo[i+2], mmo[i+3]))
	}
	if g, w := strings.Join(got, " "), strings.Join(strings.Fields(testMMO), " "); g != w {
		t.Errorf("test.mmo가 다르다:\n얻음 %s\n원함 %s", g, w)
	}
	if lst != testLST {
		t.Errorf("목록이 다르다:\n%s", lst)
	}
}

//line mmixal.w:3715
const testMMS = `% A peculiar example of MMIXAL
     LOC   Data_Segment      % location #2000000000000000
     OCTA  1F                % a future reference
a    GREG  @                 % $254 is base address for ABCD
ABCD BYTE  "ab"              % two bytes of data
     LOC   #123456789        % switch to the instruction segment
Main JMP   1F                % another future reference
     LOC   @+#4000           % skip past 16384 bytes
2H   LDB   $3,ABCD+1         % use the base address
     BZ    $3,1F; TRAP       % and refer to the future again
# 3 "foo.mms"                % this comment is a line directive
     LOC   2B-4*10           % move 10 tetras before previous location
1H   JMP   2B                % resolve previous references to 1F
     BSPEC 5                 % begin special data of type 5
     TETRA &a<<8             % four bytes of special data
     WYDE  a-$0              % two more bytes of special data
     ESPEC                   % end a special data packet
     LOC   ABCD+2            % resume the data segment
     BYTE  "cd",#98          % assemble three more bytes of data
`

//line mmixal.w:3737
const testMMO = `98090101 36f4a363 98012001 00000000 00000000 00000000 61620000
98010002 00000001 2345678c 98060002 74657374 2e6d6d73 98070007 f0000000
98024000 98070009 8103fe01 42030000 9807000a 00000000 98010002 00000001
2345a768 98050010 0100fff5 98040ff7 98032001 00000000 98060102 666f6f2e
6d6d7300 98070004 f000000a 98080005 00000200 00fe0000 98012001 0000000a
00006364 98000001 98000000 980a00fe 20000000 00000008 00000001 2345678c
980b0000 203a5040 50404020 41204220 43094408 83404020 4d206120 69056e01
2345678c 81400f61 fe820000 980c000a`

//line mmixal.w:3747
const testLST = `                   % A peculiar example of MMIXAL
                        LOC   Data_Segment      % location #2000000000000000
2000000000000000:       OCTA  1F                % a future reference
 ...000: xxxxxxxx
 ...004: xxxxxxxx
($254=#20000000    a    GREG  @                 % $254 is base address for ABCD
         00000008)
 ...008: 6162      ABCD BYTE  "ab"              % two bytes of data
                        LOC   #123456789        % switch to the instruction segment
000000012345678c:  Main JMP   1F                % another future reference
 ...78c: f0xxxxxx
                        LOC   @+#4000           % skip past 16384 bytes
000000012345a790:  2H   LDB   $3,ABCD+1         % use the base address
 ...790: 8103fe01
 ...794: 4203xxxx       BZ    $3,1F; TRAP       % and refer to the future again
 ...798: 00000000
                   # 3 "foo.mms"                % this comment is a line directive
                        LOC   2B-4*10           ` +
	`% move 10 tetras before previous location
 ...768: f000000a  1H   JMP   2B                % resolve previous references to 1F
                        BSPEC 5                 % begin special data of type 5
         00000200       TETRA &a<<8             % four bytes of special data
         00fe           WYDE  a-$0              % two more bytes of special data
                        ESPEC                   % end a special data packet
                        LOC   ABCD+2            % resume the data segment
200000000000000a:       BYTE  "cd",#98          % assemble three more bytes of data
 ...00a:     6364
 ...00c: 98      

Symbol table:
 ABCD = #2000000000000008 (3)
 Main = #000000012345678c (1)
 a = $254 (2)
`

//line mmixal.w:3788
func TestErrorMessages(t *testing.T) {
	_, lst, stderr, code := assembleFile(t, "errs.mms", errsMMS)
	if code != 8 || stderr != errsErr {
		t.Errorf("종료 코드 %d, 표준 오류:\n%s", code, stderr)
	}
	if !strings.Contains(lst, " Foo:w = #000000000000000c (7)\n") {
		t.Errorf("기호표가 다르다:\n%s", lst)
	}
}

const errsMMS = `Main ADD  $1,$2,x
x    IS   $300
     SUB  $1,5,$2
     BYTE 256,"",'a
     LDA  $1,#1000000
y    GREG #1000000
     LDA  $1,y+17
     JMP  3F+4
     DIV  $1,$2,7//3
2X   SWYM
     FOO  1,2
     LOC  @+(1
     OCTA 9F,-x
z    IS   5
z    IS   6
rA   IS   7
     PREFIX Foo:
     SET  $1,$2
w    SETL $0,1B
`

//line mmixal.w:3820
const errsErr = `"errs.mms", line 1: Z field is undefined!
"errs.mms", line 2 warning: register number too large, will be reduced mod 256
"errs.mms", line 3 warning: Y field of ` + "`SUB'" + ` should be a register number
"errs.mms", line 4: illegal character constant!
"errs.mms", line 5: no base address is close enough to the address A!
"errs.mms", line 7 warning: register number too large, will be reduced mod 256
"errs.mms", line 8: cannot add to an undefined quantity!
"errs.mms", line 9 warning: illegal fraction
"errs.mms", line 10: improper local label ` + "`2X'" + `!
"errs.mms", line 11: unknown operation code ` + "`FOO'" + `!
"errs.mms", line 12 warning: missing right parenthesis
"errs.mms", line 13: can negate pure values only!
"errs.mms", line 15: symbol ` + "`z'" + ` is already defined!
(8 errors were found.)
`

//line mmixal.w:3841
func TestStaleLastLine(t *testing.T) {
	mmo, _, stderr, _ := assembleFile(t, "stale.mms", "Main SWYM 1,2,3\nabc")
	want := "\"stale.mms\", line 2 warning: no opcode; label `abc' will be ignored\n"
	if stderr != want {
		t.Errorf("표준 오류 %q", stderr)
	}
	if n := bytes.Count(mmo, []byte{0xfd, 1, 2, 3}); n != 1 {
		t.Errorf("SWYM이 %d번 어셈블되었다", n)
	}
}

func TestUsage(t *testing.T) {
	var e bytes.Buffer
	if code := mmixal([]string{"mmixal"}, &e, 0); code != -1 ||
		e.String() != "Usage: mmixal [-x] [-l listingname] [-b buffersize] "+
			"[-o objectfilename] sourcefilename\n" {
		t.Errorf("종료 코드 %d, %q", code, e.String())
	}
}
