//line mmixio.w:807
package mmixio

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

type fakeSim struct {
	mem   map[Octa]byte
	stdin []byte
}

func (f *fakeSim) StdinChr() byte {
	c := f.stdin[0]
	f.stdin = f.stdin[1:]
	return c
}

//line mmixio.w:828
func (f *fakeSim) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	for m := 0; m < size; m++ {
		a := addr + Octa(m)
		buf[m] = f.mem[a]
		if buf[m] == 0 && stop == 0 {
			return m
		}
		if buf[m] == 0 && stop > 0 && a&1 != 0 && buf[m-1] == 0 {
			return m - 1
		}
	}
	return size
}

func (f *fakeSim) MMPutChars(buf []byte, size int, addr Octa) {
	for m := 0; m < size; m++ {
		f.mem[addr+Octa(m)] = buf[m]
	}
}

//line mmixio.w:851
func setup(t *testing.T) (*IO, *fakeSim, *bytes.Buffer, *bytes.Buffer, string) {
	t.Helper()
	f := &fakeSim{mem: map[Octa]byte{}}
	name := filepath.Join(t.TempDir(), "file")
	f.MMPutChars(append([]byte(name), 0), len(name)+1, 0x100)
	var out, errs bytes.Buffer
	return New(f, &out, &errs), f, &out, &errs, name
}

func (f *fakeSim) str(addr Octa, n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = f.mem[addr+Octa(i)]
	}
	return string(b)
}

//line mmixio.w:873
func TestReadWrite(t *testing.T) {
	x, f, _, _, _ := setup(t)
	f.MMPutChars([]byte("Hello\nworld\n"), 12, 0x200)
	check := func(what string, got, want Octa) {
		t.Helper()
		if got != want {
			t.Errorf("%s = %#x, 원함 %#x", what, got, want)
		}
	}
	check("Fopen", x.Fopen(3, 0x100, 4), 0)
	check("Fwrite", x.Fwrite(3, 0x200, 12), 0)
	check("Ftell", x.Ftell(3), 12)
	check("Fseek", x.Fseek(3, 0), 0)
	check("Fgets", x.Fgets(3, 0x300, 100), 6)
	if s := f.str(0x300, 7); s != "Hello\n\x00" {
		t.Errorf("첫 줄 %q", s)
	}
	check("Fgets", x.Fgets(3, 0x300, 100), 6)
	check("Fgets", x.Fgets(3, 0x300, 100), NegOne)
	check("Fseek", x.Fseek(3, NegOne-1), 0)          // $-2$: 마지막 바이트 앞
	check("Fread", x.Fread(3, 0x400, 20), NegOne-18) // $1-20=-19$
	check("Fclose", x.Fclose(3), 0)
	check("Fclose", x.Fclose(3), NegOne)
}

//line mmixio.w:902
func TestModes(t *testing.T) {
	x, _, _, _, _ := setup(t)
	if x.Fopen(4, 0x100, 1) != 0 {
		t.Fatal("Fopen 실패")
	}
	for _, c := range []struct {
		what      string
		got, want Octa
	}{
		{"Fseek", x.Fseek(4, 0), NegOne},
		{"Ftell", x.Ftell(4), NegOne},
		{"Fread", x.Fread(4, 0x200, 5), NegOne - 5},
		{"Fgets", x.Fgets(4, 0x200, 5), NegOne},
		{"Fwrite(stdin)", x.Fwrite(0, 0x200, 5), NegOne - 4},
		{"Fopen", x.Fopen(4, 0x100, 5), NegOne},
		{"Fputs", x.Fputs(4, 0x100), NegOne},
	} {
		if c.got != c.want {
			t.Errorf("%s = %#x, 원함 %#x", c.what, c.got, c.want)
		}
	}
}

//line mmixio.w:926
const NegOne = ^Octa(0)

//line mmixio.w:932
func TestStdStreams(t *testing.T) {
	x, f, out, _, _ := setup(t)
	f.stdin = []byte("abc\ndef")
	if n := x.Fgets(0, 0x200, 100); n != 4 || f.str(0x200, 5) != "abc\n\x00" {
		t.Errorf("Fgets(StdIn) = %d, %q", n, f.str(0x200, 5))
	}
	f.MMPutChars([]byte("hi!\x00"), 4, 0x300)
	f.MMPutChars([]byte{0, 'W', 0, 'X', 0, 0}, 6, 0x400)
	if n := x.Fputs(1, 0x300); n != 3 {
		t.Errorf("Fputs = %d", n)
	}
	if n := x.Fputws(1, 0x400); n != 2 {
		t.Errorf("Fputws = %d", n)
	}
	if out.String() != "hi!\x00W\x00X" {
		t.Errorf("표준 출력 %q", out.String())
	}
}

//line mmixio.w:955
func TestTripWarning(t *testing.T) {
	x, _, _, errs, name := setup(t)
	x.PrintTripWarning(2, 0x100)
	if want := "Warning: integer overflow at location 0000000000000100\n"; errs.String() != want {
		t.Errorf("표준 오류 %q", errs.String())
	}
	x.Fopen(2, 0x100, 1)
	x.PrintTripWarning(8, 4)
	if b, _ := os.ReadFile(name); len(b) != 0 {
		t.Errorf("경고가 벌써 파일에 있다: %q", b)
	}
	x.FlushAll()
	if b, _ := os.ReadFile(name); string(b) != "Warning: floating point inexact at location 0000000000000004\n" {
		t.Errorf("파일 %q", b)
	}
}
