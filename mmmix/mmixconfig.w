% 이 파일은 MMIXware의 mmix-config.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w


\input kotexgweb
\def\title{MMIXCONFIG}
\def\PV{\\{PV}} % 타자기체가 아니라 이탤릭으로
\def\CPV{\\{CPV}}
\def\OP{\\{OP}}

@* 입력 형식. 설정 파일은 이 시뮬레이터가 한없이 많은 하드웨어 기능의 조합에 스스로를 맞출
수 있게 해 준다. 이 모듈의 목적은 설정 파일을 읽고, 올바른지 검사하고, 관련된 데이터 구조를
준비하는 것이다.

설정 파일의 데이터는 모두 하나 이상의 공백으로 구분된 {\it 토큰\/}들로만 이루어진다. 여기서
``토큰''은 퍼센트 기호를 담지 않은, 공백이 아닌 문자들의 열이다. 퍼센트 기호와 그 줄에서 그
뒤에 오는 것은 모두 무시한다. 이 관례 덕분에 사용자는 파일에 주석을 넣을 수 있다. 다음은
간단한 (그러나 기묘한) 예다.
$$\vbox{\halign{\tt#\hfil\cr
\% Silly configuration\cr
writebuffer 200\cr
memaddresstime 100\cr
Dcache associativity 4 lru\cr
Dcache blocksize 1024\cr
unit ODD 5555555555555555555555555555555555555555555555555555555555555555\cr
unit EVEN aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\cr
div 40 30 20\ \ \% three-stage divide\cr
}}$$
이것은 다음을 뜻한다. (1) 쓰기 버퍼에는 옥타바이트 200개를 담을 자리가 있다. (2)~메모리
버스는 주소 하나를 처리하는 데 100사이클이 걸린다. (3)~D-캐시가 있는데, 집합마다 블록이 4개
있고 교체 방침은 가장 오래전에 쓴 것(LRU)이다. (4)~D-캐시의 블록마다 1024바이트가 있다.
(5)~기능 장치가 둘 있는데, 하나는 홀수 번호 연산 코드를 모두 맡고 다른 하나는 나머지를 모두
맡는다. (6)~나눗셈 명령은 파이프라인 세 단계를 거치는데, 첫 단계에서 40사이클, 둘째에서
30사이클, 마지막에서 20사이클을 보낸다. (7)~다른 매개변수는 모두 기본값을 가진다.

보충: \GO/ 판에서 이 모듈은 메타 시뮬레이터의 \.{main} 꾸러미에 든 파일 하나다. 원본은
전역 변수와 서브루틴을 파일 안에 가두었는데, 여기서는 설정 파일을 읽는 동안에만 쓰는
상태를 구조체 |configReader|에 모으고, 그 밖의 결과는 모두 기계 |mx|의 필드에 넣는다. 원본의
|MMIX_config|는 |machine|의 메서드 |MMIXConfig|이고, 이 문서의 끝 ``모두 합치기'' 장에 있다.

@c
package main

import "io"

@<타입 정의@>
@<상수@>
@<표@>
@<함수들@>

@ 설정 파일에는 네 종류의 명세가 다음 문법에 따라 나타날 수 있다.
$$\vbox{\halign{$#$\hfil\cr
\<specification>\is\<PV spec>\mid\<cache spec>\mid\<pipe spec>\mid
  \<functional spec>\cr
\<PV spec>\is\<parameter>\<decimal value>\cr
\<cache spec>\is\<cache name>\<cache parameter>\<decimal value>\<policy>\cr
\<pipe spec>\is\<operation>\<pipeline times>\cr
\<functional spec>\is\.{unit}\ \<name>\<64 hexadecimal digits>\cr}}$$

@ \<PV spec>은 주어진 매개변수에 주어진 값을 줄 뿐이다. \<parameter>로 쓸 수 있는 것은 다음과
같다.

\def\pbull#1 {\smallskip\hang\textindent{$\bullet$}\.{#1}\enspace}
\pbull fetchbuffer (기본값 4), 가져오기 버퍼에 담을 수 있는 명령의 최대 수. 1 이상이어야
한다.

\pbull writebuffer (기본값 2), 쓰기 버퍼에 담을 수 있는 옥타바이트의 최대 수. 1 이상이어야
한다.

\pbull reorderbuffer (기본값 5), 발행했지만 확정하지 않은 명령의 최대 수. 1 이상이어야 한다.

\pbull renameregs (기본값 5), 재정렬 버퍼에 담을 수 있는 부분 결과의 최대 수. 1 이상이어야
한다.

\pbull memslots (기본값 2), 재정렬 버퍼에 담을 수 있는 저장 명령의 최대 수. 1 이상이어야
한다.

\pbull localregs (기본값 256), 고리에 든 지역 레지스터의 수. 256이나 512나 1024여야 한다.

\pbull fetchmax (기본값 2), 한 사이클에 가져오는 명령의 최대 수. 1 이상이어야 한다.

\pbull dispatchmax (기본값 1), 한 사이클에 발행하는 명령의 최대 수. 1 이상이어야 한다.

\pbull peekahead (기본값 1), 한 사이클에 점프를 찾으려고 앞을 엿보는 최대 수.

\pbull commitmax (기본값 1), 한 사이클에 확정하는 명령의 최대 수. 1 이상이어야 한다.

\pbull fremmax (기본값 1), 한 사이클에 하는 \.{FREM} 계산의 줄임 단계의 최대 수. 1 이상이어야
한다.

\pbull denin (기본값 1), 부동소수점 입력이 비정규수이면 더 걸리는 사이클 수.

\pbull denout (기본값 1), 부동소수점 결과가 비정규수이면 더 걸리는 사이클 수.

\pbull writeholdingtime (기본값 0), 데이터가 쓰기 버퍼에 머물러야 하는 최소 사이클 수.

\pbull memaddresstime (기본값 20), 메모리 주소를 처리하는 사이클 수. 1 이상이어야 한다.

\pbull memreadtime (기본값 20), 메모리 버스 한 번 분량을 읽는 사이클 수. 1 이상이어야 한다.

\pbull memwritetime (기본값 20), 메모리 버스 한 번 분량을 쓰는 사이클 수. 1 이상이어야 한다.

\pbull membusbytes (기본값 8), 메모리 버스 한 번 분량의 바이트 수. 8 이상인 2의 거듭제곱이어야
한다.

\pbull branchpredictbits (기본값 0), 분기 예측 표의 항목마다 든 비트 수. 8 이하여야 한다.

\pbull branchaddressbits (기본값 0), 분기 예측 표의 색인으로 쓰는 명령 주소의 비트 수.

\pbull branchhistorybits (기본값 0), 분기 예측 표의 색인으로 쓰는 분기 이력의 비트 수.

\pbull branchdualbits (기본값 0), 분기 예측 표의 색인으로 쓰는, 명령 주소와 분기 이력의 배타적
논리합의 비트 수.

\pbull hardwarepagetable (기본값 1), 페이지 테이블 계산을 운영체제가 에뮬레이트해야 하면 0이다.

\pbull disablesecurity (기본값 0), 뜨거운 자리의 보안 검사를 끄면 1이다. 이 선택 사항은 시험할
때만 쓴다. 이것을 켜면 `\.s' 인터럽트는 일어나지 않고, `\.p' 인터럽트는 음이 아닌 위치에서 음인
위치로 갈 때만 알린다.

\pbull memchunksmax (기본값 1000), 모의 메모리의 $2^{16}$바이트짜리 덩이의 최대 수. 1 이상이어야
한다.

\pbull hashprime (기본값 2003), 모의 메모리의 주소를 찾는 데 쓰는 소수. \.{memchunksmax}보다
커야 하는데, 두 배쯤 되는 것이 좋다.

\smallskip\noindent
매개변수 \.{memchunksmax}와 \.{hashprime}의 값은 시뮬레이터의 결과가 아니라 속도에만 영향을
준다. 아주 거대한 프로그램을 흉내 내는 것이 아니라면 말이다. \.{memchunksmax}와
\.{hashprime}의 기본값은 거의 모든 쓰임에 넉넉할 것이다.

@ \<cache spec>은 다섯 가지 캐시 가운데 하나에 영향을 주는 매개변수에 주어진 값을 준다.
$$\vbox{\halign{$#$\hfil\cr
\<cache spec>\is\<cache name>\<cache parameter>\<decimal value>\<policy>\cr
\<cache name>\is\.{ITcache}\mid\.{DTcache}\mid\.{Icache}\mid\.{Dcache}
  \mid\.{Scache}\cr
\<policy>\is\<empty>\mid\.{random}\mid\.{serial}
          \mid\.{pseudolru}\mid\.{lru}\cr}}$$
\<cache parameter>로 쓸 수 있는 것은 다음과 같다.

\pbull associativity (기본값 1), 캐시 집합마다 든 캐시 블록의 수. 2의 거듭제곱이어야 한다.
(연관도가~1인 캐시를 ``직접 사상'' 캐시라고 한다.)

\pbull blocksize (기본값 8), 캐시 블록마다 든 바이트 수. 2의 거듭제곱이어야 하고, 알갱이
이상이고 8192 이하여야 한다. \.{ITcache}와 \.{DTcache}의 블록 크기는 8이어야 한다.

\pbull setsize (기본값 1), 캐시 블록 집합의 수. 2의 거듭제곱이어야 한다. (집합 크기가~1인
캐시를 ``완전 연관'' 캐시라고 한다.)

\pbull granularity (기본값 8), ``더러움 비트'' 하나가 맡는 바이트 수. 더러움 비트는 메모리에서
읽은 뒤로 바뀐 데이터를 기억하는 데 쓴다. 8 이상인 2의 거듭제곱이어야 한다. \.{writeallocate}가
0이면 알갱이는 8이어야 한다.

\pbull victimsize (기본값 0), 주 캐시 집합에서 빼낸 블록을 담는 희생자 버퍼의 캐시 블록 수.
0이거나 2의 거듭제곱이어야 한다.

\pbull writeback (기본값 0), 더러운 데이터를 되도록 오래 붙드는 ``나중 쓰기'' 캐시이면 1이고,
모든 데이터를 되도록 빨리 깨끗이 하는 ``즉시 쓰기'' 캐시이면 0이다.

\pbull writeallocate (기본값 0), 최근에 쓴 데이터를 모두 기억하는 ``쓰기 할당'' 캐시이면
1이고, 기존 캐시 블록에 적중하지 않은 새로 쓴 데이터를 위해 자리를 만들지 않는 ``쓰기 우회''
캐시이면 0이다.

\pbull accesstime (기본값 1), 캐시에 묻는 데 드는 사이클 수. 1 이상이어야 한다. (S-캐시의
적중에는 사실 접근 시간의 {\it 두 배\/}가 든다. 한 번은 태그를 묻고 한 번은 데이터를 보낸다.)

\pbull copyintime (기본값 1), 캐시 블록을 입력 버퍼에서 캐시 본체로 옮기는 사이클 수. 1
이상이어야 한다.

\pbull copyouttime (기본값 1), 캐시 블록을 캐시 본체에서 출력 버퍼로 옮기는 사이클 수. 1
이상이어야 한다.

\pbull ports (기본값 1), 동시에 캐시에 물을 수 있는 프로세스의 수. 1 이상이어야 한다.

\smallskip
\<policy> 매개변수는 \.{associativity}와 \.{victimsize} 매개변수의 캐시 명세에서만 비어 있지
않아야 한다. 교체 방침을 지정하지 않으면 \.{random}이 기본값이다. \.{associativity}나
\.{victimsize}가~1이면 네 방침은 모두 같다. 그것이 2이면 \.{pseudolru}는 \.{lru}와 같다.

\.{granularity}, \.{writeback}, \.{writeallocate}, \.{copyouttime} 매개변수는 D-캐시와 S-캐시의
성능에만 영향을 준다. 다른 세 캐시는 읽기 전용이어서 데이터를 쓸 일이 없기 때문이다.

\.{ports} 매개변수는 D-캐시와 DT-캐시의 성능에 영향을 주고, (\.{PREGO} 명령을 쓴다면) I-캐시와
IT-캐시의 성능에도 영향을 준다. S-캐시는 지정한 포트의 수와 상관없이 한 번에 한 프로세스만
받아들인다.

기본으로는 변환 캐시(IT-캐시와 DT-캐시)만 있다. 그러나 이를테면 I-캐시에 대한 명세가 하나라도
있으면, 지정하지 않은 I-캐시의 매개변수는 모두 기본값을 가진다.

S-캐시(2차 캐시)가 있다는 것은 I-캐시와 D-캐시(명령과 데이터를 위한 1차 캐시)가 둘 다 있다는
뜻이다. 2차 캐시의 블록 크기는 1차 캐시의 블록 크기보다 작으면 안 된다. 2차 캐시의 알갱이는
D-캐시의 것과 같아야 한다.

@ \<pipe spec>은 느릴지도 모르는 연산의 실행 시간을 정한다.
$$\vbox{\halign{$#$\hfil\cr
\<pipe spec>\is\<operation>\<pipeline times>\cr
\<pipeline times>\is\<decimal value>\mid\<pipeline times>\<decimal value>\cr}}$$
여기서 \<operation>은 다음 가운데 하나다.

\pbull mul0 (기본값 10). \.{mul1}부터 \.{mul8}까지도 기본값은 10이다. \.{mul}$j$의 값은 둘째
피연산자가 $2^{8j}$보다 작은 곱에 적용되는데, 여기서 $j$는 되도록 작게 잡는다. 이를테면
\.{mul1}은 0이 아닌 한 바이트짜리 곱수에 적용된다.

\pbull div (기본값 60). 부호 있는 정수 나눗셈과 부호 없는 정수 나눗셈에 적용된다.

\pbull sh (기본값 1). 왼쪽과 오른쪽 자리 옮김에 적용된다. 부호 있는 것과 없는 것 모두에.

\pbull mux (기본값 1). 멀티플렉스 연산자.

\pbull sadd (기본값 1). 옆으로 더하기 연산자.

\pbull mor (기본값 1). 불 행렬 곱셈 연산자 \.{MOR}과 \.{MXOR}.

\pbull fadd (기본값 4). 부동소수점 덧셈과 뺄셈.

\pbull fmul (기본값 4). 부동소수점 곱셈.

\pbull fdiv (기본값 40). 부동소수점 나눗셈.

\pbull fsqrt (기본값 40). 부동소수점 제곱근.

\pbull fint (기본값 4). 부동소수점 정수화.

\pbull fix (기본값 2). 부동소수점에서 고정소수점으로 바꾸기. 부호 있는 것과 없는 것 모두에.

\pbull flot (기본값 2). 고정소수점에서 부동소수점으로 바꾸기. 부호 있는 것과 없는 것 모두에.

\pbull feps (기본값 4). 엡실론에 대한 부동소수점 비교.

\smallskip\noindent
어느 경우든 파이프라인 단계의 열을 지정할 수 있는데, 단계마다 양의 사이클 수를 쓴다. 이를테면
`\.{fmul}~\.{3}~\.{1}' 같은 명세는 \.{FMUL}을 지원하는 기능 장치가 부동소수점 곱을 계산하는 데
두 단계에 걸쳐 모두 네 사이클이 걸린다는 뜻이다. 세 사이클이 지나면 둘째 곱을 계산하기 시작할
수 있다.

부동소수점 연산의 입력이 비정규수이면 첫 단계의 시간에 \.{denin}을 더한다. 부동소수점 연산의
결과가 비정규수이면 마지막 단계의 시간에 \.{denout}을 더한다.

@ 넷째이자 마지막 종류의 명세는 기능 장치를 정의한다.
$$\<functional spec>\is\.{unit}\ \<name>\<64 hexadecimal digits>$$
기호 이름은 열다섯 자를 넘지 않아야 한다. 십육진 숫자 64개에는 256비트가 들어 있는데, 지원하는
연산 코드마다 `1'이다. 가장 큰 쪽(가장 왼쪽) 비트는 연산 코드 0(\.{TRAP})에 해당하고, 가장
작은 쪽 비트는 연산 코드 255(\.{TRIP})에 해당한다.

이를테면 적재/저장 장치(레지스터와 메모리 사이의 연산을 맡는다), 곱셈 장치(고정소수점과
부동소수점 곱셈을 맡는다), 불 장치(비트 단위 연산만 맡는다), 그리고 좀 더 일반적인 산술 논리
장치를 다음과 같이 정의할 수 있다.
$$\vbox{\halign{\tt#\hfil\cr
unit LSU 00000000000000000000000000000000fffffffcfffffffc0000000000000000\cr
unit MUL 000080f000000000000000000000000000000000000000000000000000000000\cr
unit BIT 000000000000000000000000000000000000000000000000ffff00ff00ff0000\cr
unit ALU f0000000ffffffffffffffffffffffff0000000300000003ffffffffffffffff\cr
}}$$

장치를 지정하는 순서가 중요하다. \MMIX의 배정기는 명령마다 그 연산 코드를 지원하는 첫 기능
장치와 맞추어 보기 때문이다. 그러니 더 전문화된 장치(이 예의 \.{BIT} 장치 같은 것)를 더 일반적인
장치보다 먼저 적는 것이 가장 좋다. 그러면 전문화된 장치가 자기가 다룰 수 있는 명령을 먼저 받을
기회를 얻는다.

기능 장치는 몇 개든 둘 수 있고, 명세가 똑같아도 된다. 그러나 장치마다 고유한 이름을 주는 것이
좋다(이를테면 산술 논리 장치가 둘이면 \.{ALU1}과 \.{ALU2}). 그 이름들이 진단 메시지에 쓰이기
때문이다.

지정한 어느 장치도 지원하지 않는 연산 코드는 에뮬레이션 트랩을 일으킨다.
@^emulation@>

@ 이 모든 매개변수의 뜻을 자세히 알려면 \.{mmixpipe} 모듈을 보면 된다. 그 모듈은 설정하고
초기화해야 할 데이터 구조를 정의하고 설명한다.

물론 설정 파일의 명세가 말이 될 필요는 없고, 실제로 만들 수 있을 필요도 없다. 이를테면
\.{NXOR}와 \.{DIVUI} 두 연산 코드만 다루는 장치를 지정할 수도 있다. 나눗셈은 1사이클인데 자리
옮김은 100사이클짜리 파이프라인으로 지정할 수도 있고, 메모리 접근은 1사이클인데 캐시 접근은
100사이클로 지정할 수도 있다. 이름 바꾸기 레지스터를 천 개 만들고 한 사이클에 명령을 백 개 발행할
수도 있다. 어떤 매개변수 조합은 뻔히 터무니없다.

그러나 흥미로운 가능성은 여전히 엄청나게 많이 남는다. 기술이 계속 발전하니 더욱 그렇다.
오늘날의 기준으로 극단적인 설정으로 실험해 보면, 그에 해당하는 하드웨어를 경제적으로 만들 수
있다면 얼마나 얻을 수 있을지 알 수 있다.

@* 기본 입출력. 몇 가지 간단한 기반 시설을 만들어서 |MMIX_config| 서브루틴을 짤 준비를 하자.
먼저 오류 메시지를 찍는 매크로가 필요하다.

보충: 원본의 매크로 |panic(x)|는 메시지 |x|를 표준 오류에 찍고 \.{"!\\n"}을 찍은 뒤
|exit(-1)|로 끝냈다. \.{mmixpipe}의 |panic|과 달리 앞에 \.{"Panic: "}을 붙이지 않는다. 여기서는
그 일을 하는 메서드 |configPanic|이다.

@<함수들@>=
func (cf *configReader) configPanic(format string, a ...any) {
	cf.mx.errprintf(format, a...)
	cf.mx.errprintf("!\n")
	panic(exitSignal(-1))
}

@ 그리고 입력을 볼 곳이 필요하다.

보충: 설정 파일을 읽는 동안에만 쓰는 원본의 전역 변수들은 구조체 |configReader|의 필드다.
원본의 |get_token|에 있던 정적 변수 |buffer|와 |buf_pointer|도 호출 사이에 값을 지켜야 하므로
필드다. 설정 파일은 \.{mmmix.w}에서 정의하는 타입 |cfile|로 읽는데, \CEE/의 |fgets|를 흉내 낸다.

@<상수@>=
const configBufSize = 100 // we don't need long lines

@ @<타입 정의@>=
type configReader struct {
	mx               *machine            // the machine being configured
	configFile       *cfile              // input comes from here
	token            string              // and tokens are copied to here
	tokenPrescanned  bool                // does |token| contain the next token already?
	buffer           [configBufSize]byte // input lines go here
	bufPointer       int                 // this is our current position
	@<설정하는 동안의 다른 상태@>
}

@ 루틴 |getToken|은 입력의 다음 토큰을 |token|에 복사한다. 입력이 끝난 뒤에는 마지막으로
`\.{end}'를 덧붙인다.

보충: 원본은 토큰을 공백이나 \.{\%}를 만날 때까지 복사했다. 줄 바꿈 문자로 끝나지 않는 마지막
줄에서는 널 문자를 지나 버퍼에 남은 옛 바이트까지 복사한다. 그러나 \CEE/ 문자열로서의 토큰은
첫 널 문자에서 끝나고, 다음 호출은 옛 바이트들에서 토큰을 계속 찾는다. 여기서도 그대로
흉내 낸다. 다만 버퍼 끝을 넘어서는 읽지 않고, 버퍼 끝을 널 문자처럼 다룬다.

@<함수들@>=
func (cf *configReader) getToken() { // set |token| to the next token of the configuration file
	if cf.tokenPrescanned {
		cf.tokenPrescanned = false
		return
	}
	for { // scan past white space
		c := byte(0) // treat the end of the buffer as a null character
		if cf.bufPointer < configBufSize {
			c = cf.buffer[cf.bufPointer]
		}
		if c == 0 || c == '\n' || c == '%' {
			if !cf.configFile.fgets(cf.buffer[:], configBufSize) {
				cf.token = "end"
				return
			}
			if strlen(cf.buffer[:]) == configBufSize-1 && cf.buffer[configBufSize-2] != '\n' {
				cf.configPanic("config file line too long: `%s...'", cstr(cf.buffer[:]))
@.config file line...@>
			}
			cf.bufPointer = 0
		} else if !isspace(c) {
			break
		} else {
			cf.bufPointer++
		}
	}
	p := cf.bufPointer
	for p < configBufSize && !isspace(cf.buffer[p]) && cf.buffer[p] != '%' {
		p++
	}
	cf.token = string(cstr(cf.buffer[cf.bufPointer:p]))
	cf.bufPointer = p
}

@ 루틴 |getInt|는 십진 값을 입력하고 싶을 때 부른다. 다음 토큰이 십진 숫자들의 열이 아니면
$-1$을 돌려준다.

보충: 원본은 |int|에 값을 모았으므로 32비트로 넘친다. 여기서도 그렇게 한다. 빈 토큰이면 0을
돌려주는 것도 원본과 같다.

@<함수들@>=
func (cf *configReader) getInt() int {
	cf.getToken()
	var v int32
	p := 0
	for ; p < len(cf.token) && cf.token[p] >= '0' && cf.token[p] <= '9'; p++ {
		v = 10*v + int32(cf.token[p]-'0')
	}
	if p < len(cf.token) {
		return -1
	}
	return int(v)
}

@ 간단한 데이터 구조 하나로 매개변수/값 명세를 꽤 쉽게 다룰 수 있다.

@<타입 정의@>=
type pvSpec struct {
	name           string // symbolic name
	v              *int   // internal name
	defval         int    // default value
	minval, maxval int    // minimum and maximum legal values
	powerOfTwo     bool   // must it be a power of two?
}

@ 캐시 매개변수는 조금 더 어렵지만, 그래도 나쁘지 않다.

@<타입 정의@>=
type cParam int
@#
const (
	assoc cParam = iota
	blksz
	setsz
	gran
	vctsz
	wrb
	wra
	acctm
	citm
	cotm
	prts
)
@#
type cpvSpec struct {
	name           string // symbolic name
	v              cParam // internal code
	defval         int    // default value
	minval, maxval int    // minimum and maximum legal values
	powerOfTwo     bool   // must it be a power of two?
}

@ 연산 코드가 가장 쉽다.

@<타입 정의@>=
type opSpec struct {
	name   string // symbolic name
	v      int    // internal code
	defval int    // default value
}

@ 매개변수 대부분은 \.{mmixpipe}의 |machine| 필드다. 그러나 몇 개는 이 모듈만 쓴다. 여기서
아래에서 쓰는 주된 표들을 정의한다.

보충: 원본의 \PV\ 표는 전역 변수들의 주소를 담았다. 여기서는 기계의 필드와 |configReader|의
필드를 가리켜야 하므로, 표를 |MMIXConfig| 안에서 만든다. 원본은 |disablesecurity|의 값을 |bool|
변수 |security_disabled|에 |int|로 억지로 넣었다. 여기서는 |int| 필드에 받았다가 마지막에
옮긴다.

@<설정하는 동안의 다른 상태@>=
fetchBufSize, writeBufSize, reorderBufSize, memBusBytes, hardwarePT int
disableSecurity                                                    int
maxCycs                                                            int

@ @<\PV\ 표를 만든다@>=
mx.securityDisabled = false
pv := []pvSpec{
	{"fetchbuffer", &cf.fetchBufSize, 4, 1, intMax, false},
	{"writebuffer", &cf.writeBufSize, 2, 1, intMax, false},
	{"reorderbuffer", &cf.reorderBufSize, 5, 1, intMax, false},
	{"renameregs", &mx.maxRenameRegs, 5, 1, intMax, false},
	{"memslots", &mx.maxMemSlots, 2, 1, intMax, false},
	{"localregs", &mx.lringSize, 256, 256, 1024, true},
	{"fetchmax", &mx.fetchMax, 2, 1, intMax, false},
	{"dispatchmax", &mx.dispatchMax, 1, 1, intMax, false},
	{"peekahead", &mx.peekahead, 1, 0, intMax, false},
	{"commitmax", &mx.commitMax, 1, 1, intMax, false},
	{"fremmax", &mx.fremMax, 1, 1, intMax, false},
	{"denin", &mx.deninPenalty, 1, 0, intMax, false},
	{"denout", &mx.denoutPenalty, 1, 0, intMax, false},
	{"writeholdingtime", &mx.holdingTime, 0, 0, intMax, false},
	{"memaddresstime", &mx.memAddrTime, 20, 1, intMax, false},
	{"memreadtime", &mx.memReadTime, 20, 1, intMax, false},
	{"memwritetime", &mx.memWriteTime, 20, 1, intMax, false},
	{"membusbytes", &cf.memBusBytes, 8, 8, intMax, true},
	{"branchpredictbits", &mx.bpN, 0, 0, 8, false},
	{"branchaddressbits", &mx.bpA, 0, 0, 32, false},
	{"branchhistorybits", &mx.bpB, 0, 0, 32, false},
	{"branchdualbits", &mx.bpC, 0, 0, 32, false},
	{"hardwarepagetable", &cf.hardwarePT, 1, 0, 1, false},
	{"disablesecurity", &cf.disableSecurity, 0, 0, 1, false},
	{"memchunksmax", &mx.memChunksMax, 1000, 1, intMax, false},
	{"hashprime", &mx.hashPrime, 2003, 2, intMax, false}}

@ 원본의 \.{INT\_MAX}는 32비트 |int|의 가장 큰 값이다.

@<상수@>=
const intMax = 1<<31 - 1

@ @<표@>=
var cpv = []cpvSpec{
	{"associativity", assoc, 1, 1, intMax, true},
	{"blocksize", blksz, 8, 8, 8192, true},
	{"setsize", setsz, 1, 1, intMax, true},
	{"granularity", gran, 8, 8, 8192, true},
	{"victimsize", vctsz, 0, 0, intMax, true},
	{"writeback", wrb, 0, 0, 1, false},
	{"writeallocate", wra, 0, 0, 1, false},
	{"accesstime", acctm, 1, 1, intMax, false},
	{"copyintime", citm, 1, 1, intMax, false},
	{"copyouttime", cotm, 1, 1, intMax, false},
	{"ports", prts, 1, 1, intMax, false}}
@#
var opTable = []opSpec{
	{"mul0", mul0, 10}, {"mul1", mul1, 10}, {"mul2", mul2, 10},
	{"mul3", mul3, 10}, {"mul4", mul4, 10}, {"mul5", mul5, 10},
	{"mul6", mul6, 10}, {"mul7", mul7, 10}, {"mul8", mul8, 10},
	{"div", div, 60}, {"sh", sh, 1}, {"mux", mux, 1},
	{"sadd", sadd, 1}, {"mor", mor, 1}, {"fadd", fadd, 4},
	{"fmul", fmul, 4}, {"fdiv", fdiv, 40}, {"fsqrt", fsqrt, 40},
	{"fint", fint, 4}, {"fix", fix, 2}, {"flot", flot, 2},
	{"feps", feps, 4}}

@ 루틴 |newCache|는 기본값을 가진 |cache| 구조체를 만든다. (이 기본값들은 \CPV\ 표에서 읽지
않고 프로그램에 ``박혀'' 있다.)

보충: 원본은 메모리를 할당할 수 없으면 공황 메시지를 냈다. \GO/에서는 할당이 실패하지 않으므로
그런 검사를 모두 뺐다.
@.Can't allocate...@>

@<함수들@>=
func newCache(name string) *cache {
	c := new(cache)
	c.aa = 1 // default associativity, should equal |cpv[0].defval|
	c.bb = 8 // default blocksize
	c.cc = 1 // default setsize
	c.gg = 8 // default granularity
	c.vv = 0 // default victimsize
	c.repl = random // default replacement policy
	c.vrepl = random // default victim replacement policy
	c.mode = 0 // default mode is write-through and write-around
	c.accessTime, c.copyInTime, c.copyOutTime = 1, 1, 1
	c.filler.ctl = &c.fillerCtl
	c.fillerCtl.ptrA = c
	c.fillerCtl.goLoc.o = 4
	c.flusher.ctl = &c.flusherCtl
	c.flusherCtl.ptrA = c
	c.flusherCtl.goLoc.o = 4
	c.ports = 1
	c.name = name
	return c
}

@ @<기본값으로 초기화한다@>=
mx.ITcache = newCache("ITcache")
mx.DTcache = newCache("DTcache")
mx.Icache, mx.Dcache, mx.Scache = nil, nil, nil
for j = 0; j < len(pv); j++ {
	*pv[j].v = pv[j].defval
}
for j = 0; j < len(opTable); j++ {
	mx.pipeSeq[opTable[j].v][0] = byte(opTable[j].defval)
	mx.pipeSeq[opTable[j].v][1] = 0 // one stage
}

@* 명세 읽기. 설정 파일을 처리할 준비를 하기 전에, 기능 장치의 수를 세어서 공간을 얼마나 할당할지
알아야 한다.

늘 특별한 배경 장치를 하나 두어서, \.{TRAP}과 \.{TRIP} 명령을 누군가가 반드시 다루게 한다.

@<기능 장치를 세고 할당한다@>=
mx.funitCount = 0
for cf.token != "end" {
	cf.getToken()
	if cf.token == "unit" {
		mx.funitCount++
		cf.getToken() // a unit might be named \.{unit} or \.{end}
		cf.getToken()
	}
}
mx.funit = make([]funcUnit, mx.funitCount+1)
mx.funit[mx.funitCount].name = "%%"
@.\%\%@>
mx.funit[mx.funitCount].ops[0] = 0x80000000 // \.{TRAP}
mx.funit[mx.funitCount].ops[7] = 0x1        // \.{TRIP}

@ 이제 명세를 읽고 따를 수 있다. 이 프로그램은 잘못을 너그럽게 봐주려고 애쓰지 않고, 아주
효율적이려고 애쓰지도 않는다.

덧붙여, 명세를 뜻 있는 방식으로 줄마다 나눌 필요는 없다. 그냥 토큰 하나씩 읽는다.

보충: 원본의 |rewind|는 파일의 처음으로 돌아가고 파일 끝 표시를 지운다. 여기서는 |cfile|의
필드를 직접 되돌린다. 루틴 |getToken|의 버퍼는 그대로 남는다.

@<모든 명세를 기록한다@>=
cf.configFile.f.Seek(0, io.SeekStart)
cf.configFile.r.Reset(cf.configFile.f)
cf.configFile.pos, cf.configFile.eof = 0, false
mx.funitCount = 0
cf.token = ""
for cf.token != "end" {
	cf.getToken()
	if cf.token == "end" {
		break
	}
	@<|token|이 매개변수 이름이면 \PV\ 명세를 처리한다@>
	@<|token|이 캐시 이름이면 캐시 명세를 처리한다@>
	@<|token|이 연산 이름이면 파이프 명세를 처리한다@>
	if cf.token == "unit" {
		@<기능 명세를 처리한다@>
	}
	cf.configPanic("Configuration syntax error: Specification can't start with `%s'",
		cf.token)
@.Configuration syntax error...@>
}

@ @<|token|이 매개변수 이름이면...@>=
for j = 0; j < len(pv); j++ {
	if cf.token == pv[j].name {
		n = cf.getInt()
		if n < pv[j].minval {
			cf.configPanic("Configuration error: %s must be >= %d", pv[j].name, pv[j].minval)
@.Configuration error...@>
		}
		if n > pv[j].maxval {
			cf.configPanic("Configuration error: %s must be <= %d", pv[j].name, pv[j].maxval)
		}
		if pv[j].powerOfTwo && n&(n-1) != 0 {
			cf.configPanic("Configuration error: %s must be a power of 2", pv[j].name)
		}
		*pv[j].v = n
		break
	}
}
if j < len(pv) {
	continue
}

@ @<|token|이 캐시 이름이면...@>=
switch cf.token {
case "ITcache":
	cf.pcs(mx.ITcache)
	continue
case "DTcache":
	cf.pcs(mx.DTcache)
	continue
case "Icache":
	if mx.Icache == nil {
		mx.Icache = newCache("Icache")
	}
	cf.pcs(mx.Icache)
	continue
case "Dcache":
	if mx.Dcache == nil {
		mx.Dcache = newCache("Dcache")
	}
	cf.pcs(mx.Dcache)
	continue
case "Scache":
	if mx.Icache == nil {
		mx.Icache = newCache("Icache")
	}
	if mx.Dcache == nil {
		mx.Dcache = newCache("Dcache")
	}
	if mx.Scache == nil {
		mx.Scache = newCache("Scache")
	}
	cf.pcs(mx.Scache)
	continue
}

@ @<함수들@>=
func (cf *configReader) ppol(rr *replacePolicy) { // subroutine to scan for a replacement policy
	cf.getToken()
	switch cf.token {
	case "random":
		*rr = random
	case "serial":
		*rr = serial
	case "pseudolru":
		*rr = pseudoLRU
	case "lru":
		*rr = lru
	default:
		cf.tokenPrescanned = true // oops, we should rescan that token
	}
}

@ @<함수들@>=
func (cf *configReader) pcs(c *cache) { // subroutine to process a cache spec
	var j, n int
	cf.getToken()
	for j = 0; j < len(cpv); j++ {
		if cf.token == cpv[j].name {
			break
		}
	}
	if j == len(cpv) {
		cf.configPanic("Configuration syntax error: `%s' isn't a cache parameter name",
			cf.token)
@.Configuration syntax error...@>
	}
	n = cf.getInt()
	if n < cpv[j].minval {
		cf.configPanic("Configuration error: %s must be >= %d", cpv[j].name, cpv[j].minval)
@.Configuration error...@>
	}
	if n > cpv[j].maxval {
		cf.configPanic("Configuration error: %s must be <= %d", cpv[j].name, cpv[j].maxval)
	}
	if cpv[j].powerOfTwo && n&(n-1) != 0 {
		cf.configPanic("Configuration error: %s must be power of 2", cpv[j].name)
	}
	@<캐시 매개변수 |j|를 |n|으로 정한다@>
}

@ @<캐시 매개변수 |j|를...@>=
switch cpv[j].v {
case assoc:
	c.aa = n
	cf.ppol(&c.repl)
case blksz:
	c.bb = n
case setsz:
	c.cc = n
case gran:
	c.gg = n
case vctsz:
	c.vv = n
	cf.ppol(&c.vrepl)
case wrb:
	c.mode = c.mode&^writeBack + n*writeBack
case wra:
	c.mode = c.mode&^writeAlloc + n*writeAlloc
case acctm:
	cf.maxCycs = max(cf.maxCycs, n)
	c.accessTime = n
case citm:
	cf.maxCycs = max(cf.maxCycs, n)
	c.copyInTime = n
case cotm:
	cf.maxCycs = max(cf.maxCycs, n)
	c.copyOutTime = n
case prts:
	c.ports = n
}

@ 보충: 원본은 파이프라인 시간의 열 끝에 0을 쓰지 않는다. 그래서 같은 연산을 두 번 지정하면
앞 명세의 뒤 단계들이 남을 수 있다. 여기서도 그렇다.

@<|token|이 연산 이름이면...@>=
for j = 0; j < len(opTable); j++ {
	if cf.token == opTable[j].name {
		for i = 0; ; i++ {
			n = cf.getInt()
			if n < 0 {
				break
			}
			if n == 0 {
				cf.configPanic("Configuration error: Pipeline cycles must be positive")
@.Configuration error...@>
			}
			if n > 255 {
				cf.configPanic("Configuration error: Pipeline cycles must be <= 255")
			}
			cf.maxCycs = max(cf.maxCycs, n)
			if i >= pipeLimit {
				cf.configPanic("Configuration error: More than %d pipeline stages", pipeLimit)
			}
			mx.pipeSeq[opTable[j].v][i] = byte(n)
		}
		cf.tokenPrescanned = true
		break
	}
}
if j < len(opTable) {
	continue
}

@ @<기능 명세를...@>=
cf.getToken()
if len(cf.token) > 15 {
	cf.configPanic("Configuration error: `%s' is more than 15 characters long", cf.token)
@.Configuration error...@>
}
mx.funit[mx.funitCount].name = cf.token
cf.getToken()
if len(cf.token) != 64 {
	cf.configPanic("Configuration error: unit %s doesn't have 64 hex digit specs",
		mx.funit[mx.funitCount].name)
}
{
	var n Tetra
	for i, j = 0, 0; j < 64; j++ {
		switch t := cf.token[j]; {
		case t >= '0' && t <= '9':
			n = n<<4 + Tetra(t-'0')
		case t >= 'a' && t <= 'f':
			n = n<<4 + Tetra(t-'a'+10)
		case t >= 'A' && t <= 'F':
			n = n<<4 + Tetra(t-'A'+10)
		default:
			cf.configPanic("Configuration error: `%c' is not a hex digit", t)
		}
		if j&0x7 == 0x7 {
			mx.funit[mx.funitCount].ops[i] = n
			i, n = i+1, 0
		}
	}
}
mx.funitCount++
continue

@* 검사와 할당. 설정 파일의 데이터를 모두 받아들였다고 싸움이 끝난 것은 아니다. 아직 서로 다른
양들 사이의 상호 작용을 검사해야 하고, 캐시 블록과 코루틴 따위를 위한 공간을 할당해야 한다.

가장 어려운 일 가운데 하나는 기능 장치마다 필요한 파이프라인 단계의 최대 수를 정하는 것이다.
그것부터 맞붙어 보자.

보충: 원본은 장치의 코루틴들을 배열에 나란히 두어 |self+1|로 다음 단계를 얻었다. 여기서는 |succ|
필드를 정한다.

@<기능 장치마다 코루틴을 할당한다@>=
@<연산 코드마다 필요한 파이프라인 단계의 표를 만든다@>
for j = 0; j <= mx.funitCount; j++ {
	@<|funit[j]|에 필요한 단계의 수 |n|을 정한다@>
	u := &mx.funit[j]
	u.k = n
	u.co = make([]coroutine, n)
	for i = 0; i < n; i++ {
		u.co[i].name = u.name
		u.co[i].stage = i + 1
		if i+1 < n {
			u.co[i].succ = &u.co[i+1]
		}
	}
}

@ 보충: 원본의 |strlen(pipe_seq[j])|은 첫 0 바이트의 색인이다. 원본에서 |int_stages|와 |stages|는
전역 배열이었지만, 여기서만 쓰므로 |MMIXConfig|의 지역 변수다.

@<연산 코드마다 필요한 파이프라인 단계의 표를...@>=
for j = div; j <= maxPipeOp; j++ {
	intStages[j] = strlen(mx.pipeSeq[j][:])
}
for ; j <= maxRealCommand; j++ {
	intStages[j] = 1
}
for j, n = mul0, 0; j <= mul8; j++ {
	n = max(n, strlen(mx.pipeSeq[j][:]))
}
intStages[mul] = n
intStages[ld], intStages[st], intStages[frem] = 2, 2, 2
for j = 0; j < 256; j++ {
	stages[j] = intStages[intOp[j]]
}

@ 변환표 |intOp|는 |MMIX_run| 루틴의 |internalOp| 배열과 비슷하지만, |divu|를 |div|로, |fsub|를
|fadd|로 바꾸는 따위의 일을 한다.

@<표@>=
var intOp = [256]int{
	trap, fcmp, funeq, funeq, fadd, fix, fadd, fix,
	flot, flot, flot, flot, flot, flot, flot, flot,
	fmul, feps, feps, feps, fdiv, fsqrt, frem, fint,
	mul, mul, mul, mul, div, div, div, div,
	add, add, addu, addu, sub, sub, subu, subu,
	addu, addu, addu, addu, addu, addu, addu, addu,
	cmp, cmp, cmpu, cmpu, sub, sub, subu, subu,
	sh, sh, sh, sh, sh, sh, sh, sh,
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
	ld, ld, ld, ld, ld, ld, ld, ld,
	ld, ld, ld, ld, prego, prego, goOp, goOp,
	st, st, st, st, st, st, st, st,
	st, st, st, st, st, st, st, st,
	st, st, st, st, st, st, st, st,
	st, st, st, st, st, st, pushgo, pushgo,
	or, or, orn, orn, nor, nor, xor, xor,
	and, and, andn, andn, nand, nand, nxor, nxor,
	bdif, bdif, wdif, wdif, tdif, tdif, odif, odif,
	mux, mux, sadd, sadd, mor, mor, mor, mor,
	set, set, set, set, addu, addu, addu, addu,
	or, or, or, or, andn, andn, andn, andn,
	noop, noop, pushj, pushj, set, set, put, put,
	pop, resume, save, unsave, sync, noop, get, trip}

@ @<|funit[j]|에 필요한 단계의...@>=
for i, n = 0, 0; i < 256; i++ {
	if (mx.funit[j].ops[i>>5]<<(i&0x1f))&0x80000000 != 0 && stages[i] > n {
		n = stages[i]
	}
}
if n == 0 {
	cf.configPanic("Configuration error: unit %s doesn't do anything", mx.funit[j].name)
@.Configuration error...@>
}

@ 다음으로 어려운 일은 매개변수에 따라 정해지는 캐시 구조체의 필드들을 준비하는 것이다. 이를테면
|bb| 필드(블록 크기)에는 매개변수를 넣었지만, |b|~필드(블록 크기의 로그)도 계산해야 하고, 캐시 블록
자체도 만들어야 한다.

@<함수들@>=
func lg(n int) int { // compute binary logarithm
	l := 0
	for j := n; j != 0; j >>= 1 {
		l++
	}
	return l - 1
}

@ 보충: 원본은 메모리 할당에 실패하면 공황 메시지를 냈지만, 여기서는 그 검사를 뺐다.

@<함수들@>=
func (cf *configReader) allocCache(c *cache, name string) {
	if c.bb < c.gg {
		cf.configPanic("Configuration error: blocksize of %s is less than granularity", name)
@.Configuration error...@>
	}
	if name[1] == 'T' && c.bb != 8 {
		cf.configPanic("Configuration error: blocksize of %s must be 8", name)
	}
	c.a = lg(c.aa)
	c.b = lg(c.bb)
	c.c = lg(c.cc)
	c.g = lg(c.gg)
	c.v = lg(c.vv)
	c.tagmask = -(1 << (c.b + c.c))
	if c.a+c.b+c.c >= 32 {
		cf.configPanic("Configuration error: %s has >= 4 gigabytes of data", name)
	}
	if c.gg != 8 && c.mode&writeAlloc == 0 {
		cf.configPanic("Configuration error: %s does write-around with granularity %d",
			name, c.gg)
	}
	@<캐시 |c|의 캐시 집합들을 할당한다@>
	if c.vv != 0 {
		@<캐시 |c|의 희생자 캐시를 할당한다@>
	}
	c.inbuf = newBlock(c, 0)
	c.outbuf = newBlock(c, 0)
	if name[0] != 'S' {
		@<캐시 |c|의 읽기 코루틴들을 할당한다@>
	}
}

@ 보충: 캐시 블록 하나를 만드는 일은 여러 곳에서 하므로 함수로 둔다. 원본의 |calloc|처럼 태그는
0이다. 필드 |pos|는 집합 안의 위치다.

@<함수들@>=
func newBlock(c *cache, pos int) cacheblock {
	return cacheblock{dirty: make([]bool, c.bb>>c.g), data: make([]Octa, c.bb>>3), pos: pos}
}

@ @<캐시 |c|의 캐시 집합들을...@>=
c.set = make([]cacheset, c.cc)
for j := 0; j < c.cc; j++ {
	c.set[j] = make(cacheset, c.aa)
	for k := 0; k < c.aa; k++ {
		c.set[j][k] = newBlock(c, k)
		c.set[j][k].tag = sign32 << 32 // invalid tag
	}
}

@ @<캐시 |c|의 희생자 캐시를...@>=
c.victim = make(cacheset, c.vv)
for k := 0; k < c.vv; k++ {
	c.victim[k] = newBlock(c, k)
	c.victim[k].tag = sign32 << 32 // invalid tag
}

@ @<캐시 |c|의 읽기 코루틴들을...@>=
c.reader = make([]coroutine, c.ports)
for j := 0; j < c.ports; j++ {
	c.reader[j].stage = vanish
	switch {
	case name[0] == 'D' && name[1] == 'T':
		c.reader[j].name = "DTreader"
	case name[0] == 'D':
		c.reader[j].name = "Dreader"
	case name[1] == 'T':
		c.reader[j].name = "ITreader"
	default:
		c.reader[j].name = "Ireader"
	}
}

@ @<캐시들을 할당한다@>=
cf.allocCache(mx.ITcache, "ITcache")
mx.ITcache.filler.name, mx.ITcache.filler.stage = "ITfiller", fillFromVirt
cf.allocCache(mx.DTcache, "DTcache")
mx.DTcache.filler.name, mx.DTcache.filler.stage = "DTfiller", fillFromVirt
if mx.Icache != nil {
	cf.allocCache(mx.Icache, "Icache")
	mx.Icache.filler.name, mx.Icache.filler.stage = "Ifiller", fillFromMem
}
if mx.Dcache != nil {
	cf.allocCache(mx.Dcache, "Dcache")
	mx.Dcache.filler.name, mx.Dcache.filler.stage = "Dfiller", fillFromMem
	mx.Dcache.flusher.name, mx.Dcache.flusher.stage = "Dflusher", flushToMem
}
if mx.Scache != nil {
	@<S-캐시를 할당하고 1차 캐시와 맞는지 검사한다@>
}

@ @<S-캐시를 할당하고...@>=
cf.allocCache(mx.Scache, "Scache")
if mx.Scache.bb < mx.Icache.bb {
	cf.configPanic("Configuration error: Scache blocks smaller than Icache blocks")
@.Configuration error...@>
}
if mx.Scache.bb < mx.Dcache.bb {
	cf.configPanic("Configuration error: Scache blocks smaller than Dcache blocks")
}
if mx.Scache.gg != mx.Dcache.gg {
	cf.configPanic("Configuration error: Scache granularity differs from the Dcache")
}
mx.Icache.filler.stage = fillFromS
mx.Dcache.filler.stage = fillFromS
mx.Dcache.flusher.stage = flushToS
mx.Scache.filler.name, mx.Scache.filler.stage = "Sfiller", fillFromMem
mx.Scache.flusher.name, mx.Scache.flusher.stage = "Sflusher", flushToMem

@ 이제 거의 끝났다. 남은 중요한 일은 코루틴 스케줄을 위한 큐의 고리를 할당하는 것뿐이다. 그러려면
스케줄하는 쪽과 스케줄되는 쪽 사이에 생길 수 있는 가장 긴 기다림 시간을 알아야 한다.

@<스케줄 큐를 할당한다@>=
mx.busWords = cf.memBusBytes >> 3
j = max(mx.memReadTime, mx.memWriteTime)
n = 1
if mx.Scache != nil && mx.Scache.bb > n {
	n = mx.Scache.bb
}
if mx.Icache != nil && mx.Icache.bb > n {
	n = mx.Icache.bb
}
if mx.Dcache != nil && mx.Dcache.bb > n {
	n = mx.Dcache.bb
}
n = mx.memAddrTime + (n+cf.memBusBytes-1)/cf.memBusBytes*j
cf.maxCycs = max(cf.maxCycs, n) // now |maxCycs| bounds the waiting time
mx.ringSize = cf.maxCycs + 1
mx.ring = make([]coroutine, mx.ringSize)
for k := range mx.ring {
	mx.ring[k].name = "" // header nodes are nameless
	mx.ring[k].stage = maxStage
}

@ 보충: 원본은 버퍼들을 포인터로 할당했다. 여기서는 배열과 그 원소들의 |idx| 필드를 만들고,
재정렬 버퍼의 제어 블록마다 |link|를 부른다.

@<마지막 잔손질을 한다@>=
if mx.hashPrime <= mx.memChunksMax {
	cf.configPanic("Configuration error: hashprime must exceed memchunksmax")
@.Configuration error...@>
}
mx.memHash = make([]chunknode, mx.hashPrime+1)
mx.memHash[0].chunk = make([]Octa, 1<<13)
mx.memHash[mx.hashPrime].chunk = make([]Octa, 1<<13)
mx.memChunks = 1
mx.fetchBuf = make([]fetch, cf.fetchBufSize+1)
for k := range mx.fetchBuf {
	mx.fetchBuf[k].idx = k
}
mx.fetchBot, mx.fetchTop = &mx.fetchBuf[0], &mx.fetchBuf[cf.fetchBufSize]
mx.reorder = make([]control, cf.reorderBufSize+1)
for k := range mx.reorder {
	mx.reorder[k].idx = k
	mx.reorder[k].link()
}
mx.reorderBot, mx.reorderTop = &mx.reorder[0], &mx.reorder[cf.reorderBufSize]
mx.wbuf = make([]writeNode, cf.writeBufSize+1)
for k := range mx.wbuf {
	mx.wbuf[k].idx = k
}
mx.wbufBot, mx.wbufTop = &mx.wbuf[0], &mx.wbuf[cf.writeBufSize]
@<분기 예측 표를 할당한다@>
mx.l = make([]specnode, mx.lringSize)
j = mx.busWords
if mx.Icache != nil && mx.Icache.bb>>3 > j {
	j = mx.Icache.bb >> 3
}
mx.fetched = make([]Octa, j)
mx.dispatchStat = make([]int32, mx.dispatchMax+1)
mx.noHardwarePT = cf.hardwarePT == 0
mx.securityDisabled = cf.disableSecurity != 0

@ @<분기 예측 표를...@>=
if mx.bpN == 0 {
	mx.bpTable = nil
} else { // a branch prediction table is desired
	if mx.bpA+mx.bpB+mx.bpC >= 31 {
		cf.configPanic("Configuration error: Branch table has >= 2 gigabytes of data")
	}
	mx.bpTable = make([]int8, 1<<(mx.bpA+mx.bpB+mx.bpC))
}

@* 모두 합치기. 드디어 바라던 설정 서브루틴이다.

@<함수들@>=
func (mx *machine) MMIXConfig(filename string) {
	var i, j, n int
	var intStages [maxRealCommand + 1]int // stages as function of |internalOp|
	var stages [256]int                   // stages as function of opcode
	cf := &configReader{mx: mx, maxCycs: 60}
	cf.configFile = openCfile(filename)
	if cf.configFile == nil {
		cf.configPanic("Can't open configuration file %s", filename)
@.Can't open...@>
	}
	@<\PV\ 표를 만든다@>
	@<기본값으로 초기화한다@>
	@<기능 장치를 세고 할당한다@>
	@<모든 명세를 기록한다@>
	@<기능 장치마다 코루틴을 할당한다@>
	@<캐시들을 할당한다@>
	@<스케줄 큐를 할당한다@>
	@<마지막 잔손질을 한다@>
}

@* 찾아보기.
