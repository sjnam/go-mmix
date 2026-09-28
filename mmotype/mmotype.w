% 이 파일은 MMIXware의 mmotype.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

@s io.Writer int
@s bufio.Reader int
@s bufio.Writer int
@s bytes.Buffer int
@s time.Location int
@s testing.T int
@s do int
@s while int

\input kotexgweb
\def\title{MMOTYPE}

@* 들어가며. 이 프로그램은 \MMIXAL\ 처리기가 내놓은 이진 \.{mmo} 파일을 읽어서 사람이 읽을
수 있는 꼴로 나열한다. \.{-s} 옵션으로 부르면 기호표만 나열한다. \.{-v} 옵션으로 부르면
입력의 테트라바이트들도 나열한다.

보충: 원본의 |main| 함수가 하던 일을 여기서는 함수 |mmotype|이 한다. 명령줄 인자, 표준 출력,
표준 오류, 그리고 파일을 만든 시각을 찍을 때 쓸 시간대를 매개변수로 받고, 종료 코드를
돌려준다. 원본은 입력이 잘못되면 |exit|로 곧바로 끝냈는데, 여기서는 |exitSignal| 값을 던지는
공황으로 이 함수의 맨 바깥까지 빠져나와 그 값을 종료 코드로 돌려준다. 그래서 시험 프로그램이
같은 프로세스 안에서 이 프로그램을 여러 번 부를 수 있다. 시간대를 매개변수로 받는 것도
시험을 위해서다. 원본은 늘 지역 시간대를 썼다.

원본의 |do|\dots|while| 루프는 \GO/에서 조건을 앞에 둔 |for| 루프가 된다. 표시 |postamble|이
처음에 거짓이므로 첫 바퀴는 어차피 돈다. 이 루프에는 |items|라는 이름표를 붙였다. 아래에서
오류를 만나면 |continue items|로 루프의 조건 검사로 돌아가는데, 원본의 |continue|가
|do|\dots|while|의 조건 검사로 가던 것과 같다.

@c
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"time"
)

@<타입 정의@>
@<상수@>
@<함수들@>

func mmotype(args []string, stdout, stderr io.Writer, loc *time.Location) (code int) {
	var j, delta int
	postamble := false
	t := &typer{out: bufio.NewWriter(stdout), stderr: stderr, loc: loc}
	defer func() {
		@<출력을 비우고, 빠져나온 공황이 있으면 종료 코드로 삼는다@>
	}()
	@<명령줄을 처리한다@>
	@<모든 것을 초기화한다@>
	@<서문을 나열한다@>
items:
	for !postamble {
		@<다음 항목을 나열한다@>
	}
	@<후기를 나열한다@>
	@<기호표를 나열한다@>
	return 0
}

func main() {
	os.Exit(mmotype(os.Args, os.Stdout, os.Stderr, time.Local))
}

@ 공황은 |exitSignal|일 때만 받는다. 다른 공황은 프로그램의 잘못이므로 다시 던진다.

@<출력을 비우고...@>=
t.out.Flush()
if r := recover(); r != nil {
	e, ok := r.(exitSignal)
	if !ok {
		panic(r)
	}
	code = int(e)
}

@ 원본의 전역 변수들은 구조체 |typer|의 필드다. 필드는 원본에서 전역 변수가 처음 나오는
곳마다 이 절의 이어붙임으로 하나씩 보탠다.

@<타입 정의@>=
type typer struct {
	@<나열기의 상태@>
}

type exitSignal int // 이 종료 코드로 프로그램을 끝내라는 신호

@ 옵션 문자열은 정확히 두 글자여야 한다. 원본은 인자의 셋째 문자가 널 문자인지 보았다.

@<명령줄을 처리한다@>=
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
@.Usage: ...@>
	return -1
}

@ @<모든 것을 초기화한다@>=
f, err := os.Open(args[len(args)-1])
if err != nil {
	fmt.Fprintf(stderr, "Can't open file %s!\n", args[len(args)-1])
@.Can't open...@>
	return -2
}
defer f.Close()
t.mmoFile = bufio.NewReader(f)

@ @<나열기의 상태@>=
listing bool           // 모든 것을 나열하는가?
verbose bool           // 입력의 테트라들도 읽는 대로 보여 주는가?
mmoFile *bufio.Reader  // 입력 파일
out     *bufio.Writer  // 표준 출력
stderr  io.Writer      // 표준 오류
loc     *time.Location // 파일을 만든 시각을 찍을 시간대

@ \.{mmo} 형식의 완전한 정의는 \MMIXAL\ 문서에 나온다. 여기서는 해석에 쓰이는 기본 상수들만
정의하면 된다.

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
	lopSpec  = 0x8  // 특수 고리 lopcode
	lopPre   = 0x9  // 서문 lopcode
	lopPost  = 0xa  // 후기 lopcode
	lopStab  = 0xb  // 기호표 lopcode
	lopEnd   = 0xc  // 모든 것을 끝내는 lopcode
)

@* 낮은 수준의 산술. 이 프로그램은 |int|가 적어도 32비트이면 언제나 올바르게 동작하도록
만들어졌다.

보충: 이 프로그램은 원본에서도 {\mc MMIX-ARITH}를 쓰지 않는 독립된 프로그램이었다. 그래서
여기서도 \.{mmixarith} 꾸러미를 가져오지 않고 타입 이름만 같게 정의한다. \GO/의 |byte|는
원본의 \KW{byte}와 같은 부호 없는 한 바이트이므로 따로 정의할 필요가 없다.

@<타입 정의@>=
type (
	Tetra = uint32 // 테트라바이트
	Octa  = uint64 // 옥타바이트
)

@ 원본의 서브루틴 |incr|는 (부호 없는) 옥타바이트에 부호 있는 정수를 더했다. 낮은 쪽
테트라바이트에서 올림이나 내림이 생기는지를 |0xffffffff-delta|와 비교해 미리 알아보는
방식이었다. 보충: 64비트에서는 부호 있는 정수를 |Octa|로 바꾸어 더하기만 하면 된다. 곧 $2^{64}$을 법으로 감기므로 음수도 올바르게 더해진다. 그래서 이 서브루틴은 사라지고, 쓰이는
곳에서 |t.curLoc+Octa(int64(delta))| 꼴로 쓴다.

@* 낮은 수준의 입력. \.{mmo} 파일의 테트라바이트는 친절한 큰 끝 방식으로 저장되어 있지만,
이 프로그램은 작은 끝 컴퓨터에서도 동작해야 한다. 그러므로 테트라바이트 하나를 읽는 대신
잇단 네 바이트를 읽어서 테트라바이트 하나로 묶는다.

@<함수들@>=
func (t *typer) readTet() {
	if _, err := io.ReadFull(t.mmoFile, t.buf[:]); err != nil {
		fmt.Fprintf(t.stderr, "Unexpected end of file after %d tetras!\n", t.count)
@.Unexpected end of file...@>
		panic(exitSignal(-3))
	}
	t.yz = int(t.buf[2])<<8 + int(t.buf[3])
	t.tet = Tetra(t.buf[0])<<24 + Tetra(t.buf[1])<<16 + Tetra(t.yz)
	if t.verbose {
		fmt.Fprintf(t.out, "  %08x\n", t.tet)
	}
	t.count++
}

@ 기호표는 바이트 단위로 읽는다. 읽을 바이트가 남아 있지 않으면 테트라를 하나 더 읽는다.

@<함수들@>=
func (t *typer) readByte() byte {
	if t.byteCount == 0 {
		t.readTet()
	}
	b := t.buf[t.byteCount]
	t.byteCount = (t.byteCount + 1) & 3
	return b
}

@ @<나열기의 상태@>=
count     int     // 지금까지 읽은 테트라바이트의 수
byteCount int     // 다음에 읽을 바이트의 색인
buf       [4]byte // 가장 최근에 읽은 바이트들
yz        int     // 가장 낮은 두 바이트
tet       Tetra   // |buf|의 바이트들을 큰 끝 방식으로 묶은 것

@* 주 루프. 이제 이 프로그램의 밥과 빵에 해당하는 부분이다.

보충: 원본에서는 lopcode가 아닌 테트라를 만나거나 |lopQuote|가 다음 테트라를 읽고 나면
|switch| 문을 빠져나와 그 테트라를 보통 항목으로 나열했다. 특수 데이터가 lopcode를 만나 끝나면
|goto loop|로 그 lopcode를 다시 가렸다. 여기서는 가르는 부분을 |loop|라는 이름표를 붙인 루프로
감싸서, |continue loop|가 원본의 |goto loop| 노릇을 하게 했다. 그 루프는 한 바퀴만 돌고
|break|로 끝나는 것이 보통이다.

@<다음 항목을 나열한다@>=
t.readTet()
loop:
for {
	if t.buf[0] == mm {
		switch t.buf[1] {
		case lopQuote:
			if t.yz != 1 {
				t.err("YZ field of lop_quote should be 1")
@.YZ field...should be 1@>
				continue items
			}
			t.readTet()
		@<주 루프의 lopcode 경우들@>
		default:
			t.err("Unknown lopcode")
@.Unknown lopcode@>
			continue items
		}
	}
	break
}
if t.listing {
	@<|tet|를 보통 항목으로 나열한다@>
}

@ 우리는 \.{mmo} 형식의 규칙을 지키지 않은 모든 경우를 잡아내고 싶다. 원본의 매크로 |err|는
이 조금 지루한 일을 덜어 준다. 원본의 매크로는 메시지를 찍고 |continue|까지 했지만, 여기서는
메시지만 찍고 부르는 쪽에서 |continue items|를 한다.

@<함수들@>=
func (t *typer) err(m string) {
	fmt.Fprintf(t.stderr, "Error in tetra %d: %s!\n", t.count, m)
@.Error in tetra...@>
}

@ 보통의 경우에는 새로 읽은 테트라바이트를 현재 위치에 적재하기만 하면 된다. 우리는 현재
위치뿐 아니라, |curLine|이 0이 아니고 |curLoc|이 세그먼트~0에 속하면 현재 파일 위치도
나열한다. 파일 이름은 바뀔 때만 찍는다.

@<|tet|를 보통 항목으로...@>=
fmt.Fprintf(t.out, "%016x: %08x", t.curLoc, t.tet)
if t.curLine == 0 {
	fmt.Fprintf(t.out, "\n")
} else {
	if t.curLoc>>61 != 0 {
		fmt.Fprintf(t.out, "\n")
	} else {
		@<현재 파일 위치를 찍는다@>
	}
	t.curLine++
}
t.curLoc = (t.curLoc + 4) &^ 3

@ 이 코드는 특수 데이터를 나열할 때도 쓰인다.

보충: 망가진 파일에서는 이름이 한 번도 주어지지 않은 번호가 현재 파일이 될 수 있다(아래
|lopFile|의 경우를 보라). 그때 원본은 널 포인터를 |printf|의 \.{\%s}에 넘긴다. 정의되지 않은
동작이지만 흔한 \CEE/ 라이브러리들은 `\.{(null)}'을 찍으므로, 이 한글판도 그렇게 한다.

@<현재 파일 위치를...@>=
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

@ 원본은 파일 이름을 |char| 포인터 배열에 두고, 포인터가 널인지로 그 번호의 파일 이름이
나왔는지를 알았다. 여기서는 이름과 그 표시를 따로 둔다.

@<나열기의 상태@>=
curLoc     Octa        // 현재 위치
listedFile int         // 가장 최근에 나열한 파일 번호
curFile    int         // 가장 최근에 고른 파일 번호
curLine    int         // |curFile| 안의 현재 위치
fileName   [256]string // 본 파일 이름들
fileNamed  [256]bool   // 그 번호의 파일 이름을 보았는가?
tmp        Octa        // 잠깐 관심 있는 옥타바이트

@ @<모든 것을 초기화한다@>=
t.listedFile, t.curFile = -1, -1

@* 간단한 lopcode들. 인용 lopcode |lopQuote|는 이미 구현했다. 그것은 테트라바이트 하나를 더 읽은 뒤 보통의
경우로 흘러내린다. 이제 다른 lopcode들을 차례로 살펴보자.

원본은 매크로 |y|와 |z|로 |buf[2]|와 |buf[3]|을 불렀다. 여기서는 작은 메서드로 둔다.

@<함수들@>=
func (t *typer) y() int { return int(t.buf[2]) } // 둘째로 낮은 바이트
func (t *typer) z() int { return int(t.buf[3]) } // 가장 낮은 바이트

@ 보충: \GO/에서는 |switch| 문의 경우가 끝나면 저절로 빠져나가므로, 원본에서 다음 항목으로
넘어가던 |continue|는 모두 |continue items|로 적었다. 주소의 높은 테트라바이트는 원본처럼
|(j<<24)+tet|로 짓는데, 여기서 |j|는 테트라를 더 읽기 전에 보관해 둔 Y 필드다.

@<주 루프의 lopcode 경우들@>=
case lopLoc:
	if t.z() == 2 {
		j = t.y()
		t.readTet()
		t.curLoc = Octa(Tetra(j<<24)+t.tet) << 32
	} else if t.z() == 1 {
		t.curLoc = Octa(t.y()) << 56
	} else {
		t.err("Z field of lop_loc should be 1 or 2")
@:Z field of lop_loc...}\.{Z field of lop\_loc...@>
		continue items
	}
	t.readTet()
	t.curLoc |= Octa(t.tet)
	continue items
case lopSkip:
	t.curLoc += Octa(t.yz)
	continue items

@ 고침(fixup)은 앞선 참조가 해결되었을 때 정보를 순서에서 벗어나 적재한다. 현재 파일 이름과
줄 번호는 상관이 없다고 본다.

보충: lopcode |lopFixrx|의 $\delta$는 맨 앞 바이트가 1이면 음수 $(\delta\land\Hex{ffffff})-2^j$로
읽는다(\MMIXAL\ 문서의 |lopFixrx| 설명을 보라). 원본에서 |lopFixr|은 |goto fixr|로 공통 꼬리에
뛰었는데, |lopFixr|의 $\delta$는 \Hex{10000}보다 작으므로 공통 꼬리에서 |j|를 쓰는 일이 없다.
여기서는 공통 꼬리를 이름 있는 절로 만들어 두 곳에 끼워 넣었다.

@<주 루프의 lopcode 경우들@>=
case lopFixo:
	if t.z() == 2 {
		j = t.y()
		t.readTet()
		t.tmp = Octa(Tetra(j<<24)+t.tet) << 32
	} else if t.z() == 1 {
		t.tmp = Octa(t.y()) << 56
	} else {
		t.err("Z field of lop_fixo should be 1 or 2")
@:Z field of lop_fixo...}\.{Z field of lop\_fixo...@>
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
	@<상대 주소 고침을 나열한다@>
	continue items

@ @<주 루프의 lopcode 경우들@>=
case lopFixrx:
	j = t.yz
	if j != 16 && j != 24 {
		t.err("YZ field of lop_fixrx should be 16 or 24")
@:YZ field of lop_fixrx...}\.{YZ field of lop\_fixrx...@>
		continue items
	}
	t.readTet()
	delta = int(int32(t.tet))
	if delta&-0x2000000 != 0 {
		t.err("increment of lop_fixrx is too large")
@.increment...too large@>
		continue items
	}
	@<상대 주소 고침을 나열한다@>
	continue items

@ 보충: 원본의 |delta|는 부호 있는 32비트 |int|였으므로 읽은 테트라를 |int32|로 거쳐 넣는다.
위의 검사 |delta&0xfe000000|은 여기서 |delta&-0x2000000|이 된다(부호 있는 정수와 비교하므로).

@<상대 주소 고침을...@>=
if delta >= 0x1000000 {
	t.tmp = t.curLoc + Octa(int64(-((delta&0xffffff)-(1<<j))<<2))
} else {
	t.tmp = t.curLoc + Octa(int64(-delta<<2))
}
if t.listing {
	fmt.Fprintf(t.out, "%016x: %08x\n", t.tmp, Tetra(delta))
}

@ 원본은 파일 이름을 담을 공간을 꼭 필요하다고 확신할 때까지 할당하지 않았다. 이름은
테트라바이트들의 바이트를 이어 붙인 것에서 첫 널 문자 앞까지다.

보충: 이미 이름이 있는 번호에 다시 이름이 주어지면, 원본은 그 테트라들을 건너뛰고 파일을
고른 뒤 오류를 알린다. 그때는 오류 매크로의 |continue| 때문에 줄 번호가 0으로 돌아가지 않는다.
게다가 원본의 매크로 |y|와 |z|는 늘 |buf|를 들여다보므로, 이름의 테트라들을 건너뛴 {\it 뒤에\/}
고르는 파일 번호와 오류 검사에 쓰이는 Z는 마지막으로 읽은 이름 테트라의 바이트다. 이 한글판도
메서드 |y|와 |z|로 같은 일을 한다.

@<주 루프의 lopcode 경우들@>=
case lopFile:
	if t.fileNamed[t.y()] {
		for j = t.z(); j > 0; j-- {
			t.readTet()
		}
		t.curFile = t.y()
		if t.z() != 0 {
			t.err("Two file names with the same number")
@.Two file names...@>
			continue items
		}
	} else {
		if t.z() == 0 {
			t.err("No name given for newly selected file")
@.No name given...@>
			continue items
		}
		@<새 파일 이름을 읽는다@>
	}
	t.curLine = 0
	continue items
case lopLine:
	if t.curFile < 0 {
		t.err("No file was selected for lop_line")
@.No file was selected...@>
		continue items
	}
	t.curLine = t.yz
	continue items

@ 이름의 테트라들을 읽는 동안 |buf|가 바뀌므로 Y와 Z를 먼저 보관해 둔다. 원본은 |readTet|이
|buf|를 덮어써도 |y|를 다시 쓰지 않도록 루프의 셈을 |j|에 옮겨 두고, 이름을 쓸 곳도 미리
정해 두었다.

@<새 파일 이름을 읽는다@>=
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

@ 파일의 특수 바이트들은 현재 위치나 현재 파일 위치와 맞추어져 있을 수 있으므로, 그
매개변수들도 나열한다. 특수 데이터는 |lopQuote|가 아닌 lopcode를 만날 때까지 이어진다. 그
lopcode는 주 루프가 다시 가른다.

@<주 루프의 lopcode 경우들@>=
case lopSpec:
	if t.listing {
		fmt.Fprintf(t.out, "Special data %d at loc %016x", t.yz, t.curLoc)
		if t.curLine == 0 {
			fmt.Fprintf(t.out, "\n")
		} else {
			@<현재 파일 위치를...@>
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

@ 다른 경우들은 주 루프에 나타나면 안 된다. 다만 |lopPost|는 주 루프를 끝낸다. 그 Y와 Z
필드가 잘못되었어도 루프는 끝난다.

@<주 루프의 lopcode 경우들@>=
case lopPre:
	t.err("Can't have another preamble")
@.Can't have another...@>
	continue items
case lopPost:
	postamble = true
	if t.y() != 0 {
		t.err("Y field of lop_post should be zero")
@:Y field of lop_post...}\.{Y field of lop\_post...@>
		continue items
	}
	if t.z() < 32 {
		t.err("Z field of lop_post must be 32 or more")
@:Z field of lop_post...}\.{Z field of lop\_post...@>
	}
	continue items
case lopStab:
	t.err("Symbol table must follow postamble")
@.Symbol table...@>
	continue items
case lopEnd:
	t.err("Symbol table can't end before it begins")
	continue items

@* 서문과 후기. 이제 주 루프 앞과 뒤에서 하는 일이다.

원본은 파일을 만든 시각을 |asctime(localtime(\dots))|로 찍었다. 보충: \GO/에서는 시각을
주어진 시간대로 바꾸고, |asctime|과 같은 꼴 ``\.{Mon Jan \_2 15:04:05 2006}''로 짠다. 날짜가
한 자리이면 앞에 공백이 오는 것도 같다.

@<서문을 나열한다@>=
t.readTet() // 입력의 첫 테트라바이트를 읽는다
if t.buf[0] != mm || t.buf[1] != lopPre {
	fmt.Fprintf(stderr, "Input is not an MMO file (first two bytes are wrong)!\n")
@.Input is not...@>
	return -5
}
if t.y() != 1 {
	fmt.Fprintf(stderr, "Warning: I'm reading this file as version 1, not version %d!\n", t.y())
@.I'm reading this file...@>
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

@ 주 루프가 끝났을 때 |buf|에는 |lopPost| 명령이 남아 있으므로, 그 Z 필드가 G의 값이다.
\$G부터 \$255까지의 처음 값을 나열한다.

@<후기를 나열한다@>=
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

@* 기호표. 마침내 기호표에 이르렀다. 이것은 암묵적인 삼진 트라이 구조를 재귀적으로 따라가므로
이 프로그램에서 가장 흥미로운 부분이다. 기호표의 머리글은 \.{-s} 옵션을 주었을 때도 찍힌다.

@<기호표를 나열한다@>=
t.readTet()
if t.buf[0] != mm || t.buf[1] != lopStab {
	fmt.Fprintf(stderr, "Symbol table does not follow the postamble!\n")
@.Symbol table...@>
	return -6
}
if t.yz != 0 {
	fmt.Fprintf(stderr, "YZ field of lop_stab should be zero!\n")
@.YZ field...should be zero@>
}
fmt.Fprintf(t.out, "Symbol table (beginning at tetra %d):\n", t.count)
t.stabStart = t.count
t.symBuf = t.symBuf[:0]
t.printStab()
@<|lopEnd|을 점검한다@>

@ 주된 일은 |printStab|이라는 재귀 서브루틴이 한다. 이 서브루틴은 현재 기호의 접두어를 담은
조각 |symBuf|를 다룬다. 원본은 전역 배열과, 그 배열에서 아직 채우지 않은 첫 문자를 가리키는
전역 변수 |sym_ptr|를 썼다.

보충: 주 바이트의 비트들은 \MMIXAL\ 문서의 기호표 절에서 설명한 대로다. 왼쪽 부분 트라이,
이 마디의 문자와 (있다면) 기호, 가운데 부분 트라이, 오른쪽 부분 트라이의 순서로 나온다.
기호가 1000바이트 가까이 길어지면 원본은 멈추었다. 조각은 얼마든지 늘어날 수 있지만, 같은
입력에 같은 출력을 내도록 그 한계를 지킨다.

@<함수들@>=
func (t *typer) printStab() {
	m := int(t.readByte()) // 주 조절 바이트
	if m&0x40 != 0 {
		t.printStab() // 왼쪽 부분 트라이가 비어 있지 않으면 순회한다
	}
	if m&0x2f != 0 {
		@<문자 |c|를 읽는다@>
		t.symBuf = append(t.symBuf, c)
		if len(t.symBuf) == symLengthMax {
			fmt.Fprintf(t.stderr, "Oops, the symbol is too long!\n")
@.Oops...too long@>
			panic(exitSignal(-7))
		}
		if m&0xf != 0 {
			@<현재 기호를 그 등가와 일련번호와 함께 찍는다@>
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

@ 지금의 구현은 유니코드를 지원하지 않는다. 8비트보다 긴 코드의 문자는 `\.?'로 찍는다.
그러나 유니코드 출력에 알맞은 글꼴이 있다면 16비트 코드를 위한 변경은 아주 쉬울 것이다.
그 경우 |symBuf|는 와이드 문자의 배열이 될 것이다.
@^Unicode@>
@^system dependencies@>

@<문자 |c|를...@>=
var hi byte
if m&0x80 != 0 {
	hi = t.readByte() // 16비트 문자
}
c := t.readByte()
if hi != 0 {
	c = '?' // 아이고, |(hi<<8)+c|는 지금으로서는 쉽게 찍을 수 없다
}

@ 등가의 길이는 주 바이트의 아래 네 비트 $j$로 안다. 그 값 $j=15$이면 레지스터 번호 한 바이트다. 값이 $j\le8$이면 $j$바이트의 십육진수이고, 그것이 \.{\#0000}이면 정의되지 않은 기호다. 값이 $j>8$이면
데이터 세그먼트의 주소로서, \.{\#2000\dots}으로 시작하는 16자리 가운데 뒤쪽 $2(j-8)$자리를
읽은 바이트로 채운다. 일련번호는 기수~128의 바이트들인데 마지막 바이트에 128이 더해져 있다.

보충: 원본은 이 바이트들을 하나씩 읽으며 |j| 하나에 셈을 쌓았고, 마지막 바이트에 더해진
128은 셈이 끝난 뒤에 뺐다. 원본의 |j|는 32비트 |int|였으므로, 망가진 입력에서 바이트가 길게
이어지면 셈이 감겨 돌아간다. 같은 입력에 같은 값을 찍도록 여기서도 |int32|로 셈한다.
또 원본은 기호를 널 문자로 끝나는 \CEE/ 문자열로 찍었으므로, 망가진 파일에서 기호에 널
바이트가 섞이면 거기서 끊겼다. 이것도 똑같이 한다. 기호의 맨 앞 문자(뿌리의 `\.:')는 찍지
않는다.

@<현재 기호를 그 등가와...@>=
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

@ @<상수@>=
const symLengthMax = 1000

@ @<나열기의 상태@>=
stabStart int    // 기호표가 시작한 곳
symBuf    []byte // 현재 마디로 오는 가운데 가지들의 문자들

@ 기호표 뒤에 남은 바이트는 0이어야 하고, 그다음 테트라는 |lopEnd|이어야 하며, 그 YZ 필드는
기호표의 테트라 수여야 한다.

보충: 옮긴이가 확인해 보니, YZ 필드가 틀렸을 때 원본의 메시지는 올바른 값 |count-stabStart-1|이
아니라 |count-yz-1|을 찍는다. 예컨대 \MMIXAL\ 문서의 \.{test.mmo}에서 |lopEnd|의 YZ를 10에서
5로 바꾸면 ``should have been 53''이라고 알린다. 53은 틀린 YZ로 거꾸로 셈한 기호표의 시작
위치다. 이 한글판도 원본과 같은 값을 찍고, 시험에서 이 동작을 못박아 둔다.

@<|lopEnd|을 점검한다@>=
for t.byteCount != 0 {
	if t.readByte() != 0 {
		fmt.Fprintf(stderr, "Nonzero byte follows the symbol table!\n")
@.Nonzero byte follows...@>
	}
}
t.readTet()
switch {
case t.buf[0] != mm || t.buf[1] != lopEnd:
	fmt.Fprintf(stderr, "The symbol table isn't followed by lop_end!\n")
@.The symbol table isn't...@>
case t.count != t.stabStart+t.yz+1:
	fmt.Fprintf(stderr, "YZ field at lop_end should have been %d!\n", t.count-t.yz-1)
@:YZ field at lop_end...}\.{YZ field at lop\_end...@>
default:
	if t.verbose {
		fmt.Fprintf(t.out, "Symbol table ends at tetra %d.\n", t.count)
	}
	if _, err := t.mmoFile.ReadByte(); err == nil {
		fmt.Fprintf(stderr, "Extra bytes follow the lop_end!\n")
@.Extra bytes follow...@>
	}
}

@* 시험. 원본에는 시험 프로그램이 없었다. 옮긴이는 \MMIXAL\ 문서에 실린 \.{test.mmo}를
나열해서, 원본 \CEE/ 프로그램이 같은 입력에 대해 내놓은 출력과 한 글자도 다르지 않은지
확인한다. 시간대는 협정 세계시로 고정한다. 그리고 앞에서 말한 |lopEnd| 메시지와, 망가진
입력에 대한 오류 메시지 몇 가지를 확인한다.

이 문서 밖에서는 더 큰 비교를 했다. \.{examples} 디렉터리의 \.{.mms} 파일 54개를 원본
\MMIXAL로 어셈블한 목적 파일들과, 그것들의 바이트를 무작위로 바꾸거나 잘라 낸 파일 수천
개를 원본과 이 한글판에 옵션 없이, \.{-s}로, \.{-v}로 넣어 보았다. 표준 출력, 표준 오류,
종료 코드가 모두 같았다.

@(mmotype_test.go@>=
package main

import (
	"bytes"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func typeFile(t *testing.T, mmo []byte, opts ...string) (stdout, stderr string, code int) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "test.mmo")
	if err := os.WriteFile(path, mmo, 0o644); err != nil {
		t.Fatal(err)
	}
	var o, e bytes.Buffer
	code = mmotype(append(append([]string{"mmotype"}, opts...), path), &o, &e, time.UTC)
	return o.String(), e.String(), code
}

func testMMO(t *testing.T) []byte {
	b, err := hex.DecodeString(strings.Join(strings.Fields(testMMOHex), ""))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

@ \MMIXAL\ 문서의 \.{test.mmo}다. 파일을 만든 시각 \Hex{36f4a363}은 협정 세계시로 1999년
3월 21일 일요일 오전 7시 44분 35초다. (크누스의 표에 붙은 주석 ``Sat Mar 20 23:44:35 1999''는
태평양 표준시, 곧 협정 세계시보다 여덟 시간 늦은 캘리포니아의 시각이다. 크누스는 토요일
밤 자정 무렵에 이 파일을 만들었다.)

@(mmotype_test.go@>=
const testMMOHex = `98090101 36f4a363 98012001 00000000 00000000 00000000 61620000
98010002 00000001 2345678c 98060002 74657374 2e6d6d73 98070007 f0000000
98024000 98070009 8103fe01 42030000 9807000a 00000000 98010002 00000001
2345a768 98050010 0100fff5 98040ff7 98032001 00000000 98060102 666f6f2e
6d6d7300 98070004 f000000a 98080005 00000200 00fe0000 98012001 0000000a
00006364 98000001 98000000 980a00fe 20000000 00000008 00000001 2345678c
980b0000 203a5040 50404020 41204220 43094408 83404020 4d206120 69056e01
2345678c 81400f61 fe820000 980c000a`

@ @(mmotype_test.go@>=
func TestKnuthExample(t *testing.T) {
	out, errs, code := typeFile(t, testMMO(t))
	if code != 0 || errs != "" || out != testOut {
		t.Errorf("종료 코드 %d, 표준 오류 %q, 표준 출력:\n%s", code, errs, out)
	}
	out, _, _ = typeFile(t, testMMO(t), "-s")
	if want := testOut[strings.Index(testOut, "Symbol"):]; out != want {
		t.Errorf("-s의 출력:\n%s", out)
	}
}

const testOut = `File was created Sun Mar 21 07:44:35 1999
2000000000000000: 00000000
2000000000000004: 00000000
2000000000000008: 61620000
000000012345678c: f0000000 ("test.mms", line 7)
000000012345a790: 8103fe01 (line 9)
000000012345a794: 42030000 (line 10)
000000012345a798: 00000000 (line 10)
000000012345a794: 0100fff5
000000012345678c: 00000ff7
2000000000000000: 000000012345a768
000000012345a768: f000000a ("foo.mms", line 4)
Special data 5 at loc 000000012345a76c (line 5)
                   00000200
                   00fe0000
200000000000000a: 00006364
200000000000000c: 98000000
g254: 2000000000000008
g255: 000000012345678c
Symbol table (beginning at tetra 48):
    ABCD = #2000000000000008 (3)
    Main = #012345678c (1)
    a = $254 (2)
`

@ lopcode |lopEnd|의 YZ를 망가뜨린 경우와, 입력이 모자라거나 처음부터 \.{mmo} 파일이 아닌 경우다.

@(mmotype_test.go@>=
func TestBrokenInputs(t *testing.T) {
	good := testMMO(t)
	bad := bytes.Clone(good)
	bad[len(bad)-1] = 5 // |lopEnd|의 YZ를 10에서 5로
	if _, errs, code := typeFile(t, bad, "-s"); code != 0 ||
		errs != "YZ field at lop_end should have been 53!\n" {
		t.Errorf("종료 코드 %d, %q", code, errs)
	}
	if _, errs, code := typeFile(t, good[:30]); code != -3 ||
		errs != "Unexpected end of file after 7 tetras!\n" {
		t.Errorf("종료 코드 %d, %q", code, errs)
	}
	if _, errs, code := typeFile(t, []byte("hello, world")); code != -5 ||
		errs != "Input is not an MMO file (first two bytes are wrong)!\n" {
		t.Errorf("종료 코드 %d, %q", code, errs)
	}
}

@* 찾아보기.
