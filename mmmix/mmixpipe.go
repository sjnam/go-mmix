//line mmmix/mmixpipe.w:33
package main

import (
	"bufio"
	"fmt"
	"io"
	"math/bits"

	"github.com/sjnam/go-mmix/mmixarith"
	"github.com/sjnam/go-mmix/mmixio"
)

//line mmmix/mmixpipe.w:268
type (
	Tetra = mmixarith.Tetra // an unsigned 32-bit integer
	Octa  = mmixarith.Octa  // two tetrabytes make one octabyte
)

//line mmmix/mmixpipe.w:331
type coroutine struct {
	name    string     // symbolic identification of a coroutine
	stage   int        // its rank
	next    *coroutine // its successor
	lockloc *lockvar   // what it might be locking
	ctl     *control   // its data
	succ    *coroutine // the original's |self+1|
}

//line mmmix/mmixpipe.w:472
type lockvar = *coroutine

//line mmmix/mmixpipe.w:529
type spec struct {
	o Octa
	p *specnode
}

type specnode struct {
	o        Octa
	known    bool
	addr     Octa
	up, down *specnode
	ctl      *control // the control block containing this |specnode|
}

//line mmmix/mmixpipe.w:601
type control struct {
	loc             Octa // virtual address where an instruction originated
	op              int  // the original instruction bytes
	xx, yy, zz      byte
	y, z, b, ra     spec       // inputs
	x, a, goLoc, rl specnode   // outputs
	owner           *coroutine // a coroutine whose |ctl| this is
	i               int        // internal opcode
	state           int        // internal mindset

//line mmmix/mmixpipe.w:623
	usage      bool // should rU be increased?
	needB      bool // should we stall until |b.p==nil|?
	needRA     bool // should we stall until |ra.p==nil|?
	renX       bool // does |x| correspond to a rename register?
	memX       bool // does |x| correspond to a memory write?
	renA       bool // does |a| correspond to a rename register?
	setL       bool // does |rl| correspond to a new value of rL?
	interim    bool // does this instruction need to be reissued on interrupt?
	stackAlert bool // is there potential for stack overflow?

//line mmmix/mmixpipe.w:611
	arithExc         Tetra // arithmetic exceptions for event bits of rA
	hist             Tetra // history bits for use in branch prediction
	denin, denout    int   // execution time penalties for subnormal handling
	curO, curS       Octa  // speculative rO and rS before this instruction
	interrupt        Tetra // does this instruction generate an interrupt?
	ptrA, ptrB, ptrC any   // generic pointers for miscellaneous use
	idx              int   // position in the reorder buffer
}

//line mmmix/mmixpipe.w:1339
type fetch struct {
	loc       Octa  // virtual address of instruction
	inst      Tetra // the instruction itself
	interrupt Tetra // bit codes that might cause interruption
	noted     bool  // have we peeked at this instruction?
	hist      Tetra // if we peeked, this was the |peekHist|
	idx       int   // position in the fetch buffer
}

//line mmmix/mmixpipe.w:1512
type funcUnit struct {
	name string      // symbolic designation
	ops  [8]Tetra    // big-endian bitmap for the opcodes supported
	k    int         // number of pipeline stages
	co   []coroutine // $k$ consecutive coroutines
}

//line mmmix/mmixpipe.w:2517
type label int

//line mmmix/mmixpipe.w:3420
type replacePolicy int

const (
	random replacePolicy = iota
	serial
	pseudoLRU
	lru

//line mmmix/mmixpipe.w:3427
)

//line mmmix/mmixpipe.w:3466
type cacheblock struct {
	tag   Octa   // bits of key not included in the cache block address
	dirty []bool // array of $2^{g-b}$ dirty bits, one per granule
	data  []Octa // array of $2^{b-3}$ octabytes, the data in a cache block
	rank  int    // auxiliary information for non-|random| policies
	pos   int    // position within the set
}

type cacheset = []cacheblock // array of $2^a$ or $2^v$ blocks

type cache struct {
	a, b, c, g, v      int           // logs of associativity, blocksize, setsize, granularity, victimsize
	aa, bb, cc, gg, vv int           // associativity, blocksize, setsize, granularity, victimsize (all powers of 2)
	tagmask            int           // $-2^{b+c}$
	repl, vrepl        replacePolicy // how to choose victims and victim-victims
	mode               int           // optional |writeBack| and/or |writeAlloc|
	accessTime         int           // cycles to know if there's a hit
	copyInTime         int           // cycles to copy a new block into the cache
	copyOutTime        int           // cycles to copy an old block from the cache
	set                []cacheset    // array of $2^c$ sets of arrays of cache blocks
	victim             cacheset      // the victim cache, if present
	filler             coroutine     // a coroutine for copying new blocks into the cache
	fillerCtl          control       // its control block
	flusher            coroutine     // a coroutine for writing dirty old data from the cache
	flusherCtl         control       // its control block
	inbuf              cacheblock    // filling comes from here
	outbuf             cacheblock    // flushing goes to here
	lock               lockvar       // nonzero when the cache is being changed significantly
	fillLock           lockvar       // nonzero when filler should pass data back
	ports              int           // how many coroutines can be reading the cache?
	reader             []coroutine   // array of coroutines that might be reading simultaneously
	name               string        // |"Icache"|, for example
}

//line mmmix/mmixpipe.w:3943
type chunknode struct {
	tag   Tetra  // 32-bit chunk address
	chunk []Octa // either |nil| or an array of $2^{13}$ octabytes
}

//line mmmix/mmixpipe.w:4925
type writeNode struct {
	o     Octa  // data to be stored
	addr  Octa  // its physical address
	stamp Tetra // when last committed (mod $2^{32}$)
	i     int   // is this write special?
	size  int   // parameter for |specWrite|
	idx   int   // position in the write buffer
}

//line mmmix/mmixpipe.w:8588
type machine struct {

//line mmmix/mmixpipe.w:128
	verbose int // controls the level of diagnostic output

//line mmmix/mmixpipe.w:188
	breakpointHit bool // was the breakpoint instruction fetched?
	halted        bool // has the machine halted?
	breakpoint    Octa // the breakpoint of |MMIXRun|

//line mmmix/mmixpipe.w:301
	curRound   mmixarith.Round // the current rounding mode
	exceptions int             // bits set by floating point operations

//line mmmix/mmixpipe.w:400
	ringSize int         // set by |MMIX_config|, must be sufficiently large
	ring     []coroutine // head nodes of the scheduling queues
	curTime  int         // position of the current time in |ring|

//line mmmix/mmixpipe.w:456
	sentinel coroutine // dummy coroutine at origin of circular list

//line mmmix/mmixpipe.w:1182
	fetchMax, dispatchMax, peekahead, commitMax int // limits on instructions that can be handled per clock cycle

//line mmmix/mmixpipe.w:1204
	reorder                []control // the ring containing the reorder buffer
	reorderBot, reorderTop *control  // least and greatest elements of that ring
	hot, cool              *control  // front and rear of the reorder buffer
	oldHot                 *control  // value of |hot| at beginning of cycle
	deissues               int       // the number of instructions that need to be deissued

//line mmmix/mmixpipe.w:1289
	dispatchCount    int     // how many dispatched on this cycle
	suppressDispatch bool    // should dispatching be bypassed?
	doingInterrupt   int     // how many cycles of interrupt preparations remain
	dispatchLock     lockvar // lock to prevent instruction issues
	dispatchStat     []int32 // how often did we dispatch 0, 1, \dots\ instructions?
	securityDisabled bool    // omit security checks for testing purposes?

//line mmmix/mmixpipe.w:1356
	fetchBuf           []fetch // the ring containing the fetch buffer
	fetchBot, fetchTop *fetch  // least and greatest elements of that ring
	head, tail         *fetch  // front and rear of the fetch buffer
	oldTail            *fetch  // rear of the fetch buffer available on the current cycle

//line mmmix/mmixpipe.w:1377
	unknownSpec specnode // where the original's \.{UNKNOWN\_SPEC} points

//line mmmix/mmixpipe.w:1520
	funit      []funcUnit // array of functional units
	funitCount int        // the number of functional units

//line mmmix/mmixpipe.w:1527
	newCool  *control // the reorder position following |cool|
	resuming int      // nonzero if resuming an interrupted instruction
	support  [8]Tetra // big-endian bitmap for all opcodes supported

//line mmmix/mmixpipe.w:1742
	g                          [256]specnode // global registers and special registers
	l                          []specnode    // the ring of local registers
	lringSize                  int           // number of local registers on the chip (must be a power of 2)
	maxRenameRegs, maxMemSlots int           // capacity of reorder buffer
	renameRegs, memSlots       int           // currently unused capacity

//line mmmix/mmixpipe.w:1752
	ticks     Octa // the internal clock
	lringMask int  // for calculations modulo |lringSize|

//line mmmix/mmixpipe.w:1860
	coolO, coolS       Octa  // values of rO, rS before the |cool| instruction
	coolL, coolG       int   // values of rL and rG before the |cool| instruction
	coolHist, peekHist Tetra // history bits for branch prediction
	newO, newS         Octa  // values of rO, rS after |cool|

//line mmmix/mmixpipe.w:2163
	mem specnode

//line mmmix/mmixpipe.w:2566
	memLocker coroutine // trivial coroutine that vanishes
	dLocker   coroutine // another
	vanishCtl control   // such coroutines share a common control block

//line mmmix/mmixpipe.w:2780
	pipeSeq [maxPipeOp + 1][pipeLimit + 1]byte

//line mmmix/mmixpipe.w:3081
	newQ            Octa // when rQ increases in any bit position, so should this
	stackOverflowed bool // stack overflow not yet reported

//line mmmix/mmixpipe.w:3149
	bpA, bpB, bpC, bpN int    // parameters for branch prediction
	bpTable            []int8 // either |nil| or an array of $2^{\mkern1mua+b+c}$ items

//line mmmix/mmixpipe.w:3238
	bpAmask, bpCmask, bpBcmask, bpNmask, bpNpower int
	bpRevStat, bpOkStat                           int32 // how often we overrode and agreed
	bpBadStat, bpGoodStat                         int32 // how often we failed and succeeded

//line mmmix/mmixpipe.w:3501
	Icache, Dcache, Scache, ITcache, DTcache *cache

//line mmmix/mmixpipe.w:3789
	hitSet cacheset

//line mmmix/mmixpipe.w:3953
	memChunks    int         // this many chunks are allocated so far
	memChunksMax int         // up to this many different chunks per run
	hashPrime    int         // larger than |memChunksMax|, but not enormous
	memHash      []chunknode // the simulated main memory

//line mmmix/mmixpipe.w:3998
	lastH int // the hash index that was most recently correct

//line mmmix/mmixpipe.w:4030
	memAddrTime  int     // cycles to transmit an address on memory bus
	busWords     int     // width of memory bus, in octabytes
	memReadTime  int     // cycles to read from main memory
	memWriteTime int     // cycles to write to main memory
	memLock      lockvar // is non-|nil| when the bus is busy

//line mmmix/mmixpipe.w:4443
	cleanCo   coroutine
	cleanCtl  control
	cleanLock lockvar

//line mmmix/mmixpipe.w:4715
	IPTctl, DPTctl [5]control    // control blocks for I and D page translation
	IPTco, DPTco   [10]coroutine // each coroutine is a two-stage pipeline

//line mmmix/mmixpipe.w:4800
	pageN    int    // the 10-bit |n| field of rV, times 8
	pageR    int    // the 27-bit |r| field of rV
	pageS    int    // the 8-bit |s| field of rV
	pageF    int    // the 3-bit |f| field of rV
	pageB    [5]int // the 4-bit |b| fields of rV; |pageB[0]=0|
	pageMask Octa   // the least significant |s| bits
	pageBad  bool   // does rV violate the rules?

//line mmmix/mmixpipe.w:4852
	noHardwarePT bool

//line mmmix/mmixpipe.w:4941
	wbuf                 []writeNode // the ring containing the write buffer
	wbufBot, wbufTop     *writeNode  // least and greatest write buffer nodes
	writeHead, writeTail *writeNode  // front and rear of the write buffer
	wbufLock             lockvar     // is the data in |writeHead| being written?
	holdingTime          int         // minimum holding time
	speedLock            lockvar     // should we ignore |holdingTime|?

//line mmmix/mmixpipe.w:4967
	writeCo  coroutine // coroutine that empties the write buffer
	writeCtl control   // its control block

//line mmmix/mmixpipe.w:5030
	dunno Octa // where the original's \.{DUNNO} points

//line mmmix/mmixpipe.w:6066
	instPtr spec   // the instruction pointer (aka program counter)
	fetched []Octa // buffer for incoming instructions

//line mmmix/mmixpipe.w:6075
	fetchLo, fetchHi int // the active region of that buffer
	fetchCo          coroutine
	fetchCtl         control

//line mmmix/mmixpipe.w:6492
	sleepy bool // have we just emitted the page table emulation call?

//line mmmix/mmixpipe.w:6745
	tryingToInterrupt bool // encouraging interruptible operations to pause
	nullifying        bool // stopping dispatch to nullify a load/store command

//line mmmix/mmixpipe.w:7701
	fremMax                     int
	deninPenalty, denoutPenalty int

//line mmmix/mmixpipe.w:8576
	stdinBuf      [256]byte // standard input to the simulated program
	stdinBufStart int       // current position in that buffer
	stdinBufEnd   int       // current end of that buffer

//line mmmix/mmixpipe.w:8590
	out     *bufio.Writer // standard output
	stderr  io.Writer     // standard error
	io      *mmixio.IO    // files of the simulated program
	stdin   *cfile        // standard input
	specBuf [20]byte      // buffer used by |specRead| of \.{mmixmem.w}
	hioDev  *hio          // host I/O device of \.{mmixmem.w} (only when \.{-k} is given)
	blkDev  *blk          // block device of \.{mmixmem.w} (only when \.{-d} is given)
}

//line mmmix/mmixpipe.w:8603
type exitSignal int

//line mmmix/mmixpipe.w:115
const (
	issueBit           = 1 << 0 // show control blocks when issued, deissued, committed
	pipeBit            = 1 << 1 // show the pipeline and locks on every cycle
	coroutineBit       = 1 << 2 // show the coroutines when started on every cycle
	scheduleBit        = 1 << 3 // show the coroutines when scheduled
	uninitMemBit       = 1 << 4 // complain when reading from an uninitialized chunk of memory
	interactiveReadBit = 1 << 5 // prompt user when reading from I/O location
	showSpecBit        = 1 << 6 // display special read/write transactions as they happen
	showPredBit        = 1 << 7 // display branch prediction details
	showWholecacheBit  = 1 << 8 // display cache blocks even when their key tag is invalid
)

//line mmmix/mmixpipe.w:294
const (
	signBit = mmixarith.SignBit // the 64-bit sign bit
	negOne  = mmixarith.NegOne  // $-1$
	sign32  = 0x80000000        // the 32-bit sign bit (the original's |sign_bit|)
)

//line mmmix/mmixpipe.w:726
const (
	TRAP = iota
	FCMP
	FUN
	FEQL
	FADD
	FIX
	FSUB
	FIXU
//line mmmix/mmixpipe.w:728
	FLOT
	FLOTI
	FLOTU
	FLOTUI
	SFLOT
	SFLOTI
	SFLOTU
	SFLOTUI
//line mmmix/mmixpipe.w:729
	FMUL
	FCMPE
	FUNE
	FEQLE
	FDIV
	FSQRT
	FREM
	FINT
//line mmmix/mmixpipe.w:730
	MUL
	MULI
	MULU
	MULUI
	DIV
	DIVI
	DIVU
	DIVUI
//line mmmix/mmixpipe.w:731
	ADD
	ADDI
	ADDU
	ADDUI
	SUB
	SUBI
	SUBU
	SUBUI
//line mmmix/mmixpipe.w:732
	IIADDU
	IIADDUI
	IVADDU
	IVADDUI
	VIIIADDU
	VIIIADDUI
	XVIADDU
	XVIADDUI
//line mmmix/mmixpipe.w:733
	CMP
	CMPI
	CMPU
	CMPUI
	NEG
	NEGI
	NEGU
	NEGUI
//line mmmix/mmixpipe.w:734
	SL
	SLI
	SLU
	SLUI
	SR
	SRI
	SRU
	SRUI
//line mmmix/mmixpipe.w:735
	BN
	BNB
	BZ
	BZB
	BP
	BPB
	BOD
	BODB
//line mmmix/mmixpipe.w:736
	BNN
	BNNB
	BNZ
	BNZB
	BNP
	BNPB
	BEV
	BEVB
//line mmmix/mmixpipe.w:737
	PBN
	PBNB
	PBZ
	PBZB
	PBP
	PBPB
	PBOD
	PBODB
//line mmmix/mmixpipe.w:738
	PBNN
	PBNNB
	PBNZ
	PBNZB
	PBNP
	PBNPB
	PBEV
	PBEVB
//line mmmix/mmixpipe.w:739
	CSN
	CSNI
	CSZ
	CSZI
	CSP
	CSPI
	CSOD
	CSODI
//line mmmix/mmixpipe.w:740
	CSNN
	CSNNI
	CSNZ
	CSNZI
	CSNP
	CSNPI
	CSEV
	CSEVI
//line mmmix/mmixpipe.w:741
	ZSN
	ZSNI
	ZSZ
	ZSZI
	ZSP
	ZSPI
	ZSOD
	ZSODI
//line mmmix/mmixpipe.w:742
	ZSNN
	ZSNNI
	ZSNZ
	ZSNZI
	ZSNP
	ZSNPI
	ZSEV
	ZSEVI
//line mmmix/mmixpipe.w:743
	LDB
	LDBI
	LDBU
	LDBUI
	LDW
	LDWI
	LDWU
	LDWUI
//line mmmix/mmixpipe.w:744
	LDT
	LDTI
	LDTU
	LDTUI
	LDO
	LDOI
	LDOU
	LDOUI
//line mmmix/mmixpipe.w:745
	LDSF
	LDSFI
	LDHT
	LDHTI
	CSWAP
	CSWAPI
	LDUNC
	LDUNCI
//line mmmix/mmixpipe.w:746
	LDVTS
	LDVTSI
	PRELD
	PRELDI
	PREGO
	PREGOI
	GO
	GOI
//line mmmix/mmixpipe.w:747
	STB
	STBI
	STBU
	STBUI
	STW
	STWI
	STWU
	STWUI
//line mmmix/mmixpipe.w:748
	STT
	STTI
	STTU
	STTUI
	STO
	STOI
	STOU
	STOUI
//line mmmix/mmixpipe.w:749
	STSF
	STSFI
	STHT
	STHTI
	STCO
	STCOI
	STUNC
	STUNCI
//line mmmix/mmixpipe.w:750
	SYNCD
	SYNCDI
	PREST
	PRESTI
	SYNCID
	SYNCIDI
	PUSHGO
	PUSHGOI
//line mmmix/mmixpipe.w:751
	OR
	ORI
	ORN
	ORNI
	NOR
	NORI
	XOR
	XORI
//line mmmix/mmixpipe.w:752
	AND
	ANDI
	ANDN
	ANDNI
	NAND
	NANDI
	NXOR
	NXORI
//line mmmix/mmixpipe.w:753
	BDIF
	BDIFI
	WDIF
	WDIFI
	TDIF
	TDIFI
	ODIF
	ODIFI
//line mmmix/mmixpipe.w:754
	MUX
	MUXI
	SADD
	SADDI
	MOR
	MORI
	MXOR
	MXORI
//line mmmix/mmixpipe.w:755
	SETH
	SETMH
	SETML
	SETL
	INCH
	INCMH
	INCML
	INCL
//line mmmix/mmixpipe.w:756
	ORH
	ORMH
	ORML
	ORL
	ANDNH
	ANDNMH
	ANDNML
	ANDNL
//line mmmix/mmixpipe.w:757
	JMP
	JMPB
	PUSHJ
	PUSHJB
	GETA
	GETAB
	PUT
	PUTI
//line mmmix/mmixpipe.w:758
	POP
	RESUME
	SAVE
	UNSAVE
	SYNC
	SWYM
	GET
	TRIP

//line mmmix/mmixpipe.w:759
)

//line mmmix/mmixpipe.w:805
const (

//line mmmix/mmixpipe.w:819
	mul0  = iota // multiplication by zero
	mul1         // multiplication by 1--8 bits
	mul2         // multiplication by 9--16 bits
	mul3         // multiplication by 17--24 bits
	mul4         // multiplication by 25--32 bits
	mul5         // multiplication by 33--40 bits
	mul6         // multiplication by 41--48 bits
	mul7         // multiplication by 49--56 bits
	mul8         // multiplication by 57--64 bits
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

//line mmmix/mmixpipe.w:807

//line mmmix/mmixpipe.w:845
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

//line mmmix/mmixpipe.w:808

//line mmmix/mmixpipe.w:881
	get      // \.{GET}
	put      // \.{PUT[I]}
	ld       // \.{LD[B,W,T,O][U][I]}, \.{LDHT[I]}, \.{LDSF[I]}
	ldptp    // load page table pointer
	ldpte    // load page table entry
	ldunc    // \.{LDUNC[I]}
	ldvts    // \.{LDVTS[I]}
	preld    // \.{PRELD[I]}
	prest    // \.{PREST[I]}
	st       // \.{STO[U][I]}, \.{STCO[I]}, \.{STUNC[I]}
	syncd    // \.{SYNCD[I]}
	syncid   // \.{SYNCID[I]}
	pst      // \.{ST[B,W,T][U][I]}, \.{STHT[I]}
	stunc    // \.{STUNC[I]}, in write buffer
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
	incgamma // increase $\gamma$ pointer
	decgamma // decrease $\gamma$ pointer
	incrl    // increase rL and $\beta$
	sav      // intermediate stage of \.{SAVE}
	unsav    // intermediate stage of \.{UNSAVE}
	resum    // intermediate stage of \.{RESUME}

//line mmmix/mmixpipe.w:809
)

const (
	maxPipeOp      = feps
	maxRealCommand = trip

//line mmmix/mmixpipe.w:814
)

//line mmmix/mmixpipe.w:976
const (
	rA  = 21 // arithmetic status register
	rB  = 0  // bootstrap register (trip)
	rC  = 8  // continuation register
	rD  = 1  // dividend register
	rE  = 2  // epsilon register
	rF  = 22 // failure location register
	rG  = 19 // global threshold register
	rH  = 3  // himult register
	rI  = 12 // interval counter
	rJ  = 4  // return-jump register
	rK  = 15 // interrupt mask register
	rL  = 20 // local threshold register
	rM  = 5  // multiplex mask register
	rN  = 9  // serial number
	rO  = 10 // register stack offset
	rP  = 23 // prediction register
	rQ  = 16 // interrupt request register
	rR  = 6  // remainder register
	rS  = 11 // register stack pointer
	rT  = 13 // trap address register
	rU  = 17 // usage counter
	rV  = 18 // virtual translation register
	rW  = 24 // where-interrupted register (trip)
	rX  = 25 // execution register (trip)
	rY  = 26 // Y operand (trip)
	rZ  = 27 // Z operand (trip)
	rBB = 7  // bootstrap register (trap)
	rTT = 14 // dynamic trap address register
	rWW = 28 // where-interrupted register (trap)
	rXX = 29 // execution register (trap)
	rYY = 30 // Y operand (trap)
	rZZ = 31 // Z operand (trap)
)

//line mmmix/mmixpipe.w:1020
const (
	pBit       = 1 << 0  // instruction in privileged location
	sBit       = 1 << 1  // security violation
	bBit       = 1 << 2  // instruction breaks the rules
	kBit       = 1 << 3  // instruction for kernel only
	nBit       = 1 << 4  // virtual translation bypassed
	pxBit      = 1 << 5  // permission lacking to execute from page
	pwBit      = 1 << 6  // permission lacking to write on page
	prBit      = 1 << 7  // permission lacking to read from page
	protOffset = 5       // distance from |prBit| to protection code position
	xBit       = 1 << 8  // floating inexact
	zBit       = 1 << 9  // floating division by zero
	uBit       = 1 << 10 // floating underflow
	oBit       = 1 << 11 // floating overflow
	iBit       = 1 << 12 // floating invalid operation
	wBit       = 1 << 13 // float-to-fix overflow
	vBit       = 1 << 14 // integer overflow
	dBit       = 1 << 15 // integer divide check
	hBit       = 1 << 16 // trip handler bit
	fBit       = 1 << 17 // forced trap bit
	eBit       = 1 << 18 // external (dynamic) trap bit
)

//line mmmix/mmixpipe.w:1059
const (
	powerFailure      = 1 << 0 // try to shut down calmly and quickly
	parityError       = 1 << 1 // try to save the file systems
	nonexistentMemory = 1 << 2 // a memory address can't be used
	rebootSignal      = 1 << 4 // it's time to start over
	intervalTimeout   = 1 << 6 // the timer register, rI, has reached zero
	stackOverflow     = 1 << 7 // data has been stored on the rC page
)

//line mmmix/mmixpipe.w:1630
const (
	xIsDestBit   = 0x20
	relAddrBit   = 0x40
	ctlChangeBit = 0x80

//line mmmix/mmixpipe.w:1634
)

//line mmmix/mmixpipe.w:1770
const (
	version       = 1 // version of the \MMIX\ architecture that we support
	subversion    = 0 // secondary byte of version number
	subsubversion = 0 // further qualification to version number
)

//line mmmix/mmixpipe.w:2520
const (
	lSwitch0 label = iota // state switch of the fetch coroutine
	lSwitch1              // state switch of the first stage
	lSwitch2              // state switch of the later stages

//line mmmix/mmixpipe.w:2724
	lPassit // the original's |passit|

//line mmmix/mmixpipe.w:2907
	lDie // the original's |die|

//line mmmix/mmixpipe.w:4304
	lSNonMiss // the original's |S_non_miss|

//line mmmix/mmixpipe.w:4463
	lDcleanLoop // the original's |Dclean_loop|
	lDclean     // the original's |Dclean|
	lDcleanInc  // the original's |Dclean_inc|
	lScleanLoop // the original's |Sclean_loop|
	lSclean     // the original's |Sclean|
	lScleanInc  // the original's |Sclean_inc|

//line mmmix/mmixpipe.w:5148
	lMemDirect // the original's |mem_direct|

//line mmmix/mmixpipe.w:5389
	lMakeLdReady // the original's |make_ld_ready|

//line mmmix/mmixpipe.w:5668
	lAvoidD // the original's |avoid_D|

//line mmmix/mmixpipe.w:6122
	lKnownPhys // the original's |known_phys|
	lBadFetch  // the original's |bad_fetch|
	lSwymOne   // the original's |swym_one|
	lFetchOne  // the original's |fetch_one|

//line mmmix/mmixpipe.w:6556
	lEmulateVirt // the original's |emulate_virt|

//line mmmix/mmixpipe.w:8226
	lSyncCheck // the original's |sync_check|

//line mmmix/mmixpipe.w:2525
)

const (
	fetchSt    label = 1000  // state |case| of the fetch coroutine
	stage1St   label = 2000  // state |case| of the first stage
	stage2St   label = 3000  // state |case| of the later stages
	flushMemSt label = 4000  // state |case| of |flushToMem|
	flushSSt   label = 5000  // state |case| of |flushToS|
	fillMemSt  label = 6000  // state |case| of |fillFromMem|
	fillSSt    label = 7000  // state |case| of |fillFromS|
	cleanupSt  label = 8000  // state |case| of |cleanup|
	fillVirtSt label = 9000  // state |case| of |fillFromVirt|
	writeSt    label = 10000 // state |case| of |writeFromWbuf|
)

//line mmmix/mmixpipe.w:2598
const (
	maxStage      = 99 // exceeds all |stage| numbers
	vanish        = 98 // special coroutine that just goes away
	flushToMem    = 97 // coroutine for flushing from a cache to memory
	flushToS      = 96 // coroutine for flushing from a cache to the S-cache
	fillFromMem   = 95 // coroutine for filling a cache from memory
	fillFromS     = 94 // coroutine for filling a cache from the S-cache
	fillFromVirt  = 93 // coroutine for filling a translation cache
	writeFromWbuf = 92 // coroutine for emptying the write buffer
	cleanup       = 91 // coroutine for cleaning the caches
)

//line mmmix/mmixpipe.w:2746
const (
	lPassData = stage1St + 2 // the original's |pass_data|
	lFinEx    = stage1St + 3 // the original's |fin_ex|
)

//line mmmix/mmixpipe.w:2777
const pipeLimit = 90

//line mmmix/mmixpipe.w:3451
const (
	writeBack  = 1 // use this if not write-through
	writeAlloc = 2 // use this if not write-around
)

//line mmmix/mmixpipe.w:4471
const lSprep = cleanupSt + 9 // the original's |Sprep|

//line mmmix/mmixpipe.w:4709
const (
	LDPTP = PREGO // internally this won't cause confusion
	LDPTE = GO

//line mmmix/mmixpipe.w:4712
)

//line mmmix/mmixpipe.w:5151
const lWriteRestart = writeSt + 0 // the original's |write_restart|

//line mmmix/mmixpipe.w:5341
const ldStLaunch = 7 // |state| when load/store command has its memory address

//line mmmix/mmixpipe.w:5435
const (
	dtMiss     = 10 // second stage |state| when DT-cache doesn't hold the key
	dtHit      = 11 // second stage |state| when physical address is known
	hitAndMiss = 12 // second stage |state| when D-cache misses
	ldReady    = 13 // second stage |state| when data has been read
	stReady    = 14 // second stage |state| when data needn't be read
	prestWin   = 15 // second stage |state| when we can fill a block with zeroes
)

//line mmmix/mmixpipe.w:5655
const (
	dtRetry = 8 // second stage |state| when DT-cache should be searched again
	gotDT   = 9 // second stage |state| when DT-cache entry has been computed
)

const (
	lSquareOne   = stage2St + dtRetry  // the original's |square_one|
	lLdRetry     = stage2St + dtHit    // the original's |ld_retry|
	lPrestSpan   = stage2St + prestWin // the original's |prest_span|
	lFinishStore = stage2St + stReady  // the original's |finish_store|
)

//line mmmix/mmixpipe.w:6116
const (
	lNewFetch   = fetchSt + 0 // the original's |new_fetch|
	lStartFetch = fetchSt + 1 // the original's |start_fetch|
)

//line mmmix/mmixpipe.w:6177
const (
	gotIT       = 19 // |state| when IT-cache entry has been computed
	itMiss      = 20 // |state| when IT-cache doesn't hold the key
	itHit       = 21 // |state| when physical instruction address is known
	iHitAndMiss = 22 // |state| when I-cache misses
	fetchReady  = 23 // |state| when instructions have been read
	gotOne      = 24 // |state| when a ``preview'' octabyte is ready
)

//line mmmix/mmixpipe.w:6330
const lFetchRetry = fetchSt + itHit // the original's |fetch_retry|

//line mmmix/mmixpipe.w:6559
const (
	lState4 = stage1St + 4 // the original's |state_4|
	lState5 = stage1St + 5 // the original's |state_5|
)

//line mmmix/mmixpipe.w:6823
const (
	resumeAgain = 0 // repeat the command in rX as if in location $\rm rW-4$
	resumeCont  = 1 // same, but substitute rY and rZ for operands
	resumeSet   = 2 // set register \$X to rZ
	resumeTrans = 3 // put $\rm(rY,rZ)$ into the IT-cache or DT-cache, then do |resumeAgain|
)

//line mmmix/mmixpipe.w:7076
const (
	doResumeTrans = 17                       // |state| for performing |resumeTrans| actions
	lResumeTrans  = stage1St + doResumeTrans // the original's |resume_trans|
)

//line mmmix/mmixpipe.w:8036
const (
	lDoSyncid = stage2St + 30 // the original's |do_syncid|
	lDoSyncd  = stage2St + 33 // the original's |do_syncd|
	lNextSync = stage2St + 35 // the original's |next_sync|
)

//line mmmix/mmixpipe.w:8248
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

//line mmmix/mmixpipe.w:8260
)

const maxSysCall = Ftell

//line mmmix/mmixpipe.w:762
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

//line mmmix/mmixpipe.w:919
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

//line mmmix/mmixpipe.w:934
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

//line mmmix/mmixpipe.w:1012
var specialName = [32]string{"rB", "rD", "rE", "rH", "rJ", "rM", "rR", "rBB",
	"rC", "rN", "rO", "rS", "rI", "rT", "rTT", "rK", "rQ", "rU", "rV", "rG", "rL",
	"rA", "rF", "rP", "rW", "rX", "rY", "rZ", "rWW", "rXX", "rYY", "rZZ"}

//line mmmix/mmixpipe.w:1044
var bitCodeMap = "EFHDVWIOUZXrwxnkbsp"

//line mmmix/mmixpipe.w:1637
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

//line mmmix/mmixpipe.w:1986
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

//line mmmix/mmixpipe.w:6521
var badInstMask = [4]Tetra{0xfffffe, 0xffff, 0xffff00, 0xfffff8}

//line mmmix/mmixpipe.w:8312
var argCount = [11]int{1, 3, 1, 3, 3, 3, 3, 2, 2, 2, 1}

//line mmmix/mmixpipe.w:145
func (mx *machine) MMIXInit() {
	var i, j int

//line mmmix/mmixpipe.w:367
	for k := range mx.ring {
		mx.ring[k].next = &mx.ring[k]
	}

//line mmmix/mmixpipe.w:1226
	mx.hot, mx.cool = mx.reorderTop, mx.reorderTop
	mx.deissues = 0

//line mmmix/mmixpipe.w:1373
	mx.head, mx.tail = mx.fetchTop, mx.fetchTop
	mx.instPtr.p = &mx.unknownSpec

//line mmmix/mmixpipe.w:1532
	for k := 0; k <= mx.funitCount; k++ {
		for i = 0; i < 8; i++ {
			mx.support[i] |= mx.funit[k].ops[i]
		}
	}

//line mmmix/mmixpipe.w:1777
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
		Octa(Tetra(ABSTIME)) // see comment and warning above
	for j = 0; j < mx.lringSize; j++ {
		mx.l[j].addr = sign32<<32 | Octa(256+j)
		mx.l[j].known = true
		mx.l[j].up, mx.l[j].down = &mx.l[j], &mx.l[j]
	}

//line mmmix/mmixpipe.w:2168
	mx.mem.addr = negOne
	mx.mem.up, mx.mem.down = &mx.mem, &mx.mem

//line mmmix/mmixpipe.w:2571
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

//line mmmix/mmixpipe.w:3227
	mx.bpAmask = ((1 << mx.bpA) - 1) << 2            // least $a$ bits of instruction address
	mx.bpCmask = ((1 << mx.bpC) - 1) << (mx.bpA + 2) // the next $c$ address bits
	mx.bpBcmask = (1 << (mx.bpB + mx.bpC)) - 1       // least $b+c$ bits of history info
	mx.bpNmask = (1 << mx.bpN) - 1                   // least significant $n$ bits
	if mx.bpN > 0 {
		mx.bpNpower = 1 << (mx.bpN - 1) // $2^{n-1}$, the sign bit of an $n$-bit number
	}

//line mmmix/mmixpipe.w:4448
	mx.cleanCo.ctl = &mx.cleanCtl
	mx.cleanCo.name = "Clean"
	mx.cleanCo.stage = cleanup
	mx.cleanCtl.goLoc.o = 4

//line mmmix/mmixpipe.w:4722
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
			c.goLoc.o = 3 // the original's |incr(neg_one,4)|
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

//line mmmix/mmixpipe.w:4811
	mx.pageBad = true

//line mmmix/mmixpipe.w:4971
	mx.writeCo.ctl = &mx.writeCtl
	mx.writeCo.name = "Write"
	mx.writeCo.stage = writeFromWbuf
	mx.writeCtl.ptrA = &mx.mem
	mx.writeCtl.goLoc.o = 4
	mx.startup(&mx.writeCo, 1)
	mx.writeHead, mx.writeTail = mx.wbufTop, mx.wbufTop

//line mmmix/mmixpipe.w:6080
	mx.fetchCo.ctl = &mx.fetchCtl
	mx.fetchCo.name = "Fetch"
	mx.fetchCtl.goLoc.o = 4
	mx.startup(&mx.fetchCo, 1)

//line mmmix/mmixpipe.w:148
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

//line mmmix/mmixpipe.w:205
func (mx *machine) panic(msg string) {
	mx.errprintf("Panic: %s!\n", msg)
	mx.expire()
}

func confusion(m string) string {
	return "This can't happen: " + m
}

func (mx *machine) expire() { // the last gasp before dying
	if mx.ticks>>32 != 0 {
		mx.errprintf("(Clock time is %dH+%d.)\n",
			int32(mx.ticks>>32), int32(Tetra(mx.ticks)))
	} else {
		mx.errprintf("(Clock time is %d.)\n", int32(Tetra(mx.ticks)))
	}

	panic(exitSignal(-2))
}

//line mmmix/mmixpipe.w:229
func (mx *machine) printf(format string, a ...any) {
	fmt.Fprintf(mx.out, format, a...)
}

func (mx *machine) errprintf(format string, a ...any) {
	fmt.Fprintf(mx.stderr, format, a...)
}

//line mmmix/mmixpipe.w:277
func (mx *machine) printOcta(o Octa) {
	mx.printf("%x", o)
}

//line mmmix/mmixpipe.w:341
func (mx *machine) printCoroutineID(c *coroutine) {
	mx.printf("%s", coroutineID(c))
}

func coroutineID(c *coroutine) string {
	if c != nil {
		return fmt.Sprintf("%s:%d", c.name, c.stage)
	}
	return "??"

}

//line mmmix/mmixpipe.w:380
func (mx *machine) schedule(c *coroutine, d, s int) {
	tt := (mx.curTime + d) % mx.ringSize
	if d <= 0 || d >= mx.ringSize { // do a sanity check
		mx.panic(confusion("Scheduling ") + coroutineID(c) +
			fmt.Sprintf(" with delay %d", d))
	}
	p := &mx.ring[tt] // start at the list head
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

//line mmmix/mmixpipe.w:409
func (mx *machine) startup(c *coroutine, d int) {
	c.ctl.state = 0
	mx.schedule(c, d, 0)
}

//line mmmix/mmixpipe.w:421
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

//line mmmix/mmixpipe.w:442
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

//line mmmix/mmixpipe.w:475
func setLock(c *coroutine, l *lockvar) {
	*l = c
	c.lockloc = l
}

func releaseLock(c *coroutine, l *lockvar) {
	*l = nil
	c.lockloc = nil
}

//line mmmix/mmixpipe.w:486
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

//line mmmix/mmixpipe.w:545
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

//line mmmix/mmixpipe.w:637
func (c *control) link() {
	c.x.ctl, c.a.ctl, c.goLoc.ctl, c.rl.ctl = c, c, c, c
}

//line mmmix/mmixpipe.w:642
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

//line mmmix/mmixpipe.w:681
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

//line mmmix/mmixpipe.w:655

//line mmmix/mmixpipe.w:702
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

//line mmmix/mmixpipe.w:656
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

//line mmmix/mmixpipe.w:1047
func (mx *machine) printBits(x int) {
	for j, b := 0, eBit; x&(b+b-1) != 0 && b != 0; j, b = j+1, b>>1 {
		if x&b != 0 {
			mx.printf("%c", bitCodeMap[j])
		}
	}
}

//line mmmix/mmixpipe.w:1211
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

//line mmmix/mmixpipe.w:1230
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

//line mmmix/mmixpipe.w:1268
func (mx *machine) cycle() {
	var i, j, m int

//line mmmix/mmixpipe.w:6718
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
	if mx.blkDev != nil {
		mx.blkDev.tick() // supplement: the block device of \.{mmixmem.w} spends time
	}
	mx.tryingToInterrupt = false
	if mx.g[rQ].o&mx.g[rK].o != 0 && mx.cool != mx.hot &&
		mx.hot.interrupt&(eBit+fBit+hBit) == 0 && mx.doingInterrupt == 0 &&
		mx.hot.i != resum {
		if mx.hot.owner != nil {
			mx.tryingToInterrupt = true
		} else {
			mx.hot.interrupt |= eBit

//line mmmix/mmixpipe.w:6756
			i = mx.issuedBetween(mx.hot, mx.cool)
			if i >= mx.deissues {
				mx.deissues = i
				mx.tail = mx.head // clear the fetch buffer
				mx.resuming = 0

//line mmmix/mmixpipe.w:6086
				if mx.fetchCo.lockloc != nil {
					*mx.fetchCo.lockloc = nil
					mx.fetchCo.lockloc = nil
				}
				mx.unschedule(&mx.fetchCo)
				mx.startup(&mx.fetchCo, 1)

//line mmmix/mmixpipe.w:6762
				if isLoadStore(mx.hot.i) {
					mx.nullifying = true
				}
			}

//line mmmix/mmixpipe.w:6740
			mx.instPtr = spec{o: mx.g[rTT].o}
		}
	}

//line mmmix/mmixpipe.w:1271
	mx.dispatchCount = 0
	mx.oldHot = mx.hot   // remember the hot seat position at beginning of cycle
	mx.oldTail = mx.tail // remember the fetch buffer contents at beginning of cycle
	mx.suppressDispatch = mx.deissues != 0 || mx.dispatchLock != nil
	if mx.doingInterrupt != 0 {

//line mmmix/mmixpipe.w:6787
		d := mx.doingInterrupt
		mx.doingInterrupt--
		switch d {
		case 3:

//line mmmix/mmixpipe.w:6800
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

//line mmmix/mmixpipe.w:6792
		case 2:

//line mmmix/mmixpipe.w:6836
			{
				hot := mx.hot
				j = int(packBytes(hot.op, int(hot.xx), int(hot.yy), int(hot.zz)))
				if hot.interrupt&hBit != 0 { // trip
					mx.g[rW].o = hot.loc + 4
					mx.g[rX].o = sign32<<32 | Octa(Tetra(j))
					if mx.verbose&issueBit != 0 {
						mx.printf(" setting rW=")
						mx.printOcta(mx.g[rW].o)
						mx.printf(", rX=")
						mx.printOcta(mx.g[rX].o)
						mx.printf("\n")
					}
				} else { // trap
					mx.g[rWW].o = hot.goLoc.o
					mx.g[rXX].o = mx.g[rXX].o&^0xffffffff | Octa(Tetra(j))

//line mmmix/mmixpipe.w:6865
					if hot.interrupt&fBit != 0 { // forced
						if hot.i != trap {
							j = resumeTrans // emulate page translation
						} else if hot.op == TRAP {
							j = 0x80 // |TRAP|
						} else if flags[hot.op]&xIsDestBit != 0 {
							j = resumeSet // emulation
						} else {
							j = 0x80 // emulation when r[X] is not a destination
						}
					} else { // dynamic
						if hot.interim {
							if hot.i == frem || hot.i == syncd || hot.i == syncid {
								j = resumeCont
							} else {
								j = resumeAgain
							}
						} else if isLoadStore(hot.i) {
							j = resumeAgain
						} else {
							j = 0x80 // normal external interruption
						}
					}

//line mmmix/mmixpipe.w:6853
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

//line mmmix/mmixpipe.w:6794
		case 1:

//line mmmix/mmixpipe.w:6890
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

//line mmmix/mmixpipe.w:6796
			mx.hot = mx.prevCtl(mx.hot)
		}

//line mmmix/mmixpipe.w:1277
	} else {

//line mmmix/mmixpipe.w:1300
		for m = mx.commitMax; m > 0 && mx.deissues > 0; m-- {

//line mmmix/mmixpipe.w:2943
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

//line mmmix/mmixpipe.w:2968
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

//line mmmix/mmixpipe.w:2955
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

//line mmmix/mmixpipe.w:1302
		}
	commit:
		for ; m > 0; m-- {
			if mx.hot == mx.cool {
				break // reorder buffer is empty
			}
			if !mx.securityDisabled {

//line mmmix/mmixpipe.w:3093
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

//line mmmix/mmixpipe.w:1310
			}
			if mx.hot.owner != nil {
				break // hot seat instruction isn't finished
			}

//line mmmix/mmixpipe.w:2985
			hot := mx.hot
			if mx.nullifying {

//line mmmix/mmixpipe.w:3051
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

//line mmmix/mmixpipe.w:2988
			} else {
				if hot.i == get && hot.zz == rQ {
					mx.newQ = mx.g[rQ].o &^ hot.x.o
				} else if hot.i == put && hot.xx == rQ {
					hot.x.o |= mx.newQ
				}
				if hot.memX {

//line mmmix/mmixpipe.w:5089
					if hot.interrupt&(fBit+0xff) == 0 {
						q := mx.writeTail
						if hot.x.addr>>32&0xffff0000 != 0 {

//line mmmix/mmixpipe.w:5115
							if hot.op >= STB && hot.op < STSF {
								q.size = (hot.op & 0xf) >> 2
							} else if hot.op >= STSF && hot.op < STCO {
								q.size = 2
							} else {
								q.size = 3
							}

//line mmmix/mmixpipe.w:5093
						}
						found := false
						if hot.i != sync {

//line mmmix/mmixpipe.w:5124
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

//line mmmix/mmixpipe.w:5097
						}
						if !found {
							p := mx.prevWrite(mx.writeTail)
							if p == mx.writeHead {
								break commit // the write buffer is full
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

//line mmmix/mmixpipe.w:2996
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

//line mmmix/mmixpipe.w:3024
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

//line mmmix/mmixpipe.w:3015
			}
			if hot.interrupt >= hBit {

//line mmmix/mmixpipe.w:6771
				if hot.interrupt&hBit == 0 {
					mx.g[rK].o = 0 // trap
				}
				if (hot.interrupt&hBit != 0 && hot.i != trip) ||
					(hot.interrupt&fBit != 0 && hot.i != trap) || hot.interrupt&eBit != 0 {
					mx.doingInterrupt = 3
					mx.suppressDispatch = true
				} else {
					mx.doingInterrupt = 2 // trip or trap started by dispatcher
				}
				break

//line mmmix/mmixpipe.w:3018
			}

//line mmmix/mmixpipe.w:1315
			i = mx.hot.i
			mx.hot = mx.prevCtl(mx.hot)
			if i == resum {
				break // allow the resumed instruction to see the new rK
			}
		}

//line mmmix/mmixpipe.w:1279
	}

//line mmmix/mmixpipe.w:2450
	mx.curTime++
	if mx.curTime == mx.ringSize {
		mx.curTime = 0
	}
	for self := mx.queuelist(mx.curTime); self != &mx.sentinel; self = mx.sentinel.next {
		mx.sentinel.next = self.next
		self.next = nil // unschedule this coroutine
		if mx.verbose&coroutineBit != 0 {
			mx.printf(" running ")
			mx.printCoroutineID(self)
			mx.printf(" ")
			mx.printControlBlock(self.ctl)
			mx.printf("\n")
		}
		if mx.step(self) { // the original's |terminate|
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
		}
	}

//line mmmix/mmixpipe.w:1281
	if !mx.suppressDispatch {

//line mmmix/mmixpipe.w:1437
		trueHead := mx.head
		if mx.head == mx.oldTail && mx.head != mx.tail {
			mx.oldTail = mx.prevFetch(mx.head)
		}
		mx.peekHist = mx.coolHist
		for j = 0; j < mx.dispatchMax+mx.peekahead; j++ {

//line mmmix/mmixpipe.w:1453
			if mx.head == mx.oldTail {
				break // fetch buffer empty
			}
			newHead := mx.prevFetch(mx.head)
			op := int(mx.head.inst >> 24)
			yz := int(mx.head.inst & 0xffff)
			var f int
			freezeDispatch := false
			var u *funcUnit
			cool := mx.cool

//line mmmix/mmixpipe.w:1539
			if mx.support[op>>5]&(sign32>>(op&31)) == 0 {
				// oops, this opcode isn't supported by any functional unit
				f, i = int(flags[TRAP]), trap
			} else {
				f, i = int(flags[op]), internalOp[op]
			}
			if i == trip && mx.head.loc&signBit != 0 {
				f, i = 0, noop
			}

//line mmmix/mmixpipe.w:1871
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

//line mmmix/mmixpipe.w:1473
			if f&relAddrBit != 0 {

//line mmmix/mmixpipe.w:1675
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

//line mmmix/mmixpipe.w:1475
			}
			if mx.head.noted {
				mx.peekHist = mx.head.hist
			} else {

//line mmmix/mmixpipe.w:1692
				{
					predicted := 0
					if op&0xe0 == 0x40 {

//line mmmix/mmixpipe.w:3156
						predicted = op & 0x10 // start with the instruction's recommendation
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

//line mmmix/mmixpipe.w:1696
					}
					mx.head.noted = true
					mx.head.hist = mx.peekHist
					if predicted != 0 || f&ctlChangeBit != 0 || (i == syncid && cool.loc&signBit == 0) {
						mx.oldTail, mx.tail = newHead, newHead // discard all remaining fetches

//line mmmix/mmixpipe.w:6086
						if mx.fetchCo.lockloc != nil {
							*mx.fetchCo.lockloc = nil
							mx.fetchCo.lockloc = nil
						}
						mx.unschedule(&mx.fetchCo)
						mx.startup(&mx.fetchCo, 1)

//line mmmix/mmixpipe.w:1702
						switch i {
						case jmp, br, pbr, pushj:
							mx.instPtr = cool.z
						case pop:
							if mx.g[rJ].up.known && j < mx.dispatchMax && mx.dispatchLock == nil &&
								!mx.nullifying {
								mx.instPtr = spec{o: mx.g[rJ].up.o + Octa(yz<<2)}
								break
							}
							fallthrough // otherwise fall through, will wait on |cool.goLoc|
						case goOp, pushgo, trap, resume, syncid:
							mx.instPtr.p = &mx.unknownSpec
						case trip:
							mx.instPtr = spec{}
						}
					}
				}

//line mmmix/mmixpipe.w:1480
			}

//line mmmix/mmixpipe.w:1464
			if j >= mx.dispatchMax || mx.dispatchLock != nil || mx.nullifying {
				mx.head = newHead
				continue // can't dispatch, but can peek ahead
			}

//line mmmix/mmixpipe.w:1483
			mx.newCool = mx.prevCtl(cool)
			stalled := true
		stall:
			for once := true; once; once = false {

//line mmmix/mmixpipe.w:1904
				if mx.newCool == mx.hot {
					break stall // reorder buffer is full
				}

//line mmmix/mmixpipe.w:1925
				if !mx.g[rL].up.known {
					break stall
				}
				mx.coolL = int(Tetra(mx.g[rL].up.o))
				if !mx.g[rG].up.known && !(op == UNSAVE && cool.xx == 1) {
					break stall
				}
				mx.coolG = int(Tetra(mx.g[rG].up.o))

//line mmmix/mmixpipe.w:1935
				if mx.resuming != 0 {

//line mmmix/mmixpipe.w:7061
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

//line mmmix/mmixpipe.w:1937
				} else {
					if f&0x10 != 0 {

//line mmmix/mmixpipe.w:1973
						if int(cool.xx) >= mx.coolG {
							cool.b = mx.specval(&mx.g[cool.xx])
						} else if int(cool.xx) < mx.coolL {
							cool.b = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx)))
						}
						if f&relAddrBit != 0 {
							cool.needB = true // |br|, |pbr|
						}

//line mmmix/mmixpipe.w:1940
					}
					if thirdOperand[op] != 0 && cool.i != trap {

//line mmmix/mmixpipe.w:2024
						if to := thirdOperand[op]; to == rA || to == rE {
							cool.needRA = true
							cool.ra = mx.specval(&mx.g[rA])
						}
						if to := thirdOperand[op]; to != rA {
							cool.needB = true
							cool.b = mx.specval(&mx.g[to])
						}

//line mmmix/mmixpipe.w:1943
					}
					if f&0x1 != 0 {
						cool.z.o = Octa(cool.zz)
					} else if f&0x2 != 0 {

//line mmmix/mmixpipe.w:1959
						if int(cool.zz) >= mx.coolG {
							cool.z = mx.specval(&mx.g[cool.zz])
						} else if int(cool.zz) < mx.coolL {
							cool.z = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.zz)))
						}

//line mmmix/mmixpipe.w:1948
					} else if op&0xf0 == 0xe0 {

//line mmmix/mmixpipe.w:2037
						cool.z.o = Octa(yz) << (48 - 16*(op&3))
						if i != set { // register X should also be the Y operand
							cool.y = cool.b
							cool.b = spec{}
						}

//line mmmix/mmixpipe.w:1950
					}
					if f&0x4 != 0 {
						cool.y.o = Octa(cool.yy)
					} else if f&0x8 != 0 {

//line mmmix/mmixpipe.w:1966
						if int(cool.yy) >= mx.coolG {
							cool.y = mx.specval(&mx.g[cool.yy])
						} else if int(cool.yy) < mx.coolL {
							cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.yy)))
						}

//line mmmix/mmixpipe.w:1955
					}
				}

//line mmmix/mmixpipe.w:1909
			dispatchDone:
				for once := true; once; once = false {
					if f&xIsDestBit != 0 {

//line mmmix/mmixpipe.w:2050
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
						} else { // we need to increase L before issuing |head.inst|

//line mmmix/mmixpipe.w:2065
							if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {

//line mmmix/mmixpipe.w:2114
								cool.needB, cool.needRA = false, false
								cool.i = incgamma
								mx.newS = mx.coolS + 1
								cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
								cool.y = spec{o: mx.coolS << 3}
								cool.z = spec{}
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
								op = STOU // this instruction needs to be handled by load/store unit
								cool.interim = true
								cool.stackAlert = cool.y.o&signBit == 0
								break dispatchDone

//line mmmix/mmixpipe.w:2067
							} else {

//line mmmix/mmixpipe.w:2098
								cool.i = incrl
								mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(mx.coolL)), &cool.x)
								cool.needB, cool.needRA = false, false
								cool.y, cool.z = spec{}, spec{}
								cool.x.known = true // |cool.x.o=0|
								mx.specInstall(&mx.g[rL], &cool.rl)
								cool.rl.o = Octa(Tetra(mx.coolL + 1))
								cool.renX, cool.setL = true, true
								op = SETH // this instruction to be handled by the simplest units
								cool.interim = true
								break dispatchDone

//line mmmix/mmixpipe.w:2069
							}

//line mmmix/mmixpipe.w:2062
						}

//line mmmix/mmixpipe.w:1913
					}
				special:
					switch i {

//line mmmix/mmixpipe.w:2175
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

//line mmmix/mmixpipe.w:2203
					case put:
						if cool.yy != 0 || cool.xx >= 32 {

//line mmmix/mmixpipe.w:2238
							cool.interrupt |= bBit
							cool.i = noop
							break special

//line mmmix/mmixpipe.w:2206
						}
						if cool.xx >= 8 {
							if cool.xx <= 11 && cool.xx != 8 {

//line mmmix/mmixpipe.w:2238
								cool.interrupt |= bBit
								cool.i = noop
								break special

//line mmmix/mmixpipe.w:2210
							}
							if cool.xx <= 18 && cool.loc&signBit == 0 {

//line mmmix/mmixpipe.w:2243
								cool.interrupt |= kBit
								cool.i = noop
								break special

//line mmmix/mmixpipe.w:2213
							}
						}
						if cool.xx == 8 || (cool.xx >= 15 && cool.xx <= 20) {
							freezeDispatch = true
						}
						cool.renX = true
						mx.specInstall(&mx.g[cool.xx], &cool.x)
					case get:
						if cool.yy != 0 || cool.zz >= 32 {

//line mmmix/mmixpipe.w:2238
							cool.interrupt |= bBit
							cool.i = noop
							break special

//line mmmix/mmixpipe.w:2223
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

//line mmmix/mmixpipe.w:2243
						cool.interrupt |= kBit
						cool.i = noop
						break special

//line mmmix/mmixpipe.w:2252
					case pushgo:
						mx.instPtr.p = &cool.goLoc
						fallthrough
					case pushj:
						x := int(cool.xx)
						if x >= mx.coolG {
							if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {

//line mmmix/mmixpipe.w:2114
								cool.needB, cool.needRA = false, false
								cool.i = incgamma
								mx.newS = mx.coolS + 1
								cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
								cool.y = spec{o: mx.coolS << 3}
								cool.z = spec{}
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
								op = STOU // this instruction needs to be handled by load/store unit
								cool.interim = true
								cool.stackAlert = cool.y.o&signBit == 0
								break dispatchDone

//line mmmix/mmixpipe.w:2260
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

//line mmmix/mmixpipe.w:2292
					case pop:
						if cool.xx != 0 && mx.coolL >= int(cool.xx) {
							cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
						}

//line mmmix/mmixpipe.w:2299
						if Tetra(mx.coolS) == Tetra(mx.coolO) {

//line mmmix/mmixpipe.w:2131
							if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
								// don't let $\gamma$ pass $\beta$
								if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
									cool.i = or             // we'll preserve the main result by moving it down
									mx.head.inst -= 0x10000 // decrease X field of \.{POP} in fetch buffer
									op = OR
									cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
									mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
								} else { // decrease rL by 1
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
								op = LDOU // this instruction needs to be handled by load/store unit
								cool.ptrA = mx.mem.up
							}
							cool.z, cool.b = spec{}, spec{}
							cool.needB = false
							cool.renX, cool.interim = true, true
							break dispatchDone

//line mmmix/mmixpipe.w:2301
						}
						{
							var x Tetra
							if p := mx.lr(Tetra(mx.coolO) - 1).up; p.known {
								x = Tetra(p.o) & 0xff
							} else {
								break stall
							}
							if Tetra(mx.coolO)-Tetra(mx.coolS) <= x {

//line mmmix/mmixpipe.w:2131
								if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
									// don't let $\gamma$ pass $\beta$
									if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
										cool.i = or             // we'll preserve the main result by moving it down
										mx.head.inst -= 0x10000 // decrease X field of \.{POP} in fetch buffer
										op = OR
										cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
										mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
									} else { // decrease rL by 1
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
									op = LDOU // this instruction needs to be handled by load/store unit
									cool.ptrA = mx.mem.up
								}
								cool.z, cool.b = spec{}, spec{}
								cool.needB = false
								cool.renX, cool.interim = true, true
								break dispatchDone

//line mmmix/mmixpipe.w:2311
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

//line mmmix/mmixpipe.w:2343
					case mulu:
						cool.renA = true
						mx.specInstall(&mx.g[rH], &cool.a)
					case div, divu:
						cool.renA = true
						mx.specInstall(&mx.g[rR], &cool.a)

//line mmmix/mmixpipe.w:2363
					case noop:
						if cool.interrupt&fBit != 0 {
							cool.goLoc.o, cool.y.o = cool.loc, cool.loc
							mx.instPtr = mx.specval(&mx.g[rT])
						}

//line mmmix/mmixpipe.w:4397
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

//line mmmix/mmixpipe.w:6675
					case trap:
						if flags[op]&xIsDestBit != 0 && int(cool.xx) < mx.coolG && int(cool.xx) >= mx.coolL {

//line mmmix/mmixpipe.w:2065
							if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {

//line mmmix/mmixpipe.w:2114
								cool.needB, cool.needRA = false, false
								cool.i = incgamma
								mx.newS = mx.coolS + 1
								cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
								cool.y = spec{o: mx.coolS << 3}
								cool.z = spec{}
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
								op = STOU // this instruction needs to be handled by load/store unit
								cool.interim = true
								cool.stackAlert = cool.y.o&signBit == 0
								break dispatchDone

//line mmmix/mmixpipe.w:2067
							} else {

//line mmmix/mmixpipe.w:2098
								cool.i = incrl
								mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(mx.coolL)), &cool.x)
								cool.needB, cool.needRA = false, false
								cool.y, cool.z = spec{}, spec{}
								cool.x.known = true // |cool.x.o=0|
								mx.specInstall(&mx.g[rL], &cool.rl)
								cool.rl.o = Octa(Tetra(mx.coolL + 1))
								cool.renX, cool.setL = true, true
								op = SETH // this instruction to be handled by the simplest units
								cool.interim = true
								break dispatchDone

//line mmmix/mmixpipe.w:2069
							}

//line mmmix/mmixpipe.w:6678
						}
						if !mx.g[rT].up.known || !mx.g[rJ].up.known {
							break stall
						}
						mx.instPtr = mx.specval(&mx.g[rT]) // traps and emulated ops
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

//line mmmix/mmixpipe.w:6930
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

//line mmmix/mmixpipe.w:8268
								if cool.loc == mx.g[rT].o {
									if xl := Tetra(mx.g[rXX].o); xl&0xffff0000 == 0 && byte(xl>>8) <= maxSysCall {
										yy, zz := byte(xl>>8), byte(xl)
										var ma, mb Octa

//line mmmix/mmixpipe.w:8403
										if argCount[yy] == 3 {
											if argLoc := mx.g[rBB].o; argLoc>>32&0x9fffffff == 0 {
												mb = mx.magicRead(magicAddr(argLoc))
											}
											if argLoc := mx.g[rBB].o + 8; argLoc>>32&0x9fffffff == 0 {
												ma = mx.magicRead(magicAddr(argLoc))
											}
										}

//line mmmix/mmixpipe.w:8273
										switch yy {
										case Halt:

//line mmmix/mmixpipe.w:8302
											if zz == 0 {
												mx.halted = true
											} else if zz == 1 {
												trapLoc := mx.g[rWW].o - 4
												if !(trapLoc>>32 != 0 || Tetra(trapLoc) >= 0xf0) {
													mx.io.PrintTripWarning(int(Tetra(trapLoc)>>4), mx.g[rW].o-4)
												}
											}

//line mmmix/mmixpipe.w:8276
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
									mx.g[255].o = negOne // this will enable interrupts
								}

//line mmmix/mmixpipe.w:6953
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

//line mmmix/mmixpipe.w:6984
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
										if (Tetra(cool.b.o)>>24)&0xfa != 0xb8 { // not |syncd| or |syncid|

//line mmmix/mmixpipe.w:7037
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

//line mmmix/mmixpipe.w:6999
										}
										again = true
									case resumeAgain:
										again = true
									case resumeTrans:

//line mmmix/mmixpipe.w:7025
										if cool.zz != 0 {
											cool.y, cool.z = mx.specval(&mx.g[rYY]), mx.specval(&mx.g[rZZ])
											if Tetra(cool.b.o)>>24 != SWYM {
												again = true
												break
											}
											cool.i = resume // see ``subtle point'' above
											break
										}
										bad = true

//line mmmix/mmixpipe.w:7005
									default:
										bad = true
									}

//line mmmix/mmixpipe.w:7012
									if again {

//line mmmix/mmixpipe.w:7049
										mx.head.inst = Tetra(cool.b.o)
										m = int(mx.head.inst >> 24)
										if m == RESUME {
											bad = true // avoid uninterruptible loop
										} else {
											if cool.zz == 0 && m > RESUME && m <= SYNC && mx.head.inst&badInstMask[m-RESUME] != 0 {
												mx.head.interrupt |= bBit
											}
											mx.head.noted = false
										}

//line mmmix/mmixpipe.w:7014
									}
									if bad {
										cool.interrupt |= bBit
										cool.i = noop
										mx.resuming = 0
									}

//line mmmix/mmixpipe.w:7009
								}

//line mmmix/mmixpipe.w:6967
							}
						}

//line mmmix/mmixpipe.w:7271
					case unsave:
						if cool.interrupt&bBit != 0 {
							cool.i = noop
						} else {
							cool.interim = true
							op = LDOU // this instruction needs to be handled by load/store unit
							cool.i = unsav
							switch cool.xx {
							case 0:
								if cool.z.p != nil {
									break stall
								}

//line mmmix/mmixpipe.w:7304
								cool.renX = true
								mx.specInstall(&mx.g[rG], &cool.x)
								cool.renA = true
								mx.specInstall(&mx.g[rA], &cool.a)
								mx.newO = cool.z.o >> 3
								mx.newS = mx.newO
								cool.setL = true
								mx.specInstall(&mx.g[rL], &cool.rl)
								cool.ptrA = mx.mem.up

//line mmmix/mmixpipe.w:7284
							case 1, 2:

//line mmmix/mmixpipe.w:7296
								cool.renX = true
								mx.specInstall(&mx.g[cool.yy], &cool.x)
								mx.newO = mx.coolO - 1
								mx.newS = mx.newO
								cool.z.o = mx.newO << 3
								cool.ptrA = mx.mem.up

//line mmmix/mmixpipe.w:7286
							case 3:
								cool.i, cool.interim, op = unsave, false, UNSAVE

//line mmmix/mmixpipe.w:2299
								if Tetra(mx.coolS) == Tetra(mx.coolO) {

//line mmmix/mmixpipe.w:2131
									if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
										// don't let $\gamma$ pass $\beta$
										if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
											cool.i = or             // we'll preserve the main result by moving it down
											mx.head.inst -= 0x10000 // decrease X field of \.{POP} in fetch buffer
											op = OR
											cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
											mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
										} else { // decrease rL by 1
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
										op = LDOU // this instruction needs to be handled by load/store unit
										cool.ptrA = mx.mem.up
									}
									cool.z, cool.b = spec{}, spec{}
									cool.needB = false
									cool.renX, cool.interim = true, true
									break dispatchDone

//line mmmix/mmixpipe.w:2301
								}
								{
									var x Tetra
									if p := mx.lr(Tetra(mx.coolO) - 1).up; p.known {
										x = Tetra(p.o) & 0xff
									} else {
										break stall
									}
									if Tetra(mx.coolO)-Tetra(mx.coolS) <= x {

//line mmmix/mmixpipe.w:2131
										if Tetra(mx.coolO)+Tetra(mx.coolL) == Tetra(mx.coolS)+Tetra(mx.lringSize) {
											// don't let $\gamma$ pass $\beta$
											if cool.i == pop && int(cool.xx) == mx.coolL && mx.coolL > 1 {
												cool.i = or             // we'll preserve the main result by moving it down
												mx.head.inst -= 0x10000 // decrease X field of \.{POP} in fetch buffer
												op = OR
												cool.y = mx.specval(mx.lr(Tetra(mx.coolO) + Tetra(cool.xx) - 1))
												mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(cool.xx)-2), &cool.x)
											} else { // decrease rL by 1
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
											op = LDOU // this instruction needs to be handled by load/store unit
											cool.ptrA = mx.mem.up
										}
										cool.z, cool.b = spec{}, spec{}
										cool.needB = false
										cool.renX, cool.interim = true, true
										break dispatchDone

//line mmmix/mmixpipe.w:2311
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

//line mmmix/mmixpipe.w:7289
							default:
								cool.interim, cool.i = false, noop
								cool.interrupt |= bBit
							}
						} // this takes us to |dispatchDone|

//line mmmix/mmixpipe.w:7351
					case save:
						if int(cool.xx) < mx.coolG {
							cool.interrupt |= bBit
						}
						if cool.interrupt&bBit != 0 {
							cool.i = noop
						} else if (Tetra(mx.coolS)-Tetra(mx.coolO)-Tetra(mx.coolL)-1)&Tetra(mx.lringMask) == 0 {

//line mmmix/mmixpipe.w:2114
							cool.needB, cool.needRA = false, false
							cool.i = incgamma
							mx.newS = mx.coolS + 1
							cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
							cool.y = spec{o: mx.coolS << 3}
							cool.z = spec{}
							cool.memX = true
							mx.specInstall(&mx.mem, &cool.x)
							op = STOU // this instruction needs to be handled by load/store unit
							cool.interim = true
							cool.stackAlert = cool.y.o&signBit == 0
							break dispatchDone

//line mmmix/mmixpipe.w:7359
						} else {
							cool.interim = true
							cool.i = sav
							switch cool.zz {
							case 0:

//line mmmix/mmixpipe.w:7385
								cool.zz = 1
								cool.renX = true
								mx.specInstall(mx.lr(Tetra(mx.coolO)+Tetra(mx.coolL)), &cool.x)
								cool.x.known, cool.x.o = true, Octa(Tetra(mx.coolL))
								cool.setL = true
								mx.specInstall(&mx.g[rL], &cool.rl)
								mx.newO = mx.coolO + Octa(mx.coolL+1)

//line mmmix/mmixpipe.w:7365
							case 1:
								if Tetra(mx.coolO) != Tetra(mx.coolS) {

//line mmmix/mmixpipe.w:2114
									cool.needB, cool.needRA = false, false
									cool.i = incgamma
									mx.newS = mx.coolS + 1
									cool.b = mx.specval(mx.lr(Tetra(mx.coolS)))
									cool.y = spec{o: mx.coolS << 3}
									cool.z = spec{}
									cool.memX = true
									mx.specInstall(&mx.mem, &cool.x)
									op = STOU // this instruction needs to be handled by load/store unit
									cool.interim = true
									cool.stackAlert = cool.y.o&signBit == 0
									break dispatchDone

//line mmmix/mmixpipe.w:7368
								}
								cool.zz = 2
								cool.yy = byte(mx.coolG)
								fallthrough
							case 2, 3:

//line mmmix/mmixpipe.w:7394
								op = STOU // this instruction needs to be handled by load/store unit
								cool.memX = true
								mx.specInstall(&mx.mem, &cool.x)
								cool.z.o = mx.coolO << 3
								mx.newO = mx.coolO + 1
								mx.newS = mx.newO
								if cool.zz == 3 && cool.yy > rZ {

//line mmmix/mmixpipe.w:7409
									cool.i = save
									cool.interim = false
									cool.renA = true
									mx.specInstall(&mx.g[cool.xx], &cool.a)

//line mmmix/mmixpipe.w:7402
								} else {
									cool.b = mx.specval(&mx.g[cool.yy])
								}

//line mmmix/mmixpipe.w:7374
							default:
								cool.interim, cool.i = false, noop
								cool.interrupt |= bBit
							}
						}

//line mmmix/mmixpipe.w:7642
					case fsqrt, fint, fix, flot:
						if Tetra(cool.y.o) > 4 {

//line mmmix/mmixpipe.w:2238
							cool.interrupt |= bBit
							cool.i = noop
							break special

//line mmmix/mmixpipe.w:7645
						}

//line mmmix/mmixpipe.w:7821
					case sync:
						if cool.zz > 3 {
							if cool.loc&signBit == 0 {

//line mmmix/mmixpipe.w:2243
								cool.interrupt |= kBit
								cool.i = noop
								break special

//line mmmix/mmixpipe.w:7825
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

//line mmmix/mmixpipe.w:1917
					}
				}

//line mmmix/mmixpipe.w:1488

//line mmmix/mmixpipe.w:1594
				{
					t, b := op>>5, Tetra(sign32)>>(op&31)
					found := false
					if cool.i == trap && op != TRAP { // opcode needs to be emulated
						u = &mx.funit[mx.funitCount] // this unit supports just \.{TRIP} and \.{TRAP}
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
						break stall // all units for this |op| are busy
					}
				}

//line mmmix/mmixpipe.w:1489

//line mmmix/mmixpipe.w:2072
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

//line mmmix/mmixpipe.w:1490
				if op&0xe0 == 0x40 {

//line mmmix/mmixpipe.w:3182
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
							cool.i = pbr + br - cool.i // reverse the sense
							mx.bpRevStat++
						} else {
							mx.bpTable[m] = int8(hUp)
							cool.x.o = Octa(Tetra(hDown)) // go with the flow
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

//line mmmix/mmixpipe.w:1492
				}

//line mmmix/mmixpipe.w:1550
				if cool.interim {
					cool.usage = false
					if cool.op == SAVE {

//line mmmix/mmixpipe.w:7415
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

//line mmmix/mmixpipe.w:1554
					} else if cool.op == UNSAVE {

//line mmmix/mmixpipe.w:7315
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

//line mmmix/mmixpipe.w:1556
					} else if cool.i == preld || cool.i == prest {

//line mmmix/mmixpipe.w:4424
						mx.head.inst = (mx.head.inst &^ (Tetra(mx.Dcache.bb-1) << 16)) - 0x10000

//line mmmix/mmixpipe.w:1558
					} else if cool.i == prego {

//line mmmix/mmixpipe.w:4427
						mx.head.inst = (mx.head.inst &^ (Tetra(mx.Icache.bb-1) << 16)) - 0x10000

//line mmmix/mmixpipe.w:1560
					}
				} else if cool.i <= maxRealCommand {
					if flags[cool.op]&ctlChangeBit != 0 || cool.i == pbr {
						if mx.instPtr.p == nil && mx.instPtr.o&signBit != 0 && cool.loc&signBit == 0 &&
							cool.i != trap {
							cool.interrupt |= pBit // jumping from nonnegative to negative
						}
					}
					trueHead, mx.head = newHead, newHead // delete instruction from fetch buffer
					mx.resuming = 0
				}
				if freezeDispatch {
					setLock(&u.co[0], &mx.dispatchLock)
				}
				cool.owner = &u.co[0]
				u.co[0].ctl = cool
				mx.startup(&u.co[0], 1) // schedule execution of the new inst
				if mx.verbose&issueBit != 0 {
					mx.printf("Issuing ")
					mx.printControlBlock(cool)
					mx.printf(" ")
					mx.printCoroutineID(&u.co[0])
					mx.printf("\n")
				}
				mx.dispatchCount++

//line mmmix/mmixpipe.w:1494
				stalled = false
			}
			if stalled {

//line mmmix/mmixpipe.w:2370
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

//line mmmix/mmixpipe.w:1498
			}
			mx.cool = mx.newCool
			mx.coolO, mx.coolS = mx.newO, mx.newS
			mx.coolHist = mx.peekHist

//line mmmix/mmixpipe.w:1444
		}
		mx.head = trueHead

//line mmmix/mmixpipe.w:1283
	}
	mx.ticks++ // and the beat moves on
	mx.dispatchStat[mx.dispatchCount]++
}

//line mmmix/mmixpipe.w:1362
func (mx *machine) prevFetch(p *fetch) *fetch {
	if p == mx.fetchBot {
		return mx.fetchTop
	}
	return &mx.fetchBuf[p.idx-1]
}

//line mmmix/mmixpipe.w:1383
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

//line mmmix/mmixpipe.w:1795
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

//line mmmix/mmixpipe.w:1819
func (mx *machine) specval(r *specnode) spec {
	if r.up.known {
		return spec{o: r.up.o}
	}
	return spec{p: r.up}
}

//line mmmix/mmixpipe.w:1829
func (mx *machine) specInstall(r, t *specnode) { // insert |t| into list |r|
	t.up = r.up
	t.up.down = t
	r.up = t
	t.down = r
	t.addr = r.addr
}

//line mmmix/mmixpipe.w:1840
func specRem(t *specnode) { // remove |t| from its list
	u, d := t.up, t.down
	u.down = d
	d.up = u
}

//line mmmix/mmixpipe.w:1866
func (mx *machine) lr(t Tetra) *specnode {
	return &mx.l[int(t)&mx.lringMask]
}

//line mmmix/mmixpipe.w:2087
func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

//line mmmix/mmixpipe.w:2431
func (mx *machine) wait(self *coroutine, t int) bool {
	mx.schedule(self, t, self.ctl.state)
	return false
}

func (mx *machine) passAfter(self *coroutine, t int) {
	mx.schedule(self.succ, t, self.ctl.state)
}

func (mx *machine) sleep(self *coroutine) bool { // wait forever
	self.next = self
	return false
}

func (mx *machine) awaken(c *coroutine, t int) {
	mx.schedule(c, t, c.ctl.state)
}

//line mmmix/mmixpipe.w:2479
func (mx *machine) step(self *coroutine) bool {
	data := self.ctl
	var (
		i, j int
		p, q *cacheblock
		c    *cache
		cc   *coroutine
		co   []coroutine
		pc   label

//line mmmix/mmixpipe.w:4115
		blockDiff int // bytes still to be read in |flushToS|

//line mmmix/mmixpipe.w:2489
	)
	switch self.stage {
	case 0:
		pc = lSwitch0
	case 1:
		pc = lSwitch1
	default:
		pc = lSwitch2

//line mmmix/mmixpipe.w:2562
	case vanish:
		return true

//line mmmix/mmixpipe.w:4043
	case flushToMem:
		c = data.ptrA.(*cache)
		pc = flushMemSt + label(data.state)

//line mmmix/mmixpipe.w:4108
	case flushToS:
		c = data.ptrA.(*cache)
		blockDiff = mx.Scache.bb - c.outbuf.rank
		p, _ = data.ptrB.(*cacheblock)
		pc = flushSSt + label(data.state)

//line mmmix/mmixpipe.w:4241
	case fillFromMem:
		c = data.ptrA.(*cache)
		cc = c.fillLock
		pc = fillMemSt + label(data.state)

//line mmmix/mmixpipe.w:4297
	case fillFromS:
		c = data.ptrA.(*cache)
		cc = c.fillLock
		p, _ = data.ptrC.(*cacheblock)
		pc = fillSSt + label(data.state)

//line mmmix/mmixpipe.w:4458
	case cleanup:
		p, _ = data.ptrB.(*cacheblock)
		pc = cleanupSt + label(data.state)

//line mmmix/mmixpipe.w:4762
	case fillFromVirt:
		c = data.ptrA.(*cache)
		cc = c.fillLock
		co = data.ptrC.([]coroutine) // |IPTco| or |DPTco|
		pc = fillVirtSt + label(data.state)

//line mmmix/mmixpipe.w:5143
	case writeFromWbuf:
		p, _ = data.ptrB.(*cacheblock)
		pc = writeSt + label(data.state)

//line mmmix/mmixpipe.w:2498
	}
	for {
		switch pc {

//line mmmix/mmixpipe.w:6128
		case lSwitch0:
			pc = fetchSt + label(data.state)
			continue
		case lNewFetch:
			data.state = 0

//line mmmix/mmixpipe.w:6169
			if mx.instPtr.p != nil {
				if mx.instPtr.p != &mx.unknownSpec && mx.instPtr.p.known {
					mx.instPtr.o, mx.instPtr.p = mx.instPtr.p.o, nil
				}
				return mx.wait(self, 1)
			}

//line mmmix/mmixpipe.w:6134
			data.y.o = mx.instPtr.o
			data.state = 1
			data.interrupt = 0
			data.x.o, data.z.o = 0, 0
			fallthrough
		case lStartFetch:
			if data.y.o&signBit != 0 {

//line mmmix/mmixpipe.w:6267
				if data.i == prego && data.loc&signBit == 0 {
					pc = lFinEx
					continue
				}
				data.z.o = data.y.o - signBit
				pc = lKnownPhys
				continue

//line mmmix/mmixpipe.w:6142
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

//line mmmix/mmixpipe.w:6187
			p = mx.cacheSearch(mx.ITcache, mx.transKey(data.y.o))
			if mx.Icache == nil || mx.Icache.lock != nil {

//line mmmix/mmixpipe.w:6250
				if p != nil {

//line mmmix/mmixpipe.w:6232
					p = mx.useAndFix(mx.ITcache, p)
					if Tetra(p.data[0])&(pxBit>>protOffset) == 0 {
						pc = lBadFetch
						continue
					}

//line mmmix/mmixpipe.w:6252
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

//line mmmix/mmixpipe.w:6190
			}
			if j = getReader(mx.Icache); j < 0 {

//line mmmix/mmixpipe.w:6250
				if p != nil {

//line mmmix/mmixpipe.w:6232
					p = mx.useAndFix(mx.ITcache, p)
					if Tetra(p.data[0])&(pxBit>>protOffset) == 0 {
						pc = lBadFetch
						continue
					}

//line mmmix/mmixpipe.w:6252
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

//line mmmix/mmixpipe.w:6193
			}
			mx.startup(&mx.Icache.reader[j], mx.Icache.accessTime)
			if p != nil {

//line mmmix/mmixpipe.w:6232
				p = mx.useAndFix(mx.ITcache, p)
				if Tetra(p.data[0])&(pxBit>>protOffset) == 0 {
					pc = lBadFetch
					continue
				}

//line mmmix/mmixpipe.w:6208
				data.z.o = mx.physAddr(data.y.o, p.data[0])
				if mx.Icache.b+mx.Icache.c > mx.pageS &&
					(Tetra(data.y.o)^Tetra(data.z.o))&Tetra((mx.Icache.bb<<mx.Icache.c)-(1<<mx.pageS)) != 0 {
					data.state = itHit // spurious I-cache lookup
				} else {

//line mmmix/mmixpipe.w:6222
					q = mx.cacheSearch(mx.Icache, data.z.o)
					if q != nil {
						q = mx.useAndFix(mx.Icache, q)

//line mmmix/mmixpipe.w:6241
						if data.i != prego {
							for j = 0; j < mx.Icache.bb>>3; j++ {
								mx.fetched[j] = q.data[j]
							}
							mx.fetchLo = int(Tetra(mx.instPtr.o)&Tetra(mx.Icache.bb-1)) >> 3
							mx.fetchHi = mx.Icache.bb >> 3
						}

//line mmmix/mmixpipe.w:6226
						data.state = fetchReady
					} else {
						data.state = iHitAndMiss
					}

//line mmmix/mmixpipe.w:6214
				}
				if mx.waitOrPass(self, max(mx.ITcache.accessTime, mx.Icache.accessTime)) {
					pc = lPassit
					continue
				}
				return false

//line mmmix/mmixpipe.w:6197
			} else {
				data.state = itMiss
			}

//line mmmix/mmixpipe.w:6155
			if mx.waitOrPass(self, mx.ITcache.accessTime) {
				pc = lPassit
				continue
			}
			return false

//line mmmix/mmixpipe.w:6276
		case lKnownPhys:
			if data.z.o>>32&0xffff0000 != 0 {
				pc = lBadFetch
				continue
			}
			if mx.Icache == nil {

//line mmmix/mmixpipe.w:6309
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

//line mmmix/mmixpipe.w:6283
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

//line mmmix/mmixpipe.w:6222
			q = mx.cacheSearch(mx.Icache, data.z.o)
			if q != nil {
				q = mx.useAndFix(mx.Icache, q)

//line mmmix/mmixpipe.w:6241
				if data.i != prego {
					for j = 0; j < mx.Icache.bb>>3; j++ {
						mx.fetched[j] = q.data[j]
					}
					mx.fetchLo = int(Tetra(mx.instPtr.o)&Tetra(mx.Icache.bb-1)) >> 3
					mx.fetchHi = mx.Icache.bb >> 3
				}

//line mmmix/mmixpipe.w:6226
				data.state = fetchReady
			} else {
				data.state = iHitAndMiss
			}

//line mmmix/mmixpipe.w:6302
			if mx.waitOrPass(self, mx.Icache.accessTime) {
				pc = lPassit
				continue
			}
			return false

//line mmmix/mmixpipe.w:6333
		case fetchSt + itMiss:
			if mx.ITcache.filler.next != nil {
				if data.i == prego {
					pc = lFinEx
					continue
				}
				return mx.wait(self, 1)
			}
			if mx.noHardwarePT || mx.pageF != 0 {

//line mmmix/mmixpipe.w:6482
				if mx.cacheSearch(mx.ITcache, mx.transKey(mx.instPtr.o)) != nil {
					pc = lNewFetch
					continue
				}
				data.interrupt |= fBit
				mx.sleepy = true
				pc = lSwymOne
				continue

//line mmmix/mmixpipe.w:6343
			}
			p = mx.allocSlot(mx.ITcache, mx.transKey(data.y.o))
			if p == nil { // hey, it was present after all
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

//line mmmix/mmixpipe.w:6365
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

//line mmmix/mmixpipe.w:6390
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

//line mmmix/mmixpipe.w:6427
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
			mx.fetched[0] = data.x.o // a ``preview'' of the new cache data
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

//line mmmix/mmixpipe.w:6458
			newFetch := false
			for j = 0; j < mx.fetchMax; j++ {
				newTail := mx.prevFetch(mx.tail)
				if newTail == mx.head {
					break // fetch buffer is full
				}

//line mmmix/mmixpipe.w:6498
				mx.tail.loc = mx.instPtr.o
				if mx.instPtr.o&4 != 0 {
					mx.tail.inst = Tetra(mx.fetched[mx.fetchLo])
					mx.fetchLo++
				} else {
					mx.tail.inst = Tetra(mx.fetched[mx.fetchLo] >> 32)
				}

//line mmmix/mmixpipe.w:6507
				mx.tail.interrupt = data.interrupt
				i = int(mx.tail.inst >> 24)
				if i >= RESUME && i <= SYNC && mx.tail.inst&badInstMask[i-RESUME] != 0 {
					mx.tail.interrupt |= bBit
				}
				mx.tail.noted = false
				if mx.instPtr.o == mx.breakpoint {
					mx.breakpointHit = true
				}

//line mmmix/mmixpipe.w:6465
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

//line mmmix/mmixpipe.w:6455
			return mx.wait(self, 1)

//line mmmix/mmixpipe.w:2502

//line mmmix/mmixpipe.w:2614
		case lSwitch1:
			pc = stage1St + label(data.state)
			continue
		case stage1St + 0:

//line mmmix/mmixpipe.w:2632
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

//line mmmix/mmixpipe.w:2658
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

//line mmmix/mmixpipe.w:2650
			if j < 10 {
				data.state = 1
			}
			if j != 0 {
				return mx.wait(self, 1) // otherwise we fall through to |case 1|
			}

//line mmmix/mmixpipe.w:2619
			fallthrough
		case stage1St + 1:

//line mmmix/mmixpipe.w:2687
			switch data.i {

//line mmmix/mmixpipe.w:2787
			case set:
				data.x.o = data.z.o

//line mmmix/mmixpipe.w:2793
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

//line mmmix/mmixpipe.w:2815
			case addu:
				if data.op&0xf8 == 0x28 {
					data.x.o = data.y.o<<(1+((data.op>>1)&0x3)) + data.z.o
				} else {
					data.x.o = data.y.o + data.z.o
				}
			case subu:
				data.x.o = data.y.o - data.z.o

//line mmmix/mmixpipe.w:2830
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

//line mmmix/mmixpipe.w:2849
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

//line mmmix/mmixpipe.w:2879
			case mux:
				data.x.o = data.y.o&data.b.o | data.z.o&^data.b.o

//line mmmix/mmixpipe.w:2887
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

//line mmmix/mmixpipe.w:7452
			case mulu:
				data.a.o, data.x.o = bits.Mul64(data.y.o, data.z.o)

//line mmmix/mmixpipe.w:7482
				{
					aux := data.z.o
					for j = mul0; aux != 0; j++ {
						aux >>= 8
					}
					data.i = j // |j| is |mul0| or |mul1| or \dots~or |mul8|
				}

//line mmmix/mmixpipe.w:7455
			case mul:
				{
					x, overflow := mmixarith.SignedMult(data.y.o, data.z.o)
					data.x.o = x
					if overflow {
						data.interrupt |= vBit
					}
				}

//line mmmix/mmixpipe.w:7482
				{
					aux := data.z.o
					for j = mul0; aux != 0; j++ {
						aux >>= 8
					}
					data.i = j // |j| is |mul0| or |mul1| or \dots~or |mul8|
				}

//line mmmix/mmixpipe.w:7464
			case divu:
				data.x.o, data.a.o = mmixarith.Div(data.b.o, data.y.o, data.z.o)
				data.i = div
			case div:
				if data.z.o == 0 {
					data.interrupt |= dBit
					data.a.o = data.y.o
					data.i = set // divide by zero needn't wait in the pipeline
				} else {
					q, r, overflow := mmixarith.SignedDiv(data.y.o, data.z.o)
					data.x.o = q
					if overflow {
						data.interrupt |= vBit
					}
					data.a.o = r
				}

//line mmmix/mmixpipe.w:7496
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

//line mmmix/mmixpipe.w:7528
			case zset:
				if registerTruth(data.y.o, data.op) != 0 {
					data.x.o = data.z.o
				} // otherwise |data.x.o| is already zero
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

//line mmmix/mmixpipe.w:7584
			case fadd, fsub, fmul, fdiv, fsqrt, fint, fix:
				entry := 0 // 0 for |fin_bflot|, 1 for |fin_uflot|, 2 for |fin_flot|
				mx.setRound(data)
				switch data.i {

//line mmmix/mmixpipe.w:7615
				case fadd:
					data.x.o, mx.exceptions = mmixarith.FPlus(data.y.o, data.z.o, mx.curRound)
				case fsub:
					data.a.o = data.z.o
					if mmixarith.FComp(data.z.o, 0) != 2 {
						data.a.o ^= signBit
					}
					data.x.o, mx.exceptions = mmixarith.FPlus(data.y.o, data.a.o, mx.curRound)
					data.i = fadd // use pipeline times for addition
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
						mx.exceptions &^= wBit // unsigned case doesn't overflow
					}
					entry = 2

//line mmmix/mmixpipe.w:7589
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

//line mmmix/mmixpipe.w:7653
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

//line mmmix/mmixpipe.w:7694
					if j == 1 {
						data.x.o = 1
					} else if j == 2 {
						data.interrupt |= iBit
					}

//line mmmix/mmixpipe.w:7667
				case data.op == FCMPE && j != 0:
					if j == 2 {
						data.interrupt |= iBit
					}
				default:

//line mmmix/mmixpipe.w:7686
					j = mmixarith.FComp(data.y.o, data.z.o)
					if j < 0 {
						data.x.o = negOne
					} else {

//line mmmix/mmixpipe.w:7694
						if j == 1 {
							data.x.o = 1
						} else if j == 2 {
							data.interrupt |= iBit
						}

//line mmmix/mmixpipe.w:7691
					}

//line mmmix/mmixpipe.w:7673
				}
			case fcmp:

//line mmmix/mmixpipe.w:7686
				j = mmixarith.FComp(data.y.o, data.z.o)
				if j < 0 {
					data.x.o = negOne
				} else {

//line mmmix/mmixpipe.w:7694
					if j == 1 {
						data.x.o = 1
					} else if j == 2 {
						data.interrupt |= iBit
					}

//line mmmix/mmixpipe.w:7691
				}

//line mmmix/mmixpipe.w:7676
			case funeq:
				want := 0
				if data.op == FUN {
					want = 2
				}
				if mmixarith.FComp(data.y.o, data.z.o) == want {
					data.x.o = 1
				}

//line mmmix/mmixpipe.w:7707
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

//line mmmix/mmixpipe.w:5344
			case preld, prest, prego:
				{
					bb := mx.Dcache.bb
					if data.i == prego {
						bb = mx.Icache.bb
					}
					data.z.o += Octa(int(data.xx) & -bb) // (I hope the adder is fast enough)
				}
				fallthrough
			case ld, ldunc, ldvts, st, pst, syncd, syncid:

//line mmmix/mmixpipe.w:5364
				data.y.o += data.z.o
				data.state = ldStLaunch
				pc = lSwitch1
				continue

//line mmmix/mmixpipe.w:5355
			case ldptp, ldpte:
				if data.y.o>>32 != 0 {

//line mmmix/mmixpipe.w:5364
					data.y.o += data.z.o
					data.state = ldStLaunch
					pc = lSwitch1
					continue

//line mmmix/mmixpipe.w:5358
				}
				data.x.o, data.x.known = 0, true
				pc = lDie // page table fault
				continue

//line mmmix/mmixpipe.w:3246
			case br, pbr:
				j = registerTruth(data.b.o, data.op)
				if j != 0 {
					data.goLoc.o = data.z.o
				} else {
					data.goLoc.o = data.y.o
				}
				if (j != 0) == (data.i == pbr) {
					mx.bpGoodStat++
				} else { // oops, misprediction
					mx.bpBadStat++

//line mmmix/mmixpipe.w:3305
					i = mx.issuedBetween(data, mx.cool)
					if i < mx.deissues {
						pc = lDie
						continue
					}
					mx.deissues = i
					mx.oldTail, mx.tail = mx.head, mx.head // clear the fetch buffer
					mx.resuming = 0

//line mmmix/mmixpipe.w:6086
					if mx.fetchCo.lockloc != nil {
						*mx.fetchCo.lockloc = nil
						mx.fetchCo.lockloc = nil
					}
					mx.unschedule(&mx.fetchCo)
					mx.startup(&mx.fetchCo, 1)

//line mmmix/mmixpipe.w:3314
					mx.instPtr = spec{o: data.goLoc.o}
					if data.loc&signBit == 0 {
						if mx.instPtr.o&signBit != 0 {
							data.interrupt |= pBit
						} else {
							data.interrupt &^= pBit
						}
					}
					if mx.bpTable != nil {
						mx.bpTable[data.x.o>>32] = int8(data.x.o) // this is what we should have stored
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

//line mmmix/mmixpipe.w:3258
				}
				pc = lFinEx
				continue

//line mmmix/mmixpipe.w:6703
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

//line mmmix/mmixpipe.w:7082
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

//line mmmix/mmixpipe.w:7123
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

//line mmmix/mmixpipe.w:7159
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

//line mmmix/mmixpipe.w:7174
			case put:
				if data.xx == 8 || (data.xx >= 15 && data.xx <= 20) {
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}
					switch data.xx {
					case rV:

//line mmmix/mmixpipe.w:4814
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

//line mmmix/mmixpipe.w:7182
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

//line mmmix/mmixpipe.w:7208
						if data.z.o>>32 != 0 || Tetra(data.z.o) >= 256 ||
							Tetra(data.z.o) < Tetra(mx.g[rL].o) || Tetra(data.z.o) < 32 {
							data.interrupt |= bBit
							data.z.o = mx.g[rG].o
						} else if Tetra(data.z.o) < Tetra(mx.g[rG].o) {
							data.interim = true // potentially interruptible
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

//line mmmix/mmixpipe.w:7193
					}
				} else if data.xx == rA && (data.z.o>>32 != 0 || Tetra(data.z.o) >= 0x40000) {
					data.interrupt |= bBit
					data.z.o &= 0x3ffff
				}
				data.x.o = data.z.o
				pc = lFinEx
				continue

//line mmmix/mmixpipe.w:7236
			case goOp:
				data.x.o = data.goLoc.o

//line mmmix/mmixpipe.w:7247
				data.goLoc.o = data.y.o + data.z.o
				if data.goLoc.o&signBit != 0 && data.loc&signBit == 0 {
					data.interrupt |= pBit
				}
				data.goLoc.known = true
				pc = lFinEx
				continue

//line mmmix/mmixpipe.w:7239
			case pop:
				data.x.o = data.y.o
				data.y.o = data.b.o // move rJ to |y| field
				fallthrough
			case pushgo:

//line mmmix/mmixpipe.w:7247
				data.goLoc.o = data.y.o + data.z.o
				if data.goLoc.o&signBit != 0 && data.loc&signBit == 0 {
					data.interrupt |= pBit
				}
				data.goLoc.known = true
				pc = lFinEx
				continue

//line mmmix/mmixpipe.w:7842
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

//line mmmix/mmixpipe.w:7877
					for k := data; k != mx.hot; {
						k = mx.nextCtl(k)
						if k.owner != nil && (k.i == ld || k.i == ldunc || k.i == pst) {
							return mx.wait(self, 1)
						}
					}

//line mmmix/mmixpipe.w:7853
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

//line mmmix/mmixpipe.w:7979
					if self.lockloc != nil {
						*self.lockloc = nil
						self.lockloc = nil
					}

//line mmmix/mmixpipe.w:7997
					if mx.writeHead != mx.writeTail {
						if mx.speedLock == nil {
							setLock(self, &mx.speedLock)
						}
						return mx.wait(self, 1)
					}

//line mmmix/mmixpipe.w:7984
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

//line mmmix/mmixpipe.w:7864
				case 6:
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}

//line mmmix/mmixpipe.w:7887
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

//line mmmix/mmixpipe.w:7869
				case 7:
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}

//line mmmix/mmixpipe.w:7900
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

//line mmmix/mmixpipe.w:7874
				}

//line mmmix/mmixpipe.w:2691
			}

//line mmmix/mmixpipe.w:2705
			data.state = 3
			if data.i <= maxPipeOp {
				s := &mx.pipeSeq[data.i]
				j = int(s[0]) + data.denin
				if s[1] != 0 {
					data.state = 2 // more than one stage
				} else {
					j += data.denout
				}
				if j > 1 {
					return mx.wait(self, j-1)
				}
			}
			pc = lSwitch1
			continue

//line mmmix/mmixpipe.w:2622
		case lPassData:

//line mmmix/mmixpipe.w:2727
			if self.succ.next != nil {
				return mx.wait(self, 1) // stall if the next stage is occupied
			}
			{
				s := &mx.pipeSeq[data.i]
				j = int(s[self.stage])
				if s[self.stage+1] == 0 {
					j += data.denout
					data.state = 3 // the next stage is the last
				}
				mx.passAfter(self, j)
			}
			fallthrough
		case lPassit:
			self.succ.ctl = data
			data.owner = self.succ
			return false

//line mmmix/mmixpipe.w:2624
		case lFinEx:

//line mmmix/mmixpipe.w:2910
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
				data.ra.o &^= 0xffffffff // no trips enabled for the operating system
			}
			if data.interrupt&0xffff != 0 {

//line mmmix/mmixpipe.w:6565
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

//line mmmix/mmixpipe.w:6589
					i = mx.issuedBetween(data, mx.cool)
					if i < mx.deissues {
						pc = lDie
						continue
					}
					mx.deissues = i
					mx.oldTail, mx.tail = mx.head, mx.head // clear the fetch buffer
					mx.resuming = 0

//line mmmix/mmixpipe.w:6086
					if mx.fetchCo.lockloc != nil {
						*mx.fetchCo.lockloc = nil
						mx.fetchCo.lockloc = nil
					}
					mx.unschedule(&mx.fetchCo)
					mx.startup(&mx.fetchCo, 1)

//line mmmix/mmixpipe.w:6598
					mx.coolHist = data.hist
					m := 16
					for i = j & int(Tetra(data.ra.o)); i&dBit == 0; i <<= 1 {
						m += 16
					}
					data.arithExc |= Tetra(j&^(0x10000>>(m>>4))) >> 8 // trips taken are not logged as events
					data.goLoc.o = Octa(m)
					mx.instPtr = spec{o: data.goLoc.o}
					data.interrupt |= hBit
					pc = lState4
					continue

//line mmmix/mmixpipe.w:6577
				}
				if data.interrupt&0xff != 0 {
					pc = lState5
					continue
				}

//line mmmix/mmixpipe.w:2926
			}
			fallthrough
		case lDie:
			data.owner = nil
			return true // this coroutine now fades away

//line mmmix/mmixpipe.w:5392
		case stage1St + ldStLaunch:
			if self.succ.next != nil {
				return mx.wait(self, 1) // second stage must be clear
			}

//line mmmix/mmixpipe.w:6163
			if data.i == prego {
				pc = lStartFetch
				continue
			}

//line mmmix/mmixpipe.w:7757
			if data.i == ldvts {

//line mmmix/mmixpipe.w:7762
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
				p = mx.cacheSearch(mx.DTcache, data.y.o) // N.B.: Not |transKey(data.y.o)|
				if p != nil {
					data.x.o = data.x.o&^0xffffffff | 2
					c = mx.DTcache

//line mmmix/mmixpipe.w:7787
					if Tetra(data.z.o) != 0 {
						p = mx.useAndFix(c, p)
						p.data[0] = p.data[0]&^0xffffffff | Octa(Tetra(p.data[0])&^7+Tetra(data.z.o))
					} else {
						p = mx.demoteAndFix(c, p)
						p.tag |= signBit // invalidate the tag
					}

//line mmmix/mmixpipe.w:7778
				}
				mx.passAfter(self, mx.DTcache.accessTime)
				pc = lPassit
				continue

//line mmmix/mmixpipe.w:7759
			}

//line mmmix/mmixpipe.w:5397
			if data.y.o&signBit != 0 {

//line mmmix/mmixpipe.w:5552
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

//line mmmix/mmixpipe.w:5575
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

//line mmmix/mmixpipe.w:5566
				} else if data.i >= st && data.i <= syncid {
					data.state = stReady
					mx.passAfter(self, 1)
					pc = lPassit
					continue
				}

//line mmmix/mmixpipe.w:5609
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

//line mmmix/mmixpipe.w:5488
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

//line mmmix/mmixpipe.w:5640
				mx.passAfter(self, mx.Dcache.accessTime)
				pc = lPassit
				continue

//line mmmix/mmixpipe.w:5399
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

//line mmmix/mmixpipe.w:5445
			p = mx.cacheSearch(mx.DTcache, mx.transKey(data.y.o))
			if mx.Dcache == nil || mx.Dcache.lock != nil || data.i >= st && data.i <= syncid {

//line mmmix/mmixpipe.w:5529
				if p != nil {
					p = mx.useAndFix(mx.DTcache, p)
					data.z.o = p.data[0]

//line mmmix/mmixpipe.w:5506
					if data.stackAlert {
						if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
							data.stackAlert = false
						} else {
							data.z.o = mx.g[rC].o // use the continuation page for stack overflow
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

//line mmmix/mmixpipe.w:5533
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

//line mmmix/mmixpipe.w:5448
			}
			if j = getReader(mx.Dcache); j < 0 {

//line mmmix/mmixpipe.w:5529
				if p != nil {
					p = mx.useAndFix(mx.DTcache, p)
					data.z.o = p.data[0]

//line mmmix/mmixpipe.w:5506
					if data.stackAlert {
						if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
							data.stackAlert = false
						} else {
							data.z.o = mx.g[rC].o // use the continuation page for stack overflow
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

//line mmmix/mmixpipe.w:5533
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

//line mmmix/mmixpipe.w:5451
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)
			if p != nil {

//line mmmix/mmixpipe.w:5470
				p = mx.useAndFix(mx.DTcache, p)
				data.z.o = p.data[0]

//line mmmix/mmixpipe.w:5506
				if data.stackAlert {
					if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
						data.stackAlert = false
					} else {
						data.z.o = mx.g[rC].o // use the continuation page for stack overflow
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

//line mmmix/mmixpipe.w:5473
				if m := mx.writeSearch(data, data.z.o); m == &mx.dunno {
					data.state = dtHit
				} else if m != nil {
					data.x.o, data.state = *m, ldReady
				} else if mx.Dcache.b+mx.Dcache.c > mx.pageS &&
					(Tetra(data.y.o)^Tetra(data.z.o))&Tetra((mx.Dcache.bb<<mx.Dcache.c)-(1<<mx.pageS)) != 0 {
					data.state = dtHit // spurious D-cache lookup
				} else {

//line mmmix/mmixpipe.w:5488
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

//line mmmix/mmixpipe.w:5482
				}
				mx.passAfter(self, max(mx.DTcache.accessTime, mx.Dcache.accessTime))
				pc = lPassit
				continue

//line mmmix/mmixpipe.w:5455
			} else {
				data.state = dtMiss
			}

//line mmmix/mmixpipe.w:5415
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

//line mmmix/mmixpipe.w:6628
		case lEmulateVirt:

//line mmmix/mmixpipe.w:6611
			i = mx.issuedBetween(data, mx.cool)
			if i < mx.deissues {
				pc = lDie
				continue
			}
			mx.deissues = i
			mx.oldTail, mx.tail = mx.head, mx.head // clear the fetch buffer
			mx.resuming = 0

//line mmmix/mmixpipe.w:6086
			if mx.fetchCo.lockloc != nil {
				*mx.fetchCo.lockloc = nil
				mx.fetchCo.lockloc = nil
			}
			mx.unschedule(&mx.fetchCo)
			mx.startup(&mx.fetchCo, 1)

//line mmmix/mmixpipe.w:6620
			mx.coolHist = data.hist
			mx.instPtr.p = &mx.unknownSpec
			data.interrupt |= fBit

//line mmmix/mmixpipe.w:6630
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

//line mmmix/mmixpipe.w:7099
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

//line mmmix/mmixpipe.w:7918
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
			mx.writeHead, mx.writeCtl.state = mx.writeTail, 0 // zap the write buffer
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

//line mmmix/mmixpipe.w:7961
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

//line mmmix/mmixpipe.w:8008
		case stage1St + 13:
			if mx.cleanCo.next == nil {
				data.interim = false
				pc = lFinEx // it's done!
				continue
			}
			if mx.tryingToInterrupt {
				pc = lFinEx // accept an interruption
				continue
			}
			return mx.wait(self, 1)

//line mmmix/mmixpipe.w:2503

//line mmmix/mmixpipe.w:2752
		case lSwitch2:
			if data.b.p != nil && data.b.p.known {
				data.b.o, data.b.p = data.b.p.o, nil
			}
			pc = stage2St + label(data.state)
			continue
		case stage2St + 0:
			mx.panic(confusion("switch2"))
		case stage2St + 1:

//line mmmix/mmixpipe.w:7727
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

//line mmmix/mmixpipe.w:2762
			fallthrough
		case stage2St + 2:
			pc = lPassData
			continue
		case stage2St + 3:
			pc = lFinEx
			continue

//line mmmix/mmixpipe.w:5671
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

//line mmmix/mmixpipe.w:5506
				if data.stackAlert {
					if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
						data.stackAlert = false
					} else {
						data.z.o = mx.g[rC].o // use the continuation page for stack overflow
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

//line mmmix/mmixpipe.w:5685
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

//line mmmix/mmixpipe.w:5706
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

//line mmmix/mmixpipe.w:5696
		case stage2St + gotDT:
			releaseLock(self, &mx.DTcache.fillLock)

//line mmmix/mmixpipe.w:5506
			if data.stackAlert {
				if Tetra(data.z.o)&(pwBit>>protOffset) != 0 {
					data.stackAlert = false
				} else {
					data.z.o = mx.g[rC].o // use the continuation page for stack overflow
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

//line mmmix/mmixpipe.w:5699
			if data.i >= st && data.i <= syncid {
				pc = lFinishStore
				continue
			}
			fallthrough // otherwise we fall through to |ld_retry| below

//line mmmix/mmixpipe.w:5746
		case lLdRetry:
			data.state = dtHit
			if data.i == preld || data.i == prest {
				pc = lFinEx
				continue
			}

//line mmmix/mmixpipe.w:5853
			if m := mx.writeSearch(data, data.z.o); m == &mx.dunno {
				return mx.wait(self, 1)
			} else if m != nil {
				data.x.o = *m
				data.state = ldReady
				return mx.wait(self, 1)
			}

//line mmmix/mmixpipe.w:5753
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

//line mmmix/mmixpipe.w:5488
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

//line mmmix/mmixpipe.w:5765
			return mx.wait(self, mx.Dcache.accessTime)
		case stage2St + hitAndMiss:
			if data.i == ldunc {
				pc = lAvoidD
				continue
			}

//line mmmix/mmixpipe.w:5813
			if data.i == prest {
				bb, yl := mx.Dcache.bb, Tetra(data.y.o)
				if (int(data.xx) >= bb || yl&Tetra(bb-1) == 0) &&
					(yl+Tetra(int(data.xx)&(bb-1))+1)^yl >= Tetra(bb) {
					pc = lPrestSpan
					continue
				}
			}

//line mmmix/mmixpipe.w:5777
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

//line mmmix/mmixpipe.w:5772
		case lAvoidD:

//line mmmix/mmixpipe.w:5843
			if mx.memLock != nil {
				return mx.wait(self, 1)
			}
			setLock(&mx.memLocker, &mx.memLock)
			mx.startup(&mx.memLocker, mx.memAddrTime+mx.memReadTime)
			data.x.o = mx.memRead(data.z.o)
			data.state = ldReady
			return mx.wait(self, mx.memAddrTime+mx.memReadTime)

//line mmmix/mmixpipe.w:5823
		case lPrestSpan:
			data.state = prestWin
			if data != mx.oldHot || mx.dLocker.next != nil {
				return mx.wait(self, 1)
			}
			if mx.Dcache.lock != nil {
				pc = lFinEx
				continue
			}
			q = mx.allocSlot(mx.Dcache, data.z.o) // OK if |Dcache.filler| is busy
			if q != nil {
				cleanBlock(mx.Dcache, q)
				q.tag = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-mx.Dcache.bb))
				setLock(&mx.dLocker, &mx.Dcache.lock)
				mx.startup(&mx.dLocker, mx.Dcache.copyInTime)
			}
			pc = lFinEx
			continue

//line mmmix/mmixpipe.w:5869
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

//line mmmix/mmixpipe.w:5897
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

//line mmmix/mmixpipe.w:7335
				if data.xx == 0 {
					data.a.o = data.x.o & (0xffffff<<32 | 0xffffffff) // unsaved rA
					data.x.o >>= 56                                   // unsaved rG
					if data.a.o>>32 != 0 || Tetra(data.a.o)&0xfffc0000 != 0 {
						data.a.o &= 0x3ffff
						data.interrupt |= bBit
					}
					if Tetra(data.x.o) < 32 {
						data.x.o = 32
						data.interrupt |= bBit
					}
				}

//line mmmix/mmixpipe.w:5889
			}
			pc = lFinEx
			continue

//line mmmix/mmixpipe.w:5932
		case lFinishStore:
			data.state = stReady
			switch data.i {
			case st, pst:

//line mmmix/mmixpipe.w:5967
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

//line mmmix/mmixpipe.w:6009
						if data.z.o&4 != 0 {
							data.x.o = data.x.o&^0xffffffff | data.b.o>>32
						} else {
							data.x.o = data.x.o&0xffffffff | data.b.o&^0xffffffff
						}

//line mmmix/mmixpipe.w:5987
						data.state = 3
						return mx.wait(self, mx.denoutPenalty)
					}
					fallthrough
				case STHT >> 1:

//line mmmix/mmixpipe.w:6009
					if data.z.o&4 != 0 {
						data.x.o = data.x.o&^0xffffffff | data.b.o>>32
					} else {
						data.x.o = data.x.o&0xffffffff | data.b.o&^0xffffffff
					}

//line mmmix/mmixpipe.w:5993
				case STB >> 1, STBU >> 1:
					j, i = int(Tetra(data.z.o)&0x7)<<3, 56

//line mmmix/mmixpipe.w:6016
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

//line mmmix/mmixpipe.w:5996
				case STW >> 1, STWU >> 1:
					j, i = int(Tetra(data.z.o)&0x6)<<3, 48

//line mmmix/mmixpipe.w:6016
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

//line mmmix/mmixpipe.w:5999
				case STT >> 1, STTU >> 1:
					j, i = int(Tetra(data.z.o)&0x4)<<3, 32

//line mmmix/mmixpipe.w:6016
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

//line mmmix/mmixpipe.w:6002
				case CSWAP >> 1:

//line mmmix/mmixpipe.w:6034
					if data != mx.oldHot {
						return mx.wait(self, 1)
					}
					if data.x.o == mx.g[rP].o {
						data.a.o = 1 // the upper tetra of |data.a.o| is zero
						data.x.o = data.b.o
					} else {
						mx.g[rP].o = data.x.o // |data.a.o| is zero
						if mx.verbose&issueBit != 0 {
							mx.printf(" setting rP=")
							mx.printOcta(mx.g[rP].o)
							mx.printf("\n")
						}
					}
					data.i = cswap // cosmetic change, affects the trace output only

//line mmmix/mmixpipe.w:6004
				case SAVE >> 1:

//line mmmix/mmixpipe.w:7433
					if data.interim {
						data.x.o = data.b.o
					} else {
						if data != mx.oldHot {
							return mx.wait(self, 1) // we need the hottest value of rA
						}
						data.x.o = Octa(Tetra(mx.g[rG].o)<<24)<<32 | Octa(Tetra(mx.g[rA].o))
						data.a.o = data.y.o
					}

//line mmmix/mmixpipe.w:6006
				}

//line mmmix/mmixpipe.w:5937
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
			return true // the original breaks out of the |switch| and reaches |terminate|

//line mmmix/mmixpipe.w:6385
		case stage2St + itMiss, stage2St + iHitAndMiss, stage2St + itHit, stage2St + fetchReady:
			pc = lSwitch0
			continue

//line mmmix/mmixpipe.w:6664
		case stage2St + 4:
			pc = lState4
			continue
		case stage2St + 5:
			pc = lState5
			continue

//line mmmix/mmixpipe.w:7796
		case stage2St + ldStLaunch:
			if mx.ITcache.lock != nil {
				return mx.wait(self, 1)
			}
			if j = getReader(mx.ITcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.ITcache.reader[j], mx.ITcache.accessTime)
			p = mx.cacheSearch(mx.ITcache, data.y.o) // N.B.: Not |transKey(data.y.o)|
			if p != nil {
				data.x.o |= 1
				c = mx.ITcache

//line mmmix/mmixpipe.w:7787
				if Tetra(data.z.o) != 0 {
					p = mx.useAndFix(c, p)
					p.data[0] = p.data[0]&^0xffffffff | Octa(Tetra(p.data[0])&^7+Tetra(data.z.o))
				} else {
					p = mx.demoteAndFix(c, p)
					p.tag |= signBit // invalidate the tag
				}

//line mmmix/mmixpipe.w:7809
			}
			data.state = 3
			return mx.wait(self, mx.ITcache.accessTime)

//line mmmix/mmixpipe.w:8043
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

//line mmmix/mmixpipe.w:8149
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

//line mmmix/mmixpipe.w:8054
			data.state = syncidNext(data)
			return mx.wait(self, mx.Icache.accessTime)
		case stage2St + 31:
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}

//line mmmix/mmixpipe.w:7997
			if mx.writeHead != mx.writeTail {
				if mx.speedLock == nil {
					setLock(self, &mx.speedLock)
				}
				return mx.wait(self, 1)
			}

//line mmmix/mmixpipe.w:8062
			if (Tetra(data.b.o)-1)&^Tetra(data.y.o) < Tetra(data.xx) {
				data.interim = true
			}
			if mx.Dcache == nil {
				pc = lNextSync
				continue
			}

//line mmmix/mmixpipe.w:8164
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

//line mmmix/mmixpipe.w:8070
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

//line mmmix/mmixpipe.w:8179
			if mx.Scache.lock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.Scache.lock)
			p = mx.cacheSearch(mx.Scache, data.z.o)
			if p != nil {
				mx.demoteAndFix(mx.Scache, p)
				cleanBlock(mx.Scache, p)
			}

//line mmmix/mmixpipe.w:8082
			data.state = 35
			return mx.wait(self, mx.Scache.accessTime)

//line mmmix/mmixpipe.w:8098
		case lDoSyncd:
			data.state = 33
			if data != mx.oldHot {
				return mx.wait(self, 1)
			}
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}

//line mmmix/mmixpipe.w:7997
			if mx.writeHead != mx.writeTail {
				if mx.speedLock == nil {
					setLock(self, &mx.speedLock)
				}
				return mx.wait(self, 1)
			}

//line mmmix/mmixpipe.w:8108
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

//line mmmix/mmixpipe.w:8190
			if mx.cleanCo.next != nil || mx.cleanLock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.cleanLock)
			mx.cleanCtl.i = syncd
			mx.cleanCtl.state = 4
			mx.cleanCtl.x.o = mx.cleanCtl.x.o&0xffffffff | data.loc&signBit
			mx.cleanCtl.z.o = data.z.o
			mx.schedule(&mx.cleanCo, 1, 4)

//line mmmix/mmixpipe.w:8120
			data.state = 34
			fallthrough
		case stage2St + 34:
			if mx.cleanCo.next == nil {
				pc = lNextSync
				continue
			}
			if mx.tryingToInterrupt && data.interim && data == mx.oldHot {
				data.z.o = 0 // anticipate |resumeCont|
				pc = lFinEx  // accept an interruption
				continue
			}
			return mx.wait(self, 1)

//line mmmix/mmixpipe.w:8135
		case lNextSync:
			data.state = 35
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if data.interim {

//line mmmix/mmixpipe.w:8203
				{
					bl := Tetra(data.b.o)
					data.interim = false
					data.xx -= byte(((bl - 1) &^ Tetra(data.y.o)) + 1)
					data.y.o += Octa(bl)
					data.y.o = data.y.o&^0xffffffff | Octa(Tetra(data.y.o)&-bl)
					data.z.o = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&^8191+Tetra(data.y.o)&8191)
					if Tetra(data.y.o)&8191 == 0 {
						pc = lSquareOne // maybe crossed a page boundary
						continue
					}
					if data.i == syncd {
						pc = lDoSyncd
					} else {
						pc = lDoSyncid
					}
					continue
				}

//line mmmix/mmixpipe.w:8143
			}
			data.goLoc.known = true
			pc = lFinEx
			continue

//line mmmix/mmixpipe.w:8229
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

//line mmmix/mmixpipe.w:2504

//line mmmix/mmixpipe.w:4048
		case flushMemSt + 0:
			if mx.memLock != nil {
				return mx.wait(self, 1)
			}
			data.state = 1
			fallthrough
		case flushMemSt + 1:
			setLock(self, &mx.memLock)
			data.state = 2

//line mmmix/mmixpipe.w:4062
			{
				del := c.gg >> 3 // octabytes per granule
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

//line mmmix/mmixpipe.w:4058
		case flushMemSt + 2:
			return true // this frees |memLock| and |c.outbuf|

//line mmmix/mmixpipe.w:4118
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

//line mmmix/mmixpipe.w:4188
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

//line mmmix/mmixpipe.w:4144
		case flushSSt + 3:

//line mmmix/mmixpipe.w:4175
			if mx.Scache.filler.next != nil {
				return mx.wait(self, 1) // perhaps an unnecessary precaution?
			}
			p = mx.allocSlot(mx.Scache, c.outbuf.tag)
			if p == nil {
				return mx.wait(self, 1)
			}
			data.ptrB = p
			p.tag = c.outbuf.tag&^0xffffffff | Octa(Tetra(c.outbuf.tag)&Tetra(-mx.Scache.bb))

//line mmmix/mmixpipe.w:4146
			if blockDiff != 0 {

//line mmmix/mmixpipe.w:4210
				p.data, mx.Scache.inbuf.data = mx.Scache.inbuf.data, p.data

//line mmmix/mmixpipe.w:4148
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
			mx.useAndFix(mx.Scache, p) // |p| not moved
			data.state = 5
			return mx.wait(self, mx.Scache.copyInTime)
		case flushSSt + 5:
			if mx.Scache.mode&writeBack == 0 { // write-through
				if mx.Scache.flusher.next != nil {
					return mx.wait(self, 1)
				}
				mx.flushCache(mx.Scache, p, true)
			}
			return true
		case flushSSt + 6:

//line mmmix/mmixpipe.w:4215
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

//line mmmix/mmixpipe.w:4247
		case fillMemSt + 0:
			data.x.o = mx.memRead(data.z.o)
			if cc != nil {
				cc.ctl.x.o = data.x.o
				mx.awaken(cc, mx.memReadTime)
			}
			data.state = 1

//line mmmix/mmixpipe.w:4279
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

//line mmmix/mmixpipe.w:4255
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
				mx.awaken(cc, c.copyInTime) // the second wakeup call
			}
			mx.loadCache(c, data.ptrB.(*cacheblock))
			data.state = 3
			return mx.wait(self, c.copyInTime)
		case fillMemSt + 3:
			return true

//line mmmix/mmixpipe.w:4307
		case fillSSt + 0:
			p = mx.cacheSearch(mx.Scache, data.z.o)
			if p != nil {
				pc = lSNonMiss
				continue
			}
			data.state = 1
			fallthrough
		case fillSSt + 1:

//line mmmix/mmixpipe.w:4362
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

//line mmmix/mmixpipe.w:4317
			data.state = 2
			return mx.sleep(self)
		case fillSSt + 2:
			if cc != nil {
				cc.ctl.x.o = data.x.o               // this data has been supplied by |Scache.filler|
				mx.awaken(cc, mx.Scache.accessTime) // we propagate it back
			}
			data.state = 3
			return mx.sleep(self) // when we awake, the S-cache will have our data

//line mmmix/mmixpipe.w:4328
		case lSNonMiss:
			if cc != nil {
				cc.ctl.x.o = p.data[(Tetra(data.z.o)&Tetra(mx.Scache.bb-1))>>3]
				mx.awaken(cc, mx.Scache.accessTime)
			}
			fallthrough
		case fillSSt + 3:

//line mmmix/mmixpipe.w:4380
			{
				c.inbuf.tag = data.z.o&^0xffffffff | Octa(Tetra(data.z.o)&Tetra(-c.bb))
				off := int(Tetra(c.inbuf.tag)&Tetra(mx.Scache.bb-1)) >> 3
				for j = 0; j < c.bb>>3; j, off = j+1, off+1 {
					c.inbuf.data[j] = p.data[off]
				}
				releaseLock(self, &mx.Scache.fillLock)
				setLock(self, &mx.Scache.lock)
			}

//line mmmix/mmixpipe.w:4336
			data.state = 4
			return mx.wait(self, mx.Scache.accessTime)
		case fillSSt + 4:
			mx.Scache.lock = nil // we had been holding that lock
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
				mx.awaken(cc, 1) // second wakeup call
			}
			return true

//line mmmix/mmixpipe.w:4480
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

//line mmmix/mmixpipe.w:4510
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
				return false // premature termination
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

//line mmmix/mmixpipe.w:4538
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

//line mmmix/mmixpipe.w:4581
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

//line mmmix/mmixpipe.w:4614
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
				return false // premature termination
			}
			if mx.Scache.flusher.next != nil {
				return mx.wait(self, 1)
			}
			if data.i != sync {
				return false
			}
			data.state = 8
			fallthrough

//line mmmix/mmixpipe.w:4641
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

//line mmmix/mmixpipe.w:4476
		case cleanupSt + 10:
			return true

//line mmmix/mmixpipe.w:4769
		case fillVirtSt + 0:

//line mmmix/mmixpipe.w:4863
			aaaaa := data.y.o
			i = int(aaaaa >> 61) // the segment number
			aaaaa &= 1<<61 - 1   // the address within segment~$i$
			aaaaa >>= mx.pageS   // the page address
			for j = 0; aaaaa != 0; j++ {
				co[2*j].ctl.z.o = (aaaaa & 0x3ff) << 3
				aaaaa >>= 10
			}
			if mx.pageB[i+1] < mx.pageB[i]+j { // address too large
				// nothing needs to be done, since |data.b.o| is zero
				//
//line mmmix/mmixpipe.w:4872
//line mmmix/mmixpipe.w:4873
			} else {
				if j == 0 {
					j = 1
					co[0].ctl.z.o = 0
				}

//line mmmix/mmixpipe.w:4888
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

//line mmmix/mmixpipe.w:4879
			}

//line mmmix/mmixpipe.w:4771
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

//line mmmix/mmixpipe.w:4909
			c.inbuf.tag = mx.transKey(data.y.o)
			c.inbuf.data[0] = data.b.o
			if cc != nil {
				cc.ctl.z.o = data.b.o
				mx.awaken(cc, 1)
			}

//line mmmix/mmixpipe.w:4782
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

//line mmmix/mmixpipe.w:5154
		case writeSt + 4:

//line mmmix/mmixpipe.w:5305
			if mx.Dcache.mode&writeBack == 0 { // write-through
				if mx.Dcache.flusher.next != nil {
					return mx.wait(self, 1)
				}
				mx.flushCache(mx.Dcache, p, true)
			}

//line mmmix/mmixpipe.w:5156
			data.state = 5
			fallthrough
		case writeSt + 5:
			mx.writeHead = mx.prevWrite(mx.writeHead)
			fallthrough
		case lWriteRestart:
			data.state = 0

//line mmmix/mmixpipe.w:5179
			if self.lockloc != nil {
				*self.lockloc = nil
				self.lockloc = nil
			}
			if mx.writeHead == mx.writeTail {
				return mx.wait(self, 1) // write buffer is empty
			}
			if mx.writeHead.i == sync {

//line mmmix/mmixpipe.w:5313
				setLock(self, &mx.wbufLock)
				data.state = 5
				return mx.wait(self, 1)

//line mmmix/mmixpipe.w:5188
			}
			if mx.writeHead.addr>>32&0xffff0000 != 0 {
				pc = lMemDirect
				continue
			}
			if Tetra(mx.ticks)-mx.writeHead.stamp < Tetra(mx.holdingTime) && mx.speedLock == nil {
				return mx.wait(self, 1) // data too raw
			}
			if mx.Dcache == nil {
				pc = lMemDirect // not cached
				continue
			}
			if mx.Dcache.lock != nil {
				return mx.wait(self, 1) // D-cache busy
			}
			if j = getReader(mx.Dcache); j < 0 {
				return mx.wait(self, 1)
			}
			mx.startup(&mx.Dcache.reader[j], mx.Dcache.accessTime)

//line mmmix/mmixpipe.w:5292
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

//line mmmix/mmixpipe.w:5208
			if mx.Dcache.mode&writeAlloc != 0 && mx.writeHead.i != stunc {
				data.state = 1
			} else {
				data.state = 3
			}
			return mx.wait(self, mx.Dcache.accessTime)

//line mmmix/mmixpipe.w:5164
		case writeSt + 1:

//line mmmix/mmixpipe.w:5263
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

//line mmmix/mmixpipe.w:5166
			data.state = 2
			return mx.sleep(self)
		case writeSt + 2:
			data.state = 0
			return mx.sleep(self) // wake up when the D-cache has the block
		case writeSt + 3:

//line mmmix/mmixpipe.w:5219
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
				c.outbuf.rank = c.gg // this many valid bytes
			}
			setLock(self, &mx.wbufLock)
			mx.startup(&mx.Dcache.flusher, mx.Dcache.copyOutTime)
			data.state = 5
			return mx.wait(self, mx.Dcache.copyOutTime)

//line mmmix/mmixpipe.w:5173
		case lMemDirect:

//line mmmix/mmixpipe.w:5244
			if mx.memLock != nil {
				return mx.wait(self, 1)
			}
			setLock(self, &mx.wbufLock)
			setLock(&mx.memLocker, &mx.memLock) // a coroutine of type |vanish|
			mx.startup(&mx.memLocker, mx.memAddrTime+mx.memWriteTime)
			if mx.writeHead.addr>>32&0xffff0000 != 0 {
				mx.specWrite(mx.writeHead.addr, mx.writeHead.o, mx.writeHead.size)
			} else {
				mx.memWrite(mx.writeHead.addr, mx.writeHead.o)
			}
			data.state = 5
			return mx.wait(self, mx.memAddrTime+mx.memWriteTime)

//line mmmix/mmixpipe.w:2505
		default:

//line mmmix/mmixpipe.w:2548
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

//line mmmix/mmixpipe.w:2507
		}
		mx.panic(confusion(fmt.Sprintf("label %d", pc)))
	}
}

//line mmmix/mmixpipe.w:2866
func shiftAmt(z Octa) int {
	if z >= 64 {
		return 64
	}
	return int(z)
}

//line mmmix/mmixpipe.w:3172
func (mx *machine) bpIndex(loc Octa) int {
	l := Tetra(loc)
	m := (l&Tetra(mx.bpCmask))<<mx.bpB + l&Tetra(mx.bpAmask)
	return int((mx.coolHist&Tetra(mx.bpBcmask))<<mx.bpA ^ m>>2)
}

//line mmmix/mmixpipe.w:3266
func registerTruth(o Octa, op int) int {
	var b int
	switch (op >> 1) & 0x3 {
	case 0:
		b = int(o >> 63) // negative?
	case 1:
		b = b2i(o == 0) // zero?
	case 2:
		b = b2i(o < signBit && o != 0) // positive?
	case 3:
		b = int(o & 0x1) // odd?
	}
	if op&0x8 != 0 {
		return b ^ 1
	}
	return b
}

//line mmmix/mmixpipe.w:3288
func (mx *machine) issuedBetween(c, cc *control) int {
	if c.idx > cc.idx {
		return c.idx - 1 - cc.idx
	}
	return c.idx + (mx.reorderTop.idx - cc.idx)
}

//line mmmix/mmixpipe.w:3339
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

//line mmmix/mmixpipe.w:3507
func isDirty(c *cache, p *cacheblock) bool {
	for j, d := 0, 0; j < c.bb; j, d = j+c.gg, d+1 {
		if p.dirty[d] {
			return true
		}
	}
	return false
}

//line mmmix/mmixpipe.w:3519
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

//line mmmix/mmixpipe.w:3537
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

//line mmmix/mmixpipe.w:3553
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

//line mmmix/mmixpipe.w:3582
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

//line mmmix/mmixpipe.w:3576
	}
}

//line mmmix/mmixpipe.w:3602
func cleanBlock(c *cache, p *cacheblock) {
	p.tag = sign32 << 32
	for j := 0; j < c.bb>>3; j++ {
		p.data[j] = 0
	}
	for j := 0; j < c.bb>>c.g; j++ {
		p.dirty[j] = false
	}
}

//line mmmix/mmixpipe.w:3617
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

//line mmmix/mmixpipe.w:3632
func getReader(c *cache) int {
	for j := 0; j < c.ports; j++ {
		if c.reader[j].next == nil {
			return j
		}
	}
	return -1
}

//line mmmix/mmixpipe.w:3646
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

//line mmmix/mmixpipe.w:3668
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
		mx.panic(confusion("lru victim")) // what happened? nobody has rank zero
	case pseudoLRU:
		l := 1
		for m := aa >> 1; m != 0; m >>= 1 {
			l = l + l + s[l].rank
		}
		return &s[l-aa]
	}
	return nil
}

//line mmmix/mmixpipe.w:3697
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

//line mmmix/mmixpipe.w:3727
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

//line mmmix/mmixpipe.w:3760
func (c *cache) cacheAddr(alf Octa) cacheset {
	return c.set[(Tetra(alf)&^Tetra(c.tagmask))>>c.b]
}

func (mx *machine) cacheSearch(c *cache, alf Octa) *cacheblock {
	s := c.cacheAddr(alf) // the set corresponding to |alf|
	for k := 0; k < c.aa; k++ {
		if p := &s[k]; (Tetra(p.tag)^Tetra(alf))&Tetra(c.tagmask) == 0 && p.tag>>32 == alf>>32 {
			mx.hitSet = s
			return p
		}
	}
	s = c.victim
	if s == nil {
		return nil // cache miss, and no victim area
	}
	for k := 0; k < c.vv; k++ {
		if p := &s[k]; (Tetra(p.tag)^Tetra(alf))&Tetra(-c.bb) == 0 && p.tag>>32 == alf>>32 {
			mx.hitSet = s
			return p
		}
	}
	return nil // double miss
}

//line mmmix/mmixpipe.w:3792
func sameSet(a, b cacheset) bool {
	return len(a) > 0 && len(b) > 0 && &a[0] == &b[0]
}

//line mmmix/mmixpipe.w:3801
func (mx *machine) useAndFix(c *cache, p *cacheblock) *cacheblock {
	if !sameSet(mx.hitSet, c.victim) {
		noteUsage(p, mx.hitSet, c.aa, c.repl)
	} else {
		noteUsage(p, mx.hitSet, c.vv, c.vrepl) // found in victim cache
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

//line mmmix/mmixpipe.w:3821
func swapBlocks(p, q *cacheblock) {
	p.tag, q.tag = q.tag, p.tag
	p.dirty, q.dirty = q.dirty, p.dirty
	p.data, q.data = q.data, p.data
}

//line mmmix/mmixpipe.w:3831
func (mx *machine) demoteAndFix(c *cache, p *cacheblock) *cacheblock {
	if !sameSet(mx.hitSet, c.victim) {
		demoteUsage(p, mx.hitSet, c.aa, c.repl)
	} else {
		demoteUsage(p, mx.hitSet, c.vv, c.vrepl)
	}
	return p
}

//line mmmix/mmixpipe.w:3844
func (mx *machine) loadCache(c *cache, p *cacheblock) {
	for i := 0; i < c.bb>>c.g; i++ {
		p.dirty[i] = false
	}
	p.data, c.inbuf.data = c.inbuf.data, p.data
	p.tag = c.inbuf.tag
	mx.hitSet = c.cacheAddr(p.tag)
	mx.useAndFix(c, p) // |p| not moved
}

//line mmmix/mmixpipe.w:3859
func (mx *machine) flushCache(c *cache, p *cacheblock, keep bool) {
	c.outbuf.tag = p.tag
	if keep { // should we preserve the data in |p|?
		copy(c.outbuf.data[:c.bb>>3], p.data)
	} else {
		c.outbuf.data, p.data = p.data, c.outbuf.data
	}
	c.outbuf.dirty, p.dirty = p.dirty, c.outbuf.dirty
	for j := 0; j < c.bb>>c.g; j++ {
		p.dirty[j] = false
	}
	c.outbuf.rank = c.bb                  // this many valid bytes
	mx.startup(&c.flusher, c.copyOutTime) // will not be aborted
}

//line mmmix/mmixpipe.w:3892
func (mx *machine) allocSlot(c *cache, alf Octa) *cacheblock {
	if mx.cacheSearch(c, alf) != nil {
		return nil
	}
	if c.flusher.next != nil && c.outbuf.tag>>32 == alf>>32 &&
		(Tetra(c.outbuf.tag)^Tetra(alf))&Tetra(-c.bb) == 0 {
		return nil
	}
	s := c.cacheAddr(alf) // the set corresponding to |alf|
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
		q.tag |= sign32 << 32 // invalidate the tag
		return q
	}
	p.tag |= sign32 << 32
	return p
}

//line mmmix/mmixpipe.w:3976
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
			break // zero will be returned
		}
		if h == 0 {
			h = mx.hashPrime
		}
	}
	mx.lastH = h
	return mx.memHash[h].chunk[off]
}

//line mmmix/mmixpipe.w:4001
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

//line mmmix/mmixpipe.w:4838
func (mx *machine) transKey(addr Octa) Octa {
	return addr&^mx.pageMask + Octa(mx.pageN)
}

func (mx *machine) physAddr(virt, trans Octa) Octa {
	t := trans &^ mx.pageMask // zero out the \\{ynp} fields of a PTE
	return t + virt&mx.pageMask
}

//line mmmix/mmixpipe.w:4952
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

//line mmmix/mmixpipe.w:4982
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

//line mmmix/mmixpipe.w:5008
func (mx *machine) printPipe() {
	mx.printWriteBuffer()
	mx.printReorderBuffer()
	mx.printFetchBuffer()
}

//line mmmix/mmixpipe.w:5038
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
	for { // the original's |qloop|
		if q == mx.writeHead {
			return nil
		}
		q = mx.nextWrite(q)
		if q.addr == addr {
			return &q.o
		}
	}
}

//line mmmix/mmixpipe.w:5373
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

//line mmmix/mmixpipe.w:6102
func (mx *machine) waitOrPass(self *coroutine, t int) bool {
	if self.ctl.i == prego {
		mx.passAfter(self, t)
		return true
	}
	mx.wait(self, t)
	return false
}

//line mmmix/mmixpipe.w:6551
func isLoadStore(i int) bool {
	return i >= ld && i <= cswap
}

//line mmmix/mmixpipe.w:6831
func packBytes(a, b, c, d int) Tetra {
	return Tetra(a)<<24 + Tetra(b)<<16 + Tetra(c)<<8 + Tetra(d)
}

//line mmmix/mmixpipe.w:7556
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

//line mmmix/mmixpipe.w:8090
func syncidNext(data *control) int {
	if data.loc&signBit != 0 {
		return 31
	}
	return 33
}

//line mmmix/mmixpipe.w:8325
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

//line mmmix/mmixpipe.w:8348
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

//line mmmix/mmixpipe.w:8363
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

//line mmmix/mmixpipe.w:8398
func magicAddr(a Octa) Octa {
	return Octa(Tetra(a>>32)>>29)<<32 | a&0xffffffff
}

//line mmmix/mmixpipe.w:8423
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

//line mmmix/mmixpipe.w:8448
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

//line mmmix/mmixpipe.w:8437
		} else {

//line mmmix/mmixpipe.w:8461
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

//line mmmix/mmixpipe.w:8439
		}
	}
	return size
}

//line mmmix/mmixpipe.w:8505
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

//line mmmix/mmixpipe.w:8525
			{
				s := 8 * (^a & 0x7)
				x := mx.magicRead(a)
				x ^= ((x>>s ^ Octa(buf[k])) & 0xff) << s
				mx.magicWrite(a, x)
				k++
				a++
			}

//line mmmix/mmixpipe.w:8518
		} else {

//line mmmix/mmixpipe.w:8535
			{
				var x Octa
				for _, b := range buf[k : k+8] {
					x = x<<8 | Octa(b)
				}
				mx.magicWrite(a, x)
				k += 8
				a += 8
			}

//line mmmix/mmixpipe.w:8520
		}
	}
}

//line mmmix/mmixpipe.w:8555
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
