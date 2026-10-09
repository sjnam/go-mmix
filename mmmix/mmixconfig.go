//line mmmix/mmixconfig.w:42
package main

import "io"

//line mmmix/mmixconfig.w:304
type configReader struct {
	mx              *machine            // the machine being configured
	configFile      *cfile              // input comes from here
	token           string              // and tokens are copied to here
	tokenPrescanned bool                // does |token| contain the next token already?
	buffer          [configBufSize]byte // input lines go here
	bufPointer      int                 // this is our current position

//line mmmix/mmixconfig.w:433
	fetchBufSize, writeBufSize, reorderBufSize, memBusBytes, hardwarePT int
	disableSecurity                                                     int
	maxCycs                                                             int

//line mmmix/mmixconfig.w:312
}

//line mmmix/mmixconfig.w:380
type pvSpec struct {
	name           string // symbolic name
	v              *int   // internal name
	defval         int    // default value
	minval, maxval int    // minimum and maximum legal values
	powerOfTwo     bool   // must it be a power of two?
}

//line mmmix/mmixconfig.w:391
type cParam int

const (
	assoc cParam = iota
	blksz
	setsz
	gran
	vctsz
	wrb
	wra
	acctm
	citm
	cotm
	prts

//line mmmix/mmixconfig.w:405
)

type cpvSpec struct {
	name           string // symbolic name
	v              cParam // internal code
	defval         int    // default value
	minval, maxval int    // minimum and maximum legal values
	powerOfTwo     bool   // must it be a power of two?
}

//line mmmix/mmixconfig.w:418
type opSpec struct {
	name   string // symbolic name
	v      int    // internal code
	defval int    // default value
}

//line mmmix/mmixconfig.w:301
const configBufSize = 100 // we don't need long lines

//line mmmix/mmixconfig.w:470
const intMax = 1<<31 - 1

//line mmmix/mmixconfig.w:473
var cpv = []cpvSpec{
	{"associativity", assoc, 1, 1, intMax, true},
	{"blocksize", blksz, 8, 8, 8192, true},
	{"setsize", setsz, 1, 1, intMax, true},
	{"granularity", gran, 8, 8, 8192, true},
	{"victimsize", vctsz, 0, 0, intMax, true},
	{"writeback", wrb, 0, 0, 1, false},
	{"writeallocate", wra, 0, 0, 1, false},
	{"accesstime", acctm, 1, 1, intMax, false},
	{"copyintime", citm, 1, 1, intMax, false},
	{"copyouttime", cotm, 1, 1, intMax, false},
	{"ports", prts, 1, 1, intMax, false}}

var opTable = []opSpec{
	{"mul0", mul0, 10}, {"mul1", mul1, 10}, {"mul2", mul2, 10},
	{"mul3", mul3, 10}, {"mul4", mul4, 10}, {"mul5", mul5, 10},
	{"mul6", mul6, 10}, {"mul7", mul7, 10}, {"mul8", mul8, 10},
	{"div", div, 60}, {"sh", sh, 1}, {"mux", mux, 1},
	{"sadd", sadd, 1}, {"mor", mor, 1}, {"fadd", fadd, 4},
	{"fmul", fmul, 4}, {"fdiv", fdiv, 40}, {"fsqrt", fsqrt, 40},
	{"fint", fint, 4}, {"fix", fix, 2}, {"flot", flot, 2},
	{"feps", feps, 4}}

//line mmmix/mmixconfig.w:835
var intOp = [256]int{
	trap, fcmp, funeq, funeq, fadd, fix, fadd, fix,
	flot, flot, flot, flot, flot, flot, flot, flot,
	fmul, feps, feps, feps, fdiv, fsqrt, frem, fint,
	mul, mul, mul, mul, div, div, div, div,
	add, add, addu, addu, sub, sub, subu, subu,
	addu, addu, addu, addu, addu, addu, addu, addu,
	cmp, cmp, cmpu, cmpu, sub, sub, subu, subu,
	sh, sh, sh, sh, sh, sh, sh, sh,
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
	ld, ld, ld, ld, ld, ld, ld, ld,
	ld, ld, ld, ld, prego, prego, goOp, goOp,
	st, st, st, st, st, st, st, st,
	st, st, st, st, st, st, st, st,
	st, st, st, st, st, st, st, st,
	st, st, st, st, st, st, pushgo, pushgo,
	or, or, orn, orn, nor, nor, xor, xor,
	and, and, andn, andn, nand, nand, nxor, nxor,
	bdif, bdif, wdif, wdif, tdif, tdif, odif, odif,
	mux, mux, sadd, sadd, mor, mor, mor, mor,
	set, set, set, set, addu, addu, addu, addu,
	or, or, or, or, andn, andn, andn, andn,
	noop, noop, pushj, pushj, set, set, put, put,
	pop, resume, save, unsave, sync, noop, get, trip}

//line mmmix/mmixconfig.w:288
func (cf *configReader) configPanic(format string, a ...any) {
	cf.mx.errprintf(format, a...)
	cf.mx.errprintf("!\n")
	panic(exitSignal(-1))
}

//line mmmix/mmixconfig.w:323
func (cf *configReader) getToken() { // set |token| to the next token of the configuration file
	if cf.tokenPrescanned {
		cf.tokenPrescanned = false
		return
	}
	for { // scan past white space
		c := byte(0) // treat the end of the buffer as a null character
		if cf.bufPointer < configBufSize {
			c = cf.buffer[cf.bufPointer]
		}
		if c == 0 || c == '\n' || c == '%' {
			if !cf.configFile.fgets(cf.buffer[:], configBufSize) {
				cf.token = "end"
				return
			}
			if strlen(cf.buffer[:]) == configBufSize-1 && cf.buffer[configBufSize-2] != '\n' {
				cf.configPanic("config file line too long: `%s...'", cstr(cf.buffer[:]))

			}
			cf.bufPointer = 0
		} else if !isspace(c) {
			break
		} else {
			cf.bufPointer++
		}
	}
	p := cf.bufPointer
	for p < configBufSize && !isspace(cf.buffer[p]) && cf.buffer[p] != '%' {
		p++
	}
	cf.token = string(cstr(cf.buffer[cf.bufPointer:p]))
	cf.bufPointer = p
}

//line mmmix/mmixconfig.w:364
func (cf *configReader) getInt() int {
	cf.getToken()
	var v int32
	p := 0
	for ; p < len(cf.token) && cf.token[p] >= '0' && cf.token[p] <= '9'; p++ {
		v = 10*v + int32(cf.token[p]-'0')
	}
	if p < len(cf.token) {
		return -1
	}
	return int(v)
}

//line mmmix/mmixconfig.w:504
func newCache(name string) *cache {
	c := new(cache)
	c.aa = 1         // default associativity, should equal |cpv[0].defval|
	c.bb = 8         // default blocksize
	c.cc = 1         // default setsize
	c.gg = 8         // default granularity
	c.vv = 0         // default victimsize
	c.repl = random  // default replacement policy
	c.vrepl = random // default victim replacement policy
	c.mode = 0       // default mode is write-through and write-around
	c.accessTime, c.copyInTime, c.copyOutTime = 1, 1, 1
	c.filler.ctl = &c.fillerCtl
	c.fillerCtl.ptrA = c
	c.fillerCtl.goLoc.o = 4
	c.flusher.ctl = &c.flusherCtl
	c.flusherCtl.ptrA = c
	c.flusherCtl.goLoc.o = 4
	c.ports = 1
	c.name = name
	return c
}

//line mmmix/mmixconfig.w:646
func (cf *configReader) ppol(rr *replacePolicy) { // subroutine to scan for a replacement policy
	cf.getToken()
	switch cf.token {
	case "random":
		*rr = random
	case "serial":
		*rr = serial
	case "pseudolru":
		*rr = pseudoLRU
	case "lru":
		*rr = lru
	default:
		cf.tokenPrescanned = true // oops, we should rescan that token
	}
}

//line mmmix/mmixconfig.w:663
func (cf *configReader) pcs(c *cache) { // subroutine to process a cache spec
	var j, n int
	cf.getToken()
	for j = 0; j < len(cpv); j++ {
		if cf.token == cpv[j].name {
			break
		}
	}
	if j == len(cpv) {
		cf.configPanic("Configuration syntax error: `%s' isn't a cache parameter name",
			cf.token)

	}
	n = cf.getInt()
	if n < cpv[j].minval {
		cf.configPanic("Configuration error: %s must be >= %d", cpv[j].name, cpv[j].minval)

	}
	if n > cpv[j].maxval {
		cf.configPanic("Configuration error: %s must be <= %d", cpv[j].name, cpv[j].maxval)
	}
	if cpv[j].powerOfTwo && n&(n-1) != 0 {
		cf.configPanic("Configuration error: %s must be power of 2", cpv[j].name)
	}

//line mmmix/mmixconfig.w:691
	switch cpv[j].v {
	case assoc:
		c.aa = n
		cf.ppol(&c.repl)
	case blksz:
		c.bb = n
	case setsz:
		c.cc = n
	case gran:
		c.gg = n
	case vctsz:
		c.vv = n
		cf.ppol(&c.vrepl)
	case wrb:
		c.mode = c.mode&^writeBack + n*writeBack
	case wra:
		c.mode = c.mode&^writeAlloc + n*writeAlloc
	case acctm:
		cf.maxCycs = max(cf.maxCycs, n)
		c.accessTime = n
	case citm:
		cf.maxCycs = max(cf.maxCycs, n)
		c.copyInTime = n
	case cotm:
		cf.maxCycs = max(cf.maxCycs, n)
		c.copyOutTime = n
	case prts:
		c.ports = n
	}

//line mmmix/mmixconfig.w:688
}

//line mmmix/mmixconfig.w:885
func lg(n int) int { // compute binary logarithm
	l := 0
	for j := n; j != 0; j >>= 1 {
		l++
	}
	return l - 1
}

//line mmmix/mmixconfig.w:896
func (cf *configReader) allocCache(c *cache, name string) {
	if c.bb < c.gg {
		cf.configPanic("Configuration error: blocksize of %s is less than granularity", name)

	}
	if name[1] == 'T' && c.bb != 8 {
		cf.configPanic("Configuration error: blocksize of %s must be 8", name)
	}
	c.a = lg(c.aa)
	c.b = lg(c.bb)
	c.c = lg(c.cc)
	c.g = lg(c.gg)
	c.v = lg(c.vv)
	c.tagmask = -(1 << (c.b + c.c))
	if c.a+c.b+c.c >= 32 {
		cf.configPanic("Configuration error: %s has >= 4 gigabytes of data", name)
	}
	if c.gg != 8 && c.mode&writeAlloc == 0 {
		cf.configPanic("Configuration error: %s does write-around with granularity %d",
			name, c.gg)
	}

//line mmmix/mmixconfig.w:937
	c.set = make([]cacheset, c.cc)
	for j := 0; j < c.cc; j++ {
		c.set[j] = make(cacheset, c.aa)
		for k := 0; k < c.aa; k++ {
			c.set[j][k] = newBlock(c, k)
			c.set[j][k].tag = sign32 << 32 // invalid tag
		}
	}

//line mmmix/mmixconfig.w:918
	if c.vv != 0 {

//line mmmix/mmixconfig.w:947
		c.victim = make(cacheset, c.vv)
		for k := 0; k < c.vv; k++ {
			c.victim[k] = newBlock(c, k)
			c.victim[k].tag = sign32 << 32 // invalid tag
		}

//line mmmix/mmixconfig.w:920
	}
	c.inbuf = newBlock(c, 0)
	c.outbuf = newBlock(c, 0)
	if name[0] != 'S' {

//line mmmix/mmixconfig.w:954
		c.reader = make([]coroutine, c.ports)
		for j := 0; j < c.ports; j++ {
			c.reader[j].stage = vanish
			switch {
			case name[0] == 'D' && name[1] == 'T':
				c.reader[j].name = "DTreader"
			case name[0] == 'D':
				c.reader[j].name = "Dreader"
			case name[1] == 'T':
				c.reader[j].name = "ITreader"
			default:
				c.reader[j].name = "Ireader"
			}
		}

//line mmmix/mmixconfig.w:925
	}
}

//line mmmix/mmixconfig.w:932
func newBlock(c *cache, pos int) cacheblock {
	return cacheblock{dirty: make([]bool, c.bb>>c.g), data: make([]Octa, c.bb>>3), pos: pos}
}

//line mmmix/mmixconfig.w:1082
func (mx *machine) MMIXConfig(filename string) {
	var i, j, n int
	var intStages [maxRealCommand + 1]int // stages as function of |internalOp|
	var stages [256]int                   // stages as function of opcode
	cf := &configReader{mx: mx, maxCycs: 60}
	cf.configFile = openCfile(filename)
	if cf.configFile == nil {
		cf.configPanic("Can't open configuration file %s", filename)

	}

//line mmmix/mmixconfig.w:438
	mx.securityDisabled = false
	pv := []pvSpec{
		{"fetchbuffer", &cf.fetchBufSize, 4, 1, intMax, false},
		{"writebuffer", &cf.writeBufSize, 2, 1, intMax, false},
		{"reorderbuffer", &cf.reorderBufSize, 5, 1, intMax, false},
		{"renameregs", &mx.maxRenameRegs, 5, 1, intMax, false},
		{"memslots", &mx.maxMemSlots, 2, 1, intMax, false},
		{"localregs", &mx.lringSize, 256, 256, 1024, true},
		{"fetchmax", &mx.fetchMax, 2, 1, intMax, false},
		{"dispatchmax", &mx.dispatchMax, 1, 1, intMax, false},
		{"peekahead", &mx.peekahead, 1, 0, intMax, false},
		{"commitmax", &mx.commitMax, 1, 1, intMax, false},
		{"fremmax", &mx.fremMax, 1, 1, intMax, false},
		{"denin", &mx.deninPenalty, 1, 0, intMax, false},
		{"denout", &mx.denoutPenalty, 1, 0, intMax, false},
		{"writeholdingtime", &mx.holdingTime, 0, 0, intMax, false},
		{"memaddresstime", &mx.memAddrTime, 20, 1, intMax, false},
		{"memreadtime", &mx.memReadTime, 20, 1, intMax, false},
		{"memwritetime", &mx.memWriteTime, 20, 1, intMax, false},
		{"membusbytes", &cf.memBusBytes, 8, 8, intMax, true},
		{"branchpredictbits", &mx.bpN, 0, 0, 8, false},
		{"branchaddressbits", &mx.bpA, 0, 0, 32, false},
		{"branchhistorybits", &mx.bpB, 0, 0, 32, false},
		{"branchdualbits", &mx.bpC, 0, 0, 32, false},
		{"hardwarepagetable", &cf.hardwarePT, 1, 0, 1, false},
		{"disablesecurity", &cf.disableSecurity, 0, 0, 1, false},
		{"memchunksmax", &mx.memChunksMax, 1000, 1, intMax, false},
		{"hashprime", &mx.hashPrime, 2003, 2, intMax, false}}

//line mmmix/mmixconfig.w:1093

//line mmmix/mmixconfig.w:527
	mx.ITcache = newCache("ITcache")
	mx.DTcache = newCache("DTcache")
	mx.Icache, mx.Dcache, mx.Scache = nil, nil, nil
	for j = 0; j < len(pv); j++ {
		*pv[j].v = pv[j].defval
	}
	for j = 0; j < len(opTable); j++ {
		mx.pipeSeq[opTable[j].v][0] = byte(opTable[j].defval)
		mx.pipeSeq[opTable[j].v][1] = 0 // one stage
	}

//line mmmix/mmixconfig.w:1094

//line mmmix/mmixconfig.w:544
	mx.funitCount = 0
	for cf.token != "end" {
		cf.getToken()
		if cf.token == "unit" {
			mx.funitCount++
			cf.getToken() // a unit might be named \.{unit} or \.{end}
			cf.getToken()
		}
	}
	mx.funit = make([]funcUnit, mx.funitCount+1)
	mx.funit[mx.funitCount].name = "%%"

	mx.funit[mx.funitCount].ops[0] = 0x80000000 // \.{TRAP}
	mx.funit[mx.funitCount].ops[7] = 0x1        // \.{TRIP}

//line mmmix/mmixconfig.w:1095

//line mmmix/mmixconfig.w:568
	cf.configFile.f.Seek(0, io.SeekStart)
	cf.configFile.r.Reset(cf.configFile.f)
	cf.configFile.pos, cf.configFile.eof = 0, false
	mx.funitCount = 0
	cf.token = ""
	for cf.token != "end" {
		cf.getToken()
		if cf.token == "end" {
			break
		}

//line mmmix/mmixconfig.w:590
		for j = 0; j < len(pv); j++ {
			if cf.token == pv[j].name {
				n = cf.getInt()
				if n < pv[j].minval {
					cf.configPanic("Configuration error: %s must be >= %d", pv[j].name, pv[j].minval)

				}
				if n > pv[j].maxval {
					cf.configPanic("Configuration error: %s must be <= %d", pv[j].name, pv[j].maxval)
				}
				if pv[j].powerOfTwo && n&(n-1) != 0 {
					cf.configPanic("Configuration error: %s must be a power of 2", pv[j].name)
				}
				*pv[j].v = n
				break
			}
		}
		if j < len(pv) {
			continue
		}

//line mmmix/mmixconfig.w:579

//line mmmix/mmixconfig.w:612
		switch cf.token {
		case "ITcache":
			cf.pcs(mx.ITcache)
			continue
		case "DTcache":
			cf.pcs(mx.DTcache)
			continue
		case "Icache":
			if mx.Icache == nil {
				mx.Icache = newCache("Icache")
			}
			cf.pcs(mx.Icache)
			continue
		case "Dcache":
			if mx.Dcache == nil {
				mx.Dcache = newCache("Dcache")
			}
			cf.pcs(mx.Dcache)
			continue
		case "Scache":
			if mx.Icache == nil {
				mx.Icache = newCache("Icache")
			}
			if mx.Dcache == nil {
				mx.Dcache = newCache("Dcache")
			}
			if mx.Scache == nil {
				mx.Scache = newCache("Scache")
			}
			cf.pcs(mx.Scache)
			continue
		}

//line mmmix/mmixconfig.w:580

//line mmmix/mmixconfig.w:725
		for j = 0; j < len(opTable); j++ {
			if cf.token == opTable[j].name {
				for i = 0; ; i++ {
					n = cf.getInt()
					if n < 0 {
						break
					}
					if n == 0 {
						cf.configPanic("Configuration error: Pipeline cycles must be positive")

					}
					if n > 255 {
						cf.configPanic("Configuration error: Pipeline cycles must be <= 255")
					}
					cf.maxCycs = max(cf.maxCycs, n)
					if i >= pipeLimit {
						cf.configPanic("Configuration error: More than %d pipeline stages", pipeLimit)
					}
					mx.pipeSeq[opTable[j].v][i] = byte(n)
				}
				cf.tokenPrescanned = true
				break
			}
		}
		if j < len(opTable) {
			continue
		}

//line mmmix/mmixconfig.w:581
		if cf.token == "unit" {

//line mmmix/mmixconfig.w:754
			cf.getToken()
			if len(cf.token) > 15 {
				cf.configPanic("Configuration error: `%s' is more than 15 characters long", cf.token)

			}
			mx.funit[mx.funitCount].name = cf.token
			cf.getToken()
			if len(cf.token) != 64 {
				cf.configPanic("Configuration error: unit %s doesn't have 64 hex digit specs",
					mx.funit[mx.funitCount].name)
			}
			{
				var n Tetra
				for i, j = 0, 0; j < 64; j++ {
					switch t := cf.token[j]; {
					case t >= '0' && t <= '9':
						n = n<<4 + Tetra(t-'0')
					case t >= 'a' && t <= 'f':
						n = n<<4 + Tetra(t-'a'+10)
					case t >= 'A' && t <= 'F':
						n = n<<4 + Tetra(t-'A'+10)
					default:
						cf.configPanic("Configuration error: `%c' is not a hex digit", t)
					}
					if j&0x7 == 0x7 {
						mx.funit[mx.funitCount].ops[i] = n
						i, n = i+1, 0
					}
				}
			}
			mx.funitCount++
			continue

//line mmmix/mmixconfig.w:583
		}
		cf.configPanic("Configuration syntax error: Specification can't start with `%s'",
			cf.token)

	}

//line mmmix/mmixconfig.w:1096

//line mmmix/mmixconfig.w:816
	for j = div; j <= maxPipeOp; j++ {
		intStages[j] = strlen(mx.pipeSeq[j][:])
	}
	for ; j <= maxRealCommand; j++ {
		intStages[j] = 1
	}
	for j, n = mul0, 0; j <= mul8; j++ {
		n = max(n, strlen(mx.pipeSeq[j][:]))
	}
	intStages[mul] = n
	intStages[ld], intStages[st], intStages[frem] = 2, 2, 2
	for j = 0; j < 256; j++ {
		stages[j] = intStages[intOp[j]]
	}

//line mmmix/mmixconfig.w:798
	for j = 0; j <= mx.funitCount; j++ {

//line mmmix/mmixconfig.w:870
		for i, n = 0, 0; i < 256; i++ {
			if (mx.funit[j].ops[i>>5]<<(i&0x1f))&0x80000000 != 0 && stages[i] > n {
				n = stages[i]
			}
		}
		if n == 0 {
			cf.configPanic("Configuration error: unit %s doesn't do anything", mx.funit[j].name)

		}

//line mmmix/mmixconfig.w:800
		u := &mx.funit[j]
		u.k = n
		u.co = make([]coroutine, n)
		for i = 0; i < n; i++ {
			u.co[i].name = u.name
			u.co[i].stage = i + 1
			if i+1 < n {
				u.co[i].succ = &u.co[i+1]
			}
		}
	}

//line mmmix/mmixconfig.w:1097

//line mmmix/mmixconfig.w:970
	cf.allocCache(mx.ITcache, "ITcache")
	mx.ITcache.filler.name, mx.ITcache.filler.stage = "ITfiller", fillFromVirt
	cf.allocCache(mx.DTcache, "DTcache")
	mx.DTcache.filler.name, mx.DTcache.filler.stage = "DTfiller", fillFromVirt
	if mx.Icache != nil {
		cf.allocCache(mx.Icache, "Icache")
		mx.Icache.filler.name, mx.Icache.filler.stage = "Ifiller", fillFromMem
	}
	if mx.Dcache != nil {
		cf.allocCache(mx.Dcache, "Dcache")
		mx.Dcache.filler.name, mx.Dcache.filler.stage = "Dfiller", fillFromMem
		mx.Dcache.flusher.name, mx.Dcache.flusher.stage = "Dflusher", flushToMem
	}
	if mx.Scache != nil {

//line mmmix/mmixconfig.w:988
		cf.allocCache(mx.Scache, "Scache")
		if mx.Scache.bb < mx.Icache.bb {
			cf.configPanic("Configuration error: Scache blocks smaller than Icache blocks")

		}
		if mx.Scache.bb < mx.Dcache.bb {
			cf.configPanic("Configuration error: Scache blocks smaller than Dcache blocks")
		}
		if mx.Scache.gg != mx.Dcache.gg {
			cf.configPanic("Configuration error: Scache granularity differs from the Dcache")
		}
		mx.Icache.filler.stage = fillFromS
		mx.Dcache.filler.stage = fillFromS
		mx.Dcache.flusher.stage = flushToS
		mx.Scache.filler.name, mx.Scache.filler.stage = "Sfiller", fillFromMem
		mx.Scache.flusher.name, mx.Scache.flusher.stage = "Sflusher", flushToMem

//line mmmix/mmixconfig.w:985
	}

//line mmmix/mmixconfig.w:1098

//line mmmix/mmixconfig.w:1009
	mx.busWords = cf.memBusBytes >> 3
	j = max(mx.memReadTime, mx.memWriteTime)
	n = 1
	if mx.Scache != nil && mx.Scache.bb > n {
		n = mx.Scache.bb
	}
	if mx.Icache != nil && mx.Icache.bb > n {
		n = mx.Icache.bb
	}
	if mx.Dcache != nil && mx.Dcache.bb > n {
		n = mx.Dcache.bb
	}
	n = mx.memAddrTime + (n+cf.memBusBytes-1)/cf.memBusBytes*j
	cf.maxCycs = max(cf.maxCycs, n) // now |maxCycs| bounds the waiting time
	mx.ringSize = cf.maxCycs + 1
	mx.ring = make([]coroutine, mx.ringSize)
	for k := range mx.ring {
		mx.ring[k].name = "" // header nodes are nameless
		mx.ring[k].stage = maxStage
	}

//line mmmix/mmixconfig.w:1099

//line mmmix/mmixconfig.w:1034
	if mx.hashPrime <= mx.memChunksMax {
		cf.configPanic("Configuration error: hashprime must exceed memchunksmax")

	}
	mx.memHash = make([]chunknode, mx.hashPrime+1)
	mx.memHash[0].chunk = make([]Octa, 1<<13)
	mx.memHash[mx.hashPrime].chunk = make([]Octa, 1<<13)
	mx.memChunks = 1
	mx.fetchBuf = make([]fetch, cf.fetchBufSize+1)
	for k := range mx.fetchBuf {
		mx.fetchBuf[k].idx = k
	}
	mx.fetchBot, mx.fetchTop = &mx.fetchBuf[0], &mx.fetchBuf[cf.fetchBufSize]
	mx.reorder = make([]control, cf.reorderBufSize+1)
	for k := range mx.reorder {
		mx.reorder[k].idx = k
		mx.reorder[k].link()
	}
	mx.reorderBot, mx.reorderTop = &mx.reorder[0], &mx.reorder[cf.reorderBufSize]
	mx.wbuf = make([]writeNode, cf.writeBufSize+1)
	for k := range mx.wbuf {
		mx.wbuf[k].idx = k
	}
	mx.wbufBot, mx.wbufTop = &mx.wbuf[0], &mx.wbuf[cf.writeBufSize]

//line mmmix/mmixconfig.w:1070
	if mx.bpN == 0 {
		mx.bpTable = nil
	} else { // a branch prediction table is desired
		if mx.bpA+mx.bpB+mx.bpC >= 31 {
			cf.configPanic("Configuration error: Branch table has >= 2 gigabytes of data")
		}
		mx.bpTable = make([]int8, 1<<(mx.bpA+mx.bpB+mx.bpC))
	}

//line mmmix/mmixconfig.w:1059
	mx.l = make([]specnode, mx.lringSize)
	j = mx.busWords
	if mx.Icache != nil && mx.Icache.bb>>3 > j {
		j = mx.Icache.bb >> 3
	}
	mx.fetched = make([]Octa, j)
	mx.dispatchStat = make([]int32, mx.dispatchMax+1)
	mx.noHardwarePT = cf.hardwarePT == 0
	mx.securityDisabled = cf.disableSecurity != 0

//line mmmix/mmixconfig.w:1100
}
