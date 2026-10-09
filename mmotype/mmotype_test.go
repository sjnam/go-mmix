//line mmotype.w:723
package main

import (
	"bytes"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func typeFile(t *testing.T, mmo []byte, opts ...string) (stdout, stderr string, code int) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "test.mmo")
	if err := os.WriteFile(path, mmo, 0o644); err != nil {
		t.Fatal(err)
	}
	var o, e bytes.Buffer
	code = mmotype(append(append([]string{"mmotype"}, opts...), path), &o, &e, time.UTC)
	return o.String(), e.String(), code
}

func testMMO(t *testing.T) []byte {
	b, err := hex.DecodeString(strings.Join(strings.Fields(testMMOHex), ""))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

//line mmotype.w:760
const testMMOHex = `98090101 36f4a363 98012001 00000000 00000000 00000000 61620000
98010002 00000001 2345678c 98060002 74657374 2e6d6d73 98070007 f0000000
98024000 98070009 8103fe01 42030000 9807000a 00000000 98010002 00000001
2345a768 98050010 0100fff5 98040ff7 98032001 00000000 98060102 666f6f2e
6d6d7300 98070004 f000000a 98080005 00000200 00fe0000 98012001 0000000a
00006364 98000001 98000000 980a00fe 20000000 00000008 00000001 2345678c
980b0000 203a5040 50404020 41204220 43094408 83404020 4d206120 69056e01
2345678c 81400f61 fe820000 980c000a`

//line mmotype.w:770
func TestKnuthExample(t *testing.T) {
	out, errs, code := typeFile(t, testMMO(t))
	if code != 0 || errs != "" || out != testOut {
		t.Errorf("종료 코드 %d, 표준 오류 %q, 표준 출력:\n%s", code, errs, out)
	}
	out, _, _ = typeFile(t, testMMO(t), "-s")
	if want := testOut[strings.Index(testOut, "Symbol"):]; out != want {
		t.Errorf("-s의 출력:\n%s", out)
	}
}

const testOut = `File was created Sun Mar 21 07:44:35 1999
2000000000000000: 00000000
2000000000000004: 00000000
2000000000000008: 61620000
000000012345678c: f0000000 ("test.mms", line 7)
000000012345a790: 8103fe01 (line 9)
000000012345a794: 42030000 (line 10)
000000012345a798: 00000000 (line 10)
000000012345a794: 0100fff5
000000012345678c: 00000ff7
2000000000000000: 000000012345a768
000000012345a768: f000000a ("foo.mms", line 4)
Special data 5 at loc 000000012345a76c (line 5)
                   00000200
                   00fe0000
200000000000000a: 00006364
200000000000000c: 98000000
g254: 2000000000000008
g255: 000000012345678c
Symbol table (beginning at tetra 48):
    ABCD = #2000000000000008 (3)
    Main = #012345678c (1)
    a = $254 (2)
`

//line mmotype.w:809
func TestBrokenInputs(t *testing.T) {
	good := testMMO(t)
	bad := bytes.Clone(good)
	bad[len(bad)-1] = 5 // YZ of |lopEnd| from 10 to 5
	if _, errs, code := typeFile(t, bad, "-s"); code != 0 ||
		errs != "YZ field at lop_end should have been 53!\n" {
		t.Errorf("종료 코드 %d, %q", code, errs)
	}
	if _, errs, code := typeFile(t, good[:30]); code != -3 ||
		errs != "Unexpected end of file after 7 tetras!\n" {
		t.Errorf("종료 코드 %d, %q", code, errs)
	}
	if _, errs, code := typeFile(t, []byte("hello, world")); code != -5 ||
		errs != "Input is not an MMO file (first two bytes are wrong)!\n" {
		t.Errorf("종료 코드 %d, %q", code, errs)
	}
}
