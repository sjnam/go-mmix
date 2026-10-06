//line mmixpipe.w:43
package main

import (
	"bufio"
	"fmt"
	"io"
	"math/bits"

	"github.com/sjnam/go-mmix/mmixarith"
	"github.com/sjnam/go-mmix/mmixio"
)

//line mmixpipe.w:278
type (
	Tetra = mmixarith.Tetra // 부호 없는 32비트 정수
	Octa  = mmixarith.Octa  // 두 테트라바이트가 모여 옥타바이트를 이룬다
)

//line mmixpipe.w:341
type coroutine struct {
	name    string     // 코루틴의 기호 이름
	stage   int        // 그 순위
	next    *coroutine // 그다음 것
	lockloc *lockvar   // 그것이 잠그고 있을지 모르는 것
	ctl     *control   // 그 데이터
	succ    *coroutine // 원본의 |self+1|
}

//line mmixpipe.w:482
type lockvar = *coroutine

//line mmixpipe.w:539
type spec struct {
	o Octa
	p *specnode
}

type specnode struct {
	o        Octa
	known    bool
	addr     Octa
	up, down *specnode
	ctl      *control // 이 \KW{specnode}를 담은 제어 블록
}

//line mmixpipe.w:611
type control struct {
	loc             Octa // 명령이 나온 가상 주소
	op              int  // 원래의 명령 바이트들
	xx, yy, zz      byte
	y, z, b, ra     spec       // 입력
	x, a, goLoc, rl specnode   // 출력
	owner           *coroutine // 이것을 |ctl|로 가진 코루틴
	i               int        // 내부 연산 코드
	state           int        // 내부 마음가짐

//line mmixpipe.w:633
	usage      bool // rU를 늘려야 하는가?
	needB      bool // |b.p==nil|이 될 때까지 멈추어야 하는가?
	needRA     bool // |ra.p==nil|이 될 때까지 멈추어야 하는가?
	renX       bool // |x|가 이름 바꾸기 레지스터에 해당하는가?
	memX       bool // |x|가 메모리 쓰기에 해당하는가?
	renA       bool // |a|가 이름 바꾸기 레지스터에 해당하는가?
	setL       bool // |rl|이 rL의 새 값에 해당하는가?
	interim    bool // 인터럽트가 걸리면 이 명령을 다시 발행해야 하는가?
	stackAlert bool // 스택 넘침의 가능성이 있는가?

//line mmixpipe.w:621
	arithExc         Tetra // rA의 사건 비트를 위한 산술 예외
	hist             Tetra // 분기 예측에 쓰는 이력 비트
	denin, denout    int   // 비정규수를 다루는 데 드는 실행 시간 벌칙
	curO, curS       Octa  // 이 명령 전의 투기적 rO와 rS
	interrupt        Tetra // 이 명령이 인터럽트를 일으키는가?
	ptrA, ptrB, ptrC any   // 이런저런 쓰임새의 범용 포인터
	idx              int   // 재정렬 버퍼 안의 위치
}

//line mmixpipe.w:1349
type fetch struct {
	loc       Octa  // 명령의 가상 주소
	inst      Tetra // 명령 자체
	interrupt Tetra // 인터럽트를 일으킬지 모르는 비트 코드들
	noted     bool  // 이 명령을 엿보았는가?
	hist      Tetra // 엿보았다면, 그때의 |peekHist|
	idx       int   // 가져오기 버퍼 안의 위치
}

//line mmixpipe.w:1522
type funcUnit struct {
	name string      // 기호 이름
	ops  [8]Tetra    // 지원하는 연산 코드의 큰 쪽 먼저 비트맵
	k    int         // 파이프라인 단계의 수
	co   []coroutine // 차례로 늘어선 코루틴 $k$개
}

//line mmixpipe.w:2527
type label int

//line mmixpipe.w:3430
type replacePolicy int

const (
	random replacePolicy = iota
	serial
	pseudoLRU
	lru

//line mmixpipe.w:3437
)

//line mmixpipe.w:3476
type cacheblock struct {
	tag   Octa   // 캐시 블록 주소에 들어가지 않는 열쇠의 비트들
	dirty []bool // 알갱이마다 하나씩 있는 더러움 비트 $2^{g-b}$개의 배열
	data  []Octa // 옥타바이트 $2^{b-3}$개의 배열, 곧 캐시 블록의 데이터
	rank  int    // |random|이 아닌 방침을 위한 보조 정보
	pos   int    // 집합 안의 위치
}

type cacheset = []cacheblock // 블록 $2^a$개나 $2^v$개의 배열

type cache struct {
	a, b, c, g, v      int           // 연관도, 블록 크기, 집합 수, 알갱이, 희생자 크기의 로그
	aa, bb, cc, gg, vv int           // 연관도, 블록 크기, 집합 수, 알갱이, 희생자 크기(모두 2의 거듭제곱)
	tagmask            int           // $-2^{b+c}$
	repl, vrepl        replacePolicy // 희생자와 희생자의 희생자를 고르는 방법
	mode               int           // 선택 사항 |writeBack|과 |writeAlloc|
	accessTime         int           // 적중인지 알기까지의 사이클
	copyInTime         int           // 새 블록을 캐시에 복사해 넣는 사이클
	copyOutTime        int           // 옛 블록을 캐시에서 복사해 내는 사이클
	set                []cacheset    // 캐시 블록 배열의 집합 $2^c$개의 배열
	victim             cacheset      // 있다면, 희생자 캐시
	filler             coroutine     // 새 블록을 캐시에 복사해 넣는 코루틴
	fillerCtl          control       // 그 제어 블록
	flusher            coroutine     // 캐시의 더러운 옛 데이터를 쓰는 코루틴
	flusherCtl         control       // 그 제어 블록
	inbuf              cacheblock    // 채우기는 여기서 온다
	outbuf             cacheblock    // 쏟아 내기는 여기로 간다
	lock               lockvar       // 캐시를 크게 바꾸는 동안 0이 아니다
	fillLock           lockvar       // 채우는 코루틴이 데이터를 돌려주어야 하면 0이 아니다
	ports              int           // 몇 개의 코루틴이 캐시를 읽을 수 있는가?
	reader             []coroutine   // 동시에 읽을지도 모르는 코루틴들의 배열
	name               string        // 이를테면 |"Icache"|
}

//line mmixpipe.w:3953
type chunknode struct {
	tag   Tetra  // 32비트 덩이 주소
	chunk []Octa // |nil|이거나 옥타바이트 $2^{13}$개의 배열
}

//line mmixpipe.w:4935
type writeNode struct {
	o     Octa  // 저장할 데이터
	addr  Octa  // 그 물리 주소
	stamp Tetra // 마지막으로 확정된 때($2^{32}$을 법으로)
	i     int   // 이 쓰기는 특별한가?
	size  int   // |specWrite|의 매개변수
	idx   int   // 쓰기 버퍼 안의 위치
}

//line mmixpipe.w:8595
type machine struct {

//line mmixpipe.w:138
	verbose int // 진단 출력의 수준을 정한다

//line mmixpipe.w:198
	breakpointHit bool // 멈춤점의 명령을 가져왔는가?
	halted        bool // 기계가 멈추었는가?
	breakpoint    Octa // |MMIXRun|의 멈춤점

//line mmixpipe.w:311
	curRound   mmixarith.Round // 현재 반올림 방식
	exceptions int             // 부동소수점 연산이 켠 비트들

//line mmixpipe.w:410
	ringSize int         // |MMIX_config|가 정한다. 넉넉히 커야 한다
	ring     []coroutine // 스케줄 큐들의 머리 노드
	curTime  int         // |ring|에서 현재 시각의 위치

//line mmixpipe.w:466
	sentinel coroutine // 원형 리스트의 원점에 있는 가짜 코루틴

//line mmixpipe.w:1192
	fetchMax, dispatchMax, peekahead, commitMax int // 한 클럭 사이클에 다룰 수 있는 명령의 한계

//line mmixpipe.w:1214
	reorder                []control // 재정렬 버퍼가 든 원
	reorderBot, reorderTop *control  // 그 원의 가장 작은 원소와 가장 큰 원소
	hot, cool              *control  // 재정렬 버퍼의 앞과 뒤
	oldHot                 *control  // 사이클이 시작할 때의 |hot|
	deissues               int       // 발행을 취소해야 할 명령의 개수

//line mmixpipe.w:1299
	dispatchCount    int     // 이 사이클에 몇 개를 배정했는가
	suppressDispatch bool    // 배정을 건너뛰어야 하는가?
	doingInterrupt   int     // 인터럽트 준비가 몇 사이클 남았는가
	dispatchLock     lockvar // 명령 발행을 막는 잠금
	dispatchStat     []int32 // 명령을 0, 1, \dots개 배정한 것이 몇 번인가?
	securityDisabled bool    // 시험을 위해 보안 검사를 생략하는가?

//line mmixpipe.w:1366
	fetchBuf           []fetch // 가져오기 버퍼가 든 원
	fetchBot, fetchTop *fetch  // 그 원의 가장 작은 원소와 가장 큰 원소
	head, tail         *fetch  // 가져오기 버퍼의 앞과 뒤
	oldTail            *fetch  // 현재 사이클에 볼 수 있는 가져오기 버퍼의 뒤

//line mmixpipe.w:1387
	unknownSpec specnode // 원본의 \.{UNKNOWN\_SPEC}이 가리키는 곳

//line mmixpipe.w:1530
	funit      []funcUnit // 기능 장치들의 배열
	funitCount int        // 기능 장치의 개수

//line mmixpipe.w:1537
	newCool  *control // |cool| 다음의 재정렬 버퍼 자리
	resuming int      // 중단된 명령을 다시 시작하고 있으면 0이 아니다
	support  [8]Tetra // 지원하는 모든 연산 코드의 큰 쪽 먼저 비트맵

//line mmixpipe.w:1752
	g                          [256]specnode // 전역 레지스터와 특수 레지스터
	l                          []specnode    // 지역 레지스터의 고리
	lringSize                  int           // 칩에 있는 지역 레지스터의 수(2의 거듭제곱이어야 한다)
	maxRenameRegs, maxMemSlots int           // 재정렬 버퍼의 용량
	renameRegs, memSlots       int           // 지금 쓰지 않는 용량

//line mmixpipe.w:1762
	ticks     Octa // 내부 시계
	lringMask int  // |lringSize|를 법으로 하는 계산을 위해

//line mmixpipe.w:1870
	coolO, coolS       Octa  // |cool| 명령 전의 rO와 rS
	coolL, coolG       int   // |cool| 명령 전의 rL과 rG
	coolHist, peekHist Tetra // 분기 예측을 위한 이력 비트
	newO, newS         Octa  // |cool| 다음의 rO와 rS

//line mmixpipe.w:2173
	mem specnode

//line mmixpipe.w:2576
	memLocker coroutine // 사라지는 하찮은 코루틴
	dLocker   coroutine // 또 하나
	vanishCtl control   // 그런 코루틴들이 함께 쓰는 제어 블록

//line mmixpipe.w:2790
	pipeSeq [maxPipeOp + 1][pipeLimit + 1]byte

//line mmixpipe.w:3091
	newQ            Octa // rQ의 어느 비트가 늘면 이것도 그래야 한다
	stackOverflowed bool // 아직 알리지 않은 스택 넘침

//line mmixpipe.w:3159
	bpA, bpB, bpC, bpN int    // 분기 예측의 매개변수
	bpTable            []int8 // |nil|이거나 항목이 $2^{\mkern1mua+b+c}$개인 배열

//line mmixpipe.w:3248
	bpAmask, bpCmask, bpBcmask, bpNmask, bpNpower int
	bpRevStat, bpOkStat                           int32 // 몇 번 뒤집고 몇 번 따랐는가
	bpBadStat, bpGoodStat                         int32 // 몇 번 틀리고 몇 번 맞았는가

//line mmixpipe.w:3511
	Icache, Dcache, Scache, ITcache, DTcache *cache

//line mmixpipe.w:3799
	hitSet cacheset

//line mmixpipe.w:3963
	memChunks    int         // 지금까지 할당한 덩이의 수
	memChunksMax int         // 한 번 돌 때 서로 다른 덩이를 이만큼까지
	hashPrime    int         // |memChunksMax|보다 크되, 엄청나지는 않다
	memHash      []chunknode // 모의 주 메모리

//line mmixpipe.w:4008
	lastH int // 가장 최근에 맞은 해시 색인

//line mmixpipe.w:4040
	memAddrTime  int     // 메모리 버스로 주소를 보내는 사이클
	busWords     int     // 메모리 버스의 폭, 옥타바이트 단위
	memReadTime  int     // 주 메모리에서 읽는 사이클
	memWriteTime int     // 주 메모리에 쓰는 사이클
	memLock      lockvar // 버스가 바쁘면 |nil|이 아니다

//line mmixpipe.w:4453
	cleanCo   coroutine
	cleanCtl  control
	cleanLock lockvar

//line mmixpipe.w:4725
	IPTctl, DPTctl [5]control    // I와 D 페이지 변환을 위한 제어 블록
	IPTco, DPTco   [10]coroutine // 코루틴마다 두 단계짜리 파이프라인이다

//line mmixpipe.w:4810
	pageN    int    // rV의 10비트 |n| 필드에 8을 곱한 것
	pageR    int    // rV의 27비트 |r| 필드
	pageS    int    // rV의 8비트 |s| 필드
	pageF    int    // rV의 3비트 |f| 필드
	pageB    [5]int // rV의 4비트 |b| 필드들. |pageB[0]=0|
	pageMask Octa   // 가장 아래 |s|비트
	pageBad  bool   // rV가 규칙을 어기는가?

//line mmixpipe.w:4862
	noHardwarePT bool

//line mmixpipe.w:4951
	wbuf                 []writeNode // 쓰기 버퍼가 든 원
	wbufBot, wbufTop     *writeNode  // 가장 작은 쓰기 버퍼 노드와 가장 큰 노드
	writeHead, writeTail *writeNode  // 쓰기 버퍼의 앞과 뒤
	wbufLock             lockvar     // |writeHead|의 데이터를 쓰고 있는가?
	holdingTime          int         // 최소 머무는 시간
	speedLock            lockvar     // |holdingTime|을 무시해야 하는가?

//line mmixpipe.w:4977
	writeCo  coroutine // 쓰기 버퍼를 비우는 코루틴
	writeCtl control   // 그 제어 블록

//line mmixpipe.w:5040
	dunno Octa // 원본의 \.{DUNNO}가 가리키는 곳

//line mmixpipe.w:6076
	instPtr spec   // 명령 포인터(프로그램 계수기라고도 한다)
	fetched []Octa // 들어오는 명령을 담는 버퍼

//line mmixpipe.w:6085
	fetchLo, fetchHi int // 그 버퍼의 활성 영역
	fetchCo          coroutine
	fetchCtl         control

//line mmixpipe.w:6502
	sleepy bool // 페이지 테이블 에뮬레이션 호출을 막 내보냈는가?

//line mmixpipe.w:6752
	tryingToInterrupt bool // 가로막을 수 있는 연산들에게 멈추기를 권하는가?
	nullifying        bool // 적재/저장 명령을 무효로 만들려고 배정을 멈추는가?

//line mmixpipe.w:7708
	fremMax                     int
	deninPenalty, denoutPenalty int

//line mmixpipe.w:8583
	stdinBuf      [256]byte // 모의 프로그램의 표준 입력
	stdinBufStart int       // 그 버퍼에서의 현재 위치
	stdinBufEnd   int       // 그 버퍼의 현재 끝

//line mmixpipe.w:8597
	out     *bufio.Writer // 표준 출력
	stderr  io.Writer     // 표준 오류
	io      *mmixio.IO    // 모의 프로그램의 파일들
	stdin   *cfile        // 표준 입력
	specBuf [20]byte      // \.{mmixmem.w}의 |specRead|가 쓰는 버퍼
	hio     *hio          // \.{mmixmem.w}의 호스트 입출력 장치(\.{-k}를 주었을 때만)
}

//line mmixpipe.w:8609
type exitSignal int

//line mmixpipe.w:125
const (
	issueBit           = 1 << 0 // 명령을 발행하고, 발행을 취소하고, 확정할 때 제어 블록을 보인다
	pipeBit            = 1 << 1 // 사이클마다 파이프라인과 잠금을 보인다
	coroutineBit       = 1 << 2 // 사이클마다 시작하는 코루틴들을 보인다
	scheduleBit        = 1 << 3 // 코루틴을 스케줄할 때 보인다
	uninitMemBit       = 1 << 4 // 초기화하지 않은 메모리 덩이를 읽으면 알린다
	interactiveReadBit = 1 << 5 // 입출력 위치를 읽을 때 사용자에게 묻는다
	showSpecBit        = 1 << 6 // 특별한 읽기와 쓰기가 일어날 때 보인다
	showPredBit        = 1 << 7 // 분기 예측의 자세한 사정을 보인다
	showWholecacheBit  = 1 << 8 // 열쇠 태그가 무효인 캐시 블록도 보인다
)

//line mmixpipe.w:304
const (
	signBit = mmixarith.SignBit // 64비트 부호 비트
	negOne  = mmixarith.NegOne  // $-1$
	sign32  = 0x80000000        // 32비트 부호 비트(원본의 |sign_bit|)
)

//line mmixpipe.w:736
const (
	TRAP = iota
	FCMP
	FUN
	FEQL
	FADD
	FIX
	FSUB
	FIXU
//line mmixpipe.w:738
	FLOT
	FLOTI
	FLOTU
	FLOTUI
	SFLOT
	SFLOTI
	SFLOTU
	SFLOTUI
//line mmixpipe.w:739
	FMUL
	FCMPE
	FUNE
	FEQLE
	FDIV
	FSQRT
	FREM
	FINT
//line mmixpipe.w:740
	MUL
	MULI
	MULU
	MULUI
	DIV
	DIVI
	DIVU
	DIVUI
//line mmixpipe.w:741
	ADD
	ADDI
	ADDU
	ADDUI
	SUB
	SUBI
	SUBU
	SUBUI
//line mmixpipe.w:742
	IIADDU
	IIADDUI
	IVADDU
	IVADDUI
	VIIIADDU
	VIIIADDUI
	XVIADDU
	XVIADDUI
//line mmixpipe.w:743
	CMP
	CMPI
	CMPU
	CMPUI
	NEG
	NEGI
	NEGU
	NEGUI
//line mmixpipe.w:744
	SL
	SLI
	SLU
	SLUI
	SR
	SRI
	SRU
	SRUI
//line mmixpipe.w:745
	BN
	BNB
	BZ
	BZB
	BP
	BPB
	BOD
	BODB
//line mmixpipe.w:746
	BNN
	BNNB
	BNZ
	BNZB
	BNP
	BNPB
	BEV
	BEVB
//line mmixpipe.w:747
	PBN
	PBNB
	PBZ
	PBZB
	PBP
	PBPB
	PBOD
	PBODB
//line mmixpipe.w:748
	PBNN
	PBNNB
	PBNZ
	PBNZB
	PBNP
	PBNPB
	PBEV
	PBEVB
//line mmixpipe.w:749
	CSN
	CSNI
	CSZ
	CSZI
	CSP
	CSPI
	CSOD
	CSODI
//line mmixpipe.w:750
	CSNN
	CSNNI
	CSNZ
	CSNZI
	CSNP
	CSNPI
	CSEV
	CSEVI
//line mmixpipe.w:751
	ZSN
	ZSNI
	ZSZ
	ZSZI
	ZSP
	ZSPI
	ZSOD
	ZSODI
//line mmixpipe.w:752
	ZSNN
	ZSNNI
	ZSNZ
	ZSNZI
	ZSNP
	ZSNPI
	ZSEV
	ZSEVI
//line mmixpipe.w:753
	LDB
	LDBI
	LDBU
	LDBUI
	LDW
	LDWI
	LDWU
	LDWUI
//line mmixpipe.w:754
	LDT
	LDTI
	LDTU
	LDTUI
	LDO
	LDOI
	LDOU
	LDOUI
//line mmixpipe.w:755
	LDSF
	LDSFI
	LDHT
	LDHTI
	CSWAP
	CSWAPI
	LDUNC
	LDUNCI
//line mmixpipe.w:756
	LDVTS
	LDVTSI
	PRELD
	PRELDI
	PREGO
	PREGOI
	GO
	GOI
//line mmixpipe.w:757
	STB
	STBI
	STBU
	STBUI
	STW
	STWI
	STWU
	STWUI
//line mmixpipe.w:758
	STT
	STTI
	STTU
	STTUI
	STO
	STOI
	STOU
	STOUI
//line mmixpipe.w:759
	STSF
	STSFI
	STHT
	STHTI
	STCO
	STCOI
	STUNC
	STUNCI
//line mmixpipe.w:760
	SYNCD
	SYNCDI
	PREST
	PRESTI
	SYNCID
	SYNCIDI
	PUSHGO
	PUSHGOI
//line mmixpipe.w:761
	OR
	ORI
	ORN
	ORNI
	NOR
	NORI
	XOR
	XORI
//line mmixpipe.w:762
	AND
	ANDI
	ANDN
	ANDNI
	NAND
	NANDI
	NXOR
	NXORI
//line mmixpipe.w:763
	BDIF
	BDIFI
	WDIF
	WDIFI
	TDIF
	TDIFI
	ODIF
	ODIFI
//line mmixpipe.w:764
	MUX
	MUXI
	SADD
	SADDI
	MOR
	MORI
	MXOR
	MXORI
//line mmixpipe.w:765
	SETH
	SETMH
	SETML
	SETL
	INCH
	INCMH
	INCML
	INCL
//line mmixpipe.w:766
	ORH
	ORMH
	ORML
	ORL
	ANDNH
	ANDNMH
	ANDNML
	ANDNL
//line mmixpipe.w:767
	JMP
	JMPB
	PUSHJ
	PUSHJB
	GETA
	GETAB
	PUT
	PUTI
//line mmixpipe.w:768
	POP
	RESUME
	SAVE
	UNSAVE
	SYNC
	SWYM
	GET
	TRIP

//line mmixpipe.w:769
)

//line mmixpipe.w:815
const (

//line mmixpipe.w:829
	mul0  = iota // 0을 곱한다
	mul1         // 1--8비트짜리를 곱한다
	mul2         // 9--16비트짜리를 곱한다
	mul3         // 17--24비트짜리를 곱한다
	mul4         // 25--32비트짜리를 곱한다
	mul5         // 33--40비트짜리를 곱한다
	mul6         // 41--48비트짜리를 곱한다
	mul7         // 49--56비트짜리를 곱한다
	mul8         // 57--64비트짜리를 곱한다
	div          // \.{DIV[U][I]}
	sh           // \.{S[L,R][U][I]}
	mux          // \.{MUX[I]}
	sadd         // \.{SADD[I]}
	mor          // \.{M[X]OR[I]}
	fadd         // \.{FADD}, \.{FSUB}
	fmul         // \.{FMUL}
	fdiv         // \.{FDIV}
	fsqrt        // \.{FSQRT}
	fint         // \.{FINT}
	fix          // \.{FIX[U]}
	flot         // \.{[S]FLOT[U][I]}
	feps         // \.{FCMPE}, \.{FUNE}, \.{FEQLE}

//line mmixpipe.w:817

//line mmixpipe.w:855
	fcmp  // \.{FCMP}
	funeq // \.{FUN}, \.{FEQL}
	fsub  // \.{FSUB}
	frem  // \.{FREM}
	mul   // \.{MUL[I]}
	mulu  // \.{MULU[I]}
	divu  // \.{DIVU[I]}
	add   // \.{ADD[I]}
	addu  // \.{[2,4,8,16,]ADDU[I]}, \.{INC[M][H,L]}
	sub   // \.{SUB[I]}, \.{NEG[I]}
	subu  // \.{SUBU[I]}, \.{NEGU[I]}
	set   // \.{SET[M][H,L]}, \.{GETA[B]}
	or    // \.{OR[I]}, \.{OR[M][H,L]}
	orn   // \.{ORN[I]}
	nor   // \.{NOR[I]}
	and   // \.{AND[I]}
	andn  // \.{ANDN[I]}, \.{ANDN[M][H,L]}
	nand  // \.{NAND[I]}
	xor   // \.{XOR[I]}
	nxor  // \.{NXOR[I]}
	shlu  // \.{SLU[I]}
	shru  // \.{SRU[I]}
	shl   // \.{SL[I]}
	shr   // \.{SR[I]}
	cmp   // \.{CMP[I]}
	cmpu  // \.{CMPU[I]}
	bdif  // \.{BDIF[I]}
	wdif  // \.{WDIF[I]}
	tdif  // \.{TDIF[I]}
	odif  // \.{ODIF[I]}
	zset  // \.{ZS[N][N,Z,P][I]}, \.{ZSEV[I]}, \.{ZSOD[I]}
	cset  // \.{CS[N][N,Z,P][I]}, \.{CSEV[I]}, \.{CSOD[I]}

//line mmixpipe.w:818

//line mmixpipe.w:891
	get      // \.{GET}
	put      // \.{PUT[I]}
	ld       // \.{LD[B,W,T,O][U][I]}, \.{LDHT[I]}, \.{LDSF[I]}
	ldptp    // 페이지 테이블 포인터를 적재한다
	ldpte    // 페이지 테이블 항목을 적재한다
	ldunc    // \.{LDUNC[I]}
	ldvts    // \.{LDVTS[I]}
	preld    // \.{PRELD[I]}
	prest    // \.{PREST[I]}
	st       // \.{STO[U][I]}, \.{STCO[I]}, \.{STUNC[I]}
	syncd    // \.{SYNCD[I]}
	syncid   // \.{SYNCID[I]}
	pst      // \.{ST[B,W,T][U][I]}, \.{STHT[I]}
	stunc    // 쓰기 버퍼 안의 \.{STUNC[I]}
	cswap    // \.{CSWAP[I]}
	br       // \.{B[N][N,Z,P][B]}
	pbr      // \.{PB[N][N,Z,P][B]}
	pushj    // \.{PUSHJ[B]}
	goOp     // \.{GO[I]}
	prego    // \.{PREGO[I]}
	pushgo   // \.{PUSHGO[I]}
	pop      // \.{POP}
	resume   // \.{RESUME}
	save     // \.{SAVE}
	unsave   // \.{UNSAVE}
	sync     // \.{SYNC}
	jmp      // \.{JMP[B]}
	noop     // \.{SWYM}
	trap     // \.{TRAP}
	trip     // \.{TRIP}
	incgamma // $\gamma$ 포인터를 늘린다
	decgamma // $\gamma$ 포인터를 줄인다
	incrl    // rL과 $\beta$를 늘린다
	sav      // \.{SAVE}의 중간 단계
	unsav    // \.{UNSAVE}의 중간 단계
	resum    // \.{RESUME}의 중간 단계

//line mmixpipe.w:819
)

const (
	maxPipeOp      = feps
	maxRealCommand = trip

//line mmixpipe.w:824
)

//line mmixpipe.w:986
const (
	rA  = 21 // 산술 상태 레지스터
	rB  = 0  // 부트스트랩 레지스터(트립)
	rC  = 8  // 계속 레지스터
	rD  = 1  // 피제수 레지스터
	rE  = 2  // 엡실론 레지스터
	rF  = 22 // 실패 위치 레지스터
	rG  = 19 // 전역 문턱 레지스터
	rH  = 3  // 곱의 윗부분 레지스터
	rI  = 12 // 구간 계수기
	rJ  = 4  // 복귀 점프 레지스터
	rK  = 15 // 인터럽트 마스크 레지스터
	rL  = 20 // 지역 문턱 레지스터
	rM  = 5  // 멀티플렉스 마스크 레지스터
	rN  = 9  // 일련번호
	rO  = 10 // 레지스터 스택 오프셋
	rP  = 23 // 예측 레지스터
	rQ  = 16 // 인터럽트 요청 레지스터
	rR  = 6  // 나머지 레지스터
	rS  = 11 // 레지스터 스택 포인터
	rT  = 13 // 트랩 주소 레지스터
	rU  = 17 // 사용 계수기
	rV  = 18 // 가상 주소 변환 레지스터
	rW  = 24 // 인터럽트된 곳 레지스터(트립)
	rX  = 25 // 실행 레지스터(트립)
	rY  = 26 // Y 피연산자(트립)
	rZ  = 27 // Z 피연산자(트립)
	rBB = 7  // 부트스트랩 레지스터(트랩)
	rTT = 14 // 동적 트랩 주소 레지스터
	rWW = 28 // 인터럽트된 곳 레지스터(트랩)
	rXX = 29 // 실행 레지스터(트랩)
	rYY = 30 // Y 피연산자(트랩)
	rZZ = 31 // Z 피연산자(트랩)
)

//line mmixpipe.w:1030
const (
	pBit       = 1 << 0  // 특권 위치에 있는 명령
	sBit       = 1 << 1  // 보안 위반
	bBit       = 1 << 2  // 규칙을 어기는 명령
	kBit       = 1 << 3  // 커널 전용 명령
	nBit       = 1 << 4  // 가상 주소 변환을 건너뜀
	pxBit      = 1 << 5  // 페이지에서 실행할 권한이 없음
	pwBit      = 1 << 6  // 페이지에 쓸 권한이 없음
	prBit      = 1 << 7  // 페이지에서 읽을 권한이 없음
	protOffset = 5       // |prBit|에서 보호 코드 자리까지의 거리
	xBit       = 1 << 8  // 부동소수점 부정확
	zBit       = 1 << 9  // 부동소수점 0으로 나눔
	uBit       = 1 << 10 // 부동소수점 아래넘침
	oBit       = 1 << 11 // 부동소수점 넘침
	iBit       = 1 << 12 // 부동소수점 잘못된 연산
	wBit       = 1 << 13 // 부동소수점에서 고정소수점으로 바꿀 때 넘침
	vBit       = 1 << 14 // 정수 넘침
	dBit       = 1 << 15 // 정수 나눗셈 검사
	hBit       = 1 << 16 // 트립 처리기 비트
	fBit       = 1 << 17 // 강제 트랩 비트
	eBit       = 1 << 18 // 외부(동적) 트랩 비트
)

//line mmixpipe.w:1069
const (
	powerFailure      = 1 << 0 // 침착하고 재빨리 끄려고 한다
	parityError       = 1 << 1 // 파일 시스템을 지키려고 한다
	nonexistentMemory = 1 << 2 // 쓸 수 없는 메모리 주소
	rebootSignal      = 1 << 4 // 처음부터 다시 할 때다
	intervalTimeout   = 1 << 6 // 타이머 레지스터 rI가 0이 되었다
	stackOverflow     = 1 << 7 // rC 페이지에 데이터를 저장했다
)

//line mmixpipe.w:1640
const (
	xIsDestBit   = 0x20
	relAddrBit   = 0x40
	ctlChangeBit = 0x80

//line mmixpipe.w:1644
)

//line mmixpipe.w:1780
const (
	version       = 1 // 우리가 지원하는 \MMIX\ 아키텍처의 판
	subversion    = 0 // 판 번호의 둘째 바이트
	subsubversion = 0 // 판 번호를 더 한정하는 번호
)

//line mmixpipe.w:2530
const (
	lSwitch0 label = iota // 가져오기 코루틴의 상태 스위치
	lSwitch1              // 첫 단계의 상태 스위치
	lSwitch2              // 뒤 단계들의 상태 스위치

//line mmixpipe.w:2734
	lPassit // 원본의 |passit|

//line mmixpipe.w:2917
	lDie // 원본의 |die|

//line mmixpipe.w:4314
	lSNonMiss // 원본의 |S_non_miss|

//line mmixpipe.w:4473
	lDcleanLoop // 원본의 |Dclean_loop|
	lDclean     // 원본의 |Dclean|
	lDcleanInc  // 원본의 |Dclean_inc|
	lScleanLoop // 원본의 |Sclean_loop|
	lSclean     // 원본의 |Sclean|
	lScleanInc  // 원본의 |Sclean_inc|

//line mmixpipe.w:5158
	lMemDirect // 원본의 |mem_direct|

//line mmixpipe.w:5399
	lMakeLdReady // 원본의 |make_ld_ready|

//line mmixpipe.w:5678
	lAvoidD // 원본의 |avoid_D|

//line mmixpipe.w:6132
	lKnownPhys // 원본의 |known_phys|
	lBadFetch  // 원본의 |bad_fetch|
	lSwymOne   // 원본의 |swym_one|
	lFetchOne  // 원본의 |fetch_one|

//line mmixpipe.w:6566
	lEmulateVirt // 원본의 |emulate_virt|

//line mmixpipe.w:8233
	lSyncCheck // 원본의 |sync_check|

//line mmixpipe.w:2535
)

const (
	fetchSt    label = 1000  // 가져오기 코루틴의 상태 |case|
	stage1St   label = 2000  // 첫 단계의 상태 |case|
	stage2St   label = 3000  // 뒤 단계들의 상태 |case|
	flushMemSt label = 4000  // |flushToMem|의 상태 |case|
	flushSSt   label = 5000  // |flushToS|의 상태 |case|
	fillMemSt  label = 6000  // |fillFromMem|의 상태 |case|
	fillSSt    label = 7000  // |fillFromS|의 상태 |case|
	cleanupSt  label = 8000  // |cleanup|의 상태 |case|
	fillVirtSt label = 9000  // |fillFromVirt|의 상태 |case|
	writeSt    label = 10000 // |writeFromWbuf|의 상태 |case|
)

//line mmixpipe.w:2608
const (
	maxStage      = 99 // 모든 |stage| 번호보다 크다
	vanish        = 98 // 그냥 사라지는 특별한 코루틴
	flushToMem    = 97 // 캐시에서 메모리로 쏟아 내는 코루틴
	flushToS      = 96 // 캐시에서 S-캐시로 쏟아 내는 코루틴
	fillFromMem   = 95 // 메모리에서 캐시를 채우는 코루틴
	fillFromS     = 94 // S-캐시에서 캐시를 채우는 코루틴
	fillFromVirt  = 93 // 변환 캐시를 채우는 코루틴
	writeFromWbuf = 92 // 쓰기 버퍼를 비우는 코루틴
	cleanup       = 91 // 캐시를 청소하는 코루틴
)

//line mmixpipe.w:2756
const (
	lPassData = stage1St + 2 // 원본의 |pass_data|
	lFinEx    = stage1St + 3 // 원본의 |fin_ex|
)

//line mmixpipe.w:2787
const pipeLimit = 90

//line mmixpipe.w:3461
const (
	writeBack  = 1 // 즉시 쓰기가 아니면 이것을 쓴다
	writeAlloc = 2 // 쓰기 우회가 아니면 이것을 쓴다
)

//line mmixpipe.w:4481
const lSprep = cleanupSt + 9 // 원본의 |Sprep|

//line mmixpipe.w:4719
const (
	LDPTP = PREGO // 안에서는 헷갈릴 일이 없다
	LDPTE = GO

//line mmixpipe.w:4722
)

//line mmixpipe.w:5161
const lWriteRestart = writeSt + 0 // 원본의 |write_restart|

//line mmixpipe.w:5351
const ldStLaunch = 7 // 적재/저장 명령이 메모리 주소를 가졌을 때의 |state|

//line mmixpipe.w:5445
const (
	dtMiss     = 10 // DT-캐시에 열쇠가 없을 때의 둘째 단계 |state|
	dtHit      = 11 // 물리 주소를 알 때의 둘째 단계 |state|
	hitAndMiss = 12 // D-캐시를 놓쳤을 때의 둘째 단계 |state|
	ldReady    = 13 // 데이터를 읽었을 때의 둘째 단계 |state|
	stReady    = 14 // 데이터를 읽을 필요가 없을 때의 둘째 단계 |state|
	prestWin   = 15 // 블록을 0으로 채울 수 있을 때의 둘째 단계 |state|
)

//line mmixpipe.w:5665
const (
	dtRetry = 8 // DT-캐시를 다시 찾아야 할 때의 둘째 단계 |state|
	gotDT   = 9 // DT-캐시 항목을 계산했을 때의 둘째 단계 |state|
)

const (
	lSquareOne   = stage2St + dtRetry  // 원본의 |square_one|
	lLdRetry     = stage2St + dtHit    // 원본의 |ld_retry|
	lPrestSpan   = stage2St + prestWin // 원본의 |prest_span|
	lFinishStore = stage2St + stReady  // 원본의 |finish_store|
)

//line mmixpipe.w:6126
const (
	lNewFetch   = fetchSt + 0 // 원본의 |new_fetch|
	lStartFetch = fetchSt + 1 // 원본의 |start_fetch|
)

//line mmixpipe.w:6187
const (
	gotIT       = 19 // IT-캐시 항목을 계산했을 때의 |state|
	itMiss      = 20 // IT-캐시에 열쇠가 없을 때의 |state|
	itHit       = 21 // 명령의 물리 주소를 알 때의 |state|
	iHitAndMiss = 22 // I-캐시를 놓쳤을 때의 |state|
	fetchReady  = 23 // 명령들을 읽었을 때의 |state|
	gotOne      = 24 // ``미리 보기'' 옥타바이트가 준비되었을 때의 |state|
)

//line mmixpipe.w:6340
const lFetchRetry = fetchSt + itHit // 원본의 |fetch_retry|

//line mmixpipe.w:6569
const (
	lState4 = stage1St + 4 // 원본의 |state_4|
	lState5 = stage1St + 5 // 원본의 |state_5|
)

//line mmixpipe.w:6830
const (
	resumeAgain = 0 // rX의 명령을 위치 $\rm rW-4$에 있는 것처럼 되풀이한다
	resumeCont  = 1 // 같지만, 피연산자 대신 rY와 rZ를 쓴다
	resumeSet   = 2 // 레지스터 \$X를 rZ로 정한다
	resumeTrans = 3 // $\rm(rY,rZ)$를 IT-캐시나 DT-캐시에 넣고 |resumeAgain|을 한다
)

//line mmixpipe.w:7083
const (
	doResumeTrans = 17                       // |resumeTrans| 동작을 하는 |state|
	lResumeTrans  = stage1St + doResumeTrans // 원본의 |resume_trans|
)

//line mmixpipe.w:8043
const (
	lDoSyncid = stage2St + 30 // 원본의 |do_syncid|
	lDoSyncd  = stage2St + 33 // 원본의 |do_syncd|
	lNextSync = stage2St + 35 // 원본의 |next_sync|
)

//line mmixpipe.w:8255
const (
	Halt = iota
	Fopen
	Fclose
	Fread
	Fgets
	Fgetws
	Fwrite
	Fputs
	Fputws
	Fseek
	Ftell

//line mmixpipe.w:8267
)

const maxSysCall = Ftell

//line mmixpipe.w:772
var opcodeName = [256]string{
	"TRAP", "FCMP", "FUN", "FEQL", "FADD", "FIX", "FSUB", "FIXU",
	"FLOT", "FLOTI", "FLOTU", "FLOTUI", "SFLOT", "SFLOTI", "SFLOTU", "SFLOTUI",
	"FMUL", "FCMPE", "FUNE", "FEQLE", "FDIV", "FSQRT", "FREM", "FINT",
	"MUL", "MULI", "MULU", "MULUI", "DIV", "DIVI", "DIVU", "DIVUI",
	"ADD", "ADDI", "ADDU", "ADDUI", "SUB", "SUBI", "SUBU", "SUBUI",
	"2ADDU", "2ADDUI", "4ADDU", "4ADDUI", "8ADDU", "8ADDUI", "16ADDU", "16ADDUI",
	"CMP", "CMPI", "CMPU", "CMPUI", "NEG", "NEGI", "NEGU", "NEGUI",
	"SL", "SLI", "SLU", "SLUI", "SR", "SRI", "SRU", "SRUI",
	"BN", "BNB", "BZ", "BZB", "BP", "BPB", "BOD", "BODB",
	"BNN", "BNNB", "BNZ", "BNZB", "BNP", "BNPB", "BEV", "BEVB",
	"PBN", "PBNB", "PBZ", "PBZB", "PBP", "PBPB", "PBOD", "PBODB",
	"PBNN", "PBNNB", "PBNZ", "PBNZB", "PBNP", "PBNPB", "PBEV", "PBEVB",
	"CSN", "CSNI", "CSZ", "CSZI", "CSP", "CSPI", "CSOD", "CSODI",
	"CSNN", "CSNNI", "CSNZ", "CSNZI", "CSNP", "CSNPI", "CSEV", "CSEVI",
	"ZSN", "ZSNI", "ZSZ", "ZSZI", "ZSP", "ZSPI", "ZSOD", "ZSODI",
	"ZSNN", "ZSNNI", "ZSNZ", "ZSNZI", "ZSNP", "ZSNPI", "ZSEV", "ZSEVI",
	"LDB", "LDBI", "LDBU", "LDBUI", "LDW", "LDWI", "LDWU", "LDWUI",
	"LDT", "LDTI", "LDTU", "LDTUI", "LDO", "LDOI", "LDOU", "LDOUI",
	"LDSF", "LDSFI", "LDHT", "LDHTI", "CSWAP", "CSWAPI", "LDUNC", "LDUNCI",
	"LDVTS", "LDVTSI", "PRELD", "PRELDI", "PREGO", "PREGOI", "GO", "GOI",
	"STB", "STBI", "STBU", "STBUI", "STW", "STWI", "STWU", "STWUI",
	"STT", "STTI", "STTU", "STTUI", "STO", "STOI", "STOU", "STOUI",
	"STSF", "STSFI", "STHT", "STHTI", "STCO", "STCOI", "STUNC", "STUNCI",
	"SYNCD", "SYNCDI", "PREST", "PRESTI", "SYNCID", "SYNCIDI", "PUSHGO", "PUSHGOI",
	"OR", "ORI", "ORN", "ORNI", "NOR", "NORI", "XOR", "XORI",
	"AND", "ANDI", "ANDN", "ANDNI", "NAND", "NANDI", "NXOR", "NXORI",
	"BDIF", "BDIFI", "WDIF", "WDIFI", "TDIF", "TDIFI", "ODIF", "ODIFI",
	"MUX", "MUXI", "SADD", "SADDI", "MOR", "MORI", "MXOR", "MXORI",
	"SETH", "SETMH", "SETML", "SETL", "INCH", "INCMH", "INCML", "INCL",
	"ORH", "ORMH", "ORML", "ORL", "ANDNH", "ANDNMH", "ANDNML", "ANDNL",
	"JMP", "JMPB", "PUSHJ", "PUSHJB", "GETA", "GETAB", "PUT", "PUTI",
	"POP", "RESUME", "SAVE", "UNSAVE", "SYNC", "SWYM", "GET", "TRIP"}

//line mmixpipe.w:929
var internalOpName = [...]string{
	"mul0", "mul1", "mul2", "mul3", "mul4", "mul5", "mul6", "mul7", "mul8",
	"div", "sh", "mux", "sadd", "mor", "fadd", "fmul", "fdiv", "fsqrt", "fint",
	"fix", "flot", "feps", "fcmp", "funeq", "fsub", "frem", "mul", "mulu",
	"divu", "add", "addu", "sub", "subu", "set", "or", "orn", "nor", "and",
	"andn", "nand", "xor", "nxor", "shlu", "shru", "shl", "shr", "cmp", "cmpu",
	"bdif", "wdif", "tdif", "odif", "zset", "cset", "get", "put", "ld", "ldptp",
	"ldpte", "ldunc", "ldvts", "preld", "prest", "st", "syncd", "syncid", "pst",
	"stunc", "cswap", "br", "pbr", "pushj", "go", "prego", "pushgo", "pop",
	"resume", "save", "unsave", "sync", "jmp", "noop", "trap", "trip",
	"incgamma", "decgamma", "incrl", "sav", "unsav", "resum"}

//line mmixpipe.w:944
var internalOp = [256]int{
	trap, fcmp, funeq, funeq, fadd, fix, fsub, fix,
	flot, flot, flot, flot, flot, flot, flot, flot,
	fmul, feps, feps, feps, fdiv, fsqrt, frem, fint,
	mul, mul, mulu, mulu, div, div, divu, divu,
	add, add, addu, addu, sub, sub, subu, subu,
	addu, addu, addu, addu, addu, addu, addu, addu,
	cmp, cmp, cmpu, cmpu, sub, sub, subu, subu,
	shl, shl, shlu, shlu, shr, shr, shru, shru,
	br, br, br, br, br, br, br, br,
	br, br, br, br, br, br, br, br,
	pbr, pbr, pbr, pbr, pbr, pbr, pbr, pbr,
	pbr, pbr, pbr, pbr, pbr, pbr, pbr, pbr,
	cset, cset, cset, cset, cset, cset, cset, cset,
	cset, cset, cset, cset, cset, cset, cset, cset,
	zset, zset, zset, zset, zset, zset, zset, zset,
	zset, zset, zset, zset, zset, zset, zset, zset,
	ld, ld, ld, ld, ld, ld, ld, ld,
	ld, ld, ld, ld, ld, ld, ld, ld,
	ld, ld, ld, ld, cswap, cswap, ldunc, ldunc,
	ldvts, ldvts, preld, preld, prego, prego, goOp, goOp,
	pst, pst, pst, pst, pst, pst, pst, pst,
	pst, pst, pst, pst, st, st, st, st,
	pst, pst, pst, pst, st, st, st, st,
	syncd, syncd, prest, prest, syncid, syncid, pushgo, pushgo,
	or, or, orn, orn, nor, nor, xor, xor,
	and, and, andn, andn, nand, nand, nxor, nxor,
	bdif, bdif, wdif, wdif, tdif, tdif, odif, odif,
	mux, mux, sadd, sadd, mor, mor, mor, mor,
	set, set, set, set, addu, addu, addu, addu,
	or, or, or, or, andn, andn, andn, andn,
	jmp, jmp, pushj, pushj, set, set, put, put,
	pop, resume, save, unsave, sync, noop, get, trip}

//line mmixpipe.w:1022
var specialName = [32]string{"rB", "rD", "rE", "rH", "rJ", "rM", "rR", "rBB",
	"rC", "rN", "rO", "rS", "rI", "rT", "rTT", "rK", "rQ", "rU", "rV", "rG", "rL",
	"rA", "rF", "rP", "rW", "rX", "rY", "rZ", "rWW", "rXX", "rYY", "rZZ"}

//line mmixpipe.w:1054
var bitCodeMap = "EFHDVWIOUZXrwxnkbsp"

//line mmixpipe.w:1647
var flags = [256]byte{
	0x8a, 0x2a, 0x2a, 0x2a, 0x2a, 0x26, 0x2a, 0x26, // \.{TRAP}, \dots
	0x26, 0x25, 0x26, 0x25, 0x26, 0x25, 0x26, 0x25, // \.{FLOT}, \dots
	0x2a, 0x2a, 0x2a, 0x2a, 0x2a, 0x26, 0x2a, 0x26, // \.{FMUL}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{MUL}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{ADD}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{2ADDU}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x26, 0x25, 0x26, 0x25, // \.{CMP}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{SL}, \dots
	0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, // \.{BN}, \dots
	0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, // \.{BNN}, \dots
	0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, // \.{PBN}, \dots
	0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, // \.{PBNN}, \dots
	0x3a, 0x39, 0x3a, 0x39, 0x3a, 0x39, 0x3a, 0x39, // \.{CSN}, \dots
	0x3a, 0x39, 0x3a, 0x39, 0x3a, 0x39, 0x3a, 0x39, // \.{CSNN}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{ZSN}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{ZSNN}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{LDB}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{LDT}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x3a, 0x39, 0x2a, 0x29, // \.{LDSF}, \dots
	0x2a, 0x29, 0x0a, 0x09, 0x0a, 0x09, 0xaa, 0xa9, // \.{LDVTS}, \dots
	0x1a, 0x19, 0x1a, 0x19, 0x1a, 0x19, 0x1a, 0x19, // \.{STB}, \dots
	0x1a, 0x19, 0x1a, 0x19, 0x1a, 0x19, 0x1a, 0x19, // \.{STT}, \dots
	0x1a, 0x19, 0x1a, 0x19, 0x0a, 0x09, 0x1a, 0x19, // \.{STSF}, \dots
	0x0a, 0x09, 0x0a, 0x09, 0x0a, 0x09, 0xaa, 0xa9, // \.{SYNCD}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{OR}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{AND}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{BDIF}, \dots
	0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, 0x2a, 0x29, // \.{MUX}, \dots
	0x20, 0x20, 0x20, 0x20, 0x30, 0x30, 0x30, 0x30, // \.{SETH}, \dots
	0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, // \.{ORH}, \dots
	0xc0, 0xc0, 0xe0, 0xe0, 0x60, 0x60, 0x02, 0x01, // \.{JMP}, \dots
	0x80, 0x80, 0x00, 0x02, 0x01, 0x00, 0x20, 0x8a} // \.{POP}, \dots

//line mmixpipe.w:1996
var thirdOperand = [256]byte{
	0, rA, 0, 0, rA, rA, rA, rA, // \.{TRAP}, \dots
	rA, rA, rA, rA, rA, rA, rA, rA, // \.{FLOT}, \dots
	rA, rE, rE, rE, rA, rA, rA, rA, // \.{FMUL}, \dots
	rA, rA, 0, 0, rA, rA, rD, rD, // \.{MUL}, \dots
	rA, rA, 0, 0, rA, rA, 0, 0, // \.{ADD}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{2ADDU}, \dots
	0, 0, 0, 0, rA, rA, 0, 0, // \.{CMP}, \dots
	rA, rA, 0, 0, 0, 0, 0, 0, // \.{SL}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{BN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{BNN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{PBN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{PBNN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{CSN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{CSNN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{ZSN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{ZSNN}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{LDB}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{LDT}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{LDSF}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{LDVTS}, \dots
	rA, rA, 0, 0, rA, rA, 0, 0, // \.{STB}, \dots
	rA, rA, 0, 0, 0, 0, 0, 0, // \.{STT}, \dots
	rA, rA, 0, 0, 0, 0, 0, 0, // \.{STSF}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{SYNCD}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{OR}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{AND}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{BDIF}, \dots
	rM, rM, 0, 0, 0, 0, 0, 0, // \.{MUX}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{SETH}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{ORH}, \dots
	0, 0, 0, 0, 0, 0, 0, 0, // \.{JMP}, \dots
	rJ, 0, 0, 0, 0, 0, 0, 255} // \.{POP}, \dots

//line mmixpipe.w:6531
var badInstMask = [4]Tetra{0xfffffe, 0xffff, 0xffff00, 0xfffff8}

//line mmixpipe.w:8319
var argCount = [11]int{1, 3, 1, 3, 3, 3, 3, 2, 2, 2, 1}

//line mmixpipe.w:155
func (mx *machine) MMIXInit() {
	var i, j int

//line mmixpipe.w:377
	for k := range mx.ring {
		mx.ring[k].next = &mx.ring[k]
	}

//line mmixpipe.w:1236
	mx.hot, mx.cool = mx.reorderTop, mx.reorderTop
	mx.deissues = 0

//line mmixpipe.w:1383
	mx.head, mx.tail = mx.fetchTop, mx.fetchTop
	mx.instPtr.p = &mx.unknownSpec

//line mmixpipe.w:1542
	for k := 0; k <= mx.funitCount; k++ {
		for i = 0; i < 8; i++ {
			mx.support[i] |= mx.funit[k].ops[i]
		}
	}

//line mmixpipe.w:1787
	mx.renameRegs = mx.maxRenameRegs
	mx.memSlots = mx.maxMemSlots
	mx.lringMask = mx.lringSize - 1
	for j = 0; j < 256; j++ {
		mx.g[j].addr = sign32<<32 | Octa(j)
		mx.g[j].known = true
		mx.g[j].up, mx.g[j].down = &mx.g[j], &mx.g[j]
	}
	mx.g[rG].o = 255
	mx.g[rN].o = (version<<24+subversion<<16+subsubversion<<8)<<32 |
		Octa(Tetra(ABSTIME)) // 위의 설명과 경고를 보라
	for j = 0; j < mx.lringSize; j++ {
		mx.l[j].addr = sign32<<32 | Octa(256+j)
		mx.l[j].known = true
		mx.l[j].up, mx.l[j].down = &mx.l[j], &mx.l[j]
	}

//line mmixpipe.w:2178
	mx.mem.addr = negOne
	mx.mem.up, mx.mem.down = &mx.mem, &mx.mem

//line mmixpipe.w:2581
	mx.memLocker.name = "Locker"
	mx.memLocker.ctl = &mx.vanishCtl
	mx.memLocker.stage = vanish
	mx.dLocker.name = "Dlocker"
	mx.dLocker.ctl = &mx.vanishCtl
	mx.dLocker.stage = vanish
	mx.vanishCtl.goLoc.o = 4
	for j = 0; j < mx.DTcache.ports; j++ {
		mx.DTcache.reader[j].ctl = &mx.vanishCtl
	}
	if mx.Dcache != nil {
		for j = 0; j < mx.Dcache.ports; j++ {
			mx.Dcache.reader[j].ctl = &mx.vanishCtl
		}
	}
	for j = 0; j < mx.ITcache.ports; j++ {
		mx.ITcache.reader[j].ctl = &mx.vanishCtl
	}
	if mx.Icache != nil {
		for j = 0; j < mx.Icache.ports; j++ {
			mx.Icache.reader[j].ctl = &mx.vanishCtl
		}
	}

//line mmixpipe.w:3237
	mx.bpAmask = ((1 << mx.bpA) - 1) << 2            // 명령 주소의 가장 아래 $a$비트
	mx.bpCmask = ((1 << mx.bpC) - 1) << (mx.bpA + 2) // 그다음 $c$개의 주소 비트
	mx.bpBcmask = (1 << (mx.bpB + mx.bpC)) - 1       // 이력 정보의 가장 아래 $b+c$비트
	mx.bpNmask = (1 << mx.bpN) - 1                   // 가장 아래 $n$비트
	if mx.bpN > 0 {
		mx.bpNpower = 1 << (mx.bpN - 1) // $2^{n-1}$, 곧 $n$비트 수의 부호 비트
	}

//line mmixpipe.w:4458
	mx.cleanCo.ctl = &mx.cleanCtl
	mx.cleanCo.name = "Clean"
	mx.cleanCo.stage = cleanup
	mx.cleanCtl.goLoc.o = 4

//line mmixpipe.w:4732
	for j = 0; j < 5; j++ {
		mx.DPTco[2*j].ctl = &mx.DPTctl[j]
		mx.IPTco[2*j].ctl = &mx.IPTctl[j]
		for _, c := range []*control{&mx.IPTctl[j], &mx.DPTctl[j]} {
			if j > 0 {
				c.op, c.i = LDPTP, ldptp
			} else {
				c.op, c.i = LDPTE, ldpte
			}
			c.loc = negOne
			c.goLoc.o = 3 // 원본의 |incr(neg_one,4)|
			c.ptrA = &mx.mem
			c.renX = true
			c.x.addr = c.x.addr&0xffffffff | 0xffffffff<<32
			c.link()
		}
		for _, co := range [][]coroutine{mx.IPTco[:], mx.DPTco[:]} {
			co[2*j].stage = 1
			co[2*j+1].stage = 2
			co[2*j].succ = &co[2*j+1]
		}
		mx.IPTco[2*j].name = fmt.Sprintf("IPT%d", j)
		mx.IPTco[2*j+1].name = mx.IPTco[2*j].name
		mx.DPTco[2*j].name = fmt.Sprintf("DPT%d", j)
		mx.DPTco[2*j+1].name = mx.DPTco[2*j].name
	}
	mx.ITcache.fillerCtl.ptrC = mx.IPTco[:]
	mx.DTcache.fillerCtl.ptrC = mx.DPTco[:]

//line mmixpipe.w:4821
	mx.pageBad = true

//line mmixpipe.w:4981
	mx.writeCo.ctl = &mx.writeCtl
	mx.writeCo.name = "Write"
	mx.writeCo.stage = writeFromWbuf
	mx.writeCtl.ptrA = &mx.mem
	mx.writeCtl.goLoc.o = 4
	mx.startup(&mx.writeCo, 1)
	mx.writeHead, mx.writeTail = mx.wbufTop, mx.wbufTop

//line mmixpipe.w:6090
	mx.fetchCo.ctl = &mx.fetchCtl
	mx.fetchCo.name = "Fetch"
	mx.fetchCtl.goLoc.o = 4
	mx.startup(&mx.fetchCo, 1)

//line mmixpipe.w:158
}

func (mx *machine) MMIXSilent() int {
	mx.breakpointHit, mx.halted = false, false
	mx.breakpoint = 0
	for {
		mx.cycle()
		if mx.halted {
			return int(int32(Tetra(mx.specval(&mx.g[255]).o)))
		}
	}
}

func (mx *machine) MMIXRun(cycs int, breakpoint Octa) {
	mx.breakpointHit, mx.halted = false, false
	mx.breakpoint = breakpoint
	for cycs != 0 {
		if mx.verbose&(issueBit|pipeBit|coroutineBit|scheduleBit) != 0 {
			mx.printf("*** Cycle %d\n", int32(Tetra(mx.ticks)))
		}
		mx.cycle()
		if mx.verbose&pipeBit != 0 {
			mx.printPipe()
			mx.printLocks()
		}
		if mx.breakpointHit || mx.halted {
			if mx.breakpointHit {
				mx.printf("Breakpoint instruction fetched at time %d\n",
					int32(Tetra(mx.ticks))-1)
			}
			if mx.halted {
				mx.printf("Halted at time %d\n", int32(Tetra(mx.ticks))-1)
			}
			break
		}
		cycs--
	}
}

//line mmixpipe.w:215
func (mx *machine) panic(msg string) {
	mx.errprintf("Panic: %s!\n", msg)
	mx.expire()
}

func confusion(m string) string {
	return "This can't happen: " + m
}

func (mx *machine) expire() { // 죽기 전 마지막 숨
	if mx.ticks>>32 != 0 {
		mx.errprintf("(Clock time is %dH+%d.)\n",
			int32(mx.ticks>>32), int32(Tetra(mx.ticks)))
	} else {
		mx.errprintf("(Clock time is %d.)\n", int32(Tetra(mx.ticks)))
	}

	panic(exitSignal(-2))
}

//line mmixpipe.w:239
func (mx *machine) printf(format string, a ...any) {
	fmt.Fprintf(mx.out, format, a...)
}

func (mx *machine) errprintf(format string, a ...any) {
	fmt.Fprintf(mx.stderr, format, a...)
}

//line mmixpipe.w:287
func (mx *machine) printOcta(o Octa) {
	mx.printf("%x", o)
}

//line mmixpipe.w:351
func (mx *machine) printCoroutineID(c *coroutine) {
	mx.printf("%s", coroutineID(c))
}

func coroutineID(c *coroutine) string {
	if c != nil {
		return fmt.Sprintf("%s:%d", c.name, c.stage)
	}
	return "??"

}

//line mmixpipe.w:390
func (mx *machine) schedule(c *coroutine, d, s int) {
	tt := (mx.curTime + d) % mx.ringSize
	if d <= 0 || d >= mx.ringSize { // 상식 검사를 한다
		mx.panic(confusion("Scheduling ") + coroutineID(c) +
			fmt.Sprintf(" with delay %d", d))
	}
	p := &mx.ring[tt] // 머리 노드에서 시작한다
	for p.next.stage < c.stage {
		p = p.next
	}
	c.next = p.next
	p.next = c
	if mx.verbose&scheduleBit != 0 {
		mx.printf(" scheduling ")
		mx.printCoroutineID(c)
		mx.printf(" at time %d, state %d\n", int32(Tetra(mx.ticks)+Tetra(d)), s)
	}
}

//line mmixpipe.w:419
func (mx *machine) startup(c *coroutine, d int) {
	c.ctl.state = 0
	mx.schedule(c, d, 0)
}

//line mmixpipe.w:431
func (mx *machine) unschedule(c *coroutine) {
	if c.next != nil {
		p := c
		for p.next != c {
			p = p.next
		}
		p.next = c.next
		c.next = nil
		if mx.verbose&scheduleBit != 0 {
			mx.printf(" unscheduling ")
			mx.printCoroutineID(c)
			mx.printf("\n")
		}
	}
}

//line mmixpipe.w:452
func (mx *machine) queuelist(t int) *coroutine {
	q := &mx.sentinel
	var r *coroutine
	for p := mx.ring[t].next; p != &mx.ring[t]; p = r {
		r = p.next
		p.next = q
		q = p
	}
	mx.ring[t].next = &mx.ring[t]
	mx.sentinel.next = q
	return q
}

//line mmixpipe.w:485
func setLock(c *coroutine, l *lockvar) {
	*l = c
	c.lockloc = l
}

func releaseLock(c *coroutine, l *lockvar) {
	*l = nil
	c.lockloc = nil
}

//line mmixpipe.w:496
func (mx *machine) printLocks() {
	mx.printCacheLocks(mx.ITcache)
	mx.printCacheLocks(mx.DTcache)
	mx.printCacheLocks(mx.Icache)
	mx.printCacheLocks(mx.Dcache)
	mx.printCacheLocks(mx.Scache)
	if mx.memLock != nil {
		mx.printf("mem locked by %s:%d\n", mx.memLock.name, mx.memLock.stage)
	}
	if mx.dispatchLock != nil {
		mx.printf("dispatch locked by %s:%d\n",
			mx.dispatchLock.name, mx.dispatchLock.stage)
	}
	if mx.wbufLock != nil {
		mx.printf("head of write buffer locked by %s:%d\n",
			mx.wbufLock.name, mx.wbufLock.stage)
	}
	if mx.cleanLock != nil {
		mx.printf("cleaner locked by %s:%d\n", mx.cleanLock.name, mx.cleanLock.stage)
	}
	if mx.speedLock != nil {
		mx.printf("write buffer flush locked by %s:%d\n",
			mx.speedLock.name, mx.speedLock.stage)
	}
}

//line mmixpipe.w:555
func (mx *machine) printSpec(s spec) {
	if s.p == nil {
		mx.printOcta(s.o)
	} else {
		mx.printf(">")
		mx.printSpecnodeID(s.p.addr)
	}
}

func (mx *machine) printSpecnode(s *specnode) {
	if s.known {
		mx.printOcta(s.o)
		mx.printf("!")
	} else if s.o != 0 {
		mx.printOcta(s.o)
		mx.printf("?")
	} else {
		mx.printf("?")
	}
	mx.printSpecnodeID(s.addr)
}

//line mmixpipe.w:647
func (c *control) link() {
	c.x.ctl, c.a.ctl, c.goLoc.ctl, c.rl.ctl = c, c, c, c
}

//line mmixpipe.w:652
func (mx *machine) printControlBlock(c *control) {
	if c.loc != 0 || c.op != 0 || c.xx != 0 || c.yy != 0 || c.zz != 0 || c.owner != nil {
		mx.printOcta(c.loc)
		mx.printf(": %02x%02x%02x%02x(%s)", c.op, c.xx, c.yy, c.zz,
			internalOpName[c.i])
	}
	if c.usage {
		mx.printf("*")
	}
	if c.interim {
		mx.printf("+")
	}

//line mmixpipe.w:691
	if c.y.o != 0 || c.y.p != nil {
		mx.printf(" y=")
		mx.printSpec(c.y)
	}
	if c.z.o != 0 || c.z.p != nil {
		mx.printf(" z=")
		mx.printSpec(c.z)
	}
	if c.b.o != 0 || c.b.p != nil || c.needB {
		mx.printf(" b=")
		mx.printSpec(c.b)
		if c.needB {
			mx.printf("*")
		}
	}
	if c.needRA {
		mx.printf(" rA=")
		mx.printSpec(c.ra)
	}

//line mmixpipe.w:665

//line mmixpipe.w:712
	if c.renX || c.memX {
		mx.printf(" x=")
		mx.printSpecnode(&c.x)
	} else if c.x.o != 0 {
		mx.printf(" x=")
		mx.printOcta(c.x.o)
		if c.x.known {
			mx.printf("!")
		} else {
			mx.printf("?")
		}
	}
	if c.renA {
		mx.printf(" a=")
		mx.printSpecnode(&c.a)
	}
	if c.setL {
		mx.printf(" rL=")
		mx.printSpecnode(&c.rl)
	}

//line mmixpipe.w:666
	if c.interrupt != 0 {
		mx.printf(" int=")
		mx.printBits(int(c.interrupt))
	}
	if c.arithExc != 0 {
		mx.printf(" exc=")
		mx.printBits(int(c.arithExc << 8))
	}
	if defaultGo := c.loc + 4; c.goLoc.o != defaultGo {
		mx.printf(" ->")
		mx.printOcta(c.goLoc.o)
	}
	if mx.verbose&showPredBit != 0 {
		mx.printf(" hist=%x", c.hist)
	}
	if c.i == pop {
		mx.printf(" rS=")
		mx.printOcta(c.curS)
		mx.printf(" rO=")
		mx.printOcta(c.curO)
	}
	mx.printf(" state=%d", c.state)
}

//line mmixpipe.w:1057
func (mx *machine) printBits(x int) {
	for j, b := 0, eBit; x&(b+b-1) != 0 && b != 0; j, b = j+1, b>>1 {
		if x&b != 0 {
			mx.printf("%c", bitCodeMap[j])
		}
	}
}

//line mmixpipe.w:1221
func (mx *machine) prevCtl(c *control) *control {
	if c == mx.reorderBot {
		return mx.reorderTop
	}
	return &mx.reorder[c.idx-1]
}

func (mx *machine) nextCtl(c *control) *control {
	if c == mx.reorderTop {
		return mx.reorderBot
	}
	return &mx.reorder[c.idx+1]
}

//line mmixpipe.w:1240
func (mx *machine) printReorderBuffer() {
	mx.printf("Reorder buffer")
	if mx.hot == mx.cool {
		mx.printf(" (empty)\n")
	} else {
		if mx.deissues != 0 {
			mx.printf(" (%d to be deissued)", mx.deissues)
		}
		if mx.doingInterrupt != 0 {
			mx.printf(" (interrupt state %d)", mx.doingInterrupt)
		}
		mx.printf(":\n")
		for p := mx.hot; p != mx.cool; p = mx.prevCtl(p) {
			mx.printControlBlock(p)
			if p.owner != nil {
				mx.printf(" ")
				mx.printCoroutineID(p.owner)
			}
			mx.printf("\n")
		}
	}
	mx.printf(" %d available rename register%s, %d memory slot%s\n",
		mx.renameRegs, plural(mx.renameRegs), mx.memSlots, plural(mx.memSlots))
}

func plural(n int) string {
	if n != 1 {
		return "s"
	}
	return ""
}

//line mmixpipe.w:1278
func (mx *machine) cycle() {
	var i, j, m int

//line mmixpipe.w:6728
	mx.g[rI].o--
	if mx.g[rI].o == 0 {
		mx.g[rQ].o |= intervalTimeout
		mx.newQ |= intervalTimeout
		if mx.verbose&issueBit != 0 {
			mx.printf(" setting rQ=")
			mx.printOcta(mx.g[rQ].o)
			mx.printf("\n")
		}
	}
	mx.tryingToInterrupt = false
	if mx.g[rQ].o&mx.g[rK].o != 0 && mx.cool != mx.hot &&
		mx.hot.interrupt&(eBit+fBit+hBit) == 0 && mx.doingInterrupt == 0 &&
		mx.hot.i != resum {
		if mx.hot.owner != nil {
			mx.tryingToInterrupt = true
		} else {
			mx.hot.interrupt |= eBit

//line mmixpipe.w:6763
			i = mx.issuedBetween(mx.hot, mx.cool)
			if i >= mx.deissues {
				mx.deissues = i
				mx.tail = mx.head // 가져오기 버퍼를 비운다
				mx.resuming = 0

//line mmixpipe.w:6096
				if mx.fetchCo.lockloc != nil {
					*mx.fetchCo.lockloc = nil
					mx.fetchCo.lockloc = nil
				}
				mx.unschedule(&mx.fetchCo)
				mx.startup(&mx.fetchCo, 1)

//line mmixpipe.w:6769
				if isLoadStore(mx.hot.i) {
					mx.nullifying = true
				}
			}

//line mmixpipe.w:6747
			mx.instPtr = spec{o: mx.g[rTT].o}
		}
	}

//line mmixpipe.w:1281
	mx.dispatchCount = 0
	mx.oldHot = mx.hot   // 사이클이 시작할 때 뜨거운 자리의 위치를 기억한다
	mx.oldTail = mx.tail // 사이클이 시작할 때 가져오기 버퍼의 내용을 기억한다
	mx.suppressDispatch = mx.deissues != 0 || mx.dispatchLock != nil
	if mx.doingInterrupt != 0 {

//line mmixpipe.w:6794
		d := mx.doingInterrupt
		mx.doingInterrupt--
		switch d {
		case 3:

//line mmixpipe.w:6807
			j = int(mx.hot.interrupt & hBit)
			if j != 0 {
				mx.g[rB].o = mx.g[255].o
			} else {
				mx.g[rBB].o = mx.g[255].o
			}
			mx.g[255].o = mx.g[rJ].o
			if mx.verbose&issueBit != 0 {
				if j != 0 {
					mx.printf(" setting rB=")
					mx.printOcta(mx.g[rB].o)
				} else {
					mx.printf(" setting rBB=")
					mx.printOcta(mx.g[rBB].o)
				}
				mx.printf(", $255=")
				mx.printOcta(mx.g[255].o)
				mx.printf("\n")
			}

//line mmixpipe.w:6799
		case 2:

//line mmixpipe.w:6843
			{
				hot := mx.hot
				j = int(packBytes(hot.op, int(hot.xx), int(hot.yy), int(hot.zz)))
				if hot.interrupt&hBit != 0 { // 트립
					mx.g[rW].o = hot.loc + 4
					mx.g[rX].o = sign32<<32 | Octa(Tetra(j))
					if mx.verbose&issueBit != 0 {
						mx.printf(" setting rW=")
						mx.printOcta(mx.g[rW].o)
						mx.printf(", rX=")
						mx.printOcta(mx.g[rX].o)
						mx.printf("\n")
					}
				} else { // 트랩
					mx.g[rWW].o = hot.goLoc.o
					mx.g[rXX].o = mx.g[rXX].o&^0xffffffff | Octa(Tetra(j))

//line mmixpipe.w:6872
					if hot.interrupt&fBit != 0 { // 강제
						if hot.i != trap {
							j = resumeTrans // 페이지 변환을 에뮬레이트한다
						} else if hot.op == TRAP {
							j = 0x80 // |TRAP|
						} else if flags[hot.op]&xIsDestBit != 0 {
							j = resumeSet // 에뮬레이션
						} else {
							j = 0x80 // r[X]가 목적지가 아닐 때의 에뮬레이션
						}
					} else { // 동적
						if hot.interim {
							if hot.i == frem || hot.i == syncd || hot.i == syncid {
								j = resumeCont
							} else {
								j = resumeAgain
							}
						} else if isLoadStore(hot.i) {
							j = resumeAgain
						} else {
							j = 0x80 // 보통의 바깥 인터럽트
						}
					}

//line mmixpipe.w:6860
					mx.g[rXX].o = mx.g[rXX].o&0xffffffff | Octa(Tetra(j<<24)+hot.interrupt&0xff)<<32
					if mx.verbose&issueBit != 0 {
						mx.printf(" setting rWW=")
						mx.printOcta(mx.g[rWW].o)
						mx.printf(", rXX=")
						mx.printOcta(mx.g[rXX].o)
						mx.printf("\n")
					}
				}
			}

//line mmixpipe.w:6801
		case 1:

//line mmixpipe.w:6897
			{
				hot := mx.hot
				j = int(hot.interrupt & hBit)
				yReg, zReg := rYY, rZZ
				if j != 0 {
					yReg, zReg = rY, rZ
				}
				if hot.interrupt&fBit != 0 && hot.op == SWYM {
					mx.g[rYY].o = hot.goLoc.o
				} else {
					mx.g[yReg].o = hot.y.o
				}
				if hot.i == st || hot.i == pst {
					mx.g[zReg].o = hot.x.o
				} else {
					mx.g[zReg].o = hot.z.o
				}
				if mx.verbose&issueBit != 0 {
					if j != 0 {
						mx.printf(" setting rY=")
						mx.printOcta(mx.g[rY].o)
						mx.printf(", rZ=")
						mx.printOcta(mx.g[rZ].o)
						mx.printf("\n")
					} else {
						mx.printf(" setting rYY=")
						mx.printOcta(mx.g[rYY].o)
						mx.printf(", rZZ=")
						mx.printOcta(mx.g[rZZ].o)
						mx.printf("\n")
					}
				}
			}

//line mmixpipe.w:6803
			mx.hot = mx.prevCtl(mx.hot)
		}

//line mmixpipe.w:1287
	} else {

//line mmixpipe.w:1310
		for m = mx.commitMax; m > 0 && mx.deissues > 0; m-- {

//line mmixpipe.w:2953
			mx.cool = mx.nextCtl(mx.cool)
			cool := mx.cool
			if mx.verbose&issueBit != 0 {
				mx.printf("Deissuing ")
				mx.printControlBlock(cool)
				if cool.owner != nil {
					mx.printf(" ")
					mx.printCoroutineID(cool.owner)
				}
				mx.printf("\n")
			}

//line mmixpipe.w:2978
			if cool.renX {
				mx.renameRegs++
				specRem(&cool.x)
			}
			if cool.renA {
				mx.renameRegs++
				specRem(&cool.a)
			}
			if cool.memX {
				mx.memSlots++
				specRem(&cool.x)
			}
			if cool.setL {
				specRem(&cool.rl)
			}

//line mmixpipe.w:2965
			if cool.owner != nil {
				if cool.owner.lockloc != nil {
					*cool.owner.lockloc = nil
					cool.owner.lockloc = nil
				}
				if cool.owner.next != nil {
					mx.unschedule(cool.owner)
				}
			}
			mx.coolO, mx.coolS = cool.curO, cool.curS
			mx.deissues--

//line mmixpipe.w:1312
		}
	commit:
		for ; m > 0; m-- {
			if mx.hot == mx.cool {
				break // 재정렬 버퍼가 비어 있다
			}
			if !mx.securityDisabled {

//line mmixpipe.w:3103
				if mx.hot.loc&signBit != 0 {
					if mx.g[rK].o&(pBit<<32) != 0 && mx.hot.interrupt&pBit == 0 {
						mx.hot.interrupt |= pBit
						mx.g[rQ].o |= pBit << 32
						mx.newQ |= pBit << 32
						if mx.verbose&issueBit != 0 {
							mx.printf(" setting rQ=")
							mx.printOcta(mx.g[rQ].o)
							mx.printf("\n")
						}
						break
					}
				} else if (mx.g[rK].o>>32)&0xff != 0xff && mx.hot.interrupt&sBit == 0 {
					mx.hot.interrupt |= sBit
					mx.g[rQ].o |= sBit << 32
					mx.newQ |= sBit << 32
					mx.g[rK].o |= sBit << 32
					if mx.verbose&issueBit != 0 {
						mx.printf(" setting rQ=")
						mx.printOcta(mx.g[rQ].o)
						mx.printf(", rK=")
						mx.printOcta(mx.g[rK].o)
						mx.printf("\n")
					}
					break
				}

//line mmixpipe.w:1320
			}
			if mx.hot.owner != nil {
				break // 뜨거운 자리의 명령이 끝나지 않았다
			}

//line mmixpipe.w:2995
			hot := mx.hot
			if mx.nullifying {

//line mmixpipe.w:3061
				if mx.verbose&issueBit != 0 {
					mx.printf("Nullifying ")
					mx.printControlBlock(hot)
					mx.printf("\n")
				}
				if hot.renX {
					mx.renameRegs++
					specRem(&hot.x)
				}
				if hot.renA {
					mx.renameRegs++
					specRem(&hot.a)
				}
				if hot.memX {
					mx.memSlots++
					specRem(&hot.x)
				}
				if hot.setL {
					specRem(&hot.rl)
				}
				mx.coolO, mx.coolS = hot.curO, hot.curS
				mx.nullifying = false

//line mmixpipe.w:2998
			} else {
				if hot.i == get && hot.zz == rQ {
					mx.newQ = mx.g[rQ].o &^ hot.x.o
				} else if hot.i == put && hot.xx == rQ {
					hot.x.o |= mx.newQ
				}
				if hot.memX {

//line mmixpipe.w:5099
					if hot.interrupt&(fBit+0xff) == 0 {
						q := mx.writeTail
						if hot.x.addr>>32&0xffff0000 != 0 {

//line mmixpipe.w:5125
							if hot.op >= STB && hot.op < STSF {
								q.size = (hot.op & 0xf) >> 2
							} else if hot.op >= STSF && hot.op < STCO {
								q.size = 2
							} else {
								q.size = 3
							}

//line mmixpipe.w:5103
						}
						found := false
						if hot.i != sync {

//line mmixpipe.w:5134
							for q != mx.writeHead {
								q = mx.nextWrite(q)
								if q.i == sync {
									break
								}
								if q.addr == hot.x.addr && (q != mx.writeHead || mx.wbufLock == nil) {
									found = true
									break
								}
							}

//line mmixpipe.w:5107
						}
						if !found {
							p := mx.prevWrite(mx.writeTail)
							if p == mx.writeHead {
								break commit // 쓰기 버퍼가 차 있다
							}
							q = mx.writeTail
							mx.writeTail = p
							q.addr = hot.x.addr
						}
						q.o = hot.x.o
						q.stamp = Tetra(mx.ticks)
						q.i = hot.i
					}
					specRem(&hot.x)
					mx.memSlots++

//line mmixpipe.w:3006
				}
				if hot.stackAlert {
					mx.stackOverflowed = true
				} else if mx.stackOverflowed && !hot.interim {
					mx.g[rQ].o |= stackOverflow
					mx.newQ |= stackOverflow
					mx.stackOverflowed = false
					if mx.verbose&issueBit != 0 {
						mx.printf(" setting rQ=")
						mx.printOcta(mx.g[rQ].o)
						mx.printf("\n")
					}
				}
				if mx.verbose&issueBit != 0 {
					mx.printf("Committing ")
					mx.printControlBlock(hot)
					mx.printf("\n")
				}

//line mmixpipe.w:3034
				if hot.renX {
					mx.renameRegs++
					hot.x.up.o = hot.x.o
					specRem(&hot.x)
				}
				if hot.renA {
					mx.renameRegs++
					hot.a.up.o = hot.a.o
					specRem(&hot.a)
				}
				if hot.setL {
					hot.rl.up.o = hot.rl.o
					specRem(&hot.rl)
				}
				if hot.arithExc != 0 {
					mx.g[rA].o |= Octa(hot.arithExc)
				}
				if hot.usage {
					const count = 1<<47 - 1
					mx.g[rU].o = mx.g[rU].o&^count | (mx.g[rU].o+1)&count
				}

//line mmixpipe.w:3025
			}
			if hot.interrupt >= hBit {

//line mmixpipe.w:6778
				if hot.interrupt&hBit == 0 {
					mx.g[rK].o = 0 // 트랩
				}
				if (hot.interrupt&hBit != 0 && hot.i != trip) ||
					(hot.interrupt&fBit != 0 && hot.i != trap) || hot.interrupt&eBit != 0 {
					mx.doingInterrupt = 3
					mx.suppressDispatch = true
				} else {
					mx.doingInterrupt = 2 // 배정기가 시작한 트립이나 트랩
				}
				break

//line mmixpipe.w:3028
			}

//line mmixpipe.w:1325
			i = mx.hot.i
			mx.hot = mx.prevCtl(mx.hot)
			if i == resum {
				break // 다시 시작한 명령이 새 rK를 보게 한다
			}
		}

//line mmixpipe.w:1289
	}

//line mmixpipe.w:2460
	mx.curTime++
	if mx.curTime == mx.ringSize {
		mx.curTime = 0
	}
	for self := mx.queuelist(mx.curTime); self != &mx.sentinel; self = mx.sentinel.next {
		mx.sentinel.next = self.next
		self.next = nil // 이 코루틴의 스케줄을 푼다
		if mx.verbose&coroutineBit != 0 {
			mx.printf(" running ")
			mx.printCoroutineID(self)
			mx.printf(" ")
			mx.printControlBlock(self.ctl)
			mx.printf("\n")
		}
		if mx.step(self) { // 원본의 |terminate|
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
		}
	}

//line mmixpipe.w:1291
	if !mx.suppressDispatch {

//line mmixpipe.w:1447
		trueHead := mx.head
		if mx.head == mx.oldTail && mx.head != mx.tail {
			mx.oldTail = mx.prevFetch(mx.head)
		}
		mx.peekHist = mx.coolHist
		for j = 0; j < mx.dispatchMax+mx.peekahead; j++ {

//line mmixpipe.w:1463
			if mx.head == mx.oldTail {
				break // 가져오기 버퍼가 비어 있다
			}
			newHead := mx.prevFetch(mx.head)
			op := int(mx.head.inst >> 24)
			yz := int(mx.head.inst & 0xffff)
			var f int
			freezeDispatch := false
			var u *funcUnit
			cool := mx.cool

//line mmixpipe.w:1549
			if mx.support[op>>5]&(sign32>>(op&31)) == 0 {
				// 아이고, 이 연산 코드는 어떤 기능 장치도 지원하지 않는다
				f, i = int(flags[TRAP]), trap
			} else {
				f, i = int(flags[op]), internalOp[op]
			}
			if i == trip && mx.head.loc&signBit != 0 {
				f, i = 0, noop
			}

//line mmixpipe.w:1881
			cool.op, cool.i = op, i
			cool.xx = byte(mx.head.inst >> 16)
			cool.yy = byte(mx.head.inst >> 8)
			cool.zz = byte(mx.head.inst)
			cool.loc = mx.head.loc
			cool.y, cool.z, cool.b, cool.ra = spec{}, spec{}, spec{}, spec{}
			cool.x.o, cool.a.o, cool.rl.o = 0, 0, 0
			cool.x.known, cool.x.up = false, nil
			cool.a.known, cool.a.up = false, nil
			cool.rl.known, cool.rl.up = true, nil
			cool.needB, cool.needRA = false, false
			cool.renX, cool.memX, cool.renA, cool.setL = false, false, false, false
			cool.arithExc, cool.denin, cool.denout = 0, 0, 0
			if mx.head.loc&signBit != 0 && mx.g[rU].o&(0x8000<<32) == 0 {
				cool.usage = false
			} else {
				cool.usage = Octa(op)&(mx.g[rU].o>>48) == mx.g[rU].o>>56
			}
			mx.newO, cool.curO = mx.coolO, mx.coolO
			mx.newS, cool.curS = mx.coolS, mx.coolS
			cool.interrupt = mx.head.interrupt
			cool.hist = mx.peekHist
			cool.goLoc.o = cool.loc + 4
			cool.goLoc.known = false
			cool.goLoc.addr = cool.goLoc.addr&0xffffffff | 0xffffffff<<32
			cool.interim, cool.stackAlert = false, false

//line mmixpipe.w:1483
			if f&relAddrBit != 0 {

//line mmixpipe.w:1685
				if i == jmp {
					yz = int(mx.head.inst & 0xffffff)
				}
				if op&1 != 0 {
					if i == jmp {
						yz -= 0x1000000
					} else {
						yz -= 0x10000
					}
				}
				cool.y = spec{o: mx.head.loc + 4}
				cool.z = spec{o: mx.head.loc + Octa(yz<<2)}

//line mmixpipe.w:1485
			}
			if mx.head.noted {
				mx.peekHist = mx.head.hist
			} else {

//line mmixpipe.w:1702
				{
					predicted := 0
					if op&0xe0 == 0x40 {

//line mmixpipe.w:3166
						predicted = op & 0x10 // 명령의 권고로 시작한다
						if mx.bpTable != nil {
							m = mx.bpIndex(mx.head.loc)
							if int(mx.bpTable[m])&mx.bpNpower != 0 {
								predicted ^= 0x10
							}
						}
						if predicted != 0 {
							mx.peekHist = mx.peekHist<<1 + 1
						} else {
							mx.peekHist <<= 1
						}

//line mmixpipe.w:1706
					}
					mx.head.noted = true
					mx.head.hist = mx.peekHist
					if predicted != 0 || f&ctlChangeBit != 0 || (i == syncid && cool.loc&signBit == 0) {
						mx.oldTail, mx.tail = newHead, newHead // 남은 가져오기를 모두 버린다

//line mmixpipe.w:6096
						if mx.fetchCo.lockloc != nil {
							*mx.fetchCo.lockloc = nil
							mx.fetchCo.lockloc = nil
						}
						mx.unschedule(&mx.fetchCo)
						mx.startup(&mx.fetchCo, 1)

//line mmixpipe.w:1712
						switch i {
						case jmp, br, pbr, pushj:
							mx.instPtr = cool.z
						case pop:
							if mx.g[rJ].up.known && j < mx.dispatchMax && mx.dispatchLock == nil &&
								!mx.nullifying {
								mx.instPtr = spec{o: mx.g[rJ].up.o + Octa(yz<<2)}
								break
							}
							fallthrough // 그렇지 않으면 |cool.goLoc|을 기다린다
						case goOp, pushgo, trap, resume, syncid:
							mx.instPtr.p = &mx.unknownSpec
						case trip:
							mx.instPtr = spec{}
						}
					}
				}

//line mmixpipe.w:1490
			}

//line mmixpipe.w:1474
			if j >= mx.dispatchMax || mx.dispatchLock != nil || mx.nullifying {
				mx.head = newHead
				continue // 배정할 수는 없지만, 앞을 엿볼 수는 있다
			}

//line mmixpipe.w:1493
			mx.newCool = mx.prevCtl(cool)
			stalled := true
		stall:
			for once := true; once; once = false {

//line mmixpipe.w:1914
				if mx.newCool == mx.hot {
					break stall // 재정렬 버퍼가 차 있다
				}

//line mmixpipe.w:1935
				if !mx.g[rL].up.known {
					break stall
				}
				mx.coolL = int(Tetra(mx.g[rL].up.o))
				if !mx.g[rG].up.known && !(op == UNSAVE && cool.xx == 1) {
					break stall
				}
				mx.coolG = int(Tetra(mx.g[rG].up.o))

//line mmixpipe.w:1945
				if mx.resuming != 0 {

//line mmixpipe.w:7068
					if mx.resuming&1 != 0 {
						cool.y = mx.specval(&mx.g[rY])
						cool.z = mx.specval(&mx.g[rZ])
					} else {
						cool.y = mx.specval(&mx.g[rYY])
						cool.z = mx.specval(&mx.g[rZZ])
					}
					if mx.resuming >= 3 { // |resumeSet|
						cool.needRA, cool.ra = true, mx.specval(&mx.g[rA])
					}
					cool.usage = false

//line mmixpipe.w:1947
				} else {
					if f&0x10 != 0 {

//line mmixpipe.w:1983
						if int(cool.xx) >= mx.coolG {
							cool.b = mx.specval(&mx.g[cool.xx])
						} else if int(cool.xx) < mx.coolL {
							cool.b = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx)))
						}
						if f&relAddrBit != 0 {
							cool.needB = true // |br|, |pbr|
						}

//line mmixpipe.w:1950
					}
					if thirdOperand[op] != 0 && cool.i != trap {

//line mmixpipe.w:2034
						if to := thirdOperand[op]; to == rA || to == rE {
							cool.needRA = true
							cool.ra = mx.specval(&mx.g[rA])
						}
						if to := thirdOperand[op]; to != rA {
							cool.needB = true
							cool.b = mx.specval(&mx.g[to])
						}

//line mmixpipe.w:1953
					}
					if f&0x1 != 0 {
						cool.z.o = Octa(cool.zz)
					} else if f&0x2 != 0 {

//line mmixpipe.w:1969
						if int(cool.zz) >= mx.coolG {
							cool.z = mx.specval(&mx.g[cool.zz])
						} else if int(cool.zz) < mx.coolL {
							cool.z = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.zz)))
						}

//line mmixpipe.w:1958
					} else if op&0xf0 == 0xe0 {

//line mmixpipe.w:2047
						cool.z.o = Octa(yz) << (48 - 16*(op&3))
						if i != set { // 레지스터 X가 Y 피연산자도 되어야 한다
							cool.y = cool.b
							cool.b = spec{}
						}

//line mmixpipe.w:1960
					}
					if f&0x4 != 0 {
						cool.y.o = Octa(cool.yy)
					} else if f&0x8 != 0 {

//line mmixpipe.w:1976
						if int(cool.yy) >= mx.coolG {
							cool.y = mx.specval(&mx.g[cool.yy])
						} else if int(cool.yy) < mx.coolL {
							cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.yy)))
						}

//line mmixpipe.w:1965
					}
				}

//line mmixpipe.w:1919
			dispatchDone:
				for once := true; once; once = false {
					if f&xIsDestBit != 0 {

//line mmixpipe.w:2060
						if int(cool.xx) >= mx.coolG {
							if i != pushgo && i != pushj && i != cswap {
								cool.renX = true
								mx.specInstall(&mx.g[cool.xx], &cool.x)
							}
						} else if int(cool.xx) < mx.coolL {
							if i != cswap {
								cool.renX = true
								mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)), &cool.x)
							}
						} else { // |head.inst|를 발행하기 전에 L을 늘려야 한다

//line mmixpipe.w:2075
							if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {

//line mmixpipe.w:2124
								cool.needB, cool.needRA = false, false
								cool.i = incgamma
								mx.newS = mx.coolS + 1
								cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
								cool.y = spec{o: mx.coolS << 3}
								cool.z = spec{}
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
								op = STOU // 이 명령은 적재/저장 장치가 다루어야 한다
								cool.interim = true
								cool.stackAlert = cool.y.o&signBit == 0
								break dispatchDone

//line mmixpipe.w:2077
							} else {

//line mmixpipe.w:2108
								cool.i = incrl
								mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(mx.coolL)), &cool.x)
								cool.needB, cool.needRA = false, false
								cool.y, cool.z = spec{}, spec{}
								cool.x.known = true // |cool.x.o=0|
								mx.specInstall(&mx.g[rL], &cool.rl)
								cool.rl.o = Octa(Tetra(mx.coolL + 1))
								cool.renX, cool.setL = true, true
								op = SETH // 이 명령은 가장 단순한 장치가 다룬다
								cool.interim = true
								break dispatchDone

//line mmixpipe.w:2079
							}

//line mmixpipe.w:2072
						}

//line mmixpipe.w:1923
					}
				special:
					switch i {

//line mmixpipe.w:2185
					case cswap:
						cool.renA = true
						if int(cool.xx) >= mx.coolG {
							mx.specInstall(&mx.g[cool.xx], &cool.a)
						} else {
							mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)), &cool.a)
						}
						cool.i = pst
						fallthrough
					case st:
						if op&0xfe == STCO {
							cool.b.o = cool.b.o&^0xffffffff | Octa(cool.xx)
						}
						fallthrough
					case pst:
						cool.memX = true
						mx.specInstall(&mx.mem, &cool.x)
					case ld, ldunc:
						cool.ptrA = mx.mem.up

//line mmixpipe.w:2213
					case put:
						if cool.yy != 0 || cool.xx >= 32 {

//line mmixpipe.w:2248
							cool.interrupt |= bBit
							cool.i = noop
							break special

//line mmixpipe.w:2216
						}
						if cool.xx >= 8 {
							if cool.xx <= 11 && cool.xx != 8 {

//line mmixpipe.w:2248
								cool.interrupt |= bBit
								cool.i = noop
								break special

//line mmixpipe.w:2220
							}
							if cool.xx <= 18 && cool.loc&signBit == 0 {

//line mmixpipe.w:2253
								cool.interrupt |= kBit
								cool.i = noop
								break special

//line mmixpipe.w:2223
							}
						}
						if cool.xx == 8 || (cool.xx >= 15 && cool.xx <= 20) {
							freezeDispatch = true
						}
						cool.renX = true
						mx.specInstall(&mx.g[cool.xx], &cool.x)
					case get:
						if cool.yy != 0 || cool.zz >= 32 {

//line mmixpipe.w:2248
							cool.interrupt |= bBit
							cool.i = noop
							break special

//line mmixpipe.w:2233
						}
						if cool.zz == rO {
							cool.z.o = mx.coolO << 3
						} else if cool.zz == rS {
							cool.z.o = mx.coolS << 3
						} else {
							cool.z = mx.specval(&mx.g[cool.zz])
						}
					case ldvts:
						if cool.loc&signBit != 0 {
							break
						}

//line mmixpipe.w:2253
						cool.interrupt |= kBit
						cool.i = noop
						break special

//line mmixpipe.w:2262
					case pushgo:
						mx.instPtr.p = &cool.goLoc
						fallthrough
					case pushj:
						x := int(cool.xx)
						if x >= mx.coolG {
							if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {

//line mmixpipe.w:2124
								cool.needB, cool.needRA = false, false
								cool.i = incgamma
								mx.newS = mx.coolS + 1
								cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
								cool.y = spec{o: mx.coolS << 3}
								cool.z = spec{}
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
								op = STOU // 이 명령은 적재/저장 장치가 다루어야 한다
								cool.interim = true
								cool.stackAlert = cool.y.o&signBit == 0
								break dispatchDone

//line mmixpipe.w:2270
							}
							x = mx.coolL
							mx.coolL++
							cool.renX = true
							mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(x)), &cool.x)
						}
						cool.x.known, cool.x.o = true, Octa(x)
						cool.renA = true
						mx.specInstall(&mx.g[rJ], &cool.a)
						cool.a.known, cool.a.o = true, cool.loc+4
						cool.setL = true
						mx.specInstall(&mx.g[rL], &cool.rl)
						cool.rl.o = Octa(Tetra(mx.coolL - x - 1))
						mx.newO = mx.coolO + Octa(x+1)
					case syncid:
						if cool.loc&signBit != 0 {
							break
						}
						fallthrough
					case goOp:
						mx.instPtr.p = &cool.goLoc

//line mmixpipe.w:2302
					case pop:
						if cool.xx != 0 && mx.coolL >= int(cool.xx) {
							cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
						}

//line mmixpipe.w:2309
						if Tetra(mx.coolS) == Tetra(mx.coolO) {

//line mmixpipe.w:2141
							if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
								// $\gamma$가 $\beta$를 지나가지 못하게 한다
								if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
									cool.i = or             // 주된 결과를 아래로 옮겨서 보존한다
									mx.head.inst -= 0x10000 // 가져오기 버퍼에 있는 \.{POP}의 X 필드를 줄인다
									op = OR
									cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
									mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
								} else { // rL을 1 줄인다
									mx.specInstall(&mx.g[rL], &cool.rl)
									cool.rl.o = Octa(Tetra(mx.coolL - 1))
									cool.setL = true
								}
							}
							if cool.i != or {
								cool.i = decgamma
								mx.newS = mx.coolS - 1
								cool.y = spec{o: mx.newS << 3}
								mx.specInstall(mx.lr(Tetra(mx.newS)), &cool.x)
								op = LDOU // 이 명령은 적재/저장 장치가 다루어야 한다
								cool.ptrA = mx.mem.up
							}
							cool.z, cool.b = spec{}, spec{}
							cool.needB = false
							cool.renX, cool.interim = true, true
							break dispatchDone

//line mmixpipe.w:2311
						}
						{
							var x Tetra
							if p := mx.lr(Tetra(mx.coolO) - 1).up; p.known {
								x = Tetra(p.o) & 0xff
							} else {
								break stall
							}
							if Tetra(mx.coolO)-Tetra(mx.coolS) <= x {

//line mmixpipe.w:2141
								if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
									// $\gamma$가 $\beta$를 지나가지 못하게 한다
									if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
										cool.i = or             // 주된 결과를 아래로 옮겨서 보존한다
										mx.head.inst -= 0x10000 // 가져오기 버퍼에 있는 \.{POP}의 X 필드를 줄인다
										op = OR
										cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
										mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
									} else { // rL을 1 줄인다
										mx.specInstall(&mx.g[rL], &cool.rl)
										cool.rl.o = Octa(Tetra(mx.coolL - 1))
										cool.setL = true
									}
								}
								if cool.i != or {
									cool.i = decgamma
									mx.newS = mx.coolS - 1
									cool.y = spec{o: mx.newS << 3}
									mx.specInstall(mx.lr(Tetra(mx.newS)), &cool.x)
									op = LDOU // 이 명령은 적재/저장 장치가 다루어야 한다
									cool.ptrA = mx.mem.up
								}
								cool.z, cool.b = spec{}, spec{}
								cool.needB = false
								cool.renX, cool.interim = true, true
								break dispatchDone

//line mmixpipe.w:2321
							}
							mx.newO = mx.coolO - Octa(x) - 1
							var newL int
							if cool.i == pop {
								if int(cool.xx) <= mx.coolL {
									newL = int(x) + int(cool.xx)
								} else {
									newL = int(x) + mx.coolL + 1
								}
							} else {
								newL = int(x)
							}
							if newL > mx.coolG {
								newL = mx.coolG
							}
							if int(x) < newL {
								cool.renX = true
								mx.specInstall(mx.lr(Tetra(mx.coolO)-1), &cool.x)
							}
							cool.setL = true
							mx.specInstall(&mx.g[rL], &cool.rl)
							cool.rl.o = Octa(Tetra(newL))
							if cool.i == pop {
								cool.z.o = Octa(yz << 2)
								if mx.instPtr.p == &mx.unknownSpec && newHead == mx.tail {
									mx.instPtr.p = &cool.goLoc
								}
							}
							break special
						}

//line mmixpipe.w:2353
					case mulu:
						cool.renA = true
						mx.specInstall(&mx.g[rH], &cool.a)
					case div, divu:
						cool.renA = true
						mx.specInstall(&mx.g[rR], &cool.a)

//line mmixpipe.w:2373
					case noop:
						if cool.interrupt&fBit != 0 {
							cool.goLoc.o, cool.y.o = cool.loc, cool.loc
							mx.instPtr = mx.specval(&mx.g[rT])
						}

//line mmixpipe.w:4407
					case preld, prest:
						if mx.Dcache == nil {
							cool.i = noop
							break special
						}
						if int(cool.xx) >= mx.Dcache.bb {
							cool.interim = true
						}
						cool.ptrA = mx.mem.up
					case prego:
						if mx.Icache == nil {
							cool.i = noop
							break special
						}
						if int(cool.xx) >= mx.Icache.bb {
							cool.interim = true
						}
						cool.ptrA = mx.mem.up

//line mmixpipe.w:6685
					case trap:
						if flags[op]&xIsDestBit != 0 && int(cool.xx) < mx.coolG && int(cool.xx) >= mx.coolL {

//line mmixpipe.w:2075
							if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {

//line mmixpipe.w:2124
								cool.needB, cool.needRA = false, false
								cool.i = incgamma
								mx.newS = mx.coolS + 1
								cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
								cool.y = spec{o: mx.coolS << 3}
								cool.z = spec{}
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
								op = STOU // 이 명령은 적재/저장 장치가 다루어야 한다
								cool.interim = true
								cool.stackAlert = cool.y.o&signBit == 0
								break dispatchDone

//line mmixpipe.w:2077
							} else {

//line mmixpipe.w:2108
								cool.i = incrl
								mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(mx.coolL)), &cool.x)
								cool.needB, cool.needRA = false, false
								cool.y, cool.z = spec{}, spec{}
								cool.x.known = true // |cool.x.o=0|
								mx.specInstall(&mx.g[rL], &cool.rl)
								cool.rl.o = Octa(Tetra(mx.coolL + 1))
								cool.renX, cool.setL = true, true
								op = SETH // 이 명령은 가장 단순한 장치가 다룬다
								cool.interim = true
								break dispatchDone

//line mmixpipe.w:2079
							}

//line mmixpipe.w:6688
						}
						if !mx.g[rT].up.known || !mx.g[rJ].up.known {
							break stall
						}
						mx.instPtr = mx.specval(&mx.g[rT]) // 트랩과 에뮬레이트하는 연산
						cool.needB, cool.b = true, mx.specval(&mx.g[255])
						fallthrough
					case trip:
						if !mx.g[rJ].up.known {
							break stall
						}
						cool.renX = true
						mx.specInstall(&mx.g[255], &cool.x)
						cool.x.known, cool.x.o = true, mx.g[rJ].up.o
						if i == trip {
							cool.goLoc.o = 0
						}
						cool.renA = true
						if i == trap {
							mx.specInstall(&mx.g[rBB], &cool.a)
						} else {
							mx.specInstall(&mx.g[rB], &cool.a)
						}

//line mmixpipe.w:6937
					case resume:
						if cool != mx.oldHot {
							break stall
						}
						if cool.zz != 0 {
							mx.instPtr = mx.specval(&mx.g[rWW])
						} else {
							mx.instPtr = mx.specval(&mx.g[rW])
						}
						if cool.loc&signBit == 0 {
							if cool.zz != 0 {
								cool.interrupt |= kBit
							} else if mx.instPtr.o&signBit != 0 {
								cool.interrupt |= pBit
							}
						}
						if cool.interrupt != 0 {
							mx.instPtr.o = cool.loc + 4
							cool.i = noop
						} else {
							cool.goLoc.o = mx.instPtr.o
							if cool.zz != 0 {

//line mmixpipe.w:8275
								if cool.loc == mx.g[rT].o {
									if xl := Tetra(mx.g[rXX].o); xl&0xffff0000 == 0 && byte(xl>>8) <= maxSysCall {
										yy, zz := byte(xl>>8), byte(xl)
										var ma, mb Octa

//line mmixpipe.w:8410
										if argCount[yy] == 3 {
											if argLoc := mx.g[rBB].o; argLoc>>32&0x9fffffff == 0 {
												mb = mx.magicRead(magicAddr(argLoc))
											}
											if argLoc := mx.g[rBB].o + 8; argLoc>>32&0x9fffffff == 0 {
												ma = mx.magicRead(magicAddr(argLoc))
											}
										}

//line mmixpipe.w:8280
										switch yy {
										case Halt:

//line mmixpipe.w:8309
											if zz == 0 {
												mx.halted = true
											} else if zz == 1 {
												trapLoc := mx.g[rWW].o - 4
												if !(trapLoc>>32 != 0 || Tetra(trapLoc) >= 0xf0) {
													mx.io.PrintTripWarning(int(Tetra(trapLoc)>>4), mx.g[rW].o-4)
												}
											}

//line mmixpipe.w:8283
										case Fopen:
											mx.g[rBB].o = mx.io.Fopen(zz, mb, ma)
										case Fclose:
											mx.g[rBB].o = mx.io.Fclose(zz)
										case Fread:
											mx.g[rBB].o = mx.io.Fread(zz, mb, ma)
										case Fgets:
											mx.g[rBB].o = mx.io.Fgets(zz, mb, ma)
										case Fgetws:
											mx.g[rBB].o = mx.io.Fgetws(zz, mb, ma)
										case Fwrite:
											mx.g[rBB].o = mx.io.Fwrite(zz, mb, ma)
										case Fputs:
											mx.g[rBB].o = mx.io.Fputs(zz, mx.g[rBB].o)
										case Fputws:
											mx.g[rBB].o = mx.io.Fputws(zz, mx.g[rBB].o)
										case Fseek:
											mx.g[rBB].o = mx.io.Fseek(zz, mx.g[rBB].o)
										case Ftell:
											mx.g[rBB].o = mx.io.Ftell(zz)
										}
									}
									mx.g[255].o = negOne // 이것이 인터럽트를 허용한다
								}

//line mmixpipe.w:6960
								cool.renA = true
								mx.specInstall(&mx.g[rK], &cool.a)
								cool.a.known, cool.a.o = true, mx.g[255].o
								cool.renX = true
								mx.specInstall(&mx.g[255], &cool.x)
								cool.x.known, cool.x.o = true, mx.g[rBB].o
							}
							if cool.zz != 0 {
								cool.b = mx.specval(&mx.g[rXX])
							} else {
								cool.b = mx.specval(&mx.g[rX])
							}
							if cool.b.o&signBit == 0 {

//line mmixpipe.w:6991
								cool.xx = byte(cool.b.o >> 56)
								cool.i = resum
								mx.head.loc = mx.instPtr.o - 4
								{
									again, bad := false, false
									switch cool.xx {
									case resumeSet:
										cool.b.o = cool.b.o&^0xffffffff | Octa(Tetra(SETH)<<24+Tetra(cool.b.o)&0xff0000)
										mx.head.interrupt |= Tetra(cool.b.o>>32) & 0xff00
										mx.resuming = 2
										fallthrough
									case resumeCont:
										mx.resuming += 1 + int(cool.zz)
										if (Tetra(cool.b.o)>>24)&0xfa != 0xb8 { // |syncd|나 |syncid|가 아니다

//line mmixpipe.w:7044
											m = int(Tetra(cool.b.o) >> 28)
											if (1<<m)&0x8f30 != 0 {
												bad = true
												break
											}
											m = int(Tetra(cool.b.o)>>16) & 0xff
											if m >= mx.coolL && m < mx.coolG {
												bad = true
												break
											}

//line mmixpipe.w:7006
										}
										again = true
									case resumeAgain:
										again = true
									case resumeTrans:

//line mmixpipe.w:7032
										if cool.zz != 0 {
											cool.y, cool.z = mx.specval(&mx.g[rYY]), mx.specval(&mx.g[rZZ])
											if Tetra(cool.b.o)>>24 != SWYM {
												again = true
												break
											}
											cool.i = resume // 위의 ``미묘한 점''을 보라
											break
										}
										bad = true

//line mmixpipe.w:7012
									default:
										bad = true
									}

//line mmixpipe.w:7019
									if again {

//line mmixpipe.w:7056
										mx.head.inst = Tetra(cool.b.o)
										m = int(mx.head.inst >> 24)
										if m == RESUME {
											bad = true // 가로막을 수 없는 루프를 피한다
										} else {
											if cool.zz == 0 && m > RESUME && m <= SYNC && mx.head.inst&badInstMask[m-RESUME] != 0 {
												mx.head.interrupt |= bBit
											}
											mx.head.noted = false
										}

//line mmixpipe.w:7021
									}
									if bad {
										cool.interrupt |= bBit
										cool.i = noop
										mx.resuming = 0
									}

//line mmixpipe.w:7016
								}

//line mmixpipe.w:6974
							}
						}

//line mmixpipe.w:7278
					case unsave:
						if cool.interrupt&bBit != 0 {
							cool.i = noop
						} else {
							cool.interim = true
							op = LDOU // 이 명령은 적재/저장 장치가 다루어야 한다
							cool.i = unsav
							switch cool.xx {
							case 0:
								if cool.z.p != nil {
									break stall
								}

//line mmixpipe.w:7311
								cool.renX = true
								mx.specInstall(&mx.g[rG], &cool.x)
								cool.renA = true
								mx.specInstall(&mx.g[rA], &cool.a)
								mx.newO = cool.z.o >> 3
								mx.newS = mx.newO
								cool.setL = true
								mx.specInstall(&mx.g[rL], &cool.rl)
								cool.ptrA = mx.mem.up

//line mmixpipe.w:7291
							case 1, 2:

//line mmixpipe.w:7303
								cool.renX = true
								mx.specInstall(&mx.g[cool.yy], &cool.x)
								mx.newO = mx.coolO - 1
								mx.newS = mx.newO
								cool.z.o = mx.newO << 3
								cool.ptrA = mx.mem.up

//line mmixpipe.w:7293
							case 3:
								cool.i, cool.interim, op = unsave, false, UNSAVE

//line mmixpipe.w:2309
								if Tetra(mx.coolS) == Tetra(mx.coolO) {

//line mmixpipe.w:2141
									if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
										// $\gamma$가 $\beta$를 지나가지 못하게 한다
										if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
											cool.i = or             // 주된 결과를 아래로 옮겨서 보존한다
											mx.head.inst -= 0x10000 // 가져오기 버퍼에 있는 \.{POP}의 X 필드를 줄인다
											op = OR
											cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
											mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
										} else { // rL을 1 줄인다
											mx.specInstall(&mx.g[rL], &cool.rl)
											cool.rl.o = Octa(Tetra(mx.coolL - 1))
											cool.setL = true
										}
									}
									if cool.i != or {
										cool.i = decgamma
										mx.newS = mx.coolS - 1
										cool.y = spec{o: mx.newS << 3}
										mx.specInstall(mx.lr(Tetra(mx.newS)), &cool.x)
										op = LDOU // 이 명령은 적재/저장 장치가 다루어야 한다
										cool.ptrA = mx.mem.up
									}
									cool.z, cool.b = spec{}, spec{}
									cool.needB = false
									cool.renX, cool.interim = true, true
									break dispatchDone

//line mmixpipe.w:2311
								}
								{
									var x Tetra
									if p := mx.lr(Tetra(mx.coolO) - 1).up; p.known {
										x = Tetra(p.o) & 0xff
									} else {
										break stall
									}
									if Tetra(mx.coolO)-Tetra(mx.coolS) <= x {

//line mmixpipe.w:2141
										if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
											// $\gamma$가 $\beta$를 지나가지 못하게 한다
											if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
												cool.i = or             // 주된 결과를 아래로 옮겨서 보존한다
												mx.head.inst -= 0x10000 // 가져오기 버퍼에 있는 \.{POP}의 X 필드를 줄인다
												op = OR
												cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
												mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
											} else { // rL을 1 줄인다
												mx.specInstall(&mx.g[rL], &cool.rl)
												cool.rl.o = Octa(Tetra(mx.coolL - 1))
												cool.setL = true
											}
										}
										if cool.i != or {
											cool.i = decgamma
											mx.newS = mx.coolS - 1
											cool.y = spec{o: mx.newS << 3}
											mx.specInstall(mx.lr(Tetra(mx.newS)), &cool.x)
											op = LDOU // 이 명령은 적재/저장 장치가 다루어야 한다
											cool.ptrA = mx.mem.up
										}
										cool.z, cool.b = spec{}, spec{}
										cool.needB = false
										cool.renX, cool.interim = true, true
										break dispatchDone

//line mmixpipe.w:2321
									}
									mx.newO = mx.coolO - Octa(x) - 1
									var newL int
									if cool.i == pop {
										if int(cool.xx) <= mx.coolL {
											newL = int(x) + int(cool.xx)
										} else {
											newL = int(x) + mx.coolL + 1
										}
									} else {
										newL = int(x)
									}
									if newL > mx.coolG {
										newL = mx.coolG
									}
									if int(x) < newL {
										cool.renX = true
										mx.specInstall(mx.lr(Tetra(mx.coolO)-1), &cool.x)
									}
									cool.setL = true
									mx.specInstall(&mx.g[rL], &cool.rl)
									cool.rl.o = Octa(Tetra(newL))
									if cool.i == pop {
										cool.z.o = Octa(yz << 2)
										if mx.instPtr.p == &mx.unknownSpec && newHead == mx.tail {
											mx.instPtr.p = &cool.goLoc
										}
									}
									break special
								}

//line mmixpipe.w:7296
							default:
								cool.interim, cool.i = false, noop
								cool.interrupt |= bBit
							}
						} // 이것이 우리를 |dispatchDone|으로 데려간다

//line mmixpipe.w:7358
					case save:
						if int(cool.xx) < mx.coolG {
							cool.interrupt |= bBit
						}
						if cool.interrupt&bBit != 0 {
							cool.i = noop
						} else if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {

//line mmixpipe.w:2124
							cool.needB, cool.needRA = false, false
							cool.i = incgamma
							mx.newS = mx.coolS + 1
							cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
							cool.y = spec{o: mx.coolS << 3}
							cool.z = spec{}
							cool.memX = true
							mx.specInstall(&mx.mem, &cool.x)
							op = STOU // 이 명령은 적재/저장 장치가 다루어야 한다
							cool.interim = true
							cool.stackAlert = cool.y.o&signBit == 0
							break dispatchDone

//line mmixpipe.w:7366
						} else {
							cool.interim = true
							cool.i = sav
							switch cool.zz {
							case 0:

//line mmixpipe.w:7392
								cool.zz = 1
								cool.renX = true
								mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(mx.coolL)), &cool.x)
								cool.x.known, cool.x.o = true, Octa(Tetra(mx.coolL))
								cool.setL = true
								mx.specInstall(&mx.g[rL], &cool.rl)
								mx.newO = mx.coolO + Octa(mx.coolL+1)

//line mmixpipe.w:7372
							case 1:
								if Tetra(mx.coolO) != Tetra(mx.coolS) {

//line mmixpipe.w:2124
									cool.needB, cool.needRA = false, false
									cool.i = incgamma
									mx.newS = mx.coolS + 1
									cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
									cool.y = spec{o: mx.coolS << 3}
									cool.z = spec{}
									cool.memX = true
									mx.specInstall(&mx.mem, &cool.x)
									op = STOU // 이 명령은 적재/저장 장치가 다루어야 한다
									cool.interim = true
									cool.stackAlert = cool.y.o&signBit == 0
									break dispatchDone

//line mmixpipe.w:7375
								}
								cool.zz = 2
								cool.yy = byte(mx.coolG)
								fallthrough
							case 2, 3:

//line mmixpipe.w:7401
								op = STOU // 이 명령은 적재/저장 장치가 다루어야 한다
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
								cool.z.o = mx.coolO << 3
								mx.newO = mx.coolO + 1
								mx.newS = mx.newO
								if cool.zz == 3 && cool.yy > rZ {

//line mmixpipe.w:7416
									cool.i = save
									cool.interim = false
									cool.renA = true
									mx.specInstall(&mx.g[cool.xx], &cool.a)

//line mmixpipe.w:7409
								} else {
									cool.b = mx.specval(&mx.g[cool.yy])
								}

//line mmixpipe.w:7381
							default:
								cool.interim, cool.i = false, noop
								cool.interrupt |= bBit
							}
						}

//line mmixpipe.w:7649
					case fsqrt, fint, fix, flot:
						if Tetra(cool.y.o) > 4 {

//line mmixpipe.w:2248
							cool.interrupt |= bBit
							cool.i = noop
							break special

//line mmixpipe.w:7652
						}

//line mmixpipe.w:7828
					case sync:
						if cool.zz > 3 {
							if cool.loc&signBit == 0 {

//line mmixpipe.w:2253
								cool.interrupt |= kBit
								cool.i = noop
								break special

//line mmixpipe.w:7832
							}
							if cool.zz == 4 {
								freezeDispatch = true
							}
						} else {
							if cool.zz != 1 {
								freezeDispatch = true
							}
							if cool.zz&1 != 0 {
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
							}
						}

//line mmixpipe.w:1927
					}
				}

//line mmixpipe.w:1498

//line mmixpipe.w:1604
				{
					t, b := op>>5, Tetra(sign32)>>(op&31)
					found := false
					if cool.i == trap && op != TRAP { // 연산 코드를 에뮬레이트해야 한다
						u = &mx.funit[mx.funitCount] // 이 장치는 \.{TRIP}과 \.{TRAP}만 지원한다
						found = true
					}
				units:
					for k := 0; !found && k <= mx.funitCount; k++ {
						u = &mx.funit[k]
						if u.ops[t]&b != 0 {
							for s := 0; s < u.k; s++ {
								if u.co[s].next != nil {
									continue units
								}
							}
							found = true
						}
					}
					for k := 0; !found && k < mx.funitCount; k++ {
						u = &mx.funit[k]
						if u.ops[t]&b != 0 && u.co[0].next == nil {
							found = true
						}
					}
					if !found {
						break stall // 이 |op|를 다루는 장치가 모두 바쁘다
					}
				}

//line mmixpipe.w:1499

//line mmixpipe.w:2082
				if mx.renameRegs < b2i(cool.renX)+b2i(cool.renA) {
					break stall
				}
				if cool.memX {
					if mx.memSlots != 0 {
						mx.memSlots--
					} else {
						break stall
					}
				}
				mx.renameRegs -= b2i(cool.renX) + b2i(cool.renA)

//line mmixpipe.w:1500
				if op&0xe0 == 0x40 {

//line mmixpipe.w:3192
					if mx.bpTable != nil {
						reversed := op & 0x10
						if mx.peekHist&1 != 0 {
							reversed ^= 0x10
						}
						m = mx.bpIndex(mx.head.loc)
						h := int(mx.bpTable[m])
						hUp := (h + 1) & mx.bpNmask
						if hUp == mx.bpNpower {
							hUp = h
						}
						hDown := h
						if h != mx.bpNpower {
							hDown = (h - 1) & mx.bpNmask
						}
						if reversed != 0 {
							mx.bpTable[m] = int8(hDown)
							cool.x.o = Octa(Tetra(hUp))
							cool.i = pbr + br - cool.i // 뜻을 뒤집는다
							mx.bpRevStat++
						} else {
							mx.bpTable[m] = int8(hUp)
							cool.x.o = Octa(Tetra(hDown)) // 흐름을 따른다
							mx.bpOkStat++
						}
						if mx.verbose&showPredBit != 0 {
							mx.printf(" predicting ")
							mx.printOcta(cool.loc)
							ok := "OK"
							if reversed != 0 {
								ok = "NG"
							}
							b := int(mx.bpTable[m])
							mx.printf(" %s; bp[%x]=%d\n", ok, m, b-((b&mx.bpNpower)<<1))
						}
						cool.x.o |= Octa(Tetra(m)) << 32
					}

//line mmixpipe.w:1502
				}

//line mmixpipe.w:1560
				if cool.interim {
					cool.usage = false
					if cool.op == SAVE {

//line mmixpipe.w:7422
						switch cool.zz {
						case 1:
							mx.head.inst = packBytes(SAVE, int(cool.xx), 0, 1)
						case 2:
							if cool.yy == 255 {
								mx.head.inst = packBytes(SAVE, int(cool.xx), 0, 3)
							} else {
								mx.head.inst = packBytes(SAVE, int(cool.xx), int(cool.yy)+1, 2)
							}
						case 3:
							if cool.yy == rR {
								mx.head.inst = packBytes(SAVE, int(cool.xx), rP, 3)
							} else {
								mx.head.inst = packBytes(SAVE, int(cool.xx), int(cool.yy)+1, 3)
							}
						}

//line mmixpipe.w:1564
					} else if cool.op == UNSAVE {

//line mmixpipe.w:7322
						switch cool.xx {
						case 0:
							mx.head.inst = packBytes(UNSAVE, 1, rZ, 0)
						case 1:
							if cool.yy == rP {
								mx.head.inst = packBytes(UNSAVE, 1, rR, 0)
							} else if cool.yy == 0 {
								mx.head.inst = packBytes(UNSAVE, 2, 255, 0)
							} else {
								mx.head.inst = packBytes(UNSAVE, 1, int(cool.yy)-1, 0)
							}
						case 2:
							if int(cool.yy) == mx.coolG {
								mx.head.inst = packBytes(UNSAVE, 3, 0, 0)
							} else {
								mx.head.inst = packBytes(UNSAVE, 2, int(cool.yy)-1, 0)
							}
						}

//line mmixpipe.w:1566
					} else if cool.i == preld || cool.i == prest {

//line mmixpipe.w:4434
						mx.head.inst = (mx.head.inst &^ (Tetra(mx.Dcache.bb-1) << 16)) - 0x10000

//line mmixpipe.w:1568
					} else if cool.i == prego {

//line mmixpipe.w:4437
						mx.head.inst = (mx.head.inst &^ (Tetra(mx.Icache.bb-1) << 16)) - 0x10000

//line mmixpipe.w:1570
					}
				} else if cool.i <= maxRealCommand {
					if flags[cool.op]&ctlChangeBit != 0 || cool.i == pbr {
						if mx.instPtr.p == nil && mx.instPtr.o&signBit != 0 && cool.loc&signBit == 0 &&
							cool.i != trap {
							cool.interrupt |= pBit // 음이 아닌 곳에서 음인 곳으로 점프한다
						}
					}
					trueHead, mx.head = newHead, newHead // 가져오기 버퍼에서 명령을 지운다
					mx.resuming = 0
				}
				if freezeDispatch {
					setLock(&u.co[0], &mx.dispatchLock)
				}
				cool.owner = &u.co[0]
				u.co[0].ctl = cool
				mx.startup(&u.co[0], 1) // 새 명령의 실행을 스케줄한다
				if mx.verbose&issueBit != 0 {
					mx.printf("Issuing ")
					mx.printControlBlock(cool)
					mx.printf(" ")
					mx.printCoroutineID(&u.co[0])
					mx.printf("\n")
				}
				mx.dispatchCount++

//line mmixpipe.w:1504
				stalled = false
			}
			if stalled {

//line mmixpipe.w:2380
				if cool.renX || cool.memX {
					specRem(&cool.x)
				}
				if cool.renA {
					specRem(&cool.a)
				}
				if cool.setL {
					specRem(&cool.rl)
				}
				if mx.instPtr.p == &cool.goLoc {
					mx.instPtr.p = &mx.unknownSpec
				}
				break

//line mmixpipe.w:1508
			}
			mx.cool = mx.newCool
			mx.coolO, mx.coolS = mx.newO, mx.newS
			mx.coolHist = mx.peekHist

//line mmixpipe.w:1454
		}
		mx.head = trueHead

//line mmixpipe.w:1293
	}
	mx.ticks++ // 그리고 박자가 넘어간다
	mx.dispatchStat[mx.dispatchCount]++
}

//line mmixpipe.w:1372
func (mx *machine) prevFetch(p *fetch) *fetch {
	if p == mx.fetchBot {
		return mx.fetchTop
	}
	return &mx.fetchBuf[p.idx-1]
}

//line mmixpipe.w:1393
func (mx *machine) printFetchBuffer() {
	mx.printf("Fetch buffer")
	if mx.head == mx.tail {
		mx.printf(" (empty)\n")
	} else {
		if mx.resuming != 0 {
			mx.printf(" (resumption state %d)", mx.resuming)
		}
		mx.printf(":\n")
		for p := mx.head; p != mx.tail; p = mx.prevFetch(p) {
			mx.printOcta(p.loc)
			mx.printf(": %08x(%s)", p.inst, opcodeName[p.inst>>24])
			if p.interrupt != 0 {
				mx.printBits(int(p.interrupt))
			}
			if p.noted {
				mx.printf("*")
			}
			mx.printf("\n")
		}
	}
	mx.printf("Instruction pointer is ")
	if mx.instPtr.p == nil {
		mx.printOcta(mx.instPtr.o)
	} else {
		mx.printf("waiting for ")
		if mx.instPtr.p == &mx.unknownSpec {
			mx.printf("dispatch")
		} else if mx.instPtr.p.addr>>32 == 0xffffffff {
			mx.printCoroutineID(mx.instPtr.p.ctl.owner)
		} else {
			mx.printSpecnodeID(mx.instPtr.p.addr)
		}
	}
	mx.printf("\n")
}

//line mmixpipe.w:1805
func (mx *machine) printSpecnodeID(a Octa) {
	if a>>32 == sign32 {
		switch l := Tetra(a); {
		case l < 32:
			mx.printf("%s", specialName[l])
		case l < 256:
			mx.printf("g[%d]", l)
		default:
			mx.printf("l[%d]", l-256)
		}
	} else if a>>32 != 0xffffffff {
		mx.printf("m[")
		mx.printOcta(a)
		mx.printf("]")
	}
}

//line mmixpipe.w:1829
func (mx *machine) specval(r *specnode) spec {
	if r.up.known {
		return spec{o: r.up.o}
	}
	return spec{p: r.up}
}

//line mmixpipe.w:1839
func (mx *machine) specInstall(r, t *specnode) { // |t|를 리스트 |r|에 넣는다
	t.up = r.up
	t.up.down = t
	r.up = t
	t.down = r
	t.addr = r.addr
}

//line mmixpipe.w:1850
func specRem(t *specnode) { // |t|를 그 리스트에서 뺀다
	u, d := t.up, t.down
	u.down = d
	d.up = u
}

//line mmixpipe.w:1876
func (mx *machine) lr(t Tetra) *specnode {
	return &mx.l[int(t)&mx.lringMask]
}

//line mmixpipe.w:2097
func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

//line mmixpipe.w:2441
func (mx *machine) wait(self *coroutine, t int) bool {
	mx.schedule(self, t, self.ctl.state)
	return false
}

func (mx *machine) passAfter(self *coroutine, t int) {
	mx.schedule(self.succ, t, self.ctl.state)
}

func (mx *machine) sleep(self *coroutine) bool { // 영원히 기다린다
	self.next = self
	return false
}

func (mx *machine) awaken(c *coroutine, t int) {
	mx.schedule(c, t, c.ctl.state)
}

//line mmixpipe.w:2489
func (mx *machine) step(self *coroutine) bool {
	data := self.ctl
	var (
		i, j int
		p, q *cacheblock
		c    *cache
		cc   *coroutine
		co   []coroutine
		pc   label

//line mmixpipe.w:4125
		blockDiff int // |flushToS|에서 더 읽어야 할 바이트 수

//line mmixpipe.w:2499
	)
	switch self.stage {
	case 0:
		pc = lSwitch0
	case 1:
		pc = lSwitch1
	default:
		pc = lSwitch2

//line mmixpipe.w:2572
	case vanish:
		return true

//line mmixpipe.w:4053
	case flushToMem:
		c = data.ptrA.(*cache)
		pc = flushMemSt + label(data.state)

//line mmixpipe.w:4118
	case flushToS:
		c = data.ptrA.(*cache)
		blockDiff = mx.Scache.bb - c.outbuf.rank
		p, _ = data.ptrB.(*cacheblock)
		pc = flushSSt + label(data.state)

//line mmixpipe.w:4251
	case fillFromMem:
		c = data.ptrA.(*cache)
		cc = c.fillLock
		pc = fillMemSt + label(data.state)

//line mmixpipe.w:4307
	case fillFromS:
		c = data.ptrA.(*cache)
		cc = c.fillLock
		p, _ = data.ptrC.(*cacheblock)
		pc = fillSSt + label(data.state)

//line mmixpipe.w:4468
	case cleanup:
		p, _ = data.ptrB.(*cacheblock)
		pc = cleanupSt + label(data.state)

//line mmixpipe.w:4772
	case fillFromVirt:
		c = data.ptrA.(*cache)
		cc = c.fillLock
		co = data.ptrC.([]coroutine) // |IPTco|나 |DPTco|
		pc = fillVirtSt + label(data.state)

//line mmixpipe.w:5153
	case writeFromWbuf:
		p, _ = data.ptrB.(*cacheblock)
		pc = writeSt + label(data.state)

//line mmixpipe.w:2508
	}
	for {
		switch pc {

//line mmixpipe.w:6138
		case lSwitch0:
			pc = fetchSt + label(data.state)
			continue
		case lNewFetch:
			data.state = 0

//line mmixpipe.w:6179
			if mx.instPtr.p != nil {
				if mx.instPtr.p != &mx.unknownSpec && mx.instPtr.p.known {
					mx.instPtr.o, mx.instPtr.p = mx.instPtr.p.o, nil
				}
				return mx.wait(self, 1)
			}

//line mmixpipe.w:6144
			data.y.o = mx.instPtr.o
			data.state = 1
			data.interrupt = 0
			data.x.o, data.z.o = 0, 0
			fallthrough
		case lStartFetch:
			if data.y.o&signBit != 0 {

//line mmixpipe.w:6277
				if data.i == prego && data.loc&signBit == 0 {
					pc = lFinEx
					continue
				}
				data.z.o = data.y.o - signBit
				pc = lKnownPhys
				continue

//line mmixpipe.w:6152
			}
			if mx.pageBad {
				pc = lBadFetch
				continue
			}
			if mx.ITcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.ITcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.ITcache.reader[j], mx.ITcache.accessTime)

//line mmixpipe.w:6197
			p = mx.cacheSearch(mx.ITcache, mx.transKey(data.y.o))
			if mx.Icache == nil || mx.Icache.lock != nil {

//line mmixpipe.w:6260
				if p != nil {

//line mmixpipe.w:6242
					p = mx.useAndFix(mx.ITcache, p)
					if Tetra(p.data[0])&(pxBit>>protOffset) == 0 {
						pc = lBadFetch
						continue
					}

//line mmixpipe.w:6262
					data.z.o = mx.physAddr(data.y.o, p.data[0])
					data.state = itHit
				} else {
					data.state = itMiss
				}
				if mx.waitOrPass(self, mx.ITcache.accessTime) {
					pc = lPassit
					continue
				}
				return false

//line mmixpipe.w:6200
			}
			if j = getReader(mx.Icache); j < 0 {

//line mmixpipe.w:6260
				if p != nil {

//line mmixpipe.w:6242
					p = mx.useAndFix(mx.ITcache, p)
					if Tetra(p.data[0])&(pxBit>>protOffset) == 0 {
						pc = lBadFetch
						continue
					}

//line mmixpipe.w:6262
					data.z.o = mx.physAddr(data.y.o, p.data[0])
					data.state = itHit
				} else {
					data.state = itMiss
				}
				if mx.waitOrPass(self, mx.ITcache.accessTime) {
					pc = lPassit
					continue
				}
				return false

//line mmixpipe.w:6203
			}
			mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)
			if p != nil {

//line mmixpipe.w:6242
				p = mx.useAndFix(mx.ITcache, p)
				if Tetra(p.data[0])&(pxBit>>protOffset) == 0 {
					pc = lBadFetch
					continue
				}

//line mmixpipe.w:6218
				data.z.o = mx.physAddr(data.y.o, p.data[0])
				if mx.Icache.b+mx.Icache.c > mx.pageS &&
					(Tetra(data.y.o)^Tetra(data.z.o))&Tetra((mx.Icache.bb<<mx.Icache.c)-(1<<mx.pageS)) != 0 {
					data.state = itHit // 가짜 I-캐시 찾기
				} else {

//line mmixpipe.w:6232
					q = mx.cacheSearch(mx.Icache, data.z.o)
					if q != nil {
						q = mx.useAndFix(mx.Icache, q)

//line mmixpipe.w:6251
						if data.i != prego {
							for j = 0; j < mx.Icache.bb>>3; j++ {
								mx.fetched[j] = q.data[j]
							}
							mx.fetchLo = int(Tetra(mx.instPtr.o)&Tetra(mx.Icache.bb-1)) >> 3
							mx.fetchHi = mx.Icache.bb >> 3
						}

//line mmixpipe.w:6236
						data.state = fetchReady
					} else {
						data.state = iHitAndMiss
					}

//line mmixpipe.w:6224
				}
				if mx.waitOrPass(self, max(mx.ITcache.accessTime, mx.Icache.accessTime)) {
					pc = lPassit
					continue
				}
				return false

//line mmixpipe.w:6207
			} else {
				data.state = itMiss
			}

//line mmixpipe.w:6165
			if mx.waitOrPass(self, mx.ITcache.accessTime) {
				pc = lPassit
				continue
			}
			return false

//line mmixpipe.w:6286
		case lKnownPhys:
			if data.z.o>>32&0xffff0000 != 0 {
				pc = lBadFetch
				continue
			}
			if mx.Icache == nil {

//line mmixpipe.w:6319
				if mx.memLock != nil {
					return mx.wait(self, 1)
				}
				setLock(&mx.memLocker, &mx.memLock)
				mx.startup(&mx.memLocker, mx.memAddrTime+mx.memReadTime)
				{
					addr := data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-(mx.busWords<<3)))
					mx.fetched[0] = mx.memRead(addr)
					for j = 1; j < mx.busWords; j++ {
						mx.fetched[j] = mx.memHash[mx.lastH].chunk[int(Tetra(addr)&0xffff)>>3+j]
					}
				}
				mx.fetchLo = int(Tetra(data.z.o)>>3) & (mx.busWords - 1)
				mx.fetchHi = mx.busWords
				data.state = fetchReady
				return mx.wait(self, mx.memAddrTime+mx.memReadTime)

//line mmixpipe.w:6293
			}
			if mx.Icache.lock != nil {
				data.state = itHit
				if mx.waitOrPass(self, 1) {
					pc = lPassit
					continue
				}
				return false
			}
			if j = getReader(mx.Icache); j < 0 {
				data.state = itHit
				if mx.waitOrPass(self, 1) {
					pc = lPassit
					continue
				}
				return false
			}
			mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)

//line mmixpipe.w:6232
			q = mx.cacheSearch(mx.Icache, data.z.o)
			if q != nil {
				q = mx.useAndFix(mx.Icache, q)

//line mmixpipe.w:6251
				if data.i != prego {
					for j = 0; j < mx.Icache.bb>>3; j++ {
						mx.fetched[j] = q.data[j]
					}
					mx.fetchLo = int(Tetra(mx.instPtr.o)&Tetra(mx.Icache.bb-1)) >> 3
					mx.fetchHi = mx.Icache.bb >> 3
				}

//line mmixpipe.w:6236
				data.state = fetchReady
			} else {
				data.state = iHitAndMiss
			}

//line mmixpipe.w:6312
			if mx.waitOrPass(self, mx.Icache.accessTime) {
				pc = lPassit
				continue
			}
			return false

//line mmixpipe.w:6343
		case fetchSt + itMiss:
			if mx.ITcache.filler.next != nil {
				if data.i == prego {
					pc = lFinEx
					continue
				}
				return mx.wait(self, 1)
			}
			if mx.noHardwarePT || mx.pageF != 0 {

//line mmixpipe.w:6492
				if mx.cacheSearch(mx.ITcache, mx.transKey(mx.instPtr.o)) != nil {
					pc = lNewFetch
					continue
				}
				data.interrupt |= fBit
				mx.sleepy = true
				pc = lSwymOne
				continue

//line mmixpipe.w:6353
			}
			p = mx.allocSlot(mx.ITcache, mx.transKey(data.y.o))
			if p == nil { // 이런, 결국 있었다
				if data.i == prego {
					pc = lFinEx
				} else {
					pc = lNewFetch
				}
				continue
			}
			data.ptrB, mx.ITcache.fillerCtl.ptrB = p, p
			mx.ITcache.fillerCtl.y.o = data.y.o
			setLock(self, &mx.ITcache.fillLock)
			mx.startup(&mx.ITcache.filler, 1)
			data.state = gotIT
			if data.i == prego {
				pc = lFinEx
				continue
			}
			return mx.sleep(self)

//line mmixpipe.w:6375
		case fetchSt + gotIT:
			releaseLock(self, &mx.ITcache.fillLock)
			if Tetra(data.z.o)&(pxBit>>protOffset) == 0 {
				pc = lBadFetch
				continue
			}
			data.z.o = mx.physAddr(data.y.o, data.z.o)
			fallthrough
		case lFetchRetry:
			data.state = itHit
			if data.i == prego {
				pc = lFinEx
			} else {
				pc = lKnownPhys
			}
			continue
		case fetchSt + iHitAndMiss:

//line mmixpipe.w:6400
			if mx.Icache.filler.next != nil ||
				(mx.Scache != nil && mx.Scache.lock != nil) || (mx.Scache == nil && mx.memLock != nil) {
				pc = lFetchRetry
				continue
			}
			q = mx.allocSlot(mx.Icache, data.z.o)
			if q == nil {
				pc = lFetchRetry
				continue
			}
			if mx.Scache != nil {
				setLock(&mx.Icache.filler, &mx.Scache.lock)
			} else {
				setLock(&mx.Icache.filler, &mx.memLock)
			}
			setLock(self, &mx.Icache.fillLock)
			data.ptrB, mx.Icache.fillerCtl.ptrB = q, q
			mx.Icache.fillerCtl.z.o = data.z.o
			if mx.Scache != nil {
				mx.startup(&mx.Icache.filler, mx.Scache.accessTime)
			} else {
				mx.startup(&mx.Icache.filler, mx.memAddrTime)
			}
			data.state = gotOne
			if data.i == prego {
				pc = lFinEx
				continue
			}
			return mx.sleep(self)

//line mmixpipe.w:6437
		case lBadFetch:
			if data.i == prego {
				pc = lFinEx
				continue
			}
			data.interrupt |= pxBit
			fallthrough
		case lSwymOne:
			mx.fetched[0] = SWYM<<24<<32 | SWYM<<24
			pc = lFetchOne
			continue
		case fetchSt + gotOne:
			mx.fetched[0] = data.x.o // 새 캐시 데이터의 ``미리 보기''
			fallthrough
		case lFetchOne:
			mx.fetchLo, mx.fetchHi = 0, 1
			data.state = fetchReady
			fallthrough
		case fetchSt + fetchReady:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if data.i == prego {
				pc = lFinEx
				continue
			}

//line mmixpipe.w:6468
			newFetch := false
			for j = 0; j < mx.fetchMax; j++ {
				newTail := mx.prevFetch(mx.tail)
				if newTail == mx.head {
					break // 가져오기 버퍼가 차 있다
				}

//line mmixpipe.w:6508
				mx.tail.loc = mx.instPtr.o
				if mx.instPtr.o&4 != 0 {
					mx.tail.inst = Tetra(mx.fetched[mx.fetchLo])
					mx.fetchLo++
				} else {
					mx.tail.inst = Tetra(mx.fetched[mx.fetchLo] >> 32)
				}

//line mmixpipe.w:6517
				mx.tail.interrupt = data.interrupt
				i = int(mx.tail.inst >> 24)
				if i >= RESUME && i <= SYNC && mx.tail.inst&badInstMask[i-RESUME] != 0 {
					mx.tail.interrupt |= bBit
				}
				mx.tail.noted = false
				if mx.instPtr.o == mx.breakpoint {
					mx.breakpointHit = true
				}

//line mmixpipe.w:6475
				mx.tail = newTail
				if mx.sleepy {
					mx.sleepy = false
					return mx.sleep(self)
				}
				mx.instPtr.o += 4
				if mx.fetchLo == mx.fetchHi {
					newFetch = true
					break
				}
			}
			if newFetch {
				pc = lNewFetch
				continue
			}

//line mmixpipe.w:6465
			return mx.wait(self, 1)

//line mmixpipe.w:2512

//line mmixpipe.w:2624
		case lSwitch1:
			pc = stage1St + label(data.state)
			continue
		case stage1St + 0:

//line mmixpipe.w:2642
			j = 0
			if data.y.p != nil {
				j++
				if data.y.p.known {
					data.y.o, data.y.p = data.y.p.o, nil
				} else {
					j += 10
				}
			}
			if data.z.p != nil {
				j++
				if data.z.p.known {
					data.z.o, data.z.p = data.z.p.o, nil
				} else {
					j += 10
				}
			}

//line mmixpipe.w:2668
			if data.b.p != nil {
				if data.needB {
					j++
				}
				if data.b.p.known {
					data.b.o, data.b.p = data.b.p.o, nil
				} else if data.needB {
					j += 10
				}
			}
			if data.ra.p != nil {
				if data.needRA {
					j++
				}
				if data.ra.p.known {
					data.ra.o, data.ra.p = data.ra.p.o, nil
				} else if data.needRA {
					j += 10
				}
			}

//line mmixpipe.w:2660
			if j < 10 {
				data.state = 1
			}
			if j != 0 {
				return mx.wait(self, 1) // 그렇지 않으면 |case 1|로 흘러내린다
			}

//line mmixpipe.w:2629
			fallthrough
		case stage1St + 1:

//line mmixpipe.w:2697
			switch data.i {

//line mmixpipe.w:2797
			case set:
				data.x.o = data.z.o

//line mmixpipe.w:2803
			case or:
				data.x.o = data.y.o | data.z.o
			case orn:
				data.x.o = data.y.o | ^data.z.o
			case nor:
				data.x.o = ^(data.y.o | data.z.o)
			case and:
				data.x.o = data.y.o & data.z.o
			case andn:
				data.x.o = data.y.o &^ data.z.o
			case nand:
				data.x.o = ^(data.y.o & data.z.o)
			case xor:
				data.x.o = data.y.o ^ data.z.o
			case nxor:
				data.x.o = data.y.o ^ ^data.z.o

//line mmixpipe.w:2825
			case addu:
				if data.op&0xf8 == 0x28 {
					data.x.o = data.y.o<<(1+((data.op>>1)&0x3)) + data.z.o
				} else {
					data.x.o = data.y.o + data.z.o
				}
			case subu:
				data.x.o = data.y.o - data.z.o

//line mmixpipe.w:2840
			case add:
				data.x.o = data.y.o + data.z.o
				if (data.y.o^data.z.o)&signBit == 0 && (data.y.o^data.x.o)&signBit != 0 {
					data.interrupt |= vBit
				}
			case sub:
				data.x.o = data.y.o - data.z.o
				if (data.x.o^data.z.o)&signBit == 0 && (data.y.o^data.x.o)&signBit != 0 {
					data.interrupt |= vBit
				}

//line mmixpipe.w:2859
			case shlu:
				data.x.o = data.y.o << shiftAmt(data.z.o)
				data.i = sh
			case shl:
				data.x.o = data.y.o << shiftAmt(data.z.o)
				data.i = sh
				if mmixarith.ShiftRight(data.x.o, shiftAmt(data.z.o), false) != data.y.o {
					data.interrupt |= vBit
				}
			case shru:
				data.x.o = mmixarith.ShiftRight(data.y.o, shiftAmt(data.z.o), true)
				data.i = sh
			case shr:
				data.x.o = mmixarith.ShiftRight(data.y.o, shiftAmt(data.z.o), false)
				data.i = sh

//line mmixpipe.w:2889
			case mux:
				data.x.o = data.y.o&data.b.o | data.z.o&^data.b.o

//line mmixpipe.w:2897
			case cmp:
				if int64(data.y.o) < int64(data.z.o) {
					data.x.o = negOne
				} else if data.y.o != data.z.o {
					data.x.o = 1
				}
			case cmpu:
				if data.y.o < data.z.o {
					data.x.o = negOne
				} else if data.y.o != data.z.o {
					data.x.o = 1
				}

//line mmixpipe.w:7459
			case mulu:
				data.a.o, data.x.o = bits.Mul64(data.y.o, data.z.o)

//line mmixpipe.w:7489
				{
					aux := data.z.o
					for j = mul0; aux != 0; j++ {
						aux >>= 8
					}
					data.i = j // |j|는 |mul0|이나 |mul1|이나 \dots~|mul8|이다
				}

//line mmixpipe.w:7462
			case mul:
				{
					x, overflow := mmixarith.SignedMult(data.y.o, data.z.o)
					data.x.o = x
					if overflow {
						data.interrupt |= vBit
					}
				}

//line mmixpipe.w:7489
				{
					aux := data.z.o
					for j = mul0; aux != 0; j++ {
						aux >>= 8
					}
					data.i = j // |j|는 |mul0|이나 |mul1|이나 \dots~|mul8|이다
				}

//line mmixpipe.w:7471
			case divu:
				data.x.o, data.a.o = mmixarith.Div(data.b.o, data.y.o, data.z.o)
				data.i = div
			case div:
				if data.z.o == 0 {
					data.interrupt |= dBit
					data.a.o = data.y.o
					data.i = set // 0으로 나누기는 파이프라인에서 기다릴 필요가 없다
				} else {
					q, r, overflow := mmixarith.SignedDiv(data.y.o, data.z.o)
					data.x.o = q
					if overflow {
						data.interrupt |= vBit
					}
					data.a.o = r
				}

//line mmixpipe.w:7503
			case sadd:
				data.x.o = Octa(bits.OnesCount64(data.y.o &^ data.z.o))
			case mor:
				data.x.o = mmixarith.BoolMult(data.y.o, data.z.o, data.op&0x2 != 0)
			case bdif:
				data.x.o = mmixarith.ByteDiff(data.y.o, data.z.o)
			case wdif:
				data.x.o = mmixarith.WydeDiff(data.y.o, data.z.o)
			case tdif:
				if data.y.o>>32 > data.z.o>>32 {
					data.x.o = (data.y.o>>32 - data.z.o>>32) << 32
				}
				if Tetra(data.y.o) > Tetra(data.z.o) {
					data.x.o |= Octa(Tetra(data.y.o) - Tetra(data.z.o))
				}
			case odif:
				if data.y.o > data.z.o {
					data.x.o = data.y.o - data.z.o
				}

//line mmixpipe.w:7535
			case zset:
				if registerTruth(data.y.o, data.op) != 0 {
					data.x.o = data.z.o
				} // 그렇지 않으면 |data.x.o|는 이미 0이다
				pc = lFinEx
				continue
			case cset:
				if registerTruth(data.y.o, data.op) != 0 {
					data.x.o, data.b.p = data.z.o, nil
				} else if data.b.p == nil {
					data.x.o = data.b.o
				} else {
					data.state = 0
					data.needB = true
					pc = lSwitch1
					continue
				}

//line mmixpipe.w:7591
			case fadd, fsub, fmul, fdiv, fsqrt, fint, fix:
				entry := 0 // |fin_bflot|이면 0, |fin_uflot|이면 1, |fin_flot|이면 2
				mx.setRound(data)
				switch data.i {

//line mmixpipe.w:7622
				case fadd:
					data.x.o, mx.exceptions = mmixarith.FPlus(data.y.o, data.z.o, mx.curRound)
				case fsub:
					data.a.o = data.z.o
					if mmixarith.FComp(data.z.o, 0) != 2 {
						data.a.o ^= signBit
					}
					data.x.o, mx.exceptions = mmixarith.FPlus(data.y.o, data.a.o, mx.curRound)
					data.i = fadd // 덧셈의 파이프라인 시간을 쓴다
				case fmul:
					data.x.o, mx.exceptions = mmixarith.FMult(data.y.o, data.z.o, mx.curRound)
				case fdiv:
					data.x.o, mx.exceptions = mmixarith.FDivide(data.y.o, data.z.o, mx.curRound)
				case fsqrt:
					data.x.o, mx.exceptions = mmixarith.FRoot(data.z.o, mx.roundMode(data.y.o))
					entry = 1
				case fint:
					data.x.o, mx.exceptions = mmixarith.FIntegerize(data.z.o, mx.roundMode(data.y.o))
					entry = 1
				case fix:
					data.x.o, mx.exceptions = mmixarith.FixIt(data.z.o, mx.roundMode(data.y.o))
					if data.op&0x2 != 0 {
						mx.exceptions &^= wBit // 부호 없는 경우는 넘치지 않는다
					}
					entry = 2

//line mmixpipe.w:7596
				}
				if entry <= 0 && isSubnormal(data.y.o) {
					data.denin = mx.deninPenalty
				}
				if entry <= 1 && isSubnormal(data.x.o) {
					data.denout = mx.denoutPenalty
				}
				if isSubnormal(data.z.o) {
					data.denin = mx.deninPenalty
				}
				data.interrupt |= Tetra(mx.exceptions)
				if isTrivial(data.y.o) || isTrivial(data.z.o) {
					pc = lFinEx
					continue
				}
				if data.i == fsqrt && data.z.o&signBit != 0 {
					pc = lFinEx
					continue
				}
			case flot:
				mx.setRound(data)
				data.x.o, mx.exceptions = mmixarith.FloatIt(data.z.o, mx.roundMode(data.y.o),
					data.op&0x2 != 0, data.op&0x4 != 0)
				data.interrupt |= Tetra(mx.exceptions)

//line mmixpipe.w:7660
			case feps:
				j = mmixarith.FEpsComp(data.y.o, data.z.o, data.b.o, data.op != FEQLE)
				if j == 2 {
					data.i = fcmp
				} else if isSubnormal(data.y.o) || isSubnormal(data.z.o) {
					data.denin = mx.deninPenalty
				}
				switch {
				case data.op == FUNE:
					if j == 2 {
						data.x.o = 1
					}
				case data.op == FEQLE:

//line mmixpipe.w:7701
					if j == 1 {
						data.x.o = 1
					} else if j == 2 {
						data.interrupt |= iBit
					}

//line mmixpipe.w:7674
				case data.op == FCMPE && j != 0:
					if j == 2 {
						data.interrupt |= iBit
					}
				default:

//line mmixpipe.w:7693
					j = mmixarith.FComp(data.y.o, data.z.o)
					if j < 0 {
						data.x.o = negOne
					} else {

//line mmixpipe.w:7701
						if j == 1 {
							data.x.o = 1
						} else if j == 2 {
							data.interrupt |= iBit
						}

//line mmixpipe.w:7698
					}

//line mmixpipe.w:7680
				}
			case fcmp:

//line mmixpipe.w:7693
				j = mmixarith.FComp(data.y.o, data.z.o)
				if j < 0 {
					data.x.o = negOne
				} else {

//line mmixpipe.w:7701
					if j == 1 {
						data.x.o = 1
					} else if j == 2 {
						data.interrupt |= iBit
					}

//line mmixpipe.w:7698
				}

//line mmixpipe.w:7683
			case funeq:
				want := 0
				if data.op == FUN {
					want = 2
				}
				if mmixarith.FComp(data.y.o, data.z.o) == want {
					data.x.o = 1
				}

//line mmixpipe.w:7714
			case frem:
				if isTrivial(data.y.o) || isTrivial(data.z.o) {
					data.x.o, mx.exceptions = mmixarith.FRemStep(data.y.o, data.z.o, 2500)
					data.interrupt |= Tetra(mx.exceptions)
					pc = lFinEx
					continue
				}
				if self.succ.next != nil {
					return mx.wait(self, 1)
				}
				data.interim = true
				j = 1
				if isSubnormal(data.y.o) || isSubnormal(data.z.o) {
					j += mx.deninPenalty
				}
				mx.passAfter(self, j)
				pc = lPassit
				continue

//line mmixpipe.w:5354
			case preld, prest, prego:
				{
					bb := mx.Dcache.bb
					if data.i == prego {
						bb = mx.Icache.bb
					}
					data.z.o += Octa(int(data.xx) & -bb) // (덧셈기가 넉넉히 빠르기를 바란다)
				}
				fallthrough
			case ld, ldunc, ldvts, st, pst, syncd, syncid:

//line mmixpipe.w:5374
				data.y.o += data.z.o
				data.state = ldStLaunch
				pc = lSwitch1
				continue

//line mmixpipe.w:5365
			case ldptp, ldpte:
				if data.y.o>>32 != 0 {

//line mmixpipe.w:5374
					data.y.o += data.z.o
					data.state = ldStLaunch
					pc = lSwitch1
					continue

//line mmixpipe.w:5368
				}
				data.x.o, data.x.known = 0, true
				pc = lDie // 페이지 테이블 실패
				continue

//line mmixpipe.w:3256
			case br, pbr:
				j = registerTruth(data.b.o, data.op)
				if j != 0 {
					data.goLoc.o = data.z.o
				} else {
					data.goLoc.o = data.y.o
				}
				if (j != 0) == (data.i == pbr) {
					mx.bpGoodStat++
				} else { // 아이고, 잘못 예측했다
					mx.bpBadStat++

//line mmixpipe.w:3315
					i = mx.issuedBetween(data, mx.cool)
					if i < mx.deissues {
						pc = lDie
						continue
					}
					mx.deissues = i
					mx.oldTail, mx.tail = mx.head, mx.head // 가져오기 버퍼를 비운다
					mx.resuming = 0

//line mmixpipe.w:6096
					if mx.fetchCo.lockloc != nil {
						*mx.fetchCo.lockloc = nil
						mx.fetchCo.lockloc = nil
					}
					mx.unschedule(&mx.fetchCo)
					mx.startup(&mx.fetchCo, 1)

//line mmixpipe.w:3324
					mx.instPtr = spec{o: data.goLoc.o}
					if data.loc&signBit == 0 {
						if mx.instPtr.o&signBit != 0 {
							data.interrupt |= pBit
						} else {
							data.interrupt &^= pBit
						}
					}
					if mx.bpTable != nil {
						mx.bpTable[data.x.o>>32] = int8(data.x.o) // 이것이 넣었어야 할 값이다
						if mx.verbose&showPredBit != 0 {
							mx.printf(" mispredicted ")
							mx.printOcta(data.loc)
							l := Tetra(data.x.o)
							mx.printf("; bp[%x]=%d\n", Tetra(data.x.o>>32),
								int32(l-(l&Tetra(mx.bpNpower))<<1))
						}
					}
					if j != 0 {
						mx.coolHist = data.hist<<1 + 1
					} else {
						mx.coolHist = data.hist << 1
					}

//line mmixpipe.w:3268
				}
				pc = lFinEx
				continue

//line mmixpipe.w:6713
			case trap:
				data.interrupt |= fBit
				data.a.o = data.b.o
				pc = lFinEx
				continue
			case trip:
				data.interrupt |= hBit
				data.a.o = data.b.o
				pc = lFinEx
				continue

//line mmixpipe.w:7089
			case resume, resum:
				if data.xx != resumeTrans {
					pc = lFinEx
					continue
				}
				if Tetra(data.b.o)>>24 == SWYM {
					data.ptrA = mx.ITcache
				} else {
					data.ptrA = mx.DTcache
				}
				data.state = doResumeTrans
				data.z.o = data.z.o&^mx.pageMask + data.z.o&7
				data.z.o &= 0xffff<<32 | 0xffffffff
				pc = lResumeTrans
				continue

//line mmixpipe.w:7130
			case noop:
				if data.interrupt&fBit != 0 {
					pc = lEmulateVirt
					continue
				}
				fallthrough
			case incrl, unsave:
				pc = lFinEx
				continue
			case jmp, pushj:
				data.goLoc.o = data.z.o
				pc = lFinEx
				continue
			case sav:
				if !data.memX {
					pc = lFinEx
					continue
				}
				fallthrough
			case incgamma, save:
				data.i = st
				pc = lSwitch1
				continue
			case decgamma, unsav:
				data.i = ld
				pc = lSwitch1
				continue

//line mmixpipe.w:7166
			case get:
				if data.zz >= 21 || data.zz == rK || data.zz == rQ {
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}
					data.z.o = mx.g[data.zz].o
				}
				data.x.o = data.z.o
				pc = lFinEx
				continue

//line mmixpipe.w:7181
			case put:
				if data.xx == 8 || (data.xx >= 15 && data.xx <= 20) {
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}
					switch data.xx {
					case rV:

//line mmixpipe.w:4824
						{
							rv := data.z.o
							mx.pageF = int(rv & 7)
							mx.pageBad = mx.pageF > 1
							mx.pageN = int(rv & 0x1ff8)
							rv >>= 13
							mx.pageR = int(rv & 0x7ffffff)
							rv >>= 27
							mx.pageS = int(rv & 0xff)
							if mx.pageS < 13 || mx.pageS > 48 {
								mx.pageBad = true
							} else {
								mx.pageMask = 1<<mx.pageS - 1
							}
							mx.pageB[4] = int(rv>>8) & 0xf
							mx.pageB[3] = int(rv>>12) & 0xf
							mx.pageB[2] = int(rv>>16) & 0xf
							mx.pageB[1] = int(rv>>20) & 0xf
						}

//line mmixpipe.w:7189
					case rQ:
						mx.newQ |= data.z.o &^ mx.g[rQ].o
						data.z.o |= mx.newQ
					case rL:
						if data.z.o>>32 != 0 {
							data.z.o = Octa(Tetra(mx.g[rL].o))
						} else if Tetra(data.z.o) > Tetra(mx.g[rL].o) {
							data.z.o = Octa(Tetra(mx.g[rL].o))
						}
					case rG:

//line mmixpipe.w:7215
						if data.z.o>>32 != 0 || Tetra(data.z.o) >= 256 ||
							Tetra(data.z.o) < Tetra(mx.g[rL].o) || Tetra(data.z.o) < 32 {
							data.interrupt |= bBit
							data.z.o = mx.g[rG].o
						} else if Tetra(data.z.o) < Tetra(mx.g[rG].o) {
							data.interim = true // 가로막힐 수 있다
							for j = 0; j < mx.commitMax; j++ {
								mx.g[rG].o--
								mx.g[Tetra(mx.g[rG].o)].o = 0
								if Tetra(data.z.o) == Tetra(mx.g[rG].o) {
									break
								}
							}
							if j == mx.commitMax {
								if !mx.tryingToInterrupt {
									return mx.wait(self, 1)
								}
							} else {
								data.interim = false
							}
						}

//line mmixpipe.w:7200
					}
				} else if data.xx == rA && (data.z.o>>32 != 0 || Tetra(data.z.o) >= 0x40000) {
					data.interrupt |= bBit
					data.z.o &= 0x3ffff
				}
				data.x.o = data.z.o
				pc = lFinEx
				continue

//line mmixpipe.w:7243
			case goOp:
				data.x.o = data.goLoc.o

//line mmixpipe.w:7254
				data.goLoc.o = data.y.o + data.z.o
				if data.goLoc.o&signBit != 0 && data.loc&signBit == 0 {
					data.interrupt |= pBit
				}
				data.goLoc.known = true
				pc = lFinEx
				continue

//line mmixpipe.w:7246
			case pop:
				data.x.o = data.y.o
				data.y.o = data.b.o // rJ를 |y| 필드로 옮긴다
				fallthrough
			case pushgo:

//line mmixpipe.w:7254
				data.goLoc.o = data.y.o + data.z.o
				if data.goLoc.o&signBit != 0 && data.loc&signBit == 0 {
					data.interrupt |= pBit
				}
				data.goLoc.known = true
				pc = lFinEx
				continue

//line mmixpipe.w:7849
			case sync:
				switch data.zz {
				case 0, 4:
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}
					mx.halted = data.zz != 0
					pc = lFinEx
					continue
				case 2, 3:

//line mmixpipe.w:7884
					for k := data; k != mx.hot; {
						k = mx.nextCtl(k)
						if k.owner != nil && (k.i == ld || k.i == ldunc || k.i == pst) {
							return mx.wait(self, 1)
						}
					}

//line mmixpipe.w:7860
					releaseLock(self, &mx.dispatchLock)
					fallthrough
				case 1:
					data.x.addr = 0
					pc = lFinEx
					continue
				case 5:
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}

//line mmixpipe.w:7986
					if self.lockloc != nil {
						*self.lockloc = nil
						self.lockloc = nil
					}

//line mmixpipe.w:8004
					if mx.writeHead != mx.writeTail {
						if mx.speedLock == nil {
							setLock(self, &mx.speedLock)
						}
						return mx.wait(self, 1)
					}

//line mmixpipe.w:7991
					if mx.cleanCo.next != nil || mx.cleanLock != nil {
						return mx.wait(self, 1)
					}
					setLock(self, &mx.cleanLock)
					mx.cleanCtl.i = sync
					mx.cleanCtl.state = 0
					mx.cleanCtl.x.o &= 0xffffffff
					mx.startup(&mx.cleanCo, 1)
					data.state = 13
					data.interim = true
					return mx.wait(self, 1)

//line mmixpipe.w:7871
				case 6:
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}

//line mmixpipe.w:7894
					if mx.DTcache.lock != nil {
						return mx.wait(self, 1)
					}
					if j = getReader(mx.DTcache); j < 0 {
						return mx.wait(self, 1)
					}
					mx.startup(&mx.DTcache.reader[j], mx.DTcache.accessTime)
					setLock(self, &mx.DTcache.lock)
					zapCache(mx.DTcache)
					data.state = 10
					return mx.wait(self, mx.DTcache.accessTime)

//line mmixpipe.w:7876
				case 7:
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}

//line mmixpipe.w:7907
					if mx.Icache == nil {
						data.state = 11
						pc = lSwitch1
						continue
					}
					if mx.Icache.lock != nil {
						return mx.wait(self, 1)
					}
					if j = getReader(mx.Icache); j < 0 {
						return mx.wait(self, 1)
					}
					mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)
					setLock(self, &mx.Icache.lock)
					zapCache(mx.Icache)
					data.state = 11
					return mx.wait(self, mx.Icache.accessTime)

//line mmixpipe.w:7881
				}

//line mmixpipe.w:2701
			}

//line mmixpipe.w:2715
			data.state = 3
			if data.i <= maxPipeOp {
				s := &mx.pipeSeq[data.i]
				j = int(s[0]) + data.denin
				if s[1] != 0 {
					data.state = 2 // 단계가 하나보다 많다
				} else {
					j += data.denout
				}
				if j > 1 {
					return mx.wait(self, j-1)
				}
			}
			pc = lSwitch1
			continue

//line mmixpipe.w:2632
		case lPassData:

//line mmixpipe.w:2737
			if self.succ.next != nil {
				return mx.wait(self, 1) // 다음 단계가 차 있으면 멈춘다
			}
			{
				s := &mx.pipeSeq[data.i]
				j = int(s[self.stage])
				if s[self.stage+1] == 0 {
					j += data.denout
					data.state = 3 // 다음 단계가 마지막이다
				}
				mx.passAfter(self, j)
			}
			fallthrough
		case lPassit:
			self.succ.ctl = data
			data.owner = self.succ
			return false

//line mmixpipe.w:2634
		case lFinEx:

//line mmixpipe.w:2920
			if data.renX {
				data.x.known = true
			} else if data.memX {
				data.x.known = true
				if (data.x.addr>>32)&0xffff0000 == 0 {
					data.x.addr &^= 7
				}
			}
			if data.renA {
				data.a.known = true
			}
			if data.loc&signBit != 0 {
				data.ra.o &^= 0xffffffff // 운영체제에서는 트립을 허용하지 않는다
			}
			if data.interrupt&0xffff != 0 {

//line mmixpipe.w:6575
				if data.interrupt&0xff != 0 && isLoadStore(data.i) {
					pc = lState5
					continue
				}
				j = int(data.interrupt & 0xff00)
				data.interrupt -= Tetra(j)
				if j&(uBit+xBit) == uBit && Tetra(data.ra.o)&uBit == 0 {
					j &^= uBit
				}
				data.arithExc = (Tetra(j) &^ Tetra(data.ra.o)) >> 8
				if Tetra(j)&Tetra(data.ra.o) != 0 {

//line mmixpipe.w:6599
					i = mx.issuedBetween(data, mx.cool)
					if i < mx.deissues {
						pc = lDie
						continue
					}
					mx.deissues = i
					mx.oldTail, mx.tail = mx.head, mx.head // 가져오기 버퍼를 비운다
					mx.resuming = 0

//line mmixpipe.w:6096
					if mx.fetchCo.lockloc != nil {
						*mx.fetchCo.lockloc = nil
						mx.fetchCo.lockloc = nil
					}
					mx.unschedule(&mx.fetchCo)
					mx.startup(&mx.fetchCo, 1)

//line mmixpipe.w:6608
					mx.coolHist = data.hist
					m := 16
					for i = j & int(Tetra(data.ra.o)); i&dBit == 0; i <<= 1 {
						m += 16
					}
					data.arithExc |= Tetra(j&^(0x10000>>(m>>4))) >> 8 // 일어난 트립은 사건으로 기록하지 않는다
					data.goLoc.o = Octa(m)
					mx.instPtr = spec{o: data.goLoc.o}
					data.interrupt |= hBit
					pc = lState4
					continue

//line mmixpipe.w:6587
				}
				if data.interrupt&0xff != 0 {
					pc = lState5
					continue
				}

//line mmixpipe.w:2936
			}
			fallthrough
		case lDie:
			data.owner = nil
			return true // 이 코루틴은 이제 사라진다

//line mmixpipe.w:5402
		case stage1St + ldStLaunch:
			if self.succ.next != nil {
				return mx.wait(self, 1) // 둘째 단계가 비어 있어야 한다
			}

//line mmixpipe.w:6173
			if data.i == prego {
				pc = lStartFetch
				continue
			}

//line mmixpipe.w:7764
			if data.i == ldvts {

//line mmixpipe.w:7769
				if data != mx.oldHot {
					return mx.wait(self, 1)
				}
				if mx.DTcache.lock != nil {
					return mx.wait(self, 1)
				}
				if j = getReader(mx.DTcache); j < 0 {
					return mx.wait(self, 1)
				}
				mx.startup(&mx.DTcache.reader[j], mx.DTcache.accessTime)
				data.z.o = data.y.o & 0x7
				p = mx.cacheSearch(mx.DTcache, data.y.o) // 주의: |transKey(data.y.o)|가 아니다
				if p != nil {
					data.x.o = data.x.o&^0xffffffff | 2
					c = mx.DTcache

//line mmixpipe.w:7794
					if Tetra(data.z.o) != 0 {
						p = mx.useAndFix(c, p)
						p.data[0] = p.data[0]&^0xffffffff | Octa(Tetra(p.data[0])&^7+Tetra(data.z.o))
					} else {
						p = mx.demoteAndFix(c, p)
						p.tag |= signBit // 태그를 무효로 만든다
					}

//line mmixpipe.w:7785
				}
				mx.passAfter(self, mx.DTcache.accessTime)
				pc = lPassit
				continue

//line mmixpipe.w:7766
			}

//line mmixpipe.w:5407
			if data.y.o&signBit != 0 {

//line mmixpipe.w:5562
				if data.loc&signBit == 0 {
					if data.i == syncd || data.i == syncid {
						pc = lSyncCheck
						continue
					}
					if data.i != preld && data.i != prest {
						data.interrupt |= nBit
					}
					pc = lFinEx
					continue
				}
				data.z.o = data.y.o - signBit
				if data.z.o>>32&0xffff0000 != 0 {

//line mmixpipe.w:5585
					switch data.i {
					case ldvts, preld, prest, prego, syncd, syncid:
						pc = lFinEx
						continue
					case ld, ldunc:
						if mx.memLock != nil {
							return mx.wait(self, 1)
						}
						if data.op < LDSF {
							i = (data.op & 0xf) >> 2
						} else if data.op < CSWAP {
							i = 2
						} else {
							i = 3
						}
						data.x.o = mx.specRead(data.z.o, i)
						pc = lMakeLdReady
						continue
					case pst:
						if (data.op ^ CSWAP) <= 1 {
							data.x.o = mx.specRead(data.z.o, 3)
							pc = lMakeLdReady
							continue
						}
						data.x.o = 0
						fallthrough
					case st:
						data.state = stReady
						mx.passAfter(self, 1)
						pc = lPassit
						continue
					}

//line mmixpipe.w:5576
				} else if data.i >= st && data.i <= syncid {
					data.state = stReady
					mx.passAfter(self, 1)
					pc = lPassit
					continue
				}

//line mmixpipe.w:5619
				if m := mx.writeSearch(data, data.z.o); m != nil {
					if m == &mx.dunno {
						data.state = dtHit
					} else {
						data.x.o, data.state = *m, ldReady
					}
					mx.passAfter(self, 1)
					pc = lPassit
					continue
				} else if mx.Dcache == nil {
					if mx.memLock != nil {
						return mx.wait(self, 1)
					}
					data.x.o = mx.memRead(data.z.o)
					pc = lMakeLdReady
					continue
				}
				if mx.Dcache.lock != nil {
					data.state = dtHit
					mx.passAfter(self, 1)
					pc = lPassit
					continue
				}
				if j = getReader(mx.Dcache); j < 0 {
					data.state = dtHit
					mx.passAfter(self, 1)
					pc = lPassit
					continue
				}
				mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)

//line mmixpipe.w:5498
				q = mx.cacheSearch(mx.Dcache, data.z.o)
				if q != nil {
					if data.i == ldunc {
						q = mx.demoteAndFix(mx.Dcache, q)
					} else {
						q = mx.useAndFix(mx.Dcache, q)
					}
					data.x.o = q.data[(Tetra(data.z.o)&Tetra(mx.Dcache.bb-1))>>3]
					data.state = ldReady
				} else {
					data.state = hitAndMiss
				}

//line mmixpipe.w:5650
				mx.passAfter(self, mx.Dcache.accessTime)
				pc = lPassit
				continue

//line mmixpipe.w:5409
			}
			if mx.pageBad {
				if data.i < preld || data.i == st || data.i == pst {
					data.interrupt |= prwBits(data)
				}
				pc = lFinEx
				continue
			}
			if mx.DTcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.DTcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.DTcache.reader[j], mx.DTcache.accessTime)

//line mmixpipe.w:5455
			p = mx.cacheSearch(mx.DTcache, mx.transKey(data.y.o))
			if mx.Dcache == nil || mx.Dcache.lock != nil || data.i >= st && data.i <= syncid {

//line mmixpipe.w:5539
				if p != nil {
					p = mx.useAndFix(mx.DTcache, p)
					data.z.o = p.data[0]

//line mmixpipe.w:5516
					if data.stackAlert {
						if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
							data.stackAlert = false
						} else {
							data.z.o = mx.g[rC].o // 스택 넘침에는 계속 페이지를 쓴다
						}
					}
					j = int(prwBits(data))
					if (Tetra(data.z.o)<<protOffset)&Tetra(j) != Tetra(j) {
						if data.i == syncd || data.i == syncid {
							pc = lSyncCheck
							continue
						}
						if data.i != preld && data.i != prest {
							data.interrupt |= Tetra(j) &^ (Tetra(data.z.o) << protOffset)
						}
						data.stackAlert = false
						pc = lFinEx
						continue
					}
					data.z.o = mx.physAddr(data.y.o, data.z.o)

//line mmixpipe.w:5543
					if data.i >= st && data.i <= syncid {
						data.state = stReady
					} else if m := mx.writeSearch(data, data.z.o); m != nil && m != &mx.dunno {
						data.x.o, data.state = *m, ldReady
					} else {
						data.state = dtHit
					}
				} else {
					data.state = dtMiss
				}
				mx.passAfter(self, mx.DTcache.accessTime)
				pc = lPassit
				continue

//line mmixpipe.w:5458
			}
			if j = getReader(mx.Dcache); j < 0 {

//line mmixpipe.w:5539
				if p != nil {
					p = mx.useAndFix(mx.DTcache, p)
					data.z.o = p.data[0]

//line mmixpipe.w:5516
					if data.stackAlert {
						if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
							data.stackAlert = false
						} else {
							data.z.o = mx.g[rC].o // 스택 넘침에는 계속 페이지를 쓴다
						}
					}
					j = int(prwBits(data))
					if (Tetra(data.z.o)<<protOffset)&Tetra(j) != Tetra(j) {
						if data.i == syncd || data.i == syncid {
							pc = lSyncCheck
							continue
						}
						if data.i != preld && data.i != prest {
							data.interrupt |= Tetra(j) &^ (Tetra(data.z.o) << protOffset)
						}
						data.stackAlert = false
						pc = lFinEx
						continue
					}
					data.z.o = mx.physAddr(data.y.o, data.z.o)

//line mmixpipe.w:5543
					if data.i >= st && data.i <= syncid {
						data.state = stReady
					} else if m := mx.writeSearch(data, data.z.o); m != nil && m != &mx.dunno {
						data.x.o, data.state = *m, ldReady
					} else {
						data.state = dtHit
					}
				} else {
					data.state = dtMiss
				}
				mx.passAfter(self, mx.DTcache.accessTime)
				pc = lPassit
				continue

//line mmixpipe.w:5461
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
			if p != nil {

//line mmixpipe.w:5480
				p = mx.useAndFix(mx.DTcache, p)
				data.z.o = p.data[0]

//line mmixpipe.w:5516
				if data.stackAlert {
					if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
						data.stackAlert = false
					} else {
						data.z.o = mx.g[rC].o // 스택 넘침에는 계속 페이지를 쓴다
					}
				}
				j = int(prwBits(data))
				if (Tetra(data.z.o)<<protOffset)&Tetra(j) != Tetra(j) {
					if data.i == syncd || data.i == syncid {
						pc = lSyncCheck
						continue
					}
					if data.i != preld && data.i != prest {
						data.interrupt |= Tetra(j) &^ (Tetra(data.z.o) << protOffset)
					}
					data.stackAlert = false
					pc = lFinEx
					continue
				}
				data.z.o = mx.physAddr(data.y.o, data.z.o)

//line mmixpipe.w:5483
				if m := mx.writeSearch(data, data.z.o); m == &mx.dunno {
					data.state = dtHit
				} else if m != nil {
					data.x.o, data.state = *m, ldReady
				} else if mx.Dcache.b+mx.Dcache.c > mx.pageS &&
					(Tetra(data.y.o)^Tetra(data.z.o))&Tetra((mx.Dcache.bb<<mx.Dcache.c)-(1<<mx.pageS)) != 0 {
					data.state = dtHit // 가짜 D-캐시 찾기
				} else {

//line mmixpipe.w:5498
					q = mx.cacheSearch(mx.Dcache, data.z.o)
					if q != nil {
						if data.i == ldunc {
							q = mx.demoteAndFix(mx.Dcache, q)
						} else {
							q = mx.useAndFix(mx.Dcache, q)
						}
						data.x.o = q.data[(Tetra(data.z.o)&Tetra(mx.Dcache.bb-1))>>3]
						data.state = ldReady
					} else {
						data.state = hitAndMiss
					}

//line mmixpipe.w:5492
				}
				mx.passAfter(self, max(mx.DTcache.accessTime, mx.Dcache.accessTime))
				pc = lPassit
				continue

//line mmixpipe.w:5465
			} else {
				data.state = dtMiss
			}

//line mmixpipe.w:5425
			mx.passAfter(self, mx.DTcache.accessTime)
			pc = lPassit
			continue
		case lMakeLdReady:
			setLock(&mx.memLocker, &mx.memLock)
			data.state = ldReady
			mx.startup(&mx.memLocker, mx.memAddrTime+mx.memReadTime)
			mx.passAfter(self, mx.memAddrTime+mx.memReadTime)
			pc = lPassit
			continue

//line mmixpipe.w:6638
		case lEmulateVirt:

//line mmixpipe.w:6621
			i = mx.issuedBetween(data, mx.cool)
			if i < mx.deissues {
				pc = lDie
				continue
			}
			mx.deissues = i
			mx.oldTail, mx.tail = mx.head, mx.head // 가져오기 버퍼를 비운다
			mx.resuming = 0

//line mmixpipe.w:6096
			if mx.fetchCo.lockloc != nil {
				*mx.fetchCo.lockloc = nil
				mx.fetchCo.lockloc = nil
			}
			mx.unschedule(&mx.fetchCo)
			mx.startup(&mx.fetchCo, 1)

//line mmixpipe.w:6630
			mx.coolHist = data.hist
			mx.instPtr.p = &mx.unknownSpec
			data.interrupt |= fBit

//line mmixpipe.w:6640
			fallthrough
		case lState4:
			data.state = 4
			if mx.dispatchLock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.dispatchLock)
			fallthrough
		case lState5:
			data.state = 5
			if data != mx.oldHot {
				return mx.wait(self, 1)
			}
			if data.interrupt&fBit != 0 && data.i != trap {
				mx.instPtr = spec{o: mx.g[rT].o}
				if isLoadStore(data.i) {
					mx.nullifying = true
				}
			}
			if data.interrupt&0xff != 0 {
				mx.g[rQ].o |= Octa(data.interrupt&0xff) << 32
				mx.newQ |= Octa(data.interrupt&0xff) << 32
				if mx.verbose&issueBit != 0 {
					mx.printf(" setting rQ=")
					mx.printOcta(mx.g[rQ].o)
					mx.printf("\n")
				}
			}
			pc = lDie
			continue

//line mmixpipe.w:7106
		case lResumeTrans:
			c = data.ptrA.(*cache)
			if c.lock != nil {
				return mx.wait(self, 1)
			}
			if c.filler.next != nil {
				return mx.wait(self, 1)
			}
			p = mx.allocSlot(c, mx.transKey(data.y.o))
			if p != nil {
				c.fillerCtl.ptrB = p
				c.fillerCtl.y.o = data.y.o
				c.fillerCtl.b.o = data.z.o
				c.fillerCtl.state = 1
				mx.schedule(&c.filler, c.accessTime, 1)
			}
			pc = lFinEx
			continue

//line mmixpipe.w:7925
		case stage1St + 10:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if mx.ITcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.ITcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.ITcache.reader[j], mx.ITcache.accessTime)
			setLock(self, &mx.ITcache.lock)
			zapCache(mx.ITcache)
			data.state = 3
			return mx.wait(self, mx.ITcache.accessTime)
		case stage1St + 11:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if mx.wbufLock != nil {
				return mx.wait(self, 1)
			}
			mx.writeHead, mx.writeCtl.state = mx.writeTail, 0 // 쓰기 버퍼를 지운다
			if mx.Dcache == nil {
				data.state = 12
				pc = lSwitch1
				continue
			}
			if mx.Dcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.Dcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
			setLock(self, &mx.Dcache.lock)
			zapCache(mx.Dcache)
			data.state = 12
			return mx.wait(self, mx.Dcache.accessTime)

//line mmixpipe.w:7968
		case stage1St + 12:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if mx.Scache == nil {
				pc = lFinEx
				continue
			}
			if mx.Scache.lock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.Scache.lock)
			zapCache(mx.Scache)
			data.state = 3
			return mx.wait(self, mx.Scache.accessTime)

//line mmixpipe.w:8015
		case stage1St + 13:
			if mx.cleanCo.next == nil {
				data.interim = false
				pc = lFinEx // 끝났다!
				continue
			}
			if mx.tryingToInterrupt {
				pc = lFinEx // 가로막기를 받아들인다
				continue
			}
			return mx.wait(self, 1)

//line mmixpipe.w:2513

//line mmixpipe.w:2762
		case lSwitch2:
			if data.b.p != nil && data.b.p.known {
				data.b.o, data.b.p = data.b.p.o, nil
			}
			pc = stage2St + label(data.state)
			continue
		case stage2St + 0:
			mx.panic(confusion("switch2"))
		case stage2St + 1:

//line mmixpipe.w:7734
			j = 1
			if data.i == frem {
				data.x.o, mx.exceptions = mmixarith.FRemStep(data.y.o, data.z.o, mx.fremMax)
				if mx.exceptions&eBit != 0 {
					data.y.o = data.x.o
					if mx.tryingToInterrupt && data == mx.oldHot {
						pc = lFinEx
						continue
					}
				} else {
					data.state = 3
					data.interim = false
					data.interrupt |= Tetra(mx.exceptions)
					if isSubnormal(data.x.o) {
						j += mx.denoutPenalty
					}
				}
				return mx.wait(self, j)
			}

//line mmixpipe.w:2772
			fallthrough
		case stage2St + 2:
			pc = lPassData
			continue
		case stage2St + 3:
			pc = lFinEx
			continue

//line mmixpipe.w:5681
		case lSquareOne:
			data.state = dtRetry
			if mx.DTcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.DTcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.DTcache.reader[j], mx.DTcache.accessTime)
			p = mx.cacheSearch(mx.DTcache, mx.transKey(data.y.o))
			if p != nil {
				p = mx.useAndFix(mx.DTcache, p)
				data.z.o = p.data[0]

//line mmixpipe.w:5516
				if data.stackAlert {
					if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
						data.stackAlert = false
					} else {
						data.z.o = mx.g[rC].o // 스택 넘침에는 계속 페이지를 쓴다
					}
				}
				j = int(prwBits(data))
				if (Tetra(data.z.o)<<protOffset)&Tetra(j) != Tetra(j) {
					if data.i == syncd || data.i == syncid {
						pc = lSyncCheck
						continue
					}
					if data.i != preld && data.i != prest {
						data.interrupt |= Tetra(j) &^ (Tetra(data.z.o) << protOffset)
					}
					data.stackAlert = false
					pc = lFinEx
					continue
				}
				data.z.o = mx.physAddr(data.y.o, data.z.o)

//line mmixpipe.w:5695
				if data.i >= st && data.i <= syncid {
					data.state = stReady
				} else {
					data.state = dtHit
				}
			} else {
				data.state = dtMiss
			}
			return mx.wait(self, mx.DTcache.accessTime)
		case stage2St + dtMiss:

//line mmixpipe.w:5716
			if mx.DTcache.filler.next != nil {
				if data.i == preld || data.i == prest {
					pc = lFinEx
				} else {
					pc = lSquareOne
				}
				continue
			}
			if mx.noHardwarePT || mx.pageF != 0 {
				if data.i == preld || data.i == prest {
					pc = lFinEx
				} else {
					pc = lEmulateVirt
				}
				continue
			}
			p = mx.allocSlot(mx.DTcache, mx.transKey(data.y.o))
			if p == nil {
				pc = lSquareOne
				continue
			}
			data.ptrB, mx.DTcache.fillerCtl.ptrB = p, p
			mx.DTcache.fillerCtl.y.o = data.y.o
			setLock(self, &mx.DTcache.fillLock)
			mx.startup(&mx.DTcache.filler, 1)
			data.state = gotDT
			if data.i == preld || data.i == prest {
				pc = lFinEx
				continue
			}
			return mx.sleep(self)

//line mmixpipe.w:5706
		case stage2St + gotDT:
			releaseLock(self, &mx.DTcache.fillLock)

//line mmixpipe.w:5516
			if data.stackAlert {
				if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
					data.stackAlert = false
				} else {
					data.z.o = mx.g[rC].o // 스택 넘침에는 계속 페이지를 쓴다
				}
			}
			j = int(prwBits(data))
			if (Tetra(data.z.o)<<protOffset)&Tetra(j) != Tetra(j) {
				if data.i == syncd || data.i == syncid {
					pc = lSyncCheck
					continue
				}
				if data.i != preld && data.i != prest {
					data.interrupt |= Tetra(j) &^ (Tetra(data.z.o) << protOffset)
				}
				data.stackAlert = false
				pc = lFinEx
				continue
			}
			data.z.o = mx.physAddr(data.y.o, data.z.o)

//line mmixpipe.w:5709
			if data.i >= st && data.i <= syncid {
				pc = lFinishStore
				continue
			}
			fallthrough // 그렇지 않으면 아래의 |ld_retry|로 흘러내린다

//line mmixpipe.w:5756
		case lLdRetry:
			data.state = dtHit
			if data.i == preld || data.i == prest {
				pc = lFinEx
				continue
			}

//line mmixpipe.w:5863
			if m := mx.writeSearch(data, data.z.o); m == &mx.dunno {
				return mx.wait(self, 1)
			} else if m != nil {
				data.x.o = *m
				data.state = ldReady
				return mx.wait(self, 1)
			}

//line mmixpipe.w:5763
			if data.z.o>>32&0xffff0000 != 0 || mx.Dcache == nil {
				pc = lAvoidD
				continue
			}
			if mx.Dcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.Dcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)

//line mmixpipe.w:5498
			q = mx.cacheSearch(mx.Dcache, data.z.o)
			if q != nil {
				if data.i == ldunc {
					q = mx.demoteAndFix(mx.Dcache, q)
				} else {
					q = mx.useAndFix(mx.Dcache, q)
				}
				data.x.o = q.data[(Tetra(data.z.o)&Tetra(mx.Dcache.bb-1))>>3]
				data.state = ldReady
			} else {
				data.state = hitAndMiss
			}

//line mmixpipe.w:5775
			return mx.wait(self, mx.Dcache.accessTime)
		case stage2St + hitAndMiss:
			if data.i == ldunc {
				pc = lAvoidD
				continue
			}

//line mmixpipe.w:5823
			if data.i == prest {
				bb, yl := mx.Dcache.bb, Tetra(data.y.o)
				if (int(data.xx) >= bb || yl&Tetra(bb-1) == 0) &&
					(yl+Tetra(int(data.xx)&(bb-1))+1)^yl >= Tetra(bb) {
					pc = lPrestSpan
					continue
				}
			}

//line mmixpipe.w:5787
			if mx.Dcache.filler.next != nil ||
				(mx.Scache != nil && mx.Scache.lock != nil) || (mx.Scache == nil && mx.memLock != nil) {
				pc = lLdRetry
				continue
			}
			q = mx.allocSlot(mx.Dcache, data.z.o)
			if q == nil {
				pc = lLdRetry
				continue
			}
			if mx.Scache != nil {
				setLock(&mx.Dcache.filler, &mx.Scache.lock)
			} else {
				setLock(&mx.Dcache.filler, &mx.memLock)
			}
			setLock(self, &mx.Dcache.fillLock)
			data.ptrB, mx.Dcache.fillerCtl.ptrB = q, q
			mx.Dcache.fillerCtl.z.o = data.z.o
			if mx.Scache != nil {
				mx.startup(&mx.Dcache.filler, mx.Scache.accessTime)
			} else {
				mx.startup(&mx.Dcache.filler, mx.memAddrTime)
			}
			data.state = ldReady
			if data.i == preld || data.i == prest {
				pc = lFinEx
				continue
			}
			return mx.sleep(self)

//line mmixpipe.w:5782
		case lAvoidD:

//line mmixpipe.w:5853
			if mx.memLock != nil {
				return mx.wait(self, 1)
			}
			setLock(&mx.memLocker, &mx.memLock)
			mx.startup(&mx.memLocker, mx.memAddrTime+mx.memReadTime)
			data.x.o = mx.memRead(data.z.o)
			data.state = ldReady
			return mx.wait(self, mx.memAddrTime+mx.memReadTime)

//line mmixpipe.w:5833
		case lPrestSpan:
			data.state = prestWin
			if data != mx.oldHot || mx.dLocker.next != nil {
				return mx.wait(self, 1)
			}
			if mx.Dcache.lock != nil {
				pc = lFinEx
				continue
			}
			q = mx.allocSlot(mx.Dcache, data.z.o) // |Dcache.filler|가 바빠도 괜찮다
			if q != nil {
				cleanBlock(mx.Dcache, q)
				q.tag = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-mx.Dcache.bb))
				setLock(&mx.dLocker, &mx.Dcache.lock)
				mx.startup(&mx.dLocker, mx.Dcache.copyInTime)
			}
			pc = lFinEx
			continue

//line mmixpipe.w:5879
		case stage2St + ldReady:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if data.i >= st {
				pc = lFinishStore
				continue
			}
			switch data.op >> 1 {
			case LDB >> 1, LDBU >> 1:
				j, i = int(Tetra(data.z.o)&0x7)<<3, 56
				data.x.o = mmixarith.ShiftRight(data.x.o<<j, i, data.op&0x2 != 0)
			case LDW >> 1, LDWU >> 1:
				j, i = int(Tetra(data.z.o)&0x6)<<3, 48
				data.x.o = mmixarith.ShiftRight(data.x.o<<j, i, data.op&0x2 != 0)
			case LDT >> 1, LDTU >> 1:
				j, i = int(Tetra(data.z.o)&0x4)<<3, 32
				data.x.o = mmixarith.ShiftRight(data.x.o<<j, i, data.op&0x2 != 0)

//line mmixpipe.w:5907
			case LDHT >> 1:
				if data.z.o&4 != 0 {
					data.x.o <<= 32
				}
				data.x.o &^= 0xffffffff
			case LDSF >> 1:
				if data.z.o&4 != 0 {
					data.x.o = data.x.o<<32 | data.x.o&0xffffffff
				}
				if h := Tetra(data.x.o >> 32); h&0x7f800000 == 0 && h&0x7fffff != 0 {
					data.x.o = mmixarith.LoadSF(h)
					data.state = 3
					return mx.wait(self, mx.deninPenalty)
				}
				data.x.o = mmixarith.LoadSF(Tetra(data.x.o >> 32))
			case LDPTP >> 1:
				if data.x.o&signBit == 0 || int(data.x.o&0x1ff8) != mx.pageN {
					data.x.o = 0
				} else {
					data.x.o &^= 1<<13 - 1
				}
			case LDPTE >> 1:
				if int(data.x.o&0x1ff8) != mx.pageN {
					data.x.o = 0
				} else {
					data.x.o = data.x.o&^mx.pageMask + data.x.o&0x7
				}
				data.x.o &= 0xffff<<32 | 0xffffffff
			case UNSAVE >> 1:

//line mmixpipe.w:7342
				if data.xx == 0 {
					data.a.o = data.x.o & (0xffffff<<32 | 0xffffffff) // 되살린 rA
					data.x.o >>= 56                                   // 되살린 rG
					if data.a.o>>32 != 0 || Tetra(data.a.o)&0xfffc0000 != 0 {
						data.a.o &= 0x3ffff
						data.interrupt |= bBit
					}
					if Tetra(data.x.o) < 32 {
						data.x.o = 32
						data.interrupt |= bBit
					}
				}

//line mmixpipe.w:5899
			}
			pc = lFinEx
			continue

//line mmixpipe.w:5942
		case lFinishStore:
			data.state = stReady
			switch data.i {
			case st, pst:

//line mmixpipe.w:5977
				data.x.addr = data.z.o
				if data.b.p != nil {
					return mx.wait(self, 1)
				}
				switch data.op >> 1 {
				case STUNC >> 1:
					data.i = stunc
					fallthrough
				default:
					data.x.o = data.b.o
				case STSF >> 1:
					mx.setRound(data)
					{
						h, exc := mmixarith.StoreSF(data.b.o, mx.curRound)
						mx.exceptions = exc
						data.b.o = Octa(h)<<32 | data.b.o&0xffffffff
					}
					data.interrupt |= Tetra(mx.exceptions)
					if h := Tetra(data.b.o >> 32); h&0x7f800000 == 0 && h&0x7fffff != 0 {

//line mmixpipe.w:6019
						if data.z.o&4 != 0 {
							data.x.o = data.x.o&^0xffffffff | data.b.o>>32
						} else {
							data.x.o = data.x.o&0xffffffff | data.b.o&^0xffffffff
						}

//line mmixpipe.w:5997
						data.state = 3
						return mx.wait(self, mx.denoutPenalty)
					}
					fallthrough
				case STHT >> 1:

//line mmixpipe.w:6019
					if data.z.o&4 != 0 {
						data.x.o = data.x.o&^0xffffffff | data.b.o>>32
					} else {
						data.x.o = data.x.o&0xffffffff | data.b.o&^0xffffffff
					}

//line mmixpipe.w:6003
				case STB >> 1, STBU >> 1:
					j, i = int(Tetra(data.z.o)&0x7)<<3, 56

//line mmixpipe.w:6026
					if data.op&2 == 0 {
						before := data.b.o
						after := mmixarith.ShiftRight(data.b.o<<i, i, false)
						if before != after {
							data.interrupt |= vBit
						}
					}
					{
						mask := mmixarith.ShiftRight(negOne<<i, j, true)
						data.b.o = mmixarith.ShiftRight(data.b.o<<i, j, true)
						data.x.o ^= mask & (data.x.o ^ data.b.o)
					}

//line mmixpipe.w:6006
				case STW >> 1, STWU >> 1:
					j, i = int(Tetra(data.z.o)&0x6)<<3, 48

//line mmixpipe.w:6026
					if data.op&2 == 0 {
						before := data.b.o
						after := mmixarith.ShiftRight(data.b.o<<i, i, false)
						if before != after {
							data.interrupt |= vBit
						}
					}
					{
						mask := mmixarith.ShiftRight(negOne<<i, j, true)
						data.b.o = mmixarith.ShiftRight(data.b.o<<i, j, true)
						data.x.o ^= mask & (data.x.o ^ data.b.o)
					}

//line mmixpipe.w:6009
				case STT >> 1, STTU >> 1:
					j, i = int(Tetra(data.z.o)&0x4)<<3, 32

//line mmixpipe.w:6026
					if data.op&2 == 0 {
						before := data.b.o
						after := mmixarith.ShiftRight(data.b.o<<i, i, false)
						if before != after {
							data.interrupt |= vBit
						}
					}
					{
						mask := mmixarith.ShiftRight(negOne<<i, j, true)
						data.b.o = mmixarith.ShiftRight(data.b.o<<i, j, true)
						data.x.o ^= mask & (data.x.o ^ data.b.o)
					}

//line mmixpipe.w:6012
				case CSWAP >> 1:

//line mmixpipe.w:6044
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}
					if data.x.o == mx.g[rP].o {
						data.a.o = 1 // |data.a.o|의 윗 테트라는 0이다
						data.x.o = data.b.o
					} else {
						mx.g[rP].o = data.x.o // |data.a.o|는 0이다
						if mx.verbose&issueBit != 0 {
							mx.printf(" setting rP=")
							mx.printOcta(mx.g[rP].o)
							mx.printf("\n")
						}
					}
					data.i = cswap // 겉모습만 바꾼다. 추적 출력에만 영향을 준다

//line mmixpipe.w:6014
				case SAVE >> 1:

//line mmixpipe.w:7440
					if data.interim {
						data.x.o = data.b.o
					} else {
						if data != mx.oldHot {
							return mx.wait(self, 1) // rA의 가장 뜨거운 값이 필요하다
						}
						data.x.o = Octa(Tetra(mx.g[rG].o)<<24)<<32 | Octa(Tetra(mx.g[rA].o))
						data.a.o = data.y.o
					}

//line mmixpipe.w:6016
				}

//line mmixpipe.w:5947
				pc = lFinEx
				continue
			case syncd:
				bb := 8192
				if mx.Dcache != nil {
					bb = mx.Dcache.bb
				}
				data.b.o = data.b.o&^0xffffffff | Octa(Tetra(bb))
				pc = lDoSyncd
				continue
			case syncid:
				bb := 8192
				if mx.Icache != nil {
					bb = mx.Icache.bb
				}
				if mx.Dcache != nil && mx.Dcache.bb < bb {
					bb = mx.Dcache.bb
				}
				data.b.o = data.b.o&^0xffffffff | Octa(Tetra(bb))
				pc = lDoSyncid
				continue
			}
			return true // 원본에서는 |switch|를 빠져나가 |terminate|에 이른다

//line mmixpipe.w:6395
		case stage2St + itMiss, stage2St + iHitAndMiss, stage2St + itHit, stage2St + fetchReady:
			pc = lSwitch0
			continue

//line mmixpipe.w:6674
		case stage2St + 4:
			pc = lState4
			continue
		case stage2St + 5:
			pc = lState5
			continue

//line mmixpipe.w:7803
		case stage2St + ldStLaunch:
			if mx.ITcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.ITcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.ITcache.reader[j], mx.ITcache.accessTime)
			p = mx.cacheSearch(mx.ITcache, data.y.o) // 주의: |transKey(data.y.o)|가 아니다
			if p != nil {
				data.x.o |= 1
				c = mx.ITcache

//line mmixpipe.w:7794
				if Tetra(data.z.o) != 0 {
					p = mx.useAndFix(c, p)
					p.data[0] = p.data[0]&^0xffffffff | Octa(Tetra(p.data[0])&^7+Tetra(data.z.o))
				} else {
					p = mx.demoteAndFix(c, p)
					p.tag |= signBit // 태그를 무효로 만든다
				}

//line mmixpipe.w:7816
			}
			data.state = 3
			return mx.wait(self, mx.ITcache.accessTime)

//line mmixpipe.w:8050
		case lDoSyncid:
			data.state = 30
			if data != mx.oldHot {
				return mx.wait(self, 1)
			}
			if mx.Icache == nil {
				data.state = syncidNext(data)
				pc = lSwitch2
				continue
			}

//line mmixpipe.w:8156
			if mx.Icache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.Icache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)
			setLock(self, &mx.Icache.lock)
			p = mx.cacheSearch(mx.Icache, data.z.o)
			if p != nil {
				mx.demoteAndFix(mx.Icache, p)
				cleanBlock(mx.Icache, p)
			}

//line mmixpipe.w:8061
			data.state = syncidNext(data)
			return mx.wait(self, mx.Icache.accessTime)
		case stage2St + 31:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}

//line mmixpipe.w:8004
			if mx.writeHead != mx.writeTail {
				if mx.speedLock == nil {
					setLock(self, &mx.speedLock)
				}
				return mx.wait(self, 1)
			}

//line mmixpipe.w:8069
			if (Tetra(data.b.o)-1)&^Tetra(data.y.o) < Tetra(data.xx) {
				data.interim = true
			}
			if mx.Dcache == nil {
				pc = lNextSync
				continue
			}

//line mmixpipe.w:8171
			if mx.Dcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.Dcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
			setLock(self, &mx.Dcache.lock)
			p = mx.cacheSearch(mx.Dcache, data.z.o)
			if p != nil {
				mx.demoteAndFix(mx.Dcache, p)
				cleanBlock(mx.Dcache, p)
			}

//line mmixpipe.w:8077
			data.state = 32
			return mx.wait(self, mx.Dcache.accessTime)
		case stage2St + 32:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if mx.Scache == nil {
				pc = lNextSync
				continue
			}

//line mmixpipe.w:8186
			if mx.Scache.lock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.Scache.lock)
			p = mx.cacheSearch(mx.Scache, data.z.o)
			if p != nil {
				mx.demoteAndFix(mx.Scache, p)
				cleanBlock(mx.Scache, p)
			}

//line mmixpipe.w:8089
			data.state = 35
			return mx.wait(self, mx.Scache.accessTime)

//line mmixpipe.w:8105
		case lDoSyncd:
			data.state = 33
			if data != mx.oldHot {
				return mx.wait(self, 1)
			}
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}

//line mmixpipe.w:8004
			if mx.writeHead != mx.writeTail {
				if mx.speedLock == nil {
					setLock(self, &mx.speedLock)
				}
				return mx.wait(self, 1)
			}

//line mmixpipe.w:8115
			if (Tetra(data.b.o)-1)&^Tetra(data.y.o) < Tetra(data.xx) {
				data.interim = true
			}
			if mx.Dcache == nil {
				if data.i == syncd {
					pc = lFinEx
				} else {
					pc = lNextSync
				}
				continue
			}

//line mmixpipe.w:8197
			if mx.cleanCo.next != nil || mx.cleanLock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.cleanLock)
			mx.cleanCtl.i = syncd
			mx.cleanCtl.state = 4
			mx.cleanCtl.x.o = mx.cleanCtl.x.o&0xffffffff | data.loc&signBit
			mx.cleanCtl.z.o = data.z.o
			mx.schedule(&mx.cleanCo, 1, 4)

//line mmixpipe.w:8127
			data.state = 34
			fallthrough
		case stage2St + 34:
			if mx.cleanCo.next == nil {
				pc = lNextSync
				continue
			}
			if mx.tryingToInterrupt && data.interim && data == mx.oldHot {
				data.z.o = 0 // |resumeCont|를 내다본다
				pc = lFinEx  // 가로막기를 받아들인다
				continue
			}
			return mx.wait(self, 1)

//line mmixpipe.w:8142
		case lNextSync:
			data.state = 35
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if data.interim {

//line mmixpipe.w:8210
				{
					bl := Tetra(data.b.o)
					data.interim = false
					data.xx -= byte(((bl - 1) &^ Tetra(data.y.o)) + 1)
					data.y.o += Octa(bl)
					data.y.o = data.y.o&^0xffffffff | Octa(Tetra(data.y.o)&-bl)
					data.z.o = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&^8191+Tetra(data.y.o)&8191)
					if Tetra(data.y.o)&8191 == 0 {
						pc = lSquareOne // 페이지 경계를 넘었을지도 모른다
						continue
					}
					if data.i == syncd {
						pc = lDoSyncd
					} else {
						pc = lDoSyncid
					}
					continue
				}

//line mmixpipe.w:8150
			}
			data.goLoc.known = true
			pc = lFinEx
			continue

//line mmixpipe.w:8236
		case lSyncCheck:
			if yl := Tetra(data.y.o); yl^(yl+Tetra(data.xx)) >= 8192 {
				data.xx -= byte((8191 &^ yl) + 1)
				data.y.o += 8192
				data.y.o = data.y.o&^0xffffffff | Octa(Tetra(data.y.o)&^8191)
				pc = lSquareOne
				continue
			}
			pc = lFinEx
			continue

//line mmixpipe.w:2514

//line mmixpipe.w:4058
		case flushMemSt + 0:
			if mx.memLock != nil {
				return mx.wait(self, 1)
			}
			data.state = 1
			fallthrough
		case flushMemSt + 1:
			setLock(self, &mx.memLock)
			data.state = 2

//line mmixpipe.w:4072
			{
				del := c.gg >> 3 // 알갱이 하나의 옥타바이트 수
				addr := c.outbuf.tag
				off := int(Tetra(addr)&0xffff) >> 3
				count, first, lastOff := 0, true, 0
				for i, j = 0, 0; j < c.bb>>c.g; j++ {
					ii := i + del
					if !c.outbuf.dirty[j] {
						i = ii
						off += del
						addr += Octa(del << 3)
					} else {
						for i < ii {
							if first {
								count++
								lastOff = off
								first = false
								mx.memWrite(addr, c.outbuf.data[i])
							} else {
								if (off^lastOff)&(-mx.busWords) != 0 {
									count++
								}
								lastOff = off
								mx.memHash[mx.lastH].chunk[off] = c.outbuf.data[i]
							}
							i++
							off++
							addr += 8
						}
					}
				}
				return mx.wait(self, mx.memAddrTime+count*mx.memWriteTime)
			}

//line mmixpipe.w:4068
		case flushMemSt + 2:
			return true // 이것이 |memLock|과 |c.outbuf|를 풀어 준다

//line mmixpipe.w:4128
		case flushSSt + 0:
			if mx.Scache.lock != nil {
				return mx.wait(self, 1)
			}
			data.state = 1
			fallthrough
		case flushSSt + 1:
			setLock(self, &mx.Scache.lock)
			sp := mx.cacheSearch(mx.Scache, c.outbuf.tag)
			data.ptrB = sp
			if sp != nil {
				data.state = 4
			} else if mx.Scache.mode&writeAlloc != 0 {
				if blockDiff != 0 {
					data.state = 2
				} else {
					data.state = 3
				}
			} else {
				data.state = 6
			}
			return mx.wait(self, mx.Scache.accessTime)
		case flushSSt + 2:

//line mmixpipe.w:4198
			{
				count := blockDiff >> 3
				if mx.memLock != nil {
					return mx.wait(self, 1)
				}
				addr := c.outbuf.tag&^0xffffffff | Octa(Tetra(c.outbuf.tag)&Tetra(-mx.Scache.bb))
				off := int(Tetra(addr)&0xffff) >> 3
				for j = 0; j < mx.Scache.bb>>3; j++ {
					if j == 0 {
						mx.Scache.inbuf.data[j] = mx.memRead(addr)
					} else {
						mx.Scache.inbuf.data[j] = mx.memHash[mx.lastH].chunk[j+off]
					}
				}
				setLock(&mx.memLocker, &mx.memLock)
				delay := mx.memAddrTime + (count+mx.busWords-1)/mx.busWords*mx.memReadTime
				mx.startup(&mx.memLocker, delay)
				data.state = 3
				return mx.wait(self, delay)
			}

//line mmixpipe.w:4154
		case flushSSt + 3:

//line mmixpipe.w:4185
			if mx.Scache.filler.next != nil {
				return mx.wait(self, 1) // 어쩌면 불필요한 조심일지도?
			}
			p = mx.allocSlot(mx.Scache, c.outbuf.tag)
			if p == nil {
				return mx.wait(self, 1)
			}
			data.ptrB = p
			p.tag = c.outbuf.tag&^0xffffffff | Octa(Tetra(c.outbuf.tag)&Tetra(-mx.Scache.bb))

//line mmixpipe.w:4156
			if blockDiff != 0 {

//line mmixpipe.w:4220
				p.data, mx.Scache.inbuf.data = mx.Scache.inbuf.data, p.data

//line mmixpipe.w:4158
			} else {
				for j = 0; j < mx.Scache.bb>>3; j++ {
					p.data[j] = c.outbuf.data[j]
				}
			}
			for j = 0; j < mx.Scache.bb>>mx.Scache.g; j++ {
				p.dirty[j] = false
			}
			fallthrough
		case flushSSt + 4:
			mx.copyBlock(c, &c.outbuf, mx.Scache, p)
			mx.hitSet = mx.Scache.cacheAddr(c.outbuf.tag)
			mx.useAndFix(mx.Scache, p) // |p|는 옮겨지지 않는다
			data.state = 5
			return mx.wait(self, mx.Scache.copyInTime)
		case flushSSt + 5:
			if mx.Scache.mode&writeBack == 0 { // 즉시 쓰기
				if mx.Scache.flusher.next != nil {
					return mx.wait(self, 1)
				}
				mx.flushCache(mx.Scache, p, true)
			}
			return true
		case flushSSt + 6:

//line mmixpipe.w:4225
			if mx.Scache.flusher.next != nil {
				return mx.wait(self, 1)
			}
			mx.Scache.outbuf.tag = c.outbuf.tag&^0xffffffff |
				Octa(Tetra(c.outbuf.tag)&Tetra(-mx.Scache.bb))
			for j = 0; j < mx.Scache.bb>>mx.Scache.g; j++ {
				mx.Scache.outbuf.dirty[j] = false
			}
			mx.copyBlock(c, &c.outbuf, mx.Scache, &mx.Scache.outbuf)
			mx.startup(&mx.Scache.flusher, mx.Scache.copyOutTime)
			return true

//line mmixpipe.w:4257
		case fillMemSt + 0:
			data.x.o = mx.memRead(data.z.o)
			if cc != nil {
				cc.ctl.x.o = data.x.o
				mx.awaken(cc, mx.memReadTime)
			}
			data.state = 1

//line mmixpipe.w:4289
			{
				c.inbuf.tag = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-c.bb))
				count, off := c.bb>>3, int(Tetra(c.inbuf.tag)&0xffff)>>3
				for i = 0; i < count; i, off = i+1, off+1 {
					c.inbuf.data[i] = mx.memHash[mx.lastH].chunk[off]
				}
				if count <= mx.busWords {
					return mx.wait(self, 1+mx.memReadTime)
				}
				return mx.wait(self, count/mx.busWords*mx.memReadTime)
			}

//line mmixpipe.w:4265
		case fillMemSt + 1:
			releaseLock(self, &mx.memLock)
			data.state = 2
			fallthrough
		case fillMemSt + 2:
			if c != mx.Scache {
				if c.lock != nil {
					return mx.wait(self, 1)
				}
				setLock(self, &c.lock)
			}
			if cc != nil {
				mx.awaken(cc, c.copyInTime) // 두 번째로 깨운다
			}
			mx.loadCache(c, data.ptrB.(*cacheblock))
			data.state = 3
			return mx.wait(self, c.copyInTime)
		case fillMemSt + 3:
			return true

//line mmixpipe.w:4317
		case fillSSt + 0:
			p = mx.cacheSearch(mx.Scache, data.z.o)
			if p != nil {
				pc = lSNonMiss
				continue
			}
			data.state = 1
			fallthrough
		case fillSSt + 1:

//line mmixpipe.w:4372
			if mx.Scache.filler.next != nil || mx.memLock != nil {
				return mx.wait(self, 1)
			}
			p = mx.allocSlot(mx.Scache, data.z.o)
			if p == nil {
				return mx.wait(self, 1)
			}
			setLock(&mx.Scache.filler, &mx.memLock)
			setLock(self, &mx.Scache.fillLock)
			data.ptrC = p
			mx.Scache.fillerCtl.ptrB = p
			mx.Scache.fillerCtl.z.o = data.z.o
			mx.startup(&mx.Scache.filler, mx.memAddrTime)

//line mmixpipe.w:4327
			data.state = 2
			return mx.sleep(self)
		case fillSSt + 2:
			if cc != nil {
				cc.ctl.x.o = data.x.o               // 이 데이터는 |Scache.filler|가 공급했다
				mx.awaken(cc, mx.Scache.accessTime) // 우리는 그것을 되돌려 전한다
			}
			data.state = 3
			return mx.sleep(self) // 깨어나면 S-캐시에 우리 데이터가 있을 것이다

//line mmixpipe.w:4338
		case lSNonMiss:
			if cc != nil {
				cc.ctl.x.o = p.data[(Tetra(data.z.o)&Tetra(mx.Scache.bb-1))>>3]
				mx.awaken(cc, mx.Scache.accessTime)
			}
			fallthrough
		case fillSSt + 3:

//line mmixpipe.w:4390
			{
				c.inbuf.tag = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-c.bb))
				off := int(Tetra(c.inbuf.tag)&Tetra(mx.Scache.bb-1)) >> 3
				for j = 0; j < c.bb>>3; j, off = j+1, off+1 {
					c.inbuf.data[j] = p.data[off]
				}
				releaseLock(self, &mx.Scache.fillLock)
				setLock(self, &mx.Scache.lock)
			}

//line mmixpipe.w:4346
			data.state = 4
			return mx.wait(self, mx.Scache.accessTime)
		case fillSSt + 4:
			mx.Scache.lock = nil // 우리가 그 잠금을 쥐고 있었다
			data.state = 5
			fallthrough
		case fillSSt + 5:
			if c.lock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &c.lock)
			mx.loadCache(c, data.ptrB.(*cacheblock))
			data.state = 6
			return mx.wait(self, c.copyInTime)
		case fillSSt + 6:
			if cc != nil {
				mx.awaken(cc, 1) // 두 번째로 깨운다
			}
			return true

//line mmixpipe.w:4490
		case cleanupSt + 0:
			if mx.Dcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.Dcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
			setLock(self, &mx.Dcache.lock)
			i, j = 0, 0
			fallthrough
		case lDcleanLoop:
			if i < mx.Dcache.cc {
				p = &mx.Dcache.set[i][j]
			} else {
				p = &mx.Dcache.victim[j]
			}
			if p.tag&signBit != 0 {
				pc = lDcleanInc
				continue
			}
			if !isDirty(mx.Dcache, p) {
				p.tag |= data.x.o &^ 0xffffffff
				pc = lDcleanInc
				continue
			}
			data.y.o = Octa(Tetra(i))<<32 | Octa(Tetra(j))
			fallthrough

//line mmixpipe.w:4520
		case lDclean:
			data.state = 1
			data.ptrB = p
			return mx.wait(self, mx.Dcache.accessTime)
		case cleanupSt + 1:
			if mx.Dcache.flusher.next != nil {
				return mx.wait(self, 1)
			}
			mx.flushCache(mx.Dcache, p, data.x.o>>32 == 0)
			p.tag |= data.x.o &^ 0xffffffff
			releaseLock(self, &mx.Dcache.lock)
			data.state = 2
			return mx.wait(self, mx.Dcache.copyOutTime)
		case cleanupSt + 2:
			if mx.cleanLock == nil {
				return false // 일찍 끝난다
			}
			if mx.Dcache.flusher.next != nil {
				return mx.wait(self, 1)
			}
			if data.i != sync {
				pc = lSprep
				continue
			}
			data.state = 3
			fallthrough

//line mmixpipe.w:4548
		case cleanupSt + 3:
			if mx.Dcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.Dcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
			setLock(self, &mx.Dcache.lock)
			i, j = int(data.y.o>>32), int(Tetra(data.y.o))
			fallthrough
		case lDcleanInc:
			j++
			if i < mx.Dcache.cc && j == mx.Dcache.aa {
				j, i = 0, i+1
			}
			if i == mx.Dcache.cc && j == mx.Dcache.vv {
				data.state = 5
				return mx.wait(self, mx.Dcache.accessTime)
			}
			pc = lDcleanLoop
			continue
		case cleanupSt + 4:
			if mx.Dcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.Dcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
			setLock(self, &mx.Dcache.lock)
			p = mx.cacheSearch(mx.Dcache, data.z.o)
			if p != nil {
				mx.demoteAndFix(mx.Dcache, p)
				if isDirty(mx.Dcache, p) {
					pc = lDclean
					continue
				}
			}
			data.state = 9
			return mx.wait(self, mx.Dcache.accessTime)

//line mmixpipe.w:4591
		case cleanupSt + 5:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if mx.Scache == nil {
				return false
			}
			if mx.Scache.lock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.Scache.lock)
			i, j = 0, 0
			fallthrough
		case lScleanLoop:
			if i < mx.Scache.cc {
				p = &mx.Scache.set[i][j]
			} else {
				p = &mx.Scache.victim[j]
			}
			if p.tag&signBit != 0 {
				pc = lScleanInc
				continue
			}
			if !isDirty(mx.Scache, p) {
				p.tag |= data.x.o &^ 0xffffffff
				pc = lScleanInc
				continue
			}
			data.y.o = Octa(Tetra(i))<<32 | Octa(Tetra(j))
			fallthrough

//line mmixpipe.w:4624
		case lSclean:
			data.state = 6
			data.ptrB = p
			return mx.wait(self, mx.Scache.accessTime)
		case cleanupSt + 6:
			if mx.Scache.flusher.next != nil {
				return mx.wait(self, 1)
			}
			mx.flushCache(mx.Scache, p, data.x.o>>32 == 0)
			p.tag |= data.x.o &^ 0xffffffff
			releaseLock(self, &mx.Scache.lock)
			data.state = 7
			return mx.wait(self, mx.Scache.copyOutTime)
		case cleanupSt + 7:
			if mx.cleanLock == nil {
				return false // 일찍 끝난다
			}
			if mx.Scache.flusher.next != nil {
				return mx.wait(self, 1)
			}
			if data.i != sync {
				return false
			}
			data.state = 8
			fallthrough

//line mmixpipe.w:4651
		case cleanupSt + 8:
			if mx.Scache.lock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.Scache.lock)
			i, j = int(data.y.o>>32), int(Tetra(data.y.o))
			fallthrough
		case lScleanInc:
			j++
			if i < mx.Scache.cc && j == mx.Scache.aa {
				j, i = 0, i+1
			}
			if i == mx.Scache.cc && j == mx.Scache.vv {
				data.state = 10
				return mx.wait(self, mx.Scache.accessTime)
			}
			pc = lScleanLoop
			continue
		case lSprep:
			data.state = 9
			if self.lockloc != nil {
				releaseLock(self, &mx.Dcache.lock)
			}
			if mx.Scache == nil {
				return false
			}
			if mx.Scache.lock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.Scache.lock)
			p = mx.cacheSearch(mx.Scache, data.z.o)
			if p != nil {
				mx.demoteAndFix(mx.Scache, p)
				if isDirty(mx.Scache, p) {
					pc = lSclean
					continue
				}
			}
			data.state = 10
			return mx.wait(self, mx.Scache.accessTime)

//line mmixpipe.w:4486
		case cleanupSt + 10:
			return true

//line mmixpipe.w:4779
		case fillVirtSt + 0:

//line mmixpipe.w:4873
			aaaaa := data.y.o
			i = int(aaaaa >> 61) // 세그먼트 번호
			aaaaa &= 1<<61 - 1   // 세그먼트~$i$ 안의 주소
			aaaaa >>= mx.pageS   // 페이지 주소
			for j = 0; aaaaa != 0; j++ {
				co[2*j].ctl.z.o = (aaaaa & 0x3ff) << 3
				aaaaa >>= 10
			}
			if mx.pageB[i+1] < mx.pageB[i]+j { // 주소가 너무 크다
				// |data.b.o|가 0이므로 할 일이 없다
				//
//line mmixpipe.w:4882
//line mmixpipe.w:4883
			} else {
				if j == 0 {
					j = 1
					co[0].ctl.z.o = 0
				}

//line mmixpipe.w:4898
				j--
				aaaaa = Octa(Tetra(mx.pageR + mx.pageB[i] + j))
				co[2*j].ctl.y = spec{o: aaaaa<<13 + signBit}
				for ; ; j-- {
					co[2*j].ctl.x.o, co[2*j].ctl.x.known = 0, false
					co[2*j].ctl.owner = &co[2*j]
					mx.startup(&co[2*j], 1)
					if j == 0 {
						break
					}
					co[2*(j-1)].ctl.y.p = &co[2*j].ctl.x
				}
				data.b.p = &co[0].ctl.x

//line mmixpipe.w:4889
			}

//line mmixpipe.w:4781
			data.state = 1
			fallthrough
		case fillVirtSt + 1:
			if data.b.p != nil {
				if data.b.p.known {
					data.b.o, data.b.p = data.b.p.o, nil
				} else {
					return mx.wait(self, 1)
				}
			}

//line mmixpipe.w:4919
			c.inbuf.tag = mx.transKey(data.y.o)
			c.inbuf.data[0] = data.b.o
			if cc != nil {
				cc.ctl.z.o = data.b.o
				mx.awaken(cc, 1)
			}

//line mmixpipe.w:4792
			data.state = 2
			fallthrough
		case fillVirtSt + 2:
			if c.lock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &c.lock)
			mx.loadCache(c, data.ptrB.(*cacheblock))
			data.state = 3
			return mx.wait(self, c.copyInTime)
		case fillVirtSt + 3:
			data.b.o = 0
			return true

//line mmixpipe.w:5164
		case writeSt + 4:

//line mmixpipe.w:5315
			if mx.Dcache.mode&writeBack == 0 { // 즉시 쓰기
				if mx.Dcache.flusher.next != nil {
					return mx.wait(self, 1)
				}
				mx.flushCache(mx.Dcache, p, true)
			}

//line mmixpipe.w:5166
			data.state = 5
			fallthrough
		case writeSt + 5:
			mx.writeHead = mx.prevWrite(mx.writeHead)
			fallthrough
		case lWriteRestart:
			data.state = 0

//line mmixpipe.w:5189
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if mx.writeHead == mx.writeTail {
				return mx.wait(self, 1) // 쓰기 버퍼가 비어 있다
			}
			if mx.writeHead.i == sync {

//line mmixpipe.w:5323
				setLock(self, &mx.wbufLock)
				data.state = 5
				return mx.wait(self, 1)

//line mmixpipe.w:5198
			}
			if mx.writeHead.addr>>32&0xffff0000 != 0 {
				pc = lMemDirect
				continue
			}
			if Tetra(mx.ticks)-mx.writeHead.stamp < Tetra(mx.holdingTime) && mx.speedLock == nil {
				return mx.wait(self, 1) // 데이터가 아직 설익었다
			}
			if mx.Dcache == nil {
				pc = lMemDirect // 캐시하지 않는다
				continue
			}
			if mx.Dcache.lock != nil {
				return mx.wait(self, 1) // D-캐시가 바쁘다
			}
			if j = getReader(mx.Dcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)

//line mmixpipe.w:5302
			p = mx.cacheSearch(mx.Dcache, mx.writeHead.addr)
			if p != nil {
				p = mx.useAndFix(mx.Dcache, p)
				setLock(self, &mx.wbufLock)
				data.ptrB = p
				a := Tetra(mx.writeHead.addr) & Tetra(mx.Dcache.bb-1)
				p.data[a>>3] = mx.writeHead.o
				p.dirty[a>>mx.Dcache.g] = true
				data.state = 4
				return mx.wait(self, mx.Dcache.accessTime)
			}

//line mmixpipe.w:5218
			if mx.Dcache.mode&writeAlloc != 0 && mx.writeHead.i != stunc {
				data.state = 1
			} else {
				data.state = 3
			}
			return mx.wait(self, mx.Dcache.accessTime)

//line mmixpipe.w:5174
		case writeSt + 1:

//line mmixpipe.w:5273
			if mx.Dcache.filler.next != nil ||
				(mx.Scache != nil && mx.Scache.lock != nil) || (mx.Scache == nil && mx.memLock != nil) {
				pc = lWriteRestart
				continue
			}
			p = mx.allocSlot(mx.Dcache, mx.writeHead.addr)
			if p == nil {
				pc = lWriteRestart
				continue
			}
			if mx.Scache != nil {
				setLock(&mx.Dcache.filler, &mx.Scache.lock)
			} else {
				setLock(&mx.Dcache.filler, &mx.memLock)
			}
			setLock(self, &mx.Dcache.fillLock)
			data.ptrB, mx.Dcache.fillerCtl.ptrB = p, p
			mx.Dcache.fillerCtl.z.o = mx.writeHead.addr
			if mx.Scache != nil {
				mx.startup(&mx.Dcache.filler, mx.Scache.accessTime)
			} else {
				mx.startup(&mx.Dcache.filler, mx.memAddrTime)
			}

//line mmixpipe.w:5176
			data.state = 2
			return mx.sleep(self)
		case writeSt + 2:
			data.state = 0
			return mx.sleep(self) // D-캐시에 블록이 들어오면 깨어난다
		case writeSt + 3:

//line mmixpipe.w:5229
			if mx.Dcache.filler.next != nil ||
				(mx.Scache != nil && mx.Scache.lock != nil) || (mx.Scache == nil && mx.memLock != nil) {
				pc = lWriteRestart
				continue
			}
			if mx.Dcache.flusher.next != nil {
				return mx.wait(self, 1)
			}
			{
				c := mx.Dcache
				a := Tetra(mx.writeHead.addr)
				c.outbuf.tag = mx.writeHead.addr&^0xffffffff | Octa(a&Tetra(-c.bb))
				for j = 0; j < c.bb>>c.g; j++ {
					c.outbuf.dirty[j] = false
				}
				c.outbuf.data[(a&Tetra(c.bb-1))>>3] = mx.writeHead.o
				c.outbuf.dirty[(a&Tetra(c.bb-1))>>c.g] = true
				c.outbuf.rank = c.gg // 유효한 바이트가 이만큼 있다
			}
			setLock(self, &mx.wbufLock)
			mx.startup(&mx.Dcache.flusher, mx.Dcache.copyOutTime)
			data.state = 5
			return mx.wait(self, mx.Dcache.copyOutTime)

//line mmixpipe.w:5183
		case lMemDirect:

//line mmixpipe.w:5254
			if mx.memLock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.wbufLock)
			setLock(&mx.memLocker, &mx.memLock) // |vanish| 타입의 코루틴
			mx.startup(&mx.memLocker, mx.memAddrTime+mx.memWriteTime)
			if mx.writeHead.addr>>32&0xffff0000 != 0 {
				mx.specWrite(mx.writeHead.addr, mx.writeHead.o, mx.writeHead.size)
			} else {
				mx.memWrite(mx.writeHead.addr, mx.writeHead.o)
			}
			data.state = 5
			return mx.wait(self, mx.memAddrTime+mx.memWriteTime)

//line mmixpipe.w:2515
		default:

//line mmixpipe.w:2558
			switch {
			case pc >= fetchSt && pc < stage1St:
				pc = lSwitch1
				continue
			case pc >= stage1St && pc < stage2St:
				pc = lSwitch2
				continue
			case pc >= stage2St && pc < flushMemSt:
				return true
			}

//line mmixpipe.w:2517
		}
		mx.panic(confusion(fmt.Sprintf("label %d", pc)))
	}
}

//line mmixpipe.w:2876
func shiftAmt(z Octa) int {
	if z >= 64 {
		return 64
	}
	return int(z)
}

//line mmixpipe.w:3182
func (mx *machine) bpIndex(loc Octa) int {
	l := Tetra(loc)
	m := (l&Tetra(mx.bpCmask))<<mx.bpB + l&Tetra(mx.bpAmask)
	return int((mx.coolHist&Tetra(mx.bpBcmask))<<mx.bpA ^ m>>2)
}

//line mmixpipe.w:3276
func registerTruth(o Octa, op int) int {
	var b int
	switch (op >> 1) & 0x3 {
	case 0:
		b = int(o >> 63) // 음수인가?
	case 1:
		b = b2i(o == 0) // 0인가?
	case 2:
		b = b2i(o < signBit && o != 0) // 양수인가?
	case 3:
		b = int(o & 0x1) // 홀수인가?
	}
	if op&0x8 != 0 {
		return b ^ 1
	}
	return b
}

//line mmixpipe.w:3298
func (mx *machine) issuedBetween(c, cc *control) int {
	if c.idx > cc.idx {
		return c.idx - 1 - cc.idx
	}
	return c.idx + (mx.reorderTop.idx - cc.idx)
}

//line mmixpipe.w:3349
func (mx *machine) printStats() {
	if mx.bpTable != nil {
		mx.printf("Predictions: %d in agreement, %d in opposition; %d good, %d bad\n",
			mx.bpOkStat, mx.bpRevStat, mx.bpGoodStat, mx.bpBadStat)
	} else {
		mx.printf("Predictions: %d good, %d bad\n", mx.bpGoodStat, mx.bpBadStat)
	}
	mx.printf("Instructions issued per cycle:\n")
	for j := 0; j <= mx.dispatchMax; j++ {
		mx.printf("  %d   %d\n", j, mx.dispatchStat[j])
	}
}

//line mmixpipe.w:3517
func isDirty(c *cache, p *cacheblock) bool {
	for j, d := 0, 0; j < c.bb; j, d = j+c.gg, d+1 {
		if p.dirty[d] {
			return true
		}
	}
	return false
}

//line mmixpipe.w:3529
func (mx *machine) printCacheBlock(p *cacheblock, c *cache) {
	b, g := c.bb>>3, c.gg>>3
	mx.printf("%016x: ", p.tag)
	for i, j := 0, 0; j < b; {
		d := byte(' ')
		if p.dirty[i] {
			d = '*'
		}
		mx.printf("%016x%c", p.data[j], d)
		j++
		if j&(g-1) == 0 {
			i++
		}
	}
	mx.printf(" (%d)\n", p.rank)
}

//line mmixpipe.w:3547
func (mx *machine) printCacheLocks(c *cache) {
	if c != nil {
		if c.lock != nil {
			mx.printf("%s locked by %s:%d\n", c.name, c.lock.name, c.lock.stage)
		}
		if c.fillLock != nil {
			mx.printf("%sfill locked by %s:%d\n", c.name, c.fillLock.name, c.fillLock.stage)
		}
	}
}

//line mmixpipe.w:3563
func (mx *machine) printCache(c *cache, dirtyOnly bool) {
	if c != nil {
		what := "Contents"
		if dirtyOnly {
			what = "Dirty blocks"
		}
		mx.printf("%s of %s:", what, c.name)
		if c.filler.next != nil {
			mx.printf(" (filling ")
			if c.name[1] == 'T' {
				mx.printOcta(c.fillerCtl.y.o)
			} else {
				mx.printOcta(c.fillerCtl.z.o)
			}
			mx.printf(")")
		}
		if c.flusher.next != nil {
			mx.printf(" (flushing ")
			mx.printOcta(c.outbuf.tag)
			mx.printf(")")
		}
		mx.printf("\n")

//line mmixpipe.w:3592
		for i := 0; i < c.cc; i++ {
			for j := 0; j < c.aa; j++ {
				if (c.set[i][j].tag&signBit == 0 || mx.verbose&showWholecacheBit != 0) &&
					(!dirtyOnly || isDirty(c, &c.set[i][j])) {
					mx.printf("[%d][%d] ", i, j)
					mx.printCacheBlock(&c.set[i][j], c)
				}
			}
		}
		for j := 0; j < c.vv; j++ {
			if (c.victim[j].tag&signBit == 0 || mx.verbose&showWholecacheBit != 0) &&
				(!dirtyOnly || isDirty(c, &c.victim[j])) {
				mx.printf("V[%d] ", j)
				mx.printCacheBlock(&c.victim[j], c)
			}
		}

//line mmixpipe.w:3586
	}
}

//line mmixpipe.w:3612
func cleanBlock(c *cache, p *cacheblock) {
	p.tag = sign32 << 32
	for j := 0; j < c.bb>>3; j++ {
		p.data[j] = 0
	}
	for j := 0; j < c.bb>>c.g; j++ {
		p.dirty[j] = false
	}
}

//line mmixpipe.w:3627
func zapCache(c *cache) {
	for i := 0; i < c.cc; i++ {
		for j := 0; j < c.aa; j++ {
			cleanBlock(c, &c.set[i][j])
		}
	}
	for j := 0; j < c.vv; j++ {
		cleanBlock(c, &c.victim[j])
	}
}

//line mmixpipe.w:3642
func getReader(c *cache) int {
	for j := 0; j < c.ports; j++ {
		if c.reader[j].next == nil {
			return j
		}
	}
	return -1
}

//line mmixpipe.w:3656
func (mx *machine) copyBlock(c *cache, p *cacheblock, cc *cache, pp *cacheblock) {
	off := int(Tetra(p.tag) & Tetra(cc.bb-1))
	if c.g != cc.g || p.tag>>32 != pp.tag>>32 || Tetra(p.tag)-Tetra(off) != Tetra(pp.tag) {
		mx.panic(confusion("copy block"))
	}
	for j, jj := 0, off>>c.g; j < c.bb>>c.g; j, jj = j+1, jj+1 {
		if p.dirty[j] {
			pp.dirty[jj] = true
			for i, ii, lim := j<<(c.g-3), jj<<(c.g-3), (j+1)<<(c.g-3); i < lim; i, ii = i+1, ii+1 {
				pp.data[ii] = p.data[i]
			}
		}
	}
}

//line mmixpipe.w:3678
func (mx *machine) chooseVictim(s cacheset, aa int, policy replacePolicy) *cacheblock {
	switch policy {
	case random:
		return &s[int(Tetra(mx.ticks))&(aa-1)]
	case serial:
		l := s[0].rank
		s[0].rank = (l + 1) & (aa - 1)
		return &s[l]
	case lru:
		for k := range aa {
			if s[k].rank == 0 {
				return &s[k]
			}
		}
		mx.panic(confusion("lru victim")) // 무슨 일인가? 순위가 0인 것이 없다
	case pseudoLRU:
		l := 1
		for m := aa >> 1; m != 0; m >>= 1 {
			l = l + l + s[l].rank
		}
		return &s[l-aa]
	}
	return nil
}

//line mmixpipe.w:3707
func noteUsage(l *cacheblock, s cacheset, aa int, policy replacePolicy) {
	if aa == 1 || policy <= serial {
		return
	}
	if policy == lru {
		r := l.rank
		for k := range aa {
			if s[k].rank > r {
				s[k].rank--
			}
		}
		l.rank = aa - 1
	} else { // |policy==pseudoLRU|
		r := l.pos
		for j, m := 1, aa>>1; m != 0; m >>= 1 {
			if r&m != 0 {
				s[j].rank = 0
				j = j + j + 1
			} else {
				s[j].rank = 1
				j = j + j
			}
		}
	}
}

//line mmixpipe.w:3737
func demoteUsage(l *cacheblock, s cacheset, aa int, policy replacePolicy) {
	if aa == 1 || policy <= serial {
		return
	}
	if policy == lru {
		r := l.rank
		for k := range aa {
			if s[k].rank < r {
				s[k].rank++
			}
		}
		l.rank = 0
	} else { // |policy==pseudoLRU|
		r := l.pos
		for j, m := 1, aa>>1; m != 0; m >>= 1 {
			if r&m != 0 {
				s[j].rank = 1
				j = j + j + 1
			} else {
				s[j].rank = 0
				j = j + j
			}
		}
	}
}

//line mmixpipe.w:3770
func (c *cache) cacheAddr(alf Octa) cacheset {
	return c.set[(Tetra(alf)&^Tetra(c.tagmask))>>c.b]
}

func (mx *machine) cacheSearch(c *cache, alf Octa) *cacheblock {
	s := c.cacheAddr(alf) // |alf|에 해당하는 집합
	for k := 0; k < c.aa; k++ {
		if p := &s[k]; (Tetra(p.tag)^Tetra(alf))&Tetra(c.tagmask) == 0 && p.tag>>32 == alf>>32 {
			mx.hitSet = s
			return p
		}
	}
	s = c.victim
	if s == nil {
		return nil // 캐시를 놓쳤고, 희생자 영역도 없다
	}
	for k := 0; k < c.vv; k++ {
		if p := &s[k]; (Tetra(p.tag)^Tetra(alf))&Tetra(-c.bb) == 0 && p.tag>>32 == alf>>32 {
			mx.hitSet = s
			return p
		}
	}
	return nil // 두 번 놓쳤다
}

//line mmixpipe.w:3802
func sameSet(a, b cacheset) bool {
	return len(a) > 0 && len(b) > 0 && &a[0] == &b[0]
}

//line mmixpipe.w:3811
func (mx *machine) useAndFix(c *cache, p *cacheblock) *cacheblock {
	if !sameSet(mx.hitSet, c.victim) {
		noteUsage(p, mx.hitSet, c.aa, c.repl)
	} else {
		noteUsage(p, mx.hitSet, c.vv, c.vrepl) // 희생자 캐시에서 찾았다
		if c.filler.next == nil {
			s := c.cacheAddr(p.tag)
			q := mx.chooseVictim(s, c.aa, c.repl)
			noteUsage(q, s, c.aa, c.repl)
			swapBlocks(p, q)
			return q
		}
	}
	return p
}

//line mmixpipe.w:3831
func swapBlocks(p, q *cacheblock) {
	p.tag, q.tag = q.tag, p.tag
	p.dirty, q.dirty = q.dirty, p.dirty
	p.data, q.data = q.data, p.data
}

//line mmixpipe.w:3841
func (mx *machine) demoteAndFix(c *cache, p *cacheblock) *cacheblock {
	if !sameSet(mx.hitSet, c.victim) {
		demoteUsage(p, mx.hitSet, c.aa, c.repl)
	} else {
		demoteUsage(p, mx.hitSet, c.vv, c.vrepl)
	}
	return p
}

//line mmixpipe.w:3854
func (mx *machine) loadCache(c *cache, p *cacheblock) {
	for i := 0; i < c.bb>>c.g; i++ {
		p.dirty[i] = false
	}
	p.data, c.inbuf.data = c.inbuf.data, p.data
	p.tag = c.inbuf.tag
	mx.hitSet = c.cacheAddr(p.tag)
	mx.useAndFix(c, p) // |p|는 옮겨지지 않는다
}

//line mmixpipe.w:3869
func (mx *machine) flushCache(c *cache, p *cacheblock, keep bool) {
	c.outbuf.tag = p.tag
	if keep { // |p|의 데이터를 보존해야 하는가?
		copy(c.outbuf.data[:c.bb>>3], p.data)
	} else {
		c.outbuf.data, p.data = p.data, c.outbuf.data
	}
	c.outbuf.dirty, p.dirty = p.dirty, c.outbuf.dirty
	for j := 0; j < c.bb>>c.g; j++ {
		p.dirty[j] = false
	}
	c.outbuf.rank = c.bb                  // 유효한 바이트가 이만큼 있다
	mx.startup(&c.flusher, c.copyOutTime) // 중단되지 않는다
}

//line mmixpipe.w:3902
func (mx *machine) allocSlot(c *cache, alf Octa) *cacheblock {
	if mx.cacheSearch(c, alf) != nil {
		return nil
	}
	if c.flusher.next != nil && c.outbuf.tag>>32 == alf>>32 &&
		(Tetra(c.outbuf.tag)^Tetra(alf))&Tetra(-c.bb) == 0 {
		return nil
	}
	s := c.cacheAddr(alf) // |alf|에 해당하는 집합
	var p *cacheblock
	if c.victim != nil {
		p = mx.chooseVictim(c.victim, c.vv, c.vrepl)
	} else {
		p = mx.chooseVictim(s, c.aa, c.repl)
	}
	if isDirty(c, p) {
		if c.flusher.next != nil {
			return nil
		}
		mx.flushCache(c, p, false)
	}
	if c.victim != nil {
		q := mx.chooseVictim(s, c.aa, c.repl)
		swapBlocks(p, q)
		q.tag |= sign32 << 32 // 태그를 무효로 만든다
		return q
	}
	p.tag |= sign32 << 32
	return p
}

//line mmixpipe.w:3986
func (mx *machine) memRead(addr Octa) Octa {
	off := (Tetra(addr) & 0xffff) >> 3
	key := Tetra(addr)&0xffff0000 + Tetra(addr>>32)
	h := int(key % Tetra(mx.hashPrime))
	for ; mx.memHash[h].tag != key; h-- {
		if mx.memHash[h].chunk == nil {
			if mx.verbose&uninitMemBit != 0 {
				mx.errprintf("uninitialized memory read at %016x", addr)

			}
			h = mx.hashPrime
			break // 0을 돌려줄 것이다
		}
		if h == 0 {
			h = mx.hashPrime
		}
	}
	mx.lastH = h
	return mx.memHash[h].chunk[off]
}

//line mmixpipe.w:4011
func (mx *machine) memWrite(addr, val Octa) {
	off := (Tetra(addr) & 0xffff) >> 3
	key := Tetra(addr)&0xffff0000 + Tetra(addr>>32)
	h := int(key % Tetra(mx.hashPrime))
	for ; mx.memHash[h].tag != key; h-- {
		if mx.memHash[h].chunk == nil {
			mx.memChunks++
			if mx.memChunks > mx.memChunksMax {
				mx.panic(fmt.Sprintf("More than %d memory chunks are needed",

					mx.memChunksMax))
			}
			mx.memHash[h].chunk = make([]Octa, 1<<13)
			mx.memHash[h].tag = key
			break
		}
		if h == 0 {
			h = mx.hashPrime
		}
	}
	mx.lastH = h
	mx.memHash[h].chunk[off] = val
}

//line mmixpipe.w:4848
func (mx *machine) transKey(addr Octa) Octa {
	return addr&^mx.pageMask + Octa(mx.pageN)
}

func (mx *machine) physAddr(virt, trans Octa) Octa {
	t := trans &^ mx.pageMask // PTE의 \\{ynp} 필드들을 지운다
	return t + virt&mx.pageMask
}

//line mmixpipe.w:4962
func (mx *machine) prevWrite(p *writeNode) *writeNode {
	if p == mx.wbufBot {
		return mx.wbufTop
	}
	return &mx.wbuf[p.idx-1]
}

func (mx *machine) nextWrite(q *writeNode) *writeNode {
	if q == mx.wbufTop {
		return mx.wbufBot
	}
	return &mx.wbuf[q.idx+1]
}

//line mmixpipe.w:4992
func (mx *machine) printWriteBuffer() {
	mx.printf("Write buffer")
	if mx.writeHead == mx.writeTail {
		mx.printf(" (empty)\n")
	} else {
		mx.printf(":\n")
		for p := mx.writeHead; p != mx.writeTail; p = mx.prevWrite(p) {
			mx.printf("m[")
			mx.printOcta(p.addr)
			mx.printf("]=")
			mx.printOcta(p.o)
			if p.i == stunc {
				mx.printf(" unc")
			} else if p.i == sync {
				mx.printf(" sync")
			}
			mx.printf(" (age %d)\n", int32(Tetra(mx.ticks)-p.stamp))
		}
	}
}

//line mmixpipe.w:5018
func (mx *machine) printPipe() {
	mx.printWriteBuffer()
	mx.printReorderBuffer()
	mx.printFetchBuffer()
}

//line mmixpipe.w:5048
func (mx *machine) writeSearch(ctl *control, addr Octa) *Octa {
	var p *specnode
	if ctl.memX {
		p = ctl.x.up
	} else {
		p = ctl.ptrA.(*specnode)
	}
	q := mx.writeTail
	addr &^= 7
	if p != &mx.mem {
		k, h, c := p.ctl.idx, mx.hot.idx, ctl.idx
		if !(k > h && c <= h) && !(k < c && (c <= h || k > h)) {
			for ; p != &mx.mem; p = p.up {
				if p.addr>>32 == 0xffffffff {
					return &mx.dunno
				}
				if p.addr&^7 == addr {
					if p.known {
						return &p.o
					}
					return &mx.dunno
				}
			}
		}
	}
	for { // 원본의 |qloop|
		if q == mx.writeHead {
			return nil
		}
		q = mx.nextWrite(q)
		if q.addr == addr {
			return &q.o
		}
	}
}

//line mmixpipe.w:5383
func prwBits(data *control) Tetra {
	switch {
	case data.i < st:
		return prBit
	case data.i == pst:
		return prBit + pwBit
	case data.i == syncid && data.loc&signBit != 0:
		return 0
	}
	return pwBit
}

//line mmixpipe.w:6112
func (mx *machine) waitOrPass(self *coroutine, t int) bool {
	if self.ctl.i == prego {
		mx.passAfter(self, t)
		return true
	}
	mx.wait(self, t)
	return false
}

//line mmixpipe.w:6561
func isLoadStore(i int) bool {
	return i >= ld && i <= cswap
}

//line mmixpipe.w:6838
func packBytes(a, b, c, d int) Tetra {
	return Tetra(a)<<24 + Tetra(b)<<16 + Tetra(c)<<8 + Tetra(d)
}

//line mmixpipe.w:7563
func isSubnormal(x Octa) bool {
	return (x>>32)&0x7ff00000 == 0 && x&(0xfffff<<32|0xffffffff) != 0
}

func isTrivial(x Octa) bool {
	return (x>>32)&0x7ff00000 == 0x7ff00000
}

func (mx *machine) setRound(data *control) {
	if Tetra(data.ra.o) < 0x10000 {
		mx.curRound = mmixarith.RoundNear
	} else {
		mx.curRound = mmixarith.Round(Tetra(data.ra.o) >> 16)
	}
}

func (mx *machine) roundMode(y Octa) mmixarith.Round {
	if Tetra(y) == 0 {
		return mx.curRound
	}
	return mmixarith.Round(Tetra(y))
}

//line mmixpipe.w:8097
func syncidNext(data *control) int {
	if data.loc&signBit != 0 {
		return 31
	}
	return 33
}

//line mmixpipe.w:8332
func (mx *machine) magicRead(addr Octa) Octa {
	for q := mx.writeTail; q != mx.writeHead; {
		q = mx.nextWrite(q)
		if q.addr&^7 == addr&^7 {
			return q.o
		}
	}
	if mx.Dcache != nil {
		if o, ok := mx.magicReadCache(mx.Dcache, addr); ok {
			return o
		}
		if mx.Scache != nil {
			if o, ok := mx.magicReadCache(mx.Scache, addr); ok {
				return o
			}
		}
	}
	return mx.memRead(addr)
}

//line mmixpipe.w:8355
func (mx *machine) magicReadCache(c *cache, addr Octa) (Octa, bool) {
	k := (Tetra(addr) & Tetra(c.bb-1)) >> 3
	if p := mx.cacheSearch(c, addr); p != nil {
		return p.data[k], true
	}
	if (Tetra(c.outbuf.tag)^Tetra(addr))&Tetra(-c.bb) == 0 && c.outbuf.tag>>32 == addr>>32 {
		return c.outbuf.data[k], true
	}
	return 0, false
}

//line mmixpipe.w:8370
func (mx *machine) magicWrite(addr, val Octa) {
	for q := mx.writeTail; q != mx.writeHead; {
		q = mx.nextWrite(q)
		if q.addr&^7 == addr&^7 {
			q.o = val
		}
	}
	if mx.Dcache != nil {
		mx.magicWriteCache(mx.Dcache, addr, val)
		if mx.Scache != nil {
			mx.magicWriteCache(mx.Scache, addr, val)
		}
	}
	mx.memWrite(addr, val)
}

func (mx *machine) magicWriteCache(c *cache, addr, val Octa) {
	k := (Tetra(addr) & Tetra(c.bb-1)) >> 3
	if p := mx.cacheSearch(c, addr); p != nil {
		p.data[k] = val
	}
	for _, b := range []*cacheblock{&c.inbuf, &c.outbuf} {
		if (Tetra(b.tag)^Tetra(addr))&Tetra(-c.bb) == 0 && b.tag>>32 == addr>>32 {
			b.data[k] = val
		}
	}
}

//line mmixpipe.w:8405
func magicAddr(a Octa) Octa {
	return Octa(Tetra(a>>32)>>29)<<32 | a&0xffffffff
}

//line mmixpipe.w:8430
func (mx *machine) MMGetChars(buf []byte, size int, addr Octa, stop int) int {
	if (addr>>32&0x9fffffff != 0 || (addr+Octa(size-1))>>32&0x9fffffff != 0) && size != 0 {
		mx.errprintf("Attempt to get characters from off the page!\n")

		return 0
	}
	return mx.getChars(buf, size, magicAddr(addr), stop)
}

func (mx *machine) getChars(buf []byte, size int, a Octa, stop int) int {
	for k := 0; k < size; {
		x := mx.magicRead(a)
		if a&0x7 != 0 || k > size-8 {

//line mmixpipe.w:8455
			buf[k] = byte(x >> (8 * (^a & 0x7)))
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

//line mmixpipe.w:8444
		} else {

//line mmixpipe.w:8468
			{
				h, l := Tetra(x>>32), Tetra(x)
				buf[k] = byte(h >> 24)
				if buf[k] == 0 && (stop == 0 || stop > 0 && h < 0x10000) {
					return k
				}
				buf[k+1] = byte(h >> 16)
				if buf[k+1] == 0 && stop == 0 {
					return k + 1
				}
				buf[k+2] = byte(h >> 8)
				if buf[k+2] == 0 && (stop == 0 || stop > 0 && h&0xffff == 0) {
					return k + 2
				}
				buf[k+3] = byte(h)
				if buf[k+3] == 0 && stop == 0 {
					return k + 3
				}
				buf[k+4] = byte(l >> 24)
				if buf[k+4] == 0 && (stop == 0 || stop > 0 && l < 0x10000) {
					return k + 4
				}
				buf[k+5] = byte(l >> 16)
				if buf[k+5] == 0 && stop == 0 {
					return k + 5
				}
				buf[k+6] = byte(l >> 8)
				if buf[k+6] == 0 && (stop == 0 || stop > 0 && l&0xffff == 0) {
					return k + 6
				}
				buf[k+7] = byte(l)
				if buf[k+7] == 0 && stop == 0 {
					return k + 7
				}
				k += 8
				a += 8
			}

//line mmixpipe.w:8446
		}
	}
	return size
}

//line mmixpipe.w:8512
func (mx *machine) MMPutChars(buf []byte, size int, addr Octa) {
	if (addr>>32&0x9fffffff != 0 || (addr+Octa(size-1))>>32&0x9fffffff != 0) && size != 0 {
		mx.errprintf("Attempt to put characters off the page!\n")

		return
	}
	mx.putChars(buf, size, magicAddr(addr))
}

func (mx *machine) putChars(buf []byte, size int, a Octa) {
	for k := 0; k < size; {
		if a&0x7 != 0 || k > size-8 {

//line mmixpipe.w:8532
			{
				s := 8 * (^a & 0x7)
				x := mx.magicRead(a)
				x ^= ((x>>s ^ Octa(buf[k])) & 0xff) << s
				mx.magicWrite(a, x)
				k++
				a++
			}

//line mmixpipe.w:8525
		} else {

//line mmixpipe.w:8542
			{
				var x Octa
				for _, b := range buf[k : k+8] {
					x = x<<8 | Octa(b)
				}
				mx.magicWrite(a, x)
				k += 8
				a += 8
			}

//line mmixpipe.w:8527
		}
	}
}

//line mmixpipe.w:8562
func (mx *machine) StdinChr() byte {
	for mx.stdinBufStart == mx.stdinBufEnd {
		mx.printf("StdIn> ")

		mx.out.Flush()
		mx.stdin.fgets(mx.stdinBuf[:], 256)
		mx.stdinBufStart = 0
		p := 0
		for ; p < 254; p++ {
			if mx.stdinBuf[p] == '\n' {
				break
			}
		}
		mx.stdinBufEnd = p + 1
	}
	c := mx.stdinBuf[mx.stdinBufStart]
	mx.stdinBufStart++
	return c
}
