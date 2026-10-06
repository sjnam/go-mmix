% 이 파일은 MMIXware의 mmmix.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

@s io.Reader int
@s io.Writer int
@s bufio.Reader int
@s os.File int
@s bytes.Buffer int
@s testing.T int
@s Octa int
@s Tetra int
@s machine int
@s exitSignal int

\input kotexgweb
\def\title{MMMIX}
\def\NNIX{\hbox{\mc NNIX}}

@* 들어가며. 이 \.{GWEB} 프로그램은 \MMIX\ 컴퓨터를 여러 가지 설정의 고성능 파이프라인으로
구현하면 어떻게 될지 흉내 낸다. 다중 처리와 메모리 사상 입출력의 저수준 세부를 빼면 \MMIX\
아키텍처의 복잡한 사정을 모두 다룬다.

이 프로그램 모듈은 \MMIX\ 메타 시뮬레이터의 주 루틴을 담고 있는데, 주로 관리하는 일을 한다.
실제 일은 이 모듈이 무엇을 할지 일러 준 다른 모듈들이 한다.

보충: 원본의 |main| 함수가 하던 일을 여기서는 함수 |mmmix|가 한다. \.{mmixsim}에서처럼
명령줄 인자, 표준 입력, 표준 출력, 표준 오류를 매개변수로 받고 종료 코드를 돌려준다. 원본의
|exit|는 |exitSignal|을 던지는 공황이 되고, |mmmix|의 맨 바깥에서 종료 코드로 바뀐다. 원본의
전역 변수 가운데 이 모듈만 쓰는 것들은 |mmmix|의 지역 변수가 된다. \GO/ 판의 실행 파일
이름은 원본처럼 \.{mmmix}가 되도록 \.{go} \.{build} \.{./mmmix}로 만들면 된다.

@c
package main

import (
	"bufio"
	"bytes"
	"io"
	"os"
	"strconv"
	@#
	"github.com/sjnam/go-mmix/mmixio"
)

@<타입 정의@>
@<상수@>
@<함수들@>

func mmmix(args []string, stdin io.Reader, stdout, stderr io.Writer) (code int) {
	mx := &machine{@<기계의 입출력 필드@>}
	defer func() {
		@<출력을 모두 비우고, 빠져나온 공황이 있으면 종료 코드로 삼는다@>
	}()
	@<|mmmix|의 지역 변수@>
	@<명령줄을 해석한다@>
	mx.MMIXConfig(configFileName)
	mx.MMIXInit()
	mx.io = mmixio.New(mx, mx.out, stderr)
	@<프로그램을 입력한다@>
	@<커널이 있으면 싣는다@>
	if silent {
		return mx.MMIXSilent()
	}
	@<시뮬레이션을 대화하며 돌린다@>
	mx.printf("Simulation ended at time %d.\n", int32(Tetra(mx.ticks)))
	mx.printStats()
	return 0
}

func main() {
	os.Exit(mmmix(os.Args, os.Stdin, os.Stdout, os.Stderr))
}

@ 시뮬레이터 자신의 출력과 모의 프로그램의 표준 출력은 원본에서 같은 \CEE/ |stdout|을 나누어
썼다. 여기서도 버퍼 하나를 함께 쓴다. 표준 입력도 대화 명령과 모의 프로그램이 함께 읽는다.

@<기계의 입출력 필드@>=
out:    bufio.NewWriter(stdout),
stderr: stderr,
stdin:  &cfile{r: bufio.NewReader(stdin)},

@ 공황은 |exitSignal|일 때만 받는다. 다른 공황은 프로그램의 잘못이므로 다시 던진다. 원본은
끝날 때 \CEE/ 라이브러리의 |exit|가 모든 스트림의 버퍼를 비워 주었다. 여기서는 시뮬레이터 자신의
표준 출력을 비운 뒤, \.{mmixio}가 연 파일들을 |FlushAll|로 비운다.

@<출력을 모두 비우고...@>=
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

@ 사용자는 대개 메타 시뮬레이터를 \UNIX/ 비슷한 명령줄
`\.{mmmix} \.{options}~\.{configfile}~\.{progfile}'로 부른다. 여기서 \.{configfile}은 \MMIX\
구현의 특성을 적은 것이고, \.{progfile}에는 내려받아 돌릴 프로그램이 들어 있다. 설정 파일의
규칙은 \.{mmixconfig} 모듈에 있다. 프로그램 파일은 {\mc MMIX-SIM}이 덤프한 ``\MMIX\ 이진 파일''이거나,
십육진 데이터를 초보적인 형식으로 적은 ASCII 텍스트 파일이다. 이름이 확장자 `\.{.mmb}'로
끝나면 이진 파일로 여긴다.

지금 지원하는 명령줄 선택 사항은 \.{-s} 하나뿐이다. 이것을 주면 시뮬레이터는 \.{TRAP}
\.{0,Halt,0} 명령을 실행할 때까지 조용히 돌린다.

@ 언젠가는 명령줄에 다른 선택 사항이 더 들어갈지도 모른다. 지금은 경험이 더 쌓일 때까지
그런 것들은 잊고 모든 것을 단순하게 한다.

보충: 옮긴이는 선택 사항을 하나 덧붙였다. \.{-k<filename>}을 주면 프로그램을 입력한 뒤에
\NNIX\ 커널의 목적 파일을 싣는다. 이름을 선택 사항에 붙여 쓰는 것은 {\mc MMIX-SIM}의
\.{-f<filename>}을 본뜬 것이다. 사용법 메시지는 원본 그대로 둔다.

@<명령줄을...@>=
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
@.Usage: ...@>
	panic(exitSignal(-3))
}
configFileName := args[argc-2]
progFileName := args[argc-1]

@ @<프로그램을 입력한다@>=
if len(progFileName) > 4 && progFileName[len(progFileName)-4:] == ".mmb" {
	@<\MMIX\ 이진 파일을 입력한다@>
} else {
	@<초보적인 십육진 파일을 입력한다@>
}
progFile.f.Close()

@* 십육진 입력을 메모리로. 초보적인 십육진 입력 형식을 여기서 구현한다. 그러면 모의 메모리에
@^hexadecimal files@>
사실상 아무 데이터나 넣고 시뮬레이터를 돌릴 수 있다. 이 형식의 규칙은 아주 단순하다. 파일의
줄마다 (i)~십육진 숫자 12개와 쌍점으로 시작하거나, (ii)~빈칸 하나와 십육진 숫자 16개로 시작한다.
경우~(i)에서 십육진 숫자 12개는 현재 위치라고 부르는 48비트 물리 주소를 지정한다. 경우~(ii)에서
십육진 숫자 16개는 현재 위치에 저장할 옥타바이트를 지정하고, 그러면 현재 위치가 8만큼 는다.
현재 위치는 8의 배수여야 하지만, 가장 아래 세 비트는 실제로는 무시한다. 줄마다 99자보다 짧기만
하면 새 현재 위치나 새 옥타바이트의 지정 뒤에 아무 주석이나 올 수 있다. 이를테면 파일
$$\vbox{\halign{\tt#\hfil\cr
0123456789ab: SILLY EXAMPLE\cr
\ 0123456789abcdef first octabyte\cr
\ fedbca9876543210 second\cr}}$$
은 옥타바이트 \Hex{0123456789abcdef}를 메모리 위치 \Hex{0123456789a8}에 넣고
\Hex{fedcba9876543210}을 위치 \Hex{0123456789b0}에 넣는다.

보충: 원본의 전역 버퍼 |buffer|는 십육진 파일과 대화 명령이 함께 쓴다. 그래서 대화 명령을 읽는
|fgets|가 실패하면 파일의 마지막 줄이 명령으로 남는다. 여기서도 버퍼 하나를 함께 쓴다.

@<상수@>=
const bufSize = 100

@ @<|mmmix|의 지역 변수@>=
var (
	n, m       int              // 잠시 쓰는 정수
	curLoc     Octa             // 현재 위치
	curDat     Octa             // 현재 데이터
	newChunk   bool             // 새 덩이를 찾아야 하는가?
	buffer     [bufSize]byte    // 입력 줄
	progFile   *cfile           // 프로그램 파일
	silent     bool             // \.{-s}를 주었는가?
	badAddress bool             // 현재 위치를 쓸 수 없는가?
	bp         Octa = negOne    // 멈춤점
	tmp        Octa             // 잠시 관심을 두는 옥타바이트
	kernelFileName string       // 보충: \.{-k}로 준 커널 목적 파일
)

@ 보충: 원본은 첫 널 문자가 줄의 처음에 있으면 |buffer[-1]|을 읽었다. 여기서는 그런 줄을 너무
긴 줄로 다룬다.

@<초보적인 십육진 파일을...@>=
progFile = openCfile(progFileName)
if progFile == nil {
	mx.errprintf("Panic: Can't open MMIX hexadecimal file %s!\n", progFileName)
@.Can't open...@>
	panic(exitSignal(-3))
}
newChunk = true
for {
	if !progFile.fgets(buffer[:], bufSize) {
		break
	}
	if l := strlen(buffer[:]); l == 0 || buffer[l-1] != '\n' {
		mx.errprintf("Panic: Hexadecimal file line too long: `%s...'!\n", cstr(buffer[:]))
@.Hexadecimal file line...@>
		panic(exitSignal(-3))
	}
	if buffer[12] == ':' {
		@<현재 위치를 바꾼다@>
	} else if buffer[0] == ' ' {
		@<옥타바이트를 읽고 |curLoc|을 나아가게 한다@>
	} else {
		mx.errprintf("Panic: Improper hexadecimal file line: `%s'!\n", cstr(buffer[:]))
@.Improper hexadecimal...@>
		panic(exitSignal(-3))
	}
}

@ 보충: 원본은 |sscanf(buffer,"%4x%8x",...)|로 읽었다. 함수 |sscanfX|가 그것을 흉내 낸다.

@<현재 위치를...@>=
if h, l, ok := sscanfX(cstr(buffer[:]), 4, 8); !ok {
	mx.errprintf("Panic: Improper hexadecimal file location: `%s'!\n", cstr(buffer[:]))
@.Improper hexadecimal...@>
	panic(exitSignal(-3))
} else {
	curLoc = Octa(h)<<32 | Octa(l)
}
newChunk = true

@ 보충: 원본은 현재 위치의 아랫 테트라에만 8을 더한다. 윗 테트라로 올림하지 않는다.

@<옥타바이트를 읽고...@>=
if h, l, ok := sscanfX(cstr(buffer[1:]), 8, 8); !ok {
	mx.errprintf("Panic: Improper hexadecimal file data: `%s'!\n", cstr(buffer[:]))
@.Improper hexadecimal...@>
	panic(exitSignal(-3))
} else {
	curDat = Octa(h)<<32 | Octa(l)
}
@<|curDat|를 |curLoc|에 쓰고 |curLoc|을 나아가게 한다@>
if Tetra(curLoc)&0xfff8 != 0 {
	newChunk = false
} else {
	newChunk = true
	if Tetra(curLoc)&0xffff0000 == 0 {
		curLoc += 1 << 32
	}
}

@ @<|curDat|를 |curLoc|에 쓰고...@>=
if newChunk {
	mx.memWrite(curLoc, curDat)
} else {
	mx.memHash[mx.lastH].chunk[(Tetra(curLoc)&0xffff)>>3] = curDat
}
curLoc = curLoc&^0xffffffff | Octa(Tetra(curLoc)+8)

@* 이진 입력을 메모리로. 프로그램 파일을 {\mc MMIX-SIM}이 덤프했다면, 그 파일은 \MMIX\
분책(\/{\sl The Art of Computer Programming}, 제1권, 분책~1)의 연습 문제 1.4.3$'$--20에서 다룬
@^Fascicle 1@>
@^binary files@>
@^segments@>
단순한 형식을 가진다. 그런 프로그램에는 그 책의 관례대로 텍스트, 데이터, 풀, 스택 세그먼트가
있다고 가정한다. 그것을 세그먼트마다 하나씩, 물리 메모리의 $2^{32}$바이트짜리 페이지 네 개에
적재한다. 세그먼트~$i$의 페이지 0은 물리 위치 $2^{32}i$로 사상된다. 페이지 테이블은 물리 위치
$2^{32}\times4$부터 두고, 정적 트랩은 $2^{32}\times5$에서, 동적 트랩은 $2^{32}\times6$에서
시작한다. (이 관례는 단순한 시뮬레이터가 가정하는 특수 레지스터 설정
$\rm rT=\Hex{8000000500000000}$,
$\rm rTT=\Hex{8000000600000000}$,
$\rm rV=\Hex{369c200400000000}$과 맞는다.)

@<\MMIX\ 이진 파일을...@>=
progFile = openCfile(progFileName)
if progFile == nil {
	mx.errprintf("Panic: Can't open MMIX binary file %s!\n", progFileName)
@.Can't open...@>
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
	@<|curLoc|에서 시작하는 잇단 옥타바이트들을 입력한다@>
}
@<미리 짜 둔 환경을 준비한다@>

@ 루틴 |undumpOcta|는 이진 파일 |progFile|에서 여덟 바이트를 읽어 옥타바이트 |*dat|에 넣는다.
늘 그렇듯이 호스트 컴퓨터의 바이트 순서와 상관없이 큰 쪽 먼저로 읽는다.
@^big-endian versus little-endian@>
@^little-endian versus big-endian@>

보충: 원본은 전역 변수 |cur_dat|에 넣었는데, 앞의 네 바이트를 읽고 나서 윗 테트라를 먼저 바꾸었다.
여기서도 그렇게 한다.

@<함수들@>=
func (mx *machine) undumpOcta(f *cfile, name string, dat *Octa) bool {
	var t Tetra
	for k := 0; k < 8; k++ {
		c, err := f.r.ReadByte()
		if err != nil {
			if k == 0 {
				return false
			}
			mx.errprintf("Premature end of file on %s!\n", name)
@.Premature end of file...@>
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

@ @<|curLoc|에서 시작하는 잇단...@>=
for {
	if !mx.undumpOcta(progFile, progFileName, &curDat) {
		mx.errprintf("Unexpected end of file on %s!\n", progFileName)
@.Unexpected end of file...@>
		break
	}
	if curDat == 0 {
		break
	}
	if badAddress {
		mx.errprintf("Panic: Unsupported virtual address %016x!\n", curLoc)
@.Unsupported virtual address@>
		panic(exitSignal(-5))
	}
	@<|curDat|를 |curLoc|에 쓰고...@>
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

@ {\sl The Art of Computer Programming}의 단순한 프로그램들이 가정하는 원시적인 운영체제는
{\mc MMIX-SIM}에서처럼 텍스트 세그먼트, 데이터 세그먼트, 풀 세그먼트, 스택 세그먼트를 준비한다.
\.{.mmb} 파일에서 마지막으로 적재한 위치에서 \.{UNSAVE}를 하면 실행 시간 스택이 초기화된다.

보충: 원본은 여기서 옥타바이트의 테트라 하나씩을 따로 정했다. 여기서도 그대로 옮긴다.

@<미리 짜 둔 환경을...@>=
if curLoc>>32 != 3 {
	mx.errprintf("Panic: MMIX binary file didn't set up the stack!\n")
@.MMIX binary file...@>
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
@<원시적인 트랩 처리기들을 쓴다@>
@<뼈대만 있는 페이지 테이블을 쓴다@>
mx.g[rK].o = negOne // 인터럽트를 모두 허용한다
mx.g[rV].o = 0x369c2004<<32 | mx.g[rV].o&0xffffffff
mx.pageBad, mx.pageR, mx.pageS = false, 4<<(32-13), 32
mx.pageMask = mx.pageMask&^0xffffffff | 0xffffffff
mx.pageB[1], mx.pageB[2], mx.pageB[3], mx.pageB[4] = 3, 6, 9, 12

@ @<원시적인 트랩 처리기들을...@>=
curDat = Octa(RESUME<<24+1) << 32
curLoc = 5 << 32
mx.memWrite(curLoc, curDat) // 원시적인 트랩 처리기
curDat = Octa(NEGI<<24+255<<16+1)<<32 | curDat>>32
curLoc = 6<<32 | 8
mx.memWrite(curLoc, curDat) // 원시적인 동적 트랩 처리기
curDat = Octa(GET<<24+rQ)<<32 | Octa(PUTI<<24+rQ<<16)
curLoc = 6 << 32
mx.memWrite(curLoc, curDat) // 원시적인 동적 트랩 처리기의 나머지

@ @<뼈대만 있는 페이지 테이블을...@>=
curDat = 7 // \.{rwx} 허가를 가진 PTE를 만든다
curLoc = 4 << 32 // 뼈대 페이지 테이블의 처음
mx.memWrite(curLoc, curDat) // 텍스트 세그먼트의 PTE
mx.ITcache.set[0][0].tag = 0
mx.ITcache.set[0][0].data[0] = curDat // IT 캐시에 마중물을 붓는다
curDat = 1<<32 | 6 // 읽기와 쓰기 허가만 가진 PTE
curLoc = 4<<32 | 3<<13
mx.memWrite(curLoc, curDat) // 데이터 세그먼트의 PTE
curDat = 2<<32 | 6
curLoc = 4<<32 | 6<<13
mx.memWrite(curLoc, curDat) // 풀 세그먼트의 PTE
curDat = 3<<32 | 6
curLoc = 4<<32 | 9<<13
mx.memWrite(curLoc, curDat) // 스택 세그먼트의 PTE

@* 커널 싣기. 보충: 이 장은 옮긴이가 덧붙인 것이다. 크누스가 만들지 않은 \NNIX\ 대신에 쓸
작은 커널을 저장소의 \.{nnix/nnix.mms}에 두었다. 이 커널은 rT와 rTT에 진짜 처리기를 두고,
요구 페이징을 하며, \.{mmixmem.w}에 덧붙인 호스트 입출력 장치로 입출력을 한다. 그러면 마법 같은 입출력은 일어나지
않는다. 마법은 rT 자리에서 \.{RESUME}~\.1을 배정할 때만 일어나기 때문이다.

커널은 미리 짜 둔 환경을 준비한 {\it 뒤에\/} 싣는다. 그래서 위치 $2^{32}\times5$의 원시적인 트랩
처리기 자리는 커널의 코드가 차지한다. 장치는 커널을 실을 때만 만든다.

이진 파일을 실었으면 커널이 사용자 프로그램보다 먼저 돈다. 커널은 위치 |kernelBoot|에서 시작해서
트랩 주소와 페이지 테이블을 마련한 뒤, \.{RESUME}~\.1로 사용자 프로그램에 넘어간다. 그래서 사용자
프로그램이 시작할 곳을 rWW에 넣고, rXX를 음수로 정해 \.{RESUME}이 명령을 끼워 넣지 않게 한다. 미리
짜 둔 환경이 가져오기 버퍼에 넣어 둔 \.{UNSAVE}는 그대로 커널보다 먼저 실행되어 사용자의 레지스터를
되살린다. 대화 명령 \.{k}에서처럼 그 위치도 커널 쪽으로 옮긴다.

@<커널이 있으면...@>=
if kernelFileName != "" {
	mx.hio = &hio{mx: mx}
	mx.hio.io = mmixio.New(mx.hio, mx.out, stderr)
	@<커널 목적 파일을 싣는다@>
	if len(progFileName) > 4 && progFileName[len(progFileName)-4:] == ".mmb" {
		mx.g[rWW].o = mx.instPtr.o
		mx.g[rXX].o = signBit
		mx.instPtr.o = kernelBoot
		mx.head.loc = kernelBoot - 4
		@<새 명령 포인터를 정한다@>
	}
}

@ @<상수@>=
const kernelBoot = 0x8000000500000000 // 커널이 시작하는 곳

@ 목적 파일 형식 \.{mmo}는 {\mc MMIXAL}의 프로그램에 나온다. 여기서는 \.{mmixsim}의 적재기를 줄여
쓴다. 기호표는 싣지 않고, 후기에 이르면 멈춘다. 커널에는 특수 데이터(\.{lop\_spec})를 쓰지 않으므로
그것은 받지 않는다.

@<상수@>=
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

@ 함수 |kernelTet|는 큰 쪽 먼저로 테트라바이트 하나를 읽는다. 파일이 잘렸으면 끝낸다.
함수 |kernelAddress|는 \.{lop\_loc}이나 \.{lop\_fixo}가 가리키는 주소를 읽는다. 그 lopcode의
Z~바이트가 2이면 Y~바이트가 윗 테트라의 맨 윗 바이트가 되고, 그다음 테트라바이트가 거기에 더해진다.

@<함수들@>=
func (mx *machine) kernelTet(f *cfile, name string) Tetra {
	var b [4]byte
	if _, err := io.ReadFull(f.r, b[:]); err != nil {
		mx.kernelErr(name)
	}
	return Tetra(b[0])<<24 | Tetra(b[1])<<16 | Tetra(b[2])<<8 | Tetra(b[3])
}
@#
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
@#
func (mx *machine) kernelErr(name string) {
	mx.errprintf("Panic: Bad kernel object file %s!\n", name)
@.Bad kernel object file@>
	panic(exitSignal(-4))
}

@ 커널의 위치는 음수 가상 주소여야 하고, 부호 비트를 지운 물리 주소는 입출력 공간보다 아래여야
한다. 보통의 테트라는 그 자리에 덮어쓴다. 미리 짜 둔 환경이 써 둔 원시 처리기를 지우기 위해서다.
고치기는 \.{mmixsim}의 |mmoLoad|처럼 배타적 논리합으로 싣는다.

@<함수들@>=
func (mx *machine) kernelLoad(loc Octa, t Tetra, xor bool) {
	if loc&signBit == 0 || loc-signBit >= hioBase {
		mx.errprintf("Panic: Kernel location %016x isn't in negative memory!\n", loc)
@.Kernel location...@>
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

@ 보충: \.{mmixsim}처럼 lopcode를 해석하는 루프에 이름표를 붙인다. |continue items|는 다음 항목으로
가고, |break items|는 후기에서 멈춘다. \.{lop\_quote}는 테트라바이트 하나를 더 읽어 보통의 경우로
넘어간다.

@<커널 목적 파일을...@>=
kf := openCfile(kernelFileName)
if kf == nil {
	mx.errprintf("Panic: Can't open kernel object file %s!\n", kernelFileName)
@.Can't open kernel...@>
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
		@<커널을 실을 때 lopcode의 경우들@>
		default:
			mx.kernelErr(kernelFileName)
		}
	}
	mx.kernelLoad(curLoc, t, false)
	curLoc = (curLoc + 4) &^ 3
}
kf.f.Close()

@ @<커널을 실을 때...@>=
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

@ 상대 주소 고치기는 \.{mmixsim}과 같다. \.{lop\_fixr}의 |delta|는 \Hex{10000}보다 작다.
\.{lop\_fixrx}의 |delta|가 \Hex{1000000} 이상이면 뒤쪽을 가리키는 $j$비트 차이다.

@<커널을 실을 때...@>=
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

@* 대화. 이 시뮬레이터는 명령을 달라고 할 때 다음과 같은 짧은 명령들을 알아듣는다.
@.mmmix>@>

\bull\<positive integer>: 이만큼의 클럭 사이클 동안 돌린다.

\bull\.{@@}\<hexadecimal integer>: 명령 포인터를 이 가상 주소로 정한다. 잇단 명령들을 여기서
가져온다.

\bull\.{k}: 명령 포인터의 부호 비트를 뒤집는다.

\bull\.{b}\<hexadecimal integer>: 멈춤점을 이 가상 주소로 정한다. 멈춤점 주소의 명령이 가져오기
버퍼에 들어오면 시뮬레이션이 멈춘다.

\bull\.v\<hexadecimal integer>: 바라는 진단 출력의 수준을 정한다. 십육진 정수의 비트마다
시뮬레이터가 돌 때 어떤 출력을 켠다. 비트 \Hex1은 명령을 발행하거나 발행 취소하거나 확정할 때
보인다. \Hex2는 사이클마다 파이프라인과 잠금을 보인다. \Hex4는 코루틴이 활성화될 때마다, \Hex8은
코루틴을 스케줄할 때마다 보인다. \Hex{10}은 메모리의 초기화하지 않은 덩이에서 읽을 때 알린다.
\Hex{20}은 $2^{48}$ 이상의 주소에서 읽을 때 온라인 입력을 요청한다. \Hex{40}은 $2^{48}$ 이상의
메모리 주소로 가는 입출력을 모두 알린다. \Hex{80}은 분기 예측의 자세한 사정을 보인다. \Hex{100}은
태그가 무효인 블록까지 캐시의 내용 전체를 보인다.

\bull\.-\<integer>: 이만큼의 명령을 발행 취소한다.

\bull\.l\<integer>나 \.g\<integer>: 지역 레지스터나 전역 레지스터의 현재 ``뜨거운'' 내용을
보인다.

\bull\.m\<hexadecimal integer>: 물리 메모리 주소의 현재 내용을 보인다. (이 값은 최신이 아닐 수도
있다. 더 새 값이 쓰기 버퍼나 캐시에 있을 수 있다.)

\bull\.f\<hexadecimal integer>: 테트라바이트 하나를 가져오기 버퍼에 넣는다. (조심해서 쓸 것!)

\bull\.i\<integer>: 구간 계수기 rI를 주어진 값으로 정한다. 그러면 지정한 사이클 수 뒤에
인터럽트가 일어난다.

\bull\.{IT}, \.{DT}, \.I, \.D, \.S: 캐시의 현재 내용을 보인다.

\bull\.{D*}나 \.{S*}: 캐시의 더러운 블록들을 보인다.

\bull\.p: 파이프라인의 현재 내용을 보인다.

\bull\.s: 분기 예측과 명령 발행 속도의 현재 통계를 보인다.

\bull\.h: 도움말(대화에서 할 수 있는 것들을 보인다).

\bull\.q: 끝낸다.

보충: 원본은 알아듣지 못한 명령에서 이름표 |what_say|로 뛰었다. 여기서는 불 변수 |whatSay|를
켜고 |switch| 뒤에서 그 말을 찍는다. 원본은 명령을 읽는 |fgets|가 실패해도 따지지 않으므로, 입력이
끝나면 마지막 명령을 끝없이 되풀이한다. 여기서도 그렇다.

@<시뮬레이션을 대화하며...@>=
interact:
for {
	mx.printf("mmmix> ")
@.mmmix>@>
	mx.out.Flush()
	mx.stdin.fgets(buffer[:], bufSize)
	whatSay := false
	switch buffer[0] {
	case 'q', 'x':
		break interact
	@<대화의 경우들@>
	default:
		whatSay = true
	}
	if whatSay {
		mx.printf("Eh? Sorry, I don't understand. (Type h for help)\n")
	}
}

@ @<대화의 경우들@>=
case 'h', '?':
	mx.printf("The interactive commands are as follows:\n")
	mx.printf(" <n> to run for n cycles\n")
	mx.printf(" @@<x> to take next instruction from location x\n")
	mx.printf(" k    to change the sign bit of the instruction location\n")
	mx.printf(" b<x> to pause when location x is fetched\n")
	mx.printf(" v<x> to print specified diagnostics when running;\n")
	mx.printf("    x=1[insts enter/leave pipe]+2[whole pipeline each cycle]+\n")
	mx.printf("      4[coroutine activations]+8[coroutine scheduling]+\n")
	mx.printf("      10[uninitialized read]+20[online I/O read]+\n")
	mx.printf("      40[I/O read/write]+80[branch prediction details]+\n")
	mx.printf("      100[invalid cache blocks displayed too]\n")
	@<도움말의 나머지를 찍는다@>

@ @<도움말의 나머지...@>=
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

@ 보충: 원본은 \.{k}의 경우에서 \.{@@}의 경우 안에 있는 이름표 |new_inst_ptr|로 뛰었다. 여기서는
그 뒷부분을 절로 만들어 두 곳에서 쓴다. 원본의 |sscanf(buffer,"%d",&n)|은 함수 |sscanfD|가
흉내 낸다.

@<대화의 경우들@>=
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
case '@@':
	mx.instPtr.o = readHex(buffer[1:])
	@<새 명령 포인터를 정한다@>
case 'k':
	mx.instPtr.o ^= 0x80000000 << 32 // 커널 방식으로 가는 지름길
	if Tetra(mx.ticks) == 0 && mx.head != nil {
		mx.head.loc ^= 0x80000000 << 32 // \.{UNSAVE}의 위치를 고친다
	}
	@<새 명령 포인터를...@>
case 'b':
	bp = readHex(buffer[1:])
case 'v':
	mx.verbose = int(Tetra(readHex(buffer[1:])))

@ @<새 명령 포인터를...@>=
if mx.instPtr.o&signBit != 0 {
	mx.g[rK].o &^= 1 << 32 // |pBit|의 인터럽트를 끈다
}
mx.instPtr.p = nil

@ 다음은 버퍼에서 십육진 표기의 옥타바이트를 읽는 간단한 프로그램이다. 입력 뒤에 널 문자를 넣어서
버퍼를 바꾼다.
@^radix conversion@>

보충: 원본은 |int|를 32비트 이상 옮겼다(정의되지 않은 동작이다). 원본을 시험한 컴퓨터에서는 옮기는
양을 32로 나눈 나머지만큼 옮긴다. 그래서 숫자가 16개를 넘으면 윗 테트라에 겹쳐 더해진다. 여기서도
그렇게 한다. 버퍼 끝은 널 문자처럼 다룬다.

@<함수들@>=
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

@ 보충: 원본의 |cool<=hot|은 재정렬 버퍼 안의 위치 비교이므로 |idx|를 견준다.

@<대화의 경우들@>=
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

@ 레지스터 스택 포인터 rO와 rS는 |g| 배열에서 최신으로 유지되지 않는다. 그래서 파이프라인을
살펴서 그 값들을 알아내야 한다.

보충: 원본의 함수 |sl3|은 옥타바이트를 세 비트 왼쪽으로 옮긴다. \GO/에서는 연산자 |<<|다.

@<대화의 경우들@>=
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

@ @<대화의 경우들@>=
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

@ @<대화의 경우들@>=
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

@ 여기에 숨은 경우가 하나 있다. 크누스가 디버깅할 때 쓰려고 둔 것이다. 모든 것을 0으로 사상해서
변환 캐시들을 사실상 끈다.

@<대화의 경우들@>=
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

@ 그리고 또 하나. 크누스가 임시변통할 때 쓰려고 둔 것이다. 지금은 기능 장치의 이름들만
나열한다.

그러나 시연할 때는 다른 것을 여기에 넣기로 할지도 모른다고 크누스는 말한다.

@<대화의 경우들@>=
case '!':
	for j := 0; j < mx.funitCount; j++ {
		mx.printf("unit %s %d\n", mx.funit[j].name, mx.funit[j].k)
	}

@* \CEE/ 라이브러리 흉내 내기. 이 장은 옮긴이가 덧붙인 것이다. \.{mmixsim}에서처럼, 원본이
\CEE/의 |fgets|와 |sscanf|에 기대는 동작을 흉내 낸다. 함수 |fgets|는 읽은 바이트와 끝의 널 문자만
버퍼에 쓰고 나머지는 그대로 둔다. 파일 끝 표시는 한 번 켜지면 꺼지지 않는다(``끈끈한'' EOF).
원본을 시험한 macOS의 라이브러리가 그렇다.

@<타입 정의@>=
type cfile struct {
	f   *os.File      // 읽는 파일; 표준 입력이면 |nil|
	r   *bufio.Reader // 읽기 버퍼
	pos int64         // |ftell|이 돌려줄 위치
	eof bool          // 파일 끝 표시(|feof|)
}

@ @<함수들@>=
func openCfile(name string) *cfile {
	f, err := os.Open(name)
	if err != nil {
		return nil
	}
	return &cfile{f: f, r: bufio.NewReader(f)}
}

@ \CEE/의 |fgets(buf,n,fp)|은 바이트를 |n-1|개까지 읽되 줄 바꿈 문자를 읽으면 멈추고, 읽은 것
뒤에 널 문자를 둔다. 아무것도 읽지 못하고 파일 끝이나 오류를 만나면 실패한다. 읽기 오류도
파일 끝처럼 다룬다.

@<함수들@>=
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

@ \CEE/ 문자열 흉내: |strlen|은 첫 널 문자의 색인이고, |cstr|은 첫 널 문자 앞까지의 바이트들이다.
문자 분류는 \CEE/ 로캘의 것이다.

@<함수들@>=
func strlen(b []byte) int {
	if n := bytes.IndexByte(b, 0); n >= 0 {
		return n
	}
	return len(b)
}
@#
func cstr(b []byte) []byte { return b[:strlen(b)] }
@#
func isdigit(c byte) bool { return '0' <= c && c <= '9' }
@#
func isxdigit(c byte) bool {
	return isdigit(c) || 'a' <= c && c <= 'f' || 'A' <= c && c <= 'F'
}
@#
func isspace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}

@ 함수 호출 |sscanf(s,"%d",&n)|은 앞의 빈칸을 건너뛰고, 부호를 하나 받고, 숫자들을 읽는다. 숫자가
없으면 짝이 맞지 않으므로 |sscanfD|는 거짓을 함께 돌려준다. 원본을 시험한 macOS의 라이브러리는
숫자들을 |strtoimax|로 바꾸는데, 범위를 넘으면 가장 큰 값이나 가장 작은 값에서 멈춘다. 그 값을
|int|에 넣으면 아랫 32비트만 남는다. 또 빈칸 뒤로는 512자까지만 읽는다.

@<함수들@>=
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

@ 함수 호출 |sscanf(s,"%4x%8x",&h,&l)|은 너비가 정해진 십육진 변환 둘을 한다. 변환마다 앞의
빈칸을 건너뛰고(빈칸은 너비에 세지 않는다), 너비만큼의 문자까지 부호 하나와 접두어 \.{0x}와
십육진 숫자들을 받는다. 함수 |sscanfX|는 두 변환이 모두 맞았는지를 함께 돌려준다. 원본을 시험한
macOS의 라이브러리를 따라, 접두어의 \.x는 첫 숫자 \.0 바로 뒤에서만 받고, \.x로 끝나면 그 \.x는
돌려놓는다. 값은 |strtoumax|로 바꾸어 음수 부호가 있으면 부호를 바꾸고, 아랫 32비트만 남긴다.

@<함수들@>=
func sscanfX(s []byte, w1, w2 int) (Tetra, Tetra, bool) {
	h, s, ok := scanHexField(s, w1)
	if !ok {
		return 0, 0, false
	}
	l, _, ok := scanHexField(s, w2)
	return h, l, ok
}
@#
func scanHexField(s []byte, width int) (Tetra, []byte, bool) {
	for len(s) > 0 && isspace(s[0]) {
		s = s[1:]
	}
	var buf []byte
	nDigits := true
	@<너비만큼 부호와 접두어와 십육진 숫자를 |buf|에 모은다@>
	if nDigits {
		return 0, s, false
	}
	if c := buf[len(buf)-1]; c == 'x' || c == 'X' {
		buf = buf[:len(buf)-1]
	}
	@<|buf|를 |strtoumax|처럼 바꾼다@>
}

@ @<너비만큼 부호와...@>=
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

@ @<|buf|를 |strtoumax|처럼...@>=
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

@* 시험. 이 장은 옮긴이가 덧붙인 것이다. 크누스의 꾸러미에는 메타 시뮬레이터를 위한 설정 파일
일곱 개(\.{plain}, \.{test}, \.{test1}, \.{test2}, \.{primes}, \.{primesx}, \.{deluxe})와 십육진
프로그램 파일 다섯 개(\.{test}, \.{test1}, \.{test2}, \.{primes}, \.{halves})가 들어 있지만, 기대하는
출력은 없다. 그래서 옮긴이는 크누스의 \CEE/ 원본을 크누스의 \.{Makefile}과 같은 선택 사항
(\.{-g} \.{-fPIE})으로 빌드해서 기준으로 삼았다. 두 구현에 같은 대화 명령을 주고 출력을 견주었다.

그 결과를 모두 옮겨 적을 수는 없으므로, 시험은 출력의 SHA-256 요약값 앞 16자리를 견준다. 요약값은
\CEE/ 원본의 출력에서 얻었다. 명령 \.{v1ff}는 사이클마다 코루틴의 활동, 스케줄, 파이프라인, 잠금을
모두 찍으므로, 이 시험들은 수만 줄의 추적 출력을 한 줄도 틀리지 않고 재현해야 통과한다.

@(mmmix_test.go@>=
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

@ 대화 명령은 두 가지다. 첫째는 명령 포인터를 \Hex{8000000000010000}에 두고 모든 진단 출력을 켠
채 2000사이클을 돌린 뒤 파이프라인과 통계를 찍는다. 둘째는 100000사이클을 조용히 돌린 뒤 통계,
더러운 캐시 블록, 레지스터, 메모리를 찍는다.

@(mmmix_test.go@>=
const (
	script1 = "@@8000000000010000\nv1ff\n2000\np\ns\nq\n"
	script2 = "@@8000000000010000\n100000\ns\nD*\nS*\ng255\nm10000\nq\n"
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

@ 이진 파일은 {\mc MMIX-SIM}의 \.{-D} 선택 사항이 덤프한 것이다. \.{hello.mmb}는 \.{mmixsim}의
시험에 쓴 \.{hello.mms}를, \.{primes.mmb}는 크누스의 \.{primes.mms}를 어셈블해서 덤프했다. 첫
시험은 미리 짜 둔 환경과 마법 같은 입출력(\.{Fputs}와 \.{Halt})을 시험한다. 조용한 방식에서는
|MMIXSilent|가 |g[255]|를 돌려주는데, 여기서는 8이다.

@(mmmix_test.go@>=
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

@ 둘째 이진 파일은 처음 소수 500개의 표를 찍는다. 두 설정에서 결과가 같아야 한다.

@(mmmix_test.go@>=
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

@ 오류 메시지와 종료 코드도 원본과 같아야 한다.

@(mmmix_test.go@>=
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

@ 마지막으로 \NNIX\ 커널을 시험한다. 커널의 목적 파일은 저장소에 두지 않고, 시험할 때마다
\.{mmixal}로 \.{nnix/nnix.mms}를 어셈블한다. 한글 주석 때문에 줄이 길어 입력 버퍼를 늘린다.

@(mmmix_test.go@>=
func assembleKernel(t *testing.T) string {
	t.Helper()
	mmo := filepath.Join(t.TempDir(), "nnix.mmo")
	cmd := exec.Command("go", "run", "../mmixal", "-b", "250", "-o", mmo, "../nnix/nnix.mms")
	if out, err := cmd.CombinedOutput(); err != nil || len(out) != 0 {
		t.Fatalf("mmixal: %v\n%s", err, out)
	}
	return mmo
}

@ 커널을 거쳐도 표준 출력과 종료 코드는 마법과 같아야 한다. 마법은 시뮬레이터 안에서 순식간에
일어나지만 커널은 진짜 명령을 실행하므로 걸리는 사이클은 다르다.

@(mmmix_test.go@>=
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

@ 마법이 아니라 커널이 일했는지는 \.{v40}이 알리는 장치 입출력으로 확인한다. 커널은 부팅할 때
사용자의 rV를 장치의 \.{RV}에 쓴다. 첫 \.{Fputs}에서는 사용자의 가상 주소 \Hex{4000000000000018}을
그대로 \.{ARG0}에 쓰고(장치가 같은 페이지 테이블로 변환한다), 명령 \Hex{701}(\.{Fputs},
\.{StdOut})을 \.{CMD}에 쓴다.

@(mmmix_test.go@>=
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

@ 요구 페이징을 시험한다. 프로그램 \.{span}은 데이터 세그먼트의 페이지 경계에 걸친 문자열을
\.{Fputs}로 찍고, 역시 경계에 걸친 버퍼에 \.{Fgets}로 읽어 다시 찍는다. 문자열의 뒤 페이지를 먼저
건드리고 풀 세그먼트를 건드린 뒤에야 커널이 앞 페이지를 들이므로, 두 페이지의 프레임은 물리
메모리에서 떨어져 있고 순서도 거꾸로다. 그래도 장치가 페이지 테이블로 변환하므로 출력은 마법과
같아야 한다. 프로그램 \.{far}는 데이터 세그먼트의 1024번 페이지를 읽는다. 커널의 테이블은
세그먼트마다 한 페이지뿐이라 이 폴트는 들일 수 없고, 커널은 표준 오류에 알리고 멈춘다.

@(mmmix_test.go@>=
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

@ 커널 파일을 열 수 없거나 형식이 틀렸을 때다.

@(mmmix_test.go@>=
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
		code       int
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

@* 찾아보기.
