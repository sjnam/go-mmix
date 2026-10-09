//line mmmix.w:24
package main

import (
	"bufio"
	"bytes"
	"io"
	"os"
	"strconv"

	"github.com/sjnam/go-mmix/mmixio"
)

//line mmmix.w:914
type cfile struct {
	f   *os.File      // the file being read; |nil| if standard input
	r   *bufio.Reader // read buffer
	pos int64         // position that |ftell| would return
	eof bool          // end-of-file indicator (|feof|)
}

//line mmmix.w:162
const bufSize = 100

//line mmmix.w:438
const kernelBoot = 0x8000000500000000 // where the kernel starts

//line mmmix.w:457
const (
	mm       = 0x98 // the escape code of the \.{mmo} format
	lopQuote = 0x0  // the quotation lopcode
	lopLoc   = 0x1  // the location lopcode
	lopSkip  = 0x2  // the skip lopcode
	lopFixo  = 0x3  // the octabyte-fix lopcode
	lopFixr  = 0x4  // the relative-fix lopcode
	lopFixrx = 0x5  // extended relative-fix lopcode
	lopFile  = 0x6  // the file name lopcode
	lopLine  = 0x7  // the file position lopcode
	lopPre   = 0x9  // the preamble lopcode
	lopPost  = 0xa  // the postamble lopcode
	lopStab  = 0xb  // the symbol table lopcode
	lopEnd   = 0xc  // the end-it-all lopcode
)

//line mmmix.w:297
func (mx *machine) undumpOcta(f *cfile, name string, dat *Octa) bool {
	var t Tetra
	for k := 0; k < 8; k++ {
		c, err := f.r.ReadByte()
		if err != nil {
			if k == 0 {
				return false
			}
			mx.errprintf("Premature end of file on %s!\n", name)

			return false
		}
		t = t<<8 + Tetra(c)
		if k == 3 {
			*dat = Octa(t)<<32 | *dat&0xffffffff
			t = 0
		}
	}
	*dat = *dat&^0xffffffff | Octa(t)
	return true
}

//line mmmix.w:478
func (mx *machine) kernelTet(f *cfile, name string) Tetra {
	var b [4]byte
	if _, err := io.ReadFull(f.r, b[:]); err != nil {
		mx.kernelErr(name)
	}
	return Tetra(b[0])<<24 | Tetra(b[1])<<16 | Tetra(b[2])<<8 | Tetra(b[3])
}

func (mx *machine) kernelAddress(f *cfile, name string, t Tetra) Octa {
	var h Tetra
	switch t & 0xff {
	case 2:
		h = (t>>8&0xff)<<24 + mx.kernelTet(f, name)
	case 1:
		h = (t >> 8 & 0xff) << 24
	default:
		mx.kernelErr(name)
	}
	return Octa(h)<<32 | Octa(mx.kernelTet(f, name))
}

func (mx *machine) kernelErr(name string) {
	mx.errprintf("Panic: Bad kernel object file %s!\n", name)

	panic(exitSignal(-4))
}

//line mmmix.w:510
func (mx *machine) kernelLoad(loc Octa, t Tetra, xor bool) {
	if loc&signBit == 0 || loc-signBit >= hioBase {
		mx.errprintf("Panic: Kernel location %016x isn't in negative memory!\n", loc)

		panic(exitSignal(-5))
	}
	a := (loc - signBit) &^ 7
	s := 32 * (^loc >> 2 & 1) // 32 if the upper tetra
	o := mx.memRead(a)
	if xor {
		o ^= Octa(t) << s
	} else {
		o = o&^(0xffffffff<<s) | Octa(t)<<s
	}
	mx.memWrite(a, o)
}

//line mmmix.w:761
func readHex(p []byte) Octa {
	var h, l Tetra
	d := make([]byte, 0, len(p))
	j := 0
scan:
	for ; j < len(p); j++ {
		switch c := p[j]; {
		case c >= '0' && c <= '9':
			d = append(d, c-'0')
		case c >= 'a' && c <= 'f':
			d = append(d, c-'a'+10)
		case c >= 'A' && c <= 'F':
			d = append(d, c-'A'+10)
		default:
			break scan
		}
	}
	if j < len(p) {
		p[j] = 0
	}
	for j, k := len(d)-1, 0; k <= j; k++ {
		if k >= 8 {
			h += Tetra(d[j-k]) << ((4*k - 32) & 31)
		} else {
			l += Tetra(d[j-k]) << (4 * k)
		}
	}
	return Octa(h)<<32 | Octa(l)
}

//line mmmix.w:922
func openCfile(name string) *cfile {
	f, err := os.Open(name)
	if err != nil {
		return nil
	}
	return &cfile{f: f, r: bufio.NewReader(f)}
}

//line mmmix.w:935
func (c *cfile) fgets(buf []byte, n int) bool {
	if c.eof {
		return false
	}
	i := 0
	for i < n-1 {
		ch, err := c.r.ReadByte()
		if err != nil {
			c.eof = true
			break
		}
		buf[i] = ch
		i++
		c.pos++
		if ch == '\n' {
			break
		}
	}
	if i == 0 {
		return false
	}
	buf[i] = 0
	return true
}

//line mmmix.w:964
func strlen(b []byte) int {
	if n := bytes.IndexByte(b, 0); n >= 0 {
		return n
	}
	return len(b)
}

func cstr(b []byte) []byte { return b[:strlen(b)] }

func isdigit(c byte) bool { return '0' <= c && c <= '9' }

func isxdigit(c byte) bool {
	return isdigit(c) || 'a' <= c && c <= 'f' || 'A' <= c && c <= 'F'
}

func isspace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}

//line mmmix.w:989
func sscanfD(b []byte) (int32, bool) {
	s := cstr(b)
	i := 0
	for i < len(s) && isspace(s[i]) {
		i++
	}
	s = s[i:]
	if len(s) > 512 {
		s = s[:512]
	}
	i = 0
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		i++
	}
	j := i
	for j < len(s) && isdigit(s[j]) {
		j++
	}
	if j == i {
		return 0, false
	}
	v, _ := strconv.ParseInt(string(s[:j]), 10, 64) // saturates on overflow
	return int32(v), true
}

//line mmmix.w:1021
func sscanfX(s []byte, w1, w2 int) (Tetra, Tetra, bool) {
	h, s, ok := scanHexField(s, w1)
	if !ok {
		return 0, 0, false
	}
	l, _, ok := scanHexField(s, w2)
	return h, l, ok
}

func scanHexField(s []byte, width int) (Tetra, []byte, bool) {
	for len(s) > 0 && isspace(s[0]) {
		s = s[1:]
	}
	var buf []byte
	nDigits := true

//line mmmix.w:1047
	signOK, pfxOK, nzDigits, haveSign := true, true, true, false
scan:
	for ; width > 0 && len(buf) < len(s); width-- {
		c := s[len(buf)]
		switch {
		case c == '0':
			if nzDigits {
				signOK, nzDigits, nDigits = false, false, false
			} else {
				signOK, pfxOK, nDigits = false, false, false
			}
		case isxdigit(c):
			signOK, pfxOK, nDigits = false, false, false
		case (c == '+' || c == '-') && signOK:
			signOK, haveSign = false, true
		case (c == 'x' || c == 'X') && pfxOK && len(buf) == 1+b2i(haveSign):
			pfxOK = false
		default:
			break scan
		}
		buf = append(buf, c)
	}

//line mmmix.w:1037
	if nDigits {
		return 0, s, false
	}
	if c := buf[len(buf)-1]; c == 'x' || c == 'X' {
		buf = buf[:len(buf)-1]
	}

//line mmmix.w:1071
	rest := s[len(buf):]
	neg := buf[0] == '-'
	if buf[0] == '+' || buf[0] == '-' {
		buf = buf[1:]
	}
	if len(buf) > 1 && buf[0] == '0' && (buf[1] == 'x' || buf[1] == 'X') {
		buf = buf[2:]
	}
	v, _ := strconv.ParseUint(string(buf), 16, 64)
	if neg {
		v = -v
	}
	return Tetra(v), rest, true

//line mmmix.w:1044
}

//line mmmix.w:40
func mmmix(args []string, stdin io.Reader, stdout, stderr io.Writer) (code int) {
	mx := &machine{

//line mmmix.w:69
		out:    bufio.NewWriter(stdout),
		stderr: stderr,
		stdin:  &cfile{r: bufio.NewReader(stdin)},

//line mmmix.w:41
	}
	defer func() {

//line mmmix.w:78
		mx.out.Flush()
		if mx.io != nil {
			mx.io.FlushAll()
		}
		if mx.hioDev != nil {
			mx.hioDev.io.FlushAll() // supplement: files opened by the kernel's devices
		}
		if mx.blkDev != nil {
			mx.blkDev.f.Close() // supplement: the disk image
		}
		if r := recover(); r != nil {
			e, ok := r.(exitSignal)
			if !ok {
				panic(r)
			}
			code = int(e)
		}

//line mmmix.w:44
	}()

//line mmmix.w:165
	var (
		n, m           int                    // temporary integers
		curLoc         Octa                   // the current location
		curDat         Octa                   // the current data
		newChunk       bool                   // should we look for a new chunk?
		buffer         [bufSize]byte          // input line
		progFile       *cfile                 // the program file
		silent         bool                   // was \.{-s} given?
		badAddress     bool                   // is the current location unusable?
		bp             Octa          = negOne // breakpoint
		tmp            Octa                   // an octabyte of temporary interest
		kernelFileName string                 // supplement: kernel object file given by \.{-k}
		diskFileName   string                 // supplement: disk image given by \.{-d}
	)

//line mmmix.w:46

//line mmmix.w:115
	argc := len(args)
	for n = 1; n < len(args) && len(args[n]) > 0 && args[n][0] == '-'; n++ {
		if len(args[n]) > 1 && args[n][1] == 's' {
			silent = true
		} else if len(args[n]) > 2 && args[n][1] == 'k' {
			kernelFileName = args[n][2:]
		} else if len(args[n]) > 2 && args[n][1] == 'd' {
			diskFileName = args[n][2:]
		} else {
			argc = 0 // unknown option
		}
	}
	if argc != n+2 {
		mx.errprintf("Usage: %s [-s] configfile progfile\n", args[0])

		panic(exitSignal(-3))
	}
	configFileName := args[argc-2]
	progFileName := args[argc-1]

//line mmmix.w:47
	mx.MMIXConfig(configFileName)
	mx.MMIXInit()
	mx.io = mmixio.New(mx, mx.out, stderr)

//line mmmix.w:136
	if len(progFileName) > 4 && progFileName[len(progFileName)-4:] == ".mmb" {

//line mmmix.w:266
		progFile = openCfile(progFileName)
		if progFile == nil {
			mx.errprintf("Panic: Can't open MMIX binary file %s!\n", progFileName)

			panic(exitSignal(-3))
		}
		for {
			if !mx.undumpOcta(progFile, progFileName, &curDat) {
				break
			}
			newChunk = true
			curLoc = curDat
			if curLoc>>32&0x9fffffff != 0 {
				badAddress = true
			} else {
				badAddress = false
				curLoc = curLoc>>61<<32 | curLoc&0xffffffff // apply trivial mapping function for each segment
			}

//line mmmix.w:320
			for {
				if !mx.undumpOcta(progFile, progFileName, &curDat) {
					mx.errprintf("Unexpected end of file on %s!\n", progFileName)

					break
				}
				if curDat == 0 {
					break
				}
				if badAddress {
					mx.errprintf("Panic: Unsupported virtual address %016x!\n", curLoc)

					panic(exitSignal(-5))
				}

//line mmmix.w:244
				if newChunk {
					mx.memWrite(curLoc, curDat)
				} else {
					mx.memHash[mx.lastH].chunk[(Tetra(curLoc)&0xffff)>>3] = curDat
				}
				curLoc = curLoc&^0xffffffff | Octa(Tetra(curLoc)+8)

//line mmmix.w:335
				if Tetra(curLoc)&0xfff8 != 0 {
					newChunk = false
				} else {
					newChunk = true
					if Tetra(curLoc)&0xffff0000 == 0 {
						badAddress = true
						curLoc = Octa(Tetra(curLoc>>32)<<29+1)<<32 | curLoc&0xffffffff
					}
				}
			}

//line mmmix.w:285
		}

//line mmmix.w:353
		if curLoc>>32 != 3 {
			mx.errprintf("Panic: MMIX binary file didn't set up the stack!\n")

			panic(exitSignal(-6))
		}
		mx.instPtr.o = mx.memRead(curLoc - 8*14) // \.{Main}
		mx.instPtr.p = nil
		curLoc = 0x60000000<<32 | curLoc&0xffffffff
		mx.g[255].o = curLoc - 8 // place to \.{UNSAVE}
		curDat = curDat&^0xffffffff | 0xf0
		if mx.memRead(curDat)>>32 != 0 {
			mx.instPtr.o = curDat // start at |0xf0| if nonzero
		}
		mx.head.inst = UNSAVE<<24 + 255 // prefetch a fabricated command
		mx.tail = mx.prevFetch(mx.tail)
		mx.head.loc = mx.instPtr.o - 4 // in case the \.{UNSAVE} is interrupted
		mx.g[rT].o = 0x80000005<<32 | mx.g[rT].o&0xffffffff
		mx.g[rTT].o = 0x80000006<<32 | mx.g[rTT].o&0xffffffff

//line mmmix.w:380
		curDat = Octa(RESUME<<24+1) << 32
		curLoc = 5 << 32
		mx.memWrite(curLoc, curDat) // the primitive trap handler
		curDat = Octa(NEGI<<24+255<<16+1)<<32 | curDat>>32
		curLoc = 6<<32 | 8
		mx.memWrite(curLoc, curDat) // the primitive dynamic trap handler
		curDat = Octa(GET<<24+rQ)<<32 | Octa(PUTI<<24+rQ<<16)
		curLoc = 6 << 32
		mx.memWrite(curLoc, curDat) // more of the primitive dynamic trap handler

//line mmmix.w:391
		curDat = 7                  // generate a PTE with \.{rwx} permission
		curLoc = 4 << 32            // beginning of skeleton page table
		mx.memWrite(curLoc, curDat) // PTE for the text segment
		mx.ITcache.set[0][0].tag = 0
		mx.ITcache.set[0][0].data[0] = curDat // prime the IT cache
		curDat = 1<<32 | 6                    // PTE with read and write permission only
		curLoc = 4<<32 | 3<<13
		mx.memWrite(curLoc, curDat) // PTE for the data segment
		curDat = 2<<32 | 6
		curLoc = 4<<32 | 6<<13
		mx.memWrite(curLoc, curDat) // PTE for the pool segment
		curDat = 3<<32 | 6
		curLoc = 4<<32 | 9<<13
		mx.memWrite(curLoc, curDat) // PTE for the stack segment

//line mmmix.w:373
		mx.g[rK].o = negOne // enable all interrupts
		mx.g[rV].o = 0x369c2004<<32 | mx.g[rV].o&0xffffffff
		mx.pageBad, mx.pageR, mx.pageS = false, 4<<(32-13), 32
		mx.pageMask = mx.pageMask&^0xffffffff | 0xffffffff
		mx.pageB[1], mx.pageB[2], mx.pageB[3], mx.pageB[4] = 3, 6, 9, 12

//line mmmix.w:138
	} else {

//line mmmix.w:184
		progFile = openCfile(progFileName)
		if progFile == nil {
			mx.errprintf("Panic: Can't open MMIX hexadecimal file %s!\n", progFileName)

			panic(exitSignal(-3))
		}
		newChunk = true
		for {
			if !progFile.fgets(buffer[:], bufSize) {
				break
			}
			if l := strlen(buffer[:]); l == 0 || buffer[l-1] != '\n' {
				mx.errprintf("Panic: Hexadecimal file line too long: `%s...'!\n", cstr(buffer[:]))

				panic(exitSignal(-3))
			}
			if buffer[12] == ':' {

//line mmmix.w:214
				if h, l, ok := sscanfX(cstr(buffer[:]), 4, 8); !ok {
					mx.errprintf("Panic: Improper hexadecimal file location: `%s'!\n", cstr(buffer[:]))

					panic(exitSignal(-3))
				} else {
					curLoc = Octa(h)<<32 | Octa(l)
				}
				newChunk = true

//line mmmix.w:202
			} else if buffer[0] == ' ' {

//line mmmix.w:226
				if h, l, ok := sscanfX(cstr(buffer[1:]), 8, 8); !ok {
					mx.errprintf("Panic: Improper hexadecimal file data: `%s'!\n", cstr(buffer[:]))

					panic(exitSignal(-3))
				} else {
					curDat = Octa(h)<<32 | Octa(l)
				}

//line mmmix.w:244
				if newChunk {
					mx.memWrite(curLoc, curDat)
				} else {
					mx.memHash[mx.lastH].chunk[(Tetra(curLoc)&0xffff)>>3] = curDat
				}
				curLoc = curLoc&^0xffffffff | Octa(Tetra(curLoc)+8)

//line mmmix.w:234
				if Tetra(curLoc)&0xfff8 != 0 {
					newChunk = false
				} else {
					newChunk = true
					if Tetra(curLoc)&0xffff0000 == 0 {
						curLoc += 1 << 32
					}
				}

//line mmmix.w:204
			} else {
				mx.errprintf("Panic: Improper hexadecimal file line: `%s'!\n", cstr(buffer[:]))

				panic(exitSignal(-3))
			}
		}

//line mmmix.w:140
	}
	progFile.f.Close()

//line mmmix.w:51

//line mmmix.w:421
	if diskFileName != "" {

//line mmmix.w:443
		f, err := os.OpenFile(diskFileName, os.O_RDWR, 0)
		if err != nil {
			mx.errprintf("Panic: Can't open disk image %s!\n", diskFileName)

			panic(exitSignal(-3))
		}
		st, _ := f.Stat()
		mx.blkDev = &blk{mx: mx, f: f, nblk: Octa(st.Size() / blkSize)}

//line mmmix.w:423
	}
	if kernelFileName != "" {
		mx.hioDev = &hio{mx: mx}
		mx.hioDev.io = mmixio.New(mx.hioDev, mx.out, stderr)

//line mmmix.w:532
		kf := openCfile(kernelFileName)
		if kf == nil {
			mx.errprintf("Panic: Can't open kernel object file %s!\n", kernelFileName)

			panic(exitSignal(-3))
		}
		t := mx.kernelTet(kf, kernelFileName)
		if t>>16 != mm<<8|lopPre || t>>8&0xff != 1 {
			mx.kernelErr(kernelFileName)
		}
		for j := t & 0xff; j > 0; j-- {
			mx.kernelTet(kf, kernelFileName) // the time the file was created
		}
		curLoc = 0
	items:
		for {
			t = mx.kernelTet(kf, kernelFileName)
			if t>>24 == mm {
				yz := t & 0xffff
				switch t >> 16 & 0xff {
				case lopQuote:
					if yz != 1 {
						mx.kernelErr(kernelFileName)
					}
					t = mx.kernelTet(kf, kernelFileName)

//line mmmix.w:568
				case lopLoc:
					curLoc = mx.kernelAddress(kf, kernelFileName, t)
					continue items
				case lopSkip:
					curLoc += Octa(yz)
					continue items
				case lopFixo:
					a := mx.kernelAddress(kf, kernelFileName, t)
					mx.kernelLoad(a, Tetra(curLoc>>32), true)
					mx.kernelLoad(a+4, Tetra(curLoc), true)
					continue items
				case lopFile:
					for j := t & 0xff; j > 0; j-- {
						mx.kernelTet(kf, kernelFileName) // the file name
					}
					continue items
				case lopLine:
					continue items
				case lopPost, lopStab, lopEnd:
					break items

//line mmmix.w:593
				case lopFixr, lopFixrx:
					delta := yz
					j := Tetra(0)
					if t>>16&0xff == lopFixrx {
						j = yz
						if j != 16 && j != 24 {
							mx.kernelErr(kernelFileName)
						}
						delta = mx.kernelTet(kf, kernelFileName)
						if delta&0xfe000000 != 0 {
							mx.kernelErr(kernelFileName)
						}
					}
					d := Octa(delta)
					if delta >= 0x1000000 {
						d = Octa(delta&0xffffff) - 1<<j
					}
					mx.kernelLoad(curLoc-d<<2, delta, true)
					continue items

//line mmmix.w:558
				default:
					mx.kernelErr(kernelFileName)
				}
			}
			mx.kernelLoad(curLoc, t, false)
			curLoc = (curLoc + 4) &^ 3
		}
		kf.f.Close()

//line mmmix.w:428
		if len(progFileName) > 4 && progFileName[len(progFileName)-4:] == ".mmb" {
			mx.g[rWW].o = mx.instPtr.o
			mx.g[rXX].o = signBit
			mx.instPtr.o = kernelBoot
			mx.head.loc = kernelBoot - 4

//line mmmix.w:747
			if mx.instPtr.o&signBit != 0 {
				mx.g[rK].o &^= 1 << 32 // disable interrupts on |pBit|
			}
			mx.instPtr.p = nil

//line mmmix.w:434
		}
	}

//line mmmix.w:52
	if silent {
		return mx.MMIXSilent()
	}

//line mmmix.w:664
interact:
	for {
		mx.printf("mmmix> ")

		mx.out.Flush()
		mx.stdin.fgets(buffer[:], bufSize)
		whatSay := false
		switch buffer[0] {
		case 'q', 'x':
			break interact

//line mmmix.w:684
		case 'h', '?':
			mx.printf("The interactive commands are as follows:\n")
			mx.printf(" <n> to run for n cycles\n")
			mx.printf(" @<x> to take next instruction from location x\n")
			mx.printf(" k    to change the sign bit of the instruction location\n")
			mx.printf(" b<x> to pause when location x is fetched\n")
			mx.printf(" v<x> to print specified diagnostics when running;\n")
			mx.printf("    x=1[insts enter/leave pipe]+2[whole pipeline each cycle]+\n")
			mx.printf("      4[coroutine activations]+8[coroutine scheduling]+\n")
			mx.printf("      10[uninitialized read]+20[online I/O read]+\n")
			mx.printf("      40[I/O read/write]+80[branch prediction details]+\n")
			mx.printf("      100[invalid cache blocks displayed too]\n")

//line mmmix.w:699
			mx.printf(" -<n> to deissue n instructions\n")
			mx.printf(" l<n> to print current value of local register n\n")
			mx.printf(" g<n> to print current value of global register n\n")
			mx.printf(" m<x> to print current value of memory address x\n")
			mx.printf(" f<x> to insert instruction x into the fetch buffer\n")
			mx.printf(" i<n> to initiate a timer interrupt after n cycles\n")
			mx.printf(" IT, DT, I, D, or S to print current cache contents\n")
			mx.printf(" D* or S* to print dirty blocks of a cache\n")
			mx.printf(" p to print current pipeline contents\n")
			mx.printf(" s to print current stats\n")
			mx.printf(" h to print this message\n")
			mx.printf(" q to exit\n")
			mx.printf("(Here <n> is a decimal integer, <x> is hexadecimal.)\n")

//line mmmix.w:718
		case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
			if v, ok := sscanfD(buffer[:]); !ok {
				whatSay = true
				break
			} else {
				n = int(v)
			}
			mx.printf("Running %d at time %d", n, int32(Tetra(mx.ticks)))
			if bp == negOne {
				mx.printf("\n")
			} else {
				mx.printf(" with breakpoint %016x\n", bp)
			}
			mx.MMIXRun(n, bp)
		case '@':
			mx.instPtr.o = readHex(buffer[1:])

//line mmmix.w:747
			if mx.instPtr.o&signBit != 0 {
				mx.g[rK].o &^= 1 << 32 // disable interrupts on |pBit|
			}
			mx.instPtr.p = nil

//line mmmix.w:735
		case 'k':
			mx.instPtr.o ^= 0x80000000 << 32 // shortcut to kernel mode
			if Tetra(mx.ticks) == 0 && mx.head != nil {
				mx.head.loc ^= 0x80000000 << 32 // fix the \.{UNSAVE} loc
			}

//line mmmix.w:747
			if mx.instPtr.o&signBit != 0 {
				mx.g[rK].o &^= 1 << 32 // disable interrupts on |pBit|
			}
			mx.instPtr.p = nil

//line mmmix.w:741
		case 'b':
			bp = readHex(buffer[1:])
		case 'v':
			mx.verbose = int(Tetra(readHex(buffer[1:])))

//line mmmix.w:794
		case '-':
			if v, ok := sscanfD(buffer[1:]); !ok || v < 0 {
				whatSay = true
				break
			} else {
				n = int(v)
			}
			if mx.cool.idx <= mx.hot.idx {
				m = mx.hot.idx - mx.cool.idx
			} else {
				m = mx.hot.idx - mx.reorderBot.idx + 1 + mx.reorderTop.idx - mx.cool.idx
			}
			mx.deissues = min(n, m)
		case 'l':
			if v, ok := sscanfD(buffer[1:]); !ok || v < 0 || int(v) >= mx.lringSize {
				whatSay = true
				break
			} else {
				n = int(v)
			}
			mx.printf("  l[%d]=%016x\n", n, mx.l[n].o)
		case 'm':
			tmp = mx.memRead(readHex(buffer[1:]))
			mx.printf("  m[%s]=%016x\n", cstr(buffer[1:]), tmp)

//line mmmix.w:825
		case 'g':
			if v, ok := sscanfD(buffer[1:]); !ok || v < 0 || v >= 256 {
				whatSay = true
				break
			} else {
				n = int(v)
			}
			if n == rO || n == rS {
				if mx.hot == mx.cool { // pipeline empty
					mx.g[rO].o, mx.g[rS].o = mx.coolO<<3, mx.coolS<<3
				} else {
					mx.g[rO].o, mx.g[rS].o = mx.hot.curO<<3, mx.hot.curS<<3
				}
			}
			mx.printf("  g[%d]=%016x\n", n, mx.g[n].o)

//line mmmix.w:842
		case 'I':
			if buffer[1] == 'T' {
				mx.printCache(mx.ITcache, false)
			} else {
				mx.printCache(mx.Icache, false)
			}
		case 'D':
			if buffer[1] == 'T' {
				mx.printCache(mx.DTcache, buffer[1] == '*')
			} else {
				mx.printCache(mx.Dcache, buffer[1] == '*')
			}
		case 'S':
			mx.printCache(mx.Scache, buffer[1] == '*')
		case 'p':
			mx.printPipe()
			mx.printLocks()
		case 's':
			mx.printStats()
		case 'i':
			if v, ok := sscanfD(buffer[1:]); ok {
				mx.g[rI].o = Octa(int64(v))
			}

//line mmmix.w:867
		case 'f':
			tmp = readHex(buffer[1:])
			if newTail := mx.prevFetch(mx.tail); newTail == mx.head {
				mx.printf("Sorry, the fetch buffer is full!\n")
			} else {
				mx.tail.loc = mx.instPtr.o
				mx.tail.inst = Tetra(tmp)
				mx.tail.interrupt = 0
				mx.tail.noted = false
				mx.tail = newTail
			}

//line mmmix.w:883
		case 'd':
			if Tetra(mx.ticks) != 0 {
				mx.printf("Sorry: I disable ITcache and DTcache only at the beginning!\n")
			} else {
				mx.ITcache.set[0][0].tag = 0
				mx.ITcache.set[0][0].data[0] = 7
				mx.DTcache.set[0][0].tag = 0
				mx.DTcache.set[0][0].data[0] = 7
				mx.g[rK].o = negOne
				mx.pageBad = false
				mx.pageMask = negOne
				mx.instPtr.p = &mx.unknownSpec
			}

//line mmmix.w:903
		case '!':
			for j := 0; j < mx.funitCount; j++ {
				mx.printf("unit %s %d\n", mx.funit[j].name, mx.funit[j].k)
			}

//line mmmix.w:675
		default:
			whatSay = true
		}
		if whatSay {
			mx.printf("Eh? Sorry, I don't understand. (Type h for help)\n")
		}
	}

//line mmmix.w:56
	mx.printf("Simulation ended at time %d.\n", int32(Tetra(mx.ticks)))
	mx.printStats()
	return 0
}

func main() {
	os.Exit(mmmix(os.Args, os.Stdin, os.Stdout, os.Stderr))
}
