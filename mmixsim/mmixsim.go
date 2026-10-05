//line mmixsim.w:78
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"math/bits"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"

	"github.com/sjnam/go-mmix/mmixarith"
	"github.com/sjnam/go-mmix/mmixio"
)

//line mmixsim.w:139
type simulator struct {

//line mmixsim.w:151
	out    *bufio.Writer // 표준 출력
	stderr io.Writer     // 표준 오류
	stdin  *cfile        // 표준 입력
	io     *mmixio.IO    // 입출력 기본 연산들

//line mmixsim.w:721
	priority Tetra    // 의사 난수 시간 도장 계수기
	memRoot  *memNode // treap의 뿌리
	lastMem  *memNode // 가장 최근에 읽거나 쓴 메모리 노드
	sclock   Octa     // 모의 시계

//line mmixsim.w:851
	mmoFile *bufio.Reader // 입력 파일
	buf     [4]byte       // 가장 최근에 읽은 바이트들
	yzbytes int           // 가장 아래의 두 바이트
	tet     Tetra         // |buf|의 바이트들을 큰 쪽 먼저로 모은 것

//line mmixsim.w:965
	curFile int   // 가장 최근에 고른 파일 번호
	curLine int   // 0이 아니면, |curFile|에서의 현재 위치
	objTime Tetra // 목적 파일을 만든 시각

//line mmixsim.w:1153
	fileInfo [256]fileNode // 원시 파일마다의 데이터
	bufSize  int           // 원시 줄 버퍼의 크기
	buffer   []Char

//line mmixsim.w:1289
	srcFile              *cfile // 지금 열려 있는 원시 파일
	shownFile            int    // 가장 최근에 나열한 파일의 번호
	shownLine            int32  // |shownFile|에서 가장 최근에 나열한 줄
	gap                  int32  // 잇달아 나열하는 원시 줄 사이의 최소 빈틈
	lineShown            bool   // 최근에 무언가를 나열했는가?
	showingSource        bool   // 원시 줄을 나열하고 있는가?
	profileGap           int32  // 마지막 빈도수를 찍을 때의 |gap|
	profileShowingSource bool   // 마지막 빈도수를 찍을 때의 |showingSource|

//line mmixsim.w:1379
	impliedLoc     Octa // 마지막으로 보인 빈도 데이터 다음의 위치
	profileStarted bool // 빈도수를 하나라도 찍었는가?

//line mmixsim.w:1558
	instPtr            Octa  // 다음 명령의 위치
	tracingExceptions  int   // 추적하게 하는 예외 비트들
	halted             bool  // 프로그램이 멈추었는가?
	breakpoint         bool  // 현재 명령 다음에 쉬어야 하는가?
	tracing            bool  // 현재 명령을 추적해야 하는가?
	stackTracing       bool  // 레지스터 스택의 자세한 사정을 추적해야 하는가?
	interacting        bool  // 대화 방식에 있는가?
	interactAfterBreak bool  // 대화 방식으로 들어가야 하는가?
	traceThreshold     Tetra // 명령마다 이만큼 추적한다

//line mmixsim.w:2019
	g         [256]Octa // 전역 레지스터
	l         []Octa    // 지역 레지스터
	lringSize int       // 지역 레지스터의 개수(2의 거듭제곱)
	lringMask int       // |lringSize|보다 하나 작은 수
	S         int       // $\rm rS/8$과 |lringSize|를 법으로 합동

//line mmixsim.w:3254
	stdinBuf      [256]byte // 모의 프로그램의 표준 입력
	stdinBufStart int       // 그 버퍼에서의 현재 위치
	stdinBufEnd   int       // 그 버퍼의 현재 끝

//line mmixsim.w:3410
	showingStats bool // 추적하는 명령마다 통계도 보여 주어야 하는가?

//line mmixsim.w:3645
	goodGuesses, badGuesses int32 // 분기 예측 통계

//line mmixsim.w:3852
	myself    string        // |args[0]|, 곧 이 시뮬레이터의 이름
	interrupt atomic.Bool   // 사용자가 최근에 시뮬레이션을 가로막았는가?
	profiling bool          // 끝날 때 프로파일을 찍어야 하는가?
	fakeStdin *os.File      // 모의 \.{StdIn} 대신 쓰는 파일
	dumpFile  *bufio.Writer // 이진 덤프에 쓰는 파일
	dumpOS    *os.File      // |dumpFile| 밑의 파일

//line mmixsim.w:4086
	commandBuf [commandBufSize + 2]byte

//line mmixsim.w:4183
	val Octa // 대화 명령이 넣을 값

//line mmixsim.w:141
}

type exitSignal int // 이 종료 코드로 프로그램을 끝내라는 신호

//line mmixsim.w:589
type (
	Tetra = mmixarith.Tetra // 부호 없는 32비트 정수
	Octa  = mmixarith.Octa  // 두 테트라바이트가 모여 옥타바이트를 이룬다
)

//line mmixsim.w:682
type memTetra struct {
	tet    Tetra  // 모의 메모리의 테트라바이트
	freq   Tetra  // 그것을 명령으로 실행한 횟수
	bkpt   byte   // 이 테트라바이트의 멈춤점 정보
	fileNo byte   // 알려져 있다면, 원시 파일 번호
	lineNo uint16 // 알려져 있다면, 원시 줄 번호
}

type memNode struct {
	loc         Octa          // 모의 테트라바이트 512개 가운데 첫째의 위치
	stamp       Tetra         // treap의 균형을 위한 시간 도장
	left, right *memNode      // 부분 나무를 가리키는 포인터
	dat         [512]memTetra // 모의 테트라바이트의 덩이
}

//line mmixsim.w:1140
type fileNode struct {
	name      []byte  // 원시 파일의 이름
	lineCount int     // 파일의 줄 수
	lineMap   []int64 // 줄마다의 파일 위치를 적은 지도
}

//line mmixsim.w:1150
type Char = byte // 언젠가 와이드가 될 바이트들

//line mmixsim.w:1593
type opInfo struct {
	name         string // 연산 코드의 기호 이름
	flags        byte   // 명령의 형식
	thirdOperand byte   // 입력으로 쓰는 특수 레지스터
	mems         byte   // $\mu$를 몇 번 쓰는가
	oops         byte   // $\upsilon$를 몇 번 쓰는가
	traceFormat  string // 추적할 때 어떻게 보이는가
}

//line mmixsim.w:3548
type fmtStyle int

const (
	decimal fmtStyle = iota
	hex
	zhex
	floating
	handle

//line mmixsim.w:3556
)

//line mmixsim.w:4617
type cfile struct {
	f   *os.File      // 읽는 파일; 표준 입력이면 |nil|
	r   *bufio.Reader // 읽기 버퍼
	pos int64         // |ftell|이 돌려줄 위치
	eof bool          // 파일 끝 표시(|feof|)
}

//line mmixsim.w:635
const (
	signBit = mmixarith.SignBit // 부호 비트
	negOne  = mmixarith.NegOne  // $-1$
)

//line mmixsim.w:807
const (
	mm       = 0x98 // \.{mmo} 형식의 탈출 코드
	lopQuote = 0x0  // 인용 lopcode
	lopLoc   = 0x1  // 위치 lopcode
	lopSkip  = 0x2  // 건너뛰기 lopcode
	lopFixo  = 0x3  // 옥타바이트 고치기 lopcode
	lopFixr  = 0x4  // 상대 주소 고치기 lopcode
	lopFixrx = 0x5  // 확장된 상대 주소 고치기 lopcode
	lopFile  = 0x6  // 파일 이름 lopcode
	lopLine  = 0x7  // 파일 위치 lopcode
	lopSpec  = 0x8  // 특수 고리 lopcode
	lopPre   = 0x9  // 서문 lopcode
	lopPost  = 0xa  // 후기 lopcode
	lopStab  = 0xb  // 기호표 lopcode
	lopEnd   = 0xc  // 모든 것을 끝내는 lopcode
)

//line mmixsim.w:1399
const (
	TRAP = iota
	FCMP
	FUN
	FEQL
	FADD
	FIX
	FSUB
	FIXU
//line mmixsim.w:1401
	FLOT
	FLOTI
	FLOTU
	FLOTUI
	SFLOT
	SFLOTI
	SFLOTU
	SFLOTUI
//line mmixsim.w:1402
	FMUL
	FCMPE
	FUNE
	FEQLE
	FDIV
	FSQRT
	FREM
	FINT
//line mmixsim.w:1403
	MUL
	MULI
	MULU
	MULUI
	DIV
	DIVI
	DIVU
	DIVUI
//line mmixsim.w:1404
	ADD
	ADDI
	ADDU
	ADDUI
	SUB
	SUBI
	SUBU
	SUBUI
//line mmixsim.w:1405
	IIADDU
	IIADDUI
	IVADDU
	IVADDUI
	VIIIADDU
	VIIIADDUI
	XVIADDU
	XVIADDUI
//line mmixsim.w:1406
	CMP
	CMPI
	CMPU
	CMPUI
	NEG
	NEGI
	NEGU
	NEGUI
//line mmixsim.w:1407
	SL
	SLI
	SLU
	SLUI
	SR
	SRI
	SRU
	SRUI
//line mmixsim.w:1408
	BN
	BNB
	BZ
	BZB
	BP
	BPB
	BOD
	BODB
//line mmixsim.w:1409
	BNN
	BNNB
	BNZ
	BNZB
	BNP
	BNPB
	BEV
	BEVB
//line mmixsim.w:1410
	PBN
	PBNB
	PBZ
	PBZB
	PBP
	PBPB
	PBOD
	PBODB
//line mmixsim.w:1411
	PBNN
	PBNNB
	PBNZ
	PBNZB
	PBNP
	PBNPB
	PBEV
	PBEVB
//line mmixsim.w:1412
	CSN
	CSNI
	CSZ
	CSZI
	CSP
	CSPI
	CSOD
	CSODI
//line mmixsim.w:1413
	CSNN
	CSNNI
	CSNZ
	CSNZI
	CSNP
	CSNPI
	CSEV
	CSEVI
//line mmixsim.w:1414
	ZSN
	ZSNI
	ZSZ
	ZSZI
	ZSP
	ZSPI
	ZSOD
	ZSODI
//line mmixsim.w:1415
	ZSNN
	ZSNNI
	ZSNZ
	ZSNZI
	ZSNP
	ZSNPI
	ZSEV
	ZSEVI
//line mmixsim.w:1416
	LDB
	LDBI
	LDBU
	LDBUI
	LDW
	LDWI
	LDWU
	LDWUI
//line mmixsim.w:1417
	LDT
	LDTI
	LDTU
	LDTUI
	LDO
	LDOI
	LDOU
	LDOUI
//line mmixsim.w:1418
	LDSF
	LDSFI
	LDHT
	LDHTI
	CSWAP
	CSWAPI
	LDUNC
	LDUNCI
//line mmixsim.w:1419
	LDVTS
	LDVTSI
	PRELD
	PRELDI
	PREGO
	PREGOI
	GO
	GOI
//line mmixsim.w:1420
	STB
	STBI
	STBU
	STBUI
	STW
	STWI
	STWU
	STWUI
//line mmixsim.w:1421
	STT
	STTI
	STTU
	STTUI
	STO
	STOI
	STOU
	STOUI
//line mmixsim.w:1422
	STSF
	STSFI
	STHT
	STHTI
	STCO
	STCOI
	STUNC
	STUNCI
//line mmixsim.w:1423
	SYNCD
	SYNCDI
	PREST
	PRESTI
	SYNCID
	SYNCIDI
	PUSHGO
	PUSHGOI
//line mmixsim.w:1424
	OR
	ORI
	ORN
	ORNI
	NOR
	NORI
	XOR
	XORI
//line mmixsim.w:1425
	AND
	ANDI
	ANDN
	ANDNI
	NAND
	NANDI
	NXOR
	NXORI
//line mmixsim.w:1426
	BDIF
	BDIFI
	WDIF
	WDIFI
	TDIF
	TDIFI
	ODIF
	ODIFI
//line mmixsim.w:1427
	MUX
	MUXI
	SADD
	SADDI
	MOR
	MORI
	MXOR
	MXORI
//line mmixsim.w:1428
	SETH
	SETMH
	SETML
	SETL
	INCH
	INCMH
	INCML
	INCL
//line mmixsim.w:1429
	ORH
	ORMH
	ORML
	ORL
	ANDNH
	ANDNMH
	ANDNML
	ANDNL
//line mmixsim.w:1430
	JMP
	JMPB
	PUSHJ
	PUSHJB
	GETA
	GETAB
	PUT
	PUTI
//line mmixsim.w:1431
	POP
	RESUME
	SAVE
	UNSAVE
	SYNC
	SWYM
	GET
	TRIP

//line mmixsim.w:1432
)

//line mmixsim.w:1437
const (
	rB = iota
	rD
	rE
	rH
	rJ
	rM
	rR
	rBB
//line mmixsim.w:1439
	rC
	rN
	rO
	rS
	rI
	rT
	rTT
	rK
	rQ
	rU
	rV
	rG
	rL
//line mmixsim.w:1440
	rA
	rF
	rP
	rW
	rX
	rY
	rZ
	rWW
	rXX
	rYY
	rZZ

//line mmixsim.w:1441
)

//line mmixsim.w:1452
const (
	xBit = mmixarith.XBit // 부동소수점 부정확
	zBit = mmixarith.ZBit // 부동소수점 0으로 나눔
	uBit = mmixarith.UBit // 부동소수점 아래넘침
	oBit = mmixarith.OBit // 부동소수점 넘침
	iBit = mmixarith.IBit // 부동소수점 잘못된 연산
	wBit = mmixarith.WBit // 부동소수점에서 고정소수점으로 바꿀 때 넘침
	vBit = mmixarith.VBit // 정수 넘침
	dBit = mmixarith.DBit // 정수 나눗셈 검사
	hBit = 1 << 16        // 트립
)

//line mmixsim.w:1468
const (
	traceBit = 1 << 3
	readBit  = 1 << 2
	writeBit = 1 << 1
	execBit  = 1 << 0

//line mmixsim.w:1473
)

//line mmixsim.w:1478
const (
	Halt = iota
	Fopen
	Fclose
	Fread
	Fgets
	Fgetws
//line mmixsim.w:1480
	Fwrite
	Fputs
	Fputws
	Fseek
	Ftell

//line mmixsim.w:1481
)

const maxSysCall = Ftell

//line mmixsim.w:1612
const (
	zIsImmedBit  = 0x1
	zIsSourceBit = 0x2
	yIsImmedBit  = 0x4
	yIsSourceBit = 0x8
	xIsSourceBit = 0x10
	xIsDestBit   = 0x20
	relAddrBit   = 0x40
	pushPopBit   = 0x80

//line mmixsim.w:1621
)

//line mmixsim.w:2041
const (
	version       = 1 // 우리가 지원하는 \MMIX\ 아키텍처의 판
	subversion    = 0 // 판 번호의 둘째 바이트
	subsubversion = 1 // 판 번호를 더 한정하는 번호
)

//line mmixsim.w:3323
const (
	resumeAgain = 0 // rX의 명령을 위치 $\rm rW-4$에 있는 것처럼 되풀이한다
	resumeCont  = 1 // 같되, 피연산자 대신 rY와 rZ를 쓴다
	resumeSet   = 2 // 레지스터 \$X를 rZ로 정한다
)

//line mmixsim.w:4083
const commandBufSize = 1024 // 넉넉하게 길게, 부동소수점 시험을 위해

//line mmixsim.w:1444
var specialName = [32]string{"rB", "rD", "rE", "rH", "rJ", "rM", "rR", "rBB",
	"rC", "rN", "rO", "rS", "rI", "rT", "rTT", "rK", "rQ", "rU", "rV", "rG", "rL",
	"rA", "rF", "rP", "rW", "rX", "rY", "rZ", "rWW", "rXX", "rYY", "rZZ"}

//line mmixsim.w:1624
var info = [256]opInfo{

//line mmixsim.w:1638
	{"TRAP", 0x0a, 255, 0, 5, "%r"},
	{"FCMP", 0x2a, 0, 0, 1, "%l = %.y cmp %.z = %x"},
	{"FUN", 0x2a, 0, 0, 1, "%l = [%.y(||)%.z] = %x"},
	{"FEQL", 0x2a, 0, 0, 1, "%l = [%.y(==)%.z] = %x"},
	{"FADD", 0x2a, 0, 0, 4, "%l = %.y %(+%) %.z = %.x"},
	{"FIX", 0x26, 0, 0, 4, "%l = %(fix%) %.z = %x"},
	{"FSUB", 0x2a, 0, 0, 4, "%l = %.y %(-%) %.z = %.x"},
	{"FIXU", 0x26, 0, 0, 4, "%l = %(fix%) %.z = %#x"},
	{"FLOT", 0x26, 0, 0, 4, "%l = %(flot%) %z = %.x"},
	{"FLOTI", 0x25, 0, 0, 4, "%l = %(flot%) %z = %.x"},
	{"FLOTU", 0x26, 0, 0, 4, "%l = %(flot%) %#z = %.x"},
	{"FLOTUI", 0x25, 0, 0, 4, "%l = %(flot%) %z = %.x"},
	{"SFLOT", 0x26, 0, 0, 4, "%l = %(sflot%) %z = %.x"},
	{"SFLOTI", 0x25, 0, 0, 4, "%l = %(sflot%) %z = %.x"},
	{"SFLOTU", 0x26, 0, 0, 4, "%l = %(sflot%) %#z = %.x"},
	{"SFLOTUI", 0x25, 0, 0, 4, "%l = %(sflot%) %z = %.x"},

//line mmixsim.w:1656
	{"FMUL", 0x2a, 0, 0, 4, "%l = %.y %(*%) %.z = %.x"},
	{"FCMPE", 0x2a, rE, 0, 4, "%l = %.y cmp %.z (%.b)) = %x"},
	{"FUNE", 0x2a, rE, 0, 1, "%l = [%.y(||)%.z (%.b)] = %x"},
	{"FEQLE", 0x2a, rE, 0, 4, "%l = [%.y(==)%.z (%.b)] = %x"},
	{"FDIV", 0x2a, 0, 0, 40, "%l = %.y %(/%) %.z = %.x"},
	{"FSQRT", 0x26, 0, 0, 40, "%l = %(sqrt%) %.z = %.x"},
	{"FREM", 0x2a, 0, 0, 4, "%l = %.y %(rem%) %.z = %.x"},
	{"FINT", 0x26, 0, 0, 4, "%l = %(int%) %.z = %.x"},
	{"MUL", 0x2a, 0, 0, 10, "%l = %y * %z = %x"},
	{"MULI", 0x29, 0, 0, 10, "%l = %y * %z = %x"},
	{"MULU", 0x2a, 0, 0, 10, "%l = %#y * %#z = %#x, rH=%#a"},
	{"MULUI", 0x29, 0, 0, 10, "%l = %#y * %z = %#x, rH=%#a"},
	{"DIV", 0x2a, 0, 0, 60, "%l = %y / %z = %x, rR=%a"},
	{"DIVI", 0x29, 0, 0, 60, "%l = %y / %z = %x, rR=%a"},
	{"DIVU", 0x2a, rD, 0, 60, "%l = %#b%0y / %#z = %#x, rR=%#a"},
	{"DIVUI", 0x29, rD, 0, 60, "%l = %#b%0y / %z = %#x, rR=%#a"},

//line mmixsim.w:1674
	{"ADD", 0x2a, 0, 0, 1, "%l = %y + %z = %x"},
	{"ADDI", 0x29, 0, 0, 1, "%l = %y + %z = %x"},
	{"ADDU", 0x2a, 0, 0, 1, "%l = %#y + %#z = %#x"},
	{"ADDUI", 0x29, 0, 0, 1, "%l = %#y + %z = %#x"},
	{"SUB", 0x2a, 0, 0, 1, "%l = %y - %z = %x"},
	{"SUBI", 0x29, 0, 0, 1, "%l = %y - %z = %x"},
	{"SUBU", 0x2a, 0, 0, 1, "%l = %#y - %#z = %#x"},
	{"SUBUI", 0x29, 0, 0, 1, "%l = %#y - %z = %#x"},
	{"2ADDU", 0x2a, 0, 0, 1, "%l = %#y <<1+ %#z = %#x"},
	{"2ADDUI", 0x29, 0, 0, 1, "%l = %#y <<1+ %z = %#x"},
	{"4ADDU", 0x2a, 0, 0, 1, "%l = %#y <<2+ %#z = %#x"},
	{"4ADDUI", 0x29, 0, 0, 1, "%l = %#y <<2+ %z = %#x"},
	{"8ADDU", 0x2a, 0, 0, 1, "%l = %#y <<3+ %#z = %#x"},
	{"8ADDUI", 0x29, 0, 0, 1, "%l = %#y <<3+ %z = %#x"},
	{"16ADDU", 0x2a, 0, 0, 1, "%l = %#y <<4+ %#z = %#x"},
	{"16ADDUI", 0x29, 0, 0, 1, "%l = %#y <<4+ %z = %#x"},

//line mmixsim.w:1692
	{"CMP", 0x2a, 0, 0, 1, "%l = %y cmp %z = %x"},
	{"CMPI", 0x29, 0, 0, 1, "%l = %y cmp %z = %x"},
	{"CMPU", 0x2a, 0, 0, 1, "%l = %#y cmp %#z = %x"},
	{"CMPUI", 0x29, 0, 0, 1, "%l = %#y cmp %z = %x"},
	{"NEG", 0x26, 0, 0, 1, "%l = %y - %z = %x"},
	{"NEGI", 0x25, 0, 0, 1, "%l = %y - %z = %x"},
	{"NEGU", 0x26, 0, 0, 1, "%l = %y - %#z = %#x"},
	{"NEGUI", 0x25, 0, 0, 1, "%l = %y - %z = %#x"},
	{"SL", 0x2a, 0, 0, 1, "%l = %y << %#z = %x"},
	{"SLI", 0x29, 0, 0, 1, "%l = %y << %z = %x"},
	{"SLU", 0x2a, 0, 0, 1, "%l = %#y << %#z = %#x"},
	{"SLUI", 0x29, 0, 0, 1, "%l = %#y << %z = %#x"},
	{"SR", 0x2a, 0, 0, 1, "%l = %y >> %#z = %x"},
	{"SRI", 0x29, 0, 0, 1, "%l = %y >> %z = %x"},
	{"SRU", 0x2a, 0, 0, 1, "%l = %#y >> %#z = %#x"},
	{"SRUI", 0x29, 0, 0, 1, "%l = %#y >> %z = %#x"},

//line mmixsim.w:1626

//line mmixsim.w:1715
	{"BN", 0x50, 0, 0, 1, "%b<0? %t%g"},
	{"BNB", 0x50, 0, 0, 1, "%b<0? %t%g"},
	{"BZ", 0x50, 0, 0, 1, "%b==0? %t%g"},
	{"BZB", 0x50, 0, 0, 1, "%b==0? %t%g"},
	{"BP", 0x50, 0, 0, 1, "%b>0? %t%g"},
	{"BPB", 0x50, 0, 0, 1, "%b>0? %t%g"},
	{"BOD", 0x50, 0, 0, 1, "%b odd? %t%g"},
	{"BODB", 0x50, 0, 0, 1, "%b odd? %t%g"},
	{"BNN", 0x50, 0, 0, 1, "%b>=0? %t%g"},
	{"BNNB", 0x50, 0, 0, 1, "%b>=0? %t%g"},
	{"BNZ", 0x50, 0, 0, 1, "%b!=0? %t%g"},
	{"BNZB", 0x50, 0, 0, 1, "%b!=0? %t%g"},
	{"BNP", 0x50, 0, 0, 1, "%b<=0? %t%g"},
	{"BNPB", 0x50, 0, 0, 1, "%b<=0? %t%g"},
	{"BEV", 0x50, 0, 0, 1, "%b even? %t%g"},
	{"BEVB", 0x50, 0, 0, 1, "%b even? %t%g"},

//line mmixsim.w:1733
	{"PBN", 0x50, 0, 0, 1, "%b<0? %t%g"},
	{"PBNB", 0x50, 0, 0, 1, "%b<0? %t%g"},
	{"PBZ", 0x50, 0, 0, 1, "%b==0? %t%g"},
	{"PBZB", 0x50, 0, 0, 1, "%b==0? %t%g"},
	{"PBP", 0x50, 0, 0, 1, "%b>0? %t%g"},
	{"PBPB", 0x50, 0, 0, 1, "%b>0? %t%g"},
	{"PBOD", 0x50, 0, 0, 1, "%b odd? %t%g"},
	{"PBODB", 0x50, 0, 0, 1, "%b odd? %t%g"},
	{"PBNN", 0x50, 0, 0, 1, "%b>=0? %t%g"},
	{"PBNNB", 0x50, 0, 0, 1, "%b>=0? %t%g"},
	{"PBNZ", 0x50, 0, 0, 1, "%b!=0? %t%g"},
	{"PBNZB", 0x50, 0, 0, 1, "%b!=0? %t%g"},
	{"PBNP", 0x50, 0, 0, 1, "%b<=0? %t%g"},
	{"PBNPB", 0x50, 0, 0, 1, "%b<=0? %t%g"},
	{"PBEV", 0x50, 0, 0, 1, "%b even? %t%g"},
	{"PBEVB", 0x50, 0, 0, 1, "%b even? %t%g"},

//line mmixsim.w:1751
	{"CSN", 0x3a, 0, 0, 1, "%l = %y<0? %z: %b = %x"},
	{"CSNI", 0x39, 0, 0, 1, "%l = %y<0? %z: %b = %x"},
	{"CSZ", 0x3a, 0, 0, 1, "%l = %y==0? %z: %b = %x"},
	{"CSZI", 0x39, 0, 0, 1, "%l = %y==0? %z: %b = %x"},
	{"CSP", 0x3a, 0, 0, 1, "%l = %y>0? %z: %b = %x"},
	{"CSPI", 0x39, 0, 0, 1, "%l = %y>0? %z: %b = %x"},
	{"CSOD", 0x3a, 0, 0, 1, "%l = %y odd? %z: %b = %x"},
	{"CSODI", 0x39, 0, 0, 1, "%l = %y odd? %z: %b = %x"},
	{"CSNN", 0x3a, 0, 0, 1, "%l = %y>=0? %z: %b = %x"},
	{"CSNNI", 0x39, 0, 0, 1, "%l = %y>=0? %z: %b = %x"},
	{"CSNZ", 0x3a, 0, 0, 1, "%l = %y!=0? %z: %b = %x"},
	{"CSNZI", 0x39, 0, 0, 1, "%l = %y!=0? %z: %b = %x"},
	{"CSNP", 0x3a, 0, 0, 1, "%l = %y<=0? %z: %b = %x"},
	{"CSNPI", 0x39, 0, 0, 1, "%l = %y<=0? %z: %b = %x"},
	{"CSEV", 0x3a, 0, 0, 1, "%l = %y even? %z: %b = %x"},
	{"CSEVI", 0x39, 0, 0, 1, "%l = %y even? %z: %b = %x"},

//line mmixsim.w:1769
	{"ZSN", 0x2a, 0, 0, 1, "%l = %y<0? %z: 0 = %x"},
	{"ZSNI", 0x29, 0, 0, 1, "%l = %y<0? %z: 0 = %x"},
	{"ZSZ", 0x2a, 0, 0, 1, "%l = %y==0? %z: 0 = %x"},
	{"ZSZI", 0x29, 0, 0, 1, "%l = %y==0? %z: 0 = %x"},
	{"ZSP", 0x2a, 0, 0, 1, "%l = %y>0? %z: 0 = %x"},
	{"ZSPI", 0x29, 0, 0, 1, "%l = %y>0? %z: 0 = %x"},
	{"ZSOD", 0x2a, 0, 0, 1, "%l = %y odd? %z: 0 = %x"},
	{"ZSODI", 0x29, 0, 0, 1, "%l = %y odd? %z: 0 = %x"},
	{"ZSNN", 0x2a, 0, 0, 1, "%l = %y>=0? %z: 0 = %x"},
	{"ZSNNI", 0x29, 0, 0, 1, "%l = %y>=0? %z: 0 = %x"},
	{"ZSNZ", 0x2a, 0, 0, 1, "%l = %y!=0? %z: 0 = %x"},
	{"ZSNZI", 0x29, 0, 0, 1, "%l = %y!=0? %z: 0 = %x"},
	{"ZSNP", 0x2a, 0, 0, 1, "%l = %y<=0? %z: 0 = %x"},
	{"ZSNPI", 0x29, 0, 0, 1, "%l = %y<=0? %z: 0 = %x"},
	{"ZSEV", 0x2a, 0, 0, 1, "%l = %y even? %z: 0 = %x"},
	{"ZSEVI", 0x29, 0, 0, 1, "%l = %y even? %z: 0 = %x"},

//line mmixsim.w:1627

//line mmixsim.w:1792
	{"LDB", 0x2a, 0, 1, 1, "%l = M1[%#y+%#z] = %x"},
	{"LDBI", 0x29, 0, 1, 1, "%l = M1[%#y%?+] = %x"},
	{"LDBU", 0x2a, 0, 1, 1, "%l = M1[%#y+%#z] = %#x"},
	{"LDBUI", 0x29, 0, 1, 1, "%l = M1[%#y%?+] = %#x"},
	{"LDW", 0x2a, 0, 1, 1, "%l = M2[%#y+%#z] = %x"},
	{"LDWI", 0x29, 0, 1, 1, "%l = M2[%#y%?+] = %x"},
	{"LDWU", 0x2a, 0, 1, 1, "%l = M2[%#y+%#z] = %#x"},
	{"LDWUI", 0x29, 0, 1, 1, "%l = M2[%#y%?+] = %#x"},
	{"LDT", 0x2a, 0, 1, 1, "%l = M4[%#y+%#z] = %x"},
	{"LDTI", 0x29, 0, 1, 1, "%l = M4[%#y%?+] = %x"},
	{"LDTU", 0x2a, 0, 1, 1, "%l = M4[%#y+%#z] = %#x"},
	{"LDTUI", 0x29, 0, 1, 1, "%l = M4[%#y%?+] = %#x"},
	{"LDO", 0x2a, 0, 1, 1, "%l = M8[%#y+%#z] = %x"},
	{"LDOI", 0x29, 0, 1, 1, "%l = M8[%#y%?+] = %x"},
	{"LDOU", 0x2a, 0, 1, 1, "%l = M8[%#y+%#z] = %#x"},
	{"LDOUI", 0x29, 0, 1, 1, "%l = M8[%#y%?+] = %#x"},

//line mmixsim.w:1810
	{"LDSF", 0x2a, 0, 1, 1, "%l = (M4[%#y+%#z]) = %.x"},
	{"LDSFI", 0x29, 0, 1, 1, "%l = (M4[%#y%?+]) = %.x"},
	{"LDHT", 0x2a, 0, 1, 1, "%l = M4[%#y+%#z]<<32 = %#x"},
	{"LDHTI", 0x29, 0, 1, 1, "%l = M4[%#y%?+]<<32 = %#x"},
	{"CSWAP", 0x3a, 0, 2, 2, "%l = [M8[%#y+%#z]==%a] = %x, %r"},
	{"CSWAPI", 0x39, 0, 2, 2, "%l = [M8[%#y%?+]==%a] = %x, %r"},
	{"LDUNC", 0x2a, 0, 1, 1, "%l = M8[%#y+%#z] = %#x"},
	{"LDUNCI", 0x29, 0, 1, 1, "%l = M8[%#y%?+] = %#x"},
	{"LDVTS", 0x2a, 0, 0, 1, ""},
	{"LDVTSI", 0x29, 0, 0, 1, ""},
	{"PRELD", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
	{"PRELDI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
	{"PREGO", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
	{"PREGOI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
	{"GO", 0x2a, 0, 0, 3, "%l = %#x, -> %#y+%#z"},
	{"GOI", 0x29, 0, 0, 3, "%l = %#x, -> %#y%?+"},

//line mmixsim.w:1828
	{"STB", 0x1a, 0, 1, 1, "M1[%#y+%#z] = %b, M8[%#w]=%#a"},
	{"STBI", 0x19, 0, 1, 1, "M1[%#y%?+] = %b, M8[%#w]=%#a"},
	{"STBU", 0x1a, 0, 1, 1, "M1[%#y+%#z] = %#b, M8[%#w]=%#a"},
	{"STBUI", 0x19, 0, 1, 1, "M1[%#y%?+] = %#b, M8[%#w]=%#a"},
	{"STW", 0x1a, 0, 1, 1, "M2[%#y+%#z] = %b, M8[%#w]=%#a"},
	{"STWI", 0x19, 0, 1, 1, "M2[%#y%?+] = %b, M8[%#w]=%#a"},
	{"STWU", 0x1a, 0, 1, 1, "M2[%#y+%#z] = %#b, M8[%#w]=%#a"},
	{"STWUI", 0x19, 0, 1, 1, "M2[%#y%?+] = %#b, M8[%#w]=%#a"},
	{"STT", 0x1a, 0, 1, 1, "M4[%#y+%#z] = %b, M8[%#w]=%#a"},
	{"STTI", 0x19, 0, 1, 1, "M4[%#y%?+] = %b, M8[%#w]=%#a"},
	{"STTU", 0x1a, 0, 1, 1, "M4[%#y+%#z] = %#b, M8[%#w]=%#a"},
	{"STTUI", 0x19, 0, 1, 1, "M4[%#y%?+] = %#b, M8[%#w]=%#a"},
	{"STO", 0x1a, 0, 1, 1, "M8[%#y+%#z] = %b"},
	{"STOI", 0x19, 0, 1, 1, "M8[%#y%?+] = %b"},
	{"STOU", 0x1a, 0, 1, 1, "M8[%#y+%#z] = %#b"},
	{"STOUI", 0x19, 0, 1, 1, "M8[%#y%?+] = %#b"},

//line mmixsim.w:1846
	{"STSF", 0x1a, 0, 1, 1, "%(M4[%#y+%#z]%) = %.b, M8[%#w]=%#a"},
	{"STSFI", 0x19, 0, 1, 1, "%(M4[%#y%?+]%) = %.b, M8[%#w]=%#a"},
	{"STHT", 0x1a, 0, 1, 1, "M4[%#y+%#z] = %#b>>32, M8[%#w]=%#a"},
	{"STHTI", 0x19, 0, 1, 1, "M4[%#y%?+] = %#b>>32, M8[%#w]=%#a"},
	{"STCO", 0x0a, 0, 1, 1, "M8[%#y+%#z] = %b"},
	{"STCOI", 0x09, 0, 1, 1, "M8[%#y%?+] = %b"},
	{"STUNC", 0x1a, 0, 1, 1, "M8[%#y+%#z] = %#b"},
	{"STUNCI", 0x19, 0, 1, 1, "M8[%#y%?+] = %#b"},
	{"SYNCD", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
	{"SYNCDI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
	{"PREST", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
	{"PRESTI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
	{"SYNCID", 0x0a, 0, 0, 1, "[%#y+%#z .. %#x]"},
	{"SYNCIDI", 0x09, 0, 0, 1, "[%#y%?+ .. %#x]"},
	{"PUSHGO", 0xaa, 0, 0, 3, "%lrO=%#b, rL=%a, rJ=%#x, -> %#y+%#z"},
	{"PUSHGOI", 0xa9, 0, 0, 3, "%lrO=%#b, rL=%a, rJ=%#x, -> %#y%?+"},

//line mmixsim.w:1628

//line mmixsim.w:1869
	{"OR", 0x2a, 0, 0, 1, "%l = %#y | %#z = %#x"},
	{"ORI", 0x29, 0, 0, 1, "%l = %#y | %z = %#x"},
	{"ORN", 0x2a, 0, 0, 1, "%l = %#y |~ %#z = %#x"},
	{"ORNI", 0x29, 0, 0, 1, "%l = %#y |~ %z = %#x"},
	{"NOR", 0x2a, 0, 0, 1, "%l = %#y ~| %#z = %#x"},
	{"NORI", 0x29, 0, 0, 1, "%l = %#y ~| %z = %#x"},
	{"XOR", 0x2a, 0, 0, 1, "%l = %#y ^ %#z = %#x"},
	{"XORI", 0x29, 0, 0, 1, "%l = %#y ^ %z = %#x"},
	{"AND", 0x2a, 0, 0, 1, "%l = %#y & %#z = %#x"},
	{"ANDI", 0x29, 0, 0, 1, "%l = %#y & %z = %#x"},
	{"ANDN", 0x2a, 0, 0, 1, "%l = %#y \\ %#z = %#x"},
	{"ANDNI", 0x29, 0, 0, 1, "%l = %#y \\ %z = %#x"},
	{"NAND", 0x2a, 0, 0, 1, "%l = %#y ~& %#z = %#x"},
	{"NANDI", 0x29, 0, 0, 1, "%l = %#y ~& %z = %#x"},
	{"NXOR", 0x2a, 0, 0, 1, "%l = %#y ~^ %#z = %#x"},
	{"NXORI", 0x29, 0, 0, 1, "%l = %#y ~^ %z = %#x"},

//line mmixsim.w:1887
	{"BDIF", 0x2a, 0, 0, 1, "%l = %#y bdif %#z = %#x"},
	{"BDIFI", 0x29, 0, 0, 1, "%l = %#y bdif %z = %#x"},
	{"WDIF", 0x2a, 0, 0, 1, "%l = %#y wdif %#z = %#x"},
	{"WDIFI", 0x29, 0, 0, 1, "%l = %#y wdif %z = %#x"},
	{"TDIF", 0x2a, 0, 0, 1, "%l = %#y tdif %#z = %#x"},
	{"TDIFI", 0x29, 0, 0, 1, "%l = %#y tdif %z = %#x"},
	{"ODIF", 0x2a, 0, 0, 1, "%l = %#y odif %#z = %#x"},
	{"ODIFI", 0x29, 0, 0, 1, "%l = %#y odif %z = %#x"},
	{"MUX", 0x2a, rM, 0, 1, "%l = %#b? %#y: %#z = %#x"},
	{"MUXI", 0x29, rM, 0, 1, "%l = %#b? %#y: %z = %#x"},
	{"SADD", 0x2a, 0, 0, 1, "%l = nu(%#y\\%#z) = %x"},
	{"SADDI", 0x29, 0, 0, 1, "%l = nu(%#y%?\\) = %x"},
	{"MOR", 0x2a, 0, 0, 1, "%l = %#y mor %#z = %#x"},
	{"MORI", 0x29, 0, 0, 1, "%l = %#y mor %z = %#x"},
	{"MXOR", 0x2a, 0, 0, 1, "%l = %#y mxor %#z = %#x"},
	{"MXORI", 0x29, 0, 0, 1, "%l = %#y mxor %z = %#x"},

//line mmixsim.w:1905
	{"SETH", 0x20, 0, 0, 1, "%l = %#z"},
	{"SETMH", 0x20, 0, 0, 1, "%l = %#z"},
	{"SETML", 0x20, 0, 0, 1, "%l = %#z"},
	{"SETL", 0x20, 0, 0, 1, "%l = %#z"},
	{"INCH", 0x30, 0, 0, 1, "%l = %#y + %#z = %#x"},
	{"INCMH", 0x30, 0, 0, 1, "%l = %#y + %#z = %#x"},
	{"INCML", 0x30, 0, 0, 1, "%l = %#y + %#z = %#x"},
	{"INCL", 0x30, 0, 0, 1, "%l = %#y + %#z = %#x"},
	{"ORH", 0x30, 0, 0, 1, "%l = %#y | %#z = %#x"},
	{"ORMH", 0x30, 0, 0, 1, "%l = %#y | %#z = %#x"},
	{"ORML", 0x30, 0, 0, 1, "%l = %#y | %#z = %#x"},
	{"ORL", 0x30, 0, 0, 1, "%l = %#y | %#z = %#x"},
	{"ANDNH", 0x30, 0, 0, 1, "%l = %#y \\ %#z = %#x"},
	{"ANDNMH", 0x30, 0, 0, 1, "%l = %#y \\ %#z = %#x"},
	{"ANDNML", 0x30, 0, 0, 1, "%l = %#y \\ %#z = %#x"},
	{"ANDNL", 0x30, 0, 0, 1, "%l = %#y \\ %#z = %#x"},

//line mmixsim.w:1923
	{"JMP", 0x40, 0, 0, 1, "-> %#z"},
	{"JMPB", 0x40, 0, 0, 1, "-> %#z"},
	{"PUSHJ", 0xe0, 0, 0, 1, "%lrO=%#b, rL=%a, rJ=%#x, -> %#z"},
	{"PUSHJB", 0xe0, 0, 0, 1, "%lrO=%#b, rL=%a, rJ=%#x, -> %#z"},
	{"GETA", 0x60, 0, 0, 1, "%l = %#z"},
	{"GETAB", 0x60, 0, 0, 1, "%l = %#z"},
	{"PUT", 0x02, 0, 0, 1, "%s = %r"},
	{"PUTI", 0x01, 0, 0, 1, "%s = %r"},
	{"POP", 0x80, rJ, 0, 3, "%lrL=%a, rO=%#b, -> %#y%?+"},
	{"RESUME", 0x00, 0, 0, 5, "{%#b} -> %#z"},
	{"SAVE", 0x20, 0, 20, 1, "%l = %#x"},
	{"UNSAVE", 0x82, 0, 20, 1, "%#z: rG=%x, ..., rL=%a"},
	{"SYNC", 0x01, 0, 0, 1, ""},
	{"SWYM", 0x00, 0, 0, 1, ""},
	{"GET", 0x20, 0, 0, 1, "%l = %s = %#x"},
	{"TRIP", 0x0a, 255, 0, 5, "rW=%#w, rX=%#x, rY=%#y, rZ=%#z, rB=%#b, g[255]=%#a"},

//line mmixsim.w:1629
}

//line mmixsim.w:3077
var argCount = [...]int{1, 3, 1, 3, 3, 3, 3, 2, 2, 2, 1}

var trapFormat = [...]string{
	"Halt(%z)",
	"$255 = Fopen(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fclose(%!z) = %x",
	"$255 = Fread(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fgets(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fgetws(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fwrite(%!z,M8[%#b]=%#q,M8[%#a]=%p) = %x",
	"$255 = Fputs(%!z,%#b) = %x",
	"$255 = Fputws(%!z,%#b) = %x",
	"$255 = Fseek(%!z,%b) = %x",
	"$255 = Ftell(%!z) = %x"}

//line mmixsim.w:3577
var streamName = [3]string{"StdIn", "StdOut", "StdErr"}

//line mmixsim.w:3641
var leftParen = [5]byte{0, '[', '^', '_', '('}  // 반올림 방식을 나타낸다
var rightParen = [5]byte{0, ']', '^', '_', ')'} // 반올림 방식을 나타낸다

//line mmixsim.w:3860
var usageHelp = [...]string{
	" with these options: (<n>=decimal number, <x>=hex number)\n",
	"-t<n> trace each instruction the first n times\n",
	"-e<x> trace each instruction with an exception matching x\n",
	"-r    trace hidden details of the register stack\n",
	"-l<n> list source lines when tracing, filling gaps <= n\n",
	"-s    show statistics after each traced instruction\n",
	"-P    print a profile when simulation ends\n",
	"-L<n> list source lines with the profile\n",
	"-v    be verbose: show almost everything\n",
	"-q    be quiet: show only the simulated standard output\n",
	"-i    run interactively (prompt for online commands)\n",
	"-I    interact, but only after the program halts\n",
	"-b<n> change the buffer size for source lines\n",
	"-c<n> change the cyclic local register ring size\n",
	"-f<filename> use given file to simulate standard input\n",
	"-D<filename> dump a file for use by other simulators\n",
	""}

//line mmixsim.w:3880
var interactiveHelp = [...]string{
	"The interactive commands are:\n",
	"<return>  trace one instruction\n",
	"n         trace one instruction\n",
	"c         continue until halt or breakpoint\n",
	"q         quit the simulation\n",
	"s         show current statistics\n",
	"l<n><t>   set and/or show local register in format t\n",
	"g<n><t>   set and/or show global register in format t\n",
	"rA<t>     set and/or show register rA in format t\n",
	"$<n><t>   set and/or show dynamic register in format t\n",
	"M<x><t>   set and/or show memory octabyte in format t\n",
	"+<n><t>   set and/or show n additional octabytes in format t\n",
	" <t> is ! (decimal) or . (floating) or # (hex) or \" (string)\n",
	"     or <empty> (previous <t>) or =<value> (change value)\n",
	"@<x>      go to location x\n",
	"b[rwx]<x> set or reset breakpoint at location x\n",
	"t<x>      trace location x\n",
	"u<x>      untrace location x\n",
	"T         set current segment to Text_Segment\n",
	"D         set current segment to Data_Segment\n",
	"P         set current segment to Pool_Segment\n",
	"S         set current segment to Stack_Segment\n",
	"B         show all current breakpoints and tracepoints\n",
	"i<file>   insert commands from file\n",
	"-<option> change a tracing/listing/profile option\n",
	"-?        show the tracing/listing/profile options  \n",
	""}

//line mmixsim.w:4098
var specRegCode = [26]byte{rA, rB, rC, rD, rE, rF, rG, rH, rI, rJ, rK, rL, rM,
	rN, rO, rP, rQ, rR, rS, rT, rU, rV, rW, rX, rY, rZ}

//line mmixsim.w:4100
var specReggCode = [26]byte{0, rBB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, rTT, 0, 0, rWW, rXX, rYY, rZZ}

//line mmixsim.w:598
func (m *simulator) printHex(o Octa) {
	m.printf("%x", o)
}

//line mmixsim.w:608
func (m *simulator) eprintf(format string, a ...any) {
	if !m.io.StderrError() {
		fmt.Fprintf(m.stderr, format, a...)
	}
}

//line mmixsim.w:619
func (m *simulator) printf(format string, a ...any) {
	fmt.Fprintf(m.out, format, a...)
}

//line mmixsim.w:647
func (m *simulator) panic(msg string) {
	m.eprintf("Panic: %s!\n", msg)
	panic(exitSignal(-2))
}

//line mmixsim.w:661
func (m *simulator) printInt(o Octa) {
	m.out.WriteString(strconv.FormatInt(int64(o), 10))
}

//line mmixsim.w:706
func (m *simulator) newMem() *memNode {
	p := &memNode{stamp: m.priority}
	m.priority += 0x9e3779b9 // $\lfloor2^{32}(\phi-1)\rfloor$
	return p
}

//line mmixsim.w:739
func (m *simulator) memFind(addr Octa) []memTetra {
	key := addr &^ 0x7ff
	offset := addr & 0x7fc
	p := m.lastMem
	if p.loc != key {

//line mmixsim.w:756
		for p = m.memRoot; p != nil; {
			if key == p.loc {
				break
			}
			if key < p.loc {
				p = p.left
			} else {
				p = p.right
			}
		}
		if p == nil {
			q := &m.memRoot
			for p = m.memRoot; p != nil && p.stamp < m.priority; p = *q {
				if key < p.loc {
					q = &p.left
				} else {
					q = &p.right
				}
			}
			*q = m.newMem()
			(*q).loc = key

//line mmixsim.w:787
			l, r := &(*q).left, &(*q).right
			for p != nil {
				if key < p.loc {
					*r = p
					r = &p.left
					p = *r
				} else {
					*l = p
					l = &p.right
					p = *l
				}
			}
			*l, *r = nil, nil

//line mmixsim.w:778
			p = *q
		}
		m.lastMem = p

//line mmixsim.w:745
	}
	return p.dat[offset>>2:]
}

//line mmixsim.w:868
func (m *simulator) readTet() {
	if _, err := io.ReadFull(m.mmoFile, m.buf[:]); err != nil {
		m.mmoErr()
	}
	m.yzbytes = int(m.buf[2])<<8 | int(m.buf[3])
	m.tet = Tetra(m.buf[0])<<24 | Tetra(m.buf[1])<<16 | Tetra(m.yzbytes)
}

func (m *simulator) mmoErr() {
	m.eprintf("Bad object file! (Try running MMOtype.)\n")

	panic(exitSignal(-4))
}

//line mmixsim.w:953
func (m *simulator) mmoLoad(loc Octa, val Tetra) []memTetra {
	ll := m.memFind(loc)
	ll[0].tet ^= val
	return ll
}

//line mmixsim.w:1004
func (m *simulator) readAddress() Octa {
	var h Tetra
	switch m.buf[3] {
	case 2:
		j := Tetra(m.buf[2])
		m.readTet()
		h = j<<24 + m.tet
	case 1:
		h = Tetra(m.buf[2]) << 24
	default:
		m.mmoErr()
	}
	m.readTet()
	return Octa(h)<<32 | Octa(m.tet)
}

//line mmixsim.w:1227
func (m *simulator) printLine(k int) {
	fi := &m.fileInfo[m.curFile]
	if k >= fi.lineCount {
		return
	}

//line mmixsim.w:1248
	if _, err := m.srcFile.f.Seek(fi.lineMap[k], io.SeekStart); err != nil {
		return
	}
	m.srcFile.r.Reset(m.srcFile.f)
	m.srcFile.pos, m.srcFile.eof = fi.lineMap[k], false

//line mmixsim.w:1233
	if !m.srcFile.fgets(m.buffer, m.bufSize) {
		return
	}
	num := fmt.Sprintf("%d:    ", k)
	n := strlen(m.buffer)
	m.printf("line %s %s", num[:6], m.buffer[:n])
	if n == 0 || m.buffer[n-1] != '\n' {
		m.printf("\n")
	}
	m.lineShown = true
}

//line mmixsim.w:1264
func (m *simulator) showLine() {
	if m.shownFile != m.curFile {

//line mmixsim.w:1308
		name := m.fileInfo[m.curFile].name
		if m.srcFile == nil {
			if f, err := os.Open(string(name)); err == nil {
				m.srcFile = newCfile(f)
			}
		} else { // |freopen|
			m.srcFile.f.Close()
			if f, err := os.Open(string(name)); err == nil {
				m.srcFile.f = f
			}
			m.srcFile.r.Reset(m.srcFile.f)
			m.srcFile.pos, m.srcFile.eof = 0, false
		}
		if m.srcFile == nil {
			m.eprintf("Warning: I can't open file %s; source listing omitted.\n",

				name)
			m.showingSource = false
			return
		}
		m.printf("\"%s\"\n", name)
		m.shownFile = m.curFile
		m.shownLine = 0
		if m.fileInfo[m.curFile].lineMap == nil {

//line mmixsim.w:1209
			if st, err := os.Stat(string(m.fileInfo[m.curFile].name)); err == nil {
				if Tetra(st.ModTime().Unix()) > m.objTime {
					m.eprintf(
						"Warning: File %s was modified; it may not match the program!\n",

						m.fileInfo[m.curFile].name)
				}
			}

//line mmixsim.w:1183
			lineMap := []int64{0} // 색인 0은 쓰지 않는다
			l := 1
		lines:
			for ; l < 65536 && !m.srcFile.eof; l++ {
				pos := m.srcFile.pos // |ftell(src_file)|
				for {
					if !m.srcFile.fgets(m.buffer, m.bufSize) {
						break lines
					}
					if n := strlen(m.buffer); n > 0 && m.buffer[n-1] == '\n' {
						break
					}
				}
				lineMap = append(lineMap, pos)
			}
			m.fileInfo[m.curFile].lineCount = l
			m.fileInfo[m.curFile].lineMap = lineMap

//line mmixsim.w:1333
		}

//line mmixsim.w:1267
	} else if m.shownLine == int32(m.curLine) {
		return // 이미 보였다
	}
	cl := int32(m.curLine)
	if cl > m.shownLine+m.gap+1 || cl < m.shownLine {
		if m.shownLine > 0 {
			if cl < m.shownLine {
				m.printf("--------\n") // 위로 옮긴 것을 나타낸다
			} else {
				m.printf("     ...\n") // 빈틈을 나타낸다
			}
		}
		m.printLine(m.curLine)
	} else {
		for k := m.shownLine + 1; k <= cl; k++ {
			m.printLine(int(k))
		}
	}
	m.shownLine = cl
}

//line mmixsim.w:1340
func (m *simulator) printFreqs(p *memNode) {
	if p.left != nil {
		m.printFreqs(p.left)
	}
	for j := range 512 {
		if p.dat[j].freq != 0 {

//line mmixsim.w:1362
			curLoc := p.loc + Octa(4*j)
			shown := false
			if m.showingSource && p.dat[j].lineNo != 0 {
				m.curFile, m.curLine = int(p.dat[j].fileNo), int(p.dat[j].lineNo)
				m.lineShown = false
				m.showLine()
				shown = m.lineShown
			}
			if !shown && curLoc != m.impliedLoc && m.profileStarted {
				m.printf("         0.        ...\n")
			}
			m.printf("%10d. %016x: %08x (%s)\n", int32(p.dat[j].freq), curLoc, p.dat[j].tet,
				info[p.dat[j].tet>>24].name)
			m.impliedLoc = curLoc + 4
			m.profileStarted = true

//line mmixsim.w:1347
		}
	}
	if p.right != nil {
		m.printFreqs(p.right)
	}
}

//line mmixsim.w:2108
func (m *simulator) stackStore() {
	ll := m.memFind(m.g[rS])
	k := m.S & m.lringMask
	ll[0].tet = Tetra(m.l[k] >> 32)
	m.testStoreBkpt(ll[0])
	ll[1].tet = Tetra(m.l[k])
	m.testStoreBkpt(ll[1])
	if m.stackTracing {
		m.tracing = true
		if m.curLine != 0 {
			m.showLine()
		}
		m.printf("             M8[#%016x]=l[%d]=#%016x, rS+=8\n", m.g[rS], k, m.l[k])
	}
	m.g[rS] += 8
	m.S++
}

//line mmixsim.w:2129
func (m *simulator) stackLoad() {
	m.S--
	m.g[rS] -= 8
	ll := m.memFind(m.g[rS])
	k := m.S & m.lringMask
	m.l[k] = octa(ll)
	m.testLoadBkpt(ll[0])
	m.testLoadBkpt(ll[1])
	if m.stackTracing {
		m.tracing = true
		if m.curLine != 0 {
			m.showLine()
		}
		m.printf("             rS-=8, l[%d]=M8[#%016x]=#%016x\n", k, m.g[rS], m.l[k])
	}
}

//line mmixsim.w:2149
func (m *simulator) testStoreBkpt(t memTetra) {
	if t.bkpt&writeBit != 0 {
		m.breakpoint, m.tracing = true, true
	}
}

func (m *simulator) testLoadBkpt(t memTetra) {
	if t.bkpt&readBit != 0 {
		m.breakpoint, m.tracing = true, true
	}
}

//line mmixsim.w:2165
func octa(ll []memTetra) Octa {
	return Octa(ll[0].tet)<<32 | Octa(ll[1].tet)
}

//line mmixsim.w:2304
func shiftAmt(z Octa) int {
	if z >= 64 {
		return 64
	}
	return int(z)
}

//line mmixsim.w:2485
func registerTruth(o Octa, op int) bool {
	var b bool
	switch (op >> 1) & 0x3 {
	case 0:
		b = o&signBit != 0 // 음수인가?
	case 1:
		b = o == 0 // 0인가?
	case 2:
		b = o < signBit && o != 0 // 양수인가?
	case 3:
		b = o&0x1 != 0 // 홀수인가?
	}
	if op&0x8 != 0 {
		return !b
	}
	return b
}

//line mmixsim.w:3105
func (m *simulator) memArg(addr Octa) Octa {
	ll := m.memFind(addr)
	m.testLoadBkpt(ll[0])
	o := Octa(ll[0].tet) << 32
	if len(ll) > 1 {
		m.testLoadBkpt(ll[1])
		o |= Octa(ll[1].tet)
	}
	return o
}

//line mmixsim.w:3134
func (m *simulator) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	a := addr
	for k := 0; k < size; {
		ll := m.memFind(a)
		m.testLoadBkpt(ll[0])
		x := ll[0].tet
		if a&0x3 != 0 || k > size-4 {

//line mmixsim.w:3156
			buf[k] = byte(x >> (8 * (^a & 0x3)))
			if buf[k] == 0 && stop >= 0 {
				if stop == 0 {
					return k
				}
				if a&0x1 != 0 && (k == 0 || buf[k-1] == 0) {
					return k - 1
				}
			}
			k++
			a++

//line mmixsim.w:3142
		} else {

//line mmixsim.w:3169
			buf[k] = byte(x >> 24)
			if buf[k] == 0 && (stop == 0 || stop > 0 && x < 0x10000) {
				return k
			}
			buf[k+1] = byte(x >> 16)
			if buf[k+1] == 0 && stop == 0 {
				return k + 1
			}
			buf[k+2] = byte(x >> 8)
			if buf[k+2] == 0 && (stop == 0 || stop > 0 && x&0xffff == 0) {
				return k + 2
			}
			buf[k+3] = byte(x)
			if buf[k+3] == 0 && stop == 0 {
				return k + 3
			}
			k += 4
			a += 4

//line mmixsim.w:3144
		}
	}
	return size
}

//line mmixsim.w:3192
func (m *simulator) MMPutChars(buf []byte, size int, addr Octa) {
	a := addr
	for k := 0; k < size; {
		ll := m.memFind(a)
		m.testStoreBkpt(ll[0])
		if a&0x3 != 0 || k > size-4 {

//line mmixsim.w:3206
			s := 8 * (^a & 0x3)
			ll[0].tet ^= ((ll[0].tet>>s ^ Tetra(buf[k])) & 0xff) << s
			k++
			a++

//line mmixsim.w:3199
		} else {

//line mmixsim.w:3212
			ll[0].tet = Tetra(buf[k])<<24 | Tetra(buf[k+1])<<16 | Tetra(buf[k+2])<<8 | Tetra(buf[k+3])
			k += 4
			a += 4

//line mmixsim.w:3201
		}
	}
}

//line mmixsim.w:3229
func (m *simulator) StdinChr() byte {
	for m.stdinBufStart == m.stdinBufEnd {
		if m.interacting {
			m.printf("StdIn> ")

			m.out.Flush()
		}
		if !m.stdin.fgets(m.stdinBuf[:], 256) {
			m.panic("End of file on standard input; use the -f option, not <")
		}
		m.stdinBufStart = 0
		p := 0
		for ; p < 254; p++ {
			if m.stdinBuf[p] == '\n' {
				break
			}
		}
		m.stdinBufEnd = p + 1
	}
	c := m.stdinBuf[m.stdinBufStart]
	m.stdinBufStart++
	return c
}

//line mmixsim.w:3583
func (m *simulator) tracePrint(o Octa, style fmtStyle) {
	switch style {
	case decimal:
		m.printInt(o)
	case hex:
		m.out.WriteByte('#')
		m.printHex(o)
	case zhex:
		m.printf("%016x", o)
	case floating:
		m.out.WriteString(mmixarith.FloatString(o))
	case handle:
		if o < 3 {
			m.out.WriteString(streamName[o])
		} else {
			m.printInt(o)
		}
	}
}

//line mmixsim.w:3651
func (m *simulator) showStats(verbose bool) {
	u, h, l := Tetra(m.g[rU]), Tetra(m.sclock>>32), Tetra(m.sclock)
	m.printf("  %d instruction%s, %d mem%s, %d oop%s; %d good guess%s, %d bad\n",
		int32(u), plural(u != 1, "s"),
		int32(h), plural(h != 1, "s"),
		int32(l), plural(l != 1, "s"),
		m.goodGuesses, plural(m.goodGuesses != 1, "es"), m.badGuesses)
	if !verbose {
		return
	}
	o, what := m.instPtr, "now"
	if m.halted {
		o, what = m.instPtr-4, "halted"
	}
	m.printf("  (%s at location #%016x)\n", what, o)
}

func plural(many bool, s string) string {
	if many {
		return s
	}
	return ""
}

//line mmixsim.w:3757
func (m *simulator) scanOption(arg string, usage bool) {
	var opt byte
	if arg != "" {
		opt = arg[0]
	}
	switch opt {

//line mmixsim.w:3788
	case 't':
		if len(arg) > 10 {
			m.traceThreshold = 0xffffffff
		} else {
			m.traceThreshold = Tetra(sscanf(arg[1:], false))
		}
	case 'e':
		if len(arg) == 1 {
			m.tracingExceptions = 0xff
		} else {
			m.tracingExceptions = int(sscanf(arg[1:], true))
		}
	case 'r':
		m.stackTracing = true
	case 's':
		m.showingStats = true
	case 'l':
		if len(arg) == 1 {
			m.gap = 3
		} else {
			m.gap = sscanf(arg[1:], false)
		}
		m.showingSource = true
	case 'L':
		if len(arg) == 1 {
			m.profileGap = 3
		} else {
			m.profileGap = sscanf(arg[1:], false)
		}
		m.profileShowingSource = true
		fallthrough
	case 'P':
		m.profiling = true

//line mmixsim.w:3764

//line mmixsim.w:3823
	case 'v':
		m.traceThreshold = 0xffffffff
		m.tracingExceptions = 0xff
		m.stackTracing = true
		m.showingStats = true
		m.gap, m.showingSource = 10, true
		m.profileGap, m.profileShowingSource, m.profiling = 10, true, true
	case 'q':
		m.traceThreshold, m.tracingExceptions = 0, 0
		m.stackTracing, m.showingStats, m.showingSource = false, false, false
		m.profiling, m.profileShowingSource = false, false
	case 'i':
		m.interacting = true
	case 'I':
		m.interactAfterBreak = true
	case 'b':
		m.bufSize = int(sscanf(arg[1:], false))
	case 'c':
		m.lringSize = int(sscanf(arg[1:], false))
	case 'f':

//line mmixsim.w:3910
		if m.fakeStdin != nil {
			m.fakeStdin.Close()
		}
		f, err := os.Open(arg[1:])
		m.fakeStdin = f
		if err != nil {
			m.eprintf("Sorry, I can't open file %s!\n", arg[1:])

			m.fakeStdin = nil
		} else {
			m.io.FakeStdin(f)
		}

//line mmixsim.w:3844
	case 'D':

//line mmixsim.w:3924
		if f, err := os.Create(arg[1:]); err != nil {
			m.eprintf("Sorry, I can't open file %s!\n", arg[1:])

			m.dumpFile = nil
		} else {
			m.dumpOS = f
			m.dumpFile = bufio.NewWriter(f)
		}

//line mmixsim.w:3765
	default:

//line mmixsim.w:3774
		if usage {
			m.eprintf(
				"Usage: %s <options> progfile command line-args...\n", m.myself)

			for k := 0; usageHelp[k] != ""; k++ {
				m.eprintf("%s", usageHelp[k])
			}
			panic(exitSignal(-1))
		}
		for k := 0; usageHelp[k][1] != 'b'; k++ {
			m.printf("%s", usageHelp[k])
		}

//line mmixsim.w:3767
	}
}

//line mmixsim.w:4026
func (m *simulator) whatSay() {
	k := strlen(m.commandBuf[:])
	if k < 10 && k > 0 && m.commandBuf[k-1] == '\n' {
		m.commandBuf[k-1] = 0
	} else {
		copy(m.commandBuf[9:], "...\x00")
	}
	m.printf("Eh? Sorry, I don't understand `%s'. (Type h for help)\n",
		cstr(m.commandBuf[:]))
}

//line mmixsim.w:4213
func scanHex(s []byte, p int, offset Octa) (Octa, int) {
	var o Octa
	for ; isxdigit(s[p]); p++ {
		d := int(s[p]) - '0'
		if s[p] >= 'a' {
			d += '0' - 'a' + 10
		} else if s[p] >= 'A' {
			d += '0' - 'A' + 10
		}
		o = o<<4 + Octa(d)
	}
	return o + offset, p
}

//line mmixsim.w:4492
func (m *simulator) showBreaks(p *memNode) {
	if p.left != nil {
		m.showBreaks(p.left)
	}
	for j := range 512 {
		if bk := p.dat[j].bkpt; bk != 0 {
			m.printf("  %016x %c%c%c%c\n", p.loc+Octa(4*j),
				flag(bk&traceBit, 't'), flag(bk&readBit, 'r'),
				flag(bk&writeBit, 'w'), flag(bk&execBit, 'x'))
		}
	}
	if p.right != nil {
		m.showBreaks(p.right)
	}
}

func flag(bit byte, c rune) rune {
	if bit != 0 {
		return c
	}
	return '-'
}

//line mmixsim.w:4575
func (m *simulator) dump(p *memNode, x *Octa) {
	if p.left != nil {
		m.dump(p.left, x)
	}
	for j := 0; j < 512; j += 2 {
		if p.dat[j].tet != 0 || p.dat[j+1].tet != 0 {
			curLoc := p.loc + Octa(4*j)
			if curLoc != *x {
				if Tetra(*x) != 1 {
					m.dumpTet(0)
					m.dumpTet(0)
				}
				m.dumpTet(Tetra(curLoc >> 32))
				m.dumpTet(Tetra(curLoc))
				*x = curLoc
			}
			m.dumpTet(p.dat[j].tet)
			m.dumpTet(p.dat[j+1].tet)
			*x += 8
		}
	}
	if p.right != nil {
		m.dump(p.right, x)
	}
}

//line mmixsim.w:4602
func (m *simulator) dumpTet(t Tetra) {
	m.dumpFile.WriteByte(byte(t >> 24))
	m.dumpFile.WriteByte(byte(t >> 16))
	m.dumpFile.WriteByte(byte(t >> 8))
	m.dumpFile.WriteByte(byte(t))
}

//line mmixsim.w:4625
func newCfile(f *os.File) *cfile {
	return &cfile{f: f, r: bufio.NewReader(f)}
}

func openCfile(name string) *cfile {
	f, err := os.Open(name)
	if err != nil {
		return nil
	}
	return newCfile(f)
}

//line mmixsim.w:4642
func (c *cfile) fgets(buf []byte, n int) bool {
	if c.eof {
		return false
	}
	i := 0
	for i < n-1 {
		ch, err := c.r.ReadByte()
		if err != nil {
			c.eof = true
			break
		}
		buf[i] = ch
		i++
		c.pos++
		if ch == '\n' {
			break
		}
	}
	if i == 0 {
		return false
	}
	buf[i] = 0
	return true
}

//line mmixsim.w:4671
func strlen(b []byte) int {
	if n := bytes.IndexByte(b, 0); n >= 0 {
		return n
	}
	return len(b)
}

func cstr(b []byte) []byte { return b[:strlen(b)] }

func isdigit(c byte) bool { return '0' <= c && c <= '9' }

func isxdigit(c byte) bool {
	return isdigit(c) || 'a' <= c && c <= 'f' || 'A' <= c && c <= 'F'
}

func isspace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}

//line mmixsim.w:4699
func sscanf(s string, base16 bool) int32 {
	var sign, digits string

//line mmixsim.w:4720
	digit := isdigit
	if base16 {
		digit = isxdigit
	}
	i := 0
	for i < len(s) && isspace(s[i]) {
		i++
	}
	s = s[i:]
	if len(s) > 512 {
		s = s[:512]
	}
	i = 0
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		sign = s[i : i+1]
		i++
	}
	if base16 && i+1 < len(s) && s[i] == '0' && (s[i+1] == 'x' || s[i+1] == 'X') {
		if i+2 >= len(s) || !digit(s[i+2]) {
			return 0
		}
		i += 2
	}
	j := i
	for j < len(s) && digit(s[j]) {
		j++
	}
	digits = s[i:j]

//line mmixsim.w:4702
	if digits == "" {
		return 0
	}
	if !base16 {
		n, _ := strconv.ParseInt(sign+digits, 10, 64) // 넘치면 끝값에서 멈춘다
		return int32(n)
	}
	n, _ := strconv.ParseUint(digits, 16, 64) // 넘치면 끝값에서 멈춘다
	if sign == "-" {
		n = -n
	}
	return int32(n)
}

//line mmixsim.w:100
func mmix(args []string, stdin io.Reader, stdout, stderr io.Writer) (code int) {
	m := &simulator{

//line mmixsim.w:157
		out:    bufio.NewWriter(stdout),
		stderr: stderr,
		stdin:  &cfile{r: bufio.NewReader(stdin)},

//line mmixsim.w:727
		priority: 314159265,

//line mmixsim.w:970
		curFile: -1,

//line mmixsim.w:1299
		shownFile: -1,

//line mmixsim.w:103
	}
	defer func() {

//line mmixsim.w:121
		m.out.Flush()
		m.io.FlushAll()
		if m.dumpFile != nil {
			m.dumpFile.Flush()
			m.dumpOS.Close()
		}
		if r := recover(); r != nil {
			e, ok := r.(exitSignal)
			if !ok {
				panic(r)
			}
			code = int(e)
		}

//line mmixsim.w:106
	}()
	m.io = mmixio.New(m, m.out, stderr)

//line mmixsim.w:3684
	var (

//line mmixsim.w:860
		postamble bool // |lopPost|를 만났는가?
		delta     int  // 상대 주소 고치기의 차이

//line mmixsim.w:960
		curLoc Octa // 현재 위치

//line mmixsim.w:1543
		w, x, y, z, a, b, ma, mb Octa            // 피연산자
		xPtr                     *Octa           // 목적지
		loc                      Octa            // 현재 명령의 위치
		inst                     Tetra           // 현재 명령
		oldL                     int             // 현재 명령을 실행하기 전의 |L|
		exc                      int             // 현재 명령이 일으킨 예외
		rop                      int             // 다시 시작한 명령의 ropcode
		roundMode                mmixarith.Round // 방금 쓴 부동소수점 반올림 방식
		curRound                 mmixarith.Round // 현재 반올림 방식
		resuming                 bool            // 중단된 명령을 다시 시작하고 있는가?
		tripping                 bool            // 트립 처리기로 가려는 참인가?
		good                     bool            // 마지막 분기 명령이 옳게 짐작했는가?
		lhs, rhs                 string          // 추적 출력의 왼쪽과 오른쪽

//line mmixsim.w:1569
		op             int        // 현재 명령의 연산 코드
		xx, yy, zz, yz int        // 현재 명령의 피연산자 필드들
		f              int        // 현재 |op|의 성질
		i, j, k        int        // 이런저런 색인
		ll             []memTetra // 모의 메모리의 현재 자리
		p              int        // 문자열에서의 현재 자리

//line mmixsim.w:2014
		G, L, O int // 핵심 레지스터들의 손쉬운 사본

//line mmixsim.w:3413
		justTraced bool // 앞 명령을 추적했는가?

//line mmixsim.w:3742
		curArg int // 인자 벡터에서의 현재 자리
		argc   int // 사용자 프로그램의 인자 개수

//line mmixsim.w:4089
		cmd         = m.commandBuf[:]
		inclFile    *cfile       // `\.i'가 끼워 넣는 명령들의 파일
		curDispMode byte   = 'l' // |'l'|이나 |'g'|나 |'$'|나 |'M'|
		curDispType byte   = '!' // |'!'|나 |'.'|나 |'#'|나 |'"'|
		curDispSet  bool         // 마지막 \.{<t>}가 \.{=<val>} 꼴이었는가?
		curDispAddr Octa         // 윗 테트라는 |'M'| 방식에서만 쓰인다
		curSeg      Octa         // 현재 세그먼트 오프셋

//line mmixsim.w:3686
	)

//line mmixsim.w:3732
	m.myself = args[0]
	for curArg = 1; curArg < len(args) && args[curArg] != "" && args[curArg][0] == '-'; curArg++ {
		m.scanOption(args[curArg][1:], true)
	}
	if curArg == len(args) {
		m.scanOption("?", true) // 사용법 알림과 함께 끝낸다
	}
	argc = len(args) - curArg // 사용자 프로그램의 |argc|

//line mmixsim.w:716
	m.memRoot = m.newMem()
	m.memRoot.loc = 0x4000000000000000
	m.lastMem = m.memRoot

//line mmixsim.w:834
	mf, err := os.Open(args[curArg])
	if err != nil {
		altName := args[curArg] + ".mmo"
		mf, err = os.Open(altName)
		if err != nil {
			m.eprintf("Can't open the object file %s or %s!\n",

				args[curArg], altName)
			return -3
		}
	}
	m.mmoFile = bufio.NewReader(mf)

//line mmixsim.w:976
	curLoc = 0
	m.curFile = -1
	m.curLine = 0

//line mmixsim.w:888
	m.readTet() // 입력의 첫 테트라바이트를 읽는다
	if m.buf[0] != mm || m.buf[1] != lopPre {
		m.mmoErr()
	}
	if m.buf[2] != 1 {
		m.mmoErr()
	}
	if m.buf[3] == 0 {
		m.objTime = 0xffffffff
	} else {
		j = int(m.buf[3]) - 1
		m.readTet()
		m.objTime = m.tet // 파일을 만든 시각
		for ; j > 0; j-- {
			m.readTet()
		}
	}

//line mmixsim.w:980
items:
	for !postamble {

//line mmixsim.w:912
		m.readTet()
	dispatch:
		for m.buf[0] == mm {
			switch m.buf[1] {
			case lopQuote:
				if m.yzbytes != 1 {
					m.mmoErr()
				}
				m.readTet()
				break dispatch

//line mmixsim.w:996
			case lopLoc:
				curLoc = m.readAddress()
				continue items
			case lopSkip:
				curLoc += Octa(m.yzbytes)
				continue items

//line mmixsim.w:1028
			case lopFixo:
				tmp := m.readAddress()
				m.mmoLoad(tmp, Tetra(curLoc>>32))
				m.mmoLoad(tmp+4, Tetra(curLoc))
				continue items
			case lopFixr, lopFixrx:
				if m.buf[1] == lopFixr {
					delta = m.yzbytes
				} else {
					j = m.yzbytes
					if j != 16 && j != 24 {
						m.mmoErr()
					}
					m.readTet()
					delta = int(m.tet)
					if delta&0xfe000000 != 0 {
						m.mmoErr()
					}
				}
				d := delta
				if delta >= 0x1000000 {
					d = delta&0xffffff - 1<<j
				}
				m.mmoLoad(curLoc-Octa(d<<2), Tetra(delta))
				continue items

//line mmixsim.w:1064
			case lopFile:
				if m.fileInfo[m.buf[2]].name != nil {
					if m.buf[3] != 0 {
						m.mmoErr()
					}
					m.curFile = int(m.buf[2])
				} else {
					if m.buf[3] == 0 {
						m.mmoErr()
					}
					name := make([]byte, 0, 4*int(m.buf[3]))
					m.curFile = int(m.buf[2])
					for j = int(m.buf[3]); j > 0; j-- {
						m.readTet()
						name = append(name, m.buf[:]...)
					}
					if n := bytes.IndexByte(name, 0); n >= 0 {
						name = name[:n]
					}
					m.fileInfo[m.curFile].name = name
				}
				m.curLine = 0
				continue items
			case lopLine:
				if m.curFile < 0 {
					m.mmoErr()
				}
				m.curLine = m.yzbytes
				continue items

//line mmixsim.w:1097
			case lopSpec:
				for {
					m.readTet()
					if m.buf[0] == mm {
						if m.buf[1] != lopQuote || m.yzbytes != 1 {
							continue dispatch // 특수 데이터의 끝
						}
						m.readTet()
					}
				}

//line mmixsim.w:923
			case lopPost:
				postamble = true
				if m.buf[2] != 0 || m.buf[3] < 32 {
					m.mmoErr()
				}
				continue items
			default:
				m.mmoErr()
			}
		}

//line mmixsim.w:944
		ll = m.mmoLoad(curLoc, m.tet)
		if m.curLine != 0 {
			ll[0].fileNo = byte(m.curFile)
			ll[0].lineNo = uint16(m.curLine)
			m.curLine++
		}
		curLoc = (curLoc + 4) &^ 3

//line mmixsim.w:983
	}

//line mmixsim.w:1119
	ll = m.memFind(0x6000000000000000)
	ll[5].tet = 2           // 이것이 결국 $\rm rL=2$로 만든다
	ll[1].tet = Tetra(argc) // 그리고 $\$0=|argc|$로
	ll[2].tet = 0x40000000
	ll[3].tet = 0x8 // 그리고 $\$1=\.{Pool\_Segment}+8$로 만든다
	G, L = int(m.buf[3]), 0
	for j, k = G+G, 6; j < 256+256; j, k = j+1, k+1 {
		m.readTet()
		ll[k].tet = m.tet
	}
	m.instPtr = Octa(ll[k-2].tet)<<32 | Octa(ll[k-1].tet) // \.{Main}
	ll[k+2*12].tet = Tetra(G) << 24
	m.g[255] = 0x6000000000000000 + Octa(4*k) + 12*8 // 여기서부터 \.{UNSAVE}해서 출발한다

//line mmixsim.w:985
	mf.Close()
	m.curLine = 0

//line mmixsim.w:1165
	if m.bufSize < 72 {
		m.bufSize = 72
	}
	m.buffer = make([]Char, m.bufSize+1)

//line mmixsim.w:2048
	m.g[rK] = negOne
	m.g[rN] = (version<<24+subversion<<16+subsubversion<<8)<<32 |
		Octa(Tetra(ABSTIME)) // 위의 설명과 경고를 보라
	m.g[rT] = 0x8000000500000000
	m.g[rTT] = 0x8000000600000000
	m.g[rV] = 0x369c200400000000
	if m.lringSize < 256 {
		m.lringSize = 256
	}
	m.lringMask = m.lringSize - 1
	if m.lringSize&m.lringMask != 0 {
		m.panic("The number of local registers must be a power of 2")

	}
	m.l = make([]Octa, m.lringSize)
	curRound = mmixarith.RoundNear

//line mmixsim.w:3938
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt) // 이제 인터럽트를 받는다
	defer func() {
		signal.Stop(sig)
		close(sig)
	}()
	go func() {
		for range sig {
			m.interrupt.Store(true)
		}
	}()

//line mmixsim.w:4527
	x = 0x4000000000000008
	loc = x + Octa(8*(argc+1))
	for k = 0; k < argc; k, curArg = k+1, curArg+1 {
		ll = m.memFind(x)
		ll[0].tet, ll[1].tet = Tetra(loc>>32), Tetra(loc)
		m.memFind(loc)
		m.MMPutChars([]byte(args[curArg]), len(args[curArg]), loc)
		x += 8
		loc += Octa(8 + len(args[curArg])&^7)
	}
	x = 0x4000000000000000
	ll = m.memFind(x)
	ll[0].tet, ll[1].tet = Tetra(loc>>32), Tetra(loc)

//line mmixsim.w:4545
	x = 0xf0
	ll = m.memFind(x)
	if ll[0].tet != 0 {
		m.instPtr = x
	}

//line mmixsim.w:4552
	resuming = true
	rop = resumeAgain
	m.g[rX] = Octa(UNSAVE)<<24 + 255
	if m.dumpFile != nil {
		x = 1
		m.dump(m.memRoot, &x)
		m.dumpTet(0)
		m.dumpTet(0)
		return 0
	}

//line mmixsim.w:3691
run:
	for {
		if m.interrupt.Load() && !m.breakpoint {
			m.breakpoint, m.interacting = true, true
			m.interrupt.Store(false)
		} else {
			m.breakpoint = false
			if m.interacting {

//line mmixsim.w:3961
			interact:
				for {

//line mmixsim.w:4041
					ready := false
					for !ready {
						for inclFile != nil && !ready {
							if !inclFile.fgets(cmd, commandBufSize) {
								inclFile.f.Close()
								inclFile = nil
							} else if cmd[0] != '\n' && cmd[0] != 'i' && cmd[0] != '%' {
								if cmd[0] == ' ' {
									m.printf("%s", cstr(cmd))
								} else {
									ready = true
								}
							}
						}
						if ready {
							break
						}
						m.printf("mmix> ")

						m.out.Flush()
						if !m.stdin.fgets(cmd, commandBufSize) {
							cmd[0] = 'q'
						}
						if cmd[0] != 'i' {
							ready = true
						} else {
							cmd[strlen(cmd)-1] = 0
							inclFile = openCfile(string(cstr(cmd[1:])))
							if inclFile == nil && isspace(cmd[1]) {
								inclFile = openCfile(string(cstr(cmd[2:])))
							}
							if inclFile == nil {
								m.printf("Can't open file `%s'!\n", cstr(cmd[1:]))
							}
						}
					}

//line mmixsim.w:3964
					p = 0
					repeating := int32(0)
					incomplete := false
					switch cmd[p] {

//line mmixsim.w:3989
					case '\n', 'n':
						m.breakpoint, m.tracing = true, true // 명령 하나를 추적하고 멈춘다
						break interact
					case 'c':
						break interact // 멈춤점까지 계속한다
					case 'q':
						break run
					case 's':
						m.showStats(true)
						continue interact
					case '-':
						k = strlen(cmd)
						if cmd[k-1] == '\n' {
							cmd[k-1] = 0
						}
						m.scanOption(string(cstr(cmd[1:])), false)
						continue interact

//line mmixsim.w:3969
					case 'l', 'g', '$', 'r', 'M', '+', '!', '.', '#', '"', '=':

//line mmixsim.w:4110
						switch cmd[p] {
						case 'l', 'g', '$':
							curDispMode = cmd[p]
							var n Tetra
							for p++; isdigit(cmd[p]); p++ {
								n = 10*n + Tetra(cmd[p]-'0')
							}
							curDispAddr = Octa(n)
							curDispSet, repeating = false, 1
						case 'r':

//line mmixsim.w:4150
							p++
							curDispMode = 'g'
							if cmd[p] < 'A' || cmd[p] > 'Z' {
								m.whatSay()
								continue interact
							}
							if cmd[p+1] != cmd[p] {
								curDispAddr = Octa(specRegCode[cmd[p]-'A'])
								p++
							} else if specReggCode[cmd[p]-'A'] != 0 {
								curDispAddr = Octa(specReggCode[cmd[p]-'A'])
								p += 2
							} else {
								m.whatSay()
								continue interact
							}
							curDispSet, repeating = false, 1

//line mmixsim.w:4121
						case 'M':
							curDispMode = 'M'
							curDispAddr, p = scanHex(cmd, p+1, curSeg)
							curDispAddr &^= 7
							curDispSet, repeating = false, 1
						case '+':
							if !isdigit(cmd[p+1]) {
								repeating = 1
							}
							for p++; isdigit(cmd[p]); p++ {
								repeating = 10*repeating + int32(cmd[p]-'0')
							}
							if repeating != 0 {
								if curDispMode == 'M' {
									curDispAddr += 8
								} else {
									curDispAddr++
								}
							}
						case '=':
							repeating = 1
						default: // \.!, \.., \.\#, \."
							curDispSet, repeating = false, 1
						}

//line mmixsim.w:3971

//line mmixsim.w:4169
						if cmd[p] == '!' || cmd[p] == '.' || cmd[p] == '#' || cmd[p] == '"' {
							curDispType = cmd[p]
							p++
						} else if cmd[p] == '=' {

//line mmixsim.w:4189
							curDispSet = true
							m.val = 0
							p++
							isStr := cmd[p] == '"' || cmd[p] == '\''
							if cmd[p] == '#' {
								curDispType = '#'
								m.val, p = scanHex(cmd, p+1, 0)
							} else if !isStr {
								v, next, kind := mmixarith.ScanConst(string(cmd[p:]))
								m.val, p = v, p+next
								curDispType = '!'
								if kind > 0 {
									curDispType = '.'
								}
							}
							if !isStr && cmd[p] == ',' {
								m.val &= 0xff
								isStr = true
							}
							if isStr {

//line mmixsim.w:4234
							str:
								for {
									curDispType = '"'
									for cmd[p] == ',' {
										p++
										if cmd[p] == '#' {
											var aux Octa
											aux, p = scanHex(cmd, p+1, 0)
											m.val = m.val<<8 + aux&0xff
										} else if isdigit(cmd[p]) {
											k = int(cmd[p] - '0')
											for p++; isdigit(cmd[p]); p++ {
												k = (10*k + int(cmd[p]-'0')) & 0xff
											}
											m.val = m.val<<8 + Octa(k)
										} else if cmd[p] == '\n' {
											incomplete = true
											break str
										}
									}
									if cmd[p] == '\'' && cmd[p+2] == cmd[p] {
										cmd[p], cmd[p+2] = '"', '"'
									}
									if cmd[p] == '"' {
										for p++; cmd[p] != 0 && cmd[p] != '\n' && cmd[p] != '"'; p++ {
											m.val = m.val<<8 + Octa(int8(cmd[p]))
										}
										if cmd[p] != 0 {
											q := cmd[p]
											p++
											if q == '"' && cmd[p] == ',' {
												continue str
											}
										}
									}
									break
								}

//line mmixsim.w:4210
							}

//line mmixsim.w:4174
						}

//line mmixsim.w:3972

//line mmixsim.w:4438
					case '@':
						m.instPtr, p = scanHex(cmd, p+1, curSeg)
						m.halted = false
					case 't', 'u':
						k = int(cmd[p])
						m.val, p = scanHex(cmd, p+1, curSeg)
						if m.val>>32 < 0x20000000 {
							ll = m.memFind(m.val)
							if k == 't' {
								ll[0].bkpt |= traceBit
							} else {
								ll[0].bkpt &^= traceBit
							}
						}
					case 'b':

//line mmixsim.w:4475
						for k, p = 0, p+1; !isxdigit(cmd[p]) && cmd[p] != 0; p++ {
							switch cmd[p] {
							case 'r':
								k |= readBit
							case 'w':
								k |= writeBit
							case 'x':
								k |= execBit
							}
						}
						m.val, p = scanHex(cmd, p, curSeg)
						if m.val&signBit == 0 {
							ll = m.memFind(m.val)
							ll[0].bkpt = ll[0].bkpt&^7 | byte(k)
						}

//line mmixsim.w:4454
					case 'T':
						curSeg = 0
						p++
					case 'D':
						curSeg = 0x2000000000000000
						p++
					case 'P':
						curSeg = 0x4000000000000000
						p++
					case 'S':
						curSeg = 0x6000000000000000
						p++
					case 'B':
						m.showBreaks(m.memRoot)
						p++

//line mmixsim.w:3973
					case 'h':
						for k = 0; interactiveHelp[k] != ""; k++ {
							m.printf("%s", interactiveHelp[k])
						}
						continue interact
					default:
						m.whatSay()
						continue interact
					}

//line mmixsim.w:4008
					if incomplete || cmd[p] != '\n' {
						if incomplete || cmd[p] == 0 {
							m.printf("Syntax error: Incomplete command!\n")
						} else {
							cmd[p+strlen(cmd[p:])-1] = 0
							m.printf("Syntax error; I'm ignoring `%s'!\n", cstr(cmd[p:]))
						}
					}

//line mmixsim.w:3983
					for repeating != 0 {

//line mmixsim.w:4273
						if curDispSet {

//line mmixsim.w:4289
							switch curDispMode {
							case 'l':
								m.l[int(Tetra(curDispAddr))&m.lringMask] = m.val
							case '$':
								k = int(curDispAddr & 0xff)
								if k < L {
									m.l[(O+k)&m.lringMask] = m.val
								} else if k >= G {
									m.g[k] = m.val
								}
							case 'g':
								k = int(curDispAddr & 0xff)
								if k < 32 {

//line mmixsim.w:4320
									if k >= 9 && k != rI {
										if k <= 19 {
											break
										}
										if k == rA {
											if m.val >= 0x40000 {
												break
											}
											if m.val >= 0x10000 {
												curRound = mmixarith.Round(m.val >> 16)
											} else {
												curRound = mmixarith.RoundNear
											}
										} else if k == rG {
											if m.val > 255 || m.val < Octa(L) || m.val < 32 {
												break
											}
											for j = int(m.val); j < G; j++ {
												m.g[j] = 0
											}
											G = int(m.val)
										} else if k == rL {
											if m.val < Octa(L) {
												L = int(m.val)
											} else {
												break
											}
										}
									}

//line mmixsim.w:4303
								}
								m.g[k] = m.val
							case 'M':
								if curDispAddr&signBit == 0 {
									ll = m.memFind(curDispAddr)
									ll[0].tet, ll[1].tet = Tetra(m.val>>32), Tetra(m.val)
								}
							}

//line mmixsim.w:4275
						}

//line mmixsim.w:4351
						var aux Octa
						switch curDispMode {
						case 'l':
							k = int(Tetra(curDispAddr)) & m.lringMask
							m.printf("l[%d]=", k)
							aux = m.l[k]
						case '$':
							k = int(curDispAddr & 0xff)
							if k < L {
								m.printf("$%d=l[%d]=", k, (O+k)&m.lringMask)
								aux = m.l[(O+k)&m.lringMask]
							} else if k >= G {
								m.printf("$%d=g[%d]=", k, k)
								aux = m.g[k]
							} else {
								m.printf("$%d=", k)
							}
						case 'g':
							k = int(curDispAddr & 0xff)
							m.printf("g[%d]=", k)
							aux = m.g[k]
						case 'M':
							if curDispAddr&signBit == 0 {
								ll = m.memFind(curDispAddr)
								aux = octa(ll)
							}
							m.printf("M8[#")
							m.printHex(curDispAddr)
							m.printf("]=")
						}
						switch curDispType {
						case '!':
							m.printInt(aux)
						case '.':
							m.out.WriteString(mmixarith.FloatString(aux))
						case '#':
							m.out.WriteByte('#')
							m.printHex(aux)
						case '"':

//line mmixsim.w:4398
							state := 0
							for i = 0; i < 8; i++ {
								c := byte(aux >> (56 - 8*i))
								if c == 0 {
									if state != 0 {
										if state > 1 {
											m.printf("\",0")
										} else {
											m.printf(",0")
										}
										state = 1
									}
								} else if c >= ' ' && c <= '~' {
									if state == 0 {
										m.printf("\"")
									} else if state == 1 {
										m.printf(",\"")
									}
									m.out.WriteByte(c)
									state = 2
								} else {
									if state > 1 {
										m.printf("\",")
									} else if state == 1 {
										m.printf(",")
									}
									m.printf("#%x", c)
									state = 1
								}
							}
							if state == 0 {
								m.printf("0")
							} else if state > 1 {
								m.printf("\"")
							}

//line mmixsim.w:4391
						}

//line mmixsim.w:4277
						m.out.WriteByte('\n')
						repeating--
						if repeating == 0 {
							break
						}
						if curDispMode == 'M' {
							curDispAddr += 8
						} else {
							curDispAddr++
						}

//line mmixsim.w:3985
					}
				}

//line mmixsim.w:3700
			}
		}
		if m.halted {
			break
		}
		for {

//line mmixsim.w:1494
			if resuming {
				loc, inst = m.instPtr-4, Tetra(m.g[rX])
			} else {

//line mmixsim.w:1577
				loc = m.instPtr
				ll = m.memFind(loc)
				inst = ll[0].tet
				m.curFile = int(ll[0].fileNo)
				m.curLine = int(ll[0].lineNo)
				ll[0].freq++
				if ll[0].bkpt&execBit != 0 {
					m.breakpoint = true
				}
				m.tracing = m.breakpoint || ll[0].bkpt&traceBit != 0 || ll[0].freq <= m.traceThreshold
				m.instPtr += 4

//line mmixsim.w:1498
			}
			op = int(inst >> 24)
			xx, yy, zz = int(inst>>16)&0xff, int(inst>>8)&0xff, int(inst)&0xff
			f = int(info[op].flags)
			yz = int(inst & 0xffff)
			x, y, z, a, b = 0, 0, 0, 0, 0
			exc = 0
			oldL = L
			if f&relAddrBit != 0 {

//line mmixsim.w:1943
				if op&0xfe == JMP {
					yz = int(inst & 0xffffff)
				}
				if op&1 != 0 {
					if op == JMPB {
						yz -= 0x1000000
					} else {
						yz -= 0x10000
					}
				}
				y = m.instPtr
				z = loc + Octa(yz<<2)

//line mmixsim.w:1508
			}

//line mmixsim.w:1957
			if resuming && rop != resumeAgain {

//line mmixsim.w:3357
				if rop == resumeSet {
					op = ORI
					y = m.g[rZ]
					z = 0
					exc = int(m.g[rX]>>32) & 0xff00
					f = xIsDestBit
				} else { // |resumeCont|
					y = m.g[rY]
					z = m.g[rZ]
				}

//line mmixsim.w:1959
			} else {
				if f&xIsSourceBit != 0 {

//line mmixsim.w:2002
					if xx >= G {
						b = m.g[xx]
					} else if xx < L {
						b = m.l[(O+xx)&m.lringMask]
					}

//line mmixsim.w:1962
				}
				if info[op].thirdOperand != 0 {

//line mmixsim.w:2077
					b = m.g[info[op].thirdOperand]

//line mmixsim.w:1965
				}
				if f&zIsImmedBit != 0 {
					z = Octa(zz)
				} else if f&zIsSourceBit != 0 {

//line mmixsim.w:1988
					if zz >= G {
						z = m.g[zz]
					} else if zz < L {
						z = m.l[(O+zz)&m.lringMask]
					}

//line mmixsim.w:1970
				} else if op&0xf0 == SETH {

//line mmixsim.w:2073
					z = Octa(yz) << (48 - 16*(op&3))
					y = b

//line mmixsim.w:1972
				}
				if f&yIsImmedBit != 0 {
					y = Octa(yy)
				} else if f&yIsSourceBit != 0 {

//line mmixsim.w:1995
					if yy >= G {
						y = m.g[yy]
					} else if yy < L {
						y = m.l[(O+yy)&m.lringMask]
					}

//line mmixsim.w:1977
				}
			}

//line mmixsim.w:1510
			if f&xIsDestBit != 0 {

//line mmixsim.w:2082
				if xx >= G {
					lhs = fmt.Sprintf("$%d=g[%d]", xx, xx)
					xPtr = &m.g[xx]
				} else {
					for xx >= L {

//line mmixsim.w:2094
						m.l[(O+L)&m.lringMask] = 0
						L++
						m.g[rL] = Octa(L)
						if (m.S-O-L)&m.lringMask == 0 {
							m.stackStore()
						}

//line mmixsim.w:2088
					}
					lhs = fmt.Sprintf("$%d=l[%d]", xx, (O+xx)&m.lringMask)
					xPtr = &m.l[(O+xx)&m.lringMask]
				}

//line mmixsim.w:1512
			}
			w = y + z
			trouble := ""
			if loc>>32 >= 0x20000000 {
				trouble = "!privileged"
			} else {
			perform:
				switch op {

//line mmixsim.w:2182
				case ADD, ADDI:
					x = w // |w=y+z|
					if (y^z)&signBit == 0 && (y^x)&signBit != 0 {
						exc |= vBit
					}
					*xPtr = x

//line mmixsim.w:2196
				case SUB, SUBI, NEG, NEGI:
					x = y - z
					if (x^z)&signBit == 0 && (x^y)&signBit != 0 {
						exc |= vBit
					}
					*xPtr = x
				case ADDU, ADDUI, INCH, INCMH, INCML, INCL:
					x = w
					*xPtr = x
				case SUBU, SUBUI, NEGU, NEGUI:
					x = y - z
					*xPtr = x
				case IIADDU, IIADDUI, IVADDU, IVADDUI, VIIIADDU, VIIIADDUI, XVIADDU, XVIADDUI:
					x = y<<((op&0xf)>>1-3) + z
					*xPtr = x
				case SETH, SETMH, SETML, SETL, GETA, GETAB:
					x = z
					*xPtr = x

//line mmixsim.w:2218
				case OR, ORI, ORH, ORMH, ORML, ORL:
					x = y | z
					*xPtr = x
				case ORN, ORNI:
					x = y | ^z
					*xPtr = x
				case NOR, NORI:
					x = ^(y | z)
					*xPtr = x
				case XOR, XORI:
					x = y ^ z
					*xPtr = x
				case AND, ANDI:
					x = y & z
					*xPtr = x
				case ANDN, ANDNI, ANDNH, ANDNMH, ANDNML, ANDNL:
					x = y &^ z
					*xPtr = x
				case NAND, NANDI:
					x = ^(y & z)
					*xPtr = x
				case NXOR, NXORI:
					x = ^(y ^ z)
					*xPtr = x

//line mmixsim.w:2252
				case SL, SLI:
					sa := shiftAmt(z)
					x = y << sa
					a = mmixarith.ShiftRight(x, sa, false)
					if a != y {
						exc |= vBit
					}
					*xPtr = x
				case SLU, SLUI:
					x = y << shiftAmt(z)
					*xPtr = x
				case SR, SRI, SRU, SRUI:
					x = mmixarith.ShiftRight(y, shiftAmt(z), op&0x2 != 0)
					*xPtr = x
				case MUX, MUXI:
					x = y&b | z&^b
					*xPtr = x
				case SADD, SADDI:
					x = Octa(bits.OnesCount64(y &^ z))
					*xPtr = x

//line mmixsim.w:2277
				case MOR, MORI:
					x = mmixarith.BoolMult(y, z, false)
					*xPtr = x
				case MXOR, MXORI:
					x = mmixarith.BoolMult(y, z, true)
					*xPtr = x
				case BDIF, BDIFI:
					x = mmixarith.ByteDiff(y, z)
					*xPtr = x
				case WDIF, WDIFI:
					x = mmixarith.WydeDiff(y, z)
					*xPtr = x
				case TDIF, TDIFI:
					if y>>32 > z>>32 {
						x = (y>>32 - z>>32) << 32
					}
					if Tetra(y) > Tetra(z) {
						x |= Octa(Tetra(y) - Tetra(z))
					}
					*xPtr = x
				case ODIF, ODIFI:
					if y > z {
						x = y - z
					}
					*xPtr = x

//line mmixsim.w:2317
				case MUL, MULI:
					var overflow bool
					x, overflow = mmixarith.SignedMult(y, z)
					if overflow {
						exc |= vBit
					}
					*xPtr = x
				case MULU, MULUI:
					a, x = bits.Mul64(y, z)
					m.g[rH] = a
					*xPtr = x
				case DIV, DIVI:
					var r Octa
					overflow := false
					if z == 0 {
						r = y
						exc |= dBit
					} else {
						x, r, overflow = mmixarith.SignedDiv(y, z)
					}
					a = r
					m.g[rR] = r
					if overflow {
						exc |= vBit
					}
					*xPtr = x
				case DIVU, DIVUI:
					x, a = mmixarith.Div(b, y, z)
					m.g[rR] = a
					*xPtr = x

//line mmixsim.w:2360
				case FADD, FSUB, FMUL, FDIV, FREM:
					var e int
					switch op {
					case FADD:
						x, e = mmixarith.FPlus(y, z, curRound)
					case FSUB:
						a = z
						if mmixarith.FComp(a, 0) != 2 {
							a ^= signBit
						}
						x, e = mmixarith.FPlus(y, a, curRound)
					case FMUL:
						x, e = mmixarith.FMult(y, z, curRound)
					case FDIV:
						x, e = mmixarith.FDivide(y, z, curRound)
					case FREM:
						x, e = mmixarith.FRemStep(y, z, 2500)
					}
					roundMode = curRound
					exc |= e
					*xPtr = x

//line mmixsim.w:2386
				case FSQRT, FINT, FIX, FIXU, FLOT, FLOTI, FLOTU, FLOTUI,
					SFLOT, SFLOTI, SFLOTU, SFLOTUI:
					if y > 4 {
						trouble = "!illegal"
						break perform
					}
					roundMode = curRound
					if y != 0 {
						roundMode = mmixarith.Round(y)
					}
					var e int
					switch op {
					case FSQRT:
						x, e = mmixarith.FRoot(z, roundMode)
					case FINT:
						x, e = mmixarith.FIntegerize(z, roundMode)
					case FIX:
						x, e = mmixarith.FixIt(z, roundMode)
					case FIXU:
						x, e = mmixarith.FixIt(z, roundMode)
						e &^= wBit
					default:
						x, e = mmixarith.FloatIt(z, roundMode, op&0x2 != 0, op&0x4 != 0)
					}
					exc |= e
					*xPtr = x

//line mmixsim.w:2423
				case CMP, CMPI:
					if int64(y) < int64(z) {
						x = negOne
					} else if y != z {
						x = 1
					}
					*xPtr = x
				case CMPU, CMPUI:
					if y < z {
						x = negOne
					} else if y != z {
						x = 1
					}
					*xPtr = x

//line mmixsim.w:2439
				case FCMP, FCMPE:
					k = 0
					if op == FCMPE {
						k = mmixarith.FEpsComp(y, z, b, true)
					}
					if k == 0 {
						k = mmixarith.FComp(y, z)
						if k < 0 {
							x = negOne
						} else if k == 1 {
							x = 1
						}
					}
					if k == 2 {
						exc |= iBit
					}
					*xPtr = x
				case FUN:
					if mmixarith.FComp(y, z) == 2 {
						x = 1
					}
					*xPtr = x
				case FEQL:
					if mmixarith.FComp(y, z) == 0 {
						x = 1
					}
					*xPtr = x
				case FEQLE:
					k = mmixarith.FEpsComp(y, z, b, false)
					if k == 1 {
						x = 1
					} else if k == 2 {
						exc |= iBit
					}
					*xPtr = x
				case FUNE:
					if mmixarith.FEpsComp(y, z, b, true) == 2 {
						x = 1
					}
					*xPtr = x

//line mmixsim.w:2506
				case CSN, CSNI, CSZ, CSZI, CSP, CSPI, CSOD, CSODI,
					CSNN, CSNNI, CSNZ, CSNZI, CSNP, CSNPI, CSEV, CSEVI,
					ZSN, ZSNI, ZSZ, ZSZI, ZSP, ZSPI, ZSOD, ZSODI,
					ZSNN, ZSNNI, ZSNZ, ZSNZI, ZSNP, ZSNPI, ZSEV, ZSEVI:
					if registerTruth(y, op) {
						x = z
					} else {
						x = b
					}
					*xPtr = x

//line mmixsim.w:2525
				case BN, BNB, BZ, BZB, BP, BPB, BOD, BODB,
					BNN, BNNB, BNZ, BNZB, BNP, BNPB, BEV, BEVB,
					PBN, PBNB, PBZ, PBZB, PBP, PBPB, PBOD, PBODB,
					PBNN, PBNNB, PBNZ, PBNZB, PBNP, PBNPB, PBEV, PBEVB:
					if registerTruth(b, op) {
						x = 1
						m.instPtr = z
						good = op >= PBN
					} else {
						good = op < PBN
					}
					if good {
						m.goodGuesses++
					} else {
						m.badGuesses++
						m.sclock = m.sclock&^0xffffffff | Octa(Tetra(m.sclock)+2) // 짐작이 틀리면 벌칙은 $2\upsilon$
						if m.g[rI] <= 2 && m.g[rI] != 0 {
							m.tracing, m.breakpoint = true, true
						}
						m.g[rI] -= 2
					}

//line mmixsim.w:2554
				case LDB, LDBI, LDBU, LDBUI, LDW, LDWI, LDWU, LDWUI,
					LDT, LDTI, LDTU, LDTUI, LDHT, LDHTI:
					switch op &^ 3 {
					case LDB:
						i, j = 56, int(w&0x3)<<3
					case LDW:
						i, j = 48, int(w&0x2)<<3
					case LDT:
						i, j = 32, 0
					default:
						i, j = 0, 0
					}
					ll = m.memFind(w)
					m.testLoadBkpt(ll[0])
					x = mmixarith.ShiftRight(Octa(ll[0].tet)<<32<<j, i, op&0x2 != 0)

//line mmixsim.w:2584
					if w&signBit != 0 {
						trouble = "!privileged"
					} else {
						*xPtr = x
					}

//line mmixsim.w:2570
				case LDO, LDOI, LDOU, LDOUI, LDUNC, LDUNCI:
					w &^= 7
					ll = m.memFind(w)
					m.testLoadBkpt(ll[0])
					m.testLoadBkpt(ll[1])
					x = octa(ll)

//line mmixsim.w:2584
					if w&signBit != 0 {
						trouble = "!privileged"
					} else {
						*xPtr = x
					}

//line mmixsim.w:2577
				case LDSF, LDSFI:
					ll = m.memFind(w)
					m.testLoadBkpt(ll[0])
					x = mmixarith.LoadSF(ll[0].tet)

//line mmixsim.w:2584
					if w&signBit != 0 {
						trouble = "!privileged"
					} else {
						*xPtr = x
					}

//line mmixsim.w:2595
				case STB, STBI, STBU, STBUI, STW, STWI, STWU, STWUI,
					STT, STTI, STTU, STTUI:
					switch op &^ 3 {
					case STB:
						i, j = 56, int(w&0x3)<<3
					case STW:
						i, j = 48, int(w&0x2)<<3
					default:
						i, j = 32, 0
					}
					ll = m.memFind(w)
					if op&0x2 == 0 {
						a = mmixarith.ShiftRight(b<<i, i, false)
						if a != b {
							exc |= vBit
						}
					}
					ll[0].tet ^= (ll[0].tet ^ Tetra(b)<<(i-32-j)) & (^Tetra(0) << (i - 32) >> j)

//line mmixsim.w:2636
					m.testStoreBkpt(ll[0])
					w &^= 7
					ll = m.memFind(w)
					a = octa(ll) // 추적 출력을 위해
					if w&signBit != 0 {
						trouble = "!privileged"
					}

//line mmixsim.w:2614
				case STSF, STSFI:
					ll = m.memFind(w)
					ll[0].tet, exc = mmixarith.StoreSF(b, curRound)

//line mmixsim.w:2636
					m.testStoreBkpt(ll[0])
					w &^= 7
					ll = m.memFind(w)
					a = octa(ll) // 추적 출력을 위해
					if w&signBit != 0 {
						trouble = "!privileged"
					}

//line mmixsim.w:2618
				case STHT, STHTI:
					ll = m.memFind(w)
					ll[0].tet = Tetra(b >> 32)

//line mmixsim.w:2636
					m.testStoreBkpt(ll[0])
					w &^= 7
					ll = m.memFind(w)
					a = octa(ll) // 추적 출력을 위해
					if w&signBit != 0 {
						trouble = "!privileged"
					}

//line mmixsim.w:2622
				case STCO, STCOI, STO, STOI, STOU, STOUI, STUNC, STUNCI:
					if op&^1 == STCO {
						b = Octa(xx)
					}
					w &^= 7
					ll = m.memFind(w)
					m.testStoreBkpt(ll[0])
					m.testStoreBkpt(ll[1])
					ll[0].tet, ll[1].tet = Tetra(b>>32), Tetra(b)
					if w&signBit != 0 {
						trouble = "!privileged"
					}

//line mmixsim.w:2648
				case CSWAP, CSWAPI:
					w &^= 7
					ll = m.memFind(w)
					m.testLoadBkpt(ll[0])
					m.testLoadBkpt(ll[1])
					a = m.g[rP]
					if octa(ll) == a {
						x = 1
						m.testStoreBkpt(ll[0])
						m.testStoreBkpt(ll[1])
						ll[0].tet, ll[1].tet = Tetra(b>>32), Tetra(b)
						rhs = "M8[%#w]=%#b"
					} else {
						b = octa(ll)
						m.g[rP] = b
						rhs = "rP=%#b"
					}

//line mmixsim.w:2584
					if w&signBit != 0 {
						trouble = "!privileged"
					} else {
						*xPtr = x
					}

//line mmixsim.w:2670
				case GET:
					if yy != 0 || zz >= 32 {
						trouble = "!illegal"
						break perform
					}
					x = m.g[zz]
					*xPtr = x
				case PUT, PUTI:
					if yy != 0 || xx >= 32 {
						trouble = "!illegal"
						break perform
					}
					rhs = "%z = %#z"
					if xx >= 8 {
						if xx <= 11 && xx != 8 {
							trouble = "!illegal" // rN, rO, rS는 바꿀 수 없다
							break perform
						}
						if xx <= 18 {
							trouble = "!privileged"
							break perform
						}
						if xx == rA {

//line mmixsim.w:2732
							if z >= 0x40000 {
								trouble = "!illegal"
								break perform
							}
							if z >= 0x10000 {
								curRound = mmixarith.Round(z >> 16)
							} else {
								curRound = mmixarith.RoundNear
							}

//line mmixsim.w:2694
						} else if xx == rL {

//line mmixsim.w:2704
							x = z
							if z>>32 != 0 {
								rhs = "min(rL,%#x) = %z"
							} else {
								rhs = "min(rL,%x) = %z"
							}
							if Tetra(z) > Tetra(L) || z>>32 != 0 {
								z = Octa(L)
							} else {
								L = int(z)
								oldL = L
							}

//line mmixsim.w:2696
						} else if xx == rG {

//line mmixsim.w:2718
							if z > 255 || z < Octa(L) || z < 32 {
								trouble = "!illegal"
								break perform
							}
							for j = int(z); j < G; j++ {
								m.g[j] = 0
							}
							G = int(z)

//line mmixsim.w:2698
						}
					}
					m.g[xx] = z
					zz = xx

//line mmixsim.w:2750
				case PUSHGO, PUSHGOI, PUSHJ, PUSHJB:
					if op == PUSHGO || op == PUSHGOI {
						m.instPtr = w
					} else {
						m.instPtr = z
					}
					if xx >= G {
						xx = L
						L++
						if (m.S-O-L)&m.lringMask == 0 {
							m.stackStore()
						}
					}
					x = Octa(xx)
					m.l[(O+xx)&m.lringMask] = x // ``구멍''은 밀어 넣은 양을 기록한다
					lhs = fmt.Sprintf("l[%d]=%d, ", (O+xx)&m.lringMask, xx)
					x = loc + 4
					m.g[rJ] = x
					L -= xx + 1
					O += xx + 1
					b = m.g[rO] + Octa((xx+1)<<3)
					m.g[rO] = b
					a = Octa(L)
					m.g[rL] = a

//line mmixsim.w:2779
				case POP:
					if xx != 0 && xx <= L {
						y = m.l[(O+xx-1)&m.lringMask]
					}
					if Tetra(m.g[rS]) == Tetra(m.g[rO]) {
						m.stackLoad()
					}
					k = int(m.l[(O-1)&m.lringMask] & 0xff)
					for Tetra(O-m.S) <= Tetra(k) {
						m.stackLoad()
					}
					if xx <= L {
						L = k + xx
					} else {
						L = k + L + 1
					}
					if L > G {
						L = G
					}
					if L > k {
						m.l[(O-1)&m.lringMask] = y
						lhs = fmt.Sprintf("l[%d]=#%x, ", (O-1)&m.lringMask, y)
					} else {
						lhs = ""
					}
					y = m.g[rJ]
					z = Octa(yz << 2)
					m.instPtr = y + z
					O -= k + 1
					b = m.g[rO] - Octa((k+1)<<3)
					m.g[rO] = b
					a = Octa(L)
					m.g[rL] = a

//line mmixsim.w:2821
				case SAVE:
					if xx < G || yy != 0 || zz != 0 {
						trouble = "!illegal"
						break perform
					}
					i = (O + L) & m.lringMask
					m.l[i] = m.l[i]&^0xffffffff | Octa(L)
					L++
					if (m.S-O-L)&m.lringMask == 0 {
						m.stackStore()
					}
					O += L
					m.g[rO] += Octa(L << 3)
					L = 0
					m.g[rL] = 0
					for Tetra(m.g[rO]) != Tetra(m.g[rS]) {
						m.stackStore()
					}
					for k = G; ; {

//line mmixsim.w:2860
						ll = m.memFind(m.g[rS])
						if k == rZ+1 {
							x = Octa(G)<<56 | Octa(Tetra(m.g[rA]))
						} else {
							x = m.g[k]
						}
						ll[0].tet = Tetra(x >> 32)
						m.testStoreBkpt(ll[0])
						ll[1].tet = Tetra(x)
						m.testStoreBkpt(ll[1])
						if m.stackTracing {
							m.tracing = true
							if m.curLine != 0 {
								m.showLine()
							}
							if k >= 32 {
								m.printf("             M8[#%016x]=g[%d]=#%016x, rS+=8\n", m.g[rS], k, x)
							} else {
								name := "(rG,rA)"
								if k != rZ+1 {
									name = specialName[k]
								}
								m.printf("             M8[#%016x]=%s=#%016x, rS+=8\n", m.g[rS], name, x)
							}
						}
						m.S++
						m.g[rS] += 8

//line mmixsim.w:2841
						if k == 255 {
							k = rB
						} else if k == rR {
							k = rP
						} else if k == rZ+1 {
							break
						} else {
							k++
						}
					}
					O = m.S
					m.g[rO] = m.g[rS]
					x = m.g[rO] - 8
					*xPtr = x

//line mmixsim.w:2889
				case UNSAVE:
					if xx != 0 || yy != 0 {
						trouble = "!illegal"
						break perform
					}
					z &^= 7
					m.g[rS] = z + 8
					for k = rZ + 1; ; {

//line mmixsim.w:2926
						m.g[rS] -= 8
						ll = m.memFind(m.g[rS])
						m.testLoadBkpt(ll[0])
						m.testLoadBkpt(ll[1])
						if k == rZ+1 {
							G = int(ll[0].tet >> 24)
							x = Octa(G)
							m.g[rG] = x
							a = Octa(ll[1].tet & 0x3ffff)
							m.g[rA] = a
							if G < 32 {
								G = 32
								x = 32
								m.g[rG] = 32
							}
						} else {
							m.g[k] = octa(ll)
						}
						if m.stackTracing {
							m.tracing = true
							if m.curLine != 0 {
								m.showLine()
							}
							if k >= 32 {
								m.printf("             rS-=8, g[%d]=M8[#%016x]=#%016x\n", k, m.g[rS], octa(ll))
							} else if k == rZ+1 {
								m.printf("             (rG,rA)=M8[#%016x]=#%016x\n", m.g[rS], octa(ll))
							} else {
								m.printf("             rS-=8, %s=M8[#%016x]=#%016x\n",
									specialName[k], m.g[rS], octa(ll))
							}
						}

//line mmixsim.w:2898
						if k == rP {
							k = rR
						} else if k == rB {
							k = 255
						} else if k == G {
							break
						} else {
							k--
						}
					}
					m.S = int(Tetra(m.g[rS]) >> 3)
					m.stackLoad()
					k = int(m.l[m.S&m.lringMask] & 0xff)
					for j = 0; j < k; j++ {
						m.stackLoad()
					}
					O = m.S
					m.g[rO] = m.g[rS]
					if k > G {
						L = G
					} else {
						L = k
					}
					m.g[rL] = Octa(L)
					a = m.g[rL]
					m.g[rG] = Octa(G)

//line mmixsim.w:2964
				case SYNCID, SYNCIDI, PREST, PRESTI, SYNCD, SYNCDI, PREGO, PREGOI, PRELD, PRELDI:
					x = w + Octa(xx)

//line mmixsim.w:2974
				case GO, GOI:
					x = m.instPtr
					m.instPtr = w
					*xPtr = x
				case JMP, JMPB:
					m.instPtr = z
				case SWYM:
				case SYNC:
					if xx != 0 || yy != 0 || zz > 7 {
						trouble = "!illegal"
					} else if zz > 3 {
						trouble = "!privileged"
					}
				case LDVTS, LDVTSI:
					trouble = "!privileged"

//line mmixsim.w:3013
				case TRIP:
					exc |= hBit
				case TRAP:
					if xx != 0 || yy > maxSysCall {
						trouble = "!privileged"
						break perform
					}
					rhs = trapFormat[yy]
					m.g[rWW] = m.instPtr
					m.g[rXX] = signBit | Octa(inst)
					m.g[rYY], m.g[rZZ] = y, z
					z = Octa(zz)
					a = b + 8

//line mmixsim.w:3099
					if argCount[yy] == 3 {
						mb = m.memArg(b)
						ma = m.memArg(a)
					}

//line mmixsim.w:3027

//line mmixsim.w:3032
					switch yy {
					case Halt:

//line mmixsim.w:3063
						if zz == 0 {
							m.halted, m.breakpoint = true, true
						} else if zz == 1 {
							if loc >= 0x90 {
								trouble = "!privileged"
								break perform
							}
							m.io.PrintTripWarning(int(loc>>4), m.g[rW]-4)
						} else {
							trouble = "!privileged"
							break perform
						}

//line mmixsim.w:3035
						m.g[rBB] = m.g[255]
					case Fopen:
						m.g[rBB] = m.io.Fopen(byte(zz), mb, ma)
					case Fclose:
						m.g[rBB] = m.io.Fclose(byte(zz))
					case Fread:
						m.g[rBB] = m.io.Fread(byte(zz), mb, ma)
					case Fgets:
						m.g[rBB] = m.io.Fgets(byte(zz), mb, ma)
					case Fgetws:
						m.g[rBB] = m.io.Fgetws(byte(zz), mb, ma)
					case Fwrite:
						m.g[rBB] = m.io.Fwrite(byte(zz), mb, ma)
					case Fputs:
						m.g[rBB] = m.io.Fputs(byte(zz), b)
					case Fputws:
						m.g[rBB] = m.io.Fputws(byte(zz), b)
					case Fseek:
						m.g[rBB] = m.io.Fseek(byte(zz), b)
					case Ftell:
						m.g[rBB] = m.io.Ftell(byte(zz))
					}

//line mmixsim.w:3028
					x = m.g[rBB]
					m.g[255] = x

//line mmixsim.w:3302
				case RESUME:
					if xx != 0 || yy != 0 || zz != 0 {
						trouble = "!illegal"
						break perform
					}
					z = m.g[rW]
					m.instPtr = z
					b = m.g[rX]
					if b&signBit == 0 {

//line mmixsim.w:3330
						rop = int(b >> 56) // ropcode는 rX의 맨 윗 바이트다
						switch rop {
						case resumeCont:
							if 1<<(Tetra(b)>>28)&0x8f30 != 0 {
								trouble = "!illegal"
								break perform
							}
							fallthrough
						case resumeSet:
							k = int(b>>16) & 0xff
							if k >= L && k < G {
								trouble = "!illegal"
								break perform
							}
							fallthrough
						case resumeAgain:
							if Tetra(b)>>24 == RESUME {
								trouble = "!illegal"
								break perform
							}
						default:
							trouble = "!illegal"
							break perform
						}
						resuming = true

//line mmixsim.w:3312
					}

//line mmixsim.w:1521
				}
			}
			if trouble != "" {

//line mmixsim.w:2994
				lhs = trouble
				m.breakpoint, m.tracing = true, true
				if !m.interacting && !m.interactAfterBreak {
					m.halted = true
				}

//line mmixsim.w:1525
			}

//line mmixsim.w:3266
			if exc&(uBit+xBit) == uBit && m.g[rA]&uBit == 0 {
				exc &^= uBit
			}
			if exc != 0 {
				if exc&m.tracingExceptions != 0 {
					m.tracing = true
				}
				j = exc & (int(Tetra(m.g[rA])) | hBit) // 허용된 예외를 모두 찾는다
				if j != 0 {

//line mmixsim.w:3281
					tripping = true
					for k = 0; j&hBit == 0; j, k = j<<1, k+1 {
					}
					exc &^= hBit >> k // 취한 트립은 사건으로 기록하지 않는다
					m.g[rW] = m.instPtr
					m.instPtr = Octa(k << 4)
					m.g[rX] = signBit | Octa(inst)
					if op&0xe0 == STB {
						m.g[rY], m.g[rZ] = w, b
					} else {
						m.g[rY], m.g[rZ] = y, z
					}
					m.g[rB] = m.g[255]
					m.g[255] = m.g[rJ]
					if op == TRIP {
						w, x, a = m.g[rW], m.g[rX], m.g[255]
					}

//line mmixsim.w:3276
				}
				m.g[rA] |= Octa(exc >> 8)
			}

//line mmixsim.w:3375
			if m.sclock != 0 || !resuming {
				m.sclock += Octa(info[op].mems) << 32 // $\mu$마다 시계가 $2^{32}$씩 올라간다
				m.sclock += Octa(info[op].oops)       // $\upsilon$마다 시계가 1씩 올라간다
				if (loc&signBit == 0 || m.g[rU]&(0x8000<<32) != 0) &&
					Octa(op)&(m.g[rU]>>48) == m.g[rU]>>56 {
					const count = 1<<47 - 1
					m.g[rU] = m.g[rU]&^count | (m.g[rU]+1)&count
				} // 사용 계수기는 흉내 낸 명령 가운데 조건에 맞는 것을 센다
				if m.g[rI] <= Octa(info[op].oops) && m.g[rI] != 0 {
					m.tracing, m.breakpoint = true, true
				}
				m.g[rI] -= Octa(info[op].oops) // 구간 $\upsilon$ 타이머는 거꾸로 센다
			}

//line mmixsim.w:3393
			if m.tracing {
				if m.showingSource && m.curLine != 0 {
					m.showLine()
				}

//line mmixsim.w:3416
				if resuming && op != RESUME {
					switch rop {
					case resumeAgain:
						m.printf("           (%016x: %08x (%s)) ", loc, inst, info[op].name)
					case resumeCont:
						m.printf("           (%016x: %04xrYrZ (%s)) ", loc, inst>>16, info[op].name)
					case resumeSet:
						m.printf("           (%016x: ..%02x..rZ (SET)) ", loc, (inst>>16)&0xff)
					}
				} else {
					ll = m.memFind(loc)
					m.printf("%10d. %016x: %08x (%s) ", int32(ll[0].freq), loc, inst, info[op].name)
				}

//line mmixsim.w:3398

//line mmixsim.w:3438
				if lhs != "" && lhs[0] == '!' {
					m.printf("%s instruction!\n", lhs[1:]) // 특권 명령이거나 불법 명령
				} else {

//line mmixsim.w:3463
					if L != oldL && f&pushPopBit == 0 {
						m.printf("rL=%d, ", L)
					}

//line mmixsim.w:3442
					fs := info[op].traceFormat
					if Tetra(z) == 0 && (op == ADDUI || op == ORI) {
						fs = "%l = %y = %#x" // \.{LDA}, \.{SET}
					}
					for p = 0; p < len(fs); p++ {

//line mmixsim.w:3509
						if fs[p] != '%' {
							m.out.WriteByte(fs[p])
						} else {
							style := decimal
						charSwitch:
							for {
								p++
								switch fs[p] {

//line mmixsim.w:3534
								case '#':
									style = hex
									continue charSwitch
								case '0':
									style = zhex
									continue charSwitch
								case '.':
									style = floating
									continue charSwitch
								case '!':
									style = handle
									continue charSwitch

//line mmixsim.w:3559
								case 'a':
									m.tracePrint(a, style)
								case 'b':
									m.tracePrint(b, style)
								case 'p':
									m.tracePrint(ma, style)
								case 'q':
									m.tracePrint(mb, style)
								case 'w':
									m.tracePrint(w, style)
								case 'x':
									m.tracePrint(x, style)
								case 'y':
									m.tracePrint(y, style)
								case 'z':
									m.tracePrint(z, style)

//line mmixsim.w:3608
								case '(':
									m.out.WriteByte(leftParen[roundMode])
								case ')':
									m.out.WriteByte(rightParen[roundMode])
								case 't':
									if Tetra(x) != 0 {
										m.printf(" Yes, -> #")
										m.printHex(m.instPtr)
									} else {
										m.printf(" No")
									}
								case 'g':
									if !good {
										m.printf(" (bad guess)")
									}
								case 's':
									m.out.WriteString(specialName[zz])
								case '?':
									p++
									if Tetra(z) != 0 {
										m.out.WriteByte(fs[p])
										m.printf("%d", int32(Tetra(z)))
									}
								case 'l':
									m.out.WriteString(lhs)
								case 'r':
									fs, p = rhs, -1

//line mmixsim.w:3518
								default:
									m.printf("BUG!!") // 일어날 수 없다
								}
								break
							}
						}

//line mmixsim.w:3448
					}
					if exc != 0 {
						m.printf(", rA=#%05x", Tetra(m.g[rA]))
					}
					if tripping {
						tripping = false
						m.printf(", -> #%02x", Tetra(m.instPtr))
					}
					m.printf("\n")
				}

//line mmixsim.w:3399
				if m.showingStats || m.breakpoint {
					m.showStats(m.breakpoint)
				}
				justTraced = true
			} else if justTraced {
				m.printf(" ...............................................\n")
				justTraced = false
				m.shownLine = -m.gap - 1 // 빈틈을 채우지 않는다
			}

//line mmixsim.w:1529
			if resuming && op != RESUME {
				resuming = false
			}

//line mmixsim.w:3707
			if (m.interrupt.Load() || m.breakpoint) && !resuming {
				break
			}
		}
		if m.interactAfterBreak {
			m.interacting, m.interactAfterBreak = true, false
		}
	}
	if m.profiling {

//line mmixsim.w:1383
		m.printf("\nProgram profile:\n")
		m.shownFile, m.curFile = -1, -1
		m.shownLine, m.curLine = 0, 0
		m.gap = m.profileGap
		m.showingSource = m.profileShowingSource
		m.impliedLoc = negOne
		m.printFreqs(m.memRoot)

//line mmixsim.w:3717
	}
	if m.interacting || m.profiling || m.showingStats {
		m.showStats(true)
	}
	return int(int32(Tetra(m.g[255]))) // 비대화식 실행에 초보적인 되먹임을 준다

//line mmixsim.w:109
}

func main() {
	os.Exit(mmix(os.Args, os.Stdin, os.Stdout, os.Stderr))
}
