% 이 파일은 MMIXware의 mmix-io.w((c) 1999 Donald E. Knuth)를 한글 GWEB(Go)로
% 옮긴 것으로, MMIXware 꾸러미의 일부가 아니다.
@i ../boilerplate.w

@s os.File int
@s io.Writer int
@s bufio.Reader int
@s bufio.Writer int
@s bytes.Buffer int
@s mmixarith.Octa int
@s mmixarith.Tetra int
@s testing.T int

\input kotexgweb
\def\title{MMIXIO}

@* 들어가며. 이 프로그램 모듈에는 {\mc MMIX-SIM}의 앞머리에서 정의한 입출력 기본 연산 열
가지를 우직하게 구현한 것이 들어 있다. 이 서브루틴들을 별도의 꾸러미로 묶은 것은, 단순한
시뮬레이터뿐 아니라 파이프라인 시뮬레이터와도 함께 적재하려는 것이기 때문이다.
@^I/O@>
@^input/output@>

보충: \MMIX\ 프로그램은 \.{TRAP}~\.{0,Fopen,5} 같은 명령으로 초보적인 운영체제를 부른다.
Y 필드가 호출 번호, Z 필드가 핸들(handle)이고, 인자는 \$255와 그것이 가리키는 메모리에 있다.
시뮬레이터는 그 인자를 모아 이 꾸러미의 메서드를 부르고, 돌려받은 값을 \$255에 넣는다.
호출 번호는 \MMIXAL의 미리 정의된 기호 \.{Fopen}(1)부터 \.{Ftell}(10)까지다.

원본에서는 핸들 256개의 정보가 전역 배열이었다. 여기서는 그것을 구조체 |IO|에 담고, 원본이
각 시뮬레이터에서 가져다 쓰던 세 서브루틴은 인터페이스 |Simulator|로 받는다. 원본은 \CEE/
표준 입출력 라이브러리의 |FILE|을 썼는데, \GO/에는 그에 딱 맞는 것이 없다. 그래서 이 모듈이
기대는 |FILE|의 성질---읽기 버퍼, |feof|와 |ferror| 표시, |fgets|의 경계 동작, |fseek|와
|ftell|---을 흉내 내는 작은 타입 |stream|을 만들었다. 그 설명은 이 문서의 끝에 있다.

@c
package mmixio

import (
	"bufio"
	"fmt"
	"io"
	"os"
	@#
	"github.com/sjnam/mmix/mmixarith"
)

@<타입 정의@>
@<표@>
@<함수들@>

@ 원본은 옛 \CEE/와 맞추려고 \.{ARGS} 매크로와 \.{FILENAME\_MAX}, \.{SEEK\_SET}, \.{SEEK\_END}의
대용 정의를 두었다. \GO/에서는 필요 없다. 다만 파일 이름의 최대 길이는 \.{mmixal}에서처럼
원본과 비교 시험을 한 macOS의 \.{FILENAME\_MAX} 값 1024를 쓴다.

부호 없는 32비트 타입 \&{tetra}는 시뮬레이터의 정의와 맞아야 했다. 여기서는 \.{mmixarith}의
정의를 그대로 쓴다.

@<타입 정의@>=
type (
	Tetra = mmixarith.Tetra
	Octa  = mmixarith.Octa
)

const filenameMax = 1024

@ 기본 서브루틴 세 개가 모의 메모리에서 문자열을 가져오고 모의 메모리에 문자열을 넣는 데
쓰인다. 이 서브루틴들은 시뮬레이터마다 알맞게 정의된다. 원본은 {\mc MMIX-ARITH}에 정의된
서브루틴과 상수 몇 개도 썼는데, 64비트 \GO/에서는 연산자로 충분하다.

보충: 원본의 시뮬레이터가 정의한 약속은 이렇다. 메서드 |MMGetChars(buf,size,addr,stop)|은 모의
메모리의 주소 |addr|에서부터 문자들을 읽어 |buf|에 넣는데, |size|개를 읽거나 다른 멈춤 조건을
만날 때까지 계속한다. 인자 |stop|이 음수이면 다른 조건이 없다. 그것이 0이면 널 문자에서도 멈춘다. 그
밖에는 |addr|이 짝수이고, 짝수 주소에서 시작하는 널 바이트 둘에서 멈춘다. 읽어서 넣은 바이트
수를, 끝내는 널 문자를 빼고 돌려준다. 메서드 |MMPutChars(buf,size,addr)|은 |size|개의 문자를 모의
메모리의 주소 |addr|에서부터 넣는다. 메서드 |StdinChr|은 모의 프로그램의 표준 입력에서 문자 하나를
준다. 시뮬레이터는 대화용 입력과 섞이지 않도록 이것을 따로 관리한다.

@<타입 정의@>=
type Simulator interface {
	StdinChr() byte
	MMGetChars(buf []byte, size int, addr Octa, stop int) int
	MMPutChars(buf []byte, size int, addr Octa)
}

@ 가능한 핸들마다 파일 포인터 하나와 현재 방식(mode)이 있다.

@<타입 정의@>=
type simFileInfo struct {
	fp   *stream // 파일 포인터
	mode int    // [읽기 가능] + 2[쓰기 가능] + 4[이진] + 8[읽고 쓰기]
}

@ 보충: 원본의 전역 배열 |sfile|과 시뮬레이터의 세 서브루틴을 한데 담는다. 시뮬레이터마다
|IO| 값을 하나씩 만들어 쓴다.

@<타입 정의@>=
type IO struct {
	sfile   [256]simFileInfo
	sim     Simulator
	streams []*stream // 지금까지 연 모든 파일 스트림(|FlushAll|을 위해)
	stderr  *stream   // 원래의 표준 오류, 곧 \CEE/의 |stderr|
}

@ 처음 세 핸들은 처음부터 열려 있다. 원본의 |mmix_io_init|이 하던 일을 여기서는 |IO| 값을
만드는 함수 |New|가 한다. 표준 출력과 표준 오류는 시뮬레이터가 자신의 출력에 쓰는 것과 같은
것을 넘겨받는다. 원본에서도 모의 프로그램의 출력과 시뮬레이터의 추적 출력이 같은 \CEE/
|stdout|을 나누어 썼기 때문이다.

@<함수들@>=
func New(sim Simulator, stdout, stderr io.Writer) *IO {
	x := &IO{sim: sim}
	x.sfile[0] = simFileInfo{&stream{isStdin: true}, 1}
	x.sfile[1] = simFileInfo{&stream{w: stdout}, 2}
	x.stderr = &stream{w: stderr, unbuffered: true}
	x.sfile[2] = simFileInfo{x.stderr, 2}
	return x
}

@ 이 루틴들에서 유일하게 까다로운 점은, 표준 입력과 출력과 오류 스트림이 가로채이지 않도록
보호하고 싶다는 것이다.

보충: 그래서 핸들 0, 1, 2에 새 파일을 열 때는 원래의 스트림을 닫지 않는다. 방식 번호 |mode|는
\MMIXAL의 미리 정의된 기호 \.{TextRead}(0), \.{TextWrite}(1), \.{BinaryRead}(2),
\.{BinaryWrite}(3), \.{BinaryReadWrite}(4)다. 성공하면 0을, 실패하면 $-1$을 돌려준다. 실패하면
그 핸들은 닫힌 것으로 친다. 원본은 실패한 경우를 |goto abort|로 한 곳에 모았다. 여기서는
그 공통 꼬리를 메서드 |abort|로 둔다.

@<함수들@>=
func (x *IO) Fopen(handle byte, name, mode Octa) Octa {
	var nameBuf [filenameMax]byte
	if mode > 4 {
		return x.abort(handle)
	}
	m := x.sim.MMGetChars(nameBuf[:], filenameMax, name, 0)
	if m == filenameMax {
		return x.abort(handle)
	}
	if x.sfile[handle].mode != 0 && handle > 2 {
		x.sfile[handle].fp.close()
	}
	f, err := os.OpenFile(string(nameBuf[:m]), modeFlags[mode], 0o666)
	if err != nil {
		return x.abort(handle)
	}
	x.sfile[handle].fp = &stream{f: f, r: bufio.NewReader(f)}
	x.streams = append(x.streams, x.sfile[handle].fp)
	x.sfile[handle].mode = modeCode[mode]
	return 0 // 성공
}

func (x *IO) abort(handle byte) Octa {
	x.sfile[handle].mode = 0
	return mmixarith.NegOne // 실패
}

@ 원본은 |fopen|에 넘길 방식 문자열 \.{"r"}, \.{"w"}, \.{"rb"}, \.{"wb"}, \.{"w+b"}를 표로
두었다. \GO/에서는 그에 해당하는 |os.OpenFile|의 플래그를 표로 둔다. \.{"w"}와 \.{"w+b"}는
파일을 만들거나 길이를 0으로 줄인다. {\mc POSIX} 시스템에서는 텍스트 방식과 이진 방식이
다르지 않다.

@<표@>=
var modeFlags = [5]int{
	os.O_RDONLY,                        // \.{"r"}
	os.O_WRONLY | os.O_CREATE | os.O_TRUNC, // \.{"w"}
	os.O_RDONLY,                        // \.{"rb"}
	os.O_WRONLY | os.O_CREATE | os.O_TRUNC, // \.{"wb"}
	os.O_RDWR | os.O_CREATE | os.O_TRUNC,   // \.{"w+b"}
}
var modeCode = [5]int{0x1, 0x2, 0x5, 0x6, 0xf}

@ 시뮬레이터를 대화식으로 쓸 때는, 다른 파일을 대신 써서 |stdin|을 두고 다투는 일을 피할 수
있다.

@<함수들@>=
func (x *IO) FakeStdin(f *os.File) {
	x.sfile[0].fp = &stream{f: f, r: bufio.NewReader(f)} // |f|는 읽기 방식으로 열려 있어야 한다
	x.streams = append(x.streams, x.sfile[0].fp)
}

@ @<함수들@>=
func (x *IO) Fclose(handle byte) Octa {
	if x.sfile[handle].mode == 0 {
		return mmixarith.NegOne
	}
	if handle > 2 && !x.sfile[handle].fp.close() {
		return mmixarith.NegOne
	}
	x.sfile[handle].mode = 0
	return 0 // 성공
}

@ 메서드 |Fread|는 |size|바이트를 읽어서 모의 메모리의 |buffer|에 넣고, 실제로 읽은 바이트 수에서
|size|를 뺀 값을 돌려준다. 다 읽었으면 0이고, 파일 끝에 닿았으면 음수다. 오류가 나면
$-1-|size|$를 돌려준다.

읽기와 쓰기를 둘 다 하는 핸들에서는 읽은 다음 쓰기를 막는다. \CEE/ 표준 입출력 라이브러리는
읽기와 쓰기 사이에 |fseek|를 요구하기 때문이다. 쓰기를 다시 허용하는 것은 |Fseek|다.

보충: 원본은 |size|바이트짜리 버퍼를 |calloc|으로 한 번에 잡아서 읽고, 그것을 모의 메모리에
한꺼번에 넣었다. 크기 |size|는 $2^{32}-1$까지 될 수 있으므로, 여기서는 64킬로바이트씩 나누어 읽고
넣는다. 파일 끝에 닿거나 모자라게 읽히면 멈춘다. 결과는 원본과 같다. 다른 점은 읽는 도중에
입출력 오류가 났을 때 앞서 읽은 부분이 이미 메모리에 들어가 있다는 것뿐이다.

@<함수들@>=
func (x *IO) Fread(handle byte, buffer, size Octa) Octa {
	o := mmixarith.NegOne
	if x.sfile[handle].mode&0x1 == 0 {
		return o - size
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x2
	}
	if size>>32 != 0 {
		return o - size
	}
	@<|n<=size|개의 문자를 읽어 모의 메모리에 넣는다; 오류이면 |return o-size|@>
	return Octa(n) - size
}

@ 표준 입력에서는 시뮬레이터의 |StdinChr|로 정확히 |size|개의 문자를 읽는다. 원본은 파일을
읽기 전에 |clearerr|로 파일 끝 표시와 오류 표시를 지웠다. 그래서 전에 파일 끝에 닿았더라도
파일이 그사이에 늘어났으면 더 읽을 수 있다.

@<|n<=size|개의 문자를...@>=
fp := x.sfile[handle].fp
buf := make([]byte, min(size, 1<<16))
n := 0
if fp.isStdin {
	for n < int(size) {
		k := min(int(size)-n, len(buf))
		for i := range k {
			buf[i] = x.sim.StdinChr()
		}
		x.sim.MMPutChars(buf, k, buffer+Octa(n))
		n += k
	}
} else {
	fp.clearerr()
	for n < int(size) {
		k := fp.read(buf[:min(int(size)-n, len(buf))])
		if fp.bad {
			return o - size
		}
		x.sim.MMPutChars(buf, k, buffer+Octa(n))
		n += k
		if fp.eof {
			break
		}
	}
}

@ 메서드 |Fgets|는 줄 하나를 읽되 |size|$-1$개 문자까지만 읽는다. 읽은 것 뒤에는 널 문자를 붙여서
모의 메모리에 넣고, 읽은 문자 수를 돌려준다. 원본은 한 번에 255자씩 읽었다. 줄바꿈 문자를
읽었거나, 크기가 다 찼거나, 파일 끝에 닿으면 끝난다.

@<함수들@>=
func (x *IO) Fgets(handle byte, buffer, size Octa) Octa {
	var buf [256]byte
	var n, s int
	var o Octa
	eof := false
	if x.sfile[handle].mode&0x1 == 0 {
		return mmixarith.NegOne
	}
	if size == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x2
	}
	size--
	for {
		@<|n<256|개의 문자를 |buf|에 읽는다@>
		x.sim.MMPutChars(buf[:], n+1, buffer)
		o += Octa(n)
		size -= Octa(n)
		if (n > 0 && buf[n-1] == '\n') || size == 0 || eof {
			return o
		}
		buffer += Octa(n)
	}
}

@ 파일에서 읽을 때 원본은 |fgets|를 썼는데, |fgets|는 읽은 문자 수를 알려 주지 않는다.
그래서 원본은 버퍼를 훑으면서 줄바꿈 문자까지 센다. 파일 끝에 닿았으면 첫 널 문자가 끝을
나타낸다. 그렇지 않으면 널 문자도 줄의 일부로 센다. 이 한글판의 |fgets|도 원본처럼 버퍼
|buf|의 끝에 널 문자를 붙여 주므로, 원본의 세기를 그대로 쓴다.

@<|n<256|개의 문자를...@>=
s = 255
if size < Octa(s) {
	s = int(size)
}
fp := x.sfile[handle].fp
if fp.isStdin {
	for n = 0; n < s; {
		buf[n] = x.sim.StdinChr()
		n++
		if buf[n-1] == '\n' {
			break
		}
	}
} else {
	if !fp.fgets(buf[:], s+1) {
		return mmixarith.NegOne
	}
	eof = fp.eof
	for n = 0; n < s; {
		if buf[n] == 0 && eof {
			break
		}
		n++
		if buf[n-1] == '\n' {
			break
		}
	}
}
buf[n] = 0

@ 와이드 문자를 다루는 루틴들은 작은 끝 시스템에서는 고쳐야 할지도 모른다. 크누스는 그 일을
맡게 될 누군가에게 행운을 빈다고 적었다. \MMIX은 늘 큰 끝이지만, 아무 운영체제에서나 준비한
외부 파일은 거꾸로일 수도 있다.
@^little-endian versus big-endian@>
@^big-endian versus little-endian@>
@^system dependencies@>

보충: 메서드 |Fgetws|는 |Fgets|와 같되 와이드 문자(두 바이트) 단위다. 버퍼 주소를 짝수로 맞추고,
한 번에 127자씩 읽으며, 와이드 줄바꿈 문자 \.{\#000a}에서 끝난다. 반환값은 와이드 문자의
수다.

@<함수들@>=
func (x *IO) Fgetws(handle byte, buffer, size Octa) Octa {
	var buf [256]byte
	var n, s int
	var o Octa
	eof := false
	if x.sfile[handle].mode&0x1 == 0 {
		return mmixarith.NegOne
	}
	if size == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x2
	}
	buffer &^= 1
	size--
	for {
		@<|n<128|개의 와이드 문자를 |buf|에 읽는다@>
		x.sim.MMPutChars(buf[:], 2*n+2, buffer)
		o += Octa(n)
		size -= Octa(n)
		if (n > 0 && buf[2*n-1] == '\n' && buf[2*n-2] == 0) || size == 0 || eof {
			return o
		}
		buffer += 2 * Octa(n)
	}
}

@ 파일에서는 두 바이트씩 |fread|로 읽는다. 두 바이트를 다 읽지 못하면, 파일 끝이면 거기서
멈추고 오류이면 실패를 돌려준다.

@<|n<128|개의 와이드...@>=
s = 127
if size < Octa(s) {
	s = int(size)
}
fp := x.sfile[handle].fp
p := 0
if fp.isStdin {
	for n = 0; n < s; {
		buf[p], buf[p+1] = x.sim.StdinChr(), x.sim.StdinChr()
		p += 2
		n++
		if buf[p-1] == '\n' && buf[p-2] == 0 {
			break
		}
	}
} else {
	for n = 0; n < s; {
		if fp.read(buf[p:p+2]) != 2 {
			eof = fp.eof
			if !eof {
				return mmixarith.NegOne
			}
			break
		}
		n++
		p += 2
		if buf[p-1] == '\n' && buf[p-2] == 0 {
			break
		}
	}
}
buf[p], buf[p+1] = 0, 0

@ 메서드 |Fwrite|는 모의 메모리의 |buffer|에서 |size|바이트를 써서, 쓰지 못한 바이트 수의 음수를
돌려준다. 다 썼으면 0이다. 한 번에 256바이트씩 쓰고, 쓸 때마다 스트림을 비운다.

보충: 쓰기가 실패하면 원본은 이번 조각을 이미 |size|에서 뺀 뒤의 값을 돌려준다. 이 한글판도
그렇다.

@<함수들@>=
func (x *IO) Fwrite(handle byte, buffer, size Octa) Octa {
	var buf [256]byte
	var n int
	if x.sfile[handle].mode&0x2 == 0 {
		return -size
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x1
	}
	for {
		if size >= 256 {
			n = x.sim.MMGetChars(buf[:], 256, buffer, -1)
		} else {
			n = x.sim.MMGetChars(buf[:], int(size), buffer, -1)
		}
		size -= Octa(n)
		if x.sfile[handle].fp.write(buf[:n]) != n {
			return -size
		}
		x.sfile[handle].fp.flush()
		if size == 0 {
			return 0
		}
		buffer += Octa(n)
	}
}

@ 메서드 |Fputs|는 널 문자로 끝나는 문자열을 쓰고, 쓴 바이트 수를 돌려준다.

@<함수들@>=
func (x *IO) Fputs(handle byte, str Octa) Octa {
	var buf [256]byte
	var o Octa
	if x.sfile[handle].mode&0x2 == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x1
	}
	for {
		n := x.sim.MMGetChars(buf[:], 256, str, 0)
		if x.sfile[handle].fp.write(buf[:n]) != n {
			return mmixarith.NegOne
		}
		o += Octa(n)
		if n < 256 {
			x.sfile[handle].fp.flush()
			return o
		}
		str += Octa(n)
	}
}

@ 메서드 |Fputws|는 널 와이드 문자로 끝나는 와이드 문자열을 쓰고, 쓴 와이드 문자의 수를
돌려준다.

보충: 원본은 문자열의 주소를 짝수로 맞추지 않는다. 그런데 시뮬레이터의 |mmgetchars|는
|stop>0|일 때 주소가 짝수라고 가정한다. 홀수 주소의 첫 바이트가 0이면 원본의 |mmgetchars|는
버퍼 앞의 바이트를 읽는데, 원본을 시험한 macOS에서는 그것이 0이어서 $-1$을 돌려주었다. 그러면
원본은 |fwrite|를 크기 |SIZE_MAX|로 부른다. 버퍼가 없는 표준 오류에서는 아무것도 쓰지 못하고
$-1$을 돌려주지만, 버퍼가 있는 표준 출력이나 파일에서는 스택 너머를 복사하다가 프로그램이
죽는다. \.{mmixsim}의 |MMGetChars|는 원본처럼 $-1$을 돌려주고, 여기서는 그것을 쓰기 실패로
다룬다. 원본의 |fwrite|는 이때 스트림의 오류 표시를 켜는데, 여기서도 그렇게 한다. 원본이
죽지 않는 경우에는 원본과 같은 결과다.

@<함수들@>=
func (x *IO) Fputws(handle byte, str Octa) Octa {
	var buf [256]byte
	var o Octa
	if x.sfile[handle].mode&0x2 == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x1
	}
	for {
		n := x.sim.MMGetChars(buf[:], 256, str, 1)
		if n < 0 {
			x.sfile[handle].fp.bad = true // 원본의 |fwrite|가 실패하며 오류 표시를 켠다
			return mmixarith.NegOne
		}
		if x.sfile[handle].fp.write(buf[:n]) != n {
			return mmixarith.NegOne
		}
		o += Octa(n >> 1)
		if n < 256 {
			x.sfile[handle].fp.flush()
			return o
		}
		str += Octa(n)
	}
}

@ 메서드 |Fseek|는 이진 방식으로 연 파일에서만 쓸 수 있다. 오프셋이 음이 아니면 파일의 처음에서부터
그만큼 떨어진 곳으로, 음수이면 파일의 끝에서부터 $|offset|+1$만큼 떨어진 곳으로 간다. 그래서
$-1$은 파일의 맨 끝이다. 오프셋은 부호 있는 32비트 정수여야 한다. 읽고 쓰는 핸들에서는 다시
읽기와 쓰기를 모두 허용한다.

@<함수들@>=
func (x *IO) Fseek(handle byte, offset Octa) Octa {
	if x.sfile[handle].mode&0x4 == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode = 0xf
	}
	if offset&mmixarith.SignBit != 0 {
		if offset>>31 != 0x1ffffffff {
			return mmixarith.NegOne
		}
		if !x.sfile[handle].fp.seek(int64(int32(offset))+1, io.SeekEnd) {
			return mmixarith.NegOne
		}
	} else {
		if offset>>31 != 0 {
			return mmixarith.NegOne
		}
		if !x.sfile[handle].fp.seek(int64(offset), io.SeekStart) {
			return mmixarith.NegOne
		}
	}
	return 0
}

@ 보충: 원본은 |offset.h|가 \Hex{ffffffff}이고 |offset.l|의 부호 비트가 켜져 있는지 따로
보았다. 64비트에서는 둘을 합쳐 위쪽 33비트가 모두 1인지 보면 된다. 음이 아닌 경우도 위쪽 33비트가
모두 0인지 본다. 메서드 |Ftell|은 현재 위치를 돌려주는데, 원본은 그것을 낮은 테트라바이트에만 넣었다.

@<함수들@>=
func (x *IO) Ftell(handle byte) Octa {
	if x.sfile[handle].mode&0x4 == 0 {
		return mmixarith.NegOne
	}
	pos, ok := x.sfile[handle].fp.tell()
	if !ok || pos < 0 {
		return mmixarith.NegOne
	}
	return Octa(Tetra(pos))
}

@ 사용자가 표준 오류 핸들을 바꾸었을 경우에 대비해, 마지막 서브루틴 하나가 여기에 속한다.

보충: \.{TRAP}~\.{0,Halt,1} 명령은 산술 예외 처리기가 없을 때 경고를 찍게 한다. 시뮬레이터는
처리기로 뛴 위치에서 |n|을 얻는다. 경고는 핸들~2가 쓰기로 열려 있을 때만 찍는다. 원본은
경고를 |fprintf|로 찍었다. 원본을 시험한 macOS에서 |fprintf|는 오류 표시가 켜진 스트림에도
쓰기는 하되, 버퍼가 없는 스트림(|stderr|)에는 아무것도 쓰지 않는다. 메서드 |fprintf|가 이것을
흉내 낸다.

@<함수들@>=
func (x *IO) PrintTripWarning(n int, loc Octa) {
	if x.sfile[2].mode&0x2 != 0 {
		x.sfile[2].fp.fprintf("Warning: %s at location %016x\n", tripWarning[n], loc)
	}
}
@#
func (s *stream) fprintf(format string, a ...any) {
	if s.bad && s.unbuffered {
		return
	}
	s.write([]byte(fmt.Sprintf(format, a...)))
}

@ 보충: 시뮬레이터 자신도 경고와 오류 알림을 |stderr|에 |fprintf|로 찍는다. 원본에서는 그것이
이 꾸러미의 표준 오류와 같은 \CEE/ 스트림이므로, 오류 표시가 켜지면 시뮬레이터의 알림도
사라진다. 이 메서드는 그 표시를 알려 준다. 핸들~2에 새 파일을 열었더라도 원래의 |stderr|를
본다.

@<함수들@>=
func (x *IO) StderrError() bool {
	return x.stderr.bad
}

@ 원본의 시뮬레이터는 끝날 때 |exit|을 불렀고, |exit|은 열려 있는 모든 \CEE/ 스트림의 버퍼를
비운다. \GO/에는 그런 장치가 없으므로, 시뮬레이터가 끝날 때 부를 메서드 |FlushAll|을 둔다.
옮긴이가 덧붙인 것이다.

비워야 할 스트림은 핸들 배열에 남은 것만이 아니다. 원본은 핸들 0, 1, 2에 새 파일을 열 때 옛
스트림을 닫지 않으므로, 옛 스트림은 핸들을 잃은 채 버퍼를 들고 있다가 |exit| 때 비워진다.
그래서 지금까지 연 모든 파일 스트림을 |streams|에 기억해 두었다가, 표준 스트림들 다음에 만든
순서대로 비운다. 원본을 비교 시험한 macOS의 |exit|도 표준 스트림 셋 다음에 스트림을 할당한
순서대로 비운다. 순서가 중요한 까닭은, 핸들~2로 같은 파일을 두 번 열고 두 번 다 경고를 남기면
나중에 비우는 쪽이 먼저 비운 쪽을 덮어쓰기 때문이다.

@<함수들@>=
func (x *IO) FlushAll() {
	for h := range 3 {
		if x.sfile[h].fp.f == nil { // 원래의 표준 스트림
			x.sfile[h].fp.flush()
		}
	}
	for _, fp := range x.streams {
		fp.flush()
	}
}

@ @<표@>=
var tripWarning = [...]string{
	"TRIP",
	"integer divide check",
	"integer overflow",
	"float-to-fix overflow",
	"invalid floating point operation",
	"floating point overflow",
	"floating point underflow",
	"floating point division by zero",
	"floating point inexact"}

@* \CEE/의 파일 흉내 내기. 이 장은 옮긴이가 덧붙인 것이다. 원본의 루틴들이 기대는 \CEE/
|FILE|의 성질을 흉내 내는 타입 |stream|을 만든다. 스트림은 세 가지다. 모의 프로그램의 표준
입력(|isStdin|)은 시뮬레이터의 |StdinChr|로 읽으므로 이 타입이 하는 일이 없다. 표준 출력과
표준 오류는 |w|로 쓰기만 한다. 나머지는 진짜 파일 |f|이고, 읽을 때는 버퍼 |r|을 거친다.

파일 끝 표시 |eof|와 오류 표시 |bad|는 \CEE/의 |feof|와 |ferror|에 해당한다. 이 표시는
끈끈하다. 한번 파일 끝에 닿으면 |clearerr|나 |fseek| 전까지는 더 읽지 않는다. 이것은 원본을
비교 시험한 macOS의 \CEE/ 라이브러리(그리고 요즘의 glibc)의 동작이고, \CEE/ 표준이 요구하는
것이기도 하다. 원본의 |Fgets|와 |Fgetws|는 |clearerr|를 부르지 않으므로 이 차이가 드러날 수
있다.

@<타입 정의@>=
type stream struct {
	f          *os.File      // 진짜 파일이면
	r          *bufio.Reader // |f|에서 읽을 때의 버퍼
	pending    []byte        // |f|에 아직 쓰지 않은 바이트들
	writing    bool          // 마지막으로 한 일이 쓰기인가?
	w          io.Writer     // 표준 출력이나 표준 오류이면
	isStdin    bool          // 모의 프로그램의 표준 입력인가?
	eof        bool          // 파일 끝 표시(|feof|)
	bad        bool          // 오류 표시(|ferror|)
	unbuffered bool          // 버퍼가 없는가(|stderr|처럼)?
}

@ 메서드 |read|는 |fread|처럼 최대 |len(p)|바이트를 읽어서, 읽은 바이트 수를 돌려준다. 모자라게
읽혔으면 파일 끝이나 오류 표시가 켜진다.

@<함수들@>=
func (s *stream) read(p []byte) int {
	if s.eof || s.r == nil {
		return 0
	}
	s.startReading()
	n, err := io.ReadFull(s.r, p)
	switch err {
	case nil:
	case io.EOF, io.ErrUnexpectedEOF:
		s.eof = true
	default:
		s.bad = true
	}
	return n
}

func (s *stream) clearerr() { s.eof, s.bad = false, false }

@ 메서드 |fgets(buf,n)|은 \CEE/의 |fgets|처럼 최대 $n-1$개 문자를 읽는데, 줄바꿈 문자를 읽으면 거기서
멈추고 끝에 널 문자를 붙인다. 문자를 하나도 읽지 못하고 파일 끝이나 오류를 만나면 거짓을
돌려준다. 크기가 $n=1$이면 아무것도 읽지 않고 널 문자만 넣은 채 성공한다. 이것도 macOS와 glibc의
동작이다.

@<함수들@>=
func (s *stream) fgets(buf []byte, n int) bool {
	if n <= 0 || s.r == nil {
		return false
	}
	i := 0
	for i < n-1 {
		if s.eof {
			break
		}
		s.startReading()
		c, err := s.r.ReadByte()
		if err != nil {
			if err == io.EOF {
				s.eof = true
			} else {
				s.bad = true
			}
			break
		}
		buf[i] = c
		i++
		if c == '\n' {
			break
		}
	}
	if i == 0 && n > 1 {
		return false
	}
	buf[i] = 0
	return true
}

@ 같은 스트림에서 쓰다가 읽거나 읽다가 쓰는 일은, 원본의 방식 비트 덕분에 |Fread| 같은
루틴에서는 |Fseek|를 거치지 않고는 일어나지 않는다. 그러나 |PrintTripWarning|은 방식 비트를 보지도
바꾸지도 않으므로, 핸들~2를 읽고 쓰기로 열어 놓으면 읽기와 쓰기가 위치 지정 없이 섞일 수 있다.
\CEE/ 표준은 그 결과를 정하지 않지만, 원본을 비교 시험한 macOS(곧 BSD)의 라이브러리가 하는 일은
분명하다. 쓰다가 읽기 시작하면 대기 중인 바이트를 먼저 내보내고, 읽다가 쓰기 시작하면 읽기
버퍼를 버리고 파일 끝 표시를 지운다. 그 뒤에 쓰는 바이트는 읽기 버퍼에 미리 읽어 들인 만큼
앞선 파일 위치에 들어간다. 여기서도 그렇게 한다.

@<함수들@>=
func (s *stream) startReading() {
	if s.writing {
		s.flush()
		s.writing = false
	}
}

@ 파일에 쓰는 바이트는 대기 버퍼 |pending|에 쌓았다가 |flush|할 때 내보낸다. 원본의 |Fwrite|,
|Fputs|, |Fputws|는 쓸 때마다 |fflush|를 불렀으므로 대기가 길지 않다. 그러나
|PrintTripWarning|은 |fprintf|만 하고 비우지 않으므로, 핸들~2를 파일로 바꾸어 놓으면 경고가
버퍼에 머문다. 같은 파일을 연 다른 핸들이 그사이에 쓰면 파일 안의 순서가 달라지므로, 이 동작도
흉내 낸다. (다만 \CEE/ 라이브러리는 버퍼가 가득 차면 저절로 비우는데, 경고만 수십 개가 쌓이는
경우는 흉내 내지 않았다.)

표준 출력과 표준 오류에는 곧바로 쓴다. 표준 오류는 \CEE/에서도 버퍼가 없다. 표준 출력이
시뮬레이터의 버퍼 달린 출력이면 |flush|가 그것을 비운다.

@<함수들@>=
func (s *stream) write(p []byte) int {
	if s.f != nil {
		if !s.writing {
			s.r.Reset(s.f) // 읽기 버퍼를 버린다
			s.eof, s.writing = false, true
		}
		s.pending = append(s.pending, p...)
		return len(p)
	}
	if s.w == nil {
		return 0
	}
	n, err := s.w.Write(p)
	if err != nil {
		s.bad = true
	}
	return n
}

func (s *stream) flush() bool {
	if s.f != nil && len(s.pending) > 0 {
		_, err := s.f.Write(s.pending)
		s.pending = s.pending[:0]
		if err != nil {
			s.bad = true
			return false
		}
	}
	if f, ok := s.w.(interface{ Flush() error }); ok {
		f.Flush()
	}
	return true
}

@ 메서드 |seek|는 대기 중인 바이트를 내보낸 뒤 파일의 위치를 옮기고, 읽기 버퍼를 버리고, 파일 끝
표시를 지운다. 메서드 |tell|은 파일의 위치에서 아직 읽지 않고 버퍼에 남은 바이트 수를 빼고, 아직 쓰지
않고 대기 중인 바이트 수를 더한다. 표준 스트림에서는 둘 다 실패한다. 메서드 |close|도 대기 중인
바이트를 먼저 내보낸다.

@<함수들@>=
func (s *stream) seek(off int64, whence int) bool {
	if s.f == nil || !s.flush() {
		return false
	}
	if _, err := s.f.Seek(off, whence); err != nil {
		return false
	}
	s.r.Reset(s.f)
	s.eof, s.writing = false, false
	return true
}

func (s *stream) tell() (int64, bool) {
	if s.f == nil {
		return 0, false
	}
	pos, err := s.f.Seek(0, io.SeekCurrent)
	if err != nil {
		return 0, false
	}
	return pos - int64(s.r.Buffered()) + int64(len(s.pending)), true
}

func (s *stream) close() bool {
	if s.f == nil {
		return true
	}
	ok := s.flush()
	return s.f.Close() == nil && ok
}

@* 시험. 원본에는 시험 프로그램이 없었다. 옮긴이는 가짜 시뮬레이터를 만들어 이 꾸러미의
메서드들을 부른다. 가짜 시뮬레이터의 메모리는 바이트의 사상(map)이고, |MMGetChars|는 원본
시뮬레이터의 멈춤 규칙을 바이트 단위로 구현한다. 원본은 테트라 단위로 읽으면서 같은 규칙을
지켰다.

이 문서 밖에서는 더 큰 비교를 했다. 원본 \.{mmix-io.c}에 원본 시뮬레이터의 |mmgetchars|와
|mmputchars|를 그대로 옮긴 가짜 메모리를 붙이고, 이 꾸러미에도 같은 것을 붙였다. 그런 다음
파일 열기, 닫기, 읽기, 쓰기, 옮기기, 표준 입력, 트립 경고를 무작위로 섞은 각본 수천 개를 두
구현에 넣고 반환값, 메모리, 표준 출력과 오류, 그리고 만들어진 파일들의 내용을 비교했다.
모두 같았다. 다만 두 가지는 각본에서 뺐다. 크기가 $2^{64}-1$인 쓰기는 원본도 사실상 끝나지
않는다. 홀수 주소의 |Fputws|는 원본 시뮬레이터의 |mmgetchars|가 버퍼 앞의 바이트를 읽는
정의되지 않은 동작이 된다. 뒤의 것은 \.{mmixsim}을 옮기면서 다시 살펴보았다(|Fputws|의 설명을
보라).

@(mmixio_test.go@>=
package mmixio

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

type fakeSim struct {
	mem   map[Octa]byte
	stdin []byte
}

func (f *fakeSim) StdinChr() byte {
	c := f.stdin[0]
	f.stdin = f.stdin[1:]
	return c
}

@ @(mmixio_test.go@>=
func (f *fakeSim) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	for m := 0; m < size; m++ {
		a := addr + Octa(m)
		buf[m] = f.mem[a]
		if buf[m] == 0 && stop == 0 {
			return m
		}
		if buf[m] == 0 && stop > 0 && a&1 != 0 && buf[m-1] == 0 {
			return m - 1
		}
	}
	return size
}

func (f *fakeSim) MMPutChars(buf []byte, size int, addr Octa) {
	for m := 0; m < size; m++ {
		f.mem[addr+Octa(m)] = buf[m]
	}
}

@ 시험마다 임시 디렉터리의 파일 이름을 모의 메모리의 주소 \Hex{100}에 넣어 둔다.

@(mmixio_test.go@>=
func setup(t *testing.T) (*IO, *fakeSim, *bytes.Buffer, *bytes.Buffer, string) {
	t.Helper()
	f := &fakeSim{mem: map[Octa]byte{}}
	name := filepath.Join(t.TempDir(), "file")
	f.MMPutChars(append([]byte(name), 0), len(name)+1, 0x100)
	var out, errs bytes.Buffer
	return New(f, &out, &errs), f, &out, &errs, name
}

func (f *fakeSim) str(addr Octa, n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = f.mem[addr+Octa(i)]
	}
	return string(b)
}

@ 읽고 쓰는 파일에 줄 둘을 쓰고, 처음으로 옮겨서 |Fgets|로 한 줄씩 읽는다. 읽은 줄 뒤에는
널 문자가 붙어야 한다. 파일 끝에서는 문자를 하나도 읽지 못하므로 $-1$이다. 파일 끝을 지나서
|Fread|를 하면 읽은 바이트 수에서 요청한 크기를 뺀 음수를 돌려준다.

@(mmixio_test.go@>=
func TestReadWrite(t *testing.T) {
	x, f, _, _, _ := setup(t)
	f.MMPutChars([]byte("Hello\nworld\n"), 12, 0x200)
	check := func(what string, got, want Octa) {
		t.Helper()
		if got != want {
			t.Errorf("%s = %#x, 원함 %#x", what, got, want)
		}
	}
	check("Fopen", x.Fopen(3, 0x100, 4), 0)
	check("Fwrite", x.Fwrite(3, 0x200, 12), 0)
	check("Ftell", x.Ftell(3), 12)
	check("Fseek", x.Fseek(3, 0), 0)
	check("Fgets", x.Fgets(3, 0x300, 100), 6)
	if s := f.str(0x300, 7); s != "Hello\n\x00" {
		t.Errorf("첫 줄 %q", s)
	}
	check("Fgets", x.Fgets(3, 0x300, 100), 6)
	check("Fgets", x.Fgets(3, 0x300, 100), NegOne)
	check("Fseek", x.Fseek(3, NegOne-1), 0) // $-2$: 마지막 바이트 앞
	check("Fread", x.Fread(3, 0x400, 20), NegOne-18) // $1-20=-19$
	check("Fclose", x.Fclose(3), 0)
	check("Fclose", x.Fclose(3), NegOne)
}

@ 방식이 맞지 않는 호출이다. 텍스트로 연 파일에서는 |Fseek|와 |Ftell|을 쓸 수 없고, 쓰기로 연
파일에서는 읽을 수 없다. 방식 번호가 4보다 크면 열기가 실패하고 그 핸들은 닫힌다.

@(mmixio_test.go@>=
func TestModes(t *testing.T) {
	x, _, _, _, _ := setup(t)
	if x.Fopen(4, 0x100, 1) != 0 {
		t.Fatal("Fopen 실패")
	}
	for _, c := range []struct {
		what      string
		got, want Octa
	}{
		{"Fseek", x.Fseek(4, 0), NegOne},
		{"Ftell", x.Ftell(4), NegOne},
		{"Fread", x.Fread(4, 0x200, 5), NegOne - 5},
		{"Fgets", x.Fgets(4, 0x200, 5), NegOne},
		{"Fwrite(stdin)", x.Fwrite(0, 0x200, 5), NegOne - 4},
		{"Fopen", x.Fopen(4, 0x100, 5), NegOne},
		{"Fputs", x.Fputs(4, 0x100), NegOne},
	} {
		if c.got != c.want {
			t.Errorf("%s = %#x, 원함 %#x", c.what, c.got, c.want)
		}
	}
}

@ @(mmixio_test.go@>=
const NegOne = ^Octa(0)

@ 표준 입력은 시뮬레이터의 |StdinChr|로 읽고, 표준 출력에 쓴 것은 |New|에 넘긴 곳으로 간다.
와이드 문자열은 널 와이드 문자에서 끝난다.

@(mmixio_test.go@>=
func TestStdStreams(t *testing.T) {
	x, f, out, _, _ := setup(t)
	f.stdin = []byte("abc\ndef")
	if n := x.Fgets(0, 0x200, 100); n != 4 || f.str(0x200, 5) != "abc\n\x00" {
		t.Errorf("Fgets(StdIn) = %d, %q", n, f.str(0x200, 5))
	}
	f.MMPutChars([]byte("hi!\x00"), 4, 0x300)
	f.MMPutChars([]byte{0, 'W', 0, 'X', 0, 0}, 6, 0x400)
	if n := x.Fputs(1, 0x300); n != 3 {
		t.Errorf("Fputs = %d", n)
	}
	if n := x.Fputws(1, 0x400); n != 2 {
		t.Errorf("Fputws = %d", n)
	}
	if out.String() != "hi!\x00W\x00X" {
		t.Errorf("표준 출력 %q", out.String())
	}
}

@ 트립 경고는 핸들~2로 간다. 핸들~2를 파일로 바꾸어 놓으면, 원본처럼 경고가 파일 버퍼에 머물다가
|FlushAll|에서 나간다.

@(mmixio_test.go@>=
func TestTripWarning(t *testing.T) {
	x, _, _, errs, name := setup(t)
	x.PrintTripWarning(2, 0x100)
	if want := "Warning: integer overflow at location 0000000000000100\n"; errs.String() != want {
		t.Errorf("표준 오류 %q", errs.String())
	}
	x.Fopen(2, 0x100, 1)
	x.PrintTripWarning(8, 4)
	if b, _ := os.ReadFile(name); len(b) != 0 {
		t.Errorf("경고가 벌써 파일에 있다: %q", b)
	}
	x.FlushAll()
	if b, _ := os.ReadFile(name); string(b) != "Warning: floating point inexact at location 0000000000000004\n" {
		t.Errorf("파일 %q", b)
	}
}

@* 찾아보기.
