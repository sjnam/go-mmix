//line mmixal/mmixal.w:38
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/sjnam/go-mmix/mmixarith"
)

//line mmixal/mmixal.w:785
type (
	Tetra = mmixarith.Tetra
	Octa  = mmixarith.Octa

//line mmixal/mmixal.w:788
)

//line mmixal/mmixal.w:825
type assembler struct {

//line mmixal/mmixal.w:830
	buffer      []byte // raw input of the current line
	bufPtr      int    // current position within |buffer|
	labField    []byte // copy of the label field of the current instruction
	opField     []byte // copy of the opcode field of the current instruction
	operandList []byte // copy of the operand field of the current instruction (null-terminated)

//line mmixal/mmixal.w:905
	curFile          int  // index of the current file in |filename|
	lineNo           int  // current position in the file
	lineListed       bool // have we listed the buffer contents?
	longWarningGiven bool // have we given the hint about \.{-b}?

//line mmixal/mmixal.w:914
	filename []string // source file names, including those in line directives

//line mmixal/mmixal.w:1002
	curLoc      Octa    // current location of assembled output
	listingLoc  Octa    // current location on the listing
	holdBuf     [4]byte // assembled bytes
	heldBits    byte    // which bytes of |holdBuf| are active?
	listingBits byte    // which of them haven't been listed yet?
	specMode    bool    // are we between \.{BSPEC} and \.{ESPEC}?
	specModeLoc Tetra   // number of bytes in the current special output

//line mmixal/mmixal.w:1137
	errCount int // this many errors were found

//line mmixal/mmixal.w:1184
	mmoBuf [4]byte // tetrabyte waiting to be output
	mmoPtr int     // bytes counted while outputting the symbol table

//line mmixal/mmixal.w:1283
	mmoCurLoc      Octa      // current location in the object file
	mmoLineNo      int       // current line number in the \.{mmo} output so far
	mmoCurFile     int       // index of the current file in the \.{mmo} output so far
	filenamePassed [256]bool // has a filename been recorded in the output?

//line mmixal/mmixal.w:1365
	trieRoot  *trieNode // root of the trie
	opRoot    *trieNode // root of subtrie for opcodes
	curPrefix *trieNode // root of subtrie for unqualified symbols

//line mmixal/mmixal.w:1464
	serialNumber int

//line mmixal/mmixal.w:1927
	symBuf []byte // the characters of a symbol, gathered along middle branches

//line mmixal/mmixal.w:2045
	opStack  []stackOp // stack for pending operators
	opPtr    int       // number of items on |opStack|
	valStack []valNode // stack for pending operands
	valPtr   int       // number of items on |valStack|
	rtOp     stackOp   // newly scanned operator

//line mmixal/mmixal.w:2230
	forwardLocalHost, backwardLocalHost [10]trieNode
	forwardLocal, backwardLocal         [10]symNode

//line mmixal/mmixal.w:2667
	opcode Tetra // numeric code for \MMIX\ operation or \MMIXAL\ pseudo-op
	opBits Tetra // flags describing an operator's special characteristics

//line mmixal/mmixal.w:3031
	z, y, x, yz, xyz Tetra // pieces for assembly
	futureBits       int   // places where there are future references

//line mmixal/mmixal.w:3377
	gregVal [256]Octa // initial values of global registers

//line mmixal/mmixal.w:3576
	stderr      io.Writer     // where error messages are written
	srcFileName string        // name of the \MMIXAL\ input file
	objFileName string        // name of the binary output file
	listingName string        // name of the optional listing file
	srcFile     *bufio.Reader // the input file
	objFile     *bufio.Writer // the binary output file
	listingFile *bufio.Writer // the listing file; |nil| if none
	expanding   bool          // are we expanding instructions when base address fail?
	bufSize     int           // maximum number of characters per line of input

//line mmixal/mmixal.w:3619
	greg    int // global register allocator
	curGreg int // global register just allocated
	lreg    int // local register allocator

//line mmixal/mmixal.w:827
}

//line mmixal/mmixal.w:1094
type bypassSignal struct{} // a signal to skip the rest of the current instruction
type fatalSignal struct{}  // a signal to end the assembly

//line mmixal/mmixal.w:1354
type trieNode struct {
	ch               uint16    // the (possibly wyde) character stored here
	left, mid, right *trieNode // downward in a ternary trie
	sym              *symNode  // equivalents of symbols
}

//line mmixal/mmixal.w:1429
type symNode struct {
	serial int      // serial number of symbol; type number for fixups
	link   *symNode // |defined| status or link to fixup
	equiv  Octa     // the equivalent value
}

//line mmixal/mmixal.w:1513
type opSpec struct {
	name string // symbolic opcode
	code Tetra  // numeric opcode
	bits Tetra  // treatment of operands
}

//line mmixal/mmixal.w:1679
type predefSpec struct {
	name string
	h, l Tetra
}

//line mmixal/mmixal.w:1990
type stackOp int

//line mmixal/mmixal.w:1991
type prec int

//line mmixal/mmixal.w:1992
type stat int

//line mmixal/mmixal.w:1993
type valNode struct {
	equiv  Octa      // current value
	link   *trieNode // trie reference for symbol
	status stat      // |pure|, |regVal|, |undefined|
}

//line mmixal/mmixal.w:559
const mm = 0x98 // the escape code of loader commands

//line mmixal/mmixal.w:741
const (
	lopQuote = 0x0 // the quotation lopcode
	lopLoc   = 0x1 // the location lopcode
	lopSkip  = 0x2 // the skip lopcode
	lopFixo  = 0x3 // the octabyte-fix lopcode
	lopFixr  = 0x4 // the relative-fix lopcode
	lopFixrx = 0x5 // extended relative-fix lopcode
	lopFile  = 0x6 // the file name lopcode
	lopLine  = 0x7 // the file position lopcode
	lopSpec  = 0x8 // the special hook lopcode
	lopPre   = 0x9 // the preamble lopcode
	lopPost  = 0xa // the postamble lopcode
	lopStab  = 0xb // the symbol table lopcode
	lopEnd   = 0xc // the end-it-all lopcode
)

//line mmixal/mmixal.w:961
const filenameMax = 1024

//line mmixal/mmixal.w:1443
const (
	fixO   = 0 // |serial| code for octabyte fixup
	fixYZ  = 1 // |serial| code for relative fixup
	fixXYZ = 2 // |serial| code for \.{JMP} fixup
)

//line mmixal/mmixal.w:1486
const (
	relAddrBit  = 0x1      // is YZ or XYZ relative?
	immedBit    = 0x2      // should opcode be immediate if Z or YZ not register?
	zarBit      = 0x4      // should register status of Z be ignored?
	zrBit       = 0x8      // must Z be a register?
	yarBit      = 0x10     // should register status of Y be ignored?
	yrBit       = 0x20     // must Y be a register?
	xarBit      = 0x40     // should register status of X be ignored?
	xrBit       = 0x80     // must X be a register?
	yzarBit     = 0x100    // should register status of YZ be ignored?
	yzrBit      = 0x200    // must YZ be a register?
	xyzarBit    = 0x400    // should register status of XYZ be ignored?
	xyzrBit     = 0x800    // must XYZ be a register?
	oneArgBit   = 0x1000   // is it OK to have zero or one operand?
	twoArgBit   = 0x2000   // is it OK to have exactly two operands?
	threeArgBit = 0x4000   // is it OK to have exactly three operands?
	manyArgBit  = 0x8000   // is it OK to have more than three operands?
	alignBits   = 0x30000  // how much alignment: byte, wyde, tetra, or octa?
	noLabelBit  = 0x40000  // should the label be blank?
	memBit      = 0x80000  // must YZ be a memory reference?
	specBit     = 0x100000 // is this opcode allowed in \.{SPEC} mode?
)

//line mmixal/mmixal.w:1520
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

//line mmixal/mmixal.w:1533
)

//line mmixal/mmixal.w:2000
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

//line mmixal/mmixal.w:2020
)

const (
	zero prec = iota
	weak
	strong
	unary

//line mmixal/mmixal.w:2027
)

const (
	pure stat = iota
	regVal
	undefined

//line mmixal/mmixal.w:2033
)

//line mmixal/mmixal.w:3245
const (
	SETH = 0xe0
	SETL = 0xe3
	ORH  = 0xe8
	ORL  = 0xeb

//line mmixal/mmixal.w:3250
)

//line mmixal/mmixal.w:1436
var (
	defined    = new(symNode) // code value for octabyte equivalents
	register   = new(symNode) // code value for register-number equivalents
	predefined = new(symNode) // code value for not-yet-used predefined equivalents
)

//line mmixal/mmixal.w:1549
var opInitTable = []opSpec{

//line mmixal/mmixal.w:1554
	{"TRAP", 0x00, 0x27554}, {"FCMP", 0x01, 0x240a8}, {"FUN", 0x02, 0x240a8}, {"FEQL", 0x03, 0x240a8},

	{"FADD", 0x04, 0x240a8}, {"FIX", 0x05, 0x26288}, {"FSUB", 0x06, 0x240a8}, {"FIXU", 0x07, 0x26288},

	{"FLOT", 0x08, 0x26282}, {"FLOTU", 0x0a, 0x26282}, {"SFLOT", 0x0c, 0x26282}, {"SFLOTU", 0x0e, 0x26282},

	{"FMUL", 0x10, 0x240a8}, {"FCMPE", 0x11, 0x240a8}, {"FUNE", 0x12, 0x240a8}, {"FEQLE", 0x13, 0x240a8},

	{"FDIV", 0x14, 0x240a8}, {"FSQRT", 0x15, 0x26288}, {"FREM", 0x16, 0x240a8}, {"FINT", 0x17, 0x26288},

	{"MUL", 0x18, 0x240a2}, {"MULU", 0x1a, 0x240a2}, {"DIV", 0x1c, 0x240a2}, {"DIVU", 0x1e, 0x240a2},

	{"ADD", 0x20, 0x240a2}, {"ADDU", 0x22, 0x240a2}, {"SUB", 0x24, 0x240a2}, {"SUBU", 0x26, 0x240a2},

	{"2ADDU", 0x28, 0x240a2}, {"4ADDU", 0x2a, 0x240a2}, {"8ADDU", 0x2c, 0x240a2}, {"16ADDU", 0x2e, 0x240a2},

//line mmixal/mmixal.w:1572
	{"CMP", 0x30, 0x240a2}, {"CMPU", 0x32, 0x240a2}, {"NEG", 0x34, 0x26082}, {"NEGU", 0x36, 0x26082},

	{"SL", 0x38, 0x240a2}, {"SLU", 0x3a, 0x240a2}, {"SR", 0x3c, 0x240a2}, {"SRU", 0x3e, 0x240a2},

	{"BN", 0x40, 0x22081}, {"BZ", 0x42, 0x22081}, {"BP", 0x44, 0x22081}, {"BOD", 0x46, 0x22081},

	{"BNN", 0x48, 0x22081}, {"BNZ", 0x4a, 0x22081}, {"BNP", 0x4c, 0x22081}, {"BEV", 0x4e, 0x22081},

	{"PBN", 0x50, 0x22081}, {"PBZ", 0x52, 0x22081}, {"PBP", 0x54, 0x22081}, {"PBOD", 0x56, 0x22081},

	{"PBNN", 0x58, 0x22081}, {"PBNZ", 0x5a, 0x22081}, {"PBNP", 0x5c, 0x22081}, {"PBEV", 0x5e, 0x22081},

	{"CSN", 0x60, 0x240a2}, {"CSZ", 0x62, 0x240a2}, {"CSP", 0x64, 0x240a2}, {"CSOD", 0x66, 0x240a2},

	{"CSNN", 0x68, 0x240a2}, {"CSNZ", 0x6a, 0x240a2}, {"CSNP", 0x6c, 0x240a2}, {"CSEV", 0x6e, 0x240a2},

//line mmixal/mmixal.w:1590
	{"ZSN", 0x70, 0x240a2}, {"ZSZ", 0x72, 0x240a2}, {"ZSP", 0x74, 0x240a2}, {"ZSOD", 0x76, 0x240a2},

	{"ZSNN", 0x78, 0x240a2}, {"ZSNZ", 0x7a, 0x240a2}, {"ZSNP", 0x7c, 0x240a2}, {"ZSEV", 0x7e, 0x240a2},

	{"LDB", 0x80, 0xa60a2}, {"LDBU", 0x82, 0xa60a2}, {"LDW", 0x84, 0xa60a2}, {"LDWU", 0x86, 0xa60a2},

	{"LDT", 0x88, 0xa60a2}, {"LDTU", 0x8a, 0xa60a2}, {"LDO", 0x8c, 0xa60a2}, {"LDOU", 0x8e, 0xa60a2},

	{"LDSF", 0x90, 0xa60a2}, {"LDHT", 0x92, 0xa60a2}, {"CSWAP", 0x94, 0xa60a2}, {"LDUNC", 0x96, 0xa60a2},

	{"LDVTS", 0x98, 0xa60a2}, {"PRELD", 0x9a, 0xa6022}, {"PREGO", 0x9c, 0xa6022}, {"GO", 0x9e, 0xa60a2},

	{"STB", 0xa0, 0xa60a2}, {"STBU", 0xa2, 0xa60a2}, {"STW", 0xa4, 0xa60a2}, {"STWU", 0xa6, 0xa60a2},

	{"STT", 0xa8, 0xa60a2}, {"STTU", 0xaa, 0xa60a2}, {"STO", 0xac, 0xa60a2}, {"STOU", 0xae, 0xa60a2},

//line mmixal/mmixal.w:1608
	{"STSF", 0xb0, 0xa60a2}, {"STHT", 0xb2, 0xa60a2}, {"STCO", 0xb4, 0xa6022}, {"STUNC", 0xb6, 0xa60a2},

	{"SYNCD", 0xb8, 0xa6022}, {"PREST", 0xba, 0xa6022}, {"SYNCID", 0xbc, 0xa6022}, {"PUSHGO", 0xbe, 0xa6062},

	{"OR", 0xc0, 0x240a2}, {"ORN", 0xc2, 0x240a2}, {"NOR", 0xc4, 0x240a2}, {"XOR", 0xc6, 0x240a2},

	{"AND", 0xc8, 0x240a2}, {"ANDN", 0xca, 0x240a2}, {"NAND", 0xcc, 0x240a2}, {"NXOR", 0xce, 0x240a2},

	{"BDIF", 0xd0, 0x240a2}, {"WDIF", 0xd2, 0x240a2}, {"TDIF", 0xd4, 0x240a2}, {"ODIF", 0xd6, 0x240a2},

	{"MUX", 0xd8, 0x240a2}, {"SADD", 0xda, 0x240a2}, {"MOR", 0xdc, 0x240a2}, {"MXOR", 0xde, 0x240a2},

	{"SETH", 0xe0, 0x22080}, {"SETMH", 0xe1, 0x22080}, {"SETML", 0xe2, 0x22080}, {"SETL", 0xe3, 0x22080},

	{"INCH", 0xe4, 0x22080}, {"INCMH", 0xe5, 0x22080}, {"INCML", 0xe6, 0x22080}, {"INCL", 0xe7, 0x22080},

//line mmixal/mmixal.w:1626
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

//line mmixal/mmixal.w:1551
}

//line mmixal/mmixal.w:1673
var specialName = [32]string{"rB", "rD", "rE", "rH", "rJ", "rM", "rR", "rBB",
	"rC", "rN", "rO", "rS", "rI", "rT", "rTT", "rK", "rQ", "rU", "rV", "rG", "rL",
	"rA", "rF", "rP", "rW", "rX", "rY", "rZ", "rWW", "rXX", "rYY", "rZZ"}

//line mmixal/mmixal.w:1688
var predefs = []predefSpec{
	{"ROUND_CURRENT", 0, 0}, {"ROUND_OFF", 0, 1}, {"ROUND_UP", 0, 2},
	{"ROUND_DOWN", 0, 3}, {"ROUND_NEAR", 0, 4},

//line mmixal/mmixal.w:1693
	{"Inf", 0x7ff00000, 0},

	{"Data_Segment", 0x20000000, 0}, {"Pool_Segment", 0x40000000, 0},
	{"Stack_Segment", 0x60000000, 0},

//line mmixal/mmixal.w:1699
	{"D_BIT", 0, 0x80}, {"V_BIT", 0, 0x40}, {"W_BIT", 0, 0x20}, {"I_BIT", 0, 0x10},
	{"O_BIT", 0, 0x08}, {"U_BIT", 0, 0x04}, {"Z_BIT", 0, 0x02}, {"X_BIT", 0, 0x01},

//line mmixal/mmixal.w:1703
	{"D_Handler", 0, 0x10}, {"V_Handler", 0, 0x20}, {"W_Handler", 0, 0x30},
	{"I_Handler", 0, 0x40}, {"O_Handler", 0, 0x50}, {"U_Handler", 0, 0x60},
	{"Z_Handler", 0, 0x70}, {"X_Handler", 0, 0x80},

//line mmixal/mmixal.w:1709
	{"StdIn", 0, 0}, {"StdOut", 0, 1}, {"StdErr", 0, 2},

	{"TextRead", 0, 0}, {"TextWrite", 0, 1}, {"BinaryRead", 0, 2},
	{"BinaryWrite", 0, 3}, {"BinaryReadWrite", 0, 4},

	{"Halt", 0, 0}, {"Fopen", 0, 1}, {"Fclose", 0, 2}, {"Fread", 0, 3},
	{"Fgets", 0, 4}, {"Fgetws", 0, 5}, {"Fwrite", 0, 6}, {"Fputs", 0, 7},
	{"Fputws", 0, 8}, {"Fseek", 0, 9}, {"Ftell", 0, 10},

//line mmixal/mmixal.w:1719
}

//line mmixal/mmixal.w:2056
var precedence = [...]prec{unary, unary, unary, unary, zero,
	weak, weak, strong, strong, strong, strong, strong, strong, strong, weak, weak,
	zero, zero, zero}

//line mmixal/mmixal.w:874
func cstrlen(b []byte) int {
	for i, c := range b {
		if c == 0 {
			return i
		}
	}
	return len(b)
}

func cstr(b []byte) string { return string(b[:cstrlen(b)]) }

//line mmixal/mmixal.w:975
func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}

//line mmixal/mmixal.w:978
func isDigit(c byte) bool { return '0' <= c && c <= '9' }

//line mmixal/mmixal.w:979
func isXDigit(c byte) bool { return isDigit(c) || 'a' <= c && c <= 'f' || 'A' <= c && c <= 'F' }

//line mmixal/mmixal.w:992
func (a *assembler) flushListingLine(s string) {
	if a.lineListed {
		fmt.Fprintf(a.listingFile, "\n")
	} else {
		fmt.Fprintf(a.listingFile, "%s%s\n", s, cstr(a.buffer))
		a.lineListed = true
	}
}

//line mmixal/mmixal.w:1018
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

//line mmixal/mmixal.w:1053
		if (a.curLoc^a.listingLoc)&^0xfff != 0 {
			fmt.Fprintf(a.listingFile, "%016x:", a.curLoc&^3|Octa(k))
			a.flushListingLine("  ")
		}
		a.listingLoc = a.curLoc&^3 | Octa(k)

//line mmixal/mmixal.w:1029
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

//line mmixal/mmixal.w:1076
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

//line mmixal/mmixal.w:1101
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

//line mmixal/mmixal.w:1124
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

//line mmixal/mmixal.w:1117
	}
	if message[0] == '!' {
		panic(fatalSignal{})
	}
}

//line mmixal/mmixal.w:1148
func (a *assembler) mmoWrite(buf []byte) {
	if _, err := a.objFile.Write(buf); err != nil {
		a.fatal("Can't write on %s", a.objFileName)

	}
}

//line mmixal/mmixal.w:1160
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

//line mmixal/mmixal.w:1190
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

func (a *assembler) mmoLop(x, y, z byte) { // output a loader operation
	a.mmoBuf = [4]byte{mm, x, y, z}
	a.mmoOut()
}

func (a *assembler) mmoLopp(x byte, yz uint16) { // output a loader operation with two-byte operand
	a.mmoBuf = [4]byte{mm, x, byte(yz >> 8), byte(yz)}
	a.mmoOut()
}

//line mmixal/mmixal.w:1219
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

//line mmixal/mmixal.w:1244
func (a *assembler) mmoSync() {
	if a.curFile != a.mmoCurFile {
		if a.filenamePassed[a.curFile] {
			a.mmoLop(lopFile, byte(a.curFile), 0)
		} else {

//line mmixal/mmixal.w:1266
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

//line mmixal/mmixal.w:1250
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

//line mmixal/mmixal.w:1298
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

//line mmixal/mmixal.w:1340
		if (a.curLoc^a.mmoCurLoc)&^3 != 0 {
			a.mmoLoc()
		}

//line mmixal/mmixal.w:1315
		if a.heldBits == 0 && a.curLoc>>61 == 0 {
			a.mmoSync()
		}
	}

//line mmixal/mmixal.w:1328
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

//line mmixal/mmixal.w:1320
	if a.specMode {
		a.specModeLoc += Tetra(k)
	} else {
		a.curLoc += Octa(k)
	}
}

//line mmixal/mmixal.w:1380
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

//line mmixal/mmixal.w:1454
func (a *assembler) newSymNode(serialize bool) *symNode {
	p := new(symNode)
	if serialize {
		a.serialNumber++
		p.serial = a.serialNumber
	}
	return p
}

//line mmixal/mmixal.w:1776
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

//line mmixal/mmixal.w:1809
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

//line mmixal/mmixal.w:1839
		switch {
		case t.sym.link == register:
			m += 0xf
		case t.sym.link == defined:

//line mmixal/mmixal.w:1907
			h := Tetra(t.sym.equiv >> 32)
			x := h
			if h&0xffff0000 == 0x20000000 {
				m += 8
				x = h - 0x20000000 // data segment
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

//line mmixal/mmixal.w:1844
		case t.sym.link != nil || t.sym.serial == 1:

//line mmixal/mmixal.w:1949
			c := byte(t.ch)
			if m&0x80 != 0 {
				c = '?' // Unicode? not yet
			}
			fmt.Fprintf(a.stderr, "undefined symbol: %s\n", string(append(a.symBuf, c))[1:])

			a.errCount++
			m += 2

//line mmixal/mmixal.w:1846
		}

//line mmixal/mmixal.w:1825
	}
	a.mmoByte(byte(m))
	if t.left != nil {
		a.outStab(t.left)
	}
	if m&0x2f != 0 {

//line mmixal/mmixal.w:1855
		if m&0x80 != 0 {
			a.mmoByte(byte(t.ch >> 8))
		}
		a.mmoByte(byte(t.ch))
		if m&0x80 != 0 {
			a.symBuf = append(a.symBuf, '?') // Unicode? not yet
		} else {
			a.symBuf = append(a.symBuf, byte(t.ch))
		}
		m &= 0xf
		if m != 0 && t.sym.link != nil {
			if a.listingFile != nil {

//line mmixal/mmixal.w:1934
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

//line mmixal/mmixal.w:1868
			}

//line mmixal/mmixal.w:1881
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

//line mmixal/mmixal.w:1870
		}
		if t.mid != nil {
			a.outStab(t.mid)
		}
		a.symBuf = a.symBuf[:len(a.symBuf)-1]

//line mmixal/mmixal.w:1832
	}
	if t.right != nil {
		a.outStab(t.right)
	}
}

//line mmixal/mmixal.w:2040
func (a *assembler) topOp() stackOp { return a.opStack[a.opPtr-1] }

//line mmixal/mmixal.w:2041
func (a *assembler) topVal() *valNode { return &a.valStack[a.valPtr-1] }

//line mmixal/mmixal.w:2042
func (a *assembler) nextVal() *valNode { return &a.valStack[a.valPtr-2] }

//line mmixal/mmixal.w:2488
func (a *assembler) binaryCheck(verb string) {
	if a.topVal().status != pure || a.nextVal().status != pure {
		a.derr("can %s pure values only", verb)
	}
}

//line mmixal/mmixal.w:3524
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

//line mmixal/mmixal.w:3417
func mmixal(args []string, stderr io.Writer, now int64) (code int) {
	a := &assembler{stderr: stderr, greg: 255, lreg: 32}
	var j, k int // all-purpose integers
	var files []*os.File

//line mmixal/mmixal.w:969
	var p int // the place where we're currently scanning

//line mmixal/mmixal.w:1660
	var tt *trieNode
	var pp, qq *symNode

//line mmixal/mmixal.w:2061
	var acc Octa // temporary accumulator

//line mmixal/mmixal.w:3422
	defer func() {
		if r := recover(); r != nil {
			if r != (fatalSignal{}) {
				panic(r)
			}
			code = -2
		}

//line mmixal/mmixal.w:3459
		if a.objFile != nil {
			a.objFile.Flush()
		}
		if a.listingFile != nil {
			a.listingFile.Flush()
		}
		for _, f := range files {
			f.Close()
		}

//line mmixal/mmixal.w:3430
	}()

//line mmixal/mmixal.w:3478
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

//line mmixal/mmixal.w:3499
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

//line mmixal/mmixal.w:3489
	}
	if j != len(args)-1 {
		fmt.Fprintf(stderr, "Usage: %s %s sourcefilename\n",

			args[0], "[-x] [-l listingname] [-b buffersize] [-o objectfilename]")
		return -1
	}
	a.srcFileName = args[j]

//line mmixal/mmixal.w:3432

//line mmixal/mmixal.w:816
	if a.bufSize < 72 {
		a.bufSize = 72
	}
	a.buffer = make([]byte, a.bufSize+2)

//line mmixal/mmixal.w:1474
	a.trieRoot = &trieNode{ch: ':'}
	a.curPrefix = a.trieRoot
	a.opRoot = &trieNode{ch: '^'}
	a.trieRoot.mid = a.opRoot

//line mmixal/mmixal.w:1651
	for _, op := range opInitTable {
		tt, _ = trieSearch(a.opRoot, []byte(op.name), 0)
		pp = a.newSymNode(false)
		tt.sym = pp
		pp.link = predefined
		pp.equiv = Octa(op.code)<<32 | Octa(op.bits)
	}

//line mmixal/mmixal.w:1664
	for j, name := range specialName {
		tt, _ = trieSearch(a.trieRoot, []byte(name), 0)
		pp = a.newSymNode(false)
		tt.sym = pp
		pp.link = predefined
		pp.equiv = Octa(j)
	}

//line mmixal/mmixal.w:1723
	for _, d := range predefs {
		tt, _ = trieSearch(a.trieRoot, []byte(d.name), 0)
		pp = a.newSymNode(false)
		tt.sym = pp
		pp.link = predefined
		pp.equiv = Octa(d.h)<<32 | Octa(d.l)
	}

//line mmixal/mmixal.w:1737
	tt, _ = trieSearch(a.trieRoot, []byte("Main"), 0)
	tt.sym = a.newSymNode(true)

//line mmixal/mmixal.w:2067
	a.opStack = make([]stackOp, a.bufSize+1)
	a.valStack = make([]valNode, a.bufSize+1)

//line mmixal/mmixal.w:2237
	for j = 0; j < 10; j++ {
		a.forwardLocalHost[j].sym = &a.forwardLocal[j]
		a.backwardLocalHost[j].sym = &a.backwardLocal[j]
		a.backwardLocal[j].link = defined
	}

//line mmixal/mmixal.w:3548
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

//line mmixal/mmixal.w:3588
	a.filename = []string{a.srcFileName}

//line mmixal/mmixal.w:3592
	a.mmoLop(lopPre, 1, 1)
	a.mmoTetra(Tetra(now))
	a.mmoCurFile = -1

//line mmixal/mmixal.w:3433
	for {

//line mmixal/mmixal.w:841
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
			a.buffer[j-1] = 0 // remove the newline
		} else if c, err := a.srcFile.ReadByte(); err == nil {

//line mmixal/mmixal.w:890
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

//line mmixal/mmixal.w:864
		}
		if a.buffer[0] == '#' {

//line mmixal/mmixal.w:923
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
				if a.buffer[p] == '"' && a.buffer[p-1] != '"' { // yes, it's a line directive

//line mmixal/mmixal.w:945
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

//line mmixal/mmixal.w:941
				}
			}

//line mmixal/mmixal.w:867
		}
		a.bufPtr = 0

//line mmixal/mmixal.w:3435
		for {

//line mmixal/mmixal.w:2566
			func() {
				defer func() {
					if r := recover(); r != nil && r != (bypassSignal{}) {
						panic(r)
					}
				}()
				p = a.bufPtr
				a.bufPtr = len(a.buffer) - 1 // empty string

//line mmixal/mmixal.w:2610
				if a.buffer[p] == 0 {
					return
				}
				a.labField = a.labField[:0]
				if !isSpace(a.buffer[p]) {
					if !isDigit(a.buffer[p]) && !isLetter(a.buffer[p]) {
						return // comment
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

//line mmixal/mmixal.w:2575

//line mmixal/mmixal.w:2639
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

//line mmixal/mmixal.w:2576

//line mmixal/mmixal.w:2675
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

//line mmixal/mmixal.w:2705
						a.operandList = append(a.operandList, a.buffer[p])
						for p++; a.buffer[p] != 0 && a.buffer[p] != '"'; p++ {
							a.operandList = append(a.operandList, a.buffer[p])
						}
						if a.buffer[p] == 0 {
							a.err("incomplete string constant")
						}

//line mmixal/mmixal.w:2695
					}
					a.operandList = append(a.operandList, a.buffer[p])
					p++
					if isSpace(a.buffer[p]) {
						break
					}
				}

//line mmixal/mmixal.w:2714
				for isSpace(a.buffer[p]) {
					p++
				}
				if a.buffer[p] == ';' {
					p++
				} else {
					p = len(a.buffer) - 1 // if not followed by semicolon, rest of the line is a comment
				}
				if len(a.operandList) == 0 {
					a.operandList = append(a.operandList, '0') // change empty operand field to `\.0'
				}
				a.operandList = append(a.operandList, 0)

//line mmixal/mmixal.w:2577
				a.bufPtr = p
				if a.specMode && a.opBits&specBit == 0 {
					a.derr("cannot use `%s' in special mode", a.opField)

				}
				if a.opBits&noLabelBit != 0 && len(a.labField) > 0 {
					a.derr("*label field of `%s' instruction is ignored", a.opField)
					a.labField = a.labField[:0]
				}

				if a.opBits&alignBits != 0 {

//line mmixal/mmixal.w:2731
					j = int((a.opBits & alignBits) >> 16)
					a.curLoc = (a.curLoc + Octa(1<<j-1)) &^ Octa(1<<j-1)

//line mmixal/mmixal.w:2589
				}

//line mmixal/mmixal.w:2086
				p = 0
				a.valPtr = 0                       // |valStack| is empty
				a.opStack[0], a.opPtr = outerLP, 1 // |opStack| contains an ``outer left parenthesis''
			scan:
				for {

//line mmixal/mmixal.w:2113
				open:
					for {
						c := a.operandList[p]
						switch {
						case isLetter(c):

//line mmixal/mmixal.w:2187
							if c == ':' {
								tt, p = trieSearch(a.trieRoot, a.operandList, p+1)
							} else {
								tt, p = trieSearch(a.curPrefix, a.operandList, p)
							}

//line mmixal/mmixal.w:2198
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

//line mmixal/mmixal.w:2119
						case isDigit(c):
							switch a.operandList[p+1] {
							case 'F':

//line mmixal/mmixal.w:2218
								tt = &a.forwardLocalHost[c-'0']
								p += 2

//line mmixal/mmixal.w:2198
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

//line mmixal/mmixal.w:2123
							case 'B':

//line mmixal/mmixal.w:2223
								tt = &a.backwardLocalHost[c-'0']
								p += 2

//line mmixal/mmixal.w:2198
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

//line mmixal/mmixal.w:2125
							default:

//line mmixal/mmixal.w:2280
								acc = Octa(c - '0')
								for p++; isDigit(a.operandList[p]); p++ {
									acc = acc + acc<<2
									acc = acc<<1 + Octa(a.operandList[p]-'0')
								}

//line mmixal/mmixal.w:2290
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal/mmixal.w:2127
							}
						default:
							p++
							switch c {
							case '#':

//line mmixal/mmixal.w:2296
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

//line mmixal/mmixal.w:2290
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal/mmixal.w:2133
							case '\'':

//line mmixal/mmixal.w:2246
								acc = Octa(a.operandList[p])
								p += 2

//line mmixal/mmixal.w:2290
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal/mmixal.w:2135
							case '"':

//line mmixal/mmixal.w:2261
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

//line mmixal/mmixal.w:2290
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal/mmixal.w:2137
							case '@':

//line mmixal/mmixal.w:2315
								acc = a.curLoc

//line mmixal/mmixal.w:2290
								a.valPtr++
								a.topVal().link = nil
								a.topVal().equiv = acc
								a.topVal().status = pure

//line mmixal/mmixal.w:2139

//line mmixal/mmixal.w:2148
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

//line mmixal/mmixal.w:2140
							default:

//line mmixal/mmixal.w:2172
								if p == 1 { // treat operand list as empty
									a.operandList[0], a.operandList[1], p = '0', 0, 0
									continue open
								}
								if a.operandList[p-1] != 0 {
									a.derr("syntax error at character `%s'", ch(a.operandList[p-1]))
								}
								a.derr("syntax error after character `%s'", ch(a.operandList[p-2]))

//line mmixal/mmixal.w:2142
							}
						}
						break
					}

//line mmixal/mmixal.w:2092
				close:
					for {

//line mmixal/mmixal.w:2323
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

//line mmixal/mmixal.w:2095
					reduce:
						for precedence[a.topOp()] >= precedence[a.rtOp] {

//line mmixal/mmixal.w:2373
							a.opPtr--
							switch op := a.opStack[a.opPtr]; {
							case op == innerLP:
								if a.rtOp == innerRP {
									continue close
								}
								a.err("*missing right parenthesis")

							case op == outerLP:
								if a.rtOp == outerRP {

//line mmixal/mmixal.w:2398
									if a.topVal().status == regVal && a.topVal().equiv > 0xff {
										a.err("*register number too large, will be reduced mod 256")

										a.topVal().equiv &= 0xff
									}
									if a.operandList[p-1] == 0 {
										break scan
									}
									a.rtOp = outerLP // comma
									break reduce

//line mmixal/mmixal.w:2384
								}
								a.opPtr++
								a.err("*missing left parenthesis")

								continue close
							case op < innerLP:

//line mmixal/mmixal.w:2450
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

//line mmixal/mmixal.w:2391
								a.topVal().link = nil
							default:

//line mmixal/mmixal.w:2429
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

//line mmixal/mmixal.w:2495
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

//line mmixal/mmixal.w:2526
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

//line mmixal/mmixal.w:2444
								}

//line mmixal/mmixal.w:2394

//line mmixal/mmixal.w:2420
								if a.topVal().status == a.nextVal().status {
									a.nextVal().status = pure
								} else {
									a.nextVal().status = regVal
								}
								a.valPtr--
								a.topVal().link = nil

//line mmixal/mmixal.w:2395
							}

//line mmixal/mmixal.w:2098
						}
						break
					}
					a.opStack[a.opPtr] = a.rtOp
					a.opPtr++
				}

//line mmixal/mmixal.w:2591
				if a.opcode == GREG {

//line mmixal/mmixal.w:2738
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

//line mmixal/mmixal.w:2593
				}
				if len(a.labField) > 0 {

//line mmixal/mmixal.w:2771
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

//line mmixal/mmixal.w:2842
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

//line mmixal/mmixal.w:2798
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

//line mmixal/mmixal.w:2861
							qq = pp.link
							pp.link = qq.link
							a.mmoLoc()
							if qq.serial == fixO {

//line mmixal/mmixal.w:2871
								if (qq.equiv>>32)&0xffffff != 0 {
									a.mmoLop(lopFixo, 0, 2)
									a.mmoTetra(Tetra(qq.equiv >> 32))
								} else {
									a.mmoLop(lopFixo, byte(qq.equiv>>56), 1)
								}
								a.mmoTetra(Tetra(qq.equiv))

//line mmixal/mmixal.w:2866
							} else {

//line mmixal/mmixal.w:2885
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

//line mmixal/mmixal.w:2868
							}

//line mmixal/mmixal.w:2820
						}
					}

//line mmixal/mmixal.w:2787
					if isDigit(a.labField[0]) {
						pp = &a.backwardLocal[a.labField[0]-'0']
					}
					pp.equiv, pp.link = a.curLoc, newLink

//line mmixal/mmixal.w:2828
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

//line mmixal/mmixal.w:2792
					if a.listingFile != nil && (a.opcode == IS || a.opcode == LOC) {

//line mmixal/mmixal.w:2912
						if newLink == defined {
							fmt.Fprintf(a.listingFile, "(%016x)", a.curLoc)
							a.flushListingLine(" ")
						} else {
							fmt.Fprintf(a.listingFile, "($%03d)", Tetra(a.curLoc)&0xff)
							a.flushListingLine("             ")
						}

//line mmixal/mmixal.w:2794
					}
					a.curLoc = acc

//line mmixal/mmixal.w:2596
				}

//line mmixal/mmixal.w:2930
				a.futureBits = 0
				if a.opBits&manyArgBit != 0 {

//line mmixal/mmixal.w:2980
					for j = 0; j < a.valPtr; j++ {
						v := &a.valStack[j]

//line mmixal/mmixal.w:3007
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

//line mmixal/mmixal.w:2983
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

//line mmixal/mmixal.w:2933
					return
				}
				switch a.valPtr {
				case 1:
					if a.opBits&oneArgBit == 0 {
						a.derr("opcode `%s' needs more than one operand", a.opField)

					}

//line mmixal/mmixal.w:3256
					v := &a.valStack[0]
					switch {
					case v.status == undefined && a.opBits&relAddrBit != 0:

//line mmixal/mmixal.w:3299
						pp = v.link.sym
						qq = a.newSymNode(false)
						qq.link = pp.link
						pp.link = qq
						qq.serial = fixXYZ
						qq.equiv = a.curLoc
						a.xyz = 0
						a.futureBits = 0xe0

//line mmixal/mmixal.w:3260
					case v.status == pure && a.opBits&relAddrBit != 0:
						if a.opBits&xyzrBit != 0 {
							a.derr("*operand of `%s' should be a register number", a.opField)
						}

//line mmixal/mmixal.w:3309
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

//line mmixal/mmixal.w:3265
					default:

//line mmixal/mmixal.w:3281
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

//line mmixal/mmixal.w:3267
						if a.opcode > 0xff {

//line mmixal/mmixal.w:3338
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

//line mmixal/mmixal.w:3380
									if v.equiv != 0 {
										fmt.Fprintf(a.listingFile, "($%03d=#%08x", a.curGreg, Tetra(v.equiv>>32))
										a.flushListingLine("    ")
										fmt.Fprintf(a.listingFile, "         %08x)", Tetra(v.equiv))
										a.flushListingLine(" ")
									} else {
										fmt.Fprintf(a.listingFile, "($%03d)", a.curGreg)
										a.flushListingLine("             ")
									}

//line mmixal/mmixal.w:3350
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

//line mmixal/mmixal.w:3269
						}
						if v.equiv > 0xffffff {
							a.err("*XYZ field doesn't fit in three bytes")

						}
						a.xyz = Tetra(v.equiv) & 0xffffff
					}

//line mmixal/mmixal.w:2942
				case 2:

//line mmixal/mmixal.w:2963
					if a.opBits&twoArgBit == 0 {
						if a.opBits&oneArgBit != 0 {
							a.derr("opcode `%s' must not have two operands", a.opField)
						} else {
							a.derr("opcode `%s' must have more than two operands", a.opField)
						}
					}

//line mmixal/mmixal.w:2944
					if a.opBits&(threeArgBit|memBit) == threeArgBit {

//line mmixal/mmixal.w:2972
						a.valStack[2], a.valPtr = a.valStack[1], 3
						a.valStack[1] = valNode{equiv: 0, link: nil, status: pure}

//line mmixal/mmixal.w:2946

//line mmixal/mmixal.w:3038
						if a.valStack[2].status == undefined {
							a.err("Z field is undefined")

						}
						if a.valStack[2].status == regVal {
							if a.opBits&(immedBit|zrBit|zarBit) == 0 {
								a.derr("*Z field of `%s' should not be a register number", a.opField)

							}
						} else if a.opBits&immedBit != 0 {
							a.opcode++ // immediate
						} else if a.opBits&zrBit != 0 {
							a.derr("*Z field of `%s' should be a register number", a.opField)
						}
						if a.valStack[2].equiv > 0xff {
							a.err("*Z field doesn't fit in one byte")

						}
						a.z = Tetra(a.valStack[2].equiv) & 0xff

//line mmixal/mmixal.w:3059
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

//line mmixal/mmixal.w:3079
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

//line mmixal/mmixal.w:2947
					} else {

//line mmixal/mmixal.w:3108
						v := &a.valStack[1]
						switch {
						case v.status == undefined && a.opBits&relAddrBit != 0:

//line mmixal/mmixal.w:3157
							pp = v.link.sym
							qq = a.newSymNode(false)
							qq.link = pp.link
							pp.link = qq
							qq.serial = fixYZ
							qq.equiv = a.curLoc
							a.yz = 0
							a.futureBits = 0xc0

//line mmixal/mmixal.w:3112
						case v.status == undefined:
							a.err("YZ field is undefined")

						case v.status == pure && a.opBits&memBit != 0:

//line mmixal/mmixal.w:3194
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

//line mmixal/mmixal.w:3222
								for j = SETH; j <= ORL; j++ {
									switch j & 3 {
									case 0:
										a.yz = Tetra(o>>48) & 0xffff // \.{SETH}
									case 1:
										a.yz = Tetra(o>>32) & 0xffff // \.{SETMH} or \.{ORMH}
									case 2:
										a.yz = Tetra(o>>16) & 0xffff // \.{SETML} or \.{ORML}
									case 3:
										a.yz = Tetra(o) & 0xffff // \.{SETL} or \.{ORL}
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

//line mmixal/mmixal.w:3213
							}

//line mmixal/mmixal.w:3117
						default:
							if v.status == regVal {

//line mmixal/mmixal.w:3135
								if a.opBits&(immedBit|yzrBit|yzarBit) == 0 {
									a.derr("*YZ field of `%s' should not be a register number", a.opField)

								}
								if a.opcode == SET {
									v.equiv <<= 8
									a.opcode = 0xc1 // change to \.{OR}
								} else if a.opBits&memBit != 0 {
									v.equiv <<= 8
									a.opcode++ // silently append \.{,0}
								}

//line mmixal/mmixal.w:3120
							} else {

//line mmixal/mmixal.w:3148
								if a.opcode == SET {
									a.opcode = 0xe3 // change to \.{SETL}
								} else if a.opBits&immedBit != 0 {
									a.opcode++ // immediate
								} else if a.opBits&yzrBit != 0 {
									a.derr("*YZ field of `%s' should be a register number", a.opField)
								}

//line mmixal/mmixal.w:3122
							}
							if v.status == pure && a.opBits&relAddrBit != 0 {

//line mmixal/mmixal.w:3170
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

//line mmixal/mmixal.w:3125
							} else {
								if v.equiv > 0xffff {
									a.err("*YZ field doesn't fit in two bytes")

								}
								a.yz = Tetra(v.equiv) & 0xffff
							}
						}

//line mmixal/mmixal.w:2949

//line mmixal/mmixal.w:3079
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

//line mmixal/mmixal.w:2950
					}
				case 3:
					if a.opBits&threeArgBit == 0 {
						a.derr("opcode `%s' must not have three operands", a.opField)
					}

//line mmixal/mmixal.w:3038
					if a.valStack[2].status == undefined {
						a.err("Z field is undefined")

					}
					if a.valStack[2].status == regVal {
						if a.opBits&(immedBit|zrBit|zarBit) == 0 {
							a.derr("*Z field of `%s' should not be a register number", a.opField)

						}
					} else if a.opBits&immedBit != 0 {
						a.opcode++ // immediate
					} else if a.opBits&zrBit != 0 {
						a.derr("*Z field of `%s' should be a register number", a.opField)
					}
					if a.valStack[2].equiv > 0xff {
						a.err("*Z field doesn't fit in one byte")

					}
					a.z = Tetra(a.valStack[2].equiv) & 0xff

//line mmixal/mmixal.w:3059
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

//line mmixal/mmixal.w:3079
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

//line mmixal/mmixal.w:2956
				default:
					a.derr("too many operands for opcode `%s'", a.opField)

				}
				a.assemble(4, a.opcode<<24+a.xyz, byte(a.futureBits))

//line mmixal/mmixal.w:2598
			}()

//line mmixal/mmixal.w:3437
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

//line mmixal/mmixal.w:3600
	if a.lreg >= a.greg {
		a.fatal("Danger: Must reduce the number of GREGs by %d", a.lreg-a.greg+1)

	}

//line mmixal/mmixal.w:3627
	a.mmoLop(lopPost, 0, byte(a.greg))
	tt, _ = trieSearch(a.trieRoot, []byte("Main"), 0)
	a.gregVal[255] = tt.sym.equiv
	for j = a.greg; j < 256; j++ {
		a.mmoTetra(Tetra(a.gregVal[j] >> 32))
		a.mmoTetra(Tetra(a.gregVal[j]))
	}

//line mmixal/mmixal.w:1962
	a.opRoot.mid = nil // annihilate all the opcodes
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

//line mmixal/mmixal.w:3636
	for j = 0; j < 10; j++ {
		if a.forwardLocal[j].link != nil {
			a.errCount++
			fmt.Fprintf(stderr, "undefined local symbol %dF\n", j)

		}
	}

//line mmixal/mmixal.w:3607
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

//line mmixal/mmixal.w:3450
	return a.errCount
}

//line mmixal/mmixal.w:3454
func main() {
	os.Exit(mmixal(os.Args, os.Stderr, time.Now().Unix()))
}
