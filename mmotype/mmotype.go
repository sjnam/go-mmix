//line mmotype/mmotype.w:25
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"time"
)

//line mmotype/mmotype.w:79
type typer struct {

//line mmotype/mmotype.w:117
	listing bool           // are we listing everything?
	verbose bool           // are we also showing the tetras of input as they are read?
	mmoFile *bufio.Reader  // the input file
	out     *bufio.Writer  // standard output
	stderr  io.Writer      // standard error
	loc     *time.Location // time zone for printing the file creation time

//line mmotype/mmotype.w:195
	count     int     // the number of tetrabytes we've read
	byteCount int     // index of the next-to-be-read byte
	buf       [4]byte // the most recently read bytes
	yz        int     // the two least significant bytes
	tet       Tetra   // |buf| bytes packed big-endianwise

//line mmotype/mmotype.w:285
	curLoc     Octa        // the current location
	listedFile int         // the most recently listed file number
	curFile    int         // the most recently selected file number
	curLine    int         // the current position in |curFile|
	fileName   [256]string // file names seen
	fileNamed  [256]bool   // have we seen the file name with that number?
	tmp        Octa        // an octabyte of temporary interest

//line mmotype/mmotype.w:675
	stabStart int    // where the symbol table began
	symBuf    []byte // the characters on middle transitions to current node

//line mmotype/mmotype.w:81
}

type exitSignal int // a signal to end the program with this exit code

//line mmotype/mmotype.w:153
type (
	Tetra = uint32 // a tetrabyte
	Octa  = uint64 // an octabyte
)

//line mmotype/mmotype.w:128
const (
	mm       = 0x98 // the escape code of \.{mmo} format
	lopQuote = 0x0  // the quotation lopcode
	lopLoc   = 0x1  // the location lopcode
	lopSkip  = 0x2  // the skip lopcode
	lopFixo  = 0x3  // the octabyte-fix lopcode
	lopFixr  = 0x4  // the relative-fix lopcode
	lopFixrx = 0x5  // extended relative-fix lopcode
	lopFile  = 0x6  // the file name lopcode
	lopLine  = 0x7  // the file position lopcode
	lopSpec  = 0x8  // the special hook lopcode
	lopPre   = 0x9  // the preamble lopcode
	lopPost  = 0xa  // the postamble lopcode
	lopStab  = 0xb  // the symbol table lopcode
	lopEnd   = 0xc  // the end-it-all lopcode
)

//line mmotype/mmotype.w:672
const symLengthMax = 1000

//line mmotype/mmotype.w:168
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

//line mmotype/mmotype.w:185
func (t *typer) readByte() byte {
	if t.byteCount == 0 {
		t.readTet()
	}
	b := t.buf[t.byteCount]
	t.byteCount = (t.byteCount + 1) & 3
	return b
}

//line mmotype/mmotype.w:240
func (t *typer) err(m string) {
	fmt.Fprintf(t.stderr, "Error in tetra %d: %s!\n", t.count, m)

}

//line mmotype/mmotype.w:302
func (t *typer) y() int { return int(t.buf[2]) } // the next-to-least significant byte
func (t *typer) z() int { return int(t.buf[3]) } // the least significant byte

//line mmotype/mmotype.w:586
func (t *typer) printStab() {
	m := int(t.readByte()) // the master control byte
	if m&0x40 != 0 {
		t.printStab() // traverse the left subtrie, if it is nonempty
	}
	if m&0x2f != 0 {

//line mmotype/mmotype.w:619
		var hi byte
		if m&0x80 != 0 {
			hi = t.readByte() // 16-bit character
		}
		c := t.readByte()
		if hi != 0 {
			c = '?' // oops, we can't print |(hi<<8)+c| easily at this time
		}

//line mmotype/mmotype.w:593
		t.symBuf = append(t.symBuf, c)
		if len(t.symBuf) == symLengthMax {
			fmt.Fprintf(t.stderr, "Oops, the symbol is too long!\n")

			panic(exitSignal(-7))
		}
		if m&0xf != 0 {

//line mmotype/mmotype.w:640
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
					equiv = "?" // undefined
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
				sym = sym[:i] // null-terminated, like a \CEE/ string
			}
			fmt.Fprintf(t.out, "    %s = %s (%d)\n", sym, equiv, serial-128) // the serial number is $|serial|-128$

//line mmotype/mmotype.w:601
		}
		if m&0x20 != 0 {
			t.printStab() // traverse the middle subtrie
		}
		t.symBuf = t.symBuf[:len(t.symBuf)-1]
	}
	if m&0x10 != 0 {
		t.printStab() // traverse the right subtrie, if it is nonempty
	}
}

//line mmotype/mmotype.w:40
func mmotype(args []string, stdout, stderr io.Writer, loc *time.Location) (code int) {
	var j, delta int
	postamble := false
	t := &typer{out: bufio.NewWriter(stdout), stderr: stderr, loc: loc}
	defer func() {

//line mmotype/mmotype.w:66
		t.out.Flush()
		if r := recover(); r != nil {
			e, ok := r.(exitSignal)
			if !ok {
				panic(r)
			}
			code = int(e)
		}

//line mmotype/mmotype.w:46
	}()

//line mmotype/mmotype.w:88
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

//line mmotype/mmotype.w:48

//line mmotype/mmotype.w:107
	f, err := os.Open(args[len(args)-1])
	if err != nil {
		fmt.Fprintf(stderr, "Can't open file %s!\n", args[len(args)-1])

		return -2
	}
	defer f.Close()
	t.mmoFile = bufio.NewReader(f)

//line mmotype/mmotype.w:294
	t.listedFile, t.curFile = -1, -1

//line mmotype/mmotype.w:49

//line mmotype/mmotype.w:514
	t.readTet() // read the first tetrabyte of input
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

//line mmotype/mmotype.w:50
items:
	for !postamble {

//line mmotype/mmotype.w:210
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

//line mmotype/mmotype.w:310
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

//line mmotype/mmotype.w:338
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

//line mmotype/mmotype.w:383
					if delta >= 0x1000000 {
						t.tmp = t.curLoc + Octa(int64(-((delta&0xffffff)-(1<<j))<<2))
					} else {
						t.tmp = t.curLoc + Octa(int64(-delta<<2))
					}
					if t.listing {
						fmt.Fprintf(t.out, "%016x: %08x\n", t.tmp, Tetra(delta))
					}

//line mmotype/mmotype.w:359
					continue items

//line mmotype/mmotype.w:362
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

//line mmotype/mmotype.w:383
					if delta >= 0x1000000 {
						t.tmp = t.curLoc + Octa(int64(-((delta&0xffffff)-(1<<j))<<2))
					} else {
						t.tmp = t.curLoc + Octa(int64(-delta<<2))
					}
					if t.listing {
						fmt.Fprintf(t.out, "%016x: %08x\n", t.tmp, Tetra(delta))
					}

//line mmotype/mmotype.w:377
					continue items

//line mmotype/mmotype.w:402
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

//line mmotype/mmotype.w:437
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

//line mmotype/mmotype.w:420
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

//line mmotype/mmotype.w:457
				case lopSpec:
					if t.listing {
						fmt.Fprintf(t.out, "Special data %d at loc %016x", t.yz, t.curLoc)
						if t.curLine == 0 {
							fmt.Fprintf(t.out, "\n")
						} else {

//line mmotype/mmotype.w:270
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

//line mmotype/mmotype.w:464
						}
					}
					for {
						t.readTet()
						if t.buf[0] == mm {
							if t.buf[1] != lopQuote || t.yz != 1 {
								continue loop // end of special data
							}
							t.readTet()
						}
						if t.listing {
							fmt.Fprintf(t.out, "                   %08x\n", t.tet)
						}
					}

//line mmotype/mmotype.w:483
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

//line mmotype/mmotype.w:223
				default:
					t.err("Unknown lopcode")

					continue items
				}
			}
			break
		}
		if t.listing {

//line mmotype/mmotype.w:250
			fmt.Fprintf(t.out, "%016x: %08x", t.curLoc, t.tet)
			if t.curLine == 0 {
				fmt.Fprintf(t.out, "\n")
			} else {
				if t.curLoc>>61 != 0 {
					fmt.Fprintf(t.out, "\n")
				} else {

//line mmotype/mmotype.w:270
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

//line mmotype/mmotype.w:258
				}
				t.curLine++
			}
			t.curLoc = (t.curLoc + 4) &^ 3

//line mmotype/mmotype.w:233
		}

//line mmotype/mmotype.w:53
	}

//line mmotype/mmotype.w:543
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

//line mmotype/mmotype.w:55

//line mmotype/mmotype.w:560
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

//line mmotype/mmotype.w:687
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

//line mmotype/mmotype.w:56
	return 0
}

func main() {
	os.Exit(mmotype(os.Args, os.Stdout, os.Stderr, time.Local))
}
