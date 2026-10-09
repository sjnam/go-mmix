//line mmixmem.w:38
package main

import (
	"os"

	"github.com/sjnam/go-mmix/mmixio"
)

var kind = [4]string{"byte", "wyde", "tetra", "octa"}

//line mmixmem.w:148
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

//line mmixmem.w:377
const (
	blkBase    = hioBase + hioSize  // physical address of device 1
	blkSize    = 1024               // number of bytes in a block
	blkBlock   = 0x08               // offset of register \.{BLOCK}
	blkAddr    = 0x10               // offset of register \.{ADDR}
	blkNblk    = 0x30               // offset of register \.{NBLK}
	blkMagic   = 0x4e4e49582d424c4b // \.{"NNIX-BLK"}
	blkLatency = 10000              // cycles taken by one command
	blkInt     = 1 << 8             // bit of rQ set when a command finishes
)

//line mmixmem.w:166
type hio struct {
	mx     *machine
	io     *mmixio.IO
	arg0   Octa // register \.{ARG0}
	arg1   Octa // register \.{ARG1}
	result Octa // register \.{RESULT}
	done   Octa // register \.{DONE}
	rv     Octa // register \.{RV}
}

//line mmixmem.w:389
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

//line mmixmem.w:58
func (mx *machine) specRead(addr Octa, size int) Octa {
	var val Octa
	size &= 0x3
	addr = addr&^0xffffffff | Octa(Tetra(addr)&-(Tetra(1)<<size))
	if mx.hio != nil && addr-hioBase < hioSize {

//line mmixmem.w:181
		var reg Octa
		switch addr&^7 - hioBase {
		case hioID:
			reg = hioMagic
		case hioResult:
			reg = mx.hio.result
		case hioDone:
			reg = mx.hio.done
		case hioRV:
			reg = mx.hio.rv
		}
		val = reg >> ((8 - (1 << size) - int(addr&7)) << 3)

//line mmixmem.w:64
	} else if mx.blk != nil && addr-blkBase < hioSize {

//line mmixmem.w:404
		var reg Octa
		switch addr&^7 - blkBase {
		case hioID:
			reg = blkMagic
		case hioResult:
			reg = mx.blk.result
		case hioDone:
			reg = mx.blk.done
		case blkNblk:
			reg = mx.blk.nblk
		}
		val = reg >> ((8 - (1 << size) - int(addr&7)) << 3)

//line mmixmem.w:66
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

//line mmixmem.w:88
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

//line mmixmem.w:82
		mx.printf(" from %016x at time %d)\n", addr, int32(Tetra(mx.ticks)))
	}
	return val << ((8 - (1 << size) - int(addr&7)) << 3)
}

//line mmixmem.w:106
func (mx *machine) specWrite(addr, val Octa, size int) {
	if mx.verbose&showSpecBit != 0 {
		size &= 0x3
		addr = addr&^0xffffffff | Octa(Tetra(addr)&-(Tetra(1)<<size))
		val >>= (8 - (1 << size) - int(addr&7)) << 3
		mx.printf("   (spec_write ")

//line mmixmem.w:88
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

//line mmixmem.w:113
		mx.printf(" to %016x at time %d)\n", addr, int32(Tetra(mx.ticks)))
	}
	if mx.hio != nil && addr-hioBase < hioSize && size == 3 && addr&7 == 0 {

//line mmixmem.w:199
		h := mx.hio
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

//line mmixmem.w:117
	}
	if mx.blk != nil && addr-blkBase < hioSize && size == 3 && addr&7 == 0 {

//line mmixmem.w:422
		d := mx.blk
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

//line mmixmem.w:120
	}
}

//line mmixmem.w:249
func (h *hio) piece(v Octa, size int) (pa Octa, n int, ok bool) {
	n = size
	if h.rv == 0 || v&signBit != 0 {
		pa = v &^ signBit
	} else {

//line mmixmem.w:268
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
		t := (r + b[i]) << 13         // address of the first page table
		limit := (r + b[i+1]) << 13   // address just past the last page table
		a[0] = (v &^ (7 << 61)) >> sh // the page number
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

//line mmixmem.w:300
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

//line mmixmem.w:255
	}
	if n != 0 && (pa >= hioBase || pa+Octa(n-1) >= hioBase) {
		return 0, 0, false
	}
	return pa, n, true
}

//line mmixmem.w:326
func (h *hio) StdinChr() byte { return h.mx.StdinChr() }

func (h *hio) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	for k := 0; k < size; {
		pa, n, ok := h.piece(addr+Octa(k), size-k)
		if !ok {
			h.mx.errprintf("HIO: Attempt to get characters from off the memory!\n")

			return k
		}
		if m := h.mx.getChars(buf[k:], n, pa, stop); m < n {
			return k + m
		}
		k += n
	}
	return size
}

func (h *hio) MMPutChars(buf []byte, size int, addr Octa) {
	for k := 0; k < size; {
		pa, n, ok := h.piece(addr+Octa(k), size-k)
		if !ok {
			h.mx.errprintf("HIO: Attempt to put characters off the memory!\n")

			return
		}
		h.mx.putChars(buf[k:], n, pa)
		k += n
	}
}

//line mmixmem.w:439
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

//line mmixmem.w:463
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

//line mmixmem.w:453
		} else {

//line mmixmem.w:475
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

//line mmixmem.w:455
		}
	}
	d.done++
	mx.g[rQ].o |= blkInt
	mx.newQ |= blkInt
}
