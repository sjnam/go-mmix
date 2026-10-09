% 이 파일은 MMIXware의 mmix-arith.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

@s big.Int int
@s rand.Rand int
@s strings.Builder int
@s testing.T int

\input kotexgweb
\def\title{MMIXARITH}
\def\ff{\\{ff\kern-.05em}}

@* 들어가며. 아래의 서브루틴들은 64비트 \MMIX\ 산술을 구식 32비트 컴퓨터에서
흉내 내려고 만든 것이다. 1998년과 1999년, 크누스가 \MMIXAL과 최초의 \MMIX\
시뮬레이터들을 쓸 때 쓰던 컴퓨터가 바로 그런 기계였다. 모든 연산은 32비트
산술로 지어졌으며, IEEE 부동소수점 표준의 완전한 구현까지 포함한다. \CEE/
컴파일러에 32비트 부호 없는 정수 타입이 있다는 것 말고는 아무것도 가정하지 않았다.

크누스는 원본의 머리말에 이렇게 적었다. ``언젠가는 64비트 기계가 흔해질 것이고,
그러면 지금 이 프로그램의 어색한 조작들은 퍽 낡아 보일 것이다. 그런 컴퓨터를 가진
관심 있는 독자라면 이 코드를 순수한 64비트 형태로 어렵지 않게 바꿔서, 훨씬 빠르고
단순한 루틴을 얻을 수 있을 것이다. 그때까지는 미래를 흉내 내면서 계속 진보하기를
바랄 수밖에 없다.''

@ 이 문서가 바로 그 ``순수한 64비트 형태''다. 원본이 나온 지 사반세기가 지난 지금
64비트 기계는 흔한 정도가 아니라 당연한 것이 되었고, \GO/에는 64비트 부호 없는
정수 |uint64|와, 128비트 곱과 몫을 한 번에 내주는 표준 꾸러미 \.{math/bits}가 있다.
그래서 옮긴이는 옥타바이트를 두 테트라바이트의 구조체가 아니라 |uint64| 하나로
나타냈다. 그 결과 원본의 적잖은 서브루틴---덧셈, 뺄셈, 자리 옮김, 16비트 자리
단위의 곱셈과 나눗셈---이 \GO/ 연산자 하나나 표준 함수 호출 하나로 줄어들어
사라진다. 사라진 코드의 설명은 버리지 않고 제자리에 옮겨 두었다. 그것이 무엇을
하던 코드였는지, 64비트에서는 왜 필요 없어졌는지를 함께 적었다.

부동소수점 연산만은 사정이 다르다. 호스트 기계에도 IEEE 부동소수점 장치가 있지만,
\GO/는 반올림 방식을 바꾸는 방법도, 부정확·넘침·아래넘침 같은 예외 플래그를 읽는
방법도 주지 않는다. \MMIX은 이 둘을 모두 정확히 흉내 내야 하므로, 부동소수점은
원본처럼 정수 산술로 손수 짓는다. 다만 그 정수 산술이 이제 64비트라서 코드가 훨씬
짧아진다.

이 꾸러미는 \MMIX\ 시뮬레이터와 어셈블러에 함께 실어 쓰기 좋도록 단순한 구조를
가진다. 원본은 결과 몇 가지를 전역 변수(|aux|, |overflow|, |exceptions|, |val|,
|next_char|)로 돌려주고 현재 반올림 방식도 전역 변수 |cur_round|에서 읽었다.
\GO/에서는 함수가 값을 여러 개 돌려줄 수 있으므로, 이 전역 변수들을 모두 반환값과
매개변수로 바꾸었다. 이 꾸러미에는 바뀌는 전역 상태가 하나도 없으므로, 여러
시뮬레이터가 동시에 이 꾸러미를 불러도 서로 간섭하지 않는다.

@c
package mmixarith

import (
	"fmt"
	"math/bits"
	"strings"
)

@<타입 정의@>
@<상수@>
@<함수들@>

@ 원본에서 \KW{tetra} 타입의 정의는 ``필요하다면 부호 없는 32비트 정수를 나타내도록
고쳐야 하는'' 시스템 의존적인 부분이었다. \GO/ 명세는 |uint32|와 |uint64|의 크기를
못박아 두므로 이 걱정은 사라진다.

원본의 \KW{octa}는 테트라바이트 두 개 |h|(높은 쪽)와 |l|(낮은 쪽)을 묶은 구조체였다.
여기서는 |Octa|를 |uint64|의 새 타입이 아니라 {\it 별칭\/}으로 정의했다. 별칭으로
두면 \.{math/bits}의 함수들에 변환 없이 넘길 수 있고, 이 꾸러미를 쓰는 시뮬레이터도
|Octa|와 |uint64|를 자유롭게 섞어 쓸 수 있다. 원본에서 |x.h|라고 쓰던 것은 이제
|x>>32|이고, |x.l|이라고 쓰던 것은 |uint32(x)|다. 옮긴이는 원본의 상수를 옮길 때
이 대응을 여러 번 쓰게 된다. 예컨대 원본의 조건 |x.h>=0x400000|은 여기서
|x>=1<<54|가 된다. 곧 $\Hex{400000}=2^{22}$이고 높은 쪽 테트라바이트는 32비트만큼
위에 있으므로 $22+32=54$이기 때문이다.
@^system dependencies@>

@<타입 정의@>=
type Tetra = uint32 // tetrabyte: 32 bits
type Octa = uint64  // two tetrabytes make one octabyte

@ 원본의 전역 변수 |zero_octa|는 그냥 0이 되었다. 나머지 셋은 상수로 둔다.
원본의 |sign_bit|는 높은 쪽 테트라바이트의 부호 비트 \Hex{80000000}이었지만,
여기서는 옥타바이트 전체의 부호 비트다.

@<상수@>=
const (
	SignBit     Octa = 1 << 63            // the sign bit
	NegOne      Octa = ^Octa(0)           // $-1$, i.e., all 64 bits are 1
	InfOcta     Octa = 0x7ff0000000000000 // floating point $+\infty$
	StandardNaN Octa = 0x7ff8000000000000 // floating point NaN(.5)
)

@ 원본은 여기서 옥타바이트를 더하고 빼는 서브루틴 |oplus|와 |ominus|를 정의하고
``속도를 지나치게 걱정하지 않는다면 쉬운 일''이라고 적었다. 낮은 쪽 테트라바이트끼리
더한 결과가 더한 수보다 작아지면 올림이 생긴 것이므로 높은 쪽에 1을 더하고
(|if (x.l<y.l) x.h++|), 빼기에서는 반대로 내림을 처리한다. 뒤이은 서브루틴
|incr(y,delta)|는 부호 있는 테트라바이트 |delta|를 옥타바이트에 더했다.

\GO/에서는 이 셋이 모두 연산자 하나다: |y+z|, |y-z|, |y+Octa(delta)|. 부호 없는
정수의 덧셈과 뺄셈은 $2^{64}$을 법으로 감기므로(wrap around), 음수 |delta|를
|Octa|로 바꾸어 더해도 올바른 결과가 나온다. 그래서 이 세 서브루틴은 코드에서
사라졌다.

@ 원본은 이어서 ``왼쪽과 오른쪽 자리 옮김은 조금 더 어려울 뿐''이라며 |shift_left|와
|shift_right|를 정의했다. 이 서브루틴들이 32비트 이상 옮길 때 한 테트라바이트씩
통째로 옮기는 반복문을 따로 둔 것은, \CEE/에서 피연산자의 비트 수 이상으로 자리를
옮기는 것이 정의되지 않은 동작이기 때문이다.

\GO/ 명세는 이 경우도 정의해 둔다. 자리 옮김은 ``왼쪽 피연산자를 1비트씩 $n$번
옮긴 것처럼'' 동작하므로, |y<<64|는 0이고 부호 있는 수의 |x>>64|는 부호에 따라
0 아니면 $-1$이다. 그래서 왼쪽 옮김과 논리적 오른쪽 옮김은 연산자 |<<|와 |>>|로
충분하다. 산술적 오른쪽 옮김만은 부호 있는 타입을 한 번 거쳐야 하는데, 시뮬레이터와
어셈블러가 여러 곳에서 쓰므로 원본의 이름과 인자 순서를 살려 함수로 남긴다. 인자
|u|가 참이면 논리적(부호 없는) 옮김이고, 거짓이면 산술적 옮김이다. 원본은 $0\le
s\le64$를 요구했지만 이 함수는 음이 아닌 모든 |s|에 대해 옳게 동작한다.

@<함수들@>=
func ShiftRight(y Octa, s int, u bool) Octa {
	if u {
		return y >> s
	}
	return Octa(int64(y) >> s)
}

@* 곱셈. 우리는 부호 없는 64비트 정수 두 개를 곱해 부호 없는 128비트 곱을 얻어야
한다. 32비트 기계에서는 {\sl Seminumerical Algorithms\/}의 알고리즘 4.3.1M을
$b=2^{16}$으로 써서 이 일을 쉽게 할 수 있다. 원본의 서브루틴 |omult|는 두 수를
16비트짜리 자리 네 개씩으로 풀어 배열 |u|, |v|에 넣고, 초등학교에서 배운 곱셈을
그대로 해서 여덟 자리짜리 곱 |w|를 얻은 다음, 그 아래 절반을 돌려주고 위 절반은
전역 옥타바이트 |aux|에 넣었다. 자리를 16비트로 잡은 까닭은 16비트 수 두 개의 곱에
16비트 수 둘을 더해도 32비트를 넘지 않기 때문이다.
@^multiprecision multiplication@>

64비트 기계에는 64비트 수 두 개의 128비트 곱을 한 명령으로 내는 곱셈 회로가 있고,
\GO/의 |bits.Mul64|는 그 명령으로 번역된다. (그런 명령이 없는 기계에서는 |bits.Mul64|가
바로 위의 알고리즘을 $b=2^{32}$으로 실행한다.) 함수 호출 |bits.Mul64(y,z)|는 곱의 위 절반과
아래 절반을 차례로 돌려주므로, 원본의 |omult|와 전역 변수 |aux|는 필요 없어졌다.
이 꾸러미를 쓰는 쪽에서는 |bits.Mul64|를 바로 부르면 된다.

@ 부호 있는 곱셈의 아래 절반은 부호 없는 곱셈의 아래 절반과 같다. 부호 있는 위
절반은 많아야 두 번의 뺄셈을 더 해서 얻는다. 그렇게 얻은 위 절반이 아래 절반의
부호 비트를 64번 되풀이한 것과 다르면, 그리고 그때에만, 결과가 넘친 것이다.

뺄셈이 왜 필요한지 보충하자. 옥타바이트 |y|를 부호 있는 수로 읽으면, 부호 비트가
켜져 있을 때 그 값은 부호 없이 읽은 값보다 $2^{64}$만큼 작다. 따라서 $y<0$이면
부호 있는 곱은 부호 없는 곱보다 $2^{64}z$만큼 작고, 이는 곱의 위 절반에서 |z|를
빼는 것과 같다. 값이 $z<0$일 때도 마찬가지다. ($y$와 $z$가 둘 다 음수일 때 생기는 항
$2^{128}$은 128비트 밖으로 넘어가 버리므로 신경 쓰지 않아도 된다.)

원본은 32비트 위 절반 두 개가 부호 비트의 복사본인지를 교묘한 비트 연산으로
시험했다. 64비트에서는 아래 절반을 부호 있는 수로 보고 63비트 산술적 오른쪽
옮김을 하면 부호 비트 64개가 바로 나온다. 원본은 부호 있는 위 절반을 |aux|에 남겼지만
이 값을 쓰는 곳이 없으므로, 여기서는 아래 절반과 넘침 여부만 돌려준다.

@<함수들@>=
func SignedMult(y, z Octa) (x Octa, overflow bool) {
	hi, lo := bits.Mul64(y, z)
	if y&SignBit != 0 {
		hi -= z
	}
	if z&SignBit != 0 {
		hi -= y
	}
	return lo, hi != Octa(int64(lo)>>63)
}

@* 나눗셈. 부호 없는 128비트 정수를 부호 없는 64비트 정수로 나누는 긴 나눗셈은,
말할 것도 없이, \MMIX\ 산술에 필요한 루틴 가운데 가장 까다로운 것이다. 아래의
프로그램은 {\sl Seminumerical Algorithms\/}의 알고리즘 4.3.1D에 바탕을 두고,
옥타바이트 $x$, $y$, $z$가 주어졌을 때 $(2^{64}x+y)=qz+r$이고 $0\le r<z$인 옥타바이트
$q$와 $r$을 계산한다. 이때 $x<z$라고 가정한다. ($x\ge z$이면 그냥 $q=x$, $r=y$로 둔다.)
몫 $q$가 첫째 반환값이고, 나머지 $r$이 둘째 반환값이다. 원본은 나머지를 전역 변수
|aux|에 넣었다.
@^multiprecision division@>

원본은 이 계산을 16비트 자리로 했다. 피제수를 자리 여덟 개 |u|로, 제수를 자리 네 개
|v|로 풀고, 제수의 맨 윗자리가 $2^{15}$ 이상이 되도록 둘 다 |d|비트만큼 왼쪽으로
옮겨 정규화한다. 그런 다음 몫의 자리를 위에서부터 하나씩 구한다. 각 자리마다
피제수의 윗부분 두 자리를 제수의 맨 윗자리로 나누어 시험 몫 $\hat q$를 얻고, 제수의
둘째 자리까지 보고 $\hat q$가 너무 크면 줄인다. 그리고 $b^j\hat qv$를 |u|에서 빼고,
결과가 음수가 되었으면 $\hat q$를 1 줄이면서 |v|를 도로 더한다. 원본에 따르면 이
마지막 보정은 드물게만 일어나지만 꼭 필요할 때가 있다. 예컨대 \Hex{7fff800100000000}을
\Hex{800080020005}로 나눌 때 그렇다. 끝으로 나머지를 |d|비트만큼 도로 오른쪽으로
옮겨 정규화를 푼다.

64비트 기계에서는 |bits.Div64|가 이 일을 한다. 호스트 기계의 나눗셈 명령을 쓸 수
있으면 그것을 쓰고, 아니면 같은 알고리즘 D를 $b=2^{32}$으로 실행한다(\GO/의
구현은 {\sl Hacker's Delight\/}의 |divlu|를 따르는데, 그 뿌리가 바로 알고리즘 D다).
한 가지 조심할 점은 |bits.Div64|가 $x\ge z$일 때 ``몫이 넘친다''며 공황(panic)을
일으킨다는 것이다. 원본의 약속대로 이 경우에는 나누지 않고 $q=x$, $r=y$를 돌려준다.
제수가 $z=0$일 때도 $x\ge z$이므로 이 약속에 따라 공황 없이 처리된다.

@<함수들@>=
func Div(x, y, z Octa) (q, r Octa) {
	if x >= z {
		return x, y // trivial answer
	}
	return bits.Div64(x, y, z)
}

@ 부호 있는 나눗셈은 지루하지만 간단한 방법으로 부호 없는 나눗셈으로 바꿀 수 있다.
제수가 0이 아니라고 가정한다.

보충하자면, \MMIX의 \.{DIV}는 몫을 $-\infty$쪽으로 내림한다. 그래서 나머지는 늘
제수와 부호가 같거나 0이다. 두 수의 절댓값을 나눈 다음, 부호의 네 가지 조합에 따라
몫과 나머지를 고친다. 피제수가 음수이면 |sy=2|, 제수가 음수이면 |sz=1|로 두어,
|sy+sz|로 네 경우를 가른다.
\smallskip
\item{$\bullet$} 둘 다 음수이면 몫은 그대로이고 나머지만 부호를 바꾼다. 몫이
$2^{63}$이 되는 유일한 경우---$-2^{63}$을 $-1$로 나눌 때---가 넘침이다.
\item{$\bullet$} 둘 다 음이 아니면 고칠 것이 없다.
\item{$\bullet$} 부호가 다르면 참된 몫이 음수다. 나머지가 0이 아니면 내림 때문에
몫이 하나 더 작아진다. 나머지가 $r$이 아니라 $|zz|-r$(피제수가 음수일 때) 또는
$r-|zz|$(제수가 음수일 때)가 되고, 몫은 $-q$ 대신 $-q-1$이 된다. 원본은
$-q-1$을 |ominus(neg_one,q)|로 계산했는데, $-1-q$는 |q|의 모든 비트를 뒤집은 |^q|와
같다.
\smallskip\noindent
원본은 앞의 두 경우에서 \CEE/의 |switch| 문 안에서 다음 경우로 흘러내리기(fall
through)와 |goto negate_q|를 썼다. 여기서는 부호가 같은 두 경우에 바로 돌아가고,
부호가 다른 두 경우는 |switch| 뒤의 공통 꼬리에서 몫의 부호를 바꾼다.

@<함수들@>=
func SignedDiv(y, z Octa) (q, r Octa, overflow bool) {
	var yy, zz Octa
	var sy, sz int
	if y&SignBit != 0 {
		sy, yy = 2, -y
	} else {
		sy, yy = 0, y
	}
	if z&SignBit != 0 {
		sz, zz = 1, -z
	} else {
		sz, zz = 0, z
	}
	q, r = yy/zz, yy%zz
	switch sy + sz {
	case 2 + 1:
		return q, -r, q == SignBit
	case 0 + 0:
		return q, r, false
	case 2 + 0:
		if r != 0 {
			r = zz - r
		}
	case 0 + 1:
		if r != 0 {
			r -= zz
		}
	}
	@<몫의 부호를 바꾼다@>
}

@ 원본은 여기서 |odiv(zero_octa,yy,zz)|를 불렀다. 피제수의 위 절반이 0이므로 이것은
보통의 64비트 나눗셈이고, \GO/의 연산자 |/|와 |%|로 충분하다.

@<몫의 부호를 바꾼다@>=
if r != 0 {
	return ^q, r, false // $-q-1$
}
return -q, r, false

@* 비트 만지작거리기. \MMIX의 비트 연산자들은 직접 구현하기가 꽤 쉽지만, 그중 셋은
자주 나오므로 서브루틴으로 꾸릴 만하다.

원본은 이 절을 옥타바이트의 비트별 논리곱, 논리곱-부정, 배타적 논리합을 계산하는
서브루틴 |oand|, |oandn|, |oxor|로 시작했다. 원본에서는 높은 쪽과 낮은 쪽에 따로 연산을
해야 했지만, \GO/에서는 연산자 |&|, |&^|, |^| 하나씩이다. 연산자 |&^|(``그리고 아님'')가
\CEE/에는 없는 \GO/의 연산자로서 정확히 $y\land\bar z$를 계산한다는 것이 재미있다.

@ 원본은 이어서 한 테트라바이트 안의 1인 비트를 세는 ``재미있는 방법''을 보였다.
[이 고전적인 요령은 Wilkes, Wheeler, Gill의 {\sl The Preparation of Programs
for an Electronic Digital Computer\/} 제2판(Reading, Mass.:\ Addison--Wesley, 1957),
191--193쪽에서 ``옆으로 더하기(sideways addition)의 Gillies--Miller 방법''이라고
불린다. 여기 쓰인 요령 가운데 몇 가지는 Balbir Singh, Peter Rossmanith,
Stefan Schwoon이 제안했다.]
@^Gillies, Donald Bruce@>
@^Miller, Jeffrey Charles Percy@>
@^Wilkes, Maurice Vincent@>
@^Wheeler, David John@>
@^Gill, Stanley@>
@^Singh, Balbir@>
@^Rossmanith, Peter@>
@^Schwoon, Stefan@>

그 방법은 이렇다. 먼저 $x-((x\gg1)\land\Hex{55555555})$로 이웃한 두 비트마다 그 안의
1의 개수(0, 1, 2)를 2비트 칸에 모은다. 다음에
$(x\land\Hex{33333333})+((x\gg2)\land\Hex{33333333})$로 4비트 칸마다 모으고,
$(x+(x\gg4))\land\Hex{0f0f0f0f}$로 바이트마다 모은다. 마지막 두 걸음 $x+(x\gg8)$과
$x+(x\gg16)$에서 네 바이트의 합이 맨 아래 바이트에 쌓이므로, 거기서 \Hex{ff}로
걸러 내면 답이다. 칸 하나가 담는 수가 칸의 크기를 결코 넘지 않으므로, 한 번의
덧셈이 여러 칸을 동시에 병렬로 처리한다.

\GO/에서는 |bits.OnesCount64|가 이 일을 한다. 호스트에 비트 세기 명령(가령 \.{POPCNT})이
있으면 그것으로 번역되고, 없으면 바로 이 Gillies--Miller 방법을 64비트로 늘린 코드가
돈다. 그래서 원본의 |count_bits|는 여기서 사라졌다. \MMIX의 \.{SADD}를 흉내 내는
시뮬레이터는 |bits.OnesCount64(y&^z)|라고 쓰면 된다. 원본 시뮬레이터는 두
테트라바이트에 대해 따로 세어 더해야 했다.

@ 두 테트라바이트의 음이 아닌 바이트 차이(\MMIX의 \.{BDIF})를 계산하는 데에는
다음과 같은 20단계짜리 분기 없는 계산을 쓸 수 있다.

어떻게 되는지 보충하자. 짝수 번째 바이트들만 남긴 |y&0x00ff00ff|에 각 16비트 칸의
256 자리에 1을 더하는 \Hex{01000100}을 더하고, 같은 식으로 걸러 낸 |z|를 뺀다. 그러면
각 16비트 칸에는 $y_i+256-z_i$가 담긴다. 이 값은 1과 511 사이이므로 칸 사이로 빌림이
번지지 않는다. 칸의 256 비트는 $y_i\ge z_i$일 때, 그리고 그때에만 켜져 있다. 이
비트들만 모은 |m|에서 |m>>8|을 빼면, $y_i\ge z_i$인 칸에는 \Hex{ff}가, 아닌 칸에는 0이
생긴다. 이것으로 |d|를 거르면 짝수 번째 바이트들의 답 $\max(y_i-z_i,0)$이 나온다.
홀수 번째 바이트들은 8비트 오른쪽으로 옮겨 같은 일을 하고 도로 왼쪽으로 옮긴다.

64비트 기계의 좋은 점이 여기서 드러난다. 원본은 이 20단계를 옥타바이트의 두
절반에 한 번씩, 모두 40단계를 해야 했다. 위의 논증은 칸의 개수와 상관이 없으므로,
걸러 내는 상수를 64비트로 늘리면 같은 20단계로 여덟 바이트를 한꺼번에 처리한다.

@<함수들@>=
func ByteDiff(y, z Octa) Octa {
	d := (y & 0x00ff00ff00ff00ff) + 0x0100010001000100 - (z & 0x00ff00ff00ff00ff)
	m := d & 0x0100010001000100
	x := d & (m - (m >> 8))
	d = ((y >> 8) & 0x00ff00ff00ff00ff) + 0x0100010001000100 - ((z >> 8) & 0x00ff00ff00ff00ff)
	m = d & 0x0100010001000100
	return x + ((d & (m - (m >> 8))) << 8)
}

@ 두 테트라바이트의 음이 아닌 와이드 차이(\MMIX의 \.{WDIF})에는 다른 요령을 써서
15단계짜리 분기 없는 계산을 얻을 수 있다. (연구 문제: |count_bits|, |byte_diff|,
|wyde_diff|를 더 적은 연산으로 할 수 있을까?)
@^research problem@>

원본의 요령은 이렇다.
$$\vbox{\halign{\tt#\hfil\cr
a=((y>>16)-(z>>16))\&0x10000;\cr
b=((y\&0xffff)-(z\&0xffff))\&0x10000;\cr
return y-(z\^{}((y\^{}z)\&(b-a-(b>>16))));\cr}}$$
32비트 뺄셈에서 빌림이 생기면 16번 비트가 켜진다는 점을 이용해, |a|는 위 와이드가,
|b|는 아래 와이드가 $y_i<z_i$일 때 \Hex{10000}이 된다. 그러면 |b-a-(b>>16)|은
$y_i<z_i$인 와이드 자리에 \Hex{ffff}를 가진 마스크가 되고, 그 자리에서는 |z| 대신 |y|를
빼서 0을 얻는다.

옮긴이가 보충한다. 이 15단계 요령은 와이드가 딱 둘일 때만 통하므로, 64비트로
늘리려면 두 절반에 따로 적용해야 하고 그러면 30단계가 넘는다. 그런데 앞 절의
바이트 차이 요령은 칸의 폭과 상관이 없다. 16비트 와이드를 32비트 칸에 넣고
\Hex{0001000000010000}을 더해 같은 논증을 되풀이하면, 네 와이드 전부를 20단계에
처리할 수 있다. 64비트 기계에서는 이쪽이 낫다. 원본이 한 테트라바이트에 쓰던
15단계로 이제 옥타바이트 전체를 20단계에 처리하는 셈이다. 연구 문제는 여전히
열려 있다.

@<함수들@>=
func WydeDiff(y, z Octa) Octa {
	d := (y & 0x0000ffff0000ffff) + 0x0001000000010000 - (z & 0x0000ffff0000ffff)
	m := d & 0x0001000000010000
	x := d & (m - (m >> 16))
	d = ((y >> 16) & 0x0000ffff0000ffff) + 0x0001000000010000 - ((z >> 16) & 0x0000ffff0000ffff)
	m = d & 0x0001000000010000
	return x + ((d & (m - (m >> 16))) << 16)
}

@ 마지막으로 필요한 비트 서브루틴이 가장 흥미롭다. 이것은 \MMIX의 \.{MOR}와 \.{MXOR}
연산을 구현한다. 인자 |xor|가 참이면 논리합 대신 배타적 논리합을 쓴다.

보충하자면, 이 연산은 옥타바이트를 $8\times8$ 비트 행렬로 보고 두 행렬을 곱하는
것이다. 곱의 바이트 $j$는, |z|의 바이트 $j$에서 비트 $k$가 켜진 모든 $k$에 대해
|y|의 바이트 $k$를 논리합(또는 배타적 논리합)한 것이다. 루프는 |y|의 바이트를 아래에서부터
하나씩 |o&0xff|로 꺼낸다. 그 바이트가 0이 아니면, |z|의 각 바이트에서 비트 $k$를
골라 \Hex{ff}나 0으로 불린 마스크 |a|를 만든다. 비트를 하나씩 떼어 낸
|(z>>k)&0x0101010101010101|에 \Hex{ff}를 곱하면, 각 바이트의 1이 올림 없이 \Hex{ff}로
불어난다. 한편 꺼낸 바이트를 여덟 번 되풀이한 |c|를 만든다. 그러면 |a&c|가 이 $k$가
곱에 보태는 몫이다. 나머지 |o|에 0이 아닌 비트가 남지 않으면 루프는 일찍 끝난다.

원본은 높은 쪽과 낮은 쪽 테트라바이트에 대해 |a|와 |b|를 따로 만들어야 했지만,
64비트에서는 마스크 하나로 끝난다.

@<함수들@>=
func BoolMult(y, z Octa, xor bool) Octa {
	var x Octa
	for k, o := 0, y; o != 0; k, o = k+1, o>>8 {
		if o&0xff != 0 {
			a := ((z >> k) & 0x0101010101010101) * 0xff
			c := (o & 0xff) * 0x0101010101010101
			if xor {
				x ^= a & c
			} else {
				x |= a & c
			}
		}
	}
	return x
}

@* 부동소수점 수의 포장과 풀기. 표준 IEEE 부동 이진수는 부호, 지수, 소수 부분을
테트라바이트나 옥타바이트 하나에 담는다. 이 장에서는 IEEE 형식과, 따로 떨어진
성분들 사이를 오가는 기본 서브루틴들을 다룬다.

반올림 방식은 넷이다. 원본은 이것을 매크로 \.{ROUND\_OFF}, \.{ROUND\_UP}, \.{ROUND\_DOWN},
\.{ROUND\_NEAR}로 정의했다. 번호 1--4는 \MMIX\ 명령어의 $Y$ 필드와 특수 레지스터
\.{rA}에 그대로 쓰이는 값이므로 바꾸면 안 된다. 원본의 전역 변수 |cur_round|는 이
꾸러미에 없다. 반올림 방식이 필요한 함수는 그것을 매개변수 |r|로 받는다.

보충: 원본의 몇몇 함수(|fintegerize|, |fixit|, |floatit|, |froot|)는 |r=0|을 받으면
``현재 반올림 방식''을 쓰라는 뜻으로 알아들었다. \MMIX\ 명령의 $Y$ 필드가 0이면
그런 뜻이기 때문이다. 이 꾸러미에는 ``현재'' 방식이 없으므로, 그 풀이는 부르는
쪽(시뮬레이터)이 해서 넘겨주어야 한다.

@<타입 정의@>=
type Round int // rounding mode

@ @<상수@>=
const (
	RoundOff  Round = 1 // round toward zero
	RoundUp   Round = 2 // round toward $+\infty$
	RoundDown Round = 3 // round toward $-\infty$
	RoundNear Round = 4 // round to nearest, ties to even
)

@ 서브루틴 |fpack|은 옥타바이트 $f$, 날(raw) 지수~$e$, 부호~|s|를 받아서, 주어진
반올림 방식으로 $\pm2^{e-1076}f$에 해당하는 부동 이진수로 포장한다. 값 $f$는
$2^{54}\le f\le 2^{55}$을 만족해야 한다. 부호는 원본에서 문자 |'+'|나 |'-'|였지만,
여기서는 음수일 때 참인 |bool|이다.

예를 들어 부동 이진수 $+1.0=\Hex{3ff0000000000000}$은 $f=2^{54}$, $e=\Hex{3fe}$, 부호가
|'+'|일 때 얻어진다. 날 지수~$e$는 대개 최종 지수 값보다 하나 작다. 소수 부분 $f$의 맨 앞 비트가
사실상 지수에 더해지기 때문이다. (이 요령은 $e<0$인 비정규수(subnormal)의 경우에도,
$f$가 $2^{55}$으로 올림되는 경우에도 멋지게 통한다.)

보충하자면, $f$는 소수점 아래 54비트를 가진 고정소수점 수 $1.xxx$로 볼 수 있다.
IEEE 배정밀도의 소수 부분 52비트 밑에 두 비트가 더 있는 셈인데, 이 두 비트가
반올림에 쓰인다. 반올림을 마친 뒤 두 비트를 오른쪽으로 버리면 맨 앞의 1이
$2^{52}$ 자리, 곧 지수 필드의 맨 아래 비트에 떨어진다. 그래서 지수 필드에 $e$를
더하면 $e+1$이 된다. 반올림 때문에 $f$가 $2^{55}$이 되면 맨 앞의 1이 한 자리 위에
떨어져 지수가 저절로 하나 더 올라간다. 비정규수는 지수 필드가 0이고 맨 앞 비트가
없으므로 $e=0$으로 두면 된다.

예외적인 사건들은 적절한 비트를 예외 값에 논리합하여 기록한다. 원본은 이 비트들을
전역 변수 |exceptions|에 모았지만, 여기서는 함수마다 둘째 반환값 |exc|로 돌려준다.
아래넘침(underflow)에는 특별한 고려가 필요한데, IEEE 표준의 7.4절이 그것을 완전히
규정하지 않기 때문이다. 표준을 구현하는 쪽은 ``작음(tininess)''의 두 가지 정의와
``정확도 손실(accuracy loss)''의 두 가지 정의 가운데 고를 수 있다. \MMIX은 작음을
반올림 {\it 뒤에\/} 판정하므로, $e<0$인 결과라고 해서 반드시 작은 것은 아니다. 또
\MMIX은 정확도 손실을 부정확(inexact)과 같은 것으로 본다. 그래서 결과가 작고 또
(i)~부정확하거나 (ii)~아래넘침 트랩이 켜져 있을 때, 그리고 그때에만 아래넘침이
일어난다. 서브루틴 |fpack|은 결과가 작을 때, 그리고 그때에만 |UBit|을 켜고, 결과가
부정확할 때, 그리고 그때에만 |XBit|을 켠다.
@^underflow@>
@^tininess@>
@^accuracy loss@>

@<상수@>=
const (
	XBit = 1 << 8  // floating inexact
	ZBit = 1 << 9  // floating division by zero
	UBit = 1 << 10 // floating underflow
	OBit = 1 << 11 // floating overflow
	IBit = 1 << 12 // floating invalid operation
	WBit = 1 << 13 // float-to-fix overflow
	VBit = 1 << 14 // integer overflow
	DBit = 1 << 15 // integer divide check
	EBit = 1 << 18 // external (dynamic) trap bit
)

@ 지수가 음수이면 $f$를 $-e$비트만큼 오른쪽으로 옮겨 비정규수를 만든다. 그때 떨어져
나가는 비트 가운데 0이 아닌 것이 있으면 맨 아래 비트를 켜 둔다. 이것이 ``끈끈이
비트(sticky bit)''다. 이 비트 덕분에, 버려진 부분이 정확히 절반인지 절반보다 큰지를
반올림 단계에서 구별할 수 있다. 지수가 $-54$보다 작으면 모든 비트가 떨어져 나가므로
끈끈이 비트만 남긴다.
@^sticky bit@>

@<함수들@>=
func fpack(f Octa, e int, s bool, r Round) (o Octa, exc int) {
	if e > 0x7fd {
		e, o = 0x7ff, 0
	} else {
		if e < 0 {
			if e < -54 {
				o = 1
			} else {
				o = f >> -e
				if o<<-e != f {
					o |= 1 // sticky bit
				}
			}
			e = 0
		} else {
			o = f
		}
	}
	@<반올림하고 결과를 돌려준다@>
}

@ 여기서는 모든 것이 너무나 멋지게 맞아떨어져서, 믿기 어려울 정도다!

보충: 반올림 전의 |o|는 맨 아래에 두 비트---참된 다음 비트와 끈끈이 비트---를 더
가지고 있다. 이 두 비트가 0이 아니면 결과는 부정확하다. 버림(|RoundOff|)은 두 비트를
그냥 버리면 된다. 음수를 $-\infty$ 쪽으로, 또는 양수를 $+\infty$ 쪽으로 반올림할 때는
3을 더한 뒤 버리면, 두 비트 중 어느 하나라도 켜져 있을 때 올림이 생긴다. 가까운
쪽으로 반올림할 때는, 남길 맨 아래 비트(4의 자리)가 1이면 2를, 0이면 1을 더한다.
그러면 두 비트가 \.{10}(정확히 절반)일 때 결과가 홀수이면 올라가고 짝수이면 그대로
있게 되어 짝수 쪽 규칙이 저절로 지켜진다. 원본의 \CEE/ 코드는 \.{ROUND\_UP}에서
\.{ROUND\_OFF}로 흘러내렸는데, \.{ROUND\_OFF} 쪽은 아무 일도 하지 않으므로 여기서는
흘러내리기가 필요 없다.

지수가 너무 커서 $e=\Hex{7ff}$로 둔 경우에는 |o|가 0이므로 결과는 $\pm\infty$이고,
넘침과 부정확이 함께 기록된다. 결과의 지수 필드가 0이면, 곧 결과가 $2^{52}$보다
작으면 작음이 기록된다.

@<반올림하고 결과를 돌려준다@>=
if o&3 != 0 {
	exc |= XBit
}
switch r {
case RoundDown:
	if s {
		o += 3
	}
case RoundUp:
	if !s {
		o += 3
	}
case RoundNear:
	if o&4 != 0 {
		o += 2
	} else {
		o++
	}
}
o >>= 2
o += Octa(e) << 52
if o >= 0x7ff0000000000000 {
	exc |= OBit | XBit // overflow
} else if o < 1<<52 {
	exc |= UBit // tininess
}
if s {
	o |= SignBit
}
return

@ 마찬가지로 |sfpack|은 |fpack|과 같은 규약을 따르는 입력으로부터 짧은 부동소수점
수(단정밀도)를 포장한다.

보충하자면, 짧은 부동소수점 수는 부호 1비트, 지수 8비트, 소수 23비트로 이루어지고
지수의 치우침(bias)이 127이다. 배정밀도의 치우침은 1023이므로 둘 사이의 날 지수는
$1023-127=896=\Hex{380}$만큼 차이 난다. 그래서 짧은 수의 지수 필드가 0(비정규)이 되는
경계가 날 지수 \Hex{380}이고, 넘침의 경계가 $\Hex{380}+\Hex{fd}=\Hex{47d}$다. 소수 부분 $f$를
3비트 왼쪽으로 옮긴 높은 쪽 테트라바이트는 $f$의 맨 위 32비트---맨 앞 비트 하나, 소수
23비트, 반올림용 두 비트, 그리고 여분 여섯 비트---이다. 그 아래로 떨어져 나가는
29비트는 끈끈이 비트로 접어 넣는다.

@<함수들@>=
func sfpack(f Octa, e int, s bool, r Round) (o Tetra, exc int) {
	if e > 0x47d {
		e, o = 0x47f, 0
	} else {
		o = Tetra((f << 3) >> 32)
		if f&0x1fffffff != 0 {
			o |= 1
		}
		if e < 0x380 {
			if e < 0x380-25 {
				o = 1
			} else {
				o0 := o
				o >>= 0x380 - e
				if o<<(0x380-e) != o0 {
					o |= 1 // sticky bit
				}
			}
			e = 0x380
		}
	}
	@<반올림하고 짧은 결과를 돌려준다@>
}

@ 짧은 결과의 반올림은 긴 결과의 반올림과 똑같다. 짧은 수에서 지수 필드가 0인 것,
곧 결과가 작은 것은 결과가 \Hex{800000}보다 작을 때다.

보충: 이 경계에는 사연이 있다. 옮긴이가 처음 옮긴 원본은 2013년판이었는데, 거기서는
이 비교가 긴 수의 경계와 같은 \Hex{100000}이었다. 그래서 짧은 비정규수 가운데
\Hex{100000} 이상 \Hex{800000} 미만인 것들, 예컨대 $2^{-127}$(짧은 수로
\Hex{00400000})은 작다고 기록되지 않았다. 뒤의 시험을 쓰다가 이 점을 알아채고 크누스의
웹 페이지에서 최신판을 받아 보니, 크누스는 이미 경계를 \Hex{800000}으로 고쳐 두었다.
이 번역은 최신판을 따른다.

@<반올림하고 짧은 결과를 돌려준다@>=
if o&3 != 0 {
	exc |= XBit
}
switch r {
case RoundDown:
	if s {
		o += 3
	}
case RoundUp:
	if !s {
		o += 3
	}
case RoundNear:
	if o&4 != 0 {
		o += 2
	} else {
		o++
	}
}
o >>= 2
o += Tetra(e-0x380) << 23
if o >= 0x7f800000 {
	exc |= OBit | XBit // overflow
} else if o < 0x800000 {
	exc |= UBit // tininess
}
if s {
	o |= 1 << 31
}
return

@ 서브루틴 |funpack|은 대략 말해 |fpack|의 반대다. 주어진 부동소수점 수~$x$를 받아
소수 부분~$f$, 지수~$e$, 부호~$s$로 가른다. 원본은 이때 |exceptions|를 0으로 지웠다.
여기서는 예외가 반환값이므로 그럴 필요가 없다. 원본이 부른 쪽의 변수 주소를 받아
값을 써 넣던 것도, \GO/에서는 여러 반환값으로 바뀌었다.

이 함수는 찾아낸 값의 종류를 돌려준다: |zro|(0), |num|(0이 아닌 유한한 수), |inf|(무한대),
|nan|(NaN). 종류가 |num|일 때는, |fpack|이 예외 없이 원래의 수~$x$를 다시 만들어 낼
$f$, $e$, $s$ 값을 준다. 0에는 지수 $-1000$을 준다.

@<타입 정의@>=
type ftype int // kind of floating point value

@ @<상수@>=
const (
	zro ftype = iota // 0
	num              // a nonzero finite number
	inf              // infinity
	nan              // NaN
)

const zeroExponent = -1000 // zero is assumed to have this exponent

@ 보충하자면, $x$를 두 비트 왼쪽으로 옮기고 아래 54비트만 남기면 소수 필드 52비트가
$f$의 $2^{2}$ 자리부터 $2^{53}$ 자리에 놓이고, 맨 아래 두 비트는 반올림용 0이 된다.
지수 필드가 0이 아니면 숨은 비트 $2^{54}$을 켜고, 날 지수는 지수 필드보다 하나 작다.
지수 필드가 0이면 0이거나 비정규수다. 비정규수는 맨 앞의 1이 $2^{54}$ 자리에 올 때까지
왼쪽으로 옮기면서 지수를 줄인다. 그렇게 해서 비정규수의 지수는 음수가 될 수 있다.

@<함수들@>=
func funpack(x Octa) (t ftype, f Octa, e int, s bool) {
	s = x&SignBit != 0
	f = (x << 2) & (1<<54 - 1)
	ee := int(x>>52) & 0x7ff
	if ee != 0 {
		e = ee - 1
		f |= 1 << 54
		switch {
		case ee < 0x7ff:
			t = num
		case f == 1<<54:
			t = inf
		default:
			t = nan
		}
		return
	}
	if f == 0 {
		return zro, f, zeroExponent, s
	}
	for {
		ee--
		f <<= 1
		if f&(1<<54) != 0 {
			break
		}
	}
	return num, f, ee, s
}

@ 짧은 수를 푸는 |sfunpack|도 마찬가지다. 짧은 수의 소수 23비트는 $f$의 $2^{31}$
자리부터 $2^{53}$ 자리에 놓이고, 날 지수에는 앞에서 말한 차이 \Hex{380}을 더한다.

@<함수들@>=
func sfunpack(x Tetra) (t ftype, f Octa, e int, s bool) {
	s = x&(1<<31) != 0
	f = (Octa(x) << 31) & (1<<54 - 1)
	ee := int(x>>23) & 0xff
	if ee != 0 {
		e = ee + 0x380 - 1
		f |= 1 << 54
		switch {
		case ee < 0xff:
			t = num
		case x&0x7fffffff == 0x7f800000:
			t = inf
		default:
			t = nan
		}
		return
	}
	if x&0x7fffffff == 0 {
		return zro, f, zeroExponent, s
	}
	for {
		ee--
		f <<= 1
		if f&(1<<54) != 0 {
			break
		}
	}
	return num, f, ee + 0x380, s
}

@ \MMIX은 32비트 연산을 대수롭지 않게 여기므로, |sfpack|과 |sfunpack|은 짧은
부동소수점 수를 적재하고 저장할 때나 고정소수점을 부동소수점으로 바꿀 때만 쓴다.

짧은 수를 긴 수로 적재하는 일은 늘 정확하다. 짧은 수가 나타내는 모든 값이 긴
수로 정확히 나타나기 때문이다. 원본의 |load_sf|도 예외를 기록하지 않았으므로(|fpack|을
부르기는 하지만 그 결과는 결코 부정확하거나 작지 않다), 여기서는 예외를 돌려주지
않는다. NaN은 소수 부분을 그대로 가지고 오되, 신호용(signaling) NaN도 조용한 NaN으로
바꾸지 않는다.

@<함수들@>=
func LoadSF(z Tetra) Octa {
	t, f, e, s := sfunpack(z)
	var x Octa
	switch t {
	case zro:
		x = 0
	case num:
		x, _ := fpack(f, e, s, RoundOff)
		return x
	case inf:
		x = InfOcta
	case nan:
		x = f>>2 | 0x7ff0000000000000
	}
	if s {
		x |= SignBit
	}
	return x
}

@ 긴 수를 짧은 수로 저장할 때는 반올림이 필요하다. NaN의 경우, 소수 부분의 맨 앞
비트(여기서는 $2^{53}$ 자리)가 꺼져 있으면 그 NaN은 신호용이었으므로, 그 비트를 켜서
조용하게 만들고 잘못된 연산 예외를 기록한다. 그런 다음 소수 부분의 위쪽 비트들을
짧은 NaN의 소수 필드로 옮긴다. 원본은 이것을 |(f.h<<1)|$\,\mid\,$|(f.l>>31)|로 계산했는데,
이는 |f>>31|의 아래 32비트와 같다.

@<함수들@>=
func StoreSF(x Octa, r Round) (z Tetra, exc int) {
	t, f, e, s := funpack(x)
	switch t {
	case zro:
		z = 0
	case num:
		return sfpack(f, e, s, r)
	case inf:
		z = 0x7f800000
	case nan:
		if f&(1<<53) == 0 {
			f |= 1 << 53
			exc |= IBit // NaN was signaling
		}
		z = 0x7f800000 | Tetra(f>>31)
	}
	if s {
		z |= 1 << 31
	}
	return
}

@* 부동소수점 곱셈과 나눗셈. 고정소수점 연산 가운데 가장 어려운 것은 곱셈과
나눗셈이었다. 그러나 고정소수점 곱셈과 나눗셈이 일단 마련되고 나면, 이 두 연산은
부동소수점 산술에서 {\it 가장 쉬운\/} 연산이 된다.

두 수를 푼 다음에는 두 종류의 조합에 따라 경우를 나눈다. 종류가 넷이므로 |4*yt+zt|로
열여섯 가지 경우를 한 |switch| 문에서 가른다. 결과의 부호는 두 부호가 다를 때
음수다. 원본은 문자 부호로 이것을 |xs=ys+zs-'+'|라는 재치 있는 식으로 계산했다.
(|'+'+'+'-'+'|는 |'+'|이고 |'+'+'-'-'+'|는 |'-'|이지만, |'-'+'-'-'+'|가 |'+'|가 되는 것은
\.{ASCII}에서 |'+'|와 |'-'|의 코드가 43과 45로 2만큼 떨어져 있기 때문이다.) 부호가
|bool|인 여기서는 그냥 |ys!=zs|다.

@<함수들@>=
func FMult(y, z Octa, r Round) (x Octa, exc int) {
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, zs := funpack(z)
	xs := ys != zs
	switch 4*yt + zt {
	@<흔한 NaN 경우들@>
	case 4*zro + zro, 4*zro + num, 4*num + zro:
		x = 0
	case 4*num + inf, 4*inf + num, 4*inf + inf:
		x = InfOcta
	case 4*zro + inf, 4*inf + zro:
		x = StandardNaN
		exc |= IBit
	case 4*num + num:
		@<0이 아닌 두 수를 곱하고 돌려준다@>
	}
	if xs {
		x |= SignBit
	}
	return
}

@ 피연산자에 NaN이 있으면 결과도 NaN이다. 두 피연산자가 모두 NaN이면 |z|가 이긴다.
NaN이 신호용이면(소수 부분의 맨 앞 비트, 곧 비트 51이 꺼져 있으면) 잘못된 연산 예외를
기록하고, 결과로는 그 비트를 켠 조용한 NaN을 돌려준다. 이 경우들은 여러 연산에
공통이므로 이름 있는 절로 두고 여러 |switch| 문에 끼워 넣는다.

원본은 첫 경우에서 둘째 경우로 흘러내렸다. \GO/의 |switch|는 저절로 흘러내리지
않으므로 |fallthrough|라고 분명히 적어야 한다.

@<흔한 NaN 경우들@>=
case 4*nan + nan:
	if y&(1<<51) == 0 {
		exc |= IBit // |y| is signaling
	}
	fallthrough
case 4*zro + nan, 4*num + nan, 4*inf + nan:
	if z&(1<<51) == 0 {
		exc |= IBit
		z |= 1 << 51
	}
	return z, exc
case 4*nan + zro, 4*nan + num, 4*nan + inf:
	if y&(1<<51) == 0 {
		exc |= IBit
		y |= 1 << 51
	}
	return y, exc

@ 두 소수 부분은 $[2^{54}\dts2^{55})$에 있다. 소수 부분 |zf|를 9비트 왼쪽으로 옮겨 곱하면
128비트 곱의 위 절반이 $[2^{53}\dts2^{55})$에 떨어진다. 위 절반이 $2^{54}$보다 작으면
한 비트 왼쪽으로 옮겨 정규화하고 지수를 하나 줄인다. 아래 절반은 끈끈이 비트로
접어 넣는다.

보충: 날 지수가 어떻게 나오는지 보자. 두 수는 $y=2^{ye-1076}yf$이고 $z=2^{ze-1076}zf$이므로
곱은 $2^{ye+ze-2152}\,yf\,zf$이다. 위 절반은 곱을 $2^{64}$으로 나누고 9비트 옮긴 것을
되돌린 것이므로, $yf\cdot zf=2^{55}\cdot|aux|$다. 따라서 곱은
$2^{ye+ze-2152+55}\,|aux|=2^{(ye+ze-0x3fd)-1076}\,|aux|$이고, $2152-55-1076=1021=\Hex{3fd}$다.

@<0이 아닌 두 수를 곱하고 돌려준다@>=
xe := ye + ze - 0x3fd // the raw exponent
aux, lo := bits.Mul64(yf, zf<<9)
var xf Octa
if aux >= 1<<54 {
	xf = aux
} else {
	xf = aux << 1
	xe--
}
if lo != 0 {
	xf |= 1 // adjust the sticky bit
}
return fpack(xf, xe, xs, r)

@ 나눗셈도 같은 틀이다. 0이 아닌 수를 0으로 나누면 0으로 나눔 예외를 기록하고
무한대를 낸다. 연산 $0/0$과 $\infty/\infty$는 잘못된 연산이다.

@<함수들@>=
func FDivide(y, z Octa, r Round) (x Octa, exc int) {
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, zs := funpack(z)
	xs := ys != zs
	switch 4*yt + zt {
	@<흔한 NaN 경우들@>
	case 4*zro + inf, 4*zro + num, 4*num + inf:
		x = 0
	case 4*num + zro:
		exc |= ZBit
		fallthrough
	case 4*inf + num, 4*inf + zro:
		x = InfOcta
	case 4*zro + zro, 4*inf + inf:
		x = StandardNaN
		exc |= IBit
	case 4*num + num:
		@<0이 아닌 두 수를 나누고 돌려준다@>
	}
	if xs {
		x |= SignBit
	}
	return
}

@ 피제수 $2^{64}yf$를 $2^9zf$로 나눈다. 부등식 $yf<2^{55}\le2^{63}\le2^9zf$이므로 |Div|의
전제 $x<z$가 늘 성립한다. 몫은 $[2^{54}\dts2^{56})$에 있으므로, $2^{55}$ 이상이면
한 비트 오른쪽으로 옮기되 떨어지는 비트를 나머지에 접어 넣고 지수를 하나 올린다.
나머지가 0이 아니면 끈끈이 비트를 켠다.

@<0이 아닌 두 수를 나누고 돌려준다@>=
xe := ye - ze + 0x3fd // the raw exponent
xf, aux := Div(yf, 0, zf<<9)
if xf >= 1<<55 {
	aux |= xf & 1
	xf >>= 1
	xe++
}
if aux != 0 {
	xf |= 1 // adjust the sticky bit
}
return fpack(xf, xe, xs, r)

@*부동소수점 덧셈과 뺄셈. 이제 늘 쓰는 밥과 빵 같은 연산, 부동소수점 수 두 개의
합이다. 몹시 어렵지는 않지만, 많은 경우를 조심스럽게 다루어야 한다.

한쪽이 0이면 다른 쪽을 그대로 내면 될 것 같지만, 원본은 이때도 |fpack|을 거친다.
결과가 비정규수이면 아래넘침이 일어날 수 있기 때문이다. 크기가 같고 부호가 반대인
두 수의 합은 0이고, 그 0의 부호는 반올림 방식이 $-\infty$ 쪽일 때만 음수다(두 0을
더할 때도 마찬가지다). 그래서 |4*num+num| 경우에서 두 수가 서로의 부호만 바꾼
것이면 |4*zro+zro| 경우로 흘러내린다.

@<함수들@>=
func FPlus(y, z Octa, r Round) (x Octa, exc int) {
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, zs := funpack(z)
	var xs bool
	switch 4*yt + zt {
	@<흔한 NaN 경우들@>
	@<한쪽만 0인 합@>
	@<무한대가 끼는 합@>
	case 4*num + num:
		if y != z^SignBit {
			@<0이 아닌 두 수를 더하고 돌려준다@>
		}
		fallthrough
	case 4*zro + zro:
		x = 0
		if ys == zs {
			xs = ys
		} else {
			xs = r == RoundDown
		}
	}
	if xs {
		x |= SignBit
	}
	return
}

@ 한쪽이 0인 합은 다른 쪽을 다시 포장해서 얻는다.

@<한쪽만 0인 합@>=
case 4*zro + num:
	return fpack(zf, ze, zs, RoundOff) // may underflow
case 4*num + zro:
	return fpack(yf, ye, ys, RoundOff) // may underflow

@ 무한대가 끼면 답은 무한대이고, 부호는 무한대 쪽을 따른다. 다만 부호가 반대인 두
무한대의 합은 잘못된 연산이다.

@<무한대가 끼는 합@>=
case 4*inf + inf:
	if ys != zs {
		exc |= IBit
		x, xs = StandardNaN, zs
		break
	}
	fallthrough
case 4*num + inf, 4*zro + inf:
	x, xs = InfOcta, zs
case 4*inf + num, 4*inf + zro:
	x, xs = InfOcta, ys

@ 먼저 크기가 큰 쪽이 |y|가 되도록 필요하면 두 수를 맞바꾼다. 결과의 부호와 지수는
큰 쪽의 것에서 출발한다. 부호가 같으면 소수 부분을 더하고, 합이 $2^{55}$ 이상이면
오른쪽으로 한 비트 옮기되 떨어지는 비트를 끈끈이로 남긴다. 부호가 다르면 빼고,
결과가 작아졌으면 맨 앞의 1이 $2^{54}$ 자리에 올 때까지 왼쪽으로 옮긴다.

@<0이 아닌 두 수를 더하고 돌려준다@>=
if ye < ze || (ye == ze && yf < zf) {
	@<|y|와 |z|를 맞바꾼다@>
}
d := ye - ze
xs = ys
xe := ye
if d != 0 {
	@<지수의 차이를 맞춘다@>
}
var xf Octa
if ys == zs {
	xf = yf + zf
	if xf >= 1<<55 {
		xe++
		xf = xf>>1 | xf&1
	}
} else {
	xf = yf - zf
	if xf >= 1<<55 {
		xe++
		xf = xf>>1 | xf&1
	} else {
		for xf < 1<<54 {
			xe--
			xf <<= 1
		}
	}
}
return fpack(xf, xe, xs, r)

@ 원본은 임시 변수를 써서 세 쌍을 차례로 맞바꾸었다. \GO/의 병렬 대입은 임시 변수를
필요로 하지 않는다.

@<|y|와 |z|를 맞바꾼다@>=
yf, zf = zf, yf
ye, ze = ze, ye
ys, zs = zs, ys

@ 올바르게 반올림하려면 |fpack|에 넘기는 소수 부분의 오른쪽에 두 비트가 있어야 한다.
첫째는 결과의 참된 다음 비트다. 둘째는 ``끈끈이'' 비트로서, 참된 결과의 그 아래
비트들 가운데 하나라도 0이 아니면 0이 아니다. 정수로 끈끈이 반올림을 한다는 것은
$x$를 $\lfloor x/2\rfloor+\lceil x/2\rceil$로 바꾸는 것이다.
@^sticky bit@>

끈끈이 비트가 왼쪽으로 옮겨지지 않도록 하려면 몇 가지 미묘한 점을 지켜야 한다.
소수 부분 |zf|를 오른쪽으로 옮기기 전에 |yf|를 왼쪽으로 한 비트 옮기지 않았다면, 어떤
경우에는 틀린 답이 나왔을 것이다. 예컨대 $|yf|=2^{54}$, $|zf|=2^{54}+2^{53}-4$,
$d=52$일 때 그렇다.

보충: 부호가 다른 두 수를 뺄 때는 결과가 작아져서 나중에 왼쪽으로 옮겨질 수 있다.
그때 |zf|의 끈끈이 비트가 따라 올라가면, 끈끈이 비트가 진짜 비트처럼 행세하게 된다.
미리 |yf|를 한 자리 올리고 |zf|를 한 자리 덜 내려 두면, 뺄셈 결과가 정규화될 때
왼쪽으로 옮겨질 일이 적어도 한 자리 줄어든다. 두 수의 차가 2 이하이면 떨어지는 비트가
두 비트 안이므로 정확하고, 54보다 크면 |zf|의 모든 비트가 끈끈이 비트 하나로
줄어든다(``까다롭지만 괜찮다'').

이 문턱에도 사연이 있다. 2013년판에서는 문턱이 53이었다. 그런데 $|zf|<2^{55}$이므로,
$d=54$일 때 $|zf|/2^{54}$는 1 이상일 수 있다. 이 값을 끈끈이 비트 하나로 뭉개면, 부호가
다른 두 수를 뺄 때 반올림이 틀린 쪽으로 갈 수 있다. 옮긴이의 무작위 시험이 찾아낸 예는
$-2^{64}+1853.1765\ldots$였다. 참된 값은 $-2^{64}$보다 $-2^{64}+2048$에 훨씬 가까우므로
답은 \Hex{c3efffffffffffff}이어야 하는데, 2013년판은 \Hex{c3f0000000000000}을 냈다.
최신판은 문턱을 54로 올려, $d=54$일 때도 아래의 정밀한 길로 가게 했다. 위 문단의 예에
나오는 수도 최신판에서 $2^{53}-1$이 $2^{53}-4$로 바뀌었다.

@<지수의 차이를 맞춘다@>=
if d <= 2 {
	zf >>= d // exact result
} else if d > 54 {
	zf = 1 // tricky but OK
} else {
	if ys != zs {
		d--
		xe--
		yf <<= 1
	}
	o := zf
	zf = o >> d
	if zf<<d != o {
		zf |= 1
	}
}

@ 부동소수점 수를 $\epsilon$에 대해 비교하는 일은 부동소수점 덧셈이나 뺄셈과 성격이
비슷하다. 어떤 면에서는 더 간단하고 어떤 면에서는 더 어렵다. 이왕 여기까지 왔으니
지금 해치우자.

서브루틴 |FEpsComp(y,z,e,s)|는 |y|, |z|, |e| 가운데 NaN이 있거나 |e|가 음수이면 2를
돌려준다. 인자 |s|가 거짓이고 $y\approx z\ (e)$이거나, |s|가 참이고 $y\sim z\ (e)$이면 1을
돌려준다. 이 관계들은 {\sl Seminumerical Algorithms\/}의 4.2.2절에 정의되어 있다. 그 밖의
경우에는 0을 돌려준다.

보충: 4.2.2절의 정의를 옮겨 둔다. 두 수를 $u=(e_u,f_u)$, $v=(e_v,f_v)$라 할 때, $u\sim
v\ (\epsilon)$(``$u$와 $v$는 $\epsilon$에 대해 비슷하다'')는 $|v-u|\le\epsilon\cdot
\min(b^{e_u-q},b^{e_v-q})$이고, $u\approx v\ (\epsilon)$(``$u$와 $v$는 대략 같다'')은
$|v-u|\le\epsilon\cdot\max(b^{e_u-q},b^{e_v-q})$이다. 대략 말해, 비슷함은 둘 중 작은
쪽의 크기에 비추어, 대략 같음은 큰 쪽의 크기에 비추어 차이를 잰다. 그래서 대략 같음이
더 너그럽다. \MMIX의 \.{FCMPE}, \.{FEQLE}, \.{FUNE}가 이 서브루틴을 쓴다.

@<함수들@>=
func FEpsComp(y, z, e Octa, s bool) int {
	@<엡실론을 풀고, NaN이거나 음수이면 2를 돌려준다@>
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, zs := funpack(z)
	@<0이나 무한대나 NaN이 끼는 경우를 처리한다@>
	@<엡실론에 대해 두 수를 비교하고 돌려준다@>
}

@ 무한대인 엡실론은 지수가 아주 큰 수처럼 다룬다.

@<엡실론을 풀고...@>=
et, ef, ee, es := funpack(e)
if es {
	return 2
}
switch et {
case nan:
	return 2
case inf:
	ee = 10000
}

@ 두 무한대는 부호가 같거나 $\epsilon\ge2$이면 대략 같다. 무한대와 유한한 수는
비슷함의 관계에서 $\epsilon\ge1$일 때만 비슷하다고 본다. 0과 0이 아닌 수는 비슷함의
관계에서만 더 따져 본다.

@<0이나 무한대나 NaN이 끼는 경우를 처리한다@>=
switch 4*yt + zt {
	case 4*nan + nan, 4*nan + inf, 4*nan + num, 4*nan + zro,
		4*inf + nan, 4*num + nan, 4*zro + nan:
		return 2
	case 4*inf + inf:
		if ys == zs || ee >= 1023 {
			return 1
		}
		return 0
	case 4*inf + num, 4*inf + zro, 4*num + inf, 4*zro + inf:
		if s && ee >= 1022 {
			return 1
		}
		return 0
	case 4*zro + zro:
		return 1
	case 4*zro + num, 4*num + zro:
		if !s {
			return 0
		}
	}

@ 관계 $y\approx z\ (\epsilon)$은 $y\sim z\ (\epsilon/2^d)$로 바뀐다. 여기서 $d$는 $y$와
$z$의 지수 가운데 큰 것과 작은 것의 차이다.

@<엡실론에 대해 두 수를 비교하고 돌려준다@>=
@<비정규수인 |y|와 |z|를 정규수 꼴로 되돌린다@>
if ye < ze || (ye == ze && yf < zf) {
	@<|y|와 |z|를 맞바꾼다@>
}
if ze == zeroExponent {
	ze = ye
}
d := ye - ze
if !s {
	ee -= d
}
if ee >= 1023 {
	return 1 // if $\epsilon\ge2$, $z\in N_\epsilon(y)$
}
@<소수 부분의 차이 |o|를 계산한다@>
if o == 0 {
	return 1
}
if ee < 968 {
	return 0 // if $y\ne z$ and $\epsilon<2^{-54}$, $y\not\sim z$
}
if ee >= 1021 {
	ef <<= ee - 1021
} else {
	ef >>= 1021 - ee
}
if o <= ef {
	return 1
}
return 0

@ 보충: 함수 |funpack|은 비정규수를 정규화하면서 지수를 음수로 만든다. 이 비교에서는
비정규수를 지수 0에 소수 부분 $x\cdot4$인 것으로 되돌려야 차이의 크기가 올바로
나온다. 결과 $x$를 두 비트 왼쪽으로 옮기면 부호 비트는 밖으로 밀려 나가고 지수 필드는
0이므로, 소수 필드만 남는다.

@<비정규수인 |y|와 |z|를 정규수 꼴로 되돌린다@>=
if ye < 0 && yt != zro {
	yf, ye = y<<2, 0
}
if ze < 0 && zt != zro {
	zf, ze = z<<2, 0
}

@ 이 시점에서 $y\sim z$는 다음 조건과 동치다.
$$|yf|+(-1)^{[ys=zs]}|zf|/2^d\le 2^{ee-1021}|ef|=2^{55}\epsilon.$$
우리는 이 관계를, 흉내 낸 64비트 레지스터의 한계를 넘지 않고 평가해야 한다.

지수 차이가 $d>2$이면 소수 부분의 차이가 옥타바이트에 정확히 들어가지 않을 수 있다. 그 경우에는
$\epsilon>3/8$이 아닌 한 두 수는 비슷하지 않으며, 우리는 차이를 참된 결과의
천장값(ceiling)으로 바꾼다. 오차 한계가 $\epsilon<1/8$일 때 우리 프로그램은 사실상 $2^{55}\epsilon$을
$\lfloor2^{55}\epsilon\rfloor$로 바꾼다. 이 두 절삭은 동시에 필요하지 않다. 따라서 이
논리는 다음 사실들로 정당화된다: $n$이 정수이면 $x\le n$은 $\lceil x\rceil\le n$과
동치이고, $n\le x$는 $n\le\lfloor x\rfloor$와 동치다. (여기서는 ``끈끈이 비트''라는
개념이 적절하지 {\it 않다\/}는 데 주의하라.)
@^sticky bit@>

@<소수 부분의 차이 |o|를 계산한다@>=
var o, oo Octa
if d > 54 {
	o, oo = 0, zf
} else {
	o = zf >> d
	oo = o << d
}
if oo != zf { // truncated result, hence $d>2$
	if ee < 1020 {
		return 0 // difference is too large for similarity
	}
	if ys != zs {
		o++ // adjust for ceiling
	}
}
if ys == zs {
	o = yf - o
} else {
	o = yf + o
}

@*부동소수점 출력 변환. 함수 |FloatString|은 옥타바이트를 부동 십진 표현으로
바꾸는데, 그 표현을 다시 입력하면 정확히 같은 값이 된다. 원본의 |print_float|는 그
결과를 표준 출력에 바로 찍었다. 여기서는 문자열로 돌려주므로, 부르는 쪽이 원하는
곳에 쓸 수 있다.
@^binary-to-decimal conversion@>
@^radix conversion@>
@^multiprecision conversion@>

@<함수들@>=
func FloatString(x Octa) string {
	@<|FloatString|의 지역 변수@>
	var sb strings.Builder
	if x&SignBit != 0 {
		sb.WriteByte('-')
	}
	@<지수 |e|를 뽑아내고 소수 구간 $[f\dts g]$ 또는 $(f\dts g)$를 정한다@>
	@<$f$와 $g$를 다정밀도 정수로 저장한다@>
	@<유효 숫자 |s|와 십진 지수 |e|를 계산한다@>
	@<유효 숫자를 알맞은 꼴로 찍는다@>
	return sb.String()
}

@ 여기서 풀려는 문제를 눈으로 그려 보는 한 방법은, 지수가 2비트이고 소수 부분이
2비트뿐인 훨씬 단순한 경우를 생각하는 것이다. 그러면 열여섯 가지 4비트 조합은 다음과
같이 해석된다.
$$\def\\{\;\dts\;}
\vbox{\halign{#\qquad&$#$\hfil\cr
0000&[0\\0.125]\cr
0001&(0.125\\0.375)\cr
0010&[0.375\\0.625]\cr
0011&(0.625\\0.875)\cr
0100&[0.875\\1.125]\cr
0101&(1.125\\1.375)\cr
0110&[1.375\\1.625]\cr
0111&(1.625\\1.875)\cr
1000&[1.875\\2.25]\cr
1001&(2.25\\2.75)\cr
1010&[2.75\\3.25]\cr
1011&(3.25\\3.75)\cr
1100&[3.75\\\infty]\cr
1101&\rm NaN(0\\0.375)\cr
1110&\rm NaN[0.375\\0.625]\cr
1111&\rm NaN(0.625\\1)\cr}}$$
소수 부분이 짝수이면 구간이 닫힌 구간 $[f\dts g]$이고, 홀수이면 열린 구간 $(f\dts g)$임에
주목하라. 이렇게 짧은 지수와 소수 부분을 실제로 다룬다면, 이 열여섯 값의 출력은
차례로 \.{0.}, \.{.2}, \.{.5}, \.{.7}, \.{1.}, \.{1.2}, \.{1.5}, \.{1.7},
\.{2.}, \.{2.5}, \.{3.}, \.{3.5}, \.{Inf}, \.{NaN.2}, \.{NaN}, \.{NaN.8}이 될 것이다.

보충: 구간은 그 비트 패턴으로 반올림되는 모든 실수의 모임이다. 이웃한 두 수의
한가운데가 경계인데, 한가운데에 놓인 수는 짝수 쪽으로 반올림되므로 짝수 패턴의
구간은 양 끝을 포함하고 홀수 패턴의 구간은 포함하지 않는다. 구간 안의 어떤 수를
찍어도 다시 읽으면 같은 패턴이 되므로, 우리는 그 가운데 가장 짧게 쓸 수 있는 수를
고른다. NaN의 ``값''은 소수 부분을 0과 1 사이의 분수로 읽은 것이다.

코드에서 $f$와 $g$는 구간의 두 끝을 소수 부분 단위의 두 배로 나타낸다. 곧 $x$를 한 비트
왼쪽으로 옮겨 부호를 떨어낸 뒤, 소수 부분의 두 배에서 1을 빼고 더해 이웃과의
한가운데를 얻는다. 정규수이면 숨은 비트 $2^{53}$을 켠다. 비정규수는 지수 1인 수와
같은 간격을 가지므로 $e=1$로 둔다.

@<지수 |e|를 뽑아내고...@>=
f = x << 1
e = int(f >> 53)
f &= 1<<53 - 1
if f == 0 {
	@<소수 부분이 0인 특별한 경우를 처리한다@>
} else {
	g = f + 1
	f--
	if e == 0 {
		e = 1 // subnormal
	} else if e == 0x7ff {
		sb.WriteString("NaN")
		if g == 1<<52+1 {
			return sb.String() // the ``standard'' NaN
		}
		e = 0x3ff // extreme NaNs come out OK even without adjusting |f| or |g|
	} else {
		f |= 1 << 53
		g |= 1 << 53
	}
}

@ @<|FloatString|의 지역 변수@>=
var f, g Octa // lower and upper bounds on the fraction part
var e int     // exponent part
var j, k int  // all purpose indices

@ 지수가 바뀌는 곳은 2의 거듭제곱에 해당한다. 그런 곳에서 구간은 그 2의 거듭제곱의
왼쪽으로 오른쪽의 절반만큼만 뻗는다. 예컨대 앞에서 생각한 4비트 최소 부동소수점
수에서 경우 1000은 구간 $[1.875\;\dts\;2.25]$에 해당한다.

보충: 아래 이웃은 지수가 하나 작아 간격이 절반이므로, 지수를 하나 줄이고 소수
부분의 단위를 절반으로 잡아 $f=2^{54}-1$, $g=2^{54}+2$로 둔다. 그러면 아래로는 한
단위, 위로는 두 단위만큼 뻗는 구간이 된다.

@<소수 부분이 0인 특별한 경우를 처리한다@>=
if e == 0 {
	sb.WriteString("0.")
	return sb.String()
}
if e == 0x7ff {
	sb.WriteString("Inf")
	return sb.String()
}
e--
f = 1<<54 - 1
g = 1<<54 + 2

@ 우리는 주어진 수에 대응하는 구간에서 ``가장 단순한'' 값, 곧 십진 표기로 나타낼
때 유효 숫자가 가장 적은 값을 찾고 싶다. 예컨대 부동소수점 수를 `\.{.1}'이나
`\.{37e100}'처럼 비교적 짧은 문자열로 기술할 수 있다면, 그 표현을 찾아내고 싶다.

기본 발상은 구간의 두 끝점의 십진 표현을 만들어 가면서, 두 끝점이 일치하는 앞자리
숫자들을 내보내고, 처음으로 달라지는 자리에서 마지막 결정을 내리는 것이다.

``가장 단순한'' 값이 늘 하나뿐인 것은 아니다. 예컨대 4비트 최소 부동소수점 수의
경우, 비트 패턴 0001은 \.{.2}로도 \.{.3}으로도 나타낼 수 있고, 1001은 똑같이 짧은 다섯
가지 방법, \.{2.3}, \.{2.4}, \.{2.5}, \.{2.6}, \.{2.7}로 나타낼 수 있다. 아래의
알고리즘은 이런 경우 가운데 것을 고르려고 한다.

[반올림을 짝수 쪽으로 하는 복잡함이 없는 고정소수점 표현에 대한 비슷한 문제의
해법을, 크누스는 \TeX\ 프로그램에 썼다. {\sl Beauty is Our Business\/}(Springer,
1990), 233--242쪽을 보라.]
@^Knuth, Donald Ervin@>

$0\le f<g<1$인 두 분수 $f$와 $g$가 주어졌을 때, 닫힌 구간 $[f\dts g]$ 안의 가장 짧은
십진 소수를 구하고 싶다고 하자. 분수가 $f=0$이면 끝이다. 아니면 $10f=d+f'$, $10g=e+g'$라
하자. 여기서 $0\le f'<1$, $0\le g'<1$이다. 숫자가 $d<e$이면, 숫자 $d+1$, \dots,~$e$ 가운데
아무것이나 내보내고 끝낼 수 있다. 아니면 공통 숫자 $d=e$를 내보내고, 분수 $0\le
f'<g'<1$에 대해 이 과정을 되풀이한다. 열린 구간 $(f\dts g)$에 대해서도 비슷한 절차가
통한다.

@ 아래 프로그램은 28비트 자리 77개로 이루어진 정수에 대한 다정밀도 산술로 이
알고리즘을 실행한다. 이렇게 고르면 10을 곱하기가 쉽고, 부동 이진수의 전체 범위를
고정소수점 산술로 다룰 수 있다. 우리는 맨 앞 자리와 맨 끝 자리의 위치를 기억해
두어서, 0에 대한 쓸데없는 연산을 피한다.

포인터 |f|가 \KW{bignum}을 가리키면, 그 기수 $2^{28}$ 자리들은 가장 높은 자리부터 가장 낮은
자리까지 |f.dat[0]|부터 |f.dat[76]|까지다. 색인 |f.a|와 |f.b| 사이(양 끝 포함)에 있지
않은 모든 자리는 0이라고 가정한다. 게다가 |f.a=f.b=bignumPrec-1|이 아닌 한,
|f.dat[f.a]|와 |f.dat[f.b]|는 둘 다 0이 아니다.

데이터 타입 \KW{bignum}은 $2^{32}$보다 작은 어떤 기수로도 쓸 수 있다. 우리는 나중에
이것을 기수 $10^9$로 쓸 것이다. 배열 |dat|는 두 쓰임새를 모두 담을 만큼 크게 잡는다.

@<타입 정의@>=
type bignum struct {
	a   int               // index of the most significant digit
	b   int               // index of the least significant digit; must be $\ge a$
	dat [bignumPrec]Tetra // the digits; undefined except between |a| and |b|
}

@ @<상수@>=
const bignumPrec = 157 // would be 77 if we cared only about |FloatString|

@ 예를 들어 넘침이 일어나지 않고 기수가 $2^{28}$이라고 가정할 때, $f$에서 $10f$로
가는 방법은 이렇다. 원본의 포인터 |p|와 |q|는 여기서 |dat|의 색인이 되었다. 루프가
끝나면 |p|는 |f.a-1|을 가리키고, 거기에 마지막 올림을 넣는다.

@<함수들@>=
func (f *bignum) timesTen() {
	var carry Tetra
	p := f.b
	for ; p >= f.a; p-- {
		x := f.dat[p]*10 + carry
		f.dat[p] = x & 0xfffffff
		carry = x >> 28
	}
	f.dat[p] = carry
	if carry != 0 {
		f.a--
	}
	if f.dat[f.b] == 0 && f.b > f.a {
		f.b--
	}
}

@ 그리고 어떤 기수로든 $f<g$인지, $f=g$인지, $f>g$인지를 시험하는 방법은 이렇다.
돌려주는 값은 차례로 $-1$, 0, 1이다.

@<함수들@>=
func (f *bignum) compare(g *bignum) int {
	if f.a != g.a {
		if f.a > g.a {
			return -1
		}
		return 1
	}
	for p := f.a; p <= f.b; p++ {
		if f.dat[p] != g.dat[p] {
			if f.dat[p] < g.dat[p] {
				return -1
			}
			return 1
		}
		if p == g.b {
			if p < f.b {
				return 1
			}
			return 0
		}
	}
	return -1
}

@ 다음 서브루틴은 주어진 기수 |r|을 써서 $f$에서 $g$를 뺀다. 두 수는 $f\ge g>0$이라고
가정한다.

@<함수들@>=
func (f *bignum) dec(g *bignum, r Tetra) {
	for g.b > f.b {
		f.b++
		f.dat[f.b] = 0
	}
	borrow := 0
	p := g.b
	for ; p >= g.a; p-- {
		x := int(f.dat[p]) - int(g.dat[p]) - borrow
		if x >= 0 {
			borrow, f.dat[p] = 0, Tetra(x)
		} else {
			borrow, f.dat[p] = 1, Tetra(x+int(r))
		}
	}
	for ; borrow != 0; p-- {
		if f.dat[p] != 0 {
			borrow = 0
			f.dat[p]--
		} else {
			f.dat[p] = r - 1
		}
	}
	@<뺀 결과의 양 끝 색인을 바로잡는다@>
}

@ 뺄셈으로 앞자리들이 0이 되었을 수 있으므로 |a|를 올린다. 결과 전체가 0이면,
약속대로 |a|와 |b|를 모두 마지막 자리에 둔다.

@<뺀 결과의 양 끝 색인을 바로잡는다@>=
for f.dat[f.a] == 0 {
	if f.a == f.b { // the result is zero
		f.a, f.b = bignumPrec-1, bignumPrec-1
		f.dat[bignumPrec-1] = 0
		return
	}
	f.a++
}
for f.dat[f.b] == 0 {
	f.b--
}

@ 이 서브루틴들로 무장했으니 문제를 풀 준비가 되었다. 첫 과제는 수들을 \KW{bignum}
꼴로 넣는 것이다. 지수가 |e|이면, 자리 |dat[k]|에 들어갈 수는 주어진 소수 부분을 어떤
상수~$c$에 대해 $c-e-28k$비트만큼 오른쪽으로 옮긴 것의 오른쪽 28비트가 된다. 우리는
$e$가 최댓값 \Hex{7ff}일 때 맨 앞 자리가 |dat[1]|에 들어가도록, 그리고 찍을 수가 정확히
1일 때 $g$의 정수 부분도 정확히 1이 되도록 $c$를 고른다.

보충: 소수 부분 $f$는 많아야 55비트이므로 28비트 자리 세 개, |dat[k-1]|, |dat[k]|,
|dat[k+1]|에 걸친다. 색인을 $k=\lfloor(c-e)/28\rfloor$로 잡으면 $c-e-28k$는 0 이상 27 이하이므로,
|dat[k-1]|에는 $28$--$55$비트, |dat[k]|에는 $0$--$27$비트 오른쪽으로 옮긴 것이 들어가고,
|dat[k+1]|에는 $1$--$28$비트 왼쪽으로 옮긴 것이 들어간다. 기수점(radix point)은
|dat[37]| 바로 뒤에 있다.

@<상수@>=
const (
	magicOffset = 2112 // the constant $c$ that makes it work
	origin      = 37   // the radix point follows |dat[37]|
)

@ @<$f$와 $g$를 다정밀도 정수로 저장한다@>=
k = (magicOffset - e) / 28
ff.dat[k-1] = Tetra(f>>(magicOffset+28-e-28*k)) & 0xfffffff
gg.dat[k-1] = Tetra(g>>(magicOffset+28-e-28*k)) & 0xfffffff
ff.dat[k] = Tetra(f>>(magicOffset-e-28*k)) & 0xfffffff
gg.dat[k] = Tetra(g>>(magicOffset-e-28*k)) & 0xfffffff
ff.dat[k+1] = Tetra(f<<(e+28*k-(magicOffset-28))) & 0xfffffff
gg.dat[k+1] = Tetra(g<<(e+28*k-(magicOffset-28))) & 0xfffffff
@<$f$와 $g$의 양 끝 색인을 정한다@>

@ @<$f$와 $g$의 양 끝 색인을 정한다@>=
ff.a, ff.b, gg.a, gg.b = k, k, k, k
if ff.dat[k-1] != 0 {
	ff.a = k - 1
}
if ff.dat[k+1] != 0 {
	ff.b = k + 1
}
if gg.dat[k-1] != 0 {
	gg.a = k - 1
}
if gg.dat[k+1] != 0 {
	gg.b = k + 1
}

@ 지수 $e$가 충분히 작으면 분수 $f$와 $g$는 1보다 작고, 앞에서 말한 알고리즘을 바로 쓸 수
있다. 물론 $e$가 아주 작으면 앞쪽의 0을 많이 잘라 내야 한다. 최악의 경우 $f$와 $g$에
10을 300번 넘게 곱해야 할 수도 있다. 하지만 뭐 어떤가, 그런 일이 아주 자주 생기지는
않고, 요즘 컴퓨터는 꽤 빠르다.

작은 지수의 경우, 계산은 늘 $f$가 0이 되기 전에 끝난다. 구간의 끝점들이 어떤 $t>50$에
대해 분모가 $2^t$인 분수이기 때문이다.

조건 |ff.a=origin|이거나 |gg.a=origin|일 때, 불변 관계 |ff.dat[ff.a]!=0|과 |gg.dat[gg.a]!=0|은
여기서의 계산에서 지켜지지 않는다. 그러나 |compare|를 쓰지 않으므로 해가 없다.

보충: 루프는 두 끝점의 정수 부분(|dat[origin]|)을 보면서 돈다. 조건 |gg.a>origin|이면 아직
$g<0.1$인 셈이어서 유효 숫자가 시작되지 않았으므로 십진 지수만 하나 줄인다. 그렇지
않으면 두 정수 부분이 같은 동안 그 숫자를 내보내고 정수 부분을 지운다. 달라지면
루프를 빠져나와, 두 숫자의 한가운데(올림)를 마지막 숫자로 삼는다. 원본은 숫자들을
문자 배열 |s|에 넣고 포인터 |p|로 채웠다. 여기서는 바이트 조각(slice)에 덧붙인다.

@<유효 숫자 |s|와...@>=
if e > 0x401 {
	@<큰 지수의 경우에 유효 숫자를 계산한다@>
} else { // if |e<=0x401| we have |gg.a>=origin| and |gg.dat[origin]<=8|
	if ff.a > origin {
		ff.dat[origin] = 0
	}
	for e = 1; gg.a > origin || ff.dat[origin] == gg.dat[origin]; {
		if gg.a > origin {
			e--
		} else {
			s = append(s, byte(ff.dat[origin])+'0')
			ff.dat[origin], gg.dat[origin] = 0, 0
		}
		ff.timesTen()
		gg.timesTen()
	}
	s = append(s, byte((ff.dat[origin]+1+gg.dat[origin])>>1)+'0') // the middle digit
}

@ 지수 $e$가 크면, $f$와 $g$를 분모가 10의 거듭제곱인 분수로 보고 앞에서 말한 알고리즘을
쓴다.

흥미로운 경우는 변환할 수가 \Hex{44ada56a4b0835bf}일 때 생긴다. 구간이
$$ (69999999999999991611392\ \ \dts\ \ 70000000000000000000000)$$
이 되기 때문이다. 이것이 닫힌 구간이라면 그냥 \.{7e22}라고 답하면 되겠지만, 짝수 쪽
반올림 규칙 때문에 수 \.{7e22}는 실제로는 \Hex{44ada56a4b0835c0}에 대응한다. 따라서
올바른 답은, 이를테면 \.{6.9999999999999995e22}이다. 이 예는 열린 구간의 경우 조금
다른 전략이 필요함을 보여 준다. 끝점들의 십진 숫자가 처음으로 달라지는 자리만 보아서는
안 된다. 그래서 열린 구간이 관련될 때는 불변 관계를 $0\le f<g\le 1$로 바꾸고, $f=0$이나
$g=1$일 때 과정을 끝내지 않는다.

보충: 변수 |tt|는 분모 $10^e$이다. 먼저 $g$보다 크도록(열린 구간이면 $g$ 이상이 되도록)
변수 |tt|에 10을 거듭 곱해 십진 지수 |e|를 정한다. 그런 다음 $f$와 $g$에 10을 곱하고, |tt|를
뺄 수 있는 만큼 빼서 그 횟수를 숫자 |j|로 삼는다. 이것이 $10f=d+f'$에서 $d$를 구하는
일이다. 원본은 닫힌 구간에서 $f$가 0이 되면 |goto done|으로 가운데 숫자를 고르는
단계를 건너뛰었다. 여기서는 플래그 |done|을 쓴다.

@<큰 지수의 경우에 유효 숫자를 계산한다@>=
open := int(x & 1)
tt.dat[origin] = 10
tt.a, tt.b = origin, origin
for e = 1; gg.compare(&tt) >= open; e++ {
	tt.timesTen()
}
done := false
for {
	ff.timesTen()
	gg.timesTen()
	for j = '0'; ff.compare(&tt) >= 0; j++ {
		ff.dec(&tt, 0x10000000)
		gg.dec(&tt, 0x10000000)
	}
	if gg.compare(&tt) >= open {
		break
	}
	s = append(s, byte(j))
	if ff.a == bignumPrec-1 && open == 0 {
		done = true // $f=0$ in a closed interval
		break
	}
}
if !done {
	@<가운데 숫자를 고른다@>
}

@ 끝점 $g$가 몇 번 더 |tt|를 담는지를 세어 $10g$의 정수 부분 |k|를 얻고, $d=|j|$와
|k|의 한가운데를 올림하여 마지막 숫자로 삼는다.

@<가운데 숫자를 고른다@>=
for k = j; gg.compare(&tt) >= open; k++ {
	gg.dec(&tt, 0x10000000)
}
s = append(s, byte((j+1+k)>>1)) // the middle digit

@ 문자열~|s|의 길이는 많아야 17이다. 두 수 $f$와 $g$가 17자리까지 일치한다면
$g/f<1+10^{-16}$이지만, 비 $g/f$는 늘
$\ge(1+2^{-52}+2^{-53})/(1+2^{-52}-2^{-53})>1+2\times10^{-16}$이기 때문이다.

@<|FloatString|의 지역 변수@>=
var ff, gg bignum      // fractions or numerators of fractions
var tt bignum          // power of ten (used as the denominator)
s := make([]byte, 0, 17) // significant digits

@ 이 시점에서 유효 숫자들은 문자열 |s|에 있고, |s[0]!='0'|이다. 문자열 |s|의 왼쪽에 소수점을
찍으면, 그 결과에 $10^e$을 곱한 것이 찍으려는 값이다.

우리는 `\.{3e2}'보다 `\.{300.}'을, `\.{3e-2}'보다 `\.{.03}'을 좋아한다. 일반적으로
출력은, 지수를 쓰지 않은 꼴이 18글자보다 길어질 때만 지수를 명시적으로 쓴다.

원본의 |printf| 서식 네 개는 \GO/의 |fmt|에서도 거의 그대로 통한다. 너비와 정밀도를
인자로 받는 |*|도 \GO/에 있다.

@<유효 숫자를 알맞은 꼴로...@>=
switch s, n := string(s), len(s); {
case e > 17 || e < n-17:
	dot := ""
	if n > 1 {
		dot = "."
	}
	fmt.Fprintf(&sb, "%c%s%se%d", s[0], dot, s[1:], e-1)
case e < 0:
	fmt.Fprintf(&sb, ".%0*d%s", -e, 0, s)
case n >= e:
	fmt.Fprintf(&sb, "%.*s.%s", e, s, s[e:])
default:
	fmt.Fprintf(&sb, "%s%0*d.", s, e-n, 0)
}

@*부동소수점 입력 변환. 이번에는 반대 방향으로, 주어진 십진수를 그와 같은 부동
이진수로 바꾸고 싶다. 다음 문법을 받아들인다.
@^decimal-to-binary conversion@>
@^radix conversion@>
@^multiprecision conversion@>
$$\vbox{\halign{$#$\hfil\cr
\<digit>\is\.0\mid\.1\mid\.2\mid\.3\mid\.4\mid
        \.5\mid\.6\mid\.7\mid\.8\mid\.9\cr
\<digit string>\is\<digit>\mid\<digit string>\<digit>\cr
\<decimal string>\is\<digit string>\..\mid\..\<digit string>\mid
                      \<digit string>\..\<digit string>\cr
\<optional sign>\is\<empty>\mid\.+\mid\.-\cr
\<exponent>\is\.e\<optional sign>\<digit string>\cr
\<optional exponent>\is\<empty>\mid\<exponent>\cr
\<floating magnitude>\is\<digit string>\<exponent>\mid
                    \<decimal string>\<optional exponent>\mid\cr
\hskip12em          \.{Inf}\mid\.{NaN}\mid\.{NaN.}\<digit string>\cr
\<floating constant>\is\<optional sign>\<floating magnitude>\cr
\<decimal constant>\is\<optional sign>\<digit string>\cr
}}$$
예를 들어 `\.{-3.}'은 부동 상수 \Hex{c008000000000000}이고, `\.{1e3}'과 `\.{1000}'은
둘 다 \Hex{408f400000000000}과 같다. `\.{NaN}'과 `\.{+NaN.5}'는 둘 다
\Hex{7ff8000000000000}과 같다.

함수 |ScanConst|는 주어진 문자열을 보고, \<decimal constant>나 \<floating
constant>의 문법에 맞는 가장 긴 앞부분 문자열을 찾는다. 그리고 그에 해당하는 값
|val|과, 처음으로 읽지 않은 문자의 위치 |next|를 돌려준다. (원본은 이 둘을 전역 변수
|val|과 전역 포인터 |next_char|에 넣었다.) 셋째 반환값 |kind|는 부동 상수를 찾았으면
|FloatConst|(원본의 1), 십진 상수를 찾았으면 |DecimalConst|(원본의 0), 아무것도 못
찾았으면 |NoConst|(원본의 $-1$)다. 옥타바이트에 들어가지 않는 십진 상수는 $2^{64}$을
법으로 계산한다.
@^syntax of floating point constants@>

원본은 ``|scan_const|가 설정한 |exceptions| 값은 꼭 옳지는 않다''고 적었다. 그래서
여기서는 예외를 아예 돌려주지 않는다.

@<타입 정의@>=
type ConstKind int // kind of constant found by |ScanConst|

@ @<상수@>=
const (
	NoConst      ConstKind = -1 // no constant was found
	DecimalConst ConstKind = 0  // decimal constant
	FloatConst   ConstKind = 1  // floating constant
)

@ 원본은 \CEE/ 문자열 끝의 널 문자 덕분에 |*(p+1)|처럼 한 글자 앞을 마음 놓고 볼 수
있었다. 여기서도 문자열 끝에 널 문자 하나를 파수꾼으로 붙여서 같은 편리를 얻는다.
파수꾼은 숫자도 부호도 아니므로 어떤 문법 규칙도 그것을 넘어가지 않는다. 따라서
|next|는 늘 원래 문자열 안(또는 바로 끝)을 가리킨다.

원본의 흐름은 |goto packit|, |goto make_it_zero|, |goto make_it_infinite|로 여러 곳에서
마지막 포장 단계로 뛰었다. 여기서는 |switch| 문의 각 경우가 날 지수 |exp|와 소수
|val|을 마련하고, |switch| 다음의 공통 꼬리가 그것을 포장한다. 십진 상수와 상수 없음의
경우만 |switch| 안에서 바로 돌아간다.

@<함수들@>=
func ScanConst(s string) (val Octa, next int, kind ConstKind) {
	@<|ScanConst|의 지역 변수@>
	s += "\x00" // a sentinel at the end, like a \CEE/ string
	p := 0
	sign := byte('+')
	if s[p] == '+' || s[p] == '-' {
		sign = s[p]
		p++
	}
	NaN := strings.HasPrefix(s[p:], "NaN")
	if NaN {
		p += 3
	}
	switch {
	case isDigit(s[p]) && !NaN || s[p] == '.' && isDigit(s[p+1]):
		@<수를 읽는다; 십진 상수이면 돌려준다@>
	case NaN:
		@<표준 NaN을 마련한다@>
	case strings.HasPrefix(s[p:], "Inf"):
		@<무한대를 마련한다@>
	default:
		return 0, 0, NoConst
	}
	@<답을 포장하고 반올림한다@>
	return val, next, FloatConst
}

@ 원본은 표준 라이브러리 \.{ctype.h}의 |isdigit|을 썼다.

@<함수들@>=
func isDigit(c byte) bool { return '0' <= c && c <= '9' }

@ 원본의 지역 변수 |p|와 |q|는 한 포인터가 입력 문자열과 버퍼를 번갈아 가리켰다.
여기서는 |p|가 입력 문자열의 색인이고, |q|와 |decPt|는 버퍼 |buf|의 색인이다. 원본은
소수점이 없음을 널 포인터로 나타냈는데, 여기서는 $-1$로 나타낸다.

@<|ScanConst|의 지역 변수@>=
var q int     // where we put the next digit in |buf|
var decPt int // position of decimal point in |buf|; $-1$ if none

@ 표준 NaN은 소수 부분이 $1.5\cdot2^{54}$, 날 지수가 \Hex{3fe}인 수, 곧 $1.5$를 포장한
다음 NaN으로 만들어 얻는다. 포장 뒤의 처리는 조금 뒤에 나온다.

@<표준 NaN을 마련한다@>=
next = p
val, exp = 0x60000000000000, 0x3fe

@ 무한대는 날 지수를 아주 크게 잡아서 |fpack|이 넘침으로 처리하게 한다.

@<무한대를 마련한다@>=
next = p + 3
exp = 99999

@ 앞에서 우리는 출력할 때 부동소수점 수 하나를 특징짓는 데에는 많아야 17자리의
문자열이면 충분함을 보았다. 그러나 입력할 때는 숫자를 담을 훨씬 긴 버퍼가 필요하다.
예를 들어 경계에 걸린 양 $(1+2^{-53})/2^{1022}$을 생각해 보자. 그 십진 전개를 정확히
써 내면 유효 숫자가 750개를 넘는다: \.{2.2250738585...8125e-308}. 그 숫자들 가운데
{\it 어느 하나라도\/} 커지거나, \.{2.2250738585...81250000001e-308}처럼 0이 아닌 숫자가
뒤에 더 붙으면, 반올림된 값이 \Hex{0010000000000000}에서 \Hex{0010000000000001}로
바뀌어야 한다.

우리는 사용자가 빠르지만 거의 맞는 답보다 완전히 맞는 답을 좋아한다고 가정하고,
가장 일반적인 경우를 구현한다.

보충: 정수 부분의 숫자들을 읽으면서 두 가지 일을 함께 한다. 하나는 십진 상수일
경우를 대비해 값을 $2^{64}$을 법으로 쌓는 것이다(|val*10+d|를 원본은 ``5를 곱하고''
|val+(val<<2)|, ``2를 곱해 숫자를 더하는'' |(val<<1)+d|로 계산했고 여기서도 그렇게
한다). 다른 하나는 부동 상수일 경우를 대비해 유효 숫자들을 버퍼에 모으는 것이다. 앞쪽
0은 모으지 않는다. 버퍼가 차면 더 이상 숫자를 늘리지 않되, 마지막 칸이 0일 때 0이
아닌 숫자가 오면 그것으로 바꿔 둔다. 마지막 칸이 ``끈끈이 숫자'' 구실을 하는 것이다.

@<수를 읽는다; 십진 상수이면 돌려준다@>=
q, decPt = buf0, -1
for ; isDigit(s[p]); p++ {
	val = val + val<<2 // multiply by 5
	val = val<<1 + Octa(s[p]-'0')
	if q > buf0 || s[p] != '0' {
		if q < bufMax {
			buf[q] = s[p]
			q++
		} else if buf[q-1] == '0' {
			buf[q-1] = s[p]
		}
	}
}
if NaN {
	buf[q] = '1'
	q++
}
if s[p] == '.' {
	@<소수 부분을 읽는다@>
}
next = p
exp = 0
if s[p] == 'e' && !NaN {
	@<지수를 읽는다@>
}
if decPt < 0 {
	if sign == '-' {
		val = -val
	}
	return val, next, DecimalConst
}
@<버퍼의 숫자들을 이진 소수와 이진 지수로 바꾼다@>

@ 소수점 바로 뒤의 앞쪽 0들은 버퍼에 넣지 않고 |zeros|에 개수만 센다.

@<소수 부분을 읽는다@>=
decPt = q
p++
for zeros = 0; isDigit(s[p]); p++ {
	if s[p] == '0' && q == buf0 {
		zeros++
	} else if q < bufMax {
		buf[q] = s[p]
		q++
	} else if buf[q-1] == '0' {
		buf[q-1] = s[p]
	}
}

@ 버퍼에는 왼쪽에 채움용 숫자 여덟 개, 그다음 유효 숫자 $1022+53-307$개까지, 그다음
위치 |bufMax-1|에 ``끈끈이'' 숫자 하나, 그리고 채움용 숫자 여덟 개가 더 들어갈 자리가
필요하다.

원본은 이 버퍼를 전역 정적 배열로 두고 부를 때마다 다시 썼다. 여기서는 부를 때마다
지역 배열을 새로 마련하고, 원본의 초깃값 |"00000000"|을 앞에 채운다.

@<상수@>=
const (
	buf0   = 8   // index in |buf| where significant digits begin
	bufMax = 777 // index in |buf| where significant digits end
)

@ @<|ScanConst|의 지역 변수@>=
var buf [785]byte // where we put significant input digits
copy(buf[:], "00000000")
var exp int   // scanned exponent; later used for raw binary exponent
var zeros int // leading zeros removed after decimal point

@ 여기서는 문법에 맞는 지수가 있다는 것을 알기 전에는 |next|를 옮기지 않고 소수점도
강제하지 않는다. 예컨대 \.{1e}는 십진 상수 1이고 |next|는 \.e를 가리킨다.

이 코드는 `\.{9e+9999999999999999}' 같은 엄청나게 큰 입력을 $\infty$로, 엄청나게
작은 입력을 0으로 바꾼다. `\.{-00.0e9999999}' 같은 이상한 입력도 받아들여야 한다.
(그러나 앞쪽 0이 10억 개 이상 있을 때까지 정확한 답을 내려고 애쓰지는 {\it 않는다}.)

@<지수를 읽는다@>=
p++
expSign := byte('+')
if s[p] == '+' || s[p] == '-' {
	expSign = s[p]
	p++
}
if isDigit(s[p]) {
	for exp = int(s[p] - '0'); isDigit(s[p+1]); p++ {
		if exp < 100000000 {
			exp = 10*exp + int(s[p+1]-'0')
		}
	}
	p++
	if decPt < 0 {
		decPt, zeros = q, 0
	}
	if expSign == '-' {
		exp = -exp
	}
	next = p
}

@ 이제 이진 소수 비트들을 계산할 준비로, 읽어 들인 숫자들을 필요한 범위 전체에 걸친
다정밀도 고정소수점 누산기 |ff|에 넣는다. 이 단계가 끝나면, 부동 이진수로 바꾸려는
수가 |ff.dat[ff.a]|, |ff.dat[ff.a+1]|, \dots, |ff.dat[ff.b]|에 나타난다.
자리 ${\it ff}[36-k]$의 기수 $10^9$ 자리는 $10^{9k}$이 곱해진 것으로 이해한다. 여기서
$36\ge k\ge-120$이다.

보충: 값 |x|는 첫 유효 숫자가 |buf|에서 어느 칸에 떨어지는지를 재는 척도다. 버퍼의
숫자들이 나타내는 수는 $0.d_1d_2\ldots\times10^{333-x}$이다. 그러므로 |x|가 크면 수가
작고, $x\ge1413$이면 수가 $10^{-1080}$보다 작아서 0으로 반올림된다. 원본은 $x<0$일
때 무한대로 보냈다.

옮긴이는 여기서 원본의 문턱을 $x<0$에서 $x<10$으로 바꾸었다. 까닭은 이렇다.
지수가 $0\le x\le9$이면 |ff.a=x/9|가 0이나 1이 되는데, 뒤이은 배가(doubling) 과정에서 올림이
|dat[-1]|에 쓰일 수 있다. \CEE/에서 |dat[-1]|은 배열 밖이다. 대개의 컴파일러에서는
구조체 안에서 배열 바로 앞에 놓인 필드 |b|가 그 자리를 차지하므로 원본은 |b|를
덮어쓰게 되고, 그 뒤의 동작은 정의되지 않는다. 옮긴이의 기계에서 원본을 컴파일해
보니, `\.{9e332}' 같은 입력은 운 좋게 무한대를 냈지만 `\.{.64352139e333}'을 넣자
프로그램이 버스 오류로 죽었다. 그런 수는 적어도 $10^{323}$이어서 어차피 무한대로
넘쳐야 하는 수들이다. \GO/는 배열 색인을 검사하므로 같은 코드가 공황을 일으킬
것이다. 문턱을 10으로 올리면 이런 수들은 곧바로 무한대가 된다. 그리고 $x\ge10$인
수는 모두 $10^{323}$보다 작아서, 배가하는 동안의 값이 $2\times10^{323}$을 넘지 않으므로
누산기 안에 넉넉히 들어간다. 그 밖의 입력에 대해서는 결과가 원본과 똑같다.

@<버퍼의 숫자들을 이진 소수와 이진 지수로 바꾼다@>=
x := 341 + zeros - decPt - exp
switch {
case q == buf0 || x >= 1413:
	exp = -99999 // make it zero
case x < 10:
	exp = 99999 // make it infinity
default:
	@<|buf|의 숫자들을 |ff|로 옮긴다@>
	@<이진 소수와 이진 지수를 정한다@>
}

@ 보충: 아홉 자리씩 묶어 기수 $10^9$의 자리를 만드는데, 그 묶음의 경계가 소수점에
맞도록 |buf0-x%9|에서 읽기 시작한다. 그 앞은 채움용 0이다. 뒤쪽에도 0을 여덟 개
채워 마지막 묶음이 모자라지 않게 한다. 누산기 끝(|dat[156]|)을 넘어가는 숫자들
가운데 0이 아닌 것이 있으면, 마지막 자리에 1을 더해 끈끈이로 남긴다.
@^sticky bit@>

@<|buf|의 숫자들을 |ff|로 옮긴다@>=
ff.a = x / 9
for i := q; i < q+8; i++ {
	buf[i] = '0' // pad with trailing zeros
}
q = q - 1 - (q+341+zeros-decPt-exp)%9 // compute stopping place in |buf|
i, k := buf0-x%9, ff.a
for ; i <= q && k <= 156; i, k = i+9, k+1 {
	@<아홉 자리 수 |buf[i]|\thinspace\dots\thinspace|buf[i+8]|을 |ff.dat[k]|에 넣는다@>
}
ff.b = k - 1
x = 0
for ; i <= q; i += 9 {
	if string(buf[i:i+9]) != "000000000" {
		x = 1
	}
}
ff.dat[156] += Tetra(x) // nonzero digits that fall off the right are sticky
for ff.dat[ff.b] == 0 {
	ff.b--
}

@ @<아홉 자리 수...@>=
d := Tetra(buf[i] - '0')
for j := i + 1; j < i+9; j++ {
	d = 10*d + Tetra(buf[j]-'0')
}
ff.dat[k] = d

@ @<|ScanConst|의 지역 변수@>=
var ff, tt bignum

@ 다음은 |timesTen|과 짝을 이루는 서브루틴이다. 넘침이 일어나지 않고 기수가 $10^9$라고
가정할 때, $f$를~$2f$로 바꾼다.

@<함수들@>=
func (f *bignum) double() {
	var carry Tetra
	p := f.b
	for ; p >= f.a; p-- {
		x := f.dat[p] + f.dat[p] + carry
		if x >= 1000000000 {
			carry, f.dat[p] = 1, x-1000000000
		} else {
			carry, f.dat[p] = 0, x
		}
	}
	f.dat[p] = carry
	if carry != 0 {
		f.a--
	}
	if f.dat[f.b] == 0 && f.b > f.a {
		f.b--
	}
}

@ 보충: 수가 1 이상이면(|ff.a<=36|이 아니면 수는 1보다 작다) 경우가 둘로 나뉜다.

수가 1보다 작으면(|ff.a>36|) 정수 부분 |ff.dat[36]|이 1이 될 때까지 배가하면서 지수를
줄인다. 그다음에는 배가할 때마다 정수 부분이 다음 이진 비트가 된다. 이것은 초등학교에서
배운, 소수에 2를 거듭 곱해 이진 소수를 얻는 방법 그대로다.

수가 1 이상이면, 2의 거듭제곱 |tt|를 수보다 커질 때까지 배가하면서 지수를 늘린다.
그다음에는 수를 배가할 때마다 |tt|와 비교해서, |tt| 이상이면 그 비트를 켜고 |tt|를
뺀다. 이것은 이진 긴 나눗셈이다.

어느 쪽이든 54비트를 모두 얻기 전에 나머지가 0이 되면 일찍 멈춘다. 54비트를 모두
얻었는데(|k=0|) 나머지가 남아 있으면 끈끈이 비트를 켠다.
@^sticky bit@>

@<이진 소수와 이진 지수를 정한다@>=
val = 0
if ff.a > 36 {
	for exp = 0x3fe; ff.a > 36; exp-- {
		ff.double()
	}
	for k = 54; k != 0; k-- {
		if ff.dat[36] != 0 {
			val |= 1 << k
			ff.dat[36] = 0
			if ff.b == 36 {
				break // break if |ff| now zero
			}
		}
		ff.double()
	}
} else {
	tt.a, tt.b, tt.dat[36] = 36, 36, 2
	for exp = 0x3fe; ff.compare(&tt) >= 0; exp++ {
		tt.double()
	}
	for k = 54; k != 0; k-- {
		ff.double()
		if ff.compare(&tt) >= 0 {
			val |= 1 << k
			ff.dec(&tt, 1000000000)
			if ff.a == bignumPrec-1 {
				break // break if |ff| now zero
			}
		}
	}
}
if k == 0 {
	val |= 1 // add sticky bit if |ff| nonzero
}

@ 다음 입력이 반올림되어 올라가지 않도록 조심해야 한다.
$$\hbox{`\.{NaN.999999999999999999999}'}$$
이것은 \Hex{7fffffffffffffff}을 내야 한다.

입력 `\.{NaN.0}'은 엄밀히 말하면 문법에 맞지 않지만, 우리는 이것을 조용히
\Hex{7ff0000000000001}로 바꾼다. 이 수는 `\.{NaN.0000000000000002}'로 출력될 것이다.

보충: NaN은 우선 $1.xxx$라는 보통 수로 포장된다(버퍼 앞에 숫자 \.1을 붙였던 것을
떠올리자). 그 수의 지수는 \Hex{3ff}이므로, 거기에 $2^{62}$ 비트를 켜면 지수가
\Hex{7ff}가 되어 NaN이 된다. 소수 부분이 반올림되어 2.0이 되어 버리면 지수가
\Hex{400}이 되므로, 가장 큰 NaN으로 바꾼다. 소수 부분이 0이면(\.{NaN.0}) 무한대가 되어
버리므로 맨 아래 비트를 켠다. 원본은 첫 조건에서 높은 쪽 테트라바이트만 보았으므로,
여기서도 |val>>32|만 본다.

@<답을 포장하고 반올림한다@>=
val, _ = fpack(val, exp, sign == '-', RoundNear)
if NaN {
	switch {
	case (val>>32)&0x7fffffff == 0x40000000:
		val |= 0x7fffffffffffffff
	case val&0x7fffffffffffffff == 0x3ff0000000000000:
		val |= 0x4000000000000001
	default:
		val |= 0x4000000000000000
	}
}

@*부동소수점 나머지. 이 장에서는 부동소수점 연산의 나머지를 구현한다. 그중 하나는
마침 나머지를 구하는 연산이다.

남은 과제 가운데 가장 쉬운 것은 부동소수점 수 두 개를 비교하는 일이다. 함수
|FComp|는 $y<z$이면 $-1$을, $y=z$이면 0을, $y>z$이면 $+1$을, $y$와~$z$가 순서를 매길 수
없으면(unordered) $+2$를 돌려준다.

보충: 두 0은 부호와 상관없이 같다. 그 밖에는, 부호가 다르면 양수 쪽이 크다. 부호가
같으면 IEEE 형식의 멋진 성질 하나를 쓴다. 지수가 소수 부분보다 위에 있으므로, 음이
아닌 두 부동소수점 수의 크기는 비트 패턴을 부호 없는 정수로 비교한 것과 같다. 두 수가
음수이면 그 순서를 뒤집는다.

@<함수들@>=
func FComp(y, z Octa) int {
	yt, _, _, ys := funpack(y)
	zt, _, _, zs := funpack(z)
	var x int
	switch 4*yt + zt {
	case 4*nan + nan, 4*zro + nan, 4*num + nan, 4*inf + nan,
		4*nan + zro, 4*nan + num, 4*nan + inf:
		return 2
	case 4*zro + zro:
		return 0
	case 4*zro + num, 4*num + zro, 4*zro + inf, 4*inf + zro,
		4*num + num, 4*num + inf, 4*inf + num, 4*inf + inf:
		switch {
		case ys != zs:
			x = 1
		case y > z:
			x = 1
		case y < z:
			x = -1
		default:
			return 0
		}
	}
	if ys {
		return -x
	}
	return x
}

@ 여러 \MMIX\ 연산은 부동소수점 수 하나에 작용하고, 아무 반올림 방식이나 받아들인다.
예를 들어 가장 가까운 부동소수점 정수로 반올림하는 연산을 생각해 보자.

@<함수들@>=
func FIntegerize(z Octa, r Round) (x Octa, exc int) {
	zt, zf, ze, zs := funpack(z)
	switch zt {
	case nan:
		if z&(1<<51) == 0 {
			exc |= IBit
			z |= 1 << 51
		}
		fallthrough
	case inf, zro:
		return z, exc
	}
	@<정수로 만들고 돌려준다@>
}

@ 보충: 지수가 1074 이상이면 소수 부분에 소수점 아래 비트가 없으므로 이미 정수다.
그렇지 않으면 소수점 아래 비트들을 끈끈이 비트로 모으고, |fpack|과 같은 방식으로
반올림한 뒤 두 반올림용 비트를 지운다. 지수가 1022 이상이면 결과가 1 이상일 수
있으므로 도로 왼쪽으로 옮겨 |fpack|으로 포장한다. 지수가 그보다 작으면 수의 크기가
$1/2$보다 작아서, 반올림 결과는 0 아니면 1이다.

원본의 이 루틴은 부정확 예외를 기록하지 않는다. 반올림용 비트를 지운 뒤 포장하므로
|fpack|도 부정확을 보지 못한다. \MMIX의 정의가 \.{FINT}에 대해 어떻게 말하든, 이
번역은 원본의 동작을 따른다.

@<정수로 만들고 돌려준다@>=
if ze >= 1074 {
	return fpack(zf, ze, zs, RoundOff) // already an integer
}
var xf Octa
if ze <= 1020 {
	xf = 1
} else {
	xf = zf >> (1074 - ze)
	if xf<<(1074-ze) != zf {
		xf |= 1 // sticky bit
	}
}
@<|xf|를 |r|에 따라 반올림한다@>
xf &^= 3
if ze >= 1022 {
	return fpack(xf<<(1074-ze), ze, zs, RoundOff)
}
if xf != 0 {
	xf = 0x3ff0000000000000
}
if zs {
	xf |= SignBit
}
return xf, exc

@ @<|xf|를 |r|에 따라 반올림한다@>=
switch r {
case RoundDown:
	if zs {
		xf += 3
	}
case RoundUp:
	if !zs {
		xf += 3
	}
case RoundNear:
	if xf&4 != 0 {
		xf += 2
	} else {
		xf++
	}
}

@ 부동소수점을 고정소수점으로 바꾸는 데에는 |FixIt|을 쓴다.

보충: 먼저 |FIntegerize|로 정수로 만든다. 원본은 그 결과를 다시 |funpack|하면서
|exceptions|를 지웠으므로, 이때 생긴 예외는 버려진다. 그다음에 소수 부분을 알맞게 옮겨
정수를 얻는다. 결과가 $-2^{63}$ 이상 $2^{63}$ 미만이 아니면 |WBit|을 기록한다. 이때도
결과는 참된 값을 $2^{64}$을 법으로 줄인 것이다. 지수가 1140 이상이면 그 값은 0이다.
원본의 첫 |switch| 문은 |num|의 경우에 모든 일을 했지만, \GO/의 함수는 모든 경로가
|return|으로 끝나야 하므로 |num|의 경우를 |switch| 뒤로 뺐다.

@<함수들@>=
func FixIt(z Octa, r Round) (Octa, int) {
	zt, _, _, _ := funpack(z)
	switch zt {
	case nan, inf:
		return z, IBit
	case zro:
		return 0, 0
	}
	w, _ := FIntegerize(z, r)
	wt, zf, ze, zs := funpack(w)
	if wt == zro {
		return 0, 0
	}
	@<정수로 만든 수를 고정소수점으로 옮긴다@>
}

@ @<정수로 만든 수를 고정소수점으로 옮긴다@>=
var o Octa
exc := 0
if ze <= 1076 {
	o = zf >> (1076 - ze)
} else {
	if ze > 1085 || (ze == 1085 && (zf > 1<<54 || (zf == 1<<54 && !zs))) {
		exc |= WBit
	}
	if ze >= 1140 {
		return 0, exc
	}
	o = zf << (ze - 1076)
}
if zs {
	o = -o
}
return o, exc

@ 반대 방향으로 갈 때는 반올림 방식뿐 아니라, 주어진 고정소수점 옥타바이트가
부호 있는 수인지 부호 없는 수인지, 결과를 짧은 정밀도로 반올림할지도 지정할 수 있다.

보충: 수를 $2^{54}\le z<2^{55}$이 되도록 정규화한다. 오른쪽으로 옮길 때는 떨어지는
비트를 끈끈이로 남긴다. 부호 있는 $-2^{63}$은 부호를 바꾸어도 $2^{63}$ 그대로이지만,
부호 없는 수로 다루므로 문제가 없다.

@<함수들@>=
func FloatIt(z Octa, r Round, unsigned, short bool) (Octa, int) {
	if z == 0 {
		return 0, 0
	}
	s := false
	if !unsigned && z&SignBit != 0 {
		s, z = true, -z
	}
	e := 1076
	for z < 1<<54 {
		e--
		z <<= 1
	}
	for z >= 1<<55 {
		e++
		z = z>>1 | z&1
	}
	exc := 0
	if short {
		@<짧은 부동소수점 수로 바꾼다@>
	}
	x, ex := fpack(z, e, s, r)
	return x, exc | ex
}

@ 짧은 정밀도로 한 번 반올림한 다음, 그것을 도로 풀어서 긴 정밀도로 포장한다. 원본은
|sfunpack|이 |exceptions|를 지우기 전에 |sfpack|이 남긴 예외를 저장해 두었다가
되살렸다. 여기서는 |sfpack|이 예외를 돌려주므로 그냥 받아 두면 된다. 두 번째 포장은
정확하므로 새 예외를 보태지 않는다.

@<짧은 부동소수점 수로 바꾼다@>=
var t Tetra
t, exc = sfpack(z, e, s, r)
_, z, e, s = sfunpack(t)

@ 제곱근 연산은 더 흥미롭다.

@<함수들@>=
func FRoot(z Octa, r Round) (x Octa, exc int) {
	zt, zf, ze, zs := funpack(z)
	if zs && zt != zro {
		exc |= IBit
		x = StandardNaN
	} else {
		switch zt {
		case nan:
			if z&(1<<51) == 0 {
				exc |= IBit
				z |= 1 << 51
			}
			return z, exc
		case inf, zro:
			x = z
		case num:
			@<제곱근을 구하고 돌려준다@>
		}
	}
	if zs {
		x |= SignBit
	}
	return
}

@ 제곱근은 옛날 종이와 연필로 하던 방법을 고쳐 써서 구할 수 있다. 어떤 수 $s$가 정수이고
$n=\lfloor\sqrt s\rfloor$이면 $s=n^2+r$이고 $0\le r\le2n$이다. 이 불변 관계는 $s$를
$4s+(0,1,2,3)$으로, $n$을 $2n+(0,1)$로 바꾸면서 유지할 수 있다. 아래 코드는 이
발상을 구현하는데, |xf|에 $2n$을, |rf|에 $r$을 둔다. (이것을 두 배쯤 빠르게 만들기는
쉬울 것이다.)

보충: 값 $s$를 $4s+t$로, $n$을 $2n$으로 바꾸면 $r$은 $4r+t$가 된다. 이것이 $2\cdot(2n)$
곧 새 |xf|보다 크면 $n$을 $2n+1$로 늘려야 한다. 그러면 $r$에서
$(2n+1)^2-(2n)^2=4n+1$을 빼야 하는데, 코드는 |xf|에 1을 더한 $4n+1$을 빼고 다시 1을
더해 |xf|를 $2(2n+1)$로 만든다. 소수 부분 |zf|를 두 비트씩 위에서부터 꺼내 $t$로
쓴다. 지수가 홀수이면 |zf|를 한 비트 먼저 옮겨 지수를 짝수로 맞춘다.

원본은 |zf|의 높은 쪽과 낮은 쪽에서 두 비트씩 꺼내느라 |k>=43|과 |k>=27|의 두 경우를
나누었다. 높은 쪽의 비트 $2(k-43)$은 옥타바이트의 비트 $2(k-43)+32=2(k-27)$이므로,
64비트에서는 두 경우가 |(zf>>(2*(k-27)))&3| 하나로 합쳐진다. 색인이 $k<27$이면 꺼낼 비트가
없으므로 0을 보탠다. 루프가 끝났을 때 |rf|가 0이 아니면 근은 정확하지 않으므로
끈끈이 비트를 켠다.
@^sticky bit@>

@<제곱근을 구하고 돌려준다@>=
xf := Octa(2)
xe := (ze + 0x3fe) >> 1
if ze&1 != 0 {
	zf <<= 1
}
rf := zf>>54 - 1
for k := 53; k != 0; k-- {
	rf <<= 2
	xf <<= 1
	if k >= 27 {
		rf += (zf >> (2 * (k - 27))) & 3
	}
	if rf > xf {
		xf++
		rf -= xf
		xf++
	}
}
if rf != 0 {
	xf++ // sticky bit
}
return fpack(xf, xe, false, r)

@ 그리고 마지막으로, 진짜 부동소수점 나머지다. 서브루틴 |FRemStep|은 $y\,{\rm
rem}\,z$를 계산하거나, $y$를 $z$에 대한 나머지가 같은 더 작은 수로 줄인다. 후자의
경우에는 예외 값에 |EBit|을 켠다. 셋째 매개변수 |delta|는 불완전한 결과에 대해
받아들일 수 있는 지수 감소량을 준다. 인자 |delta|가 충분히 크면, 이를테면 2500이면,
|FRemStep| 한 걸음으로 늘 올바른 결과를 얻는다.

보충: IEEE의 나머지 $y\,{\rm rem}\,z$는 $y-nz$이다. 여기서 $n$은 $y/z$에 가장 가까운
정수이고, 동률이면 짝수다. 그래서 나머지의 크기는 $|z|/2$를 넘지 않고, 결과는 늘
정확하다.

@<함수들@>=
func FRemStep(y, z Octa, delta int) (x Octa, exc int) {
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, _ := funpack(z)
	switch 4*yt + zt {
	@<흔한 NaN 경우들@>
	case 4*zro + zro, 4*num + zro, 4*inf + zro, 4*inf + num, 4*inf + inf:
		x = StandardNaN
		exc |= IBit
	case 4*zro + num, 4*zro + inf, 4*num + inf:
		return y, exc
	case 4*num + num:
		@<0이 아닌 두 수의 나머지를 구하고 돌려준다@>
	}
	if ys {
		x |= SignBit
	}
	return
}

@ 지수 차이가 엄청나게 크고 나머지가 0이 아니면 이 계산은 오래 걸린다. 큰 $n$에
대해서는 $z$를 법으로 하는 곱셈 $O(\log n)$번으로 $(2^ny)\,{\rm rem}\,z$를 훨씬 빨리
계산할 수 있겠지만, 부동소수점 나머지 연산은 그렇게 비싼 하드웨어를 정당화할 만큼
중요하지 않다.

부동소수점 나머지의 결과는 늘 정확하므로 반올림 방식은 상관이 없다.

보충: 루프는 이진 긴 나눗셈과 같다. 수 $y$의 지수를 $z$의 지수 쪽으로 한 자리씩 내리면서
$z$를 뺄 수 있으면 뺀다. 수 $y$의 지수가 $z$의 지수와 같아졌을 때 뺐다면 몫의 맨 아래
비트가 1, 곧 $z$의 홀수 배를 뺀 것이다. 원본은 루프 안에서 |goto zero_out|과
|goto try_complement|로 뛰어나왔다. 여기서는 플래그 |zero|와 |complement|를 세우고
|break|로 루프를 빠져나온다. 나머지가 0이면 |x|는 0 그대로이고, |switch| 다음에서
$y$의 부호를 받는다.

@<0이 아닌 두 수의 나머지를...@>=
odd := false // becomes true if we've subtracted an odd multiple of~$z$ from $y$
zero, complement := false, false
thresh := max(ye-delta, ze)
for ye >= thresh {
	@<|(ye,yf)|를 |zf|의 배수만큼 줄인다@>
}
if !zero {
	@<나머지를 마무리하고 돌려준다@>
}

@ 여기서는 |y|의 부호를 바꾸지 않도록 조심한다. 0인 나머지는 원래 |y|의 부호를
이어받아야 하기 때문이다. 나머지가 0이 되면 |zero|를, 보수를 시도할 때가 되면
|complement|를 세우고 루프를 멈춘다.

@<|(ye,yf)|를 |zf|의 배수만큼...@>=
if yf == zf {
	zero = true
	break
}
if yf < zf {
	if ye == ze {
		complement = true
		break
	}
	ye--
	yf <<= 1
}
yf -= zf
if ye == ze {
	odd = true
}
for yf < 1<<54 {
	ye--
	yf <<= 1
}

@ 보충: 루프가 문턱에 걸려 끝났는데 $y$의 지수가 아직 $z$의 지수 이상이면, 일을 다
마치지 못한 것이다. 비트 |EBit|을 켜고 지금까지 줄인 수를 돌려준다. 수 $y$가 $z/4$보다
작아졌으면 그대로 답이다. 그 사이(지수가 하나 작음)면 소수 부분을 한 비트 옮겨
지수를 $z$에 맞춘다.

그다음 ``보수를 시도''한다. 나머지 후보 $y$와 $z-y$ 가운데 크기가 작은 쪽이 답이다.
차 $z-y$ 쪽을 고르면 부호가 바뀐다. 둘이 같으면 몫이 짝수가 되는 쪽을 고른다. 지금까지
$z$의 홀수 배를 뺐으면 한 번 더 빼서(곧 $z-y$) 짝수로 만든다.

@<나머지를 마무리하고 돌려준다@>=
if !complement {
	if ye >= ze {
		exc |= EBit
		x, ex := fpack(yf, ye, ys, RoundOff)
		return x, exc | ex
	}
	if ye < ze-1 {
		return fpack(yf, ye, ys, RoundOff)
	}
	yf >>= 1
}
xf, xe, xs := zf-yf, ze, !ys
if xf > yf || (xf == yf && !odd) {
	xf, xs = yf, ys
}
for xf < 1<<54 {
	xe--
	xf <<= 1
}
return fpack(xf, xe, xs, RoundOff)

@* 시험. 원본에는 시험 프로그램이 따로 없었다. 원본의 서브루틴들은 \.{silly.mms}처럼
\MMIX\ 시뮬레이터 전체를 돌리는 시험으로 검증되었다. 옮긴이는 64비트로 다시 쓴 이
꾸러미가 원본과 똑같이 동작하는지를 세 겹으로 확인한다.

첫째는 크누스가 본문에 든 예들이다. 이것들을 그대로 못박는다. 둘째는 호스트 기계의
IEEE 부동소수점 장치와 \GO/ 표준 라이브러리를 오라클로 삼는 무작위 시험이다. 호스트
장치는 반올림 방식을 바꾸거나 예외를 읽을 수 없지만, 가장 가까운 쪽 반올림의 결과
값은 정확히 알려 준다. 셋째는 이 문서 밖에서 한 일이다. 크누스의 최신판 \CEE/ 코드를
컴파일해 두 구현에 같은 무작위 입력을 넣고, 3400만 번이 넘는 호출에서 네 반올림 방식
모두의 결과 값과 예외 비트, 출력 문자열, |next| 위치까지 한 비트도 다르지 않음을
확인했다. (다만 앞에서 말한 $0\le x\le9$인 입력은 원본이 정의되지 않은 동작을 하므로,
그때는 원본에 같은 문턱 수정을 입혀 비교했다.)

@(mmixarith_test.go@>=
package mmixarith

import (
	"math"
	"math/big"
	"math/bits"
	"math/rand/v2"
	"strconv"
	"strings"
	"testing"
)

@ 먼저 크누스가 본문에서 든 예들이다. 입력 변환의 예부터 본다.

@(mmixarith_test.go@>=
func TestScanConstExamples(t *testing.T) {
	for _, c := range []struct {
		in   string
		val  Octa
		next int
		kind ConstKind
	}{
		{"-3.", 0xc008000000000000, 3, FloatConst},
		{"1e3", 0x408f400000000000, 3, FloatConst},
		{"1000.", 0x408f400000000000, 5, FloatConst},
		{"1000", 1000, 4, DecimalConst},
		{"NaN", StandardNaN, 3, FloatConst},
		{"+NaN.5", StandardNaN, 6, FloatConst},
		{"NaN.999999999999999999999", 0x7fffffffffffffff, 25, FloatConst},
		{"NaN.0", 0x7ff0000000000001, 5, FloatConst},
		{"9e+9999999999999999", InfOcta, 19, FloatConst},
		{"-00.0e9999999", SignBit, 13, FloatConst},
		{"1e", 1, 1, DecimalConst},
		{"-Inf", InfOcta | SignBit, 4, FloatConst},
		{"x", 0, 0, NoConst},
		{"18446744073709551617", 1, 20, DecimalConst}, // $2^{64}+1$
		{".64352139e333", InfOcta, 13, FloatConst},   // the original \CEE/ crashes here
	} {
		v, n, k := ScanConst(c.in)
		if v != c.val || n != c.next || k != c.kind {
			t.Errorf("ScanConst(%q) = %#x, %d, %d; 원함 %#x, %d, %d",
				c.in, v, n, k, c.val, c.next, c.kind)
		}
	}
}

@ 출력 변환의 예들이다. 크누스가 든 열린 구간의 예 \Hex{44ada56a4b0835bf}와, 그
이웃 \Hex{44ada56a4b0835c0}을 함께 넣었다.

@(mmixarith_test.go@>=
func TestFloatStringExamples(t *testing.T) {
	for _, c := range []struct {
		in  Octa
		out string
	}{
		{0x44ada56a4b0835bf, "6.9999999999999995e22"},
		{0x44ada56a4b0835c0, "7e22"},
		{0x7ff0000000000001, "NaN.0000000000000002"},
		{StandardNaN, "NaN"},
		{InfOcta | SignBit, "-Inf"},
		{SignBit, "-0."},
		{0x4072c00000000000, "300."},
		{0x3f9eb851eb851eb8, ".03"},
		{0x3fb999999999999a, ".1"},
		{0x3ff0000000000000, "1."},
	} {
		if s := FloatString(c.in); s != c.out {
			t.Errorf("FloatString(%#x) = %q; 원함 %q", c.in, s, c.out)
		}
	}
}

@ 경계에 걸린 양 $(1+2^{-53})/2^{1022}$의 정확한 십진 전개는 $(2^{53}+1)\cdot5^{1075}$을
$10^{1075}$으로 나눈 것이다. 타입 |big.Int|로 그 숫자들을 만들어 넣으면 정확히 가운데이므로
짝수 쪽인 \Hex{0010000000000000}이 나와야 하고, 마지막 숫자를 하나 키우거나 0이
아닌 숫자를 뒤에 붙이면 \Hex{0010000000000001}이 나와야 한다.

@(mmixarith_test.go@>=
func TestBorderline(t *testing.T) {
	n := new(big.Int).Lsh(big.NewInt(1), 53)
	n.Add(n, big.NewInt(1))
	n.Mul(n, new(big.Int).Exp(big.NewInt(5), big.NewInt(1075), nil))
	digits := n.String()
	if len(digits) <= 750 {
		t.Fatalf("유효 숫자가 %d개뿐이다", len(digits))
	}
	frac := "." + strings.Repeat("0", 1075-len(digits))
	bumped := digits[:len(digits)-1] + string(digits[len(digits)-1]+1)
	for _, c := range []struct {
		in   string
		want Octa
	}{
		{frac + digits, 0x0010000000000000},
		{frac + bumped, 0x0010000000000001},
		{frac + digits + "0000001", 0x0010000000000001},
	} {
		if v, _, _ := ScanConst(c.in); v != c.want {
			t.Errorf("경계값: %#x; 원함 %#x", v, c.want)
		}
	}
}

@ 나눗셈에서 드문 보정 단계가 필요한 크누스의 예와, 부호 있는 곱셈·나눗셈의 넘침,
예외 비트 몇 가지를 확인한다. 2013년판과 최신판이 갈리는 두 곳---짧은 수의 작음 판정과
덧셈의 문턱---도 최신판의 동작대로 못박는다.

@(mmixarith_test.go@>=
func TestArithExamples(t *testing.T) {
	q, r := Div(0, 0x7fff800100000000, 0x800080020005)
	if q != 0x7fff800100000000/0x800080020005 || r != 0x7fff800100000000%0x800080020005 {
		t.Errorf("Div 보정 예: %#x, %#x", q, r)
	}
	if q, r := Div(5, 7, 5); q != 5 || r != 7 {
		t.Errorf("x>=z일 때 자명한 답이 아니다: %d, %d", q, r)
	}
	if _, _, ov := SignedDiv(SignBit, NegOne); !ov {
		t.Error("-2^63/-1은 넘쳐야 한다")
	}
	if _, ov := SignedMult(1<<32, 1<<31); !ov {
		t.Error("2^63은 부호 있는 곱으로 넘쳐야 한다")
	}
	if _, ov := SignedMult(1<<32, 0xffffffff80000000); ov {
		t.Error("-2^63은 부호 있는 곱으로 넘치지 않는다")
	}
	one, three := Octa(0x3ff0000000000000), Octa(0x4008000000000000)
	if _, e := FDivide(one, 0, RoundNear); e != ZBit {
		t.Errorf("1/0의 예외 %#x", e)
	}
	if _, e := FDivide(one, three, RoundNear); e != XBit {
		t.Errorf("1/3의 예외 %#x", e)
	}
	if _, e := FPlus(InfOcta, InfOcta|SignBit, RoundNear); e != IBit {
		t.Errorf("inf-inf의 예외 %#x", e)
	}
	@<2013년판과 최신판이 갈리는 곳을 못박는다@>
}

@ @<2013년판과 최신판이 갈리는 곳을 못박는다@>=
if z, e := StoreSF(0x3800000000000000, RoundNear); z != 0x00400000 || e != UBit {
	t.Errorf("StoreSF(2^-127) = %#x, %#x", z, e)
}
if x, _ := FPlus(0xc3f0000000000000, 0x409cf4b4d61b9dbe, RoundNear); x != 0xc3efffffffffffff {
	t.Errorf("-2^64+1853.17... = %#x", x)
}

@ 무작위 시험에 쓸 옥타바이트를 만든다. 순전히 무작위인 64비트 패턴은 거의 언제나
평범한 정규수이므로, 특별한 값들, 비정규수, 1 근처의 수, 지수가 가까운 두 수를
일부러 섞는다. 이 함수는 여러 시험에서 부른다.

@(mmixarith_test.go@>=
var specials = [...]Octa{0, InfOcta, StandardNaN, 0x7ff0000000000001, 1,
	0x000fffffffffffff, 0x0010000000000000, 0x7fefffffffffffff,
	0x3ff0000000000000, 0x43e0000000000000, 0x43f0000000000000}

func randOcta(r *rand.Rand) Octa {
	switch r.IntN(8) {
	case 0:
		return specials[r.IntN(len(specials))] | Octa(r.IntN(2))<<63
	case 1:
		return r.Uint64() & 0x800fffffffffffff // subnormal
	case 2:
		return r.Uint64()&0x800fffffffffffff | Octa(0x3e0+r.IntN(64))<<52
	case 3:
		return r.Uint64()&0xfff0000000000000 | r.Uint64()&0xff // near an integer
	default:
		return r.Uint64()
	}
}

func randPair(r *rand.Rand) (Octa, Octa) {
	y := randOcta(r)
	if r.IntN(2) == 0 {
		return y, randOcta(r)
	}
	e := int(y>>52&0x7ff) + r.IntN(120) - 60
	e = min(max(e, 0), 0x7fe)
	return y, r.Uint64()&0x800fffffffffffff | Octa(e)<<52
}

@ 이제 호스트 기계와 비교한다. 결과가 둘 다 NaN이면 넘어간다. 호스트의 NaN 비트
패턴은 기계마다 다르고 \MMIX의 규칙과도 다르기 때문이다. \GO/ 명세는 여러 부동소수점
연산을 하나로 합쳐(fused) 계산하는 것을 허락하지만, 여기서는 연산을 하나씩만 하므로
그럴 일이 없다.

@(mmixarith_test.go@>=
func same(got Octa, want float64) bool {
	g := math.Float64frombits(got)
	return got == math.Float64bits(want) || (g != g && want != want)
}

func TestAgainstHardware(t *testing.T) {
	rng := rand.New(rand.NewPCG(1999, 2026))
	f := math.Float64frombits
	for range 300000 {
		y, z := randPair(rng)
		@<네 가지 산술 연산과 제곱근을 호스트와 비교한다@>
		@<정수화와 고정·부동 변환을 호스트와 비교한다@>
		@<짧은 수의 적재와 저장을 호스트와 비교한다@>
	}
}

@ @<네 가지 산술 연산과...@>=
if x, _ := FPlus(y, z, RoundNear); !same(x, f(y)+f(z)) {
	t.Fatalf("FPlus(%#x, %#x) = %#x", y, z, x)
}
if x, _ := FMult(y, z, RoundNear); !same(x, f(y)*f(z)) {
	t.Fatalf("FMult(%#x, %#x) = %#x", y, z, x)
}
if x, _ := FDivide(y, z, RoundNear); !same(x, f(y)/f(z)) {
	t.Fatalf("FDivide(%#x, %#x) = %#x", y, z, x)
}
if x, _ := FRoot(z, RoundNear); !same(x, math.Sqrt(f(z))) {
	t.Fatalf("FRoot(%#x) = %#x", z, x)
}
if x, _ := FRemStep(y, z, 2500); !same(x, math.Remainder(f(y), f(z))) {
	t.Fatalf("FRemStep(%#x, %#x) = %#x", y, z, x)
}
want := 2 // unordered
switch fy, fz := f(y), f(z); {
case fy < fz:
	want = -1
case fy > fz:
	want = 1
case fy == fz:
	want = 0
}
if c := FComp(y, z); c != want {
	t.Fatalf("FComp(%#x, %#x) = %d", y, z, c)
}

@ 반올림 방식 넷 모두를 호스트의 |math| 함수와 비교할 수 있는 것이 정수화다.
고정소수점으로 바꾸는 것은 결과가 |int64| 범위 안일 때만 비교한다.

@(mmixarith_test.go@>=
var integerizers = map[Round]func(float64) float64{
	RoundOff: math.Trunc, RoundUp: math.Ceil,
	RoundDown: math.Floor, RoundNear: math.RoundToEven,
}

@ @<정수화와 고정·부동...@>=
for mode, g := range integerizers {
	if x, _ := FIntegerize(z, mode); !same(x, g(f(z))) {
		t.Fatalf("FIntegerize(%#x, %d) = %#x", z, mode, x)
	}
}
if w := math.RoundToEven(f(z)); math.Abs(w) < 1<<63 {
	if x, _ := FixIt(z, RoundNear); x != Octa(int64(w)) {
		t.Fatalf("FixIt(%#x) = %#x", z, x)
	}
}
if x, _ := FloatIt(y, RoundNear, false, false); !same(x, float64(int64(y))) {
	t.Fatalf("FloatIt(%#x) = %#x", y, x)
}
if x, _ := FloatIt(y, RoundNear, true, false); !same(x, float64(y)) {
	t.Fatalf("FloatIt(%#x, 부호 없음) = %#x", y, x)
}
if x, _ := FloatIt(y, RoundNear, false, true); !same(x, float64(float32(int64(y)))) {
	t.Fatalf("FloatIt(%#x, 짧음) = %#x", y, x)
}

@ @<짧은 수의 적재와...@>=
if s, _ := StoreSF(z, RoundNear); f(z) == f(z) && s != math.Float32bits(float32(f(z))) {
	t.Fatalf("StoreSF(%#x) = %#x", z, s)
}
if w := Tetra(y); math.Float32frombits(w) == math.Float32frombits(w) &&
	LoadSF(w) != math.Float64bits(float64(math.Float32frombits(w))) {
	t.Fatalf("LoadSF(%#x) = %#x", w, LoadSF(w))
}

@ 출력 변환에는 두 가지를 요구한다. 찍은 문자열을 |ScanConst|로 다시 읽으면 원래
값이 정확히 나와야 한다(NaN도 포함). 그리고 유효 숫자의 개수가, 가장 짧은 표현을 찾는
|strconv.FormatFloat|의 것과 같아야 한다. 입력 변환은 무작위 십진 문자열에 대해
|strconv.ParseFloat|와 비교한다. 둘 다 정확히 반올림하므로 결과가 같아야 한다.

@(mmixarith_test.go@>=
func sigDigits(s string) int {
	if i := strings.IndexAny(s, "e"); i >= 0 {
		s = s[:i]
	}
	s = strings.Trim(strings.Map(func(c rune) rune {
		if '0' <= c && c <= '9' {
			return c
		}
		return -1
	}, s), "0")
	return len(s)
}

func TestFloatStringRoundTrip(t *testing.T) {
	rng := rand.New(rand.NewPCG(1750, 1999))
	for range 200000 {
		x := randOcta(rng)
		s := FloatString(x)
		if v, n, k := ScanConst(s); v != x || n != len(s) || k != FloatConst {
			t.Fatalf("%#x -> %q -> %#x", x, s, v)
		}
		fx := math.Float64frombits(x)
		if fx == fx && !math.IsInf(fx, 0) && fx != 0 {
			if a, b := sigDigits(s), sigDigits(strconv.FormatFloat(fx, 'e', -1, 64)); a != b {
				t.Fatalf("%#x -> %q: 유효 숫자 %d개, strconv는 %d개", x, s, a, b)
			}
		}
	}
}

@ @(mmixarith_test.go@>=
func TestScanConstAgainstStrconv(t *testing.T) {
	rng := rand.New(rand.NewPCG(308, 324))
	for range 200000 {
		var sb strings.Builder
		for range 1 + rng.IntN(25) {
			sb.WriteByte(byte('0' + rng.IntN(10)))
		}
		s := sb.String()
		i := rng.IntN(len(s) + 1)
		s = s[:i] + "." + s[i:] + "e" + strconv.Itoa(rng.IntN(700)-350)
		if s[0] == '.' && (len(s) == 1 || !isDigit(s[1])) {
			continue
		}
		v, _, _ := ScanConst(s)
		w, _ := strconv.ParseFloat(s, 64)
		if v != math.Float64bits(w) {
			t.Fatalf("ScanConst(%q) = %#x; strconv는 %#x", s, v, math.Float64bits(w))
		}
	}
}

@ 끝으로 정수 연산과 비트 연산을 느리지만 뻔한 방법과 비교한다. 부호 있는 곱셈은
|big.Int|로, 부호 있는 나눗셈은 몫을 $-\infty$쪽으로 내리는 정의로, 바이트·와이드
차이와 \.{MOR}·\.{MXOR}는 자리 하나씩 계산하는 방법으로 확인한다.

@(mmixarith_test.go@>=
func TestIntegerOps(t *testing.T) {
	rng := rand.New(rand.NewPCG(64, 32))
	for range 300000 {
		y, z := randOcta(rng), randOcta(rng)
		if rng.IntN(4) == 0 {
			z >>= rng.IntN(64)
		}
		@<부호 있는 곱셈을 확인한다@>
		@<부호 있는 나눗셈을 확인한다@>
		@<바이트·와이드 차이와 불 행렬 곱을 확인한다@>
	}
}

@ @<부호 있는 곱셈을 확인한다@>=
p := new(big.Int).Mul(big.NewInt(int64(y)), big.NewInt(int64(z)))
if x, ov := SignedMult(y, z); x != Octa(int64(y)*int64(z)) || ov != !p.IsInt64() {
	t.Fatalf("SignedMult(%#x, %#x) = %#x, %v", y, z, x, ov)
}

@ @<부호 있는 나눗셈을 확인한다@>=
if z != 0 && !(y == SignBit && z == NegOne) {
	a, b := int64(y), int64(z)
	wq, wr := a/b, a%b
	if wr != 0 && (wr < 0) != (b < 0) {
		wq, wr = wq-1, wr+b
	}
	if q, r, ov := SignedDiv(y, z); q != Octa(wq) || r != Octa(wr) || ov {
		t.Fatalf("SignedDiv(%#x, %#x) = %#x, %#x, %v", y, z, q, r, ov)
	}
}

@ @<바이트·와이드 차이와 불 행렬 곱을 확인한다@>=
var bd, wd, mor, mxor Octa
for i := 0; i < 64; i += 8 {
	bd |= Octa(max(int(y>>i&0xff)-int(z>>i&0xff), 0)) << i
	for k := range 8 {
		if z>>(i+k)&1 != 0 {
			mor |= (y >> (8 * k) & 0xff) << i
			mxor ^= (y >> (8 * k) & 0xff) << i
		}
	}
}
for i := 0; i < 64; i += 16 {
	wd |= Octa(max(int(y>>i&0xffff)-int(z>>i&0xffff), 0)) << i
}
if ByteDiff(y, z) != bd || WydeDiff(y, z) != wd ||
	BoolMult(y, z, false) != mor || BoolMult(y, z, true) != mxor ||
	bits.OnesCount64(y&^z) != bits.OnesCount64(y)-bits.OnesCount64(y&z) {
	t.Fatalf("비트 연산 (%#x, %#x)", y, z)
}

@* 찾아보기.
