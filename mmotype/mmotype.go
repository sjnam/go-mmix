//line mmotype.w:32
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"time"
)

//line mmotype.w:86
type typer struct {

//line mmotype.w:124
	listing bool           // 모든 것을 나열하는가?
	verbose bool           // 입력의 테트라들도 읽는 대로 보여 주는가?
	mmoFile *bufio.Reader  // 입력 파일
	out     *bufio.Writer  // 표준 출력
	stderr  io.Writer      // 표준 오류
	loc     *time.Location // 파일을 만든 시각을 찍을 시간대

//line mmotype.w:202
	count     int     // 지금까지 읽은 테트라바이트의 수
	byteCount int     // 다음에 읽을 바이트의 색인
	buf       [4]byte // 가장 최근에 읽은 바이트들
	yz        int     // 가장 낮은 두 바이트
	tet       Tetra   // |buf|의 바이트들을 큰 끝 방식으로 묶은 것

//line mmotype.w:292
	curLoc     Octa        // 현재 위치
	listedFile int         // 가장 최근에 나열한 파일 번호
	curFile    int         // 가장 최근에 고른 파일 번호
	curLine    int         // |curFile| 안의 현재 위치
	fileName   [256]string // 본 파일 이름들
	fileNamed  [256]bool   // 그 번호의 파일 이름을 보았는가?
	tmp        Octa        // 잠깐 관심 있는 옥타바이트

//line mmotype.w:682
	stabStart int    // 기호표가 시작한 곳
	symBuf    []byte // 현재 마디로 오는 가운데 가지들의 문자들

//line mmotype.w:88
}

type exitSignal int // 이 종료 코드로 프로그램을 끝내라는 신호

//line mmotype.w:160
type (
	Tetra = uint32 // 테트라바이트
	Octa  = uint64 // 옥타바이트
)

//line mmotype.w:135
const (
	mm       = 0x98 // \.{mmo} 형식의 탈출 코드
	lopQuote = 0x0  // 인용 lopcode
	lopLoc   = 0x1  // 위치 lopcode
	lopSkip  = 0x2  // 건너뛰기 lopcode
	lopFixo  = 0x3  // 옥타바이트 고치기 lopcode
	lopFixr  = 0x4  // 상대 주소 고치기 lopcode
	lopFixrx = 0x5  // 확장된 상대 주소 고치기 lopcode
	lopFile  = 0x6  // 파일 이름 lopcode
	lopLine  = 0x7  // 파일 위치 lopcode
	lopSpec  = 0x8  // 특수 고리 lopcode
	lopPre   = 0x9  // 서문 lopcode
	lopPost  = 0xa  // 후기 lopcode
	lopStab  = 0xb  // 기호표 lopcode
	lopEnd   = 0xc  // 모든 것을 끝내는 lopcode
)

//line mmotype.w:679
const symLengthMax = 1000

//line mmotype.w:175
func (t *typer) readTet() {
	if _, err := io.ReadFull(t.mmoFile, t.buf[:]); err != nil {
		fmt.Fprintf(t.stderr, "Unexpected end of file after %d tetras!\n", t.count)

		panic(exitSignal(-3))
	}
	t.yz = int(t.buf[2])<<8 + int(t.buf[3])
	t.tet = Tetra(t.buf[0])<<24 + Tetra(t.buf[1])<<16 + Tetra(t.yz)
	if t.verbose {
		fmt.Fprintf(t.out, "  %08x\n", t.tet)
	}
	t.count++
}

//line mmotype.w:192
func (t *typer) readByte() byte {
	if t.byteCount == 0 {
		t.readTet()
	}
	b := t.buf[t.byteCount]
	t.byteCount = (t.byteCount + 1) & 3
	return b
}

//line mmotype.w:247
func (t *typer) err(m string) {
	fmt.Fprintf(t.stderr, "Error in tetra %d: %s!\n", t.count, m)

}

//line mmotype.w:309
func (t *typer) y() int { return int(t.buf[2]) } // 둘째로 낮은 바이트
func (t *typer) z() int { return int(t.buf[3]) } // 가장 낮은 바이트

//line mmotype.w:593
func (t *typer) printStab() {
	m := int(t.readByte()) // 주 조절 바이트
	if m&0x40 != 0 {
		t.printStab() // 왼쪽 부분 트라이가 비어 있지 않으면 순회한다
	}
	if m&0x2f != 0 {

//line mmotype.w:626
		var hi byte
		if m&0x80 != 0 {
			hi = t.readByte() // 16비트 문자
		}
		c := t.readByte()
		if hi != 0 {
			c = '?' // 아이고, |(hi<<8)+c|는 지금으로서는 쉽게 찍을 수 없다
		}

//line mmotype.w:600
		t.symBuf = append(t.symBuf, c)
		if len(t.symBuf) == symLengthMax {
			fmt.Fprintf(t.stderr, "Oops, the symbol is too long!\n")

			panic(exitSignal(-7))
		}
		if m&0xf != 0 {

//line mmotype.w:647
			var equiv string
			j := m & 0xf
			switch {
			case j == 15:
				equiv = fmt.Sprintf("$%03d", t.readByte())
			case j <= 8:
				equiv = "#"
				for ; j > 0; j-- {
					equiv += fmt.Sprintf("%02x", t.readByte())
				}
				if equiv == "#0000" {
					equiv = "?" // 정의되지 않음
				}
			default:
				equiv = "#20000000000000"[:33-2*j]
				for ; j > 8; j-- {
					equiv += fmt.Sprintf("%02x", t.readByte())
				}
			}
			k := int32(t.readByte())
			serial := k
			for k < 128 {
				k = int32(t.readByte())
				serial = serial<<7 + k
			}
			sym := t.symBuf[1:]
			if i := bytes.IndexByte(sym, 0); i >= 0 {
				sym = sym[:i] // \CEE/ 문자열처럼 널 문자에서 끝난다
			}
			fmt.Fprintf(t.out, "    %s = %s (%d)\n", sym, equiv, serial-128) // 일련번호는 $|serial|-128$

//line mmotype.w:608
		}
		if m&0x20 != 0 {
			t.printStab() // 가운데 부분 트라이를 순회한다
		}
		t.symBuf = t.symBuf[:len(t.symBuf)-1]
	}
	if m&0x10 != 0 {
		t.printStab() // 오른쪽 부분 트라이가 비어 있지 않으면 순회한다
	}
}

//line mmotype.w:47
func mmotype(args []string, stdout, stderr io.Writer, loc *time.Location) (code int) {
	var j, delta int
	postamble := false
	t := &typer{out: bufio.NewWriter(stdout), stderr: stderr, loc: loc}
	defer func() {

//line mmotype.w:73
		t.out.Flush()
		if r := recover(); r != nil {
			e, ok := r.(exitSignal)
			if !ok {
				panic(r)
			}
			code = int(e)
		}

//line mmotype.w:53
	}()

//line mmotype.w:95
	t.listing, t.verbose = true, false
options:
	for j = 1; j < len(args)-1 && len(args[j]) == 2 && args[j][0] == '-'; j++ {
		switch args[j][1] {
		case 's':
			t.listing = false
		case 'v':
			t.verbose = true
		default:
			break options
		}
	}
	if j != len(args)-1 {
		fmt.Fprintf(stderr, "Usage: %s [-s] [-v] mmofile\n", args[0])

		return -1
	}

//line mmotype.w:55

//line mmotype.w:114
	f, err := os.Open(args[len(args)-1])
	if err != nil {
		fmt.Fprintf(stderr, "Can't open file %s!\n", args[len(args)-1])

		return -2
	}
	defer f.Close()
	t.mmoFile = bufio.NewReader(f)

//line mmotype.w:301
	t.listedFile, t.curFile = -1, -1

//line mmotype.w:56

//line mmotype.w:521
	t.readTet() // 입력의 첫 테트라바이트를 읽는다
	if t.buf[0] != mm || t.buf[1] != lopPre {
		fmt.Fprintf(stderr, "Input is not an MMO file (first two bytes are wrong)!\n")

		return -5
	}
	if t.y() != 1 {
		fmt.Fprintf(stderr, "Warning: I'm reading this file as version 1, not version %d!\n", t.y())

	}
	if t.z() > 0 {
		j = t.z()
		t.readTet()
		if t.listing {
			fmt.Fprintf(t.out, "File was created %s\n",
				time.Unix(int64(t.tet), 0).In(t.loc).Format("Mon Jan _2 15:04:05 2006"))
		}
		for j--; j > 0; j-- {
			t.readTet()
			if t.listing {
				fmt.Fprintf(t.out, "Preamble data %08x\n", t.tet)
			}
		}
	}

//line mmotype.w:57
items:
	for !postamble {

//line mmotype.w:217
		t.readTet()
	loop:
		for {
			if t.buf[0] == mm {
				switch t.buf[1] {
				case lopQuote:
					if t.yz != 1 {
						t.err("YZ field of lop_quote should be 1")

						continue items
					}
					t.readTet()

//line mmotype.w:317
				case lopLoc:
					if t.z() == 2 {
						j = t.y()
						t.readTet()
						t.curLoc = Octa(Tetra(j<<24)+t.tet) << 32
					} else if t.z() == 1 {
						t.curLoc = Octa(t.y()) << 56
					} else {
						t.err("Z field of lop_loc should be 1 or 2")

						continue items
					}
					t.readTet()
					t.curLoc |= Octa(t.tet)
					continue items
				case lopSkip:
					t.curLoc += Octa(t.yz)
					continue items

//line mmotype.w:345
				case lopFixo:
					if t.z() == 2 {
						j = t.y()
						t.readTet()
						t.tmp = Octa(Tetra(j<<24)+t.tet) << 32
					} else if t.z() == 1 {
						t.tmp = Octa(t.y()) << 56
					} else {
						t.err("Z field of lop_fixo should be 1 or 2")

						continue items
					}
					t.readTet()
					t.tmp |= Octa(t.tet)
					if t.listing {
						fmt.Fprintf(t.out, "%016x: %016x\n", t.tmp, t.curLoc)
					}
					continue items
				case lopFixr:
					delta = t.yz

//line mmotype.w:390
					if delta >= 0x1000000 {
						t.tmp = t.curLoc + Octa(int64(-((delta&0xffffff)-(1<<j))<<2))
					} else {
						t.tmp = t.curLoc + Octa(int64(-delta<<2))
					}
					if t.listing {
						fmt.Fprintf(t.out, "%016x: %08x\n", t.tmp, Tetra(delta))
					}

//line mmotype.w:366
					continue items

//line mmotype.w:369
				case lopFixrx:
					j = t.yz
					if j != 16 && j != 24 {
						t.err("YZ field of lop_fixrx should be 16 or 24")

						continue items
					}
					t.readTet()
					delta = int(int32(t.tet))
					if delta&-0x2000000 != 0 {
						t.err("increment of lop_fixrx is too large")

						continue items
					}

//line mmotype.w:390
					if delta >= 0x1000000 {
						t.tmp = t.curLoc + Octa(int64(-((delta&0xffffff)-(1<<j))<<2))
					} else {
						t.tmp = t.curLoc + Octa(int64(-delta<<2))
					}
					if t.listing {
						fmt.Fprintf(t.out, "%016x: %08x\n", t.tmp, Tetra(delta))
					}

//line mmotype.w:384
					continue items

//line mmotype.w:409
				case lopFile:
					if t.fileNamed[t.y()] {
						for j = t.z(); j > 0; j-- {
							t.readTet()
						}
						t.curFile = t.y()
						if t.z() != 0 {
							t.err("Two file names with the same number")

							continue items
						}
					} else {
						if t.z() == 0 {
							t.err("No name given for newly selected file")

							continue items
						}

//line mmotype.w:444
						y := t.y()
						t.curFile = y
						var name []byte
						for j = t.z(); j > 0; j-- {
							t.readTet()
							name = append(name, t.buf[:]...)
						}
						for i, c := range name {
							if c == 0 {
								name = name[:i]
								break
							}
						}
						t.fileName[y], t.fileNamed[y] = string(name), true

//line mmotype.w:427
					}
					t.curLine = 0
					continue items
				case lopLine:
					if t.curFile < 0 {
						t.err("No file was selected for lop_line")

						continue items
					}
					t.curLine = t.yz
					continue items

//line mmotype.w:464
				case lopSpec:
					if t.listing {
						fmt.Fprintf(t.out, "Special data %d at loc %016x", t.yz, t.curLoc)
						if t.curLine == 0 {
							fmt.Fprintf(t.out, "\n")
						} else {

//line mmotype.w:277
							if t.curFile == t.listedFile {
								fmt.Fprintf(t.out, " (line %d)\n", t.curLine)
							} else {
								name := "(null)"
								if t.fileNamed[t.curFile] {
									name = t.fileName[t.curFile]
								}
								fmt.Fprintf(t.out, " (\"%s\", line %d)\n", name, t.curLine)
								t.listedFile = t.curFile
							}

//line mmotype.w:471
						}
					}
					for {
						t.readTet()
						if t.buf[0] == mm {
							if t.buf[1] != lopQuote || t.yz != 1 {
								continue loop // 특수 데이터의 끝
							}
							t.readTet()
						}
						if t.listing {
							fmt.Fprintf(t.out, "                   %08x\n", t.tet)
						}
					}

//line mmotype.w:490
				case lopPre:
					t.err("Can't have another preamble")

					continue items
				case lopPost:
					postamble = true
					if t.y() != 0 {
						t.err("Y field of lop_post should be zero")

						continue items
					}
					if t.z() < 32 {
						t.err("Z field of lop_post must be 32 or more")

					}
					continue items
				case lopStab:
					t.err("Symbol table must follow postamble")

					continue items
				case lopEnd:
					t.err("Symbol table can't end before it begins")
					continue items

//line mmotype.w:230
				default:
					t.err("Unknown lopcode")

					continue items
				}
			}
			break
		}
		if t.listing {

//line mmotype.w:257
			fmt.Fprintf(t.out, "%016x: %08x", t.curLoc, t.tet)
			if t.curLine == 0 {
				fmt.Fprintf(t.out, "\n")
			} else {
				if t.curLoc>>61 != 0 {
					fmt.Fprintf(t.out, "\n")
				} else {

//line mmotype.w:277
					if t.curFile == t.listedFile {
						fmt.Fprintf(t.out, " (line %d)\n", t.curLine)
					} else {
						name := "(null)"
						if t.fileNamed[t.curFile] {
							name = t.fileName[t.curFile]
						}
						fmt.Fprintf(t.out, " (\"%s\", line %d)\n", name, t.curLine)
						t.listedFile = t.curFile
					}

//line mmotype.w:265
				}
				t.curLine++
			}
			t.curLoc = (t.curLoc + 4) &^ 3

//line mmotype.w:240
		}

//line mmotype.w:60
	}

//line mmotype.w:550
	for j = t.z(); j < 256; j++ {
		t.readTet()
		t.tmp = Octa(t.tet) << 32
		t.readTet()
		if t.listing {
			if t.tmp != 0 || t.tet != 0 {
				fmt.Fprintf(t.out, "g%03d: %016x\n", j, t.tmp|Octa(t.tet))
			} else {
				fmt.Fprintf(t.out, "g%03d: 0\n", j)
			}
		}
	}

//line mmotype.w:62

//line mmotype.w:567
	t.readTet()
	if t.buf[0] != mm || t.buf[1] != lopStab {
		fmt.Fprintf(stderr, "Symbol table does not follow the postamble!\n")

		return -6
	}
	if t.yz != 0 {
		fmt.Fprintf(stderr, "YZ field of lop_stab should be zero!\n")

	}
	fmt.Fprintf(t.out, "Symbol table (beginning at tetra %d):\n", t.count)
	t.stabStart = t.count
	t.symBuf = t.symBuf[:0]
	t.printStab()

//line mmotype.w:694
	for t.byteCount != 0 {
		if t.readByte() != 0 {
			fmt.Fprintf(stderr, "Nonzero byte follows the symbol table!\n")

		}
	}
	t.readTet()
	switch {
	case t.buf[0] != mm || t.buf[1] != lopEnd:
		fmt.Fprintf(stderr, "The symbol table isn't followed by lop_end!\n")

	case t.count != t.stabStart+t.yz+1:
		fmt.Fprintf(stderr, "YZ field at lop_end should have been %d!\n", t.count-t.yz-1)

	default:
		if t.verbose {
			fmt.Fprintf(t.out, "Symbol table ends at tetra %d.\n", t.count)
		}
		if _, err := t.mmoFile.ReadByte(); err == nil {
			fmt.Fprintf(stderr, "Extra bytes follow the lop_end!\n")

		}
	}

//line mmotype.w:63
	return 0
}

func main() {
	os.Exit(mmotype(os.Args, os.Stdout, os.Stderr, time.Local))
}
