//line mmixal.w:47
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/sjnam/mmix/mmixarith"
)

//line mmixal.w:794
type (
	Tetra = mmixarith.Tetra
	Octa  = mmixarith.Octa

//line mmixal.w:797
)

//line mmixal.w:834
type assembler struct {

//line mmixal.w:839
	buffer      []byte // 현재 줄의 날 입력
	bufPtr      int    // |buffer| 안의 현재 위치
	labField    []byte // 현재 명령의 레이블 필드 사본
	opField     []byte // 현재 명령의 연산 코드 필드 사본
	operandList []byte // 현재 명령의 피연산자 필드 사본(널 문자로 끝난다)

//line mmixal.w:914
	curFile          int  // |filename|에서 현재 파일의 색인
	lineNo           int  // 파일 안의 현재 위치
	lineListed       bool // 버퍼 내용을 목록에 적었는가?
	longWarningGiven bool // \.{-b}에 대한 힌트를 주었는가?

//line mmixal.w:923
	filename []string // 줄 지시문에 나온 것까지 포함한 소스 파일 이름들

//line mmixal.w:1011
	curLoc      Octa    // 어셈블된 출력의 현재 위치
	listingLoc  Octa    // 목록의 현재 위치
	holdBuf     [4]byte // 어셈블된 바이트들
	heldBits    byte    // |holdBuf|의 어느 바이트가 살아 있는가?
	listingBits byte    // 그 가운데 어느 것을 아직 목록에 적지 않았는가?
	specMode    bool    // \.{BSPEC}과 \.{ESPEC} 사이에 있는가?
	specModeLoc Tetra   // 현재 특수 출력의 바이트 수

//line mmixal.w:1146
	errCount int // 찾아낸 오류의 수

//line mmixal.w:1193
	mmoBuf [4]byte // 출력을 기다리는 테트라바이트
	mmoPtr int     // 기호표를 출력하면서 센 바이트 수

//line mmixal.w:1292
	mmoCurLoc      Octa      // 목적 파일의 현재 위치
	mmoLineNo      int       // 지금까지 \.{mmo} 출력의 현재 줄 번호
	mmoCurFile     int       // 지금까지 \.{mmo} 출력의 현재 파일 색인
	filenamePassed [256]bool // 파일 이름을 출력에 기록했는가?

//line mmixal.w:1374
	trieRoot  *trieNode // 트라이의 뿌리
	opRoot    *trieNode // 연산 코드들의 부분 트라이의 뿌리
	curPrefix *trieNode // 한정되지 않은 기호들의 부분 트라이의 뿌리

//line mmixal.w:1473
	serialNumber int

//line mmixal.w:1936
	symBuf []byte // 가운데 가지를 따라 모은 기호의 문자들

//line mmixal.w:2054
	opStack  []stackOp // 처리를 기다리는 연산자들의 스택
	opPtr    int       // |opStack|에 있는 항목의 수
	valStack []valNode // 처리를 기다리는 피연산자들의 스택
	valPtr   int       // |valStack|에 있는 항목의 수
	rtOp     stackOp   // 새로 읽은 연산자

//line mmixal.w:2239
	forwardLocalHost, backwardLocalHost [10]trieNode
	forwardLocal, backwardLocal         [10]symNode

//line mmixal.w:2676
	opcode Tetra // \MMIX\ 연산이나 \MMIXAL\ 유사 연산의 수로 된 코드
	opBits Tetra // 연산자의 특별한 성질을 나타내는 플래그들

//line mmixal.w:3040
	z, y, x, yz, xyz Tetra // 어셈블할 조각들
	futureBits       int   // 앞선 참조가 있는 자리들

//line mmixal.w:3386
	gregVal [256]Octa // 전역 레지스터의 처음 값들

//line mmixal.w:3585
	stderr      io.Writer     // 오류 메시지를 쓰는 곳
	srcFileName string        // \MMIXAL\ 입력 파일의 이름
	objFileName string        // 이진 출력 파일의 이름
	listingName string        // 목록 파일의 이름(있다면)
	srcFile     *bufio.Reader // 입력 파일
	objFile     *bufio.Writer // 이진 출력 파일
	listingFile *bufio.Writer // 목록 파일; 없으면 |nil|
	expanding   bool          // 기준 주소가 모자랄 때 명령을 펼치는가?
	bufSize     int           // 입력 한 줄의 최대 문자 수

//line mmixal.w:3628
	greg    int // 전역 레지스터 할당기
	curGreg int // 방금 할당한 전역 레지스터
	lreg    int // 지역 레지스터 할당기

//line mmixal.w:836
}

//line mmixal.w:1103
type bypassSignal struct{} // 현재 명령의 나머지를 건너뛰라는 신호
type fatalSignal struct{}  // 어셈블을 끝내라는 신호

//line mmixal.w:1363
type trieNode struct {
	ch               uint16    // 여기 저장된 (와이드일 수도 있는) 문자
	left, mid, right *trieNode // 삼진 트라이의 아래쪽으로
	sym              *symNode  // 기호의 등가
}

//line mmixal.w:1438
type symNode struct {
	serial int      // 기호의 일련번호; 고침 마디에서는 종류 번호
	link   *symNode // |defined| 따위의 상태, 또는 고침 마디로의 연결
	equiv  Octa     // 등가
}

//line mmixal.w:1522
type opSpec struct {
	name string // 기호로 된 연산 코드
	code Tetra  // 수로 된 연산 코드
	bits Tetra  // 피연산자를 다루는 방법
}

//line mmixal.w:1688
type predefSpec struct {
	name string
	h, l Tetra
}

//line mmixal.w:1999
type stackOp int

//line mmixal.w:2000
type prec int

//line mmixal.w:2001
type stat int

//line mmixal.w:2002
type valNode struct {
	equiv  Octa      // 현재 값
	link   *trieNode // 기호의 트라이 참조
	status stat      // |pure|, |regVal|, |undefined|
}

//line mmixal.w:568
const mm = 0x98 // 적재기 명령의 탈출 코드

//line mmixal.w:750
const (
	lopQuote = 0x0 // 인용 lopcode
	lopLoc   = 0x1 // 위치 lopcode
	lopSkip  = 0x2 // 건너뛰기 lopcode
	lopFixo  = 0x3 // 옥타바이트 고치기 lopcode
	lopFixr  = 0x4 // 상대 주소 고치기 lopcode
	lopFixrx = 0x5 // 확장된 상대 주소 고치기 lopcode
	lopFile  = 0x6 // 파일 이름 lopcode
	lopLine  = 0x7 // 파일 위치 lopcode
	lopSpec  = 0x8 // 특수 고리(hook) lopcode
	lopPre   = 0x9 // 서문 lopcode
	lopPost  = 0xa // 후기 lopcode
	lopStab  = 0xb // 기호표 lopcode
	lopEnd   = 0xc // 모든 것을 끝내는 lopcode
)

//line mmixal.w:970
const filenameMax = 1024

//line mmixal.w:1452
const (
	fixO   = 0 // 옥타바이트 고침의 |serial| 코드
	fixYZ  = 1 // 상대 주소 고침의 |serial| 코드
	fixXYZ = 2 // \.{JMP} 고침의 |serial| 코드
)

//line mmixal.w:1495
const (
	relAddrBit  = 0x1      // YZ나 XYZ가 상대 주소인가?
	immedBit    = 0x2      // Z나 YZ가 레지스터가 아니면 즉치 연산 코드로 할까?
	zarBit      = 0x4      // Z의 레지스터 상태를 무시할까?
	zrBit       = 0x8      // Z는 레지스터여야 하는가?
	yarBit      = 0x10     // Y의 레지스터 상태를 무시할까?
	yrBit       = 0x20     // Y는 레지스터여야 하는가?
	xarBit      = 0x40     // X의 레지스터 상태를 무시할까?
	xrBit       = 0x80     // X는 레지스터여야 하는가?
	yzarBit     = 0x100    // YZ의 레지스터 상태를 무시할까?
	yzrBit      = 0x200    // YZ는 레지스터여야 하는가?
	xyzarBit    = 0x400    // XYZ의 레지스터 상태를 무시할까?
	xyzrBit     = 0x800    // XYZ는 레지스터여야 하는가?
	oneArgBit   = 0x1000   // 피연산자가 없거나 하나여도 되는가?
	twoArgBit   = 0x2000   // 피연산자가 정확히 둘이어도 되는가?
	threeArgBit = 0x4000   // 피연산자가 정확히 셋이어도 되는가?
	manyArgBit  = 0x8000   // 피연산자가 셋보다 많아도 되는가?
	alignBits   = 0x30000  // 얼마나 맞출까: 바이트, 와이드, 테트라, 옥타?
	noLabelBit  = 0x40000  // 레이블이 비어 있어야 하는가?
	memBit      = 0x80000  // YZ는 메모리 참조여야 하는가?
	specBit     = 0x100000 // 이 연산 코드를 \.{SPEC} 모드에서 쓸 수 있는가?
)

//line mmixal.w:1529
const (
	SET = 0x100 + iota
	IS
	LOC
	PREFIX
	BSPEC
	ESPEC
	GREG
	LOCAL
	BYTE
	WYDE
	TETRA
	OCTA

//line mmixal.w:1542
)

//line mmixal.w:2009
const (
	negate stackOp = iota
	serialize
	complement
	registerize
	innerLP
	plus
	minus
	times
	over
	frac
	mod
	shl
	shr
	and
	or
	xor
	outerLP
	outerRP
	innerRP

//line mmixal.w:2029
)

const (
	zero prec = iota
	weak
	strong
	unary

//line mmixal.w:2036
)

const (
	pure stat = iota
	regVal
	undefined

//line mmixal.w:2042
)

//line mmixal.w:3254
const (
	SETH = 0xe0
	SETL = 0xe3
	ORH  = 0xe8
	ORL  = 0xeb

//line mmixal.w:3259
)

//line mmixal.w:1445
var (
	defined    = new(symNode) // 옥타바이트 등가를 뜻하는 코드
	register   = new(symNode) // 레지스터 번호 등가를 뜻하는 코드
	predefined = new(symNode) // 아직 쓰이지 않은 미리 정의된 등가를 뜻하는 코드
)

//line mmixal.w:1558
var opInitTable = []opSpec{

//line mmixal.w:1563
	{"TRAP", 0x00, 0x27554}, {"FCMP", 0x01, 0x240a8}, {"FUN", 0x02, 0x240a8}, {"FEQL", 0x03, 0x240a8},

	{"FADD", 0x04, 0x240a8}, {"FIX", 0x05, 0x26288}, {"FSUB", 0x06, 0x240a8}, {"FIXU", 0x07, 0x26288},

	{"FLOT", 0x08, 0x26282}, {"FLOTU", 0x0a, 0x26282}, {"SFLOT", 0x0c, 0x26282}, {"SFLOTU", 0x0e, 0x26282},

	{"FMUL", 0x10, 0x240a8}, {"FCMPE", 0x11, 0x240a8}, {"FUNE", 0x12, 0x240a8}, {"FEQLE", 0x13, 0x240a8},

	{"FDIV", 0x14, 0x240a8}, {"FSQRT", 0x15, 0x26288}, {"FREM", 0x16, 0x240a8}, {"FINT", 0x17, 0x26288},

	{"MUL", 0x18, 0x240a2}, {"MULU", 0x1a, 0x240a2}, {"DIV", 0x1c, 0x240a2}, {"DIVU", 0x1e, 0x240a2},

	{"ADD", 0x20, 0x240a2}, {"ADDU", 0x22, 0x240a2}, {"SUB", 0x24, 0x240a2}, {"SUBU", 0x26, 0x240a2},

	{"2ADDU", 0x28, 0x240a2}, {"4ADDU", 0x2a, 0x240a2}, {"8ADDU", 0x2c, 0x240a2}, {"16ADDU", 0x2e, 0x240a2},

//line mmixal.w:1581
	{"CMP", 0x30, 0x240a2}, {"CMPU", 0x32, 0x240a2}, {"NEG", 0x34, 0x26082}, {"NEGU", 0x36, 0x26082},

	{"SL", 0x38, 0x240a2}, {"SLU", 0x3a, 0x240a2}, {"SR", 0x3c, 0x240a2}, {"SRU", 0x3e, 0x240a2},

	{"BN", 0x40, 0x22081}, {"BZ", 0x42, 0x22081}, {"BP", 0x44, 0x22081}, {"BOD", 0x46, 0x22081},

	{"BNN", 0x48, 0x22081}, {"BNZ", 0x4a, 0x22081}, {"BNP", 0x4c, 0x22081}, {"BEV", 0x4e, 0x22081},

	{"PBN", 0x50, 0x22081}, {"PBZ", 0x52, 0x22081}, {"PBP", 0x54, 0x22081}, {"PBOD", 0x56, 0x22081},

	{"PBNN", 0x58, 0x22081}, {"PBNZ", 0x5a, 0x22081}, {"PBNP", 0x5c, 0x22081}, {"PBEV", 0x5e, 0x22081},

	{"CSN", 0x60, 0x240a2}, {"CSZ", 0x62, 0x240a2}, {"CSP", 0x64, 0x240a2}, {"CSOD", 0x66, 0x240a2},

	{"CSNN", 0x68, 0x240a2}, {"CSNZ", 0x6a, 0x240a2}, {"CSNP", 0x6c, 0x240a2}, {"CSEV", 0x6e, 0x240a2},

//line mmixal.w:1599
	{"ZSN", 0x70, 0x240a2}, {"ZSZ", 0x72, 0x240a2}, {"ZSP", 0x74, 0x240a2}, {"ZSOD", 0x76, 0x240a2},

	{"ZSNN", 0x78, 0x240a2}, {"ZSNZ", 0x7a, 0x240a2}, {"ZSNP", 0x7c, 0x240a2}, {"ZSEV", 0x7e, 0x240a2},

	{"LDB", 0x80, 0xa60a2}, {"LDBU", 0x82, 0xa60a2}, {"LDW", 0x84, 0xa60a2}, {"LDWU", 0x86, 0xa60a2},

	{"LDT", 0x88, 0xa60a2}, {"LDTU", 0x8a, 0xa60a2}, {"LDO", 0x8c, 0xa60a2}, {"LDOU", 0x8e, 0xa60a2},

	{"LDSF", 0x90, 0xa60a2}, {"LDHT", 0x92, 0xa60a2}, {"CSWAP", 0x94, 0xa60a2}, {"LDUNC", 0x96, 0xa60a2},

	{"LDVTS", 0x98, 0xa60a2}, {"PRELD", 0x9a, 0xa6022}, {"PREGO", 0x9c, 0xa6022}, {"GO", 0x9e, 0xa60a2},

	{"STB", 0xa0, 0xa60a2}, {"STBU", 0xa2, 0xa60a2}, {"STW", 0xa4, 0xa60a2}, {"STWU", 0xa6, 0xa60a2},

	{"STT", 0xa8, 0xa60a2}, {"STTU", 0xaa, 0xa60a2}, {"STO", 0xac, 0xa60a2}, {"STOU", 0xae, 0xa60a2},

//line mmixal.w:1617
	{"STSF", 0xb0, 0xa60a2}, {"STHT", 0xb2, 0xa60a2}, {"STCO", 0xb4, 0xa6022}, {"STUNC", 0xb6, 0xa60a2},

	{"SYNCD", 0xb8, 0xa6022}, {"PREST", 0xba, 0xa6022}, {"SYNCID", 0xbc, 0xa6022}, {"PUSHGO", 0xbe, 0xa6062},

	{"OR", 0xc0, 0x240a2}, {"ORN", 0xc2, 0x240a2}, {"NOR", 0xc4, 0x240a2}, {"XOR", 0xc6, 0x240a2},

	{"AND", 0xc8, 0x240a2}, {"ANDN", 0xca, 0x240a2}, {"NAND", 0xcc, 0x240a2}, {"NXOR", 0xce, 0x240a2},

	{"BDIF", 0xd0, 0x240a2}, {"WDIF", 0xd2, 0x240a2}, {"TDIF", 0xd4, 0x240a2}, {"ODIF", 0xd6, 0x240a2},

	{"MUX", 0xd8, 0x240a2}, {"SADD", 0xda, 0x240a2}, {"MOR", 0xdc, 0x240a2}, {"MXOR", 0xde, 0x240a2},

	{"SETH", 0xe0, 0x22080}, {"SETMH", 0xe1, 0x22080}, {"SETML", 0xe2, 0x22080}, {"SETL", 0xe3, 0x22080},

	{"INCH", 0xe4, 0x22080}, {"INCMH", 0xe5, 0x22080}, {"INCML", 0xe6, 0x22080}, {"INCL", 0xe7, 0x22080},

//line mmixal.w:1635
	{"ORH", 0xe8, 0x22080}, {"ORMH", 0xe9, 0x22080}, {"ORML", 0xea, 0x22080}, {"ORL", 0xeb, 0x22080},

	{"ANDNH", 0xec, 0x22080}, {"ANDNMH", 0xed, 0x22080}, {"ANDNML", 0xee, 0x22080}, {"ANDNL", 0xef, 0x22080},

	{"JMP", 0xf0, 0x21001}, {"PUSHJ", 0xf2, 0x22041}, {"GETA", 0xf4, 0x22081}, {"PUT", 0xf6, 0x22002},

	{"POP", 0xf8, 0x23000}, {"RESUME", 0xf9, 0x21000}, {"SAVE", 0xfa, 0x22080}, {"UNSAVE", 0xfb, 0x23a00},

	{"SYNC", 0xfc, 0x21000}, {"SWYM", 0xfd, 0x27554}, {"GET", 0xfe, 0x22080}, {"TRIP", 0xff, 0x27554},

	{"SET", SET, 0x22180}, {"LDA", 0x22, 0xa60a2},

	{"IS", IS, 0x101400}, {"LOC", LOC, 0x1400}, {"PREFIX", PREFIX, 0x141000},

	{"BYTE", BYTE, 0x10f000}, {"WYDE", WYDE, 0x11f000}, {"TETRA", TETRA, 0x12f000}, {"OCTA", OCTA, 0x13f000},

	{"BSPEC", BSPEC, 0x41400}, {"ESPEC", ESPEC, 0x141000},

	{"GREG", GREG, 0x101000}, {"LOCAL", LOCAL, 0x141800},

//line mmixal.w:1560
}

//line mmixal.w:1682
var specialName = [32]string{"rB", "rD", "rE", "rH", "rJ", "rM", "rR", "rBB",
	"rC", "rN", "rO", "rS", "rI", "rT", "rTT", "rK", "rQ", "rU", "rV", "rG", "rL",
	"rA", "rF", "rP", "rW", "rX", "rY", "rZ", "rWW", "rXX", "rYY", "rZZ"}

//line mmixal.w:1697
var predefs = []predefSpec{
	{"ROUND_CURRENT", 0, 0}, {"ROUND_OFF", 0, 1}, {"ROUND_UP", 0, 2},
	{"ROUND_DOWN", 0, 3}, {"ROUND_NEAR", 0, 4},

//line mmixal.w:1702
	{"Inf", 0x7ff00000, 0},

	{"Data_Segment", 0x20000000, 0}, {"Pool_Segment", 0x40000000, 0},
	{"Stack_Segment", 0x60000000, 0},

//line mmixal.w:1708
	{"D_BIT", 0, 0x80}, {"V_BIT", 0, 0x40}, {"W_BIT", 0, 0x20}, {"I_BIT", 0, 0x10},
	{"O_BIT", 0, 0x08}, {"U_BIT", 0, 0x04}, {"Z_BIT", 0, 0x02}, {"X_BIT", 0, 0x01},

//line mmixal.w:1712
	{"D_Handler", 0, 0x10}, {"V_Handler", 0, 0x20}, {"W_Handler", 0, 0x30},
	{"I_Handler", 0, 0x40}, {"O_Handler", 0, 0x50}, {"U_Handler", 0, 0x60},
	{"Z_Handler", 0, 0x70}, {"X_Handler", 0, 0x80},

//line mmixal.w:1718
	{"StdIn", 0, 0}, {"StdOut", 0, 1}, {"StdErr", 0, 2},

	{"TextRead", 0, 0}, {"TextWrite", 0, 1}, {"BinaryRead", 0, 2},
	{"BinaryWrite", 0, 3}, {"BinaryReadWrite", 0, 4},

	{"Halt", 0, 0}, {"Fopen", 0, 1}, {"Fclose", 0, 2}, {"Fread", 0, 3},
	{"Fgets", 0, 4}, {"Fgetws", 0, 5}, {"Fwrite", 0, 6}, {"Fputs", 0, 7},
	{"Fputws", 0, 8}, {"Fseek", 0, 9}, {"Ftell", 0, 10},

//line mmixal.w:1728
}

//line mmixal.w:2065
var precedence = [...]prec{unary, unary, unary, unary, zero,
	weak, weak, strong, strong, strong, strong, strong, strong, strong, weak, weak,
	zero, zero, zero}

//line mmixal.w:883
func cstrlen(b []byte) int {
	for i, c := range b {
		if c == 0 {
			return i
		}
	}
	return len(b)
}

func cstr(b []byte) string { return string(b[:cstrlen(b)]) }

//line mmixal.w:984
func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}

//line mmixal.w:987
func isDigit(c byte) bool { return '0' <= c && c <= '9' }

//line mmixal.w:988
func isXDigit(c byte) bool { return isDigit(c) || 'a' <= c && c <= 'f' || 'A' <= c && c <= 'F' }

//line mmixal.w:1001
func (a *assembler) flushListingLine(s string) {
	if a.lineListed {
		fmt.Fprintf(a.listingFile, "\n")
	} else {
		fmt.Fprintf(a.listingFile, "%s%s\n", s, cstr(a.buffer))
		a.lineListed = true
	}
}

//line mmixal.w:1027
func (a *assembler) listingClear() {
	var j, k int
	for k = 0; k < 4; k++ {
		if a.listingBits&(1<<k) != 0 {
			break
		}
	}
	if a.specMode {
		fmt.Fprintf(a.listingFile, "         ")
	} else {

//line mmixal.w:1062
		if (a.curLoc^a.listingLoc)&^0xfff != 0 {
			fmt.Fprintf(a.listingFile, "%016x:", a.curLoc&^3|Octa(k))
			a.flushListingLine("  ")
		}
		a.listingLoc = a.curLoc&^3 | Octa(k)

//line mmixal.w:1038
		fmt.Fprintf(a.listingFile, " ...%03x: ", Tetra(a.listingLoc)&0xffc|Tetra(k))
	}
	for j = 0; j < 4; j++ {
		switch {
		case a.listingBits&(0x10<<j) != 0:
			fmt.Fprintf(a.listingFile, "xx")
		case a.listingBits&(1<<j) != 0:
			fmt.Fprintf(a.listingFile, "%02x", a.holdBuf[j])
		default:
			fmt.Fprintf(a.listingFile, "  ")
		}
	}
	a.flushListingLine("  ")
	a.listingBits = 0
}

//line mmixal.w:1085
func (a *assembler) err(m string) {
	a.reportError(m)
	if m[0] != '*' {
		panic(bypassSignal{})
	}
}

func (a *assembler) derr(format string, args ...any) {
	a.err(fmt.Sprintf(format, args...))
}

func (a *assembler) fatal(format string, args ...any) {
	a.reportError("!" + fmt.Sprintf(format, args...))
}

func ch(c byte) string { return string([]byte{c}) }

//line mmixal.w:1110
func (a *assembler) reportError(message string) {
	name := "(nofile)"
	if a.curFile < len(a.filename) {
		name = a.filename[a.curFile]
	}
	switch message[0] {
	case '*':
		fmt.Fprintf(a.stderr, "\"%s\", line %d warning: %s\n", name, a.lineNo, message[1:])
	case '!':
		fmt.Fprintf(a.stderr, "\"%s\", line %d fatal error: %s\n", name, a.lineNo, message[1:])
	default:
		fmt.Fprintf(a.stderr, "\"%s\", line %d: %s!\n", name, a.lineNo, message)
		a.errCount++
	}
	if a.listingFile != nil {

//line mmixal.w:1133
		if !a.lineListed {
			a.flushListingLine("****************** ")
		}
		switch message[0] {
		case '*':
			fmt.Fprintf(a.listingFile, "************ warning: %s\n", message[1:])
		case '!':
			fmt.Fprintf(a.listingFile, "******** fatal error: %s!\n", message[1:])
		default:
			fmt.Fprintf(a.listingFile, "********** error: %s!\n", message)
		}

//line mmixal.w:1126
	}
	if message[0] == '!' {
		panic(fatalSignal{})
	}
}

//line mmixal.w:1157
func (a *assembler) mmoWrite(buf []byte) {
	if _, err := a.objFile.Write(buf); err != nil {
		a.fatal("Can't write on %s", a.objFileName)

	}
}

//line mmixal.w:1169
func (a *assembler) mmoClear() {
	if a.holdBuf[0] == mm {
		a.mmoWrite([]byte{mm, lopQuote, 0, 1})
	}
	a.mmoWrite(a.holdBuf[:])
	if a.listingFile != nil && a.listingBits != 0 {
		a.listingClear()
	}
	a.heldBits = 0
	a.holdBuf = [4]byte{}
	a.mmoCurLoc = (a.mmoCurLoc + 4) &^ 3
	if a.mmoLineNo != 0 {
		a.mmoLineNo++
	}
}

func (a *assembler) mmoOut() {
	if a.heldBits != 0 {
		a.mmoClear()
	}
	a.mmoWrite(a.mmoBuf[:])
}

//line mmixal.w:1199
func (a *assembler) mmoTetra(t Tetra) {
	a.mmoBuf = [4]byte{byte(t >> 24), byte(t >> 16), byte(t >> 8), byte(t)}
	a.mmoOut()
}

func (a *assembler) mmoByte(b byte) {
	a.mmoBuf[a.mmoPtr&3] = b
	a.mmoPtr++
	if a.mmoPtr&3 == 0 {
		a.mmoOut()
	}
}

func (a *assembler) mmoLop(x, y, z byte) { // 적재기 연산을 출력한다
	a.mmoBuf = [4]byte{mm, x, y, z}
	a.mmoOut()
}

func (a *assembler) mmoLopp(x byte, yz uint16) { // 두 바이트 피연산자를 가진 적재기 연산
	a.mmoBuf = [4]byte{mm, x, byte(yz >> 8), byte(yz)}
	a.mmoOut()
}

//line mmixal.w:1228
func (a *assembler) mmoLoc() {
	if a.heldBits != 0 {
		a.mmoClear()
	}
	o := a.curLoc - a.mmoCurLoc
	if o < 0x10000 {
		if o != 0 {
			a.mmoLopp(lopSkip, uint16(o))
		}
	} else {
		if (a.curLoc>>32)&0xffffff != 0 {
			a.mmoLop(lopLoc, 0, 2)
			a.mmoTetra(Tetra(a.curLoc >> 32))
		} else {
			a.mmoLop(lopLoc, byte(a.curLoc>>56), 1)
		}
		a.mmoTetra(Tetra(a.curLoc))
	}
	a.mmoCurLoc = a.curLoc
}

//line mmixal.w:1253
func (a *assembler) mmoSync() {
	if a.curFile != a.mmoCurFile {
		if a.filenamePassed[a.curFile] {
			a.mmoLop(lopFile, byte(a.curFile), 0)
		} else {

//line mmixal.w:1275
			name := a.filename[a.curFile]
			a.mmoLop(lopFile, byte(a.curFile), byte((len(name)+3)>>2))
			j := 0
			for i := 0; i < len(name); i, j = i+1, (j+1)&3 {
				a.mmoBuf[j] = name[i]
				if j == 3 {
					a.mmoOut()
				}
			}
			if j != 0 {
				for ; j < 4; j++ {
					a.mmoBuf[j] = 0
				}
				a.mmoOut()
			}

//line mmixal.w:1259
			a.filenamePassed[a.curFile] = true
		}
		a.mmoCurFile = a.curFile
		a.mmoLineNo = 0
	}
	if a.lineNo != a.mmoLineNo {
		if a.lineNo >= 0x10000 {
			a.fatal("I can't deal with line numbers exceeding 65535")

		}
		a.mmoLopp(lopLine, uint16(a.lineNo))
		a.mmoLineNo = a.lineNo
	}
}

//line mmixal.w:1307
func (a *assembler) assemble(k int, dat Tetra, xBits byte) {
	var l int
	if a.specMode {
		l = int(a.specModeLoc)
		if l&(k-1) != 0 {
			if a.heldBits == 1 && k == 2 {
				l++
				a.specModeLoc, a.holdBuf[1], a.heldBits = Tetra(l), 0, 3
			} else {
				l = (l + k) & -k
				a.specModeLoc = Tetra(l)
				a.mmoClear()
			}
		}
	} else {
		l = int(Tetra(a.curLoc))

//line mmixal.w:1349
		if (a.curLoc^a.mmoCurLoc)&^3 != 0 {
			a.mmoLoc()
		}

//line mmixal.w:1324
		if a.heldBits == 0 && a.curLoc>>61 == 0 {
			a.mmoSync()
		}
	}

//line mmixal.w:1337
	for j := 0; j < k; j++ {
		jj := (l + j) & 3
		a.holdBuf[jj] = byte(dat >> (8 * (k - 1 - j)))
		a.heldBits |= 1 << jj
		a.listingBits |= 1 << jj
	}
	a.listingBits |= xBits
	if (l+k)&3 == 0 {
		a.mmoClear()
	}

//line mmixal.w:1329
	if a.specMode {
		a.specModeLoc += Tetra(k)
	} else {
		a.curLoc += Octa(k)
	}
}

//line mmixal.w:1389
func isLetter(c byte) bool {
	return 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || c == '_' || c == ':' || c > 126
}

func trieSearch(t *trieNode, s []byte, i int) (*trieNode, int) {
	tt := t
	for i < len(s) && (isLetter(s[i]) || isDigit(s[i])) {
		c := uint16(s[i])
		if tt.mid == nil {
			tt.mid = &trieNode{ch: c}
		}
		tt = tt.mid
		for c != tt.ch {
			if c < tt.ch {
				if tt.left == nil {
					tt.left = &trieNode{ch: c}
				}
				tt = tt.left
			} else {
				if tt.right == nil {
					tt.right = &trieNode{ch: c}
				}
				tt = tt.right
			}
		}
		i++
	}
	return tt, i
}

//line mmixal.w:1463
func (a *assembler) newSymNode(serialize bool) *symNode {
	p := new(symNode)
	if serialize {
		a.serialNumber++
		p.serial = a.serialNumber
	}
	return p
}

//line mmixal.w:1785
func prune(t *trieNode) *trieNode {
	useful := false
	if t.sym != nil {
		if t.sym.serial != 0 {
			useful = true
		} else {
			t.sym = nil
		}
	}
	if t.left != nil {
		if t.left = prune(t.left); t.left != nil {
			useful = true
		}
	}
	if t.mid != nil {
		if t.mid = prune(t.mid); t.mid != nil {
			useful = true
		}
	}
	if t.right != nil {
		if t.right = prune(t.right); t.right != nil {
			useful = true
		}
	}
	if useful {
		return t
	}
	return nil
}

//line mmixal.w:1818
func (a *assembler) outStab(t *trieNode) {
	m := 0
	if t.ch > 0xff {
		m += 0x80
	}
	if t.left != nil {
		m += 0x40
	}
	if t.mid != nil {
		m += 0x20
	}
	if t.right != nil {
		m += 0x10
	}
	if t.sym != nil {

//line mmixal.w:1848
		switch {
		case t.sym.link == register:
			m += 0xf
		case t.sym.link == defined:

//line mmixal.w:1916
			h := Tetra(t.sym.equiv >> 32)
			x := h
			if h&0xffff0000 == 0x20000000 {
				m += 8
				x = h - 0x20000000 // 데이터 세그먼트
			}
			if x != 0 {
				m += 4
			} else {
				x = Tetra(t.sym.equiv)
			}
			j := 1
			for ; j < 4; j++ {
				if x < 1<<(8*j) {
					break
				}
			}
			m += j

//line mmixal.w:1853
		case t.sym.link != nil || t.sym.serial == 1:

//line mmixal.w:1958
			c := byte(t.ch)
			if m&0x80 != 0 {
				c = '?' // 유니코드? 아직 아니다
			}
			fmt.Fprintf(a.stderr, "undefined symbol: %s\n", string(append(a.symBuf, c))[1:])

			a.errCount++
			m += 2

//line mmixal.w:1855
		}

//line mmixal.w:1834
	}
	a.mmoByte(byte(m))
	if t.left != nil {
		a.outStab(t.left)
	}
	if m&0x2f != 0 {

//line mmixal.w:1864
		if m&0x80 != 0 {
			a.mmoByte(byte(t.ch >> 8))
		}
		a.mmoByte(byte(t.ch))
		if m&0x80 != 0 {
			a.symBuf = append(a.symBuf, '?') // 유니코드? 아직 아니다
		} else {
			a.symBuf = append(a.symBuf, byte(t.ch))
		}
		m &= 0xf
		if m != 0 && t.sym.link != nil {
			if a.listingFile != nil {

//line mmixal.w:1943
				fmt.Fprintf(a.listingFile, " %s = ", a.symBuf[1:])
				switch pp := t.sym; pp.link {
				case defined:
					fmt.Fprintf(a.listingFile, "#%016x", pp.equiv)
				case register:
					fmt.Fprintf(a.listingFile, "$%03d", Tetra(pp.equiv))
				default:
					fmt.Fprintf(a.listingFile, "?")
				}
				fmt.Fprintf(a.listingFile, " (%d)\n", t.sym.serial)

//line mmixal.w:1877
			}

//line mmixal.w:1890
			if m == 15 {
				m = 1
			} else if m > 8 {
				m -= 8
			}
			for ; m > 0; m-- {
				a.mmoByte(byte(t.sym.equiv >> (8 * (m - 1))))
			}
			for m = 0; m < 4; m++ {
				if t.sym.serial < 1<<(7*(m+1)) {
					break
				}
			}
			for ; m >= 0; m-- {
				b := byte((t.sym.serial >> (7 * m)) & 0x7f)
				if m == 0 {
					b += 0x80
				}
				a.mmoByte(b)
			}

//line mmixal.w:1879
		}
		if t.mid != nil {
			a.outStab(t.mid)
		}
		a.symBuf = a.symBuf[:len(a.symBuf)-1]

//line mmixal.w:1841
	}
	if t.right != nil {
		a.outStab(t.right)
	}
}

//line mmixal.w:2049
func (a *assembler) topOp() stackOp { return a.opStack[a.opPtr-1] }

//line mmixal.w:2050
func (a *assembler) topVal() *valNode { return &a.valStack[a.valPtr-1] }

//line mmixal.w:2051
func (a *assembler) nextVal() *valNode { return &a.valStack[a.valPtr-2] }

//line mmixal.w:2497
func (a *assembler) binaryCheck(verb string) {
	if a.topVal().status != pure || a.nextVal().status != pure {
		a.derr("can %s pure values only", verb)
	}
}

//line mmixal.w:3533
func scanInt(s string) (int, bool) {
	i := 0
	for i < len(s) && isSpace(s[i]) {
		i++
	}
	neg := false
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		neg = s[i] == '-'
		i++
	}
	if i == len(s) || !isDigit(s[i]) {
		return 0, false
	}
	n := 0
	for ; i < len(s) && isDigit(s[i]); i++ {
		n = 10*n + int(s[i]-'0')
	}
	if neg {
		n = -n
	}
	return n, true
}

//line mmixal.w:3426
func mmixal(args []string, stderr io.Writer, now int64) (code int) {
	a := &assembler{stderr: stderr, greg: 255, lreg: 32}
	var j, k int // 두루 쓰는 정수들
	var files []*os.File

//line mmixal.w:978
	var p int // 지금 훑고 있는 곳

//line mmixal.w:1669
	var tt *trieNode
	var pp, qq *symNode

//line mmixal.w:2070
	var acc Octa // 임시 누산기

//line mmixal.w:3431
	defer func() {
		if r := recover(); r != nil {
			if r != (fatalSignal{}) {
				panic(r)
			}
			code = -2
		}

//line mmixal.w:3468
		if a.objFile != nil {
			a.objFile.Flush()
		}
		if a.listingFile != nil {
			a.listingFile.Flush()
		}
		for _, f := range files {
			f.Close()
		}

//line mmixal.w:3439
	}()

//line mmixal.w:3487
options:
	for j = 1; j < len(args)-1 && len(args[j]) > 0 && args[j][0] == '-'; j++ {
		if len(args[j]) > 2 {
			n, ok := scanInt(args[j][2:])
			if args[j][1] != 'b' || !ok {
				break
			}
			a.bufSize = n
			continue
		}

//line mmixal.w:3508
		var opt byte
		if len(args[j]) == 2 {
			opt = args[j][1]
		}
		switch opt {
		case 'x':
			a.expanding = true
		case 'o':
			j++
			a.objFileName = args[j]
		case 'l':
			j++
			a.listingName = args[j]
		case 'b':
			n, ok := scanInt(args[j+1])
			if !ok {
				break options
			}
			a.bufSize = n
			j++
		default:
			break options
		}

//line mmixal.w:3498
	}
	if j != len(args)-1 {
		fmt.Fprintf(stderr, "Usage: %s %s sourcefilename\n",

			args[0], "[-x] [-l listingname] [-b buffersize] [-o objectfilename]")
		return -1
	}
	a.srcFileName = args[j]

//line mmixal.w:3441

//line mmixal.w:825
	if a.bufSize < 72 {
		a.bufSize = 72
	}
	a.buffer = make([]byte, a.bufSize+2)

//line mmixal.w:1483
	a.trieRoot = &trieNode{ch: ':'}
	a.curPrefix = a.trieRoot
	a.opRoot = &trieNode{ch: '^'}
	a.trieRoot.mid = a.opRoot

//line mmixal.w:1660
	for _, op := range opInitTable {
		tt, _ = trieSearch(a.opRoot, []byte(op.name), 0)
		pp = a.newSymNode(false)
		tt.sym = pp
		pp.link = predefined
		pp.equiv = Octa(op.code)<<32 | Octa(op.bits)
	}

//line mmixal.w:1673
	for j, name := range specialName {
		tt, _ = trieSearch(a.trieRoot, []byte(name), 0)
		pp = a.newSymNode(false)
		tt.sym = pp
		pp.link = predefined
		pp.equiv = Octa(j)
	}

//line mmixal.w:1732
	for _, d := range predefs {
		tt, _ = trieSearch(a.trieRoot, []byte(d.name), 0)
		pp = a.newSymNode(false)
		tt.sym = pp
		pp.link = predefined
		pp.equiv = Octa(d.h)<<32 | Octa(d.l)
	}

//line mmixal.w:1746
	tt, _ = trieSearch(a.trieRoot, []byte("Main"), 0)
	tt.sym = a.newSymNode(true)

//line mmixal.w:2076
	a.opStack = make([]stackOp, a.bufSize+1)
	a.valStack = make([]valNode, a.bufSize+1)

//line mmixal.w:2246
	for j = 0; j < 10; j++ {
		a.forwardLocalHost[j].sym = &a.forwardLocal[j]
		a.backwardLocalHost[j].sym = &a.backwardLocal[j]
		a.backwardLocal[j].link = defined
	}

//line mmixal.w:3557
	f, err := os.Open(a.srcFileName)
	if err != nil {
		a.fatal("Can't open the source file %s", a.srcFileName)

	}
	files = append(files, f)
	a.srcFile = bufio.NewReader(f)
	if a.objFileName == "" {
		if n := len(a.srcFileName); n > 0 && a.srcFileName[n-1] == 's' {
			a.objFileName = a.srcFileName[:n-1] + "o"
		} else {
			a.objFileName = a.srcFileName + ".mmo"
		}
	}
	if f, err = os.Create(a.objFileName); err != nil {
		a.fatal("Can't open the object file %s", a.objFileName)
	}
	files = append(files, f)
	a.objFile = bufio.NewWriter(f)
	if a.listingName != "" {
		if f, err = os.Create(a.listingName); err != nil {
			a.fatal("Can't open the listing file %s", a.listingName)
		}
		files = append(files, f)
		a.listingFile = bufio.NewWriter(f)
	}

//line mmixal.w:3597
	a.filename = []string{a.srcFileName}

//line mmixal.w:3601
	a.mmoLop(lopPre, 1, 1)
	a.mmoTetra(Tetra(now))
	a.mmoCurFile = -1

//line mmixal.w:3442
	for {

//line mmixal.w:850
		n := 0
		for n < a.bufSize {
			c, err := a.srcFile.ReadByte()
			if err != nil {
				break
			}
			a.buffer[n] = c
			n++
			if c == '\n' {
				break
			}
		}
		if n == 0 {
			break
		}
		a.buffer[n], a.buffer[n+1] = 0, 0
		a.lineNo++
		a.lineListed = false
		j = cstrlen(a.buffer)
		if j > 0 && a.buffer[j-1] == '\n' {
			a.buffer[j-1] = 0 // 줄바꿈 문자를 없앤다
		} else if c, err := a.srcFile.ReadByte(); err == nil {

//line mmixal.w:899
			for c != '\n' {
				if c, err = a.srcFile.ReadByte(); err != nil {
					break
				}
			}
			if !a.longWarningGiven {
				a.longWarningGiven = true
				a.err("*trailing characters of long input line have been dropped")

				fmt.Fprintf(a.stderr, "(say `-b <number>' to increase the length of my input buffer)\n")
			} else {
				a.err("*trailing characters dropped")
			}

//line mmixal.w:873
		}
		if a.buffer[0] == '#' {

//line mmixal.w:932
			for p = 1; isSpace(a.buffer[p]); p++ {
			}
			for j = 0; isDigit(a.buffer[p]); p++ {
				j = 10*j + int(a.buffer[p]-'0')
			}
			for ; isSpace(a.buffer[p]); p++ {
			}
			if a.buffer[p] == '"' {
				var name []byte
				for p, k = p+1, 0; a.buffer[p] != 0 && a.buffer[p] != '"' && k < filenameMax; p, k = p+1, k+1 {
					name = append(name, a.buffer[p])
				}
				if k == filenameMax {
					a.fatal("Capacity exceeded: File name too long")

				}
				if a.buffer[p] == '"' && a.buffer[p-1] != '"' { // 그렇다, 줄 지시문이다

//line mmixal.w:954
					for k = 0; k < len(a.filename) && a.filename[k] != string(name); k++ {
					}
					if k == len(a.filename) {
						if len(a.filename) == 256 {
							a.fatal("Capacity exceeded: More than 256 file names")
						}
						a.filename = append(a.filename, string(name))
					}
					a.curFile = k
					a.lineNo = j - 1

//line mmixal.w:950
				}
			}

//line mmixal.w:876
		}
		a.bufPtr = 0

//line mmixal.w:3444
		for {

//line mmixal.w:2575
			func() {
				defer func() {
					if r := recover(); r != nil && r != (bypassSignal{}) {
						panic(r)
					}
				}()
				p = a.bufPtr
				a.bufPtr = len(a.buffer) - 1 // 빈 문자열

//line mmixal.w:2619
				if a.buffer[p] == 0 {
					return
				}
				a.labField = a.labField[:0]
				if !isSpace(a.buffer[p]) {
					if !isDigit(a.buffer[p]) && !isLetter(a.buffer[p]) {
						return // 주석
					}
					for isDigit(a.buffer[p]) || isLetter(a.buffer[p]) {
						a.labField = append(a.labField, a.buffer[p])
						p++
					}
					if a.buffer[p] != 0 && !isSpace(a.buffer[p]) {
						a.derr("label syntax error at `%s'", ch(a.buffer[p]))

					}
				}
				if len(a.labField) > 0 && isDigit(a.labField[0]) &&
					(len(a.labField) < 2 || a.labField[1] != 'H' || len(a.labField) > 2) {
					a.derr("improper local label `%s'", a.labField)

				}
				for p++; isSpace(a.buffer[p]); p++ {
				}

//line mmixal.w:2584

//line mmixal.w:2648
				a.opField = a.opField[:0]
				for isLetter(a.buffer[p]) || isDigit(a.buffer[p]) {
					a.opField = append(a.opField, a.buffer[p])
					p++
				}
				if !isSpace(a.buffer[p]) && a.buffer[p] != 0 && len(a.opField) > 0 {
					a.derr("opcode syntax error at `%s'", ch(a.buffer[p]))

				}
				tt, _ = trieSearch(a.opRoot, a.opField, 0)
				pp = tt.sym
				if pp == nil {
					if len(a.opField) > 0 {
						a.derr("unknown operation code `%s'", a.opField)

					}
					if len(a.labField) > 0 {
						a.derr("*no opcode; label `%s' will be ignored", a.labField)

					}
					return
				}
				a.opcode, a.opBits = Tetra(pp.equiv>>32), Tetra(pp.equiv)
				for isSpace(a.buffer[p]) {
					p++
				}

//line mmixal.w:2585

//line mmixal.w:2684
				a.operandList = a.operandList[:0]
				for a.buffer[p] != 0 {
					if a.buffer[p] == ';' {
						break
					}
					if a.buffer[p] == '\'' {
						a.operandList = append(a.operandList, a.buffer[p])
						p++
						if a.buffer[p] == 0 {
							a.err("incomplete character constant")

						}
						a.operandList = append(a.operandList, a.buffer[p])
						p++
						if a.buffer[p] != '\'' {
							a.err("illegal character constant")

						}
					} else if a.buffer[p] == '"' {

//line mmixal.w:2714
						a.operandList = append(a.operandList, a.buffer[p])
						for p++; a.buffer[p] != 0 && a.buffer[p] != '"'; p++ {
							a.operandList = append(a.operandList, a.buffer[p])
						}
						if a.buffer[p] == 0 {
							a.err("incomplete string constant")
						}

//line mmixal.w:2704
					}
					a.operandList = append(a.operandList, a.buffer[p])
					p++
					if isSpace(a.buffer[p]) {
						break
					}
				}

//line mmixal.w:2723
				for isSpace(a.buffer[p]) {
					p++
				}
				if a.buffer[p] == ';' {
					p++
				} else {
					p = len(a.buffer) - 1 // 쌍반점이 뒤따르지 않으면 줄의 나머지는 주석이다
				}
				if len(a.operandList) == 0 {
					a.operandList = append(a.operandList, '0') // 빈 피연산자 필드를 `\.0'으로 바꾼다
				}
				a.operandList = append(a.operandList, 0)

//line mmixal.w:2586
				a.bufPtr = p
				if a.specMode && a.opBits&specBit == 0 {
					a.derr("cannot use `%s' in special mode", a.opField)

				}
				if a.opBits&noLabelBit != 0 && len(a.labField) > 0 {
					a.derr("*label field of `%s' instruction is ignored", a.opField)
					a.labField = a.labField[:0]
				}

				if a.opBits&alignBits != 0 {

//line mmixal.w:2740
					j = int((a.opBits & alignBits) >> 16)
					a.curLoc = (a.curLoc + Octa(1<<j-1)) &^ Octa(1<<j-1)

//line mmixal.w:2598
				}

//line mmixal.w:2095
				p = 0
				a.valPtr = 0                       // |valStack|은 비었다
				a.opStack[0], a.opPtr = outerLP, 1 // |opStack|에는 ``바깥 왼쪽 괄호''가 있다
			scan:
				for {

//line mmixal.w:2122
				open:
					for {
						c := a.operandList[p]
						switch {
						case isLetter(c):

//line mmixal.w:2196
							if c == ':' {
								tt, p = trieSearch(a.trieRoot, a.operandList, p+1)
							} else {
								tt, p = trieSearch(a.curPrefix, a.operandList, p)
							}

//line mmixal.w:2207
							a.valPtr++
							pp = tt.sym
							if pp == nil {
								pp = a.newSymNode(true)
								tt.sym = pp
							}
							a.topVal().link, a.topVal().equiv = tt, pp.equiv
							if pp.link == predefined {
								pp.link = defined
							}
							switch pp.link {
							case defined:
								a.topVal().status = pure
							case register:
								a.topVal().status = regVal
							default:
								a.topVal().status = undefined
							}

//line mmixal.w:2128
						case isDigit(c):
							switch a.operandList[p+1] {
							case 'F':

//line mmixal.w:2227
								tt = &a.forwardLocalHost[c-'0']
								p += 2

//line mmixal.w:2207
								a.valPtr++
								pp = tt.sym
								if pp == nil {
									pp = a.newSymNode(true)
									tt.sym = pp
								}
								a.topVal().link, a.topVal().equiv = tt, pp.equiv
								if pp.link == predefined {
									pp.link = defined
								}
								switch pp.link {
								case defined:
									a.topVal().status = pure
								case register:
									a.topVal().status = regVal
								default:
									a.topVal().status = undefined
								}

//line mmixal.w:2132
							case 'B':

//line mmixal.w:2232
								tt = &a.backwardLocalHost[c-'0']
								p += 2

//line mmixal.w:2207
								a.valPtr++
								pp = tt.sym
								if pp == nil {
									pp = a.newSymNode(true)
									tt.sym = pp
								}
								a.topVal().link, a.topVal().equiv = tt, pp.equiv
								if pp.link == predefined {
									pp.link = defined
								}
								switch pp.link {
								case defined:
									a.topVal().status = pure
								case register:
									a.topVal().status = regVal
								default:
									a.topVal().status = undefined
								}

//line mmixal.w:2134
							default:

//line mmixal.w:2289
								acc = Octa(c - '0')
								for p++; isDigit(a.operandList[p]); p++ {
									acc = acc + acc<<2
									acc = acc<<1 + Octa(a.operandList[p]-'0')
								}

//line mmixal.w:2299
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal.w:2136
							}
						default:
							p++
							switch c {
							case '#':

//line mmixal.w:2305
								if !isXDigit(a.operandList[p]) {
									a.err("illegal hexadecimal constant")

								}
								acc = 0
								for ; isXDigit(a.operandList[p]); p++ {
									d := a.operandList[p]
									switch {
									case d >= 'a':
										acc = acc<<4 + Octa(d-'a'+10)
									case d >= 'A':
										acc = acc<<4 + Octa(d-'A'+10)
									default:
										acc = acc<<4 + Octa(d-'0')
									}
								}

//line mmixal.w:2299
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal.w:2142
							case '\'':

//line mmixal.w:2255
								acc = Octa(a.operandList[p])
								p += 2

//line mmixal.w:2299
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal.w:2144
							case '"':

//line mmixal.w:2270
								acc = Octa(a.operandList[p])
								if a.operandList[p] == '"' {
									p++
									acc = 0
									a.err("*null string is treated as zero")

								} else if a.operandList[p+1] == '"' {
									p += 2
								} else {
									a.operandList[p] = '"'
									p--
									a.operandList[p] = ','
								}

//line mmixal.w:2299
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal.w:2146
							case '@':

//line mmixal.w:2324
								acc = a.curLoc

//line mmixal.w:2299
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal.w:2148

//line mmixal.w:2157
							case '-':
								a.opStack[a.opPtr] = negate
								a.opPtr++
								continue open
							case '+':
								continue open
							case '&':
								a.opStack[a.opPtr] = serialize
								a.opPtr++
								continue open
							case '~':
								a.opStack[a.opPtr] = complement
								a.opPtr++
								continue open
							case '$':
								a.opStack[a.opPtr] = registerize
								a.opPtr++
								continue open
							case '(':
								a.opStack[a.opPtr] = innerLP
								a.opPtr++
								continue open

//line mmixal.w:2149
							default:

//line mmixal.w:2181
								if p == 1 { // 피연산자 목록을 빈 것으로 취급한다
									a.operandList[0], a.operandList[1], p = '0', 0, 0
									continue open
								}
								if a.operandList[p-1] != 0 {
									a.derr("syntax error at character `%s'", ch(a.operandList[p-1]))
								}
								a.derr("syntax error after character `%s'", ch(a.operandList[p-2]))

//line mmixal.w:2151
							}
						}
						break
					}

//line mmixal.w:2101
				close:
					for {

//line mmixal.w:2332
						c := a.operandList[p]
						p++
						switch c {
						case '+':
							a.rtOp = plus
						case '-':
							a.rtOp = minus
						case '*':
							a.rtOp = times
						case '/':
							if a.operandList[p] != '/' {
								a.rtOp = over
							} else {
								p++
								a.rtOp = frac
							}
						case '%':
							a.rtOp = mod
						case '<', '>':
							if c == '<' {
								a.rtOp = shl
							} else {
								a.rtOp = shr
							}
							p++
							if a.operandList[p-1] != a.operandList[p-2] {
								a.derr("syntax error at `%s'", ch(a.operandList[p-2]))

							}
						case '&':
							a.rtOp = and
						case '|':
							a.rtOp = or
						case '^':
							a.rtOp = xor
						case ')':
							a.rtOp = innerRP
						case 0, ',':
							a.rtOp = outerRP
						default:
							a.derr("syntax error at `%s'", ch(a.operandList[p-1]))
						}

//line mmixal.w:2104
					reduce:
						for precedence[a.topOp()] >= precedence[a.rtOp] {

//line mmixal.w:2382
							a.opPtr--
							switch op := a.opStack[a.opPtr]; {
							case op == innerLP:
								if a.rtOp == innerRP {
									continue close
								}
								a.err("*missing right parenthesis")

							case op == outerLP:
								if a.rtOp == outerRP {

//line mmixal.w:2407
									if a.topVal().status == regVal && a.topVal().equiv > 0xff {
										a.err("*register number too large, will be reduced mod 256")

										a.topVal().equiv &= 0xff
									}
									if a.operandList[p-1] == 0 {
										break scan
									}
									a.rtOp = outerLP // 반점
									break reduce

//line mmixal.w:2393
								}
								a.opPtr++
								a.err("*missing left parenthesis")

								continue close
							case op < innerLP:

//line mmixal.w:2459
								top := a.topVal()
								switch op {
								case negate:
									if top.status != pure {
										a.err("can negate pure values only")

									}
									top.equiv = -top.equiv
								case complement:
									if top.status != pure {
										a.err("can complement pure values only")

									}
									top.equiv = ^top.equiv
								case registerize:
									if top.status != pure {
										a.err("can registerize pure values only")

									}
									top.status = regVal
								case serialize:
									if top.link == nil {
										a.err("can take serial number of symbol only")

									}
									top.equiv = Octa(top.link.sym.serial)
									top.status = pure
								}

//line mmixal.w:2400
								a.topVal().link = nil
							default:

//line mmixal.w:2438
								top, next := a.topVal(), a.nextVal()
								switch op {
								case plus:
									if top.status == undefined {
										a.err("cannot add an undefined quantity")

									}
									if next.status == undefined {
										a.err("cannot add to an undefined quantity")
									}
									if top.status == regVal && next.status == regVal {
										a.err("cannot add two register numbers")
									}
									next.equiv += top.equiv

//line mmixal.w:2504
								case minus:
									if top.status == undefined {
										a.err("cannot subtract an undefined quantity")

									}
									if next.status == undefined {
										a.err("cannot subtract from an undefined quantity")
									}
									if top.status == regVal && next.status != regVal {
										a.err("cannot subtract register number from pure value")
									}
									next.equiv -= top.equiv
								case times:
									a.binaryCheck("multiply")

									next.equiv *= top.equiv
								case over, mod:
									a.binaryCheck("divide")

									if top.equiv == 0 {
										a.err("*division by zero")

									}
									q, r := mmixarith.Div(0, next.equiv, top.equiv)
									if op == mod {
										next.equiv = r
									} else {
										next.equiv = q
									}

//line mmixal.w:2535
								case frac:
									a.binaryCheck("compute a ratio of")

									if next.equiv >= top.equiv {
										a.err("*illegal fraction")

									}
									next.equiv, _ = mmixarith.Div(next.equiv, 0, top.equiv)
								case shl, shr:
									a.binaryCheck("compute a bitwise shift of")
									switch {
									case top.equiv > 63:
										next.equiv = 0
									case op == shl:
										next.equiv <<= top.equiv
									default:
										next.equiv >>= top.equiv
									}
								case and:
									a.binaryCheck("compute bitwise and of")
									next.equiv &= top.equiv
								case or:
									a.binaryCheck("compute bitwise or of")
									next.equiv |= top.equiv
								case xor:
									a.binaryCheck("compute bitwise xor of")
									next.equiv ^= top.equiv

//line mmixal.w:2453
								}

//line mmixal.w:2403

//line mmixal.w:2429
								if a.topVal().status == a.nextVal().status {
									a.nextVal().status = pure
								} else {
									a.nextVal().status = regVal
								}
								a.valPtr--
								a.topVal().link = nil

//line mmixal.w:2404
							}

//line mmixal.w:2107
						}
						break
					}
					a.opStack[a.opPtr] = a.rtOp
					a.opPtr++
				}

//line mmixal.w:2600
				if a.opcode == GREG {

//line mmixal.w:2747
					v := a.valStack[0].equiv
					for j = a.greg; v != 0 && j < 255; j++ {
						if a.gregVal[j] == v {
							break
						}
					}
					if v != 0 && j < 255 {
						a.curGreg = j
					} else {
						if a.greg == 32 {
							a.err("too many global registers")

						}
						a.greg--
						a.gregVal[a.greg] = v
						a.curGreg = a.greg
					}

//line mmixal.w:2602
				}
				if len(a.labField) > 0 {

//line mmixal.w:2780
					newLink := defined
					acc = a.curLoc
					if a.opcode == IS {
						if a.valStack[0].status == undefined {
							a.err("the operand is undefined")

						}
						a.curLoc = a.valStack[0].equiv
						if a.valStack[0].status == regVal {
							newLink = register
						}
					} else if a.opcode == GREG {
						a.curLoc, newLink = Octa(a.curGreg), register
					}

//line mmixal.w:2851
					if isDigit(a.labField[0]) {
						pp = &a.forwardLocal[a.labField[0]-'0']
					} else {
						if a.labField[0] == ':' {
							tt, _ = trieSearch(a.trieRoot, a.labField, 1)
						} else {
							tt, _ = trieSearch(a.curPrefix, a.labField, 0)
						}
						pp = tt.sym
						if pp == nil {
							pp = a.newSymNode(true)
							tt.sym = pp
						}
					}

//line mmixal.w:2807
					switch {
					case pp.link == defined || pp.link == register:
						if pp.equiv != a.curLoc || pp.link != newLink {
							if pp.serial != 0 {
								a.derr("symbol `%s' is already defined", a.labField)

							}
							a.serialNumber++
							pp.serial = a.serialNumber
							a.derr("*redefinition of predefined symbol `%s'", a.labField)

						}
					case pp.link == predefined:
						a.serialNumber++
						pp.serial = a.serialNumber
					case pp.link != nil:
						if newLink == register {
							a.err("future reference cannot be to a register")

						}
						for pp.link != nil {

//line mmixal.w:2870
							qq = pp.link
							pp.link = qq.link
							a.mmoLoc()
							if qq.serial == fixO {

//line mmixal.w:2880
								if (qq.equiv>>32)&0xffffff != 0 {
									a.mmoLop(lopFixo, 0, 2)
									a.mmoTetra(Tetra(qq.equiv >> 32))
								} else {
									a.mmoLop(lopFixo, byte(qq.equiv>>56), 1)
								}
								a.mmoTetra(Tetra(qq.equiv))

//line mmixal.w:2875
							} else {

//line mmixal.w:2894
								o := a.curLoc - qq.equiv
								if o&3 != 0 {
									a.derr("*relative address in location #%016x not divisible by 4", qq.equiv)

								}
								o = Octa(int64(o) >> 2)
								k = 0
								switch h, l := Tetra(o>>32), Tetra(o); {
								case h == 0 && l < 0x10000:
									a.mmoLopp(lopFixr, uint16(l))
								case h == 0 && qq.serial == fixXYZ && l < 0x1000000:
									a.mmoLop(lopFixrx, 0, 24)
									a.mmoTetra(l)
								case h == 0xffffffff && qq.serial == fixXYZ && l >= 0xff000000:
									a.mmoLop(lopFixrx, 0, 24)
									a.mmoTetra(l & 0x1ffffff)
								case h == 0xffffffff && qq.serial == fixYZ && l >= 0xffff0000:
									a.mmoLop(lopFixrx, 0, 16)
									a.mmoTetra(l & 0x100ffff)
								default:
									k = 1
								}
								if k != 0 {
									a.derr("relative address in location #%016x is too far away", qq.equiv)
								}

//line mmixal.w:2877
							}

//line mmixal.w:2829
						}
					}

//line mmixal.w:2796
					if isDigit(a.labField[0]) {
						pp = &a.backwardLocal[a.labField[0]-'0']
					}
					pp.equiv, pp.link = a.curLoc, newLink

//line mmixal.w:2837
					if !isDigit(a.labField[0]) {
						for j = 0; j < a.valPtr; j++ {
							if a.valStack[j].status == undefined && a.valStack[j].link.sym == pp {
								if newLink == register {
									a.valStack[j].status = regVal
								} else {
									a.valStack[j].status = pure
								}
								a.valStack[j].equiv = a.curLoc
							}
						}
					}

//line mmixal.w:2801
					if a.listingFile != nil && (a.opcode == IS || a.opcode == LOC) {

//line mmixal.w:2921
						if newLink == defined {
							fmt.Fprintf(a.listingFile, "(%016x)", a.curLoc)
							a.flushListingLine(" ")
						} else {
							fmt.Fprintf(a.listingFile, "($%03d)", Tetra(a.curLoc)&0xff)
							a.flushListingLine("             ")
						}

//line mmixal.w:2803
					}
					a.curLoc = acc

//line mmixal.w:2605
				}

//line mmixal.w:2939
				a.futureBits = 0
				if a.opBits&manyArgBit != 0 {

//line mmixal.w:2989
					for j = 0; j < a.valPtr; j++ {
						v := &a.valStack[j]

//line mmixal.w:3016
						if v.status == regVal {
							a.err("*register number used as a constant")

						} else if v.status == undefined {
							if a.opcode != OCTA {
								a.err("undefined constant")

							}
							pp = v.link.sym
							qq = a.newSymNode(false)
							qq.link = pp.link
							pp.link = qq
							qq.serial = fixO
							qq.equiv = a.curLoc
						}

//line mmixal.w:2992
						k = 1 << (a.opcode - BYTE)
						if (v.equiv>>32 != 0 && a.opcode < OCTA) ||
							(Tetra(v.equiv) > 0xffff && a.opcode < TETRA) ||
							(Tetra(v.equiv) > 0xff && a.opcode < WYDE) {
							if k == 1 {
								a.err("*constant doesn't fit in one byte")

							} else {
								a.derr("*constant doesn't fit in %d bytes", k)
							}
						}
						switch {
						case k < 8:
							a.assemble(k, Tetra(v.equiv), 0)
						case v.status == undefined:
							a.assemble(4, 0, 0xf0)
							a.assemble(4, 0, 0xf0)
						default:
							a.assemble(4, Tetra(v.equiv>>32), 0)
							a.assemble(4, Tetra(v.equiv), 0)
						}
					}

//line mmixal.w:2942
					return
				}
				switch a.valPtr {
				case 1:
					if a.opBits&oneArgBit == 0 {
						a.derr("opcode `%s' needs more than one operand", a.opField)

					}

//line mmixal.w:3265
					v := &a.valStack[0]
					switch {
					case v.status == undefined && a.opBits&relAddrBit != 0:

//line mmixal.w:3308
						pp = v.link.sym
						qq = a.newSymNode(false)
						qq.link = pp.link
						pp.link = qq
						qq.serial = fixXYZ
						qq.equiv = a.curLoc
						a.xyz = 0
						a.futureBits = 0xe0

//line mmixal.w:3269
					case v.status == pure && a.opBits&relAddrBit != 0:
						if a.opBits&xyzrBit != 0 {
							a.derr("*operand of `%s' should be a register number", a.opField)
						}

//line mmixal.w:3318
						if v.equiv&3 != 0 {
							a.err("*relative address is not divisible by 4")

						}
						source := Octa(int64(a.curLoc) >> 2)
						dest := Octa(int64(v.equiv) >> 2)
						acc = dest - source
						if acc&mmixarith.SignBit == 0 {
							if acc > 0xffffff {
								a.err("relative address is more than #ffffff tetrabytes forward")
							}
						} else {
							acc += 0x1000000
							a.opcode++
							if acc > 0xffffff {
								a.err("relative address is more than #1000000 tetrabytes backward")
							}
						}
						a.xyz = Tetra(acc)

//line mmixal.w:3274
					default:

//line mmixal.w:3290
						switch v.status {
						case undefined:
							if a.opcode != PREFIX {
								a.err("the operand is undefined")

							}
						case regVal:
							if a.opBits&(xyzrBit|xyzarBit) == 0 {
								a.derr("*operand of `%s' should not be a register number", a.opField)

							}
						default:
							if a.opBits&xyzrBit != 0 {
								a.derr("*operand of `%s' should be a register number", a.opField)
							}
						}

//line mmixal.w:3276
						if a.opcode > 0xff {

//line mmixal.w:3347
							switch a.opcode {
							case LOC:
								a.curLoc = v.equiv
							case PREFIX:
								if v.link == nil {
									a.err("not a valid prefix")

								}
								a.curPrefix = v.link
							case GREG:
								if a.listingFile != nil {

//line mmixal.w:3389
									if v.equiv != 0 {
										fmt.Fprintf(a.listingFile, "($%03d=#%08x", a.curGreg, Tetra(v.equiv>>32))
										a.flushListingLine("    ")
										fmt.Fprintf(a.listingFile, "         %08x)", Tetra(v.equiv))
										a.flushListingLine(" ")
									} else {
										fmt.Fprintf(a.listingFile, "($%03d)", a.curGreg)
										a.flushListingLine("             ")
									}

//line mmixal.w:3359
								}
							case LOCAL:
								if Tetra(v.equiv) > Tetra(a.lreg) {
									a.lreg = int(int32(Tetra(v.equiv)))
								}
								if a.listingFile != nil {
									fmt.Fprintf(a.listingFile, "($%03d)", int32(Tetra(v.equiv)))
									a.flushListingLine("             ")
								}
							case BSPEC:
								if v.equiv > 0xffff {
									a.err("*operand of `BSPEC' doesn't fit in two bytes")

								}
								a.mmoLoc()
								a.mmoSync()
								a.mmoLopp(lopSpec, uint16(v.equiv))
								a.specMode, a.specModeLoc = true, 0
							case ESPEC:
								a.specMode = false
								if a.heldBits != 0 {
									a.mmoClear()
								}
							}
							return

//line mmixal.w:3278
						}
						if v.equiv > 0xffffff {
							a.err("*XYZ field doesn't fit in three bytes")

						}
						a.xyz = Tetra(v.equiv) & 0xffffff
					}

//line mmixal.w:2951
				case 2:

//line mmixal.w:2972
					if a.opBits&twoArgBit == 0 {
						if a.opBits&oneArgBit != 0 {
							a.derr("opcode `%s' must not have two operands", a.opField)
						} else {
							a.derr("opcode `%s' must have more than two operands", a.opField)
						}
					}

//line mmixal.w:2953
					if a.opBits&(threeArgBit|memBit) == threeArgBit {

//line mmixal.w:2981
						a.valStack[2], a.valPtr = a.valStack[1], 3
						a.valStack[1] = valNode{equiv: 0, link: nil, status: pure}

//line mmixal.w:2955

//line mmixal.w:3047
						if a.valStack[2].status == undefined {
							a.err("Z field is undefined")

						}
						if a.valStack[2].status == regVal {
							if a.opBits&(immedBit|zrBit|zarBit) == 0 {
								a.derr("*Z field of `%s' should not be a register number", a.opField)

							}
						} else if a.opBits&immedBit != 0 {
							a.opcode++ // 즉치
						} else if a.opBits&zrBit != 0 {
							a.derr("*Z field of `%s' should be a register number", a.opField)
						}
						if a.valStack[2].equiv > 0xff {
							a.err("*Z field doesn't fit in one byte")

						}
						a.z = Tetra(a.valStack[2].equiv) & 0xff

//line mmixal.w:3068
						if a.valStack[1].status == undefined {
							a.err("Y field is undefined")

						}
						if a.valStack[1].status == regVal {
							if a.opBits&(yrBit|yarBit) == 0 {
								a.derr("*Y field of `%s' should not be a register number", a.opField)

							}
						} else if a.opBits&yrBit != 0 {
							a.derr("*Y field of `%s' should be a register number", a.opField)
						}
						if a.valStack[1].equiv > 0xff {
							a.err("*Y field doesn't fit in one byte")

						}
						a.y = Tetra(a.valStack[1].equiv) & 0xff
						a.yz = a.y<<8 + a.z

//line mmixal.w:3088
						if a.valStack[0].status == undefined {
							a.err("X field is undefined")

						}
						if a.valStack[0].status == regVal {
							if a.opBits&(xrBit|xarBit) == 0 {
								a.derr("*X field of `%s' should not be a register number", a.opField)

							}
						} else if a.opBits&xrBit != 0 {
							a.derr("*X field of `%s' should be a register number", a.opField)
						}
						if a.valStack[0].equiv > 0xff {
							a.err("*X field doesn't fit in one byte")

						}
						a.x = Tetra(a.valStack[0].equiv) & 0xff
						a.xyz = a.x<<16 + a.yz

//line mmixal.w:2956
					} else {

//line mmixal.w:3117
						v := &a.valStack[1]
						switch {
						case v.status == undefined && a.opBits&relAddrBit != 0:

//line mmixal.w:3166
							pp = v.link.sym
							qq = a.newSymNode(false)
							qq.link = pp.link
							pp.link = qq
							qq.serial = fixYZ
							qq.equiv = a.curLoc
							a.yz = 0
							a.futureBits = 0xc0

//line mmixal.w:3121
						case v.status == undefined:
							a.err("YZ field is undefined")

						case v.status == pure && a.opBits&memBit != 0:

//line mmixal.w:3203
							o := v.equiv
							k = 0
							for j = a.greg; j < 255; j++ {
								if a.gregVal[j] != 0 {
									acc = v.equiv - a.gregVal[j]
									if acc <= o {
										o, k = acc, j
									}
								}
							}
							switch {
							case o <= 0xff && k != 0:
								a.yz = Tetra(k<<8) + Tetra(o)
								a.opcode++
							case !a.expanding:
								a.err("no base address is close enough to the address A")

							default:

//line mmixal.w:3231
								for j = SETH; j <= ORL; j++ {
									switch j & 3 {
									case 0:
										a.yz = Tetra(o>>48) & 0xffff // \.{SETH}
									case 1:
										a.yz = Tetra(o>>32) & 0xffff // \.{SETMH} 또는 \.{ORMH}
									case 2:
										a.yz = Tetra(o>>16) & 0xffff // \.{SETML} 또는 \.{ORML}
									case 3:
										a.yz = Tetra(o) & 0xffff // \.{SETL} 또는 \.{ORL}
									}
									if a.yz != 0 || j == SETL {
										a.assemble(4, Tetra(j<<24)+255<<16+a.yz, 0)
										j |= ORH
									}
								}
								if k != 0 {
									a.yz = Tetra(k<<8) + 255 // Y = \$$k$, Z = \$255
								} else {
									a.yz, a.opcode = 255<<8, a.opcode+1 // Y = \$255, Z = 0
								}

//line mmixal.w:3222
							}

//line mmixal.w:3126
						default:
							if v.status == regVal {

//line mmixal.w:3144
								if a.opBits&(immedBit|yzrBit|yzarBit) == 0 {
									a.derr("*YZ field of `%s' should not be a register number", a.opField)

								}
								if a.opcode == SET {
									v.equiv <<= 8
									a.opcode = 0xc1 // \.{OR}로 바꾼다
								} else if a.opBits&memBit != 0 {
									v.equiv <<= 8
									a.opcode++ // 조용히 \.{,0}을 덧붙인다
								}

//line mmixal.w:3129
							} else {

//line mmixal.w:3157
								if a.opcode == SET {
									a.opcode = 0xe3 // \.{SETL}로 바꾼다
								} else if a.opBits&immedBit != 0 {
									a.opcode++ // 즉치
								} else if a.opBits&yzrBit != 0 {
									a.derr("*YZ field of `%s' should be a register number", a.opField)
								}

//line mmixal.w:3131
							}
							if v.status == pure && a.opBits&relAddrBit != 0 {

//line mmixal.w:3179
								if v.equiv&3 != 0 {
									a.err("*relative address is not divisible by 4")

								}
								source := Octa(int64(a.curLoc) >> 2)
								dest := Octa(int64(v.equiv) >> 2)
								acc = dest - source
								if acc&mmixarith.SignBit == 0 {
									if acc > 0xffff {
										a.err("relative address is more than #ffff tetrabytes forward")
									}
								} else {
									acc += 0x10000
									a.opcode++
									if acc > 0xffff {
										a.err("relative address is more than #10000 tetrabytes backward")
									}
								}
								a.yz = Tetra(acc)

//line mmixal.w:3134
							} else {
								if v.equiv > 0xffff {
									a.err("*YZ field doesn't fit in two bytes")

								}
								a.yz = Tetra(v.equiv) & 0xffff
							}
						}

//line mmixal.w:2958

//line mmixal.w:3088
						if a.valStack[0].status == undefined {
							a.err("X field is undefined")

						}
						if a.valStack[0].status == regVal {
							if a.opBits&(xrBit|xarBit) == 0 {
								a.derr("*X field of `%s' should not be a register number", a.opField)

							}
						} else if a.opBits&xrBit != 0 {
							a.derr("*X field of `%s' should be a register number", a.opField)
						}
						if a.valStack[0].equiv > 0xff {
							a.err("*X field doesn't fit in one byte")

						}
						a.x = Tetra(a.valStack[0].equiv) & 0xff
						a.xyz = a.x<<16 + a.yz

//line mmixal.w:2959
					}
				case 3:
					if a.opBits&threeArgBit == 0 {
						a.derr("opcode `%s' must not have three operands", a.opField)
					}

//line mmixal.w:3047
					if a.valStack[2].status == undefined {
						a.err("Z field is undefined")

					}
					if a.valStack[2].status == regVal {
						if a.opBits&(immedBit|zrBit|zarBit) == 0 {
							a.derr("*Z field of `%s' should not be a register number", a.opField)

						}
					} else if a.opBits&immedBit != 0 {
						a.opcode++ // 즉치
					} else if a.opBits&zrBit != 0 {
						a.derr("*Z field of `%s' should be a register number", a.opField)
					}
					if a.valStack[2].equiv > 0xff {
						a.err("*Z field doesn't fit in one byte")

					}
					a.z = Tetra(a.valStack[2].equiv) & 0xff

//line mmixal.w:3068
					if a.valStack[1].status == undefined {
						a.err("Y field is undefined")

					}
					if a.valStack[1].status == regVal {
						if a.opBits&(yrBit|yarBit) == 0 {
							a.derr("*Y field of `%s' should not be a register number", a.opField)

						}
					} else if a.opBits&yrBit != 0 {
						a.derr("*Y field of `%s' should be a register number", a.opField)
					}
					if a.valStack[1].equiv > 0xff {
						a.err("*Y field doesn't fit in one byte")

					}
					a.y = Tetra(a.valStack[1].equiv) & 0xff
					a.yz = a.y<<8 + a.z

//line mmixal.w:3088
					if a.valStack[0].status == undefined {
						a.err("X field is undefined")

					}
					if a.valStack[0].status == regVal {
						if a.opBits&(xrBit|xarBit) == 0 {
							a.derr("*X field of `%s' should not be a register number", a.opField)

						}
					} else if a.opBits&xrBit != 0 {
						a.derr("*X field of `%s' should be a register number", a.opField)
					}
					if a.valStack[0].equiv > 0xff {
						a.err("*X field doesn't fit in one byte")

					}
					a.x = Tetra(a.valStack[0].equiv) & 0xff
					a.xyz = a.x<<16 + a.yz

//line mmixal.w:2965
				default:
					a.derr("too many operands for opcode `%s'", a.opField)

				}
				a.assemble(4, a.opcode<<24+a.xyz, byte(a.futureBits))

//line mmixal.w:2607
			}()

//line mmixal.w:3446
			if a.buffer[a.bufPtr] == 0 {
				break
			}
		}
		if a.listingFile != nil {
			if a.listingBits != 0 {
				a.listingClear()
			} else if !a.lineListed {
				a.flushListingLine("                   ")
			}
		}
	}

//line mmixal.w:3609
	if a.lreg >= a.greg {
		a.fatal("Danger: Must reduce the number of GREGs by %d", a.lreg-a.greg+1)

	}

//line mmixal.w:3636
	a.mmoLop(lopPost, 0, byte(a.greg))
	tt, _ = trieSearch(a.trieRoot, []byte("Main"), 0)
	a.gregVal[255] = tt.sym.equiv
	for j = a.greg; j < 256; j++ {
		a.mmoTetra(Tetra(a.gregVal[j] >> 32))
		a.mmoTetra(Tetra(a.gregVal[j]))
	}

//line mmixal.w:1971
	a.opRoot.mid = nil // 연산 코드들을 모두 없앤다
	prune(a.trieRoot)
	a.symBuf = a.symBuf[:0]
	if a.listingFile != nil {
		fmt.Fprintf(a.listingFile, "\nSymbol table:\n")
	}
	a.mmoLop(lopStab, 0, 0)
	a.outStab(a.trieRoot)
	for a.mmoPtr&3 != 0 {
		a.mmoByte(0)
	}
	a.mmoLopp(lopEnd, uint16(a.mmoPtr>>2))

//line mmixal.w:3645
	for j = 0; j < 10; j++ {
		if a.forwardLocal[j].link != nil {
			a.errCount++
			fmt.Fprintf(stderr, "undefined local symbol %dF\n", j)

		}
	}

//line mmixal.w:3616
	if a.errCount > 0 {
		if a.errCount > 1 {
			fmt.Fprintf(stderr, "(%d errors were found.)\n", a.errCount)
		} else {
			fmt.Fprintf(stderr, "(One error was found.)\n")
		}
	}
	if a.objFile.Flush() != nil {
		a.fatal("Can't write on %s", a.objFileName)
	}

//line mmixal.w:3459
	return a.errCount
}

//line mmixal.w:3463
func main() {
	os.Exit(mmixal(os.Args, os.Stderr, time.Now().Unix()))
}
