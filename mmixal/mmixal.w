% 이 파일은 MMIXware의 mmixal.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w


\input kotexgweb
\def\title{MMIXAL}

@* MMIXAL의 정의. 이 프로그램은 \MMIX의 어셈블리 언어인 \MMIXAL로 쓴 입력을
받아서, \MMIX\ 시뮬레이터에 적재해 실행할 수 있는 이진 파일로 번역한다.
@^assembly language@>
\MMIXAL은 컴퓨터 제조사들이 흔히 내놓는 ``산업용'' 어셈블리 언어보다 훨씬
단순하다. 무엇보다 {\sl The Art of Computer Programming}에 나오는 간단한 시범
프로그램들을 위해 만든 것이기 때문이다. 그래도 \CEE/를 비롯한 고급 언어 컴파일러의
뒷단(back end) 노릇도 할 수 있을 만큼의 기능은 갖추려고 한다.

프로그램을 쓰는 방법은 이 문서의 끝에 나온다. 먼저 입력 언어와 출력 언어를 자세히
살펴보고, 그다음 번역 과정을 한 걸음씩 짚은 뒤, 모든 것을 한데 모을 것이다.

@ 옮긴이가 보충한다. 이 문서는 크누스의 \.{mmixal.w}를 \GO/로 옮긴 것이다. 원본은
절 번호가 없는 긴 \CEE/ 프로그램 하나이고, 전역 변수 수십 개와 |goto| 문 수십 개로
이루어져 있다. 옮긴이는 다음과 같이 바꾸었다.
\smallskip
\item{$\bullet$} 전역 변수들은 모두 구조체 |assembler|의 필드가 되었다. 그래서 한
프로세스 안에서 어셈블러를 여러 번 돌릴 수 있고, 시험 프로그램이 파일을 실제로
어셈블해 보고 결과를 원본의 것과 비교할 수 있다.
\item{$\bullet$} 원본의 오류 매크로 |err|는 오류를 보고한 다음, 경고가 아니면 |goto
bypass|로 현재 명령의 나머지를 건너뛰었다. 여기서는 |err|가 특별한 값으로 공황(panic)을
일으키고, 명령 하나를 처리하는 코드를 감싼 함수가 그것을 되살린다(recover). 표준
라이브러리의 구문 분석기들도 오류에서 빠져나올 때 이 방법을 쓴다. 치명적 오류도
같은 방법으로 맨 바깥까지 빠져나온다.
\item{$\bullet$} 그 밖의 |goto| 문들은 이름표 붙은 |break|와 |continue|로 바꾸었다.
\item{$\bullet$} 옥타바이트는 \.{mmixarith} 꾸러미에서처럼 |uint64|다.
\smallskip\noindent
다음은 이 프로그램 전체의 뼈대다. 크누스의 원본에서는 이것이 맨 끝의 ``프로그램
실행하기'' 장에 있었다.

@c
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"time"
	@#
	"github.com/sjnam/go-mmix/mmixarith"
)

@<타입 정의@>
@<상수@>
@<표@>
@<함수들@>
@<|mmixal| 함수@>
@<|main| 함수@>

@ \MMIXAL\ 프로그램은 {\it 줄\/}들의 연속이고, 한 줄에는 대개 명령이 하나 들어 있다.
그러나 명령이 없는 줄도 있을 수 있고, 명령이 둘 이상인 줄도 있을 수 있다.

명령마다 레이블 필드, 연산 코드 필드, 피연산자 필드라는 세 부분이 있다. 이 필드들은
하나 이상의 공백으로 서로 떨어져 있다. 레이블 필드는 흔히 비어 있는데, 첫 공백 문자
앞까지의 모든 문자로 이루어진다. 연산 코드 필드는 결코 비어 있지 않으며, 레이블 다음의
첫 비공백 문자부터 그다음 공백까지다. 피연산자 필드는 역시 비어 있을 수 있는데, 그다음
비공백 문자(있다면)부터, 문자열 상수나 문자 상수의 일부가 아닌 첫 공백이나 쌍반점까지다.
피연산자 필드 뒤에 쌍반점이 오면(사이에 공백이 있어도 된다) 쌍반점 바로 뒤에서 새 명령이
시작한다. 그렇지 않으면 줄의 나머지는 무시된다. 이 규칙들에서 줄의 끝은 공백으로 취급된다.
다만 문자열 상수와 문자 상수는 한 줄에서 다음 줄로 이어질 수 없다는 단서가 붙는다.

레이블 필드는 글자나 숫자로 시작해야 한다. 그렇지 않으면 줄 전체가 주석으로 취급된다.
주석을 다는 흔한 방법은, 줄의 처음이든 피연산자 필드 뒤든, \TeX에서처럼 문자 \.\%를
앞세우거나 \CPLUSPLUS/에서처럼 \.{//}를 앞세우는 것이다. \MMIXAL은 그리 까다롭지 않다.
그러나 Lisp 식으로 쌍반점 하나로 시작하는 주석은 명령 뒤에 오면 실패한다. 새 명령을
시작하는 것으로 여겨지기 때문이다.

@ \MMIXAL에는 매크로 기능이 없고, 머리 파일(header file)을 끌어들이는 방법 같은 것도
모른다. 그러나 사용자는 파일을 표준 \CEE/ 전처리기에 통과시켜서, 매크로 따위가 펼쳐진
\MMIXAL\ 프로그램을 얻을 수 있다. (주의: 전처리기는 따로 일러 주지 않으면 \CEE/ 식
주석도 없앤다.) 문학적 프로그래밍 도구도 전처리에 쓸 수 있을 것이다.
@^C preprocessor@>
@^literate programming@>

줄이 `\.\# \<integer> \<string>'이라는 특별한 꼴로 시작하면, 이 프로그램은 그것을
전처리기가 내보낸 {\it 줄 지시문\/}({\it line directive\/})으로 해석한다. 예컨대
$$\leftline{\indent\.{\# 13 "foo.mms"}}$$
는 다음 줄이 사용자의 소스 파일 \.{foo.mms}의 13번째 줄이었다는 뜻이다. 줄 지시문
덕분에 우리는 오류를 사용자의 원래 파일과 맞대어 볼 수 있다. 우리는 이것을 출력에도
넘겨주어 시뮬레이터와 디버거가 쓸 수 있게 한다.
@^line directives@>

@ \MMIXAL은 주로 {\it 기호\/}와 {\it 상수\/}를 다루며, 이것들을 해석하고 조합해서
기계어 명령과 데이터를 만든다. 상수가 가장 간단하므로 먼저 살펴보자.

{\it 십진 상수\/}는 기수~10으로 수를 나타내는 숫자들의 나열이다. {\it 십육진 상수\/}는
\.\#를 앞세운 십육진 숫자들의 나열로서, 기수~16으로 수를 나타낸다.
$$\vbox{\halign{$#$\hfil\cr
\<digit>\is\.0\mid\.1\mid\.2\mid\.3\mid\.4\mid
        \.5\mid\.6\mid\.7\mid\.8\mid\.9\cr
\<hex digit>\is\<digit>\mid\.A\mid\.B\mid\.C\mid\.D\mid\.E\mid\.F\mid
        \.a\mid\.b\mid\.c\mid\.d\mid\.e\mid\.f\cr
\<decimal constant>\is\<digit>\mid\<decimal constant>\<digit>\cr
\<hex constant>\is\.\#\<hex digit>\mid\<hex constant>\<hex digit>\cr
}}$$
값이 $2^{64}$ 이상인 상수는 $2^{64}$을 법으로 줄인다.

@ {\it 문자 상수\/}는 작은따옴표로 둘러싼 문자 하나로, 그 문자에 해당하는 {\mc ASCII}
번호나 유니코드 번호를 나타낸다.
@^Unicode@>
예컨대 \.{'a'}는 상수 \.{\#61}, 곧 \.{97}을 나타낸다. 따옴표 안의 문자는 \CEE/
라이브러리가 \.{\\n}, 곧 {\it 줄바꿈\/}이라고 부르는 문자만 빼면 무엇이든 될 수 있다.
줄바꿈 문자는 \.{\#a}로 나타내야 한다.
$$\vbox{\halign{$#$\hfil\cr
\<character constant>\is\.'\<single byte character except newline>\.'\cr
\<constant>\is\<decimal constant>\mid\<hex constant>\mid\<character constant>
\cr}}$$
\.{'''}는 작은따옴표 하나, 곧 코드 \.{\#27}을 나타내고, \.{'\\'}는 역빗금, 곧 코드
\.{\#5c}를 나타낸다는 데 주목하라. \MMIXAL의 문자들은 \CEE/ 언어에서처럼 역빗금으로
``따옴표 처리''되는 일이 결코 없다.

현재의 구현에서는 와이드 문자 입력을 지원하지 않으므로 문자 상수는 늘 255 이하다.
입력이 유니코드라면, 이를테면 \.{'Ж'}라고 써서 \.{\#0416}을 나타낼 수 있을 것이다.
(원본은 특별한 글꼴이 준비되어 있을 때만 이 예와 히브리 문자 알레프의 예를 찍었다.
이 한글판은 유니코드를 곧바로 다루는 Lua\TeX으로 조판하므로 키릴 문자는 그냥 찍힌다.
히브리 문자는 우리 글꼴에 없어서 뺐다.) 지금의 프로그램이 유니코드를 곧바로 지원하지
않는 것은, 이 글을 쓸 당시 16비트 문자를 입력하고 출력하는 기본 소프트웨어가 아직
원시적인 상태였기 때문이다. 그러나 아래의 데이터 구조들은 때가 무르익었을 때
유니코드로 바꾸기가 어렵지 않도록 설계되어 있다.

@ \.{"Hello"} 같은 {\it 문자열 상수\/}는 반점으로 구분된 하나 이상의 문자 상수들을
줄여 쓴 것이다: \.{'H','e','l','l','o'}. 줄바꿈과 큰따옴표~\."를 뺀 어떤 문자든
문자열 상수의 큰따옴표 사이에 올 수 있다. 마찬가지로 유니코드가 지원되면 \."高德纳\."는
\.'高\.{','}德\.{','}纳\.'(곧 \.{\#9ad8,\#5fb7,\#7eb3})를 줄여 쓴 것이 된다.
@^Unicode@>

보충: 이 세 글자는 크누스의 중국어 이름 ``가오더나''다. 원본은 이 예를 유니코드 글꼴이
있을 때만 비트맵으로 찍었다.
@^Knuth, Donald Ervin@>

@ \MMIXAL의 {\it 기호\/}는 글자로 시작하는, 글자와 숫자의 임의의 나열이다. 이 정의에서
쌍점~`\.:'과 밑줄 `\.\_'은 글자로 친다. 8비트 코드가 126을 넘는 `{\tt \'e}' 같은
확장 {\mc ASCII} 문자들도 모두 글자로 취급된다.
$$\vbox{\halign{$#$\hfil\cr
\<letter>\is\.A\mid\.B\mid\cdots\mid\.Z\mid\.a\mid\.b\mid\cdots\mid\.z\mid
        \.:\mid\.\_\mid\<{character with code value $>126$}>\cr
\<symbol>\is\<letter>\mid\<symbol>\<letter>\mid\<symbol>\<digit>\cr
}}$$

앞으로의 구현에서 \MMIXAL을 유니코드와 함께 쓰게 되면, 16비트 코드가 126을 넘는 모든
와이드 문자가 글자로 여겨질 것이다. 그러면 \MMIXAL의 기호에 그리스 문자나 한자를 비롯한
수천 가지 글리프가 들어갈 수 있게 될 것이다.
@^Unicode@>

@ 쌍점으로 시작하는 기호를 {\it 완전히 한정되었다\/}({\it fully qualified\/})고 한다. 완전히
한정되지 않은 기호는 모두, 그 앞에 {\it 현재 접두어\/}를 붙여서 얻는 완전히 한정된
기호를 줄여 쓴 것이다. 현재 접두어는 늘 완전히 한정되어 있다. \MMIXAL\ 프로그램이
시작할 때 현재 접두어는 문자 하나 `\.:'뿐이지만, 사용자는 \.{PREFIX} 명령으로 이것을
바꿀 수 있다. 예를 들면 다음과 같다.
$$\vbox{\halign{&\quad\tt#\hfil\cr
ADD&x,y,z&\% means ADD :x,:y,:z\cr
PREFIX&Foo:&\% current prefix is :Foo:\cr
ADD&x,y,z&\% means ADD :Foo:x,:Foo:y,:Foo:z\cr
PREFIX&Bar:&\% current prefix is :Foo:Bar:\cr
ADD&:x,y,:z&\% means ADD :x,:Foo:Bar:y,:z\cr
PREFIX&:&\% current prefix reverts to :\cr
ADD&x,Foo:Bar:y,Foo:z&\% means ADD :x,:Foo:Bar:y,:Foo:z\cr
}}$$
이 방법을 쓰면, 프로그램의 부분들이 서로 독립적이거나 서로 다른 사용자가 쓴 큰
프로그램에서 기호 이름이 부딪치는 것을 피할 수 있다. 현재 접두어는 관례상 쌍점으로
끝나지만, 이 관례를 꼭 지켜야 하는 것은 아니다.

@ {\it 지역 기호\/}는 십진 숫자 하나 뒤에 글자 \.B, \.F, \.H 가운데 하나가 붙은 것으로,
각각 ``뒤쪽(backward),'' ``앞쪽(forward),'' ``여기(here)''를 뜻한다.
$$\vbox{\halign{$#$\hfill\cr
\<local operand>\is\<digit>\,\.B\mid\<digit>\,\.F\cr
\<local label>\is\<digit>\,\.H\cr
}}$$
\.B와 \.F 꼴은 \MMIXAL\ 명령의 피연산자 필드에서만 쓸 수 있고, \.H 꼴은 레이블
필드에서만 쓸 수 있다. \.{2B} 같은 지역 피연산자는 현재 명령보다 앞선 명령들 가운데
마지막 지역 레이블~\.{2H}를 뜻하며, \.{2H}가 아직 레이블로 나온 적이 없으면 0을 뜻한다.
\.{2F} 같은 지역 피연산자는 현재 명령 뒤의 명령들 가운데 첫 \.{2H}를 뜻한다. 그래서
$$\vbox{\halign{\tt#\cr 2H JMP 2F\cr 2H JMP 2B\cr}}$$
같은 순서에서 첫 명령은 둘째 명령으로 뛰고, 둘째 명령은 첫 명령으로 뛴다.

지역 기호는 의미 있는 이름을 붙이기 알맞지 않은 곳에서 프로그램의 가까운 지점들을
가리킬 때 쓸모가 있다. 또한 다시 정의할 수 있는 기호가 필요한 특별한 상황에서도
쓸모가 있다. 예를 들어
$$\.{9H IS 9B+1}$$
같은 명령은 계속 늘어나는 셈값 하나를 유지한다.

@ 기호가 명령의 레이블 필드에 나타나면 {\it 등가\/}({\it equivalent\/})라는 값을 받는다.
등가가 정해진 뒤의 기호를 {\it 정의되었다\/}고 한다. \.{rA}와 \.{ROUND\_OFF}와 \.{Fopen}처럼
몇몇 기호는 \MMIX\ 하드웨어나 그 초보적인 운영체제에 딸린 고정된 상수를 가리키므로
미리 정의되어 있다. 그 밖의 모든 기호는 정확히 한 번 정의되어야 한다. 앞의 예에서
`\.{2H}'가 두 번 나오는 것은 이 규칙을 어기지 않는다. 둘째 `\.{2H}'는 첫째와 같은 기호가
아니기 때문이다.

미리 정의된 기호는 다시 정의할 수 있다(새 등가를 줄 수 있다). 다시 정의된 기호는 보통의
기호처럼 행동하며, 또다시 정의할 수는 없다. 미리 정의된 기호의 완전한 목록은 아래의
프로그램 목록에 나온다.
@^predefined symbols@>

등가는 {\it 순수한\/}({\it pure\/}) 값이거나 {\it 레지스터 번호\/}다. 순수한 등가는 부호 없는
옥타바이트이고, 레지스터 번호 등가는 0과~255 사이의 한 바이트 값이다. 순수한 수를 레지스터
번호로 바꿀 때는 달러 기호를 쓴다. 예컨대 `\.{\$20}'은 레지스터 번호~20을 뜻한다.

@ 상수와 기호는 간단한 방법으로 조합되어 {\it 식\/}을 이룬다.
$$\vbox{\halign{$#$\hfil\cr
\<primary expression>\is\<constant>\mid\<symbol>\mid\<local operand>\mid
  \.{@@}\mid\cr
\hskip12pc\.(\<expression>\.)\mid\<unary operator>\<primary expression>\cr
\<term>\is\<primary expression>\mid
  \<term>\<strong operator>\<primary expression>\cr
\<expression>\is\<term>\mid\<expression>\<weak operator>\<term>\cr
\<unary operator>\is\.+\mid\.-\mid\.\~\mid\.\$\mid\.\&\cr
\<strong operator>\is\.*\mid\./\mid\.{//}\mid\.\%\mid\.{<<}\mid\.{>>}
       \mid\.\&\cr
\<weak operator>\is\.+\mid\.-\mid\.{\char'174}\mid\.\^\cr
}}$$
식마다 값이 있는데, 그 값은 순수하거나 레지스터 번호다. 문자 \.{@@}는 현재 위치를 나타내며,
현재 위치는 늘 순수하다. 단항 연산자 \.+, \.-, \.\~, \.\$, \.\&는 차례로 ``아무것도 하지
않는다,'' ``0에서 뺀다,'' ``비트를 뒤집는다,'' ``순수한 값을 레지스터 번호로 바꾼다,''
``일련번호를 얻는다''를 뜻한다. 이 가운데 첫째인 \.+만 레지스터 번호에 적용할 수 있다.
마지막 단항 연산자 \.\&는 기호에만 적용되며, 주로 시스템 프로그래머의 관심거리다. 이
연산자는 기호를, \MMIXAL이 내놓는 이진 파일에서 그 기호를 식별하는 데 쓰이는 유일한 양의
정수로 바꾼다.
@^serial number@>

이항 연산자는 강한 것과 약한 것 두 가지 맛이 있다. 강한 연산자들은 본질적으로 곱셈이나
나눗셈과 관계가 있다: \.{x*y}, \.{x/y}, \.{x//y}, \.{x\%y}, \.{x<<y}, \.{x>>y},
\.{x\&y}는 부호 없는 옥타바이트에 대해 차례로 $(x\times y)\bmod2^{64}$(곱셈),
$\lfloor x/y\rfloor$(나눗셈), $\lfloor2^{64}x/y\rfloor$(분수 나눗셈), $x\bmod y$(나머지),
$(x\times2^y)\bmod2^{64}$(왼쪽 자리 옮김), $\lfloor x/2^y\rfloor$(오른쪽 자리 옮김),
$x\mathbin{\char`\&}y$(비트별 논리곱)를 뜻한다. 나눗셈은 $y>0$일 때만 적법하고, 분수
나눗셈은 $x<y$일 때만 적법하다. 강한 이항 연산은 어느 것도 레지스터 번호에 적용할 수
없다.

약한 이항 연산 \.{x+y}, \.{x-y}, \.{x\char'174 y}, \.{x\^y}는 부호 없는 옥타바이트에
대해 차례로 $(x+y)\bmod2^{64}$(덧셈), $(x-y)\bmod2^{64}$(뺄셈),
$x\mathbin{\mkern1mu\vert\mkern1mu}y$(비트별 논리합), $x\oplus y$(비트별 배타적 논리합)를
뜻한다. 이 연산들은 네 가지 경우에만 레지스터 번호에 적용할 수 있다:
$\<register>+\<pure>$, $\<pure>+\<register>$, $\<register>-\<pure>$,
$\<register>-\<register>$. 예컨대 \.{x}가 \.{\$1}을 나타내고 \.{y}가 \.{\$10}을
나타내면, \.{x+3}과 \.{3+x}는 \.{\$4}를 나타내고, \.{y-x}는 순수한 값 \.{9}를 나타낸다.

식 안에서 레지스터 번호는 임의의 옥타바이트일 수 있지만, 기호의 등가로 주는 레지스터
번호는 255를 넘으면 안 된다.

(내친김에, \MMIXAL의 설계자가 왜 \CEE/의 식 규칙을 그냥 받아들이지 않았는지 물을 수도
있겠다. 주된 까닭은 \CEE/의 설계자들이 \.{<<}, \.{>>}, \.\&에 \.+보다 낮은 우선순위를
주기로 했기 때문이다. 그러나 \MMIXAL에서는 \.{o<<24+x<<16+y<<8+z}나 \.{@@+yz<<2}나
\.{@@+(\#100-@@)\&\#ff} 같은 것을 쓸 수 있기를 바란다. \CEE/의 관례가 알맞지 않았으므로,
그 언어와 가까운 관계인 척하지 않고 깨끗이 갈라서는 편이 나았다. 새 규칙은 아주 쉽게
외워진다. \MMIXAL에는 우선순위가 두 단계밖에 없고, 강한 이항 연산은 모두 본질적으로
곱셈 같은 것이며 약한 이항 연산은 모두 본질적으로 덧셈 같은 것이기 때문이다.)

@ 기호는 정의되기 전까지 {\it 앞선 참조\/}({\it future reference\/})라고 부른다. \MMIXAL은
앞선 참조의 사용을 제한해서, 입력을 한 번만 훑어서 빨리 어셈블할 수 있게 한다. 그래서 모든
식은 \MMIXAL\ 처리기가 처음 볼 때 값을 매길 수 있다.

제한은 쉽게 말할 수 있다. 앞선 참조는 단항 연산자나 이항 연산자와 함께 식에 쓸 수 없다
(아무것도 하지 않는 단항 \.+는 예외다). 게다가 앞선 참조는 상대 주소를 가진 명령(곧
분기, 확률 분기, \.{JMP}, \.{PUSHJ}, \.{GETA})의 피연산자로만, 또는 옥타바이트 상수
(유사 연산 \.{OCTA})에서만 쓸 수 있다. 그래서 예를 들어 \.{JMP}~\.{1F}나
\.{JMP}~\.{1B-4}라고는 쓸 수 있지만 \.{JMP}~\.{1F-4}라고는 쓸 수 없다.

@ 앞에서 우리는 \MMIXAL\ 명령마다 레이블 필드, 연산 코드 필드, 피연산자 필드가 있다고
했다. 레이블 필드는 비어 있거나 기호 또는 지역 레이블이다. 비어 있지 않으면 그 기호나
지역 레이블이 등가를 받는다. 피연산자 필드는 비어 있거나 반점으로 구분된 식들의
나열이다. 비어 있으면 단순한 피연산자 필드~`\.0'과 같다.
$$\vbox{\halign{$#$\hfil\cr
\<instruction>\is\<label>\<opcode>\<operand list>\cr
\<label>\is\<empty>\mid\<symbol>\mid\<local label>\cr
\<operand list>\is\<empty>\mid\<expression list>\cr
\<expression list>\is\<expression>\mid\<expression list>\.,\<expression>\cr
}}$$

연산 코드 필드에는 (\.{ADD} 같은) 기호로 된 \MMIX\ 연산 이름, 또는 {\it 별칭 연산\/}
({\it alias operation\/}), 또는 {\it 유사 연산\/}({\it pseudo-operation\/})이 들어 있다. 별칭 연산은
표준 이름이 어떤 맥락에서 어울리지 않는 \MMIX\ 연산들의 다른 이름이다. 유사 연산은
\MMIX\ 명령에 곧바로 대응하지는 않지만, 어셈블 과정을 중요한 방식으로 이끈다.

별칭 연산은 둘이다.

\bull \.{SET} \.{\$X,\$Y}는 \.{OR} \.{\$X,\$Y,0}과 같다. 레지스터~X를 레지스터~Y로
정한다. 마찬가지로 \.{SET} \.{\$X,Y}는 (\.Y가 레지스터가 아니면) \.{SETL} \.{\$X,Y}와
같다.
@.SET@>

\bull \.{LDA} \.{\$X,\$Y,\$Z}는 \.{ADDU} \.{\$X,\$Y,\$Z}와 같다. 메모리 위치
$\rm \$Y+\$Z$의 주소를 레지스터~X에 적재한다. 마찬가지로 \.{LDA} \.{\$X,\$Y,Z}는
\.{ADDU} \.{\$X,\$Y,Z}와 같다.
@.LDA@>

\smallskip
진짜 \MMIX\ 연산의 기호 이름에는 즉치(immediate) 연산을 나타내는 접미어~\.I나 뒤로
뛰는 것을 나타내는 접미어~\.B를 붙이지 말아야 한다. 그런 것은 \MMIXAL이 저절로 정한다.
그래서 \MMIXAL의 소스 입력에는 \.{ADDI}나 \.{JMPB}를 결코 쓰지 않는다. 다만
시뮬레이터나 디버거나 역어셈블러가 수치 명령을 기호로 보여 줄 때는 그런 연산 코드가
나타날 수도 있다.
$$\vbox{\halign{$#$\hfil\cr
\<opcode>\is\<symbolic \MMIX\ operation>\mid\<alias operation>\cr
\hskip12pc\mid\<pseudo-operation>\cr
\<symbolic \MMIX\ operation>\is\.{TRAP}\mid\.{FCMP}\mid\cdots\mid\.{TRIP}\cr
\<alias operation>\is\.{SET}\mid\.{LDA}\cr
\<pseudo-operation>\is\.{IS}\mid\.{LOC}\mid\.{PREFIX}\mid
   \.{GREG}\mid\.{LOCAL}\mid\.{BSPEC}\mid\.{ESPEC}\cr
\hskip12pc\mid\.{BYTE}\mid\.{WYDE}\mid\.{TETRA}\mid\.{OCTA}\cr
}}$$

@ \.{ADD} 같은 \MMIX\ 연산은 피연산자로 정확히 식 세 개를 요구한다. 처음 둘은
레지스터 번호여야 한다. 셋째는 레지스터 번호이거나 0과~255 사이의 순수한 수여야 한다.
뒤의 경우에 \.{ADD}는 어셈블된 출력에서 \.{ADDI}가 된다. 그래서 예컨대 ``레지스터~2와
레지스터~3의 합을 레지스터~1에 넣어라''라는 명령은
$$\.{ADD \$1,\$2,\$3}$$
으로 나타낼 수도 있고, \.x의 등가가 \.{\$1}이고 \.y의 등가가 \.{\$2}라면 이를테면
$$\.{ADD x,y,y+1}$$
로 나타낼 수도 있다. ``레지스터~1에서 5를 빼라''라는 명령은
$$\.{SUB \$1,\$1,5}$$
나
$$\.{SUB x,x,5}$$
로 나타낼 수 있지만, `\.{SUBI} \.{\$1,\$1,5}'나 `\.{SUBI} \.{x,x,5}'로는 나타낼 수 없다.

\.{FLOT} 같은 \MMIX\ 연산은 피연산자 셋(레지스터, 순수, 레지스터/순수)이나 둘(레지스터,
레지스터/순수)을 요구한다. 앞의 경우에 가운데 피연산자는 반올림 방식인데, 미리 정의된
기호 값 \.{ROUND\_CURRENT}, \.{ROUND\_OFF}, \.{ROUND\_UP}, \.{ROUND\_DOWN},
\.{ROUND\_NEAR}로 나타내는 것이 가장 좋다. 이것들은 차례로 $(0,1,2,3,4)$를 뜻한다. 뒤의
경우에 가운데 피연산자는 0(곧 \.{ROUND\_CURRENT})으로 이해된다.
@:ROUND_OFF}\.{ROUND\_OFF@>
@:ROUND_UP}\.{ROUND\_UP@>
@:ROUND_DOWN}\.{ROUND\_DOWN@>
@:ROUND_NEAR}\.{ROUND\_NEAR@>
@:ROUND_CURRENT}\.{ROUND\_CURRENT@>

\.{SETL}이나 \.{INCH}처럼 와이드 즉치 상수가 들어가는 \MMIX\ 연산은 정확히 두
피연산자(레지스터, 순수)를 요구한다. 둘째 피연산자의 값은 두 바이트에 들어가야 한다.

\.{BNZ}처럼 레지스터 하나와 상대 주소를 언급하는 \MMIX\ 연산도 두 피연산자를 요구한다.
첫 피연산자는 레지스터 번호여야 한다. 둘째 피연산자에서 현재 위치를 빼고 4로 나눈
결과~$r$은 $-2^{16}\le r<2^{16}$ 범위에 있어야 한다. 둘째 피연산자는 정의되지 않은
것일 수도 있다. 그 경우에는 나중에 정해지는 값이 정의된 값에 대한 제한을 만족해야 한다.
연산 코드 \.{GETA}와 \.{PUSHJ}도 비슷한데, \.{PUSHJ}의 첫 피연산자는 순수한 값일 수도
있다(아래를 보라). \.{JMP} 연산도 비슷하지만, 피연산자가 하나뿐이고 더 넓은 주소 범위
$-2^{24}\le r<2^{24}$를 허용한다.

\.{LDO}와 \.{STHT}와 \.{GO}처럼 메모리를 가리키는 \MMIX\ 연산은, 피연산자가 셋이면
\.{ADD}처럼 다룬다. 다만 \.{PRELD}, \.{PREGO}, \.{PREST}, \.{STCO}, \.{SYNCD},
\.{SYNCID}의 경우에는 첫 피연산자가 레지스터 번호가 아니라 순수한 값이어야 한다. 이
연산 코드들은 특별한 두 피연산자 꼴도 받아들이는데, 그때 둘째 피연산자는 {\it 기준
주소\/}(base address)와 즉치 오프셋을 나타낸다(아래를 보라).

\.{PUSHJ}와 \.{PUSHGO}의 첫 피연산자는 순수한 수일 수도 있고 레지스터 번호일 수도
있다. 앞의 경우(`\.{PUSHJ}~\.{2,Sub}'나 `\.{PUSHGO}~\.{2,Sub}')에 프로그래머는 ``레지스터
두 개를 밀어 넣자''라고 생각하고 있을 것이고, 뒤의 경우(`\.{PUSHJ}~\.{\$2,Sub}'나
`\.{PUSHGO}~\.{\$2,Sub}')에는 ``레지스터~2를 이 서브루틴 호출의 구멍(hole) 위치로 삼자''라고
생각하고 있을 것이다. 두 경우 모두 어셈블된 출력은 같다.

나머지 \MMIX\ 연산 코드들은 저마다 특이하다.
$$\def\\{{\rm\quad or\quad}}
\vbox{\halign{\tt#\hfill\cr
NEG r,p,z;\cr
PUT s,z;\cr
GET r,s;\cr
POP p,yz;\cr
RESUME xyz;\cr
SAVE r,0;\cr
UNSAVE r;\cr
SYNC xyz;\cr
TRAP x,y,z\\TRAP x,yz\\TRAP xyz;\cr
}}$$
\.{SWYM}과 \.{TRIP}은 \.{TRAP}과 같다. 여기서 \.s는 0과~31 사이의 정수로, 되도록이면
특수 레지스터 코드를 나타내는 미리 정의된 기호 \.{rA}, \.{rB}, \dots~가운데 하나로 준다.
\.r은 레지스터 번호이고, \.p는 순수한 바이트이며, \.x, \.y, \.z는 레지스터 번호이거나
순수한 바이트다. \.{yz}와 \.{xyz}는 각각 두 바이트와 세 바이트에 들어가는 순수한 값이다.

이 모든 규칙은 \MMIXAL이 \MMIX\ 연산 코드를 저마다 가장 자연스러운 방식으로 다룬다고
말하면 요약된다. 피연산자가 셋이면 어셈블된 \MMIX\ 명령의 X,~Y,~Z 필드에 영향을 준다.
둘이면 X와~YZ 필드에, 하나뿐이면 XYZ 필드에 영향을 준다.

@ 연산 코드가 \MMIX\ 연산에 해당하는 모든 경우에, \MMIXAL\ 명령은 어셈블러에게 네 단계를
수행하라고 이른다. (1)~현재 위치에 필요하면 1이나 2나~3을 더해서 4의 배수로 맞춘다.
(2)~레이블이 비어 있지 않으면 레이블 필드의 등가를 현재 위치로 정의한다. (3)~피연산자들의
값을 매기고, 지정된 \MMIX\ 명령을 어셈블해서 현재 위치에 넣는다. (4)~현재 위치를
4만큼 늘린다.

@ 이제 유사 연산을 살펴보자. 가장 간단한 것부터 시작한다.

\bull\<label> \.{IS} \<expression>은 레이블의 값을 식의 값으로 정의한다. 식은 앞선
참조이면 안 된다. 식은 순수한 값일 수도 레지스터 번호일 수도 있다.
@.IS@>

\bull\<label> \.{LOC} \<expression>은 먼저, 레이블이 비어 있지 않으면 그것을 현재 위치의
값으로 정의한다. 그런 다음 현재 위치를 식의 값으로 바꾼다. 식은 순수해야 한다.
@.LOC@>

\smallskip 예컨대 `\.{LOC} \.{\#1000}'은 뒤따르는 명령이나 데이터를 십육진 값이
\Hex{1000}인 위치에서부터 어셈블하기 시작한다. `\.X~\.{LOC}~\.{@@+500}'은 \.X를 메모리의
500바이트 가운데 첫 바이트의 주소로 정의한다. 어셈블은 위치 $\.X+500$에서 계속된다.
현재 위치가 아직 256의 배수로 맞춰져 있지 않을 때 그렇게 맞추는 작업은
`\.{LOC}~\.{@@+(256-@@)\&255}'로 나타낼 수 있다.

좀 더 복잡한 예는 명령과 데이터를 메모리의 두 영역에 따로 내보내고 싶지만, \MMIXAL\
소스 파일에서는 그것들을 섞어 쓰고 싶을 때 생긴다. 먼저 \.{8H}와 \.{9H}를 각각 명령
세그먼트와 데이터 세그먼트의 시작 주소로 정의한다. 그러면 명령들의 한 덩어리는
`\.{LOC}~\.{8B}; \dots; \.{8H}~\.{IS}~\.{@@}'로 감쌀 수 있고, 데이터의 한 덩어리는
`\.{LOC}~\.{9B}; \dots; \.{9H}~\.{IS}~\.{@@}'로 감쌀 수 있다. 이런 덩어리를 얼마든지
섞을 수 있다. 명령에서 데이터로 넘어갈 때는 유사 명령 두 개
`\.{8H}~\.{IS}~\.{@@;} \.{LOC}~\.{9B}' 대신 그냥 `\.{8H}~\.{LOC}~\.{9B}'라고 써도 된다.

\bull \.{PREFIX} \<symbol>은 현재 접두어를 주어진 (완전히 한정된) 기호로 새로 정의한다.
레이블 필드는 비어 있어야 한다.
@.PREFIX@>

@ 다음 유사 연산들은 바이트, 와이드, 테트라바이트, 옥타바이트 데이터를 어셈블한다.

\bull \<label> \.{BYTE} \<expression list>는 레이블 필드가 비어 있지 않으면 레이블을
현재 위치로 정의한다. 그런 다음 식 목록의 식마다 바이트 하나씩을 어셈블하고, 현재 위치를
그 바이트 수만큼 전진시킨다. 식들은 모두 한 바이트에 들어가는 순수한 수여야 한다.

이런 식 목록에는 문자열 상수가 자주 쓰인다. 예컨대 현재 위치가 \Hex{1000}이면, 명령
\.{BYTE}~\.{"Hello",0}은 상수 \.{'H'}, \.{'e'}, \.{'l'}, \.{'l'}, \.{'o'}, \.0을 담은
여섯 바이트를 위치 \Hex{1000}, \dots,~\Hex{1005}에 어셈블하고, 현재 위치를
\Hex{1006}으로 전진시킨다.
@.BYTE@>

\bull \<label> \.{WYDE} \<expression list>도 비슷하지만, 먼저 필요하면 현재 위치에 1을
더해서 짝수로 만든다. 그런 다음 (비어 있지 않은 레이블이 있으면) 레이블을 정의하고,
식마다 두 바이트 값으로 어셈블한다. 현재 위치는 목록의 식 수의 두 배만큼 전진한다.
식들은 모두 두 바이트에 들어가는 순수한 수여야 한다.
@.WYDE@>

\bull \<label> \.{TETRA} \<expression list>도 비슷하지만, 레이블을 정의하기 전에 현재
위치를 4의 배수로 맞춘다. 그런 다음 식마다 네 바이트 값으로 어셈블한다. 목록에 식이
$n$개이면 현재 위치는 $4n$만큼 전진한다. 식마다 네 바이트에 들어가는 순수한 수여야 한다.
@.TETRA@>

\bull \<label> \.{OCTA} \<expression list>도 비슷하지만, 먼저 현재 위치를 8의 배수로
맞추고, 식마다 여덟 바이트 값으로 어셈블한다. 목록에 식이 $n$개이면 현재 위치는 $8n$만큼
전진한다. 식들 가운데 어느 것이든, 또는 전부가 앞선 참조일 수 있지만, 결국에는 모두
순수한 수로 정의되어야 한다.
@.OCTA@>

@ 전역 레지스터는 \MMIX\ 프로그램에서 메모리에 접근하는 데 중요하다. 전역 레지스터를
손으로 할당하고 \.{IS} 명령으로 정의할 수도 있겠지만, \MMIXAL은 대개 훨씬 편리한 방법을
제공한다.

\bull \<label> \.{GREG} \<expression>은 새 전역 레지스터 하나를 할당하고, 그 번호를
레이블의 등가로 준다. 어셈블을 시작할 때 현재의 전역 문턱~G는 \$255다. 서로 다른
\.{GREG} 명령마다 G가 1씩 줄어든다. G의 마지막 값이, 어셈블된 프로그램이 적재될 때 rG의
처음 값이 된다.
@.GREG@>

식의 값은 프로그램이 시작할 때 전역 레지스터에 적재된다. {\it 이 값이 0이 아니면,
프로그램이 실행되는 내내 일정하게 남아 있어야 한다\/}. 그런 전역 레지스터를 {\it 기준
주소\/}라고 부른다. 값이 같은 기준 주소 둘 이상에는 같은 전역 레지스터 번호가 할당된다.

기준 주소는 메모리 접근을 중요한 방식으로 단순하게 해 준다. 예컨대 옥타바이트 값 다섯
개가 데이터 세그먼트에 있고, 그 주소들을 \.{AA}, \.{BB}, \.{CC}, \.{DD}, \.{EE}라고
부른다고 하자:
$$\.{AA LOC @@+8;BB LOC @@+8;CC LOC @@+8;DD LOC @@+8;EE LOC @@+8}$$
그러면 \.{Base GREG AA}라고 해 두면, \.{AA}를 레지스터~\.{\$1}로 가져올 때 그냥
`\.{LDO}~\.{\$1,AA}'라고 쓰고, \.{CC}를 레지스터~\.{\$2}로 가져올 때
`\.{LDO}~\.{\$2,CC}'라고 쓸 수 있다.

그 원리는 이렇다. \.{LDO}나 \.{STB}나 \.{GO} 같은 메모리 연산에 피연산자가 둘뿐이면,
둘째 피연산자는 $0\le\delta<256$이고 $b$가 앞선 \.{GREG} 명령들 가운데 하나의 기준
주소 값일 때 $b+\delta$로 나타낼 수 있는 순수한 수여야 한다. \MMIXAL\ 처리기는 가장 가까운
기준 주소를 찾아서 알맞은 명령을 만들어 낸다. 예컨대 앞 문단의 예에서 명령
`\.{LDO}~\.{\$2,CC}'는 저절로 `\.{LDO}~\.{\$2,Base,16}'으로 바뀐다.

충분히 가까운 기준 주소가 없으면 오류 메시지가 나온다. 다만 이 프로그램을 명령줄 옵션
\.{-x}로 실행하면 그렇지 않다. \.{-x} 옵션은 필요하면 전역 레지스터~255를 써서 명령을
더 끼워 넣어, 어떤 주소에든 접근할 수 있게 한다. 예컨대 \.{LDO}~\.{\$2,FF}를 명령 하나로
구현할 수 있게 해 주는 기준 주소가 없고, \.{FF}가 \.{Base+1000}과 같다면, \.{-x} 옵션은
\.{LDO}~\.{\$2,FF} 대신
$$\.{SETL \$255,1000; LDO \$2,Base,\$255}$$
라는 두 명령을 어셈블한다. 주의: \.{-x} 기능을 쓰면 실제 \MMIX\ 명령의 수를 예측하기
어려워진다. 그러므로 `\.{BNZ}~\.{x,@@+8}' 같은 위험한 꼴의 상대 분기 명령을 쓰는
코딩 습관이 있다면 극도로 조심해야 한다.

이 기준 주소 관례는 별칭 연산~\.{LDA}에도 쓸 수 있다. 예컨대 `\.{LDA}~\.{\$3,CC}'는
@.LDA@>
명령 `\.{ADDU}~\.{\$3,Base,16}'을 어셈블해서 \.{CC}의 주소를 레지스터~3에 적재한다.

\MMIXAL은 또한
$$\hbox{\.{LDO} \.{\$1,\$2}}$$
같은 메모리 연산의 두 피연산자 꼴을 `\.{LDO} \.{\$1,\$2,0}'의 줄임으로 허용한다.

\MMIXAL\ 프로그램이 내장 레지스터 스택 말고 메모리 스택도 쓰는 서브루틴을 쓸 때는 대개
`\.{sp}~\.{GREG}~\.{0;fp}~\.{GREG}~\.0'이라는 명령들로 시작한다. 이 명령들은 {\it 스택
포인터\/} \.{sp=\$254}와 {\it 프레임 포인터\/} \.{fp=\$253}을 할당한다. 그러나
서브루틴 라이브러리는 전역 레지스터와 스택에 대해 어떤 관례든 자유롭게 구현할 수 있다.
@^stack pointer@>
@^frame pointer@>

@ 짧은 프로그램은 전역 레지스터가 모자라는 일이 드물지만, 긴 프로그램에는 \.{GREG}를
너무 자주 쓰지 않았는지 확인하는 방법이 필요하다. 다음 유사 명령이 그 안전밸브다.

\bull \.{LOCAL} \<expression>은 그 식이 어셈블하는 프로그램에서 지역 레지스터가 되도록
보장한다. 식은 레지스터 번호여야 하고, 레이블 필드는 비어 있어야 한다. 어셈블이 끝날 때
G의 마지막 값이 이런 식으로 지역이라고 선언된 모든 레지스터 번호보다 크지 않으면
\MMIXAL이 오류를 보고한다.
@.LOCAL@>

레지스터 번호가 32 이상이 아니면 \.{LOCAL} 명령을 줄 필요가 없다. (\MMIX은 늘 \.{\$0}부터
\.{\$31}까지를 지역으로 여기므로, \MMIXAL은 명령 `\.{LOCAL}~\.{\$31}'이 있는 것처럼
은연중에 행동한다.)

@ 마지막으로, 적재 루틴과, 어셈블된 프로그램을 쓸 디버거에 정보와 힌트를 넘기는 유사
명령이 둘 있다.

\bull \.{BSPEC} \<expression>은 ``특수 모드''를 시작한다. \<expression>의 값은 두
바이트에 들어가야 하고, 레이블 필드는 비어 있어야 한다.
@.BSPEC@>

\bull \.{ESPEC}은 ``특수 모드''를 끝낸다. 피연산자 필드는 무시되고, 레이블 필드는 비어
있어야 한다.
@.ESPEC@>

\smallskip\noindent
\.{BSPEC}과 \.{ESPEC} 사이에 어셈블된 모든 것은 출력에 곧바로 넘겨지지만, 어셈블된
프로그램의 일부로 적재되지는 않는다. 보통의 \MMIX\ 명령은 특수 모드에 나타날 수 없다.
유사 연산 \.{IS}, \.{PREFIX}, \.{BYTE}, \.{WYDE}, \.{TETRA}, \.{OCTA}, \.{GREG},
\.{LOCAL}만 허용된다. \.{BSPEC}의 피연산자는 두 바이트에 들어가는 값이어야 한다. 이 값은
뒤따르는 데이터의 종류를 나타낸다. (예컨대 \.{BSPEC}~\.0은 현재 위치의 서브루틴 호출
관례에 관한 정보를 들여올 수 있고, \.{BSPEC}~\.1은 현재 자리의 코드로 컴파일된 고급
언어 프로그램의 줄 번호를 들여올 수 있다. 시스템 루틴은 어셈블러를 거쳐 운영체제로 이런
정보를 넘겨야 할 때가 많으므로, \MMIXAL은 범용 통로를 제공하는 것이다.)

@ 프로그램은 특별한 기호 위치 \.{Main}에서 시작해야 한다(더 정확히 말하면, 완전히
@.Main@>
한정된 기호 \.{:Main}에 해당하는 주소에서). 이 기호는 늘 일련번호~1을 가지며, 늘 정의되어
있어야 한다.
@^serial number@>

한 위치가 어셈블된 데이터를 두 번 이상 받아서는 안 된다. (더 정확히 말하면, 적재기는 각
바이트 위치에 대해 어셈블된 모든 데이터의 비트별 배타적 논리합을 적재한다. 그러나 ``같은
바이트에 두 가지를 적재하지 말라''는 일반 규칙이 가장 안전하다.) 어셈블된 데이터를 받지
않는 모든 위치는 처음에 0이다. 다만 적재 루틴은 세그먼트~3에 레지스터 스택 데이터를
넣고, 운영체제는 세그먼트~2에 명령줄 데이터와 디버거 데이터를 넣을 수 있다. (초보적인
\MMIX\ 운영체제는 프로그램을 시작할 때 명령줄 인자의 개수를~\$0에, 인자 포인터 배열의
시작을 가리키는 포인터를~\$1에 넣는다.) 사용자가 그런 데이터가 시스템을 망가뜨릴 위험을
감수할 참된 해커가 아니라면, 세그먼트 2와 3에는 어셈블된 데이터를 넣지 말아야 한다.

@* 이진 MMO 출력. \MMIXAL\ 처리기가 \.{foo.mms}라는 파일을 어셈블하면 \.{foo.mmo}라는
이진 출력 파일이 나온다. (접미어 \.{mms}는 ``\MMIX\ 기호(symbolic),'' \.{mmo}는 ``\MMIX\
목적(object)''을 뜻한다.) 이런 \.{mmo} 파일은 테트라바이트의 연속이라는 단순한 구조를
가진다. 테트라바이트 가운데 어떤 것은 적재 루틴에 내리는 명령이고, 나머지는 적재할
데이터다.
@^object files@>

적재기 명령은 첫(가장 높은) 바이트로 데이터 테트라바이트와 구별된다. 그 바이트는
\Hex{98}이라는 특별한 탈출 코드 값을 가지는데, 아래 프로그램에서는 이것을 |mm|이라고
부른다. 이 코드 값은 \MMIX의 연산 코드 \.{LDVTS}에 해당하는데, \.{LDVTS}는 데이터
테트라에 나타날 가능성이 낮다. 적재기 명령의 둘째 바이트~X는 적재기 연산 코드, 곧 {\it
lopcode}다. 셋째와 넷째 바이트 Y와~Z는 피연산자다. 때로는 둘을 합쳐서 YZ라는 16비트
피연산자 하나로 쓴다.
@^lopcodes@>

@<상수@>=
const mm = 0x98 // the escape code of loader commands

@ 작고 억지로 꾸민 예 하나가 \.{mmo} 형식의 기본 발상을 설명하는 데 도움이 될 것이다.
\.{test.mms}라는 다음 입력 파일을 생각해 보자.
$$\obeyspaces\vbox{\halign{\tt#\hfil\cr
\% A peculiar example of MMIXAL\cr
\     LOC   Data\_Segment      \% location \#2000000000000000\cr
\     OCTA  1F                \% a future reference\cr
a    GREG  @@                 \% \$254 is base address for ABCD\cr
ABCD BYTE  "ab"              \% two bytes of data\cr
\     LOC   \#123456789        \% switch to the instruction segment\cr
Main JMP   1F                \% another future reference\cr
\     LOC   @@+\#4000           \% skip past 16384 bytes\cr
2H   LDB   \$3,ABCD+1         \% use the base address\cr
\     BZ    \$3,1F; TRAP       \% and refer to the future again\cr
\# 3 "foo.mms"                \% this comment is a line directive\cr
\     LOC   2B-4*10           \% move 10 tetras before previous location\cr
1H   JMP   2B                \% resolve previous references to 1F\cr
\     BSPEC 5                 \% begin special data of type 5\cr
\     TETRA \&a<<8             \% four bytes of special data\cr
\     WYDE  a-\$0              \% two more bytes of special data\cr
\     ESPEC                   \% end a special data packet\cr
\     LOC   ABCD+2            \% resume the data segment\cr
\     BYTE  "cd",\#98          \% assemble three more bytes of data\cr
}}$$
이것은 본질적으로 \.{'b'}를 레지스터~3에 넣는 우스꽝스러운 프로그램을 정의한다.
프로그램은 \.{BZ} 다음의 모든 비트가 0인 \.{TRAP} 명령에 이르면 멈춘다. 그러나 이 파일을
어셈블한 출력은 \MMIX\ 목적 파일의 기능 대부분을 보여 준다. 사실 \.{test.mms}는 크누스가
\MMIXAL\ 처리기를 처음 썼을 때 맨 처음 시험해 본 파일이다.

\.{test.mms}로부터 어셈블한 이진 출력 파일 \.{test.mmo}는 다음 테트라바이트들로
이루어진다. 십육진 표기로 보이고, 짧은 설명을 붙였다. 더 자세한 설명은 아래에서
lopcode를 하나씩 설명할 때 나온다.
$$
\halign{\hskip.5in\tt#&\quad#\hfil\cr
98090101&|lopPre| $1,1$ (서문, 판 1, 테트라 1개)\cr
36f4a363&(파일을 만든 시각)\cr
% Sat Mar 20 23:44:35 1999
98012001&|lopLoc| $\Hex{20},1$ (데이터 세그먼트, 테트라 1개)\cr
00000000&(데이터 세그먼트 주소의 낮은 테트라바이트)\cr
00000000&(\.{OCTA} \.{1F}의 높은 테트라바이트)\cr
00000000&(낮은 테트라바이트, 나중에 고쳐짐)\cr
61620000&(\.{"ab"}, 뒤에 0을 채움)\cr
\noalign{\penalty-200}
98010002&|lopLoc| $0,2$ (명령 세그먼트, 테트라 2개)\cr
00000001&(명령 세그먼트 주소의 높은 테트라바이트)\cr
2345678c&(맞춘 뒤의 주소의 낮은 테트라바이트)\cr
98060002&|lopFile| $0,2$ (파일 이름 0, 테트라 2개)\cr
74657374&(\.{"test"})\cr
2e6d6d73&(\.{".mms"})\cr
98070007&|lopLine| 7 (현재 파일의 7번째 줄)\cr
f0000000&(\.{JMP} \.{1F}, 나중에 고쳐짐)\cr
98024000&|lopSkip| \Hex{4000} (16384바이트 전진)\cr
98070009&|lopLine| 9 (현재 파일의 9번째 줄)\cr
8103fe01&(\.{LDB} \.{\$3,a,1}, 기준 주소 \.a를 씀)\cr
42030000&(\.{BZ} \.{\$3,1F}, 나중에 고쳐짐)\cr
9807000a&|lopLine| 10 (10번째 줄에 머묾)\cr
00000000&(\.{TRAP})\cr
98010002&|lopLoc| $0,2$ (명령 세그먼트, 테트라 2개)\cr
00000001&(명령 세그먼트 주소의 높은 테트라바이트)\cr
2345a768&(주소 \.{1H}의 낮은 테트라바이트)\cr
98050010&|lopFixrx| 16 (16비트 상대 주소를 고침)\cr
0100fff5&(위치 \.{@@-4*-11}를 고침)\cr
98040ff7&|lopFixr| \Hex{ff7} (\.{@@-4*\#ff7}을 고침)\cr
98032001&|lopFixo| $\Hex{20},1$ (데이터 세그먼트, 테트라 1개)\cr
00000000&(고칠 데이터 세그먼트 주소의 낮은 테트라바이트)\cr
98060102&|lopFile| $1,2$ (파일 이름 1, 테트라 2개)\cr
666f6f2e&(\.{"foo."})\cr
6d6d7300&(\.{"mms",0})\cr
98070004&|lopLine| 4 (현재 파일의 4번째 줄)\cr
f000000a&(\.{JMP} \.{2B})\cr
98080005&|lopSpec| 5 (종류 5의 특수 데이터 시작)\cr
00000200&(\.{TETRA} \.{\&a<<8})\cr
00fe0000&(\.{WYDE} \.{a-\$0})\cr
98012001&|lopLoc| $\Hex{20},1$ (데이터 세그먼트, 테트라 1개)\cr
0000000a&(데이터 세그먼트 주소의 낮은 테트라바이트)\cr
00006364&(\.{"cd"}, 맞춤 때문에 앞에 0이 옴)\cr
98000001&|lopQuote| (다음 테트라바이트를 lopcode로 취급하지 말 것)\cr
98000000&(\.{BYTE} \.{\#98}, 뒤에 0을 채움)\cr
980a00fe&|lopPost| \$254 (후기 시작, G는 254)\cr
20000000&(\$254의 처음 내용의 높은 테트라바이트)\cr
00000008&(기준 주소 \$254의 낮은 테트라바이트)\cr
00000001&(\$255의 처음 내용의 높은 테트라바이트)\cr
2345678c&(\$255의 낮은 테트라바이트, \.{Main}의 주소)\cr
980b0000&|lopStab| (기호표 시작)\cr
203a5040&(삼진 트라이로 나타낸 기호표의 압축 꼴)\cr
50404020\cr
41204220\cr
43094408\cr
83404020&(\.{ABCD} = \Hex{2000000000000008}, 일련번호 3)\cr
4d206120\cr
69056e01\cr
2345678c\cr
81400f61&(\.{Main} = \Hex{000000012345678c}, 일련번호 1)\cr
fe820000&(\.{a} = \$254, 일련번호 2)\cr
980c000a&|lopEnd| (기호표 끝, 테트라 10개)\cr
}$$
보충: 옮긴이의 시험(이 문서 끝의 ``시험'' 장)은 이 \.{test.mms}를 실제로 어셈블해서,
파일을 만든 시각만 이 표의 값으로 고정하면 표의 테트라바이트 58개가 한 비트도 다르지 않게
나오는지 확인한다.

@ \.{mmo} 파일의 테트라바이트가 탈출 코드로 시작하지 않으면, 그것은 현재 위치~$\lambda$에
적재되고 $\lambda$는 4의 다음 배수로 늘어난다. ($\lambda$가 4의 배수가 아니면, \MMIX의
보통 관례에 따라 테트라바이트는 실제로는 위치 $\lambda\land(-4)=4\lfloor\lambda/4\rfloor$에
들어간다.) 현재 줄 번호도 0이 아니면 1 늘어난다.

테트라바이트가 탈출 코드로 시작하면, 그다음 바이트는 적재기 명령을 정의하는 lopcode다.
lopcode는 열세 가지다.

\bull |lopQuote|: $\rm X=\Hex{00}$, $\rm YZ=1$. 다음 테트라가 탈출 코드로 시작하더라도
보통의 테트라바이트로 취급한다.

\bull |lopLoc|: $\rm X=\Hex{01}$, $\rm Y={}$높은 바이트, $\rm Z={}$테트라 개수($\rm Z=1$~또는~2).
현재 위치를, 다음 Z개의 테트라가 정의하는 64비트 주소에 $\rm 2^{56}Y$를 더한 값으로 정한다.
보통 $\rm Y=0$(명령 세그먼트)이거나 $\rm Y=\Hex{20}$(데이터 세그먼트)이다. 곧 $\rm Z=2$이면
높은 테트라가 먼저 나온다.

\bull |lopSkip|: $\rm X=\Hex{02}$, $\rm YZ=delta$. 현재 위치를 YZ만큼 늘린다.

\bull |lopFixo|: $\rm X=\Hex{03}$, $\rm Y={}$높은 바이트, $\rm Z={}$테트라 개수($\rm Z=1$~또는~2).
현재 위치~$\lambda$의 값을 옥타바이트~P에 적재한다. 여기서 P는 |lopLoc|에서처럼 다음 Z개의
테트라가 정의하는 64비트 주소에 $\rm2^{56}Y$를 더한 것이다. (P의 옥타바이트는 앞선 참조
때문에 앞서 0으로 어셈블되어 있었다.)

\bull |lopFixr|: $\rm X=\Hex{04}$, $\rm YZ=delta$. 위치~P의 테트라바이트의 YZ~필드에 YZ를
적재한다. 여기서 P는 $\rm\lambda-4YZ$, 곧 현재 위치보다 YZ개의 테트라바이트만큼 앞선
주소다. (이 테트라바이트에는 앞서 상대 주소를 받는 \MMIX\ 명령---분기, 확률 분기,
\.{JMP}, \.{PUSHJ}, \.{GETA}---이 적재되어 있었다. 그 YZ~필드는 앞선 참조 때문에 0으로
어셈블되어 있었다.)

\bull |lopFixrx|: $\rm X=\Hex{05}$, $\rm Y=0$, $\rm Z=16$ 또는 24. lopcode |lopFixr|에서처럼
진행하되, YZ를 $\rm P=\lambda-4YZ$에 적재하는 대신 $\delta$를 테트라바이트
$\rm P=\lambda-4\delta$에 적재한다. 여기서 $\delta$는 |lopFixrx| 명령 다음 테트라바이트의
값이고, 그 맨 앞 바이트는 0이거나~1이다. 맨 앞 바이트가~1이면, 주소~P를 계산할 때
$\delta$를 {\it 음수\/} $(\delta\land\Hex{ffffff})-2^{\rm Z}$로 취급해야 한다. (뒤의
경우는 드물게만 생기지만, 결국 ``뒤로 가는'' 명령이 되는 상대 ``앞선'' 참조를 고칠 때
필요하다. 그런 경우 위치~P에 배타적 논리합으로 들어가는 $\delta$의 값은 \.{BZ}를
\.{BZB}로, \.{JMP}를 \.{JMPB}로 바꾸는 따위의 일을 한다. \.{JMP}를 고칠 때는 $\rm Z=24$이고,
그 밖에는 $\rm Z=16$이다.)

\bull |lopFile|: $\rm X=\Hex{06}$, $\rm Y={}$파일 번호, $\rm Z={}$테트라 개수. 현재 파일 번호를~Y로,
현재 줄 번호를 0으로 정한다. 이 파일 번호가 앞서 나온 적이 있으면 Z는 0이어야 한다. 그렇지
않으면 Z는 양수여야 하고, 다음 Z개의 테트라바이트는 큰 끝(big-endian) 순서로 된 파일 이름의
문자들이다. 이름의 길이가 4의 배수가 아니면 뒤에 0이 따른다.

\bull |lopLine|: $\rm X=\Hex{07}$, $\rm YZ={}$줄 번호. 현재 줄 번호를 YZ로 정한다. 줄 번호가
0이 아니면, 현재 파일과 현재 줄은 다음에 적재될 데이터를 만들어 낸 소스 위치에 해당해야
하며, 진단 메시지에 쓰인다. (\MMIXAL\ 처리기는 세그먼트~0의 테트라바이트---대개
명령이다---의 소스에는 정확한 줄 번호를 주지만, 다른 세그먼트에 어셈블된 테트라바이트의
소스에는 주지 않는다.)

\bull |lopSpec|: $\rm X=\Hex{08}$, $\rm YZ={}$종류. 종류~YZ의 특수 데이터를 시작한다. 뒤따르는
테트라바이트들이, |lopQuote| 말고 다른 적재기 연산이 나올 때까지, 특수 데이터를 이룬다.
인용 명령 |lopQuote| 덕분에 특수 데이터의 테트라바이트가 탈출 코드로 시작할 수 있다.

\bull |lopPre|: $\rm X=\Hex{09}$, $\rm Y=1$, $\rm Z={}$테트라 개수. ``서문''을 정의하는
|lopPre| 명령은 모든 \.{mmo} 파일의 첫 테트라바이트여야 한다. Y~필드는 \.{mmo} 형식의
판 번호를 나타내며, 현재는~1이다. 나중에 다른 판 번호가 정의될 수도 있지만, 판~1은 늘 이
문서에 적힌 대로 지원되어야 한다. 서문 명령 |lopPre| 뒤의 Z개의 테트라바이트는 시스템 루틴이
관심을 가질 만한 추가 정보를 준다. 값이 $\rm Z>0$이면, 추가 정보의 첫 테트라는 이 \.{mmo}
파일을 만든 시각을 그리니치 평균시 1970년 1월 1일 00:00:00부터 잰 초로 기록한다.

\bull |lopPost|: $\rm X=\Hex{0a}$, $\rm Y=0$, $\rm Z=G$(32 이상이어야 한다). 이 명령은
적재할 모든 명령과 데이터 뒤에 오는 {\it 후기\/}({\it postamble\/})를 시작한다. 적재된 프로그램은
rG가 이 G 값인 채로 시작하며, \$G, $\rm G+1$, \dots,~\$255는 다음 $\rm(256-G)*2$개의
테트라바이트 값으로 처음에 정해진다. 이 테트라바이트들은 $\rm 256-G$개의 옥타바이트를
큰 끝 방식(높은 절반이 먼저)으로 나타낸다.

\bull |lopStab|: $\rm X=\Hex{0b}$, $\rm YZ=0$. 이 명령은 |lopPost| 다음의
$\rm(256-G)*2$개의 테트라바이트 바로 뒤에 나와야 한다. 그 뒤에 기호표가 따르는데, 기호표는
사용자가 정의한 모든 기호의 등가를 나중에 설명할 간결한 꼴로 나열한다.

\bull |lopEnd|: $\rm X=\Hex{0c}$, $\rm YZ={}$테트라 개수. 이 명령은 모든 \.{mmo} 파일의
맨 마지막 테트라바이트여야 한다. 게다가 이것과 |lopStab| 명령 사이에는 정확히 YZ개의
테트라바이트가 있어야 한다. (그래서 프로그램은 \.{mmo} 파일 전체를 앞으로 읽어 나가지
않고도 기호표를 쉽게 찾을 수 있다.)

\smallskip
이진 \.{mmo} 파일을 사람이 읽을 수 있는 꼴로 옮겨 주는 \.{MMOtype}이라는 루틴이 따로
있다.

@<상수@>=
const (
	lopQuote = 0x0 // the quotation lopcode
	lopLoc   = 0x1 // the location lopcode
	lopSkip  = 0x2 // the skip lopcode
	lopFixo  = 0x3 // the octabyte-fix lopcode
	lopFixr  = 0x4 // the relative-fix lopcode
	lopFixrx = 0x5 // extended relative-fix lopcode
	lopFile  = 0x6 // the file name lopcode
	lopLine  = 0x7 // the file position lopcode
	lopSpec  = 0x8 // the special hook lopcode
	lopPre   = 0x9 // the preamble lopcode
	lopPost  = 0xa // the postamble lopcode
	lopStab  = 0xb // the symbol table lopcode
	lopEnd   = 0xc // the end-it-all lopcode
)

@ 많은 독자가 \MMIXAL에 재배치 가능한(relocatable) 출력을 위한 기능이 없고, \.{mmo}
형식도 그런 기능을 지원하지 않는다는 것을 눈치챘을 것이다. 크누스가 처음 쓴 \MMIXAL과
\.{mmo}의 초고는 외부 연결을 가진 재배치 가능한 목적 파일을 허용했지만, 규칙이 상당히
복잡해져서 {\sl The Art of Computer Programming}의 목표와 어울리지 않았다. 컴퓨터 메모리가
예전보다 훨씬 싸진 지금은, 지금의 설계가 현재의 관행보다 오히려 나은 것으로 드러날지도
모른다. 재배치와 외부 연결을 허용하지 않으면 한 번에 하는 어셈블과 적재가 엄청나게
빠르기 때문이다. 서로 다른 프로그램 모듈을 한데 어셈블하는 것은 재배치 방식에서 그것들을
연결하는 것만큼이나 빠르고, 모듈끼리 훨씬 유연한 방법으로 소통할 수 있다. 공개 소스
라이브러리를 사용자 프로그램과 합치면 디버깅 도구가 좋아지고, 소스 꼴을 더 많은 사용자
공동체가 볼 수 있으면 그런 라이브러리의 품질은 틀림없이 나아질 것이다.

@* 기본 데이터 타입. 이 64비트 \MMIX\ 아키텍처용 프로그램은 원래 32비트 정수 산술에
바탕을 두었다. 크누스가 이 글을 쓸 때 쓸 수 있던 거의 모든 컴퓨터가 그렇게 제한되어
있었기 때문이다. 기본 산술의 세부는 시뮬레이터들에도 같은 루틴이 필요하므로
{\mc MMIX-ARITH}라는 별도의 프로그램 모듈에 있다.
@^system dependencies@>

보충: 이 한글판에서 그 모듈은 \.{mmixarith} 꾸러미다. 옥타바이트는 거기서처럼 |uint64|의
별칭이다. 원본은 \.{mmixarith}의 서브루틴 |oplus|, |ominus|, |incr|, |oand|,
|shift_left|, |shift_right|, |omult|, |odiv|를 외부 함수로 선언하고, 어셈블러가 시작할 때
``타입 \KW{tetra}가 제대로 구현되지 않았다''는 기초 점검까지 했다. 64비트 \GO/에서는 덧셈,
뺄셈, 논리곱, 자리 옮김, 곱셈의 아래 절반이 모두 연산자이고 타입 크기는 언어가 보장하므로,
그 선언들과 점검은 필요 없다. 원본의 산술적 오른쪽 자리 옮김 |shift_right(o,2,0)|은
여기서 |int64|를 거치는 |>>|로 쓴다. \.{mmixarith}에서 가져다 쓰는 것은 나눗셈 |Div|
하나뿐이다. 함수 |Div|는 피제수의 위 절반이 제수 이상이면 나누지 않고 자명한 답을 돌려주는데,
아래에서 보듯 \MMIXAL의 나눗셈 연산자는 바로 그 약속에 기대기 때문이다.

@<타입 정의@>=
type (
	Tetra = mmixarith.Tetra
	Octa  = mmixarith.Octa
)

@ 앞으로 이 프로그램은 유니코드 문자로 된 기호를 다루겠지만, 지금 코드는 8비트 부분
집합에 머문다.
@^Unicode@>
원본은 나중의 이행을 쉽게 하려고 \KW{Char}라는 타입을 정의했다. 지금은 \KW{Char}가
\KW{char}와 같지만, 유니코드판에서는 16비트 타입으로 바꿀 수 있다. 유니코드로 이행할 때는
다른 변경도 필요할 것이다. 이를테면 |fprintf| 호출 가운데 어떤 것은 |fwprintf| 호출이
되고, 출력 서식의 \.{\%s} 가운데 어떤 것은 \.{\%ls}가 될 것이다. 바꿀 수 있는 타입 이름
\KW{Char}는 적어도 유니코드와 함께하는 더 밝은 미래를 향한 첫걸음이 된다.

보충: \GO/에서는 입력 줄과 필드들을 바이트 조각 |[]byte|로 다룬다. 원본의 \KW{Char}
배열이 널 문자로 끝나는 \CEE/ 문자열이었던 것처럼, 입력 버퍼와 피연산자 목록 버퍼도
끝에 널 문자를 파수꾼으로 둔다. 그러면 원본의 포인터 연산 |*(p+1)|, |*(p-2)| 따위를
색인 연산으로 그대로 옮길 수 있다. 원본은 또한 옛 \CEE/ 컴파일러를 위해 함수 원형을
감추는 매크로 \.{ARGS}를 정의했는데, 이것도 필요 없다.

@* 기본 입출력. 입력은 보통 72자로 제한된 버퍼로 들어간다. 이 한계는 어셈블러를 부를
때 \.{-b} 옵션으로 늘릴 수 있다. 그러나 버퍼가 짧아야 목록(listing)이 다루기 힘들어지지
않는다. 기호 목록은 줄마다 19자를 보태기 때문이다.

보충: 원본은 버퍼 다섯 개를 |calloc|으로 따로 잡고, 잡지 못하면 ``No room for the
buffers''라며 치명적 오류를 냈다. \GO/에서는 메모리가 모자라면 런타임이 알아서 멈추므로
그 점검은 없다. 입력 버퍼에는 |bufSize|개의 문자 뒤에 널 문자 {\it 둘\/}을 둘 자리를
잡는다. 왜 둘인지는 조금 뒤, 레이블 필드를 읽는 곳에서 설명한다. 나머지 세 필드는
필요한 만큼 늘어나는 바이트 조각이므로 따로 잡을 필요가 없다.

@<모든 것을 초기화한다@>=
if a.bufSize < 72 {
	a.bufSize = 72
}
a.buffer = make([]byte, a.bufSize+2)

@ 원본의 전역 변수들은 이 한글판에서 모두 구조체 |assembler|의 필드다. 필드는 원본에서
전역 변수가 처음 나오는 곳마다 이 절의 이어붙임으로 하나씩 보탠다.

@<타입 정의@>=
type assembler struct {
	@<어셈블러의 상태@>
}

@ @<어셈블러의 상태@>=
buffer      []byte // raw input of the current line
bufPtr      int    // current position within |buffer|
labField    []byte // copy of the label field of the current instruction
opField     []byte // copy of the opcode field of the current instruction
operandList []byte // copy of the operand field of the current instruction (null-terminated)

@ 원본은 |fgets|로 한 줄을 읽었다. 함수 |fgets|는 줄바꿈 문자를 만나거나 |bufSize|개의 문자를
읽을 때까지 읽고, 끝에 널 문자를 붙인다. 여기서는 그 동작을 한 바이트씩 그대로 흉내 낸다.
아무것도 읽지 못했을 때만 입력이 끝난 것이다.

@<다음 입력 줄을 읽는다; 입력이 끝났으면 |break|@>=
n := 0
for n < a.bufSize {
	c, err := a.srcFile.ReadByte()
	if err != nil {
		break
	}
	a.buffer[n] = c
	n++
	if c == '\n' {
		break
	}
}
if n == 0 {
	break
}
a.buffer[n], a.buffer[n+1] = 0, 0
a.lineNo++
a.lineListed = false
j = cstrlen(a.buffer)
if j > 0 && a.buffer[j-1] == '\n' {
	a.buffer[j-1] = 0 // remove the newline
} else if c, err := a.srcFile.ReadByte(); err == nil {
	@<너무 긴 줄의 남는 부분을 버린다@>
}
if a.buffer[0] == '#' {
	@<줄 지시문인지 확인한다@>
}
a.bufPtr = 0

@ 보충: 원본이 줄의 길이를 |strlen|으로 쟀으므로 여기서도 첫 널 문자까지를 잰다. 줄
안에 널 문자가 끼어 있는 이상한 입력에서도 원본과 똑같이 동작하려는 것이다.

@<함수들@>=
func cstrlen(b []byte) int {
	for i, c := range b {
		if c == 0 {
			return i
		}
	}
	return len(b)
}

func cstr(b []byte) string { return string(b[:cstrlen(b)]) }

@ 보충: 원본의 경고는 줄바꿈 문자 말고는 아무것도 버려지지 않은 경우에도 나온다. 줄이
정확히 |bufSize|자이면 |fgets|가 줄바꿈 문자를 읽지 못하고, 그다음 |fgetc|가 줄바꿈
문자를 읽기 때문이다. 이 한글판도 그대로 따른다.

@<너무 긴 줄의 남는 부분을 버린다@>=
for c != '\n' {
	if c, err = a.srcFile.ReadByte(); err != nil {
		break
	}
}
if !a.longWarningGiven {
	a.longWarningGiven = true
	a.err("*trailing characters of long input line have been dropped")
@.trailing characters...@>
	fmt.Fprintf(a.stderr, "(say `-b <number>' to increase the length of my input buffer)\n")
} else {
	a.err("*trailing characters dropped")
}

@ @<어셈블러의 상태@>=
curFile          int  // index of the current file in |filename|
lineNo           int  // current position in the file
lineListed       bool // have we listed the buffer contents?
longWarningGiven bool // have we given the hint about \.{-b}?

@ 우리는 오류 보고를 위해, 그리고 목적 파일의 동기화 데이터를 위해 소스 파일 이름과
줄 번호를 늘 기억해 둔다. 서로 다른 소스 파일 이름을 256개까지 기억할 수 있다.

@<어셈블러의 상태@>=
filename []string // source file names, including those in line directives

@ 현재 줄이 줄 지시문이면, 어셈블러는 그것을 주석으로도 취급한다.

보충: 원본은 이름을 담을 배열 칸을 미리 잡아 두고 거기에 글자를 채워 넣은 뒤, 같은
이름이 앞에 있는지 찾았다. 여기서는 이름을 조각 |name|에 모은다. 따옴표 안이 비어
있으면(|a.buffer[p-1]=='"'|) 줄 지시문이 아니다.

@<줄 지시문인지 확인한다@>=
for p = 1; isSpace(a.buffer[p]); p++ {
}
for j = 0; isDigit(a.buffer[p]); p++ {
	j = 10*j + int(a.buffer[p]-'0')
}
for ; isSpace(a.buffer[p]); p++ {
}
if a.buffer[p] == '"' {
	var name []byte
	for p, k = p+1, 0; a.buffer[p] != 0 && a.buffer[p] != '"' && k < filenameMax; p, k = p+1, k+1 {
		name = append(name, a.buffer[p])
	}
	if k == filenameMax {
		a.fatal("Capacity exceeded: File name too long")
@.Capacity exceeded...@>
	}
	if a.buffer[p] == '"' && a.buffer[p-1] != '"' { // yes, it's a line directive
		@<이름 |name|을 찾거나 새로 등록해 현재 파일로 삼는다@>
	}
}

@ @<이름 |name|을 찾거나...@>=
for k = 0; k < len(a.filename) && a.filename[k] != string(name); k++ {
}
if k == len(a.filename) {
	if len(a.filename) == 256 {
		a.fatal("Capacity exceeded: More than 256 file names")
	}
	a.filename = append(a.filename, string(name))
}
a.curFile = k
a.lineNo = j - 1

@ 원본은 \CEE/ 라이브러리가 정하는 \.{FILENAME\_MAX}를 파일 이름의 최대 길이로 썼고,
옛 라이브러리가 그것을 정의하지 않으면 256으로 두었다. 보충: 이 값은 시스템마다 다르다.
옮긴이는 원본과 비교 시험을 한 macOS의 값 1024를 쓴다.

@<상수@>=
const filenameMax = 1024

@ 원본의 지역 변수들은 |mmixal| 함수의 지역 변수다. 원본의 포인터 |p|는 입력 버퍼와
피연산자 목록 사이를 오가며 가리켰다. 여기서는 색인이며, 어느 버퍼의 색인인지는 쓰이는
곳의 문맥이 정한다. 원본에는 복사할 곳을 가리키는 포인터 |q|도 있었지만, 바이트 조각에
|append|로 덧붙이는 이 한글판에서는 필요 없다.

@<지역 변수@>=
var p int // the place where we're currently scanning

@ 문자 분류에는 \CEE/ 라이브러리의 |isspace|, |isdigit|, |isxdigit|를 흉내 낸 함수를
쓴다. 모두 {\mc ASCII} 문자만 알아본다.

@<함수들@>=
func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}
func isDigit(c byte) bool  { return '0' <= c && c <= '9' }
func isXDigit(c byte) bool { return isDigit(c) || 'a' <= c && c <= 'f' || 'A' <= c && c <= 'F' }

@ 다음 서브루틴 몇 개는 어셈블된 결과의 목록을 만드는 데 쓸모가 있다. 사용자는 명령줄
옵션으로 목록을 요청할 수 있다. 목록에서는 왼쪽 19칸을, 버퍼의 입력으로부터 어셈블된
출력의 표현으로 채운다. 한 줄에 테트라바이트 하나만큼의 자리밖에 없으므로, 어셈블된
출력이 한 줄보다 많이 필요할 때도 있다.

서브루틴 |flushListingLine|은 목록 한 줄 분량의 어셈블된 자료를 다 만들었을 때 부른다.
매개변수는, 입력 줄을 아직 되풀이해 적지 않았다면 어셈블된 자료와 버퍼 내용 사이에 찍을
문자열이다. 이 문자열의 길이는 목록의 현재 줄에 이미 찍은 문자 수를 19에서 뺀 것이어야
한다.

@<함수들@>=
func (a *assembler) flushListingLine(s string) {
	if a.lineListed {
		fmt.Fprintf(a.listingFile, "\n")
	} else {
		fmt.Fprintf(a.listingFile, "%s%s\n", s, cstr(a.buffer))
		a.lineListed = true
	}
}

@ @<어셈블러의 상태@>=
curLoc      Octa    // current location of assembled output
listingLoc  Octa    // current location on the listing
holdBuf     [4]byte // assembled bytes
heldBits    byte    // which bytes of |holdBuf| are active?
listingBits byte    // which of them haven't been listed yet?
specMode    bool    // are we between \.{BSPEC} and \.{ESPEC}?
specModeLoc Tetra   // number of bytes in the current special output

@ 바이트가 어셈블되면 |holdBuf|에 놓인다. 더 정확히 말하면, |j|에 4의 배수를 더한 위치에
어셈블되는 바이트는 |holdBuf[j]|에 놓이고, 보조 변수 |heldBits|와 |listingBits|에 |1<<j|가
더해진다. 게다가 그 바이트가 나중에 해결될 앞선 참조이면 |listingBits|에 |0x10<<j|가 더해진다.

바이트들은 출력해야 할 때까지 붙잡아 둔다. 루틴 |listingClear|는 붙잡아 두었지만 아직
보이지 않은 바이트들을 목록에 적는다. 이 메서드는 |listingBits!=0|일 때만 불러야 한다.

@<함수들@>=
func (a *assembler) listingClear() {
	var j, k int
	for k = 0; k < 4; k++ {
		if a.listingBits&(1<<k) != 0 {
			break
		}
	}
	if a.specMode {
		fmt.Fprintf(a.listingFile, "         ")
	} else {
		@<목록의 위치를 바꾸어야 하면 바꾼다@>
		fmt.Fprintf(a.listingFile, " ...%03x: ", Tetra(a.listingLoc)&0xffc|Tetra(k))
	}
	for j = 0; j < 4; j++ {
		switch {
		case a.listingBits&(0x10<<j) != 0:
			fmt.Fprintf(a.listingFile, "xx")
		case a.listingBits&(1<<j) != 0:
			fmt.Fprintf(a.listingFile, "%02x", a.holdBuf[j])
		default:
			fmt.Fprintf(a.listingFile, "  ")
		}
	}
	a.flushListingLine("  ")
	a.listingBits = 0
}

@ 목록에는 위치의 십육진 숫자 가운데 가장 낮은 세 자리만 보인다. 다만 다른 자리가
바뀌었으면 그렇지 않다. 다음 코드는 바뀐 것을 보여 주어야 할 때 줄을 하나 더 찍는다.
위치의 맨 아래 두 비트는 목록에 보일 위치를 4로 나눈 나머지 |k|로 바꾼다.

보충: 원본에서는 이것이 |update_listing_loc|라는 서브루틴이었지만, 부르는 곳이
|listingClear| 하나뿐이므로 여기서는 이름 있는 절로 끼워 넣었다.

@<목록의 위치를 바꾸어야 하면 바꾼다@>=
if (a.curLoc^a.listingLoc)&^0xfff != 0 {
	fmt.Fprintf(a.listingFile, "%016x:", a.curLoc&^3|Octa(k))
	a.flushListingLine("  ")
}
a.listingLoc = a.curLoc&^3 | Octa(k)

@ 오류 메시지는 표준 오류에 쓴다. 메시지가 `\.*'로 시작하면 그냥 경고이고, `\.!'로
시작하면 치명적이다. 그 밖의 오류는 아마도 손으로 고쳐야 할 만큼 심각하지만 비극적이지는
않은 것이다. 오류와 경고는 목록 파일에도 나타난다.

원본의 매크로 |err(m)|은 오류를 보고하고, 메시지가 `\.*'로 시작하지 않으면 |goto bypass|로
현재 명령의 나머지를 건너뛰었다. 메서드 |derr|와 |dderr|는 메시지를 |sprintf|로 짠 다음 같은 일을
했고, |panic|과 |dpanic|은 메시지 앞에 `\.!'를 붙여 치명적 오류로 보고했다.

보충: \GO/에서 |err|와 |derr|는 메서드다. 건너뛰기는 |bypassSignal| 값을 던지는
공황으로 한다. 이 공황은 명령 하나를 처리하는 코드를 감싼 함수가 받아서 되살린다.
치명적 오류는 원본에서 |exit(-2)|로 프로그램을 끝냈는데, 여기서는 |fatalSignal| 값을
던지는 공황으로 |mmixal| 함수의 맨 바깥까지 빠져나간다. 그래야 시험 프로그램이 같은
프로세스 안에서 치명적 오류를 확인할 수 있다. 원본의 |panic|은 \GO/의 내장 함수 이름과
겹치므로 |fatal|이라고 불렀다. 문자 하나를 |%c|로 찍던 곳에서는, 126을 넘는 바이트도
원본처럼 그대로 찍히도록 |%s|와 함수 |ch|를 쓴다.

@<함수들@>=
func (a *assembler) err(m string) {
	a.reportError(m)
	if m[0] != '*' {
		panic(bypassSignal{})
	}
}

func (a *assembler) derr(format string, args ...any) {
	a.err(fmt.Sprintf(format, args...))
}

func (a *assembler) fatal(format string, args ...any) {
	a.reportError("!" + fmt.Sprintf(format, args...))
}

func ch(c byte) string { return string([]byte{c}) }

@ @<타입 정의@>=
type bypassSignal struct{} // a signal to skip the rest of the current instruction
type fatalSignal struct{}  // a signal to end the assembly

@ 파일 이름이 아직 정해지지 않았을 때(예컨대 소스 파일을 열지 못했을 때) 원본은
``\.{(nofile)}''이라고 찍었다.

@<함수들@>=
func (a *assembler) reportError(message string) {
	name := "(nofile)"
	if a.curFile < len(a.filename) {
		name = a.filename[a.curFile]
	}
	switch message[0] {
	case '*':
		fmt.Fprintf(a.stderr, "\"%s\", line %d warning: %s\n", name, a.lineNo, message[1:])
	case '!':
		fmt.Fprintf(a.stderr, "\"%s\", line %d fatal error: %s\n", name, a.lineNo, message[1:])
	default:
		fmt.Fprintf(a.stderr, "\"%s\", line %d: %s!\n", name, a.lineNo, message)
		a.errCount++
	}
	if a.listingFile != nil {
		@<오류 메시지를 목록에도 적는다@>
	}
	if message[0] == '!' {
		panic(fatalSignal{})
	}
}

@ @<오류 메시지를 목록에도 적는다@>=
if !a.lineListed {
	a.flushListingLine("****************** ")
}
switch message[0] {
case '*':
	fmt.Fprintf(a.listingFile, "************ warning: %s\n", message[1:])
case '!':
	fmt.Fprintf(a.listingFile, "******** fatal error: %s!\n", message[1:])
default:
	fmt.Fprintf(a.listingFile, "********** error: %s!\n", message)
}

@ @<어셈블러의 상태@>=
errCount int // this many errors were found

@ 이진 목적 파일 |objFile|로의 출력은 한 번에 네 바이트씩 일어난다. 바이트들은 테트라바이트
하나로 출력하지 않고 작은 버퍼에 모아서 출력한다. 어셈블러가 작은 끝(little-endian)
기계에서 돌더라도 출력은 큰 끝이기를 바라기 때문이다.
@^big-endian versus little-endian@>
@^little-endian versus big-endian@>

원본의 |mmo_write|는 매크로였다. 여기서는 메서드이며, 쓰기에 실패하면 치명적 오류를 낸다.

@<함수들@>=
func (a *assembler) mmoWrite(buf []byte) {
	if _, err := a.objFile.Write(buf); err != nil {
		a.fatal("Can't write on %s", a.objFileName)
@.Can't write...@>
	}
}

@ 메서드 |mmoClear|는 |heldBits!=0|일 때 |holdBuf|를 비운다. 붙잡아 둔 테트라가 탈출 코드로
시작하면 먼저 |lopQuote|를 내보낸다. 메서드 |mmoOut|은 |mmoBuf|의 내용을 출력하는데, 그 전에
붙잡아 둔 바이트가 있으면 먼저 내보낸다.

@<함수들@>=
func (a *assembler) mmoClear() {
	if a.holdBuf[0] == mm {
		a.mmoWrite([]byte{mm, lopQuote, 0, 1})
	}
	a.mmoWrite(a.holdBuf[:])
	if a.listingFile != nil && a.listingBits != 0 {
		a.listingClear()
	}
	a.heldBits = 0
	a.holdBuf = [4]byte{}
	a.mmoCurLoc = (a.mmoCurLoc + 4) &^ 3
	if a.mmoLineNo != 0 {
		a.mmoLineNo++
	}
}

func (a *assembler) mmoOut() {
	if a.heldBits != 0 {
		a.mmoClear()
	}
	a.mmoWrite(a.mmoBuf[:])
}

@ @<어셈블러의 상태@>=
mmoBuf [4]byte // tetrabyte waiting to be output
mmoPtr int     // bytes counted while outputting the symbol table

@ 테트라바이트 하나, 바이트 하나, 적재기 연산 하나를 내보내는 서브루틴들이다.

@<함수들@>=
func (a *assembler) mmoTetra(t Tetra) {
	a.mmoBuf = [4]byte{byte(t >> 24), byte(t >> 16), byte(t >> 8), byte(t)}
	a.mmoOut()
}

func (a *assembler) mmoByte(b byte) {
	a.mmoBuf[a.mmoPtr&3] = b
	a.mmoPtr++
	if a.mmoPtr&3 == 0 {
		a.mmoOut()
	}
}

func (a *assembler) mmoLop(x, y, z byte) { // output a loader operation
	a.mmoBuf = [4]byte{mm, x, y, z}
	a.mmoOut()
}

func (a *assembler) mmoLopp(x byte, yz uint16) { // output a loader operation with two-byte operand
	a.mmoBuf = [4]byte{mm, x, byte(yz >> 8), byte(yz)}
	a.mmoOut()
}

@ 서브루틴 |mmoLoc|은 목적 파일의 현재 위치를 |curLoc|과 같게 만든다. 차이가
\Hex{10000}보다 작으면 |lopSkip|으로 건너뛰고, 아니면 |lopLoc|으로 새 위치를 준다. 주소의
높은 테트라바이트에서 맨 위 바이트 말고 다른 비트가 켜져 있지 않으면, 맨 위 바이트를
Y~필드에 넣고 테트라 하나만 쓴다.

@<함수들@>=
func (a *assembler) mmoLoc() {
	if a.heldBits != 0 {
		a.mmoClear()
	}
	o := a.curLoc - a.mmoCurLoc
	if o < 0x10000 {
		if o != 0 {
			a.mmoLopp(lopSkip, uint16(o))
		}
	} else {
		if (a.curLoc>>32)&0xffffff != 0 {
			a.mmoLop(lopLoc, 0, 2)
			a.mmoTetra(Tetra(a.curLoc >> 32))
		} else {
			a.mmoLop(lopLoc, byte(a.curLoc>>56), 1)
		}
		a.mmoTetra(Tetra(a.curLoc))
	}
	a.mmoCurLoc = a.curLoc
}

@ 마찬가지로 서브루틴 |mmoSync|는 출력 파일의 현재 파일과 줄 번호가 |curFile|, |lineNo|와
맞는지 확인한다. 파일 이름은 처음 나올 때만 글자들을 적고, 그다음부터는 번호만 적는다.

@<함수들@>=
func (a *assembler) mmoSync() {
	if a.curFile != a.mmoCurFile {
		if a.filenamePassed[a.curFile] {
			a.mmoLop(lopFile, byte(a.curFile), 0)
		} else {
			@<파일 이름을 적는 |lopFile|을 출력한다@>
			a.filenamePassed[a.curFile] = true
		}
		a.mmoCurFile = a.curFile
		a.mmoLineNo = 0
	}
	if a.lineNo != a.mmoLineNo {
		if a.lineNo >= 0x10000 {
			a.fatal("I can't deal with line numbers exceeding 65535")
@.I can't deal with...@>
		}
		a.mmoLopp(lopLine, uint16(a.lineNo))
		a.mmoLineNo = a.lineNo
	}
}

@ @<파일 이름을 적는 |lopFile|을 출력한다@>=
name := a.filename[a.curFile]
a.mmoLop(lopFile, byte(a.curFile), byte((len(name)+3)>>2))
j := 0
for i := 0; i < len(name); i, j = i+1, (j+1)&3 {
	a.mmoBuf[j] = name[i]
	if j == 3 {
		a.mmoOut()
	}
}
if j != 0 {
	for ; j < 4; j++ {
		a.mmoBuf[j] = 0
	}
	a.mmoOut()
}

@ @<어셈블러의 상태@>=
mmoCurLoc      Octa      // current location in the object file
mmoLineNo      int       // current line number in the \.{mmo} output so far
mmoCurFile     int       // index of the current file in the \.{mmo} output so far
filenamePassed [256]bool // has a filename been recorded in the output?

@ 다음은 |curLoc|에서부터 |k|바이트를 어셈블하는 기본 서브루틴이다. 크기 |k|의 값은 1, 2, 4
가운데 하나여야 하고, |curLoc|은 |k|의 배수여야 한다. 매개변수 |xBits|는 어느 바이트가
(있다면) 앞선 참조의 일부인지를 알려 준다.

보충: 특수 모드에서는 목적 파일의 위치 대신 특수 데이터 안의 바이트 수 |specModeLoc|을
위치로 쓴다. 맞춤이 어긋나면 붙잡아 둔 바이트들을 내보내고 다음 경계로 건너뛰는데, 바이트
하나 뒤에 와이드가 오는 경우만은 빈 바이트 하나를 끼워 같은 테트라 안에 둔다. 보통 모드에서는
|curLoc|의 맨 위 세 비트가 0일 때, 곧 세그먼트~0에 어셈블할 때만 줄 번호를 동기화한다.

@<함수들@>=
func (a *assembler) assemble(k int, dat Tetra, xBits byte) {
	var l int
	if a.specMode {
		l = int(a.specModeLoc)
		if l&(k-1) != 0 {
			if a.heldBits == 1 && k == 2 {
				l++
				a.specModeLoc, a.holdBuf[1], a.heldBits = Tetra(l), 0, 3
			} else {
				l = (l + k) & -k
				a.specModeLoc = Tetra(l)
				a.mmoClear()
			}
		}
	} else {
		l = int(Tetra(a.curLoc))
		@<|curLoc|와 |mmoCurLoc|이 같은 테트라바이트를 가리키게 한다@>
		if a.heldBits == 0 && a.curLoc>>61 == 0 {
			a.mmoSync()
		}
	}
	@<|dat|의 바이트 |k|개를 |holdBuf|에 넣는다@>
	if a.specMode {
		a.specModeLoc += Tetra(k)
	} else {
		a.curLoc += Octa(k)
	}
}

@ @<|dat|의 바이트...@>=
for j := 0; j < k; j++ {
	jj := (l + j) & 3
	a.holdBuf[jj] = byte(dat >> (8 * (k - 1 - j)))
	a.heldBits |= 1 << jj
	a.listingBits |= 1 << jj
}
a.listingBits |= xBits
if (l+k)&3 == 0 {
	a.mmoClear()
}

@ @<|curLoc|와 |mmoCurLoc|이...@>=
if (a.curLoc^a.mmoCurLoc)&^3 != 0 {
	a.mmoLoc()
}

@* 기호표. 기호는 Bentley와 Sedgewick의 발상을 따르는 {\it 삼진 탐색 트라이\/}({\it ternary
search trie\/})로 저장하고 꺼낸다. ({\sl ACM--SIAM Symp.\ on Discrete Algorithms\/ \bf8}
(1997), 360--369; R.~Sedgewick, {\sl Algorithms in C\/} (Reading, Mass.:\
Addison--Wesley, 1998), \S15.4를 보라.) 트라이의 마디마다 문자 하나가 저장되고, 주어진
@^Bentley, Jon Louis@>
@^Sedgewick, Robert@>
문자가 트라이의 문자보다 작을 때, 같을 때, 클 때 각각에 해당하는 부분 트라이로의 가지가
있다. 또 현재 마디에서 끝나는 기호가 있으면 기호표 항목을 가리키는 포인터가 있다.

@<타입 정의@>=
type trieNode struct {
	ch               uint16    // the (possibly wyde) character stored here
	left, mid, right *trieNode // downward in a ternary trie
	sym              *symNode  // equivalents of symbols
}

@ 원본은 트라이 마디를 한 번에 1000개씩 덩어리로 할당하고, 다 쓰면 ``Capacity exceeded:
Out of trie memory''라며 멈추었다. \GO/에서는 마디가 필요할 때마다 |&trieNode{}|로 만들면
된다. 쓰레기 수집기가 알아서 치운다.

@<어셈블러의 상태@>=
trieRoot  *trieNode // root of the trie
opRoot    *trieNode // root of subtrie for opcodes
curPrefix *trieNode // root of subtrie for unqualified symbols

@ 서브루틴 |trieSearch|는 트라이의 주어진 마디에서 출발해서 그 가운데 부분 트라이에서
주어진 문자열을 찾는다. 필요하면 새 마디를 끼워 넣는다. 문자열은 글자도 숫자도 아닌 첫
문자에서 끝난다. 원본은 끝낸 문자의 위치를 전역 변수 |terminator|에 넣었다. 여기서는
그 색인을 둘째 반환값으로 돌려준다. 문자열은 조각 |s|의 색인 |i|부터 시작하며, 조각이
끝나는 곳도 문자열의 끝이다.

원본은 새 마디를 만들 때 |goto store_new_char|로 문자를 저장하는 곳으로 뛰었다. 여기서는
새 마디를 만들 때부터 문자를 넣어 둔다. 그러면 바로 다음의 비교가 일치하여 루프가 저절로
끝나므로, 같은 일이 |goto| 없이 된다.

@<함수들@>=
func isLetter(c byte) bool {
	return 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || c == '_' || c == ':' || c > 126
}

func trieSearch(t *trieNode, s []byte, i int) (*trieNode, int) {
	tt := t
	for i < len(s) && (isLetter(s[i]) || isDigit(s[i])) {
		c := uint16(s[i])
		if tt.mid == nil {
			tt.mid = &trieNode{ch: c}
		}
		tt = tt.mid
		for c != tt.ch {
			if c < tt.ch {
				if tt.left == nil {
					tt.left = &trieNode{ch: c}
				}
				tt = tt.left
			} else {
				if tt.right == nil {
					tt.right = &trieNode{ch: c}
				}
				tt = tt.right
			}
		}
		i++
	}
	return tt, i
}

@ 기호표 마디는 정의된 기호의 일련번호와 등가를 담는다. 또한 정의되지 않은 기호에 대해서는
``고침 정보''(fixup information)를 담는다. 이 정보 덕분에 적재기는 그런 기호를 가리키던,
앞서 어셈블된 명령들을 그 기호가 마침내 정의될 때 고칠 수 있다.

정의된 기호의 기호표 마디에서 필드 |link|는 특별한 코드 |defined|, |register|,
|predefined| 가운데 하나이고, |equiv| 필드는 정의된 값을 담는다. 일련번호 |serial|은
사용자가 정의한 모든 기호의 유일한 식별자다.

정의되지 않은 기호의 기호표 마디에서는 |equiv| 필드를 무시한다. 필드 |link|는 고침 정보의
첫 마디를 가리키고, 그 마디는 다시 다른 고침 마디로 이어질 수 있는 기호표 마디다. 고침
마디의 일련번호는 0이나 1이나 2인데, 각각 ``|equiv|가 가리키는 옥타바이트를 고쳐라,''
``|equiv|가 가리키는 명령의 YZ 필드의 상대 주소를 고쳐라,'' ``|equiv|가 가리키는 명령의
XYZ 필드의 상대 주소를 고쳐라''를 뜻한다.

보충: 원본은 특별한 코드를 포인터 값 1, 2, 3으로 흉내 냈다. \GO/에서는 그런 거짓 포인터를
만들 수 없으므로, 아무 데도 쓰이지 않는 마디 세 개를 만들어 그 주소를 코드로 쓴다. 비교
|pp.link==defined| 같은 원본의 표현이 그대로 살아남는다.

@<타입 정의@>=
type symNode struct {
	serial int      // serial number of symbol; type number for fixups
	link   *symNode // |defined| status or link to fixup
	equiv  Octa     // the equivalent value
}

@ @<표@>=
var (
	defined    = new(symNode) // code value for octabyte equivalents
	register   = new(symNode) // code value for register-number equivalents
	predefined = new(symNode) // code value for not-yet-used predefined equivalents
)

@ @<상수@>=
const (
	fixO   = 0 // |serial| code for octabyte fixup
	fixYZ  = 1 // |serial| code for relative fixup
	fixXYZ = 2 // |serial| code for \.{JMP} fixup
)

@ 원본은 기호표 마디도 트라이 마디처럼 덩어리로 할당하고, 더 이상 필요 없어진 고침 마디를
``재활용'' 목록에 모아 다시 썼다. 쓰레기 수집기가 있는 \GO/에서는 둘 다 필요 없으므로,
새 마디를 만들고 원하면 일련번호를 붙이는 일만 남는다.

@<함수들@>=
func (a *assembler) newSymNode(serialize bool) *symNode {
	p := new(symNode)
	if serialize {
		a.serialNumber++
		p.serial = a.serialNumber
	}
	return p
}

@ @<어셈블러의 상태@>=
serialNumber int

@ 트라이는 미리 정의된 모든 기호를 끼워 넣어 초기화한다. 연산 코드에는 보통 기호와
구별하려고 접두어 \.{\^}를 붙인다. 이 문자는 대문자와 소문자 사이를 멋지게 가른다.

보충: {\mc ASCII}에서 \.{\^}의 코드는 \Hex{5e}로, 대문자(\Hex{41}--\Hex{5a})보다 크고
소문자(\Hex{61}--\Hex{7a})보다 작다. 그래서 연산 코드들의 부분 트라이 뿌리 \.{\^}는
대문자로 시작하는 기호들과 소문자로 시작하는 기호들 사이에 자리 잡는다.

@<모든 것을 초기화한다@>=
a.trieRoot = &trieNode{ch: ':'}
a.curPrefix = a.trieRoot
a.opRoot = &trieNode{ch: '^'}
a.trieRoot.mid = a.opRoot
@<\MMIX\ 연산 코드와 \MMIXAL\ 유사 연산을 트라이에 넣는다@>
@<특수 레지스터 이름을 트라이에 넣는다@>
@<그 밖의 미리 정의된 기호를 트라이에 넣는다@>

@ 어셈블 작업의 대부분은 표에 따라 할 수 있다. 표의 내용은 \.{\^ADD} 같은 연산 코드
기호의 ``등가''로 저장된 비트들이다.

@<상수@>=
const (
	relAddrBit  = 0x1      // is YZ or XYZ relative?
	immedBit    = 0x2      // should opcode be immediate if Z or YZ not register?
	zarBit      = 0x4      // should register status of Z be ignored?
	zrBit       = 0x8      // must Z be a register?
	yarBit      = 0x10     // should register status of Y be ignored?
	yrBit       = 0x20     // must Y be a register?
	xarBit      = 0x40     // should register status of X be ignored?
	xrBit       = 0x80     // must X be a register?
	yzarBit     = 0x100    // should register status of YZ be ignored?
	yzrBit      = 0x200    // must YZ be a register?
	xyzarBit    = 0x400    // should register status of XYZ be ignored?
	xyzrBit     = 0x800    // must XYZ be a register?
	oneArgBit   = 0x1000   // is it OK to have zero or one operand?
	twoArgBit   = 0x2000   // is it OK to have exactly two operands?
	threeArgBit = 0x4000   // is it OK to have exactly three operands?
	manyArgBit  = 0x8000   // is it OK to have more than three operands?
	alignBits   = 0x30000  // how much alignment: byte, wyde, tetra, or octa?
	noLabelBit  = 0x40000  // should the label be blank?
	memBit      = 0x80000  // must YZ be a memory reference?
	specBit     = 0x100000 // is this opcode allowed in \.{SPEC} mode?
)

@ 원본에서 유사 연산의 번호는 열거형 \KW{pseudo\_op}의 값이었다. 모두 \Hex{100} 이상이라서
진짜 \MMIX\ 연산 코드(\Hex{00}--\Hex{ff})와 겹치지 않는다.

@<타입 정의@>=
type opSpec struct {
	name string // symbolic opcode
	code Tetra  // numeric opcode
	bits Tetra  // treatment of operands
}

@ @<상수@>=
const (
	SET = 0x100 + iota
	IS
	LOC
	PREFIX
	BSPEC
	ESPEC
	GREG
	LOCAL
	BYTE
	WYDE
	TETRA
	OCTA
)

@ 다음 표는 모든 \MMIX\ 연산 코드와 \MMIXAL\ 유사 연산의 이름, 수로 된 연산 코드, 그리고
피연산자를 다루는 방법을 나타내는 비트들을 담는다.

보충: 비트들을 읽는 법을 한 번 보자. \.{ADD}의 \Hex{240a2}는
$\Hex{20000}+\Hex{4000}+\Hex{80}+\Hex{20}+\Hex{2}$, 곧 ``테트라로 맞추고(|alignBits|의
값 2), 피연산자는 정확히 셋이며, X와 Y는 레지스터여야 하고, Z가 레지스터가 아니면
\.{ADDI}로 바꾼다''이다. \.{TRAP}의 \Hex{27554}는 피연산자가 하나에서 셋까지일 수 있고
(\Hex{7000}), 모든 필드의 레지스터 상태를 무시한다(\Hex{554})는 뜻이다. 조건 분기의
\Hex{22081}은 피연산자가 둘이고, X는 레지스터여야 하며, YZ는 상대 주소라는 뜻이다. 메모리
연산의 \Hex{a60a2}에는 |memBit|과 |twoArgBit|이 더 들어 있어서, 앞에서 말한 기준 주소를
쓰는 두 피연산자 꼴이 허용된다. 별칭 \.{LDA}의 수로 된 연산 코드는 \.{ADDU}의 것
\Hex{22}다.

@<표@>=
var opInitTable = []opSpec{
	@<연산 코드 표@>
}

@ @<연산 코드 표@>=
{"TRAP", 0x00, 0x27554}, {"FCMP", 0x01, 0x240a8}, {"FUN", 0x02, 0x240a8}, {"FEQL", 0x03, 0x240a8},
@.TRAP@>@.FCMP@>@.FUN@>@.FEQL@>
{"FADD", 0x04, 0x240a8}, {"FIX", 0x05, 0x26288}, {"FSUB", 0x06, 0x240a8}, {"FIXU", 0x07, 0x26288},
@.FADD@>@.FIX@>@.FSUB@>@.FIXU@>
{"FLOT", 0x08, 0x26282}, {"FLOTU", 0x0a, 0x26282}, {"SFLOT", 0x0c, 0x26282}, {"SFLOTU", 0x0e, 0x26282},
@.FLOT@>@.FLOTU@>@.SFLOT@>@.SFLOTU@>
{"FMUL", 0x10, 0x240a8}, {"FCMPE", 0x11, 0x240a8}, {"FUNE", 0x12, 0x240a8}, {"FEQLE", 0x13, 0x240a8},
@.FMUL@>@.FCMPE@>@.FUNE@>@.FEQLE@>
{"FDIV", 0x14, 0x240a8}, {"FSQRT", 0x15, 0x26288}, {"FREM", 0x16, 0x240a8}, {"FINT", 0x17, 0x26288},
@.FDIV@>@.FSQRT@>@.FREM@>@.FINT@>
{"MUL", 0x18, 0x240a2}, {"MULU", 0x1a, 0x240a2}, {"DIV", 0x1c, 0x240a2}, {"DIVU", 0x1e, 0x240a2},
@.MUL@>@.MULU@>@.DIV@>@.DIVU@>
{"ADD", 0x20, 0x240a2}, {"ADDU", 0x22, 0x240a2}, {"SUB", 0x24, 0x240a2}, {"SUBU", 0x26, 0x240a2},
@.ADD@>@.ADDU@>@.SUB@>@.SUBU@>
{"2ADDU", 0x28, 0x240a2}, {"4ADDU", 0x2a, 0x240a2}, {"8ADDU", 0x2c, 0x240a2}, {"16ADDU", 0x2e, 0x240a2},
@.2ADDU@>@.4ADDU@>@.8ADDU@>@.16ADDU@>

@ @<연산 코드 표@>=
{"CMP", 0x30, 0x240a2}, {"CMPU", 0x32, 0x240a2}, {"NEG", 0x34, 0x26082}, {"NEGU", 0x36, 0x26082},
@.CMP@>@.CMPU@>@.NEG@>@.NEGU@>
{"SL", 0x38, 0x240a2}, {"SLU", 0x3a, 0x240a2}, {"SR", 0x3c, 0x240a2}, {"SRU", 0x3e, 0x240a2},
@.SL@>@.SLU@>@.SR@>@.SRU@>
{"BN", 0x40, 0x22081}, {"BZ", 0x42, 0x22081}, {"BP", 0x44, 0x22081}, {"BOD", 0x46, 0x22081},
@.BN@>@.BZ@>@.BP@>@.BOD@>
{"BNN", 0x48, 0x22081}, {"BNZ", 0x4a, 0x22081}, {"BNP", 0x4c, 0x22081}, {"BEV", 0x4e, 0x22081},
@.BNN@>@.BNZ@>@.BNP@>@.BEV@>
{"PBN", 0x50, 0x22081}, {"PBZ", 0x52, 0x22081}, {"PBP", 0x54, 0x22081}, {"PBOD", 0x56, 0x22081},
@.PBN@>@.PBZ@>@.PBP@>@.PBOD@>
{"PBNN", 0x58, 0x22081}, {"PBNZ", 0x5a, 0x22081}, {"PBNP", 0x5c, 0x22081}, {"PBEV", 0x5e, 0x22081},
@.PBNN@>@.PBNZ@>@.PBNP@>@.PBEV@>
{"CSN", 0x60, 0x240a2}, {"CSZ", 0x62, 0x240a2}, {"CSP", 0x64, 0x240a2}, {"CSOD", 0x66, 0x240a2},
@.CSN@>@.CSZ@>@.CSP@>@.CSOD@>
{"CSNN", 0x68, 0x240a2}, {"CSNZ", 0x6a, 0x240a2}, {"CSNP", 0x6c, 0x240a2}, {"CSEV", 0x6e, 0x240a2},
@.CSNN@>@.CSNZ@>@.CSNP@>@.CSEV@>

@ @<연산 코드 표@>=
{"ZSN", 0x70, 0x240a2}, {"ZSZ", 0x72, 0x240a2}, {"ZSP", 0x74, 0x240a2}, {"ZSOD", 0x76, 0x240a2},
@.ZSN@>@.ZSZ@>@.ZSP@>@.ZSOD@>
{"ZSNN", 0x78, 0x240a2}, {"ZSNZ", 0x7a, 0x240a2}, {"ZSNP", 0x7c, 0x240a2}, {"ZSEV", 0x7e, 0x240a2},
@.ZSNN@>@.ZSNZ@>@.ZSNP@>@.ZSEV@>
{"LDB", 0x80, 0xa60a2}, {"LDBU", 0x82, 0xa60a2}, {"LDW", 0x84, 0xa60a2}, {"LDWU", 0x86, 0xa60a2},
@.LDB@>@.LDBU@>@.LDW@>@.LDWU@>
{"LDT", 0x88, 0xa60a2}, {"LDTU", 0x8a, 0xa60a2}, {"LDO", 0x8c, 0xa60a2}, {"LDOU", 0x8e, 0xa60a2},
@.LDT@>@.LDTU@>@.LDO@>@.LDOU@>
{"LDSF", 0x90, 0xa60a2}, {"LDHT", 0x92, 0xa60a2}, {"CSWAP", 0x94, 0xa60a2}, {"LDUNC", 0x96, 0xa60a2},
@.LDSF@>@.LDHT@>@.CSWAP@>@.LDUNC@>
{"LDVTS", 0x98, 0xa60a2}, {"PRELD", 0x9a, 0xa6022}, {"PREGO", 0x9c, 0xa6022}, {"GO", 0x9e, 0xa60a2},
@.LDVTS@>@.PRELD@>@.PREGO@>@.GO@>
{"STB", 0xa0, 0xa60a2}, {"STBU", 0xa2, 0xa60a2}, {"STW", 0xa4, 0xa60a2}, {"STWU", 0xa6, 0xa60a2},
@.STB@>@.STBU@>@.STW@>@.STWU@>
{"STT", 0xa8, 0xa60a2}, {"STTU", 0xaa, 0xa60a2}, {"STO", 0xac, 0xa60a2}, {"STOU", 0xae, 0xa60a2},
@.STT@>@.STTU@>@.STO@>@.STOU@>

@ @<연산 코드 표@>=
{"STSF", 0xb0, 0xa60a2}, {"STHT", 0xb2, 0xa60a2}, {"STCO", 0xb4, 0xa6022}, {"STUNC", 0xb6, 0xa60a2},
@.STSF@>@.STHT@>@.STCO@>@.STUNC@>
{"SYNCD", 0xb8, 0xa6022}, {"PREST", 0xba, 0xa6022}, {"SYNCID", 0xbc, 0xa6022}, {"PUSHGO", 0xbe, 0xa6062},
@.SYNCD@>@.PREST@>@.SYNCID@>@.PUSHGO@>
{"OR", 0xc0, 0x240a2}, {"ORN", 0xc2, 0x240a2}, {"NOR", 0xc4, 0x240a2}, {"XOR", 0xc6, 0x240a2},
@.OR@>@.ORN@>@.NOR@>@.XOR@>
{"AND", 0xc8, 0x240a2}, {"ANDN", 0xca, 0x240a2}, {"NAND", 0xcc, 0x240a2}, {"NXOR", 0xce, 0x240a2},
@.AND@>@.ANDN@>@.NAND@>@.NXOR@>
{"BDIF", 0xd0, 0x240a2}, {"WDIF", 0xd2, 0x240a2}, {"TDIF", 0xd4, 0x240a2}, {"ODIF", 0xd6, 0x240a2},
@.BDIF@>@.WDIF@>@.TDIF@>@.ODIF@>
{"MUX", 0xd8, 0x240a2}, {"SADD", 0xda, 0x240a2}, {"MOR", 0xdc, 0x240a2}, {"MXOR", 0xde, 0x240a2},
@.MUX@>@.SADD@>@.MOR@>@.MXOR@>
{"SETH", 0xe0, 0x22080}, {"SETMH", 0xe1, 0x22080}, {"SETML", 0xe2, 0x22080}, {"SETL", 0xe3, 0x22080},
@.SETH@>@.SETMH@>@.SETML@>@.SETL@>
{"INCH", 0xe4, 0x22080}, {"INCMH", 0xe5, 0x22080}, {"INCML", 0xe6, 0x22080}, {"INCL", 0xe7, 0x22080},
@.INCH@>@.INCMH@>@.INCML@>@.INCL@>

@ @<연산 코드 표@>=
{"ORH", 0xe8, 0x22080}, {"ORMH", 0xe9, 0x22080}, {"ORML", 0xea, 0x22080}, {"ORL", 0xeb, 0x22080},
@.ORH@>@.ORMH@>@.ORML@>@.ORL@>
{"ANDNH", 0xec, 0x22080}, {"ANDNMH", 0xed, 0x22080}, {"ANDNML", 0xee, 0x22080}, {"ANDNL", 0xef, 0x22080},
@.ANDNH@>@.ANDNMH@>@.ANDNML@>@.ANDNL@>
{"JMP", 0xf0, 0x21001}, {"PUSHJ", 0xf2, 0x22041}, {"GETA", 0xf4, 0x22081}, {"PUT", 0xf6, 0x22002},
@.JMP@>@.PUSHJ@>@.GETA@>@.PUT@>
{"POP", 0xf8, 0x23000}, {"RESUME", 0xf9, 0x21000}, {"SAVE", 0xfa, 0x22080}, {"UNSAVE", 0xfb, 0x23a00},
@.POP@>@.RESUME@>@.SAVE@>@.UNSAVE@>
{"SYNC", 0xfc, 0x21000}, {"SWYM", 0xfd, 0x27554}, {"GET", 0xfe, 0x22080}, {"TRIP", 0xff, 0x27554},
@.SYNC@>@.SWYM@>@.GET@>@.TRIP@>
{"SET", SET, 0x22180}, {"LDA", 0x22, 0xa60a2},
@.SET@>@.LDA@>
{"IS", IS, 0x101400}, {"LOC", LOC, 0x1400}, {"PREFIX", PREFIX, 0x141000},
@.IS@>@.LOC@>@.PREFIX@>
{"BYTE", BYTE, 0x10f000}, {"WYDE", WYDE, 0x11f000}, {"TETRA", TETRA, 0x12f000}, {"OCTA", OCTA, 0x13f000},
@.BYTE@>@.WYDE@>@.TETRA@>@.OCTA@>
{"BSPEC", BSPEC, 0x41400}, {"ESPEC", ESPEC, 0x141000},
@.BSPEC@>@.ESPEC@>
{"GREG", GREG, 0x101000}, {"LOCAL", LOCAL, 0x141800},
@.GREG@>@.LOCAL@>

@ 연산 코드를 넣을 때 기호표 마디의 등가는 높은 쪽에 수로 된 연산 코드를, 낮은 쪽에 비트들을
담는다. 이 마디들은 일련번호를 받지 않으므로 목적 파일의 기호표에 나가지 않는다.

@<\MMIX\ 연산 코드와 \MMIXAL\ 유사 연산을 트라이에 넣는다@>=
for _, op := range opInitTable {
	tt, _ = trieSearch(a.opRoot, []byte(op.name), 0)
	pp = a.newSymNode(false)
	tt.sym = pp
	pp.link = predefined
	pp.equiv = Octa(op.code)<<32 | Octa(op.bits)
}

@ @<지역 변수@>=
var tt *trieNode
var pp, qq *symNode

@ @<특수 레지스터 이름을 트라이에 넣는다@>=
for j, name := range specialName {
	tt, _ = trieSearch(a.trieRoot, []byte(name), 0)
	pp = a.newSymNode(false)
	tt.sym = pp
	pp.link = predefined
	pp.equiv = Octa(j)
}

@ @<표@>=
var specialName = [32]string{"rB", "rD", "rE", "rH", "rJ", "rM", "rR", "rBB",
	"rC", "rN", "rO", "rS", "rI", "rT", "rTT", "rK", "rQ", "rU", "rV", "rG", "rL",
	"rA", "rF", "rP", "rW", "rX", "rY", "rZ", "rWW", "rXX", "rYY", "rZZ"}
@^predefined symbols@>

@ @<타입 정의@>=
type predefSpec struct {
	name string
	h, l Tetra
}

@ 미리 정의된 그 밖의 기호들은 반올림 방식, 무한대, 세그먼트의 시작 주소, 산술 예외
비트와 그 처리기의 주소, 그리고 초보적인 \MMIX\ 운영체제의 입출력 호출 번호들이다.

@<표@>=
var predefs = []predefSpec{
	{"ROUND_CURRENT", 0, 0}, {"ROUND_OFF", 0, 1}, {"ROUND_UP", 0, 2},
	{"ROUND_DOWN", 0, 3}, {"ROUND_NEAR", 0, 4},
@:ROUND_CURRENT}\.{ROUND\_CURRENT@>@:ROUND_OFF}\.{ROUND\_OFF@>@:ROUND_UP}\.{ROUND\_UP@>
@:ROUND_DOWN}\.{ROUND\_DOWN@>@:ROUND_NEAR}\.{ROUND\_NEAR@>
	{"Inf", 0x7ff00000, 0},
@.Inf@>
	{"Data_Segment", 0x20000000, 0}, {"Pool_Segment", 0x40000000, 0},
	{"Stack_Segment", 0x60000000, 0},
@:Data_Segment}\.{Data\_Segment@>@:Pool_Segment}\.{Pool\_Segment@>
@:Stack_Segment}\.{Stack\_Segment@>
	{"D_BIT", 0, 0x80}, {"V_BIT", 0, 0x40}, {"W_BIT", 0, 0x20}, {"I_BIT", 0, 0x10},
	{"O_BIT", 0, 0x08}, {"U_BIT", 0, 0x04}, {"Z_BIT", 0, 0x02}, {"X_BIT", 0, 0x01},
@:D_BIT}\.{D\_BIT@>@:V_BIT}\.{V\_BIT@>@:W_BIT}\.{W\_BIT@>@:I_BIT}\.{I\_BIT@>
@:O_BIT}\.{O\_BIT@>@:U_BIT}\.{U\_BIT@>@:Z_BIT}\.{Z\_BIT@>@:X_BIT}\.{X\_BIT@>
	{"D_Handler", 0, 0x10}, {"V_Handler", 0, 0x20}, {"W_Handler", 0, 0x30},
	{"I_Handler", 0, 0x40}, {"O_Handler", 0, 0x50}, {"U_Handler", 0, 0x60},
	{"Z_Handler", 0, 0x70}, {"X_Handler", 0, 0x80},
@:D_Handler}\.{D\_Handler@>@:V_Handler}\.{V\_Handler@>@:W_Handler}\.{W\_Handler@>
@:I_Handler}\.{I\_Handler@>@:O_Handler}\.{O\_Handler@>@:U_Handler}\.{U\_Handler@>
@:Z_Handler}\.{Z\_Handler@>@:X_Handler}\.{X\_Handler@>
	{"StdIn", 0, 0}, {"StdOut", 0, 1}, {"StdErr", 0, 2},
@.StdIn@>@.StdOut@>@.StdErr@>
	{"TextRead", 0, 0}, {"TextWrite", 0, 1}, {"BinaryRead", 0, 2},
	{"BinaryWrite", 0, 3}, {"BinaryReadWrite", 0, 4},
@.TextRead@>@.TextWrite@>@.BinaryRead@>@.BinaryWrite@>@.BinaryReadWrite@>
	{"Halt", 0, 0}, {"Fopen", 0, 1}, {"Fclose", 0, 2}, {"Fread", 0, 3},
	{"Fgets", 0, 4}, {"Fgetws", 0, 5}, {"Fwrite", 0, 6}, {"Fputs", 0, 7},
	{"Fputws", 0, 8}, {"Fseek", 0, 9}, {"Ftell", 0, 10},
@.Halt@>@.Fopen@>@.Fclose@>@.Fread@>@.Fgets@>@.Fgetws@>
@.Fwrite@>@.Fputs@>@.Fputws@>@.Fseek@>@.Ftell@>
}
@^predefined symbols@>

@ @<그 밖의 미리 정의된 기호를 트라이에 넣는다@>=
for _, d := range predefs {
	tt, _ = trieSearch(a.trieRoot, []byte(d.name), 0)
	pp = a.newSymNode(false)
	tt.sym = pp
	pp.link = predefined
	pp.equiv = Octa(d.h)<<32 | Octa(d.l)
}

@ 어셈블을 시작할 때 \.{Main}을 트라이에 넣어 둔다. 그래야 사용자가 시작점을 지정하지
않았을 때 정의되지 않은 기호로 나타난다. \.{Main}이 늘 일련번호~1을 받는 까닭이
여기에 있다.
@.Main@>

@<모든 것을 초기화한다@>=
tt, _ = trieSearch(a.trieRoot, []byte("Main"), 0)
tt.sym = a.newSymNode(true)

@ 어셈블이 끝나면 기호표 전체를 훑으면서 기호를 사전 순서로 하나씩 방문하고, 트라이 구조를
출력 파일로 보낸다. 이때 정의되지 않은 앞선 참조도 찾아낸다.

순회 순서는 간단한 재귀 꼴을 가진다. 노드 |t|가 뿌리인 부분 트라이를 순회하려면
$$\vbox{\halign{#\hfil\cr
왼쪽 부분 트라이가 비어 있지 않으면 |t.left|를 순회하고,\cr
이 기호표 항목이 있으면 |t.sym|을 방문하고,\cr
가운데 부분 트라이가 비어 있지 않으면 |t.mid|를 순회하고,\cr
오른쪽 부분 트라이가 비어 있지 않으면 |t.right|를 순회한다.\cr
}}$$
이 꼴을 따르면 \.{mmo} 파일에서 간결한 표현을 얻는다. 대개 트라이 마디 하나에 두 바이트가
안 들고, 거기에 등가와 일련번호를 부호화하는 데 필요한 바이트가 더해질 뿐이다. 트라이의
마디마다 ``주 바이트''(master byte) 하나로 부호화하고, 그 뒤에 왼쪽 부분 트라이, 문자,
등가, 가운데 부분 트라이, 오른쪽 부분 트라이의 부호가 차례로 온다. 주 바이트는 다음을 더한
것이다.
$$\vbox{\halign{#\hfil\cr
문자가 한 바이트가 아니라 두 바이트를 차지하면 \Hex{80},\cr
왼쪽 부분 트라이가 비어 있지 않으면 \Hex{40},\cr
가운데 부분 트라이가 비어 있지 않으면 \Hex{20},\cr
오른쪽 부분 트라이가 비어 있지 않으면 \Hex{10},\cr
기호의 등가가 한 바이트에서 여덟 바이트 길이이면 \Hex{01}에서 \Hex{08},\cr
기호의 등가가 $2^{61}$ 더하기 한 바이트에서 여섯 바이트이면 \Hex{09}에서 \Hex{0e},\cr
기호의 등가가 \$0 더하기 한 바이트이면 \Hex{0f}.\cr}}$$
가운데 부분 트라이와 등가가 둘 다 비어 있으면 문자는 생략된다. 정의되지 않은 기호의
``등가''는 0이지만, 두 바이트 길이인 것으로 적는다. 기호의 등가 뒤에는 일련번호가 오는데,
기수~128의 바이트 하나 이상으로 나타낸다. 일련번호의 마지막 바이트에는 128을 더해 표시한다.
(그래서 일련번호 $2^{14}-1$은 \Hex{7fff}로, 일련번호 $2^{14}$은 \Hex{010080}으로
부호화된다.)

보충: \Hex{09}--\Hex{0e}는 데이터 세그먼트(\Hex{2000000000000000}부터 시작한다)의 주소를
위한 줄임이다. 적재기는 이 경우 읽은 값에 $2^{61}$을 더한다. \Hex{0f}는 레지스터 번호다.

@ 먼저 사용자가 다시 정의하지 않은 미리 정의된 기호를 모두 없애서 트라이의 가지를 친다.
쓸모 있는 것이 하나도 남지 않은 부분 트라이는 통째로 사라진다.

@<함수들@>=
func prune(t *trieNode) *trieNode {
	useful := false
	if t.sym != nil {
		if t.sym.serial != 0 {
			useful = true
		} else {
			t.sym = nil
		}
	}
	if t.left != nil {
		if t.left = prune(t.left); t.left != nil {
			useful = true
		}
	}
	if t.mid != nil {
		if t.mid = prune(t.mid); t.mid != nil {
			useful = true
		}
	}
	if t.right != nil {
		if t.right = prune(t.right); t.right != nil {
			useful = true
		}
	}
	if useful {
		return t
	}
	return nil
}

@ 그런 다음 재귀 순회 꼴을 따라 트라이를 출력한다.

@<함수들@>=
func (a *assembler) outStab(t *trieNode) {
	m := 0
	if t.ch > 0xff {
		m += 0x80
	}
	if t.left != nil {
		m += 0x40
	}
	if t.mid != nil {
		m += 0x20
	}
	if t.right != nil {
		m += 0x10
	}
	if t.sym != nil {
		@<주 바이트에 등가의 길이를 더한다@>
	}
	a.mmoByte(byte(m))
	if t.left != nil {
		a.outStab(t.left)
	}
	if m&0x2f != 0 {
		@<|t|를 방문하고 |t.mid|를 순회한다@>
	}
	if t.right != nil {
		a.outStab(t.right)
	}
}

@ @<주 바이트에 등가의 길이를 더한다@>=
switch {
case t.sym.link == register:
	m += 0xf
case t.sym.link == defined:
	@<|t.sym.equiv|의 길이를 부호화한다@>
case t.sym.link != nil || t.sym.serial == 1:
	@<정의되지 않은 기호를 보고한다@>
}

@ 필드 |symBuf|는 현재 트라이 마디까지 가운데 가지들을 따라 내려온 모든 문자를 담는다.
원본은 이것을 문자 배열과 포인터 |sym_ptr|로 다루었고, 999바이트가 넘는 기호에 대해서는
``엄밀히 말하면 이 한계를 넘는지 프로그램이 확인해야 하겠지만, 설마!''라고 적었다. \GO/의
조각은 필요한 만큼 늘어나므로 그 걱정도 사라진다.
@^Unicode@>

@<|t|를 방문하고...@>=
if m&0x80 != 0 {
	a.mmoByte(byte(t.ch >> 8))
}
a.mmoByte(byte(t.ch))
if m&0x80 != 0 {
	a.symBuf = append(a.symBuf, '?') // Unicode? not yet
} else {
	a.symBuf = append(a.symBuf, byte(t.ch))
}
m &= 0xf
if m != 0 && t.sym.link != nil {
	if a.listingFile != nil {
		@<기호 |symBuf|와 그 등가를 목록에 찍는다@>
	}
	@<등가와 일련번호를 출력한다@>
}
if t.mid != nil {
	a.outStab(t.mid)
}
a.symBuf = a.symBuf[:len(a.symBuf)-1]

@ 등가의 바이트 수는 |m|에서 되살린다. 레지스터(\Hex{0f})는 한 바이트이고, 데이터
세그먼트의 줄임(\Hex{09}--\Hex{0e})은 8을 뺀 만큼의 바이트다. 원본은 높은 쪽과 낮은 쪽
테트라바이트를 구별해 바이트를 꺼냈지만, 64비트에서는 |8*(m-1)|비트 옮기면 된다.

@<등가와 일련번호를 출력한다@>=
if m == 15 {
	m = 1
} else if m > 8 {
	m -= 8
}
for ; m > 0; m-- {
	a.mmoByte(byte(t.sym.equiv >> (8 * (m - 1))))
}
for m = 0; m < 4; m++ {
	if t.sym.serial < 1<<(7*(m+1)) {
		break
	}
}
for ; m >= 0; m-- {
	b := byte((t.sym.serial >> (7 * m)) & 0x7f)
	if m == 0 {
		b += 0x80
	}
	a.mmoByte(b)
}

@ 보충: 데이터 세그먼트의 주소라면 높은 테트라바이트에서 \Hex{20000000}을 뺀 나머지로
길이를 잰다. 높은 쪽에 남는 것이 있으면 네 바이트에 그 길이를 더하고, 없으면 낮은 쪽으로만
잰다. 길이는 1에서 4 사이다.

@<|t.sym.equiv|의 길이를...@>=
h := Tetra(t.sym.equiv >> 32)
x := h
if h&0xffff0000 == 0x20000000 {
	m += 8
	x = h - 0x20000000 // data segment
}
if x != 0 {
	m += 4
} else {
	x = Tetra(t.sym.equiv)
}
j := 1
for ; j < 4; j++ {
	if x < 1<<(8*j) {
		break
	}
}
m += j

@ @<어셈블러의 상태@>=
symBuf []byte // the characters of a symbol, gathered along middle branches

@ 완전히 한정된 기호마다 맨 앞의 `\.:'은 여기서 생략한다. \MMIXAL\ 사용자들은 대부분
\.{PREFIX} 기능이 필요 없을 것이기 때문이다. 이렇게 생략한 결과, \MMIXAL의 규칙이 허용하는
한 글자 기호~`\.:' 자체는 빈 문자열로 찍힌다.

@<기호 |symBuf|와 그 등가를...@>=
fmt.Fprintf(a.listingFile, " %s = ", a.symBuf[1:])
switch pp := t.sym; pp.link {
case defined:
	fmt.Fprintf(a.listingFile, "#%016x", pp.equiv)
case register:
	fmt.Fprintf(a.listingFile, "$%03d", Tetra(pp.equiv))
default:
	fmt.Fprintf(a.listingFile, "?")
}
fmt.Fprintf(a.listingFile, " (%d)\n", t.sym.serial)

@ 보충: 원본은 기호 버퍼의 끝에 현재 문자를 잠깐 써 넣고 찍었다. 여기서는 조각에 한 글자를
덧붙인 새 문자열을 찍는다.

@<정의되지 않은 기호를 보고한다@>=
c := byte(t.ch)
if m&0x80 != 0 {
	c = '?' // Unicode? not yet
}
fmt.Fprintf(a.stderr, "undefined symbol: %s\n", string(append(a.symBuf, c))[1:])
@.undefined symbol@>
a.errCount++
m += 2

@ 보충: 연산 코드들의 부분 트라이는 통째로 없앤 다음 가지를 친다. 기호표를 다 내보낸 뒤
마지막 테트라를 0으로 채우고, |lopEnd|에 기호표의 테트라 수를 적는다.

@<트라이를 점검하고 출력한다@>=
a.opRoot.mid = nil // annihilate all the opcodes
prune(a.trieRoot)
a.symBuf = a.symBuf[:0]
if a.listingFile != nil {
	fmt.Fprintf(a.listingFile, "\nSymbol table:\n")
}
a.mmoLop(lopStab, 0, 0)
a.outStab(a.trieRoot)
for a.mmoPtr&3 != 0 {
	a.mmoByte(0)
}
a.mmoLopp(lopEnd, uint16(a.mmoPtr>>2))

@* 식. 어셈블 과정에서 가장 복잡한 부분은 피연산자 필드의 식을 훑고 값을 매기는 일이다.
다행히 \MMIXAL의 식은 구조가 간단해서 스택에 바탕을 둔 방법으로 쉽게 다룰 수 있다.

피연산자 필드를 훑고 값을 매기는 동안, 스택 둘이 처리를 기다리는 데이터를 붙잡아 둔다.
스택 |opStack|에는 아직 수행하지 않은 연산자가, |valStack|에는 아직 쓰지 않은 값이 들어 있다.
피연산자 목록 전체를 훑고 나면 |opStack|은 비고, |valStack|에는 현재 명령을 어셈블하는 데
필요한 피연산자 값들이 남는다.

@ 스택 |opStack|의 항목은 여기 정의된 상수 값 가운데 하나를 가지며, 여기 정의된 우선순위 단계
가운데 하나를 가진다.

스택 |valStack|의 항목에는 |equiv|, |link|, |status| 필드가 있다. 식이 아직 아무 연산도
적용되지 않은 기호이면 |link|가 그 트라이 마디를 가리킨다.

@<타입 정의@>=
type stackOp int
type prec int
type stat int
type valNode struct {
	equiv  Octa      // current value
	link   *trieNode // trie reference for symbol
	status stat      // |pure|, |regVal|, |undefined|
}

@ @<상수@>=
const (
	negate stackOp = iota
	serialize
	complement
	registerize
	innerLP
	plus
	minus
	times
	over
	frac
	mod
	shl
	shr
	and
	or
	xor
	outerLP
	outerRP
	innerRP
)

const (
	zero prec = iota
	weak
	strong
	unary
)

const (
	pure stat = iota
	regVal
	undefined
)

@ 원본의 매크로 |top_op|, |top_val|, |next_val|은 각각 연산자 스택의 맨 위 항목, 값 스택의
맨 위 항목, 값 스택의 맨 위 바로 아래 항목이었다. 여기서는 메서드로 둔다. 값 스택의 항목은
제자리에서 고치므로 포인터를 돌려준다.

@<함수들@>=
func (a *assembler) topOp() stackOp     { return a.opStack[a.opPtr-1] }
func (a *assembler) topVal() *valNode  { return &a.valStack[a.valPtr-1] }
func (a *assembler) nextVal() *valNode { return &a.valStack[a.valPtr-2] }

@ @<어셈블러의 상태@>=
opStack  []stackOp // stack for pending operators
opPtr    int       // number of items on |opStack|
valStack []valNode // stack for pending operands
valPtr   int       // number of items on |valStack|
rtOp     stackOp   // newly scanned operator

@ 각 |stackOp| 값의 우선순위다. 단항 연산자 넷이 가장 강하고, 곱셈 같은 강한 이항 연산자가
그다음, 덧셈 같은 약한 이항 연산자가 그다음이다. 괄호들의 우선순위는 가장 낮다. 원본이
|acc|라는 전역 누산기를 두었던 것은 여기서 |mmixal| 함수의 지역 변수가 된다.

@<표@>=
var precedence = [...]prec{unary, unary, unary, unary, zero,
	weak, weak, strong, strong, strong, strong, strong, strong, strong, weak, weak,
	zero, zero, zero}

@ @<지역 변수@>=
var acc Octa // temporary accumulator

@ 원본은 두 스택을 |bufSize| 크기로 잡았다. 피연산자 필드가 입력 줄보다 길 수 없으므로
이것으로 넉넉하다. 여기서는 바깥 괄호 하나 몫을 더 잡는다.

@<모든 것을 초기화한다@>=
a.opStack = make([]stackOp, a.bufSize+1)
a.valStack = make([]valNode, a.bufSize+1)

@ 이 부분에 이르렀을 때 명령의 피연산자 필드는 이미 |operandList|라는 별도의 바이트
배열에 복사되어 있다.

원본의 구조는 이랬다. 상태 |scan_open|에서 여는 토큰들을 훑다가 값 하나를 |valStack|에 올리면,
|scan_close|에서 이항 연산자나 닫는 토큰 |rt_op|를 읽는다. 그런 다음 |opStack|의 맨 위
연산자가 |rt_op|보다 우선순위가 낮지 않은 동안 맨 위 연산을 수행하고, |hold_op|에서
|rt_op|를 |opStack|에 올린 뒤 다시 |scan_open|으로 간다. 피연산자 목록이 끝나면
|operands_done|으로 빠져나온다.

보충: 여기서는 이 흐름을 이름표 붙은 루프 셋으로 나타낸다. 바깥 루프 |scan|의 한 바퀴가
``값 하나와 그 뒤의 연산자 하나''를 처리한다. 그 안의 루프 |close|는 원본의 |scan_close|로
되돌아가는 경우(괄호가 짝을 찾았을 때, 왼쪽 괄호가 모자랄 때)를 위한 것이고, 가장 안쪽의
루프 |reduce|는 우선순위에 따라 연산을 수행한다. 문장 |break reduce|가 원본의 |goto hold_op|이고,
|continue close|가 |goto scan_close|이며, |break scan|이 |goto operands_done|이다.

@<피연산자 필드를 훑는다@>=
p = 0
a.valPtr = 0 // |valStack| is empty
a.opStack[0], a.opPtr = outerLP, 1 // |opStack| contains an ``outer left parenthesis''
scan:
for {
	@<|valStack|에 무언가를 올릴 때까지 여는 토큰들을 훑는다@>
close:
	for {
		@<이항 연산자나 닫는 토큰 |a.rtOp|를 훑는다@>
	reduce:
		for precedence[a.topOp()] >= precedence[a.rtOp] {
			@<|opStack|의 맨 위 연산을 수행한다@>
		}
		break
	}
	a.opStack[a.opPtr] = a.rtOp
	a.opPtr++
}

@ 빈 피연산자 목록 뒤에 오는 주석은 여기서 알아내야 한다.

보충: 예컨대 `\.{TRAP \% 멈춤}'에서는 피연산자 필드가 `\.\%'로 시작한다. 첫 문자에서 곧바로
문법 오류가 나면, 그 목록을 빈 것으로, 곧 `\.0'으로 취급한다. 원본에서 부호 `\.-'는
|negate|를 올린 뒤 `\.+'의 경우로 흘러내려 |goto scan_open|했다. 여기서는 둘 다 |continue
open|이다. 여는 토큰이 값 하나를 올리면 맨 끝의 |break|로 루프를 벗어난다.

@<|valStack|에 무언가를 올릴 때까지...@>=
open:
for {
	c := a.operandList[p]
	switch {
	case isLetter(c):
		@<기호를 훑는다@>
	case isDigit(c):
		switch a.operandList[p+1] {
		case 'F':
			@<앞쪽 지역 기호를 훑는다@>
		case 'B':
			@<뒤쪽 지역 기호를 훑는다@>
		default:
			@<십진 상수를 훑는다@>
		}
	default:
		p++
		switch c {
		case '#':
			@<십육진 상수를 훑는다@>
		case '\'':
			@<문자 상수를 훑는다@>
		case '"':
			@<문자열 상수를 훑는다@>
		case '@@':
			@<현재 위치를 훑는다@>
		@<단항 연산자와 여는 괄호를 |opStack|에 올리는 경우들@>
		default:
			@<빈 피연산자 목록으로 취급하거나 문법 오류를 보고한다@>
		}
	}
	break
}

@ @<단항 연산자와 여는 괄호를...@>=
case '-':
	a.opStack[a.opPtr] = negate
	a.opPtr++
	continue open
case '+':
	continue open
case '&':
	a.opStack[a.opPtr] = serialize
	a.opPtr++
	continue open
case '~':
	a.opStack[a.opPtr] = complement
	a.opPtr++
	continue open
case '$':
	a.opStack[a.opPtr] = registerize
	a.opPtr++
	continue open
case '(':
	a.opStack[a.opPtr] = innerLP
	a.opPtr++
	continue open

@ @<빈 피연산자 목록으로...@>=
if p == 1 { // treat operand list as empty
	a.operandList[0], a.operandList[1], p = '0', 0, 0
	continue open
}
if a.operandList[p-1] != 0 {
	a.derr("syntax error at character `%s'", ch(a.operandList[p-1]))
}
a.derr("syntax error after character `%s'", ch(a.operandList[p-2]))
@.syntax error...@>

@ 기호는 쌍점으로 시작하면 트라이의 뿌리에서, 아니면 현재 접두어에서 찾는다. 찾은 트라이
마디 |tt|를 값 스택에 올리는 일은 지역 기호에도 똑같이 쓰인다. 원본은 이 공통 부분을
|symbol_found|라는 이름표로 공유했는데, 여기서는 이름 있는 절로 만들어 세 곳에 끼워 넣는다.

@<기호를 훑는다@>=
if c == ':' {
	tt, p = trieSearch(a.trieRoot, a.operandList, p+1)
} else {
	tt, p = trieSearch(a.curPrefix, a.operandList, p)
}
@<기호 |tt|를 |valStack|에 올린다@>

@ 미리 정의된 기호가 처음 쓰이면 그 상태를 |defined|로 바꾼다. 그래야 나중에 사용자가 그
기호를 다른 값으로 다시 정의하려 할 때, 미리 정의된 값이 이미 쓰였다는 경고를 줄 수 있다.

@<기호 |tt|를...@>=
a.valPtr++
pp = tt.sym
if pp == nil {
	pp = a.newSymNode(true)
	tt.sym = pp
}
a.topVal().link, a.topVal().equiv = tt, pp.equiv
if pp.link == predefined {
	pp.link = defined
}
switch pp.link {
case defined:
	a.topVal().status = pure
case register:
	a.topVal().status = regVal
default:
	a.topVal().status = undefined
}

@ @<앞쪽 지역 기호를 훑는다@>=
tt = &a.forwardLocalHost[c-'0']
p += 2
@<기호 |tt|를...@>

@ @<뒤쪽 지역 기호를 훑는다@>=
tt = &a.backwardLocalHost[c-'0']
p += 2
@<기호 |tt|를...@>

@ 필드 |forwardLocalHost[j]|와 |backwardLocalHost[j]|는 트라이의 마디처럼 행세한다.

@<어셈블러의 상태@>=
forwardLocalHost, backwardLocalHost [10]trieNode
forwardLocal, backwardLocal         [10]symNode

@ 처음에 \.{0H}, \.{1H}, \dots, \.{9H}는 0으로 정의되어 있다. 그래서 아직 나오지 않은
지역 레이블을 뒤쪽으로 참조하면 0이 된다.

@<모든 것을 초기화한다@>=
for j = 0; j < 10; j++ {
	a.forwardLocalHost[j].sym = &a.forwardLocal[j]
	a.backwardLocalHost[j].sym = &a.backwardLocal[j]
	a.backwardLocal[j].link = defined
}

@ 문자 상수가 적법한지는 이미 확인해 두었다.

@<문자 상수를 훑는다@>=
acc = Octa(a.operandList[p])
p += 2
@<상수 |acc|를 |valStack|에 올린다@>

@ 문자열 상수는 멋진 요령으로 다룬다. 한 글자짜리 문자열이면 그냥 문자 상수와 같다. 그보다
길면 첫 문자를 상수로 삼고, 피연산자 목록 자체를 고쳐서 나머지가 새 문자열 상수가 되게
한다.

보충: 요령을 풀어 보자. 포인터 |p|가 \.{"abc"}의 \.a를 가리킨다고 하자. 코드는 \.a가 있던 칸에
\.{"}를 쓰고, 여는 따옴표가 있던 칸에 반점을 쓴 뒤 |p|를 그 반점으로 옮긴다. 그러면 남은
피연산자 목록은 \.{,"bc"}가 된다. 그래서 다음에 이항 연산자를 훑을 때 반점을 만나 피연산자
하나(\.{'a'})가 끝나고, 그다음 여는 토큰을 훑을 때 \.{"bc"}라는 새 문자열 상수를 만난다.
결국 \.{"abc"}는 \.{'a','b','c'}처럼 처리된다.

@<문자열 상수를 훑는다@>=
acc = Octa(a.operandList[p])
if a.operandList[p] == '"' {
	p++
	acc = 0
	a.err("*null string is treated as zero")
@.null string...@>
} else if a.operandList[p+1] == '"' {
	p += 2
} else {
	a.operandList[p] = '"'
	p--
	a.operandList[p] = ','
}
@<상수 |acc|를...@>

@ 원본은 십진 상수에 10을 곱할 때 \.{mmixarith}에서처럼 ``5를 곱하고, 2를 곱해 숫자를
더하는'' 두 걸음을 밟았다. 64비트 연산자로도 같은 모양을 지킨다.

@<십진 상수를 훑는다@>=
acc = Octa(c - '0')
for p++; isDigit(a.operandList[p]); p++ {
	acc = acc + acc<<2
	acc = acc<<1 + Octa(a.operandList[p]-'0')
}
@<상수 |acc|를...@>

@ 원본은 모든 상수가 공유하는 이 부분에 이름표 |constant_found|를 달아 두었다.

@<상수 |acc|를...@>=
a.valPtr++
a.topVal().link = nil
a.topVal().equiv = acc
a.topVal().status = pure

@ @<십육진 상수를 훑는다@>=
if !isXDigit(a.operandList[p]) {
	a.err("illegal hexadecimal constant")
@.illegal hexadecimal constant@>
}
acc = 0
for ; isXDigit(a.operandList[p]); p++ {
	d := a.operandList[p]
	switch {
	case d >= 'a':
		acc = acc<<4 + Octa(d-'a'+10)
	case d >= 'A':
		acc = acc<<4 + Octa(d-'A'+10)
	default:
		acc = acc<<4 + Octa(d-'0')
	}
}
@<상수 |acc|를...@>

@ @<현재 위치를 훑는다@>=
acc = a.curLoc
@<상수 |acc|를...@>

@ 보충: 널 문자나 반점은 피연산자 하나를 끝내는 ``바깥 오른쪽 괄호''다. 원본처럼 널 문자를
지나서도 |p|를 하나 늘리므로, 목록이 끝났는지는 나중에 |a.operandList[p-1]|로 알아본다.
\.{<<}와 \.{>>}는 두 글자가 같아야 한다.

@<이항 연산자나 닫는 토큰...@>=
c := a.operandList[p]
p++
switch c {
case '+':
	a.rtOp = plus
case '-':
	a.rtOp = minus
case '*':
	a.rtOp = times
case '/':
	if a.operandList[p] != '/' {
		a.rtOp = over
	} else {
		p++
		a.rtOp = frac
	}
case '%':
	a.rtOp = mod
case '<', '>':
	if c == '<' {
		a.rtOp = shl
	} else {
		a.rtOp = shr
	}
	p++
	if a.operandList[p-1] != a.operandList[p-2] {
		a.derr("syntax error at `%s'", ch(a.operandList[p-2]))
@.syntax error...@>
	}
case '&':
	a.rtOp = and
case '|':
	a.rtOp = or
case '^':
	a.rtOp = xor
case ')':
	a.rtOp = innerRP
case 0, ',':
	a.rtOp = outerRP
default:
	a.derr("syntax error at `%s'", ch(a.operandList[p-1]))
}

@ 안쪽 왼쪽 괄호가 안쪽 오른쪽 괄호를 만나면 짝이 맞은 것이므로, 오른쪽 괄호는 버리고 다음
이항 연산자를 읽는다. 바깥 왼쪽 괄호가 바깥 오른쪽 괄호(반점이나 목록 끝)를 만나면
피연산자 하나가 끝난 것이다. 그 값이 255보다 큰 레지스터 번호이면 256을 법으로 줄인다.
목록 끝이면 훑기를 마치고, 반점이면 새 바깥 왼쪽 괄호를 올린다. 바깥 왼쪽 괄호가 다른 닫는
토큰을 만나면 왼쪽 괄호가 모자란 것이다.

@<|opStack|의 맨 위 연산을...@>=
a.opPtr--
switch op := a.opStack[a.opPtr]; {
case op == innerLP:
	if a.rtOp == innerRP {
		continue close
	}
	a.err("*missing right parenthesis")
@.missing right parenthesis@>
case op == outerLP:
	if a.rtOp == outerRP {
		@<피연산자 하나를 마친다@>
	}
	a.opPtr++
	a.err("*missing left parenthesis")
@.missing left parenthesis@>
	continue close
case op < innerLP:
	@<단항 연산자의 경우들@>
	a.topVal().link = nil
default:
	@<이항 연산자의 경우들@>
	@<이항 연산을 마무리한다@>
}

@ @<피연산자 하나를...@>=
if a.topVal().status == regVal && a.topVal().equiv > 0xff {
	a.err("*register number too large, will be reduced mod 256")
@.register number...@>
	a.topVal().equiv &= 0xff
}
if a.operandList[p-1] == 0 {
	break scan
}
a.rtOp = outerLP // comma
break reduce

@ 이제 식에서 찾은 단항 연산자나 이항 연산자가 등가를 바꾸는 부분에 이르렀다.

가장 전형적이면서 어떤 면에서는 가장 다루기 까다로운 연산자는 이항 덧셈이다. 이 경우의
코드를 쓰고 나면 다른 경우들은 거의 저절로 해결된다.

보충: 원본에서 이항 연산의 공통 꼬리는 이름표 |fin_bin|이었다. 두 피연산자의 상태가 같으면
결과는 순수하고(순수+순수, 또는 레지스터$-$레지스터), 다르면 레지스터 번호다. 그다음 값
스택을 하나 줄이고, 새 맨 위 항목의 |link|를 지운다(원본의 이름표 |delink|). 연산을 거친
값은 더 이상 기호 그 자체가 아니기 때문이다.

@<이항 연산을 마무리한다@>=
if a.topVal().status == a.nextVal().status {
	a.nextVal().status = pure
} else {
	a.nextVal().status = regVal
}
a.valPtr--
a.topVal().link = nil

@ @<이항 연산자의 경우들@>=
top, next := a.topVal(), a.nextVal()
switch op {
case plus:
	if top.status == undefined {
		a.err("cannot add an undefined quantity")
@.cannot add...@>
	}
	if next.status == undefined {
		a.err("cannot add to an undefined quantity")
	}
	if top.status == regVal && next.status == regVal {
		a.err("cannot add two register numbers")
	}
	next.equiv += top.equiv
@<나머지 이항 연산자의 경우들@>
}

@ 원본의 매크로 |unary_check|는 순수하지 않은 값에 단항 연산자를 쓰면 ``can \dots\ pure values
only''라는 오류를 냈다. 일련번호 연산자 \.\&는 기호에만 쓸 수 있다.

@<단항 연산자의 경우들@>=
top := a.topVal()
switch op {
case negate:
	if top.status != pure {
		a.err("can negate pure values only")
@.can negate...@>
	}
	top.equiv = -top.equiv
case complement:
	if top.status != pure {
		a.err("can complement pure values only")
@.can complement...@>
	}
	top.equiv = ^top.equiv
case registerize:
	if top.status != pure {
		a.err("can registerize pure values only")
@.can registerize...@>
	}
	top.status = regVal
case serialize:
	if top.link == nil {
		a.err("can take serial number of symbol only")
@.can take serial number...@>
	}
	top.equiv = Octa(top.link.sym.serial)
	top.status = pure
}

@ 원본의 매크로 |binary_check|는 두 피연산자가 모두 순수한지 확인한다. 여기서는 작은
메서드로 둔다.

보충: 나눗셈과 나머지는 \.{mmixarith}의 |Div(0,y,z)|로, 분수 나눗셈은 |Div(y,0,z)|로 한다.
0으로 나누거나 적법하지 않은 분수를 만나면 경고만 하고 계속하는데, 그때 |Div|는 나누지 않고
피제수의 위 절반을 몫으로, 아래 절반을 나머지로 돌려준다. 그래서 $y/0=0$, $y\bmod 0=y$이고,
$x\ge y$인 분수 나눗셈 \.{x//y}의 값은 $x$ 그대로다. 자리 옮김은 63비트를 넘으면 0이다.

@<함수들@>=
func (a *assembler) binaryCheck(verb string) {
	if a.topVal().status != pure || a.nextVal().status != pure {
		a.derr("can %s pure values only", verb)
	}
}

@ @<나머지 이항 연산자의 경우들@>=
case minus:
	if top.status == undefined {
		a.err("cannot subtract an undefined quantity")
@.cannot subtract...@>
	}
	if next.status == undefined {
		a.err("cannot subtract from an undefined quantity")
	}
	if top.status == regVal && next.status != regVal {
		a.err("cannot subtract register number from pure value")
	}
	next.equiv -= top.equiv
case times:
	a.binaryCheck("multiply")
@.can multiply...@>
	next.equiv *= top.equiv
case over, mod:
	a.binaryCheck("divide")
@.can divide...@>
	if top.equiv == 0 {
		a.err("*division by zero")
@.division by zero@>
	}
	q, r := mmixarith.Div(0, next.equiv, top.equiv)
	if op == mod {
		next.equiv = r
	} else {
		next.equiv = q
	}

@ @<나머지 이항 연산자의 경우들@>=
case frac:
	a.binaryCheck("compute a ratio of")
@.can compute...@>
	if next.equiv >= top.equiv {
		a.err("*illegal fraction")
@.illegal fraction@>
	}
	next.equiv, _ = mmixarith.Div(next.equiv, 0, top.equiv)
case shl, shr:
	a.binaryCheck("compute a bitwise shift of")
	switch {
	case top.equiv > 63:
		next.equiv = 0
	case op == shl:
		next.equiv <<= top.equiv
	default:
		next.equiv >>= top.equiv
	}
case and:
	a.binaryCheck("compute bitwise and of")
	next.equiv &= top.equiv
case or:
	a.binaryCheck("compute bitwise or of")
	next.equiv |= top.equiv
case xor:
	a.binaryCheck("compute bitwise xor of")
	next.equiv ^= top.equiv

@* 명령어 어셈블하기. 이제 식의 수준에서 명령의 수준으로 올라가 보자. 줄이 시작될 때나,
현재 줄의 앞선 명령 끝의 쌍반점 뒤에서 프로그램의 이 부분에 이른다. 버퍼 안의 현재 위치는
|bufPtr|의 값이다.

보충: 원본의 이름표 |bypass|는 명령 하나를 처리하는 코드의 맨 끝에 있었고, 오류 매크로와
주석과 유사 연산이 모두 그리로 뛰었다. 여기서는 명령 하나를 처리하는 코드를 이름 없는 함수로
감싼다. 그러면 원본의 |goto bypass|는 그 함수에서의 |return|이 되고, 오류로 인한 건너뛰기는
그 함수의 |recover|가 받는다. 치명적 오류의 공황은 다시 던져서 바깥으로 보낸다. 처리를
시작할 때 |bufPtr|을 버퍼 끝의 널 문자로 옮겨 두므로, 오류로 건너뛰면 줄의 나머지가
버려진다. 오류가 없으면 피연산자 필드를 복사한 뒤 |bufPtr|을 쌍반점 다음으로 옮긴다.

@<다음 \MMIXAL\ 명령이나 주석을 처리한다@>=
func() {
	defer func() {
		if r := recover(); r != nil && r != (bypassSignal{}) {
			panic(r)
		}
	}()
	p = a.bufPtr
	a.bufPtr = len(a.buffer) - 1 // empty string
	@<레이블 필드를 훑는다; 없으면 |return|@>
	@<연산 코드 필드를 훑는다; 없으면 |return|@>
	@<피연산자 필드를 복사한다@>
	a.bufPtr = p
	if a.specMode && a.opBits&specBit == 0 {
		a.derr("cannot use `%s' in special mode", a.opField)
@.cannot use...@>
	}
	if a.opBits&noLabelBit != 0 && len(a.labField) > 0 {
		a.derr("*label field of `%s' instruction is ignored", a.opField)
		a.labField = a.labField[:0]
	}
@.label field...ignored@>
	if a.opBits&alignBits != 0 {
		@<위치 포인터를 맞춘다@>
	}
	@<피연산자 필드를 훑는다@>
	if a.opcode == GREG {
		@<전역 레지스터를 할당한다@>
	}
	if len(a.labField) > 0 {
		@<레이블을 정의한다@>
	}
	@<연산을 수행한다@>
}()

@ 보충: 레이블 필드 다음의 공백 하나는 무조건 건너뛴다(|p++|). 레이블 필드가 줄 전체를
차지하면 이때 |p|가 줄 끝의 널 문자를 넘어간다. 원본의 버퍼는 |fgets|가 줄바꿈 문자 뒤에
붙인 널 문자 덕분에 대개 그다음 칸도 널 문자였다. 그러나 파일이 줄바꿈 문자 없이 끝나면
그 칸에는 {\it 앞 줄의 찌꺼기\/}가 남아 있다. 옮긴이가 확인해 보니, 원본은 `\.{Main
SWYM 1,2,3}' 다음에 줄바꿈 없이 `\.{abc}'로 끝나는 파일을 받으면 `\.{abc}'를 레이블로
삼아 \.{SWYM 1,2,3}을 한 번 더 어셈블했다. 이 한글판은 줄 끝에 늘 널 문자 둘을 두므로,
그런 경우에도 줄바꿈이 있을 때처럼 ``no opcode'' 경고를 낸다. 이것이 입력 버퍼에 두 칸을
더 잡은 까닭이다.

@<레이블 필드를 훑는다...@>=
if a.buffer[p] == 0 {
	return
}
a.labField = a.labField[:0]
if !isSpace(a.buffer[p]) {
	if !isDigit(a.buffer[p]) && !isLetter(a.buffer[p]) {
		return // comment
	}
	for isDigit(a.buffer[p]) || isLetter(a.buffer[p]) {
		a.labField = append(a.labField, a.buffer[p])
		p++
	}
	if a.buffer[p] != 0 && !isSpace(a.buffer[p]) {
		a.derr("label syntax error at `%s'", ch(a.buffer[p]))
@.label syntax error...@>
	}
}
if len(a.labField) > 0 && isDigit(a.labField[0]) &&
	(len(a.labField) < 2 || a.labField[1] != 'H' || len(a.labField) > 2) {
	a.derr("improper local label `%s'", a.labField)
@.improper local label...@>
}
for p++; isSpace(a.buffer[p]); p++ {
}

@ 연산 코드 필드는 오류 메시지에서 기호로 된 연산 코드를 언급하고 싶을 수 있으므로 별도의
버퍼에 복사한다. 연산 코드는 부분 트라이 |opRoot|에서 찾는다.

@<연산 코드 필드를...@>=
a.opField = a.opField[:0]
for isLetter(a.buffer[p]) || isDigit(a.buffer[p]) {
	a.opField = append(a.opField, a.buffer[p])
	p++
}
if !isSpace(a.buffer[p]) && a.buffer[p] != 0 && len(a.opField) > 0 {
	a.derr("opcode syntax error at `%s'", ch(a.buffer[p]))
@.opcode syntax error...@>
}
tt, _ = trieSearch(a.opRoot, a.opField, 0)
pp = tt.sym
if pp == nil {
	if len(a.opField) > 0 {
		a.derr("unknown operation code `%s'", a.opField)
@.unknown operation code@>
	}
	if len(a.labField) > 0 {
		a.derr("*no opcode; label `%s' will be ignored", a.labField)
@.no opcode...@>
	}
	return
}
a.opcode, a.opBits = Tetra(pp.equiv>>32), Tetra(pp.equiv)
for isSpace(a.buffer[p]) {
	p++
}

@ @<어셈블러의 상태@>=
opcode Tetra // numeric code for \MMIX\ operation or \MMIXAL\ pseudo-op
opBits Tetra // flags describing an operator's special characteristics

@ 피연산자 필드는 별도의 버퍼에 복사한다. 그래야 나중에 문자열 상수를 훑으면서 고칠 수
있다. 문자 상수와 문자열 상수 안의 공백과 쌍반점은 필드를 끝내지 않는다. 필드 뒤에 쌍반점이
오지 않으면 줄의 나머지는 주석이다. 빈 피연산자 필드는 `\.0'으로 바꾼다.

@<피연산자 필드를 복사한다@>=
a.operandList = a.operandList[:0]
for a.buffer[p] != 0 {
	if a.buffer[p] == ';' {
		break
	}
	if a.buffer[p] == '\'' {
		a.operandList = append(a.operandList, a.buffer[p])
		p++
		if a.buffer[p] == 0 {
			a.err("incomplete character constant")
@.incomplete...constant@>
		}
		a.operandList = append(a.operandList, a.buffer[p])
		p++
		if a.buffer[p] != '\'' {
			a.err("illegal character constant")
@.illegal character constant@>
		}
	} else if a.buffer[p] == '"' {
		@<문자열 상수를 복사한다@>
	}
	a.operandList = append(a.operandList, a.buffer[p])
	p++
	if isSpace(a.buffer[p]) {
		break
	}
}
@<피연산자 필드 뒤를 정리한다@>

@ @<문자열 상수를 복사한다@>=
a.operandList = append(a.operandList, a.buffer[p])
for p++; a.buffer[p] != 0 && a.buffer[p] != '"'; p++ {
	a.operandList = append(a.operandList, a.buffer[p])
}
if a.buffer[p] == 0 {
	a.err("incomplete string constant")
}

@ @<피연산자 필드 뒤를...@>=
for isSpace(a.buffer[p]) {
	p++
}
if a.buffer[p] == ';' {
	p++
} else {
	p = len(a.buffer) - 1 // if not followed by semicolon, rest of the line is a comment
}
if len(a.operandList) == 0 {
	a.operandList = append(a.operandList, '0') // change empty operand field to `\.0'
}
a.operandList = append(a.operandList, 0)

@ 레이블을 정의하거나 피연산자 필드의 값을 매기기 전에 이 단계에서 맞춤을 하는 것이
중요하다. 변수 |alignBits|의 값 $j$가 0, 1, 2, 3이면 차례로 1, 2, 4, 8의 배수로 맞춘다.

@<위치 포인터를 맞춘다@>=
j = int((a.opBits & alignBits) >> 16)
a.curLoc = (a.curLoc + Octa(1<<j-1)) &^ Octa(1<<j-1)

@ 값이 0이 아닌 \.{GREG}는 같은 값의 기준 주소가 이미 있으면 그 레지스터를 다시 쓴다. 원본은
찾으면 |goto got_greg|로 새 레지스터 할당을 건너뛰었다.

@<전역 레지스터를 할당한다@>=
v := a.valStack[0].equiv
for j = a.greg; v != 0 && j < 255; j++ {
	if a.gregVal[j] == v {
		break
	}
}
if v != 0 && j < 255 {
	a.curGreg = j
} else {
	if a.greg == 32 {
		a.err("too many global registers")
@.too many global registers@>
	}
	a.greg--
	a.gregVal[a.greg] = v
	a.curGreg = a.greg
}

@ 레이블이 이를테면 \.{2H}라면, 피연산자의 값을 매길 때 \.{2B}의 옛 값을 이미 썼을 것이다.
게다가 \.{2F}라는 피연산자는 정의되지 않은 것으로 다루어졌을 텐데, 그것은 여전히 정의되지
않은 채다.

기호는 두 번 이상 정의될 수 있지만, 정의할 때마다 같은 등가 값을 줄 때에만 그렇다.

미리 정의된 기호를 다시 정의할 때, 그 미리 정의된 값이 이미 쓰였다면 경고 메시지를 준다.

보충: \.{IS}와 \.{GREG}의 레이블은 현재 위치가 아니라 피연산자의 값이나 레지스터 번호를
받는다. 원본은 그 값을 잠깐 |cur_loc|에 넣어 두고 레이블을 정의한 뒤 |acc|에 보관해 둔
현재 위치를 되돌렸다. 그런데 이 절 안에서 오류가 나면 되돌리기 전에 건너뛰게 된다. 이를테면
\.{x IS 5} 다음에 \.{x IS 6}이 오면 ``already defined'' 오류가 나고 현재 위치가 6으로
남는다. 이 한글판도 원본과 같이 동작한다.

@<레이블을 정의한다@>=
newLink := defined
acc = a.curLoc
if a.opcode == IS {
	if a.valStack[0].status == undefined {
		a.err("the operand is undefined")
@.the operand is undefined@>
	}
	a.curLoc = a.valStack[0].equiv
	if a.valStack[0].status == regVal {
		newLink = register
	}
} else if a.opcode == GREG {
	a.curLoc, newLink = Octa(a.curGreg), register
}
@<기호표 마디 |pp|를 찾는다@>
@<기호의 상태에 따라 정의를 점검하거나 앞선 참조들을 고친다@>
if isDigit(a.labField[0]) {
	pp = &a.backwardLocal[a.labField[0]-'0']
}
pp.equiv, pp.link = a.curLoc, newLink
@<|valStack|에 있을지 모르는 참조들을 고친다@>
if a.listingFile != nil && (a.opcode == IS || a.opcode == LOC) {
	@<레이블의 등가를 보여 주는 특별한 목록을 만든다@>
}
a.curLoc = acc

@ @<기호의 상태에 따라...@>=
switch {
case pp.link == defined || pp.link == register:
	if pp.equiv != a.curLoc || pp.link != newLink {
		if pp.serial != 0 {
			a.derr("symbol `%s' is already defined", a.labField)
@.symbol...already defined@>
		}
		a.serialNumber++
		pp.serial = a.serialNumber
		a.derr("*redefinition of predefined symbol `%s'", a.labField)
@.redefinition...@>
	}
case pp.link == predefined:
	a.serialNumber++
	pp.serial = a.serialNumber
case pp.link != nil:
	if newLink == register {
		a.err("future reference cannot be to a register")
@.future reference cannot...@>
	}
	for pp.link != nil {
		@<이 레이블에 대한 앞선 참조 하나를 고친다@>
	}
}

@ 보충: \.{2H}를 정의할 때 |pp|는 앞쪽 지역 기호 |forwardLocal|이다. \.{2F}에 대한 앞선
참조들은 거기에 걸려 있으므로 여기서 모두 고치고, 정의된 값은 뒤쪽 지역 기호 |backwardLocal|에
넣는다. 그러면 \.{2F}는 다시 정의되지 않은 상태가 되고, \.{2B}는 새 값을 가리킨다.

@<|valStack|에 있을지...@>=
if !isDigit(a.labField[0]) {
	for j = 0; j < a.valPtr; j++ {
		if a.valStack[j].status == undefined && a.valStack[j].link.sym == pp {
			if newLink == register {
				a.valStack[j].status = regVal
			} else {
				a.valStack[j].status = pure
			}
			a.valStack[j].equiv = a.curLoc
		}
	}
}

@ @<기호표 마디 |pp|를...@>=
if isDigit(a.labField[0]) {
	pp = &a.forwardLocal[a.labField[0]-'0']
} else {
	if a.labField[0] == ':' {
		tt, _ = trieSearch(a.trieRoot, a.labField, 1)
	} else {
		tt, _ = trieSearch(a.curPrefix, a.labField, 0)
	}
	pp = tt.sym
	if pp == nil {
		pp = a.newSymNode(true)
		tt.sym = pp
	}
}

@ 앞선 참조를 고치는 적재기 명령을 내보내기 전에, 목적 파일의 위치를 현재 위치(이제 레이블의
값)로 맞춘다. 고침 명령들은 늘 현재 위치~$\lambda$를 기준으로 하기 때문이다.

@<이 레이블에 대한 앞선 참조 하나를 고친다@>=
qq = pp.link
pp.link = qq.link
a.mmoLoc()
if qq.serial == fixO {
	@<옥타바이트의 앞선 참조를 고친다@>
} else {
	@<상대 주소의 앞선 참조를 고친다@>
}

@ @<옥타바이트의 앞선...@>=
if (qq.equiv>>32)&0xffffff != 0 {
	a.mmoLop(lopFixo, 0, 2)
	a.mmoTetra(Tetra(qq.equiv >> 32))
} else {
	a.mmoLop(lopFixo, byte(qq.equiv>>56), 1)
}
a.mmoTetra(Tetra(qq.equiv))

@ 보충: 상대 거리 $o$를 테트라바이트 단위로 잰다. 앞으로 \Hex{10000}보다 작게 떨어져
있으면 |lopFixr| 하나로 충분하다. \.{JMP}라면 \Hex{1000000}보다 작을 때까지 |lopFixrx| 24로
고칠 수 있다. 오프셋 $o$가 음수, 곧 앞선 참조가 결국 뒤를 가리키게 된 경우에는 |lopFixrx|의
맨 앞 바이트를 1로 해서 알린다. 그 밖의 경우는 너무 멀다.

@<상대 주소의 앞선...@>=
o := a.curLoc - qq.equiv
if o&3 != 0 {
	a.derr("*relative address in location #%016x not divisible by 4", qq.equiv)
@.relative address...@>
}
o = Octa(int64(o) >> 2)
k = 0
switch h, l := Tetra(o>>32), Tetra(o); {
case h == 0 && l < 0x10000:
	a.mmoLopp(lopFixr, uint16(l))
case h == 0 && qq.serial == fixXYZ && l < 0x1000000:
	a.mmoLop(lopFixrx, 0, 24)
	a.mmoTetra(l)
case h == 0xffffffff && qq.serial == fixXYZ && l >= 0xff000000:
	a.mmoLop(lopFixrx, 0, 24)
	a.mmoTetra(l & 0x1ffffff)
case h == 0xffffffff && qq.serial == fixYZ && l >= 0xffff0000:
	a.mmoLop(lopFixrx, 0, 16)
	a.mmoTetra(l & 0x100ffff)
default:
	k = 1
}
if k != 0 {
	a.derr("relative address in location #%016x is too far away", qq.equiv)
}

@ @<레이블의 등가를 보여 주는...@>=
if newLink == defined {
	fmt.Fprintf(a.listingFile, "(%016x)", a.curLoc)
	a.flushListingLine(" ")
} else {
	fmt.Fprintf(a.listingFile, "($%03d)", Tetra(a.curLoc)&0xff)
	a.flushListingLine("             ")
}

@ 이제 연산을 수행한다. 피연산자가 많을 수 있는 연산(데이터 유사 연산)은 따로 다루고, 그
밖에는 피연산자의 수에 따라 가른다.

보충: 원본의 흐름은 |switch| 문의 경우에서 다음 경우로 흘러내리고 이름표 |make_two_three|,
|assemble_X|, |assemble_inst|로 뛰는 복잡한 것이었다. 여기서는 모든 경로가 필드 |xyz|를
채운 뒤 맨 끝의 한 곳에서 명령을 어셈블하도록 다시 짰다. 피연산자가 둘인데 연산 코드가
피연산자 셋을 허용하고 메모리 연산이 아니면, 가운데에 \.0을 끼워 넣어 세 피연산자 연산으로
만든다. 그런 연산은 반드시 셋을 허용하므로 원본의 |case 3| 점검은 늘 통과한다.

@<연산을 수행한다@>=
a.futureBits = 0
if a.opBits&manyArgBit != 0 {
	@<피연산자가 많은 연산을 수행한다@>
	return
}
switch a.valPtr {
case 1:
	if a.opBits&oneArgBit == 0 {
		a.derr("opcode `%s' needs more than one operand", a.opField)
@.opcode...operand(s)@>
	}
	@<피연산자가 하나인 연산을 수행한다@>
case 2:
	@<피연산자가 둘일 수 있는지 확인한다@>
	if a.opBits&(threeArgBit|memBit) == threeArgBit {
		@<가운데 피연산자로 \.0을 끼워 넣는다@>
		@<피연산자가 셋인 연산을 수행한다@>
	} else {
		@<피연산자가 둘인 연산을 수행한다@>
		@<X 필드를 채운다@>
	}
case 3:
	if a.opBits&threeArgBit == 0 {
		a.derr("opcode `%s' must not have three operands", a.opField)
	}
	@<피연산자가 셋인 연산을 수행한다@>
default:
	a.derr("too many operands for opcode `%s'", a.opField)
@.too many operands...@>
}
a.assemble(4, a.opcode<<24+a.xyz, byte(a.futureBits))

@ @<피연산자가 둘일 수 있는지...@>=
if a.opBits&twoArgBit == 0 {
	if a.opBits&oneArgBit != 0 {
		a.derr("opcode `%s' must not have two operands", a.opField)
	} else {
		a.derr("opcode `%s' must have more than two operands", a.opField)
	}
}

@ @<가운데 피연산자로...@>=
a.valStack[2], a.valPtr = a.valStack[1], 3
a.valStack[1] = valNode{equiv: 0, link: nil, status: pure}

@ 피연산자가 많을 수 있는 연산자는 |BYTE|, |WYDE|, |TETRA|, |OCTA|다. 변수 |k|는 식 하나가
차지하는 바이트 수다. 옥타바이트는 테트라바이트 둘로 어셈블하고, 앞선 참조이면 두 테트라
모두를 고칠 것으로 표시한다.

@<피연산자가 많은 연산을...@>=
for j = 0; j < a.valPtr; j++ {
	v := &a.valStack[j]
	@<|v|가 순수하지 않은 경우를 처리한다@>
	k = 1 << (a.opcode - BYTE)
	if (v.equiv>>32 != 0 && a.opcode < OCTA) ||
		(Tetra(v.equiv) > 0xffff && a.opcode < TETRA) ||
		(Tetra(v.equiv) > 0xff && a.opcode < WYDE) {
		if k == 1 {
			a.err("*constant doesn't fit in one byte")
@.constant doesn't fit...@>
		} else {
			a.derr("*constant doesn't fit in %d bytes", k)
		}
	}
	switch {
	case k < 8:
		a.assemble(k, Tetra(v.equiv), 0)
	case v.status == undefined:
		a.assemble(4, 0, 0xf0)
		a.assemble(4, 0, 0xf0)
	default:
		a.assemble(4, Tetra(v.equiv>>32), 0)
		a.assemble(4, Tetra(v.equiv), 0)
	}
}

@ @<|v|가 순수하지 않은...@>=
if v.status == regVal {
	a.err("*register number used as a constant")
@.register number...@>
} else if v.status == undefined {
	if a.opcode != OCTA {
		a.err("undefined constant")
@.undefined constant@>
	}
	pp = v.link.sym
	qq = a.newSymNode(false)
	qq.link = pp.link
	pp.link = qq
	qq.serial = fixO
	qq.equiv = a.curLoc
}

@ @<피연산자가 셋인 연산을...@>=
@<Z 필드를 채운다@>
@<Y 필드를 채운다@>
@<X 필드를 채운다@>

@ 명령의 각 필드는 필드 |z|, |y|, |x|, |yz|, |xyz|에 놓인다.

@<어셈블러의 상태@>=
z, y, x, yz, xyz Tetra // pieces for assembly
futureBits       int   // places where there are future references

@ Z 필드가 레지스터가 아니고 연산 코드가 즉치 꼴을 가지면, 연산 코드에 1을 더해 즉치 꼴로
바꾼다. \MMIX의 연산 코드 표에서 즉치 꼴은 늘 바로 다음 번호이기 때문이다.

@<Z 필드를...@>=
if a.valStack[2].status == undefined {
	a.err("Z field is undefined")
@.Z field is undefined@>
}
if a.valStack[2].status == regVal {
	if a.opBits&(immedBit|zrBit|zarBit) == 0 {
		a.derr("*Z field of `%s' should not be a register number", a.opField)
@.Z field...register number@>
	}
} else if a.opBits&immedBit != 0 {
	a.opcode++ // immediate
} else if a.opBits&zrBit != 0 {
	a.derr("*Z field of `%s' should be a register number", a.opField)
}
if a.valStack[2].equiv > 0xff {
	a.err("*Z field doesn't fit in one byte")
@.Z field doesn't fit...@>
}
a.z = Tetra(a.valStack[2].equiv) & 0xff

@ @<Y 필드를...@>=
if a.valStack[1].status == undefined {
	a.err("Y field is undefined")
@.Y field is undefined@>
}
if a.valStack[1].status == regVal {
	if a.opBits&(yrBit|yarBit) == 0 {
		a.derr("*Y field of `%s' should not be a register number", a.opField)
@.Y field...register number@>
	}
} else if a.opBits&yrBit != 0 {
	a.derr("*Y field of `%s' should be a register number", a.opField)
}
if a.valStack[1].equiv > 0xff {
	a.err("*Y field doesn't fit in one byte")
@.Y field doesn't fit...@>
}
a.y = Tetra(a.valStack[1].equiv) & 0xff
a.yz = a.y<<8 + a.z

@ @<X 필드를...@>=
if a.valStack[0].status == undefined {
	a.err("X field is undefined")
@.X field is undefined@>
}
if a.valStack[0].status == regVal {
	if a.opBits&(xrBit|xarBit) == 0 {
		a.derr("*X field of `%s' should not be a register number", a.opField)
@.X field...register number@>
	}
} else if a.opBits&xrBit != 0 {
	a.derr("*X field of `%s' should be a register number", a.opField)
}
if a.valStack[0].equiv > 0xff {
	a.err("*X field doesn't fit in one byte")
@.X field doesn't fit...@>
}
a.x = Tetra(a.valStack[0].equiv) & 0xff
a.xyz = a.x<<16 + a.yz

@ 피연산자가 둘인 연산에서 둘째 피연산자는 YZ 필드가 된다. 정의되지 않았으면 상대 주소의
앞선 참조이거나 오류다. 순수한 메모리 주소이면 기준 주소를 찾는다. 레지스터 번호인데 연산
코드가 \.{SET}이면 \.{OR}로, 메모리 연산이면 \.{,0}을 조용히 덧붙인 셋 피연산자 꼴로
바꾼다. 순수한 값인데 \.{SET}이면 \.{SETL}로 바꾼다.

보충: 원본은 레지스터 번호를 Z 자리로 옮기려고 등가의 낮은 테트라바이트만 8비트 옮겼다.
피연산자 하나를 마칠 때 레지스터 번호는 255 이하로 줄여 두었으므로, 여기서 옥타바이트 전체를
옮겨도 같다.

@<피연산자가 둘인 연산을...@>=
v := &a.valStack[1]
switch {
case v.status == undefined && a.opBits&relAddrBit != 0:
	@<YZ를 앞선 참조로 어셈블한다@>
case v.status == undefined:
	a.err("YZ field is undefined")
@.YZ field is undefined@>
case v.status == pure && a.opBits&memBit != 0:
	@<YZ를 메모리 주소로 어셈블한다@>
default:
	if v.status == regVal {
		@<레지스터인 YZ를 점검한다@>
	} else {
		@<순수한 YZ에 맞게 연산 코드를 바꾼다@>
	}
	if v.status == pure && a.opBits&relAddrBit != 0 {
		@<YZ를 상대 주소로 어셈블한다@>
	} else {
		if v.equiv > 0xffff {
			a.err("*YZ field doesn't fit in two bytes")
@.YZ field doesn't fit...@>
		}
		a.yz = Tetra(v.equiv) & 0xffff
	}
}

@ @<레지스터인 YZ를...@>=
if a.opBits&(immedBit|yzrBit|yzarBit) == 0 {
	a.derr("*YZ field of `%s' should not be a register number", a.opField)
@.YZ field...register number@>
}
if a.opcode == SET {
	v.equiv <<= 8
	a.opcode = 0xc1 // change to \.{OR}
} else if a.opBits&memBit != 0 {
	v.equiv <<= 8
	a.opcode++ // silently append \.{,0}
}

@ @<순수한 YZ에 맞게...@>=
if a.opcode == SET {
	a.opcode = 0xe3 // change to \.{SETL}
} else if a.opBits&immedBit != 0 {
	a.opcode++ // immediate
} else if a.opBits&yzrBit != 0 {
	a.derr("*YZ field of `%s' should be a register number", a.opField)
}

@ @<YZ를 앞선 참조로...@>=
pp = v.link.sym
qq = a.newSymNode(false)
qq.link = pp.link
pp.link = qq
qq.serial = fixYZ
qq.equiv = a.curLoc
a.yz = 0
a.futureBits = 0xc0

@ 상대 주소는 테트라바이트 단위로 잰다. 뒤로 가는 주소이면 연산 코드에 1을 더해 ``뒤로''
꼴(\.{BZB} 따위)로 바꾸고, 거리에 \Hex{10000}을 더한다.

@<YZ를 상대 주소로...@>=
if v.equiv&3 != 0 {
	a.err("*relative address is not divisible by 4")
@.relative address...@>
}
source := Octa(int64(a.curLoc) >> 2)
dest := Octa(int64(v.equiv) >> 2)
acc = dest - source
if acc&mmixarith.SignBit == 0 {
	if acc > 0xffff {
		a.err("relative address is more than #ffff tetrabytes forward")
	}
} else {
	acc += 0x10000
	a.opcode++
	if acc > 0xffff {
		a.err("relative address is more than #10000 tetrabytes backward")
	}
}
a.yz = Tetra(acc)

@ 기준 주소 가운데 주소 A와의 차이가 가장 작은 것을 찾는다. 차이는 부호 없이 비교하므로,
A보다 큰 기준 주소는 차이가 엄청나게 커서 저절로 밀려난다.

@<YZ를 메모리 주소로...@>=
o := v.equiv
k = 0
for j = a.greg; j < 255; j++ {
	if a.gregVal[j] != 0 {
		acc = v.equiv - a.gregVal[j]
		if acc <= o {
			o, k = acc, j
		}
	}
}
switch {
case o <= 0xff && k != 0:
	a.yz = Tetra(k<<8) + Tetra(o)
	a.opcode++
case !a.expanding:
	a.err("no base address is close enough to the address A")
@.no base address...@>
default:
	@<보충 데이터를 \$255에 넣는 명령들을 어셈블한다@>
}

@ \.{-x} 옵션이 켜져 있으면, 모자라는 부분 |o|를 \.{SETH}, \.{SETMH}, \.{SETML}, \.{SETL}과
\.{ORH}, \.{ORMH}, \.{ORML}, \.{ORL}로 \$255에 넣는다. 0인 와이드는 건너뛰되 \.{SETL}은
하나라도 내보내야 한다. 첫 명령을 내보낸 뒤에는 |j|에 |ORH|를 논리합해서 나머지를 \.{OR}
꼴로 바꾼다. 그런 다음 원래 명령은 기준 주소가 있으면 $\rm \$k+\$255$를, 없으면
$\rm \$255+0$을 주소로 쓴다.

@<보충 데이터를...@>=
for j = SETH; j <= ORL; j++ {
	switch j & 3 {
	case 0:
		a.yz = Tetra(o>>48) & 0xffff // \.{SETH}
	case 1:
		a.yz = Tetra(o>>32) & 0xffff // \.{SETMH} or \.{ORMH}
	case 2:
		a.yz = Tetra(o>>16) & 0xffff // \.{SETML} or \.{ORML}
	case 3:
		a.yz = Tetra(o) & 0xffff // \.{SETL} or \.{ORL}
	}
	if a.yz != 0 || j == SETL {
		a.assemble(4, Tetra(j<<24)+255<<16+a.yz, 0)
		j |= ORH
	}
}
if k != 0 {
	a.yz = Tetra(k<<8) + 255 // Y = \$$k$, Z = \$255
} else {
	a.yz, a.opcode = 255<<8, a.opcode+1 // Y = \$255, Z = 0
}

@ @<상수@>=
const (
	SETH = 0xe0
	SETL = 0xe3
	ORH  = 0xe8
	ORL  = 0xeb
)

@ 피연산자가 하나인 연산에서 그 피연산자는 XYZ 필드가 된다. 앞선 참조나 순수한 상대 주소는
따로 어셈블하고, 나머지 경우에는 유사 연산을 처리하거나 XYZ를 채운다.

@<피연산자가 하나인 연산을...@>=
v := &a.valStack[0]
switch {
case v.status == undefined && a.opBits&relAddrBit != 0:
	@<XYZ를 앞선 참조로 어셈블한다@>
case v.status == pure && a.opBits&relAddrBit != 0:
	if a.opBits&xyzrBit != 0 {
		a.derr("*operand of `%s' should be a register number", a.opField)
	}
	@<XYZ를 상대 주소로 어셈블한다@>
default:
	@<하나뿐인 피연산자의 상태를 점검한다@>
	if a.opcode > 0xff {
		@<유사 연산을 수행하고 |return|@>
	}
	if v.equiv > 0xffffff {
		a.err("*XYZ field doesn't fit in three bytes")
@.XYZ field doesn't fit...@>
	}
	a.xyz = Tetra(v.equiv) & 0xffffff
}

@ \.{PREFIX}의 피연산자는 아직 정의되지 않은 기호여도 된다. 접두어로 쓰는 것은 기호의 값이
아니라 트라이 마디이기 때문이다.

@<하나뿐인 피연산자의 상태를...@>=
switch v.status {
case undefined:
	if a.opcode != PREFIX {
		a.err("the operand is undefined")
@.the operand is undefined@>
	}
case regVal:
	if a.opBits&(xyzrBit|xyzarBit) == 0 {
		a.derr("*operand of `%s' should not be a register number", a.opField)
@.operand...register number@>
	}
default:
	if a.opBits&xyzrBit != 0 {
		a.derr("*operand of `%s' should be a register number", a.opField)
	}
}

@ @<XYZ를 앞선 참조로...@>=
pp = v.link.sym
qq = a.newSymNode(false)
qq.link = pp.link
pp.link = qq
qq.serial = fixXYZ
qq.equiv = a.curLoc
a.xyz = 0
a.futureBits = 0xe0

@ @<XYZ를 상대 주소로...@>=
if v.equiv&3 != 0 {
	a.err("*relative address is not divisible by 4")
@.relative address...@>
}
source := Octa(int64(a.curLoc) >> 2)
dest := Octa(int64(v.equiv) >> 2)
acc = dest - source
if acc&mmixarith.SignBit == 0 {
	if acc > 0xffffff {
		a.err("relative address is more than #ffffff tetrabytes forward")
	}
} else {
	acc += 0x1000000
	a.opcode++
	if acc > 0xffffff {
		a.err("relative address is more than #1000000 tetrabytes backward")
	}
}
a.xyz = Tetra(acc)

@ 유사 연산은 모두 여기서 끝난다. 원본에서 |LOC|은 현재 위치를 바꾼 뒤 |IS|의 경우로 흘러내려
|goto bypass|했다. 명령 |IS|가 할 일은 레이블을 정의하는 것뿐인데, 그것은 이미 했다.

보충: 원본은 \.{LOCAL}의 값을 부호 없는 테트라바이트로 비교하고 부호 있는 |int| 변수에
넣었다. 순수한 값을 잘못 주면(경고가 나온다) $2^{31}$ 이상의 값이 음수가 될 수 있는데, 그
동작까지 똑같이 하려고 |int32|를 거친다. 목록에 찍을 때도 원본은 부호 없는 값을 \.{\%d}로
찍었으므로 음수로 나온다.

@<유사 연산을 수행하고...@>=
switch a.opcode {
case LOC:
	a.curLoc = v.equiv
case PREFIX:
	if v.link == nil {
		a.err("not a valid prefix")
@.not a valid prefix@>
	}
	a.curPrefix = v.link
case GREG:
	if a.listingFile != nil {
		@<|GREG|의 목록을 만든다@>
	}
case LOCAL:
	if Tetra(v.equiv) > Tetra(a.lreg) {
		a.lreg = int(int32(Tetra(v.equiv)))
	}
	if a.listingFile != nil {
		fmt.Fprintf(a.listingFile, "($%03d)", int32(Tetra(v.equiv)))
		a.flushListingLine("             ")
	}
case BSPEC:
	if v.equiv > 0xffff {
		a.err("*operand of `BSPEC' doesn't fit in two bytes")
@.operand of `BSPEC'...@>
	}
	a.mmoLoc()
	a.mmoSync()
	a.mmoLopp(lopSpec, uint16(v.equiv))
	a.specMode, a.specModeLoc = true, 0
case ESPEC:
	a.specMode = false
	if a.heldBits != 0 {
		a.mmoClear()
	}
}
return

@ @<어셈블러의 상태@>=
gregVal [256]Octa // initial values of global registers

@ @<|GREG|의 목록을...@>=
if v.equiv != 0 {
	fmt.Fprintf(a.listingFile, "($%03d=#%08x", a.curGreg, Tetra(v.equiv>>32))
	a.flushListingLine("    ")
	fmt.Fprintf(a.listingFile, "         %08x)", Tetra(v.equiv))
	a.flushListingLine(" ")
} else {
	fmt.Fprintf(a.listingFile, "($%03d)", a.curGreg)
	a.flushListingLine("             ")
}

@* 프로그램 실행하기. \UNIX/ 비슷한 시스템에서 명령
$$\.{mmixal [options] sourcefilename}$$
은 파일 \.{sourcefilename}에 있는 \MMIXAL\ 프로그램을 어셈블하고, 오류 메시지가 있으면
표준 오류 파일에 쓴다. (표준 출력에는 아무것도 쓰지 않는다.) 옵션들은 어떤 순서로 나와도
되며, 다음과 같다.

\bull\.{-o objectfilename}\quad 출력을 \.{objectfilename}이라는 이진 파일로 보낸다.
\.{-o}를 지정하지 않으면, 목적 파일 이름은 입력 파일 이름의 마지막 글자를 `\.s'에서~`\.o'로
바꾸어서, 또는 \.{sourcefilename}이 \.s로 끝나지 않으면 `\.{.mmo}'를 덧붙여서 얻는다.

\bull\.{-l listingname}\quad 어셈블된 입력과 출력의 목록을 \.{listingname}이라는 텍스트
파일로 내보낸다.

\bull\.{-x}\quad 명령 하나로 어셈블할 수 없는 메모리 지향 명령을, 전역 레지스터~\$255를
잠깐 쓰는 보조 명령들을 어셈블해서 펼친다.

\bull\.{-b bufsize}\quad 입력 한 줄에 \.{bufsize}자까지 허용한다.

@ 마지막으로, 이 프로그램의 전체 구조가 여기 있다.

보충: 원본의 |main|이 하던 일을 여기서는 함수 |mmixal|이 한다. 명령줄 인자와 표준 오류와
파일을 만든 시각을 매개변수로 받고, 종료 코드를 돌려준다. 그래서 시험 프로그램은 시각을
고정해 놓고 이 함수를 불러 결과를 원본의 것과 비교할 수 있다. 치명적 오류는 |fatalSignal|
공황으로 여기까지 빠져나오며, 원본의 |exit(-2)|처럼 종료 코드 $-2$가 된다. 그때도 원본의
|exit|이 표준 입출력 버퍼를 비우듯이 출력 파일들을 비우고 닫는다.

@<|mmixal| 함수@>=
func mmixal(args []string, stderr io.Writer, now int64) (code int) {
	a := &assembler{stderr: stderr, greg: 255, lreg: 32}
	var j, k int // all-purpose integers
	var files []*os.File
	@<지역 변수@>
	defer func() {
		if r := recover(); r != nil {
			if r != (fatalSignal{}) {
				panic(r)
			}
			code = -2
		}
		@<출력 파일들을 비우고 닫는다@>
	}()
	@<명령줄을 처리한다@>
	@<모든 것을 초기화한다@>
	for {
		@<다음 입력 줄을 읽는다...@>
		for {
			@<다음 \MMIXAL\ 명령이나...@>
			if a.buffer[a.bufPtr] == 0 {
				break
			}
		}
		if a.listingFile != nil {
			if a.listingBits != 0 {
				a.listingClear()
			} else if !a.lineListed {
				a.flushListingLine("                   ")
			}
		}
	}
	@<어셈블을 마무리한다@>
	return a.errCount
}

@ @<|main| 함수@>=
func main() {
	os.Exit(mmixal(os.Args, os.Stderr, time.Now().Unix()))
}

@ @<출력 파일들을 비우고...@>=
if a.objFile != nil {
	a.objFile.Flush()
}
if a.listingFile != nil {
	a.listingFile.Flush()
}
for _, f := range files {
	f.Close()
}

@ \.{-b} 뒤의 공백은 있어도 되고 없어도 된다. {\mc MMIX-SIM}이 이런 맥락에서 공백을 쓰지
않기 때문이다.

보충: 원본은 수를 읽을 때 |sscanf|의 \.{\%d}를 썼다. 앞의 공백과 부호를 허용하고, 숫자가
하나라도 있으면 성공이며, 숫자 뒤의 다른 문자는 무시한다. 함수 |scanInt|가 그것을 흉내
낸다. 원본이 인자 문자열의 셋째 문자가 널 문자인지 보던 것은 여기서 인자의 길이가 2
이하인지 보는 것이 된다.

@<명령줄을 처리한다@>=
options:
for j = 1; j < len(args)-1 && len(args[j]) > 0 && args[j][0] == '-'; j++ {
	if len(args[j]) > 2 {
		n, ok := scanInt(args[j][2:])
		if args[j][1] != 'b' || !ok {
			break
		}
		a.bufSize = n
		continue
	}
	@<한 글자 옵션을 처리한다@>
}
if j != len(args)-1 {
	fmt.Fprintf(stderr, "Usage: %s %s sourcefilename\n",
@.Usage: ...@>
		args[0], "[-x] [-l listingname] [-b buffersize] [-o objectfilename]")
	return -1
}
a.srcFileName = args[j]

@ @<한 글자 옵션을...@>=
var opt byte
if len(args[j]) == 2 {
	opt = args[j][1]
}
switch opt {
case 'x':
	a.expanding = true
case 'o':
	j++
	a.objFileName = args[j]
case 'l':
	j++
	a.listingName = args[j]
case 'b':
	n, ok := scanInt(args[j+1])
	if !ok {
		break options
	}
	a.bufSize = n
	j++
default:
	break options
}

@ @<함수들@>=
func scanInt(s string) (int, bool) {
	i := 0
	for i < len(s) && isSpace(s[i]) {
		i++
	}
	neg := false
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		neg = s[i] == '-'
		i++
	}
	if i == len(s) || !isDigit(s[i]) {
		return 0, false
	}
	n := 0
	for ; i < len(s) && isDigit(s[i]); i++ {
		n = 10*n + int(s[i]-'0')
	}
	if neg {
		n = -n
	}
	return n, true
}

@ @<파일들을 연다@>=
f, err := os.Open(a.srcFileName)
if err != nil {
	a.fatal("Can't open the source file %s", a.srcFileName)
@.Can't open...@>
}
files = append(files, f)
a.srcFile = bufio.NewReader(f)
if a.objFileName == "" {
	if n := len(a.srcFileName); n > 0 && a.srcFileName[n-1] == 's' {
		a.objFileName = a.srcFileName[:n-1] + "o"
	} else {
		a.objFileName = a.srcFileName + ".mmo"
	}
}
if f, err = os.Create(a.objFileName); err != nil {
	a.fatal("Can't open the object file %s", a.objFileName)
}
files = append(files, f)
a.objFile = bufio.NewWriter(f)
if a.listingName != "" {
	if f, err = os.Create(a.listingName); err != nil {
		a.fatal("Can't open the listing file %s", a.listingName)
	}
	files = append(files, f)
	a.listingFile = bufio.NewWriter(f)
}

@ @<어셈블러의 상태@>=
stderr      io.Writer     // where error messages are written
srcFileName string        // name of the \MMIXAL\ input file
objFileName string        // name of the binary output file
listingName string        // name of the optional listing file
srcFile     *bufio.Reader // the input file
objFile     *bufio.Writer // the binary output file
listingFile *bufio.Writer // the listing file; |nil| if none
expanding   bool          // are we expanding instructions when base address fail?
bufSize     int           // maximum number of characters per line of input

@ @<모든 것을 초기화한다@>=
@<파일들을 연다@>
a.filename = []string{a.srcFileName}
@<서문을 출력한다@>

@ @<서문을 출력한다@>=
a.mmoLop(lopPre, 1, 1)
a.mmoTetra(Tetra(now))
a.mmoCurFile = -1

@ 보충: 원본은 |exit(err_count)|로 오류의 수를 종료 코드로 삼았다. 출력 파일을 비우다가
실패하면 원본의 |mmo_write|처럼 ``Can't write'' 치명적 오류를 낸다.

@<어셈블을 마무리한다@>=
if a.lreg >= a.greg {
	a.fatal("Danger: Must reduce the number of GREGs by %d", a.lreg-a.greg+1)
@.Danger@>
}
@<후기를 출력한다@>
@<트라이를 점검하고 출력한다@>
@<정의되지 않은 지역 기호를 보고한다@>
if a.errCount > 0 {
	if a.errCount > 1 {
		fmt.Fprintf(stderr, "(%d errors were found.)\n", a.errCount)
	} else {
		fmt.Fprintf(stderr, "(One error was found.)\n")
	}
}
if a.objFile.Flush() != nil {
	a.fatal("Can't write on %s", a.objFileName)
}

@ @<어셈블러의 상태@>=
greg    int // global register allocator
curGreg int // global register just allocated
lreg    int // local register allocator

@ 후기에는 \$G부터 \$255까지의 처음 값이 들어간다. \$255에는 \.{Main}의 주소가 들어가므로,
프로그램은 그것을 보고 어디서 시작할지 안다.

@<후기를 출력한다@>=
a.mmoLop(lopPost, 0, byte(a.greg))
tt, _ = trieSearch(a.trieRoot, []byte("Main"), 0)
a.gregVal[255] = tt.sym.equiv
for j = a.greg; j < 256; j++ {
	a.mmoTetra(Tetra(a.gregVal[j] >> 32))
	a.mmoTetra(Tetra(a.gregVal[j]))
}

@ @<정의되지 않은 지역 기호를...@>=
for j = 0; j < 10; j++ {
	if a.forwardLocal[j].link != nil {
		a.errCount++
		fmt.Fprintf(stderr, "undefined local symbol %dF\n", j)
@.undefined local symbol@>
	}
}

@* 시험. 원본에는 시험 프로그램이 따로 없었다. 크누스는 이 문서의 앞머리에 실은 \.{test.mms}와
그 어셈블 결과를 첫 시험으로 삼았다. 옮긴이는 그 예를 그대로 시험으로 만들고, 오류 메시지를
두루 건드리는 작은 프로그램과, 원본과 일부러 다르게 한 경우를 하나씩 더했다.

이 문서 밖에서는 더 큰 비교를 했다. 크누스의 최신판 \CEE/ 코드를 컴파일한 어셈블러와 이
한글판에, \.{examples} 디렉터리의 \.{.mms} 파일 54개를 옵션 없이, \.{-x}로, \.{-b 50}으로
어셈블하게 하고, 그 줄들을 무작위로 뒤틀거나 이상한 식과 레이블을 섞어 만든 입력 6000개를
더 넣어 보았다. 목적 파일(만든 시각을 뺀 모든 바이트), 목록 파일, 표준 오류, 종료 코드가 모두
한 바이트도 다르지 않았다. 다른 것은 마지막 줄이 줄바꿈 없이 레이블만으로 끝나는 경우뿐이었는데,
그것은 레이블 필드를 읽는 곳에서 설명한 대로 일부러 다르게 한 것이다.

시험 함수들은 임시 디렉터리로 옮겨 가서 소스 파일을 쓰고 |mmixal|을 부른다. 파일 이름이
목적 파일과 오류 메시지에 들어가므로, 디렉터리를 옮겨 상대 경로로 부르는 것이 중요하다.
파일을 만든 시각은 크누스의 표에 적힌 \Hex{36f4a363}(1999년 3월 20일)으로 고정한다.

@(mmixal_test.go@>=
package main

import (
	"bytes"
	"fmt"
	"os"
	"strings"
	"testing"
)

func assembleFile(t *testing.T, name, src string, opts ...string) (mmo []byte, lst, stderr string, code int) {
	t.Helper()
	t.Chdir(t.TempDir())
	if err := os.WriteFile(name, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	args := append(append([]string{"mmixal"}, opts...), "-l", "out.lst", name)
	var e bytes.Buffer
	code = mmixal(args, &e, 0x36f4a363)
	mmo, _ = os.ReadFile(strings.TrimSuffix(name, "s") + "o")
	l, _ := os.ReadFile("out.lst")
	return mmo, string(l), e.String(), code
}

@ 크누스의 예다. 목적 파일은 앞에서 본 표와, 목록 파일은 원본 \CEE/ 어셈블러가 만든 것과
똑같아야 한다.

@(mmixal_test.go@>=
func TestKnuthExample(t *testing.T) {
	mmo, lst, stderr, code := assembleFile(t, "test.mms", testMMS)
	if code != 0 || stderr != "" {
		t.Fatalf("종료 코드 %d, 표준 오류 %q", code, stderr)
	}
	var got []string
	for i := 0; i+4 <= len(mmo); i += 4 {
		got = append(got, fmt.Sprintf("%02x%02x%02x%02x", mmo[i], mmo[i+1], mmo[i+2], mmo[i+3]))
	}
	if g, w := strings.Join(got, " "), strings.Join(strings.Fields(testMMO), " "); g != w {
		t.Errorf("test.mmo가 다르다:\n얻음 %s\n원함 %s", g, w)
	}
	if lst != testLST {
		t.Errorf("목록이 다르다:\n%s", lst)
	}
}

@ @(mmixal_test.go@>=
const testMMS = `% A peculiar example of MMIXAL
     LOC   Data_Segment      % location #2000000000000000
     OCTA  1F                % a future reference
a    GREG  @@                 % $254 is base address for ABCD
ABCD BYTE  "ab"              % two bytes of data
     LOC   #123456789        % switch to the instruction segment
Main JMP   1F                % another future reference
     LOC   @@+#4000           % skip past 16384 bytes
2H   LDB   $3,ABCD+1         % use the base address
     BZ    $3,1F; TRAP       % and refer to the future again
# 3 "foo.mms"                % this comment is a line directive
     LOC   2B-4*10           % move 10 tetras before previous location
1H   JMP   2B                % resolve previous references to 1F
     BSPEC 5                 % begin special data of type 5
     TETRA &a<<8             % four bytes of special data
     WYDE  a-$0              % two more bytes of special data
     ESPEC                   % end a special data packet
     LOC   ABCD+2            % resume the data segment
     BYTE  "cd",#98          % assemble three more bytes of data
`

@ @(mmixal_test.go@>=
const testMMO = `98090101 36f4a363 98012001 00000000 00000000 00000000 61620000
98010002 00000001 2345678c 98060002 74657374 2e6d6d73 98070007 f0000000
98024000 98070009 8103fe01 42030000 9807000a 00000000 98010002 00000001
2345a768 98050010 0100fff5 98040ff7 98032001 00000000 98060102 666f6f2e
6d6d7300 98070004 f000000a 98080005 00000200 00fe0000 98012001 0000000a
00006364 98000001 98000000 980a00fe 20000000 00000008 00000001 2345678c
980b0000 203a5040 50404020 41204220 43094408 83404020 4d206120 69056e01
2345678c 81400f61 fe820000 980c000a`

@ @(mmixal_test.go@>=
const testLST = `                   % A peculiar example of MMIXAL
                        LOC   Data_Segment      % location #2000000000000000
2000000000000000:       OCTA  1F                % a future reference
 ...000: xxxxxxxx
 ...004: xxxxxxxx
($254=#20000000    a    GREG  @@                 % $254 is base address for ABCD
         00000008)
 ...008: 6162      ABCD BYTE  "ab"              % two bytes of data
                        LOC   #123456789        % switch to the instruction segment
000000012345678c:  Main JMP   1F                % another future reference
 ...78c: f0xxxxxx
                        LOC   @@+#4000           % skip past 16384 bytes
000000012345a790:  2H   LDB   $3,ABCD+1         % use the base address
 ...790: 8103fe01
 ...794: 4203xxxx       BZ    $3,1F; TRAP       % and refer to the future again
 ...798: 00000000
                   # 3 "foo.mms"                % this comment is a line directive
                        LOC   2B-4*10           ` +
	`% move 10 tetras before previous location
 ...768: f000000a  1H   JMP   2B                % resolve previous references to 1F
                        BSPEC 5                 % begin special data of type 5
         00000200       TETRA &a<<8             % four bytes of special data
         00fe           WYDE  a-$0              % two more bytes of special data
                        ESPEC                   % end a special data packet
                        LOC   ABCD+2            % resume the data segment
200000000000000a:       BYTE  "cd",#98          % assemble three more bytes of data
 ...00a:     6364
 ...00c: 98      

Symbol table:
 ABCD = #2000000000000008 (3)
 Main = #000000012345678c (1)
 a = $254 (2)
`

@ 오류 메시지를 두루 건드리는 프로그램이다. 경고는 목적 파일을 만드는 것을 막지 않고, 오류는
그 명령의 나머지를 건너뛴다. 기대하는 표준 오류는 원본 \CEE/ 어셈블러가 낸 것이다. 마지막 줄
\.{w}의 값 \Hex{c}는 ``레이블을 정의한다'' 절에서 말한 원본의 동작, 곧 \.{z IS 6}의 오류 뒤에
현재 위치가 6으로 남는 것을 보여 준다.

@(mmixal_test.go@>=
func TestErrorMessages(t *testing.T) {
	_, lst, stderr, code := assembleFile(t, "errs.mms", errsMMS)
	if code != 8 || stderr != errsErr {
		t.Errorf("종료 코드 %d, 표준 오류:\n%s", code, stderr)
	}
	if !strings.Contains(lst, " Foo:w = #000000000000000c (7)\n") {
		t.Errorf("기호표가 다르다:\n%s", lst)
	}
}

const errsMMS = `Main ADD  $1,$2,x
x    IS   $300
     SUB  $1,5,$2
     BYTE 256,"",'a
     LDA  $1,#1000000
y    GREG #1000000
     LDA  $1,y+17
     JMP  3F+4
     DIV  $1,$2,7//3
2X   SWYM
     FOO  1,2
     LOC  @@+(1
     OCTA 9F,-x
z    IS   5
z    IS   6
rA   IS   7
     PREFIX Foo:
     SET  $1,$2
w    SETL $0,1B
`

@ @(mmixal_test.go@>=
const errsErr = `"errs.mms", line 1: Z field is undefined!
"errs.mms", line 2 warning: register number too large, will be reduced mod 256
"errs.mms", line 3 warning: Y field of ` + "`SUB'" + ` should be a register number
"errs.mms", line 4: illegal character constant!
"errs.mms", line 5: no base address is close enough to the address A!
"errs.mms", line 7 warning: register number too large, will be reduced mod 256
"errs.mms", line 8: cannot add to an undefined quantity!
"errs.mms", line 9 warning: illegal fraction
"errs.mms", line 10: improper local label ` + "`2X'" + `!
"errs.mms", line 11: unknown operation code ` + "`FOO'" + `!
"errs.mms", line 12 warning: missing right parenthesis
"errs.mms", line 13: can negate pure values only!
"errs.mms", line 15: symbol ` + "`z'" + ` is already defined!
(8 errors were found.)
`

@ 마지막 줄이 줄바꿈 없이 레이블만으로 끝나는 경우다. 원본은 앞 줄의 찌꺼기를 읽어 \.{SWYM}을
한 번 더 어셈블했지만, 이 한글판은 경고를 내고 레이블을 무시한다. 목적 파일에는 \.{SWYM}이
하나만 있어야 한다. 끝으로 인자가 모자라면 사용법을 알려 주고 $-1$을 돌려준다.

@(mmixal_test.go@>=
func TestStaleLastLine(t *testing.T) {
	mmo, _, stderr, _ := assembleFile(t, "stale.mms", "Main SWYM 1,2,3\nabc")
	want := "\"stale.mms\", line 2 warning: no opcode; label `abc' will be ignored\n"
	if stderr != want {
		t.Errorf("표준 오류 %q", stderr)
	}
	if n := bytes.Count(mmo, []byte{0xfd, 1, 2, 3}); n != 1 {
		t.Errorf("SWYM이 %d번 어셈블되었다", n)
	}
}

func TestUsage(t *testing.T) {
	var e bytes.Buffer
	if code := mmixal([]string{"mmixal"}, &e, 0); code != -1 ||
		e.String() != "Usage: mmixal [-x] [-l listingname] [-b buffersize] "+
			"[-o objectfilename] sourcefilename\n" {
		t.Errorf("종료 코드 %d, %q", code, e.String())
	}
}

@* 찾아보기.
