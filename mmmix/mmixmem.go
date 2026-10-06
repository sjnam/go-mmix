//line mmixmem.w:35
package main

import "github.com/sjnam/go-mmix/mmixio"

var kind = [4]string{"byte", "wyde", "tetra", "octa"}

//line mmixmem.w:135
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

//line mmixmem.w:151
type hio struct {
	mx     *machine
	io     *mmixio.IO
	arg0   Octa // 레지스터 \.{ARG0}
	arg1   Octa // 레지스터 \.{ARG1}
	result Octa // 레지스터 \.{RESULT}
	done   Octa // 레지스터 \.{DONE}
}

//line mmixmem.w:51
func (mx *machine) specRead(addr Octa, size int) Octa {
	var val Octa
	size &= 0x3
	addr = addr&^0xffffffff | Octa(Tetra(addr)&-(Tetra(1)<<size))
	if mx.hio != nil && addr-hioBase < hioSize {

//line mmixmem.w:165
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

//line mmixmem.w:57
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

//line mmixmem.w:79
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

//line mmixmem.w:73
		mx.printf(" from %016x at time %d)\n", addr, int32(Tetra(mx.ticks)))
	}
	return val << ((8 - (1 << size) - int(addr&7)) << 3)
}

//line mmixmem.w:97
func (mx *machine) specWrite(addr, val Octa, size int) {
	if mx.verbose&showSpecBit != 0 {
		size &= 0x3
		addr = addr&^0xffffffff | Octa(Tetra(addr)&-(Tetra(1)<<size))
		val >>= (8 - (1 << size) - int(addr&7)) << 3
		mx.printf("   (spec_write ")

//line mmixmem.w:79
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

//line mmixmem.w:104
		mx.printf(" to %016x at time %d)\n", addr, int32(Tetra(mx.ticks)))
	}
	if mx.hio != nil && addr-hioBase < hioSize && size == 3 && addr&7 == 0 {

//line mmixmem.w:181
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

//line mmixmem.w:108
	}
}

//line mmixmem.w:224
func (h *hio) StdinChr() byte { return h.mx.StdinChr() }

func (h *hio) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	if size != 0 && (addr >= hioBase || addr+Octa(size-1) >= hioBase) {
		h.mx.errprintf("HIO: Attempt to get characters from off the memory!\n")

		return 0
	}
	return h.mx.getChars(buf, size, addr, stop)
}

func (h *hio) MMPutChars(buf []byte, size int, addr Octa) {
	if size != 0 && (addr >= hioBase || addr+Octa(size-1) >= hioBase) {
		h.mx.errprintf("HIO: Attempt to put characters off the memory!\n")

		return
	}
	h.mx.putChars(buf, size, addr)
}
