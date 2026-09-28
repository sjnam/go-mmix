//line mmixmem.w:29
package main

var kind = [4]string{"byte", "wyde", "tetra", "octa"}

//line mmixmem.w:41
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

//line mmixmem.w:67
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

//line mmixmem.w:61
		mx.printf(" from %016x at time %d)\n", addr, int32(Tetra(mx.ticks)))
	}
	return val << ((8 - (1 << size) - int(addr&7)) << 3)
}

//line mmixmem.w:81
func (mx *machine) specWrite(addr, val Octa, size int) {
	if mx.verbose&showSpecBit != 0 {
		size &= 0x3
		addr = addr&^0xffffffff | Octa(Tetra(addr)&-(Tetra(1)<<size))
		val >>= (8 - (1 << size) - int(addr&7)) << 3
		mx.printf("   (spec_write ")

//line mmixmem.w:67
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

//line mmixmem.w:88
		mx.printf(" to %016x at time %d)\n", addr, int32(Tetra(mx.ticks)))
	}
}
