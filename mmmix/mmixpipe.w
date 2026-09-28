% 이 파일은 MMIXware의 mmix-pipe.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

@s io.Writer int
@s bufio.Writer int
@s mmixarith.Octa int
@s mmixarith.Tetra int
@s mmixarith.Round int
@s mmixio.IO int
@s mmixio.Simulator int
@s cfile int

\input kotexgweb
\def\title{MMIXPIPE}
\def\NNIX{\hbox{\mc NNIX}}

@* 들어가며. 이 프로그램은 설정을 한없이 바꿀 수 있는 \MMIX\ 파이프라인을 흉내 내는 메타
시뮬레이터의 심장이다. 이 프로그램은 일의 대부분을 하는 루틴 |MMIX_run|을 정의한다. 또 다른
루틴 |MMIX_init|도 여기서 정의하고, \.{mmix-pipe.h}라는 헤더 파일도 여기서 정의한다. 그
헤더 파일은 주 루틴과, 따로 컴파일되는 |MMIX_config| 같은 다른 루틴들이 쓴다.

이 프로그램을 읽는 사람은 {\mc MMMIX}의 주 프로그램 모듈에 나오는 \MMIX\ 아키텍처 설명에
익숙해야 한다.

명령들을 나란히 실행할 때는 미묘한 일이 많이 일어날 수 있다. 그래서 이 시뮬레이터는
크누스가 겪은 프로그램 가운데 가장 흥미롭고 배울 것이 많은 축에 든다. 크누스는 모든 것을
바르게 하려고 최선을 다했지만\dots\ 잘못이 생길 여지는 크다. 그러니 버그를 찾은 사람은
되도록 빨리 알려 주기 바란다. 방법은 \.{http:/\kern-.1em/mmix.cs.hm.edu/bugs/}에 있다.

이 프로그램이 언젠가 \MMIX용 \CEE/~컴파일러로 번역되어 {\it 자기 자신\/}을 흉내 내는
데 쓰일지도 모른다는 생각을 하면 머리가 어질어질하다.

보충: \GO/ 판에서 메타 시뮬레이터는 디렉터리 \.{mmmix} 하나에 든 \.{main} 꾸러미다.
크누스의 네 파일 \.{mmix-pipe.w}, \.{mmix-config.w}, \.{mmix-mem.w}, \.{mmmix.w}는 각각
\.{mmixpipe.w}, \.{mmixconfig.w}, \.{mmixmem.w}, \.{mmmix.w}로 옮겼고, 저마다 같은 이름의
\GO/ 파일을 만든다. 원본은 헤더 파일 \.{mmix-pipe.h}로 전역 변수를 나누어 썼는데, 여기서는
그 변수들이 모두 구조체 |machine|의 필드다. 주 프로그램 \.{mmmix.w}가 파이프라인의 속사정을
직접 들여다보므로, 꾸러미를 나누지 않고 한 꾸러미에 두었다.

@c
package main

import (
	"bufio"
	"fmt"
	"io"
	"math/bits"
	@#
	"github.com/sjnam/mmix/mmixarith"
	"github.com/sjnam/mmix/mmixio"
)

@<타입 정의@>
@<상수@>
@<표@>
@<함수들@>

@ 이 고성능 \MMIX\ 시제품은 ``파이프라이닝''으로 효율을 얻는다. 파이프라이닝은 겹쳐서 일하는
기법인데, Hennessy와 Patterson의 책 {\sl Computer Architecture\/}(제2판) 3장에서 비슷한
@^Hennessy, John LeRoy@>
@^Patterson, David Andrew@>
\.{DLX} 컴퓨터를 예로 설명되어 있다. 그 책의 4장에서 설명하는 ``동적 스케줄링''과 ``다중
발행''이라는 기법도 쓴다.

이 과정을 머릿속에 그리는 좋은 방법 하나는, 누군가가 비슷한 원리로 첨단 자동차 정비소를
차렸다고 상상하는 것이다. 독립된 기능 장치가 여덟 개 있는데, 이것들을 저마다 특정한 일을
전문으로 하는 자동차 정비공 여덟 무리라고 생각하면 된다. 무리마다 자기 작업 공간이 있어서
한 번에 차 한 대를 다룰 수 있다. F~무리(``가져오기'' 무리)는 손님을 끌어모아 조립 라인
정비소에 차례로 들여보내는 일을 맡는다. D~무리(``해독과 배정'' 무리)는 처음에 차를
점검하고, 어떤 정비가 필요한지 적은 작업 지시서를 쓴다. 그다음에 차들은 네 ``실행''
무리 가운데 하나로 간다. X~무리는 일상적인 정비를 하고, XF, XM, XD 무리는 더 복잡하고 대개
더 오래 걸리는 일의 전문가들이다. (XF 사람들은 소수점을 띄우는 일에 능하고, XM과 XD 무리는
다중 링크 서스펜션과 디퍼렌셜의 전문가들이다.) 해당하는 X~무리가 일을 마치면 차들은 M~정거장으로
가서 메시지를 주고받고, 어쩌면 ``메모리'' 무리에게 돈을 치른다. 마지막으로 W~무리, 곧
``쓰기'' 무리가 필요한 부품을 모두 달아 주고 차가 정비소를 떠난다. 모든 것이 빈틈없이
짜여 있어서, 대개 차들은 100나노세기라는 일정한 간격으로 정거장에서 정거장으로 발맞추어
움직인다.

이와 비슷하게, 대부분의 \MMIX\ 명령은 F--D--X--M--W라는 다섯 단계 파이프라인에서 처리할 수
있다. 부동소수점 덧셈이나 변환이면 X 대신 XF를, 곱셈이면 XM을, 나눗셈이나 제곱근이면 XD를
쓴다. 단계마다 이상적으로는 한 클럭 사이클이 걸리지만, XF, XM, 그리고 (특히) XD는 더 느리다.
명령들이 알맞은 모양으로 들어오면, 한 명령을 가져오는 동안 다른 명령을 해독하고, 네 명령까지
실행하고, 또 다른 명령은 메모리에 접근하고, 또 다른 명령은 레지스터에 새 정보를 써서 일을
마무리하는 광경을 볼 수 있다. 이 모든 일이 한 클럭 사이클 동안 동시에 일어난다. 따라서 여덟
단계로 파이프라인을 짜면, 명령마다 따로따로 겹치지 않고 처리할 때보다 기계가 최대 8배까지
빨라질 수 있다. (사실 완벽한 가속은 불가능한 것으로 드러난다. M과~W 단계를 함께 쓰기
때문이다. {\sl The Art of Computer Programming\/} 7.7절에서 다룰 배낭 문제 이론에 따르면, XF,
XM, XD의 지연이 각각 $p$, $q$, $r$ 사이클 이하일 때 얻을 수 있는 최대 가속은 많아야
$8-1/p-1/q-1/r$이다. 그래도 운이 아주 좋으면 7배가 넘는 가속을 얻을 수 있다.)

\.{ADD} 명령을 예로 생각해 보자. 이 명령은 F 단계에서 컴퓨터의 처리 장치로 들어오는데, 최근에
본 명령들의 캐시에 들어 있다면 한 클럭 사이클만 걸린다. 그다음 D~단계가 그 명령이 \.{ADD}임을
알아보고 \$Y와 \$Z의 현재 값을 얻는다. 물론 그동안 F는 다른 명령을 가져오고 있다. 다음 클럭
사이클에 X 단계가 두 값을 더한다. 이것으로 M 단계가 넘침을 살피고, 특수 레지스터~rA의 설정에
따라 필요할지 모르는 예외 조치를 준비할 길이 열린다. 마지막으로 다섯째 클럭 사이클에 합이
\$X에 쓰이거나, 정수 넘침을 처리하는 트립 처리기가 불린다. 이 과정에 다섯 클럭 사이클(곧
$5\upsilon$)이 걸렸지만, 실행 시간은 $1\upsilon$만 늘었다.

물론 정비소에서처럼 컴퓨터 안에서도 정체가 생길 수 있다. 이를테면 자동차 부품을 바로 구할
수 없을 수도 있고, 어떤 차는 XM으로 가려고 D 정거장에서 기다리느라 다른 차가 F에서 D로
옮기지 못하게 막을 수도 있다. 손님이 늘 꾸준히 오지는 않을 수도 있다. 그럴 때는 정비소
일부의 일꾼들이 이따금 논다. 그러나 우리는 그들이 마주치는 손님들의 순서가 주어졌을 때 늘
최대한 빨리 일한다고 가정한다. 영리한 누군가가 약속을 잡아 준다면---곧 영리한
프로그래머나 컴파일러가 \MMIX\ 명령들을 배열해 준다면---조직은 흔히 최고 능력에 가깝게
돌아갈 것이다.

사실 이 프로그램은 여러 종류의 파이프라인으로 실험할 수 있도록 설계되었다. 기능 장치를 더
쓸 수도 있고(이를테면 독립된 X~무리를 여럿 둘 수도 있다), 서로 충돌하지 않는 명령 여러 개를
동시에 가져오고 배정하고 실행할 수도 있다. 이런 복잡함 탓에 이 프로그램은 단순한 파이프라인
시뮬레이터보다 어렵다. 그러나 문제를 더 일반적으로 다루어야 하므로 관련된 쟁점들을 더 잘
이해하게 되어, 훨씬 배울 것이 많아지기도 한다.

@ 원본은 여기서 프로그램 모듈 전체의 구조를 보였다. 보충: 앞의 절에 둔 뼈대가 그 구조다.
원본은 다른 모듈에서 쓰는 변수를 \KW{Extern}이라고 선언해서, 이 모듈에서는 빈칸으로, 헤더
파일에서는 \KW{extern}으로 바꾸었다. \GO/에서는 한 꾸러미 안의 이름이 어디서나 보이므로
그런 장치가 필요 없다. 원본의 헤더 파일은 이 모듈의 기본 정의와 선언을 되풀이했고, 옛
컴파일러를 위해 \.{ARGS} 매크로를 두었고, 어떤 컴퓨터의 라이브러리와 이름이 부딪치지 않도록
|random|, |fsqrt|, |div|를 다른 이름으로 바꾸었다. 모두 \GO/에서는 필요 없다.

@ 진단 출력을 얼마나 할지는 다음 비트 코드들에 달려 있다.

@<상수@>=
const (
	issueBit          = 1 << 0 // 명령을 발행하고, 발행을 취소하고, 확정할 때 제어 블록을 보인다
	pipeBit           = 1 << 1 // 사이클마다 파이프라인과 잠금을 보인다
	coroutineBit      = 1 << 2 // 사이클마다 시작하는 코루틴들을 보인다
	scheduleBit       = 1 << 3 // 코루틴을 스케줄할 때 보인다
	uninitMemBit      = 1 << 4 // 초기화하지 않은 메모리 덩이를 읽으면 알린다
	interactiveReadBit = 1 << 5 // 입출력 위치를 읽을 때 사용자에게 묻는다
	showSpecBit       = 1 << 6 // 특별한 읽기와 쓰기가 일어날 때 보인다
	showPredBit       = 1 << 7 // 분기 예측의 자세한 사정을 보인다
	showWholecacheBit = 1 << 8 // 열쇠 태그가 무효인 캐시 블록도 보인다
)

@ @<기계의 상태@>=
verbose int // 진단 출력의 수준을 정한다

@ 루틴 |MMIX_init()|는 |MMIX_config()|가 일을 마친 뒤, 시뮬레이터가 프로그램을 실행하기
시작하기 전에 정확히 한 번 불러야 한다. 그다음에는 |MMIX_run()|을 사용자가 원하는 만큼
여러 번 부를 수 있다.

루틴 |MMIX_silent()|는 |MMIX_run()|의 대화하지 않는 변형이다. \.{TRAP} \.{0,Halt,0} 명령을
실행하면 레지스터 |g[255].l|의 값을 돌려준다.

보충: \GO/에서는 셋 다 |machine|의 메서드 |MMIXInit|, |MMIXRun|, |MMIXSilent|다. 원본의
|MMIX_silent|와 |MMIX_run|은 같은 절 ``한 기계 사이클을 수행한다''를 각자 끼워 넣었는데,
여기서는 그 절을 메서드 |cycle|로 두고 둘이 함께 부른다. 원본에서 |breakpoint_hit|과
|halted|는 두 루틴의 지역 변수였지만, 코루틴들이 바꾸므로 여기서는 필드다. 두 루틴은
시작할 때 이것들을 거짓으로 되돌린다. 원본의 |MMIX_silent|는 지역 변수 |breakpoint|를
초기화하지 않고 썼지만, 멈춤점에 걸렸는지는 보지 않으므로 결과에는 상관이 없다.

@<함수들@>=
func (mx *machine) MMIXInit() {
	var i, j int
	@<모든 것을 초기화한다@>
}
@#
func (mx *machine) MMIXSilent() int {
	mx.breakpointHit, mx.halted = false, false
	mx.breakpoint = 0
	for {
		mx.cycle()
		if mx.halted {
			return int(int32(Tetra(mx.specval(&mx.g[255]).o)))
		}
	}
}
@#
func (mx *machine) MMIXRun(cycs int, breakpoint Octa) {
	mx.breakpointHit, mx.halted = false, false
	mx.breakpoint = breakpoint
	for cycs != 0 {
		if mx.verbose&(issueBit|pipeBit|coroutineBit|scheduleBit) != 0 {
			mx.printf("*** Cycle %d\n", int32(Tetra(mx.ticks)))
		}
		mx.cycle()
		if mx.verbose&pipeBit != 0 {
			mx.printPipe()
			mx.printLocks()
		}
		if mx.breakpointHit || mx.halted {
			if mx.breakpointHit {
				mx.printf("Breakpoint instruction fetched at time %d\n",
					int32(Tetra(mx.ticks))-1)
			}
			if mx.halted {
				mx.printf("Halted at time %d\n", int32(Tetra(mx.ticks))-1)
			}
			break
		}
		cycs--
	}
}

@ @<기계의 상태@>=
breakpointHit bool // 멈춤점의 명령을 가져왔는가?
halted        bool // 기계가 멈추었는가?
breakpoint    Octa // |MMIXRun|의 멈춤점

@ 원본은 불 타입에 거짓과 참 말고 |wow|라는 셋째 값까지 두었다(``살짝 넓힌 불 값'').
그러나 |wow|는 어디서도 쓰지 않는다. \GO/의 |bool|로 충분하다.

@ 이 프로그램을 끝내는 오류 메시지를 공황 메시지라고 부른다. 알림 |confusion|은 이
프로그램이 안에서 앞뒤가 맞지 않을 때가 아니면 결코 필요 없다.

보충: 원본의 매크로 |panic(x)|는 \.{"Panic: "}을 찍고, |x|로 메시지를 찍고, \.{"!\\n"}을
찍은 뒤 |expire|를 불렀다. \GO/에서는 메시지 문자열을 받는 메서드 |panic|이다. 원본의
|confusion(m)|은 \.{"This can't happen: "}에 |m|을 붙인 메시지다. 원본의 |exit(-2)|는
|exitSignal|을 던지는 공황이 되고, 주 프로그램이 그것을 종료 코드로 바꾼다.
@.This can't happen@>

@<함수들@>=
func (mx *machine) panic(msg string) {
	mx.errprintf("Panic: %s!\n", msg)
	mx.expire()
}
@#
func confusion(m string) string {
	return "This can't happen: " + m
}
@#
func (mx *machine) expire() { // 죽기 전 마지막 숨
	if mx.ticks>>32 != 0 {
		mx.errprintf("(Clock time is %dH+%d.)\n",
			int32(mx.ticks>>32), int32(Tetra(mx.ticks)))
	} else {
		mx.errprintf("(Clock time is %d.)\n", int32(Tetra(mx.ticks)))
	}
@.Clock time is...@>
	panic(exitSignal(-2))
}

@ 보충: 표준 출력과 표준 오류에 쓰는 메서드를 둔다. 원본의 |printf|와 |fprintf(stderr,...)|에
해당한다. 표준 출력은 버퍼를 거치고, 표준 오류는 바로 쓴다.

@<함수들@>=
func (mx *machine) printf(format string, a ...any) {
	fmt.Fprintf(mx.out, format, a...)
}
@#
func (mx *machine) errprintf(format string, a ...any) {
	fmt.Fprintf(mx.stderr, format, a...)
}

@ 이 프로그램의 데이터 구조는 실리콘에 바로 구현할 수 있는 논리 게이트와 정확히 같지는
않다. \CEE/ 프로그래밍 언어에 알맞은 데이터 구조와 알고리즘을 쓸 것이다. 이를테면 버스와
포트와 래치 대신 포인터와 배열을 쓴다. 그러나 우리의 데이터 구조와 알고리즘이 내는 최종
효과는 실리콘 구현이 내는 최종 효과와 같도록 하려는 것이다. 아래에서 쓰는 방법들은 오늘날의
실제 기계에서 쓰는 방법들과 본질적으로 같다. 다만 무슨 일이 일어나는지 쉽게 지켜볼 수 있도록
진단 기능을 덧붙였다.

\MMIX\ 파이프라인의 기능 장치는 저마다 \CEE/(보충: 여기서는 \GO/)의 코루틴으로 프로그램된다.
클럭 사이클마다 활성인 코루틴 하나하나를 불러 그 동작의 한 국면을 하게 한다. 주 프로그램에서
설명한 정비소 비유로 말하면, 정비공 무리마다 차 한 대에 대해 한 단위의 작업을 하게 하는 것에
해당한다. 실제 파이프라인에서는 코루틴들이 나란히 움직이겠지만, 여기서는 차례로 수행한다.
하드웨어가 같은 방식으로 ``속일'' 수 있는 경우가 아니라면, 어떤 코루틴이 자기 사이클 초기에
다른 코루틴이 그 사이클 후반에 계산하는 값에 접근하는 식으로 ``속이지'' 않는다.

@* 저수준 루틴. 어디서 시작해야 할까? 시뮬레이터 전체를 먼저 바라본 다음 구성 요소로 쪼개
나가고 싶은 마음이 든다. 그러나 그 일은 너무 벅차다. 더 큰 구성 요소를 만들 때 어떤 기본
재료를 합쳐야 할지 모르는 것이 너무 많기 때문이다. 그러니 먼저 윗부분 구조를 세울 바탕이 될
원시 연산들부터 살펴보자. 기반 시설을 좀 만들고 나면 더 큰 일을 자신 있게 해 나갈 수 있을
것이다.

@ 이 64비트 \MMIX\ 아키텍처용 프로그램은 32비트 정수 산술에 바탕을 두고 있다. 이 글을
쓰던 무렵(1998--1999년)에 크누스가 쓸 수 있던 컴퓨터가 거의 다 그런 제약을 받았기 때문이다.
기본 산술의 자세한 사항은 {\mc MMIX-ARITH}라는 별도의 프로그램 모듈에 있다. 어셈블러와
파이프라인이 없는 시뮬레이터에도 같은 루틴이 필요하기 때문이다. 타입 \KW{tetra}의 정의는,
필요하다면 거기서 찾을 수 있는 정의에 맞추어 고쳐야 한다.
@^system dependencies@>

보충: \.{mmixsim}에서처럼 옥타바이트는 64비트 부호 없는 정수이고, 정의는 \.{mmixarith}의 것을
쓴다.

@<타입 정의@>=
type (
	Tetra = mmixarith.Tetra // 부호 없는 32비트 정수
	Octa  = mmixarith.Octa  // 두 테트라바이트가 모여 옥타바이트를 이룬다
)

@ 원본의 |print_octa|는 윗 테트라가 0이 아니면 |"%x%08x"|로, 0이면 |"%x"|로 찍었다.
64비트 수를 |"%x"|로 찍는 것과 같다.

@<함수들@>=
func (mx *machine) printOcta(o Octa) {
	mx.printf("%x", o)
}

@ {\mc MMIX-ARITH}의 서브루틴 대부분은 옥타바이트 둘의 함수로서 옥타바이트 하나를
돌려준다. 이를테면 |oplus(y,z)|는 옥타바이트 |y|와~|z|의 합을 돌려준다. 곱셈은 곱의 윗부분을
전역 변수~|aux|로 돌려주고, 나눗셈은 나머지를 |aux|로 돌려준다.

보충: 옮긴 \.{mmixarith}에는 전역 변수가 없다. 곱의 윗부분과 나머지, 넘침, 예외 비트는
반환값으로 돌아오고, 반올림 방식은 매개변수로 넘긴다. 원본에서 전역 변수 |cur_round|였던
현재 반올림 방식은 여기서는 |machine|의 필드 |curRound|이고, |exceptions|는 필드
|exceptions|다. 원본의 코드가 이 둘을 서로 떨어진 곳에서 정하고 읽기 때문이다. 간단한 연산
|oplus|, |ominus|, |incr|, |oand|, |oandn|, |shift_left|는 \GO/의 연산자가 되고, |omult|와
|count_bits|는 |bits.Mul64|와 |bits.OnesCount64|가 된다. 자주 쓰는 상수에는 짧은 이름을
붙인다.

@<상수@>=
const (
	signBit = mmixarith.SignBit // 64비트 부호 비트
	negOne  = mmixarith.NegOne  // $-1$
	sign32  = 0x80000000        // 32비트 부호 비트(원본의 |sign_bit|)
)

@ @<기계의 상태@>=
curRound   mmixarith.Round // 현재 반올림 방식
exceptions int             // 부동소수점 연산이 켠 비트들

@ 원본은 여기서 32비트 가정이 맞는지 검사했다. \GO/에서는 타입이 크기를 보장하므로 이
검사를 뺐다.
@.Incorrect implementation...@>

@* 코루틴. 앞서 말했듯이 이 프로그램은 서로 영향을 주고받는 코루틴들의 체계로 볼 수 있다.
코루틴(스레드라고도 한다)은 데이터와 제어를 주고받으며 어느 정도 독립적으로 움직이는
프로세스다. 조직으로 말하면 개별 일꾼에 해당한다.

재귀적 코루틴의 온전한 힘, 곧 새 스레드가 동적으로 생겨나고 저마다 독립된 계산 스택을 가지는
힘까지는 필요 없다. 결국 우리는 고정된 하드웨어를 흉내 내는 것이기 때문이다. 다루는 코루틴의
총수는 루틴 |MMIX_config|가 한 번에 정해 버리고, 코루틴마다 정해진 양의 지역 데이터가 있다.

시뮬레이션은 한 번에 한 클럭 틱씩 진행한다. 시각~$t$에 스케줄된 코루틴들을 모두 실행한 다음에
시각~$t+1$로 넘어간다. 시각~$t$의 코루틴들은 잠들기로 할 수도 있고, 자신이나 다른 코루틴을
앞으로의 시각에 다시 스케줄할 수도 있다.

코루틴마다 진단용 기호 이름 |name|(이를테면 \.{ALU1}), 음이 아닌 단계 번호
|stage|(이를테면 파이프라인의 둘째 단계이면~2), 같은 시각에 스케줄된 다음 코루틴을 가리키는
포인터(스케줄되지 않았으면 |nil|), 잠금 변수를 가리키는 포인터(관련된 잠금이 없으면 |nil|),
그리고 처리할 데이터를 담은 제어 블록에 대한 참조가 있다.

보충: 원본은 기능 장치의 다음 파이프라인 단계를 |self+1|로 얻었다. 코루틴들이 배열 안에
나란히 있었기 때문이다. \GO/에서는 포인터 산술을 할 수 없으므로 그 코루틴을 가리키는 필드
|succ|를 둔다. 잠금 변수는 코루틴을 가리키는 포인터이므로, |lockloc|은 그런 포인터를 가리키는
포인터다.

@<타입 정의@>=
type coroutine struct {
	name    string     // 코루틴의 기호 이름
	stage   int        // 그 순위
	next    *coroutine // 그다음 것
	lockloc *lockvar   // 그것이 잠그고 있을지 모르는 것
	ctl     *control   // 그 데이터
	succ    *coroutine // 원본의 |self+1|
}

@ @<함수들@>=
func (mx *machine) printCoroutineID(c *coroutine) {
	mx.printf("%s", coroutineID(c))
}
@#
func coroutineID(c *coroutine) string {
	if c != nil {
		return fmt.Sprintf("%s:%d", c.name, c.stage)
	}
	return "??"
@.??@>
}

@ 코루틴 제어는 큐의 고리가 총지휘한다. 현재 클럭 시각을 $t$라고 할 때 시각 $t$, $t+1$, \dots,
$t+|ringSize|-1$마다 큐가 하나씩 있다.

스케줄은 모두 먼저 온 것이 먼저 가지만, |stage| 번호가 큰 코루틴이 우선한다. 이 순차 구현에서는
파이프라인의 뒤 단계들을 먼저 처리하고 싶다. 다른 차가 M~정거장에 들어오려면 먼저 있던 차가
M~정거장에서 W~정거장으로 가야 하는 것과 같은 이치다.

각 큐는 \KW{coroutine} 노드들이 |next| 필드로 이어진 원형 리스트다. 단계 번호가 |maxStage|인 머리 노드~$h$가 큐의 끝이자 처음에 온다. (정상적인 코루틴의 |stage| 번호는 모두 |maxStage|보다
작다.) 큐에 든 항목은 뒤에서 앞으로 |h.next|, |h.next.next| 등이고, |c=h|가 아니면
|c.stage<=c.next.stage|이다.

처음에는 모든 큐가 비어 있다.

@<모든 것을 초기화한다@>=
for k := range mx.ring {
	mx.ring[k].next = &mx.ring[k]
}

@ 코루틴~|c|를 양의 지연 |d<ringSize| 뒤에 스케줄하려면 |schedule(c,d,s)|를 부른다. (인자
|s|는 스케줄을 기록할 때만 쓰인다. 계산에는 영향이 없지만, 대개 |s|는 스케줄된 코루틴이 시작할
상태로 정한다.)

보충: 원본은 지연을 따지기 전에 큐의 색인을 계산하고 그 큐의 주소를 잡았다. 여기서는 지연이
범위 안인지 먼저 따진 뒤에 배열에 접근한다. 원본에서 추적 출력의 시각은 부호 없는 32비트
합을 \.{\%d}로 찍은 것이다.

@<함수들@>=
func (mx *machine) schedule(c *coroutine, d, s int) {
	tt := (mx.curTime + d) % mx.ringSize
	if d <= 0 || d >= mx.ringSize { // 상식 검사를 한다
		mx.panic(confusion("Scheduling ") + coroutineID(c) +
			fmt.Sprintf(" with delay %d", d))
	}
	p := &mx.ring[tt] // 머리 노드에서 시작한다
	for p.next.stage < c.stage {
		p = p.next
	}
	c.next = p.next
	p.next = c
	if mx.verbose&scheduleBit != 0 {
		mx.printf(" scheduling ")
		mx.printCoroutineID(c)
		mx.printf(" at time %d, state %d\n", int32(Tetra(mx.ticks)+Tetra(d)), s)
	}
}

@ @<기계의 상태@>=
ringSize int         // |MMIX_config|가 정한다. 넉넉히 커야 한다
ring     []coroutine // 스케줄 큐들의 머리 노드
curTime  int         // |ring|에서 현재 시각의 위치

@ 코루틴의 매우 중요한 필드 |ctl|은 다루고 있는 데이터를 담는데, 아래에서 설명한다. 그
구성 요소 가운데 핵심 하나는 |state| 필드로, 코루틴이 다음에 할 행동을 정하는 데 쓰인다.
새 일을 맡기려고 코루틴을 스케줄할 때는 흔히 상태~0에서 시작하게 하고 싶다.

@<함수들@>=
func (mx *machine) startup(c *coroutine, d int) {
	c.ctl.state = 0
	mx.schedule(c, d, 0)
}

@ 다음 루틴은 코루틴을 그것이 든 큐에서 뺀다. 코루틴 |c|가 |c.next=c|인 경우도 허용된다. 그런 자기
고리는 코루틴이 잠들면서 다른 코루틴이 깨워 주기를(곧 스케줄해 주기를) 기대할 때 생긴다.
잠든 코루틴은 |ctl| 필드에 중요한 데이터를 가지고 있다. 그래서 스케줄되지 않은, 곧 ``일이
없는'' 코루틴과는 아주 다르다. 일이 없는 코루틴은 |c.next=nil|이고, |ctl| 필드에 유효한
데이터가 있다고 가정하지 않는다.

@<함수들@>=
func (mx *machine) unschedule(c *coroutine) {
	if c.next != nil {
		p := c
		for p.next != c {
			p = p.next
		}
		p.next = c.next
		c.next = nil
		if mx.verbose&scheduleBit != 0 {
			mx.printf(" unscheduling ")
			mx.printCoroutineID(c)
			mx.printf("\n")
		}
	}
}

@ 어떤 시각~|t|에 줄 선 코루틴들을 모두 처리할 때가 되면, |ring[t]|라는 큐를 비우고 그
항목들을 반대 순서로(앞에서 뒤로) 잇는다. 다음 서브루틴은 {\sl The Art of Computer
Programming\/}의 연습 문제 2.2.3--7에서 다룬 잘 알려진 알고리즘을 쓴다.

@<함수들@>=
func (mx *machine) queuelist(t int) *coroutine {
	q := &mx.sentinel
	var r *coroutine
	for p := mx.ring[t].next; p != &mx.ring[t]; p = r {
		r = p.next
		p.next = q
		q = p
	}
	mx.ring[t].next = &mx.ring[t]
	mx.sentinel.next = q
	return q
}

@ @<기계의 상태@>=
sentinel coroutine // 원형 리스트의 원점에 있는 가짜 코루틴

@ 코루틴은 흔히 {\it 투기적인\/} 일을 시작한다. 쓸모 있을지도 모르는 결과를 미리 준비해 두고
싶지만, 투기적인 계산이 실제로는 필요 없을 수도 있다는 뜻이다. 그래서 코루틴은 일을 마치기
전에 중단되어야 할 수도 있다.

모든 코루틴은 갑자기 끝나더라도 중요한 데이터 구조가 온전히 남도록 짜야 한다. 특히 공유
자원에 대한 ``잠금''은, 그 잠금을 쥔 코루틴이 중단될 때 풀린 상태로 되돌려 놓아야 한다.

타입 \KW{lockvar}의 변수는 풀려 있으면 |nil|이고, 그렇지 않으면 그것을 풀 책임이 있는 코루틴을
가리킨다.

보충: 원본의 매크로 |set_lock(c,l)|과 |release_lock(c,l)|은 잠금 변수 자체를 받았다.
\GO/에서는 그 변수를 가리키는 포인터를 받는 메서드다.

@<타입 정의@>=
type lockvar = *coroutine

@ @<함수들@>=
func setLock(c *coroutine, l *lockvar) {
	*l = c
	c.lockloc = l
}
@#
func releaseLock(c *coroutine, l *lockvar) {
	*l = nil
	c.lockloc = nil
}

@ @<함수들@>=
func (mx *machine) printLocks() {
	mx.printCacheLocks(mx.ITcache)
	mx.printCacheLocks(mx.DTcache)
	mx.printCacheLocks(mx.Icache)
	mx.printCacheLocks(mx.Dcache)
	mx.printCacheLocks(mx.Scache)
	if mx.memLock != nil {
		mx.printf("mem locked by %s:%d\n", mx.memLock.name, mx.memLock.stage)
	}
	if mx.dispatchLock != nil {
		mx.printf("dispatch locked by %s:%d\n",
			mx.dispatchLock.name, mx.dispatchLock.stage)
	}
	if mx.wbufLock != nil {
		mx.printf("head of write buffer locked by %s:%d\n",
			mx.wbufLock.name, mx.wbufLock.stage)
	}
	if mx.cleanLock != nil {
		mx.printf("cleaner locked by %s:%d\n", mx.cleanLock.name, mx.cleanLock.stage)
	}
	if mx.speedLock != nil {
		mx.printf("write buffer flush locked by %s:%d\n",
			mx.speedLock.name, mx.speedLock.stage)
	}
}

@ 우리가 다루는 양 가운데 많은 것은 아직 ``진짜'' 계산의 일부로 인정받지 못한 투기적인
값이다. 사실 아직 계산되지 않았을 수도 있다.

타입 \KW{spec}은 64비트 양 |o|와 \KW{specnode}를 가리키는 포인터~|p|로 이루어진다. 값~|o|는
포인터~|p|가 |nil|일 때만 뜻이 있다. 그렇지 않으면 |p|는 더 많은 정보가 있는 곳을 가리킨다.

타입 \KW{specnode}는 64비트 양 |o|와, 이중 연결 리스트에서 그 위와 아래에 있는 다른 \KW{specnode}들에
대한 링크로 이루어진다. 비트 |known|이 더 있어서 |o|~필드가 계산되었는지 알려 준다. 또 리스트를
식별하고 정보를 더 주는 64비트 |addr| 필드가 있다. 이 \KW{specnode} 리스트는 특정한 레지스터나
주 메모리 전체와 관련된 투기적 값들을 추적한다. 이런 리스트는 나중에 자세히 다룬다.

보충: 필드 |ctl|은 옮긴이가 덧붙인 것이다. 제어 블록 안에 든 \KW{specnode}이면 그 제어 블록을
가리킨다. 원본은 이 정보를 두 가지 방식으로 얻었다. 하나는 주소 비교로, \KW{specnode}가 재정렬
버퍼의 어느 제어 블록 안에 있는지 가렸다. 다른 하나는 |go| 필드의 |up|에 제어 블록의 주소를
억지로 넣어 두는 것이었다.

@<타입 정의@>=
type spec struct {
	o Octa
	p *specnode
}
@#
type specnode struct {
	o        Octa
	known    bool
	addr     Octa
	up, down *specnode
	ctl      *control // 이 \KW{specnode}를 담은 제어 블록
}

@ 원본의 전역 변수 |zero_spec|은 \GO/에서 |spec{}|이다.

@<함수들@>=
func (mx *machine) printSpec(s spec) {
	if s.p == nil {
		mx.printOcta(s.o)
	} else {
		mx.printf(">")
		mx.printSpecnodeID(s.p.addr)
	}
}
@#
func (mx *machine) printSpecnode(s *specnode) {
	if s.known {
		mx.printOcta(s.o)
		mx.printf("!")
	} else if s.o != 0 {
		mx.printOcta(s.o)
		mx.printf("?")
	} else {
		mx.printf("?")
	}
	mx.printSpecnodeID(s.addr)
}

@ 우리 시뮬레이터에서 자동차에 해당하는 것은 \KW{control}이라는 데이터 블록이다. 이것은
\MMIX\ 명령에 관한 모든 사실을 나타낸다. 차의 앞유리에 붙은 작업 지시서라고 생각하면 된다.
차가 정비소를 지나가면서 직원 무리마다 작업 지시서를 고쳐 쓴다.

타입 \KW{control}의 레코드에는 명령이 원래 있던 위치와 그 명령의 네 바이트 OP~X~Y~Z가 들어 있다.
명령은 입력이 넷까지 있는데, |y|, |z|, |b|, |ra|라는 \KW{spec} 레코드다. 출력은 셋까지 있는데,
|x|, |a|, |rl|이라는 \KW{specnode} 레코드다. (특별한 입력~|ra|와 특별한 출력~|rl|은 대개
말하지 않는다. 이것들은 \.{MMIX}의 내부 레지스터 rA와~rL을 가리킨다.) 이를테면 \.{DIVU}
명령의 주 입력은 \$Y, \$Z, rD이고, 출력은 몫~\$X와 나머지~rR이다. \.{STO} 명령의 입력은
\$Y, \$Z, \$X다. ``출력''은 하나인데, 필드~|x.addr|에 가상 주소 $\rm \$Y+\$Z$에 해당하는
메모리 위치의 물리 주소가 들어간다.

타입 \KW{control}의 블록마다 그것을 가진 코루틴이 있으면 그 코루틴도 가리킨다. 그 밖의 여러 필드에는
이런저런 정보가 들어 있다. 이를테면 앞서 말한 |state|~필드가 있는데, 이 필드는 흔히
코루틴의 행동을 지배한다. 필드~|i|에는 내부 연산 코드 번호가 들어 있고, 대개 |state|와 함께
여러 계산 단계 가운데 하나로 갈라지는 데 쓰인다. 이를테면 |op|~필드가 \.{SUB}나 \.{SUBI}나
\.{NEG}나 \.{NEGI}이면 내부 연산 코드~|i|는 그냥 |sub|다. 이제 \KW{control} 레코드의 필드를
모두 정의하고, 설명은 나중에 한다.

실제 하드웨어 구현이라면 우리가 \KW{control} 블록에 넣는 정보가 다 필요하지는 않을 것이다.
그 정보의 일부는 대개 파이프라인 단계 사이에서 래치에 붙잡힐 것이고, 다른 일부는 이른바
``이름 바꾸기 레지스터''에 나타날 것이다.
@^rename registers@>
우리는 이름 바꾸기 레지스터를 간접적으로만 흉내 낸다. 저수준 하드웨어의 세부를 더 정확히
흉내 낸다면 그런 레지스터가 몇 개나 쓰이고 있을지를 세는 것이다. 필드 |go|는 프로그래밍의
편의상 \KW{specnode}이지만, 그 가운데 |known|과 |o| 필드만 쓴다. 여기에는 대개 다음 명령의
주소가 들어 있다.

보충: \GO/에서 |go|는 예약어이므로 이 필드의 이름은 |goLoc|이다. 필드 |idx|는 옮긴이가
덧붙인 것으로, 재정렬 버퍼 안에서 이 블록의 색인이다. 재정렬 버퍼 밖의 블록에서는 이 필드를
쓰지 않는다. 원본은 이 정보를 포인터 산술로 얻었다. 필드 |ptr_a|, |ptr_b|, |ptr_c|는 \CEE/의 |void*|였는데,
여기서는 아무 타입이나 담는 |any|다.

@<타입 정의@>=
type control struct {
	loc              Octa       // 명령이 나온 가상 주소
	op               int        // 원래의 명령 바이트들
	xx, yy, zz       byte
	y, z, b, ra      spec       // 입력
	x, a, goLoc, rl  specnode   // 출력
	owner            *coroutine // 이것을 |ctl|로 가진 코루틴
	i                int        // 내부 연산 코드
	state            int        // 내부 마음가짐
	@<제어 블록의 불 필드들@>
	arithExc         Tetra      // rA의 사건 비트를 위한 산술 예외
	hist             Tetra      // 분기 예측에 쓰는 이력 비트
	denin, denout    int        // 비정규수를 다루는 데 드는 실행 시간 벌칙
	curO, curS       Octa       // 이 명령 전의 투기적 rO와 rS
	interrupt        Tetra      // 이 명령이 인터럽트를 일으키는가?
	ptrA, ptrB, ptrC any        // 이런저런 쓰임새의 범용 포인터
	idx              int        // 재정렬 버퍼 안의 위치
}

@ 제어 블록의 불 필드들은 다음과 같다.

@<제어 블록의 불 필드들@>=
usage      bool // rU를 늘려야 하는가?
needB      bool // |b.p==nil|이 될 때까지 멈추어야 하는가?
needRA     bool // |ra.p==nil|이 될 때까지 멈추어야 하는가?
renX       bool // |x|가 이름 바꾸기 레지스터에 해당하는가?
memX       bool // |x|가 메모리 쓰기에 해당하는가?
renA       bool // |a|가 이름 바꾸기 레지스터에 해당하는가?
setL       bool // |rl|이 rL의 새 값에 해당하는가?
interim    bool // 인터럽트가 걸리면 이 명령을 다시 발행해야 하는가?
stackAlert bool // 스택 넘침의 가능성이 있는가?

@ 보충: 제어 블록의 네 \KW{specnode}가 자기 블록을 가리키게 하는 함수다. 제어 블록을 만든
뒤에 한 번 부른다.

@<함수들@>=
func (c *control) link() {
	c.x.ctl, c.a.ctl, c.goLoc.ctl, c.rl.ctl = c, c, c, c
}

@ @<함수들@>=
func (mx *machine) printControlBlock(c *control) {
	if c.loc != 0 || c.op != 0 || c.xx != 0 || c.yy != 0 || c.zz != 0 || c.owner != nil {
		mx.printOcta(c.loc)
		mx.printf(": %02x%02x%02x%02x(%s)", c.op, c.xx, c.yy, c.zz,
			internalOpName[c.i])
	}
	if c.usage {
		mx.printf("*")
	}
	if c.interim {
		mx.printf("+")
	}
	@<제어 블록의 입력을 찍는다@>
	@<제어 블록의 출력을 찍는다@>
	if c.interrupt != 0 {
		mx.printf(" int=")
		mx.printBits(int(c.interrupt))
	}
	if c.arithExc != 0 {
		mx.printf(" exc=")
		mx.printBits(int(c.arithExc << 8))
	}
	if defaultGo := c.loc + 4; c.goLoc.o != defaultGo {
		mx.printf(" ->")
		mx.printOcta(c.goLoc.o)
	}
	if mx.verbose&showPredBit != 0 {
		mx.printf(" hist=%x", c.hist)
	}
	if c.i == pop {
		mx.printf(" rS=")
		mx.printOcta(c.curS)
		mx.printf(" rO=")
		mx.printOcta(c.curO)
	}
	mx.printf(" state=%d", c.state)
}

@ @<제어 블록의 입력을 찍는다@>=
if c.y.o != 0 || c.y.p != nil {
	mx.printf(" y=")
	mx.printSpec(c.y)
}
if c.z.o != 0 || c.z.p != nil {
	mx.printf(" z=")
	mx.printSpec(c.z)
}
if c.b.o != 0 || c.b.p != nil || c.needB {
	mx.printf(" b=")
	mx.printSpec(c.b)
	if c.needB {
		mx.printf("*")
	}
}
if c.needRA {
	mx.printf(" rA=")
	mx.printSpec(c.ra)
}

@ @<제어 블록의 출력을 찍는다@>=
if c.renX || c.memX {
	mx.printf(" x=")
	mx.printSpecnode(&c.x)
} else if c.x.o != 0 {
	mx.printf(" x=")
	mx.printOcta(c.x.o)
	if c.x.known {
		mx.printf("!")
	} else {
		mx.printf("?")
	}
}
if c.renA {
	mx.printf(" a=")
	mx.printSpecnode(&c.a)
}
if c.setL {
	mx.printf(" rL=")
	mx.printSpecnode(&c.rl)
}

@* 목록. 다음은 \MMIX\ 연산 코드를 차례대로 모두 적은 (지루한) 목록이다.

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

@ @<표@>=
var opcodeName = [256]string{
	"TRAP", "FCMP", "FUN", "FEQL", "FADD", "FIX", "FSUB", "FIXU",
	"FLOT", "FLOTI", "FLOTU", "FLOTUI", "SFLOT", "SFLOTI", "SFLOTU", "SFLOTUI",
	"FMUL", "FCMPE", "FUNE", "FEQLE", "FDIV", "FSQRT", "FREM", "FINT",
	"MUL", "MULI", "MULU", "MULUI", "DIV", "DIVI", "DIVU", "DIVUI",
	"ADD", "ADDI", "ADDU", "ADDUI", "SUB", "SUBI", "SUBU", "SUBUI",
	"2ADDU", "2ADDUI", "4ADDU", "4ADDUI", "8ADDU", "8ADDUI", "16ADDU", "16ADDUI",
	"CMP", "CMPI", "CMPU", "CMPUI", "NEG", "NEGI", "NEGU", "NEGUI",
	"SL", "SLI", "SLU", "SLUI", "SR", "SRI", "SRU", "SRUI",
	"BN", "BNB", "BZ", "BZB", "BP", "BPB", "BOD", "BODB",
	"BNN", "BNNB", "BNZ", "BNZB", "BNP", "BNPB", "BEV", "BEVB",
	"PBN", "PBNB", "PBZ", "PBZB", "PBP", "PBPB", "PBOD", "PBODB",
	"PBNN", "PBNNB", "PBNZ", "PBNZB", "PBNP", "PBNPB", "PBEV", "PBEVB",
	"CSN", "CSNI", "CSZ", "CSZI", "CSP", "CSPI", "CSOD", "CSODI",
	"CSNN", "CSNNI", "CSNZ", "CSNZI", "CSNP", "CSNPI", "CSEV", "CSEVI",
	"ZSN", "ZSNI", "ZSZ", "ZSZI", "ZSP", "ZSPI", "ZSOD", "ZSODI",
	"ZSNN", "ZSNNI", "ZSNZ", "ZSNZI", "ZSNP", "ZSNPI", "ZSEV", "ZSEVI",
	"LDB", "LDBI", "LDBU", "LDBUI", "LDW", "LDWI", "LDWU", "LDWUI",
	"LDT", "LDTI", "LDTU", "LDTUI", "LDO", "LDOI", "LDOU", "LDOUI",
	"LDSF", "LDSFI", "LDHT", "LDHTI", "CSWAP", "CSWAPI", "LDUNC", "LDUNCI",
	"LDVTS", "LDVTSI", "PRELD", "PRELDI", "PREGO", "PREGOI", "GO", "GOI",
	"STB", "STBI", "STBU", "STBUI", "STW", "STWI", "STWU", "STWUI",
	"STT", "STTI", "STTU", "STTUI", "STO", "STOI", "STOU", "STOUI",
	"STSF", "STSFI", "STHT", "STHTI", "STCO", "STCOI", "STUNC", "STUNCI",
	"SYNCD", "SYNCDI", "PREST", "PRESTI", "SYNCID", "SYNCIDI", "PUSHGO", "PUSHGOI",
	"OR", "ORI", "ORN", "ORNI", "NOR", "NORI", "XOR", "XORI",
	"AND", "ANDI", "ANDN", "ANDNI", "NAND", "NANDI", "NXOR", "NXORI",
	"BDIF", "BDIFI", "WDIF", "WDIFI", "TDIF", "TDIFI", "ODIF", "ODIFI",
	"MUX", "MUXI", "SADD", "SADDI", "MOR", "MORI", "MXOR", "MXORI",
	"SETH", "SETMH", "SETML", "SETL", "INCH", "INCMH", "INCML", "INCL",
	"ORH", "ORMH", "ORML", "ORL", "ANDNH", "ANDNMH", "ANDNML", "ANDNL",
	"JMP", "JMPB", "PUSHJ", "PUSHJB", "GETA", "GETAB", "PUT", "PUTI",
	"POP", "RESUME", "SAVE", "UNSAVE", "SYNC", "SWYM", "GET", "TRIP"}

@ 그리고 다음은 내부 연산 코드를 모두 적은 (마찬가지로 지루한) 목록이다. 가장 작은 번호들,
곧 |maxPipeOp| 이하인 번호들은 |MMIX_config|로 파이프라인 지연을 마음대로 설정할 수 있는
연산에 해당한다. 가장 큰 번호들, 곧 |maxRealCommand|보다 큰 번호들은 공식 OP 코드가 없는,
안에서 만들어 내는 연산에 해당한다. 이를테면 레지스터 스택의 $\gamma$ 포인터를 옮기는 내부
연산과 페이지 테이블 항목을 계산하는 내부 연산이 있다.

보충: 원본의 내부 연산 |go|는 \GO/의 예약어와 이름이 같으므로 |goOp|이라고 부른다.

@<상수@>=
const (
	@<파이프라인 시간을 설정할 수 있는 내부 연산 코드@>
	@<다른 산술 내부 연산 코드@>
	@<메모리와 제어의 내부 연산 코드@>
)
@#
const (
	maxPipeOp      = feps
	maxRealCommand = trip
)

@ 첫 무리는 |MMIX_config|로 파이프라인 시간을 정할 수 있는 연산들이다.

@<파이프라인 시간을 설정할...@>=
mul0 = iota // 0을 곱한다
mul1        // 1--8비트짜리를 곱한다
mul2        // 9--16비트짜리를 곱한다
mul3        // 17--24비트짜리를 곱한다
mul4        // 25--32비트짜리를 곱한다
mul5        // 33--40비트짜리를 곱한다
mul6        // 41--48비트짜리를 곱한다
mul7        // 49--56비트짜리를 곱한다
mul8        // 57--64비트짜리를 곱한다
div         // \.{DIV[U][I]}
sh          // \.{S[L,R][U][I]}
mux         // \.{MUX[I]}
sadd        // \.{SADD[I]}
mor         // \.{M[X]OR[I]}
fadd        // \.{FADD}, \.{FSUB}
fmul        // \.{FMUL}
fdiv        // \.{FDIV}
fsqrt       // \.{FSQRT}
fint        // \.{FINT}
fix         // \.{FIX[U]}
flot        // \.{[S]FLOT[U][I]}
feps        // \.{FCMPE}, \.{FUNE}, \.{FEQLE}

@ 다음 무리는 나머지 산술 연산과 논리 연산이다.

@<다른 산술 내부 연산 코드@>=
fcmp        // \.{FCMP}
funeq       // \.{FUN}, \.{FEQL}
fsub        // \.{FSUB}
frem        // \.{FREM}
mul         // \.{MUL[I]}
mulu        // \.{MULU[I]}
divu        // \.{DIVU[I]}
add         // \.{ADD[I]}
addu        // \.{[2,4,8,16,]ADDU[I]}, \.{INC[M][H,L]}
sub         // \.{SUB[I]}, \.{NEG[I]}
subu        // \.{SUBU[I]}, \.{NEGU[I]}
set         // \.{SET[M][H,L]}, \.{GETA[B]}
or          // \.{OR[I]}, \.{OR[M][H,L]}
orn         // \.{ORN[I]}
nor         // \.{NOR[I]}
and         // \.{AND[I]}
andn        // \.{ANDN[I]}, \.{ANDN[M][H,L]}
nand        // \.{NAND[I]}
xor         // \.{XOR[I]}
nxor        // \.{NXOR[I]}
shlu        // \.{SLU[I]}
shru        // \.{SRU[I]}
shl         // \.{SL[I]}
shr         // \.{SR[I]}
cmp         // \.{CMP[I]}
cmpu        // \.{CMPU[I]}
bdif        // \.{BDIF[I]}
wdif        // \.{WDIF[I]}
tdif        // \.{TDIF[I]}
odif        // \.{ODIF[I]}
zset        // \.{ZS[N][N,Z,P][I]}, \.{ZSEV[I]}, \.{ZSOD[I]}
cset        // \.{CS[N][N,Z,P][I]}, \.{CSEV[I]}, \.{CSOD[I]}

@ 마지막 무리는 메모리와 제어 흐름에 관한 연산과, 안에서 만들어 내는 연산이다.

@<메모리와 제어의 내부 연산 코드@>=
get         // \.{GET}
put         // \.{PUT[I]}
ld          // \.{LD[B,W,T,O][U][I]}, \.{LDHT[I]}, \.{LDSF[I]}
ldptp       // 페이지 테이블 포인터를 적재한다
ldpte       // 페이지 테이블 항목을 적재한다
ldunc       // \.{LDUNC[I]}
ldvts       // \.{LDVTS[I]}
preld       // \.{PRELD[I]}
prest       // \.{PREST[I]}
st          // \.{STO[U][I]}, \.{STCO[I]}, \.{STUNC[I]}
syncd       // \.{SYNCD[I]}
syncid      // \.{SYNCID[I]}
pst         // \.{ST[B,W,T][U][I]}, \.{STHT[I]}
stunc       // 쓰기 버퍼 안의 \.{STUNC[I]}
cswap       // \.{CSWAP[I]}
br          // \.{B[N][N,Z,P][B]}
pbr         // \.{PB[N][N,Z,P][B]}
pushj       // \.{PUSHJ[B]}
goOp        // \.{GO[I]}
prego       // \.{PREGO[I]}
pushgo      // \.{PUSHGO[I]}
pop         // \.{POP}
resume      // \.{RESUME}
save        // \.{SAVE}
unsave      // \.{UNSAVE}
sync        // \.{SYNC}
jmp         // \.{JMP[B]}
noop        // \.{SWYM}
trap        // \.{TRAP}
trip        // \.{TRIP}
incgamma    // $\gamma$ 포인터를 늘린다
decgamma    // $\gamma$ 포인터를 줄인다
incrl       // rL과 $\beta$를 늘린다
sav         // \.{SAVE}의 중간 단계
unsav       // \.{UNSAVE}의 중간 단계
resum       // \.{RESUME}의 중간 단계

@ @<표@>=
var internalOpName = [...]string{
	"mul0", "mul1", "mul2", "mul3", "mul4", "mul5", "mul6", "mul7", "mul8",
	"div", "sh", "mux", "sadd", "mor", "fadd", "fmul", "fdiv", "fsqrt", "fint",
	"fix", "flot", "feps", "fcmp", "funeq", "fsub", "frem", "mul", "mulu",
	"divu", "add", "addu", "sub", "subu", "set", "or", "orn", "nor", "and",
	"andn", "nand", "xor", "nxor", "shlu", "shru", "shl", "shr", "cmp", "cmpu",
	"bdif", "wdif", "tdif", "odif", "zset", "cset", "get", "put", "ld", "ldptp",
	"ldpte", "ldunc", "ldvts", "preld", "prest", "st", "syncd", "syncid", "pst",
	"stunc", "cswap", "br", "pbr", "pushj", "go", "prego", "pushgo", "pop",
	"resume", "save", "unsave", "sync", "jmp", "noop", "trap", "trip",
	"incgamma", "decgamma", "incrl", "sav", "unsav", "resum"}

@ 바깥 연산 코드를 내부 연산 코드로 바꾸는 표가 필요하다.

@<표@>=
var internalOp = [256]int{
	trap, fcmp, funeq, funeq, fadd, fix, fsub, fix,
	flot, flot, flot, flot, flot, flot, flot, flot,
	fmul, feps, feps, feps, fdiv, fsqrt, frem, fint,
	mul, mul, mulu, mulu, div, div, divu, divu,
	add, add, addu, addu, sub, sub, subu, subu,
	addu, addu, addu, addu, addu, addu, addu, addu,
	cmp, cmp, cmpu, cmpu, sub, sub, subu, subu,
	shl, shl, shlu, shlu, shr, shr, shru, shru,
	br, br, br, br, br, br, br, br,
	br, br, br, br, br, br, br, br,
	pbr, pbr, pbr, pbr, pbr, pbr, pbr, pbr,
	pbr, pbr, pbr, pbr, pbr, pbr, pbr, pbr,
	cset, cset, cset, cset, cset, cset, cset, cset,
	cset, cset, cset, cset, cset, cset, cset, cset,
	zset, zset, zset, zset, zset, zset, zset, zset,
	zset, zset, zset, zset, zset, zset, zset, zset,
	ld, ld, ld, ld, ld, ld, ld, ld,
	ld, ld, ld, ld, ld, ld, ld, ld,
	ld, ld, ld, ld, cswap, cswap, ldunc, ldunc,
	ldvts, ldvts, preld, preld, prego, prego, goOp, goOp,
	pst, pst, pst, pst, pst, pst, pst, pst,
	pst, pst, pst, pst, st, st, st, st,
	pst, pst, pst, pst, st, st, st, st,
	syncd, syncd, prest, prest, syncid, syncid, pushgo, pushgo,
	or, or, orn, orn, nor, nor, xor, xor,
	and, and, andn, andn, nand, nand, nxor, nxor,
	bdif, bdif, wdif, wdif, tdif, tdif, odif, odif,
	mux, mux, sadd, sadd, mor, mor, mor, mor,
	set, set, set, set, addu, addu, addu, addu,
	or, or, or, or, andn, andn, andn, andn,
	jmp, jmp, pushj, pushj, set, set, put, put,
	pop, resume, save, unsave, sync, noop, get, trip}

@ 지루한 목록을 다루는 김에, 특수 레지스터 번호들도 모두 정의하고 진단 출력에 쓸 역표도
만들자. 이 코드들은 다음과 같이 설계되었다. 특수 레지스터 0--7은 아무 제약이 없다. 9--11은
누구도 \.{PUT}할 수 없다. 8과 12--18은 사용자가 \.{PUT}할 수 없다. 특수 레지스터 21--31에
\.{GET}을 쓰거나 특수 레지스터 8이나 15--20에 \.{PUT}을 쓰면 파이프라인 지연이 생길 수 있다.
\.{SAVE}와 \.{UNSAVE} 명령은 특수 레지스터 0--6과 23--27을 저장하고 되살리며, 이어서 rG~(19)와
rA~(21)를 여덟 바이트에 모아 저장하고 되살린다.

@<상수@>=
const (
	rA  = 21 // 산술 상태 레지스터
	rB  = 0  // 부트스트랩 레지스터(트립)
	rC  = 8  // 계속 레지스터
	rD  = 1  // 피제수 레지스터
	rE  = 2  // 엡실론 레지스터
	rF  = 22 // 실패 위치 레지스터
	rG  = 19 // 전역 문턱 레지스터
	rH  = 3  // 곱의 윗부분 레지스터
	rI  = 12 // 구간 계수기
	rJ  = 4  // 복귀 점프 레지스터
	rK  = 15 // 인터럽트 마스크 레지스터
	rL  = 20 // 지역 문턱 레지스터
	rM  = 5  // 멀티플렉스 마스크 레지스터
	rN  = 9  // 일련번호
	rO  = 10 // 레지스터 스택 오프셋
	rP  = 23 // 예측 레지스터
	rQ  = 16 // 인터럽트 요청 레지스터
	rR  = 6  // 나머지 레지스터
	rS  = 11 // 레지스터 스택 포인터
	rT  = 13 // 트랩 주소 레지스터
	rU  = 17 // 사용 계수기
	rV  = 18 // 가상 주소 변환 레지스터
	rW  = 24 // 인터럽트된 곳 레지스터(트립)
	rX  = 25 // 실행 레지스터(트립)
	rY  = 26 // Y 피연산자(트립)
	rZ  = 27 // Z 피연산자(트립)
	rBB = 7  // 부트스트랩 레지스터(트랩)
	rTT = 14 // 동적 트랩 주소 레지스터
	rWW = 28 // 인터럽트된 곳 레지스터(트랩)
	rXX = 29 // 실행 레지스터(트랩)
	rYY = 30 // Y 피연산자(트랩)
	rZZ = 31 // Z 피연산자(트랩)
)

@ @<표@>=
var specialName = [32]string{"rB", "rD", "rE", "rH", "rJ", "rM", "rR", "rBB",
	"rC", "rN", "rO", "rS", "rI", "rT", "rTT", "rK", "rQ", "rU", "rV", "rG", "rL",
	"rA", "rF", "rP", "rW", "rX", "rY", "rZ", "rWW", "rXX", "rYY", "rZZ"}

@ 다음은 트립과 트랩에 영향을 주는 비트 코드들이다. 처음 여덟은 rQ의 위쪽 절반에도
적용되고, 다음 여덟은 rA에 적용된다.

@<상수@>=
const (
	pBit       = 1 << 0  // 특권 위치에 있는 명령
	sBit       = 1 << 1  // 보안 위반
	bBit       = 1 << 2  // 규칙을 어기는 명령
	kBit       = 1 << 3  // 커널 전용 명령
	nBit       = 1 << 4  // 가상 주소 변환을 건너뜀
	pxBit      = 1 << 5  // 페이지에서 실행할 권한이 없음
	pwBit      = 1 << 6  // 페이지에 쓸 권한이 없음
	prBit      = 1 << 7  // 페이지에서 읽을 권한이 없음
	protOffset = 5       // |prBit|에서 보호 코드 자리까지의 거리
	xBit       = 1 << 8  // 부동소수점 부정확
	zBit       = 1 << 9  // 부동소수점 0으로 나눔
	uBit       = 1 << 10 // 부동소수점 아래넘침
	oBit       = 1 << 11 // 부동소수점 넘침
	iBit       = 1 << 12 // 부동소수점 잘못된 연산
	wBit       = 1 << 13 // 부동소수점에서 고정소수점으로 바꿀 때 넘침
	vBit       = 1 << 14 // 정수 넘침
	dBit       = 1 << 15 // 정수 나눗셈 검사
	hBit       = 1 << 16 // 트립 처리기 비트
	fBit       = 1 << 17 // 강제 트랩 비트
	eBit       = 1 << 18 // 외부(동적) 트랩 비트
)

@ @<표@>=
var bitCodeMap = "EFHDVWIOUZXrwxnkbsp"

@ @<함수들@>=
func (mx *machine) printBits(x int) {
	for j, b := 0, eBit; x&(b+b-1) != 0 && b != 0; j, b = j+1, b>>1 {
		if x&b != 0 {
			mx.printf("%c", bitCodeMap[j])
		}
	}
}

@ rQ의 아래쪽 절반에는 우선순위가 가장 높은 외부 인터럽트들이 들어 있다. 그 대부분은 구현에
따라 다르지만, 몇 가지는 일반적으로 정의되어 있다.

@<상수@>=
const (
	powerFailure      = 1 << 0 // 침착하고 재빨리 끄려고 한다
	parityError       = 1 << 1 // 파일 시스템을 지키려고 한다
	nonexistentMemory = 1 << 2 // 쓸 수 없는 메모리 주소
	rebootSignal      = 1 << 4 // 처음부터 다시 할 때다
	intervalTimeout   = 1 << 6 // 타이머 레지스터 rI가 0이 되었다
	stackOverflow     = 1 << 7 // rC 페이지에 데이터를 저장했다
)

@* 동적 투기.
기본적인 저수준 구조를 이해했으니, 이제 더 큰 그림을 볼 준비가 되었다.

이 시뮬레이터는 1960년대에 R.~M. Tomasulo가 도입한 ``레지스터 이름 바꾸기를 곁들인 동적
스케줄링''이라는 착상에 바탕을 두고 있다[{\sl IBM Journal of Research and Development\/}
@^Tomasulo, Robert Marco@>
{\bf11} (1967), 25--33]. 더욱이 여기서는 동적 스케줄링 방법을 ``투기적 실행''으로 넓혔다.
투기적 실행은 1990년대의 여러 프로세서에 구현되었고, Hennessy와 Patterson의 {\sl Computer
Architecture\/} 제2판(1995) 4.6절에 설명되어 있다.
@^Hennessy, John LeRoy@>
@^Patterson, David Andrew@>
핵심 착상은 끝나지 않은 계산들 사이의 의존 관계를 모두 {\it 재정렬 버퍼\/}라는 큐에 기록해서
파이프라인의 내용을 추적하는 것이다. 이를테면 재정렬 버퍼의 한 항목은, 값이 아직 계산 중인 두
수를 더하는 명령에 해당할 수 있다. 그 두 수는 재정렬 버퍼의 앞쪽 자리에 공간을 받아 두었다.
덧셈은 두 피연산자가 알려지자마자 일어나지만, 합이 곧바로 목적지 레지스터에 쓰이지는 않는다.
합은 큐의 맨 앞, 곧 {\it 뜨거운 자리\/}에 이를 때까지 재정렬 버퍼에 머문다. 마침내 덧셈이
뜨거운 자리를 떠나면 그 덧셈이 {\it 확정되었다\/}고 말한다.

재정렬 버퍼의 어떤 명령들은 사실 투기로만 실행되는 것일 수도 있다. 앞선 분기 명령이 예측한
결과를 내지 않으면 실제로는 필요 없는 명령이라는 뜻이다. 실은 아직 뜨거운 자리에 오지 않은
명령은 모두 투기로 실행되는 것이라고 말할 수 있다. 바깥 인터럽트가 언제든 일어나 계산의 흐름
전체를 바꿀 수 있기 때문이다. 파이프라인을 재정렬 버퍼로 짜 두면 앞을 내다보고, 쓸모 있을
가능성이 높은 값들을 계산하느라 바쁘게 지낼 수 있다. 느린 명령이나 느린 메모리 참조가 끝나기를
기다리지 않아도 된다.

재정렬 버퍼는 사실 \KW{control} 레코드의 큐이고, 개념상으로는 시뮬레이터 안에 있는 그런
레코드들의 원의 일부를 이룬다. 이 레코드들은 배정되었거나 {\it 발행되었지만\/} 아직 확정되지
않은 모든 명령에 해당하며, 엄격한 프로그램 순서를 따른다.

투기적 실행을 이해하는 가장 좋은 방법은 아마 재정렬 버퍼가 여러 실행 단계에 있는 명령
수백 개를 담을 만큼 크다고 상상하고, 실제로 칩에 넣을 수 있는 것보다 많은 수십 개의 기능
장치를 가진 \MMIX\ 구현을 떠올려 보는 것이다.
@^thinking big@>
그러면 올바른 실행을 보장하려면 어떤 제어 구조와 검사가 필요한지 쉽게 그려 볼 수 있다. 그렇게
넓게 보지 않으면, 프로그래머나 하드웨어 설계자는 단순한 경우만 생각하고 적절한 일반성이 없는
알고리즘을 고안하기 쉽다. 그래서 어려운 일반 문제가 그 단순한 특수한 경우들보다 풀기 쉬운
것으로 드러나는, 좀 역설적인 상황이 생긴다. 일반 문제가 생각을 명료하게 하도록 강제하기
때문이다.

실행을 마쳤지만 아직 확정되지 않은 명령은, 가상의 정비소를 거쳐 나와 주인이 찾아가기를
기다리는 차와 비슷하다. 그러나 모든 비유가 그렇듯이 이 비유도 무너지는데, 자동차의 세계에는
투기적 실행이라는 개념에 자연스럽게 대응하는 것이 없다. 그 개념은 대략 이런 상황에 해당한다.
사람들이 자기 차에 새 장비가 필요하다고 믿게 되었다가, 가격표를 보고는 갑자기 마음을 바꾸어,
장비를 일부 또는 전부 설치한 뒤에라도 떼어 내라고 고집하는 것이다.

투기로 실행한 명령은 말이 안 되는 일을 할 수도 있다. 0으로 나누거나 보호된 메모리 영역을
참조할 수도 있다. 그런 이상한 일은 명령이 뜨거운 자리에 이를 때까지 치명적이라거나 심지어
예외적이라고도 여기지 않는다.

투기적 실행을 하는 컴퓨터를 설계하는 사람은 기계의 예측이 대부분 맞으리라고 믿는
낙관주의자다. 그런 컴퓨터를 믿음직하게 구현하는 사람은 모든 예측이 수포로 돌아갈 수도 있음을
아는 비관주의자다. 그러나 비관주의자도 결과가 좋게 나오는 경우들을 최적화하는 데 공을
들인다.

@ 이를테면 \.{ADD} \.{\$1,\$2,\$3}이라는 명령 하나가 보통의 상황에서 파이프라인을 지나갈 때
무슨 일이 일어나는지 생각해 보자. 이 명령을 처음 만나면 I-캐시(곧 명령 캐시)에 넣는다. 그래서
다시 수행해야 할 때는 메모리에 접근하지 않아도 된다. 이 논의에서는 간단히 I-캐시 접근이 한
클럭 사이클씩 걸린다고 가정한다. 물론 |MMIX_config|로 다른 경우도 설정할 수 있다.

흉내 내는 기계가 예로 든 \.{ADD} 명령을 시각 1000에 가져온다고 하자. 가져오기는 |stage|
번호가~0인 코루틴이 한다. 캐시 블록 하나에는 대개 명령이 8개나 16개 들어 있다. 기계의 가져오기
장치는 클럭 사이클마다 명령을 |fetchMax|개까지 가져와 가져오기 버퍼에 넣을 수 있다. 다만 버퍼에
자리가 있고 그 명령들이 모두 같은 캐시 블록에 속해야 한다.

시뮬레이터의 배정 장치는 클럭 사이클마다 명령을 |dispatchMax|개까지 발행해서 가져오기
버퍼에서 재정렬 버퍼로 옮길 수 있다. 다만 그 명령들을 처리할 기능 장치가 있고 재정렬 버퍼에
자리가 있어야 한다. \.{ADD}를 처리하는 기능 장치는 흔히 ALU(산술 논리 장치)라고 부르는데,
흉내 내는 기계에는 ALU가 여럿 있을 수 있다. 다음 조건이 모두 맞으면 \.{ADD} 명령은 시각
1001에 발행된다. ALU가 모두 자기 파이프라인의 1단계에서 멈추어 있지는 않다. 재정렬 버퍼가
차 있지 않다. 기계가 잘못 예측한 명령들의 발행을 취소하는 중이 아니다. 가져오기 버퍼에서
\.{ADD}보다 앞에 있는 명령이 |dispatchMax|개보다 적다. 앞에 있는 그 명령들을 모두 발행해도
빈 ALU가 다 쓰이지는 않는다. (사실 이 조건들은 대개 모두 맞는다.)

지역 레지스터의 수 $\rm L$이 3보다 커서 \$1, \$2, \$3이 지역 레지스터라고 가정하자. 간단히 레지스터 스택이 비어
있다고도 가정하자. 그러면 \.{ADD} 명령은 $\rm l[1]\gets l[2]+l[3]$을 해야 한다. 피연산자
l[2]와~l[3]은 시각 1001에 알려져 있지 않을 수도 있다. 이것들은 \KW{spec} 값이어서, 목적지가
l[2]와~l[3]인 앞선 명령들을 위해 재정렬 버퍼에 만든 \KW{specnode} 항목을 가리킬 수 있다.
배정기는 재정렬 버퍼에서 다음에 쓸 수 있는 제어 블록을 \.{ADD}의 정보로 채우는데, 그 |y|와~|z|
필드에는 l[2]와~l[3]에 해당하는 알맞은 \KW{spec} 값이 들어간다. 이 제어 블록의 |x|~필드는
\KW{specnode} 레코드의 이중 연결 리스트에 끼워 넣는다. 그 리스트는 l[1]과, 재정렬 버퍼에서
l[1]을 목적지로 가진 모든 명령에 해당한다. 불 값 |x.known|은 거짓이 되는데, 이 투기적 값을
아직 계산해야 한다는 뜻이다. 합 |x.o|가 계산되기 전에 발행된, l[1]을 원천으로 쓰는 뒤따르는
명령들은 |x|를 가리킨다. 이 \KW{specnode} 리스트를 이중으로 잇는 것은, \.{ADD} 명령이 끝내
확정되기 전에 취소될 수도 있기 때문이다. 그래서 l[1]의 리스트에서는 양쪽 끝에서 지우기가
일어날 수 있다.

@ 시각 1002에 \.{ADD}를 다루는 ALU는 입력 |y|와~|z|가 둘 다 알려져 있지 않으면(곧 |y.p!=nil|이거나
|z.p!=nil|이면) 멈춘다. 사실 셋째 입력인 rA가 알려져 있지 않을 때도 멈춘다. rA의 현재 투기적
값은 사건 비트를 빼고 제어 블록의 |ra|~필드에 나타나 있는데, |ra.p==nil|이어야 한다. 그런
경우에 ALU는 |y.p|나 |z.p|나 |ra.p|가 가리키는 \KW{spec} 값들이 이 클럭 사이클에 정해지는지
살펴보고, 그에 따라 자기 입력 값을 고친다.

그러나 |y|, |z|, |ra|가 시각 1002에 이미 알려져 있다고 하자. 그러면 |x.o|는 |y.o+z.o|가 되고
|x.known|은 참이 된다. 이로써 l[1]로 갈 결과를 시각~1003에 다른 명령들이 쓸 수 있다.

값 |y.o|에 |z.o|를 더할 때 넘침이 일어나지 않으면, \.{ADD}의 제어 블록에서 |interrupt|와
|arithExc| 필드는 0이 된다. 그러나 넘침이 일어나면(끔찍하게도) 두 경우가 있다. 이것은 rA의
V~허용 비트에 달려 있는데, 그 비트는 제어 블록의 필드 |b.o|에 있다. 이 비트가~0이면 제어
블록의 |arithExc| 필드에서 V~비트를 1로 만든다. 필드 |arithExc|는 \.{ADD} 명령이 마침내
확정될 때 rA에 논리합으로 들어간다. 그러나 V~허용 비트가~1이면 트립 처리기를 불러서 정상적인
흐름을 가로막아야 한다. 그런 경우에는 제어 블록의 |interrupt| 필드에 트립을 지정하고,
가져오기와 배정 장치에게 하던 일을 잊으라고 알린다. 재정렬 버퍼에서 \.{ADD} 뒤에 있는 명령은
이제 모두 발행을 취소해야 한다. 넘침 트립 처리기의 가상 시작 주소, 곧 위치~32를 서둘러
가져오기 루틴에 넘기고, 되도록 빨리 그 위치에서 명령을 가져온다. (물론 넘침과 트립 처리기는
\.{ADD} 명령이 확정될 때까지 여전히 투기적이다. 다른 예외 상황 때문에 \.{ADD} 자체가 뜨거운
자리에 이르기 전에 끝날 수도 있다. 그러나 파이프라인은 늘 가장 그럴듯한 결과를 짐작하면서
계속 앞으로 돌진한다.)

이 시뮬레이터의 확정 장치는 클럭 사이클마다 명령을 |commitMax|개까지 확정하거나 발행을
취소할 수 있다. 운이 좋으면 시각~1003에 \.{ADD} 명령 앞에 있는 명령이 |commitMax|개보다
적을 것이고, 그것들은 모두 정상적으로 끝날 것이다. 그러면 l[1]을 |x.o|로 정하고, rA의 사건
비트를 |arithExc|로 고치고, \.{ADD} 명령은 뜨거운 자리를 지나 재정렬 버퍼를 떠날 수 있다.

@<기계의 상태@>=
fetchMax, dispatchMax, peekahead, commitMax int // 한 클럭 사이클에 다룰 수 있는 명령의 한계

@ 뜨거운 자리를 차지한 명령은, 발행되었지만 아직 확정되지 않은 명령 가운데 기계의 계산에
정말로 필요하다고 보장되는 유일한 명령이다. 재정렬 버퍼의 다른 명령은 모두 투기로 실행되고
있다. 그것들이 필요한 것으로 드러나면 좋은 일이지만, 이를테면 바깥 인터럽트가 일어나면 그것들을
모두 내던지고 싶을 수도 있다.

그래서 전역 상태를 복잡하게 바꾸는 명령은 모두---이를테면 가상 주소 변환 캐시를 바꾸는
\.{LDVTS} 같은 명령은---뜨거운 자리에 이르렀을 때만 수행한다. 다행히 명령의 대다수는 충분히
단순해서, 다른 계산이 일어나는 동안 더 효율적으로 다룰 수 있다.

이 구현에서 재정렬 버퍼는 그냥 제어 레코드의 배열에 들어 있다. 배열의 첫 원소는
|reorderBot|이고 마지막 원소는 |reorderTop|이다. 변수 |hot|은 뜨거운 자리의 제어 블록을
가리키고, |hot-1|은 그 앞의 것을 가리키는 식이다. 변수 |cool|은 재정렬 버퍼에서 다음에 채울
제어 블록을 가리킨다. 두 포인터가 같으면(|hot==cool|이면) 재정렬 버퍼가 비어 있다. 그렇지 않으면 버퍼에는 제어
레코드 |hot|, |hot-1|, \dots,~|cool+1|이 들어 있다. 물론 버퍼 안에서 아래로 내려가다가
|reorderBot|을 지나면 |reorderTop|으로 돌아온다.

보충: 원본은 이 원을 포인터 산술로 돌았다. 여기서는 배열 |reorder|에 제어 블록을 두고, 블록의
|idx| 필드로 이웃을 찾는 메서드 |prevCtl|과 |nextCtl|을 쓴다.

@<기계의 상태@>=
reorder                  []control // 재정렬 버퍼가 든 원
reorderBot, reorderTop   *control  // 그 원의 가장 작은 원소와 가장 큰 원소
hot, cool                *control  // 재정렬 버퍼의 앞과 뒤
oldHot                   *control  // 사이클이 시작할 때의 |hot|
deissues                 int       // 발행을 취소해야 할 명령의 개수

@ @<함수들@>=
func (mx *machine) prevCtl(c *control) *control {
	if c == mx.reorderBot {
		return mx.reorderTop
	}
	return &mx.reorder[c.idx-1]
}
@#
func (mx *machine) nextCtl(c *control) *control {
	if c == mx.reorderTop {
		return mx.reorderBot
	}
	return &mx.reorder[c.idx+1]
}

@ @<모든 것을 초기화한다@>=
mx.hot, mx.cool = mx.reorderTop, mx.reorderTop
mx.deissues = 0

@ @<함수들@>=
func (mx *machine) printReorderBuffer() {
	mx.printf("Reorder buffer")
	if mx.hot == mx.cool {
		mx.printf(" (empty)\n")
	} else {
		if mx.deissues != 0 {
			mx.printf(" (%d to be deissued)", mx.deissues)
		}
		if mx.doingInterrupt != 0 {
			mx.printf(" (interrupt state %d)", mx.doingInterrupt)
		}
		mx.printf(":\n")
		for p := mx.hot; p != mx.cool; p = mx.prevCtl(p) {
			mx.printControlBlock(p)
			if p.owner != nil {
				mx.printf(" ")
				mx.printCoroutineID(p.owner)
			}
			mx.printf("\n")
		}
	}
	mx.printf(" %d available rename register%s, %d memory slot%s\n",
		mx.renameRegs, plural(mx.renameRegs), mx.memSlots, plural(mx.memSlots))
}
@#
func plural(n int) string {
	if n != 1 {
		return "s"
	}
	return ""
}

@ 다음은 클럭 사이클마다 일어나는 일의 개요다.

보충: 원본은 이 절을 |MMIX_run|과 |MMIX_silent|에 끼워 넣었다. 여기서는 메서드 |cycle|의
몸통이다. 원본의 두 루틴에 있던 지역 변수 |i|, |j|, |m|은 이 메서드의 지역 변수가 된다.

@<함수들@>=
func (mx *machine) cycle() {
	var i, j, m int
	@<바깥 인터럽트를 검사한다@>
	mx.dispatchCount = 0
	mx.oldHot = mx.hot   // 사이클이 시작할 때 뜨거운 자리의 위치를 기억한다
	mx.oldTail = mx.tail // 사이클이 시작할 때 가져오기 버퍼의 내용을 기억한다
	mx.suppressDispatch = mx.deissues != 0 || mx.dispatchLock != nil
	if mx.doingInterrupt != 0 {
		@<인터럽트 준비의 한 사이클을 수행한다@>
	} else {
		@<명령을 |commitMax|개까지 확정하거나 발행을 취소한다@>
	}
	@<현재 시각에 스케줄된 코루틴을 모두 실행한다@>
	if !mx.suppressDispatch {
		@<한 사이클 분량의 명령을 배정한다@>
	}
	mx.ticks++ // 그리고 박자가 넘어간다
	mx.dispatchStat[mx.dispatchCount]++
}

@ @<기계의 상태@>=
dispatchCount    int     // 이 사이클에 몇 개를 배정했는가
suppressDispatch bool    // 배정을 건너뛰어야 하는가?
doingInterrupt   int     // 인터럽트 준비가 몇 사이클 남았는가
dispatchLock     lockvar // 명령 발행을 막는 잠금
dispatchStat     []int32 // 명령을 0, 1, \dots개 배정한 것이 몇 번인가?
securityDisabled bool    // 시험을 위해 보안 검사를 생략하는가?

@ 보충: 원본의 루프 안에서 |break|는 모두 이 루프를 빠져나온다. 확정 부분에 들어 있는 다른
루프 안에서 이 루프를 빠져나와야 하는 곳이 있어서, 루프에 |commit|이라는 이름표를 붙였다.

@<명령을 |commitMax|개까지...@>=
for m = mx.commitMax; m > 0 && mx.deissues > 0; m-- {
	@<가장 차가운 명령의 발행을 취소한다@>
}
commit:
for ; m > 0; m-- {
	if mx.hot == mx.cool {
		break // 재정렬 버퍼가 비어 있다
	}
	if !mx.securityDisabled {
		@<보안 위반을 검사하고, 위반이면 |break|한다@>
	}
	if mx.hot.owner != nil {
		break // 뜨거운 자리의 명령이 끝나지 않았다
	}
	@<가장 뜨거운 명령을 확정하고, 준비가 안 되었으면 |break|한다@>
	i = mx.hot.i
	mx.hot = mx.prevCtl(mx.hot)
	if i == resum {
		break // 다시 시작한 명령이 새 rK를 보게 한다
	}
}

@* 배정 단계. 이 시뮬레이터의 부분들을 가져오기, 배정, 실행, 확정 단계의 순서로 소개하면 좋을
것이다. 명령은 결국 먼저 가져오고, 그다음 배정하고, 그다음 실행하고, 마지막으로 확정하기
때문이다. 그러나 가져오기 단계는 메모리 관리의 어려운 문제에 크게 기대는데, 그런 문제는
시뮬레이션의 더 단순한 부분들을 본 다음으로 미루는 것이 좋다. 그래서 이 프로그램의 세부로
처음 뛰어들 때는 배정 국면부터 보기로 한다. 명령들이 어떻게든 마법처럼 가져오기 버퍼에
나타났다고 가정하자.

가져오기 버퍼는 모든 코루틴의 원형 우선순위 큐나 재정렬 버퍼에 쓰는 원형 큐처럼, 원소들의
고리로 보는 것이 가장 좋은 배열 안에 산다. 원소는 \KW{fetch} 타입의 구조체로, 다섯 필드가 있다.
32비트 |inst|는 \MMIX\ 명령이다. 64비트 |loc|은 그 명령의 가상 주소다. 필드 |interrupt|는 이를테면 이 주소에 해당하는 페이지 테이블 항목의 보호 비트가 실행 접근을 허락하지 않으면 0이
아니다. 불 필드 |noted|는 배정 장치가 그 명령이 점프이거나 그럴듯한 분기인지 엿본 뒤에 참이
된다. 필드 |hist|는 최근의 분기 이력을 기록한다. (필드 |hist|의 가장 아래 비트들이 가장 최근의
분기에 해당한다.)

보충: 필드 |idx|는 옮긴이가 덧붙인 것으로, 가져오기 버퍼 안에서의 색인이다.

@<타입 정의@>=
type fetch struct {
	loc       Octa  // 명령의 가상 주소
	inst      Tetra // 명령 자체
	interrupt Tetra // 인터럽트를 일으킬지 모르는 비트 코드들
	noted     bool  // 이 명령을 엿보았는가?
	hist      Tetra // 엿보았다면, 그때의 |peekHist|
	idx       int   // 가져오기 버퍼 안의 위치
}

@ 가져오기 버퍼에서 가장 오래된 항목과 가장 젊은 항목은 |head|와 |tail|이 가리킨다. 재정렬
버퍼에서 가장 오래된 항목과 가장 젊은 항목을 |hot|과 |cool|이라고 부르는 것과 같다. 가져오기
코루틴은 배정기가 흉내 내는 동작과 나란히 |tail| 자리에 항목을 보탠다. 그 자리는 사이클이
시작할 때 |oldTail|에서 시작한다. 그래서 배정기는 |head|, |head-1|, \dots,~|oldTail+1|에 있는
명령만 볼 수 있다. 이 부분의 프로그램이 실행될 무렵에는 대개 좀 더 최근에 가져온 명령 몇 개가
가져오기 버퍼에 있겠지만 말이다.

@<기계의 상태@>=
fetchBuf           []fetch // 가져오기 버퍼가 든 원
fetchBot, fetchTop *fetch  // 그 원의 가장 작은 원소와 가장 큰 원소
head, tail         *fetch  // 가져오기 버퍼의 앞과 뒤
oldTail            *fetch  // 현재 사이클에 볼 수 있는 가져오기 버퍼의 뒤

@ @<함수들@>=
func (mx *machine) prevFetch(p *fetch) *fetch {
	if p == mx.fetchBot {
		return mx.fetchTop
	}
	return &mx.fetchBuf[p.idx-1]
}

@ 원본의 \.{UNKNOWN\_SPEC}은 포인터로 쓸 수 없는 값 |(specnode*)1|이었다. 여기서는 그 뜻으로만
쓰는 \KW{specnode} 필드 |unknownSpec|의 주소를 쓴다.

@<모든 것을 초기화한다@>=
mx.head, mx.tail = mx.fetchTop, mx.fetchTop
mx.instPtr.p = &mx.unknownSpec

@ @<기계의 상태@>=
unknownSpec specnode // 원본의 \.{UNKNOWN\_SPEC}이 가리키는 곳

@ 보충: 원본은 |go| 필드의 |up|에 제어 블록의 주소를 넣어 두었다가 여기서 되찾았다. 여기서는
\KW{specnode}의 |ctl| 필드가 그 제어 블록이다.

@<함수들@>=
func (mx *machine) printFetchBuffer() {
	mx.printf("Fetch buffer")
	if mx.head == mx.tail {
		mx.printf(" (empty)\n")
	} else {
		if mx.resuming != 0 {
			mx.printf(" (resumption state %d)", mx.resuming)
		}
		mx.printf(":\n")
		for p := mx.head; p != mx.tail; p = mx.prevFetch(p) {
			mx.printOcta(p.loc)
			mx.printf(": %08x(%s)", p.inst, opcodeName[p.inst>>24])
			if p.interrupt != 0 {
				mx.printBits(int(p.interrupt))
			}
			if p.noted {
				mx.printf("*")
			}
			mx.printf("\n")
		}
	}
	mx.printf("Instruction pointer is ")
	if mx.instPtr.p == nil {
		mx.printOcta(mx.instPtr.o)
	} else {
		mx.printf("waiting for ")
		if mx.instPtr.p == &mx.unknownSpec {
			mx.printf("dispatch")
		} else if mx.instPtr.p.addr>>32 == 0xffffffff {
			mx.printCoroutineID(mx.instPtr.p.ctl.owner)
		} else {
			mx.printSpecnodeID(mx.instPtr.p.addr)
		}
	}
	mx.printf("\n")
}

@ 배정 과정을 이해하는 가장 좋은 방법은 이번에도 ``크게 생각하는'' 것이다. 거대한 가져오기
버퍼와, 한 사이클에 명령 수십 개를 발행할 수 있는 잠재 능력을 상상해 보라. 실제 수는 대개
@^thinking big@>
꽤 작지만 말이다.

가져오기 버퍼가 |dispatchMax|개의 명령을 배정한 뒤에도 비어 있지 않으면, 배정기는 명령을
|peekahead|개까지 더 보면서 그것이 점프나 제어 흐름을 바꾸는 다른 명령인지 살핀다. 실제 기계라면
이 일의 많은 부분이 나란히 일어나겠지만, 우리 시뮬레이터는 차례로 일한다.

다음 프로그램에서 |trueHead|는 명령이 실제로 배정될 때의 가져오기 버퍼 머리를 기록하고,
|head|는 지금 살펴보고 있는 (어쩌면 앞날을 엿보고 있는) 자리를 가리킨다.

현재 클럭 사이클이 시작할 때 가져오기 버퍼가 비어 있으면, ``배정 우회로''가 있어서 이
사이클에 가져오기 버퍼에 들어오는 첫 명령을 배정기가 발행할 수 있다. 그렇지 않으면 배정기는
앞서 가져온 명령들로 제한된다.

@<한 사이클 분량의 명령을 배정한다@>=
trueHead := mx.head
if mx.head == mx.oldTail && mx.head != mx.tail {
	mx.oldTail = mx.prevFetch(mx.head)
}
mx.peekHist = mx.coolHist
for j = 0; j < mx.dispatchMax+mx.peekahead; j++ {
	@<|head| 명령을 보고, |j<dispatchMax|이면 배정해 본다@>
}
mx.head = trueHead

@ 보충: 원본은 발행할 수 없을 때 |goto stall|로 이 절의 끝으로 뛰었다. 여기서는 발행하는
부분을 한 번만 도는 루프로 감싸고 |stall|이라는 이름표를 붙인다. 그러면 |break stall|이
원본의 |goto stall|이다. 루프를 끝까지 돌면 |stalled|가 거짓이 된다. 원본에서 |cool|은
전역 변수였는데, 이 반복 동안은 바뀌지 않으므로 지역 변수로 잡아 둔다.

@<|head| 명령을 보고...@>=
if mx.head == mx.oldTail {
	break // 가져오기 버퍼가 비어 있다
}
newHead := mx.prevFetch(mx.head)
op := int(mx.head.inst >> 24)
yz := int(mx.head.inst & 0xffff)
var f int
freezeDispatch := false
var u *funcUnit
cool := mx.cool
@<|head| 명령을 해독하고, 제어가 바뀌는지 엿본다@>
if j >= mx.dispatchMax || mx.dispatchLock != nil || mx.nullifying {
	mx.head = newHead
	continue // 배정할 수는 없지만, 앞을 엿볼 수는 있다
}
@<|cool| 블록에 |head| 명령을 발행해 본다@>

@ @<|head| 명령을 해독하고...@>=
@<플래그 |f|와 내부 연산 코드 |i|를 정한다@>
@<|cool| 블록에 기본 필드를 넣는다@>
if f&relAddrBit != 0 {
	@<상대 주소를 절대 주소로 바꾼다@>
}
if mx.head.noted {
	mx.peekHist = mx.head.hist
} else {
	@<이 명령에서 제어가 바뀌면 가져오기의 방향을 바꾼다@>
}

@ @<|cool| 블록에 |head| 명령을 발행해 본다@>=
mx.newCool = mx.prevCtl(cool)
stalled := true
stall:
for once := true; once; once = false {
	@<|cool| 블록에 명령을 배정해 본다. 할 수 없으면 |break stall|한다@>
	@<쓸 수 있는 기능 장치를 배정한다. 없으면 |break stall|한다@>
	@<이름 바꾸기 레지스터와 메모리 자리가 넉넉한지 보고, 모자라면 |break stall|한다@>
	if op&0xe0 == 0x40 {
		@<분기 예측의 결과를 기록한다@>
	}
	@<|cool| 명령을 발행한다@>
	stalled = false
}
if stalled {
	@<|cool| 블록에 너무 일찍 정한 데이터 구조를 되돌리고 |break|한다@>
}
mx.cool = mx.newCool
mx.coolO, mx.coolS = mx.newO, mx.newS
mx.coolHist = mx.peekHist

@ 명령은 그것을 처리할 기능 장치가 있을 때만 배정할 수 있다. 기능 장치는 \MMIX\ 연산
코드의 부분집합을 지정하는 256비트 벡터와, 파이프라인 단계를 맡는 코루틴들의 배열로 이루어진다.
배열에는 코루틴이 $k$개 있는데, $k$는 그 장치가 지원하는 연산 코드들이 필요로 하는 단계 수의
최댓값이다.

보충: \GO/에서 |func|는 예약어이므로 이 타입의 이름은 \KW{funcUnit}이다. 원본의 |co|는 $k$개의
코루틴 가운데 첫째를 가리키는 포인터였는데, 여기서는 그 배열 자체다.

@<타입 정의@>=
type funcUnit struct {
	name string      // 기호 이름
	ops  [8]Tetra    // 지원하는 연산 코드의 큰 쪽 먼저 비트맵
	k    int         // 파이프라인 단계의 수
	co   []coroutine // 차례로 늘어선 코루틴 $k$개
}

@ @<기계의 상태@>=
funit      []funcUnit // 기능 장치들의 배열
funitCount int        // 기능 장치의 개수

@ 지원하는 연산 코드를 모두 모은 256비트 벡터가 있으면 편리하다. 어떤 연산 코드가 지원되지
않을 때는 많은 특별한 동작을 꺼야 하기 때문이다.

@<기계의 상태@>=
newCool  *control  // |cool| 다음의 재정렬 버퍼 자리
resuming int       // 중단된 명령을 다시 시작하고 있으면 0이 아니다
support  [8]Tetra  // 지원하는 모든 연산 코드의 큰 쪽 먼저 비트맵

@ @<모든 것을 초기화한다@>=
for k := 0; k <= mx.funitCount; k++ {
	for i = 0; i < 8; i++ {
		mx.support[i] |= mx.funit[k].ops[i]
	}
}

@ @<플래그 |f|와...@>=
if mx.support[op>>5]&(sign32>>(op&31)) == 0 {
	// 아이고, 이 연산 코드는 어떤 기능 장치도 지원하지 않는다
	f, i = int(flags[TRAP]), trap
} else {
	f, i = int(flags[op]), internalOp[op]
}
if i == trip && mx.head.loc&signBit != 0 {
	f, i = 0, noop
}

@ @<|cool| 명령을 발행한다@>=
if cool.interim {
	cool.usage = false
	if cool.op == SAVE {
		@<\.{SAVE}의 다음 단계를 준비한다@>
	} else if cool.op == UNSAVE {
		@<\.{UNSAVE}의 다음 단계를 준비한다@>
	} else if cool.i == preld || cool.i == prest {
		@<\.{PRELD}나 \.{PREST}의 다음 단계를 준비한다@>
	} else if cool.i == prego {
		@<\.{PREGO}의 다음 단계를 준비한다@>
	}
} else if cool.i <= maxRealCommand {
	if flags[cool.op]&ctlChangeBit != 0 || cool.i == pbr {
		if mx.instPtr.p == nil && mx.instPtr.o&signBit != 0 && cool.loc&signBit == 0 &&
			cool.i != trap {
			cool.interrupt |= pBit // 음이 아닌 곳에서 음인 곳으로 점프한다
		}
	}
	trueHead, mx.head = newHead, newHead // 가져오기 버퍼에서 명령을 지운다
	mx.resuming = 0
}
if freezeDispatch {
	setLock(&u.co[0], &mx.dispatchLock)
}
cool.owner = &u.co[0]
u.co[0].ctl = cool
mx.startup(&u.co[0], 1) // 새 명령의 실행을 스케줄한다
if mx.verbose&issueBit != 0 {
	mx.printf("Issuing ")
	mx.printControlBlock(cool)
	mx.printf(" ")
	mx.printCoroutineID(&u.co[0])
	mx.printf("\n")
}
mx.dispatchCount++

@ 가능하면 |op|를 지원하면서 완전히 비어 있는 첫 기능 장치를 배정한다. 그런 장치가 없으면
|op|를 지원하면서 1단계가 비어 있는 첫 기능 장치를 배정한다.

보충: 원본은 이 일을 |goto unit_found|와 |goto unit_busy|로 했다. 원본은 장치의 단계들을 도는
데 내부 연산 코드를 담은 변수 |i|를 썼다. 그 뒤로는 |i|를 다시 읽지 않으므로 여기서는 따로
변수를 쓴다.

@<쓸 수 있는 기능 장치를...@>=
{
	t, b := op>>5, Tetra(sign32)>>(op&31)
	found := false
	if cool.i == trap && op != TRAP { // 연산 코드를 에뮬레이트해야 한다
		u = &mx.funit[mx.funitCount] // 이 장치는 \.{TRIP}과 \.{TRAP}만 지원한다
		found = true
	}
units:
	for k := 0; !found && k <= mx.funitCount; k++ {
		u = &mx.funit[k]
		if u.ops[t]&b != 0 {
			for s := 0; s < u.k; s++ {
				if u.co[s].next != nil {
					continue units
				}
			}
			found = true
		}
	}
	for k := 0; !found && k < mx.funitCount; k++ {
		u = &mx.funit[k]
		if u.ops[t]&b != 0 && u.co[0].next == nil {
			found = true
		}
	}
	if !found {
		break stall // 이 |op|를 다루는 장치가 모두 바쁘다
	}
}

@ 표 |flags|는 연산 코드마다 특별한 성질을 이진수로 기록한다. \Hex{1}은 Z가 즉시값이라는 뜻,
\Hex{2}는 rZ가 원천 피연산자라는 뜻, \Hex{4}는 Y가 즉시값이라는 뜻, \Hex{8}은 rY가 원천
피연산자라는 뜻, \Hex{10}은 rX가 원천 피연산자라는 뜻, \Hex{20}은 rX가 목적지라는 뜻,
\Hex{40}은 YZ가 상대 주소의 일부라는 뜻, \Hex{80}은 이 지점에서 제어가 바뀐다는 뜻이다.

@<상수@>=
const (
	xIsDestBit   = 0x20
	relAddrBit   = 0x40
	ctlChangeBit = 0x80
)

@ @<표@>=
var flags = [256]byte{
	0x8a, 0x2a, 0x2a, 0x2a, 0x2a, 0x26, 0x2a, 0x26, // \.{TRAP}, \dots
	0x26, 0x25, 0x26, 0x25, 0x26, 0x25, 0x26, 0x25, // \.{FLOT}, \dots
	0x2a, 0x2a, 0x2a, 0x2a, 0x2a, 0x26, 0x2a, 0x26, // \.{FMUL}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{MUL}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{ADD}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{2ADDU}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x26, 0x25, 0x26, 0x25, // \.{CMP}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{SL}, \dots
	0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, // \.{BN}, \dots
	0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, // \.{BNN}, \dots
	0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, // \.{PBN}, \dots
	0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, // \.{PBNN}, \dots
	0x3a, 0x39, 0x3a, 0x39, 0x3a, 0x39, 0x3a, 0x39, // \.{CSN}, \dots
	0x3a, 0x39, 0x3a, 0x39, 0x3a, 0x39, 0x3a, 0x39, // \.{CSNN}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{ZSN}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{ZSNN}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{LDB}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{LDT}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x3a, 0x39, 0x2a, 0x29, // \.{LDSF}, \dots
	0x2a, 0x29, 0x0a, 0x09, 0x0a, 0x09, 0xaa, 0xa9, // \.{LDVTS}, \dots
	0x1a, 0x19, 0x1a, 0x19, 0x1a, 0x19, 0x1a, 0x19, // \.{STB}, \dots
	0x1a, 0x19, 0x1a, 0x19, 0x1a, 0x19, 0x1a, 0x19, // \.{STT}, \dots
	0x1a, 0x19, 0x1a, 0x19, 0x0a, 0x09, 0x1a, 0x19, // \.{STSF}, \dots
	0x0a, 0x09, 0x0a, 0x09, 0x0a, 0x09, 0xaa, 0xa9, // \.{SYNCD}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{OR}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{AND}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{BDIF}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{MUX}, \dots
	0x20, 0x20, 0x20, 0x20, 0x30, 0x30, 0x30, 0x30, // \.{SETH}, \dots
	0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, // \.{ORH}, \dots
	0xc0, 0xc0, 0xe0, 0xe0, 0x60, 0x60, 0x02, 0x01, // \.{JMP}, \dots
	0x80, 0x80, 0x00, 0x02, 0x01, 0x00, 0x20, 0x8a} // \.{POP}, \dots

@ 보충: \.{JMP}에서는 XYZ가 부호 없는 24비트이고, 다른 명령에서는 YZ가 부호 없는 16비트다.
연산 코드가 홀수이면 뒤로 가는 것이므로 $2^{24}$나 $2^{16}$을 뺀다.

@<상대 주소를 절대...@>=
if i == jmp {
	yz = int(mx.head.inst & 0xffffff)
}
if op&1 != 0 {
	if i == jmp {
		yz -= 0x1000000
	} else {
		yz -= 0x10000
	}
}
cool.y = spec{o: mx.head.loc + 4}
cool.z = spec{o: mx.head.loc + Octa(yz<<2)}

@ 다음에 가져올 명령의 위치는 |instPtr|이라는 \KW{spec} 변수에 있다. rJ의 투기적 값이 알려져
있는 흔한 경우에는 \.{POP} 명령을 조금 까다롭게 최적화한다.

@<이 명령에서 제어가 바뀌면...@>=
{
	predicted := 0
	if op&0xe0 == 0x40 {
		@<분기의 결과를 예측한다@>
	}
	mx.head.noted = true
	mx.head.hist = mx.peekHist
	if predicted != 0 || f&ctlChangeBit != 0 || (i == syncid && cool.loc&signBit == 0) {
		mx.oldTail, mx.tail = newHead, newHead // 남은 가져오기를 모두 버린다
		@<가져오기 코루틴을 다시 시작한다@>
		switch i {
		case jmp, br, pbr, pushj:
			mx.instPtr = cool.z
		case pop:
			if mx.g[rJ].up.known && j < mx.dispatchMax && mx.dispatchLock == nil &&
				!mx.nullifying {
				mx.instPtr = spec{o: mx.g[rJ].up.o + Octa(yz<<2)}
				break
			}
			fallthrough // 그렇지 않으면 |cool.goLoc|을 기다린다
		case goOp, pushgo, trap, resume, syncid:
			mx.instPtr.p = &mx.unknownSpec
		case trip:
			mx.instPtr = spec{}
		}
	}
}

@ 어느 때든 흉내 내는 기계는 두 가지 주된 상태에 있다. 하나는 확정된 명령들에 해당하는
``뜨거운 상태''이고, 다른 하나는 지금 고려하고 있는 모든 투기적 변화에 해당하는 ``차가운
상태''다. 배정기는 차가운 명령들을 다루며 그것들을 재정렬 버퍼에 넣는데, 거기서 명령들은 점점
따뜻해진다. 포인터 |hot|과 |cool| 사이의 중간 명령들은 중간 온도를 가진다.

l[101]이나 g[250] 같은 기계 레지스터는 \KW{specnode}로 나타내는데, 그 |o|~필드가 레지스터의
현재 뜨거운 값이다. 이 \KW{specnode}의 |up|과 |down| 필드가 노드 자신을 가리키면, 레지스터의
뜨거운 값과 차가운 값이 같다. 그렇지 않으면 |up|과 |down|은 중간의 투기적 값들(흔히 ``이름
바꾸기 레지스터''라고 부른다)을 나타내는 \KW{specnode} 이중 연결 리스트의 가장 차가운 끝과
가장 뜨거운 끝을 가리킨다.
@^rename registers@>
이름 바꾸기 레지스터는 이 레지스터를 목적지로 쓰는 투기적 명령들의 제어 블록 안에 든 |x|나~|a|
\KW{specnode}로 구현된다. 이 레지스터를 원천 피연산자로 쓰는 투기적 명령들은 값이 알려질 때까지
리스트에서 그다음으로 뜨거운 \KW{specnode}를 가리킨다. 이 \KW{specnode}들의 이중 연결 리스트는
입력이 제한된 덱이다. 배정기가 이 레지스터를 목적지로 하는 명령을 발행하면 차가운 끝에 노드를
넣고, 명령의 발행을 취소해야 하면 차가운 끝에서 노드를 빼고, 명령이 확정되면 뜨거운 끝에서
노드를 뺀다.

특수 레지스터 rA, rB, \dots는 전역 레지스터 g[32], g[33], \dots와 같은 배열을 차지한다.
이를테면 |rB=0|이므로 rB는 안에서 g[0]과 같다.

@<기계의 상태@>=
g                           [256]specnode // 전역 레지스터와 특수 레지스터
l                           []specnode    // 지역 레지스터의 고리
lringSize                   int           // 칩에 있는 지역 레지스터의 수(2의 거듭제곱이어야 한다)
maxRenameRegs, maxMemSlots  int           // 재정렬 버퍼의 용량
renameRegs, memSlots        int           // 지금 쓰지 않는 용량

@ 특수 레지스터 rC는 \MMIX의 원래 정의에서 시계였다. 그러나 이제 시계는 |ticks|라는 바깥
변수일 뿐이다.

@<기계의 상태@>=
ticks     Octa // 내부 시계
lringMask int  // |lringSize|를 법으로 하는 계산을 위해

@ 레지스터의 \KW{specnode} 리스트에 있는 |addr| 필드는 진단 메시지에서 그 레지스터를
식별하는 데 쓰인다. 이런 주소는 음수이고, 메모리 주소는 양수다.

모든 레지스터는 처음에 0이다. 다만 rG는 처음에 255이고, rN은 컴파일한 때를 나타내는 상수
값을 가진다. (원본에서 매크로 \.{ABSTIME}은 바깥 파일 \.{abstime.h}에 정의되어 있었다. 그
파일은 {\mc ABSTIME}이 방금 만들었어야 한다. {\mc ABSTIME}은 표준 라이브러리 함수
|time(NULL)|의 값을 계산하는 사소한 프로그램이다. 이 수는 ``{\mc UNIX} 기원'' 이래의 초
수인데, 우리는 이 수가 $2^{32}$보다 작다고 가정한다. 조심하라: 이 가정은 2106년 2월에
깨진다.)
@^system dependencies@>

보충: \.{mmixsim}에서처럼 \GO/ 판에서는 \.{abstime}이 만드는 파일 \.{abstime.go}가 상수
|ABSTIME|을 정의한다. 메타 시뮬레이터의 판 번호는 \.{mmixsim}과 조금 다르다.

@<상수@>=
const (
	version       = 1 // 우리가 지원하는 \MMIX\ 아키텍처의 판
	subversion    = 0 // 판 번호의 둘째 바이트
	subsubversion = 0 // 판 번호를 더 한정하는 번호
)

@ @<모든 것을 초기화한다@>=
mx.renameRegs = mx.maxRenameRegs
mx.memSlots = mx.maxMemSlots
mx.lringMask = mx.lringSize - 1
for j = 0; j < 256; j++ {
	mx.g[j].addr = sign32<<32 | Octa(j)
	mx.g[j].known = true
	mx.g[j].up, mx.g[j].down = &mx.g[j], &mx.g[j]
}
mx.g[rG].o = 255
mx.g[rN].o = (version<<24+subversion<<16+subsubversion<<8)<<32 |
	Octa(Tetra(ABSTIME)) // 위의 설명과 경고를 보라
for j = 0; j < mx.lringSize; j++ {
	mx.l[j].addr = sign32<<32 | Octa(256+j)
	mx.l[j].known = true
	mx.l[j].up, mx.l[j].down = &mx.l[j], &mx.l[j]
}

@ @<함수들@>=
func (mx *machine) printSpecnodeID(a Octa) {
	if a>>32 == sign32 {
		switch l := Tetra(a); {
		case l < 32:
			mx.printf("%s", specialName[l])
		case l < 256:
			mx.printf("g[%d]", l)
		default:
			mx.printf("l[%d]", l-256)
		}
	} else if a>>32 != 0xffffffff {
		mx.printf("m[")
		mx.printOcta(a)
		mx.printf("]")
	}
}

@ 서브루틴 |specval|은 주어진 지역 레지스터나 전역 레지스터의 지금 가장 차가운 값에 해당하는
\KW{spec}을 만든다.

보충: 원본은 값을 모를 때 |o| 필드를 초기화하지 않은 채 돌려주었다. 여기서는 0이다. 그런
\KW{spec}은 |p|가 |nil|이 될 때까지 |o|를 보지 않는다.

@<함수들@>=
func (mx *machine) specval(r *specnode) spec {
	if r.up.known {
		return spec{o: r.up.o}
	}
	return spec{p: r.up}
}

@ 서브루틴 |specInstall|은 주어진 이중 연결 리스트의 차가운 끝에 새 투기적 값을 넣는다.

@<함수들@>=
func (mx *machine) specInstall(r, t *specnode) { // |t|를 리스트 |r|에 넣는다
	t.up = r.up
	t.up.down = t
	r.up = t
	t.down = r
	t.addr = r.addr
}

@ 반대로 |specRem|은 그런 값을 뺀다.

@<함수들@>=
func specRem(t *specnode) { // |t|를 그 리스트에서 뺀다
	u, d := t.up, t.down
	u.down = d
	d.up = u
}

@ 어떤 특수 레지스터들은 \MMIX의 동작에 너무나 중요해서, 명령마다 원천 레지스터와 목적지
레지스터로 다루지 않고 재정렬 버퍼의 제어 블록마다 함께 싣고 다닌다. 이를테면 레지스터 스택
포인터 rO와~rS가 그렇게 다루어진다. rO와~rS의 보통 \KW{specnode}인 |g[rO]|와~|g[rS]|는 실제로
쓰이지 않는다. 차가운 값은 |coolO|와 |coolS|라고 부른다. (사실 |coolO|와 |coolS|는 레지스터
값을~8로 나눈 것에 해당한다. rO와~rS는 늘 8의 배수이기 때문이다.)

산술 상태 레지스터 rA도 특별하게 다룬다. 그 사건 비트는 ``뜨거운'' 끝에서만 |arithExc| 값을
모아서 최신으로 유지한다. rA의 값을 \.{GET}하는 명령은 뜨거운 자리에서만 실행된다. rA의 다른
비트들은 트립 처리기와 부동소수점 반올림을 제어하는 데 필요한데, 보통의 방식으로 다룬다.

보충: 원본은 지역 레지스터의 색인을 |l[(cool_O.l+x)&lring_mask]|처럼 테트라의 합을 |lring_mask|로
걸러서 얻었다. 그 계산을 하는 메서드 |lr|을 둔다.

@<기계의 상태@>=
coolO, coolS       Octa  // |cool| 명령 전의 rO와 rS
coolL, coolG       int   // |cool| 명령 전의 rL과 rG
coolHist, peekHist Tetra // 분기 예측을 위한 이력 비트
newO, newS         Octa  // |cool| 다음의 rO와 rS

@ @<함수들@>=
func (mx *machine) lr(t Tetra) *specnode {
	return &mx.l[int(t)&mx.lringMask]
}

@ @<|cool| 블록에 기본 필드를...@>=
cool.op, cool.i = op, i
cool.xx = byte(mx.head.inst >> 16)
cool.yy = byte(mx.head.inst >> 8)
cool.zz = byte(mx.head.inst)
cool.loc = mx.head.loc
cool.y, cool.z, cool.b, cool.ra = spec{}, spec{}, spec{}, spec{}
cool.x.o, cool.a.o, cool.rl.o = 0, 0, 0
cool.x.known, cool.x.up = false, nil
cool.a.known, cool.a.up = false, nil
cool.rl.known, cool.rl.up = true, nil
cool.needB, cool.needRA = false, false
cool.renX, cool.memX, cool.renA, cool.setL = false, false, false, false
cool.arithExc, cool.denin, cool.denout = 0, 0, 0
if mx.head.loc&signBit != 0 && mx.g[rU].o&(0x8000<<32) == 0 {
	cool.usage = false
} else {
	cool.usage = Octa(op)&(mx.g[rU].o>>48) == mx.g[rU].o>>56
}
mx.newO, cool.curO = mx.coolO, mx.coolO
mx.newS, cool.curS = mx.coolS, mx.coolS
cool.interrupt = mx.head.interrupt
cool.hist = mx.peekHist
cool.goLoc.o = cool.loc + 4
cool.goLoc.known = false
cool.goLoc.addr = cool.goLoc.addr&0xffffffff | 0xffffffff<<32
cool.interim, cool.stackAlert = false, false

@ 보충: 원본은 명령을 끼워 넣은 뒤 |goto dispatch_done|으로 특별한 경우들의 스위치를
건너뛰었다. 여기서는 그 부분을 한 번만 도는 루프로 감싸고 |dispatchDone|이라는 이름표를
붙인다. 특별한 경우들의 스위치에는 |special|이라는 이름표를 붙이는데, 원본에서 스위치를
빠져나가던 |break|가 안쪽의 스위치나 루프 안에 있는 곳에서 쓴다.

@<|cool| 블록에 명령을 배정해 본다...@>=
if mx.newCool == mx.hot {
	break stall // 재정렬 버퍼가 차 있다
}
@<|coolL|과 |coolG|가 최신인지 확인한다@>
@<|cool| 블록의 피연산자 필드를 설치한다@>
dispatchDone:
for once := true; once; once = false {
	if f&xIsDestBit != 0 {
		@<레지스터 X를 목적지로 설치한다@>
	}
special:
	switch i {
	@<명령 배정의 특별한 경우들@>
	}
}

@ \.{UNSAVE} 연산은 메모리에서 레지스터~rG를 적재하는 것으로 시작한다. 다른 레지스터 열두
개를 되살리기 전까지는 rG의 값을 정말 알 필요가 없으므로, 여기서는 그것을 까다롭게 따지지
않는다.

@<|coolL|과 |coolG|가...@>=
if !mx.g[rL].up.known {
	break stall
}
mx.coolL = int(Tetra(mx.g[rL].up.o))
if !mx.g[rG].up.known && !(op == UNSAVE && cool.xx == 1) {
	break stall
}
mx.coolG = int(Tetra(mx.g[rG].up.o))

@ @<|cool| 블록의 피연산자...@>=
if mx.resuming != 0 {
	@<중단된 연산을 다시 시작할 때의 특별한 피연산자를 넣는다@>
} else {
	if f&0x10 != 0 {
		@<레지스터 X에서 |cool.b|를 정한다@>
	}
	if thirdOperand[op] != 0 && cool.i != trap {
		@<특수 레지스터에서 |cool.b|와 |cool.ra|를 정한다@>
	}
	if f&0x1 != 0 {
		cool.z.o = Octa(cool.zz)
	} else if f&0x2 != 0 {
		@<레지스터 Z에서 |cool.z|를 정한다@>
	} else if op&0xf0 == 0xe0 {
		@<|cool.z|를 즉시 와이드로 정한다@>
	}
	if f&0x4 != 0 {
		cool.y.o = Octa(cool.yy)
	} else if f&0x8 != 0 {
		@<레지스터 Y에서 |cool.y|를 정한다@>
	}
}

@ @<레지스터 Z에서 |cool.z|를...@>=
if int(cool.zz) >= mx.coolG {
	cool.z = mx.specval(&mx.g[cool.zz])
} else if int(cool.zz) < mx.coolL {
	cool.z = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.zz)))
}

@ @<레지스터 Y에서 |cool.y|를...@>=
if int(cool.yy) >= mx.coolG {
	cool.y = mx.specval(&mx.g[cool.yy])
} else if int(cool.yy) < mx.coolL {
	cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.yy)))
}

@ @<레지스터 X에서 |cool.b|를...@>=
if int(cool.xx) >= mx.coolG {
	cool.b = mx.specval(&mx.g[cool.xx])
} else if int(cool.xx) < mx.coolL {
	cool.b = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx)))
}
if f&relAddrBit != 0 {
	cool.needB = true // |br|, |pbr|
}

@ 연산에 셋째 피연산자로 특수 레지스터가 필요하면, 그 레지스터는 |thirdOperand| 표에 적혀
있다.

@<표@>=
var thirdOperand = [256]byte{
	0, rA, 0, 0, rA, rA, rA, rA, // \.{TRAP}, \dots
	rA, rA, rA, rA, rA, rA, rA, rA, // \.{FLOT}, \dots
	rA, rE, rE, rE, rA, rA, rA, rA, // \.{FMUL}, \dots
	rA, rA, 0, 0, rA, rA, rD, rD, // \.{MUL}, \dots
	rA, rA, 0, 0, rA, rA, 0, 0, // \.{ADD}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{2ADDU}, \dots
	0, 0, 0, 0, rA, rA, 0, 0, // \.{CMP}, \dots
	rA, rA, 0, 0, 0, 0, 0, 0, // \.{SL}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{BN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{BNN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{PBN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{PBNN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{CSN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{CSNN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{ZSN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{ZSNN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{LDB}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{LDT}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{LDSF}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{LDVTS}, \dots
	rA, rA, 0, 0, rA, rA, 0, 0, // \.{STB}, \dots
	rA, rA, 0, 0, 0, 0, 0, 0, // \.{STT}, \dots
	rA, rA, 0, 0, 0, 0, 0, 0, // \.{STSF}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{SYNCD}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{OR}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{AND}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{BDIF}, \dots
	rM, rM, 0, 0, 0, 0, 0, 0, // \.{MUX}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{SETH}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{ORH}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{JMP}, \dots
	rJ, 0, 0, 0, 0, 0, 0, 255} // \.{POP}, \dots

@ \.{STB}나 \.{STSF} 같은 연산에서는 rA가 필요한데 |cool.b| 필드가 이미 쓰이고 있다. 그래서
rA가 필요할 때는 |cool.ra|를 대신 쓴다.

@<특수 레지스터에서 |cool.b|와...@>=
if to := thirdOperand[op]; to == rA || to == rE {
	cool.needRA = true
	cool.ra = mx.specval(&mx.g[rA])
}
if to := thirdOperand[op]; to != rA {
	cool.needB = true
	cool.b = mx.specval(&mx.g[to])
}

@ 보충: 원본은 연산 코드의 아래 두 비트로 네 경우를 나누었다. 값 |yz|를 $48-16(|op|\bmod4)$
비트만큼 옮기는 것과 같다.

@<|cool.z|를 즉시 와이드로...@>=
cool.z.o = Octa(yz) << (48 - 16*(op&3))
if i != set { // 레지스터 X가 Y 피연산자도 되어야 한다
	cool.y = cool.b
	cool.b = spec{}
}

@ 보충: 원본은 레지스터 X가 가장자리 레지스터일 때 |increase_L|이라는 이름표를 지나 내부
명령을 끼워 넣었는데, \.{TRAP}의 경우에서도 그 이름표로 뛰어들었다. 여기서는 그 부분을 절로
만들어 두 곳에서 쓴다.

X가 가장자리 레지스터이면 다음 절은 내부 명령을 끼워 넣고 |break dispatchDone|한다.

@<레지스터 X를 목적지로 설치한다@>=
if int(cool.xx) >= mx.coolG {
	if i != pushgo && i != pushj && i != cswap {
		cool.renX = true
		mx.specInstall(&mx.g[cool.xx], &cool.x)
	}
} else if int(cool.xx) < mx.coolL {
	if i != cswap {
		cool.renX = true
		mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)), &cool.x)
	}
} else { // |head.inst|를 발행하기 전에 L을 늘려야 한다
	@<L을 늘리는 내부 명령을 끼워 넣는다@>
}

@ @<L을 늘리는 내부 명령을...@>=
if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {
	@<$\gamma$를 나아가게 하는 명령을 끼워 넣는다@>
} else {
	@<$\beta$와 L을 나아가게 하는 명령을 끼워 넣는다@>
}

@ @<이름 바꾸기 레지스터와 메모리 자리가...@>=
if mx.renameRegs < b2i(cool.renX)+b2i(cool.renA) {
	break stall
}
if cool.memX {
	if mx.memSlots != 0 {
		mx.memSlots--
	} else {
		break stall
	}
}
mx.renameRegs -= b2i(cool.renX) + b2i(cool.renA)

@ 보충: 원본은 불 값을 그대로 정수로 더했다.

@<함수들@>=
func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

@ 내부 명령 |incrl|은 지역 레지스터의 고리에서 $\beta\ne\gamma$임을 알 때 $\beta$와~rL을
1씩 나아가게 한다.

@<$\beta$와 L을 나아가게...@>=
cool.i = incrl
mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(mx.coolL)), &cool.x)
cool.needB, cool.needRA = false, false
cool.y, cool.z = spec{}, spec{}
cool.x.known = true // |cool.x.o=0|
mx.specInstall(&mx.g[rL], &cool.rl)
cool.rl.o = Octa(Tetra(mx.coolL + 1))
cool.renX, cool.setL = true, true
op = SETH // 이 명령은 가장 단순한 장치가 다룬다
cool.interim = true
break dispatchDone

@ 내부 명령 |incgamma|는 지역 레지스터 고리의 옥타바이트 하나를 가상 메모리 위치
|coolS<<3|에 저장해서 $\gamma$와 rS를 나아가게 한다.

@<$\gamma$를 나아가게 하는...@>=
cool.needB, cool.needRA = false, false
cool.i = incgamma
mx.newS = mx.coolS + 1
cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
cool.y = spec{o: mx.coolS << 3}
cool.z = spec{}
cool.memX = true
mx.specInstall(&mx.mem, &cool.x)
op = STOU // 이 명령은 적재/저장 장치가 다루어야 한다
cool.interim = true
cool.stackAlert = cool.y.o&signBit == 0
break dispatchDone

@ 내부 명령 |decgamma|는 가상 메모리 위치 |(coolS-1)<<3|의 옥타바이트를 지역 레지스터
고리에 적재해서 $\gamma$와 rS를 줄인다. 포인터 $\beta$도 줄여야 할 수 있다(rL을 줄여서).

@<$\gamma$를 줄이는 명령을 끼워 넣는다@>=
if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
	// $\gamma$가 $\beta$를 지나가지 못하게 한다
	if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
		cool.i = or // 주된 결과를 아래로 옮겨서 보존한다
		mx.head.inst -= 0x10000 // 가져오기 버퍼에 있는 \.{POP}의 X 필드를 줄인다
		op = OR
		cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
		mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
	} else { // rL을 1 줄인다
		mx.specInstall(&mx.g[rL], &cool.rl)
		cool.rl.o = Octa(Tetra(mx.coolL - 1))
		cool.setL = true
	}
}
if cool.i != or {
	cool.i = decgamma
	mx.newS = mx.coolS - 1
	cool.y = spec{o: mx.newS << 3}
	mx.specInstall(mx.lr(Tetra(mx.newS)), &cool.x)
	op = LDOU // 이 명령은 적재/저장 장치가 다루어야 한다
	cool.ptrA = mx.mem.up
}
cool.z, cool.b = spec{}, spec{}
cool.needB = false
cool.renX, cool.interim = true, true
break dispatchDone

@ 메모리에 저장하려면 지역 레지스터와 전역 레지스터에 쓰는 것과 같은 \KW{specnode}의 이중
연결 데이터 리스트가 필요하다. 이 경우에 리스트의 머리는 |mem|이라고 부르고, |addr| 필드는
메모리의 물리 주소다.

@<기계의 상태@>=
mem specnode

@ 메모리 \KW{specnode}의 |addr| 필드는 물리 주소를 계산할 때까지 모두 1이다.

@<모든 것을 초기화한다@>=
mx.mem.addr = negOne
mx.mem.up, mx.mem.down = &mx.mem, &mx.mem

@ \.{CSWAP} 연산은 \$X를 둘째 출력으로 가지는 부분 저장으로 다룬다. 부분 저장(|pst|) 명령은
옥타바이트를 쓰기 전에 메모리에서 읽는다.

@<명령 배정의 특별한 경우들@>=
case cswap:
	cool.renA = true
	if int(cool.xx) >= mx.coolG {
		mx.specInstall(&mx.g[cool.xx], &cool.a)
	} else {
		mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)), &cool.a)
	}
	cool.i = pst
	fallthrough
case st:
	if op&0xfe == STCO {
		cool.b.o = cool.b.o&^0xffffffff | Octa(cool.xx)
	}
	fallthrough
case pst:
	cool.memX = true
	mx.specInstall(&mx.mem, &cool.x)
case ld, ldunc:
	cool.ptrA = mx.mem.up

@ 특수 레지스터 8이나 15--20(곧 rC, rK, rQ, rU, rV, rG, rL)에 새 데이터를 \.{PUT}하면 많은
것에 영향을 줄 수 있다. 그래서 그런 \.{PUT}이 확정될 때까지 뒤따르는 명령의 발행을 멈춘다.
더욱이 나중에 보겠지만, 그런 과격한 \.{PUT}은 뜨거운 자리에 이를 때까지 실행을 미룬다.

보충: 원본은 불법 명령과 특권 명령을 |illegal_inst|, |privileged_inst|, |noop_inst|라는 이름표로
모았다. 여기서는 그 꼬리를 작은 절 둘로 만들어 필요한 곳에 끼워 넣는다.

@<명령 배정의 특별한 경우들@>=
case put:
	if cool.yy != 0 || cool.xx >= 32 {
		@<|cool|을 불법 명령으로 만든다@>
	}
	if cool.xx >= 8 {
		if cool.xx <= 11 && cool.xx != 8 {
			@<|cool|을 불법 명령으로...@>
		}
		if cool.xx <= 18 && cool.loc&signBit == 0 {
			@<|cool|을 특권 명령으로 만든다@>
		}
	}
	if cool.xx == 8 || (cool.xx >= 15 && cool.xx <= 20) {
		freezeDispatch = true
	}
	cool.renX = true
	mx.specInstall(&mx.g[cool.xx], &cool.x)
case get:
	if cool.yy != 0 || cool.zz >= 32 {
		@<|cool|을 불법 명령으로...@>
	}
	if cool.zz == rO {
		cool.z.o = mx.coolO << 3
	} else if cool.zz == rS {
		cool.z.o = mx.coolS << 3
	} else {
		cool.z = mx.specval(&mx.g[cool.zz])
	}
case ldvts:
	if cool.loc&signBit != 0 {
		break
	}
	@<|cool|을 특권 명령으로...@>

@ @<|cool|을 불법 명령으로...@>=
cool.interrupt |= bBit
cool.i = noop
break special

@ @<|cool|을 특권 명령으로...@>=
cool.interrupt |= kBit
cool.i = noop
break special

@ 레지스터 번호가 $\rm X\ge G$인 \.{PUSHGO} 명령은 $\rm L=G$이더라도 L을 잠깐 1 늘린다. 그러나 \.{PUSHGO}가
끝나기 전에 L의 값을 줄이므로, 실제로 G를 넘지는 않는다. 더욱이 |incrl| 명령을 끼워 넣을
필요도 없다.

@<명령 배정의 특별한 경우들@>=
case pushgo:
	mx.instPtr.p = &cool.goLoc
	fallthrough
case pushj:
	x := int(cool.xx)
	if x >= mx.coolG {
		if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {
			@<$\gamma$를 나아가게 하는...@>
		}
		x = mx.coolL
		mx.coolL++
		cool.renX = true
		mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(x)), &cool.x)
	}
	cool.x.known, cool.x.o = true, Octa(x)
	cool.renA = true
	mx.specInstall(&mx.g[rJ], &cool.a)
	cool.a.known, cool.a.o = true, cool.loc+4
	cool.setL = true
	mx.specInstall(&mx.g[rL], &cool.rl)
	cool.rl.o = Octa(Tetra(mx.coolL - x - 1))
	mx.newO = mx.coolO + Octa(x+1)
case syncid:
	if cool.loc&signBit != 0 {
		break
	}
	fallthrough
case goOp:
	mx.instPtr.p = &cool.goLoc

@ \.{POP} 명령을 배정할 때는 레지스터 스택에서 가장 위에 있는 ``숨은'' 원소를 알아야 한다. 이
원소는 $\gamma=\alpha$가 아니면 대개 지역 레지스터 고리 안에 있다.

그것을 알게 되면 그 가장 아래 바이트를 $x$라고 하자. rO를 $x+1$만큼 줄일 것이므로, $\rm rS\le
rO$라는 조건을 지키려면 $\gamma$를 거듭 줄여야 할 수도 있다.

보충: 원본은 \.{UNSAVE}의 마지막 단계에서 |goto pop_unsave|로 이 경우의 한가운데로 뛰어들었다.
여기서는 그 뒷부분을 절로 만들어 두 곳에서 쓴다.

@<명령 배정의 특별한 경우들@>=
case pop:
	if cool.xx != 0 && mx.coolL >= int(cool.xx) {
		cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
	}
	@<레지스터 스택을 꺼내거나 되살린다@>

@ @<레지스터 스택을 꺼내거나...@>=
if Tetra(mx.coolS) == Tetra(mx.coolO) {
	@<$\gamma$를 줄이는 명령을...@>
}
{
	var x Tetra
	if p := mx.lr(Tetra(mx.coolO) - 1).up; p.known {
		x = Tetra(p.o) & 0xff
	} else {
		break stall
	}
	if Tetra(mx.coolO)-Tetra(mx.coolS) <= x {
		@<$\gamma$를 줄이는 명령을...@>
	}
	mx.newO = mx.coolO - Octa(x) - 1
	var newL int
	if cool.i == pop {
		if int(cool.xx) <= mx.coolL {
			newL = int(x) + int(cool.xx)
		} else {
			newL = int(x) + mx.coolL + 1
		}
	} else {
		newL = int(x)
	}
	if newL > mx.coolG {
		newL = mx.coolG
	}
	if int(x) < newL {
		cool.renX = true
		mx.specInstall(mx.lr(Tetra(mx.coolO)-1), &cool.x)
	}
	cool.setL = true
	mx.specInstall(&mx.g[rL], &cool.rl)
	cool.rl.o = Octa(Tetra(newL))
	if cool.i == pop {
		cool.z.o = Octa(yz << 2)
		if mx.instPtr.p == &mx.unknownSpec && newHead == mx.tail {
			mx.instPtr.p = &cool.goLoc
		}
	}
	break special
}

@ @<명령 배정의 특별한 경우들@>=
case mulu:
	cool.renA = true
	mx.specInstall(&mx.g[rH], &cool.a)
case div, divu:
	cool.renA = true
	mx.specInstall(&mx.g[rR], &cool.a)

@ 아무 연산도 할 필요가 없을 때는 재정렬 버퍼의 자리를 차지하지 않게 할 수 있을 것 같은
유혹이 든다. \.{JMP} 명령은 이런 뜻에서 아무것도 하지 않는 명령에 해당한다. 제어의 변화가
실행 단계 전에 일어나기 때문이다. 그러나 아무것도 하지 않는 명령이라도 사용 레지스터~rU에
세어야 할 수도 있으므로, 그 까닭으로 실행 단계에 들어갈 수 있다. 아무것도 하지 않는 명령이
음인 위치에 있으면 보호 인터럽트를 일으킬 수도 있다. 더 중요한 것은 이것이다. 프로그램이
점프와 아무것도 하지 않는 명령만으로 이루어진 루프에 빠질 수 있는데, 그러면 우리는 그것을
가로막을 수 없다. 가로막는 장치가 재정렬 버퍼에서 현재 위치를 찾아야 하기 때문이다! 그래서
적어도 한 기능 장치는 \.{JMP}, \.{JMPB}, \.{SWYM}을 명시적으로 지원해야 한다.

비트 |fBit|가 켜진 \.{SWYM} 명령은 특별한 경우다. 이것은 페이지 테이블 방법이 하드웨어에 구현되어
있지 않을 때, 가져오기 코루틴이 IT-캐시를 고쳐 달라고 요청하는 것이다.

@<명령 배정의 특별한 경우들@>=
case noop:
	if cool.interrupt&fBit != 0 {
		cool.goLoc.o, cool.y.o = cool.loc, cool.loc
		mx.instPtr = mx.specval(&mx.g[rT])
	}

@ @<|cool| 블록에 너무 일찍...@>=
if cool.renX || cool.memX {
	specRem(&cool.x)
}
if cool.renA {
	specRem(&cool.a)
}
if cool.setL {
	specRem(&cool.rl)
}
if mx.instPtr.p == &cool.goLoc {
	mx.instPtr.p = &mx.unknownSpec
}
break

@* 실행 단계. \MMIX가 {\it 존재하는 까닭\/}은 명령을 실행하는 능력이다. 그러니 이제 기능
장치들의 행동을 흉내 내고 싶다.

현재 클럭 틱에 동작하도록 스케줄된 코루틴마다 \MMIX\ 하드웨어의 특정 부분집합에 해당하는
|stage| 번호가 있다. 이를테면 |stage=2|인 코루틴은 기능 장치 파이프라인의 둘째 단계다.
단계 번호가 0인 코루틴은 가져오기 장치에서 일한다. 인위적으로 큰 단계 번호 몇 개는 버퍼의 데이터를
메모리에 쓰는 일 따위를 하는 특별한 코루틴들을 제어하는 데 쓰인다.

이 프로그램에서 지금 관심 있는 코루틴은 |self|라고 부른다. 그러니 |self.stage|가 지금 관심
있는 단계 번호다. 또 다른 핵심 변수 |self.ctl|은 |data|라고 부른다. 현재 코루틴이 다루고 있는
제어 블록이다. 우리는 대개 |data.x|를 |data.y|와 |data.z|의 함수로 계산하는 연산을 흉내 낸다.
레코드 |data|에는 앞서 \KW{control} 구조를 정의할 때 설명한 대로 필드가 많다. 이를테면 실행
단계 동안 |data.owner|가 |nil|이 아니면 |self|와 같다.

시뮬레이터의 이 부분은 기능 장치마다 256가지 연산을 모두 다룰 수 있는 것처럼 쓰여 있다.
물론 실제로는 기능 장치가 훨씬 전문화되어 있기 마련이다. 실제 전문화는 배정기가 정한다.
배정기는 명령을 그것을 지원하는 기능 장치에만 발행한다. 그러나 일단 명령이 배정되면, 그
기능 장치가 만능이라고 상상하는 것이 흉내 내기에 가장 쉽다.

단계 번호 |stage|가 큰 코루틴을 먼저 처리한다. 단계 번호 |self.stage|가 주어졌을 때 코루틴의 행동을 지배하는
가장 중요한 세 변수는 바깥 연산 코드 |data.op|, 내부 연산 코드 |data.i|, 그리고 |data.state|의
값이다. 코루틴을 처음 띄울 때는 대개 |data.state=0|이다.

@ 코루틴은 한 사이클에 하고 싶은 일을 다 하면 |goto done|이라고 말한다. 그 코루틴은 실행을
시작한 뒤로 |schedule| 루틴이 불리지 않았다면 더 이상 일하도록 스케줄되지 않는다. 매크로
|wait|는 ``정해진 시간 뒤에 현재의 |data.state|에서 다시 시작하도록 나를 스케줄해 주세요''라고
말하는 편리한 방법이다. 이를테면 |wait(1)|은 다음 클럭 틱에 코루틴을 다시 시작한다.

보충: 원본의 코루틴들은 모두 절 ``현재 시각에 스케줄된 코루틴을 모두 실행한다'' 안의 거대한
스위치 하나로 짜여 있었다. 이 스위치 안에서 코드는 |goto|로 이름표 사이를 넘나들고, |case|
사이를 흘러내리고, 안쪽 블록 한가운데로 뛰어든다. 그런 구조를 \GO/로 옮기려고, 옮긴이는 그
스위치를 메서드 |step| 하나로 만들고 ``지점 기계''로 짰다. 원본의 이름표 하나하나와 상태
스위치의 |case| 하나하나가 \KW{label} 타입의 지점이 된다. 메서드는 |for| 루프 안의 |switch pc|로
돌면서, 지점마다 원본의 코드를 수행한다. 원본에서 다음 |case|로 흘러내리던 곳은 \GO/의
|fallthrough|가 되고, |goto X|는 |pc=X|와 |continue|가 된다. 원본의 |goto done|은 |return false|이고,
|goto terminate|는 |return true|다.

원본은 이름표로 뛸 때 |data.state|를 바꾸지 않는다. 이 값은 추적 출력에 찍히므로, 지점을
흉내 내는 데 |data.state|를 빌려 쓰면 안 된다. 그래서 따로 |pc| 변수를 둔다. 원본의 상태
스위치 가운데 하나에서 상태가 |s|인 |case|는 그 스위치의 기준값에 |s|를 더한 지점이다. 그러면
원본의 |goto switch1| 같은 다시 가르기가 |pc=stage1St+label(data.state)| 한 줄이 된다.
원본에서 흔히 쓴 꼴 `이름표: |data.state=s|; |case s|:'는 그 |case|의 지점 하나로 합친다.
상태가 이미 |s|일 때 다시 |s|로 정하는 것은 아무 일도 하지 않기 때문이다.

원본의 매크로 |wait|, |pass_after|, |sleep|, |awaken|은 메서드가 된다. 메서드 |wait|와 |sleep|은 |false|를 돌려주므로, |return mx.wait(self,t)|가 원본의 |wait(t)|다.

@<함수들@>=
func (mx *machine) wait(self *coroutine, t int) bool {
	mx.schedule(self, t, self.ctl.state)
	return false
}
@#
func (mx *machine) passAfter(self *coroutine, t int) {
	mx.schedule(self.succ, t, self.ctl.state)
}
@#
func (mx *machine) sleep(self *coroutine) bool { // 영원히 기다린다
	self.next = self
	return false
}
@#
func (mx *machine) awaken(c *coroutine, t int) {
	mx.schedule(c, t, c.ctl.state)
}

@ @<현재 시각에 스케줄된 코루틴을 모두 실행한다@>=
mx.curTime++
if mx.curTime == mx.ringSize {
	mx.curTime = 0
}
for self := mx.queuelist(mx.curTime); self != &mx.sentinel; self = mx.sentinel.next {
	mx.sentinel.next = self.next
	self.next = nil // 이 코루틴의 스케줄을 푼다
	if mx.verbose&coroutineBit != 0 {
		mx.printf(" running ")
		mx.printCoroutineID(self)
		mx.printf(" ")
		mx.printControlBlock(self.ctl)
		mx.printf("\n")
	}
	if mx.step(self) { // 원본의 |terminate|
		if self.lockloc != nil {
			*self.lockloc = nil
			self.lockloc = nil
		}
	}
}

@ 보충: 원본에서 |i|, |j|, |p|, |q|는 |MMIX_run|의 지역 변수였으므로, 한 코루틴이 남긴 값이
다음 코루틴에서도 보였다. 그러나 코루틴들은 이 변수들을 읽기 전에 늘 새로 정한다. 그래서
여기서는 |step|의 지역 변수다. 특별한 코루틴들은 원본에서 저마다 블록 첫머리에 |c|, |cc|,
|co| 같은 지역 변수를 선언했는데, 여기서는 이것들도 |step|의 지역 변수로 두고 코루틴의 출발
지점에서 정한다.

@<함수들@>=
func (mx *machine) step(self *coroutine) bool {
	data := self.ctl
	var (
		i, j  int
		p, q  *cacheblock
		c     *cache
		cc    *coroutine
		co    []coroutine
		pc    label
		@<|step|의 다른 지역 변수@>
	)
	switch self.stage {
	case 0:
		pc = lSwitch0
	case 1:
		pc = lSwitch1
	default:
		pc = lSwitch2
	@<특별한 코루틴의 출발 지점@>
	}
	for {
		switch pc {
		@<가져오기 코루틴의 동작을 흉내 낸다@>
		@<실행 파이프라인의 첫 단계를 흉내 낸다@>
		@<실행 파이프라인의 뒤 단계들을 흉내 낸다@>
		@<특별한 코루틴을 제어하는 경우들@>
		default:
			@<맞는 |case|가 없으면 다음 스위치로 흘러내린다@>
		}
		mx.panic(confusion(fmt.Sprintf("label %d", pc)))
	}
}

@ 지점은 두 가지다. 원본의 이름표는 여기에 모은 차례 번호를 가진다. 원본의 상태 스위치
|case|는 스위치마다 정한 기준값에 상태 번호를 더한 번호를 가진다. 상태 번호는 모두 100보다
작다.

@<타입 정의@>=
type label int

@ @<상수@>=
const (
	lSwitch0 label = iota // 가져오기 코루틴의 상태 스위치
	lSwitch1              // 첫 단계의 상태 스위치
	lSwitch2              // 뒤 단계들의 상태 스위치
	@<지점 이름@>
)
@#
const (
	fetchSt    label = 1000  // 가져오기 코루틴의 상태 |case|
	stage1St   label = 2000  // 첫 단계의 상태 |case|
	stage2St   label = 3000  // 뒤 단계들의 상태 |case|
	flushMemSt label = 4000  // |flushToMem|의 상태 |case|
	flushSSt   label = 5000  // |flushToS|의 상태 |case|
	fillMemSt  label = 6000  // |fillFromMem|의 상태 |case|
	fillSSt    label = 7000  // |fillFromS|의 상태 |case|
	cleanupSt  label = 8000  // |cleanup|의 상태 |case|
	fillVirtSt label = 9000  // |fillFromVirt|의 상태 |case|
	writeSt    label = 10000 // |writeFromWbuf|의 상태 |case|
)

@ 원본에서 가져오기 코루틴의 상태 스위치는 |stage=0|인 |case| 안에 있고, 그 뒤에 |stage=1|인
|case|와 |default|가 차례로 온다. 그래서 상태 스위치에 맞는 |case|가 없으면 다음 단계의 상태
스위치로 흘러내린다. 뒤 단계들의 상태 스위치에 맞는 |case|가 없으면 특별한 코루틴의 첫 |case|인
|vanish|에 이르러 |terminate|로 뛴다. 보충: 이를테면 1단계에서 \.{SYNCD}가 보호 검사에 걸려
|sync_check|를 거쳐 |square_one|으로 가면, 1단계 코루틴이 상태 |dtRetry|로 다시 스케줄되어 이
흘러내림을 겪는다. 여기서는 그 흘러내림을 흉내 낸다.

@<맞는 |case|가 없으면...@>=
switch {
case pc >= fetchSt && pc < stage1St:
	pc = lSwitch1
	continue
case pc >= stage1St && pc < stage2St:
	pc = lSwitch2
	continue
case pc >= stage2St && pc < flushMemSt:
	return true
}

@ 단계 번호가 |vanish|인 특별한 코루틴은 스케줄된 시각에 그냥 사라진다.

@<특별한 코루틴의 출발 지점@>=
case vanish:
	return true

@ @<기계의 상태@>=
memLocker coroutine // 사라지는 하찮은 코루틴
dLocker   coroutine // 또 하나
vanishCtl control   // 그런 코루틴들이 함께 쓰는 제어 블록

@ @<모든 것을 초기화한다@>=
mx.memLocker.name = "Locker"
mx.memLocker.ctl = &mx.vanishCtl
mx.memLocker.stage = vanish
mx.dLocker.name = "Dlocker"
mx.dLocker.ctl = &mx.vanishCtl
mx.dLocker.stage = vanish
mx.vanishCtl.goLoc.o = 4
for j = 0; j < mx.DTcache.ports; j++ {
	mx.DTcache.reader[j].ctl = &mx.vanishCtl
}
if mx.Dcache != nil {
	for j = 0; j < mx.Dcache.ports; j++ {
		mx.Dcache.reader[j].ctl = &mx.vanishCtl
	}
}
for j = 0; j < mx.ITcache.ports; j++ {
	mx.ITcache.reader[j].ctl = &mx.vanishCtl
}
if mx.Icache != nil {
	for j = 0; j < mx.Icache.ports; j++ {
		mx.Icache.reader[j].ctl = &mx.vanishCtl
	}
}

@ 다음은 아래에서 정의할 특별한 코루틴들의 |stage| 번호 목록이다.

@<상수@>=
const (
	maxStage      = 99 // 모든 |stage| 번호보다 크다
	vanish        = 98 // 그냥 사라지는 특별한 코루틴
	flushToMem    = 97 // 캐시에서 메모리로 쏟아 내는 코루틴
	flushToS      = 96 // 캐시에서 S-캐시로 쏟아 내는 코루틴
	fillFromMem   = 95 // 메모리에서 캐시를 채우는 코루틴
	fillFromS     = 94 // S-캐시에서 캐시를 채우는 코루틴
	fillFromVirt  = 93 // 변환 캐시를 채우는 코루틴
	writeFromWbuf = 92 // 쓰기 버퍼를 비우는 코루틴
	cleanup       = 91 // 캐시를 청소하는 코루틴
)

@ 1단계를 시작하자마자 기능 장치는 필요하면 피연산자를 쓸 수 있을 때까지 멈춘다. 피연산자가
모두 있으면 |state|를 0이 아닌 값으로 정하고 본격적인 실행을 시작한다.

@<실행 파이프라인의 첫 단계...@>=
case lSwitch1:
	pc = stage1St + label(data.state)
	continue
case stage1St + 0:
	@<필요하면 입력 데이터를 기다린다. 데이터가 있으면 |state=1|로 한다@>
	fallthrough
case stage1St + 1:
	@<연산의 실행을 시작한다@>
case lPassData:
	@<|data|를 파이프라인의 다음 단계로 넘긴다@>
case lFinEx:
	@<연산의 실행을 마친다@>
@<첫 단계의 특별한 상태들@>

@ 입력 데이터 가운데 일부를 다른 코루틴이 이번 사이클에 계산했다면, 지금 그것을 붙잡되 다음
사이클까지 기다린다. (실제 기계라면 그때까지는 데이터를 래치에 붙잡지 않았을 것이다.)

@<필요하면 입력 데이터를 기다린다...@>=
j = 0
if data.y.p != nil {
	j++
	if data.y.p.known {
		data.y.o, data.y.p = data.y.p.o, nil
	} else {
		j += 10
	}
}
if data.z.p != nil {
	j++
	if data.z.p.known {
		data.z.o, data.z.p = data.z.p.o, nil
	} else {
		j += 10
	}
}
@<|b|와 |ra| 입력을 기다린다@>
if j < 10 {
	data.state = 1
}
if j != 0 {
	return mx.wait(self, 1) // 그렇지 않으면 |case 1|로 흘러내린다
}

@ @<|b|와 |ra| 입력을...@>=
if data.b.p != nil {
	if data.needB {
		j++
	}
	if data.b.p.known {
		data.b.o, data.b.p = data.b.p.o, nil
	} else if data.needB {
		j += 10
	}
}
if data.ra.p != nil {
	if data.needRA {
		j++
	}
	if data.ra.p.known {
		data.ra.o, data.ra.p = data.ra.p.o, nil
	} else if data.needRA {
		j += 10
	}
}

@ \.{ADD} 같은 간단한 레지스터 대 레지스터 명령은 한 사이클만 걸린다고 가정하지만,
\.{FADD} 같은 다른 명령은 거의 틀림없이 시간이 더 필요하다. 이 시뮬레이터는 \.{FADD}가 이를테면
한 사이클씩인 파이프라인 단계 넷($1+1+1+1$)을 거치거나, 두 사이클씩인 단계 둘($2+2$)을
거치거나, 네 사이클이 걸리는 파이프라인 없는 단계 하나(4)를 거치도록 설정할 수 있다. 어느
경우든 시뮬레이터는 간단히 지금 결과를 계산해서 |data.x|에 넣고, 경우에 따라 |data.a|나
|data.interrupt|에도 넣는다. 결과는 알맞은 때가 될 때까지 공식적으로 |known|이 되지 않는다.

@<연산의 실행을 시작한다@>=
switch data.i {
@<레지스터 대 레지스터 연산의 결과를 계산하는 경우들@>
@<메모리 연산의 가상 주소를 계산하는 경우들@>
@<1단계 실행의 경우들@>
}
@<결과가 알맞은 때에 |known|이 되도록 준비한다@>

@ 내부 연산 코드 |data.i|가 |maxPipeOp| 이하이면, $1+1+1+1$이나 $2+2$나 $15+10$ 같은 특별한
파이프라인 순서가 설정되어 있다. 그렇지 않으면 파이프라인 순서가 그냥~1이라고 가정한다.

파이프라인 순서가 $t_1+t_2+\cdots+t_k$라고 하자. 시간 $t_j$는 모두 양수이고 256보다 작으므로, 이
순서를 0으로 끝나는 부호 없는 ``문자''의 문자열 |pipeSeq[data.i]|로 나타낸다. 그런 문자열이
주어지면 다음 일을 하고 싶다. 먼저 $(t_1-1)$ 사이클을 기다렸다가 |data|를 2단계로 넘긴다. 이어서 $t_2$ 사이클을 기다렸다가 |data|를 3단계로 넘긴다. \dots. 그다음 $t_{k-1}$ 사이클을 기다렸다가 |data|를
$k$단계로 넘긴다. 마지막으로 $t_k$ 사이클을 기다렸다가 결과를 |known|으로 만든다.

지연 |denin|의 값은 $t_1$에 더하고, |denout|의 값은 $t_k$에 더한다.

@<결과가 알맞은 때에...@>=
data.state = 3
if data.i <= maxPipeOp {
	s := &mx.pipeSeq[data.i]
	j = int(s[0]) + data.denin
	if s[1] != 0 {
		data.state = 2 // 단계가 하나보다 많다
	} else {
		j += data.denout
	}
	if j > 1 {
		return mx.wait(self, j-1)
	}
}
pc = lSwitch1
continue

@ 코루틴이 $j$단계에 있을 때, 같은 기능 장치의 $j+1$단계 코루틴은 |self.succ|다.

@<지점 이름@>=
lPassit // 원본의 |passit|

@ @<|data|를 파이프라인의...@>=
if self.succ.next != nil {
	return mx.wait(self, 1) // 다음 단계가 차 있으면 멈춘다
}
{
	s := &mx.pipeSeq[data.i]
	j = int(s[self.stage])
	if s[self.stage+1] == 0 {
		j += data.denout
		data.state = 3 // 다음 단계가 마지막이다
	}
	mx.passAfter(self, j)
}
fallthrough
case lPassit:
	self.succ.ctl = data
	data.owner = self.succ
	return false

@ @<상수@>=
const (
	lPassData = stage1St + 2 // 원본의 |pass_data|
	lFinEx    = stage1St + 3 // 원본의 |fin_ex|
)

@ @<실행 파이프라인의 뒤 단계들...@>=
case lSwitch2:
	if data.b.p != nil && data.b.p.known {
		data.b.o, data.b.p = data.b.p.o, nil
	}
	pc = stage2St + label(data.state)
	continue
case stage2St + 0:
	mx.panic(confusion("switch2"))
case stage2St + 1:
	@<2단계 연산의 실행을 시작한다@>
	fallthrough
case stage2St + 2:
	pc = lPassData
	continue
case stage2St + 3:
	pc = lFinEx
	continue
@<뒤 단계들의 특별한 상태들@>

@ 기본 파이프라인 시간은 한 단계만 쓴다. 루틴 |MMIX_config|가 이것을 바꿀 수 있다. 이
시뮬레이터가 지원하는 단계의 총수는 90으로 제한된다. 아래에서 정의하는 특별한 코루틴들의
|stage| 번호와 결코 부딪치지 않아야 하기 때문이다. (크누스는 이런 제한을 둔 것에 조금도
죄책감을 느끼지 않는다.)

@<상수@>=
const pipeLimit = 90

@ @<기계의 상태@>=
pipeSeq [maxPipeOp + 1][pipeLimit + 1]byte

@ 모든 레지스터 대 레지스터 연산 가운데 가장 단순한 것은 |set|이다. 이것은 \.{SETH} 같은
명령뿐 아니라 \.{GETA} 같은 명령에도 쓰인다. (쉬운 경우부터 시작해서 차츰 어려운 쪽으로
나아가는 것이 좋겠다.)

@<레지스터 대 레지스터 연산의 결과를...@>=
case set:
	data.x.o = data.z.o

@ 다음은 기본적인 불 연산들인데, \MMIX의 연산 코드 256개 가운데 24개를 차지한다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case or:
	data.x.o = data.y.o | data.z.o
case orn:
	data.x.o = data.y.o | ^data.z.o
case nor:
	data.x.o = ^(data.y.o | data.z.o)
case and:
	data.x.o = data.y.o & data.z.o
case andn:
	data.x.o = data.y.o &^ data.z.o
case nand:
	data.x.o = ^(data.y.o & data.z.o)
case xor:
	data.x.o = data.y.o ^ data.z.o
case nxor:
	data.x.o = data.y.o ^ ^data.z.o

@ \.{ADDU}의 구현은 조금만 더 어렵다. 내부 연산 코드 |addu|가 \.{ADDU[I]}와 \.{INC[M][H,L]}
연산에만 쓰인다면 간단하겠다. 그런 연산에서는 그냥 |data.y.o|를 |data.z.o|에 더하면 된다.
그러나 |addu|는 \.{4ADDU} 같은 연산에도 쓰인다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case addu:
	if data.op&0xf8 == 0x28 {
		data.x.o = data.y.o<<(1+((data.op>>1)&0x3)) + data.z.o
	} else {
		data.x.o = data.y.o + data.z.o
	}
case subu:
	data.x.o = data.y.o - data.z.o

@ 부호 있는 덧셈과 뺄셈은 부호 없는 덧셈과 뺄셈과 같은 결과를 내지만, 넘침도 찾아내야 한다.
값 |y|를~|z|에 더할 때 넘침은 |y|와~|z|의 부호가 같은데 합의 부호가 다를 때, 그리고 그때에만
일어난다. 계산 |x=y-z|에서 넘침이 일어나는 것은 계산 |y=x+z|에서 넘침이 일어날 때, 그리고
그때뿐이다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case add:
	data.x.o = data.y.o + data.z.o
	if (data.y.o^data.z.o)&signBit == 0 && (data.y.o^data.x.o)&signBit != 0 {
		data.interrupt |= vBit
	}
case sub:
	data.x.o = data.y.o - data.z.o
	if (data.x.o^data.z.o)&signBit == 0 && (data.y.o^data.x.o)&signBit != 0 {
		data.interrupt |= vBit
	}

@ 자리 옮김 명령은 |pipeSeq[sh]|의 기본값을 바꾸면 한 사이클보다 오래 걸리거나 파이프라인으로
처리될 수도 있다. 그러나 여기서는 자리 옮김을 한꺼번에 계산한다. 파이프라인의 시간 계산은
시뮬레이터의 다른 부분이 맡기 때문이다. (그래서 |shlu|를 |sh|로 바꾼다는 데 주목하라. 아래의
다른 연산자에서도 내부 연산 코드를 비슷하게 바꾼다.)

보충: 원본의 매크로 |shift_amt|는 \.{mmixsim}에서처럼 |z|가 64 이상이면 64다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case shlu:
	data.x.o = data.y.o << shiftAmt(data.z.o)
	data.i = sh
case shl:
	data.x.o = data.y.o << shiftAmt(data.z.o)
	data.i = sh
	if mmixarith.ShiftRight(data.x.o, shiftAmt(data.z.o), false) != data.y.o {
		data.interrupt |= vBit
	}
case shru:
	data.x.o = mmixarith.ShiftRight(data.y.o, shiftAmt(data.z.o), true)
	data.i = sh
case shr:
	data.x.o = mmixarith.ShiftRight(data.y.o, shiftAmt(data.z.o), false)
	data.i = sh

@ @<함수들@>=
func shiftAmt(z Octa) int {
	if z >= 64 {
		return 64
	}
	return int(z)
}

@ \.{MUX} 연산의 피연산자는 셋, 곧 |data.y|, |data.z|, |data.b|다. 셋째 피연산자는 특수 마스크
레지스터~rM의 현재 (투기적) 값이다. 그 밖에 \.{MUX}는 평범하다.

보충: 원본은 두 부분을 |+|로 합쳤는데, 겹치는 비트가 없으므로 논리합과 같다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case mux:
	data.x.o = data.y.o&data.b.o | data.z.o&^data.b.o

@ 비교는 누워서 떡 먹기다.

보충: 원본은 이 경우들을 |cmp_neg|, |cmp_pos|, |cmp_zero| 따위의 이름표 사이를 |goto|로 오가며 처리했다. 필드 |data.x.o|는 처음에 0이다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case cmp:
	if int64(data.y.o) < int64(data.z.o) {
		data.x.o = negOne
	} else if data.y.o != data.z.o {
		data.x.o = 1
	}
case cmpu:
	if data.y.o < data.z.o {
		data.x.o = negOne
	} else if data.y.o != data.z.o {
		data.x.o = 1
	}

@ 다른 연산들은 기본 착상을 이해했으니 나중으로 미룬다. 그러나 다른 주제로 넘어가기 전에 써
두어야 할 코드가 하나 더 있다. 이미 다룬 간단한 경우들의 실행 단계를 마무리하는 코드다.

필드 |renX|와 |renA|는 |x|와 |a| 필드에 공식적으로 알려야 할 유효한 정보가 들어 있는지를
알려 준다.

@<지점 이름@>=
lDie // 원본의 |die|

@ @<연산의 실행을 마친다@>=
if data.renX {
	data.x.known = true
} else if data.memX {
	data.x.known = true
	if (data.x.addr>>32)&0xffff0000 == 0 {
		data.x.addr &^= 7
	}
}
if data.renA {
	data.a.known = true
}
if data.loc&signBit != 0 {
	data.ra.o &^= 0xffffffff // 운영체제에서는 트립을 허용하지 않는다
}
if data.interrupt&0xffff != 0 {
	@<실행 단계 끝에서 인터럽트를 다룬다@>
}
fallthrough
case lDie:
	data.owner = nil
	return true // 이 코루틴은 이제 사라진다

@* 확정과 발행 취소 단계. 제어 블록은 뜨거운 끝에서(확정될 때) 또는 차가운 끝에서(발행이
취소될 때) 재정렬 버퍼를 떠난다. 대부분이 확정되기를 바라지만, 이따금 투기가 틀려서 쓸모없는
것으로 드러난 명령들의 발행을 취소해야 한다. 발행 취소가 확정보다 우선해야 한다. 기계의 차가운
상태가 안정될 때까지 배정기가 아무 일도 할 수 없기 때문이다.

발행 취소는 가장 최근에 발행한 명령들을 거꾸로 되돌려서 차가운 상태를 바꾼다. 확정은 가장
오래전에 발행한 명령들을 원래 순서대로 해서 뜨거운 상태를 바꾼다. 두 연산은 비슷하므로 같은
시간이 걸린다고 가정한다. 클럭 사이클마다 많아야 |commitMax|개의 명령을 발행 취소하거나
확정한다.

@<가장 차가운 명령의 발행을...@>=
mx.cool = mx.nextCtl(mx.cool)
cool := mx.cool
if mx.verbose&issueBit != 0 {
	mx.printf("Deissuing ")
	mx.printControlBlock(cool)
	if cool.owner != nil {
		mx.printf(" ")
		mx.printCoroutineID(cool.owner)
	}
	mx.printf("\n")
}
@<|cool| 명령이 차지한 이름 바꾸기 레지스터와 메모리 자리를 돌려준다@>
if cool.owner != nil {
	if cool.owner.lockloc != nil {
		*cool.owner.lockloc = nil
		cool.owner.lockloc = nil
	}
	if cool.owner.next != nil {
		mx.unschedule(cool.owner)
	}
}
mx.coolO, mx.coolS = cool.curO, cool.curS
mx.deissues--

@ @<|cool| 명령이 차지한...@>=
if cool.renX {
	mx.renameRegs++
	specRem(&cool.x)
}
if cool.renA {
	mx.renameRegs++
	specRem(&cool.a)
}
if cool.memX {
	mx.memSlots++
	specRem(&cool.x)
}
if cool.setL {
	specRem(&cool.rl)
}

@ @<가장 뜨거운 명령을 확정하고...@>=
hot := mx.hot
if mx.nullifying {
	@<가장 뜨거운 명령을 무효로 만든다@>
} else {
	if hot.i == get && hot.zz == rQ {
		mx.newQ = mx.g[rQ].o &^ hot.x.o
	} else if hot.i == put && hot.xx == rQ {
		hot.x.o |= mx.newQ
	}
	if hot.memX {
		@<가능하면 메모리에 확정하고, 그렇지 않으면 |break|한다@>
	}
	if hot.stackAlert {
		mx.stackOverflowed = true
	} else if mx.stackOverflowed && !hot.interim {
		mx.g[rQ].o |= stackOverflow
		mx.newQ |= stackOverflow
		mx.stackOverflowed = false
		if mx.verbose&issueBit != 0 {
			mx.printf(" setting rQ=")
			mx.printOcta(mx.g[rQ].o)
			mx.printf("\n")
		}
	}
	if mx.verbose&issueBit != 0 {
		mx.printf("Committing ")
		mx.printControlBlock(hot)
		mx.printf("\n")
	}
	@<가장 뜨거운 명령의 결과를 뜨거운 상태에 넣는다@>
}
if hot.interrupt >= hBit {
	@<인터럽트를 시작하고 |break|한다@>
}

@ 보충: 원본에서 rU의 아래 47비트가 사용 횟수다. \.{mmixsim}에서처럼 이 47비트만 $2^{47}$을
법으로 1 늘린다.

@<가장 뜨거운 명령의 결과를...@>=
if hot.renX {
	mx.renameRegs++
	hot.x.up.o = hot.x.o
	specRem(&hot.x)
}
if hot.renA {
	mx.renameRegs++
	hot.a.up.o = hot.a.o
	specRem(&hot.a)
}
if hot.setL {
	hot.rl.up.o = hot.rl.o
	specRem(&hot.rl)
}
if hot.arithExc != 0 {
	mx.g[rA].o |= Octa(hot.arithExc)
}
if hot.usage {
	const count = 1<<47 - 1
	mx.g[rU].o = mx.g[rU].o&^count | (mx.g[rU].o+1)&count
}

@ 적재나 저장 명령이 트랩 인터럽트에 곧 붙잡히게 되면 그 명령을 ``무효로 만든다''. 그런 경우
그 명령은 재정렬 버퍼에 있는 유일한 항목일 것이다. 그러니 무효로 만드는 것은 발행 취소와 확정의
중간쯤 되는 일이다. (무효로 만들어야 할 때는 배정을 멈추어 두는 것이 중요하다. 내부 명령 |incgamma|나 |decgamma|가 rS를 바꾸는데, 뜻밖의 가로막기가 일어나면 그것을 되돌려야 하기 때문이다.)

@<가장 뜨거운 명령을 무효로...@>=
if mx.verbose&issueBit != 0 {
	mx.printf("Nullifying ")
	mx.printControlBlock(hot)
	mx.printf("\n")
}
if hot.renX {
	mx.renameRegs++
	specRem(&hot.x)
}
if hot.renA {
	mx.renameRegs++
	specRem(&hot.a)
}
if hot.memX {
	mx.memSlots++
	specRem(&hot.x)
}
if hot.setL {
	specRem(&hot.rl)
}
mx.coolO, mx.coolS = hot.curO, hot.curS
mx.nullifying = false

@ rQ의 인터럽트 비트는 \.{GET}과~\.{PUT} 사이에 켜지면 잃어버릴 수 있다. 그래서 가장 최근에
확정한 \.{GET} 뒤로 1이 된 비트들을 \.{PUT}이 0으로 만들지 못하게 한다.

보충: 원본의 전역 변수 |stack_overflow|는 rQ의 비트 이름 \.{STACK\_OVERFLOW}와 헷갈리지 않도록
여기서는 |stackOverflowed|라고 부른다.

@<기계의 상태@>=
newQ            Octa // rQ의 어느 비트가 늘면 이것도 그래야 한다
stackOverflowed bool // 아직 알리지 않은 스택 넘침

@ 명령이 \MMIX의 기본 보안 규칙을 어기면 곧바로 확정하지 않는다. 그 규칙은 이렇다. 음이
아닌 위치에 있는 명령은, 인터럽트 마스크 레지스터~rK에서 여덟 가지 내부 인터럽트가 모두
허용되어 있지 않으면 수행하지 않아야 한다. 반대로 음인 위치에 있는 명령은, rK에서 |pBit|가
허용되어 있으면 수행하지 않아야 한다.

그런 명령은 확정되기 전에 사이클이 하나 더 걸린다. 음이 아닌 위치의 경우에는 rK와~rQ 둘 다의
|sBit|를 켜서 곧바로 인터럽트가 일어나게 한다(현재 명령이 |trap|, |put|, |resume|이 아니라면).

@<보안 위반을 검사하고...@>=
if mx.hot.loc&signBit != 0 {
	if mx.g[rK].o&(pBit<<32) != 0 && mx.hot.interrupt&pBit == 0 {
		mx.hot.interrupt |= pBit
		mx.g[rQ].o |= pBit << 32
		mx.newQ |= pBit << 32
		if mx.verbose&issueBit != 0 {
			mx.printf(" setting rQ=")
			mx.printOcta(mx.g[rQ].o)
			mx.printf("\n")
		}
		break
	}
} else if (mx.g[rK].o>>32)&0xff != 0xff && mx.hot.interrupt&sBit == 0 {
	mx.hot.interrupt |= sBit
	mx.g[rQ].o |= sBit << 32
	mx.newQ |= sBit << 32
	mx.g[rK].o |= sBit << 32
	if mx.verbose&issueBit != 0 {
		mx.printf(" setting rQ=")
		mx.printOcta(mx.g[rQ].o)
		mx.printf(", rK=")
		mx.printOcta(mx.g[rK].o)
		mx.printf("\n")
	}
	break
}

@* 분기 예측. \MMIX\ 프로그래머는 ``분기''와 ``그럴듯한 분기''를 정적으로 구별한다. 그러나
오늘날의 많은 컴퓨터는 동적 분기 예측을 구현해서 더 잘하려고 한다. (이를테면 Hennessy와
Patterson의 {\sl Computer Architecture\/} 제2판 4.3절을 보라.) 경험에 따르면 동적 분기
@^Hennessy, John LeRoy@>
@^Patterson, David Andrew@>
예측은 발행을 취소해야 할 명령의 수를 줄여서 투기적 실행의 성능을 크게 높일 수 있다.

이 시뮬레이터에는 $n$~비트짜리 항목이 $2^{\mkern1mua+b+c}$개 든 |bpTable|을 선택적으로 둘 수
있다. 여기서 $n$은 1부터~8 사이다. 실제로는 대개 $n$이 1이나~2이지만, 이 프로그램에서는
편의상 항목마다 8비트를 할당한다. 표 |bpTable|은 모든 분기 명령마다(모든 \.{B}와 \.{PB} 명령마다,
그러나 \.{JMP}는 빼고) 비슷한 상황의 지난 이력에 대한 조언을 얻으려고 찾아보고 고친다. 이 표는
명령 주소의 가장 아래 $a$비트와, 전역 분기 이력의 가장 최근 $b$비트와, 주소와 이력의 그다음
$c$비트(배타적 논리합을 한 것)로 색인한다.

표 |bpTable|의 항목은 0에서 시작하고 부호 있는 $n$비트 수로 본다. 음이 아니면 명령의 예측을 따른다.
곧 \.{PB}인 경우에만 분기가 일어난다고 예측한다. 음이면 명령이 권하는 것과 반대로 예측한다.
명령의 예측이 맞았으면 $n$비트 수를 (할 수 있다면) 늘리고, 틀렸으면 (할 수 있다면) 줄인다.

(덧붙여, $n$을 크게 하는 것이 꼭 좋은 생각은 아니다. 이를테면 $n=8$이면, 처음 150번은 일어난
분기가 다음 150번은 일어나지 않는다는 것을 기계가 알아채는 데 128걸음이 필요할 수 있다. 이
문제를 피하려고 고치는 기준을 바꾸면, $n$이 더 작은 단순한 방법보다 나은 경우가 드문 방법을
얻게 된다.)

이 논의의 값 $a$, $b$, $c$, $n$을 프로그램에서는 |bpA|, |bpB|, |bpC|, |bpN|이라고 부른다.

보충: 원본의 |bp_table|은 \CEE/의 |char| 배열인데, 원본을 시험한 macOS에서 |char|는 부호가
있다. 비트 수가 $n=8$이면 부호가 결과에 영향을 주므로, 여기서도 부호 있는 바이트 |int8|을 쓴다.

@<기계의 상태@>=
bpA, bpB, bpC, bpN int    // 분기 예측의 매개변수
bpTable            []int8 // |nil|이거나 항목이 $2^{\mkern1mua+b+c}$개인 배열

@ 분기 예측은 명령을 발행하려 할 때나 앞을 엿볼 때 한다. 표 |bpTable|을 보기는 하지만, 아직
고치고 싶지는 않다.

@<분기의 결과를 예측한다@>=
predicted = op & 0x10 // 명령의 권고로 시작한다
if mx.bpTable != nil {
	m = mx.bpIndex(mx.head.loc)
	if int(mx.bpTable[m])&mx.bpNpower != 0 {
		predicted ^= 0x10
	}
}
if predicted != 0 {
	mx.peekHist = mx.peekHist<<1 + 1
} else {
	mx.peekHist <<= 1
}

@ 보충: 원본은 표의 색인을 계산하는 같은 두 줄을 두 곳에 썼다. 여기서는 메서드로 둔다.

@<함수들@>=
func (mx *machine) bpIndex(loc Octa) int {
	l := Tetra(loc)
	m := (l&Tetra(mx.bpCmask))<<mx.bpB + l&Tetra(mx.bpAmask)
	return int((mx.coolHist&Tetra(mx.bpBcmask))<<mx.bpA ^ m>>2)
}

@ 명령을 발행할 때 |bpTable|을 고친다. 그리고 예측이 틀린 것으로 드러날 경우에 대비해서, 표에
넣었어야 할 반대 값을 |cool.x.o|의 아랫 테트라에 넣어 둔다. 윗 테트라에는 표의 색인이 들어간다.

@<분기 예측의 결과를 기록한다@>=
if mx.bpTable != nil {
	reversed := op & 0x10
	if mx.peekHist&1 != 0 {
		reversed ^= 0x10
	}
	m = mx.bpIndex(mx.head.loc)
	h := int(mx.bpTable[m])
	hUp := (h + 1) & mx.bpNmask
	if hUp == mx.bpNpower {
		hUp = h
	}
	hDown := h
	if h != mx.bpNpower {
		hDown = (h - 1) & mx.bpNmask
	}
	if reversed != 0 {
		mx.bpTable[m] = int8(hDown)
		cool.x.o = Octa(Tetra(hUp))
		cool.i = pbr + br - cool.i // 뜻을 뒤집는다
		mx.bpRevStat++
	} else {
		mx.bpTable[m] = int8(hUp)
		cool.x.o = Octa(Tetra(hDown)) // 흐름을 따른다
		mx.bpOkStat++
	}
	if mx.verbose&showPredBit != 0 {
		mx.printf(" predicting ")
		mx.printOcta(cool.loc)
		ok := "OK"
		if reversed != 0 {
			ok = "NG"
		}
		b := int(mx.bpTable[m])
		mx.printf(" %s; bp[%x]=%d\n", ok, m, b-((b&mx.bpNpower)<<1))
	}
	cool.x.o |= Octa(Tetra(m)) << 32
}

@ 앞 절들의 계산에는 매개변수 $a$, $b$, $c$, $n$에 따라 미리 계산해 둔 상수가 몇 개 필요하다.

보충: 원본은 $n=0$일 때도 $2^{n-1}$을 계산한다. 음수만큼 옮기는 것은 \CEE/에서 정의되지 않은
동작이고 \GO/에서는 공황이다. 비트 수가 $n=0$이면 표 |bpTable|이 없어서 그 값을 쓰지 않으므로, 여기서는 그
계산을 건너뛴다.

@<모든 것을 초기화한다@>=
mx.bpAmask = ((1 << mx.bpA) - 1) << 2 // 명령 주소의 가장 아래 $a$비트
mx.bpCmask = ((1 << mx.bpC) - 1) << (mx.bpA + 2) // 그다음 $c$개의 주소 비트
mx.bpBcmask = (1 << (mx.bpB + mx.bpC)) - 1 // 이력 정보의 가장 아래 $b+c$비트
mx.bpNmask = (1 << mx.bpN) - 1 // 가장 아래 $n$비트
if mx.bpN > 0 {
	mx.bpNpower = 1 << (mx.bpN - 1) // $2^{n-1}$, 곧 $n$비트 수의 부호 비트
}

@ 보충: 원본의 통계는 |int|였고 \.{\%d}로 찍었다. 여기서는 32비트로 둔다.

@<기계의 상태@>=
bpAmask, bpCmask, bpBcmask, bpNmask, bpNpower int
bpRevStat, bpOkStat                           int32 // 몇 번 뒤집고 몇 번 따랐는가
bpBadStat, bpGoodStat                         int32 // 몇 번 틀리고 몇 번 맞았는가

@ 분기나 그럴듯한 분기 명령을 발행했고 재정렬 버퍼에서 관련 레지스터의 값을 |data.b.o|로
계산했다면, 예측이 맞았는지 가릴 준비가 된 것이다.

@<1단계 실행의 경우들@>=
case br, pbr:
	j = registerTruth(data.b.o, data.op)
	if j != 0 {
		data.goLoc.o = data.z.o
	} else {
		data.goLoc.o = data.y.o
	}
	if (j != 0) == (data.i == pbr) {
		mx.bpGoodStat++
	} else { // 아이고, 잘못 예측했다
		mx.bpBadStat++
		@<잘못된 분기 예측에서 회복한다@>
	}
	pc = lFinEx
	continue

@ 서브루틴 |registerTruth|는 \.B, \.{PB}, \.{CS}, \.{ZS} 명령이 옥타바이트가 연산 코드
|data.op|의 조건을 만족하는지 가리는 데 쓴다.

@<함수들@>=
func registerTruth(o Octa, op int) int {
	var b int
	switch (op >> 1) & 0x3 {
	case 0:
		b = int(o >> 63) // 음수인가?
	case 1:
		b = b2i(o == 0) // 0인가?
	case 2:
		b = b2i(o < signBit && o != 0) // 양수인가?
	case 3:
		b = int(o & 0x1) // 홀수인가?
	}
	if op&0x8 != 0 {
		return b ^ 1
	}
	return b
}

@ 서브루틴 |issuedBetween|은 재정렬 버퍼 안의 주어진 제어 블록과 현재의 |cool| 포인터 사이에
투기적 명령이 몇 개나 발행되었는지 가린다. 이때 |cc=cool|이다.

@<함수들@>=
func (mx *machine) issuedBetween(c, cc *control) int {
	if c.idx > cc.idx {
		return c.idx - 1 - cc.idx
	}
	return c.idx + (mx.reorderTop.idx - cc.idx)
}

@ 분기 명령을 처리할 수 있는 기능 장치가 하나보다 많고 둘이 동시에 잘못된 예측을 알아채면,
또는 한 장치가 인터럽트를 만드는 바로 그때 다른 장치가 잘못된 예측을 알아채면, 조정이 일어나서
그 가운데 가장 뜨거운 것만 실제로 더 차가운 명령들의 발행을 취소한다고 가정한다.

발행이 취소되는 명령에서 투기로 한 |bpTable|의 변경은 되돌리지 않는다. 둘 이상의 활성 코루틴이
같은 |bpTable| 항목을 고치는 경우도 걱정하지 않는다. 결국 |bpTable|은 실제 계산의 일부가
아니라 발견적 방법일 뿐이다. 예측이 틀렸음을 알게 된 경우에만 |bpTable|을 바로잡아서, 나중에
같은 실수를 덜 하게 한다.

@<잘못된 분기 예측에서...@>=
i = mx.issuedBetween(data, mx.cool)
if i < mx.deissues {
	pc = lDie
	continue
}
mx.deissues = i
mx.oldTail, mx.tail = mx.head, mx.head // 가져오기 버퍼를 비운다
mx.resuming = 0
@<가져오기 코루틴을 다시 시작한다@>
mx.instPtr = spec{o: data.goLoc.o}
if data.loc&signBit == 0 {
	if mx.instPtr.o&signBit != 0 {
		data.interrupt |= pBit
	} else {
		data.interrupt &^= pBit
	}
}
if mx.bpTable != nil {
	mx.bpTable[data.x.o>>32] = int8(data.x.o) // 이것이 넣었어야 할 값이다
	if mx.verbose&showPredBit != 0 {
		mx.printf(" mispredicted ")
		mx.printOcta(data.loc)
		l := Tetra(data.x.o)
		mx.printf("; bp[%x]=%d\n", Tetra(data.x.o>>32),
			int32(l-(l&Tetra(mx.bpNpower))<<1))
	}
}
if j != 0 {
	mx.coolHist = data.hist<<1 + 1
} else {
	mx.coolHist = data.hist << 1
}

@ @<함수들@>=
func (mx *machine) printStats() {
	if mx.bpTable != nil {
		mx.printf("Predictions: %d in agreement, %d in opposition; %d good, %d bad\n",
			mx.bpOkStat, mx.bpRevStat, mx.bpGoodStat, mx.bpBadStat)
	} else {
		mx.printf("Predictions: %d good, %d bad\n", mx.bpGoodStat, mx.bpBadStat)
	}
	mx.printf("Instructions issued per cycle:\n")
	for j := 0; j <= mx.dispatchMax; j++ {
		mx.printf("  %d   %d\n", j, mx.dispatchStat[j])
	}
}

@* 캐시 메모리. 이제 \MMIX의 MMU, 곧 메모리 관리 장치를 생각할 때가 되었다. 기계의 이 부분은
계산 장치들로 데이터를 가져가고 가져오는 중대한 문제를 다룬다. RISC 아키텍처에서 주 메모리와
컴퓨터 레지스터 사이의 모든 상호 작용은 적재와 저장 명령으로 지정한다. 그러니 메모리 접근은 더
복잡한 상호 작용이 있는 기계보다 훨씬 다루기 쉽다. 그러나 잘하려면 메모리 관리는 여전히 어렵다.
주 메모리는 대개 레지스터보다 훨씬 느린 속도로 움직이기 때문이다. \MMIX의 고속 구현은 가장
중요한 데이터를 쓰기 쉽게 두려고 중간 저장소인 ``캐시''를 둔다. 세부를 모두 따지면 캐시
관리는 복잡해질 수 있다.
(이를테면 Hennessy와 Patterson의 {\sl Computer Architecture\/} 제2판 5장을 보라.)
@^Hennessy, John LeRoy@>
@^Patterson, David Andrew@>
@^caches@>

이 시뮬레이터는 레지스터와 메모리 사이에 보조 캐시를 셋까지 두도록 설정할 수 있다. 명령을
위한 I-캐시, 데이터를 위한 D-캐시, 그리고 명령과 데이터 모두를 위한 S-캐시다. S-캐시는
{\it 2차 캐시\/}라고도 부르는데, I-캐시와 D-캐시가 둘 다 있을 때만 지원된다. 캐시마다 접근
시간을 따로 정할 수 있다. 이를테면 I-캐시나 D-캐시의 데이터는 한두 클럭 사이클 만에 레지스터로
보낼 수 있지만, S-캐시의 접근 시간은 이를테면 5사이클일 수 있고, 주 메모리에는 20사이클 이상이
걸릴 수 있다고 가정할 수 있다. 우리의 투기적 파이프라인에는 적재와 저장 명령을 다루는 기능 장치가
많이 있을 수 있지만, 한 번에 한 적재나 저장 명령만 D-캐시나 S-캐시나 주 메모리를 고칠 수 있다.
(그러나 D-캐시에는 읽기 포트가 여럿 있을 수 있다. 더욱이 재정렬 버퍼와 D-캐시 사이에 데이터가
오가는 동안 S-캐시와 메모리 사이에서 데이터가 오갈 수도 있다.)

선택할 수 있는 I-캐시, D-캐시, S-캐시 말고도, 가상 주소를 물리 주소로 바꾸는 데 필요한
IT-캐시와 DT-캐시라는 캐시가 반드시 있다. 변환 캐시는 흔히 ``변환 참조 버퍼(translation
@^TLB@>
@^translation caches@>
lookaside buffer)'' 곧 TLB라고 부르지만, 우리는 I-캐시와 거의 같은 방식으로 구현하므로
캐시라고 부른다.

@ 블록마다 $2^b$~바이트이고 연관도가~$2^a$인 캐시를 생각하자. 여기서 $b\ge3$이고 $a\ge0$이다.
I-캐시, D-캐시, S-캐시는 주 메모리의 일부인 것처럼 48비트 물리 주소로 주소를 지정한다. 그러나
IT와 DT 캐시는 64비트 열쇠로 주소를 지정한다. 이 열쇠는 가상 주소에서 아래 $s$비트를 지우고
$n$의 값을 넣어서 얻는데, 페이지 크기~$s$와 프로세스 번호~$n$은 rV에 있다. 우리는 모든 캐시가
64비트 열쇠로 주소를 지정한다고 보아서, 두 경우를 같은 기본 방법으로 다룬다.

64비트 열쇠가 주어지면, 아래 $b$~비트는 무시하고 그다음 $c$~비트로 {\it 캐시 집합\/}의 주소를
정한다. 그러면 나머지 $64-b-c$비트가 그 집합의 {\it 태그\/} $2^a$개 가운데 하나와 맞아야 한다.
매개변수가 $a=0$인 경우는 이른바 {\it 직접 사상\/} 캐시에 해당하고, $c=0$인 경우는 이른바 {\it 완전 연관\/}
캐시에 해당한다. 블록 $2^a$개씩인 집합이 $2^c$개 있고 블록마다 $2^b$바이트이면, 캐시에는 태그에
필요한 공간 말고 $2^{a+b+c}$바이트의 데이터가 들어 있다. 변환 캐시는 $b=3$이고, 대개 $c=0$이기도
하다.

태그가 지정된 비트와 맞으면 캐시에 ``적중''한 것이어서, 거기 있는 데이터를 쓰거나 고칠 수
있다. 그렇지 않으면 ``놓친'' 것이어서, 아마 캐시 블록 하나를 찾는 항목이 든 블록으로 바꾸고 싶을
것이다. 바꾸려고 고른 항목을 {\it 희생자\/}라고 부른다. 캐시가 직접 사상이면 희생자는 정해져
있다. 그러나 $a>0$이어서 $2^a$개 항목 가운데서 골라야 할 때는 희생자를 고르는 네 가지 전략을
쓸 수 있다.

\smallskip\textindent{$\bullet$} ``무작위'' 선택은 시계의 가장 아래 $a$~비트를 떼어 내서
희생자를 고른다.

\smallskip\textindent{$\bullet$} ``차례'' 선택은 잇단 시도마다 0, 1, \dots, $2^a-1$, 0, 1,
\dots, $2^a-1$, 0, \dots을 고른다.

\smallskip\textindent{$\bullet$} ``LRU(가장 오래전에 쓴 것)'' 선택은, 항목들을 앞서 쓴
뒤로 지난 시간의 역순으로 순위를 매겼을 때 꼴찌인 희생자를 고른다.

\smallskip\textindent{$\bullet$} ``유사 LRU'' 선택은 하드웨어로 구현하기 더 쉬운, LRU의 거친
근사로 희생자를 고른다. 비트 표 $r_1\ldots r_{2^a-1}$이 필요하다. 집합에서 이진 주소가
$(i_1\ldots i_a)_2$인 항목을 쓸 때마다 비트 표를 다음과 같이 고친다.
$$r_1\gets1-i_1,\quad r_{1i_1}\gets1-i_2,\quad\ldots,\quad
r_{1i_1\ldots i_{a-1}}\gets1-i_a;$$
여기서 $r$의 첨자는 이진수다. (이를테면 $a=3$일 때 원소 $(010)_2$를 쓰면 $r_1\gets1$,
$r_{10}\gets0$, $r_{101}\gets1$이 된다. 여기서 $r_{101}$은 $r_5$와 같은 뜻이다.) 희생자를
고르려면 $l\gets1$에서 시작해서 $l\gets2l+r_l$을 $a$번 거듭한다. 그런 다음 원소 $l-2^a$를
고른다. 매개변수가 $a=1$이면 이 방법은 LRU와 같다. 매개변수가 $a=2$인 이 방법은 Intel 80486 칩에 구현되었다.

@<타입 정의@>=
type replacePolicy int
@#
const (
	random    replacePolicy = iota
	serial
	pseudoLRU
	lru
)

@ 캐시에는 ``희생자'' 영역이 있을 수도 있다. 여기에는 주 캐시 영역에서 빼낸 마지막 $2^v$개의
희생자 블록이 들어 있다. 희생자 영역은 지정된 캐시 집합과 나란히 찾을 수 있으므로, 찾기를
늦추지 않으면서 적중할 확률을 높인다. 세 가지 교체 방침 모두를 희생자 캐시에도 쓸 수 있다.

@ 캐시에는 {\it 알갱이\/} $2^g$도 있다. 여기서 $b\ge g\ge3$이다. 이것은 캐시 블록마다 $2^{b-g}$개의
``더러움 비트''를 둔다는 뜻이다. 이 비트들은 메모리에서 마지막으로 읽은 뒤로 바뀌었을지도
모르는 $2^g$바이트 무리를 가리킨다. 그러니 $g=b$이면 캐시 블록 전체가 더럽거나 깨끗하고, $g=3$이면
옥타바이트마다 더러운지를 따로 관리한다.

캐시 블록의 전부나 일부에 새 데이터를 쓸 때 쓸 수 있는 방침은 둘이다. {\it 즉시 쓰기\/}를 할 수
있다. 새 데이터를 모두 곧바로 메모리로 보내고 아무것도 더럽다고 표시하지 않는다는 뜻이다. 또는
{\it 나중 쓰기\/}를 할 수 있다. 꼭 필요할 때만 캐시에서 메모리를 고친다는 뜻이다. 더욱이 {\it
쓰기 할당\/}을 할 수 있다. 쓰는 캐시 블록을 놓쳐서 그것을 먼저 가져와야 하더라도 새 데이터를
캐시에 둔다는 뜻이다. 또는 {\it 쓰기 우회\/}를 할 수 있다. 새 데이터가 이미 있는 캐시 블록의
일부일 때만 그것을 둔다는 뜻이다.

(이 논의에서 ``메모리''는 ``메모리 계층의 다음 단계''를 줄여 말한 것이다. S-캐시가 있으면
I-캐시와 D-캐시는 새 데이터를 메모리가 아니라 S-캐시에 쓴다. I-캐시, IT-캐시, DT-캐시는 읽기
전용이므로 이 절에서 말한 기능이 필요 없다. 더욱이 D-캐시와 S-캐시는 알갱이가 같다고 가정할 수
있다.)

@<상수@>=
const (
	writeBack  = 1 // 즉시 쓰기가 아니면 이것을 쓴다
	writeAlloc = 2 // 쓰기 우회가 아니면 이것을 쓴다
)

@ 앞에서 보았듯이 여러 종류의 캐시를 흉내 낼 수 있다. 캐시는 \KW{cache} 구조체로 나타내는데,
여기에는 \KW{cacheset} 구조체의 배열이 들어 있고, 그 안에는 개별 블록을 위한 \KW{cacheblock}
구조체의 배열이 들어 있다. 우리는 더러움 비트마다 한 바이트를 쓰고, LRU 처리 등을 위한 |rank|
필드에는 정수 한 낱말을 쓴다. 이 시뮬레이터에서는 메모리 절약보다 단순함이 더 중요하다.

보충: 필드 |pos|는 옮긴이가 덧붙인 것으로, 집합 안에서 이 블록의 색인이다. 원본은 이 값을
포인터의 차로 얻었다. 블록을 맞바꿀 때는 태그와 데이터만 바꾸고 블록 자체는 그 자리에 있으므로
|pos|는 변하지 않는다. 원본은 더러움 비트를 |char|로 담았는데, 여기서는 |bool|이다.

@<타입 정의@>=
type cacheblock struct {
	tag   Octa   // 캐시 블록 주소에 들어가지 않는 열쇠의 비트들
	dirty []bool // 알갱이마다 하나씩 있는 더러움 비트 $2^{g-b}$개의 배열
	data  []Octa // 옥타바이트 $2^{b-3}$개의 배열, 곧 캐시 블록의 데이터
	rank  int    // |random|이 아닌 방침을 위한 보조 정보
	pos   int    // 집합 안의 위치
}
@#
type cacheset = []cacheblock // 블록 $2^a$개나 $2^v$개의 배열
@#
type cache struct {
	a, b, c, g, v            int           // 연관도, 블록 크기, 집합 수, 알갱이, 희생자 크기의 로그
	aa, bb, cc, gg, vv       int           // 연관도, 블록 크기, 집합 수, 알갱이, 희생자 크기(모두 2의 거듭제곱)
	tagmask                  int           // $-2^{b+c}$
	repl, vrepl              replacePolicy // 희생자와 희생자의 희생자를 고르는 방법
	mode                     int           // 선택 사항 |writeBack|과 |writeAlloc|
	accessTime               int           // 적중인지 알기까지의 사이클
	copyInTime               int           // 새 블록을 캐시에 복사해 넣는 사이클
	copyOutTime              int           // 옛 블록을 캐시에서 복사해 내는 사이클
	set                      []cacheset    // 캐시 블록 배열의 집합 $2^c$개의 배열
	victim                   cacheset      // 있다면, 희생자 캐시
	filler                   coroutine     // 새 블록을 캐시에 복사해 넣는 코루틴
	fillerCtl                control       // 그 제어 블록
	flusher                  coroutine     // 캐시의 더러운 옛 데이터를 쓰는 코루틴
	flusherCtl               control       // 그 제어 블록
	inbuf                    cacheblock    // 채우기는 여기서 온다
	outbuf                   cacheblock    // 쏟아 내기는 여기로 간다
	lock                     lockvar       // 캐시를 크게 바꾸는 동안 0이 아니다
	fillLock                 lockvar       // 채우는 코루틴이 데이터를 돌려주어야 하면 0이 아니다
	ports                    int           // 몇 개의 코루틴이 캐시를 읽을 수 있는가?
	reader                   []coroutine   // 동시에 읽을지도 모르는 코루틴들의 배열
	name                     string        // 이를테면 |"Icache"|
}

@ @<기계의 상태@>=
Icache, Dcache, Scache, ITcache, DTcache *cache

@ 이제 캐시 관리를 위한 기본 서브루틴들을 정의할 준비가 되었다. 주어진 캐시 블록이 더러운지
검사하는 사소한 루틴부터 시작하자.

@<함수들@>=
func isDirty(c *cache, p *cacheblock) bool {
	for j, d := 0, 0; j < c.bb; j, d = j+c.gg, d+1 {
		if p.dirty[d] {
			return true
		}
	}
	return false
}

@ 진단을 위해 캐시 블록 전체를 보이고 싶을 수도 있다.

@<함수들@>=
func (mx *machine) printCacheBlock(p *cacheblock, c *cache) {
	b, g := c.bb>>3, c.gg>>3
	mx.printf("%016x: ", p.tag)
	for i, j := 0, 0; j < b; {
		d := byte(' ')
		if p.dirty[i] {
			d = '*'
		}
		mx.printf("%016x%c", p.data[j], d)
		j++
		if j&(g-1) == 0 {
			i++
		}
	}
	mx.printf(" (%d)\n", p.rank)
}

@ @<함수들@>=
func (mx *machine) printCacheLocks(c *cache) {
	if c != nil {
		if c.lock != nil {
			mx.printf("%s locked by %s:%d\n", c.name, c.lock.name, c.lock.stage)
		}
		if c.fillLock != nil {
			mx.printf("%sfill locked by %s:%d\n", c.name, c.fillLock.name, c.fillLock.stage)
		}
	}
}

@ 루틴 |printCache|는 캐시의 내용 전체를 찍는다. 데이터가 엄청나게 많을 수 있지만, 디버깅할
때 아주 쓸모 있을 수 있다. 다행히 디버깅할 때는 작은 캐시가 좋다. 캐시가 꽤 작을 때 흥미로운
경우가 더 자주 생기기 때문이다.

@<함수들@>=
func (mx *machine) printCache(c *cache, dirtyOnly bool) {
	if c != nil {
		what := "Contents"
		if dirtyOnly {
			what = "Dirty blocks"
		}
		mx.printf("%s of %s:", what, c.name)
		if c.filler.next != nil {
			mx.printf(" (filling ")
			if c.name[1] == 'T' {
				mx.printOcta(c.fillerCtl.y.o)
			} else {
				mx.printOcta(c.fillerCtl.z.o)
			}
			mx.printf(")")
		}
		if c.flusher.next != nil {
			mx.printf(" (flushing ")
			mx.printOcta(c.outbuf.tag)
			mx.printf(")")
		}
		mx.printf("\n")
		@<|c|의 캐시 블록을 모두 찍는다@>
	}
}

@ 태그가 무효인 캐시 블록은 자세히 보이라는 요청이 없으면 찍지 않는다.

@<|c|의 캐시 블록을 모두 찍는다@>=
for i := 0; i < c.cc; i++ {
	for j := 0; j < c.aa; j++ {
		if (c.set[i][j].tag&signBit == 0 || mx.verbose&showWholecacheBit != 0) &&
			(!dirtyOnly || isDirty(c, &c.set[i][j])) {
			mx.printf("[%d][%d] ", i, j)
			mx.printCacheBlock(&c.set[i][j], c)
		}
	}
}
for j := 0; j < c.vv; j++ {
	if (c.victim[j].tag&signBit == 0 || mx.verbose&showWholecacheBit != 0) &&
		(!dirtyOnly || isDirty(c, &c.victim[j])) {
		mx.printf("V[%d] ", j)
		mx.printCacheBlock(&c.victim[j], c)
	}
}

@ 루틴 |cleanBlock|은 주어진 캐시 블록을 그냥 초기화한다.

@<함수들@>=
func cleanBlock(c *cache, p *cacheblock) {
	p.tag = sign32 << 32
	for j := 0; j < c.bb>>3; j++ {
		p.data[j] = 0
	}
	for j := 0; j < c.bb>>c.g; j++ {
		p.dirty[j] = false
	}
}

@ 루틴 |zapCache|는 주어진 캐시의 태그를 모두 무효로 만들어서, 사실상 처음 상태로 되돌린다.
태그가 무효일 때는 |dirty| 항목을 아무렇게나 두어도 되지만, 그냥 깔끔하게 하려고 여기서
지운다.

@<함수들@>=
func zapCache(c *cache) {
	for i := 0; i < c.cc; i++ {
		for j := 0; j < c.aa; j++ {
			cleanBlock(c, &c.set[i][j])
		}
	}
	for j := 0; j < c.vv; j++ {
		cleanBlock(c, &c.victim[j])
	}
}

@ 서브루틴 |getReader|는 주어진 캐시에서 쓸 수 있는 읽기 코루틴의 색인을 찾는다. 쓸 수 있는
것이 없으면 음수를 돌려준다.

@<함수들@>=
func getReader(c *cache) int {
	for j := 0; j < c.ports; j++ {
		if c.reader[j].next == nil {
			return j
		}
	}
	return -1
}

@ 서브루틴 |copyBlock(c,p,cc,pp)|는 캐시~|c|의 블록~|p|에서 더러운 항목들을 캐시~|cc|의
블록~|pp|로 복사한다. 이때 목적지 캐시의 블록 크기가 넉넉하다고 가정한다. (다시 말해
|cc.b>=c.b|라고 가정한다.) 또 두 블록의 태그가 맞고, 두 캐시의 알갱이가 같다고 가정한다.

@<함수들@>=
func (mx *machine) copyBlock(c *cache, p *cacheblock, cc *cache, pp *cacheblock) {
	off := int(Tetra(p.tag) & Tetra(cc.bb-1))
	if c.g != cc.g || p.tag>>32 != pp.tag>>32 || Tetra(p.tag)-Tetra(off) != Tetra(pp.tag) {
		mx.panic(confusion("copy block"))
	}
	for j, jj := 0, off>>c.g; j < c.bb>>c.g; j, jj = j+1, jj+1 {
		if p.dirty[j] {
			pp.dirty[jj] = true
			for i, ii, lim := j<<(c.g-3), jj<<(c.g-3), (j+1)<<(c.g-3); i < lim; i, ii = i+1, ii+1 {
				pp.data[ii] = p.data[i]
			}
		}
	}
}

@ 서브루틴 |chooseVictim|은 캐시~집합을 바꿔야 할 때 바꿀 희생자를 고른다.
방침 |policy|가 |pseudoLRU|이면 $r$~표를 구현하는 데 |rank| 필드의 한 비트만 있으면 되고,
|policy=random|이면 |rank|가 아예 필요 없다. 물론 |policy=serial|을 구현하는 데는 $a$비트 계수기를
쓴다. 나머지 경우 |policy=lru|에는 $a$비트 |rank| 필드가 필요하다. 가장 오래전에 쓴 항목의 순위는~0이고,
가장 최근에 쓴 항목의 순위는~$2^a-1=|aa|-1$이다.

@<함수들@>=
func (mx *machine) chooseVictim(s cacheset, aa int, policy replacePolicy) *cacheblock {
	switch policy {
	case random:
		return &s[int(Tetra(mx.ticks))&(aa-1)]
	case serial:
		l := s[0].rank
		s[0].rank = (l + 1) & (aa - 1)
		return &s[l]
	case lru:
		for k := range aa {
			if s[k].rank == 0 {
				return &s[k]
			}
		}
		mx.panic(confusion("lru victim")) // 무슨 일인가? 순위가 0인 것이 없다
	case pseudoLRU:
		l := 1
		for m := aa >> 1; m != 0; m >>= 1 {
			l = l + l + s[l].rank
		}
		return &s[l-aa]
	}
	return nil
}

@ 서브루틴 |noteUsage|는 캐시 집합의 특정 블록이 이제 쓰이고 있다는 사실을 기록하도록 |rank|
항목들을 고친다.

@<함수들@>=
func noteUsage(l *cacheblock, s cacheset, aa int, policy replacePolicy) {
	if aa == 1 || policy <= serial {
		return
	}
	if policy == lru {
		r := l.rank
		for k := range aa {
			if s[k].rank > r {
				s[k].rank--
			}
		}
		l.rank = aa - 1
	} else { // |policy==pseudoLRU|
		r := l.pos
		for j, m := 1, aa>>1; m != 0; m >>= 1 {
			if r&m != 0 {
				s[j].rank = 0
				j = j + j + 1
			} else {
				s[j].rank = 1
				j = j + j
			}
		}
	}
}

@ 서브루틴 |demoteUsage|는 |noteUsage|의 반대쯤 된다. 주어진 블록의 순위를 {\it 가장 오래전에\/}
쓴 것으로 바꾼다.

@<함수들@>=
func demoteUsage(l *cacheblock, s cacheset, aa int, policy replacePolicy) {
	if aa == 1 || policy <= serial {
		return
	}
	if policy == lru {
		r := l.rank
		for k := range aa {
			if s[k].rank < r {
				s[k].rank++
			}
		}
		l.rank = 0
	} else { // |policy==pseudoLRU|
		r := l.pos
		for j, m := 1, aa>>1; m != 0; m >>= 1 {
			if r&m != 0 {
				s[j].rank = 1
				j = j + j + 1
			} else {
				s[j].rank = 0
				j = j + j
			}
		}
	}
}

@ 루틴 |cacheSearch|는 주어진 캐시에서 주어진 열쇠 $\alpha$를 찾아서, 적중하면 캐시 블록을
돌려주고 그렇지 않으면~|nil|을 돌려준다. 적중하면 블록을 찾은 집합을 |hitSet|에 넣는다.
희생자 영역에서 찾을 때는 태그의 비트를 더 많이 확인해야 한다는 데 주목하라.

보충: 원본의 매크로 |cache_addr(c,alf)|는 메서드 |cacheAddr|이다.

@<함수들@>=
func (c *cache) cacheAddr(alf Octa) cacheset {
	return c.set[(Tetra(alf)&^Tetra(c.tagmask))>>c.b]
}
@#
func (mx *machine) cacheSearch(c *cache, alf Octa) *cacheblock {
	s := c.cacheAddr(alf) // |alf|에 해당하는 집합
	for k := 0; k < c.aa; k++ {
		if p := &s[k]; (Tetra(p.tag)^Tetra(alf))&Tetra(c.tagmask) == 0 && p.tag>>32 == alf>>32 {
			mx.hitSet = s
			return p
		}
	}
	s = c.victim
	if s == nil {
		return nil // 캐시를 놓쳤고, 희생자 영역도 없다
	}
	for k := 0; k < c.vv; k++ {
		if p := &s[k]; (Tetra(p.tag)^Tetra(alf))&Tetra(-c.bb) == 0 && p.tag>>32 == alf>>32 {
			mx.hitSet = s
			return p
		}
	}
	return nil // 두 번 놓쳤다
}

@ 보충: 원본은 |hit_set|과 희생자 캐시를 포인터로 견주었다. 슬라이스는 첫 원소의 주소로
견준다.

@<기계의 상태@>=
hitSet cacheset

@ @<함수들@>=
func sameSet(a, b cacheset) bool {
	return len(a) > 0 && len(b) > 0 && &a[0] == &b[0]
}

@ 호출 |p=cacheSearch(c,alf)|가 적중한 바로 뒤에 |useAndFix(c,p)|를 부르면, 캐시~|c|를 고쳐서
열쇠~|alf|를 쓴 것을 기록한다. 희생자 영역에서 적중하면, 캐시~|c|의 |filler| 루틴이 활성이
아닌 한 그 캐시 블록을 주 영역으로 옮긴다. (옮겼을 수도 있는) 캐시 블록의 포인터를 돌려준다.

@<함수들@>=
func (mx *machine) useAndFix(c *cache, p *cacheblock) *cacheblock {
	if !sameSet(mx.hitSet, c.victim) {
		noteUsage(p, mx.hitSet, c.aa, c.repl)
	} else {
		noteUsage(p, mx.hitSet, c.vv, c.vrepl) // 희생자 캐시에서 찾았다
		if c.filler.next == nil {
			s := c.cacheAddr(p.tag)
			q := mx.chooseVictim(s, c.aa, c.repl)
			noteUsage(q, s, c.aa, c.repl)
			swapBlocks(p, q)
			return q
		}
	}
	return p
}

@ 데이터를 복사하는 대신 캐시의 \KW{cacheblock} 구조 안에 있는 포인터들을 맞바꿀 수 있다.
다만 그 포인터들이 다른 데이터 구조로 새어 나가지 않도록 조심해야 한다.

@<함수들@>=
func swapBlocks(p, q *cacheblock) {
	p.tag, q.tag = q.tag, p.tag
	p.dirty, q.dirty = q.dirty, p.dirty
	p.data, q.data = q.data, p.data
}

@ 루틴 |demoteAndFix|는 |useAndFix|와 비슷하지만, 찾은 데이터의 순위를 올리고 싶지 않을 때
쓴다.

@<함수들@>=
func (mx *machine) demoteAndFix(c *cache, p *cacheblock) *cacheblock {
	if !sameSet(mx.hitSet, c.victim) {
		demoteUsage(p, mx.hitSet, c.aa, c.repl)
	} else {
		demoteUsage(p, mx.hitSet, c.vv, c.vrepl)
	}
	return p
}

@ 서브루틴 |loadCache(c,p)|는 |c.lock|이 정해져 있고 |c.inbuf|가 캐시 블록~|p|에 넣을 깨끗한
데이터로 채워진 순간에 부른다.

@<함수들@>=
func (mx *machine) loadCache(c *cache, p *cacheblock) {
	for i := 0; i < c.bb>>c.g; i++ {
		p.dirty[i] = false
	}
	p.data, c.inbuf.data = c.inbuf.data, p.data
	p.tag = c.inbuf.tag
	mx.hitSet = c.cacheAddr(p.tag)
	mx.useAndFix(c, p) // |p|는 옮겨지지 않는다
}

@ 서브루틴 |flushCache(c,p,keep)|는 |c.flusher.next=nil|인 ``조용한'' 순간에 부른다. 이것은
캐시 블록~|p|를 |c.outbuf|에 넣고 |c.flusher| 코루틴을 띄운다. 그 코루틴은 데이터를 메모리
계층의 아래 단계들로 보내는 일을 맡는다. 캐시 블록~|p|는 깨끗하다고 표시한다.

@<함수들@>=
func (mx *machine) flushCache(c *cache, p *cacheblock, keep bool) {
	c.outbuf.tag = p.tag
	if keep { // |p|의 데이터를 보존해야 하는가?
		copy(c.outbuf.data[:c.bb>>3], p.data)
	} else {
		c.outbuf.data, p.data = p.data, c.outbuf.data
	}
	c.outbuf.dirty, p.dirty = p.dirty, c.outbuf.dirty
	for j := 0; j < c.bb>>c.g; j++ {
		p.dirty[j] = false
	}
	c.outbuf.rank = c.bb // 유효한 바이트가 이만큼 있다
	mx.startup(&c.flusher, c.copyOutTime) // 중단되지 않는다
}

@ 루틴 |allocSlot|은 캐시를 놓친 뒤 새 정보를 캐시에 넣고 싶을 때 부른다. 이것은 새 정보를 넣을
주 영역의 캐시 블록의 포인터를 돌려준다. 그 캐시 블록의 태그는 무효가 된다. 부르는 루틴이
때가 되면 그것을 채우고 유효한 태그를 주어야 한다. 루틴 |allocSlot|을 부를 때 캐시의 |filler|
루틴이 활성이면 안 된다.

새 정보를 넣으려면, 바꿀 블록이 더러우면 옛 정보를 메모리 계층의 다음 단계에 써야 할 수도
있다. 그런 경우 캐시가 앞서 버린 블록을 쏟아 내고 있으면 이 루틴은 |nil|을 돌려준다. 그렇지
않으면 |flusher| 코루틴을 스케줄한다.

주어진 열쇠가 우연히 캐시에 있을 때도 이 루틴은 |nil|을 돌려준다. 그런 경우는 드물지만,
다음 시나리오가 보여 주듯이 불가능하지는 않다. DT-캐시의 접근 시간이 5이고 D-캐시의 접근
시간이 1이며, 두 프로세스가 동시에 같은 물리 주소를 찾는다고 하자. 한 프로세스는 DT-캐시에서
적중했지만 D-캐시에서 놓쳐서, D-캐시에서 |allocSlot|을 해 보기 전에 5사이클을 기다린다. 그동안
다른 프로세스는 D-캐시에서 놓쳤지만 DT-캐시를 쓸 필요가 없어서 D-캐시를 고쳐 놓았을 수 있다.

열쇠의 값은 결코 음수가 아니다. 그래서 고른 자리의 태그를 음수로 만들어서 무효로 할 수 있다.

@<함수들@>=
func (mx *machine) allocSlot(c *cache, alf Octa) *cacheblock {
	if mx.cacheSearch(c, alf) != nil {
		return nil
	}
	if c.flusher.next != nil && c.outbuf.tag>>32 == alf>>32 &&
		(Tetra(c.outbuf.tag)^Tetra(alf))&Tetra(-c.bb) == 0 {
		return nil
	}
	s := c.cacheAddr(alf) // |alf|에 해당하는 집합
	var p *cacheblock
	if c.victim != nil {
		p = mx.chooseVictim(c.victim, c.vv, c.vrepl)
	} else {
		p = mx.chooseVictim(s, c.aa, c.repl)
	}
	if isDirty(c, p) {
		if c.flusher.next != nil {
			return nil
		}
		mx.flushCache(c, p, false)
	}
	if c.victim != nil {
		q := mx.chooseVictim(s, c.aa, c.repl)
		swapBlocks(p, q)
		q.tag |= sign32 << 32 // 태그를 무효로 만든다
		return q
	}
	p.tag |= sign32 << 32
	return p
}

@* 모의 메모리. \MMIX의 잠재적으로 거대한 메모리를 어떻게 다루어야 할까? 크기가 $2^{48}$바이트인 배열~$m$을 그냥 선언할 수는 없다. (메모리 사상 입출력을 위해 남겨 둔 $2^{48}$ 이상의 물리 주소도
생각하면, 사실 $2^{63}$바이트까지 필요하다.)

메모리를 특별한 종류의 캐시로 볼 수도 있을 것이다. 모든 접근이 적중해야 하는 캐시다. 이를테면
그런 ``M-캐시''는 블록 $2^a$개가 저마다 다른 태그를 가진 완전 연관 캐시일 수 있다. 태그가
$2^a-1$개보다 많이 필요해질 때까지 시뮬레이션을 이어 갈 수 있을 것이다. 그러나 그러면 미리 정한
$a$의 값이 너무 커서 |cacheSearch| 루틴의 순차 찾기가 너무 느려질 것이다.

대신 메모리를 필요할 때마다 $2^{16}$바이트씩 덩이로 할당하고, 물리 주소가 주어질 때마다 해싱으로
해당 덩이를 찾기로 한다. 주소가 $2^{48}$ 이상이면 사용자가 공급하는 |specRead|와 |specWrite|라는
특별한 루틴을 불러서 읽거나 쓴다. 그렇지 않으면 48비트 주소는 32비트 {\it 덩이 주소\/}와 16비트
{\it 덩이 오프셋\/}으로 이루어진다.

쓰이지 않는 덩이 주소는 이 시뮬레이터에서 공간을 차지하지 않는다. 그러나 이를테면 그런 패턴이
1000개 나타나면, 시뮬레이터는 주 메모리에서 쓰인 부분을 위해 대략 65MB를 동적으로 할당할 것이다.
매개변수 |memChunksMax|는 지원하는 서로 다른 덩이 주소의 최대 수를 정한다. 이 매개변수는 흉내
내는 물리 주소의 범위를 제한하지 않는다. 물리 주소는 \MMIX가 허락하는 256 큰 테라바이트 범위
전체에 걸친다.

@<타입 정의@>=
type chunknode struct {
	tag   Tetra  // 32비트 덩이 주소
	chunk []Octa // |nil|이거나 옥타바이트 $2^{13}$개의 배열
}

@ 매개변수 |hashPrime|은 매개변수 |memChunksMax|보다 큰 소수여야 한다. 두 배보다 넉넉히
크되 그보다 훨씬 크지는 않은 것이 좋다. 사용자가 달리 지정하지 않으면 |MMIX_config|가 기본값
|memChunksMax=1000|과 |hashPrime=2003|으로 정한다.

@<기계의 상태@>=
memChunks    int         // 지금까지 할당한 덩이의 수
memChunksMax int         // 한 번 돌 때 서로 다른 덩이를 이만큼까지
hashPrime    int         // |memChunksMax|보다 크되, 엄청나지는 않다
memHash      []chunknode // 모의 주 메모리

@ 따로 컴파일하는 프로시저 |spec_read()|와 |spec_write()|는 일반 프로시저 |mem_read()|와
|mem_write()|와 같은 호출 관례를 따르되, |size| 매개변수가 더 있다. 이것은 |1<<size|바이트를
읽거나 써야 한다는 것을 지정한다. 보충: 이 둘은 \.{mmixmem.w}에서 정의하는 메서드 |specRead|와
|specWrite|다.

@ 프로그램이 할당하지 않은 덩이에서 읽으려고 하면 값 0을 돌려준다. 원하면 사용자에게 알림도
보낸다.

덩이 주소 0은 늘 맨 먼저 할당한다. 그래서 덩이 태그가 맞으면 |chunk| 포인터가 |nil|이 아니라고
가정할 수 있다.

이 루틴은 찾은 덩이를 |lastH|에 넣는다. 그래서 같은 덩이에 속하는 것을 아는 다른 낱말들을 빨리
읽을 수 있다. 이를 위해 |memHash[hashPrime]|을 0으로 가득 찬 덩이로 두어, 초기화하지 않은
메모리를 나타내는 것이 편리하다.

보충: 원본의 알림에는 줄 바꿈 문자가 없다. 그대로 흉내 낸다.

@<함수들@>=
func (mx *machine) memRead(addr Octa) Octa {
	off := (Tetra(addr) & 0xffff) >> 3
	key := Tetra(addr)&0xffff0000 + Tetra(addr>>32)
	h := int(key % Tetra(mx.hashPrime))
	for ; mx.memHash[h].tag != key; h-- {
		if mx.memHash[h].chunk == nil {
			if mx.verbose&uninitMemBit != 0 {
				mx.errprintf("uninitialized memory read at %016x", addr)
@.uninitialized memory...@>
			}
			h = mx.hashPrime
			break // 0을 돌려줄 것이다
		}
		if h == 0 {
			h = mx.hashPrime
		}
	}
	mx.lastH = h
	return mx.memHash[h].chunk[off]
}

@ @<기계의 상태@>=
lastH int // 가장 최근에 맞은 해시 색인

@ @<함수들@>=
func (mx *machine) memWrite(addr, val Octa) {
	off := (Tetra(addr) & 0xffff) >> 3
	key := Tetra(addr)&0xffff0000 + Tetra(addr>>32)
	h := int(key % Tetra(mx.hashPrime))
	for ; mx.memHash[h].tag != key; h-- {
		if mx.memHash[h].chunk == nil {
			mx.memChunks++
			if mx.memChunks > mx.memChunksMax {
				mx.panic(fmt.Sprintf("More than %d memory chunks are needed",
@.More...chunks are needed@>
					mx.memChunksMax))
			}
			mx.memHash[h].chunk = make([]Octa, 1<<13)
			mx.memHash[h].tag = key
			break
		}
		if h == 0 {
			h = mx.hashPrime
		}
	}
	mx.lastH = h
	mx.memHash[h].chunk[off] = val
}

@ 메모리는 흉내 내는 메모리 버스의 성질에 따라 매개변수 몇 개로 특징지어진다. 매개변수 |busWords|는 동시에 읽거나 쓰는 옥타바이트의 수라고 하자(대개 |busWords|는 1이나~2이고, 2의 거듭제곱이어야
한다). 모두 같은 캐시 블록에 속하는 옥타바이트 |c*busWords|개를 읽거나 쓰는 데 드는 클럭
사이클 수는 각각 |memAddrTime+c*memReadTime|이나 |memAddrTime+c*memWriteTime|이라고 가정한다.

@<기계의 상태@>=
memAddrTime  int     // 메모리 버스로 주소를 보내는 사이클
busWords     int     // 메모리 버스의 폭, 옥타바이트 단위
memReadTime  int     // 주 메모리에서 읽는 사이클
memWriteTime int     // 주 메모리에 쓰는 사이클
memLock      lockvar // 버스가 바쁘면 |nil|이 아니다

@ 메모리에 쓰는 주된 방법 하나는 |flushToMem| 코루틴을 부르는 것이다. S-캐시가 있으면
|Scache.flusher|가, S-캐시는 없고 D-캐시가 있으면 |Dcache.flusher|가 그 코루틴이다.

그런 코루틴을 시작할 때 |data.ptrA|는 |Scache|나~|Dcache|다. 쓸 데이터는 막 그 캐시의 |outbuf|로
복사되었을 것이다.

@<특별한 코루틴의 출발 지점@>=
case flushToMem:
	c = data.ptrA.(*cache)
	pc = flushMemSt + label(data.state)

@ @<특별한 코루틴을 제어하는 경우들@>=
case flushMemSt + 0:
	if mx.memLock != nil {
		return mx.wait(self, 1)
	}
	data.state = 1
	fallthrough
case flushMemSt + 1:
	setLock(self, &mx.memLock)
	data.state = 2
	@<|c.outbuf|의 더러운 데이터를 쓰고 버스를 기다린다@>
case flushMemSt + 2:
	return true // 이것이 |memLock|과 |c.outbuf|를 풀어 준다

@ @<|c.outbuf|의 더러운 데이터를...@>=
{
	del := c.gg >> 3 // 알갱이 하나의 옥타바이트 수
	addr := c.outbuf.tag
	off := int(Tetra(addr)&0xffff) >> 3
	count, first, lastOff := 0, true, 0
	for i, j = 0, 0; j < c.bb>>c.g; j++ {
		ii := i + del
		if !c.outbuf.dirty[j] {
			i = ii
			off += del
			addr += Octa(del << 3)
		} else {
			for i < ii {
				if first {
					count++
					lastOff = off
					first = false
					mx.memWrite(addr, c.outbuf.data[i])
				} else {
					if (off^lastOff)&(-mx.busWords) != 0 {
						count++
					}
					lastOff = off
					mx.memHash[mx.lastH].chunk[off] = c.outbuf.data[i]
				}
				i++
				off++
				addr += 8
			}
		}
	}
	return mx.wait(self, mx.memAddrTime+count*mx.memWriteTime)
}

@* 캐시 전송. S-캐시가 없으면 |Dcache.flusher|가 데이터를 바로 주 메모리로 보낸다는 것을
보았다. 그러나 D-캐시와 S-캐시가 둘 다 있으면 |Dcache.flusher|는 |flushToS| 타입의 더 복잡한
코루틴이다. 이 경우에는 S-캐시 블록이 D-캐시 블록보다 클 수 있다는 사실을 다루어야 한다. 더욱이
S-캐시가 쓰기 우회나 즉시 쓰기 방침을 쓸 수도 있다. 그러나 한 가지 단순하게 해 주는 사실이
도움이 된다. 쏟아 내는 코루틴은 끝까지 돌기 전에는 중단되지 않는다는 것을 우리는 안다.

Alpha 21164 같은 어떤 기계에는 S-캐시와 메모리 사이에 캐시가 하나 더 있는데, B-캐시(``예비
@^Alpha computers@>
캐시'')라고 부른다. 여기서 쓴 논리를 넓혀서 B-캐시도 흉내 낼 수 있겠지만, 이 프로그램의 그런
확장은 관심 있는 독자에게 맡긴다.

@<특별한 코루틴의 출발 지점@>=
case flushToS:
	c = data.ptrA.(*cache)
	blockDiff = mx.Scache.bb - c.outbuf.rank
	p, _ = data.ptrB.(*cacheblock)
	pc = flushSSt + label(data.state)

@ @<|step|의 다른 지역 변수@>=
blockDiff int // |flushToS|에서 더 읽어야 할 바이트 수

@ @<특별한 코루틴을 제어하는 경우들@>=
case flushSSt + 0:
	if mx.Scache.lock != nil {
		return mx.wait(self, 1)
	}
	data.state = 1
	fallthrough
case flushSSt + 1:
	setLock(self, &mx.Scache.lock)
	sp := mx.cacheSearch(mx.Scache, c.outbuf.tag)
	data.ptrB = sp
	if sp != nil {
		data.state = 4
	} else if mx.Scache.mode&writeAlloc != 0 {
		if blockDiff != 0 {
			data.state = 2
		} else {
			data.state = 3
		}
	} else {
		data.state = 6
	}
	return mx.wait(self, mx.Scache.accessTime)
case flushSSt + 2:
	@<|Scache.inbuf|를 메모리의 깨끗한 데이터로 채운다@>

@ @<특별한 코루틴을 제어하는 경우들@>=
case flushSSt + 3:
	@<S-캐시에 자리 |p|를 할당한다@>
	if blockDiff != 0 {
		@<|Scache.inbuf|를 자리 |p|로 복사한다@>
	} else {
		for j = 0; j < mx.Scache.bb>>3; j++ {
			p.data[j] = c.outbuf.data[j]
		}
	}
	for j = 0; j < mx.Scache.bb>>mx.Scache.g; j++ {
		p.dirty[j] = false
	}
	fallthrough
case flushSSt + 4:
	mx.copyBlock(c, &c.outbuf, mx.Scache, p)
	mx.hitSet = mx.Scache.cacheAddr(c.outbuf.tag)
	mx.useAndFix(mx.Scache, p) // |p|는 옮겨지지 않는다
	data.state = 5
	return mx.wait(self, mx.Scache.copyInTime)
case flushSSt + 5:
	if mx.Scache.mode&writeBack == 0 { // 즉시 쓰기
		if mx.Scache.flusher.next != nil {
			return mx.wait(self, 1)
		}
		mx.flushCache(mx.Scache, p, true)
	}
	return true
case flushSSt + 6:
	@<S-캐시로 쏟아 낼 때 쓰기 우회를 다룬다@>

@ @<S-캐시에 자리 |p|를...@>=
if mx.Scache.filler.next != nil {
	return mx.wait(self, 1) // 어쩌면 불필요한 조심일지도?
}
p = mx.allocSlot(mx.Scache, c.outbuf.tag)
if p == nil {
	return mx.wait(self, 1)
}
data.ptrB = p
p.tag = c.outbuf.tag&^0xffffffff | Octa(Tetra(c.outbuf.tag)&Tetra(-mx.Scache.bb))

@ 모자란 |blockDiff|바이트만 읽으면 되지만, 모두 읽고 필요했던 것만 값을 치르는 편이 쉽다.

@<|Scache.inbuf|를 메모리의...@>=
{
	count := blockDiff >> 3
	if mx.memLock != nil {
		return mx.wait(self, 1)
	}
	addr := c.outbuf.tag&^0xffffffff | Octa(Tetra(c.outbuf.tag)&Tetra(-mx.Scache.bb))
	off := int(Tetra(addr)&0xffff) >> 3
	for j = 0; j < mx.Scache.bb>>3; j++ {
		if j == 0 {
			mx.Scache.inbuf.data[j] = mx.memRead(addr)
		} else {
			mx.Scache.inbuf.data[j] = mx.memHash[mx.lastH].chunk[j+off]
		}
	}
	setLock(&mx.memLocker, &mx.memLock)
	delay := mx.memAddrTime + (count+mx.busWords-1)/mx.busWords*mx.memReadTime
	mx.startup(&mx.memLocker, delay)
	data.state = 3
	return mx.wait(self, delay)
}

@ @<|Scache.inbuf|를 자리 |p|로...@>=
p.data, mx.Scache.inbuf.data = mx.Scache.inbuf.data, p.data

@ 여기서는 알갱이가~8이라고 가정한다.

@<S-캐시로 쏟아 낼 때...@>=
if mx.Scache.flusher.next != nil {
	return mx.wait(self, 1)
}
mx.Scache.outbuf.tag = c.outbuf.tag&^0xffffffff |
	Octa(Tetra(c.outbuf.tag)&Tetra(-mx.Scache.bb))
for j = 0; j < mx.Scache.bb>>mx.Scache.g; j++ {
	mx.Scache.outbuf.dirty[j] = false
}
mx.copyBlock(c, &c.outbuf, mx.Scache, &mx.Scache.outbuf)
mx.startup(&mx.Scache.flusher, mx.Scache.copyOutTime)
return true

@ S-캐시는 |fillFromMem| 코루틴을 불러서 메모리에서 새 데이터를 얻는다. S-캐시가 없으면
I-캐시나 D-캐시도 |fillFromMem| 코루틴을 부를 수 있다. 그런 코루틴을 부를 때 그것은 |memLock|을
쥐고 있고, 부른 쪽은 잠들어 있다. 물리 메모리 주소는 |data.z.o|에 있고, |data.ptrA|는 |Icache|나
|Dcache|나 |Scache|를 가리킨다. 더욱이 |data.ptrB|는 그 캐시 안의 블록을 가리키는데, 루틴
|allocSlot|이 정한 것이다. 이 코루틴은 지정된 메모리 위치의 내용을 읽는 것을 흉내 내서, 그 결과를
부른 쪽 제어 블록의 |x.o| 필드에 넣고 부른 쪽을 깨운다. 그런 다음 캐시의 |inbuf|를 채우고,
마침내 지정된 캐시 블록을 채운 뒤 부른 쪽을 다시 깨운다.

캐시를 |c=data.ptrA|라고 하자. 그러면 부른 쪽은, 이 변수가 |nil|이 아니라면 |c.fillLock|이다. 그러나
부른 쪽이 깨어나거나 데이터를 받고 싶지 않을 수도 있다(이를테면 중단되었다면). 그런 경우에는
|c.fillLock|이~|nil|이 된다. 채우기 동작은 깨우는 호출 없이 계속된다. 캐시가 |c=Scache|이면 S-캐시는
잠겨 있을 것이고 부른 쪽은 중단되지 않았을 것이다.

@<특별한 코루틴의 출발 지점@>=
case fillFromMem:
	c = data.ptrA.(*cache)
	cc = c.fillLock
	pc = fillMemSt + label(data.state)

@ @<특별한 코루틴을 제어하는 경우들@>=
case fillMemSt + 0:
	data.x.o = mx.memRead(data.z.o)
	if cc != nil {
		cc.ctl.x.o = data.x.o
		mx.awaken(cc, mx.memReadTime)
	}
	data.state = 1
	@<데이터를 |c.inbuf|로 읽고 버스를 기다린다@>
case fillMemSt + 1:
	releaseLock(self, &mx.memLock)
	data.state = 2
	fallthrough
case fillMemSt + 2:
	if c != mx.Scache {
		if c.lock != nil {
			return mx.wait(self, 1)
		}
		setLock(self, &c.lock)
	}
	if cc != nil {
		mx.awaken(cc, c.copyInTime) // 두 번째로 깨운다
	}
	mx.loadCache(c, data.ptrB.(*cacheblock))
	data.state = 3
	return mx.wait(self, c.copyInTime)
case fillMemSt + 3:
	return true

@ 캐시의 크기가 메모리 버스보다 크지 않으면 한 사이클을 더 기다린다. 그래서 깨우는 호출이 두
번 있게 된다.

@<데이터를 |c.inbuf|로...@>=
{
	c.inbuf.tag = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-c.bb))
	count, off := c.bb>>3, int(Tetra(c.inbuf.tag)&0xffff)>>3
	for i = 0; i < count; i, off = i+1, off+1 {
		c.inbuf.data[i] = mx.memHash[mx.lastH].chunk[off]
	}
	if count <= mx.busWords {
		return mx.wait(self, 1+mx.memReadTime)
	}
	return mx.wait(self, count/mx.busWords*mx.memReadTime)
}

@ 코루틴 |fillFromS|는 |fillFromMem|과 관례가 같지만, 데이터가 S-캐시에 있으면 거기서 곧바로
온다. S-캐시가 있으면 이것이 I-캐시와 D-캐시의 |filler| 코루틴이다.

보충: 원본의 이름표 |S_non_miss|는 상태~2의 |case|와 상태~3의 |case| 사이에 있었다.

@<특별한 코루틴의 출발 지점@>=
case fillFromS:
	c = data.ptrA.(*cache)
	cc = c.fillLock
	p, _ = data.ptrC.(*cacheblock)
	pc = fillSSt + label(data.state)

@ @<지점 이름@>=
lSNonMiss // 원본의 |S_non_miss|

@ @<특별한 코루틴을 제어하는 경우들@>=
case fillSSt + 0:
	p = mx.cacheSearch(mx.Scache, data.z.o)
	if p != nil {
		pc = lSNonMiss
		continue
	}
	data.state = 1
	fallthrough
case fillSSt + 1:
	@<S-캐시를 채우는 코루틴을 띄운다@>
	data.state = 2
	return mx.sleep(self)
case fillSSt + 2:
	if cc != nil {
		cc.ctl.x.o = data.x.o // 이 데이터는 |Scache.filler|가 공급했다
		mx.awaken(cc, mx.Scache.accessTime) // 우리는 그것을 되돌려 전한다
	}
	data.state = 3
	return mx.sleep(self) // 깨어나면 S-캐시에 우리 데이터가 있을 것이다

@ @<특별한 코루틴을 제어하는 경우들@>=
case lSNonMiss:
	if cc != nil {
		cc.ctl.x.o = p.data[(Tetra(data.z.o)&Tetra(mx.Scache.bb-1))>>3]
		mx.awaken(cc, mx.Scache.accessTime)
	}
	fallthrough
case fillSSt + 3:
	@<|p|의 데이터를 |c.inbuf|로 복사한다@>
	data.state = 4
	return mx.wait(self, mx.Scache.accessTime)
case fillSSt + 4:
	mx.Scache.lock = nil // 우리가 그 잠금을 쥐고 있었다
	data.state = 5
	fallthrough
case fillSSt + 5:
	if c.lock != nil {
		return mx.wait(self, 1)
	}
	setLock(self, &c.lock)
	mx.loadCache(c, data.ptrB.(*cacheblock))
	data.state = 6
	return mx.wait(self, c.copyInTime)
case fillSSt + 6:
	if cc != nil {
		mx.awaken(cc, 1) // 두 번째로 깨운다
	}
	return true

@ 우리는 이미 |Scache.lock|을 쥐고 있지만, 곧 |Scache.fillLock|도 떠맡으려 한다(하나가 다른
하나보다 ``강하다''는 것을 알고서). 잠깐 동안 |Scache.lock|은 우리를 가리키지만 우리는
|Scache.fillLock|을 가리키게 된다. 이 코루틴은 중단될 수 없으므로 이것이 문제를 일으키지는
않는다.

@<S-캐시를 채우는 코루틴을...@>=
if mx.Scache.filler.next != nil || mx.memLock != nil {
	return mx.wait(self, 1)
}
p = mx.allocSlot(mx.Scache, data.z.o)
if p == nil {
	return mx.wait(self, 1)
}
setLock(&mx.Scache.filler, &mx.memLock)
setLock(self, &mx.Scache.fillLock)
data.ptrC = p
mx.Scache.fillerCtl.ptrB = p
mx.Scache.fillerCtl.z.o = data.z.o
mx.startup(&mx.Scache.filler, mx.memAddrTime)

@ S-캐시 블록은 I-캐시나 D-캐시의 블록보다 넓을 수 있으므로, 이 단계의 복사가 아주 사소하지는
않다.

@<|p|의 데이터를 |c.inbuf|로...@>=
{
	c.inbuf.tag = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-c.bb))
	off := int(Tetra(c.inbuf.tag)&Tetra(mx.Scache.bb-1)) >> 3
	for j = 0; j < c.bb>>3; j, off = j+1, off+1 {
		c.inbuf.data[j] = p.data[off]
	}
	releaseLock(self, &mx.Scache.fillLock)
	setLock(self, &mx.Scache.lock)
}

@ D-캐시에 블록마다 $2^b$바이트가 있으면 명령 \.{PRELD} \.{X,\$Y,\$Z}는 $\lfloor{\rm X}/2^b\rfloor$개의
명령을 만들어 낸다. 이 명령들은 캐시가 너무 바쁘지 않으면 블록 $\rm\$Y+\$Z$,
${\rm\$Y}+{\rm\$Z}+2^b$, \dots를 캐시에 미리 적재하려고 한다.

명령 \.{PREGO} \.{X,\$Y,\$Z}와 \.{PREST} \.{X,\$Y,\$Z}에도 비슷한 사정이 적용된다.

@<명령 배정의 특별한 경우들@>=
case preld, prest:
	if mx.Dcache == nil {
		cool.i = noop
		break special
	}
	if int(cool.xx) >= mx.Dcache.bb {
		cool.interim = true
	}
	cool.ptrA = mx.mem.up
case prego:
	if mx.Icache == nil {
		cool.i = noop
		break special
	}
	if int(cool.xx) >= mx.Icache.bb {
		cool.interim = true
	}
	cool.ptrA = mx.mem.up

@ 블록 크기가 64이면, \.{PREST}~\.{200,\$Y,\$Z} 같은 명령은 실제로 명령 넷
\.{PREST}~\.{200,\$Y,\$Z;} \.{PREST}~\.{191,\$Y,\$Z;} \.{PREST}~\.{127,\$Y,\$Z;}
\.{PREST}~\.{63,\$Y,\$Z}로 발행된다. 그러면 가로막기가 일어나도 제대로 다시 시작할 수 있다.
파이프라인에서 명령 \.{PREST}~\.{200,\$Y,\$Z}는 바이트 $\rm\$Y+\$Z+192$부터 $\rm\$Y+\$Z+200$까지,
또는 $\rm\$Y+\$Z$가 64의 배수가 아니면 그보다 적은 바이트에 영향을 주는 것으로 본다. (이 명령들은
귀띔일 뿐이라는 것을 기억하라. 꽤 편리할 때만 이 명령들에 따라 행동한다.)

@<\.{PRELD}나 \.{PREST}의 다음 단계를...@>=
mx.head.inst = (mx.head.inst &^ (Tetra(mx.Dcache.bb-1) << 16)) - 0x10000

@ @<\.{PREGO}의 다음 단계를...@>=
mx.head.inst = (mx.head.inst &^ (Tetra(mx.Icache.bb-1) << 16)) - 0x10000

@ 또 다른 코루틴 |cleanup|은 이따금 불려 나와 D-캐시와 S-캐시에서 더러운 데이터를
치운다. 필드 |i|를 |sync|로 정하고 상태~0에서 시작해서 부르면 모든 것을 청소한다. 필드 |i|를 |syncd|로 정하고 |z.o| 필드에 물리 주소를 넣은 채 상태~4에서 부를 수도 있다. 그러면 그 주소와
관련된 D-캐시나 S-캐시 블록이 더럽지 않게만 한다.

청소한 뒤에도 항목이 캐시에 남아 있기를 바라면 필드 |x.o.h|를 0으로 정해야 한다. 그렇지 않으면
필드 |x.o.h|를 |sign_bit|로 정해야 한다.

청소 코루틴 |cleanup|을 부르는 쪽은 |cleanLock|을 쥐고 있어야 한다. 그 코루틴이 가로막기 때문에 죽으면,
|cleanup| 코루틴은 일찍 끝난다.

D-캐시와 S-캐시에는 |accessTime| 사이클 안에 첫 더러운 블록이 있다면 그것을 알아내는 방법이
있다고 가정한다.

@<기계의 상태@>=
cleanCo   coroutine
cleanCtl  control
cleanLock lockvar

@ @<모든 것을 초기화한다@>=
mx.cleanCo.ctl = &mx.cleanCtl
mx.cleanCo.name = "Clean"
mx.cleanCo.stage = cleanup
mx.cleanCtl.goLoc.o = 4

@ 보충: 원본은 청소할 블록을 찾으면서 이름표 |Dclean_loop|, |Dclean|, |Dclean_inc|와
|Sclean_loop|, |Sclean|, |Sclean_inc| 사이를 |goto|로 오갔다. 이것들이 지점이 된다. 원본의
|Sprep|은 `|Sprep|: |data.state=9|; |case 9|:' 꼴이므로 상태~9의 |case|와 합친다.

@<특별한 코루틴의 출발 지점@>=
case cleanup:
	p, _ = data.ptrB.(*cacheblock)
	pc = cleanupSt + label(data.state)

@ @<지점 이름@>=
lDcleanLoop // 원본의 |Dclean_loop|
lDclean     // 원본의 |Dclean|
lDcleanInc  // 원본의 |Dclean_inc|
lScleanLoop // 원본의 |Sclean_loop|
lSclean     // 원본의 |Sclean|
lScleanInc  // 원본의 |Sclean_inc|

@ @<상수@>=
const lSprep = cleanupSt + 9 // 원본의 |Sprep|

@ @<특별한 코루틴을 제어하는 경우들@>=
@<D-캐시를 위한 상태 0부터 4까지@>
@<S-캐시를 위한 상태 5부터 9까지@>
case cleanupSt + 10:
	return true

@ @<D-캐시를 위한...@>=
case cleanupSt + 0:
	if mx.Dcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.Dcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
	setLock(self, &mx.Dcache.lock)
	i, j = 0, 0
	fallthrough
case lDcleanLoop:
	if i < mx.Dcache.cc {
		p = &mx.Dcache.set[i][j]
	} else {
		p = &mx.Dcache.victim[j]
	}
	if p.tag&signBit != 0 {
		pc = lDcleanInc
		continue
	}
	if !isDirty(mx.Dcache, p) {
		p.tag |= data.x.o &^ 0xffffffff
		pc = lDcleanInc
		continue
	}
	data.y.o = Octa(Tetra(i))<<32 | Octa(Tetra(j))
	fallthrough

@ @<D-캐시를 위한...@>=
case lDclean:
	data.state = 1
	data.ptrB = p
	return mx.wait(self, mx.Dcache.accessTime)
case cleanupSt + 1:
	if mx.Dcache.flusher.next != nil {
		return mx.wait(self, 1)
	}
	mx.flushCache(mx.Dcache, p, data.x.o>>32 == 0)
	p.tag |= data.x.o &^ 0xffffffff
	releaseLock(self, &mx.Dcache.lock)
	data.state = 2
	return mx.wait(self, mx.Dcache.copyOutTime)
case cleanupSt + 2:
	if mx.cleanLock == nil {
		return false // 일찍 끝난다
	}
	if mx.Dcache.flusher.next != nil {
		return mx.wait(self, 1)
	}
	if data.i != sync {
		pc = lSprep
		continue
	}
	data.state = 3
	fallthrough

@ @<D-캐시를 위한...@>=
case cleanupSt + 3:
	if mx.Dcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.Dcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
	setLock(self, &mx.Dcache.lock)
	i, j = int(data.y.o>>32), int(Tetra(data.y.o))
	fallthrough
case lDcleanInc:
	j++
	if i < mx.Dcache.cc && j == mx.Dcache.aa {
		j, i = 0, i+1
	}
	if i == mx.Dcache.cc && j == mx.Dcache.vv {
		data.state = 5
		return mx.wait(self, mx.Dcache.accessTime)
	}
	pc = lDcleanLoop
	continue
case cleanupSt + 4:
	if mx.Dcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.Dcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
	setLock(self, &mx.Dcache.lock)
	p = mx.cacheSearch(mx.Dcache, data.z.o)
	if p != nil {
		mx.demoteAndFix(mx.Dcache, p)
		if isDirty(mx.Dcache, p) {
			pc = lDclean
			continue
		}
	}
	data.state = 9
	return mx.wait(self, mx.Dcache.accessTime)

@ @<S-캐시를 위한...@>=
case cleanupSt + 5:
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	if mx.Scache == nil {
		return false
	}
	if mx.Scache.lock != nil {
		return mx.wait(self, 1)
	}
	setLock(self, &mx.Scache.lock)
	i, j = 0, 0
	fallthrough
case lScleanLoop:
	if i < mx.Scache.cc {
		p = &mx.Scache.set[i][j]
	} else {
		p = &mx.Scache.victim[j]
	}
	if p.tag&signBit != 0 {
		pc = lScleanInc
		continue
	}
	if !isDirty(mx.Scache, p) {
		p.tag |= data.x.o &^ 0xffffffff
		pc = lScleanInc
		continue
	}
	data.y.o = Octa(Tetra(i))<<32 | Octa(Tetra(j))
	fallthrough

@ @<S-캐시를 위한...@>=
case lSclean:
	data.state = 6
	data.ptrB = p
	return mx.wait(self, mx.Scache.accessTime)
case cleanupSt + 6:
	if mx.Scache.flusher.next != nil {
		return mx.wait(self, 1)
	}
	mx.flushCache(mx.Scache, p, data.x.o>>32 == 0)
	p.tag |= data.x.o &^ 0xffffffff
	releaseLock(self, &mx.Scache.lock)
	data.state = 7
	return mx.wait(self, mx.Scache.copyOutTime)
case cleanupSt + 7:
	if mx.cleanLock == nil {
		return false // 일찍 끝난다
	}
	if mx.Scache.flusher.next != nil {
		return mx.wait(self, 1)
	}
	if data.i != sync {
		return false
	}
	data.state = 8
	fallthrough

@ @<S-캐시를 위한...@>=
case cleanupSt + 8:
	if mx.Scache.lock != nil {
		return mx.wait(self, 1)
	}
	setLock(self, &mx.Scache.lock)
	i, j = int(data.y.o>>32), int(Tetra(data.y.o))
	fallthrough
case lScleanInc:
	j++
	if i < mx.Scache.cc && j == mx.Scache.aa {
		j, i = 0, i+1
	}
	if i == mx.Scache.cc && j == mx.Scache.vv {
		data.state = 10
		return mx.wait(self, mx.Scache.accessTime)
	}
	pc = lScleanLoop
	continue
case lSprep:
	data.state = 9
	if self.lockloc != nil {
		releaseLock(self, &mx.Dcache.lock)
	}
	if mx.Scache == nil {
		return false
	}
	if mx.Scache.lock != nil {
		return mx.wait(self, 1)
	}
	setLock(self, &mx.Scache.lock)
	p = mx.cacheSearch(mx.Scache, data.z.o)
	if p != nil {
		mx.demoteAndFix(mx.Scache, p)
		if isDirty(mx.Scache, p) {
			pc = lSclean
			continue
		}
	}
	data.state = 10
	return mx.wait(self, mx.Scache.accessTime)

@* 가상 주소 변환. 가상 주소 변환에 쓰이는 \MMIX의 꽤 복잡한 페이지 테이블 방식을 구현해야 할
때는 코루틴과 제어 블록의 특별한 배열들이 나선다. 사실상 재정렬 버퍼 {\it 밖에\/} 제어 블록이
열 개까지 있는데, 이것들은 그 버퍼의 일부인 것처럼 명령을 실행할 수 있다. 가로막을 수 없는 이
명령들의 ``연산 코드''는 |ldptp|와 |ldpte|라는 특별한 내부 연산으로, 페이지 테이블 포인터와
페이지 테이블 항목을 적재한다.

이를테면 DT-캐시를 위해 가상 주소를 변환해야 하는데, 세그먼트~$i$의 가상 페이지 주소
$(a_4a_3a_2a_1a_0)_{1024}$에서 $a_4=a_3=0$이고 $a_2\ne0$이라고 하자. 그러면 규칙에 따라 먼저
물리 위치 $2^{13}(r+b_i+2)+8a_2$에서 페이지 테이블 포인터 $p_2$를 찾고, 그다음 위치 $p_2+8a_1$에서
또 다른 페이지 테이블 포인터~$p_1$을 찾고, 마지막으로 위치 $p_1+8a_0$에서 페이지 테이블
항목~$p_0$을 찾아야 한다. 이 시뮬레이터는 코루틴 셋 $c_0$, $c_1$, $c_2$를 띄워서 이 일을 한다.
그 제어 블록들은 다음 의사 명령들에 해당한다.
$$\vbox{\halign{\tt#\hfil\cr
LDPTP $x$,[$2^{63}+2^{13}(r+b_i+2)$],$8a_2$\cr
LDPTP $x$,$x$,$8a_1$\cr
LDPTE $x$,$x$,$8a_0$\cr}}$$
여기서 $x$는 숨은 내부 레지스터이고 다른 양들은 즉시값이다. \.{LDO}의 보통 기능을 조금만 바꾸면
\.{LDPTP}와 \.{LDPTE}를 구현하는 데 필요한 동작을 얻는다. 코루틴~$c_j$는 $a_j$를 쓰고 $p_j$를
계산하는 명령에 해당한다. 코루틴 $c_0$이 값~$p_0$을 계산하면 원래 가상 주소를 어떻게 변환할지 알게 된다.

\.{LDPTP}와 \.{LDPTE} 명령은 $y$~피연산자가 0이거나 페이지 테이블이 rV와 제대로 맞지 않으면 0을
돌려준다.

보충: 원본은 코루틴의 이름을 문자열 배열 |IPTname|과 |DPTname|에 두었다. 여기서는 초기화할 때
만든다.

@<상수@>=
const (
	LDPTP = PREGO // 안에서는 헷갈릴 일이 없다
	LDPTE = GO
)

@ @<기계의 상태@>=
IPTctl, DPTctl [5]control    // I와 D 페이지 변환을 위한 제어 블록
IPTco, DPTco   [10]coroutine // 코루틴마다 두 단계짜리 파이프라인이다

@ 보충: 원본은 |co[2*j]|의 다음 단계를 |self+1|로 얻었다. 여기서는 |succ| 필드를 정한다. 제어
블록의 \KW{specnode}들이 자기 블록을 가리키게 하는 일도 여기서 한다.

@<모든 것을 초기화한다@>=
for j = 0; j < 5; j++ {
	mx.DPTco[2*j].ctl = &mx.DPTctl[j]
	mx.IPTco[2*j].ctl = &mx.IPTctl[j]
	for _, c := range []*control{&mx.IPTctl[j], &mx.DPTctl[j]} {
		if j > 0 {
			c.op, c.i = LDPTP, ldptp
		} else {
			c.op, c.i = LDPTE, ldpte
		}
		c.loc = negOne
		c.goLoc.o = 3 // 원본의 |incr(neg_one,4)|
		c.ptrA = &mx.mem
		c.renX = true
		c.x.addr = c.x.addr&0xffffffff | 0xffffffff<<32
		c.link()
	}
	for _, co := range [][]coroutine{mx.IPTco[:], mx.DPTco[:]} {
		co[2*j].stage = 1
		co[2*j+1].stage = 2
		co[2*j].succ = &co[2*j+1]
	}
	mx.IPTco[2*j].name = fmt.Sprintf("IPT%d", j)
	mx.IPTco[2*j+1].name = mx.IPTco[2*j].name
	mx.DPTco[2*j].name = fmt.Sprintf("DPT%d", j)
	mx.DPTco[2*j+1].name = mx.DPTco[2*j].name
}
mx.ITcache.fillerCtl.ptrC = mx.IPTco[:]
mx.DTcache.fillerCtl.ptrC = mx.DPTco[:]

@ 페이지 테이블 계산은 |fillFromVirt| 타입의 코루틴이 불러낸다. 이 코루틴은 IT-캐시나 DT-캐시를
채우는 데 쓰인다. 코루틴 |fillFromVirt|의 호출 관례는 |fillFromMem|이나 |fillFromS|의 것과 비슷하다.
가상 주소는 |data.y.o|에 주어지고, |data.ptrA|는 캐시(|ITcache|나 |DTcache|)를 가리키며,
|data.ptrB|는 그 캐시 안의 블록이다. 부른 쪽은 캐시의 |fillLock|을 쥐고 있는데, 주어진 주소의
변환이 계산되자마자 부른 쪽을 깨운다. 부른 쪽이 중단되었다면 깨우지 않는다. (두 번째로 깨울
필요는 없다.)

보충: 원본에서 |data.ptrC|는 |\&IPTco[0]|이나 |\&DPTco[0]|이었다. 여기서는 코루틴 열 개의
슬라이스다.

@<특별한 코루틴의 출발 지점@>=
case fillFromVirt:
	c = data.ptrA.(*cache)
	cc = c.fillLock
	co = data.ptrC.([]coroutine) // |IPTco|나 |DPTco|
	pc = fillVirtSt + label(data.state)

@ @<특별한 코루틴을 제어하는 경우들@>=
case fillVirtSt + 0:
	@<보조 코루틴들을 띄워 페이지 테이블 항목을 계산한다@>
	data.state = 1
	fallthrough
case fillVirtSt + 1:
	if data.b.p != nil {
		if data.b.p.known {
			data.b.o, data.b.p = data.b.p.o, nil
		} else {
			return mx.wait(self, 1)
		}
	}
	@<|c.inbuf|에 넣을 새 항목을 계산하고 부른 쪽에 미리 보여 준다@>
	data.state = 2
	fallthrough
case fillVirtSt + 2:
	if c.lock != nil {
		return mx.wait(self, 1)
	}
	setLock(self, &c.lock)
	mx.loadCache(c, data.ptrB.(*cacheblock))
	data.state = 3
	return mx.wait(self, c.copyInTime)
case fillVirtSt + 3:
	data.b.o = 0
	return true

@ 특별한 가상 변환 레지스터 rV의 현재 내용은 편의상 |pageR|, |pageS| 같은 필드 몇 개에 풀어서
둔다. rV가 바뀔 때마다 이 필드들을 모두 다시 계산한다.

@<기계의 상태@>=
pageN    int    // rV의 10비트 |n| 필드에 8을 곱한 것
pageR    int    // rV의 27비트 |r| 필드
pageS    int    // rV의 8비트 |s| 필드
pageF    int    // rV의 3비트 |f| 필드
pageB    [5]int // rV의 4비트 |b| 필드들. |pageB[0]=0|
pageMask Octa   // 가장 아래 |s|비트
pageBad  bool   // rV가 규칙을 어기는가?

@ 보충: 원본에서 |page_bad|는 처음에 참이었다.

@<모든 것을 초기화한다@>=
mx.pageBad = true

@ @<|page| 변수들을 고친다@>=
{
	rv := data.z.o
	mx.pageF = int(rv & 7)
	mx.pageBad = mx.pageF > 1
	mx.pageN = int(rv & 0x1ff8)
	rv >>= 13
	mx.pageR = int(rv & 0x7ffffff)
	rv >>= 27
	mx.pageS = int(rv & 0xff)
	if mx.pageS < 13 || mx.pageS > 48 {
		mx.pageBad = true
	} else {
		mx.pageMask = 1<<mx.pageS - 1
	}
	mx.pageB[4] = int(rv>>8) & 0xf
	mx.pageB[3] = int(rv>>12) & 0xf
	mx.pageB[2] = int(rv>>16) & 0xf
	mx.pageB[1] = int(rv>>20) & 0xf
}

@ 가상 주소에서 IT-캐시나 DT-캐시의 태그를 계산하는 방법과, 캐시에서 찾은 변환에서 물리 주소를
계산하는 방법은 다음과 같다.

@<함수들@>=
func (mx *machine) transKey(addr Octa) Octa {
	return addr&^mx.pageMask + Octa(mx.pageN)
}
@#
func (mx *machine) physAddr(virt, trans Octa) Octa {
	t := trans &^ mx.pageMask // PTE의 \\{ynp} 필드들을 지운다
	return t + virt&mx.pageMask
}

@ 값싼 (그리고 느린) \MMIX\ 판은 페이지 테이블 계산을 소프트웨어에 맡긴다. 필드
|noHardwarePT|가 참이면 |fillFromVirt|는 상태~0이 아니라 상태~1에서 동작을 시작한다.
(재개 코드 |resumeTrans|의 연산을 보라.)

@<기계의 상태@>=
noHardwarePT bool

@ 주의: 변환 캐시를 고치고 있을 때 페이지 테이블 항목의 변화가 파이프라인에 나타나지 않게 하는
것은 운영체제의 몫이다. 내부 명령 \.{LDPTP}와 \.{LDPTE}는 메모리 체계의 ``뜨거운 상태''만
쓴다.
@^operating system@>

보충: 원본의 지역 변수 |aaaaa|는 이 절과 다음 절에서만 쓴다. 원본에서 |shift_right|로 옮긴 것은
부호 없는 옮김이다. 주소에서 세그먼트 번호를 지웠으므로 여기서 $s$는 48 이하다.

@<보조 코루틴들을 띄워...@>=
aaaaa := data.y.o
i = int(aaaaa >> 61) // 세그먼트 번호
aaaaa &= 1<<61 - 1 // 세그먼트~$i$ 안의 주소
aaaaa >>= mx.pageS // 페이지 주소
for j = 0; aaaaa != 0; j++ {
	co[2*j].ctl.z.o = (aaaaa & 0x3ff) << 3
	aaaaa >>= 10
}
if mx.pageB[i+1] < mx.pageB[i]+j { // 주소가 너무 크다
	// |data.b.o|가 0이므로 할 일이 없다
} else {
	if j == 0 {
		j = 1
		co[0].ctl.z.o = 0
	}
	@<페이지 테이블 항목을 계산하는 의사 명령 $j$개를 발행한다@>
}

@ 코루틴~$c_j$의 첫 단계는 |co[2*j]|다. 그것은 $j$번째 제어 블록을 둘째 단계 |co[2*j+1]|에
넘기고, 둘째 단계는 메모리에서(되도록이면 D-캐시에서) 페이지 테이블 정보를 적재한다.

보충: 원본은 |aaaaa|의 아랫 테트라만 정했다. 앞의 루프가 끝났을 때 |aaaaa|는 0이므로 윗
테트라는 0이다.

@<페이지 테이블 항목을 계산하는 의사 명령...@>=
j--
aaaaa = Octa(Tetra(mx.pageR + mx.pageB[i] + j))
co[2*j].ctl.y = spec{o: aaaaa<<13 + signBit}
for ; ; j-- {
	co[2*j].ctl.x.o, co[2*j].ctl.x.known = 0, false
	co[2*j].ctl.owner = &co[2*j]
	mx.startup(&co[2*j], 1)
	if j == 0 {
		break
	}
	co[2*(j-1)].ctl.y.p = &co[2*j].ctl.x
}
data.b.p = &co[0].ctl.x

@ 이 시점에서 주어진 가상 주소 |data.y.o|의 변환은 옥타바이트 |data.b.o|다. 그 가장 아래 세
비트는 보호 코드~$p=p_rp_wp_x$이고, 페이지 주소 필드는 $2^s$ 단위다. 페이지 테이블 실패가
있었다면 보호 비트까지 모두 0이다.

부른 쪽의 |z| 필드가 이 변환을 받는다.

@<|c.inbuf|에 넣을 새 항목을...@>=
c.inbuf.tag = mx.transKey(data.y.o)
c.inbuf.data[0] = data.b.o
if cc != nil {
	cc.ctl.z.o = data.b.o
	mx.awaken(cc, 1)
}

@* 쓰기 버퍼. 배정기는 메모리에 투기로 저장하는 명령들을 |mem|에서 위로 뻗어 가는 이중 연결
리스트에 기록하도록 해 두었다. 그런 명령들이 마침내 확정되면 ``쓰기 버퍼''로 들어간다. 쓰기
버퍼에는 지정된 물리 메모리 주소에(또는 D-캐시나 S-캐시에) 쓸 준비가 된 옥타바이트들이 들어
있다. 계산의 ``뜨거운 상태''는 레지스터와 캐시뿐 아니라 쓰기 버퍼에서 기다리는 명령들에도
나타난다.

보충: 필드 |idx|는 옮긴이가 덧붙인 것으로, 쓰기 버퍼 안에서의 색인이다.

@<타입 정의@>=
type writeNode struct {
	o     Octa  // 저장할 데이터
	addr  Octa  // 그 물리 주소
	stamp Tetra // 마지막으로 확정된 때($2^{32}$을 법으로)
	i     int   // 이 쓰기는 특별한가?
	size  int   // |specWrite|의 매개변수
	idx   int   // 쓰기 버퍼 안의 위치
}

@ 이 버퍼는 늘 하던 대로 원형 리스트로 나타내는데, 원소는 |writeTail+1|, |writeTail+2|,
\dots,~|writeHead|이다.

데이터는 쓰기 버퍼를 떠나기 전에 적어도 |holdingTime| 사이클 동안 머문다. 그러면 같은
옥타바이트의 여러 필드를 여러 명령이 저장할 때 일이 빨라진다.

@<기계의 상태@>=
wbuf                 []writeNode // 쓰기 버퍼가 든 원
wbufBot, wbufTop     *writeNode  // 가장 작은 쓰기 버퍼 노드와 가장 큰 노드
writeHead, writeTail *writeNode  // 쓰기 버퍼의 앞과 뒤
wbufLock             lockvar     // |writeHead|의 데이터를 쓰고 있는가?
holdingTime          int         // 최소 머무는 시간
speedLock            lockvar     // |holdingTime|을 무시해야 하는가?

@ 보충: 원형 리스트를 도는 두 메서드를 둔다. 메서드 |prevWrite|는 원본의 |p-1|이고, |nextWrite|는
원본의 |q+1|이다. 둘 다 원의 끝에서 반대쪽 끝으로 돌아간다.

@<함수들@>=
func (mx *machine) prevWrite(p *writeNode) *writeNode {
	if p == mx.wbufBot {
		return mx.wbufTop
	}
	return &mx.wbuf[p.idx-1]
}
@#
func (mx *machine) nextWrite(q *writeNode) *writeNode {
	if q == mx.wbufTop {
		return mx.wbufBot
	}
	return &mx.wbuf[q.idx+1]
}

@ @<기계의 상태@>=
writeCo  coroutine // 쓰기 버퍼를 비우는 코루틴
writeCtl control   // 그 제어 블록

@ @<모든 것을 초기화한다@>=
mx.writeCo.ctl = &mx.writeCtl
mx.writeCo.name = "Write"
mx.writeCo.stage = writeFromWbuf
mx.writeCtl.ptrA = &mx.mem
mx.writeCtl.goLoc.o = 4
mx.startup(&mx.writeCo, 1)
mx.writeHead, mx.writeTail = mx.wbufTop, mx.wbufTop

@ 보충: 원본은 나이를 부호 없는 32비트 차로 계산해서 \.{\%d}로 찍었다.

@<함수들@>=
func (mx *machine) printWriteBuffer() {
	mx.printf("Write buffer")
	if mx.writeHead == mx.writeTail {
		mx.printf(" (empty)\n")
	} else {
		mx.printf(":\n")
		for p := mx.writeHead; p != mx.writeTail; p = mx.prevWrite(p) {
			mx.printf("m[")
			mx.printOcta(p.addr)
			mx.printf("]=")
			mx.printOcta(p.o)
			if p.i == stunc {
				mx.printf(" unc")
			} else if p.i == sync {
				mx.printf(" sync")
			}
			mx.printf(" (age %d)\n", int32(Tetra(mx.ticks)-p.stamp))
		}
	}
}

@ 파이프라인 계산의 현재 상태 전체는 먼저 쓰기 버퍼를, 그다음 재정렬 버퍼를, 그다음 가져오기
버퍼를 찍어서 한눈에 볼 수 있다. 그러면 결과들이 가장 오래된 것부터 가장 젊은 것까지, 지글지글
뜨거운 것부터 얼음처럼 차가운 것까지 차례로 보인다.

@<함수들@>=
func (mx *machine) printPipe() {
	mx.printWriteBuffer()
	mx.printReorderBuffer()
	mx.printFetchBuffer()
}

@ 루틴 |writeSearch|는 재정렬 버퍼의 |mem| 리스트에서 주어진 자리보다 앞선 명령 가운데 주어진
물리 주소에 저장하는 것이 있는지, 또는 쓰기 버퍼에 그 주소로 가는 명령이 기다리고 있는지
살핀다. 있으면 쓸 값을 가리키는 포인터를 돌려주고, 없으면~|nil|을 돌려준다. 관련이 있을지 모르는
물리 주소 가운데 적어도 하나가 아직 계산되지 않아서 지금은 답을 모르면, 특별한 코드 값~|dunno|를
돌려준다.

찾기는 저장 명령의 제어 블록이면 |x.up| 필드에서 시작하고, 그렇지 않으면 제어 블록의 |ptrA|
필드에서 시작한다. 다만 |ptrA|가 이미 확정된 명령을 가리키면 그렇게 하지 않는다.

쓰기 버퍼의 |i| 필드는 대개 |st|나 |pst|인데, 저장 명령이나 부분 저장 명령에서 물려받은 것이다.
내부 연산 |sync|(\.{SYNC}~\.1이나 \.{SYNC}~\.3에서)나 |stunc|(\.{STUNC}에서)일 수도 있다.

보충: 원본의 \.{DUNNO}는 포인터로 쓸 수 없는 값 |(octa*)1|이었다. 여기서는 그 뜻으로만 쓰는 필드
|dunno|의 주소를 쓴다.

@<기계의 상태@>=
dunno Octa // 원본의 \.{DUNNO}가 가리키는 곳

@ 원본은 |p|와 |\&hot->x|, |ctl|과 |hot|의 주소를 견주어 |p|가 이미 확정된 명령에 속하는지
가렸다. 리스트 |mem|에서 머리 |mem| 말고는 모두 재정렬 버퍼 안 제어 블록의 |x| 필드이므로, 보충:
여기서는 그 제어 블록들의 |idx|를 견준다. 원본의 이름표 |qloop|로 뛰는 것은 |mem| 리스트를 훑는
루프를 건너뛰는 것이다.

@<함수들@>=
func (mx *machine) writeSearch(ctl *control, addr Octa) *Octa {
	var p *specnode
	if ctl.memX {
		p = ctl.x.up
	} else {
		p = ctl.ptrA.(*specnode)
	}
	q := mx.writeTail
	addr &^= 7
	if p != &mx.mem {
		k, h, c := p.ctl.idx, mx.hot.idx, ctl.idx
		if !(k > h && c <= h) && !(k < c && (c <= h || k > h)) {
			for ; p != &mx.mem; p = p.up {
				if p.addr>>32 == 0xffffffff {
					return &mx.dunno
				}
				if p.addr&^7 == addr {
					if p.known {
						return &p.o
					}
					return &mx.dunno
				}
			}
		}
	}
	for { // 원본의 |qloop|
		if q == mx.writeHead {
			return nil
		}
		q = mx.nextWrite(q)
		if q.addr == addr {
			return &q.o
		}
	}
}

@ 새 데이터를 메모리에 확정할 때, 쓰기 버퍼에 물리 주소가 같은 항목이 있으면 그것을 고칠 수
있다. 다만 그 항목이 이미 쓰이고 있는 중이면 안 된다. 매개변수 |holdingTime|의 값을 늘리면 이렇게 아낄
가능성이 커지지만, 서로 다른 위치에 쓸 때 버퍼에 쌓이는 항목의 수도 늘어난다.

여덟 인터럽트 비트 \.{rwxnkbsp} 가운데 어느 것이라도 켜는 저장 명령은, 인터럽트를 일으키지
않더라도 메모리에 영향을 주지 않는다.

같은 주소에 ``저장'' 뒤에 ``캐시하지 않는 저장''이 오거나 그 반대이면, 가장 최근의 귀띔을
믿는다.

보충: 원본에서 쓰기 버퍼가 차 있을 때의 |break|는 확정하는 루프를 빠져나온다. 여기서는
|break commit|이다. 원본의 이름표 |addr_found|와 |done_with_write|로 뛰는 곳은 불 변수
|found|와 |if| 문으로 바꾸었다.

@<가능하면 메모리에 확정하고...@>=
if hot.interrupt&(fBit+0xff) == 0 {
	q := mx.writeTail
	if hot.x.addr>>32&0xffff0000 != 0 {
		@<|specWrite|에 넘길 크기를 정한다@>
	}
	found := false
	if hot.i != sync {
		@<쓰기 버퍼에서 물리 주소가 같은 항목 |q|를 찾는다@>
	}
	if !found {
		p := mx.prevWrite(mx.writeTail)
		if p == mx.writeHead {
			break commit // 쓰기 버퍼가 차 있다
		}
		q = mx.writeTail
		mx.writeTail = p
		q.addr = hot.x.addr
	}
	q.o = hot.x.o
	q.stamp = Tetra(mx.ticks)
	q.i = hot.i
}
specRem(&hot.x)
mx.memSlots++

@ @<|specWrite|에 넘길...@>=
if hot.op >= STB && hot.op < STSF {
	q.size = (hot.op & 0xf) >> 2
} else if hot.op >= STSF && hot.op < STCO {
	q.size = 2
} else {
	q.size = 3
}

@ @<쓰기 버퍼에서 물리 주소가...@>=
for q != mx.writeHead {
	q = mx.nextWrite(q)
	if q.i == sync {
		break
	}
	if q.addr == hot.x.addr && (q != mx.writeHead || mx.wbufLock == nil) {
		found = true
		break
	}
}

@ 쓰기 버퍼를 비우는 일을 맡은 특별한 코루틴은 늘 활성이다. 이 코루틴은 |writeHead|의 내용을
쓰는 동안 |wbufLock|을 쥔다. D-캐시가 블록을 채우기를 기다리는 동안에는 |Dcache.fillLock|을
쥔다.

보충: 원본의 이름표 |write_restart|는 `|write_restart|: |data.state=0|; |case 0|:' 꼴이므로 상태~0의
|case|와 합친다. 원본의 이름표 |mem_direct|는 지점이 된다.

@<특별한 코루틴의 출발 지점@>=
case writeFromWbuf:
	p, _ = data.ptrB.(*cacheblock)
	pc = writeSt + label(data.state)

@ @<지점 이름@>=
lMemDirect // 원본의 |mem_direct|

@ @<상수@>=
const lWriteRestart = writeSt + 0 // 원본의 |write_restart|

@ @<특별한 코루틴을 제어하는 경우들@>=
case writeSt + 4:
	@<즉시 쓰기이면 새 데이터를 D-캐시 너머로 보낸다@>
	data.state = 5
	fallthrough
case writeSt + 5:
	mx.writeHead = mx.prevWrite(mx.writeHead)
	fallthrough
case lWriteRestart:
	data.state = 0
	@<쓰기 버퍼의 머리를 D-캐시에 써 본다@>
case writeSt + 1:
	@<위치 |writeHead.addr|의 내용을 D-캐시에 넣어 본다@>
	data.state = 2
	return mx.sleep(self)
case writeSt + 2:
	data.state = 0
	return mx.sleep(self) // D-캐시에 블록이 들어오면 깨어난다
case writeSt + 3:
	@<D-캐시에 쓸 때 쓰기 우회를 다룬다@>
case lMemDirect:
	@<|writeHead|에서 메모리로 바로 쓴다@>

@ 보충: 원본은 머무는 시간을 부호 없는 32비트 차로 견주었다.

@<쓰기 버퍼의 머리를 D-캐시에 써 본다@>=
if self.lockloc != nil {
	*self.lockloc = nil
	self.lockloc = nil
}
if mx.writeHead == mx.writeTail {
	return mx.wait(self, 1) // 쓰기 버퍼가 비어 있다
}
if mx.writeHead.i == sync {
	@<|writeHead|의 항목을 무시한다@>
}
if mx.writeHead.addr>>32&0xffff0000 != 0 {
	pc = lMemDirect
	continue
}
if Tetra(mx.ticks)-mx.writeHead.stamp < Tetra(mx.holdingTime) && mx.speedLock == nil {
	return mx.wait(self, 1) // 데이터가 아직 설익었다
}
if mx.Dcache == nil {
	pc = lMemDirect // 캐시하지 않는다
	continue
}
if mx.Dcache.lock != nil {
	return mx.wait(self, 1) // D-캐시가 바쁘다
}
if j = getReader(mx.Dcache); j < 0 {
	return mx.wait(self, 1)
}
mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
@<데이터를 D-캐시에 쓰고, 적중하면 |state=4|로 한다@>
if mx.Dcache.mode&writeAlloc != 0 && mx.writeHead.i != stunc {
	data.state = 1
} else {
	data.state = 3
}
return mx.wait(self, mx.Dcache.accessTime)

@ 쓰기 우회 방식에서는 알갱이가 8임이 보장된다(|MMIX_config|를 보라). 캐시하지 않는 저장은
(D-캐시에서 적중하지 않으면) D-캐시에 저장되지 않지만, 2차 캐시에는 들어간다.

@<D-캐시에 쓸 때 쓰기 우회를...@>=
if mx.Dcache.filler.next != nil ||
	(mx.Scache != nil && mx.Scache.lock != nil) || (mx.Scache == nil && mx.memLock != nil) {
	pc = lWriteRestart
	continue
}
if mx.Dcache.flusher.next != nil {
	return mx.wait(self, 1)
}
{
	c := mx.Dcache
	a := Tetra(mx.writeHead.addr)
	c.outbuf.tag = mx.writeHead.addr&^0xffffffff | Octa(a&Tetra(-c.bb))
	for j = 0; j < c.bb>>c.g; j++ {
		c.outbuf.dirty[j] = false
	}
	c.outbuf.data[(a&Tetra(c.bb-1))>>3] = mx.writeHead.o
	c.outbuf.dirty[(a&Tetra(c.bb-1))>>c.g] = true
	c.outbuf.rank = c.gg // 유효한 바이트가 이만큼 있다
}
setLock(self, &mx.wbufLock)
mx.startup(&mx.Dcache.flusher, mx.Dcache.copyOutTime)
data.state = 5
return mx.wait(self, mx.Dcache.copyOutTime)

@ @<|writeHead|에서 메모리로...@>=
if mx.memLock != nil {
	return mx.wait(self, 1)
}
setLock(self, &mx.wbufLock)
setLock(&mx.memLocker, &mx.memLock) // |vanish| 타입의 코루틴
mx.startup(&mx.memLocker, mx.memAddrTime+mx.memWriteTime)
if mx.writeHead.addr>>32&0xffff0000 != 0 {
	mx.specWrite(mx.writeHead.addr, mx.writeHead.o, mx.writeHead.size)
} else {
	mx.memWrite(mx.writeHead.addr, mx.writeHead.o)
}
data.state = 5
return mx.wait(self, mx.memAddrTime+mx.memWriteTime)

@ 여기서 짚어 둘 미묘한 점이 있다. D-캐시를 고치려는 동안 다른 명령이 같은 캐시 블록을 채우고
있을 수 있다(같은 물리 주소 때문은 아니더라도). 그래서 여기서는 |wait(1)| 대신 |write_restart|로
뛴다.

@<위치 |writeHead.addr|의 내용을...@>=
if mx.Dcache.filler.next != nil ||
	(mx.Scache != nil && mx.Scache.lock != nil) || (mx.Scache == nil && mx.memLock != nil) {
	pc = lWriteRestart
	continue
}
p = mx.allocSlot(mx.Dcache, mx.writeHead.addr)
if p == nil {
	pc = lWriteRestart
	continue
}
if mx.Scache != nil {
	setLock(&mx.Dcache.filler, &mx.Scache.lock)
} else {
	setLock(&mx.Dcache.filler, &mx.memLock)
}
setLock(self, &mx.Dcache.fillLock)
data.ptrB, mx.Dcache.fillerCtl.ptrB = p, p
mx.Dcache.fillerCtl.z.o = mx.writeHead.addr
if mx.Scache != nil {
	mx.startup(&mx.Dcache.filler, mx.Scache.accessTime)
} else {
	mx.startup(&mx.Dcache.filler, mx.memAddrTime)
}

@ 여기서는 |Dcache.accessTime|이면 D-캐시를 찾고 적중했을 때 옥타바이트 하나를 고치기에
넉넉하다고 가정한다. D-캐시는 잠그지 않는다. 동시에 D-캐시를 읽고 있을지 모르는 다른 코루틴들은
바뀌는 옥타바이트를 쓰지 않을 것이기 때문이다. 어쩌면 이 시뮬레이터가 너무 너그러운지도 모른다.

@<데이터를 D-캐시에 쓰고...@>=
p = mx.cacheSearch(mx.Dcache, mx.writeHead.addr)
if p != nil {
	p = mx.useAndFix(mx.Dcache, p)
	setLock(self, &mx.wbufLock)
	data.ptrB = p
	a := Tetra(mx.writeHead.addr) & Tetra(mx.Dcache.bb-1)
	p.data[a>>3] = mx.writeHead.o
	p.dirty[a>>mx.Dcache.g] = true
	data.state = 4
	return mx.wait(self, mx.Dcache.accessTime)
}

@ @<즉시 쓰기이면 새 데이터를...@>=
if mx.Dcache.mode&writeBack == 0 { // 즉시 쓰기
	if mx.Dcache.flusher.next != nil {
		return mx.wait(self, 1)
	}
	mx.flushCache(mx.Dcache, p, true)
}

@ @<|writeHead|의 항목을 무시한다@>=
setLock(self, &mx.wbufLock)
data.state = 5
return mx.wait(self, 1)

@* 적재와 저장. RISC 기계를 흔히 ``적재/저장 아키텍처''라고 부르는데, 아마 적재와 저장이 RISC
기계가 해야 하는 가장 어려운 일에 들기 때문일 것이다.

메모리 접근이 효율적이기를 바라므로, DT-캐시로 가상 주소를 변환하는 것과 동시에 D-캐시에
접근하려고 한다. 대개는 두 캐시 모두에서 적중하지만, 놓칠 때는 수많은 경우를 다루어야 한다.
모든 경우를 다루는 우아한 방법이 있을까? 아쉽게도 이 프로그램의 저자는 문제에 코드를 잔뜩
쏟아붓는 것보다 나은 방법을 생각해 내지 못했다. 그렇게 스파게티 같은 방법에 잘못의 가능성이
가득하다는 것을 잘 알면서도 말이다.

\.{LDO} $x,y,z$ 같은 명령은 파이프라인 두 단계에서 일한다. 첫 단계는 가상 주소 $y+z$를
계산하는데, 필요하면 $y$와~$z$를 둘 다 알 때까지 기다린다. 그런 다음 필요한 캐시들에 접근하기
시작한다. 둘째 단계에서는 해당하는 물리 주소를 확인하고, 바라건대 캐시에서(또는 투기적 |mem|
리스트나 쓰기 버퍼에서) 데이터를 찾는다.

\.{STB} $x,y,z$ 같은 명령은 \.{LDO}~$x,y,z$의 계산 일부를 함께 쓴다. 한 바이트만 저장하지만
나머지 일곱 바이트를 캐시에서 찾아야 하기 때문이다. 그러나 이 경우에는 $x$가 입력으로 다루어지고,
|mem|이 출력이다. 저장 명령의 둘째 단계는 첫 단계 동안 $x$를 모르더라도 시작할 수 있다.

1단계를 시작할 때 하는 일은 다음과 같다.

보충: 원본은 |ldptp|와 |ldpte|의 경우에서 |ld|의 경우 안에 있는 이름표 |start_ld_st|로 뛰었다.
여기서는 그 뒷부분을 절로 만들어 두 곳에서 쓴다.

@<상수@>=
const ldStLaunch = 7 // 적재/저장 명령이 메모리 주소를 가졌을 때의 |state|

@ @<메모리 연산의 가상 주소를...@>=
case preld, prest, prego:
	{
		bb := mx.Dcache.bb
		if data.i == prego {
			bb = mx.Icache.bb
		}
		data.z.o += Octa(int(data.xx) & -bb) // (덧셈기가 넉넉히 빠르기를 바란다)
	}
	fallthrough
case ld, ldunc, ldvts, st, pst, syncd, syncid:
	@<적재나 저장을 시작한다@>
case ldptp, ldpte:
	if data.y.o>>32 != 0 {
		@<적재나 저장을 시작한다@>
	}
	data.x.o, data.x.known = 0, true
	pc = lDie // 페이지 테이블 실패
	continue

@ @<적재나 저장을 시작한다@>=
data.y.o += data.z.o
data.state = ldStLaunch
pc = lSwitch1
continue

@ 원본의 매크로 \.{PRW\_BITS}는 이 명령에 필요한 보호 비트들이다. 보충: 여러 곳에서 쓰므로
함수로 둔다.

@<함수들@>=
func prwBits(data *control) Tetra {
	switch {
	case data.i < st:
		return prBit
	case data.i == pst:
		return prBit + pwBit
	case data.i == syncid && data.loc&signBit != 0:
		return 0
	}
	return pwBit
}

@ 보충: 원본의 이름표 |make_ld_ready|는 물리 주소를 아는 경우를 다루는 절의 한가운데 있었다. 여기서는
지점이 된다. 원본에서 이름표 |sync_check|와 |emulate_virt|는 뒤에서 나온다.

@<지점 이름@>=
lMakeLdReady // 원본의 |make_ld_ready|

@ @<첫 단계의 특별한 상태들@>=
case stage1St + ldStLaunch:
	if self.succ.next != nil {
		return mx.wait(self, 1) // 둘째 단계가 비어 있어야 한다
	}
	@<|prego|나 |ldvts| 같은 연산의 특별한 경우를 다룬다@>
	if data.y.o&signBit != 0 {
		@<물리 주소를 아는 적재/저장의 1단계를 한다@>
	}
	if mx.pageBad {
		if data.i < preld || data.i == st || data.i == pst {
			data.interrupt |= prwBits(data)
		}
		pc = lFinEx
		continue
	}
	if mx.DTcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.DTcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.DTcache.reader[j], mx.DTcache.accessTime)
	@<DT-캐시에서 주소를 찾고, 할 수 있으면 D-캐시에서도 찾는다@>
	mx.passAfter(self, mx.DTcache.accessTime)
	pc = lPassit
	continue
case lMakeLdReady:
	setLock(&mx.memLocker, &mx.memLock)
	data.state = ldReady
	mx.startup(&mx.memLocker, mx.memAddrTime+mx.memReadTime)
	mx.passAfter(self, mx.memAddrTime+mx.memReadTime)
	pc = lPassit
	continue

@ 적재/저장 명령의 2단계가 시작할 때 상태는 1단계에서 일어난 일에 달려 있다. 이를테면 가상 주소
열쇠를 DT-캐시에서 찾을 수 없으면 |data.state|는 |dtMiss|이고, 그러면 2단계가 물리 주소를 어렵게
계산해야 한다.

DT-캐시로 물리 주소를 알지만 데이터가 D-캐시에 있을지 없을지 모르면 |data.state|는 |dtHit|이다.
DT-캐시는 적중하고 D-캐시는 놓치면 |data.state|는 |hitAndMiss|다. 그리고 |data.x.o|가 바라던
옥타바이트이면(이를테면 두 캐시가 모두 적중하면) 상태 |data.state|는 |ldReady|다.

@<상수@>=
const (
	dtMiss     = 10 // DT-캐시에 열쇠가 없을 때의 둘째 단계 |state|
	dtHit      = 11 // 물리 주소를 알 때의 둘째 단계 |state|
	hitAndMiss = 12 // D-캐시를 놓쳤을 때의 둘째 단계 |state|
	ldReady    = 13 // 데이터를 읽었을 때의 둘째 단계 |state|
	stReady    = 14 // 데이터를 읽을 필요가 없을 때의 둘째 단계 |state|
	prestWin   = 15 // 블록을 0으로 채울 수 있을 때의 둘째 단계 |state|
)

@ @<DT-캐시에서 주소를 찾고...@>=
p = mx.cacheSearch(mx.DTcache, mx.transKey(data.y.o))
if mx.Dcache == nil || mx.Dcache.lock != nil || data.i >= st && data.i <= syncid {
	@<D-캐시를 찾지 않고 적재/저장의 1단계를 한다@>
}
if j = getReader(mx.Dcache); j < 0 {
	@<D-캐시를 찾지 않고 적재/저장의 1단계를 한다@>
}
mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
if p != nil {
	@<D-캐시에서도 동시에 찾는다@>
} else {
	data.state = dtMiss
}

@ DT-캐시에서 가상 주소를 찾는 것과 동시에 D-캐시에서 해당하는 물리 주소를 찾을 수 있다고
가정한다. 다만 두 주소의 아래 $b+c$비트가 같아야 한다. (두 값이 |b+c<=pageS|이면 늘 같다. 그렇지 않으면
운영체제가 ``페이지 채색''으로 되도록 같게 하려고 애쓸 수 있다.) 두 캐시가 모두 적중하면 물리
@^page coloring@>
주소를 max(|DTcache.accessTime|, |Dcache.accessTime|) 사이클 만에 안다.

가상 주소와 물리 주소의 아래 $b+c$비트가 다르면, 기계는 DT-캐시가 적중할 때까지 그것을 모른다.
그래서 D-캐시에 접근하는 동작은 흉내 내지만, |hitAndMiss| 대신 |dtHit|으로 간다. D-캐시가 가짜로
놓칠 것이기 때문이다.

@<D-캐시에서도 동시에...@>=
p = mx.useAndFix(mx.DTcache, p)
data.z.o = p.data[0]
@<보호 비트를 검사하고 물리 주소를 얻는다@>
if m := mx.writeSearch(data, data.z.o); m == &mx.dunno {
	data.state = dtHit
} else if m != nil {
	data.x.o, data.state = *m, ldReady
} else if mx.Dcache.b+mx.Dcache.c > mx.pageS &&
	(Tetra(data.y.o)^Tetra(data.z.o))&Tetra((mx.Dcache.bb<<mx.Dcache.c)-(1<<mx.pageS)) != 0 {
	data.state = dtHit // 가짜 D-캐시 찾기
} else {
	@<D-캐시에서 |data.z.o|를 찾아 적중하면 |x|를 읽는다@>
}
mx.passAfter(self, max(mx.DTcache.accessTime, mx.Dcache.accessTime))
pc = lPassit
continue

@ @<D-캐시에서 |data.z.o|를...@>=
q = mx.cacheSearch(mx.Dcache, data.z.o)
if q != nil {
	if data.i == ldunc {
		q = mx.demoteAndFix(mx.Dcache, q)
	} else {
		q = mx.useAndFix(mx.Dcache, q)
	}
	data.x.o = q.data[(Tetra(data.z.o)&Tetra(mx.Dcache.bb-1))>>3]
	data.state = ldReady
} else {
	data.state = hitAndMiss
}

@ 변환 캐시의 보호 비트 $p_rp_wp_x$는 인터럽트 코드 |prBit|, |pwBit|, |pxBit|를 오른쪽으로 다섯
자리 옮긴 곳에 있다. 데이터가 보호되어 있으면 적재/저장 연산을 곧바로 중단한다. 이것이 다른
사용자들의 사생활을 지켜 준다.

@<보호 비트를 검사하고...@>=
if data.stackAlert {
	if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
		data.stackAlert = false
	} else {
		data.z.o = mx.g[rC].o // 스택 넘침에는 계속 페이지를 쓴다
	}
}
j = int(prwBits(data))
if (Tetra(data.z.o)<<protOffset)&Tetra(j) != Tetra(j) {
	if data.i == syncd || data.i == syncid {
		pc = lSyncCheck
		continue
	}
	if data.i != preld && data.i != prest {
		data.interrupt |= Tetra(j) &^ (Tetra(data.z.o) << protOffset)
	}
	data.stackAlert = false
	pc = lFinEx
	continue
}
data.z.o = mx.physAddr(data.y.o, data.z.o)

@ @<D-캐시를 찾지 않고 적재/저장의 1단계를 한다@>=
if p != nil {
	p = mx.useAndFix(mx.DTcache, p)
	data.z.o = p.data[0]
	@<보호 비트를...@>
	if data.i >= st && data.i <= syncid {
		data.state = stReady
	} else if m := mx.writeSearch(data, data.z.o); m != nil && m != &mx.dunno {
		data.x.o, data.state = *m, ldReady
	} else {
		data.state = dtHit
	}
} else {
	data.state = dtMiss
}
mx.passAfter(self, mx.DTcache.accessTime)
pc = lPassit
continue

@ 보충: 원본은 주소에서 윗 테트라의 부호 비트를 뺐다. 부호 비트가 켜져 있으므로 옥타바이트에서
$2^{63}$을 빼는 것과 같다. 주소가 $2^{48}$ 이상일 때의 |switch|에서 \.{LDPTP}와 \.{LDPTE}는 어느
|case|에도 맞지 않아서 그 뒤로 이어진다. 원본과 같다.

@<물리 주소를 아는 적재/저장의 1단계를 한다@>=
if data.loc&signBit == 0 {
	if data.i == syncd || data.i == syncid {
		pc = lSyncCheck
		continue
	}
	if data.i != preld && data.i != prest {
		data.interrupt |= nBit
	}
	pc = lFinEx
	continue
}
data.z.o = data.y.o - signBit
if data.z.o>>32&0xffff0000 != 0 {
	@<특별한 물리 주소에서 적재/저장의 1단계를 한다@>
} else if data.i >= st && data.i <= syncid {
	data.state = stReady
	mx.passAfter(self, 1)
	pc = lPassit
	continue
}
@<물리 주소로 쓰기 버퍼와 메모리나 D-캐시를 찾는다@>

@ @<특별한 물리 주소에서...@>=
switch data.i {
case ldvts, preld, prest, prego, syncd, syncid:
	pc = lFinEx
	continue
case ld, ldunc:
	if mx.memLock != nil {
		return mx.wait(self, 1)
	}
	if data.op < LDSF {
		i = (data.op & 0xf) >> 2
	} else if data.op < CSWAP {
		i = 2
	} else {
		i = 3
	}
	data.x.o = mx.specRead(data.z.o, i)
	pc = lMakeLdReady
	continue
case pst:
	if (data.op ^ CSWAP) <= 1 {
		data.x.o = mx.specRead(data.z.o, 3)
		pc = lMakeLdReady
		continue
	}
	data.x.o = 0
	fallthrough
case st:
	data.state = stReady
	mx.passAfter(self, 1)
	pc = lPassit
	continue
}

@ @<물리 주소로 쓰기 버퍼와...@>=
if m := mx.writeSearch(data, data.z.o); m != nil {
	if m == &mx.dunno {
		data.state = dtHit
	} else {
		data.x.o, data.state = *m, ldReady
	}
	mx.passAfter(self, 1)
	pc = lPassit
	continue
} else if mx.Dcache == nil {
	if mx.memLock != nil {
		return mx.wait(self, 1)
	}
	data.x.o = mx.memRead(data.z.o)
	pc = lMakeLdReady
	continue
}
if mx.Dcache.lock != nil {
	data.state = dtHit
	mx.passAfter(self, 1)
	pc = lPassit
	continue
}
if j = getReader(mx.Dcache); j < 0 {
	data.state = dtHit
	mx.passAfter(self, 1)
	pc = lPassit
	continue
}
mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
@<D-캐시에서 |data.z.o|를...@>
mx.passAfter(self, mx.Dcache.accessTime)
pc = lPassit
continue

@ 둘째 단계의 프로그램도 마찬가지로 꽤 장황하지만, 이미 여러 번 본 캐시 조작과 아주 비슷하다.

여러 명령이 같은 페이지를 위해 DT-캐시를 채우려 할 수도 있다. (코루틴 |writeFromWbuf|에서도
비슷한 상황을 만났다.) 그래서 둘째 단계도 첫 단계처럼 변환 캐시를 찾아야 한다. 그러나 이
단계에서는 속도에 온 힘을 쏟지는 않는다. DT-캐시를 놓치는 일은 드물기 때문이다.

보충: 원본의 이름표 |square_one|은 `|square_one|: |data.state=DT_retry|; |case DT_retry|:' 꼴이고,
|ld_retry|, |prest_span|, |finish_store|도 같은 꼴이다. 넷 다 그 |case|와 합친다. 원본의 이름표
|avoid_D|는 지점이 된다.

@<상수@>=
const (
	dtRetry = 8 // DT-캐시를 다시 찾아야 할 때의 둘째 단계 |state|
	gotDT   = 9 // DT-캐시 항목을 계산했을 때의 둘째 단계 |state|
)
@#
const (
	lSquareOne   = stage2St + dtRetry  // 원본의 |square_one|
	lLdRetry     = stage2St + dtHit    // 원본의 |ld_retry|
	lPrestSpan   = stage2St + prestWin // 원본의 |prest_span|
	lFinishStore = stage2St + stReady  // 원본의 |finish_store|
)

@ @<지점 이름@>=
lAvoidD // 원본의 |avoid_D|

@ @<뒤 단계들의 특별한 상태들@>=
case lSquareOne:
	data.state = dtRetry
	if mx.DTcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.DTcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.DTcache.reader[j], mx.DTcache.accessTime)
	p = mx.cacheSearch(mx.DTcache, mx.transKey(data.y.o))
	if p != nil {
		p = mx.useAndFix(mx.DTcache, p)
		data.z.o = p.data[0]
		@<보호 비트를...@>
		if data.i >= st && data.i <= syncid {
			data.state = stReady
		} else {
			data.state = dtHit
		}
	} else {
		data.state = dtMiss
	}
	return mx.wait(self, mx.DTcache.accessTime)
case stage2St + dtMiss:
	@<DT-캐시를 채우는 코루틴을 띄우고 잠든다@>
case stage2St + gotDT:
	releaseLock(self, &mx.DTcache.fillLock)
	@<보호 비트를...@>
	if data.i >= st && data.i <= syncid {
		pc = lFinishStore
		continue
	}
	fallthrough // 그렇지 않으면 아래의 |ld_retry|로 흘러내린다

@ @<DT-캐시를 채우는 코루틴을...@>=
if mx.DTcache.filler.next != nil {
	if data.i == preld || data.i == prest {
		pc = lFinEx
	} else {
		pc = lSquareOne
	}
	continue
}
if mx.noHardwarePT || mx.pageF != 0 {
	if data.i == preld || data.i == prest {
		pc = lFinEx
	} else {
		pc = lEmulateVirt
	}
	continue
}
p = mx.allocSlot(mx.DTcache, mx.transKey(data.y.o))
if p == nil {
	pc = lSquareOne
	continue
}
data.ptrB, mx.DTcache.fillerCtl.ptrB = p, p
mx.DTcache.fillerCtl.y.o = data.y.o
setLock(self, &mx.DTcache.fillLock)
mx.startup(&mx.DTcache.filler, 1)
data.state = gotDT
if data.i == preld || data.i == prest {
	pc = lFinEx
	continue
}
return mx.sleep(self)

@ 둘째 단계는 데이터를 얻으면서 D-캐시(그리고 어쩌면 S-캐시)를 채우고 싶을 수도 있다.

여러 적재 명령이 같은 캐시 블록을 채우려 할 수도 있다. 그러니 놓쳤는데 곧바로 자리를 할당할 수
없으면 D-캐시로 돌아가 다시 찾아야 한다.

\.{PRELD}나 \.{PREST} 명령은 ``귀띔''일 뿐이므로, 캐시들이 이미 바쁘면 더 아무것도 하지 않는다.

@<뒤 단계들의 특별한 상태들@>=
case lLdRetry:
	data.state = dtHit
	if data.i == preld || data.i == prest {
		pc = lFinEx
		continue
	}
	@<기다리는 쓰기에서 적중하는지 검사한다@>
	if data.z.o>>32&0xffff0000 != 0 || mx.Dcache == nil {
		pc = lAvoidD
		continue
	}
	if mx.Dcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.Dcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
	@<D-캐시에서 |data.z.o|를...@>
	return mx.wait(self, mx.Dcache.accessTime)
case stage2St + hitAndMiss:
	if data.i == ldunc {
		pc = lAvoidD
		continue
	}
	@<위치 |data.z.o|의 내용을 D-캐시에 가져와 본다@>
case lAvoidD:
	@<D-캐시를 찾지 않고 적재/저장의 2단계를 한다@>

@ @<위치 |data.z.o|의 내용을 D-캐시에 가져와 본다@>=
@<|prest|가 캐시 블록 전체에 걸치는지 검사한다@>
if mx.Dcache.filler.next != nil ||
	(mx.Scache != nil && mx.Scache.lock != nil) || (mx.Scache == nil && mx.memLock != nil) {
	pc = lLdRetry
	continue
}
q = mx.allocSlot(mx.Dcache, data.z.o)
if q == nil {
	pc = lLdRetry
	continue
}
if mx.Scache != nil {
	setLock(&mx.Dcache.filler, &mx.Scache.lock)
} else {
	setLock(&mx.Dcache.filler, &mx.memLock)
}
setLock(self, &mx.Dcache.fillLock)
data.ptrB, mx.Dcache.fillerCtl.ptrB = q, q
mx.Dcache.fillerCtl.z.o = data.z.o
if mx.Scache != nil {
	mx.startup(&mx.Dcache.filler, mx.Scache.accessTime)
} else {
	mx.startup(&mx.Dcache.filler, mx.memAddrTime)
}
data.state = ldReady
if data.i == preld || data.i == prest {
	pc = lFinEx
	continue
}
return mx.sleep(self)

@ 내부 명령 |prest|가 뜨거운 자리에 이르면, \.{PREST}를 쓴 사람이 가상 주소
|data.y.o-(data.xx&-Dcache.bb)|부터 |data.y.o+(data.xx&(Dcache.bb-1))|까지의 바이트들의 현재 값은
상관없다고 보장해 준 것이다. 그러니 그 값들이 0이라고 아는 척할 수 있다. 그러면 S-캐시나
메모리에서 캐시 블록을 채우는 일을 덜 수 있어서 이롭다.

@<|prest|가 캐시 블록 전체에...@>=
if data.i == prest {
	bb, yl := mx.Dcache.bb, Tetra(data.y.o)
	if (int(data.xx) >= bb || yl&Tetra(bb-1) == 0) &&
		(yl+Tetra(int(data.xx)&(bb-1))+1)^yl >= Tetra(bb) {
		pc = lPrestSpan
		continue
	}
}

@ @<뒤 단계들의 특별한 상태들@>=
case lPrestSpan:
	data.state = prestWin
	if data != mx.oldHot || mx.dLocker.next != nil {
		return mx.wait(self, 1)
	}
	if mx.Dcache.lock != nil {
		pc = lFinEx
		continue
	}
	q = mx.allocSlot(mx.Dcache, data.z.o) // |Dcache.filler|가 바빠도 괜찮다
	if q != nil {
		cleanBlock(mx.Dcache, q)
		q.tag = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-mx.Dcache.bb))
		setLock(&mx.dLocker, &mx.Dcache.lock)
		mx.startup(&mx.dLocker, mx.Dcache.copyInTime)
	}
	pc = lFinEx
	continue

@ @<D-캐시를 찾지 않고 적재/저장의 2단계를...@>=
if mx.memLock != nil {
	return mx.wait(self, 1)
}
setLock(&mx.memLocker, &mx.memLock)
mx.startup(&mx.memLocker, mx.memAddrTime+mx.memReadTime)
data.x.o = mx.memRead(data.z.o)
data.state = ldReady
return mx.wait(self, mx.memAddrTime+mx.memReadTime)

@ @<기다리는 쓰기에서 적중하는지...@>=
if m := mx.writeSearch(data, data.z.o); m == &mx.dunno {
	return mx.wait(self, 1)
} else if m != nil {
	data.x.o = *m
	data.state = ldReady
	return mx.wait(self, 1)
}

@ 바라던 옥타바이트는 조만간 |data.x.o|에 도착할 것이다. 그러면 적재 명령은 거의 끝난 셈인데,
입력을 조금 주물러야 할 수도 있다.

보충: 원본은 바이트, 와이드, 테트라의 경우에서 |fin_ld|라는 이름표로 모였다가 |default|로 흘러내려
|fin_ex|로 뛰었다. 여기서는 세 경우가 저마다 자리 옮김을 하고 |switch|를 빠져나오며, |switch|
뒤에서 |fin_ex|로 간다. 다른 경우들도 |fin_ex|로 뛰던 것은 그냥 |switch|를 빠져나온다.

@<뒤 단계들의 특별한 상태들@>=
case stage2St + ldReady:
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	if data.i >= st {
		pc = lFinishStore
		continue
	}
	switch data.op >> 1 {
	case LDB >> 1, LDBU >> 1:
		j, i = int(Tetra(data.z.o)&0x7)<<3, 56
		data.x.o = mmixarith.ShiftRight(data.x.o<<j, i, data.op&0x2 != 0)
	case LDW >> 1, LDWU >> 1:
		j, i = int(Tetra(data.z.o)&0x6)<<3, 48
		data.x.o = mmixarith.ShiftRight(data.x.o<<j, i, data.op&0x2 != 0)
	case LDT >> 1, LDTU >> 1:
		j, i = int(Tetra(data.z.o)&0x4)<<3, 32
		data.x.o = mmixarith.ShiftRight(data.x.o<<j, i, data.op&0x2 != 0)
	@<적재한 데이터를 고치는 다른 경우들@>
	}
	pc = lFinEx
	continue

@ 보충: 원본은 |z.o|의 비트~2가 켜져 있으면 아랫 테트라를 윗 테트라로 옮겼다. 여기서는 그
옮김을 32비트 자리 옮김으로 쓴다.

@<적재한 데이터를 고치는...@>=
case LDHT >> 1:
	if data.z.o&4 != 0 {
		data.x.o <<= 32
	}
	data.x.o &^= 0xffffffff
case LDSF >> 1:
	if data.z.o&4 != 0 {
		data.x.o = data.x.o<<32 | data.x.o&0xffffffff
	}
	if h := Tetra(data.x.o >> 32); h&0x7f800000 == 0 && h&0x7fffff != 0 {
		data.x.o = mmixarith.LoadSF(h)
		data.state = 3
		return mx.wait(self, mx.deninPenalty)
	}
	data.x.o = mmixarith.LoadSF(Tetra(data.x.o >> 32))
case LDPTP >> 1:
	if data.x.o&signBit == 0 || int(data.x.o&0x1ff8) != mx.pageN {
		data.x.o = 0
	} else {
		data.x.o &^= 1<<13 - 1
	}
case LDPTE >> 1:
	if int(data.x.o&0x1ff8) != mx.pageN {
		data.x.o = 0
	} else {
		data.x.o = data.x.o&^mx.pageMask + data.x.o&0x7
	}
	data.x.o &= 0xffff<<32 | 0xffffffff
case UNSAVE >> 1:
	@<적재할 때가 된 내부 \.{UNSAVE}를 다룬다@>

@ 보충: 원본의 |switch|에서 |case|는 저마다 |fin_ex|나 |do_syncd|, |do_syncid|로 뛰었다. 원본의
이름표 |do_syncd|와 |do_syncid|는 뒤에서 나온다.

@<뒤 단계들의 특별한 상태들@>=
case lFinishStore:
	data.state = stReady
	switch data.i {
	case st, pst:
		@<저장 명령을 마친다@>
		pc = lFinEx
		continue
	case syncd:
		bb := 8192
		if mx.Dcache != nil {
			bb = mx.Dcache.bb
		}
		data.b.o = data.b.o&^0xffffffff | Octa(Tetra(bb))
		pc = lDoSyncd
		continue
	case syncid:
		bb := 8192
		if mx.Icache != nil {
			bb = mx.Icache.bb
		}
		if mx.Dcache != nil && mx.Dcache.bb < bb {
			bb = mx.Dcache.bb
		}
		data.b.o = data.b.o&^0xffffffff | Octa(Tetra(bb))
		pc = lDoSyncid
		continue
	}
	return true // 원본에서는 |switch|를 빠져나가 |terminate|에 이른다

@ 저장 명령에는 복잡한 점이 하나 더 있다. 어떤 것들은 넘침을 검사해야 하기 때문이다.

보충: 원본의 |switch|에서 |fin_ex|로 뛰던 |case|들은 여기서 그냥 |switch|를 빠져나간다. 원본의
|fin_st|는 세 경우가 모이던 이름표인데, 여기서는 그 뒤의 절을 세 번 끼워 넣는다.

@<저장 명령을 마친다@>=
data.x.addr = data.z.o
if data.b.p != nil {
	return mx.wait(self, 1)
}
switch data.op >> 1 {
case STUNC >> 1:
	data.i = stunc
	fallthrough
default:
	data.x.o = data.b.o
case STSF >> 1:
	mx.setRound(data)
	{
		h, exc := mmixarith.StoreSF(data.b.o, mx.curRound)
		mx.exceptions = exc
		data.b.o = Octa(h)<<32 | data.b.o&0xffffffff
	}
	data.interrupt |= Tetra(mx.exceptions)
	if h := Tetra(data.b.o >> 32); h&0x7f800000 == 0 && h&0x7fffff != 0 {
		@<|data.b.o|의 윗 테트라를 |data.x.o|의 알맞은 절반에 넣는다@>
		data.state = 3
		return mx.wait(self, mx.denoutPenalty)
	}
	fallthrough
case STHT >> 1:
	@<|data.b.o|의 윗 테트라를...@>
case STB >> 1, STBU >> 1:
	j, i = int(Tetra(data.z.o)&0x7)<<3, 56
	@<|data.b.o|를 |data.x.o|의 알맞은 필드에 넣고, 부호 있으면 산술 예외를 검사한다@>
case STW >> 1, STWU >> 1:
	j, i = int(Tetra(data.z.o)&0x6)<<3, 48
	@<|data.b.o|를 |data.x.o|의...@>
case STT >> 1, STTU >> 1:
	j, i = int(Tetra(data.z.o)&0x4)<<3, 32
	@<|data.b.o|를 |data.x.o|의...@>
case CSWAP >> 1:
	@<\.{CSWAP}을 마친다@>
case SAVE >> 1:
	@<저장할 때가 된 내부 \.{SAVE}를 다룬다@>
}

@ @<|data.b.o|의 윗 테트라를...@>=
if data.z.o&4 != 0 {
	data.x.o = data.x.o&^0xffffffff | data.b.o>>32
} else {
	data.x.o = data.x.o&0xffffffff | data.b.o&^0xffffffff
}

@ @<|data.b.o|를 |data.x.o|의...@>=
if data.op&2 == 0 {
	before := data.b.o
	after := mmixarith.ShiftRight(data.b.o<<i, i, false)
	if before != after {
		data.interrupt |= vBit
	}
}
{
	mask := mmixarith.ShiftRight(negOne<<i, j, true)
	data.b.o = mmixarith.ShiftRight(data.b.o<<i, j, true)
	data.x.o ^= mask & (data.x.o ^ data.b.o)
}

@ \.{CSWAP} 연산은 입력이 넷 $\rm(\$X, \$Y, \$Z, rP)$이고 출력이 셋 $\rm(\$X,M_8[A],rP)$이다.
파이프라인의 제어 블록이 담을 수 있는 양을 넘지 않도록, 이 명령이 뜨거운 자리에 이를 때까지
기다린다. 그러면 rP에 투기 없이 접근할 수 있다.

@<\.{CSWAP}을 마친다@>=
if data != mx.oldHot {
	return mx.wait(self, 1)
}
if data.x.o == mx.g[rP].o {
	data.a.o = 1 // |data.a.o|의 윗 테트라는 0이다
	data.x.o = data.b.o
} else {
	mx.g[rP].o = data.x.o // |data.a.o|는 0이다
	if mx.verbose&issueBit != 0 {
		mx.printf(" setting rP=")
		mx.printOcta(mx.g[rP].o)
		mx.printf("\n")
	}
}
data.i = cswap // 겉모습만 바꾼다. 추적 출력에만 영향을 준다

@* 가져오기 단계. 가장 어려운 메모리 연산들을 익혔으니, 이제 긴장을 풀고 그 지식을 조금 더
단순한 일, 곧 가져오기 버퍼를 채우는 일에 쓸 수 있다. 가져오기는 적재/저장과 비슷하지만, D-캐시
대신 I-캐시를 쓴다. I-캐시는 읽기 전용이므로 조금 더 단순하다. 가져오기 장치는 하나뿐이므로
\.{PREGO} 명령이 없다면 더 단순하게 할 수 있을 것이다. 그러나 그 명령이 쓸모 있는지 알아보려면
\.{PREGO}를 꽤 효율적으로 구현하고 싶다. 그래서 D-캐시와 DT-캐시에서 이미 구현한, I-캐시와
IT-캐시를 동시에 읽는 복잡함을 여기에도 넣는다.

가져오기 코루틴은 |stage| 번호가~0인 유일한 코루틴으로서 늘 있다.

보통 상황에서 가져오기 코루틴은 가상 주소가 |instPtr|(명령 포인터)로 주어진 명령이 든 캐시
블록에 접근해서, 그 블록에서 명령을 |fetchMax|개까지 가져오기 버퍼로 옮긴다. 명령이 캐시에
없거나, IT-캐시를 놓쳐서 가상 주소를 변환할 수 없으면 복잡해진다. 더욱이 |instPtr|는 \KW{spec}
변수여서 그 값을 아직 모를 수도 있다. 포인터 |instPtr.p|가 |nil|이 아니면 무엇을 가져올지 모른다.
@^program counter@>

@<기계의 상태@>=
instPtr spec   // 명령 포인터(프로그램 계수기라고도 한다)
fetched []Octa // 들어오는 명령을 담는 버퍼

@ 가져오기 코루틴은 대개 |fetchReady| 상태에서 사이클을 시작하는데, 이때 가장 최근에 가져온
옥타바이트들이 |fetched|라는 버퍼의 자리 |fetchLo|, |fetchLo+1|, \dots, |fetchHi-1|에 있다.
그 버퍼를 다 쓰면 코루틴은 상태~0으로 돌아간다. 운이 좋으면 다음 사이클이 돌아올 때쯤 버퍼에
데이터가 더 있을지도 모른다.

@<기계의 상태@>=
fetchLo, fetchHi int // 그 버퍼의 활성 영역
fetchCo          coroutine
fetchCtl         control

@ @<모든 것을 초기화한다@>=
mx.fetchCo.ctl = &mx.fetchCtl
mx.fetchCo.name = "Fetch"
mx.fetchCtl.goLoc.o = 4
mx.startup(&mx.fetchCo, 1)

@ @<가져오기 코루틴을 다시 시작한다@>=
if mx.fetchCo.lockloc != nil {
	*mx.fetchCo.lockloc = nil
	mx.fetchCo.lockloc = nil
}
mx.unschedule(&mx.fetchCo)
mx.startup(&mx.fetchCo, 1)

@ 여기의 동작 가운데 일부는 가져오기 코루틴만이 아니라 |prego| 연산의 첫 단계와 둘째 단계도
한다.

보충: 원본의 매크로 |wait_or_pass(t)|는 |prego|이면 |pass_after(t)|를 하고 |passit|으로 뛰었고,
그렇지 않으면 |wait(t)|를 했다. 여기서는 메서드 |waitOrPass|가 참을 돌려주면 |passit|으로 간다.
그래서 원본의 |wait_or_pass(t)|는, |waitOrPass(self,t)|가 참이면 |pc=lPassit|로 하고
|continue|하는 |if| 문과 그 뒤의 |return false|가 된다.

@<함수들@>=
func (mx *machine) waitOrPass(self *coroutine, t int) bool {
	if self.ctl.i == prego {
		mx.passAfter(self, t)
		return true
	}
	mx.wait(self, t)
	return false
}

@ 보충: 원본의 이름표 |new_fetch|는 `|new_fetch|: |data.state=0|; |case 0|:' 꼴이므로 상태~0의
|case|와 합친다. 이름표 |start_fetch|는 |case 1| 바로 뒤에 있으므로 상태~1의 |case|와 같다.
이름표 |known_phys|, |bad_fetch|, |swym_one|, |fetch_one|은 지점이 된다.

@<상수@>=
const (
	lNewFetch   = fetchSt + 0 // 원본의 |new_fetch|
	lStartFetch = fetchSt + 1 // 원본의 |start_fetch|
)

@ @<지점 이름@>=
lKnownPhys // 원본의 |known_phys|
lBadFetch  // 원본의 |bad_fetch|
lSwymOne   // 원본의 |swym_one|
lFetchOne  // 원본의 |fetch_one|

@ @<가져오기 코루틴의 동작을...@>=
case lSwitch0:
	pc = fetchSt + label(data.state)
	continue
case lNewFetch:
	data.state = 0
	@<필요하면 명령 포인터를 알 때까지 기다린다@>
	data.y.o = mx.instPtr.o
	data.state = 1
	data.interrupt = 0
	data.x.o, data.z.o = 0, 0
	fallthrough
case lStartFetch:
	if data.y.o&signBit != 0 {
		@<물리 주소를 아는 가져오기를 시작한다@>
	}
	if mx.pageBad {
		pc = lBadFetch
		continue
	}
	if mx.ITcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.ITcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.ITcache.reader[j], mx.ITcache.accessTime)
	@<IT-캐시에서 주소를 찾고, 할 수 있으면 I-캐시에서도 찾는다@>
	if mx.waitOrPass(self, mx.ITcache.accessTime) {
		pc = lPassit
		continue
	}
	return false
@<가져오기 코루틴의 다른 경우들@>

@ @<|prego|나 |ldvts| 같은...@>=
if data.i == prego {
	pc = lStartFetch
	continue
}

@ @<필요하면 명령 포인터를...@>=
if mx.instPtr.p != nil {
	if mx.instPtr.p != &mx.unknownSpec && mx.instPtr.p.known {
		mx.instPtr.o, mx.instPtr.p = mx.instPtr.p.o, nil
	}
	return mx.wait(self, 1)
}

@ @<상수@>=
const (
	gotIT       = 19 // IT-캐시 항목을 계산했을 때의 |state|
	itMiss      = 20 // IT-캐시에 열쇠가 없을 때의 |state|
	itHit       = 21 // 명령의 물리 주소를 알 때의 |state|
	iHitAndMiss = 22 // I-캐시를 놓쳤을 때의 |state|
	fetchReady  = 23 // 명령들을 읽었을 때의 |state|
	gotOne      = 24 // ``미리 보기'' 옥타바이트가 준비되었을 때의 |state|
)

@ @<IT-캐시에서 주소를 찾고...@>=
p = mx.cacheSearch(mx.ITcache, mx.transKey(data.y.o))
if mx.Icache == nil || mx.Icache.lock != nil {
	@<I-캐시를 찾지 않고 가져오기를 시작한다@>
}
if j = getReader(mx.Icache); j < 0 {
	@<I-캐시를 찾지 않고...@>
}
mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)
if p != nil {
	@<I-캐시에서도 동시에 찾는다@>
} else {
	data.state = itMiss
}

@ IT-캐시에서 가상 주소를 찾는 것과 동시에 I-캐시에서 해당하는 물리 주소를 찾을 수 있다고
가정한다. 다만 두 주소의 아래 $b+c$비트가 같아야 한다. (DT-캐시와 D-캐시에 대해 비슷한 가정을
할 때 한 ``페이지 채색'' 이야기를 보라.)
@^page coloring@>

@<I-캐시에서도 동시에...@>=
@<IT-캐시의 쓰임을 고치고 보호 비트를 검사한다@>
data.z.o = mx.physAddr(data.y.o, p.data[0])
if mx.Icache.b+mx.Icache.c > mx.pageS &&
	(Tetra(data.y.o)^Tetra(data.z.o))&Tetra((mx.Icache.bb<<mx.Icache.c)-(1<<mx.pageS)) != 0 {
	data.state = itHit // 가짜 I-캐시 찾기
} else {
	@<I-캐시에서 |data.z.o|를 찾아 적중하면 |fetched|로 복사한다@>
}
if mx.waitOrPass(self, max(mx.ITcache.accessTime, mx.Icache.accessTime)) {
	pc = lPassit
	continue
}
return false

@ @<I-캐시에서 |data.z.o|를...@>=
q = mx.cacheSearch(mx.Icache, data.z.o)
if q != nil {
	q = mx.useAndFix(mx.Icache, q)
	@<블록~|q|의 데이터를 |fetched|로 복사한다@>
	data.state = fetchReady
} else {
	data.state = iHitAndMiss
}

@ @<IT-캐시의 쓰임을 고치고...@>=
p = mx.useAndFix(mx.ITcache, p)
if Tetra(p.data[0])&(pxBit>>protOffset) == 0 {
	pc = lBadFetch
	continue
}

@ 이 시점에서 |instPtr.o|는 |data.y.o|와 같다.

@<블록~|q|의 데이터를...@>=
if data.i != prego {
	for j = 0; j < mx.Icache.bb>>3; j++ {
		mx.fetched[j] = q.data[j]
	}
	mx.fetchLo = int(Tetra(mx.instPtr.o)&Tetra(mx.Icache.bb-1)) >> 3
	mx.fetchHi = mx.Icache.bb >> 3
}

@ @<I-캐시를 찾지 않고...@>=
if p != nil {
	@<IT-캐시의 쓰임을...@>
	data.z.o = mx.physAddr(data.y.o, p.data[0])
	data.state = itHit
} else {
	data.state = itMiss
}
if mx.waitOrPass(self, mx.ITcache.accessTime) {
	pc = lPassit
	continue
}
return false

@ 보충: 원본은 이 절의 한가운데에 이름표 |known_phys|를 두었다. 여기서는 그 뒷부분이 지점
|lKnownPhys|의 |case|다.

@<물리 주소를 아는 가져오기를...@>=
if data.i == prego && data.loc&signBit == 0 {
	pc = lFinEx
	continue
}
data.z.o = data.y.o - signBit
pc = lKnownPhys
continue

@ @<가져오기 코루틴의 다른 경우들@>=
case lKnownPhys:
	if data.z.o>>32&0xffff0000 != 0 {
		pc = lBadFetch
		continue
	}
	if mx.Icache == nil {
		@<메모리에서 |fetched|로 읽는다@>
	}
	if mx.Icache.lock != nil {
		data.state = itHit
		if mx.waitOrPass(self, 1) {
			pc = lPassit
			continue
		}
		return false
	}
	if j = getReader(mx.Icache); j < 0 {
		data.state = itHit
		if mx.waitOrPass(self, 1) {
			pc = lPassit
			continue
		}
		return false
	}
	mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)
	@<I-캐시에서 |data.z.o|를...@>
	if mx.waitOrPass(self, mx.Icache.accessTime) {
		pc = lPassit
		continue
	}
	return false

@ @<메모리에서 |fetched|로...@>=
if mx.memLock != nil {
	return mx.wait(self, 1)
}
setLock(&mx.memLocker, &mx.memLock)
mx.startup(&mx.memLocker, mx.memAddrTime+mx.memReadTime)
{
	addr := data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-(mx.busWords<<3)))
	mx.fetched[0] = mx.memRead(addr)
	for j = 1; j < mx.busWords; j++ {
		mx.fetched[j] = mx.memHash[mx.lastH].chunk[int(Tetra(addr)&0xffff)>>3+j]
	}
}
mx.fetchLo = int(Tetra(data.z.o)>>3) & (mx.busWords - 1)
mx.fetchHi = mx.busWords
data.state = fetchReady
return mx.wait(self, mx.memAddrTime+mx.memReadTime)

@ 보충: 원본의 이름표 |fetch_retry|는 `|fetch_retry|: |data.state=IT_hit|; |case IT_hit|:' 꼴이므로
그 |case|와 합친다.

@<상수@>=
const lFetchRetry = fetchSt + itHit // 원본의 |fetch_retry|

@ @<가져오기 코루틴의 다른 경우들@>=
case fetchSt + itMiss:
	if mx.ITcache.filler.next != nil {
		if data.i == prego {
			pc = lFinEx
			continue
		}
		return mx.wait(self, 1)
	}
	if mx.noHardwarePT || mx.pageF != 0 {
		@<페이지 테이블 에뮬레이션을 위한 가짜 명령을 끼워 넣는다@>
	}
	p = mx.allocSlot(mx.ITcache, mx.transKey(data.y.o))
	if p == nil { // 이런, 결국 있었다
		if data.i == prego {
			pc = lFinEx
		} else {
			pc = lNewFetch
		}
		continue
	}
	data.ptrB, mx.ITcache.fillerCtl.ptrB = p, p
	mx.ITcache.fillerCtl.y.o = data.y.o
	setLock(self, &mx.ITcache.fillLock)
	mx.startup(&mx.ITcache.filler, 1)
	data.state = gotIT
	if data.i == prego {
		pc = lFinEx
		continue
	}
	return mx.sleep(self)

@ @<가져오기 코루틴의 다른 경우들@>=
case fetchSt + gotIT:
	releaseLock(self, &mx.ITcache.fillLock)
	if Tetra(data.z.o)&(pxBit>>protOffset) == 0 {
		pc = lBadFetch
		continue
	}
	data.z.o = mx.physAddr(data.y.o, data.z.o)
	fallthrough
case lFetchRetry:
	data.state = itHit
	if data.i == prego {
		pc = lFinEx
	} else {
		pc = lKnownPhys
	}
	continue
case fetchSt + iHitAndMiss:
	@<위치 |data.z.o|의 내용을 I-캐시에 가져와 본다@>

@ @<뒤 단계들의 특별한 상태들@>=
case stage2St + itMiss, stage2St + iHitAndMiss, stage2St + itHit, stage2St + fetchReady:
	pc = lSwitch0
	continue

@ @<위치 |data.z.o|의 내용을 I-캐시에...@>=
if mx.Icache.filler.next != nil ||
	(mx.Scache != nil && mx.Scache.lock != nil) || (mx.Scache == nil && mx.memLock != nil) {
	pc = lFetchRetry
	continue
}
q = mx.allocSlot(mx.Icache, data.z.o)
if q == nil {
	pc = lFetchRetry
	continue
}
if mx.Scache != nil {
	setLock(&mx.Icache.filler, &mx.Scache.lock)
} else {
	setLock(&mx.Icache.filler, &mx.memLock)
}
setLock(self, &mx.Icache.fillLock)
data.ptrB, mx.Icache.fillerCtl.ptrB = q, q
mx.Icache.fillerCtl.z.o = data.z.o
if mx.Scache != nil {
	mx.startup(&mx.Icache.filler, mx.Scache.accessTime)
} else {
	mx.startup(&mx.Icache.filler, mx.memAddrTime)
}
data.state = gotOne
if data.i == prego {
	pc = lFinEx
	continue
}
return mx.sleep(self)

@ I-캐시를 채우는 코루틴은 캐시 블록 전체를 채우기 전에 우리가 바라는 옥타바이트를 가지고
우리를 깨운다. 그러면 블록의 나머지가 적재되기 전에 명령을 한두 개 가져올 수 있다.

보충: 원본은 가져오기 버퍼를 채우는 루프 안에서 |goto new_fetch|로 뛰었다. 여기서는 불 변수
|newFetch|를 켜고 루프를 빠져나온다.

@<가져오기 코루틴의 다른 경우들@>=
case lBadFetch:
	if data.i == prego {
		pc = lFinEx
		continue
	}
	data.interrupt |= pxBit
	fallthrough
case lSwymOne:
	mx.fetched[0] = SWYM<<24<<32 | SWYM<<24
	pc = lFetchOne
	continue
case fetchSt + gotOne:
	mx.fetched[0] = data.x.o // 새 캐시 데이터의 ``미리 보기''
	fallthrough
case lFetchOne:
	mx.fetchLo, mx.fetchHi = 0, 1
	data.state = fetchReady
	fallthrough
case fetchSt + fetchReady:
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	if data.i == prego {
		pc = lFinEx
		continue
	}
	@<가져온 명령들을 가져오기 버퍼에 넣는다@>
	return mx.wait(self, 1)

@ @<가져온 명령들을...@>=
newFetch := false
for j = 0; j < mx.fetchMax; j++ {
	newTail := mx.prevFetch(mx.tail)
	if newTail == mx.head {
		break // 가져오기 버퍼가 차 있다
	}
	@<|tail| 자리에 새 명령을 넣는다@>
	mx.tail = newTail
	if mx.sleepy {
		mx.sleepy = false
		return mx.sleep(self)
	}
	mx.instPtr.o += 4
	if mx.fetchLo == mx.fetchHi {
		newFetch = true
		break
	}
}
if newFetch {
	pc = lNewFetch
	continue
}

@ @<페이지 테이블 에뮬레이션을 위한...@>=
if mx.cacheSearch(mx.ITcache, mx.transKey(mx.instPtr.o)) != nil {
	pc = lNewFetch
	continue
}
data.interrupt |= fBit
mx.sleepy = true
pc = lSwymOne
continue

@ @<기계의 상태@>=
sleepy bool // 페이지 테이블 에뮬레이션 호출을 막 내보냈는가?

@ 이 시점에서 터무니없이 잘못된 명령을 검사한다. (배정기가 안에서 만든 명령을 위해 그런
명령이 가져오기 버퍼를 차지하도록 실제로 허락할 때도 있다.)

@<|tail| 자리에 새 명령을...@>=
mx.tail.loc = mx.instPtr.o
if mx.instPtr.o&4 != 0 {
	mx.tail.inst = Tetra(mx.fetched[mx.fetchLo])
	mx.fetchLo++
} else {
	mx.tail.inst = Tetra(mx.fetched[mx.fetchLo] >> 32)
}
@^big-endian versus little-endian@>
@^little-endian versus big-endian@>
mx.tail.interrupt = data.interrupt
i = int(mx.tail.inst >> 24)
if i >= RESUME && i <= SYNC && mx.tail.inst&badInstMask[i-RESUME] != 0 {
	mx.tail.interrupt |= bBit
}
mx.tail.noted = false
if mx.instPtr.o == mx.breakpoint {
	mx.breakpointHit = true
}

@ 명령 \.{RESUME}, \.{SAVE}, \.{UNSAVE}, \.{SYNC}는 여기서 정한 자리에 0이 아닌 비트가 있으면
안 된다.

@<표@>=
var badInstMask = [4]Tetra{0xfffffe, 0xffff, 0xffff00, 0xfffff8}

@* 인터럽트. 파이프라인 기계의 설계에서 가장 무서운 것은 인터럽트의 존재다. 인터럽트는 미리
내다보기 어려운 방식으로 계산의 매끄러운 흐름을 깨뜨린다. 그러나 다행히 명령을 차례대로 확정하게
하는 재정렬 버퍼의 규율 덕분에 인터럽트를 꽤 자연스럽게 다룰 수 있다. 그래서 동적 스케줄링과
투기적 실행의 문제를 푼 우리의 방법이 인터럽트 문제도 풀어 준다.
@^interrupts@>

\MMIX에는 인터럽트가 세 가지 있는데, 명령이 확정될 준비가 되었을 때 |interrupt| 필드에 비트
코드로 나타난다. 비트 |hBit|는 \.{TRIP} 명령과 산술 예외를 위한 트립 처리기를 부른다. 비트 |fBit|는 \.{TRAP} 명령과, 소프트웨어로 에뮬레이트해야 하는 구현되지 않은 명령을 위한 강제 트랩 처리기를
부른다. 비트 |eBit|는 입출력 신호 같은 바깥 인터럽트나 부적절한 명령 때문에 생기는 안쪽 인터럽트를
위한 동적 트랩 처리기를 부른다. 세 경우 모두, 인터럽트된 명령이 확정될 준비가 될 무렵에는
파이프라인 제어가 이미 올바른 처리기 주소에서 새 명령을 가져오도록 방향을 바꾸어 놓았다.

@ 대부분의 명령은 실행을 마쳤을 때 여덟 트립 비트나 여덟 트랩 비트 가운데 1이 있으면 프로그램의
다음 부분에 온다.

트립 비트가 모두 0은 아니면 rA의 사건 비트를 고치거나, 허용된 트립 처리기를 수행하거나, 둘 다
하고 싶다. 트랩 비트가 0이 아니면 뜨거운 자리에 이를 때까지 그 비트들을 붙들고 있어야 한다.
그때 그 비트들은 rQ의 비트들과 합쳐져서 아마도 인터럽트를 일으킬 것이다. 트랩 비트가 0이 아닌
적재나 저장 명령은 확정되지 않고 무효가 된다.

정확하고 허용되지 않은 아래넘침은 IEEE 표준의 관례에 따라 무시한다. (이것은 |resumeSet|이
일으킨 아래넘침에도 적용된다.)

보충: 원본의 매크로 |is_load_store|는 여러 곳에서 쓰므로 함수 |isLoadStore|다. 원본의 이름표
|emulate_virt|는 지점이 되고, |state_4|와 |state_5|는 `|state_4|: |data.state=4|; |case 4|:' 꼴이므로
그 |case|와 합친다.

@<함수들@>=
func isLoadStore(i int) bool {
	return i >= ld && i <= cswap
}

@ @<지점 이름@>=
lEmulateVirt // 원본의 |emulate_virt|

@ @<상수@>=
const (
	lState4 = stage1St + 4 // 원본의 |state_4|
	lState5 = stage1St + 5 // 원본의 |state_5|
)

@ @<실행 단계 끝에서 인터럽트를...@>=
if data.interrupt&0xff != 0 && isLoadStore(data.i) {
	pc = lState5
	continue
}
j = int(data.interrupt & 0xff00)
data.interrupt -= Tetra(j)
if j&(uBit+xBit) == uBit && Tetra(data.ra.o)&uBit == 0 {
	j &^= uBit
}
data.arithExc = (Tetra(j) &^ Tetra(data.ra.o)) >> 8
if Tetra(j)&Tetra(data.ra.o) != 0 {
	@<예외 트립 처리기를 준비한다@>
}
if data.interrupt&0xff != 0 {
	pc = lState5
	continue
}

@ 실행은 투기적이므로 예외 조건이 ``진짜'' 계산의 일부가 아닐 수도 있다. 사실 현재 코루틴의
발행이 이미 취소되었을 수도 있다.

보충: 원본은 지역 변수 |m|을 |MMIX_run|의 것으로 썼다. 여기서는 이 절의 지역 변수다.

@<예외 트립 처리기를...@>=
i = mx.issuedBetween(data, mx.cool)
if i < mx.deissues {
	pc = lDie
	continue
}
mx.deissues = i
mx.oldTail, mx.tail = mx.head, mx.head // 가져오기 버퍼를 비운다
mx.resuming = 0
@<가져오기 코루틴을 다시 시작한다@>
mx.coolHist = data.hist
m := 16
for i = j & int(Tetra(data.ra.o)); i&dBit == 0; i <<= 1 {
	m += 16
}
data.arithExc |= Tetra(j&^(0x10000>>(m>>4))) >> 8 // 일어난 트립은 사건으로 기록하지 않는다
data.goLoc.o = Octa(m)
mx.instPtr = spec{o: data.goLoc.o}
data.interrupt |= hBit
pc = lState4
continue

@ @<페이지 변환을 에뮬레이트할 준비를 한다@>=
i = mx.issuedBetween(data, mx.cool)
if i < mx.deissues {
	pc = lDie
	continue
}
mx.deissues = i
mx.oldTail, mx.tail = mx.head, mx.head // 가져오기 버퍼를 비운다
mx.resuming = 0
@<가져오기 코루틴을 다시 시작한다@>
mx.coolHist = data.hist
mx.instPtr.p = &mx.unknownSpec
data.interrupt |= fBit

@ 재정렬 버퍼 안에서 트립 처리기를 부를 때는 배정을 멈추어야 한다. 그러지 않으면 |g[255]|나
rB를 피연산자로 쓰는 명령을 발행할 수도 있기 때문이다.

@<첫 단계의 특별한 상태들@>=
case lEmulateVirt:
	@<페이지 변환을 에뮬레이트할...@>
	fallthrough
case lState4:
	data.state = 4
	if mx.dispatchLock != nil {
		return mx.wait(self, 1)
	}
	setLock(self, &mx.dispatchLock)
	fallthrough
case lState5:
	data.state = 5
	if data != mx.oldHot {
		return mx.wait(self, 1)
	}
	if data.interrupt&fBit != 0 && data.i != trap {
		mx.instPtr = spec{o: mx.g[rT].o}
		if isLoadStore(data.i) {
			mx.nullifying = true
		}
	}
	if data.interrupt&0xff != 0 {
		mx.g[rQ].o |= Octa(data.interrupt&0xff) << 32
		mx.newQ |= Octa(data.interrupt&0xff) << 32
		if mx.verbose&issueBit != 0 {
			mx.printf(" setting rQ=")
			mx.printOcta(mx.g[rQ].o)
			mx.printf("\n")
		}
	}
	pc = lDie
	continue

@ 앞 절의 명령들은 코루틴 1단계의 스위치에만 나타난다. 뒤 단계들에서도 써야 한다.

@<뒤 단계들의 특별한 상태들@>=
case stage2St + 4:
	pc = lState4
	continue
case stage2St + 5:
	pc = lState5
	continue

@ 보충: 원본은 \.{TRAP}의 경우에서 이름표 |increase_L|로 뛰었다. 그 부분은 절 ``L을 늘리는 내부
명령을 끼워 넣는다''다.

@<명령 배정의 특별한 경우들@>=
case trap:
	if flags[op]&xIsDestBit != 0 && int(cool.xx) < mx.coolG && int(cool.xx) >= mx.coolL {
		@<L을 늘리는 내부 명령을...@>
	}
	if !mx.g[rT].up.known || !mx.g[rJ].up.known {
		break stall
	}
	mx.instPtr = mx.specval(&mx.g[rT]) // 트랩과 에뮬레이트하는 연산
	cool.needB, cool.b = true, mx.specval(&mx.g[255])
	fallthrough
case trip:
	if !mx.g[rJ].up.known {
		break stall
	}
	cool.renX = true
	mx.specInstall(&mx.g[255], &cool.x)
	cool.x.known, cool.x.o = true, mx.g[rJ].up.o
	if i == trip {
		cool.goLoc.o = 0
	}
	cool.renA = true
	if i == trap {
		mx.specInstall(&mx.g[rBB], &cool.a)
	} else {
		mx.specInstall(&mx.g[rB], &cool.a)
	}

@ @<1단계 실행의 경우들@>=
case trap:
	data.interrupt |= fBit
	data.a.o = data.b.o
	pc = lFinEx
	continue
case trip:
	data.interrupt |= hBit
	data.a.o = data.b.o
	pc = lFinEx
	continue

@ 다음 검사는 사이클마다 처음에 한다. 뜨거운 자리의 명령은 확정될 준비가 되어 있고 이미 트립이나
트랩으로 표시되어 있지 않을 때만 바깥에서 인터럽트할 수 있다.

@<바깥 인터럽트를 검사한다@>=
mx.g[rI].o--
if mx.g[rI].o == 0 {
	mx.g[rQ].o |= intervalTimeout
	mx.newQ |= intervalTimeout
	if mx.verbose&issueBit != 0 {
		mx.printf(" setting rQ=")
		mx.printOcta(mx.g[rQ].o)
		mx.printf("\n")
	}
}
mx.tryingToInterrupt = false
if mx.g[rQ].o&mx.g[rK].o != 0 && mx.cool != mx.hot &&
	mx.hot.interrupt&(eBit+fBit+hBit) == 0 && mx.doingInterrupt == 0 &&
	mx.hot.i != resum {
	if mx.hot.owner != nil {
		mx.tryingToInterrupt = true
	} else {
		mx.hot.interrupt |= eBit
		@<가장 뜨거운 명령 말고는 모두 발행을 취소한다@>
		mx.instPtr = spec{o: mx.g[rTT].o}
	}
}

@ @<기계의 상태@>=
tryingToInterrupt bool // 가로막을 수 있는 연산들에게 멈추기를 권하는가?
nullifying        bool // 적재/저장 명령을 무효로 만들려고 배정을 멈추는가?

@ 뜨거운 자리의 명령이 발행 취소되었을 수도 있지만, 시뮬레이터가 사용자의 요청으로 그렇게 했을
때뿐이다. 그렇지 않으면 여기서 `|i>=deissues|' 검사는 늘 성공한다.

변수 |coolHist|의 값은 여기서 믿을 수 없게 된다. 엄밀하게 최신으로 유지하려고 애쓸 수도 있겠지만,
바깥 인터럽트의 예측할 수 없는 성질을 생각하면 그냥 두는 편이 낫다. (그것은 분기 예측을 위한
발견적 방법일 뿐이고, 충분히 강한 예측은 인터럽트 때문에 한 번 생기는 결함을 견딜 것이다.)

@<가장 뜨거운 명령 말고는...@>=
i = mx.issuedBetween(mx.hot, mx.cool)
if i >= mx.deissues {
	mx.deissues = i
	mx.tail = mx.head // 가져오기 버퍼를 비운다
	mx.resuming = 0
	@<가져오기 코루틴을 다시 시작한다@>
	if isLoadStore(mx.hot.i) {
		mx.nullifying = true
	}
}

@ 인터럽트된 명령은 공식적으로 ``확정''되었거나 ``무효''가 되었더라도, 나중에 계산을 다시
시작할 만큼 기계 상태를 저장하는 동안 두세 사이클 더 뜨거운 자리에 머문다.

@<인터럽트를 시작하고 |break|한다@>=
if hot.interrupt&hBit == 0 {
	mx.g[rK].o = 0 // 트랩
}
if (hot.interrupt&hBit != 0 && hot.i != trip) ||
	(hot.interrupt&fBit != 0 && hot.i != trap) || hot.interrupt&eBit != 0 {
	mx.doingInterrupt = 3
	mx.suppressDispatch = true
} else {
	mx.doingInterrupt = 2 // 배정기가 시작한 트립이나 트랩
}
break

@ 메모리 실패가 일어나면 여기서, 경우~2나 경우~1에서 rF를 정해야 한다. 이 시뮬레이터는 지금은
rF로 아무것도 하지 않는다.

@<인터럽트 준비의 한 사이클을...@>=
d := mx.doingInterrupt
mx.doingInterrupt--
switch d {
case 3:
	@<재개 레지스터 $\rm(rB,\$255)$나 $\rm(rBB,\$255)$를 정한다@>
case 2:
	@<재개 레지스터 $\rm(rW,rX)$나 $\rm(rWW,rXX)$를 정한다@>
case 1:
	@<재개 레지스터 $\rm(rY,rZ)$나 $\rm(rYY,rZZ)$를 정한다@>
	mx.hot = mx.prevCtl(mx.hot)
}

@ @<재개 레지스터 $\rm(rB,\$255)$나...@>=
j = int(mx.hot.interrupt & hBit)
if j != 0 {
	mx.g[rB].o = mx.g[255].o
} else {
	mx.g[rBB].o = mx.g[255].o
}
mx.g[255].o = mx.g[rJ].o
if mx.verbose&issueBit != 0 {
	if j != 0 {
		mx.printf(" setting rB=")
		mx.printOcta(mx.g[rB].o)
	} else {
		mx.printf(" setting rBB=")
		mx.printOcta(mx.g[rBB].o)
	}
	mx.printf(", $255=")
	mx.printOcta(mx.g[255].o)
	mx.printf("\n")
}

@ 재개를 위한 ``ropcode''는 여기서 만든다.

@<상수@>=
const (
	resumeAgain = 0 // rX의 명령을 위치 $\rm rW-4$에 있는 것처럼 되풀이한다
	resumeCont  = 1 // 같지만, 피연산자 대신 rY와 rZ를 쓴다
	resumeSet   = 2 // 레지스터 \$X를 rZ로 정한다
	resumeTrans = 3 // $\rm(rY,rZ)$를 IT-캐시나 DT-캐시에 넣고 |resumeAgain|을 한다
)

@ @<함수들@>=
func packBytes(a, b, c, d int) Tetra {
	return Tetra(a)<<24 + Tetra(b)<<16 + Tetra(c)<<8 + Tetra(d)
}

@ @<재개 레지스터 $\rm(rW,rX)$나...@>=
{
	hot := mx.hot
	j = int(packBytes(hot.op, int(hot.xx), int(hot.yy), int(hot.zz)))
	if hot.interrupt&hBit != 0 { // 트립
		mx.g[rW].o = hot.loc + 4
		mx.g[rX].o = sign32<<32 | Octa(Tetra(j))
		if mx.verbose&issueBit != 0 {
			mx.printf(" setting rW=")
			mx.printOcta(mx.g[rW].o)
			mx.printf(", rX=")
			mx.printOcta(mx.g[rX].o)
			mx.printf("\n")
		}
	} else { // 트랩
		mx.g[rWW].o = hot.goLoc.o
		mx.g[rXX].o = mx.g[rXX].o&^0xffffffff | Octa(Tetra(j))
		@<트랩의 ropcode |j|를 정한다@>
		mx.g[rXX].o = mx.g[rXX].o&0xffffffff | Octa(Tetra(j<<24)+hot.interrupt&0xff)<<32
		if mx.verbose&issueBit != 0 {
			mx.printf(" setting rWW=")
			mx.printOcta(mx.g[rWW].o)
			mx.printf(", rXX=")
			mx.printOcta(mx.g[rXX].o)
			mx.printf("\n")
		}
	}
}

@ @<트랩의 ropcode...@>=
if hot.interrupt&fBit != 0 { // 강제
	if hot.i != trap {
		j = resumeTrans // 페이지 변환을 에뮬레이트한다
	} else if hot.op == TRAP {
		j = 0x80 // |TRAP|
	} else if flags[hot.op]&xIsDestBit != 0 {
		j = resumeSet // 에뮬레이션
	} else {
		j = 0x80 // r[X]가 목적지가 아닐 때의 에뮬레이션
	}
} else { // 동적
	if hot.interim {
		if hot.i == frem || hot.i == syncd || hot.i == syncid {
			j = resumeCont
		} else {
			j = resumeAgain
		}
	} else if isLoadStore(hot.i) {
		j = resumeAgain
	} else {
		j = 0x80 // 보통의 바깥 인터럽트
	}
}

@ @<재개 레지스터 $\rm(rY,rZ)$나...@>=
{
	hot := mx.hot
	j = int(hot.interrupt & hBit)
	yReg, zReg := rYY, rZZ
	if j != 0 {
		yReg, zReg = rY, rZ
	}
	if hot.interrupt&fBit != 0 && hot.op == SWYM {
		mx.g[rYY].o = hot.goLoc.o
	} else {
		mx.g[yReg].o = hot.y.o
	}
	if hot.i == st || hot.i == pst {
		mx.g[zReg].o = hot.x.o
	} else {
		mx.g[zReg].o = hot.z.o
	}
	if mx.verbose&issueBit != 0 {
		if j != 0 {
			mx.printf(" setting rY=")
			mx.printOcta(mx.g[rY].o)
			mx.printf(", rZ=")
			mx.printOcta(mx.g[rZ].o)
			mx.printf("\n")
		} else {
			mx.printf(" setting rYY=")
			mx.printOcta(mx.g[rYY].o)
			mx.printf(", rZZ=")
			mx.printOcta(mx.g[rZZ].o)
			mx.printf("\n")
		}
	}
}

@ 휴, 계산을 성공적으로 가로막았다. 남은 일은 되도록 티 나지 않게 계산을 다시 시작하는 것이다.

\.{RESUME} 명령은 파이프라인이 빌 때까지 기다린다. 그만큼 과격한 일을 해야 하기 때문이다.
이를테면 바로 이 순간에 인터럽트가 일어나서 재개에 필요한 레지스터들을 바꾸고 있을 수도 있다.

@<명령 배정의 특별한 경우들@>=
case resume:
	if cool != mx.oldHot {
		break stall
	}
	if cool.zz != 0 {
		mx.instPtr = mx.specval(&mx.g[rWW])
	} else {
		mx.instPtr = mx.specval(&mx.g[rW])
	}
	if cool.loc&signBit == 0 {
		if cool.zz != 0 {
			cool.interrupt |= kBit
		} else if mx.instPtr.o&signBit != 0 {
			cool.interrupt |= pBit
		}
	}
	if cool.interrupt != 0 {
		mx.instPtr.o = cool.loc + 4
		cool.i = noop
	} else {
		cool.goLoc.o = mx.instPtr.o
		if cool.zz != 0 {
			@<|cool.loc|이 rT이면 마법처럼 입출력 연산을 한다@>
			cool.renA = true
			mx.specInstall(&mx.g[rK], &cool.a)
			cool.a.known, cool.a.o = true, mx.g[255].o
			cool.renX = true
			mx.specInstall(&mx.g[255], &cool.x)
			cool.x.known, cool.x.o = true, mx.g[rBB].o
		}
		if cool.zz != 0 {
			cool.b = mx.specval(&mx.g[rXX])
		} else {
			cool.b = mx.specval(&mx.g[rX])
		}
		if cool.b.o&signBit == 0 {
			@<중단된 연산을 다시 시작한다@>
		}
	}

@ 여기서 |cool.i=resum|으로 정한다. \.{RESUME} 자신 뒤에 명령을 하나 더 발행하고 싶기 때문이다.

끼워 넣는 명령에 대한 제약은 그 명령들이 곧바로 다음에 발행되도록 보장하려는 것이다. (이를테면
|incgamma| 명령이 필요하다면, 그것이 페이지 실패를 일으켜서 |resumeSet|이나 |resumeCont|의 피연산자
값을 잃어버릴 수도 있다.)

여기서 미묘한 점이 하나 생긴다. 재개 코드 |resumeTrans|로 가상 주소 0의 페이지 변환을 계산하고 있다면,
가상 주소 $-4$에서 가짜 \.{SWYM} 명령을 실행하고 싶지 않다! 그래서 \.{SWYM}을 아예 피한다.

보충: 원본의 |switch|는 |case| 사이를 흘러내리고, 이름표 |resume_again|과 |bad_resume|으로 뛰었다.
여기서는 불 변수 |again|과 |bad|를 켜고 |switch| 뒤에서 그 일을 한다. 원본에서 |m|은
|MMIX_run|의 지역 변수였는데, 여기서는 |cycle|의 지역 변수다.

@<중단된 연산을 다시 시작한다@>=
cool.xx = byte(cool.b.o >> 56)
cool.i = resum
mx.head.loc = mx.instPtr.o - 4
{
	again, bad := false, false
	switch cool.xx {
	case resumeSet:
		cool.b.o = cool.b.o&^0xffffffff | Octa(Tetra(SETH)<<24+Tetra(cool.b.o)&0xff0000)
		mx.head.interrupt |= Tetra(cool.b.o>>32) & 0xff00
		mx.resuming = 2
		fallthrough
	case resumeCont:
		mx.resuming += 1 + int(cool.zz)
		if (Tetra(cool.b.o)>>24)&0xfa != 0xb8 { // |syncd|나 |syncid|가 아니다
			@<rX의 명령이 |resumeCont|로 되풀이할 수 있는 것인지 검사하고, 아니면 |break|한다@>
		}
		again = true
	case resumeAgain:
		again = true
	case resumeTrans:
		@<|resumeTrans|의 피연산자를 넣는다. |SWYM|이 아니면 |again|을 켠다@>
	default:
		bad = true
	}
	@<되풀이할 명령을 넣거나, 잘못된 재개를 표시한다@>
}

@ @<되풀이할 명령을 넣거나...@>=
if again {
	@<rX에 든 명령을 가져오기 버퍼의 머리에 넣는다@>
}
if bad {
	cool.interrupt |= bBit
	cool.i = noop
	mx.resuming = 0
}

@ 보충: 재개 코드 |resumeTrans|는 트랩 처리기에서 돌아올 때(\.{RESUME}~\.1)만 뜻이 있다. 트립 처리기에서
돌아올 때(\.{RESUME}~\.0)는 잘못된 재개다.

@<|resumeTrans|의 피연산자를...@>=
if cool.zz != 0 {
	cool.y, cool.z = mx.specval(&mx.g[rYY]), mx.specval(&mx.g[rZZ])
	if Tetra(cool.b.o)>>24 != SWYM {
		again = true
		break
	}
	cool.i = resume // 위의 ``미묘한 점''을 보라
	break
}
bad = true

@ @<rX의 명령이 |resumeCont|로...@>=
m = int(Tetra(cool.b.o) >> 28)
if (1<<m)&0x8f30 != 0 {
	bad = true
	break
}
m = int(Tetra(cool.b.o)>>16) & 0xff
if m >= mx.coolL && m < mx.coolG {
	bad = true
	break
}

@ @<rX에 든 명령을...@>=
mx.head.inst = Tetra(cool.b.o)
m = int(mx.head.inst >> 24)
if m == RESUME {
	bad = true // 가로막을 수 없는 루프를 피한다
} else {
	if cool.zz == 0 && m > RESUME && m <= SYNC && mx.head.inst&badInstMask[m-RESUME] != 0 {
		mx.head.interrupt |= bBit
	}
	mx.head.noted = false
}

@ @<중단된 연산을 다시 시작할 때의...@>=
if mx.resuming&1 != 0 {
	cool.y = mx.specval(&mx.g[rY])
	cool.z = mx.specval(&mx.g[rZ])
} else {
	cool.y = mx.specval(&mx.g[rYY])
	cool.z = mx.specval(&mx.g[rZZ])
}
if mx.resuming >= 3 { // |resumeSet|
	cool.needRA, cool.ra = true, mx.specval(&mx.g[rA])
}
cool.usage = false

@ 보충: 원본의 이름표 |resume_trans|는 |case do_resume_trans| 바로 뒤에 있으므로 그 |case|와 같다.

@<상수@>=
const (
	doResumeTrans = 17                      // |resumeTrans| 동작을 하는 |state|
	lResumeTrans  = stage1St + doResumeTrans // 원본의 |resume_trans|
)

@ @<1단계 실행의 경우들@>=
case resume, resum:
	if data.xx != resumeTrans {
		pc = lFinEx
		continue
	}
	if Tetra(data.b.o)>>24 == SWYM {
		data.ptrA = mx.ITcache
	} else {
		data.ptrA = mx.DTcache
	}
	data.state = doResumeTrans
	data.z.o = data.z.o&^mx.pageMask + data.z.o&7
	data.z.o &= 0xffff<<32 | 0xffffffff
	pc = lResumeTrans
	continue

@ @<첫 단계의 특별한 상태들@>=
case lResumeTrans:
	c = data.ptrA.(*cache)
	if c.lock != nil {
		return mx.wait(self, 1)
	}
	if c.filler.next != nil {
		return mx.wait(self, 1)
	}
	p = mx.allocSlot(c, mx.transKey(data.y.o))
	if p != nil {
		c.fillerCtl.ptrB = p
		c.fillerCtl.y.o = data.y.o
		c.fillerCtl.b.o = data.z.o
		c.fillerCtl.state = 1
		mx.schedule(&c.filler, c.accessTime, 1)
	}
	pc = lFinEx
	continue

@* 관리 연산. 레지스터 스택을 다루는 내부 명령들은 이미 할 줄 아는 일들로 그냥 바뀐다. (뭐,
저장하고 되살리는 내부 명령들은 |data.op|에 따라 이따금 특별한 경우로 가기도 한다. 그러나 대부분
필요한 장치는 이미 갖추어져 있다.)

@<1단계 실행의 경우들@>=
case noop:
	if data.interrupt&fBit != 0 {
		pc = lEmulateVirt
		continue
	}
	fallthrough
case incrl, unsave:
	pc = lFinEx
	continue
case jmp, pushj:
	data.goLoc.o = data.z.o
	pc = lFinEx
	continue
case sav:
	if !data.memX {
		pc = lFinEx
		continue
	}
	fallthrough
case incgamma, save:
	data.i = st
	pc = lSwitch1
	continue
case decgamma, unsav:
	data.i = ld
	pc = lSwitch1
	continue

@ 특수 레지스터 가운데 21 이상인 것(곧 rA, rF, rP, rW--rZ, rWW--rZZ)은 뜨거운 자리에서만
\.{GET}할 수 있다. 그 레지스터들은 많은 명령의 드러나지 않은 출력이기 때문이다.

rK도 마찬가지다. \.{TRAP}과 에뮬레이트하는 명령들이 rK를 바꾸기 때문이다.

rQ도 너무 일찍 얻으면 안 된다.

@<1단계 실행의 경우들@>=
case get:
	if data.zz >= 21 || data.zz == rK || data.zz == rQ {
		if data != mx.oldHot {
			return mx.wait(self, 1)
		}
		data.z.o = mx.g[data.zz].o
	}
	data.x.o = data.z.o
	pc = lFinEx
	continue

@ \.{PUT}도 마찬가지로 |dispatchLock|을 쥐는 경우에는 미룬다. 이 프로그램은 rQ에 \.{PUT}할 수
있는 1~비트를 제한하지 않는다. 그 레지스터의 내용이 과격한 결과를 낳을 수 있는데도 말이다.

@<1단계 실행의 경우들@>=
case put:
	if data.xx == 8 || (data.xx >= 15 && data.xx <= 20) {
		if data != mx.oldHot {
			return mx.wait(self, 1)
		}
		switch data.xx {
		case rV:
			@<|page| 변수들을 고친다@>
		case rQ:
			mx.newQ |= data.z.o &^ mx.g[rQ].o
			data.z.o |= mx.newQ
		case rL:
			if data.z.o>>32 != 0 {
				data.z.o = Octa(Tetra(mx.g[rL].o))
			} else if Tetra(data.z.o) > Tetra(mx.g[rL].o) {
				data.z.o = Octa(Tetra(mx.g[rL].o))
			}
		case rG:
			@<rG를 고친다@>
		}
	} else if data.xx == rA && (data.z.o>>32 != 0 || Tetra(data.z.o) >= 0x40000) {
		data.interrupt |= bBit
		data.z.o &= 0x3ffff
	}
	data.x.o = data.z.o
	pc = lFinEx
	continue

@ rG가 줄어들 때는 클럭 사이클마다 가장자리 레지스터를 |commitMax|개까지 0으로 만들 수 있다고
가정한다. (지금 우리는 뜨거운 자리에 있고 |dispatchLock|을 쥐고 있다는 것을 기억하라.)

보충: 여기서 rG의 윗 테트라는 늘 0이고 아랫 테트라는 32 이상이다.

@<rG를 고친다@>=
if data.z.o>>32 != 0 || Tetra(data.z.o) >= 256 ||
	Tetra(data.z.o) < Tetra(mx.g[rL].o) || Tetra(data.z.o) < 32 {
	data.interrupt |= bBit
	data.z.o = mx.g[rG].o
} else if Tetra(data.z.o) < Tetra(mx.g[rG].o) {
	data.interim = true // 가로막힐 수 있다
	for j = 0; j < mx.commitMax; j++ {
		mx.g[rG].o--
		mx.g[Tetra(mx.g[rG].o)].o = 0
		if Tetra(data.z.o) == Tetra(mx.g[rG].o) {
			break
		}
	}
	if j == mx.commitMax {
		if !mx.tryingToInterrupt {
			return mx.wait(self, 1)
		}
	} else {
		data.interim = false
	}
}

@ 계산하는 점프는 가고 싶은 목적지 주소를 |goLoc| 필드에 넣는다.

보충: 원본은 |go|의 경우에서 |pushgo|의 경우 안에 있는 이름표 |add_go|로 뛰었다. 여기서는 그
뒷부분을 절로 만들어 두 곳에서 쓴다.

@<1단계 실행의 경우들@>=
case goOp:
	data.x.o = data.goLoc.o
	@<점프할 주소를 계산한다@>
case pop:
	data.x.o = data.y.o
	data.y.o = data.b.o // rJ를 |y| 필드로 옮긴다
	fallthrough
case pushgo:
	@<점프할 주소를 계산한다@>

@ @<점프할 주소를...@>=
data.goLoc.o = data.y.o + data.z.o
if data.goLoc.o&signBit != 0 && data.loc&signBit == 0 {
	data.interrupt |= pBit
}
data.goLoc.known = true
pc = lFinEx
continue

@ 명령 \.{UNSAVE}~$z$는 실제로 되살리는 일을 하는 내부 명령들의 열을 만들어 낸다. 이 열은 지금
가져오기 버퍼에 있는 명령이 제어하는데, 그 명령은 전역 레지스터를 모두 적재할 때까지 X와~Y
필드를 바꾼다. 이 열의 첫 명령들은 \.{UNSAVE}~$0,0,z$; \.{UNSAVE}~$1,rZ,z-8$;
\.{UNSAVE}~$1,rY,z-16$; \dots; \.{UNSAVE}~$1,rB,z-96$; \.{UNSAVE}~$2,255,z-104$;
\.{UNSAVE}~$2,254,z-112$ 등이다. 이 명령들이 모두 확정되기 전에 인터럽트가 일어나면, 실행
레지스터에 그 과정을 다시 시작할 만큼의 정보가 들어간다.

전역 레지스터를 모두 적재한 뒤에 \.{UNSAVE}는 \.{POP}과 꽤 비슷하게 행동하며 이어 간다. 이 마지막
단계에서 일어나는 인터럽트는 $\rm rS<rO$를 보게 된다. 그러면 문맥 전환으로 지역 레지스터들을 다시
되살리는 일로 돌아올 수도 있다. 그러나 되살리기를 시작한 레지스터가 오래전에 바뀌었더라도 정보를
잃지는 않는다.

보충: 원본은 |xx=3|인 경우에서 \.{POP}의 경우 안에 있는 이름표 |pop_unsave|로 뛰었다. 그 부분은
절 ``레지스터 스택을 꺼내거나 되살린다''다.

@<명령 배정의 특별한 경우들@>=
case unsave:
	if cool.interrupt&bBit != 0 {
		cool.i = noop
	} else {
		cool.interim = true
		op = LDOU // 이 명령은 적재/저장 장치가 다루어야 한다
		cool.i = unsav
		switch cool.xx {
		case 0:
			if cool.z.p != nil {
				break stall
			}
			@<되살리기의 첫 국면을 준비한다@>
		case 1, 2:
			@<|g[yy]|를 되살리는 명령을 만든다@>
		case 3:
			cool.i, cool.interim, op = unsave, false, UNSAVE
			@<레지스터 스택을 꺼내거나...@>
		default:
			cool.interim, cool.i = false, noop
			cool.interrupt |= bBit
		}
	} // 이것이 우리를 |dispatchDone|으로 데려간다

@ @<|g[yy]|를 되살리는...@>=
cool.renX = true
mx.specInstall(&mx.g[cool.yy], &cool.x)
mx.newO = mx.coolO - 1
mx.newS = mx.newO
cool.z.o = mx.newO << 3
cool.ptrA = mx.mem.up

@ @<되살리기의 첫 국면을...@>=
cool.renX = true
mx.specInstall(&mx.g[rG], &cool.x)
cool.renA = true
mx.specInstall(&mx.g[rA], &cool.a)
mx.newO = cool.z.o >> 3
mx.newS = mx.newO
cool.setL = true
mx.specInstall(&mx.g[rL], &cool.rl)
cool.ptrA = mx.mem.up

@ @<\.{UNSAVE}의 다음 단계를...@>=
switch cool.xx {
case 0:
	mx.head.inst = packBytes(UNSAVE, 1, rZ, 0)
case 1:
	if cool.yy == rP {
		mx.head.inst = packBytes(UNSAVE, 1, rR, 0)
	} else if cool.yy == 0 {
		mx.head.inst = packBytes(UNSAVE, 2, 255, 0)
	} else {
		mx.head.inst = packBytes(UNSAVE, 1, int(cool.yy)-1, 0)
	}
case 2:
	if int(cool.yy) == mx.coolG {
		mx.head.inst = packBytes(UNSAVE, 3, 0, 0)
	} else {
		mx.head.inst = packBytes(UNSAVE, 2, int(cool.yy)-1, 0)
	}
}

@ @<적재할 때가 된 내부 \.{UNSAVE}를...@>=
if data.xx == 0 {
	data.a.o = data.x.o & (0xffffff<<32 | 0xffffffff) // 되살린 rA
	data.x.o >>= 56 // 되살린 rG
	if data.a.o>>32 != 0 || Tetra(data.a.o)&0xfffc0000 != 0 {
		data.a.o &= 0x3ffff
		data.interrupt |= bBit
	}
	if Tetra(data.x.o) < 32 {
		data.x.o = 32
		data.interrupt |= bBit
	}
}

@ 물론 \.{SAVE}는 \.{UNSAVE}와 본질적으로 같게, 그러나 거꾸로 다룬다.

@<명령 배정의 특별한 경우들@>=
case save:
	if int(cool.xx) < mx.coolG {
		cool.interrupt |= bBit
	}
	if cool.interrupt&bBit != 0 {
		cool.i = noop
	} else if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {
		@<$\gamma$를 나아가게 하는...@>
	} else {
		cool.interim = true
		cool.i = sav
		switch cool.zz {
		case 0:
			@<저장하기의 첫 국면을 준비한다@>
		case 1:
			if Tetra(mx.coolO) != Tetra(mx.coolS) {
				@<$\gamma$를 나아가게 하는...@>
			}
			cool.zz = 2
			cool.yy = byte(mx.coolG)
			fallthrough
		case 2, 3:
			@<|g[yy]|를 저장하는 명령을 만든다@>
		default:
			cool.interim, cool.i = false, noop
			cool.interrupt |= bBit
		}
	}

@ 첫 국면 동안, 이를테면 두 |incgamma| 명령 사이에서 인터럽트가 일어나면, 값 |cool.zz=1|이 일을
제대로 다시 시작하게 해 준다. (실은 인터럽트 동안 문맥을 저장하고 되살리면, 많은 |incgamma| 명령이
더는 필요 없어질 수도 있다.)

@<저장하기의 첫 국면을...@>=
cool.zz = 1
cool.renX = true
mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(mx.coolL)), &cool.x)
cool.x.known, cool.x.o = true, Octa(Tetra(mx.coolL))
cool.setL = true
mx.specInstall(&mx.g[rL], &cool.rl)
mx.newO = mx.coolO + Octa(mx.coolL+1)

@ @<|g[yy]|를 저장하는...@>=
op = STOU // 이 명령은 적재/저장 장치가 다루어야 한다
cool.memX = true
mx.specInstall(&mx.mem, &cool.x)
cool.z.o = mx.coolO << 3
mx.newO = mx.coolO + 1
mx.newS = mx.newO
if cool.zz == 3 && cool.yy > rZ {
	@<마지막 \.{SAVE}를 한다@>
} else {
	cool.b = mx.specval(&mx.g[cool.yy])
}

@ 마지막 \.{SAVE} 명령은 rG와 rA를 저장할 뿐 아니라, 마지막 주소를 전역 레지스터~X에 넣는다.

@<마지막 \.{SAVE}를...@>=
cool.i = save
cool.interim = false
cool.renA = true
mx.specInstall(&mx.g[cool.xx], &cool.a)

@ @<\.{SAVE}의 다음 단계를...@>=
switch cool.zz {
case 1:
	mx.head.inst = packBytes(SAVE, int(cool.xx), 0, 1)
case 2:
	if cool.yy == 255 {
		mx.head.inst = packBytes(SAVE, int(cool.xx), 0, 3)
	} else {
		mx.head.inst = packBytes(SAVE, int(cool.xx), int(cool.yy)+1, 2)
	}
case 3:
	if cool.yy == rR {
		mx.head.inst = packBytes(SAVE, int(cool.xx), rP, 3)
	} else {
		mx.head.inst = packBytes(SAVE, int(cool.xx), int(cool.yy)+1, 3)
	}
}

@ @<저장할 때가 된 내부 \.{SAVE}를...@>=
if data.interim {
	data.x.o = data.b.o
} else {
	if data != mx.oldHot {
		return mx.wait(self, 1) // rA의 가장 뜨거운 값이 필요하다
	}
	data.x.o = Octa(Tetra(mx.g[rG].o)<<24)<<32 | Octa(Tetra(mx.g[rA].o))
	data.a.o = data.y.o
}

@* 레지스터 대 레지스터 연산 더 보기. 어려운 것은 거의 끝냈으니, 이제 긴장을 풀고 실행 단계의
레지스터만 쓰는 부분에 남겨 둔 구멍들을 메울 수 있다.

먼저 곱셈과 나눗셈을 처리해서 고정소수점 산술 연산을 마무리하자.

보충: 원본은 |mulu|의 경우에서 |mul|의 경우 안에 있는 이름표 |quantify_mul|로 뛰었다. 여기서는
그 뒷부분을 절로 만들어 두 곳에서 쓴다. 원본의 |omult|는 |bits.Mul64|다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case mulu:
	data.a.o, data.x.o = bits.Mul64(data.y.o, data.z.o)
	@<곱셈의 파이프라인 시간을 정한다@>
case mul:
	{
		x, overflow := mmixarith.SignedMult(data.y.o, data.z.o)
		data.x.o = x
		if overflow {
			data.interrupt |= vBit
		}
	}
	@<곱셈의 파이프라인 시간을...@>
case divu:
	data.x.o, data.a.o = mmixarith.Div(data.b.o, data.y.o, data.z.o)
	data.i = div
case div:
	if data.z.o == 0 {
		data.interrupt |= dBit
		data.a.o = data.y.o
		data.i = set // 0으로 나누기는 파이프라인에서 기다릴 필요가 없다
	} else {
		q, r, overflow := mmixarith.SignedDiv(data.y.o, data.z.o)
		data.x.o = q
		if overflow {
			data.interrupt |= vBit
		}
		data.a.o = r
	}

@ @<곱셈의 파이프라인 시간을...@>=
{
	aux := data.z.o
	for j = mul0; aux != 0; j++ {
		aux >>= 8
	}
	data.i = j // |j|는 |mul0|이나 |mul1|이나 \dots~|mul8|이다
}

@ 다음으로 비트 단위와 바이트 단위 연산들을 마무리하자.

보충: 원본의 |odif|는 윗 테트라들이 같으면 |tdif|의 경우 안에 있는 이름표 |tdif_l|로 뛰었다.
필드 |data.x.o|는 처음에 0이므로, 그것은 |y>z|일 때만 |x=y-z|로 하는 것과 같다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case sadd:
	data.x.o = Octa(bits.OnesCount64(data.y.o &^ data.z.o))
case mor:
	data.x.o = mmixarith.BoolMult(data.y.o, data.z.o, data.op&0x2 != 0)
case bdif:
	data.x.o = mmixarith.ByteDiff(data.y.o, data.z.o)
case wdif:
	data.x.o = mmixarith.WydeDiff(data.y.o, data.z.o)
case tdif:
	if data.y.o>>32 > data.z.o>>32 {
		data.x.o = (data.y.o>>32 - data.z.o>>32) << 32
	}
	if Tetra(data.y.o) > Tetra(data.z.o) {
		data.x.o |= Octa(Tetra(data.y.o) - Tetra(data.z.o))
	}
case odif:
	if data.y.o > data.z.o {
		data.x.o = data.y.o - data.z.o
	}

@ 조건부 설정(\.{CS}) 명령은 뜻밖에도, 하는 일이 더 많은 0 설정(\.{ZS}) 명령보다 구현하기
어렵다. \.{CS}에서는 동적인 명령 의존 관계가 더 복잡하기 때문이다. 이를테면 다음 명령들을
생각해 보자.
$$\advance\abovedisplayskip-.5\baselineskip
  \advance\belowdisplayskip-.5\baselineskip
\hbox{\tt LDO x,a,b; \ FDIV y,c,d; \ CSZ y,x,0; \ INCL y,1.}$$
\.x의 값이 0이면 \.{INCL} 명령은 나눗셈이 끝나기를 기다릴 필요가 없다. (그러나 그런 경우에도
나눗셈을 중단하지는 않는다. 나눗셈이 트립 처리기를 부르거나 부정확 비트를 바꿀 수도 있기
때문이다. 우리의 방침은 흔한 경우를 효율적으로 다루고 모든 경우를 올바르게 다루되, 모든 경우를
최대한 효율적으로 다루지는 않는 것이다.)

@<레지스터 대 레지스터 연산의 결과를...@>=
case zset:
	if registerTruth(data.y.o, data.op) != 0 {
		data.x.o = data.z.o
	} // 그렇지 않으면 |data.x.o|는 이미 0이다
	pc = lFinEx
	continue
case cset:
	if registerTruth(data.y.o, data.op) != 0 {
		data.x.o, data.b.p = data.z.o, nil
	} else if data.b.p == nil {
		data.x.o = data.b.o
	} else {
		data.state = 0
		data.needB = true
		pc = lSwitch1
		continue
	}

@ 부동소수점 계산은 대부분 {\mc MMIX-ARITH}의 루틴들이 맡는데, 그 루틴들은 비정상적인 사건을
전역 변수 |exceptions|에 기록한다. 그러나 입력이 무한대나 NaN이면 연산을 하찮은 것으로 여긴다. 그리고
비정규수가 있으면 실행 시간을 늘려야 할 수도 있다.

보충: 옮긴 \.{mmixarith}의 루틴들은 예외 비트를 반환값으로 돌려준다. 여기서는 그 값을 필드
|exceptions|에 넣는다. 원본의 |exceptions|는 루틴이 인자를 풀 때마다 지워지므로, 호출 직후의 값은
그 호출이 켠 비트들이다. 원본의 매크로 |set_round|는 메서드 |setRound|이고, 반올림 방식 인자가 0이면
현재 방식을 쓰는 원본 루틴들의 관례는 메서드 |roundMode|가 흉내 낸다.

@<함수들@>=
func isSubnormal(x Octa) bool {
	return (x>>32)&0x7ff00000 == 0 && x&(0xfffff<<32|0xffffffff) != 0
}
@#
func isTrivial(x Octa) bool {
	return (x>>32)&0x7ff00000 == 0x7ff00000
}
@#
func (mx *machine) setRound(data *control) {
	if Tetra(data.ra.o) < 0x10000 {
		mx.curRound = mmixarith.RoundNear
	} else {
		mx.curRound = mmixarith.Round(Tetra(data.ra.o) >> 16)
	}
}
@#
func (mx *machine) roundMode(y Octa) mmixarith.Round {
	if Tetra(y) == 0 {
		return mx.curRound
	}
	return mmixarith.Round(Tetra(y))
}

@ 보충: 원본은 연산마다 결과를 계산한 뒤 이름표 |fin_bflot|, |fin_uflot|, |fin_flot| 가운데
하나로 뛰었다. 세 이름표는 차례로 흘러내리므로, 앞의 것으로 뛸수록 검사를 많이 한다. 여기서는
어느 이름표로 뛰는지를 변수 |entry|(0, 1, 2)에 기록하고 공통 꼬리에서 그만큼 검사를 건너뛴다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case fadd, fsub, fmul, fdiv, fsqrt, fint, fix:
	entry := 0 // |fin_bflot|이면 0, |fin_uflot|이면 1, |fin_flot|이면 2
	mx.setRound(data)
	switch data.i {
	@<부동소수점 연산의 결과를 계산하는 경우들@>
	}
	if entry <= 0 && isSubnormal(data.y.o) {
		data.denin = mx.deninPenalty
	}
	if entry <= 1 && isSubnormal(data.x.o) {
		data.denout = mx.denoutPenalty
	}
	if isSubnormal(data.z.o) {
		data.denin = mx.deninPenalty
	}
	data.interrupt |= Tetra(mx.exceptions)
	if isTrivial(data.y.o) || isTrivial(data.z.o) {
		pc = lFinEx
		continue
	}
	if data.i == fsqrt && data.z.o&signBit != 0 {
		pc = lFinEx
		continue
	}
case flot:
	mx.setRound(data)
	data.x.o, mx.exceptions = mmixarith.FloatIt(data.z.o, mx.roundMode(data.y.o),
		data.op&0x2 != 0, data.op&0x4 != 0)
	data.interrupt |= Tetra(mx.exceptions)

@ @<부동소수점 연산의 결과를 계산하는 경우들@>=
case fadd:
	data.x.o, mx.exceptions = mmixarith.FPlus(data.y.o, data.z.o, mx.curRound)
case fsub:
	data.a.o = data.z.o
	if mmixarith.FComp(data.z.o, 0) != 2 {
		data.a.o ^= signBit
	}
	data.x.o, mx.exceptions = mmixarith.FPlus(data.y.o, data.a.o, mx.curRound)
	data.i = fadd // 덧셈의 파이프라인 시간을 쓴다
case fmul:
	data.x.o, mx.exceptions = mmixarith.FMult(data.y.o, data.z.o, mx.curRound)
case fdiv:
	data.x.o, mx.exceptions = mmixarith.FDivide(data.y.o, data.z.o, mx.curRound)
case fsqrt:
	data.x.o, mx.exceptions = mmixarith.FRoot(data.z.o, mx.roundMode(data.y.o))
	entry = 1
case fint:
	data.x.o, mx.exceptions = mmixarith.FIntegerize(data.z.o, mx.roundMode(data.y.o))
	entry = 1
case fix:
	data.x.o, mx.exceptions = mmixarith.FixIt(data.z.o, mx.roundMode(data.y.o))
	if data.op&0x2 != 0 {
		mx.exceptions &^= wBit // 부호 없는 경우는 넘치지 않는다
	}
	entry = 2

@ @<명령 배정의 특별한 경우들@>=
case fsqrt, fint, fix, flot:
	if Tetra(cool.y.o) > 4 {
		@<|cool|을 불법 명령으로...@>
	}

@ 보충: 원본은 비교 결과에 따라 이름표 |cmp_neg|, |cmp_pos|, |cmp_zero|, |cmp_fin|,
|cmp_zero_or_invalid|로 뛰었다. 필드 |data.x.o|는 처음에 0이므로 이름표 |cmp_zero|는 아무 일도 하지 않는다.
이름표 |cmp_fin|에서 시작하는 꼬리는 절로 만들어 여러 곳에서 쓴다. \.{FCMPE}의 엡실론 비교가 0을 돌려주면
원본은 |fcmp|의 경우로 흘러내렸다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case feps:
	j = mmixarith.FEpsComp(data.y.o, data.z.o, data.b.o, data.op != FEQLE)
	if j == 2 {
		data.i = fcmp
	} else if isSubnormal(data.y.o) || isSubnormal(data.z.o) {
		data.denin = mx.deninPenalty
	}
	switch {
	case data.op == FUNE:
		if j == 2 {
			data.x.o = 1
		}
	case data.op == FEQLE:
		@<부동소수점 비교의 결과 |j|를 마무리한다@>
	case data.op == FCMPE && j != 0:
		if j == 2 {
			data.interrupt |= iBit
		}
	default:
		@<부동소수점 수를 비교한다@>
	}
case fcmp:
	@<부동소수점 수를 비교한다@>
case funeq:
	want := 0
	if data.op == FUN {
		want = 2
	}
	if mmixarith.FComp(data.y.o, data.z.o) == want {
		data.x.o = 1
	}

@ @<부동소수점 수를 비교한다@>=
j = mmixarith.FComp(data.y.o, data.z.o)
if j < 0 {
	data.x.o = negOne
} else {
	@<부동소수점 비교의 결과...@>
}

@ @<부동소수점 비교의 결과...@>=
if j == 1 {
	data.x.o = 1
} else if j == 2 {
	data.interrupt |= iBit
}

@ @<기계의 상태@>=
fremMax                     int
deninPenalty, denoutPenalty int

@ 부동소수점 나머지 연산은 뜨거운 자리에 있을 때 가로막힐 수 있어서 특히 흥미롭다.

@<레지스터 대 레지스터 연산의 결과를...@>=
case frem:
	if isTrivial(data.y.o) || isTrivial(data.z.o) {
		data.x.o, mx.exceptions = mmixarith.FRemStep(data.y.o, data.z.o, 2500)
		data.interrupt |= Tetra(mx.exceptions)
		pc = lFinEx
		continue
	}
	if self.succ.next != nil {
		return mx.wait(self, 1)
	}
	data.interim = true
	j = 1
	if isSubnormal(data.y.o) || isSubnormal(data.z.o) {
		j += mx.deninPenalty
	}
	mx.passAfter(self, j)
	pc = lPassit
	continue

@ @<2단계 연산의 실행을 시작한다@>=
j = 1
if data.i == frem {
	data.x.o, mx.exceptions = mmixarith.FRemStep(data.y.o, data.z.o, mx.fremMax)
	if mx.exceptions&eBit != 0 {
		data.y.o = data.x.o
		if mx.tryingToInterrupt && data == mx.oldHot {
			pc = lFinEx
			continue
		}
	} else {
		data.state = 3
		data.interim = false
		data.interrupt |= Tetra(mx.exceptions)
		if isSubnormal(data.x.o) {
			j += mx.denoutPenalty
		}
	}
	return mx.wait(self, j)
}

@* 시스템 연산. 마지막으로 운영체제를 위한 연산 몇 가지를 구현해야 한다. 그러면 하드웨어
시뮬레이션이 끝난다!

\.{LDVTS} 명령은 IT-캐시와 DT-캐시를 바꾸므로 뜨거운 자리에 이를 때까지 미룬다. 효과가 곧바로
필요하면 운영체제는 \.{LDVTS} 뒤에 \.{SYNC}를 써야 한다. \.{LDVTS}의 허가 비트가 0이 아닐 때는
페이지 테이블의 허가 비트가 그것과 맞도록 하는 것도 운영체제의 몫이다. (또한 어떤 페이지에서 쓰기
허가를 거두려면, 그 페이지에서 캐시에 들어왔을지 모르는 더러운 바이트들을 운영체제가 미리
\.{SYNCD}로 써 내보냈어야 한다. 쓰기 허가가 사라진 뒤에는 \.{SYNCD}가 아무 일도 하지 않는다.)

@<|prego|나 |ldvts| 같은...@>=
if data.i == ldvts {
	@<\.{LDVTS}의 1단계를 한다@>
}

@ @<\.{LDVTS}의 1단계를...@>=
if data != mx.oldHot {
	return mx.wait(self, 1)
}
if mx.DTcache.lock != nil {
	return mx.wait(self, 1)
}
if j = getReader(mx.DTcache); j < 0 {
	return mx.wait(self, 1)
}
mx.startup(&mx.DTcache.reader[j], mx.DTcache.accessTime)
data.z.o = data.y.o & 0x7
p = mx.cacheSearch(mx.DTcache, data.y.o) // 주의: |transKey(data.y.o)|가 아니다
if p != nil {
	data.x.o = data.x.o&^0xffffffff | 2
	c = mx.DTcache
	@<변환 캐시 블록 |p|의 보호 비트를 바꾸거나 블록을 무효로 만든다@>
}
mx.passAfter(self, mx.DTcache.accessTime)
pc = lPassit
continue

@ 보충: 원본은 이 일을 DT-캐시와 IT-캐시에 대해 따로 적었다. 여기서는 부르는 쪽이 |c|를 그
캐시로 정해 둔다.

@<변환 캐시 블록 |p|의...@>=
if Tetra(data.z.o) != 0 {
	p = mx.useAndFix(c, p)
	p.data[0] = p.data[0]&^0xffffffff | Octa(Tetra(p.data[0])&^7+Tetra(data.z.o))
} else {
	p = mx.demoteAndFix(c, p)
	p.tag |= signBit // 태그를 무효로 만든다
}

@ @<뒤 단계들의 특별한 상태들@>=
case stage2St + ldStLaunch:
	if mx.ITcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.ITcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.ITcache.reader[j], mx.ITcache.accessTime)
	p = mx.cacheSearch(mx.ITcache, data.y.o) // 주의: |transKey(data.y.o)|가 아니다
	if p != nil {
		data.x.o |= 1
		c = mx.ITcache
		@<변환 캐시 블록 |p|의...@>
	}
	data.state = 3
	return mx.wait(self, mx.ITcache.accessTime)

@ \.{SYNC} 연산은 파이프라인과 흥미롭게 얽힌다. \.{SYNC}~\.0과 \.{SYNC}~\.4가 가장 단순하다.
배정을 잠그고 뜨거운 자리에 이를 때까지 기다리기만 하면, 그 뒤에는 파이프라인이 비어 있다.
\.{SYNC}~\.1과 \.{SYNC}~\.3은 쓰기 버퍼에 ``장벽''을 넣어서, 뒤따르는 저장 명령이 앞선 저장과
합쳐지지 않게 한다. \.{SYNC}~\.2와 \.{SYNC}~\.3은 앞선 적재 명령들이 모두 파이프라인을 떠날 때까지
배정을 잠근다. \.{SYNC}~\.5, \.{SYNC}~\.6, \.{SYNC}~\.7은 뜨거운 자리에 이르면 캐시에서 것들을
없앤다.

@<명령 배정의 특별한 경우들@>=
case sync:
	if cool.zz > 3 {
		if cool.loc&signBit == 0 {
			@<|cool|을 특권 명령으로...@>
		}
		if cool.zz == 4 {
			freezeDispatch = true
		}
	} else {
		if cool.zz != 1 {
			freezeDispatch = true
		}
		if cool.zz&1 != 0 {
			cool.memX = true
			mx.specInstall(&mx.mem, &cool.x)
		}
	}

@ 보충: 원본에서 이 |switch|를 빠져나가면 연산을 시작하는 |switch|도 빠져나간다. 여기서도 그렇다.

@<1단계 실행의 경우들@>=
case sync:
	switch data.zz {
	case 0, 4:
		if data != mx.oldHot {
			return mx.wait(self, 1)
		}
		mx.halted = data.zz != 0
		pc = lFinEx
		continue
	case 2, 3:
		@<앞에 끝나지 않은 적재가 있으면 기다린다@>
		releaseLock(self, &mx.dispatchLock)
		fallthrough
	case 1:
		data.x.addr = 0
		pc = lFinEx
		continue
	case 5:
		if data != mx.oldHot {
			return mx.wait(self, 1)
		}
		@<데이터 캐시들을 청소한다@>
	case 6:
		if data != mx.oldHot {
			return mx.wait(self, 1)
		}
		@<변환 캐시들을 지운다@>
	case 7:
		if data != mx.oldHot {
			return mx.wait(self, 1)
		}
		@<명령 캐시와 데이터 캐시를 지운다@>
	}

@ @<앞에 끝나지 않은 적재가...@>=
for k := data; k != mx.hot; {
	k = mx.nextCtl(k)
	if k.owner != nil && (k.i == ld || k.i == ldunc || k.i == pst) {
		return mx.wait(self, 1)
	}
}

@ 여기서는 지연이 더 길어야 할지도 모른다.

@<변환 캐시들을 지운다@>=
if mx.DTcache.lock != nil {
	return mx.wait(self, 1)
}
if j = getReader(mx.DTcache); j < 0 {
	return mx.wait(self, 1)
}
mx.startup(&mx.DTcache.reader[j], mx.DTcache.accessTime)
setLock(self, &mx.DTcache.lock)
zapCache(mx.DTcache)
data.state = 10
return mx.wait(self, mx.DTcache.accessTime)

@ @<명령 캐시와 데이터 캐시를...@>=
if mx.Icache == nil {
	data.state = 11
	pc = lSwitch1
	continue
}
if mx.Icache.lock != nil {
	return mx.wait(self, 1)
}
if j = getReader(mx.Icache); j < 0 {
	return mx.wait(self, 1)
}
mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)
setLock(self, &mx.Icache.lock)
zapCache(mx.Icache)
data.state = 11
return mx.wait(self, mx.Icache.accessTime)

@ @<첫 단계의 특별한 상태들@>=
case stage1St + 10:
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	if mx.ITcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.ITcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.ITcache.reader[j], mx.ITcache.accessTime)
	setLock(self, &mx.ITcache.lock)
	zapCache(mx.ITcache)
	data.state = 3
	return mx.wait(self, mx.ITcache.accessTime)
case stage1St + 11:
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	if mx.wbufLock != nil {
		return mx.wait(self, 1)
	}
	mx.writeHead, mx.writeCtl.state = mx.writeTail, 0 // 쓰기 버퍼를 지운다
	if mx.Dcache == nil {
		data.state = 12
		pc = lSwitch1
		continue
	}
	if mx.Dcache.lock != nil {
		return mx.wait(self, 1)
	}
	if j = getReader(mx.Dcache); j < 0 {
		return mx.wait(self, 1)
	}
	mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
	setLock(self, &mx.Dcache.lock)
	zapCache(mx.Dcache)
	data.state = 12
	return mx.wait(self, mx.Dcache.accessTime)

@ @<첫 단계의 특별한 상태들@>=
case stage1St + 12:
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	if mx.Scache == nil {
		pc = lFinEx
		continue
	}
	if mx.Scache.lock != nil {
		return mx.wait(self, 1)
	}
	setLock(self, &mx.Scache.lock)
	zapCache(mx.Scache)
	data.state = 3
	return mx.wait(self, mx.Scache.accessTime)

@ @<데이터 캐시들을 청소한다@>=
if self.lockloc != nil {
	*self.lockloc = nil
	self.lockloc = nil
}
@<쓰기 버퍼가 빌 때까지 기다린다@>
if mx.cleanCo.next != nil || mx.cleanLock != nil {
	return mx.wait(self, 1)
}
setLock(self, &mx.cleanLock)
mx.cleanCtl.i = sync
mx.cleanCtl.state = 0
mx.cleanCtl.x.o &= 0xffffffff
mx.startup(&mx.cleanCo, 1)
data.state = 13
data.interim = true
return mx.wait(self, 1)

@ @<쓰기 버퍼가 빌 때까지...@>=
if mx.writeHead != mx.writeTail {
	if mx.speedLock == nil {
		setLock(self, &mx.speedLock)
	}
	return mx.wait(self, 1)
}

@ 청소 과정은 엄청나게 오래 걸릴 수 있으므로 가로막을 수 있어야 한다. (물론 가로막은 것을
처리하다 보면 캐시에 더 많은 것이 들어갈 수도 있다.)

@<첫 단계의 특별한 상태들@>=
case stage1St + 13:
	if mx.cleanCo.next == nil {
		data.interim = false
		pc = lFinEx // 끝났다!
		continue
	}
	if mx.tryingToInterrupt {
		pc = lFinEx // 가로막기를 받아들인다
		continue
	}
	return mx.wait(self, 1)

@ 이제 \.{SYNCD}와 \.{SYNCID}를 생각하자. 제어가 프로그램의 이 부분에 올 때 |data.y.o|는 가상
주소이고 |data.z.o|는 해당하는 물리 주소다. 값 |data.xx+1|은 동기화해야 할 바이트 수이고, |data.b.o|의
아랫 테트라는 한 번에 다룰 수 있는 바이트 수다(|Icache.bb|나 |Dcache.bb|나 8192).

``귀띔'' 명령인 \.{PRELD}, \.{PREGO}, \.{PREST}에 쓴 것보다 더 정교한 방법이 \.{SYNCD}와
\.{SYNCID}를 구현하는 데 필요하다. \.{SYNCD}와 \.{SYNCID}는 그저 귀띔이 아니기 때문이다. 시작하는
가상 주소가 캐시 블록의 처음에 맞추어져 있다고 장담할 수 없으므로, 배정할 때 캐시 블록 크기의
명령들로 바꿀 수도 없다. \.{SYNCD}나 \.{SYNCID}가 지정하는 바이트들이 가상 페이지 경계를 넘을 수도
있고, 쪽마다 보호 비트가 다를 수도 있다는 것을 깨달아야 한다. 인터럽트도 허용해야 한다. 그리고
사용자의 \.{SYNCID}가 메모리를 완전히 최신으로 만들 때까지 가져오기 버퍼를 비워 두어야 한다.

보충: 원본의 이름표 |do_syncid|, |do_syncd|, |next_sync|는 모두 `이름표: |data.state=s|;
|case s|:' 꼴이므로 그 |case|와 합친다. 원본에서 |goto switch2|는 뒤 단계들의 상태 스위치로 다시
가르는 것이다.

@<상수@>=
const (
	lDoSyncid = stage2St + 30 // 원본의 |do_syncid|
	lDoSyncd  = stage2St + 33 // 원본의 |do_syncd|
	lNextSync = stage2St + 35 // 원본의 |next_sync|
)

@ @<뒤 단계들의 특별한 상태들@>=
case lDoSyncid:
	data.state = 30
	if data != mx.oldHot {
		return mx.wait(self, 1)
	}
	if mx.Icache == nil {
		data.state = syncidNext(data)
		pc = lSwitch2
		continue
	}
	@<|data.z.o|에 해당하는 I-캐시 블록이 있으면 청소한다@>
	data.state = syncidNext(data)
	return mx.wait(self, mx.Icache.accessTime)
case stage2St + 31:
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	@<쓰기 버퍼가 빌 때까지...@>
	if (Tetra(data.b.o)-1)&^Tetra(data.y.o) < Tetra(data.xx) {
		data.interim = true
	}
	if mx.Dcache == nil {
		pc = lNextSync
		continue
	}
	@<|data.z.o|에 해당하는 D-캐시 블록이 있으면 청소한다@>
	data.state = 32
	return mx.wait(self, mx.Dcache.accessTime)
case stage2St + 32:
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	if mx.Scache == nil {
		pc = lNextSync
		continue
	}
	@<|data.z.o|에 해당하는 S-캐시 블록이 있으면 청소한다@>
	data.state = 35
	return mx.wait(self, mx.Scache.accessTime)
@<\.{SYNCD}를 위한 상태 33부터 35까지@>

@ 운영체제의 \.{SYNCID}는 상태~31로 가서 캐시의 데이터를 버리고, 사용자의 \.{SYNCID}는
상태~33으로 가서 데이터를 써 내보낸다.

@<함수들@>=
func syncidNext(data *control) int {
	if data.loc&signBit != 0 {
		return 31
	}
	return 33
}

@ @<\.{SYNCD}를 위한...@>=
case lDoSyncd:
	data.state = 33
	if data != mx.oldHot {
		return mx.wait(self, 1)
	}
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	@<쓰기 버퍼가 빌 때까지...@>
	if (Tetra(data.b.o)-1)&^Tetra(data.y.o) < Tetra(data.xx) {
		data.interim = true
	}
	if mx.Dcache == nil {
		if data.i == syncd {
			pc = lFinEx
		} else {
			pc = lNextSync
		}
		continue
	}
	@<|data.z.o|에 해당하는 캐시 블록들에 |cleanup|을 쓴다@>
	data.state = 34
	fallthrough
case stage2St + 34:
	if mx.cleanCo.next == nil {
		pc = lNextSync
		continue
	}
	if mx.tryingToInterrupt && data.interim && data == mx.oldHot {
		data.z.o = 0 // |resumeCont|를 내다본다
		pc = lFinEx  // 가로막기를 받아들인다
		continue
	}
	return mx.wait(self, 1)

@ @<\.{SYNCD}를 위한...@>=
case lNextSync:
	data.state = 35
	if self.lockloc != nil {
		*self.lockloc = nil
		self.lockloc = nil
	}
	if data.interim {
		@<이 명령을 다음 캐시 블록에서 이어 간다@>
	}
	data.goLoc.known = true
	pc = lFinEx
	continue

@ @<|data.z.o|에 해당하는 I-캐시...@>=
if mx.Icache.lock != nil {
	return mx.wait(self, 1)
}
if j = getReader(mx.Icache); j < 0 {
	return mx.wait(self, 1)
}
mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)
setLock(self, &mx.Icache.lock)
p = mx.cacheSearch(mx.Icache, data.z.o)
if p != nil {
	mx.demoteAndFix(mx.Icache, p)
	cleanBlock(mx.Icache, p)
}

@ @<|data.z.o|에 해당하는 D-캐시...@>=
if mx.Dcache.lock != nil {
	return mx.wait(self, 1)
}
if j = getReader(mx.Dcache); j < 0 {
	return mx.wait(self, 1)
}
mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
setLock(self, &mx.Dcache.lock)
p = mx.cacheSearch(mx.Dcache, data.z.o)
if p != nil {
	mx.demoteAndFix(mx.Dcache, p)
	cleanBlock(mx.Dcache, p)
}

@ @<|data.z.o|에 해당하는 S-캐시...@>=
if mx.Scache.lock != nil {
	return mx.wait(self, 1)
}
setLock(self, &mx.Scache.lock)
p = mx.cacheSearch(mx.Scache, data.z.o)
if p != nil {
	mx.demoteAndFix(mx.Scache, p)
	cleanBlock(mx.Scache, p)
}

@ @<|data.z.o|에 해당하는 캐시 블록들에...@>=
if mx.cleanCo.next != nil || mx.cleanLock != nil {
	return mx.wait(self, 1)
}
setLock(self, &mx.cleanLock)
mx.cleanCtl.i = syncd
mx.cleanCtl.state = 4
mx.cleanCtl.x.o = mx.cleanCtl.x.o&0xffffffff | data.loc&signBit
mx.cleanCtl.z.o = data.z.o
mx.schedule(&mx.cleanCo, 1, 4)

@ 캐시 블록 크기가 8192의 약수라는 사실을 쓴다.

@<이 명령을 다음 캐시 블록에서...@>=
{
	bl := Tetra(data.b.o)
	data.interim = false
	data.xx -= byte(((bl - 1) &^ Tetra(data.y.o)) + 1)
	data.y.o += Octa(bl)
	data.y.o = data.y.o&^0xffffffff | Octa(Tetra(data.y.o)&-bl)
	data.z.o = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&^8191+Tetra(data.y.o)&8191)
	if Tetra(data.y.o)&8191 == 0 {
		pc = lSquareOne // 페이지 경계를 넘었을지도 모른다
		continue
	}
	if data.i == syncd {
		pc = lDoSyncd
	} else {
		pc = lDoSyncid
	}
	continue
}

@ 첫 페이지의 보호가 알맞지 않더라도, 드물게 페이지 경계에 걸친 경우에는 둘째 페이지를 시도해야
한다.

@<지점 이름@>=
lSyncCheck // 원본의 |sync_check|

@ @<뒤 단계들의 특별한 상태들@>=
case lSyncCheck:
	if yl := Tetra(data.y.o); yl^(yl+Tetra(data.xx)) >= 8192 {
		data.xx -= byte((8191 &^ yl) + 1)
		data.y.o += 8192
		data.y.o = data.y.o&^0xffffffff | Octa(Tetra(data.y.o)&^8191)
		pc = lSquareOne
		continue
	}
	pc = lFinEx
	continue

@* 입력과 출력. 하드웨어 구현은 끝났지만 아직 소프트웨어의 작은 문제가 남아 있다. 실제 운영체제를
적재하지 않고도 운영체제가 있는 척하고 싶을 때가 있기 때문이다. 그래서 이 시뮬레이터는 특별한
기능을 하나 구현한다. 위치~rT에서 \.{RESUME}~\.1을 발행하면, {\mc MMIX-SIM}의 특별한 입출력 트랩
열 가지가 뒤에서 순식간에 수행된다.

물론 이 기능을 쓰면 정확한 시뮬레이션이라는 주장은 모두 물거품이 된다.

@<상수@>=
const (
	Halt = iota
	Fopen
	Fclose
	Fread
	Fgets
	Fgetws
	Fwrite
	Fputs
	Fputws
	Fseek
	Ftell
)
@#
const maxSysCall = Ftell

@ 보충: 원본은 조건이 맞지 않으면 이름표 |magic_done|으로 뛰었다. 여기서는 조건을 |if| 문에
모았다.

@<|cool.loc|이 rT이면 마법처럼...@>=
if cool.loc == mx.g[rT].o {
	if xl := Tetra(mx.g[rXX].o); xl&0xffff0000 == 0 && byte(xl>>8) <= maxSysCall {
		yy, zz := byte(xl>>8), byte(xl)
		var ma, mb Octa
		@<필요하면 메모리 인자 $|ma|={\rm M}[a]$와 $|mb|={\rm M}[b]$를 준비한다@>
		switch yy {
		case Halt:
			@<멈추거나 경고를 찍는다@>
		case Fopen:
			mx.g[rBB].o = mx.io.Fopen(zz, mb, ma)
		case Fclose:
			mx.g[rBB].o = mx.io.Fclose(zz)
		case Fread:
			mx.g[rBB].o = mx.io.Fread(zz, mb, ma)
		case Fgets:
			mx.g[rBB].o = mx.io.Fgets(zz, mb, ma)
		case Fgetws:
			mx.g[rBB].o = mx.io.Fgetws(zz, mb, ma)
		case Fwrite:
			mx.g[rBB].o = mx.io.Fwrite(zz, mb, ma)
		case Fputs:
			mx.g[rBB].o = mx.io.Fputs(zz, mx.g[rBB].o)
		case Fputws:
			mx.g[rBB].o = mx.io.Fputws(zz, mx.g[rBB].o)
		case Fseek:
			mx.g[rBB].o = mx.io.Fseek(zz, mx.g[rBB].o)
		case Ftell:
			mx.g[rBB].o = mx.io.Ftell(zz)
		}
	}
	mx.g[255].o = negOne // 이것이 인터럽트를 허용한다
}

@ @<멈추거나 경고를...@>=
if zz == 0 {
	mx.halted = true
} else if zz == 1 {
	trapLoc := mx.g[rWW].o - 4
	if !(trapLoc>>32 != 0 || Tetra(trapLoc) >= 0xf0) {
		mx.io.PrintTripWarning(int(Tetra(trapLoc)>>4), mx.g[rW].o-4)
	}
}

@ @<표@>=
var argCount = [11]int{1, 3, 1, 3, 3, 3, 3, 2, 2, 2, 1}

@ \.{TRAP}이 부르는 입출력 연산들은 {\mc MMIX-IO}라는 보조 프로그램 모듈의 서브루틴들이 한다.
여기서는 그 서브루틴들을 선언하고, 그것들이 기대는 기본 인터페이스 세 개를 쓰기만 하면 된다.

보충: \.{mmixsim}에서처럼 \GO/에서는 \.{mmixio} 꾸러미의 인터페이스 |mmixio.Simulator|가 요구하는
메서드 세 개 |MMGetChars|, |MMPutChars|, |StdinChr|을 |machine|에 정의한다.

@ 마법 같은 입출력을 하려면 버퍼와 캐시의 복잡한 사정을 모두 뚫고 지나가야 한다. 루틴
|magicRead|는 주어진 물리 주소의 현재 옥타바이트를, 쓰기 버퍼, D-캐시, S-캐시, 메모리를 차례로
보면서 찾는다.

@<함수들@>=
func (mx *machine) magicRead(addr Octa) Octa {
	for q := mx.writeTail; q != mx.writeHead; {
		q = mx.nextWrite(q)
		if q.addr&^7 == addr&^7 {
			return q.o
		}
	}
	if mx.Dcache != nil {
		if o, ok := mx.magicReadCache(mx.Dcache, addr); ok {
			return o
		}
		if mx.Scache != nil {
			if o, ok := mx.magicReadCache(mx.Scache, addr); ok {
				return o
			}
		}
	}
	return mx.memRead(addr)
}

@ 보충: 원본은 D-캐시와 S-캐시에 대해 같은 코드를 두 번 적었다. 여기서는 함수로 둔다.

@<함수들@>=
func (mx *machine) magicReadCache(c *cache, addr Octa) (Octa, bool) {
	k := (Tetra(addr) & Tetra(c.bb-1)) >> 3
	if p := mx.cacheSearch(c, addr); p != nil {
		return p.data[k], true
	}
	if (Tetra(c.outbuf.tag)^Tetra(addr))&Tetra(-c.bb) == 0 && c.outbuf.tag>>32 == addr>>32 {
		return c.outbuf.data[k], true
	}
	return 0, false
}

@ 루틴 |magicWrite|는 주어진 물리 주소의 옥타바이트를, 그것이 나타나는 버퍼와 캐시마다 바꾼다.
``더러움''이나 ``가장 오래전에 씀'' 상태는 그대로 둔다. (그렇다, 이것이 {\it 바로\/} 마법이다.)

@<함수들@>=
func (mx *machine) magicWrite(addr, val Octa) {
	for q := mx.writeTail; q != mx.writeHead; {
		q = mx.nextWrite(q)
		if q.addr&^7 == addr&^7 {
			q.o = val
		}
	}
	if mx.Dcache != nil {
		mx.magicWriteCache(mx.Dcache, addr, val)
		if mx.Scache != nil {
			mx.magicWriteCache(mx.Scache, addr, val)
		}
	}
	mx.memWrite(addr, val)
}
@#
func (mx *machine) magicWriteCache(c *cache, addr, val Octa) {
	k := (Tetra(addr) & Tetra(c.bb-1)) >> 3
	if p := mx.cacheSearch(c, addr); p != nil {
		p.data[k] = val
	}
	for _, b := range []*cacheblock{&c.inbuf, &c.outbuf} {
		if (Tetra(b.tag)^Tetra(addr))&Tetra(-c.bb) == 0 && b.tag>>32 == addr>>32 {
			b.data[k] = val
		}
	}
}

@ 우리의 상상 속 운영체제의 관례에 따라, 세그먼트~$i$가 물리 주소 $2^{32}i$에서 시작하는
$2^{32}$바이트짜리 페이지에 나타나는 하찮은 메모리 사상을 적용해야 한다.

보충: 원본은 주소의 윗 테트라를 29비트 오른쪽으로 옮겼다. 그 일을 하는 함수 |magicAddr|를 둔다.
주소의 윗 테트라에서 세그먼트 번호 말고는 모두 0이라고 가정한다.

@<함수들@>=
func magicAddr(a Octa) Octa {
	return Octa(Tetra(a>>32)>>29)<<32 | a&0xffffffff
}

@ @<필요하면 메모리 인자...@>=
if argCount[yy] == 3 {
	if argLoc := mx.g[rBB].o; argLoc>>32&0x9fffffff == 0 {
		mb = mx.magicRead(magicAddr(argLoc))
	}
	if argLoc := mx.g[rBB].o + 8; argLoc>>32&0x9fffffff == 0 {
		ma = mx.magicRead(magicAddr(argLoc))
	}
}

@ 서브루틴 |MMGetChars(buf,size,addr,stop)|은 모의 메모리의 주소 |addr|에서 시작해서 문자들을
읽어 |buf|에 넣는다. 문자를 |size|개 읽었거나 다른 어떤 멈춤 조건을 만날 때까지 계속한다. 인자
|stop|이 음수이면 다른 조건이 없다. 그것이 0이면 널 문자에서도 멈춘다. 그 밖에는 |addr|이 짝수이고,
짝수 주소에서 시작하는 연이은 널 바이트 둘에서 멈춘다. 읽어서 넣은 바이트의 개수를 돌려주는데,
끝을 알리는 널 문자는 세지 않는다.

보충: 원본에서 |m|은 읽은 개수이고 |p|는 |buf+m|이었다. 여기서는 색인 |k| 하나로 둘을 대신한다.

@<함수들@>=
func (mx *machine) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	if (addr>>32&0x9fffffff != 0 || (addr+Octa(size-1))>>32&0x9fffffff != 0) && size != 0 {
		mx.errprintf("Attempt to get characters from off the page!\n")
@.Attempt to get characters...@>
		return 0
	}
	a := magicAddr(addr)
	for k := 0; k < size; {
		x := mx.magicRead(a)
		if a&0x7 != 0 || k > size-8 {
			@<바이트 하나를 읽어서 넣는다; 끝났으면 |return|한다@>
		} else {
			@<바이트를 여덟까지 읽어서 넣는다; 끝났으면 |return|한다@>
		}
	}
	return size
}

@ 보충: \.{mmixsim}에서처럼, 홀수 주소의 첫 바이트가 0이면 원본은 |buf|의 앞 바이트를 읽는다.
그 바이트를 0으로 쳐서 $-1$을 돌려준다.

@<바이트 하나를 읽어서...@>=
buf[k] = byte(x >> (8 * (^a & 0x7)))
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

@ @<바이트를 여덟까지...@>=
{
	h, l := Tetra(x>>32), Tetra(x)
	buf[k] = byte(h >> 24)
	if buf[k] == 0 && (stop == 0 || stop > 0 && h < 0x10000) {
		return k
	}
	buf[k+1] = byte(h >> 16)
	if buf[k+1] == 0 && stop == 0 {
		return k + 1
	}
	buf[k+2] = byte(h >> 8)
	if buf[k+2] == 0 && (stop == 0 || stop > 0 && h&0xffff == 0) {
		return k + 2
	}
	buf[k+3] = byte(h)
	if buf[k+3] == 0 && stop == 0 {
		return k + 3
	}
	buf[k+4] = byte(l >> 24)
	if buf[k+4] == 0 && (stop == 0 || stop > 0 && l < 0x10000) {
		return k + 4
	}
	buf[k+5] = byte(l >> 16)
	if buf[k+5] == 0 && stop == 0 {
		return k + 5
	}
	buf[k+6] = byte(l >> 8)
	if buf[k+6] == 0 && (stop == 0 || stop > 0 && l&0xffff == 0) {
		return k + 6
	}
	buf[k+7] = byte(l)
	if buf[k+7] == 0 && stop == 0 {
		return k + 7
	}
	k += 8
	a += 8
}

@ 서브루틴 |MMPutChars(buf,size,addr)|는 |size|개의 문자를 주소 |addr|에서 시작하는 모의
메모리에 넣는다.

@<함수들@>=
func (mx *machine) MMPutChars(buf []byte, size int, addr Octa) {
	if (addr>>32&0x9fffffff != 0 || (addr+Octa(size-1))>>32&0x9fffffff != 0) && size != 0 {
		mx.errprintf("Attempt to put characters off the page!\n")
@.Attempt to put characters...@>
		return
	}
	a := magicAddr(addr)
	for k := 0; k < size; {
		if a&0x7 != 0 || k > size-8 {
			@<바이트 하나를 적재해서 쓴다@>
		} else {
			@<바이트 여덟을 적재해서 쓴다@>
		}
	}
}

@ @<바이트 하나를 적재해서...@>=
{
	s := 8 * (^a & 0x7)
	x := mx.magicRead(a)
	x ^= ((x>>s ^ Octa(buf[k])) & 0xff) << s
	mx.magicWrite(a, x)
	k++
	a++
}

@ @<바이트 여덟을 적재해서...@>=
{
	var x Octa
	for _, b := range buf[k : k+8] {
		x = x<<8 | Octa(b)
	}
	mx.magicWrite(a, x)
	k += 8
	a += 8
}

@ 모의 프로그램이 표준 입력을 읽는 동안 그것을 대화에도 쓴다면, 모의 프로그램의 \.{StdIn}을 위한
버퍼를 따로 두어 두 쓰임을 떼어 놓으려 한다. 온라인 입력은 대개 키보드에서 \CEE/ 프로그램으로 한
줄씩 전해진다. 그래서 새 입력을 받으려고 프롬프트를 띄울 때는 |fread|보다 |fgets|가 훨씬 잘 된다.
그러나 조금 복잡한 문제가 있다. 함수 |fgets|는 줄 바꿈 문자에 이르기 전에 널 문자를 읽을 수도 있다.
그래서 |fgets|가 읽은 문자의 개수를 |strlen(stdin_buf)|만 보고 알아낼 수는 없다.

보충: 원본은 |fgets|가 실패해도 따지지 않는다. 그러면 버퍼에 앞서 읽은 바이트들이 남아 있고, 그것이
다시 모의 프로그램에 넘어간다. 여기서도 그대로 흉내 낸다.

@<함수들@>=
func (mx *machine) StdinChr() byte {
	for mx.stdinBufStart == mx.stdinBufEnd {
		mx.printf("StdIn> ")
@.StdIn>@>
		mx.out.Flush()
		mx.stdin.fgets(mx.stdinBuf[:], 256)
		mx.stdinBufStart = 0
		p := 0
		for ; p < 254; p++ {
			if mx.stdinBuf[p] == '\n' {
				break
			}
		}
		mx.stdinBufEnd = p + 1
	}
	c := mx.stdinBuf[mx.stdinBufStart]
	mx.stdinBufStart++
	return c
}

@ @<기계의 상태@>=
stdinBuf      [256]byte // 모의 프로그램의 표준 입력
stdinBufStart int       // 그 버퍼에서의 현재 위치
stdinBufEnd   int       // 그 버퍼의 현재 끝

@* 기계. 보충: 이 장은 옮긴이가 덧붙인 것이다. 원본의 전역 변수들은 모두 앞에서 조금씩 정의한
절 ``기계의 상태''에 모였다. 그것들을 필드로 가진 구조체가 |machine|이다. 여기에 입출력을 위한
필드를 더한다. 표준 출력은 버퍼를 거치고, 표준 오류는 바로 쓴다. 필드 |io|는 \.{mmixio}의 상태이고,
|stdin|은 표준 입력을 \CEE/의 |fgets|처럼 읽는 파일이다. 타입 \KW{cfile}은 \.{mmmix.w}에서 정의한다.
필드 |specBuf|는 \.{mmixmem.w}의 원본에서 정적 버퍼였다.

@<타입 정의@>=
type machine struct {
	@<기계의 상태@>
	out    *bufio.Writer // 표준 출력
	stderr io.Writer     // 표준 오류
	io     *mmixio.IO    // 모의 프로그램의 파일들
	stdin  *cfile        // 표준 입력
	specBuf [20]byte     // \.{mmixmem.w}의 |specRead|가 쓰는 버퍼
}

@ 원본의 |exit(n)|은 종료 코드를 담은 |exitSignal|을 던지는 공황이 된다. 주 프로그램이 그것을
받아 종료 코드로 바꾼다.

@<타입 정의@>=
type exitSignal int

@* 찾아보기.
