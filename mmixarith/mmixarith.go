//line mmixarith/mmixarith.w:44
package mmixarith

import (
	"fmt"
	"math/bits"
	"strings"
)

//line mmixarith/mmixarith.w:71
type Tetra = uint32 // tetrabyte: 32 bits
type Octa = uint64  // two tetrabytes make one octabyte

//line mmixarith/mmixarith.w:398
type Round int // rounding mode

//line mmixarith/mmixarith.w:618
type ftype int // kind of floating point value

//line mmixarith/mmixarith.w:1337
type bignum struct {
	a   int               // index of the most significant digit
	b   int               // index of the least significant digit; must be $\ge a$
	dat [bignumPrec]Tetra // the digits; undefined except between |a| and |b|
}

//line mmixarith/mmixarith.w:1648
type ConstKind int // kind of constant found by |ScanConst|

//line mmixarith/mmixarith.w:79
const (
	SignBit     Octa = 1 << 63            // the sign bit
	NegOne      Octa = ^Octa(0)           // $-1$, i.e., all 64 bits are 1
	InfOcta     Octa = 0x7ff0000000000000 // floating point $+\infty$
	StandardNaN Octa = 0x7ff8000000000000 // floating point NaN(.5)
)

//line mmixarith/mmixarith.w:401
const (
	RoundOff  Round = 1 // round toward zero
	RoundUp   Round = 2 // round toward $+\infty$
	RoundDown Round = 3 // round toward $-\infty$
	RoundNear Round = 4 // round to nearest, ties to even
)

//line mmixarith/mmixarith.w:441
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

//line mmixarith/mmixarith.w:621
const (
	zro ftype = iota // 0
	num              // a nonzero finite number
	inf              // infinity
	nan              // NaN
)

const zeroExponent = -1000 // zero is assumed to have this exponent

//line mmixarith/mmixarith.w:1344
const bignumPrec = 157 // would be 77 if we cared only about |FloatString|

//line mmixarith/mmixarith.w:1455
const (
	magicOffset = 2112 // the constant $c$ that makes it work
	origin      = 37   // the radix point follows |dat[37]|
)

//line mmixarith/mmixarith.w:1651
const (
	NoConst      ConstKind = -1 // no constant was found
	DecimalConst ConstKind = 0  // decimal constant
	FloatConst   ConstKind = 1  // floating constant
)

//line mmixarith/mmixarith.w:1797
const (
	buf0   = 8   // index in |buf| where significant digits begin
	bufMax = 777 // index in |buf| where significant digits end
)

//line mmixarith/mmixarith.w:111
func ShiftRight(y Octa, s int, u bool) Octa {
	if u {
		return y >> s
	}
	return Octa(int64(y) >> s)
}

//line mmixarith/mmixarith.w:149
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

//line mmixarith/mmixarith.w:187
func Div(x, y, z Octa) (q, r Octa) {
	if x >= z {
		return x, y // trivial answer
	}
	return bits.Div64(x, y, z)
}

//line mmixarith/mmixarith.w:216
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

//line mmixarith/mmixarith.w:251
	if r != 0 {
		return ^q, r, false // $-q-1$
	}
	return -q, r, false

//line mmixarith/mmixarith.w:245
}

//line mmixarith/mmixarith.w:309
func ByteDiff(y, z Octa) Octa {
	d := (y & 0x00ff00ff00ff00ff) + 0x0100010001000100 - (z & 0x00ff00ff00ff00ff)
	m := d & 0x0100010001000100
	x := d & (m - (m >> 8))
	d = ((y >> 8) & 0x00ff00ff00ff00ff) + 0x0100010001000100 - ((z >> 8) & 0x00ff00ff00ff00ff)
	m = d & 0x0100010001000100
	return x + ((d & (m - (m >> 8))) << 8)
}

//line mmixarith/mmixarith.w:342
func WydeDiff(y, z Octa) Octa {
	d := (y & 0x0000ffff0000ffff) + 0x0001000000010000 - (z & 0x0000ffff0000ffff)
	m := d & 0x0001000000010000
	x := d & (m - (m >> 16))
	d = ((y >> 16) & 0x0000ffff0000ffff) + 0x0001000000010000 - ((z >> 16) & 0x0000ffff0000ffff)
	m = d & 0x0001000000010000
	return x + ((d & (m - (m >> 16))) << 16)
}

//line mmixarith/mmixarith.w:367
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

//line mmixarith/mmixarith.w:461
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

//line mmixarith/mmixarith.w:499
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

//line mmixarith/mmixarith.w:480
}

//line mmixarith/mmixarith.w:542
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

//line mmixarith/mmixarith.w:577
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

//line mmixarith/mmixarith.w:564
}

//line mmixarith/mmixarith.w:637
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

//line mmixarith/mmixarith.w:671
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

//line mmixarith/mmixarith.w:711
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

//line mmixarith/mmixarith.w:738
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

//line mmixarith/mmixarith.w:772
func FMult(y, z Octa, r Round) (x Octa, exc int) {
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, zs := funpack(z)
	xs := ys != zs
	switch 4*yt + zt {

//line mmixarith/mmixarith.w:803
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

//line mmixarith/mmixarith.w:778
	case 4*zro + zro, 4*zro + num, 4*num + zro:
		x = 0
	case 4*num + inf, 4*inf + num, 4*inf + inf:
		x = InfOcta
	case 4*zro + inf, 4*inf + zro:
		x = StandardNaN
		exc |= IBit
	case 4*num + num:

//line mmixarith/mmixarith.w:832
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

//line mmixarith/mmixarith.w:787
	}
	if xs {
		x |= SignBit
	}
	return
}

//line mmixarith/mmixarith.w:850
func FDivide(y, z Octa, r Round) (x Octa, exc int) {
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, zs := funpack(z)
	xs := ys != zs
	switch 4*yt + zt {

//line mmixarith/mmixarith.w:803
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

//line mmixarith/mmixarith.w:856
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

//line mmixarith/mmixarith.w:881
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

//line mmixarith/mmixarith.w:868
	}
	if xs {
		x |= SignBit
	}
	return
}

//line mmixarith/mmixarith.w:903
func FPlus(y, z Octa, r Round) (x Octa, exc int) {
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, zs := funpack(z)
	var xs bool
	switch 4*yt + zt {

//line mmixarith/mmixarith.w:803
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

//line mmixarith/mmixarith.w:909

//line mmixarith/mmixarith.w:933
	case 4*zro + num:
		return fpack(zf, ze, zs, RoundOff) // may underflow
	case 4*num + zro:
		return fpack(yf, ye, ys, RoundOff) // may underflow

//line mmixarith/mmixarith.w:910

//line mmixarith/mmixarith.w:942
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

//line mmixarith/mmixarith.w:911
	case 4*num + num:
		if y != z^SignBit {

//line mmixarith/mmixarith.w:960
			if ye < ze || (ye == ze && yf < zf) {

//line mmixarith/mmixarith.w:994
				yf, zf = zf, yf
				ye, ze = ze, ye
				ys, zs = zs, ys

//line mmixarith/mmixarith.w:962
			}
			d := ye - ze
			xs = ys
			xe := ye
			if d != 0 {

//line mmixarith/mmixarith.w:1025
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

//line mmixarith/mmixarith.w:968
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

//line mmixarith/mmixarith.w:914
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

//line mmixarith/mmixarith.w:1059
func FEpsComp(y, z, e Octa, s bool) int {

//line mmixarith/mmixarith.w:1070
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

//line mmixarith/mmixarith.w:1061
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, zs := funpack(z)

//line mmixarith/mmixarith.w:1086
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

//line mmixarith/mmixarith.w:1064

//line mmixarith/mmixarith.w:1149
	if ye < 0 && yt != zro {
		yf, ye = y<<2, 0
	}
	if ze < 0 && zt != zro {
		zf, ze = z<<2, 0
	}

//line mmixarith/mmixarith.w:1113
	if ye < ze || (ye == ze && yf < zf) {

//line mmixarith/mmixarith.w:994
		yf, zf = zf, yf
		ye, ze = ze, ye
		ys, zs = zs, ys

//line mmixarith/mmixarith.w:1115
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

//line mmixarith/mmixarith.w:1170
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

//line mmixarith/mmixarith.w:1127
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

//line mmixarith/mmixarith.w:1065
}

//line mmixarith/mmixarith.w:1200
func FloatString(x Octa) string {

//line mmixarith/mmixarith.w:1274
	var f, g Octa // lower and upper bounds on the fraction part
	var e int     // exponent part
	var j, k int  // all purpose indices

//line mmixarith/mmixarith.w:1582
	var ff, gg bignum        // fractions or numerators of fractions
	var tt bignum            // power of ten (used as the denominator)
	s := make([]byte, 0, 17) // significant digits

//line mmixarith/mmixarith.w:1202
	var sb strings.Builder
	if x&SignBit != 0 {
		sb.WriteByte('-')
	}

//line mmixarith/mmixarith.w:1251
	f = x << 1
	e = int(f >> 53)
	f &= 1<<53 - 1
	if f == 0 {

//line mmixarith/mmixarith.w:1287
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

//line mmixarith/mmixarith.w:1256
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

//line mmixarith/mmixarith.w:1207

//line mmixarith/mmixarith.w:1461
	k = (magicOffset - e) / 28
	ff.dat[k-1] = Tetra(f>>(magicOffset+28-e-28*k)) & 0xfffffff
	gg.dat[k-1] = Tetra(g>>(magicOffset+28-e-28*k)) & 0xfffffff
	ff.dat[k] = Tetra(f>>(magicOffset-e-28*k)) & 0xfffffff
	gg.dat[k] = Tetra(g>>(magicOffset-e-28*k)) & 0xfffffff
	ff.dat[k+1] = Tetra(f<<(e+28*k-(magicOffset-28))) & 0xfffffff
	gg.dat[k+1] = Tetra(g<<(e+28*k-(magicOffset-28))) & 0xfffffff

//line mmixarith/mmixarith.w:1471
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

//line mmixarith/mmixarith.w:1208

//line mmixarith/mmixarith.w:1503
	if e > 0x401 {

//line mmixarith/mmixarith.w:1541
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

//line mmixarith/mmixarith.w:1572
			for k = j; gg.compare(&tt) >= open; k++ {
				gg.dec(&tt, 0x10000000)
			}
			s = append(s, byte((j+1+k)>>1)) // the middle digit

//line mmixarith/mmixarith.w:1566
		}

//line mmixarith/mmixarith.w:1505
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

//line mmixarith/mmixarith.w:1209

//line mmixarith/mmixarith.w:1596
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

//line mmixarith/mmixarith.w:1210
	return sb.String()
}

//line mmixarith/mmixarith.w:1351
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

//line mmixarith/mmixarith.w:1372
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

//line mmixarith/mmixarith.w:1400
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

//line mmixarith/mmixarith.w:1430
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

//line mmixarith/mmixarith.w:1424
}

//line mmixarith/mmixarith.w:1668
func ScanConst(s string) (val Octa, next int, kind ConstKind) {

//line mmixarith/mmixarith.w:1705
	var q int     // where we put the next digit in |buf|
	var decPt int // position of decimal point in |buf|; $-1$ if none

//line mmixarith/mmixarith.w:1803
	var buf [785]byte // where we put significant input digits
	copy(buf[:], "00000000")
	var exp int   // scanned exponent; later used for raw binary exponent
	var zeros int // leading zeros removed after decimal point

//line mmixarith/mmixarith.w:1909
	var ff, tt bignum

//line mmixarith/mmixarith.w:1670
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

//line mmixarith/mmixarith.w:1740
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

//line mmixarith/mmixarith.w:1776
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

//line mmixarith/mmixarith.w:1759
		}
		next = p
		exp = 0
		if s[p] == 'e' && !NaN {

//line mmixarith/mmixarith.w:1816
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

//line mmixarith/mmixarith.w:1764
		}
		if decPt < 0 {
			if sign == '-' {
				val = -val
			}
			return val, next, DecimalConst
		}

//line mmixarith/mmixarith.w:1862
		x := 341 + zeros - decPt - exp
		switch {
		case q == buf0 || x >= 1413:
			exp = -99999 // make it zero
		case x < 10:
			exp = 99999 // make it infinity
		default:

//line mmixarith/mmixarith.w:1880
			ff.a = x / 9
			for i := q; i < q+8; i++ {
				buf[i] = '0' // pad with trailing zeros
			}
			q = q - 1 - (q+341+zeros-decPt-exp)%9 // compute stopping place in |buf|
			i, k := buf0-x%9, ff.a
			for ; i <= q && k <= 156; i, k = i+9, k+1 {

//line mmixarith/mmixarith.w:1902
				d := Tetra(buf[i] - '0')
				for j := i + 1; j < i+9; j++ {
					d = 10*d + Tetra(buf[j]-'0')
				}
				ff.dat[k] = d

//line mmixarith/mmixarith.w:1888
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

//line mmixarith/mmixarith.w:1870

//line mmixarith/mmixarith.w:1950
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

//line mmixarith/mmixarith.w:1871
		}

//line mmixarith/mmixarith.w:1684
	case NaN:

//line mmixarith/mmixarith.w:1712
		next = p
		val, exp = 0x60000000000000, 0x3fe

//line mmixarith/mmixarith.w:1686
	case strings.HasPrefix(s[p:], "Inf"):

//line mmixarith/mmixarith.w:1718
		next = p + 3
		exp = 99999

//line mmixarith/mmixarith.w:1688
	default:
		return 0, 0, NoConst
	}

//line mmixarith/mmixarith.w:2000
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

//line mmixarith/mmixarith.w:1692
	return val, next, FloatConst
}

//line mmixarith/mmixarith.w:1698
func isDigit(c byte) bool { return '0' <= c && c <= '9' }

//line mmixarith/mmixarith.w:1915
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

//line mmixarith/mmixarith.w:2025
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

//line mmixarith/mmixarith.w:2058
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

//line mmixarith/mmixarith.w:2084
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

//line mmixarith/mmixarith.w:2110
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

//line mmixarith/mmixarith.w:2097
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

//line mmixarith/mmixarith.w:2071
}

//line mmixarith/mmixarith.w:2137
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

//line mmixarith/mmixarith.w:2154
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

//line mmixarith/mmixarith.w:2151
}

//line mmixarith/mmixarith.w:2180
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

//line mmixarith/mmixarith.w:2211
		var t Tetra
		t, exc = sfpack(z, e, s, r)
		_, z, e, s = sfunpack(t)

//line mmixarith/mmixarith.w:2200
	}
	x, ex := fpack(z, e, s, r)
	return x, exc | ex
}

//line mmixarith/mmixarith.w:2218
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

//line mmixarith/mmixarith.w:2263
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

//line mmixarith/mmixarith.w:2235
		}
	}
	if zs {
		x |= SignBit
	}
	return
}

//line mmixarith/mmixarith.w:2297
func FRemStep(y, z Octa, delta int) (x Octa, exc int) {
	yt, yf, ye, ys := funpack(y)
	zt, zf, ze, _ := funpack(z)
	switch 4*yt + zt {

//line mmixarith/mmixarith.w:803
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

//line mmixarith/mmixarith.w:2302
	case 4*zro + zro, 4*num + zro, 4*inf + zro, 4*inf + num, 4*inf + inf:
		x = StandardNaN
		exc |= IBit
	case 4*zro + num, 4*zro + inf, 4*num + inf:
		return y, exc
	case 4*num + num:

//line mmixarith/mmixarith.w:2331
		odd := false // becomes true if we've subtracted an odd multiple of~$z$ from $y$
		zero, complement := false, false
		thresh := max(ye-delta, ze)
		for ye >= thresh {

//line mmixarith/mmixarith.w:2346
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

//line mmixarith/mmixarith.w:2336
		}
		if !zero {

//line mmixarith/mmixarith.w:2377
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

//line mmixarith/mmixarith.w:2339
		}

//line mmixarith/mmixarith.w:2309
	}
	if ys {
		x |= SignBit
	}
	return
}
