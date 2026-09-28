//line mmixsim.w:4759
package main

import (
	"bytes"
	"encoding/binary"
	hexenc "encoding/hex"
	"os"
	"strings"
	"testing"
	"time"
)

func simulate(t *testing.T, stdin string, args ...string) (stdout, stderr string, code int) {
	t.Helper()
	var o, e bytes.Buffer
	code = mmix(append([]string{"mmix"}, args...), strings.NewReader(stdin), &o, &e)
	return o.String(), e.String(), code
}

func writeMMO(t *testing.T, name string, main Octa, code ...Tetra) {
	t.Helper()
	tets := []Tetra{0x98090100, 0x98010002, Tetra(main >> 32), Tetra(main)}
	tets = append(tets, code...)
	tets = append(tets, 0x980a00ff, Tetra(main>>32), Tetra(main))
	var b []byte
	for _, x := range tets {
		b = binary.BigEndian.AppendUint32(b, x)
	}
	if err := os.WriteFile(name, b, 0o644); err != nil {
		t.Fatal(err)
	}
}

//line mmixsim.w:4799
func TestSilly(t *testing.T) {
	var files [3][]byte
	for i, name := range []string{"silly.mms", "silly.run", "silly.out"} {
		b, err := os.ReadFile("../examples/" + name)
		if err != nil {
			t.Fatal(err)
		}
		files[i] = b
	}
	mmo, err := hexenc.DecodeString(strings.Join(strings.Fields(sillyMMOHex), ""))
	if err != nil {
		t.Fatal(err)
	}
	t.Chdir(t.TempDir())
	os.WriteFile("silly.mmo", mmo, 0o644)
	os.WriteFile("silly.mms", files[0], 0o644)
	os.WriteFile("silly.run", files[1], 0o644)
	when := time.Unix(int64(binary.BigEndian.Uint32(mmo[4:])), 0)
	os.Chtimes("silly.mms", when, when)
	out, errs, _ := simulate(t, "i silly.run\n", "-i", "silly")
	want := strings.Replace(string(files[2]), "mmix> i silly.run\n", "mmix> ", 1)
	var lines []string
	for _, s := range strings.SplitAfter(want, "\n") {
		if !strings.HasPrefix(s, "Warning:") {
			lines = append(lines, s)
		}
	}
	if want = strings.Join(lines, ""); out != want {
		os.WriteFile("/tmp/silly.got", []byte(out), 0o644)
		t.Errorf("표준 출력이 silly.out과 다르다")
	}
	if errs != "Warning: TRIP at location 000000000000039c\n"+
		"Warning: floating point underflow at location 00000000000003a0\n" {
		t.Errorf("표준 오류 %q", errs)
	}
}

//line mmixsim.w:4837
const sillyMMOHex = `
98090101 6ab7bebd 98012001 00000000 2404fc01 3f04fc01 80818283 84858687
88898a8b 8c8d8e8f f0000002 f8000000 5f030405 97030405 9f28f305 ef28f305
98010001 00000100 98060003 73696c6c 792e6d6d 73000000 9807001d 0100fd05
0101fdfb 0102fbfa 0203fafa 030404fd 0405fcfb 0406fcfd 0407fcfc 0408fcfa
0609fcfe f61500f9 0609fcfe 0609fefc 150a0009 060bfa0a f61500f7 060cfcfc
060c1415 060c14fd f61500f8 2500fb01 040c00fe 050c00fc 070e0309 080f03f6
081002f6 35010001 09110001 08110001 0b1200ff 0a1200fd 050d0412 0c1203f6
0c1302f6 06141213 0614100f 0d140001 0c140001 0e150001 0f1500ff 1016fdfb
1016fcfc 1017fe00 f60200fc 1118fc15 1118fdfe 1118fdfc 1118fcfb 13180f10
f60200fd 1318fcfc 1218fcfc 15190200 141a0019 f6150032 141a0019 101b1919
161c09fc 161d09fe 171e0009 171e02fe 181ff4f4 1820f401 1921f402 1c202001
1c20fd01 1a20f401 1a1ff4f4 fe210003 f6010021 1d210103 1e221ff4 2023f6f5
0424f6f5 30252423 f4030000 f6180003 8906f100 8b07f104 98040004 30050607
48050000 e6060100 f6190006 f9000000 98040004 40000006 5100ffff 48000006
50000005 58000005 4100fffd 4900fffd 5100fffd 5900fffd 42000006 5300ffff
4a000006 52000005 5a000005 4300fffd 4b00fffd 5300fffd 5b00fffd 44000006
5500ffff 4c000006 54000005 5c000005 4500fffd 4d00fffd 5500fffd 5d00fffd
46000006 5700ffff 4e000006 56000005 5e000005 4700fffd 4f00fffd 5700fffd
5f00fffd 2304f10c f4030000 f6180003 8b07f124 8b06f120 98040004 32080607
48080000 e6060100 f6190006 f9000000 fedcba98 9807009f 76543210 ffeeddcc
980700a0 bbaa9988 34f300f6 c1f2f400 f60500f5 f8000000 9804000c f504fff8
e307002c 9e070704 9f070430 9a460404 9b460400 9c460404 9d460400 9503f115
f4030000 f6180003 e3f20001 21f30404 8f28f118 8b07f12c 8b06f128 98040007
32080607 48080000 e6060100 f6190006 c105f200 f9000000 98040005 3928fe33
3928fe34 faff0000 f71300fe e7fd0400 0464fec8 f61500fd ff0164fe 0664fec8
f714000a f61400fe f20b0001 fb0000ff 00000000 98010001 00000060 980700cb
f2ff0000 00000001 25000101 f8020000 fe320019 e4328100 093c0001 f61b003c
f0000000 98010001 00000000 980700d6 fe320019 e4328200 e532fb00 00000001
98050018 01ffffe4 f6190032 feff0000 f9000000 98050010 0100ffef e305abcd
fe010004 f2030010 240a0304 f6040001 f80b0003 980a00f1 20000000 00000000
00000000 00000000 00000000 00000000 01020408 10204080 ff5ffb6a 4534a3f7
7f6001b4 c67bc809 00000000 00030000 00000000 00020000 00000000 00010000
7ff10000 00000000 7ff00000 00000000 3fe00000 00000000 80000000 00000000
00000000 00000abc 00000000 00000100 980b0000 203a5050 50502042 20694020
67205f30 42206520 67206909 6e289520 45206e09 642c9660 20464010 10206920
6e206120 6c205f20 49206e20 73097404 90482061 10206e20 64206c20 6501721c
97404060 60204a20 6d207020 5f205020 6f097018 924c206f 20612064 205f6030
42206520 67206909 6e209320 45206e09 64249454 20652073 09740891 4d206120
69026e01 00812053 20742061 10207220 74205f20 49206e20 73097400 8f706070
30612064 20641f79 f68a0f7a f58b2066 206c2069 0f70f48c 68206120 6c0f66fc
84206920 6e0f66fb 856e2065 2067205f 207a2065 20720f6f fd837210 10101010
10101010 10101010 1010306f 2075206e 2064205f 70206420 6f20770f 6ef7896f
20660f66 f9872075 0f70f888 1f79f38d 0f7af28e 20736020 69206720 5f206e20
610f6efa 866d2061 206c0f6c fe820000 980c004f`

//line mmixsim.w:4888
var helloCode = []Tetra{
	0x8fff0100,                         // |LDOU $255,argv,0|
	0x00000701,                         // |TRAP 0,Fputs,StdOut|
	0xf4ff0003,                         // |GETA $255,String|
	0x00000701,                         // |TRAP 0,Fputs,StdOut|
	0x00000000,                         // |TRAP 0,Halt,0|
	0x2c20776f, 0x726c640a, 0x00000000} // |String BYTE ", world",#a,0|

func TestHello(t *testing.T) {
	t.Chdir(t.TempDir())
	writeMMO(t, "hello.mmo", 0x100, helloCode...)
	out, errs, code := simulate(t, "", "hello")
	if out != "hello, world\n" || errs != "" || code != 8 {
		t.Errorf("출력 %q, 오류 %q, 종료 코드 %d", out, errs, code)
	}
	out, _, _ = simulate(t, "", "-t9", "-s", "hello")
	if out != helloTrace {
		t.Errorf("추적 출력:\n%s", out)
	}
}

const helloTrace = "" +
	"         1. 0000000000000100: 8fff0100 (LDOUI) " +
	"$255=g[255] = M8[#4000000000000008] = #4000000000000018\n" +
	"  1 instruction, 1 mem, 1 oop; 0 good guesses, 0 bad\n" +
	"hello         1. 0000000000000104: 00000701 (TRAP) " +
	"$255 = Fputs(StdOut,#4000000000000018) = 5\n" +
	"  2 instructions, 1 mem, 6 oops; 0 good guesses, 0 bad\n" +
	"         1. 0000000000000108: f4ff0003 (GETA) $255=g[255] = #114\n" +
	"  3 instructions, 1 mem, 7 oops; 0 good guesses, 0 bad\n" +
	", world\n" +
	"         1. 000000000000010c: 00000701 (TRAP) " +
	"$255 = Fputs(StdOut,#114) = 8\n" +
	"  4 instructions, 1 mem, 12 oops; 0 good guesses, 0 bad\n" +
	"         1. 0000000000000110: 00000000 (TRAP) Halt(0)\n" +
	"  5 instructions, 1 mem, 17 oops; 0 good guesses, 0 bad\n" +
	"  (halted at location #0000000000000110)\n" +
	"  5 instructions, 1 mem, 17 oops; 0 good guesses, 0 bad\n" +
	"  (halted at location #0000000000000110)\n"

//line mmixsim.w:4931
func TestBadInputs(t *testing.T) {
	t.Chdir(t.TempDir())
	_, errs, code := simulate(t, "")
	if code != -1 || !strings.HasPrefix(errs,
		"Usage: mmix <options> progfile command line-args...\n with these options:") {
		t.Errorf("인자가 없을 때: %d %q", code, errs)
	}
	_, errs, code = simulate(t, "", "nothing")
	if code != -3 || errs != "Can't open the object file nothing or nothing.mmo!\n" {
		t.Errorf("파일이 없을 때: %d %q", code, errs)
	}
	os.WriteFile("bad.mmo", []byte{0x98, 0x09, 0x01}, 0o644)
	_, errs, code = simulate(t, "", "bad")
	if code != -4 || errs != "Bad object file! (Try running MMOtype.)\n" {
		t.Errorf("잘린 목적 파일: %d %q", code, errs)
	}
	writeMMO(t, "hello.mmo", 0x100, helloCode...)
	_, errs, code = simulate(t, "", "-c300", "hello")
	if code != -2 || errs != "Panic: The number of local registers must be a power of 2!\n" {
		t.Errorf("-c300: %d %q", code, errs)
	}
}

//line mmixsim.w:4962
func TestOddities(t *testing.T) {
	t.Chdir(t.TempDir())
	writeMMO(t, "ovf.mmo", 0x100,
		0xe0017fff, // |SETH $1,#7fff|
		0x20020101, // |ADD $2,$1,$1|
		0x00000000) // |TRAP 0,Halt,0|
	if out, _, _ := simulate(t, "", "-e", "ovf"); out != "" {
		t.Errorf("-e가 무언가를 추적했다:\n%s", out)
	}
	out, _, _ := simulate(t, "", "-eff00", "ovf")
	if !strings.Contains(out, "(ADD) rL=3, $2=l[2] = ") {
		t.Errorf("-eff00의 출력:\n%s", out)
	}
	writeMMO(t, "priv.mmo", 0x100,
		0xe3010005, // |SETL $1,5|
		0xfd000000, // |SWYM|
		0x00010203, // |TRAP 1,2,3|
		0xfd000000, // |SWYM|
		0xf0000001, // |JMP @+4|
		0x00000000) // |TRAP 0,Halt,0|
	out, _, _ = simulate(t, "c\nc\nrG=40\nq\n", "-i", "-t9", "priv")
	for _, want := range []string{
		"000000000000010c: fd000000 (SWYM) privileged instruction!\n",
		"0000000000000114: 00000000 (TRAP) privileged instruction!\n",
		"mmix> g[19]=255\n"} {
		if !strings.Contains(out, want) {
			t.Errorf("%q가 없다:\n%s", want, out)
		}
	}
}
