% 이 파일은 MMIXware의 mmix-mem.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

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

import (
	"os"
	@#
	"github.com/sjnam/go-mmix/mmixio"
)

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
	if mx.hioDev != nil && addr-hioBase < hioSize {
		@<장치 0의 레지스터를 읽어 |val|에 넣는다@>
	} else if mx.blkDev != nil && addr-blkBase < hioSize {
		@<장치 1의 레지스터를 읽어 |val|에 넣는다@>
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
	if mx.hioDev != nil && addr-hioBase < hioSize && size == 3 && addr&7 == 0 {
		@<장치 0의 레지스터에 |val|을 쓴다@>
	}
	if mx.blkDev != nil && addr-blkBase < hioSize && size == 3 && addr&7 == 0 {
		@<장치 1의 레지스터에 |val|을 쓴다@>
	}
}

@ 덧붙여, 합친 주소 $a$와 크기 $s$는 실제 메모리 버스의 64비트로 보낼 수 있을 것이다. 주소 $a$는 늘
$2^s$의 배수이고 $2^{63}$보다 작기 때문이다. 그러니 $(a,s)$는 64비트 수 $2a+2^s$에 깔끔하게 담을
수 있다. (생각해 보라.)

@* 호스트 입출력 장치. 보충: 이 장은 옮긴이가 덧붙인 것이다. 메타 시뮬레이터는 \NNIX\ 없이도
돌 수 있도록 rT 자리에서 \.{RESUME}~\.1을 배정하면 입출력 트랩을 ``마법''으로 해치운다. 저장소의
\.{nnix/nnix.mms}는 그 자리에 진짜 트랩 처리기를 두는 작은 커널이다. 커널은 트랩을 나누고, 사용자
메모리에서 인자를 읽고, 버퍼가 걸친 페이지를 들여놓은 뒤, 여기서 정의하는 장치에 입출력을 시킨다.
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
\#28&DONE&읽기: 지금까지 끝낸 명령의 수\cr
\#30&RV&읽고 쓰기: 주소를 변환할 rV 값. 0이면 주소는 물리 주소다\cr}}$$
연산 코드 op는 \.{TRAP}의 Y와 같다(|Fopen|${}=1$부터 |Ftell|${}=10$까지). 그래서 커널은 Y를
그대로 넘긴다. |Halt|는 장치로 오지 않으므로 op${}=0$은 트립 경고에 쓴다.

@<상수@>=
const (
	hioBase   = 1 << 48            // physical address of device 0
	hioSize   = 1 << 16            // number of bytes occupied by one device
	hioID     = 0x00               // offset of register \.{ID}
	hioArg0   = 0x08               // offset of register \.{ARG0}
	hioArg1   = 0x10               // offset of register \.{ARG1}
	hioCmd    = 0x18               // offset of register \.{CMD}
	hioResult = 0x20               // offset of register \.{RESULT}
	hioDone   = 0x28               // offset of register \.{DONE}
	hioRV     = 0x30               // offset of register \.{RV}
	hioMagic  = 0x4e4e49582d48494f // \.{"NNIX-HIO"}
)

@ 장치를 만들 때 자기 몫의 \.{mmixio} 상태를 하나 둔다. 마법이 쓰는 |mx.io|는 사용자의 가상 주소를
받아 세그먼트를 고정된 방식으로 사상하지만, 장치는 \.{RV}가 가리키는 진짜 페이지 테이블로 변환하기
때문이다.

@<타입 정의@>=
type hio struct {
	mx     *machine
	io     *mmixio.IO
	arg0   Octa // register \.{ARG0}
	arg1   Octa // register \.{ARG1}
	result Octa // register \.{RESULT}
	done   Octa // register \.{DONE}
	rv     Octa // register \.{RV}
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
	reg = mx.hioDev.result
case hioDone:
	reg = mx.hioDev.done
case hioRV:
	reg = mx.hioDev.rv
}
val = reg >> ((8 - (1 << size) - int(addr&7)) << 3)

@ 저장은 확정된 뒤에야 쓰기 버퍼를 거쳐 차례로 이곳에 닿는다. 그래서 상태는 저장으로만 바꾼다.
\.{CMD}가 닿으면 그 자리에서 명령을 다 하고 \.{DONE}을 하나 늘린다. 커널은 \.{DONE}이 바뀔 때까지
기다린 뒤에 \.{RESULT}를 읽는다. 트립 경고는 \.{RESULT}를 바꾸지 않는다.

@<장치 0의 레지스터에...@>=
h := mx.hioDev
switch addr - hioBase {
case hioArg0:
	h.arg0 = val
case hioArg1:
	h.arg1 = val
case hioRV:
	h.rv = val
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

@ 레지스터 \.{RV}는 장치의 IOMMU다. 그것이 0이 아니면 장치는 인자로 받은 주소를 그 rV 값이 정하는
페이지 테이블로 변환한다. 규칙은 \MMIX\ 프로세서와 같다. 음수 주소는 부호 비트를 지운 물리 주소이고,
음이 아닌 주소는 \.{mmixdoc}의 규칙대로 PTP와 PTE를 거친다. 그래서 커널은 사용자의 가상 주소를
그대로 넘길 수 있다. 버퍼가 여러 페이지에 걸치고 그 프레임들이 물리 메모리에 흩어져 있어도 된다.
커널은 넘기기 전에 버퍼의 페이지를 들여놓으므로 장치는 페이지 폴트를 처리하지 않는다. 변환할 수 없는
주소를 만나면 거기서 멈춘다. \.{RV}가 0이면 주소를 물리 주소로 본다.

함수 |piece|는 주소 |v|에서 시작하는 |size|바이트 가운데 한 페이지에 든 앞부분의 물리 주소 |pa|와
길이 |n|을 돌려준다. 입출력 공간이나 그 너머를 가리키는 주소는 받지 않는다.

@<함수들@>=
func (h *hio) piece(v Octa, size int) (pa Octa, n int, ok bool) {
	n = size
	if h.rv == 0 || v&signBit != 0 {
		pa = v &^ signBit
	} else {
		@<|v|를 |h.rv|로 변환해서 |pa|에 넣고 |n|을 페이지 안으로 줄인다@>
	}
	if n != 0 && (pa >= hioBase || pa+Octa(n-1) >= hioBase) {
		return 0, 0, false
	}
	return pa, n, true
}

@ 변환은 명세 47절의 소프트웨어 변환 코드를 \GO/로 옮긴 것이다. 페이지 번호의 1024진 ``자릿수''를
오른쪽에서 왼쪽으로 찾고, 맨 윗자리에 해당하는 테이블에서 PTP들을 거쳐 PTE까지 내려온다. PTP는
부호가 1이고 $n$~필드가 rV와 맞아야 하며, PTE는 $n$~필드가 맞아야 한다. 테이블은 |magicRead|로
읽으므로 커널이 막 써서 아직 쓰기 버퍼나 캐시에 있는 항목도 보인다.

@<|v|를 |h.rv|로...@>=
rv := h.rv
sh := uint(rv >> 40 & 0xff)
if sh < 13 || sh > 48 {
	return 0, 0, false
}
var b, a [5]Octa
for j := 1; j <= 4; j++ {
	b[j] = rv >> (64 - 4*j) & 0xf
}
i := v >> 61
r := rv >> 13 & (1<<27 - 1)
t := (r + b[i]) << 13            // address of the first page table
limit := (r + b[i+1]) << 13      // address just past the last page table
a[0] = (v &^ (7 << 61)) >> sh    // the page number
if a[0] == 0 {
	limit++
}
d := 0
for d < 4 && a[d] >= 1024 {
	a[d+1] = a[d] >> 10
	a[d] &= 0x3ff
	d++
}
if t += Octa(d) << 13; t >= limit {
	return 0, 0, false
}
@<PTP들을 거쳐 PTE까지 내려와 |pa|와 |n|을 정한다@>

@ 테이블 |t|의 항목 |a[d]|가 다음 수준의 PTP다. 가장 아래 수준의 항목 |a[0]|이 PTE이고, 물리
주소는 $2^s a+(v\bmod2^s)$다.

@<PTP들을 거쳐...@>=
for ; d > 0; d-- {
	x := h.mx.magicRead(t + 8*a[d])
	if x&signBit == 0 || (x^rv)&0x1ff8 != 0 {
		return 0, 0, false
	}
	t = x &^ signBit &^ 0x1fff
}
x := h.mx.magicRead(t + 8*a[0])
if (x^rv)&0x1ff8 != 0 {
	return 0, 0, false
}
mask := Octa(1)<<sh - 1
pa = x&(1<<48-1)&^mask | v&mask
if left := int(mask + 1 - v&mask); left < n {
	n = left
}

@ 장치는 |mmixio.Simulator|가 요구하는 메서드 셋을 구현한다. 버퍼를 한 페이지씩 변환해서
\.{mmixpipe.w}의 |getChars|와 |putChars|로 읽고 쓴다. 그것들은 |magicRead|와 |magicWrite|를 거치므로
쓰기 버퍼와 캐시까지 살핀다. 곧 이 장치는 캐시 일관성을 지키는 DMA처럼 동작한다.

페이지는 짝수 크기이고 짝수 주소에서 시작하므로, |getChars|의 멈춤 조건(널 바이트, 또는 짝수
주소에서 시작하는 널 와이드)은 페이지 경계에 걸리지 않는다. 그래서 한 페이지에서 덜 읽었으면
거기서 멈추고, 다 읽었으면 다음 페이지로 넘어가면 된다.

@<함수들@>=
func (h *hio) StdinChr() byte { return h.mx.StdinChr() }
@#
func (h *hio) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	for k := 0; k < size; {
		pa, n, ok := h.piece(addr+Octa(k), size-k)
		if !ok {
			h.mx.errprintf("HIO: Attempt to get characters from off the memory!\n")
@.HIO: Attempt to get characters...@>
			return k
		}
		if m := h.mx.getChars(buf[k:], n, pa, stop); m < n {
			return k + m
		}
		k += n
	}
	return size
}
@#
func (h *hio) MMPutChars(buf []byte, size int, addr Octa) {
	for k := 0; k < size; {
		pa, n, ok := h.piece(addr+Octa(k), size-k)
		if !ok {
			h.mx.errprintf("HIO: Attempt to put characters off the memory!\n")
@.HIO: Attempt to put characters...@>
			return
		}
		h.mx.putChars(buf[k:], n, pa)
		k += n
	}
}

@* 블록 장치. 보충: 이 장도 옮긴이가 덧붙인 것이다. \NNIX\ 커널의 4단계는 파일 시스템을 갖는다.
그 디스크가 장치~1이다. 명령줄에 \.{-d<image>}를 주면 호스트의 파일 하나가 1024바이트짜리 블록들의
디스크가 된다. 디스크 이미지는 저장소의 도구 \.{nnixfs}로 만들고, 거기에 파일을 넣고 꺼낸다.
장치는 블록 하나를 메모리와 디스크 사이에서 통째로 옮긴다(DMA). 레지스터는 모두 옥타바이트다.
$$\vbox{\halign{\hfil\tt#\quad&\.{#}\hfil\quad&#\hfil\cr
\#00&ID&읽기: 상수 \.{"NNIX-BLK"}\cr
\#08&BLOCK&쓰기: 블록 번호\cr
\#10&ADDR&쓰기: 메모리 쪽 버퍼의 주소(음수면 부호 비트를 지운 물리 주소)\cr
\#18&CMD&쓰기: 1이면 블록을 메모리로 읽고, 2면 메모리를 블록에 쓴다. 닿는 순간 실행한다\cr
\#20&RESULT&읽기: 마지막 명령의 결과. 0이면 성공, $-1$이면 실패\cr
\#28&DONE&읽기: 지금까지 끝낸 명령의 수\cr
\#30&NBLK&읽기: 디스크의 블록 수\cr}}$$
규약은 장치~0과 같다. 커널은 \.{DONE}이 바뀔 때까지 기다린 뒤에 \.{RESULT}를 읽는다.

다만 장치~0과 달리 이 장치는 시간이 걸린다. 명령은 |blkLatency|사이클 뒤에야 끝나고, 그때 블록을
옮기고 \.{DONE}을 늘리고 rQ의 비트 |blkInt|를 켠다. 이것은 rQ의 ``높은 우선순위 입출력'' 바이트들의
가장 오른쪽 비트다. 커널은 그동안 다른 프로세스를 돌리다가 이 인터럽트로 기다리던 프로세스를
깨운다. 명령이 끝나기 전에 다음 명령을 내리면 그것은 무시한다.

@<상수@>=
const (
	blkBase   = hioBase + hioSize  // physical address of device 1
	blkSize   = 1024               // number of bytes in a block
	blkBlock  = 0x08               // offset of register \.{BLOCK}
	blkAddr   = 0x10               // offset of register \.{ADDR}
	blkNblk   = 0x30               // offset of register \.{NBLK}
	blkMagic  = 0x4e4e49582d424c4b // \.{"NNIX-BLK"}
	blkLatency = 10000             // cycles taken by one command
	blkInt    = 1 << 8             // bit of rQ set when a command finishes
)

@ @<타입 정의@>=
type blk struct {
	mx     *machine
	f      *os.File // the disk image
	nblk   Octa     // register \.{NBLK}
	block  Octa     // register \.{BLOCK}
	addr   Octa     // register \.{ADDR}
	result Octa     // register \.{RESULT}
	done   Octa     // register \.{DONE}
	cmd    Octa     // the command in progress (0 if none)
	count  int      // cycles left until that command finishes
}

@ 레지스터 \.{ID}, \.{RESULT}, \.{DONE}의 오프셋은 장치~0과 같다.

@<장치 1의 레지스터를 읽어...@>=
var reg Octa
switch addr&^7 - blkBase {
case hioID:
	reg = blkMagic
case hioResult:
	reg = mx.blkDev.result
case hioDone:
	reg = mx.blkDev.done
case blkNblk:
	reg = mx.blkDev.nblk
}
val = reg >> ((8 - (1 << size) - int(addr&7)) << 3)

@ 메모리는 |magicRead|와 |magicWrite|로 읽고 쓴다. 그러니 이 장치도 캐시 일관성을 지키는 DMA다.
버퍼는 옥타바이트 경계에 있어야 하고 입출력 공간에 걸치면 안 된다. 호스트 파일의 읽기나 쓰기가
실패해도 \.{RESULT}가 $-1$이 된다.

@<장치 1의 레지스터에...@>=
d := mx.blkDev
switch addr - blkBase {
case blkBlock:
	d.block = val
case blkAddr:
	d.addr = val &^ signBit
case hioCmd:
	if d.cmd == 0 {
		d.cmd, d.count = val, blkLatency
	}
}

@ 메서드 |tick|은 \.{mmixpipe.w}가 사이클마다 부른다. 명령이 진행 중이면 남은 사이클을 줄이고, 다
되면 일을 한다. 레지스터 \.{BLOCK}과 \.{ADDR}은 명령이 끝날 때의 값을 쓴다(커널은 그동안 바꾸지
않는다). 크누스의 타이머 rI처럼 rQ와 |newQ|에 같은 비트를 켠다.

@<함수들@>=
func (d *blk) tick() {
	if d.cmd == 0 {
		return
	}
	if d.count--; d.count > 0 {
		return
	}
	mx, val := d.mx, d.cmd
	d.cmd = 0
	d.result = negOne
	if d.block < d.nblk && d.addr&7 == 0 && d.addr+blkSize <= hioBase && (val == 1 || val == 2) {
		var b [blkSize]byte
		if val == 1 {
			@<블록 |d.block|을 메모리 |d.addr|로 읽는다@>
		} else {
			@<메모리 |d.addr|를 블록 |d.block|에 쓴다@>
		}
	}
	d.done++
	mx.g[rQ].o |= blkInt
	mx.newQ |= blkInt
}

@ @<블록 |d.block|을...@>=
if _, err := d.f.ReadAt(b[:], int64(d.block)*blkSize); err == nil {
	for k := 0; k < blkSize; k += 8 {
		var o Octa
		for _, c := range b[k : k+8] {
			o = o<<8 | Octa(c)
		}
		mx.magicWrite(d.addr+Octa(k), o)
	}
	d.result = 0
}

@ @<메모리 |d.addr|를...@>=
for k := 0; k < blkSize; k += 8 {
	o := mx.magicRead(d.addr + Octa(k))
	for j := 7; j >= 0; j-- {
		b[k+j] = byte(o)
		o >>= 8
	}
}
if _, err := d.f.WriteAt(b[:], int64(d.block)*blkSize); err == nil {
	d.result = 0
}

@* 찾아보기.
