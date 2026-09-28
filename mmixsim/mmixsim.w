% 이 파일은 MMIXware의 mmix-sim.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

@s io.Writer int
@s bufio.Reader int
@s bufio.Writer int
@s bytes.Buffer int
@s atomic.Bool int
@s mmixio.IO int
@s io.Reader int
@s os.File int
@s os.Signal int
@s mmixarith.Octa int
@s mmixarith.Tetra int
@s mmixarith.Round int
@s mmixio.Simulator int
@s testing.T int
@s FILE int

\input kotexgweb
\def\title{MMIXSIM}
\def\NNIX{\hbox{\mc NNIX}}

@* 들어가며. 이 프로그램은 \MMIX\ 컴퓨터를 단순화한 판을 흉내 낸다. 주된 목적은 사람들이
{\sl The Art of Computer Programming\/}과 그에 딸린 출판물에 실을 \MMIX\ 프로그램을
만들고 시험하도록 돕는 것이다. 이 시뮬레이터는 초보적인 단말기 중심의 인터페이스만
제공하지만, 멋진 그래픽 사용자 인터페이스를 받쳐 줄 만한 기반은 충분히 갖추고 있다.
그런 인터페이스는 의욕 있는 독자가 덧붙이면 된다. (힌트, 힌트.)

\MMIX는 다음과 같이 단순화되었다.

\bull
파이프라인이 없고 캐시도 없다. 따라서 \.{SYNC}, \.{SYNCD}, \.{PREGO} 같은 명령은 아무
일도 하지 않는다.

\bull
운영체제 커널은 흉내 내지 않고 사용자 프로그램만 흉내 낸다. 따라서 모든 주소는 음이
아니어야 한다. ``특권'' 명령, 이를테면 \.{PUT}~\.{rK,z}나 \.{RESUME}~\.1이나
\.{LDVTS}~\.{x,y,z}는 허용되지 않는다. 명령은 세그먼트~0에서만, 곧 \Hex{2000000000000000}보다 작은
주소에서만 실행해야 한다. 어떤 특수 레지스터들은 늘 같은 값을 가진다.
곧 $\rm rF=0$,
$\rm rK=\Hex{ffffffffffffffff}$,
$\rm rQ=0$,
$\rm rT=\Hex{8000000500000000}$,
$\rm rTT=\Hex{8000000600000000}$,
$\rm rV=\Hex{369c200400000000}$이다.

\bull
트랩 인터럽트는 구현하지 않는다. 다만 초보적인 입출력을 제공하는 \.{TRAP}의 특별한
경우 몇 가지는 예외다.
@^interrupts@>

\bull
모든 명령은 정해진 만큼의 시간이 걸린다. 그 시간은 \MMIX\ 문서에 적힌 대략의
추정값이다. 이를테면 \.{MUL}은 $10\upsilon$, \.{LDB}는 $\mu+\upsilon\mkern1mu$가 걸린다.
모든 시간은 $\mu$와~$\upsilon$, 곧 ``mem''과 ``oop''으로 나타낸다. 모의 시계는
@^mems@>
@^oops@>
$\mu$마다 $2^{32}$씩, $\upsilon$마다 1씩 늘어난다. 그러나 구간 계수기~rI는 $\upsilon$마다
@^rI@>
@^rU@>
1씩 줄어든다. 그리고 rU의 사용 횟수 필드는 명령마다 ($2^{47}$을 법으로) 1씩 늘어날 수
있다.

보충: 원본의 |main| 함수가 하던 일을 여기서는 함수 |mmix|가 한다. 명령줄 인자, 표준 입력,
표준 출력, 표준 오류를 매개변수로 받고 종료 코드를 돌려준다. 그래서 시험 프로그램이 같은
프로세스 안에서 시뮬레이터를 여러 번 부를 수 있다. 원본은 여러 곳에서 |exit|로 곧바로
끝냈는데, 여기서는 |exitSignal| 값을 던지는 공황으로 |mmix|의 맨 바깥까지 빠져나와 그
값을 종료 코드로 삼는다. 원본의 전역 변수들은 두 갈래로 나뉜다. 여러 서브루틴이 함께
쓰는 것은 구조체 |simulator|의 필드가 되고, |main| 안에서만 쓰는 것은 |mmix|의 지역 변수가
된다. 앞서 옮긴 \.{mmixal}과 \.{mmotype}에서처럼 \CEE/의 |goto|는 이름표를 붙인 |break|와
|continue|로 바꾸었다. 원본의 몸통은 이 문서의 끝 무렵 ``프로그램 돌리기'' 장에 있다.
\GO/ 판의 실행 파일 이름은 원본처럼 \.{mmix}가 되도록 \.{go} \.{build} \.{-o} \.{mmix}
\.{./mmixsim}으로 만들면 된다.

@c
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"math/bits"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	@#
	"github.com/sjnam/mmix/mmixarith"
	"github.com/sjnam/mmix/mmixio"
)

@<타입 정의@>
@<상수@>
@<표@>
@<함수들@>

func mmix(args []string, stdin io.Reader, stdout, stderr io.Writer) (code int) {
	m := &simulator{
		@<시뮬레이터의 초깃값@>
	}
	defer func() {
		@<출력을 모두 비우고, 빠져나온 공황이 있으면 종료 코드로 삼는다@>
	}()
	m.io = mmixio.New(m, m.out, stderr)
	@<프로그램을 돌린다@>
}

func main() {
	os.Exit(mmix(os.Args, os.Stdin, os.Stdout, os.Stderr))
}

@ 공황은 |exitSignal|일 때만 받는다. 다른 공황은 프로그램의 잘못이므로 다시 던진다.
원본은 끝날 때 \CEE/ 라이브러리의 |exit|가 모든 스트림의 버퍼를 비워 주었다. 여기서는
시뮬레이터 자신의 표준 출력을 비운 뒤, \.{mmixio}가 연 파일들을 |FlushAll|로 비운다.
덤프 파일도 비우고 닫는다.

@<출력을 모두 비우고...@>=
m.out.Flush()
m.io.FlushAll()
if m.dumpFile != nil {
	m.dumpFile.Flush()
	m.dumpOS.Close()
}
if r := recover(); r != nil {
	e, ok := r.(exitSignal)
	if !ok {
		panic(r)
	}
	code = int(e)
}

@ 원본의 전역 변수 가운데 서브루틴들이 함께 쓰는 것들은 구조체 |simulator|의 필드다.
필드는 원본에서 그 변수가 처음 나오는 곳마다 이 절의 이어붙임으로 하나씩 보탠다.

@<타입 정의@>=
type simulator struct {
	@<시뮬레이터의 상태@>
}

type exitSignal int // 이 종료 코드로 프로그램을 끝내라는 신호

@ 시뮬레이터 자신의 출력과 모의 프로그램의 표준 출력은 원본에서 같은 \CEE/ |stdout|을
나누어 썼다. 여기서도 버퍼 하나를 함께 쓴다. 표준 입력도 대화 명령과 모의 프로그램이
함께 읽는다. 이것은 \CEE/의 |fgets|를 흉내 내는 타입 |cfile|로 읽는데, 그 타입은 이
문서의 끝 무렵에 있는 옮긴이의 장에서 정의한다.

@<시뮬레이터의 상태@>=
out    *bufio.Writer // 표준 출력
stderr io.Writer     // 표준 오류
stdin  *cfile        // 표준 입력
io     *mmixio.IO    // 입출력 기본 연산들

@ @<시뮬레이터의 초깃값@>=
out:    bufio.NewWriter(stdout),
stderr: stderr,
stdin:  &cfile{r: bufio.NewReader(stdin)},

@ \UNIX/의 관례를 따른다면, 이 시뮬레이터는
`\.{mmix} \<options> \.{progfile} \.{args...}'라고 불러 돌린다.
여기서 \.{progfile}은 \.{MMIXAL} 어셈블러가 내놓은 출력이고, \.{args...}는 모의
프로그램에 넘겨줄 명령줄 인자들(없어도 된다)이다. \<options>는 다음 옵션들 가운데 아무
것이나 고른 것이다.
@^command line arguments@>

\bull \.{-t<n>}\quad 각 명령을 처음 $n$번 실행될 때까지 추적한다. (이 옵션과 아래의 여러
옵션과 대화 명령에 나오는 \.{<n>}은 십진 정수를 뜻한다.)

\bull \.{-e<x>}\quad 주어진 비트 패턴에 속하는 산술 예외를 일으키는 명령을 모두 추적한다.
(이 옵션과 아래의 여러 명령에 나오는 \.{<x>}는 십육진 정수를 뜻한다.) 예외 비트는 rA에
나타나는 대로 DVWIOUZX다. 곧 D(정수 나눗셈 검사)는~\Hex{80}, V(정수 넘침)는~\Hex{40},
\dots, X(부동소수점 부정확)는~\Hex{01}이다. 옵션 \.{-e}만 쓰면 \.{-eff}와 같고, 여덟 가지
예외를 모두 추적한다.

\bull \.{-r}\quad 레지스터 스택의 자세한 사정을 추적한다. 이 옵션을 쓰면, 옥타바이트들이
지역 레지스터의 고리에서 메모리로 쓰이거나 메모리에서 그 고리로 읽힐 때 일어나는
``숨은'' 적재와 저장이 모두 보인다. 연산 \.{SAVE}와 \.{UNSAVE}의 자세한 사정도 모두
보인다.

\bull \.{-l<n>}\quad 추적하는 명령마다 그에 해당하는 원시 줄을 보여 준다. 길이가 $n$ 이하인
빈틈은 채운다. 이를테면 어떤 명령이 원시 파일의 10번째 줄에서 왔고 다음에 추적할 명령이
12번째 줄에서 왔다면, $n\ge1$일 때 11번째 줄도 보인다. 수 \.{<n>}을 빼면 3으로 친다.

\bull \.{-s}\quad 추적하는 명령마다 실행 시간 통계를 보여 준다.

\bull \.{-P}\quad 시뮬레이션이 끝날 때 프로그램 프로파일, 곧 실행된 명령마다의 빈도수를
보여 준다.

\bull \.{-L<n>}\quad 프로그램 프로파일에 나오는 명령마다 그에 해당하는 원시 줄을 보여 준다.
길이가 $n$ 이하인 빈틈은 채운다. 이 옵션은 \.{-P}를 함축한다. 수 \.{<n>}을 빼면 3으로 친다.

\bull \.{-v}\quad 자세히 보여 준다: \kern-2.5pt 모든 옵션을 켠다. (더 정확히 말하면
\.{-v} 옵션은 \.{-t9999999999}~\.{-e} \.{-r} \.{-s} \.{-l10}~\.{-L10}의 줄임말이다.)

\bull \.{-q}\quad 조용히 한다: 앞서 준 옵션들을 모두 취소한다.

\bull \.{-i}\quad 시뮬레이션을 시작하기 전에 대화 방식으로 들어간다.

\bull \.{-I}\quad 모의 프로그램이 멈추거나 멈춤점에서 쉬면 대화 방식으로 들어간다.

\bull \.{-b<n>}\quad 원시 줄 버퍼의 크기를 $\max(72,n)$으로 정한다.

\bull \.{-c<n>}\quad 지역 레지스터 고리의 용량을 $\max(256,n)$으로 정한다. 이 수는
2의 거듭제곱이어야 한다.

\bull \.{-f<filename>}\quad 주어진 이름의 파일을 모의 프로그램의 표준 입력으로 쓴다.
시뮬레이터를 대화식으로 쓰지 않을 때는 늘 이 옵션을 써야 한다. 표준 입력을 다른 방법으로
정하면 시뮬레이터가 파일 끝을 알아채지 못하기 때문이다.

\bull \.{-D<filename>}\quad 실제로 시뮬레이션을 하는 대신, 다른 시뮬레이터들이 쓸 수
있도록 주어진 이름의 파일을 준비한다.

\bull \.{-?}\quad 명령줄 옵션을 요약한 ``\.{Usage}'' 알림을 찍는다.

\smallskip\noindent
처음으로 오프라인 디버깅을 할 때는 \.{-t2} \.{-l} \.{-L}을 권한다.

모의 프로그램이 돌고 있는 동안 {\it 인터럽트\/} 신호(보통 control-C)를 보내면,
@^interrupts@>
시뮬레이터는 현재 명령을 추적한 뒤 멈추고 대화 방식으로 들어간다. 옵션 \.{-i}나 \.{-I}를
명령줄에 주지 않았어도 그렇다.

@ 대화 방식에서는 `\.{mmix>}'라는 프롬프트가 뜨고, 여러 가지 명령을 입력할 수 있다.
@.mmix>@>
명령줄 옵션은 무엇이든 이 프롬프트에 대한 대답으로 줄 수 있다(옵션을 시작하는 `\.-'도
함께 쓴다). 그 밖에 다음 연산들도 쓸 수 있다.

\bull \.{mmix>} 프롬프트에 그냥 \<return>이나 \.n\<return>을 치면 \MMIX\ 명령 하나를
실행해서 추적하고, 다시 프롬프트를 띄운다.

\bull \.c는 프로그램이 멈추거나 멈춤점에 이를 때까지 시뮬레이션을 이어 간다. (사실
명령은 `\.c\<return>'이지만, 아래 설명에서 \<return>은 굳이 밝히지 않는다.)

\bull \.q는 끝낸다(시뮬레이션을 마친다). 프로파일을 요청했다면 그것을 찍고, 마지막
통계를 찍은 뒤에 끝낸다.

\bull \.s는 현재 통계(시계 시간들과 현재 명령의 위치)를 찍는다. 명령줄의 \.{-s} 옵션은
이미 이야기했다. 그 옵션을 쓰면 이 통계가 저절로 찍힌다. 그러나 통계가 많으면 파일
공간을 많이 차지할 수 있으므로, 원할 때만 통계를 보고 싶은 사용자도 있을 것이다.

\bull \.{l<n><t>}, \.{g<n><t>}, \.{\$<n><t>}, \.{rA<t>}, \.{rB<t>}, \dots,
\.{rZZ<t>}, \.{M<x><t>}는 각각 지역 레지스터, 전역 레지스터, 동적으로 번호가 매겨지는
레지스터, 특수 레지스터, 메모리 위치의 현재 값을 보여 준다. 여기서 \.{<t>}는 보여 줄 값의
형식을 정한다. 형식 \.{<t>}가 `\.!'이면 값을 십진으로, `\..'이면 부동소수점으로,
`\.\#'이면 십육진으로, `\."'이면 한 바이트 문자 여덟 개의 문자열로 보여 준다. 형식 \.{<t>}만
치면 가장 최근에 보여 준 값을 다시 보여 주는데, 다른 형식으로 보여 줄 수도 있다. 이를테면
`\.{l10\#}' 명령은 지역 레지스터 10을 십육진으로 보여 주고, 이어서 `\.!' 명령을 치면
그것을 십진으로, `\..' 명령을 치면 부동소수점 수로 보여 준다. 형식 \.{<t>}가 비어 있으면 앞의
형식을 되풀이한다. 기본 형식은 십진이다. 명령 \.{GET}과 \.{PUT}에서 쓰는 번호 매김을
따르면 레지스터 \.{rA}는 \.{g21}과 같다.

이 명령들의 `\.{<t>}'는 `\.{=<value>}' 꼴일 수도 있다. 여기서 값은 십진이나 부동소수점이나
십육진 상수, 또는 문자열 상수다. (부동소수점 상수의 문법 규칙은 {\mc MMIX-ARITH}에
나온다. 문자열 상수는 \.{MMIXAL}의 \.{BYTE} 명령에서처럼 다루되, 지정한 문자가 여덟 개보다
적으면 왼쪽을 0으로 채운다.) 이렇게 하면 값을 보여 주기 전에 새 값을 넣는다. 이를테면
`\.{l10=.1e3}'은 지역 레지스터 10을 100으로 만들고, `\.{g250="ABCD",\#a}'는 전역
레지스터 250을 \Hex{000000414243440a}로 만들고, `\.{M1000=-Inf}'는
M$_8[\Hex{1000}]$을 $-\infty$의 표현인 \Hex{fff0000000000000}으로 만든다. 특수 레지스터
가운데 rI가 아닌 것에는 \.{PUT}이 허용하지 않는 값을 넣을 수 없다. 가장자리 레지스터에는 0이 아닌
값을 넣을 수 없다.

명령 `\.{rI=250}'은 구간 계수기를 250으로 만든다. 그러면 $250\upsilon$이 지난 뒤에
시뮬레이션이 멈춘다.

\bull \.{+<n><t>}는 가장 최근에 보여 준 옥타바이트 다음의 옥타바이트 $n$개를 형식
\.{<t>}로 보여 준다. 이를테면 `\.{l10\#}' 다음에 `\.{+30}'을 치면 \.{l11}, \.{l12},
\dots, \.{l40}을 십육진으로 보여 준다. `\.{g200=3}' 다음에 `\.{+30}'을 치면 \.{g201},
\.{g202}, \dots, \.{g230}을 모두 3으로 만든다. 그러나 `\.{+30!}'을 치면 \.{g201}부터
\.{g230}까지를 십진으로 보여 주기만 한다. 메모리 주소는 1이 아니라 8씩 나아간다. 수 \.{<n>}이
비어 있으면 기본값 $n=1$을 쓴다.

\bull \.{@@<x>}는 다음에 흉내 낼 테트라바이트의 주소를 정한다. 명령 \.{GO}와 비슷하다.

\bull \.{t<x>}는 테트라바이트 위치 $x$에 있는 명령을 빈도수에 관계없이 늘 추적하라는
뜻이다.

\bull \.{u<x>}는 \.{t<x>}의 효과를 없앤다.

\bull \.{b[rwx]<x>}는 테트라바이트 $x$에 멈춤점을 둔다. 여기서 \.{[rwx]}는 글자 \.r,
\.w, \.x의 아무 부분집합이고, 그 테트라바이트를 읽을 때, 쓸 때, 실행할 때 멈추라는
뜻이다. 이를테면 `\.{bx1000}'은 \Hex{1000}에 있는 테트라바이트를 실행한 직후에
시뮬레이션을 멈추게 한다. `\.{b1000}'은 이 멈춤점을 없앤다. `\.{brwx1000}'은 모의 명령이
테트라바이트 \Hex{1000}을 적재하거나 저장하거나 그 자리에 있을 때마다 그 명령 직후에
멈추게 한다.

\bull \.{T}, \.{D}, \.{P}, \.{S}는 ``현재 세그먼트''를 각각 \.{Text\_Segment},
\.{Data\_Segment}, \.{Pool\_Segment}, \.{Stack\_Segment}로, 곧 \Hex{0},
\Hex{2000000000000000}, \Hex{4000000000000000}, \Hex{6000000000000000}으로 정한다.
처음에 \Hex{0}인 현재 세그먼트는 \.{M}, \.{@@}, \.{t}, \.{u}, \.{b} 명령의 모든 메모리
주소에 더해진다.
@:Text_Segment}\.{Text\_Segment@>
@:Data_Segment}\.{Data\_Segment@>
@:Pool_Segment}\.{Pool\_Segment@>
@:Stack_Segment}\.{Stack\_Segment@>

\bull \.{B}는 현재의 멈춤점과 추적점을 모두 나열한다.

\bull \.{i<filename>}은 주어진 파일에서 대화 명령들을 한 줄에 하나씩 읽는다. 빈 줄은
건너뛴다. 이 기능을 쓰면 멈춤점을 많이 두거나 중요한 레지스터 여럿을 보여 주는 일 따위를
할 수 있다. 끼워 넣은 줄 가운데 \.\%나 \.i로 시작하는 줄은 무시한다. 따라서 끼워 넣은
파일이 {\it 또 다른\/} 파일을 끼워 넣을 수는 없다. 끼워 넣은 줄 가운데 빈칸으로 시작하는
줄은 표준 출력에 그대로 찍히고, 그 밖에는 무시된다.

\bull \.h(도움말)는 쓸 수 있는 대화 명령들을 일러 준다.

@* 초보적인 입출력.
입력과 출력은 다음 열 가지 기본 시스템 호출로 제공된다.
@^I/O@>
@^input/output@>

\bull \.{Fopen}|(handle,name,mode)|. 여기서 |handle|은 한 바이트 정수이고, |name|은
문자열의 첫 바이트의 주소이고, |mode|는 \.{TextRead}, \.{TextWrite}, \.{BinaryRead},
\.{BinaryWrite}, \.{BinaryReadWrite} 가운데 하나다. 호출 \.{Fopen}은 |handle|을
|name|이라는 외부 파일과 연결하고, 그 파일에 입력이나 출력이나 둘 다를 할 준비를 한다.
파일을 잘 열었으면 0을 돌려주고, 그렇지 않으면 $-1$을 돌려준다. 방식 |mode|가
\.{TextWrite}나 \.{BinaryWrite}나 \.{BinaryReadWrite}이면 그 이름의 파일에 있던 내용은
모두 버려진다. 방식 |mode|가 \.{TextRead}나 \.{TextWrite}이면 파일은 ``줄 바꿈'' 문자로
끝나는 ``줄''들로 이루어지고, 텍스트 파일이라고 부른다. 그렇지 않으면 파일은 해석하지
않는 바이트들로 이루어지고, 이진 파일이라고 부른다.
@.Fopen@>
@.TextRead@>
@.TextWrite@>
@.BinaryRead@>
@.BinaryWrite@>
@.BinaryReadWrite@>

이 시뮬레이터가 \UNIX/에서 비롯된 운영체제 위에서 돌 때는 텍스트 파일과 이진 파일이
사실상 같다. 그런 경우에는 텍스트로 쓴 파일을 이진으로 읽어도 되고 그 반대도 된다. 그러나
다른 운영체제에서는 텍스트 파일과 이진 파일의 표현이 아주 다른 때가 많고, 바이트 코드가
|' '|보다 작은 어떤 문자들은 텍스트에 쓸 수 없다. \MMIX\ 프로그램 안에서 줄 바꿈 문자의
바이트 코드는 $\Hex{0a}=10$이다.

프로그램이 시작할 때 핸들 세 개가 이미 열려 있다. ``표준 입력'' 파일 \.{StdIn}(핸들~0)은
방식이 \.{TextRead}이고, ``표준 출력'' 파일 \.{StdOut}(핸들~1)은 방식이
\.{TextWrite}이고, ``표준 오류'' 파일 \.{StdErr}(핸들~2)도 방식이 \.{TextWrite}이다.
@.StdIn@>
@.StdOut@>
@.StdErr@>
이 시뮬레이터를 대화식으로 돌릴 때는, \.{-f} 옵션을 쓰지 않았다면 `\.{StdIn>\ }'라는
프롬프트 뒤에 표준 입력의 줄들을 쳐야 한다. 모의 프로그램의 표준 출력과 표준 오류 파일은
시뮬레이터 자신의 출력과 뒤섞인다.

이 시뮬레이터가 지원하는 입출력 연산들은 \CEE/ 언어에 딸린 표준 라이브러리 \.{stdio}에
견주어 보면 가장 쉽게 이해될 것이다. \CEE/의 관례는 수백 권의 책에서 설명되어 왔기
때문이다. 배열 |FILE *file[256]|을 선언하고 |file[0]=stdin|, |file[1]=stdout|,
|file[2]=stderr|로 둔다면, 모의 시스템 호출 \.{Fopen}|(handle,name,mode)|는 본질적으로
다음 \CEE/ 식과 같다.
$$\displaylines{
\hskip5em\hbox{(|file[handle]|?
     |(file[handle]=freopen(name,mode_string[mode],file[handle]))|:}\hfill\cr
\hfill\hbox{|(file[handle]=fopen(name,mode_string[mode]))|)? 0: $-1$}%
      \hskip5em\cr}$$
여기서 |mode_string|[\.{TextRead}]~=~|"r"|,
|mode_string|[\.{TextWrite}]~=~|"w"|,
|mode_string|[\.{BinaryRead}]~=~|"rb"|,
|mode_string|[\.{BinaryWrite}]~=~|"wb"|,
|mode_string|[\.{BinaryReadWrite}]~=~|"wb+"|로 둔다.

\bull \.{Fclose}|(handle)|. 주어진 파일 핸들이 열려 있었다면 그것을 닫는다. 곧 더는
어떤 파일과도 연결되지 않는다. 이번에도 결과는 성공하면 0이고, 파일이 이미 닫혀 있었거나
닫을 수 없으면 $-1$이다. \CEE/로는
$$\hbox{|fclose(file[handle])? -1: 0|}$$
와 같고, 덧붙여 |file[handle]=NULL|로 만드는 부수 효과가 있다.

\bull \.{Fread}|(handle,buffer,size)|.
파일 핸들은 \.{TextRead}, \.{BinaryRead}, \.{BinaryReadWrite} 가운데 한 방식으로 열려
있어야 한다.
@.Fread@>
다음 |size|개의 문자를 읽어서 주소 |buffer|에서 시작하는 \MMIX의 메모리에 넣는다. 오류가
생기면 |-1-size|를 돌려준다. 그렇지 않으면, 도중에 파일 끝을 만나지 않았다면 0을
돌려주고, 만났다면 음수 |n-size|를 돌려준다. 여기서 |n|은 제대로 읽어서 넣은 문자의
개수다. 파일 오류가 없다면
$$\hbox{|fread(buffer,1,size,file[handle])-size|}$$
라는 \CEE/ 문장이 같은 효과를 낸다.

\bull \.{Fgets}|(handle,buffer,size)|.
파일 핸들은 \.{TextRead}, \.{BinaryRead}, \.{BinaryReadWrite} 가운데 한 방식으로 열려
있어야 한다.
@.Fgets@>
문자들을 읽어서 주소 |buffer|에서 시작하는 \MMIX의 메모리에 넣는데, |size-1|개를 읽어서
넣거나 줄 바꿈 문자 하나를 읽어서 넣을 때까지 계속한다. 그런 다음 메모리의 다음 바이트를
0으로 만든다. 읽기를 마치기 전에 오류나 파일 끝이 생기면 메모리의 내용은 정의되지 않고,
$-1$을 돌려준다. 그렇지 않으면 제대로 읽어서 넣은 문자의 개수를 돌려준다. 읽은 문자 가운데
널 문자가 없다고 가정하면, \CEE/로는
$$\hbox{|fgets(buffer,size,file[handle])? strlen(buffer): -1|}$$
와 같다. 그러나 널 문자가 줄 바꿈 문자 앞에 올 수도 있고, 그런 널 문자도 다른 문자들처럼
센다.

\bull \.{Fgetws}|(handle,buffer,size)|.
@.Fgetws@>
이 명령은 \.{Fgets}와 같되, 한 바이트 문자 대신 와이드 문자에 적용된다. 와이드 문자를
|size-1|개까지 읽는다. 와이드 줄 바꿈 문자는 $\Hex{000a}$이다. ISO 멀티바이트 문자열
확장(MSE)의 관례를 쓰는 \CEE/ 판은 대략
@^MSE@>
$$\hbox{|fgetws(buffer,size,file[handle])? wcslen(buffer): -1|}$$
이다. 여기서 |buffer|의 타입은 이제 |wchar_t*|다.

\bull \.{Fwrite}|(handle,buffer,size)|.
파일 핸들은 \.{TextWrite}, \.{BinaryWrite}, \.{BinaryReadWrite} 가운데 한 방식으로 열려
있어야 한다.
@.Fwrite@>
주소 |buffer|에서 시작하는 \MMIX의 메모리에서 다음 |size|개의 문자를 쓴다. 오류가
없으면 0을 돌려준다. 그렇지 않으면 음수 |n-size|를 돌려준다. 여기서 |n|은 제대로 쓴
문자의 개수다.
$$\hbox{|fwrite(buffer,1,size,file[handle])-size|}$$
라는 문장에 |fflush(file[handle])|를 곁들이면 \CEE/에서 같은 효과를 낸다.

\bull \.{Fputs}|(handle,string)|.
파일 핸들은 \.{TextWrite}, \.{BinaryWrite}, \.{BinaryReadWrite} 가운데 한 방식으로 열려
있어야 한다.
@.Fputs@>
주소 |string|에서 시작해서, 0인 첫 바이트의 앞까지(그 바이트는 빼고) \MMIX의 메모리에 있는
한 바이트 문자들을 파일에 쓴다. 쓴 바이트의 개수를 돌려주고, 오류가 나면 $-1$을
돌려준다. \CEE/ 판은
$$\hbox{|fputs(string,file[handle])>=0? strlen(string): -1|}$$
에 |fflush(file[handle])|를 곁들인 것이다.

\bull \.{Fputws}|(handle,string)|.
파일 핸들은 \.{TextWrite}, \.{BinaryWrite}, \.{BinaryReadWrite} 가운데 한 방식으로 열려
있어야 한다.
@.Fputws@>
주소 |string|에서 시작해서, 0인 첫 와이드의 앞까지(그 와이드는 빼고) \MMIX의 메모리에
있는 와이드 문자들을 파일에 쓴다. 쓴 와이드의 개수를 돌려주고, 오류가 나면 $-1$을
돌려준다. \CEE/+MSE 판은
$$\hbox{|fputws(string,file[handle])>=0? wcslen(string): -1|}$$
에 |fflush(file[handle])|를 곁들인 것이다. 여기서 |string|의 타입은 이제 |wchar_t*|다.

\bull \.{Fseek}|(handle,offset)|.
파일 핸들은 \.{BinaryRead}, \.{BinaryWrite}, \.{BinaryReadWrite} 가운데 한 방식으로
열려 있어야 한다.
@.Fseek@>
이 연산을 하면 다음 입력이나 출력 연산이, |offset>=0|이면 파일의 시작에서 |offset|
바이트인 곳에서, |offset<0|이면 파일의 끝에서 |-offset-1| 바이트 앞인 곳에서 시작한다.
(이를테면 |offset=0|이면 파일을 맨 처음으로 ``되감고'', |offset=-1|이면 끝까지 쭉
나아간다.) 결과는 성공하면 0이고, 말한 위치로 옮길 수 없으면 $-1$이다. \CEE/ 판은
$$\hbox{|fseek(file[handle],@,offset<0? offset+1: offset,@,
              offset<0? SEEK_END: SEEK_SET)|? $-1$: 0}$$
이다. 방식이 \.{BinaryReadWrite}인 파일을 읽기와 쓰기에 모두 쓴다면, 입력에서 출력으로,
또는 출력에서 입력으로 바꿀 때 \.{Fseek} 명령을 주어야 한다.

\bull \.{Ftell}|(handle)|.
파일 핸들은 \.{BinaryRead}, \.{BinaryWrite}, \.{BinaryReadWrite} 가운데 한 방식으로
열려 있어야 한다.
@.Ftell@>
이 연산은 현재 파일 위치를 파일의 처음에서부터 센 바이트 수로 돌려주고, 오류가 생겼으면
$-1$을 돌려준다. 이 경우에는 \CEE/ 함수
$$\hbox{|ftell(file[handle])|}$$
가 정확히 같은 뜻을 가진다.

\smallskip
이 열 가지 연산은 아주 원시적이지만, 대단히 복잡한 입출력 동작에 필요한 기능을 다
제공한다. 이를테면 \CEE/의 \.{stdio} 라이브러리에 있는 함수들은, 관리용 연산인
\\{remove}와 \\{rename} 둘을 빼면 모두, 기본 연산 여섯 가지 \.{Fopen}, \.{Fclose},
\.{Fread}, \.{Fwrite}, \.{Fseek}, \.{Ftell}로 서브루틴을 만들어 구현할 수 있다.

\MMIX의 함수 호출이 \CEE/ 라이브러리의 것보다 훨씬 일관성이 있다는 데 주목하라. 첫째
인자는 늘 핸들이다. 둘째 인자가 있다면 늘 주소다. 셋째 인자가 있다면 늘 크기다. {\it
돌려주는 결과는, 연산이 성공했으면 늘 음이 아니고, 이상한 일이 생겼으면 음수다.} 이런
공통의 성질 덕분에 이 함수들은 꽤 기억하기 쉽다.

@ 앞 절의 입출력 연산 열 가지는 $\rm X=0$이고 Y가 \.{Fopen}이나 \.{Fclose}나
\dots~\.{Ftell}이고 Z가 \.{Handle}인 \.{TRAP} 명령으로 부른다. 인자가 둘이면 둘째
인자를 \$255에 둔다. 인자가 셋이면 둘째 인자의 주소를 \$255에 둔다. 그러면 둘째 인자는
M$_8[\$255]$이고 셋째 인자는 M$_8[\$255+8]$이다. 시스템 호출이 끝나면 돌려주는 값은
\$255에 있다. (아래의 예를 보라.)

@ 사용자 프로그램은 기호 위치 \.{Main}에서 시작한다. 이때 전역 레지스터들은 \.{MMIXAL}
@.Main@>
@:Pool_Segment}\.{Pool\_Segment@>
프로그램의 \.{GREG} 문에 따라 초기화되어 있고, \$255는 \.{Main}의 수치와 같게 되어
있다. 지역 레지스터~\$0은 처음에 {\it 명령줄 인자\/}의 개수로 정해져 있다.
@^command line arguments@>
그리고 지역 레지스터~\$1은 첫째 인자를 가리키는데, 첫째 인자는 늘 프로그램 이름을
가리키는 포인터다. 명령줄 인자는 저마다 문자열을 가리키는 포인터다. 마지막 포인터는
M$_8[\$0\ll3+\$1]$이고, M$_8[\$0\ll3+\$1+8]$은 0이다. (레지스터~\$1은
\.{Pool\_Segment}에 있는 옥타바이트를 가리키고, 명령줄 문자열들도 그 세그먼트에 있다.)
위치 M[\.{Pool\_Segment}]에는 풀 세그먼트에서 아직 쓰지 않은 첫 옥타바이트의 주소가
있다.

레지스터 rA, rB, rD, rE, rF, rH, rI, rJ, rM, rP, rQ, rR은 처음에 0이고, $\rm rL=2$이다.

사용자 프로그램과 함께 적재된 서브루틴 라이브러리가 스스로 초기화해야 할 수도 있다.
테트라바이트 M$_4[\Hex{f0}]$에 명령이 적재되어 있으면, 시뮬레이터는 실제로 \.{Main}이
아니라 \Hex{f0}에서 실행을 시작한다. 이 경우에 \$255에는 \.{Main}의 위치가 있다.
@^subroutine library initialization@>
@^initialization of a user program@>
(\Hex{f0}에 있는 루틴은 다음과 같은 조금 까다로운 명령 열로 시작하면 rL을 늘리지 않고
\.{Main}으로 제어를 넘길 수 있다.
$$\.{PUT rW,\$255;{ } PUT rB,\$255;{ } SETML \$255,\#F700;{ } % PUTI rB,0!
      PUT rX,\$255}$$
그리고 마지막에 \.{RESUME}을 하면 된다. 이 \.{RESUME} 명령이 \$255와 rB를 되살린다. 그러나
사용자 프로그램은 rL이 처음에 2라는 사실에 {\it 기대지는\/} 말아야 한다.)

@ 주 프로그램은 \MMIX가 시스템 호출 \.{TRAP}~\.{0}을 실행하면 끝난다. 이 호출은 뜻을
분명히 하려고 흔히 `\.{TRAP}~\.{0,Halt,0}'이라고 기호로 쓴다. 그때 \$255에 든 값은
\CEE/의 |exit| 문에서처럼 주 프로그램이 ``돌려주는'' 값으로 여긴다. 0이 아닌 값은
비정상적인 끝남을 나타낸다. 프로그램이 끝나면 열린 파일은 모두 닫힌다.
@.Halt@>

@ 이를테면 다음은 복사할 파일의 이름을 받아서 그 텍스트 파일을 표준 출력에 복사하는 완전한
프로그램이다. 필요한 오류 검사가 모두 들어 있다.
\vskip-14pt
$$\baselineskip=10pt
\obeyspaces\halign{\qquad\.{#}\hfil\cr
* SAMPLE PROGRAM: COPY A GIVEN FILE TO STANDARD OUTPUT\cr
\noalign{\smallskip}
t        IS   \$255\cr
argc     IS   \$0\cr
argv     IS   \$1\cr
s        IS   \$2\cr
Buf\_Size IS   1000\cr
{}         LOC  Data\_Segment\cr
Buffer   LOC  @@+Buf\_Size\cr
{}         GREG @@\cr
Arg0     OCTA 0,TextRead\cr
Arg1     OCTA Buffer,Buf\_Size\cr
\noalign{\smallskip}
{}         LOC  \#200              main(argc,argv) \{\cr
Main     CMP  t,argc,2          if (argc==2) goto openit\cr
{}         PBZ  t,OpenIt\cr
{}         GETA t,1F              fputs("Usage: ",stderr)\cr
{}         TRAP 0,Fputs,StdErr\cr
{}         LDOU t,argv,0          fputs(argv[0],stderr)\cr
{}         TRAP 0,Fputs,StdErr\cr
{}         GETA t,2F              fputs(" filename\\n",stderr)\cr
Quit     TRAP 0,Fputs,StdErr    \cr
{}         NEG  t,0,1             quit: exit(-1)\cr
{}         TRAP 0,Halt,0\cr
1H       BYTE "Usage: ",0\cr
{}         LOC  (@@+3)\&-4          align to tetrabyte\cr
2H       BYTE " filename",\#a,0\cr
\noalign{\smallskip}
OpenIt   LDOU s,argv,8          openit: s=argv[1]\cr
{}         STOU s,Arg0\cr
{}         LDA  t,Arg0            fopen(argv[1],"r",file[3])\cr
{}         TRAP 0,Fopen,3\cr
{}         PBNN t,CopyIt          if (no error) goto copyit\cr
{}         GETA t,1F              fputs("Can't open file ",stderr)\cr
{}         TRAP 0,Fputs,StdErr\cr
{}         SET  t,s               fputs(argv[1],stderr)\cr
{}         TRAP 0,Fputs,StdErr\cr
{}         GETA t,2F              fputs("!\\n",stderr)\cr
{}         JMP  Quit              goto quit\cr
1H       BYTE "Can't open file ",0\cr
{}         LOC  (@@+3)\&-4          align to tetrabyte\cr
2H       BYTE "!",\#a,0\cr
\noalign{\smallskip}
CopyIt   LDA  t,Arg1            copyit:\cr
{}         TRAP 0,Fread,3         items=fread(buffer,1,buf\_size,file[3])\cr
{}         BN   t,EndIt           if (items < buf\_size) goto endit\cr
{}         LDA  t,Arg1            items=fwrite(buffer,1,buf\_size,stdout)\cr
{}         TRAP 0,Fwrite,StdOut\cr
{}         PBNN t,CopyIt          if (items >= buf\_size) goto copyit\cr
Trouble  GETA t,1F              trouble: fputs("Trouble w...!",stderr)\cr
{}         JMP  Quit              goto quit\cr
1H       BYTE "Trouble writing StdOut!",\#a,0\cr
\noalign{\smallskip}
EndIt    INCL t,Buf\_Size\cr
{}         BN   t,ReadErr         if (ferror(file[3])) goto readerr\cr
{}         STO  t,Arg1+8\cr
{}         LDA  t,Arg1            n=fwrite(buffer,1,items,stdout)\cr
{}         TRAP 0,Fwrite,StdOut\cr
{}         BN   t,Trouble         if (n < items) goto trouble\cr
{}         TRAP 0,Halt,0          exit(0)\cr
ReadErr  GETA t,1F              readerr: fputs("Trouble r...!",stderr)\cr
{}         JMP  Quit              goto quit \}\cr
1H       BYTE "Trouble reading!",\#a,0\cr
}$$
보충: 오른쪽 열은 각 명령에 해당하는 \CEE/ 코드다. 이 프로그램은 크누스의 꾸러미에
\.{copy.mms}로 들어 있다.

@* 기초. 원본은 먼저 의미상의 편의를 주는 타입 |bool|을 정의했다. \GO/에는 이미 있다.

@ 이 64비트 \MMIX\ 아키텍처용 프로그램은 32비트 정수 산술에 바탕을 두고 있다. 1999년에 이
글을 쓸 무렵 크누스가 쓸 수 있던 컴퓨터가 거의 다 그런 제약을 받았기 때문이다. 이
프로그램은 {\mc MMIX-ARITH} 모듈의 서브루틴을 쓰는데, 타입 \KW{tetra}가 부호 없는 32비트
정수를 나타낸다는 것만 가정한다. 여기서 준 \KW{tetra}의 정의는, 필요하다면 그 모듈의
정의와 맞도록 고쳐야 한다.
@^system dependencies@>

보충: 옮긴이는 \.{mmixarith}에서처럼 옥타바이트를 두 테트라의 구조체가 아니라 64비트
부호 없는 정수로 나타냈다. 정의는 \.{mmixarith}의 것을 그대로 쓴다. 원본은 서브루틴을 새
컴파일러에서도 옛 컴파일러에서도 선언하려고 \.{ARGS} 매크로를 두었는데, \GO/에서는 필요
없다.

@<타입 정의@>=
type (
	Tetra = mmixarith.Tetra // 부호 없는 32비트 정수
	Octa  = mmixarith.Octa  // 두 테트라바이트가 모여 옥타바이트를 이룬다
)

@ 원본의 |print_hex|는 윗 테트라가 0이 아닐 때 |"%x%08x"|로, 0일 때 |"%x"|로 찍었다. 64비트
수를 |"%x"|로 찍는 것과 같다.

@<함수들@>=
func (m *simulator) printHex(o Octa) {
	m.printf("%x", o)
}

@ 보충: 원본은 경고와 오류 알림을 |fprintf(stderr,...)|로 찍었다. 원본을 시험한 macOS에서는
|stderr|의 오류 표시가 켜져 있으면 |fprintf|가 아무것도 쓰지 않는다. 모의 프로그램이 홀수
주소에서 \.{Fputws}를 하면 그런 일이 생길 수 있다(|MMGetChars|의 설명을 보라). 그래서
표준 오류에 쓰는 일은 모두 이 메서드를 거치고, 오류 표시는 \.{mmixio}에게 묻는다.

@<함수들@>=
func (m *simulator) eprintf(format string, a ...any) {
	if !m.io.StderrError() {
		fmt.Fprintf(m.stderr, format, a...)
	}
}

@ 보충: 원본의 |printf|처럼 표준 출력 버퍼에 쓰는 메서드를 하나 둔다. 한 바이트를 쓸 때는
|m.out.WriteByte|를 쓴다. \GO/의 \.{\%c}는 128 이상인 바이트를 UTF-8의 두 바이트로
찍어 버리기 때문이다.

@<함수들@>=
func (m *simulator) printf(format string, a ...any) {
	fmt.Fprintf(m.out, format, a...)
}

@ {\mc MMIX-ARITH}의 서브루틴 대부분은 옥타바이트 둘의 함수로서 옥타바이트 하나를
돌려준다. 이를테면 |oplus(y,z)|는 옥타바이트 |y|와~|z|의 합을 돌려준다. 나눗셈은
피제수의 윗부분을 전역 변수~|aux|로 받고, 나머지를 |aux|로 돌려준다.

보충: 옮긴 \.{mmixarith}에는 전역 변수가 없다. 나머지, 넘침, 예외 비트는 모두 둘째와 셋째
반환값으로 돌아오고, 반올림 방식은 매개변수로 넘긴다. 원본이 \.{extern}으로 선언한
서브루틴 가운데 |oplus|, |ominus|, |incr|, |oand|, |shift_left|는 \GO/의 연산자가 되고,
|omult|와 |count_bits|는 \.{math/bits}의 |bits.Mul64|와 |bits.OnesCount64|가 된다. 나머지는
\.{mmixarith}에서 이름만 \GO/식으로 바뀐 채 그대로 쓴다. 원본의 |print_float|는 문자열을
돌려주는 |mmixarith.FloatString|이 된다. 자주 쓰는 상수 둘에는 짧은 이름을 붙여 둔다.

@<상수@>=
const (
	signBit = mmixarith.SignBit // 부호 비트
	negOne  = mmixarith.NegOne  // $-1$
)

@ 원본은 여기서 산술이 제대로 되는지 빨리 검사해 보았다. 타입 \KW{tetra}를 잘못
정의했다면 |shift_left(neg_one,1)|의 윗 테트라가 \Hex{ffffffff}가 아닐 것이다. \GO/에서는
타입이 크기를 보장하므로 이 검사를 뺐다. 그러나 그 검사가 쓰던 |panic| 매크로는 다른
곳에서도 쓰므로 메서드로 남긴다.
@.Incorrect implementation...@>

@<함수들@>=
func (m *simulator) panic(msg string) {
	m.eprintf("Panic: %s!\n", msg)
	panic(exitSignal(-2))
}

@ 옥타바이트를 부호 있는 정수로 보고 싶을 때는 이진수를 십진수로 바꾼다. 이때 항등식
$\lfloor(an+b)/10\rfloor= \lfloor a/10\rfloor n+\lfloor((a\bmod 10)n+b)/10\rfloor$가
쓸모 있다.

보충: 원본은 이 항등식으로 32비트 산술만 써서 64비트 수를 10으로 나누었다. \GO/에서는
64비트 수를 부호 있는 정수로 바꾸어 |strconv.FormatInt|에 넘기면 된다. 가장 작은 수 $-2^{63}$도
원본처럼 \.{-9223372036854775808}로 찍힌다.

@<함수들@>=
func (m *simulator) printInt(o Octa) {
	m.out.WriteString(strconv.FormatInt(int64(o), 10))
}

@* 모의 메모리. 모의 메모리는 2048바이트짜리 덩이들로 나누어, Vuillemin과 Aragon과
Seidel의 발상에 따라 {\it treap\/}으로 짜인 나무 구조에 둔다
@^Vuillemin, Jean Etienne@>
@^Aragon, Cecilia Rodriguez@>
@^Seidel, Raimund@>
[{\sl Communications of the ACM\/ \bf23} (1980), 229--239;
{\sl IEEE Symp.\ on Foundations of Computer Science\/ \bf30} (1989), 540--546].
이 treap의 각 노드에는 열쇠가 둘 있다. 하나는 |loc|이라는 것으로, 모의 테트라바이트 512개의
기준 주소다. 이 열쇠는 보통의 이진 탐색 나무의 관례를 따른다. 곧 왼쪽 부분 나무의 모든
위치는 노드의 |loc|보다 작고, 오른쪽 부분 나무의 모든 위치는 그 |loc|보다 크다. 다른
하나는 |stamp|라는 것으로, 그 노드를 나무에 넣은 시각이라고 생각하면 된다. 어떤 노드의
모든 아랫노드는 더 큰 |stamp|를 가진다. 시간 도장을 무작위로 매기면 거의 언제나 꽤 균형이
잡힌 나무 구조를 유지할 수 있다.

모의 테트라바이트마다 빈도수와 원시 파일 참조가 딸려 있다.

@<타입 정의@>=
type memTetra struct {
	tet    Tetra  // 모의 메모리의 테트라바이트
	freq   Tetra  // 그것을 명령으로 실행한 횟수
	bkpt   byte   // 이 테트라바이트의 멈춤점 정보
	fileNo byte   // 알려져 있다면, 원시 파일 번호
	lineNo uint16 // 알려져 있다면, 원시 줄 번호
}
@#
type memNode struct {
	loc         Octa          // 모의 테트라바이트 512개 가운데 첫째의 위치
	stamp       Tetra         // treap의 균형을 위한 시간 도장
	left, right *memNode      // 부분 나무를 가리키는 포인터
	dat         [512]memTetra // 모의 테트라바이트의 덩이
}

@ 시간 도장 |stamp|의 값은 사실 의사 난수일 뿐이다. 피보나치 해싱의 발상에 바탕을 두었다({\sl
Sorting and Searching}, 6.4절을 보라). 우리 목적에는 이것으로 충분하고, 두 도장이 같아지는
일도 없다.

보충: 원본은 |calloc|이 실패하면 ``\.{Can't allocate any more memory}''라고 알리고
끝냈다. \GO/에서는 메모리가 모자라면 런타임이 프로그램을 끝낸다.
@.Can't allocate...@>

@<함수들@>=
func (m *simulator) newMem() *memNode {
	p := &memNode{stamp: m.priority}
	m.priority += 0x9e3779b9 // $\lfloor2^{32}(\phi-1)\rfloor$
	return p
}

@ 처음에는 풀 세그먼트를 위한 덩이 하나로 시작한다. 시뮬레이터는 프로그램을 돌리기 전에
거기에 명령줄 정보를 넣기 때문이다.

@<모든 것을 초기화한다@>=
m.memRoot = m.newMem()
m.memRoot.loc = 0x4000000000000000
m.lastMem = m.memRoot

@ @<시뮬레이터의 상태@>=
priority Tetra    // 의사 난수 시간 도장 계수기
memRoot  *memNode // treap의 뿌리
lastMem  *memNode // 가장 최근에 읽거나 쓴 메모리 노드
sclock   Octa     // 모의 시계

@ @<시뮬레이터의 초깃값@>=
priority: 314159265,

@ 메서드 |memFind|는 모의 메모리에서 주어진 테트라바이트를 찾는다. 필요하면 treap에 새
노드를 넣는다.

보충: 원본은 테트라바이트를 가리키는 포인터 |ll|을 돌려주었고, 부르는 쪽은 옥타바이트의
아랫 테트라를 |ll+1|로 얻었다. \GO/에서는 덩이의 배열을 그 테트라바이트에서부터 자른
슬라이스를 돌려준다. 그러면 |ll[0]|이 원본의 |*ll|, |ll[1]|이 원본의 |*(ll+1)|이 된다.
원본은 테트라 둘을 따로 견주어 |key|가 |p->loc|보다 작은지를 가렸는데, 그것은 64비트 수의
비교 |key<p.loc|와 같다.

@<함수들@>=
func (m *simulator) memFind(addr Octa) []memTetra {
	key := addr &^ 0x7ff
	offset := addr & 0x7fc
	p := m.lastMem
	if p.loc != key {
		@<treap에서 |key|를 찾아 |lastMem|과 |p|를 그 위치로 정한다@>
	}
	return p.dat[offset>>2:]
}

@ 첫 루프는 이미 있는 노드를 찾는다. 없으면 둘째 루프가 새 노드를 넣을 자리를 찾는다. 그
자리는 도장이 새 노드의 도장보다 작은 노드들 아래다.

보충: 원본은 찾은 경우에 |goto found|로 넣는 부분을 건너뛰었다. 여기서는 첫 루프를
|break|로 빠져나온 뒤 |p|가 |nil|인지를 본다.

@<treap에서 |key|를 찾아...@>=
for p = m.memRoot; p != nil; {
	if key == p.loc {
		break
	}
	if key < p.loc {
		p = p.left
	} else {
		p = p.right
	}
}
if p == nil {
	q := &m.memRoot
	for p = m.memRoot; p != nil && p.stamp < m.priority; p = *q {
		if key < p.loc {
			q = &p.left
		} else {
			q = &p.right
		}
	}
	*q = m.newMem()
	(*q).loc = key
	@<|*q|의 부분 나무들을 바로잡는다@>
	p = *q
}
m.lastMem = p

@ 여기서는 이진 탐색 나무 |p|를 주어진 |key|에 따라 두 부분으로 쪼개어, 새 노드~|q|의
왼쪽과 오른쪽 부분 나무로 만들고 싶다. 그 결과는 |key|를 |p|의 모든 노드보다 먼저 넣은
것과 같다.

@<|*q|의 부분 나무들을 바로잡는다@>=
l, r := &(*q).left, &(*q).right
for p != nil {
	if key < p.loc {
		*r = p
		r = &p.left
		p = *r
	} else {
		*l = p
		l = &p.right
		p = *l
	}
}
*l, *r = nil, nil

@* 목적 파일 싣기. 사용자의 프로그램을 메모리에 넣으려면 \MMIX\ 목적 파일을 읽어야 한다.
이 일에는 유틸리티 프로그램 \.{MMOtype}의 루틴들을 고쳐 쓴다. 목적 파일 형식 \.{mmo}의 자세한
사항은 모두 {\mc MMIXAL}의 프로그램에 나온다. 이 장을 이해하고 싶은 독자는 적어도 그
문서를 훑어보아야 한다. 여기서는 해석에 쓰이는 기본 상수들만 정의하면 된다.

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

@ 기호표는 싣지 않는다. (더 야심 찬 시뮬레이터라면 대화식 디버깅을 위해 \.{MMIXAL} 식의
식을 구현할 수도 있겠지만, 그런 개선은 관심 있는 독자에게 맡긴다.)

보충: 목적 파일의 이름은 명령줄에서 옵션들 다음에 오는 인자 |args[curArg]|다. 원본은 이것을
매크로 |mmo_file_name|이라고 불렀다. 그 이름의 파일이 없으면 끝에 \.{.mmo}를 붙여 본다.
원본은 그렇게 만든 이름을 담을 버퍼를 할당하지 못하면 ``\.{Can't allocate file name
buffer}''라고 알리고 끝냈다.
@.Can't allocate...@>

@<모든 것을 초기화한다@>=
mf, err := os.Open(args[curArg])
if err != nil {
	altName := args[curArg] + ".mmo"
	mf, err = os.Open(altName)
	if err != nil {
		m.eprintf("Can't open the object file %s or %s!\n",
@.Can't open...@>
			args[curArg], altName)
		return -3
	}
}
m.mmoFile = bufio.NewReader(mf)

@ 보충: 원본에는 다음 바이트의 색인 |byte_count|도 있었다. 그것은 아래에서 말하는
|read_byte|만 썼다.

@<시뮬레이터의 상태@>=
mmoFile *bufio.Reader // 입력 파일
buf     [4]byte       // 가장 최근에 읽은 바이트들
yzbytes int           // 가장 아래의 두 바이트
tet     Tetra         // |buf|의 바이트들을 큰 쪽 먼저로 모은 것

@ 보충: 원본의 전역 변수 가운데 |postamble|과 |delta|는 |main|에서만 쓰므로 지역 변수다.
이런 지역 변수들은 이 절의 이어붙임으로 모아서 |mmix|의 첫머리에 선언한다.

@<지역 변수@>=
postamble bool // |lopPost|를 만났는가?
delta     int  // 상대 주소 고치기의 차이

@ 목적 파일 \.{mmo}의 테트라바이트들은 다루기 좋은 큰 쪽 먼저(big-endian) 방식으로 저장되어
있다. 그러나 이 프로그램은 작은 쪽 먼저(little-endian)인 컴퓨터에서도 돌아야 한다. 그래서
테트라바이트 하나를 한꺼번에 읽지 않고, 네 바이트를 차례로 읽어서 테트라바이트로 모은다.

@<함수들@>=
func (m *simulator) readTet() {
	if _, err := io.ReadFull(m.mmoFile, m.buf[:]); err != nil {
		m.mmoErr()
	}
	m.yzbytes = int(m.buf[2])<<8 | int(m.buf[3])
	m.tet = Tetra(m.buf[0])<<24 | Tetra(m.buf[1])<<16 | Tetra(m.yzbytes)
}
@#
func (m *simulator) mmoErr() {
	m.eprintf("Bad object file! (Try running MMOtype.)\n")
@.Bad object file@>
	panic(exitSignal(-4))
}

@ 보충: 원본에는 바이트 하나를 읽는 서브루틴 |read_byte|도 있었는데, 이 프로그램의 어디에서도
부르지 않는다. 프로그램 \.{mmotype}에서 가져온 루틴들의 흔적인 듯하다. 옮긴이는 그것을 뺐다.

원본은 |buf[2]|와 |buf[3]|을 매크로 |ybyte|와 |zbyte|로 불렀다.

@<서문을 싣는다@>=
m.readTet() // 입력의 첫 테트라바이트를 읽는다
if m.buf[0] != mm || m.buf[1] != lopPre {
	m.mmoErr()
}
if m.buf[2] != 1 {
	m.mmoErr()
}
if m.buf[3] == 0 {
	m.objTime = 0xffffffff
} else {
	j = int(m.buf[3]) - 1
	m.readTet()
	m.objTime = m.tet // 파일을 만든 시각
	for ; j > 0; j-- {
		m.readTet()
	}
}

@ 보충: 원본은 \.{lop\_spec}의 특수 데이터를 다 읽고 나서 |goto loop|로 새로 읽은
테트라바이트를 처음부터 다시 해석했다. 여기서는 lopcode를 해석하는 루프에 |dispatch|라는
이름표를 붙이고, |continue dispatch|로 그 일을 한다. 원본의 |continue|는 |do|\dots|while|의
조건 검사로 갔는데, 여기서는 |continue items|가 그 일을 한다.

@<다음 항목을 싣는다@>=
m.readTet()
dispatch:
for m.buf[0] == mm {
	switch m.buf[1] {
	case lopQuote:
		if m.yzbytes != 1 {
			m.mmoErr()
		}
		m.readTet()
		break dispatch
	@<주 루프에서 lopcode의 경우들@>
	case lopPost:
		postamble = true
		if m.buf[2] != 0 || m.buf[3] < 32 {
			m.mmoErr()
		}
		continue items
	default:
		m.mmoErr()
	}
}
@<|tet|을 보통의 항목으로 싣는다@>

@ 보통의 경우에는 새로 읽은 테트라바이트를 현재 위치에 싣기만 하면 된다. 현재 줄 |curLine|이 0이
아니고 현재 위치 |curLoc|이 세그먼트~0에 있으면, 현재 위치뿐 아니라 현재의 파일 위치도 싣는다.

보충: 실제 코드는 |curLoc|이 세그먼트~0에 있는지를 따지지 않는다.

원본의 매크로 |mmo_load|는 메모리에 값을 싣는데, 그 자리에 있던 값과 배타적 논리합을
한다. 이 매크로를 메서드로 옮겼다.

@<|tet|을 보통의 항목으로...@>=
ll = m.mmoLoad(curLoc, m.tet)
if m.curLine != 0 {
	ll[0].fileNo = byte(m.curFile)
	ll[0].lineNo = uint16(m.curLine)
	m.curLine++
}
curLoc = (curLoc + 4) &^ 3

@ @<함수들@>=
func (m *simulator) mmoLoad(loc Octa, val Tetra) []memTetra {
	ll := m.memFind(loc)
	ll[0].tet ^= val
	return ll
}

@ @<지역 변수@>=
curLoc Octa // 현재 위치

@ 보충: 원본의 전역 변수 |tmp|는 \.{lop\_fixo}에서만 쓰므로 그 경우의 지역 변수가 되었다.

@<시뮬레이터의 상태@>=
curFile int   // 가장 최근에 고른 파일 번호
curLine int   // 0이 아니면, |curFile|에서의 현재 위치
objTime Tetra // 목적 파일을 만든 시각

@ @<시뮬레이터의 초깃값@>=
curFile: -1,

@ 보충: 원본은 |do|\dots|while| 루프로 후기를 만날 때까지 항목을 읽었다. 표시 |postamble|이
처음에 거짓이므로 조건을 앞에 둔 루프도 첫 바퀴는 어차피 돈다.

@<모든 것을 초기화한다@>=
curLoc = 0
m.curFile = -1
m.curLine = 0
@<서문을 싣는다@>
items:
for !postamble {
	@<다음 항목을 싣는다@>
}
@<후기를 싣는다@>
mf.Close()
m.curLine = 0

@ 우리는 이미 \.{lop\_quote}를 구현했다. 이것은 테트라바이트 하나를 더 읽은 뒤 보통의
경우로 넘어간다. 이제 다른 lopcode들을 차례로 살펴보자.

보충: 원본은 \.{lop\_loc}과 \.{lop\_fixo}에서 주소를 읽는 같은 코드를 두 번 썼다. 옮긴이는
그것을 메서드 |readAddress|로 묶었다. 그 lopcode의 Z~바이트가 2이면 Y~바이트가 윗 테트라의 맨 윗
바이트가 되고, 그다음 테트라바이트가 거기에 더해진다.

@<주 루프에서 lopcode의 경우들@>=
case lopLoc:
	curLoc = m.readAddress()
	continue items
case lopSkip:
	curLoc += Octa(m.yzbytes)
	continue items

@ @<함수들@>=
func (m *simulator) readAddress() Octa {
	var h Tetra
	switch m.buf[3] {
	case 2:
		j := Tetra(m.buf[2])
		m.readTet()
		h = j<<24 + m.tet
	case 1:
		h = Tetra(m.buf[2]) << 24
	default:
		m.mmoErr()
	}
	m.readTet()
	return Octa(h)<<32 | Octa(m.tet)
}

@ 고치기(fixup)는 앞으로의 참조가 풀렸을 때 정보를 순서 없이 싣는다. 현재의 파일 이름과
줄 번호는 여기에 상관이 없다고 본다.

보충: 원본은 \.{lop\_fixr}에서 |goto fixr|로 \.{lop\_fixrx}의 뒷부분에 뛰어들었다. 여기서는
두 경우를 하나로 묶었다. lopcode \.{lop\_fixr}에서는 |delta|가 \Hex{1000000}보다 작으므로 |j|를
쓰지 않는다.

@<주 루프에서 lopcode의 경우들@>=
case lopFixo:
	tmp := m.readAddress()
	m.mmoLoad(tmp, Tetra(curLoc>>32))
	m.mmoLoad(tmp+4, Tetra(curLoc))
	continue items
case lopFixr, lopFixrx:
	if m.buf[1] == lopFixr {
		delta = m.yzbytes
	} else {
		j = m.yzbytes
		if j != 16 && j != 24 {
			m.mmoErr()
		}
		m.readTet()
		delta = int(m.tet)
		if delta&0xfe000000 != 0 {
			m.mmoErr()
		}
	}
	d := delta
	if delta >= 0x1000000 {
		d = delta&0xffffff - 1<<j
	}
	m.mmoLoad(curLoc-Octa(d<<2), Tetra(delta))
	continue items

@ 파일 이름을 담을 공간은 그것이 필요하다는 것이 확실해질 때까지 할당하지 않는다.

보충: 원본은 이름을 \CEE/ 문자열로 담았으므로 널 문자에서 이름이 끝났다. 여기서도 첫 널
문자에서 자른다. 원본은 |name|이 널 포인터인지로 그 번호의 이름이 있는지를 알았다.
\GO/에서도 |make|로 만든 슬라이스는 길이가 0으로 잘려도 |nil|이 아니므로 같은 검사가
통한다. 원본은 이름을 담을 공간을 할당하지 못하면 ``\.{No room to store the file name!}''
이라고 알리고 종료 코드 $-5$로 끝냈다.
@.No room...@>

@<주 루프에서 lopcode의 경우들@>=
case lopFile:
	if m.fileInfo[m.buf[2]].name != nil {
		if m.buf[3] != 0 {
			m.mmoErr()
		}
		m.curFile = int(m.buf[2])
	} else {
		if m.buf[3] == 0 {
			m.mmoErr()
		}
		name := make([]byte, 0, 4*int(m.buf[3]))
		m.curFile = int(m.buf[2])
		for j = int(m.buf[3]); j > 0; j-- {
			m.readTet()
			name = append(name, m.buf[:]...)
		}
		if n := bytes.IndexByte(name, 0); n >= 0 {
			name = name[:n]
		}
		m.fileInfo[m.curFile].name = name
	}
	m.curLine = 0
	continue items
case lopLine:
	if m.curFile < 0 {
		m.mmoErr()
	}
	m.curLine = m.yzbytes
	continue items

@ 특수 바이트들은 (적어도 지금은) 무시한다.

@<주 루프에서 lopcode의 경우들@>=
case lopSpec:
	for {
		m.readTet()
		if m.buf[0] == mm {
			if m.buf[1] != lopQuote || m.yzbytes != 1 {
				continue dispatch // 특수 데이터의 끝
			}
			m.readTet()
		}
	}

@ 메모리의 덩이 하나에는 테트라바이트가 512개 들어 있다. 그래서 다음 루프에서 |ll|은
같은 덩이, 곧 세그먼트~3(\.{Stack\_Segment}라고도 한다)의 첫 덩이 안에 머문다.
@:Stack_Segment}\.{Stack\_Segment@>
@:Pool_Segment}\.{Pool\_Segment@>

보충: 원본은 주소 \Hex{6000000000000018}을 찾아 |ll|로 삼고, |ll-1|이나 |ll-5|처럼 그
앞의 테트라바이트들도 썼다. \GO/의 슬라이스는 음수 색인을 쓸 수 없으므로, 여기서는 덩이의
처음부터 자른 슬라이스를 쓴다. 그러면 원본의 |ll| 자리는 색인 6이다. 후기의 Z~바이트가
|G|이고, 그 뒤에 전역 레지스터 |G|부터 255까지의 값이 테트라바이트 둘씩 온다.

@<후기를 싣는다@>=
ll = m.memFind(0x6000000000000000)
ll[5].tet = 2 // 이것이 결국 $\rm rL=2$로 만든다
ll[1].tet = Tetra(argc) // 그리고 $\$0=|argc|$로
ll[2].tet = 0x40000000
ll[3].tet = 0x8 // 그리고 $\$1=\.{Pool\_Segment}+8$로 만든다
G, L = int(m.buf[3]), 0
for j, k = G+G, 6; j < 256+256; j, k = j+1, k+1 {
	m.readTet()
	ll[k].tet = m.tet
}
m.instPtr = Octa(ll[k-2].tet)<<32 | Octa(ll[k-1].tet) // \.{Main}
ll[k+2*12].tet = Tetra(G) << 24
m.g[255] = 0x6000000000000000 + Octa(4*k) + 12*8 // 여기서부터 \.{UNSAVE}해서 출발한다

@* 원시 줄을 싣고 찍기. 실린 프로그램에는 대개 기호로 된 원시 파일의 줄들을 가리키는 상호
참조가 들어 있다. 그래서 명령마다 그 문맥을 알 수 있다. 이 프로그램의 다음 절들은 그런
정보를 원할 때 쓸 수 있게 해 준다.

원시 파일의 데이터는 \KW{fileNode} 구조체에 둔다.

@<타입 정의@>=
type fileNode struct {
	name      []byte  // 원시 파일의 이름
	lineCount int     // 파일의 줄 수
	lineMap   []int64 // 줄마다의 파일 위치를 적은 지도
}

@ 원시 파일이 유니코드로 된 날을 조금이나마 대비해서, 원시 파일의 문자를 나타내는 타입
\KW{Char}를 정의한다.

@<타입 정의@>=
type Char = byte // 언젠가 와이드가 될 바이트들

@ @<시뮬레이터의 상태@>=
fileInfo [256]fileNode // 원시 파일마다의 데이터
bufSize  int           // 원시 줄 버퍼의 크기
buffer   []Char

@ 어셈블러 \.{MMIXAL}에서처럼 원시 줄은 72자 이하가 좋다. 그러나 사용자가 그 한계를 늘릴 수 있다.
(시뮬레이터가 줄을 보여 줄 때, 더 긴 줄은 버퍼 크기에 맞게 조용히 잘린다.)

보충: 원본은 버퍼를 할당하지 못하면 ``\.{Can't allocate source line buffer}''라고
알렸다.
@.Can't allocate...@>

@<모든 것을 초기화한다@>=
if m.bufSize < 72 {
	m.bufSize = 72
}
m.buffer = make([]Char, m.bufSize+1)

@ 주어진 원시 파일에서 줄을 처음 보여 달라는 요청을 받으면, 줄마다의 시작 위치를 적은
지도를 만든다. 원시 파일은 65535줄을 넘지 않아야 한다. 원시 파일에 널 문자는 없다고
가정한다.

보충: 원본은 이 일을 서브루틴 |make_map|으로 했는데, 부르는 곳이 한 군데뿐이어서 여기서는
절로 두었다. 원본은 |fgets|로 버퍼 크기만큼씩 읽다가, 읽은 것이 줄 바꿈 문자로 끝나지
않으면 |goto loop|로 그 줄의 나머지를 더 읽었다. 함수 |fgets|가 실패하면 그 줄은 줄 수에 넣지
않는다. 그래서 줄 바꿈 문자로 끝나지 않는 마지막 줄은 지도에 오르지 않고, 원본에서처럼
결코 보이지 않는다. 버퍼의 첫 문자가 널 문자이면 원본은 |buffer[-1]|을 읽었는데, 여기서는
줄 바꿈 문자가 아닌 것으로 친다.

@<줄마다의 파일 위치를 적은 지도를 만든다@>=
@<원시 파일이 바뀌었는지 검사한다@>
lineMap := []int64{0} // 색인 0은 쓰지 않는다
l := 1
lines:
for ; l < 65536 && !m.srcFile.eof; l++ {
	pos := m.srcFile.pos // |ftell(src_file)|
	for {
		if !m.srcFile.fgets(m.buffer, m.bufSize) {
			break lines
		}
		if n := strlen(m.buffer); n > 0 && m.buffer[n-1] == '\n' {
			break
		}
	}
	lineMap = append(lineMap, pos)
}
m.fileInfo[m.curFile].lineCount = l
m.fileInfo[m.curFile].lineMap = lineMap

@ 원시 파일이 목적 파일을 쓴 뒤에 바뀌었다면 사용자에게 경고하고 싶다. 표준 \CEE/
라이브러리는 우리가 필요로 하는 정보를 주지 않는다. 그래서 \UNIX/의 시스템 함수 |stat|을
쓴다. 다른 운영체제에도 비슷한 방법이 있기를 바란다.
@^system dependencies@>

보충: \GO/에서는 |os.Stat|이 그 일을 한다. 원본은 수정 시각을 32비트로 잘라서 비교했다.

@<원시 파일이 바뀌었는지...@>=
if st, err := os.Stat(string(m.fileInfo[m.curFile].name)); err == nil {
	if Tetra(st.ModTime().Unix()) > m.objTime {
		m.eprintf(
			"Warning: File %s was modified; it may not match the program!\n",
@.File...was modified@>
			m.fileInfo[m.curFile].name)
	}
}

@ 원시 줄은 메서드 |printLine|이 보여 준다. 줄 앞에는 줄 번호를 담은 12문자가 온다. 파일
오류가 생기면 아무것도 찍지 않는다. 오류 알림조차 찍지 않는다. 보여 준 데이터가 없다는
것 자체가 알림이기 때문이다.

보충: 원본의 \.{"line \%.6s \%s"}는 \.{"\%d:\ \ \ \ "}로 만든 문자열의 처음 여섯 문자를
찍는다. 줄 번호가 다섯 자리를 넘지 않으므로 뒤의 빈칸만 잘린다. 원본은 |fseek|에
\.{SEEK\_SET}을 썼고, 옛 라이브러리를 위해 그 값을 대신 정의해 두었다.

@<함수들@>=
func (m *simulator) printLine(k int) {
	fi := &m.fileInfo[m.curFile]
	if k >= fi.lineCount {
		return
	}
	@<원시 파일에서 |k|번째 줄의 자리로 옮기고, 실패하면 |return|한다@>
	if !m.srcFile.fgets(m.buffer, m.bufSize) {
		return
	}
	num := fmt.Sprintf("%d:    ", k)
	n := strlen(m.buffer)
	m.printf("line %s %s", num[:6], m.buffer[:n])
	if n == 0 || m.buffer[n-1] != '\n' {
		m.printf("\n")
	}
	m.lineShown = true
}

@ 보충: 원본은 |fseek|으로 옮겼다. |fseek|은 읽기 버퍼를 버리고 파일 끝 표시를 지운다.

@<원시 파일에서 |k|번째 줄의...@>=
if _, err := m.srcFile.f.Seek(fi.lineMap[k], io.SeekStart); err != nil {
	return
}
m.srcFile.r.Reset(m.srcFile.f)
m.srcFile.pos, m.srcFile.eof = fi.lineMap[k], false

@ 메서드 |showLine|은 원시 파일 번호 |curFile|의 |curLine|번째 줄을 보이고 싶을 때
부른다. 이때 |curLine!=0|이라고 가정한다. 이 메서드가 하는 일은 주로 연속성을 지키는
것이다. 원시 파일이 바뀌면 |srcFile|을 열거나 다시 열고, 앞서 보인 줄들과 새 줄을
이어 준다. 원하는 줄을 이미 찍었다면 아무것도 찍지 않아도 된다.

보충: 원본에서 |gap|과 |shown_line|은 \CEE/의 32비트 |int|였다. 빈틈 |gap|은 명령줄에서 아무
값이나 받을 수 있으므로 |shown_line+gap+1|이 넘칠 수 있다. 원본과 같은 결과를 내도록
여기서도 32비트로 셈한다.

@<함수들@>=
func (m *simulator) showLine() {
	if m.shownFile != m.curFile {
		@<새 원시 파일의 줄을 나열할 준비를 한다@>
	} else if m.shownLine == int32(m.curLine) {
		return // 이미 보였다
	}
	cl := int32(m.curLine)
	if cl > m.shownLine+m.gap+1 || cl < m.shownLine {
		if m.shownLine > 0 {
			if cl < m.shownLine {
				m.printf("--------\n") // 위로 옮긴 것을 나타낸다
			} else {
				m.printf("     ...\n") // 빈틈을 나타낸다
			}
		}
		m.printLine(m.curLine)
	} else {
		for k := m.shownLine + 1; k <= cl; k++ {
			m.printLine(int(k))
		}
	}
	m.shownLine = cl
}

@ @<시뮬레이터의 상태@>=
srcFile              *cfile // 지금 열려 있는 원시 파일
shownFile            int    // 가장 최근에 나열한 파일의 번호
shownLine            int32  // |shownFile|에서 가장 최근에 나열한 줄
gap                  int32  // 잇달아 나열하는 원시 줄 사이의 최소 빈틈
lineShown            bool   // 최근에 무언가를 나열했는가?
showingSource        bool   // 원시 줄을 나열하고 있는가?
profileGap           int32  // 마지막 빈도수를 찍을 때의 |gap|
profileShowingSource bool   // 마지막 빈도수를 찍을 때의 |showingSource|

@ @<시뮬레이터의 초깃값@>=
shownFile: -1,

@ 보충: 원본은 처음에는 |fopen|으로 열고, 그 뒤로는 |freopen|으로 같은 \KW{FILE}을 다시 열었다.
그런데 |freopen|의 결과를 버렸으므로, 다시 열기에 실패하면 |src_file|은 닫힌 \KW{FILE}을
가리킨 채 남는다. 그러면 파일 이름만 찍히고, 그 뒤의 읽기는 모두 실패해서 줄이 하나도
보이지 않는다. 여기서도 다시 열기에 실패하면 닫힌 파일을 그대로 두어 이것을 흉내 낸다. 원시
줄 지도를 만드는 일은 한 곳에서만 하므로 원본의 |make_map|을 절로 두었다.

@<새 원시 파일의 줄을...@>=
name := m.fileInfo[m.curFile].name
if m.srcFile == nil {
	if f, err := os.Open(string(name)); err == nil {
		m.srcFile = newCfile(f)
	}
} else { // |freopen|
	m.srcFile.f.Close()
	if f, err := os.Open(string(name)); err == nil {
		m.srcFile.f = f
	}
	m.srcFile.r.Reset(m.srcFile.f)
	m.srcFile.pos, m.srcFile.eof = 0, false
}
if m.srcFile == nil {
	m.eprintf("Warning: I can't open file %s; source listing omitted.\n",
@.I can't open...@>
		name)
	m.showingSource = false
	return
}
m.printf("\"%s\"\n", name)
m.shownFile = m.curFile
m.shownLine = 0
if m.fileInfo[m.curFile].lineMap == nil {
	@<줄마다의 파일 위치를 적은 지도를 만든다@>
}

@ 다음은 |showLine|의 간단한 응용이다. 재귀 루틴으로, 모의 메모리의 주어진 부분 나무에
있는 명령 가운데 한 번이라도 실행된 것들의 빈도수를 모두 찍는다. 부분 나무를 대칭 순서로
돌므로 빈도수는 명령의 위치가 커지는 순서로 나온다.

@<함수들@>=
func (m *simulator) printFreqs(p *memNode) {
	if p.left != nil {
		m.printFreqs(p.left)
	}
	for j := range 512 {
		if p.dat[j].freq != 0 {
			@<위치 |p.loc+4*j|의 빈도 데이터를 찍는다@>
		}
	}
	if p.right != nil {
		m.printFreqs(p.right)
	}
}

@ 이어지지 않는 명령들의 빈도 데이터 사이에는 말줄임표(\.{...})를 찍는다. 다만 원시 줄
정보가 끼어들면 찍지 않는다.

보충: 원본은 원시 줄을 보였으면 |goto loc_implied|로 말줄임표를 건너뛰었다. 여기서는
|shown|이라는 표시로 그 일을 한다. 원본은 빈도수를 \.{\%10d}로, 곧 부호 있는 32비트
정수로 찍었다.

@<위치 |p.loc+4*j|의 빈도...@>=
curLoc := p.loc + Octa(4*j)
shown := false
if m.showingSource && p.dat[j].lineNo != 0 {
	m.curFile, m.curLine = int(p.dat[j].fileNo), int(p.dat[j].lineNo)
	m.lineShown = false
	m.showLine()
	shown = m.lineShown
}
if !shown && curLoc != m.impliedLoc && m.profileStarted {
	m.printf("         0.        ...\n")
}
m.printf("%10d. %016x: %08x (%s)\n", int32(p.dat[j].freq), curLoc, p.dat[j].tet,
	info[p.dat[j].tet>>24].name)
m.impliedLoc = curLoc + 4
m.profileStarted = true

@ @<시뮬레이터의 상태@>=
impliedLoc     Octa // 마지막으로 보인 빈도 데이터 다음의 위치
profileStarted bool // 빈도수를 하나라도 찍었는가?

@ @<모든 빈도수를 찍는다@>=
m.printf("\nProgram profile:\n")
m.shownFile, m.curFile = -1, -1
m.shownLine, m.curLine = 0, 0
m.gap = m.profileGap
m.showingSource = m.profileShowingSource
m.impliedLoc = negOne
m.printFreqs(m.memRoot)

@* 목록. 이 시뮬레이터는 서로 다른 연산 코드 256개를 다루어야 하므로, 지금 그것들을
열거해 두는 것이 좋겠다.

보충: 원본은 \CEE/의 |enum|으로 열거했다. 여기서는 |iota|로 매긴 상수들이다. 이를테면
\.{2ADDU} 같은 이름은 \GO/의 식별자가 될 수 없으므로 원본처럼 \.{IIADDU}로 쓴다. 원본처럼 한 줄에
여덟 개씩 쓰려고 세미콜론으로 이었다.

@<상수@>=
const (
	TRAP = iota; FCMP; FUN; FEQL; FADD; FIX; FSUB; FIXU
	FLOT; FLOTI; FLOTU; FLOTUI; SFLOT; SFLOTI; SFLOTU; SFLOTUI
	FMUL; FCMPE; FUNE; FEQLE; FDIV; FSQRT; FREM; FINT
	MUL; MULI; MULU; MULUI; DIV; DIVI; DIVU; DIVUI
	ADD; ADDI; ADDU; ADDUI; SUB; SUBI; SUBU; SUBUI
	IIADDU; IIADDUI; IVADDU; IVADDUI; VIIIADDU; VIIIADDUI; XVIADDU; XVIADDUI
	CMP; CMPI; CMPU; CMPUI; NEG; NEGI; NEGU; NEGUI
	SL; SLI; SLU; SLUI; SR; SRI; SRU; SRUI
	BN; BNB; BZ; BZB; BP; BPB; BOD; BODB
	BNN; BNNB; BNZ; BNZB; BNP; BNPB; BEV; BEVB
	PBN; PBNB; PBZ; PBZB; PBP; PBPB; PBOD; PBODB
	PBNN; PBNNB; PBNZ; PBNZB; PBNP; PBNPB; PBEV; PBEVB
	CSN; CSNI; CSZ; CSZI; CSP; CSPI; CSOD; CSODI
	CSNN; CSNNI; CSNZ; CSNZI; CSNP; CSNPI; CSEV; CSEVI
	ZSN; ZSNI; ZSZ; ZSZI; ZSP; ZSPI; ZSOD; ZSODI
	ZSNN; ZSNNI; ZSNZ; ZSNZI; ZSNP; ZSNPI; ZSEV; ZSEVI
	LDB; LDBI; LDBU; LDBUI; LDW; LDWI; LDWU; LDWUI
	LDT; LDTI; LDTU; LDTUI; LDO; LDOI; LDOU; LDOUI
	LDSF; LDSFI; LDHT; LDHTI; CSWAP; CSWAPI; LDUNC; LDUNCI
	LDVTS; LDVTSI; PRELD; PRELDI; PREGO; PREGOI; GO; GOI
	STB; STBI; STBU; STBUI; STW; STWI; STWU; STWUI
	STT; STTI; STTU; STTUI; STO; STOI; STOU; STOUI
	STSF; STSFI; STHT; STHTI; STCO; STCOI; STUNC; STUNCI
	SYNCD; SYNCDI; PREST; PRESTI; SYNCID; SYNCIDI; PUSHGO; PUSHGOI
	OR; ORI; ORN; ORNI; NOR; NORI; XOR; XORI
	AND; ANDI; ANDN; ANDNI; NAND; NANDI; NXOR; NXORI
	BDIF; BDIFI; WDIF; WDIFI; TDIF; TDIFI; ODIF; ODIFI
	MUX; MUXI; SADD; SADDI; MOR; MORI; MXOR; MXORI
	SETH; SETMH; SETML; SETL; INCH; INCMH; INCML; INCL
	ORH; ORMH; ORML; ORL; ANDNH; ANDNMH; ANDNML; ANDNL
	JMP; JMPB; PUSHJ; PUSHJB; GETA; GETAB; PUT; PUTI
	POP; RESUME; SAVE; UNSAVE; SYNC; SWYM; GET; TRIP
)

@ 특수 레지스터의 이름도 열거해야 한다.

@<상수@>=
const (
	rB = iota; rD; rE; rH; rJ; rM; rR; rBB
	rC; rN; rO; rS; rI; rT; rTT; rK; rQ; rU; rV; rG; rL
	rA; rF; rP; rW; rX; rY; rZ; rWW; rXX; rYY; rZZ
)

@ @<표@>=
var specialName = [32]string{"rB", "rD", "rE", "rH", "rJ", "rM", "rR", "rBB",
	"rC", "rN", "rO", "rS", "rI", "rT", "rTT", "rK", "rQ", "rU", "rV", "rG", "rL",
	"rA", "rF", "rP", "rW", "rX", "rY", "rZ", "rWW", "rXX", "rYY", "rZZ"}

@ 다음은 산술 예외의 비트 코드들이다. 트립 비트 |hBit|를 뺀 코드들은 {\mc MMIX-ARITH}에도
정의되어 있다.

@<상수@>=
const (
	xBit = mmixarith.XBit // 부동소수점 부정확
	zBit = mmixarith.ZBit // 부동소수점 0으로 나눔
	uBit = mmixarith.UBit // 부동소수점 아래넘침
	oBit = mmixarith.OBit // 부동소수점 넘침
	iBit = mmixarith.IBit // 부동소수점 잘못된 연산
	wBit = mmixarith.WBit // 부동소수점에서 고정소수점으로 바꿀 때 넘침
	vBit = mmixarith.VBit // 정수 넘침
	dBit = mmixarith.DBit // 정수 나눗셈 검사
	hBit = 1 << 16        // 트립
)

@ 메모리의 테트라바이트마다 딸린 |bkpt| 필드에는 강제 추적, 그리고 읽기와 쓰기와 실행
때의 멈춤에 해당하는 비트들이 있다.

@<상수@>=
const (
	traceBit = 1 << 3
	readBit  = 1 << 2
	writeBit = 1 << 1
	execBit  = 1 << 0
)

@ 목록의 목록을 마무리하려고, \.{MMIXAL}에 들어 있는 초보적인 운영체제 호출들을 열거한다.

@<상수@>=
const (
	Halt = iota; Fopen; Fclose; Fread; Fgets; Fgetws
	Fwrite; Fputs; Fputws; Fseek; Ftell
)
@#
const maxSysCall = Ftell

@* 주 루프. 이제 시뮬레이터의 한복판으로 뛰어들자. 대부분의 동작을 다스리는 큰 스위치다.

보충: 원본은 특권 명령이나 불법 명령을 만나면 |goto privileged_inst|나 |goto
illegal_inst|로 스위치의 끝에 있는 공통 꼬리로 갔다. 여기서는 지역 변수 |trouble|에
\.{"!privileged"}나 \.{"!illegal"}을 넣고, 스위치에 붙인 이름표 |perform|으로 |break|한다.
스위치 다음에서 |trouble|이 비어 있지 않으면 원본의 꼬리가 하던 일을 한다. 원본의
|goto store_x|는 저마다의 경우에서 |*xPtr=x|로 바로 쓴다.

@<한 명령을 수행한다@>=
if resuming {
	loc, inst = m.instPtr-4, Tetra(m.g[rX])
} else {
	@<다음 명령을 가져온다@>
}
op = int(inst >> 24)
xx, yy, zz = int(inst>>16)&0xff, int(inst>>8)&0xff, int(inst)&0xff
f = int(info[op].flags)
yz = int(inst & 0xffff)
x, y, z, a, b = 0, 0, 0, 0, 0
exc = 0
oldL = L
if f&relAddrBit != 0 {
	@<상대 주소를 절대 주소로 바꾼다@>
}
@<피연산자 필드를 설치한다@>
if f&xIsDestBit != 0 {
	@<레지스터~X를 목적지로 설치하고, 필요하면 레지스터 스택을 조정한다@>
}
w = y + z
trouble := ""
if loc>>32 >= 0x20000000 {
	trouble = "!privileged"
} else {
perform:
	switch op {
	@<개별 \MMIX\ 명령의 경우들@>
	}
}
if trouble != "" {
	@<명령을 특권 명령이나 불법 명령으로 처리한다@>
}
@<트립 인터럽트를 검사한다@>
@<시계를 갱신한다@>
@<요청이 있으면 현재 명령을 추적한다@>
if resuming && op != RESUME {
	resuming = false
}

@ 피연산자 |x|와 |a|는 대개 목적지(결과)다. 이것들은 원천 피연산자 |y|, |z|, |b|로
계산한다.

보충: 원본의 전역 변수 가운데 |main|에서만 쓰는 것들은 지역 변수다. 원본의 |lhs|는 32바이트
문자 배열이고, |rhs|는 48바이트 배열 |switchable_string|의 둘째 바이트부터였다. 여기서는
둘 다 \GO/의 문자열이다. 문자열 |lhs|는 명령마다 새로 정하지 않으므로, 앞 명령의 값이 남아 있을 수
있다는 데 주의하라. 원본은 반올림 방식을 {\mc MMIX-ARITH}의 전역 변수 |cur_round|에 두었다.
여기서는 지역 변수 |curRound|다.

@<지역 변수@>=
w, x, y, z, a, b, ma, mb Octa // 피연산자
xPtr        *Octa          // 목적지
loc         Octa           // 현재 명령의 위치
inst        Tetra          // 현재 명령
oldL        int            // 현재 명령을 실행하기 전의 |L|
exc         int            // 현재 명령이 일으킨 예외
rop         int            // 다시 시작한 명령의 ropcode
roundMode   mmixarith.Round // 방금 쓴 부동소수점 반올림 방식
curRound    mmixarith.Round // 현재 반올림 방식
resuming    bool           // 중단된 명령을 다시 시작하고 있는가?
tripping    bool           // 트립 처리기로 가려는 참인가?
good        bool           // 마지막 분기 명령이 옳게 짐작했는가?
lhs, rhs    string         // 추적 출력의 왼쪽과 오른쪽

@ @<시뮬레이터의 상태@>=
instPtr            Octa  // 다음 명령의 위치
tracingExceptions  int   // 추적하게 하는 예외 비트들
halted             bool  // 프로그램이 멈추었는가?
breakpoint         bool  // 현재 명령 다음에 쉬어야 하는가?
tracing            bool  // 현재 명령을 추적해야 하는가?
stackTracing       bool  // 레지스터 스택의 자세한 사정을 추적해야 하는가?
interacting        bool  // 대화 방식에 있는가?
interactAfterBreak bool  // 대화 방식으로 들어가야 하는가?
traceThreshold     Tetra // 명령마다 이만큼 추적한다

@ @<지역 변수@>=
op         int        // 현재 명령의 연산 코드
xx, yy, zz, yz int    // 현재 명령의 피연산자 필드들
f          int        // 현재 |op|의 성질
i, j, k    int        // 이런저런 색인
ll         []memTetra // 모의 메모리의 현재 자리
p          int        // 문자열에서의 현재 자리

@ @<다음 명령을 가져온다@>=
loc = m.instPtr
ll = m.memFind(loc)
inst = ll[0].tet
m.curFile = int(ll[0].fileNo)
m.curLine = int(ll[0].lineNo)
ll[0].freq++
if ll[0].bkpt&execBit != 0 {
	m.breakpoint = true
}
m.tracing = m.breakpoint || ll[0].bkpt&traceBit != 0 || ll[0].freq <= m.traceThreshold
m.instPtr += 4

@ 시뮬레이션의 많은 부분은 표로 움직인다. 연산 코드마다 \KW{opInfo}라는 정적 데이터
구조가 있다.

@<타입 정의@>=
type opInfo struct {
	name         string // 연산 코드의 기호 이름
	flags        byte   // 명령의 형식
	thirdOperand byte   // 입력으로 쓰는 특수 레지스터
	mems         byte   // $\mu$를 몇 번 쓰는가
	oops         byte   // $\upsilon$를 몇 번 쓰는가
	traceFormat  string // 추적할 때 어떻게 보이는가
}

@ 이를테면 |info[op]|의 |flags| 필드는 현재 명령의 X, Y, Z 필드에서 피연산자를 어떻게
얻는지 알려 준다. 각 항목은 연산 코드의 특별한 성질을 이진수로 기록한다.
값 \Hex{1}은 Z가 즉시값이라는 뜻, \Hex{2}는 rZ가 원천 피연산자라는 뜻, \Hex{4}는 Y가
즉시값이라는 뜻, \Hex{8}은 rY가 원천 피연산자라는 뜻, \Hex{10}은 rX가 원천 피연산자라는
뜻, \Hex{20}은 rX가 목적지라는 뜻, \Hex{40}은 YZ가 상대 주소의 일부라는 뜻,
\Hex{80}은 넣기나 꺼내기나 \.{UNSAVE} 명령이라는 뜻이다.

필드 |traceFormat|은 나중에 설명한다.

@<상수@>=
const (
	zIsImmedBit  = 0x1
	zIsSourceBit = 0x2
	yIsImmedBit  = 0x4
	yIsSourceBit = 0x8
	xIsSourceBit = 0x10
	xIsDestBit   = 0x20
	relAddrBit   = 0x40
	pushPopBit   = 0x80
)

@ @<표@>=
var info = [256]opInfo{
	@<산술 명령의 정보@>
	@<분기 명령의 정보@>
	@<적재와 저장 명령의 정보@>
	@<논리와 제어 명령의 정보@>
}

@ @<산술 명령의 정보@>=
@<연산 코드 \Hex{00}--\Hex{0f}의 정보@>
@<연산 코드 \Hex{10}--\Hex{1f}의 정보@>
@<연산 코드 \Hex{20}--\Hex{2f}의 정보@>
@<연산 코드 \Hex{30}--\Hex{3f}의 정보@>

@ @<연산 코드 \Hex{00}--\Hex{0f}의 정보@>=
{"TRAP", 0x0a, 255, 0, 5, "%r"},
{"FCMP", 0x2a, 0, 0, 1, "%l = %.y cmp %.z = %x"},
{"FUN", 0x2a, 0, 0, 1, "%l = [%.y(||)%.z] = %x"},
{"FEQL", 0x2a, 0, 0, 1, "%l = [%.y(==)%.z] = %x"},
{"FADD", 0x2a, 0, 0, 4, "%l = %.y %(+%) %.z = %.x"},
{"FIX", 0x26, 0, 0, 4, "%l = %(fix%) %.z = %x"},
{"FSUB", 0x2a, 0, 0, 4, "%l = %.y %(-%) %.z = %.x"},
{"FIXU", 0x26, 0, 0, 4, "%l = %(fix%) %.z = %#x"},
{"FLOT", 0x26, 0, 0, 4, "%l = %(flot%) %z = %.x"},
{"FLOTI", 0x25, 0, 0, 4, "%l = %(flot%) %z = %.x"},
{"FLOTU", 0x26, 0, 0, 4, "%l = %(flot%) %#z = %.x"},
{"FLOTUI", 0x25, 0, 0, 4, "%l = %(flot%) %z = %.x"},
{"SFLOT", 0x26, 0, 0, 4, "%l = %(sflot%) %z = %.x"},
{"SFLOTI", 0x25, 0, 0, 4, "%l = %(sflot%) %z = %.x"},
{"SFLOTU", 0x26, 0, 0, 4, "%l = %(sflot%) %#z = %.x"},
{"SFLOTUI", 0x25, 0, 0, 4, "%l = %(sflot%) %z = %.x"},

@ @<연산 코드 \Hex{10}--\Hex{1f}의 정보@>=
{"FMUL", 0x2a, 0, 0, 4, "%l = %.y %(*%) %.z = %.x"},
{"FCMPE", 0x2a, rE, 0, 4, "%l = %.y cmp %.z (%.b)) = %x"},
{"FUNE", 0x2a, rE, 0, 1, "%l = [%.y(||)%.z (%.b)] = %x"},
{"FEQLE", 0x2a, rE, 0, 4, "%l = [%.y(==)%.z (%.b)] = %x"},
{"FDIV", 0x2a, 0, 0, 40, "%l = %.y %(/%) %.z = %.x"},
{"FSQRT", 0x26, 0, 0, 40, "%l = %(sqrt%) %.z = %.x"},
{"FREM", 0x2a, 0, 0, 4, "%l = %.y %(rem%) %.z = %.x"},
{"FINT", 0x26, 0, 0, 4, "%l = %(int%) %.z = %.x"},
{"MUL", 0x2a, 0, 0, 10, "%l = %y * %z = %x"},
{"MULI", 0x29, 0, 0, 10, "%l = %y * %z = %x"},
{"MULU", 0x2a, 0, 0, 10, "%l = %#y * %#z = %#x, rH=%#a"},
{"MULUI", 0x29, 0, 0, 10, "%l = %#y * %z = %#x, rH=%#a"},
{"DIV", 0x2a, 0, 0, 60, "%l = %y / %z = %x, rR=%a"},
{"DIVI", 0x29, 0, 0, 60, "%l = %y / %z = %x, rR=%a"},
{"DIVU", 0x2a, rD, 0, 60, "%l = %#b%0y / %#z = %#x, rR=%#a"},
{"DIVUI", 0x29, rD, 0, 60, "%l = %#b%0y / %z = %#x, rR=%#a"},

@ @<연산 코드 \Hex{20}--\Hex{2f}의 정보@>=
{"ADD", 0x2a, 0, 0, 1, "%l = %y + %z = %x"},
{"ADDI", 0x29, 0, 0, 1, "%l = %y + %z = %x"},
{"ADDU", 0x2a, 0, 0, 1, "%l = %#y + %#z = %#x"},
{"ADDUI", 0x29, 0, 0, 1, "%l = %#y + %z = %#x"},
{"SUB", 0x2a, 0, 0, 1, "%l = %y - %z = %x"},
{"SUBI", 0x29, 0, 0, 1, "%l = %y - %z = %x"},
{"SUBU", 0x2a, 0, 0, 1, "%l = %#y - %#z = %#x"},
{"SUBUI", 0x29, 0, 0, 1, "%l = %#y - %z = %#x"},
{"2ADDU", 0x2a, 0, 0, 1, "%l = %#y <<1+ %#z = %#x"},
{"2ADDUI", 0x29, 0, 0, 1, "%l = %#y <<1+ %z = %#x"},
{"4ADDU", 0x2a, 0, 0, 1, "%l = %#y <<2+ %#z = %#x"},
{"4ADDUI", 0x29, 0, 0, 1, "%l = %#y <<2+ %z = %#x"},
{"8ADDU", 0x2a, 0, 0, 1, "%l = %#y <<3+ %#z = %#x"},
{"8ADDUI", 0x29, 0, 0, 1, "%l = %#y <<3+ %z = %#x"},
{"16ADDU", 0x2a, 0, 0, 1, "%l = %#y <<4+ %#z = %#x"},
{"16ADDUI", 0x29, 0, 0, 1, "%l = %#y <<4+ %z = %#x"},

@ @<연산 코드 \Hex{30}--\Hex{3f}의 정보@>=
{"CMP", 0x2a, 0, 0, 1, "%l = %y cmp %z = %x"},
{"CMPI", 0x29, 0, 0, 1, "%l = %y cmp %z = %x"},
{"CMPU", 0x2a, 0, 0, 1, "%l = %#y cmp %#z = %x"},
{"CMPUI", 0x29, 0, 0, 1, "%l = %#y cmp %z = %x"},
{"NEG", 0x26, 0, 0, 1, "%l = %y - %z = %x"},
{"NEGI", 0x25, 0, 0, 1, "%l = %y - %z = %x"},
{"NEGU", 0x26, 0, 0, 1, "%l = %y - %#z = %#x"},
{"NEGUI", 0x25, 0, 0, 1, "%l = %y - %z = %#x"},
{"SL", 0x2a, 0, 0, 1, "%l = %y << %#z = %x"},
{"SLI", 0x29, 0, 0, 1, "%l = %y << %z = %x"},
{"SLU", 0x2a, 0, 0, 1, "%l = %#y << %#z = %#x"},
{"SLUI", 0x29, 0, 0, 1, "%l = %#y << %z = %#x"},
{"SR", 0x2a, 0, 0, 1, "%l = %y >> %#z = %x"},
{"SRI", 0x29, 0, 0, 1, "%l = %y >> %z = %x"},
{"SRU", 0x2a, 0, 0, 1, "%l = %#y >> %#z = %#x"},
{"SRUI", 0x29, 0, 0, 1, "%l = %#y >> %z = %#x"},
@ @<분기 명령의 정보@>=
@<연산 코드 \Hex{40}--\Hex{4f}의 정보@>
@<연산 코드 \Hex{50}--\Hex{5f}의 정보@>
@<연산 코드 \Hex{60}--\Hex{6f}의 정보@>
@<연산 코드 \Hex{70}--\Hex{7f}의 정보@>

@ @<연산 코드 \Hex{40}--\Hex{4f}의 정보@>=
{"BN", 0x50, 0, 0, 1, "%b<0? %t%g"},
{"BNB", 0x50, 0, 0, 1, "%b<0? %t%g"},
{"BZ", 0x50, 0, 0, 1, "%b==0? %t%g"},
{"BZB", 0x50, 0, 0, 1, "%b==0? %t%g"},
{"BP", 0x50, 0, 0, 1, "%b>0? %t%g"},
{"BPB", 0x50, 0, 0, 1, "%b>0? %t%g"},
{"BOD", 0x50, 0, 0, 1, "%b odd? %t%g"},
{"BODB", 0x50, 0, 0, 1, "%b odd? %t%g"},
{"BNN", 0x50, 0, 0, 1, "%b>=0? %t%g"},
{"BNNB", 0x50, 0, 0, 1, "%b>=0? %t%g"},
{"BNZ", 0x50, 0, 0, 1, "%b!=0? %t%g"},
{"BNZB", 0x50, 0, 0, 1, "%b!=0? %t%g"},
{"BNP", 0x50, 0, 0, 1, "%b<=0? %t%g"},
{"BNPB", 0x50, 0, 0, 1, "%b<=0? %t%g"},
{"BEV", 0x50, 0, 0, 1, "%b even? %t%g"},
{"BEVB", 0x50, 0, 0, 1, "%b even? %t%g"},

@ @<연산 코드 \Hex{50}--\Hex{5f}의 정보@>=
{"PBN", 0x50, 0, 0, 1, "%b<0? %t%g"},
{"PBNB", 0x50, 0, 0, 1, "%b<0? %t%g"},
{"PBZ", 0x50, 0, 0, 1, "%b==0? %t%g"},
{"PBZB", 0x50, 0, 0, 1, "%b==0? %t%g"},
{"PBP", 0x50, 0, 0, 1, "%b>0? %t%g"},
{"PBPB", 0x50, 0, 0, 1, "%b>0? %t%g"},
{"PBOD", 0x50, 0, 0, 1, "%b odd? %t%g"},
{"PBODB", 0x50, 0, 0, 1, "%b odd? %t%g"},
{"PBNN", 0x50, 0, 0, 1, "%b>=0? %t%g"},
{"PBNNB", 0x50, 0, 0, 1, "%b>=0? %t%g"},
{"PBNZ", 0x50, 0, 0, 1, "%b!=0? %t%g"},
{"PBNZB", 0x50, 0, 0, 1, "%b!=0? %t%g"},
{"PBNP", 0x50, 0, 0, 1, "%b<=0? %t%g"},
{"PBNPB", 0x50, 0, 0, 1, "%b<=0? %t%g"},
{"PBEV", 0x50, 0, 0, 1, "%b even? %t%g"},
{"PBEVB", 0x50, 0, 0, 1, "%b even? %t%g"},

@ @<연산 코드 \Hex{60}--\Hex{6f}의 정보@>=
{"CSN", 0x3a, 0, 0, 1, "%l = %y<0? %z: %b = %x"},
{"CSNI", 0x39, 0, 0, 1, "%l = %y<0? %z: %b = %x"},
{"CSZ", 0x3a, 0, 0, 1, "%l = %y==0? %z: %b = %x"},
{"CSZI", 0x39, 0, 0, 1, "%l = %y==0? %z: %b = %x"},
{"CSP", 0x3a, 0, 0, 1, "%l = %y>0? %z: %b = %x"},
{"CSPI", 0x39, 0, 0, 1, "%l = %y>0? %z: %b = %x"},
{"CSOD", 0x3a, 0, 0, 1, "%l = %y odd? %z: %b = %x"},
{"CSODI", 0x39, 0, 0, 1, "%l = %y odd? %z: %b = %x"},
{"CSNN", 0x3a, 0, 0, 1, "%l = %y>=0? %z: %b = %x"},
{"CSNNI", 0x39, 0, 0, 1, "%l = %y>=0? %z: %b = %x"},
{"CSNZ", 0x3a, 0, 0, 1, "%l = %y!=0? %z: %b = %x"},
{"CSNZI", 0x39, 0, 0, 1, "%l = %y!=0? %z: %b = %x"},
{"CSNP", 0x3a, 0, 0, 1, "%l = %y<=0? %z: %b = %x"},
{"CSNPI", 0x39, 0, 0, 1, "%l = %y<=0? %z: %b = %x"},
{"CSEV", 0x3a, 0, 0, 1, "%l = %y even? %z: %b = %x"},
{"CSEVI", 0x39, 0, 0, 1, "%l = %y even? %z: %b = %x"},

@ @<연산 코드 \Hex{70}--\Hex{7f}의 정보@>=
{"ZSN", 0x2a, 0, 0, 1, "%l = %y<0? %z: 0 = %x"},
{"ZSNI", 0x29, 0, 0, 1, "%l = %y<0? %z: 0 = %x"},
{"ZSZ", 0x2a, 0, 0, 1, "%l = %y==0? %z: 0 = %x"},
{"ZSZI", 0x29, 0, 0, 1, "%l = %y==0? %z: 0 = %x"},
{"ZSP", 0x2a, 0, 0, 1, "%l = %y>0? %z: 0 = %x"},
{"ZSPI", 0x29, 0, 0, 1, "%l = %y>0? %z: 0 = %x"},
{"ZSOD", 0x2a, 0, 0, 1, "%l = %y odd? %z: 0 = %x"},
{"ZSODI", 0x29, 0, 0, 1, "%l = %y odd? %z: 0 = %x"},
{"ZSNN", 0x2a, 0, 0, 1, "%l = %y>=0? %z: 0 = %x"},
{"ZSNNI", 0x29, 0, 0, 1, "%l = %y>=0? %z: 0 = %x"},
{"ZSNZ", 0x2a, 0, 0, 1, "%l = %y!=0? %z: 0 = %x"},
{"ZSNZI", 0x29, 0, 0, 1, "%l = %y!=0? %z: 0 = %x"},
{"ZSNP", 0x2a, 0, 0, 1, "%l = %y<=0? %z: 0 = %x"},
{"ZSNPI", 0x29, 0, 0, 1, "%l = %y<=0? %z: 0 = %x"},
{"ZSEV", 0x2a, 0, 0, 1, "%l = %y even? %z: 0 = %x"},
{"ZSEVI", 0x29, 0, 0, 1, "%l = %y even? %z: 0 = %x"},
@ @<적재와 저장 명령의 정보@>=
@<연산 코드 \Hex{80}--\Hex{8f}의 정보@>
@<연산 코드 \Hex{90}--\Hex{9f}의 정보@>
@<연산 코드 \Hex{a0}--\Hex{af}의 정보@>
@<연산 코드 \Hex{b0}--\Hex{bf}의 정보@>

@ @<연산 코드 \Hex{80}--\Hex{8f}의 정보@>=
{"LDB", 0x2a, 0, 1, 1, "%l = M1[%#y+%#z] = %x"},
{"LDBI", 0x29, 0, 1, 1, "%l = M1[%#y%?+] = %x"},
{"LDBU", 0x2a, 0, 1, 1, "%l = M1[%#y+%#z] = %#x"},
{"LDBUI", 0x29, 0, 1, 1, "%l = M1[%#y%?+] = %#x"},
{"LDW", 0x2a, 0, 1, 1, "%l = M2[%#y+%#z] = %x"},
{"LDWI", 0x29, 0, 1, 1, "%l = M2[%#y%?+] = %x"},
{"LDWU", 0x2a, 0, 1, 1, "%l = M2[%#y+%#z] = %#x"},
{"LDWUI", 0x29, 0, 1, 1, "%l = M2[%#y%?+] = %#x"},
{"LDT", 0x2a, 0, 1, 1, "%l = M4[%#y+%#z] = %x"},
{"LDTI", 0x29, 0, 1, 1, "%l = M4[%#y%?+] = %x"},
{"LDTU", 0x2a, 0, 1, 1, "%l = M4[%#y+%#z] = %#x"},
{"LDTUI", 0x29, 0, 1, 1, "%l = M4[%#y%?+] = %#x"},
{"LDO", 0x2a, 0, 1, 1, "%l = M8[%#y+%#z] = %x"},
{"LDOI", 0x29, 0, 1, 1, "%l = M8[%#y%?+] = %x"},
{"LDOU", 0x2a, 0, 1, 1, "%l = M8[%#y+%#z] = %#x"},
{"LDOUI", 0x29, 0, 1, 1, "%l = M8[%#y%?+] = %#x"},

@ @<연산 코드 \Hex{90}--\Hex{9f}의 정보@>=
{"LDSF", 0x2a, 0, 1, 1, "%l = (M4[%#y+%#z]) = %.x"},
{"LDSFI", 0x29, 0, 1, 1, "%l = (M4[%#y%?+]) = %.x"},
{"LDHT", 0x2a, 0, 1, 1, "%l = M4[%#y+%#z]<<32 = %#x"},
{"LDHTI", 0x29, 0, 1, 1, "%l = M4[%#y%?+]<<32 = %#x"},
{"CSWAP", 0x3a, 0, 2, 2, "%l = [M8[%#y+%#z]==%a] = %x, %r"},
{"CSWAPI", 0x39, 0, 2, 2, "%l = [M8[%#y%?+]==%a] = %x, %r"},
{"LDUNC", 0x2a, 0, 1, 1, "%l = M8[%#y+%#z] = %#x"},
{"LDUNCI", 0x29, 0, 1, 1, "%l = M8[%#y%?+] = %#x"},
{"LDVTS", 0x2a, 0, 0, 1, ""},
{"LDVTSI", 0x29, 0, 0, 1, ""},
{"PRELD", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
{"PRELDI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
{"PREGO", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
{"PREGOI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
{"GO", 0x2a, 0, 0, 3, "%l = %#x, -> %#y+%#z"},
{"GOI", 0x29, 0, 0, 3, "%l = %#x, -> %#y%?+"},

@ @<연산 코드 \Hex{a0}--\Hex{af}의 정보@>=
{"STB", 0x1a, 0, 1, 1, "M1[%#y+%#z] = %b, M8[%#w]=%#a"},
{"STBI", 0x19, 0, 1, 1, "M1[%#y%?+] = %b, M8[%#w]=%#a"},
{"STBU", 0x1a, 0, 1, 1, "M1[%#y+%#z] = %#b, M8[%#w]=%#a"},
{"STBUI", 0x19, 0, 1, 1, "M1[%#y%?+] = %#b, M8[%#w]=%#a"},
{"STW", 0x1a, 0, 1, 1, "M2[%#y+%#z] = %b, M8[%#w]=%#a"},
{"STWI", 0x19, 0, 1, 1, "M2[%#y%?+] = %b, M8[%#w]=%#a"},
{"STWU", 0x1a, 0, 1, 1, "M2[%#y+%#z] = %#b, M8[%#w]=%#a"},
{"STWUI", 0x19, 0, 1, 1, "M2[%#y%?+] = %#b, M8[%#w]=%#a"},
{"STT", 0x1a, 0, 1, 1, "M4[%#y+%#z] = %b, M8[%#w]=%#a"},
{"STTI", 0x19, 0, 1, 1, "M4[%#y%?+] = %b, M8[%#w]=%#a"},
{"STTU", 0x1a, 0, 1, 1, "M4[%#y+%#z] = %#b, M8[%#w]=%#a"},
{"STTUI", 0x19, 0, 1, 1, "M4[%#y%?+] = %#b, M8[%#w]=%#a"},
{"STO", 0x1a, 0, 1, 1, "M8[%#y+%#z] = %b"},
{"STOI", 0x19, 0, 1, 1, "M8[%#y%?+] = %b"},
{"STOU", 0x1a, 0, 1, 1, "M8[%#y+%#z] = %#b"},
{"STOUI", 0x19, 0, 1, 1, "M8[%#y%?+] = %#b"},

@ @<연산 코드 \Hex{b0}--\Hex{bf}의 정보@>=
{"STSF", 0x1a, 0, 1, 1, "%(M4[%#y+%#z]%) = %.b, M8[%#w]=%#a"},
{"STSFI", 0x19, 0, 1, 1, "%(M4[%#y%?+]%) = %.b, M8[%#w]=%#a"},
{"STHT", 0x1a, 0, 1, 1, "M4[%#y+%#z] = %#b>>32, M8[%#w]=%#a"},
{"STHTI", 0x19, 0, 1, 1, "M4[%#y%?+] = %#b>>32, M8[%#w]=%#a"},
{"STCO", 0x0a, 0, 1, 1, "M8[%#y+%#z] = %b"},
{"STCOI", 0x09, 0, 1, 1, "M8[%#y%?+] = %b"},
{"STUNC", 0x1a, 0, 1, 1, "M8[%#y+%#z] = %#b"},
{"STUNCI", 0x19, 0, 1, 1, "M8[%#y%?+] = %#b"},
{"SYNCD", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
{"SYNCDI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
{"PREST", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
{"PRESTI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
{"SYNCID", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
{"SYNCIDI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
{"PUSHGO", 0xaa, 0, 0, 3, "%lrO=%#b, rL=%a, rJ=%#x, -> %#y+%#z"},
{"PUSHGOI", 0xa9, 0, 0, 3, "%lrO=%#b, rL=%a, rJ=%#x, -> %#y%?+"},
@ @<논리와 제어 명령의 정보@>=
@<연산 코드 \Hex{c0}--\Hex{cf}의 정보@>
@<연산 코드 \Hex{d0}--\Hex{df}의 정보@>
@<연산 코드 \Hex{e0}--\Hex{ef}의 정보@>
@<연산 코드 \Hex{f0}--\Hex{ff}의 정보@>

@ @<연산 코드 \Hex{c0}--\Hex{cf}의 정보@>=
{"OR", 0x2a, 0, 0, 1, "%l = %#y | %#z = %#x"},
{"ORI", 0x29, 0, 0, 1, "%l = %#y | %z = %#x"},
{"ORN", 0x2a, 0, 0, 1, "%l = %#y |~ %#z = %#x"},
{"ORNI", 0x29, 0, 0, 1, "%l = %#y |~ %z = %#x"},
{"NOR", 0x2a, 0, 0, 1, "%l = %#y ~| %#z = %#x"},
{"NORI", 0x29, 0, 0, 1, "%l = %#y ~| %z = %#x"},
{"XOR", 0x2a, 0, 0, 1, "%l = %#y ^ %#z = %#x"},
{"XORI", 0x29, 0, 0, 1, "%l = %#y ^ %z = %#x"},
{"AND", 0x2a, 0, 0, 1, "%l = %#y & %#z = %#x"},
{"ANDI", 0x29, 0, 0, 1, "%l = %#y & %z = %#x"},
{"ANDN", 0x2a, 0, 0, 1, "%l = %#y \\ %#z = %#x"},
{"ANDNI", 0x29, 0, 0, 1, "%l = %#y \\ %z = %#x"},
{"NAND", 0x2a, 0, 0, 1, "%l = %#y ~& %#z = %#x"},
{"NANDI", 0x29, 0, 0, 1, "%l = %#y ~& %z = %#x"},
{"NXOR", 0x2a, 0, 0, 1, "%l = %#y ~^ %#z = %#x"},
{"NXORI", 0x29, 0, 0, 1, "%l = %#y ~^ %z = %#x"},

@ @<연산 코드 \Hex{d0}--\Hex{df}의 정보@>=
{"BDIF", 0x2a, 0, 0, 1, "%l = %#y bdif %#z = %#x"},
{"BDIFI", 0x29, 0, 0, 1, "%l = %#y bdif %z = %#x"},
{"WDIF", 0x2a, 0, 0, 1, "%l = %#y wdif %#z = %#x"},
{"WDIFI", 0x29, 0, 0, 1, "%l = %#y wdif %z = %#x"},
{"TDIF", 0x2a, 0, 0, 1, "%l = %#y tdif %#z = %#x"},
{"TDIFI", 0x29, 0, 0, 1, "%l = %#y tdif %z = %#x"},
{"ODIF", 0x2a, 0, 0, 1, "%l = %#y odif %#z = %#x"},
{"ODIFI", 0x29, 0, 0, 1, "%l = %#y odif %z = %#x"},
{"MUX", 0x2a, rM, 0, 1, "%l = %#b? %#y: %#z = %#x"},
{"MUXI", 0x29, rM, 0, 1, "%l = %#b? %#y: %z = %#x"},
{"SADD", 0x2a, 0, 0, 1, "%l = nu(%#y\\%#z) = %x"},
{"SADDI", 0x29, 0, 0, 1, "%l = nu(%#y%?\\) = %x"},
{"MOR", 0x2a, 0, 0, 1, "%l = %#y mor %#z = %#x"},
{"MORI", 0x29, 0, 0, 1, "%l = %#y mor %z = %#x"},
{"MXOR", 0x2a, 0, 0, 1, "%l = %#y mxor %#z = %#x"},
{"MXORI", 0x29, 0, 0, 1, "%l = %#y mxor %z = %#x"},

@ @<연산 코드 \Hex{e0}--\Hex{ef}의 정보@>=
{"SETH", 0x20, 0, 0, 1, "%l = %#z"},
{"SETMH", 0x20, 0, 0, 1, "%l = %#z"},
{"SETML", 0x20, 0, 0, 1, "%l = %#z"},
{"SETL", 0x20, 0, 0, 1, "%l = %#z"},
{"INCH", 0x30, 0, 0, 1, "%l = %#y + %#z = %#x"},
{"INCMH", 0x30, 0, 0, 1, "%l = %#y + %#z = %#x"},
{"INCML", 0x30, 0, 0, 1, "%l = %#y + %#z = %#x"},
{"INCL", 0x30, 0, 0, 1, "%l = %#y + %#z = %#x"},
{"ORH", 0x30, 0, 0, 1, "%l = %#y | %#z = %#x"},
{"ORMH", 0x30, 0, 0, 1, "%l = %#y | %#z = %#x"},
{"ORML", 0x30, 0, 0, 1, "%l = %#y | %#z = %#x"},
{"ORL", 0x30, 0, 0, 1, "%l = %#y | %#z = %#x"},
{"ANDNH", 0x30, 0, 0, 1, "%l = %#y \\ %#z = %#x"},
{"ANDNMH", 0x30, 0, 0, 1, "%l = %#y \\ %#z = %#x"},
{"ANDNML", 0x30, 0, 0, 1, "%l = %#y \\ %#z = %#x"},
{"ANDNL", 0x30, 0, 0, 1, "%l = %#y \\ %#z = %#x"},

@ @<연산 코드 \Hex{f0}--\Hex{ff}의 정보@>=
{"JMP", 0x40, 0, 0, 1, "-> %#z"},
{"JMPB", 0x40, 0, 0, 1, "-> %#z"},
{"PUSHJ", 0xe0, 0, 0, 1, "%lrO=%#b, rL=%a, rJ=%#x, -> %#z"},
{"PUSHJB", 0xe0, 0, 0, 1, "%lrO=%#b, rL=%a, rJ=%#x, -> %#z"},
{"GETA", 0x60, 0, 0, 1, "%l = %#z"},
{"GETAB", 0x60, 0, 0, 1, "%l = %#z"},
{"PUT", 0x02, 0, 0, 1, "%s = %r"},
{"PUTI", 0x01, 0, 0, 1, "%s = %r"},
{"POP", 0x80, rJ, 0, 3, "%lrL=%a, rO=%#b, -> %#y%?+"},
{"RESUME", 0x00, 0, 0, 5, "{%#b} -> %#z"},
{"SAVE", 0x20, 0, 20, 1, "%l = %#x"},
{"UNSAVE", 0x82, 0, 20, 1, "%#z: rG=%x, ..., rL=%a"},
{"SYNC", 0x01, 0, 0, 1, ""},
{"SWYM", 0x00, 0, 0, 1, ""},
{"GET", 0x20, 0, 0, 1, "%l = %s = %#x"},
{"TRIP", 0x0a, 255, 0, 5, "rW=%#w, rX=%#x, rY=%#y, rZ=%#z, rB=%#b, g[255]=%#a"},
@ 보충: YZ 필드는 부호 없는 16비트이고, \.{JMP}에서는 XYZ가 부호 없는 24비트다. 연산
코드가 홀수이면 뒤로 가는 분기이므로 $2^{16}$이나 $2^{24}$를 뺀다.

@<상대 주소를 절대 주소로 바꾼다@>=
if op&0xfe == JMP {
	yz = int(inst & 0xffffff)
}
if op&1 != 0 {
	if op == JMPB {
		yz -= 0x1000000
	} else {
		yz -= 0x10000
	}
}
y = m.instPtr
z = loc + Octa(yz<<2)

@ @<피연산자 필드를 설치한다@>=
if resuming && rop != resumeAgain {
	@<중단된 연산을 다시 시작할 때의 특별한 피연산자를 설치한다@>
} else {
	if f&xIsSourceBit != 0 {
		@<레지스터 X에서 |b|를 정한다@>
	}
	if info[op].thirdOperand != 0 {
		@<특수 레지스터에서 |b|를 정한다@>
	}
	if f&zIsImmedBit != 0 {
		z = Octa(zz)
	} else if f&zIsSourceBit != 0 {
		@<레지스터 Z에서 |z|를 정한다@>
	} else if op&0xf0 == SETH {
		@<|z|를 즉시 와이드로 정한다@>
	}
	if f&yIsImmedBit != 0 {
		y = Octa(yy)
	} else if f&yIsSourceBit != 0 {
		@<레지스터 Y에서 |y|를 정한다@>
	}
}

@ 전역 레지스터는 |g[0]|부터 |g[255]|까지 256개 있다. 그 가운데 처음 32개는 특수 레지스터
|rA|, |rB| 등에 쓰인다. 지역 레지스터는 |lringMask+1|개 있다. 보통은 256개이지만,
사용자가 이것을 2의 더 큰 거듭제곱으로 늘릴 수 있다.

rL, rG, rO, rS의 현재 값은 편의를 위해 |L|, |G|, |O|, |S|라는 변수에 따로 둔다. (사실
|O|와 |S|에는 rO/8과 rS/8을 |lringSize|로 나눈 나머지와 합동인 값이 들어 있다.)

@<레지스터 Z에서 |z|를...@>=
if zz >= G {
	z = m.g[zz]
} else if zz < L {
	z = m.l[(O+zz)&m.lringMask]
}

@ @<레지스터 Y에서 |y|를...@>=
if yy >= G {
	y = m.g[yy]
} else if yy < L {
	y = m.l[(O+yy)&m.lringMask]
}

@ @<레지스터 X에서 |b|를...@>=
if xx >= G {
	b = m.g[xx]
} else if xx < L {
	b = m.l[(O+xx)&m.lringMask]
}

@ 보충: 원본에서 |G|와 |L|은 후기를 실을 때 정해지고, |O|는 모든 것을 시작하는 \.{UNSAVE}가
정한다. 그런데 대화 명령 \.{@@}로 첫 명령 전에 다음 명령의 위치를 세그먼트~0 밖으로 옮기면, 그
\.{UNSAVE}가 특권 명령이 되어 실행되지 않는다. 그러면 원본의 |register int O|는 초기화되지
않은 채 쓰인다. 여기서는 \GO/의 지역 변수이므로 0이다.

@<지역 변수@>=
G, L, O int // 핵심 레지스터들의 손쉬운 사본

@ 보충: 원본에서 |S|는 전역 변수였다. 메서드 |stackStore|와 |stackLoad|가 쓰기 때문이다.

@<시뮬레이터의 상태@>=
g         [256]Octa // 전역 레지스터
l         []Octa    // 지역 레지스터
lringSize int       // 지역 레지스터의 개수(2의 거듭제곱)
lringMask int       // |lringSize|보다 하나 작은 수
S         int       // $\rm rS/8$과 |lringSize|를 법으로 합동

@ 이 시뮬레이터에서는 \MMIX를 단순화한 탓에 전역 레지스터 가운데 몇몇은 값이 바뀌지
않는다.

특수 레지스터 rN에는 컴파일한 때를 나타내는 값이 들어 있다. (원본에서 매크로
\.{ABSTIME}은 바깥의 파일 \.{abstime.h}에 정의되어 있었다. 그 파일은 {\mc ABSTIME}이
방금 만들었어야 한다. {\mc ABSTIME}은 표준 라이브러리 함수 |time(NULL)|의 값을 계산하는
사소한 프로그램이다. 이 수는 ``{\mc UNIX} 기원'' 이래의 초 수인데, 우리는 이 수가
$2^{32}$보다 작다고 가정한다. 조심하라: 이 가정은 2106년 2월에 깨진다.)
@^system dependencies@>

보충: 여기서는 \.{abstime} 프로그램이 같은 디렉터리에 \.{abstime.go}라는 \GO/ 파일을
만들어 상수 |ABSTIME|을 정의한다. 원본처럼 그 값을 32비트로 잘라서 쓴다. 원본은 지역
레지스터를 할당하지 못하면 ``\.{No room for the local registers}''라고 알렸다.
@.No room...@>

@<상수@>=
const (
	version       = 1 // 우리가 지원하는 \MMIX\ 아키텍처의 판
	subversion    = 0 // 판 번호의 둘째 바이트
	subsubversion = 1 // 판 번호를 더 한정하는 번호
)

@ @<모든 것을 초기화한다@>=
m.g[rK] = negOne
m.g[rN] = (version<<24+subversion<<16+subsubversion<<8)<<32 |
	Octa(Tetra(ABSTIME)) // 위의 설명과 경고를 보라
m.g[rT] = 0x8000000500000000
m.g[rTT] = 0x8000000600000000
m.g[rV] = 0x369c200400000000
if m.lringSize < 256 {
	m.lringSize = 256
}
m.lringMask = m.lringSize - 1
if m.lringSize&m.lringMask != 0 {
	m.panic("The number of local registers must be a power of 2")
@.The number of local...@>
}
m.l = make([]Octa, m.lringSize)
curRound = mmixarith.RoundNear

@ 이를테면 \.{INCH} 같은 연산에서는 |z|가 |yz| 필드를 왼쪽으로 48비트 옮긴 값이면 좋겠다. 또 |y|가
레지스터~X였으면 좋겠는데, 그 값은 이미 |b|에 들어 있다. 그러면 \.{INCH}를 \.{ADDU}인
것처럼 흉내 낼 수 있다.

보충: 원본은 연산 코드의 아래 두 비트로 네 경우를 나누었다. 이것은 |yz|를 $48-16(|op|\bmod4)$
비트만큼 옮기는 것과 같다.

@<|z|를 즉시 와이드로...@>=
z = Octa(yz) << (48 - 16*(op&3))
y = b

@ @<특수 레지스터에서 |b|를...@>=
b = m.g[info[op].thirdOperand]

@ 보충: 원본은 |lhs|를 |sprintf|로 만들었다. 여기서는 |fmt.Sprintf|다.

@<레지스터~X를 목적지로...@>=
if xx >= G {
	lhs = fmt.Sprintf("$%d=g[%d]", xx, xx)
	xPtr = &m.g[xx]
} else {
	for xx >= L {
		@<rL을 늘린다@>
	}
	lhs = fmt.Sprintf("$%d=l[%d]", xx, (O+xx)&m.lringMask)
	xPtr = &m.l[(O+xx)&m.lringMask]
}

@ @<rL을 늘린다@>=
m.l[(O+L)&m.lringMask] = 0
L++
m.g[rL] = Octa(L)
if (m.S-O-L)&m.lringMask == 0 {
	m.stackStore()
}

@ 메서드 |stackStore|는 지역 레지스터의 고리에서 ``감마'' 포인터를 나아가게 한다. 가장
오래된 지역 레지스터를 메모리 위치~rS에 저장하고 rS를 나아가게 하는 것이다.

보충: 원본의 매크로 |test_store_bkpt|와 |test_load_bkpt|는 메서드가 되었다. 그것들은 이
장의 끝에 있다.

@<함수들@>=
func (m *simulator) stackStore() {
	ll := m.memFind(m.g[rS])
	k := m.S & m.lringMask
	ll[0].tet = Tetra(m.l[k] >> 32)
	m.testStoreBkpt(ll[0])
	ll[1].tet = Tetra(m.l[k])
	m.testStoreBkpt(ll[1])
	if m.stackTracing {
		m.tracing = true
		if m.curLine != 0 {
			m.showLine()
		}
		m.printf("             M8[#%016x]=l[%d]=#%016x, rS+=8\n", m.g[rS], k, m.l[k])
	}
	m.g[rS] += 8
	m.S++
}

@ 메서드 |stackLoad|는 본질적으로 |stackStore|의 역이다.

@<함수들@>=
func (m *simulator) stackLoad() {
	m.S--
	m.g[rS] -= 8
	ll := m.memFind(m.g[rS])
	k := m.S & m.lringMask
	m.l[k] = octa(ll)
	m.testLoadBkpt(ll[0])
	m.testLoadBkpt(ll[1])
	if m.stackTracing {
		m.tracing = true
		if m.curLine != 0 {
			m.showLine()
		}
		m.printf("             rS-=8, l[%d]=M8[#%016x]=#%016x\n", k, m.g[rS], m.l[k])
	}
}

@ 멈춤점 비트를 보고 멈추어야 하는지 정한다.

@<함수들@>=
func (m *simulator) testStoreBkpt(t memTetra) {
	if t.bkpt&writeBit != 0 {
		m.breakpoint, m.tracing = true, true
	}
}
@#
func (m *simulator) testLoadBkpt(t memTetra) {
	if t.bkpt&readBit != 0 {
		m.breakpoint, m.tracing = true, true
	}
}

@ 보충: 원본은 옥타바이트를 두 테트라바이트 |ll->tet|와 |(ll+1)->tet|에서 여러 번 모았다.
그 일을 하는 함수를 둔다.

@<함수들@>=
func octa(ll []memTetra) Octa {
	return Octa(ll[0].tet)<<32 | Octa(ll[1].tet)
}

@* 명령 흉내 내기. 큰 스위치는 \MMIX\ 명령마다 하나씩, 256갈래로 갈라진다.

명령 \.{ADD}부터 시작하자. 이것이 어쩐지 가장 전형적인 경우이기 때문이다. 너무 쉽지도 너무
어렵지도 않다. 할 일은 |x=y+z|를 계산하고, 합이 범위를 벗어나면 넘침을 알리는 것이다.
넘침은 |y|와 |z|의 부호가 같은데 합의 부호가 다를 때, 그리고 그때에만 일어난다.

넘침은 산술 예외 여덟 가지 가운데 하나다. 그런 예외는 |exc|라는 변수에 기록한다. 이
변수는 사이클마다 처음에 0이 되고, 끝에서 rA를 고치는 데 쓰인다.

주 제어 루틴은 입력 피연산자를 옥타바이트 |y|와~|z|에 넣어 두었다. 또 결과를 넣을
옥타바이트를 |xPtr|이 가리키게 해 두었다.

@<개별 \MMIX\ 명령의 경우들@>=
case ADD, ADDI:
	x = w // |w=y+z|
	if (y^z)&signBit == 0 && (y^x)&signBit != 0 {
		exc |= vBit
	}
	*xPtr = x

@ 부호 있는 덧셈과 뺄셈, 부호 없는 덧셈과 뺄셈의 다른 경우들도 물론 비슷하다. 계산
|x=y-z|에서 넘침이 일어나는 것은 계산 |y=x+z|에서 넘침이 일어날 때, 그리고 그때뿐이다.

보충: 명령 \.{2ADDU}부터 \.{16ADDU}까지는 연산 코드의 아래 넷째 비트부터 둘째 비트까지가 옮길
비트 수에 3을 더한 값이다.

@<개별 \MMIX\ 명령의 경우들@>=
case SUB, SUBI, NEG, NEGI:
	x = y - z
	if (x^z)&signBit == 0 && (x^y)&signBit != 0 {
		exc |= vBit
	}
	*xPtr = x
case ADDU, ADDUI, INCH, INCMH, INCML, INCL:
	x = w
	*xPtr = x
case SUBU, SUBUI, NEGU, NEGUI:
	x = y - z
	*xPtr = x
case IIADDU, IIADDUI, IVADDU, IVADDUI, VIIIADDU, VIIIADDUI, XVIADDU, XVIADDUI:
	x = y<<((op&0xf)>>1-3) + z
	*xPtr = x
case SETH, SETMH, SETML, SETL, GETA, GETAB:
	x = z
	*xPtr = x

@ 간단한 비트 연산들도 치워 버리자.

@<개별 \MMIX\ 명령의 경우들@>=
case OR, ORI, ORH, ORMH, ORML, ORL:
	x = y | z
	*xPtr = x
case ORN, ORNI:
	x = y | ^z
	*xPtr = x
case NOR, NORI:
	x = ^(y | z)
	*xPtr = x
case XOR, XORI:
	x = y ^ z
	*xPtr = x
case AND, ANDI:
	x = y & z
	*xPtr = x
case ANDN, ANDNI, ANDNH, ANDNMH, ANDNML, ANDNL:
	x = y &^ z
	*xPtr = x
case NAND, NANDI:
	x = ^(y & z)
	*xPtr = x
case NXOR, NXORI:
	x = ^(y ^ z)
	*xPtr = x

@ 덜 간단한 비트 조작도, {\mc MMIX-ARITH}의 서브루틴이 있으니 거의 마찬가지로 간단하다.
연산 \.{MUX}는 입력이 셋이다. 그런 경우에 입력은 |y|, |z|, |b|에 있다.

보충: 원본의 매크로 |shift_amt|는 |z|가 64 이상이면 64가 된다. \GO/에서는 64비트 수를 64
비트 옮기면 0이 되고, 부호 있는 수를 오른쪽으로 64비트 옮기면 부호 비트로 채워진다. 이것은
원본의 |shift_left|와 |shift_right|가 하는 일과 같다. 원본의 \.{TDIF}와 \.{ODIF}는 |goto
tdif_l|로 코드를 함께 썼다. 64비트 수에서 \.{ODIF}는 그냥 |y>z|이면 |y-z|, 아니면 0이다.

@<개별 \MMIX\ 명령의 경우들@>=
case SL, SLI:
	sa := shiftAmt(z)
	x = y << sa
	a = mmixarith.ShiftRight(x, sa, false)
	if a != y {
		exc |= vBit
	}
	*xPtr = x
case SLU, SLUI:
	x = y << shiftAmt(z)
	*xPtr = x
case SR, SRI, SRU, SRUI:
	x = mmixarith.ShiftRight(y, shiftAmt(z), op&0x2 != 0)
	*xPtr = x
case MUX, MUXI:
	x = y&b | z&^b
	*xPtr = x
case SADD, SADDI:
	x = Octa(bits.OnesCount64(y &^ z))
	*xPtr = x

@ 보충: 나머지 비트 조작들이다. 명령 \.{BDIF}와 \.{WDIF}는 \.{mmixarith}가 64비트 전체를 한꺼번에
다룬다. 원본은 테트라마다 따로 불렀다.

@<개별 \MMIX\ 명령의 경우들@>=
case MOR, MORI:
	x = mmixarith.BoolMult(y, z, false)
	*xPtr = x
case MXOR, MXORI:
	x = mmixarith.BoolMult(y, z, true)
	*xPtr = x
case BDIF, BDIFI:
	x = mmixarith.ByteDiff(y, z)
	*xPtr = x
case WDIF, WDIFI:
	x = mmixarith.WydeDiff(y, z)
	*xPtr = x
case TDIF, TDIFI:
	if y>>32 > z>>32 {
		x = (y>>32 - z>>32) << 32
	}
	if Tetra(y) > Tetra(z) {
		x |= Octa(Tetra(y) - Tetra(z))
	}
	*xPtr = x
case ODIF, ODIFI:
	if y > z {
		x = y - z
	}
	*xPtr = x

@ @<함수들@>=
func shiftAmt(z Octa) int {
	if z >= 64 {
		return 64
	}
	return int(z)
}

@ 연산의 출력이 둘이면, 주된 출력은 |x|에, 곁 출력은 |a|에 둔다.

보충: 원본에서 나눗셈의 나머지는 전역 변수 |aux|로, 넘침은 전역 변수 |overflow|로 돌아왔다.
여기서는 반환값이다. 64비트 곱의 윗부분은 |bits.Mul64|의 첫째 반환값이다.

@<개별 \MMIX\ 명령의 경우들@>=
case MUL, MULI:
	var overflow bool
	x, overflow = mmixarith.SignedMult(y, z)
	if overflow {
		exc |= vBit
	}
	*xPtr = x
case MULU, MULUI:
	a, x = bits.Mul64(y, z)
	m.g[rH] = a
	*xPtr = x
case DIV, DIVI:
	var r Octa
	overflow := false
	if z == 0 {
		r = y
		exc |= dBit
	} else {
		x, r, overflow = mmixarith.SignedDiv(y, z)
	}
	a = r
	m.g[rR] = r
	if overflow {
		exc |= vBit
	}
	*xPtr = x
case DIVU, DIVUI:
	x, a = mmixarith.Div(b, y, z)
	m.g[rR] = a
	*xPtr = x

@ {\mc MMIX-ARITH}의 부동소수점 루틴들은 예외적인 사건을 |exceptions|라는 변수에
기록한다. 여기서는 그 비트들을 그냥 |exc| 변수에 합친다. 비트 |uBit|는 ``아래넘침''과 꼭
같지는 않지만, 아래넘침의 참된 정의는 |exc|를 rA와 합칠 때 적용된다.

보충: 옮긴 \.{mmixarith}에서 예외 비트는 둘째 반환값으로 돌아온다. 원본은 반올림 방식
0을 ``현재 방식''으로 알아듣는 일을 {\mc MMIX-ARITH} 안에서 했는데, 옮긴 \.{mmixarith}에서는
부르는 쪽이 한다. 그래서 여기서는 불법 명령인지를 먼저 따지고 반올림 방식을 정한 뒤에
계산한다. 원본은 계산을 먼저 하고 그 결과를 버렸는데, 계산에는 부수 효과가 없으므로 두
순서의 결과는 같다. 원본의 이름표 |fin_float|와 |fin_unifloat|는 두 무리의 경우가 함께
쓰는 꼬리였다.

@<개별 \MMIX\ 명령의 경우들@>=
case FADD, FSUB, FMUL, FDIV, FREM:
	var e int
	switch op {
	case FADD:
		x, e = mmixarith.FPlus(y, z, curRound)
	case FSUB:
		a = z
		if mmixarith.FComp(a, 0) != 2 {
			a ^= signBit
		}
		x, e = mmixarith.FPlus(y, a, curRound)
	case FMUL:
		x, e = mmixarith.FMult(y, z, curRound)
	case FDIV:
		x, e = mmixarith.FDivide(y, z, curRound)
	case FREM:
		x, e = mmixarith.FRemStep(y, z, 2500)
	}
	roundMode = curRound
	exc |= e
	*xPtr = x

@ 보충: 피연산자가 하나인 부동소수점 명령에서는 Y~필드가 반올림 방식이다. 4보다 크면
불법 명령이다. 명령 \.{FIXU}는 넘침을 알리지 않는다.

@<개별 \MMIX\ 명령의 경우들@>=
case FSQRT, FINT, FIX, FIXU, FLOT, FLOTI, FLOTU, FLOTUI,
	SFLOT, SFLOTI, SFLOTU, SFLOTUI:
	if y > 4 {
		trouble = "!illegal"
		break perform
	}
	roundMode = curRound
	if y != 0 {
		roundMode = mmixarith.Round(y)
	}
	var e int
	switch op {
	case FSQRT:
		x, e = mmixarith.FRoot(z, roundMode)
	case FINT:
		x, e = mmixarith.FIntegerize(z, roundMode)
	case FIX:
		x, e = mmixarith.FixIt(z, roundMode)
	case FIXU:
		x, e = mmixarith.FixIt(z, roundMode)
		e &^= wBit
	default:
		x, e = mmixarith.FloatIt(z, roundMode, op&0x2 != 0, op&0x4 != 0)
	}
	exc |= e
	*xPtr = x

@ 이제 산술 연산은, 두 레지스터를 비교해서 $-1$이나 0이나 1을 내는 경우들을 빼고 모두
끝냈다.

보충: 원본은 이 경우들을 |cmp_neg|, |cmp_pos|, |cmp_zero|, |cmp_fin| 따위의 이름표 사이를
|goto|로 오가며 처리했다. 원본의 매크로 |cmp_zero|는 |store_x|였다. 결과 |x|는 처음에 0이기
때문이다. 명령 \.{FCMPE}는 $y\sim z\ (\epsilon)$이거나 비교가 잘못되었으면(|FEpsComp|의 결과가
1이나 2이면) 0을 내고, 그렇지 않으면 \.{FCMP}처럼 한다. 함수 |FComp|는 $y<z$, $y=z$, $y>z$,
$y\parallel z$일 때 각각 $-1$, 0, 1, 2를 돌려준다.

@<개별 \MMIX\ 명령의 경우들@>=
case CMP, CMPI:
	if int64(y) < int64(z) {
		x = negOne
	} else if y != z {
		x = 1
	}
	*xPtr = x
case CMPU, CMPUI:
	if y < z {
		x = negOne
	} else if y != z {
		x = 1
	}
	*xPtr = x

@ @<개별 \MMIX\ 명령의 경우들@>=
case FCMP, FCMPE:
	k = 0
	if op == FCMPE {
		k = mmixarith.FEpsComp(y, z, b, true)
	}
	if k == 0 {
		k = mmixarith.FComp(y, z)
		if k < 0 {
			x = negOne
		} else if k == 1 {
			x = 1
		}
	}
	if k == 2 {
		exc |= iBit
	}
	*xPtr = x
case FUN:
	if mmixarith.FComp(y, z) == 2 {
		x = 1
	}
	*xPtr = x
case FEQL:
	if mmixarith.FComp(y, z) == 0 {
		x = 1
	}
	*xPtr = x
case FEQLE:
	k = mmixarith.FEpsComp(y, z, b, false)
	if k == 1 {
		x = 1
	} else if k == 2 {
		exc |= iBit
	}
	*xPtr = x
case FUNE:
	if mmixarith.FEpsComp(y, z, b, true) == 2 {
		x = 1
	}
	*xPtr = x

@ 이제 레지스터와 레지스터 사이의 연산은 조건부 명령들을 빼고 모두 끝냈다. 조건부 명령과
분기 명령은 모두 간단한 서브루틴 하나를 쓴다. 이 서브루틴은 주어진 옥타바이트가 주어진
연산 코드의 조건을 만족하는지 판정한다.

@<함수들@>=
func registerTruth(o Octa, op int) bool {
	var b bool
	switch (op >> 1) & 0x3 {
	case 0:
		b = o&signBit != 0 // 음수인가?
	case 1:
		b = o == 0 // 0인가?
	case 2:
		b = o < signBit && o != 0 // 양수인가?
	case 3:
		b = o&0x1 != 0 // 홀수인가?
	}
	if op&0x8 != 0 {
		return !b
	}
	return b
}

@ 피연산자 |b|는 \.{ZS} 연산에서는 0이고, \.{CS} 연산에서는 레지스터~X의 내용이다.

@<개별 \MMIX\ 명령의 경우들@>=
case CSN, CSNI, CSZ, CSZI, CSP, CSPI, CSOD, CSODI,
	CSNN, CSNNI, CSNZ, CSNZI, CSNP, CSNPI, CSEV, CSEVI,
	ZSN, ZSNI, ZSZ, ZSZI, ZSP, ZSPI, ZSOD, ZSODI,
	ZSNN, ZSNNI, ZSNZ, ZSNZI, ZSNP, ZSNPI, ZSEV, ZSEVI:
	if registerTruth(y, op) {
		x = z
	} else {
		x = b
	}
	*xPtr = x

@ 연산 코드 32개가 경우 하나로 줄어드니 기분 좋지 않은가? 한 번 더 그렇게 해 보자.
행복하다!

보충: 원본은 짐작이 틀렸을 때의 벌칙 $2\upsilon$를 |sclock.l+=2|로 더했다. 아랫 테트라에서
올림이 생겨도 윗 테트라로 넘기지 않는다. 원본과 같은 결과를 내려고 여기서도 아랫 32비트에만
더한다.

@<개별 \MMIX\ 명령의 경우들@>=
case BN, BNB, BZ, BZB, BP, BPB, BOD, BODB,
	BNN, BNNB, BNZ, BNZB, BNP, BNPB, BEV, BEVB,
	PBN, PBNB, PBZ, PBZB, PBP, PBPB, PBOD, PBODB,
	PBNN, PBNNB, PBNZ, PBNZB, PBNP, PBNPB, PBEV, PBEVB:
	if registerTruth(b, op) {
		x = 1
		m.instPtr = z
		good = op >= PBN
	} else {
		good = op < PBN
	}
	if good {
		m.goodGuesses++
	} else {
		m.badGuesses++
		m.sclock = m.sclock&^0xffffffff | Octa(Tetra(m.sclock)+2) // 짐작이 틀리면 벌칙은 $2\upsilon$
		if m.g[rI] <= 2 && m.g[rI] != 0 {
			m.tracing, m.breakpoint = true, true
		}
		m.g[rI] -= 2
	}

@ 다음 차례는 메모리 연산이다. 메모리 주소 |y+z|는 이미 |w|에 들어 있다.

보충: 원본은 |i|와 |j|를 정한 뒤 |goto fin_ld|로 공통 부분에 갔고, 주소가 음수인지를
|check_ld|에서 따졌다. 명령 \.{LDHT}는 연산 코드의 아래 두 비트를 지우면 \.{LDSF}와 같아지므로
|default|에 온다.

@<개별 \MMIX\ 명령의 경우들@>=
case LDB, LDBI, LDBU, LDBUI, LDW, LDWI, LDWU, LDWUI,
	LDT, LDTI, LDTU, LDTUI, LDHT, LDHTI:
	switch op &^ 3 {
	case LDB:
		i, j = 56, int(w&0x3)<<3
	case LDW:
		i, j = 48, int(w&0x2)<<3
	case LDT:
		i, j = 32, 0
	default:
		i, j = 0, 0
	}
	ll = m.memFind(w)
	m.testLoadBkpt(ll[0])
	x = mmixarith.ShiftRight(Octa(ll[0].tet)<<32<<j, i, op&0x2 != 0)
	@<|w|가 음수이면 특권 명령이고, 아니면 |x|를 저장한다@>
case LDO, LDOI, LDOU, LDOUI, LDUNC, LDUNCI:
	w &^= 7
	ll = m.memFind(w)
	m.testLoadBkpt(ll[0])
	m.testLoadBkpt(ll[1])
	x = octa(ll)
	@<|w|가 음수이면 특권 명령이고...@>
case LDSF, LDSFI:
	ll = m.memFind(w)
	m.testLoadBkpt(ll[0])
	x = mmixarith.LoadSF(ll[0].tet)
	@<|w|가 음수이면 특권 명령이고...@>

@ @<|w|가 음수이면 특권 명령이고...@>=
if w&signBit != 0 {
	trouble = "!privileged"
} else {
	*xPtr = x
}

@ 보충: 원본은 여기서도 |goto fin_pst|, |goto fin_st|, |goto check_st|로 공통 부분을 함께
썼다. 부분 저장에서는 테트라바이트 안의 알맞은 바이트들만 바꾼다. 부호 있는 저장이면
값이 그 크기에 들어가는지 따져서 넘침을 알린다.

@<개별 \MMIX\ 명령의 경우들@>=
case STB, STBI, STBU, STBUI, STW, STWI, STWU, STWUI,
	STT, STTI, STTU, STTUI:
	switch op &^ 3 {
	case STB:
		i, j = 56, int(w&0x3)<<3
	case STW:
		i, j = 48, int(w&0x2)<<3
	default:
		i, j = 32, 0
	}
	ll = m.memFind(w)
	if op&0x2 == 0 {
		a = mmixarith.ShiftRight(b<<i, i, false)
		if a != b {
			exc |= vBit
		}
	}
	ll[0].tet ^= (ll[0].tet ^ Tetra(b)<<(i-32-j)) & (^Tetra(0) << (i - 32) >> j)
	@<부분 저장을 마친다@>
case STSF, STSFI:
	ll = m.memFind(w)
	ll[0].tet, exc = mmixarith.StoreSF(b, curRound)
	@<부분 저장을 마친다@>
case STHT, STHTI:
	ll = m.memFind(w)
	ll[0].tet = Tetra(b >> 32)
	@<부분 저장을 마친다@>
case STCO, STCOI, STO, STOI, STOU, STOUI, STUNC, STUNCI:
	if op&^1 == STCO {
		b = Octa(xx)
	}
	w &^= 7
	ll = m.memFind(w)
	m.testStoreBkpt(ll[0])
	m.testStoreBkpt(ll[1])
	ll[0].tet, ll[1].tet = Tetra(b>>32), Tetra(b)
	if w&signBit != 0 {
		trouble = "!privileged"
	}

@ @<부분 저장을 마친다@>=
m.testStoreBkpt(ll[0])
w &^= 7
ll = m.memFind(w)
a = octa(ll) // 추적 출력을 위해
if w&signBit != 0 {
	trouble = "!privileged"
}

@ 연산 \.{CSWAP}에는 적재와 저장의 요소가 모두 있다. 추적 출력에 알맞게 나오도록
피연산자 몇 개를 뒤섞는다.

@<개별 \MMIX\ 명령의 경우들@>=
case CSWAP, CSWAPI:
	w &^= 7
	ll = m.memFind(w)
	m.testLoadBkpt(ll[0])
	m.testLoadBkpt(ll[1])
	a = m.g[rP]
	if octa(ll) == a {
		x = 1
		m.testStoreBkpt(ll[0])
		m.testStoreBkpt(ll[1])
		ll[0].tet, ll[1].tet = Tetra(b>>32), Tetra(b)
		rhs = "M8[%#w]=%#b"
	} else {
		b = octa(ll)
		m.g[rP] = b
		rhs = "rP=%#b"
	}
	@<|w|가 음수이면 특권 명령이고...@>

@ 명령 \.{GET}은 너그럽지만, \.{PUT}은 까다롭다.

@<개별 \MMIX\ 명령의 경우들@>=
case GET:
	if yy != 0 || zz >= 32 {
		trouble = "!illegal"
		break perform
	}
	x = m.g[zz]
	*xPtr = x
case PUT, PUTI:
	if yy != 0 || xx >= 32 {
		trouble = "!illegal"
		break perform
	}
	rhs = "%z = %#z"
	if xx >= 8 {
		if xx <= 11 && xx != 8 {
			trouble = "!illegal" // rN, rO, rS는 바꿀 수 없다
			break perform
		}
		if xx <= 18 {
			trouble = "!privileged"
			break perform
		}
		if xx == rA {
			@<rA를 고칠 준비를 한다@>
		} else if xx == rL {
			@<$L=z=\min(z,L)$로 한다@>
		} else if xx == rG {
			@<rG를 고칠 준비를 한다@>
		}
	}
	m.g[xx] = z
	zz = xx

@ @<$L=z=\min(z,L)$로 한다@>=
x = z
if z>>32 != 0 {
	rhs = "min(rL,%#x) = %z"
} else {
	rhs = "min(rL,%x) = %z"
}
if Tetra(z) > Tetra(L) || z>>32 != 0 {
	z = Octa(L)
} else {
	L = int(z)
	oldL = L
}

@ @<rG를 고칠 준비를 한다@>=
if z > 255 || z < Octa(L) || z < 32 {
	trouble = "!illegal"
	break perform
}
for j = int(z); j < G; j++ {
	m.g[j] = 0
}
G = int(z)

@ 원본은 여기서 반올림 방식의 번호 \.{ROUND\_OFF}~(1), \.{ROUND\_UP}~(2), \.{ROUND\_DOWN}~(3),
\.{ROUND\_NEAR}~(4)를 정의했다. 옮긴 \.{mmixarith}에는 |RoundOff|부터 |RoundNear|까지가 같은
값으로 정의되어 있다.

@<rA를 고칠 준비를 한다@>=
if z >= 0x40000 {
	trouble = "!illegal"
	break perform
}
if z >= 0x10000 {
	curRound = mmixarith.Round(z >> 16)
} else {
	curRound = mmixarith.RoundNear
}

@ 넣기와 꺼내기는 꽤 까다롭다. 추적 출력이 앞뒤가 맞게 나오기를 바라기 때문이다.

보충: 원본은 \.{PUSHGO}와 \.{PUSHJ}가 다음 명령의 위치를 정한 뒤 |goto push|로 공통 부분에
갔다. 명령 \.{POP}은 |goto sync_L|로 \.{PUSH}의 마지막 줄을 함께 썼다. 원본의 |sprintf|
\.{"l[\%d]=\#\%x\%08x, "}는 윗 테트라가 0이 아닐 때 쓰였는데, 64비트 수를 \.{\%x}로 찍는
것과 같다.

@<개별 \MMIX\ 명령의 경우들@>=
case PUSHGO, PUSHGOI, PUSHJ, PUSHJB:
	if op == PUSHGO || op == PUSHGOI {
		m.instPtr = w
	} else {
		m.instPtr = z
	}
	if xx >= G {
		xx = L
		L++
		if (m.S-O-L)&m.lringMask == 0 {
			m.stackStore()
		}
	}
	x = Octa(xx)
	m.l[(O+xx)&m.lringMask] = x // ``구멍''은 밀어 넣은 양을 기록한다
	lhs = fmt.Sprintf("l[%d]=%d, ", (O+xx)&m.lringMask, xx)
	x = loc + 4
	m.g[rJ] = x
	L -= xx + 1
	O += xx + 1
	b = m.g[rO] + Octa((xx+1)<<3)
	m.g[rO] = b
	a = Octa(L)
	m.g[rL] = a

@ 보충: 명령 \.{POP}은 먼저 돌려줄 값 |y|를 잡아 두고, 스택에서 꺼낼 만큼 레지스터를 메모리에서
되살린다. ``구멍''에 기록된 수 |k|가 밀어 넣었던 레지스터의 개수다.

@<개별 \MMIX\ 명령의 경우들@>=
case POP:
	if xx != 0 && xx <= L {
		y = m.l[(O+xx-1)&m.lringMask]
	}
	if Tetra(m.g[rS]) == Tetra(m.g[rO]) {
		m.stackLoad()
	}
	k = int(m.l[(O-1)&m.lringMask] & 0xff)
	for Tetra(O-m.S) <= Tetra(k) {
		m.stackLoad()
	}
	if xx <= L {
		L = k + xx
	} else {
		L = k + L + 1
	}
	if L > G {
		L = G
	}
	if L > k {
		m.l[(O-1)&m.lringMask] = y
		lhs = fmt.Sprintf("l[%d]=#%x, ", (O-1)&m.lringMask, y)
	} else {
		lhs = ""
	}
	y = m.g[rJ]
	z = Octa(yz << 2)
	m.instPtr = y + z
	O -= k + 1
	b = m.g[rO] - Octa((k+1)<<3)
	m.g[rO] = b
	a = Octa(L)
	m.g[rL] = a

@ \MMIX의 레지스터 스택을 흉내 내는 일을 마무리하려면 \.{SAVE}와 \.{UNSAVE}를 구현해야
한다.

보충: 원본은 \.{SAVE}가 쌓는 ``구멍''에 |l[(O+L)&lring_mask].l=L|로 아랫 테트라만
넣었다. 그래서 그 옥타바이트의 윗 테트라에는 앞서 그 자리를 쓴 레지스터의 값이 남는다.
여기서도 그대로 흉내 낸다.

@<개별 \MMIX\ 명령의 경우들@>=
case SAVE:
	if xx < G || yy != 0 || zz != 0 {
		trouble = "!illegal"
		break perform
	}
	i = (O + L) & m.lringMask
	m.l[i] = m.l[i]&^0xffffffff | Octa(L)
	L++
	if (m.S-O-L)&m.lringMask == 0 {
		m.stackStore()
	}
	O += L
	m.g[rO] += Octa(L << 3)
	L = 0
	m.g[rL] = 0
	for Tetra(m.g[rO]) != Tetra(m.g[rS]) {
		m.stackStore()
	}
	for k = G; ; {
		@<|g[k]|를 레지스터 스택에 저장한다@>
		if k == 255 {
			k = rB
		} else if k == rR {
			k = rP
		} else if k == rZ+1 {
			break
		} else {
			k++
		}
	}
	O = m.S
	m.g[rO] = m.g[rS]
	x = m.g[rO] - 8
	*xPtr = x

@ 프로그램의 이 부분은 당연히 |stackStore| 서브루틴과 닮은 데가 많다. (절 이름에 작은
거짓말이 하나 있다. 색인 |k|가 |rZ+1|이면 |g[k]|가 아니라 rG와 rA를 저장한다.)

@<|g[k]|를 레지스터 스택에...@>=
ll = m.memFind(m.g[rS])
if k == rZ+1 {
	x = Octa(G)<<56 | Octa(Tetra(m.g[rA]))
} else {
	x = m.g[k]
}
ll[0].tet = Tetra(x >> 32)
m.testStoreBkpt(ll[0])
ll[1].tet = Tetra(x)
m.testStoreBkpt(ll[1])
if m.stackTracing {
	m.tracing = true
	if m.curLine != 0 {
		m.showLine()
	}
	if k >= 32 {
		m.printf("             M8[#%016x]=g[%d]=#%016x, rS+=8\n", m.g[rS], k, x)
	} else {
		name := "(rG,rA)"
		if k != rZ+1 {
			name = specialName[k]
		}
		m.printf("             M8[#%016x]=%s=#%016x, rS+=8\n", m.g[rS], name, x)
	}
}
m.S++
m.g[rS] += 8

@ @<개별 \MMIX\ 명령의 경우들@>=
case UNSAVE:
	if xx != 0 || yy != 0 {
		trouble = "!illegal"
		break perform
	}
	z &^= 7
	m.g[rS] = z + 8
	for k = rZ + 1; ; {
		@<레지스터 스택에서 |g[k]|를 적재한다@>
		if k == rP {
			k = rR
		} else if k == rB {
			k = 255
		} else if k == G {
			break
		} else {
			k--
		}
	}
	m.S = int(Tetra(m.g[rS]) >> 3)
	m.stackLoad()
	k = int(m.l[m.S&m.lringMask] & 0xff)
	for j = 0; j < k; j++ {
		m.stackLoad()
	}
	O = m.S
	m.g[rO] = m.g[rS]
	if k > G {
		L = G
	} else {
		L = k
	}
	m.g[rL] = Octa(L)
	a = m.g[rL]
	m.g[rG] = Octa(G)

@ @<레지스터 스택에서 |g[k]|를...@>=
m.g[rS] -= 8
ll = m.memFind(m.g[rS])
m.testLoadBkpt(ll[0])
m.testLoadBkpt(ll[1])
if k == rZ+1 {
	G = int(ll[0].tet >> 24)
	x = Octa(G)
	m.g[rG] = x
	a = Octa(ll[1].tet & 0x3ffff)
	m.g[rA] = a
	if G < 32 {
		G = 32
		x = 32
		m.g[rG] = 32
	}
} else {
	m.g[k] = octa(ll)
}
if m.stackTracing {
	m.tracing = true
	if m.curLine != 0 {
		m.showLine()
	}
	if k >= 32 {
		m.printf("             rS-=8, g[%d]=M8[#%016x]=#%016x\n", k, m.g[rS], octa(ll))
	} else if k == rZ+1 {
		m.printf("             (rG,rA)=M8[#%016x]=#%016x\n", m.g[rS], octa(ll))
	} else {
		m.printf("             rS-=8, %s=M8[#%016x]=#%016x\n",
			specialName[k], m.g[rS], octa(ll))
	}
}

@ 캐시를 관리하는 명령들은 이 시뮬레이션에 아무 영향도 주지 않는다. 캐시가 없기
때문이다. 그러나 사용자가 그런 명령을 썼다면, 추적할 때 그 명령이 미치는 범위를 알려
주는 정보를 조금 준다.

@<개별 \MMIX\ 명령의 경우들@>=
case SYNCID, SYNCIDI, PREST, PRESTI, SYNCD, SYNCDI, PREGO, PREGOI, PRELD, PRELDI:
	x = w + Octa(xx)

@ 아직 몇 가지 매듭을 지어야 한다.

보충: 원본에서 \.{JMP}는 다음 경우인 \.{SWYM}으로 흘러내렸고, \.{SYNC}는 |zz>3|이면
\.{LDVTS}로 흘러내려 특권 명령이 되었다. 특권 명령과 불법 명령의 공통 꼬리는 다음 절에
있다.

@<개별 \MMIX\ 명령의 경우들@>=
case GO, GOI:
	x = m.instPtr
	m.instPtr = w
	*xPtr = x
case JMP, JMPB:
	m.instPtr = z
case SWYM:
case SYNC:
	if xx != 0 || yy != 0 || zz > 7 {
		trouble = "!illegal"
	} else if zz > 3 {
		trouble = "!privileged"
	}
case LDVTS, LDVTSI:
	trouble = "!privileged"

@ 특권 명령이나 불법 명령이면 멈춤점처럼 멈추고 추적한다. 대화 방식이 아니면 프로그램을
멈춘다.

@<명령을 특권 명령이나 불법 명령으로 처리한다@>=
lhs = trouble
m.breakpoint, m.tracing = true, true
if !m.interacting && !m.interactAfterBreak {
	m.halted = true
}

@* 트립과 트랩. 이제 명령 256개 가운데 253개를 구현했다. 남은 것은
\.{TRIP}, \.{TRAP}, \.{RESUME}뿐이다.

명령 \.{TRIP}은 |exc| 변수의 |hBit|를 켜기만 한다. 그러면 위치~0으로 가는 인터럽트가
일어난다.
@^interrupts@>

명령 \.{TRAP}은 들어가며에서 말한 시스템 호출들을 빼면 흉내 내지 않는다.

보충: 원본은 입출력 서브루틴을 |unsigned char| 핸들로 불렀다. 여기서는 \.{mmixio}의
메서드를 |byte(zz)|로 부른다.

@<개별 \MMIX\ 명령의 경우들@>=
case TRIP:
	exc |= hBit
case TRAP:
	if xx != 0 || yy > maxSysCall {
		trouble = "!privileged"
		break perform
	}
	rhs = trapFormat[yy]
	m.g[rWW] = m.instPtr
	m.g[rXX] = signBit | Octa(inst)
	m.g[rYY], m.g[rZZ] = y, z
	z = Octa(zz)
	a = b + 8
	@<필요하면 메모리 인자 $|ma|={\rm M}[a]$와 $|mb|={\rm M}[b]$를 준비한다@>
	@<시스템 호출 |yy|를 부른다@>
	x = m.g[rBB]
	m.g[255] = x

@ @<시스템 호출 |yy|를 부른다@>=
switch yy {
case Halt:
	@<멈추거나 경고를 찍는다@>
	m.g[rBB] = m.g[255]
case Fopen:
	m.g[rBB] = m.io.Fopen(byte(zz), mb, ma)
case Fclose:
	m.g[rBB] = m.io.Fclose(byte(zz))
case Fread:
	m.g[rBB] = m.io.Fread(byte(zz), mb, ma)
case Fgets:
	m.g[rBB] = m.io.Fgets(byte(zz), mb, ma)
case Fgetws:
	m.g[rBB] = m.io.Fgetws(byte(zz), mb, ma)
case Fwrite:
	m.g[rBB] = m.io.Fwrite(byte(zz), mb, ma)
case Fputs:
	m.g[rBB] = m.io.Fputs(byte(zz), b)
case Fputws:
	m.g[rBB] = m.io.Fputws(byte(zz), b)
case Fseek:
	m.g[rBB] = m.io.Fseek(byte(zz), b)
case Ftell:
	m.g[rBB] = m.io.Ftell(byte(zz))
}

@ 보충: 호출 \.{TRAP}~\.{0,Halt,1}은 트립 처리기가 트립 경고를 찍게 하는 특별한 호출이다. 위치
\Hex{0}부터 \Hex{80}까지의 트립 처리기 안에서만 쓸 수 있고, 경고에는 트립을 일으킨 명령의
위치 $\rm rW-4$가 나온다.

@<멈추거나 경고를 찍는다@>=
if zz == 0 {
	m.halted, m.breakpoint = true, true
} else if zz == 1 {
	if loc >= 0x90 {
		trouble = "!privileged"
		break perform
	}
	m.io.PrintTripWarning(int(loc>>4), m.g[rW]-4)
} else {
	trouble = "!privileged"
	break perform
}

@ @<표@>=
var argCount = [...]int{1, 3, 1, 3, 3, 3, 3, 2, 2, 2, 1}
@#
var trapFormat = [...]string{
	"Halt(%z)",
	"$255 = Fopen(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fclose(%!z) = %x",
	"$255 = Fread(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fgets(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fgetws(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fwrite(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fputs(%!z,%#b) = %x",
	"$255 = Fputws(%!z,%#b) = %x",
	"$255 = Fseek(%!z,%b) = %x",
	"$255 = Ftell(%!z) = %x"}

@ 보충: 원본은 |mem_find(b)|로 찾은 테트라바이트와 그다음 테트라바이트 |ll+1|에서
옥타바이트를 모았다. 주소 |b|는 \$255의 값이므로 8의 배수가 아닐 수도 있다. 그 주소가
덩이의 마지막 테트라바이트이면 원본의 |ll+1|은 덩이 밖을 읽는다(정의되지 않은 동작이다).
원본을 시험한 macOS에서는 그 자리가 0으로 읽혔으므로, 여기서도 0으로 친다. 그 밖의
경우에는 원본과 같은 테트라바이트다. 이 일은 두 번 하므로 메서드 |memArg|로 둔다.

@<필요하면 메모리 인자...@>=
if argCount[yy] == 3 {
	mb = m.memArg(b)
	ma = m.memArg(a)
}

@ @<함수들@>=
func (m *simulator) memArg(addr Octa) Octa {
	ll := m.memFind(addr)
	m.testLoadBkpt(ll[0])
	o := Octa(ll[0].tet) << 32
	if len(ll) > 1 {
		m.testLoadBkpt(ll[1])
		o |= Octa(ll[1].tet)
	}
	return o
}

@ 명령 \.{TRAP}이 부르는 입출력 연산들은 {\mc MMIX-IO}라는 보조 프로그램 모듈의 서브루틴들이
한다. 여기서는 그 서브루틴들을 선언하고, 그것들이 기대는 기본 인터페이스 세 개를 쓰기만
하면 된다.

보충: \GO/에서는 \.{mmixio} 꾸러미를 가져오고, 그 꾸러미의 인터페이스 |mmixio.Simulator|가
요구하는 메서드 세 개 |MMGetChars|, |MMPutChars|, |StdinChr|을 |simulator|에 정의한다.
원본의 |mmix_io_init|은 |mmixio.New|가 되었다.

@ 서브루틴 |mmgetchars(buf,size,addr,stop)|은 모의 메모리의 주소 |addr|에서 시작해서
문자들을 읽어 |buf|에 넣는다. 문자를 |size|개 읽었거나 다른 어떤 멈춤 조건을 만날 때까지
계속한다. 인자 |stop|이 음수이면 다른 조건이 없다. 그것이 0이면 널 문자에서도 멈춘다. 그 밖에는
|addr|이 짝수이고, 짝수 주소에서 시작하는 연이은 널 바이트 둘에서 멈춘다. 읽어서 넣은
바이트의 개수를 돌려주는데, 끝을 알리는 널 문자는 세지 않는다.

보충: 원본에서 |m|은 읽은 개수이고 |p|는 |buf+m|이었다. \GO/에서는 수신자 이름이 |m|이므로
색인 |k| 하나로 둘을 대신한다.

@<함수들@>=
func (m *simulator) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	a := addr
	for k := 0; k < size; {
		ll := m.memFind(a)
		m.testLoadBkpt(ll[0])
		x := ll[0].tet
		if a&0x3 != 0 || k > size-4 {
			@<바이트 하나를 읽어서 넣는다; 끝났으면 |return|한다@>
		} else {
			@<바이트를 넷까지 읽어서 넣는다; 끝났으면 |return|한다@>
		}
	}
	return size
}

@ 보충: 호출 \.{Fputws}는 문자열의 주소를 짝수로 맞추지 않고 이 서브루틴을 부른다. 그래서
홀수 주소의 첫 바이트가 0이면, 원본은 |buf|의 앞 바이트 |*(p-1)|을 읽는다(정의되지 않은
동작이다). 원본을 시험한 macOS에서는 그 바이트가 0이어서 $-1$을 돌려주었다. 여기서도 그
바이트를 0으로 쳐서 $-1$을 돌려준다. 그 뒤의 일은 \.{mmixio}의 |Fputws|를 보라. 원본은
표준 출력이나 파일에 쓸 때 이 값 때문에 죽는다.

@<바이트 하나를 읽어서 넣는다...@>=
buf[k] = byte(x >> (8 * (^a & 0x3)))
if buf[k] == 0 && stop >= 0 {
	if stop == 0 {
		return k
	}
	if a&0x1 != 0 && (k == 0 || buf[k-1] == 0) {
		return k - 1
	}
}
k++
a++

@ @<바이트를 넷까지 읽어서 넣는다...@>=
buf[k] = byte(x >> 24)
if buf[k] == 0 && (stop == 0 || stop > 0 && x < 0x10000) {
	return k
}
buf[k+1] = byte(x >> 16)
if buf[k+1] == 0 && stop == 0 {
	return k + 1
}
buf[k+2] = byte(x >> 8)
if buf[k+2] == 0 && (stop == 0 || stop > 0 && x&0xffff == 0) {
	return k + 2
}
buf[k+3] = byte(x)
if buf[k+3] == 0 && stop == 0 {
	return k + 3
}
k += 4
a += 4

@ 서브루틴 |mmputchars(buf,size,addr)|는 |size|개의 문자를 주소 |addr|에서 시작하는 모의
메모리에 넣는다.

@<함수들@>=
func (m *simulator) MMPutChars(buf []byte, size int, addr Octa) {
	a := addr
	for k := 0; k < size; {
		ll := m.memFind(a)
		m.testStoreBkpt(ll[0])
		if a&0x3 != 0 || k > size-4 {
			@<바이트 하나를 적재해서 쓴다@>
		} else {
			@<바이트 넷을 적재해서 쓴다@>
		}
	}
}

@ @<바이트 하나를 적재해서...@>=
s := 8 * (^a & 0x3)
ll[0].tet ^= ((ll[0].tet>>s ^ Tetra(buf[k])) & 0xff) << s
k++
a++

@ @<바이트 넷을 적재해서...@>=
ll[0].tet = Tetra(buf[k])<<24 | Tetra(buf[k+1])<<16 | Tetra(buf[k+2])<<8 | Tetra(buf[k+3])
k += 4
a += 4

@ 모의 프로그램이 표준 입력을 읽는 동안 그것을 대화에도 쓴다면, 모의 프로그램의
\.{StdIn}을 위한 버퍼를 따로 두어 두 쓰임을 떼어 놓으려 한다. 온라인 입력은 대개
키보드에서 \CEE/ 프로그램으로 한 줄씩 전해진다. 그래서 새 입력을 받으려고 프롬프트를
띄울 때는 |fread|보다 |fgets|가 훨씬 잘 된다. 그러나 조금 복잡한 문제가 있다. 함수 |fgets|는
줄 바꿈 문자에 이르기 전에 널 문자를 읽을 수도 있다. 그래서 |fgets|가 읽은 문자의 개수를
|strlen(stdin_buf)|만 보고 알아낼 수는 없다.

보충: 원본의 |stdin_buf|는 256바이트의 전역 배열이고, |fgets|는 읽은 바이트와 널 문자만
쓰고 나머지는 그대로 둔다. 줄 바꿈 문자로 끝나지 않는 마지막 줄을 읽으면 앞서 읽은 줄의
바이트들이 버퍼에 남아 모의 프로그램에 넘어간다. 여기서도 버퍼를 구조체의 배열로 두어 이
동작을 그대로 흉내 낸다.

@<함수들@>=
func (m *simulator) StdinChr() byte {
	for m.stdinBufStart == m.stdinBufEnd {
		if m.interacting {
			m.printf("StdIn> ")
@.StdIn>@>
			m.out.Flush()
		}
		if !m.stdin.fgets(m.stdinBuf[:], 256) {
			m.panic("End of file on standard input; use the -f option, not <")
		}
		m.stdinBufStart = 0
		p := 0
		for ; p < 254; p++ {
			if m.stdinBuf[p] == '\n' {
				break
			}
		}
		m.stdinBufEnd = p + 1
	}
	c := m.stdinBuf[m.stdinBufStart]
	m.stdinBufStart++
	return c
}

@ @<시뮬레이터의 상태@>=
stdinBuf      [256]byte // 모의 프로그램의 표준 입력
stdinBufStart int       // 그 버퍼에서의 현재 위치
stdinBufEnd   int       // 그 버퍼의 현재 끝

@ 명령을 하나 실행할 때마다 바로 뒤에 다음 일을 한다. 정확하고 허용되지 않은 아래넘침은
무시한다. (이것은 \.{RESUME\_SET}이 일으킨 아래넘침에도 적용된다.)

보충: 레지스터 rA의 아래 여덟 비트가 사건 비트이고, 그다음 여덟 비트가 허용 비트다. 변수 |exc|의 비트들은
허용 비트와 같은 자리에 있다. 그래서 |exc|의 비트 가운데 rA의 허용 비트나 |hBit|와 겹치는 것이 허용된
예외들이고, 사건 비트에는 |exc>>8|을 더한다.

@<트립 인터럽트를 검사한다@>=
if exc&(uBit+xBit) == uBit && m.g[rA]&uBit == 0 {
	exc &^= uBit
}
if exc != 0 {
	if exc&m.tracingExceptions != 0 {
		m.tracing = true
	}
	j = exc & (int(Tetra(m.g[rA])) | hBit) // 허용된 예외를 모두 찾는다
	if j != 0 {
		@<트립 인터럽트를 시작한다@>
	}
	m.g[rA] |= Octa(exc >> 8)
}

@ @<트립 인터럽트를 시작한다@>=
tripping = true
for k = 0; j&hBit == 0; j, k = j<<1, k+1 {
}
exc &^= hBit >> k // 취한 트립은 사건으로 기록하지 않는다
m.g[rW] = m.instPtr
m.instPtr = Octa(k << 4)
m.g[rX] = signBit | Octa(inst)
if op&0xe0 == STB {
	m.g[rY], m.g[rZ] = w, b
} else {
	m.g[rY], m.g[rZ] = y, z
}
m.g[rB] = m.g[255]
m.g[255] = m.g[rJ]
if op == TRIP {
	w, x, a = m.g[rW], m.g[rX], m.g[255]
}

@ 드디어 마지막 경우를 다룰 준비가 되었다.

@<개별 \MMIX\ 명령의 경우들@>=
case RESUME:
	if xx != 0 || yy != 0 || zz != 0 {
		trouble = "!illegal"
		break perform
	}
	z = m.g[rW]
	m.instPtr = z
	b = m.g[rX]
	if b&signBit == 0 {
		@<ropcode를 수행할 준비를 한다@>
	}

@ 여기서는 ropcode의 제약이 지켜지는지 확인한다. 지켜진다면 ropcode는 다음 가져오기
단계에서 실제로 수행된다.

보충: 원본에서는 \.{RESUME\_CONT}가 \.{RESUME\_SET}으로, \.{RESUME\_SET}이 \.{RESUME\_AGAIN}으로
흘러내렸다. \GO/의 |fallthrough|가 같은 일을 한다. ropcode \.{RESUME\_CONT}에서 금지되는 것은 rX에
든 명령의 연산 코드의 윗 네 비트가 4, 5, 8, 9, 10, 11, 15인 경우, 곧 분기, 적재와 저장,
그리고 \.{JMP}부터 \.{TRIP}까지다.

@<상수@>=
const (
	resumeAgain = 0 // rX의 명령을 위치 $\rm rW-4$에 있는 것처럼 되풀이한다
	resumeCont  = 1 // 같되, 피연산자 대신 rY와 rZ를 쓴다
	resumeSet   = 2 // 레지스터 \$X를 rZ로 정한다
)

@ @<ropcode를 수행할...@>=
rop = int(b >> 56) // ropcode는 rX의 맨 윗 바이트다
switch rop {
case resumeCont:
	if 1<<(Tetra(b)>>28)&0x8f30 != 0 {
		trouble = "!illegal"
		break perform
	}
	fallthrough
case resumeSet:
	k = int(b>>16) & 0xff
	if k >= L && k < G {
		trouble = "!illegal"
		break perform
	}
	fallthrough
case resumeAgain:
	if Tetra(b)>>24 == RESUME {
		trouble = "!illegal"
		break perform
	}
default:
	trouble = "!illegal"
	break perform
}
resuming = true

@ @<중단된 연산을 다시 시작할 때의...@>=
if rop == resumeSet {
	op = ORI
	y = m.g[rZ]
	z = 0
	exc = int(m.g[rX]>>32) & 0xff00
	f = xIsDestBit
} else { // |resumeCont|
	y = m.g[rY]
	z = m.g[rZ]
}

@ 모든 것을 시작하게 하는 \.{UNSAVE}는 세지 않으려 한다.

보충: 원본에서 rU의 아래 47비트가 사용 횟수이고, 그 위의 비트들은 어떤 명령을 셀지를
정한다. 원본은 아랫 테트라에 1을 더하고 올림을 윗 테트라로 넘긴 뒤, 올림이 47번째 비트로
넘어가면 다시 뺐다. 이것은 아래 47비트만 $2^{47}$을 법으로 1 늘리는 것과 같다.

@<시계를 갱신한다@>=
if m.sclock != 0 || !resuming {
	m.sclock += Octa(info[op].mems) << 32 // $\mu$마다 시계가 $2^{32}$씩 올라간다
	m.sclock += Octa(info[op].oops) // $\upsilon$마다 시계가 1씩 올라간다
	if (loc&signBit == 0 || m.g[rU]&(0x8000<<32) != 0) &&
		Octa(op)&(m.g[rU]>>48) == m.g[rU]>>56 {
		const count = 1<<47 - 1
		m.g[rU] = m.g[rU]&^count | (m.g[rU]+1)&count
	} // 사용 계수기는 흉내 낸 명령 가운데 조건에 맞는 것을 센다
	if m.g[rI] <= Octa(info[op].oops) && m.g[rI] != 0 {
		m.tracing, m.breakpoint = true, true
	}
	m.g[rI] -= Octa(info[op].oops) // 구간 $\upsilon$ 타이머는 거꾸로 센다
}

@* 추적. 명령을 하나 실행한 뒤에는 그 효과를 보여 주고 싶을 때가 많다. 프로그램의 이
부분은 방금 일어난 일을 기호로 풀어서 찍는다.

@<요청이 있으면 현재 명령을 추적한다@>=
if m.tracing {
	if m.showingSource && m.curLine != 0 {
		m.showLine()
	}
	@<빈도수, 위치, 명령을 찍는다@>
	@<명령을 의식의 흐름처럼 풀어 찍는다@>
	if m.showingStats || m.breakpoint {
		m.showStats(m.breakpoint)
	}
	justTraced = true
} else if justTraced {
	m.printf(" ...............................................\n")
	justTraced = false
	m.shownLine = -m.gap - 1 // 빈틈을 채우지 않는다
}

@ @<시뮬레이터의 상태@>=
showingStats bool // 추적하는 명령마다 통계도 보여 주어야 하는가?

@ @<지역 변수@>=
justTraced bool // 앞 명령을 추적했는가?

@ @<빈도수, 위치, 명령을 찍는다@>=
if resuming && op != RESUME {
	switch rop {
	case resumeAgain:
		m.printf("           (%016x: %08x (%s)) ", loc, inst, info[op].name)
	case resumeCont:
		m.printf("           (%016x: %04xrYrZ (%s)) ", loc, inst>>16, info[op].name)
	case resumeSet:
		m.printf("           (%016x: ..%02x..rZ (SET)) ", loc, (inst>>16)&0xff)
	}
} else {
	ll = m.memFind(loc)
	m.printf("%10d. %016x: %08x (%s) ", int32(ll[0].freq), loc, inst, info[op].name)
}

@ 시뮬레이터의 이 부분은 E.~H. Satterthwaite의 착상에서 영감을 받았다
@^Satterthwaite, Edwin Hallowell, Jr.@>
[{\sl Software---Practice and Experience\/ \bf2} (1972), 197--217].
Satterthwaite가 그 연구를 발표한 뒤로 온라인 디버깅 도구는 크게 나아졌지만, 좋은 오프라인
도구는 여전히 값지다. 안타깝게도 오늘날의 대수적 프로그래밍 언어들은, Satterthwaite가
1970년에 {\mc ALGOL}로 보여 줄 수 있었던 수준에 조금이라도 가까운 추적 기능을 주지 못한다.

@<명령을 의식의 흐름처럼...@>=
if lhs != "" && lhs[0] == '!' {
	m.printf("%s instruction!\n", lhs[1:]) // 특권 명령이거나 불법 명령
} else {
	@<rL이 바뀐 것을 찍는다@>
	fs := info[op].traceFormat
	if Tetra(z) == 0 && (op == ADDUI || op == ORI) {
		fs = "%l = %y = %#x" // \.{LDA}, \.{SET}
	}
	for p = 0; p < len(fs); p++ {
		@<추적 형식의 문자 |fs[p]|를 해석한다@>
	}
	if exc != 0 {
		m.printf(", rA=#%05x", Tetra(m.g[rA]))
	}
	if tripping {
		tripping = false
		m.printf(", -> #%02x", Tetra(m.instPtr))
	}
	m.printf("\n")
}

@ 넣기, 꺼내기, \.{UNSAVE} 명령은 rL과 rO가 바뀐 것을 드러내 놓고 보여 준다. 그 밖의
명령에서는 |L!=oldL|이면 그 변화가 암묵적이다.

@<rL이 바뀐 것을 찍는다@>=
if L != oldL && f&pushPopBit == 0 {
	m.printf("rL=%d, ", L)
}

@ \MMIX\ 명령마다 {\it 추적 형식\/} 문자열이 있어서, 그 명령을 기호로 어떻게 나타낼지를
정한다. 이를테면 \.{ADD}의 문자열은 |"%l = %y + %z = %x"|다. 명령이 이를테면
\.{ADD}~\.{\$1,\$2,\$3}이고 $\$2=5$, $\$3=8$이고 스택 오프셋이 100이면, 추적 출력은
|"$1=l[101] = 5 + 8 = 13"|이 된다.

퍼센트 기호(\.\%)는 다음과 같은 특별한 서식 규칙을 불러낸다.

\bull \.{\%a}, \.{\%b}, \.{\%p}, \.{\%q}, \.{\%w}, \.{\%x}, \.{\%y}, \.{\%z}는 각각
옥타바이트 |a|, |b|, |ma|, |mb|, |w|, |x|, |y|,~|z|의 수치를 나타낸다. 이 경우에는 퍼센트
기호 뒤에 ``모양'' 문자가 올 수 있는데, 아래에서 설명한다.

\bull \.{\%(}와 \.{\%)}는 부동소수점 반올림 방식을 나타내는 괄호다. 반올림 방식 |roundMode|가
|RoundNear|, |RoundOff|, |RoundUp|, |RoundDown|이면 괄호는 각각 \.(와~\.),
\.[와~\.], \.\^와~\.\^, \.\_와~\.\_이다. 이런 괄호는 부동소수점 연산자를 둘러싼다.
이를테면 현재 반올림 방식이 버림이면 부동소수점 덧셈은 `\.{[+]}'로 나타낸다.

\bull \.{\%l}은 문자열 |lhs|를 나타낸다. 이것은 대개 방금 수행한 명령의 ``왼쪽''을
나타내는데, 레지스터 번호와 그것이 지역 레지스터 고리에서 해당하는 곳(이를테면
`\.{\$1=l[101]}')이나, 레지스터 번호와 그것이 전역 레지스터 배열에서 해당하는 곳(이를테면
`\.{\$255=g[255]}')의 꼴이다. 명령 \.{POP}은 |lhs|로 레지스터 스택의 ``구멍''을 어떻게
메웠는지 나타낸다.

\bull \.{\%r}은 문자열 |rhs|로 옮겨 가서 거기서부터 서식을 이어 가라는 뜻이다. 이
장치 덕분에 \.{TRAP}처럼 여러 변형이 있는 연산 코드에 바뀌는 서식을 쓸 수 있다.

\bull \.{\%t}는 |x|의 값에 따라 `\.{Yes, ->loc}'(여기서 \.{loc}은 다음 명령의 위치다)나
`\.{No}'를 찍으라는 뜻이다.

\bull \.{\%g}는 |good|이 거짓이면 `\.{ (bad guess)}'를 찍으라는 뜻이다.

\bull \.{\%s}는 특수 레지스터 |g[zz]|의 이름을 나타낸다.

\bull \.{\%?}는 |z=0|이면 다음 연산자를 빼라는 뜻이다. 이를테면 \.{LDBI}의 메모리 주소는
`\.{\%\#y\%?+}'로 나타낸다. 이것은 |z=0|이면 주소를 그냥 `\.{\%\#y}'로, 그렇지 않으면
`\.{\%\#y+\%z}'로 다루라는 뜻이다. 이 경우는 |z|가 비교적 작은 수일 때($z<2^{32}$일 때)만
쓰인다.

보충: 원본은 모양 문자를 읽은 뒤 |goto char_switch|로 스위치를 다시 돌았다. 여기서는 스위치를
루프로 감싸고 |continue charSwitch|로 그 일을 한다. 원본은 모양을 전역 변수 |style|에
두었는데, 여기서는 지역 변수로 두고 |tracePrint|에 넘긴다.

@<추적 형식의 문자 |fs[p]|를...@>=
if fs[p] != '%' {
	m.out.WriteByte(fs[p])
} else {
	style := decimal
charSwitch:
	for {
		p++
		switch fs[p] {
		@<서식 문자의 경우들@>
		default:
			m.printf("BUG!!") // 일어날 수 없다
		}
		break
	}
}

@ 옥타바이트는, 퍼센트 기호와 옥타바이트 이름 사이에 ``모양'' 문자가 끼어들지 않으면
십진수로 찍는다. `\.\#'은 앞에 \.\#을 붙인 십육진 표기를 뜻한다. `\.0'은 앞에 \.\#을 붙이지
않고 앞쪽의 0들도 없애지 않는 십육진 표기를 뜻한다. `\..'은 부동 십진 표기를 뜻한다.
`\.!'는 값이 0, 1, 2이면 이름 \.{StdIn}, \.{StdOut}, \.{StdErr}를 쓰라는 뜻이다.
@.StdIn@>
@.StdOut@>
@.StdErr@>

@<서식 문자의 경우들@>=
case '#':
	style = hex
	continue charSwitch
case '0':
	style = zhex
	continue charSwitch
case '.':
	style = floating
	continue charSwitch
case '!':
	style = handle
	continue charSwitch

@ @<타입 정의@>=
type fmtStyle int
@#
const (
	decimal  fmtStyle = iota
  hex
  zhex
  floating
  handle
)

@ @<서식 문자의 경우들@>=
case 'a':
	m.tracePrint(a, style)
case 'b':
	m.tracePrint(b, style)
case 'p':
	m.tracePrint(ma, style)
case 'q':
	m.tracePrint(mb, style)
case 'w':
	m.tracePrint(w, style)
case 'x':
	m.tracePrint(x, style)
case 'y':
	m.tracePrint(y, style)
case 'z':
	m.tracePrint(z, style)

@ @<표@>=
var streamName = [3]string{"StdIn", "StdOut", "StdErr"}
@.StdIn@>
@.StdOut@>
@.StdErr@>

@ @<함수들@>=
func (m *simulator) tracePrint(o Octa, style fmtStyle) {
	switch style {
	case decimal:
		m.printInt(o)
	case hex:
		m.out.WriteByte('#')
		m.printHex(o)
	case zhex:
		m.printf("%016x", o)
	case floating:
		m.out.WriteString(mmixarith.FloatString(o))
	case handle:
		if o < 3 {
			m.out.WriteString(streamName[o])
		} else {
			m.printInt(o)
		}
	}
}

@ 보충: 원본은 \.{\%r}에서 |p|를 |switchable_string|에 맞추었다. 그러면 |for| 루프의
|p++|이 |rhs|, 곧 그 문자열의 둘째 바이트로 옮겨 간다. 여기서는 |fs|를 |rhs|로 바꾸고
|p|를 $-1$로 둔다.

@<서식 문자의 경우들@>=
case '(':
	m.out.WriteByte(leftParen[roundMode])
case ')':
	m.out.WriteByte(rightParen[roundMode])
case 't':
	if Tetra(x) != 0 {
		m.printf(" Yes, -> #")
		m.printHex(m.instPtr)
	} else {
		m.printf(" No")
	}
case 'g':
	if !good {
		m.printf(" (bad guess)")
	}
case 's':
	m.out.WriteString(specialName[zz])
case '?':
	p++
	if Tetra(z) != 0 {
		m.out.WriteByte(fs[p])
		m.printf("%d", int32(Tetra(z)))
	}
case 'l':
	m.out.WriteString(lhs)
case 'r':
	fs, p = rhs, -1

@ 보충: 반올림 방식 0에 해당하는 괄호는 널 문자다. 원본에서는 |round_mode|가 처음에
0이었으므로, 부동소수점 명령을 하나도 실행하지 않은 채 괄호를 찍으면 널 문자가 찍혔을
것이다. 실제로는 괄호를 찍는 명령이 늘 |roundMode|를 먼저 정한다.

@<표@>=
var leftParen = [5]byte{0, '[', '^', '_', '('}  // 반올림 방식을 나타낸다
var rightParen = [5]byte{0, ']', '^', '_', ')'} // 반올림 방식을 나타낸다

@ @<시뮬레이터의 상태@>=
goodGuesses, badGuesses int32 // 분기 예측 통계

@ 보충: 원본은 명령 수, 시계, 짐작 횟수를 모두 \.{\%d}로, 곧 부호 있는 32비트 정수로
찍었다.

@<함수들@>=
func (m *simulator) showStats(verbose bool) {
	u, h, l := Tetra(m.g[rU]), Tetra(m.sclock>>32), Tetra(m.sclock)
	m.printf("  %d instruction%s, %d mem%s, %d oop%s; %d good guess%s, %d bad\n",
		int32(u), plural(u != 1, "s"),
		int32(h), plural(h != 1, "s"),
		int32(l), plural(l != 1, "s"),
		m.goodGuesses, plural(m.goodGuesses != 1, "es"), m.badGuesses)
	if !verbose {
		return
	}
	o, what := m.instPtr, "now"
	if m.halted {
		o, what = m.instPtr-4, "halted"
	}
	m.printf("  (%s at location #%016x)\n", what, o)
}
@#
func plural(many bool, s string) string {
	if many {
		return s
	}
	return ""
}

@* 프로그램 돌리기. 이제 조각들을 맞추어 제대로 돌아가는 시뮬레이터를 만들 준비가 되었다.

보충: 원본에서는 이것이 |main| 함수의 몸통이다. 첫 절의 |mmix| 함수가 이것을 부른다.
원본은 `\.{q}' 명령을 받으면 |goto end_simulation|으로 주 루프 뒤로 뛰었다. 여기서는 주
루프에 |run|이라는 이름표를 붙이고 |break run|으로 그 일을 한다. 원본의 |do|\dots|while|
루프는 끝에서 조건을 검사하는 |for| 루프가 된다. 원본은 |main|의 반환값을 종료 코드로
삼았으므로, \$255의 아랫 32비트가 부호 있는 정수로서 종료 코드가 된다.

@<프로그램을 돌린다@>=
var (
	@<지역 변수@>
)
@<명령줄을 처리한다@>
@<모든 것을 초기화한다@>
@<명령줄 인자들을 싣는다@>
@<처음 문맥을 \.{UNSAVE}할 준비를 한다@>
run:
for {
	if m.interrupt.Load() && !m.breakpoint {
		m.breakpoint, m.interacting = true, true
		m.interrupt.Store(false)
	} else {
		m.breakpoint = false
		if m.interacting {
			@<사용자와 대화한다@>
		}
	}
	if m.halted {
		break
	}
	for {
		@<한 명령을 수행한다@>
		if (m.interrupt.Load() || m.breakpoint) && !resuming {
			break
		}
	}
	if m.interactAfterBreak {
		m.interacting, m.interactAfterBreak = true, false
	}
}
if m.profiling {
	@<모든 빈도수를 찍는다@>
}
if m.interacting || m.profiling || m.showingStats {
	m.showStats(true)
}
return int(int32(Tetra(m.g[255]))) // 비대화식 실행에 초보적인 되먹임을 준다

@ 여기서는 명령줄 옵션들을 처리한다. 처리를 마치면 |args[curArg]|가 싣고 흉내 낼 목적
파일의 이름이어야 한다.

우리는 |args[0]|이 결코 비어 있지 않다고 가정한다. (크누스는, |argc=0|을 허용하기로
한 마법사들이 C89 표준을 정할 때 잘못을 저질렀다고 굳게 믿는다. 그래서 사람들이 그의
프로그램을 빈 환경으로 부를 때 시스템이 망가지지 않도록 애쓰지 않았다. 빈 호출은 \CEE/를
설계한 사람들의 뜻에 어긋난다.)

@<명령줄을 처리한다@>=
m.myself = args[0]
for curArg = 1; curArg < len(args) && args[curArg] != "" && args[curArg][0] == '-'; curArg++ {
	m.scanOption(args[curArg][1:], true)
}
if curArg == len(args) {
	m.scanOption("?", true) // 사용법 알림과 함께 끝낸다
}
argc = len(args) - curArg // 사용자 프로그램의 |argc|

@ @<지역 변수@>=
curArg int // 인자 벡터에서의 현재 자리
argc   int // 사용자 프로그램의 인자 개수

@ 다음 서브루틴을 꼼꼼히 읽는 독자는 작고 하얀 버그 하나를 알아챌 것이다. 이를테면
\.{t1000000000}이나 \.{t0000000000}이나 심지어 \.{t!!!!!!!!!!} 같은 추적 지정이 소리 없이
\.{t4294967295}로 바뀐다.

옵션 \.{-b}와 \.{-c}는 명령줄에서만 효과가 있지만, 대화 중에 써도 해는 없다.

보충: 원본은 |sscanf|의 \.{\%d}와 \.{\%x}로 수를 읽었다. 그 흉내는 옮긴이의 장에 있는
함수 |sscanf|가 낸다. 읽기에 실패하면 원본처럼 0이 된다. 원본에서 \.{-L}은 \.{-P}로
흘러내렸는데, \GO/에서도 |fallthrough|가 같은 일을 한다. 원본의 도움말은 |printf|의 서식
문자열로 찍혔지만, 그 안에 \.\%가 없으므로 그냥 찍는 것과 같다.

@<함수들@>=
func (m *simulator) scanOption(arg string, usage bool) {
	var opt byte
	if arg != "" {
		opt = arg[0]
	}
	switch opt {
	@<추적과 나열 옵션의 경우들@>
	@<나머지 옵션의 경우들@>
	default:
		@<사용법을 알린다@>
	}
}

@ 명령줄에서 알아듣지 못한 옵션을 만나면 사용법을 표준 오류에 알리고 끝낸다. 대화
중이면 옵션 목록만(\.{-b} 앞까지) 표준 출력에 찍는다.

@<사용법을 알린다@>=
if usage {
	m.eprintf(
		"Usage: %s <options> progfile command line-args...\n", m.myself)
@.Usage: ...@>
	for k := 0; usageHelp[k] != ""; k++ {
		m.eprintf("%s", usageHelp[k])
	}
	panic(exitSignal(-1))
}
for k := 0; usageHelp[k][1] != 'b'; k++ {
	m.printf("%s", usageHelp[k])
}

@ @<추적과 나열 옵션의 경우들@>=
case 't':
	if len(arg) > 10 {
		m.traceThreshold = 0xffffffff
	} else {
		m.traceThreshold = Tetra(sscanf(arg[1:], false))
	}
case 'e':
	if len(arg) == 1 {
		m.tracingExceptions = 0xff
	} else {
		m.tracingExceptions = int(sscanf(arg[1:], true))
	}
case 'r':
	m.stackTracing = true
case 's':
	m.showingStats = true
case 'l':
	if len(arg) == 1 {
		m.gap = 3
	} else {
		m.gap = sscanf(arg[1:], false)
	}
	m.showingSource = true
case 'L':
	if len(arg) == 1 {
		m.profileGap = 3
	} else {
		m.profileGap = sscanf(arg[1:], false)
	}
	m.profileShowingSource = true
	fallthrough
case 'P':
	m.profiling = true

@ @<나머지 옵션의 경우들@>=
case 'v':
	m.traceThreshold = 0xffffffff
	m.tracingExceptions = 0xff
	m.stackTracing = true
	m.showingStats = true
	m.gap, m.showingSource = 10, true
	m.profileGap, m.profileShowingSource, m.profiling = 10, true, true
case 'q':
	m.traceThreshold, m.tracingExceptions = 0, 0
	m.stackTracing, m.showingStats, m.showingSource = false, false, false
	m.profiling, m.profileShowingSource = false, false
case 'i':
	m.interacting = true
case 'I':
	m.interactAfterBreak = true
case 'b':
	m.bufSize = int(sscanf(arg[1:], false))
case 'c':
	m.lringSize = int(sscanf(arg[1:], false))
case 'f':
	@<모의 표준 입력으로 쓸 파일을 연다@>
case 'D':
	@<이진 출력을 덤프할 파일을 연다@>

@ 보충: 원본의 |interrupt|는 신호 처리기가 바꾸는 전역 변수였다. \GO/에서 신호는 다른
고루틴으로 오므로, 여기서는 원자적으로 읽고 쓰는 |atomic.Bool|로 둔다. 원본은 덤프 파일을
|FILE*| 하나로 두었는데, 여기서는 버퍼와 그 밑의 파일을 따로 둔다.

@<시뮬레이터의 상태@>=
myself    string        // |args[0]|, 곧 이 시뮬레이터의 이름
interrupt atomic.Bool   // 사용자가 최근에 시뮬레이션을 가로막았는가?
profiling bool          // 끝날 때 프로파일을 찍어야 하는가?
fakeStdin *os.File      // 모의 \.{StdIn} 대신 쓰는 파일
dumpFile  *bufio.Writer // 이진 덤프에 쓰는 파일
dumpOS    *os.File      // |dumpFile| 밑의 파일

@ @<표@>=
var usageHelp = [...]string{
	" with these options: (<n>=decimal number, <x>=hex number)\n",
	"-t<n> trace each instruction the first n times\n",
	"-e<x> trace each instruction with an exception matching x\n",
	"-r    trace hidden details of the register stack\n",
	"-l<n> list source lines when tracing, filling gaps <= n\n",
	"-s    show statistics after each traced instruction\n",
	"-P    print a profile when simulation ends\n",
	"-L<n> list source lines with the profile\n",
	"-v    be verbose: show almost everything\n",
	"-q    be quiet: show only the simulated standard output\n",
	"-i    run interactively (prompt for online commands)\n",
	"-I    interact, but only after the program halts\n",
	"-b<n> change the buffer size for source lines\n",
	"-c<n> change the cyclic local register ring size\n",
	"-f<filename> use given file to simulate standard input\n",
	"-D<filename> dump a file for use by other simulators\n",
	""}

@ @<표@>=
var interactiveHelp = [...]string{
	"The interactive commands are:\n",
	"<return>  trace one instruction\n",
	"n         trace one instruction\n",
	"c         continue until halt or breakpoint\n",
	"q         quit the simulation\n",
	"s         show current statistics\n",
	"l<n><t>   set and/or show local register in format t\n",
	"g<n><t>   set and/or show global register in format t\n",
	"rA<t>     set and/or show register rA in format t\n",
	"$<n><t>   set and/or show dynamic register in format t\n",
	"M<x><t>   set and/or show memory octabyte in format t\n",
	"+<n><t>   set and/or show n additional octabytes in format t\n",
	" <t> is ! (decimal) or . (floating) or # (hex) or \" (string)\n",
	"     or <empty> (previous <t>) or =<value> (change value)\n",
	"@@<x>      go to location x\n",
	"b[rwx]<x> set or reset breakpoint at location x\n",
	"t<x>      trace location x\n",
	"u<x>      untrace location x\n",
	"T         set current segment to Text_Segment\n",
	"D         set current segment to Data_Segment\n",
	"P         set current segment to Pool_Segment\n",
	"S         set current segment to Stack_Segment\n",
	"B         show all current breakpoints and tracepoints\n",
	"i<file>   insert commands from file\n",
	"-<option> change a tracing/listing/profile option\n",
	"-?        show the tracing/listing/profile options  \n",
	""}

@ @<모의 표준 입력으로...@>=
if m.fakeStdin != nil {
	m.fakeStdin.Close()
}
f, err := os.Open(arg[1:])
m.fakeStdin = f
if err != nil {
	m.eprintf("Sorry, I can't open file %s!\n", arg[1:])
@.Sorry, I can't open...@>
	m.fakeStdin = nil
} else {
	m.io.FakeStdin(f)
}

@ @<이진 출력을 덤프할...@>=
if f, err := os.Create(arg[1:]); err != nil {
	m.eprintf("Sorry, I can't open file %s!\n", arg[1:])
@.Sorry, I can't open...@>
	m.dumpFile = nil
} else {
	m.dumpOS = f
	m.dumpFile = bufio.NewWriter(f)
}

@ 보충: 원본의 |catchint|는 인터럽트를 받을 때마다 |interrupt|를 참으로 만들고 자신을 다시
처리기로 등록했다. \GO/에서는 신호를 채널로 받는 고루틴 하나가 그 일을 한다. 함수 |mmix|가
끝나면 신호 받기를 그만두고 채널을 닫아서 그 고루틴도 끝낸다.

@<모든 것을 초기화한다@>=
sig := make(chan os.Signal, 1)
signal.Notify(sig, os.Interrupt) // 이제 인터럽트를 받는다
defer func() {
	signal.Stop(sig)
	close(sig)
}()
go func() {
	for range sig {
		m.interrupt.Store(true)
	}
}()

@ 보충: 원본은 이름표 |interact|와 |resume_simulation|, |what_say|, |check_syntax| 따위
사이를 |goto|로 오갔다. 여기서는 대화 루프에 |interact|라는 이름표를 붙이고, 다음 명령을
받으러 갈 때는 |continue interact|, 시뮬레이션을 이어 갈 때는 |break interact|를 쓴다.
원본은 레지스터나 메모리를 보이는 명령을 두 무리의 경우로 나누고, 한 무리의 끝에서 다른
무리의 한가운데로 |goto scan_type|이나 |goto scan_eql|로 뛰어들었다. 여기서는 그런 경우들을
하나로 묶고, 앞부분(무엇을 보일지)과 뒷부분(어떤 형식으로 보일지)을 차례로 훑는다.
알아듣지 못한 명령을 알리는 일은 두 곳에서 하므로 메서드 |whatSay|로 둔다. 원본은 문자열
상수가 줄 바꿈 문자에서 끝나 버리면 |goto incomplete_str|로 문법 검사의 한가운데로 뛰었다.
여기서는 |incomplete| 표시가 그 일을 한다.

@<사용자와 대화한다@>=
interact:
for {
	@<|cmd|에 새 명령을 넣는다@>
	p = 0
	repeating := int32(0)
	incomplete := false
	switch cmd[p] {
	@<시뮬레이션을 이어 가거나 끝내거나 옵션을 바꾸는 명령들@>
	case 'l', 'g', '$', 'r', 'M', '+', '!', '.', '#', '"', '=':
		@<무엇을 보일지 훑는다@>
		@<어떤 형식으로 보일지 훑는다@>
	@<추적과 멈춤점을 정하고 지우는 경우들@>
	case 'h':
		for k = 0; interactiveHelp[k] != ""; k++ {
			m.printf("%s", interactiveHelp[k])
		}
		continue interact
	default:
		m.whatSay()
		continue interact
	}
	@<문법을 검사한다@>
	for repeating != 0 {
		@<현재 옥타바이트를 보이거나 정한다@>
	}
}

@ @<시뮬레이션을 이어 가거나...@>=
case '\n', 'n':
	m.breakpoint, m.tracing = true, true // 명령 하나를 추적하고 멈춘다
	break interact
case 'c':
	break interact // 멈춤점까지 계속한다
case 'q':
	break run
case 's':
	m.showStats(true)
	continue interact
case '-':
	k = strlen(cmd)
	if cmd[k-1] == '\n' {
		cmd[k-1] = 0
	}
	m.scanOption(string(cstr(cmd[1:])), false)
	continue interact

@ @<문법을 검사한다@>=
if incomplete || cmd[p] != '\n' {
	if incomplete || cmd[p] == 0 {
		m.printf("Syntax error: Incomplete command!\n")
	} else {
		cmd[p+strlen(cmd[p:])-1] = 0
		m.printf("Syntax error; I'm ignoring `%s'!\n", cstr(cmd[p:]))
	}
}

@ 원본은 알아듣지 못한 명령을 아홉 문자까지만 되풀이해 보였다. 명령이 열 문자 이상이면
뒤를 \.{...}로 줄인다.

보충: 원본은 명령 버퍼의 열째 바이트부터 \.{"..."}를 겹쳐 썼다. 명령이 아홉 문자보다 짧은데
줄 바꿈 문자로 끝나지 않으면(입력의 마지막 줄이면), 널 문자가 그 앞에 있으므로 \.{...}는
찍히지 않는다. 여기서도 버퍼에 겹쳐 써서 그대로 흉내 낸다. 명령이 널 문자로 시작하면 원본은
|command_buf[-1]|을 읽었는데, 여기서는 줄 바꿈 문자가 아닌 것으로 친다.

@<함수들@>=
func (m *simulator) whatSay() {
	k := strlen(m.commandBuf[:])
	if k < 10 && k > 0 && m.commandBuf[k-1] == '\n' {
		m.commandBuf[k-1] = 0
	} else {
		copy(m.commandBuf[9:], "...\x00")
	}
	m.printf("Eh? Sorry, I don't understand `%s'. (Type h for help)\n",
		cstr(m.commandBuf[:]))
}

@ 보충: 원본은 끼워 넣은 파일에서 명령을 찾지 못하면 프롬프트를 띄웠고, 새로 파일을 열면
|goto incl_read|로 그 파일을 읽으러 되돌아갔다. 여기서는 둘을 한 루프로 묶었다.

@<|cmd|에 새 명령을...@>=
ready := false
for !ready {
	for inclFile != nil && !ready {
		if !inclFile.fgets(cmd, commandBufSize) {
			inclFile.f.Close()
			inclFile = nil
		} else if cmd[0] != '\n' && cmd[0] != 'i' && cmd[0] != '%' {
			if cmd[0] == ' ' {
				m.printf("%s", cstr(cmd))
			} else {
				ready = true
			}
		}
	}
	if ready {
		break
	}
	m.printf("mmix> ")
@.mmix>@>
	m.out.Flush()
	if !m.stdin.fgets(cmd, commandBufSize) {
		cmd[0] = 'q'
	}
	if cmd[0] != 'i' {
		ready = true
	} else {
		cmd[strlen(cmd)-1] = 0
		inclFile = openCfile(string(cstr(cmd[1:])))
		if inclFile == nil && isspace(cmd[1]) {
			inclFile = openCfile(string(cstr(cmd[2:])))
		}
		if inclFile == nil {
			m.printf("Can't open file `%s'!\n", cstr(cmd[1:]))
		}
	}
}

@ 보충: 원본의 |command_buf|는 1024바이트였다. 문자열 상수를 훑을 때 원본은 |*(p+2)|를
보는데, 이것이 버퍼의 끝을 넘을 수 있다. 여기서는 버퍼 끝에 두 바이트를 더 두어 그런 일이
생기지 않게 한다. 명령 버퍼를 가리키는 |cmd|는 원본의 |command_buf|와 같다.

@<상수@>=
const commandBufSize = 1024 // 넉넉하게 길게, 부동소수점 시험을 위해

@ @<시뮬레이터의 상태@>=
commandBuf [commandBufSize + 2]byte

@ @<지역 변수@>=
cmd         = m.commandBuf[:]
inclFile    *cfile // `\.i'가 끼워 넣는 명령들의 파일
curDispMode byte  = 'l' // |'l'|이나 |'g'|나 |'$'|나 |'M'|
curDispType byte  = '!' // |'!'|나 |'.'|나 |'#'|나 |'"'|
curDispSet  bool        // 마지막 \.{<t>}가 \.{=<val>} 꼴이었는가?
curDispAddr Octa        // 윗 테트라는 |'M'| 방식에서만 쓰인다
curSeg      Octa        // 현재 세그먼트 오프셋

@ @<표@>=
var specRegCode = [26]byte{rA, rB, rC, rD, rE, rF, rG, rH, rI, rJ, rK, rL, rM,
	rN, rO, rP, rQ, rR, rS, rT, rU, rV, rW, rX, rY, rZ}
var specReggCode = [26]byte{0, rBB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, rTT, 0, 0, rWW, rXX, rYY, rZZ}

@ 보충: 대화 명령 \.{l}, \.{g}, \.\$, \.{r}, \.{M}은 보일 방식과 주소를 새로 정하고 |curDispSet|을
지운다. 등호 \.{=}은 명령 \.+만 기억한다. 원본은 \.{l}, \.{g}, \.\$에서 주소의 아랫 테트라만 새로
정했지만, 윗 테트라는 \.{M} 방식에서만 쓰이고 \.{M}은 주소 전체를 새로 정하므로 여기서는
주소 전체를 정한다. 원본은 \.{r}에서 방식을 |'g'|로 바꾼 뒤에 이름이 맞는지 따졌으므로,
알아듣지 못한 명령이어도 방식은 바뀐다. 원본의 반복 횟수는 32비트 |int|였다.

@<무엇을 보일지 훑는다@>=
switch cmd[p] {
case 'l', 'g', '$':
	curDispMode = cmd[p]
	var n Tetra
	for p++; isdigit(cmd[p]); p++ {
		n = 10*n + Tetra(cmd[p]-'0')
	}
	curDispAddr = Octa(n)
	curDispSet, repeating = false, 1
case 'r':
	@<특수 레지스터의 이름을 훑는다@>
case 'M':
	curDispMode = 'M'
	curDispAddr, p = scanHex(cmd, p+1, curSeg)
	curDispAddr &^= 7
	curDispSet, repeating = false, 1
case '+':
	if !isdigit(cmd[p+1]) {
		repeating = 1
	}
	for p++; isdigit(cmd[p]); p++ {
		repeating = 10*repeating + int32(cmd[p]-'0')
	}
	if repeating != 0 {
		if curDispMode == 'M' {
			curDispAddr += 8
		} else {
			curDispAddr++
		}
	}
case '=':
	repeating = 1
default: // \.!, \.., \.\#, \."
	curDispSet, repeating = false, 1
}

@ 특수 레지스터의 이름은 한 글자이거나, 같은 글자를 겹친 두 글자다. 두 글자 이름은
\.{rBB}, \.{rTT}, \.{rWW}, \.{rXX}, \.{rYY}, \.{rZZ}뿐이다.

@<특수 레지스터의 이름을...@>=
p++
curDispMode = 'g'
if cmd[p] < 'A' || cmd[p] > 'Z' {
	m.whatSay()
	continue interact
}
if cmd[p+1] != cmd[p] {
	curDispAddr = Octa(specRegCode[cmd[p]-'A'])
	p++
} else if specReggCode[cmd[p]-'A'] != 0 {
	curDispAddr = Octa(specReggCode[cmd[p]-'A'])
	p += 2
} else {
	m.whatSay()
	continue interact
}
curDispSet, repeating = false, 1

@ @<어떤 형식으로 보일지 훑는다@>=
if cmd[p] == '!' || cmd[p] == '.' || cmd[p] == '#' || cmd[p] == '"' {
	curDispType = cmd[p]
	p++
} else if cmd[p] == '=' {
	@<등호 뒤의 값을 훑는다@>
}

@ 보충: 원본의 |val|은 {\mc MMIX-ARITH}의 전역 변수였다. 이 값은 명령과 명령 사이에도
남아서, 뒤에 오는 \.+ 명령이 그 값을 다시 쓴다. 그런데 \.t, \.u, \.b 명령도 주소를 이
변수에 넣는다. 그래서 이를테면 `\.{g200=3}' 다음에 `\.{t1000}'을 치고 `\.{+5}'를 치면,
\.{g201}부터 \.{g205}까지가 3이 아니라 \Hex{1000}이 된다. 여기서도 그대로 흉내 내려고
|val|을 구조체의 필드로 둔다.

@<시뮬레이터의 상태@>=
val Octa // 대화 명령이 넣을 값

@ 보충: 원본은 |scan_const|가 \Hex{0}보다 큰 값(부동소수점 상수)을 돌려주면 형식을
|'.'|로, 그렇지 않으면 |'!'|로 정했다. 상수를 찾지 못하면 값은 0이고 |p|는 그대로다.

@<등호 뒤의 값을...@>=
curDispSet = true
m.val = 0
p++
isStr := cmd[p] == '"' || cmd[p] == '\''
if cmd[p] == '#' {
	curDispType = '#'
	m.val, p = scanHex(cmd, p+1, 0)
} else if !isStr {
	v, next, kind := mmixarith.ScanConst(string(cmd[p:]))
	m.val, p = v, p+next
	curDispType = '!'
	if kind > 0 {
		curDispType = '.'
	}
}
if !isStr && cmd[p] == ',' {
	m.val &= 0xff
	isStr = true
}
if isStr {
	@<문자열 상수를 훑는다@>
}

@ @<함수들@>=
func scanHex(s []byte, p int, offset Octa) (Octa, int) {
	var o Octa
	for ; isxdigit(s[p]); p++ {
		d := int(s[p]) - '0'
		if s[p] >= 'a' {
			d += '0' - 'a' + 10
		} else if s[p] >= 'A' {
			d += '0' - 'A' + 10
		}
		o = o<<4 + Octa(d)
	}
	return o + offset, p
}

@ 보충: 원본은 쉼표 뒤에 문자열이 또 오면 |goto scan_string|으로 이 절의 처음으로 되돌아갔다.
여기서는 루프에 |str|이라는 이름표를 붙이고 |continue str|로 그 일을 한다. 원본은 따옴표
안의 문자를 \CEE/의 |char|로 더했는데, 원본을 시험한 macOS에서 |char|는 부호가 있다. 그래서
128 이상인 바이트는 음수로 더해진다. 이를테면 `\.{g1="\\303\\251"}'(UTF-8의 \'e)는
\Hex{ffffffffffffc2a9}가 된다. 여기서도 그대로 흉내 낸다.

@<문자열 상수를...@>=
str:
for {
	curDispType = '"'
	for cmd[p] == ',' {
		p++
		if cmd[p] == '#' {
			var aux Octa
			aux, p = scanHex(cmd, p+1, 0)
			m.val = m.val<<8 + aux&0xff
		} else if isdigit(cmd[p]) {
			k = int(cmd[p] - '0')
			for p++; isdigit(cmd[p]); p++ {
				k = (10*k + int(cmd[p]-'0')) & 0xff
			}
			m.val = m.val<<8 + Octa(k)
		} else if cmd[p] == '\n' {
			incomplete = true
			break str
		}
	}
	if cmd[p] == '\'' && cmd[p+2] == cmd[p] {
		cmd[p], cmd[p+2] = '"', '"'
	}
	if cmd[p] == '"' {
		for p++; cmd[p] != 0 && cmd[p] != '\n' && cmd[p] != '"'; p++ {
			m.val = m.val<<8 + Octa(int8(cmd[p]))
		}
		if cmd[p] != 0 {
			q := cmd[p]
			p++
			if q == '"' && cmd[p] == ',' {
				continue str
			}
		}
	}
	break
}

@ @<현재 옥타바이트를 보이거나...@>=
if curDispSet {
	@<현재 옥타바이트를 |val|로 정한다@>
}
@<현재 옥타바이트를 보인다@>
m.out.WriteByte('\n')
repeating--
if repeating == 0 {
	break
}
if curDispMode == 'M' {
	curDispAddr += 8
} else {
	curDispAddr++
}

@ @<현재 옥타바이트를 |val|로...@>=
switch curDispMode {
case 'l':
	m.l[int(Tetra(curDispAddr))&m.lringMask] = m.val
case '$':
	k = int(curDispAddr & 0xff)
	if k < L {
		m.l[(O+k)&m.lringMask] = m.val
	} else if k >= G {
		m.g[k] = m.val
	}
case 'g':
	k = int(curDispAddr & 0xff)
	if k < 32 {
		@<|g[k]=val|이 허용될 때만 정한다@>
	}
	m.g[k] = m.val
case 'M':
	if curDispAddr&signBit == 0 {
		ll = m.memFind(curDispAddr)
		ll[0].tet, ll[1].tet = Tetra(m.val>>32), Tetra(m.val)
	}
}

@ 여기서는 본질적으로 \.{PUT} 명령을 흉내 내는데, \.{PUT}이 불법이거나 특권 명령이면 그냥
|break|한다.

보충: 레지스터 rG의 번호는 19이므로, 이 코드에서 rG를 다루는 가지에는 결코 이르지 못한다. 그 앞의
|k<=19|에서 이미 |break|하기 때문이다. 그래서 대화 명령 `\.{rG=40}'은 아무 일도 하지
않는다. 명령 \.{PUT}에서는 특권 레지스터의 한계가 |xx<=18|이었다. 여기서도 원본 그대로 둔다.

@<|g[k]=val|이 허용될...@>=
if k >= 9 && k != rI {
	if k <= 19 {
		break
	}
	if k == rA {
		if m.val >= 0x40000 {
			break
		}
		if m.val >= 0x10000 {
			curRound = mmixarith.Round(m.val >> 16)
		} else {
			curRound = mmixarith.RoundNear
		}
	} else if k == rG {
		if m.val > 255 || m.val < Octa(L) || m.val < 32 {
			break
		}
		for j = int(m.val); j < G; j++ {
			m.g[j] = 0
		}
		G = int(m.val)
	} else if k == rL {
		if m.val < Octa(L) {
			L = int(m.val)
		} else {
			break
		}
	}
}

@ @<현재 옥타바이트를 보인다@>=
var aux Octa
switch curDispMode {
case 'l':
	k = int(Tetra(curDispAddr)) & m.lringMask
	m.printf("l[%d]=", k)
	aux = m.l[k]
case '$':
	k = int(curDispAddr & 0xff)
	if k < L {
		m.printf("$%d=l[%d]=", k, (O+k)&m.lringMask)
		aux = m.l[(O+k)&m.lringMask]
	} else if k >= G {
		m.printf("$%d=g[%d]=", k, k)
		aux = m.g[k]
	} else {
		m.printf("$%d=", k)
	}
case 'g':
	k = int(curDispAddr & 0xff)
	m.printf("g[%d]=", k)
	aux = m.g[k]
case 'M':
	if curDispAddr&signBit == 0 {
		ll = m.memFind(curDispAddr)
		aux = octa(ll)
	}
	m.printf("M8[#")
	m.printHex(curDispAddr)
	m.printf("]=")
}
switch curDispType {
case '!':
	m.printInt(aux)
case '.':
	m.out.WriteString(mmixarith.FloatString(aux))
case '#':
	m.out.WriteByte('#')
	m.printHex(aux)
case '"':
	@<|aux|를 문자열로 찍는다@>
}

@ 보충: 원본은 이 일을 서브루틴 |print_string|으로 했는데, 부르는 곳이 한 군데뿐이어서
여기서는 절로 두었다. 상태 |state|는 아직 아무것도 찍지 않았으면 0, 마지막으로 찍은 것이
수이면 1, 따옴표 안의 문자이면 2다.

@<|aux|를 문자열로 찍는다@>=
state := 0
for i = 0; i < 8; i++ {
	c := byte(aux >> (56 - 8*i))
	if c == 0 {
		if state != 0 {
			if state > 1 {
				m.printf("\",0")
			} else {
				m.printf(",0")
			}
			state = 1
		}
	} else if c >= ' ' && c <= '~' {
		if state == 0 {
			m.printf("\"")
		} else if state == 1 {
			m.printf(",\"")
		}
		m.out.WriteByte(c)
		state = 2
	} else {
		if state > 1 {
			m.printf("\",")
		} else if state == 1 {
			m.printf(",")
		}
		m.printf("#%x", c)
		state = 1
	}
}
if state == 0 {
	m.printf("0")
} else if state > 1 {
	m.printf("\"")
}

@ 보충: 원본에서 \.T, \.D, \.P, \.S는 현재 세그먼트를 정한 뒤, \.B는 멈춤점을 보인 뒤
|goto passit|으로 명령 문자를 건너뛰었다.

@<추적과 멈춤점을 정하고...@>=
case '@@':
	m.instPtr, p = scanHex(cmd, p+1, curSeg)
	m.halted = false
case 't', 'u':
	k = int(cmd[p])
	m.val, p = scanHex(cmd, p+1, curSeg)
	if m.val>>32 < 0x20000000 {
		ll = m.memFind(m.val)
		if k == 't' {
			ll[0].bkpt |= traceBit
		} else {
			ll[0].bkpt &^= traceBit
		}
	}
case 'b':
	@<멈춤점을 정하거나 지운다@>
case 'T':
	curSeg = 0
	p++
case 'D':
	curSeg = 0x2000000000000000
	p++
case 'P':
	curSeg = 0x4000000000000000
	p++
case 'S':
	curSeg = 0x6000000000000000
	p++
case 'B':
	m.showBreaks(m.memRoot)
	p++

@ 보충: 원본은 |bkpt|를 |ll->bkpt&-8|에 |k|를 비트 논리합한 값으로 바꾼다. 곧 추적 비트만
남기고 아래 세 비트를 새로 정한다.
주소 앞의 글자 가운데 십육진 숫자가 아닌 것은 모두 건너뛰는데, \.r, \.w, \.x만 뜻이 있다.

@<멈춤점을 정하거나...@>=
for k, p = 0, p+1; !isxdigit(cmd[p]) && cmd[p] != 0; p++ {
	switch cmd[p] {
	case 'r':
		k |= readBit
	case 'w':
		k |= writeBit
	case 'x':
		k |= execBit
	}
}
m.val, p = scanHex(cmd, p, curSeg)
if m.val&signBit == 0 {
	ll = m.memFind(m.val)
	ll[0].bkpt = ll[0].bkpt&^7 | byte(k)
}

@ @<함수들@>=
func (m *simulator) showBreaks(p *memNode) {
	if p.left != nil {
		m.showBreaks(p.left)
	}
	for j := range 512 {
		if bk := p.dat[j].bkpt; bk != 0 {
			m.printf("  %016x %c%c%c%c\n", p.loc+Octa(4*j),
				flag(bk&traceBit, 't'), flag(bk&readBit, 'r'),
				flag(bk&writeBit, 'w'), flag(bk&execBit, 'x'))
		}
	}
	if p.right != nil {
		m.showBreaks(p.right)
	}
}
@#
func flag(bit byte, c rune) rune {
	if bit != 0 {
		return c
	}
	return '-'
}

@ 명령줄 문자열을 가리키는 포인터들은 $0\le k<|argc|$일 때
M$_8[\.{Pool\_Segment}+8*(k+1)]$에 넣는다. 문자열 자체는 옥타바이트 단위로 맞추어
M$_8[\.{Pool\_Segment}+8*(|argc|+2)]$에서부터 둔다. 풀 세그먼트에서 비어 있는 첫
옥타바이트의 위치는 M$_8[\.{Pool\_Segment}]$에 넣는다.
@:Pool_Segment}\.{Pool\_Segment@>
@^command line arguments@>

보충: 원본은 문자열을 넣기 전에 |mem_find(loc)|를 한 번 불렀다. 문자열이 비어 있으면 이
호출이 없을 때 그 덩이가 생기지 않지만, 덩이가 생기든 말든 출력은 같다. 여기서도 그대로
둔다.

@<명령줄 인자들을...@>=
x = 0x4000000000000008
loc = x + Octa(8*(argc+1))
for k = 0; k < argc; k, curArg = k+1, curArg+1 {
	ll = m.memFind(x)
	ll[0].tet, ll[1].tet = Tetra(loc>>32), Tetra(loc)
	m.memFind(loc)
	m.MMPutChars([]byte(args[curArg]), len(args[curArg]), loc)
	x += 8
	loc += Octa(8 + len(args[curArg])&^7)
}
x = 0x4000000000000000
ll = m.memFind(x)
ll[0].tet, ll[1].tet = Tetra(loc>>32), Tetra(loc)

@ 보충: 원본은 덤프를 마치면 |exit(0)|으로 끝냈다. 여기서는 |return 0|이다. 버퍼를 비우는
일은 첫 절의 지연 함수가 한다.

@<처음 문맥을 \.{UNSAVE}할...@>=
x = 0xf0
ll = m.memFind(x)
if ll[0].tet != 0 {
	m.instPtr = x
}
@^subroutine library initialization@>
@^initialization of a user program@>
resuming = true
rop = resumeAgain
m.g[rX] = Octa(UNSAVE)<<24 + 255
if m.dumpFile != nil {
	x = 1
	m.dump(m.memRoot, &x)
	m.dumpTet(0)
	m.dumpTet(0)
	return 0
}

@ 특별한 옵션 `\.{-D<filename>}'을 쓰면 {\sl The Art of Computer Programming}의 1.4.3\'{}절에
나오는 \MMIX-in-\MMIX\ 시뮬레이터에 필요한 이진 파일을 준비할 수 있다. (1권 분책~1을 보라.)
@^Fascicle 1@>
이 옵션은 큰 쪽 먼저인 옥타바이트들을 주어진 파일에 넣는다. 위치~$l$ 다음에 0이 아닌
옥타바이트 하나 이상 M$_8[l]$, M$_8[l+8]$, M$_8[l+16]$, \dots가 오고, 그다음에 0이 온다.
흉내 낸 시뮬레이터는 이런 형식의 프로그램을 싣는 법을 알고(연습 문제 1.4.3\'{}--20을
보라), 메타 시뮬레이터 {\mc MMMIX}도 그렇다.

보충: 원본의 |dump|는 전역 변수 |x|를 ``다음에 올 것으로 기대하는 위치''로 썼다. 처음 값
1은 아직 아무것도 쓰지 않았다는 표시다. 여기서는 그 변수를 포인터로 넘긴다.

@<함수들@>=
func (m *simulator) dump(p *memNode, x *Octa) {
	if p.left != nil {
		m.dump(p.left, x)
	}
	for j := 0; j < 512; j += 2 {
		if p.dat[j].tet != 0 || p.dat[j+1].tet != 0 {
			curLoc := p.loc + Octa(4*j)
			if curLoc != *x {
				if Tetra(*x) != 1 {
					m.dumpTet(0)
					m.dumpTet(0)
				}
				m.dumpTet(Tetra(curLoc >> 32))
				m.dumpTet(Tetra(curLoc))
				*x = curLoc
			}
			m.dumpTet(p.dat[j].tet)
			m.dumpTet(p.dat[j+1].tet)
			*x += 8
		}
	}
	if p.right != nil {
		m.dump(p.right, x)
	}
}

@ @<함수들@>=
func (m *simulator) dumpTet(t Tetra) {
	m.dumpFile.WriteByte(byte(t >> 24))
	m.dumpFile.WriteByte(byte(t >> 16))
	m.dumpFile.WriteByte(byte(t >> 8))
	m.dumpFile.WriteByte(byte(t))
}

@* \CEE/ 라이브러리 흉내 내기. 이 장은 옮긴이가 덧붙인 것이다. 원본은 원시 파일, 끼워 넣은
명령 파일, 표준 입력을 \CEE/의 |fgets|로 읽었고, 원시 파일에서는 |ftell|과 |fseek|도 썼다.
함수 |fgets|는 읽은 바이트와 끝의 널 문자만 버퍼에 쓰고 나머지는 그대로 둔다. 원본의 여러 곳이
이 성질에 기대거나, 적어도 그 영향을 받는다. 그래서 그 동작을 흉내 내는 작은 타입
|cfile|을 둔다. 파일 끝 표시는 한 번 켜지면 꺼지지 않는다(``끈끈한'' EOF). 원본을 시험한
macOS의 라이브러리가 그렇다. |fseek|과 |freopen|은 한 곳에서만 쓰므로 그 자리에서 흉내 낸다.

@<타입 정의@>=
type cfile struct {
	f   *os.File      // 읽는 파일; 표준 입력이면 |nil|
	r   *bufio.Reader // 읽기 버퍼
	pos int64         // |ftell|이 돌려줄 위치
	eof bool          // 파일 끝 표시(|feof|)
}

@ @<함수들@>=
func newCfile(f *os.File) *cfile {
	return &cfile{f: f, r: bufio.NewReader(f)}
}
@#
func openCfile(name string) *cfile {
	f, err := os.Open(name)
	if err != nil {
		return nil
	}
	return newCfile(f)
}

@ \CEE/의 |fgets(buf,n,fp)|은 바이트를 |n-1|개까지 읽되 줄 바꿈 문자를 읽으면 멈추고, 읽은
것 뒤에 널 문자를 둔다. 아무것도 읽지 못하고 파일 끝이나 오류를 만나면 실패한다. 읽기
오류도 파일 끝처럼 다룬다.

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

@ \CEE/ 문자열 흉내: |strlen|은 첫 널 문자의 색인이고, |cstr|은 첫 널 문자 앞까지의
바이트들이다. 문자 분류는 \CEE/ 로캘의 것이다.

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
없으면 짝이 맞지 않는다. 원본은 그 경우에 값을 0으로 두었으므로 여기서도 0을 돌려준다.
원본을 시험한 macOS의 라이브러리는 숫자들을 |strtoimax|로 바꾸는데, 범위를 넘으면 가장 큰 값이나 가장
작은 값에서 멈춘다. 그 값을 |int|에 넣으면 아랫 32비트만 남는다. 또 빈칸 뒤로는 512자까지만
읽는다. 서식 \.{\%x}는 부호 뒤에 \.{0x}를 받을 수 있고, 부호 없는 수로 바꾸어 음수 부호가
있으면 부호를 바꾼다. 함수 |sscanf|는 |base16|이 참이면 \.{\%x}를, 거짓이면 \.{\%d}를
흉내 낸다.

@<함수들@>=
func sscanf(s string, base16 bool) int32 {
	var sign, digits string
	@<빈칸을 건너뛰고 부호와 숫자들을 떼어 낸다@>
	if digits == "" {
		return 0
	}
	if !base16 {
		n, _ := strconv.ParseInt(sign+digits, 10, 64) // 넘치면 끝값에서 멈춘다
		return int32(n)
	}
	n, _ := strconv.ParseUint(digits, 16, 64) // 넘치면 끝값에서 멈춘다
	if sign == "-" {
		n = -n
	}
	return int32(n)
}

@ 부호와 접두어와 숫자를 합쳐 512자까지만 읽는다. 접두어 \.{0x} 다음에 십육진 숫자가 없으면
값은 0이다.

@<빈칸을 건너뛰고...@>=
digit := isdigit
if base16 {
	digit = isxdigit
}
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
	sign = s[i : i+1]
	i++
}
if base16 && i+1 < len(s) && s[i] == '0' && (s[i+1] == 'x' || s[i+1] == 'X') {
	if i+2 >= len(s) || !digit(s[i+2]) {
		return 0
	}
	i += 2
}
j := i
for j < len(s) && digit(s[j]) {
	j++
}
digits = s[i:j]

@* 시험. 원본에는 시험 프로그램이 따로 없었지만, 크누스의 꾸러미에는 시뮬레이터를 시험하는
\.{silly.mms}와 대화 명령 파일 \.{silly.run}, 그리고 기대하는 출력 \.{silly.out}이 들어 있다.
옮긴이는 그것을 첫 시험으로 삼았다. 나머지 시험들은 옮긴이가 만든 것이다. 시험마다 임시
디렉터리로 옮겨 가서 시뮬레이터를 부르므로, 파일 이름이 원본을 돌릴 때와 같다.

시험 대부분은 작은 목적 파일을 그 자리에서 만든다. 함수 |writeMMO|는 서문(시각 없음),
\.{Main}의 위치, 명령들, 그리고 $\rm G=255$이고 $\$255=\.{Main}$인 후기로 이루어진 목적
파일을 쓴다.

@(mmixsim_test.go@>=
package main

import (
	"bytes"
	"encoding/binary"
	hexenc "encoding/hex"
	"os"
	"strings"
	"testing"
	"time"
)

func simulate(t *testing.T, stdin string, args ...string) (stdout, stderr string, code int) {
	t.Helper()
	var o, e bytes.Buffer
	code = mmix(append([]string{"mmix"}, args...), strings.NewReader(stdin), &o, &e)
	return o.String(), e.String(), code
}

func writeMMO(t *testing.T, name string, main Octa, code ...Tetra) {
	t.Helper()
	tets := []Tetra{0x98090100, 0x98010002, Tetra(main >> 32), Tetra(main)}
	tets = append(tets, code...)
	tets = append(tets, 0x980a00ff, Tetra(main>>32), Tetra(main))
	var b []byte
	for _, x := range tets {
		b = binary.BigEndian.AppendUint32(b, x)
	}
	if err := os.WriteFile(name, b, 0o644); err != nil {
		t.Fatal(err)
	}
}

@ 크누스의 \.{silly.out}은 단말기에서 만든 것이어서, 사용자가 친 `\.{i silly.run}'이 들어
있고 표준 오류로 나간 경고 두 줄이 표준 출력 사이에 섞여 있다. 그것을 걷어 내면 우리의
표준 출력과 한 바이트도 다르지 않아야 한다. 목적 파일은 \.{silly.mms}를 \.{mmixal}로
어셈블한 것이다. 원시 파일을 목적 파일보다 나중에 고친 것처럼 보이면 경고가 붙으므로,
원시 파일의 수정 시각을 목적 파일의 시각으로 맞춘다.

@(mmixsim_test.go@>=
func TestSilly(t *testing.T) {
	var files [3][]byte
	for i, name := range []string{"silly.mms", "silly.run", "silly.out"} {
		b, err := os.ReadFile("../examples/" + name)
		if err != nil {
			t.Fatal(err)
		}
		files[i] = b
	}
	mmo, err := hexenc.DecodeString(strings.Join(strings.Fields(sillyMMOHex), ""))
	if err != nil {
		t.Fatal(err)
	}
	t.Chdir(t.TempDir())
	os.WriteFile("silly.mmo", mmo, 0o644)
	os.WriteFile("silly.mms", files[0], 0o644)
	os.WriteFile("silly.run", files[1], 0o644)
	when := time.Unix(int64(binary.BigEndian.Uint32(mmo[4:])), 0)
	os.Chtimes("silly.mms", when, when)
	out, errs, _ := simulate(t, "i silly.run\n", "-i", "silly")
	want := strings.Replace(string(files[2]), "mmix> i silly.run\n", "mmix> ", 1)
	var lines []string
	for _, s := range strings.SplitAfter(want, "\n") {
		if !strings.HasPrefix(s, "Warning:") {
			lines = append(lines, s)
		}
	}
	if want = strings.Join(lines, ""); out != want {
		os.WriteFile("/tmp/silly.got", []byte(out), 0o644)
		t.Errorf("표준 출력이 silly.out과 다르다")
	}
	if errs != "Warning: TRIP at location 000000000000039c\n"+
		"Warning: floating point underflow at location 00000000000003a0\n" {
		t.Errorf("표준 오류 %q", errs)
	}
}

@ @(mmixsim_test.go@>=
const sillyMMOHex = `
98090101 6ab7bebd 98012001 00000000 2404fc01 3f04fc01 80818283 84858687
88898a8b 8c8d8e8f f0000002 f8000000 5f030405 97030405 9f28f305 ef28f305
98010001 00000100 98060003 73696c6c 792e6d6d 73000000 9807001d 0100fd05
0101fdfb 0102fbfa 0203fafa 030404fd 0405fcfb 0406fcfd 0407fcfc 0408fcfa
0609fcfe f61500f9 0609fcfe 0609fefc 150a0009 060bfa0a f61500f7 060cfcfc
060c1415 060c14fd f61500f8 2500fb01 040c00fe 050c00fc 070e0309 080f03f6
081002f6 35010001 09110001 08110001 0b1200ff 0a1200fd 050d0412 0c1203f6
0c1302f6 06141213 0614100f 0d140001 0c140001 0e150001 0f1500ff 1016fdfb
1016fcfc 1017fe00 f60200fc 1118fc15 1118fdfe 1118fdfc 1118fcfb 13180f10
f60200fd 1318fcfc 1218fcfc 15190200 141a0019 f6150032 141a0019 101b1919
161c09fc 161d09fe 171e0009 171e02fe 181ff4f4 1820f401 1921f402 1c202001
1c20fd01 1a20f401 1a1ff4f4 fe210003 f6010021 1d210103 1e221ff4 2023f6f5
0424f6f5 30252423 f4030000 f6180003 8906f100 8b07f104 98040004 30050607
48050000 e6060100 f6190006 f9000000 98040004 40000006 5100ffff 48000006
50000005 58000005 4100fffd 4900fffd 5100fffd 5900fffd 42000006 5300ffff
4a000006 52000005 5a000005 4300fffd 4b00fffd 5300fffd 5b00fffd 44000006
5500ffff 4c000006 54000005 5c000005 4500fffd 4d00fffd 5500fffd 5d00fffd
46000006 5700ffff 4e000006 56000005 5e000005 4700fffd 4f00fffd 5700fffd
5f00fffd 2304f10c f4030000 f6180003 8b07f124 8b06f120 98040004 32080607
48080000 e6060100 f6190006 f9000000 fedcba98 9807009f 76543210 ffeeddcc
980700a0 bbaa9988 34f300f6 c1f2f400 f60500f5 f8000000 9804000c f504fff8
e307002c 9e070704 9f070430 9a460404 9b460400 9c460404 9d460400 9503f115
f4030000 f6180003 e3f20001 21f30404 8f28f118 8b07f12c 8b06f128 98040007
32080607 48080000 e6060100 f6190006 c105f200 f9000000 98040005 3928fe33
3928fe34 faff0000 f71300fe e7fd0400 0464fec8 f61500fd ff0164fe 0664fec8
f714000a f61400fe f20b0001 fb0000ff 00000000 98010001 00000060 980700cb
f2ff0000 00000001 25000101 f8020000 fe320019 e4328100 093c0001 f61b003c
f0000000 98010001 00000000 980700d6 fe320019 e4328200 e532fb00 00000001
98050018 01ffffe4 f6190032 feff0000 f9000000 98050010 0100ffef e305abcd
fe010004 f2030010 240a0304 f6040001 f80b0003 980a00f1 20000000 00000000
00000000 00000000 00000000 00000000 01020408 10204080 ff5ffb6a 4534a3f7
7f6001b4 c67bc809 00000000 00030000 00000000 00020000 00000000 00010000
7ff10000 00000000 7ff00000 00000000 3fe00000 00000000 80000000 00000000
00000000 00000abc 00000000 00000100 980b0000 203a5050 50502042 20694020
67205f30 42206520 67206909 6e289520 45206e09 642c9660 20464010 10206920
6e206120 6c205f20 49206e20 73097404 90482061 10206e20 64206c20 6501721c
97404060 60204a20 6d207020 5f205020 6f097018 924c206f 20612064 205f6030
42206520 67206909 6e209320 45206e09 64249454 20652073 09740891 4d206120
69026e01 00812053 20742061 10207220 74205f20 49206e20 73097400 8f706070
30612064 20641f79 f68a0f7a f58b2066 206c2069 0f70f48c 68206120 6c0f66fc
84206920 6e0f66fb 856e2065 2067205f 207a2065 20720f6f fd837210 10101010
10101010 10101010 1010306f 2075206e 2064205f 70206420 6f20770f 6ef7896f
20660f66 f9872075 0f70f888 1f79f38d 0f7af28e 20736020 69206720 5f206e20
610f6efa 866d2061 206c0f6c fe820000 980c004f`

@ 크누스의 \.{hello.mms}를 손으로 어셈블한 것이다. 이 프로그램은 자신의 이름(첫 명령줄
인자)과 \.{", world"}를 찍는다. 종료 코드는 마지막 \.{Fputs}가 돌려준 8이다. 옵션 \.{-t9}로
추적하면 원본과 같은 모양의 추적 출력이 나와야 한다.

@(mmixsim_test.go@>=
var helloCode = []Tetra{
	0x8fff0100, // |LDOU $255,argv,0|
	0x00000701, // |TRAP 0,Fputs,StdOut|
	0xf4ff0003, // |GETA $255,String|
	0x00000701, // |TRAP 0,Fputs,StdOut|
	0x00000000, // |TRAP 0,Halt,0|
	0x2c20776f, 0x726c640a, 0x00000000} // |String BYTE ", world",#a,0|

func TestHello(t *testing.T) {
	t.Chdir(t.TempDir())
	writeMMO(t, "hello.mmo", 0x100, helloCode...)
	out, errs, code := simulate(t, "", "hello")
	if out != "hello, world\n" || errs != "" || code != 8 {
		t.Errorf("출력 %q, 오류 %q, 종료 코드 %d", out, errs, code)
	}
	out, _, _ = simulate(t, "", "-t9", "-s", "hello")
	if out != helloTrace {
		t.Errorf("추적 출력:\n%s", out)
	}
}

const helloTrace = "" +
	"         1. 0000000000000100: 8fff0100 (LDOUI) " +
		"$255=g[255] = M8[#4000000000000008] = #4000000000000018\n" +
	"  1 instruction, 1 mem, 1 oop; 0 good guesses, 0 bad\n" +
	"hello         1. 0000000000000104: 00000701 (TRAP) " +
		"$255 = Fputs(StdOut,#4000000000000018) = 5\n" +
	"  2 instructions, 1 mem, 6 oops; 0 good guesses, 0 bad\n" +
	"         1. 0000000000000108: f4ff0003 (GETA) $255=g[255] = #114\n" +
	"  3 instructions, 1 mem, 7 oops; 0 good guesses, 0 bad\n" +
	", world\n" +
	"         1. 000000000000010c: 00000701 (TRAP) " +
		"$255 = Fputs(StdOut,#114) = 8\n" +
	"  4 instructions, 1 mem, 12 oops; 0 good guesses, 0 bad\n" +
	"         1. 0000000000000110: 00000000 (TRAP) Halt(0)\n" +
	"  5 instructions, 1 mem, 17 oops; 0 good guesses, 0 bad\n" +
	"  (halted at location #0000000000000110)\n" +
	"  5 instructions, 1 mem, 17 oops; 0 good guesses, 0 bad\n" +
	"  (halted at location #0000000000000110)\n"

@ 명령줄과 목적 파일이 잘못되었을 때다.

@(mmixsim_test.go@>=
func TestBadInputs(t *testing.T) {
	t.Chdir(t.TempDir())
	_, errs, code := simulate(t, "")
	if code != -1 || !strings.HasPrefix(errs,
		"Usage: mmix <options> progfile command line-args...\n with these options:") {
		t.Errorf("인자가 없을 때: %d %q", code, errs)
	}
	_, errs, code = simulate(t, "", "nothing")
	if code != -3 || errs != "Can't open the object file nothing or nothing.mmo!\n" {
		t.Errorf("파일이 없을 때: %d %q", code, errs)
	}
	os.WriteFile("bad.mmo", []byte{0x98, 0x09, 0x01}, 0o644)
	_, errs, code = simulate(t, "", "bad")
	if code != -4 || errs != "Bad object file! (Try running MMOtype.)\n" {
		t.Errorf("잘린 목적 파일: %d %q", code, errs)
	}
	writeMMO(t, "hello.mmo", 0x100, helloCode...)
	_, errs, code = simulate(t, "", "-c300", "hello")
	if code != -2 || errs != "Panic: The number of local registers must be a power of 2!\n" {
		t.Errorf("-c300: %d %q", code, errs)
	}
}

@ 원본에서 찾은 이상한 동작 세 가지를 못 박아 둔다. 첫째, \.{-e} 옵션은 예외 비트를 rA의
패턴(\Hex{ff})으로 받지만, 시뮬레이터는 그것을 |exc|의 비트(\Hex{ff00})와 견준다. 그래서
\.{-e}로는 아무것도 추적되지 않고 \.{-eff00}이어야 추적된다. 둘째, 특권 명령 뒤에
대화 방식으로 시뮬레이션을 이어 가면, X를 목적지로 쓰지 않는 명령들이 추적에서 모두
``\.{privileged instruction!}''으로 나온다. 문자열 |lhs|가 그대로 남아 있기 때문이다. 셋째,
대화 명령 `\.{rG=40}'은 아무 일도 하지 않는다.

@(mmixsim_test.go@>=
func TestOddities(t *testing.T) {
	t.Chdir(t.TempDir())
	writeMMO(t, "ovf.mmo", 0x100,
		0xe0017fff, // |SETH $1,#7fff|
		0x20020101, // |ADD $2,$1,$1|
		0x00000000) // |TRAP 0,Halt,0|
	if out, _, _ := simulate(t, "", "-e", "ovf"); out != "" {
		t.Errorf("-e가 무언가를 추적했다:\n%s", out)
	}
	out, _, _ := simulate(t, "", "-eff00", "ovf")
	if !strings.Contains(out, "(ADD) rL=3, $2=l[2] = ") {
		t.Errorf("-eff00의 출력:\n%s", out)
	}
	writeMMO(t, "priv.mmo", 0x100,
		0xe3010005, // |SETL $1,5|
		0xfd000000, // |SWYM|
		0x00010203, // |TRAP 1,2,3|
		0xfd000000, // |SWYM|
		0xf0000001, // |JMP @@+4|
		0x00000000) // |TRAP 0,Halt,0|
	out, _, _ = simulate(t, "c\nc\nrG=40\nq\n", "-i", "-t9", "priv")
	for _, want := range []string{
		"000000000000010c: fd000000 (SWYM) privileged instruction!\n",
		"0000000000000114: 00000000 (TRAP) privileged instruction!\n",
		"mmix> g[19]=255\n"} {
		if !strings.Contains(out, want) {
			t.Errorf("%q가 없다:\n%s", want, out)
		}
	}
}

@* 찾아보기.
