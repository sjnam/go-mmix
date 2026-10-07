//line nnixfs.w:37
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

//line nnixfs.w:107
const (
	bsize     = 1024       // 블록의 바이트 수
	magic     = "NNIXFS01" // 슈퍼블록의 이름표
	fatFree   = 0          // 빈 블록
	fatEnd    = 0xffffffff // 파일의 마지막 블록
	fatMeta   = 0xfffffffe // 슈퍼블록, FAT, 디렉터리
	dirBlocks = 4          // 디렉터리의 블록 수
	entSize   = 64         // 디렉터리 항목의 바이트 수
	nameMax   = 47         // 이름의 최대 길이
	maxBlocks = 4096       // 커널이 다룰 수 있는 블록 수
)

//line nnixfs.w:122
type fsys struct {
	b         []byte // 이미지 전체
	nblocks   int    // 블록의 수
	fatStart  int    // FAT가 시작하는 블록
	fatBlocks int    // FAT의 블록 수
	dirStart  int    // 디렉터리가 시작하는 블록
	dataStart int    // 데이터가 시작하는 블록
}

//line nnixfs.w:162
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

func (f *fsys) fat(i int) uint32 {
	return binary.BigEndian.Uint32(f.b[f.fatStart*bsize+4*i:])
}

func (f *fsys) setFat(i int, v uint32) {
	binary.BigEndian.PutUint32(f.b[f.fatStart*bsize+4*i:], v)
}

func (f *fsys) entry(i int) []byte {
	return f.b[f.dirStart*bsize+entSize*i:][:entSize]
}

func (f *fsys) block(i int) []byte {
	return f.b[i*bsize:][:bsize]
}

//line nnixfs.w:199
func (f *fsys) lookup(name string) int {
	for i := 0; i < dirBlocks*bsize/entSize; i++ {
		if e := f.entry(i); e[0] != 0 && entName(e) == name {
			return i
		}
	}
	return -1
}

func entName(e []byte) string {
	n := 0
	for n < nameMax && e[n] != 0 {
		n++
	}
	return string(e[:n])
}

//line nnixfs.w:219
func (f *fsys) free(b uint32) {
	for b != fatEnd && b != fatFree {
		next := f.fat(int(b))
		f.setFat(int(b), fatFree)
		b = next
	}
}

//line nnixfs.w:53
func main() {
	os.Exit(nnixfs(os.Args, os.Stdout, os.Stderr))
}

func nnixfs(args []string, stdout, stderr io.Writer) int {
	if len(args) < 3 {

//line nnixfs.w:85
		fmt.Fprintf(stderr, "Usage: nnixfs mkfs|put|get|ls|rm image ...\n")
		return 2

//line nnixfs.w:60
	}
	img := args[2]
	var err error
	switch args[1] {
	case "mkfs":

//line nnixfs.w:136
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

//line nnixfs.w:66
	case "put":

//line nnixfs.w:231
		if len(args) < 4 {

//line nnixfs.w:85
			fmt.Fprintf(stderr, "Usage: nnixfs mkfs|put|get|ls|rm image ...\n")
			return 2

//line nnixfs.w:233
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

//line nnixfs.w:264
			for i = 0; i < dirBlocks*bsize/entSize && f.entry(i)[0] != 0; i++ {
			}
			if i == dirBlocks*bsize/entSize {
				err = errors.New("the directory is full")
				break
			}

//line nnixfs.w:255
		}
		e := f.entry(i)
		clear(e)
		copy(e, name)

//line nnixfs.w:275
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

//line nnixfs.w:260
		binary.BigEndian.PutUint64(e[56:], uint64(len(data)))
		err = os.WriteFile(img, f.b, 0o644)

//line nnixfs.w:68
	case "get":

//line nnixfs.w:304
		if len(args) < 4 {

//line nnixfs.w:85
			fmt.Fprintf(stderr, "Usage: nnixfs mkfs|put|get|ls|rm image ...\n")
			return 2

//line nnixfs.w:306
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

//line nnixfs.w:70
	case "ls":

//line nnixfs.w:336
		var f *fsys
		if f, err = load(img); err != nil {
			break
		}
		for i := 0; i < dirBlocks*bsize/entSize; i++ {
			if e := f.entry(i); e[0] != 0 {
				fmt.Fprintf(stdout, "%8d %s\n", binary.BigEndian.Uint64(e[56:]), entName(e))
			}
		}

//line nnixfs.w:72
	case "rm":

//line nnixfs.w:347
		if len(args) < 4 {

//line nnixfs.w:85
			fmt.Fprintf(stderr, "Usage: nnixfs mkfs|put|get|ls|rm image ...\n")
			return 2

//line nnixfs.w:349
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

//line nnixfs.w:74
	default:

//line nnixfs.w:85
		fmt.Fprintf(stderr, "Usage: nnixfs mkfs|put|get|ls|rm image ...\n")
		return 2

//line nnixfs.w:76
	}
	if err != nil {
		fmt.Fprintf(stderr, "nnixfs: %v\n", err)
		return 1
	}
	return 0
}
