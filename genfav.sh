#!/bin/sh

# CHANGELOG
# * Version 1.0
#	- Initial version
# * Version 1.0.1
#	- Correcao na geracao do favorito que contem todos os canais
#	- Ignorando espaco inicial e final no nome dos favoritos e filtros
# * Version 1.1
#	- O favorito que contem todos os canais agora inclui o numero do satelite a qual o canal pertence
# * Version 1.2
#	- Incluido verificacao da existencia do arquivo de regras

LAMEFILE=/etc/enigma2/lamedb
RULES=/etc/enigma2/genfav_rules.txt
OUTDIR=/etc/enigma2
TMPDIR=/tmp/genfav_tmp
LOGFILE=$TMPDIR/genfav.log

SATS=""
SERVICE=""
EXCLUDE=""

if [ ! -e $RULES ]; then
        echo "!!! ARQUIVO DE REGRAS NAO ENCONTRADO EM: $RULES !!!"
        exit 1
fi

if [ ! -d $TMPDIR ]; then
	mkdir $TMPDIR
fi
rm -rf $TMPDIR/*

if [ ! -d $OUTDIR ]; then
	mkdir $OUTDIR
fi
rm -rf $OUTDIR/userbouquet.*
rm -rf $OUTDIR/bouquets.*

log()
{
	if [ "$2" = "2" ]; then
		touch $LOGFILE
		printf "$1 \r\n"
		printf "$1 \r\n" >> $LOGFILE
        else
                touch $LOGFILE
                echo "$1"
                echo "$1" >> $LOGFILE
        fi
}

convertdb ()
{
	log "### Convertendo a base de dados de canais"	

	LINENUMBERFIRSTEND=$(grep -n '^end$' $LAMEFILE | cut -d: -f1 | head -n 1)

	log "   -> Separando lista de TPs"
	head -n $LINENUMBERFIRSTEND $LAMEFILE > $TMPDIR/transponder.txt
	tail -n $(($(wc -l $LAMEFILE | cut -d' ' -f1)-$(wc -l $TMPDIR/transponder.txt | cut -d' ' -f1))) $LAMEFILE > $TMPDIR/services.txt

	log "   -> Separando lista de canais"
	grep -E '^.{8}:.{4}:.{4}$' $TMPDIR/transponder.txt | cut -d: -f1 | sort | uniq > $TMPDIR/transponder_code.txt

	touch $TMPDIR/tp-sat.txt

	log "   -> Classificando TPs por satelite"
	for CODE in $(cat $TMPDIR/transponder_code.txt); do
		SAT=$(grep -A 1 $CODE $TMPDIR/transponder.txt | grep -Ev '^.{8}:.{4}:.{4}$' | cut -d: -f5  | grep -v ^--$ | sort | uniq | cut -c2-3)
		echo "$CODE:$SAT" >> $TMPDIR/tp-sat.txt
	done

	log "### Classificando canais por satelite"
	for SAT in $(cut -d: -f2 $TMPDIR/tp-sat.txt | sort | uniq); do
		echo "      * Satelite $SAT"
		SATS="$SATS $SAT"
		touch $TMPDIR/sat-$SAT.txt
		for CODESAT in $(grep ":$SAT" $TMPDIR/tp-sat.txt | cut -d: -f1); do
			grep -A 1 $CODESAT $TMPDIR/services.txt | tr '\n' ':' | sed 's/:--:/\n/g' | sed 's/.:$/\n/g' | grep -v '^$' >> $TMPDIR/sat-$SAT.txt
		done	
	done
}

checkexclude ()
{
	if cat "$RULES" | grep -i "^exclude=" &>/dev/null; then
		EXCLUDE=$(cat "$RULES" | grep -i "^exclude=" | cut -d= -f2 | sed 's/,/|:/g')
	fi
}

mkservice ()
{
	CHANNEL="$1"
	NAME="$2"

	CHANNELCODE1=$(echo $CHANNEL | cut -d: -f1 | sed 's/^0*//g' | tr 'a-z' 'A-Z')

	CHANNELTP=$(echo $CHANNEL | cut -d: -f2 | sed 's/^0*//g' | tr 'a-z' 'A-Z')

	CHANNELCODE2=$(echo $CHANNEL | cut -d: -f3 | sed 's/^0*//g' | tr 'a-z' 'A-Z')
	if [ "$CHANNELCODE2" == "" ]; then
		CHANNELCODE2=0
	fi

	CHANNELTYPE=$(echo $CHANNEL | cut -d: -f5 | sed 's/^0*//g' | tr 'a-z' 'A-Z')
	if [ "$CHANNELTYPE" == "25" ]; then
		CHANNELTYPE=19
	fi

	if [ "$NAME" == "" ]; then
		SERVICE="#SERVICE 1:0:$CHANNELTYPE:$CHANNELCODE1:$CHANNELCODE2:1:$CHANNELTP:0:0:0:\n"
	else
		SERVICE="#SERVICE 1:0:$CHANNELTYPE:$CHANNELCODE1:$CHANNELCODE2:1:$CHANNELTP:0:0:0::$NAME\n#DESCRIPTION $NAME\n"
	fi

}

genfavall ()
{
	SAT="$1"
	CHANNELTYPE="$2"

	log "### Gerando favoritos gerais"

	if [ ! -e $OUTDIR/userbouquet.favourites.tv ]; then
		echo "#NAME Favourites (TV)" > $OUTDIR/userbouquet.favourites.tv
	fi
	if [ ! -e $OUTDIR/userbouquet.favourites.radio ]; then
		echo "#NAME Favourites (Radio)" > $OUTDIR/userbouquet.favourites.radio
	fi

	if [ "$EXCLUDE" == "" ]; then
		cat "$TMPDIR/sat-$SAT.txt" | sort -t: -k7 | grep -E '.*:.*:.*:.*:.*:.*:' > $TMPDIR/genfavall-$SAT.txt
	else
		cat "$TMPDIR/sat-$SAT.txt" | sort -t: -k7 | grep -E '.*:.*:.*:.*:.*:.*:' | grep -Eiv "$EXCLUDE" > $TMPDIR/genfavall-$SAT.txt
	fi

	while read REG; do
		CHANNEL="$(echo "$REG" | cut -d: -f1-6)"
		NAME="$(echo "$REG" | cut -d: -f7)"
		mkservice "$CHANNEL" "$NAME ($SAT)"

		if [ "$CHANNELTYPE" == "1" ]; then
			printf "$SERVICE" >> $OUTDIR/userbouquet.favourites.tv
		elif [ "$CHANNELTYPE" == "2" ]; then
			printf "$SERVICE" >> $OUTDIR/userbouquet.favourites.radio
		else
			printf "$SERVICE" >> $OUTDIR/userbouquet.favourites.tv
		fi
	done < "$TMPDIR/genfavall-$SAT.txt"
	
	log "   -> Gerado favorito com $(wc -l $OUTDIR/userbouquet.favourites.tv | cut -d' ' -f1) canais de TV"
	log "   -> Gerado favorito com $(wc -l $OUTDIR/userbouquet.favourites.radio | cut -d' ' -f1) canais de Radio"
	
	SERVICE=""
}

genfav ()
{
	SAT=$1
	FAV=$2
	
	log "   -> Gerando favorito com $(wc -l $TMPDIR/parserule-$SAT-$(echo $FAV | tr ' ' '_')-channel.txt | cut -d' ' -f1) canais"
	echo "#NAME $FAV ($SAT)" > $OUTDIR/userbouquet.$SAT.$(echo $FAV | tr ' ' '_' | tr 'A-Z' 'a-z').tv
	
	for CHANNEL in $(cat $TMPDIR/parserule-$SAT-$(echo $FAV | tr ' ' '_')-channel.txt | cut -d: -f1-6); do
		mkservice "$CHANNEL"
		printf "$SERVICE" >> $OUTDIR/userbouquet.$SAT.$(echo $FAV | tr ' ' '_' | tr 'A-Z' 'a-z').tv
	done

	SERVICE=""
}

parserule ()
{
	SAT="$1"
	FAV="$2"
	FILERULECHANNEL="$3"

	if [ "$FAV" != "exclude" ]; then
		log "   -> Aplicando $(wc -l $FILERULECHANNEL | cut -d' ' -f1) filtros"
		FILTERIN=""
		FILTEROUT=""
		while read RULECHANNEL; do
			if ( echo $RULECHANNEL | grep '^!' &>/dev/null); then
				FILTEROUT="$FILTEROUT|:$(echo $RULECHANNEL | sed 's/!//g')"
			else
				FILTERIN="$FILTERIN|:$(echo $RULECHANNEL)"
			fi
		done < "$FILERULECHANNEL"

		touch $TMPDIR/parserule-$SAT-$(echo $FAV | tr ' ' '_')-channel.txt

		if [ "$EXCLUDE" == "" ]; then
			if [ "$FILTEROUT" == "" ]; then
				cat "$TMPDIR/sat-$SAT.txt" | grep -Ei "${FILTERIN##|}" | sort -t: -k7 >> $TMPDIR/parserule-$SAT-$(echo $FAV | tr ' ' '_')-channel.txt
			else
				cat "$TMPDIR/sat-$SAT.txt" | grep -Ei "${FILTERIN##|}" | grep -Eiv "${FILTEROUT##|}" | sort -t: -k7 >> $TMPDIR/parserule-$SAT-$(echo $FAV | tr ' ' '_')-channel.txt
			fi
		else
			if [ "$FILTEROUT" == "" ]; then
				cat "$TMPDIR/sat-$SAT.txt" | grep -Ei "${FILTERIN##|}" | grep -Eiv "$EXCLUDE" | sort -t: -k7 >> $TMPDIR/parserule-$SAT-$(echo $FAV | tr ' ' '_')-channel.txt
			else
				cat "$TMPDIR/sat-$SAT.txt" | grep -Ei "${FILTERIN##|}" | grep -Eiv "${FILTEROUT##|}" | grep -Eiv "$EXCLUDE" | sort -t: -k7 >> $TMPDIR/parserule-$SAT-$(echo $FAV | tr ' ' '_')-channel.txt
			fi

		fi
	fi
}

rules () {
	SAT=$1

	cat $RULES | grep -v "^#" | grep -v "^$" > $TMPDIR/rulespt.txt

	while read RULELINE; do
		FAV=$(echo $(echo "$RULELINE" | cut -d'=' -f1))
		CHANNELS=$(echo "$RULELINE" | cut -d'=' -f2)

		if [ "$FAV" != "exclude" ]; then
			log "### Lendo regra do favorito: $FAV"
			echo "$CHANNELS" | tr ',' '\n' >> $TMPDIR/rules-$SAT-$(echo $FAV | tr ' ' '_').txt
			parserule "$SAT" "$FAV" "$TMPDIR/rules-$SAT-$(echo $FAV | tr ' ' '_').txt"
			genfav "$SAT" "$FAV"

			echo "#SERVICE 1:7:1:0:0:0:0:0:0:0:FROM BOUQUET \"userbouquet.$SAT.$(echo $FAV | tr ' ' '_' | tr 'A-Z' 'a-z').tv\" ORDER BY bouquet" >> $OUTDIR/bouquets.tv
		fi
	done < "$TMPDIR/rulespt.txt"
}


log "### Iniciado em $(date)"
log "----------------------------------------"
convertdb
log "----------------------------------------"

log "### Check exclude rule"
checkexclude
log "----------------------------------------"

echo "#NAME User - bouquets (TV)" > $OUTDIR/bouquets.radio
echo "#SERVICE 1:7:2:0:0:0:0:0:0:0:FROM BOUQUET \"userbouquet.favourites.radio" ORDER BY bouquet\" >> $OUTDIR/bouquets.radio

echo "#NAME User - bouquets (TV)" > $OUTDIR/bouquets.tv
echo "#SERVICE 1:7:1:0:0:0:0:0:0:0:FROM BOUQUET \"userbouquet.favourites.tv\" ORDER BY bouquet" >> $OUTDIR/bouquets.tv

for SAT in $SATS; do
	log ""
	log "------------- Satellite $SAT -------------"
	genfavall $SAT
	rules $SAT
	log "----------------------------------------"
done

log "### Finalizado em $(date)"
