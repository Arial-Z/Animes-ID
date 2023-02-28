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
		id-from-tvdb
		id-from-imdb
		malid=""
		anilistid=""
	fi
}
function id-from-tvdb () {
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
}
function id-from-imdb () {
	if [[ -n "$imdbid" ]] && [[ $imdbid != "unknown" ]]
	then
		missing-multiples-movies
		if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/list-movies-id.tsv | grep -w $imdbid
		then
			get-mal-anilist-id
			printf "$imdbid\t$anidbid\t$malid\t$anilistid\n" >> $SCRIPT_FOLDER/tmp/list-movies-id.tsv
		fi
	fi
}
function missing-multiples-movies () {
    if  echo $imdbid | grep ,
    then
        columns_total_mumbers=$(echo "$imdbid" | awk -F"," '{print NF}')
        columns_mumbers=1
        missing_movies=""
        while [ $columns_mumbers -le $columns_total_mumbers ];
        do
            current_movie=$(echo "$imdbid" | awk -v columns_mumbers=$columns_mumbers -F"," '{print $columns_mumbers}')
            if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/override-movies-id.tsv | grep -w $current_movie
            then
                missing_movies=$(printf "$missing_movies$current_movie," )
            fi
        ((columns_mumbers++))
        done
        if [[ -n "$missing_movies" ]]
        then
            printf "Anidb : $anidbid missing multiples movies $missing_movies\n" >> $SCRIPT_FOLDER/mapping-needed/missing-multiples-movies.txt
        fi
        imdbid=$(echo "$imdbid" | awk -F"," '{print $1}')
    fi
}
function get-mal-anilist-id () {
	if awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/override-animes-id.tsv | grep -w $anidbid
	then
		line_anidb=$(awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/override-animes-id.tsv | grep -w -n $anidbid | cut -d : -f 1)
		malid=$(sed -n "${line_anidb}p" $SCRIPT_FOLDER/tmp/override-animes-id.tsv | awk -F"\t" '{print $2}')
		anilistid=$(sed -n "${line_anidb}p" $SCRIPT_FOLDER/tmp/override-animes-id.tsv | awk -F"\t" '{print $3}')
	else
		line=$(grep -w -n "https://anidb.net/anime/$anidbid"  $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | cut -d : -f 1)
		if [[ -n "$line" ]]
		then
			malid=$(awk -v line=$line -F"\t" 'NR==line' $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | grep -oP "(?<=https:\/\/myanimelist.net\/anime\/)(\d+)")
			if [[ -n "$malid" ]]
			then
				anilistid=$(awk -v line=$line -F"\t" 'NR==line' $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | grep -oP "(?<=https:\/\/anilist.co\/anime\/)(\d+)")
				if [[ -z "$anilistid" ]]
				then
					curl 'https://graphql.anilist.co/' \
					-X POST \
					-H 'content-type: application/json' \
					--data '{ "query": "{ Media(idMal: '"$malid"') { id startDate { day month year } } }" }' > $SCRIPT_FOLDER/tmp/anilist-infos.json
					sleep 0.7s
					curl "https://api.jikan.moe/v4/anime/$malid" > $SCRIPT_FOLDER/tmp/mal-infos.json
					sleep 0.7s
					mal_start_date=$(jq '.data.aired.prop.from| [.year, .month, .day] | @tsv' -r $SCRIPT_FOLDER/tmp/mal-infos.json | sed -r 's:\t:/:g')
					anilist_start_date=$(jq '.data.Media.startDate| [.year, .month, .day] | @tsv' -r $SCRIPT_FOLDER/tmp/anilist-infos.json | sed -r 's:\t:/:g')
					if [[ $mal_start_date == $anilist_start_date ]]
					then
						anilistid=$(jq '.data.Media.id' -r $SCRIPT_FOLDER/tmp/anilist-infos.json)
						printf "$anidbid\t$malid\t$anilistid\n" >> $SCRIPT_FOLDER/override-animes-id.tsv
					else
						printf "Missing Anilist id for Anidb : $anidbid fix needed\n" >> $SCRIPT_FOLDER/mapping-needed/missing-anilist.txt
					fi
				fi
			else
				printf "Missing MAL id for Anidb : $anidbid fix needed\n" >> $SCRIPT_FOLDER/mapping-needed/missing-mal.txt
			fi
		else
			printf "Anidb : $anidbid missing from manami-project fix needed\n" >> $SCRIPT_FOLDER/mapping-needed/missing-anidb.txt
		fi
	fi
}

wget -O $SCRIPT_FOLDER/tmp/anime-list-master.xml "https://raw.githubusercontent.com/Anime-Lists/anime-lists/master/anime-list-master.xml"
wget -O $SCRIPT_FOLDER/tmp/anime-offline-database.json "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json"

tail -n +2 $SCRIPT_FOLDER/override-animes-id.tsv > $SCRIPT_FOLDER/tmp/override-animes-id.tsv
tail -n +2 $SCRIPT_FOLDER/override-movies-id.tsv > $SCRIPT_FOLDER/tmp/list-movies-id.tsv

jq ".data[].sources| @tsv" -r $SCRIPT_FOLDER/tmp/anime-offline-database.json > $SCRIPT_FOLDER/tmp/anime-offline-database.tsv

while read-dom
do
	parse-dom
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
