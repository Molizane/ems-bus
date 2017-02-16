#!/bin/bash 
#
# Title: ERLANGMS ldap client tool (bash version)
# Author: Everton de Vargas Agilar
# Data: 16/03/2016
#
# Requisitos: Necessita do pacote ldap-utils
#

# Verifica se não há parâmetros
if [ "$#" = "0" ] || [ "$1" = "--help" ]; then
	echo "Modo de usar 1: ./ldap_client.sh qtd_requests host_ldap user"
	echo "Modo de usar 2: ./ldap_client.sh host_ldap user"
	echo "         qtd_requests  => número de requisições simultâneas (default é 100)"
	echo "         host_ldap     => host do ldap (default é localhost:2389)"	
	echo "         user          => login do user"	
	echo "         admin_passwd  => password do admin do ldap"	
	exit
fi

# Parâmetro qtd_requests
if [ $# -ge 3 ]; then
	COUNTER=$1
    RE='^[0-9]+$'
    if ! [[ $COUNTER =~ $RE ]] ; then
       echo "Parâmetro qtd_requests ( $COUNTER ) deve ser um número!" >&2; exit 1
    fi
else
    COUNTER=1
fi

# Parâmetro host_ldap
if [ "$#" = "4" ]; then
    HOST_LDAP="$2"
    RE='^[0-9a-zA-Z_-.]+:[0-9]+$'
    if ! [[ $HOST_LDAP =~ $RE ]] ; then
       echo "Parâmetro host_ldap ( $HOST_LDAP ) deve possuir o seguinte formato: hostname:port. Ex.: localhost:2389" >&2; exit 1
    fi
else
       HOST_LDAP="localhost:2389"
fi

# Parâmetro user
if [ "$#" = "1" ] || [ "$#" = "2" ]; then
    USER=$1
elif [ "$#" = "3" ]; then
    USER=$2
else
    USER=$3
fi

# Parâmetro password
if [ "$#" = "4" ]; then
	ADMIN_PASSWD="$4"
elif [ "$#" = "3" ]; then
    ADMIN_PASSWD="$3"
elif [ "$#" = "2" ]; then
	ADMIN_PASSWD="$2"
else
	echo "Informe a senha do administrador do LDAP para autenticação:"
	read -s ADMIN_PASSWD
fi

if [ "$COUNTER" = "1" ]; then
	echo ""
	echo "Realizando 1 requisição LDAP para $HOST_LDAP com user $USER"
	echo "    Cmd: " ldapsearch -xLLL -h "$HOST_LDAP" -b 'dc=unb,dc=br' -D 'cn=admin,dc=unb,dc=br' uid="$USER" -w "xxxxxxx"
	echo ""
	ldapsearch -xLLL -h "$HOST_LDAP" -b 'dc=unb,dc=br' -D 'cn=admin,dc=unb,dc=br' uid="$USER" -w "$ADMIN_PASSWD"
else
	echo ""
	echo "Realizando $COUNTER requisições LDAP para $HOST_LDAP com user $USER"
	echo "    Cmd: " ldapsearch -xLLL -h "$HOST_LDAP" -b 'dc=unb,dc=br' -D 'cn=admin,dc=unb,dc=br' uid="$USER" -w "xxxxxxx"
	echo ""
	until [  $COUNTER -lt 1 ]; do
		let COUNTER-=1
		ldapsearch -xLLL -h "$HOST_LDAP" -b 'dc=unb,dc=br' -D 'cn=admin,dc=unb,dc=br' uid="$USER" -w "$ADMIN_PASSWD"
		echo "---"
	done
fi
			         