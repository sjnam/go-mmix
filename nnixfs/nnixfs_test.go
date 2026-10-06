//line nnixfs/nnixfs.w:367
package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func run(t *testing.T, args ...string) (string, string, int) {
	t.Helper()
	var o, e bytes.Buffer
	code := nnixfs(append([]string{"nnixfs"}, args...), &o, &e)
	return o.String(), e.String(), code
}

func TestRoundTrip(t *testing.T) {
	dir := t.TempDir()
	img := filepath.Join(dir, "disk.img")
	big := filepath.Join(dir, "big.txt")
	data := []byte(strings.Repeat("0123456789abcdef", 160)) // 2560바이트, 블록 셋

//line nnixfs/nnixfs.w:394
	os.WriteFile(big, data, 0o644)
	empty := filepath.Join(dir, "empty")
	os.WriteFile(empty, nil, 0o644)
	for _, a := range [][]string{
		{"mkfs", img, "64"}, {"put", img, big}, {"put", img, empty, "nothing"},
	} {
		if _, e, code := run(t, a...); code != 0 {
			t.Fatalf("%v: %s", a, e)
		}
	}
	if o, _, _ := run(t, "ls", img); o != "    2560 big.txt\n       0 nothing\n" {
		t.Errorf("ls: %q", o)
	}

//line nnixfs/nnixfs.w:390

//line nnixfs/nnixfs.w:409
	out := filepath.Join(dir, "out")
	run(t, "get", img, "big.txt", out)
	if got, _ := os.ReadFile(out); !bytes.Equal(got, data) {
		t.Errorf("get: %d bytes", len(got))
	}
	os.WriteFile(big, []byte("short\n"), 0o644)
	run(t, "put", img, big)
	run(t, "get", img, "big.txt", out)
	if got, _ := os.ReadFile(out); string(got) != "short\n" {
		t.Errorf("overwrite: %q", got)
	}
	run(t, "rm", img, "big.txt")
	run(t, "rm", img, "nothing")
	f, err := load(img)
	if err != nil {
		t.Fatal(err)
	}
	for b := f.dataStart; b < f.nblocks; b++ {
		if f.fat(b) != fatFree {
			t.Errorf("block %d is still in use", b)
		}
	}

//line nnixfs/nnixfs.w:391
}

//line nnixfs/nnixfs.w:435
func TestErrors(t *testing.T) {
	dir := t.TempDir()
	img := filepath.Join(dir, "disk.img")
	run(t, "mkfs", img, "16")
	notfs := filepath.Join(dir, "notfs")
	os.WriteFile(notfs, make([]byte, 20*1024), 0o644) // 데이터 영역(10KB)보다 크다
	for _, c := range []struct {
		args []string
		err  string
		code int
	}{
		{[]string{"ls"}, "Usage: nnixfs mkfs|put|get|ls|rm image ...\n", 2},
		{[]string{"mkfs", img, "5"}, "nnixfs: the number of blocks must be between 7 and 4096\n", 1},
		{[]string{"ls", notfs}, "nnixfs: " + notfs + " is not an NNIXFS image\n", 1},
		{[]string{"get", img, "nope"}, "nnixfs: no file named nope\n", 1},
		{[]string{"put", img, notfs, strings.Repeat("x", 48)},
			"nnixfs: the name must have 1 to 47 characters\n", 1},
		{[]string{"put", img, notfs}, "nnixfs: the disk is full\n", 1},
	} {
		if _, e, code := run(t, c.args...); e != c.err || code != c.code {
			t.Errorf("%v: %q %d", c.args, e, code)
		}
	}
	if o, _, _ := run(t, "ls", img); o != "" {
		t.Errorf("a failed put left %q", o)
	}
}
