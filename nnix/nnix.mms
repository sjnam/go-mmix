% NNIX 1단계: 진짜 트랩 처리기와 호스트 입출력 장치(HIO).
%
% 크누스는 MMIX의 운영체제를 NNIX라고 부르고는 만들지 않았다(mmixdoc.w 2절).
% 메타 시뮬레이터 mmmix는 그 자리를 ``마법''으로 메운다. rT 자리에서 RESUME 1을
% 배정하면 MMIX-SIM의 입출력 트랩 열 가지가 뒤에서 순식간에 일어난다. 이 커널은
% 그 자리에 진짜 처리기를 둔다. 트랩을 나누고, 사용자 메모리에서 인자를 읽고,
% 가상 주소를 물리 주소로 바꾸고, 장치 레지스터를 거쳐 입출력을 시킨다.
%
%   mmixal -b 250 -o nnix.mmo nnix.mms
%   mmmix -knnix.mmo plain.mmconfig hello.mmb
%
% mmmix의 -k는 미리 짜 둔 환경(뼈대 페이지 테이블, rT, rTT)을 준비한 뒤에 이
% 커널을 싣는다. 그래서 이 커널은 rT=#8000000500000000 자리의 원시 처리기를 덮어쓴다.
% rTT=#8000000600000000의 원시 동적 트랩 처리기는 1단계에서 그대로 둔다.
%
% 물리 메모리 배치(앞의 넷은 mmmix가 미리 짜 두는 환경과 같다):
%   0 .. 4<<32    사용자 세그먼트 넷(텍스트, 데이터, 풀, 스택)
%   4<<32         뼈대 페이지 테이블
%   5<<32         이 커널의 코드와 데이터 (rT가 가리키는 입구)
%   6<<32         원시 동적 트랩 처리기
%   2^48+d<<16    장치 d. 1단계에는 d=0인 HIO 하나뿐이다.
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

% 연산 코드는 TRAP의 Y와 같다(Fopen=1 .. Ftell=10). 0은 트립 경고다.
TripWarn IS   0
MaxOp   IS    10

        LOC   #8000000500000000
% 입구. TRAP은 사용자의 $255를 rBB로 옮기고 $255를 rJ로 정한 뒤 여기로 온다.
% 처리기가 마음대로 쓸 수 있는 것은 $255뿐이므로, PUSHJ $255로 사용자의 지역
% 레지스터를 모두 숨기고 새 틀에서 일한다. 전역 레지스터는 건드리지 않는다.
Main    PUSHJ $255,Syscall
        PUT   rJ,$255           TRAP이 $255에 넣어 둔 사용자의 rJ를 되돌린다
        NEG   $255,0,1          돌아갈 때의 rK: 모두 허용(원시 처리기와 같다)
        RESUME 1                rK<-$255, $255<-rBB

% 시스템 호출. rXX의 아랫 테트라가 TRAP 0,Y,Z이고 Y<=10일 때만 일한다.
% 그 밖에는 마법처럼 rBB를 그대로 두고 돌아간다.
t       IS    $0
op      IS    $1                Y
h       IS    $2                Z (파일 핸들)
a0      IS    $3                장치의 첫째 인자
a1      IS    $4                장치의 둘째 인자
kind    IS    $5                인자를 가져오는 방식
rj      IS    $6                안에서 PUSHJ를 하므로 rJ를 여기 둔다
res     IS    $7                Translate나 Device를 부르는 자리
Syscall GET   rj,rJ
        GET   t,rXX
        SLU   t,t,32
        SRU   t,t,32            t = rXX의 아랫 테트라
        SRU   op,t,16
        BNZ   op,Done           opcode나 X가 0이 아니면 TRAP 0,Y,Z가 아니다
        SRU   op,t,8            op = Y
        AND   h,t,#ff           h = Z
        CMP   t,op,MaxOp
        BP    t,Done
        BZ    op,Stop
% 인자를 가져온다. 방식은 ArgKind 표에 있다.
%   0: 인자 없음
%   1: 사용자의 M[rBB], M[rBB+8]을 읽고, 앞의 것을 읽기 버퍼로 변환한다
%   2: 1과 같되 쓰기 버퍼로 변환한다
%   3: rBB를 읽기 버퍼로 변환한다
%   4: rBB를 값 그대로 넘긴다
        GETA  t,ArgKind
        LDBU  kind,t,op
        SET   a0,0
        SET   a1,0
        BZ    kind,Call
        GET   a0,rBB
        CMP   t,kind,3
        BNN   t,1F
        LDO   a1,a0,8           커널이 양수 주소를 읽으면 rV를 거쳐 변환된다
        LDO   a0,a0,0
1H      CMP   t,kind,4
        BZ    t,Call
        SET   res+1,a0
        SETL  res+2,4           p_r
        CMP   t,kind,2
        BNZ   t,2F
        SETL  res+2,2           p_w
2H      PUSHJ res,Translate
        BN    res,Bad
        SET   a0,res
Call    SET   res+1,a0
        SET   res+2,a1
        SLU   t,op,8
        OR    res+3,t,h
        PUSHJ res,Device
        PUT   rBB,res           RESUME 1이 이것을 사용자의 $255에 넣는다
Done    PUT   rJ,rj
        POP   0,0
Bad     NEG   t,0,1
        PUT   rBB,t
        JMP   Done

% Stop: Halt. Z=0이면 멈추고, Z=1이면 기본 트립 처리기(TRAP 1)가 부른 것이므로
% 트립 경고를 찍는다. 마법처럼 rBB는 그대로 둔다.
Stop    BNZ   h,Warn
        GET   $255,rBB          종료 코드는 Halt할 때의 사용자 $255다(mmmix -s)
        SYNC  5                 쓰기 버퍼를 비운다
1H      SYNC  4
        JMP   1B
Warn    CMP   t,h,1
        BNZ   t,Done
        GET   t,rWW
        SUBU  t,t,4             트립이 일어난 처리기 자리
        CMPU  a0,t,#f0
        BNN   a0,Done
        SRU   res+1,t,4         트립 번호
        GET   res+2,rW
        SUBU  res+2,res+2,4     트립이 일어난 위치
        SETL  res+3,TripWarn
        PUSHJ res,Device
        JMP   Done

% Device(a0,a1,cmd): HIO에 명령 하나를 시키고 그 결과를 돌려준다.
% 앞 명령이 끝났으므로 쓰기 버퍼에 이 장치로 가는 저장은 남아 있지 않다.
% DONE은 순수하게 읽히므로 투기적으로 읽혀도 상관없고, 값이 바뀔 때까지 돈다.
% 그 뒤의 SYNC 2는 RESULT를 DONE보다 먼저 읽지 못하게 막는다.
dev     IS    $3
seq     IS    $4
Device  SETH  dev,HIO
        LDO   seq,dev,DONE
        STO   $0,dev,ARG0
        STO   $1,dev,ARG1
        STO   $2,dev,CMD
1H      LDO   $5,dev,DONE
        CMPU  $5,$5,seq
        BZ    $5,1B
        SYNC  2
        LDO   $0,dev,RESULT
        POP   1,0

% Translate(virt,need): 음이 아닌 가상 주소 virt를 물리 주소로 바꾼다.
% 그 페이지의 보호 비트에 need(p_r=4, p_w=2)가 모두 있어야 하고,
% 실패하면 -1을 돌려준다. 물리 주소는 2^48보다 작으므로 실패와 헷갈리지 않는다.
%
% 가운데 부분은 크누스가 명세(mmixdoc.w 47절)에 적은 소프트웨어 변환 코드를
% 거의 그대로 옮긴 것이다. 다른 점은 셋이다. virt를 rYY 대신 인자로 받고,
% 맨 끝에서 PTE를 rZZ에 넣고 RESUME하는 대신 물리 주소를 만들어 POP하고,
% 실패하면 PTE 0 대신 -1을 돌려준다.
virt    IS    $8
base    IS    $9
limit   IS    $10
s       IS    $11
mask    IS    $12
need    IS    $13
Translate SET virt,$0
        SET   need,$1
        BN    virt,Fail         사용자의 주소는 음이 아니어야 한다
        GET   $7,rV             $7=(가상 변환 레지스터)
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

ArgKind BYTE  0,1,0,2,2,2,1,3,3,4,0
