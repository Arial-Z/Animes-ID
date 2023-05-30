#!/bin/bash

SCRIPT_FOLDER=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

if [ ! -d "$SCRIPT_FOLDER/tmp" ]
then
	mkdir "$SCRIPT_FOLDER/tmp"
else
    rm "$SCRIPT_FOLDER/tmp"/*
fi
if [ ! -d "$SCRIPT_FOLDER/mapping-needed" ]
then
	mkdir "$SCRIPT_FOLDER/mapping-needed"
else
    rm "$SCRIPT_FOLDER/mapping-needed"/*
fi
if [ -f "$SCRIPT_FOLDER/override/auto-override-animes-id.tsv" ]
then
	if [[ $(find "$SCRIPT_FOLDER/override/auto-override-animes-id.tsv" -mtime +7 -print) ]]
	then
		rm "$SCRIPT_FOLDER/override/auto-override-animes-id.tsv"
		:> "$SCRIPT_FOLDER/override/auto-override-animes-id.tsv"
	fi
else
	:> "$SCRIPT_FOLDER/override/auto-override-animes-id.tsv"
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
		eval local "$ATTRIBUTES"
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
		if ! awk -F"\t" '{print $4}' "$SCRIPT_FOLDER/tmp/list-animes.tsv" | grep -q -w "$anidbid"
		then
			get-mal-anilist-id
			printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$tvdbid" "$defaulttvdbseason" "$episodeoffset" "$anidbid" "$malid" "$anilistid" >> "$SCRIPT_FOLDER/tmp/list-animes.tsv"
		fi
	fi
}
function id-from-imdb () {
	if [[ -n "$imdbid" ]] && [[ $imdbid != "unknown" ]]
	then
		missing-multiples-movies
		if ! awk -F"\t" '{print $1}' "$SCRIPT_FOLDER/tmp/list-movies.tsv" | grep -q -w "$imdbid"
		then
			get-mal-anilist-id
			printf "%s\t%s\t%s\t%s\n" "$imdbid" "$anidbid" "$malid" "$anilistid" >> "$SCRIPT_FOLDER/tmp/list-movies.tsv"
		fi
	fi
}
function missing-multiples-movies () {
    if  echo "$imdbid" | grep -q ,
    then
        columns_total_mumbers=$(echo "$imdbid" | awk -F"," '{print NF}')
        columns_mumbers=1
        missing_movies=""
        while [ $columns_mumbers -le "$columns_total_mumbers" ];
        do
            current_movie=$(echo "$imdbid" | awk -v columns_mumbers=$columns_mumbers -F"," '{print $columns_mumbers}')
            if ! awk -F"\t" '{print $1}' "$SCRIPT_FOLDER/override/override-imdb.tsv" | grep -q -w "$current_movie"
            then
                missing_movies=$(printf "%s," "$missing_movies$current_movie" )
            fi
        ((columns_mumbers++))
        done
        if [[ -n "$missing_movies" ]]
        then
            printf "Anidb : %s missing multiples movies %s\n" "$anidbid" "$missing_movies" >> "$SCRIPT_FOLDER/mapping-needed/missing-multiples-movies.txt"
        fi
        imdbid=$(echo "$imdbid" | awk -F"," '{print $1}')
    fi
}
function get-mal-anilist-id () {
	malid=""
	anilistid=""
	if awk -F"\t" '{print $1}' "$SCRIPT_FOLDER/tmp/override-animes-id.tsv" | grep -q -w "$anidbid"
	then
		line_anidb=$(awk -F"\t" '{print $1}' "$SCRIPT_FOLDER/tmp/override-animes-id.tsv" | grep -w -n "$anidbid" | cut -d : -f 1)
		malid=$(sed -n "${line_anidb}p" "$SCRIPT_FOLDER/tmp/override-animes-id.tsv" | awk -F"\t" '{print $2}')
		anilistid=$(sed -n "${line_anidb}p" "$SCRIPT_FOLDER/tmp/override-animes-id.tsv" | awk -F"\t" '{print $3}')
	else
		line=$(grep -w -n "https://anidb.net/anime/$anidbid"  "$SCRIPT_FOLDER/tmp/anime-offline-database.tsv" | cut -d : -f 1)
		if [[ -n "$line" ]]
		then
			malid=$(awk -v line="$line" -F"\t" 'NR==line' "$SCRIPT_FOLDER/tmp/anime-offline-database.tsv" | grep -oP "(?<=https:\/\/myanimelist.net\/anime\/)(\d+)")
			if [[ -z "$malid" ]]
			then
				printf "Missing MAL id for Anidb : %s fix needed\n" "$anidbid" >> "$SCRIPT_FOLDER/mapping-needed/missing-mal.txt"
			fi
			anilistid=$(awk -v line="$line" -F"\t" 'NR==line' "$SCRIPT_FOLDER/tmp/anime-offline-database.tsv" | grep -oP "(?<=https:\/\/anilist.co\/anime\/)(\d+)")
			if [[ -z "$anilistid" ]] && [[ -n "$malid" ]]
			then
				curl -s 'https://graphql.anilist.co/' \
				-X POST \
				-H 'content-type: application/json' \
				--data '{ "query": "{ Media(type: ANIME, idMal: '"$malid"') { id startDate } }" }' > "$SCRIPT_FOLDER/tmp/anilist-infos.json" -D "$SCRIPT_FOLDER/tmp/anilist-limit-rate.txt"
				rate_limit=0
				rate_limit=$(grep -oP '(?<=x-ratelimit-remaining: )[0-9]+' "$SCRIPT_FOLDER/tmp/anilist-limit-rate.txt")
				if [[ rate_limit -lt 3 ]]
				then
					printf "%s - Anilist API limit reached watiting 30s" "$(date +%H:%M:%S)" | tee -a "$LOG"
					sleep 30
				else
					sleep 0.7
					printf "%s\t\t - Done\n" "$(date +%H:%M:%S)" | tee -a "$LOG"
				fi
				anilistid=$(jq '.data.Media.id' -r "$SCRIPT_FOLDER/tmp/anilist-infos.json")
				if [[ -n "$anilistid" ]]
				then
					printf "%s\t%s\t%s\n" "$anidbid" "$malid" "$anilistid" >> "$SCRIPT_FOLDER/override/auto-override-animes-id.tsv"
				else
					printf "Missing Anilist id for Anidb : %s fix needed\n" "$anidbid" >> "$SCRIPT_FOLDER/mapping-needed/missing-anilist.txt"
				fi
			fi
		else
			printf "Anidb : %s missing from manami-project fix needed\n" "$anidbid" >> "$SCRIPT_FOLDER/mapping-needed/missing-anidb.txt"
		fi
	fi
}

wget -O "$SCRIPT_FOLDER/tmp/anime-list-master.xml" "https://raw.githubusercontent.com/Anime-Lists/anime-lists/master/anime-list-master.xml"
wget -O "$SCRIPT_FOLDER/tmp/anime-offline-database.json" "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json"

tail -n +2 "$SCRIPT_FOLDER/override/override-animes-id.tsv" > "$SCRIPT_FOLDER/tmp/override-animes-id.tsv"
cat "$SCRIPT_FOLDER/override/auto-override-animes-id.tsv" > "$SCRIPT_FOLDER/tmp/override-animes-id.tsv"
tail -n +2 "$SCRIPT_FOLDER/override/override-tvdb.tsv" > "$SCRIPT_FOLDER/tmp/list-animes.tsv"
tail -n +2 "$SCRIPT_FOLDER/override/override-imdb.tsv" > "$SCRIPT_FOLDER/tmp/list-movies.tsv"

jq ".data[].sources| @tsv" -r "$SCRIPT_FOLDER/tmp/anime-offline-database.json" > "$SCRIPT_FOLDER/tmp/anime-offline-database.tsv"

while read-dom
do
	parse-dom
done < "$SCRIPT_FOLDER/tmp/anime-list-master.xml"

< "$SCRIPT_FOLDER/tmp/list-animes.tsv" jq -s  --slurp --raw-input --raw-output 'split("\n") | .[0:-1] | map(split("\t")) |
	map({"tvdb_id": .[0],
	"tvdb_season": .[1],
	"tvdb_epoffset": .[2],
	"anidb_id": .[3],
	"mal_id": .[4],
	"anilist_id": .[5]})' > "$SCRIPT_FOLDER/list-animes-id.json"

< "$SCRIPT_FOLDER/tmp/list-movies.tsv" jq -s  --slurp --raw-input --raw-output 'split("\n") | .[0:-1] | map(split("\t")) |
	map({"imdb_id": .[0],
	"anidb_id": .[1],
	"mal_id": .[2],
	"anilist_id": .[3]})' > "$SCRIPT_FOLDER/list-movies-id.json"
