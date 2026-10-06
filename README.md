<p align="center"><img src="mmix-logo.svg" alt="MMIX" width="500"></p><!-- markdownlint-disable-line MD033 -->

This repository translates Donald E. Knuth's **MMIXware** into Korean literate programs (GWEB) and Go.
MMIX is a 64-bit RISC computer that Knuth designed for the examples in *The Art of Computer Programming* (TAOCP).
MMIXware is the package, written entirely in CWEB, that contains the machine's specification,
an assembler, a simulator, and a pipelined meta-simulator.

도널드 크누스(Donald E. Knuth)의 **MMIXware**를 한글 문학적 프로그램(GWEB)과 Go로 옮긴 저장소다.
MMIX는 크누스가 『The Art of Computer Programming』(TAOCP)의 예제를 위해 설계한 64비트 RISC 컴퓨터다.
MMIXware는 그 기계의 명세, 어셈블러, 시뮬레이터, 그리고 파이프라인 메타 시뮬레이터를 모두 CWEB로 쓴 꾸러미다.

이 저장소의 `.w` 파일들은 원본을 한 절도 빠뜨리지 않고 한글로 옮기고, C 코드를 Go로 다시 썼다.
옮긴이가 덧붙인 설명은 문서 안에서 "보충:"으로 밝혀 두었다.
Go 프로그램은 크누스의 C 프로그램과 같은 입력에 대해 바이트 단위로 같은 출력을 내는지 대조하며 검증했다.

> 원본 MMIXware © 1999 Donald E. Knuth. 크누스의 원본 파일은 아무것도 바꾸지 않는다는
> 조건으로 자유롭게 복사할 수 있고, 고친 파일은 새 이름을 달고 MMIXware의 일부가 아님을
> 밝혀야 한다. 이 저장소의 번역은 그 조건에 따라 새 이름을 붙인 것이며 **MMIXware 꾸러미의
> 일부가 아니다.** 손대지 않은 원본은 크누스의 누리집
> <https://www-cs-faculty.stanford.edu/~knuth/mmix.html>에서 받을 수 있다.

## 디렉터리 구성

| 디렉터리 | 원본 | 종류 | 내용 |
| --- | --- | --- | --- |
| `mmixarith/` | `mmix-arith.w` | 라이브러리 | 64비트 정수 산술과 IEEE 부동소수점 산술 |
| `mmixio/` | `mmix-io.w` | 라이브러리 | 초보적인 입출력(`TRAP`의 `Fopen` 등) |
| `mmixal/` | `mmixal.w` | 실행 파일 | 어셈블러. `.mms` 원시 파일을 `.mmo` 목적 파일로 바꾼다 |
| `mmixsim/` | `mmix-sim.w` | 실행 파일 | 단순한(파이프라인 없는) 시뮬레이터. 원본의 `mmix` |
| `mmotype/` | `mmotype.w` | 실행 파일 | `.mmo` 목적 파일을 사람이 읽을 수 있게 풀어 보여 준다 |
| `mmmix/` | `mmmix.w` 외 셋 | 실행 파일 | 파이프라인 메타 시뮬레이터 |
| `abstime/` | `abstime.w` | 도구 | 시뮬레이터마다 고유한 번호(`rN`에 들어갈 시각)를 만든다 |
| `nnix/` | | 커널 | 크누스가 만들지 않은 운영체제 NNIX의 1단계(아래 [NNIX 커널](#nnix-커널) 참고) |
| `examples/` | | 예제 | 원본에 딸린 예제(아래 [예제 파일](#예제-파일) 참고) |

디렉터리 `mmmix/`의 원본은 `mmmix.w`, `mmix-pipe.w`, `mmix-config.w`,
`mmix-mem.w` 네 개이고, 번역도 같은 이름의 `.w` 네 개로 나뉘어 있다.

루트에는 다음 파일이 있다.

- `mmixdoc.w`: 원본 `mmix-doc.w`를 옮긴 것으로, MMIX 아키텍처의 자세한 명세다.
  코드가 없어 조판만 한다.
- `mmix-logo.mp`: `mmixdoc.w`의 목차 쪽에 놓는 MMIX 로고(MetaPost). 이 README 머리의
  `mmix-logo.svg`도 여기서 뽑는다.
- `boilerplate.w`: 모든 `.w`가 첫머리에서 `@i`로 읽어 들이는 공통 머리말이다.
  저작권 안내와 매크로가 들어 있다.
- `Makefile`: tangle, 테스트, 조판을 한꺼번에 돌린다.
- `go.mod`: 모듈 `github.com/sjnam/go-mmix`를 정의한다.
- `BUGS.md`: 옮기면서 찾은 원본의 버그와 문서 오타(영문). 재현 방법과 패치를 담았다.

각 디렉터리의 일차 산출물은 `.w`다. Go 원시 파일 `.go`는 `gtangle`이 `.w`에서
뽑아낸 것이고, 문서 `.pdf`는 `gweave`와 `luatex`로 조판한 것이다.
라이브러리 꾸러미(`mmixarith`, `mmixio`)는 `go get`이 되도록 `.go`도 함께 둔다.

## 빌드

실행 파일만 필요하면 Go만 있으면 된다.

```sh
go install ./mmixal ./mmixsim ./mmotype ./mmmix    # $GOPATH/bin에 설치
# 또는
go build -o bin/ ./mmixal ./mmixsim ./mmotype ./mmmix
```

문학적 프로그램 `.w`를 고치고 다시 만들 때는 GWEB 도구(`gtangle`, `gweave`)가 필요하다.
문서를 조판할 때는 `luatex`와 한글 조판용 `kotexgweb`, 그림을 그릴 `luamplib`도 필요하다.

```sh
make          # 모든 .w를 tangle한 뒤 go vet, go test
make tangle   # .w → .go (+ _test.go)
make test     # go vet + go test
make doc      # 각 .w를 조판해 .pdf를 만들고 조판 경고 수를 보여 준다
make intro    # mmixal과 mmixsim의 앞머리 안내서(*-intro.pdf)를 뗀다
make clean    # 조판 생성물 삭제
```

## 실행 파일

아래 네 프로그램은 모두 인자 없이 실행하면 사용법을 보여 준다.

### `mmixal`: 어셈블러

```text
mmixal [-x] [-l listingname] [-b buffersize] [-o objectfilename] sourcefilename
```

MMIXAL로 쓴 `foo.mms`를 어셈블해 목적 파일 `foo.mmo`를 만든다.

- `-l`: 기호 목록 파일을 함께 만든다.
- `-o`: 목적 파일 이름을 바꾼다.
- `-b`: 줄 버퍼 크기를 바꾼다(기본 72자).
- `-x`: 범위를 벗어난 주소를 전역 레지스터 `$255`로 메워 어셈블하게 한다.

MMIXAL 언어 자체는 `mmixal.pdf`의 첫 장 "MMIXAL의 정의"에서 설명한다.

### `mmixsim`: 단순 시뮬레이터

```text
mmixsim <options> progfile command line-args...
```

목적 파일 `progfile.mmo`를 읽어 실행한다. 뒤에 오는 인자들은 MMIX 프로그램의 `argc`/`argv`가 된다.
주요 옵션은 다음과 같다.

| 옵션 | 뜻 |
| --- | --- |
| `-t<n>` | 각 명령을 처음 n번 실행할 때 추적 |
| `-e<x>` | 예외 x가 일어나는 명령을 추적 |
| `-r` | 레지스터 스택의 숨은 동작까지 추적 |
| `-l<n>` | 추적할 때 원시 줄도 함께 보여 줌 |
| `-s` | 끝날 때 통계를 보여 줌 |
| `-P` | 끝날 때 프로파일을 보여 줌 |
| `-v` / `-q` | 거의 모든 것을 보여 줌 / 시뮬레이트된 표준 출력만 보여 줌 |
| `-i` / `-I` | 대화형으로 실행 / 프로그램이 멈춘 뒤에만 대화 |
| `-f<file>` | 파일을 시뮬레이트된 표준 입력으로 씀 |
| `-D<file>` | `mmmix`가 읽을 수 있는 이진 덤프 파일(`.mmb`)을 만듦 |

대화형 모드(`-i`)에서 `h`를 입력하면 명령 목록이 나온다.
명령 파일은 `i 파일이름`으로 읽어 들이고, `q`로 끝낸다.
이 시뮬레이터는 캐시와 파이프라인이 없는 대신, 명령마다 정해진 시간(mem `μ`와 oop `υ`)을 센다.

### `mmotype`: 목적 파일 보기

```text
mmotype [-s] [-v] mmofile
```

이 프로그램은 `.mmo` 파일을 주소와 내용, 원시 줄 번호, 기호표로 풀어 보여 준다.
옵션 `-s`를 주면 기호표만 보여 주고, `-v`를 주면 입력의 테트라바이트를 읽는 대로 모두 보여 준다.

### `mmmix`: 파이프라인 메타 시뮬레이터

```text
mmmix [-s] [-k<kernel>] configfile progfile
```

설정 파일 `configfile`(`.mmconfig`)이 정하는 하드웨어로 `progfile`을 사이클 단위로 시뮬레이트한다.
설정 파일은 파이프라인 폭, 기능 장치, 캐시, 분기 예측 등을 정한다.
프로그램 파일 `progfile`은 두 가지 형식을 받는다.

- **`.mmb`**: `mmixsim -D`로 만든 이진 덤프다. 텍스트, 데이터, 풀, 스택
  세그먼트와 `Main`이 갖추어진 보통의 사용자 프로그램이다.
- **`.mmix`**: 16진 텍스트 파일이다. 세그먼트 구분도 `Main`도 없이 메모리에
  무엇이든 넣을 수 있다. 운영체제 코드, 가상 주소 변환, 인터럽트 같은
  하드웨어의 모든 면을 시험할 수 있지만, 시작 주소를 `@<x>` 명령으로 직접
  정해야 한다.

실행하면 `mmmix>` 프롬프트가 나온다. 주요 명령은 다음과 같다.

| 명령 | 뜻 |
| --- | --- |
| `<n>` | n 사이클 동안 실행 |
| `@<x>` | 다음 명령을 주소 x에서 가져옴 |
| `b<x>` | 주소 x의 명령을 가져올 때 멈춤 |
| `v<x>` | 진단 출력 선택(`vff`는 거의 모든 것) |
| `p`, `s` | 파이프라인 내용, 통계 출력 |
| `I`, `D`, `S` 등 | 캐시 내용 출력 |
| `h`, `q` | 도움말, 끝내기 |

옵션 `-s`를 주면 `TRAP 0,Halt,0`을 만날 때까지 조용히 돌린다.
옵션 `-k<kernel>`은 옮긴이가 덧붙인 것으로, 프로그램을 실은 뒤에 NNIX 커널의 목적 파일을
싣는다(아래 [NNIX 커널](#nnix-커널) 참고).

## 예제 돌려 보기

디렉터리 `examples/`에는 크누스가 배포한 예제가 있다.
아래 예는 실행 파일들이 `PATH`에 있다고 가정하고, `examples/` 안에서 실행한다.
결과 파일(`.mmo`, `.lst`, `.mmb`)이 그 디렉터리에 생긴다.

```sh
cd examples
```

### 1. 인사하기

```sh
$ mmixal hello.mms          # hello.mmo 생성
$ mmixsim hello
hello, world
$ mmotype hello.mmo         # 목적 파일 들여다보기
```

### 2. 파일 복사와 목록 파일

```sh
mmixal -l copy.lst copy.mms   # copy.mmo와 기호 목록 copy.lst 생성
mmixsim copy copy.mms         # MMIX 프로그램이 copy.mms를 표준 출력으로 복사
```

### 3. 추적과 통계

```sh
mmixal primes.mms
mmixsim -s primes             # 처음 500개 소수와 실행 통계
mmixsim -t2 -l primes         # 명령마다 두 번까지 원시 줄과 함께 추적
mmixsim -P -L primes          # 프로파일
```

### 4. 명령 256개 모두 시험하기

시험 프로그램 `silly.mms`는 256개 연산 코드를 거의 다 써 보는 괴상한 시험 프로그램이다.
명령 파일 `silly.run`과 올바른 출력 `silly.out`도 함께 들어 있다.

```sh
$ mmixal silly.mms
$ mmixsim -i silly
mmix> i silly.run
...                               # 약 100KB의 출력. silly.out과 같아야 한다
mmix> q
```

### 5. 파이프라인 메타 시뮬레이터

먼저 `mmixsim -D`로 이진 덤프를 만든 다음, 그것을 `mmmix`에 설정 파일과 함께 넘긴다.

```sh
$ mmixsim -Dhello.mmb hello
$ mmmix plain.mmconfig hello.mmb
mmmix> 10000
Running 10000 at time 0
hello, world
Halted at time 405
mmmix> q
Simulation ended at time 406.
Predictions: 0 in agreement, 0 in opposition; 0 good, 0 bad
Instructions issued per cycle:
  0   380
  1   26
```

시험 프로그램 `silly`도 같은 방법으로 돌릴 수 있다. `mmixsim -Dsilly.mmb silly`
다음에 `mmmix plain.mmconfig silly.mmb`를 실행하면 된다.
진단 명령 `vff`를 먼저 주면 파이프라인의 모든 움직임이 출력되는데, 그 양이 엄청나다.

16진 프로그램은 시작 주소를 직접 정한다. 다음은 크누스의 첫 시험 프로그램으로,
복잡한 가상 주소 변환을 보여 준다.

```sh
$ mmmix test1.mmconfig test1.mmix
mmmix> @8000000000010000
mmmix> b0
mmmix> 140
Running 140 at time 0 with breakpoint 0000000000000000
Breakpoint instruction fetched at time 137
mmmix> q
```

명령 `b0` 다음에 `vff`를 넣으면 사이클마다 코루틴과 버퍼의 상태가 모두 출력된다.

### 6. NNIX 커널로 돌리기

`make nnix`로 커널을 어셈블한 다음 `-k`로 싣는다. 출력은 같지만, 이번에는 진짜
트랩 처리기가 일하므로 사이클이 더 걸린다.

```sh
$ make nnix
$ mmmix -knnix/nnix.mmo plain.mmconfig hello.mmb
mmmix> 10000
Running 10000 at time 0
hello, world
Halted at time 1342
mmmix> q
```

진단 명령 `v40`을 먼저 주면 커널이 장치 레지스터에 읽고 쓰는 것이 모두 보인다.

### 예제 파일

| 파일 | 내용 |
| --- | --- |
| `hello`, `copy`, `cp`, `echo` | 기본 입출력 |
| `primes*`, `fib*`, `sort*`, `crypto*`, `harm`, … | TAOCP 1.3′, 1.4′의 예제 |
| `sim` | MMIXAL로 쓴 MMIX 시뮬레이터(TAOCP 1.4.3′) |
| `permu-*`, `coolcomb`, `alpha`, `leadingbit`, … | TAOCP 7권 연습문제 |
| `silly`, `test`, `iotest*`, `hptest`, `fsubtest`, … | 어셈블러와 시뮬레이터 시험 |
| `silly.run`, `silly.out` | `silly` 시험의 명령 파일과 기대 출력 |
| `*.mmconfig` | `mmmix` 설정 파일(`plain`이 가장 무난하다) |
| `*.mmix` | `mmmix`용 16진 프로그램(`test1`, `test2`, `primes` 등) |

표에서 확장자가 없는 이름은 MMIXAL 원시 파일 `.mms`를 가리킨다.

## NNIX 커널

크누스는 MMIX의 운영체제를 NNIX라고 부르고는 만들지 않았다(`mmixdoc.pdf` 2절).
메타 시뮬레이터 `mmmix`는 그 자리를 "마법"으로 메운다. 트랩 주소 rT에서 `RESUME 1`을
배정하면 `Fopen`, `Fputs` 같은 입출력 트랩 열 가지가 시뮬레이터 안에서 순식간에 일어난다.
`nnix/nnix.mms`는 그 자리에 진짜 트랩 처리기를 두는 작은 커널이다. 하는 일은 이렇다.

- `TRAP 0,Y,Z`를 나누고, 사용자 메모리에서 인자를 읽는다.
- 가상 주소를 물리 주소로 바꾼다. 페이지 테이블을 순회하는 코드는 크누스가
  명세(`mmixdoc.pdf` 47절)에 적은 것을 거의 그대로 옮겼다.
- 메모리 사상 입출력 장치에 명령을 내리고, 끝나기를 기다려 결과를 돌려준다.

장치는 `mmmix/mmixmem.w`에 덧붙인 호스트 입출력 장치(HIO)다. 물리 주소 2^48
(커널이 보기에는 `#8001000000000000`)에 레지스터 여섯 개를 둔다. 호스트의 파일을 읽고
쓰는 일은 여전히 시뮬레이터 안에서 `mmixio`가 하지만, 이제는 장치 레지스터라는
하드웨어 인터페이스를 거친다. 장치를 이렇게 설계한 까닭은 파이프라인의 성질에 있다.
`mmmix`에서 시험해 보면 장치 적재는 투기적으로 일어나고, 같은 주소로 가는 저장은 쓰기
버퍼에서 합쳐지며, `SYNC 4`로 멈추면 쓰기 버퍼에 남은 저장이 버려진다. 자세한 것은
`mmmix/mmixmem.pdf`의 "호스트 입출력 장치" 장과 `nnix/nnix.mms`의 주석에 있다.

`-k`를 주지 않으면 `mmmix`는 원본과 똑같이 동작한다. 시험 `TestKernelMatchesMagic`은
같은 프로그램을 마법으로 돌린 출력과 커널로 돌린 출력이 같은지 견준다.

1단계에서는 일부러 몇 가지를 남겨 두었다. 버퍼는 한 물리 페이지 안에 있다고 가정한다
(미리 짜 둔 환경의 페이지가 2^32바이트라 지금은 문제가 없다). 처리기는 인터럽트를
끈 채로 돌고, 동적 트랩 처리기는 원시적인 것을 그대로 쓴다. 다음 단계에서는 진짜
페이지 테이블과 요구 페이징, 타이머 인터럽트로 프로세스 둘을 번갈아 돌리기, 블록
장치 위의 작은 파일 시스템을 차례로 쌓을 생각이다.

## 문서를 읽는 순서

문서는 `make doc`으로 만든 루트와 각 디렉터리의 `.pdf`로 읽는다.
찾아보기의 번호는 쪽이 아니라 절 번호다. MMIX를 차근차근 이해하려면 다음 순서를 권한다.

### 1단계: 기계를 알기

1. **`mmixdoc.pdf`**(48쪽): MMIX 아키텍처 명세다. 레지스터, 명령
   256개, 트립과 트랩, 특수 레지스터, 가상 주소 변환까지 다룬다. 다른 모든
   문서가 이것을 전제로 하므로 가장 먼저 읽는다.
2. **`mmixal/mmixal.pdf`의 앞 두 장**: "MMIXAL의 정의"와 "이진 MMO 출력"이다.
   어셈블리 언어와 목적 파일 형식을 다룬다. 크누스의 원본 배포판도 이 부분을
   `mmixal-intro`로 따로 떼어 입문서로 삼는다.
3. **`mmixsim/mmixsim.pdf`의 앞 두 장**: "들어가며"와 "초보적인 입출력"이다.
   시뮬레이터 사용법과 실행 환경(`Main`, `argc`/`argv`, `TRAP`을 통한
   입출력)을 다룬다. 원본의 `mmix-sim-intro`에 해당한다.

여기까지 읽고 `examples/`의 프로그램들을 돌려 보면 MMIX로 프로그램을 짤 수 있다.

### 2단계: 단순 시뮬레이터의 내부

1. **`mmixarith/mmixarith.pdf`**: 128비트 곱셈과 나눗셈, IEEE 부동소수점의
   포장과 풀기, 덧셈, 곱셈, 십진 변환, 나머지를 다룬다. 시뮬레이터가 산술
   명령을 흉내 낼 때 이 루틴들을 부른다.
2. **`mmixio/mmixio.pdf`**: `Fopen`, `Fread`, `Fputs` 같은 `TRAP` 입출력의
   구현이다.
3. **`mmixsim/mmixsim.pdf`의 나머지**: 모의 메모리, 목적 파일 싣기, 256갈래
   스위치로 명령을 흉내 내는 주 루프, 트립과 트랩, 추적을 다룬다.
4. **`mmotype/mmotype.pdf`**: 1단계에서 읽은 "이진 MMO 출력"을 거꾸로 읽는
   프로그램이다. 목적 파일 형식을 복습하기 좋다.
5. **`abstime/abstime.pdf`**(3쪽): 쉬어 가는 작은 프로그램이다.

### 3단계: 파이프라인 메타 시뮬레이터

1. **`mmmix/mmixpipe.pdf`**(261쪽): 이 꾸러미의 핵심이다. 코루틴으로 짠
   파이프라인, 동적 투기, 배정·실행·확정 단계, 분기 예측, 캐시, 가상 주소
   변환, 쓰기 버퍼, 인터럽트를 차례로 쌓아 올린다. 1단계의 `mmixdoc` 가운데
   가상 주소와 인터럽트 부분을 다시 곁에 두고 읽으면 좋다.
2. **`mmmix/mmixconfig.pdf`**: `.mmconfig` 파일 형식과, 그 설정대로 캐시와
   기능 장치를 만드는 과정이다.
3. **`mmmix/mmixmem.pdf`**: 메모리 사상 입출력을 붙일 자리다. 옮긴이가 NNIX
   커널을 위한 호스트 입출력 장치를 덧붙였다.
4. **`mmmix/mmmix.pdf`**: 위 모듈들을 묶는 구동 프로그램이다. `.mmix`와
   `.mmb` 적재, `mmmix>` 대화 명령을 다룬다.

두 시뮬레이터 `mmixsim`과 `mmmix`에는 옮긴이가 덧붙인 "C 라이브러리 흉내 내기" 장과 "시험" 장이 있다.
앞의 장은 원본이 기대는 C 표준 라이브러리의 동작(`fgets`, `sscanf` 등)을 Go로 똑같이 재현한다.
뒤의 장은 크누스의 예제를 C 원본과 같은 결과가 나오는지 확인하는 Go 테스트다.
