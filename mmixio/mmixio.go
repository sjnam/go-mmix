//line mmixio.w:35
package mmixio

import (
	"bufio"
	"fmt"
	"io"
	"os"

	"github.com/sjnam/go-mmix/mmixarith"
)

//line mmixio.w:58
type (
	Tetra = mmixarith.Tetra
	Octa  = mmixarith.Octa

//line mmixio.w:61
)

const filenameMax = 1024

//line mmixio.w:78
type Simulator interface {
	StdinChr() byte
	MMGetChars(buf []byte, size int, addr Octa, stop int) int
	MMPutChars(buf []byte, size int, addr Octa)
}

//line mmixio.w:87
type simFileInfo struct {
	fp   *stream // file pointer
	mode int     // [read OK] + 2[write OK] + 4[binary] + 8[readwrite]
}

//line mmixio.w:96
type IO struct {
	sfile   [256]simFileInfo
	sim     Simulator
	streams []*stream // every file stream opened so far (for |FlushAll|)
	stderr  *stream   // the original standard error, i.e., \CEE/'s |stderr|
}

//line mmixio.w:622
type stream struct {
	f          *os.File      // if a real file
	r          *bufio.Reader // buffer for reading from |f|
	pending    []byte        // bytes not yet written to |f|
	writing    bool          // was the last thing done a write?
	w          io.Writer     // if standard output or standard error
	isStdin    bool          // is it the simulated program's standard input?
	eof        bool          // end-of-file indicator (|feof|)
	bad        bool          // error indicator (|ferror|)
	unbuffered bool          // is it unbuffered (like |stderr|)?
}

//line mmixio.w:161
var modeFlags = [5]int{
	os.O_RDONLY,                            // \.{"r"}
	os.O_WRONLY | os.O_CREATE | os.O_TRUNC, // \.{"w"}
	os.O_RDONLY,                            // \.{"rb"}
	os.O_WRONLY | os.O_CREATE | os.O_TRUNC, // \.{"wb"}
	os.O_RDWR | os.O_CREATE | os.O_TRUNC,   // \.{"w+b"}
}

//line mmixio.w:168
var modeCode = [5]int{0x1, 0x2, 0x5, 0x6, 0xf}

//line mmixio.w:599
var tripWarning = [...]string{
	"TRIP",
	"integer divide check",
	"integer overflow",
	"float-to-fix overflow",
	"invalid floating point operation",
	"floating point overflow",
	"floating point underflow",
	"floating point division by zero",
	"floating point inexact"}

//line mmixio.w:109
func New(sim Simulator, stdout, stderr io.Writer) *IO {
	x := &IO{sim: sim}
	x.sfile[0] = simFileInfo{&stream{isStdin: true}, 1}
	x.sfile[1] = simFileInfo{&stream{w: stdout}, 2}
	x.stderr = &stream{w: stderr, unbuffered: true}
	x.sfile[2] = simFileInfo{x.stderr, 2}
	return x
}

//line mmixio.w:128
func (x *IO) Fopen(handle byte, name, mode Octa) Octa {
	var nameBuf [filenameMax]byte
	if mode > 4 {
		return x.abort(handle)
	}
	m := x.sim.MMGetChars(nameBuf[:], filenameMax, name, 0)
	if m == filenameMax {
		return x.abort(handle)
	}
	if x.sfile[handle].mode != 0 && handle > 2 {
		x.sfile[handle].fp.close()
	}
	f, err := os.OpenFile(string(nameBuf[:m]), modeFlags[mode], 0o666)
	if err != nil {
		return x.abort(handle)
	}
	x.sfile[handle].fp = &stream{f: f, r: bufio.NewReader(f)}
	x.streams = append(x.streams, x.sfile[handle].fp)
	x.sfile[handle].mode = modeCode[mode]
	return 0 // success
}

func (x *IO) abort(handle byte) Octa {
	x.sfile[handle].mode = 0
	return mmixarith.NegOne // failure
}

//line mmixio.w:174
func (x *IO) FakeStdin(f *os.File) {
	x.sfile[0].fp = &stream{f: f, r: bufio.NewReader(f)} // |f| should be open for reading
	x.streams = append(x.streams, x.sfile[0].fp)
}

//line mmixio.w:180
func (x *IO) Fclose(handle byte) Octa {
	if x.sfile[handle].mode == 0 {
		return mmixarith.NegOne
	}
	if handle > 2 && !x.sfile[handle].fp.close() {
		return mmixarith.NegOne
	}
	x.sfile[handle].mode = 0
	return 0 // success
}

//line mmixio.w:204
func (x *IO) Fread(handle byte, buffer, size Octa) Octa {
	o := mmixarith.NegOne
	if x.sfile[handle].mode&0x1 == 0 {
		return o - size
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x2
	}
	if size>>32 != 0 {
		return o - size
	}

//line mmixio.w:224
	fp := x.sfile[handle].fp
	buf := make([]byte, min(size, 1<<16))
	n := 0
	if fp.isStdin {
		for n < int(size) {
			k := min(int(size)-n, len(buf))
			for i := range k {
				buf[i] = x.sim.StdinChr()
			}
			x.sim.MMPutChars(buf, k, buffer+Octa(n))
			n += k
		}
	} else {
		fp.clearerr()
		for n < int(size) {
			k := fp.read(buf[:min(int(size)-n, len(buf))])
			if fp.bad {
				return o - size
			}
			x.sim.MMPutChars(buf, k, buffer+Octa(n))
			n += k
			if fp.eof {
				break
			}
		}
	}

//line mmixio.w:216
	return Octa(n) - size
}

//line mmixio.w:256
func (x *IO) Fgets(handle byte, buffer, size Octa) Octa {
	var buf [256]byte
	var n, s int
	var o Octa
	eof := false
	if x.sfile[handle].mode&0x1 == 0 {
		return mmixarith.NegOne
	}
	if size == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x2
	}
	size--
	for {

//line mmixio.w:289
		s = 255
		if size < Octa(s) {
			s = int(size)
		}
		fp := x.sfile[handle].fp
		if fp.isStdin {
			for n = 0; n < s; {
				buf[n] = x.sim.StdinChr()
				n++
				if buf[n-1] == '\n' {
					break
				}
			}
		} else {
			if !fp.fgets(buf[:], s+1) {
				return mmixarith.NegOne
			}
			eof = fp.eof
			for n = 0; n < s; {
				if buf[n] == 0 && eof {
					break
				}
				n++
				if buf[n-1] == '\n' {
					break
				}
			}
		}
		buf[n] = 0

//line mmixio.w:273
		x.sim.MMPutChars(buf[:], n+1, buffer)
		o += Octa(n)
		size -= Octa(n)
		if (n > 0 && buf[n-1] == '\n') || size == 0 || eof {
			return o
		}
		buffer += Octa(n)
	}
}

//line mmixio.w:331
func (x *IO) Fgetws(handle byte, buffer, size Octa) Octa {
	var buf [256]byte
	var n, s int
	var o Octa
	eof := false
	if x.sfile[handle].mode&0x1 == 0 {
		return mmixarith.NegOne
	}
	if size == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x2
	}
	buffer &^= 1
	size--
	for {

//line mmixio.w:363
		s = 127
		if size < Octa(s) {
			s = int(size)
		}
		fp := x.sfile[handle].fp
		p := 0
		if fp.isStdin {
			for n = 0; n < s; {
				buf[p], buf[p+1] = x.sim.StdinChr(), x.sim.StdinChr()
				p += 2
				n++
				if buf[p-1] == '\n' && buf[p-2] == 0 {
					break
				}
			}
		} else {
			for n = 0; n < s; {
				if fp.read(buf[p:p+2]) != 2 {
					eof = fp.eof
					if !eof {
						return mmixarith.NegOne
					}
					break
				}
				n++
				p += 2
				if buf[p-1] == '\n' && buf[p-2] == 0 {
					break
				}
			}
		}
		buf[p], buf[p+1] = 0, 0

//line mmixio.w:349
		x.sim.MMPutChars(buf[:], 2*n+2, buffer)
		o += Octa(n)
		size -= Octa(n)
		if (n > 0 && buf[2*n-1] == '\n' && buf[2*n-2] == 0) || size == 0 || eof {
			return o
		}
		buffer += 2 * Octa(n)
	}
}

//line mmixio.w:403
func (x *IO) Fwrite(handle byte, buffer, size Octa) Octa {
	var buf [256]byte
	var n int
	if x.sfile[handle].mode&0x2 == 0 {
		return -size
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x1
	}
	for {
		if size >= 256 {
			n = x.sim.MMGetChars(buf[:], 256, buffer, -1)
		} else {
			n = x.sim.MMGetChars(buf[:], int(size), buffer, -1)
		}
		size -= Octa(n)
		if x.sfile[handle].fp.write(buf[:n]) != n {
			return -size
		}
		x.sfile[handle].fp.flush()
		if size == 0 {
			return 0
		}
		buffer += Octa(n)
	}
}

//line mmixio.w:433
func (x *IO) Fputs(handle byte, str Octa) Octa {
	var buf [256]byte
	var o Octa
	if x.sfile[handle].mode&0x2 == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x1
	}
	for {
		n := x.sim.MMGetChars(buf[:], 256, str, 0)
		if x.sfile[handle].fp.write(buf[:n]) != n {
			return mmixarith.NegOne
		}
		o += Octa(n)
		if n < 256 {
			x.sfile[handle].fp.flush()
			return o
		}
		str += Octa(n)
	}
}

//line mmixio.w:469
func (x *IO) Fputws(handle byte, str Octa) Octa {
	var buf [256]byte
	var o Octa
	if x.sfile[handle].mode&0x2 == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode &^= 0x1
	}
	for {
		n := x.sim.MMGetChars(buf[:], 256, str, 1)
		if n < 0 {
			x.sfile[handle].fp.bad = true // the original |fwrite| fails and sets the error indicator
			return mmixarith.NegOne
		}
		if x.sfile[handle].fp.write(buf[:n]) != n {
			return mmixarith.NegOne
		}
		o += Octa(n >> 1)
		if n < 256 {
			x.sfile[handle].fp.flush()
			return o
		}
		str += Octa(n)
	}
}

//line mmixio.w:502
func (x *IO) Fseek(handle byte, offset Octa) Octa {
	if x.sfile[handle].mode&0x4 == 0 {
		return mmixarith.NegOne
	}
	if x.sfile[handle].mode&0x8 != 0 {
		x.sfile[handle].mode = 0xf
	}
	if offset&mmixarith.SignBit != 0 {
		if offset>>31 != 0x1ffffffff {
			return mmixarith.NegOne
		}
		if !x.sfile[handle].fp.seek(int64(int32(offset))+1, io.SeekEnd) {
			return mmixarith.NegOne
		}
	} else {
		if offset>>31 != 0 {
			return mmixarith.NegOne
		}
		if !x.sfile[handle].fp.seek(int64(offset), io.SeekStart) {
			return mmixarith.NegOne
		}
	}
	return 0
}

//line mmixio.w:532
func (x *IO) Ftell(handle byte) Octa {
	if x.sfile[handle].mode&0x4 == 0 {
		return mmixarith.NegOne
	}
	pos, ok := x.sfile[handle].fp.tell()
	if !ok || pos < 0 {
		return mmixarith.NegOne
	}
	return Octa(Tetra(pos))
}

//line mmixio.w:552
func (x *IO) PrintTripWarning(n int, loc Octa) {
	if x.sfile[2].mode&0x2 != 0 {
		x.sfile[2].fp.fprintf("Warning: %s at location %016x\n", tripWarning[n], loc)
	}
}

func (s *stream) fprintf(format string, a ...any) {
	if s.bad && s.unbuffered {
		return
	}
	s.write(fmt.Appendf(nil, format, a...))
}

//line mmixio.w:571
func (x *IO) StderrError() bool {
	return x.stderr.bad
}

//line mmixio.w:587
func (x *IO) FlushAll() {
	for h := range 3 {
		if x.sfile[h].fp.f == nil { // an original standard stream
			x.sfile[h].fp.flush()
		}
	}
	for _, fp := range x.streams {
		fp.flush()
	}
}

//line mmixio.w:638
func (s *stream) read(p []byte) int {
	if s.eof || s.r == nil {
		return 0
	}
	s.startReading()
	n, err := io.ReadFull(s.r, p)
	switch err {
	case nil:
	case io.EOF, io.ErrUnexpectedEOF:
		s.eof = true
	default:
		s.bad = true
	}
	return n
}

func (s *stream) clearerr() { s.eof, s.bad = false, false }

//line mmixio.w:662
func (s *stream) fgets(buf []byte, n int) bool {
	if n <= 0 || s.r == nil {
		return false
	}
	i := 0
	for i < n-1 {
		if s.eof {
			break
		}
		s.startReading()
		c, err := s.r.ReadByte()
		if err != nil {
			if err == io.EOF {
				s.eof = true
			} else {
				s.bad = true
			}
			break
		}
		buf[i] = c
		i++
		if c == '\n' {
			break
		}
	}
	if i == 0 && n > 1 {
		return false
	}
	buf[i] = 0
	return true
}

//line mmixio.w:703
func (s *stream) startReading() {
	if s.writing {
		s.flush()
		s.writing = false
	}
}

//line mmixio.w:721
func (s *stream) write(p []byte) int {
	if s.f != nil {
		if !s.writing {
			s.r.Reset(s.f) // discard the read buffer
			s.eof, s.writing = false, true
		}
		s.pending = append(s.pending, p...)
		return len(p)
	}
	if s.w == nil {
		return 0
	}
	n, err := s.w.Write(p)
	if err != nil {
		s.bad = true
	}
	return n
}

func (s *stream) flush() bool {
	if s.f != nil && len(s.pending) > 0 {
		_, err := s.f.Write(s.pending)
		s.pending = s.pending[:0]
		if err != nil {
			s.bad = true
			return false
		}
	}
	if f, ok := s.w.(interface{ Flush() error }); ok {
		f.Flush()
	}
	return true
}

//line mmixio.w:761
func (s *stream) seek(off int64, whence int) bool {
	if s.f == nil || !s.flush() {
		return false
	}
	if _, err := s.f.Seek(off, whence); err != nil {
		return false
	}
	s.r.Reset(s.f)
	s.eof, s.writing = false, false
	return true
}

func (s *stream) tell() (int64, bool) {
	if s.f == nil {
		return 0, false
	}
	pos, err := s.f.Seek(0, io.SeekCurrent)
	if err != nil {
		return 0, false
	}
	return pos - int64(s.r.Buffered()) + int64(len(s.pending)), true
}

func (s *stream) close() bool {
	if s.f == nil {
		return true
	}
	ok := s.flush()
	return s.f.Close() == nil && ok
}
