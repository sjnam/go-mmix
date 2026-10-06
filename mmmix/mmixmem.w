% 이 파일은 MMIXware의 mmix-mem.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

@s Octa int
@s Tetra int
@s machine int
@s hio int
@s mmixio.IO int

\input kotexgweb
\def\title{MMIXMEM}
\def\NNIX{\hbox{\mc NNIX}}

@* 메모리 사상 입출력. 이 모듈은 48비트를 넘는 \MMIX\ 메모리 주소에서 읽고 쓰는 프로시저를
@^I/O@>
@^input/output@>
@^memory-mapped input/output@>
공급한다. 그런 주소는 운영체제가 입출력에 쓰므로 특별하게 다루어야 한다. 지금은 이 루틴들의
허수아비 판만 구현되어 있다. 루틴 |specRead|나 |specWrite|의 제대로 된 판이 필요한 사용자는 직접
만들어서 시뮬레이터의 나머지와 함께 링크하면 된다.

많은 입출력 장치는 옥타바이트가 아니라 바이트나 와이드나 테트라로 통신한다. 그래서 이 시제품
루틴들에는 |size| 매개변수가 있어서, \MMIX가 메모리 사상 주소에서 읽고 쓰려는 여러 종류의 양을
가린다.

보충: \GO/ 판에서 두 루틴은 |machine|의 메서드다. 원본은 주 프로그램 모듈의 |read_hex|를
가져다 썼는데, 여기서도 \.{mmmix.w}의 |readHex|를 쓴다. 원본의 정적 버퍼 |buf|는 |machine|의
필드 |specBuf|다.

보충: 원본의 두 루틴은 허수아비 판 그대로 두고, 끝에 \NNIX\ 커널을 위한 장치 하나를 덧붙인다.
명령줄에 \.{-k}를 주었을 때만 그 장치가 생기고, 장치에 배정한 주소에서만 끼어든다. 그 밖의
동작은 원본과 한 바이트도 다르지 않다.

@c
package main

import "github.com/sjnam/go-mmix/mmixio"

var kind = [4]string{"byte", "wyde", "tetra", "octa"}
@<상수@>
@<타입 정의@>
@<함수들@>

@ 진단 제어 |verbose|의 |interactiveReadBit|가 켜져 있으면 사용자가 값을 그때그때 공급해야 한다.
그렇지 않으면 0을 읽는다.

보충: 원본은 |fgets|가 실패해도 따지지 않는다. 그러면 버퍼에 남은 옛 내용을 읽는다. 원본의
|switch|는 |case| 사이를 흘러내리며 비트를 차례로 지웠는데, 여기서는 한 번에 지운다.

@<함수들@>=
func (mx *machine) specRead(addr Octa, size int) Octa {
	var val Octa
	size &= 0x3
	addr = addr&^0xffffffff | Octa(Tetra(addr)&-(Tetra(1)<<size))
	if mx.hio != nil && addr-hioBase < hioSize {
		@<장치 0의 레지스터를 읽어 |val|에 넣는다@>
	} else if mx.verbose&interactiveReadBit != 0 {
		mx.printf("** Read %s from loc %016x: ", kind[size], addr)
		mx.stdin.fgets(mx.specBuf[:], 20)
		val = readHex(mx.specBuf[:])
	}
	switch size {
	case 0:
		val &= 0xff
	case 1:
		val &= 0xffff
	case 2:
		val &= 0xffffffff
	}
	if mx.verbose&showSpecBit != 0 {
		mx.printf("   (spec_read ")
		@<크기 |size|의 값 |val|을 찍는다@>
		mx.printf(" from %016x at time %d)\n", addr, int32(Tetra(mx.ticks)))
	}
	return val << ((8 - (1 << size) - int(addr&7)) << 3)
}

@ @<크기 |size|의 값...@>=
switch size {
case 0:
	mx.printf("%02x", Tetra(val))
case 1:
	mx.printf("%04x", Tetra(val))
case 2:
	mx.printf("%08x", Tetra(val))
case 3:
	mx.printf("%016x", val)
}

@ 기본 |specWrite|는 인자들을 알리기만 하고 실제로 아무것도 쓰지 않는다.

보충: 장치 0에 쓰는 일은 알린 뒤에 한다. 그래야 \.{v40} 추적에서 \.{spec\_write} 줄이 장치가
찍는 출력보다 먼저 나온다. 장치의 레지스터는 옥타바이트뿐이고, 정렬된 옥타바이트를 쓸 때는
알리는 코드가 |addr|와 |val|을 바꾸지 않는다.

@<함수들@>=
func (mx *machine) specWrite(addr, val Octa, size int) {
	if mx.verbose&showSpecBit != 0 {
		size &= 0x3
		addr = addr&^0xffffffff | Octa(Tetra(addr)&-(Tetra(1)<<size))
		val >>= (8 - (1 << size) - int(addr&7)) << 3
		mx.printf("   (spec_write ")
		@<크기 |size|의 값...@>
		mx.printf(" to %016x at time %d)\n", addr, int32(Tetra(mx.ticks)))
	}
	if mx.hio != nil && addr-hioBase < hioSize && size == 3 && addr&7 == 0 {
		@<장치 0의 레지스터에 |val|을 쓴다@>
	}
}

@ 덧붙여, 합친 주소 $a$와 크기 $s$는 실제 메모리 버스의 64비트로 보낼 수 있을 것이다. 주소 $a$는 늘
$2^s$의 배수이고 $2^{63}$보다 작기 때문이다. 그러니 $(a,s)$는 64비트 수 $2a+2^s$에 깔끔하게 담을
수 있다. (생각해 보라.)

@* 호스트 입출력 장치. 보충: 이 장은 옮긴이가 덧붙인 것이다. 메타 시뮬레이터는 \NNIX\ 없이도
돌 수 있도록 rT 자리에서 \.{RESUME}~\.1을 배정하면 입출력 트랩을 ``마법''으로 해치운다. 저장소의
\.{nnix/nnix.mms}는 그 자리에 진짜 트랩 처리기를 두는 작은 커널이다. 커널은 트랩을 나누고, 사용자
메모리에서 인자를 읽고, 가상 주소를 물리 주소로 바꾼 뒤, 여기서 정의하는 장치에 입출력을 시킨다.
호스트의 파일을 읽고 쓰는 일은 여전히 시뮬레이터 안에서 \.{mmixio}가 하지만, 이제는 장치
레지스터라는 하드웨어 인터페이스를 거친다.

장치~$d$는 물리 주소 $2^{48}+2^{16}d$부터 $2^{16}$바이트를 차지한다. 지금은 장치~0 하나뿐이다.
커널은 이것을 가상 주소 \Hex{8001000000000000}으로 본다. 레지스터는 모두 옥타바이트다.
$$\vbox{\halign{\hfil\tt#\quad&\.{#}\hfil\quad&#\hfil\cr
\#00&ID&읽기: 상수 \.{"NNIX-HIO"}\cr
\#08&ARG0&쓰기: 첫째 인자\cr
\#10&ARG1&쓰기: 둘째 인자\cr
\#18&CMD&쓰기: $\rm op\times256+handle$. 이 값이 닿는 순간 명령을 실행한다\cr
\#20&RESULT&읽기: 마지막 명령의 결과\cr
\#28&DONE&읽기: 지금까지 끝낸 명령의 수\cr}}$$
연산 코드 op는 \.{TRAP}의 Y와 같다(|Fopen|${}=1$부터 |Ftell|${}=10$까지). 그래서 커널은 Y를
그대로 넘긴다. |Halt|는 장치로 오지 않으므로 op${}=0$은 트립 경고에 쓴다.

@<상수@>=
const (
	hioBase   = 1 << 48            // 장치 0의 물리 주소
	hioSize   = 1 << 16            // 장치 하나가 차지하는 바이트 수
	hioID     = 0x00               // 레지스터 \.{ID}의 오프셋
	hioArg0   = 0x08               // 레지스터 \.{ARG0}의 오프셋
	hioArg1   = 0x10               // 레지스터 \.{ARG1}의 오프셋
	hioCmd    = 0x18               // 레지스터 \.{CMD}의 오프셋
	hioResult = 0x20               // 레지스터 \.{RESULT}의 오프셋
	hioDone   = 0x28               // 레지스터 \.{DONE}의 오프셋
	hioMagic  = 0x4e4e49582d48494f // \.{"NNIX-HIO"}
)

@ 장치를 만들 때 자기 몫의 \.{mmixio} 상태를 하나 둔다. 마법이 쓰는 |mx.io|는 사용자의 가상 주소를
받아 세그먼트를 고정된 방식으로 사상하지만, 장치는 커널이 변환한 물리 주소를 받기 때문이다.

@<타입 정의@>=
type hio struct {
	mx     *machine
	io     *mmixio.IO
	arg0   Octa // 레지스터 \.{ARG0}
	arg1   Octa // 레지스터 \.{ARG1}
	result Octa // 레지스터 \.{RESULT}
	done   Octa // 레지스터 \.{DONE}
}

@ 파이프라인은 장치 적재를 투기적으로, 그리고 쓰기 버퍼의 앞선 저장보다 먼저 할 수 있다. 그래서
장치를 읽는 일에는 부작용이 없다. 쓰기 전용 레지스터는 0으로 읽힌다. 원본처럼 |size|에 맞는 바이트만
골라 두면 |specRead|의 나머지가 그것을 제자리에 놓는다.

@<장치 0의 레지스터를 읽어...@>=
var reg Octa
switch addr&^7 - hioBase {
case hioID:
	reg = hioMagic
case hioResult:
	reg = mx.hio.result
case hioDone:
	reg = mx.hio.done
}
val = reg >> ((8 - (1 << size) - int(addr&7)) << 3)

@ 저장은 확정된 뒤에야 쓰기 버퍼를 거쳐 차례로 이곳에 닿는다. 그래서 상태는 저장으로만 바꾼다.
\.{CMD}가 닿으면 그 자리에서 명령을 다 하고 \.{DONE}을 하나 늘린다. 커널은 \.{DONE}이 바뀔 때까지
기다린 뒤에 \.{RESULT}를 읽는다. 트립 경고는 \.{RESULT}를 바꾸지 않는다.

@<장치 0의 레지스터에...@>=
h := mx.hio
switch addr - hioBase {
case hioArg0:
	h.arg0 = val
case hioArg1:
	h.arg1 = val
case hioCmd:
	handle := byte(val)
	switch val >> 8 {
	case 0:
		h.io.PrintTripWarning(int(Tetra(h.arg0)), h.arg1)
	case Fopen:
		h.result = h.io.Fopen(handle, h.arg0, h.arg1)
	case Fclose:
		h.result = h.io.Fclose(handle)
	case Fread:
		h.result = h.io.Fread(handle, h.arg0, h.arg1)
	case Fgets:
		h.result = h.io.Fgets(handle, h.arg0, h.arg1)
	case Fgetws:
		h.result = h.io.Fgetws(handle, h.arg0, h.arg1)
	case Fwrite:
		h.result = h.io.Fwrite(handle, h.arg0, h.arg1)
	case Fputs:
		h.result = h.io.Fputs(handle, h.arg0)
	case Fputws:
		h.result = h.io.Fputws(handle, h.arg0)
	case Fseek:
		h.result = h.io.Fseek(handle, h.arg0)
	case Ftell:
		h.result = h.io.Ftell(handle)
	default:
		h.result = negOne
	}
	h.done++
}

@ 장치는 |mmixio.Simulator|가 요구하는 메서드 셋을 물리 주소로 구현한다. 메모리는 \.{mmixpipe.w}의
|getChars|와 |putChars|로 읽고 쓴다. 그것들은 |magicRead|와 |magicWrite|를 거치므로 쓰기 버퍼와
캐시까지 살핀다. 곧 이 장치는 캐시 일관성을 지키는 DMA처럼 동작한다. 입출력 공간이나 그 너머를
가리키는 주소는 받지 않는다.

@<함수들@>=
func (h *hio) StdinChr() byte { return h.mx.StdinChr() }
@#
func (h *hio) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	if size != 0 && (addr >= hioBase || addr+Octa(size-1) >= hioBase) {
		h.mx.errprintf("HIO: Attempt to get characters from off the memory!\n")
@.HIO: Attempt to get characters...@>
		return 0
	}
	return h.mx.getChars(buf, size, addr, stop)
}
@#
func (h *hio) MMPutChars(buf []byte, size int, addr Octa) {
	if size != 0 && (addr >= hioBase || addr+Octa(size-1) >= hioBase) {
		h.mx.errprintf("HIO: Attempt to put characters off the memory!\n")
@.HIO: Attempt to put characters...@>
		return
	}
	h.mx.putChars(buf, size, addr)
}

@* 찾아보기.
