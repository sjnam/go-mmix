//line mmmix.w:1084
package main

import (
	"bytes"
	"crypto/sha256"
	hexenc "encoding/hex"
	"os"
	"os/exec"
	"path/filepath"
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

//line mmmix.w:1114
const (
	script1 = "@8000000000010000\nv1ff\n2000\np\ns\nq\n"
	script2 = "@8000000000010000\n100000\ns\nD*\nS*\ng255\nm10000\nq\n"

//line mmmix.w:1117
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

//line mmmix.w:1145
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

//line mmmix.w:1157
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

//line mmmix.w:1187
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

//line mmmix.w:1212
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

//line mmmix.w:1257
func assembleKernel(t *testing.T) string {
	t.Helper()
	mmo := filepath.Join(t.TempDir(), "nnix.mmo")
	cmd := exec.Command("go", "run", "../mmixal", "-b", "250", "-o", mmo, "../nnix/nnix.mms")
	if out, err := cmd.CombinedOutput(); err != nil || len(out) != 0 {
		t.Fatalf("mmixal: %v\n%s", err, out)
	}
	return mmo
}

//line mmmix.w:1271
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

//line mmmix.w:1295
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

//line mmmix.w:1319
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

//line mmmix.w:1333
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

//line mmmix.w:1355
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
}
