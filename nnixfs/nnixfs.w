% NNIX의 파일 시스템 NNIXFS의 디스크 이미지를 다루는 호스트 도구.
% 크누스의 MMIXware를 옮긴 것이 아니라 옮긴이가 새로 쓴 프로그램이다.

@s io.Writer int
@s testing.T int
@s bytes.Buffer int

\input kotexgweb
\def\title{NNIXFS}
\def\MMIX{\.{MMIX}}
\def\NNIX{\hbox{\mc NNIX}}
\def\Hex#1{\hbox{$^{\scriptscriptstyle\#}$\tt#1}}
\def\botofcontents{\vskip 0pt plus 1filll
    \ninepoint\baselineskip12pt
    \noindent 이 프로그램은 크누스의 {\tt MMIX}ware를 옮긴 것이 아니라, 옮긴이가
    \NNIX\ 커널을 위해 새로 쓴 것이다. {\tt MMIX}ware 꾸러미의 일부가 아니다.}

@* 들어가며. 크누스는 \MMIX의 운영체제를 \NNIX라고 부르고는 만들지 않았다. 나는 2026년
10월에 메타 시뮬레이터 \.{mmmix} 위에서 그것을 조금씩 만들어 보기 시작했다. 4단계에서
커널이 진짜 파일 시스템을 갖게 되었는데, 그 디스크는 호스트의 파일 하나다. \.{mmmix}는
\.{-d<image>}로 그 파일을 블록 장치로 붙인다. 이 프로그램 \.{nnixfs}는 호스트에서 그 디스크
이미지를 만들고, 거기에 파일을 넣고 꺼낸다. 그러니 커널과 이 도구는 같은 형식을 양쪽에서
구현한 셈이다. 커널 쪽은 \.{nnix/nnix.mms}에 있다.

쓰는 법은 다음과 같다.
$$\vbox{\halign{\tt#\hfil\quad&#\hfil\cr
nnixfs mkfs image [nblocks]&블록 \.{nblocks}개(기본은 1024)짜리 빈 디스크를 만든다\cr
nnixfs put image file [name]&호스트 파일을 \.{name}(기본은 파일의 이름)으로 넣는다\cr
nnixfs get image name [file]&파일을 꺼내 \.{file}(기본은 \.{name})에 쓴다\cr
nnixfs ls image&파일의 크기와 이름을 찍는다\cr
nnixfs rm image name&파일을 지운다\cr}}$$

일은 함수 |nnixfs|가 한다. 명령줄 인자와 표준 출력, 표준 오류를 받고 종료 코드를 돌려주므로
시험에서도 그대로 부를 수 있다. 이미지는 통째로 메모리에 읽어 고친 뒤 다시 쓴다.

@c
package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
)

@<상수@>
@<타입 정의@>
@<함수들@>

func main() {
	os.Exit(nnixfs(os.Args, os.Stdout, os.Stderr))
}

func nnixfs(args []string, stdout, stderr io.Writer) int {
	if len(args) < 3 {
		@<사용법을 알리고 |return 2|@>
	}
	img := args[2]
	var err error
	switch args[1] {
	case "mkfs":
		@<빈 디스크 이미지 |img|를 만든다@>
	case "put":
		@<호스트 파일을 |img|에 넣는다@>
	case "get":
		@<|img|에서 파일을 꺼낸다@>
	case "ls":
		@<|img|의 파일 목록을 찍는다@>
	case "rm":
		@<|img|에서 파일을 지운다@>
	default:
		@<사용법을 알리고 |return 2|@>
	}
	if err != nil {
		fmt.Fprintf(stderr, "nnixfs: %v\n", err)
		return 1
	}
	return 0
}

@ @<사용법을...@>=
fmt.Fprintf(stderr, "Usage: nnixfs mkfs|put|get|ls|rm image ...\n")
return 2

@* 디스크의 모양. 블록은 1024바이트다. 수는 모두 \MMIX처럼 큰 쪽 먼저로 적는다.

\smallskip
\item{$\bullet$} 블록~0은 슈퍼블록이다. 옥타바이트 일곱 개가 차례로 이름표 \.{"NNIXFS01"},
블록의 수, FAT가 시작하는 블록, FAT의 블록 수, 디렉터리가 시작하는 블록, 디렉터리의 블록 수,
데이터가 시작하는 블록을 적는다.
\item{$\bullet$} 블록~1부터는 FAT(파일 할당 표)다. 블록마다 테트라바이트 하나가 있어서, 0이면
빈 블록이고, \Hex{ffffffff}이면 파일의 마지막 블록이고, \Hex{fffffffe}이면 슈퍼블록과 FAT와
디렉터리가 차지한 블록이다. 그 밖의 값은 파일의 다음 블록의 번호다.
\item{$\bullet$} 그다음 네 블록이 디렉터리다. 항목은 64바이트이므로 파일은 64개까지다. 항목의
처음 48바이트는 널 문자로 끝나는 이름이고(그래서 이름은 47자까지다. 첫 바이트가 0이면 빈
항목이다), 바이트 48--51은 첫 블록의 번호(빈 파일이면 0), 바이트 56--63은 파일의 크기다.
\item{$\bullet$} 나머지가 데이터 블록이다.
\smallskip

\noindent 나는 FAT를 골랐다. 커널을 어셈블리 언어로 쓰니 아이노드와 간접 블록보다 사슬 하나를
따라가는 편이 훨씬 짧기 때문이다. 커널은 FAT를 16KB까지만 메모리에 두므로 블록은 4096개(4MB)까지다.

@<상수@>=
const (
	bsize     = 1024       // bytes per block
	magic     = "NNIXFS01" // the superblock's label
	fatFree   = 0          // a free block
	fatEnd    = 0xffffffff // the last block of a file
	fatMeta   = 0xfffffffe // superblock, FAT, directory
	dirBlocks = 4          // number of directory blocks
	entSize   = 64         // bytes per directory entry
	nameMax   = 47         // maximum length of a name
	maxBlocks = 4096       // number of blocks the kernel can handle
)

@ 이미지를 메모리에 올린 것이 |fsys|다. 슈퍼블록의 값들을 풀어 둔다.

@<타입 정의@>=
type fsys struct {
	b         []byte // the whole image
	nblocks   int    // number of blocks
	fatStart  int    // block where the FAT begins
	fatBlocks int    // number of FAT blocks
	dirStart  int    // block where the directory begins
	dataStart int    // block where the data begins
}

@ 빈 디스크를 만들 때는 FAT의 크기부터 정한다. 블록마다 4바이트이므로 FAT는
$\lceil 4n/1024\rceil$블록이다. 메타데이터가 차지한 블록은 FAT에 \Hex{fffffffe}로 적어서
할당하는 쪽이 건드리지 않게 한다.

@<빈 디스크 이미지...@>=
n := 1024
if len(args) > 3 {
	if n, err = strconv.Atoi(args[3]); err != nil {
		break
	}
}
fatBlocks := (4*n + bsize - 1) / bsize
f := &fsys{b: make([]byte, n*bsize), nblocks: n, fatStart: 1, fatBlocks: fatBlocks,
	dirStart: 1 + fatBlocks, dataStart: 1 + fatBlocks + dirBlocks}
if n <= f.dataStart || n > maxBlocks {
	err = fmt.Errorf("the number of blocks must be between %d and %d", f.dataStart+1, maxBlocks)
	break
}
copy(f.b, magic)
for i, v := range []int{n, f.fatStart, fatBlocks, f.dirStart, dirBlocks, f.dataStart} {
	binary.BigEndian.PutUint64(f.b[8+8*i:], uint64(v))
}
for i := 0; i < f.dataStart; i++ {
	f.setFat(i, fatMeta)
}
err = os.WriteFile(img, f.b, 0o644)

@ 함수 |load|는 이미지를 읽고 슈퍼블록을 검사한다. 메서드 |fat|와 |setFat|는 FAT의 항목을,
|entry|는 디렉터리의 항목~|i|를, |block|은 블록~|i|를 바이트 조각으로 준다.

@<함수들@>=
func load(name string) (*fsys, error) {
	b, err := os.ReadFile(name)
	if err != nil {
		return nil, err
	}
	if len(b) < bsize || string(b[:8]) != magic {
		return nil, errors.New(name + " is not an NNIXFS image")
	}
	u := func(i int) int { return int(binary.BigEndian.Uint64(b[8+8*i:])) }
	f := &fsys{b: b, nblocks: u(0), fatStart: u(1), fatBlocks: u(2), dirStart: u(3),
		dataStart: u(5)}
	if f.nblocks*bsize != len(b) || f.nblocks > maxBlocks {
		return nil, errors.New(name + " has a bad superblock")
	}
	return f, nil
}
@#
func (f *fsys) fat(i int) uint32 {
	return binary.BigEndian.Uint32(f.b[f.fatStart*bsize+4*i:])
}
@#
func (f *fsys) setFat(i int, v uint32) {
	binary.BigEndian.PutUint32(f.b[f.fatStart*bsize+4*i:], v)
}
@#
func (f *fsys) entry(i int) []byte {
	return f.b[f.dirStart*bsize+entSize*i:][:entSize]
}
@#
func (f *fsys) block(i int) []byte {
	return f.b[i*bsize:][:bsize]
}

@ 함수 |lookup|은 이름이 |name|인 항목의 번호를 돌려준다. 없으면 $-1$이다. 함수 |entName|은 항목의
이름을 꺼낸다.

@<함수들@>=
func (f *fsys) lookup(name string) int {
	for i := 0; i < dirBlocks*bsize/entSize; i++ {
		if e := f.entry(i); e[0] != 0 && entName(e) == name {
			return i
		}
	}
	return -1
}
@#
func entName(e []byte) string {
	n := 0
	for n < nameMax && e[n] != 0 {
		n++
	}
	return string(e[:n])
}

@ 파일을 덮어쓰거나 지울 때는 그 사슬의 블록들을 FAT에서 풀어 준다.

@<함수들@>=
func (f *fsys) free(b uint32) {
	for b != fatEnd && b != fatFree {
		next := f.fat(int(b))
		f.setFat(int(b), fatFree)
		b = next
	}
}

@* 명령들. 파일을 넣을 때 이름이 이미 있으면 그 파일을 덮어쓴다. 블록은 데이터 영역의 앞에서부터
빈 것을 골라 사슬로 잇는다. 빈 파일은 블록을 갖지 않는다.

@<호스트 파일을 |img|에...@>=
if len(args) < 4 {
	@<사용법을...@>
}
name := filepath.Base(args[3])
if len(args) > 4 {
	name = args[4]
}
var f *fsys
var data []byte
if f, err = load(img); err != nil {
	break
}
if data, err = os.ReadFile(args[3]); err != nil {
	break
}
if len(name) == 0 || len(name) > nameMax {
	err = fmt.Errorf("the name must have 1 to %d characters", nameMax)
	break
}
i := f.lookup(name)
if i >= 0 {
	f.free(binary.BigEndian.Uint32(f.entry(i)[48:]))
} else {
	@<빈 항목을 찾아 |i|에 넣는다@>
}
e := f.entry(i)
clear(e)
copy(e, name)
@<|data|를 블록 사슬에 쓰고, 첫 블록을 |e|에 적는다@>
binary.BigEndian.PutUint64(e[56:], uint64(len(data)))
err = os.WriteFile(img, f.b, 0o644)

@ @<빈 항목을 찾아...@>=
for i = 0; i < dirBlocks*bsize/entSize && f.entry(i)[0] != 0; i++ {
}
if i == dirBlocks*bsize/entSize {
	err = errors.New("the directory is full")
	break
}

@ 블록을 하나 쓸 때마다 FAT를 앞에서부터 훑는다. 디스크가 작으니 이것으로 넉넉하다. 자리가 모자라면
이미 잡은 블록을 풀어 준다.

@<|data|를 블록 사슬에...@>=
var first, prev uint32
for off := 0; off < len(data); off += bsize {
	b := f.dataStart
	for b < f.nblocks && f.fat(b) != fatFree {
		b++
	}
	if b == f.nblocks {
		f.free(first)
		clear(e)
		err = errors.New("the disk is full")
		break
	}
	f.setFat(b, fatEnd)
	if prev == 0 {
		first = uint32(b)
	} else {
		f.setFat(int(prev), uint32(b))
	}
	prev = uint32(b)
	copy(f.block(b), data[off:])
}
if err != nil {
	break
}
binary.BigEndian.PutUint32(e[48:], first)

@ 파일을 꺼낼 때는 사슬을 따라가며 크기만큼 모은다.

@<|img|에서 파일을 꺼낸다@>=
if len(args) < 4 {
	@<사용법을...@>
}
var f *fsys
if f, err = load(img); err != nil {
	break
}
i := f.lookup(args[3])
if i < 0 {
	err = errors.New("no file named " + args[3])
	break
}
e := f.entry(i)
size := int(binary.BigEndian.Uint64(e[56:]))
data := make([]byte, 0, size)
for b := binary.BigEndian.Uint32(e[48:]); len(data) < size; b = f.fat(int(b)) {
	if b == fatFree || b >= uint32(f.nblocks) {
		err = errors.New("the chain of " + args[3] + " is broken")
		break
	}
	data = append(data, f.block(int(b))[:min(bsize, size-len(data))]...)
}
if err != nil {
	break
}
out := args[3]
if len(args) > 4 {
	out = args[4]
}
err = os.WriteFile(out, data, 0o644)

@ @<|img|의 파일 목록을...@>=
var f *fsys
if f, err = load(img); err != nil {
	break
}
for i := 0; i < dirBlocks*bsize/entSize; i++ {
	if e := f.entry(i); e[0] != 0 {
		fmt.Fprintf(stdout, "%8d %s\n", binary.BigEndian.Uint64(e[56:]), entName(e))
	}
}

@ @<|img|에서 파일을 지운다@>=
if len(args) < 4 {
	@<사용법을...@>
}
var f *fsys
if f, err = load(img); err != nil {
	break
}
i := f.lookup(args[3])
if i < 0 {
	err = errors.New("no file named " + args[3])
	break
}
f.free(binary.BigEndian.Uint32(f.entry(i)[48:]))
clear(f.entry(i))
err = os.WriteFile(img, f.b, 0o644)

@* 시험. 빈 디스크를 만들고, 블록 셋에 걸치는 파일과 빈 파일을 넣고, 목록을 보고, 꺼내서 견주고,
덮어쓰고, 지운다. 지운 뒤에는 FAT의 데이터 영역이 다시 모두 비어 있어야 한다.

@(nnixfs_test.go@>=
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
	data := []byte(strings.Repeat("0123456789abcdef", 160)) // 2560 bytes, three blocks
	@<빈 디스크에 |big|과 빈 파일을 넣고 목록을 본다@>
	@<꺼내서 견주고, 덮어쓰고, 지운다@>
}

@ @<빈 디스크에...@>=
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

@ @<꺼내서 견주고...@>=
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

@ 잘못된 쓰임은 종료 코드와 알림으로 드러나야 한다.

@(nnixfs_test.go@>=
func TestErrors(t *testing.T) {
	dir := t.TempDir()
	img := filepath.Join(dir, "disk.img")
	run(t, "mkfs", img, "16")
	notfs := filepath.Join(dir, "notfs")
	os.WriteFile(notfs, make([]byte, 20*1024), 0o644) // larger than the data area (10KB)
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

@* 찾아보기.
