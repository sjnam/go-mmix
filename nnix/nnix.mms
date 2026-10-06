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
% 3단계: 프로세스 여럿. 새 시스템 호출 Fork(TRAP 0,11,0)가 주소 공간을 복사해
%   자식을 만들고, 구간 계수기 rI의 타이머 인터럽트가 SAVE와 UNSAVE로 프로세스를
%   번갈아 돌린다. Halt는 그 프로세스만 끝내고, 마지막 프로세스가 끝나면 멈춘다.
% 4단계: 파일 시스템. mmmix -d로 붙인 블록 장치의 디스크(NNIXFS, 호스트 도구
%   nnixfs로 만든다)를 부팅할 때 마운트하고, 파일 연산을 커널이 직접 한다.
%   표준 입출력(핸들 0, 1, 2)은 그대로 HIO로 보낸다. 디스크가 없으면 3단계처럼
%   모든 입출력을 HIO로 보낸다.
% 5단계: Exec과 Wait. Exec(TRAP 0,12,0)은 디스크의 목적 파일을 지금 프로세스의 새
%   주소 공간에 싣고 MMIX-SIM과 같은 실행 환경을 차려 실행한다. Wait(TRAP 0,13,0)은
%   끝난 자식을 거둔다. 이 둘과 Fork로 셸(nnix/sh.mms)이 디스크의 프로그램을 돌린다.
% 8단계: PTP. 세그먼트마다 테이블 페이지를 셋 두고 중간 테이블은 필요할 때 만든다.
%   세그먼트마다 8MB이던 한계가 8TB가 된다.
% 6단계: 프레임 회수와 쓸 때 복사. 프레임마다 참조 계수를 두고, 끝난 프로세스와 Exec이
%   버린 주소 공간의 프레임을 빈 목록으로 돌려받는다. Fork는 스택 세그먼트 말고는 페이지를
%   복사하지 않고 함께 쓰며, 쓰기 허가를 끄고 PTE의 x 필드에 COW 표시를 해 둔다. 누가
%   거기에 쓰면 그때 복사한다.
% 7단계: 인터럽트로 하는 입출력. 블록 장치는 명령마다 시간이 걸리고, 끝나면 rQ의 입출력
%   비트를 켠다. 디스크를 기다리는 프로세스는 커널 안에서 SAVE하고 잠들며(커널 연속),
%   그동안 다른 프로세스가 돈다. 블록 캐시를 함께 쓰므로 파일 시스템에는 자물쇠를 둔다.
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
%   6<<32         커널 메모리: FAT 16KB, 디렉터리 4KB, 블록 캐시 1KB, 줄 버퍼 1KB,
%                 #5800에 Exec의 인자 버퍼, #8000에 핸들 표(256개 x 64바이트),
%                 #c000에 Exec의 커널 핸들, #10000에 늘 0인 페이지, #18000에 프레임 관리
%                 (다음 새 프레임, 빈 목록의 머리), #20000부터 프레임마다의 참조 계수
%   7<<32         프로세스 p의 페이지 테이블이 7<<32+p<<17에. 세그먼트마다 세 페이지
%                 (수준 0, 1, 2). PTP가 가리키는 중간 테이블은 프레임 풀에서 꺼낸다
%   8<<32 ..      프레임 풀. 빈 목록에서 먼저 꺼내고, 없으면 앞에서부터 새로 꺼낸다.
%   2^48+d<<16    장치 d. d=0은 HIO, d=1은 블록 장치다.
%
% 프로세스 p의 rV는 #369C0D0700000000+p<<17+(p+1)<<3이다. b1..b4=3,6,9,12(mmmix가
% 미리 짜 두는 환경과 같다), 페이지 크기 2^13, 테이블 뿌리 r=7<<32+p<<17, 주소 공간
% 번호 n=p+1, 하드웨어 변환(f=0)이다. 주소 공간 번호가 프로세스마다 다르므로 프로세스를
% 바꿀 때 변환 캐시를 비우지 않는다. 세그먼트 i의 테이블은 뿌리에서 3i, 3i+1, 3i+2번째
% 페이지다. 페이지 번호를 1024진 자릿수 a2 a1 a0로 쓰면, 1024보다 작은 페이지의 PTE는
% 첫 테이블에, 그다음 백만 페이지는 둘째 테이블의 PTP를 거쳐, 그다음 십억 페이지는 셋째
% 테이블의 PTP 둘을 거쳐 찾는다(mmixdoc.w 45절). 그래서 세그먼트마다 2^30페이지(8TB)를
% 쓸 수 있다. 7단계까지는 b1..b4=1,2,3,4로 세그먼트마다 테이블이 한 페이지(8MB)뿐이었다.
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
Fork    IS    11                TRAP 0,Fork,0: 부모는 자식의 pid를, 자식은 0을 받는다

% 프로세스 표. 항목마다 옥타바이트 여덟 개다.
NProc   IS    4                 프로세스는 넷까지(2의 거듭제곱이어야 한다)
ST      IS    0                 0: 빈 자리, 1: 돌 수 있다, 2: 좀비, 3: Wait으로 잠들었다, 4: 커널 안에서 잠들었다
RVO     IS    8                 이 프로세스의 rV
CTX     IS    16                SAVE가 돌려준 문맥의 주소(이 프로세스의 가상 주소)
BBO     IS    24                rBB (사용자의 $255)
WWO     IS    32                rWW
XXO     IS    40                rXX
YYO     IS    48                rYY
ZZO     IS    56                rZZ
Quantum IS    10000             타이머의 한 조각(사이클)
PAR     IS    64                부모의 pid(없으면 -1)
BACK    IS    72                1이면 비어 있는 페이지를 프로그램 이미지에서, 0이면 0으로 채워 들인다
PShift  IS    7                 항목은 128바이트다
SCHAN   IS    80                상태 4일 때 기다리는 것(1: 디스크, 2: 파일 시스템 자물쇠)
KPC     IS    88                커널 안에서 잠들었으면 깨어나 돌아갈 커널 주소(아니면 0)
S255    IS    96                그때의 $255
DiskBit IS    #100              블록 장치가 명령을 끝내면 켜는 rQ의 비트(ANDNL로 지운다)
Exec    IS    12                TRAP 0,Exec,0: $255는 널로 끝나는 argv 배열. 성공하면 돌아오지 않는다
Wait    IS    13                TRAP 0,Wait,0: 끝난 자식 하나를 거두어 그 pid를(자식이 없으면 -1)
MaxArg  IS    32                Exec의 인자는 32개까지
EBufOff IS    #5800             Exec이 인자 문자열을 옮겨 두는 곳(4KB)
IHOff   IS    #c000             Exec이 목적 파일을 읽는 커널 핸들
COW     IS    #0001             PTE의 x 필드(하드웨어가 무시한다)의 쓸 때 복사 표시. ORH와 ANDNH로 다룬다

% 블록 장치(장치 1)의 레지스터. ID, CMD, RESULT, DONE의 오프셋은 HIO와 같다.
BLK     IS    #8001             장치 1의 기준 주소는 SETH BLK와 ORML BLKLO로 만든다
BLKLO   IS    #0001
BBLOCK  IS    #08               쓰기: 블록 번호
BADDR   IS    #10               쓰기: 메모리 쪽 버퍼의 주소
BSize   IS    1024              블록의 바이트 수

% 파일 시스템(nnixfs/nnixfs.w의 형식과 같다)과 그 커널 메모리(6<<32부터)
NDirBlk IS    4                 디렉터리의 블록 수
NEnt    IS    64                디렉터리 항목의 수
NameMax IS    47                이름의 최대 길이
MaxFatBlk IS  16                커널이 올릴 수 있는 FAT의 블록 수
DirOff  IS    #4000             디렉터리의 오프셋(FAT는 0에)
BufOff  IS    #5000             블록 캐시의 오프셋
LineOff IS    #5400             줄 버퍼의 오프셋
HOff    IS    #8000             핸들 표의 오프셋
HKIND   IS    0                 핸들 항목: 0이면 닫힘, 1이면 콘솔, 2면 파일
HMODE   IS    8                 mmixio의 방식 코드
HENT    IS    16                디렉터리 항목의 번호
HPOS    IS    24                위치
HCBLK   IS    32                위치가 든 디스크 블록(0이면 모른다)
HCIDX   IS    40                그 블록의 파일 안 번호

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
% rJ는 그대로 있으므로 $255는 마음대로 써도 된다. Fork와 Wait이면 곧바로 문맥을 저장하고,
% 아니면 PUSHJ $255로 사용자의 지역 레지스터를 모두 숨기고 새 틀에서 일한다.
% 전역 레지스터는 건드리지 않는다.
TrapEnt GET   $255,rXX
        SLU   $255,$255,32
        SRU   $255,$255,40      $255=rXX의 아랫 테트라에서 opcode, X, Y
        CMP   $255,$255,Fork
        BZ    $255,DoFork
        GET   $255,rXX
        SLU   $255,$255,32
        SRU   $255,$255,40
        CMP   $255,$255,Wait
        BZ    $255,DoWait
        GET   $255,rJ
        PUSHJ $255,Syscall
        PUT   rJ,$255           사용자의 rJ를 되돌린다
        NEG   $255,0,1          돌아갈 때의 rK: 모두 허용(원시 처리기와 같다)
        RESUME 1                rK<-$255, $255<-rBB

% 동적 트랩 입구. 레지스터를 넘겨받는 모양은 TRAP과 같다. 보호 결함(r, w, x)을
% 먼저 보고, 그다음 디스크를 본다. 타이머라면 돌 수 있는 프로세스가 둘 이상일 때만 프로세스를 바꾸고,
% 혼자면 타이머를 끈다(rI를 다시 걸지 않는다). 나머지는 Fault가 지운다.
DynEnt  GET   $255,rQ
        SRU   $255,$255,32
        AND   $255,$255,#e0
        BNZ   $255,1F           보호 결함
        GET   $255,rQ
        SRU   $255,$255,8
        AND   $255,$255,1
        BNZ   $255,DiskTick     디스크가 명령을 끝냈다
        GET   $255,rQ
        AND   $255,$255,#40     구간 인터럽트
        BZ    $255,1F
        GETA  $255,NReady
        LDO   $255,$255,0
        CMP   $255,$255,1
        BP    $255,Tick
        GET   $255,rQ
        ANDN  $255,$255,#40
        PUT   rQ,$255
        NEG   $255,0,1
        RESUME 1
1H      GET   $255,rJ
        PUSHJ $255,Fault
        PUT   rJ,$255
        NEG   $255,0,1
        RESUME 1

% Init: 트랩 주소를 정하고, rV와 장치의 RV를 프로세스 0의 페이지 테이블로 바꾸고,
% 스택 세그먼트의 앞부분을 들여놓는다. 테이블은 처음에 비어 있다(메모리는 0이다).
% 부팅 때 레지스터 고리는 거의 비어 있으므로, rV를 바꾼 뒤에 지역 레지스터가
% 아직 들이지 않은 스택 페이지로 쏟아질 일은 없다.
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
        SETH  t,#8000
        ORMH  t,#0006
        ORML  t,#0001
        ORL   t,#8000
        SETH  k,#8000
        ORMH  k,#0008
        STO   k,t,0             첫 새 프레임은 8<<32다
        GETA  t,:Procs
        LDO   t,t,:RVO          프로세스 0의 rV
        PUT   :rV,t
        SETH  k,:HIO
        STO   t,k,:RV
        SET   k,0
1H      SETH  res+1,#6000
        SLU   t,k,:PageS
        OR    res+1,res+1,t
        PUSHJ res,:PageIn       스택 세그먼트의 k번 페이지
        ADD   k,k,1
        CMP   t,k,:StackPages
        BN    t,1B
        PUSHJ res,:Mount        디스크가 있으면 마운트한다
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
x       IS    $7                핸들 표의 항목
res     IS    $8                부르는 서브루틴의 결과 자리
:Syscall GET   rj,:rJ
        GET   t,:rXX
        SLU   t,t,32
        SRU   t,t,32            t = rXX의 아랫 테트라
        SRU   op,t,16
        BNZ   op,Done           opcode나 X가 0이 아니면 TRAP 0,Y,Z가 아니다
        SRU   op,t,8            op = Y
        AND   h,t,#ff           h = Z
        BZ    op,Stop
        CMP   t,op,:Exec
        BNZ   t,4F
        GET   res+1,:rBB
        PUSHJ res,:DoExec       돌아오면 실패한 것이다
        JMP   Ret
4H      CMP   t,op,:MaxOp
        BP    t,Done
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
        BZ    kind,1F
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
% 디스크가 있으면 핸들 표를 본다. Fopen과 파일은 FsOp가, 콘솔은 HIO가 맡는다.
1H      GETA  t,:Mounted
        LDO   t,t,0
        BZ    t,Con
        SETH  x,#8000
        ORMH  x,#0006
        SETL  t,:HOff
        ADDU  x,x,t
        SLU   t,h,6
        ADDU  x,x,t             x=핸들 h의 항목
        CMP   t,op,:Fopen
        BZ    t,Fs
        LDO   t,x,:HKIND
        CMP   t,t,1
        BZ    t,Con
Fs      SET   res+1,x
        SET   res+2,op
        SET   res+3,a0
        SET   res+4,a1
        PUSHJ res,:FsOp
        JMP   Ret
Con     BZ    kind,Call
        CMP   t,kind,6
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
Ret     PUT   :rBB,res          RESUME 1이 이것을 사용자의 $255에 넣는다
Done    PUT   :rJ,rj
        POP   0,0
Bad     NEG   t,0,1
        PUT   :rBB,t
        JMP   Done

% Stop: Halt. Z=0이면 Exit으로 이 프로세스를 끝내고, Z=1이면 기본 트립 처리기(TRAP 1)가 부른 것이므로
% 트립 경고를 찍는다. 마법처럼 rBB는 그대로 둔다.
Stop    BNZ   h,Warn
        JMP   :Exit             종료 코드는 Halt할 때의 사용자 $255, 곧 rBB다
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
        BZ    res,2F
        BN    res,Kill          범위 밖
        SET   res+1,va
        PUSHJ res,:CowBreak     이미 있다면 쓸 때 복사하는 페이지인가
        BNZ   res,Kill          진짜 보호 위반
2H      GET   q,:rQ
        SETMH t,#00e0
        ANDN  q,q,t
        PUT   :rQ,q
        SYNC  6                 실패한 변환이 캐시에 남지 않게 한다
        PUT   :rJ,rj
        POP   0,0
Other   PUT   :rQ,0
        PUT   :rJ,rj
        POP   0,0
% 들일 수 없는 폴트. 표준 오류에 알리고 이 프로세스를 끝낸다. 장치는 음수 주소를 물리 주소로 본다.
Kill    GETA  res+1,:KillMsg
        SET   res+2,0
        SETL  res+3,:Fputs<<8|:StdErr
        PUSHJ res,:Device
        NEG   t,0,1
        PUT   :rBB,t
        JMP   :Exit             이 프로세스를 -1로 끝낸다
        PREFIX :

% PageIn(va): 지금 프로세스에서 va가 든 페이지를 들인다. 빈 프레임을 하나 꺼내,
% 프로그램 이미지의 같은 페이지(세그먼트 i의 페이지 p라면 물리 주소 i<<32+p<<13)를
% 복사하고(Exec한 프로세스이거나 이미지 너머의 페이지라면 0으로 채우고), PTE를 쓴다.
% PTE의 자리는 PteSlot이 찾고, 모자라는 중간 테이블은 그때 만든다. 텍스트 세그먼트는
% rwx, 나머지는 rw-다(뼈대 페이지 테이블과 같다).
% 돌려주는 값: 0이면 들였고, 1이면 이미 있었고, -1이면 범위 밖이다.
        PREFIX PageIn:
seg     IS    $1
pg      IS    $2
pte     IS    $3
t       IS    $4
rv      IS    $5
rj      IS    $6
frame   IS    $7
res     IS    $8
:PageIn GET   rj,:rJ
        BN    $0,9F             사용자의 주소는 음이 아니어야 한다
        GET   rv,:rV
        SET   res+1,rv
        SET   res+2,$0
        SETL  res+3,1
        PUSHJ res,:PteSlot
        BZ    res,9F            세그먼트마다 2^30페이지까지다
        SET   pte,res
        LDO   t,pte,0
        BNZ   t,8F
        SRU   seg,$0,61
        ANDNH $0,#e000
        SRU   pg,$0,:PageS
        PUSHJ res,:AllocFrame
        SET   frame,res
        GETA  t,:Cur
        LDO   t,t,0
        SLU   t,t,:PShift
        GETA  res+1,:Procs
        ADDU  t,t,res+1
        LDO   t,t,:BACK
        SETH  res+1,#8000
        BZ    t,1F
        SRU   t,pg,19
        BNZ   t,1F              이미지는 세그먼트마다 2^32바이트까지다
        SLU   t,seg,32
        OR    res+1,res+1,t
        SLU   t,pg,:PageS
        OR    res+1,res+1,t     이미지 안의 같은 페이지
        JMP   3F
1H      ORMH  res+1,#0006
        ORML  res+1,#0001       늘 0인 페이지
3H      SET   res+2,frame
        ZSZ   res+3,seg,1       텍스트 세그먼트인가
        PUSHJ res,:CopyPage
        ANDNH frame,#8000       물리 주소
        SETL  t,#1ff8
        AND   t,rv,t
        OR    frame,frame,t     주소 공간 번호
        SET   t,6               rw-
        BNZ   seg,2F
        SET   t,7               rwx
2H      OR    frame,frame,t
        STO   frame,pte,0
        PUT   :rJ,rj
        SET   $0,0
        POP   1,0
8H      PUT   :rJ,rj
        SET   $0,1
        POP   1,0
9H      PUT   :rJ,rj
        NEG   $0,0,1
        POP   1,0
        PREFIX :

% PteSlot(rv,va,alloc): rV가 rv인 주소 공간에서 가상 주소 va의 PTE 자리(커널 주소).
% 세그먼트 i의 수준 d 테이블은 뿌리에서 3i+d번째 페이지다. 페이지 번호가 1024 이상이면
% 수준 1이나 2의 테이블에서 PTP를 따라 내려간다. 중간 테이블이 없으면 alloc이 0이
% 아닐 때만 만들고, 아니면 0이다. 페이지 번호가 2^30 이상이어도 0이다. 만들 때는 수준 1
% 테이블의 항목 0에 표시를 한다. 페이지 번호 0..1023은 수준 0에 있으므로 이 칸은 하드웨어도
% Translate도 장치도 읽지 않는다. Walk는 표시가 없는 세그먼트의 수준 1과 2를 건너뛴다.
        PREFIX Slot:
rv      IS    $0
va      IS    $1
alloc   IS    $2
seg     IS    $3
pg      IS    $4
base    IS    $5
t       IS    $6
n3      IS    $7
d       IS    $8
rj      IS    $9
res     IS    $10
:PteSlot BN   va,Zero
        SRU   seg,va,61
        ANDNH va,#e000
        SRU   pg,va,:PageS
        SLU   base,rv,24
        SRU   base,base,37
        SLU   base,base,13
        ORH   base,#8000        뿌리
        SLU   t,seg,1
        ADD   t,t,seg
        SLU   t,t,:PageS
        ADDU  base,base,t       세그먼트의 수준 0 테이블
        SETL  t,#1ff8
        AND   n3,rv,t           주소 공간 번호(n<<3)
        SRU   d,pg,10
        BNZ   d,1F
        8ADDU $0,pg,base        수준 0
        POP   1,0
1H      GET   rj,:rJ
        BZ    alloc,4F
        SETL  t,#2000
        ADDU  t,base,t
        STCO  1,t,0             이 세그먼트가 PTP를 쓴다는 표시(수준 1 테이블의 항목 0)
4H      SRU   t,pg,20
        BNZ   t,2F
        SETL  t,#2000
        ADDU  base,base,t       수준 1 테이블
        SRU   t,pg,10           a1
        8ADDU res+1,t,base
        SET   res+2,alloc
        SET   res+3,n3
        PUSHJ res,:Follow
        JMP   3F
2H      SRU   t,pg,30
        BNZ   t,Fail
        SETL  t,#4000
        ADDU  base,base,t       수준 2 테이블
        SRU   t,pg,20           a2
        8ADDU res+1,t,base
        SET   res+2,alloc
        SET   res+3,n3
        PUSHJ res,:Follow
        BZ    res,Fail
        SRU   t,pg,10
        SETL  d,#3ff
        AND   t,t,d             a1
        8ADDU res+1,t,res
        SET   res+2,alloc
        SET   res+3,n3
        PUSHJ res,:Follow
3H      BZ    res,Fail
        SETL  d,#3ff
        AND   t,pg,d            a0
        8ADDU $0,t,res
        PUT   :rJ,rj
        POP   1,0
Fail    PUT   :rJ,rj
Zero    SET   $0,0
        POP   1,0
        PREFIX :

% Follow(pslot,alloc,n3): PTP 자리 pslot이 가리키는 다음 테이블의 커널 주소. PTP가
% 없으면 alloc이 0이 아닐 때만 0으로 채운 프레임을 꺼내 테이블로 삼고 PTP를 쓴다.
% PTP는 부호 비트, 테이블의 물리 주소, 주소 공간 번호로 이루어진다. 프레임의 커널 주소가
% 이미 부호 비트를 가지므로 거기에 n<<3만 더하면 된다.
Follow  LDO   $3,$0,0
        BZ    $3,1F
        SETL  $4,#1fff
        ANDN  $0,$3,$4
        POP   1,0
1H      BZ    $1,9F
        GET   $5,rJ
        PUSHJ $6,AllocFrame
        PUT   rJ,$5
        SET   $7,0
        SETL  $8,#2000
2H      STCO  0,$6,$7
        ADDU  $7,$7,8
        CMP   $9,$7,$8
        BN    $9,2B
        OR    $3,$6,$2
        STO   $3,$0,0
        SET   $0,$6
        POP   1,0
9H      SET   $0,0
        POP   1,0

% Walk(rv,cb,arg,nseg,free): rV가 rv인 주소 공간의 세그먼트 0..nseg-1에 든 PTE마다
% cb(자리,가상 주소,arg)를 PUSHGO로 부른다. free가 0이 아니면 PTP가 가리키던 중간
% 테이블의 프레임도 다 훑은 뒤에 돌려주고 그 PTP를 지운다. 수준 1과 2의 테이블에서
% 항목 0은 쓰지 않는다(페이지 번호 0..1023은 수준 0에 있다).
        PREFIX Walk:
rv      IS    $0
cb      IS    $1
arg     IS    $2
nseg    IS    $3
free    IS    $4
seg     IS    $5
base    IS    $6
i       IS    $7
j       IS    $8
k       IS    $9
e       IS    $10               윗 테이블의 PTP 자리
ps      IS    $11               가운데 테이블의 PTP 자리
c       IS    $12               PTE 테이블
c2      IS    $13               가운데 테이블
vb      IS    $14               세그먼트의 가상 주소
t       IS    $15
sl      IS    $16               PTE 자리
rj      IS    $17
res     IS    $18
:Walk   GET   rj,:rJ
        SET   seg,0
Seg     CMP   t,seg,nseg
        BNN   t,Done
        SLU   vb,seg,61
        SLU   base,rv,24
        SRU   base,base,37
        SLU   base,base,13
        ORH   base,#8000        뿌리
        SLU   t,seg,1
        ADD   t,t,seg
        SLU   t,t,:PageS
        ADDU  base,base,t       이 세그먼트의 수준 0 테이블(뿌리에서 3i번째 페이지)
% 수준 0
        SET   i,0
L0      8ADDU sl,i,base
        LDO   t,sl,0
        BZ    t,L0n
        SET   res+1,sl
        SLU   res+2,i,:PageS
        OR    res+2,res+2,vb
        SET   res+3,arg
        PUSHGO res,cb,0
L0n     ADD   i,i,1
        SETL  t,1024
        CMP   t,i,t
        BN    t,L0
        SETL  t,#2000
        ADDU  t,base,t
        LDO   t,t,0
        BZ    t,NextS           이 세그먼트는 PTP를 쓰지 않는다
% 수준 1: 페이지 번호 a1 a0
        SET   i,1
L1      SETL  t,#2000
        ADDU  e,base,t
        8ADDU e,i,e
        LDO   c,e,0
        BZ    c,L1n
        SETL  t,#1fff
        ANDN  c,c,t
        SET   j,0
L1a     8ADDU sl,j,c
        LDO   t,sl,0
        BZ    t,L1b
        SET   res+1,sl
        SLU   res+2,i,10
        OR    res+2,res+2,j
        SLU   res+2,res+2,:PageS
        OR    res+2,res+2,vb
        SET   res+3,arg
        PUSHGO res,cb,0
L1b     ADD   j,j,1
        SETL  t,1024
        CMP   t,j,t
        BN    t,L1a
        BZ    free,L1n
        SET   res+1,c
        PUSHJ res,:DecRef
        STCO  0,e,0
L1n     ADD   i,i,1
        SETL  t,1024
        CMP   t,i,t
        BN    t,L1
% 수준 2: 페이지 번호 a2 a1 a0
        SET   i,1
L2      SETL  t,#4000
        ADDU  e,base,t
        8ADDU e,i,e
        LDO   c2,e,0
        BZ    c2,L2n
        SETL  t,#1fff
        ANDN  c2,c2,t
        SET   j,0
L2a     8ADDU ps,j,c2
        LDO   c,ps,0
        BZ    c,L2d
        SETL  t,#1fff
        ANDN  c,c,t
        SET   k,0
L2b     8ADDU sl,k,c
        LDO   t,sl,0
        BZ    t,L2c
        SET   res+1,sl
        SLU   res+2,i,10
        OR    res+2,res+2,j
        SLU   res+2,res+2,10
        OR    res+2,res+2,k
        SLU   res+2,res+2,:PageS
        OR    res+2,res+2,vb
        SET   res+3,arg
        PUSHGO res,cb,0
L2c     ADD   k,k,1
        SETL  t,1024
        CMP   t,k,t
        BN    t,L2b
        BZ    free,L2d
        SET   res+1,c
        PUSHJ res,:DecRef
        STCO  0,ps,0
L2d     ADD   j,j,1
        SETL  t,1024
        CMP   t,j,t
        BN    t,L2a
        BZ    free,L2n
        SET   res+1,c2
        PUSHJ res,:DecRef
        STCO  0,e,0
L2n     ADD   i,i,1
        SETL  t,1024
        CMP   t,i,t
        BN    t,L2
        BZ    free,NextS
        SETL  t,#2000
        ADDU  t,base,t
        STCO  0,t,0             표시를 지운다
NextS   ADD   seg,seg,1
        JMP   Seg
Done    PUT   :rJ,rj
        POP   0,0
        PREFIX :

% Walk의 콜백들. 모두 (자리,가상 주소,arg)를 받는다.
% FreeCb: PTE를 지우고 그 프레임의 참조를 놓는다.
FreeCb  LDO   $3,$0,0
        STCO  0,$0,0
        SETL  $4,#1fff
        ANDN  $6,$3,$4
        ANDNH $6,#ffff
        ORH   $6,#8000
        GET   $4,rJ
        PUSHJ $5,DecRef
        PUT   rJ,$4
        POP   0,0
% SyncCb: 그 프레임을 SYNCD로 메모리에 내려보낸다(CopyPage를 보라).
SyncCb  LDO   $3,$0,0
        SETL  $4,#1fff
        ANDN  $3,$3,$4
        ANDNH $3,#ffff
        ORH   $3,#8000
        SET   $4,0
        SETL  $5,#2000
1H      SYNCD #ff,$3,$4
        INCL  $4,#100
        CMP   $6,$4,$5
        BN    $6,1B
        POP   0,0

% 프레임 관리. 커널 메모리 #8000000600018000에 다음 새 프레임(FMTop)과 빈 목록의
% 머리(FMFree)를 두고, #8000000600020000부터 프레임마다 참조 계수 바이트를 둔다.
% 빈 프레임은 그 첫 옥타바이트에 다음 빈 프레임을 적어 목록으로 잇는다.
% AllocFrame(): 프레임 하나를 꺼내 참조 계수를 1로 하고 그 커널 주소를 돌려준다.
AllocFrame GET $2,rJ
        SETH  $1,#8000
        ORMH  $1,#0006
        ORML  $1,#0001
        ORL   $1,#8000          FMTop, FMFree
        LDO   $0,$1,8
        BZ    $0,1F
        LDO   $3,$0,0
        STO   $3,$1,8           빈 목록에서 꺼낸다
        JMP   2F
1H      LDO   $0,$1,0
        SETL  $3,#2000
        ADDU  $3,$0,$3
        STO   $3,$1,0           새로 꺼낸다
2H      SET   $4,$0
        PUSHJ $3,RefCnt
        SETL  $4,1
        STB   $4,$3,0
        PUT   rJ,$2
        POP   1,0

% RefCnt(f): 프레임 f(커널 주소)의 참조 계수 바이트의 커널 주소.
RefCnt  ANDNH $0,#8000
        SETL  $1,8
        SLU   $1,$1,32
        SUBU  $0,$0,$1
        SRU   $0,$0,13          프레임 번호
        SETH  $1,#8000
        ORMH  $1,#0006
        ORML  $1,#0002
        ADDU  $0,$0,$1
        POP   1,0

% IncRef(f), DecRef(f): 참조 계수를 하나 늘리고 줄인다. 0이 되면 빈 목록에 넣는다.
IncRef  GET   $1,rJ
        SET   $3,$0
        PUSHJ $2,RefCnt
        PUT   rJ,$1
        LDBU  $3,$2,0
        ADD   $3,$3,1
        STB   $3,$2,0
        POP   0,0
DecRef  GET   $1,rJ
        SET   $3,$0
        PUSHJ $2,RefCnt
        PUT   rJ,$1
        LDBU  $3,$2,0
        SUB   $3,$3,1
        STB   $3,$2,0
        BP    $3,9F
        SETH  $4,#8000
        ORMH  $4,#0006
        ORML  $4,#0001
        ORL   $4,#8000
        LDO   $5,$4,8
        STO   $5,$0,0
        STO   $0,$4,8           빈 목록의 머리가 된다
9H      POP   0,0

% FreeSpace(): 지금 프로세스의 페이지 테이블을 비우고 프레임들과 중간 테이블들의 참조를
% 놓는다. 그다음 옛 변환을 변환 캐시에서 지운다.
FreeSpace GET $0,rJ
        GET   $2,rV
        GETA  $3,FreeCb
        SET   $4,0
        SETL  $5,4
        SETL  $6,1
        PUSHJ $1,Walk
        SYNC  6
        PUT   rJ,$0
        POP   0,0

% CowBreak(va): 지금 프로세스에서 va가 든 쓸 때 복사 페이지를 쓸 수 있게 한다. 그 프레임을
% 혼자 쓰고 있으면 쓰기 허가만 되돌리고, 함께 쓰고 있으면 새 프레임에 복사해 그것으로 바꾼다.
% COW 표시가 없는 페이지면 -1이다(진짜 보호 위반).
        PREFIX Cow:
va      IS    $0
seg     IS    $1
pg      IS    $2
pte     IS    $3
t       IS    $4
old     IS    $5
e       IS    $6
rj      IS    $7
nf      IS    $8
res     IS    $9
:CowBreak GET  rj,:rJ
        SRU   seg,va,61
        GET   res+1,:rV
        SET   res+2,va
        SET   res+3,0
        PUSHJ res,:PteSlot
        BZ    res,9F
        SET   pte,res           pte=PTE의 주소
        LDO   e,pte,0
        SRU   t,e,48
        AND   t,t,1
        BZ    t,9F              쓸 때 복사하는 페이지가 아니다
        SETL  t,#1fff
        ANDN  old,e,t
        ANDNH old,#ffff
        ORH   old,#8000         지금 프레임
        SET   res+1,old
        PUSHJ res,:RefCnt
        LDBU  t,res,0
        CMP   t,t,1
        BZ    t,1F              혼자 쓴다
        PUSHJ res,:AllocFrame
        SET   nf,res
        SET   res+1,old
        SET   res+2,nf
        ZSZ   res+3,seg,1       텍스트 세그먼트인가
        PUSHJ res,:CopyPage
        SET   res+1,old
        PUSHJ res,:DecRef
        SETL  t,#1fff
        AND   e,e,t             주소 공간 번호와 보호 비트만 남긴다
        ANDNH nf,#8000
        OR    e,e,nf
1H      OR    e,e,2             쓰기 허가
        ANDNH e,:COW
        STO   e,pte,0
        SYNC  6
        PUT   :rJ,rj
        SET   $0,0
        POP   1,0
9H      PUT   :rJ,rj
        NEG   $0,0,1
        POP   1,0
        PREFIX :

% CopyPage(src,dst,text): 커널 주소 src의 페이지를 dst로 복사한다. text가 0이
% 아니면 그 페이지는 명령으로 쓰인다. 복사한 것은 아직 D-캐시에만 있을 수 있고
% I-캐시는 메모리에서 채우므로, 음수 주소의 SYNCD로 메모리에 내려보내고 캐시에서
% 없앤다.
CopyPage SET   $3,0
        SETL  $4,#2000
1H      LDO   $5,$0,$3
        STO   $5,$1,$3
        ADDU  $3,$3,8
        CMP   $5,$3,$4
        BN    $5,1B
        BZ    $2,9F
        SET   $3,0
2H      SYNCD #ff,$1,$3
        INCL  $3,#100
        CMP   $5,$3,$4
        BN    $5,2B
9H      POP   0,0

% UserPA(va,need): 사용자의 가상 주소 va를 물리 주소로 바꾼다. 페이지가 없으면
% 들인 뒤 다시 바꾼다. 쓰려는데 쓸 때 복사하는 페이지면 먼저 복사한다. 보호 비트에
% need가 없거나 들일 수 없으면 -1이다.
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
        BN    res,8F
        BZ    res,7F
        AND   res,need,2        이미 있다. 쓰려는 것이면 쓸 때 복사하는 페이지일 수 있다
        BZ    res,8F
        SET   res+1,$0
        PUSHJ res,:CowBreak
        BNZ   res,8F
7H      SET   res+1,$0
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

% 문맥 바꾸기. Tick(타이머)과 DoFork(Fork)는 입구에서 곧바로 온다. 그때 rJ와 지역
% 레지스터는 사용자의 것이고, 사용자의 $255는 rBB에, 재개 정보는 rWW..rZZ에 있다.
% SAVE $255,0은 나머지를 모두 이 프로세스의 레지스터 스택(스택 세그먼트)에 저장하고
% 문맥의 주소를 $255에 돌려준다. 그 뒤로 레지스터 스택은 비어 있으므로 커널은
% 지역 레지스터를 마음대로 쓰고 서브루틴을 부를 수 있다. 다만 그 아래로 POP하면
% 안 된다. Resume은 다른 프로세스의 rV로 바꾸고 그 재개 정보를 되돌린 뒤, UNSAVE로
% 그 문맥을 되살리고 RESUME 1로 넘어간다.
        PREFIX Sched:
t       IS    $0
e       IS    $1
c       IS    $2
cp      IS    $3
u       IS    $4
res     IS    $5
:Tick   SAVE  $255,0
        GET   t,:rQ
        ANDN  t,t,#40
        PUT   :rQ,t             구간 인터럽트를 지운다
        SETL  t,:Quantum
        PUT   :rI,t             다음 조각
        SET   res+1,$255
        PUSHJ res,:Store
        PUSHJ res,:Next
        SET   t,res
        JMP   :Resume

% DiskTick: 디스크가 명령을 끝냈다는 인터럽트. rQ의 비트를 지우고 디스크를 기다리던
% 프로세스를 깨운 뒤 곧바로 그쪽으로 넘어간다(Next는 지금 프로세스 다음부터 찾는다). 깨어난
% 프로세스는 대개 조금 계산하고 다음 블록을 요청하며 다시 잠드므로, 다음 틱까지 기다리게
% 하면 디스크가 놀게 된다. 깨울 프로세스가 없으면 Next가 지금 프로세스를 돌려준다.
:DiskTick SAVE $255,0
        GET   t,:rQ
        ANDNL t,:DiskBit
        PUT   :rQ,t
        SET   res+1,$255
        PUSHJ res,:Store
        SETL  res+1,1
        PUSHJ res,:Wakeup
        PUSHJ res,:Next
        SET   t,res
        JMP   :Resume

% DoFork: 지금 프로세스의 문맥을 저장하고 빈 자리에 자식을 만든다. 자식은 부모와
% 같은 문맥 주소와 재개 정보를 갖고, 주소 공간은 들여놓은 페이지를 모두 새 프레임에
% 복사해 만든다. 그래서 자식의 스택 세그먼트에도 같은 문맥이 같은 주소에 있다.
% 부모의 rBB는 자식의 pid, 자식의 rBB는 0이다. 빈 자리가 없으면 부모에게 -1을 준다.
:DoFork SAVE  $255,0
        SET   res+1,$255
        PUSHJ res,:Store        부모의 상태
        GETA  t,:Cur
        LDO   t,t,0
        SLU   e,t,:PShift
        GETA  u,:Procs
        ADDU  e,e,u             e=부모의 항목
        SET   cp,0
1H      ADD   cp,cp,1
        CMP   t,cp,:NProc
        BNN   t,Full
        SLU   c,cp,:PShift
        ADDU  c,c,u             c=자식 후보의 항목
        LDO   t,c,:ST
        BNZ   t,1B
        SETL  t,1
        STO   t,c,:ST
        SETH  t,#369C
        ORMH  t,#0D07
        SLU   u,cp,17
        ADDU  t,t,u
        ADD   u,cp,1
        SLU   u,u,3
        ADDU  t,t,u             t=자식의 rV
        STO   t,c,:RVO
        LDO   t,e,:CTX
        STO   t,c,:CTX
        LDO   t,e,:WWO
        STO   t,c,:WWO
        LDO   t,e,:XXO
        STO   t,c,:XXO
        LDO   t,e,:YYO
        STO   t,c,:YYO
        LDO   t,e,:ZZO
        STO   t,c,:ZZO
        STCO  0,c,:BBO          자식에게는 0
        STO   cp,e,:BBO         부모에게는 자식의 pid
        GETA  u,:Cur
        LDO   u,u,0
        STO   u,c,:PAR
        LDO   u,e,:BACK
        STO   u,c,:BACK         뒷받침은 부모와 같다
        GETA  u,:NReady
        LDO   t,u,0
        ADD   t,t,1
        STO   t,u,0
        LDO   res+1,e,:RVO
        LDO   res+2,c,:RVO
        PUSHJ res,:CopySpace
        SYNC  6                 같은 주소 공간 번호를 쓴 옛 프로세스의 변환을 지운다
        SETL  t,:Quantum
        PUT   :rI,t             타이머를 건다
        JMP   2F
Full    NEG   t,0,1
        STO   t,e,:BBO
2H      GETA  t,:Cur
        LDO   t,t,0
        JMP   :Resume           부모로 돌아간다

% Resume(pid=$0): 레지스터 스택을 버리고 프로세스 pid로 넘어간다. rV를 바꾼 뒤로는
% 서브루틴을 부르지 않는다. 레지스터가 쏟아지면 새 주소 공간에 쓰일 것이기 때문이다.
% 그 프로세스가 커널 안에서 잠들었다면(KPC가 0이 아니면) RESUME 대신 커널로 돌아간다.
% SAVE한 문맥의 $255 자리(꼭대기에서 104바이트 아래)에 돌아갈 주소를 써 두면, UNSAVE가
% 그것을 $255에 넣으므로 GO로 갈 수 있다. 원래의 $255는 S255에 두었다가 Sleep이 되돌린다.
:Resume GETA  u,:Cur
        STO   t,u,0
        SLU   e,t,:PShift
        GETA  u,:Procs
        ADDU  e,e,u
        LDO   t,e,:RVO
        PUT   :rV,t
        SETH  u,:HIO
        STO   t,u,:RV           장치도 같은 주소 공간을 본다
        LDO   t,e,:BBO
        PUT   :rBB,t
        LDO   t,e,:WWO
        PUT   :rWW,t
        LDO   t,e,:XXO
        PUT   :rXX,t
        LDO   t,e,:YYO
        PUT   :rYY,t
        LDO   t,e,:ZZO
        PUT   :rZZ,t
        LDO   $255,e,:CTX
        LDO   t,e,:KPC
        BZ    t,1F
        STCO  0,e,:KPC          커널 안에서 잠들었다
        SUBU  u,$255,104        SAVE한 문맥에서 $255의 자리
        LDO   c,u,0
        STO   c,e,:S255
        STO   t,u,0             UNSAVE가 $255에 돌아갈 곳을 넣게 한다
        UNSAVE $255
        GO    $255,$255,0       Sleep으로 돌아간다
1H      UNSAVE $255
        NEG   $255,0,1
        RESUME 1
        PREFIX :

% DoWait: Wait. 문맥을 저장한 뒤 이 프로세스의 자식을 훑는다. 좀비가 있으면 거두어
% 그 pid를 돌려준다. 살아 있는 자식만 있으면 잠들고(상태 3) 다른 프로세스로 넘어간다.
% 자식이 끝날 때 Exit이 깨워 준다. 자식이 하나도 없으면 -1이다.
        PREFIX Wait:
x       IS    $0
e       IS    $1
p       IS    $2
q       IS    $3
t       IS    $4
base    IS    $5
alive   IS    $6
res     IS    $7
:DoWait SAVE  $255,0
        SET   res+1,$255
        PUSHJ res,:Store
        GETA  t,:Cur
        LDO   x,t,0
        GETA  base,:Procs
        SLU   e,x,:PShift
        ADDU  e,e,base          e=이 프로세스의 항목
        SET   alive,0
        SET   p,0
1H      SLU   q,p,:PShift
        ADDU  q,q,base
        LDO   t,q,:ST
        BZ    t,2F              빈 자리의 부모 칸은 옛 값이다
        LDO   t,q,:PAR
        CMP   t,t,x
        BNZ   t,2F
        LDO   t,q,:ST
        CMP   t,t,2
        BZ    t,Reap
        SETL  alive,1
2H      ADD   p,p,1
        CMP   t,p,:NProc
        BN    t,1B
        NEG   t,0,1
        BZ    alive,3F          자식이 없다
        SETL  t,3
        STO   t,e,:ST           잠든다
        GETA  t,:NReady
        LDO   q,t,0
        SUB   q,q,1
        STO   q,t,0
        PUSHJ res,:Next
        SET   $0,res
        JMP   :Resume
Reap    STCO  0,q,:ST           좀비를 거둔다
        SET   t,p
3H      STO   t,e,:BBO
        SET   $0,x
        JMP   :Resume
        PREFIX :

% Exit: 지금 프로세스를 끝낸다. 종료 코드는 rBB(사용자의 $255)에 있다. 레지스터 스택은
% 버린다. 이 프로세스의 자식들은 고아가 되고(좀비는 거둔다), 부모가 Wait으로 잠들어
% 있으면 깨워 이 pid를 돌려주고, 부모가 살아 있으면 좀비로 남아 부모의 Wait을 기다린다.
% 그다음 이 프로세스의 프레임을 돌려준다. 그 뒤에 쏟아지는 레지스터는 사라질 수 있으므로
% 다음 pid는 메모리에 두었다가 읽는다.
% 살아 있는 프로세스가 더 없으면 디스크를 맞추고 기계를 멈춘다(mmmix -s의 종료 코드는
% 이 프로세스의 $255다).
        PREFIX Exit:
x       IS    $0
e       IS    $1
p       IS    $2
q       IS    $3
t       IS    $4
base    IS    $5
u       IS    $6
res     IS    $7
:Exit   GETA  t,:Cur
        LDO   x,t,0
        GETA  base,:Procs
        SLU   e,x,:PShift
        ADDU  e,e,base          e=이 프로세스의 항목
        GETA  t,:NReady
        LDO   u,t,0
        SUB   u,u,1
        STO   u,t,0
        SET   p,0
1H      SLU   q,p,:PShift
        ADDU  q,q,base
        LDO   t,q,:PAR
        CMP   t,t,x
        BNZ   t,2F
        NEG   t,0,1
        STO   t,q,:PAR          고아가 된다
        LDO   t,q,:ST
        CMP   t,t,2
        BNZ   t,2F
        STCO  0,q,:ST           좀비는 거둔다
2H      ADD   p,p,1
        CMP   t,p,:NProc
        BN    t,1B
        STCO  0,e,:ST
        LDO   p,e,:PAR
        BN    p,4F              부모가 없다
        SLU   q,p,:PShift
        ADDU  q,q,base          q=부모의 항목
        LDO   t,q,:ST
        CMP   u,t,3
        BZ    u,3F
        BZ    t,4F
        CMP   u,t,2
        BZ    u,4F              부모가 없거나 좀비다
        SETL  t,2
        STO   t,e,:ST           부모가 거둘 때까지 좀비로 남는다
        JMP   4F
3H      SETL  t,1
        STO   t,q,:ST           부모를 깨운다
        STO   x,q,:BBO          부모의 Wait이 돌려줄 값
        GETA  t,:NReady
        LDO   u,t,0
        ADD   u,u,1
        STO   u,t,0
4H      SET   p,0               살아 있는(1, 3, 4) 프로세스가 남았는가
5H      SLU   q,p,:PShift
        ADDU  q,q,base
        LDO   t,q,:ST
        CMP   u,t,1
        BZ    u,6F
        CMP   u,t,3
        BZ    u,6F
        CMP   u,t,4
        BZ    u,6F
        ADD   p,p,1
        CMP   t,p,:NProc
        BN    t,5B
        JMP   Stop
6H      PUSHJ res,:Next
        GETA  t,:ExitNext
        STO   res,t,0
        PUSHJ res,:FreeSpace    이 프로세스의 프레임을 돌려준다
        GETA  t,:ExitNext       레지스터는 이제 믿지 않는다
        LDO   $0,t,0
        JMP   :Resume
Stop    PUSHJ res,:SyncFS       디스크를 맞춘다(디스크가 없으면 할 일이 없다)
        GET   $255,:rBB
        JMP   :Halt5
        PREFIX :

% Store(ctx): 지금 프로세스의 항목에 문맥의 주소와 rBB, rWW..rZZ를 적는다.
Store   GETA  $1,Cur
        LDO   $1,$1,0
        SLU   $1,$1,PShift
        GETA  $2,Procs
        ADDU  $1,$1,$2
        STO   $0,$1,CTX
        GET   $2,rBB
        STO   $2,$1,BBO
        GET   $2,rWW
        STO   $2,$1,WWO
        GET   $2,rXX
        STO   $2,$1,XXO
        GET   $2,rYY
        STO   $2,$1,YYO
        GET   $2,rZZ
        STO   $2,$1,ZZO
        POP   0,0

% Next(): 지금 프로세스 다음부터 돌아가며 찾은, 돌 수 있는(상태가 1인) 프로세스의 pid.
% 하나도 없으면 모두 디스크를 기다리며 잠든 것이므로, 커널은 놀면서 rQ의 디스크 비트를
% 직접 지켜보다가 그 프로세스들을 깨운다(커널은 인터럽트를 끈 채로 돌지만 rQ는 켜진다).
Next    GETA  $1,Cur
        LDO   $0,$1,0
        GETA  $2,Procs
        SET   $3,NProc
1H      ADD   $0,$0,1
        AND   $0,$0,NProc-1
        SLU   $1,$0,PShift
        LDO   $1,$2,$1
        CMP   $1,$1,1
        BZ    $1,9F
        SUB   $3,$3,1
        BP    $3,1B
        GET   $4,rJ             돌 수 있는 프로세스가 없다
2H      GET   $1,rQ
        SRU   $1,$1,8
        AND   $1,$1,1
        BZ    $1,2B             디스크의 인터럽트를 rQ에서 직접 기다린다
        GET   $1,rQ
        ANDNL $1,DiskBit
        PUT   rQ,$1
        SETL  $6,1
        PUSHJ $5,Wakeup
        PUT   rJ,$4
        SET   $3,NProc
        JMP   1B
9H      POP   1,0

% CopySpace(prv,crv): rV가 prv인 주소 공간에 들어 있는 페이지를 rV가 crv인 주소 공간의
% 같은 자리에 넣는다. Walk가 부모의 PTE마다 CopyCb를 부른다. 자식의 PTE 자리는 PteSlot이
% 찾고, 모자라는 중간 테이블은 그때 만든다. 스택 세그먼트의 페이지는 새 프레임에 복사한다.
% 커널이 인터럽트를 끈 채 SAVE로 거기에 쓰므로 쓰기 허가를 끌 수 없기 때문이다. 나머지는 프레임을
% 함께 쓰고, 쓸 수 있던 페이지는 부모와 자식 모두에서 쓰기 허가를 끄고 COW 표시를 한다.
% 자식의 테이블은 비어 있다(앞서 같은 pid를 쓴 프로세스는 Exit에서 테이블을 비웠다).
CopySpace GET $2,rJ
        SET   $4,$0
        GETA  $5,CopyCb
        SET   $6,$1
        SETL  $7,4
        SET   $8,0
        PUSHJ $3,Walk
        PUT   rJ,$2
        POP   0,0

        PREFIX Copy:
sl      IS    $0                부모의 PTE 자리
va      IS    $1
crv     IS    $2
cs      IS    $3                자식의 PTE 자리
pte     IS    $4
t       IS    $5
cn      IS    $6
fr      IS    $7
rj      IS    $8
res     IS    $9
:CopyCb GET   rj,:rJ
        SET   res+1,crv
        SET   res+2,va
        SETL  res+3,1
        PUSHJ res,:PteSlot
        SET   cs,res
        SETL  t,#1ff8
        AND   cn,crv,t          자식의 주소 공간 번호(n<<3)
        LDO   pte,sl,0
        SRU   t,va,61
        CMP   t,t,3
        BZ    t,Copy            스택 세그먼트는 바로 복사한다
        AND   t,pte,2
        BZ    t,Share
        ANDN  pte,pte,2         쓰기 허가를 끄고
        ORH   pte,:COW          쓸 때 복사한다고 적는다
        STO   pte,sl,0          부모도 그렇다
Share   SETL  t,#1fff
        ANDN  res+1,pte,t
        ANDNH res+1,#ffff
        ORH   res+1,#8000
        PUSHJ res,:IncRef       프레임을 함께 쓴다
        SETL  t,#1ff8
        ANDN  fr,pte,t
        OR    fr,fr,cn          주소 공간 번호만 자식의 것으로
        STO   fr,cs,0
        PUT   :rJ,rj
        POP   0,0
Copy    PUSHJ res,:AllocFrame
        SET   fr,res
        SETL  t,#1fff
        ANDN  res+1,pte,t
        ANDNH res+1,#ffff
        ORH   res+1,#8000       부모의 프레임
        SET   res+2,fr
        SET   res+3,0
        PUSHJ res,:CopyPage
        ANDNH fr,#8000
        OR    fr,fr,cn
        AND   t,pte,7
        OR    fr,fr,t
        STO   fr,cs,0
        PUT   :rJ,rj
        POP   0,0
        PREFIX :

% ---- 파일 시스템 ----
% 디스크가 붙어 있으면(Mounted) 커널은 파일을 직접 다룬다. 핸들 표의 항목마다
% 종류(0: 닫힘, 1: 콘솔, 2: 파일), mmixio와 같은 방식 코드(1: 읽기, 2: 쓰기,
% 4: 찾기, 8: 읽고 쓰기), 디렉터리 항목 번호, 위치, 그리고 위치가 든 블록과
% 그 블록의 파일 안 번호를 둔다. 콘솔 핸들은 HIO로 보내고, 파일은 FsOp가 다룬다.
% 반환값과 오류는 mmixio(mmixio.w)와 똑같이 맞춘다.
%
% FsOp(H,op,a0,a1): 핸들 항목 H에 연산 op를 한다. 인자는 Syscall이 가져온 그대로다.
        PREFIX Fs:
H       IS    $0
op      IS    $1
a0      IS    $2
a1      IS    $3
rj      IS    $4
mode    IS    $5
n       IS    $6
k       IS    $7
c       IS    $8
t       IS    $9
o       IS    $10
s       IS    $11
eof     IS    $12
ln      IS    $13               줄 버퍼의 커널 주소
res     IS    $14
:FsOp   GET   rj,:rJ
        PUSHJ res,:FsLock
        NEG   t,0,1
        GETA  res,:URTag        사용자 페이지의 캐시를 비운다
        STO   t,res,0
        GETA  res,:UWTag
        STO   t,res,0
        SETH  ln,#8000
        ORMH  ln,#0006
        SETL  t,:LineOff
        ADDU  ln,ln,t
        LDO   mode,H,:HMODE
        CMP   t,op,:Fopen
        BZ    t,Open
        CMP   t,op,:Fclose
        BZ    t,Close
        CMP   t,op,:Fread
        BZ    t,Read
        CMP   t,op,:Fgets
        BZ    t,Gets
        CMP   t,op,:Fgetws
        BZ    t,Getws
        CMP   t,op,:Fwrite
        BZ    t,Write
        CMP   t,op,:Fputs
        BZ    t,Puts
        CMP   t,op,:Fputws
        BZ    t,Putws
        CMP   t,op,:Fseek
        BZ    t,Seek
        JMP   Tell
Neg1    NEG   o,0,1
Ret     PUSHJ res,:FsUnlock
        SET   $0,o
        PUT   :rJ,rj
        POP   1,0

% Fopen(name=a0, mode=a1). 이름을 줄 버퍼로 가져와 디렉터리에서 찾는다. 읽기
% 방식(0, 2)이면 있어야 하고, 쓰기 방식이면 있으면 비우고 없으면 만든다.
% 실패하면 mmixio처럼 핸들을 닫는다.
Open    CMPU  t,a1,4
        BP    t,Abort
        SET   k,0
1H      ADDU  res+1,a0,k
        PUSHJ res,:UGet
        BN    res,Abort
        STB   res,ln,k
        BZ    res,2F
        ADD   k,k,1
        SETL  t,1024
        CMP   t,k,t
        BN    t,1B
        JMP   Abort             이름이 1024바이트 안에서 끝나지 않는다
2H      BZ    k,Abort
        CMP   t,k,:NameMax
        BP    t,Abort
        SETH  s,#8000
        ORMH  s,#0006
        SETL  t,:DirOff
        ADDU  s,s,t             s=디렉터리
        SET   res+1,ln
        PUSHJ res,:Lookup
        SET   n,res
        BN    n,5F
        SLU   t,n,6
        ADDU  c,s,t             c=항목 n
        JMP   Found
5H      CMP   t,a1,0            없다
        BZ    t,Abort
        CMP   t,a1,2
        BZ    t,Abort
        SET   n,0
6H      SLU   t,n,6
        ADDU  c,s,t
        LDBU  t,c,0
        BZ    t,7F
        ADD   n,n,1
        CMP   t,n,:NEnt
        BN    t,6B
        JMP   Abort             디렉터리가 가득 찼다
7H      SET   o,0
8H      LDBU  t,ln,o
        STB   t,c,o
        ADD   o,o,1
        CMP   t,o,k
        BNP   t,8B
        STCO  0,c,48
        STCO  0,c,56
        JMP   Mark
Found   CMP   t,a1,0
        BZ    t,Set
        CMP   t,a1,2
        BZ    t,Set
        LDTU  res+1,c,48        쓰기 방식이면 비운다
        PUSHJ res,:FreeChain
        STCO  0,c,48
        STCO  0,c,56
Mark    GETA  t,:MetaDirty
        SETL  res,1
        STO   res,t,0
Set     SETL  t,2
        STO   t,H,:HKIND
        GETA  t,:ModeCode
        LDBU  t,t,a1
        STO   t,H,:HMODE
        STO   n,H,:HENT
        STCO  0,H,:HPOS
        STCO  0,H,:HCBLK
        STCO  0,H,:HCIDX
        SET   o,0
        JMP   Ret
Abort   STCO  0,H,:HKIND
        STCO  0,H,:HMODE
        JMP   Neg1

% Fclose. 파일이면 디스크를 맞춘다.
Close   BZ    mode,Neg1
        LDO   t,H,:HKIND
        CMP   t,t,2
        BNZ   t,1F
        PUSHJ res,:SyncFS
1H      STCO  0,H,:HKIND
        STCO  0,H,:HMODE
        SET   o,0
        JMP   Ret

% Fread(buffer=a0, size=a1): 읽은 바이트 수에서 size를 뺀 값을 돌려준다.
Read    AND   t,mode,1
        BZ    t,8F
        AND   t,mode,8
        BZ    t,1F
        ANDN  mode,mode,2
        STO   mode,H,:HMODE
1H      SRU   t,a1,32
        BNZ   t,8F
        SET   n,0
2H      CMPU  t,n,a1
        BNN   t,3F
        SET   res+1,H
        PUSHJ res,:Getc
        BN    res,3F
        SET   res+2,res
        ADDU  res+1,a0,n
        PUSHJ res,:UPut
        BN    res,8F
        ADD   n,n,1
        JMP   2B
3H      SUBU  o,n,a1
        JMP   Ret
8H      NEG   o,0,1
        SUBU  o,o,a1            -1-size
        JMP   Ret

% Fgets(buffer=a0, size=a1). mmixio처럼 255바이트씩 줄 버퍼에 모아 옮긴다.
% 한 덩이를 읽기 시작할 때 이미 파일 끝이면 -1이다.
Gets    AND   t,mode,1
        BZ    t,Neg1
        BZ    a1,Neg1
        AND   t,mode,8
        BZ    t,1F
        ANDN  mode,mode,2
        STO   mode,H,:HMODE
1H      SUB   a1,a1,1
        SET   o,0
2H      SETL  s,255
        CMPU  t,a1,s
        BNN   t,3F
        SET   s,a1
3H      BZ    s,4F
        SET   res+1,H
        PUSHJ res,:AtEnd
        BNZ   res,Neg1
4H      SET   n,0
        SET   eof,0
5H      CMP   t,n,s
        BNN   t,7F
        SET   res+1,H
        PUSHJ res,:Getc
        BN    res,6F
        STB   res,ln,n
        ADD   n,n,1
        CMP   t,res,#a
        BZ    t,7F
        JMP   5B
6H      SET   eof,1
7H      SET   t,0
        STB   t,ln,n
        SET   k,0
8H      LDBU  res+2,ln,k
        ADDU  res+1,a0,k
        PUSHJ res,:UPut
        BN    res,Neg1
        ADD   k,k,1
        CMP   t,k,n
        BNP   t,8B
        ADDU  o,o,n
        SUBU  a1,a1,n
        BNZ   eof,Ret
        BZ    a1,Ret
        BZ    n,9F
        SUB   t,n,1
        LDBU  t,ln,t
        CMP   t,t,#a
        BZ    t,Ret
9H      ADDU  a0,a0,n
        JMP   2B

% Fgetws(buffer=a0, size=a1). 와이드 문자 127개씩. 파일 끝에서는 0을 돌려준다.
Getws   AND   t,mode,1
        BZ    t,Neg1
        BZ    a1,Neg1
        AND   t,mode,8
        BZ    t,1F
        ANDN  mode,mode,2
        STO   mode,H,:HMODE
1H      ANDN  a0,a0,1
        SUB   a1,a1,1
        SET   o,0
2H      SETL  s,127
        CMPU  t,a1,s
        BNN   t,3F
        SET   s,a1
3H      SET   n,0
        SET   k,0
        SET   eof,0
4H      CMP   t,n,s
        BNN   t,6F
        SET   res+1,H
        PUSHJ res,:Getc
        BN    res,5F
        SET   c,res
        SET   res+1,H
        PUSHJ res,:Getc
        BN    res,5F
        STB   c,ln,k
        ADD   k,k,1
        STB   res,ln,k
        ADD   k,k,1
        ADD   n,n,1
        BNZ   c,4B
        CMP   t,res,#a
        BNZ   t,4B
        JMP   6F
5H      SET   eof,1
6H      SET   t,0
        STB   t,ln,k
        ADD   c,k,1
        STB   t,ln,c
        SET   c,0
7H      LDBU  res+2,ln,c
        ADDU  res+1,a0,c
        PUSHJ res,:UPut
        BN    res,Neg1
        ADD   c,c,1
        ADD   t,k,1
        CMP   t,c,t
        BNP   t,7B
        ADDU  o,o,n
        SUBU  a1,a1,n
        BNZ   eof,Ret
        BZ    a1,Ret
        BZ    n,8F
        SUB   t,k,2
        LDBU  t,ln,t
        BNZ   t,8F
        SUB   t,k,1
        LDBU  t,ln,t
        CMP   t,t,#a
        BZ    t,Ret
8H      ADDU  a0,a0,k
        JMP   2B

% Fwrite(buffer=a0, size=a1): 다 쓰면 0, 아니면 못 쓴 바이트 수의 음수.
Write   AND   t,mode,2
        BNZ   t,1F
        NEG   o,0,a1
        JMP   Ret
1H      AND   t,mode,8
        BZ    t,2F
        ANDN  mode,mode,1
        STO   mode,H,:HMODE
2H      SET   n,0
3H      CMPU  t,n,a1
        BNN   t,4F
        ADDU  res+1,a0,n
        PUSHJ res,:UGet
        BN    res,5F
        SET   res+2,res
        SET   res+1,H
        PUSHJ res,:Putc
        BN    res,5F
        ADD   n,n,1
        JMP   3B
4H      SET   o,0
        JMP   Ret
5H      SUBU  o,n,a1
        JMP   Ret

% Fputs(string=a0): 쓴 바이트 수.
Puts    AND   t,mode,2
        BZ    t,Neg1
        AND   t,mode,8
        BZ    t,1F
        ANDN  mode,mode,1
        STO   mode,H,:HMODE
1H      SET   o,0
2H      ADDU  res+1,a0,o
        PUSHJ res,:UGet
        BN    res,Neg1
        BZ    res,Ret
        SET   res+2,res
        SET   res+1,H
        PUSHJ res,:Putc
        BN    res,Neg1
        ADD   o,o,1
        JMP   2B

% Fputws(string=a0): 쓴 와이드 문자의 수.
Putws   AND   t,mode,2
        BZ    t,Neg1
        AND   t,mode,8
        BZ    t,1F
        ANDN  mode,mode,1
        STO   mode,H,:HMODE
1H      SET   n,0
2H      ADDU  res+1,a0,n
        PUSHJ res,:UGet
        BN    res,Neg1
        SET   c,res
        ADDU  res+1,a0,n
        ADD   res+1,res+1,1
        PUSHJ res,:UGet
        BN    res,Neg1
        SET   k,res
        OR    t,c,k
        BZ    t,3F
        SET   res+1,H
        SET   res+2,c
        PUSHJ res,:Putc
        BN    res,Neg1
        SET   res+1,H
        SET   res+2,k
        PUSHJ res,:Putc
        BN    res,Neg1
        ADD   n,n,2
        JMP   2B
3H      SRU   o,n,1
        JMP   Ret

% Fseek(offset=a0). 음수면 끝에서부터 센다(-1이 끝). 텍스트 방식이면 -1.
Seek    AND   t,mode,4
        BZ    t,Neg1
        AND   t,mode,8
        BZ    t,1F
        SETL  mode,#f
        STO   mode,H,:HMODE
1H      SRU   t,a0,31
        BN    a0,2F
        BNZ   t,Neg1
        SET   c,a0
        JMP   3F
2H      SETL  s,1
        SLU   s,s,33
        SUBU  s,s,1
        CMPU  t,t,s
        BNZ   t,Neg1
        SET   res+1,H
        PUSHJ res,:EntAddr
        LDO   c,res,56
        ADD   c,c,a0
        ADD   c,c,1
        BN    c,Neg1
3H      STO   c,H,:HPOS
        STCO  0,H,:HCBLK
        SET   o,0
        JMP   Ret

% Ftell: 위치. 텍스트 방식이면 -1.
Tell    AND   t,mode,4
        BZ    t,Neg1
        LDO   o,H,:HPOS
        SLU   o,o,32
        SRU   o,o,32
        JMP   Ret
        PREFIX :

% EntAddr(H): 핸들 항목 H가 가리키는 디렉터리 항목의 커널 주소.
EntAddr LDO   $1,$0,HENT
        SLU   $1,$1,6
        SETH  $0,#8000
        ORMH  $0,#0006
        SETL  $2,DirOff
        ADDU  $0,$0,$2
        ADDU  $0,$0,$1
        POP   1,0

% AtEnd(H): 위치가 파일 끝이거나 그 너머이면 1, 아니면 0.
AtEnd   GET   $3,rJ
        SET   $5,$0
        PUSHJ $4,EntAddr
        PUT   rJ,$3
        LDO   $1,$4,56
        LDO   $2,$0,HPOS
        CMPU  $1,$2,$1
        ZSNN  $0,$1,1
        POP   1,0

% Getc(H): 핸들 H의 위치에서 바이트 하나를 읽고 위치를 하나 늘린다. 파일 끝이면 -1.
        PREFIX Getc:
pos     IS    $1
t       IS    $2
rj      IS    $3
res     IS    $4
:Getc   GET   rj,:rJ
        SET   res+1,$0
        PUSHJ res,:AtEnd
        BNZ   res,9F
        SET   res+1,$0
        SET   res+2,0
        PUSHJ res,:BlockFor
        BZ    res,9F
        SET   res+1,res
        PUSHJ res,:GetBlk
        LDO   pos,$0,:HPOS
        SETL  t,#3ff
        AND   t,pos,t
        SETH  res,#8000
        ORMH  res,#0006
        INCL  res,:BufOff
        LDBU  t,res,t
        ADD   pos,pos,1
        STO   pos,$0,:HPOS
        SET   $0,t
        PUT   :rJ,rj
        POP   1,0
9H      NEG   $0,0,1
        PUT   :rJ,rj
        POP   1,0
        PREFIX :

% Putc(H,c): 핸들 H의 위치에 바이트 c를 쓰고 위치를 하나 늘린다. 블록이 모자라면
% 할당한다. 파일이 길어지면 디렉터리 항목의 크기를 고친다. 디스크가 가득 차면 -1.
        PREFIX Putc:
pos     IS    $2
t       IS    $3
rj      IS    $4
res     IS    $5
:Putc   GET   rj,:rJ
        SET   res+1,$0
        SETL  res+2,1
        PUSHJ res,:BlockFor
        BZ    res,9F
        SET   res+1,res
        PUSHJ res,:GetBlk
        LDO   pos,$0,:HPOS
        SETL  t,#3ff
        AND   t,pos,t
        SETH  res,#8000
        ORMH  res,#0006
        INCL  res,:BufOff
        STB   $1,res,t
        GETA  t,:CacheDirty
        SETL  res,1
        STO   res,t,0
        ADD   pos,pos,1
        STO   pos,$0,:HPOS
        SET   res+1,$0
        PUSHJ res,:EntAddr
        LDO   t,res,56
        CMPU  t,pos,t
        BNP   t,1F
        STO   pos,res,56        파일이 길어졌다
        GETA  t,:MetaDirty
        SETL  res,1
        STO   res,t,0
1H      SET   $0,0
        PUT   :rJ,rj
        POP   1,0
9H      NEG   $0,0,1
        PUT   :rJ,rj
        POP   1,0
        PREFIX :

% BlockFor(H,alloc): 핸들 H의 위치가 든 디스크 블록. 위치의 블록 번호가 항목에
% 기억한 것과 같으면 그대로 쓰고, 바로 다음이면 FAT를 한 칸만 따라가고, 아니면
% 첫 블록부터 걷는다. 사슬이 모자라면 alloc이 0이 아닐 때만 블록을 할당해 잇고,
% 아니면 0이다.
        PREFIX BlockFor:
H       IS    $0
alloc   IS    $1
idx     IS    $2
b       IS    $3
t       IS    $4
k       IS    $5
rj      IS    $6
res     IS    $7
:BlockFor GET rj,:rJ
        LDO   idx,H,:HPOS
        SRU   idx,idx,10
        LDO   b,H,:HCBLK
        BZ    b,Walk
        LDO   t,H,:HCIDX
        CMP   k,t,idx
        BZ    k,Done
        ADD   t,t,1
        CMP   k,t,idx
        BNZ   k,Walk
        SET   res+1,b
        SET   res+2,alloc
        PUSHJ res,:FatNext
        BZ    res,Fail
        SET   b,res
        JMP   Done
Walk    SET   res+1,H
        PUSHJ res,:EntAddr
        SET   k,res
        LDTU  b,k,48
        BNZ   b,1F
        BZ    alloc,Fail
        PUSHJ res,:AllocBlk
        BZ    res,Fail
        SET   b,res
        STT   b,k,48            첫 블록
        GETA  t,:MetaDirty
        SETL  res,1
        STO   res,t,0
1H      SET   k,0
2H      CMP   t,k,idx
        BNN   t,Done
        SET   res+1,b
        SET   res+2,alloc
        PUSHJ res,:FatNext
        BZ    res,Fail
        SET   b,res
        ADD   k,k,1
        JMP   2B
Done    STO   b,H,:HCBLK
        STO   idx,H,:HCIDX
        SET   $0,b
        PUT   :rJ,rj
        POP   1,0
Fail    SET   $0,0
        PUT   :rJ,rj
        POP   1,0
        PREFIX :

% FatNext(b,alloc): FAT에서 블록 b의 다음 블록. 사슬의 끝이면 alloc이 0이 아닐
% 때만 새 블록을 할당해 잇고, 아니면 0이다. 사슬이 망가져 빈 블록을 가리켜도 0이다.
        PREFIX FatNext:
b       IS    $0
alloc   IS    $1
a       IS    $2
nb      IS    $3
t       IS    $4
rj      IS    $5
res     IS    $6
:FatNext SETH a,#8000
        ORMH  a,#0006
        4ADDU a,b,a             a=FAT[b]의 주소
        LDTU  nb,a,0
        SETML t,#ffff
        ORL   t,#ffff
        CMP   t,nb,t
        BZ    t,1F
        SET   $0,nb             0이면 망가진 사슬이다
        POP   1,0
1H      SET   $0,0
        BZ    alloc,9F
        GET   rj,:rJ
        PUSHJ res,:AllocBlk
        PUT   :rJ,rj
        BZ    res,9F
        STT   res,a,0
        GETA  t,:MetaDirty
        SETL  nb,1
        STO   nb,t,0
        SET   $0,res
9H      POP   1,0
        PREFIX :

% AllocBlk(): 데이터 영역의 앞에서부터 빈 블록을 찾아 사슬의 끝으로 표시하고, 0으로
% 채운 채 블록 캐시에 올린다(나중에 디스크에 쓰인다). 가득 찼으면 0이다.
        PREFIX AllocBlk:
b       IS    $0
n       IS    $1
a       IS    $2
t       IS    $3
rj      IS    $4
res     IS    $5
:AllocBlk GETA t,:DataStart
        LDO   b,t,0
        GETA  t,:NBlocks
        LDO   n,t,0
1H      CMP   t,b,n
        BNN   t,8F
        SETH  a,#8000
        ORMH  a,#0006
        4ADDU a,b,a
        LDTU  t,a,0
        BZ    t,2F
        ADD   b,b,1
        JMP   1B
2H      SETML t,#ffff
        ORL   t,#ffff
        STT   t,a,0
        GETA  t,:MetaDirty
        SETL  n,1
        STO   n,t,0
        GET   rj,:rJ
        SET   res+1,b
        PUSHJ res,:ZeroBlk
        PUT   :rJ,rj
        POP   1,0
8H      SET   $0,0
        POP   1,0
        PREFIX :

% FreeChain(b): 블록 b에서 시작하는 사슬을 FAT에서 풀어 준다. 풀린 블록이 캐시에
% 남아 나중에 디스크에 쓰이지 않도록 캐시를 먼저 비우고 잊는다.
        PREFIX FreeChain:
b       IS    $0
a       IS    $1
nb      IS    $2
end     IS    $3
zero    IS    $4
rj      IS    $5
res     IS    $6
:FreeChain GET rj,:rJ
        PUSHJ res,:FlushBuf
        PUT   :rJ,rj
        NEG   end,0,1
        GETA  a,:CacheBlk
        STO   end,a,0
        SETML end,#ffff
        ORL   end,#ffff
        SET   zero,0
1H      BZ    b,9F
        CMP   nb,b,end
        BZ    nb,9F
        SETH  a,#8000
        ORMH  a,#0006
        4ADDU a,b,a
        LDTU  b,a,0
        STTU  zero,a,0
        JMP   1B
9H      GETA  a,:MetaDirty
        SETL  nb,1
        STO   nb,a,0
        POP   0,0
        PREFIX :

% 블록 캐시. 디스크 블록 하나(CacheBlk, 없으면 -1)를 커널 메모리 BufOff에 둔다.
% CacheDirty가 0이 아니면 아직 디스크에 쓰지 않은 것이다.
% GetBlk(b): 블록 b를 캐시에 올린다.
GetBlk  GETA  $1,CacheBlk
        LDO   $2,$1,0
        CMP   $2,$2,$0
        BZ    $2,9F
        GET   $3,rJ
        PUSHJ $4,FlushBuf
        SET   $5,$0
        SETH  $6,#8000
        ORMH  $6,#0006
        INCL  $6,BufOff
        SETL  $7,1              읽기
        PUSHJ $4,BlkIO
        PUT   rJ,$3
        GETA  $1,CacheBlk
        STO   $0,$1,0
        GETA  $1,CacheDirty
        STCO  0,$1,0
9H      POP   0,0

% FlushBuf(): 캐시가 더러우면 디스크에 쓴다.
FlushBuf GETA $0,CacheDirty
        LDO   $1,$0,0
        BZ    $1,9F
        STCO  0,$0,0
        GET   $2,rJ
        GETA  $0,CacheBlk
        LDO   $4,$0,0
        SETH  $5,#8000
        ORMH  $5,#0006
        INCL  $5,BufOff
        SETL  $6,2              쓰기
        PUSHJ $3,BlkIO
        PUT   rJ,$2
9H      POP   0,0

% ZeroBlk(b): 새로 할당한 블록 b를 0으로 채운 채 캐시에 올린다. 읽을 필요가 없다.
ZeroBlk GET   $1,rJ
        PUSHJ $2,FlushBuf
        PUT   rJ,$1
        SETH  $1,#8000
        ORMH  $1,#0006
        INCL  $1,BufOff
        SET   $2,0
        SETL  $3,BSize
1H      STCO  0,$1,$2
        ADDU  $2,$2,8
        CMP   $4,$2,$3
        BN    $4,1B
        GETA  $1,CacheBlk
        STO   $0,$1,0
        GETA  $1,CacheDirty
        SETL  $2,1
        STO   $2,$1,0
        POP   0,0

% WriteBlocks(blk,addr,n): 커널 메모리 addr부터 n블록을 디스크의 블록 blk부터 쓴다.
% ReadBlocks(blk,addr,n)는 거꾸로 읽는다. 둘 다 BlkIO의 명령 하나만 다르다.
WriteBlocks SETL $3,2
        JMP   1F
ReadBlocks SETL $3,1
1H      GET   $4,rJ
2H      BZ    $2,9F
        SET   $6,$0
        SET   $7,$1
        SET   $8,$3
        PUSHJ $5,BlkIO
        ADD   $0,$0,1
        INCL  $1,BSize
        SUB   $2,$2,1
        JMP   2B
9H      PUT   rJ,$4
        POP   0,0

% SyncFS(): 캐시와, 바뀌었으면 FAT와 디렉터리를 디스크에 쓴다. 파일을 닫을 때와
% 기계를 멈추기 전에 부른다.
        PREFIX Sync:
t       IS    $0
rj      IS    $1
res     IS    $2
:SyncFS GET   rj,:rJ
        PUSHJ res,:FlushBuf
        GETA  t,:MetaDirty
        LDO   res,t,0
        BZ    res,9F
        STCO  0,t,0
        GETA  t,:FatStart
        LDO   res+1,t,0
        SETH  res+2,#8000
        ORMH  res+2,#0006       FAT
        GETA  t,:FatBlocks
        LDO   res+3,t,0
        PUSHJ res,:WriteBlocks
        GETA  t,:DirStart
        LDO   res+1,t,0
        SETH  res+2,#8000
        ORMH  res+2,#0006
        SETL  t,:DirOff
        ADDU  res+2,res+2,t     디렉터리
        SETL  res+3,:NDirBlk
        PUSHJ res,:WriteBlocks
9H      PUT   :rJ,rj
        POP   0,0
        PREFIX :

% BlkIO(blk,addr,cmd): 블록 장치에 명령 하나(1: 읽기, 2: 쓰기)를 시키고 결과(0이나
% -1)를 돌려준다. 규약은 Device와 같다. 장치는 음수 주소를 물리 주소로 본다. 명령에는
% 시간이 걸리므로, 돌 수 있는 다른 프로세스가 있으면 끝날 때까지 잠든다.
BlkIO   SETH  $3,BLK
        ORML  $3,BLKLO
        LDO   $4,$3,DONE
        STO   $0,$3,BBLOCK
        STO   $1,$3,BADDR
        STO   $2,$3,CMD
1H      LDO   $5,$3,DONE
        CMPU  $5,$5,$4
        BNZ   $5,2F
        GETA  $5,NReady
        LDO   $5,$5,0
        CMP   $5,$5,1
        BNP   $5,1B             혼자면 바쁘게 기다린다
        GET   $6,rJ
        SETL  $8,1
        PUSHJ $7,Sleep          디스크를 기다리며 잠든다
        PUT   rJ,$6
        JMP   1B
2H      SYNC  2
        LDO   $0,$3,RESULT
        POP   1,0

% UGet(va): 사용자 주소 va의 바이트. UPut(va,c): 거기에 바이트 c를 쓴다. 실패하면
% -1이다. 바이트마다 UserPA를 부르지 않도록 읽기와 쓰기에 페이지 하나씩을 기억한다.
% FsOp가 시작할 때 이 기억을 지운다(페이지 테이블은 시스템 호출 사이에 바뀔 수 있다).
        PREFIX UGet:
va      IS    $0
pg      IS    $1
t       IS    $2
m       IS    $3
rj      IS    $4
res     IS    $5
:UGet   SETL  m,#1fff
        ANDN  pg,va,m
        GETA  t,:URTag
        LDO   t,t,0
        CMP   t,t,pg
        BZ    t,1F
        GET   rj,:rJ
        SET   res+1,pg
        SETL  res+2,4           p_r
        PUSHJ res,:UserPA
        PUT   :rJ,rj
        BN    res,9F
        ORH   res,#8000
        GETA  t,:URPA
        STO   res,t,0
        GETA  t,:URTag
        STO   pg,t,0
1H      GETA  t,:URPA
        LDO   t,t,0
        AND   va,va,m
        LDBU  $0,t,va
        POP   1,0
9H      NEG   $0,0,1
        POP   1,0
        PREFIX :

        PREFIX UPut:
va      IS    $0
c       IS    $1
pg      IS    $2
t       IS    $3
m       IS    $4
rj      IS    $5
res     IS    $6
:UPut   SETL  m,#1fff
        ANDN  pg,va,m
        GETA  t,:UWTag
        LDO   t,t,0
        CMP   t,t,pg
        BZ    t,1F
        GET   rj,:rJ
        SET   res+1,pg
        SETL  res+2,2           p_w
        PUSHJ res,:UserPA
        PUT   :rJ,rj
        BN    res,9F
        ORH   res,#8000
        GETA  t,:UWPA
        STO   res,t,0
        GETA  t,:UWTag
        STO   pg,t,0
1H      GETA  t,:UWPA
        LDO   t,t,0
        AND   va,va,m
        STB   c,t,va
        SET   $0,0
        POP   1,0
9H      NEG   $0,0,1
        POP   1,0
        PREFIX :

% Mount(): 블록 장치가 있고 그 디스크가 NNIXFS이면 FAT와 디렉터리를 커널 메모리에
% 올리고 Mounted를 1로 한다. 핸들 0, 1, 2는 콘솔로(방식은 mmixio와 같이 1, 2, 2) 둔다.
        PREFIX Mount:
t       IS    $0
u       IS    $1
d       IS    $2
rj      IS    $3
res     IS    $4
:Mount  GET   rj,:rJ
        SETH  d,:BLK
        ORML  d,:BLKLO
        LDO   t,d,:ID
        SETH  u,#4e4e           "NNIX-BLK"
        ORMH  u,#4958
        ORML  u,#2d42
        ORL   u,#4c4b
        CMP   t,t,u
        BNZ   t,9F              블록 장치가 없다
        SET   res+1,0
        SETH  res+2,#8000
        ORMH  res+2,#0006
        INCL  res+2,:BufOff
        SET   res+3,1
        PUSHJ res,:ReadBlocks   슈퍼블록
        SETH  d,#8000
        ORMH  d,#0006
        INCL  d,:BufOff
        LDO   t,d,0
        SETH  u,#4e4e           "NNIXFS01"
        ORMH  u,#4958
        ORML  u,#4653
        ORL   u,#3031
        CMP   t,t,u
        BNZ   t,9F
        LDO   t,d,40
        CMP   t,t,:NDirBlk
        BNZ   t,9F              디렉터리는 네 블록이어야 한다
        LDO   t,d,24
        CMP   t,t,:MaxFatBlk
        BP    t,9F              FAT는 16블록까지
        LDO   t,d,8
        GETA  u,:NBlocks
        STO   t,u,0
        LDO   t,d,16
        GETA  u,:FatStart
        STO   t,u,0
        LDO   t,d,24
        GETA  u,:FatBlocks
        STO   t,u,0
        LDO   t,d,32
        GETA  u,:DirStart
        STO   t,u,0
        LDO   t,d,48
        GETA  u,:DataStart
        STO   t,u,0
        GETA  t,:FatStart
        LDO   res+1,t,0
        SETH  res+2,#8000
        ORMH  res+2,#0006
        GETA  t,:FatBlocks
        LDO   res+3,t,0
        PUSHJ res,:ReadBlocks   FAT
        GETA  t,:DirStart
        LDO   res+1,t,0
        SETH  res+2,#8000
        ORMH  res+2,#0006
        SETL  t,:DirOff
        ADDU  res+2,res+2,t
        SETL  res+3,:NDirBlk
        PUSHJ res,:ReadBlocks   디렉터리
        SETH  d,#8000
        ORMH  d,#0006
        SETL  t,:HOff
        ADDU  d,d,t             핸들 표
        SETL  t,1
        STO   t,d,:HKIND
        STO   t,d,:HMODE
        STO   t,d,64+:HKIND
        STO   t,d,128+:HKIND
        SETL  t,2
        STO   t,d,64+:HMODE
        STO   t,d,128+:HMODE
        GETA  t,:Mounted
        SETL  u,1
        STO   u,t,0
9H      PUT   :rJ,rj
        POP   0,0
        PREFIX :

% ---- Exec ----
% DoExec(argv): 디스크의 목적 파일 argv[0](없으면 argv[0].mmo)을 지금 프로세스의 새
% 주소 공간에 싣고 실행한다. 실행 환경은 MMIX-SIM이 차리는 것(mmixsim.w의 "목적 파일
% 싣기" 장)과 똑같다. 풀 세그먼트의 맨 앞 옥타바이트에는 비어 있는 첫 자리가, 그 뒤에는
% argv[k]의 포인터들이 오고, 문자열은 옥타바이트 단위로 맞춰 그 뒤에 둔다. 스택
% 세그먼트의 맨 앞에는 UNSAVE할 문맥을 쌓는다: $0=argc, $1=Pool_Segment+8, rL=2,
% 목적 파일의 후기가 주는 전역 레지스터 $G..$255, 0인 특수 레지스터 열둘, 그리고
% rG와 rA. 시작 주소는 후기의 $255(곧 Main)이고, #F0에 무언가 있으면 #F0이다.
% 그다음 프로세스 표의 문맥 주소를 그 UNSAVE 프레임으로 정하고 Resume으로 넘어간다.
%
% 인자를 옮기고 파일과 서문을 확인하기까지 실패하면 -1을 돌려준다. 그 뒤로는 옛 주소
% 공간을 버렸으므로, 목적 파일이 망가졌으면 알리고 이 프로세스를 -1로 끝낸다.
        PREFIX Exec:
argv    IS    $0
argc    IS    $1
eb      IS    $2                인자 버퍼의 커널 주소
n       IS    $3
p       IS    $4
c       IS    $5
t       IS    $6
ih      IS    $7                목적 파일을 읽는 커널 핸들
loc     IS    $8                싣는 위치
tet     IS    $9
g       IS    $10               후기의 G
k       IS    $11
ent     IS    $12               이 프로세스의 항목
main    IS    $13
rj      IS    $14
res     IS    $15
:DoExec GET   rj,:rJ
        GETA  t,:Mounted
        LDO   t,t,0
        BZ    t,Fail0           디스크가 없으면 실행할 파일도 없다
        PUSHJ res,:FsLock
        NEG   t,0,1
        GETA  c,:URTag
        STO   t,c,0
        SETH  eb,#8000
        ORMH  eb,#0006
        SETL  t,:EBufOff
        ADDU  eb,eb,t
% 인자 문자열을 커널 버퍼로 옮긴다. 옛 주소 공간은 곧 사라진다.
        SET   argc,0
        SET   n,0
1H      SLU   res+1,argc,3
        ADDU  res+1,argv,res+1
        SETL  res+2,4
        PUSHJ res,:UserPA
        BN    res,Fail
        ORH   res,#8000
        LDO   p,res,0           p=argv[argc]
        BZ    p,3F
        CMP   t,argc,:MaxArg
        BNN   t,Fail
2H      SET   res+1,p
        PUSHJ res,:UGet
        BN    res,Fail
        STB   res,eb,n
        ADD   n,n,1
        SETL  t,#1000
        CMP   t,n,t
        BNN   t,Fail            인자가 모두 4KB를 넘는다
        ADD   p,p,1
        BNZ   res,2B
        ADD   argc,argc,1
        JMP   1B
3H      BZ    argc,Fail
% 파일을 찾는다. 없으면 ".mmo"를 붙여 본다(MMIX-SIM과 같다).
        SET   res+1,eb
        PUSHJ res,:Lookup
        BNN   res,Found
        SETH  p,#8000
        ORMH  p,#0006
        SETL  t,:LineOff
        ADDU  p,p,t             줄 버퍼에 이름을 만든다
        SET   k,0
4H      LDBU  c,eb,k
        BZ    c,5F
        STB   c,p,k
        ADD   k,k,1
        CMP   t,k,:NameMax
        BP    t,Fail
        JMP   4B
5H      SETL  c,'.'
        STB   c,p,k
        ADD   k,k,1
        SETL  c,'m'
        STB   c,p,k
        ADD   k,k,1
        STB   c,p,k
        ADD   k,k,1
        SETL  c,'o'
        STB   c,p,k
        ADD   k,k,1
        SET   c,0
        STB   c,p,k
        SET   res+1,p
        PUSHJ res,:Lookup
        BN    res,Fail
Found   SETH  ih,#8000
        ORMH  ih,#0006
        SETL  t,:IHOff
        ADDU  ih,ih,t
        SETL  t,2
        STO   t,ih,:HKIND
        SETL  t,5
        STO   t,ih,:HMODE       이진 읽기
        STO   res,ih,:HENT
        STCO  0,ih,:HPOS
        STCO  0,ih,:HCBLK
        STCO  0,ih,:HCIDX
        SET   res+1,ih
        PUSHJ res,:ReadTet
        BN    res,Fail
        SRU   t,res,8
        SETL  c,#9809
        SLU   c,c,8
        OR    c,c,1
        CMP   t,t,c
        BNZ   t,Fail            서문이 아니다
        AND   k,res,#ff         만든 시각의 테트라 수
6H      BZ    k,Clear
        SET   res+1,ih
        PUSHJ res,:ReadTet
        SUB   k,k,1
        JMP   6B
% 여기부터는 돌아갈 수 없다. 옛 주소 공간을 놓고, 비어 있는 페이지는 0으로 채워
% 들이게 하고, 스택 세그먼트의 앞부분을 들여놓는다.
Clear   GETA  t,:Cur
        LDO   ent,t,0
        SLU   ent,ent,:PShift
        GETA  t,:Procs
        ADDU  ent,ent,t
        STCO  0,ent,:BACK
        PUSHJ res,:FreeSpace    옛 주소 공간의 프레임을 돌려준다
        NEG   t,0,1
        GETA  c,:URTag
        STO   t,c,0
        GETA  c,:UWTag
        STO   t,c,0
        SET   k,0
8H      SETH  res+1,#6000
        SLU   t,k,:PageS
        OR    res+1,res+1,t
        PUSHJ res,:PageIn
        ADD   k,k,1
        CMP   t,k,:StackPages
        BN    t,8B
% 목적 파일을 싣는다. mmixsim의 적재기와 같은 일을 한다. 보통의 테트라와 고치기는
% 모두 배타적 논리합으로 싣는다(새 주소 공간은 0이다).
        SET   loc,0
Item    SET   res+1,ih
        PUSHJ res,:ReadTet
        BN    res,Bad
        SET   tet,res
Disp    SRU   t,tet,24
        CMP   t,t,#98
        BNZ   t,Load
        SRU   c,tet,16
        AND   c,c,#ff           lopcode
        SETL  t,#ffff
        AND   k,tet,t           YZ
        BZ    c,Quote
        CMP   t,c,1
        BZ    t,Loc
        CMP   t,c,2
        BZ    t,Skip
        CMP   t,c,3
        BZ    t,Fixo
        CMP   t,c,4
        BZ    t,Fixr
        CMP   t,c,5
        BZ    t,Fixrx
        CMP   t,c,6
        BZ    t,File
        CMP   t,c,7
        BZ    t,Item            lop_line은 무시한다
        CMP   t,c,8
        BZ    t,Spec
        CMP   t,c,10
        BZ    t,Post
        JMP   Bad
Quote   CMP   t,k,1
        BNZ   t,Bad
        SET   res+1,ih
        PUSHJ res,:ReadTet
        BN    res,Bad
        SET   tet,res
Load    ANDN  loc,loc,3
        SET   res+1,loc
        SET   res+2,tet
        PUSHJ res,:XorT
        BN    res,Bad
        ADDU  loc,loc,4
        JMP   Item
Loc     SET   res+1,ih
        SET   res+2,tet
        PUSHJ res,:ReadAddr
        BN    res,Bad
        SET   loc,res
        JMP   Item
Skip    ADDU  loc,loc,k
        JMP   Item
Fixo    SET   res+1,ih
        SET   res+2,tet
        PUSHJ res,:ReadAddr
        BN    res,Bad
        SET   p,res
        SET   res+1,p
        SRU   res+2,loc,32
        PUSHJ res,:XorT
        BN    res,Bad
        ADDU  res+1,p,4
        SLU   res+2,loc,32
        SRU   res+2,res+2,32
        PUSHJ res,:XorT
        BN    res,Bad
        JMP   Item
Fixr    SET   p,k               delta
        SET   c,k               차이 d
        JMP   FixIt
Fixrx   CMP   t,k,16
        BZ    t,1F
        CMP   t,k,24
        BNZ   t,Bad
1H      SET   res+1,ih
        PUSHJ res,:ReadTet
        BN    res,Bad
        SET   p,res
        SRU   t,p,25
        BNZ   t,Bad
        SET   c,p
        SRU   t,p,24
        BZ    t,FixIt
        SETML t,#ff
        ORL   t,#ffff
        AND   c,p,t
        SETL  t,1
        SLU   t,t,k
        SUB   c,c,t             뒤쪽을 가리키는 k비트 차이
FixIt   SLU   t,c,2
        SUBU  res+1,loc,t
        SET   res+2,p
        PUSHJ res,:XorT
        BN    res,Bad
        JMP   Item
File    AND   k,tet,#ff
9H      BZ    k,Item
        SET   res+1,ih
        PUSHJ res,:ReadTet
        BN    res,Bad
        SUB   k,k,1
        JMP   9B
Spec    SET   res+1,ih
        PUSHJ res,:ReadTet
        BN    res,Bad
        SET   tet,res
        SRU   t,tet,24
        CMP   t,t,#98
        BNZ   t,Spec
        SRU   t,tet,16
        AND   t,t,#ff
        BNZ   t,Disp            특수 데이터가 끝났다
        SETL  c,#ffff
        AND   c,tet,c
        CMP   c,c,1
        BNZ   c,Disp
        SET   res+1,ih
        PUSHJ res,:ReadTet      인용된 테트라를 건너뛴다
        BN    res,Bad
        JMP   Spec
% 후기. 스택 세그먼트에 UNSAVE할 문맥을 쌓는다.
Post    AND   g,tet,#ff
        CMP   t,g,32
        BN    t,Bad
        SETH  p,#6000
        SET   res+1,p
        SET   res+2,argc
        PUSHJ res,:PutO         $0=argc
        BN    res,Bad
        ADDU  res+1,p,8
        SETH  res+2,#4000
        ORL   res+2,8
        PUSHJ res,:PutO         $1=Pool_Segment+8
        BN    res,Bad
        ADDU  res+1,p,16
        SETL  res+2,2
        PUSHJ res,:PutO         rL=2
        BN    res,Bad
        ADDU  p,p,24
        SET   k,g
PostL   SET   res+1,ih
        PUSHJ res,:ReadTet
        BN    res,Bad
        SLU   main,res,32
        SET   res+1,ih
        PUSHJ res,:ReadTet
        BN    res,Bad
        OR    main,main,res
        SET   res+1,p
        SET   res+2,main
        PUSHJ res,:PutO         $k
        BN    res,Bad
        ADDU  p,p,8
        ADD   k,k,1
        SETL  t,256
        CMP   t,k,t
        BN    t,PostL           마지막 main이 곧 $255, Main이다
        ADDU  p,p,96            특수 레지스터 열둘은 0이다
        SET   res+1,p
        SLU   res+2,g,56
        PUSHJ res,:PutO         rG와 rA
        BN    res,Bad
% 풀 세그먼트에 argv를 둔다.
        SETH  t,#4000
        ADD   c,argc,2
        SLU   c,c,3
        ADDU  loc,t,c           첫 문자열의 자리
        SET   k,0
        SET   n,0
ArgL    CMP   t,k,argc
        BNN   t,ArgD
        SETH  res+1,#4000
        ADD   t,k,1
        SLU   t,t,3
        ADDU  res+1,res+1,t
        SET   res+2,loc
        PUSHJ res,:PutO         argv[k]
        BN    res,Bad
        SET   tet,0
ArgC    LDBU  c,eb,n
        ADDU  res+1,loc,tet
        SET   res+2,c
        PUSHJ res,:UPut
        BN    res,Bad
        ADD   n,n,1
        BZ    c,ArgE
        ADD   tet,tet,1
        JMP   ArgC
ArgE    ANDN  tet,tet,7
        ADD   tet,tet,8
        ADDU  loc,loc,tet
        ADD   k,k,1
        JMP   ArgL
ArgD    SETH  res+1,#4000
        SET   res+2,loc
        PUSHJ res,:PutO         비어 있는 첫 자리
        BN    res,Bad
% 시작 주소. #F0에 무언가 있으면 거기서 시작한다.
        SETL  res+1,#f0
        SETL  res+2,4
        PUSHJ res,:UserPA
        BN    res,Bad
        ORH   res,#8000
        LDTU  t,res,0
        SET   c,main
        BZ    t,1F
        SETL  c,#f0
1H      PUSHJ res,:FlushText
        STCO  0,ih,:HKIND
        PUSHJ res,:FsUnlock
        STO   p,ent,:CTX
        STO   main,ent,:BBO     처음의 $255는 Main이다
        STO   c,ent,:WWO
        SETH  t,#8000
        STO   t,ent,:XXO        RESUME이 명령을 끼워 넣지 않는다
        STCO  0,ent,:YYO
        STCO  0,ent,:ZZO
        GETA  t,:Cur
        LDO   $0,t,0
        JMP   :Resume
Bad     STCO  0,ih,:HKIND
        PUSHJ res,:FsUnlock
        GETA  res+1,:ExecMsg
        SET   res+2,0
        SETL  res+3,:Fputs<<8|:StdErr
        PUSHJ res,:Device
        NEG   t,0,1
        PUT   :rBB,t
        JMP   :Exit
Fail    PUSHJ res,:FsUnlock
Fail0   NEG   $0,0,1
        PUT   :rJ,rj
        POP   1,0
        PREFIX :

% Lookup(name): 커널 주소 name의 이름(널로 끝남)을 디렉터리에서 찾아 항목 번호를
% 돌려준다. 없으면 -1이다.
        PREFIX Lookup:
name    IS    $0
s       IS    $1
i       IS    $2
e       IS    $3
k       IS    $4
c       IS    $5
d       IS    $6
:Lookup SETH  s,#8000
        ORMH  s,#0006
        SETL  c,:DirOff
        ADDU  s,s,c
        SET   i,0
1H      SLU   e,i,6
        ADDU  e,s,e
        LDBU  c,e,0
        BZ    c,4F
        SET   k,0
2H      LDBU  c,e,k
        LDBU  d,name,k
        CMP   c,c,d
        BNZ   c,4F
        BZ    d,3F
        ADD   k,k,1
        CMP   c,k,48
        BN    c,2B
        JMP   4F
3H      SET   $0,i
        POP   1,0
4H      ADD   i,i,1
        CMP   c,i,:NEnt
        BN    c,1B
        NEG   $0,0,1
        POP   1,0
        PREFIX :

% ReadTet(H): 핸들 H에서 큰 쪽 먼저로 테트라바이트 하나를 읽는다. 파일이 끝났으면 -1.
ReadTet GET   $1,rJ
        SET   $2,0
        SET   $3,4
1H      SET   $5,$0
        PUSHJ $4,Getc
        BN    $4,9F
        SLU   $2,$2,8
        OR    $2,$2,$4
        SUB   $3,$3,1
        BP    $3,1B
        PUT   rJ,$1
        SET   $0,$2
        POP   1,0
9H      PUT   rJ,$1
        NEG   $0,0,1
        POP   1,0

% ReadAddr(H,tet): lop_loc이나 lop_fixo가 가리키는 주소를 읽는다. Z 바이트가 2이면
% Y 바이트가 윗 테트라의 맨 윗 바이트가 되고 다음 테트라가 거기에 더해지며, 1이면
% Y 바이트만 쓴다. 그다음 테트라가 아랫 테트라다. 잘못되었으면 -1(사용자의 주소는
% 음이 아니다).
ReadAddr GET  $2,rJ
        SRU   $3,$1,8
        AND   $3,$3,#ff
        SLU   $3,$3,24
        AND   $4,$1,#ff
        CMP   $5,$4,1
        BZ    $5,1F
        CMP   $5,$4,2
        BNZ   $5,9F
        SET   $6,$0
        PUSHJ $5,ReadTet
        BN    $5,9F
        ADDU  $3,$3,$5
1H      SET   $6,$0
        PUSHJ $5,ReadTet
        BN    $5,9F
        SLU   $3,$3,32
        OR    $3,$3,$5
        PUT   rJ,$2
        SET   $0,$3
        POP   1,0
9H      PUT   rJ,$2
        NEG   $0,0,1
        POP   1,0

% XorT(va,val): 사용자 주소 va의 테트라에 val을 배타적 논리합으로 싣는다.
% PutO(va,val): 사용자 주소 va에 옥타바이트 val을 쓴다. 둘 다 실패하면 -1.
XorT    GET   $2,rJ
        SET   $4,$0
        SETL  $5,2
        PUSHJ $3,UserPA
        PUT   rJ,$2
        BN    $3,9F
        ORH   $3,#8000
        LDTU  $4,$3,0
        XOR   $4,$4,$1
        STTU  $4,$3,0
        SET   $0,0
        POP   1,0
9H      NEG   $0,0,1
        POP   1,0
PutO    GET   $2,rJ
        SET   $4,$0
        SETL  $5,2
        PUSHJ $3,UserPA
        PUT   rJ,$2
        BN    $3,9F
        ORH   $3,#8000
        STO   $1,$3,0
        SET   $0,0
        POP   1,0
9H      NEG   $0,0,1
        POP   1,0

% FlushText(): 텍스트 세그먼트의 들어 있는 프레임을 모두 SYNCD로 메모리에 내려보낸다.
% 커널이 STTU로 실은 명령은 아직 D-캐시에만 있을 수 있기 때문이다(CopyPage를 보라).
FlushText GET $0,rJ
        GET   $2,rV
        GETA  $3,SyncCb
        SET   $4,0
        SETL  $5,1
        SET   $6,0
        PUSHJ $1,Walk
        PUT   rJ,$0
        POP   0,0

% ---- 잠들기와 깨우기 ----
% Sleep(chan): 지금 프로세스를 chan(1: 디스크, 2: 파일 시스템 자물쇠)에서 잠재우고 다른
% 프로세스로 넘어간다. 커널 안 어디서든 부를 수 있다. SAVE는 사용자의 레지스터뿐 아니라
% 그 위에 쌓인 커널의 틀까지 모두 저장하므로, 깨어나면 Resume이 UNSAVE한 뒤 이곳의 Cont로
% 돌아와 부른 곳으로 POP한다. 그때 $255는 S255에서 되돌린다.
        PREFIX Sleep:
chan    IS    $0
e       IS    $1
t       IS    $2
res     IS    $3
:Sleep  GETA  t,:Cur
        LDO   e,t,0
        SLU   e,e,:PShift
        GETA  t,:Procs
        ADDU  e,e,t             e=이 프로세스의 항목
        STO   chan,e,:SCHAN
        SETL  t,4
        STO   t,e,:ST
        GETA  t,:NReady
        LDO   res,t,0
        SUB   res,res,1
        STO   res,t,0
        GETA  t,Cont
        STO   t,e,:KPC
        SAVE  $255,0
        SET   res+1,$255
        PUSHJ res,:Store
        PUSHJ res,:Next
        SET   $0,res
        JMP   :Resume
Cont    LDO   $255,e,:S255      깨어났다
        POP   0,0
        PREFIX :

% Wakeup(chan): chan에서 잠든 프로세스를 모두 깨운다. 돌 수 있는 프로세스가 둘 이상이
% 되면 타이머를 건다(혼자일 때 꺼 두었을 수 있다).
Wakeup  GETA  $1,Procs
        SET   $2,0
        SET   $5,0              깨운 수
1H      SLU   $3,$2,PShift
        ADDU  $3,$3,$1
        LDO   $4,$3,ST
        CMP   $4,$4,4
        BNZ   $4,2F
        LDO   $4,$3,SCHAN
        CMP   $4,$4,$0
        BNZ   $4,2F
        SETL  $4,1
        STO   $4,$3,ST
        ADD   $5,$5,1
2H      ADD   $2,$2,1
        CMP   $4,$2,NProc
        BN    $4,1B
        BZ    $5,9F
        GETA  $4,NReady
        LDO   $6,$4,0
        ADD   $6,$6,$5
        STO   $6,$4,0
        CMP   $6,$6,1
        BNP   $6,9F
        SETL  $4,Quantum
        PUT   rI,$4
9H      POP   0,0

% FsLock(), FsUnlock(): 파일 시스템의 자물쇠. 블록 캐시와 핸들 표를 함께 쓰므로, 한
% 프로세스가 파일 연산 도중에 디스크를 기다리며 잠든 사이에 다른 프로세스가 들어오면 안
% 된다. 자물쇠가 잠겨 있으면 풀릴 때까지 잠든다. 커널은 선점되지 않으므로 자물쇠를 쥔
% 프로세스는 디스크를 기다리며 잠든 것뿐이다.
FsLock  GET   $0,rJ
1H      GETA  $1,FsOwner
        LDO   $2,$1,0
        BN    $2,2F
        SETL  $4,2
        PUSHJ $3,Sleep
        JMP   1B
2H      GETA  $2,Cur
        LDO   $2,$2,0
        STO   $2,$1,0
        PUT   rJ,$0
        POP   0,0
FsUnlock GETA $1,FsOwner
        NEG   $2,0,1
        STO   $2,$1,0
        GET   $0,rJ
        SETL  $4,2
        PUSHJ $3,Wakeup
        PUT   rJ,$0
        POP   0,0

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

ExitNext OCTA  0                Exit이 다음에 돌릴 pid
FsOwner OCTA  -1                파일 시스템 자물쇠를 쥔 pid(없으면 -1)
Cur     OCTA  0                 지금 도는 프로세스의 pid
NReady  OCTA  1                 돌 수 있는 프로세스의 수
Procs   OCTA  1,#369C0D0700000008,0,0,0,0,0,0,-1,1 프로세스 0: 돌 수 있고, 테이블은 7<<32, n=1, 부모 없음, 이미지
        LOC   Procs+NProc*128
KillMsg BYTE  "NNIX: page fault I can't serve",#a,0
        LOC   (@+3)&-4
ExecMsg BYTE  "NNIX: exec failed",#a,0
        LOC   (@+3)&-4          GETA로 가리키는 곳은 테트라 경계여야 한다
ArgKind BYTE  0,1,0,2,2,2,3,4,5,6,0
        LOC   (@+3)&-4
ModeCode BYTE 1,2,5,6,#f        Fopen의 방식 0..4에 대한 mmixio의 방식 코드
        LOC   (@+7)&-8
Mounted OCTA  0                 디스크를 마운트했는가
NBlocks OCTA  0                 디스크의 블록 수
FatStart OCTA 0                 FAT가 시작하는 블록
FatBlocks OCTA 0                FAT의 블록 수
DirStart OCTA 0                 디렉터리가 시작하는 블록
DataStart OCTA 0                데이터가 시작하는 블록
CacheBlk OCTA -1                블록 캐시에 든 블록(없으면 -1)
CacheDirty OCTA 0               캐시를 아직 디스크에 쓰지 않았는가
MetaDirty OCTA 0                FAT나 디렉터리를 아직 디스크에 쓰지 않았는가
URTag   OCTA  -1                UGet이 기억하는 사용자 페이지
URPA    OCTA  0                 그 페이지의 커널 주소
UWTag   OCTA  -1                UPut이 기억하는 사용자 페이지
UWPA    OCTA  0                 그 페이지의 커널 주소
