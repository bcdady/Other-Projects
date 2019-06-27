# Get-DomainAccounts

These scripts are powerful, but written in a becoming-increasingly-rare language, and requiring multiple external dependencies, and so I've forked this repo to start working on translating these scripts to a new language, like PowerShell, to ideally be a self-contained replacement, or at least be more cohesive/comprehensive, and modular.
I may also consider using bits or pieces of this to give me something to work on in Python or Go, as I want (need?) to skill up in those languages.

---

## Get-DomainAdmin

Forked from GDA by Scott Sutherland ([nullbind](https://github.com/nullbind/Other-Projects))

### Script Summary

The primary goal of the script is to locate systems 
running processes with a Domain Admin account so that pen-testers
can conduct cleaner privilege escalation in Active Directory domains.  

#### How it Works

1. Gather a list of Domain Controllers from the ADS "Domain Controllers" OU 
   using LDAP and a trusted connection.

2. Gather a list of Domain Admins from the ADS "Domain Admins" group using LDAP and a trusted connection.

3. Gather a list of all of the active sessions being tracked on each of the domain controllers

   The following information will be returned:
   - IP address
   - Username 
   - Session start time
   - Session idle time

4. Cross reference the Domain Admin list with the active session list to determine which IP addresses have processes being run as a Domain Admin.

## Get-DomainUser

Forked from GDU by Scott Sutherland ([nullbind](https://github.com/nullbind/Other-Projects))

### Script Summary

 This script is intended to automate Windows domain user enumeration using multiple methods, and initiate a dictionary attack against the accounts with respect to the account lockout policy.

 Technical Summary:

 1) Determine domain from ipconfig (option provided to override)
 2) Identify domain controllers via DNS server queries
 3) Enumerate users via RCP endpoints

 Authentication Methods:

 Users can authenticate with one of three options:

 1) Null SMB Login
 2) Trusted connection
 3) Username and password

 Notes:

 1) If no lockout policy exists, the dictionary attack will be aborted so it can be manually confirmed.

 2) If the lockout policy cannot be determined the dictionary attack will be aborted.

## "Todo"
  
 1) Add fast/comprehensive modes - fast=stop user enumeration on first success.
 2) Add custom dictionary option.
 3) Add check for required executables before running.
 4) Add some more error checking.
 5) Write the script in a real programming language . - Maybe ruby...  :)
  



