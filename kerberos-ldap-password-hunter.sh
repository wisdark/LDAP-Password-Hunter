#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
ORANGE='\033[0;33m'
echo -e "${GREEN}****LDAP PASSWORD ENUM****${NC}"
#1 dc-ip
#2 DC hostname ( for the SPN )
#3 username
#4 domain 

if [ -z $KRB5CCNAME ] ; then  
	echo "Creating a TGT ticket for the user"
	getTGT.py -dc-ip $1 $5/$3
	mv $3.ccache $3TGT.ccache
	export KRB5CCNAME="$(pwd)"/$3TGT.ccache
fi 
#exporting LDAPSAL_NOCANON variable for forcing not to reverse lookup
export LDAPSASL_NOCANON=on
DOMAIN=$4
base=""
filter="(|"
baseconf="CN=Schema,CN=Configuration,"
baseconf+=$(ldapsearch -R $5 -h $2.$DOMAIN -Y GSSAPI -s base -b "" rootDomainNamingContext | grep -i rootDomainNamingContext: | cut -d " " -f 2)

echo "Building attributes list"
ldapsearch -R $5 -h $2.$DOMAIN -E pr=10000/noprompt -Y GSSAPI -b "${baseconf}" lDAPDisplayName | grep -i lDAPDisplayName | cut -d " " -f 2 | grep -iE 'password|pwd|creds|cred|secret|userpw' | grep -vEi 'count|set|time|age|length|properties|format|data' | sort | uniq  > $DOMAIN-keywords.txt
echo -n "Analyzing domain " 
echo -e "${ORANGE}${DOMAIN^^}${NC}"
IFS='.' read -r -a array <<< "$DOMAIN"
for x in ${!array[@]}; do
   base="${base}DC=${array[x]},"
done

for KEYWORD in $(cat $DOMAIN-keywords.txt)
do
  if ! grep -Fxq ${KEYWORD//[$'\t\r\n']} attribute-blacklist.txt; then
    filter+="(${KEYWORD}=*)" 
  else
    echo -e "${RED}Found blacklisted keyword:${NC} ${KEYWORD}"
    sed -e "/^${KEYWORD}$/d" -i $DOMAIN-keywords.txt
  fi
done
filter+=")"
echo -e "${RED}****Results are on disk, enumerating next DC! ****${NC}"
ldapsearch -R $5 -h $2.$DOMAIN -E pr=10000/noprompt -Y GSSAPI -b "${base::-1}" "${filter}" > $DOMAIN-enum.txt
echo "" 
cat $DOMAIN-enum.txt | grep -i -w -f $DOMAIN-keywords.txt | grep -ivE 'filter|objectclass|ExpirationTime' | uniq  > $DOMAIN-enum-bak.txt
mv $DOMAIN-enum-bak.txt $DOMAIN-enum.txt
echo "" 

while read -r x; do
     read -r y
    DN=$(echo $x | cut -d ":" -f2)
    #VALUE=$(echo $y | cut -d ":" -f3 | sed 's/ //g')
  if [ "$y" != "" ]; then  
     CHECK=$(sqlite3 ldapph.db "SELECT FindingId FROM LDAPHUNTERFINDINGS WHERE DistinguishedName = '${DN}' AND Value = '${y}';")
     if [ "$CHECK" == ""  ]; then
         echo -ne "${RED}NEW ENTRY IN THE DATABASE:${NC}"
         echo -ne $y
         echo " - $(date)"
         echo "${y} - $(date)" >> $DOMAIN-new-entries-$(date "+%F").txt
         sqlite3 ldapph.db "INSERT INTO LDAPHUNTERFINDINGS (DistinguishedName,Value,Domain) VALUES('${DN}','${y}','${DOMAIN}');" ".exit"
     fi 
     sqlite3 ldapph.db "DELETE FROM LDAPHUNTERFINDINGS WHERE Value IS ''"
  fi
done < $DOMAIN-enum.txt
