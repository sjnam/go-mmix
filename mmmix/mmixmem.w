% 이 파일은 MMIXware의 mmix-mem.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

@s Octa int
@s Tetra int
@s machine int

\input kotexgweb
\def\title{MMIXMEM}

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

@c
package main

var kind = [4]string{"byte", "wyde", "tetra", "octa"}
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
	if mx.verbose&interactiveReadBit != 0 {
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
}

@ 덧붙여, 합친 주소 $a$와 크기 $s$는 실제 메모리 버스의 64비트로 보낼 수 있을 것이다. 주소 $a$는 늘
$2^s$의 배수이고 $2^{63}$보다 작기 때문이다. 그러니 $(a,s)$는 64비트 수 $2a+2^s$에 깔끔하게 담을
수 있다. (생각해 보라.)

@* 찾아보기.
