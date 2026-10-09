//line mmixarith.w:2417
package mmixarith

import (
	"math"
	"math/big"
	"math/bits"
	"math/rand/v2"
	"strconv"
	"strings"
	"testing"
)

//line mmixarith.w:2432
func TestScanConstExamples(t *testing.T) {
	for _, c := range []struct {
		in   string
		val  Octa
		next int
		kind ConstKind
	}{
		{"-3.", 0xc008000000000000, 3, FloatConst},
		{"1e3", 0x408f400000000000, 3, FloatConst},
		{"1000.", 0x408f400000000000, 5, FloatConst},
		{"1000", 1000, 4, DecimalConst},
		{"NaN", StandardNaN, 3, FloatConst},
		{"+NaN.5", StandardNaN, 6, FloatConst},
		{"NaN.999999999999999999999", 0x7fffffffffffffff, 25, FloatConst},
		{"NaN.0", 0x7ff0000000000001, 5, FloatConst},
		{"9e+9999999999999999", InfOcta, 19, FloatConst},
		{"-00.0e9999999", SignBit, 13, FloatConst},
		{"1e", 1, 1, DecimalConst},
		{"-Inf", InfOcta | SignBit, 4, FloatConst},
		{"x", 0, 0, NoConst},
		{"18446744073709551617", 1, 20, DecimalConst}, // $2^{64}+1$
		{".64352139e333", InfOcta, 13, FloatConst},    // the original \CEE/ crashes here
	} {
		v, n, k := ScanConst(c.in)
		if v != c.val || n != c.next || k != c.kind {
			t.Errorf("ScanConst(%q) = %#x, %d, %d; 원함 %#x, %d, %d",
				c.in, v, n, k, c.val, c.next, c.kind)
		}
	}
}

//line mmixarith.w:2467
func TestFloatStringExamples(t *testing.T) {
	for _, c := range []struct {
		in  Octa
		out string
	}{
		{0x44ada56a4b0835bf, "6.9999999999999995e22"},
		{0x44ada56a4b0835c0, "7e22"},
		{0x7ff0000000000001, "NaN.0000000000000002"},
		{StandardNaN, "NaN"},
		{InfOcta | SignBit, "-Inf"},
		{SignBit, "-0."},
		{0x4072c00000000000, "300."},
		{0x3f9eb851eb851eb8, ".03"},
		{0x3fb999999999999a, ".1"},
		{0x3ff0000000000000, "1."},
	} {
		if s := FloatString(c.in); s != c.out {
			t.Errorf("FloatString(%#x) = %q; 원함 %q", c.in, s, c.out)
		}
	}
}

//line mmixarith.w:2495
func TestBorderline(t *testing.T) {
	n := new(big.Int).Lsh(big.NewInt(1), 53)
	n.Add(n, big.NewInt(1))
	n.Mul(n, new(big.Int).Exp(big.NewInt(5), big.NewInt(1075), nil))
	digits := n.String()
	if len(digits) <= 750 {
		t.Fatalf("유효 숫자가 %d개뿐이다", len(digits))
	}
	frac := "." + strings.Repeat("0", 1075-len(digits))
	bumped := digits[:len(digits)-1] + string(digits[len(digits)-1]+1)
	for _, c := range []struct {
		in   string
		want Octa
	}{
		{frac + digits, 0x0010000000000000},
		{frac + bumped, 0x0010000000000001},
		{frac + digits + "0000001", 0x0010000000000001},
	} {
		if v, _, _ := ScanConst(c.in); v != c.want {
			t.Errorf("경계값: %#x; 원함 %#x", v, c.want)
		}
	}
}

//line mmixarith.w:2524
func TestArithExamples(t *testing.T) {
	q, r := Div(0, 0x7fff800100000000, 0x800080020005)
	if q != 0x7fff800100000000/0x800080020005 || r != 0x7fff800100000000%0x800080020005 {
		t.Errorf("Div 보정 예: %#x, %#x", q, r)
	}
	if q, r := Div(5, 7, 5); q != 5 || r != 7 {
		t.Errorf("x>=z일 때 자명한 답이 아니다: %d, %d", q, r)
	}
	if _, _, ov := SignedDiv(SignBit, NegOne); !ov {
		t.Error("-2^63/-1은 넘쳐야 한다")
	}
	if _, ov := SignedMult(1<<32, 1<<31); !ov {
		t.Error("2^63은 부호 있는 곱으로 넘쳐야 한다")
	}
	if _, ov := SignedMult(1<<32, 0xffffffff80000000); ov {
		t.Error("-2^63은 부호 있는 곱으로 넘치지 않는다")
	}
	one, three := Octa(0x3ff0000000000000), Octa(0x4008000000000000)
	if _, e := FDivide(one, 0, RoundNear); e != ZBit {
		t.Errorf("1/0의 예외 %#x", e)
	}
	if _, e := FDivide(one, three, RoundNear); e != XBit {
		t.Errorf("1/3의 예외 %#x", e)
	}
	if _, e := FPlus(InfOcta, InfOcta|SignBit, RoundNear); e != IBit {
		t.Errorf("inf-inf의 예외 %#x", e)
	}

//line mmixarith.w:2555
	if z, e := StoreSF(0x3800000000000000, RoundNear); z != 0x00400000 || e != UBit {
		t.Errorf("StoreSF(2^-127) = %#x, %#x", z, e)
	}
	if x, _ := FPlus(0xc3f0000000000000, 0x409cf4b4d61b9dbe, RoundNear); x != 0xc3efffffffffffff {
		t.Errorf("-2^64+1853.17... = %#x", x)
	}

//line mmixarith.w:2552
}

//line mmixarith.w:2567
var specials = [...]Octa{0, InfOcta, StandardNaN, 0x7ff0000000000001, 1,
	0x000fffffffffffff, 0x0010000000000000, 0x7fefffffffffffff,
	0x3ff0000000000000, 0x43e0000000000000, 0x43f0000000000000}

func randOcta(r *rand.Rand) Octa {
	switch r.IntN(8) {
	case 0:
		return specials[r.IntN(len(specials))] | Octa(r.IntN(2))<<63
	case 1:
		return r.Uint64() & 0x800fffffffffffff // subnormal
	case 2:
		return r.Uint64()&0x800fffffffffffff | Octa(0x3e0+r.IntN(64))<<52
	case 3:
		return r.Uint64()&0xfff0000000000000 | r.Uint64()&0xff // near an integer
	default:
		return r.Uint64()
	}
}

func randPair(r *rand.Rand) (Octa, Octa) {
	y := randOcta(r)
	if r.IntN(2) == 0 {
		return y, randOcta(r)
	}
	e := int(y>>52&0x7ff) + r.IntN(120) - 60
	e = min(max(e, 0), 0x7fe)
	return y, r.Uint64()&0x800fffffffffffff | Octa(e)<<52
}

//line mmixarith.w:2602
func same(got Octa, want float64) bool {
	g := math.Float64frombits(got)
	return got == math.Float64bits(want) || (g != g && want != want)
}

func TestAgainstHardware(t *testing.T) {
	rng := rand.New(rand.NewPCG(1999, 2026))
	f := math.Float64frombits
	for range 300000 {
		y, z := randPair(rng)

//line mmixarith.w:2619
		if x, _ := FPlus(y, z, RoundNear); !same(x, f(y)+f(z)) {
			t.Fatalf("FPlus(%#x, %#x) = %#x", y, z, x)
		}
		if x, _ := FMult(y, z, RoundNear); !same(x, f(y)*f(z)) {
			t.Fatalf("FMult(%#x, %#x) = %#x", y, z, x)
		}
		if x, _ := FDivide(y, z, RoundNear); !same(x, f(y)/f(z)) {
			t.Fatalf("FDivide(%#x, %#x) = %#x", y, z, x)
		}
		if x, _ := FRoot(z, RoundNear); !same(x, math.Sqrt(f(z))) {
			t.Fatalf("FRoot(%#x) = %#x", z, x)
		}
		if x, _ := FRemStep(y, z, 2500); !same(x, math.Remainder(f(y), f(z))) {
			t.Fatalf("FRemStep(%#x, %#x) = %#x", y, z, x)
		}
		want := 2 // unordered
		switch fy, fz := f(y), f(z); {
		case fy < fz:
			want = -1
		case fy > fz:
			want = 1
		case fy == fz:
			want = 0
		}
		if c := FComp(y, z); c != want {
			t.Fatalf("FComp(%#x, %#x) = %d", y, z, c)
		}

//line mmixarith.w:2613

//line mmixarith.w:2657
		for mode, g := range integerizers {
			if x, _ := FIntegerize(z, mode); !same(x, g(f(z))) {
				t.Fatalf("FIntegerize(%#x, %d) = %#x", z, mode, x)
			}
		}
		if w := math.RoundToEven(f(z)); math.Abs(w) < 1<<63 {
			if x, _ := FixIt(z, RoundNear); x != Octa(int64(w)) {
				t.Fatalf("FixIt(%#x) = %#x", z, x)
			}
		}
		if x, _ := FloatIt(y, RoundNear, false, false); !same(x, float64(int64(y))) {
			t.Fatalf("FloatIt(%#x) = %#x", y, x)
		}
		if x, _ := FloatIt(y, RoundNear, true, false); !same(x, float64(y)) {
			t.Fatalf("FloatIt(%#x, 부호 없음) = %#x", y, x)
		}
		if x, _ := FloatIt(y, RoundNear, false, true); !same(x, float64(float32(int64(y)))) {
			t.Fatalf("FloatIt(%#x, 짧음) = %#x", y, x)
		}

//line mmixarith.w:2614

//line mmixarith.w:2678
		if s, _ := StoreSF(z, RoundNear); f(z) == f(z) && s != math.Float32bits(float32(f(z))) {
			t.Fatalf("StoreSF(%#x) = %#x", z, s)
		}
		if w := Tetra(y); math.Float32frombits(w) == math.Float32frombits(w) &&
			LoadSF(w) != math.Float64bits(float64(math.Float32frombits(w))) {
			t.Fatalf("LoadSF(%#x) = %#x", w, LoadSF(w))
		}

//line mmixarith.w:2615
	}
}

//line mmixarith.w:2651
var integerizers = map[Round]func(float64) float64{
	RoundOff: math.Trunc, RoundUp: math.Ceil,
	RoundDown: math.Floor, RoundNear: math.RoundToEven,
}

//line mmixarith.w:2692
func sigDigits(s string) int {
	if i := strings.IndexAny(s, "e"); i >= 0 {
		s = s[:i]
	}
	s = strings.Trim(strings.Map(func(c rune) rune {
		if '0' <= c && c <= '9' {
			return c
		}
		return -1
	}, s), "0")
	return len(s)
}

func TestFloatStringRoundTrip(t *testing.T) {
	rng := rand.New(rand.NewPCG(1750, 1999))
	for range 200000 {
		x := randOcta(rng)
		s := FloatString(x)
		if v, n, k := ScanConst(s); v != x || n != len(s) || k != FloatConst {
			t.Fatalf("%#x -> %q -> %#x", x, s, v)
		}
		fx := math.Float64frombits(x)
		if fx == fx && !math.IsInf(fx, 0) && fx != 0 {
			if a, b := sigDigits(s), sigDigits(strconv.FormatFloat(fx, 'e', -1, 64)); a != b {
				t.Fatalf("%#x -> %q: 유효 숫자 %d개, strconv는 %d개", x, s, a, b)
			}
		}
	}
}

//line mmixarith.w:2723
func TestScanConstAgainstStrconv(t *testing.T) {
	rng := rand.New(rand.NewPCG(308, 324))
	for range 200000 {
		var sb strings.Builder
		for range 1 + rng.IntN(25) {
			sb.WriteByte(byte('0' + rng.IntN(10)))
		}
		s := sb.String()
		i := rng.IntN(len(s) + 1)
		s = s[:i] + "." + s[i:] + "e" + strconv.Itoa(rng.IntN(700)-350)
		if s[0] == '.' && (len(s) == 1 || !isDigit(s[1])) {
			continue
		}
		v, _, _ := ScanConst(s)
		w, _ := strconv.ParseFloat(s, 64)
		if v != math.Float64bits(w) {
			t.Fatalf("ScanConst(%q) = %#x; strconv는 %#x", s, v, math.Float64bits(w))
		}
	}
}

//line mmixarith.w:2749
func TestIntegerOps(t *testing.T) {
	rng := rand.New(rand.NewPCG(64, 32))
	for range 300000 {
		y, z := randOcta(rng), randOcta(rng)
		if rng.IntN(4) == 0 {
			z >>= rng.IntN(64)
		}

//line mmixarith.w:2763
		p := new(big.Int).Mul(big.NewInt(int64(y)), big.NewInt(int64(z)))
		if x, ov := SignedMult(y, z); x != Octa(int64(y)*int64(z)) || ov != !p.IsInt64() {
			t.Fatalf("SignedMult(%#x, %#x) = %#x, %v", y, z, x, ov)
		}

//line mmixarith.w:2757

//line mmixarith.w:2769
		if z != 0 && !(y == SignBit && z == NegOne) {
			a, b := int64(y), int64(z)
			wq, wr := a/b, a%b
			if wr != 0 && (wr < 0) != (b < 0) {
				wq, wr = wq-1, wr+b
			}
			if q, r, ov := SignedDiv(y, z); q != Octa(wq) || r != Octa(wr) || ov {
				t.Fatalf("SignedDiv(%#x, %#x) = %#x, %#x, %v", y, z, q, r, ov)
			}
		}

//line mmixarith.w:2758

//line mmixarith.w:2781
		var bd, wd, mor, mxor Octa
		for i := 0; i < 64; i += 8 {
			bd |= Octa(max(int(y>>i&0xff)-int(z>>i&0xff), 0)) << i
			for k := range 8 {
				if z>>(i+k)&1 != 0 {
					mor |= (y >> (8 * k) & 0xff) << i
					mxor ^= (y >> (8 * k) & 0xff) << i
				}
			}
		}
		for i := 0; i < 64; i += 16 {
			wd |= Octa(max(int(y>>i&0xffff)-int(z>>i&0xffff), 0)) << i
		}
		if ByteDiff(y, z) != bd || WydeDiff(y, z) != wd ||
			BoolMult(y, z, false) != mor || BoolMult(y, z, true) != mxor ||
			bits.OnesCount64(y&^z) != bits.OnesCount64(y)-bits.OnesCount64(y&z) {
			t.Fatalf("비트 연산 (%#x, %#x)", y, z)
		}

//line mmixarith.w:2759
	}
}
