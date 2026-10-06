% NNIX: 크누스가 만들지 않은 MMIX의 운영체제를 조금씩 만들어 본다.
%
% 크누스는 MMIX의 운영체제를 NNIX라고 부르고는 만들지 않았다(mmixdoc.w 2절).
% 메타 시뮬레이터 mmmix는 그 자리를 ``마법''으로 메운다. rT 자리에서 RESUME 1을
% 배정하면 MMIX-SIM의 입출력 트랩 열 가지가 뒤에서 순식간에 일어난다.
%
% 1단계(2026-10-06): 진짜 트랩 처리기. 트랩을 나누고, 사용자 메모리에서 인자를
%   읽고, 가상 주소를 물리 주소로 바꾸고, 장치 레지스터를 거쳐 입출력을 시킨다.
% 2단계: 커널이 먼저 부팅하고, 진짜 페이지 테이블과 요구 페이징을 쓴다.
%   mmmix가 실어 둔 프로그램 이미지는 ``디스크의 실행 파일''로 치고, 사용자가
%   처음 건드리는 페이지마다 새 프레임을 꺼내 이미지에서 복사해 들인다.
%
%   mmixal -b 250 -o nnix.mmo nnix.mms
%   mmmix -knnix.mmo plain.mmconfig hello.mmb
%
% mmmix의 -k는 미리 짜 둔 환경을 준비한 뒤에 이 커널을 싣고, 사용자 프로그램이
% 시작할 곳을 rWW에 넣은 채 Boot에서 출발시킨다. 미리 가져온 UNSAVE가 먼저
% 사용자의 레지스터를 되살린다.
%
% 물리 메모리 배치:
%   0 .. 4<<32    mmmix가 실은 프로그램 이미지(세그먼트 i가 i<<32에)
%   4<<32         mmmix의 뼈대 페이지 테이블(부팅 뒤로는 쓰지 않는다)
%   5<<32         이 커널의 코드와 데이터
%   7<<32         사용자의 페이지 테이블. 세그먼트마다 한 페이지(PTE 1024개)
%   8<<32 ..      빈 프레임 풀. 앞에서부터 하나씩 꺼낸다.
%   2^48+d<<16    장치 d. 지금은 d=0인 HIO 하나뿐이다.
%
% 사용자의 rV는 #12340D0700000008이다. b1..b4=1,2,3,4, 페이지 크기 2^13,
% 테이블 뿌리 r=7<<32, 주소 공간 번호 n=1, 하드웨어 변환(f=0)이다. 세그먼트마다
% 테이블이 한 페이지뿐이라 세그먼트마다 처음 1024페이지(8MB)만 쓸 수 있다.
%
% 커널은 인터럽트를 끈 채로 돈다. 그래서 커널이 하드웨어 변환으로 비어 있는
% 사용자 페이지를 읽으면 폴트가 나지 않고 조용히 0이 읽힌다. 그러므로 커널은
% 사용자 메모리를 언제나 UserPA로 변환해서(필요하면 페이지를 들이면서) 만진다.
% 다만 처리기의 PUSHJ가 사용자의 지역 레지스터를 스택 세그먼트(rS)로 쏟을 수 있으므로,
% 스택 세그먼트의 처음 StackPages 페이지는 부팅할 때 미리 들여놓는다.
%
% 장치는 레지스터 RV에 사용자의 rV를 받아 같은 페이지 테이블로 주소를 변환한다
% (IOMMU). 그래서 커널은 사용자의 가상 주소를 그대로 넘기고, 넘기기 전에 버퍼의
% 페이지를 들여놓기만 한다. 버퍼의 프레임이 물리 메모리에 흩어져 있어도 된다.
%
% 파이프라인에서 장치를 다룰 때 지킬 것(mmmix의 v40 추적으로 확인했다):
%   - 장치 적재는 투기적으로 일어나고, 앞선 저장을 쓰기 버퍼에서 앞지를 수 있다.
%     그래서 장치를 읽는 일에는 부작용이 없게 했다.
%   - 같은 주소에 연달아 저장하면 쓰기 버퍼에서 합쳐져 앞의 값이 사라진다.
%     커널은 앞 명령이 끝날 때까지(DONE이 바뀔 때까지) 기다린 뒤에 다음 명령을 낸다.
%   - SYNC 4로 멈추면 쓰기 버퍼에 남은 저장이 버려진다. 그래서 SYNC 5를 먼저 한다.

% 호스트 입출력 장치의 레지스터. 모두 옥타바이트다.
HIO     IS    #8001             장치 0의 기준 주소(SETH로 만든다)
ID      IS    #00               읽기: 상수 "NNIX-HIO"
ARG0    IS    #08               쓰기: 첫째 인자
ARG1    IS    #10               쓰기: 둘째 인자
CMD     IS    #18               쓰기: (op<<8)|handle, 닿는 순간 실행
RESULT  IS    #20               읽기: 마지막 명령의 결과
DONE    IS    #28               읽기: 지금까지 끝낸 명령의 수
RV      IS    #30               읽고 쓰기: 주소를 변환할 rV 값

% 연산 코드는 TRAP의 Y와 같다(Fopen=1 .. Ftell=10). 0은 트립 경고다.
TripWarn IS    0
MaxOp   IS    10

PageS   IS    13                페이지 크기는 2^13바이트
StackPages IS    4              부팅할 때 들여놓는 스택 세그먼트의 페이지 수

        LOC   #8000000500000000
% 부팅. mmmix가 사용자 프로그램의 시작 주소를 rWW에, 음수를 rXX에 넣어 두었고,
% 미리 가져온 UNSAVE가 사용자의 레지스터를 되살려 두었다. 트랩 입구와 같은 모양으로
% 사용자의 지역 레지스터를 숨기고 Init을 부른 뒤, RESUME 1로 사용자에게 간다.
Boot    PUT   rK,0              커널은 인터럽트를 끈 채로 돈다
        PUT   rBB,$255          RESUME 1이 사용자의 $255를 되돌린다
        GET   $255,rJ
        PUSHJ $255,Init
        PUT   rJ,$255
        NEG   $255,0,1          사용자의 rK: 모두 허용
        RESUME 1                rWW로 간다
Main    IS    Boot

% 트랩 입구. TRAP은 사용자의 $255를 rBB로 옮기고 $255를 rJ로 정한 뒤 여기로 온다.
% 처리기가 마음대로 쓸 수 있는 것은 $255뿐이므로, PUSHJ $255로 사용자의 지역
% 레지스터를 모두 숨기고 새 틀에서 일한다. 전역 레지스터는 건드리지 않는다.
TrapEnt PUSHJ $255,Syscall
        PUT   rJ,$255           TRAP이 $255에 넣어 둔 사용자의 rJ를 되돌린다
        NEG   $255,0,1          돌아갈 때의 rK: 모두 허용(원시 처리기와 같다)
        RESUME 1                rK<-$255, $255<-rBB

% 동적 트랩 입구. 레지스터를 넘겨받는 모양은 TRAP과 같다.
DynEnt  PUSHJ $255,Fault
        PUT   rJ,$255
        NEG   $255,0,1
        RESUME 1

% Init: 트랩 주소를 정하고, 스택 세그먼트의 앞부분을 들여놓고, rV와 장치의 RV를
% 사용자의 페이지 테이블로 바꾼다. 테이블은 처음에 비어 있다(메모리는 0이다).
        PREFIX Init:
t       IS    $0
k       IS    $1
rj      IS    $2
res     IS    $3
:Init   GET   rj,:rJ
        GETA  t,:TrapEnt
        PUT   :rT,t
        GETA  t,:DynEnt
        PUT   :rTT,t
        SET   k,0
1H      SETH  res+1,#6000
        SLU   t,k,:PageS
        OR    res+1,res+1,t
        PUSHJ res,:PageIn       스택 세그먼트의 k번 페이지
        ADD   k,k,1
        CMP   t,k,:StackPages
        BN    t,1B
        SETH  t,#1234
        ORMH  t,#0D07
        ORL   t,#0008           t=사용자의 rV
        PUT   :rV,t
        SETH  k,:HIO
        STO   t,k,:RV
        SYNC  6                 변환 캐시를 지운다
        PUT   :rJ,rj
        POP   0,0
        PREFIX :

% 시스템 호출. rXX의 아랫 테트라가 TRAP 0,Y,Z이고 Y<=10일 때만 일한다.
% 그 밖에는 마법처럼 rBB를 그대로 두고 돌아간다.
        PREFIX Syscall:
t       IS    $0
op      IS    $1                Y
h       IS    $2                Z (파일 핸들)
a0      IS    $3                장치의 첫째 인자
a1      IS    $4                장치의 둘째 인자
kind    IS    $5                인자를 가져오는 방식
rj      IS    $6                안에서 PUSHJ를 하므로 rJ를 여기 둔다
res     IS    $7                부르는 서브루틴의 결과 자리
:Syscall GET   rj,:rJ
        GET   t,:rXX
        SLU   t,t,32
        SRU   t,t,32            t = rXX의 아랫 테트라
        SRU   op,t,16
        BNZ   op,Done           opcode나 X가 0이 아니면 TRAP 0,Y,Z가 아니다
        SRU   op,t,8            op = Y
        AND   h,t,#ff           h = Z
        CMP   t,op,:MaxOp
        BP    t,Done
        BZ    op,Stop
% 인자를 가져온다. 방식은 ArgKind 표에 있다.
%   0: 인자 없음
%   1: 사용자의 M[rBB], M[rBB+8]을 읽고, 앞의 것이 가리키는 바이트 문자열을 들인다
%   2: 1처럼 읽고, 버퍼 [M[rBB], M[rBB]+M[rBB+8])을 쓰기 허가로 들인다
%   3: 2와 같되 읽기 허가로 들인다
%   4: rBB가 가리키는 바이트 문자열을 들인다
%   5: rBB가 가리키는 와이드 문자열을 들인다
%   6: rBB를 값 그대로 넘긴다
        GETA  t,:ArgKind
        LDBU  kind,t,op
        SET   a0,0
        SET   a1,0
        BZ    kind,Call
        GET   a0,:rBB
        CMP   t,kind,4
        BNN   t,1F
        SET   res+1,a0          사용자의 인자 블록은 UserPA로 읽는다
        INCL  res+1,8
        SETL  res+2,4
        PUSHJ res,:UserPA
        BN    res,Bad
        ORH   res,#8000
        LDO   a1,res,0          a1=M[rBB+8]
        SET   res+1,a0
        SETL  res+2,4
        PUSHJ res,:UserPA
        BN    res,Bad
        ORH   res,#8000
        LDO   a0,res,0          a0=M[rBB]
1H      CMP   t,kind,6
        BZ    t,Call
        SET   res+1,a0
        CMP   t,kind,2
        BZ    t,Wbuf
        CMP   t,kind,3
        BZ    t,Rbuf
        SETL  res+2,1           바이트 문자열
        CMP   t,kind,5
        BNZ   t,2F
        SETL  res+2,2           와이드 문자열
2H      PUSHJ res,:Scan
        JMP   3F
Wbuf    SET   res+2,a1
        SETL  res+3,2           p_w
        PUSHJ res,:Prefault
        JMP   3F
Rbuf    SET   res+2,a1
        SETL  res+3,4           p_r
        PUSHJ res,:Prefault
3H      BN    res,Bad
Call    SET   res+1,a0
        SET   res+2,a1
        SLU   t,op,8
        OR    res+3,t,h
        PUSHJ res,:Device
        PUT   :rBB,res          RESUME 1이 이것을 사용자의 $255에 넣는다
Done    PUT   :rJ,rj
        POP   0,0
Bad     NEG   t,0,1
        PUT   :rBB,t
        JMP   Done

% Stop: Halt. Z=0이면 멈추고, Z=1이면 기본 트립 처리기(TRAP 1)가 부른 것이므로
% 트립 경고를 찍는다. 마법처럼 rBB는 그대로 둔다.
Stop    BNZ   h,Warn
        GET   $255,:rBB         종료 코드는 Halt할 때의 사용자 $255다(mmmix -s)
:Halt5  SYNC  5                 쓰기 버퍼를 비운다
1H      SYNC  4
        JMP   1B
Warn    CMP   t,h,1
        BNZ   t,Done
        GET   t,:rWW
        SUBU  t,t,4             트립이 일어난 처리기 자리
        CMPU  a0,t,#f0
        BNN   a0,Done
        SRU   res+1,t,4         트립 번호
        GET   res+2,:rW
        SUBU  res+2,res+2,4     트립이 일어난 위치
        SETL  res+3,:TripWarn
        PUSHJ res,:Device
        JMP   Done
        PREFIX :

% Fault: 동적 트랩. 사용자가 비어 있는 페이지를 건드려 r, w, x 보호 결함이
% 나면 그 페이지를 들인다. 적재와 저장은 RESUME 1이 다시 실행하고(ropcode 0),
% 가상 주소는 rYY에 있다. 명령을 가져오다 난 x 결함은 그 명령이 SWYM으로 바뀌어
% 확정되므로, rWW를 그 명령으로 되돌려 다시 가져오게 한다.
% 다른 인터럽트는 원시 처리기처럼 모두 지운다.
        PREFIX Fault:
t       IS    $0
q       IS    $1
va      IS    $2
rj      IS    $3
res     IS    $4
:Fault  GET   rj,:rJ
        GET   q,:rQ
        SETMH t,#00e0           rQ의 r, w, x 비트
        AND   t,q,t
        BZ    t,Other
        SRU   t,t,32
        AND   t,t,#20
        GET   va,:rYY
        BZ    t,1F
        GET   va,:rWW
        SUBU  va,va,4
        PUT   :rWW,va
1H      SET   res+1,va
        PUSHJ res,:PageIn
        BNZ   res,Kill          들일 수 없거나 이미 있다(진짜 보호 위반)
        GET   q,:rQ
        SETMH t,#00e0
        ANDN  q,q,t
        PUT   :rQ,q
        SYNC  6                 실패한 변환이 캐시에 남지 않게 한다
        PUT   :rJ,rj
        POP   0,0
Other   PUT   :rQ,0
        PUT   :rJ,rj
        POP   0,0
% 들일 수 없는 폴트. 표준 오류에 알리고 멈춘다. 장치는 음수 주소를 물리 주소로 본다.
Kill    GETA  res+1,:KillMsg
        SET   res+2,0
        SETL  res+3,:Fputs<<8|:StdErr
        PUSHJ res,:Device
        NEG   $255,0,1
        JMP   :Halt5
        PREFIX :

% PageIn(va): va가 든 페이지를 들인다. 빈 프레임을 하나 꺼내, 프로그램 이미지의
% 같은 페이지(세그먼트 i의 페이지 p라면 물리 주소 i<<32+p<<13)를 복사하고, PTE를
% 쓴다. 텍스트 세그먼트는 rwx, 나머지는 rw-다(뼈대 페이지 테이블과 같다).
% 돌려주는 값: 0이면 들였고, 1이면 이미 있었고, -1이면 범위 밖이다.
        PREFIX PageIn:
seg     IS    $1
pg      IS    $2
pte     IS    $3
frame   IS    $5
src     IS    $6
lim     IS    $8
:PageIn BN    $0,9F             사용자의 주소는 음이 아니어야 한다
        SRU   seg,$0,61
        ANDNH $0,#e000
        SRU   pg,$0,:PageS
        SRU   $4,pg,10
        BNZ   $4,9F             세그먼트마다 처음 1024페이지뿐이다
        SETH  pte,#8000
        ORMH  pte,#0007         테이블의 커널 주소
        SLU   $4,seg,:PageS
        ADDU  pte,pte,$4
        8ADDU pte,pg,pte        pte=PTE의 주소
        LDO   $4,pte,0
        BNZ   $4,8F
        GETA  $4,:FreeFrame
        LDO   frame,$4,0
        SETL  lim,#2000
        ADDU  $7,frame,lim
        STO   $7,$4,0           다음 빈 프레임
        SETH  src,#8000
        SLU   $4,seg,32
        OR    src,src,$4
        SLU   $4,pg,:PageS
        OR    src,src,$4        src=이미지 안의 같은 페이지
        SET   $7,0
1H      LDO   $4,src,$7
        STO   $4,frame,$7
        ADDU  $7,$7,8
        CMP   $4,$7,lim
        BN    $4,1B
        BNZ   seg,3F
% 텍스트 페이지는 명령으로 쓰인다. 복사한 것은 아직 D-캐시에만 있을 수 있고 I-캐시는
% 메모리에서 채우므로, 음수 주소의 SYNCD로 메모리에 내려보내고 캐시에서 없앤다.
        SET   $7,0
4H      SYNCD #ff,frame,$7
        INCL  $7,#100
        CMP   $4,$7,lim
        BN    $4,4B
3H      ANDNH frame,#8000       물리 주소
        ORL   frame,#8          n=1
        SET   $4,6              rw-
        BNZ   seg,2F
        SET   $4,7              rwx
2H      OR    frame,frame,$4
        STO   frame,pte,0
        SET   $0,0
        POP   1,0
8H      SET   $0,1
        POP   1,0
9H      NEG   $0,0,1
        POP   1,0
        PREFIX :

% UserPA(va,need): 사용자의 가상 주소 va를 물리 주소로 바꾼다. 페이지가 없으면
% 들인 뒤 다시 바꾼다. 보호 비트에 need가 없거나 들일 수 없으면 -1이다.
        PREFIX UserPA:
need    IS    $1
rj      IS    $2
res     IS    $3
:UserPA GET   rj,:rJ
        SET   res+1,$0
        SET   res+2,need
        PUSHJ res,:Translate
        BNN   res,9F
        SET   res+1,$0
        PUSHJ res,:PageIn
        BNZ   res,8F
        SET   res+1,$0
        SET   res+2,need
        PUSHJ res,:Translate
        JMP   9F
8H      NEG   res,0,1
9H      PUT   :rJ,rj
        SET   $0,res
        POP   1,0
        PREFIX :

% Prefault(va,len,need): [va,va+len)이 걸친 페이지를 모두 들인다. 0이나 -1.
        PREFIX Prefault:
len     IS    $1
need    IS    $2
last    IS    $3
m       IS    $4
rj      IS    $5
res     IS    $6
:Prefault GET   rj,:rJ
        SET   res,0
        BZ    len,9F
        ADDU  last,$0,len
        SUBU  last,last,1
        SETL  m,#1fff
        ANDN  last,last,m       마지막 페이지
1H      SET   res+1,$0
        SET   res+2,need
        PUSHJ res,:UserPA
        BN    res,9F
        ANDN  $0,$0,m
        INCL  $0,#2000          다음 페이지
        CMPU  res,$0,last
        BNP   res,1B
        SET   res,0
9H      PUT   :rJ,rj
        SET   $0,res
        POP   1,0
        PREFIX :

% Scan(va,w): 너비 w(바이트면 1, 와이드면 2)의 문자열이 끝날 때까지 그것이
% 걸친 페이지를 들인다. 0이나 -1.
        PREFIX Scan:
w       IS    $1
p       IS    $2
c       IS    $3
m       IS    $4
rj      IS    $5
res     IS    $6
:Scan   GET   rj,:rJ
        SETL  m,#1fff
1H      SET   res+1,$0
        SETL  res+2,4
        PUSHJ res,:UserPA
        BN    res,9F
        ORH   res,#8000
        SET   p,res
2H      LDBU  c,p,0
        CMP   res,w,1
        BZ    res,3F
        LDWU  c,p,0
3H      BZ    c,8F
        ADDU  $0,$0,w
        ADDU  p,p,w
        AND   res,$0,m
        BNZ   res,2B            같은 페이지 안이다
        JMP   1B
8H      SET   res,0
9H      PUT   :rJ,rj
        SET   $0,res
        POP   1,0
        PREFIX :

% Device(a0,a1,cmd): HIO에 명령 하나를 시키고 그 결과를 돌려준다.
% 앞 명령이 끝났으므로 쓰기 버퍼에 이 장치로 가는 저장은 남아 있지 않다.
% DONE은 순수하게 읽히므로 투기적으로 읽혀도 상관없고, 값이 바뀔 때까지 돈다.
% 그 뒤의 SYNC 2는 RESULT를 DONE보다 먼저 읽지 못하게 막는다.
        PREFIX Device:
dev     IS    $3
seq     IS    $4
:Device SETH  dev,:HIO
        LDO   seq,dev,:DONE
        STO   $0,dev,:ARG0
        STO   $1,dev,:ARG1
        STO   $2,dev,:CMD
1H      LDO   $5,dev,:DONE
        CMPU  $5,$5,seq
        BZ    $5,1B
        SYNC  2
        LDO   $0,dev,:RESULT
        POP   1,0
        PREFIX :

% Translate(virt,need): 음이 아닌 가상 주소 virt를 물리 주소로 바꾼다.
% 그 페이지의 보호 비트에 need(p_r=4, p_w=2)가 모두 있어야 하고,
% 실패하면 -1을 돌려준다. 물리 주소는 2^48보다 작으므로 실패와 헷갈리지 않는다.
%
% 가운데 부분은 크누스가 명세(mmixdoc.w 47절)에 적은 소프트웨어 변환 코드를
% 거의 그대로 옮긴 것이다. 다른 점은 셋이다. virt를 rYY 대신 인자로 받고,
% 맨 끝에서 PTE를 rZZ에 넣고 RESUME하는 대신 물리 주소를 만들어 POP하고,
% 실패하면 PTE 0 대신 -1을 돌려준다.
        PREFIX Translate:
virt    IS    $8
base    IS    $9
limit   IS    $10
s       IS    $11
mask    IS    $12
need    IS    $13
:Translate SET   virt,$0
        SET   need,$1
        BN    virt,Fail         사용자의 주소는 음이 아니어야 한다
        GET   $7,:rV            $7=(가상 변환 레지스터)
        SRU   $1,virt,61        $1=i (가상 주소의 세그먼트 번호)
        SLU   $1,$1,2
        NEG   $1,52,$1          $1=52-4i
        SRU   $1,$7,$1
        SLU   $2,$1,4
        SETL  $0,#f000
        AND   $1,$1,$0          $1=b[i]<<12
        AND   $2,$2,$0          $2=b[i+1]<<12
        SLU   $3,$7,24
        SRU   $3,$3,37
        SLU   $3,$3,13          $3=(rV의 r 필드)
        ORH   $3,#8000          $3을 물리 주소로 만든다
        2ADDU base,$1,$3        base=첫 페이지 테이블의 주소
        2ADDU limit,$2,$3       limit=마지막 페이지 테이블 다음의 주소
        SRU   s,$7,40
        AND   s,s,#ff           s=(rV의 s 필드)
        CMP   $0,s,13
        BN    $0,Fail           s는 13 이상이어야 한다
        CMP   $0,s,49
        BNN   $0,Fail           s는 48 이하여야 한다
        SETH  mask,#8000
        ORL   mask,#1ff8        mask=(부호 비트와 n 필드)
        ORH   $7,#8000          아래의 PTP 검증을 위해 부호 비트를 켠다
        ANDNH virt,#e000        세그먼트 번호를 지운다
        SRU   $0,virt,s         $0=a4a3a2a1a0 (virt의 페이지 번호)
        ZSZ   $1,$0,1           $1=[페이지 번호가 0이다]
        ADD   limit,limit,$1    페이지 번호가 0이면 limit를 늘린다
        SETL  $6,#3ff
% 페이지 번호의 ``자릿수''를 오른쪽에서 왼쪽으로 찾는다.
        CMP   $5,base,limit
        SRU   $1,$0,10
        PBZ   $1,1F
        AND   $0,$0,$6
        INCL  base,#2000
        CMP   $5,base,limit
        SRU   $2,$1,10
        PBZ   $2,2F
        AND   $1,$1,$6
        INCL  base,#2000
        CMP   $5,base,limit
        SRU   $3,$2,10
        PBZ   $3,3F
        AND   $2,$2,$6
        INCL  base,#2000
        CMP   $5,base,limit
        SRU   $4,$3,10
        PBZ   $4,4F
        AND   $3,$3,$6
        INCL  base,#2000
% PTP들을 거쳐 거꾸로 폭포처럼 내려온다.
        CMP   $5,base,limit
        BNN   $5,Fail
        8ADDU $6,$4,base
        LDO   base,$6,0
        XOR   $6,base,$7
        AND   $6,$6,mask
        BNZ   $6,Fail
        ANDNL base,#1fff
4H      BNN   $5,Fail
        8ADDU $6,$3,base
        LDO   base,$6,0
        XOR   $6,base,$7
        AND   $6,$6,mask
        BNZ   $6,Fail
        ANDNL base,#1fff
3H      BNN   $5,Fail
        8ADDU $6,$2,base
        LDO   base,$6,0
        XOR   $6,base,$7
        AND   $6,$6,mask
        BNZ   $6,Fail
        ANDNL base,#1fff
2H      BNN   $5,Fail
        8ADDU $6,$1,base
        LDO   base,$6,0
        XOR   $6,base,$7
        AND   $6,$6,mask
        BNZ   $6,Fail
        ANDNL base,#1fff        PTP의 아래 13비트를 없앤다
1H      BNN   $5,Fail
        8ADDU $6,$0,base
        LDO   base,$6,0         base=PTE
        XOR   $6,base,$7
        ANDN  $6,$6,#7
        SLU   $6,$6,51
        PBZ   $6,Ready          n이 맞으면 분기한다
Fail    NEG   $0,0,1
        POP   1,0
% 여기부터는 크누스의 코드가 아니다. 보호 비트를 보고 물리 주소를 만든다.
% PTE = x(16) a(48-s) y(s-13) n(10) p(3)이고, 물리 주소는 2^s a + (virt mod 2^s)다.
Ready   AND   $6,base,need
        CMP   $6,$6,need
        BNZ   $6,Fail
        SETL  $6,1
        SLU   $6,$6,s
        SUBU  $6,$6,1           $6=2^s-1
        AND   $0,virt,$6        페이지 안의 오프셋
        ANDN  base,base,$6      y, n, p를 지운다
        ANDNH base,#ffff        x를 지운다
        OR    $0,base,$0
        POP   1,0
        PREFIX :

FreeFrame OCTA  #8000000800000000 다음 빈 프레임의 커널 주소
KillMsg BYTE  "NNIX: page fault I can't serve",#a,0
ArgKind BYTE  0,1,0,2,2,2,3,4,5,6,0
