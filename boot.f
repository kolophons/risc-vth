: (
  BEGIN
      CONSOLE-KEY 41 - 1 U<
  UNTIL
; IMMEDIATE ( and now we have comments )

( value -- value==0? )
: 0= 1 U< ;

( a b -- a==b? )
: =
  ( if not a<b and not b<a, then a=b by construction )
  OVER OVER U< ( a b a<b? )
  IF
      2DROP 0 EXIT
  THEN
  SWAP U< 0=
;

: ACCEPT-CHAR ( buffer capacity len -- buffer capacity len char )
    CONSOLE-KEY ( buffer capacity len char )
    DUP 8 =
    IF
      SWAP DUP  ( buffer capacity char len len )
      IF 1-     ( check if len is 0. If not, then decrement )
      THEN SWAP ( buffer capacity len-1|0 char )
      EXIT
    THEN
    DUP 10 = IF EXIT THEN ( newline check )

    -ROT 2DUP SWAP U< ( buffer char capacity len len<capacity? )
    IF                  ( buffer char capacity len )
      2OVER -ROT OVER + ( buffer char capacity char len buffer+len )
      ROT SWAP          ( buffer char capacity len char buffer+len )
      C! ( buffer char capacity len :: Store char at buffer+len )
      1+ ( buffer char capacity len+1 )
    THEN ( buffer char capacity len )
    ROT  ( buffer capacity len char )
;
: ACCEPT ( buffer capacity -- length )
    0 ( buffer capacity 0 )
    BEGIN
      ACCEPT-CHAR ( buffer capacity len char )
      10 =        ( :: check if char is a newline )
    UNTIL   ( buffer capacity len )
    NIP NIP ( len )
;

