//line mmmix.w:1107
package main

import (
	"bytes"
	"crypto/sha256"
	hexenc "encoding/hex"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

func simulate(t *testing.T, stdin string, args ...string) (stdout, stderr string, code int) {
	t.Helper()
	var o, e bytes.Buffer
	code = mmmix(append([]string{"mmmix"}, args...), strings.NewReader(stdin), &o, &e)
	return o.String(), e.String(), code
}

func digest(s string) string {
	h := sha256.Sum256([]byte(s))
	return hexenc.EncodeToString(h[:8])
}

//line mmmix.w:1138
const (
	script1 = "@8000000000010000\nv1ff\n2000\np\ns\nq\n"
	script2 = "@8000000000010000\n100000\ns\nD*\nS*\ng255\nm10000\nq\n"

//line mmmix.w:1141
)

func TestKnuthFiles(t *testing.T) {
	for _, c := range []struct{ cfg, prog, script, out, err string }{
		{"plain", "test.mmix", script1, "423456fca2773436", "e3b0c44298fc1c14"},
		{"test", "test.mmix", script1, "d4d068ee554a3c31", "e3b0c44298fc1c14"},
		{"deluxe", "test.mmix", script1, "97d870adbb478180", "e3b0c44298fc1c14"},
		{"test1", "test1.mmix", script1, "d5b1d72ebce4cdb9", "e3b0c44298fc1c14"},
		{"test2", "test2.mmix", script1, "07708e2ede82a155", "3f969b9f0f495734"},
		{"primes", "primes.mmix", script2, "ac5cd3dd8bc6b7d5", "e3b0c44298fc1c14"},
		{"primesx", "primes.mmix", script2, "5d5b5edd7dc99d31", "e3b0c44298fc1c14"},
		{"plain", "halves.mmix", script2, "c89243d60644ae78", "e3b0c44298fc1c14"},
	} {
		out, err, code := simulate(t, c.script,
			"../examples/"+c.cfg+".mmconfig", "../examples/"+c.prog)
		if code != 0 || digest(out) != c.out || digest(err) != c.err {
			t.Errorf("%s %s: code %d, stdout %s, stderr %s", c.cfg, c.prog,
				code, digest(out), digest(err))
		}
	}
}

//line mmmix.w:1169
const (
	helloMMB = "00000000000001008fff010000000701f4ff000300000701000000002c20776f726c640a" +
		"0000000000000000000000004000000000000000400000000000002840000000000000180000" +
		"000000000000400000000000001868656c6c6f2e6d6d6f00000000000000000000000000000060" +
		"000000000000000000000000000001400000000000000800000000000000020000000000000100" +
		"00000000000000006000000000000080ff000000000000000000000000000000"
	helloRun = "mmmix> Running 3000 at time 0\nhello.mmo, world\nHalted at time 405\n" +
		"mmmix> Predictions: 0 in agreement, 0 in opposition; 0 good, 0 bad\n" +
		"Instructions issued per cycle:\n  0   380\n  1   26\n" +
		"mmmix> Simulation ended at time 406.\n" +
		"Predictions: 0 in agreement, 0 in opposition; 0 good, 0 bad\n" +
		"Instructions issued per cycle:\n  0   380\n  1   26\n"

//line mmmix.w:1181
)

func writeHex(t *testing.T, name, h string) string {
	t.Helper()
	b, err := hexenc.DecodeString(h)
	if err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, b, 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestHello(t *testing.T) {
	p := writeHex(t, "hello.mmb", helloMMB)
	out, _, code := simulate(t, "", "-s", "../examples/plain.mmconfig", p)
	if out != "hello.mmo, world\n" || code != 8 {
		t.Errorf("silent: %q, code %d", out, code)
	}
	out, _, code = simulate(t, "3000\ns\nq\n", "../examples/plain.mmconfig", p)
	if out != helloRun || code != 0 {
		t.Errorf("interactive: %q, code %d", out, code)
	}
}

//line mmmix.w:1211
const primesMMB = "0000000000000100e3fe0003c1fbf700a6fef8fbe7fb000242fb0013e7fe0002c1faf70086f9" +
	"f8fa1cfdfef9fefc000643fcfffb30fffdf94dfffff6e7fa0002f1fffff9466972737420466976" +
	"652048756e64726564205072696d65730a00202020000023fff6000000070135fa000220fafaf7" +
	"23fff61b0000070186f9f8faaff5f80023fff8041df9f90afefc0006e7fc0030a3fcff0025ffff" +
	"015bf9fffb23fff80000000701e7fa006451fafff423fff6190000070131fffa625bffffed0000" +
	"000000000000200000000000000000020000000000000000000000000000400000000000000040" +
	"000000000000284000000000000018000000000000000040000000000000187072696d65732e6d" +
	"6d6f00000000000000000000000000006000000000000000000000000000000140000000000000" +
	"0800000000000000022030303030000000000000000000013cfffffffffffffc1a200000000000" +
	"03e8000000000000000060000000000000680000000000000100000000000000000060000000" +
	"000000d0f5000000000000000000000000000000"

func TestPrimes(t *testing.T) {
	p := writeHex(t, "primes.mmb", primesMMB)
	for _, cfg := range []string{"plain", "deluxe"} {
		out, _, code := simulate(t, "", "-s", "../examples/"+cfg+".mmconfig", p)
		if digest(out) != "bd64b4848d0e1d0d" || code != 0 {
			t.Errorf("%s: stdout %s, code %d", cfg, digest(out), code)
		}
	}
}

//line mmmix.w:1236
func TestErrors(t *testing.T) {
	dir := t.TempDir()
	file := func(name, text string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
		return p
	}
	empty := file("empty.mmconfig", "")
	ok := file("ok.mmix", "000000010000:\n 0000000100000000\n")
	for _, c := range []struct {
		args []string
		err  string
		code int
	}{
		{nil, "Usage: mmmix [-s] configfile progfile\n", -3},
		{[]string{"-x", "a", "b"}, "Usage: mmmix [-s] configfile progfile\n", -3},
		{[]string{filepath.Join(dir, "nope"), ok},
			"Can't open configuration file " + filepath.Join(dir, "nope") + "!\n", -1},
		{[]string{file("b1", "sh*t % obscene\n"), ok},
			"Configuration syntax error: Specification can't start with `sh*t'!\n", -1},
		{[]string{file("b2", "memaddresstime 0\n"), ok},
			"Configuration error: memaddresstime must be >= 1!\n", -1},
		{[]string{file("b3", "unit 0 0123456789abcdef0123456789abcdef"+
			"0123456789abcdef0123456789ABCDEG\n"), ok},
			"Configuration error: `G' is not a hex digit!\n", -1},
		{[]string{file("b4", "Dcache blocksize 1024\nScache blocksize 64\n"), ok},
			"Configuration error: Scache blocks smaller than Dcache blocks!\n", -1},
		{[]string{empty, file("bad.mmix", "0000000100: x\nxyz\n")},
			"Panic: Improper hexadecimal file line: `0000000100: x\n'!\n", -3},
		{[]string{empty, filepath.Join(dir, "nope.mmb")},
			"Panic: Can't open MMIX binary file " + filepath.Join(dir, "nope.mmb") + "!\n", -3},
	} {
		_, err, code := simulate(t, "", c.args...)
		if err != c.err || code != c.code {
			t.Errorf("%q: %q, code %d", c.args, err, code)
		}
	}
}

//line mmmix.w:1281
func assembleKernel(t *testing.T) string {
	t.Helper()
	mmo := filepath.Join(t.TempDir(), "nnix.mmo")
	cmd := exec.Command("go", "run", "../mmixal", "-b", "250", "-o", mmo, "../nnix/nnix.mms")
	if out, err := cmd.CombinedOutput(); err != nil || len(out) != 0 {
		t.Fatalf("mmixal: %v\n%s", err, out)
	}
	return mmo
}

//line mmmix.w:1295
func TestKernelMatchesMagic(t *testing.T) {
	k := assembleKernel(t)
	for _, prog := range []struct{ name, hex string }{
		{"hello.mmb", helloMMB}, {"primes.mmb", primesMMB},
	} {
		p := writeHex(t, prog.name, prog.hex)
		for _, cfg := range []string{"plain", "deluxe"} {
			c := "../examples/" + cfg + ".mmconfig"
			mOut, _, mCode := simulate(t, "", "-s", c, p)
			kOut, kErr, kCode := simulate(t, "", "-s", "-k"+k, c, p)
			if kOut != mOut || kCode != mCode || kErr != "" {
				t.Errorf("%s %s: magic %q %d, kernel %q %d %q",
					prog.name, cfg, mOut, mCode, kOut, kCode, kErr)
			}
		}
	}
}

//line mmmix.w:1319
func TestKernelUsesDevice(t *testing.T) {
	k := assembleKernel(t)
	p := writeHex(t, "hello.mmb", helloMMB)
	out, _, code := simulate(t, "v40\n1000000\nq\n", "-k"+k, "../examples/plain.mmconfig", p)
	for _, want := range []string{
		"(spec_write 12340d0700000008 to 0001000000000030 ",
		"(spec_write 4000000000000018 to 0001000000000008 ",
		"(spec_write 0000000000000701 to 0001000000000018 ",
		"hello.mmo", ", world\n", "Halted at time ",
	} {
		if !strings.Contains(out, want) || code != 0 {
			t.Errorf("missing %q (code %d)", want, code)
		}
	}
}

//line mmmix.w:1343
const (
	spanMMB = "0000000000000100e0002000eb001ff081010018e0024000a1010200c1ff000000000701e0ff" +
		"2000ebff500000000400e0ff2000ebff3ffc0000070100000000000000000000000020000000" +
		"00001ff06120737472696e672074686174207370616e732074776f2070616765730a00000000" +
		"00000000000020000000000050002000000000003ffc00000000000000090000000000000000" +
		"4000000000000000400000000000002040000000000000180000000000000000400000000000" +
		"00187370616e0000000000000000000000006000000000000000000000000000000140000000" +
		"000000080000000000000002000000000000010000000000000000006000000000000080ff00" +
		"0000000000000000000000000000"
	farMMB = "0000000000000100e0002000e9000000ea0000808d0100000000000000000000400000000000" +
		"0000400000000000002040000000000000180000000000000000400000000000001866617200" +
		"0000000000000000000000006000000000000000000000000000000140000000000000080000" +
		"000000000002000000000000010000000000000000006000000000000080ff00000000000000" +
		"0000000000000000"

//line mmmix.w:1357
)

func TestKernelPaging(t *testing.T) {
	k := assembleKernel(t)
	p := writeHex(t, "span.mmb", spanMMB)
	c := "../examples/plain.mmconfig"
	mOut, _, mCode := simulate(t, "abcdefgh\n", "-s", c, p)
	kOut, kErr, kCode := simulate(t, "abcdefgh\n", "-s", "-k"+k, c, p)
	want := "a string that spans two pages\nStdIn> abcdefgh"
	if kOut != want || mOut != want || kCode != mCode || kErr != "" {
		t.Errorf("span: magic %q %d, kernel %q %d %q", mOut, mCode, kOut, kCode, kErr)
	}
	p = writeHex(t, "far.mmb", farMMB)
	_, kErr, kCode = simulate(t, "", "-s", "-k"+k, c, p)
	if kErr != "NNIX: page fault I can't serve\n" || kCode != -1 {
		t.Errorf("far: %q %d", kErr, kCode)
	}
}

//line mmmix.w:1385
const (
	forkMMB = "000000000000010000000b00c105ff00e30100504a050004e30100432303fe00a10103002303" +
		"fe03a1010300e304000021020430a1020301e30603e8250606015506ffff23fffe0300000701" +
		"21040401310604055106fff723fffe000000070100000000000000002000000000000000410a" +
		"003f302000000000000000000000400000000000000040000000000000204000000000000018" +
		"00000000000000004000000000000018666f726b000000000000000000000000600000000000" +
		"0000000000000000000140000000000000080000000000000002200000000000000000000000" +
		"0000010000000000000000006000000000000088fe000000000000000000000000000000"
	manyMMB = "0000000000000100e301000000000b0042ff000c40ff000521010101310201045102fffb0000" +
		"00002303fe00e302002da102030423fffe000000070100000000e302ea60250202015502ffff" +
		"210201312303fe00a102030423fffe0000000701000000000000000020000000000000007069" +
		"64203f0a00000000000000000000400000000000000040000000000000204000000000000018" +
		"000000000000000040000000000000186d616e79000000000000000000000000600000000000" +
		"0000000000000000000140000000000000080000000000000002200000000000000000000000" +
		"0000010000000000000000006000000000000088fe000000000000000000000000000000"

//line mmmix.w:1400
)

//line mmmix.w:1405
func TestKernelFork(t *testing.T) {
	k := assembleKernel(t)
	for _, c := range []struct {
		name, hex, out string
		code           int
	}{
		{"fork.mmb", forkMMB, "P0 P1 C0 C1 C2 P2 P3 P4 A\nC3 C4 C\n", 2},
		{"many.mmb", manyMMB, "pid -\npid 1\npid 2\npid 3\n", 6},
	} {
		p := writeHex(t, c.name, c.hex)
		for _, cfg := range []string{"plain", "deluxe"} {
			out, e, code := simulate(t, "", "-s", "-k"+k, "../examples/"+cfg+".mmconfig", p)
			if c.name == "many.mmb" {
				lines := strings.SplitAfter(out, "\n")
				sort.Strings(lines[1:])
				out = strings.Join(lines, "")
			}
			if out != c.out || code != c.code || e != "" {
				t.Errorf("%s %s: %q %d %q", c.name, cfg, out, code, e)
			}
		}
	}
}

//line mmmix.w:1435
const cowMMB = "000000000000010000000b0042ff000500000d0023fffe00000007010000000023fffe10" +
	"000004002300fe00e3010043a101000023fffe0000000701000000000000000000000000" +
	"2000000000000000706172656e740a000000000000000000200000000000001020000000" +
	"000000000000000000000010000000000000000040000000000000004000000000000020" +
	"400000000000001800000000000000004000000000000018636f77000000000000000000" +
	"000000006000000000000000000000000000000140000000000000080000000000000002" +
	"2000000000000000000000000000010000000000000000006000000000000088fe000000" +
	"000000000000000000000000"

func TestKernelCow(t *testing.T) {
	k := assembleKernel(t)
	p := writeHex(t, "cow.mmb", cowMMB)
	for _, cfg := range []string{"plain", "deluxe"} {
		out, e, code := simulate(t, "child\n", "-s", "-k"+k, "../examples/"+cfg+".mmconfig", p)
		if out != "StdIn> Child\nparent\n" || e != "" || code != 7 {
			t.Errorf("%s: %q %q %d", cfg, out, e, code)
		}
	}
}

//line mmmix.w:1464
const (
	copyMMB = "000000000000020031ff000252ff000ef4ff0008000007028fff010000000702f4ff00060000" +
		"070235ff00010000000055736167653a20002066696c656e616d650a00008f020108af02fe03" +
		"23fffe030000010358ff000df4ff000600000702c1ff020000000702f4ff0007f1ffffee4361" +
		"6e2774206f70656e2066696c652000000000210a000023fffe130000030340ff000d23fffe13" +
		"0000060159fffffbf4ff0002f1ffffe054726f75626c652077726974696e67205374644f7574" +
		"210a00000000e7ff000540ff0006adfffe1b23fffe130000060141fffff200000000f4ff0002" +
		"f1ffffd054726f75626c652072656164696e67210a0000000000000000000000000000002000" +
		"0000000000182000000000000000000000000000000500000000000000004000000000000000" +
		"4000000000000040400000000000002040000000000000300000000000000000400000000000" +
		"0020636f70792e6d6d6f0000000000000000400000000000003068656c6c6f2e6d6d73000000" +
		"0000000000000000000000006000000000000000000000000000000240000000000000080000" +
		"0000000000022000000000000005000000000000020000000000000000006000000000000088" +
		"fe000000000000000000000000000000"

//line mmmix.w:1478
)

//line mmmix.w:1483
const (
	iotest2MMB = "00000000000001000000020323fffe580000010323fffe000000080300000a03e3ff03e80000" +
		"090300000a03e3ff00010000090300000a0323fffe680000040323fffe780000040323fffe88" +
		"0000050323fffe980000040323fffea80000040323fffeb80000040323fffec80000040323ff" +
		"fed80000040323fffee80000050323fffef80000050323fffd080000050323fffd1800000503" +
		"23fffd280000050335ff00030000090300000a0323fffd3800000403e3ff00000000090323ff" +
		"fd48000006030000000000000000000000002000000000000000111111111111111122222222" +
		"2222222233333333333333334444444444444444555555555555555566666666666666667777" +
		"7777777777778888888888888888999999999999999911111111111111112222222222222222" +
		"3333333333333333444444444444444455555555555555556666666666666666777777777777" +
		"77778888888888888888999999999999999978610a62630a6465660a31323334353637383941" +
		"0a3132333435363738394142000a0a0a000a78787979000a31313232333334343535000a3131" +
		"3232333334343535363670710000696f7363722e746d700000000000000020000000000000d8" +
		"0000000000000004200000000000000000000000000000002000000000000108200000000000" +
		"0000000000000000000120000000000000030000000000000001200000000000000500000000" +
		"0000000c200000000000000d000000000000000c2000000000000015000000000000000c2000" +
		"00000000001d000000000000000c200000000000002d000000000000000c200000000000003d" +
		"000000000000000720000000000000450000000000000007200000000000004d000000000000" +
		"0007200000000000005500000000000000072000000000000065000000000000000720000000" +
		"0000007500000000000000072000000000000000000000000000009000000000000000004000" +
		"0000000000004000000000000028400000000000001800000000000000004000000000000018" +
		"696f74657374322e6d6d6f000000000000000000000000006000000000000000000000000000" +
		"0001400000000000000800000000000000022000000000000190200000000000009000000000" +
		"0000010000000000000000006000000000000090fd000000000000000000000000000000"
	iotest2Final = "0011000011610a00222222222262630a00333333336465660a0044444431323334353637" +
		"3839410a0066666666313233343536373839414200888888000a0000999999990a0a000a" +
		"0000111178787979000a000031313232333334343535000a000044443131323233333434" +
		"353536360000666666707100777777777777777788888888888888889999999999999999"

//line mmmix.w:1511
)

//line mmmix.w:1519
const bigMMB = "00000000000001002300fd00e3010000c90201ffa002000121010101e303138830030103" +
	"5103fffb23fffe080000010323fffe1800000603e3ff00000000090323fffe2800000303" +
	"c104ff0023fffe3800000303c105ff0035ff00010000090300000a03c106ff0000000203" +
	"23fffe480000060120ff040520ffff060000000000000000000000002000000000002af8" +
	"6269672e646174002000000000002af80000000000000004200000000000000000000000" +
	"0000138820000000000013880000000000000bb82000000000001f4000000000000009c4" +
	"200000000000138800000000000013880000000000000000400000000000000040000000" +
	"000000204000000000000018000000000000000040000000000000186269672e6d6d6f00" +
	"000000000000000060000000000000000000000000000001400000000000000800000000" +
	"0000000220000000000000002000000000002af800000000000001000000000000000000" +
	"6000000000000090fd000000000000000000000000000000"

//line mmmix.w:1535
func nnixfsTool(t *testing.T, args ...string) {
	t.Helper()
	cmd := exec.Command("go", append([]string{"run", "../nnixfs"}, args...)...)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("nnixfs %v: %v\n%s", args, err, out)
	}
}

//line mmmix.w:1546
func TestKernelFS(t *testing.T) {
	k := assembleKernel(t)
	dir := t.TempDir()
	img := filepath.Join(dir, "disk.img")
	src := filepath.Join(dir, "hello.mms")
	text := "a file on the NNIX disk\nand its second line\n"
	os.WriteFile(src, []byte(text), 0o644)
	nnixfsTool(t, "mkfs", img)
	nnixfsTool(t, "put", img, src)
	c := "../examples/plain.mmconfig"

//line mmmix.w:1562
	p := writeHex(t, "copy.mmb", copyMMB)
	out, e, code := simulate(t, "", "-s", "-k"+k, "-d"+img, c, p)
	if out != text || code != 0 || e != "" {
		t.Errorf("copy: %q %d %q", out, code, e)
	}

//line mmmix.w:1557

//line mmmix.w:1569
	p = writeHex(t, "iotest2.mmb", iotest2MMB)
	out, e, code = simulate(t, "", "-s", "-k"+k, "-d"+img, c, p)
	if out != "" || code != 0 || e != "" {
		t.Errorf("iotest2: %q %d %q", out, code, e)
	}
	got := filepath.Join(dir, "ioscr.tmp")
	nnixfsTool(t, "get", img, "ioscr.tmp", got)
	if b, _ := os.ReadFile(got); hexenc.EncodeToString(b) != iotest2Final {
		t.Errorf("ioscr.tmp: %x", b)
	}

//line mmmix.w:1558

//line mmmix.w:1581
	p = writeHex(t, "big.mmb", bigMMB)
	out, e, code = simulate(t, "", "-s", "-k"+k, "-d"+img, c, p)
	pattern := make([]byte, 5000)
	for i := range pattern {
		pattern[i] = byte(i)
	}
	nnixfsTool(t, "get", img, "big.dat", got)
	if b, _ := os.ReadFile(got); out != string(pattern) || code != 4500 || e != "" ||
		!bytes.Equal(b, pattern) {
		t.Errorf("big: %d bytes out, code %d, %q, %d bytes on disk", len(out), code, e, len(b))
	}

//line mmmix.w:1559
}

//line mmmix.w:1604
func goRun(t *testing.T, tool string, args ...string) {
	t.Helper()
	cmd := exec.Command("go", append([]string{"run", "../" + tool}, args...)...)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%s %v: %v\n%s", tool, args, err, out)
	}
}

//line mmmix.w:1613
func TestKernelShell(t *testing.T) {
	k := assembleKernel(t)
	dir := t.TempDir()
	in := func(name string) string { return filepath.Join(dir, name) }
	goRun(t, "mmixal", "-b", "250", "-o", in("sh.mmo"), "../nnix/sh.mms")
	goRun(t, "mmixsim", "-D"+in("sh.mmb"), in("sh.mmo"))
	goRun(t, "nnixfs", "mkfs", in("disk.img"))
	for _, prog := range []string{"hello", "echo", "primes"} {
		goRun(t, "mmixal", "-o", in(prog+".mmo"), "../examples/"+prog+".mms")
		goRun(t, "nnixfs", "put", in("disk.img"), in(prog+".mmo"))
	}

//line mmmix.w:1629
	out, e, code := simulate(t, "hello\necho one two three\nprimes\nnope\nexit\n", "-s", "-k"+k,
		"-d"+in("disk.img"), "../examples/plain.mmconfig", in("sh.mmb"))
	const prompt = "nnix$ StdIn> "
	head := prompt + "hello, world\n" + prompt + "one two three\n" + prompt
	tail := prompt + prompt
	if !strings.HasPrefix(out, head) || !strings.HasSuffix(out, tail) || len(out) < len(head)+len(tail) ||
		digest(out[len(head):len(out)-len(tail)]) != "bd64b4848d0e1d0d" ||
		e != "sh: cannot execute nope\n" || code != 0 {
		t.Errorf("shell: %q, %q, code %d", out, e, code)
	}

//line mmmix.w:1625

//line mmmix.w:1646
	frames := func(n int) string {
		input := "100000000\n" + strings.Repeat("hello\n", n) + "exit\nm600018000\nq\n"
		out, _, _ := simulate(t, input, "-k"+k, "-d"+in("disk.img"), "../examples/plain.mmconfig",
			in("sh.mmb"))
		i := strings.Index(out, "m[600018000]=")
		if i < 0 {
			t.Fatalf("no frame top in %q", out)
		}
		return out[i : i+29]
	}
	if a, b := frames(2), frames(6); a != b || a == "m[600018000]=0000000000000000" {
		t.Errorf("frames leak: %s, then %s", a, b)
	}

//line mmmix.w:1626
}

//line mmmix.w:1663
func TestKernelErrors(t *testing.T) {
	dir := t.TempDir()
	bad := filepath.Join(dir, "bad.mmo")
	if err := os.WriteFile(bad, []byte("not an object file"), 0o644); err != nil {
		t.Fatal(err)
	}
	pos := filepath.Join(dir, "pos.mmo") // 위치가 양수인 테트라 하나
	if err := os.WriteFile(pos, []byte{0x98, 9, 1, 0, 0x98, 1, 0, 1, 0, 0, 1, 0,
		0xe3, 0, 0, 1}, 0o644); err != nil {
		t.Fatal(err)
	}
	p := writeHex(t, "hello.mmb", helloMMB)
	for _, c := range []struct {
		kernel, err string
		code        int
	}{
		{filepath.Join(dir, "nope.mmo"),
			"Panic: Can't open kernel object file " + filepath.Join(dir, "nope.mmo") + "!\n", -3},
		{bad, "Panic: Bad kernel object file " + bad + "!\n", -4},
		{pos, "Panic: Kernel location 0000000000000100 isn't in negative memory!\n", -5},
	} {
		_, e, code := simulate(t, "", "-s", "-k"+c.kernel, "../examples/plain.mmconfig", p)
		if e != c.err || code != c.code {
			t.Errorf("%s: %q %d", c.kernel, e, code)
		}
	}
	nodisk := filepath.Join(dir, "nodisk.img")
	_, e, code := simulate(t, "", "-s", "-d"+nodisk, "../examples/plain.mmconfig", p)
	if e != "Panic: Can't open disk image "+nodisk+"!\n" || code != -3 {
		t.Errorf("disk: %q %d", e, code)
	}
}
