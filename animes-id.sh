#!/bin/bash

SCRIPT_FOLDER=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

if [ ! -d $SCRIPT_FOLDER/tmp ]
then
	mkdir $SCRIPT_FOLDER/tmp
else
    rm $SCRIPT_FOLDER/tmp/*
fi
if [ ! -d $SCRIPT_FOLDER/mapping-needed ]
then
	mkdir $SCRIPT_FOLDER/mapping-needed
else
    rm $SCRIPT_FOLDER/mapping-needed/*
fi

function read-dom () {
	local IFS=\>
	read -d \< ENTITY CONTENT
	local RET=$?
	TAG_NAME=${ENTITY%% *}
	ATTRIBUTES=${ENTITY#* }
	return $RET
}
function parse-dom () {
	if [[ $TAG_NAME = "anime" ]]
	then
		eval local $ATTRIBUTES
		if [[ -n "$tvdbid" ]] && [ "$tvdbid" -eq "$tvdbid" ] 2>/dev/null
		then
			if [[ "$defaulttvdbseason" == a ]]
			then
				defaulttvdbseason=-1
			fi
			if [[ -z "$episodeoffset" ]]
			then
				episodeoffset=0
			fi
			get-mal-anilist-id
			printf "$tvdbid\t$defaulttvdbseason\t$episodeoffset\t$anidbid\t$malid\t$anilistid\n" >> $SCRIPT_FOLDER/tmp/list-animes-id.tsv
		fi
	fi
}
function id-from-tvdb () {
	if [[ -n "$tvdb_id" ]] && [ "$tvdb_id" -eq "$tvdb_id" ] 2>/dev/null
	then
		if [[ "$defaulttvdbseason" == a ]]
		then
			defaulttvdbseason=-1
		fi
		if [[ -z "$episodeoffset" ]]
		then
			episodeoffset=0
		fi
		get-mal-anilist-id
		printf "$tvdb_id\t$defaulttvdbseason\t$episodeoffset\t$anidb_id\t$mal_id\t$anilist_id\n" >> $SCRIPT_FOLDER/tmp/list-animes-id.tsv
	fi
}
function id-from-imdb () {
	if [[ -n "$imdb_id" ]] && [[ $imdb_id != "unknown" ]]
	then
		missing-multiples-movies
		if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/list-movies-id.tsv | grep -w $imdb_id
		then
			get-mal-anilist-id
			printf "$imdb_id\t$anidb_id\t$mal_id\t$anilist_id\n" >> $SCRIPT_FOLDER/tmp/list-movies-id.tsv
		fi
	fi
}
function get-mal-anilist-id () {
	if awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/override-animes-id.tsv | grep -w $anidb_id
	then
		echo "anidb found for tvdb : $tvdb_id"
		line_anidb=$(awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/override-animes-id.tsv | grep -w -n $anidb_id | cut -d : -f 1)
		mal_id=$(sed -n "${line_anidb}p" $SCRIPT_FOLDER/tmp/override-animes-id.tsv | awk -F"\t" '{print $2}')
		anilist_id=$(sed -n "${line_anidb}p" $SCRIPT_FOLDER/tmp/override-animes-id.tsv | awk -F"\t" '{print $3}')
	else
		line=$(grep -w -n "https://anidb.net/anime/$anidb_id"  $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | cut -d : -f 1)
		if [[ -n "$line" ]]
		then
			echo "anidb found for tvdb : $tvdb_id"
			mal_id=$(awk -v line=$line -F"\t" 'NR==line' $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | grep -oP "(?<=https:\/\/myanimelist.net\/anime\/)(\d+)")
			if [[ -n "$anilist_id" ]]
			then
				anilist_id=$(awk -v line=$line -F"\t" 'NR==line' $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | grep -oP "(?<=https:\/\/anilist.co\/anime\/)(\d+)")
				if [[ -z "$anilist_id" ]]
				then
					curl 'https://graphql.anilist.co/' \
					-X POST \
					-H 'content-type: application/json' \
					--data '{ "query": "{ Media(idMal: '"$mal_id"') { id startDate { day month year } } }" }' > $SCRIPT_FOLDER/tmp/anilist-infos.json
					curl "https://api.jikan.moe/v4/anime/$mal_id" > $SCRIPT_FOLDER/tmp/mal-infos.json
					mal_start_date=$(jq '.data.aired.prop.from' -r $SCRIPT_FOLDER/tmp/mal-infos.json)
					anilist_start_date=$(jq '.data.Media.startDate' -r $SCRIPT_FOLDER/tmp/anilist-infos.json)
					if [[ mal_start_date == anilist_start_date ]]
					then
						anilist_id=$(jq '.data.Media.id' -r $SCRIPT_FOLDER/tmp/anilist-infos.json)
						printf "$anidb_id\t$mal_id\t$anilist_id\n" >> $SCRIPT_FOLDER/override-animes-id.tsv
					else
						printf "Missing Anilist id for Anidb : $anidb_id fix needed\n" >> $SCRIPT_FOLDER/mapping-needed/missing-anilist.txt
					fi
				fi
			else
				printf "Missing MAL id for Anidb : $anidb_id fix needed\n" >> $SCRIPT_FOLDER/mapping-needed/missing-mal.txt
			fi
		else
			echo "anidb missing for tvdb : $tvdb_id"
			printf "Anidb : $anidb_id missing from manami-project fix needed\n" >> $SCRIPT_FOLDER/mapping-needed/missing-anidb.txt
		fi
	fi
}
function missing-multiples-movies () {
    if  echo $imdb_id | grep ,
    then
        columns_total_mumbers=$(echo "$imdb_id" | awk -F"," '{print NF}')
        columns_mumbers=1
        missing_movies=""
        while [ $columns_mumbers -le $columns_total_mumbers ];
        do
            current_movie=$(echo "$imdb_id" | awk -v columns_mumbers=$columns_mumbers -F"," '{print $columns_mumbers}')
            if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/override-movies.tsv | grep -w $current_movie
            then
                missing_movies=$(printf "$missing_movies$current_movie," )
            fi
        ((columns_mumbers++))
        done
        if [[ -n "$missing_movies" ]]
        then
            printf "Anidb : $anidb_id missing multiples movies $missing_movies\n" >> $SCRIPT_FOLDER/mapping-needed/missing-multiples-movies.txt
        fi
        imdb_id=$(echo "$imdb_id" | awk -F"," '{print $1}')
    fi
}

wget -O $SCRIPT_FOLDER/tmp/anime-list-master.xml "https://raw.githubusercontent.com/Anime-Lists/anime-lists/master/anime-list-master.xml"
wget -O $SCRIPT_FOLDER/tmp/anime-offline-database.json "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json"

tail -n +2 $SCRIPT_FOLDER/override-movies-id.tsv > $SCRIPT_FOLDER/tmp/override-movies-id.tsv
tail -n +2 $SCRIPT_FOLDER/override-animes-id.tsv > $SCRIPT_FOLDER/tmp/override-animes-id.tsv

jq ".data[].sources| @tsv" -r $SCRIPT_FOLDER/tmp/anime-offline-database.json > $SCRIPT_FOLDER/tmp/anime-offline-database.tsv

while read-dom
do
	parse-dom
	echo "oui"
done < $SCRIPT_FOLDER/tmp/anime-list-master.xml

cat $SCRIPT_FOLDER/tmp/list-animes-id.tsv | jq -s  --slurp --raw-input --raw-output 'split("\n") | .[0:-1] | map(split("\t")) |
	map({"tvdb_id": .[0],
	"tvdb_season": .[1],
	"tvdb_epoffset": .[2],
	"anidb_id": .[3],
	"mal_id": .[4],
	"anilist_id": .[5]})' > $SCRIPT_FOLDER/list-animes-id.json

cat $SCRIPT_FOLDER/tmp/list-movies-id.tsv | jq -s  --slurp --raw-input --raw-output 'split("\n") | .[0:-1] | map(split("\t")) |
	map({"imdb_id": .[0],
	"anidb_id": .[1],
	"mal_id": .[2],
	"anilist_id": .[3]})' > $SCRIPT_FOLDER/list-movies-id.json
