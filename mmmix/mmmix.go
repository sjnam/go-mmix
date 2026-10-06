//line mmmix.w:33
package main

import (
	"bufio"
	"bytes"
	"io"
	"os"
	"strconv"

	"github.com/sjnam/go-mmix/mmixio"
)

//line mmmix.w:885
type cfile struct {
	f   *os.File      // 읽는 파일; 표준 입력이면 |nil|
	r   *bufio.Reader // 읽기 버퍼
	pos int64         // |ftell|이 돌려줄 위치
	eof bool          // 파일 끝 표시(|feof|)
}

//line mmmix.w:165
const bufSize = 100

//line mmmix.w:428
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
	lopPre   = 0x9  // 서문 lopcode
	lopPost  = 0xa  // 후기 lopcode
	lopStab  = 0xb  // 기호표 lopcode
	lopEnd   = 0xc  // 모든 것을 끝내는 lopcode
)

//line mmmix.w:299
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

//line mmmix.w:449
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

//line mmmix.w:481
func (mx *machine) kernelLoad(loc Octa, t Tetra, xor bool) {
	if loc&signBit == 0 || loc-signBit >= hioBase {
		mx.errprintf("Panic: Kernel location %016x isn't in negative memory!\n", loc)

		panic(exitSignal(-5))
	}
	a := (loc - signBit) &^ 7
	s := 32 * (^loc >> 2 & 1) // 윗 테트라면 32
	o := mx.memRead(a)
	if xor {
		o ^= Octa(t) << s
	} else {
		o = o&^(0xffffffff<<s) | Octa(t)<<s
	}
	mx.memWrite(a, o)
}

//line mmmix.w:732
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

//line mmmix.w:893
func openCfile(name string) *cfile {
	f, err := os.Open(name)
	if err != nil {
		return nil
	}
	return &cfile{f: f, r: bufio.NewReader(f)}
}

//line mmmix.w:906
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

//line mmmix.w:935
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

//line mmmix.w:960
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
	v, _ := strconv.ParseInt(string(s[:j]), 10, 64) // 넘치면 끝값에서 멈춘다
	return int32(v), true
}

//line mmmix.w:992
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

//line mmmix.w:1018
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

//line mmmix.w:1008
	if nDigits {
		return 0, s, false
	}
	if c := buf[len(buf)-1]; c == 'x' || c == 'X' {
		buf = buf[:len(buf)-1]
	}

//line mmmix.w:1042
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

//line mmmix.w:1015
}

//line mmmix.w:49
func mmmix(args []string, stdin io.Reader, stdout, stderr io.Writer) (code int) {
	mx := &machine{

//line mmmix.w:78
		out:    bufio.NewWriter(stdout),
		stderr: stderr,
		stdin:  &cfile{r: bufio.NewReader(stdin)},

//line mmmix.w:50
	}
	defer func() {

//line mmmix.w:87
		mx.out.Flush()
		if mx.io != nil {
			mx.io.FlushAll()
		}
		if mx.hio != nil {
			mx.hio.io.FlushAll() // 보충: 커널의 장치가 연 파일들
		}
		if r := recover(); r != nil {
			e, ok := r.(exitSignal)
			if !ok {
				panic(r)
			}
			code = int(e)
		}

//line mmmix.w:53
	}()

//line mmmix.w:168
	var (
		n, m           int                    // 잠시 쓰는 정수
		curLoc         Octa                   // 현재 위치
		curDat         Octa                   // 현재 데이터
		newChunk       bool                   // 새 덩이를 찾아야 하는가?
		buffer         [bufSize]byte          // 입력 줄
		progFile       *cfile                 // 프로그램 파일
		silent         bool                   // \.{-s}를 주었는가?
		badAddress     bool                   // 현재 위치를 쓸 수 없는가?
		bp             Octa          = negOne // 멈춤점
		tmp            Octa                   // 잠시 관심을 두는 옥타바이트
		kernelFileName string                 // 보충: \.{-k}로 준 커널 목적 파일
	)

//line mmmix.w:55

//line mmmix.w:120
	argc := len(args)
	for n = 1; n < len(args) && len(args[n]) > 0 && args[n][0] == '-'; n++ {
		if len(args[n]) > 1 && args[n][1] == 's' {
			silent = true
		} else if len(args[n]) > 2 && args[n][1] == 'k' {
			kernelFileName = args[n][2:]
		} else {
			argc = 0 // 모르는 선택 사항
		}
	}
	if argc != n+2 {
		mx.errprintf("Usage: %s [-s] configfile progfile\n", args[0])

		panic(exitSignal(-3))
	}
	configFileName := args[argc-2]
	progFileName := args[argc-1]

//line mmmix.w:56
	mx.MMIXConfig(configFileName)
	mx.MMIXInit()
	mx.io = mmixio.New(mx, mx.out, stderr)

//line mmmix.w:139
	if len(progFileName) > 4 && progFileName[len(progFileName)-4:] == ".mmb" {

//line mmmix.w:268
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
				curLoc = curLoc>>61<<32 | curLoc&0xffffffff // 세그먼트마다 하찮은 사상 함수를 적용한다
			}

//line mmmix.w:322
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

//line mmmix.w:246
				if newChunk {
					mx.memWrite(curLoc, curDat)
				} else {
					mx.memHash[mx.lastH].chunk[(Tetra(curLoc)&0xffff)>>3] = curDat
				}
				curLoc = curLoc&^0xffffffff | Octa(Tetra(curLoc)+8)

//line mmmix.w:337
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

//line mmmix.w:287
		}

//line mmmix.w:355
		if curLoc>>32 != 3 {
			mx.errprintf("Panic: MMIX binary file didn't set up the stack!\n")

			panic(exitSignal(-6))
		}
		mx.instPtr.o = mx.memRead(curLoc - 8*14) // \.{Main}
		mx.instPtr.p = nil
		curLoc = 0x60000000<<32 | curLoc&0xffffffff
		mx.g[255].o = curLoc - 8 // \.{UNSAVE}할 곳
		curDat = curDat&^0xffffffff | 0xf0
		if mx.memRead(curDat)>>32 != 0 {
			mx.instPtr.o = curDat // |0xf0|이 0이 아니면 거기서 시작한다
		}
		mx.head.inst = UNSAVE<<24 + 255 // 만들어 낸 명령을 미리 가져온다
		mx.tail = mx.prevFetch(mx.tail)
		mx.head.loc = mx.instPtr.o - 4 // \.{UNSAVE}가 가로막힐 경우에 대비한다
		mx.g[rT].o = 0x80000005<<32 | mx.g[rT].o&0xffffffff
		mx.g[rTT].o = 0x80000006<<32 | mx.g[rTT].o&0xffffffff

//line mmmix.w:382
		curDat = Octa(RESUME<<24+1) << 32
		curLoc = 5 << 32
		mx.memWrite(curLoc, curDat) // 원시적인 트랩 처리기
		curDat = Octa(NEGI<<24+255<<16+1)<<32 | curDat>>32
		curLoc = 6<<32 | 8
		mx.memWrite(curLoc, curDat) // 원시적인 동적 트랩 처리기
		curDat = Octa(GET<<24+rQ)<<32 | Octa(PUTI<<24+rQ<<16)
		curLoc = 6 << 32
		mx.memWrite(curLoc, curDat) // 원시적인 동적 트랩 처리기의 나머지

//line mmmix.w:393
		curDat = 7                  // \.{rwx} 허가를 가진 PTE를 만든다
		curLoc = 4 << 32            // 뼈대 페이지 테이블의 처음
		mx.memWrite(curLoc, curDat) // 텍스트 세그먼트의 PTE
		mx.ITcache.set[0][0].tag = 0
		mx.ITcache.set[0][0].data[0] = curDat // IT 캐시에 마중물을 붓는다
		curDat = 1<<32 | 6                    // 읽기와 쓰기 허가만 가진 PTE
		curLoc = 4<<32 | 3<<13
		mx.memWrite(curLoc, curDat) // 데이터 세그먼트의 PTE
		curDat = 2<<32 | 6
		curLoc = 4<<32 | 6<<13
		mx.memWrite(curLoc, curDat) // 풀 세그먼트의 PTE
		curDat = 3<<32 | 6
		curLoc = 4<<32 | 9<<13
		mx.memWrite(curLoc, curDat) // 스택 세그먼트의 PTE

//line mmmix.w:375
		mx.g[rK].o = negOne // 인터럽트를 모두 허용한다
		mx.g[rV].o = 0x369c2004<<32 | mx.g[rV].o&0xffffffff
		mx.pageBad, mx.pageR, mx.pageS = false, 4<<(32-13), 32
		mx.pageMask = mx.pageMask&^0xffffffff | 0xffffffff
		mx.pageB[1], mx.pageB[2], mx.pageB[3], mx.pageB[4] = 3, 6, 9, 12

//line mmmix.w:141
	} else {

//line mmmix.w:186
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

//line mmmix.w:216
				if h, l, ok := sscanfX(cstr(buffer[:]), 4, 8); !ok {
					mx.errprintf("Panic: Improper hexadecimal file location: `%s'!\n", cstr(buffer[:]))

					panic(exitSignal(-3))
				} else {
					curLoc = Octa(h)<<32 | Octa(l)
				}
				newChunk = true

//line mmmix.w:204
			} else if buffer[0] == ' ' {

//line mmmix.w:228
				if h, l, ok := sscanfX(cstr(buffer[1:]), 8, 8); !ok {
					mx.errprintf("Panic: Improper hexadecimal file data: `%s'!\n", cstr(buffer[:]))

					panic(exitSignal(-3))
				} else {
					curDat = Octa(h)<<32 | Octa(l)
				}

//line mmmix.w:246
				if newChunk {
					mx.memWrite(curLoc, curDat)
				} else {
					mx.memHash[mx.lastH].chunk[(Tetra(curLoc)&0xffff)>>3] = curDat
				}
				curLoc = curLoc&^0xffffffff | Octa(Tetra(curLoc)+8)

//line mmmix.w:236
				if Tetra(curLoc)&0xfff8 != 0 {
					newChunk = false
				} else {
					newChunk = true
					if Tetra(curLoc)&0xffff0000 == 0 {
						curLoc += 1 << 32
					}
				}

//line mmmix.w:206
			} else {
				mx.errprintf("Panic: Improper hexadecimal file line: `%s'!\n", cstr(buffer[:]))

				panic(exitSignal(-3))
			}
		}

//line mmmix.w:143
	}
	progFile.f.Close()

//line mmmix.w:60

//line mmmix.w:417
	if kernelFileName != "" {
		mx.hio = &hio{mx: mx}
		mx.hio.io = mmixio.New(mx.hio, mx.out, stderr)

//line mmmix.w:503
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
			mx.kernelTet(kf, kernelFileName) // 파일을 만든 시각
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

//line mmmix.w:539
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
						mx.kernelTet(kf, kernelFileName) // 파일 이름
					}
					continue items
				case lopLine:
					continue items
				case lopPost, lopStab, lopEnd:
					break items

//line mmmix.w:564
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

//line mmmix.w:529
				default:
					mx.kernelErr(kernelFileName)
				}
			}
			mx.kernelLoad(curLoc, t, false)
			curLoc = (curLoc + 4) &^ 3
		}
		kf.f.Close()

//line mmmix.w:421
	}

//line mmmix.w:61
	if silent {
		return mx.MMIXSilent()
	}

//line mmmix.w:635
interact:
	for {
		mx.printf("mmmix> ")

		mx.out.Flush()
		mx.stdin.fgets(buffer[:], bufSize)
		whatSay := false
		switch buffer[0] {
		case 'q', 'x':
			break interact

//line mmmix.w:655
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

//line mmmix.w:670
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

//line mmmix.w:689
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

//line mmmix.w:718
			if mx.instPtr.o&signBit != 0 {
				mx.g[rK].o &^= 1 << 32 // |pBit|의 인터럽트를 끈다
			}
			mx.instPtr.p = nil

//line mmmix.w:706
		case 'k':
			mx.instPtr.o ^= 0x80000000 << 32 // 커널 방식으로 가는 지름길
			if Tetra(mx.ticks) == 0 && mx.head != nil {
				mx.head.loc ^= 0x80000000 << 32 // \.{UNSAVE}의 위치를 고친다
			}

//line mmmix.w:718
			if mx.instPtr.o&signBit != 0 {
				mx.g[rK].o &^= 1 << 32 // |pBit|의 인터럽트를 끈다
			}
			mx.instPtr.p = nil

//line mmmix.w:712
		case 'b':
			bp = readHex(buffer[1:])
		case 'v':
			mx.verbose = int(Tetra(readHex(buffer[1:])))

//line mmmix.w:765
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

//line mmmix.w:796
		case 'g':
			if v, ok := sscanfD(buffer[1:]); !ok || v < 0 || v >= 256 {
				whatSay = true
				break
			} else {
				n = int(v)
			}
			if n == rO || n == rS {
				if mx.hot == mx.cool { // 파이프라인이 비어 있다
					mx.g[rO].o, mx.g[rS].o = mx.coolO<<3, mx.coolS<<3
				} else {
					mx.g[rO].o, mx.g[rS].o = mx.hot.curO<<3, mx.hot.curS<<3
				}
			}
			mx.printf("  g[%d]=%016x\n", n, mx.g[n].o)

//line mmmix.w:813
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

//line mmmix.w:838
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

//line mmmix.w:854
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

//line mmmix.w:874
		case '!':
			for j := 0; j < mx.funitCount; j++ {
				mx.printf("unit %s %d\n", mx.funit[j].name, mx.funit[j].k)
			}

//line mmmix.w:646
		default:
			whatSay = true
		}
		if whatSay {
			mx.printf("Eh? Sorry, I don't understand. (Type h for help)\n")
		}
	}

//line mmmix.w:65
	mx.printf("Simulation ended at time %d.\n", int32(Tetra(mx.ticks)))
	mx.printStats()
	return 0
}

func main() {
	os.Exit(mmmix(os.Args, os.Stdin, os.Stdout, os.Stderr))
}
